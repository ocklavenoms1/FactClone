"""Measure where the footprint marker actually landed. Partner of verify_anchor.py.

    python art/tools/measure_anchor.py chest smelter power_pole

Downsamples the marker master exactly as downsample.py would (LANCZOS; alpha
resamples identically premultiplied or not, and only alpha is measured), then
reports the quad's edges in final sprite pixels against what anchor_px claims.

PASS means: the footprint front edge lands at anchor_y, its centre at anchor_x,
and the footprint spans footprint*32 px - each within 1px, which is the honest
limit of an edge through LANCZOS at a half-pixel boundary.
"""

import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def main():
    names = sys.argv[1:]
    if not names:
        raise SystemExit(__doc__)
    fails = 0
    for name in names:
        d = os.path.join(REPO, "art", "renders", "anchor_marker")
        meta = json.load(open(os.path.join(d, f"{name}_marker.json")))
        sw, sh = meta["sprite_px"]
        ax, ay = meta["anchor_px"]
        fp = meta["footprint"]
        al = Image.open(os.path.join(d, f"{name}_marker_4x.png")).convert("RGBA") \
                  .getchannel("A").resize((sw, sh), Image.Resampling.LANCZOS)
        arr = np.asarray(al)
        rows = np.where(arr.max(axis=1) > 127)[0]
        cols = np.where(arr.max(axis=0) > 127)[0]
        bottom = rows[-1] + 1                       # boundary below last opaque row
        centre = (cols[0] + cols[-1] + 1) / 2.0
        width = cols[-1] - cols[0] + 1
        ok = (abs(bottom - ay) <= 1 and abs(centre - ax) <= 1
              and abs(width - fp * 32) <= 1)
        fails += not ok
        print(f"{'PASS' if ok else 'FAIL':4} {name:11} "
              f"front edge at row boundary {bottom} (anchor_y {ay})  "
              f"centre {centre} (anchor_x {ax})  "
              f"footprint width {width}px (expected {fp * 32:.0f})")
    if fails:
        raise SystemExit(f"{fails} anchor(s) FAILED - the metadata is wrong, fix ours first")
    print("\nEvery anchor verified by experiment: the pipeline, asked where the")
    print("footprint is, answers with the number the metadata already claims.")


if __name__ == "__main__":
    main()
