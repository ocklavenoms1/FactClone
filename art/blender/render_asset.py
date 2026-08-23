"""Render one asset from assets.json through the locked template.

    blender -b art/template.blend -P art/blender/render_asset.py -- --name smelter
    python art/tools/downsample.py art/sprites/smelter.json

Writes the 4x master(s) to art/renders/ and a metadata JSON to art/sprites/.
The downsample step is deliberately separate: it needs Pillow's LANCZOS and
premultiplied alpha, which Blender's bundled Python cannot do well.

For a 4-way asset the cell is unioned across all four yaws, so Godot carries
ONE anchor per building rather than four.
"""

import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lock       # noqa: E402
import normalize  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))


def get_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a, i = {}, 0
    while i < len(argv):
        if argv[i].startswith("--"):
            a[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else "1"
            i += 2
        else:
            i += 1
    return a


def load_asset(name):
    with open(os.path.join(REPO, "art", "assets.json")) as f:
        man = json.load(f)
    for a in man["assets"]:
        if a["name"] == name:
            return a
    raise SystemExit(f"asset {name!r} not in assets.json")


def apply_state(name, hook, ctx):
    if not hook:
        return None
    path = os.path.join(HERE, "states", hook)
    if not os.path.exists(path):
        print(f"WARN missing state hook {path}")
        return None
    g = {"bpy": bpy, "lock": lock, "__file__": path}
    g.update(ctx)
    exec(compile(open(path).read(), path, "exec"), g)  # noqa: S102
    return hook


def main():
    a = get_args()
    name = a["name"]
    cfg = load_asset(name)
    no_matnorm = "no-material-norm" in a
    suffix_extra = a.get("out-suffix", "")

    glb = os.path.join(REPO, "art", "source", a.get("source", cfg.get("source", f"{name}.glb")))
    if not os.path.exists(glb):
        raise SystemExit(f"MISSING_SOURCE {glb}")

    roots = normalize.import_glb(glb)
    norm = normalize.normalize(
        roots,
        footprint=float(cfg["footprint"]),
        fit=cfg.get("fit", "footprint"),
        height_tiles=float(a["height-tiles"]) if "height-tiles" in a else cfg.get("height_tiles"),
        yaw_correction_deg=float(cfg.get("yaw_correction", 0.0)),
        footprint_fill=cfg.get("footprint_fill"),
    )
    mat_report = normalize.normalize_materials(
        norm["meshes"], enabled=not no_matnorm, hsv=cfg.get("hsv"))
    # Value/exposure correction. Measured per asset by art/tools/palette_drift.py
    # and stored in the manifest, because Tripo's palette shift is not consistent
    # between generations and so cannot be fixed by prompting.
    # ORDER MATTERS. The emission mask must be detected from the RAW texture,
    # before any albedo correction rewires Base Color - otherwise the chroma
    # score is measured on corrected colour, no longer clears the cut, and the
    # firebox silently never lights. neutralize_mask() taps the raw texture and
    # inserts its mix; the albedo correction then stacks on top of that.
    mask_sockets = normalize.neutralize_mask(norm["meshes"])

    # mode: "gain" (single per-channel), "remap" (per-cluster), or "none".
    # Overridable with --albedo-mode so the two can be rendered side by side.
    albedo_report = None
    mode = a.get("albedo-mode", cfg.get("albedo_correction", "gain"))
    if no_matnorm:
        mode = "none"
    if cfg.get("albedo_pinned"):
        print("ALBEDO pinned: using the approved remap, not re-measuring")
    if mode == "remap" and cfg.get("albedo_remap"):
        albedo_report = normalize.apply_albedo_remap(norm["meshes"], cfg["albedo_remap"])
        albedo_report["mode"] = "remap"
        print(f"ALBEDO remap: {len(albedo_report['anchors'])} anchors "
              f"{albedo_report['anchors']} sigma={albedo_report['sigma']} "
              f"dropped={albedo_report['dropped']}")
    elif mode == "gain" and cfg.get("albedo_gain"):
        albedo_report = normalize.apply_albedo_gain(norm["meshes"], cfg["albedo_gain"])
        albedo_report["mode"] = "gain"
        print(f"ALBEDO gain^-1 applied to {albedo_report['materials']} material(s): "
              f"{[round(v, 3) for v in albedo_report['inverse']]}")

    scene = bpy.context.scene
    cam = scene.camera
    root = norm["root"]
    footprint = float(cfg["footprint"])
    base_yaw = float(cfg.get("yaw_correction", 0.0))
    yaws = cfg.get("yaws") or [None]

    # union the cell across every facing so one anchor serves all of them
    frames = []
    for y in yaws:
        if y is not None:
            root.rotation_euler = (0.0, 0.0, math.radians(base_yaw + float(y)))
            bpy.context.view_layer.update()
        frames.append(normalize.frame(norm["meshes"], footprint))
    cell_w = max(f["cell_tiles"][0] for f in frames)
    cell_h = max(f["cell_tiles"][1] for f in frames)
    cam_v = max(f["cam_uv"][1] for f in frames)
    overhangs = any(f["overhangs_front"] for f in frames)

    sw, sh = lock.sprite_px(cell_w, cell_h)
    rx, ry = lock.render_px(cell_w, cell_h)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry

    # recompute the anchor against the unioned cell
    front_v = lock.GROUND_SQUASH * (-footprint / 2.0)
    bottom_v = cam_v - cell_h * lock.GROUND_SQUASH / 2.0
    top_v = bottom_v + cell_h * lock.GROUND_SQUASH
    anchor = [round(sw * 0.5, 2),
              round((top_v - front_v) / (cell_h * lock.GROUND_SQUASH) * sh, 2)]

    states = cfg.get("states") or {"": None}
    renders_dir = os.path.join(REPO, "art", "renders")
    sprites_dir = os.path.join(REPO, "art", "sprites")
    os.makedirs(renders_dir, exist_ok=True)
    os.makedirs(sprites_dir, exist_ok=True)

    masters = []
    for state, hook in states.items():
        # state hooks mutate materials; reload-free approach is fine because
        # each hook is written to be idempotent on a fresh import
        applied = apply_state(state, hook, {
            "meshes": norm["meshes"],
            "root": root,
            "cfg": cfg,
            "glow_at": cfg.get("glow_at"),
            "mask_sockets": mask_sockets,
        })
        for y in yaws:
            if y is not None:
                root.rotation_euler = (0.0, 0.0, math.radians(base_yaw + float(y)))
                bpy.context.view_layer.update()
            normalize.place_camera(cam, cell_w, 0.0, cam_v)

            tag = name
            if state:
                tag += f"_{state}"
            if y is not None:
                tag += f"_d{int(y)}"
            tag += suffix_extra

            master = os.path.join(renders_dir, f"{tag}_4x.png")
            scene.render.filepath = master
            bpy.ops.render.render(write_still=True)
            masters.append({
                "tag": tag,
                "state": state or None,
                "yaw": y,
                "master": os.path.relpath(master, REPO).replace("\\", "/"),
                "sprite": os.path.relpath(os.path.join(sprites_dir, f"{tag}.png"),
                                          REPO).replace("\\", "/"),
                "state_hook": applied,
            })
            print(f"RENDERED {tag} {rx}x{ry}")

    meta = {
        "name": name + suffix_extra,
        "source": os.path.basename(glb),
        "footprint_tiles": footprint,
        "fit": cfg.get("fit", "footprint"),
        "height_tiles": cfg.get("height_tiles"),
        "yaw_correction": base_yaw,
        "cell_tiles": [cell_w, cell_h],
        "sprite_px": [sw, sh],
        "render_px": [rx, ry],
        # pixel offset from sprite top-left to the footprint's bottom-centre.
        # Godot draws the sprite at (footprint_bottom_centre - anchor_px).
        "anchor_px": anchor,
        "overhangs_front_edge": overhangs,
        "normalized_scale": round(norm["scale"], 6),
        "normalized_extent_tiles": [round(v, 4) for v in norm["size_tiles"]],
        "material_norm": not no_matnorm,
        "material_report": mat_report,
        "albedo_gain_applied": albedo_report,
        "masters": masters,
        "lock_stamp": lock.lock_stamp(),
    }
    meta_path = os.path.join(sprites_dir, f"{name}{suffix_extra}.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"META {meta_path} cell={cell_w}x{cell_h} sprite={sw}x{sh} anchor={anchor}")


if __name__ == "__main__":
    main()
