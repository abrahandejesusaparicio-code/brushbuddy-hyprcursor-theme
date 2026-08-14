#!/usr/bin/env python3
from pathlib import Path
import argparse, re, sys
from collections import Counter

ap=argparse.ArgumentParser()
ap.add_argument("theme", type=Path)
args=ap.parse_args()
root=args.theme
manifest=root/"manifest.hl"
if not manifest.exists(): raise SystemExit("missing manifest.hl")
m=re.search(r"(?m)^\s*cursors_directory\s*=\s*([^#\n]+)",manifest.read_text())
if not m: raise SystemExit("missing cursors_directory")
cdir=root/m.group(1).strip()
if not cdir.is_dir(): raise SystemExit(f"missing {cdir}")

ok=True
allowed={"resize_algorithm","hotspot_x","hotspot_y","define_override","define_size"}

for shape in sorted(p for p in cdir.iterdir() if p.is_dir()):
    meta=shape/"meta.hl"
    if not meta.exists():
        print("missing meta:",shape); ok=False; continue
    txt=meta.read_text()
    sizes=[]
    for n,line in enumerate(txt.splitlines(),1):
        s=line.split("#",1)[0].strip()
        if not s: continue
        if "=" not in s:
            print(f"{meta}:{n}: malformed: {line}"); ok=False; continue
        key=s.split("=",1)[0].strip()
        if key not in allowed:
            print(f"{meta}:{n}: unexpected key {key!r}"); ok=False
        if key == "define_size":
            parts=[p.strip() for p in s.split("=",1)[1].split(",")]
            if len(parts) not in (2,3):
                print(f"{meta}:{n}: bad define_size: {line}"); ok=False; continue
            try:
                size=int(parts[0])
                sizes.append(size)
            except ValueError:
                print(f"{meta}:{n}: invalid size: {parts[0]}"); ok=False
                continue
            img=shape/parts[1]
            if not img.exists():
                print(f"{meta}:{n}: missing image {parts[1]}"); ok=False
            if len(parts)==3:
                try:
                    timeout=int(parts[2])
                    if timeout <= 0:
                        print(f"{meta}:{n}: non-positive animation timeout"); ok=False
                except ValueError:
                    print(f"{meta}:{n}: invalid timeout {parts[2]}"); ok=False
    for required in (24,256):
        if required not in sizes:
            print(f"{meta}: missing required {required}px define_size variant")
            ok=False

print("OK" if ok else "FAILED")
sys.exit(0 if ok else 1)
