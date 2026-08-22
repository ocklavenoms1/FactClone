"""Build gate: the albedo's baked light must not OPPOSE the locked rig.

    blender -b art/template.blend -P art/blender/render_rigonly.py -- --name smelter
    python art/tools/assert_rig_correlation.py smelter

WHY THIS IS A GATE AND NOT A DIAGNOSTIC
The approved smelter measured +0.443 - its baked directional light happens to
run WITH the rig's key, so it exaggerates the rig's own shading rather than
fighting it. That was fortunate, not designed: the concept image carried a
painted falloff despite the prompt demanding flat lighting, and it happened to
fall near the key.

An asset lit from the opposite side would OPPOSE the rig. Every downstream
number would still look fine - the palette matches, the HF gate passes, the
states differ - and nothing would notice until a human looked at the verdict
sheet and saw one building lit from the wrong side.

So the SIGN is a hard gate. Negative fails the build.

MAGNITUDE IS ADVISORY, deliberately. A large positive correlation means the
albedo is doing a lot of the lighting, which is a cross-asset consistency risk
because the amount varies per asset and the remap does not correct it. But
there is only one reference asset so far, and a threshold picked from n=1 is a
guess. It is reported every build and gets a limit once three assets exist.

METHOD
Divide the rig out of the real render, in log space, leaving the asset's own
albedo plus whatever light was baked into it. Correlate that against the rig's
own shading:

    implied_albedo = log(real) - log(rig_only)
    correlation(implied_albedo, log(rig_only))

Positive: baked light runs with the rig. Negative: it runs against it.
"""

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def load(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0
    return a[..., :3], a[..., 3]


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def lum(rgb):
    l = srgb_to_linear(rgb)
    return l[..., 0] * 0.2126 + l[..., 1] * 0.7152 + l[..., 2] * 0.0722


def body_master(name):
    meta_path = os.path.join(REPO, "art", "sprites", f"{name}.json")
    if os.path.exists(meta_path):
        meta = json.load(open(meta_path))
        for m in meta.get("masters", []):
            if m.get("yaw") in (None, 0):
                return os.path.join(REPO, m["master"])
    for cand in (f"{name}_idle_4x.png", f"{name}_4x.png"):
        p = os.path.join(REPO, "art", "renders", cand)
        if os.path.exists(p):
            return p
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="+")
    a = ap.parse_args()

    failures = []
    for name in a.names:
        rig = os.path.join(REPO, "art", "renders", f"{name}_rigonly_4x.png")
        real = body_master(name)
        if not real or not os.path.exists(rig):
            print(f"  [--  ] {name}: no rig-only render to compare (skipped)")
            continue

        rgb_r, ar = load(real)
        rgb_g, ag = load(rig)
        if rgb_r.shape != rgb_g.shape:
            print(f"  [--  ] {name}: render sizes differ, cannot compare")
            continue

        m = (ar > 0.5) & (ag > 0.5)
        if m.sum() < 200:
            print(f"  [--  ] {name}: too few shared opaque pixels")
            continue

        lr = np.log(np.maximum(lum(rgb_r)[m], 1e-5))
        lg = np.log(np.maximum(lum(rgb_g)[m], 1e-5))
        implied = lr - lg
        corr = float(np.corrcoef(implied, lg)[0, 1])
        rig_share = float(lg.var() / max(lr.var(), 1e-12))

        if corr < 0:
            verdict = "FAIL"
            failures.append((name, corr))
        else:
            verdict = "ok  "
        mag = ("strong" if abs(corr) > 0.6 else "moderate" if abs(corr) > 0.3 else "weak")
        print(f"  [{verdict}] {name}: albedo x rig correlation {corr:+.3f} ({mag}), "
              f"rig accounts for {rig_share * 100:.0f}% of sprite variance")

    if failures:
        print("\nRIG CORRELATION ASSERTION FAILED:")
        for n, c in failures:
            print(f"  {n}: {c:+.3f} - the albedo's baked light OPPOSES the locked rig.")
        print("The concept image was lit from the wrong side. Nothing else in the")
        print("pipeline would have noticed: the palette still matches, the HF gate")
        print("still passes, the states still differ. Regenerate with the key from")
        print("screen upper-left, matching the rig.")
        return 1

    print("\nrig correlation: no asset opposes the rig")
    return 0


if __name__ == "__main__":
    sys.exit(main())
