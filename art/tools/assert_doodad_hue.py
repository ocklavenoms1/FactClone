"""GATE: vegetation is GREENER than the ground, or equal. Never yellower.

    python art/tools/assert_doodad_hue.py

Ground #2E3A26 is hue 96. Vegetation sits in [96, 115]. Yellow is for dead
terrain and there is no dead terrain yet, so a warm doodad is not a variation -
it is straw lying on a lawn.

MEASURED ON THE RENDERED SPRITE, NOT THE ALBEDO, and that distinction is the
whole reason this file exists. The key light is warm - (1.0, 0.965, 0.912) -
so it drags everything it touches toward yellow. An albedo comfortably inside
the window can still render outside it, and the render is what a player sees.
The retired grass_tuft is the worked example: mixed from weathered_oak (hue
29.5) and verdigris (152.7), it rendered at 38.7, which is 57 degrees warm of
the ground it lay on.

Hue is taken from the alpha-weighted mean sRGB colour. Alpha-weighted because a
half-covered pixel contributes half a blade's worth of colour to the screen,
and sRGB rather than linear because hue is a property of what is displayed.

MINERAL DOODADS ARE EXEMPT. The rule is about vegetation: a grey pebble is
allowed to be grey. Exemption is by material - anything drawing on the
vegetation_palette is bound, anything on lock.PALETTE is not - so it cannot be
claimed by relabelling an asset.
"""

import colorsys
import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPRITES = os.path.join(REPO, "art", "sprites", "doodads")


def hue_of(path):
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0
    a = im[..., 3:4]
    if a.sum() <= 0:
        return None, None
    mean = (im[..., :3] * a).sum((0, 1)) / a.sum()
    h, _, _ = colorsys.rgb_to_hsv(*mean)
    return h * 360.0, mean


def main():
    man = json.load(open(os.path.join(REPO, "art", "doodads.json")))
    lo, hi = man["hue_window"]
    veg = set(man.get("vegetation_palette", {}))
    gh, _ = None, None
    g = man["ground_hex"].lstrip("#")
    gh = colorsys.rgb_to_hsv(*[int(g[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])[0] * 360.0
    want = sys.argv[1:]
    print(f"  ground {man['ground_hex']} hue {gh:.1f}   window [{lo}, {hi}]")
    bad = 0
    for d in man["doodads"]:
        name = d["name"]
        if want and name not in want:
            continue
        if d.get("status") == "calibration":
            continue
        bound = bool(veg.intersection(d.get("materials", [])))
        p = os.path.join(SPRITES, f"{name}.png")
        if not os.path.exists(p):
            print(f"  [--  ] {name}: not rendered")
            continue
        h, mean = hue_of(p)
        hexs = "#" + "".join(f"{int(round(c * 255)):02X}" for c in mean)
        if not bound:
            print(f"  [--  ] {name:22} hue {h:6.1f}  {hexs}  mineral, exempt")
            continue
        ok = lo <= h <= hi
        bad += not ok
        why = ""
        if not ok:
            why = (f"  - {gh - h:+.1f} deg of ground, "
                   f"{'YELLOWER' if h < gh else 'too cyan'}")
        print(f"  [{'ok  ' if ok else 'FAIL'}] {name:22} hue {h:6.1f}  {hexs}{why}")
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
