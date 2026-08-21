"""Detail-density conformance. Two numbers per asset.

    python art/tools/detail_density.py smelter_idle chest power_pole

1. FEATURE COUNT PER OCCUPIED TILE, against the cap of six.
   Counted at FINAL sprite resolution, because that is where "readable" is
   decided. Sobel edge magnitude -> threshold -> connected components of at
   least 3 px. Reported at three thresholds so the figure is not cherry-picked
   by one lucky cutoff.

   DENOMINATOR FIX: divided by OCCUPIED SILHOUETTE AREA (opaque px / 32^2),
   not by footprint tiles. Dividing by footprint punished thin objects that do
   not fill their tile - it scored the flat untextured pole proxy at 11.0
   features/tile, worse than the heavily textured kiln at 8.75, which is
   obviously backwards. Occupied area is what the eye actually reads.

2. HIGH-FREQUENCY SURVIVAL - the cobble problem as a number.
   Rendering at 4x and downsampling to 1x cannot carry any spatial frequency
   above one quarter of the master's Nyquist limit. So: take the 4x master,
   measure its power spectrum, and report what fraction of the AC energy sits
   above that cutoff. That fraction is destroyed by the downsample no matter
   how good the filter is - it is generation effort that provably cannot reach
   the screen.

   TARGET FIX: the pass mark is a RATIO against the flat-geometry floor, not
   an absolute percentage. Flat untextured proxies measure ~2%, so the budget
   is "under 3x the floor" - about 6% today, and it recalibrates itself as the
   reference assets change. The rejected kiln was 14.3%, i.e. 7x the floor.

   The opaque region is cropped and its transparent surround filled with the
   mean opaque luminance, so the silhouette boundary does not ring; a Hann
   window suppresses the remaining edge discontinuity.
"""

import argparse
import json
import os

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CAP_PER_TILE = 6
SUPERSAMPLE = 4
TILE_PX = 32
HF_RATIO_CAP = 3.0                        # pass mark: under 3x the flat floor
FLOOR_REFS = ("chest", "power_pole")      # flat untextured proxies define the floor


def luma(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def load(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0
    return a[..., :3], a[..., 3]


def sobel(g):
    kx = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.float32)
    ky = kx.T
    p = np.pad(g, 1, mode="edge")
    gx = sum(kx[i, j] * p[i:i + g.shape[0], j:j + g.shape[1]]
             for i in range(3) for j in range(3))
    gy = sum(ky[i, j] * p[i:i + g.shape[0], j:j + g.shape[1]]
             for i in range(3) for j in range(3))
    return np.hypot(gx, gy)


def components(mask, min_area=3):
    """Connected components (4-neighbour), iterative flood fill."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    count = 0
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            stack, area = [(sy, sx)], 0
            seen[sy, sx] = True
            while stack:
                y, x = stack.pop()
                area += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if area >= min_area:
                count += 1
    return count


def feature_count(sprite_path, footprint_tiles):
    rgb, a = load(sprite_path)
    op = a > 0.5
    if op.sum() == 0:
        return {}
    g = luma(rgb) * op
    e = sobel(g)
    vals = e[op]
    out = {}
    for pct in (75, 85, 92):
        thr = np.percentile(vals, pct)
        n = components((e >= thr) & op, min_area=3)
        out[f"p{pct}"] = n

    occupied_tiles = op.sum() / float(TILE_PX * TILE_PX)
    footprint_area = max(1.0, footprint_tiles ** 2)
    return {
        "thresholds": out,
        "occupied_px": int(op.sum()),
        "occupied_tiles": round(occupied_tiles, 3),
        "footprint_area_tiles": footprint_area,
        "fill_ratio": round(occupied_tiles / footprint_area, 3),
        # per OCCUPIED tile - the metric that matters
        "per_tile": {k: round(v / max(occupied_tiles, 1e-6), 2) for k, v in out.items()},
        # kept only to show what the old denominator did
        "per_footprint_tile_legacy": {k: round(v / footprint_area, 2) for k, v in out.items()},
    }


def hf_survival(master_path):
    rgb, a = load(master_path)
    op = a > 0.5
    ys, xs = np.nonzero(op)
    if len(xs) == 0:
        return {}
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    g = luma(rgb)[y0:y1 + 1, x0:x1 + 1]
    m = op[y0:y1 + 1, x0:x1 + 1]

    # fill the transparent surround with the mean opaque value so the
    # silhouette boundary is not a step to black
    g = np.where(m, g, g[m].mean())
    g = g - g.mean()

    h, w = g.shape
    win = np.outer(np.hanning(h), np.hanning(w))
    F = np.fft.fftshift(np.fft.fft2(g * win))
    P = (F.real ** 2 + F.imag ** 2)

    fy = np.fft.fftshift(np.fft.fftfreq(h)) * 2.0   # Nyquist -> 1.0
    fx = np.fft.fftshift(np.fft.fftfreq(w)) * 2.0
    R = np.hypot(*np.meshgrid(fx, fy, indexing="xy"))

    ac = R > 1e-9
    cutoff = 1.0 / SUPERSAMPLE          # what a 4x downsample can still carry
    total = P[ac].sum()
    lost = P[ac & (R > cutoff)].sum()

    bands = {}
    edges = [0.0, 0.125, 0.25, 0.5, 1.0, 1.5]
    for lo, hi in zip(edges[:-1], edges[1:]):
        sel = ac & (R > lo) & (R <= hi)
        bands[f"{lo:.3f}-{hi:.3f}"] = round(float(P[sel].sum() / total * 100), 1)

    return {
        "master_px": [int(w), int(h)],
        "cutoff_norm_freq": cutoff,
        "energy_lost_pct": round(float(lost / total * 100), 1),
        "energy_bands_pct": bands,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="+", help="sprite basenames, e.g. smelter_idle")
    ap.add_argument("--json", help="write the report here")
    ap.add_argument("--floor-refs", nargs="*", default=list(FLOOR_REFS),
                    help="flat-geometry sprites that define the HF floor")
    a = ap.parse_args()

    # Establish the floor first, so the HF budget recalibrates itself.
    floor_vals = []
    for ref in a.floor_refs:
        m = os.path.join(REPO, "art", "renders", f"{ref}_4x.png")
        if os.path.exists(m):
            h = hf_survival(m)
            if h:
                floor_vals.append(h["energy_lost_pct"])
    floor = float(np.mean(floor_vals)) if floor_vals else None
    if floor:
        print(f"flat-geometry HF floor: {floor:.2f}% "
              f"(mean of {', '.join(a.floor_refs)})   budget = {HF_RATIO_CAP:g}x = {floor*HF_RATIO_CAP:.1f}%")

    report = {"hf_floor_pct": round(floor, 2) if floor else None,
              "hf_ratio_cap": HF_RATIO_CAP}
    for n in a.names:
        sprite = os.path.join(REPO, "art", "sprites", f"{n}.png")
        master = os.path.join(REPO, "art", "renders", f"{n}_4x.png")
        if not os.path.exists(sprite):
            print(f"MISSING {sprite}")
            continue

        # footprint from whichever metadata file lists this sprite
        fp = 1.0
        for cand in os.listdir(os.path.join(REPO, "art", "sprites")):
            if not cand.endswith(".json"):
                continue
            d = json.load(open(os.path.join(REPO, "art", "sprites", cand)))
            if any(m.get("tag") == n for m in d.get("masters", [])):
                fp = float(d.get("footprint_tiles", 1))
                break

        fc = feature_count(sprite, fp)
        hf = hf_survival(master) if os.path.exists(master) else {}
        report[n] = {"footprint_tiles": fp, "features": fc, "high_frequency": hf}

        print(f"\n=== {n}   footprint {fp:g}x{fp:g}")
        if fc:
            print(f"  occupied {fc['occupied_px']} px = {fc['occupied_tiles']:.2f} tile-equivalents "
                  f"({fc['fill_ratio']*100:.0f}% of its footprint)")
            for k in ("p75", "p85", "p92"):
                tot = fc["thresholds"][k]
                per = fc["per_tile"][k]
                old = fc["per_footprint_tile_legacy"][k]
                flag = "OVER CAP" if per > CAP_PER_TILE else "ok"
                print(f"  features @{k}: {tot:4d} total   {per:6.2f}/occupied-tile   "
                      f"cap {CAP_PER_TILE}   {flag}   (old denominator: {old:.2f})")
        if hf:
            lost = hf["energy_lost_pct"]
            print(f"  4x master {hf['master_px'][0]}x{hf['master_px'][1]}")
            if floor:
                ratio = lost / floor
                verdict = "PASS" if ratio <= HF_RATIO_CAP else "FAIL"
                print(f"  HF energy destroyed: {lost}%   = {ratio:.2f}x the {floor:.2f}% floor"
                      f"   (cap {HF_RATIO_CAP:g}x)   {verdict}")
                report[n]["hf_ratio"] = round(ratio, 2)
                report[n]["hf_verdict"] = verdict
            else:
                print(f"  HF energy destroyed: {lost}%")
            print(f"  energy by normalised frequency band (1.0 = master Nyquist):")
            for band, pct in hf["energy_bands_pct"].items():
                lo = float(band.split("-")[0])
                mark = "  <- survives" if lo < 0.25 else "  <- destroyed"
                print(f"      {band}: {pct:5.1f}%{mark}")

    if a.json:
        with open(a.json, "w") as f:
            json.dump(report, f, indent=2)
        print(f"\nJSON {a.json}")


if __name__ == "__main__":
    main()
