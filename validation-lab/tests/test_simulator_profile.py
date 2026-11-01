import base64
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile


spec = importlib.util.spec_from_file_location(
    'simulator_profile', Path(__file__).resolve().parents[2]
    / 'garmin-app/install-simulator-profile.py')
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class SimulatorProfileTests(unittest.TestCase):
    def bundle(self, root, *, missing_font=False, unsafe=False):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr('Devices/edge1050/compiler.json', '{}')
            archive.writestr('Devices/edge1050/edge1050.bin', b'device bits')
            archive.writestr('Devices/edge1050/simulator.json', json.dumps({
                'fonts': [{'fontSet': 'ww', 'fonts': [
                    {'filename': 'fixture', 'type': 'ttf'}]}]}))
            if not missing_font:
                archive.writestr('Fonts/fixture.ttf', b'font fixture')
            if unsafe:
                archive.writestr('../../../escaped.txt', b'bad')
        payload = buffer.getvalue()
        encoded = base64.b64encode(payload).decode()
        # Exercise joining multiple chunks, including a non-base64 boundary.
        return {'APPDATA': str(root), 'GARMIN_SIMULATOR_01': encoded[:7],
                'GARMIN_SIMULATOR_02': encoded[7:],
                'GARMIN_SIMULATOR_MANIFEST': json.dumps({
                    'chunks': 2, 'device': 'edge1050', 'font_set': 'ww',
                    'sha256': hashlib.sha256(payload).hexdigest()})}

    def test_installs_complete_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                profile.install(self.bundle(directory))
            self.assertTrue((Path(directory) / 'Garmin/ConnectIQ/Fonts/fixture.ttf').is_file())

    def test_checksum_failure_writes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            env = self.bundle(directory)
            manifest = json.loads(env['GARMIN_SIMULATOR_MANIFEST'])
            manifest['sha256'] = '0' * 64
            env['GARMIN_SIMULATOR_MANIFEST'] = json.dumps(manifest)
            with self.assertRaisesRegex(ValueError, 'checksum'):
                profile.install(env)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_compiler_only_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'fonts'):
                profile.install(self.bundle(directory, missing_font=True))

    def test_unsafe_archive_writes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Unsafe'):
                profile.install(self.bundle(directory, unsafe=True))
            self.assertEqual(list(Path(directory).iterdir()), [])
