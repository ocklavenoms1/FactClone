"""Render a palette on flat proxy geometry - no Tripo, no correction.

    blender -b art/template.blend -P art/blender/palette_swatch.py -- --set undistorted
    blender -b art/template.blend -P art/blender/palette_swatch.py -- --set separable5

The only honest way to judge a palette is to see it under the locked rig at
true size, with nothing between the hex and the pixel. Every previous look at
these colours was through a Tripo texture and an albedo correction; that shows
a correction, not a palette.

Each member gets a 1-tile block. Then two proxy buildings are re-materialed
from the palette so the colours can be judged in combination rather than as
isolated chips.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lock       # noqa: E402
import normalize  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

SETS = {
    "undistorted": {
        "fieldstone": "#5A5E58",
        "wrought_iron": "#46504E",
        "weathered_oak": "#6B4E32",
        "leather": "#7A4438",
        "verdigris": "#4E7A66",
    },
    "separable5": {
        "fieldstone": "#5A5E58",
        "wrought_iron": "#36455E",
        "weathered_oak": "#7A6633",
        "leather": "#7E3B2C",
        "verdigris": "#3D7A5E",
    },
}


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


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_linear(h):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def flat_mat(name, hexcol):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*hex_linear(hexcol), 1.0)
    # mid-band roughness, zero metallic: the locked clamps' own midpoint, so
    # the surface response is neutral and only the hue is under test
    b.inputs["Roughness"].default_value = sum(lock.ROUGHNESS_RANGE) / 2.0
    b.inputs["Metallic"].default_value = 0.0
    return m


def clear():
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o.name != "TileRefCube":
            bpy.data.objects.remove(o, do_unlink=True)


def render(tag, cell_w, cell_h, out_dir):
    scene = bpy.context.scene
    cam = scene.camera
    cam_v = (cell_h * lock.GROUND_SQUASH) / 2.0 - lock.GROUND_SQUASH * (cell_h / 2.0) \
        + (cell_h * lock.GROUND_SQUASH) / 2.0 - lock.GROUND_SQUASH * 0.5
    normalize.place_camera(cam, cell_w, 0.0, cam_v)
    rx, ry = lock.render_px(cell_w, cell_h)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry
    path = os.path.join(out_dir, f"{tag}_4x.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"SWATCH {tag} {rx}x{ry} -> {path}")
    return path


def box(name, size, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.data.materials.append(mat)
    return o


def cyl(name, r, h, loc, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=20)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


def main():
    a = get_args()
    setname = a.get("set", "undistorted")
    pal = SETS[setname]
    out_dir = os.path.join(REPO, "art", "renders", "palette", setname)
    os.makedirs(out_dir, exist_ok=True)

    mats = {n: flat_mat(f"{setname}_{n}", h) for n, h in pal.items()}

    # ---- one chip per member: a plain 1-tile block ------------------------
    for n, m in mats.items():
        clear()
        box(f"chip_{n}", (0.92, 0.92, 0.62), (0, 0, 0.31), m)
        render(f"chip_{n}", 1, 2, out_dir)

    # ---- the colours in combination, on proxy buildings -------------------
    clear()
    box("body", (1.7, 1.7, 1.0), (0, 0, 0.5), mats["fieldstone"])
    box("band", (1.76, 1.76, 0.12), (0, 0, 0.22), mats["wrought_iron"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"post{sx}{sy}", (0.16, 0.16, 1.12), (sx * 0.82, sy * 0.82, 0.56), mats["weathered_oak"])
    box("hopper", (0.62, 0.62, 0.34), (0.3, 0.3, 1.17), mats["weathered_oak"])
    box("bellows", (0.1, 0.62, 0.62), (-0.9, 0, 0.5), mats["leather"])
    box("accent", (0.5, 0.06, 0.16), (0, -0.86, 0.34), mats["verdigris"])
    render("proxy_smelter", 2, 3, out_dir)

    clear()
    box("footing", (0.55, 0.55, 0.18), (0, 0, 0.09), mats["fieldstone"])
    cyl("pole", 0.09, 2.4, (0, 0, 1.28), mats["weathered_oak"])
    box("crossarm", (0.9, 0.09, 0.09), (0, 0, 2.34), mats["wrought_iron"])
    for sx in (-1, 1):
        cyl(f"ins{sx}", 0.06, 0.14, (sx * 0.35, 0, 2.46), mats["verdigris"])
    render("proxy_pole", 1, 3, out_dir)

    clear()
    box("chest_body", (0.85, 0.7, 0.5), (0, 0, 0.25), mats["weathered_oak"])
    box("chest_lid", (0.88, 0.73, 0.12), (0, 0, 0.55), mats["leather"])
    box("chest_band", (0.9, 0.06, 0.56), (0, 0, 0.3), mats["wrought_iron"])
    render("proxy_chest", 1, 2, out_dir)

    print(f"SWATCH_SET_DONE {setname} -> {out_dir}")


if __name__ == "__main__":
    main()
