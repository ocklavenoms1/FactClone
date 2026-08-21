# contact_sheet.py — composes rendered sprites side by side at true in-game
# size (top row) and 4x nearest-neighbor zoom (bottom row) over a dirt-colored
# 32 px tile grid, for the consistency verdict.
#
# Run:
#   blender -b -P art/blender/contact_sheet.py -- --out art/renders/contact_sheet.png \
#       art/sprites/chest.png art/sprites/smelter_idle.png ...

import os
import sys

import bpy
import numpy as np

TILE = 32
GAP = 16
DIRT = np.array([0.36, 0.29, 0.21, 1.0])
GRID = np.array([0.30, 0.24, 0.17, 1.0])


def load_rgba(path):
    img = bpy.data.images.load(os.path.abspath(path))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def blend(dst, src, x, y):
    h, w = src.shape[:2]
    a = src[:, :, 3:4]
    region = dst[y:y + h, x:x + w]
    dst[y:y + h, x:x + w] = src * a + region * (1 - a)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out = os.path.abspath(argv[argv.index("--out") + 1])
    paths = [p for p in argv if not p.startswith("--") and p != out and p.endswith(".png")]
    paths = [p for p in paths if os.path.abspath(p) != out]

    sprites = [load_rgba(p) for p in paths]
    zooms = [np.repeat(np.repeat(s, 4, axis=0), 4, axis=1) for s in sprites]

    def row_dims(imgs):
        w = sum(i.shape[1] for i in imgs) + GAP * (len(imgs) + 1)
        h = max(i.shape[0] for i in imgs)
        return w, h

    w1, h1 = row_dims(sprites)
    w4, h4 = row_dims(zooms)
    W = max(w1, w4)
    H = h1 + h4 + GAP * 3

    canvas = np.tile(DIRT, (H, W, 1))
    canvas[::TILE, :, :] = GRID
    canvas[:, ::TILE, :] = GRID

    # bottom-up pixel space: zoom row at bottom, true-size row above it
    x = GAP
    for z in zooms:
        blend(canvas, z, x, GAP)
        x += z.shape[1] + GAP
    x = GAP
    for s in sprites:
        blend(canvas, s, x, GAP * 2 + h4)
        x += s.shape[1] + GAP

    img = bpy.data.images.new("sheet", W, H, alpha=True)
    img.pixels = canvas.ravel().tolist()
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    print(f"SHEET_SAVED: {out} ({W}x{H})")


if __name__ == "__main__":
    main()
