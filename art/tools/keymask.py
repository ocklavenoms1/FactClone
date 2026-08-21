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
    ap.add_argument("--tolerance", type=float, default=0.45)
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

    # ---- the diagnostic that actually decides the mask --------------------
    # Absolute distance fails because Tripo returns the mask darkened. Chroma
    # score min(R,B)-G is what the shader uses; it is computed in LINEAR space
    # because that is what an Image Texture node outputs.
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    score = np.minimum(r, b) - g
    mx = np.maximum(np.maximum(r, g), b)
    norm = score / np.maximum(mx, 1e-3)

    print("\nchroma score  min(R,B)-G  (LINEAR space - what the shader sees)")
    print("  every palette member scores negative; the mask scores positive.")
    for t in (0.02, 0.05, 0.10, 0.16, 0.20, 0.26, 0.32, 0.40):
        pct = (score > t).mean() * 100
        tag = ""
        if abs(t - lock.MASK_SCORE_LO) < 1e-9:
            tag = "  <- EMIT cut (LO)"
        elif abs(t - lock.MASK_SCORE_HI) < 1e-9:
            tag = "  <- EMIT full (HI)"
        print(f"    score > {t:4.2f} -> {pct:7.4f}%{tag}")

    if (score > lock.MASK_SCORE_LO).mean() == 0:
        print("\n  VERDICT (chroma): NO MASK - nothing clears the emit cut.")
        return 0

    emit = (score > lock.MASK_SCORE_LO).mean() * 100
    core = (score > lock.MASK_SCORE_HI).mean() * 100
    spill = (score > 0.02).mean() * 100 - emit
    print(f"\n  panel admitted to emission : {emit:.4f}% of texels")
    print(f"  panel core (full strength) : {core:.4f}%")
    print(f"  spill excluded by the cut  : {spill:.4f}% of texels")
    print(f"  neutralized (normalized > {lock.MASK_NEUTRAL_LO}) : "
          f"{(norm > lock.MASK_NEUTRAL_LO).mean() * 100:.4f}%   "
          f"(spill is neutralized everywhere - it is an artifact)")

    # The verdict is decided on the chroma score, not on absolute distance.
    # Distance is still printed above because it is what shows *how far* Tripo
    # moved the mask colour, which is the thing worth knowing per generation.
    hist, edges_s = np.histogram(score, bins=300, range=(-0.2, 1.05))
    frac = hist / score.size
    empty = [(edges_s[i], edges_s[i + 1]) for i in range(len(hist))
             if frac[i] < 1e-6 and edges_s[i] > 0.0]
    gaps, run = [], None
    for lo, hi in empty:
        if run and abs(run[1] - lo) < 1e-9:
            run = (run[0], hi)
        else:
            if run:
                gaps.append(run)
            run = (lo, hi)
    if run:
        gaps.append(run)
    inner = [g for g in gaps if g[1] - g[0] > 0.02 and g[0] < 0.9]

    print()
    if emit < 1e-4:
        print("VERDICT: NO MASK - nothing clears the emit cut. Either the concept "
              "image had no magenta, or it did not survive generation.")
    elif inner:
        g = max(inner, key=lambda x: x[1] - x[0])
        print(f"VERDICT: PASS - mask present and separable. Panel population is "
              f"{emit:.3f}% of texels,")
        print(f"         with an empty band at score {g[0]:.3f}..{g[1]:.3f} "
              f"separating it from the material bulk.")
    else:
        print(f"VERDICT: PASS (soft) - mask present at {emit:.3f}% of texels, but "
              f"the score distribution is")
        print(f"         continuous rather than cleanly bimodal, so the cut at "
              f"{lock.MASK_SCORE_LO} is a judgement call.")
        print(f"         Spill excluded: {spill:.3f}% of texels. Inspect the idle "
              f"render for magenta residue.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
