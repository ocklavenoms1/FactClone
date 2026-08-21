"""Regenerates art/template.blend from scratch.

    blender -b -P art/blender/make_template.py

The .blend is shipped too, but this script is the source of truth: it is
diffable, reviewable, and keeps the lock in readable code rather than buried in
a binary. Never hand-edit the .blend; edit here and regenerate.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lock  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_BLEND = os.path.join(REPO, "art", "template.blend")

CAM_DISTANCE = 30.0  # orthographic: distance is cosmetic, just clear of geometry


def sun(name, elev_deg, plan_deg, energy, color, angle_deg=2.0):
    """A sun whose rays travel from (elev, plan) toward the origin.

    plan_deg is a compass-style bearing in the ground plane: 90 = +Y (screen
    up/back), 180 = -X (screen left). The key at 135 therefore sits back-left,
    which puts the highlight on screen upper-left and throws shadows toward
    lower-right.
    """
    data = bpy.data.lights.new(name, type="SUN")
    data.energy = energy
    data.color = color
    data.angle = math.radians(angle_deg)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)

    # direction FROM the light TO the origin
    el = math.radians(elev_deg)
    az = math.radians(plan_deg)
    pos = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
    obj.location = pos * 20.0
    # a sun points down its local -Z; aim that at the origin
    obj.rotation_euler = (-pos).to_track_quat("-Z", "Y").to_euler()
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "SpriteRender"

    # ------------------------------------------------------------- render --
    scene.render.engine = lock.ENGINE
    scene.cycles.device = lock.CYCLES_DEVICE
    scene.cycles.samples = lock.CYCLES_SAMPLES
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filter_size = 1.20
    # Square pixels, always. The vertical squash is handled by the render
    # height and undone in the downsample - see lock.render_px().
    scene.render.pixel_aspect_x = 1.0
    scene.render.pixel_aspect_y = 1.0
    scene.render.resolution_percentage = 100
    scene.render.resolution_x, scene.render.resolution_y = lock.render_px(1, 1)

    scene.view_settings.view_transform = lock.VIEW_TRANSFORM
    scene.view_settings.look = lock.VIEW_LOOK
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    # -------------------------------------------------------------- world --
    world = bpy.data.worlds.new("SpriteWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*lock.WORLD_COLOR, 1.0)
    bg.inputs["Strength"].default_value = lock.WORLD_STRENGTH
    scene.world = world

    # ------------------------------------------------------------- camera --
    cam_data = bpy.data.cameras.new("SpriteCam")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "HORIZONTAL"   # ortho_scale spans the WIDTH in tiles
    cam_data.ortho_scale = 1.0
    cam_data.clip_start = 0.01
    cam_data.clip_end = 200.0
    cam = bpy.data.objects.new("SpriteCam", cam_data)
    scene.collection.objects.link(cam)

    # Pitch is measured above the ground plane, so tilt from vertical is
    # (90 - pitch). Azimuth 0 keeps the ground grid axis-aligned.
    cam.rotation_euler = (
        math.radians(lock.TILT_FROM_VERTICAL_DEG),
        0.0,
        math.radians(lock.CAM_AZIMUTH_DEG),
    )
    back = cam.rotation_euler.to_matrix() @ Vector((0.0, 0.0, 1.0))
    cam.location = back * CAM_DISTANCE
    scene.camera = cam

    # ----------------------------------------------------------- lighting --
    sun("KeyLight", lock.KEY_ELEV_DEG, lock.KEY_PLAN_DEG,
        lock.KEY_ENERGY, lock.KEY_COLOR, lock.KEY_ANGLE_DEG)
    sun("FillLight", lock.FILL_ELEV_DEG, lock.FILL_PLAN_DEG,
        lock.FILL_ENERGY, lock.FILL_COLOR, 15.0)
    sun("RimLight", lock.RIM_ELEV_DEG, lock.RIM_PLAN_DEG,
        lock.RIM_ENERGY, lock.RIM_COLOR, 15.0)

    # ---------------------------------------------- one-tile reference cube --
    ref_col = bpy.data.collections.new("REFERENCE")
    scene.collection.children.link(ref_col)
    mesh = bpy.data.meshes.new("TileRefCube")
    s = 0.5
    verts = [(x, y, z + s) for x in (-s, s) for y in (-s, s) for z in (-s, s)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
             (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    cube = bpy.data.objects.new("TileRefCube", mesh)
    ref_col.objects.link(cube)
    ref_col.hide_render = True
    ref_col.hide_viewport = True

    scene["lock_stamp"] = lock.lock_stamp()

    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print(f"TEMPLATE_SAVED {OUT_BLEND} lock={lock.lock_stamp()}")


if __name__ == "__main__":
    main()
