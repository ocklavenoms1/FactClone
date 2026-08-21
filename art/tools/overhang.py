"""Measure lateral appendages sticking out past the main body block.

    python art/tools/overhang.py smelter_idle [--flag-pct 10]

The containment rule exists because an appendage steals scale from the
building: on the first kiln the timber outrigger consumed 38% of the
silhouette width and rendered the furnace itself 1.69x smaller than the same
tile could have held.

HOW THE SPLIT IS FOUND
Take the per-column opaque-pixel height profile of the 4x master. The body is
a solid run of tall columns; an appendage is separated from it by a notch. So:
walk outward from the tallest column and find the first deep notch - a column
whose height falls below `notch_frac` of the body's median height. Anything
beyond that notch is an appendage.

Height alone cannot do this: the smelter's bellows is a TALL leather panel
whose columns reach 187px against a body of ~250px, so a simple height
threshold keeps it as part of the body. The notch is the real signal.
"""

import argparse
import os

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
NOTCH_FRAC = 0.35


def measure(master_path, flag_pct=10.0):
    a = np.asarray(Image.open(master_path).convert("RGBA"))
    op = a[..., 3] > 127
    H, W = op.shape
    cols = op.sum(axis=0)
    occ = np.nonzero(cols)[0]
    if not len(occ):
        return None
    x0, x1 = int(occ.min()), int(occ.max())
    sil_w = x1 - x0 + 1

    core = int(np.argmax(cols))
    lo_c, hi_c = x0 + sil_w // 4, x1 - sil_w // 4
    body_med = float(np.median(cols[lo_c:hi_c + 1])) if hi_c > lo_c else float(cols[core])
    notch_h = NOTCH_FRAC * body_med

    def side(direction):
        """Return (appendage_px, notch_x) walking left(-1) or right(+1)."""
        x = core
        notch = None
        while x0 <= x <= x1:
            if cols[x] < notch_h and cols[x] > 0:
                notch = x
                break
            if cols[x] == 0:
                break
            x += direction
        if notch is None:
            return 0, None
        edge = x0 if direction < 0 else x1
        beyond = abs(notch - edge)
        return (beyond if beyond > 0 else 0), notch

    left_px, left_notch = side(-1)
    right_px, right_notch = side(+1)

    return {
        "master": os.path.basename(master_path),
        "master_px": [W, H],
        "silhouette_px": [x0, x1],
        "silhouette_w": sil_w,
        "body_median_col_h": round(body_med, 1),
        "notch_threshold_h": round(notch_h, 1),
        "left": {"px": left_px, "notch_x": left_notch,
                 "pct_of_silhouette": round(left_px / sil_w * 100, 1),
                 "pct_of_canvas": round(left_px / W * 100, 1)},
        "right": {"px": right_px, "notch_x": right_notch,
                  "pct_of_silhouette": round(right_px / sil_w * 100, 1),
                  "pct_of_canvas": round(right_px / W * 100, 1)},
        "flag_pct": flag_pct,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="+")
    ap.add_argument("--flag-pct", type=float, default=10.0)
    a = ap.parse_args()

    for n in a.names:
        p = os.path.join(REPO, "art", "renders", f"{n}_4x.png")
        if not os.path.exists(p):
            print(f"MISSING {p}")
            continue
        r = measure(p, a.flag_pct)
        if not r:
            continue
        print(f"\n=== {n}")
        print(f"  silhouette {r['silhouette_w']}px of a {r['master_px'][0]}px canvas"
              f"   body median column {r['body_median_col_h']}px")
        for side in ("left", "right"):
            s = r[side]
            if not s["px"]:
                print(f"  {side:5}: none")
                continue
            over = s["pct_of_silhouette"] > a.flag_pct
            print(f"  {side:5}: {s['px']}px past the notch at x={s['notch_x']}   "
                  f"{s['pct_of_silhouette']}% of silhouette, {s['pct_of_canvas']}% of canvas"
                  f"   {'** OVER ' + str(a.flag_pct) + '% - FLAG **' if over else 'ok'}")


if __name__ == "__main__":
    main()
