# Stewardship art pipeline — Tripo → Blender → sprite

How a building goes from a prompt to a PNG the game can draw. Reproducible by
someone who was not here.

Nothing here touches Godot. This pipeline emits PNGs and JSON sidecars; the
sprite-loading layer is a separate session.

## How to read this document

**Sections 0–13 are the pipeline as it stands.** Read those to run an asset.
They are kept current; if one contradicts a later section, the later section
wins and says so.

**Sections 14–31 are the record**, in the order things were decided, including
the things we got wrong and how they were caught. They are not a tutorial and
several reach conclusions that a later section overturns — every such section
carries a SUPERSEDED line at its top pointing forward. They are kept rather
than deleted because most of them exist to stop a future session re-making a
decision that was already paid for.

If you only read three of them, read **§22** (why the gate is the eye and not a
metric), **§25** (why the rig stays locked), and **§30** (why a small accent
needs the nearest-texel rescue).

**The shortest path to a working asset** is §3, with §0 for the constants and
§12 for the tripwires that have actually bitten.

---

## 0. The lock

Every constant lives in [`art/blender/lock.py`](blender/lock.py) and is hashed
into a **lock stamp** written into every asset's metadata JSON. A sprite
rendered under a changed camera is therefore detectable rather than silently
wrong.

Current stamp: **`434c0cf56d8f`**

| Constant | Value |
|---|---|
| Projection | Orthographic |
| **Camera azimuth** | **0°** |
| **Camera pitch** | **60° above the ground plane** (30° from vertical) |
| `GROUND_SQUASH` = sin 60° | 0.86603 |
| `WALL_RATIO` = 1/tan 60° | 0.57735 |
| Tile | 1 Blender unit = 1 tile = 32 px |
| Supersample | 4× (a 1×1 cell renders 128×111) |
| Engine | Cycles, CPU, 96 samples |
| View transform / look | `Standard` / `None` |
| Film | Transparent |
| Key light | elev 50°, plan 135°, energy 3.2, sun angle 8° |
| Fill light | elev 25°, plan 300°, energy 0.85, cool |
| Rim light | elev 55°, plan 330°, energy 1.15, cool |
| World ambient | `#6B7891`-ish at 0.22 |
| Frame pad | 0.04 tiles |
| Footprint fill | 0.92 |
| Roughness clamp | [0.34, 0.86] |
| Metallic ceiling | 0.55 |
| Emission ceiling | 2.5 |

**Why azimuth 0.** At 45° a square ground tile projects to a diamond — that is
isometric. Factorio's ground grid is axis-aligned squares, and the existing
`draw_one()` code draws axis-aligned rects on a square grid. A 45° render
would not sit on that grid.

**Why pitch 60.** A 1-tile-tall wall reads as 0.577 tiles of screen height —
the shallow 3/4 factory-game proportion — while a ground tile still reads as a
square after the anamorphic correction below.

**Why `Standard`, not AgX.** AgX desaturates and rolls off highlights for
filmic realism. At 32 px that is washed-out mud. Keep light energies below
clipping instead of relying on a tone curve.

**Why the rig is fixed.** Every sprite is lit from the same screen direction,
so assets placed side by side agree about where the sun is. That agreement is
most of what makes independently generated assets read as one game.

---

## 1. The anamorphic correction, and the trap

A horizontal 1×1 tile projects to 1 wide × 0.866 tall. Left alone every sprite
footprint is a squashed rectangle that will not sit on a square tile.

**`render.pixel_aspect_y` does not work for this.** Blender ignores pixel
aspect when framing an orthographic camera: renders at `pixel_aspect_y = 0.866`
and `= 1.0` come back byte-identical, because with square pixels the camera
frame aspect is forced to equal the resolution aspect.

The correction that works — bake the squash into the render height, undo it in
the downsample:

```
render_px_x = cell_w_tiles * 32 * 4
render_px_y = round(cell_h_tiles * 32 * 4 * 0.86603)
sprite_px   = (cell_w_tiles * 32, cell_h_tiles * 32)
camera.sensor_fit = 'HORIZONTAL'
camera.ortho_scale = cell_w_tiles
```

The LANCZOS resample to `sprite_px` applies the vertical stretch in the same
pass, so the image is filtered exactly once.

**Verify, never trust.** [`verify_calibration.py`](blender/verify_calibration.py)
renders an emissive 1×1 ground plane and measures its opaque bounding box after
downsample. It must come back exactly 32×32.

```bash
powershell -ExecutionPolicy Bypass -File art\build.ps1 -Calibrate
```

Re-run it after any change to the camera or the lock. It currently passes.

---

## 2. Layout

```
art/
  template.blend           THE locked scene (generated, never hand-edited)
  assets.json              manifest: one row per building
  build.ps1                the one command
  PROMPTS.md               prompt template + art direction + Tripo settings
  PIPELINE.md              this file
  source/                  YOUR Tripo GLBs (see source/README.md)
  sprites/                 OUTPUT: final PNGs + metadata JSON
  renders/                 OUTPUT: 4x masters, turnarounds, verdict sheets
  blender/
    lock.py                every locked constant + the lock stamp
    make_template.py       regenerates template.blend
    verify_calibration.py  the 32x32 camera check
    normalize.py           import, normalize, material clamp, framing
    render_asset.py        one asset -> master PNG(s) + metadata
    turnaround.py          8-way sheet, to read yaw_correction off
    analyze_mesh.py        structural report on a Tripo mesh
    dump_texture.py        extract basecolour/normal/rm to PNG for measurement
    make_proxies.py        stand-in geometry for testing without Tripo
    render_rigonly.py      flat-albedo render: the rig's shading, alone
    render_shadow.py       contact shadow as its own transparent layer
    rig_study.py           measures key:fill vs form-driven lightness; changes nothing
    palette_swatch.py      a palette on flat proxies, no Tripo, no correction
    states/                per-state material/light hooks
  tools/                   system Python (needs Pillow + numpy)
    downsample.py          premultiplied LANCZOS downsample
    sheet.py               contact sheets on neutral mid-grey
    rotation_test.py       the 4-renders-vs-2D-rotation comparison
    keymask.py             validates the magenta emission mask on a real texture
    palette_drift.py       measures Tripo's palette shift; emits the albedo gain
    glow_layer.py          extracts the fire as a separate additive layer
    overhang.py            containment: lateral appendages past the body block
    detail_density.py      HF gate + feature/thickness diagnostics
    assert_states.py       tripwire: declared states must actually differ
    assert_palette_era.py  gate: every real asset on the locked palette era
    assert_rig_correlation.py  gate: baked light must not oppose the rig
    baked_shading.py       albedo variance by spatial scale (see section 15)
    hf_regions.py          WHERE an asset spends its HF: by region and by stripe orientation
    eye_sheet.py           THE GATE: sprite at true size beside a reference, no metrics
    make_calibration.py    builds the permanent synthetic HF floor (blender/)
    palette_board.py       renders a palette on flat proxies, no correction
```

`template.blend` is generated from code, so the lock lives in a reviewable
diff rather than inside a binary:

```bash
blender -b -P art/blender/make_template.py
```

---

## 3. The everyday loop

1. Write the prompt from [`PROMPTS.md`](PROMPTS.md); generate in Tripo.
2. Put the GLB at `art/source/<name>.glb`.
3. Run the turnaround and **read** the facing off it — never guess:
   ```bash
   blender -b art/template.blend -P art/blender/turnaround.py -- \
       --glb art/source/smelter.glb --name smelter --footprint 2
   python art/tools/sheet.py --out art/renders/smelter_turnaround.png --label \
       art/renders/turnaround/smelter_yaw*_4x.png
   ```
4. Put that angle into `assets.json` as `yaw_correction`, with the rest of the row.
5. Build:
   ```bash
   powershell -ExecutionPolicy Bypass -File art\build.ps1 -Sheet
   ```
6. Measure the palette drift and write the anchors into the manifest. This is
   **per generation** — Tripo's shift is not consistent between them, so it
   cannot be fixed by prompting and a previous version's anchors are wrong:
   ```bash
   blender -b -P art/blender/dump_texture.py -- --glb art/source/smelter.glb --out-dir art/renders/tex
   python art/tools/palette_drift.py art/renders/tex/smelter_basecolor.png --emit smelter --members fieldstone,wrought_iron,weathered_oak,leather
   ```
   Read the output. A **DROP** means that member got no correction; a
   **RESCUED** line means it was too small to win a centroid and was recovered
   per-texel (§30). `art/tools/remap_audit.py <name>` says which anchor every
   cluster actually inherited, if you need to ask why a region looks wrong.
7. **The gate.** Judge these two, at 100%, never at 4×:
   ```bash
   python art/tools/eye_sheet.py --asset smelter_idle --shadow
   python art/tools/eye_sheet.py --asset smelter_idle --silhouette
   ```
   The eye sheet is the finished sprite at the size a player sees it, beside an
   approved asset. The silhouette is the outline alone. **If the outline does
   not say what the building is, the asset fails however good its interior
   looks** — a pole passed four reviews because every one of them looked at a
   4× master. See §22, §23, §26.
8. On approval, set `"albedo_pinned": true` on the manifest row. `--emit` will
   then refuse to overwrite it. Pin means *requires explicit re-approval*, not
   *frozen forever*: a pipeline improvement applies to every asset, and every
   affected approval gets re-reviewed.

Useful flags: `-Only <name>`, `-Calibrate`, `-NoMaterialNorm`.

### The manifest

```json
{
  "name": "power_pole",
  "source": "power_pole.glb",
  "footprint": 1,
  "fit": "height",
  "height_tiles": 2.6,
  "yaw_correction": 0,
  "states": { "idle": null, "smelting": "smelter_smelting.py" },
  "yaws": [],
  "status": "real"
}
```

`fit` matters more than it looks. `footprint` scales the XY extent to fill the
footprint; `height` scales Z to `height_tiles`. **Tall thin assets must use
`height`** — a pole's footprint carries no usable scale signal, and fitting to
it makes the pole enormous.

---

## 4. Import and normalization

### The import trap that costs an hour

The glTF importer leaves objects with `rotation_mode = 'QUATERNION'`. Writing
`rotation_euler` on such an object is **silently discarded** — the matrix is
driven by `rotation_quaternion` instead. Every Tripo mesh arrives this way, and
the failure reports no error: an 8-way turnaround renders eight identical
images. `import_glb()` forces `'XYZ'` before anything touches a rotation.

### Order of operations

1. Force euler rotation mode; drop any camera or light that came with the file.
2. Yaw by the per-asset `yaw_correction` so the front faces **−Y** (toward camera).
3. Uniform scale, by `fit`. Uniform only — non-uniform scale would make this
   asset's proportions disagree with every other asset.
4. Centre on the footprint centre in XY; sit `bbox.min.z` on the ground.

Bounds are measured with `foreach_get` into numpy. A 1.95M-triangle mesh
iterated in pure Python takes minutes; this takes milliseconds.

### Material normalization

Tripo bakes lighting into base colour and returns PBR chosen by nobody. The
pass clamps roughness into [0.34, 0.86], metallic to ≤ 0.55, emission to ≤ 2.5,
with an optional HSV correction before Base Color. Toggle with
`-NoMaterialNorm` so its effect can be measured.

**A trap here too.** Tripo ships roughness *and* metallic as a packed `_rm`
texture, so those sockets are **linked** and their `default_value` is ignored —
clamping the scalar does nothing at all. The clamp is inserted into the node
chain instead: a clamped Map Range for the roughness band, a Math `MINIMUM` for
the metallic ceiling (a Map Range would compress the span rather than clamp it).

Measured on the real kiln, pass on vs off: mean 0.41% per-channel change, max
9/255, concentrated in the brightest 20% of pixels (2.09/255 vs 0.80/255
elsewhere). It is correctly active but small on this asset — Tripo's `rm` map
happened to be reasonable. Its cross-asset value cannot be judged from one
asset.

### 4b. Palette drift — Tripo shifts the whole palette, and not consistently

```bash
blender -b -P art/blender/dump_texture.py -- --glb art/source/<n>.glb --out-dir art/renders/tex
python art/tools/palette_drift.py art/renders/tex/<n>_basecolor.png [more...]
```

The magenta mask came back at roughly half brightness (`#FF00FF` → `#9D009A`),
which raised the obvious question: was the stone, oak, iron and leather shifted
too? **Yes.** Measured on the approved smelter's albedo, matching clusters to
palette members by *chromaticity* (stable under a value shift) rather than by
absolute colour:

| member | locked | observed | luminance ratio |
|---|---|---|---|
| fieldstone | `#5A5E58` | `#4C4D46` | 0.667 |
| fired clay | `#8A6A4F` | `#443424` | 0.229 |
| weathered oak | `#6B4E32` | `#584732` | 0.750 |
| wrought iron | `#46504E` | `#3F3F38` | 0.643 |
| leather | `#7A5A42` | `#503F2C` | 0.443 |
| forge brown | `#8C4A32` | `#614F39` | 0.658 |

Best single per-channel gain **R 0.417 / G 0.535 / B 0.530**, explaining 67% of
the error. The magenta's own ratio is 0.330 — the same phenomenon, hit somewhat
harder, as saturated extremes tend to be.

**And it is not systematic.** Running the same measurement on the first kiln —
a second generation — gives gain **R 0.989 / G 1.268 / B 1.167**: near unity,
even slightly bright. Gain spread across the two generations is **0.57–0.73 per
channel**, enormous.

> **Caveat, stated plainly.** The two generations differ in modality as well as
> content — the first kiln was text-to-3D, the approved smelter image-to-3D —
> so this is strong evidence rather than a controlled experiment. The chest and
> the power pole come through the *same* flow as the smelter and will settle it
> definitively. The harness runs on them automatically.

**Consequence: the material pass must own value and exposure.** Prompting
cannot deliver cross-asset colour consistency when the transform varies per
generation. The correction is stored per asset in the manifest and applied in
normalization, in one of two modes.

### Global gain vs per-cluster remap — measured, remap wins

A single gain explains only ~67% of the drift. The residual is per-material and
large: on the smelter, fired clay sits at 0.229 luminance against weathered oak
at 0.750 — a **3.3× spread inside one asset**. No global gain can touch that, so
a clay-heavy chest would still not match an oak-heavy smelter.

`apply_albedo_remap()` gives each trusted cluster its own per-channel gain
(`target / observed`) and corrects a texel by the gaussian-weighted blend of the
anchors nearest it in colour space.

**Multiplicative, not additive, deliberately.** An additive shift moves each
cluster's mean onto target but lifts blacks with it, washing out shading. A
gain preserves every texel's ratio to its cluster mean — within-cluster
variation survives intact, shadows stay dark — and it degenerates exactly to the
global gain when the anchors agree.

Measured in render space, per-member |delta| against the locked palette:

| member | global gain | per-cluster remap |
|---|---|---|
| fieldstone | 0.1045 (lum 0.424) | **0.0053** (lum 0.971) |
| weathered oak | 0.1870 (lum **2.197**) | **0.0259** (lum 1.007) |
| fired clay | 0.1094 | 0.0938 |
| wrought iron | 0.0324 | 0.0439 |
| leather | 0.0441 | 0.0516 |
| **RMS** | **0.0675** | **0.0559** |

The remap fixes the two worst members outright and costs a little on two small
ones. Note what the global gain was doing to the timber: **overshooting oak to
2.197× luminance** — that is exactly the per-material residual a single gain
cannot see.

**It does not flatten.** Detail survives in both — the HF gate actually reads
*lower* under the remap (see below), which is what you would expect when the
correction stops over-brightening one material.

Two safeguards, both measured rather than assumed:

- **Untrusted anchors are dropped.** `forge_brown` matched at chroma distance
  0.279; a confident-looking gain built on a bad match shifts hues wherever it
  applies. Anything above 0.15 is discarded (5 of 6 anchors survive here).
- **Gains are clamped to [0.4, 2.5].** Fired clay wanted **4.4×**, which
  amplifies compression noise and clips highlights. Clamping trades exact
  mean-matching for not destroying the texture.

### Not locked until n = 3

The correction stays **per-asset and measured**. The two generations compared
above differ in modality as well as content, so "varies per generation" is
strong evidence, not a controlled result. The chest and the pole come through
the *identical* flow as the approved smelter — those are the control. Only when
all three are in do we decide whether a shared constant exists.

```json
"albedo_gain": [0.417, 0.535, 0.530],
"albedo_correction": "remap",
"albedo_remap": { "sigma": 0.02, "anchors": [ ... ] }
```

The goal is not to hit the locked hexes exactly — albedo is not a lit
appearance — but to put every asset through the **same transform to a common
reference**, which is what consistency actually requires. Verified on the
smelter: render-space gain moved from **R 0.378 / G 0.518 / B 0.469** to
**R 0.781 / G 0.854 / B 0.785** — near-neutral, and the channels now agree with
each other, so the colour cast is gone. The residual ~0.8 is the lighting rig,
which is locked and therefore common to every asset.

Albedo is clamped to 1.0 after correction; values above that are unphysical and
blow out. The correction is skipped by `-NoMaterialNorm`, so its effect stays
measurable.

---

## 5. Framing and the Godot contract

The cell is a whole number of tiles, centred on the footprint's X centre, with
its **bottom edge on the footprint's front edge** — so tall silhouettes
overflow upward only.

Screen projection, pre-stretch: `u = x`, `v = sin(60°)·y + cos(60°)·z`.

Each asset emits `art/sprites/<name>.json`:

```json
{
  "cell_tiles": [2, 3],
  "sprite_px": [64, 96],
  "anchor_px": [32.0, 96.0],
  "lock_stamp": "434c0cf56d8f"
}
```

`anchor_px` is the pixel offset from the sprite's top-left to the footprint's
**bottom-centre**. Godot draws at `footprint_bottom_centre − anchor_px`. One
anchor, one rule, and it works for a chest and a pole alike.

For a 4-way asset the cell is **unioned across all four facings**, so Godot
carries one anchor per building rather than four.

### The pad that buys a whole tile

`FRAME_PAD_TILES` is 0.04, not 0.10. At 0.10 the pad alone pushed a 1×1 chest
into a 2-tile-wide cell — a free extra 32 px of nothing.

Worse, `FOOTPRINT_FILL 0.92 + 2 × 0.04` is **exactly 1.000 tiles**, so float
noise alone decided whether `ceil()` returned 1 or 2. It returned 2, and the
chest rendered 64 px wide for no reason. `frame()` now uses a tolerance of
1e-4 tiles — far below one pixel, far above float noise. The chest is 32×64.

---

## 6. Downsampling — premultiply or get halos

Blender writes PNG with **straight (unassociated)** alpha, where fully
transparent pixels are black. Resizing that bleeds black into every silhouette
edge and each sprite picks up a dark fringe.

`downsample.py` premultiplies → resizes (LANCZOS) → unpremultiplies. This is
the single difference between crisp and muddy at 32 px, and it is why the
downsample lives in system Python with Pillow rather than in Blender.

---

## 6a. Containment — the overhang measurement

```bash
python art/tools/overhang.py smelter_idle --flag-pct 10
```

An appendage steals scale from the building it hangs off. The tool takes the
per-column opaque-height profile of the 4× master, walks outward from the
tallest column, and finds the first **notch** — a column below 35% of the
body's median height. Anything past the notch is an appendage.

Height alone cannot find it: the smelter's bellows is a *tall* leather panel
reaching 187 px against a body of 267 px, so a height threshold keeps it inside
the body. The notch is the real signal.

| asset | overhang | verdict |
|---|---|---|
| first kiln (rejected) | 38% of silhouette | outrigger |
| **approved smelter** — bellows, left | **10.2%** (24 px past the notch at x=34) | **flagged, marginal** |
| approved smelter, right | 0.4% | ok |
| chest (proxy) | 1.7% each side | ok |
| power_pole (proxy) | 18.5% each side | flagged — but see below |

The pole's flag is the metric working as designed on a shape it was not meant
for: a crossarm on a thin post *is* mostly overhang. Containment is a rule for
**block-form buildings**; a pole is judged on `fit: height` instead.

---

## 6b. Detail-density conformance

Two numbers, both from `art/tools/detail_density.py`. Conformance is judged per
asset against the budget; it does not need the other assets to exist.

```bash
python art/tools/detail_density.py smelter_idle chest power_pole
```

### The gate is ONE number

**High-frequency destruction, as a ratio against the flat-geometry floor. Cap 3×.**

Rendering at 4× and downsampling cannot carry any spatial frequency above one
quarter of the master's Nyquist limit; the tool measures the 4× master's power
spectrum and reports the AC energy above that cutoff. The floor is the mean of
the flat untextured proxies, so the budget recalibrates itself instead of being
a magic percentage.

It needs no special-casing for shape, and it measures the thing actually cared
about — whether the detail reaches the screen — rather than a proxy for it.

Measured (floor = **2.35%**, budget = 7.1%):

| asset | HF destroyed | ratio | gate |
|---|---|---|---|
| first kiln (rejected) | 14.3% | 6.1× | **FAIL** |
| **approved smelter** | **6.1%** | **2.60×** | **PASS** |
| chest (proxy) | 2.1% | 0.89× | pass |
| power_pole (proxy) | 2.6% | 1.11× | pass |

The smelter moved from 2.21× to 2.60× when the albedo correction went in
(see §4b) — a brighter albedo carries more contrast, so more energy sits in the
high bands. Still comfortably inside the cap, but worth knowing that the
correction spends some of the detail budget.

### Diagnostics — reported, never enforced

**Feature count per occupied tile.** Divided by opaque area ÷ 32², not
footprint area. That is the right denominator, but it does **not** rescue thin
objects — the flat pole proxy scores *worse* under it (11.0 → 17.8) because it
occupies only 0.62 tile-equivalents. A thin object is nearly all edge and no
normalization changes that, which is precisely why this is not a gate.

**Minimum feature thickness in FINAL pixels — this is PROMPT FEEDBACK, not a
gate, and it is not going to become one.** Anything under ~2 px at 32 px output
is dead regardless of the object's shape, so the number says whether the detail
budget in the prompt is realistic for that footprint at this camera.

Current: smelter median **1.15 px with 87% under 2 px**; chest 1.80 px with 67%
under. Read that as *the prompt's detail budget is still too generous for a 2×2
at this camera* — a thing to tighten in `PROMPTS.md` as the numbers accumulate
across assets, not a thing to fail a build on.

It is reported per asset every run and never enforced.

---

## 7. Visual states

A state is **never a second generation** — two generations would differ in
shape and the building would jump when it changed state. One mesh is rendered
more than once with a material/light delta from a hook in `blender/states/`.

For a fused single-material mesh, selecting in **texture space** is the only
handle available: the mesh has one material and its loose parts are meaningless
(see §9). So any region that should glow is painted flat `#FF00FF` in the
concept image, and Blender keys on that.

### Magenta is a mask, not a colour

`normalize.neutralize_mask()` runs on **every** asset in **every** state and
replaces the magenta with a dark cavity colour, handing back the mask socket.
The `smelting` hook reuses that same socket to drive emission. Two consequences
that matter:

- Magenta can never reach the screen. An idle firebox renders as a cold dark
  opening rather than a magenta rectangle.
- The lit region and the neutralized region are the same socket, so they cannot
  disagree.

Measured separation from the palette, linear RGB: nearest member (fired clay)
**1.194**, versus a widest-pair-inside-the-palette of 0.206 and the **0.079**
that killed the first attempt. The mask sits 15× clear of the failure
threshold; tolerance is 0.45 with roughly 0.6 of headroom.

**Why not just widen the palette.** The earlier fix added a saturated orange
`#FF5A18` so the key would separate. That makes a hot-looking colour
legitimately available to every *cold* asset in the set, which Tripo will drift
into — buying a working mask at the cost of palette discipline across twenty
buildings. The mask belongs outside the palette.

### What the first attempt taught us

Keying on the palette member `hot_iron #8C4A32` had no usable window at all:

| tolerance | texels matched |
|---|---|
| 0.340 | 99.83% (the entire model glows) |
| 0.079 | 4.50% (nearest non-heat palette colour) |
| 0.036 | 0.00% (nothing glows) |

and the texture held **0.000%** genuinely fiery texels — the concept image had
no lit firebox to bake.

### Validate before trusting — the harness

```bash
blender -b -P art/blender/dump_texture.py -- --glb art/source/<name>.glb --out-dir art/renders/tex
python art/tools/keymask.py art/renders/tex/<name>_basecolor.png
```

`keymask.py` prints the texel-distance histogram and passes only on a clean
bimodal gap: a spike near 0, a wide empty band, then the material bulk. The
plausible failure is JPEG ringing smearing texels continuously out of a hard
magenta edge — this is how we would see it, on asset 4 rather than asset 14.

Baseline on the current kiln (generated before the mask existed): **0.000%** of
texels within 0.6 of the key, 100% out beyond 1.2 — correctly reported as
`NO MASK PRESENT`.

### Live on the approved smelter — and two traps it exposed

The mask path is **on**. `glow_at` and the emitter fallback are gone from the
smelter. Two things had to be fixed to get there, both of which would have
silently produced a mask that never fires:

**Trap 1 — Tripo does not return the colour it was given.** The `#FF00FF`
panel came back as **`#9D009A`**, roughly half brightness, sitting 0.80–1.00
from the key. No absolute-distance tolerance works: wide enough to catch it
also caught 30% of the texture. So the mask is detected by **chroma**, not
colour: `score = min(R, B) − G`, which is invariant to the brightness shift.

**Trap 2 — the thresholds must be in LINEAR space.** An Image Texture node
outputs linear; the file is sRGB and Blender converts on read. Thresholds
derived from the sRGB values of the same texture are ~2× too high and the mask
never fires — which is exactly what happened on the first attempt.

Measured on the approved smelter, in linear:

| | linear chroma score |
|---|---|
| every palette member | −0.014 … −0.066 (all negative) |
| observed panel | **+0.323** |
| pure magenta | +1.000 |

### Two masks, not one

Neutralization and emission have different requirements, so they get different
cuts off the same score:

- **Neutralize generously** (normalized score > 0.13). Magenta bled onto the
  hearth stones is an artifact; removing it everywhere is correct. This uses
  the score divided by the brightest channel, which is genuinely
  brightness-invariant and so also catches the shaded dark panel edge Tripo
  adds despite "flat".
- **Emit tightly** (raw score > 0.16). A stone with a magenta tint must not
  glow. Measured: the cut admits **0.670%** of texels and excludes **0.425%**
  of spill.

A dark panel rim therefore ends up neutralized but unlit — which is what an
arch mouth edge should look like anyway. Residual tint in the idle render fell
from 759 px to **177 px** (median `#29181D`, a dark warm interior).

`keymask.py` verdict on this asset: **PASS** — panel population 0.670% of
texels with an empty band at score 0.442–1.050 separating it from the material
bulk.

---

## 7b. The glow ships as a separate layer

The fire is **not baked into the smelting sprite**. Godot draws the body
sprite, then a transparent glow layer on top with additive blending, and pulses
`modulate.a` for flicker — the Factorio "alive" read for zero animation frames.

```bash
python art/tools/glow_layer.py --name smelter --body idle --lit smelting
```

The layer is derived as `lit_render − body_render`, clamped at zero, on the 4×
masters in premultiplied space, then downsampled by the same premultiplied
LANCZOS path as everything else. That difference *is* the light the fire adds,
so it carries for free what a hand-painted glow could not: the spill onto the
surrounding stones, correct occlusion (both renders share geometry and camera),
and real falloff instead of a guessed gradient.

RGB stores the fire colour normalized to its brightest channel and A stores
intensity, so additive compositing reconstructs the lit render exactly:

```
dst += rgb * a
```

and scaling `a` dims the fire without shifting its hue. Verified: additive
recomposition against the baked smelting sprite differs by **0.60/255 mean**
(p99 12/255), with 3.5% of pixels off by more than 4/255 — all of them at the
antialiased rim.

| | |
|---|---|
| file | `art/sprites/smelter_glow.png` |
| body | `art/sprites/smelter_idle.png` |
| lit pixels | 174 (2.83% of the sprite) |
| bbox | `[24, 73, 43, 82]` |
| blend | additive; pulse `modulate.a` |

`smelter_smelting.png` is kept as the derivation input and a visual reference.
It is **not** a shipping sprite — shipping is body + glow layer.

---

## 8. Rotation — settled: four renders

Tested, not assumed. `art/renders/rotation_test.png`: top row is four true 3D
renders with the model rotated; bottom row is the `d0` sprite rotated 90/180/270
in 2D, as an engine transform would.

The 2D row fails in two ways that need no measurement to see:

1. **Gravity rotates with the sprite.** The projection bakes in a view
   direction; spinning it in 2D lays the kiln on its side with the chimney
   pointing sideways.
2. **Lighting rotates with the sprite.** The baked key swings around, so a
   rotated building disagrees with its neighbours about where the sun is.

Four renders cost four Cycles renders — seconds, and only for buildings that
actually rotate. Set `"yaws": [0, 90, 180, 270]`; the cell is unioned across
all four so Godot still carries one anchor.

---

## 9. Moving parts — recommendation

**Recommended: option 3 for the parts you already animate — keep drawing the
moving part programmatically — and option 1 only where the motion is a true
3D rotation.** Reasoning, with the measurements behind it.

**Option 2, splitting a fused mesh, is dead.** Measured on the real kiln via
`analyze_mesh.py`: the mesh separates into **705 loose parts**, the largest
spanning 0.659 tiles. They are surface fragments, not components. There is no
"the arm" to select, and there is only **one material**, so material-slot
selection is unavailable too. This is not a tuning problem; AI-generated meshes
are a soup of disconnected patches.

**Option 3 is the right default, and the brief's instinct is correct.** The
arm-swing interpolation already exists and works. Throwing away working code to
gain a sprite sequence is a bad trade, and the fill-bar cases (accumulator) are
pure overlay anyway — no geometry is involved at all. Keeping the programmatic
layer also keeps animation out of the asset budget entirely: no extra
generations, no frame sets, no sprite-sheet packing.

The cost is a visual seam: a flat drawn shape beside a textured, three-point-lit
render. Two things keep that acceptable, and both should be applied — sample
the body's own palette for the drawn part rather than using flat colour, and
keep drawn parts small relative to the body.

**Option 1 earns its cost only where the motion is genuinely 3D.** A water
wheel or windmill sail rotates about an axis that, at 60° pitch, traces an
**ellipse** on screen, not a circle — no 2D transform reproduces it, and the
spokes self-occlude as they pass behind the hub. Those two buildings want a
short pre-rendered frame set: one extra generation for the moving part, exported
with **its pivot at the world origin**, rendered as a full assembly per frame.

**And that budget is far smaller than it sounds, because a rotationally
symmetric wheel repeats every 360/N degrees.** Render one period and loop it:

| Part | Symmetry | Travel needed | Frames |
|---|---|---|---|
| Water wheel | 8 spokes | **45°** | 12 |
| Windmill sails | 4 sails | **90°** | 16 |

**~28 frames for the entire animated set**, not hundreds. Everything else —
inserter arm, accumulator fill bar — stays programmatic and costs nothing.

Render the assembly, never composite two sprite layers: alpha compositing can
only draw the part *in front of* the body, so a spoke swinging behind the hub
would float over it. Depth ordering cannot be recovered from two flat layers.

Frame sets are out of scope for this session; `render_animated.py` from the
earlier draft was removed rather than left behind at the wrong camera angle.

---

## 10. Reproducing from nothing

```bash
blender -b -P art/blender/make_template.py                    # rebuild the lock
powershell -ExecutionPolicy Bypass -File art\build.ps1 -Calibrate
blender -b -P art/blender/make_proxies.py -- --out-dir art/source   # optional stand-ins
powershell -ExecutionPolicy Bypass -File art\build.ps1 -Sheet
python art/tools/rotation_test.py --name smelter_rot --out art/renders/rotation_test.png
```

Blender is expected at `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`
(override with `-Blender`). `art/tools/*` need system Python with Pillow and numpy.

### Environment gotchas already handled

- **PowerShell execution policy.** Scripts are blocked by default here; run
  `build.ps1` with `-ExecutionPolicy Bypass`.
- **Blender stderr.** The installed Tripo Blender Bridge add-on logs to stderr
  on every headless launch. With `2>&1` and `$ErrorActionPreference = "Stop"`
  that benign line becomes a fatal `NativeCommandError`. `build.ps1` uses
  `"Continue"` and detects success from stdout markers.
- **Blender 5.x** renamed `BLENDER_EEVEE_NEXT` back to `BLENDER_EEVEE`. The
  pipeline uses Cycles on CPU: a 128×111 render is well under a second and
  headless EEVEE needs a GPU context that is not available here.

---

## 11. Status — end of session 1

**Three real assets and a calibration fixture. No proxies.** The chest proxy is
retired; every asset in the set is now a real Tripo generation through the full
pipeline.

| Asset | Status | Pinned | Notes |
|---|---|---|---|
| `smelter` | **real, APPROVED** | yes | Reference asset. 2×2, idle + smelting, magenta firebox mask, all four declared members matched with zero drops. |
| `power_pole` | **real, APPROVED** | yes | v5, one-sided. 1×1 footprint, `fit: height` 2.6, cell 1×3. Weakest of the set — see below. |
| `chest` | **real, APPROVED** | yes | 1×1, `fit: footprint`, fill 0.90, cell 1×2, single state. **First 1×1 textured asset** and **first two-member asset**. Retires the proxy. |
| `_calib_floor` | calibration | n/a | Permanent synthetic HF floor, 1.00%. Committed, gitignore-exempt, **never regenerated** — regenerating moves the floor, which is the failure it exists to prevent. |

### The chest: what it exercised that nothing else had

**The 1×1 textured path.** It had only ever been walked by an untextured
placeholder, so every part of the pipeline downstream of a texture — palette
matching, the remap, the material clamps — was unproven at 1×1. It works. Rig
correlation +0.681 (strong), the highest in the set.

**The `K = 6 × members` rule at its low end.** The rule was fitted on a
four-member asset. The chest is the first two-member one, so K=12, the floor.
Result, from `art/tools/k_sweep.py`:

| K | trusted | oak gain (R) | iron gain (R) |
|---|---|---|---|
| 12 *(derived)* | 2/2 | 1.40 | **1.08** |
| 16 | 2/2 | 1.41 | **1.21** |
| 20 | 2/2 | 1.64 | 1.42 |
| 24 | 2/2 | 1.59 | 1.38 |
| 32 | 2/2 | 1.56 | 1.40 |
| 48 | 2/2 | 1.49 | 1.30 |
| 64 | 2/2 | 1.34 | 1.29 |

**`trusted` carries no signal at two members** — two declared members are
maximally separable, so the column is 2/2 everywhere including K=4. The
diagnostic that decided the rule at four members is blind at two.

The gains are not blind, and they say **K=12 is under-resolved**: iron reads
1.08 at the derived K against 1.29–1.42 for K≥20, and iron's chroma match
distance is 0.115 at K=12 against 0.120 at K=24 while oak's is 0.021. The
chest's texture is oak-dominated, so at 12 clusters the minority ironwork gets
too few centroids and its own is contaminated by dark oak.

**It was not raised, and the reason is measured, not assumed.** Rendering the
same asset at K=12 and K=24 and differencing the sprites: **mean 8-bit sRGB
delta 3.2, p95 5, max 8**. The ironwork is 17.5% brighter at K=24 in relative
terms, but these are dark values and the absolute difference is invisible at
32 px. Against that, raising `K_MIN` would change K for every asset with three
or fewer members — including the **approved and pinned** power pole (18 → 20) —
and force it back through the gate. An invisible correction is not worth an
approval.

Recorded as a known soft spot rather than fixed: **if a future two- or
three-member asset shows visible material disagreement, raise `K_MIN` first.**

### The chest's plan is rectangular, and here is what that costs

`fit: footprint` scales by the **larger** XY extent, so a non-square plan fills
the tile in its long axis and leaves a gap in the short one. Measured:

| | |
|---|---|
| Normalized extent | X 0.900, Y 0.581, Z 0.479 tiles |
| **Plan ratio X:Y** | **1.549 : 1** |
| Tile coverage | X 90.0%, Y 58.1% |
| Plan area covered | 52.3% of the tile, 64.5% of the 0.90 fill box |
| Gap along Y | 0.319 tiles = **10.2 px** at 32 px/tile |

Not a defect — Factorio's chests are rectangular too, and the sprite is
centred, so the gap is symmetric front and back. It is written down because it
becomes a habit across twenty buildings: **`footprint_fill` controls the long
axis only.** An asset whose plan ratio drifts past roughly 2:1 will start to
look lost in its tile, and the fix at that point is a rectangular footprint in
the manifest, not a larger fill.

| Check | State |
|---|---|
| Camera calibration | **PASS** — emissive 1×1 plane measures 32×32 |
| Lock stamp | `434c0cf56d8f`, written into every asset's metadata |
| Emission mask (magenta) | **live on a real generation** (smelter firebox), not just analytic |
| Glow | ships as a separate additive layer; the `glow_at` emitter fallback is retired |
| Shadow | separate layer, composite strength `lock.SHADOW_STRENGTH` = 0.4 |
| Palette era | `natural-5`; build FAILS on mismatch |
| HF destruction | **diagnostic, not a gate** (§22). Cap 3× the synthetic floor. |
| The gate | the 32 px sprite and its silhouette, judged by eye (§22, §26) |

### The consistency verdict — three real assets, no proxies

[`renders/consistency_1x.png`](renders/consistency_1x.png): chest, smelter
idle, smelter smelting, power pole, all at true 32 px on mid-grey with shadow
0.4. This is the first time the verdict can honestly exist.

**They read as one game.** All three sit under the same locked camera and rig,
all land on `natural-5` after per-cluster correction, and they agree about
material, weight and where the sun is.

**With one measured disagreement, and it is the pole.** Mean rendered
luminance of the weathered-oak pixels in each sprite:

| Asset | oak px | mean luminance | vs smelter |
|---|---|---|---|
| `smelter` | 876 | 0.0992 | 1.00× |
| `chest` | 597 | 0.1137 | 1.15× |
| `power_pole` | 364 | 0.0326 | **0.33×** |

Smelter and chest agree within 15%, which is close. The pole's oak renders
**three times darker** than either.

It is not the correction. In *albedo* the pole's oak is the **brightest** of
the three (population-weighted corrected luminance 0.196, against 0.105 for the
chest and 0.085 for the smelter). Brighter albedo arriving darker on screen
means the loss is entirely **form**: the pole is almost all vertical surface,
and a fixed key at 50° elevation puts far less light on a vertical face than on
the lids and tops that dominate the chest and smelter.

That is the form-driven lightness accepted in **§25**, where the rig was
measured and deliberately left locked. Three assets is the first sample large
enough to show its size, and 0.33× is larger than that decision anticipated.
It is not re-opened here — the trade was argued and settled — but it is the
single number most worth re-checking at five assets. If tall vertical assets
keep landing near a third of the set's mean, the decision deserves re-litigating
with better evidence than two probes.

### Hue agreement — and this is where the verdict is NOT clean

The luminance table above passed the smelter and chest within 15% while the
sheet plainly showed one timber reading salmon and the other mid brown. **A
luminance-only check is blind to the drift most visible when assets sit side by
side**: value differences read as lighting, hue differences read as different
materials. `art/tools/hue_agreement.py` applies the instrument already used
inside one asset — chromaticity, stable under a value shift — across assets.

Rendered chromaticity, `weathered_oak`, present in all three:

| Asset | rendered chromaticity | px |
|---|---|---|
| target | (0.576, 0.299, 0.125) | — |
| `smelter` | (0.540, 0.281, 0.180) | 836 |
| `chest` | (0.512, 0.312, 0.176) | 597 |
| `power_pole` | (0.466, 0.321, 0.214) | 364 |

**Spread 0.090.** `wrought_iron` spreads 0.053 across the same three. Both are
well past the 0.030 at which two samples stop looking like one material.

First, what the salmon is **not**. The smelter declares `leather` (`#7A4438`),
a legitimately red-brown member, and the obvious hypothesis was that the corner
posts are leather rather than drifted oak. They are not: the reddest 20% of the
smelter's warm pixels sit at chromaticity (0.558, 0.273, 0.170), which is 0.055
from oak and 0.137 from leather. Leather is 9.2% of the texture and corrects
almost perfectly (0.017 from target, the best in the set) but contributes **no**
classified sprite pixels — it is not visible from this camera. The salmon posts
are oak.

### The answer is (a): the CORRECTION, and it is systematic

Pairwise disagreement between assets, at each stage of the chain:

| Pair | raw texture | after remap | rendered | effect of correction |
|---|---|---|---|---|
| smelter vs chest | 0.0242 | 0.0593 | 0.0420 | **widens ×2.45** |
| smelter vs pole | 0.0616 | 0.1117 | 0.0907 | **widens ×1.81** |
| chest vs pole | 0.0832 | 0.0601 | 0.0603 | narrows ×0.72 |

And distance from the locked target, per asset:

| Asset | raw → target | corrected → target | gain skew |
|---|---|---|---|
| `smelter` | 0.0310 | 0.0326 **further** | 1.46 |
| `chest` | **0.0094** | 0.0292 **further** | 1.17 |
| `power_pole` | 0.0863 | 0.0876 **further** | 4.01 |

**The remap moves every asset's oak further from target in hue. Every one.**
The chest's raw oak was nearly perfect at 0.0094 and the correction pushed it
to 0.0292 — three times worse. The smelter and chest agree to 0.024 in the raw
Tripo texture and the remap pushes them apart to 0.059.

Not (b) rig: the rig's effect is common-mode. It lifts B by roughly 0.05 on all
three alike, so it moves the whole set together and cannot explain a
disagreement *between* assets. Not (c) source: raw smelter-vs-chest is 0.024,
which is agreement, not drift.

**The mechanism is in the design of the anchor.** A per-channel multiplicative
gain is hue-preserving only when its three channel gains are equal. The anchor
solves `gain = target / observed` per channel, which constrains **value** — the
anchor's mean lands exactly on target, as intended and as verified repeatedly —
and constrains hue **not at all**. The `gain skew` column is max/min of each
anchor's three gains: 1.17 on the chest, 1.46 on the smelter, 4.01 on the pole.
Every asset is fitted to its own drift, so every asset gets a different hue
rotation, and assets that agreed beforehand are rotated apart.

This is the cost of the decision in §13/§17 to own colour in the remap rather
than in prompting. It bought cross-asset **value** agreement, which was the
problem in front of us, and it silently traded hue to get it.

**Not fixed here.** The fix is to split the correction: a scalar gain for
luminance, which is hue-preserving by construction, plus a bounded chromaticity
correction applied only where the raw hue is measurably off target — so a
member Tripo already got right, like the chest's oak, is left alone. That
changes the pixels of all three approved assets and needs its own pass and its
own re-approvals. It is the first item in §31.

Three assets is still a thin basis. It is enough to say the pipeline produces
assets that agree in **value** across both footprints, both fit modes, and two
through four palette members. It does not yet produce assets that agree in
**hue**, and the verdict should not be recorded as a clean pass.

### The pole is the weakest of the set, and the reason is EQUIPMENT REACH

Not colour and not silhouette — both of those were chased and both came back
clean. The cross read that killed v4 is gone (asymmetry 26% → 52%, mast-above
36% → 18%), and after the nearest-texel rescue the verdigris lands on palette.

What is weak: **the transformer box widens the outline from 13 px to 19 px and
stops.** At 1× the pole reads as a post with a small cluster near the top. Its
value contrast against the oak is already 2.08× and does not need changing —
the box needs to project further from the mast. When Pole Tiers needs variants,
that is the note to start from.

### What session 1 did not do

Out of scope and untouched: any Godot code, the other ~17 buildings, animation
frame sequences, terrain, items, UI. Moving parts are specified (§9) but not
built.

---

## 12. Silent-failure tripwires

Two failures have shipped through this pipeline and **both were caught only by
a human looking at pixels**, while every log line reported success:

1. The glTF importer's `QUATERNION` rotation mode made an 8-way turnaround
   render eight identical images, with no error anywhere.
2. Applying the albedo correction *before* the emission mask was detected made
   the smelting state render identical to idle — while the log printed
   `STATE smelting: mask-driven emission on 1 material(s)` throughout.

They share a shape: **a transform silently did nothing, and every downstream
report claimed success.** Logs confirm that code ran, not that it had an effect.

`art/tools/assert_states.py` runs on every build and fails it if two declared
states of the same asset differ by less than 0.25% of opaque pixels (at a
per-channel threshold of 8/255). Deliberately loose — it is a tripwire for
"did nothing at all", not a quality check. The smelter's fire changes **4.48%**,
an order of magnitude above the floor.

Verified in both directions: it passes on a good build, and forcing the two
states to be identical makes it fail with a non-zero exit.

The general lesson, worth applying to the next transform added here: **assert on
the output, not on the fact that the code ran.**

---

## 13. Palette matching: order before distortion

The albedo remap needs to know which cluster is which material. That matching
used to run **before** the global gain was removed, which forced the metric to
be value-invariant (chromaticity only) - and a value-invariant metric cannot
separate two near-neutrals at any hue, because a near-neutral's chromaticity
*is* the white point.

The response was almost to distort the palette: push iron blue, push oak olive,
buy separation with colours nobody wanted. That would have been solving the
right problem in the wrong place.

**The fix is ordering, not colour:**

```
a. estimate the global gain from AGGREGATE albedo   (no matching needed)
b. divide it out                                    (value is meaningful again)
c. match clusters on FULL linear RGB                (chromaticity AND value)
d. per-cluster remap
```

Step (a) needs no correspondence at all - it is just the asset's mean albedo
against the palette's mean - so it can run first. Measured estimation error
~9%.

Correct-assignment rate, 25 randomised trials with a stone-heavy material mix
and a random per-generation gain:

| palette | old ordering | new ordering |
|---|---|---|
| **natural (locked)** | 53.6% | **89.6%** |
| distorted "separable-5" | 78.4% | 93.6% |

The distorted palette is still 4 points better; that gap is the price of
natural colour and is paid deliberately. On the real smelter the two
near-neutrals now both clear the trust threshold - fieldstone at 0.19 of
min-pair, wrought iron at 0.44 - and variance explained rose from 67% to 79%.

The trust threshold is no longer an absolute number: an anchor is trusted when
its match sits nearer than **half the palette's own min-pair separation**, so it
recalibrates with the palette instead of being a magic constant.

### Judging a palette

`palette_board.py` renders each candidate on flat proxy geometry through the
locked rig with **no Tripo texture and no correction in the path** - chips at
true 32 px size, at 4x, and on three proxy buildings. Every earlier look at
these colours was through a Tripo texture and an albedo correction, which shows
a correction, not a palette.

---

## 14. Does the PROMPT palette bind? No - it is advisory (re-verified at K=24)

`SMELTER.glb` was prompted with the superseded draft palette (`#3C4650` blue
iron, `#7A5A33` olive oak) and measured against the locked `natural-5` targets.
If the prompt palette bound, iron and oak would be the anchors that failed.

**The original version of this test ran at K=10 and was therefore contaminated**
- the same K bug that later turned out to be merging the two near-neutrals into
one cluster. One row of it (leather's drop) was already retracted, so the whole
table was re-run at the derived K.

| member | prompt delta from locked | K=10 match d | K=24 match d | K=24 d1/d2 | K=24 |
|---|---|---|---|---|---|
| fieldstone | **0.0000** (prompted exactly) | 0.0474 | 0.0228 | 0.50 | clears |
| wrought iron | 0.0252 (prompted **wrong**) | 0.0219 | **0.0215** | 0.40 | **clears** |
| weathered oak | **0.0543** (prompted **most wrong**) | 0.0168 | **0.0111** | 0.24 | **clears best** |
| leather | 0.0154 (near-identical) | 0.0656 | 0.0270 | 0.74 | clears |

**The answer is (a), and it is stronger at K=24 than it was at K=10.** At the
correct resolution **all four declared members clear with zero drops**, and the
ordering is unchanged: the member prompted *most* wrongly matches *best*, and
the member prompted *exactly* is third of four. Rank correlation between prompt
delta and match distance is **-0.80 at both K=10 and K=24** - identical, and
negative, where a binding prompt would give a positive one.

> **Honest limit:** n = 4, so the rank correlation alone is weak evidence. The
> claim does not rest on it. The robust fact is that **both** members prompted
> with materially wrong hexes (iron 0.025 off, oak 0.054 off) clear comfortably,
> while exact prompting bought fieldstone nothing.

**Conclusion for assets 4-20: the prompt palette is advisory.** Getting a hex
slightly wrong costs nothing once the remap exists. What binds is that every
material an asset claims appears as a **visually distinct region with real
area** - see `palette_members` below. Prompt for material separation, not for
exact hexes.

### Was the palette rebuilt for the right reason? Half of the evidence was contaminated

The legacy-6 palette was retired on two measurements, both taken at K=10:
`forge_brown` mismatching at 0.279, and `fired_clay` needing a 4.4x gain clamp.
Re-run on the original kiln at the derived K=36:

| member | K=12 | K=36 | |
|---|---|---|---|
| fieldstone | keep | keep | |
| fired_clay | keep, but **4.4x clamp at K=10** | keep, gain **[1.33, 1.38, 1.65]** | **no clamp - the 4.4x was a K artifact** |
| weathered oak | keep | keep | |
| wrought iron | **DROP** | keep | K artifact |
| leather | keep | keep | |
| forge_brown | **DROP** | **DROP** (d1/d2 = 1.31) | **real at every K** |

So: **`fired_clay`'s 4.4x clamp was an artifact and should not have counted.
`forge_brown`'s drop is real** - it fails at every resolution from 3 clusters
per member upward, because at 0.079 from leather it is genuinely inseparable.

The rebuild was justified, but by one of the two numbers rather than both - and
by the structural argument that never depended on K at all: four members at hue
17-30 degrees separated only by value is a bad palette on its own merits.

---

## 15. Baked shading: it reinforces the rig, it does not fight it

The stone faces carry painted gradients. The remap corrects value, not
gradient, so the question is whether that baked light competes with the locked
rig.

**A variance decomposition of the albedo could not answer it.** Splitting
within-cluster luminance variance by spatial scale returned ~100% "coarse" for
every material, at both 2048 and full 8192 resolution - because the variance is
dominated by different *faces* sitting at different values, which swamps any
within-face gradient. The metric is in `baked_shading.py` and is reported, but
it is not the answer.

**The decisive test is a rig-only render.** `render_rigonly.py` re-renders the
asset with every albedo flattened to mid grey, leaving only what the three-point
rig and the geometry produce. Comparing that against the real render separates
the two:

| | |
|---|---|
| correlation, real vs rig-only (log luminance) | **+0.918** |
| final-sprite variance from the RIG | **52.0%** |
| final-sprite variance from the ALBEDO | 48.0% |
| correlation of implied albedo with rig shading | **+0.443** |

The last number is the answer: **the baked light runs WITH the rig**, not
against it. The concept image was lit from roughly the same direction the rig
uses, so the painted falloff exaggerates the rig's own shading rather than
fighting it.

That is the good outcome, with one caveat worth carrying: *exaggerates* means
this asset renders at higher contrast than a genuinely flat-albedo one would,
and the amount is per-asset and uncorrected. It is a cross-asset consistency
risk, not a per-asset defect - and it is exactly why "flat even shadowless
lighting" stays in the style block.

---

## 16. Rivet noise: invisible, but cheap

Dozens of sub-2px dots on the iron straps.

| | |
|---|---|
| features at p85 | 20 |
| under 2 px thick | **16 of 20 (80%)** |
| under 1.5 px | 9 |
| median thickness | 1.54 px |
| HF energy destroyed | **3.4% = 1.45x floor** - the best of any asset so far |

They do **not** survive - no dot pattern is visible on the straps at true size.
But they cost almost nothing either: the HF gate is the lowest yet, because the
rivets are low-contrast against the strap and average into its tone rather than
fighting the downsample.

So this is wasted generation detail rather than harmful detail. It feeds the
prompt-budget feedback (80% under 2 px) without threatening the gate.

---

## 17. Three changes from the advisory-palette finding

### The rig correlation is a GATE now, not a diagnostic

`+0.443` on the first measurement was fortunate, not designed - the concept
image carried a painted falloff despite the prompt demanding flat lighting, and
it happened to fall near the rig's key. An asset lit from the opposite side
would **oppose** the rig, and nothing else in the pipeline would notice: the
palette still matches, the HF gate still passes, the states still differ.

`assert_rig_correlation.py` runs on every real asset. It divides the rig out of
the render in log space and correlates the remainder against the rig's own
shading. **A negative sign fails the build.** Magnitude stays advisory until
three assets exist to calibrate a threshold against - a limit picked from n=1
is a guess.

> **The magnitude is not comparable across pipeline versions.** The same asset
> measured **+0.443** and later **+0.296** with no re-render and no change to
> the concept image - only the correction pipeline moved underneath it (K=10 to
> derived K, pruned membership, different per-cluster gains). The sign was
> unaffected, which is why the sign is the gate.
>
> When the magnitude threshold is set at n=3, set it on **final corrected
> renders of all three assets measured under one pipeline version**, and re-measure
> all three whenever the correction changes. A magnitude carried forward from an
> older pipeline version is not evidence.

Negative-tested by synthesising an asset with `real = rig^0.5`, whose implied
albedo opposes the rig by construction: the gate returns `-0.999` and exits 1.
The real smelter reads **+0.296** and passes.

`PROMPTS.md` now specifies the key direction (upper left, matching the rig)
rather than only asking for flat light.

### Palette membership is declared per asset

Verdigris "dropped" on a building with no green in it - a category error, not a
failure, and it first stole a cluster from the assignment on its way out.
`assets.json` now carries `palette_members`; matching is restricted to those and
undeclared members are **skipped**, not attempted.

### K=10 was the real bug behind every matching instability

Pruning membership exposed something bigger. Three matching strategies were
tried and all three behaved erratically:

- **greedy** - order-dependent and cascading. Removing verdigris freed a
  cluster, leather took the one oak wanted, and oak went from matching to
  ambiguous with nothing about oak having changed.
- **optimal (min total cost)** - sacrifices individuals for the sum. Fieldstone
  was handed the iron cluster and iron a brown one; each absurd, together cheap.
- **independent nearest** - stable, and the one kept. Two members landing on the
  same cluster is not a conflict to resolve arbitrarily; it is exactly the
  ambiguity the `d1/d2` test exists to catch.

But the erratic behaviour was not really the algorithm. **With K=10 clusters the
two near-neutrals kept merging into ONE cluster**, and which member won it then
swung with membership, gain, and strategy.

### K is DERIVED, not chosen

24 would have been a magic number tuned on one asset. The rule is
**K = 6 x declared palette members**, so a three-material chest gets 18 and a
six-material building gets 36 instead of one constant over- or under-resolving
both. Swept on two assets with different member counts:

| clusters per member | 2 | 3 | 4 | **5** | **6** | 8 | 10 |
|---|---|---|---|---|---|---|---|
| SMELTER x natural-5 (4 members) | 2/4 | 2/4 | 3/4 | **4/4** | **4/4** | 4/4 | 4/4 |
| original kiln x legacy-6 (6 members) | 4/6 | 5/6 | 5/6 | **5/6** | **5/6** | 5/6 | 5/6 |

Both plateau at or below 5 per member, so **6x sits inside the plateau with
margin on both**, at different absolute K (24 and 36). The kiln's remaining
drop is `forge_brown`, which fails at every resolution - that one is the
palette, not the clustering. With that fixed and
membership pruned, the smelter matches **all four declared members with zero
drops and 90% variance explained** - the best result of the project.

### Thickness alone was the wrong diagnostic

16 of 20 features under 2px, yet this asset has the *lowest* HF destruction of
the set at 1.45x floor - because its rivets are low-contrast and average
harmlessly into the strap. Sub-2px detail is only wasteful when it is **also
high-contrast**.

The diagnostic now reports thickness x contrast:

| | |
|---|---|
| median thickness | 1.54 px, 80% under 2px |
| sub-2px **costly** (contrast >= 0.12) | **8** |
| sub-2px free (averages away) | 8 |

Half the thin detail is free. Only the other half is worth prompting away. Still
prompt feedback, still not a gate.

---

## 18. The power pole: tall-thin proven, verdigris confirmed, HF gate FAILED

> **SUPERSEDED in part by §22.** The HF gate referred to here no longer exists:
> it rejected a pole that looked correct, and was demoted to a diagnostic. The
> tall-thin and verdigris findings stand. The pole described here is v1; the
> approved asset is v5 (§30, §11).


### K = 6 x members holds away from the value it was derived on

Three declared members, so K = 18. Swept:

| clusters per member | 2 | 3 | 4 | **5** | **6** | 8 | 10 |
|---|---|---|---|---|---|---|---|
| trusted (of 3) | 1 | 1 | 1 | 2 | **3** | 3 | 3 |

The plateau starts at 6 here rather than 5, so **the 6x rule sits exactly on the
knee for this asset** - it holds, but with no margin below it. Three assets now
sweep clean at 6x (smelter 4/4, kiln 5/6, pole 3/3) at three different absolute
K values (24, 36, 18). Keep 6x; do not lower it.

### Verdigris clears - but only after a gain fix

The first run dropped verdigris at **every** K, which looked like the
prune-membership rule failing on its first real test. It was not. The caps are
present: 2.84% of texels, median `#2F4F41`, hue ratio G/R 2.79 against the
target's 2.55.

The fault was the **aggregate gain seed**. It assumes the asset's material mix
resembles the palette's, and this asset is overwhelmingly timber with only three
declared members - so the seed came out `R 1.050 / G 0.462 / B 0.203`, a **5.2x
channel spread**, and the skew pushed verdigris out of range.

Fixed by **refining the gain iteratively**: match with the seed, re-estimate the
gain from the trusted anchors only, repeat. Convergence:

| pass | pole gain spread | pole trusted | smelter gain spread | smelter trusted |
|---|---|---|---|---|
| 0 (seed) | 5.17x | 2/3 | 1.22x | 4/4 |
| 1 | 2.96x | 2/3 | 1.29x | 4/4 |
| 2 | 2.51x | **3/3** | 1.31x | 4/4 |
| 3 | 1.82x | **3/3** | 1.31x | 4/4 |

It rescues a mix-skewed asset and leaves a well-mixed one alone. This is not the
circular "match before removing the gain" the ordering fix eliminated: the seed
still needs no correspondence, and each refinement uses only anchors that
already passed the trust tests.

**So the prune-membership rule is confirmed, not merely assumed.** Verdigris
clears at 0.47 of min-pair on the asset that has it, and is skipped on the one
that does not.

### An approved asset must not be silently re-corrected

The refinement changed the *smelter's* correction too - improving its measured
fit 90% -> 92% while altering **28.6% of its pixels by >8/255 and 7.6% by
>32/255**. Better numbers, different picture, on an asset that was already
approved.

Its remap is now **pinned** (`albedo_pinned: true`): the approved values are
frozen in the manifest, `palette_drift.py --emit` refuses to overwrite them, and
the render reports the pin. Verified byte-identical to the approved sprite
(mean delta 0.00/255).

The general rule: **a pipeline improvement is not a licence to re-render an
approved asset.** Pin it, and unpin deliberately when re-approving.

### Tall-thin case: confirmed

| | |
|---|---|
| fit | `height`, 2.6 tiles - mandatory, the 1x1 footprint carries no scale signal |
| normalized extent | 1.19 x 0.56 x 2.60 tiles |
| cell | **2 x 3 tiles** -> 64 x 96 sprite |
| anchor | **[32.0, 96.0]** = exactly sprite bottom-centre |
| overflows front edge | **false** - the cell grows UPWARD only |

### Crossarm overhang: 26.3% each side

Measured, both sides symmetric: **40 px past the notch, 26.3% of silhouette
width, 15.6% of canvas.** That is what forces `cell_w` to 2 and gives the
64 x 96 sprite, exactly as expected.

It is **not** pushing past 2 tiles: the full silhouette is 152 px of a 256 px
(2-tile) canvas, so there is 40% of the cell still spare. A crossarm would have
to grow by roughly 1.7x before it forced a 3-tile cell. Tiered variants have
room.

### HF detail gate: FAILED at 7.43x

| asset | HF destroyed | ratio | gate |
|---|---|---|---|
| chest (proxy, the floor) | 2.1% | 1.00x | pass |
| smelter (reference) | 3.5% | 1.67x | pass |
| **power_pole** | **15.6%** | **7.43x** | **FAIL** |
| first kiln (rejected) | 14.3% | 6.1x | fail |

**The pole destroys more high-frequency energy than the kiln that was rejected
for cobbles.** The shape is not the excuse: the flat-shaded pole *proxy*, same
silhouette and same 41% bbox coverage, measured 2.6%. The difference is
contrast - 10 of its 16 features are sub-2px **and** high-contrast, mostly the
dark iron bands against light timber.

**The cap has not been moved.** Recommendation: regenerate with fewer iron
bands - two instead of five - and lower contrast between band and post. The
silhouette, the crossarm, the verdigris caps and the base plate all read well
and should be kept.

> **Floor caveat:** `power_pole` used to be one of the two flat-geometry floor
> references and cannot be now that it is a real textured asset - a floor cannot
> include the thing it measures. The floor is `chest` alone, **n = 1**. That
> also means the smelter's ratio moved 1.45x -> 1.67x on the same pixels, purely
> because the floor changed. Ratios are only comparable within one floor
> definition, the same caveat that already applies to rig correlation.

---

## 19. The HF floor is now synthetic and permanent - and the cap needs a decision

> **The floor stands; the cap question is closed by §21, and the gate it was a
> cap FOR is demoted by §22.** The synthetic floor remains correct and in use.


### The floor object

`art/source/_calib_floor.glb`, built once by `make_calibration.py` and
**committed**. A real asset is never the floor again: a floor cannot include the
thing it measures, and when `power_pole` graduated from proxy to real the
smelter's ratio moved **1.45x -> 1.67x on byte-identical pixels**.

How absurd that gets if you ignore the rule: measured *today*, with the now-real
`power_pole` still in the floor, the "floor" computes to **8.85%** and every
asset passes - including the pole, at 1.76x, which is the thing the gate exists
to catch.

**The floor object is a MODEL ASSET, not a bare solid.** A single-colour block
measures 0.80%; adding building features took it to 1.10%; giving those features
real palette colours at high value contrast settled it at **1.00%**. The old
proxies measured 2.1-2.6% because they carried several materials meeting at
colour boundaries - and a colour boundary between two large flat regions is
legitimate, required detail. So the floor obeys the art direction exactly:
large regions, real palette colours, high contrast between them, no thin
high-contrast features, no texture. What it costs is the irreducible cost of a
compliant building.

`detail_density.py` prints the floor with every measurement, and will flag drift
if it ever moves.

### The cap now needs re-deriving, and that is YOUR call

**I have not moved it.** But the denominator moved underneath it, so the gate
silently became stricter and that must be visible rather than absorbed:

| | old floor (proxies) | new floor (synthetic) |
|---|---|---|
| floor | 2.35% | **1.00%** |
| budget at 3x | 7.1% absolute | **3.0% absolute** |

The same 3x cap is now roughly **2.4x stricter in absolute terms**. Measured
against it:

| asset | HF | vs new floor | vs old budget (7.1%) |
|---|---|---|---|
| `_calib_floor` | 1.0% | 1.00x pass | pass |
| chest (proxy) | 2.1% | 2.10x pass | pass |
| smelter, approved correction | 3.5% | 3.50x **fail** | pass |
| smelter, refined correction | 6.4% | 6.40x **fail** | pass |
| **power_pole** | **15.6%** | **15.60x fail** | **fail** |

**The pole fails under either definition** - that conclusion is robust and does
not depend on this decision. The smelter's status depends entirely on it.

Two coherent options, both defensible, neither taken unilaterally:

1. **Keep 3x and accept the absolute budget is now 3.0%.** The gate genuinely
   tightened; both real assets need less texture. Honest, and the strictest
   reading.
2. **Re-derive the cap so the absolute budget is preserved** - about **7x**
   against this floor reproduces the ~7% the old gate actually allowed. This is
   not "moving the cap to accommodate a correction"; it is restoring a threshold
   after its denominator was redefined. The pole still fails decisively at 15.6x.

My recommendation is (2), with the cap written as a derived value rather than a
constant, so it is obvious it belongs to a floor definition. But the gate's
strictness is an art-direction decision, not a measurement one.

### The smelter is unpinned and awaiting re-approval

Pin means "requires explicit re-approval", not "frozen forever" - freezing it
would recreate the palette-era problem one layer down, with the smelter
corrected by the old algorithm and the pole by the refined one.

Re-emitted with the refined gain: **measured fit 90% -> 92%**, and **28.6% of
pixels moved by >8/255, 7.6% by >32/255**. Side by side in
`art/renders/smelter_reapproval.png`. Its rig correlation moved +0.296 ->
+0.492, which is expected: same asset, different correction, and the magnitude
is not comparable across pipeline versions.

---

## 20. Pole v2: the band fix was right and insufficient - GRAIN dominates

> **SUPERSEDED.** Grain was later made INTENTIONAL on this asset and must not be
> flagged. See §21. The measurement technique here is still sound.


Five high-contrast bands became two low-contrast bands. The result, plainly:

| | HF destroyed | vs synthetic floor |
|---|---|---|
| pole v1 (five bands) | 15.6% | 15.60x |
| **pole v2 (two bands)** | **13.6%** | **13.60x** |

**A 13% drop, not a large one.** The contrast-by-area theory is not falsified -
it moved the number in the right direction - but it is clearly not the dominant
cost on this asset. Saying so plainly rather than explaining it away was the
instruction, and this is that answer.

### Where the cost actually is

`hf_regions.py` decomposes it two ways. The one that matters here is by
ORIENTATION, because grain and bands overlap in the same pixels and no spatial
mask could separate them: vertical stripes (grain running up the mast) put their
energy in the horizontal-frequency axis, horizontal stripes (bands crossing it)
in the vertical axis.

| | share of destroyed energy |
|---|---|
| whole sprite - vertical stripes (grain) | **64%** |
| whole sprite - horizontal stripes (bands) | 36% |
| **inside the mast** - vertical (grain) | **74%** |
| inside the mast - horizontal (bands) | 26% |

**Grain dominates, roughly 3:1 inside the mast.** Corroborated independently in
the albedo: the pole carries about **1.7x the smelter's total fine-detail
energy**.

> **A flaw in my own metric, stated rather than buried:** the by-region
> "contribution" number came out **negative** for the crossarm (-5.90%). That is
> the measure failing, not a finding - HF is a RATIO of high-band to total AC
> energy, so flattening a large region strips low-frequency energy too and can
> RAISE the ratio. Region contributions are only readable by sign, and only for
> the largest region. The orientation split has no such problem: fixed region,
> fixed total, so it is the number to trust.

**The fix is "no visible wood grain", and it belongs in the style core** - where
it was, before the fine-detail rule was relaxed. That is a prompt error, not a
model failure. `PROMPTS.md` now carries it with this measurement attached.

### The bands landed exactly on the ambiguity the d1/d2 rule exists to catch

They do form their own cluster, and it is a dead heat:

| cluster | colour | pop | d to oak | d to iron | d to verdigris | d1/d2 |
|---|---|---|---|---|---|---|
| 15 | `#4F4229` | 2.5% | 0.0909 | 0.0983 | 0.0933 | **0.97** |

Equidistant from three members at once. It did not cause a *drop*, because it is
not the chosen cluster for any member - oak took `#4C300F`, iron took `#282B23`
(the dark base plate). So the band cluster is simply **unmatched and ignored**:
the bands are corrected only by whatever gaussian blend of the other anchors
happens to reach them, and drift uncorrected.

**The tension is real and worth naming: low contrast helps the downsample and
hurts the matcher.** Asking for a band "only slightly darker than the timber"
produced a warm olive sitting between oak and iron, which is exactly what an
ambiguous cluster looks like.

**It resolves rather than trades off, though - the instruction just needs to be
sharper.** Low contrast should constrain **value**, not **hue**. A thin iron
band should be a *dark, desaturated wrought iron* - close to the timber in
lightness, unmistakably iron in hue. What produces ambiguity is drifting the hue
halfway to the neighbour, not keeping the value close. `PROMPTS.md` now says so.

---

## 21. HF cap DECIDED: 3x the synthetic floor, locked

> **Still the cap, but read §22 first** — HF destruction is a diagnostic, not a
> gate, so the cap no longer rejects anything on its own.


The cap stays at **3x**, measured against the permanent synthetic floor
(`_calib_floor`, 1.00%), giving an absolute budget of **3.0%**. Closed; not
revisited when an asset finds it tight. *"If it feels tight, that is a signal
about the asset, not the cap."*

### One correction to the number that decision cited

The decision cited the smelter passing "comfortably at 1.67x". **That figure was
against the retired proxy floor of 2.10%, not the synthetic floor.** Re-measured
against the locked floor:

| smelter correction | HF | vs 1.00% floor | 3x cap |
|---|---|---|---|
| approved (current) | 3.5% | **3.50x** | fail, marginal |
| refined (unpinned candidate) | 6.4% | **6.40x** | fail, not marginal |

**The reference asset does not currently pass its own gate**, under either
correction. That does not change the decision - the pole fails at 13.60x under
any definition, so moving the cap was never the answer - but it does mean the
cap now flags the reference asset too, and that should be a deliberate state
rather than a surprise.

The smelter's HF is isotropic (50% vertical / 50% horizontal), so unlike the
pole it has no single dominant source to remove; getting it under 3.0% means
less texture generally, not one rule.

### The refinement's HF cost, which the re-approval decision now has to weigh

Re-emitting the smelter with the refined gain **doubles its HF**: 3.5% -> 6.4%.
That was invisible while the floor was 2.35% and both readings passed. Under the
locked cap it is the difference between marginal and clearly over.

So the re-approval is no longer only "better colour fit vs different pixels":

| | approved | refined |
|---|---|---|
| variance explained | 90% | **92%** |
| HF vs 3x cap | 3.50x | 6.40x |
| pixels moved >8/255 | - | 28.6% |

The asset is **pinned to the approved correction** until that is decided, so the
lower-HF, already-approved pixels are what sits in the tree meanwhile.

---

## 22. The gate is the sprite, judged by eye

**HF destruction is demoted to a diagnostic.** It is still measured and still
reported on every run. It no longer rejects anything.

It earned its keep once: on the first kiln the cobbles genuinely turned to mud
at 32 px and this number caught it before anyone looked closely. Then it
rejected a power pole that looked good, and the asset was re-generated to
satisfy it into looking plastic. **A gate that fails good work is worse than no
gate.**

> Worth stating plainly rather than implying a bigger change than happened:
> `detail_density.py` was never wired into `build.ps1`. **No build was ever
> blocked by the HF number** - the `GATE ... FAIL` wording was presentational.
> The demotion is real as policy and as language; it changed no build behaviour.

**The gate is a finished sprite at true in-game size, looked at.**
`art/tools/eye_sheet.py` puts the asset at 1x, 2x and 4x beside an approved
reference at 1x, on neutral mid-grey, with **nothing written on the image** - no
labels, no numbers, no grid. A metric printed beside a picture tells you what to
think about the picture.

```bash
python art/tools/eye_sheet.py --asset power_pole --reference smelter_idle
```

If a high HF number ever coincides with a sprite that genuinely reads as mud,
the number was right and should be said so. It does not get to reject on its own.

### What still gates a build

| gate | what it catches |
|---|---|
| `assert_palette_era` | an asset from a superseded palette entering the verdict |
| `assert_states` | a state that renders identical to another - a transform that silently did nothing |
| `assert_rig_correlation` | baked light that OPPOSES the locked rig |
| camera calibration | the anamorphic correction breaking |

All four catch things a human cannot see by looking at one sprite: a wrong
palette era looks fine in isolation, identical states look fine unless compared,
opposing light looks fine until placed next to a neighbour. That is the right
division - **automation for what the eye cannot check, the eye for everything
else.**

### And it should have happened sooner

Nothing in this session had been judged as a finished sprite at true size until
now. Everything was 4x masters and spectral ratios - which is how an asset got
tuned into looking plastic while every number improved. The session's own brief
said to judge at true size; the tooling made it easy not to.

---

## 23. What the eye sheet found that no metric did

Pole v2 approved by eye, and at 4x the grain is invisible - which settles the
grain argument from the other direction: that energy was never going to be seen
either way, so three regenerations chased something that does not exist at final
size. The HF number was measuring a real physical fact that had no visible
consequence.

### The shadow: none of the three hypotheses - there is no shadow at all

Not the catcher rendering its own surface, not `film_transparent`, not the eye
sheet compositing an alpha-less layer. **The template contains a camera, three
suns and a hidden reference cube. No ground plane. No shadow catcher.**

The hard grey slab is each asset's **own modelled base plate**, and it is fully
opaque in the sprite alpha - 28% of the bottom band at alpha 1.0, only 2%
partial. A real soft shadow would be a broad band of PARTIAL alpha; there is
none, because nothing casts one.

So the observation was right and the cause was the opposite of the assumption:
the assets look pasted on because **they have no contact shadow whatsoever.**

`render_shadow.py` adds one, as a separate layer on the glow-layer precedent. A
ground plane marked `is_shadow_catcher` contributes only the shadow that falls
on it; the asset is hidden from camera rays (`visible_camera = False`) while
still casting, so the pass contains the shadow and nothing else. It is soft
because the key already carries an 8-degree angular size - **nothing in the lock
changes.** Measured on the pole: 22.9% faint alpha, 3.9% mid, 4.2% solid, max
1.0 - a falloff, not a slab.

Godot draws shadow, then body, same anchor. Keeping it separate means it can be
tinted per biome, faded, or switched off without re-rendering.

### The bleached smelter: the rig responding to FORM, not a correction misfiring

Measured on the FINAL 32 px sprites, not the albedo, and decomposed exactly by
dividing the real render by the rig-only render:

| | albedo after correction | rig multiplier | on screen |
|---|---|---|---|
| smelter stone | 0.24x target | **8.63x** | **2.07x target** |
| pole timber | 0.18x target | **2.85x** | **0.53x target** |

**Relative gap on screen: 3.92x.** That is the cross-asset consistency failure,
and it only appeared when two finished sprites sat side by side.

Ruling the hypotheses out in turn:

- **Not the view transform.** 0.0% of pixels at 255, max 217. Nothing clips.
- **Not the correction over-brightening.** It is *under*-correcting - both
  assets land at 0.18-0.24x of their target albedo.
- **It is the rig, responding to form.** A blocky mass presents large flat faces
  to the key (8.63x); a thin post is mostly edge-on and self-shadowed (2.85x).
  That 3x is most of the 3.92x gap.

> **A locked palette hex is an ALBEDO, not a screen colour.** Under this rig
> every surface is multiplied by roughly 3-9x depending on how it faces the key,
> so no asset will ever show `#5A5E58` on screen. Consistency means every asset
> sharing one albedo-to-screen transform, which they do - but form still decides
> how much of each asset is lit, and at 32 px a 3x spread reads as one building
> being bleached.

### And a bug of mine underneath it: the gain clamp is the binding constraint

**Every single anchor on every asset is clamped.** 52% of raw gain channels sit
at or above the 2.5 ceiling; the pole's oak asked for **6.53x** on blue and got
2.5x.

Tripo returns albedos around 0.2x of target, so the correction needs roughly
4-5x - and `GAIN_CLAMP` caps it at 2.5. It is not a safety rail here, it is the
thing limiting every correction, and it truncates by a **different amount per
asset**, which feeds straight into the cross-asset gap above.

Worse, the clamp was introduced for a reason that turned out not to exist:
`fired_clay` "wanting 4.4x" was later shown to be a **K=10 artifact**. The rail
was built for a phantom and has been quietly degrading every asset since.

Raising it is a pipeline change that touches approved pixels, so it is proposed
rather than shipped - see the session report.

---

## 24. Clamp raised, a correction to my own diagnosis, and the rig measured

> **The clamp raise and the rig measurement stand; the rig DECISION is §25.**


### The clamp is now a safety rail at 12x, and it speaks when it binds

`GAIN_CLAMP` was `(0.4, 2.5)` and bound on every anchor of every asset. It is
now `(0.4, 12.0)` - high enough to be non-binding - and if it ever does bind it
logs loudly, because **an anchor demanding more than 12x means the MATCH is
wrong**, and truncating it silently would hide the bad match instead of
surfacing it.

Both assets re-emitted. Nothing binds. The pole's oak now receives its full
**6.53x** on blue where it previously received 2.5x.

### I was wrong about what the clamp was doing, and the correction matters

Last round I reported the albedo correction "under-correcting to 0.18-0.24x of
target". **That was wrong.** Checked directly, every anchor lands exactly on
its target:

| asset | member | observed Y | x gain | corrected | target | ratio |
|---|---|---|---|---|---|---|
| smelter | fieldstone | 0.0446 | 2.52 | 0.1088 | 0.1088 | **1.00x** |
| smelter | wrought iron | 0.0348 | 2.28 | 0.0759 | 0.0759 | **1.00x** |
| smelter | weathered oak | 0.0395 | 2.54 | 0.0880 | 0.0880 | **1.00x** |
| pole | weathered oak | 0.0372 | 3.70 | 0.0880 | 0.0880 | **1.00x** |
| pole | wrought iron | 0.0234 | 3.56 | 0.0759 | 0.0759 | **1.00x** |

The 0.21x figure compared a **region median** against a single flat hex. The
albedo carries heavy baked shading - measured earlier at ~100% coarse-scale
variance - so a region's median sits far below its cluster MEAN. Correcting the
mean onto target is exactly right; the spread around it is baked light, which
the remap was never meant to remove.

**The clamp was still a real bug** - but it was causing a per-channel HUE error,
not a lightness shortfall. The pole's oak was getting 2.5x where it needed 6.53x
on blue alone, a blue deficit that read as a warm cast. Raising it moved
**90.1% of the pole's pixels** by more than 8/255.

**So the bleaching has exactly one cause: the rig responding to form.** Not the
correction, not the view transform.

### The rig, measured - NOT changed

`rig_study.py` renders three flat-shaded probes at one albedo and reports the
multiplier for each. It writes nothing and touches no locked value.

| variant | key:fill | top | front | post | spread | top/post |
|---|---|---|---|---|---|---|
| **locked** | 3.76:1 | 11.67 | 5.30 | 5.30 | 6.37 | **2.20x** |
| fill x2 | 1.88:1 | 11.96 | 6.18 | 6.31 | 5.78 | 1.90x |
| fill x3 + ambient x1.5 | 1.25:1 | 12.39 | 7.59 | 7.62 | 4.81 | **1.63x** |

Form readability, top-vs-front separation: **54.6% -> 48.4% -> 38.8%**.

**The trade is roughly one for one.** Going from the locked rig to the widest
fill tested cuts the form-driven spread by 26% and costs 29% of the contrast
between a lit face and a turned-away one. There is no free lunch in the fill
knob: consistency is bought from form readability at about par.

Note also that fill lifts only the shadowed side - the top face barely moves
(11.67 -> 12.39) while front and post rise from 5.30 to 7.6. It compresses the
range from below, which is the mechanism to expect.

> **The probes UNDERSTATE the real problem, and that limitation is the most
> important thing here.** They read 2.20x top-to-post, but the real assets
> measured **8.63x vs 2.85x = 3.03x**. The probes isolate ORIENTATION; they
> cannot reproduce self-shadowing and inter-part occlusion, which is where the
> rest of the real gap comes from. An isolated post catches as much fill as a
> wall does - my "post" and "front" probes returned an identical 5.30 - whereas
> a post standing among crossarm, plate and its own bracing does not.
>
> So raising fill would narrow the gap by *less* than this table suggests, at
> the readability cost the table shows in full. If the rig is unlocked, it
> should be on probes that include occlusion, not these.

---

## 25. DECISION: the rig stays locked, and form-driven lightness is accepted

Not a defect. A decision, taken on measurement.

### The rule

**A locked palette hex is an ALBEDO, never a screen colour.**

Under this rig every surface is multiplied by roughly 3-9x depending on how it
faces the key. `#5A5E58` will never appear on screen and is not supposed to. It
is the target the albedo correction aims the *material* at, before any light
touches it.

**Consistency means a shared transform, not a shared appearance.** Every asset
goes through the same locked camera, the same three-point rig, the same
correction to the same palette. That is what makes them one set.

**Form still decides how much light a surface catches, and that is correct.** A
squat blocky smelter presents broad faces to the key and reads light. A thin
post is edge-on and self-shadowed and reads dark. Two buildings of the same
material *should* differ in final lightness if their shapes differ - that is
what makes them read as objects standing in a world rather than decals pasted
onto it.

### Why it was not "fixed"

The bleaching had exactly one cause once the other two were ruled out: not the
view transform (0.0% of pixels clip), not the albedo correction (every anchor
lands 1.00x on target). The rig, on form, measured at 8.63x versus 2.85x
between the smelter's stone and the pole's timber.

The fill knob was measured rather than turned:

| variant | key:fill | top/post spread | form readability |
|---|---|---|---|
| **locked** | 3.76:1 | **2.20x** | **54.6%** |
| fill x2 | 1.88:1 | 1.90x | 48.4% |
| fill x3 + ambient x1.5 | 1.25:1 | 1.63x | 38.8% |

**A one-for-one trade** - 26% less form spread for 29% less contrast between a
lit face and a turned-away one. And the probes *overstate* the benefit, because
they isolate orientation and cannot reproduce self-shadowing or inter-part
occlusion: they read 2.20x where the real assets read 3.03x. Raising fill would
buy less than the table promises at the full price it shows.

So the trade was refused. Flattening the rig to make two buildings agree would
cost the thing that makes every building read as solid.

### What this means going forward

- Do not compare a rendered sprite's lightness against a palette hex. They are
  different quantities. Compare a rendered sprite against **another rendered
  sprite** - which is what `eye_sheet.py` is for.
- A big pale building next to a small dark one is the rig working, not drifting.
- The rig is the last locked thing and stays locked. `rig_study.py` remains for
  measuring it; occlusion-aware probes were considered and **deliberately not
  built**, because that is work to justify a change nobody is making.

---

## 26. The silhouette check

`eye_sheet.py --silhouette` renders the sprite as a **solid black mask on
white**, at true size, with no interior detail whatsoever. If the outline alone
does not say what the building is, the asset fails however good its interior
looks.

**This is the cheapest check in the pipeline and it should have existed on day
one.** The power pole passed four consecutive reviews because every one of them
looked at 4x masters, where the ironwork, the grain and the verdigris caps all
read - and the outline does not. Interior detail flatters an asset at
magnification. The silhouette is what survives at 32 px in peripheral vision,
which is how a factory game is actually read.

Run on the current assets it is immediately decisive:

- **power_pole** reads as a **crucifix**. A plain vertical post crossed by a
  plain horizontal bar, with the insulator caps too small to break the outline.
  Nothing about it says "electrical infrastructure".
- **smelter** reads as a featureless rectangle. Defensible for a squat furnace
  block, but the top hopper barely dents the outline, so it is closer to the
  line than its interior suggests.

Neither of those is visible in any metric this pipeline computes, and neither is
visible at 4x.

**Rule: judge the silhouette before the interior.** An asset whose outline does
not identify it cannot be rescued by texture, and time spent on its materials is
spent before the question that decides it has been asked.

---

## 27. Shadow strength is a composite-time choice

The shadow is a separate layer, so its strength is not baked. `--shadow-levels`
renders one sprite at several strengths side by side at 1x so the level is
picked by eye:

```bash
python art/tools/eye_sheet.py --asset power_pole --shadow-levels 0.25,0.4,0.55,0.7,1.0
```

At full strength the shadow competes with the object at 32px - it reads as a
second dark shape rather than as contact. The layer stays at full density on
disk; Godot scales it with `modulate.a`, the same mechanism the fire glow uses.
Whatever level is chosen is a game-side constant, not a re-render.

**SETTLED: 0.4**, as `lock.SHADOW_STRENGTH`, and it is now the default for
`eye_sheet.py --shadow` so every sheet shows what ships. 0.5 read a touch heavy
at 1x; 0.3 vanished.

It is deliberately NOT in `_lock_payload()`. The stamp answers one question -
"was this rendered under the locked camera and rig" - and shadow opacity is not
part of it. Adding a constant that changes no rendered pixel would invalidate
the stamp on every sprite on disk and force a re-render for nothing. Verified:
stamp still `434c0cf56d8f` after adding it.

## 28. `height_tiles` changes SIZE, not aspect ratio

Pole v4 was rejected on silhouette: the outline reads as a Latin cross. Before
spending a Tripo generation, the cheap thing to try was the manifest, since
`height_tiles` is a number in `assets.json` and not geometry. The reasoning was
that a 2.6-tile thin post with a horizontal bar reads as a monument, and
something stubbier would read as equipment.

It cannot work, and the sweep proves it. `fit: height` is a single scalar
applied to all three axes:

```python
s = float(height_tiles) / max(size[2], 1e-9)   # normalize.py:124
```

Uniform scale preserves every proportion. `height_tiles` sets how many tiles
tall the asset is; it cannot make it stubbier, only smaller. The same v4 mesh
at 2.6 / 2.1 / 1.8:

| height_tiles | bbox | H/W | mast above arm | asymmetry | thin spine | CoM low |
|---|---|---|---|---|---|---|
| 2.6 | 36x56 | 1.56 | 36% | 26% | 67% | 5.4% |
| 2.1 | 30x45 | 1.50 | 36% | 25% | 70% | 5.2% |
| 1.8 | 26x39 | 1.50 | 36% | 25% | 69% | 4.8% |

Every cross metric is flat to within rasterisation noise. Mast-above - the one
that moved when the crossarm was lowered, and so the one that had to move back
- does not budge: 35.7% / 35.6% / 35.9%. The three silhouettes are the same
shape at three sizes, and all three read as a cross.

Aspect ratio is a property of the MESH. The only knob that could change it is
non-uniform scale, which is forbidden here for a good reason: it would make
this asset's proportions disagree with every other asset in the game, and a
squashed pole would sit next to an unsquashed smelter under one camera.

The general rule, worth more than the pole: **a manifest value can only change
what it parameterises.** Before reaching for a free fix, check that the knob is
attached to the thing you want to move. This one was attached to scale, and the
defect was in proportion.

One thing the sweep did surface: at 2.6 the cell unions to 2x3 tiles because
the crossarm overhangs a full tile; at 2.1 and 1.8 it fits in 1x2. That is a
real packing difference, but it is a consequence of the crossarm's span and not
a fix for the silhouette.

**Verdict: no height kills the cross read. Regeneration required**, to the
ordering already agreed - crossarm hard at the TOP of the mast so the outline
is a T with no mast above it, then the transformer box moved high and made much
bigger, then unequal crossarm arms. `art/tools/cross_read.py` measures the four
numbers so the next version can be checked before it is approved.

## 29. The eye sheet must be built from what SHIPS, not from the lit render

Adding `--glow` to `eye_sheet.py` for the smelter's re-approval turned up two
things, one a bug in the new flag and one older.

**The flag lit the wrong panel.** `glow = lit - body`, so the layer may only be
composited onto the body sprite. The first version took the caller's word for
it, lit the idle panel as well, and produced a states strip where idle and
smelting looked identical. `glow_of()` now reads `assets.json`, finds the state
whose hook is null, and refuses anything else out loud:

```
SKIP glow on smelter_smelting: not the body sprite (smelter_idle). glow = lit - body.
```

Compositing the glow onto the LIT render double-counts the fire, which is the
more dangerous of the two mistakes: it looks plausible, just hotter.

**`body + glow` does not reconstruct the lit render exactly**, and glow_layer.py
claimed it did. Measured on the smelter: max 47/255, mean 5.7/255 over the 513
lit pixels. Not clipping - the 35 pixels that clip have LOWER error (3.5) than
the ones that don't (5.9). The cause is that the chain is not linear end to
end: the difference is clamped at zero before the downsample, LANCZOS has
negative lobes, and clamp-then-resample disagrees with resample-then-clamp at
the fire's soft edge.

The error is invisible at 32px and is not worth fixing. What matters is the
consequence: **the composite is what ships and the lit render is a staging
artifact**, so a states sheet built from `smelter_smelting.png` is judging
pixels no player will ever see. The strip is now idle | idle+glow.

Same shape as the silhouette lesson and the shadow lesson: judge the thing in
the state and at the size it will actually be seen in. Three times now the
defect has been in what the review LOOKED at rather than in the asset.

`--glow-strength` renders the flicker range (0.35 / 0.7 / 1.0) so the pulse
bounds are chosen by eye rather than guessed.

## 30. A small accent cannot win a centroid - the nearest-texel rescue

Two of the three defects charged to pole v5 were checked against the pipeline
before writing v6. One was ours. One was mine, and it was a measurement error.

### Verdigris: ours, and it would have recurred on every accent

`d1/d2 = 1.36` on the insulators was read as ambiguity. It was ABSENCE. At
K=18 on a mostly-timber asset, a 4%-of-texture accent never wins a centroid, so
the cluster verdigris "matched" was a blend that was never the insulators. It
then kept Tripo's raw shift - R,G at 0.65x of target with B at 0.99x - which is
a hue skew to cyan, not a dimming, and it was the one feature carrying
"electrical".

The ratio test was not wrong. It was applied at the wrong RESOLUTION. Asking
"is this CLUSTER decisively verdigris" asks about a blend; asking it of each
TEXEL finds the accent. 4.31% of the pole's texels are decisively
verdigris-chromatic, mean #2A4C3C, a real dark teal - and its chroma distance
to target is 0.038, better than either k-means anchor (iron 0.142, oak 0.128).

After the rescue: observed/target went from [0.648, 0.638, 0.993] to
[0.815, 0.764, 0.870]. Channel spread 1.56x -> 1.14x, so what is left is
shading rather than hue.

**Chosen over seeding k-means with the palette members**, which was the other
option on the table. Seeding re-clusters every asset including approved ones.
The rescue can only fire when a member drops, so a zero-drop asset re-emits
bit-identically - verified on the smelter, all four gains unchanged to the last
digit, sigma unchanged. An approval should never be invalidated by a fix aimed
at a different asset.

**The first cut of this was wrong and is worth keeping on the record.** It
selected texels within a radius of `target * gain` in absolute linear space and
"rescued" 7.0% of the texture at #434C40 - a neutral grey. Around a dark
target, a radius in absolute linear space sweeps in every dark texel regardless
of hue. That is exactly the "call a grey cluster green" failure the ratio test
exists to prevent, reintroduced by the thing meant to work around it. Selecting
on chromaticity fixed it.

### The transformer box: MY error, and the diagnosis is withdrawn

I reported the box at 1.27x value contrast against the oak and called it a
design failure. That number came from a crude geometric region - "right of
centre, upper half" - which mixed post pixels and bright hardware into the
sample. It was not the box.

Measured properly, the box texels routed to wrought_iron with 98-100% weight
share and received its ~2.2x gain. The pipeline did its job:

| | iron : oak |
|---|---|
| raw texture albedo | 3.18x |
| after remap | 2.70x |
| rendered sprite, darkest 60% of iron | 2.08x |

The remap does compress the separation slightly (3.18 -> 2.70), because iron's
gain is larger than oak's and lifts the dark toward the light. Worth knowing,
not worth fixing at that magnitude.

`art/tools/remap_audit.py` exists so this question is answerable without
guessing: it prints, per cluster, which anchor's basin it fell into and what
gain it actually received. Its own `--pair` had the same bug in its first cut -
it compared each member's single NEAREST centroid, and reported 1.14x, because
iron's nearest cluster is a 6%-population mid-grey while the box's mass sits in
two darker clusters that also route to iron. One centroid is not a region; it
is population-weighted now.

**So the box is not a contrast defect.** What it lacks is SILHOUETTE
projection: it widens the outline from 13px to 19px and no more. The v6
ordering stands - bigger box first - but for reach away from the mast, not for
value.

## 31. Session 1 close

### Against the brief

| Deliverable | State |
|---|---|
| A locked Blender template | **done** — `art/template.blend`, regenerable from `make_template.py`, stamp `434c0cf56d8f` |
| Three test assets | **three of three, all real.** smelter and power_pole approved and pinned; chest rendered and awaiting approval. No proxies remain. |
| A consistency verdict | **given** (§11), on three real assets. Value: agrees. **Hue: does not** — oak spreads 0.090 in chromaticity and the remap is the cause. Not a clean pass, and recorded as such. |
| A prompt template | **done** — [`PROMPTS.md`](PROMPTS.md) |
| `art/PIPELINE.md` | this file |

The three assets were chosen to expose different failure modes and they did:
the smelter proved the 2×2 path, the emission mask and the palette matcher; the
pole proved the tall-thin path, `fit: height`, and — expensively — that the
silhouette is the gate; the chest proved the 1×1 TEXTURED path, which had only
ever been walked by a placeholder, and tested `K = 6 × members` at its low end
where it turned out to be under-resolved but invisibly so.

Each one broke something different, which is what choosing them for failure
modes was supposed to achieve.

### What actually cost the most

Not the rendering. Every real problem this session was a **measurement** problem,
and the same shape recurred four times: *the review was looking at the wrong
thing.*

- A pole passed four reviews at 4× and failed instantly as a silhouette (§23, §26).
- Shadow opacity judged at 4× reads as an opaque rectangle at 32 px (§27).
- A states sheet built from the lit render judges pixels that never ship (§29).
- A region metric built from a geometric box measured mostly not-the-box (§30).

Two of those were caught only because a number was computed and disagreed with
the story being told about it. The lesson worth carrying: **when a measurement
supports a conclusion you already reached, that is when to check what it
actually measured.**

### Where the ground is soft

- **Three assets is still a thin consistency verdict.** Re-take it at five.
- **The remap corrects value and degrades hue** (§11). It moves all three
  assets' oak FURTHER from target in chromaticity and widens smelter-vs-chest
  disagreement ×2.45. This is the largest known defect in the pipeline.
- **The pole renders at 0.33× the set's oak luminance** — form, not correction
  (§11). Accepted under §25, but it is the number to watch as tall assets
  accumulate.
- **Luminance-only checks pass things the eye rejects.** Run
  `hue_agreement.py` alongside the eye sheet, not instead of it.
- **`K_MIN = 12` is under-resolved for two-member assets**, by measurement, but
  the error is invisible (max 8/255). Raise it if a future low-member asset
  shows visible material disagreement — and expect to re-approve the pole.
- **The prompt palette is advisory** (§14). What binds is material presence and
  distinctness. Do not expect prompting to control colour; the remap owns it.
- **Moving parts are specified, not built** (§9).
- **The nearest-texel rescue is one asset old.** It fired correctly once. Watch
  the RESCUED lines on the next few assets rather than trusting it silently.

### First things to do in session 2

1. **Split the albedo correction into a hue-preserving scalar plus a bounded
   chroma term** (§11). Today's per-channel gain rotates hue by a different
   amount per asset, which is why three timbers read as three materials. This
   changes the pixels of all three approved assets, so it needs its own pass
   and three re-approvals — which is exactly why it was not done inline.
2. Re-take the consistency verdict once five real assets exist, and watch both
   the oak-luminance spread (the pole's 0.33×) and the chromaticity spread.
3. Pole variants for Pole Tiers — start from the equipment-reach note in §11,
   not from colour or silhouette.
4. A rectangular-footprint asset, if one is coming. `footprint_fill` controls
   the long axis only, and the chest already leaves 10.2 px of gap at 1.549:1.

## 32. The split correction: value by scalar, hue only when it is wrong

§11 established that the per-cluster remap corrected value and degraded hue: it
moved every asset's oak FURTHER from target in chromaticity and pushed
smelter-vs-chest from 0.024 in the raw texture to 0.059 after correction. The
cause was structural — `gain = target / observed` per channel constrains value
exactly and hue not at all, because a per-channel multiplicative gain preserves
hue only when its three channel gains are equal.

### The anchor now solves two things separately

```python
scale  = lum(target) / lum(c_eff)          # value: hue-preserving by construction
c_eff  = c_obs + frac * (c_target - c_obs) # hue: bounded, and often zero
gain   = scale * c_eff / observed
```

`frac` is 0 below a **dead zone of 0.030** and ramps to 1 at 0.060.

**The dead zone is not tuned.** 0.030 is the chromaticity distance at which two
samples stop reading as one material — the same threshold `hue_agreement.py`
already flags DISAGREE at. Inside it the chromatic term is exactly zero, not
small, so a member Tripo already got right is left alone and the correction
becomes a pure scalar that cannot rotate hue at all. A tuned constant here
would have been the clamp mistake again.

The ramp rather than a cliff is deliberate: at a hard threshold, anchors at
0.0299 and 0.0301 would get wildly different corrections, making the output
sensitive to measurement noise exactly where it is least meaningful.

Verified at both boundaries: at `frac = 0` the three channel gains are equal to
14 decimal places and chromaticity is preserved exactly; at `frac = 1` the gain
is bit-identical to the old one. **The change is a strict generalisation, not a
different correction.**

What it does per anchor:

| Asset | member | hue d | chromatic term | skew before → after |
|---|---|---|---|---|
| `chest` | weathered_oak | 0.0211 | **0%** | 1.17 → **1.00** |
| `smelter` | weathered_oak | 0.0418 | 39% | 1.46 → 1.17 |
| `smelter` | fieldstone | 0.0406 | 35% | 1.19 → 1.07 |
| `power_pole` | weathered_oak | 0.1276 | 100% | 4.01 → 4.01 |

The chest's oak is the case that mattered and it now receives a skew of exactly
1.00 — Tripo got it right and the correction's only job was to leave it alone.

### Result, judged on cross-asset spread

Success was defined as **reducing the spread**, not reducing each asset's
distance to target: fitting each asset to its own error is what caused the
problem.

| Member | pair | before | after | |
|---|---|---|---|---|
| oak | smelter vs chest | 0.0420 | **0.0278** | −34%, **now agrees** |
| oak | smelter vs pole | 0.0907 | 0.0843 | −7% |
| oak | chest vs pole | 0.0603 | **0.0762** | **+26%, worse** |
| oak | **spread** | 0.0902 | 0.0841 | −7% |
| iron | smelter vs chest | 0.0099 | 0.0059 | −40% |
| iron | smelter vs pole | 0.0532 | 0.0395 | −26% |
| iron | chest vs pole | 0.0433 | 0.0375 | −13% |
| iron | **spread** | 0.0529 | 0.0395 | −26% |

**The defect that was diagnosed is fixed.** Smelter-vs-chest oak — the salmon
against mid brown — drops 34% and lands under 0.030, which is agreement. Every
iron pair improves and iron's spread falls 26%.

**One pair got worse and it should not be glossed.** Chest-vs-pole oak widens
26%. The chest is now left alone in the dead zone, where before it received a
hue rotation that happened to carry it toward the pole. It moved closer to
target (0.0829 → 0.0673) and further from the pole at the same time, because
the pole is nowhere near target and cannot be brought there.

### What this exposes: the pole's oak is a SOURCE problem

The pole is unchanged by this work — its oak was at 100% chromatic term before
and after — and it alone holds oak's spread at 0.084. Its raw hue is 0.1276
from target at the anchor and its rendered region sits 0.1432 away **even at
full correction**.

Full correction lands the ANCHOR on target. It cannot land the REGION on
target, because a multiplicative gain preserves every texel's ratio to the
anchor, so a region whose colour distribution is skewed keeps that skew. When
the source wood is strongly orange and blue-deficient — the pole's raw oak
chromaticity is (0.623, 0.321, 0.056) against a target B of 0.125 — no
per-cluster gain can fix it.

That is outcome **(c)** from the §11 diagnosis, and removing (a) is what
exposed it. **It belongs in the style core as a prompt rule — "timber reads
brown, never pink or orange" — not in the pipeline.**

### How visible is any of this

| Asset | mean Δ | p95 | max |
|---|---|---|---|
| `chest` | 2.22/255 | 3 | 4 |
| `smelter` | 2.45/255 | 5 | 6 |
| `power_pole` | 0.33/255 | 2 | 4 |

Small. This is a correctness fix that makes the pipeline stop introducing
disagreement, not a visible restyling — and at three assets the largest
remaining disagreement is now source, not correction. The value of it is that
it does not compound: every future asset whose hue Tripo gets right will now be
left alone instead of being rotated away from the set.
