"""Doodads on the real ground, and then a field of them placed the intended way.

    python art/tools/doodad_sheet.py

The eye sheet for buildings uses neutral grey, because a building is judged
against its neighbours. A doodad is judged against the GROUND it is embedded
in, so grey would flatter it - the question is whether it settles into #2E3A26
or sits on top of it.

TWO PANELS, AND THE SECOND IS THE ONE THAT DECIDES

  strip   each doodad once, at true size, on the ground
  field   a large area placed the way the game is told to place them

The field exists because the failure mode is a SET failure, and the first
doodad set failed exactly there: four individually reasonable objects scattered
one per eight tiles read as confetti on a vacant lot. Ground reads as ground
because vegetation comes in PATCHES with clear ground between them - density
VARIANCE, not density - so the field is generated from a low-frequency mask
exactly as `_placement` in the manifest instructs, with patches only where the
mask is high and bare ground elsewhere.

If the field reads as a lawn with worn patches, the set works. If it reads as
scattered objects, no amount of per-sprite tuning will save it.
"""

import json
import math
import os
import random

from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPR = os.path.join(REPO, "art", "sprites", "doodads")
PAD, GAP = 16, 14
FIELD_W, FIELD_H = 420, 240
TILE = 32


def ground_rgb(hex_s):
    h = hex_s.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mask_at(x, y, seed):
    """Smooth low-frequency mask - the same idea the game side is asked to use."""
    v = 0.0
    for i, (period, amp) in enumerate(((190.0, 1.0), (95.0, 0.5))):
        a = math.sin((x / period) * 2 * math.pi + seed * 1.7 + i)
        b = math.cos((y / (period * 0.8)) * 2 * math.pi + seed * 2.3 - i)
        v += amp * a * b
    return (v / 1.5 + 1.0) * 0.5


def main():
    man = json.load(open(os.path.join(REPO, "art", "doodads.json")))
    g = ground_rgb(man["ground_hex"])
    entries = [d for d in man["doodads"] if d.get("status") != "calibration"]
    ims = {d["name"]: Image.open(os.path.join(SPR, f"{d['name']}.png")).convert("RGBA")
           for d in entries}
    names = [d["name"] for d in entries]

    w = sum(ims[n].width for n in names) + GAP * (len(names) - 1) + PAD * 2
    h = max(ims[n].height for n in names) + PAD * 2
    strip = Image.new("RGBA", (w, h), (*g, 255))
    x = PAD
    for n in names:
        strip.alpha_composite(ims[n], (x, h - PAD - ims[n].height))
        x += ims[n].width + GAP

    rng = random.Random(11)
    field = Image.new("RGBA", (FIELD_W, FIELD_H), (*g, 255))
    big = [d for d in entries if d["kind"] == "patch" and max(d.get("size_tiles", [1]))>= 2]
    edge = [d for d in entries if d["kind"] == "patch" and d not in big]
    mineral = [d for d in entries if d["kind"] != "patch"]
    # patches where the mask is high; edge pieces around them; minerals anywhere
    for d, lo, tries in ((big, 0.62, 90), (edge, 0.45, 220)):
        for _ in range(tries):
            if not d:
                continue
            e = d[rng.randrange(len(d))]
            im = ims[e["name"]]
            px = rng.randrange(0, max(1, FIELD_W - im.width))
            py = rng.randrange(0, max(1, FIELD_H - im.height))
            if mask_at(px + im.width / 2, py + im.height / 2, 3) < lo:
                continue
            field.alpha_composite(im, (px, py))
    for _ in range(int(FIELD_W * FIELD_H / (TILE * TILE) / 40)):
        e = mineral[rng.randrange(len(mineral))] if mineral else None
        if not e:
            break
        im = ims[e["name"]]
        field.alpha_composite(im, (rng.randrange(0, FIELD_W - im.width),
                                   rng.randrange(0, FIELD_H - im.height)))

    W = max(strip.width, field.width + PAD * 2)
    H = strip.height + field.height + PAD
    out = Image.new("RGB", (W, H), g)
    out.paste(strip.convert("RGB"), (0, 0))
    out.paste(field.convert("RGB"), (PAD, strip.height + PAD // 2))
    p = os.path.join(REPO, "art", "renders", "doodad_sheet.png")
    out.save(p)
    print(f"DOODAD_SHEET {p}   strip at 1x, then a mask-placed field")


if __name__ == "__main__":
    main()
