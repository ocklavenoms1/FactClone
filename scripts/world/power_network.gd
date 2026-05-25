class_name PowerNetwork
extends RefCounted

## Power network resolver — graph + dirty-flag pattern.
##
## Mirrors the fluid-network pattern at grid_world.gd:475-565. Power poles
## form components via BFS over 5-tile Chebyshev adjacency. Generators
## adjacent to a pole will contribute supply; consumers will contribute
## demand (added in Task 7). Each component will have a linear
## satisfaction ratio in [0.0, 1.0]:
##
##   satisfaction = min(1.0, supply / max(1, demand))
##
## Consumer interface contract (arc-wide, locked at Session 1 spec):
## every electric consumer reads world.power_satisfaction_at(b.anchor)
## and scales its throughput or visual feedback accordingly. Lamps
## modulate brightness; future processors (Sessions 4+) multiply
## cycle_ticks by 1.0 / max(0.1, sat).
##
## All state lives on the world (Dictionary maps); poles have empty state.
## On placement/removal of pole/generator/consumer, world calls
## `mark_dirty(world)`. Next query triggers a rebuild.
##
## TASK 2 SCOPE: topology + queries only. update_supply_demand lands in
## Task 7 once WATER_WHEEL and ELECTRIC_LAMP enum entries exist (Tasks 5+6).

# Maximum Chebyshev distance for pole-to-pole auto-connection.
# Reduced from 5 to 3 at PAUSE 1 user request: 5-tile range produced too
# many in-range pairs in dense layouts (K4 with 6 wires for 4 poles),
# even though that was the locked mesh-within-network rule. Tighter
# range forces denser pole placement but produces visually cleaner
# topology — direct neighbors only, no long diagonals that "skip over"
# intermediate poles.
const POLE_RANGE: int = 3

# Pole's supply-area Chebyshev radius for CONSUMERS (Factorio-style).
# A consumer at any cell within SUPPLY_RADIUS Chebyshev distance of a
# pole receives power from that pole's component. Radius 1 = 3×3 area
# centered on pole (8 surrounding cells + the pole's own cell). Lamps,
# future electric processors, etc. all use this. GENERATORS
# (WATER_WHEEL, etc.) intentionally use strict cardinal adjacency
# instead — see _adjacent_component_id. Asymmetric by design (PAUSE 1
# user decision): consumers powered wirelessly within radius, generators
# must touch a pole.
const SUPPLY_RADIUS: int = 1

# 4-directional adjacency for building-to-pole association. Local copy —
# grid_world.gd has its own `_CARDINALS` at line 471; kept separate so
# PowerNetwork stays self-contained and doesn't need to reach into
# grid_world for a private constant.
const _CARDINALS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Mark the power network as needing a topology rebuild on next query.
## Called by grid_world on placement/removal of poles, generators, or
## consumers.
##
## NOTE: `world` is intentionally untyped across this module. Adding
## `world: GridWorld` would create a cyclic class_name dependency
## (grid_world.gd already preloads/references PowerNetwork via
## `power_satisfaction_at` wrapper). Untyped duck-typing is the
## established Godot 4 escape hatch for this loop; same pattern used
## by Buildings.tick_one(b, world) etc.
static func mark_dirty(world) -> void:
	world._power_network_dirty = true

## Rebuild the topology: walks all poles, BFS over 5-tile Chebyshev
## adjacency, populates world._pole_component[pos] = comp_id. Clears
## supply/demand/satisfaction (they're recomputed by update_supply_demand
## in Task 7).
##
## Deterministic via lex-sorted starting points (matches fluid network).
static func rebuild_topology(world) -> void:
	world._pole_component.clear()
	world._component_supply.clear()
	world._component_demand.clear()
	world._component_satisfaction.clear()
	# Electricity Session 2: clear the 3-stage flow's intermediate dicts too.
	# Currently benign (update_supply_demand only iterates unique_comps built
	# from current _pole_component, so stale entries are unreachable) but
	# prevents a class of future bugs if downstream code iterates these dicts
	# directly. Symmetric with the original 4 dict clears.
	world._component_raw_supply.clear()
	world._component_accumulators.clear()
	world._component_accumulator_supply.clear()
	world._component_accumulator_drain.clear()

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
## building tick loop. 3-stage flow (extended at Electricity Session 2):
##
## Stage 1: walk all buildings. Classify by type:
##   - Generators (WATER_WHEEL, WINDMILL, STEAM_GENERATOR) → sum MAX_OUTPUT
##     into _component_raw_supply when output_active.
##   - Consumers (ELECTRIC_LAMP) → sum DEMAND into _component_demand.
##   - Accumulators (ACCUMULATOR) → register in _component_accumulators
##     list per component (no supply/demand contribution yet).
##
## Stage 2: per component, compute excess = raw_supply - demand. For each
## accumulator in the component:
##   - excess > 0: charge by min(excess_per_acc, MAX_CHARGE_RATE,
##     MAX_CAPACITY - acc.charge). Mutate acc.state.charge.
##     Track total _component_accumulator_drain (acts as additional
##     "consumption" — units siphoned from the network into storage).
##   - excess < 0: discharge by min(deficit_per_acc, MAX_DISCHARGE_RATE,
##     acc.charge). Mutate acc.state.charge. Track total
##     _component_accumulator_supply (acts as additional "supply" —
##     units fed from storage into the network).
##   - excess == 0: no-op.
##
## Stage 3: effective_supply = raw_supply + accumulator_supply -
## accumulator_drain. satisfaction = min(1.0, effective_supply / max(1, demand)).
##
## State mutation in pre-pass justified: accumulator charge IS network
## state. Consumer interface contract unchanged — world.power_satisfaction_at
## returns post-accumulator satisfaction; lamps modulate brightness identically;
## future Session 4+ processors apply 1.0 / max(0.1, satisfaction) identically.
static func update_supply_demand(world) -> void:
	if world._power_network_dirty:
		rebuild_topology(world)
	# Deduplicate component IDs — _pole_component.values() yields per-pole,
	# so a component with N poles would otherwise be visited N times, which
	# would multiply accumulator charge/discharge mutations in Stage 2. Use a
	# Dictionary-as-set keyed by comp_id to iterate each component exactly once.
	var unique_comps: Dictionary = {}
	for comp_id in world._pole_component.values():
		unique_comps[comp_id] = true
	# Reset all per-component accumulators.
	for comp_id in unique_comps:
		world._component_supply[comp_id] = 0
		world._component_demand[comp_id] = 0
		world._component_raw_supply[comp_id] = 0
		world._component_accumulators[comp_id] = []
		world._component_accumulator_supply[comp_id] = 0.0
		world._component_accumulator_drain[comp_id] = 0.0

	# ----- Stage 1: classify and sum raw_supply + demand -----
	for anchor in world.buildings:
		var b: Building = world.buildings[anchor]
		if b.type == Buildings.Type.WATER_WHEEL:
			var gen_comp: int = _adjacent_component_id(world, b)
			if gen_comp < 0:
				continue
			if bool(b.state.get("output_active", false)):
				world._component_raw_supply[gen_comp] = int(world._component_raw_supply.get(gen_comp, 0)) + WaterWheel.MAX_OUTPUT
		elif b.type == Buildings.Type.WINDMILL:
			var gen_comp_w: int = _adjacent_component_id(world, b)
			if gen_comp_w < 0:
				continue
			if bool(b.state.get("output_active", true)):
				world._component_raw_supply[gen_comp_w] = int(world._component_raw_supply.get(gen_comp_w, 0)) + Windmill.MAX_OUTPUT
		elif b.type == Buildings.Type.STEAM_GENERATOR:
			var gen_comp_s: int = _adjacent_component_id(world, b)
			if gen_comp_s < 0:
				continue
			if bool(b.state.get("output_active", false)):
				world._component_raw_supply[gen_comp_s] = int(world._component_raw_supply.get(gen_comp_s, 0)) + SteamGenerator.MAX_OUTPUT
		elif b.type == Buildings.Type.ELECTRIC_LAMP:
			var con_comp: int = _supply_component_id(world, b)
			if con_comp < 0:
				continue
			world._component_demand[con_comp] = int(world._component_demand.get(con_comp, 0)) + ElectricLamp.DEMAND
		elif b.type == Buildings.Type.ACCUMULATOR:
			var acc_comp: int = _adjacent_component_id(world, b)
			if acc_comp < 0:
				continue
			world._component_accumulators[acc_comp].append(b)

	# ----- Stage 2: accumulator charge/discharge per component -----
	for comp_id in unique_comps:
		var raw_supply: int = int(world._component_raw_supply.get(comp_id, 0))
		var demand: int = int(world._component_demand.get(comp_id, 0))
		var accumulators: Array = world._component_accumulators.get(comp_id, [])
		if accumulators.is_empty():
			continue
		var excess: int = raw_supply - demand
		var acc_count: int = accumulators.size()
		if excess > 0:
			# Charge: distribute excess evenly across accumulators.
			var excess_per_acc: float = float(excess) / float(acc_count)
			for acc in accumulators:
				var current_charge: float = float(acc.state.get("charge", 0.0))
				var capacity_remaining: float = float(Accumulator.MAX_CAPACITY) - current_charge
				var delta: float = min(excess_per_acc, float(Accumulator.MAX_CHARGE_RATE), capacity_remaining)
				if delta <= 0.0:
					continue
				acc.state["charge"] = current_charge + delta
				world._component_accumulator_drain[comp_id] = float(world._component_accumulator_drain.get(comp_id, 0.0)) + delta
		elif excess < 0:
			# Discharge: distribute deficit evenly across accumulators.
			var deficit: int = -excess
			var deficit_per_acc: float = float(deficit) / float(acc_count)
			for acc in accumulators:
				var current_charge_d: float = float(acc.state.get("charge", 0.0))
				var delta_d: float = min(deficit_per_acc, float(Accumulator.MAX_DISCHARGE_RATE), current_charge_d)
				if delta_d <= 0.0:
					continue
				acc.state["charge"] = current_charge_d - delta_d
				world._component_accumulator_supply[comp_id] = float(world._component_accumulator_supply.get(comp_id, 0.0)) + delta_d

	# ----- Stage 3: effective_supply + satisfaction -----
	# Per Foundation comment block: dem == 0 → satisfaction 1.0 (benign;
	# no consumer reads sat when no consumer exists). Reaffirmed at Task 7
	# Cluster B review.
	for comp_id in unique_comps:
		var raw: int = int(world._component_raw_supply.get(comp_id, 0))
		var acc_sup: float = float(world._component_accumulator_supply.get(comp_id, 0.0))
		var acc_drain: float = float(world._component_accumulator_drain.get(comp_id, 0.0))
		var effective_supply: float = float(raw) + acc_sup - acc_drain
		# _component_supply exposes effective supply for Q-inspect and existing
		# supply_for() API — preserves Foundation contract for consumers.
		world._component_supply[comp_id] = int(round(effective_supply))
		var dem: int = int(world._component_demand.get(comp_id, 0))
		var sat: float = 1.0 if dem == 0 else min(1.0, effective_supply / float(dem))
		world._component_satisfaction[comp_id] = sat

## Find the component ID of any pole CARDINALLY ADJACENT (4-direction,
## 1-tile) to building `b`. Returns -1 if no adjacent pole. Used by
## GENERATORS (water wheel etc.) which must touch a pole to feed the
## network. Lex-first iteration order resolves the ambiguity when a
## building borders TWO different networks (documented v1 simplification).
##
## Consumers should use _supply_component_id instead — Factorio-style
## wireless supply area (PAUSE 1 user decision).
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

## Find the component ID of any pole within SUPPLY_RADIUS Chebyshev
## distance of any cell of building `b`'s footprint. Returns -1 if no
## pole in supply area. Used by CONSUMERS (lamps etc.) — Factorio-style
## wireless supply. Pole at (5,5) with SUPPLY_RADIUS=1 covers consumers
## anywhere in the 3×3 area (4,4)..(6,6).
##
## First pole found wins (lex iteration order of pole positions).
## Defensive verification: only counts cells that are confirmed POWER_POLE
## buildings (in case _pole_component has stale entries during a rebuild).
static func _supply_component_id(world, b: Building) -> int:
	var radius: int = SUPPLY_RADIUS
	var fp: Vector2i = Buildings.footprint_of(b.type)
	# Iterate the consumer's full footprint. For each footprint cell,
	# scan the (2*radius+1)² area around it for a pole. 1×1 consumers
	# (lamps) iterate 1 cell × 9 checks = 9; 2×2 future consumers would
	# do 4 × 9 = 36 (with overlap, but the early-return on first pole
	# found makes worst case rare).
	for fy in range(fp.y):
		for fx in range(fp.x):
			var footprint_cell: Vector2i = b.anchor + Vector2i(fx, fy)
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var check_pos: Vector2i = footprint_cell + Vector2i(dx, dy)
					if not world._pole_component.has(check_pos):
						continue
					# Defensive: confirm it's actually a pole.
					if not world.has_building_at(check_pos):
						continue
					var nb: Building = world.building_at(check_pos)
					if nb == null or nb.type != Buildings.Type.POWER_POLE:
						continue
					return int(world._pole_component[check_pos])
	return -1

## Public query: is the position within SUPPLY_RADIUS of a pole in a
## powered (sat > 0) network? Used for boolean checks. Most consumers
## should use power_satisfaction_at() instead.
static func is_powered_at(world, pos: Vector2i) -> bool:
	return power_satisfaction_at(world, pos) > 0.0

## Public query: per-tile satisfaction for consumers. Returns 0.0 if no
## pole within SUPPLY_RADIUS Chebyshev. Returns [0.0, 1.0] otherwise.
## Consumers call this from their tick to drive brightness / throughput.
##
## Scans the (2*SUPPLY_RADIUS+1)² area around pos for any pole. First
## pole found wins. This is the per-position equivalent of
## _supply_component_id for 1×1 callers — lamps mostly. Multi-cell
## consumers should use _supply_component_id with their Building.
static func power_satisfaction_at(world, pos: Vector2i) -> float:
	if world._power_network_dirty:
		rebuild_topology(world)
	var radius: int = SUPPLY_RADIUS
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var n: Vector2i = pos + Vector2i(dx, dy)
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
