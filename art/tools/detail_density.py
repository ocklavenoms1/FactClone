"""Detail-density conformance.

DIAGNOSTIC, NOT A GATE. High-frequency destruction as a ratio to the synthetic
floor. Reported every run; it does not block anything.

It earned its keep on the first kiln, where cobbles genuinely turned to mud at
32px and this number caught it. Then it rejected a power pole that looked good,
and an asset was over-tuned to satisfy it into looking plastic. A gate that
fails good work is worse than no gate, so it went back to being a diagnostic.

THE GATE IS THE 32PX SPRITE, JUDGED BY EYE - see art/tools/eye_sheet.py. If a
high number ever coincides with a sprite that genuinely reads as mud, the number
was right. It does not get to reject on its own.

    python art/tools/detail_density.py smelter_idle chest power_pole

HOW THE HF NUMBER IS COMPUTED
   Rendering at 4x and downsampling to 1x cannot carry any spatial frequency
   above one quarter of the master's Nyquist limit. Take the 4x master, measure
   its power spectrum, and report the fraction of AC energy above that cutoff:
   that fraction is destroyed by the downsample however good the filter is.

   Reported as a RATIO against the permanent synthetic floor, so it is a
   multiple of "what a compliant untextured building costs" rather than a bare
   percentage. 3x is a useful reference band, not a pass mark.

EVERYTHING HERE IS REPORTED, NOTHING HERE ENFORCES
   Feature count is divided by OCCUPIED SILHOUETTE AREA rather than footprint
   tiles. That is the right denominator, but be clear about what it does NOT
   fix: the flat pole proxy scores WORSE under it (11.0 -> 17.8), because it
   occupies only 0.62 tile-equivalents. A thin object is nearly all edge and no
   normalization changes that - which is exactly why this is not a gate.

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
CAP_PER_TILE = 4                          # tightened from 6: 87% of features were under 2px
SUPERSAMPLE = 4
TILE_PX = 32
HF_RATIO_CAP = 3.0                        # reference band, NOT a pass mark - see the
                                          # module docstring. The eye is the gate.
CONTRAST_COSTLY = 0.12                    # luminance range above which thin detail costs
# THE FLOOR IS A FIXED SYNTHETIC OBJECT, never a real asset.
# It used to be whichever proxies were lying around, and it moved: when
# power_pole graduated from proxy to real it had to leave the floor, and the
# smelter's ratio shifted 1.45x -> 1.67x on BYTE-IDENTICAL pixels. A floor that
# moves is not a floor, and a gate whose denominator drifts will eventually pass
# something it should have caught.
FLOOR_REFS = ("_calib_floor",)
# Measured once and recorded here. The tool reports the live floor against this
# every run, so drift is visible rather than silent.
FLOOR_EXPECTED_PCT = None                 # set after the first calibration run
FLOOR_DRIFT_WARN = 0.15                   # warn if the live floor moves >15%


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


def components(mask, min_area=3, want_sizes=False, lumimg=None):
    """Connected components (4-neighbour), iterative flood fill.

    With want_sizes, also returns per component (thickness, contrast):
    thickness in FINAL pixels as area / longest-bbox-side (a 1px-wide streak
    10px long is 1.0; a compact 4x4 blob is 4.0), and contrast as the luminance
    range across the component's pixels.

    Thickness alone is the wrong diagnostic. The approved smelter has 16 of 20
    features under 2px yet the LOWEST HF destruction of the set at 1.45x floor,
    because its sub-2px rivets are low-contrast and average harmlessly into the
    strap. Sub-2px detail is only wasteful when it is ALSO high-contrast: a thin
    high-contrast edge is what costs, a thin low-contrast dot is free.
    """
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    count, sizes = 0, []
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or seen[sy, sx]:
                continue
            stack, area = [(sy, sx)], 0
            y0 = y1 = sy
            x0 = x1 = sx
            px = []
            seen[sy, sx] = True
            while stack:
                y, x = stack.pop()
                area += 1
                y0, y1 = min(y0, y), max(y1, y)
                x0, x1 = min(x0, x), max(x1, x)
                if lumimg is not None:
                    px.append(lumimg[y, x])
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if area >= min_area:
                count += 1
                if want_sizes:
                    longest = max(y1 - y0 + 1, x1 - x0 + 1)
                    contrast = (max(px) - min(px)) if px else 0.0
                    sizes.append((area / max(longest, 1), float(contrast)))
    return (count, sizes) if want_sizes else count


def feature_count(sprite_path, footprint_tiles):
    rgb, a = load(sprite_path)
    op = a > 0.5
    if op.sum() == 0:
        return {}
    g = luma(rgb) * op
    e = sobel(g)
    vals = e[op]
    out, sizes = {}, []
    for pct in (75, 85, 92):
        thr = np.percentile(vals, pct)
        if pct == 85:
            n, sizes = components((e >= thr) & op, min_area=3, want_sizes=True,
                                  lumimg=luma(rgb))
        else:
            n = components((e >= thr) & op, min_area=3)
        out[f"p{pct}"] = n

    thin = {}
    if sizes:
        arr = np.array(sizes)
        th, ct = arr[:, 0], arr[:, 1]
        thin_mask = th < 2.0
        hot = thin_mask & (ct >= CONTRAST_COSTLY)
        cold = thin_mask & (ct < CONTRAST_COSTLY)
        thin = {
            "median_thickness_px": round(float(np.median(th)), 2),
            "p10_thickness_px": round(float(np.percentile(th, 10)), 2),
            "under_2px_pct": round(float(thin_mask.mean() * 100), 1),
            "median_contrast": round(float(np.median(ct)), 3),
            # the number that matters: thin AND high-contrast
            "thin_costly": int(hot.sum()),
            "thin_free": int(cold.sum()),
            "thin_costly_pct": round(float(hot.mean() * 100), 1),
        }

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
        "feature_thickness": thin,
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
        note = ""
        if FLOOR_EXPECTED_PCT:
            drift = floor / FLOOR_EXPECTED_PCT - 1.0
            note = f"   [expected {FLOOR_EXPECTED_PCT:.2f}%, drift {drift*100:+.1f}%]"
            if abs(drift) > FLOOR_DRIFT_WARN:
                note += "  ** FLOOR HAS DRIFTED - the gate denominator moved **"
        print(f"HF floor: {floor:.2f}%  from {', '.join(a.floor_refs)} "
              f"(synthetic, permanent){note}")
        print(f"  budget = {HF_RATIO_CAP:g}x = {floor*HF_RATIO_CAP:.1f}%")

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
            print("  [diagnostic, not a gate] feature counts:")
            for k in ("p75", "p85", "p92"):
                tot = fc["thresholds"][k]
                per = fc["per_tile"][k]
                print(f"      @{k}: {tot:4d} total   {per:6.2f}/occupied-tile")
            th = fc.get("feature_thickness") or {}
            if th:
                print(f"  [diagnostic] thickness x contrast, FINAL px:")
                print(f"      median thickness {th['median_thickness_px']}px, "
                      f"{th['under_2px_pct']}% under 2px, median contrast {th['median_contrast']}")
                print(f"      sub-2px COSTLY (contrast >= {CONTRAST_COSTLY}): "
                      f"{th['thin_costly']}  <- the ones that actually waste budget")
                print(f"      sub-2px free   (low contrast, averages away): "
                      f"{th['thin_free']}")
        if hf:
            lost = hf["energy_lost_pct"]
            print(f"  4x master {hf['master_px'][0]}x{hf['master_px'][1]}")
            if floor:
                ratio = lost / floor
                note = "" if ratio <= HF_RATIO_CAP else "  (above the 3x reference band)"
                print(f"  [diagnostic] HF energy destroyed: {lost}%   "
                      f"= {ratio:.2f}x the {floor:.2f}% floor{note}")
                report[n]["hf_ratio"] = round(ratio, 2)
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
