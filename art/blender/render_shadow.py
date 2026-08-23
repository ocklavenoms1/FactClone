"""Render a contact shadow as its own transparent layer.

    blender -b art/template.blend -P art/blender/render_shadow.py -- --name power_pole
    python art/tools/downsample.py art/sprites/<name>_shadow.json

There is no shadow in the pipeline at all today - the template holds a camera,
three suns and a hidden reference cube, and nothing else. What reads as a hard
grey slab under each asset is the asset's OWN modelled base plate, fully opaque
in the sprite alpha. So assets sit on nothing and look pasted onto the ground.

This adds the missing piece the same way the fire glow was added: as a separate
layer, not baked into the body sprite. Godot draws shadow, then body. Keeping it
separate means the shadow can be tinted per biome, faded, or switched off
without re-rendering anything.

HOW IT WORKS
A ground plane at z=0 is marked `is_shadow_catcher`. In Cycles a shadow catcher
contributes only the shadow that falls ON it - never its own surface - so with
`film_transparent` the render comes back empty except where the asset occludes
the lights. The asset itself is hidden from camera rays (`visible_camera =
False`) while still casting, so the pass contains the shadow and nothing else.

The result is soft because the key light carries an 8-degree angular size, which
is already in the lock. Nothing about the rig changes.
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

    # the asset casts but is not itself photographed
    for ob in norm["meshes"]:
        ob.visible_camera = False
        ob.visible_shadow = True

    bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "ShadowCatcher"
    ground.is_shadow_catcher = True

    # frame exactly as the body sprite does, so the layers land pixel-aligned
    footprint = float(cfg["footprint"])
    frame = normalize.frame(norm["meshes"], footprint)
    cell_w, cell_h = frame["cell_tiles"]
    scene = bpy.context.scene
    normalize.place_camera(scene.camera, cell_w, 0.0, frame["cam_uv"][1])
    rx, ry = lock.render_px(cell_w, cell_h)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry
    scene.render.film_transparent = True

    renders = os.path.join(REPO, "art", "renders")
    sprites = os.path.join(REPO, "art", "sprites")
    master = os.path.join(renders, f"{name}_shadow_4x.png")
    scene.render.filepath = master
    bpy.ops.render.render(write_still=True)

    sw, sh = lock.sprite_px(cell_w, cell_h)
    meta = {
        "name": f"{name}_shadow",
        "cell_tiles": [cell_w, cell_h],
        "sprite_px": [sw, sh],
        "render_px": [rx, ry],
        "anchor_px": frame["anchor_px"],
        "masters": [{
            "tag": f"{name}_shadow", "state": None, "yaw": None,
            "master": os.path.relpath(master, REPO).replace("\\", "/"),
            "sprite": os.path.relpath(os.path.join(sprites, f"{name}_shadow.png"),
                                      REPO).replace("\\", "/"),
        }],
        "lock_stamp": lock.lock_stamp(),
        "blend": "draw UNDER the body sprite, same anchor; alpha is shadow density",
    }
    with open(os.path.join(sprites, f"{name}_shadow.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print(f"SHADOW {master} {rx}x{ry} cell={cell_w}x{cell_h}")


if __name__ == "__main__":
    main()
