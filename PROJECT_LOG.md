# Stewardship — Project Log

Reverse-chronological. Newest session at the top. Update this file at the end of every session as part of the commit — the session isn't done until the log is updated.

Each entry has three sections:
- **What shipped** — features, files added/removed, schema bumps, things you can point at in the diff.
- **Decisions** — architectural choices made and the reasoning. The "why" that wouldn't be obvious from the code.
- **Lessons** — what we got wrong, what we learned, what to do differently. Anti-patterns earned through pain.

---

## QoL Cluster A — Click extraction + shift/ctrl stack ops

**Date:** 2026-05-15
**Tag:** `session-qol-cluster-a`
**Save:** v18 (no schema bump — UI-only changes, no state shape change)

**First Superpowers-methodology session.** Wrapped CLAUDE.md project protocols (design pass / PAUSE checkpoints / PROJECT_LOG / tagged commit) around Superpowers' brainstorming → writing-plans → subagent-driven-development → TDD inner loop. 27-task implementation plan executed via Opus/Sonnet/Haiku subagents with two-stage review (spec compliance + code quality) per task. Final commit chain: ~45 commits from `1ce0d4d` (design spec) through PAUSE 2 fixes.

Cluster A as planned: (1) refactor the duplicated player-slot click handler into a static `SlotClickHandler` module, (2) add shift+LMB half-stack take/drop across all slot kinds, (3) add ctrl+LMB exact-N quantity picker modal across the same matrix. Each phase ended with a manual smoke gate (GATE 1 / GATE 2 / PAUSE 2). 13 internal sub-suites in one new test file (`test_slot_click_handler.gd`); runner pass count 33 → 34, internal coverage 33 → 46 sub-suites.

### What shipped

**Phase 1 — Refactor extraction (Tasks 1-5, GATE 1):**
- `scripts/ui/slot_click_handler.gd` (new, ~80 lines): static module with `MOD_NONE/MOD_SHIFT/MOD_CTRL` constants, `split_half(n)` math util, `handle_player_slot(slot, cursor, mods)` for plain-LMB pick/place/merge/swap. Mirrors `Burner`/`Processor`/`Inserter` static-module pattern.
- `inventory_grid._handle_left_click_player` and `BuildingPanel._handle_player_slot_click` migrated to delegate to the new handler. Byte-identical-outcomes contract preserved for plain LMB.

**Phase 2 — Shift+LMB (Tasks 6-16, GATE 2):**
- `_handle_shift_player` helper extended SlotClickHandler with the full 5-cell shift matrix (spec §5.1).
- Modifier extraction (`_extract_mods`) wired into `inventory_grid` and `BuildingPanel` `_gui_input` events. `mods` parameter threaded through `_handle_chest_slot_click`, `_take_from_slot`, `_drop_into_slot`, `_drop_into_input`, `_drop_into_fuel`.
- Per-kind shift behaviors:
  - **Player** (player Inventory.slots): cell-matrix per §5.1.
  - **Chest** (bag Array): take half / drop half. Drop **refuses with toast** on no-fit (preserves chest LMB convention — does NOT silent-clamp like player slot).
  - **Building input**: take half / drop half with max_stack silent-clamp.
  - **Building output / output_multi**: take half of addressed entry only.
  - **Building fuel (TAKE)**: split_half(units) (initially lossy WOOD per spec §5a — REVISED at PAUSE 2; see "Decisions" below).
  - **Building fuel (DROP)**: split_half(cursor.count) items, atomic via FUEL_VALUES, silent-clamp to free units.
  - **Filter slot**: no-op for shift/ctrl, no toast.

**Phase 3 — Ctrl+LMB picker (Tasks 17-23, PAUSE 2):**
- `scripts/ui/quantity_picker_modal.gd` (new, ~95 lines): `class_name QuantityPickerModal extends PopupPanel`. Hard modal via `popup_exclusive_on_parent`, Esc/click-outside via `close_requested` signal, Enter via custom `_input`. SpinBox-based exact-N picker with edge-flip placement (anchor + (60,-40) offset, flip on right/bottom viewport edge).
- `scenes/quantity_picker_modal.tscn` (new): VBoxContainer { Label, SpinBox, HBoxContainer { OK, Cancel } }. Single HUD singleton wired in `main.gd` and distributed to all `BuildingPanel`-derived panels.
- `SlotClickHandler.ctrl_click_max(slot, cursor)` + `ctrl_click_transfer(slot, cursor, n)` for the player-slot path. Other slot kinds compute max inline (Q2 minimal-extraction principle).
- Ctrl branches wired into every click dispatcher: `inventory_grid._handle_left_click_player`, `BuildingPanel._handle_player_slot_click`, `chest_panel._handle_chest_slot_click`, `BuildingPanel._take_from_slot` (all 4 take kinds), `_drop_into_input`, `_drop_into_fuel`. Each branch: caller-side gate (`if max_n > 0`), build anchor + direction + label_item, open picker with Callable confirm_cb.

**Test coverage (13 sub-suites in `test_slot_click_handler.gd`):**
1. `player_slot_regression` — 5-cell critical-gate test (the refactor must be byte-identical).
2-5. shift_take_player_half / shift_drop_player_half_empty / shift_drop_player_half_matching (with capacity clamp) / shift_player_diff_type_noop.
6. shift_chest_take_and_drop (with refuse-with-toast on no-fit).
7. shift_building_input_and_output.
8. shift_fuel_take_items_same_type (PAUSE 2 revision — was shift_fuel_take_units).
9. shift_fuel_drop_items_atomic.
10. shift_filter_noop.
11. ctrl_picker_open_default_max (player-slot cases).
12. ctrl_picker_confirm_cancel_gate (orchestration: confirm fires cb, cancel doesn't, max==0 gate suppresses).
13. ctrl_picker_outside_click_no_propagation (scene-tree test — first sub-suite to instantiate the picker scene).

**PAUSE 2 fixes (committed pre-ship):**
- **Picker placement** (`222cb9e`): explicit Window position+size + Vector2i Rect2i conversion. Initial Vector2 → Rect2i implicit conversion was silently broken for embedded sub-windows.
- **Close-on-padding** (`7998024`): removed `_close()` / `close()` from `_gui_input` slot_idx<0 branches in inventory_grid / chest_panel / building_panel. Clicks inside panel padding now no-op; Esc still closes.
- **Fuel TAKE design reversal** (`7998024`): see "Decisions" below.

### Decisions

- **Helper shape: static module `SlotClickHandler`** (Q1, design pass). Rejected: method on `CursorStack` (would double the size of a pure-data class); method on `SlotWidget` (CLAUDE.md forbids click logic in pure render helpers); universal entry point dispatching across kinds (would couple SlotClickHandler to `Burner.FUEL_VALUES`, `Chest._bag_*`, `Buildings.slot_layout_for`'s `accepts` validation — defeats isolation/clarity).
- **API surface: minimal extraction** (Q2). Helper covers player-slot path only + `split_half(n)` math util. Other slot kinds compute max inline in dispatchers — each kind's max formula is 1-2 lines tightly coupled to its data shape. Per-kind dispatcher max formulas covered by integration smoke, NOT unit tests (Test Layering Strategy now pinned to NOTES.md).
- **Shift+LMB cursor×slot matrix (Q3)**: same-type drop = drop ceil(M/2) clamped to space (cursor-as-donor consistent across all M+_ cells); different-type = no-op (shift never swaps; plain LMB still swaps). Chest's drop behavior preserves its existing LMB refuse-with-toast convention on no-fit; player-slot silent-clamp does NOT inherit.
- **Ctrl+LMB picker (Q4)**: PopupPanel subclass with `popup_exclusive_on_parent()` for hard-modal + click-outside-close + Esc handling all native. SpinBox default = max (Minecraft convention: "transfer all unless you change it"). Pre-open gate on `max ≤ 0` — picker doesn't open for empty+empty, different-type, full same-type slots, or fuel-drop with no atomic fit. Asymmetric fuel labels per direction (originally TAKE in units / DROP in items; revised at PAUSE 2 to both in items).
- **Default-value parameter addition (Task 12 deviation)**: implementer added `mods: int = SlotClickHandler.MOD_NONE` defaults to `_take_from_slot`, `_drop_into_slot`, `_drop_into_input` (later `_drop_into_fuel`) without surfacing as DONE_WITH_CONCERNS. Caught at controller code-quality review. Decision: keep the defaults pragmatically (avoids cascading test churn for 14 existing call sites), but flag for future protocol enhancement (strengthen scope-deviation wording to include "adding default values" explicitly). Strengthened protocol applied from Task 13 onward.
- **REVERSAL: Fuel TAKE returns last_fuel_item type, NOT lossy WOOD** (PAUSE 2, post-Q5 reversal). Original spec §5a/§6.2 was lossy WOOD always; user confirmed at Q5 ("5a units for take — keep math one-line"). After actually playing it, user found the surprise factor exceeded the simplicity gain ("put coal in, take back, got wood?"). Fix: `_fuel_take_item_type()` helper reads `last_fuel_item` with WOOD fallback when missing OR remaining units < one item's energy (so stranded sub-item-energy can be recovered). Aligns take semantics with display semantics — `info_lines` fuel arm already uses last_fuel_item for the slot icon. Working protocol #6 ("Reversal is cheap at design time, expensive after shipping") — we're at PAUSE 2 pre-ship, reversal cost is bounded (4 files touched + 1 test assertion update).
- **NOTES.md backlog item 8 (close-on-padding-click UX) elevated to MUST-FIX**: originally deferred to Cluster B at GATE 1 smoke. At PAUSE 2 user escalated. ~3-site removal (1 line each) lands in same commit as fuel reversal.
- **test_save_migration fixture leakage architectural fix**: user repeatedly hit "Save incompatible" popup after each test run because `test_save_migration.gd` creates a v19 fixture at `user://test_save_migration.json` and the game's load_game OS.alert popups any v19 save it encounters. **Definitive fix at commit `9b4e972`**: `save_system.gd._is_test_fixture_path(path)` helper guards all 3 `OS.alert` call sites — push_error still fires for logging, but OS.alert only fires for non-test paths. Test fixtures can now appear/disappear at any path; user-facing popup is killed at the source.

### Lessons

- **Superpowers methodology integration was a net win.** 27-task plan executed cleanly via subagent-driven-development with two-stage review per task. The brainstorming skill caught 2 spec issues during self-review pass (chest refuse-clamp semantic + Phase 3 helper-vs-inline ambivalence). The writing-plans skill produced a 1974-line plan that survived execution with only mechanical corrections.
- **Code-quality reviewer line-quoting protocol was empirically validated.** Pre-protocol: 3 false-positive omission claims in 6 reviews (~50% FP rate). Post-protocol (added at Task 7): 0 false positives in 17 reviews. Strong evidence that requiring reviewers to quote-by-line-number forces them to read the file rather than pattern-match. Pinned to NOTES.md as standard practice for future subagent-driven sessions.
- **Opus reviewers exhibit context-discrimination behavior that Sonnet doesn't.** Across Tasks 13, 15, 18 (3 data points), Opus reviewer explicitly identified and ignored ambient context that leaked into tool output (MCP system reminders, link-safety prompts). Sonnet did not surface this in 6 reviews. Real model-level provenance reasoning, context-dependent. Worth the cost for high-stakes reviews of foundational code.
- **Subagent stall pattern is cross-model and orchestration-framework-bound.** Implementer subagents (Sonnet@12, Opus@14, Opus@21) all stalled at the test-verification step when Godot's cold-cache test takes >2 minutes. Controller had to verify independently and commit on behalf. DONE_PENDING_VERIFICATION protocol added at Task 14 mitigated the recovery cost (~5 min/stall) but didn't prevent the stalls themselves. Future enhancement: lower the threshold to 2 min OR move test-verification to controller as standard step.
- **Parse-error-against-base-class is invisible to test_runner.** Picker (`QuantityPickerModal extends PopupPanel`) had `get_viewport_rect()` (a `CanvasItem` method, NOT on `Window`) at line 66 — latent bug since Task 18 commit `286493e`, missed by 5 code-quality reviewer cycles. Test_runner never loads main.gd (only test_*.gd files), so the parse error never fired during test runs. Game launched because `@onready var quantity_picker` resolved to null and Task 19's defensive `quantity_picker != null` gate silently no-op'd ctrl+LMB. Caught at Task 23 when implementer tried to instantiate the picker scene under test conditions. **Future enhancement: implementer briefs for scripts with `extends <UnusualBaseClass>` should require `godot --headless --import` verification before reporting DONE.** Pinned to NOTES.md "Subagent Protocol Gap" section.
- **GATE 2 smoke is necessary but not sufficient.** Shift+LMB worked perfectly at GATE 2. Ctrl+LMB was silently broken (picker resolved to null, gate no-op'd). PAUSE 2 caught it but only because the user explicitly tested ctrl-click. Lesson: smoke matrices need explicit per-modifier coverage, not just per-slot-kind.
- **Test fixture leakage into game saves is an architectural smell.** `test_save_migration.gd` creates a v19 fixture and the game's save loader can encounter it if the test crashes mid-run. The path-relocation workaround (`c20286a` move to `test_artifacts/` subdir) didn't fix it — the game's load path still scans the user_data. The right fix is at the load_game source: filter test paths from user-facing alerts. **Pattern: don't fix at the file-location level (workaround); fix at the alert-source level (definitive).** ~3 hours of recurring popup frustration could have been avoided by going to the OS.alert call site sooner.
- **The "test_runner reports per FILE, not per sub-suite" convention is load-bearing.** All 13 sub-suites land in one test file → runner shows 33→34, internal coverage 33→46. Initial draft of the plan had stale `Expected: 38 passed` lines from before I'd internalized this. Caught at plan self-review; documented at GATE 1 sign-off section as the convention reference for future sessions.
- **Design reversal at PAUSE 2 is acceptable when bounded.** Fuel-take returning lossy WOOD was confirmed at Q5; player tested it and hated it. Reversal cost: 4 production files + 1 test assertion = ~30 min including review. Working protocol #6 warns about reversal cost; this one was small enough to land pre-ship rather than as a Cluster B follow-up. The bar for "land pre-ship vs defer": is the existing behavior actively user-hostile, or just suboptimal? Lossy WOOD was user-hostile (surprise factor); the chest-deposit-on-same-type swap (NOTES item 9) is suboptimal but not hostile, defer to Cluster B.



**Date:** 2026-05-09
**Tag:** none (small post-session fix, not a session in its own right)
**Save:** v18 (no schema bump — `walkable` is a DATA-registry flag, not save state)

Adopts Factorio convention: **buildings now block player movement.** Closes the existing UX wart (NOTES.md: *"player walks through them visually, which is a small UX wart"*). User-asked QoL Cluster C from the post-`session-inserter-fast-filter` polish queue.

### What shipped

- **`buildings.gd`**: new `static func is_walkable(t) -> bool` reading a `"walkable"` flag from each DATA entry, default `false` (blocked is the norm). BELT, INSERTER, FAST_INSERTER opted in to `walkable: true` — "thin devices" (belt is flat-on-ground; inserters have small bases with arms swinging overhead) where walking through reads correctly.
- **`grid_world.gd`**: `is_passable_at(pos)` extended with a building layer — after the existing water-base check, also reject if `occupied.has(pos)` AND `Buildings.is_walkable(b.type) == false`. Multi-tile buildings auto-block all footprint cells because `occupied` already maps every cell to the building's anchor.
- **`main.gd`**: `_try_place` rejects placements whose footprint contains the player's tile (`"Can't place X on yourself — step off first."`). Belts skip the check (walkable, no self-trap risk). Console placement bypasses; the player's existing `on_impassable` escape valve in `_move_with_passability` covers the dev case.
- **`test_walkability.gd`** (new, 4 sub-suites): is_walkable per-type sanity (belt + inserter + fast inserter walkable; smelter + chest + pipe blocked), belt placement → passable, smelter placement → blocked, 2×2 mining drill blocks all 4 footprint cells, water still blocks regardless of building presence (regression). **Tests: 32 → 33.**

### Decisions

- **Walkable is per-DATA-entry, default false.** The "blocked is the norm" intuition is correct — most buildings have visual mass. Belts and inserters are the exceptions (thin devices). Pipes stay blocked per Q4 of the design pass even though they're thin too — user call ("keep pipes blocked").
- **Multi-tile blocking is automatic.** `occupied` already has per-cell coverage from `place_building` bookkeeping; `building_at(pos)` returns the same Building instance for any footprint cell, so the walkable check works on all cells with no special-cased loop.
- **Player-on-tile check stays in `main.gd._try_place`, not `can_place_building`.** Keeps `can_place_building` pure (no player coupling). Console placement bypasses, which is acceptable — devs accept the consequences, and the existing `on_impassable` escape valve in player movement prevents permanent traps.
- **Inserters walkable surfaced at PAUSE smoke**, not in design pass. First commit blocked them by default; user immediately tested and asked to walk through. One-line fix per inserter type. **Pattern: smoke catches what design pass misses — physical "thin device" intuition is hard to anticipate without playing.**

---

## Inserter Arc Session 2 — Fast Inserter + Filter

**Date:** 2026-05-09
**Tag:** `session-inserter-fast-filter`
**Save:** v18 (no schema bump — new building type appended to enum, new state field with `.get(key, -1)` defensive default)

Second session of the 6-session Inserter Arc. Ships the **Fast Inserter** as a parallel tier to basic: same code path, twice the cycle speed (0.5s vs 1.0s), bundled with a single-slot **filter** capability (drop an item type to gate pickup; right-click clears). Plus a **parametric refactor** of `inserter.gd` so future tiers (electric / long-reach / stack) extend by adding rows to `*_BY_TYPE` tables instead of duplicating modules. Plus a **pre-existing fuel-port bug** caught at PAUSE 1 and fixed.

### What shipped

**`scripts/world/inserter.gd`** (refactored to tier-parametric): replaced single-tier constants `CYCLE_TICKS`, `BODY_COLOR` with per-type Dictionary tables `CYCLE_TICKS_BY_TYPE` and `BODY_COLOR_BY_TYPE`. Public API `Inserter.cycle_ticks(b)` and `Inserter.body_color(b)` look up by `b.type` with fallback to basic-tier defaults. `make()` signature gained a `b_type` parameter (defaults to `INSERTER`). Tick/draw/info_lines use the parametric path uniformly — both `INSERTER` and `FAST_INSERTER` route to the same `Inserter.tick(b, world)` function. Added `filter_item_type` field to state (default `-1` = no filter), checked in `_try_pickup` per-source helpers. **Future variant cost: ~1 row per table + 1 dispatch case in buildings.gd.**

**`scripts/world/inserter.gd` — Fuel-port bug fix:** added `const FUEL_PORT_DIR: int = Belt.DIR_S`, replaced `Burner.try_pull_fuel(b, world, -1)` (scan-all-edges) with `Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR))`. Mirrors the Smelter pattern from session-smelter. See "Lessons" for the bug story.

**`scripts/world/burner.gd`** (docstring): the FUEL PORT DIRECTION pattern is now front-and-center in the file header — "Do NOT pass -1 (scan-all-edges) in production code unless the building has no other item ports." Future Burner consumers won't repeat the bug from copy-paste oversight.

**`scripts/world/buildings.gd`**: appended `Type.FAST_INSERTER` to enum (APPEND-ONLY contract). Added DATA entry: 1×1 footprint, blue-grey swatch_color, 3-slot layout (held_item + fuel + filter). Dispatch cases in `make_one`, `tick_one`, `draw_one`, `info_lines_for` use comma-pattern `Type.INSERTER, Type.FAST_INSERTER:` so both tiers reach the shared Inserter.* code with no duplication.

**`scripts/ui/slot_widget.gd`**: new `BORDER_FILTER` color (cyan), `border_for_kind` "filter" case, `draw_slot` gained a `show_count` parameter (default true). Filter slots pass `show_count=false` so the icon renders without a count overlay (filter holds an item TYPE, not a stack — count would mislead).

**`scripts/ui/building_panel.gd`**: new `_drop_into_filter(slot_def)` helper — sets `b.state[state_field]` to `cursor.item_type` WITHOUT consuming the cursor. Match-statement cases added for `"filter"` in `_drop_into_slot`, `_take_from_slot` (no-op + discoverability toast), and `_draw_slots`. Filter is the **first non-storage slot kind** in the project; pattern documented at the FAST_INSERTER DATA entry.

**`scripts/ui/inserter_panel.gd`** (refactored for inheritance): now `class_name InserterPanel`. Extracted `_slot_y_offsets()` virtual hook so subclasses can inject additional rows. Facing-line draw anchored to `area.size.y - 40` so taller subclass panels position the line correctly without overrides.

**`scripts/ui/fast_inserter_panel.gd`** (new, ~85 lines): extends `InserterPanel`. Three small overrides: `_top_area_height()` (360 vs 280), `_slot_y_offsets()` (adds `"filter": 240`), `_draw_building_specific()` (calls super, then `_draw_filter_section`). Plus `_gui_input()` override for right-click-to-clear: hits filter slot rect → clears `filter_item_type` to -1 → `accept_event()` to consume the RMB so it doesn't fall through. Layout: `FILTER` cyan label at y=234, slot at y=240, filter name at y=258, hint at y=278, facing line at y=320 (42px breathing room).

**`scripts/main.gd`** + **`scenes/main.tscn`** + **`scripts/ui/hotbar.gd`**: standard wire-up — `@onready var fast_inserter_panel`, panel arrays in two places (`_ready` + `_all_building_panels`), click-to-open dispatch case for FAST_INSERTER, scene HUD node with ext_resource id `32_fastinspanel` (load_steps 34 → 35), Inserters hotbar category gains FAST_INSERTER as 2nd slot.

**`scripts/tests/test_inserter.gd`** (new, ~340 lines): 10 sub-suites covering basic-cycle regression (parametric refactor doesn't break Session 1), fast-cycle (10 ticks/cycle vs basic 20), filter unset = any item, filter set on chest source = matching only, filter set on belt source = matching picked / wrong-type stays on belt, panel drop-to-set (cursor TYPE copied, items not consumed), panel RMB clears filter, save round-trip preserves `filter_item_type`, AND **a regression test for the fuel-port fix** (wood in source chest is not eaten as fuel; fuel must come from S edge). **Tests: 31 → 32 passing**, internal sub-suite count 31 → 41.

### Decisions

- **Filter as tier-bundled capability, not orthogonal axis.** Fast inserter is "speed AND filter as a unit" — there's no slow-with-filter or fast-without-filter. Sanity-checked against Reversal #7's anti-pattern (don't conflate orthogonal axes): the test "would slow-with-filter make sense?" returns "no — filter IS what fast-tier means." Bundling is correct here. Future electric tier will bundle multi-filter; long-reach will bundle reach-2 with a base tier's filter capability.
- **`filter_item_type` is a UNIVERSAL state field across all inserter tiers.** Basic gets it too (default -1), even though basic has no UI to set it. Reasons: (1) Tick logic stays uniform — no `if b.type == FAST_INSERTER: read filter; else: skip` branching. (2) Future tiers inherit the field for free. (3) Save shape is consistent across tiers. The "filter unset → behave like basic" path is built into the pickup helpers as `if filter >= 0 and item_t != filter: continue` — a one-line no-op when filter is -1.
- **Parametric refactor uses Dictionary lookup tables, not subclass polymorphism.** `Inserter` is a static `RefCounted` class; subclasses would mean per-tier files with `extends Inserter` boilerplate. Tables are cleaner: one row per tier in `CYCLE_TICKS_BY_TYPE`, one in `BODY_COLOR_BY_TYPE`, future `ARM_LENGTH_BY_TYPE` for long-reach. Future variant cost stays sub-30-line.
- **`InserterPanel` uses virtual `_slot_y_offsets()` for subclass injection.** Pattern cribbed from `ProcessorPanel` (11 consumers via virtual hooks). FastInserterPanel overrides one method to add a row; future tiers add the same way. Compared to scene-tree-with-named-children, this keeps panel logic data-driven and inheritable.
- **'filter' slot kind is the FIRST non-storage slot in the project.** Three dispatch points in `BuildingPanel` (drop / take / draw) needed explicit `"filter"` cases — silent fallthrough would manifest as filter slots that pretend to have item counts or accept consumed drops. Documented at the FAST_INSERTER DATA entry so future metadata-style slot kinds (recipe picker, configuration toggle, etc.) follow the same explicit-case pattern.
- **Right-click handling is panel-local, not pushed into SlotWidget** (per re-orient guidance #2 — don't pre-emptively refactor click code). FastInserterPanel owns its RMB branch in `_gui_input`; existing click extraction trigger captured but DEFERRED to QoL session.
- **No save schema bump.** New building TYPE (append-only enum is save-safe) + new optional state field (defensive `.get(key, -1)`) are exactly what the migration framework treats as non-events. Bumping for this would dilute the framework's signal value.

### Lessons

- **Pre-existing fuel-port bug from Session 1 caught at PAUSE 1.** `Inserter.tick` called `Burner.try_pull_fuel(b, world, -1)` (scan-all-edges). Latent in Session 1 because the smoke test never put fuel-eligible items at source/destination. Session 2 manual smoke (placing **wood** in a source chest for testing) immediately surfaced it: inserter pulled wood from the source chest as **fuel** instead of transporting wood to the destination. **Fix: mirror the existing Smelter pattern from session-smelter** — `const FUEL_PORT_DIR: int = Belt.DIR_S`, restrict fuel intake to one specific perpendicular edge via `Buildings.world_dir(b, FUEL_PORT_DIR)`. Smelter shipped this protection in session-smelter; Inserter inherited the buggy `-1` from a copy-paste oversight from MiningDrill (which has no source-input port — drill output comes from the deposit tile under the building, not from an adjacent input). **Pattern captured in `burner.gd` header:** "Do NOT pass -1 (scan-all-edges) in production code unless the building has no other item ports." Regression test 10 in `test_inserter.gd` locks in the fix. **The bug was pre-existing for ~1 day; surfaced within 2 minutes of Session 2 smoke. Cost to fix: 5 minutes + 1 test. Cost if it had landed in production: every inserter player builds eats their items.**

- **Scope-creep mid-session was managed via "Option B: defer to follow-up" pattern, not by cramming in.** During implementation, user surfaced four out-of-scope asks: (1) shift/ctrl stack-split, (2) item hover tooltips with descriptions, (3) filter dropdown picker (a UX REVERSAL of the locked drop-to-set design), (4) building-blocks-movement (player walks around buildings, Factorio convention). Each was acknowledged with concrete scope (lines of code, architectural touchpoints) and explicitly **deferred to a "QoL Polish Session"** queued in NOTES.md. The inserter session shipped its locked design clean. **Pattern: when user surfaces UX preferences mid-implementation, the right move is "captured + deferred to a polish session," not "let me also land that real quick."** The polish session aggregates UX feedback from multiple sessions and lands them in one cohesive arc.

- **Layout-overlap caught at PAUSE 2 — anchored Y constants prevent regression.** First version of FastInserterPanel positioned filter at y=270 with hint text at y=308 and facing line at y=320 (12px overlap). Fix moved filter to y=240 (hint at y=278, facing at y=320 = 42px breathing room). **More importantly:** also factored out a `FILTER_Y` constant inside `_draw_filter_section` so all hint Y positions chain off one source — future tweaks are one-edit. **Pattern: when adjusting magic-number Y offsets, factor out a single anchor first; the second adjustment costs zero.**

- **Filter UX clarity check at PAUSE 2 — "(any item)" placeholder works without escalation.** Architectural concern #6 from design pass anticipated potential UX confusion ("player tries to take items from filter slot, expecting buffer semantics"). Player tested by setting WOOD as filter against a chest with wheat+flax: inserter correctly stopped (no matching items). Player initially read this as a bug ("but the chest has stuff!") then confirmed it's correct behavior on explanation. **Concrete future polish:** add `Status: IDLE (no items match filter)` diagnostic line in panel/Q-inspect — currently silent on the WHY of idleness. Captured for the QoL session.

- **MCP wasn't useful for this session.** godot-mcp was available throughout but offered no concrete value: it can only screenshot the running game and read editor scene-tree defaults (per session-inserter-foundation lessons). The bug-find at PAUSE 1 came from user manual smoke — exactly the workflow MCP can't help with. **Pattern: the screenshot-only path of MCP is useful when the user can't easily share what they're seeing. When the user is hands-on at PAUSE time, MCP adds no value.**

---

## Inserter Arc Session 1 — Foundation (basic inserter, fixed-cycle)

**Date:** 2026-05-08
**Tag:** `session-inserter-foundation`
**Save:** v18 (no schema bump — new state fields are additive with `.get(key, default)` fallbacks)

First session of the planned 6-session Inserter Arc. Ships **the** basic inserter: 1×1 building, fuel-powered via the Burner module, fixed 1.0s pickup-and-deliver cycle, swinging-arm animation. Universal source/destination — picks from belts, chests, or recipe-driven Processor `out_buffer`s; drops onto belts, into chests, or into Processor `in_buffer`s. **Closes the only remaining "you can't connect a chest to a building without a belt going past it" hole** in the factory layer.

### What shipped

**`scripts/world/inserter.gd`** (new, ~440 lines): 5-state phase machine (IDLE / WORKING_OUT / BLOCKED_AT_DEST / WORKING_IN / NO_FUEL), `cycle_progress` (0.0–1.0) drives both transitions and arm-rotation rendering. Source/destination resolved via `Belt.DIR_VECS[dir]` (source = anchor − dir; destination = anchor + dir). Pickup/drop dispatched per source-building type: belts use `Belt.slot_facing_external` for handoff, chests pop FIFO from `bag`, Processors pop FIFO from `out_buffer`. Drop side mirrors: `Belt.try_insert`, chest bag append/top-up, Processor `in_buffer` with capacity + `accepts` checks against `Buildings.slot_layout_for(type)`.

**`scripts/world/burner.gd`** (modified): added `last_fuel_item: int = -1` to `make_state()` and to both `_try_pull_from_belt` / `_try_pull_from_chest`. Display-only field; no behavior coupling. Drill and Smelter inherit the fix automatically.

**`scripts/ui/inserter_panel.gd`** (new, ~140 lines): specialized BuildingPanel showing held-item slot, fuel slot, source/destination tile summary, cycle-progress bar with state-tinted fill (bronze when working, yellow when blocked), facing indicator. Hits the same drag-drop infrastructure as drill/smelter via the slot_layout pattern.

**`scripts/ui/building_panel.gd`** (modified): the shared "fuel"-kind slot renderer now reads `last_fuel_item` and divides `fuel_buffer` by `Burner.FUEL_VALUES[item]` so coal shows "COAL ×3" (3 items) instead of "WOOD ×12" (12 units). The drag-drop path (`_drop_into_fuel`) sets `last_fuel_item` to the cursor item type. **Bonus retroactive fix:** drill/smelter panels now show the correct fuel item icon too — this was a pre-existing display bug that only became user-visible when the inserter session put a fuel slot in front of a player who'd been dropping coal directly.

**`scripts/world/buildings.gd`** (modified): `Type.INSERTER` enum entry, DATA registration (footprint 1×1, supports_direction=true, slot_layout = held_item + fuel), dispatch cases in `make_one`, `tick_one`, `draw_one`, `info_lines_for`.

**`scenes/main.tscn`** (modified): added InserterPanel HUD node (load_steps=34, ext_resource id 31_inspanel).

**`scripts/main.gd`** (modified): `@onready var inserter_panel`, `@onready var dev_console` (untyped — see Lessons), wires `hotbar.dev_console = dev_console`, console-open gate at `_process` line 358 to suppress `Input.is_action_just_pressed` matches while typing, click-dispatch case for INSERTER to open the panel.

**`scripts/ui/hotbar.gd`** (modified): new "Inserters" hotbar category with a single INSERTER slot, console-open gate at `_process` to suppress hotbar number-key + Tab actions while typing.

**`scripts/player.gd`** (modified): `dev_console` field added to the `modal_open` check so WASD doesn't move the player while the console captures keystrokes.

**`scripts/ui/console.gd`** (substantially rewritten): see "Console focus rewrite" below — the focus bug surfaced during PAUSE 1 forced a deep rewrite of how the LineEdit handles Enter. Plus Tab-completion for command names landed as a small QoL addition at user request.

### Decisions

- **Single basic inserter, fixed 1.0s cycle (REVERSAL #7).** Original design had cycle speed determined by fuel tier (wood=2.0s, coal=1.0s, briquette=0.5s). Rolled back during PAUSE 1 because **conflating fuel-energy-density and machine-throughput is two orthogonal axes pretending to be one**: a player who burns coal expects "coal lasts longer" (yes — 4× the energy units per item), not "coal is also faster" (no game-design reason for that). Fast Inserter / Stack Inserter variants in future sessions will be **separate building types** with their own cycle constants, not the same building running at different speeds. Captured in `inserter.gd` header comment so future readers don't re-discover the question.
- **`last_fuel_item` is display-only state.** Tracked in Burner's `make_state` so it's free for all burner consumers (drill, smelter, inserter, future kilns), set on every fuel-pull/drop path. Never read by tick logic, fuel economy, or save migration — just by the panel renderer. Mixed-tier buffers display whichever fuel was added last, which is fine because players in practice feed one tier at a time.
- **Inserter does NOT use the Processor pattern.** Considered making it a recipe with no `inputs/outputs` and a `process_ticks: 20` pseudo-recipe — rejected. The Inserter has 4 distinct phases (idle / working-out / blocked / working-in) that are state-machine-shaped, not recipe-shaped. Forcing the Processor mold would have meant either bolting state-machine logic onto Processor (corrupting the abstraction) or leaving the state machine in Inserter with the recipe being an unused adapter (dead complexity). Custom `tick(b, world)` is the right tool here.
- **Universal source/dest dispatch via heuristics, not registration.** `_is_processor_with_output(b)` checks for `b.state.has("out_buffer")` rather than maintaining a registry of "which building types have outputs." Works for every current case (Mill, Mixer, Composter, Smelter, Thresher) and is forward-compatible with new processors automatically.
- **Console Enter handling: intercept in `_input`, not `text_submitted`** (see Lessons for why this took 6 attempts to land correctly). Once the right architecture was found, the implementation collapsed to ~10 lines.
- **Tab completion: command-name only, not arguments.** Argument completion would need per-command schemas (item names for `give`, building names for `place`, valid x/y ranges for `tp`). Defers cleanly until a future session if anyone asks for it.

### Lessons

- **Console focus rewrite — "the right architecture was 5 attempts of code-fighting away."** PAUSE 1 surfaced a focus bug: after pressing Enter to submit a command, the LineEdit lost focus and the user had to left-click to type again. Five increasingly-aggressive fixes failed:
  - (1) `grab_focus()` after submit — lost the race with LineEdit's internal Enter handling.
  - (2) `call_deferred("grab_focus")` — still raced.
  - (3) `focus_exited` signal hook re-grabbing — fired but focus immediately bounced again.
  - (4) Per-frame `_process` brute-force re-grab — diagnostic showed `input_focus=true` was already true, but the user still couldn't type.
  - (5) Diagnostic prints — confirmed Godot's focus state was correct but typing didn't reach the LineEdit.

  The breakthrough was switching frame of reference: **stop trying to restore focus after Enter; intercept Enter before LineEdit ever sees it.** `Node._input(event)` runs *before* Godot's GUI dispatch routes the event to the focused control. Catch Enter there, pull `_input_field.text` directly, clear, dispatch — call `set_input_as_handled()` — done. LineEdit never sees the Enter, never runs its internal Enter handling, never has a chance to release focus. **The whole class of bugs vanishes.** Per-frame `_process` safety net stays as a single line for edge cases (clicking outside the input briefly clears focus to null). Sets `RichTextLabel.focus_mode = FOCUS_NONE` so the scrollback can't steal focus on click. ~5 lines of fix code; ~80 lines of removed scaffolding from prior attempts.

  **Anti-pattern recognized: when a Godot signal causes a state issue and you find yourself fighting deferred-call timing, look for a way to bypass the signal entirely.** `text_submitted` was the wrong abstraction for "command-line Enter" — the LineEdit's notion of "submit" includes focus-release semantics that don't fit a console use case. The right fix wasn't to suppress the side effect; it was to never trigger the signal in the first place.

- **Pre-existing display bug only became visible when the new feature put it in front of the player.** The fuel-slot-shows-WOOD bug had been latent in `building_panel.gd` since drill/smelter shipped — those panels already rendered fuel as "WOOD ×N units." But because drills are typically loaded from belts (player rarely opens the panel) and smelters had recipe focus pulling player attention, **nobody noticed**. The inserter session put a fuel slot front-and-center in a workflow where players directly drag-drop coal in to test, and the bug was caught within minutes of PAUSE 1 verification. **Pattern: when adding a new consumer of a shared component, expect to surface latent bugs in that component that previous consumers had been working around or ignoring.**

- **Don't conflate orthogonal axes in a single mechanic** (fuel-tier × cycle-speed reversal). A clean-feeling design that combines two systems can hide a category error: are these two axes really one axis, or are they two? Symptom that you've conflated them: the player asks "wait, why does coal make it FASTER?" and you have no satisfying answer beyond "because we coupled them." When the answer to "why" is mechanic-driven (energy density), the axis is one. When the answer is design-fiat (because we said so), it's probably two pretending to be one. Reversal #7 is now in NOTES.md as a referenced anti-pattern for future arc-session design passes.

- **`var dev_console: Control = null` typed-cast at runtime errors with "Nonexistent function `is_open`."** `is_open()` lives on the `DevConsole` subclass, not the `Control` parent. Even though @onready resolves the actual instance correctly, the static type bound on the variable causes Godot's method-resolution to look on the *declared* type, not the runtime type. Workaround: `var dev_console = null` (untyped) — duck-types `is_open()` correctly. Same gotcha would apply to any HUD child accessed through a parent-typed reference. **Pattern: for autonomous Control subclasses with subclass-only API, leave the @onready var untyped.**

- **MCP servers need an editor to talk to.** Installed godot-mcp during this session for the focus-bug debugging, then discovered it requires the Godot **editor** (not the game binary) running with the addon enabled to expose its websocket bridge. We were launching the game directly via the headless-friendly `Godot.exe --path` path, which doesn't run the editor. The MCP would have been useful if I'd been working from the editor IDE, but for our terminal-driven workflow it added zero value to this debugging session. **Pattern: before installing a new MCP, verify it works with how you actually run the project, not how its README assumes you do.** Keeping it installed for future use — `node get_properties` and `screenshot_game` tools have real value when running tests through the editor.

---

## Save Migration Framework — **CLOSE-OUT OF MAJOR TOOLING DEBT**

**Date:** 2026-05-08
**Tag:** `session-save-migration`
**Save:** v18 (no schema change this session; framework lets v17 saves migrate forward to v18)

Replaces the prior "hard-fail on schema mismatch" policy with chained migration steps. When loading a save with version < SAVE_VERSION, the framework walks `MIGRATIONS[N] → MIGRATIONS[N+1] → ...` until it reaches the current schema. **Player keeps save state across game updates instead of losing it on every schema bump.**

This closes the second half of the schema-mismatch UX gap captured at session-soil-exhaustion-3-5. The first half (post-3.5 hotfix: graceful fresh-world fallthrough on load failure) protected players from being stranded in an empty world. This session protects their save DATA from being lost.

### What shipped

**`MIGRATIONS` registry** (`save_system.gd`): centralized Dict keyed by source version → migration method name (string). One entry today: `17 → "_migrate_v17_to_v18"`. Grows by one entry per future schema bump.

**`_try_migrate(data, from_version, to_version) -> Variant`**: chain orchestrator. Walks the registry one version at a time, verifying each step produces a `version: N+1` dict before continuing. Returns the migrated Dictionary on success OR `null` on any failure (gap in chain, malformed migration output, etc.). Pure data transformation — no game state mutation, no I/O.

**`_dispatch_migration(method_name, data) -> Variant`**: match-statement router. Each registered migration adds one match case. (See Decisions for why match instead of `Object.call(name)`.)

**`_migrate_v17_to_v18`** — first migration. Schema diff was a single field addition (`tile_wasteland_state`); migration is correspondingly trivial:
```gdscript
static func _migrate_v17_to_v18(data: Dictionary) -> Dictionary:
    data["tile_wasteland_state"] = []
    data["version"] = 18
    return data
```

**`load_game` refactored**: prior single-line version-equality check replaced with the migration chain. Forward-only: a save with version > SAVE_VERSION (newer game build than running binary) hard-fails with a clear "update the game" message. Worldgen version mismatch still hard-fails as a separate axis (covered below).

**`test_save_migration.gd`** (new): 8 sub-suites covering registry shape, the v17→v18 migration's happy path, single-step / no-op / no-path / unknown-dispatch chain orchestration, an end-to-end load_game round-trip (write a synthetic v17 save, load, assert state preserved + tile_wasteland_state defaulted to empty), and forward-incompatibility (v19 save fails with the expected message). **30 → 31 passing in runner**; the test file packs 8 internal sub-suites.

**`CONVENTIONS.md`** — replaced the prior 5-line "Save schema" section with a full schema-bump protocol covering: 7-step bump checklist, migration robustness guidelines (defensive `.get()`, type validation, float-coercion handling, ≤80-line guideline), failure handling, breaking-change reset point (v17), and the worldgen-version-is-separate-axis rule.

**Manual smoke verified:** edited a real saved game from v18 → v17 (changed version field, removed `tile_wasteland_state`), relaunched. Migration ran cleanly: no `OS.alert`, normal "World loaded" toast, all player state preserved (position, inventory, buildings, soil, fertilizer), wasteland dict defaulted to empty. F5 saved back as v18 with the field restored.

### Decisions

- **Centralized registry in `save_system.gd`** (vs per-file modules under `scripts/systems/migrations/`). Single file is right for ≤5 migrations / ≤80 lines each. Per-file split deferred until thresholds breached. Pattern documented in NOTES.md.
- **Match-statement dispatcher** (`_dispatch_migration`) instead of `SaveSystem.call(method_name, data)`. **Godot static-method quirk:** `Object.call()` is instance-only and errors with "Cannot call non-static function `call()` on the class directly" when invoked on a script class. Tried `Callable(SaveSystem, name)` — also unreliable for static methods. Match-statement is slightly verbose (one new case per migration) but unambiguous, statically checkable, and produces a clean error if a registered migration is missing its dispatch case.
- **v17 cutoff for migration coverage.** No production players exist; v14/v15/v16 saves only ever existed as schema-history reference (Session 1 region-scoped data was reversed at Session 2 → v16 was the first stable per-tile baseline). Writing back-migrations for v14→v15→v16→v17 would be 3 unused functions. Documented in CONVENTIONS.md under "Breaking-change reset point: v17."
- **Forward-only migration; backward not in scope.** Older binaries reading newer saves hard-fail with "update the game." Reasonable: if save format diverges across game versions enough that backward migration would matter, the player can simply update.
- **Worldgen version stays as a separate hard-fail axis.** Procgen-output changes for the same seed cannot be data-migrated — buildings positioned against old terrain would silently end up on water / stone / wrong overlays. Surfacing the failure and falling through to fresh world (existing post-3.5 hotfix) is the only safe behavior. Documented.
- **Migrations are pure transformations** (Dictionary in, Dictionary out — no game state, no I/O, no `print`). Lets them be tested in isolation without standing up a full GridWorld + Player + Inventory. The end-to-end test layer covers integration; the unit-test layer covers transformation correctness.
- **Defensive verification at every step** (`_try_migrate` checks new_version == current+1 after each migration). Catches "migration forgot to bump the version" bugs at the failing step (named in error) instead of at downstream-data-shape mismatch points where the cause is opaque.

### Lessons

- **Godot static-method dispatch is a real gotcha.** `SaveSystem.call(method_name, data)` parsed fine but errored at runtime: "Cannot call non-static function `call()` on the class `SaveSystem` directly. Make an instance instead." `Object.call()` is a virtual method on instances; static script classes don't expose it. **Match-statement dispatch is the GDScript-static-friendly pattern** for "call function by name string" — captured in CONVENTIONS.md schema-bump protocol so future migrations follow the pattern automatically.
- **Test 7 (end-to-end save → mutate to v17 → load) was the highest-value test.** Unit tests of `_migrate_v17_to_v18` are valuable for catching transformation bugs, but the realistic scenario — write a save with the actual `save_game()` machinery, mutate the file to look like v17, run the actual `load_game()` path — exercises the entire integration: JSON round-tripping, sparse Dict serialization, post-migration `tile_wasteland_state.clear() + restore` loop. If any of those broke during the framework refactor, the unit tests would still pass and the bug would only surface in production. The end-to-end test caught zero bugs this session, but its presence is the safety net that lets future refactors of `load_game` proceed confidently.
- **Manual smoke validated nothing because design + tests were already correct.** Every migration test passed on the first run; manual smoke confirmed in-game behavior matched test expectations. **This is a positive signal**: the design pass anticipated the failure modes (gap in chain, version-bump bug, forward-incompat, end-to-end correctness) and the tests covered them. PAUSE 1 was a confirmation step, not a discovery step. **Pattern: when smoke catches nothing, the design pass + tests did their job. When smoke catches something (cf. session-soil-exhaustion-4 PAUSE 1, 2 bugs), the gap was in the test→smoke coverage seam.**
- **Tooling debt close-out has compounding payoff.** Save-migration framework was queued post-3.5 hotfix; its prerequisite (Dev Console for rapid migration testing) was queued before that. Both shipped within ~24h of each other, and Session 4 wasteland used the Dev Console to set up scenarios that would have been 30-min builds otherwise. **Investing in tooling pays off across sessions, not within the session that ships the tooling.** Captured pattern: when proposing a new feature, ask "what tooling makes future sessions cheaper?" and consider sequencing the tooling first.

### Roadmap implications

- **Major queued debt: closed.** Migration framework was the largest pending tooling item. NOTES.md "schema-mismatch UX gap" entry now reads "both fixes SHIPPED."
- **Future schema bumps** follow the protocol in CONVENTIONS.md. Each bump = ~10 LOC migration + ~20 LOC test + 1 PROJECT_LOG entry. Framework cost amortized to near-zero per future bump.
- **Per-file migration modules deferred** until `MIGRATIONS` grows past 5 entries or a single migration past 80 lines.
- **Backup-before-migration** still queued as nice-to-have. Defer until production players exist.

### Known follow-ups

- **Per-file migration modules** (when `MIGRATIONS` >5 entries OR single migration >80 lines).
- **`migrate_test <from_version>` Dev Console command** if migration testing becomes frequent. Currently the manual workflow (edit save JSON, relaunch) is fast enough.
- **Backup-before-migration** (`save_slot_1.json.bak.pre-v18` written before migration runs, restored on failure). Adds confidence for production players. Niche today; defer.
- **No production cutoff** documented for when v17-and-earlier saves should be advanced. Will become relevant when real players exist.

---

## Soil exhaustion — Session 4 — **WASTELAND MECHANICS + ARC CLOSE-OUT**

**Date:** 2026-05-08
**Tag:** `session-soil-exhaustion-4`
**Save:** v17 → v18 (hard-fail v17 per existing policy; gracefully regenerates fresh world via post-3.5 hotfix)
**Worldgen:** v3 → v4 (fallback-lake origin-exclusion — no water at spawn origin)

**This is the close-out of the multi-session soil arc.** Sessions 1–4 ship a complete stewardship loop: deplete fast → grace warning → wasteland scarring → Premium Compost restoration. Real failure state. Real recovery path. Optional Session 5 (legumes) deferred indefinitely as polish — the core mechanic is complete without it.

### What shipped

**Wasteland state machine (the mechanic):**
- Tile soil at 0 starts a 60-second grace timer (`WASTELAND_GRACE_SEC`).
- Grace timer counts down ONLY while soil stays at 0; soil rising to ≥1 erases the grace entry (recoverable mid-grace).
- Grace expiry → tile becomes scarred (persistent `tile_wasteland_state[pos].scarred = true`).
- Scarred tiles SKIP all passive regen — `_tick_soil_regen` early-continues for them.
- Visual: `WASTELAND_TINT` (near-black brown) overlaid + 2 diagonal `WASTELAND_CRACK` lines forming an X near tile center. Distinct from the existing DEAD tint (which represents "soil at 0, recoverable").
- Same-tick rescue path: when regen lifts soil from 0 → >0 in a single tick AND grace was active, the grace state erases at the end of that same tick (no 1-frame delay where grace persists past the rescue).

**`COMPOST_HIGH` ("Premium Compost") activated** (was deferred from Session 3):
- Items.Type.COMPOST_HIGH appended to enum, color `Color(0.22, 0.16, 0.10)` — top of the brown gradient.
- Two new Composter recipes (`composter_high_bread`, `composter_high_loafpack`):
  - `BREAD × 2 → COMPOST_HIGH × 1` at 200 ticks (10 sec)
  - `LOAF_PACK × 1 → COMPOST_HIGH × 1` at 200 ticks
- Composter slot_layout `accepts` lists extended; `_INPUT_TO_RECIPE` map gains BREAD + LOAF_PACK entries.
- Fertilizer Applicator slot accepts HIGH alongside LOW + MID.
- `fertilizer_multiplier(HIGH) = 8.0`, `fertilizer_duration(HIGH) = 120.0` extending the existing tier table.

**Restoration via `try_apply_fertilizer`:**
- HIGH on scarred tile → `_restore_wasteland(pos)` erases scarred flag + snaps `tile_soil_modifications[pos]` to **30** (`WASTELAND_RESTORE_SOIL`) + applies HIGH boost (8× for 120s).
- HIGH on healthy tile → applies HIGH boost (just a stronger MID — no soil snap).
- LOW or MID on scarred tile → REJECTED with explicit toast ("only Premium Compost restores wasteland"), no inventory consumption. Prevents wasted lower-tier compost on scarred soil where it wouldn't help anyway.
- Stacking rules extended: HIGH > MID > LOW.

**Recovery timing math (designed, not arbitrary):**
- Snap-to-30 + 8× boost for 120 sec = 32 soil points recovered in boost window → tile at 62 at boost end.
- 62 → 100 via natural regen (38 pts × 30 sec/pt) ≈ 19 minutes.
- **Total wasteland-to-fully-healed: ~21 min.** This is the intended "wasteland is real loss" timing. Tunable from playtest data; do not change without playtest evidence.

**Planter idle gate** (extends Session 1 soil-zero gate):
- Planter at growth==0 stays IDLE if `tile_soil_health(anchor) <= 0` OR `is_wasteland_at(anchor)`.
- Wasteland check is structurally redundant (wasteland implies soil 0) but explicit so future soil-gate semantics changes don't accidentally remove the wasteland gate.
- In-progress crops (growth > 0) still finish gracefully — wasteland blocks NEW cycles only.

**Q-inspect three states** in `info_panel.gd`:
| State | Soil line | Action prompt |
|---|---|---|
| Healthy / damaged / dying | `Soil: N / 100 (level)` + activity suffix | (existing fertilizer line if active) |
| Soil 0, in grace | `Soil: 0 / 100 (DEAD — will scar in Xs)` red | (existing fertilizer line if active) |
| Wasteland scarred | `Soil: 0 / 100 (WASTELAND)` red | `Apply Premium Compost to restore.` |

**PlanterPanel wasteland messaging:**
- `Status: IDLE — tile (X, Y) is WASTELAND` (red)
- `Action: Apply Premium Compost to (X, Y).` (red, second line)

**Save schema v17 → v18:**
- New top-level field `tile_wasteland_state`: sparse Array of `[x, y, scarred_bool, decay_remaining_float]`.
- Both fields persist (mid-scarring tiles resume countdown after load).
- v17 saves hard-fail with OS.alert; post-3.5 hotfix gracefully regenerates fresh world.

**Worldgen v3 → v4 (`FALLBACK_LAKE_ORIGIN_EXCLUSION = 6`):**
- The spawn-area-safety-net `_ensure_spawn_area_water` was placing fallback 4×4 lakes at the closest-to-origin candidate, which often centered on (0, 0) on low-natural-water seeds.
- Caught at PAUSE 1 re-smoke when the user noticed every fresh world had water at origin.
- Fix: anchors within Chebyshev distance 6 of origin are excluded from the fallback candidate pool. Spawn-safety floor (`SPAWN_AREA_MIN_WATER = 12`) still met from the rest of the spawn area.
- Bumped `WorldGenerator.VERSION` (procgen change → same-seed-different-output → existing v3 saves hard-fail). Hotfix from post-3.5 catches the fail and regenerates.

**Dev Console additions:**
- `wasteland <x> <y>` command — directly forces scarred state at a tile (bypasses 60-sec grace). Required for testing wasteland mechanics without setting up active planters to keep soil pinned at 0.
- `tile <x> <y>` now shows base/overlay names (`Base: GRASS, Overlay: NONE`) instead of raw enum ints.
- `tile` output gains a wasteland status line (`Wasteland: SCARRED` or `in grace, will scar in Xs`).
- `fertilize` accepts `high` tier in addition to `low | mid`.
- `place` auto-overlay-set now picks the first non-NONE overlay from the building's `requires_overlay` list (e.g., SOIL_TILLED for Planter, STONE for Mill) instead of blanket STONE.

**Hotbar Soil category:**
- Grew from 4 slots to 5: added `Apply Premium Compost` (item_apply for COMPOST_HIGH). Inventory-empty slot dimming works for HIGH same as the existing tiers.
- This was Bug 2 from PAUSE 1 — the entire wasteland recovery path was unreachable until this slot was added.

**Tests: 30 → 31 passing**, but the new test file (`test_wasteland.gd`) has 9 sub-suites:
- 1. Trigger: soil 0 + grace expiry → scarred
- 2. Grace reset: soil rises above 0 before expiry → no scar
- 3. Wasteland blocks regen: scarred tile + 60 sec ticks, soil stays at 0
- 4. Planter idle on wasteland: planter on scarred tile, growth stays at 0
- 5. Premium Compost on wasteland: scarred flag erased, soil → 30, HIGH boost applied; LOW/MID on scarred REJECTED
- 6. Save round-trip preserves grace + scarred (v18)
- 7. Composter HIGH recipes: BREAD × 2 → HIGH, LOAF_PACK × 1 → HIGH
- 8. Stacking: HIGH > MID > LOW (apply MID/LOW to HIGH-fertilized tile rejected)
- 9. (14i) Grace rescue: LOW boost during grace + 30s regen → grace state erased, no scar

(The "+1 test" goes from 30 → 31 in test_runner output but the file packs 9 sub-suites internally.)

### Decisions

- **60-second grace period.** Player gets ~2 wheat-harvest cycles to react before scarring. Tunable; chosen for "felt like real soil exhaustion" rather than binary on/off.
- **Snap-to-30 + 8× boost (NOT snap-to-100).** Wasteland recovery should feel like a real loss-recovery cycle, not a minor speed bump. The ~21 min total recovery is the design target. If playtest says "feels too harsh," tune snap-to-50 or extend boost duration. Don't tune without playtest data.
- **HIGH on healthy tile = stronger MID (8×/120s).** Considered restricting HIGH to wasteland-only ("save your premium compost for emergencies"). Rejected: universal usefulness wins over enforced scarcity. Players paying the upstream cost (bread chain) self-regulate. Could be revisited if playtest reveals exploit pattern (e.g., players HIGH-spam non-wasteland fields for trivial speedup).
- **Both BREAD AND LOAF_PACK recipes for HIGH.** Loaf pack is the better deal (1 input vs 2, but each loaf_pack costs 4 bread upstream). Intentional design pressure to build the full Packager chain for sustainable wasteland recovery.
- **Wasteland blocks crop production (planter idles), NOT building placement.** Player can build a composter on a wasteland tile to recover. Wasteland blocks the *crop production* mechanic, not infrastructure. Considered blocking placement; rejected — too restrictive, no thematic reason.
- **Existing planters stay placed when their tile transitions to wasteland.** Planter goes idle (visible in PlanterPanel + Q-inspect). Considered destroying — rejected, would force players to remember placement positions, bad UX.
- **Explicit tile_wasteland_state dict (NOT computed from soil 0 + duration).** Both grace progress and scarred flag must persist across saves. Computing from soil-time-at-zero would lose state on every save/load. Sparse parallel dict mirrors existing tile_fertilizer_state pattern.
- **Same-tick grace rescue** (post-increment check). Without this, grace state would persist for one extra tick after regen lifted soil > 0. Doesn't affect correctness (next tick clears) but affects test predictability and player feel ("I just rescued this tile, why does the panel still say grace?"). Same-tick erasure makes "rescue during grace" feel responsive.
- **Worldgen v3 → v4 origin-exclusion as a same-session fix.** Caught during PAUSE 1 re-smoke. Could have deferred to a separate hotfix. Shipped here because (a) it directly affects the testing flow this session validates ("`wasteland 0 0` requires (0, 0) to be land"), and (b) the procgen version bump is gracefully handled by the post-3.5 hotfix anyway.

### Lessons

- **PAUSE 1 paid off immediately on first Dev Console use.** Test coverage was the commit gate for the Dev Console session itself; manual smoke deferred to "first real-use." That first real-use was THIS session, and it caught 2 real bugs:
  - **Bug 1** (display): `tile <x> <y>` showed raw enum ints (`base: 0, overlay: 0`) instead of names. Cosmetic, easy fix.
  - **Bug 2** (CRITICAL): Premium Compost hotbar slot was MISSING. The entire wasteland recovery path via hand-apply was unreachable. Tests didn't catch this because tests bypass the hotbar layer entirely (call `try_apply_fertilizer` directly). Without smoke, this would have shipped — wasteland-as-a-mechanic, not wasteland-as-a-feature.
  - The "ship tooling without exhaustive UI testing, surface bugs on first real use" pattern from session-dev-console is now validated. Both classes of bug (cosmetic + critical-feature-gap) were caught in the cheapest possible context.
- **Tests don't replace smoke for end-to-end UX flows.** Test 5 in `test_wasteland.gd` directly calls `try_apply_fertilizer(pos, COMPOST_HIGH)` and verifies state mutation — and passes. But the player journey is "click hotbar slot → check toast → check tile state." Bug 2 was invisible at the data layer (the apply function works) but broken at the UX layer (no slot to click). **Future protocol: when adding a new tier or category, smoke the full PLAYER path, not just the data path.** Captured in NOTES.md.
- **Spawn-area worldgen quirks deserve their own watchlist.** "Every world spawns with water at origin" was a latent issue from the spawn-safety-net design — the candidate-sort algorithm picked the closest-to-origin anchor by construction. Hadn't surfaced because previous sessions didn't test directly at (0, 0) — they used arbitrary coordinates. The dev console encourages (0, 0) as the natural test origin, which exposed the issue. **Lesson: as testing tools change, latent issues surface where they couldn't before.**
- **Three architectural patterns from this arc, all earned:** (a) **per-tile-not-region** (Session 1 → Session 2 reversal #5), (b) **manual-before-automation** (3 instances now: mining, soil hand-apply, soil applicator), (c) **explicit-state-not-computed** (per-tile soil, fertilizer, wasteland — all sparse parallel dicts with persistent state, not derived). All three came from playtest pressure, not advance design. The arc that started as "deplete soil when crops harvest" ended with a complete stewardship-tension system because each session learned from the previous one's playtest. **Multi-session arcs work when each session genuinely learns from the previous one's lived behavior.**

### Roadmap implications — soil arc COMPLETE

| Session | Status | Tag |
|---|---|---|
| Session 1 — region-based soil_health (REVERSED) | shipped → reversed | `session-soil-exhaustion-1` |
| Session 2 — per-tile refactor + visual states + regen | SHIPPED | `session-soil-exhaustion-2` |
| Session 3 — Composter + hand-apply fertilizer + COMPOST_LOW/MID | SHIPPED | `session-soil-exhaustion-3` |
| Session 3.5 — Fertilizer Applicator + composter prefer_dir fix | SHIPPED | `session-soil-exhaustion-3-5` |
| Session 4 — Wasteland + COMPOST_HIGH + arc close-out | **SHIPPED** | `session-soil-exhaustion-4` |
| Session 5 — Legumes / crop rotation healing | OPTIONAL polish, deferred indefinitely | — |

Save schema arc: v14 → v15 (region) → v16 (per-tile) → v17 (fertilizer) → v18 (wasteland). 4 schema bumps in the arc; one quick-fix UX session (post-3.5 schema-mismatch fallthrough); migration framework still queued.

### Known follow-ups

- **Session 5 (legumes)** deferred indefinitely. Negative-soil-cost crops (legumes) heal their 3×3 area instead of depleting. Player learns "wheat → flax → legume + fertilize the dying patches" rotation. Optional polish — the wasteland mechanic completes the arc on its own.
- **Migration framework** still queued (now post-Dev Console + post-Session-4). Replaces hard-fail with chained migration steps. Would let players preserve save data across the 4 schema bumps in this arc.
- **Premium Compost universal-usefulness** could be revisited if playtest reveals HIGH-spam exploit. No change without evidence.
- **Wasteland recovery timing (~21 min total)** flagged for playtest re-confirmation before any tuning.

---

## Dev Console — **TOOLING INVESTMENT, NOT GAMEPLAY**

**Date:** 2026-05-08
**Tag:** `session-dev-console`
**Save:** v17 (no schema bump — console is a runtime tool only)

In-game console for development testing. Press backtick (`` ` ``) to toggle. Type commands to manipulate game state directly instead of slow farm-to-test setup. Debug-build-only — gated by `OS.is_debug_build()`. Production exports never see the console.

This is a **tooling session**, not a gameplay session. The payoff is every subsequent session: replacing 5–10 min of "build a planter chain to feed a composter to feed an applicator to test wasteland reclamation" with 3-line console setup (`set_soil 0 0 0; place applicator 0 0; give compost_mid 5`). Cost recovered within 2–3 future sessions.

### What shipped

**12 commands** registered in a single `_commands` Dict for tokenize-and-dispatch:

| Command | Form | Behavior |
|---|---|---|
| `help` | `help [<cmd>]` | List 12 commands or show usage for one |
| `seed` | `seed` | Print current world seed |
| `tile` | `tile <x> <y> [radius]` | Tile detail (radius 0) or soil grid (radius >0) |
| `give` | `give <item> <count>` | Add items to player inventory |
| `place` | `place <building> <x> <y> [dir]` | Place building at tile; auto-sets STONE overlay if needed |
| `destroy` | `destroy <x> <y>` | Remove building at tile, no drops |
| `tp` | `tp <x> <y>` | Teleport player to tile |
| `set_soil` | `set_soil <x> <y> <value>` | Direct write to tile_soil_modifications, clamped 0..100 |
| `deplete_area` | `deplete_area <x> <y> <radius> [amount]` | Bulk deplete Chebyshev-radius square (default 50) |
| `fertilize` | `fertilize <x> <y> <tier>` | Direct write to tile_fertilizer_state, tier=low/mid |
| `clear` | `clear inventory \| clear chest <x> <y>` | Wipe inventory or named chest |
| `tick_speed` | `tick_speed <multiplier>` | Multiply tick rate, clamped [0.1, 10.0] |

**Files added:**
- `scripts/ui/console.gd` (657 lines): UI panel + parser + 12 command implementations + arg-parsing helpers + `_format_tile_detail` / `_format_tile_grid`.
- `scripts/tests/test_console.gd` (182 lines): parser tokenization, item/building/dir name resolution, error message structure, tick_speed clamp, give end-to-end (inventory mutation), tp end-to-end (position mutation).

**Files modified:**
- `scripts/systems/tick_system.gd`: added `tick_rate_multiplier: float = 1.0`. Console writes to it for fast-forward testing.
- `scripts/main.gd`: backtick activation in `_unhandled_input` (gated by `OS.is_debug_build()`); console reference + game-state wiring; modal-open input gating.
- `scripts/player.gd`: movement gates on `dev_console.is_open()` so WASD doesn't move the player while LineEdit captures keystrokes.
- `scenes/main.tscn`: `DevConsole` node under HUD, ext_resource for the script.
- `scripts/tests/test_runner.gd`: registered `test_console.gd`.

**Tests: 28 → 29 passing.** New `test_console.gd` covers ~25 sub-checks.

### Decisions

- **One file (console.gd) for UI + parser + commands.** Considered splitting into `console.gd` (UI) + `console_commands.gd` (parser + dispatch). At 657 lines, kept as single file — splitting becomes worth it past ~800 lines (queued in NOTES.md). Right now the dispatcher and command bodies live in the same head, which is convenient for adding commands.
- **Tokenize-and-dispatch over regex.** All 12 commands have 0–4 whitespace-separated args. Regex would be over-engineering. Each `_cmd_*` method does its own type validation, returns String for output.
- **Strict debug-build gate (Q2 confirmed).** `OS.is_debug_build()` wraps the activation. Production exports won't have the console at all. Future "creative mode" or modding system would expose state manipulation through a designed UI; until then, dev-only.
- **Split `give` from `place` (Q3 confirmed).** Buildings aren't items — they're placed directly via hotbar, not held in inventory. Forcing `give <building>` would have required inventing fake "building items." `place <building> <x> <y> [dir]` matches the actual game model.
- **`clear` requires explicit target (Q3 confirmed).** Unqualified `clear` is footgun. `clear inventory` and `clear chest <x> <y>` are unambiguous.
- **`tile <x> <y> [radius]` (per design pushback addition).** Default 0 prints single-tile detail. Radius >0 prints `(2r+1)×(2r+1)` grid of soil values with `B` for buildings, `L`/`M` for fertilized tiles, `---` for out-of-bounds. Useful for "diagnose what's happening in this region" workflows in future Session 4 wasteland or Session 5 legumes.
- **`destroy` (per design pushback addition).** Without it, test sessions accumulate leftover buildings. Standard usage: `place applicator 0 0; destroy 0 0`. No drops — clean test removal.
- **`tick_speed` clamped to [0.1, 10.0] (per design pushback addition).** Multipliers above 10× start breaking belt timing math, animations, save format invariants. Out-of-range returns: `tick_speed must be between 0.1 and 10.0 (got X). Multipliers above 10x may break tick-dependent systems.`
- **In-memory history only (Q7 confirmed).** Up/down arrow walks 50-entry history. Not persisted across launches. If console becomes daily driver tooling, persist via `user://console_history.txt`. Defer.
- **Manual smoke deferred to first real-use session.** Test coverage alone is the commit gate. Bugs in the UI layer surface organically next time the console is used during a real testing session, captured + patched as discovered. Pragmatic given this session's framing as tooling investment.

### Lessons

- **Console.gd at 657 lines vs ~300–400 estimate.** Two underestimates:
  - **UI layer underestimated.** Godot's Control + RichTextLabel + LineEdit setup is ~80 lines of anchors / theme overrides / signal wiring / color-bbcode helpers. Design pass treated this as "trivial overlay"; it isn't. Lesson: when estimating LOC for a new UI component, account for ~50–100 lines of Godot scaffolding before the actual logic.
  - **Command bodies averaged 22 lines, not 10.** Each command has 2–4 arg validations, 2–3 error-return branches, plus the actual operation. Validation discipline is non-negotiable (no crashes on typos, no panics on missing world references), so the lines are real. 12 commands × 22 lines = ~264 lines for command bodies alone. Lesson: when estimating "N commands at K lines," K should include validation overhead, not just the success path.
- **Test-coverage-as-commit-gate is reasonable for tooling.** Manual smoke deferred to first-use is a sensible trade for dev-only tools where bugs surface in low-stakes contexts. The 29/29 test pass demonstrates parser correctness + 2 representative end-to-end commands work. UI-layer bugs (panel position, scrollback rendering, history navigation) are visual-only and trivially observable — capturing-on-encounter is cheaper than testing exhaustively up front.
- **The `class_name DevConsole` race did NOT bite this session.** Importing the new class via the existing post-class-name workflow (`--headless --import` after creating the file) prevented the parse-error cascade we hit in Sessions 3 and 3.5. Pattern is now muscle memory.
- **Mid-implementation rename caught a virtual-method collision.** Originally named the LineEdit `_input` (matches the field's role); collided with Godot's `Control._input(event)` virtual method. Caught immediately on file review (before run), renamed to `_input_field`, re-grepped to verify the virtual method method name was preserved. Lesson: when naming private fields, watch for collision with framework virtual methods (`_input`, `_process`, `_ready`, `_draw`, `_unhandled_input`).

### Roadmap implications

- **Session 4 (wasteland) becomes much faster.** Setup that previously needed "deplete a 5×5 area to soil 0 and observe wasteland transition" can now be `set_soil 50 50 -1; tile 50 50` (assuming wasteland mechanic permits negative soil). Testing edge cases ("does the planter on soil 0 transition correctly when fertilized?") becomes a 4-line console session.
- **Save migration framework session unblocked.** Was deferred until "after dev console" specifically because rapid migration testing was a primary use case. Now achievable: `set_soil 50 50 30; save; edit version; load; assert state migrated correctly` becomes a quick console + manual JSON edit + relaunch loop instead of "build a full factory, save, edit, reload, manually verify."
- **TickSystem rate multiplier is reusable.** Future "speed up" UI (a slider in dev settings, or a "fast-forward" gameplay mode) can write to `TickSystem.tick_rate_multiplier` directly. The clamp lives in console.gd; if a UI surface wants different bounds, it sets directly without going through the console.

### Known follow-ups

- **Manual smoke at first real-use** (per session-end decision). When a future session needs the console, exercise the 12 commands + UI behaviors. Log any bugs as discovered and patch as needed. Captured in NOTES.md.
- **Persistent command history** (Q7 deferred). Implement via `user://console_history.txt` if console becomes daily-driver tooling.
- **Console split if file grows past ~800 lines.** Cut: `console.gd` keeps UI + LineEdit + activation; `console_commands.gd` (new) gets the parser + 12 command implementations. ~30-min refactor when triggered.
- **Save migration framework** (still queued from post-3.5). Now unblocked by this session.

---

## Soil exhaustion — Session 3.5 — **FERTILIZER APPLICATOR (AUTOMATION TIER)**

**Date:** 2026-05-07
**Tag:** `session-soil-exhaustion-3-5`
**Save:** v17 (no schema bump — applicator state is standard JSON-clean fields)

Automation tier of the fertilizer chain. Hand-apply (Session 3) shipped first to validate the mechanic; this session adds the Fertilizer Applicator on the validated foundation. Third instance of the manual-before-automation pattern (mining-manual → mining-drill, soil-3 → soil-3.5).

**Plus:** mid-PAUSE-6 fix to a latent Composter design bug (output without `prefer_dir` → backward contamination of input belts when downstream jams). Caught by the user during PAUSE-6 smoke when compost started flowing onto the wheat-supply belt. Fixed by giving composter recipes `Belt.DIR_E` prefer_dir and making the building rotatable.

### What shipped

**1 new building** (`scripts/world/fertilizer_applicator.gd` ~250 lines):
- `Buildings.Type.FERTILIZER_APPLICATOR` — 1×1 footprint, 5×5 coverage. NOT a Processor (no recipe; writes directly to `tile_fertilizer_state` via `GridWorld.try_apply_fertilizer`). Custom tick mirrors MiningDrill's structure.
- Single input slot accepts COMPOST_LOW + COMPOST_MID. No output slot — pure consumer.
- Pulls from canonical W input port (rotates with R). 1-pull-per-tick rate-limit, 16-stack input buffer (~80 sec of operation).
- Three-state machine: IDLE (no input) / SCANNING (counting toward apply) / BLOCKED (no eligible tiles in coverage).
- **BLOCKED polling** (per design pushback at design-pass): when BLOCKED, scan_progress holds at threshold (100); applicator re-checks eligibility every tick and fires immediately when a tile becomes eligible. Avoids the "Next apply" UI countdown jumping backwards.
- Visual: sage-green sprinkler body, central nozzle with 4 spray lines radiating cardinally; state tints (gray IDLE, yellow BLOCKED).

**1 new specialized panel** (`scripts/ui/fertilizer_applicator_panel.gd` ~200 lines):
- Extends BuildingPanel directly (NOT ProcessorPanel — no recipe, custom layout).
- 5×5 coverage mini-grid (46×46px cells, 2px gaps). Cell colors: dim sage (pristine) / mustard (eligible) / light-green (LOW fertilized) / dark-green (MID fertilized) / near-black (impassable). Anchor cell gets bright yellow border.
- Header: "Coverage: 5×5 (25 tiles)" + "Eligible: N (for X tier)" + "Next apply: in X.Xs" (only when SCANNING — BLOCKED suppresses the countdown to avoid panel-overflow UI weirdness).
- Single input slot centered below the grid.
- Status line + facing indicator at the bottom.

**Tier preference + most-depleted-first targeting:**
- `_select_fertilizer_from_buffer(b)` — two-pass: prefer COMPOST_MID, fall back to COMPOST_LOW. Static + pure, tested directly.
- `_pick_most_depleted_eligible_tile(b, world, tier)` — sorts by soil_health ascending, tiebreak topmost-leftmost (Vector2i compare on y then x). Filters out-of-bounds tiles (world-edge applicator placement is safe). Static + pure.

**Hotbar:** 4th slot in the Soil category, between Composter and the hand-apply slots: buildings grouped first, then consumable item-apply slots.

**Composter prefer_dir fix** (mid-PAUSE-6, separate from the applicator work):
- All 3 composter recipes (`composter_low_wheat`, `composter_low_flax`, `composter_mid_beet`) gained `Belt.DIR_E` prefer_dir on outputs. Without this, `Processor._try_push_outputs` falls through to other directions when the east belt jams — pushing compost BACKWARD onto the input belt, contaminating the wheat supply.
- `Buildings.DATA[COMPOSTER].supports_direction = true` and `Composter.make(pos, dir)` accepts a rotation. Outputs go to the rotated east edge (player can press R for different layouts). Recipe inputs stay direction-free so feeders can arrive from any side.
- Old (Session 3) composter saves still load — buildings without a `dir` field default to 0 (canonical east), preserving Session 3 placement intent.

**Tests: 27 → 28 passing.** New `test_fertilizer_applicator.gd` (4 sub-suites): apply rate (5 applies in 30 sec) + BLOCKED steady-state, tier preference (MID before LOW + fallthrough), most-depleted-first targeting (with topmost-leftmost tiebreak), world-edge placement (out-of-bounds tiles excluded from scan, no crash). Existing fertilizer-chain tests pass unchanged with the prefer_dir fix.

### Decisions

- **Custom tick (not Processor.tick).** Applicator has no recipe — it consumes input and writes per-tile state. Recipe-driven `Processor.tick` doesn't fit (no time_ticks, no out_buffer, no recipe lookup). Mirroring MiningDrill's pattern (custom `tick` with bespoke pull/apply logic) is the right shape.
- **BLOCKED polls every tick at threshold, doesn't roll back scan_progress.** Original design pulled scan_progress back to (APPLY_INTERVAL - 20) on entering BLOCKED, which would have made the UI "Next apply" countdown jump backward from 5.0s to 1.0s. User pushback at design pass: keep scan_progress at threshold, re-check eligibility per tick (O(25), trivial), fire immediately when conditions change (e.g., player just hand-applied to a different tile, freeing one for upgrade). Cleaner state machine + faster response.
- **Tier preference: MID first, then LOW.** Prevents wasted MID compost on tiles that LOW could handle. Same stacking rules as hand-apply — applicator's targeting filter (`current_tier < selected_tier`) means it only targets tiles where the available tier would actually upgrade or freshly apply.
- **Most-depleted-first with topmost-leftmost tiebreak.** Deterministic ordering matches MiningDrill's pattern. Player can't predict applicator behavior to "game" it, but tiebreak determinism means save/load preserves which tile gets fertilized next.
- **No save schema bump.** All applicator state (in_buffer, scan_progress, dir, state) is standard `Building.state` fields — already JSON-clean and serialized via existing v17 schema.
- **Composter rotatable to fix backward-push bug.** Could have just added `prefer_dir = Belt.DIR_E` and kept `supports_direction: false` — but rotatable is strictly more flexible (player can build north-pointing or south-pointing composters), and the cost is minimal (one new state field, default 0 backwards-compat). Mirrors Thresher pattern exactly.
- **Combined PAUSE 5 + PAUSE 6 in implementation order.** Originally split: PAUSE 5 (mechanics + UI) → tests → PAUSE 6 (full chain). Compressed to single PAUSE per pause point because the panel layout was new enough to warrant visual verification before tests, and the full chain just needed connecting working pieces.
- **Composter input belt contamination caught at PAUSE 6 by user, not by tests.** Fixed mid-session per "fix root-cause issues that surface during smoke" protocol — not deferred. Latent across all 12 ProcessorPanel consumers but only Composter's specific topology (input + output on the same straight-line belt run) made it visible. Other Processors (Mill, Mixer, Thresher etc.) either have prefer_dir on outputs already or have multi-side input access that masks the issue.

### Lessons

- **Custom tick saved real complexity.** Using `Processor.tick` would have required a fake recipe with time_ticks, out_buffer that gets emptied somehow, etc. The applicator has fundamentally different shape (no recipe, no output flow) and forcing it into Processor would have produced if-flag branches inside the shared tick. Mirroring Drill's standalone-tick pattern was the right call. Pattern: when a building's flow shape (in/out/timing) doesn't match Processor's, write a custom tick — don't bend Processor.
- **The "panel is too wide" UI bug appeared at PAUSE 5, fixed in 5 lines.** Original panel layout drew `BLOCKED — no eligible tiles in coverage` in the header at `hx + 240` with no width clip; the text overflowed past the panel right edge. Real fix: don't show countdown text in the header during BLOCKED — the bottom Status line already says it. Lesson: when the same state info appears in two UI surfaces, prefer the dedicated one and suppress duplicates rather than fighting the layout.
- **The composter contamination bug was found by EYE-TESTING, not unit tests.** All 27 prior tests passed; the composter test in particular ran the recipe and verified compost output, but never checked WHICH adjacent belt received the compost when downstream was jammed. Belt-routing tests would have to set up a multi-belt topology and check buffer contents per-belt — heavyweight. Eye-testing during PAUSE 6 caught it in 30 seconds. Lesson: PAUSE-time eye-testing complements unit tests — they catch different classes of bug.
- **The schema-mismatch UX gap (NOTES.md) hit during PAUSE 5** — user had a v16 save lingering after Session 3's bump to v17, world spawned empty. ~10 min lost to "is my Session 3.5 work broken?" diagnosis before checking stderr. Captured in NOTES.md with two queued fixes (5-line graceful fallthrough + full migration framework session). This entry of PROJECT_LOG also reinforces: every session that bumps SAVE_VERSION will hit this UX gap until the quick fix lands.
- **Manual-before-automation worked on its third instance.** Hand-apply (Session 3) had ~2 hours of playtest before Session 3.5 started. By the time the applicator landed, the per-tile fertilizer state was already validated — no second-guessing of the Session 3 mechanics, just plumbing automation onto a known-good foundation. Each instance has been smoother than the last. Pattern is now codified in NOTES.md and earned its keep.

### Roadmap implications

- **Soil arc almost complete:** Sessions 1+2+3+3.5 shipped. Remaining: Session 4 (wasteland) — tiles below soil 0 enter wasteland state, require fertilizer to reclaim, unclamps `max(0, ...)`. Optional Session 5 (legumes / crop rotation) — negative-soil-cost crops heal their 3×3 instead of depleting. Both can use the existing `tile_fertilizer_state` and applicator infrastructure unchanged.
- **Composter prefer_dir fix unlocks any future "linear chain" Processor placement.** Player can now confidently place a composter inline with a single belt run without worrying about backward contamination. Pattern extends to any future Processor with similar topology constraints.

### Known follow-ups

- **Schema-mismatch UX gap quick fix** (queued in NOTES.md): when load fails on schema mismatch, fall through to fresh-world generation instead of leaving an empty world. ~5 lines in `main.gd`. Hotfix slot before the next schema bump.
- **Save migration framework** (queued in NOTES.md): full session work, deferred until after the dev console session. Replaces hard-fail with chained migration steps (`migrate_v15_to_v16`, `migrate_v16_to_v17`, …).
- **Audit other Processors for backward-push risk.** Mill, Mixer, Thresher, etc. — most already have prefer_dir, but a quick recipes.gd grep confirms which don't, and whether the topology actually exposes the bug. ~15-min audit at start of next session.
- **Multi-applicator UX**: overlapping coverage works (each applicator independently scans + applies), but no visual cue that two applicators share coverage of a tile. Defer to playtest feedback.

---

## Soil exhaustion — Session 3 of multi-session arc (save v16 → v17) — **FERTILIZER CHAIN (HAND-APPLY ONLY)**

**Date:** 2026-05-06
**Tag:** `session-soil-exhaustion-3`

Third session of the soil arc adds the fertilizer chain: crops → Composter → Compost item → hand-applied to soil → boosts per-tile regen rate for a duration. Closes the soil cycle thematically — heaviest depletion crop (sugar beet) becomes the richest compost, healing what it took.

**Scope reduced after design pass.** Original design (per pre-session brief) included a Fertilizer Applicator building for automation. User cut scope at design-pass time per the "manual mechanic before automation" pattern (mirrors the manual-mining → drill arc): foundation first, automation later. Applicator deferred to Session 3.5 or merged with Session 4 (wasteland).

### What shipped

**2 new items** (`scripts/world/items.gd`):
- `COMPOST_LOW` — "Low Compost", brown, stack 100. Made from wheat or flax (2 → 1).
- `COMPOST_MID` — "Rich Compost", darker brown, stack 100. Made from sugar beet (2 → 1). HIGH tier deferred to Session 4 (wasteland) — there's no clean "waste" item in today's chain that maps thematically to high-tier compost.

**1 new building** (`scripts/world/composter.gd` + `scripts/world/buildings.gd` enum + DATA):
- `Buildings.Type.COMPOSTER` — 1×1 footprint, "small farm operation" feel. Multi-recipe like Smelter (auto-selects based on input). No fuel; biological process. Reuses `Processor.tick` via thin shim that wraps it with `_maybe_select_recipe` (second multi-recipe processor in the codebase; pattern is now established).
- Visual: wooden compost bin with central heap mound that brightens when running, plank slats for texture, progress arc when running.

**3 new recipes** (`scripts/world/recipes.gd`):
- `composter_low_wheat`: WHEAT × 2 → COMPOST_LOW × 1, 100 ticks (5s).
- `composter_low_flax`: FLAX × 2 → COMPOST_LOW × 1, 100 ticks.
- `composter_mid_beet`: SUGAR_BEET × 2 → COMPOST_MID × 1, 140 ticks (7s — premium tier slower).

**1 new ProcessorPanel consumer** (`scripts/ui/composter_panel.gd`): 5-line `extends ProcessorPanel`, no overrides. **12th ProcessorPanel consumer** (joins Mill, Oven, Proofer, Packager, Loom, Tailor, Briquetter, Sugar Press, Retter, Yeast Culture, Thresher).

**Per-tile fertilizer state** (`scripts/world/grid_world.gd`):
- New sparse dict `tile_fertilizer_state: Dictionary[Vector2i → {tier: int, remaining: float}]`.
- Helpers: `try_apply_fertilizer(pos, tier) -> bool` (with stacking rules — see Decisions), `tile_fertilizer_tier(pos)`, `tile_fertilizer_remaining(pos)`, `_fertilizer_boost_multiplier(pos)`.
- Static helpers `fertilizer_multiplier(tier)` and `fertilizer_duration(tier)` — inline 2-tier table (LOW = 2× / 30s, MID = 4× / 60s).
- New `_tick_fertilizer_decay(delta)` runs in `_process` BEFORE `_tick_soil_regen` (decay-then-regen ordering — see Decisions).
- `_tick_soil_regen` modified: regen accumulator now multiplied by `_fertilizer_boost_multiplier(pos)` per tile.

**Hand-apply via NEW hotbar kind** (`scripts/ui/hotbar.gd`):
- Third hotbar kind: `item_apply` joins `terrain` (paint overlay) and `building` (place building). Documented at the top of `hotbar.gd` with full extension protocol for future kinds (seeds, wasteland restorers, etc.).
- New "Soil" category between "Refining" and "Storage" with 3 slots: Composter (building) + Apply Low Compost + Apply Rich Compost (item_apply).
- `Hotbar.player_inventory` ref wired by main.gd at `_ready` so `item_apply` slots **dim when the player has 0 of the item** (Factorio-style "can't use this" affordance — better UX than "click → toast → click → toast" loop). Falls back to never-dim when inventory ref is null (tests / scripted scenes).

**Hand-apply trigger** (`scripts/main.gd`):
- New `_try_apply_item(pos, item_type)` dispatched from `_try_place(pos)` for `item_apply` slots.
- Uses `Input.is_action_just_pressed("place_tile")` (not `pressed`) — fertilizer is a discrete consume per click; holding LMB would otherwise drain inventory at frame rate. Terrain (drag-paint) and building (drag-place) keep their `pressed` semantics.
- On apply success: consumes 1 from player_inventory + toast. On lower-tier-rejected: toast + no consumption. On empty-inventory click: toast (the dim-on-empty hotbar slot is the upstream affordance).

**Visual + Q-inspect feedback**:
- New `FERT_TINT_LOW` / `FERT_TINT_MID` overlays in `GridWorld._draw` (light green / saturated green, 20% / 30% alpha) — applied AFTER soil tint so a damaged-but-fertilized tile blends red+green.
- `info_panel.gd` Q-inspect adds a fertilizer line under the soil line when active boost is on the tile: "Fertilizer: Low Compost (Xs remaining, 2.0x regen)" in green text (matching SOIL_REGEN_COLOR — "this is good news").

**Save schema v16 → v17**:
- New top-level field `tile_fertilizer_state`: sparse Array of `[x, y, tier_int, remaining_float]`.
- `SAVE_VERSION = 17`. v16 saves hard-fail with OS.alert per existing policy. Migration log entry added.

**Tests: 26 → 27 passing.** New `test_fertilizer_chain.gd` (5 sub-suites): composter recipe selection (multi-recipe), hand-apply state set correctly, stacking rules (refresh / upgrade / reject), boost regen rate (2× LOW + 4× MID + 1× control + decay), save round-trip preserves v17 state.

### Decisions

- **Defer Fertilizer Applicator to Session 3.5 / Session 4 (manual before automation).** Original design included an Applicator building (1×1 footprint, 5×5 coverage, consumes compost from belt input, auto-fertilizes most-depleted eligible tile in coverage). User cut at design-pass time per the manual-before-automation pattern (mirrors `session-mining-manual` → `session-mining-drill`). Validates the mechanic in playtest before committing to automation. NOTES.md captures the pattern as a project protocol.
- **2-tier compost this session, defer HIGH to Session 4.** Low = wheat/flax base; Mid = sugar beet (heaviest depletion → richest compost — thematic closure). HIGH would need a "waste/excess" input that doesn't exist in today's chain; bread-as-waste only makes sense in Session 4 when wasteland recovery becomes a separate vertical. Enum is append-only so HIGH adds without breaking saves.
- **Boost is acceleration, NOT refill.** LOW = 2× regen for 30 sec → up to 2 soil points recovered. MID = 4× regen for 60 sec → up to 8 points. Both intentionally short relative to total depletion (a wheat planter at -29 aggregate per harvest). Prevents "infinite fertilizer = infinite farming" exploit; the player still has to give the land time.
- **Stacking rules**: same tier refreshes timer; higher tier upgrades; LOWER tier on active higher REJECTS (no inventory consumption + toast). Prevents wasted LOW compost on already-MID-fertilized tiles.
- **Parallel sparse dict for `tile_fertilizer_state`, NOT extending `tile_soil_modifications`.** Different lifetimes (soil mods can persist for the whole game; fertilizer expires in 30–60s). Coupling them creates entry-erase ordering bugs. Mirrors the existing Tree-regrowth pattern (separate `resource_state_modifications` dict).
- **Decay-before-regen ordering in `_process`.** Fertilizer decay runs FIRST so a tile doesn't fire its last regen tick AFTER the boost expired (1-frame "leak"). In production this is invisible (per-frame deltas are tiny so a tile gets ~1800 boosted ticks before its 1-tick expiry). Also affects testing — the test exposes boost-rate via direct state-set with long `remaining` to isolate from decay (see `test_fertilizer_chain.gd` sub-suite 4a comments).
- **`item_apply` is a NEW third hotbar kind**, NOT a new menu or right-click-in-inventory mechanic. Matches the existing hotbar paradigm (player selects → click tile to use). Hotbar.gd's file header now documents the 3-kind extension protocol for future kinds (seeds, wasteland restorers, etc.).
- **Hotbar slot dims when inventory has 0 of the item**, matching Factorio. Cleaner affordance than "click → toast → click → toast." Implementation: `_is_slot_disabled(slot)` checks `player_inventory.total_of(item_type) <= 0`; draw pass applies `SLOT_DIM_ALPHA = 0.35` to swatch + label.
- **`item_apply` uses `just_pressed`**, not `pressed`. Discrete consume per click. Holding LMB on a fertilizer slot would otherwise drain inventory at frame rate. Terrain/building keep `pressed` semantics (drag-to-paint / drag-to-place are intended).
- **Composter is multi-recipe like Smelter, NOT single-recipe like Mill.** Recipe auto-selects from input via `_maybe_select_recipe` — pattern duplicated from Smelter (now 2 multi-recipe processors). NOTES.md flags: if a third multi-recipe processor lands, factor out `MultiRecipeProcessor.tick(b, world, input_to_recipe_map)` to avoid the third copy.

### Lessons

- **The "manual before automation" pattern earned its name.** This is the second time it's saved a session from over-scoping. Mining-manual shipped before mining-drill; soil-fertilizer hand-apply ships before applicator. Both times: foundation gets validated in playtest before automation gets built on top of it. Codified in NOTES.md as project protocol.
- **Reduced scope at the design-pass writeup, not silently in code.** When the user cut the Applicator at design pass, all references to it were stripped from the implementation order before any code was written. Reversal #6 (zoom-to-map) caught a similar over-scope at PAUSE 2 — much later, ~2 sessions of dead work. Catching at the design pass is the cheapest possible time.
- **Float precision bites tests with many small increments.** First version of the boost-regen test ran 30 iterations of `_tick_soil_regen(1.0)`; the accumulator landed at 0.99999... instead of 1.0, no soil increment fired. Fix: use single-call deltas with the full duration where possible (`_tick_soil_regen(30.0)` lands at exactly 1.0). When per-frame iteration is necessary (e.g., to drive multiple systems simultaneously), use larger-step increments (5.0 sec × 6, not 1.0 sec × 30). Production frames are tiny so this never bites at runtime — but tests amplify the precision sensitivity.
- **Class registration race bit again on first launch after adding `class_name Composter`.** Tests failed with "Identifier 'Composter' not declared" until `--headless --import` rebuilt the global script class cache. This is now the third time this race has caught a session (zoom-to-map's MapBackdrop, soil-2's PlanterPanel during refactor, and now Composter). Adding `--headless --import` to the post-class_name workflow is the right reflex; documented in PROJECT_LOG history but not yet codified as a hard protocol — could become a pre-test step in future sessions.

### Roadmap implications

- **Session 3.5 (or merged into Session 4)**: Fertilizer Applicator. 1×1 footprint, 5×5 coverage, belt-fed compost input, auto-applies to most-depleted eligible tile in coverage at rate-limited intervals. Most of the design is already worked out (see this session's pre-cut design pass for spec); implementation is straightforward once the manual mechanic is playtested.
- **Session 4 (wasteland)**: tiles below soil 0 enter wasteland state — render distinctly (cracked-earth blacker), block planter placement, require fertilizer to reclaim. THIS is when bread-as-waste makes thematic sense for HIGH-tier compost (refined goods get composted into wasteland-recovery material). Unclamps `max(0, ...)` in `deplete_tile_soil`.
- **Session 5 (legumes / crop rotation)**: legume crops with negative `soil_cost` heal their 3×3 area instead of depleting. Fertilizer chain is orthogonal — legumes are an alternative to fertilization, not a replacement. Player learns "wheat → flax → legume + fertilize the dying patches" as the sustainable per-tile pattern.

### Known follow-ups

- Stacking rule edge case: at floating-point boundary where `remaining` ≈ 0 but state hasn't been erased yet, `try_apply_fertilizer` would treat the tile as "currently fertilized" and apply stacking rules. In practice this is a 1-frame window (decay erases the state immediately). Not worth a fix unless playtest exposes a visible artifact.
- Composter visual is currently identical regardless of which recipe is running. Future polish: tint the heap mound based on output tier (lighter brown for LOW, darker for MID).
- ApplicatorPanel design (5×5 coverage grid) is already worked out for Session 3.5 — see this session's pre-cut design pass spec.

---

## Zoom-to-map — wheel-trigger of M-key modal — **30 LINES OF CODE, ~2 SESSIONS OF DEAD WORK**

**Date:** 2026-05-06
**Tag:** `session-zoom-to-map`

The shipped feature is small and clean: at the existing zoom floor (`ZOOM_MIN = 0.85`), one more wheel-down opens the existing M-key map modal. Inside the modal, wheel-up closes back to world view at the same zoom. ~30 lines in `main.gd` + a 130-line headless test (7 sub-suites).

The history behind those 30 lines is the entry's real content: **architectural reversal #6** discarded ~2 sessions of work (`MapBackdrop` separate-render node, dual textures with/without fog, dynamic resolution-independent `ZOOM_MIN`, cross-fade alpha math, click-vs-drag distinction, smooth lerp pan animation in fullscreen) after the user's playtest revealed they wanted "wheel-out triggers the existing M-key modal," not a new continuous-cross-fade rendering path.

### Architectural reversal #6 — separate-render zoom-to-map → wheel-trigger of M-key modal

**Original locked design (~2 sessions of work):**
- New `MapBackdrop` Node2D rendering the cached map texture covering the entire 16384×16384 world rect, fading in below `ZOOM_FADE_START = 0.40`, fully visible below `ZOOM_FADE_END = 0.20`.
- Cross-fade math via `_world_alpha_for_zoom(z)` and `_map_alpha_for_zoom(z)` driving `grid_world.modulate.a` and `map_backdrop.map_alpha` per frame.
- Dynamic `_zoom_min()` computed from viewport height (so map fills vertical viewport on any monitor).
- Player movement frozen at `grid_world.modulate.a < 0.5` (Factorio look-only convention; this was reversal #6.5 in the same arc).
- Click-to-pan with click-vs-drag threshold (5px), smooth lerp pan animation (PAN_LERP_RATE = 12.0) inside the M-key fullscreen.
- Test suite for cross-fade math + click-vs-drag threshold + rapid-zoom edge cases.

**What revealed it was wrong:** at PAUSE 2 manual verification, the user reported the map "fills only ~43% of the viewport." Diagnostic HUD instrumentation (`get_canvas_transform()` applied to known world corners + viewport size + window size) confirmed the math was actually correct: the map texture WAS rendering at full 16384 world-px = full vertical viewport. But ~80% of the texture was solid black (unexplored regions per `_redraw_region`'s `Color(0,0,0,1)` fill), so the visible "map" was just the explored center. Path forward would have been a second 4MB always-bright texture for `MapBackdrop` only — adding more code on top of code that wasn't the right shape.

The user's clarification: "discard all current zoom-to-map work, build the simpler 'zoom-out triggers M-key map' feature." The desired feature was a **trigger**, not a **render mode**. Fog-of-war + drag-pan + click-to-pan + everything else came for free from the existing M-key modal.

**The reversal in numbers:**
| | Separate-render approach (~2 sessions) | Wheel-trigger of M-key (this commit) |
|---|---|---|
| New nodes | `MapBackdrop` Node2D + scene wiring | none |
| New textures | 1 texture (1024² RGBA = 4MB), with planned 2nd full-bright texture (+4MB) | none |
| Cross-fade math | ~30 lines + tests | none |
| Dynamic `_zoom_min()` | ~10 lines + tests | none (existing constant `ZOOM_MIN = 0.85` reused) |
| Click-to-pan in M-fullscreen | ~50 lines (smooth lerp + click-vs-drag) | none (existing M-key behavior reused) |
| Player freeze logic | ~10 lines in `player.gd` | none (existing modal pattern reused) |
| Save schema bump | none planned but conceptually adjacent | none |
| `main.gd` zoom handler | full rewrite around alpha cross-fade | +30 lines (modal-open + at-floor branches) |
| Test code | 100+ lines on cross-fade + thresholds + edges | 130 lines on the 7 wheel decision branches |
| Total LOC delta from clean state | ~600 added | +30 in main.gd + 130 test = **160 net** |

**Cost of the reversal — caught at PAUSE 2 of the second session:**
- ~2 sessions of `MapBackdrop` work fully discarded (`git restore .` + `git clean -fd` from clean HEAD).
- Architectural lesson preserved (this entry).
- Zero salvage — the new feature shares no code with the old approach.

**Why the reversal was correct:** the user wanted to **navigate** at extreme zoom-out, not see a continuous cross-fade visualization. The M-key modal already supported all the navigation primitives (pan, click-to-pan, full fog-of-war map texture). Wheel-out was just an alternate trigger for it. The "separate-render with cross-fade" framing was an over-elaborate solution to a much simpler input-routing problem.

### What shipped (this session)

**`scripts/main.gd` — wheel-trigger logic (~30 lines net)**
- Extracted `_handle_zoom_wheel(direction: int)` from `_unhandled_input` (pure refactor preserving the previous behavior).
- Added `_compute_zoom_action(current_zoom, modal_open, direction) -> Dictionary` as a static, pure decision function. Tests call this directly without instantiating Main's full @onready scene graph.
- Three behaviors layered on top of plain zoom:
  - **A.** Modal open + wheel-up → close the modal. No zoom change.
  - **B.** Modal open + wheel-down → no-op (debounce).
  - **C.** World view + wheel-down at `ZOOM_MIN + 1e-4` floor → open the modal. Zoom unchanged.
- Threshold reuses existing `ZOOM_MIN = 0.85` — no new constant. Float-epsilon tolerance handles lerp-converged values that float just above the strict floor.

**`scripts/tests/test_zoom_trigger_map.gd` — 7 sub-suites**
1. Wheel-down decreases zoom above min, modal stays closed.
2. Wheel-down at min triggers map open, target_zoom unchanged.
3. Modal-open blocks wheel-down (no zoom change, no extra toggle).
4. Modal-open + wheel-up requests close.
5. Wheel-up after modal closed zooms in normally.
6. M-key direct toggle is independent of wheel state (verified structurally — only `modal_open` parameter couples the function to modal state).
7. **Regression: wheel-up in world view at any zoom < ZOOM_MAX zooms in normally** across 30 steps from floor; clamps at ceiling without exceeding. This is the regression test for the static-helper extraction.

**Test count: 25 → 26 passing.**

**`scripts/tests/test_runner.gd`** — registered the new test.

### Decisions

- **Reuse existing `ZOOM_MIN` constant.** No new threshold variable. The floor where zoom previously clamped is the trigger point. One source of truth.
- **Float-epsilon tolerance (`1e-4`) on the at-floor check.** Smooth-zoom lerp drifts target_zoom slightly above the strict floor in some frames; epsilon makes the trigger reliable. Test #2b verifies fired-within-epsilon.
- **Static + pure decision function (`_compute_zoom_action`).** Lets headless tests verify the full decision logic without standing up a Main instance with all its @onready scene-graph dependencies. Pattern: thin instance wrapper applies side-effects (target_zoom assignment, `map_panel.toggle()` call); pure helper makes the decisions. Tests exercise the pure helper.
- **Wheel-up at floor with modal open closes the modal but does NOT bump zoom up by one step.** Clean state-machine boundary: one wheel event = one decision. If the player wants to zoom in further, they wheel-up again after the modal closes. Considered the "close + bump zoom in same event" alternative; rejected for state-machine clarity.
- **No visual hint that wheel-out can trigger the modal.** Modal-open IS the indicator. Player learns "wheel-out at min zoom opens the map" the first time it happens. Defer any one-shot toast to PAUSE 2 follow-up if discoverability proves to be an issue.
- **No save schema bump.** Behavior change only — no persisted state added.
- **No project.godot input changes.** Wheel events already bind through `_unhandled_input`.

### Lessons

- **"Like Factorio" is a reference, not a spec.** The user said the feature should work "exactly like Factorio." That phrase let the implementer pick a mental model (continuous cross-fade rendering) that fit "exactly like Factorio" but not the user's actual need (wheel-out trigger of the existing modal). Reference-style phrasing preserves the user's escape hatch ("oh, that's not what I meant") without forcing the alignment that a behavioral spec would. **Protocol added to NOTES.md:** when the user says "like X," the next response must be specific behavioral verification — frame-by-frame description of the desired sequence — before any design pass. See NOTES.md → Protocol: unpack reference-style requirements before design pass.
- **Reversals get more expensive when reconnaissance is "verify the math" rather than "verify the user's mental model."** Multiple HUD instrumentations + canvas-transform debugging confirmed the cross-fade math was correct, while the actual issue was that the cross-fade approach was solving the wrong problem. Math verification is necessary but not sufficient — the audit step has to also ask "is this what the user wants to see?"
- **Same-day pattern: this is the second instance.** Reversal #5 (region soil → per-tile soil) was caught after ~1 hour of playtest. Reversal #6 (separate-render → wheel-trigger) was caught after ~2 sessions of build + diagnostic. Both reversals had the same root cause: building what the literal text said vs. what the user actually meant. The cost differential: #5 caught fast = 1 session of rewrite. #6 caught slower = 2 sessions of fully-discarded work.
- **Discard cleanly when the reversal is total.** No salvage was attempted on the `MapBackdrop` work because nothing in it was scope-agnostic — every line was specific to the wrong framing. `git restore . && git clean -fd` from clean HEAD `58934b7` was the right move. Salvage is appropriate when partial work is scope-agnostic (reversal #5: ~30 lines of UI scaffolding). Salvage is wrong when every line encodes the wrong abstraction (reversal #6: 100% discarded).

### Roadmap implications

None for the soil-exhaustion arc (Sessions 3-5 unaffected). Zoom-to-map is now closed; the M-key modal is the single canonical "look at the whole map" surface, with two triggers (M key + wheel-out at floor).

### Known follow-ups

- **PAUSE-2 discoverability check (low priority):** if subsequent playtest reveals players don't realize wheel-out at floor opens the map, add a one-shot toast on first ZOOM_MIN-reach: "Wheel down again to open the map." Defer until evidence demands it.

---

## Soil exhaustion — Session 2 of multi-session arc (save v15 → v16) — **REFACTOR + REGEN + VISUAL STATES**

**Date:** 2026-05-03
**Tag:** `session-soil-exhaustion-2`

Three deliverables in one commit, plus the most expensive architectural reversal in the project's history (#5 — would have been catastrophic if missed).

1. **Refactor**: region-based soil → per-tile soil with 1-tile-radius falloff (3×3 around each planter).
2. **Visual states**: per-tile rendering shows soil tints so dead zones form visibly.
3. **Per-tile regen**: fallow regeneration at 1 point per 30 sec, blocked by active planters' 3×3 areas.

Total: ~700 lines net change across grid_world.gd, planter.gd, info_panel.gd, planter_panel.gd, save_system.gd, and test_soil_exhaustion.gd. Save schema v15 → v16, hard-fail v15 (no migration).

### Architectural reversal #5 — region-based soil → per-tile

**The reversal in numbers:**
| | Region (Session 1) | Per-tile (Session 2) |
|---|---|---|
| Scope per planter | 1024 tiles (32×32) | 9 tiles (3×3) |
| Storage | sparse Dict[region → soil] | sparse Dict[tile → soil] |
| Save size at 50 planters | ~10 entries (~200B) | ~200-450 entries (~9KB) |
| Visual feedback | none planned | per-tile tints |
| Player perception | "1 planter killed an entire region" | "1 planter killed its 3×3 area" |

**Why region was wrong:** at 32×32 tiles, one planter affected an enormous area decoupled from its physical footprint. Player UX in playtest: harvested a wheat planter, looked around, "where's the effect?" Soil dropped from 100 → 95 in the abstract — invisible in any visual feedback because the region scope was too large to localize cause.

**Why per-tile is right:** 9 tiles around the planter is a *visible* footprint. Player harvests, sees the immediate 3×3 dim. Multiple planters spaced apart create non-overlapping dead patches; planters in a line create overlap intensification. The geometry of the factory becomes visible in the soil state. **Cause-effect proximity restored.**

### Cost of the reversal — caught fast vs. caught late

**Caught at: ~1 hour after Session 1 ship.** Real-time wall-clock from `git log`. The user playtested the Session 1 region-based mechanic, immediately saw the disconnect, called the architectural reversal during the next session's design pass.

**Cost now:**
- ~30 lines of UI scaffolding from a partial Session 2 attempt salvaged (Planter.is_active, info_panel colorization, planter_panel status messaging shapes — all scope-agnostic).
- ~1 session of rewrite work: storage refactor, regen rewrite, visual rendering, test rewrite.
- Save schema bump v15 → v16 with hard-fail (no migration; mechanic 1 day old, no real save state to preserve).

**Cost if caught later (estimated):**
- Session 3 (fertilizer chain) would have built on region-scoped Compost / Spreader buildings. Compost spreader would distribute fertilizer per region. Per-tile concept would force redesign of whole fertilizer chain.
- Session 4 (wasteland) would have implemented region-wide wasteland. Per-tile wasteland tiles is an entirely different mechanic.
- Session 5 (legumes) would have inherited region-scoped healing. Per-tile healing is fundamentally different geometry.

3-5 sessions of compound rework, plus undoing each session's tests + UI + save schema additions. **Estimated 10× cost differential** vs catching at Session 2 (~1 session vs 3-5).

### What shipped

**Per-tile storage (`tile_soil_modifications`)**
- `Dictionary[Vector2i (tile pos) → int (0..100)]`. Sparse — pristine tiles absent. `tile_soil_health(pos)` defaults to 100 via `.get(pos, TILE_SOIL_FULL)`.
- `tile_regen_progress: Dictionary[Vector2i → float]` — in-memory only (not persisted). Lossy on save/load: up to 30 sec of pending regen per tile.

**Falloff formula (`_neighbor_falloff_cost`)** — per locked design Q5:
```
neighbor_cost = max(1, ceil(center_cost * 0.6))
```
Verified for all 3 crops:
- Wheat (5): center -5, 8 neighbors -3 each = -29 aggregate per harvest
- Sugar Beet (8): center -8, 8 neighbors -5 each = -48 aggregate
- Flax (3): center -3, 8 neighbors -2 each = -19 aggregate

Wheat aggregate (-29) is ~6× the old single-region depletion (-5). New mechanic is genuinely punishing per-action.

**`deplete_planter_area(anchor, center_cost)`** — applies center + 8-neighbor falloff in one call. Replaces the old `deplete_region_soil(region, amount)`. Each tile clamped at 0 individually.

**Per-tile regen (`_tick_soil_regen`)** — per-frame iteration of `tile_soil_modifications`:
1. Single pass marks all tiles in active planters' 3×3 areas (Chebyshev distance ≤ 1 from each active planter).
2. Second pass iterates modified tiles: if active, clear partial regen progress; else accumulate `delta / SECONDS_PER_SOIL_POINT`. When progress ≥ 1.0, increment soil by floor(progress); on full recovery (soil ≥ 100), erase from both dicts (sparse return to pristine).

**Active-planter detection: O(planters × 9) per frame.** At 100 planters = 900 dict inserts/frame; sub-millisecond.

**Two new enums** (orthogonal):
- `SoilLevel`: PRISTINE / HEALTHY / DAMAGED / DYING / DEAD — pure function of `soil_health` value.
- `SoilActivity`: NONE / ACTIVE_FARMING / REGENERATING — function of nearby planter state.

`tile_soil_level(pos)` and `tile_soil_activity(pos)` helpers; used by visual rendering and Q-inspect.

**Visual rendering (`_soil_tint_for_tile`)**
- Tint pass added to `_draw()` between resource layer and grid lines.
- Per-tile lookup of `tile_soil_modifications`; iterate sparse dict, draw tint rect per visible tile.
- **Restricted scope** (per design Q5):
  - Plain grass (unmapped tile, OR `base=GRASS, overlay=NONE`): tint shows.
  - SOIL_TILLED tiles: tint shows.
  - Stone / Path / Water tiles: NO tint (these are infrastructure / paved / water).
- Tint colors: DAMAGED = yellow-brown, DYING = brown, DEAD = dark cracked-earth. PRISTINE + HEALTHY = no tint.

**Q-inspect updates (info_panel)**
- `_draw_soil_footer` rewritten to show per-tile soil + level label + activity suffix.
- Format: `Soil: 73 / 100 (damaged) — regen` with color cue per level.

**PlanterPanel 3×3 mini-grid**
- New widget showing planter's 3×3 area with each cell color-coded by SoilLevel and labeled with soil value. Center cell highlighted with yellow border.
- Aggregate average + center tile level + activity status displayed alongside.
- Single-planter oscillation (per Q1 user note) visible naturally: center cell flickers DEAD ↔ DYING every ~30 sec when fully depleted; the mini-grid IS the diagnostic feedback.

**`_top_area_height`** override in PlanterPanel bumped to 300px to fit the 3×3 mini-grid.

**Save format v15 → v16**
- Replace `region_soil_modifications` with `tile_soil_modifications`.
- Hard-fail v15 saves per existing schema-bump policy.
- No migration: region values would synthesize artificially uniform tiles (1024 tiles all at the same value) — gameplay feel wrong, save bloat for fake data.

**Test rewrite (`test_soil_exhaustion`)**
- Session 1 region-scoped tests fully replaced with 17 sub-suites for per-tile model:
  - `tile_soil_health` defaults / sparse storage
  - `deplete_tile_soil` clamp
  - `_neighbor_falloff_cost` formula for all 3 crops + edge cases (cost=0, cost=1)
  - `deplete_planter_area` 9-tile area depletion
  - Per-crop integration: WHEAT extract drops 9 tiles correctly
  - Multi-planter overlap: tiles in both 3×3 areas drop double
  - Distance-isolation: tile far from planter unaffected
  - **3×3 boundary exactness** (Q2 user pushback): distance-3 tile regenerates while nearby planter active
  - Soil-zero gate per-tile (center tile drives gate)
  - In-progress crop finishes despite zero center soil
  - Already-dead tile edge case
  - Per-tile regen with 30-sec delta
  - Active planter blocks regen on its 3×3; outside-3×3 unaffected
  - Save round-trip preserves tile_soil_modifications
  - **Partial-progress-cleared-on-active-farming** (Session 2 carry)
  - **Single-planter oscillation in dead 3×3 area** (Q1 user pushback) — verified growth advances after regen ticks
  - SoilLevel thresholds at all 5 boundaries (100, 99, 70, 69, 30, 29, 1, 0)
- 25 → 25 tests passing (1 test rewritten, no net add — rewrite was extensive).

### Decisions

- **Per-tile over region scope.** Reversal of Session 1's design. Argued in detail above.
- **3×3 area, not 5×5 or larger.** 1-tile radius was chosen because:
  - Visible at typical zoom levels (3 tiles is recognizable as "the planter and its surroundings").
  - Localizes the dead zone visibly to the player.
  - Multi-planter spacing strategy emerges naturally (place planters 2+ tiles apart for non-overlap, tighter for overlap intensification).
- **Falloff formula `max(1, ceil(0.6 * center_cost))`.** The 0.6 factor was the user's locked decision. Neighbors take ~60% of the center hit — significantly more than half, ensures fast dead-zone formation. The `max(1, …)` guards against future tiny-cost crops touching neighbors at 0 (which would create visual edge cases where the area is "depleted" but neighbors are pristine).
- **Hard-fail v15 saves** rather than migrate. Mechanic is 1 day old; no real save state to preserve. Migration would synthesize fake uniform per-tile values that don't match player expectation.
- **Visual tints scoped to grass + SOIL_TILLED only.** Avoids weird visuals on stone/path/water (which players read as "infrastructure" — soil mechanic doesn't apply). Soil VALUES still tracked on infrastructure tiles (faithful to the model); only visualization is filtered.
- **In-memory `tile_regen_progress` (not persisted).** Save is integer-only; partial fractional progress lost on reload. Up to 30 sec lost per regenerating tile — negligible. Keeps save format simple.
- **Two orthogonal enums (SoilLevel + SoilActivity)** instead of one combined enum. Soil level is pure function of value; activity is function of nearby planter state. Combining would have been a 5×3 = 15-state enum where most combos are meaningless.
- **Two-pass active detection in `_tick_soil_regen`.** Single pass over planters builds active-tile set; single pass over modified tiles checks set membership. Cleaner than per-tile O(planters) lookups; same total work.
- **Single-planter oscillation feedback via mini-grid flicker.** Per Q1 user pushback: don't add explicit "oscillating" status text. The mini-grid's flicker (DEAD ↔ DYING every 30 sec) IS the diagnostic feedback. Player sees their farming intensity exceeds soil capacity without needing a textbook diagnosis.
- **3×3 boundary check via Chebyshev distance** (`abs(dx) ≤ 1 and abs(dy) ≤ 1`). Exact, simple, no fuzzy region-match.

### Lessons

- **Playtest reveals scope errors that pure design doesn't.** This was reversal #5 — the most expensive one we'd have committed to without playtest. Region-based soil sounded strategic in design pass; felt disconnected in play. The 30 minutes of playtest after Session 1 caught what hours of design pass missed.
- **Reversal cost scales with how many dependent sessions land before the reversal.** Catching at Session 2 = 1 session rewrite. Catching at Session 5 = 3-5 sessions of compound rework + save migrations + test cascades. **The cost differential is roughly 10×** in this case.
- **Codified protocol** (in NOTES.md): "**Playtest gates between foundational sessions.** After a foundational session ships, play 30+ minutes before approving the design of dependent sessions." This is a new development-process invariant for the project.
- **Salvage > rewrite when partial work exists.** ~30 lines of UI scaffolding from a partial Session 2 attempt (Planter.is_active, info_panel colorization, status messaging skeleton) were preserved when their domain was scope-agnostic. Region-scoped logic was rewritten; level-scoped UI was kept. Two-pass cleanup left the codebase clean.
- **The visual tint pass mattered enormously for "feel."** Without tints, per-tile mechanic would have been just numbers in Q-inspect — invisible during gameplay. With tints, the dead zones literally appear on the map. **The architectural decision and its visual feedback are inseparable** — neither would feel right alone.

### Roadmap implications

This is **Session 2 of the multi-session arc** (per-tile foundation now stable). Sessions 3-5 inherit per-tile semantics:

- **Session 3 — Fertilizer chain** (per-tile). Compost building (consumes straw/scraps → compost item). Fertilizer Spreader (consumes compost, accelerates regen on a per-tile area — likely 5×5 or larger to differentiate from planter's 3×3). Save schema bump if Spreader needs duration/intensity state.
- **Session 4 — Wasteland mechanics** (per-tile). Tiles below soil 0 enter wasteland state — render distinctly (cracked-earth blacker), block planter placement, require fertilizer to reclaim. Unclamps `max(0, ...)` in `deplete_tile_soil`.
- **Session 5 — Legumes / crop rotation** (per-tile). Legume crops with negative `soil_cost` heal their 3×3 area instead of depleting. Player learns "wheat → flax → legume" rotation as the sustainable per-tile pattern.

All three sessions are FUNDAMENTALLY DIFFERENT under per-tile vs region scope. The reversal at Session 2 was the right time to catch this.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Mining category at 2/9** — smelter session carry.
- **Click-handling duplication** between inventory_grid + BuildingPanel — refined trigger criteria in NOTES.md.
- **Right-click half-stack interactions** — flagged at session-building-ui-1 as building-UI v2 polish.
- **SmelterPanel + DrillPanel migration to ProcessorPanel-style** — flagged session-building-ui-4 as deferred indefinitely.
- **Tile-level soil visualization** — DELIVERED this session; no longer a follow-up.
- **"Q on grass shows 100/100 everywhere" noise** — still deferred to polish.
- **Optional Session 5 (legumes / crop rotation)** captured in NOTES.md as part of the soil arc roadmap.

---

## Soil exhaustion — Session 1 of multi-session stewardship-tension arc (save v14 → v15)

**Date:** 2026-05-03
**Tag:** `session-soil-exhaustion-1`

First slice of the soil exhaustion mechanic — region-based soil_health that depletes when crops harvest. Foundation for fallow regen (Session 2), fertilizer chain (Session 3), and wasteland mechanics (Session 4). Recovery is intentionally NOT in scope this session; soil can only deplete.

The mechanic introduces real factory-strategy consequences: a wheat farm that runs unchecked drains its region's soil to zero, and the planters quietly stop accepting new growth cycles. Existing crops finish gracefully (player keeps the in-flight harvest), but to keep producing the player must move planters to fresh regions — until enough sessions ship to give them recovery options.

### What shipped

**Region soil_health storage** (`GridWorld.region_soil_modifications: Dictionary[Vector2i → int]`)
- Sparse: only depleted regions appear. Default `SOIL_HEALTH_FULL = 100` is implicit (absent key = pristine).
- Mirrors the proven `resource_state_modifications` pattern. Adds a constant + a Dictionary; minimal new state.
- Two helpers: `region_soil_health(region)` reads with default 100; `deplete_region_soil(region, amount)` decrements clamped at 0 (negative-soil for wasteland deferred to Session 4).

**Per-crop soil_cost** in `Planter.CROP_DATA` (renamed from `CROP_GROWTH_TICKS`)
- Co-located dict: each crop entry has `growth_ticks` AND `soil_cost`. Can't drift apart.
- Initial values: WHEAT 5 (baseline), SUGAR_BEET 8 (heavy feeder), FLAX 3 (light feeder).
- New helper `Planter.soil_cost_for(crop_type)`. `max_growth_for` updated to read from the Dict-of-Dicts shape.

**Depletion-on-extract**: `Planter.try_extract(b, world)` — signature change adds `world` param. When extraction succeeds, region soil drops by `soil_cost_for(crop_type)`. Region resolved from the planter's anchor (NOT the consumer — soil is paid at the grow site).
- Both call sites updated: `Harvester.tick` passes `world`, `PlanterPanel._take_from_slot` passes `world`.

**Soil-zero gate** in `Planter.tick(b, world)` — signature change adds `world` param.
- When `growth == 0` AND `region_soil_health <= 0`: tick returns early (don't start a new cycle in dead soil).
- When `0 < growth < max_growth`: keeps ticking regardless of soil (in-progress crops finish gracefully).
- When ripe (`output > 0`): paused as before.
- Achieves the locked Q5 graceful behavior — player gets in-flight crops, then planter idles.

**Save format v14 → v15**
- New top-level field `region_soil_modifications: Array of [rx, ry, soil_health]`.
- Sparse: pristine regions absent. On load, `.get()` with default 100 keeps absent regions pristine.
- Old v14 saves hard-fail per existing schema-bump policy (`OS.alert` with delete instructions).
- Migration log comment added to save_system.gd header.

**Q-inspect — universal info access**
- New `TargetKind.TILE` for Q on empty grass. Shows region coordinates + soil_health.
- BUILDING and RESOURCE target kinds get a soil footer line via shared `_draw_soil_footer` helper.
- Panel always shows useful per-region info regardless of what's at the cursor (per Q8 design: "player scouting requires universal info access").
- main.gd `_try_inspect` falls through to `info_panel.set_tile_target` for empty grass instead of `clear_target`.

**PlanterPanel — soil status line + state-aware messaging** (per Q9 design)
- "Region soil: 73 / 100" line above main status.
- Three messaging cases when soil <= 0:
  - growth == 0: "Region soil DEPLETED — no new crops" (red)
  - growth > 0 (in progress): "Growing N% (soil depleted; this cycle finishes)" (red)
  - output > 0 (ripe): "Ripe — extract; soil depleted, no new crop" (red)

**Tests: 25/25 passing** (was 24; added 1)
- **NEW** `test_soil_exhaustion` — 9 sub-suites:
  1. `region_soil_health` defaults to 100 for absent regions.
  2. `deplete_region_soil` accumulates across calls; clamps at 0; multi-region isolation (depleting (1,1) leaves (2,2) at 100).
  3. Per-crop `soil_cost_for` returns 5 / 8 / 3 for WHEAT / SUGAR_BEET / FLAX.
  4. Depletion-on-extract: `try_extract(p, world)` decrements region soil; empty extract is no-op.
  5. **Multi-region isolation**: harvest in region (0,0) drops only (0,0); region (1,1) untouched after extract from a separate planter at (40, 40).
  6. **Soil-zero gate**: planter at growth==0 in dead region stays at growth==0 across multiple ticks.
  7. **In-progress finishes**: planter at growth==300 in dead region keeps ticking, completes (output=1).
  8. **Save round-trip**: depleted regions persist; pristine regions absent from save (sparse); load restores defaults via `.get(region, 100)`.
  9. **Edge case — already-dead region**: planter placed in zero-soil region stays at growth=0 from tick 1, no grace period (matches "soil-zero gate" general rule).

### Decisions

- **Region-based, not tile-based, soil.** Per locked design Q1. Each 32×32 region has ONE shared soil_health. Tile-level would have meant 256× more state (every tile its own soil), painful to visualize, and forces the player to micro-manage. Region scope creates strategic decisions ("don't over-farm this region") without overwhelming bookkeeping.
- **Sparse storage** (`region_soil_modifications`). Mirror of `resource_state_modifications`. Default 100 implicit (absent = pristine). Avoids 256-entry pristine dict that grows for no reason.
- **Q3 pushback: Planter.CROP_DATA, NOT Recipes.DATA.** Crops aren't recipes — `Planter.tick` reads its own crop dict; planters don't go through the Processor pipeline. Adding soil_cost to Recipes.DATA would have created a "crop" recipe shape that no other code uses. Co-locating in Planter's existing dict is cleaner.
- **Depletion-on-extract, not on growth-completion.** Per locked design Q5(a). Cause-effect is clean: player got the crop, soil paid the cost. If we depleted on completion (Q5(b)), a ripe-but-unharvested crop would have already paid the soil cost — but the player hasn't benefited yet. Extract-time aligns the bookkeeping with the visible benefit.
- **Soil-zero gate at `growth == 0` AND fresh-cycle start.** In-progress crops keep ticking (per Q7 graceful). The gate only blocks NEW growth from starting. This avoids the ugly UX of crops disappearing mid-growth because soil hit zero between their start and finish.
- **Soil-zero clamps at 0 this session.** Future Session 4 unclamps for negative-value wasteland mechanics. The clamp is intentional — without it, over-depletion would silently track magnitude, but no current code reads beyond zero.
- **Universal info access via Q on any tile** (locked decision Q8(a)). Q always shows useful info — pristine regions display "100/100" as a meaningful baseline rather than "no info." Defer to polish if "Q on grass shows 100/100 everywhere" becomes noise in playtest.
- **Save v15 hard-fails v14.** No migration code (consistent with existing schema-bump policy at v13/v14). Player must delete the save and start fresh.

### Lessons

- **Pre-implementation reconnaissance prevented two design-pass errors.**
  1. The user's premise that "planters use Recipes.DATA" was wrong; recipes weren't there. Audit caught it; design pushed back with `Planter.CROP_DATA` as the right home. (Same protocol-driven reversal as session-building-ui-3 and session-building-ui-4.)
  2. The user's premise about info_panel showing soil "for any tile" needed clarification: implemented as a TILE target kind for empty grass + soil footer for building/resource kinds. Without the audit, would have either (a) hidden soil info on grass tiles (poor UX) or (b) added it only to existing kinds (incomplete coverage).
- **Defaults via `.get()` make the sparse storage trivially forward-compat.** Old v14 saves can't load (hard-fail) but the additive shape means a hypothetical future migration could read v14 + treat all regions as pristine. The `region_soil_health(r)` accessor reads `modifications.get(r, 100)` — caller code never sees the difference between "absent" and "explicitly 100." Internal sparse storage, external uniform default. **Pattern: sparse-with-default is the right shape for player-modified state with implicit baselines.**
- **The signature change cascade was small.** Adding `world` to `Planter.tick(b)` and `Planter.try_extract(b)` touched 4 call sites total: Buildings.tick_one, Harvester.tick, PlanterPanel._take_from_slot, plus the function itself. Defensive `world == null` guards keep tests that don't have a world reference working. **Lesson: when a primitive needs context it didn't previously, count the callers BEFORE the design pass — small caller count → low cost; large caller count → maybe the context belongs elsewhere.**
- **Test ordering caught the right invariants in the right order.** Sub-suite 5 (multi-region isolation) and sub-suite 9 (already-dead-region edge case) both came from user pushback at design pass. Both were genuine risks: a global-state implementation bug would have escaped sub-suite 4 (single-region depletion works) but would have been caught by sub-suite 5; a misplaced `growth == 0` check would have failed sub-suite 9. **Lesson: edge-case tests catch what happy-path tests miss; spec them explicitly when reviewing the design pass.**

### Roadmap implications

This is **Session 1 of a multi-session stewardship-tension arc**. The remaining sessions add the recovery half:

- **Session 2 — Fallow regeneration.** Regions slowly heal soil_health when no harvests occur for N ticks (e.g., +1 per minute when idle). Player can leave a depleted region fallow and return later. Adds fallow-state UI + decay timer per region. Save bump v15 → v16 if region tracks "last_harvest_tick" explicitly.
- **Session 3 — Fertilizer chain.** New buildings: Compost (consumes organic waste — straw, chaff, kitchen scraps), Fertilizer Spreader (consumes compost, accelerates regen on its region). Connects to bread chain (straw → compost) for cross-chain dependencies.
- **Session 4 — Wasteland mechanics.** Soil_health goes negative for severely depleted regions. Wasteland tiles render visually distinct, block planter placement, require fertilizer to reclaim. Unclamps the deplete clamp shipped this session.
- **Optional Session 5 — Crop rotation.** Legumes (with negative soil_cost — they HEAL the soil) introduced. Player learns "rotate wheat → flax → legume" as a sustainable pattern.

This session sets up all of those: the storage primitive, the depletion trigger, the visualization layer. Each future session adds a recovery mechanism on top of the same foundation.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Mining category at 2/9** — smelter session carry.
- **Click-handling duplication** between inventory_grid + BuildingPanel — refined trigger criteria in NOTES.md.
- **Right-click half-stack interactions** — flagged at session-building-ui-1 as building-UI v2 polish.
- **SmelterPanel + DrillPanel migration to ProcessorPanel-style** — flagged session-building-ui-4 as deferred indefinitely.
- **Tile-level soil visualization** — deferred to Session 2 alongside recovery (so visual states have both deplete + heal meaning).
- **"Q on grass shows 100/100 everywhere" noise** — deferred to polish if playtest confirms it's annoying.

---

## Building Interaction UI — Session 4 of multi-session arc (save v14, no bump) — **ARC COMPLETE**

**Date:** 2026-05-03
**Tag:** `session-building-ui-4`

Final session of the 4-session UI arc. Three new specialized panels: HarvesterPanel (3×3 coverage display + multi-output buffer), PlanterPanel (handles all 3 variants — Wheat/Sugar Beet/Flax — via crop_type read), ThresherPanel (vanilla `extends ProcessorPanel`). After this session, **every interactive building in the game has a specialized UI**; only passive infrastructure (Pipe/Pump/Belt) remains UI-less.

### What shipped

**`scripts/ui/harvester_panel.gd`** (~165 lines) — extends BuildingPanel.
- 3×3 coverage display: harvester's own tile (■) + 8 King-move neighbors color-coded by planter status (R=ripe gold, G=growing leafy-green, _=empty/non-planter dim gray).
- Output buffer rendered as 6-slot horizontal row (`output_multi` kind, same shape as drill's output buffer). Multi-type bag: harvester scoops crops from any planter type in coverage.
- Coverage state read on-the-fly per frame from `world.has_building_at` + `Planter.is_ripe` (per Q2 design — no caching needed at this scale).
- Status row: scan timer + buffer fill, plus hint about belt/chest auto-drain.
- Overrides `_top_area_height()` to 380px (coverage + output row + status).

**`scripts/ui/planter_panel.gd`** (~140 lines) — extends BuildingPanel.
- **One panel handles all 3 planter variants** — they share `Buildings.Type.PLANTER` with `crop_type` set at placement via hotbar `extra`. PlanterPanel reads `Planter.crop_of(b)` per frame to title and color the output.
- Growth bar (240×18px) fills toward `max_growth_for(crop_type)`: 600 ticks for wheat, 800 for sugar beet, 500 for flax.
- Status text: "Growing N%" (leafy-green) or "Ripe — extract to start next cycle" (ripe gold).
- Centered output slot with the configured crop's color swatch.
- **Custom drag-out for int-typed output**: Planter's `output` is `int` (0 or 1), not `Array of [type, count]`. PlanterPanel overrides `_take_from_slot` to call `Planter.try_extract` (resets growth=0 on output→0 — consistent with the harvester-driven extraction primitive). Drop into output rejected via base-class read-only logic (no override needed).
- Overrides `_draw_slots` so the slot renders the crop_type-derived item even though the underlying state is just an int.

**`scripts/ui/thresher_panel.gd`** (~5 lines) — pure `extends ProcessorPanel`.
- 1 input (WHEAT) + 2 outputs (GRAIN, STRAW). ProcessorPanel's default lay-out stacks the 2 outputs vertically on the right column. **No overrides needed.**
- Validates ProcessorPanel pattern at **11 consumers** post-Session-4.

**Buildings.DATA slot_layouts added (3 buildings):**
- HARVESTER: `[output_multi buffer, multi_count: 6]`
- PLANTER: `[output, max_stack: 1, state_field: output (int!)]`
- THRESHER: `[input WHEAT, output GRAIN, output STRAW]`

**Buildings.gd schema docs**: added comprehensive comment for `slot_layout_for` clarifying the slot descriptor shape, kind enum, and the `accepts:[]` semantics:
- For `input`/`fuel` kinds: accepts is **VALIDATED** (drag-drop rejects non-listed types).
- For `output`/`output_multi` kinds: accepts is **INFORMATIONAL** (output kinds are read-only by design; accepts is for display).
- Special-purpose fields per kind documented (`multi_count`, `fluid_type`).

**E-key on harvester now opens panel, not drain.** Harvester gained `has_interaction_ui == true`; `_try_e_key_interact` finds it as an interactable first, so E opens HarvesterPanel. Player drains by drag-out from the output buffer. Old "Drain with E" hint replaced with "Drag items from buffer to inventory below, or place a chest/belt adjacent for auto-drain."

**Test canary updated**: `test_building_ui` "no UI" assertion swapped from HARVESTER (now has UI) to BELT (passive infrastructure, will never have a UI).

**Tests: 24/24 passing** (was 23; added 1)
- **NEW** `test_building_ui_4` — 5 sub-suites:
  1. slot_layout shapes for harvester/planter/thresher correct (kinds, accepts, fields).
  2. ProcessorPanel reuse milestone hits 11 consumers via static file scan.
  3. **Multi-session arc COMPLETE check**: iterates every `Buildings.DATA` key — passive types (Pipe/Pump/Belt) have NO UI; all others have `has_interaction_ui == true`.
  4. PlanterPanel int-typed output: take from ripe planter pulls crop to cursor and resets growth via `Planter.try_extract`. Empty planter → no-op.
  5. HarvesterPanel coverage scan returns expected enum states (RIPE for ripe planter, GROWING for default planter, EMPTY for chest/no-building).

### Multi-session arc COMPLETE — final reuse milestones

| Pattern | Consumers post-arc | Cost saved vs naive |
|---|---|---|
| **BuildingPanel base** | 14 specialized panels | one-shared modal lifecycle, drag-drop, validation |
| **ProcessorPanel intermediate** | 11 (Mill/Oven/Proofer/Packager/Loom/Tailor/Briquetter/SugarPress/Retter/YeastCulture/Thresher) | ~700 lines saved across sessions 2-4 |
| **`draw_fluid_indicator` shared helper** | 3 (Mixer/Retter/YeastCulture) | unified visual; ~50 lines saved |
| **`output_multi` shared kind** | 2 (Drill/Harvester) | shared sub-slot rendering + click logic |
| **`fluid_indicator` shared kind** | 3 (Mixer/Retter/YeastCulture) | unified read-only fluid widget |

**Final post-arc panel sizes:**
- 14 specialized panel files
- 11 of those are 5–10 lines each (pure `extends ProcessorPanel` or `extends BuildingPanel`)
- 3 specialized: HarvesterPanel (~165), PlanterPanel (~140), ChestPanel (~170), MixerPanel (~155), SmelterPanel (~180), DrillPanel (~245)
- ProcessorPanel itself: ~230 lines (intermediate base for 11 buildings)
- BuildingPanel base: ~400 lines (modal lifecycle, drag-drop, validation, `draw_fluid_indicator`, player inventory render)

**Architectural payoff arc:**
- Session 1 paid ~400 lines for the BuildingPanel framework. 2 specialized consumers.
- Session 2 paid ~200 lines for ProcessorPanel. Reuse jumped to 4 consumers.
- Session 3 paid ~30 lines for fluid_indicator extension. Reuse jumped to 10 consumers + 3 fluid consumers.
- Session 4 paid ~5 lines for ThresherPanel and ~300 lines for harvester+planter specialization. Reuse hit 11 consumers; arc complete.

The "expensive code paid in early sessions, cheap subclass declarations in later sessions" pattern played out exactly as planned. Late-session subclass files are 5-10 lines each. The architectural credit balance keeps cashing out.

### Decisions

- **ExtractionPanel intermediate class deferred (architectural reversal #3 in the project).** User-locked decision at session start was "ExtractionPanel base class for harvester + 3 planters." Pre-implementation audit found:
  - Harvester is 1×1 with a 3×3 *coverage* display reading 8 neighbors.
  - Planters are 1×1 with NO coverage area; just grow on themselves.
  - Their layouts share <30% — coverage is harvester-only; growth fraction is planter-only; harvester has multi-bag output, planters have int-typed single output.
  - Forcing them into one base class would mean "if-has-coverage / if-has-growth / if-multi-output" branches — at that point ExtractionPanel is BuildingPanel with flags, no real abstraction value.
- **PlanterPanel single-class for all 3 variants.** Wheat/Sugar Beet/Flax planters share `Buildings.Type.PLANTER`; only the `crop_type` state field differs. One PlanterPanel reads crop_type per-open. Three variants but one panel file. Cleaner than 3 near-identical subclasses (which the user's brief had implicitly assumed).
- **Coverage state read on-the-fly per frame, not cached.** Harvester scans 8 cells at most; per-frame cost is negligible. Caching would introduce sync complexity (when does the cache invalidate?) for no measurable gain.
- **Planter's int-typed output handled via PlanterPanel override**, not by changing Planter state shape. Migration risk avoided. The override is small and localized.
- **Thresher's 2 outputs use existing ProcessorPanel default**, not a special "multi-output" Processor variant. ProcessorPanel already stacks outputs vertically when `output_count > 1`; thresher's 2-stack (grain above, straw below) inherits this for free.

### Lessons

- **Pre-implementation audits catch faulty abstraction assumptions.** This is the **3rd architectural reversal in the project** based on reconnaissance findings:
  1. **Mining tier — deposit-overlay rule reversal** (`session-mining-manual`): "overlay obscures deposit, RMB-clear reveals" was reversed to "overlay placement BLOCKED on deposits" after the UX trap became obvious in playtest.
  2. **Fluid_indicator extraction before extending ProcessorPanel** (`session-building-ui-3`): user pushback on the design pass added the 3a→3b→3c sequencing to extract MixerPanel's fluid renderer to a shared helper BEFORE ProcessorPanel grew its own fluid logic.
  3. **ExtractionPanel deferred** (`session-building-ui-4`): user-locked architectural decision overturned by reconnaissance audit revealing harvester ↔ planter shape divergence.
- **Codified as protocol** in NOTES.md: "**Locked architectural decisions can be reversed if pre-implementation reconnaissance reveals the assumption was wrong.**" The cost of reversing during design pass is ~10 minutes of writeup; the cost of shipping a bad abstraction and removing it later is 10× that. Always run the audit step the user explicitly requested.
- **The "specialized panel" line count grew with feature complexity, not arbitrarily.** HarvesterPanel (~165 lines) is 3× the size of trivial ProcessorPanel subclasses because it has a unique coverage widget. PlanterPanel (~140 lines) is 2× because of its int-typed-output override and crop_type-driven display. The ratio of "novel UX requirement → custom code" is what drove sizes; pure declaration cases stayed at 5-10 lines.
- **Thresher catch-up was a 5-line fix** after sessions 2-3 missed it. Carrying "Thresher should have shipped with food chain" as an explicit follow-up note (NOTES.md) prevented it from being silently forgotten. Lesson: **when a session scope-out is intentional, document it as a known follow-up immediately, not "later in the doc pass."**
- **Multi-session arc complete on schedule with no schema bumps.** 4 sessions, 14 specialized panels, 0 save format changes, 24 cumulative tests at the end (vs 21 at session 1 start). The data-driven `slot_layout` registry + `BuildingPanel`/`ProcessorPanel` hierarchy was the right architecture from session 1; later sessions were pure additions, not reshapes. Lesson: **when the early-session architectural decisions are right, late sessions are easy.**

### Roadmap implications — multi-session UI arc COMPLETE

This arc is closed. Every interactive building in the game has a specialized UI panel. Future UI work falls into three categories:

- **Polish** (defer to playtest feedback): right-click half-stack, drag-drop visuals (true mouse drag instead of click-pick / click-place), animations, panel transitions.
- **New buildings** (Sessions C/D/E/F per main spec): future processors automatically inherit ProcessorPanel; specialized buildings get a panel file. Adding a UI for a new processor = ~10 lines panel file + 1 slot_layout entry.
- **Major rework** (deferred indefinitely): SmelterPanel and DrillPanel still have their own standalone implementations from Session 1 — they predate ProcessorPanel. Could be migrated in a future polish session if the divergence becomes painful. Not currently painful.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Mining category at 2/9** — smelter session carry. Future kilns/lumber camp/electric drills join here.
- **Click-handling duplication** between inventory_grid + BuildingPanel — refined trigger criteria in NOTES.md (still 2 implementations after 4 sessions).
- **Right-click half-stack interactions** — flagged at session-building-ui-1 as building-UI v2 polish.
- **SmelterPanel + DrillPanel migration to ProcessorPanel + ExtractionPanel-style refactor** — flagged this session as deferred indefinitely.

---

## Building Interaction UI — Session 3 of multi-session arc (save v14, no bump)

**Date:** 2026-05-03
**Tag:** `session-building-ui-3`

Six new specialized building UIs: Loom, Tailor, Briquetter, Sugar Press (cloth chain + fuel processing), and Retter, Yeast Culture (solid + fluid input). All 6 extend ProcessorPanel directly with **no overrides** — each panel file is ~10 lines. ProcessorPanel grew ~30 lines to support `fluid_indicator` slot kind, validating the architectural pattern at **10 total consumers** post-Session-3.

### What shipped

**`scripts/ui/loom_panel.gd` / `tailor_panel.gd` / `briquetter_panel.gd` / `sugar_press_panel.gd`** — each ~5 lines. Pure `extends ProcessorPanel` with no overrides.

**`scripts/ui/retter_panel.gd` / `yeast_culture_panel.gd`** — same shape (1 solid input + 1 fluid_indicator + 1 output). Each ~5 lines, pure `extends ProcessorPanel`.

**ProcessorPanel extended for `fluid_indicator` slot kind (~30 lines)**
- `_building_slot_rects()`: skips fluid_indicator entries (render-only, not click-targetable).
- `_draw_building_specific()`: renders the fluid widget below the input column (same vertical band where the fuel slot would go for fuel-using processors).
- `_status_y()`: includes fluid widget's bottom in the deepest-column calc so status text doesn't overlap.
- All rendering delegates to the shared `BuildingPanel.draw_fluid_indicator` (extracted in this session).

**Shared `BuildingPanel.draw_fluid_indicator` helper** (~25 lines)
- Extracted from MixerPanel (~30 lines deleted there).
- Renders filled-or-hollow blue dot + name label based on `world.fluid_available_for_building(b, fluid_type)`.
- Used by MixerPanel AND ProcessorPanel-fluid (Retter, Yeast Culture). **Single source of truth** for "how a fluid input looks."
- Three consumers post-Session-3.

**`Buildings.DATA` slot_layouts added (6 buildings):**
- BRIQUETTER: `[input STRAW, output FUEL_BRIQUETTE]`
- SUGAR_PRESS: `[input SUGAR_BEET, output SUGAR]`
- LOOM: `[input FIBER, output CLOTH]`
- TAILOR: `[input CLOTH, output BAG]`
- RETTER: `[input FLAX, fluid_indicator WATER, output FIBER]`
- YEAST_CULTURE: `[input SUGAR, fluid_indicator WATER, output YEAST]`

**Hot fix from Session 2 carry:** `test_building_ui` "no UI canary" updated from BRIQUETTER (now has UI) to HARVESTER (Session 4 target).

**Tests: 23/23 passing** (was 22; added 1)
- **NEW** `test_building_ui_3` — 4 sub-suites:
  1. slot_layout shapes for all 6 new buildings (correct kinds, accepts, fluid_type).
  2. ProcessorPanel-fluid drag-drop: Retter accepts FLAX into input; rejects wrong-type with toast; fluid_indicator NOT in `_building_slot_rects` (render-only).
  3. **ProcessorPanel reuse milestone**: static file scan confirms 10 panels are pure `extends ProcessorPanel` with no overrides (Mill, Oven, Proofer, Packager, Loom, Tailor, Briquetter, Sugar Press, Retter, Yeast Culture).
  4. `BuildingPanel.draw_fluid_indicator` method exists (extraction sanity check).

### ProcessorPanel reuse milestone — architectural-investment-pays-off log

| Session | ProcessorPanel consumers | Notes |
|---|---|---|
| Session 2 (~ship) | 4 (Mill, Oven, Proofer, Packager) | Initial pattern — paid ~200 lines for ProcessorPanel base |
| Session 3 (~ship) | **10** (+ Loom, Tailor, Briquetter, Sugar Press, Retter, Yeast Culture) | ~30 line extension for fluid_indicator support |

**Session 3 additions: 6 new buildings × ~5 lines each = ~30 lines for panel files.** Total session 3 panel cost ≈ 30 lines (panel files) + 30 lines (ProcessorPanel fluid_indicator) = **~60 lines** for 6 new building UIs.

**Naive plan would have been:** 4 standard processors × ~10 lines + 2 specialized fluid processors × ~150 lines (separate Retter/YeastCulture panels with hand-written fluid rendering) = **~340 lines.**

**Net savings: ~280 lines** by extending ProcessorPanel for fluid_indicator instead of specializing the 2 buildings separately. The 30-line ProcessorPanel extension paid for itself **immediately at 2 consumers** and will keep paying as future fluid processors land (e.g., a hypothetical brewery, distillery, kiln-with-water).

This is the second cumulative architectural-investment lesson in the project (first: Burner module reusability validated at session-smelter when smelter integrated in ~13 lines vs ~100+ for drill-specific fuel).

**Pattern:** when a sub-feature (here: fluid input) appears in 2+ buildings of the same family, extending the family base class is dramatically cheaper than per-building specialization. Even at N=2.

### Decisions

- **Click-handling extraction deferred** (per user-approved refined criteria). Audit: only 2 implementations exist (`inventory_grid.gd::_handle_left_click_player` and `building_panel.gd::_handle_player_slot_click`). ChestPanel overrides `_gui_input` but only for hit-test routing (calls inherited `_handle_player_slot_click` for player slots). No third copy. Refined trigger criteria captured in NOTES.md:
  - Third *implementation* of the click logic appears (not a subclass).
  - New behavior added that requires both call sites to be updated identically.
  - Player-slot click logic genuinely diverges between modals.
- **Fluid indicator helper extracted to `BuildingPanel.draw_fluid_indicator` BEFORE extending ProcessorPanel.** Prevents two independent render paths from drifting over time. MixerPanel + ProcessorPanel-fluid (Retter, Yeast Culture) all call the same helper. Three consumers immediately validate the extraction.
- **All 6 new buildings extend ProcessorPanel directly, no overrides.** Validates the pattern at 10 total consumers. Each panel file is essentially a class-doc comment + `extends ProcessorPanel`. Adding more processor-shape buildings in the future = same boilerplate.
- **Retter and Yeast Culture didn't get specialized panels.** First draft of design pass had them at "MixerPanel-style specialization, ~150 lines each." Reconsidered: their shape (1 solid + 1 fluid + 1 output) is simpler than Mixer's (2 side-by-side solid + 1 fluid). Extending ProcessorPanel for fluid_indicator support handles both Retter and YeastCulture trivially. Mixer's 2-input-side-by-side layout is what makes it diverge enough to justify specialization.
- **Independent panels (no cloth-chain branding).** Considered visual cohesion via tinted borders for cloth-chain panels. Rejected: explicit chain branding is overdesign at this stage. Recipe display name in the panel title area communicates "you're looking at the cloth-chain step."
- **`fluid_indicator` is not click-targetable.** It's render-only. ProcessorPanel.`_building_slot_rects()` skips it; clicks on the widget area do nothing. Player can't drag water into the building because there's no WATER item. Connection state is purely informational.

### Lessons

- **The audit verification step caught nothing — but was worth doing.** User pushback at design-pass time asked for a grep of subclass click-handler overrides before deferring extraction. Result: only one override (ChestPanel's hit-test routing) and it inherits the actual click logic. So the deferral was correct. But verifying took ~30 seconds and locked in confidence. Lesson: pre-commit audits are cheap; do them when there's any doubt.
- **3a → 3b → 3c sequencing was right.** Extracted `draw_fluid_indicator` to BuildingPanel base FIRST, refactored MixerPanel to use it (mechanical, no behavior change — verified 22/22 tests still passed), THEN extended ProcessorPanel to also call it. Atomic, reviewable steps. Compare to extracting + extending in one shot: a regression in either step would be harder to localize. **Pattern: when extracting then extending, always intermediate-test after extract before extending.**
- **Pure subclass files are gold.** The 6 new panels are 5 lines each — basically class-name + `extends ProcessorPanel` + a doc comment. Total panel-file LOC for this session: ~30. Compare to Session 2's MixerPanel at ~155 lines, or Session 1's SmelterPanel at ~180 lines. **The expensive code (drag-drop, layout, validation) was paid in Session 1; subclasses are pure declaration.** The architectural "credit balance" from earlier sessions just keeps cashing out.
- **No layout bugs surfaced at PAUSE 1.** Unlike Sessions 1 and 2 (each had at least one overlap fix at PAUSE 1), Session 3's panels rendered correctly first try. This is because:
  - 4 of 6 panels reused the exact ProcessorPanel layout (no new positioning code).
  - 2 of 6 (Retter, Yeast Culture) reused the fuel-slot vertical position via the `_status_y()` helper that already accounted for variable column heights.
  - The shared `draw_fluid_indicator` produced visually identical output to MixerPanel.
  - Each architectural reuse takes one less custom-layout opportunity for bugs.

### Roadmap implications

This is **Session 3 of a 4-session arc**. Session 4 adds extraction-tier UIs for the remaining buildings.

- **Session 4 — Extraction.** Harvester, Planters. Architectural concern flagged in Sessions 1-2: planter has no input/output buffer in the conventional sense (crops grow on the tile itself); harvester's "input" is the tile under it. Both diverge from Processor-shaped slot_layout. Either extends BuildingPanel directly (specialized layouts) OR extends a new `ExtractionPanel` intermediate class if the 2 share enough. **Decide at start of Session 4** based on actual layout sketches.

### Out-of-scope this session (NOT shipped, captured for later)

- **Thresher** has no UI yet. It's a basic Processor (wheat → grain + straw). Should logically have a UI alongside Mill/Mixer/Oven. **Got skipped in Sessions 2 and 3.** Capture as Session 4 add-on candidate (~15 minutes — single slot_layout entry + 5-line panel file).
- **Pump, Pipe, Belt** — passive infrastructure; no internal state worth a UI panel. Read-only Q-inspect via info_panel is sufficient.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Mining category at 2/9** — smelter session carry.
- **Click-handling duplication** between inventory_grid + BuildingPanel — refined trigger criteria captured in NOTES.md.
- **Right-click half-stack interactions** — flagged at session-building-ui-1 as building-UI v2 polish.
- **Thresher UI** — flagged this session.

---

## Building Interaction UI — Session 2 of multi-session arc (save v14, no bump)

**Date:** 2026-05-03
**Tag:** `session-building-ui-2`

Six new specialized building UIs: chest, mill, oven, proofer, packager, mixer. Built on the BuildingPanel base from Session 1. Introduces:
1. **`ProcessorPanel`** intermediate class — Mill, Proofer, Packager, Oven each ~10 lines (just `extends`).
2. **`ChestPanel`** replacing the old `inventory_grid` paired-view (~150 lines deleted from inventory_grid.gd).
3. **Unified E-key**: opens building UIs (any building with `has_interaction_ui`); falls back to drain for legacy harvester.
4. **New slot kinds**: `chest_bag` (defers to subclass render), `fluid_indicator` (read-only display).

### What shipped

**`scripts/ui/processor_panel.gd`** (~200 lines) — intermediate base class extending BuildingPanel.
- Default `_building_slot_rects()` lays out inputs as a left-column (stacked vertically), outputs as a right-column, fuel slot below inputs.
- Default `_draw_building_specific()` paints progress bar between input and output, slot labels, status text + recipe display.
- Each row is `SLOT_LARGE + LABEL_HEIGHT + SLOT_VGAP = 94px` so labels never overlap the next stacked slot.
- `_status_y()` helper computes status-text Y as the deepest column's bottom + 8px (avoids overlap when oven has 2 stacked inputs).
- `_status_subline()` virtual method for buildings that want a sub-line (Smelter would override; deferred).

**`scripts/ui/mill_panel.gd` + `proofer_panel.gd` + `packager_panel.gd` + `oven_panel.gd`** (each ~10 lines)
- Pure `extends ProcessorPanel`. Slot layout in `Buildings.DATA[type]` drives rendering. No overrides needed.
- Oven inherits the 2-input vertical stack naturally via ProcessorPanel's iteration over `inputs` array — both slot 1 (Risen Dough) and slot 2 (Fuel Briquette) lay out below each other on the left column.

**`scripts/ui/mixer_panel.gd`** (~155 lines) — extends BuildingPanel directly (not ProcessorPanel).
- Two solid input slots side-by-side (flour + yeast) — diverges from ProcessorPanel's stacked-vertical default.
- **Fluid indicator widget**: read-only blue dot (filled = connected, hollow = no pipe network). Reads `world.fluid_available_for_building(b, fluid_type)` per frame. Player can't drag water — water is pipe-fed infrastructure, not a carryable item.
- Output slot on the right.

**`scripts/ui/chest_panel.gd`** (~170 lines) — extends BuildingPanel.
- Doesn't use slot_layout-driven generic render (overrides `_building_slot_rects()` to return empty). Renders its own bag grid via `SlotWidget.chest_bag_to_slot_views`.
- 6-row × 4-col grid, 24 slots (matches old inventory_grid paired-view dimensions).
- Click semantics: empty cursor + content slot → pick to cursor; cursor + slot → drop to bag (capacity-checked); cursor + occupied slot → swap via remove-then-add (chest is bulk; no per-slot ordering).
- Capacity header in top-right: "Capacity: N / 2400".
- **Custom hit-test override** (`_hit_test_chest`): combines player inventory slots + chest grid slots into one routing layer.
- Overrides `_top_area_height()` to ~380px — wider than default 280px to fit 6 rows of chest slots without overlapping the player inventory below.

**`Buildings.DATA` slot_layouts added (6 buildings):**
- CHEST: `[{kind: chest_bag, max_stack: 2400, state_field: bag}]`
- MILL: `[input GRAIN, output FLOUR]`
- OVEN: `[input RISEN_DOUGH, input FUEL_BRIQUETTE, output BREAD]` — both inputs share `in_buffer` (multi-type bag)
- PROOFER: `[input DOUGH, output RISEN_DOUGH]`
- PACKAGER: `[input BREAD, output LOAF_PACK]`
- MIXER: `[input FLOUR, input YEAST, fluid_indicator WATER, output DOUGH]`

**`SlotWidget.chest_bag_to_slot_views(bag)`** moved from `inventory_grid.gd`. Pure adapter logic; same callers, new home. Used by ChestPanel (and any future bulk-bag widget).

**`inventory_grid.gd` refactored** — chest paired-view code removed (~150 lines deleted).
- `_chest_building` field, `GRID_CHEST` constant, `open_chest_paired_view`, `_chest_slot_views`, `_chest_slot_capacity`, `_handle_left_click_chest`, `_handle_shift_click`, `_is_paired`, `_row_count_chest`, paired-view branches in `_draw_panel` / `_grid_origin_of` / `_slot_under` — all gone.
- File shrunk from 543 → 217 lines.
- Now does ONE thing: render the player inventory. Single-responsibility.

**E-key unification (`main.gd::_try_interact`)**
- Old: chest → paired-view, harvester → drain, others → no-op.
- New: any adjacent building with `has_interaction_ui` → open its panel via `_try_open_building_ui`; else any drainable → drain (legacy harvester); else silent no-op.
- Adjacency scan: 4-direction including own tile (Manhattan ≤ 1 from player_tile).
- E ignores hotbar state (works whether holding an item or not). Click-to-open requires NEUTRAL cursor.

**Multi-tile hover-rect resolution** (Session 1 carry-over) confirmed working with all new building types — clicking any cell of a 2×2 oven/proofer/packager/mixer highlights the full footprint.

**Tests: 22/22 passing** (was 21; added 1)
- **NEW** `test_building_ui_2` — 4 sub-suites:
  1. slot_layout shape correctness for chest (chest_bag kind), mill (GRAIN→FLOUR), oven (2 inputs both kind=input, distinct accepts, both state_field=in_buffer), mixer (4 entries including fluid_indicator), proofer/packager (standard 2-entry).
  2. ChestPanel drag-drop: pick from bag → cursor; drop into bag → capacity-checked; over-capacity drop rejected with toast.
  3. Multi-input oven: drop RISEN_DOUGH into dough slot → in_buffer has dough; drop FUEL_BRIQUETTE into briquette slot → in_buffer also has briquette (multi-type bag); wrong-type rejected per slot's accepts list.
  4. E-key adjacent-interactable scan: 4 cardinal directions + own tile all find an adjacent interactable building; Manhattan 2 doesn't.
- **UPDATED** `test_building_ui` — assertion swapped from MILL (now has UI) to BRIQUETTER (still no UI; ships in Session 3).
- **UPDATED** `test_chest_paired_view` — call site updated from `InventoryGridScript.chest_bag_to_slot_views` to `SlotWidget.chest_bag_to_slot_views`. Test logic unchanged; the adapter is exactly the same code at a new home.

### Decisions

- **(a) ProcessorPanel intermediate class.** Mill/Proofer/Packager/Oven all share input → progress → output flow with optional fuel slot. Extracting the layout into a base class makes each subclass ~10 lines. Decision against (b) composition: subclass-per-building is explicit ownership; composition would mean a 500-line `building_panel.gd` with all building-specific render code mingled in one file.
- **Oven NOT converted to Burner.** Investigated: oven uses fuel-as-recipe-input (FUEL_BRIQUETTE in `inputs_solid` from S edge). Converting to Burner would mean: (1) recipe contract change (remove from `inputs_solid`, add fuel_buffer state), (2) save migration (existing saves have briquettes in `in_buffer`), (3) loss of recipe-layer fuel visibility. Net negative. Oven stays as a 2-input processor; second input is "FUEL_BRIQUETTE only" with the same buffer as the first input. The fact that one input is conceptually fuel is documented by the recipe itself.
- **Mixer fluid: read-only display, not drag-droppable.** Water is fluid (Fluids.Type.WATER) flowing via pipes; no WATER item in the game. Adding an item parallel to the fluid concept would be bad shape. The fluid indicator just shows "is the pipe network alive."
- **Chest UI: bulk-storage grid, not slot-discrete.** Chest is conceptually one big bag of any items. Single `chest_bag` slot kind — BuildingPanel's generic render skips it; ChestPanel handles its own grid. New kind documents the intent (chest is "different" from input/output processors).
- **E-key unified with click-to-open.** Both routes go through `_try_open_building_ui` with adjacency check. E is faster (no need to clear hotbar first); click is more visual (point at exactly which building you mean). Two redundant entry points, accepted. E falls back to drain for legacy harvester (until Session 4 gives it a UI).
- **`_top_area_height()` virtual method.** ChestPanel's bag grid (6 rows × 52px = 312px) doesn't fit in BuildingPanel's default 280px top area. Adding `_top_area_height()` as a subclass-overridable hook lets each panel size itself appropriately. Future panels (Session 3 cloth-chain processors) can inherit the default; ChestPanel and any other tall-content panel override.
- **`SlotWidget.chest_bag_to_slot_views` moved, not deleted.** Pure adapter logic; ChestPanel still needs it. Moving to SlotWidget centralizes "bag → display views" rendering helpers. Test_chest_paired_view continues to verify the SAME adapter.
- **`row_h = 94px`, not `72px`.** First draft used `top_y + i * (SLOT_LARGE + 8)` for stacked slots — labels (at +14 offset) overlapped the next slot's top edge. Bumped to `SLOT_LARGE + LABEL_HEIGHT + SLOT_VGAP = 94px` so each row reserves space for slot + label + gap. Caught at PAUSE 1.
- **`_status_y()` computes from deepest column.** Originally hardcoded as `top_y + SLOT_LARGE + 50`. Failed on oven (2-input column extends 188px, status at 114px → status overlaps second slot). Fix: compute as `max(input_bottom, output_bottom, fuel_bottom) + 8`. Caught at PAUSE 1; surfaced in user screenshot.

### Lessons

- **PAUSE 1 caught two real layout bugs.** The chest-overlap and the oven-status-overlap were both invisible until visual smoke. The user's screenshots surfaced both. Session 2's two-pause structure (first PAUSE = "infrastructure works", second PAUSE = "full chain") meant we caught these at the cheap stage. Lesson: when adding many panels at once, don't skip the per-stage smoke.
- **Refactoring inventory_grid was cheaper than expected.** Estimated ~150-200 lines deleted; actually 326 lines deleted (543 → 217). Removing all chest paired-view logic was mechanical once we had ChestPanel as the replacement. Lesson: when a feature has a clean replacement, don't preserve the old code "for compat" — delete it. The replacement's tests cover the same surface.
- **Oven's "fuel as second input slot" is the right answer.** The slot_layout shape supports two `kind: "input"` slots with distinct accepts lists, both writing to the same in_buffer. Drag-drop validates per-slot (briquette goes only into the briquette slot; wrong-type toast). The recipe still treats fuel as a normal input. No new "fuel_input" kind needed; existing input kind suffices. **Pattern: the right primitive is often "two slots that look different but share storage."**
- **`extends ProcessorPanel` files are 10-line gold.** Mill, Proofer, Packager, Oven are basically copy-paste boilerplate. Total per-building cost: 10 lines + 1 .uid + 1 scene-node entry. The expensive code (drag-drop, validation, layout) was paid once in ProcessorPanel; subclasses are pure declaration. **Pattern works when the layout is genuinely shared.**
- **Mixer NOT extending ProcessorPanel was the right call.** Initially considered. But: 2 inputs side-by-side, fluid indicator, no fuel slot. Three layout differences vs ProcessorPanel's defaults; extending would require overriding 3 of ProcessorPanel's 4 layout decisions. At that point, just extend BuildingPanel directly. Lesson: the "barely fits the inheritance hierarchy" sub-class is a smell; flatten and extend the base instead.

### Roadmap implications

This is **Session 2 of a 4-session arc**. Sessions 3 and 4 add UIs for the remaining buildings.

- **Session 3 — Cloth chain + remaining processors.** Retter, Loom, Tailor, Briquetter, Sugar Press, Yeast Culture. ~6 panel subclasses. Most extend ProcessorPanel directly; Retter has fluid input (water from pipe) like Mixer, will likely extend BuildingPanel and reuse the fluid_indicator pattern. **Click-handling-duplication smell** flagged in NOTES.md revisits here at 4+ consumers.
- **Session 4 — Extraction.** Harvester, Planters. Architectural concern: planter has no input/output buffer in the conventional sense (crops grow on the tile). UI shape may diverge enough to warrant a non-Processor-shaped slot_layout (or none at all).

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Mining category at 2/9** — smelter session carry.
- **Click-handling duplication between inventory_grid + BuildingPanel** — flagged at session-building-ui-1; revisit at Session 3 (4+ consumers).
- **Specialized building UIs for remaining 8 buildings** — Sessions 3-4.

---

## Building Interaction UI — Session 1 of multi-session arc (save v14, no bump)

**Date:** 2026-05-03
**Tag:** `session-building-ui-1`

The first slice of click-to-open building modals: Esc clears the hotbar selection, click on a building (when adjacent) opens its specialized UI panel, drag-drop between player inventory and building slots. Two specialized UIs ship: smelter and drill. The architectural foundation (slot_layout registry, BuildingPanel base class, shared CursorStack across modals) is designed to scale to all 16 buildings; future sessions add UIs for chest/food chain (Session 2), cloth chain (Session 3), and extraction (Session 4).

### What shipped

**Cursor state machine — three modes derived from existing state:**
- `BUILDING_SELECTED`: hotbar has a selection AND no modal open. Held-LMB places. Existing behavior preserved.
- `NEUTRAL`: Esc-cleared hotbar (no selection). LMB on building → opens its UI; LMB on empty tile → silent no-op.
- `MODAL_OPEN`: any modal (inventory_grid, map_panel, building_panel, smelter_panel, drill_panel) up. Movement gated.

**Esc priority chain (in `main.gd`):**
1. inventory_grid open → close it
2. building panel open → close it
3. map panel open → close it
4. info panel has target → clear
5. hotbar has selection → clear (enter NEUTRAL with toast)
6. else → no-op

**`scripts/ui/cursor_stack.gd`** — shared cursor object (~70 lines)
- `pick(t, c)`, `clear()`, `has_item()`, `return_to_inventory(inv)`.
- `to_dict()` / `from_dict()` for serialization through `player_progression["cursor"]` (additive field, no save schema bump).
- One instance owned by main.gd, passed by reference to inventory_grid + every BuildingPanel subclass. Player picks up wood in inventory, closes it, opens smelter, drops into fuel slot — single object tracks the held stack.
- Cursor persists across modal close (was: auto-return on close; that pattern created friction for cross-modal drag).

**`scripts/ui/slot_widget.gd`** — extracted slot rendering (~80 lines)
- `draw_slot(canvas, font, rect, item_type, count, hovered, kind_border_tint)` — single source of truth for slot visuals.
- `draw_cursor_stack(canvas, font, mouse_pos, cursor)` — floating swatch + count.
- `border_for_kind(kind)` returns kind-tinted borders: input (cool blue), output (green), fuel (orange).
- Used by inventory_grid AND every building panel. Visual identity uniform across all modals.

**`Buildings.slot_layout_for(t)` registry**
- New `slot_layout` field on `Buildings.DATA[type]` — Array of slot descriptors.
- Slot shape: `{id, kind, accepts, max_stack, state_field}`.
  - `kind`: `"input"`, `"output"`, `"fuel"`, `"output_multi"` (for drill's per-ore-type sub-stacks).
  - `accepts`: list of valid `Items.Type` values for drag-in validation.
  - `state_field`: which `b.state` field this slot reads/writes (lets the rendering layer be data-driven instead of per-building hardcoded).
- Smelter: 3 slots (input/output/fuel). Drill: 2 slots (output_multi with 5 sub-slots, fuel).
- `Buildings.has_interaction_ui(t)` flag — true when slot_layout is non-empty. Used by main.gd's click-to-open dispatch to fall back to "(no UI yet)" toast for buildings without a registered layout.

**`scripts/ui/building_panel.gd`** — base class for all building modals (~340 lines)
- Modal lifecycle: `open(b, w)`, `close()`, `is_open()`, `MOUSE_FILTER_STOP` blocks world clicks.
- Player inventory grid rendered at the bottom of every panel (slot_widget reuse).
- Drag-drop with kind-validation:
  - `_drop_into_slot(slot_def, sub_idx)` — routes to `_drop_into_input` / `_drop_into_fuel` / rejects output.
  - Wrong-type drop → toast `"This slot accepts: <list>"`.
  - Output drop → toast `"Output slot is read-only"`.
  - Fuel drop converts items to units atomically: 1 wood = 1 unit, 1 coal = 4, 1 briquette = 8. Won't split items (drops 5 coal but only 3 fit → 3 deposited, 2 stay on cursor).
  - **Lossy fuel take-back** (per Q7 user pushback): clicking fuel slot with empty cursor returns `WOOD ×N` where N = current `fuel_buffer` units. Player who loaded coal accepts efficiency loss on retrieval. Simpler than tracking loaded items, no UX trap from auto-conversion accidents.
- `output_multi` sub-slot resolution: each rendered sub-slot maps to `output_buffer[sub_idx]`; click takes that entry; remaining entries shift up via `Array.remove_at`.
- Subclass override hooks: `_draw_building_specific(area, font)` and `_building_slot_rects()`.

**`scripts/ui/smelter_panel.gd`** — specialized smelter UI (~180 lines)
- Layout: input slot (large 64×64) ━━ progress bar with X/40 ticks + arrow ━▶ output slot (large 64×64). Fuel slot below. Status text + currently-smelting line.
- Progress bar fills orange when SMELTING, gray when IDLE. Status text color-coded per state (Smelting/NO FUEL/Output blocked/Idle).
- Slot labels show actual recipe item names (e.g., "Iron Ore" / "Iron Ingot") when a recipe is selected.

**`scripts/ui/drill_panel.gd`** — specialized drill UI (~210 lines)
- Layout: 2×2 coverage panel (top-left, ore-tinted cells with name + richness) + currently-mining + active-deposits list (top-right). Output row of 5 sub-slots. Fuel slot below. Status row.
- Coverage cells show per-tile ore type and remaining richness in real time.
- Active deposits sorted by richness descending (matches drill's `_pick_best_deposit` order). Top entry is the one currently being mined.

**Multi-tile hover-rect resolution**
- When in NEUTRAL mode and hovering any cell of an existing building's footprint, the hover indicator now highlights the full footprint at the building's anchor (instead of the 1×1 cursor cell).
- Implemented in `grid_world._draw`: `if occupied.has(hover_tile): rect_anchor = occupied[hover_tile]; fp_size = footprint of building at that anchor`.

**Adjacency requirement (per Q4 user pushback)**
- Click-to-open requires Manhattan ≤ 1 from any cell of the building's footprint. Consistent with E-drain, manual mining, manual chopping. Click on remote building → toast `"Move closer to interact with <name>."`.
- `main.gd::_is_adjacent_to_building(b, player_tile)` static helper.

**Cursor save/load** (per Q4 user pushback)
- Cursor serialized as `player_progression["cursor"] = {item_type, count}`. Additive field; old saves without it leave cursor empty on load.
- `_capture_cursor_in_progression()` runs before save; `_apply_loaded_progression()` restores after load.

**Tests: 21/21 passing** (was 20; added 1)
- **NEW** `test_building_ui` — 7 sub-suites:
  1. CursorStack pure ops (pick, clear, has_item, return_to_inventory, to_dict/from_dict round-trip, malformed-dict guard).
  2. `Buildings.slot_layout_for` returns expected shape for SMELTER/MINING_DRILL; empty for MILL.
  3. Hotbar `has_selection` / `clear_selection` / `current_kind() == ""` sentinel.
  4. Click resolution via `grid_world.occupied` for multi-tile (all 4 cells of 2×2 smelter resolve to anchor (0,0)).
  5. Adjacency check (Manhattan ≤ 1 from any footprint cell, including diagonals NOT counting as adjacent for 1-tile-distance rule).
  6. BuildingPanel drag-drop semantics: drop into input (accepted), drop wrong-type (rejected), drop into output (rejected), drop into fuel (converted to units), lossy take from fuel (1 unit → 1 wood), output_multi sub-slot take (entries shift up).
  7. Save/load round-trip preserves cursor through `player_progression["cursor"]`. Backward-compat: old save without cursor key → cursor stays empty.

**Tangential fix:** `Recipes.get_recipe("")` now silently returns `{}` instead of warning. Empty-string is the smelter's "no recipe selected yet" sentinel; warning was log-spam.

### Decisions

- **(a) Inheritance over (b) composition for the BuildingPanel framework.** Each specialized UI gets its own file (smelter_panel.gd, drill_panel.gd), inheriting modal lifecycle + drag-drop from BuildingPanel. Subclasses override `_draw_building_specific(area, font)` and `_building_slot_rects()`. Per the user's "specialized layouts per building" decision (Q3), inheritance naturally expresses the "shared chassis + per-building cabin" pattern. Composition was rejected because all-building-render-in-one-file would grow to 1500+ lines by Session 4.
- **Slot layout as data, not code.** Rendering, drag-drop, validation, and capacity checks all read from `Buildings.DATA[type].slot_layout`. Adding a new building UI = (1) add slot_layout entry, (2) write a *_panel.gd subclass with custom layout. Renaming `b.state.in_buffer` to `b.state.inputs` would be a one-line DATA edit, not a per-panel rewrite.
- **CursorStack shared across modals.** Picked over per-modal cursor + auto-return-on-close because cross-modal drag is a real player flow (open chest, take item, close, walk to smelter, drop in). Auto-return created a UX trap. Cursor persistence + serialization is ~70 lines; auto-return logic was ~30 lines that didn't compose with multi-modal flows.
- **Save cursor instead of force-return-on-save.** Per Q4 user pushback. Force-return creates "can't save" UX trap when inventory is full. Serializing the cursor is ~5 lines, no schema bump (additive field), matches expected save behavior. If load happens with an inventory-full + cursor-held save, the cursor is still held on load — player can drop wherever.
- **Lossy fuel take-back.** Per Q7+Q8 user pushback. The cursor-persists + fuel-one-way combination would create accidental-loss UX traps (player picks up wood, accidentally clicks fuel slot, wood auto-converts, can't retrieve). Allowing take-back as `1 unit → 1 wood` accepts efficiency loss for coal-loaders but eliminates the trap. Simpler than tracking loaded items per-slot; no confirm dialogs.
- **Adjacency required.** Per Q4 user pushback. The game has a physically-present player avatar; consistency with E-drain, manual mining, and manual chopping matters more than minor layout-iteration friction. Factorio's no-adjacency cursor model assumes a spectator-cursor; this game doesn't.
- **Specialized panels live in `scripts/ui/`, not `scripts/ui/panels/`.** Single namespace. Other UI modules (info_panel, map_panel, inventory_panel) already live there; consistent location.
- **Output_multi sub-slot index is the array index, not a stable slot ID.** Drill's `output_buffer = [[IRON,5],[COPPER,3]]` renders as sub-slot 0 (Iron) + sub-slot 1 (Copper). Clicking sub-slot 0 takes Iron and shifts Copper up to slot 0. The visual reorders mid-session. This matches chest paired view's behavior (entries reorder after takes); player learns the pattern once. Stable IDs would require per-ore-type slot mapping in state, which is more state to persist.
- **NEUTRAL mode hotbar visual: dim header brackets, no slot border.** Subtle but discoverable. The toast on Esc-clear ("Hotbar cleared — click a building to interact, or press 1-9 to re-select.") is the discovery affordance for first-time encounter.
- **Click-handling duplicated between inventory_grid and BuildingPanel** (per user-approved option 1). Captured in NOTES.md as smell to revisit at Session 3 (4+ consumers exist).

### Lessons

- **The hover-rect issue surfaced exactly at PAUSE 1.** Visual verification caught what the design pass missed: 1×1 hover rect doesn't communicate "this whole 2×2 smelter is what I'd click on." Fix was 8 lines in `grid_world._draw` (use `occupied[hover_tile]` to find the building's anchor + footprint). Surfaced before specialized UIs landed = trivial to fix; would have been obscured by panel layout work if we'd skipped the pause.
- **`current_kind() == ""` sentinel as the NEUTRAL signal.** Using empty-string as the "no selection" sentinel let main.gd's existing match-statement (`match hotbar.current_kind(): "terrain": ...`) fall through naturally. No new branches in `_try_place`; the place_tile path simply does nothing in NEUTRAL mode. The only new branch was the click-to-open at the call site. **Pattern: reuse sentinel values to avoid match-statement explosions.**
- **Silent failures in `Recipes.get_recipe("")` were log-spam.** Smelter-with-empty-recipe-id is a normal state, not an error. The warning only fired this session because smelter is the first building that legitimately has a transient empty recipe. Adding `if id == "": return {}` early-out at the top of get_recipe was 2 lines, removed all spurious warnings.
- **Modal gating chains add up.** `if inventory_grid.is_open() or map_panel.is_open() or _any_building_panel_open(): return` — the chain grows linearly with each modal type. At 5+ modals, an `is_any_modal_open()` helper would be cleaner. Captured implicitly via `_any_building_panel_open()` already extracted; if the inventory_grid + map_panel checks accumulate further, they'll join the helper.
- **Auto-return-on-close was the right call to remove.** Pre-session, `inventory_grid._close()` had ~30 lines of "stash cursor in first-empty-slot" logic. Removing it (making cursor persist) was simpler AND made cross-modal drag possible. Lesson: when a feature was added because of a constraint that no longer exists, remove the feature, don't preserve it for "compatibility."
- **`@onready` references to scene nodes that don't exist yet** required creating stub `*_panel.gd` files at scene-wire time. The scene loader fails fast if a referenced script doesn't exist. Workflow: write the scene wiring in step 8, but have stub scripts ready (extends BuildingPanel with no overrides) so the scene loads. Specialized rendering lands in the next step. Avoided a "broken scene during step 8" hour-long debugging session.

### Roadmap implications

This is **Session 1 of a 4-session arc**. The slot_layout abstraction + BuildingPanel base + shared CursorStack are the foundation; the next 3 sessions add specialized UIs for the remaining buildings:

- **Session 2 — Chest + food chain processors.** Chest UI (replaces existing paired-view inventory grid hack), Mill, Mixer, Oven, Proofer, Packager. ~6 new panel subclasses; main architectural concern is whether the existing chest paired-view migrates to a BuildingPanel subclass or stays as an inventory_grid mode (likely migrate for uniformity).
- **Session 3 — Cloth chain + remaining processors.** Retter, Loom, Tailor, Briquetter, Sugar Press, Yeast Culture. ~6 panel subclasses. Click-handling-duplication smell revisits here per the NOTES follow-up.
- **Session 4 — Extraction.** Harvester, Planter (3 variants?). Architectural concern: planter has no input/output buffer in the conventional sense (crops grow on the tile itself); UI shape may diverge enough to warrant a non-Processor-shaped slot_layout.

Cross-cutting throughout: every new panel subclass is ~150-250 lines of layout. The expensive code (drag-drop, validation, modal lifecycle) was paid this session; future panels are mostly visual layout.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers, click-to-pan-from-minimap — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Mining category at 2/9** — smelter session carry. Next building added joins Mining.
- **Click-handling duplication** between inventory_grid + BuildingPanel — captured in NOTES.md, revisit at Session 3 (4+ consumers).
- **Specialized building UIs for remaining 14 buildings** — Sessions 2-4 (captured in NOTES.md as multi-session arc).

---

## Burner smelter — first multi-recipe processor + Burner reusability validation (save v14, no bump)

**Date:** 2026-05-03
**Tag:** `session-smelter`

The first ore-refining tier: a 2×2 furnace that smelts iron ore → iron ingot or copper ore → copper ingot, fed fuel by the same Burner module shipped one session ago in the mining drill. Two architectural firsts:
1. **Multi-recipe Processor.** Mill, Mixer, etc. each have one recipe. Smelter has two and picks at runtime based on what arrives — the architectural foundation for future configurable processors (Oven via UI, kiln, refinery).
2. **Burner module's second consumer.** This session was the validation: did the Burner abstraction pay off? Result: **yes — ~13–15 lines of fuel-related code in smelter vs ~11 in drill, rough parity**. The module's reusability is real.

### What shipped

**`scripts/world/smelter.gd`** (~280 lines)
- 2×2 footprint, three rotating ports + one unused: ore in (W), ingot out (E), fuel in (S), N idle.
- 4-state machine: IDLE / SMELTING / NO_FUEL / BLOCKED_OUTPUT. Fuel committed up-front at IDLE→SMELTING (1 fuel unit per ingot via `Burner.consume_tick(b, 1)`). NO_FUEL has explicit recovery branch — when fuel arrives mid-stall, smelter resumes immediately without waiting for the next batch boundary.
- 40 ticks (2 sec) per ingot at 20 sim tps → 0.5 ingot/sec. Matches drill's 0.5 ore/sec rate, giving a clean 1:1 drill→smelter pairing.
- Fuel cost asymmetry: 1 wood = 1 ingot (vs drill's 1 wood = 8 ore). Smelting is 8× more fuel-intensive than mining, reflecting the reality of sustained heat vs. mechanical extraction. Briquettes (made from wheat-chain straw) become high-value: 1 briquette = 8 ingots ties bread chain into iron production.
- Visual: anthracite body, lighter chimney top-center, dim ember mouth bottom-center that brightens to orange-red when SMELTING. State-tinted body (cool blue for NO_FUEL, yellow for BLOCKED, orange overlay for SMELTING).
- Q-inspect: prominent "Currently smelting: <recipe display name>" line, progress bar, in/out buffers, fuel via `Burner.info_lines`, port assignments, fuel port direction (rotated), facing.

**Multi-recipe runtime selection (`_maybe_select_recipe`)**
- The architectural meat. At IDLE, smelter scans:
  1. **`in_buffer` first** — FIFO via array order. First-arrived ore wins. If iron is at index 0 and copper at index 1, recipe = `smelt_iron`.
  2. **Input port peek** — if buffer is empty, scan adjacent W-edge belts for any recipe-eligible ore. First found wins.
  3. **Else** — leave recipe_id unchanged.
- Once SMELTING, recipe is pinned for the duration of that batch. Switching only happens at IDLE with empty in_buffer.
- Hardcoded `_INPUT_TO_RECIPE` map (IRON_ORE → smelt_iron, COPPER_ORE → smelt_copper). At >5 entries, derive from `Recipes.for_building(SMELTER)` — for v1 (2 recipes), explicit is clearer.

**`Recipes.DATA`: 2 new recipes**
- `smelt_iron`: IRON_ORE (W) → IRON_INGOT (E), 40 ticks, capacity 8/8.
- `smelt_copper`: COPPER_ORE (W) → COPPER_INGOT (E), 40 ticks, capacity 8/8.

**`Items` registry: 2 new ingots**
- IRON_INGOT (gunmetal gray, max_stack 100) — refined materials convention.
- COPPER_INGOT (warm copper-orange, max_stack 100). The ore→ingot color shift (rust→gunmetal, verdigris→copper) is intentional player feedback: visibly different post-furnace.

**Hotbar reorganization: new "Mining" category**
- Previous: Production at 9/9 with no thematic home for the smelter.
- Now: Mining category contains drill (moved from Production) + smelter. Production drops to 8/9 with a free slot for cloth-chain expansion.
- 6 categories total (Terrain · Logistics · Production · Refining · Mining · Storage). Tab cycle still snappy.
- Future kilns, lumber camp, charcoal kiln, drill tiers all land in Mining. If the category grows past 9, split into "Mining" + "Smelting" — captured as future-work note.

**Tests: 20/20 passing** (was 19; added 1)
- **NEW** `test_smelter` — covers basic iron production, copper production, **explicit FIFO recipe-switching contract** (4 iron in_buffer + 2 copper in_buffer → produces exactly 4 iron ingots first, then 2 copper, recipe switches at the right moment, no copper produced before iron exhausted), fuel decrement at 1-fuel-per-ingot, NO_FUEL state with refuel recovery, BLOCKED_OUTPUT state (recipe doesn't start when output at cap), save round-trip mid-batch (progress + fuel + state + recipe_id + in_buffer all preserved).

### Burner integration line-count audit (architectural verification of session-mining-drill investment)

| Category | Drill | Smelter |
|---|---|---|
| Fuel constants | 1 | 3 |
| `Burner.make_state` merge in make() | 2 | 2 |
| `Burner.try_pull_fuel` call | 1 | 1 |
| `Burner.consume_tick` + NO_FUEL branch | 4 | 5 |
| `Burner.info_lines` forwarding | 2 | 2 |
| Fuel port display | 0 | 2 |
| **Total fuel-mechanic lines** | **~11** | **~13–15** |

**Verdict: parity. Burner architecture validated.** The ~2–4 line delta in smelter is building-specific tuning:
- Directed fuel port (S edge) vs drill's any-edge → +2 lines (constant + display).
- Explicit NO_FUEL recovery branch (smelter resumes mid-stall without waiting for batch boundary) → +1–2 lines.

~80% of fuel logic shared via Burner module. **Charcoal Kiln (next burner building) projected at similar line count without Burner expansion.**

### Decisions

- **Auto-select recipe (option a) over player-set lock (option b) or hybrid (option c).** The deciding argument: belt routing IS the recipe selector. A smelter that "smelts whatever arrives" is a feature, not a limitation, because the player has full control over what arrives. Want iron-only? Build an iron-only feed line. This matches Factorio's smelter model — single-recipe-at-a-time auto-select, no per-machine config. Option (b) creates worse failure modes (wrong-ore arrives at locked smelter, sits on belt blocking the line; invisible-by-default cause). Option (c) builds UI for a 5%-of-players feature.
- **FIFO via array order.** `in_buffer` is `Array of [type, count]` — insertion order naturally preserved across JSON round-trip. First-arrived-ore wins gives the player a deterministic mental model and survives save/load without extra state.
- **Fuel committed up-front at IDLE→SMELTING.** With 1 fuel per ingot and 1 ingot per batch, paying fuel at the start of a batch (not mid-progress) is the simplest semantics and avoids "consumed fuel mid-batch but couldn't finish" failure modes. `Burner.consume_tick(b, 1)` = "pay 1 fuel; if fuel_buffer is 0, return false." Returning false transitions to NO_FUEL without any state mutation — clean check-and-commit idiom.
- **2×2 footprint matches drill.** "Industrial 2×2 = mining-tier" visual identity. Pack-density cost (4 tiles per smelter) is real but minor. Matches drill so player sees consistent industrial language across the mining→smelting chain.
- **NO_FUEL has its own state with explicit recovery, not a passive substate of IDLE.** Drill's "stay-at-threshold" pattern works for drill because drilling is incremental. Smelter is batch-based — without an explicit NO_FUEL state, the smelter would have to re-evaluate IDLE→SMELTING transition every tick, paying fuel-check overhead each time. Explicit NO_FUEL with one-direction recovery is cleaner and matches the player UX ("the smelter is stalled because it has no fuel, refuel it").
- **Recipes registered separately, not as a "recipe family."** Each recipe is its own DATA entry. `Recipes.for_building(SMELTER)` returns both. The smelter's `_INPUT_TO_RECIPE` map is the runtime selector. This keeps the Recipes registry shape uniform — no special "polymorphic input" recipe shape.
- **Fuel port is NOT in Recipes.DATA.** Burner is generic infrastructure, not recipe-aware. Smelter declares `FUEL_PORT_DIR` as a building-level constant. Future smelter variants (electric tier) might have different fuel concepts; keeping fuel out of Recipes.DATA preserves Burner's reusability boundary.
- **New "Mining" hotbar category.** Two new categories (Mining + Smelting) for 1 building each was over-investment. Single "Mining" category covers the whole heavy-industry tier. Drill + smelter feels coherent. Future kilns join here. If the category exceeds 9 slots, split — flagged as future work.
- **Recipe pre-selector wraps Processor instead of replacing it.** Smelter calls `Processor._try_pull_inputs`, `Processor._has_all_inputs`, `Processor._has_room_for_outputs`, `Processor._consume_inputs`, `Processor._emit_outputs`, `Processor._try_push_outputs` directly (calling underscore-prefixed methods). The state machine is smelter-owned; the *helpers* are shared. This validates Processor's helpers as building blocks even when the state machine itself diverges.

### Lessons

- **The "1-2 sessions ahead" forecast bore out exactly.** Last session's design pass projected: "Path (b) Burner module pays off the moment we add a second burner — ~80 lines saved vs Path (a) drill-specific." This session's audit: ~13–15 fuel lines in smelter vs ~50+ if we'd duplicated drill's fuel logic. Net savings ~35–40 lines on this session alone, plus a Burner module that's now battle-tested. The forecast was the difference between confident architectural choice and hand-wavy "extensible." Worth doing again for the next reusability call.
- **Test the FIFO contract explicitly.** The "auto-select" recipe model has a subtle invariant: 4 iron + 2 copper in buffer must produce 4 iron then 2 copper, never interleaved. Without an explicit test, a future array-shuffle in some pull/sort path could break this silently. The session-smelter test_smelter test asserts batch-by-batch progression (`[1, 2, 3, 4]` iron, then `[1, 2]` copper), catching ordering regressions. Pattern worth applying to any "ordering matters" contract.
- **Save round-trip test needed correction.** First draft asserted `in_buffer` iron count was 3 (the pre-tick value). Wrong — at the moment of save, the smelter had already transitioned IDLE→SMELTING and consumed 1 iron, so the saved value was 2. Lesson: when testing save round-trip mid-operation, capture the pre-save value and compare to post-load, don't hardcode the expected. Same trap I almost hit in the drill test (resource_state).
- **Calling `Processor._helper` from outside Processor is fine.** GDScript's underscore is convention, not enforcement. The helpers (`_try_pull_inputs`, `_consume_inputs`, etc.) are pure static functions taking explicit arguments — they're naturally reusable. The convention violation is documented with one comment in smelter.tick. If reuse grows beyond smelter, rename to drop the underscore (or add public passthrough wrappers). For now, calling underscore methods is the pragmatic answer.
- **Two extra lines for "fuel port display" in info_lines is worth it.** Drill doesn't show a fuel port direction because drill accepts fuel from any edge. Smelter has a directed S port — players need to know that to plumb fuel correctly. Two lines of UI for one building-specific UX detail is the right level of investment.

### Roadmap implications

- **Charcoal Kiln** (likely next burner building): WOOD → CHARCOAL, where CHARCOAL is a higher-tier fuel (8 units? to be tuned). Burner already supports adding CHARCOAL to the FUEL_VALUES dict — single line. Kiln itself is ~30 lines of building-specific code on top of Processor + Burner. Multi-recipe selection isn't needed (one recipe). Estimated total: similar to smelter at ~250 lines.
- **Brick Kiln**: CLAY → BRICK. Same shape as Charcoal Kiln but different recipe. Output BRICK becomes a building material (future Stone Crusher gets RAW_STONE → STONE_BLOCK; brick fits the same materials category).
- **Tier-2 / electric smelter**: deferred until electricity infrastructure lands. Architecturally trivial — speed multiplier on `time_ticks`.
- **Module slots / smelter upgrades**: deferred. The Building.state Dict is extensible — adding a `modules` field is non-structural.
- **Building Interaction UI** (captured separately in NOTES.md): drag-drop between player inventory and building slots. Retroactive on drill + smelter; foundational for all future interactive buildings.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers, click-to-pan-from-minimap — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Mining category at 2/9** — plenty of room. If it exceeds 9, split into Mining + Smelting.
- **Building Interaction UI** — new this session, captured in NOTES.md as next-session candidate.

---

## Burner mining drill — first automation tier (save v14, no bump)

**Date:** 2026-05-03
**Tag:** `session-mining-drill`

The first slice of mining automation: player places a 2×2 drill on top of an ore patch, feeds it fuel from an adjacent belt or chest, and ore flows out the prefer_dir port. Same `deplete_resource` primitive the manual-mining tier uses; same Burner-fuel mechanic that future smelters and charcoal kilns will reuse. No save bump — drill state lives entirely on `Building.state` (Dict-shaped, JSON-clean) and rides through the existing v14 building round-trip with zero schema changes.

### What shipped

**`scripts/world/burner.gd`** — generic fuel infrastructure (~130 lines)
- Static helpers: `try_pull_fuel(b, world, fuel_edge_dir=-1)`, `consume_tick(b, ticks_per_unit)`, `info_lines(b)`, `make_state()`.
- Fuel item → energy unit table: `WOOD: 1, COAL: 4, FUEL_BRIQUETTE: 8`. Tunable per item by editing one dict entry; future fuels (CHARCOAL, etc.) are append-only.
- `FUEL_BUFFER_CAPACITY: int = 16` — units, not item count. Items convert via `FUEL_VALUES` on pull. A coal item in a buffer of 13 doesn't pull (would overfill).
- State convention on the burner building: `fuel_buffer: int` (units), `fuel_burn_progress: int` (ticks toward next unit consumption).
- `consume_tick(b, ticks_per_unit)` returns `false` when the buffer is empty — the building's tick handler sets its own NO_FUEL state on this signal. Burner doesn't know what state means; the consumer interprets.

**`scripts/world/mining_drill.gd`** (~340 lines)
- 2×2 footprint covering up to 4 ore deposits.
- Fuel input: any of 4 edges (no fuel prefer_dir for v1; pulls from belts/chests indiscriminately).
- Output port: prefer_dir, rotates with `b.state.dir` via `Buildings.world_dir(b, recipe_dir)`. Default canonical-East.
- **DRILL_TICKS_PER_ORE = 40** (0.5 ore/sec at 20 sim tps). Slower than manual stone/coal/clay (2/sec) but faster than manual iron/copper (1/sec). Factorio-style automation-not-speed.
- **DRILL_ORE_PER_FUEL = 8** (1 wood = 8 ore = 16 sec; 1 coal = 32 ore = 64 sec).
- State machine: `IDLE / DRILLING / NO_FUEL / BLOCKED_OUTPUT / DEPLETED`. Body+head visual tinted by state (red for no fuel, yellow for blocked, gray for depleted).
- **Highest-richness-wins deposit selection** (per Q7 design pass) — each tick scans `covered_deposits`, picks max richness, tiebreaks topmost-leftmost. Zero state, no save burden, no edge cases. Player UX: drill goes for the rich stuff first; transitions to lesser deposits as the prime ones drain.
- `covered_deposits: Array of [x, y]` — populated once at placement (in `GridWorld.place_building` via `MiningDrill.refresh_covered_deposits` post-hook), persists in state across save/load. `make()` can't see the world, so the post-hook bridges that.
- Q-inspect (`info_lines`) shows: Status, **prominent "Currently producing: <ore>"** (per Q11 pushback), fuel buffer, output buffer, covered deposits sorted by richness desc with per-deposit coords + remaining richness, and Facing.

**Building-placement-cancels-regrowth (generic, all buildings)**
- Pushback 1 from the design pass: building placement now cancels active tree regrowth in footprint cells. Same logic as `set_overlay`'s overlay-cancels-regrowth rule, but triggered by any building placement in any 2×2+ footprint.
- Defensive: only cancels for `regrowth_remaining` specifically; doesn't touch ore richness or other resource_state fields.
- Generic: applies to every building type (Mixer, Oven, drill — anything that physically occupies a tile).
- Player intuition: if you've placed a building, the tree won't pop back through it.

**Wired into existing dispatch**
- `Buildings.Type.MINING_DRILL` enum slot appended (save-stable).
- DATA entry: 2×2 footprint, gray-brown swatch, `requires_overlay: [NONE, STONE]` (drill can sit on bare grass OR stone industrial floor; soil/path don't make sense).
- `make()` / `tick_one()` / `draw_one()` / `info_lines_for()` dispatch added.
- `GridWorld.can_place_building` calls `MiningDrill.validate_placement` for Q9 rules: ≥1 ore in footprint, no water, no trees. Errors surface via existing toast.
- Hotbar Production category, slot 9 (now full at 9/9).

**Tests: 19/19 passing** (was 18; added 1)
- **NEW** `test_mining_drill` — covers: placement validation (4 sub-cases: valid, no-ore reject, water reject, tree reject), single-cycle production with highest-richness-wins assertion, fuel decrement at the 8-ore boundary, NO_FUEL state, save round-trip preserving drill_progress + fuel_buffer + covered_deposits, and the generic building-placement-cancels-regrowth rule.

### Decisions

- **Path (b) generic Burner over Path (a) drill-specific.** Forecast: ~80 lines shared infrastructure; pays off the moment we add a second burner (smelter, charcoal kiln). Bug fixes happen in one place. Fuel-type extension is a single dict edit. Q-inspect "Fuel: 3 / 16 units" is uniform across all burners. Cost is ~10 lines of indirection that the next burner saves us 60+ on.
- **Path (e) highest-richness-wins over (a) round-robin.** Round-robin needs cursor state, has tiebreak edge cases, requires save round-trip, and feels arbitrary to the player ("why is the drill ignoring the rich tile?"). Highest-richness needs zero state, no edge cases, no save burden — and matches the player's instinct ("drill goes for the rich stuff first"). Tiebreak is topmost-leftmost (sort by y, then x); deterministic.
- **Drill produces ore at uniform 0.5/sec across all ore types.** Factorio model: automation isn't faster than manual; it's *unattended*. Iron/copper drilling at 0.5/sec is half the manual rate (1/sec) but gains the player back their attention. Stone/coal/clay drilling at 0.5/sec is a quarter of manual (2/sec); a single drill is unambiguously slower than a player crouched over a stone patch — but a *bank* of drills is a different game.
- **`covered_deposits` cached at placement, refreshed via post-hook in `place_building`.** The alternative — recomputing every tick — was rejected: cheap per drill, but for 50+ drills it's a real cost AND the deposit list never changes after placement (depletion is handled via `richness_at(pos) > 0` filter). The post-hook in `place_building` (rather than passing world to `make()`) keeps `Buildings.make` signatures uniform.
- **`requires_overlay: [NONE, STONE]`.** Bare grass is fine for drill placement (industrial machinery in the wilderness; matches mining-camp aesthetic). Stone overlay is the formal industrial floor. Soil/path don't make sense semantically and are rejected.
- **No save bump.** Drill state is pure Dict (ints, arrays, strings) — rides through `Building.from_dict` round-trip with the existing v14 schema. Adding the new building type doesn't change save layout.
- **Building-placement-cancels-regrowth pushback was right.** The `set_overlay` rule already cancels regrowth; same physical reality applies to building placement. Generalizing the existing rule to a new trigger is mechanical, not architectural — ~5 lines in `place_building`. Future 2×2+ buildings inherit it for free.

### Lessons

- **The "1-2 sessions ahead" forecast for Path (b) was the right framing.** Abstract "extensible vs simple" debates produce hand-wavy answers. Concrete projection ("here's the smelter's `_try_pull_fuel`; here's the charcoal kiln's") forces the comparison to be honest. Both paths look the same at session 1; Path (b) starts winning at session 2. The forecast was the difference between a confident decision and a coin-flip.
- **Save model has hidden assumptions.** First test draft tried to verify ore richness round-trip after save/load. Failed because the save/load model is procgen-rehydration: WorldGenerator regenerates the canonical world from seed, then `resource_state_modifications` applies player deltas on top. Test world used `_set_ore` to manually place tiles — those tiles aren't in worldgen, so the modifications applied to nothing. Resource round-trip is already covered by `test_resource_state_modifications_roundtrip` (which uses WorldGenerator). Lesson: when writing a test that touches save/load, either go through worldgen (full faithful round-trip) or scope the test to verify only the new state shape (drill state in our case). Don't reach across system boundaries unless the boundary itself is the test target.
- **`make()` can't see the world.** Standard pattern in this codebase: `Buildings.make(t, pos, dir, extra)` returns a Building before `place_building` registers it. Drill's `covered_deposits` needs the world's tile dict to populate; the post-hook in `place_building` (after `Buildings.make` returns, before `buildings[pos] = b`) is the natural seam. This pattern will recur for any future building that needs a world-context-aware initial state.

### Roadmap implications

- **Smelter** (likely next mining-tier session): `Burner` is ready. Smelter `make` calls `Burner.make_state()`, smelter tick calls `Burner.try_pull_fuel` + `Burner.consume_tick(b, RECIPE_TICKS_PER_FUEL_UNIT)`. Recipe-driven via existing `Processor` infrastructure. Combined estimate: ~30 lines of smelter glue + recipe entries.
- **Charcoal kiln** (parallel): same shape; consumes WOOD as both input AND fuel. Output CHARCOAL becomes a higher-tier fuel (8 units? to be tuned). Burner's `FUEL_VALUES` already designed for the addition.
- **Tier-2 burner drill / electric drill**: speed multiplier on `DRILL_TICKS_PER_ORE`. Out of scope for this session per spec.
- **Lumber camp**: not a burner; calls `chop_tree` directly on adjacent trees with built-in scheduling. Unrelated to Burner architecture; mentioned for completeness.
- **Ore depletion at drill scale**: a single drill fully drains a typical 100-richness patch in 200 seconds (3.3 min). Several drills clustered will drain a region quickly. Future "find new patches" exploration loop becomes a real game pressure once drills proliferate.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers, click-to-pan-from-minimap — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** (tree-harvest carry).
- **Hotbar Production category at 9/9.** No room to add a 10th building. Next building added to Production triggers either splitting into a new category ("Mining" comes to mind) or rebalancing Refining (currently also 9/9). Layout choice deferred to next placement session.

---

## Tree harvesting — manual tier + variable yield (save v13 → v14)

**Date:** 2026-05-04
**Tag:** `session-tree-harvest`

The second slice of manual harvesting: player walks adjacent to a tree, holds Spacebar, gets wood, tree disappears, regrows after 5 minutes. Wood yield varies 1-4 per tree based on visible tree size (deterministic per position). Three smaller fixes also shipped in this session: safe player spawn (no more starting in water), inventory panel relocated below the minimap, and a generic-Dict schema shape for `resource_state_modifications` that makes future per-tile state types (crops, berries, etc.) config-only additions.

### What shipped

**Tree chop mechanics**
- Reuses Spacebar (the existing `mine` input action) — same "extract resource" verb for both ore and trees.
- Hover-targeted: cursor over an adjacent tree + Space held = 2-second chop tick → tree gone, wood added to inventory.
- Adjacency: same as mining (Manhattan ≤ 1, includes own tile).
- Auto-stops when target depletes (tree gone) or moves out of range.
- Inventory full: rate-limited toast `Inventory full.`, no extraction.

**Variable wood yield**
- `GridWorld.wood_yield_for_tree(pos)` — static helper, deterministic per position.
- Yield distribution (skewed toward small trees):
  - ~50% yield 1 (common scrubby tree)
  - ~35% yield 2
  - ~10% yield 3
  - ~5% yield 4 (rare big tree)
- **Correlated with visible size**: uses the same byte of the position hash that drives `size_jitter` in `_draw_tree`. Visibly bigger trees actually give more wood. Player learns to recognize value-vs-effort at a glance.
- Q-inspect on mature tree shows `Yields N wood` line.
- Yield is a property of the position (not the tree instance) — survives chop/regrowth cycles.

**WOOD item**
- New `Items.Type.WOOD` — color brown matching trunk (`Color(0.50, 0.32, 0.18)`), max stack 200, bare name (no `RAW_` prefix; consumed directly).
- Future hooks: charcoal kiln (`WOOD → CHARCOAL` alternative fuel), sawmill (`WOOD → PLANKS` building material).

**5-minute regrowth timer**
- `TREE_REGROWTH_SECONDS = 300.0`. Long enough that a re-visited chopping ground feels rewarding; short enough that a 30-min play session sees a full cycle.
- `GridWorld._process(delta)` ticks active timers each frame via `_tick_regrowth`. O(active timers) per frame; negligible cost.
- Restored tree visual is identical to canonical (same `_draw_tree` jitter) — same yield, same size, same color (deterministic per position).

**Code-share rename: `MINING_*` → `HARVEST_*`**
- One verb covers both mining and chopping at the player-input layer:
  - `MINING_TICK_INTERVAL` → `HARVEST_TICK_INTERVAL` (now includes TREE: 2.0)
  - `MINING_RESOURCE_TO_ITEM` → `HARVEST_RESOURCE_TO_ITEM` (now includes TREE: WOOD)
  - `_try_mining_tick` → `_try_harvest_tick` (dispatches: `is_ore` → `deplete_resource`, TREE → `chop_tree`)
  - `_resolve_mining_target` → `_resolve_harvest_target` (filter via `HARVEST_TICK_INTERVAL.has`, replaces hardcoded `is_ore` check)
  - GridWorld's `mining_indicator_*` → `harvest_indicator_*`
- Inventory-full handling shared across both paths — written once, applied uniformly.
- Buildings (future drills, lumber camps) call into the underlying primitives (`deplete_resource`, `chop_tree`) directly — they don't go through `_try_harvest_tick`. Player input layer and building tick layer are independent.

**Save format v13 → v14: generic Dict shape**
- `resource_state_modifications` field shape changed from `Array of [x, y, richness:int]` to `Array of [x, y, dict]` where dict carries fields per resource type:
  - Ore: `{"richness": int}`
  - Tree: `{"regrowth_remaining": float}`
  - Future (crops, berries, etc.): just add keys; no schema bump
- v13 saves hard-fail with `OS.alert` per existing schema-bump policy.
- Trade-off: lighter typing per entry. GDScript dynamically typed anyway; `state.get(key, default)` idiom matches existing patterns (`tile.state.get("dir", 0)`, `building.state.get(...)`).

**Overlay-cancels-regrowth rule**
- New rule in `set_overlay`: if target tile has `resource_state[pos]["regrowth_remaining"]`, erase the regrowth timer before placing overlay. Player committed to paving — tree won't return.
- Defensive check: only cancels for `regrowth_remaining` specifically, not blanket-erase. Future code paths that programmatically `set_overlay` on tiles with other resource state shapes are unaffected.

**Spawn position fix (safe spawn)**
- Old behavior: player at hardcoded `(64, 64)` = tile `(2, 2)`. On many seeds this lands in a spawn-area lake.
- New: `_safe_spawn_position()` — scans tiles within 30-tile radius of origin, picks from top 20 closest passable tiles using seeded RNG. Same seed → same spawn (save/load consistent); different seeds → different spawn (variety per fresh start).
- Fallback to `(0, 0)` if no passable tile found (extreme seed). Player's escape valve in `player.gd::_move_with_passability` lets them walk off impassable.

**Inventory panel layout move**
- `inventory_panel.gd::_ready` updated `offset_top` from 80 → 244, putting the panel below the minimap (which sits at top=10..234 with 224 height) with a 10px gap.
- `info_panel.gd` bumped from 240 → 560 to stay below the inventory panel's typical max height.

**Tests: 18/18 passing** (was 17; added 1, updated 2)
- **NEW** `test_tree_harvest_lifecycle` — covers chop_tree mutation, regrowth tick, full restore at timer-end, save mid-regrowth round-trip, overlay-cancels-regrowth rule, WOOD item registration, AND wood-yield distribution sanity (yield 1 most common, yield 4 rare; deterministic per position).
- **UPDATED** `test_save_load_roundtrip` for v14 (Dict shape).
- **UPDATED** `test_resource_state_modifications_roundtrip` — assertions adjusted for Dict-shaped modifications. Test still covers partial AND full ore depletion round-trip.

### Decisions

- **(a) Generalize-and-rename over (b) separate functions.** The verb truly is "harvest" for both ore and trees; "mining" was a subtype. Single dispatch path keeps inventory-full handling shared and keeps the player-input layer compact. Buildings are independent of this layer; (a) vs (b) doesn't affect future drills/lumber-camps.
- **Path 1 (generic Dict) over Path 2 (parallel fields).** Forward-extensibility wins for the next 5+ stages of features. Adding a third resource state type = config-only key. Path 2 would force schema bump + new field + new serialize/load loop every time. GDScript's dynamic typing makes the "lighter typing" cost real-but-tolerable.
- **(c) Cancel regrowth on overlay placement.** Player committed; honor the intent. Maintains the "no overlay + resource_node simultaneously" invariant naturally. Also matches the stewardship theme: terraforming is a commitment.
- **Variable yield tied to visible size, not random per-chop.** Same hash byte drives both `size_jitter` and `wood_yield`. Player can predict yield by looking at the tree. Deterministic per position; yield doesn't change after regrowth.
- **5-minute regrowth at default.** Single tunable constant; balance based on playtest feedback.
- **`wood_yield_for_tree` static helper, no per-tile state for yield.** Yield is a property of the position, derived from hash. No state to persist. Survives chop/regrowth/load cycles automatically.
- **`Tile.is_passable()` system was the right primitive.** It existed already (water collision in mining-manual session); added the spawn-position fix on top, no new infrastructure. Future passability checks (cliffs, walls, etc.) get the same treatment for free.

### Lessons

- **Generic schema paid off immediately.** The Dict-shape decision was made for tree regrowth in this session, but the next two state-type additions (whatever they are) will be schema-free. Path 1 vs Path 2 is the kind of architectural decision where the win is invisible until the second use case lands; the second use case shipped one session later.
- **Same-byte-hash trick: visual variance + gameplay variance for free.** Reusing the byte of the position hash that drives `size_jitter` to also drive yield means the two are inherently correlated. Player perception ("big tree = more wood") is automatically backed by code; no separate state, no risk of drift between visual and gameplay layers. Pattern worth reusing for future "visible variance" features (crop quality, berry ripeness, etc.).
- **Mid-session refinement was cheap.** User's "big trees should give more wood" landed late but cost ~30 lines (one helper, one dispatch site, one Q-inspect line). Variable-yield architecture was already implicit in the chop-tick dispatch — just needed an `amount` parameter.
- **Spawn-on-water was a latent bug** invisible until water collision shipped (mining-manual session). Before water-collision, spawning in water was awkward but not broken. After water-collision, spawning in water leaves the player on impassable terrain, escape-valve required. The bug existed for one session before showing up in playtest. Lesson: when changing movement rules, sweep all spawn / placement sites for new edge cases.
- **UI layout drift is easy to forget.** Inventory panel moved → info panel needed to follow. Both reference the SAME visual region of the screen (top-right column). When relocating one, sweep callers/neighbors for layout dependencies. Bumped info_panel.gd `offset_top` 240 → 560; would have been an obvious "the info panel disappeared!" bug at next Q-inspect smoke.
- **The Path 1 schema cost showed up in the test.** `test_resource_state_modifications_roundtrip` had `int(modifications[pos])` assertions that broke when shape changed. Updated to `dict.get("richness", -1)` — clean, but a reminder that schema changes ripple to test code.

### Migration

Save format v13 → v14. **All existing v13 saves hard-fail on load** with `OS.alert`. Player must delete `%APPDATA%\Godot\app_userdata\Stewardship\save_slot_1.json` and start fresh. Reason: structural change to `resource_state_modifications` (int → Dictionary) is incompatible with v13's int reader path.

### Roadmap implications

- **Burner mining drill** (next likely): the architecture supports it directly. Drills call `GridWorld.deplete_resource(pos, amount)` from their tick handler with `amount > 1`. No code in this session needs changing for drill support.
- **Lumber camp** (parallel to drill): calls `GridWorld.chop_tree(pos)` directly + handles its own scheduling. Wood yield via `GridWorld.wood_yield_for_tree(pos)`.
- **Charcoal kiln / sawmill**: process WOOD into CHARCOAL / PLANKS. Standard processor recipe; no new mechanics needed.
- **Soil exhaustion**: extends `resource_state` to non-ore tiles (e.g., `{"fertility": float}` on farmable grass). Path 1 generic-Dict shape supports this with zero schema changes.
- **Sapling visualization**: deferred polish item. Currently regrowing tiles render as plain grass; a small sapling sprite would be discoverable in playtest.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (worldgen-stage1 carry).
- **Cloth chain `prefer_dir` polish** (Session E carry).
- **Map polish** (zoom, markers, click-to-pan-from-minimap — explore-map carry).
- **Patch-edge zero-richness tiles** (mining-manual carry).
- **Sapling visual during regrowth** — new this session. Empty-grass during 5-min regrowth feels invisible; small sapling sprite + size-grows-toward-mature animation would be discoverable. Defer to polish session.

---

## Mining mechanics — manual tier (save v12 → v13)

**Date:** 2026-05-04
**Tag:** `session-mining-manual`

The first slice of mining mechanics: player walks adjacent to a deposit, holds a key, ore enters inventory, deposit depletes, and when richness hits 0 the tile reverts to grass. Foundation for future drill tiers, soil exhaustion, and processing chains.

Three significant non-mining changes also shipped in this session: a generic `Tile.is_passable()` system (water now blocks player movement, extensible for future cliffs/walls), a deposit-overlay rule reversal (overlay placement on deposit tiles is now blocked — previous "overlay obscures deposit, RMB reveals" design was a UX trap that's been removed), and a `resource_state_modifications` parallel-architecture save field that fits cleanly alongside the existing `tile_modifications` model.

### What shipped

**Mining input + targeting**
- Mine action bound to **Spacebar (held)**.
- Hover-targeted: cursor over an adjacent deposit + Space held = mining ticks. Manhattan distance ≤ 1 from player tile (4-directional + self).
- Mining auto-stops when target tile depletes, target moves out of range, or Space released.

**Tick rate (per resource)**
- Stone, Coal, Clay: **2/sec** (commodity / common-fuel tier).
- Iron, Copper: **1/sec** (advanced ore tier; intentionally slower to incentivize drill upgrades in a future session).
- Each tick drains 1 richness AND produces 1 ore.

**5 new items in `Items` registry**
- `RAW_STONE` (gray, max_stack 200) — avoids `Terrain.Overlay.STONE` namespace collision; future stone-crusher chain produces `STONE_BLOCK`.
- `COAL` (near-black, 200) — feeds existing `FUEL_BRIQUETTE` chain directly.
- `IRON_ORE` (rust, 100) — `_ORE` suffix anticipates `IRON_INGOT` post-smelting.
- `COPPER_ORE` (verdigris, 100) — same pattern.
- `CLAY` (warm orange, 200) — future brick / pottery chains.
- Naming convention documented in `items.gd` header: `RAW_*` for collision-dodge or substantial-transformation, `*_ORE` for smelt-to-ingot, bare names for direct-use materials.

**Resource state with original_richness**
- Every patch tile now stores `{richness: int, original_richness: int}` in `GridWorld.resource_state[pos]`. `original_richness` is set once by `WorldGenerator` and stays constant for the patch's lifetime. Used by visuals for proportional alpha-fade.
- `original_richness` is NOT persisted in save — rederived from `(world_seed, worldgen_version)` at load time via procgen rerun.

**Save format v12 → v13**
- New top-level field `resource_state_modifications: Array of [x, y, richness]` — sparse, only stores tiles whose richness has been depleted from procgen-canonical state.
- **Architecturally parallel** to `tile_modifications`: WorldGenerator restores canonical state on load, then this overlay applies player-driven mining changes on top.
- Fully-depleted tiles (richness=0) handled by `tile_modifications` (resource_node = NONE); their entry in `resource_state_modifications` is erased at depletion.
- v12 saves hard-fail with `OS.alert`. **Dual reason for the bump**: (1) new field, (2) the "no overlay on deposits" rule reversal — v12 saves could have stale overlay-on-deposit tiles now considered invalid.

**Tile-passability system** (`Tile.is_passable()`)
- Generic Boolean check on every tile. Returns `false` for water, `true` for everything else. Extensible: future cliff / wall / structure-blocking variants override the same method.
- `GridWorld.is_passable_at(pos)` defaults to passable for unmapped tiles (implicit grass).
- `Player._move_with_passability(delta)` replaces `move_and_slide()` for tile-level movement: per-axis sliding so diagonal movement glides along water edges instead of stopping dead. Defensive: player on impassable terrain (e.g., scripted spawn) can still escape.

**Deposit-overlay rule reversal**
- Yesterday's "overlay obscures deposit, RMB-clear reveals" design was reversed. **New rule: overlay placement is BLOCKED on deposit tiles.** Player must mine the deposit out (richness→0, tile becomes grass) before paving.
- Toast: `Mine the {ore} first.` (ore tiles) / `Can't pave over {tree}.` (tree tiles).
- Eliminates the UX trap where a player accidentally paves over a deposit and loses track of it. Matches the stewardship theme — you mine an iron vein, you don't pave over it.
- Mining-Q8 from the design pass became automatic under this invariant: deposits never carry overlays, so the "can't mine through overlay" check is redundant. Cleaned up.

**Visual feedback during mining**
- **Progress arc** on the targeted tile: yellow circular arc fills clockwise as the next tick approaches. Background dim ring gives the arc a "track." Drawn after buildings, before hover indicator, in `GridWorld._draw`.
- **Proportional alpha-fade** on partially-depleted deposits: `alpha = lerp(0.35, 1.0, current/original)`. Player sees at-a-glance how much is left. Alpha-fade survives save/load (current and original both restored correctly via procgen rerun + modifications overlay).

**Tile reversion on full depletion**
- `GridWorld.deplete_resource(pos, amount)` decrements richness; on hit-zero, erases `resource_state[pos]`, mutates `tiles[pos].resource_node = NONE`, and either erases `tiles[pos]` (if base+overlay both default) or records the depleted state in `tile_modifications`. Either way the next render shows grass.
- `resource_changed` signal fires per tile; `main.gd` forwards to `map_panel.mark_tile_dirty(pos)` so M-map / minimap re-render that region.

**Inventory full handling**
- Each mining tick: `inventory.has_room_for(item, 1)` check. Failed → toast `Inventory full.` (rate-limited to one per 30 ticks ≈ 0.5sec). No silent richness loss; the failed tick simply doesn't extract.

**Tests: 17/17 passing** (was 16; one new + one updated)
- **NEW** `test_resource_state_modifications_roundtrip` — partial-depletion via `deplete_resource`, save → clear → load → assert `richness` preserved AND `original_richness` rederived from procgen. Also exercises the full-depletion + save+load path: depleted tiles stay grass after reload (don't re-appear from procgen rehydration because `tile_modifications` overrides with `resource_node=NONE`). **THE critical test for v13.**
- **UPDATED** `test_save_load_roundtrip` — name v12 → v13.
- **UPDATED** `test_placement_rules` — overlay-on-deposit assertions (toast `Mine the ...`); overlay-on-tree assertions (toast `Can't pave over ...`); `Tile.is_passable_at()` assertions (water blocks, deposits/trees/grass/overlay all passable).

### Decisions

- **Deposits are walkable but block overlay placement.** Player walks freely over an iron deposit (it's "stuff on the ground," not an obstacle), but can't pave it (paving destroys data; mining preserves player intent). Two rules from different axes that don't conflict.
- **Mining requires NO overlay on the target tile** — but this is now automatic since the rule above forbids overlay on deposits in the first place. The mining check is defensive rather than active.
- **Generic `Tile.is_passable()` over hardcoded `is_water()`.** Future cliffs / walls / structure-blocking buildings will register as impassable via the same method. Cost today: zero (one new method on Tile, one new method on GridWorld). Future payoff: every blocker uses the same passability path, no `if water or cliff or wall or ...` cascades.
- **Per-axis sliding instead of `move_and_slide()`.** CharacterBody2D's `move_and_slide()` only respects Godot's physics-collision shapes; we don't have those for tiles. Custom per-axis check + global_position update bypasses physics in favor of direct tile-passability lookup. Diagonal movement near water glides along edge — required for "Factorio feel."
- **`original_richness` runtime-only, not persisted in save.** Recomputable from `(seed, worldgen_version)` at load time. Saving it would double the per-tile state and provide no information that procgen doesn't already produce deterministically. Same pattern as `tile_modifications` (player edits persist; procgen-canonical state is rederived).
- **Save schema v13 with dual-reason hard-fail.** Both the new `resource_state_modifications` field AND the rule-reversal-induced state-validity issue are addressed by the same v12→v13 bump. One bump, two architectural changes documented in the migration log.
- **Spacebar for mining (held).** Free key, conventional "primary action while moving," doesn't conflict with WASD movement. `mine` action added to project.godot.
- **5×5 region area mining check** (Manhattan ≤ 1, including self). Player can mine the tile they're standing on or any of 4 cardinal neighbors. Diagonal mining excluded — feels weird; matches placement adjacency conventions.
- **Tick rate per resource** (not uniform). Stone/coal/clay 2/sec, iron/copper 1/sec. Differentiates ore tiers in feel; future drill upgrades multiply rates.
- **Proportional alpha-fade requires `original_richness`.** Absolute-threshold alternative (e.g., "fade when richness < 30") would make a 500-richness iron tile look identical at 500 and at 50 — player can't read depletion at a glance. Tracking original is one int per ore tile (~6,400 tiles target generation = ~25KB) — negligible. Reversed during design pass review.

### Lessons

- **Yesterday's "overlay obscures deposit" design was wrong, and the cost was low to reverse.** The UX trap (player accidentally paves over a deposit and loses track) wasn't visible in design but became obvious in playtest. Reversed mid-session — `set_overlay` now rejects, downstream code (info_panel, mining checks) became defensive but kept their structure. Lesson: when a design rule has a clean architectural inverse, reversing it is cheap; the high cost is in the player-facing UX trap if you ship the wrong rule.
- **Headless tests catch architectural bugs that smoke tests miss.** The first run of `test_resource_state_modifications_roundtrip` failed because WorldGenerator places some patch tiles with `intra_intensity` so low that richness rounds to 0 — those tiles exist in `tiles` but are unmineable (richness 0). The smoke tests would have shown this as "alpha 0 = invisible" if alpha-fade were proportional, but the player would have struggled to ever notice. The headless test surfaced it as "first stone tile has richness 0 — can't run partial-depletion test." Worth a follow-up sweep: WorldGenerator should probably skip placing 0-richness tiles, but it's not blocking gameplay so deferred.
- **Per-axis sliding is the right primitive for "feels like Factorio" movement.** First implementation used `move_and_slide()` and just relied on Godot's physics. That doesn't see tiles. Switching to manual per-axis passability checks took ~30 lines and immediately produced the "glide along the water edge" feel. Don't fight the physics system — bypass it for tile-grid games.
- **Save-format parallel-architecture pattern keeps cleaner.** `tile_modifications` (player tile edits) and `resource_state_modifications` (mining-induced richness deltas) are independent fields with the same shape and load procedure. Adding the second one was almost zero design overhead — it follows the established model. Procgen rehydration as the canonical model continues to pay off three sessions in.
- **"Mine the deposit first" toast is enough teaching, no tutorial needed.** Reversed-design discovery was instant for the user: try to paint, see toast, RMB or mine first, retry succeeds. Discovery learning + fast feedback. No special tutorial state required.

### Migration

Save format v12 → v13. **All existing v12 saves hard-fail on load** with `OS.alert` per existing schema-bump policy. Player must delete `%APPDATA%\Godot\app_userdata\Stewardship\save_slot_1.json` and start fresh. **Dual reason** for the bump (documented in code): (1) new `resource_state_modifications` field, (2) the "no overlay on deposits" rule reversal would leave v12 saves with possibly-invalid overlay-on-deposit tiles.

### Roadmap implications

- **Drill tiers** are the natural next session. Architecture supports them: `MINING_TICK_INTERVAL` is a per-resource dict (drills could multiply); `deplete_resource(pos, amount)` already takes an amount parameter (drills extract more per tick); resource_node + richness model is already in place. Just need a new building type with extraction logic.
- **Soil exhaustion** would extend the `resource_state` model to non-ore tiles (e.g., farmable grass tiles get a "fertility" field that decreases as crops are planted/harvested, regenerates over time). Same procgen + modifications save pattern. Likely a separate session.
- **Cliffs / walls / structure-blocking** for movement: `Tile.is_passable()` is the hook. New `Tile.cliff: bool` field or new `Terrain.Base.CLIFF` enum value, override `is_passable()` accordingly. Player movement code unchanged.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** — still deferred, unchanged from worldgen-stage1.
- **Cloth chain `prefer_dir` polish** — still deferred from Session E.
- **Map polish** — zoom, markers, click-to-pan-from-minimap (carried from session-explore-map).
- **Patch-edge zero-richness tiles** — WorldGenerator places some tiles with richness rounded to 0 (very low intra-patch intensity). Not blocking gameplay but visually inconsistent with the "alpha-fade indicates depletion" rule (these tiles are alpha-0 from generation). Could fix by adding a richness floor in `_place_patch` or skipping the tile placement entirely. Defer until it bites.

---

## Exploration UI — M-key fullscreen map + minimap + fog-of-war

**Date:** 2026-05-03
**Tag:** `session-explore-map`

The navigation/awareness layer for the worldgen world. Player gains:
- A 200×200 minimap top-right showing 7×7 regions of fog-of-war state centered on player
- A fullscreen pannable map opened with M, showing the full 16×16 region world
- Three visibility states (unrevealed / fog / active) tracked per region and persisted in save
- Initial 3-radius reveal at game start so spawn vicinity has context

Foundation for Stage 2+ exploration mechanics (radar buildings, map markers, etc.).

### What shipped

**Region visibility system** (`grid_world.gd`)
- New `region_visibility: Dictionary[Vector2i, int]` — sparse per-region state (1=fog, 2=active; 0=unrevealed = no entry).
- `update_vision(player_region)` — Chebyshev radius 2 around player. Downgrades exited regions to fog, upgrades in-range to active. Returns the list of changed regions for map dirty tracking.
- `initial_reveal()` — radius 3 (7×7 = 49 regions) marked as fog at fresh game start. Spawn vicinity has navigation context on first M-press; corrected from the kickoff message's "radius 7" which would have pre-revealed 88% of the map.
- `region_of()` and `region_of_world_pos()` — static helpers to map tile / world position to region coord.
- `_in_region_bounds()` — clipping check; vision update at world corners produces 3×3 instead of 5×5.

**Vision update timing** (`main.gd`)
- Per-frame: one `Vector2i` compare (`_player_last_region` vs current). Microseconds.
- On region cross only: `update_vision()` runs — ~50 dict ops total. Microseconds.
- Cross detection works in real game loop (verified via headless probe + in-game smoke).

**Map texture caching** (`map_panel.gd`)
- Single 1024×1024 RGBA8 `Image` + `ImageTexture`. Per Q9 measurement (`ImageTexture.update()` = 7µs, `set_pixel × 1M` = 60ms), in-place GPU upload is essentially free.
- **Background incremental build**: 8 regions per frame from `tick_background_build` while not yet `_initial_built`. ~32 frames at 60fps = 0.5sec total to build the 256-region map. Per-frame cost ≈ 0.8ms. Texture progressively reveals as build advances (not snap-to-full at end).
- **Per-region dirty tracking**: vision changes / tile modifications / building placements mark specific regions dirty. On next visible frame, only dirty regions redraw, then `texture.update()` syncs GPU.

**Fullscreen M-map**
- Covers full viewport when open. No 85% panel — full coverage.
- Display scale: `max(2.5, max(viewport.x, viewport.y) * 1.5 / TEX_SIZE)` — ensures texture is meaningfully larger than viewport in BOTH axes (drag-pan visible horizontally and vertically on any aspect ratio).
- **Drag-to-pan**: hold left mouse, drag to scroll. Texture origin clamped to keep map covering viewport — no off-edge black void during pan.
- **Re-center on player at every M-open**. Pan during one session, close M, reopen → texture re-centers on current player position.
- **Black underlay across full viewport** before drawing texture — prevents world bleed-through where Control area isn't covered by texture (the bug the first smoke caught).
- Three visibility states render correctly: black for unrevealed regions, color × `FOG_DIMMING` (0.45) for fog (preserves color identity for ore-type recognition), full color for active.
- Buildings rendered as bright orange markers on top of underlying tile color.
- Player position marker (yellow dot, black outline, radius 5px) drawn on top of texture each frame; reflects current world position regardless of pan offset.

**Minimap** (`minimap.gd`)
- 224×224 px top-right (margin: 20px right, 10px top — 6px gap from info panel).
- Shows 7×7 regions = 224 tiles centered on player (1:1 px/tile, no filtering blur).
- **Samples the main map's cached texture** via `draw_texture_rect_region` — zero duplicate render work; reuses the main map's incremental dirty tracking.
- Player marker (yellow dot, 3px) at minimap center.
- **Hidden when M-map or inventory grid is open** (polled per frame in main.gd).
- `MOUSE_FILTER_IGNORE` so cursor over the minimap area passes through to the world (player can place buildings "behind" the minimap).
- Edge-clamp behavior near world boundary: source rect extending past texture shows the texture's edge (which is unrevealed-black at init) — correct "world doesn't extend" semantic with no manual clipping needed.

**Save format v11 → v12**
- New top-level field `explored_regions: Array of [rx, ry]` — sparse list of regions ever charted (state ≥ 1).
- **Active state collapses to fog on save**; load-time vision update re-derives active state from player position. Avoids "saved active but loaded somewhere else" inconsistency. Single source of truth: player position → active state.
- v11 saves hard-fail with `OS.alert` per existing schema-bump policy.

**Modal coordination**
- M-key: opens / closes map panel; ESC also closes.
- World inputs (placement, hotbar, inspect, save, etc.) suspended while map open (matches inventory grid pattern).
- Player movement frozen while map open (`player.gd` gates on `map_panel.is_open() OR inventory_grid.is_open()`).
- Drag-pan only fires inside the map panel (via `_gui_input` while open).

**Tests**: 16/16 passing
- **NEW** `test_region_visibility` — initial reveal (49 fog), vision update (25 active + 24 fog), region cross (returns changed list), boundary clipping at world corner (3×3 = 9), no out-of-bounds tracking, `region_of_world_pos` arithmetic correctness
- **UPDATED** `test_save_load_roundtrip` for v12 — explored_regions persist as fog, post-load vision update re-derives 25 active regions

### Decisions

- **Three-state visibility tracked as a single int dict** with state collapse on save (active→fog). Two-bool variants would have required keeping two flags consistent; single int with three states naturally encodes the "active implies revealed" invariant. State 2 (active) is runtime-derived from player position — no risk of stale active-state-without-player.
- **Vision radius = 2 (5×5 active area)**. Matches Factorio's player vision granularity. Cheap to compute, gives a small "currently visible" footprint distinct from the larger "ever explored" history.
- **Initial reveal radius = 3 (7×7 = 49 regions = 19% of map)**. The kickoff message said radius 7 = 15×15 = 88% of map; corrected during design pass after recognizing this would eliminate the exploration loop. Spawn vicinity stays revealed; rest of world is discovery.
- **Region cross detected by `Vector2i` compare**, not per-frame recomputation. One compare per frame; vision math runs only on the rare frame the player crosses a 32-tile region boundary.
- **Map texture rebuild via per-region dirty tracking** (not full-rebuild on dirty). Q9 measurement showed full 1M-pixel rebuild is ~60ms (perceptible single-frame hitch); per-region rebuild is ~0.1ms each, so 5-10 region updates on a cross take 1ms total. Imperceptible.
- **Background incremental build** (8 regions/frame from game start). Eliminates the 30-60ms first-M-press hitch by spreading build across ~32 frames before the player thinks to open the map. Makes "M opens instantly" the felt UX.
- **`ImageTexture.update()` for incremental GPU upload**, not `create_from_image` per change. Q9 measured both at 7µs / 13µs — both effectively free. Used `update()` for clarity (in-place semantic).
- **Fullscreen M-map (not 85% panel) per user revision**. Originally specced as centered 85% panel; user revised mid-session to "covers whole screen" with drag-pan. Required adding pan state + clamping + black underlay (the world-bleed-through bug surfaced at first smoke).
- **Minimap shares the main map texture, not independent rendering**. `draw_texture_rect_region` samples a 7×7-region window of the cached image. Zero duplicate render work; minimap inherits the main map's dirty tracking automatically.
- **Minimap visibility hidden when fullscreen modals open** (M-map or inventory grid). Reduces visual noise; M-map is redundant with minimap (same data at higher zoom).
- **Cellular noise still deferred** (carried from worldgen-stage1) — not relevant to this session.

### Lessons

- **Q9 measurement before locking design saved a wrong architecture.** Pre-measurement, I'd budgeted 200-500ms for full rebuilds and was leaning toward complex partial-rebuild schemes. Empirical probe showed `set_pixel × 1M` is 60ms (~5x faster than estimate) and `ImageTexture.update()` is 7µs (effectively free). Per-region rebuild + in-place GPU upload became trivially cheap; no exotic architecture needed. Always measure before designing-around-cost.
- **Mid-session scope additions need explicit gating.** User added two scope items mid-session (fullscreen + drag-pan, then minimap). Both got design-passes and pause points before implementation. The "fullscreen + pan" addition broke the original 85%-centered design and surfaced the world-bleed-through bug at smoke; the design-pass-first protocol caught it before it shipped.
- **Anchor coords on Control nodes are easy to get wrong.** First minimap implementation set anchors to top-right (anchor_left=1.0, anchor_right=1.0) intending "stick to right edge," then drew at viewport-relative coords — Control's local coord system has origin at the right edge, so viewport coord 1676 added to right-edge origin = drawn far off-screen. Lesson: when a Control draws using viewport-absolute coords, anchor it to FILL the viewport (anchors 0..1) so local coord system matches viewport. Saved by the smoke test catching it immediately.
- **The "first M-press" UX is dominated by hidden background build cost.** With background build at 8 regions/frame from game start, by the time a player walks around for a few seconds and reaches for M, the map is fully built. M opens instantly. Without this, M would have a visible 30-60ms hitch. The lesson is: anything that's "expensive but bounded" + "user will eventually do it" can be backgrounded into the dead time before the user asks.
- **Two-version-axes pattern (save_version + worldgen_version) extended naturally.** Worldgen Stage 1 introduced this for procgen rehydration; the v12 bump for explored_regions only needed `SAVE_VERSION`, not `WorldGenerator.VERSION`. The split was right — independent axes evolve at independent cadences.
- **`draw_texture_rect_region` edge-clamp behavior is the right default for "sample a window of a finite source."** No manual clipping needed — the texture's pre-init black fill becomes the "out of world" appearance automatically.
- **Pan-clamping at world edges felt right immediately.** Without clamping, dragging past the map edge would expose black void. With clamping, the map "stops" at world boundary — natural and obvious. Cheap rule (~10 lines).
- **Re-center on M-open, NOT continuous player-following.** Player can pan to look at distant ore patches, then close M to actually go there. Re-center on next open re-anchors them. Continuous following would prevent intentional pan-away.

### Migration

Save format v11 → v12. **All existing v11 saves hard-fail on load** with `OS.alert` per the existing schema-bump policy. Player must delete `%APPDATA%\Godot\app_userdata\Stewardship\save_slot_1.json` and start fresh. The new world generates with a random seed at fresh start (worldgen Stage 1 behavior unchanged).

### Roadmap implications

- **Map polish** (next likely session): zoom on map (mouse wheel), markers/waypoints, perhaps a more responsive minimap interaction model (click-to-pan-main-map, etc.). Out of scope for this session.
- **Radar buildings** (Stage 2 of exploration): a building that extends `region_visibility` for nearby regions even when player isn't there. Architecture supports this trivially — just call `region_visibility[r] = 1` for the radar's covered regions. Hook would be Buildings.tick_one for the radar type.
- **Worldgen Stages 2-5** (chunked, biomes, mining, etc.): unaffected by this session. Map architecture handles arbitrary `region_visibility` content; whatever future stages put in regions just renders.

### Known follow-ups (carried forward)

- **Cellular noise revisit at sprite migration** (carried from worldgen-stage1).
- **Cloth chain `prefer_dir` polish** (carried from Session E).
- **Sprite migration** — long-term replacement for placeholder rect/circle rendering.

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
