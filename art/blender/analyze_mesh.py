"""Structural report on a Tripo mesh, after normalization.

    blender -b art/template.blend -P art/blender/analyze_mesh.py -- \
        --glb art/source/smelter.glb --footprint 2 --yaw 45

Answers two questions with numbers rather than opinion:

  * how much of the footprint the main body actually occupies, versus any
    outrigger geometry that steals scale from it
  * whether the mesh is genuinely fused, or separates into loose parts that
    could be posed independently (bears directly on the moving-parts question)
"""

import json
import os
import sys

import bpy
import numpy as np

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
    footprint = float(a.get("footprint", "2"))
    yaw = float(a.get("yaw", "0"))

    roots = normalize.import_glb(a["glb"])
    norm = normalize.normalize(roots, footprint, fit="footprint", yaw_correction_deg=yaw)
    meshes = norm["meshes"]

    tris = sum(len(m.data.loop_triangles) if m.data.loop_triangles else 0 for m in meshes)
    for m in meshes:
        m.data.calc_loop_triangles()
    tris = sum(len(m.data.loop_triangles) for m in meshes)
    verts = sum(len(m.data.vertices) for m in meshes)
    mats = sorted({s.material.name for m in meshes for s in m.material_slots if s.material})
    images = sorted({img.name: img.size[:] for img in bpy.data.images if img.size[0]}.items())

    co = normalize.world_coords(meshes)
    lo, hi = co.min(axis=0), co.max(axis=0)

    report = {
        "source": os.path.basename(a["glb"]),
        "yaw_applied": yaw,
        "objects": len(meshes),
        "triangles": tris,
        "vertices": verts,
        "materials": mats,
        "textures": [[n, list(s)] for n, s in images],
        "normalized_extent_tiles": [round(float(v), 3) for v in (hi - lo)],
        "footprint_tiles": footprint,
    }

    # ---- loose-part separation: is the mesh actually fused? ----------------
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    try:
        bpy.ops.mesh.separate(type="LOOSE")
    except Exception as e:  # noqa: BLE001
        report["separate_error"] = str(e)

    parts = [o for o in bpy.context.scene.objects
             if o.type == "MESH" and o.name != "TileRefCube"]
    part_rows = []
    for p in parts:
        pc = normalize.world_coords([p])
        plo, phi = pc.min(axis=0), pc.max(axis=0)
        p.data.calc_loop_triangles()
        part_rows.append({
            "name": p.name,
            "tris": len(p.data.loop_triangles),
            "extent": [round(float(v), 3) for v in (phi - plo)],
            "center_xy": [round(float((plo[0] + phi[0]) / 2), 3),
                          round(float((plo[1] + phi[1]) / 2), 3)],
        })
    part_rows.sort(key=lambda r: -r["tris"])
    report["loose_parts"] = len(part_rows)
    report["parts_top"] = part_rows[:8]

    # ---- how much scale the largest part actually gets ---------------------
    if part_rows:
        big = part_rows[0]
        core_xy = max(big["extent"][0], big["extent"][1])
        full_xy = max(report["normalized_extent_tiles"][0],
                      report["normalized_extent_tiles"][1])
        report["core_xy_tiles"] = round(core_xy, 3)
        report["full_xy_tiles"] = round(full_xy, 3)
        report["core_fraction_of_footprint"] = round(core_xy / footprint, 3)
        report["scale_lost_to_overhang"] = round(1.0 - core_xy / full_xy, 3)

    out = os.path.join(REPO, "art", "renders", "smelter_mesh_report.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump(report, f, indent=2)
    print("MESH_REPORT " + json.dumps({k: v for k, v in report.items() if k != "parts_top"}))
    print(f"REPORT_JSON {out}")


if __name__ == "__main__":
    main()
