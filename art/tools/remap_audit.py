"""Which clusters actually received the albedo correction, and which did not.

    python art/tools/remap_audit.py power_pole

palette_drift.py reports whether each DECLARED member matched. It does not say
what happened to everything else - and "everything else" is where the asset's
mass usually lives. A texel far from every trusted anchor still gets a
correction, because the gaussian weights are normalized: it inherits whatever
the nearest anchor's gain happens to be. That is a reasonable default and a
silent one, so this prints it.

Two questions it answers, both raised by the pole:

  1. Did region X get member Y's correction, or did it inherit someone else's?
     Column `w-share` is the nearest anchor's normalized weight. Near 100% means
     that cluster is squarely inside one anchor's basin. Near 1/n means it sat
     far from all of them and got the average, which is nobody's colour.

  2. What contrast does the corrected TEXTURE predict between two regions?
     If the rendered sprite shows less separation than the corrected albedo
     does, the loss is in lighting or form. If the albedo itself is flat, no
     amount of rig work will fix it and the texture is the defect.

`--pair A B` prints the predicted albedo luminance ratio between the dominant
clusters nearest to two named members, which is the number to compare against
what the sprite actually shows.
"""

import argparse
import itertools
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "art", "blender"))
import palette_drift as pd  # noqa: E402
import lock  # noqa: E402

LUM = np.array([0.2126, 0.7152, 0.0722])


def cluster(path, members, sample=200_000):
    """Reproduce palette_drift's clustering exactly, and return the centroids.

    analyse() does not hand them back, and re-deriving them here rather than
    changing its return shape keeps the measurement path and the emit path
    from drifting apart.
    """
    from PIL import Image
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float64) / 255.0
    lin = pd.srgb_to_linear(im).reshape(-1, 3)
    score = np.minimum(lin[:, 0], lin[:, 2]) - lin[:, 1]
    lin = lin[score <= 0.02]
    rng = np.random.default_rng(pd.SEED)
    if len(lin) > sample:
        lin = lin[rng.choice(len(lin), sample, replace=False)]

    pal = {n: pd.hexlin(lock.PALETTE[n]) for n in members}
    P = np.array(list(pal.values()))
    K = pd.clusters_for(len(P))
    min_pair = (min(float(np.linalg.norm(P[i] - P[j]))
                    for i, j in itertools.combinations(range(len(P)), 2))
                if len(P) >= 2 else 1.0)

    gain = np.ones(3)
    cent = w = None
    for _p in range(pd.GAIN_REFINE_PASSES):
        cent, w = pd.kmeans(lin / np.maximum(gain, 1e-6), K)
        D = np.array([[float(np.linalg.norm(cent[i] - P[j])) for i in range(K)]
                      for j in range(len(P))])
        trial = {}
        for j, name in enumerate(pal):
            i = int(np.argmin(D[j]))
            others = sorted(D[k][i] for k in range(len(P)) if k != j)
            trial[name] = (i, float(D[j][i]), others[0] if others else float("inf"))
        kept = [n for n in pal if trial[n][1] <= min_pair
                and trial[n][1] / max(trial[n][2], 1e-9) <= pd.MATCH_RATIO_TEST]
        if _p == pd.GAIN_REFINE_PASSES - 1 or not kept:
            break
        names = list(pal)
        O = np.array([cent[trial[n][0]] * gain for n in kept])
        T = np.array([P[names.index(n)] for n in kept])
        gain = (O.mean(0) / np.maximum(T.mean(0), 1e-9) if len(kept) > 1
                else (T * O).sum(0) / np.maximum((T * T).sum(0), 1e-12))
    return cent * gain, w, P, list(pal), min_pair


def effective_gain(c, obs, gains, sigma):
    """The gain a texel of colour c actually receives, shader math reproduced."""
    d = np.linalg.norm(obs - c, axis=1)
    w = np.exp(-(d ** 2) / max(sigma * sigma, 1e-12))
    if w.sum() <= 1e-30:          # every basin underflowed - nearest wins
        w = (d == d.min()).astype(float)
    w = w / w.sum()
    return (w[:, None] * gains).sum(0), d, w


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("asset")
    ap.add_argument("--tex")
    ap.add_argument("--pair", nargs=2, metavar=("A", "B"))
    a = ap.parse_args()

    man = json.load(open(os.path.join(REPO, "art", "assets.json")))
    cfg = next(x for x in man["assets"] if x["name"] == a.asset)
    members = cfg["palette_members"]
    tex = a.tex or os.path.join(REPO, "art", "renders", "tex",
                                f"{a.asset}_basecolor.png")

    remap = cfg["albedo_remap"]
    anchors = remap["anchors"]
    sigma = float(remap["sigma"])
    obs = np.array([an["observed"] for an in anchors])
    gains = np.array([an["gain"] for an in anchors])
    names = [an["member"] for an in anchors]
    dropped = remap.get("dropped") or []

    cent, wts, P, declared, min_pair = cluster(tex, members)
    print(f"{a.asset}: K={len(cent)}  sigma={sigma}  min_pair={min_pair:.4f}")
    print(f"  anchors {names}" + (f"   DROPPED {dropped}" if dropped else ""))
    print(f"\n{'pop%':>6} {'observed':>9} {'lum':>7} | {'nearest':<14} {'d':>7} "
          f"{'w-share':>8} | {'corrected':>9} {'lum':>7}  {'x':>5}")
    rows = []
    for i in np.argsort(-wts):
        c = cent[i]
        g, d, w = effective_gain(c, obs, gains, sigma)
        corr = c * g
        j = int(np.argmin(d))
        rows.append((wts[i], c, corr, names[j], d[j], w[j]))
        print(f"{wts[i]*100:5.1f}% {pd.tohex(c):>9} {c@LUM:7.4f} | {names[j]:<14} "
              f"{d[j]:7.4f} {w[j]*100:7.1f}% | {pd.tohex(corr):>9} {corr@LUM:7.4f} "
              f"{(corr@LUM)/max(c@LUM,1e-9):5.2f}")

    # a declared member that never formed a cluster of its own
    print()
    for m in declared:
        t = P[declared.index(m)]
        d = np.array([np.linalg.norm(c - t) for c in cent])
        i = int(np.argmin(d))
        flag = "  <-- DROPPED, uncorrected" if m in dropped else ""
        print(f"  {m:<14} nearest cluster {pd.tohex(cent[i])} at d={d[i]:.4f}, "
              f"pop {wts[i]*100:.1f}%{flag}")

    if a.pair:
        # POPULATION-WEIGHTED over every cluster that member owns, not the
        # single nearest one. The first version of this took the nearest
        # centroid and reported 1.14x for iron-vs-oak on the pole, because
        # iron's nearest cluster is a 6%-population mid-grey while the box's
        # actual mass sits in two much darker clusters that also route to iron.
        # One centroid is not a region.
        owner = [int(np.argmin(np.linalg.norm(obs - c, axis=1))) for c in cent]
        out = []
        for m in a.pair:
            if m not in names:
                print(f"\n{m} has no anchor (dropped?) - cannot attribute clusters")
                return
            k = names.index(m)
            idx = [i for i in range(len(cent)) if owner[i] == k]
            wsum = sum(wts[i] for i in idx)
            raw = sum(wts[i] * (cent[i] @ LUM) for i in idx) / wsum
            cor = sum(wts[i] * ((cent[i] * effective_gain(cent[i], obs, gains, sigma)[0]) @ LUM)
                      for i in idx) / wsum
            out.append((m, raw, cor, wsum, len(idx)))
        (na, ra, ca, wa, ka), (nb, rb, cb, wb, kb) = out
        print(f"\nPREDICTED ALBEDO CONTRAST  {na} vs {nb}   "
              f"({ka} clusters / {wa*100:.0f}% vs {kb} / {wb*100:.0f}%)")
        print(f"  raw texture   {max(ra,rb)/max(min(ra,rb),1e-9):.2f}x   "
              f"(lum {ra:.4f} vs {rb:.4f})")
        print(f"  after remap   {max(ca,cb)/max(min(ca,cb),1e-9):.2f}x   "
              f"(lum {ca:.4f} vs {cb:.4f})")
        print("  Compare against the sprite. Lower in the sprite = lighting or")
        print("  form is compressing it. Equal and low = the texture is flat.")


if __name__ == "__main__":
    main()
