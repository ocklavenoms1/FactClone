# Stewardship art pipeline — Tripo → Blender → sprite

How a building goes from a prompt to a PNG the game can draw. Reproducible by
someone who was not here.

Nothing here touches Godot. This pipeline emits PNGs and JSON sidecars; the
sprite-loading layer is a separate session.

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
6. Judge `art/renders/verdict_truesize.png` **at 100%**. Never at 4×. A sprite
   that only works magnified does not work.

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

## 11. Status

| | |
|---|---|
| Camera calibration | **PASS** — emissive 1×1 plane measures 32×32 |
| Real Tripo assets | **1 of 3** (smelter). Chest and power pole are proxies. |
| Consistency verdict | **pending** — needs all three real |
| Smelter art direction | **REJECTED**, regenerate from `PROMPTS.md` |
| Smelter detail density | **FAIL** — 8.75 features/tile vs cap 6; 14.3% HF energy destroyed |
| Emission mask (magenta) | **built, validated analytically** (15× margin); awaiting a real generation to key on |
| Shipping state mechanism | per-asset `glow_at` emitter — **not deprecated** until the mask passes |

The pipeline is complete and verified end to end. What it now needs is assets:
three concept images in one batch, verified by silhouette, through Tripo
image-to-3D. Everything up to that point has passed.

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
