"""Empirically verify anchor_px: render the FOOTPRINT itself and see where it lands.

    blender -b art/template.blend -P art/blender/verify_anchor.py -- --name chest
    python art/tools/measure_anchor.py chest

anchor_px claims to be the pixel offset from the sprite's top-left to the
footprint's bottom-centre. That claim is derived from the same math that frames
the camera, so checking it against the framing math proves nothing - agreement
by shared mistake looks identical to agreement by correctness.

This checks it against the RENDERER instead. It reproduces an asset's exact
framing (same import, same normalize, same frame() union, same camera call),
then hides the asset and renders a flat emissive quad covering exactly the
footprint - y from -fp/2 to +fp/2, x likewise, z = 0. That quad goes through
the same 4x master and the same premultiplied LANCZOS downsample as any sprite.
Where its front edge lands IS where the footprint front edge lands, measured in
final sprite pixels by the whole pipeline acting at once, with no step trusted
on paper.

If the quad's bottom boundary equals anchor_y and its horizontal centre equals
anchor_x, the anchor is right by experiment, not by construction.
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


def main():
    a = get_args()
    name = a["name"]
    with open(os.path.join(REPO, "art", "assets.json")) as f:
        cfg = next(x for x in json.load(f)["assets"] if x["name"] == name)

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

    scene = bpy.context.scene
    cam = scene.camera
    root = norm["root"]
    fp = float(cfg["footprint"])
    base_yaw = float(cfg.get("yaw_correction", 0.0))
    yaws = cfg.get("yaws") or [None]

    # the same union loop as render_asset.py, verbatim in behaviour
    frames = []
    for y in yaws:
        if y is not None:
            root.rotation_euler = (0.0, 0.0, math.radians(base_yaw + float(y)))
            bpy.context.view_layer.update()
        frames.append(normalize.frame(norm["meshes"], fp))
    cell_w = max(f["cell_tiles"][0] for f in frames)
    cell_h = max(f["cell_tiles"][1] for f in frames)
    cam_v = max(f["cam_uv"][1] for f in frames)

    sw, sh = lock.sprite_px(cell_w, cell_h)
    rx, ry = lock.render_px(cell_w, cell_h)
    front_v = lock.GROUND_SQUASH * (-fp / 2.0)
    bottom_v = cam_v - cell_h * lock.GROUND_SQUASH / 2.0
    top_v = bottom_v + cell_h * lock.GROUND_SQUASH
    anchor = [round(sw * 0.5, 2),
              round((top_v - front_v) / (cell_h * lock.GROUND_SQUASH) * sh, 2)]

    # the asset framed the camera; now it leaves the stage
    for ob in norm["meshes"]:
        ob.hide_render = True

    mesh = bpy.data.meshes.new("fp_marker")
    h = fp / 2.0
    mesh.from_pydata([(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)],
                     [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new("fp_marker", mesh)
    scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("fp_emit")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (1, 1, 1, 1)
    em.inputs[1].default_value = 5.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    ob.data.materials.append(mat)

    normalize.place_camera(cam, cell_w, 0.0, cam_v)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry
    out_dir = os.path.join(REPO, "art", "renders", "anchor_marker")
    os.makedirs(out_dir, exist_ok=True)
    scene.render.filepath = os.path.join(out_dir, f"{name}_marker_4x.png")
    bpy.ops.render.render(write_still=True)

    with open(os.path.join(out_dir, f"{name}_marker.json"), "w") as f:
        json.dump({"name": name, "sprite_px": [sw, sh], "anchor_px": anchor,
                   "footprint": fp, "cell_tiles": [cell_w, cell_h]}, f)
    print(f"MARKER {name} cell={cell_w}x{cell_h} sprite={sw}x{sh} anchor={anchor}")


if __name__ == "__main__":
    main()
