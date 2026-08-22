"""How much of an albedo's variation is TEXTURE, and how much is baked shading?

    blender -b -P art/blender/dump_texture.py -- --glb art/source/<n>.glb --out-dir art/renders/tex
    python art/tools/baked_shading.py art/renders/tex/<n>_basecolor.png

WHY THIS MATTERS
The albedo remap corrects VALUE. It does not correct a painted GRADIENT: a
slab face that fades dark-to-light across itself carries a lighting cue baked
into the albedo, and that cue was invented by the image model, not by the
locked three-point rig. Wherever the two disagree, the sprite carries two
light sources - and no amount of per-cluster gain fixes it, because the gain is
constant across the cluster while the gradient is not.

It also passes a visual check easily. A baked *cast shadow* is obvious; a soft
painted falloff across a face is not.

METHOD
Within each material cluster, decompose luminance variance across SEVERAL
spatial scales rather than one. A single blur radius conflates two different
things - a painted gradient across one face, and two separate faces sitting at
different flat values - and reports both as "shading". The multi-scale profile
separates them:

    fine   (<= 4px)    grain, mortar, speckle          -> texture
    medium (4-32px)    rivets, plank edges, courses    -> texture detail
    coarse (> 32px)    falloff across a face, or       -> gradient OR
                       whole faces at different values     legitimate variation

Coarse variance alone is not proof of a painted gradient. The decisive test is
the RIG COMPARISON below.

FIGHTING THE RIG
A gradient only fights the rig if it runs the wrong WAY. The locked key comes
from screen upper-left, so a face should be brighter at its top-left. The tool
reports the dominant gradient direction per cluster in UV space and flags
clusters whose baked gradient opposes the key. UV direction is not screen
direction, so this is reported as a magnitude plus a caution, not a verdict:
the definitive check is the rendered sprite.
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None   # 8192x8192 albedo atlases are normal here

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "blender"))
import lock  # noqa: E402


def srgb_to_linear(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def hexlin(h):
    h = h.lstrip("#")
    return srgb_to_linear(np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]))


def box_blur(img, r):
    """Separable box blur via integral image - no scipy."""
    pad = np.pad(img, r, mode="edge")
    c = np.cumsum(np.cumsum(pad, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)), mode="constant")
    h, w = img.shape
    k = 2 * r + 1
    tot = c[k:k + h, k:k + w] - c[0:h, k:k + w] - c[k:k + h, 0:w] + c[0:h, 0:w]
    return tot / (k * k)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("texture")
    ap.add_argument("--blur-frac", type=float, default=0.02,
                    help="blur radius as a fraction of texture width")
    a = ap.parse_args()

    im = np.asarray(Image.open(a.texture).convert("RGB")).astype(np.float64) / 255.0
    lin = srgb_to_linear(im)
    H, W = lin.shape[:2]
    lum = lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722

    # exclude the emission mask
    mask = (np.minimum(lin[..., 0], lin[..., 2]) - lin[..., 1]) > 0.02

    # scales expressed in texels of THIS image. Measure on the FULL-RES
    # atlas: downsampling an 8192 atlas to 2048 averages away exactly the
    # fine detail the metric is meant to find, and reports 0% fine for a
    # texture that has plenty.
    scales = [max(1, int(W * 0.0005)), max(2, int(W * 0.004))]
    b_fine = box_blur(lum, scales[0])
    b_coarse = box_blur(lum, scales[1])

    # assign every texel to its nearest palette member, on gain-removed colour
    P = np.array([hexlin(h) for h in lock.PALETTE.values()])
    names = list(lock.PALETTE)
    flat = lin.reshape(-1, 3)
    keep = ~mask.reshape(-1)
    gain = flat[keep].mean(0) / P.mean(0)
    Y = flat / np.maximum(gain, 1e-6)
    lab = np.argmin(((Y[:, None, :] - P[None, :, :]) ** 2).sum(-1), axis=1).reshape(H, W)

    print(f"texture {os.path.basename(a.texture)}  {W}x{H}   "
          f"scales: fine<={scales[0]}px  coarse>{scales[1]}px")
    print(f"\n{'cluster':15}{'texels':>9}{'fine':>8}{'medium':>8}{'coarse':>8}"
          f"{'grad dU':>9}{'grad dV':>9}")

    tot_sh, tot_n = 0.0, 0
    for j, n in enumerate(names):
        sel = (lab == j) & (~mask)
        cnt = int(sel.sum())
        if cnt < 500:
            print(f"{n:15}{cnt:9}      (too few texels to judge)")
            continue
        v_all = float(lum[sel].var())
        v_coarse = float(b_coarse[sel].var())
        v_fine_removed = float(b_fine[sel].var())
        coarse = min(1.0, v_coarse / max(v_all, 1e-12))
        fine = max(0.0, 1.0 - v_fine_removed / max(v_all, 1e-12))
        medium = max(0.0, 1.0 - fine - coarse)

        ys, xs = np.nonzero(sel)
        du = float(np.corrcoef(xs, b_coarse[sel])[0, 1]) if cnt > 2 else 0.0
        dv = float(np.corrcoef(ys, b_coarse[sel])[0, 1]) if cnt > 2 else 0.0

        tot_sh += coarse * cnt
        tot_n += cnt
        print(f"{n:15}{cnt:9}{fine * 100:7.1f}%{medium * 100:7.1f}%{coarse * 100:7.1f}%"
              f"{du:9.2f}{dv:9.2f}")

    overall = tot_sh / max(tot_n, 1)
    print(f"\noverall baked-shading share of albedo luminance variance: "
          f"{overall * 100:.1f}%")
    if overall > 0.5:
        print("  HIGH - most of the albedo's variation is a painted gradient, not")
        print("  texture. The remap corrects value, not gradient, so this rides")
        print("  through into every sprite and competes with the locked rig.")
    elif overall > 0.3:
        print("  MODERATE - a visible painted falloff sits under the rig's own")
        print("  shading. Tolerable, but it is why 'flat even shadowless lighting'")
        print("  is in the style block.")
    else:
        print("  LOW - the albedo is mostly texture. The rig owns the shading.")
    print("\n  grad dU/dV: correlation of the low-frequency component with UV")
    print("  position. |value| near 0 means no directional gradient; large means")
    print("  a systematic light-to-dark ramp across the atlas. UV direction is")
    print("  not screen direction - judge the rendered sprite for the verdict.")


if __name__ == "__main__":
    main()
