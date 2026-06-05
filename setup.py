#!/usr/bin/env python3
"""
10mila Menu Bootstrap
---------------------
Run this first on the Ubuntu server:  python3 setup.py
It strips Windows CRLF from all .sh files, then runs install.sh.
Works regardless of how the files were transferred (SFTP, SCP, copy-paste).
"""

import os
import subprocess
import sys

base = os.path.dirname(os.path.abspath(__file__))

print("--- Stripping CRLF from all .sh files ---")
fixed = 0
for root, dirs, files in os.walk(base):
    for fname in files:
        if fname.endswith(".sh"):
            path = os.path.join(root, fname)
            with open(path, "rb") as f:
                content = f.read()
            cleaned = content.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            if cleaned != content:
                with open(path, "wb") as f:
                    f.write(cleaned)
                print(f"  Fixed: {os.path.relpath(path, base)}")
                fixed += 1

if fixed == 0:
    print("  No CRLF found — all files already clean.")
else:
    print(f"  {fixed} file(s) fixed.")

print("")
install = os.path.join(base, "install.sh")
sys.exit(subprocess.run(["bash", install] + sys.argv[1:]).returncode)
