# rotation_test.py — settles the open question: for a 4-way building, render
# four times with the MODEL rotated, or render once and rotate the SPRITE in
# Godot?
#
# Builds a 2-row comparison:
#   row A (top)    four true 3D renders at yaw 0/90/180/270
#   row B (bottom) one render (yaw 0) rotated 90/180/270 in 2D, as Godot would
#
# Run: blender -b -P art/blender/rotation_test.py

import os
import sys

import bpy
import numpy as np

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPRITES = os.path.join(REPO, "art", "sprites")
OUT = os.path.join(REPO, "art", "renders", "rotation_test.png")

ZOOM = 4
GAP = 12
BG = np.array([0.36, 0.29, 0.21, 1.0])
GRID = np.array([0.30, 0.24, 0.17, 1.0])


def load(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def blend(dst, src, x, y):
    h, w = src.shape[:2]
    a = src[:, :, 3:4]
    dst[y:y + h, x:x + w] = src * a + dst[y:y + h, x:x + w] * (1 - a)


def main():
    true3d = [load(os.path.join(SPRITES, f"dir_test_yaw{y}.png")) for y in (0, 90, 180, 270)]
    base = true3d[0]
    # np.rot90 on the image array == rotating the sprite in-engine
    naive = [base, np.rot90(base, 1), np.rot90(base, 2), np.rot90(base, 3)]

    def up(a):
        return np.repeat(np.repeat(a, ZOOM, axis=0), ZOOM, axis=1)

    true3d = [up(a) for a in true3d]
    naive = [up(a) for a in naive]

    cell_w = true3d[0].shape[1]
    cell_h = true3d[0].shape[0]
    W = 4 * cell_w + 5 * GAP
    H = 2 * cell_h + 3 * GAP

    canvas = np.tile(BG, (H, W, 1))
    canvas[::32, :, :] = GRID
    canvas[:, ::32, :] = GRID

    # bottom row of the array is drawn first (Blender pixel space is bottom-up),
    # so `naive` goes in first and ends up visually BELOW `true3d`.
    x = GAP
    for a in naive:
        blend(canvas, a, x, GAP)
        x += cell_w + GAP
    x = GAP
    for a in true3d:
        blend(canvas, a, x, GAP * 2 + cell_h)
        x += cell_w + GAP

    img = bpy.data.images.new("rot", W, H, alpha=True)
    img.pixels = canvas.ravel().tolist()
    img.filepath_raw = OUT
    img.file_format = "PNG"
    img.save()
    print(f"ROT_TEST_SAVED: {OUT} ({W}x{H})  top=true-3D-renders  bottom=2D-rotated")


if __name__ == "__main__":
    main()
