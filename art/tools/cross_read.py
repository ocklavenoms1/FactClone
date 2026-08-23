"""Does this silhouette read as a Latin cross? Measured, side by side.

    python art/tools/cross_read.py power_pole_h26 power_pole_h21 power_pole_h18

A pole was rejected on silhouette after four approvals, because every review
looked at 4x masters. The fix attempt was to move the crossarm DOWN with the
mast rising above it - which is precisely the crucifix proportion, and made it
worse. These are the four numbers that separate "a T with equipment on it" from
"a cross":

  mast_above    fraction of total height standing above the crossarm's top.
                A T is ~0. Anything over ~0.15 starts reading as a cross.
  asymmetry     |left mass - right mass| / total. A cross is symmetric; a pole
                with a transformer bolted to one side is not.
  thin_spine    fraction of columns shorter than 35% of the tallest. High means
                most of the outline is empty air around a bare post.
  com_low       lower-half centre of mass, offset from centre as a fraction of
                width. Equipment low on one side pulls this off zero.

The crossarm row is found as the widest run of the silhouette, which is what an
eye locks onto too.

These numbers are a DIAGNOSTIC. The gate is still eye_sheet.py --silhouette,
judged by eye at 1x. This tool exists to say WHY an outline fails, and to make
an A/B comparison arguable rather than impressionistic.
"""

import os
import sys

from PIL import Image, ImageDraw

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BG = (255, 255, 255, 255)
INK = (0, 0, 0, 255)
GAP = 30
PAD = 24
CAPTION_H = 96
THIN = 0.35


def mask_of(name):
    p = os.path.join(REPO, "art", "sprites", f"{name}.png")
    if not os.path.exists(p):
        raise SystemExit(f"MISSING {p}")
    im = Image.open(p).convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v > 127 else 0)
    return im, a


def metrics(alpha):
    px = alpha.load()
    W, H = alpha.size
    cols = [[y for y in range(H) if px[x, y]] for x in range(W)]
    occupied = [x for x in range(W) if cols[x]]
    if not occupied:
        return None
    x0, x1 = occupied[0], occupied[-1]
    rows = [[x for x in range(W) if px[x, y]] for y in range(H)]
    used_rows = [y for y in range(H) if rows[y]]
    y0, y1 = used_rows[0], used_rows[-1]
    bw, bh = x1 - x0 + 1, y1 - y0 + 1

    # the crossarm is the widest row; take the topmost if several tie
    widths = [(len(rows[y]), -y, y) for y in used_rows]
    arm_w, _, arm_y = max(widths)
    # top of the crossarm: walk up while the row stays near the arm's width
    arm_top = arm_y
    while arm_top - 1 >= y0 and len(rows[arm_top - 1]) >= arm_w * 0.6:
        arm_top -= 1
    mast_above = (arm_top - y0) / bh

    total = sum(len(c) for c in cols)
    mid = (x0 + x1 + 1) / 2.0
    left = sum(len(cols[x]) for x in range(x0, x1 + 1) if x + 0.5 < mid)
    right = total - left
    asymmetry = abs(left - right) / total

    tallest = max(len(c) for c in cols)
    thin = sum(1 for x in range(x0, x1 + 1) if len(cols[x]) < tallest * THIN) / bw

    ymid = (y0 + y1 + 1) / 2.0
    low = [(x, y) for x in range(x0, x1 + 1) for y in cols[x] if y >= ymid]
    com_low = abs(sum(x + 0.5 for x, _ in low) / len(low) - mid) / bw if low else 0.0

    return {"bbox": (bw, bh), "arm_w": arm_w, "arm_top": arm_top - y0,
            "mast_above": mast_above, "asymmetry": asymmetry,
            "thin_spine": thin, "com_low": com_low}


def silhouette(alpha):
    out = Image.new("RGBA", alpha.size, (0, 0, 0, 0))
    out.paste(Image.new("RGBA", alpha.size, INK), (0, 0), alpha)
    return out


def main():
    names = sys.argv[1:]
    if not names:
        raise SystemExit(__doc__)
    panels, caps = [], []
    for n in names:
        _, a = mask_of(n)
        m = metrics(a)
        panels.append(silhouette(a))
        caps.append((n, m))
        print(f"{n}: bbox={m['bbox'][0]}x{m['bbox'][1]} arm_w={m['arm_w']} "
              f"mast_above={m['mast_above']:.3f} asym={m['asymmetry']:.3f} "
              f"thin={m['thin_spine']:.3f} com_low={m['com_low']:.3f}")

    colw = max(max(p.width for p in panels), 190)
    W = len(panels) * colw + GAP * (len(panels) - 1) + PAD * 2
    H = max(p.height for p in panels) + PAD * 2 + CAPTION_H
    canvas = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(canvas)
    base = H - PAD - CAPTION_H
    x = PAD
    for p, (n, m) in zip(panels, caps):
        canvas.alpha_composite(p, (x + (colw - p.width) // 2, base - p.height))
        lines = [n.replace("power_pole_h", "height_tiles ").replace("26", "2.6")
                 .replace("21", "2.1").replace("18", "1.8"),
                 f"{m['bbox'][0]}x{m['bbox'][1]}px  arm {m['arm_w']}px",
                 f"mast above  {m['mast_above'] * 100:.0f}%",
                 f"asymmetry   {m['asymmetry'] * 100:.0f}%",
                 f"thin spine  {m['thin_spine'] * 100:.0f}%",
                 f"CoM low     {m['com_low'] * 100:.1f}%"]
        for i, t in enumerate(lines):
            d.text((x, base + 10 + i * 14), t, fill=(0, 0, 0))
        x += colw + GAP
    out = os.path.join(REPO, "art", "renders", "cross_read.png")
    canvas.convert("RGB").save(out)
    print(f"CROSS_READ {out}")


if __name__ == "__main__":
    main()
