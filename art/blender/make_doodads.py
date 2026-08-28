"""Ground doodads: modelled in code, rendered through the locked rig.

    blender -b art/template.blend -P art/blender/make_doodads.py -- --name grass_tuft
    blender -b art/template.blend -P art/blender/make_doodads.py -- --all
    python art/tools/downsample_doodads.py

These are too small to survive a Tripo generation - a 6px tuft of grass is
below the resolution at which image-to-3D carries any intent - so they are
built directly. That has one large consequence beyond the modelling: doodads
are authored ON the locked palette, so the whole palette_drift / anchor /
remap chain does not apply to them. There is no generation to correct.

WHAT IS DIFFERENT FROM A BUILDING

  * No cell packing. A building is framed to whole tiles so it lands on the
    grid; a doodad is scattered at an arbitrary world point and framed tight
    to its own alpha.
  * The anchor is the doodad's GROUND CENTRE - world (0,0,0) - not the
    footprint's bottom-centre. Doodads have no footprint contract. The
    metadata records `anchor_mode` explicitly so a consumer cannot mistake one
    convention for the other; that confusion has already cost a round once.
  * No states, no glow, no shadow layer. They lie in the ground texture.

THE TWO PROJECTIONS, AND WHY THEY DIFFER

`screen_uv` gives v = sin(60)*y + cos(60)*z, and the downsample maps u at 32px
per tile and v at 32/GROUND_SQUASH = 36.9502px per unit. So:

    one tile of ground DEPTH  -> 0.86603 * 36.9502 = 32.0 px   (square, 1:1)
    one tile of world HEIGHT  -> 0.5     * 36.9502 = 18.475 px (WALL_RATIO)

Both matter here. "6px tall" is a request about the SPRITE, so it converts to
world Z through the second line, not the first - asking for 6px of world height
would produce an 11px sprite. And the first line is why `plan_squash` is 1.0:
ground shapes already arrive at true proportions.
"""

import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lock       # noqa: E402
import normalize  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

PX_PER_V = lock.TILE_PX / lock.GROUND_SQUASH              # 36.9502
PX_PER_Z = math.cos(math.radians(lock.CAM_PITCH_DEG)) * PX_PER_V   # 18.4752
PAD_PX = 1.0


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


def palette_material(member, value_scale=1.0, tag=""):
    """On-palette HUE, value scaled to sit against the ground.

    The scale is a single scalar applied to all three linear channels, so
    chromaticity is preserved EXACTLY - the same property the split albedo
    correction relies on (PIPELINE.md 32). The doodad keeps the palette
    member's identity and gives up only its brightness.

    It has to give that up. Every locked member's albedo is 2.0-4.4x the
    ground's luminance BEFORE any light is added, so no palette-value material
    under the locked rig can sit inside a 1.25:1 cap. See PIPELINE.md 34.
    """
    name = f"doodad_{member}_{tag}_{value_scale:.4f}"
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    h = lock.PALETTE[member].lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    lin = [c * value_scale for c in lin]
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = lock.ROUGHNESS_RANGE[1]
    bsdf.inputs["Metallic"].default_value = 0.0
    # KILL THE SPECULAR LOBE. It is albedo-INDEPENDENT, so with it on, scaling
    # base colour down does not scale the render down - the first calibration
    # run measured an identical 2.66:1 at scale 0.003 and 0.0119 and the solver
    # sat there spinning. It also carries its own wide shading range, being a
    # highlight. Same shape of bug as the roughness/metallic clamp that did
    # nothing because the sockets were linked: a default doing work nobody
    # asked it to do.
    for sock, val in (("Specular IOR Level", 0.0), ("IOR", 1.0),
                      ("Coat Weight", 0.0), ("Sheen Weight", 0.0)):
        if sock in bsdf.inputs:
            bsdf.inputs[sock].default_value = val
    return mat


def new_object(name, verts, faces, member, scale=1.0, tag=""):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(palette_material(member, scale, tag))
    bpy.context.scene.collection.objects.link(ob)
    return ob


def blade(rng, height, w0, lean_dir, curve):
    """One tapered blade of grass: a 4-segment strip, curving as it rises."""
    segs = 4
    verts, faces = [], []
    cx, cy = 0.0, 0.0
    for i in range(segs + 1):
        t = i / segs
        z = height * t
        # quadratic lean, so the base stays upright and the tip bows over
        off = curve * t * t
        x = cx + math.cos(lean_dir) * off
        y = cy + math.sin(lean_dir) * off
        w = w0 * (1.0 - 0.92 * t)
        nx, ny = -math.sin(lean_dir) * w, math.cos(lean_dir) * w
        verts += [(x - nx, y - ny, z), (x + nx, y + ny, z)]
        if i:
            b = 2 * (i - 1)
            faces.append((b, b + 1, b + 3, b + 2))
    return verts, faces


def leaf(rng, length, width, azim, tilt):
    """A broad leaf: a flat lens shape, tilted up from the ground."""
    segs = 5
    verts, faces = [], []
    for i in range(segs + 1):
        t = i / segs
        r = length * t
        # widest at a third of the way out, tapering to a point
        w = width * math.sin(math.pi * min(1.0, t * 1.15)) * 0.5
        z = math.sin(tilt) * r * (1.0 - 0.45 * t)
        rad = math.cos(tilt) * r
        x, y = math.cos(azim) * rad, math.sin(azim) * rad
        nx, ny = -math.sin(azim) * w, math.cos(azim) * w
        verts += [(x - nx, y - ny, z), (x + nx, y + ny, z)]
        if i:
            b = 2 * (i - 1)
            faces.append((b, b + 1, b + 3, b + 2))
    return verts, faces


def build_upright(cfg, rng):
    obs = []
    mats = cfg["materials"]
    vs = float(cfg.get("albedo_value_scale", 1.0))
    tag = cfg["name"]
    if "blades" in cfg:
        h = cfg["height_px"] / PX_PER_Z
        spread = cfg["spread_px"] / lock.TILE_PX
        n = int(cfg["blades"])
        for i in range(n):
            az = rng.uniform(0, 2 * math.pi)
            hh = h * rng.uniform(0.72, 1.0)
            v, f = blade(rng, hh, spread * 0.10, az, spread * rng.uniform(0.20, 0.32))
            ob = new_object(f"{cfg['name']}_blade{i}", v, f, mats[i % len(mats)], vs, tag)
            r = spread * 0.5 * math.sqrt(rng.random()) * 0.6
            a = rng.uniform(0, 2 * math.pi)
            ob.location = (math.cos(a) * r, math.sin(a) * r, 0.0)
            obs.append(ob)
    else:
        h = cfg["height_px"] / PX_PER_Z
        spread = cfg["spread_px"] / lock.TILE_PX
        n = int(cfg["leaves"])
        for i in range(n):
            az = (i / n) * 2 * math.pi + rng.uniform(-0.35, 0.35)
            # narrow tilt spread: leaves that agree about where the sun is
            tilt = rng.uniform(0.72, 0.92)
            v, f = leaf(rng, spread * rng.uniform(0.42, 0.60),
                        spread * rng.uniform(0.26, 0.38), az, tilt)
            ob = new_object(f"{cfg['name']}_leaf{i}", v, f, mats[i % len(mats)], vs, tag)
            ob.location = (0.0, 0.0, h * rng.uniform(0.0, 0.16))
            obs.append(ob)
        # a short stem so the clump reads as one plant, not scattered leaves
        v, f = blade(rng, h * 0.75, spread * 0.055, 0.0, spread * 0.05)
        obs.append(new_object(f"{cfg['name']}_stem", v, f, mats[-1], vs, tag))
    return obs


def build_ground(cfg, rng):
    obs = []
    mats = cfg["materials"]
    vs = float(cfg.get("albedo_value_scale", 1.0))
    tag = cfg["name"]
    plan = cfg["plan_px"] / lock.TILE_PX
    if cfg["name"] == "_calib_dome":
        # A hemisphere presents every normal a ground doodad can present.
        # Its rendered p95/p5 IS the locked rig's diffuse dynamic range - the
        # hard floor under any contrast cap, measured rather than argued.
        bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24,
                                             radius=plan / 2.0, location=(0, 0, 0))
        ob = bpy.context.active_object
        import bmesh
        bm = bmesh.new(); bm.from_mesh(ob.data)
        for v in [v for v in bm.verts if v.co.z < 0]:
            bm.verts.remove(v)
        bm.to_mesh(ob.data); bm.free()
        ob.data.materials.append(palette_material(mats[0], vs, tag))
        return [ob]
    if cfg["name"] == "_calib_disc":
        bpy.ops.mesh.primitive_circle_add(vertices=64, radius=plan / 2.0,
                                          fill_type="NGON", location=(0, 0, 0.001))
        ob = bpy.context.active_object
        ob.data.materials.append(palette_material(mats[0], vs, tag))
        return [ob]
    if "stones" in cfg:
        n = int(cfg["stones"])
        for i in range(n):
            r = plan * rng.uniform(0.16, 0.26)
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r)
            ob = bpy.context.active_object
            ob.name = f"{cfg['name']}_stone{i}"
            # stones are wider than they are tall - they sit, they do not float
            # FLAT. A sphere sweeps its normals through 90deg and blows the
            # contrast band open on its own; a pressed stone points mostly up.
            ob.scale = (rng.uniform(0.95, 1.15), rng.uniform(0.9, 1.1),
                        rng.uniform(0.16, 0.22))
            a = rng.uniform(0, 2 * math.pi)
            d = plan * 0.5 * rng.uniform(0.15, 0.42)
            ob.location = (math.cos(a) * d, math.sin(a) * d, r * 0.30)
            ob.rotation_euler = (0, 0, rng.uniform(0, math.pi))
            ob.data.materials.append(palette_material(mats[0], vs, tag))
            obs.append(ob)
        return obs
    # fallen twig: a tapered cylinder lying down, plus one side branch
    for i, (ln, rad, az, off) in enumerate((
            (plan, plan * 0.055, rng.uniform(-0.55, 0.55), (0.0, 0.0)),
            (plan * 0.38, plan * 0.035, rng.uniform(0.9, 1.9), (plan * 0.16, plan * 0.05)))):
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=rad, depth=ln)
        ob = bpy.context.active_object
        ob.name = f"{cfg['name']}_stick{i}"
        ob.rotation_euler = (0.0, math.pi / 2, az)
        # pressed flat for the same reason as the stones - a full round barrel
        # shows every normal from vertical to grazing in six pixels
        ob.scale = (0.34, 1.0, 1.0)
        ob.location = (off[0], off[1], rad * 0.34)
        ob.data.materials.append(palette_material(mats[0], vs, tag))
        obs.append(ob)
    return obs


def frame_doodad(obs, plan_squash):
    """Tight screen bbox -> sprite size, camera, and the ground-centre anchor."""
    if plan_squash != 1.0:
        for ob in obs:
            ob.scale = (ob.scale[0], ob.scale[1] * plan_squash, ob.scale[2])
            ob.location = (ob.location[0], ob.location[1] * plan_squash, ob.location[2])
    bpy.context.view_layer.update()
    co = normalize.world_coords(obs)
    u, v = normalize.screen_uv(co)
    pad_u = PAD_PX / lock.TILE_PX
    pad_v = PAD_PX / PX_PER_V
    u0, u1 = float(u.min()) - pad_u, float(u.max()) + pad_u
    v0, v1 = float(v.min()) - pad_v, float(v.max()) + pad_v

    sw = max(1, int(math.ceil((u1 - u0) * lock.TILE_PX)))
    sh = max(1, int(math.ceil((v1 - v0) * PX_PER_V)))
    rw = sw * lock.SUPERSAMPLE
    rh = max(1, int(round(sh * lock.SUPERSAMPLE * lock.GROUND_SQUASH)))

    cam_u = (u0 + u1) * 0.5
    cam_v = (v0 + v1) * 0.5
    # world (0,0,0) -> u=0, v=0; find it in final sprite pixels
    anchor = [round(sw * 0.5 - cam_u * lock.TILE_PX, 2),
              round(sh * 0.5 + cam_v * PX_PER_V, 2)]
    return {"sprite_px": [sw, sh], "render_px": [rw, rh],
            "cam_uv": [cam_u, cam_v], "anchor_px": anchor}


def render_one(cfg, out_dir):
    for ob in list(bpy.context.scene.objects):
        if ob.type == "MESH":
            bpy.data.objects.remove(ob, do_unlink=True)
    rng = random.Random(int(cfg["seed"]))
    obs = (build_upright(cfg, rng) if cfg["kind"] == "upright"
           else build_ground(cfg, rng))
    fr = frame_doodad(obs, float(cfg.get("plan_squash", 1.0)))

    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = fr["render_px"]
    cam = scene.camera
    normalize.place_camera(cam, fr["sprite_px"][0] / lock.TILE_PX,
                           fr["cam_uv"][0], fr["cam_uv"][1])
    master = os.path.join(out_dir, f"{cfg['name']}_4x.png")
    scene.render.filepath = master
    bpy.ops.render.render(write_still=True)

    meta = {
        "name": cfg["name"],
        "kind": cfg["kind"],
        "status": cfg.get("status", "real"),
        "materials": cfg["materials"],
        "plan_squash": float(cfg.get("plan_squash", 1.0)),
        "albedo_value_scale": float(cfg.get("albedo_value_scale", 1.0)),
        "seed": cfg["seed"],
        "sprite_px": fr["sprite_px"],
        "render_px": fr["render_px"],
        "anchor_px": fr["anchor_px"],
        # SPELLED OUT so it cannot be confused with the building contract.
        # Buildings: draw at footprint_bottom_centre - anchor_px.
        # Doodads:   draw at ground_point           - anchor_px.
        "anchor_mode": "ground_centre",
        "master": os.path.relpath(master, REPO).replace("\\", "/"),
        "lock_stamp": lock.lock_stamp(),
    }
    with open(os.path.join(out_dir, f"{cfg['name']}.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print(f"DOODAD {cfg['name']} render={fr['render_px']} sprite={fr['sprite_px']} "
          f"anchor={fr['anchor_px']} squash={meta['plan_squash']}")


def main():
    a = get_args()
    with open(os.path.join(REPO, "art", "doodads.json")) as f:
        man = json.load(f)
    out_dir = os.path.join(REPO, "art", "renders", "doodads")
    os.makedirs(out_dir, exist_ok=True)
    todo = [d for d in man["doodads"]
            if "all" in a or d["name"] == a.get("name")]
    if not todo:
        raise SystemExit(f"no doodad matched {a.get('name')!r}")
    if "vscale" in a:
        for d in todo:
            d["albedo_value_scale"] = float(a["vscale"])
    if "squash" in a:
        for d in todo:
            d["plan_squash"] = float(a["squash"])
            d["name"] = d["name"] + a.get("suffix", "")
    for d in todo:
        render_one(d, out_dir)


if __name__ == "__main__":
    main()
