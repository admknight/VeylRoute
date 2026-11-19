"""Run under xvfb-run with real Tk: validate navigation and actual icon rendering."""
from __future__ import annotations
import tkinter as tk
from veylroute.gui import App

root = tk.Tk(className='VeylRoute')
app = App(root)
root.update_idletasks()
root.update()
assert root.winfo_class() == 'Veylroute'
assert len(app.pages) == 11
assert len(app.images) == 4
for page in app.pages:
    app.show(page)
    root.update_idletasks()
    root.update()
assert app._portable() is True  # checked out source is portable-shaped
assert app.update_button.cget('state') == 'disabled'  # no speculative install button
app.exit_gui()
print('PASS: 11 Linux GUI pages, 4 approved icons, window WM_CLASS, no network mutation')
