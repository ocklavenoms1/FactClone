# make_proxies.py — builds crude stand-in GLBs with the same PROPORTIONS as the
# three Session 1 assets, so the render pipeline can be validated before any
# real Tripo mesh exists. These are shape tests, not art. They are throwaway:
# when the real GLB lands in art/source/, it replaces the proxy by filename.
#
# Run: blender -b -P art/blender/make_proxies.py -- --out-dir <dir>
#
# Proxies deliberately cover the three failure modes:
#   chest       1x1, fits inside its tile              -> baseline case
#   smelter     2x2, footprint scaling + state variant -> footprint case
#   power_pole  1x1 base, ~3 tiles tall                -> vertical overflow case
#   dir_test    1x1 with an unmistakable front         -> rotation experiment

import bpy
import math
import os
import sys


def get_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = {}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--"):
            args[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return args


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, rough=0.7, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def box(name, size, loc, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.data.materials.append(material)
    return o


def cyl(name, r, h, loc, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=16)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    return o


def export(path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB")
    print(f"PROXY: {path}")


def build_chest(out):
    reset()
    steel = mat("steel", (0.34, 0.30, 0.28))
    rust = mat("rust", (0.42, 0.24, 0.12), rough=0.85)
    box("body", (0.85, 0.7, 0.5), (0, 0, 0.25), steel)
    box("lid", (0.88, 0.73, 0.12), (0, 0, 0.55), rust)
    box("latch", (0.12, 0.06, 0.16), (0, -0.36, 0.44), rust)
    for sx in (-1, 1):
        box(f"handle{sx}", (0.05, 0.3, 0.06), (sx * 0.44, 0, 0.36), rust)
    export(os.path.join(out, "chest.glb"))


def build_smelter(out):
    reset()
    stone = mat("stone", (0.38, 0.36, 0.33), rough=0.9)
    iron = mat("iron", (0.22, 0.20, 0.19), rough=0.6, metal=0.6)
    brick = mat("firebrick", (0.45, 0.18, 0.12), rough=0.85)
    box("hull", (1.7, 1.7, 1.2), (0, 0, 0.6), stone)
    box("band_lo", (1.76, 1.76, 0.14), (0, 0, 0.30), iron)
    box("band_hi", (1.76, 1.76, 0.14), (0, 0, 0.95), iron)
    # furnace mouth: recessed arch on -Y face, named so the state hook can find it
    box("furnace_mouth", (0.7, 0.12, 0.55), (0, -0.85, 0.42), brick)
    cyl("chimney", 0.22, 1.0, (0.55, 0.55, 1.6), iron)
    cyl("chimney_cap", 0.28, 0.12, (0.55, 0.55, 2.14), iron)
    export(os.path.join(out, "smelter.glb"))


def build_power_pole(out):
    reset()
    timber = mat("creosote", (0.26, 0.18, 0.11), rough=0.95)
    galv = mat("galvanized", (0.55, 0.57, 0.58), rough=0.4, metal=0.8)
    ceramic = mat("ceramic", (0.62, 0.60, 0.45), rough=0.35)
    box("footing", (0.55, 0.55, 0.18), (0, 0, 0.09), mat("concrete", (0.48, 0.47, 0.44), rough=0.95))
    cyl("pole", 0.09, 2.7, (0, 0, 1.44), timber)
    box("crossarm", (0.9, 0.09, 0.09), (0, 0, 2.55), galv)
    for sx in (-1, 1):
        cyl(f"insulator{sx}", 0.06, 0.14, (sx * 0.35, 0, 2.67), ceramic)
    export(os.path.join(out, "power_pole.glb"))


def build_dir_test(out):
    """1x1 block with an unmistakable front + top marker, for the rotation test."""
    reset()
    body = mat("body", (0.35, 0.35, 0.38), rough=0.6, metal=0.3)
    front = mat("front", (0.75, 0.55, 0.10), rough=0.5)
    top = mat("top", (0.15, 0.45, 0.55), rough=0.5)
    box("hull", (0.8, 0.8, 0.6), (0, 0, 0.3), body)
    box("nose", (0.5, 0.2, 0.3), (0, -0.45, 0.32), front)   # points -Y
    box("fin", (0.1, 0.5, 0.35), (0, 0.2, 0.75), top)       # asymmetric on top
    export(os.path.join(out, "dir_test.glb"))


def build_inserter_parts(out):
    """Body and arm exported SEPARATELY, both sharing the world origin as the
    arm's pivot. This is the geometry contract for the moving-parts pipeline:
    the arm's rotation axis must sit at the origin so that rendering the arm at
    N angles produces frames that are already aligned to the static body."""
    # NB: materials must be created AFTER each reset() — reset wipes the
    # datablocks and any earlier handle becomes a removed StructRNA.
    reset()
    yellow = mat("insert_yellow", (0.72, 0.55, 0.09), rough=0.5)
    dark = mat("insert_dark", (0.20, 0.19, 0.18), rough=0.6, metal=0.4)
    box("base", (0.8, 0.8, 0.28), (0, 0, 0.14), dark)
    box("housing", (0.5, 0.5, 0.3), (0, 0, 0.36), yellow)
    export(os.path.join(out, "inserter_body.glb"))

    reset()
    yellow = mat("insert_yellow", (0.72, 0.55, 0.09), rough=0.5)
    dark = mat("insert_dark", (0.20, 0.19, 0.18), rough=0.6, metal=0.4)
    # arm pivots about world Z at the origin; hand at the far end
    cyl("arm", 0.05, 0.75, (0, -0.37, 0.62), yellow, rot=(math.radians(90), 0, 0))
    box("hand", (0.22, 0.16, 0.1), (0, -0.72, 0.62), dark)
    export(os.path.join(out, "inserter_arm.glb"))


def main():
    a = get_args()
    out = os.path.abspath(a.get("out-dir", "."))
    os.makedirs(out, exist_ok=True)
    build_chest(out)
    build_smelter(out)
    build_power_pole(out)
    build_dir_test(out)
    build_inserter_parts(out)


if __name__ == "__main__":
    main()
