# Stewardship — design notes

Forward-looking design plans that aren't yet implemented. Each entry should answer: what's the goal, what hooks exist today, what blocks it, what's the target session.

Move entries to `CHANGELOG.md` (or just delete them) once the corresponding work ships.

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

## Camera zoom — shipped, known limitations

**Status:** mouse-wheel zoom + smooth-lerp shipped at `session-camera-zoom`. The stash's displacement bug was diagnosed (sub-pixel jitter from non-integer zoom × fractional camera position) and fixed via project-level pixel-snap rendering. The zoom spec previously in `SESSION_E_PLAN.md` is now history; this entry replaces the stash reminder.

### Known limitation: outlines fade at extreme zoom-out

Hover indicator, grid lines, building borders, port dots, and direction arrows all use **world-unit widths** so they scale with the tile. The trade-off chosen during the session: at zoom 0.85, a 2-world-unit outline = 1.7 screen pixels (sub-pixel anti-aliased — visible but thin). At default zoom 1.5, 3 px (clear). At max zoom 6.75, 13.5 px (chunky but proportional).

The alternative was screen-fixed outline widths via a `screen_px()` helper. That made outlines overshoot small tiles at low zoom — the hover box looked larger than the tile beneath it. The "outline matches tile exactly" verification criterion took priority over "outlines stay readable at any zoom."

**Future fix option (deferred):** minimum-pixel-floor for hover outline only. Pseudocode:

```gdscript
var width: float = max(world_units, 2.0 / camera.zoom.x)  # at least 2 screen px
draw_rect(rect, color, false, width)
```

This keeps world-unit widths above default zoom (preserving exact tile alignment when zoomed in) but adds a floor at low zoom so the outline stays at least 2 screen pixels visible. Add only if it bites in playtest. ~30 minutes of work — small, scoped, easy to layer in later.

The wider concern (outlines fading on placeholder art) is solved long-term by **moving from colored rectangles to actual sprites** — sprite outlines are inside the sprite texture, not draw_line/draw_rect calls, so they don't have the screen/world dimension question. Sprite migration is its own future session.

### `screen_px()` helper kept but unused

`grid_world.gd::screen_px(world_px)` exists for future in-world overlays that genuinely need constant screen-pixel size. No current callers. Cheap to keep; removing later if dead code accumulates is trivial.

---

## Resource mining: stone / ore / wood become world-gen consumables

**Goal:** stop letting the player paint stone for free. Stone (and eventually ore, wood) become finite resources mined from world-gen deposits, processed into raw materials, and then placed.

**Target session:** G or H. Sessions C–F focus on chains and content; this is a mid-tier complexity feature that fits after the chain content is in place but before the world becomes "complete."

**Hooks already present (as of post-Session-B):**

- `Tile.resource_node: int` — every tile carries a resource-node slot. World-gen will populate it with `ResourceNodes.Type.STONE_DEPOSIT` / `ORE_DEPOSIT` / `WOOD_GROVE` (currently only `NONE` exists).
- `ResourceNodes` registry — `scripts/world/resource_nodes.gd`. Empty enum slots ready for new types.
- Save schema v8 — tile entry already includes `resource_node`. No more save bumps needed when mining lands.

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
