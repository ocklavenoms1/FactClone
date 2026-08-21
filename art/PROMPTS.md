# Tripo Prompt Template — Stewardship building assets

The consistency lever is discipline, not luck. Every asset prompt is the same
sentence skeleton with only the bracketed slots changed. The style preamble and
constraint suffix are **verbatim identical** across all assets — never
paraphrase them, never "improve" them.

Model version is pinned: `v3.1-20260211` (Tripo H series, text-to-model).
A model-version change is a schema-bump-level event: it restyles everything,
so it requires re-generating the full asset set.

## The form

```
Stylized industrial {SUBJECT}, a {DESCRIPTION}. Factorio-style factory
building proportions: squat, chunky, boxy silhouette with a compact square
base. Weathered painted steel, riveted metal plates, visible bolts, subtle
rust and grime, muted desaturated industrial colors with {ACCENT} accents.
Clean readable large shapes, medium detail density, no fine greebles.
Single object, centered, upright, no ground plane, no scenery, no text,
no characters.
```

| Slot | What goes in it |
|---|---|
| `{SUBJECT}` | Two-to-four word building name, e.g. "storage chest" |
| `{DESCRIPTION}` | One clause of concrete geometry: base shape, lid/mouth/arm, 2–3 distinguishing features. Name shapes, not functions. |
| `{ACCENT}` | The building-class accent color, from the palette table below |

## Accent palette (per building class)

| Class | Accent |
|---|---|
| Storage (chest, warehouse) | rusty orange-brown |
| Smelting / heat | dark iron and firebrick red |
| Power (poles, accumulator, windmill) | creosote brown timber and galvanized steel |
| Logistics (inserter, belts) | industrial yellow |
| Fluid (pump, water wheel) | oxidized copper green |

## Session 1 instances

**chest** (1×1):
> Stylized industrial storage chest, a low rectangular metal storage crate with a slightly domed hinged lid, two side handles, and a front latch. Factorio-style factory building proportions: squat, chunky, boxy silhouette with a compact square base. Weathered painted steel, riveted metal plates, visible bolts, subtle rust and grime, muted desaturated industrial colors with rusty orange-brown accents. Clean readable large shapes, medium detail density, no fine greebles. Single object, centered, upright, no ground plane, no scenery, no text, no characters.

**smelter** (2×2):
> Stylized industrial smelter furnace, a heavy squat stone and cast-iron smelting furnace with an arched front furnace mouth, thick riveted iron bands, and a short wide chimney stack on the back corner. Factorio-style factory building proportions: squat, chunky, boxy silhouette with a compact square base. Weathered painted steel, riveted metal plates, visible bolts, subtle rust and grime, muted desaturated industrial colors with dark iron and firebrick red accents. Clean readable large shapes, medium detail density, no fine greebles. Single object, centered, upright, no ground plane, no scenery, no text, no characters.

**power_pole** (1×1, tall):
> Stylized industrial small electric power pole, a single tall wooden utility pole on a small square concrete footing with one steel crossarm near the top and two ceramic insulators. Factorio-style factory building proportions: squat, chunky, boxy silhouette with a compact square base. Weathered painted steel, riveted metal plates, visible bolts, subtle rust and grime, muted desaturated industrial colors with creosote brown timber and galvanized steel accents. Clean readable large shapes, medium detail density, no fine greebles. Single object, centered, upright, no ground plane, no scenery, no text, no characters.

## Rules

1. One asset per prompt. Never ask for variants, sets, or scenes.
2. If a generation comes back off-style (wrong proportions, cartoon look,
   scene clutter), **regenerate — do not hand-fix style in Blender.** Blender
   fixes geometry problems; prompts fix style problems.
3. Judge the Tripo preview render before spending Blender time on it.
4. Keep every accepted prompt verbatim in this file next to its asset name —
   the prompt is part of the asset's source.
