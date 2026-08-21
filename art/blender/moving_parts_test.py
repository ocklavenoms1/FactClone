# moving_parts_test.py — proves the recommended moving-parts approach:
# a static body sprite with a separately-rendered part sequence composited on
# top, all sharing one locked canvas and origin.
#
# Godot draws body.png, then arm_f<N>.png at the same position. No transform is
# applied to either — the existing swing interpolation picks N instead of
# computing a rotation.
#
# Run: blender -b -P art/blender/moving_parts_test.py

import os

import bpy
import numpy as np

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPRITES = os.path.join(REPO, "art", "sprites")
OUT = os.path.join(REPO, "art", "renders", "moving_parts_test.png")

FRAMES = [0, 45, 90, 135, 180]
ZOOM = 3
GAP = 12
BG = np.array([0.36, 0.29, 0.21, 1.0])
GRID = np.array([0.30, 0.24, 0.17, 1.0])


def load(p):
    img = bpy.data.images.load(p)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def over(top, bottom):
    a = top[:, :, 3:4]
    out = top * a + bottom * (1 - a)
    out[:, :, 3:4] = np.clip(top[:, :, 3:4] + bottom[:, :, 3:4] * (1 - a), 0, 1)
    return out


def blend(dst, src, x, y):
    h, w = src.shape[:2]
    a = src[:, :, 3:4]
    dst[y:y + h, x:x + w] = src * a + dst[y:y + h, x:x + w] * (1 - a)


def main():
    body = load(os.path.join(SPRITES, "inserter_body.png"))
    comps = [over(load(os.path.join(SPRITES, f"inserter_arm_f{f}.png")), body) for f in FRAMES]
    comps = [np.repeat(np.repeat(c, ZOOM, axis=0), ZOOM, axis=1) for c in comps]

    cw, ch = comps[0].shape[1], comps[0].shape[0]
    W = len(comps) * cw + (len(comps) + 1) * GAP
    H = ch + 2 * GAP
    canvas = np.tile(BG, (H, W, 1))
    canvas[::32, :, :] = GRID
    canvas[:, ::32, :] = GRID

    x = GAP
    for c in comps:
        blend(canvas, c, x, GAP)
        x += cw + GAP

    img = bpy.data.images.new("mp", W, H, alpha=True)
    img.pixels = canvas.ravel().tolist()
    img.filepath_raw = OUT
    img.file_format = "PNG"
    img.save()
    print(f"MOVING_PARTS_SAVED: {OUT} ({W}x{H}) frames={FRAMES}")


if __name__ == "__main__":
    main()
