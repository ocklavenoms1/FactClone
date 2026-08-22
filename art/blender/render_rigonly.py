"""Render an asset with a FLAT grey albedo - the locked rig's shading, alone.

    blender -b art/template.blend -P art/blender/render_rigonly.py -- --name smelter

Every base colour is replaced by a constant mid grey, so the only luminance
variation left in the render is what the three-point rig and the geometry
produce. Comparing this against the real render separates "shading the rig
made" from "shading the albedo already had painted into it".

That comparison is the decisive test for baked shading. A variance
decomposition of the albedo cannot answer it: within a material, the variance
is dominated by different faces sitting at different values, which swamps any
within-face gradient.
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
GREY = 0.18


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


def main():
    a = get_args()
    name = a["name"]
    man = json.load(open(os.path.join(REPO, "art", "assets.json")))
    cfg = next(x for x in man["assets"] if x["name"] == name)

    glb = os.path.join(REPO, "art", "source", cfg.get("source", f"{name}.glb"))
    roots = normalize.import_glb(glb)
    norm = normalize.normalize(
        roots,
        footprint=float(cfg["footprint"]),
        fit=cfg.get("fit", "footprint"),
        height_tiles=cfg.get("height_tiles"),
        yaw_correction_deg=float(cfg.get("yaw_correction", 0.0)),
        footprint_fill=cfg.get("footprint_fill"),
    )

    # flatten every albedo to a constant; leave roughness/metallic alone so the
    # surface response is the asset's own
    seen = set()
    for ob in norm["meshes"]:
        for slot in ob.material_slots:
            m = slot.material
            if not m or m.name in seen or not m.use_nodes:
                continue
            seen.add(m.name)
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            base = bsdf.inputs.get("Base Color")
            if base is None:
                continue
            for link in list(base.links):
                m.node_tree.links.remove(link)
            base.default_value = (GREY, GREY, GREY, 1.0)
            e = bsdf.inputs.get("Emission Strength")
            if e is not None and not e.is_linked:
                e.default_value = 0.0

    footprint = float(cfg["footprint"])
    frame = normalize.frame(norm["meshes"], footprint)
    cell_w, cell_h = frame["cell_tiles"]
    scene = bpy.context.scene
    normalize.place_camera(scene.camera, cell_w, 0.0, frame["cam_uv"][1])
    rx, ry = lock.render_px(cell_w, cell_h)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry

    out = os.path.join(REPO, "art", "renders", f"{name}_rigonly_4x.png")
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print(f"RIGONLY {out} {rx}x{ry} cell={cell_w}x{cell_h}")


if __name__ == "__main__":
    main()
