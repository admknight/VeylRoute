"""Linux Tk desktop control center. GUI never changes routing without consent."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading
import tkinter as tk
import webbrowser
from pathlib import Path
from tkinter import filedialog, messagebox

from . import __version__
from . import desktop, model, settings, tray, updates
from .app import STATUS, read_json

BG = '#091626'
SIDEBAR = '#0f2239'
CARD = '#142b47'
BORDER = '#244564'
WHITE = '#e9f5fb'
MUTED = '#9cafc5'
CYAN = '#47d4e8'
GREEN = '#5ce4ac'
RED = '#f59fa3'
PROJECT_URL = 'https://github.com/admknight/VeylRoute'


class App:
    def __init__(self, root: tk.Tk):
        self.root = root
        root.title(f'VeylRoute — Linux Control Center {__version__}')
        root.geometry('1110x755')
        root.minsize(900, 610)
        root.configure(bg=BG)
        self.closing = False
        self.busy = False
        self.current_action = ''
        try:
            self.saved = settings.load()
        except (ValueError, OSError, json.JSONDecodeError):
            self.saved = settings.DEFAULTS.copy()
        self.exit_country = tk.StringVar(value=self.saved['exit_country'])
        self.bridge_path = tk.StringVar(value='')  # Never persist private bridge path.
        self.minimize_to_tray = tk.BooleanVar(value=self.saved['minimize_to_tray'])
        self.phase = tk.StringVar(value='NOT CONNECTED')
        self.detail = tk.StringVar(value='No Tor session is active.')
        self.version = tk.StringVar(value=f'Linux {__version__} · experimental')
        self.tray_status = tk.StringVar(value='System tray: unavailable')
        self.update_status = tk.StringVar(value='Stable Linux channel not checked.')
        self.update_result = None
        self.images = {}
        self._install_icon()
        self._build()
        self.tray = tray.Tray(root, self.restore_window,
                              lambda: self.operation('stop'), self.exit_gui)
        available = self.tray.start()
        self.tray_status.set('System tray: enabled' if available else
                             'System tray: optional integration unavailable')
        root.protocol('WM_DELETE_WINDOW', self.on_close)
        root.after(300, self.refresh)

    def _install_icon(self):
        for name in ('disconnected', 'connecting', 'connected', 'warning'):
            path = tray.artwork(name)
            if path.is_file():
                try:
                    self.images[name] = tk.PhotoImage(file=str(path))
                except tk.TclError:
                    pass
        if 'disconnected' in self.images:
            self.root.iconphoto(True, self.images['disconnected'])

    def _set_window_icon(self, state):
        if state in self.images:
            self.root.iconphoto(True, self.images[state])
        if hasattr(self, 'tray'):
            self.tray.set_state(state)

    def panel(self, parent):
        p = tk.Frame(parent, bg=CARD, highlightthickness=1, highlightbackground=BORDER)
        p.pack(fill='x', padx=18, pady=7)
        return p

    def text(self, parent, content, size=11, color=WHITE, bold=False, **kwargs):
        w = tk.Label(parent, text=content, font=('DejaVu Sans', size, 'bold' if bold else 'normal'),
                     fg=color, bg=parent.cget('bg'), justify='left', anchor='w',
                     wraplength=750, **kwargs)
        w.pack(anchor='w', padx=14, pady=5)
        return w

    def button(self, parent, label, callback, primary=False, width=15):
        return tk.Button(parent, text=label, command=callback,
                         font=('DejaVu Sans', 10, 'bold'),
                         bg=CYAN if primary else SIDEBAR,
                         fg='#081322' if primary else WHITE,
                         activebackground=GREEN if primary else CARD,
                         bd=0, relief='flat', padx=10, pady=8,
                         cursor='hand2', width=width)

    def button_row(self, parent, items):
        p = tk.Frame(parent, bg=parent.cget('bg'))
        p.pack(anchor='w', padx=14, pady=(8, 15))
        for label, callback, primary in items:
            self.button(p, label, callback, primary, min(20, max(10, len(label)+1))).pack(side='left', padx=4)
        return p

    def _build(self):
        sidebar = tk.Frame(self.root, bg=SIDEBAR, width=235)
        sidebar.pack(side='left', fill='y')
        sidebar.pack_propagate(False)
        brand = tk.Frame(sidebar, bg=SIDEBAR)
        brand.pack(fill='x', padx=12, pady=(14, 0))
        if 'disconnected' in self.images:
            self.brand_icon = self.images['disconnected'].subsample(7, 7)
            tk.Label(brand, image=self.brand_icon, bg=SIDEBAR).pack(side='left', padx=(0, 8))
        tk.Label(brand, text='VeylRoute', bg=SIDEBAR, fg=CYAN,
                 font=('DejaVu Sans', 19, 'bold')).pack(side='left')
        self.text(sidebar, 'Privacy Routing Control Center', 9, MUTED)
        groups = (
            ('WORKSPACE', (('Overview', 'overview'), ('Exit locations', 'locations'),
                           ('DNS protection', 'privacy'), ('Application routing', 'routing'),
                           ('obfs4 bridges', 'bridges'), ('Advanced settings', 'settings'))),
            ('OPERATIONS', (('Versions & updates', 'updates'), ('Activity log', 'activity'),
                            ('Maintenance', 'maintenance'), ('Setup guide', 'guide'),
                            ('About VeylRoute', 'about'))),
        )
        for header, entries in groups:
            self.text(sidebar, header, 9, CYAN, bold=True)
            for label, page in entries:
                self.button(sidebar, label, lambda p=page: self.show(p), width=23).pack(
                    anchor='w', padx=8, pady=2)
        self.button(sidebar, 'Exit GUI', self.exit_gui, width=23).pack(anchor='w', padx=8, pady=(9, 0))
        self.text(sidebar, 'LINUX · EXPERIMENTAL', 9, MUTED)

        self.content = tk.Frame(self.root, bg=BG)
        self.content.pack(side='left', fill='both', expand=True)
        self.pages = {name: tk.Frame(self.content, bg=BG) for name in
                      ('overview', 'locations', 'privacy', 'routing', 'bridges',
                       'settings', 'updates', 'activity', 'maintenance', 'guide', 'about')}
        self._overview(); self._locations(); self._privacy(); self._routing()
        self._bridges(); self._settings(); self._updates(); self._activity()
        self._maintenance(); self._guide(); self._about()
        self.show('overview')

    def _section(self, page, title, subtitle):
        p = self.pages[page]
        self.text(p, title, 23, bold=True)
        self.text(p, subtitle, 10, MUTED)
        return p

    def _overview(self):
        p = self._section('overview', 'Overview', 'Connection and system health at a glance')
        card = self.panel(p)
        self.text(card, 'CONNECTION STATUS', 10, CYAN, bold=True)
        tk.Label(card, textvariable=self.phase, bg=CARD, fg=WHITE,
                 font=('DejaVu Sans', 16, 'bold')).pack(anchor='w', padx=15, pady=5)
        tk.Label(card, textvariable=self.detail, bg=CARD, fg=MUTED,
                 wraplength=700, justify='left', font=('DejaVu Sans', 10)).pack(anchor='w', padx=15, pady=(0, 12))
        self.button_row(card, [('Connect', lambda: self.operation('start'), True),
                               ('Disconnect', lambda: self.operation('stop'), False),
                               ('Cancel', self.cancel, False),
                               ('New circuit', lambda: self.operation('new-circuit'), False)])
        self.text(p, 'Country preference and private obfs4 bridge file are configured on their dedicated pages.', 10, MUTED)
        priv = self.panel(p)
        self.text(priv, 'PRIVACY AT A GLANCE', 10, CYAN, bold=True)
        self.text(priv, 'Tor status and nftables indicators are local checks, not a guarantee of leak-free routing.', 11)
        self.text(priv, 'DNS egress, browser fingerprinting and SelectedAppsOnly isolation are not independently verified.', 10, MUTED)

    def _locations(self):
        p = self._section('locations', 'Exit locations', 'Preferred Tor exit country')
        card = self.panel(p)
        self.text(card, 'EXIT COUNTRY', 10, CYAN, bold=True)
        form = tk.Frame(card, bg=CARD)
        form.pack(anchor='w', padx=14, pady=10)
        tk.Entry(form, textvariable=self.exit_country, bg=SIDEBAR, fg=WHITE,
                 insertbackground=WHITE, relief='flat', width=12).pack(side='left', ipady=8)
        self.text(form, 'auto or two-letter ISO code (e.g. US)', 10, MUTED)
        self.text(card, 'Strict exit-country selection may prevent Tor from completing bootstrap if suitable relays are unavailable.', 10, MUTED)
        self.button_row(card, [('Validate format', self.validate_country, True),
                               ('Save preference', self.save_preferences, False)])

    def _privacy(self):
        p = self._section('privacy', 'DNS protection', 'Tor DNSPort and Linux nftables containment')
        card = self.panel(p)
        self.text(card, 'CURRENT LINUX MODEL', 10, CYAN, bold=True)
        self.text(card, 'SystemWide: IPv4 TCP is redirected to Tor TransPort and UDP/53 to DNSPort. Other outgoing protocols are guarded by nftables while connected.', 10)
        self.text(card, 'IPv6 and DNS-over-HTTPS/DoT: not independently leak-tested. A local status screen cannot certify the actual DNS path.', 10, MUTED)
        self.button_row(card, [('Health check', lambda: self.operation('health'), True),
                               ('Activity log', lambda: self.show('activity'), False)])

    def _routing(self):
        p = self._section('routing', 'Application routing', 'Linux operating mode and isolation limitations')
        card = self.panel(p)
        self.text(card, 'SystemWide · implemented', 11, GREEN, bold=True)
        self.text(card, 'Uses the dedicated Tor UID and app-owned nftables rules. A live Linux privacy test is still required.', 10)
        self.text(card, 'SelectedAppsOnly · not available', 11, RED, bold=True)
        self.text(card, 'Linux process isolation needs an independently tested network-namespace/cgroup design. It is not safe to imitate Windows Wintun routing or label a SOCKS environment variable as isolation.', 10, MUTED)

    def _bridges(self):
        p = self._section('bridges', 'obfs4 bridges', 'Use a private file; bridge lines are not stored in GUI preferences')
        card = self.panel(p)
        self.text(card, 'PRIVATE BRIDGE FILE', 10, CYAN, bold=True)
        row = tk.Frame(card, bg=CARD)
        row.pack(fill='x', padx=14, pady=8)
        tk.Entry(row, textvariable=self.bridge_path, bg=SIDEBAR, fg=WHITE,
                 insertbackground=WHITE, relief='flat', width=34).pack(side='left', ipady=8)
        self.button(row, 'Browse', self.pick_bridges, width=9).pack(side='left', padx=8)
        self.text(card, 'Use obfs4 IPv4 bridge lines from a trusted private source. Do not publish the file or paste bridge credentials into GitHub issues.', 10, MUTED)
        self.button_row(card, [('Validate format', self.validate_bridges, True),
                               ('Clear selection', lambda: self.bridge_path.set(''), False)])

    def _settings(self):
        p = self._section('settings', 'Advanced settings', 'Explicitly saved GUI preferences; no hidden route changes')
        card = self.panel(p)
        self.text(card, 'USER PREFERENCES', 10, CYAN, bold=True)
        tk.Checkbutton(card, text='Hide GUI to system tray when closing (when available)',
                       variable=self.minimize_to_tray, bg=CARD, fg=WHITE,
                       activebackground=CARD, activeforeground=WHITE,
                       selectcolor=SIDEBAR).pack(anchor='w', padx=14, pady=7)
        tk.Label(card, textvariable=self.tray_status, bg=CARD, fg=MUTED).pack(anchor='w', padx=14, pady=6)
        self.text(card, 'Private bridge credentials are never included in saved preferences. Desktop dock pinning is always your choice.', 10, MUTED)
        self.button_row(card, [('Save preferences', self.save_preferences, True),
                               ('Reload', self.reload_preferences, False)])
        if self._portable():
            shortcut = self.panel(p)
            self.text(shortcut, 'PORTABLE DESKTOP INTEGRATION', 10, CYAN, bold=True)
            self.button_row(shortcut, [('Add to application menu', self.desktop_install, True),
                                       ('Remove menu shortcut', self.desktop_remove, False)])
        else:
            self.text(p, 'Setup installations include a system application-menu entry and custom icon.', 10, MUTED)

    def _updates(self):
        p = self._section('updates', 'Versions & updates', 'Linux application updates are separate from Tor distro packages')
        card = self.panel(p)
        self.text(card, f'VEYLROUTE LINUX {__version__}  ·  {self._edition_display()}', 10, CYAN, bold=True)
        tk.Label(card, textvariable=self.update_status, bg=CARD, fg=WHITE,
                 wraplength=690, justify='left').pack(anchor='w', padx=14, pady=8)
        buttons = self.button_row(card, [('Check for updates', self.check_updates, True),
                                         ('Download & update', self.download_update, False)])
        self.update_button = list(buttons.winfo_children())[-1]
        self.update_button.config(state='disabled')
        self.text(card, 'The stable Linux channel uses Linux-only GitHub release tags and verifies SHA-256 checksums. Preview versions are intentionally excluded.', 10, MUTED)
        tor = self.panel(p)
        self.text(tor, 'TOR COMPONENT UPDATES', 10, CYAN, bold=True)
        self.text(tor, 'Tor, nftables and obfs4 binaries are maintained using your Linux distribution package manager. VeylRoute does not silently replace those components.', 10)
        self.button_row(tor, [('View release notes', lambda: webbrowser.open(PROJECT_URL + '/releases'), False)])

    def _activity(self):
        p = self._section('activity', 'Activity log', 'Local controller output; private bridge lines are not logged')
        card = self.panel(p)
        self.activity = tk.Text(card, bg='#0b1d31', fg=WHITE, insertbackground=WHITE,
                                height=15, wrap='word', bd=0,
                                font=('DejaVu Sans Mono', 10))
        self.activity.pack(fill='both', expand=True, padx=14, pady=(10, 6))
        self.activity.insert('end', '[INFO] Linux control center started. No network changes requested.\n')
        self.activity.config(state='disabled')
        self.button_row(card, [('Copy log', self.copy_log, True),
                               ('Clear display', self.clear_log, False)])

    def _maintenance(self):
        p = self._section('maintenance', 'Maintenance', 'Preflight, health and guarded session recovery')
        card = self.panel(p)
        self.text(card, 'NETWORK RECOVERY', 10, CYAN, bold=True)
        self.text(card, 'Recovery stops only the managed Tor process and removes only VeylRoute-owned nftables tables. It never blindly resets your other firewall rules, routes or resolver.', 10)
        self.button_row(card, [('Preflight', lambda: self.operation('preflight'), True),
                               ('Health', lambda: self.operation('health'), False),
                               ('Recover', lambda: self.operation('recover'), False)])
        self.text(card, 'A stale or unrecognized process blocks automatic cleanup and requires operator review; do not delete session files to bypass recovery.', 10, MUTED)

    def _guide(self):
        p = self._section('guide', 'Setup guide', 'Debian/Ubuntu and portable editions')
        card = self.panel(p)
        self.text(card, 'BEFORE CONNECTING', 10, CYAN, bold=True)
        self.text(card, 'Install distro Tor, nftables and iproute2. For the optional bridges feature, install obfs4proxy or lyrebird. Run Preflight before Connect.', 10)
        self.text(card, 'The desktop GUI uses a polkit authorization prompt for privileged commands; terminal users may run sudo veylroute. Test real routing only in a disposable Linux VM until the live security gate is passed.', 10, MUTED)
        self.button_row(card, [('Project documentation', lambda: webbrowser.open(PROJECT_URL + '/tree/main/platforms/linux'), True)])

    def _about(self):
        p = self._section('about', 'About VeylRoute', 'Your connection. Your route. Your privacy.')
        card = self.panel(p)
        logo = tk.Frame(card, bg=CARD)
        logo.pack(anchor='w', padx=14, pady=(12, 4))
        if 'disconnected' in self.images:
            self.about_icon = self.images['disconnected'].subsample(5, 5)
            tk.Label(logo, image=self.about_icon, bg=CARD).pack(side='left', padx=(0, 12))
        tk.Label(logo, text='VeylRoute', bg=CARD, fg=CYAN,
                 font=('DejaVu Sans', 23, 'bold')).pack(side='left')
        self.text(card, f'Privacy Routing Control Center · Linux v{__version__} (Experimental)', 11)
        self.text(card, 'Developer & maintainer: Adam Knight (@admknight)', 10, WHITE, bold=True)
        self.text(card, 'Original project source: MIT. Tor, nftables, obfs4 and other dependencies retain their own licenses.', 10, MUTED)
        self.button_row(card, [('Open GitHub', lambda: webbrowser.open(PROJECT_URL), True),
                               ('View license', lambda: webbrowser.open(PROJECT_URL + '/blob/main/LICENSE'), False)])
        second = self.panel(p)
        self.text(second, 'APPLICATION EDITION', 10, CYAN, bold=True)
        self.text(second, self._edition_display() + ' · Linux system update channel', 10)
        self.button_row(second, [('Check for updates', lambda: (self.show('updates'), self.check_updates()), True)])

    def _portable(self):
        try:
            return updates.edition() == 'portable'
        except updates.UpdateError:
            return False

    def _edition_display(self):
        try:
            return 'Portable edition' if updates.edition() == 'portable' else 'Debian Setup edition'
        except updates.UpdateError:
            return 'Unknown edition · automatic updates disabled'

    def show(self, page):
        for view in self.pages.values():
            view.pack_forget()
        self.pages[page].pack(fill='both', expand=True)

    def add_log(self, severity: str, message: str):
        if self.closing:
            return
        def update():
            if self.closing:
                return
            self.activity.config(state='normal')
            self.activity.insert('end', f'[{severity}] {message[:800]}\n')
            # Bound text output to avoid unbounded memory use.
            if int(self.activity.index('end-1c').split('.')[0]) > 800:
                self.activity.delete('1.0', '250.0')
            self.activity.see('end')
            self.activity.config(state='disabled')
        self.root.after(0, update)

    def copy_log(self):
        self.root.clipboard_clear()
        self.root.clipboard_append(self.activity.get('1.0', 'end-1c'))
        self.add_log('INFO', 'Activity display copied to clipboard')

    def clear_log(self):
        self.activity.config(state='normal')
        self.activity.delete('1.0', 'end')
        self.activity.config(state='disabled')

    def pick_bridges(self):
        p = filedialog.askopenfilename(title='Select PRIVATE obfs4 bridge file')
        if p:
            self.bridge_path.set(p)

    def validate_country(self):
        try:
            value = model.Options(self.exit_country.get()).validate().exit_country
            self.exit_country.set(value)
            messagebox.showinfo('Exit selection', f'Country format valid: {value}. Relay availability is not guaranteed.')
        except ValueError as ex:
            messagebox.showerror('Exit selection', str(ex))

    def validate_bridges(self):
        path = self.bridge_path.get().strip()
        if not path:
            messagebox.showinfo('Private bridges', 'No bridge file selected; direct Tor mode is used.')
            return
        try:
            file = Path(path)
            if not file.is_file() or file.stat().st_size > 12000:
                raise ValueError('Private bridge file missing or unexpectedly large')
            lines = [line.strip() for line in file.read_text(encoding='utf-8').splitlines()
                     if line.strip() and not line.lstrip().startswith('#')]
            for line in lines:
                model.validate_bridge(line)
            messagebox.showinfo('Private bridges', f'{len(lines)} obfs4 bridge entries have valid format. No bridge details were logged.')
        except (ValueError, OSError, UnicodeDecodeError):
            messagebox.showerror('Private bridges', 'Invalid private bridge file or unsupported bridge format. File details were not logged.')

    def save_preferences(self):
        try:
            saved = settings.save({'exit_country': self.exit_country.get(),
                                   'minimize_to_tray': self.minimize_to_tray.get()})
            self.add_log('INFO', 'Preferences saved (private bridge path excluded).')
        except (ValueError, OSError) as ex:
            messagebox.showerror('Settings', str(ex))

    def reload_preferences(self):
        try:
            prefs = settings.load()
            self.exit_country.set(prefs['exit_country'])
            self.minimize_to_tray.set(prefs['minimize_to_tray'])
        except (ValueError, OSError) as ex:
            messagebox.showerror('Settings', str(ex))

    def desktop_install(self):
        try:
            path = desktop.install()
            messagebox.showinfo('Application menu', f'Portable VeylRoute shortcut installed:\n{path}\nPin to dock manually if desired.')
        except (RuntimeError, OSError) as ex:
            messagebox.showerror('Application menu', str(ex))

    def desktop_remove(self):
        try:
            removed = desktop.remove()
            messagebox.showinfo('Application menu', 'Portable shortcut removed.' if removed else 'No portable shortcut was found.')
        except (RuntimeError, OSError) as ex:
            messagebox.showerror('Application menu', str(ex))

    def refresh(self):
        if self.closing:
            return
        try:
            state = read_json(STATUS)
            phase = str(state.get('phase') or 'not-running')
            self.phase.set(phase.replace('-', ' ').upper())
            detail = 'Local safeguards are not a verified DNS leak test.'
            if phase == 'connecting':
                value = int(state.get('bootstrap') or 0)
                detail = f'Tor bootstrap: {value}% — Cancel is available.'
                if getattr(self, '_last_bootstrap', None) != value:
                    self._last_bootstrap = value
                    self.add_log('INFO', f'Tor bootstrap {value}%')
            if phase == 'connected-unverified':
                detail = 'Tor bootstrap complete; local firewall is installed. Use Health. External privacy not yet validated.'
            if phase == 'recovery-required':
                detail = 'Partial operation; use Recover before reconnecting.'
            self.detail.set(detail)
            mode = ('connected' if phase == 'connected-unverified' else
                    'connecting' if phase == 'connecting' else
                    'warning' if phase == 'recovery-required' else 'disconnected')
            if getattr(self, '_last_icon', None) != mode:
                self._set_window_icon(mode)
                self._last_icon = mode
        except Exception as ex:
            self.detail.set('Unable to read local status: ' + type(ex).__name__)
        self.root.after(1100, self.refresh)

    def _command(self, action: str) -> list[str]:
        executable = Path(sys.argv[0]).resolve()
        if not executable.is_file() or executable.name not in ('veylroute', 'veylroute-gui'):
            raise RuntimeError('Launch GUI using the packaged veylroute or veylroute-gui launcher')
        polkit = shutil.which('pkexec')
        if not polkit:
            raise RuntimeError('pkexec not found. Use sudo veylroute <command> in a terminal')
        command = [polkit, str(executable), action]
        if action in ('start', 'preflight'):
            command.extend(['--exit-country', self.exit_country.get().strip() or 'auto'])
            if self.bridge_path.get().strip():
                command.extend(['--bridges-file', self.bridge_path.get().strip()])
        return command

    def operation(self, action: str):
        if self.busy:
            self.add_log('WARN', 'Another operation is active')
            return
        if action in ('stop', 'recover') and not messagebox.askyesno(
                'Network restoration', f'Proceed with {action}? This will change VeylRoute-owned Linux firewall tables.'):
            return
        try:
            cmd = self._command(action)
        except RuntimeError as ex:
            messagebox.showerror('VeylRoute', str(ex))
            return
        self.busy = True
        self.current_action = action
        self.add_log('INFO', f'{action.upper()} requested')
        threading.Thread(target=self._run_command, args=(cmd, action), daemon=True).start()

    def _run_command(self, cmd: list[str], action: str):
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    text=True, timeout=350)
            for line in result.stdout.splitlines():
                self.add_log('INFO', line)
            for line in result.stderr.splitlines():
                self.add_log('ERROR', line)
            self.add_log('OK' if result.returncode == 0 else 'ERROR', f'{action}: exit {result.returncode}')
        except Exception as ex:
            self.add_log('ERROR', f'{action}: {type(ex).__name__}')
        finally:
            if not self.closing:
                self.root.after(0, self._set_idle)

    def _set_idle(self):
        self.busy = False
        self.current_action = ''

    def cancel(self):
        if self.current_action != 'start':
            return
        try:
            cmd = self._command('cancel')
        except RuntimeError as ex:
            messagebox.showerror('VeylRoute', str(ex))
            return
        self.add_log('WARN', 'Cooperative cancellation requested; recovery guard is retained if needed.')
        threading.Thread(target=self._run_cancel, args=(cmd,), daemon=True).start()

    def _run_cancel(self, cmd):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            self.add_log('OK' if result.returncode == 0 else 'ERROR',
                         (result.stdout or result.stderr or 'Cancel request finished').strip())
        except Exception as ex:
            self.add_log('ERROR', 'Cancel request failed: ' + type(ex).__name__)

    def check_updates(self):
        if self.busy:
            return
        self.update_status.set('Checking the stable Linux release channel…')
        self.update_button.config(state='disabled')
        self.busy = True
        def task():
            try:
                result = updates.check()
                self.root.after(0, lambda r=result: self._update_checked(r))
            except Exception as ex:
                self.root.after(0, lambda m=str(ex): self._update_failed(m))
        threading.Thread(target=task, daemon=True).start()

    def _update_checked(self, result):
        self.busy = False
        self.update_result = result
        state = result['status']
        if state == 'update-available':
            self.update_status.set(f"Linux v{result['version']} available for {result['mode']}. Download is verified before installation.")
            self.update_button.config(state='normal')
        elif state == 'no-linux-stable':
            self.update_status.set(result['message'])
        elif state == 'up-to-date':
            self.update_status.set('Already using the latest stable Linux release.')
        else:
            self.update_status.set('Installed Linux edition is newer than the stable channel.')
        self.add_log('INFO', 'Linux release check: ' + state)

    def _update_failed(self, message):
        self.busy = False
        self.update_status.set('Update check failed: ' + message[:170])
        self.add_log('ERROR', 'Update check failed')

    def download_update(self):
        if self.busy or not self.update_result or self.update_result.get('status') != 'update-available':
            return
        if not messagebox.askyesno('VeylRoute update', 'Download and SHA-256 verify the matching Linux package? No files will be installed until you approve again.'):
            return
        self.busy = True
        self.update_button.config(state='disabled')
        self.update_status.set('Downloading and verifying Linux application update…')
        def task():
            try:
                receipt = updates.prepare(self.update_result)
                self.root.after(0, lambda p=receipt: self._update_prepared(p))
            except Exception as ex:
                self.root.after(0, lambda m=str(ex): self._update_failed(m))
        threading.Thread(target=task, daemon=True).start()

    def _update_prepared(self, receipt: Path):
        self.busy = False
        self.update_status.set('Package verified. No application or networking files have changed.')
        if not messagebox.askyesno('Apply verified update', 'Apply the verified Linux application update? VeylRoute must be disconnected and this GUI will close. If the installation is not idle, the updater will refuse.'):
            return
        try:
            executable = Path(sys.argv[0]).resolve()
            cmd = [str(executable), 'update-apply', '--receipt', str(receipt),
                   '--parent-pid', str(os.getpid())]
            if updates.edition() == 'deb':
                polkit = shutil.which('pkexec')
                if not polkit:
                    raise RuntimeError('pkexec unavailable: use sudo veylroute update-apply with the verified receipt')
                cmd.insert(0, polkit)
            with (receipt.parent / 'apply.log').open('a', encoding='utf-8') as output:
                subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=output,
                                 stderr=subprocess.STDOUT, start_new_session=True, close_fds=True)
        except (RuntimeError, OSError, updates.UpdateError) as ex:
            messagebox.showerror('VeylRoute update', str(ex))
            return
        self.exit_gui(force=True)

    def restore_window(self):
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def on_close(self):
        if self.busy:
            messagebox.showwarning('VeylRoute', 'An operation is active. Complete or cancel it before exiting the GUI.')
            return
        if self.minimize_to_tray.get() and self.tray.icon is not None:
            self.root.withdraw()
            return
        self.exit_gui()

    def exit_gui(self, force=False):
        if self.busy and not force:
            messagebox.showwarning('VeylRoute', 'An operation is active; do not exit during network restoration.')
            return
        self.closing = True
        if hasattr(self, 'tray'):
            self.tray.stop()
        self.root.destroy()


def main():
    if sys.platform != 'linux':
        raise RuntimeError('Linux GUI is Linux-only')
    root = tk.Tk(className='VeylRoute')
    App(root)
    root.mainloop()
    return 0
