"""Solve each doodad's albedo value scale against BOTH bounds. Take the min.

    python art/tools/calibrate_doodads.py            # solve all, write the manifest
    python art/tools/calibrate_doodads.py --dry      # measure only

The bounds are in assert_doodad_contrast.py:
  (1) median <= ground * MEDIAN_CAP      - does it read as an object
  (2) p95    <= pooled building p50      - does it outshine a machine

Solved, not iterated. With the specular lobe off the doodad material is pure
Lambertian, so rendered luminance is EXACTLY proportional to the albedo scale -
which means one render at scale 1.0 determines the answer for every scale, and
each bound gives a closed-form scale:

    scale_1 = median_ceiling / median(L at 1.0)
    scale_2 = p95_ceiling    / p95(L at 1.0)
    scale   = min(scale_1, scale_2)

The min is where the trade lives. Because p95 ~= median * sqrt(internal range),
a doodad with more internal form has a longer tail above its median, so bound
(2) binds first and pushes it darker. The busiest form ends up quietest, with
nothing tuned by hand.

That proportionality is not an assumption - it is the thing the specular probe
established (PIPELINE.md 35), and it is only true because doodad materials set
Specular IOR Level to 0. With the default 0.5 lobe, rendered luminance is
AFFINE in albedo and none of this closed form holds.
"""

import argparse
import json
import os
import subprocess
import sys

import numpy as np

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assert_doodad_contrast as gate  # noqa: E402

BLENDER = os.environ.get("BLENDER",
                         r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
# Aim just inside each bound. A doodad solved to land exactly on a ceiling is
# one resample away from crossing it, and a gate that trips on its own
# calibration output teaches people to rerun until it passes.
MARGIN = 0.96


def render(name, scale):
    subprocess.run([BLENDER, "-b", os.path.join(REPO, "art", "template.blend"),
                    "-P", os.path.join(REPO, "art", "blender", "make_doodads.py"),
                    "--", "--name", name, "--vscale", f"{scale:.6f}"],
                   capture_output=True, check=True)
    subprocess.run([sys.executable,
                    os.path.join(REPO, "art", "tools", "downsample_doodads.py"), name],
                   capture_output=True, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("names", nargs="*")
    a = ap.parse_args()

    mpath = os.path.join(REPO, "art", "doodads.json")
    man = json.load(open(mpath))
    gl = float(gate.LUM @ gate.hex_lin(man["ground_hex"]))
    mcap = float(man.get("median_cap", 1.25))
    med_ceiling = gl * mcap
    bld = gate.building_p50()
    print(f"  ground rel-lum {gl:.4f}   median ceiling {med_ceiling:.4f} "
          f"({mcap}:1)   building p50 ceiling {bld:.4f}")

    for d in man["doodads"]:
        if d.get("status") == "calibration":
            continue
        if a.names and d["name"] not in a.names:
            continue
        name = d["name"]
        render(name, 1.0)
        l = gate.lum_of(os.path.join(REPO, "art", "sprites", "doodads", f"{name}.png"))
        med1, p951 = float(np.median(l)), float(np.percentile(l, 95))
        s_med = med_ceiling / max(med1, 1e-12)
        s_p95 = bld / max(p951, 1e-12)
        scale = min(s_med, s_p95) * MARGIN
        binder = "median-vs-ground" if s_med < s_p95 else "p95-vs-buildings"
        render(name, scale)
        l2 = gate.lum_of(os.path.join(REPO, "art", "sprites", "doodads", f"{name}.png"))
        rng = float(np.percentile(l2, 95)) / max(float(np.percentile(l2, 5)), 1e-12)
        d["albedo_value_scale"] = round(scale, 4)
        print(f"  {name:15} scale {scale:7.4f}  binds on {binder:17} "
              f"median {np.median(l2):.4f} ({np.median(l2) / gl:4.2f}:1)  "
              f"p95 {np.percentile(l2, 95):.4f}  own range {rng:4.2f}:1")

    if not a.dry:
        json.dump(man, open(mpath, "w"), indent=2)
        print("  wrote albedo_value_scale into art/doodads.json")


if __name__ == "__main__":
    main()
