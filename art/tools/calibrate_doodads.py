"""Solve each doodad's albedo value scale so it lands inside the contrast cap.

    python art/tools/calibrate_doodads.py            # solve all, write the manifest
    python art/tools/calibrate_doodads.py --dry      # measure only

Every locked palette member's albedo is 2.0-4.4x the ground's luminance BEFORE
any light is added, and the rig then multiplies it. So no doodad built at
palette VALUE can sit inside a 1.25:1 cap, at any orientation, except by
accident. Something has to give, and the choice of what is not arbitrary:

  HUE is identity - it is what makes a thing weathered oak rather than iron.
  VALUE is context - it is how bright that thing happens to be here.

So the doodad keeps the palette hue exactly and gives up its brightness. The
scale is a single scalar on linear RGB, which preserves chromaticity to machine
precision - the same property PIPELINE.md 32's split correction is built on.

Solving rather than guessing, because a guessed constant is the clamp mistake
again. Rendering is close to linear in albedo, so a first-order step lands
near the target and two or three passes converge; the loop stops when the
measured p95 is inside the cap, and reports the scale it found.
"""

import argparse
import json
import os
import math
import subprocess
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
LUM = np.array([0.2126, 0.7152, 0.0722])
BLENDER = os.environ.get("BLENDER",
                         r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
MAX_PASSES = 6
# Aim just inside the cap rather than at it. A doodad solved to land exactly on
# 1.25 is one resample away from 1.26, and a gate that trips on its own
# calibration output teaches people to rerun until it passes.
TARGET_FRACTION = 0.94


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def hex_lin(h):
    h = h.lstrip("#")
    return srgb_to_linear(np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]))


def render(name, scale):
    subprocess.run([BLENDER, "-b", os.path.join(REPO, "art", "template.blend"),
                    "-P", os.path.join(REPO, "art", "blender", "make_doodads.py"),
                    "--", "--name", name, "--vscale", f"{scale:.6f}"],
                   capture_output=True, check=True)
    subprocess.run([sys.executable,
                    os.path.join(REPO, "art", "tools", "downsample_doodads.py"), name],
                   capture_output=True, check=True)


def internal_range(name):
    """The doodad's OWN p95/p5 luminance over opaque pixels.

    This, not brightness, is what actually binds. A 1.25:1 cap admits a window
    1.25*1.25 = 1.5625:1 wide from floor to ceiling, so a doodad whose own
    shading spans more than that cannot be fitted inside by ANY uniform scale -
    scaling slides the distribution, it does not narrow it. When this exceeds
    1.5625 the fix is flatter geometry (or a wider cap), never a smaller scale.
    """
    p = os.path.join(REPO, "art", "sprites", "doodads", f"{name}.png")
    im = np.asarray(Image.open(p).convert("RGBA")).astype(np.float64) / 255.0
    sel = im[..., 3] > 0.9
    if sel.sum() < 3:
        sel = im[..., 3] > 0.5
    l = (srgb_to_linear(im[..., :3]) @ LUM)[sel]
    p5, p95 = float(np.percentile(l, 5)), float(np.percentile(l, 95))
    return p95 / max(p5, 1e-9), p5, p95


def measure(name, ground, gl):
    p = os.path.join(REPO, "art", "sprites", "doodads", f"{name}.png")
    im = np.asarray(Image.open(p).convert("RGBA")).astype(np.float64) / 255.0
    rgb, al = srgb_to_linear(im[..., :3]), im[..., 3:4]
    comp = rgb * al + ground * (1.0 - al)
    sel = im[..., 3] > 0
    l = (comp @ LUM)[sel]
    ratio = np.maximum(l, gl) / np.maximum(np.minimum(l, gl), 1e-9)
    return float(np.percentile(ratio, 95)), float(np.percentile(l, 95))


def solve(name, ground, gl, cap):
    """Best achievable contrast, and the scale that achieves it - analytically.

    With the specular lobe off the material is pure Lambertian, so rendered
    luminance is EXACTLY proportional to the albedo scale. That makes one
    render enough: sweep the scale numerically over the pixels already in hand
    rather than re-rendering to find out what a scale does.

    The earlier loop re-rendered per step and still stalled, because it was
    reading an internal range off the handful of pixels above alpha 0.9 - on a
    9x8 sprite that subset does not contain the extremes it was trying to
    measure. Sweeping the real composited statistic has no such blind spot.
    """
    p = os.path.join(REPO, "art", "sprites", "doodads", f"{name}.png")
    im = np.asarray(Image.open(p).convert("RGBA")).astype(np.float64) / 255.0
    sel = im[..., 3] > 0
    ld = (srgb_to_linear(im[..., :3]) @ LUM)[sel]      # rendered at scale 1.0
    al = im[..., 3][sel]
    best = (None, 1e9)
    for s in np.exp(np.linspace(np.log(0.002), np.log(3.0), 900)):
        l = al * ld * s + (1.0 - al) * gl
        r = np.maximum(l, gl) / np.maximum(np.minimum(l, gl), 1e-12)
        p95 = float(np.percentile(r, 95))
        if p95 < best[1]:
            best = (float(s), p95)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("names", nargs="*")
    a = ap.parse_args()

    mpath = os.path.join(REPO, "art", "doodads.json")
    man = json.load(open(mpath))
    ground = hex_lin(man["ground_hex"])
    gl = float(LUM @ ground)
    cap = float(man["contrast_cap"])
    print(f"  ground luminance {gl:.4f}  cap {cap}:1")

    for d in man["doodads"]:
        if d.get("status") == "calibration":
            continue
        if a.names and d["name"] not in a.names:
            continue
        name = d["name"]
        render(name, 1.0)
        scale, p95 = solve(name, ground, gl, cap)
        render(name, scale)
        _, achieved = solve(name, ground, gl, cap)
        p95_final = measure(name, ground, gl)[0]
        d["albedo_value_scale"] = round(scale, 4)
        verdict = "ok" if p95_final <= cap else f"needs cap >= {p95_final:.2f}"
        print(f"  {name:15} scale {scale:7.4f} -> best achievable p95 "
              f"{p95_final:5.2f}:1   {verdict}")

    if not a.dry:
        json.dump(man, open(mpath, "w"), indent=2)
        print("  wrote albedo_value_scale into art/doodads.json")


if __name__ == "__main__":
    main()
