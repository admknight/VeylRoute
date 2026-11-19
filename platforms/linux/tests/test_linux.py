"""Network-neutral Linux platform contract and lifecycle tests."""
from __future__ import annotations

import contextlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from veylroute import app, control, model

ORIGINAL_WAIT_BOOTSTRAP = app.wait_bootstrap


class ModelTests(unittest.TestCase):
    def test_nft_contract_fail_closed(self):
        rules = model.build_nft_plan(993)
        self.assertIn("table ip veylroute_nat", rules)
        self.assertIn("table inet veylroute_guard", rules)
        self.assertIn("meta skuid 993", rules)
        self.assertIn("udp dport 53 redirect to :39053", rules)
        self.assertIn("meta l4proto tcp redirect to :39040", rules)
        self.assertIn('oifname "lo" accept', rules)
        self.assertIn("counter drop", rules)
        self.assertNotIn("ct status dnat accept", rules)
        self.assertNotIn("flush ruleset", rules)
        self.assertNotIn("accept all", rules)
        self.assertEqual(rules.count("type nat hook output"), 1)
        self.assertEqual(rules.count("type filter hook output"), 1)

    def test_nft_root_uid_rejected(self):
        for uid in (0, -1, True, "0"):
            with self.subTest(uid=uid), self.assertRaises(ValueError):
                model.build_nft_plan(uid)

    def test_bridge_validation_rejects_injection_and_invalid_addresses(self):
        good = "obfs4 192.0.2.4:443 " + "A" * 40 + " cert=" + "Z" * 60 + " iat-mode=0"
        self.assertEqual(model.validate_bridge(good), "Bridge " + good)
        for bad in (good + "\nExitNodes {ru}", "obfs4 evil:80 ",
                    good.replace("192.0.2.4", "999.1.2.3"),
                    good.replace(":443", ":70000"),
                    "Bridge 127.0.0.1:443", good + " # comments", good + "\x00"):
            with self.subTest(line=bad[:35]), self.assertRaises(ValueError):
                model.validate_bridge(bad)

    def test_exit_country_validation_and_torrc(self):
        for country in ("auto", "US", "gb"):
            content = model.build_torrc(model.Options(country))
            self.assertIn("CookieAuthentication 1", content)
            self.assertIn("TransPort 127.0.0.1:39040", content)
            self.assertIn("DNSPort 127.0.0.1:39053", content)
            self.assertIn("SocksPort 127.0.0.1:39050", content)
            self.assertNotIn("Bridge ", content)
        self.assertIn("ExitNodes {us}", model.build_torrc(model.Options("US")))
        for invalid in ("Europe", "PK;ExitNodes", "US\nSocksPort", " ", "XYZ"):
            with self.assertRaises(ValueError):
                model.Options(invalid).validate()

    def test_snapshot_comparison_records_drift_without_mutation(self):
        before = {"ipv4_routes": [1], "ipv6_routes": [2], "dns_state": {"hash": 3}}
        after = dict(before, ipv6_routes=[3], captured_at="later")
        self.assertEqual(model.snapshot_compare(before, after),
                         {"ipv4_routes": True, "ipv6_routes": False, "dns_state": True})
        self.assertEqual(before["ipv6_routes"], [2])


class SafeCookieTests(unittest.TestCase):
    def test_hmac_known_python_reference(self):
        import hmac
        import hashlib
        cookie, client, server = bytes(range(32)), b"A" * 32, b"B" * 32
        s, c = control.hmac_pair(cookie, client, server)
        self.assertEqual(s, hmac.new(control.KEY_SERVER, cookie + client + server,
                                     hashlib.sha256).digest())
        self.assertEqual(c, hmac.new(control.KEY_CLIENT, cookie + client + server,
                                     hashlib.sha256).digest())
        self.assertNotEqual(s, c)
        for invalid in ((b"short", client, server), (cookie, client, b"")):
            with self.assertRaises(control.ControlError):
                control.hmac_pair(*invalid)

    def test_response_gate_rejects_failure(self):
        class Sock:
            def __init__(self, *args, **kwargs):
                self.output = b"550 Permission denied\r\n"
                self.sent = []
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def settimeout(self, secs): pass
            def connect(self, path): pass
            def sendall(self, data): self.sent.append(data)
            def recv(self, n):
                ret, self.output = self.output[:n], self.output[n:]
                return ret
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / "cookie"
            f.write_bytes(b"A" * 32)
            with patch.object(control.socket, "socket", Sock):
                with self.assertRaises(control.ControlError):
                    control.request_new_circuit("/fake", str(f))


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.root.joinpath("run").mkdir()
        self.root.joinpath("data").mkdir()
        base = self.root / "run"
        assignments = {
            "RUN": base,
            "DATA": self.root / "data",
            "STATE": base / "session.json", "STATUS": base / "status.json",
            "PENDING": base / "pending.json", "CANCEL": base / "cancel",
            "LOCK": base / "lock", "TORRC": base / "torrc",
            "TOR_LOG": base / "tor.log", "BASELINE": base / "baseline.json",
            "LAST_NYM": base / "last-newnym",
        }
        for k, v in assignments.items():
            p = patch.object(app, k, v)
            p.start(); self.addCleanup(p.stop)
        self.actions = []
        self.guard = False
        self.nat = False
        self.patches = [
            patch.object(app, "root_only"),
            patch.object(app, "exclusive", lambda: contextlib.nullcontext()),
            patch.object(app, "preflight", lambda _: {"tor_uid": 993, "preflight": "ready-for-start"}),
            patch.object(app, "account", lambda: SimpleNamespace(pw_gid=993, pw_uid=993)),
            patch.object(app, "capture_snapshot", lambda: {"ipv4_routes": [],
                                                           "ipv6_routes": [], "dns_state": {}}),
            patch.object(app.os, "chown"),
            patch.object(app.subprocess, "run", return_value=SimpleNamespace(returncode=0)),
            patch.object(app.subprocess, "Popen", return_value=SimpleNamespace(pid=12345)),
            patch.object(app, "wait_bootstrap"),
            patch.object(app, "kill_managed_tor", side_effect=lambda p, ticks=None: self.actions.append("kill")),
            patch.object(app, "has_guard", side_effect=lambda: self.guard),
            patch.object(app, "has_nat", side_effect=lambda: self.nat),
            patch.object(app, "run", side_effect=self.fake_run),
        ]
        for p in self.patches:
            p.start(); self.addCleanup(p.stop)

    def fake_run(self, *args, **kw):
        command = kw.get("input_text", "")
        if args[:3] == ("nft", "list", "tables"):
            stdout = ("table ip veylroute_nat\n" if self.nat else "") + \
                     ("table inet veylroute_guard\n" if self.guard else "")
            return SimpleNamespace(returncode=0, stdout=stdout, stderr="")
        if args[:2] == ("nft", "-f"):
            if "delete table" in command:
                self.actions.append("guard-removed")
                self.guard = self.nat = False
            elif "table ip veylroute_nat" in command:
                self.actions.append("guard-installed")
                self.guard = self.nat = True
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    def test_guards_before_tor_and_sets_verified_as_false(self):
        result = app.connect(model.Options())
        self.assertEqual(result["result"], "connected-unverified")
        self.assertTrue(self.guard)
        self.assertEqual(self.actions, ["guard-installed"])
        self.assertEqual(app.read_json(app.STATE)["pid"], 12345)
        self.assertFalse(app.read_json(app.STATUS)["privacy_verified"])
        self.assertFalse(app.PENDING.exists())
        self.assertEqual(app.TORRC.stat().st_mode & 0o777, 0o640)

    def test_bootstrap_failure_kills_then_removes_guard(self):
        with patch.object(app, "wait_bootstrap", side_effect=app.VeylRouteError("timeout")):
            with self.assertRaisesRegex(app.VeylRouteError, "timeout"):
                app.connect(model.Options())
        self.assertEqual(self.actions, ["guard-installed", "kill", "guard-removed"])
        self.assertFalse(app.STATE.exists())
        self.assertFalse(self.guard)
        self.assertEqual(app.read_json(app.STATUS)["phase"], "disconnected")

    def test_rollback_failure_preserves_fail_closed_guard(self):
        def fail_rollback():
            raise app.VeylRouteError("netlink unavailable")
        with patch.object(app, "wait_bootstrap", side_effect=app.VeylRouteError("cancelled")), \
             patch.object(app, "rollback_tables", side_effect=fail_rollback):
            with self.assertRaisesRegex(app.VeylRouteError, "safe recovery is required"):
                app.connect(model.Options())
        self.assertTrue(self.guard)
        self.assertTrue(app.PENDING.exists())
        self.assertEqual(app.read_json(app.STATUS)["phase"], "recovery-required")

    def test_recover_deletes_only_app_tables(self):
        app.atomic_json(app.PENDING, {"pid": 12345})
        self.guard = self.nat = True
        with patch.object(app, "rollback_tables", side_effect=lambda: (self.actions.append("guard-removed"))):
            result = app.recover()
        self.assertEqual(result["recovery"], "completed")
        self.assertFalse(app.PENDING.exists())
        self.assertEqual(self.actions, ["guard-removed"])

    def test_disconnect_keeps_guard_until_tor_stops(self):
        app.atomic_json(app.STATE, {"pid": 12345})
        self.guard = self.nat = True
        with patch.object(app, "pid_matches", lambda p, ticks=None: True), \
             patch.object(app, "rollback_tables", side_effect=lambda: self.actions.append("guard-removed")), \
             patch.object(app.Path, "is_dir", lambda p: True):
            app.disconnect()
        self.assertEqual(self.actions, ["kill", "guard-removed"])

    def test_cancel_interrupts_bootstrap_without_network_io(self):
        app.CANCEL.write_text("")
        proc = SimpleNamespace(poll=lambda: None)
        with self.assertRaisesRegex(app.VeylRouteError, "cancelled"):
            ORIGINAL_WAIT_BOOTSTRAP(proc, 3)

    def test_cancel_out_of_band(self):
        app.atomic_json(app.PENDING, {"pid": 12345})
        result = app.cancel()
        self.assertEqual(result["cancel"], "requested")
        self.assertTrue(app.CANCEL.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
