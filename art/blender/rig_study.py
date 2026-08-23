"""Measure how the rig's key:fill ratio drives form-dependent lightness.

    blender -b art/template.blend -P art/blender/rig_study.py

MEASUREMENT ONLY. This script never writes the template and never changes the
lock. It renders probes at the current rig and at alternative fill levels and
prints the numbers, so the decision to unlock the rig - the last locked thing,
and the most expensive to move - can be made on evidence.

WHY
Two finished sprites side by side showed the smelter reading pale against the
pole. Decomposed, the cause is not the correction and not the view transform:
it is the rig multiplier differing 8.63x vs 2.85x between a blocky mass and a
thin post. A locked palette hex is an albedo, and this rig multiplies it by
3-9x depending on how a surface faces the key - so FORM, not material, decides
final lightness.

THE PROBES
Three flat-shaded surfaces at the same albedo, isolating the orientations that
matter:
  top    a horizontal plate            - the broad top face of a block
  front  a vertical plane facing -Y    - the face turned to camera
  post   a thin vertical column        - edge-on, largely self-shadowed

The spread between them IS the form-driven lightness range. Narrowing it makes
assets agree with each other; narrowing it too far flattens the form and every
building reads as a decal, so both numbers are reported together.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lock  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
GREY = 0.18
RES = 160


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def clear_probes():
    for o in list(bpy.context.scene.objects):
        if o.name.startswith("probe_"):
            bpy.data.objects.remove(o, do_unlink=True)


def make_probe(kind, mat):
    if kind == "top":
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0.5))
        o = bpy.context.active_object
    elif kind == "front":
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, -0.5, 0.5))
        o = bpy.context.active_object
        o.rotation_euler = (math.radians(90), 0, 0)
    else:  # post
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
        o = bpy.context.active_object
        o.scale = (0.10, 0.10, 1.0)
    o.name = f"probe_{kind}"
    o.data.materials.append(mat)
    return o


def render_mean(tag):
    scene = bpy.context.scene
    out = os.path.join(REPO, "art", "renders", "rigstudy", f"{tag}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    scene.render.filepath = out
    scene.render.resolution_x = scene.render.resolution_y = RES
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(out)
    import numpy as np
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    bpy.data.images.remove(img)
    op = px[:, 3] > 0.5
    if op.sum() == 0:
        return 0.0
    rgb = px[op, :3]           # Blender pixels are already LINEAR
    y = rgb[:, 0] * 0.2126 + rgb[:, 1] * 0.7152 + rgb[:, 2] * 0.0722
    return float(np.median(y))


def main():
    scene = bpy.context.scene
    mat = bpy.data.materials.new("probe_flat")
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    g = srgb_to_linear(GREY)
    b.inputs["Base Color"].default_value = (g, g, g, 1.0)
    b.inputs["Roughness"].default_value = sum(lock.ROUGHNESS_RANGE) / 2.0
    b.inputs["Metallic"].default_value = 0.0

    cam = scene.camera
    cam.data.ortho_scale = 1.6
    rot = cam.rotation_euler.to_matrix()
    cam.location = rot.col[1] * (lock.GROUND_SQUASH * 0.5) + rot.col[2] * 30.0

    key = bpy.data.objects["KeyLight"]
    fill = bpy.data.objects["FillLight"]
    world_bg = scene.world.node_tree.nodes["Background"]

    variants = [
        ("locked", lock.FILL_ENERGY, lock.WORLD_STRENGTH),
        ("fill x2", lock.FILL_ENERGY * 2.0, lock.WORLD_STRENGTH),
        ("fill x3 + ambient x1.5", lock.FILL_ENERGY * 3.0, lock.WORLD_STRENGTH * 1.5),
    ]

    print(f"albedo on every probe: {GREY} sRGB = {g:.4f} linear")
    print(f"key energy {lock.KEY_ENERGY} (unchanged in every variant)\n")
    print(f"{'variant':26}{'key:fill':>10}"
          f"{'top':>9}{'front':>9}{'post':>9}{'spread':>9}{'top/post':>10}")

    rows = []
    for name, fe, amb in variants:
        fill.data.energy = fe
        world_bg.inputs["Strength"].default_value = amb
        mults = {}
        for kind in ("top", "front", "post"):
            clear_probes()
            make_probe(kind, mat)
            bpy.context.view_layer.update()
            mults[kind] = render_mean(f"{kind}_{name.replace(' ', '_')}") / g
        vals = [mults["top"], mults["front"], mults["post"]]
        spread = max(vals) - min(vals)
        ratio = mults["top"] / max(mults["post"], 1e-6)
        print(f"{name:26}{lock.KEY_ENERGY / fe:9.2f}:1"
              f"{mults['top']:9.2f}{mults['front']:9.2f}{mults['post']:9.2f}"
              f"{spread:9.2f}{ratio:10.2f}")
        rows.append((name, mults, spread, ratio))

    print("\nFORM READABILITY - the contrast the rig gives between a lit face and")
    print("a turned-away one. Too little and every building reads as a flat decal.")
    base = rows[0]
    for name, m, spread, ratio in rows:
        d_top_front = abs(m["top"] - m["front"]) / max(m["top"], 1e-6) * 100
        print(f"  {name:26} top-vs-front separation {d_top_front:5.1f}%"
              f"   form spread {spread / base[2] * 100:5.0f}% of locked")

    print("\nNOTHING WAS CHANGED. The template on disk is untouched; these were")
    print("in-memory variants only.")


if __name__ == "__main__":
    main()
