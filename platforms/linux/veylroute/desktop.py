"""Per-user portable desktop entry, without root or silent dock changes.

The installed Debian package ships its own system desktop file.  This module
handles only the portable source edition and never overwrites other launchers.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

DESKTOP_ID = 'veylroute-portable.desktop'


def portable_root() -> Path:
    root = Path(__file__).resolve().parent.parent
    if not (root / 'bin' / 'veylroute-gui').is_file() or not (root / 'assets' / 'veylroute.png').is_file():
        raise RuntimeError('Portable desktop integration requires the complete portable archive')
    return root


def xdg_applications_dir() -> Path:
    base = os.environ.get('XDG_DATA_HOME')
    data = Path(base).expanduser() if base else Path.home() / '.local' / 'share'
    if not data.is_absolute():
        raise RuntimeError('XDG_DATA_HOME must be an absolute path')
    return data / 'applications'


def _safe_path(path: Path) -> str:
    value = str(path)
    if any(ord(ch) < 32 for ch in value) or '\x00' in value:
        raise RuntimeError('Portable installation path contains unsupported control characters')
    return value


def exec_quote(path: Path) -> str:
    """Exec uses Desktop Entry (not shell) quoting/field-code escaping."""
    value = _safe_path(path)
    value = value.replace('\\', '\\\\').replace('"', '\\"')
    value = value.replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
    return f'"{value}"'


def desktop_text(root: Path) -> str:
    launcher = root / 'bin' / 'veylroute-gui'
    icon = root / 'assets' / 'veylroute.png'
    return ("[Desktop Entry]\n"
            "Version=1.0\nType=Application\nName=VeylRoute (Portable Linux)\n"
            "GenericName=Privacy Routing Control Center\n"
            "Comment=Experimental Linux Tor control center\n"
            f"Exec={exec_quote(launcher)}\n"
            f"TryExec={_safe_path(launcher)}\n"
            f"Icon={_safe_path(icon)}\n"
            "Categories=Network;\nKeywords=Tor;privacy;network;\n"
            "Terminal=false\nStartupNotify=true\nStartupWMClass=Veylroute\n"
            "SingleMainWindow=true\nX-VeylRoute-Portable=true\n")


def install() -> Path:
    root = portable_root()
    folder = xdg_applications_dir()
    target = folder / DESKTOP_ID
    if target.is_symlink():
        raise RuntimeError('Refusing to overwrite symbolic-link desktop entry')
    if target.exists():
        text = target.read_text(encoding='utf-8')
        if 'X-VeylRoute-Portable=true\n' not in text:
            raise RuntimeError('Refusing to overwrite an unrelated desktop entry')
    folder.mkdir(parents=True, exist_ok=True)
    content = desktop_text(root)
    temporary = target.with_name(target.name + f'.tmp-{os.getpid()}')
    try:
        temporary.write_text(content, encoding='utf-8')
        temporary.chmod(0o644)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    return target


def remove() -> bool:
    target = xdg_applications_dir() / DESKTOP_ID
    if target.is_symlink():
        raise RuntimeError('Refusing to follow a symbolic-link desktop entry')
    if not target.exists():
        return False
    text = target.read_text(encoding='utf-8')
    if 'X-VeylRoute-Portable=true\n' not in text:
        raise RuntimeError('Desktop entry is not a VeylRoute portable launcher')
    target.unlink()
    return True
