"""GATE: a doodad must not read as an object, and must not outshine a machine.

    python art/tools/assert_doodad_contrast.py            # all
    python art/tools/assert_doodad_contrast.py grass_tuft

TWO CONSTRAINTS, AND THEY TRADE AGAINST EACH OTHER

  (1) MEDIAN vs the GROUND.   median <= ground * MEDIAN_CAP
      "Does this read as an object?" - the typical pixel of a doodad must not
      be meaningfully brighter than the dirt it lies in.

  (2) p95 vs the BUILDINGS.   p95 <= pooled building p50
      "No part of a decoration is as bright as the TYPICAL part of a machine."
      The ceiling is set by the machines, not the ground, because the thing a
      doodad must not do is compete with them.

Because p95 ~= median * sqrt(internal range), the two bounds trade
automatically: a doodad with MORE internal form has a longer tail above its
median, so constraint (2) pushes it darker to hold the same ceiling. The
busiest form ends up the quietest in value, with nothing hand-tuned. That is a
real art principle falling out of two measurements.

WHAT THIS REPLACES, AND WHY

The first version capped p95 against the ground at 1.25:1 and was
unsatisfiable: a cap of C admits a window C^2 wide, and the locked rig's own
diffuse range is 2.72:1 (measured on _calib_dome), so the floor for any rounded
form is sqrt(2.72) = 1.65:1. That cap constrained a doodad's INTERNAL shading,
which was never the intent. Internal shading range is now UNCONSTRAINED -
blades stay blades.

VALUE ONLY. Hue separation is free and unlimited, and it is how these actually
read: grey pebbles and brown twigs against green ground separate chromatically
at any value. Do not spend value on legibility available for free from hue.

The building ceiling is MEASURED from the shipped sprites every run rather than
stored, so it tracks the assets instead of drifting away from them. It is
therefore sensitive to anything that changes building brightness - the open
specular question (PIPELINE.md 35) would move it.
"""

import glob
import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPRITES = os.path.join(REPO, "art", "sprites", "doodads")
LUM = np.array([0.2126, 0.7152, 0.0722])
# Composited, but only where the doodad actually FORMS the pixel. At alpha > 0
# a tight-cropped patch is mostly gap, so both statistics collapse onto the
# ground itself and stop describing the doodad at all - the first attempt at
# this solved every patch to a near-black scale while reporting p95 = 0.0373,
# which is just the ground. A quarter coverage is where a pixel starts being
# the doodad rather than the dirt behind it.
ALPHA_MIN = 0.25


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def hex_lin(h):
    h = h.lstrip("#")
    return srgb_to_linear(np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]))


def lum_of(path, amin=ALPHA_MIN, over=None):
    """Luminance of what reaches the screen.

    `over` composites the sprite onto the ground first, and for a dense patch
    that is not a refinement, it is the difference between right and wrong. A
    grass patch is mostly SEMI-TRANSPARENT: the gaps between blades are where
    the ground shows through, and they are the majority of its area. Measuring
    the sprite's own RGB there charges the patch for a darkness the player
    never sees, which drove the first solve to push patches to half the
    ground's brightness - dark blotches, not grass.

    Buildings are opaque, so their own pixels ARE what they put on screen and
    the ceiling stays a like-for-like comparison.
    """
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0
    sel = im[..., 3] > amin
    if not sel.any():
        return None
    rgb = srgb_to_linear(im[..., :3])
    if over is not None:
        a = im[..., 3:4]
        rgb = rgb * a + over * (1.0 - a)
    return (rgb @ LUM)[sel]


def building_sprite_names():
    """Exactly the sprites that SHIP, enumerated from the manifest.

    Globbing art/sprites/ for anything starting with an asset name sweeps in
    experiments that happen to share a prefix - smelter_rot_d0, smelter_idle_remap,
    smelter_idle_nomatnorm - and those are comparison artifacts, not shipped
    pixels. Pooling them moved the ceiling by 18% on the first run here.
    """
    man = json.load(open(os.path.join(REPO, "art", "assets.json")))
    out = []
    for a in man["assets"]:
        if a.get("status") not in ("real", "reference"):
            continue
        states = a.get("states") or {}
        if states:
            out += [f"{a['name']}_{s}" if s else a["name"] for s in states]
        else:
            out.append(a["name"])
    return out


def building_p50():
    """Pooled median of every shipped building sprite, measured not stored."""
    pool = []
    for n in building_sprite_names():
        p = os.path.join(REPO, "art", "sprites", f"{n}.png")
        if not os.path.exists(p):
            continue
        l = lum_of(p, 0.9)
        if l is not None:
            pool.append(l)
    if not pool:
        return None
    return float(np.median(np.concatenate(pool)))


def main():
    man = json.load(open(os.path.join(REPO, "art", "doodads.json")))
    gl = float(LUM @ hex_lin(man["ground_hex"]))
    mcap = float(man.get("median_cap", 1.25))
    med_ceiling = gl * mcap
    bld = building_p50()
    want = sys.argv[1:]

    print(f"  ground {man['ground_hex']} rel-lum {gl:.4f}")
    print(f"  (1) median <= {med_ceiling:.4f}  ({mcap}:1 of ground)")
    print(f"  (2) p95    <= {bld:.4f}  (pooled building p50, measured this run)")
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
        l = lum_of(p, over=hex_lin(man["ground_hex"]))
        if l is None:
            print(f"  [--  ] {name}: empty sprite")
            continue
        med, p95 = float(np.median(l)), float(np.percentile(l, 95))
        ok1, ok2 = med <= med_ceiling, p95 <= bld
        ok = ok1 and ok2
        bad += not ok
        why = ""
        if not ok1:
            why += f"  median {med / gl:.2f}:1 over ground"
        if not ok2:
            why += f"  p95 above building p50"
        print(f"  [{'ok  ' if ok else 'FAIL'}] {name:15} median {med:.4f} "
              f"({med / gl:4.2f}:1)  p95 {p95:.4f} ({p95 / bld:4.2f} of ceiling)"
              f"  range {p95 / max(np.percentile(l, 5), 1e-9):4.2f}:1{why}")
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
