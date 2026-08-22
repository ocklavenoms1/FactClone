# Prompts and art direction — Stewardship buildings

## The flow

```
concept image (flat-lit, 3/4 view, white bg)
      ↓  verify the silhouette BY EYE
Tripo image-to-3D
      ↓
GLB → art/source/<name>.glb
```

**Text-to-3D is not used.** The first smelter prompt contained *NOT round*,
*NOT conical*, *NOT domed* — three separate negations — and Tripo returned a
beehive kiln. Negative form constraints are not honoured, and no rewording
fixes a modality that ignores them.

The point of the concept image is not that image models are better at 3D. It is
that **a wrong silhouette is visible in two seconds** and costs one cheap
regeneration, instead of surviving into a 65 MB mesh and a full render pass
before anyone notices.

**Generate every concept image in one batch, one session, one style reference.**
That single discipline does more for cross-asset consistency than every
downstream normalization step combined.

---

## Style block — verbatim, unchanged for every asset

Copy this exactly. Never paraphrase it, never "improve" it for one asset.

```
Early-industrial agrarian MACHINE, hand-built from farm materials but clearly a
working piece of equipment. Fieldstone, weathered oak timber framing, wrought
iron banding, leather.

Not sci-fi. Not steampunk. Not fantasy. Not a decorative prop or set dressing.

Form: a squared rectangular block on a square plan, wider than it is tall.
Flat faceted walls that may batter slightly. Flat top. Heavy visible timber
framing. Hand-built and slightly irregular, never machined smooth.

Everything sits inside a square footprint. No arms, no outriggers, nothing
projecting sideways beyond the body. The mass is centred in its own footprint.

Function readable at a glance: a visible input where material goes in and a
visible output where product comes out.

At most FOUR readable features on the whole building. Stone is LARGE blocks, at
most four courses visible on a face. Not cobbles, not rubble, not small stones.
Every detail at least one eighth of the building's width - nothing thin, no
narrow lines, no small repeated ornament. Timber is plain, no visible grain.
Matte, light edge wear only. No grunge, no rust streaking, no dirt.

Colours only: fieldstone grey #5A5E58, wrought iron blue-grey #36455E,
weathered oak #7A6633, leather red-brown #7E3B2C, verdigris green #3D7A5E
(accents only).

Any region that glows when the machine is running is painted FLAT MAGENTA
#FF00FF with no shading — it is a mask, not a colour.

Flat even shadowless lighting. Plain white background, no ground, no base.
```

Aspect **1:1**.

---

## The palette is a closed set

**Five members, spread across hue.** `fired_clay` and `forge_brown` are
**removed**: a member Tripo cannot reproduce and the pipeline cannot correct is
a liability, not a member.

| Role | Hex | Hue | Sat | Use |
|---|---|---|---|---|
| fieldstone | `#5A5E58` | 100° | 0.06 | stone |
| wrought iron | `#36455E` | 218° | 0.43 | ironwork |
| weathered oak | `#7A6633` | 43° | 0.58 | timber |
| leather | `#7E3B2C` | 11° | 0.65 | leather, canvas |
| verdigris | `#3D7A5E` | 153° | 0.50 | accents only |

**Minimum pairwise chromaticity distance 0.2743 = 1.83× the matcher's 0.15
confidence threshold.** Every pair clears comfortably. The old six-member set
had four members at hue 17–30° separated only by value; the matcher is
value-invariant by design, so those four were mutually invisible to it — which
is why `forge_brown` mismatched at 0.279 and `fired_clay` needed a 4.4× clamp.
Those were the palette failing, not the matcher.

> **The structural rule, learned the hard way: only ONE member may sit near the
> white point.** A near-neutral colour's chromaticity *is* the white point, so
> its distance to anything else is capped by that other colour's saturation.
> Two near-neutrals can never be told apart. Fieldstone holds that slot at
> saturation 0.06 — which is why wrought iron had to move from 0.25 to 0.43.

Three hexes moved from the first draft of this palette to clear the threshold:
wrought iron `#3C4650`→`#36455E`, weathered oak `#7A5A33`→`#7A6633`, leather
`#7E4433`→`#7E3B2C`, verdigris `#4E7A66`→`#3D7A5E`. Fieldstone was untouched.

### Heat is a state, not a material

Any region that glows is painted **flat `#FF00FF`, unshaded**. Blender keys on
it and substitutes the real fire colour at render time; the magenta is
neutralized to a dark cavity colour in *every* state, so an idle firebox reads
as a cold dark opening and the mask never reaches the screen.

Measured separation, linear RGB:

| | distance from `#FF00FF` |
|---|---|
| nearest palette member (leather) | **1.256** |
| the distance that killed the first attempt | 0.079 |

Re-verified against the five-member palette. Detection uses the linear chroma
score `min(R,B) − G`: every palette member scores **negative** (worst is
fieldstone at −0.0143) against an emit cut of **+0.16** — a margin of 0.17, so
no palette member can false-trigger the mask.

> **Rejected alternative, and why.** The first fix was to add a saturated
> orange `#FF5A18` so the key would separate. That solves masking by making a
> hot-looking colour legitimately available to every *cold* asset in the set,
> which Tripo will then drift into. It buys a working mask at the cost of
> palette discipline across twenty buildings. The mask belongs outside the
> palette, not inside it.

**Validate the mask on the next generation before trusting it:**

```bash
blender -b -P art/blender/dump_texture.py -- --glb art/source/<name>.glb --out-dir art/renders/tex
python art/tools/keymask.py art/renders/tex/<name>_basecolor.png
```

It prints the texel-distance histogram and passes only on a clean bimodal gap.
JPEG smear around a hard magenta edge is the plausible failure mode; this is
how we would see it, on asset 4 rather than asset 14. **Until it passes, the
per-asset emitter (`glow_at`) remains the shipping mechanism** — it works, and
it is not deprecated yet.

---

## Hard rules, with the numbers attached

Rules with a number attached survive. Rules without one get quietly relaxed.
All figures measured on the first kiln.

**Containment.** Everything sits inside the footprint. No outriggers, no arms
projecting sideways. *Measured cost on the first kiln: the timber outrigger
consumed **38% of the sprite's width** and rendered the building itself
**1.69× smaller** than the same tile could have held.*

**Centring.** The mass is centred in its own footprint. *The first kiln's apex
sat **0.28 tiles left of its own tile centre**. A building not centred on the
tile it occupies reads as misplaced the moment it stands next to another one.*

**Detail budget: FOUR readable features per tile, four stone courses per face.**
Tightened from six.
*The first kiln measured **8.75 features per tile** — 1.46× over the cap — and
**14.3% of its spatial-frequency energy is destroyed by the downsample**, against
about 2% for flat-shaded geometry. That 14.3% is generation effort that
provably cannot reach the screen. Cobbles are not a matter of taste; they are
waste, and now we can say so with a figure.*

Re-measure any asset with:

```bash
python art/tools/detail_density.py <sprite_name>
```

**Minimum strut or wall thickness 1/16 tile**, or it vanishes on downsample.

---

## Tripo settings

| Setting | Value | Why |
|---|---|---|
| Mode | **image-to-3D** | text-to-3D ignores negative form constraints |
| Style preset | **None / Original** | a preset is a second, uncontrolled style layer |
| Texture | **on, 2048+** | the texture is the asset; the mesh is thrown away |
| Auto-orient | **off** | Blender owns orientation (`yaw_correction`) |
| Auto-scale | **off** | Blender owns scale (`fit`) |
| Remesh / decimate | **off** | rounds off the chamfers that read as highlight lines at 32 px |
| Polycount | **maximum** | irrelevant to cost; only the render ships |

Expect ~65 MB, ~2M triangles, one fused mesh, one material, an 8K basecolour
plus 4K normal and roughness/metallic. The pipeline handles it: the real kiln
imports, normalizes and renders eight turnaround views in **18 seconds**.

---

## Reject before importing

- Round, conical, domed, or beehive-shaped
- Anything projecting outside the footprint
- Projecting parts not tucked flush inside the corner posts — bellows, chutes,
  levers and hoods all sit *against* the flank, never standing off it. The
  approved smelter's bellows measured 10.2% of sprite width and was accepted
  only because it was marginal; the first kiln's outrigger was 38%
- Mass not centred in its own footprint
- More than four stone courses on a face
- Baked shadows or highlights in the texture
- A ground plane or base slab fused to the bottom
- Struts thinner than 1/16 tile
- Magenta region shaded, gradient, or absent

**Fixable downstream — do not reject for these:** arbitrary yaw, arbitrary
scale, off-centre origin, wrong roughness/metallic, slightly-off saturation.

---

## Subject blocks

### smelter — ACCEPTED, but LEGACY PALETTE (`stone furnace 3d model.glb`)

> **Regenerate against the five-member palette.** This asset was generated
> against the old six-member set, and a new-palette remap on it *recolours*
> rather than corrects: only 2 of 5 anchors match (wrought iron 0.334, leather
> 0.285, verdigris 0.299 — all dropped as untrusted), oak's gain clamps at 2.5,
> and the whole asset goes olive. Its accepted appearance is preserved by
> keeping the legacy remap in the manifest (`"palette_era": "legacy-6"`).
>
> The general rule: **the albedo correction is a drift corrector, not a
> recolouring tool.** A palette change requires regeneration.


Fixes all three rejects on the first kiln. Measured, not eyeballed:

| check | first kiln | approved | verdict |
|---|---|---|---|
| form | conical beehive | squared block, square plan | fixed |
| containment | outrigger **38%** of width | bellows **10.2%** | flagged, marginal |
| detail density | 8.75 features/tile | **5.92** per occupied tile (cap 6) | pass |
| HF destroyed | 14.3% (6.1× floor) | **5.2%** (2.21× floor, cap 3×) | pass |
| magenta mask | absent | **present, keymask PASS** | live |

The bellows is 0.2 points over the 10% containment threshold — not worth a
regeneration on its own, but on any future revision tuck it flush to the flank
inside the corner posts.

**Note for every future asset: Tripo darkens the mask.** The `#FF00FF` panel
came back as **`#9D009A`**, roughly half brightness. Detection is by chroma
rather than absolute colour so this is handled — but paint the mask flat and
fully saturated, and never assume the returned colour is the one you painted.

```
Subject: a bloomery smelter that melts ore into iron blooms.

A squat rectangular fieldstone furnace block, clearly wider than tall, with
slightly battered flat walls and a flat top.

Features: square ore hopper on the top rear, arched firebox at the front base
with its interior painted flat magenta, iron bloom chute low on the front
right, a flat leather wedge bellows lying tight against the left flank inside
the footprint, four corner timber posts with iron straps. Nothing more.
```

### chest — not yet generated
### power_pole — not yet generated

Both go through the same flow and the same style block. **Only when all three
are real is the three-way consistency verdict meaningful**; everything before
that is pipeline validation, and that has passed.

---

## Rules of engagement

1. One asset per prompt. Never variants, sets, or scenes.
2. Judge the concept image's silhouette before spending a Tripo generation.
3. Off-style output is **regenerated, never repaired in Blender.** Blender
   fixes geometry and material *range*; only the prompt fixes style, form, and
   detail density.
4. Run the 8-way turnaround on every new asset and **read** `yaw_correction`
   off it. Never guess which way a model faces.
5. Keep every accepted prompt in this file next to its asset name. The prompt
   is part of the asset's source.
