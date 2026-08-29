"""Fit rendered luminance against albedo scale. A non-zero intercept is the bug.

    python art/tools/fit_specular.py chest

Reads the renders made by art/blender/probe_specular.py and fits

    rendered_luminance = k * albedo_scale + s

for the specular-on and specular-off series separately.

  s ~= 0  ->  rendered is PROPORTIONAL to albedo, and a multiplicative gain is
              the correct correction. This is what the pipeline has assumed.
  s  > 0  ->  rendered is AFFINE in albedo. A multiplicative gain can then land
              exactly one point on target and must miss every other, by an
              amount that grows with distance from that point. Anchors land at
              1.00x while the region around them skews - which is the signature
              already recorded and never explained.

The specular-off series is the control. If it does not come back with an
intercept near zero, the method is measuring something other than what it
claims and no conclusion can be drawn from the specular-on series either.

`offset_share` is s / (k + s): the fraction of a full-albedo render that comes
from the albedo-independent term. That is the number that says how much this
matters, as opposed to whether it is present at all.
"""

import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DIR = os.path.join(REPO, "art", "renders", "specprobe")
LUM = np.array([0.2126, 0.7152, 0.0722])


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def mean_lum(path):
    im = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0
    sel = im[..., 3] > 0.9
    if not sel.any():
        return float("nan")
    return float((srgb_to_linear(im[..., :3]) @ LUM)[sel].mean())


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "chest"
    meta = json.load(open(os.path.join(DIR, f"{name}_probe.json")))
    series = {}
    for r in meta["runs"]:
        series.setdefault(r["spec"], []).append(
            (r["albedo_scale"], mean_lum(os.path.join(DIR, r["file"]))))

    print(f"{name}: {meta['materials']} material(s), "
          f"mean linear luminance over opaque pixels\n")
    print(f"{'albedo x':>9}  {'spec 0.5':>10}  {'spec 0.0':>10}")
    on = dict(series[0.5])
    off = dict(series[0.0])
    for s in sorted(on):
        print(f"{s:9.2f}  {on[s]:10.5f}  {off[s]:10.5f}")

    print()
    for spec, pts in sorted(series.items(), reverse=True):
        x = np.array([p[0] for p in pts])
        y = np.array([p[1] for p in pts])
        k, s = np.polyfit(x, y, 1)
        pred = k * x + s
        r2 = 1.0 - ((y - pred) ** 2).sum() / max(((y - y.mean()) ** 2).sum(), 1e-18)
        full = k + s
        print(f"  specular {spec:.1f}:  luminance = {k:.5f} * albedo + {s:+.5f}   "
              f"(R2 {r2:.4f})")
        print(f"                 offset_share at albedo 1.0 = "
              f"{s / max(full, 1e-12) * 100:+.1f}% of the render")
    print()
    _, s_on = np.polyfit([p[0] for p in series[0.5]], [p[1] for p in series[0.5]], 1)
    _, s_off = np.polyfit([p[0] for p in series[0.0]], [p[1] for p in series[0.0]], 1)
    print(f"  control (specular off) intercept {s_off:+.5f} - near zero means the")
    print(f"  method can see proportionality when it is there.")
    print(f"  finding (specular on)  intercept {s_on:+.5f}")


if __name__ == "__main__":
    main()
