# Stewardship — Project Log

Reverse-chronological. Newest session at the top. Update this file at the end of every session as part of the commit — the session isn't done until the log is updated.

Each entry has three sections:
- **What shipped** — features, files added/removed, schema bumps, things you can point at in the diff.
- **Decisions** — architectural choices made and the reasoning. The "why" that wouldn't be obvious from the code.
- **Lessons** — what we got wrong, what we learned, what to do differently. Anti-patterns earned through pain.

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
