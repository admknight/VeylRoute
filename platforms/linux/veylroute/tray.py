"""Best-effort Linux status indicator, with explicit desktop compatibility limits.

Tries pystray when available; falls back to the distro's Ayatana AppIndicator
GI package. GNOME may need an AppIndicator shell extension. No tray backend is
allowed to run routing commands directly; callbacks return to Tk's main loop.
"""
from __future__ import annotations

import threading
from pathlib import Path

STATES = ('disconnected', 'connecting', 'connected', 'warning')


def artwork(state: str) -> Path:
    if state not in STATES:
        state = 'warning'
    base = Path(__file__).resolve().parent.parent
    local = base / 'assets' / f'veylroute-{state}.png'
    if local.is_file():
        return local
    return Path('/usr/share/veylroute/assets') / f'veylroute-{state}.png'


class Tray:
    def __init__(self, root, on_show, on_disconnect, on_exit):
        self.root = root
        self.on_show = on_show
        self.on_disconnect = on_disconnect
        self.on_exit = on_exit
        self.icon = None
        self.thread = None
        self.Images = {}
        self.backend = ''
        self.Gtk = None
        self.GLib = None
        self.IndicatorStatus = None

    def _schedule(self, callback):
        # Never manipulate Tk widgets from a tray callback thread.
        self.root.after(0, callback)

    def _pystray_start(self) -> bool:
        try:
            import pystray
            from PIL import Image
            images = {s: Image.open(artwork(s)).convert('RGBA') for s in STATES}
            menu = pystray.Menu(
                pystray.MenuItem('Open VeylRoute', lambda *_: self._schedule(self.on_show), default=True),
                pystray.MenuItem('Disconnect', lambda *_: self._schedule(self.on_disconnect)),
                pystray.MenuItem('Exit GUI', lambda *_: self._schedule(self.on_exit)),
            )
            self.icon = pystray.Icon('veylroute', images['disconnected'], 'VeylRoute', menu)
            self.Images = images
            self.thread = threading.Thread(target=self.icon.run, daemon=True, name='VeylRoutePystray')
            self.thread.start()
            self.backend = 'pystray'
            return True
        except (ImportError, FileNotFoundError, OSError, RuntimeError, ValueError):
            self.icon = None
            return False

    def _appindicator_start(self) -> bool:
        """Use system-provided GI libraries; do not bundle shell extensions."""
        try:
            import gi
            gi.require_version('Gtk', '3.0')
            try:
                gi.require_version('AyatanaAppIndicator3', '0.1')
                from gi.repository import AyatanaAppIndicator3 as Indicator
            except (ValueError, ImportError):
                gi.require_version('AppIndicator3', '0.1')
                from gi.repository import AppIndicator3 as Indicator
            from gi.repository import Gtk, GLib
            icon = Indicator.Indicator.new('veylroute', str(artwork('disconnected')),
                                           Indicator.IndicatorCategory.APPLICATION_STATUS)
            menu = Gtk.Menu()
            for title, callback in (('Open VeylRoute', self.on_show),
                                    ('Disconnect', self.on_disconnect),
                                    ('Exit GUI', self.on_exit)):
                item = Gtk.MenuItem.new_with_label(title)
                item.connect('activate', lambda *_args, cb=callback: self._schedule(cb))
                menu.append(item)
            menu.show_all()
            icon.set_menu(menu)
            icon.set_status(Indicator.IndicatorStatus.ACTIVE)
            self.icon = icon
            self.IndicatorStatus = Indicator.IndicatorStatus
            self.Gtk, self.GLib = Gtk, GLib
            self.thread = threading.Thread(target=Gtk.main, daemon=True, name='VeylRouteAppIndicator')
            self.thread.start()
            self.backend = 'appindicator'
            return True
        except (ImportError, ValueError, RuntimeError, OSError, AttributeError):
            self.icon = None
            return False

    def start(self) -> bool:
        return self._pystray_start() or self._appindicator_start()

    def set_state(self, state: str) -> None:
        if self.icon is None:
            return
        name = state if state in STATES else 'warning'
        try:
            if self.backend == 'pystray':
                self.icon.icon = self.Images[name]
                self.icon.title = f'VeylRoute — {name}'
            elif self.backend == 'appindicator' and self.GLib is not None:
                self.GLib.idle_add(self.icon.set_icon_full, str(artwork(name)), f'VeylRoute — {name}')
        except (RuntimeError, OSError, AttributeError):
            pass

    def stop(self) -> None:
        if self.icon is None:
            return
        try:
            if self.backend == 'pystray':
                self.icon.stop()
            elif self.backend == 'appindicator' and self.GLib is not None:
                self.GLib.idle_add(self.icon.set_status, self.IndicatorStatus.PASSIVE)
                self.GLib.idle_add(self.Gtk.main_quit)
        except (RuntimeError, OSError, AttributeError):
            pass
        self.icon = None
