"""Contact sheets on a neutral mid-grey field.

    python art/tools/sheet.py --out <png> [--zoom N] [--label] [--grid] <sprite.png>...

Mid-grey (#808080) is deliberate: it is the only background that flatters
neither light nor dark assets, so a sheet on it shows real value differences
rather than the ones the backdrop invented.
"""

import argparse
import os

from PIL import Image, ImageDraw

BG = (128, 128, 128, 255)
GRID = (118, 118, 118, 255)
GAP = 14
LABEL_H = 16


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--zoom", type=int, default=1)
    ap.add_argument("--label", action="store_true")
    ap.add_argument("--grid", action="store_true", help="32px tile grid")
    ap.add_argument("--align", choices=["bottom", "center"], default="bottom")
    ap.add_argument("sprites", nargs="+")
    a = ap.parse_args()

    imgs, names = [], []
    for p in a.sprites:
        im = Image.open(p).convert("RGBA")
        if a.zoom != 1:
            im = im.resize((im.width * a.zoom, im.height * a.zoom), Image.Resampling.NEAREST)
        imgs.append(im)
        names.append(os.path.splitext(os.path.basename(p))[0])

    cw = max(i.width for i in imgs)
    ch = max(i.height for i in imgs)
    lab = LABEL_H if a.label else 0
    W = len(imgs) * cw + (len(imgs) + 1) * GAP
    H = ch + 2 * GAP + lab

    canvas = Image.new("RGBA", (W, H), BG)
    if a.grid:
        d = ImageDraw.Draw(canvas)
        step = 32 * a.zoom
        for x in range(0, W, step):
            d.line([(x, 0), (x, H)], fill=GRID)
        for y in range(0, H, step):
            d.line([(0, y), (W, y)], fill=GRID)

    x = GAP
    for im, nm in zip(imgs, names):
        y = GAP + (ch - im.height) if a.align == "bottom" else GAP + (ch - im.height) // 2
        canvas.alpha_composite(im, (x + (cw - im.width) // 2, y))
        if a.label:
            d = ImageDraw.Draw(canvas)
            d.text((x + 2, GAP + ch + 3), nm[:26], fill=(30, 30, 30, 255))
        x += cw + GAP

    canvas.convert("RGB").save(a.out)
    print(f"SHEET {a.out} {W}x{H} n={len(imgs)} zoom={a.zoom}")


if __name__ == "__main__":
    main()
