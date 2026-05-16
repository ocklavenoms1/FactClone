# Electricity Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the foundation of the Electricity Arc — a power network module with graph + dirty-flag topology, one generator (Water Wheel), one consumer (Electric Lamp), and a linear-satisfaction interface contract for the entire arc.

**Architecture:** Mirror the existing fluid-network pattern at `grid_world.gd:475-565` — `Dictionary[Vector2i, int]` component map, `Dictionary[int, T]` per-component data, dirty-flag for lazy BFS rebuild, lex-sort for deterministic component IDs. Add `PowerNetwork` as a pure-logic `RefCounted` static module (mirrors `Burner`). Linear satisfaction `min(1.0, supply / max(1, demand))` becomes the consumer interface contract — Sessions 4+ apply `1.0 / max(0.1, satisfaction)` to electric processors.

**Tech Stack:** Godot 4.6.2 / GDScript / `class_name X extends RefCounted` static modules. Headless test runner at `scripts/tests/test_runner.gd`. Save schema v18 unchanged.

**Plan source:** `docs/superpowers/specs/2026-05-15-electricity-foundation-design.md` (committed at `6977a81`).

---

## File map

| File | Purpose | Change type |
|---|---|---|
| `scripts/world/buildings.gd` | Type enum + DATA + dispatch | Modify — 3 enum entries + 3 DATA blocks + 4 dispatch sites |
| `scripts/world/power_network.gd` | Pure-logic module: BFS, supply/demand, satisfaction | NEW |
| `scripts/world/power_pole.gd` | make/draw/info_lines (no tick) | NEW |
| `scripts/world/water_wheel.gd` | make/tick/draw/info_lines + water-adjacency | NEW |
| `scripts/world/electric_lamp.gd` | make/tick/draw/info_lines + brightness modulation | NEW |
| `scripts/world/grid_world.gd` | New dict members + dirty-flag hooks + pre-tick orchestrator + wire draw | Modify (5 regions) |
| `scripts/ui/hotbar.gd` | Append "Power" category with 3 slots | Modify (1 region) |
| `scripts/tests/test_power_network.gd` | 10 internal sub-cases | NEW |
| `scripts/tests/test_runner.gd` | Append new test file to TESTS array | Modify (1 line) |
| `PROJECT_LOG.md` | Prepend session ship entry | Modify |
| `NOTES.md` | Update arc tracker + add new working protocols if any earned | Modify |

5 new files, 4 modified files. Save schema unchanged at v18.

---

## Task overview

| # | Task | TDD red | TDD green | Manual gate |
|---|---|---|---|---|
| 1 | Threshold audit (34/34 baseline) | — | run tests | — |
| 2 | PowerNetwork module skeleton + grid_world plumbing | — (pure scaffolding) | parse-check | — |
| 3 | Power Pole + topology + sub-cases (1)–(5) | sub-cases fail (POWER_POLE undefined) | enum + DATA + power_pole.gd + rebuild_topology + dirty-flag hooks | — |
| 4 | Wire rendering in grid_world._draw | — (visual only) | `_draw_power_wires` | covered by PAUSE 1 |
| 5 | Water Wheel + sub-case (6) | sub-case (6) fails | enum + DATA + water_wheel.gd + supply accumulation | — |
| 6 | Electric Lamp + sub-case (7) | sub-case (7) fails | enum + DATA + electric_lamp.gd + demand accumulation | — |
| 7 | Linear satisfaction + sub-cases (8)+(9) | sub-cases fail | `update_supply_demand` complete + pre-tick hook in `_on_tick` | — |
| 8 | Hotbar "Power" category | — (smoke at PAUSE 1) | hotbar.gd append | — |
| 9 | Save round-trip sub-case (10) | sub-case (10) likely passes on first run | (already wired) | — |
| 10 | PAUSE 1 visual smoke | — | — | user smoke |
| 11 | PAUSE 2 full gameplay | — | — | user smoke |
| 12 | Ship (PROJECT_LOG + NOTES + tag + push) | — | — | — |

**Subagent protocol per task:** implementer + spec reviewer + code quality reviewer (line-quoting required). Manual T10 + T11 stay with controller. Strengthened scope-deviation protocol applies — implementer flags any change beyond listed file regions, including silent default-value additions.

**Variable-name pre-check protocol** (validated last session): when appending sub-cases to a shared test file's `run()` function, grep for variable names before declaring them in the same scope. Suffix with `_N` (sub-case number) for collision defense.

---

## Task 1: Threshold audit

**Files:** none (verification only)

**Purpose:** Confirm 34/34 PASS baseline. HEAD must be `6977a81` (spec commit).

- [ ] **Step 1: Verify HEAD + working tree**

Run:
```bash
git status
git log --oneline -1
```
Expected: working tree clean, HEAD = `6977a81` (Spec: Electricity Foundation).

- [ ] **Step 2: Run full test suite**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `34 passed, 0 failed`. Three intentional stderr noises (save-migration negative paths, slot-handler headless popup-parent reuse).

- [ ] **Step 3: No commit (verification only)**

Proceed to Task 2.

---

## Task 2: PowerNetwork module skeleton + grid_world plumbing

**Files:**
- Create: `scripts/world/power_network.gd`
- Modify: `scripts/world/grid_world.gd` (add dict members + `mark_power_network_dirty()`)

**Purpose:** Scaffolding before any building references it. Module exists with empty function bodies; grid_world has dict members and a `mark_power_network_dirty()` glue method. No behavior yet, no tests; just makes Task 3's tests compilable.

- [ ] **Step 1: Create `scripts/world/power_network.gd`**

```gdscript
class_name PowerNetwork
extends RefCounted

## Power network resolver — graph + dirty-flag pattern.
##
## Mirrors the fluid-network pattern at grid_world.gd:475-565. Power poles
## form components via BFS over 5-tile Chebyshev adjacency. Generators
## adjacent to a pole contribute supply; consumers contribute demand. Each
## component has a linear satisfaction ratio in [0.0, 1.0]:
##
##   satisfaction = min(1.0, supply / max(1, demand))
##
## Consumer interface contract (arc-wide): every electric consumer reads
## world.power_satisfaction_at(b.anchor) and scales its throughput or
## visual feedback accordingly. Lamps modulate brightness; future
## processors (Sessions 4+) multiply cycle_ticks by 1.0 / max(0.1, sat).
##
## All state lives on the world (Dictionary maps); poles have empty state.
## On placement/removal of pole/generator/consumer, world calls
## `mark_dirty(world)`. Next query triggers a rebuild.

# Maximum Chebyshev distance for pole-to-pole auto-connection.
const POLE_RANGE: int = 5

# 4-directional adjacency for building-to-pole association.
const _CARDINALS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Mark the power network as needing a topology rebuild on next query.
## Called by grid_world on placement/removal of poles, generators, or
## consumers.
static func mark_dirty(world) -> void:
	world._power_network_dirty = true

## Rebuild the topology: walks all poles, BFS over 5-tile Chebyshev
## adjacency, populates world._pole_component[pos] = comp_id. Clears
## supply/demand/satisfaction (they're recomputed by update_supply_demand).
##
## Deterministic via lex-sorted starting points (matches fluid network).
static func rebuild_topology(world) -> void:
	world._pole_component.clear()
	world._component_supply.clear()
	world._component_demand.clear()
	world._component_satisfaction.clear()

	var pole_anchors: Array = []
	for anchor in world.buildings:
		if world.buildings[anchor].type == Buildings.Type.POWER_POLE:
			pole_anchors.append(anchor)
	pole_anchors.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))

	var next_id: int = 0
	for start in pole_anchors:
		if world._pole_component.has(start):
			continue
		var queue: Array = [start]
		while not queue.is_empty():
			var p: Vector2i = queue.pop_front()
			if world._pole_component.has(p):
				continue
			world._pole_component[p] = next_id
			# Find all poles within POLE_RANGE Chebyshev distance.
			for other in pole_anchors:
				if other == p:
					continue
				if world._pole_component.has(other):
					continue
				var dx: int = abs(other.x - p.x)
				var dy: int = abs(other.y - p.y)
				if max(dx, dy) <= POLE_RANGE:
					queue.append(other)
		next_id += 1

	world._power_network_dirty = false

## Per-tick orchestrator. Called from grid_world._on_tick BEFORE the
## building tick loop. Rebuilds topology if dirty, then walks generators
## (water wheels) and consumers (lamps) to accumulate supply/demand per
## component. Computes satisfaction last.
static func update_supply_demand(world) -> void:
	if world._power_network_dirty:
		rebuild_topology(world)

	# Reset accumulators.
	for comp_id in world._pole_component.values():
		world._component_supply[comp_id] = 0
		world._component_demand[comp_id] = 0

	# Walk all buildings. Generators contribute supply; consumers contribute
	# demand. Both use Buildings.all_edge_cells() to find adjacent poles.
	for anchor in world.buildings:
		var b: Building = world.buildings[anchor]
		var comp_id: int = _adjacent_component_id(world, b)
		if comp_id < 0:
			continue
		if b.type == Buildings.Type.WATER_WHEEL:
			if bool(b.state.get("output_active", false)):
				world._component_supply[comp_id] = int(world._component_supply.get(comp_id, 0)) + WaterWheel.MAX_OUTPUT
		elif b.type == Buildings.Type.ELECTRIC_LAMP:
			world._component_demand[comp_id] = int(world._component_demand.get(comp_id, 0)) + ElectricLamp.DEMAND

	# Compute satisfaction per component.
	for comp_id in world._pole_component.values():
		var sup: int = int(world._component_supply.get(comp_id, 0))
		var dem: int = int(world._component_demand.get(comp_id, 0))
		var sat: float = 1.0 if dem == 0 else min(1.0, float(sup) / float(dem))
		world._component_satisfaction[comp_id] = sat

## Find the component ID of any pole adjacent to building `b`. Returns -1
## if no adjacent pole. Used by generators (supply) and consumers (demand).
## Lex-first iteration order resolves the ambiguity when a building borders
## TWO different networks (documented v1 simplification).
static func _adjacent_component_id(world, b: Building) -> int:
	for cell in Buildings.all_edge_cells(b.type, b.anchor):
		if not world.has_building_at(cell):
			continue
		var nb: Building = world.building_at(cell)
		if nb == null or nb.type != Buildings.Type.POWER_POLE:
			continue
		if world._pole_component.has(nb.anchor):
			return int(world._pole_component[nb.anchor])
	return -1

## Public query: is the position adjacent to a pole in a powered (sat > 0)
## network? Used for boolean checks. Most consumers should use
## power_satisfaction_at() instead.
static func is_powered_at(world, pos: Vector2i) -> bool:
	return power_satisfaction_at(world, pos) > 0.0

## Public query: per-tile satisfaction. Returns 0.0 if no adjacent pole or
## no network. Returns [0.0, 1.0] otherwise. Consumers call this from their
## tick to drive brightness / throughput.
static func power_satisfaction_at(world, pos: Vector2i) -> float:
	if world._power_network_dirty:
		rebuild_topology(world)
	# Look for an adjacent pole.
	for dir_vec in _CARDINALS:
		var n: Vector2i = pos + dir_vec
		if not world._pole_component.has(n):
			continue
		var comp_id: int = int(world._pole_component[n])
		return float(world._component_satisfaction.get(comp_id, 0.0))
	return 0.0

## Public query: network ID (component ID) of the pole at `pos`, or -1
## if not a pole or not in network. Used by Q-inspect info_lines.
static func network_id_at(world, pos: Vector2i) -> int:
	if world._power_network_dirty:
		rebuild_topology(world)
	return int(world._pole_component.get(pos, -1))

## Public query: total supply for a component. For Q-inspect display.
static func supply_for(world, comp_id: int) -> int:
	return int(world._component_supply.get(comp_id, 0))

## Public query: total demand for a component.
static func demand_for(world, comp_id: int) -> int:
	return int(world._component_demand.get(comp_id, 0))

## Public query: satisfaction for a component.
static func satisfaction_for(world, comp_id: int) -> float:
	return float(world._component_satisfaction.get(comp_id, 0.0))
```

- [ ] **Step 2: Add dict members + glue to `scripts/world/grid_world.gd`**

Locate the fluid network dict members around line 211 (`var _fluid_network_dirty: bool = true`). Add immediately AFTER that block:

```gdscript
# Power network — mirrors fluid network pattern (BFS + dirty-flag). See
# scripts/world/power_network.gd for the resolver module. Linear-
# satisfaction model: each component has a ratio in [0, 1] applied by
# consumers to scale their throughput/visual feedback.
var _pole_component: Dictionary = {}              # Vector2i → int (component id)
var _component_supply: Dictionary = {}            # int (comp_id) → int (units)
var _component_demand: Dictionary = {}            # int (comp_id) → int (units)
var _component_satisfaction: Dictionary = {}      # int (comp_id) → float in [0, 1]
var _power_network_dirty: bool = true
```

Then locate `func mark_fluid_network_dirty() -> void:` around line 466. Add immediately AFTER its closing line:

```gdscript

## Mark the power network as needing a topology rebuild on next query.
## Useful for tests or future code paths that mutate buildings without
## going through place_building / remove_building.
func mark_power_network_dirty() -> void:
	_power_network_dirty = true

## Wrapper around PowerNetwork.power_satisfaction_at — convenience for
## consumers in their tick: `var sat = world.power_satisfaction_at(b.anchor)`.
func power_satisfaction_at(pos: Vector2i) -> float:
	return PowerNetwork.power_satisfaction_at(self, pos)
```

- [ ] **Step 3: Verify parse**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" --quit 2>&1 | tail -20
```
Expected: no parse errors. The new `power_network.gd` references `Buildings.Type.WATER_WHEEL` / `Buildings.Type.ELECTRIC_LAMP` / `WaterWheel.MAX_OUTPUT` / `ElectricLamp.DEMAND` which DON'T exist yet — GDScript resolves these lazily at runtime, NOT parse-time, so the file should parse OK. If parse fails, investigate.

- [ ] **Step 4: Run tests — expect 34/34 PASS (no behavior change)**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `34 passed, 0 failed`. The new module is unused; existing behavior unchanged.

- [ ] **Step 5: Commit**

```bash
git add scripts/world/power_network.gd scripts/world/grid_world.gd
git commit -m "$(cat <<'EOF'
Task 2: PowerNetwork module skeleton + grid_world plumbing

Pre-building scaffolding — module exists with full BFS + supply/demand
+ satisfaction logic, grid_world has new dict members + mark_dirty glue
+ power_satisfaction_at wrapper. No behavior yet (no building types
reference any of this); just makes Task 3's tests compilable.

PowerNetwork mirrors the existing fluid network pattern at
grid_world.gd:475-565 — Dictionary[Vector2i, int] component map,
Dictionary[int, T] per-component data, dirty-flag for lazy BFS rebuild,
lex-sorted start points for deterministic component IDs.

Linear-satisfaction model locked: each component has satisfaction in
[0.0, 1.0]; consumers scale brightness/throughput. This is the consumer
interface contract for the entire arc (Sessions 4+ will apply
1.0 / max(0.1, satisfaction) multiplier to electric processors).

34/34 still passing — module unused, no behavior change.
EOF
)"
```

---

## Task 3: Power Pole + topology tests (sub-cases 1–5)

**Files:**
- Modify: `scripts/world/buildings.gd` (enum + DATA + 4 dispatch sites)
- Create: `scripts/world/power_pole.gd`
- Modify: `scripts/world/grid_world.gd` (dirty-flag hooks in `place_building` + `remove_building_at`)
- Create: `scripts/tests/test_power_network.gd` (sub-cases 1–5)
- Modify: `scripts/tests/test_runner.gd` (append new file to TESTS array)

**Purpose:** First building type + first 5 test sub-cases. Power poles connect within 5-tile Chebyshev range, merge networks on bridge, split on bridge removal. This task is the most architecturally significant — it brings the topology BFS to life.

- [ ] **Step 1: Append POWER_POLE to Buildings.Type enum**

In `scripts/world/buildings.gd`, find the end of the `Type` enum (currently ends with `LONG_REACH_INSERTER,`). Append before the closing brace:

```gdscript
	LONG_REACH_INSERTER,
	# Electricity Arc Session 1 (session-electricity-foundation): Power
	# infrastructure foundation. POWER_POLE forms the wire network via
	# 5-tile Chebyshev adjacency; auto-connects on placement. Empty state.
	POWER_POLE,
}
```

- [ ] **Step 2: Append DATA entry for POWER_POLE**

In `scripts/world/buildings.gd`, find the end of the LONG_REACH_INSERTER DATA block. After its closing `},`, insert:

```gdscript
	Type.POWER_POLE: {
		"name": "Power Pole",
		"swatch_color": Color(0.50, 0.38, 0.25),    # dark wood-brown
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": false,
		# Thin pole — player walks under wires, matches inserter convention.
		"walkable": true,
		# No slot_layout — pole is passive infrastructure, no inventory UI.
		# Info-only via Q-inspect (info_lines shows network ID + capacity).
	},
```

- [ ] **Step 3: Extend dispatch in buildings.gd `make`**

Locate the `make` function (around line 794). After the `Type.LONG_REACH_INSERTER:` case (before the `push_error`), add:

```gdscript
		Type.POWER_POLE:
			return PowerPole.make(pos)
```

- [ ] **Step 4: Extend `info_lines` dispatch**

Locate the `info_lines_for` function (search for `static func info_lines_for`). Add a new case for POWER_POLE:

```gdscript
			Type.POWER_POLE:
				return PowerPole.info_lines(b, world)
```

(POWER_POLE has no tick or draw_one dispatch — handled below via direct `Buildings.draw_one` extension.)

- [ ] **Step 5: Extend `draw_one` dispatch**

Locate `draw_one` (around line 886, where Inserter is). Add a new case:

```gdscript
		Type.POWER_POLE:
			PowerPole.draw(b, canvas, world_pos, tile_size)
```

(No `tick_one` case — pole is passive, no per-tick logic.)

- [ ] **Step 6: Create `scripts/world/power_pole.gd`**

```gdscript
class_name PowerPole
extends RefCounted

## Power Pole — passive carrier of the electric network.
##
## Auto-connects to other poles within 5-tile Chebyshev range (POLE_RANGE
## in power_network.gd). No tick logic; network membership is computed on
## demand by PowerNetwork.rebuild_topology(world). Visual: dark wood base
## + tall pole + small "T" crossarm at top. Wires drawn globally by
## grid_world._draw_power_wires (NOT per-pole, to avoid double-drawing).
##
## State: empty {} (network membership tracked at world._pole_component level).

const BODY_COLOR: Color = Color(0.50, 0.38, 0.25)         # dark wood-brown
const POLE_COLOR: Color = Color(0.45, 0.32, 0.20)         # slightly darker shaft
const CROSSARM_COLOR: Color = Color(0.40, 0.28, 0.18)     # darkest

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.POWER_POLE, pos, {})

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	# Base square — small footprint reading as "thin pole standing here".
	var base_size: float = float(tile_size) * 0.30
	var base_rect: Rect2 = Rect2(
		center - Vector2(base_size * 0.5, base_size * 0.5),
		Vector2(base_size, base_size)
	)
	canvas.draw_rect(base_rect, BODY_COLOR, true)
	canvas.draw_rect(base_rect, CROSSARM_COLOR, false, 1.5)
	# Pole shaft — tall vertical bar from base to top of tile.
	var shaft_width: float = float(tile_size) * 0.10
	var shaft_rect: Rect2 = Rect2(
		Vector2(center.x - shaft_width * 0.5, world_pos.y + float(tile_size) * 0.10),
		Vector2(shaft_width, float(tile_size) * 0.55)
	)
	canvas.draw_rect(shaft_rect, POLE_COLOR, true)
	# Crossarm — small horizontal bar near top.
	var crossarm_width: float = float(tile_size) * 0.55
	var crossarm_height: float = float(tile_size) * 0.08
	var crossarm_rect: Rect2 = Rect2(
		Vector2(center.x - crossarm_width * 0.5, world_pos.y + float(tile_size) * 0.16),
		Vector2(crossarm_width, crossarm_height)
	)
	canvas.draw_rect(crossarm_rect, CROSSARM_COLOR, true)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	var comp_id: int = PowerNetwork.network_id_at(world, b.anchor)
	if comp_id < 0:
		lines.append("Network: (not connected)")
		return lines
	var supply: int = PowerNetwork.supply_for(world, comp_id)
	var demand: int = PowerNetwork.demand_for(world, comp_id)
	var sat: float = PowerNetwork.satisfaction_for(world, comp_id)
	lines.append("Network: #%d" % comp_id)
	lines.append("Capacity: %d / %d units" % [supply, demand])
	lines.append("Satisfaction: %d%%" % int(sat * 100.0))
	return lines
```

- [ ] **Step 7: Add dirty-flag hooks to `scripts/world/grid_world.gd`**

Locate `place_building` around line 436 (`if t == Buildings.Type.PIPE or t == Buildings.Type.PUMP: _fluid_network_dirty = true`). Add immediately AFTER that line:

```gdscript
	if t == Buildings.Type.POWER_POLE or t == Buildings.Type.WATER_WHEEL or t == Buildings.Type.ELECTRIC_LAMP:
		_power_network_dirty = true
```

Locate `remove_building_at` around line 455 (the parallel fluid line). Add immediately AFTER that line:

```gdscript
	if b.type == Buildings.Type.POWER_POLE or b.type == Buildings.Type.WATER_WHEEL or b.type == Buildings.Type.ELECTRIC_LAMP:
		_power_network_dirty = true
```

(Note: WATER_WHEEL / ELECTRIC_LAMP are referenced here BEFORE they exist as enum entries — Tasks 5 + 6 add them. This is OK because `Buildings.Type.X` is a constant resolved at runtime; an unresolved enum at parse time becomes a runtime error only if executed. Tests in Task 3 never instantiate those types so the lines aren't hit. **Task 3 verification: run tests; lines stay dormant.**)

- [ ] **Step 8: Create `scripts/tests/test_power_network.gd` with sub-cases (1)–(5)**

```gdscript
extends RefCounted

## Power network resolver tests.
##
## Sub-cases cover topology (single pole, in-range merge, out-of-range
## separation, bridge merge, split on bridge removal), generator/consumer
## association (water wheel adjacency, lamp adjacency), linear
## satisfaction (supply >= demand, brownout), and save round-trip.
##
## Sub-cases (1)-(5) shipped in Task 3 (topology only). Sub-cases (6)-(10)
## land in Tasks 5, 6, 7, 9 respectively.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "power network (topology)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var world = GridWorldScript.new()
	parent.add_child(world)

	# Lay overlay (STONE) across a horizontal strip so we can place poles
	# on any column 0..30. POWER_POLE accepts NONE/STONE/PATH/SOIL_TILLED
	# so STONE is fine.
	for x in range(0, 31):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)

	# ===========================================================================
	# (1) PLACE SINGLE POLE — component id 0 assigned.
	# ===========================================================================
	if not world.place_building(Buildings.Type.POWER_POLE, Vector2i(0, 5)):
		_disconnect(world)
		return { "ok": false, "message": "(1) could not place single pole at (0,5)" }
	# Trigger topology rebuild via a query.
	var comp_1: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	_check(failures, comp_1 == 0, "(1) single pole should be component 0, got %d" % comp_1)

	# ===========================================================================
	# (2) TWO POLES IN RANGE — within 5-tile Chebyshev, same component.
	# Place 2nd pole 5 tiles away (just at the edge of the connection range).
	# ===========================================================================
	if not world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5)):
		_disconnect(world)
		return { "ok": false, "message": "(2) could not place pole at (5,5)" }
	var comp_2a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var comp_2b: int = PowerNetwork.network_id_at(world, Vector2i(5, 5))
	_check(failures, comp_2a == comp_2b, "(2) poles at (0,5) and (5,5) should share component, got %d vs %d" % [comp_2a, comp_2b])

	# ===========================================================================
	# (3) TWO POLES OUT OF RANGE — 6+ tiles apart, different components.
	# Reset world, place poles at (0,5) and (11,5) (Chebyshev dist 11 > 5).
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 31):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(0, 5))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(11, 5))
	var comp_3a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var comp_3b: int = PowerNetwork.network_id_at(world, Vector2i(11, 5))
	_check(failures, comp_3a != comp_3b, "(3) poles at (0,5) and (11,5) should be different components, both got %d" % comp_3a)

	# ===========================================================================
	# (4) BRIDGE MERGES NETWORKS — place a third pole linking two separate.
	# Continuing from (3): place pole at (6,5) which is in-range of both
	# (0,5) (dist 6 — out of range, actually... wait) and (11,5) (dist 5).
	# We need bridge in range of BOTH ends. Use (5,5) — dist 5 from (0,5),
	# dist 6 from (11,5). Still out of range from (11,5)! Need (5,5) AND
	# additional middle. Cleanest: bridge at (8,5) — dist 8 from (0,5)
	# (out of range) and dist 3 from (11,5) (in range). Doesn't work either.
	# CORRECT BRIDGE: spans need 2 poles. Reset to a layout where bridge is
	# a single pole within 5 of BOTH ends.
	# Layout: (0,5) and (10,5) are 10 apart → different networks.
	# Bridge at (5,5): 5 tiles from each → in range of both → merges.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 31):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(0, 5))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(10, 5))
	# Before bridge: different components.
	var pre_bridge_a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var pre_bridge_b: int = PowerNetwork.network_id_at(world, Vector2i(10, 5))
	_check(failures, pre_bridge_a != pre_bridge_b, "(4) pre-bridge: (0,5) and (10,5) should be separate, both got %d" % pre_bridge_a)
	# Place bridge.
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5))
	var post_bridge_a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var post_bridge_b: int = PowerNetwork.network_id_at(world, Vector2i(10, 5))
	var post_bridge_mid: int = PowerNetwork.network_id_at(world, Vector2i(5, 5))
	_check(failures, post_bridge_a == post_bridge_b, "(4) post-bridge: ends should share component, got %d vs %d" % [post_bridge_a, post_bridge_b])
	_check(failures, post_bridge_a == post_bridge_mid, "(4) bridge itself should share component with both ends")

	# ===========================================================================
	# (5) REMOVE BRIDGE SPLITS NETWORK — remove the middle pole, network
	# splits back into two separate components.
	# ===========================================================================
	world.remove_building_at(Vector2i(5, 5))
	var post_remove_a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var post_remove_b: int = PowerNetwork.network_id_at(world, Vector2i(10, 5))
	_check(failures, post_remove_a != post_remove_b, "(5) post-remove: ends should be separate components again, both got %d" % post_remove_a)

	_disconnect(world)

	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: single pole + in-range merge + out-of-range + bridge merge + split on remove" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

static func _disconnect(world) -> void:
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.queue_free()
```

- [ ] **Step 9: Append new test file to TESTS array in `scripts/tests/test_runner.gd`**

Find the TESTS array (lines 14-49). After the last entry (`preload("res://scripts/tests/test_slot_click_handler.gd"),`), insert:

```gdscript
	preload("res://scripts/tests/test_slot_click_handler.gd"),
	preload("res://scripts/tests/test_power_network.gd"),
]
```

- [ ] **Step 10: Run tests — expect 35/35 PASS**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `35 passed, 0 failed`. New entry: `PASS  power network (topology)` with description listing the 5 sub-cases.

If FAIL on sub-cases (4) or (5): inspect the BFS in `rebuild_topology` — likely the Chebyshev-distance check or the queue handling.

- [ ] **Step 11: Commit**

```bash
git add scripts/world/buildings.gd scripts/world/power_pole.gd scripts/world/grid_world.gd scripts/tests/test_power_network.gd scripts/tests/test_runner.gd
git commit -m "$(cat <<'EOF'
Task 3: Power Pole + topology tests (sub-cases 1-5)

First building type in the Electricity Arc:
- Buildings.Type.POWER_POLE enum entry + DATA registration (1x1,
  walkable, NONE/STONE/PATH/SOIL_TILLED overlays accepted, no slot_layout)
- scripts/world/power_pole.gd — make/draw/info_lines (no tick — passive)
- grid_world dirty-flag hooks in place_building/remove_building (also
  flags for WATER_WHEEL/ELECTRIC_LAMP placeholders; safe because those
  types are unused this task)

PowerNetwork.rebuild_topology now exercised — BFS over 5-tile Chebyshev
adjacency, lex-sorted start points for deterministic component IDs.

scripts/tests/test_power_network.gd — NEW test file with sub-cases (1)-(5):
single pole assigned component 0, in-range poles share component,
out-of-range poles separate, bridge merges networks, removing bridge
splits back.

Runner count 34 -> 35. PASS line: 'power network (topology)' with 5
sub-cases listed in success message.
EOF
)"
```

---

## Task 4: Wire rendering in grid_world._draw

**Files:**
- Modify: `scripts/world/grid_world.gd` (add `_draw_power_wires` helper + call from `_draw`)

**Purpose:** Visual representation of the network. Lines between connected poles, color-coded by satisfaction. No tests — covered by PAUSE 1.

- [ ] **Step 1: Find `_draw` function**

Run:
```bash
grep -n "^func _draw" scripts/world/grid_world.gd
```

Note the line of `func _draw() -> void:`.

- [ ] **Step 2: Add `_draw_power_wires` helper near the end of grid_world.gd**

Append at the end of `scripts/world/grid_world.gd` (before the closing of the script, after `region_of_world_pos`):

```gdscript

# ---------- power network rendering ----------

## Draw wires between all pole pairs that are (a) in the same component
## and (b) within POLE_RANGE Chebyshev distance. Color reflects
## component satisfaction: golden if any power, dark brown if dead.
## Called from _draw between building draws and post-pass indicators.
func _draw_power_wires() -> void:
	if _power_network_dirty:
		PowerNetwork.rebuild_topology(self)
	# Collect poles grouped by component.
	var poles_by_comp: Dictionary = {}    # comp_id → Array[Vector2i]
	for pos in _pole_component:
		var cid: int = int(_pole_component[pos])
		if not poles_by_comp.has(cid):
			poles_by_comp[cid] = []
		poles_by_comp[cid].append(pos)
	# Draw wires per component.
	const WIRE_THICKNESS: float = 2.0
	var golden: Color = Color(0.85, 0.70, 0.40)
	var dark: Color = Color(0.30, 0.22, 0.15)
	for cid in poles_by_comp:
		var sat: float = float(_component_satisfaction.get(cid, 0.0))
		var wire_color: Color = golden if sat > 0.0 else dark
		var poles: Array = poles_by_comp[cid]
		# Pairwise draw (canonical ordering: lex-smaller anchor first).
		for i in range(poles.size()):
			for j in range(i + 1, poles.size()):
				var a: Vector2i = poles[i]
				var b: Vector2i = poles[j]
				var dx: int = abs(b.x - a.x)
				var dy: int = abs(b.y - a.y)
				if max(dx, dy) > PowerNetwork.POLE_RANGE:
					continue
				# Wire from pole-top to pole-top. Pole-top = world_pos + (tile_size/2, tile_size*0.16).
				var a_top: Vector2 = Vector2(a.x * TILE_SIZE + TILE_SIZE * 0.5, a.y * TILE_SIZE + TILE_SIZE * 0.16)
				var b_top: Vector2 = Vector2(b.x * TILE_SIZE + TILE_SIZE * 0.5, b.y * TILE_SIZE + TILE_SIZE * 0.16)
				draw_line(a_top, b_top, wire_color, WIRE_THICKNESS)
```

- [ ] **Step 3: Hook `_draw_power_wires` into `_draw`**

Open `scripts/world/grid_world.gd`, find `func _draw() -> void:`, and locate where buildings are drawn. The pattern looks like a loop calling `Buildings.draw_one(...)`. After that loop ends, add:

```gdscript
	_draw_power_wires()
```

(If `_draw` already has a post-pass section for borders/indicators, place this call between the building loop and the post-pass.)

If you can't locate the exact spot, alternative: add it as the LAST line of `_draw` so it draws on top of everything. Wires-on-top is acceptable visually.

- [ ] **Step 4: Run tests — expect 35/35 PASS**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `35 passed, 0 failed`. The new render code doesn't execute in headless tests (no display server invokes `_draw`).

- [ ] **Step 5: Commit**

```bash
git add scripts/world/grid_world.gd
git commit -m "$(cat <<'EOF'
Task 4: Wire rendering between connected poles

Adds _draw_power_wires() helper to grid_world.gd. Iterates all poles
grouped by component, draws pairwise lines for in-range pole pairs
within the same component. Golden when component has power, dark
brown when dead.

Visual only — no tests (covered by PAUSE 1 smoke). Run in headless:
35/35 still PASS, render code is unreached without display server.
EOF
)"
```

---

## Task 5: Water Wheel + sub-case (6)

**Files:**
- Modify: `scripts/world/buildings.gd` (enum + DATA + dispatch)
- Create: `scripts/world/water_wheel.gd`
- Modify: `scripts/tests/test_power_network.gd` (append sub-case 6)

**Purpose:** First generator. Water Wheel checks water adjacency, produces 10 power units when active. Test verifies adjacency-to-pole joins the network's supply pool.

- [ ] **Step 1: Append WATER_WHEEL to Buildings.Type enum**

In `scripts/world/buildings.gd`, find `POWER_POLE,` in the enum (added in Task 3). Append after it:

```gdscript
	POWER_POLE,
	# Water Wheel — first generator. 2x2, requires STONE/PATH base, must
	# have at least one perimeter cell over a water terrain tile to be
	# active. MAX_OUTPUT = 10 power units when active.
	WATER_WHEEL,
```

- [ ] **Step 2: Append DATA entry for WATER_WHEEL**

In `scripts/world/buildings.gd`, after the POWER_POLE DATA block, insert:

```gdscript
	Type.WATER_WHEEL: {
		"name": "Water Wheel",
		"swatch_color": Color(0.40, 0.55, 0.65),    # wet wood-teal
		"footprint": Vector2i(2, 2),
		# Substantial generator — needs solid base near water. Mirrors PUMP.
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": true,                  # wheel faces water
		"player_drainable": false,
		"walkable": false,
		# No slot_layout — generator has no items. Info via Q-inspect.
	},
```

- [ ] **Step 3: Extend dispatch for WATER_WHEEL**

In `scripts/world/buildings.gd`:

`make` (after `Type.POWER_POLE:` case from Task 3):
```gdscript
		Type.WATER_WHEEL:
			return WaterWheel.make(pos, dir)
```

`tick_one` (after the LONG_REACH_INSERTER case label):
```gdscript
		Type.WATER_WHEEL:
			WaterWheel.tick(b, world)
```

`draw_one` (after `Type.POWER_POLE:` case from Task 3):
```gdscript
		Type.WATER_WHEEL:
			WaterWheel.draw(b, canvas, world_pos, tile_size)
```

`info_lines_for` (after the POWER_POLE case from Task 3):
```gdscript
			Type.WATER_WHEEL:
				return WaterWheel.info_lines(b, world)
```

- [ ] **Step 4: Create `scripts/world/water_wheel.gd`**

```gdscript
class_name WaterWheel
extends RefCounted

## Water Wheel — sustainable electric generator.
##
## 2x2 footprint. Requires at least one perimeter cell over a water
## terrain tile to be active. MAX_OUTPUT = 10 power units when active.
## No fuel consumption — water is renewable.
##
## State:
##   dir: int                   — direction the wheel "faces" (water expected here)
##   output_active: bool        — set per-tick based on water adjacency
##   wheel_rotation: float      — visual rotation accumulator [0, TAU)
##
## Power network contract: when output_active, contributes MAX_OUTPUT to
## the supply of the component containing any adjacent pole. Adjacency
## resolved by Buildings.all_edge_cells() — same pattern as fluid.

const MAX_OUTPUT: int = 10
const ROTATION_PER_TICK: float = 0.15 * TAU / 20.0      # ~1 full rotation / 6.67 sec

const FRAME_COLOR: Color = Color(0.40, 0.32, 0.20)      # wooden frame
const WHEEL_COLOR: Color = Color(0.55, 0.45, 0.30)      # spokes
const WHEEL_RIM: Color = Color(0.30, 0.22, 0.14)        # rim outline
const WATER_INDICATOR: Color = Color(0.30, 0.55, 0.75)  # tiny dot when water adjacent
const IDLE_TINT: Color = Color(0.55, 0.55, 0.55)        # multiplicative dim when inactive

static func make(pos: Vector2i, dir: int = 0) -> Building:
	var state: Dictionary = {
		"dir": dir,
		"output_active": false,
		"wheel_rotation": 0.0,
	}
	return Building.new(Buildings.Type.WATER_WHEEL, pos, state)

## Tick: check water adjacency, update output_active and wheel_rotation.
static func tick(b: Building, world) -> void:
	var has_water: bool = _has_water_adjacent(b, world)
	b.state["output_active"] = has_water
	if has_water:
		var rot: float = float(b.state.get("wheel_rotation", 0.0)) + ROTATION_PER_TICK
		if rot >= TAU:
			rot -= TAU
		b.state["wheel_rotation"] = rot

## True if any perimeter cell of the wheel's footprint is over a water
## terrain tile.
static func _has_water_adjacent(b: Building, world) -> bool:
	for cell in Buildings.all_edge_cells(b.type, b.anchor):
		if world.tiles.has(cell):
			var tile = world.tiles[cell]
			if tile != null and tile.base == Terrain.Base.WATER:
				return true
	return false

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# 2x2 frame.
	var frame_rect: Rect2 = Rect2(world_pos, Vector2(tile_size * 2, tile_size * 2))
	var active: bool = bool(b.state.get("output_active", false))
	var tint: Color = Color.WHITE if active else IDLE_TINT
	var frame_color: Color = Color(FRAME_COLOR.r * tint.r, FRAME_COLOR.g * tint.g, FRAME_COLOR.b * tint.b, 1.0)
	canvas.draw_rect(frame_rect, frame_color, true)
	canvas.draw_rect(frame_rect, WHEEL_RIM, false, 2.0)
	# Wheel — central rotating spokes.
	var center: Vector2 = world_pos + Vector2(tile_size, tile_size)
	var radius: float = float(tile_size) * 0.85
	var wheel_color: Color = Color(WHEEL_COLOR.r * tint.r, WHEEL_COLOR.g * tint.g, WHEEL_COLOR.b * tint.b, 1.0)
	canvas.draw_arc(center, radius, 0.0, TAU, 24, WHEEL_RIM, 2.0)
	canvas.draw_arc(center, radius * 0.8, 0.0, TAU, 24, wheel_color, 1.5)
	# Spokes — 6 of them, rotated by wheel_rotation.
	var rot: float = float(b.state.get("wheel_rotation", 0.0))
	for i in range(6):
		var angle: float = rot + (TAU / 6.0) * float(i)
		var tip: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * 0.85
		canvas.draw_line(center, tip, wheel_color, 2.0)
	# Water indicator — small blue dot at center when active.
	if active:
		canvas.draw_circle(center, float(tile_size) * 0.12, WATER_INDICATOR)
		canvas.draw_arc(center, float(tile_size) * 0.12, 0.0, TAU, 16, WHEEL_RIM, 1.0)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	var active: bool = bool(b.state.get("output_active", false))
	var output_str: String = "%d / %d units" % [MAX_OUTPUT if active else 0, MAX_OUTPUT]
	lines.append("Output: %s (water adjacent: %s)" % [output_str, "yes" if active else "no"])
	# Network info — only meaningful if adjacent to a pole.
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
	else:
		lines.append("Network: #%d" % comp_id)
	# Facing.
	lines.append("Facing: %s (R to rotate; water expected on this edge)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])
	return lines
```

- [ ] **Step 5: Append sub-case (6) to test_power_network.gd**

Find the end of sub-case (5) in `scripts/tests/test_power_network.gd`, just before the `_disconnect(world)` line. Insert:

```gdscript

	# ===========================================================================
	# (6) GENERATOR JOINS NETWORK — water wheel adjacent to pole contributes
	# MAX_OUTPUT (10) to that network's supply pool when active.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	# Paint a strip of stone + a water tile next to where the wheel will be.
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	# Water tile at (3, 5) — wheel will be at (4, 5) - (5, 6) facing west (DIR_W).
	# But the wheel is 2x2, so its anchor at (4, 5) covers (4,5)(5,5)(4,6)(5,6).
	# Water at (3, 5) is adjacent to (4, 5) — the wheel's west edge.
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	# Pole adjacent to the wheel — place it east of the wheel at (6, 5).
	# The wheel covers (4,5)(5,5)(4,6)(5,6). (6, 5) is adjacent to (5, 5).
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	# Place wheel facing west (DIR_W). DIR_W = 2 per Belt.DIR_VECS convention.
	if not world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W):
		_disconnect(world)
		return { "ok": false, "message": "(6) could not place water wheel at (4,5) — check water-overlay setup" }
	# Tick once to populate output_active.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	# Now run update_supply_demand explicitly (which _on_tick would normally do
	# via grid_world._on_tick pre-pass; but test_runner pauses TickSystem so
	# the per-tick orchestrator may not have fired. Call directly.)
	PowerNetwork.update_supply_demand(world)
	# Verify: pole's component has supply >= 10.
	var comp_6: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, comp_6 >= 0, "(6) pole should be in a network, got comp_id %d" % comp_6)
	if comp_6 >= 0:
		var supply_6: int = PowerNetwork.supply_for(world, comp_6)
		_check(failures, supply_6 == WaterWheel.MAX_OUTPUT,
			"(6) network supply should equal MAX_OUTPUT (%d), got %d" % [WaterWheel.MAX_OUTPUT, supply_6])
		# Sanity: wheel's output_active should be true.
		var wheel_b: Building = world.building_at(Vector2i(4, 5))
		_check(failures, bool(wheel_b.state.get("output_active", false)),
			"(6) wheel should be output_active = true (water at (3,5) adjacent)")
```

Also update the success message at the bottom:

```gdscript
		return { "ok": true, "message": "6 sub-cases pass: single pole + in-range + out-of-range + bridge merge + split + generator joins network" }
```

And update `test_name()`:

```gdscript
static func test_name() -> String:
	return "power network (topology + generator)"
```

- [ ] **Step 6: Run tests — expect 35/35 PASS**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `35 passed, 0 failed`. PASS line now `power network (topology + generator)`.

If FAIL on sub-case (6): inspect `WaterWheel._has_water_adjacent` (water tile check) or `PowerNetwork._adjacent_component_id` (perimeter scan).

- [ ] **Step 7: Commit**

```bash
git add scripts/world/buildings.gd scripts/world/water_wheel.gd scripts/tests/test_power_network.gd
git commit -m "$(cat <<'EOF'
Task 5: Water Wheel generator + sub-case (6)

First generator in the Electricity Arc:
- Buildings.Type.WATER_WHEEL enum + DATA (2x2, supports_direction,
  STONE/PATH overlays, walkable=false)
- scripts/world/water_wheel.gd — make/tick/draw/info_lines
- Tick: check water-adjacent perimeter cell, update output_active +
  wheel_rotation (visual)
- MAX_OUTPUT = 10 power units when active
- Joins network's supply pool via PowerNetwork._adjacent_component_id

Test sub-case (6): water at (3,5), pole at (6,5), wheel at (4,5)
facing west. After tick + update_supply_demand, network supply
equals MAX_OUTPUT. 35/35 PASS.
EOF
)"
```

---

## Task 6: Electric Lamp + sub-case (7)

**Files:**
- Modify: `scripts/world/buildings.gd` (enum + DATA + dispatch)
- Create: `scripts/world/electric_lamp.gd`
- Modify: `scripts/tests/test_power_network.gd` (append sub-case 7)

**Purpose:** First consumer. Demand = 1, brightness modulates by satisfaction. Test verifies adjacency-to-pole joins the network's demand pool.

- [ ] **Step 1: Append ELECTRIC_LAMP to Buildings.Type enum**

In `scripts/world/buildings.gd`, find `WATER_WHEEL,` (added in Task 5). Append after it:

```gdscript
	WATER_WHEEL,
	# Electric Lamp — first consumer. 1x1, DEMAND = 1 power unit.
	# Brightness modulates by network satisfaction in [0, 1]. The lamp
	# is intentionally binary-visual (on/off threshold at sat>0.05 + alpha
	# scaling); future processors will scale throughput linearly.
	ELECTRIC_LAMP,
```

- [ ] **Step 2: Append DATA entry for ELECTRIC_LAMP**

In `scripts/world/buildings.gd`, after the WATER_WHEEL DATA block:

```gdscript
	Type.ELECTRIC_LAMP: {
		"name": "Electric Lamp",
		"swatch_color": Color(0.95, 0.85, 0.45),    # warm yellow
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": false,
		"walkable": false,
	},
```

- [ ] **Step 3: Extend dispatch for ELECTRIC_LAMP**

In `scripts/world/buildings.gd`:

`make` (after `Type.WATER_WHEEL:` case from Task 5):
```gdscript
		Type.ELECTRIC_LAMP:
			return ElectricLamp.make(pos)
```

`tick_one` (after the WATER_WHEEL case):
```gdscript
		Type.ELECTRIC_LAMP:
			ElectricLamp.tick(b, world)
```

`draw_one` (after the WATER_WHEEL case):
```gdscript
		Type.ELECTRIC_LAMP:
			ElectricLamp.draw(b, canvas, world_pos, tile_size)
```

`info_lines_for` (after the WATER_WHEEL case):
```gdscript
			Type.ELECTRIC_LAMP:
				return ElectricLamp.info_lines(b, world)
```

- [ ] **Step 4: Create `scripts/world/electric_lamp.gd`**

```gdscript
class_name ElectricLamp
extends RefCounted

## Electric Lamp — first consumer in the Electricity Arc.
##
## 1x1 footprint. DEMAND = 1 power unit. Brightness modulates by network
## satisfaction in [0, 1] — fully on at satisfaction == 1.0, dim under
## brownout, dark at satisfaction == 0.0.
##
## State:
##   satisfaction: float        — cached from network for visual modulation
##
## Power network contract: subtracts DEMAND from network's pool. Reads
## world.power_satisfaction_at(b.anchor) in tick.

const DEMAND: int = 1

const OFF_COLOR: Color = Color(0.30, 0.30, 0.30)      # dark gray when no power
const ON_COLOR: Color = Color(1.00, 0.90, 0.50)       # warm yellow when full
const BASE_COLOR: Color = Color(0.40, 0.32, 0.20)     # lamp base / housing
const GLOW_COLOR: Color = Color(1.00, 0.85, 0.40)     # halo glow

static func make(pos: Vector2i) -> Building:
	var state: Dictionary = {
		"satisfaction": 0.0,
	}
	return Building.new(Buildings.Type.ELECTRIC_LAMP, pos, state)

## Tick: query network satisfaction, cache for draw().
static func tick(b: Building, world) -> void:
	b.state["satisfaction"] = world.power_satisfaction_at(b.anchor)

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var sat: float = float(b.state.get("satisfaction", 0.0))
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	# Base housing — small square at the bottom.
	var base_size: float = float(tile_size) * 0.55
	var base_rect: Rect2 = Rect2(
		Vector2(center.x - base_size * 0.5, center.y - base_size * 0.5),
		Vector2(base_size, base_size)
	)
	canvas.draw_rect(base_rect, BASE_COLOR, true)
	canvas.draw_rect(base_rect, BASE_COLOR.darkened(0.3), false, 1.5)
	# Bulb — central circle, color interpolated by satisfaction.
	var bulb_color: Color = OFF_COLOR.lerp(ON_COLOR, sat)
	canvas.draw_circle(center, float(tile_size) * 0.22, bulb_color)
	canvas.draw_arc(center, float(tile_size) * 0.22, 0.0, TAU, 16, BASE_COLOR.darkened(0.3), 1.5)
	# Glow halo — only when satisfaction > 0.05. Alpha scales with sat.
	if sat > 0.05:
		var halo_color: Color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.35 * sat)
		canvas.draw_circle(center, float(tile_size) * 0.42, halo_color)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	lines.append("Demand: %d unit" % DEMAND)
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
		lines.append("Satisfaction: 0%% (NO POWER)")
		return lines
	var sat: float = PowerNetwork.satisfaction_for(world, comp_id)
	lines.append("Network: #%d" % comp_id)
	var status: String
	if sat >= 1.0:
		status = "FULL"
	elif sat > 0.0:
		status = "BROWNOUT"
	else:
		status = "NO POWER"
	lines.append("Satisfaction: %d%% (%s)" % [int(sat * 100.0), status])
	return lines
```

- [ ] **Step 5: Append sub-case (7) to test_power_network.gd**

Find the end of sub-case (6) in `scripts/tests/test_power_network.gd`. Append:

```gdscript

	# ===========================================================================
	# (7) CONSUMER JOINS NETWORK — lamp adjacent to pole contributes DEMAND
	# to that network's demand pool.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	# Place pole at (5, 5), lamp at (6, 5) (adjacent).
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5))
	world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(6, 5))
	# update_supply_demand to populate demand.
	PowerNetwork.update_supply_demand(world)
	var comp_7: int = PowerNetwork.network_id_at(world, Vector2i(5, 5))
	_check(failures, comp_7 >= 0, "(7) pole should be in a network, got comp_id %d" % comp_7)
	if comp_7 >= 0:
		var demand_7: int = PowerNetwork.demand_for(world, comp_7)
		_check(failures, demand_7 == ElectricLamp.DEMAND,
			"(7) network demand should equal lamp DEMAND (%d), got %d" % [ElectricLamp.DEMAND, demand_7])
```

Update the success message and test_name:

```gdscript
		return { "ok": true, "message": "7 sub-cases pass: + consumer joins network" }
```

```gdscript
static func test_name() -> String:
	return "power network (topology + generator + consumer)"
```

- [ ] **Step 6: Run tests — expect 35/35 PASS**

Run the test command. Expected: `35 passed, 0 failed`. PASS line: `power network (topology + generator + consumer)`.

- [ ] **Step 7: Commit**

```bash
git add scripts/world/buildings.gd scripts/world/electric_lamp.gd scripts/tests/test_power_network.gd
git commit -m "$(cat <<'EOF'
Task 6: Electric Lamp + sub-case (7)

First consumer in the Electricity Arc:
- Buildings.Type.ELECTRIC_LAMP enum + DATA (1x1, NONE/STONE/PATH/SOIL_TILLED
  overlays, walkable=false)
- scripts/world/electric_lamp.gd — make/tick/draw/info_lines
- Tick: read world.power_satisfaction_at(b.anchor), cache to state
- DEMAND = 1 power unit
- Draw: bulb color lerps from dark gray to warm yellow by satisfaction;
  glow halo at satisfaction > 0.05 with alpha proportional to sat

Test sub-case (7): pole at (5,5), lamp at (6,5). After update_supply_demand,
network demand equals ElectricLamp.DEMAND. 35/35 PASS.
EOF
)"
```

---

## Task 7: Linear satisfaction + sub-cases (8)+(9)

**Files:**
- Modify: `scripts/world/grid_world.gd` (hook `PowerNetwork.update_supply_demand` into `_on_tick`)
- Modify: `scripts/tests/test_power_network.gd` (append sub-cases 8 + 9)

**Purpose:** Wire the per-tick supply/demand orchestrator into `_on_tick`. Verify linear satisfaction math via two scenarios: sufficient supply (satisfaction = 1.0) and brownout (satisfaction < 1.0).

- [ ] **Step 1: Hook `update_supply_demand` into `_on_tick`**

In `scripts/world/grid_world.gd`, locate `func _on_tick(_tick_no: int) -> void:` (around line 568). Modify to insert the power-network update BEFORE the building loop:

```gdscript
func _on_tick(_tick_no: int) -> void:
	# Pre-pass: update power network supply/demand/satisfaction. Generators
	# and consumers read/write state during their own tick (output_active /
	# satisfaction); this pre-pass aggregates those into the per-component
	# numbers, so consumers see the CURRENT-tick numbers when their tick
	# runs in the building loop below.
	PowerNetwork.update_supply_demand(self)
	# Two-pass tick: pass 1 mutates self only, pass 2 hands items to neighbors.
	# Reading neighbor state in pass 2 is safe because pass 1 has finished
	# everywhere — order-independent for chain belts.
	for anchor in buildings:
		Buildings.tick_one(buildings[anchor], self)
	for anchor in buildings:
		Buildings.post_tick_one(buildings[anchor], self)
```

Note: there's an ordering subtlety here. `update_supply_demand` reads generator's `output_active` state — but `output_active` is SET by generator's tick. So the FIRST tick after placement, the supply will be 0 (generator's tick hasn't fired yet). For tests that need a single-tick verification, call `update_supply_demand` directly AFTER one tick has occurred (Tasks 5 + 6 already do this). For in-game, the second tick onward shows correct supply. **Acceptable for v1**; can refine in Session 2 if it surfaces as a UX issue.

- [ ] **Step 2: Append sub-cases (8) and (9) to test_power_network.gd**

Find the end of sub-case (7). Append:

```gdscript

	# ===========================================================================
	# (8) SUPPLY SUFFICIENT — wheel (10) + lamp (1), satisfaction == 1.0.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	# Layout: water (3,5), wheel (4,5) facing west, pole (6,5), lamp (7,5).
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(7, 5))
	# Tick once to populate wheel's output_active.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var comp_8: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, comp_8 >= 0, "(8) pole should be in a network")
	if comp_8 >= 0:
		var sat_8: float = PowerNetwork.satisfaction_for(world, comp_8)
		_check(failures, abs(sat_8 - 1.0) < 0.001,
			"(8) satisfaction should be 1.0 (supply 10 > demand 1), got %f" % sat_8)
		# Tick lamp again to update its cached satisfaction.
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		var lamp_b: Building = world.building_at(Vector2i(7, 5))
		_check(failures, abs(float(lamp_b.state.get("satisfaction", -1.0)) - 1.0) < 0.001,
			"(8) lamp.state.satisfaction should be 1.0, got %f" % float(lamp_b.state.get("satisfaction", -1.0)))

	# ===========================================================================
	# (9) BROWNOUT — 1 wheel (10 supply) + 100 lamps (100 demand). Sat = 0.1.
	# Use a different layout — line of lamps adjacent to a single pole chain.
	# Simplest: place pole at (5,5), 1 wheel adjacent (4,5 — water at (3,5)),
	# and many lamps adjacent to the same pole. A 1x1 pole has 4 adjacent
	# cells. To get >10 lamps, chain poles along the row.
	# Simpler: place wheel + pole + lamps NOT FROM ALL DIRECTIONS but use
	# a chain. Layout:
	#   (3,5)=water, (4,5)+(5,6)=wheel facing W, (6,5)=pole, (7,5)+(8,5)+(7,6)+(8,6) = 4 lamps directly adjacent.
	#   Add more poles to extend: (11,5)=pole (in range of (6,5)).
	#   Lamps around (11,5): (10,5)+(12,5)+(11,4)+(11,6) = 4 more lamps.
	#   Add (16,5)=pole. Lamps around: (15,5)+(17,5)+(16,4)+(16,6) = 4 more lamps.
	#   Total 12 lamps, demand 12, supply 10 → satisfaction = 10/12 ≈ 0.833.
	# That's brownout but not extreme. Let's tune for sat = 0.5 by using
	# 20 lamps. Easiest: programmatic placement in a loop.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	# Paint a 30-tile-wide strip of stone so we can place lots of things.
	for x in range(0, 30):
		for y in range(3, 8):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	# Chain of poles spanning columns 6, 11, 16, 21, 26 (5-tile spacing).
	for px in [6, 11, 16, 21, 26]:
		world.place_building(Buildings.Type.POWER_POLE, Vector2i(px, 5))
	# Place 20 lamps adjacent to those poles. Each pole's 4 cardinal neighbors
	# (minus pole-adjacent cells used by other poles) can host lamps. Use
	# columns above (y=4) and below (y=6) the pole row.
	var lamps_placed: int = 0
	for px in [6, 11, 16, 21, 26]:
		# y=4 and y=6 for each pole — 2 lamps per pole × 5 poles = 10 lamps.
		for ly in [4, 6]:
			if world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(px, ly)):
				lamps_placed += 1
		# Adjacent columns too — (px-1, 5), (px+1, 5) where not occupied by pole.
		for dx_ in [-1, 1]:
			var col: int = px + dx_
			if col == 4 or col == 5:  # wheel zone
				continue
			# Check not already a pole.
			var taken: bool = false
			for poles_x in [6, 11, 16, 21, 26]:
				if col == poles_x:
					taken = true
					break
			if taken:
				continue
			if world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(col, 5)):
				lamps_placed += 1
	# Demand = lamps_placed × 1. Supply = 10 (one wheel).
	# Tick once to populate wheel's output_active.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var comp_9: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, comp_9 >= 0, "(9) pole should be in a network")
	if comp_9 >= 0:
		var sup_9: int = PowerNetwork.supply_for(world, comp_9)
		var dem_9: int = PowerNetwork.demand_for(world, comp_9)
		var sat_9: float = PowerNetwork.satisfaction_for(world, comp_9)
		var expected_sat: float = min(1.0, float(sup_9) / float(max(1, dem_9)))
		_check(failures, abs(sat_9 - expected_sat) < 0.001,
			"(9) brownout satisfaction should be %f (supply %d / demand %d), got %f" % [expected_sat, sup_9, dem_9, sat_9])
		# Sanity: brownout actually occurred (sup < dem).
		_check(failures, sup_9 < dem_9, "(9) brownout precondition: supply %d should be < demand %d" % [sup_9, dem_9])
```

Update success message and test_name:

```gdscript
		return { "ok": true, "message": "9 sub-cases pass: + supply sufficient + brownout (linear satisfaction)" }
```

```gdscript
static func test_name() -> String:
	return "power network (topology + generator + consumer + linear satisfaction)"
```

- [ ] **Step 3: Run tests — expect 35/35 PASS**

Expected: PASS line is `power network (topology + generator + consumer + linear satisfaction)`.

If FAIL on (8): satisfaction not reaching 1.0. Inspect formula in `update_supply_demand`.
If FAIL on (9): brownout math wrong. Verify `min(1.0, supply / max(1, demand))` gives a value < 1.0 when supply < demand.

- [ ] **Step 4: Commit**

```bash
git add scripts/world/grid_world.gd scripts/tests/test_power_network.gd
git commit -m "$(cat <<'EOF'
Task 7: Linear satisfaction + sub-cases (8)+(9)

Wires PowerNetwork.update_supply_demand into grid_world._on_tick as a
pre-pass before the building tick loop. This means every consumer's tick
sees current-frame supply/demand state.

Sub-case (8): water wheel (supply 10) + lamp (demand 1) → satisfaction
1.0. Lamp's cached state.satisfaction matches.

Sub-case (9): water wheel (supply 10) + 20+ lamps → satisfaction
proportional to supply/demand ratio, < 1.0. Confirms linear scaling.

Ordering note: first tick after placement, generator's output_active is
still false (tick fires AFTER pre-pass). For in-game this means 1-tick
delay on initial supply — acceptable for v1, refine in Session 2 if it
surfaces as UX issue.

35/35 PASS.
EOF
)"
```

---

## Task 8: Hotbar "Power" category

**Files:**
- Modify: `scripts/ui/hotbar.gd` (append new category)

**Purpose:** Make the 3 building types placeable from the hotbar UI. Smoke verified at PAUSE 1.

- [ ] **Step 1: Append Power category to hotbar.gd**

In `scripts/ui/hotbar.gd`, find the existing categories (Terrain, Logistics, Inserters, Production). Append after the last category but before any closing block. Typical structure has `categories.append({ ... })` calls. Add immediately after the Inserters category append (around line 120):

```gdscript

	# Electricity Arc Session 1 (session-electricity-foundation): NEW Power
	# category. Three slots — pole (connector), water wheel (generator),
	# electric lamp (test consumer). Future sessions extend with more
	# generators (windmill, steam engine), storage (accumulator), and
	# tier variants (medium pole, substation).
	categories.append({
		"name": "Power",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.POWER_POLE },
			{ "kind": "building", "value": Buildings.Type.WATER_WHEEL },
			{ "kind": "building", "value": Buildings.Type.ELECTRIC_LAMP },
		],
		"selected": 0,
	})
```

- [ ] **Step 2: Run tests — expect 35/35 PASS**

Hotbar changes don't affect test runner. Expected: `35 passed, 0 failed`.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/hotbar.gd
git commit -m "$(cat <<'EOF'
Task 8: Hotbar 'Power' category — 3 slots

Appends a new Power category to the hotbar with 3 slots (in order):
- Power Pole (1x1 wood-brown swatch)
- Water Wheel (2x2 wet-teal swatch)
- Electric Lamp (1x1 warm-yellow swatch)

Smoke verification deferred to PAUSE 1. 35/35 PASS.
EOF
)"
```

---

## Task 9: Save round-trip sub-case (10)

**Files:**
- Modify: `scripts/tests/test_power_network.gd` (append sub-case 10)

**Purpose:** Lock down save/load preservation. Place 2 poles + 1 wheel + 1 lamp, save, reload, verify network reconstructed correctly and lamp still receiving power. Since save schema is unchanged (v18) and network rebuilds via dirty-flag on load, expect PASS on first run.

- [ ] **Step 1: Append sub-case (10) to test_power_network.gd**

Find the end of sub-case (9). Append:

```gdscript

	# ===========================================================================
	# (10) SAVE ROUND-TRIP — place network, save, reload, verify topology
	# reconstructed and lamp still powered.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(11, 5))
	world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(7, 5))
	# Pre-save: tick + update + verify lamp powered.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var pre_comp: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	var pre_sat: float = PowerNetwork.satisfaction_for(world, pre_comp)
	_check(failures, abs(pre_sat - 1.0) < 0.001, "(10) pre-save: lamp should be fully powered, got sat %f" % pre_sat)

	# Save via SaveSystem (matches inserter save sub-case pattern).
	var save_path_10: String = "user://test_power_network_save.json"
	var orig_path_10: String = SaveSystem.save_path
	SaveSystem.save_path = save_path_10
	var player_a_10 := Node2D.new()
	parent.add_child(player_a_10)
	if not SaveSystem.save_game(world, player_a_10, Inventory.new(16)):
		SaveSystem.save_path = orig_path_10
		_disconnect(world)
		player_a_10.queue_free()
		return { "ok": false, "message": "(10) save_game failed" }

	# Load into a fresh world.
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	var player_b_10 := Node2D.new()
	parent.add_child(player_b_10)
	var result_10: LoadResult = SaveSystem.load_game(world, player_b_10, Inventory.new(16))
	if not result_10.success:
		SaveSystem.save_path = orig_path_10
		_disconnect(world)
		player_a_10.queue_free()
		player_b_10.queue_free()
		return { "ok": false, "message": "(10) load_game failed: %s" % result_10.error_message }

	# Post-load: tick + update + verify lamp still powered (network reconstructed).
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var post_comp: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, post_comp >= 0, "(10) post-load: pole at (6,5) should be in a network, got %d" % post_comp)
	if post_comp >= 0:
		var post_sat: float = PowerNetwork.satisfaction_for(world, post_comp)
		_check(failures, abs(post_sat - 1.0) < 0.001, "(10) post-load: lamp should still be fully powered, got sat %f" % post_sat)
		# Sanity: wheel + 2 poles + 1 lamp all loaded as the correct types.
		_check(failures, world.has_building_at(Vector2i(4, 5)) and world.building_at(Vector2i(4, 5)).type == Buildings.Type.WATER_WHEEL,
			"(10) wheel at (4,5) should be loaded")
		_check(failures, world.has_building_at(Vector2i(6, 5)) and world.building_at(Vector2i(6, 5)).type == Buildings.Type.POWER_POLE,
			"(10) pole at (6,5) should be loaded")
		_check(failures, world.has_building_at(Vector2i(11, 5)) and world.building_at(Vector2i(11, 5)).type == Buildings.Type.POWER_POLE,
			"(10) pole at (11,5) should be loaded")
		_check(failures, world.has_building_at(Vector2i(7, 5)) and world.building_at(Vector2i(7, 5)).type == Buildings.Type.ELECTRIC_LAMP,
			"(10) lamp at (7,5) should be loaded")

	# Cleanup test save file + restore path.
	SaveSystem.save_path = orig_path_10
	if FileAccess.file_exists(save_path_10):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path_10))
	player_a_10.queue_free()
	player_b_10.queue_free()
```

Update success message and test_name (final form):

```gdscript
		return { "ok": true, "message": "10 sub-cases pass: + save round-trip (network rebuilt on load)" }
```

```gdscript
static func test_name() -> String:
	return "power network (topology + generator + consumer + linear satisfaction + save)"
```

- [ ] **Step 2: Run tests — expect 35/35 PASS**

Expected: PASS line is the full description.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_power_network.gd
git commit -m "$(cat <<'EOF'
Task 9: Save round-trip sub-case (10) — last code task

Place network (wheel + 2 poles + lamp), save, reload, verify all 4
buildings preserved + lamp still receiving full power. Confirms:
- Append-only enum (POWER_POLE/WATER_WHEEL/ELECTRIC_LAMP get next ints)
  compatible with save format unchanged
- Network maps (_pole_component etc.) NOT serialized but rebuilt via
  dirty-flag on load
- Save schema v18 sufficient — no migration needed

35/35 PASS. Last code task before manual PAUSE checkpoints.
EOF
)"
```

---

## Task 10: PAUSE 1 — visual smoke

**Files:** none (manual verification)

**Purpose:** Visual confirmation of behaviors headless tests can't cover — wire rendering, water wheel rotation, lamp brightness modulation, hotbar swatches, panel routing (info_lines via Q-key).

**Manual gate — controller orchestrates, user verifies in-game.**

- [ ] **Step 1: Launch game**

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9"
```

- [ ] **Step 2: User verifies the 5-item smoke matrix**

1. Hotbar Power category shows 3 slots in order: dark wood-brown (pole) → wet-teal (wheel) → warm-yellow (lamp).
2. Place 3 poles spaced ~5 tiles apart in a row → wires visible between each in-range pair (dark brown since no generator yet).
3. Place a water wheel adjacent to water (e.g., near the lake) facing the water → wheel rotates visually + water-indicator dot appears + lamp would be reachable. (Generator's `output_active` should make wires turn golden after the next tick.)
4. Place a lamp adjacent to the connected pole → lamp lights up to full brightness within 1-2 ticks (warm yellow + halo glow).
5. Drag the wheel away from water (remove + replace far from water) → lamp darkens (no supply → satisfaction 0).

Q-inspect (Q-key or right-click) on each building should show the network info — pole shows component # + capacity, wheel shows output/water status, lamp shows demand + satisfaction.

- [ ] **Step 3: User reports PASS or FAIL with detail**

If FAIL: investigate the specific item. Common pitfalls:
- Wires not visible: check `_draw_power_wires` is actually called from `_draw`.
- Wheel not rotating: check tick fires (state.wheel_rotation increases).
- Lamp not bright: check satisfaction propagation (tick order: pre-pass → consumer tick).

- [ ] **Step 4: Close game**

When user confirms PASS, close the game (TaskStop or user closes window) and proceed to Task 11.

---

## Task 11: PAUSE 2 — full gameplay

**Files:** none (manual verification)

**Purpose:** Full §13 acceptance matrix from the spec — multi-pole grid, multiple generators, multiple consumers, disconnection/split scenarios, save mid-operation.

- [ ] **Step 1: Launch game**

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9"
```

- [ ] **Step 2: User builds and verifies the acceptance matrix**

Acceptance matrix (spec section 13):

1. ✅ All 3 building types placeable from "Power" hotbar category
2. ✅ Two poles within 5 tiles auto-connect (wires visible between them)
3. ✅ Two poles 6+ tiles apart do NOT connect (no wire)
4. ✅ Water wheel near water shows `output_active = true` (wheel rotates); away from water → idle
5. ✅ Lamp adjacent to wheel + pole = bright; lamp on isolated network = dark
6. ✅ Brownout test: 1 wheel + 10+ lamps → all lamps dim (linear scaling visible)
7. ✅ Disconnect by removing bridging pole → network splits, downstream lamps go dark
8. ✅ Q-inspect on each building type shows network ID + supply/demand/satisfaction correctly
9. ✅ Save mid-operation → reload → all 3 building types preserved, network rebuilt correctly

- [ ] **Step 3: User reports PASS or FAIL**

If FAIL on any item: investigate. Possible deep bugs that headless tests missed:
- Item 6 (brownout linear scaling): if lamps all stay full bright, satisfaction isn't being read by `draw()`. Check `state.satisfaction` propagation.
- Item 7 (split): if downstream lamps stay bright after pole removal, dirty-flag not firing on `remove_building_at`.
- Item 9 (save mid-op): if reload corrupts wheel state, check `wheel_rotation` serialization.

- [ ] **Step 4: User confirms PAUSE 2 PASS**

Wait for explicit user signal (e.g., "all good", "PAUSE 2 PASS"). Do NOT proceed to ship without explicit approval.

---

## Task 12: Ship — PROJECT_LOG + NOTES + tag + push

**Files:**
- Modify: `PROJECT_LOG.md` (prepend session entry)
- Modify: `NOTES.md` (add Electricity Arc tracker + lessons earned this session)

- [ ] **Step 1: Prepend PROJECT_LOG entry**

Open `PROJECT_LOG.md`. Insert a new entry at the top (after file header, before the previous most-recent entry). Use this template:

```markdown
---

## Electricity Arc Session 1 — Electricity Foundation

**Date:** 2026-05-15
**Tag:** `session-electricity-foundation`
**Save:** v18 (no schema bump — append-only enum + .get() defaults + network rebuild on load)

First session of a new major arc. Foundation only — power network module, Power Pole connector, Water Wheel generator, Electric Lamp test consumer. Linear satisfaction `min(1.0, supply / max(1, demand))` locked as the consumer interface contract for the entire arc.

### What shipped

**Production code:**
- 3 new building types: POWER_POLE (1×1, walkable, no state), WATER_WHEEL (2×2, requires water adjacency, MAX_OUTPUT=10, supports_direction), ELECTRIC_LAMP (1×1, DEMAND=1, brightness modulates by satisfaction)
- `scripts/world/power_network.gd` — pure-logic module with BFS topology, supply/demand aggregation, linear satisfaction computation, public query API
- `scripts/world/grid_world.gd` — new dict members (`_pole_component`, `_component_supply`, `_component_demand`, `_component_satisfaction`), `mark_power_network_dirty()`, `power_satisfaction_at(pos)` wrapper, dirty-flag hooks in `place_building` + `remove_building_at`, pre-tick orchestrator in `_on_tick`, `_draw_power_wires` helper
- Wires drawn as golden (powered) or dark brown (dead) lines between in-range same-component poles
- Hotbar "Power" category with 3 slots

**Tests:**
- NEW `scripts/tests/test_power_network.gd` with 10 internal sub-cases: topology (1-5), generator joins network (6), consumer joins network (7), supply sufficient (8), brownout (9), save round-trip (10)
- Runner count: 34 → 35

### Decisions

- **Q1 — CORRECTION via Design Brief Verification (4th catch):** Brief leaned (c) per-pole `network_id` field. Code citation at `grid_world.gd:475-565` proves precedent is (a) graph + dirty-flag + grid_world-level state maps. Mirror that pattern exactly. Poles have empty state; network is computed property of the world.
- **Q2 — Connection range: 5 tiles Chebyshev.** Single pole tier this session. Parametric `RANGE_BY_TYPE` table pattern reserved for Session 3.
- **Q3 — Building-network association via `Buildings.all_edge_cells()` perimeter scan.** Mirrors `fluid_available_for_building`. Lex-first iteration order resolves the "adjacent to 2 networks" ambiguity.
- **Q4 — LINEAR satisfaction scaling (user override of my recommendation).** Each network has `satisfaction: float ∈ [0, 1]`. Consumers scale throughput/brightness. **Arc-wide contract**: future electric processors apply `1.0 / max(0.1, satisfaction)` multiplier to their cycle ticks.
- **Q5 — Two-pass per-tick.** `grid_world._on_tick` pre-pass calls `PowerNetwork.update_supply_demand` before the building tick loop. Consumer ticks then read up-to-date satisfaction.
- **Save schema: NO bump.** Append-only enum + `.get(field, default)` for new state fields + network rebuilt on load via dirty flag. Stays at v18.

### Lessons

- **Design Brief Verification protocol now at 4 catches** across this multi-session run: Cluster A Task 14 (refuse-clamp semantic conflation), Inserter Session 3 Q4 (REACH belongs in accessors not tick), Inserter Session 3 Task 6 (5 API mismatches), Electricity Foundation Q1 (per-pole field vs graph+dirty-flag pattern). 100% of conceptual errors caught by code-citation verification. **Protocol is earning compound value across sessions.**
- **Linear satisfaction as arc-wide contract**: the v1 lamp is binary-visual but the satisfaction model is linear — defers nothing. When Session 4 adds throughput consumers (electric smelter, electric drill), the `1.0 / max(0.1, satisfaction)` multiplier slots in cleanly. Single formula across all electric buildings.
- **Tick ordering subtlety**: generator's `output_active` is set during its own tick, but the pre-pass `update_supply_demand` runs BEFORE the building tick loop. First tick after placement has supply=0; second tick has correct supply. Acceptable for v1; refine in Session 2 if it surfaces.
- **Tests for foundation arc deserve dedicated file**: `test_power_network.gd` parallel to `test_fluid_network.gd`. Future sessions append sub-cases or add adjacent test files; no risk of one giant test file.
```

- [ ] **Step 2: Update NOTES.md — add Electricity Arc tracker**

Open `NOTES.md`. Find an appropriate section (after the "Inserter Arc" entry is a good spot since electricity is the natural next major arc). Insert:

```markdown

---

## Electricity Arc — 1 of N sessions shipped

**Status:** Session 1 (foundation) shipped. Linear satisfaction model locked as arc-wide consumer interface contract. Future sessions extend the parametric tier shape.

**Shipped:**
- **Session 1 (`session-electricity-foundation`)** — POWER_POLE + WATER_WHEEL + ELECTRIC_LAMP + PowerNetwork module (BFS + dirty-flag mirroring fluid pattern). Linear satisfaction `min(1.0, supply / max(1, demand))` per component. Wire rendering between in-range same-component poles. Hotbar "Power" category. 10-sub-case dedicated test file `test_power_network.gd`. Save schema unchanged at v18.

**Queued (re-plan each at session start):**
- **Session 2 — More Generators + Accumulator.** Windmill (wind direction adjacency), Steam Engine (fuel-powered), Solar Panel (daylight-dependent), Accumulator (battery storage smooths supply/demand over time). DATA entries + Burner integration for Steam.
- **Session 3 — Power Pole Tiers.** Medium pole + substation. `RANGE_BY_TYPE` parametric table on power_network.gd. Reuses BFS — only the range lookup changes.
- **Session 4 — Electric Processors.** Electric variants of smelter, drill. First consumers using the `1.0 / max(0.1, satisfaction)` cycle-multiplier contract.
- **Session 5 — Electric Inserters (closes Inserter Arc).** Combines reach + speed + electric power axes. Reuses Inserter parametric tables.

**Cross-cutting contracts:**
- **Consumer interface (locked in Session 1)**: every electric consumer reads `world.power_satisfaction_at(b.anchor)`. Lamps modulate brightness; processors multiply cycle_ticks by `1.0 / max(0.1, satisfaction)`. Single formula across the arc.
- **Network identity**: component IDs are dynamic labels, NOT stable references. Users identify networks by topology, not ID. Don't persist component IDs.
- **Save**: only building positions persist. Network is rebuilt on load via dirty flag.

```

If the user wants additional working-protocol entries earned during the session (e.g., new tooling caveats or implementer-brief patterns), append those at appropriate spots in NOTES.

- [ ] **Step 3: Final test run**

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `35 passed, 0 failed`.

- [ ] **Step 4: Commit ship entry**

```bash
git add PROJECT_LOG.md NOTES.md
git commit -m "$(cat <<'EOF'
Ship session-electricity-foundation: PROJECT_LOG entry + NOTES updates

PROJECT_LOG: full session entry — what shipped (3 building types, new
PowerNetwork module, grid_world hooks, wire rendering, hotbar Power
category, dedicated test file), Q1-Q5 decisions (Q1 corrected via
Design Brief Verification 4th catch, Q4 user override locking linear
satisfaction as arc-wide contract), 4 lessons (DBV protocol at 4
catches, linear satisfaction earns its place, tick-ordering subtlety,
test file precedent).

NOTES: Electricity Arc tracker added (Session 1 of N shipped), future
sessions queued (Session 2: more generators + accumulator; Session 3:
pole tiers; Session 4: electric processors; Session 5: electric
inserters — closes Inserter Arc). Cross-cutting contracts locked:
consumer interface formula, network-identity discipline, save
rebuild-on-load.

Final test count: 35/35 PASS (was 34/34; +1 new test file
test_power_network.gd with 10 internal sub-cases).
EOF
)"
```

- [ ] **Step 5: Tag commit**

```bash
git tag session-electricity-foundation
git log --oneline -1
git tag --list | grep electricity
```

Expected:
- `git log` shows the ship commit
- `git tag --list | grep electricity` shows `session-electricity-foundation`

- [ ] **Step 6: Push branch + tag**

```bash
git push origin claude/silly-bardeen-3279e9
git push origin session-electricity-foundation
```

Expected:
- Branch push: existing tracking branch update with N new commits
- Tag push: `* [new tag] session-electricity-foundation -> session-electricity-foundation`

- [ ] **Step 7: Verify on origin**

```bash
git ls-remote origin refs/heads/claude/silly-bardeen-3279e9 refs/tags/session-electricity-foundation
```

Expected: both refs point to the same ship commit SHA.

- [ ] **Step 8: Report to user**

Report: ship commit SHA, tag pushed, test count (34 → 35), total commits this session, total tag count.

---

## Self-review (writing-plans skill, completed at plan-write time)

**Spec coverage:**

- Spec §1 (context, future arc sessions): future sessions documented in PROJECT_LOG ship entry (Task 12) ✓
- Spec §2 (locked scope in/out): each task corresponds to a scope item; out-of-scope items NOT addressed in any task ✓
- Spec §3 (methodology layering): subagent triad applied per task as in plan header ✓
- Spec §4 (Q1-Q5 decisions): Q1 in Tasks 2+3, Q2 in Task 2 (POLE_RANGE constant), Q3 in `_adjacent_component_id` Task 2, Q4 in Task 7 with sub-cases 8/9, Q5 in Task 7 ✓
- Spec §5 (buildings: pole/wheel/lamp): Tasks 3, 5, 6 respectively ✓
- Spec §6 (PowerNetwork module): Task 2 ✓
- Spec §7 (wire rendering): Task 4 ✓
- Spec §8 (Q-inspect info_lines): folded into each building's create-file step (Tasks 3, 5, 6) ✓
- Spec §9 (no save bump): Task 9 sub-case (10) validates ✓
- Spec §10 (10 sub-cases): distributed across Tasks 3 (1-5), 5 (6), 6 (7), 7 (8-9), 9 (10) ✓
- Spec §11 (touchpoint inventory 9 files): all 9 files appear in the file map at plan start ✓
- Spec §12 (implementation order): reflected in Task 1-12 sequence ✓
- Spec §13 (validation criteria): items reflected in PAUSE 2 acceptance matrix (Task 11) ✓
- Spec §14 (anti-scope-creep reminders): documented in spec but no task — that's the right place ✓

**Placeholder scan:** No TBD / TODO / "similar to Task N" / "implement appropriately" patterns. Each task has complete code blocks.

**Type consistency:**
- `PowerNetwork.rebuild_topology(world)`, `PowerNetwork.update_supply_demand(world)`, `PowerNetwork.power_satisfaction_at(world, pos)`, `PowerNetwork.network_id_at(world, pos)` — used consistently across tasks
- `Buildings.Type.POWER_POLE` / `WATER_WHEEL` / `ELECTRIC_LAMP` — consistent enum identifiers
- `WaterWheel.MAX_OUTPUT` = 10, `ElectricLamp.DEMAND` = 1 — used consistently in tests and module logic
- `world._pole_component`, `_component_supply`, `_component_demand`, `_component_satisfaction`, `_power_network_dirty` — consistent across grid_world.gd and power_network.gd

No issues found. Plan ready for execution.
