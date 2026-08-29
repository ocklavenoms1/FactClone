"""Is rendered luminance PROPORTIONAL to albedo, or AFFINE in it?

    blender -b art/template.blend -P art/blender/probe_specular.py -- --name chest
    python art/tools/fit_specular.py chest

This is the question the whole albedo correction rests on and it has never been
asked. The per-cluster remap is a multiplicative gain: it assumes

    rendered = k * albedo

so that scaling albedo by t/o lands the render on target. If instead

    rendered = k * albedo + s

with a non-zero s, a multiplicative gain can still put ONE point exactly on
target - the anchor - but every other point in the region lands wrong, and
wrong by an amount that grows as the region spreads away from the anchor. That
is precisely the signature already recorded and never explained: anchors
landing 1.00x on target while regions skew around them.

The candidate for s is the Principled BSDF dielectric specular lobe, which sits
at 0.5 by default, is never set anywhere in the building path, and is
ALBEDO-INDEPENDENT. It was found because it broke the doodad solver, where the
albedo was driven low enough for it to dominate outright.

METHOD
One import, then the same asset rendered across a range of uniform albedo
scales, twice: once with specular at its 0.5 default and once at 0. A Multiply
node injected after each Base Color source provides the scale, so nothing else
about the material changes between renders. Mean linear luminance over opaque
pixels is recorded per point; art/tools/fit_specular.py fits a line to each
series and reports the intercept.

Zero intercept with specular off is the control - it says the method can see
proportionality when proportionality is there. A non-zero intercept with
specular on is the finding.
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
SCALES = [0.15, 0.3, 0.5, 0.75, 1.0, 1.4]
RES_PCT = 40


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


def inject_scalers(meshes):
    """A Multiply node on every Base Color, so albedo can be swept in place."""
    seen, nodes = set(), []
    for ob in meshes:
        for slot in ob.material_slots:
            mat = slot.material
            if not mat or mat.name in seen or not mat.use_nodes:
                continue
            seen.add(mat.name)
            nt = mat.node_tree
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            base = bsdf.inputs.get("Base Color")
            if base is None or not base.is_linked:
                continue
            src = base.links[0].from_socket
            mul = nt.nodes.new("ShaderNodeVectorMath")
            mul.operation = "MULTIPLY"
            mul.label = "probe_scale"
            nt.links.new(src, mul.inputs[0])
            mul.inputs[1].default_value = (1.0, 1.0, 1.0)
            nt.links.new(mul.outputs["Vector"], base)
            nodes.append((mul, bsdf))
    return nodes


def main():
    a = get_args()
    name = a["name"]
    with open(os.path.join(REPO, "art", "assets.json")) as f:
        cfg = next(x for x in json.load(f)["assets"] if x["name"] == name)

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
    normalize.normalize_materials(norm["meshes"], enabled=True, hsv=cfg.get("hsv"))
    nodes = inject_scalers(norm["meshes"])

    fp = float(cfg["footprint"])
    fr = normalize.frame(norm["meshes"], fp)
    cw, ch = fr["cell_tiles"]
    scene = bpy.context.scene
    rx, ry = lock.render_px(cw, ch)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry
    scene.render.resolution_percentage = RES_PCT
    normalize.place_camera(scene.camera, cw, 0.0, fr["cam_uv"][1])

    out_dir = os.path.join(REPO, "art", "renders", "specprobe")
    os.makedirs(out_dir, exist_ok=True)
    runs = []
    for spec in (0.5, 0.0):
        for mul, bsdf in nodes:
            for sock, val in (("Specular IOR Level", spec),
                              ("IOR", 1.45 if spec else 1.0),
                              ("Coat Weight", 0.0), ("Sheen Weight", 0.0)):
                if sock in bsdf.inputs:
                    bsdf.inputs[sock].default_value = val
        for s in SCALES:
            for mul, _ in nodes:
                mul.inputs[1].default_value = (s, s, s)
            tag = f"{name}_spec{int(spec * 100):03d}_a{int(s * 1000):04d}"
            scene.render.filepath = os.path.join(out_dir, f"{tag}.png")
            bpy.ops.render.render(write_still=True)
            runs.append({"spec": spec, "albedo_scale": s, "file": f"{tag}.png"})
            print(f"PROBE spec={spec} albedo_scale={s} -> {tag}.png")

    with open(os.path.join(out_dir, f"{name}_probe.json"), "w") as f:
        json.dump({"asset": name, "materials": len(nodes), "runs": runs}, f, indent=2)
    print(f"PROBE_META {os.path.join(out_dir, name + '_probe.json')}")


if __name__ == "__main__":
    main()
