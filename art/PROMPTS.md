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

CONTRAST BY AREA:
LARGE regions - walls, roof, base, posts - are strongly DIFFERENT in value from
each other. A stone wall against a timber post should read as light against
dark at a glance.
THIN features - bands, straps, bolts, rivets, edging, trim - are CLOSE in VALUE
to whatever surrounds them, but keep their own HUE. A thin iron band on a timber
post is barely darker than the post, never a hard dark line - and it is still
unmistakably iron-coloured, never a blend halfway between iron and timber.

NO VISIBLE WOOD GRAIN. Timber is a flat block of colour. No striping, no
lengthwise fibres, no plank lines.

Colours only: fieldstone grey #5A5E58, wrought iron #46504E, weathered oak
#6B4E32, leather #7A4438, verdigris green #4E7A66 (accents only).

Any region that glows when the machine is running is painted FLAT MAGENTA
#FF00FF with no shading — it is a mask, not a colour.

Flat even shadowless lighting. If any directional light is unavoidable, the key
must come from the UPPER LEFT, matching the render rig. Never lit from the
right or from below. Plain white background, no ground, no base.
```

Aspect **1:1**.

---

## The palette is a closed set

**Five members - natural, undistorted.** `fired_clay` and `forge_brown` are
**removed**: a member Tripo cannot reproduce and the pipeline cannot correct is
a liability, not a member.

| Role | Hex | Use |
|---|---|---|
| fieldstone | `#5A5E58` | stone |
| wrought iron | `#46504E` | ironwork |
| weathered oak | `#6B4E32` | timber |
| leather | `#7A4438` | leather, canvas |
| verdigris | `#4E7A66` | accents only |

**Palette era: `natural-5`.** Every asset declares it and the build **fails** on
a mismatch. An asset generated against a superseded palette cannot enter the
consistency verdict, and the albedo correction cannot retarget it - retargeting
recolours rather than corrects, measured.

### These colours are not distorted for the matcher - the ORDERING was fixed

An earlier draft pushed iron blue and oak olive to force chromaticity
separation. That solved the right problem in the wrong place. Matching used to
run **before** the global gain was removed, which forced the metric to be
value-invariant - and a value-invariant metric cannot tell two near-neutrals
apart at any hue. The palette was being distorted to compensate for an ordering
mistake.

The order is now: estimate the global gain from **aggregate** albedo (no
matching needed), divide it out, match on **full linear RGB** (chromaticity
*and* value), then per-cluster remap.

Correct-assignment rate over 25 randomised trials, stone-heavy mix and random
per-generation gain:

| palette | old ordering | new ordering |
|---|---|---|
| **this one (natural)** | 53.6% | **89.6%** |
| distorted "separable-5" | 78.4% | 93.6% |

The distorted palette remains 4 points better. That is the price of natural
colour, paid deliberately. On the real smelter both near-neutrals now clear the
trust threshold - fieldstone at 0.19 of min-pair, wrought iron at 0.44 - where
chromaticity matching had them at the edge.

> **The rule that survives:** a value-invariant matcher can hold only ONE
> near-neutral. Removing the global gain first is what lets fieldstone and
> wrought iron coexist - they differ hugely in luminance even though both sit
> near the white point.

See `art/renders/palette_board.png`: both candidate palettes rendered on flat
proxy geometry under the locked rig, no Tripo and no correction in the path.

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

These are **diagnostics, not gates**. They tell you where an asset is spending
its budget so the prompt can be aimed at the real source. They do not reject
anything - the finished 32 px sprite, looked at, does that.

```bash
python art/tools/detail_density.py <sprite_name>      # what it costs
python art/tools/hf_regions.py <sprite_name>          # where it costs it
python art/tools/eye_sheet.py --asset <name>          # THE GATE
```

*The HF number rejected a pole that looked good, and chasing it produced a
plastic asset. It caught real mud once, on the first kiln, and that is what it
is for - not for deciding on its own.*

**Minimum strut or wall thickness 1/16 tile**, or it vanishes on downsample.

**Contrast by AREA, not globally.** This is the rule that separates a cheap
asset from an expensive one:

| | |
|---|---|
| **Large regions** | **HIGH** value contrast - helps the matcher, reads at 32 px |
| **Thin features** | **LOW** value contrast - close in value to their surroundings |

*"Ironwork reads darker than the oak" was right for a base plate and wrong for
a band.* Both halves are measured:

- The smelter's rivets proved the second half: **16 of 20 sub-2px features**, and
  the **lowest HF destruction of the set**, because they were low-contrast and
  averaged into the strap.
- The power pole proved the cost of getting it wrong: **10 of 16 features sub-2px
  AND high-contrast** - dark iron bands against light timber - and **15.6% HF
  destroyed, worse than the kiln that was rejected for cobbles.**

A thin high-contrast edge is the single most expensive thing you can ask for at
this resolution. A thin low-contrast one is free.

**Low contrast means VALUE, not HUE.** The pole's bands were asked to be "only
slightly darker than the timber" and came back a warm olive sitting between
weathered oak and wrought iron - a cluster **equidistant from three palette
members at once (d1/d2 = 0.97)**, which the matcher cannot assign, so those
pixels go uncorrected. Keep a thin feature close in lightness to its
surroundings and firmly in its own hue.

**NO VISIBLE WOOD GRAIN - measured.** On the pole, **64% of all destroyed
high-frequency energy is vertical striping, rising to 74% inside the mast**;
the two iron bands account for only 26% there. Grain is the single largest HF
cost in the set, roughly 3:1 over the thing it was assumed to be. Timber is a
flat block of colour.

---

## The hexes are advisory — material separation is not

**Getting a palette hex slightly wrong costs nothing.** `SMELTER.glb` was
prompted with `#3C4650` blue iron and `#7A5A33` olive oak against a locked
palette of `#46504E` and `#6B4E32`, and both matched — oak, the most wrongly
prompted member, matched *best* of the four. Re-verified at the derived K after
the original measurement proved contaminated; all four declared members clear
with zero drops.

**What binds instead: every material an asset claims must appear as a visually
distinct region with real area.** Declare it in `palette_members` and prompt so
the materials separate. A member with no area gets skipped; a member that reads
as a shade of its neighbour is ambiguous and gets dropped.

So write the colours in the prompt as guidance, not as a specification — but be
strict about *which* materials appear and that they look different from each
other.

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
