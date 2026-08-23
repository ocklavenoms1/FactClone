"""Do assets agree on HUE, not just on value? Measured across the whole set.

    python art/tools/hue_agreement.py smelter chest power_pole

The consistency verdict was first taken on luminance alone: mean brightness of
each member's pixels, per asset. That check passed the smelter and chest within
15% while the sheet plainly showed one timber reading salmon and the other mid
brown. **A luminance-only check is blind to exactly the drift that is most
visible when two assets sit side by side.** Value differences read as lighting;
hue differences read as different materials.

So this applies the instrument already used INSIDE one asset - chromaticity,
c / sum(c), which is stable under a value shift - ACROSS assets instead.

THE CHAIN
For each declared member of each asset it reports chromaticity at four stages,
which is what makes the result diagnostic rather than merely descriptive:

    target      the locked palette entry. Where it should be.
    raw         the Tripo texture, before any correction. SOURCE drift.
    corrected   raw x the per-cluster gain the remap actually applies.
                Movement between raw and corrected is what CORRECTION did.
    rendered    the finished sprite. Movement between corrected and rendered is
                what the RIG did.

Reading it:
  * raw already off-target, corrected still off  -> SOURCE. Tripo made it that
    colour and a multiplicative gain moved value without fixing hue. Belongs in
    the style core as a prompt rule, not in the pipeline.
  * raw off-target, corrected on-target, rendered off -> RIG. The albedo is
    right and lighting is tinting it.
  * corrected further from target than raw -> CORRECTION. The anchor is landing
    off-hue and it is fixable.

A per-channel multiplicative gain CAN shift hue - it is only hue-preserving
when the three channel gains are equal. The `gain skew` column reports
max/min of each anchor's three gains, so a hue-shifting correction is visible
rather than inferred.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "art", "blender"))
import palette_drift as pd  # noqa: E402
import remap_audit as ra  # noqa: E402
import lock  # noqa: E402


def own(chrom, members):
    """Assign each sample to the declared member nearest in chromaticity."""
    P = np.stack([pd.chromaticity(pd.hexlin(lock.PALETTE[m])) for m in members])
    D = np.stack([np.linalg.norm(chrom - P[j], axis=1) for j in range(len(P))])
    return D.argmin(0), D


def sprite_samples(name):
    p = os.path.join(REPO, "art", "sprites", f"{name}.png")
    if not os.path.exists(p):
        return None, None
    im = np.asarray(Image.open(p).convert("RGBA")).astype(float)
    rgb, a = im[..., :3] / 255.0, im[..., 3] / 255.0
    lin = pd.srgb_to_linear(rgb)
    op = a > 0.9
    return lin[op], np.argwhere(op)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("assets", nargs="+")
    ap.add_argument("--sprite", action="append", default=[],
                    help="asset=spritename when the sprite is not <asset>.png")
    a = ap.parse_args()
    override = dict(s.split("=", 1) for s in a.sprite)

    man = json.load(open(os.path.join(REPO, "art", "assets.json")))
    rows = {}
    for name in a.assets:
        cfg = next(x for x in man["assets"] if x["name"] == name)
        members = cfg["palette_members"]
        rm = cfg["albedo_remap"]
        anchors = rm["anchors"]
        sigma = float(rm["sigma"])
        obs = np.array([an["observed"] for an in anchors])
        gains = np.array([an["gain"] for an in anchors])
        anames = [an["member"] for an in anchors]

        tex = os.path.join(REPO, "art", "renders", "tex", f"{name}_basecolor.png")
        im = np.asarray(Image.open(tex).convert("RGB")).astype(np.float64) / 255.0
        X = pd.srgb_to_linear(im).reshape(-1, 3)
        sc = np.minimum(X[:, 0], X[:, 2]) - X[:, 1]
        X = X[sc <= 0.02]
        rng = np.random.default_rng(pd.SEED)
        if len(X) > 200_000:
            X = X[rng.choice(len(X), 200_000, replace=False)]
        owner, _ = own(pd.chromaticity(X), members)

        S, _ = sprite_samples(override.get(name, name))
        sowner = own(pd.chromaticity(S), members)[0] if S is not None else None

        print(f"\n=== {name} ===")
        print(f"{'member':14} {'target':>16} {'raw':>16} {'corrected':>16} "
              f"{'rendered':>16} | {'d raw':>6} {'d corr':>6} {'d rend':>6} {'skew':>5}")
        for j, m in enumerate(members):
            t = pd.chromaticity(pd.hexlin(lock.PALETTE[m]))
            sel = owner == j
            if not sel.any():
                continue
            raw = X[sel]
            g = np.array([ra.effective_gain(c, obs, gains, sigma)[0] for c in raw[:4000]])
            cor = raw[:4000] * g
            craw, ccor = pd.chromaticity(raw.mean(0)), pd.chromaticity(cor.mean(0))
            if sowner is not None and (sowner == j).any():
                crend = pd.chromaticity(S[sowner == j].mean(0))
                drend = np.linalg.norm(crend - t)
                rend_s, n_rend = f"({crend[0]:.3f},{crend[1]:.3f},{crend[2]:.3f})", (sowner == j).sum()
            else:
                crend, drend, rend_s, n_rend = None, float("nan"), "-", 0
            sk = next((max(x["gain"]) / min(x["gain"]) for x in anchors if x["member"] == m), float("nan"))
            print(f"{m:14} ({t[0]:.3f},{t[1]:.3f},{t[2]:.3f}) "
                  f"({craw[0]:.3f},{craw[1]:.3f},{craw[2]:.3f}) "
                  f"({ccor[0]:.3f},{ccor[1]:.3f},{ccor[2]:.3f}) {rend_s:>16} | "
                  f"{np.linalg.norm(craw-t):6.3f} {np.linalg.norm(ccor-t):6.3f} "
                  f"{drend:6.3f} {sk:5.2f}")
            rows.setdefault(m, []).append((name, crend, n_rend))

    print("\n=== CROSS-ASSET AGREEMENT (rendered chromaticity) ===")
    print("The verdict number. Spread is the max pairwise chromaticity distance")
    print("between assets that both contain the member.")
    for m, lst in rows.items():
        lst = [(n, c, k) for n, c, k in lst if c is not None and k > 0]
        if len(lst) < 2:
            if lst:
                print(f"  {m:14} only in {lst[0][0]} - no cross-asset check")
            continue
        sp = max(float(np.linalg.norm(c1 - c2))
                 for _, c1, _ in lst for _, c2, _ in lst)
        flag = "  <-- DISAGREE" if sp > 0.030 else ""
        print(f"  {m:14} spread {sp:.4f}{flag}")
        for n, c, k in lst:
            print(f"      {n:14} ({c[0]:.3f},{c[1]:.3f},{c[2]:.3f})  {k}px")


if __name__ == "__main__":
    main()
