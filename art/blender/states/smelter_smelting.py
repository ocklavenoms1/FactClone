"""State hook: smelter "smelting".

TWO MECHANISMS LIVE HERE, DELIBERATELY.

1. MASK EMISSION - the standard for assets 4-20.
   Any region that should glow is painted flat #FF00FF in the concept image.
   normalize.neutralize_mask() has already replaced that magenta with a dark
   cavity colour (so it never reaches the screen in ANY state) and handed back
   the mask socket. This hook reuses that exact socket to drive emission, so
   the lit region and the neutralized region cannot disagree.

   Magenta is used because it appears in no real material in this set.
   Measured separation in linear RGB from the palette:
       nearest palette member (fired_clay)  1.194
       widest pair inside the palette       0.206
       the distance that killed the old key 0.079
   The mask sits 15x clear of the failure threshold, so tolerance is no longer
   a knife-edge - anything up to ~0.60 works.

   Validate on each new asset with the harness before trusting it:
       blender -b -P art/blender/dump_texture.py -- --glb art/source/X.glb \
           --out-dir art/renders/tex
       python art/tools/keymask.py art/renders/tex/X_basecolor.png
   It reports the texel-distance histogram and passes only on a clean bimodal
   gap. JPEG smear around a hard magenta edge is the plausible failure, and
   this is how we would see it.

2. EMITTER FALLBACK - what the current smelter actually ships with.
   The existing kiln was generated before the mask existed, so it has no
   magenta: the harness measures 0.000% of texels within 0.6 of the key, and
   100% out past 1.2. A warm point light is placed in the furnace mouth from
   `glow_at` in the manifest instead. It needs nothing from the texture and
   lights the real recessed geometry rather than faking a glow.

   This mechanism is NOT deprecated yet. It ships until the mask is validated
   on a real generation; only then does per-asset emitter placement go away.

WHY NOT WIDEN THE PALETTE INSTEAD
The earlier fix was to add a saturated orange (#FF5A18) so the key would
separate. That solves the masking problem by making a hot-looking colour
legitimately available to every cold asset in the set, which Tripo would then
drift into. It buys a working mask at the cost of palette discipline across
twenty buildings. The mask belongs outside the palette, not inside it.
"""

import lock

GLOW_MAX = 2.2                # <= lock.EMISSION_CEILING
FALLBACK_ENERGY = 26.0


def mask_emission(sockets):
    """Drive emission from the mask socket normalization already built."""
    lit = 0
    for mat_name, socket in (sockets or {}).items():
        mat = bpy.data.materials.get(mat_name)
        if not mat or not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf:
            continue

        gain = nt.nodes.new("ShaderNodeMath")
        gain.operation = "MULTIPLY"
        gain.label = f"mask emission x{GLOW_MAX}"
        gain.inputs[1].default_value = GLOW_MAX
        nt.links.new(socket, gain.inputs[0])

        ecol = bsdf.inputs.get("Emission Color")
        estr = bsdf.inputs.get("Emission Strength")
        if ecol is not None:
            ecol.default_value = (*lock.MASK_FIRE_COLOR, 1.0)
        if estr is not None:
            nt.links.new(gain.outputs["Value"], estr)
        lit += 1
    return lit


def emitter(where):
    data = bpy.data.lights.new("SmeltGlow", type="POINT")
    data.energy = FALLBACK_ENERGY
    data.color = lock.MASK_FIRE_COLOR
    data.shadow_soft_size = 0.12
    obj = bpy.data.objects.new("SmeltGlow", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = tuple(where)
    return obj


lit = mask_emission(globals().get("mask_sockets"))     # noqa: F821
spot = globals().get("glow_at")                        # noqa: F821
if spot:
    emitter(spot)

print(f"STATE smelting: mask-driven emission on {lit} material(s)"
      f"{'; emitter fallback at ' + str(spot) if spot else '; no emitter'}")
