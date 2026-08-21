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

K = 10
ITERS = 40
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


def analyse(path, sample=200_000, is_render=False):
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

    cent, w = kmeans(lin, K)

    pal = {n: hexlin(h) for n, h in lock.PALETTE.items()}
    cc = chromaticity(cent)

    # greedy one-to-one assignment on chromaticity distance
    pairs = []
    for name, p in pal.items():
        pc = chromaticity(p)
        d = np.linalg.norm(cc - pc, axis=1)
        pairs.append((name, d))
    used, result = set(), {}
    flat = sorted(((d[i], name, i) for name, d in pairs for i in range(K)))
    for dist, name, i in flat:
        if name in result or i in used:
            continue
        result[name] = (i, dist)
        used.add(i)

    rows = []
    for name, p in pal.items():
        i, cdist = result[name]
        o = cent[i]
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
            "cluster_pct": float(w[i] * 100),
        })

    P = np.array([r["palette_lin"] for r in rows])
    O = np.array([r["observed_lin"] for r in rows])
    gain = (P * O).sum(0) / np.maximum((P * P).sum(0), 1e-12)   # per-channel least squares
    resid = O - P * gain
    return {
        "file": os.path.basename(path),
        "mask_pct": mask_pct,
        "rows": rows,
        "gain": gain,
        "resid_rms": float(np.sqrt((resid ** 2).mean())),
        "raw_rms": float(np.sqrt(((O - P) ** 2).mean())),
    }


def report(a):
    print(f"\n=== {a['file']}   (mask texels excluded: {a['mask_pct']:.2f}%)")
    print(f"{'member':15}{'locked':9}{'observed':10}{'|delta|':>9}{'lum ratio':>11}"
          f"{'chroma d':>10}{'cluster':>9}")
    for r in a["rows"]:
        print(f"{r['member']:15}{r['palette_hex']:9}{r['observed_hex']:10}"
              f"{r['delta_mag']:9.4f}{r['lum_ratio']:11.3f}"
              f"{r['chroma_dist']:10.4f}{r['cluster_pct']:8.1f}%")
    g = a["gain"]
    print(f"  best single per-channel gain: R {g[0]:.3f}  G {g[1]:.3f}  B {g[2]:.3f}")
    print(f"  RMS error   raw {a['raw_rms']:.4f}  ->  after gain {a['resid_rms']:.4f}"
          f"   ({(1 - a['resid_rms'] / max(a['raw_rms'], 1e-9)) * 100:.0f}% explained)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("textures", nargs="+")
    ap.add_argument("--render", action="store_true",
                    help="inputs are rendered RGBA sprites/masters, not albedo textures")
    a = ap.parse_args()

    out = []
    for t in a.textures:
        if not os.path.exists(t):
            print(f"MISSING {t}")
            continue
        r = analyse(t, is_render=a.render)
        report(r)
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
