#!/usr/bin/python3
"""Record the source revision in the app's input Info.plist."""
import plistlib
import subprocess
import sys
from pathlib import Path

info = plistlib.loads(Path("App/Info.plist").read_bytes())
info["MailSearchCommit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
info["MailSearchDirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip())
target = Path(sys.argv[1])
contents = plistlib.dumps(info)
if not target.exists() or target.read_bytes() != contents:
    target.write_bytes(contents)
