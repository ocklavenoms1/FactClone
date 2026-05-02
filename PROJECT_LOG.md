# Stewardship — Project Log

Reverse-chronological. Newest session at the top. Update this file at the end of every session as part of the commit — the session isn't done until the log is updated.

Each entry has three sections:
- **What shipped** — features, files added/removed, schema bumps, things you can point at in the diff.
- **Decisions** — architectural choices made and the reasoning. The "why" that wouldn't be obvious from the code.
- **Lessons** — what we got wrong, what we learned, what to do differently. Anti-patterns earned through pain.

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
