# Stewardship — design notes

Forward-looking design plans that aren't yet implemented. Each entry should answer: what's the goal, what hooks exist today, what blocks it, what's the target session.

Move entries to `CHANGELOG.md` (or just delete them) once the corresponding work ships.

---

## Click-handling duplication (BuildingPanel ↔ inventory_grid)

**Status:** still 2 implementations after session-building-ui-3. Audit verified at session 3 design pass: ChestPanel overrides `_gui_input` for hit-test routing only; calls `_handle_player_slot_click` from BuildingPanel base unchanged. No third copy exists.

**Why still NOT extracted:**
- True duplication count is 2, hasn't grown since Session 1. The 14 BuildingPanel subclasses (after Sessions 1+2+3) all *inherit* one implementation; they don't duplicate it.
- Extracting now produces a 25-line static helper that saves ~50 lines. Modest. Risk: an abstraction that doesn't fit a future divergence (e.g., right-click half-stack might want different player-slot vs building-slot behavior).

**Refined trigger criteria** (replacing the original "4+ consumers" wording):
- **Third *implementation* of the click logic appears** (not a subclass — a genuine new copy of pick/place/combine/swap).
- **New behavior added that requires both call sites to be updated identically** (e.g., right-click half-stack, shift-click bulk transfer in modals).
- **Player-slot click logic genuinely diverges between modals** (one modal needs different semantics, current logic is identical).

When any one fires: extract to `CursorStack.click_swap(slot, cursor) -> void` or `SlotWidget.handle_click(slot_provider, cursor)`.

---

## Building Interaction UI — multi-session arc (Sessions 1+2+3 shipped)

**Status:** **Sessions 1 + 2 + 3 SHIPPED.** Foundation infrastructure + 14 specialized UIs (smelter, drill, chest, mill, oven, proofer, packager, mixer, loom, tailor, briquetter, sugar press, retter, yeast culture). Session 4 adds extraction-tier UIs (harvester, planters).

**ProcessorPanel reuse milestone:** 10 consumers post-Session-3 (Mill, Oven, Proofer, Packager, Loom, Tailor, Briquetter, Sugar Press, Retter, Yeast Culture). All extend with no overrides — pure 5-line subclass files. ~280 line savings vs naive plan (specialized panels per building). See PROJECT_LOG session-building-ui-3 for the architectural-investment-pays-off log.

**Shared `BuildingPanel.draw_fluid_indicator`:** 3 consumers (Mixer, Retter, Yeast Culture). Single source of truth for "how a fluid input looks."

### What's shipped (sessions 1+2)

**Foundation (session-building-ui-1):**
- `scripts/ui/cursor_stack.gd` — shared cursor object, persists across modals, serializes to `player_progression["cursor"]`.
- `scripts/ui/slot_widget.gd` — extracted slot rendering (used by inventory_grid + every building panel). Now also hosts the `chest_bag_to_slot_views` adapter (moved from inventory_grid at session 2).
- `scripts/ui/building_panel.gd` — base class with modal lifecycle, drag-drop, kind-validation (input/output/fuel/output_multi/chest_bag/fluid_indicator), lossy fuel take-back, player inventory render at bottom. `_top_area_height()` virtual hook for subclasses needing taller panels.
- `Buildings.slot_layout_for(t)` + `has_interaction_ui(t)` data registry.
- Hotbar `has_selection()` / `clear_selection()` + neutral visual.
- `main.gd` Esc priority chain + click-to-open dispatch + Manhattan-1 adjacency check + cursor save/load.
- Multi-tile hover rect.

**Session 1 panels:**
- `scripts/ui/smelter_panel.gd` — flow layout with progress bar, fuel slot.
- `scripts/ui/drill_panel.gd` — coverage 2×2, multi-output sub-slots, fuel slot.

**Session 2 panels:**
- `scripts/ui/processor_panel.gd` — intermediate base for Mill/Proofer/Packager/Oven (~10 lines each as subclass).
- `scripts/ui/chest_panel.gd` — bulk-storage 6×4 grid + capacity header. Replaces old inventory_grid paired-view (removed ~150 lines from inventory_grid.gd).
- `scripts/ui/mill_panel.gd` / `proofer_panel.gd` / `packager_panel.gd` / `oven_panel.gd` — each `extends ProcessorPanel` with no overrides. Slot_layout in Buildings.DATA drives rendering.
- `scripts/ui/mixer_panel.gd` — extends BuildingPanel directly; 2 solid inputs side-by-side + fluid indicator + output.
- E-key unified: opens building UI for any adjacent building with `has_interaction_ui`; falls back to drain for legacy harvester.

**Tests: 22/22 passing.** New tests cover: cursor stack, slot_layout shapes, hotbar selection, click resolution, drag-drop semantics, ChestPanel pick/drop, multi-input dispatch (oven), mixer fluid indicator, E-key adjacency scan.

### Session 4 (next): Extraction tier

**Specialized UIs to add:**
- Harvester — 1 input slot (auto-populated from adjacent crop tile? Or just shows what was harvested?) + N output (multi-item buffer like drill). Depends on architecture decisions during the session.
- Planter (Wheat/Sugar Beet/Flax variants) — single seed slot? Or no slot at all (seeds are in inventory only)? Planter may not need a panel; if it doesn't have buffers, the existing Q-inspect read-only view is enough.
- **Thresher** (carry from sessions 2-3 oversight) — basic Processor (wheat → grain + straw). Likely just 5-line `extends ProcessorPanel` like other simple processors. Small add-on this session.

**Architectural concern:** Planter and Harvester are extraction-tier; they don't have the input-buffer / output-buffer / fuel shape that Processor-derived buildings share. If their UIs don't fit the BuildingPanel mold cleanly, that's a signal that BuildingPanel is over-fitted to processors. Plan to revisit the slot_layout schema if/when extraction UIs feel forced.

### Cross-cutting follow-ups (across all 4 sessions)

- **Right-click half-stack** in building slots — defer to building UI v2 polish.
- **Animations / transitions** for modal open/close — defer.
- **Drag-and-drop visual** — currently click-to-pickup, click-to-place. Real drag (button-down + move + button-up) may feel more natural; defer until playtest confirms the click pattern is unwieldy.

### Hooks shipped this arc so far (sessions 1-3)

- `Buildings.slot_layout_for(t)` + `has_interaction_ui(t)` — data registry.
- `BuildingPanel` base class with modal lifecycle + drag-drop + kind-validation + `draw_fluid_indicator` helper.
- `ProcessorPanel` intermediate class (input → progress → output ± fuel ± fluid_indicator). 10 consumers.
- `CursorStack` shared object (one instance, all modals).
- `SlotWidget` static helper for uniform slot rendering + chest-bag adapter.
- Esc priority chain in main.gd — extending for new panels is mechanical.
- E-key unified dispatch — opens building UI for any adjacent building with `has_interaction_ui`.

---

## Tile passability system (post-mining-manual)

**Status:** shipped at `session-mining-manual`. `Tile.is_passable() -> bool` is the generic blocker check. Today only water blocks; player movement uses per-axis sliding via `Player._move_with_passability(delta)`.

**Foundation for future blocker types:**
- **Cliffs / elevation barriers** — a future `Tile.cliff: bool` field or a `Terrain.Base.CLIFF` enum value with `is_passable() = false`. Player can't walk off a cliff edge; future ladder/ramp buildings allow traversal.
- **Walls** — placeable building or terrain that blocks movement. `tile.has_wall: bool` field, `is_passable()` returns false. Player walks around. Doors are walls with a `passable_when_open` flag.
- **Structures** — large buildings could mark their footprint cells as impassable so player walks around them rather than through. Today buildings don't block movement (player walks through them visually, which is a small UX wart).

**Why generic `is_passable()` over specific `is_water()`:**
- Future blocker types add their own logic to `Tile.is_passable()` rather than touching player movement code
- Per-axis sliding logic in `Player._move_with_passability` doesn't care WHY a tile blocks; works for any combination of blockers
- New blocker = override one method, no other code changes needed

**Don't pre-build:**
- Wall buildings, cliff terrain, ladder mechanics — wait for them to be needed in actual gameplay before scaffolding
- Save format implications — adding fields to Tile is a schema bump; do it when the feature lands, not pre-emptively

---

## Map polish (post-explore-map session)

**Status:** the M-key fullscreen map + minimap shipped at `session-explore-map`. Three-state visibility (unrevealed / fog / active), drag-pan, region-level fog tracking, save persistence — all live. What remains is polish.

**Deferred items captured during the session:**

- **Mouse-wheel zoom on M-map.** Currently fixed at the auto-computed display scale. Wheel could zoom in (smaller area, more detail) or out (whole world more visible). Pan-clamp adjusts naturally. ~30 min of work.
- **Map markers / waypoints.** Right-click on map to drop a marker; visible on M-map and minimap. Persists in save. Useful when the player has scattered outposts to remember. v2 feature; no architectural blocker.
- **Click-to-pan-from-minimap.** Right now minimap is `MOUSE_FILTER_IGNORE` (passive). Could open M-map at clicked position. Mild scope creep; defer until "I want to see X area" becomes a real friction.
- **Facing-direction arrow on player marker.** Currently a dot. Player has no `facing` state today; would need to derive from velocity or track explicitly. Defer until needed.
- **Fog-vs-active visual distinction beyond brightness.** 0.45 brightness multiplier reads but is subtle. Could add a desaturation overlay or animated edge for clearer "this is current vision." Wait for playtest feedback before tuning.

**Radar buildings (Stage 2 of exploration):** the architecture supports them trivially. A radar building's tick (or place-time) hook would call `world.region_visibility[r] = 1` for the regions it covers. Visual would be a different state (maybe value = 3 = "remote-revealed") if we want to distinguish player-explored from radar-revealed. Out of scope for Stage 1; designed for when bigger maps make this gameplay-meaningful.

---

## Tooling: godot-mcp (installed, capability honestly documented)

- **Repo:** [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp), addon version **2.17.0**.
- **Status:** installed and connected. Capabilities and limitations characterized via direct verification. **Smaller win than the original install plan claimed; documentation below is the truthful version.**

### What MCP **CAN** do (confirmed by verification)

| Capability | Tool / action | Notes |
|---|---|---|
| Capture a screenshot of the running game | `editor screenshot_game` | **The only confirmed live-state path.** Returns a real PNG of the running Godot window — visible HUD, real-time tick count, current player position, building visuals. Solves the original "I can't see the screen" debugging problem at the visual level. |
| Run / stop the project | `editor run`, `editor stop` | Launches the game from the editor and reports `is_playing` via `editor get_state`. |
| Read the editor's loaded scene tree | `node find`, `node get_properties` | Returns built-in Godot properties (position, scale, modulate, etc.) and `@export`-annotated script vars **at their authored scene-file default values** — see caveat below. |
| Look up Godot API documentation | `godot_docs` | Search/lookup against the engine's docs; useful for "how does Camera2D.zoom work" type queries. |
| Control the editor's 2D viewport | `editor set_viewport_2d` | Pan/zoom the editor view (not the running game). |
| Editor-side selection / scene editing | `node create / update / delete / reparent`, `scene open / save / create` | Authoring tools — useful for tooling/automation, irrelevant to live-state debugging. |

### What MCP **CANNOT** do (confirmed by failed verification attempts)

| Capability we wanted | Tool that should have worked | What actually happened |
|---|---|---|
| Read live game state (variables in the running game process) | `node get_properties` on `/root/Main` etc. | **Returns the editor's static scene tree, not the running game's runtime state.** Player.position read as `(64, 64)` (scene-file default) while the live game had the player at world `(64, 416)`. |
| Read custom GDScript `var` declarations | `node get_properties` | Plain `var` is invisible. Only `@export`-annotated vars surface — and even then, only their **scene-file default values**, not live runtime values. |
| Read Dictionary-typed game state | n/a | `GridWorld.buildings` (the master dict of Building instances by anchor) is a custom var holding RefCounted instances. Not readable through any MCP tool. |
| Capture game stdout | `editor get_log_messages` (with `source=game`) | Returned `No log messages` even when game was running. Stdout-print-then-read fallback is unreliable. |
| Inject input into the running game | `input sequence` | The tool reports "executed" but the action does not reach the running game process — `_demo_origin` and `_demo_spawned` did not change after `debug_spawn_demo` injection while the game was running. Action injection appears to target the editor's input map, not the live game. |

### Critical caveat — read this before assuming MCP can debug your game

**MCP reads the editor's static scene tree, NOT the running game process.** When `editor.run` launches the game, it forks a separate process; the editor's scene tree continues to reflect the **authored `.tscn` file content** — built-in property defaults, exported var defaults, the static layout. Anything that changes at runtime (player movement, F11 demo state, Building dict contents, tick count) is invisible to `node get_properties`.

Adding `@export` to a script var **does NOT make its live runtime value readable**. It only makes the var visible to the inspector / scene serializer. MCP reads the scene-file default, not the running value. We tested this directly: `@export var _demo_origin` returned `(0, 0)` (its initial default) regardless of F11 state in the live game.

**The single confirmed live-state path is `editor screenshot_game`.** Everything else is editor-scene introspection at the authored level.

### Verification scope (revised after honest characterization)

The original four-check protocol assumed MCP could read live game state. It cannot. Use this **two-check** smoke test instead when re-verifying a fresh install:

1. **`editor get_state` reports `is_playing: true` after `editor run`.** Confirms editor↔game launch control works.
2. **`editor screenshot_game` returns a valid PNG of the running game window.** Confirms the live-state path. Visual content (player position, building counts, HUD text) reads correctly from the screenshot.

That's the verifiable scope. Everything beyond that — reading state programmatically, injecting input, capturing stdout — is **either limited to editor-scene defaults or doesn't work at all** in the current install.

### Workarounds and future work

- **Reading live state when needed:** use `editor screenshot_game` and read the HUD strip visually. The HUD already shows player tile, hover tile, building count, current tick, holding-item — most of what's needed for "where am I in the world."
- **Reading per-Building state (in_buffer, out_buffer, etc.):** **manual Q-inspect with eyes on screen.** No MCP path. Don't build a workflow that assumes MCP can answer this.
- **Future Option (deferred indefinitely): debug-bridge autoload.** The addon already adds an `MCPGameBridge` autoload that runs in the game. In principle a custom bridge layer could expose live state as JSON via a new MCP command. **Real work, not free.** Defer until the screenshot-only path proves insufficient at least 3 times — and even then, weigh against simpler answers like "instrument the game with on-screen debug overlays" or "write programmatic E2E tests via PlayGodot from the Randroids-Dojo skill pack."

### Install footprint

- `claude mcp add godot-mcp -- npx @satelliteoflove/godot-mcp` registers the server (modifies `~/.claude.json` project block).
- `addons/godot_mcp/` directory in the project root (the addon files).
- `project.godot` has `[editor_plugins] enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")`, an `MCPGameBridge` autoload entry, and a `[godot_mcp]` config section (port 6550, bind_mode=0). These were auto-added when the plugin first loaded; not corruption, not to be reverted.
- 8 tests pass post-install. Plugin GDScript is well-isolated.

### Known gotchas (verified)

- **Plugin only binds the WebSocket when the *editor* is running, not the game.** Launching with just `Godot --path X` opens the game (not the editor); the WebSocket server stays unbound. Use `Godot --editor --path X` to launch the editor; `_enter_tree()` in `plugin.gd` runs only in editor context.
- **Stale game processes block MCP connection.** During verification, an orphan game process from an earlier run held the editor's earlier WebSocket connection in a stuck state; killing the orphan unblocked MCP. If `editor get_state` returns "Not connected" but `netstat` shows port 6550 LISTENING, check for stale Godot processes via `tasklist` and kill them.
- **Headless import logs `[godot-mcp] Plugin disabled` at shutdown** — graceful shutdown message, not an error.

---

## Camera zoom — shipped + polished

**Status:** mouse-wheel zoom + smooth-lerp shipped at `session-camera-zoom`. The stash's displacement bug was diagnosed (sub-pixel jitter from non-integer zoom × fractional camera position) and fixed via project-level pixel-snap rendering. The hover-outline-fades-at-low-zoom limitation that was deferred from that session was closed at `session-polish-1` via `screen_px(2.0)` floor. **No active limitations.**

### What `screen_px()` is used for now

`grid_world.gd::screen_px(world_px)` returns `max(world_px, world_px / camera.zoom.x)`. At zoom ≥ 1, it returns `world_px` (the floor wins); at zoom < 1, it returns `world_px / zoom` so the rendered output is at least `world_px` screen pixels.

**Used selectively:**
- **Hover rect outline** (line 427-ish in `_draw`) — vanishing-at-low-zoom was the worse failure mode than ~0.15 screen-pixel overshoot at min zoom.

**NOT used for:**
- Grid lines, building borders, port dots, direction arrow strokes — these stay in world units to match tile boundaries exactly. Overshoot on these (especially port dots, where the radius is small) was visible at low zoom and looked bad. Per-call dimensional choice.

The trade-off is acknowledged: at zoom 0.85 (min), the hover outline overshoots the tile by ~0.18 world units / ~0.15 screen pixels per side. Under perception threshold; visibility win is the priority for hover specifically.

### Long-term solution: sprite migration

The wider "outlines on placeholder art" question is solved by **moving from colored rectangles to actual sprites** — sprite outlines are inside the sprite texture, not draw_rect calls, so they don't have the screen/world dimension question at all. Sprite migration is its own future session.

---

## Cloth chain prefer_dir — shipped, save migration recorded

**Status:** shipped at `session-polish-1`. The Session E follow-up about no-prefer_dir on cloth recipes is closed. Retter/Loom/Tailor now use canonical-east ports with rotation; the F11 demo rotates them south to match the chain's vertical layout.

### Save migration notes (informational, no version bump)

Save schema stayed at v10 — no structural change. But any save with cloth processors placed before `session-polish-1` will need each processor rotated south manually. Defensive `.get("dir", 0)` reads everywhere mean the save loads cleanly; the chain just doesn't produce until rotation is applied.

**The migration steps:**
1. Hover the Retter with empty hand. Press R three times until toast says "Retter rotated to S".
2. Repeat for Loom and Tailor.
3. Chain resumes within ~30 seconds.

Alternative: delete the save (`%APPDATA%\Godot\app_userdata\Stewardship\save_slot_1.json`) and re-spawn with F11 — the demo now spawns them rotated.

### Lesson recorded

R-key rotates a placed building IN PLACE when hand is empty (`main.gd::167-171`), gated on `Buildings.supports_direction(t)`. Discovered during the polish session by reading the actual code rather than assuming "rotation only works during placement preview." First instinct was to write migration docs as "remove + replace each cloth processor" — much worse UX than rotating in place. **Lesson: read the code before writing migration docs.**

---

## Resource harvesting + smelting roadmap (manual + drill + smelter shipped; lumber-camp + kilns next)

**Status update:**
- **Manual tier shipped** for both ore and trees.
  - Ore mining at `session-mining-manual`: walk adjacent → hold Space → drain richness → tile reverts at 0. 5 ore items.
  - Tree chopping at `session-tree-harvest`: walk adjacent → hold Space → 2-second chop → wood (1-4 yield) → 5-minute regrowth.
- **Burner mining drill shipped** at `session-mining-drill`. 2×2 building, fed fuel from adjacent belt/chest, produces ore at 0.5/sec into prefer_dir output port. Highest-richness-wins deposit selection across the 4-tile footprint. Generic `Burner` module ready for smelter / kiln reuse — **validated this session.**
- **Burner smelter shipped** at `session-smelter`. 2×2 building, fed iron or copper ore from W edge + fuel from S edge, produces ingots out E edge at 0.5/sec. **Multi-recipe runtime selection** via FIFO over input buffer (`_maybe_select_recipe`); recipe switches automatically when input changes. Burner module reusability validated: ~13–15 fuel lines vs drill's ~11, parity.
- Save v14 persists per-tile state (richness, regrowth_remaining) via generic Dict-shape `resource_state_modifications`. Drill + smelter state lives on `Building.state` (no schema change at either session).

**What remains: lumber-camp tier + ore→ingot consumers + clay/stone processing.**

**Lumber camp (likely next-after-UI):** placeable building that automates tree chopping. Calls `GridWorld.chop_tree(pos)` on a schedule, reads `GridWorld.wood_yield_for_tree(pos)` for output count. Could be Burner-fed for speed or passive (design TBD).

**Charcoal Kiln (next likely burner consumer):** WOOD → CHARCOAL. CHARCOAL becomes a higher-tier fuel (~8 units?) — single FUEL_VALUES dict entry. Validates Burner module's third consumer.

**Brick Kiln:** CLAY → BRICK (building material). Same shape as Charcoal Kiln; different recipe.

**Stone Crusher:** RAW_STONE → STONE_BLOCK. Stone overlay becomes a consumable (no longer free-paint).

**Tier-2 drill / electric smelter:** deferred until electricity. Architecturally trivial — speed multiplier on `time_ticks` / `DRILL_TICKS_PER_ORE`.

Manual harvest stays as the fallback / early-game tool. Drill is unambiguously slower than manual for stone/coal/clay (0.5 vs 2/sec) but unattended — a *bank* of drills is a different game. Smelter at 1:1 with drill output makes the "1 drill + 1 smelter" the basic ore-tier unit.

**Hooks already in place (as of session-smelter):**

- `ResourceNodes.is_renewable(t)` distinguishes ore from trees in behavior.
- `GridWorld.deplete_resource(pos, amount)` — canonical ore extraction primitive (used by manual mining AND mining drill).
- `GridWorld.chop_tree(pos)` — canonical tree chop primitive (single-shot, starts regrowth).
- `GridWorld.wood_yield_for_tree(pos)` — deterministic yield helper.
- `resource_state[pos]` — per-tile dict; `{richness, original_richness}` for ore, `{regrowth_remaining}` for chopped trees, future fields for future types.
- Save format v14 — `resource_state_modifications` is generic Dict; future state types add keys without schema bump.
- `Burner` static helpers (`scripts/world/burner.gd`) — fuel buffer, fuel pull from belt/chest, per-tick consumption. **Validated reusable at session-smelter** (~13–15 fuel lines in smelter vs drill's ~11). Charcoal Kiln + Brick Kiln are next consumers; will reuse without extension.
- Building-placement-cancels-regrowth (`GridWorld.place_building`) — generic to all building types. Future 2×2+ buildings inherit it for free.
- **Multi-recipe Processor pattern** (`smelter.gd::_maybe_select_recipe`): pre-tick recipe selection wrapping `Processor` helpers. Foundation for any future building that needs runtime recipe switching (configurable Oven via UI, refinery, etc.). Smelter calls `Processor._try_pull_inputs / _has_all_inputs / _has_room_for_outputs / _consume_inputs / _emit_outputs / _try_push_outputs` directly — Processor's helpers double as building blocks for non-Processor.tick state machines.

**Stage 5 (processing chains)** — still the plan:
- `stone_crusher`: `raw_stone × N → stone_block × 1` (the existing stone overlay becomes a consumable item).
- `smelter`: `iron_ore + fuel_briquette → iron_ingot`.
- `sawmill`: `wood × N → planks × 1`.
- `charcoal_kiln`: `wood → charcoal` (alternative fuel to coal/briquettes).
- `brick_kiln`: `clay → brick` (building material).

**Stone overlay becomes a consumable** at processing-chain ship: hotbar's "Stone" slot stops being a free brush. Painting consumes 1 `stone_block` per tile. Belts, harvesters, mills, etc. that currently require Stone overlay continue to work — the overlay still exists, you just have to manufacture it now.

## Sapling visualization during tree regrowth (deferred polish)

**Status:** at `session-tree-harvest`, chopped tile regrowth uses empty-grass rendering during the 5-minute timer. Player can't visually distinguish a regrowing tile from default grass — they only know via Q-inspect or by waiting and watching.

**Polish path:** small sapling sprite drawn on regrowing tiles, growing in size toward mature as the timer ticks down. Cheap render (one circle that scales 0.0 → 0.32 over 300 sec). ~20 lines of code in `_draw_resource` or a new `_draw_regrowth`. Defer until "I can't tell which tiles I chopped" becomes a real complaint in playtest.

**Design sketch:**

1. **World-gen extension.** `GridWorld.generate_default_world()` (or its successor) places resource_node deposits in irregular clusters far from spawn — stone deposits in rocky regions, wood groves at forest edges, ore in deeper veins. Deterministic shapes, like the Session B water lake.
2. **Mining buildings.** Two new placeable types:
   - **Quarry:** placed adjacent to stone/ore deposits. Periodically extracts `raw_stone` / `raw_ore` items into its output buffer. Like Harvester for crops, but consumes the deposit (depletion is the soft-threat — eventually a deposit runs dry).
   - **Lumber Camp:** same idea for wood groves → `raw_wood`.
3. **Processing.** New Processor recipes:
   - `stone_crusher`: `raw_stone × N` → `stone_block × 1` (the existing stone overlay is renamed `STONE_BLOCK_TILE` or similar; the consumable item is `stone_block`).
   - `smelter`: `raw_ore + fuel_briquette` → `metal_ingot`.
   - `sawmill`: `raw_wood` → `planks`.
4. **Stone overlay becomes a consumable.** The hotbar's "Stone" slot stops being a free brush. Painting consumes 1 `stone_block` from player inventory per tile. Belts, harvesters, mills, etc. that currently require Stone overlay continue to work — the overlay still exists, you just have to manufacture it now.
5. **Player inventory pressure.** This is the gating effect — early game you're working with what you can carry from a quarry, late game you have a stone-block stockpile and freely build big factories.

**What this unlocks:**

- A real mid-game economy (not just "I can paint anything for free").
- A stewardship-themed soft-threat: deposits deplete; over-mining a region forces you to relocate quarries.
- A reason to build long supply lines back to your factory hub (raw materials don't spawn where you want to build).

**Migration concerns:**

- Existing v8 saves with the current "free stone" model will need a one-time conversion when this lands: scan tiles, count stone overlays, credit player inventory with that many stone_blocks. Document in save migration log.
- Hotbar layout will shift: Stone moves from Terrain category to a new Materials category alongside future planks/ingots.

**Don't pre-build:**

- The Quarry / Sawmill / Smelter aren't generic Processors quite — they consume a deposit (resource_node) on the tile they sit on or adjacent to, not items from a belt. Will likely need a separate `Extractor` base class. Do not generalize until the second extractor type lands.

**Until then:**

- Stone is free in the hotbar. Don't gate Sessions C-F on this.
- `resource_node` field round-trips through saves but is otherwise inert.
- Remove the F12 yeast spawn debug at the same time as wiring real ore→ingot processing — both are "scaffold I owe the codebase."

---

## Building size tiers

The game has a deliberate vocabulary of footprint sizes. Each tier corresponds to a category of equipment with consistent visual / spatial weight. Keeping tiers stable makes layouts feel intentional.

| Tier | Footprint | Examples (current and planned) |
|---|---|---|
| **1×1** | Tools, throughput devices, simple processes | Planter, Harvester, Belt, Pipe, Pump, Mill, Thresher, Briquetter, Sugar Press, Yeast Culture, Chest |
| **2×2** | Substantial machinery, mid-tier processing | Mixer, Oven, Proofer, Packager (Session D scope) |
| **3×3** | Major industrial equipment, late-game specialty | (planned) Smelter, Refinery, Silo, Brewery; possible Oven upgrade if 2×2 feels too small after playtest |
| **4×4+** | Endgame megabuildings (reactors, mass storage, factories-in-a-box) | Deferred indefinitely; not designed yet |

### Sizes are data

Footprint lives in `Buildings.DATA[type].footprint`. Changing a building's tier is a one-line edit; the multi-tile infrastructure (edge_cells, placement validation, rendering, occupied map) handles any size uniformly. **Oven starts as 2×2 in Session D. If 2×2 feels too small after playtest, upgrade to 3×3 in a future session by editing `Buildings.DATA[OVEN].footprint`.** Save schema bump on upgrade because existing saves' OVEN entries claim a different footprint.

### Open questions for 3×3 (and anything larger)

A 2×2 building has 2 edge cells per side. `prefer_dir: Belt.DIR_E` for a 2×2 is unambiguous-ish: scan both east-edge cells, push to first that accepts.

A 3×3 has **3** edge cells per side. `prefer_dir: Belt.DIR_E` is ambiguous — which east cell does the recipe mean? Three reasonable answers, each with tradeoffs:

1. **Any cell, first match.** Recipe says "east edge"; Processor scans (X+3, Y), (X+3, Y+1), (X+3, Y+2) in order; pushes/pulls at first that accepts. Simplest, current behavior generalized. Caveat: ordering is implicit (which cell is "first"?); two outputs both saying "east" might collide on the same belt unintentionally.

2. **Specific cell via offset.** Recipe declares both edge AND offset along that edge: `[item, count, dir, offset]`. E.g. "east edge, middle cell" = `[BREAD, 1, DIR_E, 1]`. Most explicit; requires recipe authors to think about port placement. Best for visual clarity (large machines have specific input/output points) but more verbose.

3. **All cells must accept.** Output items duplicate to every edge cell on that edge — recipe produces 1 bread, but *all 3 east-edge cells* receive it (as 3 copies, or block until all 3 can accept). Mostly nonsensical for current items; might make sense for fluid recipes where "fluid leaves on east edge" = pipe at any east cell suffices. Probably not the right answer for 3×3 solid outputs.

**Recommended for when 3×3 lands:** option 2 (specific cell via offset). Add the `offset` element only when the recipe actually needs it; default to "first match" (option 1) when omitted. Backwards-compatible with 2×2 recipes that don't specify an offset.

When 3×3 ships, also consider:
- Whether `Buildings.edge_cells` should support an optional offset parameter, returning a single cell instead of all edge cells.
- How the info panel displays per-port positions ("Bread → E[1]" vs "Bread → E").
- Visual tells on the building itself — do players SEE that fuel must enter via the southwest tile of a 3×3 Smelter, or do they have to learn it from the recipe?

These are real design questions that 2×2 lets us defer. Don't try to solve them in Session D; capture the tradeoffs here so future-me has the framing pre-loaded.
