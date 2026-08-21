"""Premultiplied LANCZOS downsample - system Python, needs Pillow + numpy.

    python art/tools/downsample.py art/sprites/<name>.json
    python art/tools/downsample.py --check art/renders/_calib.json

Two things happen here and both matter.

1. The vertical squash is undone. The master was rendered at
   (w*32*SS) x (h*32*SS*0.86603); resampling to (w*32) x (h*32) stretches it
   back to square in the SAME resample, so the image is only ever filtered
   once. Two resamples would double-soften it.

2. Alpha is premultiplied before resizing and unpremultiplied after. Blender
   writes straight (unassociated) alpha, where the RGB of fully transparent
   pixels is black. Resampling that bleeds black into every silhouette edge and
   the sprite gets a dark fringe. This is the single biggest difference between
   crisp and muddy at 32 px.
"""

import json
import os
import sys

import numpy as np
from PIL import Image


def downsample(master_path, out_path, sprite_px):
    src = Image.open(master_path).convert("RGBA")
    a = np.asarray(src).astype(np.float32) / 255.0

    rgb, alpha = a[..., :3], a[..., 3:4]
    pre = np.concatenate([rgb * alpha, alpha], axis=-1)      # premultiply

    pre_img = Image.fromarray((np.clip(pre, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA")
    small = pre_img.resize(tuple(sprite_px), Image.Resampling.LANCZOS)

    b = np.asarray(small).astype(np.float32) / 255.0
    ba = b[..., 3:4]
    with np.errstate(divide="ignore", invalid="ignore"):      # unpremultiply
        brgb = np.where(ba > 1e-4, b[..., :3] / np.maximum(ba, 1e-6), 0.0)
    out = np.concatenate([np.clip(brgb, 0, 1), np.clip(ba, 0, 1)], axis=-1)

    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA").save(out_path)
    return out


def opaque_bbox(rgba, thresh=0.5):
    """Bounding box of pixels with alpha above thresh, as (w, h)."""
    alpha = rgba[..., 3]
    ys, xs = np.nonzero(alpha > thresh)
    if len(xs) == 0:
        return (0, 0), None
    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    return (x1 - x0 + 1, y1 - y0 + 1), (x0, y0, x1, y1)


def main():
    args = sys.argv[1:]
    check = "--check" in args
    args = [a for a in args if not a.startswith("--")]
    if not args:
        print("usage: downsample.py [--check] <meta.json>")
        return 1

    meta_path = os.path.abspath(args[0])
    with open(meta_path) as f:
        meta = json.load(f)

    repo = os.path.abspath(os.path.join(os.path.dirname(meta_path), "..", ".."))

    def resolve(p):
        return p if os.path.isabs(p) else os.path.join(repo, p)

    masters = meta.get("masters") or [{"master": meta["master"], "sprite": meta["sprite"]}]
    rc = 0
    for m in masters:
        mp, sp = resolve(m["master"]), resolve(m["sprite"])
        if not os.path.exists(mp):
            print(f"MISSING master {mp}")
            rc = 1
            continue
        out = downsample(mp, sp, meta["sprite_px"])
        (w, h), _ = opaque_bbox(out)
        print(f"DOWNSAMPLED {os.path.basename(sp)} {meta['sprite_px'][0]}x{meta['sprite_px'][1]} bbox={w}x{h}")

        if check:
            ew, eh = meta["expect_bbox"]
            if (w, h) == (ew, eh):
                print(f"CALIBRATION PASS  bbox {w}x{h} == expected {ew}x{eh}")
            else:
                print(f"CALIBRATION FAIL  bbox {w}x{h} != expected {ew}x{eh}")
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
