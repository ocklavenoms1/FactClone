"""GATE: shadow layers are pure black, alpha-only. Colour in a shadow FAILS.

    python art/tools/assert_shadow_black.py            # every *_shadow.png
    python art/tools/assert_shadow_black.py smelter    # one asset's

The game composites shadows with `modulate.a` and nothing else - the layer's
own RGB is trusted to be black, so any colour that sneaks in tints every
building's ground contact and nothing catches it but the eye, one asset at a
time. Until now this was a happy accident of the shadow render being lit by
nothing; the game team asked for it as a contract, and a contract without a
tripwire gets quietly relaxed.

Tolerance is 1/255, not 0, for a measured reason: the smelter's shadow carries
a single stray value of 1 from 8-bit unpremultiply rounding at soft edges.
That is not colour - it is quantisation - and a gate that cries wolf on
quantisation teaches people to ignore it. 2 and above is a real tint and fails.
"""

import glob
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TOLERANCE = 1


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "*"
    paths = sorted(glob.glob(os.path.join(REPO, "art", "sprites", f"{which}_shadow.png")))
    if not paths:
        print(f"  [--  ] no shadow layers matching {which!r}")
        return
    bad = 0
    for p in paths:
        im = np.asarray(Image.open(p).convert("RGBA")).astype(int)
        sel = im[..., 3] > 0
        peak = int(im[..., :3][sel].max()) if sel.any() else 0
        ok = peak <= TOLERANCE
        bad += not ok
        name = os.path.basename(p)
        print(f"  [{'ok  ' if ok else 'FAIL'}] {name}: max RGB under alpha = {peak}/255"
              + ("" if ok else f"  - shadow is TINTED; it must be pure black + alpha"))
    if bad:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
