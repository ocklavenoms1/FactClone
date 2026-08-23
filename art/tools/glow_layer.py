"""Extract the fire as a separate additive layer.

    python art/tools/glow_layer.py --name smelter --body idle --lit smelting

Godot draws the BODY sprite, then this layer on top with additive blending and
pulses `modulate.a` for flicker. That buys the Factorio "alive" read with zero
animation frames and zero extra geometry.

HOW THE LAYER IS DERIVED
glow = lit_render - body_render, per pixel, clamped at zero.

That difference is exactly the light the fire adds, which means it carries for
free everything a hand-painted glow sprite would not:
  * the spill onto the surrounding hearth stones and arch voussoirs
  * correct occlusion, since both renders share geometry and camera
  * the falloff of the light, rather than a guessed gradient

The subtraction happens on the 4x masters in premultiplied space, and the
result goes through the same premultiplied LANCZOS downsample as everything
else, so the layer is filtered exactly once and lands pixel-aligned with the
body sprite.

STORAGE
RGB holds the fire's colour normalized to its brightest channel; A holds the
intensity. Additive compositing reconstructs the lit render:

    dst += rgb * a

and scaling `a` dims the fire without shifting its hue - which is what a
flicker pulse needs.

NOT exactly, though - this file used to claim "exactly" and that was wrong.
Measured on the smelter: body+glow at full strength differs from the direct lit
render by up to 47/255 on the 513 lit pixels, mean 5.7/255. It is not clipping;
the pixels that clip are actually the ACCURATE ones (mean error 3.5 vs 5.9 for
the rest). The cause is that the chain is not linear end to end - the
difference is clamped at zero before the downsample, and LANCZOS has negative
lobes, so clamp-then-resample and resample-then-clamp disagree at the fire's
soft edge, and the normalize/8-bit round-trip adds a little more.

The error is invisible at 32px and does not need fixing. It does need to be
stated, because the composite is what SHIPS and the lit render is only a
staging artifact - so eye sheets must be built from body+glow, never from the
lit render, or an approval is judging pixels no player will see.
"""

import argparse
import json
import os

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def premultiplied(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255.0
    return a[..., :3] * a[..., 3:4], a[..., 3:4]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--body", default="idle")
    ap.add_argument("--lit", default="smelting")
    ap.add_argument("--floor", type=float, default=2.0 / 255.0,
                    help="ignore differences below this; kills sampling noise")
    a = ap.parse_args()

    meta_path = os.path.join(REPO, "art", "sprites", f"{a.name}.json")
    meta = json.load(open(meta_path))
    sw, sh = meta["sprite_px"]

    body_m = os.path.join(REPO, "art", "renders", f"{a.name}_{a.body}_4x.png")
    lit_m = os.path.join(REPO, "art", "renders", f"{a.name}_{a.lit}_4x.png")
    for p in (body_m, lit_m):
        if not os.path.exists(p):
            print(f"MISSING {p}")
            return 1

    b_rgb, b_a = premultiplied(body_m)
    l_rgb, l_a = premultiplied(lit_m)
    if b_rgb.shape != l_rgb.shape:
        print("MISMATCH: body and lit masters differ in size")
        return 1

    delta = np.clip(l_rgb - b_rgb, 0.0, None)
    delta[delta < a.floor] = 0.0

    intensity = delta.max(axis=-1, keepdims=True)
    with np.errstate(divide="ignore", invalid="ignore"):
        hue = np.where(intensity > 1e-6, delta / np.maximum(intensity, 1e-6), 0.0)

    # store premultiplied so the LANCZOS downsample treats it like any sprite
    pre = np.concatenate([np.clip(hue, 0, 1) * intensity, np.clip(intensity, 0, 1)], axis=-1)
    big = Image.fromarray((np.clip(pre, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGBA")
    small = big.resize((sw, sh), Image.Resampling.LANCZOS)

    s = np.asarray(small).astype(np.float32) / 255.0
    sa = s[..., 3:4]
    with np.errstate(divide="ignore", invalid="ignore"):
        srgb = np.where(sa > 1e-4, s[..., :3] / np.maximum(sa, 1e-6), 0.0)
    out = np.concatenate([np.clip(srgb, 0, 1), np.clip(sa, 0, 1)], axis=-1)

    out_path = os.path.join(REPO, "art", "sprites", f"{a.name}_glow.png")
    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA").save(out_path)

    lit_px = int((out[..., 3] > 0.02).sum())
    peak = float(out[..., 3].max())
    ys, xs = np.nonzero(out[..., 3] > 0.02)
    bbox = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None

    meta["glow_layer"] = {
        "file": os.path.relpath(out_path, REPO).replace("\\", "/"),
        "body_sprite": f"art/sprites/{a.name}_{a.body}.png",
        "derived_from": [f"{a.name}_{a.lit}_4x.png", f"{a.name}_{a.body}_4x.png"],
        "blend": "additive; dst += rgb * a. Pulse modulate.a for flicker.",
        "lit_px": lit_px,
        "coverage_pct": round(lit_px / (sw * sh) * 100, 2),
        "peak_alpha": round(peak, 3),
        "bbox": bbox,
    }
    json.dump(meta, open(meta_path, "w"), indent=2)

    print(f"GLOW {out_path}  {sw}x{sh}")
    print(f"  lit pixels {lit_px} ({meta['glow_layer']['coverage_pct']}% of sprite), "
          f"peak alpha {peak:.3f}")
    print(f"  bbox {bbox}")
    print(f"  body sprite: art/sprites/{a.name}_{a.body}.png   blend: additive")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
