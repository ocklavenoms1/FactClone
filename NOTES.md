# Stewardship — design notes

Forward-looking design plans that aren't yet implemented. Each entry should answer: what's the goal, what hooks exist today, what blocks it, what's the target session.

Move entries to `CHANGELOG.md` (or just delete them) once the corresponding work ships.

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
