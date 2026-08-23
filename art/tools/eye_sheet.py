"""The actual gate: a finished sprite at true in-game size, judged by eye.

    python art/tools/eye_sheet.py --asset power_pole --reference smelter_idle --shadow
    python art/tools/eye_sheet.py --asset power_pole --silhouette
    python art/tools/eye_sheet.py --asset power_pole --shadow-levels 0.25,0.5,0.75,1.0

Every other tool here measures something. This one just shows the sprite at the
size a player sees it, next to an approved asset, on neutral mid-grey, with
NOTHING written on the image - no labels, no numbers, no grid. A metric printed
beside a picture tells you what to think about the picture.

Why this is the gate and the spectral ratio is not: the HF number earned its
keep on the first kiln, where cobbles genuinely turned to mud and it caught
them. Then it rejected a pole that looked good. A gate that fails good work is
worse than no gate, so it went back to being a diagnostic and the eye took over.

THE SILHOUETTE CHECK
`--silhouette` renders the sprite as a solid black mask on white, at true size,
with no interior detail at all. If the outline alone does not say what the
building is, the asset fails however good its interior looks.

This is the cheapest check here and it should have existed on day one. A pole
was approved four times running because every review looked at 4x masters,
where the ironwork reads and the outline does not. Interior detail flatters an
asset at magnification; the silhouette is what survives at 32px in peripheral
vision, which is how a factory game is actually read.

THE SHADOW
The shadow is a separate layer, so its strength is a composite-time decision -
exactly what `modulate.a` does in Godot. `--shadow-levels` renders the same
sprite at several strengths side by side so the level can be chosen by eye
rather than guessed in the renderer.
"""

import argparse
import os

from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BG = (128, 128, 128, 255)
SIL_BG = (255, 255, 255, 255)
GAP = 26
PAD = 26


def body_of(name):
    p = os.path.join(REPO, "art", "sprites", f"{name}.png")
    if not os.path.exists(p):
        raise SystemExit(f"MISSING {p}")
    return Image.open(p).convert("RGBA")


def shadow_of(name):
    base = name.replace("_idle", "")
    sp = os.path.join(REPO, "art", "sprites", f"{base}_shadow.png")
    if not os.path.exists(sp):
        return None
    return Image.open(sp).convert("RGBA")


def load(name, with_shadow=False, strength=1.0):
    body = body_of(name)
    if not with_shadow:
        return body
    shadow = shadow_of(name)
    if shadow is None or shadow.size != body.size:
        return body
    if strength != 1.0:
        a = shadow.getchannel("A").point(lambda v: int(v * strength))
        shadow = shadow.copy()
        shadow.putalpha(a)
    out = Image.new("RGBA", body.size, (0, 0, 0, 0))
    out.alpha_composite(shadow)
    out.alpha_composite(body)
    return out


def silhouette(name):
    """Solid black wherever the sprite is opaque. No interior detail."""
    body = body_of(name)
    out = Image.new("RGBA", body.size, (0, 0, 0, 0))
    alpha = body.getchannel("A").point(lambda v: 255 if v > 127 else 0)
    black = Image.new("RGBA", body.size, (0, 0, 0, 255))
    out.paste(black, (0, 0), alpha)
    return out


def zoom(im, z):
    return im if z == 1 else im.resize((im.width * z, im.height * z),
                                       Image.Resampling.NEAREST)


def compose(panels, bg):
    W = sum(p.width for p in panels) + GAP * (len(panels) - 1) + PAD * 2
    H = max(p.height for p in panels) + PAD * 2
    canvas = Image.new("RGBA", (W, H), bg)
    x = PAD
    for p in panels:
        # common baseline - buildings stand on the ground
        canvas.alpha_composite(p, (x, H - PAD - p.height))
        x += p.width + GAP
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset", required=True)
    ap.add_argument("--reference", default="smelter_idle")
    ap.add_argument("--zooms", default="1,2,4")
    ap.add_argument("--out")
    ap.add_argument("--shadow", action="store_true")
    ap.add_argument("--shadow-strength", type=float, default=1.0)
    ap.add_argument("--shadow-levels",
                    help="comma-separated strengths, rendered side by side at 1x")
    ap.add_argument("--silhouette", action="store_true",
                    help="solid black mask on white - does the outline alone read?")
    a = ap.parse_args()

    if a.shadow_levels:
        levels = [float(v) for v in a.shadow_levels.split(",")]
        panels = [load(a.asset, True, s) for s in levels]
        out = a.out or os.path.join(REPO, "art", "renders", f"shadow_levels_{a.asset}.png")
        compose(panels, BG).convert("RGB").save(out)
        print(f"SHADOW_LEVELS {out}   {a.asset} at 1x, strengths {levels}")
        return

    if a.silhouette:
        panels = [zoom(silhouette(a.asset), 1), zoom(silhouette(a.asset), 2),
                  zoom(silhouette(a.reference), 1)]
        out = a.out or os.path.join(REPO, "art", "renders", f"silhouette_{a.asset}.png")
        compose(panels, SIL_BG).convert("RGB").save(out)
        print(f"SILHOUETTE {out}   {a.asset} at 1x and 2x, {a.reference} at 1x")
        print("  If the outline alone does not say what it is, it fails.")
        return

    zs = [int(z) for z in a.zooms.split(",")]
    asset = load(a.asset, a.shadow, a.shadow_strength)
    ref = load(a.reference, a.shadow, a.shadow_strength)
    panels = [zoom(asset, z) for z in zs] + [ref]
    out = a.out or os.path.join(REPO, "art", "renders", f"eye_{a.asset}.png")
    compose(panels, BG).convert("RGB").save(out)
    print(f"EYE_SHEET {out}   {a.asset} at {zs} + {a.reference} at 1x")
    print(f"  {a.asset} true size: {asset.width}x{asset.height}px")


if __name__ == "__main__":
    main()
