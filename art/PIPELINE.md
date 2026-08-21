# Stewardship Art Pipeline — Tripo → Blender → Sprite

How a building goes from a text prompt to a PNG the game can draw. Written to
be reproducible by someone who was not present when it was built.

Nothing here touches Godot. This pipeline produces PNGs and JSON sidecars; the
sprite-loading layer is a separate session.

---

## 0. The locked constants

These are the reason the asset set looks like one game. **Changing any of them
invalidates every sprite already rendered** and requires a full re-render.
Treat a change here the way you would treat a save-schema bump.

| Constant | Value | Where |
|---|---|---|
| Camera projection | Orthographic | `template.blend` |
| Camera azimuth | **45°** | `build_template.py: CAM_AZIMUTH_DEG` |
| Camera pitch | **35° from vertical** | `build_template.py: CAM_PITCH_DEG` |
| Render resolution | **128 px per tile** (4× target) | `RENDER_PX_PER_TILE` |
| Final resolution | **32 px per tile** (= `TILE_SIZE`) | `FINAL_PX_PER_TILE` |
| Scale | 1 Blender unit = 1 game tile | reference cube |
| Key light | azimuth −90° relative to camera, 50° elevation, warm | 3-sun rig |
| Fill light | azimuth +60° relative, 30° elevation, cool | 3-sun rig |
| Rim light | azimuth +180° relative, 25° elevation, white | 3-sun rig |
| View transform | `Standard` (not AgX) | `template.blend` |
| Film | Transparent (renders to alpha) | `template.blend` |

**Why 45° / 35°.** 45° azimuth puts two faces of a boxy building in view at
equal weight, so silhouettes stay legible and the tile grid reads as diamonds
at a consistent angle. A 35° pitch is shallow enough to show the front face
(where a furnace mouth or an inserter hand lives) while still reading as a
top-down factory view. Factorio sits in the same neighbourhood.

**Why 4× supersample.** Cycles renders at 128 px per tile and the result is
box-filtered down to 32. Downsampling a large render preserves edge and
material detail that a native 32 px render turns to mush, and it leaves
headroom if `TILE_SIZE` ever increases — the 4× masters are kept in
`art/renders/`.

**Why `Standard` and not AgX.** AgX desaturates and rolls off highlights for
filmic realism. On a 32 px sprite that reads as washed-out mud. Standard keeps
the colors that the prompt asked for.

**Why the key light is fixed relative to the camera, not to the world.** Every
sprite is lit from the same screen-space direction, so a chest and a smelter
placed side by side agree about where the sun is. This is what makes a set of
independently-generated assets read as one scene.

---

## 1. Layout

```
art/
  template.blend            THE locked scene. Every render starts here.
  assets.json               manifest: one row per building
  build_sprites.ps1         the one command that builds everything
  PROMPTS.md                the Tripo prompt template + accepted prompts
  PIPELINE.md               this file
  source/                   YOUR Tripo GLBs land here (see source/README.md)
  sprites/                  OUTPUT: 32 px/tile PNGs + JSON sidecars
  renders/                  OUTPUT: 128 px/tile masters, contact sheets, tests
  blender/
    build_template.py       regenerates template.blend from code
    render_asset.py         one GLB -> one sprite
    render_animated.py      body + moving part -> a frame sequence
    make_proxies.py         crude stand-in GLBs for pipeline testing
    contact_sheet.py        all sprites at true size over a tile grid
    strip.py                a row of sprites at a chosen zoom
    rotation_test.py        the 4-renders-vs-rotate-sprite experiment
    moving_parts_test.py    the layered-composite experiment
    states/
      smelter_smelting.py   per-state material/light hooks
```

The template is **generated from code**, not hand-edited. If it is ever lost or
corrupted, rebuild it:

```bash
blender -b -P art/blender/build_template.py
```

Editing `build_template.py` and regenerating is the only supported way to
change the template — that way the locked constants live in version control
and a diff shows what changed.

---

## 2. The everyday loop

1. Write the prompt using the template in `art/PROMPTS.md`.
2. Generate in Tripo Studio; bring the GLB into `art/source/<name>.glb`
   (see `art/source/README.md` for the Studio→Blender bridge route).
3. Add a row to `art/assets.json` if the asset is new.
4. Build:

```bash
powershell -File art\build_sprites.ps1 -Sheet
```

5. Look at `art/renders/contact_sheet.png` at 100% zoom. Judge at **true
   in-game size**, never at 4×. A sprite that only reads when magnified does
   not work.

Single asset while iterating:

```bash
powershell -File art\build_sprites.ps1 -Only chest
```

### The manifest

```json
{
  "name": "smelter",      // source is art/source/smelter.glb
  "footprint": 2,          // tiles per side
  "inset": 0.92,           // fraction of footprint the model fills
  "max_height": 0,         // tile cap on height; 0 = uncapped
  "states": ["idle", "smelting"],
  "yaws": []               // [0,90,180,270] for 4-way buildings
}
```

`inset` is the deliberate gap between a building and its tile edge. 0.92 gives
a small breathing margin. The power pole uses **0.55** with `max_height: 3.0`,
because a pole that fills its tile horizontally looks like a tower — thin
things need a smaller inset and a height cap instead.

---

## 3. Scale normalization

Tripo returns models at arbitrary scale, arbitrary origin, arbitrary
orientation. `render_asset.py` normalizes every import identically:

1. Import the GLB; discard any camera or light that came with it.
2. Parent everything to one empty, so normalization is a single transform.
3. Measure the world-space bounding box of the mesh data.
4. Compute one uniform scale so the **larger horizontal dimension** equals
   `footprint × inset` tiles. If that would exceed `max_height`, scale to the
   height cap instead.
5. Translate so the footprint centre is at the world origin and the **base sits
   on Z = 0** — buildings stand on the ground, they do not float or sink.

Only uniform scale is ever applied. Non-uniform scaling would make one asset's
proportions disagree with the rest, which is exactly the drift this pipeline
exists to prevent.

### Framing and the anchor sidecar

After normalization the silhouette is measured **in camera space** and the
canvas is grown to a whole number of tiles around it. A 1×1 building does not
produce a 32×32 sprite: rotated 45°, a one-tile box is about 1.41 tiles wide,
and the pitch adds height on top. The chest lands on a 64×64 canvas.

So the sprite cannot simply be centred on the tile. Every sprite gets a JSON
sidecar:

```json
{
  "name": "power_pole",
  "footprint_tiles": 1.0,
  "canvas_tiles": 3,
  "sprite_px": 96,
  "anchor_px_from_center": [0.0, 24.61]
}
```

`anchor_px_from_center` is where the building's **footprint centre** sits
relative to the sprite's centre, in final sprite pixels, +y downward. Godot
places the sprite so that `sprite_centre + anchor` lands on the tile centre.
The power pole's anchor is ~24 px below centre because the pole overflows
upward — which is exactly how a tall object should sit on its tile.

This mechanism is what makes vertical overflow work in general, and most of the
remaining buildings will need it.

---

## 4. Visual states

A state is **not a second generation**. One mesh is rendered more than once
with a material/light delta applied at render time by a hook in
`art/blender/states/<asset>_<state>.py`, invoked via `--extra-py`.

`smelter_smelting.py` sets emission on any material whose name contains
`firebrick`/`mouth`/`furnace` and adds a warm point light in front of the
furnace mouth so the glow spills onto the hull.

Two reasons this beats generating an "idle smelter" and a "smelting smelter":

- **Registration.** Both states go through identical normalization and framing,
  so they are pixel-aligned by construction — verified: `smelter_idle` and
  `smelter_smelting` share canvas `96×96` and anchor `[-0.35, 11.61]`. Two
  separate Tripo generations would differ in shape and the building would
  visibly jump when it started smelting.
- **Cost.** A state is a ~10-line hook, not a generation.

**Tuning note, learned the hard way.** The first smelting pass used emission
strength 12 and a 60 W spill light. At 4× it looked like glowing metal; after
downsampling to 32 px it clipped to a pure white rectangle that read as a *hole*
in the sprite. Tuned down to strength 3 / 18 W. **Judge every state at true
in-game size** — bright emissive detail is the first thing the downsample
destroys.

---

## 5. Rotation — settled: render four times

**Answer: four renders with the model rotated. Do not rotate the sprite in Godot.**

This was tested rather than assumed. `rotation_test.py` renders a deliberately
asymmetric block (yellow nose pointing −Y, blue fin offset on top) at yaw
0/90/180/270 and compares it against the same sprite rotated 90/180/270 in 2D,
as an engine transform would. See `art/renders/rotation_test.png` — top row is
true 3D renders, bottom row is the 2D rotation.

The 2D row fails in two ways that are obvious side by side:

1. **Lighting rotates with the object.** The baked key light is supposed to
   come from a fixed screen direction. Rotate the sprite and the lit face swings
   round with it, so a rotated building disagrees with every neighbour about
   where the sun is.
2. **Gravity rotates with the object.** The projection bakes in a specific view
   direction; spinning it in 2D tips the object over. The bottom row reads as a
   building lying on its side, not one facing a different way.

Four renders cost four Cycles renders — seconds, and only for the subset of
buildings that actually rotate. The manifest handles it:

```json
{ "name": "inserter", "footprint": 1, "yaws": [0, 90, 180, 270] }
```

producing `inserter_d0.png` … `inserter_d270.png`.

---

## 6. Moving parts — settled: pose in 3D, render the assembly per frame

**Recommendation: generate the moving part as a separate Tripo model, pose it
in Blender, and render the whole assembly once per frame.** Use
`render_animated.py`. Do not draw the moving part programmatically, and do not
alpha-composite a part sprite over a body sprite.

The three candidate approaches, and what testing showed:

**(a) Keep drawing the moving part programmatically in GDScript.** Tempting,
because the arm-swing interpolation already exists and works. Rejected: a flat
programmatic rectangle next to a 3D-rendered, textured, three-point-lit body is
precisely the visual incoherence this whole pipeline exists to eliminate. The
arm is not a minor detail on an inserter — it is the part the player watches.

**(b) Render body and part as separate sprites, composite in Godot.** Tested in
`moving_parts_test.py` (see `art/renders/moving_parts_test.png`). It registers
perfectly — all frames share one canvas and a `[0,0]` anchor — but it is
**wrong at rear-facing angles**: alpha compositing can only ever draw the arm
*in front of* the body, so when the arm swings behind the housing it floats over
it instead of being occluded. Compare against
`art/renders/inserter_frames.png`, where at 45° the arm is correctly hidden
behind the housing. Depth ordering cannot be recovered from two flat layers.

**(c) Pose in 3D, render the assembly per frame. ← chosen.** Occlusion,
contact shading, and the arm's shadow on the body all come out correct for
free, because it is a real render of a real 3D arrangement.

Cost is modest and bounded: one extra Tripo generation per animated building
(the part), then N renders. `art/assets.json` lists five frames for the
inserter; the existing swing interpolation stays exactly as it is and simply
selects a frame index instead of computing a draw transform.

The one requirement this places on the source art: **the moving part's pivot
must be at the world origin** when exported, because `render_animated.py` spins
it about world Z. That is documented in `art/source/README.md`.

Frame sets, rotation sets, and state pairs all share a further rule enforced by
`--canvas-tiles` / `--center-on-origin`: **a multi-frame set must share one
canvas and one origin.** Auto-fitting each frame to its own silhouette would
silently re-centre every frame and the animation would jitter.

---

## 7. Output conventions

| Path | Contents |
|---|---|
| `art/sprites/<name>.png` | 32 px/tile sprite — what the game loads |
| `art/sprites/<name>.json` | canvas size, footprint, anchor |
| `art/sprites/<name>_<state>.png` | one per visual state |
| `art/sprites/<name>_d<yaw>.png` | one per facing, 4-way buildings |
| `art/sprites/<name>_f<deg>.png` | animation frames |
| `art/sprites/<name>_frames.json` | frame list + shared anchor |
| `art/renders/<name>_4x.png` | 128 px/tile master, kept for re-downsampling |
| `art/renders/contact_sheet.png` | the coherence check |

---

## 8. Reproducing from nothing

```bash
# 1. rebuild the locked template
blender -b -P art/blender/build_template.py

# 2. (optional) proxy GLBs, to exercise the pipeline with no Tripo assets
blender -b -P art/blender/make_proxies.py -- --out-dir art/source

# 3. render everything in the manifest
powershell -File art\build_sprites.ps1 -Sheet

# 4. re-run the two design experiments
blender -b -P art/blender/rotation_test.py
blender -b -P art/blender/moving_parts_test.py
```

Blender is expected at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`;
override with `-Blender <path>`.

### Two environment gotchas, both already worked around in `build_sprites.ps1`

- The installed **Tripo3d Blender Bridge** add-on logs to stderr on every
  headless launch. With `2>&1` and `$ErrorActionPreference = "Stop"`, that
  benign line becomes a fatal `NativeCommandError`. The script uses
  `"Continue"` and detects success by looking for a marker in stdout.
- `@($null)` unrolls to plain `$null` on assignment in PowerShell, and
  `foreach ($x in $null)` iterates **zero** times — which silently skipped
  every asset that had no states and no rotations. The script uses an
  empty-string sentinel instead.

---

## 9. Status

The pipeline is proven end to end on proxy geometry covering all three Session 1
failure modes (1×1, 2×2 with states, tall-and-thin), plus rotation and
animation. **The consistency verdict on real Tripo output is still outstanding**
— see the session report. Proxies were authored in one script with a shared
material set, so their coherence proves the *renderer* is deterministic and
proves nothing about Tripo's style drift. That verdict requires the three real
assets.
