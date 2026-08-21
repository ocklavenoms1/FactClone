# State hook: smelter "smelting".
#
# Invoked by render_asset.py via --extra-py, after normalization and before
# framing, with `bpy`, `root` and `scale` in scope.
#
# The principle for visual states: the MESH IS NEVER REGENERATED. One Tripo
# generation produces the body; each state is a material/light delta applied at
# render time. This keeps states pixel-aligned with each other by construction
# — vital, since the game swaps between them on the same tile.
#
# Here: make the furnace mouth emissive and add a warm point light in front of
# it so the glow spills onto the surrounding hull.

import bpy

# Strength is deliberately low. Anything above ~4 clips to pure white once the
# 128 px render is downsampled to 32 px, and a white blob reads as a hole in the
# sprite rather than as heat. Tuned by eye at true in-game size, not at 4x.
GLOW_RGB = (1.0, 0.42, 0.10)
GLOW_STRENGTH = 3.0

# Match by material name first (real Tripo meshes carry arbitrary object names,
# so name-matching is a convention we control at export/rename time).
targets = [m for m in bpy.data.materials
           if any(k in m.name.lower() for k in ("firebrick", "mouth", "furnace"))]

for m in targets:
    if not m.use_nodes:
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Emission Color"].default_value = (*GLOW_RGB, 1.0)
        bsdf.inputs["Emission Strength"].default_value = GLOW_STRENGTH

# spill light just outside the furnace mouth (-Y face of the hull)
light_data = bpy.data.lights.new("SmeltGlow", type="POINT")
light_data.energy = 18.0
light_data.color = GLOW_RGB
light_data.shadow_soft_size = 0.3
glow = bpy.data.objects.new("SmeltGlow", light_data)
bpy.context.scene.collection.objects.link(glow)
glow.location = (0.0, -0.95, 0.42)

print(f"STATE_HOOK: smelting applied to {len(targets)} material(s)")
