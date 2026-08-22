"""Compose the palette swatch renders into one comparison board.

    python art/tools/palette_board.py --sets undistorted separable5

Downsamples each 4x master through the real premultiplied LANCZOS path, then
lays out per palette set: the five chips at TRUE in-game size, the same at 4x,
and the three proxy buildings at 3x. Neutral mid-grey ground, 32 px grid.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from downsample import downsample  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BG = (128, 128, 128, 255)
GRID = (118, 118, 118, 255)
GAP = 12

CHIPS = ["fieldstone", "wrought_iron", "weathered_oak", "leather", "verdigris"]
PROXIES = ["proxy_chest", "proxy_pole", "proxy_smelter"]


def to_sprite(master, tiles_w, tiles_h, tmp):
    out = os.path.join(tmp, os.path.basename(master).replace("_4x", ""))
    downsample(master, out, (tiles_w * 32, tiles_h * 32))
    return Image.open(out).convert("RGBA")


def up(im, z):
    return im.resize((im.width * z, im.height * z), Image.Resampling.NEAREST)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sets", nargs="+", default=["undistorted", "separable5"])
    ap.add_argument("--out", default=os.path.join(REPO, "art", "renders", "palette_board.png"))
    a = ap.parse_args()

    tmp = os.path.join(REPO, "art", "renders", "palette", "_tmp")
    os.makedirs(tmp, exist_ok=True)

    rows = []
    for s in a.sets:
        d = os.path.join(REPO, "art", "renders", "palette", s)
        chips = [to_sprite(os.path.join(d, f"chip_{c}_4x.png"), 1, 2, tmp) for c in CHIPS]
        px = {"proxy_chest": (1, 2), "proxy_pole": (1, 3), "proxy_smelter": (2, 3)}
        proxies = [to_sprite(os.path.join(d, f"{p}_4x.png"), *px[p], tmp) for p in PROXIES]
        rows.append((s, chips, proxies))

    band_h = max(max(c.height for c in r[1]) for r in rows)
    band4_h = band_h * 4
    prox_h = max(max(p.height for p in r[2]) for r in rows) * 3
    row_h = band_h + band4_h + prox_h + GAP * 5 + 34

    chip_w = max(max(c.width for c in r[1]) for r in rows)
    left_w = 5 * (chip_w + GAP) + GAP
    left_w4 = 5 * (chip_w * 4 + GAP) + GAP
    prox_w = sum(p.width * 3 + GAP for p in rows[0][2]) + GAP
    W = max(left_w, left_w4, prox_w) + GAP
    H = row_h * len(rows)

    canvas = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    for x in range(0, W, 32):
        d.line([(x, 0), (x, H)], fill=GRID)
    for y in range(0, H, 32):
        d.line([(0, y), (W, y)], fill=GRID)

    y = 0
    for name, chips, proxies in rows:
        d.text((GAP, y + 4), f"{name.upper()}   chips: true 32px size", fill=(20, 20, 20, 255))
        yy = y + 18
        x = GAP
        for c, lab in zip(chips, CHIPS):
            canvas.alpha_composite(c, (x, yy + band_h - c.height))
            x += chip_w + GAP
        yy += band_h + GAP
        x = GAP
        for c, lab in zip(chips, CHIPS):
            b = up(c, 4)
            canvas.alpha_composite(b, (x, yy))
            d.text((x + 2, yy + b.height + 1), lab[:14], fill=(30, 30, 30, 255))
            x += chip_w * 4 + GAP
        yy += band4_h + GAP + 12
        x = GAP
        for p in proxies:
            b = up(p, 3)
            canvas.alpha_composite(b, (x, yy + prox_h - b.height))
            x += b.width + GAP
        y += row_h

    canvas.convert("RGB").save(a.out)
    print(f"PALETTE_BOARD {a.out} {W}x{H} sets={a.sets}")


if __name__ == "__main__":
    main()
