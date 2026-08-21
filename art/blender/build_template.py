# build_template.py — creates art/template.blend, the locked sprite-render scene.
# Run:  blender -b -P art/blender/build_template.py
#
# LOCKED CONSTANTS — changing any of these breaks coherence with every sprite
# already rendered. Do not touch without re-rendering the entire asset set.
#
#   1 Blender unit = 1 game tile (TILE_SIZE = 32 px in-game)
#   Camera: orthographic, azimuth 45 deg, pitch 35 deg from vertical
#   Render: 128 px per tile (4x supersample), downsampled to 32 px per tile
#   Lighting: 3-sun rig fixed relative to camera azimuth (see below)
#   Color: view transform 'Standard' (no AgX — keeps sprite colors punchy)

import bpy
import math
import os
import sys

CAM_AZIMUTH_DEG = 45.0   # LOCKED
CAM_PITCH_DEG = 35.0     # LOCKED — degrees tilted from straight-down
RENDER_PX_PER_TILE = 128  # LOCKED — 4x the in-game 32 px/tile
CYCLES_SAMPLES = 64

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_BLEND = os.path.join(REPO, "art", "template.blend")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "SpriteRender"

    # --- render settings ---
    scene.render.engine = "CYCLES"
    scene.cycles.samples = CYCLES_SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 2 * RENDER_PX_PER_TILE  # placeholder; render script sets per asset
    scene.render.resolution_y = 2 * RENDER_PX_PER_TILE
    scene.render.resolution_percentage = 100

    # --- world: dim neutral ambient, renders to alpha (film_transparent) ---
    world = bpy.data.worlds.new("SpriteWorld")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.5, 0.5, 0.5, 1.0)
    bg.inputs["Strength"].default_value = 0.3
    scene.world = world

    # --- camera ---
    cam_data = bpy.data.cameras.new("SpriteCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0  # placeholder; render script frames per asset
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100.0
    cam = bpy.data.objects.new("SpriteCam", cam_data)
    scene.collection.objects.link(cam)
    cam.rotation_euler = (math.radians(CAM_PITCH_DEG), 0.0, math.radians(CAM_AZIMUTH_DEG))
    # back the camera off along its own +Z (behind the lens); ortho, so distance is cosmetic
    back = cam.rotation_euler.to_matrix() @ __import__("mathutils").Vector((0.0, 0.0, 1.0))
    cam.location = back * 20.0
    scene.camera = cam

    # --- 3-sun lighting rig, fixed relative to camera azimuth. LOCKED. ---
    # key : azimuth cam+90 (upper-left of frame), 50 deg elevation, warm, energy 4.0
    # fill: azimuth cam-60 (right of frame),      30 deg elevation, cool, energy 1.2
    # rim : azimuth cam+180 (behind subject),     25 deg elevation, white, energy 2.0
    rig = [
        ("KeyLight",  CAM_AZIMUTH_DEG - 90.0, 50.0, 2.2, (1.00, 0.98, 0.95)),
        ("FillLight", CAM_AZIMUTH_DEG + 60.0, 30.0, 0.7, (0.85, 0.90, 1.00)),
        ("RimLight",  CAM_AZIMUTH_DEG + 180.0, 25.0, 1.1, (1.00, 1.00, 1.00)),
    ]
    for name, az, elev, energy, color in rig:
        sun_data = bpy.data.lights.new(name, type="SUN")
        sun_data.energy = energy
        sun_data.color = color
        sun_data.angle = math.radians(5.0)  # slightly soft shadow edges
        sun = bpy.data.objects.new(name, sun_data)
        scene.collection.objects.link(sun)
        # sun at (0,0,0) shines down its -Z; tilt from vertical by (90-elev), spin to azimuth
        sun.rotation_euler = (math.radians(90.0 - elev), 0.0, math.radians(az))

    # --- reference cube: exactly one game tile, base on Z=0. Never rendered. ---
    ref_col = bpy.data.collections.new("REFERENCE")
    scene.collection.children.link(ref_col)
    mesh = bpy.data.meshes.new("TileRefCube")
    s = 0.5
    verts = [(x, y, z + s) for x in (-s, s) for y in (-s, s) for z in (-s, s)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    cube = bpy.data.objects.new("TileRefCube", mesh)
    ref_col.objects.link(cube)
    ref_col.hide_render = True

    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print(f"TEMPLATE_SAVED: {OUT_BLEND}")


if __name__ == "__main__":
    main()
