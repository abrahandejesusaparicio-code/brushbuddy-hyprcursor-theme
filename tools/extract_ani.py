#!/usr/bin/env python3
"""
Extract PNG frames and ANI timing from a Windows .ani cursor.

No Pillow required: Brushbuddy embeds PNG images inside CUR records inside RIFF/ACON.
ANI timing uses jiffies (1/60 second).
"""
from pathlib import Path
import argparse, struct, json

def chunks(data, start=12, end=None):
    if end is None: end = len(data)
    pos = start
    while pos + 8 <= end:
        cid = data[pos:pos+4]
        size = struct.unpack_from("<I", data, pos+4)[0]
        ps, pe = pos+8, pos+8+size
        yield cid, data[ps:pe]
        pos = pe + (size & 1)

def parse(path):
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"ACON":
        raise SystemExit("Not RIFF/ACON")
    anih = rates = seq = None
    frames = []
    for cid,payload in chunks(data):
        if cid == b"anih":
            vals = struct.unpack_from("<9I", payload, 0)
            keys = ["cbSizeOf","cFrames","cSteps","cx","cy","cBitCount","cPlanes","JifRate","flags"]
            anih = dict(zip(keys, vals))
        elif cid == b"rate":
            rates = list(struct.unpack("<" + "I"*(len(payload)//4), payload))
        elif cid == b"seq ":
            seq = list(struct.unpack("<" + "I"*(len(payload)//4), payload))
        elif cid == b"LIST" and payload[:4] == b"fram":
            fake = b"RIFF\x00\x00\x00\x00FAKE" + payload[4:]
            for ccid,cpayload in chunks(fake):
                if ccid == b"icon":
                    frames.append(cpayload)
    rates = rates or [anih["JifRate"]] * anih["cSteps"]
    seq = seq or list(range(anih["cSteps"]))
    return anih, rates, seq, frames

def png_from_icon(blob):
    reserved, typ, count = struct.unpack_from("<HHH", blob, 0)
    candidates = []
    for i in range(count):
        o=6+i*16
        w,h,_,_,p1,p2,nbytes,img_off = struct.unpack_from("<BBBBHHII",blob,o)
        W,H=w or 256,h or 256
        candidates.append((W*H,W,H,p1,p2,nbytes,img_off))
    _,W,H,p1,p2,nbytes,img_off=max(candidates)
    png=blob[img_off:img_off+nbytes]
    if png[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("Frame is not PNG-backed")
    return png, {"type":typ,"width":W,"height":H,"field1":p1,"field2":p2}

ap=argparse.ArgumentParser()
ap.add_argument("ani", type=Path)
ap.add_argument("output", type=Path)
args=ap.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
anih,rates,seq,frames=parse(args.ani)
info=[]
for i,blob in enumerate(frames):
    png,meta=png_from_icon(blob)
    (args.output/f"frame_{i:03d}.png").write_bytes(png)
    info.append(meta)
steps=[]
for i,frame in enumerate(seq):
    j=rates[i] if i < len(rates) else anih["JifRate"]
    steps.append({"step":i,"frame":frame,"jiffies":j,"milliseconds":max(1,round(j*1000/60))})
(args.output/"metadata.json").write_text(json.dumps({"anih":anih,"steps":steps,"frames":info},indent=2)+"\n")
print(f"Extracted {len(frames)} frames to {args.output}")
