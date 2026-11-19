"""Linux-only app update pipeline. No Windows 'latest' and no silent upgrades.

check: read-only stable Linux GitHub releases, verify metadata.
prepare: download a matching package and verify GitHub release asset digest and SHA256SUMS.
apply: explicit operator action; refuses active sessions, checks unchanged bytes again.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

from . import __version__

REPO = "admknight/VeylRoute"
API = f"https://api.github.com/repos/{REPO}/releases?per_page=100"
RELEASE = re.compile(r"linux-v(\d+\.\d+\.\d+)$")
HASH = re.compile(r"^[0-9a-fA-F]{64}$")
MAX_PACKAGE = 80 * 1024 * 1024
MAX_HASHES = 64 * 1024
UA = f"VeylRoute-Linux-Updater/{__version__}"


class UpdateError(RuntimeError):
    pass


def edition() -> str:
    # Installation identity is checked from the actual, imported Python module.
    path = Path(__file__).resolve()
    if str(path).startswith('/usr/lib/veylroute/veylroute/'):
        return 'deb'
    root = path.parent.parent
    if (root / 'bin' / 'veylroute').is_file() and (root / 'assets' / 'veylroute.png').is_file():
        return 'portable'
    raise UpdateError('Installation type is unknown; automatic update disabled')


def data_dir() -> Path:
    home = os.environ.get('XDG_CACHE_HOME')
    base = Path(home).expanduser() if home else Path.home() / '.cache'
    if not base.is_absolute():
        raise UpdateError('XDG_CACHE_HOME must be absolute')
    return base / 'veylroute' / 'updates'


def get(url: str, limit: int, timeout: int = 30) -> bytes:
    if not url.startswith('https://'):
        raise UpdateError('Non-HTTPS update URL blocked')
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            address = urllib.parse.urlsplit(response.geturl())
            if address.scheme != 'https' or address.hostname not in (
                'api.github.com', 'github.com', 'release-assets.githubusercontent.com',
                'objects.githubusercontent.com'):
                raise UpdateError('Release URL redirected outside trusted GitHub download hosts')
            chunks = []
            size = 0
            while True:
                part = response.read(min(65536, limit + 1 - size))
                if not part:
                    break
                size += len(part)
                if size > limit:
                    raise UpdateError('Release response exceeded size cap')
                chunks.append(part)
            return b''.join(chunks)
    except (OSError, TimeoutError) as ex:
        raise UpdateError(f'GitHub request failed: {type(ex).__name__}') from ex


def version_key(text: str) -> tuple[int, int, int]:
    if not re.fullmatch(r'\d+\.\d+\.\d+', text):
        raise UpdateError('Unsupported Linux release version')
    return tuple(map(int, text.split('.')))


def digest(asset: dict) -> str:
    raw = asset.get('digest')
    if not isinstance(raw, str) or not raw.startswith('sha256:') or not HASH.fullmatch(raw[7:]):
        raise UpdateError('GitHub release asset lacks a supported SHA-256 digest')
    return raw[7:].lower()


def asset_url(tag: str, name: str, provided: str) -> str:
    if not re.fullmatch(r'linux-v\d+\.\d+\.\d+', tag):
        raise UpdateError('Unexpected Linux release tag')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', name):
        raise UpdateError('Unexpected release filename')
    url = f'https://github.com/{REPO}/releases/download/{tag}/{name}'
    if provided != url:
        raise UpdateError('Release asset URL does not match expected GitHub location')
    return url


def release_candidate(releases: list, mode: str) -> dict | None:
    """Ignore Windows releases, experimental Linux tags and prereleases."""
    if mode not in ('deb', 'portable'):
        raise UpdateError('Unsupported Linux edition')
    choices = []
    for release in releases:
        if not isinstance(release, dict) or release.get('draft') or release.get('prerelease'):
            continue
        m = RELEASE.fullmatch(str(release.get('tag_name') or ''))
        if not m:
            continue
        version = m.group(1)
        if mode == 'deb':
            names = {f'VeylRoute-Linux-{version}-Setup.deb',
                     f'VeylRoute-Linux-{version}-Stable.deb',
                     f'VeylRoute-Linux-{version}-Preview.deb'}
        else:
            names = {f'VeylRoute-Linux-{version}-Portable.tar.gz'}
        assets = release.get('assets') or []
        packages = [x for x in assets if isinstance(x, dict) and x.get('name') in names]
        manifests = [x for x in assets if isinstance(x, dict) and x.get('name') == 'SHA256SUMS-Linux.txt']
        if len(packages) != 1 or len(manifests) != 1:
            continue
        pack, hashes = packages[0], manifests[0]
        tag = f'linux-v{version}'
        info = {'tag': tag, 'version': version, 'mode': mode,
                'filename': pack['name'],
                'url': asset_url(tag, pack['name'], pack.get('browser_download_url')),
                'sha256': digest(pack),
                'hashes_url': asset_url(tag, hashes['name'], hashes.get('browser_download_url')),
                'hashes_sha256': digest(hashes),
                'size': int(pack.get('size') or 0)}
        if info['size'] <= 1000 or info['size'] > MAX_PACKAGE:
            continue
        choices.append(info)
    if not choices:
        return None
    return max(choices, key=lambda x: version_key(x['version']))


def check(mode: str | None = None, releases: list | None = None) -> dict:
    mode = mode or edition()
    if releases is None:
        blob = get(API, 2 * 1024 * 1024)
        try:
            releases = json.loads(blob)
        except ValueError as ex:
            raise UpdateError('Invalid GitHub release metadata') from ex
    if not isinstance(releases, list):
        raise UpdateError('GitHub release list was not an array')
    candidate = release_candidate(releases, mode)
    if candidate is None:
        return {'status': 'no-linux-stable', 'mode': mode, 'current': __version__,
                'message': 'No stable Linux release for this edition; previews are excluded.'}
    current, remote = version_key(__version__), version_key(candidate['version'])
    status = 'update-available' if remote > current else ('up-to-date' if remote == current else 'local-newer')
    return {'status': status, 'mode': mode, 'current': __version__, **candidate}


def _verify_hashes(contents: bytes, filename: str, expected: str) -> None:
    rows = contents.decode('ascii', 'strict').splitlines()
    matches = []
    for row in rows:
        m = re.fullmatch(r'([0-9a-fA-F]{64})\s+\*?([A-Za-z0-9_.-]+)', row)
        if m and m.group(2) == filename:
            matches.append(m.group(1).lower())
    if matches != [expected]:
        raise UpdateError('Release manifest hash does not match GitHub asset digest')


def prepare(candidate: dict, root_dir: Path | None = None) -> Path:
    """Stages files only; does not install, elevate or touch routing."""
    if candidate.get('status') != 'update-available':
        raise UpdateError('A newer stable Linux release must be checked first')
    fresh = check(candidate['mode'])
    if fresh.get('tag') != candidate.get('tag') or fresh.get('sha256') != candidate.get('sha256'):
        raise UpdateError('The stable Linux release changed; check again')
    base = root_dir or data_dir()
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    if base.is_symlink():
        raise UpdateError('Update staging folder must not be a symlink')
    stage = base / ('stage-' + uuid.uuid4().hex)
    stage.mkdir(mode=0o700)
    try:
        manifest = get(fresh['hashes_url'], MAX_HASHES)
        if hashlib.sha256(manifest).hexdigest() != fresh['hashes_sha256']:
            raise UpdateError('GitHub checksum manifest digest mismatch')
        _verify_hashes(manifest, fresh['filename'], fresh['sha256'])
        contents = get(fresh['url'], MAX_PACKAGE, timeout=90)
        if len(contents) != fresh['size'] or hashlib.sha256(contents).hexdigest() != fresh['sha256']:
            raise UpdateError('Downloaded Linux package checksum or size mismatch')
        package = stage / fresh['filename']
        package.write_bytes(contents)
        package.chmod(0o600)
        record = {'format': 1, 'tag': fresh['tag'], 'version': fresh['version'],
                  'mode': fresh['mode'], 'filename': fresh['filename'],
                  'sha256': fresh['sha256'], 'state': 'verified', 'source': 'github.com/admknight/VeylRoute'}
        receipt = stage / 'receipt.json'
        receipt.write_text(json.dumps(record, sort_keys=True, indent=2) + '\n', encoding='utf-8')
        receipt.chmod(0o600)
        return receipt
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def _validate_receipt(receipt_path: Path) -> tuple[dict, Path]:
    if receipt_path.is_symlink() or not receipt_path.is_file():
        raise UpdateError('Update receipt does not exist or is unsafe')
    record = json.loads(receipt_path.read_text(encoding='utf-8'))
    if record.get('format') != 1 or record.get('state') != 'verified':
        raise UpdateError('Invalid verified update receipt')
    filename = record.get('filename', '')
    if not isinstance(filename, str) or not re.fullmatch(r'[A-Za-z0-9_.-]+', filename):
        raise UpdateError('Invalid receipt package name')
    package = receipt_path.parent / filename
    if package.is_symlink() or not package.is_file():
        raise UpdateError('Verified package missing or linked unexpectedly')
    if not HASH.fullmatch(str(record.get('sha256', ''))):
        raise UpdateError('Invalid receipt hash')
    if hashlib.sha256(package.read_bytes()).hexdigest() != record['sha256']:
        raise UpdateError('Staged package changed since verification')
    if record.get('source') != 'github.com/admknight/VeylRoute':
        raise UpdateError('Unrecognized staging source')
    if record.get('mode') not in ('deb', 'portable'):
        raise UpdateError('Unknown edition in receipt')
    if record.get('tag') != f"linux-v{record.get('version')}":
        raise UpdateError('Version/tag mismatch in receipt')
    if version_key(record['version']) <= version_key(__version__):
        raise UpdateError('No newer Linux version staged')
    return record, package


def assert_idle() -> None:
    from . import app
    if app.STATE.exists() or app.PENDING.exists():
        raise UpdateError('Disconnect/recover before updating: session files still exist')
    if os.geteuid() == 0:
        if app.has_guard() or app.has_nat():
            raise UpdateError('VeylRoute firewall still active; run recovery before updating')


def wait_for_gui(pid: int) -> None:
    if pid <= 0:
        return
    if pid == os.getpid():
        raise UpdateError('Refusing to wait on own process')
    for _ in range(200):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    raise UpdateError('GUI did not exit before update; no files replaced')


def portable_apply(archive: Path, root: Path, version: str) -> str:
    """Bounded replacement with pre-copy backups and rollback on error."""
    if not (root / 'bin' / 'veylroute').is_file() or not (root / 'veylroute' / 'app.py').is_file():
        raise UpdateError('Portable target does not match expected layout')
    base = root.resolve()
    with tarfile.open(archive, 'r:gz') as tf:
        payload = f'veylroute-linux-{version}/'
        names = set()
        copied = []
        total = 0
        for member in tf.getmembers():
            name = member.name
            if not name.startswith(payload) or member.issym() or member.islnk() or member.isdev():
                raise UpdateError('Untrusted portable archive entry')
            relative = name[len(payload):]
            if relative == '' and member.isdir():
                continue
            raw_parts = relative.split('/')
            if '\\' in relative or any(x in ('', '.', '..') for x in raw_parts if not (x == '' and member.isdir() and raw_parts[-1] == '')):
                raise UpdateError('Portable archive path traversal rejected')
            pieces = Path(relative).parts
            if not pieces or any(x in ('', '.', '..') for x in pieces):
                raise UpdateError('Portable archive path traversal rejected')
            if not member.isdir() and not member.isfile():
                raise UpdateError('Unexpected archive entry type')
            if member.isdir():
                continue
            if relative in names:
                raise UpdateError('Duplicate portable archive path')
            names.add(relative)
            total += member.size
            if member.size > 20*1024*1024 or total > 75*1024*1024:
                raise UpdateError('Portable archive exceeds extraction limits')
            if not (relative.startswith(('bin/','veylroute/','assets/','packaging/'))
                    or relative in ('README.md', 'LICENSE', 'ASSET-PROVENANCE.md')):
                raise UpdateError('Portable archive contains unauthorized path')
            copied.append((relative, member))
        if not {'bin/veylroute', 'veylroute/app.py', 'veylroute/updates.py',
                'veylroute/__init__.py', 'assets/veylroute.png'}.issubset(names):
            raise UpdateError('Portable archive lacks required application files')
        version_member = next(member for rel, member in copied if rel == 'veylroute/__init__.py')
        version_source = tf.extractfile(version_member)
        if version_source is None or f'__version__ = "{version}"'.encode('ascii') not in version_source.read(10000):
            raise UpdateError('Portable archive does not match target version')
        # Stage content under the current user's update folder, not the application tree.
        backup = archive.parent / ('backup-' + uuid.uuid4().hex)
        backup.mkdir(mode=0o700)
        touched = []
        try:
            for rel, member in copied:
                dest = base / rel
                if not dest.resolve().is_relative_to(base) or dest.is_symlink():
                    raise UpdateError('Unsafe destination path in portable installation')
                existed = dest.is_file()
                if existed:
                    save = backup / rel
                    save.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(dest, save)
                touched.append((rel, existed))
            modified = []
            try:
                for rel, member in copied:
                    dest = base / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    # Register first to recover even partially overwritten data.
                    modified.append((rel, next(old for key, old in touched if key == rel)))
                    source = tf.extractfile(member)
                    if source is None:
                        raise UpdateError('Unextractable application file')
                    with dest.open('wb') as out:
                        shutil.copyfileobj(source, out)
                    dest.chmod(0o755 if rel.startswith('bin/') else 0o644)
                return f'Portable application files replaced; backup saved: {backup}'
            except Exception as ex:
                errors = []
                for rel, existed in reversed(modified):
                    try:
                        dest = base / rel
                        if existed:
                            shutil.copy2(backup / rel, dest)
                        else:
                            dest.unlink(missing_ok=True)
                    except OSError as err:
                        errors.append(str(err))
                if errors:
                    raise UpdateError(f'Update failed; incomplete rollback: {errors}') from ex
                raise UpdateError('Update failed and previous app files restored') from ex
        except Exception:
            # A pre-copy validation error leaves the application unmodified.
            raise


def apply(receipt_path: Path, parent_pid: int = 0) -> str:
    wait_for_gui(parent_pid)
    record, package = _validate_receipt(receipt_path)
    mode = edition()
    if record['mode'] != mode:
        raise UpdateError('Package edition does not match current installation')
    # Reconfirm the staged hash against live GitHub metadata before elevation.
    # A user-editable receipt alone is never treated as release authority.
    latest = check(mode)
    if (latest.get('status') != 'update-available' or
            latest.get('tag') != record['tag'] or
            latest.get('filename') != record['filename'] or
            latest.get('sha256') != record['sha256']):
        raise UpdateError('Staged package no longer matches the latest verified Linux release')
    assert_idle()
    if mode == 'deb':
        if os.geteuid() != 0:
            raise UpdateError('Setup-based update requires administrator authorization')
        cmd = ['/usr/bin/apt-get', 'install', '-y', '--', str(package.resolve())]
        result = subprocess.run(cmd, timeout=240, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, check=False)
        if result.returncode:
            raise UpdateError(f'Debian upgrade exited with code {result.returncode}')
        return 'Debian installer upgrade completed; restart VeylRoute.'
    return portable_apply(package, Path(__file__).resolve().parent.parent, record['version'])
