"""Where does an asset's high-frequency cost actually come from?

    python art/tools/hf_regions.py power_pole

`detail_density.py` gives one number for the whole sprite. When that number is
too high, this says WHICH PART of the asset is spending it - so the prompt fix
targets the real source instead of the most visible one.

TWO DECOMPOSITIONS

1. BY REGION. Split the silhouette into base / mast / crossarm from the
   column-width profile, then measure each region's contribution as

       contribution = HF(full) - HF(that region flattened to its local mean)

   Flattening rather than deleting keeps the silhouette intact, so the number
   isolates the region's TEXTURE rather than its outline.

2. BY ORIENTATION, within a region. Vertical stripes (wood grain running up the
   mast) put their energy in the horizontal-frequency axis; horizontal stripes
   (iron bands crossing the mast) put theirs in the vertical axis. Splitting the
   destroyed energy by which axis dominates separates grain from bands without
   needing to segment them spatially at all.

That second split is the one that matters here: grain and bands overlap in the
same pixels, so no spatial mask could ever tell them apart.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SUPERSAMPLE = 4


def luma(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def load(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0
    return a[..., :3], a[..., 3]


def box_blur(img, r):
    pad = np.pad(img, r, mode="edge")
    c = np.cumsum(np.cumsum(pad, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)), mode="constant")
    h, w = img.shape
    k = 2 * r + 1
    tot = c[k:k + h, k:k + w] - c[0:h, k:k + w] - c[k:k + h, 0:w] + c[0:h, 0:w]
    return tot / (k * k)


def hf_of(lum, mask, split=False):
    """Fraction of AC energy above the downsample cutoff. Optionally also the
    split of that lost energy into vertical-stripe vs horizontal-stripe."""
    ys, xs = np.nonzero(mask)
    if len(xs) < 64:
        return (0.0, 0.0, 0.0) if split else 0.0
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    g = lum[y0:y1 + 1, x0:x1 + 1].copy()
    m = mask[y0:y1 + 1, x0:x1 + 1]
    g = np.where(m, g, g[m].mean())
    g = g - g.mean()

    h, w = g.shape
    win = np.outer(np.hanning(h), np.hanning(w))
    F = np.fft.fftshift(np.fft.fft2(g * win))
    P = F.real ** 2 + F.imag ** 2

    fy = np.fft.fftshift(np.fft.fftfreq(h)) * 2.0
    fx = np.fft.fftshift(np.fft.fftfreq(w)) * 2.0
    FX, FY = np.meshgrid(fx, fy, indexing="xy")
    R = np.hypot(FX, FY)

    ac = R > 1e-9
    cutoff = 1.0 / SUPERSAMPLE
    total = P[ac].sum()
    lost_mask = ac & (R > cutoff)
    lost = P[lost_mask].sum()
    frac = float(lost / max(total, 1e-12) * 100)
    if not split:
        return frac

    # vertical stripes vary along x -> energy where |fx| > |fy|
    vert = P[lost_mask & (np.abs(FX) > np.abs(FY))].sum()
    horiz = P[lost_mask & (np.abs(FY) >= np.abs(FX))].sum()
    tot2 = max(vert + horiz, 1e-12)
    return frac, float(vert / tot2 * 100), float(horiz / tot2 * 100)


def regions_from_profile(mask):
    """base / mast / crossarm from the column-width profile."""
    cols = mask.sum(axis=0)
    rows = mask.sum(axis=1)
    ys = np.nonzero(rows)[0]
    y0, y1 = ys.min(), ys.max()
    H = y1 - y0 + 1

    widths = np.array([mask[y].sum() for y in range(y0, y1 + 1)], dtype=float)
    med = np.median(widths[widths > 0])

    reg = np.zeros(mask.shape, dtype=np.uint8)   # 1 base, 2 mast, 3 crossarm
    for i, y in enumerate(range(y0, y1 + 1)):
        rel = (y - y0) / max(H - 1, 1)
        w = widths[i]
        if rel > 0.80 and w > med * 1.15:
            reg[y] = 1                      # wide and low -> base plate
        elif rel < 0.45 and w > med * 1.35:
            reg[y] = 3                      # wide and high -> crossarm
        else:
            reg[y] = 2                      # everything else -> mast
    reg[~mask] = 0
    return reg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--suffix", default="")
    a = ap.parse_args()

    master = os.path.join(REPO, "art", "renders", f"{a.name}{a.suffix}_4x.png")
    if not os.path.exists(master):
        print(f"MISSING {master}")
        return 1
    rgb, al = load(master)
    mask = al > 0.5
    lum = luma(rgb)

    base_hf, v_all, h_all = hf_of(lum, mask, split=True)
    print(f"{a.name}{a.suffix}   master {rgb.shape[1]}x{rgb.shape[0]}")
    print(f"  TOTAL HF destroyed: {base_hf:.2f}%")
    print(f"  of that lost energy:  vertical stripes {v_all:.0f}%   "
          f"horizontal stripes {h_all:.0f}%")
    print("     (vertical stripes = grain running up the mast;")
    print("      horizontal stripes = bands crossing it)")

    reg = regions_from_profile(mask)
    names = {1: "base plate", 2: "mast", 3: "crossarm"}
    print(f"\n  contribution by region (HF minus HF with that region flattened):")
    print(f"  {'region':12}{'px share':>10}{'HF if flat':>12}{'contribution':>14}")
    rows = []
    for rid in (2, 3, 1):
        sel = reg == rid
        if sel.sum() < 64:
            continue
        flat = lum.copy()
        blurred = box_blur(lum, max(3, int(min(rgb.shape[:2]) * 0.05)))
        flat[sel] = blurred[sel]
        hf_flat = hf_of(flat, mask)
        contrib = base_hf - hf_flat
        rows.append((names[rid], sel.sum() / max(mask.sum(), 1) * 100, hf_flat, contrib))
    for n, share, hff, c in sorted(rows, key=lambda r: -r[3]):
        print(f"  {n:12}{share:9.1f}%{hff:11.2f}%{c:13.2f}%")

    # orientation split inside the mast only
    mast = reg == 2
    if mast.sum() > 64:
        _, v, h = hf_of(lum, mast, split=True)
        print(f"\n  INSIDE THE MAST, the destroyed energy splits:")
        print(f"    vertical stripes (wood grain) : {v:.0f}%")
        print(f"    horizontal stripes (bands)    : {h:.0f}%")
        verdict = ("GRAIN dominates - the fix is 'no visible wood grain'"
                   if v > 60 else
                   "BANDS dominate - the fix is fewer / lower-contrast bands"
                   if h > 60 else
                   "neither dominates - grain and bands cost comparably")
        print(f"    -> {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
