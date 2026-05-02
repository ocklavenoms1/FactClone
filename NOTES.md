# Stewardship — design notes

Forward-looking design plans that aren't yet implemented. Each entry should answer: what's the goal, what hooks exist today, what blocks it, what's the target session.

Move entries to `CHANGELOG.md` (or just delete them) once the corresponding work ships.

---

## Tooling: godot-mcp (install in progress, awaiting verification)

**Status as of commit installing this:** server registered + addon installed + plugin enabled, but **verification has NOT yet completed**. Verification requires a Claude Code restart so the new MCP tool schemas load. Restart, then run the four-check protocol below.

### What was installed

- **Repo:** [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp)
- **Addon version installed:** 2.17.0 (latest published to npm at install time; npm distro may lag the GitHub HEAD which was 2.18.0)
- **Why this one over Coding-Solo's:** Coding-Solo's MCP only reads stdout/stderr, not live game state. satelliteoflove's MCP installs an in-project addon (`MCPGameBridge` autoload + WebSocket server) that exposes runtime introspection — query node properties, scene tree, etc., from the running game.

### Install steps (executed)

1. **Register MCP server in Claude Code (project-local):**
   ```
   claude mcp add godot-mcp -- npx @satelliteoflove/godot-mcp
   ```
   Modifies `~/.claude.json` (project-scoped block).

2. **Install in-project addon:**
   ```
   npx -y @satelliteoflove/godot-mcp --install-addon "C:/Users/elham/facvtorio"
   ```
   Creates `addons/godot_mcp/` (command_router.gd, commands/, core/, game_bridge/, plugin.cfg, plugin.gd, ui/, websocket_server.gd).

3. **Enable plugin in `project.godot`:** added `[editor_plugins] enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")`.

4. **Plugin auto-edits on first import:** when Godot first imported the project after the plugin was enabled, the plugin auto-added an `MCPGameBridge` autoload entry plus a `[godot_mcp]` config section (defaults: bind_mode=0, port_override_enabled=false, port_override=6550). These edits are intentional and should not be reverted.

### Dependencies

- Node.js ≥20 (verified: v24.14.1 installed)
- Godot ≥4.5 (verified: 4.6.2 installed)
- No API keys, no auth tokens.

### Verification protocol (run AFTER Claude Code restart)

**The first Claude turn after restart should follow these re-orientation steps before doing anything else** (per user-specified protocol):

1. Read `SESSION_E_PLAN.md`, `PROJECT_LOG.md`, `NOTES.md` (this file).
2. Run `git status` to check for uncommitted state.
3. **Summarize back to user where things stand before acting.** This prevents fresh-Claude starting the wrong task.

**Then run the four-check verification** (per user-locked spec):

1. Have the user press F11 in a running Godot session, spawning the demo.
2. Use `mcp__godot-mcp__*` tools to read live state:
   - **(a) Where is the Flax Planter?** Should be a Building node at `cloth_o + (0, 0)` where `cloth_o = player_tile + (10, 8)` at F11 press time. Confirm via MCP node lookup.
   - **(b) What is the Retter's `Waiting for:` line?** Read the Retter Building's `state` dict, specifically `state.in_buffer` and `state.recipe_id`. Compare against the recipe's required inputs to construct the Waiting-for message that `Processor._missing_for_start()` would produce.
   - **(c) What is the player's current tile?** Read `Player.global_position`, divide by `GridWorld.TILE_SIZE` (=32), report `Vector2i`.
   - **(d) What is `_demo_origin`?** Read the value of `main.gd`'s `_demo_origin: Vector2i`. **This is the proof that today's coordinate-confusion problem is solved** — if MCP can read the F11 spawn origin without the user describing the screen, the install solved the actual problem.

If all four pass: install verified, document the working tool names + commands in this section, commit `[mcp] verification passed: 4/4 checks`. If any fail: document specifically which capability is missing, commit a partial-install note, decide whether to abandon or remediate.

### Known gotchas (so far, expand on verification)

- **Plugin auto-edits `project.godot` on first headless import.** Don't be surprised when `[autoload]`, `[editor_plugins]`, and `[godot_mcp]` sections gain content you didn't manually write. Those edits are intentional plugin behavior, not corruption.
- **Headless import logs `[godot-mcp] Plugin disabled` at shutdown.** This is a graceful shutdown message, not an error. The plugin is enabled in normal runs; it disables itself when the editor closes.
- **8 tests pass post-install.** Plugin's GDScript is well-isolated; doesn't conflict with the test suite or autoloads (`TickSystem` is unaffected; `MCPGameBridge` is a new autoload added below it, runs alongside).

### Out of scope (next session: actually use it for game work)

- This session's goal is "is the install working?" — verification only. Real usage of MCP tools to debug/inspect Stewardship landed in the next session.
- PlayGodot integration tests (from Randroids-Dojo skill pack) — also next session or later.

---

## ⚠ Active git stash: zoom feature (WIP)

**There is an uncommitted-but-stashed zoom implementation.** Don't forget about it.

- **Stash:** `stash@{0}` — message `WIP: zoom feature, displacement bug unresolved, return to fresh later`.
- **What it touches:** `scripts/main.gd` (wheel input + smooth-lerp zoom toward target), `scripts/world/grid_world.gd` (added `screen_px()` helper, scaled grid lines / hover preview / arrow widths), `scripts/world/buildings.gd` (scaled multi-tile border + port indicators).
- **Why stashed:** at low zoom, the user reported a "squares are displaced" visual bug. The repro was unclear (screenshot showed grid only, no visible buildings/player). Investigation paused; we pivoted to other work.
- **When returning:** restore with `git stash pop` (or `git stash apply` if you want to keep the entry), launch, place a recognizable building (e.g. Mill on stone), zoom out to the displacement state, screenshot it, and debug from there. Likely culprits: sub-pixel rounding in `screen_px()`-scaled draw widths, or camera position not snapped to integer pixels at low zoom.
- **Spec reference:** the camera-zoom spec section in `SESSION_E_PLAN.md` (current at the time the stash was made — may have moved by the time you read this).

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
