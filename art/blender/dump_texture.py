"""Extract an asset's textures to PNG so system-Python tools can measure them.

    blender -b -P art/blender/dump_texture.py -- \
        --glb art/source/smelter.glb --out-dir art/renders/tex [--size 1024]

An 8192x8192 image is 268M floats through bpy's pixel API; it is scaled down
first. 1024 is ample for colour-population statistics.
"""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import normalize  # noqa: E402


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
    out_dir = os.path.abspath(a.get("out-dir", "."))
    size = int(a.get("size", "1024"))
    os.makedirs(out_dir, exist_ok=True)

    normalize.import_glb(a["glb"])
    stem = os.path.splitext(os.path.basename(a["glb"]))[0]

    # A GLB can carry more than one image datablock per map type (previews,
    # duplicates). Keep only the LARGEST for each kind, or a 256px thumbnail
    # silently overwrites the 8K basecolour and every measurement downstream is
    # taken from the wrong image.
    best = {}
    for img in list(bpy.data.images):
        w, h = img.size[:]
        if not w:
            continue
        n = img.name.lower()
        if "normal" in n:
            kind = "normal"
        elif "_rm" in n or "rough" in n or "metal" in n:
            kind = "rm"
        elif "basecolor" in n or "base_color" in n or "diffuse" in n or "albedo" in n:
            kind = "basecolor"
        else:
            print(f"SKIP unclassified image {img.name} {w}x{h}")
            continue
        if kind not in best or w * h > best[kind][1] * best[kind][2]:
            best[kind] = (img, w, h)

    for kind, (img, w, h) in best.items():
        img.scale(min(size, w), min(size, h))
        path = os.path.join(out_dir, f"{stem}_{kind}.png")
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        print(f"TEX {kind} src {w}x{h} -> {min(size, w)}x{min(size, h)} {path}")


if __name__ == "__main__":
    main()
