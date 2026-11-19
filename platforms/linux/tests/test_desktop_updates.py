"""Linux desktop parity, update trust-chain and reversible copy tests (offline)."""
from __future__ import annotations

import hashlib
import io
import json
import os
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from veylroute import desktop, settings, tray, updates


def asset(name: str, content: bytes) -> dict:
    return {'name': name, 'browser_download_url':
            f'https://github.com/{updates.REPO}/releases/download/linux-v0.3.0/{name}',
            'digest': 'sha256:' + hashlib.sha256(content).hexdigest(),
            'size': len(content)}


class DesktopTests(unittest.TestCase):
    def test_desktop_entry_has_custom_icon_and_wmclass(self):
        root = Path('/tmp/VeylRoute demo')
        content = desktop.desktop_text(root)
        self.assertIn('Icon=/tmp/VeylRoute demo/assets/veylroute.png', content)
        self.assertIn('Exec="/tmp/VeylRoute demo/bin/veylroute-gui"', content)
        self.assertIn('StartupWMClass=Veylroute', content)
        self.assertIn('X-VeylRoute-Portable=true', content)
        self.assertNotIn('Scopewise', content)
        with self.assertRaises(RuntimeError):
            desktop.desktop_text(Path('/tmp/unsafe\nexec'))

    def test_portable_menu_install_replace_only_own_and_remove(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'app'
            (root / 'bin').mkdir(parents=True)
            (root / 'assets').mkdir()
            (root / 'bin/veylroute-gui').write_text('#!/bin/sh\n')
            (root / 'assets/veylroute.png').write_bytes(b'PNG')
            env = {'XDG_DATA_HOME': str(Path(tmp) / 'userdata')}
            with patch.dict(os.environ, env), patch.object(desktop, 'portable_root', return_value=root):
                target = desktop.install()
                self.assertEqual(target.name, 'veylroute-portable.desktop')
                self.assertIn(str(root), target.read_text())
                desktop.install()
                self.assertTrue(desktop.remove())
                self.assertFalse(desktop.remove())
                target.write_text('[Desktop Entry]\nName=Other App\n')
                with self.assertRaises(RuntimeError):
                    desktop.install()
                with self.assertRaises(RuntimeError):
                    desktop.remove()

    def test_saved_preferences_do_not_persist_bridge_path(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'XDG_CONFIG_HOME': tmp}):
            saved = settings.save({'exit_country':'US', 'minimize_to_tray':True,
                                   'bridge_path':'/private/bridges.txt'})
            self.assertEqual(settings.load(), {'exit_country':'US', 'minimize_to_tray':True})
            self.assertNotIn('private', saved.read_text())
            self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(ValueError):
                settings.save({'exit_country': 'US;ExitNodes', 'minimize_to_tray':False})
            saved.unlink()
            saved.symlink_to(Path(tmp) / 'bogus')
            with self.assertRaises(ValueError):
                settings.save({'exit_country': 'auto', 'minimize_to_tray':False})

    def test_tray_backend_dispatches_callbacks_and_status_icon(self):
        import sys
        import types
        class FakeIcon:
            def __init__(self, name, image, title, menu):
                self.icon = image
                self.title = title
                self.menu = menu
                self.started = False
                self.stopped = False
            def run(self):
                self.started = True
            def stop(self):
                self.stopped = True
        fake = types.SimpleNamespace(
            Icon=FakeIcon,
            Menu=lambda *items: items,
            MenuItem=lambda label, callback, **kw: (label, callback),
        )
        events = []
        class Root:
            def after(self, delay, callback):
                callback()
        with patch.dict(sys.modules, {'pystray': fake}):
            manager = tray.Tray(Root(), lambda: events.append('open'),
                                lambda: events.append('disconnect'),
                                lambda: events.append('exit'))
            self.assertTrue(manager.start())
            self.assertEqual(manager.backend, 'pystray')
            manager.icon.menu[1][1]()
            manager.set_state('connected')
            self.assertIn('connected', manager.icon.title)
            self.assertEqual(events, ['disconnect'])
            icon = manager.icon
            manager.stop()
            self.assertTrue(icon.stopped)

    def test_state_icon_files_are_real_pngs(self):
        for state in tray.STATES:
            data = tray.artwork(state).read_bytes()
            self.assertTrue(data.startswith(b'\x89PNG\r\n\x1a\n'))


class LinuxUpdateTests(unittest.TestCase):
    def make_release(self, *, tag='linux-v0.3.0', prerelease=False):
        version = tag.removeprefix('linux-v')
        deb = f'VeylRoute-Linux-{version}-Setup.deb'
        content = b'this is a developer-test package\n' * 100
        manifest = f'{hashlib.sha256(content).hexdigest()}  {deb}\n'.encode()
        return {'tag_name':tag, 'prerelease':prerelease, 'draft':False,
                'assets':[asset(deb,content),asset('SHA256SUMS-Linux.txt',manifest)]}, content, manifest

    def test_linux_stable_selection_excludes_windows_and_previews(self):
        release, _, _ = self.make_release()
        preview, _, _ = self.make_release(prerelease=True)
        windows = {'tag_name':'v9.0.0', 'prerelease':False, 'draft':False, 'assets':release['assets']}
        selected = updates.release_candidate([preview, windows, release], 'deb')
        self.assertEqual(selected['version'],'0.3.0')
        self.assertEqual(selected['mode'],'deb')
        self.assertEqual(updates.check('deb', [preview, windows])['status'],'no-linux-stable')
        self.assertEqual(updates.check('deb', [release])['status'],'update-available')
        self.assertIsNone(updates.release_candidate([release], 'portable'))

    def test_reject_asset_url_or_digest_mismatch(self):
        release, _, _ = self.make_release()
        release['assets'][0]['browser_download_url']='https://evil.example/update.deb'
        with self.assertRaises(updates.UpdateError):
            updates.release_candidate([release], 'deb')
        release, _, _ = self.make_release()
        release['assets'][0]['digest']=None
        with self.assertRaises(updates.UpdateError):
            updates.release_candidate([release], 'deb')

    def test_verified_download_and_tamper_detection(self):
        release, package, manifest = self.make_release()
        choice = updates.check('deb', [release])
        contents={choice['url']:package, choice['hashes_url']:manifest}
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(updates, 'check', return_value=choice), \
                 patch.object(updates, 'get', side_effect=lambda url, *_args, **_kw: contents[url]):
                receipt=updates.prepare(choice, Path(tmp))
            record, path=updates._validate_receipt(receipt)
            self.assertEqual(record['mode'],'deb')
            self.assertEqual(path.read_bytes(),package)
            path.write_bytes(b'tampered')
            with self.assertRaisesRegex(updates.UpdateError, 'changed'):
                updates._validate_receipt(receipt)

    def test_wrong_manifest_hash_is_rejected_before_package_download(self):
        release, package, manifest = self.make_release()
        choice = updates.check('deb', [release])
        with tempfile.TemporaryDirectory() as tmp, \
             patch.object(updates, 'check', return_value=choice), \
             patch.object(updates, 'get', return_value=b'bad manifest'):
            with self.assertRaisesRegex(updates.UpdateError, 'digest mismatch'):
                updates.prepare(choice, Path(tmp))
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def portable_tar(self, path, version='0.3.0'):
        entries = {
            'bin/veylroute': b'#!/usr/bin/env python3\n',
            'veylroute/app.py': b'# new app\n',
            'veylroute/updates.py': b'# update helper\n',
            'veylroute/__init__.py': f'__version__ = "{version}"\n'.encode(),
            'assets/veylroute.png': b'icon bytes',
            'README.md': b'docs',
        }
        with tarfile.open(path, 'w:gz') as archive:
            for rel, value in entries.items():
                data=io.BytesIO(value)
                info=tarfile.TarInfo(f'veylroute-linux-{version}/{rel}')
                info.size=len(value)
                archive.addfile(info, data)
        return entries

    def test_portable_update_preserves_unrelated_user_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'portable'
            (root/'bin').mkdir(parents=True)
            (root/'veylroute').mkdir()
            (root/'bin/veylroute').write_text('old')
            (root/'veylroute/app.py').write_text('old')
            (root/'config').mkdir()
            (root/'config/private.txt').write_text('DO NOT TOUCH')
            archive=Path(tmp)/'stage.tar.gz'
            self.portable_tar(archive)
            result=updates.portable_apply(archive, root, '0.3.0')
            self.assertIn('files replaced',result)
            self.assertEqual((root/'config/private.txt').read_text(),'DO NOT TOUCH')
            self.assertIn('# new app', (root/'veylroute/app.py').read_text())

    def test_portable_partial_copy_rolls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'portable'
            (root/'bin').mkdir(parents=True)
            (root/'veylroute').mkdir()
            (root/'bin/veylroute').write_bytes(b'old-start')
            (root/'veylroute/app.py').write_bytes(b'old-app')
            archive=Path(tmp)/'stage.tar.gz'
            self.portable_tar(archive)
            original=updates.shutil.copyfileobj
            calls=0
            def corrupt_and_fail(src, dst):
                nonlocal calls
                calls+=1
                if calls==2:
                    dst.write(b'partially overwritten')
                    raise OSError('simulated interruption')
                return original(src,dst)
            with patch.object(updates.shutil,'copyfileobj',side_effect=corrupt_and_fail):
                with self.assertRaisesRegex(updates.UpdateError,'restored'):
                    updates.portable_apply(archive, root, '0.3.0')
            self.assertEqual((root/'bin/veylroute').read_bytes(),b'old-start')
            self.assertEqual((root/'veylroute/app.py').read_bytes(),b'old-app')

    def test_archive_traversal_and_wrong_version_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'portable'
            (root/'bin').mkdir(parents=True)
            (root/'veylroute').mkdir()
            (root/'bin/veylroute').write_text('old')
            (root/'veylroute/app.py').write_text('old')
            tar=Path(tmp)/'wrong.tar.gz'
            self.portable_tar(tar,version='0.2.9')
            with self.assertRaisesRegex(updates.UpdateError,'Untrusted'):
                updates.portable_apply(tar,root,'0.3.0')
            self.assertEqual((root/'bin/veylroute').read_text(),'old')


if __name__ == '__main__':
    unittest.main()
