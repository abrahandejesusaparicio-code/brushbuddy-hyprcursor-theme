#!/usr/bin/env python3
"""
Create a PATCHED COPY of an extracted Bibata hyprcursor working-state tree.

V2 policy established on Ace's machine:
- keep only the five proven meta.hl keys
- provide an exact 24px raster AND the original 256px raster
- preserve Bibata's existing directory names and define_override aliases
- never modify the input tree
- dry-run by default
"""
from pathlib import Path
import argparse, shutil, sys
from PIL import Image

KIT = Path(__file__).resolve().parents[1]
EXTRACTED = KIT / "extracted"

ALIASES = {
    "classic": {"left_ptr","default","arrow","top_left_arrow"},
    "pointer": {"pointer","hand","hand1","hand2","link","pointing_hand"},
    "resize_pointer": {
        "top_side",
        "bottom_side",
        "left_side",
        "right_side",
        "top_left_corner",
        "top_right_corner",
        "bottom_left_corner",
        "bottom_right_corner",
        "fd_double_arrow",
        "bd_double_arrow",
        "sb_h_double_arrow",
        "sb_v_double_arrow",
    },
    "wait": {"wait","watch","progress","left_ptr_watch","half-busy"},
}
HOTSPOTS = {
    "classic": ("0.4688","0.4063"),
    "pointer": ("0.4570","0.3906"),
    "resize_pointer": ("0.4570","0.3906"),
    "wait": ("0.5","0.5"),
}
DELAYS = {"classic":117, "pointer":83, "resize_pointer":83, "wait":83}
FRAME_COUNTS = {"classic":7, "pointer":2, "resize_pointer":2, "wait":46}
SOURCE_KIND = {
    "classic": "classic",
    "pointer": "pointer",
    "resize_pointer": "pointer",
    "wait": "wait",
}

def value(line):
    return line.split("=",1)[1].split("#",1)[0].strip()

def manifest_cursor_dir(root):
    mf=root/"manifest.hl"
    if not mf.exists():
        raise SystemExit(f"Missing {mf}")
    for line in mf.read_text(errors="replace").splitlines():
        if line.strip().startswith("cursors_directory") and "=" in line:
            return value(line)
    raise SystemExit("manifest.hl has no cursors_directory")

def read_meta(shape):
    meta=shape/"meta.hl"
    overrides=[]
    if meta.exists():
        for line in meta.read_text(errors="replace").splitlines():
            s=line.strip()
            if s.startswith("define_override") and "=" in s:
                overrides.append(value(s))
    return overrides

def classify(shape):
    names={shape.name,*read_meta(shape)}
    hits={k:sorted(names & aliases) for k,aliases in ALIASES.items() if names & aliases}
    return names,hits

def make24(src,dst):
    with Image.open(src) as im:
        im.convert("RGBA").resize((24,24), Image.Resampling.LANCZOS).save(dst,"PNG")

def write_brushbuddy_shape(target, kind, overrides):
    # Preserve meta only until we replace it; remove raster assets in this matched shape.
    for f in list(target.iterdir()):
        if f.is_file() and f.name != "meta.hl" and f.suffix.lower() in {".png",".svg",".webp"}:
            f.unlink()

    lines=[
        "resize_algorithm = bilinear",
        f"hotspot_x = {HOTSPOTS[kind][0]}",
        f"hotspot_y = {HOTSPOTS[kind][1]}",
    ]
    for o in overrides:
        lines.append(f"define_override = {o}")

    # 24px exact match first, then 256px original source.
    # Repeated entries of one size are animation frames.
    for size in (24,256):
        for i in range(FRAME_COUNTS[kind]):
            src=EXTRACTED/SOURCE_KIND[kind]/f"frame_{i:03d}.png"
            fn=f"frame_{size}_{i:03d}.png"
            dst=target/fn
            if size == 24:
                make24(src,dst)
            else:
                shutil.copy2(src,dst)
            lines.append(f"define_size = {size}, {fn}, {DELAYS[kind]}")

    (target/"meta.hl").write_text("\n".join(lines)+"\n")

ap=argparse.ArgumentParser()
ap.add_argument("bibata_source", type=Path,
                help="hyprcursor-util --extract working-state directory")
ap.add_argument("output", type=Path, nargs="?",
                help="destination patched working-state directory")
ap.add_argument("--apply", action="store_true",
                help="actually create the patched copy")
ap.add_argument("--force", action="store_true",
                help="replace output if it already exists")
args=ap.parse_args()

src=args.bibata_source.expanduser().resolve()
cdir=manifest_cursor_dir(src)
shapes_root=src/cdir
if not shapes_root.is_dir():
    raise SystemExit(f"Missing cursor directory: {shapes_root}")

matches={"classic":[],"pointer":[],"resize_pointer":[],"wait":[]}
conflicts=[]
print(f"Bibata source: {src}")
print(f"cursors_directory: {cdir}")
print("\nDetection:")
for shape in sorted((p for p in shapes_root.iterdir() if p.is_dir()), key=lambda p:p.name):
    names,hits=classify(shape)
    if len(hits)>1:
        conflicts.append((shape,hits))
    for k in hits:
        matches[k].append(shape)
        print(f"  {k:7s} <- {shape.name:30s} via {', '.join(hits[k])}")

for k in matches:
    if not matches[k]:
        print(f"  WARNING: no {k} shape detected")

if conflicts:
    print("\nABORT: some directories matched more than one category:")
    for shape,hits in conflicts:
        print(" ",shape.name,hits)
    sys.exit(2)

if not args.apply:
    print("\nDry run only.")
    print("Claude/Ace: verify these matches against the extracted working Bibata tree.")
    print()
    print("IMPORTANT VISUAL TRADEOFF:")
    print("  All 12 resize directions matched as 'resize_pointer' will use the SAME")
    print("  2-frame Brushbuddy hand animation. Horizontal/vertical/diagonal resize")
    print("  directions will no longer be visually distinguishable by cursor shape.")
    print()
    print("If correct and intentional, re-run with --apply and an output path.")
    sys.exit(0)

if args.output is None:
    raise SystemExit("Output path is required with --apply")

out=args.output.expanduser().resolve()
if out.exists():
    if not args.force:
        raise SystemExit(f"Output exists: {out} (use --force to replace it)")
    shutil.rmtree(out)

shutil.copytree(src,out)
out_shapes=out/cdir

for kind, src_shapes in matches.items():
    for old_shape in src_shapes:
        target=out_shapes/old_shape.name
        overrides=read_meta(old_shape)  # preserve Bibata alias coverage exactly
        write_brushbuddy_shape(target,kind,overrides)
        print(f"Patched {kind}: {target}")

print(f"\nPatched COPY created at: {out}")
print("Original Bibata working-state was not modified.")
print("Generated Brushbuddy shapes contain explicit 24px and 256px variants.")
