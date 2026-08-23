"""Does Tripo shift the whole palette, or only the magenta mask?

    python art/tools/palette_drift.py art/renders/tex/<name>_basecolor.png [...]

The magenta mask came back at roughly half brightness (#FF00FF -> #9D009A).
If that shift was applied to the mask it was probably applied to the stone,
oak, iron and leather too - and the consequences fork sharply:

  * SYSTEMATIC shift  -> one levels correction in normalization fixes all
    twenty assets, and prompting keeps working.
  * PER-GENERATION shift -> cross-asset colour consistency is not achievable
    through prompting at all, and the material-normalization pass must own
    value and exposure, not just roughness and metallic.

METHOD
1. Cluster the basecolour texture in LINEAR space (k-means, no scipy), with
   the mask texels excluded.
2. Match clusters to palette members by CHROMATICITY, not by absolute colour.
   That matters: the shift we are trying to measure is mostly in value, so
   matching on absolute colour would partly hide the very thing being
   measured. Chromaticity (c / sum(c)) is stable under a value shift.
3. Report each member's delta in linear space - magnitude and direction.
4. Fit a single per-channel gain mapping palette -> observed, and report the
   residual. A small residual means one global correction explains everything;
   a large one means the drift is per-material and cannot be corrected
   globally.

Run it on two or more generations to separate "systematic across generations"
from "varies per generation" - that is the question that decides the pipeline.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender"))
import lock  # noqa: E402

# K IS DERIVED, NOT CHOSEN.
#
# K=10 was too few and was the real source of every matching instability chased
# before it: with only ten clusters the two near-neutrals (stone and iron) kept
# merging into ONE cluster, and which member won it then swung with membership,
# gain and assignment strategy. Measured trusted-anchor count on the smelter
# with four declared members:
#     K=10  2/4      K=14  2/4      K=20  4/4      K=28  4/4      K=40  4/4
#
# The break is at K>=20 for four members, i.e. about five clusters per member.
# Six per member sits inside the plateau with margin, and - unlike a fixed 24 -
# it scales: a three-material chest gets 18, a six-material building gets 36,
# instead of one number over- or under-resolving both.
CLUSTERS_PER_MEMBER = 6
GAIN_REFINE_PASSES = 4   # aggregate seed, then 3 refinements from trusted anchors
K_MIN, K_MAX = 12, 64


def clusters_for(n_members):
    """K derived from how many palette members the asset actually declares."""
    return max(K_MIN, min(K_MAX, CLUSTERS_PER_MEMBER * max(1, n_members)))


ITERS = 40
# An anchor is trusted only if BOTH questions pass:
#   "is it close at all?"      d1 < MATCH_ABS_RATIO * palette min-pair
#   "is it decisively closest?" d1/d2 < MATCH_RATIO_TEST
# Absolute-only (the old d1 < 0.5*min_pair) dropped fieldstone - the largest
# cluster on a stone building. Ratio-only kept verdigris, calling a grey cluster
# green on an asset with no green in it. Each question alone is wrong.
MATCH_ABS_RATIO = 1.0
MATCH_RATIO_TEST = 0.8
# SAFETY RAIL, NOT A TUNING PARAMETER. Deliberately set high enough to be
# non-binding in normal operation.
#
# It used to be (0.4, 2.5) and it bound on EVERY anchor of EVERY asset - 52% of
# raw gain channels sat at or above the ceiling, and the pole's oak asked for
# 6.53x and got 2.5x. Tripo returns albedos around 0.2x of target, so a real
# correction needs 4-5x; a 2.5 cap was the binding constraint on the whole
# pipeline, truncating by a different amount per asset and feeding the
# cross-asset lightness gap directly.
#
# Worse, it was introduced for a case that turned out not to exist: fired_clay
# "wanting 4.4x" was later shown to be a K=10 clustering artifact.
#
# At 12x it should never bind. If it does, that is a SIGNAL, not a fix: an
# anchor demanding more than 12x means the MATCH is wrong, and silently
# truncating it would hide the bad match instead of surfacing it. So binding is
# logged loudly.
GAIN_CLAMP = (0.4, 12.0)
SEED = 12345


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def hexlin(h):
    h = h.lstrip("#")
    return srgb_to_linear(np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float64))


def tohex(lin):
    s = linear_to_srgb(np.asarray(lin, dtype=np.float64))
    return "#" + "".join(f"{int(round(v * 255)):02X}" for v in s)


def chromaticity(c):
    c = np.asarray(c, dtype=np.float64)
    s = c.sum(axis=-1, keepdims=True)
    return c / np.maximum(s, 1e-9)


def kmeans(X, k, iters=ITERS, seed=SEED):
    rng = np.random.default_rng(seed)
    # k-means++ style seeding, cheap version
    cent = X[rng.integers(0, len(X), 1)]
    for _ in range(k - 1):
        d = ((X[:, None, :] - cent[None, :, :]) ** 2).sum(-1).min(1)
        p = d / max(d.sum(), 1e-12)
        cent = np.vstack([cent, X[rng.choice(len(X), p=p)]])
    for _ in range(iters):
        lab = ((X[:, None, :] - cent[None, :, :]) ** 2).sum(-1).argmin(1)
        new = np.array([X[lab == i].mean(0) if (lab == i).any() else cent[i] for i in range(k)])
        if np.allclose(new, cent, atol=1e-6):
            cent = new
            break
        cent = new
    lab = ((X[:, None, :] - cent[None, :, :]) ** 2).sum(-1).argmin(1)
    w = np.array([(lab == i).mean() for i in range(k)])
    return cent, w


def analyse(path, sample=200_000, is_render=False, members=None):
    img = Image.open(path)
    if is_render:
        a = np.asarray(img.convert("RGBA")).astype(np.float64) / 255.0
        opaque = a[..., 3].reshape(-1) > 0.5
        lin = srgb_to_linear(a[..., :3]).reshape(-1, 3)[opaque]
    else:
        im = np.asarray(img.convert("RGB")).astype(np.float64) / 255.0
        lin = srgb_to_linear(im).reshape(-1, 3)

    # drop the emission mask: it is not a material and would skew everything
    score = np.minimum(lin[:, 0], lin[:, 2]) - lin[:, 1]
    keep = score <= 0.02
    mask_pct = (~keep).mean() * 100
    lin = lin[keep]

    rng = np.random.default_rng(SEED)
    if len(lin) > sample:
        lin = lin[rng.choice(len(lin), sample, replace=False)]

    # PRUNE membership to what this asset actually uses. Attempting a member
    # the building was never going to contain is a category error, not a
    # failure: verdigris "dropped" on a smelter with no green in it, having
    # first stolen a cluster from the greedy assignment. An absent member is
    # skipped, not attempted.
    declared = list(members) if members else list(lock.PALETTE)
    unknown = [m for m in declared if m not in lock.PALETTE]
    if unknown:
        raise SystemExit(f"palette_members not in the locked palette: {unknown}")
    skipped = [m for m in lock.PALETTE if m not in declared]
    pal = {n: hexlin(lock.PALETTE[n]) for n in declared}
    P = np.array(list(pal.values()))

    # (a) GLOBAL GAIN SEED, from aggregate albedo, with NO matching at all.
    #     Matching before this point forces the metric to be value-invariant,
    #     and a value-invariant metric cannot separate two near-neutrals - which
    #     is the whole reason the old palette needed distorting. Estimating the
    #     gain from aggregate means needs no correspondence, so it can run first.
    gain = lin.mean(axis=0) / np.maximum(P.mean(axis=0), 1e-9)

    # (b) divide it out, then REFINE. The aggregate seed assumes the asset's
    #     material mix resembles the palette's, and that assumption breaks when
    #     one material dominates. On the power pole - mostly timber, only three
    #     declared members - the seed came out R 1.050 / G 0.462 / B 0.203, a
    #     5.2x channel spread, and the skew pushed verdigris out of range even
    #     though its cluster was present and correctly the greenest.
    #
    #     So the seed is only a seed: match with it, then re-estimate the gain
    #     from the TRUSTED correspondences alone and repeat. This is not the
    #     circular "match before removing the gain" that the ordering fix
    #     eliminated - the first estimate still needs no correspondence, and
    #     each refinement uses only anchors that already passed the trust tests.
    #
    #     Measured convergence, trusted anchors and gain spread by iteration:
    #       pole    5.17x 2/3  ->  2.96x 2/3  ->  2.51x 3/3  ->  1.82x 3/3
    #       smelter 1.22x 4/4  ->  1.29x 4/4  ->  1.31x 4/4  ->  1.31x 4/4
    #     It rescues a skewed asset and leaves a well-mixed one alone.
    K = clusters_for(len(P))
    min_pair_seed = (min(float(np.linalg.norm(P[i] - P[j]))
                         for i, j in __import__("itertools").combinations(range(len(P)), 2))
                     if len(P) >= 2 else 1.0)

    cent = w = None
    for _pass in range(GAIN_REFINE_PASSES):
        Y = lin / np.maximum(gain, 1e-6)
        cent, w = kmeans(Y, K)
        D = np.array([[float(np.linalg.norm(cent[i] - P[j])) for i in range(K)]
                      for j in range(len(P))])
        trial = {}
        for j, name in enumerate(pal):
            i = int(np.argmin(D[j]))
            others = sorted(D[k][i] for k in range(len(P)) if k != j)
            trial[name] = (i, float(D[j][i]), others[0] if others else float("inf"))
        kept = [n for n in pal
                if trial[n][1] <= min_pair_seed
                and trial[n][1] / max(trial[n][2], 1e-9) <= MATCH_RATIO_TEST]
        if _pass == GAIN_REFINE_PASSES - 1 or not kept:
            break
        names = list(pal)
        O = np.array([cent[trial[n][0]] * gain for n in kept])
        T = np.array([P[names.index(n)] for n in kept])
        gain = (O.mean(0) / np.maximum(T.mean(0), 1e-9) if len(kept) > 1
                else (T * O).sum(0) / np.maximum((T * T).sum(0), 1e-12))

    # (c) final match on FULL LINEAR RGB - chromaticity AND value together.
    D = np.array([[float(np.linalg.norm(cent[i] - P[j])) for i in range(K)]
                  for j in range(len(P))])
    result = {}
    for j, name in enumerate(pal):
        i = int(np.argmin(D[j]))
        others = sorted(D[k][i] for k in range(len(P)) if k != j)
        result[name] = (i, float(D[j][i]), others[0] if others else float("inf"))

    # trust threshold scales with how separable THIS ASSET's declared subset is
    if len(P) >= 2:
        min_pair = min(float(np.linalg.norm(P[i] - P[j]))
                       for i, j in __import__("itertools").combinations(range(len(P)), 2))
    else:
        min_pair = 1.0

    rows = []
    for name, p in pal.items():
        i, mdist, runner = result[name]
        # back into the ORIGINAL texture space: the shader taps the raw texture
        o = cent[i] * gain
        cdist = float(np.linalg.norm(chromaticity(o) - chromaticity(p)))
        delta = o - p
        rows.append({
            "member": name,
            "palette_hex": lock.PALETTE[name],
            "observed_hex": tohex(o),
            "palette_lin": p,
            "observed_lin": o,
            "delta": delta,
            "delta_mag": float(np.linalg.norm(delta)),
            "lum_ratio": float((o.sum() + 1e-9) / (p.sum() + 1e-9)),
            "chroma_dist": float(cdist),
            "match_dist": float(mdist),
            "match_ratio": float(mdist / max(min_pair, 1e-9)),
            "runner_up": float(runner),
            "ratio_test": float(mdist / max(runner, 1e-9)),
            "cluster_pct": float(w[i] * 100),
        })

    O = np.array([r["observed_lin"] for r in rows])
    resid = O - P * gain
    return {
        "file": os.path.basename(path),
        "mask_pct": mask_pct,
        "rows": rows,
        "gain": gain,
        "min_pair": min_pair,
        "k": K,
        "declared": declared,
        "skipped": skipped,
        "resid_rms": float(np.sqrt((resid ** 2).mean())),
        "raw_rms": float(np.sqrt(((O - P) ** 2).mean())),
    }


def report(a):
    print(f"\n=== {a['file']}   (mask texels excluded: {a['mask_pct']:.2f}%)")
    print(f"{'member':15}{'locked':9}{'observed':10}{'match d':>9}"
          f"{'d/minpr':>9}{'d1/d2':>9}{'cluster':>9}")
    for r in a["rows"]:
        keep = r["match_ratio"] <= MATCH_ABS_RATIO and r["ratio_test"] <= MATCH_RATIO_TEST
        flag = "" if keep else ("  DROP far" if r["match_ratio"] > MATCH_ABS_RATIO
                                else "  DROP ambiguous")
        print(f"{r['member']:15}{r['palette_hex']:9}{r['observed_hex']:10}"
              f"{r['match_dist']:9.4f}{r['match_ratio']:9.2f}{r['ratio_test']:9.2f}"
              f"{r['cluster_pct']:8.1f}%{flag}")
    g = a["gain"]
    print(f"  palette min-pair separation (linear RGB): {a['min_pair']:.4f}")
    print(f"  K = {a['k']} clusters ({CLUSTERS_PER_MEMBER} x {len(a['declared'])} declared members)")
    print(f"  (a) aggregate global gain, no matching: R {g[0]:.3f}  G {g[1]:.3f}  B {g[2]:.3f}")
    print(f"  RMS error   raw {a['raw_rms']:.4f}  ->  after gain {a['resid_rms']:.4f}"
          f"   ({(1 - a['resid_rms'] / max(a['raw_rms'], 1e-9)) * 100:.0f}% explained)")


def build_remap(a):
    """Per-cluster correction anchors, for normalize.apply_albedo_remap().

    The global gain explains only ~67% of the error; the residual is
    per-material and large - on the smelter, fired clay sits at 0.229 luminance
    against weathered oak at 0.750, a 3.3x spread INSIDE one asset. No single
    gain can touch that, so a clay-heavy chest would still not match an
    oak-heavy smelter after correction.

    Each matched cluster therefore gets its own per-channel gain t_i / c_i, and
    a texel is corrected by the softly-weighted blend of the anchors nearest it
    in colour space.

    MULTIPLICATIVE, not additive, and deliberately so. An additive shift moves
    the mean but lifts blacks with it, washing out shading. A per-channel gain
    preserves each texel's ratio to its cluster mean, so within-cluster
    variation survives intact, shadows stay dark, and the whole thing reduces
    exactly to the accepted global gain when every cluster agrees.
    """
    anchors, dropped = [], []
    for r in a["rows"]:
        c = np.asarray(r["observed_lin"], dtype=float)
        t = np.asarray(r["palette_lin"], dtype=float)
        g = np.array([t[k] / max(c[k], 1e-4) for k in range(3)])

        # A poor chromaticity match means we are not actually confident this
        # cluster IS that material - and a confident-looking gain built on a bad
        # match will shift hues wherever it applies. Drop it rather than trust it.
        too_far = r["match_ratio"] > MATCH_ABS_RATIO
        not_decisive = r["ratio_test"] > MATCH_RATIO_TEST
        if too_far or not_decisive:
            why = ("no material that close - likely absent from the asset" if too_far
                   else "ambiguous against its runner-up - materials not distinct")
            dropped.append((r["member"], round(r["ratio_test"], 3), why))
            continue

        # Clamp: an unclamped gain on a very dark cluster (fired clay wants
        # 4.4x) amplifies compression noise and clips highlights. Clamping
        # trades exact mean-matching for not destroying the texture.
        clamped = np.clip(g, GAIN_CLAMP[0], GAIN_CLAMP[1])
        if np.any(np.abs(clamped - g) > 1e-6):
            print(f"  ** CLAMP BOUND on {r['member']}: raw "
                  f"{[round(float(v), 2) for v in g]} -> "
                  f"{[round(float(v), 2) for v in clamped]}")
            print(f"     The rail is set at {GAIN_CLAMP[1]}x to be non-binding. It binding "
                  f"means the MATCH is suspect, not that the gain needs capping.")
            print(f"     Check this anchor: match d1/d2 = {r['ratio_test']:.2f}, "
                  f"population {r['cluster_pct']:.1f}%.")
        anchors.append({
            "member": r["member"],
            "observed": [round(float(v), 6) for v in c],
            "target": [round(float(v), 6) for v in t],
            "gain": [round(float(v), 4) for v in clamped],
            "gain_raw": [round(float(v), 4) for v in g],
            "clamped": bool(np.any(np.abs(clamped - g) > 1e-6)),
            "chroma_dist": round(r["chroma_dist"], 4),
            "match_ratio": round(r["match_ratio"], 3),
        })

    if dropped:
        print("  anchors dropped (not trusted):")
        for m, d, why in dropped:
            print(f"    {m:15} chroma_d {d}  - {why}")

    # sigma from the anchors' own spacing: half the median nearest-neighbour
    # distance. Too small bands at cluster boundaries; too large and every
    # anchor blends into one average, which is just the global gain again.
    C = np.array([an["observed"] for an in anchors])
    d = np.linalg.norm(C[:, None, :] - C[None, :, :], axis=-1)
    np.fill_diagonal(d, np.inf)
    sigma = float(np.median(d.min(axis=1)) * 0.5)
    return {"sigma": round(max(sigma, 0.02), 4), "anchors": anchors,
            "dropped": [d[0] for d in dropped]}


def emit(name, a):
    import json as _json
    repo = os.path.abspath(os.path.join(HERE, "..", ".."))
    p = os.path.join(repo, "art", "assets.json")
    man = _json.load(open(p))
    hit = False
    for row in man["assets"]:
        if row.get("albedo_pinned") and (row["name"] == name):
            print(f"  {name} is PINNED (approved pixels frozen) - refusing to overwrite its remap.")
            return
        if row["name"] == name or row.get("source", "") == f"{name}.glb":
            row["albedo_gain"] = [round(float(v), 4) for v in a["gain"]]
            row["albedo_remap"] = build_remap(a)
            hit = True
    if not hit:
        print(f"  (no manifest row matched {name!r}; nothing written)")
        return
    _json.dump(man, open(p, "w"), indent=2)
    print(f"  wrote albedo_gain + albedo_remap for {name} into assets.json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("textures", nargs="+")
    ap.add_argument("--render", action="store_true",
                    help="inputs are rendered RGBA sprites/masters, not albedo textures")
    ap.add_argument("--emit", metavar="ASSET",
                    help="write albedo_gain and albedo_remap for this asset into assets.json")
    ap.add_argument("--members", help="comma-separated palette members this asset uses; "
                                      "defaults to the asset's palette_members in assets.json")
    a = ap.parse_args()

    out = []
    for t in a.textures:
        if not os.path.exists(t):
            print(f"MISSING {t}")
            continue
        members = None
        if a.members:
            members = [x.strip() for x in a.members.split(",") if x.strip()]
        elif a.emit:
            import json as _j
            _m = _j.load(open(os.path.join(HERE, "..", "assets.json")))
            _row = next((x for x in _m["assets"] if x["name"] == a.emit), None)
            if _row:
                members = _row.get("palette_members")
        r = analyse(t, is_render=a.render, members=members)
        report(r)
        if a.emit:
            print("\n  per-cluster anchors:")
            rm = build_remap(r)
            for an in rm["anchors"]:
                print(f"    {an['member']:15} gain {an['gain']}   chroma_d {an['chroma_dist']}")
            print(f"    sigma {rm['sigma']}")
            emit(a.emit, r)
        out.append(r)

    if len(out) >= 2:
        print("\n=== ACROSS GENERATIONS")
        print(f"{'member':15}" + "".join(f"{o['file'][:16]:>18}" for o in out) + f"{'spread':>10}")
        for i, name in enumerate(lock.PALETTE):
            vals = [o["rows"][i]["lum_ratio"] for o in out]
            print(f"{name:15}" + "".join(f"{v:18.3f}" for v in vals)
                  + f"{max(vals) - min(vals):10.3f}")
        gains = np.array([o["gain"] for o in out])
        print(f"\n  per-channel gain per generation:")
        for o in out:
            print(f"    {o['file'][:34]:36} R {o['gain'][0]:.3f}  G {o['gain'][1]:.3f}  B {o['gain'][2]:.3f}")
        spread = gains.max(0) - gains.min(0)
        print(f"    gain spread across generations: R {spread[0]:.3f}  G {spread[1]:.3f}  B {spread[2]:.3f}")
        if spread.max() < 0.15:
            print("\n  READING: the gain is consistent across generations -> the shift is")
            print("  SYSTEMATIC, and one levels correction in normalization fixes every asset.")
        else:
            print("\n  READING: the gain varies between generations -> colour consistency is NOT")
            print("  achievable through prompting. The material pass must own value and exposure.")


if __name__ == "__main__":
    main()
