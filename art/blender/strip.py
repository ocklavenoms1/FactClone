# strip.py — lays a list of equal-size sprites in a row over a tile grid at a
# chosen zoom. General-purpose viewer for frame sequences and comparisons.
#
# Run: blender -b -P art/blender/strip.py -- --out <png> --zoom 3 <sprite.png>...

import os
import sys

import bpy
import numpy as np

BG = np.array([0.36, 0.29, 0.21, 1.0])
GRID = np.array([0.30, 0.24, 0.17, 1.0])
GAP = 12


def load(p):
    img = bpy.data.images.load(os.path.abspath(p))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def blend(dst, src, x, y):
    h, w = src.shape[:2]
    a = src[:, :, 3:4]
    dst[y:y + h, x:x + w] = src * a + dst[y:y + h, x:x + w] * (1 - a)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out = os.path.abspath(argv[argv.index("--out") + 1])
    zoom = int(argv[argv.index("--zoom") + 1]) if "--zoom" in argv else 3
    skip = {out, str(zoom)}
    paths = [p for p in argv if p.endswith(".png") and os.path.abspath(p) != out]

    imgs = [np.repeat(np.repeat(load(p), zoom, axis=0), zoom, axis=1) for p in paths]
    cw = max(i.shape[1] for i in imgs)
    ch = max(i.shape[0] for i in imgs)
    W = len(imgs) * cw + (len(imgs) + 1) * GAP
    H = ch + 2 * GAP
    canvas = np.tile(BG, (H, W, 1))
    canvas[::32, :, :] = GRID
    canvas[:, ::32, :] = GRID

    x = GAP
    for i in imgs:
        blend(canvas, i, x, GAP)
        x += cw + GAP

    img = bpy.data.images.new("strip", W, H, alpha=True)
    img.pixels = canvas.ravel().tolist()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    print(f"STRIP_SAVED: {out} ({W}x{H})")


if __name__ == "__main__":
    main()
