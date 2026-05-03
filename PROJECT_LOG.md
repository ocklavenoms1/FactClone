# Stewardship — Project Log

Reverse-chronological. Newest session at the top. Update this file at the end of every session as part of the commit — the session isn't done until the log is updated.

Each entry has three sections:
- **What shipped** — features, files added/removed, schema bumps, things you can point at in the diff.
- **Decisions** — architectural choices made and the reasoning. The "why" that wouldn't be obvious from the code.
- **Lessons** — what we got wrong, what we learned, what to do differently. Anti-patterns earned through pain.

---

## Worldgen Stage 1 — patch placement, distance gating, procgen rehydration

**Date:** 2026-05-02
**Tag:** `session-worldgen-stage1`

The first of multiple staged worldgen sessions. Stage 1's scope: seeded deterministic generation of a finite 512×512 world with seven resource types, distance-scaled deposit abundance, and exploration loop via distance-gated resource availability. Stages 2-5 (chunked infinite, biomes, mining, etc.) deferred to their own future sessions.

### What shipped

- **`scripts/world/world_generator.gd`** (NEW, ~370 lines) — patch-placement worldgen. 32×32 region grid (Factorio chunk size, forward-compatible with Stage 3 chunked); per-region rolls for patch presence, type, position, size, with `seed + offset` hash3 for each independent random source. Lakes and forests as separate cluster passes. Spawn safety net (floor + ceiling) clamps spawn-area water to [12, 900] tiles. **Single shape-perturbation noise** for organic boundaries, shared across all patches and lakes. Generation runtime ~80-130ms per fresh world.
- **`ResourceNodes` enum populated**: `TREE`, `STONE`, `COAL`, `IRON`, `COPPER`, `CLAY`. `is_renewable()`, `is_ore()`, `name_of()`, `color_of()` helpers. Per-design Q1: trees + ore both go through `resource_node` for identity; per-tile state (richness, growth) lives in a parallel sparse `resource_state: Dictionary` on GridWorld. Most tiles have no state entry (defaults).
- **Distance-gated resource availability** (the exploration loop):
  - Stone, Clay: `MIN_SPAWN_DISTANCE = 0` — available at spawn
  - Coal: 30 tiles — early game
  - Iron: 50 tiles — mid game
  - Copper: 100 tiles — advanced
  - Operates on **region-center distance**, not tile distance. Patches whose home region is past the threshold can still have edge tiles spilling slightly inward; this is an organic outcome rather than a half-moon-clipped boundary.
- **Patch shape**: perturbed circle. Base radius `lerp(MIN, MAX, size_roll)` × distance multiplier. Per-tile shape-noise perturbation gives organic edges (`±SHAPE_PERTURB_AMOUNT * radius`). Within-patch richness `intensity = 1 - (dist/radius)²` (inverse-square fade from center) × `BASE_RICHNESS[type]` × distance multiplier from world origin.
- **Per-resource BASE_RICHNESS** (Q3 design — differentiated Day 1): Stone 80 (commodity), Coal 60, Iron 50, Copper 50, Clay 40 (rarest). Each resource has a distinct yield-per-tile profile that gives gameplay character without requiring per-resource tuning.
- **Trees as forest clusters AND ambient scatter** (Path B refinement):
  - 6-10 forest clusters per world, radius 8-25 tiles, density falls off quadratically from PEAK 0.6 at center
  - Ambient scattered trees on plains modulated by low-frequency density noise (frequency 0.005, base probability 0.002, multiplier 0.5×–2.0× by density). "Lightly wooded grassland" vs "open plains" regions instead of uniform speckle.
  - Combined: forest clusters as destinations, ambient trees for visibility-from-spawn and plains variety. ~2400 trees total per world (~0.9% of map).
- **Save format v10 → v11.** New top-level fields: `world_seed: int`, `worldgen_version: int`. Tile data shape changed: `tiles` → `tile_modifications` (only player-modified tiles persist). Load procedure: read seed → run `WorldGenerator.generate()` to rebuild canonical world → apply `tile_modifications` on top → restore buildings/player/progression.
  - **Save sizes scale with player effort, not world size.** Pristine map ≈ 1KB save; late-game ≈ tens of KB. Compare to a hypothetical "save every tile" v11 = 1-2 MB even on a fresh world.
- **`worldgen_version: int`** with policy comment: any change to generation logic requires bumping VERSION; saves hard-fail on mismatch. Forces every change to be deliberate. Currently at v3 (started v1 per-tile-noise, v2 patch placement, v3 added ambient trees).
- **Spawn safety net** (floor + ceiling): `_ensure_spawn_area_water` adds a 4×4 lake at a seeded-pick eligible grass position if spawn 60×60 box has < 12 water tiles. `_clamp_spawn_area_water_max` removes excess water (edge tiles first, seeded shuffle within ties) if > 900 tiles (25%). 0 violations across 50-seed sample in either direction.
- **Q-inspect for resources** (`info_panel.gd` extended): hovering a tile with a resource_node and pressing Q shows `Stone @ (pos)` / `Richness: 247` / status, or `Tree @ (pos)` / `Mature (renewable)`. Auto-closes when player paints over the tile or removes the resource. Building inspect takes priority when both apply.
- **Rendering**: ore deposits as inset filled rectangles (90% of tile, darker outline), trees as canopy circle + brown trunk rect with per-tile color/size jitter. Drawn between terrain overlay and grid lines (so ore visible on grass; player overlay obscures ore visually but data preserved).
- **Tile struct**: unchanged shape (base / overlay / resource_node). `set_overlay` and `clear_tile` updated to write to `tile_modifications` so saves preserve player edits. Player-paint preserves any existing `resource_node` (overlay obscures visually; RMB-clear reveals).
- **Tests**: 15/15 passing.
  - **NEW** `test_worldgen_determinism` — generate seed=42 twice, assert identical tile/resource_state/seed across runs
  - **NEW** `test_worldgen_distance_scaling` — far-band ore richness must be ≥3× near-band (locks in the exploration loop economic curve)
  - **NEW** `test_worldgen_spawn_safety` — 20-seed sample, all spawn-area water counts in [12, 900]
  - **NEW** `test_random_seed_save_roundtrip` — random seed persists through save→load
  - **UPDATED** `test_save_load_roundtrip` for v11 schema (seed round-trip, tile_modifications shape, procgen rehydration produces identical world)
  - **UPDATED** `test_placement_rules` — removed hardcoded-lake assertion block (lake is no longer at fixed coords)
- **Removed**: `GridWorld.generate_default_world()`, `DEFAULT_LAKE_X_RANGE`, `DEFAULT_LAKE_Y_RANGE`. Hardcoded Session-B lake at (8..11, 4..5) is gone.

### Decisions

- **Patch placement, NOT per-tile noise** (architectural rewrite mid-session). First implementation tried per-tile noise threshold checks for ore — produced speckled terrain regardless of threshold tuning. Threshold + frequency tuning could halve density but couldn't change the spatial pattern from "scattered everywhere" to "discrete patches in mostly-empty terrain." The architectural shift to per-region patch placement was the actual fix; tuning thresholds further was pushing on the wrong lever. Documented as a real lesson below.
- **32×32 regions, not 64×64.** 64×64 regions = 64 patches in a 512×512 world, average 100+ tile spacing — too sparse for the exploration loop. 32×32 = 256 regions, ~128 patches at 50% probability — patches every 30-100 tiles. Matches Factorio's actual chunk granularity. Stage 3 chunked generation will use 32×32 as both region and chunk size — single primitive.
- **Distance gating on region centers, not tile distance.** Cleaner abstraction: a region either rolls for a resource or doesn't. Patches can extend beyond their home region via shape perturbation, so some tiles spill into the eligible band — accepted as organic rather than half-moon-clipped boundaries. Spillover is small (<5%) and visually invisible.
- **Lake-before-ore iteration order.** Ore patches abort if their region's center cell is water (avoids half-moon ore patches around lake edges). Forests run after both — they fill remaining grass.
- **Tie-breaking via highest normalized noise intensity** (Q4 design, applied to per-region weighted-pick). Each region's type roll is over the eligible weighted set; no priority-rank artifacts.
- **Trees: forest clusters + ambient pass.** Path A (forests only) was tried; player saw zero trees from many spawns because cluster count is low and clusters scatter across 512×512. Path B added a low-density ambient scatter modulated by low-frequency density noise — "lightly wooded grassland vs. open plains" variation. Forest clusters remain destinations; ambient trees give visibility-from-spawn and plains character.
- **Procgen rehydration save model.** Saves persist `world_seed` + `tile_modifications`; load regenerates canonical world from seed and applies modifications. Directly aligns with Stage 3's chunked-infinite save model — same architecture, different chunk count. Also: save sizes scale with player effort instead of world size.
- **Cellular noise abandoned with reasoning, not punted.** Original design called for cellular F1 on stone/clay (crisp Voronoi boundaries = "rock formations") vs Perlin on ores. Investigation revealed: (a) `RETURN_CELL_VALUE` works mechanically (the original "doesn't threshold" framing was wrong — that was `RETURN_DISTANCE` having a lopsided range), but (b) cellular cells produce uniform-within-cell noise, which combined with distance scaling would produce ~6M ore per corner cell — 30× over the 200K target. The "crisp rock vs soft ore" visual distinction is actually about visual style, not noise math; that distinction belongs in sprite art when sprite migration lands, not in noise type. Documented in `world_generator.gd` so future-self doesn't re-litigate this when revisiting.
- **`screen_px()` helper still used selectively** (for hover outline only) — unchanged from camera-zoom session.
- **`worldgen_version` separate from `SAVE_VERSION`.** Two version axes: save schema (changes when serialized field shape changes) and worldgen logic (changes when noise math / iteration order / parameters change). Both must match on load. Allows tightening worldgen without churning the save format and vice versa.

### Lessons

- **Per-tile noise vs patch placement is an architectural decision, not a tuning knob.** Mid-session pivot from per-tile noise to patch placement was correct but cost ~half a session of tuning effort that produced "less wrong" results without ever producing "right." When the tuning curve flattens but the visual still feels wrong, step back and ask whether you're tuning the right abstraction. Per-tile noise → speckle, no matter the parameters. Per-region rolls → discrete features, naturally.
- **The "first 30 seconds" of a new world matters disproportionately.** With clusters-only trees, most spawns saw zero trees — felt like a broken world even though it was working as designed. Path B (clusters + ambient) was a small change (~30 lines) with a large UX payoff. Lesson: when a game-feel mechanic is "discrete events that the player must travel to," ALSO add an ambient layer for visibility-from-spawn so the player knows the discrete events exist.
- **`RETURN_DISTANCE` ≠ `RETURN_CELL_VALUE` in Godot's FastNoiseLite.** The cellular config bug at first looked like "cellular doesn't work for thresholds" — actually was the wrong return type. RETURN_DISTANCE has range -0.90 to -0.17 (lopsided, reverse-thresholdable); RETURN_CELL_VALUE has range -1..1 like Perlin. Empirical probe (10K samples per config) was the cheap way to diagnose. Lesson: when a noise system "doesn't work," sample it before assuming it's broken.
- **Procgen rehydration is the architecture you ship NOW for Stage 3 reasons.** Even though Stage 1 is finite (512×512), the save format change v10 → v11 implements the model that Stage 3 needs anyway. Doing it later would mean v11 → v12 with migration burden. Doing it now means Stage 3 inherits the architecture for free.
- **Two version axes (save_version + worldgen_version) is the right shape.** Bundle them and you can't change worldgen without bumping save schema (which is wrong — the schema didn't change, only the procgen output). Independent axes let each evolve at its own cadence with both required to match on load. Both bump 1 → 2+ trivially when the relevant subsystem changes.
- **The `MIN_SPAWN_DISTANCE` exploration loop took two architectures to land.** First attempt: per-tile distance check inside per-tile noise loop. Worked mechanically but didn't produce the FEEL because resources were still everywhere. Second attempt: per-region distance check (a region either rolls for the resource or doesn't, before any noise is sampled). Same gameplay rule, different abstraction level — the second one produces the actual exploration mechanic. Lesson: gameplay mechanics often don't manifest until the architecture matches the mental model.
- **Headless smoke iteration was the correct loop.** Pre-rendering smoke (`worldgen_smoke.gd`, deleted before commit) ran in <1s and let us iterate on noise tuning, threshold tuning, density tuning, and architecture choice without ever launching the full game. The "design pass → smoke → architectural pivot → smoke → another pivot" cycle would have been intolerable if every iteration required launching the game and walking around.
- **The MCP "screenshot live game" capability earned its keep.** The first "I don't see trees" report was visual; data said trees existed, screenshots showed they were 50+ tiles from spawn. Distinguishing "rendering bug" from "they're just over there" required real visual evidence. NOTES.md flagged screenshot as the only confirmed live-state path; this session validated the call.

### Migration

Save format v10 → v11. **All existing v10 saves hard-fail on load** with `OS.alert` per the existing schema-bump policy. Player must delete `%APPDATA%\Godot\app_userdata\Stewardship\save_slot_1.json` and start fresh. The new world is procedurally generated with a random seed at fresh start.

### Stage roadmap (from session brief, for context)

- **Stage 1 (this session):** finite 512×512 deterministic worldgen with patch placement, distance gating, procgen rehydration save model.
- **Stage 2** (future): seed selection menu / new-game UI. Currently random per fresh start; player can't pick a specific seed without code edit.
- **Stage 3** (future): chunked infinite generation. World expands beyond 512×512; chunks generate on-demand within view radius; save persists `tile_modifications` per chunk. Architecture in place — `WorldGenerator.generate()` becomes per-chunk; the same patch-placement primitive runs.
- **Stage 4** (future): biomes. Currently single grassland biome; Stage 4 adds desert/forest/tundra/etc. with biome-specific resource availability and visual themes.
- **Stage 5** (future): mining mechanics. Quarry/Sawmill/Smelter buildings extract richness from deposits over time. `resource_state.richness` decrements; deposits deplete; tree clusters regrow over time. Hooks already in place via the renewable/finite distinction.

### Known follow-ups (carried forward)

- **Exploration UI: M-key map + fog-of-war** — next session. Modal fullscreen map; tracks explored regions in save; shows terrain/resources/buildings within explored areas; unexplored renders as fog. Future: radar buildings extend exploration radius. Standalone scoped feature, deserves its own design pass.
- **Sprite migration** — long-term solution to placeholder-rect rendering. When sprites land, the "crisp rock vs soft ore" visual distinction (deferred from Q3 cellular investigation) implements via sprite art rather than noise type.
- **Chunked save (Stage 3)** — architecture already supports it via `tile_modifications`; needs per-chunk save partitioning + on-demand generation when ready.
- **Cloth chain `prefer_dir` polish** (still open from Session E): lower priority now that worldgen is in place; cloth-related polish whenever it next bites in playtest.

---

## Polish session — cloth chain prefer_dir + hover-outline minimum-pixel-floor

**Date:** 2026-05-02
**Tag:** `session-polish-1`

Two carried-forward issues closed in one session: (1) the cloth chain ergonomic wart from Session E (no `prefer_dir` ports → fragile to "added a chest, chain stopped"), and (2) the camera zoom session's known limitation (hover outline fades to sub-pixel anti-aliased lines at extreme zoom-out). Polish, not new content.

### What shipped

- **Cloth chain `prefer_dir` ports.** All three cloth recipes now declare canonical-east ports — input from W, output to E — matching the bread chain authoring convention. Buildings rotate at runtime via `Buildings.world_dir()` so the F11 demo's south-running layout works with `dir = DIR_S`.
  - `retter_fiber`: flax (W) + water (no prefer_dir) → fiber (E)
  - `loom_cloth`: 3 fiber (W) → cloth (E)
  - `tailor_bag`: 4 cloth (W) → bag (E)
- **`supports_direction: true`** on `Type.RETTER`, `Type.LOOM`, `Type.TAILOR`. R-key now rotates them in placement preview and in-place via the existing hover-rotate flow.
- **`Retter.make`, `Loom.make`, `Tailor.make`** updated to accept `dir: int = 0` and thread it to `Processor.make_state(recipe_id, dir)`. Building dispatch in `Buildings.gd::make()` updated.
- **F11 demo cloth chain rotated south:** `cloth_plan` in `main.gd` now sets `dir = BLT_S` on the three cloth processor entries. Canonical W input rotates to world N (pulls from belt above), canonical E output rotates to world S (pushes to belt below). Water input has no prefer_dir, so the shared pipe network still feeds the Retter regardless of rotation.
- **Hover-outline minimum-pixel-floor:** `grid_world.gd::_draw()` hover rect outline width changed from a literal `2.0` world units to `screen_px(2.0)`, which returns `max(2.0, 2.0 / camera.zoom.x)`. At zoom ≥ 1, world-unit width wins and the outline aligns exactly to tile boundaries (the camera-zoom session's "outline matches tile" criterion preserved). At zoom < 1, the floor kicks in so the outline never falls below 2 screen pixels — visible at extreme zoom-out instead of sub-pixel anti-aliased.
  - Trade-off accepted: at zoom 0.85 (min), the outline now overshoots the tile by ~0.18 world units (~0.15 screen pixels) per side. Much smaller than the pre-camera-zoom-session overshoot bug; visibility win outweighs it.
- **`screen_px()` helper** is now actually used (was "kept but unused" per NOTES.md after the camera zoom session). Comment rewritten to clarify per-call trade-off — used selectively for hover, NOT for grid lines / port dots / building borders (those stay in world units to match tile boundaries exactly).
- **New test `test_cloth_prefer_dir.gd`**, +1 to suite (11/11 passing). Two cases:
  - Case A (`dir = 0`): pre-load Retter `out_buffer` with fiber, place belts at N and S only (NO E belt), tick 1500. Assert: both N and S chests stay empty, fiber stays in `out_buffer`. Locks in "prefer_dir is strict — items go to the declared port or wait, no fallback."
  - Case B (`dir = S`): same setup, rotate Retter south. Assert: S chest gets ≥9 fiber, N chest stays empty (no canonical W output declared, only input). Locks in "rotation routes the output to the right edge."
- **Save schema unchanged at v10.** No structural change; rotation is data on existing `state.dir` field with defensive `state.get("dir", 0)` reads everywhere.

### Decisions

- **Canonical-east everywhere.** Considered making cloth canonical-south to match the F11 demo layout. Rejected — would split authoring conventions across the codebase. Bread chain is canonical-east; cloth follows the same. The F11 demo carries the rotation flag, which is one column in `cloth_plan`.
- **Retter water input stays without `prefer_dir`.** The original ergonomic complaint was about solid outputs (chest stealing fiber). Water arrives via the shared pipe network; adding a fluid prefer_dir would lock it to one side and force re-routing the shared network. Out of scope for a polish pass; matches Mixer (also no fluid prefer_dir).
- **R-key rotates in place — no remove+replace migration.** Confirmed by reading `main.gd::152-173` before locking in the migration story. Defensive `state.get("dir", 0)` reads everywhere mean old saves load cleanly with implicit east-facing; player rotates each cloth processor with R until "Facing: S" appears. Three R-presses per processor.
- **Hover-outline floor uses `screen_px(2.0)`, NOT a new formula.** The helper already exists; reusing it consumes the "kept but unused" flag from NOTES.md. Inline comment documents the per-call trade-off so the next person reading the code knows why hover uses screen_px and grid lines / port dots don't.
- **Negative-assertion test pattern.** `test_cloth_prefer_dir.gd` Case A asserts the chain DOESN'T work at `dir = 0`. Catches regressions where someone removes `prefer_dir` from `retter_fiber` (Case A would fail because fiber would push to N or S). Pairs with the existing `test_thresher_rotation.gd` pattern.

### Lessons

- **Verify before locking in migration story.** First instinct on R-key migration was "remove + replace each cloth processor." Two minutes of reading `main.gd::152-173` revealed R rotates in place when hand is empty — much cleaner migration ("press R three times"). Don't write migration docs from memory of how a feature MIGHT work. Read the relevant code first.
- **Polish sessions are real sessions, not afterthoughts.** Two small carried-forward items + tests + logs is ~90 minutes of work. Worth doing as its own session with its own tag rather than bundling into the next big session — keeps PROJECT_LOG entries scoped and makes it possible to bisect a regression to "the polish session vs Session F."
- **The `screen_px()` helper was the right tool for the right job.** The camera zoom session reverted nearly every screen_px usage to world-unit literals. Correct call for grid lines / port dots / building borders (where overshoot proportionally matters). Wrong call for hover outline only — the hover-outline overshoot at low zoom is ~0.15 screen pixels per side, way under perception threshold, and the visibility win at extreme zoom-out is real. Per-call dimensional choice, not blanket rule.
- **The "kept but unused" flag in NOTES.md was a future-self breadcrumb that worked.** Camera zoom session left the helper in place specifically anticipating this fix. Removing dead code is good general policy; leaving it with a "future use case X" comment is sometimes better.

### Migration (read this if you have a v10 save with cloth chain content)

Any cloth processor placed before this session was placed with `dir = 0` (east-facing). Inputs and outputs were both routed by "any neighbor accepts" before this session; now they're routed strictly by `prefer_dir`. **Old saves load cleanly** (defensive `.get("dir", 0)` reads everywhere) but **the cloth chain stops producing** until each Retter / Loom / Tailor is rotated to face south.

**Fix:**
1. Hover the Retter with empty hand. Press R three times until toast says "Retter rotated to S".
2. Repeat for Loom and Tailor.
3. Chain resumes within ~30 seconds.

This applies to **any v10 save with cloth processors**, including F11-spawned chains placed before this session. The save file isn't corrupt; the processors just need their orientation set. Alternative: delete the save and re-spawn with F11 (the demo now spawns them rotated south).

The save schema does NOT bump (still v10). Old saves work fine; rotation is the only manual step.

---

## Camera zoom session — pop the stash, diagnose displacement, ship

**Date:** 2026-05-02
**Tag:** `session-camera-zoom`

The deferred zoom feature from late Session D, stashed when the displacement bug couldn't be characterized at the time. Popped, conflict-resolved against three intervening sessions of main.gd churn, diagnosed (sub-pixel jitter from non-integer zoom × fractional camera position), fixed.

### What shipped

- **Mouse wheel zoom in/out**, smooth-lerped via `target_zoom` toward `camera.zoom` at 12/sec convergence rate.
- **Zoom range:** `[0.85, 6.75]` clamped per wheel notch (×1.15 multiplier). Range computed against the 1080-px viewport short axis: 0.85 ≈ ~40-tile factory overview, 6.75 ≈ ~5-tile detail.
- **Modal input gating:** wheel zoom suspended while the inventory grid is open. Implicit via `MOUSE_FILTER_STOP` on the InventoryGrid Control catching all mouse events; explicit guard in `main.gd::_unhandled_input` makes the design intent visible if the mouse_filter ever changes.
- **Smooth-lerp loop runs regardless of modal state** — pure visual update, so an in-flight zoom-out animation completes even if the player opens inventory mid-scroll. Placed before the modal early-return in `_process`.
- **Pixel-snap rendering settings** added to `project.godot`:
  - `rendering/2d/snap/snap_2d_transforms_to_pixel = true`
  - `rendering/2d/snap/snap_2d_vertices_to_pixel = true`
  Both required — transforms-only wasn't enough; per-vertex snapping closed the remaining sub-pixel jitter.
- **Outline widths reverted to world-unit literals.** Earlier stash version used `screen_px(N)` to keep outlines at constant screen-pixel size. At low zoom, that overshot small tiles by a relatively large proportion, looking like overlay-doesn't-match-tile. Reverted to plain world-unit widths so outlines scale with the tile and stay visually flush at every zoom level. Trade-off: at extreme zoom-out, outlines fade to sub-pixel anti-aliased lines (visible but thin); see "Known limitations" in NOTES.md.
- **Tests:** 10 passing throughout. No new tests added (zoom is pure render-layer; can't be unit-tested without scene-tree instrumentation).

### Decisions

- **Pixel-snap globally via project setting, not manual camera snap.** Considered manually snapping `camera.position` each frame to keep `camera.global_position * camera.zoom.x` integer. Rejected: that would jitter the player's screen position relative to the camera (player follows world coords, camera would snap to fractional offsets). Project-level pixel snap is the cleaner Godot-native fix.
- **Outline widths in world units, not screen pixels.** Per the user's verification spec: "hover box exactly matches tile at every zoom level." Screen-fixed outlines overshoot small tiles. World-unit outlines scale correctly. Outline readability at extreme zoom-out is the secondary concern; documented as a known limitation.
- **`screen_px()` helper kept (unused).** Future in-world overlays that genuinely need constant screen-pixel size could call it. Cheap to keep; removing it later if dead-code accumulates is trivial.

### Lessons

- **Stash conflicts after multi-session intervening work were small but non-trivial.** The zoom stash was created mid-Session-D, popped after Session E final + Inventory UI shipped. main.gd had two purely-additive conflict regions (constants + _ready init); buildings.gd and grid_world.gd applied cleanly. Bounded conflict + decision-rule worked: "1-2 small hunks → resolve in place." Concatenating both sides was the fix.
- **Stale Godot processes are a real problem on Windows.** Two zombie Godot processes from earlier sessions held the file system lock and showed pre-fix code despite multiple kill+relaunch attempts. The user's "2-tile-wide hover" report turned out to be stale-build display, not a code bug. Lesson: when a fix isn't reflected in the live game, force-kill ALL Godot PIDs (not just by image name; PID-specific) before relaunching. `taskkill /PID N /F` works after `taskkill /IM ... /F` doesn't if the process is in a hung state.
- **Outline widths and overlay sizes are different concerns.** First instinct was "scale outline width with zoom for readability" → led to overshoot bug. Correct framing: overlay POSITION + SIZE in world coords (so they match world objects), outline WIDTH same dimensional space as overlay (so they don't visually drift). Mixing screen-fixed and world-fixed dimensions in the same draw is where the bug hid.
- **NOTES.md predicted the displacement cause exactly.** "Likely culprits: sub-pixel rounding in screen_px()-scaled draw widths, or camera position not snapped to integer pixels at low zoom." Both turned out to be involved. Worth keeping the diagnosis-while-you-stash discipline going for future stashes.

### Known limitations

- **Outlines fade at extreme zoom-out.** At zoom 0.85, a 2-world-unit hover outline = 1.7 screen pixels (sub-pixel anti-aliased). At default zoom 1.5, 3 px (clear). At max zoom 6.75, 13.5 px (chunky but proportional). Trade-off accepted in this commit; documented in NOTES.md with "minimum-pixel-floor" as a future fix option.
- **Player movement at low zoom feels less smooth.** Pixel-snap rounds the player avatar's screen position to whole pixels each frame. At zoom 0.85 this can produce a slight 1-pixel "stairstep" when moving diagonally. Acceptable; consistent with the rest of the visual style.

---

## Inventory UI session — Factorio-style slot grid + chest paired view

**Date:** 2026-05-02
**Tag:** `session-inventory-ui`

The deferred UI work captured in `INVENTORY_UI_PLAN.md`. Replaces the aggregated inventory display with a slot grid that surfaces the per-slot reality of `Inventory` storage (which has always been correct internally) and adds two-way item transfer between player and chests via paired-grid view.

### What shipped

- **`InventoryGrid` modal Control** (`scripts/ui/inventory_grid.gd`, ~480 lines) — full-screen dim overlay + centered grid panel, opens with `I`, closes with `I` / `Esc` / click-outside.
- **4-column grid layout**, +1 row per bag consumed (4×4 base, up to 9×4 at cap). Each bag's reward is **visually obvious** as a new row appears at the bottom.
- **Slot rendering**: empty/filled/hovered states from the hotbar palette. Item swatch (32px centered in 48px slot). Stack count overlay bottom-right with shadow. Tooltip on hover (`ItemName: count / max_stack`).
- **Click pick / place / combine / swap** within the player grid. Cursor stack follows mouse position; `Inventory.add()` semantics for combining; swap on cursor-vs-different-item-type.
- **Auto-return on close** with cursor non-empty: place into player's first empty slot, toast announcing the slot. Falls back to chest if player full and chest paired view is open. If both full, refuse close + toast `Place cursor stack before closing inventory.`
- **Chest paired view** — `E` adjacent to a chest opens player + chest grids side-by-side. `E`/`I`/`Esc` closes both. Replaces the old "drain all" behavior on chest E (harvesters and other drainables continue to drain on E unchanged).
- **Edge case**: pressing `E` on chest with cursor stack already held → place cursor into chest first (via `Chest.try_insert`), then open the paired view. Avoids the "open mid-pickup" ambiguity.
- **Chest view adapter (Path A)** — chest `state.bag` (bulk storage, no per-slot positioning) is split into `max_stack`-sized virtual slots for display. Slot positions don't persist across re-renders (chest reorders after each change). Acceptable per design; migrate to per-slot chest storage later if it becomes painful. View adapter extracted as a static method for unit testability.
- **Cross-grid transfers**:
  - Left-click chest slot with empty cursor → pick up that view.
  - Left-click any chest slot with full cursor → drop cursor into chest bag (with capacity check). Optional swap if slot was already occupied.
  - Shift-click player slot → entire stack to chest (partial transfer if chest has limited capacity, toast on partial).
  - Shift-click chest slot → entire view to player via `Inventory.add()` (respects player max_stack across slots; partial transfer + toast if player full).
- **Modal interaction discipline**: while grid is open, world clicks blocked, player movement frozen (`player.gd` gates on `inventory_grid.is_open()`), hotbar / placement / save / interact / consume input suspended. Only `I` and `Esc` continue to fire (to close). Game tick keeps running — factory continues producing.
- **Aggregate panel trimmed**: `Slots: A/B used` line dropped (slot count is now implicit in the grid view). `Bags: X / 5 consumed` line stays (the lifetime cap isn't visible in the grid). Panel narrowed from 280px back to 180px.
- **Tests**: 10 passing. New `test_chest_paired_view.gd` covers view adapter splitting (max_stack-sized chunks, multi-type bags, edge cases) + transfer semantics (player→chest deposit, chest→player pickup with overflow / partial / refuse paths).
- **No save schema change** (still v10). Path A view adapter doesn't touch chest storage shape. Inventory class unchanged.

### Decisions

- **Modal grid, not persistent.** Factorio's persistent quickbar is analogous to Stewardship's existing hotbar (which holds buildings/terrain). The inventory itself is for occasional management — modal-on-demand fits that frequency. Aggregate corner panel stays for at-a-glance monitoring.
- **No "Take All" button on chest paired view.** Original design had it as a v1 hedge. Pushed back during design pass: shipping old+new flow simultaneously means half the design fails to land. Committed to E auto-opens paired view + shift-click for transfer-all. Matches Factorio convention exactly.
- **Auto-return: first empty slot, not original slot.** Naive "return to original" fails when the original slot was modified during pickup (player swapped something into it). First-empty + toast is predictable because the toast always announces what happened. Refuse-close as last resort if inventory genuinely full.
- **Path A view adapter for chest storage.** Path B (migrate chest to use `Inventory` class) was the right end-state but required a v10→v11 schema bump. Path A is ~30 lines of pure-function conversion code with zero schema impact. If players ever complain about slot-arrangement-not-persisting-in-chests, migrate later.
- **4-column grid layout.** +4 slots per bag = exactly +1 row. Bag-cap progression becomes visually obvious as the grid grows downward by one row per consumed bag. Layout choice and mechanic alignment are the same shape.
- **Pick-up-and-place model, not drag-and-drop.** Universal across RPGs / Factorio / Minecraft. Drag adds gesture detection complexity. Defer drag to v2 if pick-up feels clunky; not heard yet.

### Lessons

- **The bug-that-isn't was a vocabulary problem.** "Bag" was used to mean both "openable container item" and "player's inventory slot count," and we built the wrong thing for almost a session before the unstick. Lesson recorded: when scope feels off, re-derive the user-facing problem statement before going deeper.
- **`draw_string` HORIZONTAL_ALIGNMENT_RIGHT positioning is non-obvious.** First-pass count overlay had the alignment rectangle starting at the slot's right edge, which drew text past the slot boundary. The text was rendered, just off-screen. Caught at smoke test, not at code review. Lesson: when text positioning looks wrong, instrument with a temporary visible bounding box before iterating on numbers.
- **Pushback on the "Take All" button paid off.** UX hedging would have shipped two flows competing for the same action; either wins out and the unused half gets stripped later anyway. Better to commit to the new flow up front.
- **Static / pure helpers + scene-tree-free tests.** The view adapter's split logic was extracted as a `static func` so the test could call it with synthetic bags. No `add_child` / scene tree gymnastics. Worth keeping as a pattern for future UI testing — anything pure should be hoisted out.
- **Modal input gating is small but easy to miss bits of.** `player.gd` gates movement; `main.gd` gates hotbar / placement / interact / save. Each was ~one conditional. The risk was forgetting one and having the player walk off mid-modal. Caught everything in the smoke test on the first try because the test included "press 1-9 with grid open should do nothing."

### Known follow-ups (carried forward, unchanged where applicable)

- **Camera zoom (stashed):** `stash@{0}`, displacement bug unresolved. Pop-and-debug session.
- **Cloth chain ergonomic wart:** no `prefer_dir` on cloth recipes. Polish session.
- **v2 inventory grid features (deferred):** right-click for half-stack pickup, drag-and-drop, ctrl-click for "transfer one," selected-source highlight on cursor pickup, hotbar item slots (place from hotbar). Each lands when a real need surfaces.
- **Chest storage Path B (per-slot persistence):** migrate `state.bag` to `Inventory` class if "I can't leave a gap in my chest" becomes a real complaint. Schema bump v10 → v11 at that point.
- **Session F:** premium feedback loop (Trough, Coop, premium bread, configurable Oven, score/value system). Score/value is the second `player_progression` field — slots in cleanly without further refactor.

---

## Session E final — Bag-cap progression mechanic

**Date:** 2026-05-02
**Tag:** `session-e-final`

The deferred Session E architectural piece. Bags are consumed by the player to permanently expand inventory, capped at 5 bags lifetime. Sets a `player_progression: Dictionary` pattern that future progression state (score, achievements) can extend.

### What shipped

- **`Inventory.expand(n: int)` primitive.** Generic "grow capacity by N empty slots" — used by bag-cap, but not coupled to it. Future inventory-upgrade mechanics (NPC quest rewards, world-gen chests) can use the same primitive.
- **Bag-cap consume flow on key `B`** with two-press confirm:
  - First press → toast `Consume bag for +4 slots? Press B again to confirm.` 3-second confirm window.
  - Second press within window → consume bag, expand inventory by `SLOTS_PER_BAG` (4), increment `bags_consumed`. Toast `Inventory expanded: X/5 bags consumed, +4 slots`.
  - Window expires silently. Press outside window = fresh first press, re-shows prompt.
  - Decay-before-input ordering in `_process` ensures expiry-frame presses always read as fresh, never stale-confirm.
- **Failure ordering locked in:** cap-reached takes priority over no-bag (cap is the more permanent state — `Inventory at maximum. Save bags for trade.` helps the player stop trying). Documented in code comment + asserted in `test_bag_cap.gd`.
- **`player_progression: Dictionary` on `main.gd`** — single container keyed today by `bags_consumed`. Forward-extensible for score/achievements/research without further parallel `var`s on `main.gd`.
- **Inventory panel header** shows `Bags: X / 5 consumed` — always visible when progression dict is set, gives the player a working anchor for the cap.
- **Save schema v9 → v10.** New top-level field `player_progression: Dictionary`. v9 saves hard-fail with `OS.alert`. Inventory capacity persists implicitly via `Inventory.load_array`'s resize logic; progression dict is the explicit counter.
- **`SaveSystem` refactor:** `load_game` now returns a `LoadResult` class (`success: bool`, `error_message: String`, `player_progression: Dictionary`) instead of `bool`. Eliminates `SaveSystem.last_load_error` static var. Three call sites updated (`main.gd::_ready`, `main.gd::_process` quick_load, `test_save_load_roundtrip.gd`).
- **Tests:** 9 passing.
  - New `test_bag_cap.gd` — three phases: `Inventory.expand` correctness, cap-of-5 lifecycle (5 successes + 6th rejection), failure ordering (cap-priority + no-bag-only).
  - Extended `test_save_load_roundtrip.gd` — non-empty progression (`bags_consumed: 3`) round-trips via the new `LoadResult.player_progression` field. Renamed to "(v10)".

### Decisions

- **`player_progression: Dictionary` rather than flat `bags_consumed: int`.** YAGNI rejected because score/value system is already on Session F's roadmap. One container now sets the pattern; future fields go into the same dict instead of accumulating as parallel main.gd vars.
- **Schema bump v9→v10 instead of deriving `bags_consumed` from inventory size.** Deriving assumes "the only slot source is bags forever." Future mechanics (quest rewards, etc.) could grant slots from non-bag sources, breaking the math. Explicit count matches the player-facing rule "5 bags consumed total."
- **Key `B` + two-press toast confirm, no inventory UI rebuild.** `inventory_panel.gd` is currently `MOUSE_FILTER_IGNORE` and renders aggregated rows (one per item type), not slot-by-slot. Right-click on a bag isn't possible without rebuilding the panel as an interactive grid — out of scope. Two-press toast confirm is mild friction equivalent to a confirm dialog and matches the existing keyboard-driven UX (Q inspect, R rotate, F11 demo).
- **`LoadResult` class instead of static `last_load_error` + `last_loaded_bags_consumed`.** With 3 call sites and a clear "future fields go here" pattern, the bounded refactor was worth doing. Migrated `last_load_error` → `error_message` along with adding `player_progression`. Static load-time state surface is now zero.
- **Decay-check before input-check in `_process`.** Ordering matters: an expiry-frame press always reads as a fresh first press (re-shows prompt), never as a stale confirm. Documented in code so future-me doesn't reorder.

### Lessons

- **"Make a small home now" beats YAGNI when the next field is already on the roadmap.** The instinct was `var bags_consumed: int`. Pushback caught it: `player_progression: Dictionary` costs one line and one access pattern (`int(dict.get(key, 0))`) and saves a refactor when score/value lands. Default to the small home; defend YAGNI only when there's evidence the second field truly won't materialize.
- **Failure ordering is a real design decision, not a coding detail.** With both cap-reached and no-bag failures possible at the same time, picking the priority message was a UX call. Documented + tested rather than left implicit.
- **Smoke tests need a way to skip cold-start cost.** F11 demo + cloth chain takes ~5 minutes to produce a bag. For verification, that's intolerable. Solution: a temp F12 debug spawn that puts 5 bags in inventory directly. Added during smoke test, removed before commit. Convention captured: **debug-spawn keys are a smoke-test pattern, not a feature**; mark them clearly, remove them before the session ships.
- **Save-state staleness causes false-positive bug reports.** During smoke test, the save loaded with `bags_consumed: 5` from earlier testing. Pressing B → "Inventory at maximum" looks like a bug; it was the cap test passing on stale state. Lesson: **clear save before claiming a smoke test pass on a fresh-start scenario**, or build the test to start from known state.
- **`LoadResult` refactor was a bounded refactor with outsized payoff.** 3 call sites, ~30 lines changed. Static-state surface now zero; future progression fields slot in cleanly. The "bounded refactor" sweet spot is "if it's 2-3 call sites, do it"; 10+ would have been the static-var lesser-evil.

### Known follow-ups (carried forward unchanged)

- **Camera zoom (stashed):** `stash@{0}`, displacement bug unresolved. Pop-and-debug is its own session.
- **Cloth chain ergonomic wart:** no `prefer_dir` on cloth recipes — fragile to "I added a chest and the chain stopped." Likely fix is per-recipe prefer_dir + rotation enable. Punt to a polish session.
- **Future inventory UI rebuild:** if/when the panel becomes interactive (slot grid, hover, click), bag consumption can move from key+two-press to right-click + dialog. Mechanic stays the same; UX shell changes. No urgency.

---

## Session E — Cloth chain + F11 demo extension

**Date:** 2026-05-02
**Tag:** `session-e-complete`

Shipped across multiple groundwork sub-slices and one main session:

- `b3185ce` — Session E groundwork: tighten remaining test thresholds.
- `552f4ce` — Session E groundwork: register cloth chain items (FLAX, FIBER, CLOTH, BAG).
- `b25bc8a` — Session E groundwork: register cloth chain recipes (retter_fiber, loom_cloth, tailor_bag) + RETTER/LOOM/TAILOR enum slots.
- `691c7e6` — Session E groundwork: register cloth chain buildings (Retter, Loom, Tailor at 1×1) + Production hotbar entries.
- `01504c5` — note camera zoom feature in SESSION_E_PLAN (deferred to its own session).
- `ec0a2eb` — note zoom-feature WIP stash in NOTES.md.
- (this commit) — Flax Planter hotbar entry, F11 demo extension with shared water network, F11 ergonomics fixes.

### What shipped

- **Cloth chain end-to-end runnable:** Flax Planter (variant of existing Planter via `crop_type` extra) → Harvester → Retter (`flax + water → fiber`, 8s) → Loom (`3 fiber → cloth`, 6s) → Tailor (`4 cloth → bag`, 8s) → Bag Chest. Production rate gated by Flax Planter's 25-second growth cycle; ~5 minutes per bag in steady state.
- **Flax Planter** added as a Production-category hotbar entry (slot 3, between Sugar Planter and Harvester). Reuses existing `Buildings.Type.PLANTER` with `extra: Items.Type.FLAX`. Growth time 500 ticks (25 s @ 20 tps), registered in `Planter.CROP_GROWTH_TICKS`.
- **F11 demo extension:** added a fourth chain group (cloth) at `player + (10, 8)` and **moved bread mini from `player + (3, 8)` to `player + (15, 8)`**. The two consumers (cloth Retter at the cloth chain's row 3, bread Mixer at the bread mini's anchor) now share a single pump+water tile via a 5-pipe L-shape network — multi-consumer fluid-network integration test now real and verified.
- **F11 ergonomics fixes:**
  - Spawn toast now reports the origin: `[debug] Demo chain: NN placed, MM skipped at origin (X, Y)`. One missing string in that toast cost an hour of "where's my F11 demo" debugging during this session.
  - F11 dedup: tracks `_demo_spawned: bool` + `_demo_origin: Vector2i` on `main.gd`. Subsequent F11 presses no-op with `[debug] Demo already exists at (X, Y). Shift+F11 to allow respawn.` Shift+F11 clears the flag but does NOT delete buildings — player cleans up manually before respawning if they want a fresh layout.
- **Tests:** 8 passing throughout. No new tests added in main session (groundwork commit `b3185ce` had already tightened all four throughput-bearing assertions).
- **Save schema unchanged at v9.** New items, recipes, buildings, and hotbar entries are all forward-compat additions; no shape change.

### Decisions

- **Dedup flag is in-memory, not save-persisted.** The flag resets on every Stewardship launch. Reasoning: the flag's job is to prevent accidental double-spawns within a single play session. Persisting it across save/load would mean "I saved with a demo, reloaded, can't respawn even after manually clearing." The session-scoped semantic matches the user's actual intent.
- **Shift+F11 doesn't auto-clear buildings.** Auto-clearing demo buildings would be destructive and easy to misfire. Manual cleanup is verbose but safe; the flag clear is just permission to re-spawn.
- **Bag-cap mechanic deferred** to its own session. The original Session E plan included it, but the F11 coordinate-confusion sidetrack ate the budget for architectural decisions (slots-per-bag, schema bump y/n, UX for consumption). Better to land cloth chain cleanly than half-ship bag-cap.
- **Cloth chain processors stay 1×1, non-rotatable.** SESSION_E_PLAN.md sketched Retter/Loom as candidates for 2×2 (they're vats and big looms thematically). Holding off; rotation+multi-tile work for cloth was deferred since the chain ships fine at 1×1 and there's no current ergonomic reason. Note for future: if cloth chain layouts feel cramped, revisit.
- **Cloth recipes have NO `prefer_dir` ports** (per spec). Discovered as a real ergonomic wart during smoke-test: "I added a chest near the Retter and now my chain stopped" because the chest got fiber instead of the south belt. Logged as a follow-up note for a later sub-session — likely the right answer is `prefer_dir` per recipe + rotation enabled, matching what bread chain has.

### Lessons

- **F11 spawned-at-press-time-player-position bit hard.** Today's hour of "where's the Flax Planter / why doesn't (12, 22) have anything" came from me reasoning about offsets relative to the player's CURRENT position when the demo was spawned at the player's PRESS-TIME position. The fix (origin in toast + dedup flag) is one extra string and one bool — should have been there from Session C. Lesson: **debug tools must surface their own context.** A toast that says "thing happened" without "where" is half a tool.
- **"Manual verification" still needs the right scaffolding.** The F11 demo IS manually verifiable, but only if the spawn origin is visible. Without that toast addition, manual verification was effectively impossible without code-level recall. This is exactly the friction point that motivates the next session's MCP install.
- **The user's "show me a screenshot" override saved the loop.** I was about to keep iterating on coord guesses; the user shifted to "drop a screenshot in chat" and that resolved it in one round trip. Lesson for future: when coord debugging stalls, escalate to visual.
- **Stash discipline paid off.** The zoom WIP from Session D's tail was stashed cleanly (`stash@{0}`) before this session started. NOTES.md flagged its existence. Tree was clean for Session E work, no entanglement. Next session can pop the stash fresh.
- **Groundwork commits + roll-up rule worked.** Five small groundwork commits (b3185ce / 552f4ce / b25bc8a / 691c7e6 / 01504c5 / ec0a2eb) shipped across late Session D and early Session E without a PROJECT_LOG entry per commit, exactly as the convention specified. This entry rolls them all up.

### Known follow-ups (for future sessions)

- **Camera zoom (stashed):** `stash@{0}` "WIP: zoom feature, displacement bug unresolved." Restore + debug visual displacement in its own session. Pop instructions in NOTES.md.
- **Cloth chain ergonomic wart:** no `prefer_dir` on cloth recipes means the chain is fragile to "I added a chest near a processor." Likely fix is per-recipe prefer_dir + rotation enable. Punt to bag-cap session or a polish session.
- **Bag-cap mechanic:** still on the roadmap. Per-bag slots, lifetime cap of 5, schema bump unknown. Architectural decisions deferred.
- **Tooling: install godot-mcp.** Next session is dedicated tooling setup; satelliteoflove/godot-mcp identified as the candidate. Starts immediately after this session ships.

---

## Session D — Multi-tile buildings + rotation + visual upgrades

**Date:** 2026-05-01
**Tag:** `session-d-complete`

### What shipped

- **Mixer / Oven / Proofer / Packager promoted to 2×2.** Footprint changes are pure data — single-line edits in `Buildings.DATA[t].footprint`. No special-cased multi-tile branches; the existing `occupied: Dictionary` (which already mapped non-anchor cells to anchor) handles placement, removal, and ticks uniformly.
- **`Buildings.edge_cells(t, anchor, dir)` and `all_edge_cells(t, anchor)` helpers.** Return the cells immediately outside a building's footprint along a given edge. 1×1 → 1 cell per edge; 2×2 → 2 cells per edge. Generalizes to any size.
- **Multi-tile-aware `Processor` pull/push.** `_try_pull_inputs` and `_try_push_outputs` iterate all cells along the relevant edge instead of a single position. Rate-limited to one item/tick across the full edge.
- **`fluid_available_for_building(b)` and `fluid_available_for_building_edge(b, dir)`.** Multi-tile fluid lookup — scans all 8 perimeter cells of a 2×2 (4× the chances vs 1×1) or restricts to a single edge when a recipe pins fluid input direction.
- **Rotation, end-to-end.**
  - Mixer / Oven / Proofer / Packager / Thresher all `supports_direction: true`.
  - `Buildings.world_dir(b, recipe_dir) = (recipe_dir + b.state.dir) % 4` rotates a recipe's canonical port direction by the building's current orientation.
  - Recipes declare ports in **canonical** orientation (as if facing east); rotation applies at tick time. Used uniformly for solid input, solid output, and fluid input prefer_dir.
  - `Processor.make_state(recipe_id, dir)` threads orientation in at construction. Rotatable processor `make()` functions (Mixer/Oven/Proofer/Packager/Thresher) all accept `dir`.
  - **Hover-rotate (Factorio convention):** R rotates a placed building under the cursor when hand is empty. With a rotatable building in hand, R rotates the placement direction. With a non-rotatable building in hand, toast: "X has no directional ports." Mill / Briquetter / Yeast Culture / Sugar Press deliberately stay non-rotatable since their recipes have no `prefer_dir` ports.
- **Recipes for Mixer / Oven / Proofer / Packager gained prefer_dir on every solid I/O.** Canonical layout: inputs from W (and S for Oven fuel branch), outputs to E. Continuous east-going main flow with perpendicular fuel and waste branches.
- **Save schema v8 → v9.** Locks out v8 saves whose Mixer/Oven/Proofer/Packager were 1×1 / non-directional — mismatched `occupied` cells would silently corrupt placement. Hard-fail with `OS.alert` naming the file path.
- **Visual upgrades, all programmer-art:**
  - **Multi-tile footprint border** (`Buildings._draw_multitile_border`): 2px near-black outline around any footprint > 1×1. Drawn after per-type render so it always sits on top. Auto-generalizes to future 3×3.
  - **Connection point indicators** (`Buildings._draw_port_indicators`): yellow dots for solid item ports, blue for fluid. **Filled** when the port is currently usable (belt with right item / chest with room / pipe in pump-bearing component). **Hollow** when port exists but isn't functional (no neighbor or wrong content). Fluid-no-prefer_dir draws filled-only on actively-connected cells, skipping hollow to avoid 8-dot noise.
  - **Pipe redesign**: continuous tubes with stubs to actual connectable neighbors only. Bright saturated blue when in a pump-bearing component, muted gray-blue when not. Removed the tile-background rect so tubes float over terrain. Connectivity is data-driven — any building whose recipe has `inputs_fluid` is auto-connectable.
- **Hover preview shows full footprint.** White outline if all cells placeable, red if any cell blocked. Direction arrow centered on the footprint (not just anchor cell) for rotatable multi-tile buildings.
- **Q-inspect rebuilt for rotation:** info panel shows "Input ports: Flour ← N, Yeast ← E", "Output ports: Dough → S", "Facing: S (R to rotate before placing)" — all in WORLD directions after rotation, so what the player reads matches what they see on the building.
- **F11 demo extended** with a bread mini-chain: a Mixer rotated to face south, dough belt exiting south to a chest, water from a small pump+pipe on the west. Pre-loaded buffer so the integration test for rotated push fires immediately.
- **Tests:** 8 passing. New `test_thresher_rotation.gd` covers all 4 orientations (E / S / W / N), asserting both correct world-dir routing AND that other-side chests stay empty. The 90° and 270° cases catch CW-vs-CCW confusion in the rotation math.

### Decisions

- **Recipes declare ports in canonical orientation, rotation applied at runtime.** Authoring port directions in the recipe (rather than per-instance) means each recipe has one "natural" layout; the player picks an orientation per machine. Eliminates a class of bugs where a recipe edit would break already-placed buildings.
- **Non-port buildings stay non-rotatable.** Mill, Briquetter, Yeast Culture, Sugar Press have no `prefer_dir` on their recipes — rotation would be a no-op. Letting players rotate them visibly does nothing, which feels broken. R-key on these shows a toast naming the building. When/if a recipe gains `prefer_dir`, flip the flag in `DATA` — sizes and rotatability are both data, defer the choice until the building actually needs it.
- **Square footprints only.** 1×1 and 2×2 — no asymmetric shapes yet. Rotation just swaps port directions; no cell relocation or footprint overlap re-validation needed. When 1×3 / 3×3 / asymmetric land, rotation will need a placement-revalidation step.
- **Multi-tile model uses the existing `occupied: Dictionary`, no new tile-ref entries.** The plan called for `Tile` entries marking expansion cells. The `occupied` map already maps any footprint cell to its anchor — that's the same information without a parallel data structure or Tile-shape change.
- **Pipe stub rendering tells the truth, not a "clean" version.** Originally considered hiding stubs to make the visual less busy; rejected. The invariant "stub = real connection, no stub = no connection" is the kind of debug aid that pays off for the lifetime of the project. Don't lie about state in the renderer.
- **Fluid-no-prefer_dir gets filled indicators only on active connections, no hollow noise.** A 2×2 with no-prefer_dir would have 8 hollow blue dots otherwise. Only highlighting the cells where water actually flows in is enough — the absence of any blue dot is itself a signal that water isn't connected.
- **Hover-rotate matches Factorio.** R with a building in hand rotates the placement; R with empty hand rotates whatever's under the cursor. Lowest-friction iteration on layouts.

### Lessons

- **Multi-tile is mostly free if the data structure was right.** The single biggest rewrite — `_try_pull_inputs` and `_try_push_outputs` — was about 30 lines. Everything else was footprint-aware draws and helper additions. Investing in `occupied: Dictionary` early (Session A?) paid off handsomely.
- **Show the design before implementing.** The user's process gate — "design before code, then approve, then code" — caught two issues that would have been wrong otherwise: the multi-tile model that would have changed Tile shape unnecessarily, and the rotation feature that almost shipped without the four-direction test. Both saved a rewrite.
- **The CW-vs-CCW concern was real.** Godot's Y-down system makes "visual CW" and "math CW" the same in this enum's case (E=0 → S=1 → W=2 → N=3 happens to be visual-CW), but only because `Belt.DIR_VECS` was laid out that way deliberately. The four-direction test is what verifies this stays true if anyone ever reorders the enum.
- **Visual feedback is a separate axis from logic correctness.** All 8 tests passed multiple times before the visual upgrades shipped — but the visuals themselves had bugs (port indicators flickering, pipes still looking like belts) that no amount of unit testing would catch. Manual F11 verification + Q-inspect was the only path to confidence here.
- **"Don't ship without showing design first" caught a real issue.** When the user asked for rotation, my first instinct was to just mark every processor `supports_direction: true`. The user's "non-port buildings shouldn't be rotatable" rule would have been a follow-up bug otherwise. The design pass caught it.
- **Pipe drawing finally has world access.** A comment in the old `pipe.gd` literally said "we can't query world from a static draw method without it being passed in." The fix turned out to be trivial — `canvas` IS the GridWorld; GDScript's dynamic typing lets us call its methods directly. Deferred for too long.

---

## Session C — Bread chain + prefer_dir output ports

**Date:** 2026-05-01
**Tag:** `session-c-complete` (commit `3af1eb5`)

### What shipped

- **9 new building types:** Thresher, Proofer, Oven, Packager, Briquetter, Yeast Culture, Sugar Press, Wheat Planter (hotbar variant), Sugar Planter (hotbar variant).
- **9 new items:** GRAIN, STRAW, RISEN_DOUGH, BREAD, LOAF_PACK, FUEL_BRIQUETTE, SUGAR_BEET, SUGAR, plus YEAST and DOUGH already added in Session B.
- **Recipe shape evolution:** `inputs` → `inputs_solid`; new `inputs_fluid`; `process_ticks` → `time_ticks`. Added `prefer_dir` 3rd element on `outputs_solid` entries for per-output port routing.
- **Mill recipe shifted** from `wheat → flour` to `grain → flour` (the first "factory got more complex" moment — players must add a Thresher upstream).
- **Planter retrofitted** to support `crop_type` field via `.get(default=WHEAT)` — first time the deferred forward-compat discipline mattered. Old saves load with all-wheat behavior.
- **Hotbar Refining category** added for the 7 new processors. Slot model gained optional `extra` payload + `label` override.
- **F11 demo** spawns wheat chain (with east/west thresher branches) + sugar/yeast chain (with pump+water+pipe). Self-contained, debug-only.
- **Save schema unchanged at v8.** New building types and recipe content are forward-compatible additions; no data shape change.
- **Two critical bug fixes** discovered during play-testing:
  1. **Multi-slot belt pull** — consumers grab their wanted item from any slot of the adjacent belt, not just the front. Fixes deadlock where straw at slot 3 blocked the mill from reaching grain in slot 1.
  2. **Machines push to chests directly** in addition to belts — byproducts can drain to a sink without requiring a belt segment.
- **Diagnostics gained:** BLOCKED_OUTPUT names the specific output that's full ("Straw output full (8/8)"); belt direction preview arrow on hover; one-time recipe-id warning instead of per-tick spam.
- **Removed:** F12 yeast debug spawn (replaced by real Yeast Culture).
- **Tests:** 7 passing. New `test_thresher_prefer_dir` locks in the routing semantic.

### Decisions

- **Replaced the input-belt-skip heuristic with declarative per-output `prefer_dir`.** The heuristic ("skip belts that look like input lanes") was an inferred guess; `prefer_dir` is a recipe-level declaration of intent. Strict mode: items go to their designated port or wait. No fallback. Multi-output recipes (Thresher) declare `[GRAIN, 1, Belt.DIR_E]` and `[STRAW, 1, Belt.DIR_W]`. Players place belts at each port.
- **Killed the Void building.** Anti-thematic for a stewardship game; discarding output rewards laziness. Closing the loop (Briquetter → fuel → Oven) is the right answer. Void was a workaround for the architectural limitation that `prefer_dir` properly fixed.
- **Kept Mill / Mixer / Oven / etc. as 1×1.** Multi-tile is Session D's job; conflating size with output-routing in Session C would have stalled the bread chain content.
- **Kept Mill as its own enum entry, not a generic `PROCESSOR`.** Each future processor (Oven, Press, Smelter) has its own visual, terrain restrictions, hotbar slot, default recipe. Behavior is what we factored out into `Processor.tick`, not identity.

### Lessons

- **Strict routing > heuristics.** The first attempt was an "input-belt-skip" check that inspected belt contents at push time. It worked but was opaque. Moving to declarative `prefer_dir` made the routing intent visible in the recipe data, deterministic at runtime, and easier to debug.
- **Game design > sink hacks.** When the multi-output deadlock first appeared, the instinct was a Void building. The user's correct call: the deadlock isn't a missing sink, it's a missing routing primitive. Adding the primitive made the Void unnecessary.
- **Test thresholds matter.** A test asserting `≥1 flour` over 1500 ticks passed even when the chain produced exactly 1 flour and deadlocked. Tighter thresholds (≥5 over 5000 ticks) actually verify sustained operation. Worth re-tightening other tests as systems mature.
- **Q-inspect feedback loop is the most valuable debugging tool.** Every "Q the X, paste readings" round caught real state. Couldn't have diagnosed the prefer_dir need from code alone.
- **Don't ship "fixes" without diagnosis.** Mid-session, three "fixes" landed in succession (chest-push, two-pass push, input-belt-skip) before the actual problem was understood. Each made the system more permissive without addressing the root cause. The user's "stop adding fixes, paste exact readings" was correct discipline.
- **Don't delete files without asking.** Even files that "should regenerate" (saves) — the user's policy was leave-it-alone-and-decide.

---

## Session B — Pipes, pump, fluid network, Mixer

**Date:** 2026-05-01
**Tag:** `session-b-complete` (commit `e417d8a`), plus follow-up commit `84d1c06` (Tile.resource_node forward-prep)

### What shipped

- **3 new buildings:** Pipe (passive 4-way carrier), Pump (validates adjacent water), Mixer (Processor running `mixer_dough`).
- **Fluid network resolver** in GridWorld: BFS over pipe positions, deterministic component IDs, lazy rebuild via dirty flag. Query: `world.fluid_available_at(pos, fluid_type)`. Connectivity-only model; no flow simulation.
- **Recipe shape gained `inputs_fluid`** and Processor.tick consults the fluid network at recipe-start. Connectivity-only consumption (no buffer, just availability gate).
- **BLOCKED_OUTPUT state** wired into Processor: set when output buffer can't hold next cycle's results; re-checked each tick until room clears.
- **Items gained YEAST and DOUGH.** Fluids registry created (just WATER for now).
- **F12 debug spawn** (10 yeast in player inventory) until Yeast Culture lands in Session C.
- **Esc closes info panel.** OS.alert path uses native Windows backslashes.
- **Mixer info panel** shows "Waiting for: Flour (0/2), Yeast (0/1), Water (no pipe→pump)" diagnostics.
- **`last_building_place_error`** supplies specific reasons (e.g. "Pump must be placed adjacent to water" instead of generic terrain list).
- **`Tile.resource_node` field added** as forward-prep for future world-gen mining (target Session G/H).
- **Save schema bumps:** v6 → v7 (base/overlay tile model — Session B prep), v7 → v8 (resource_node forward-prep).
- **Test harness built:** `scripts/tests/test_runner.gd` discovers test classes, runs each in isolation. Tests: placement_rules, save_load_roundtrip, wheat_to_flour, fluid_network, mixer_dough.
- **CONVENTIONS.md** updated: JSON canonicalizes numerics to float on save (reads must use `int(...)` coercion); state reads with `.get(key, default)` for forward-compat.
- **NOTES.md** created with the resource-mining roadmap entry.

### Decisions

- **Fluid network is connectivity-only, no flow simulation.** Per spec, this is enough for Session B; real flow rates land if/when bottlenecking matters. Dramatically simpler implementation.
- **Each fluid-consuming machine has its own pump+water tile in the F11 demo.** Avoiding a shared pipe network in the demo because the demo is meant to be self-contained — small water patches per machine are clearer than tracing one network through the layout.
- **`Recipes.get_recipe` softens `push_error` to one-time `push_warning`.** Per-tick spam from a stale recipe ID would flood the log; once-per-id is enough signal.
- **Hard-fail save migrations stay unconditional.** Any schema bump = `OS.alert` with file path. Solo project; not worth migration code.
- **Tile gains `resource_node` field now**, even though no buildings use it yet. The save format includes it from v8 onward — no second bump when mining lands in Session G/H.

### Lessons

- **Don't reflexively bump save schema.** v7 → v8 (resource_node) was a real shape change and bumped correctly. Session C added new building types and didn't bump — new buildings are forward-compatible additions to the existing buildings array. The bump-policy heuristic is "shape changes only," not "version per session."
- **Fluid-input gating is the cleanest cross-system primitive.** Adding a dependency from Processor to GridWorld was small (`world` already passed to `tick`), and the resulting "ask the network if water is available" call is dirt simple. Connectivity model bought enormous simplification.
- **JSON canonicalizes numerics to float.** Caught when test_save_load_roundtrip used `str()` equality on dicts: `{x: 0}` and `{x: 0.0}` differ as strings, equal as values. Fixed with semantic deep-equals helper. Now documented in CONVENTIONS.md.
- **Forward-compat within a save version requires `.get(key, default)` reads.** Some buildings (planter, harvester) used `.get` defensively; others (belt, processor) used direct keys assuming `make()` always wrote. The pattern was inconsistent. Documented the discipline in CONVENTIONS.md so future field additions don't break older v8 saves of existing buildings.

---

## Session A — Recipe registry + Processor + Info Panel + Save v5

**Date:** 2026-05-01
**Tag:** `session-a-complete` (commit `1343c1a`)

### What shipped

- **Recipes registry** (`scripts/world/recipes.gd`): static class mirroring `Items` and `Buildings`. One recipe registered: `mill_wheat_to_flour`.
- **Processor class** (`scripts/world/processor.gd`): generic recipe-driven tick logic with state machine (IDLE / RUNNING / BLOCKED_OUTPUT). Mill became a thin shim — its own `make()` and `draw()`, behavior delegated to `Processor.tick`.
- **Belt I/O helpers** lifted out of Mill / Chest into `Belt.slot_facing_external()` and `Belt.try_pull_matching()`. Eliminated duplicated logic.
- **Building Info Panel** (`scripts/ui/info_panel.gd`): right-side panel, opens via Q-key or middle-click. Per-type `info_lines()` dispatch with generic fallback. Tracks target by anchor (Vector2i) so building deletion auto-closes the panel.
- **`Inventory.has_room_for(item, count)`** added. One-liner using `add` semantics, no mutation.
- **Save schema v4 → v5:** Mill's state shape changed from `{in_count, out_count, progress}` to `{recipe_id, state, progress, in_buffer, out_buffer}`. Hard-fail on mismatch via `OS.alert` blocking dialog.
- **`Buildings.gd` checklist comment** documents the 9-10 mechanical edits required to add a new building type. Future processor machines (Oven, Press) shrink to ~30 lines: `make` + `draw` + a Recipe entry.

### Decisions

- **Recipe IDs are strings, not enum ints.** Stable across enum reordering; self-documenting in saves; survive content additions.
- **Mill kept as `Buildings.Type` entry, not replaced with generic `PROCESSOR`.** Each future processor wants its own visual, terrain restrictions, hotbar slot, default recipe. Behavior is shared via `Processor.tick`; identity stays per-type.
- **Default recipe assigned in the building's `make()`**, not in a `Buildings.DATA` field. `make()` is the only function that constructs initial state — that's where the default belongs.
- **Match-statement dispatch in `Buildings.gd` not refactored to a registry.** "9 places per new building" is real but a `BuildingHandler` registry rewrite is risky and expensive. The Processor refactor itself is the bigger cost-reducer. Defer the registry until ~10 building types make it pay off.
- **Info panel renders strings, dispatched per type.** Each building file optionally defines `info_lines(b) -> Array[String]`; generic fallback introspects `b.state` keys. Strings keep scope tight; structured renderers can come later if needed.
- **Track inspected building by anchor, not by Building reference.** RefCounted weak-refs are awkward in GDScript; anchor + `world.has_building_at(anchor)` is stable and detects deletion cleanly.
- **Hard-fail policy for v4 saves with `OS.alert`.** Migration code is expensive and the project is solo. Documented the path so the user can manually delete.

### Lessons

- **`Object` has shadowing risks for short method names.** `Recipes.get(id)` collided with `Object.get` and produced "Could not resolve external class member" errors. Renamed to `get_recipe`. Established the rule: never use bare reserved names (`get`, `set`, `has`, `connect`, `free`, etc.) on a `class_name`'d type. Documented in CONVENTIONS.md.
- **Inventory objects don't survive JSON round-trip.** Storing an `Inventory` in `Building.state` silently degrades to a plain Dictionary on load. Must store as `[[type, count], ...]` arrays and rehydrate on demand. Mirror the Chest pattern. Documented in CONVENTIONS.md.
- **Per-step headless imports are the cheap regression net.** Running `--headless --import` after each meaningful chunk caught a `Recipes.get` collision on the first try and confirmed each step landed cleanly. Worth keeping as default workflow.
- **Visual fidelity of `Mill.draw` reading new state was straightforward.** The shim pattern (visuals stay; behavior moves) is the right migration shape for future processors.

---

## Pre-Session-B — Hotbar categories, base/overlay terrain, test harness

**Date:** 2026-05-01
**Tag:** `pre-session-b` (commit `e4ed0e5`)

### What shipped

- **CONVENTIONS.md** created. Naming rules (no bare `get`/`set`/`has`), file layout, state storage discipline, save schema rules, tick determinism.
- **Hotbar overflow fix:** category bar with Tab/Shift+Tab cycling. Categories: Terrain, Logistics, Production, Storage. Each remembers its own last selection. Single-string header (no overlap risk for any name length).
- **Chest migrated** from Inventory to bag format (`[[type, count], ...]`). Total cap 2400 (= old 24 slots × 100 max_stack), no per-type cap.
- **Base/overlay terrain model:** `Tile.base` (GRASS, WATER) + `Tile.overlay` (NONE, SOIL_TILLED, PATH, STONE). Player paints overlays only; water is natural terrain spawned by world-gen. Overlay placement ladder (soil → path → stone) preserved.
- **Fixed-position default lake** seeded by `GridWorld.generate_default_world()` at tile coords (8..11, 4..5). 4×2 rectangle, 8 water tiles, 12-spot perimeter for multi-pump testing. Coordinates exposed as `DEFAULT_LAKE_X_RANGE` / `_Y_RANGE`.
- **Save schema v6 → v7.** Tile entry shape changed from `[x, y, terrain]` to `[x, y, base, overlay]`.
- **Test harness foundation:** `scenes/test_runner.tscn` discovers test scripts, runs each in isolation, exits with pass/fail code.

---

## Session-tracking convention going forward

- Each session ends with a commit that includes a PROJECT_LOG.md update covering that session.
- Each session entry uses the three-sub-section format above (What shipped / Decisions / Lessons).
- Lessons should be specific and actionable. "We learned to be careful" is not a lesson; "Don't use bare `get` on `class_name`'d types — collides with `Object.get`" is.
- Decisions should explain the *why*, not just the *what*. Code shows the what.
- Don't backfill from memory weeks later. Write while the context is fresh.
