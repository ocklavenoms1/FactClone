"""Doodads on the real ground colour, at the size a player sees them.

    python art/tools/doodad_sheet.py

The eye sheet for buildings uses neutral mid-grey, because a building is judged
against its neighbours. A doodad is judged against the GROUND it is embedded
in, so grey would flatter it - the whole question is whether it disappears into
#2E3A26 or shouts over it.

Three panels, and the third is the one that decides:
  1x       each doodad at true size on the ground
  4x       the same, magnified, for seeing what the form actually is
  scatter  a field of them at 1x, which is how they are really encountered

The scatter panel exists because the failure mode is a SET failure. One tuft at
1x always looks fine. Forty of them either read as ground texture or as forty
small objects demanding to be identified, and nothing but a field shows which.
"""

import json
import os
import random

import numpy as np
from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPR = os.path.join(REPO, "art", "sprites", "doodads")
GAP, PAD = 14, 16
SCATTER_W, SCATTER_H, SCATTER_N = 220, 96, 46


def ground_rgb(hex_s):
    h = hex_s.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def main():
    man = json.load(open(os.path.join(REPO, "art", "doodads.json")))
    g = ground_rgb(man["ground_hex"])
    names = [d["name"] for d in man["doodads"] if d.get("status") != "calibration"]
    ims = {n: Image.open(os.path.join(SPR, f"{n}.png")).convert("RGBA") for n in names}

    def row(zoom):
        w = sum(ims[n].width * zoom for n in names) + GAP * (len(names) - 1) + PAD * 2
        h = max(ims[n].height * zoom for n in names) + PAD * 2
        c = Image.new("RGBA", (w, h), (*g, 255))
        x = PAD
        for n in names:
            im = ims[n]
            if zoom > 1:
                im = im.resize((im.width * zoom, im.height * zoom), Image.Resampling.NEAREST)
            c.alpha_composite(im, (x, h - PAD - im.height))
            x += im.width + GAP
        return c

    rng = random.Random(7)
    sc = Image.new("RGBA", (SCATTER_W, SCATTER_H), (*g, 255))
    for _ in range(SCATTER_N):
        im = ims[rng.choice(names)]
        sc.alpha_composite(im, (rng.randrange(0, SCATTER_W - im.width),
                                rng.randrange(0, SCATTER_H - im.height)))

    r1, r4 = row(1), row(4)
    W = max(r1.width, r4.width, sc.width + PAD * 2)
    H = r1.height + r4.height + sc.height + PAD
    out = Image.new("RGB", (W, H), g)
    out.paste(r1.convert("RGB"), (0, 0))
    out.paste(r4.convert("RGB"), (0, r1.height))
    out.paste(sc.convert("RGB"), (PAD, r1.height + r4.height + PAD // 2))
    p = os.path.join(REPO, "art", "renders", "doodad_sheet.png")
    out.save(p)
    print(f"DOODAD_SHEET {p}   {names} at 1x, 4x, and scattered")


if __name__ == "__main__":
    main()
