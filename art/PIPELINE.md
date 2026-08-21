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
    states/                per-state material/light hooks
  tools/                   system Python (needs Pillow + numpy)
    downsample.py          premultiplied LANCZOS downsample
    sheet.py               contact sheets on neutral mid-grey
    rotation_test.py       the 4-renders-vs-2D-rotation comparison
    keymask.py             validates the magenta emission mask on a real texture
    detail_density.py      feature count per tile + high-frequency survival
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

## 6b. Detail-density conformance

Two numbers, both from `art/tools/detail_density.py`. Conformance is judged per
asset against the budget; it does not need the other assets to exist.

```bash
python art/tools/detail_density.py smelter_idle chest power_pole
```

**Feature count per tile**, against the cap of six. Counted at *final* sprite
resolution, because that is where "readable" is decided: Sobel edge magnitude →
threshold → connected components of ≥3 px, reported at three thresholds so the
figure is not one lucky cutoff.

**High-frequency survival.** Rendering at 4× and downsampling cannot carry any
spatial frequency above one quarter of the master's Nyquist limit. The tool
takes the 4× master, measures its power spectrum, and reports the fraction of
AC energy above that cutoff — energy destroyed no matter how good the filter
is. The opaque region is cropped, its surround filled with the mean opaque
luminance so the silhouette does not ring, and a Hann window applied.

Measured:

| asset | features/tile (p85) | HF energy destroyed |
|---|---|---|
| **smelter** (real, cobbled) | **8.75** — 1.46× over cap | **14.3%** |
| chest (proxy, flat-shaded) | 3.00 | 2.1% |
| power_pole (proxy, flat-shaded) | 11.00 | 2.6% |

The kiln throws away roughly **seven times** the spectral energy of flat-shaded
geometry. That 14.3% is generation effort that provably cannot reach the
screen — the cobble problem as a number.

Two caveats worth stating. The proxies are untextured flat-shaded geometry, so
~2% is a *floor*, not a realistic target for a textured asset; the real
threshold should be set when the first compliant Tripo asset lands. And the
power pole's high feature count is an artefact of a thin object being measured
per-tile — density metrics need care on assets that do not fill their footprint.

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

### What ships today

Until the mask passes on a real generation, the smelter ships on the **emitter
fallback**: a warm point light placed in the furnace mouth from `glow_at` in the
manifest. One coordinate per asset, nothing required of the texture, and it
lights the real recessed geometry rather than faking a glow. It is not
deprecated — per-asset emitter placement goes away only once the mask is
validated. `smelter_idle` and `smelter_smelting` are otherwise pixel-identical,
which is the whole point.

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
