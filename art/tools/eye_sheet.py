"""The actual gate: a finished sprite at true in-game size, judged by eye.

    python art/tools/eye_sheet.py --asset power_pole --reference smelter_idle

Every other tool here measures something. This one just shows the sprite at the
size a player sees it, next to an approved asset, on neutral mid-grey, with
NOTHING written on the image - no labels, no numbers, no grid. A metric printed
beside a picture tells you what to think about the picture.

Why this is the gate and the spectral ratio is not: the HF number earned its
keep on the first kiln, where cobbles genuinely turned to mud and it caught
them. Then it rejected a pole that looked good. A gate that fails good work is
worse than no gate, so it went back to being a diagnostic and the eye took over.

Layout: the asset at 1x, 2x and 4x, then the reference at 1x. True size sits
first because it is the one that decides.
"""

import argparse
import os

from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BG = (128, 128, 128, 255)
GAP = 26
PAD = 26


def load(name):
    p = os.path.join(REPO, "art", "sprites", f"{name}.png")
    if not os.path.exists(p):
        raise SystemExit(f"MISSING {p}")
    return Image.open(p).convert("RGBA")


def zoom(im, z):
    return im if z == 1 else im.resize((im.width * z, im.height * z),
                                       Image.Resampling.NEAREST)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset", required=True)
    ap.add_argument("--reference", default="smelter_idle")
    ap.add_argument("--zooms", default="1,2,4")
    ap.add_argument("--out")
    a = ap.parse_args()

    zs = [int(z) for z in a.zooms.split(",")]
    asset = load(a.asset)
    ref = load(a.reference)

    panels = [zoom(asset, z) for z in zs] + [ref]
    W = sum(p.width for p in panels) + GAP * (len(panels) - 1) + PAD * 2
    H = max(p.height for p in panels) + PAD * 2

    canvas = Image.new("RGBA", (W, H), BG)
    x = PAD
    for p in panels:
        # sit everything on a common baseline - buildings stand on the ground
        canvas.alpha_composite(p, (x, H - PAD - p.height))
        x += p.width + GAP

    out = a.out or os.path.join(REPO, "art", "renders", f"eye_{a.asset}.png")
    canvas.convert("RGB").save(out)
    print(f"EYE_SHEET {out} {W}x{H}   {a.asset} at {zs} + {a.reference} at 1x")
    print(f"  {a.asset} true size: {asset.width}x{asset.height}px")
    print(f"  {a.reference} true size: {ref.width}x{ref.height}px")


if __name__ == "__main__":
    main()
