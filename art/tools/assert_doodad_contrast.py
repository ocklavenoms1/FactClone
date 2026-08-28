"""GATE: a doodad must not compete with a building. Contrast against the ground.

    python art/tools/assert_doodad_contrast.py            # all
    python art/tools/assert_doodad_contrast.py grass_tuft

A doodad is decoration. If it carries as much contrast as a machine, the eye
reads it as a machine, and the player scans a field of noise looking for the
thing that matters. The failure is silent in exactly the way this project keeps
being bitten by: every doodad looks fine in isolation, at 4x, on grey. It only
fails as a set, on the real ground, at 32px, and by then twenty of them exist.

WHAT IS MEASURED

The doodad is composited OVER the ground colour and each resulting pixel's
relative luminance is compared to the ground's. That is what a player sees: a
half-transparent blade of grass does not put its own colour on screen, it puts
a blend, and measuring the raw RGB of a 40%-alpha pixel would charge the doodad
for light it never emits.

Contrast is the luminance RATIO, max/min, so it is symmetric - a doodad DARKER
than the ground competes exactly as much as one lighter, and a gate that only
watched for "too bright" would wave through a black smear.

THE STATISTIC IS p95, NOT THE MEAN, AND NOT THE MAX

Salience is set by the loudest part of a shape, not its average: a dark tuft
with one blazing highlight reads as a highlight. So the mean is wrong - it
dilutes with every antialiased fringe pixel and would let a bright doodad pass
by being mostly edge.

The true max is also wrong, for the opposite reason: one outlier pixel out of a
LANCZOS resample is not something an eye picks out of a 6px sprite, and a gate
that fires on it would be ignored within a week. p95 is the loudest thing
actually large enough to see. Mean and max are both printed so the choice can
be argued with rather than taken on trust.
"""

import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPRITES = os.path.join(REPO, "art", "sprites", "doodads")
LUM = np.array([0.2126, 0.7152, 0.0722])


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def hex_lin(h):
    h = h.lstrip("#")
    return srgb_to_linear(np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]))


def main():
    man = json.load(open(os.path.join(REPO, "art", "doodads.json")))
    ground = hex_lin(man["ground_hex"])
    cap = float(man["contrast_cap"])
    gl = float(LUM @ ground)
    want = sys.argv[1:]

    print(f"  ground {man['ground_hex']} luminance {gl:.4f}, cap {cap}:1 on p95")
    bad = 0
    for d in man["doodads"]:
        name = d["name"]
        if want and name not in want:
            continue
        if d.get("status") == "calibration":
            continue
        p = os.path.join(SPRITES, f"{name}.png")
        if not os.path.exists(p):
            print(f"  [--  ] {name}: not rendered")
            continue
        im = np.asarray(Image.open(p).convert("RGBA")).astype(np.float64) / 255.0
        rgb, al = srgb_to_linear(im[..., :3]), im[..., 3:4]
        # what the player actually sees: the doodad OVER the ground
        comp = rgb * al + ground * (1.0 - al)
        sel = im[..., 3] > 0
        if not sel.any():
            print(f"  [--  ] {name}: empty sprite")
            continue
        l = (comp @ LUM)[sel]
        ratio = np.maximum(l, gl) / np.maximum(np.minimum(l, gl), 1e-9)
        p95 = float(np.percentile(ratio, 95))
        ok = p95 <= cap
        bad += not ok
        print(f"  [{'ok  ' if ok else 'FAIL'}] {name:15} p95 {p95:5.2f}:1  "
              f"(mean {float(ratio.mean()):.2f}, max {float(ratio.max()):.2f}, "
              f"{int(sel.sum())}px)"
              + ("" if ok else f"  - exceeds {cap}:1, competes with a building"))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
