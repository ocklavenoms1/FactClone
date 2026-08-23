"""Does K = 6 x declared members still hold at this member count?

    python art/tools/k_sweep.py chest --ks 4,6,8,12,16,24,32

K=10 was the root cause of every matching instability chased before it, and the
fix was to DERIVE K from how many palette members an asset declares rather than
pick a number (see PIPELINE.md, the comment above CLUSTERS_PER_MEMBER). That
rule was established on a four-member asset. A rule fitted at one point is not
a rule, so it gets re-tested whenever a new member count first appears.

What to look for, in order:

  trusted   how many declared members produced a trusted anchor. This is the
            headline. The derived K should sit INSIDE a plateau where this is
            at its maximum, not at the edge of one.
  rescued   members recovered by the nearest-texel fallback (§30). A member
            that is rescued at every K is genuinely too small to cluster and
            says nothing about K; one that is rescued only at low K is being
            starved of centroids.
  gain      the anchors' gains. Even where `trusted` is flat, gains that swing
            with K mean the clusters are still being cut differently each time
            and the plateau is not real.

A plateau in `trusted` with unstable `gain` is a false plateau. Both have to
settle before the derived K is defensible at that member count.
"""

import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import palette_drift as pd  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("asset")
    ap.add_argument("--ks", default="4,6,8,12,16,24,32")
    ap.add_argument("--tex")
    a = ap.parse_args()

    man = json.load(open(os.path.join(REPO, "art", "assets.json")))
    cfg = next(x for x in man["assets"] if x["name"] == a.asset)
    members = cfg["palette_members"]
    tex = a.tex or os.path.join(REPO, "art", "renders", "tex",
                                f"{a.asset}_basecolor.png")
    derived = pd.clusters_for(len(members))
    print(f"{a.asset}: {len(members)} declared members {members}")
    print(f"  derived K = {pd.CLUSTERS_PER_MEMBER} x {len(members)} = {derived}\n")
    print(f"{'K':>4} {'trusted':>8} {'rescued':>9}  anchors and gains")

    real = pd.clusters_for
    for K in [int(v) for v in a.ks.split(",")]:
        pd.clusters_for = lambda n, _k=K: _k
        try:
            res = pd.analyse(tex, members=members)
            import io
            import contextlib
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                remap = pd.build_remap(res)
        finally:
            pd.clusters_for = real
        anchors = remap["anchors"]
        resc = [x["member"] for x in anchors if x.get("via") == "nearest-texel"]
        trusted = [x["member"] for x in anchors if x.get("via") != "nearest-texel"]
        desc = "  ".join(
            f"{x['member'][:12]} [{', '.join(f'{v:.2f}' for v in x['gain'])}]"
            + ("*" if x.get("via") == "nearest-texel" else "")
            for x in anchors)
        mark = "  <-- derived" if K == derived else ""
        print(f"{K:>4} {len(trusted):>4}/{len(members)} {len(resc):>9}  {desc}{mark}")
    print("\n  * = recovered by the nearest-texel fallback, not by clustering")


if __name__ == "__main__":
    main()
