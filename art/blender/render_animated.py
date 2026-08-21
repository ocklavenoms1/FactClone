# render_animated.py — renders a multi-part building as one sprite PER FRAME,
# with the moving part posed in 3D and the whole assembly rendered together.
#
# Why not composite two sprite layers instead: a part that swings behind the
# body must be OCCLUDED by it, and must cast/receive shadow against it. Alpha-
# compositing an arm sprite over a body sprite can only ever draw the arm in
# front, so rear-facing frames read as the arm floating over the housing.
# Rendering the posed assembly gets depth and shading right for free.
#
# Run:
#   blender -b art/template.blend -P art/blender/render_animated.py -- \
#       --body art/source/inserter_body.glb --part art/source/inserter_arm.glb \
#       --name inserter --footprint 1 --canvas-tiles 3 --frames 0,45,90,135,180
#
# The part GLB must have its pivot at the world origin (see PIPELINE.md).

import json
import math
import os
import sys

import bpy
import mathutils

RENDER_PX_PER_TILE = 128
FINAL_PX_PER_TILE = 32

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


def import_under(path, name):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    new = [o for o in bpy.context.scene.objects if o not in before]
    for o in list(new):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    for o in new:
        if o.name in bpy.data.objects and o.parent is None:
            o.parent = root
    return root


def bounds(objs):
    deps = bpy.context.evaluated_depsgraph_get()
    lo = mathutils.Vector((1e9, 1e9, 1e9))
    hi = mathutils.Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
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
    name = a["name"]
    footprint = float(a.get("footprint", "1"))
    inset = float(a.get("inset", "0.92"))
    canvas_tiles = int(a.get("canvas-tiles", "3"))
    frames = [float(f) for f in a.get("frames", "0,45,90,135,180").split(",")]

    body = import_under(a["body"], f"{name}_body")
    part = import_under(a["part"], f"{name}_part")

    # normalize on the BODY footprint only, then apply the same scale to the
    # part so their proportions stay locked to each other.
    body_meshes = [o for o in bpy.context.scene.objects
                   if o.type == "MESH" and o.name != "TileRefCube" and o.parent == body]
    lo, hi = bounds(body_meshes)
    size = hi - lo
    s = (footprint * inset) / max(size.x, size.y)
    center = (lo + hi) * 0.5
    offset = mathutils.Vector((-center.x * s, -center.y * s, -lo.z * s))

    for root in (body, part):
        root.scale = (s, s, s)
        root.location = offset
    bpy.context.view_layer.update()

    cam = bpy.context.scene.camera
    cam.data.ortho_scale = float(canvas_tiles)
    rot = cam.rotation_euler.to_matrix()
    cam.location = rot.col[2] * 20.0  # framed on origin, fixed for all frames

    scene = bpy.context.scene
    res = canvas_tiles * RENDER_PX_PER_TILE
    scene.render.resolution_x = res
    scene.render.resolution_y = res

    renders = os.path.join(REPO, "art", "renders")
    sprites = os.path.join(REPO, "art", "sprites")
    os.makedirs(renders, exist_ok=True)
    os.makedirs(sprites, exist_ok=True)

    base_matrix = part.matrix_world.copy()
    written = []
    for f in frames:
        spin = mathutils.Matrix.Rotation(math.radians(f), 4, "Z")
        # rotate about the world Z axis through the footprint origin
        part.matrix_world = spin @ base_matrix
        bpy.context.view_layer.update()

        tag = f"{name}_f{int(f)}"
        big = os.path.join(renders, f"{tag}_4x.png")
        scene.render.filepath = big
        bpy.ops.render.render(write_still=True)

        img = bpy.data.images.load(big)
        small = canvas_tiles * FINAL_PX_PER_TILE
        img.scale(small, small)
        out = os.path.join(sprites, f"{tag}.png")
        img.filepath_raw = out
        img.file_format = "PNG"
        img.save()
        bpy.data.images.remove(img)
        written.append(os.path.basename(out))
        print(f"FRAME: {out}")

    meta = {
        "name": name,
        "footprint_tiles": footprint,
        "canvas_tiles": canvas_tiles,
        "sprite_px": canvas_tiles * FINAL_PX_PER_TILE,
        "anchor_px_from_center": [0.0, 0.0],
        "frames_deg": frames,
        "frame_files": written,
    }
    with open(os.path.join(sprites, f"{name}_frames.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    print(f"ANIM_DONE: {len(written)} frames")


if __name__ == "__main__":
    main()
