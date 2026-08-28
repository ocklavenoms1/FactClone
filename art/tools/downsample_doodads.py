"""Downsample doodad masters and crop to tight alpha bounds.

    python art/tools/downsample_doodads.py [name ...]

Same premultiplied LANCZOS as downsample.py - straight alpha bleeds the
transparent background's black into every edge, and a 6px tuft of grass is
almost entirely edge, so on these it is not a subtlety.

Then it crops. Buildings are framed to whole tiles because they must land on
the grid; a doodad is scattered at an arbitrary point, so every transparent
row it carries is wasted texture and a wasted blit. Cropping moves the anchor,
which is tracked here rather than recomputed - the render knew where the
ground point was, and arithmetic on a known offset cannot disagree with it.
"""

import json
import os
import sys

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(REPO, "art", "renders", "doodads")
DST = os.path.join(REPO, "art", "sprites", "doodads")


def premultiplied_resize(im, size):
    a = np.asarray(im.convert("RGBA")).astype(np.float64) / 255.0
    pm = np.dstack([a[..., :3] * a[..., 3:4], a[..., 3:4]])
    small = np.asarray(Image.fromarray(
        (np.clip(pm, 0, 1) * 255).round().astype(np.uint8), "RGBA")
        .resize(size, Image.Resampling.LANCZOS)).astype(np.float64) / 255.0
    al = small[..., 3:4]
    rgb = np.divide(small[..., :3], np.maximum(al, 1e-6))
    out = np.dstack([np.clip(rgb, 0, 1), np.clip(al, 0, 1)])
    return Image.fromarray((out * 255).round().astype(np.uint8), "RGBA")


def main():
    os.makedirs(DST, exist_ok=True)
    want = sys.argv[1:]
    metas = sorted(f for f in os.listdir(SRC) if f.endswith(".json"))
    for mf in metas:
        meta = json.load(open(os.path.join(SRC, mf)))
        if want and meta["name"] not in want:
            continue
        sw, sh = meta["sprite_px"]
        im = premultiplied_resize(Image.open(os.path.join(SRC, f"{meta['name']}_4x.png")),
                                  (sw, sh))
        arr = np.asarray(im)
        ys, xs = np.nonzero(arr[..., 3] > 0)
        if len(xs) == 0:
            print(f"  EMPTY {meta['name']} - nothing rendered")
            continue
        x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
        im = im.crop((x0, y0, x1 + 1, y1 + 1))
        ax, ay = meta["anchor_px"]
        meta["anchor_px"] = [round(ax - x0, 2), round(ay - y0, 2)]
        meta["sprite_px"] = [im.width, im.height]
        meta["crop_offset_px"] = [x0, y0]
        out = os.path.join(DST, f"{meta['name']}.png")
        im.save(out)
        with open(os.path.join(DST, f"{meta['name']}.json"), "w") as f:
            json.dump(meta, f, indent=2)
        print(f"  DOODAD {meta['name']:16} {sw}x{sh} -> {im.width}x{im.height}  "
              f"anchor {meta['anchor_px']}")


if __name__ == "__main__":
    main()
