"""Build assertion: states declared different must actually LOOK different.

    python art/tools/assert_states.py art/sprites/smelter.json

WHY THIS EXISTS
Two silent failures have now shipped through this pipeline and both were caught
only by a human looking at pixels:

  1. The glTF importer's QUATERNION rotation mode made an 8-way turnaround
     render eight identical images, with no error anywhere.
  2. Applying the albedo correction before the emission mask was detected made
     the smelting state render identical to idle - while the log cheerfully
     printed "STATE smelting: mask-driven emission on 1 material(s)" throughout.

Both share a shape: a transform silently did nothing, and every downstream
report claimed success. This assertion kills the class rather than the
instance. It is cheap - two PNG loads and a subtraction - and it runs on every
build.

WHAT IT CHECKS
For each pair of distinct states at the same facing, the fraction of opaque
pixels that differ by more than DIFF_LEVEL. If that fraction is below
MIN_CHANGED_PCT the states are effectively identical and the build fails.

The thresholds are deliberately loose. This is not a quality check - it is a
tripwire for "the transform did nothing at all". The smelter's fire changes
2.83% of the sprite, an order of magnitude above the floor.
"""

import argparse
import itertools
import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

DIFF_LEVEL = 8.0 / 255.0     # per-channel difference that counts as "changed"
MIN_CHANGED_PCT = 0.25       # at least this % of opaque pixels must change


def load(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0
    return a[..., :3], a[..., 3]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("metas", nargs="+")
    ap.add_argument("--min-changed-pct", type=float, default=MIN_CHANGED_PCT)
    a = ap.parse_args()

    failures = []
    for mp in a.metas:
        if not os.path.exists(mp):
            print(f"MISSING {mp}")
            failures.append(mp)
            continue
        meta = json.load(open(mp))
        name = meta.get("name", os.path.basename(mp))
        masters = meta.get("masters", [])

        # group by facing so a 4-way asset compares like with like
        by_yaw = {}
        for m in masters:
            if m.get("state") is None:
                continue
            by_yaw.setdefault(m.get("yaw"), []).append(m)

        checked = 0
        for yaw, group in by_yaw.items():
            if len(group) < 2:
                continue
            for m1, m2 in itertools.combinations(group, 2):
                p1 = os.path.join(REPO, m1["sprite"])
                p2 = os.path.join(REPO, m2["sprite"])
                if not (os.path.exists(p1) and os.path.exists(p2)):
                    print(f"  SKIP {m1['tag']} vs {m2['tag']} - sprite missing")
                    continue
                rgb1, a1 = load(p1)
                rgb2, a2 = load(p2)
                if rgb1.shape != rgb2.shape:
                    print(f"  {name}: {m1['state']} vs {m2['state']} differ in SIZE - ok")
                    checked += 1
                    continue
                op = (a1 > 0.5) | (a2 > 0.5)
                if op.sum() == 0:
                    continue
                d = np.abs(rgb1 - rgb2).max(axis=-1)
                changed = float((d[op] > DIFF_LEVEL).mean() * 100)
                ok = changed >= a.min_changed_pct
                tag = "ok  " if ok else "FAIL"
                print(f"  [{tag}] {name} {m1['state']} vs {m2['state']}"
                      f"{'' if yaw is None else f' @yaw{yaw}'}: "
                      f"{changed:.2f}% of opaque pixels changed "
                      f"(floor {a.min_changed_pct}%)")
                if not ok:
                    failures.append(f"{name}: {m1['state']} == {m2['state']}")
                checked += 1

        if checked == 0:
            print(f"  [--  ] {name}: no distinct state pair to compare")

    if failures:
        print("\nSTATE ASSERTION FAILED:")
        for f in failures:
            print(f"  {f}")
        print("A state that renders identical to another means the transform "
              "silently did nothing.")
        return 1
    print("\nstate assertion: all declared states differ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
