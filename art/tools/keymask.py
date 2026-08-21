"""Validate an emission mask colour against a real Tripo basecolour texture.

    blender -b -P art/blender/dump_texture.py -- --glb art/source/<a>.glb --out-dir art/renders/tex
    python art/tools/keymask.py art/renders/tex/<a>_basecolor.png

This is the harness that decides whether the magenta mask survives Tripo's
generation and JPEG compression. It reports the texel-distance histogram: how
many texels fall at each distance from the mask colour, and therefore whether
a tolerance exists that catches the whole mask and nothing else.

WHAT A PASS LOOKS LIKE
A clean bimodal histogram: a spike near distance 0 (the mask region), a wide
gap, then the bulk of the texture beyond ~1.0. Any tolerance inside the gap
works, so the choice is not delicate.

WHAT A FAIL LOOKS LIKE
Texels smeared continuously between the mask and the material population -
which is what JPEG ringing around a hard magenta edge would produce. Then the
mask has to be eroded, or painted with a margin, or abandoned.

The previous attempt failed this way for a different reason: the key colour was
a palette member, so there was never a gap to find. Distances measured then:
tolerance 0.34 caught 99.83% of texels, 0.036 caught 0.00%.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender"))
import lock  # noqa: E402


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def hex_linear(h):
    h = h.lstrip("#")
    v = np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)
    return srgb_to_linear(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("texture")
    ap.add_argument("--key", default=lock.MASK_MAGENTA)
    ap.add_argument("--tolerance", type=float, default=lock.MASK_TOLERANCE)
    a = ap.parse_args()

    if not os.path.exists(a.texture):
        print(f"MISSING {a.texture}")
        return 1

    im = np.asarray(Image.open(a.texture).convert("RGB")).astype(np.float32) / 255.0
    lin = srgb_to_linear(im)
    key = hex_linear(a.key)
    d = np.linalg.norm(lin - key, axis=-1)
    n = d.size

    print(f"texture {os.path.basename(a.texture)}  {im.shape[1]}x{im.shape[0]}")
    print(f"mask key {a.key}   tolerance {a.tolerance}\n")

    print("texel-distance histogram (fraction of texels at each distance from the key)")
    edges = [0, .05, .1, .2, .3, .45, .6, .8, 1.0, 1.2, 1.5, 3.0]
    for lo, hi in zip(edges[:-1], edges[1:]):
        pct = ((d > lo) & (d <= hi)).mean() * 100
        bar = "#" * int(round(pct / 2))
        inside = "  [inside tolerance]" if hi <= a.tolerance else ""
        print(f"  {lo:4.2f}-{hi:4.2f}  {pct:6.2f}%  {bar}{inside}")

    matched = (d <= a.tolerance).mean() * 100
    print(f"\nmatched by tolerance {a.tolerance}: {matched:.3f}% of texels")

    # is there a usable gap between the mask population and the material bulk?
    near = d[d <= 0.6]
    if near.size == 0:
        print("VERDICT: NO MASK PRESENT - no texel is within 0.6 of the key.")
        print("         Either the concept image had no magenta, or it did not survive.")
        return 0

    hist, bin_edges = np.histogram(d, bins=120, range=(0, 3.0))
    frac = hist / n
    empty = [(bin_edges[i], bin_edges[i + 1]) for i in range(len(hist)) if frac[i] < 1e-5]
    gaps, run = [], None
    for lo, hi in empty:
        if run and abs(run[1] - lo) < 1e-6:
            run = (run[0], hi)
        else:
            if run:
                gaps.append(run)
            run = (lo, hi)
    if run:
        gaps.append(run)
    usable = [g for g in gaps if g[0] > 0.02 and (g[1] - g[0]) > 0.1]

    if usable:
        g = max(usable, key=lambda x: x[1] - x[0])
        print(f"VERDICT: PASS - clean gap from {g[0]:.3f} to {g[1]:.3f} "
              f"(width {g[1]-g[0]:.3f}).")
        print(f"         Any tolerance inside that gap isolates the mask. "
              f"Suggested: {(g[0]+g[1])/2:.2f}")
    else:
        print("VERDICT: FAIL - no clean gap; texels smear continuously from the "
              "mask into the material population.")
        print("         Erode the mask, paint it with a margin, or abandon the key.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
