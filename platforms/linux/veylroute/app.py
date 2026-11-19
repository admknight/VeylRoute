"""VeylRoute Linux CLI: Tor TransPort / nftables guarded session.

IMPORTANT: Experimental Linux runtime. No production leak-free claim.
No existing route, resolv.conf, NetworkManager or firewall table is rewritten.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import pwd
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from . import __version__
from . import control, model

RUN = Path(model.RUN_DIR)
DATA = Path(model.DATA_DIR)
STATE = RUN / "session.json"
STATUS = RUN / "status.json"
PENDING = RUN / "pending.json"
CANCEL = RUN / "cancel"
LOCK = RUN / "lock"
TORRC = RUN / "torrc"
TOR_LOG = RUN / "tor.log"
BASELINE = RUN / "baseline.json"
LAST_NYM = RUN / "last-newnym"


class VeylRouteError(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def atomic_json(path: Path, data: dict, public: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp-" + str(os.getpid()))
    try:
        with temp.open("w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, 0o644 if public else 0o600)
        os.replace(temp, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            temp.unlink()


def read_json(path: Path) -> dict:
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(result, dict):
            raise ValueError("not an object")
        return result
    except FileNotFoundError:
        return {}
    except (ValueError, OSError) as ex:
        raise VeylRouteError(f"Invalid state {path.name}: {ex}") from ex


def root_only() -> None:
    if os.geteuid() != 0:
        raise VeylRouteError("Administrator privileges required. Use sudo veylroute <command> or the GUI elevation prompt.")


def run(*args: str, input_text: str | None = None, check: bool = True, timeout: int = 20) -> subprocess.CompletedProcess:
    try:
        p = subprocess.run(list(args), input=input_text, text=True, capture_output=True,
                           timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as ex:
        raise VeylRouteError(f"Required command unavailable or timed out: {args[0]}") from ex
    if check and p.returncode != 0:
        # Never echo potentially private command arguments; nft errors may
        # contain addresses supplied by user in future revisions.
        raise VeylRouteError(f"Command {args[0]} failed: {p.stderr.strip()[:400]}")
    return p


def init_run_dir() -> None:
    root_only()
    RUN.mkdir(mode=0o755, parents=True, exist_ok=True)
    os.chmod(RUN, 0o755)


@contextlib.contextmanager
def exclusive():
    init_run_dir()
    with LOCK.open("a+") as handle:
        os.chmod(LOCK, 0o600)
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def account() -> pwd.struct_passwd:
    try:
        info = pwd.getpwnam(model.TOR_USER)
    except KeyError as ex:
        raise VeylRouteError("Dedicated tor account missing; run sudo veylroute prepare") from ex
    if info.pw_uid == 0:
        raise VeylRouteError("Refusing to run Tor as root")
    return info


def prepare() -> dict:
    """Explicit opt-in: create dedicated local user and Tor state directory."""
    root_only()
    try:
        info = account()
    except VeylRouteError:
        if pwd.getpwnam("root").pw_uid != 0:
            raise VeylRouteError("System passwd database unavailable")
        tool = shutil.which("useradd") or "/usr/sbin/useradd"
        run(tool, "--system", "--user-group", "--home-dir", str(DATA.parent),
            "--shell", "/usr/sbin/nologin", model.TOR_USER)
        info = account()
    DATA.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chown(DATA.parent, info.pw_uid, info.pw_gid)
    os.chown(DATA, info.pw_uid, info.pw_gid)
    os.chmod(DATA.parent, 0o700)
    os.chmod(DATA, 0o700)
    init_run_dir()
    return {"status": "prepared", "account": model.TOR_USER, "tor_uid": info.pw_uid}


def nft_tables() -> str:
    return run("nft", "list", "tables").stdout


def has_guard(tables: str | None = None) -> bool:
    return model.guard_present(nft_tables() if tables is None else tables)


def has_nat(tables: str | None = None) -> bool:
    return model.nat_present(nft_tables() if tables is None else tables)


def check_tools(options: model.Options) -> dict:
    options.validate()
    tools = {name: shutil.which(name) for name in ("tor", "nft", "ip")}
    if any(x is None for x in tools.values()):
        raise VeylRouteError("Missing one of Tor, nftables or iproute2; install distro packages first")
    if options.bridges and not (Path("/usr/bin/obfs4proxy").is_file() or Path("/usr/bin/lyrebird").is_file()):
        raise VeylRouteError("obfs4 bridges configured but neither obfs4proxy nor lyrebird is installed")
    info = account()
    return {"tor_uid": info.pw_uid, "tor_gid": info.pw_gid, "tor_binary": tools["tor"], "utilities": tools}


def bridge_file(path: str) -> tuple[str, ...]:
    if not path:
        return ()
    file = Path(path)
    if not file.is_file() or file.stat().st_size > 12000:
        raise VeylRouteError("Bridge config missing or unexpectedly large")
    # Only root reads bridge secrets. User should not place bridges in public repos.
    lines = [line.strip() for line in file.read_text(encoding="utf-8").splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    return tuple(model.validate_bridge(line) for line in lines)


def capture_snapshot() -> dict:
    """Read-only snapshot for comparison; NOT a blind restore recipe."""
    routes4 = run("ip", "-j", "-4", "route", "show", "table", "all").stdout
    routes6 = run("ip", "-j", "-6", "route", "show", "table", "all").stdout
    path = Path("/etc/resolv.conf")
    try:
        dns = path.read_bytes()
        resolver = {"path": os.path.realpath(path), "sha256": hashlib.sha256(dns).hexdigest()}
    except OSError:
        resolver = {"path": "unreadable", "sha256": None}
    return {"captured_at": now(), "ipv4_routes": json.loads(routes4),
            "ipv6_routes": json.loads(routes6), "dns_state": resolver}


def process_start_ticks(pid: int) -> int | None:
    """Linux /proc field 22: prevents PID reuse from matching old state."""
    try:
        data = Path(f"/proc/{pid}/stat").read_text()
        return int(data.rsplit(") ", 1)[1].split()[19])
    except (OSError, ValueError, IndexError):
        return None


def pid_matches(pid: int, expected_ticks: int | None = None) -> bool:
    if not isinstance(pid, int) or pid < 2:
        return False
    try:
        node = Path(f"/proc/{pid}")
        if not node.is_dir() or node.stat().st_uid != account().pw_uid:
            return False
        # Tor may change the process title; bind to the dedicated account,
        # executable AND (when saved) the original kernel start time.
        executable = (node / "exe").resolve().name
        if executable != "tor":
            return False
        if expected_ticks is not None and process_start_ticks(pid) != expected_ticks:
            return False
        return True
    except (OSError, VeylRouteError):
        return False


def wait_terminated(pid: int, seconds: int = 10, ticks: int | None = None) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if not pid_matches(pid, ticks):
            return True
        time.sleep(0.15)
    return not pid_matches(pid, ticks)


def kill_managed_tor(pid: int, ticks: int | None = None) -> None:
    if not pid_matches(pid, ticks):
        return
    os.kill(pid, signal.SIGTERM)
    if wait_terminated(pid, ticks=ticks):
        return
    if pid_matches(pid, ticks):
        os.kill(pid, signal.SIGKILL)
    if not wait_terminated(pid, 3, ticks=ticks):
        raise VeylRouteError("Managed Tor did not terminate; firewall guard retained for safety")


def rollback_tables() -> list[str]:
    tables = nft_tables()
    commands = []
    # Each table is named exactly for this application; never 'flush ruleset'.
    if model.nat_present(tables):
        commands.append(f"delete table ip {model.NAT_TABLE}")
    if model.guard_present(tables):
        commands.append(f"delete table inet {model.GUARD_TABLE}")
    if commands:
        run("nft", "-f", "-", input_text="\n".join(commands) + "\n")
    if has_nat() or has_guard():
        raise VeylRouteError("Application nft tables remain after cleanup")
    return commands


def cleanup_control_files() -> None:
    """Remove stale Tor runtime socket/PID file only after managed Tor exited."""
    socket_path = DATA / "control.socket"
    try:
        if stat.S_ISSOCK(socket_path.lstat().st_mode):
            socket_path.unlink()
    except FileNotFoundError:
        pass
    pid_file = DATA / "tor.pid"
    if pid_file.is_symlink():
        return
    try:
        pid = int(pid_file.read_text().strip())
    except (OSError, ValueError):
        return
    if not pid_matches(pid) and not Path(f"/proc/{pid}").exists():
        with contextlib.suppress(FileNotFoundError):
            pid_file.unlink()


def emit_summary(phase: str, **details) -> None:
    payload = {"platform": "linux", "version": __version__, "phase": phase, "at": now(),
               "privacy_verified": False, **details}
    atomic_json(STATUS, payload, public=True)


def is_port_free(port: int, udp: bool = False) -> bool:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM if udp else socket.SOCK_STREAM)
        with sock:
            sock.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False


def preflight(options: model.Options) -> dict:
    root_only()
    info = check_tools(options)
    if not Path("/proc").is_dir():
        raise VeylRouteError("Linux /proc must be mounted")
    if has_guard() or has_nat():
        raise VeylRouteError("Previous VeylRoute nft rules exist; recover before connecting")
    if STATE.exists() or PENDING.exists():
        raise VeylRouteError("Old or active session state found; stop/recover before connecting")
    for port, udp in ((model.TOR_TRANS_PORT, False), (model.TOR_SOCKS_PORT, False),
                      (model.TOR_DNS_PORT, True)):
        if not is_port_free(port, udp=udp):
            raise VeylRouteError(f"Local Tor port {port} is already occupied")
    return {"preflight": "ready-for-start", "tor_uid": info["tor_uid"],
            "exit_country": options.validate().exit_country,
            "bridge_count": len(options.bridges),
            "dns_model": "Tor DNSPort / transparent nft redirect",
            "network_changes": "none during preflight", "privacy_verified": False}


def drop_identity(uid: int, gid: int) -> None:
    os.setgroups([])
    os.setgid(gid)
    os.setuid(uid)


def wait_bootstrap(proc: subprocess.Popen, timeout: int) -> None:
    until = time.monotonic() + timeout
    last_seen = ""
    while time.monotonic() < until:
        if CANCEL.is_file():
            raise VeylRouteError("Connection cancelled by user")
        if proc.poll() is not None:
            raise VeylRouteError("Tor exited before 100% bootstrap")
        if TOR_LOG.exists():
            with TOR_LOG.open("rb") as f:
                f.seek(max(0, f.seek(0, os.SEEK_END) - 20000))
                log = f.read().decode("utf-8", "replace")
            found = re.findall(r"Bootstrapped (\d+)%", log)
            if found:
                current = found[-1]
                if current != last_seen:
                    last_seen = current
                    emit_summary("connecting", bootstrap=int(current))
                if "100" in found:
                    return
        time.sleep(0.4)
    raise VeylRouteError(f"Tor bootstrap timeout after {timeout} seconds (last {last_seen or 'unknown'}%)")


def connect(options: model.Options) -> dict:
    root_only()
    with exclusive():
        info = preflight(options)
        uid, gid = info["tor_uid"], account().pw_gid
        snapshot = capture_snapshot()
        atomic_json(BASELINE, snapshot)
        # Mark the operation before starting any subprocess, so cancellation
        # and recovery can detect an interrupted attempt.
        atomic_json(PENDING, {"phase": "starting", "at": now(), "pid": None})
        with contextlib.suppress(FileNotFoundError):
            CANCEL.unlink()
        emit_summary("connecting", bootstrap=0)
        opts = options.validate()
        config = model.build_torrc(opts)
        if opts.bridges:
            transport = "/usr/bin/obfs4proxy" if Path("/usr/bin/obfs4proxy").is_file() else "/usr/bin/lyrebird"
            config = config.replace("/usr/bin/obfs4proxy", transport)
        TORRC.write_text(config, encoding="utf-8")
        os.chown(TORRC, 0, gid)
        os.chmod(TORRC, 0o640)
        proc = None
        try:
            # Tor config is verified as the unprivileged Tor account BEFORE
            # installing the guard. The verification itself has no networking.
            verify = subprocess.run(["tor", "--verify-config", "-f", str(TORRC)],
                                    capture_output=True, timeout=20, text=True,
                                    preexec_fn=lambda: drop_identity(uid, gid))
            if verify.returncode:
                raise VeylRouteError("Tor configuration validation failed (see local diagnostic log)")
            if CANCEL.exists():
                raise VeylRouteError("Connection cancelled before startup")
            # Commit the NAT redirect and fail-closed filter ATOMICALLY before
            # Tor bootstrap, so other applications cannot transmit directly
            # throughout bootstrap (including a stalled 240-second attempt).
            run("nft", "-f", "-", input_text=model.build_nft_plan(uid))
            if not has_guard() or not has_nat():
                raise VeylRouteError("Firewall transaction did not install both VeylRoute tables")
            emit_summary("connecting", bootstrap=0, guard_present=True)
            with TOR_LOG.open("wb") as log:
                os.chmod(TOR_LOG, 0o600)
                proc = subprocess.Popen(["tor", "-f", str(TORRC)], stdin=subprocess.DEVNULL,
                                        stdout=log, stderr=subprocess.STDOUT,
                                        cwd="/", start_new_session=True,
                                        preexec_fn=lambda: drop_identity(uid, gid))
            atomic_json(PENDING, {"phase": "bootstrap", "at": now(), "pid": proc.pid,
                                  "start_ticks": process_start_ticks(proc.pid)})
            wait_bootstrap(proc, model.BOOTSTRAP_TIMEOUT)
            if CANCEL.exists():
                raise VeylRouteError("Connection cancelled during bootstrap")
            state = {"pid": proc.pid, "start_ticks": process_start_ticks(proc.pid),
                     "at": now(), "mode": "systemwide",
                     "exit_country": opts.exit_country, "tor_uid": uid}
            atomic_json(STATE, state)
            emit_summary("connected-unverified", mode="systemwide", tor_pid=proc.pid,
                         exit_country=opts.exit_country, guard_present=True)
            with contextlib.suppress(FileNotFoundError):
                PENDING.unlink()
            return {"result": "connected-unverified", "pid": proc.pid,
                    "guard": "active", "traffic_verification": "not-run"}
        except (Exception, KeyboardInterrupt) as problem:
            # An expected startup failure or user cancel must restore normal
            # networking. If restoration itself fails, LEAVE the firewall in
            # fail-closed state, clearly mark recovery-required, and stop.
            errors = []
            if proc is not None:
                try:
                    kill_managed_tor(proc.pid, process_start_ticks(proc.pid))
                except Exception as ex:
                    errors.append("Managed Tor cleanup: " + str(ex))
            if not errors:
                try:
                    rollback_tables()
                except Exception as ex:
                    errors.append("Firewall rollback: " + str(ex))
            if errors:
                emit_summary("recovery-required", error="; ".join(errors))
                raise VeylRouteError("Start failed and safe recovery is required: " +
                                     "; ".join(errors)) from problem
            for path in (PENDING, CANCEL, TORRC, STATE):
                with contextlib.suppress(FileNotFoundError):
                    path.unlink()
            emit_summary("disconnected", error="Start failed or was cancelled; guard restored")
            raise


def cancel() -> dict:
    """Cooperative out-of-band cancellation; does not acquire start lock."""
    root_only()
    if not PENDING.exists():
        raise VeylRouteError("No pending connection to cancel")
    # May be called while connect holds its lock, so do not hold that lock.
    fd = os.open(CANCEL, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600) if not CANCEL.exists() else None
    if fd is not None:
        os.close(fd)
    return {"cancel": "requested", "message": "Await bootstrap worker rollback"}


def disconnect() -> dict:
    root_only()
    with exclusive():
        # Prevent accidental stop while a separate start operation is pending.
        if PENDING.exists():
            raise VeylRouteError("Connection still starting. Use cancel, then recover if needed")
        state = read_json(STATE)
        pid = int(state.get("pid") or 0)
        ticks = state.get("start_ticks")
        if pid and Path(f"/proc/{pid}").is_dir() and not pid_matches(pid, ticks):
            raise VeylRouteError("Tor PID identity could not be confirmed; firewall guard retained")
        if pid and pid_matches(pid, ticks):
            kill_managed_tor(pid, ticks)  # guard remains while Tor exits
        rollback_tables()          # then remove just our own tables
        cleanup_control_files()
        before = read_json(BASELINE)
        after = capture_snapshot() if before else {}
        comparison = model.snapshot_compare(before, after) if before else {}
        for path in (STATE, PENDING, CANCEL, TORRC):
            with contextlib.suppress(FileNotFoundError):
                path.unlink()
        emit_summary("disconnected", route_dns_comparison=comparison)
        return {"result": "disconnected", "baseline_comparison": comparison,
                "note": "Other programs may independently change routes/DNS during a session."}


def recover() -> dict:
    root_only()
    with exclusive():
        # Same lifecycle, but intentionally admits stale pending.json.
        state = read_json(STATE)
        pending = read_json(PENDING)
        pid = int(state.get("pid") or pending.get("pid") or 0)
        ticks = state.get("start_ticks") or pending.get("start_ticks")
        if not pid and (DATA / "tor.pid").is_file():
            try:
                pid = int((DATA / "tor.pid").read_text().strip())
            except (OSError, ValueError):
                pass
        if pid and Path(f"/proc/{pid}").is_dir() and not pid_matches(pid, ticks):
            raise VeylRouteError("Tor PID identity uncertain; guard retained for operator review")
        if pid and pid_matches(pid, ticks):
            kill_managed_tor(pid, ticks)
        rollback_tables()
        cleanup_control_files()
        for path in (STATE, PENDING, CANCEL, TORRC):
            with contextlib.suppress(FileNotFoundError):
                path.unlink()
        emit_summary("disconnected", recovery="completed")
        return {"recovery": "completed", "network_tables": "removed"}


def status() -> dict:
    if not STATUS.is_file():
        return {"platform": "linux", "version": __version__, "phase": "not-running",
                "verification": "no session observed"}
    data = read_json(STATUS)
    if os.geteuid() == 0:
        data["guard_observed"] = has_guard()
        data["nat_observed"] = has_nat()
        sess = read_json(STATE)
        data["managed_tor_running"] = pid_matches(int(sess.get("pid") or 0), sess.get("start_ticks"))
    else:
        data["verification"] = "state-file only; use sudo veylroute health for firewall/daemon checks"
    return data


def health() -> dict:
    root_only()
    data = status()
    live = (bool(data.get("guard_observed")) and bool(data.get("nat_observed"))
            and bool(data.get("managed_tor_running")))
    data["local_safeguards"] = "active" if live else "incomplete"
    data["dns_leak_independently_tested"] = False
    data["external_tor_identity_tested"] = False
    data["overall"] = "local-controls-present" if live else "not-healthy"
    return data


def new_circuit() -> dict:
    root_only()
    with exclusive():
        info = health()
        if info["overall"] != "local-controls-present":
            raise VeylRouteError("An active, locally healthy session is required")
        now_ts = time.monotonic()
        if LAST_NYM.is_file():
            old = read_json(LAST_NYM)
            if old.get("boot_id") == Path("/proc/sys/kernel/random/boot_id").read_text().strip():
                age = now_ts - float(old.get("monotonic") or 0)
                if 0 <= age < 15:
                    raise VeylRouteError("Tor NEWNYM rate limit: please retry after 15 seconds")
        result = control.request_new_circuit(str(DATA / "control.socket"),
                                             str(DATA / "control.authcookie"))
        atomic_json(LAST_NYM, {"monotonic": now_ts,
                               "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip()})
        return {"new_circuit": "acknowledged", "message": result,
                "exit_ip_changed": "not-verified"}


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="veylroute", description="VeylRoute Linux experimental Tor controller")
    parser.add_argument("--json", action="store_true", help="Machine-readable result")
    sub = parser.add_subparsers(dest="action", required=True)
    for command in ("prepare", "preflight", "start", "cancel", "status", "health",
                    "stop", "recover", "new-circuit", "version", "gui",
                    "desktop-install", "desktop-remove", "update-check", "update-prepare",
                    "update-apply"):
        p = sub.add_parser(command)
        if command in ("preflight", "start"):
            p.add_argument("--exit-country", default="auto", help="Auto or two-letter ISO exit country")
            p.add_argument("--bridges-file", default="", help="Private obfs4 bridge config file")
        if command == "update-apply":
            p.add_argument("--receipt", required=True, help="Path to the verified downloaded update receipt")
            p.add_argument("--parent-pid", type=int, default=0, help="Wait until the GUI process exits")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = get_parser().parse_args(argv)
    try:
        if args.action == "version":
            result = {"version": __version__, "platform": "linux"}
        elif args.action == "gui":
            from .gui import main as gui_main
            return gui_main()
        elif args.action == "prepare":
            result = prepare()
        elif args.action in ("preflight", "start"):
            options = model.Options(args.exit_country, bridge_file(args.bridges_file))
            result = preflight(options) if args.action == "preflight" else connect(options)
        elif args.action == "cancel":
            result = cancel()
        elif args.action == "status":
            result = status()
        elif args.action == "health":
            result = health()
        elif args.action == "stop":
            result = disconnect()
        elif args.action == "recover":
            result = recover()
        elif args.action == "new-circuit":
            result = new_circuit()
        elif args.action in ("desktop-install", "desktop-remove"):
            if os.geteuid() == 0:
                raise VeylRouteError("Portable menu integration must run as the desktop user, not root")
            from . import desktop
            if args.action == "desktop-install":
                result = {"desktop_shortcut": str(desktop.install()), "mode": "portable"}
            else:
                result = {"desktop_shortcut_removed": desktop.remove()}
        elif args.action in ("update-check", "update-prepare", "update-apply"):
            from . import updates
            if args.action == "update-check":
                result = updates.check()
            elif args.action == "update-prepare":
                result = {"verified_receipt": str(updates.prepare(updates.check()))}
            else:
                result = {"update_result": updates.apply(Path(args.receipt), args.parent_pid)}
        else:
            raise VeylRouteError("Unsupported Linux operation")
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            for k, v in result.items():
                print(f"{k.replace('_', ' ').capitalize()}: {v}")
        return 0
    except (VeylRouteError, ValueError, OSError, subprocess.SubprocessError, control.ControlError, RuntimeError) as ex:
        if args.json:
            print(json.dumps({"error": str(ex), "status": "failed"}))
        else:
            print(f"ERROR: {ex}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
