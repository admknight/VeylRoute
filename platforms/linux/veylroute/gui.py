"""Native Tk GUI for the Linux controller; no network privileges in GUI process."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import threading
import tkinter as tk
import webbrowser
from pathlib import Path
from tkinter import filedialog, messagebox

from . import __version__
from .app import STATUS, read_json

BG = "#091626"
SIDEBAR = "#0f2239"
CARD = "#142b47"
BORDER = "#244564"
WHITE = "#e9f5fb"
MUTED = "#9cafc5"
CYAN = "#47d4e8"
GREEN = "#5ce4ac"
RED = "#f59fa3"


class App:
    def __init__(self, root: tk.Tk):
        self.root = root
        root.title("VeylRoute - Linux Control Center")
        root.geometry("1040x700")
        root.minsize(830, 550)
        root.configure(bg=BG)
        self.busy = False
        self.current_action = ""
        self.exit_country = tk.StringVar(value="auto")
        self.bridge_path = tk.StringVar(value="")
        self.phase = tk.StringVar(value="Not connected")
        self.detail = tk.StringVar(value="No Tor network session is active.")
        self.version = tk.StringVar(value=f"VeylRoute Linux {__version__} | Experimental build")
        self._build()
        root.after(500, self.refresh)

    def panel(self, parent, padx=16, pady=13):
        p = tk.Frame(parent, bg=CARD, highlightthickness=1, highlightbackground=BORDER)
        p.pack(fill="x", padx=20, pady=7)
        return p

    def text(self, parent, text, size=11, color=WHITE, bold=False, **kwargs):
        f = ("DejaVu Sans", size, "bold" if bold else "normal")
        w = tk.Label(parent, text=text, font=f, fg=color, bg=parent.cget("bg"),
                     wraplength=780, justify="left", anchor="w", **kwargs)
        w.pack(anchor="w", padx=15, pady=5)
        return w

    def button(self, parent, name, callback, primary=False, width=15):
        return tk.Button(parent, text=name, command=callback, font=("DejaVu Sans", 10, "bold"),
                         bg=CYAN if primary else SIDEBAR, fg="#081322" if primary else WHITE,
                         activebackground=GREEN if primary else CARD, bd=0, relief="flat",
                         padx=13, pady=11, cursor="hand2", width=width)

    def _build(self):
        bar = tk.Frame(self.root, bg=SIDEBAR, width=230)
        bar.pack(side="left", fill="y")
        bar.pack_propagate(False)
        tk.Label(bar, text="◈  VeylRoute", bg=SIDEBAR, fg=CYAN,
                 font=("DejaVu Sans", 21, "bold")).pack(anchor="w", padx=18, pady=(28, 1))
        tk.Label(bar, text="Privacy Routing Control Center", bg=SIDEBAR,
                 fg=MUTED, font=("DejaVu Sans", 9)).pack(anchor="w", padx=18, pady=(0, 25))
        for label, page in (("◉  Overview", "overview"), ("▤  Diagnostics", "diagnostics"),
                            ("ⓘ  About VeylRoute", "about")):
            item = self.button(bar, label, lambda p=page: self.show(p), width=23)
            item.pack(anchor="w", padx=10, pady=4)
        tk.Label(bar, text="LINUX • EXPERIMENTAL", bg=SIDEBAR, fg=MUTED,
                 font=("DejaVu Sans", 9)).pack(side="bottom", anchor="w", padx=20, pady=25)

        self.content = tk.Frame(self.root, bg=BG)
        self.content.pack(side="left", fill="both", expand=True)
        self.pages = {}
        for page in ("overview", "diagnostics", "about"):
            self.pages[page] = tk.Frame(self.content, bg=BG)
        self._overview()
        self._diagnostics()
        self._about()
        self.show("overview")

    def _overview(self):
        p = self.pages["overview"]
        self.text(p, "Overview", 24, bold=True)
        self.text(p, "Connection and privacy controls at a glance", 11, MUTED)
        card = self.panel(p)
        self.text(card, "CONNECTION STATUS", 10, CYAN, bold=True)
        tk.Label(card, textvariable=self.phase, bg=CARD, fg=WHITE,
                 font=("DejaVu Sans", 17, "bold")).pack(anchor="w", padx=15, pady=5)
        tk.Label(card, textvariable=self.detail, bg=CARD, fg=MUTED,
                 font=("DejaVu Sans", 10), wraplength=670, justify="left").pack(anchor="w", padx=15, pady=(0, 12))
        settings = self.panel(p)
        self.text(settings, "CONNECTION PREFERENCES", 10, CYAN, bold=True)
        form = tk.Frame(settings, bg=CARD)
        form.pack(fill="x", padx=15, pady=10)
        tk.Label(form, text="Exit country", bg=CARD, fg=MUTED).grid(row=0, column=0, sticky="w", padx=6)
        tk.Entry(form, textvariable=self.exit_country, bg=SIDEBAR, fg=WHITE,
                 insertbackground=WHITE, width=12, relief="flat").grid(row=0, column=1, padx=8, ipady=7)
        tk.Label(form, text="auto or ISO code (e.g. US)", bg=CARD, fg=MUTED).grid(row=0, column=2, sticky="w")
        tk.Label(form, text="Private bridges file", bg=CARD, fg=MUTED).grid(row=1, column=0, sticky="w", pady=15, padx=6)
        tk.Entry(form, textvariable=self.bridge_path, bg=SIDEBAR, fg=WHITE,
                 insertbackground=WHITE, relief="flat", width=28).grid(row=1, column=1, columnspan=2, padx=8, sticky="ew", ipady=7)
        self.button(form, "Browse", self.pick_bridges, width=8).grid(row=1, column=3, padx=7)
        row = tk.Frame(settings, bg=CARD)
        row.pack(fill="x", padx=15, pady=(4, 17))
        self.connect_button = self.button(row, "Connect", lambda: self.operation("start"), primary=True, width=12)
        self.connect_button.pack(side="left", padx=4)
        self.stop_button = self.button(row, "Disconnect", lambda: self.operation("stop"), width=13)
        self.stop_button.pack(side="left", padx=4)
        self.cancel_button = self.button(row, "Cancel", self.cancel, width=10)
        self.cancel_button.pack(side="left", padx=4)
        self.newnym_button = self.button(row, "New circuit", lambda: self.operation("new-circuit"), width=13)
        self.newnym_button.pack(side="left", padx=4)
        priv = self.panel(p)
        self.text(priv, "PRIVACY CHECKS", 10, CYAN, bold=True)
        self.text(priv, "Local firewall and Tor process indicators are distinct from external leak verification.", 10, WHITE)
        self.text(priv, "External DNS path: not independently verified. IPv6 blocked during a guarded session by design; test on your Linux device.", 9, MUTED)

    def _diagnostics(self):
        p = self.pages["diagnostics"]
        self.text(p, "Diagnostics", 24, bold=True)
        self.text(p, "Preflight, status, health and protected recovery actions", 11, MUTED)
        row = tk.Frame(p, bg=BG)
        row.pack(fill="x", padx=19, pady=12)
        for name, operation in (("Preflight", "preflight"), ("Health", "health"),
                                ("Recover", "recover")):
            self.button(row, name, lambda c=operation: self.operation(c), width=14).pack(side="left", padx=4)
        card = self.panel(p)
        self.text(card, "ACTIVITY", 10, CYAN, bold=True)
        self.activity = tk.Text(card, bg="#0b1d31", fg=WHITE, insertbackground=WHITE,
                                height=19, wrap="word", bd=0, font=("DejaVu Sans Mono", 10))
        self.activity.pack(fill="both", expand=True, padx=15, pady=(6, 18))
        self.activity.insert("end", "[INFO] Linux controller ready. No connection attempted.\n")
        self.activity.config(state="disabled")

    def _about(self):
        p = self.pages["about"]
        self.text(p, "About VeylRoute", 24, bold=True)
        self.text(p, "Your connection. Your route. Your privacy.", 11, MUTED)
        hero = self.panel(p)
        self.text(hero, "◈  VeylRoute", 25, CYAN, bold=True)
        self.text(hero, "Privacy Routing Control Center · Linux", 12)
        self.text(hero, f"Version {__version__}  •  Experimental Linux foundation", 10, MUTED)
        info = self.panel(p)
        self.text(info, "DEVELOPED & MAINTAINED BY", 10, CYAN, bold=True)
        self.text(info, "Adam Knight  |  @admknight", 12, bold=True)
        self.text(info, "Tor, Linux nftables, and open-source networking tools retain their own licenses.", 10, MUTED)
        self.text(info, "Project code: MIT License. No third-party binaries bundled.", 10, MUTED)
        row = tk.Frame(info, bg=CARD)
        row.pack(anchor="w", padx=15, pady=13)
        self.button(row, "GitHub releases", lambda: webbrowser.open("https://github.com/admknight/VeylRoute/releases"), width=18).pack(side="left", padx=4)
        self.button(row, "Project source", lambda: webbrowser.open("https://github.com/admknight/VeylRoute"), width=18).pack(side="left", padx=4)
        self.text(info, "Linux in-app automatic updates: not yet available. Only Windows v3.0.1 is stable.", 9, MUTED)

    def show(self, page):
        for view in self.pages.values():
            view.pack_forget()
        self.pages[page].pack(fill="both", expand=True)

    def add_log(self, severity: str, message: str):
        def update():
            self.activity.config(state="normal")
            self.activity.insert("end", f"[{severity}] {message}\n")
            self.activity.see("end")
            self.activity.config(state="disabled")
        self.root.after(0, update)

    def pick_bridges(self):
        p = filedialog.askopenfilename(title="Select PRIVATE obfs4 bridge file")
        if p:
            self.bridge_path.set(p)

    def refresh(self):
        try:
            state = read_json(STATUS)
            phase = str(state.get("phase") or "not-running")
            self.phase.set(phase.replace("-", " ").upper())
            detail = "Local safeguards are not a verified DNS leak test."
            if phase == "connecting":
                detail = f"Tor bootstrap: {state.get('bootstrap', 0)}% — Cancel is available."
            if phase == "connected-unverified":
                detail = "Tor bootstrap complete; local nftables guard installed. Run Health."
            if phase == "recovery-required":
                detail = "Partial operation; use Recover before trying to reconnect."
            self.detail.set(detail)
        except Exception as ex:
            self.detail.set(f"Unable to read local status: {type(ex).__name__}")
        self.cancel_button.config(state="normal" if self.current_action == "start" else "disabled")
        self.root.after(900, self.refresh)

    def _command(self, action: str) -> list[str]:
        executable = Path(sys.argv[0]).resolve()
        # GUI must be started from bin/veylroute; do not guess source module path.
        if not executable.is_file() or executable.name not in ("veylroute", "veylroute-gui"):
            raise RuntimeError("Launch GUI using the packaged veylroute or veylroute-gui launcher")
        polkit = shutil.which("pkexec")
        if not polkit:
            raise RuntimeError("pkexec not found. Use sudo veylroute <command> from a terminal")
        cmd = [polkit, str(executable), action]
        if action in ("start", "preflight"):
            cmd.extend(["--exit-country", self.exit_country.get().strip() or "auto"])
            if self.bridge_path.get().strip():
                cmd.extend(["--bridges-file", self.bridge_path.get().strip()])
        return cmd

    def operation(self, action: str):
        if self.busy:
            self.add_log("WARN", "Another operation is active.")
            return
        if action in ("stop", "recover") and not messagebox.askyesno(
                "Network restoration", f"Proceed with {action}? This will modify VeylRoute's Linux firewall guard."):
            return
        try:
            command = self._command(action)
        except RuntimeError as ex:
            messagebox.showerror("VeylRoute", str(ex))
            return
        self.busy = True
        self.current_action = action
        self.add_log("INFO", f"{action.upper()} requested")
        threading.Thread(target=self._run_command, args=(command, action), daemon=True).start()

    def _run_command(self, command: list[str], action: str):
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, timeout=350)
            if result.stdout:
                for line in result.stdout.splitlines():
                    self.add_log("INFO", line[:500])
            if result.stderr:
                for line in result.stderr.splitlines():
                    self.add_log("ERROR", line[:500])
            self.add_log("OK" if result.returncode == 0 else "ERROR", f"{action}: exit {result.returncode}")
        except Exception as ex:
            self.add_log("ERROR", f"{action}: {type(ex).__name__}")
        finally:
            self.root.after(0, lambda: self._set_idle())

    def _run_cancel(self, command: list[str]):
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
            self.add_log("OK" if result.returncode == 0 else "ERROR",
                         (result.stdout or result.stderr or "Cancel request finished").strip()[:500])
        except Exception as ex:
            self.add_log("ERROR", "Cancel request failed: " + type(ex).__name__)

    def _set_idle(self):
        self.busy = False
        self.current_action = ""

    def cancel(self):
        if self.current_action != "start":
            return
        try:
            command = self._command("cancel")
        except RuntimeError as ex:
            messagebox.showerror("VeylRoute", str(ex))
            return
        self.add_log("WARN", "Cooperative cancellation requested; guard will be preserved if recovery is needed.")
        threading.Thread(target=self._run_cancel, args=(command,), daemon=True).start()


def main():
    if sys.platform != "linux":
        raise RuntimeError("Linux GUI is Linux-only")
    root = tk.Tk()
    App(root)
    root.mainloop()
    return 0
