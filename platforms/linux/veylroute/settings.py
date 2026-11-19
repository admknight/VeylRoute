"""Explicit user GUI preferences. Private bridge paths/content are not retained."""
from __future__ import annotations

import json
import os
from pathlib import Path
from . import model

DEFAULTS = {"exit_country": "auto", "minimize_to_tray": False}


def path() -> Path:
    home = os.environ.get('XDG_CONFIG_HOME')
    base = Path(home).expanduser() if home else Path.home() / '.config'
    if not base.is_absolute():
        raise ValueError('XDG_CONFIG_HOME must be absolute')
    return base / 'veylroute' / 'ui.json'


def load() -> dict:
    p = path()
    if p.is_symlink():
        raise ValueError('Preferences cannot be a symbolic link')
    try:
        payload = json.loads(p.read_text(encoding='utf-8'))
    except FileNotFoundError:
        return DEFAULTS.copy()
    if not isinstance(payload, dict):
        raise ValueError('Invalid GUI preferences')
    return validate(payload)


def validate(data: dict) -> dict:
    if not isinstance(data, dict):
        raise ValueError('Invalid preferences input')
    country = data.get('exit_country', 'auto')
    if not isinstance(country, str):
        raise ValueError('Exit country must be text')
    country = model.Options(country).validate().exit_country
    hide = data.get('minimize_to_tray', False)
    if not isinstance(hide, bool):
        raise ValueError('Minimize to tray must be boolean')
    return {'exit_country': country, 'minimize_to_tray': hide}


def save(data: dict) -> Path:
    cleaned = validate(data)
    dest = path()
    dest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if dest.is_symlink():
        raise ValueError('Preferences cannot be a symbolic link')
    temp = dest.with_name(dest.name + f'.tmp-{os.getpid()}')
    try:
        with temp.open('x', encoding='utf-8') as handle:
            json.dump(cleaned, handle, indent=2, sort_keys=True)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        temp.chmod(0o600)
        temp.replace(dest)
    finally:
        temp.unlink(missing_ok=True)
    return dest
