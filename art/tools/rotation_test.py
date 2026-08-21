"""Settles the rotation question with a picture instead of an opinion.

    python art/tools/rotation_test.py --name smelter_rot --out art/renders/rotation_test.png

Top row    four true 3D renders, model rotated 0/90/180/270 in Blender.
Bottom row the d0 sprite rotated 90/180/270 in 2D, as an engine transform
           would do it.
"""

import argparse
import json
import os

from PIL import Image, ImageDraw

BG = (128, 128, 128, 255)
GAP = 14
ZOOM = 3
LABEL = 18


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="smelter_rot")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    repo = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    meta = json.load(open(os.path.join(repo, "art", "sprites", f"{a.name}.json")))
    by_yaw = {m["yaw"]: os.path.join(repo, m["sprite"]) for m in meta["masters"]}

    true3d = [Image.open(by_yaw[y]).convert("RGBA") for y in (0, 90, 180, 270)]
    base = true3d[0]
    naive = [base,
             base.rotate(-90, resample=Image.Resampling.NEAREST, expand=False),
             base.rotate(-180, resample=Image.Resampling.NEAREST, expand=False),
             base.rotate(-270, resample=Image.Resampling.NEAREST, expand=False)]

    def up(i):
        return i.resize((i.width * ZOOM, i.height * ZOOM), Image.Resampling.NEAREST)

    true3d = [up(i) for i in true3d]
    naive = [up(i) for i in naive]

    cw, ch = true3d[0].width, true3d[0].height
    W = 4 * cw + 5 * GAP
    H = 2 * ch + 3 * GAP + 2 * LABEL
    canvas = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(canvas)

    y = GAP + LABEL
    d.text((GAP, GAP // 2), "TRUE 3D RENDERS - model rotated in Blender (0 / 90 / 180 / 270)",
           fill=(20, 20, 20, 255))
    for i, im in enumerate(true3d):
        canvas.alpha_composite(im, (GAP + i * (cw + GAP), y))

    y2 = y + ch + GAP + LABEL
    d.text((GAP, y + ch + GAP), "2D SPRITE ROTATION of the d0 sprite - what an engine transform gives you",
           fill=(20, 20, 20, 255))
    for i, im in enumerate(naive):
        canvas.alpha_composite(im, (GAP + i * (cw + GAP), y2))

    canvas.convert("RGB").save(a.out)
    print(f"ROTATION_TEST {a.out} {W}x{H}")


if __name__ == "__main__":
    main()
