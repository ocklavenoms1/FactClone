"""Camera calibration check. Run after ANY change to the camera or lock.

    blender -b art/template.blend -P art/blender/verify_calibration.py
    python art/tools/downsample.py --check art/renders/_calib.json

Renders an emissive 1x1 ground plane through the locked camera into a 1x1 cell.
After the squash-correcting downsample its opaque bounding box must measure
exactly TILE_PX x TILE_PX. If it comes back non-square, the anamorphic
correction is broken and every sprite footprint will be a squashed rectangle
that does not sit on the game's square grid.
"""

import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lock  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_PNG = os.path.join(REPO, "art", "renders", "_calib_4x.png")
OUT_JSON = os.path.join(REPO, "art", "renders", "_calib.json")


def main():
    scene = bpy.context.scene

    # a perfectly flat 1x1 tile on the ground, pure emission so lighting and
    # shading cannot affect the measured extent
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
    plane = bpy.context.active_object
    mat = bpy.data.materials.new("CalibEmit")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (1, 1, 1, 1)
    emit.inputs["Strength"].default_value = 1.0
    nt.links.new(emit.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
    plane.data.materials.append(mat)

    cam = scene.camera
    cam.data.ortho_scale = 1.0                       # 1 tile wide
    rot = cam.rotation_euler.to_matrix()
    cam.location = rot.col[2] * 30.0                 # centred on the origin

    rx, ry = lock.render_px(1, 1)
    scene.render.resolution_x = rx
    scene.render.resolution_y = ry
    scene.render.filepath = OUT_PNG
    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    bpy.ops.render.render(write_still=True)

    sx, sy = lock.sprite_px(1, 1)
    meta = {
        "master": OUT_PNG,
        "sprite": os.path.join(REPO, "art", "renders", "_calib.png"),
        "render_px": [rx, ry],
        "sprite_px": [sx, sy],
        "expect_bbox": [lock.TILE_PX, lock.TILE_PX],
        "lock_stamp": lock.lock_stamp(),
    }
    with open(OUT_JSON, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"CALIB_RENDERED {rx}x{ry} -> expect {sx}x{sy}, bbox {lock.TILE_PX}x{lock.TILE_PX}")


if __name__ == "__main__":
    main()
