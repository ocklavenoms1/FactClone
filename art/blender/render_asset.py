# render_asset.py — imports a GLB into the locked template, normalizes scale
# against the tile grid, frames the silhouette, renders 4x + true-size sprite.
#
# Run:
#   blender -b art/template.blend -P art/blender/render_asset.py -- \
#       --glb art/source/chest.glb --name chest --footprint 1 \
#       [--max-height 2.5] [--inset 0.92] [--suffix _idle] [--extra-py file.py]
#
# Outputs:
#   art/renders/<name><suffix>_4x.png     (128 px per tile)
#   art/sprites/<name><suffix>.png        (32 px per tile, in-game size)
#   art/sprites/<name><suffix>.json       (canvas size + footprint anchor)
#
# The anchor JSON records where the footprint center sits relative to the
# sprite center, in final-sprite pixels: place the sprite so that
# (sprite_center + anchor_px) lands on the building's footprint center.

import bpy
import json
import math
import os
import sys

import mathutils

RENDER_PX_PER_TILE = 128  # LOCKED (4x of in-game 32)
FINAL_PX_PER_TILE = 32    # LOCKED
PAD_TILES = 0.08          # silhouette padding before snapping canvas to tiles

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def get_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = {}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--"):
            args[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else "1"
            i += 2
        else:
            i += 1
    return args


def mesh_objects():
    return [o for o in bpy.context.scene.objects
            if o.type == "MESH" and o.name != "TileRefCube"]


def world_bounds(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    lo = mathutils.Vector((1e9, 1e9, 1e9))
    hi = mathutils.Vector((-1e9, -1e9, -1e9))
    for o in objs:
        ev = o.evaluated_get(deps)
        m = ev.matrix_world
        for v in ev.to_mesh().vertices:
            w = m @ v.co
            lo = mathutils.Vector(map(min, lo, w))
            hi = mathutils.Vector(map(max, hi, w))
        ev.to_mesh_clear()
    return lo, hi


def main():
    a = get_args()
    glb = os.path.abspath(a["glb"])
    name = a["name"]
    footprint = float(a.get("footprint", "1"))
    inset = float(a.get("inset", "0.92"))
    max_height = float(a.get("max-height", "0"))  # 0 = uncapped
    suffix = a.get("suffix", "")

    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    imported = [o for o in bpy.context.scene.objects if o not in before]
    for o in imported:
        if o.type == "LIGHT" or o.type == "CAMERA":
            bpy.data.objects.remove(o, do_unlink=True)

    # parent everything under one empty so normalization is a single transform
    root = bpy.data.objects.new(f"{name}_root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in imported:
        if o.name in bpy.data.objects and o.parent is None:
            o.parent = root

    meshes = mesh_objects()
    lo, hi = world_bounds(meshes)
    size = hi - lo

    # uniform scale: footprint fills footprint*inset tiles, optionally height-capped
    s = (footprint * inset) / max(size.x, size.y)
    if max_height > 0 and size.z * s > max_height:
        s = max_height / size.z
    root.scale = (s, s, s)
    # base on Z=0, footprint center at origin
    center = (lo + hi) * 0.5
    root.location = (-center.x * s, -center.y * s, -lo.z * s)

    # --yaw spins the MODEL about world Z before framing. For 4-way buildings
    # this is how the four facings are produced: 0/90/180/270. Rotating the
    # finished sprite in Godot instead would rotate the baked lighting and the
    # projection with it — see art/PIPELINE.md, "Rotation".
    yaw = float(a.get("yaw", "0"))
    if yaw:
        rot = mathutils.Matrix.Rotation(math.radians(yaw), 4, "Z")
        root.matrix_world = rot @ root.matrix_world
    bpy.context.view_layer.update()

    # optional per-asset hook (state lights, material tweaks) before framing
    if "extra-py" in a:
        exec(compile(open(os.path.abspath(a["extra-py"])).read(), a["extra-py"], "exec"),
             {"bpy": bpy, "root": root, "scale": s})
        bpy.context.view_layer.update()

    # frame the silhouette in camera space
    cam = bpy.context.scene.camera
    rot = cam.rotation_euler.to_matrix()
    right, up = rot.col[0], rot.col[1]
    deps = bpy.context.evaluated_depsgraph_get()
    px = [1e9, -1e9]
    py = [1e9, -1e9]
    for o in mesh_objects():
        ev = o.evaluated_get(deps)
        m = ev.matrix_world
        for v in ev.to_mesh().vertices:
            w = m @ v.co
            x, y = w.dot(right), w.dot(up)
            px[0], px[1] = min(px[0], x), max(px[1], x)
            py[0], py[1] = min(py[0], y), max(py[1], y)
        ev.to_mesh_clear()

    span = max(px[1] - px[0], py[1] - py[0]) + 2 * PAD_TILES
    canvas_tiles = max(1, math.ceil(span))
    cx, cy = (px[0] + px[1]) / 2, (py[0] + py[1]) / 2

    # --canvas-tiles / --center-on-origin force a FIXED frame instead of fitting
    # to this mesh's silhouette. Required for any multi-frame set (animation
    # frames, rotation sets, idle/active state pairs of differing extent):
    # auto-fitting each frame independently would silently re-center every frame
    # and the sequence would jitter. Frames must share one canvas and one origin.
    if "canvas-tiles" in a:
        canvas_tiles = int(a["canvas-tiles"])
    if "center-on-origin" in a:
        cx, cy = 0.0, 0.0

    cam.data.ortho_scale = float(canvas_tiles)
    back = rot.col[2]
    cam.location = right * cx + up * cy + back * 20.0

    res = canvas_tiles * RENDER_PX_PER_TILE
    scene = bpy.context.scene
    scene.render.resolution_x = res
    scene.render.resolution_y = res

    renders = os.path.join(REPO, "art", "renders")
    sprites = os.path.join(REPO, "art", "sprites")
    os.makedirs(renders, exist_ok=True)
    os.makedirs(sprites, exist_ok=True)

    big_path = os.path.join(renders, f"{name}{suffix}_4x.png")
    scene.render.filepath = big_path
    bpy.ops.render.render(write_still=True)

    img = bpy.data.images.load(big_path)
    small = canvas_tiles * FINAL_PX_PER_TILE
    img.scale(small, small)
    small_path = os.path.join(sprites, f"{name}{suffix}.png")
    img.filepath_raw = small_path
    img.file_format = "PNG"
    img.save()

    # anchor: world origin (footprint center) relative to sprite center, +y down
    ax = (0.0 - cx) / canvas_tiles * small
    ay = -(0.0 - cy) / canvas_tiles * small
    meta = {
        "name": name + suffix,
        "footprint_tiles": footprint,
        "canvas_tiles": canvas_tiles,
        "render_px": res,
        "sprite_px": small,
        "anchor_px_from_center": [round(ax, 2), round(ay, 2)],
        "scale_applied": round(s, 5),
        "source_glb": os.path.relpath(glb, REPO),
    }
    with open(os.path.join(sprites, f"{name}{suffix}.json"), "w") as f:
        json.dump(meta, f, indent=2)

    print(f"RENDERED: {big_path}")
    print(f"SPRITE: {small_path} ({small}x{small}, anchor {meta['anchor_px_from_center']})")


if __name__ == "__main__":
    main()
