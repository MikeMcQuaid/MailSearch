#!/usr/bin/env python3
"""Prepare a pinned IMAP-only SwiftMail package using Apple's TLS transport."""
import io
import json
import subprocess
import tarfile
import tempfile
from pathlib import Path

package = Path('vendor/SwiftMail')
pin = json.loads((package / 'upstream.json').read_text())
checkout = Path('.build/upstream/SwiftMail.git')
if not checkout.exists():
    checkout.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git', 'clone', '--bare', '--filter=blob:none', '--single-branch', '--branch',
                    pin['state']['version'], pin['location'], str(checkout)], check=True)
revision = pin['state']['revision']
if subprocess.run(['git', '-C', str(checkout), 'cat-file', '-e', revision + '^{commit}'],
                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
    subprocess.run(['git', '-C', str(checkout), 'fetch', pin['location'], revision], check=True)
archive = subprocess.check_output(['git', '-C', str(checkout), 'archive', revision, 'Sources/SwiftMail', 'LICENSE'])
with tempfile.TemporaryDirectory(dir='.build', prefix='swiftmail-') as temporary:
    root = Path(temporary)
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        for member in source:
            if not member.isfile():
                continue
            target = root / member.name
            assert target.resolve().is_relative_to(root.resolve())
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.extractfile(member).read())
    subprocess.run(['git', 'init', '--quiet', str(root)], check=True)
    subprocess.run(['git', '-C', str(root), 'apply', str((package / 'network-framework.patch').resolve())], check=True)
    for path in Path('script/support').glob('*.swift'):
        (root / 'Sources/SwiftMail/IMAP' / path.name).write_bytes(path.read_bytes())
    for path in (package / 'Sources').rglob('*'):
        if path.is_file() and not (root / path.relative_to(package)).exists():
            path.unlink()
    for path in root.rglob('*'):
        if not path.is_file() or '.git' in path.parts:
            continue
        target = package / path.relative_to(root)
        if not target.exists() or target.read_bytes() != path.read_bytes():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
