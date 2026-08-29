"""DIAGNOSTIC: does a doodad accidentally read as a tool? Numbers, then the eye.

    python art/tools/tool_silhouette.py

Three times this project has shipped an accidental cross or tool. The pole was
rejected twice as a crucifix, and the retired fallen_twig read as a HAMMER - a
long bar with a shorter bar meeting it near perpendicular. The eye names tools
before it names debris, and in a factory game that is actively harmful, because
the player is scanning for equipment.

WHAT IT MEASURES

The shape is reduced to its own principal axis and profiled along it: for each
band across the length, how far does the silhouette reach perpendicular?

  a stick        flat profile, low limb ratio
  a hammer / T   one narrow band far wider than the rest
  a clump        wide somewhere and wide everywhere, so `localised` stays high

Measured on the 4x MASTER, unsquashed, not on the final sprite. At 5-15px a
sprite has too few pixels to profile - the first version of this ran on the
sprite and inverted completely, passing the hammer at limb 1.00x while failing
a legitimate grass clump at 7.25x. That was quantisation, not shape.

WHY THIS IS NOT A GATE, AND SHOULD NOT BECOME ONE YET

At 4x the measurement does separate the known cases - the retired twig scores
limb 3.20x, the grass patch 2.13x - but that is a threshold drawn between two
samples, and one of them is legitimate art sitting close to the line. Setting a
constant there would be the tuned-constant mistake this project keeps writing
warnings about, and section 22 already paid for the lesson that a gate which
fails good work is worse than no gate.

So it prints numbers and writes a silhouette sheet, and the eye decides. When
enough bad cases accumulate to place a threshold honestly, it can be promoted.
"""

import json
import os

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MASTERS = os.path.join(REPO, "art", "renders", "doodads")
SPRITES = os.path.join(REPO, "art", "sprites", "doodads")
GROUND_SQUASH = 0.86603
BANDS = 11
MIN_PX = 40
SIL_BG = (255, 255, 255)


def profile(path):
    im = Image.open(path).convert("RGBA")
    im = im.resize((im.width, max(1, int(round(im.height / GROUND_SQUASH)))),
                   Image.Resampling.LANCZOS)
    a = np.asarray(im)[..., 3] > 127
    ys, xs = np.nonzero(a)
    if len(xs) < MIN_PX:
        return None
    pts = np.stack([xs.astype(float), ys.astype(float)], 1)
    pts -= pts.mean(0)
    w, v = np.linalg.eigh(np.cov(pts.T))
    axis = v[:, int(np.argmax(w))]
    t = pts @ axis
    n = pts @ np.array([-axis[1], axis[0]])
    span = float(t.max() - t.min())
    if span <= 1e-6:
        return None
    edges = np.linspace(t.min(), t.max(), BANDS + 1)
    widths = np.array([float(n[m].max() - n[m].min()) if (m := (t >= edges[i]) & (t <= edges[i + 1])).sum() >= 2
                       else 0.0 for i in range(BANDS)])
    occ = widths[widths > 0]
    if len(occ) < 3:
        return None
    med = float(np.median(occ))
    peak = float(widths.max())
    return {"aspect": span / max(med, 1e-6),
            "limb": peak / max(med, 1e-6),
            "local": float((widths >= 0.75 * peak).sum()) / BANDS}


def main():
    man = json.load(open(os.path.join(REPO, "art", "doodads.json")))
    names = [d["name"] for d in man["doodads"] if d.get("status") != "calibration"]
    print("  advisory only - the sheet is the check. limb is the tell:")
    print("  (retired fallen_twig, which read as a hammer, scored limb 3.20x)")
    panels = []
    for n in names:
        m = os.path.join(MASTERS, f"{n}_4x.png")
        if os.path.exists(m):
            p = profile(m)
            if p:
                print(f"  {n:22} aspect {p['aspect']:5.2f}  limb {p['limb']:5.2f}x  "
                      f"localised {p['local']:4.2f}")
            else:
                print(f"  {n:22} too few pixels to profile")
        s = os.path.join(SPRITES, f"{n}.png")
        if os.path.exists(s):
            im = Image.open(s).convert("RGBA")
            a = im.getchannel("A").point(lambda v: 255 if v > 127 else 0)
            blk = Image.new("RGBA", im.size, (0, 0, 0, 255))
            sil = Image.new("RGBA", im.size, (0, 0, 0, 0))
            sil.paste(blk, (0, 0), a)
            panels.append(sil)

    if panels:
        z = 3
        pad, gap = 16, 14
        big = [p.resize((p.width * z, p.height * z), Image.Resampling.NEAREST) for p in panels]
        row = panels + big
        W = sum(p.width for p in row) + gap * (len(row) - 1) + pad * 2
        H = max(p.height for p in row) + pad * 2
        c = Image.new("RGB", (W, H), SIL_BG)
        x = pad
        for p in row:
            c.paste(p.convert("RGB"), (x, H - pad - p.height), p)
            x += p.width + gap
        out = os.path.join(REPO, "art", "renders", "doodad_silhouettes.png")
        c.save(out)
        print(f"\n  SHEET {out}   1x then 3x, black on white")
        print("  If any outline names a tool before it names vegetation, it fails.")


if __name__ == "__main__":
    main()
