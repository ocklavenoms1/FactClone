"""8-way turnaround: renders one asset at 45-degree yaw steps.

    blender -b art/template.blend -P art/blender/turnaround.py -- \
        --glb "<path>.glb" --name smelter --footprint 2 [--fit height --height-tiles 3]

Tripo's idea of "front" is arbitrary and differs per generation. Look at the
resulting sheet, pick the view whose front face reads best, and put that yaw
into assets.json as yaw_correction. Do not guess it.

If all eight frames come out identical, the rotation is being silently
discarded - see normalize.import_glb() and the QUATERNION note.
"""

import json
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lock       # noqa: E402
import normalize  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
STEPS = [0, 45, 90, 135, 180, 225, 270, 315]


def get_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a, i = {}, 0
    while i < len(argv):
        if argv[i].startswith("--"):
            nxt = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else "1"
            a[argv[i][2:]] = nxt
            i += 2
        else:
            i += 1
    return a


def main():
    a = get_args()
    name = a["name"]
    footprint = float(a.get("footprint", "1"))
    fit = a.get("fit", "footprint")
    height_tiles = float(a["height-tiles"]) if "height-tiles" in a else None

    roots = normalize.import_glb(a["glb"])
    norm = normalize.normalize(roots, footprint, fit=fit, height_tiles=height_tiles)
    normalize.normalize_materials(norm["meshes"], enabled=True)

    out_dir = os.path.join(REPO, "art", "renders", "turnaround")
    os.makedirs(out_dir, exist_ok=True)

    scene = bpy.context.scene
    cam = scene.camera
    root = norm["root"]

    # one shared cell across all eight yaws, so the frames are comparable
    cells = []
    for yaw in STEPS:
        root.rotation_euler = (0.0, 0.0, __import__("math").radians(yaw))
        bpy.context.view_layer.update()
        cells.append(normalize.frame(norm["meshes"], footprint))
    cell_w = max(c["cell_tiles"][0] for c in cells)
    cell_h = max(c["cell_tiles"][1] for c in cells)
    cam_v = max(c["cam_uv"][1] for c in cells)
    rx, ry = lock.render_px(cell_w, cell_h)

    masters = []
    for yaw in STEPS:
        root.rotation_euler = (0.0, 0.0, __import__("math").radians(yaw))
        bpy.context.view_layer.update()
        normalize.place_camera(cam, cell_w, 0.0, cam_v)
        scene.render.resolution_x, scene.render.resolution_y = rx, ry
        master = os.path.join(out_dir, f"{name}_yaw{yaw:03d}_4x.png")
        scene.render.filepath = master
        bpy.ops.render.render(write_still=True)
        masters.append({
            "master": os.path.relpath(master, REPO).replace("\\", "/"),
            "sprite": os.path.relpath(
                os.path.join(out_dir, f"{name}_yaw{yaw:03d}.png"), REPO).replace("\\", "/"),
        })
        print(f"YAW {yaw:03d} {master}")

    meta = {
        "name": f"{name}_turnaround",
        "cell_tiles": [cell_w, cell_h],
        "sprite_px": list(lock.sprite_px(cell_w, cell_h)),
        "render_px": [rx, ry],
        "masters": masters,
        "lock_stamp": lock.lock_stamp(),
    }
    meta_path = os.path.join(out_dir, f"{name}_turnaround.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"TURNAROUND_META {meta_path}")


if __name__ == "__main__":
    main()
