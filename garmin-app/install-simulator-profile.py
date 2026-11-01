"""Install the private Edge 1050 runtime profile, including its WW fonts.

Compiler-only device bits do not provision the simulator. The bundle is kept in
environment secrets (not repository secrets, which have a combined size limit).
Never print its contents or put it in public caches/artifacts.
"""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import zipfile


def install(environ=os.environ):
    manifest = json.loads(environ['GARMIN_SIMULATOR_MANIFEST'])
    count = manifest['chunks']
    if not isinstance(count, int) or not 1 <= count <= 48:
        raise ValueError('Invalid simulator bundle chunk count')
    if manifest['device'] != 'edge1050' or manifest['font_set'] != 'ww':
        raise ValueError('Expected the Edge 1050 WW simulator profile')
    encoded = ''.join(environ[f'GARMIN_SIMULATOR_{i:02}'] for i in range(1, count + 1))
    payload = base64.b64decode(encoded, validate=True)
    if hashlib.sha256(payload).hexdigest() != manifest['sha256']:
        raise ValueError('Simulator bundle checksum mismatch')
    root = Path(environ['APPDATA']) / 'Garmin/ConnectIQ'
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        for entry in archive.infolist():
            target = (root / entry.filename).resolve()
            if not target.is_relative_to(root.resolve()):
                raise ValueError('Unsafe simulator bundle path')
        archive.extractall(root)
    device = root / 'Devices/edge1050'
    for filename in ('compiler.json', 'simulator.json', 'edge1050.bin'):
        if not (device / filename).is_file():
            raise ValueError('Incomplete simulator device profile')
    profile = json.loads((device / 'simulator.json').read_text(encoding='utf-8'))
    fonts = {font['filename'] + '.' + font.get('type', 'cft')
             for group in profile['fonts'] if group['fontSet'] == 'ww'
             for font in group['fonts']}
    if not fonts or any(not (root / 'Fonts' / name).is_file() for name in fonts):
        raise ValueError('Missing Edge 1050 WW simulator fonts')
    print(f'Edge 1050 simulator runtime installed; WW fonts verified: {len(fonts)}')


if __name__ == '__main__':
    install()
