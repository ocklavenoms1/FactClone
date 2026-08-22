class_name PowerNetwork
extends RefCounted

## Power network resolver — graph + dirty-flag pattern.
##
## Mirrors the fluid-network pattern at grid_world.gd:475-565. Poles of every
## tier form components via BFS over Chebyshev adjacency, at the PER-TIER
## range in POLE_RANGE_BY_TYPE (basic 3, medium 6, substation 11) under the
## either-reaches rule in poles_connected(). Generators
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

# Per-tier maximum Chebyshev distance for pole-to-pole auto-connection.
#
# The basic pole's 3 is a PAUSE 1 user decision, reduced from 5 because
# "5-tile range produced too many in-range pairs in dense layouts (K4 with 6
# wires for 4 poles)". That complaint was about WIRE COUNT, not about reach,
# and Session 3 removes its cause in Task 7 by rendering a minimum spanning
# tree per component instead of the full mesh grid_world._draw_power_wires
# still draws today — which is why the substation can afford 11 without
# reintroducing the hairball.
#
# Lookup miss returns POLE_RANGE_DEFAULT, so a future pole tier that forgets
# its row behaves like a basic pole rather than failing to connect at all.
const POLE_RANGE_BY_TYPE: Dictionary = {
	Buildings.Type.POWER_POLE:  3,
	Buildings.Type.MEDIUM_POLE: 6,
	Buildings.Type.SUBSTATION:  11,
}
const POLE_RANGE_DEFAULT: int = 3

# Per-tier supply-area Chebyshev radius for CONSUMERS (Factorio-style
# wireless supply). Radius r is measured from the pole's FOOTPRINT, so a 1x1
# pole covers (2r+1) cells per axis and the 2x2 substation covers (2r+2) —
# anchor-r .. anchor+1+r. GENERATORS (WATER_WHEEL, etc.) intentionally use
# strict cardinal adjacency instead — see _adjacent_component_id. Asymmetric
# by design (PAUSE 1 user decision): consumers are powered wirelessly within
# the radius, generators must touch a pole.
#
# NOT YET WIRED UP. Task 4 lands the table; Task 5 lands the footprint-
# projected resolver that reads it. Until then the two consumer paths below
# (_supply_component_id, power_satisfaction_at) are still hardcoded to
# SUPPLY_RADIUS_DEFAULT — see the TEMPORARY note on each.
#
# WHY THESE STOP AT 4. The lookup is consumer-outward: a consumer scans a box
# around ITSELF and asks what poles are in it (power_satisfaction_at), because
# it cannot know in advance which tier might be covering it. That means every
# consumer pays the box of the LARGEST tier on the map, every tick, even where
# no substation exists. Cost is (2r+1)^2: radius 1 is 9 checks, radius 4 is 81,
# radius 7 would be 225. 4 is the affordability ceiling, not a balance choice.
const SUPPLY_RADIUS_BY_TYPE: Dictionary = {
	Buildings.Type.POWER_POLE:  1,
	Buildings.Type.MEDIUM_POLE: 2,
	Buildings.Type.SUBSTATION:  4,
}
const SUPPLY_RADIUS_DEFAULT: int = 1

# The widest supply radius any tier declares. Derived at first use rather than
# hardcoded so it cannot drift from the table above.
static var _max_supply_radius_cache: int = -1

## Widest supply radius across all pole tiers — the consumer-side scan box
## size. NO CALLER YET: Task 5's resolver sizes its box to this and then
## filters per-pole, because the consumer does not know what tier will answer.
## Landed here so the table and the number derived from it stay in one file.
static func max_supply_radius() -> int:
	if _max_supply_radius_cache < 0:
		var m: int = SUPPLY_RADIUS_DEFAULT
		for t in SUPPLY_RADIUS_BY_TYPE:
			m = max(m, int(SUPPLY_RADIUS_BY_TYPE[t]))
		_max_supply_radius_cache = m
	return _max_supply_radius_cache

## Wire range for one pole type.
static func pole_range(t: int) -> int:
	return int(POLE_RANGE_BY_TYPE.get(t, POLE_RANGE_DEFAULT))

## Supply radius for one pole type.
static func supply_radius(t: int) -> int:
	return int(SUPPLY_RADIUS_BY_TYPE.get(t, SUPPLY_RADIUS_DEFAULT))

## THE connection predicate — the single source of truth for "are these two
## poles wired together". Called by BOTH rebuild_topology's BFS and
## grid_world._draw_power_wires. That sharing is the entire point: these used
## to be two independent reads of one constant, and with per-type ranges two
## reads WILL diverge.
##
## The divergence is dangerous in one direction specifically. If the renderer
## is STRICTER than the BFS, poles are in one component but no wire is drawn —
## an invisible connection, with no test or visual signal. (Looser is caught by
## the renderer's same-component guard.) One predicate makes that unreachable.
##
## RULE: EITHER-REACHES — chebyshev(a, b) <= max(range(a), range(b)).
## Symmetric, so the BFS stays an undirected flood fill and component grouping
## cannot depend on lex start order. It also mirrors the asymmetry the project
## already chose for consumers: a pole reaches OUT to things that do not reach
## back. A min() rule would cap a substation talking to basic poles at the
## basic pole's 3, making the backbone tier useless in mixed networks.
static func poles_connected(world, anchor_a: Vector2i, anchor_b: Vector2i) -> bool:
	if anchor_a == anchor_b:
		return false
	var ba: Building = world.buildings.get(anchor_a, null)
	var bb: Building = world.buildings.get(anchor_b, null)
	if ba == null or bb == null:
		return false
	if not Buildings.POLE_TYPES.has(ba.type) or not Buildings.POLE_TYPES.has(bb.type):
		return false
	var reach: int = max(pole_range(ba.type), pole_range(bb.type))
	return _pole_distance(ba, bb) <= reach

## Chebyshev distance between two poles, measured FOOTPRINT to FOOTPRINT
## rather than anchor to anchor.
##
## For 1x1 poles these are identical. For the 2x2 substation they diverge in
## one direction per axis, because the anchor sits on the footprint's west/north
## edge: toward -x/-y the two metrics AGREE, while toward +x/+y anchor-to-anchor
## OVER-measures by 1 and so understates the substation's real reach. Worked:
## a substation anchored at x 12 (cells 12..13) against a 1x1 pole at x 3 reads
## 9 either way, but against one at x 16 reads 4 by anchor and 3 by footprint.
## Left uncorrected, a substation reaches further "up-left" than "down-right",
## which is invisible in tests built around a single orientation and obvious
## on screen. Footprint-to-footprint is orientation-independent.
static func _pole_distance(a: Building, b: Building) -> int:
	var fa: Vector2i = Buildings.footprint_of(a.type)
	var fb: Vector2i = Buildings.footprint_of(b.type)
	var dx: int = max(0, max(a.anchor.x - (b.anchor.x + fb.x - 1), b.anchor.x - (a.anchor.x + fa.x - 1)))
	var dy: int = max(0, max(a.anchor.y - (b.anchor.y + fb.y - 1), b.anchor.y - (a.anchor.y + fa.y - 1)))
	return max(dx, dy)

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

## Rebuild the topology: walks every pole of every tier in Buildings.POLE_TYPES,
## BFS over the shared poles_connected() predicate (per-tier Chebyshev range,
## either-reaches), populates world._pole_component[anchor] = comp_id. Clears
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

	# EVERY pole tier, not just POWER_POLE — Buildings.POLE_TYPES is the one
	# hand-maintained list, and a tier missing from it is invisible here and
	# forms no network at all (the silent failure test_pole_tiers sub-case 1
	# pins). Keys are ANCHORS: a 2x2 substation contributes one entry, and
	# _pole_distance re-derives its footprint from the type.
	var pole_anchors: Array = []
	for anchor in world.buildings:
		if Buildings.POLE_TYPES.has(world.buildings[anchor].type):
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
			# Find all poles this one is wired to. poles_connected is the
			# SHARED predicate — grid_world._draw_power_wires calls the same
			# function, so the graph the BFS builds and the graph the renderer
			# draws cannot disagree. It also rejects other == p on its own, so
			# no self-skip guard is needed here.
			for other in pole_anchors:
				if world._pole_component.has(other):
					continue
				if PowerNetwork.poles_connected(world, p, other):
					queue.append(other)
		next_id += 1

	world._power_network_dirty = false

## Per-tick orchestrator. Called from grid_world._on_tick BEFORE the
## building tick loop. 3-stage flow (extended at Electricity Session 2):
##
## Stage 1: walk all buildings. Classify by type:
##   - Generators (WATER_WHEEL, WINDMILL, STEAM_GENERATOR) → sum MAX_OUTPUT
##     into _component_raw_supply when output_active.
##   - Consumers (ELECTRIC_LAMP, ELECTRIC_INSERTER) → sum DEMAND into
##     _component_demand. Consumer draw is CONSTANT (never activity-gated)
##     — see the ELECTRIC_INSERTER arm below for why.
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
		elif b.type == Buildings.Type.ELECTRIC_INSERTER:
			# CONSUMER rule (_supply_component_id — a Chebyshev supply radius
			# around every footprint cell), same as lamps. NOT the generator/
			# accumulator rule (_adjacent_component_id), which demands a
			# touching pole.
			var ins_comp: int = _supply_component_id(world, b)
			if ins_comp < 0:
				continue
			# UNCONDITIONAL — no activity gate. This is the constant-demand
			# decision, locked at Inserter Arc Session 4 Task 5, not an
			# oversight: update_supply_demand is a PRE-PASS that runs BEFORE
			# grid_world's building tick loop, so any activity state sampled
			# here is one tick stale. Duty-cycling on it would close a
			# delayed-feedback loop — the network sizing itself to last
			# tick's activity — and lamps sharing the component would
			# visibly flicker. An idle electric inserter draws full power.
			world._component_demand[ins_comp] = int(world._component_demand.get(ins_comp, 0)) + Inserter.power_demand(b)
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

## Find the component ID of any pole within a Chebyshev supply radius of any
## cell of building `b`'s footprint. Returns -1 if no pole in supply area.
## Used by CONSUMERS (lamps etc.) — Factorio-style wireless supply. A pole at
## (5,5) with radius 1 covers consumers anywhere in the 3×3 area (4,4)..(6,6).
##
## First pole found wins (lex iteration order of pole positions).
## Defensive verification: only counts cells that are confirmed POWER_POLE
## buildings (in case _pole_component has stale entries during a rebuild).
static func _supply_component_id(world, b: Building) -> int:
	# TEMPORARY (Task 4 -> Task 5): the consumer-side scan is still sized to
	# the basic pole's radius and still takes the first pole it hits, and the
	# POWER_POLE check below still excludes the two new tiers outright. That is
	# behaviourally IDENTICAL to pre-Session-3, so the existing suite stays
	# green — but it means MEDIUM_POLE and SUBSTATION now join the network
	# without yet projecting their wider supply areas, which is why
	# test_pole_tier_rig sub-cases (2) and (4b) still read demand 30 of 40.
	# Task 5 replaces this function and power_satisfaction_at with the
	# per-pole-radius, footprint-projected resolver that reads
	# SUPPLY_RADIUS_BY_TYPE.
	var radius: int = SUPPLY_RADIUS_DEFAULT
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

## Public query: is the position within a pole's supply radius in a
## powered (sat > 0) network? Used for boolean checks. Most consumers
## should use power_satisfaction_at() instead.
static func is_powered_at(world, pos: Vector2i) -> bool:
	return power_satisfaction_at(world, pos) > 0.0

## Public query: per-tile satisfaction for consumers. Returns 0.0 if no
## pole within the supply radius. Returns [0.0, 1.0] otherwise.
## Consumers call this from their tick to drive brightness / throughput.
##
## Scans the (2*radius+1)² area around pos for any pole. First pole found
## wins. This is the per-position equivalent of _supply_component_id for 1×1
## callers — lamps mostly. Multi-cell consumers should use
## _supply_component_id with their Building.
static func power_satisfaction_at(world, pos: Vector2i) -> float:
	if world._power_network_dirty:
		rebuild_topology(world)
	# TEMPORARY (Task 4 -> Task 5): same bridge as _supply_component_id — the
	# box is still the basic pole's radius, so the wider tiers do not yet
	# project their supply areas. NOTE the one asymmetry this bridge leaves
	# behind: unlike _supply_component_id, this scan has never verified the
	# building type, and _pole_component now holds MEDIUM_POLE and SUBSTATION
	# anchors, so at radius 1 the two functions can answer differently about a
	# consumer next to a new tier. Task 5 rewrites both together and the
	# question disappears. No RIG hits it in the meantime — every pole_tier_rig
	# consumer is at Chebyshev 2 or more from the medium pole and 3 or more
	# from the substation anchor, and electric_rig places neither tier — but a
	# player who puts a lamp beside a medium pole between Task 4 and Task 5
	# will see it glow while contributing no demand.
	var radius: int = SUPPLY_RADIUS_DEFAULT
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
