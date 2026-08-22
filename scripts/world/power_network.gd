class_name PowerNetwork
extends RefCounted

## Power network resolver — graph + dirty-flag pattern.
##
## Mirrors the fluid-network resolver in grid_world.gd. Poles of every
## tier form components via BFS over Chebyshev adjacency, at the PER-TIER
## range in POLE_RANGE_BY_TYPE (basic 3, medium 6, substation 11) under the
## either-reaches rule in poles_connected(). Generators CARDINALLY TOUCHING a
## pole of any tier contribute supply (_adjacent_component_id); consumers
## anywhere in a pole's per-tier supply area contribute demand
## (_supply_component_id). Each component has a linear
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
## TWO CACHES share that dirty flag and are rebuilt together by
## rebuild_topology: world._pole_component (anchor -> component id) and
## world._pole_cells (any pole footprint cell -> that pole's anchor). Anything
## that repopulates world.buildings behind place_building's back has to mark
## the network dirty or BOTH go stale — see GridWorld.mark_power_network_dirty
## and its caller at the end of SaveSystem.load_game's world-mutation section.

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
# WIRED UP as of Task 5. Both consumer paths — power_satisfaction_at and
# _supply_component_id — resolve through _covering_component_id, which reads
# this table per candidate pole. Lookup miss returns SUPPLY_RADIUS_DEFAULT, so
# a future tier that forgets its row projects the basic pole's area rather
# than none at all.
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

## Widest supply radius across all pole tiers — the consumer-side scan box
## size. Derived from the table rather than hardcoded so it cannot drift from
## it. Its one caller is _covering_component_id, which sizes its box to this
## and then filters each candidate against that pole's OWN radius, because the
## consumer does not know what tier will answer.
##
## Deliberately UNCACHED. The plan suggested memoising into a static var; that
## is three iterations of a const Dictionary, called once per consumer scan
## that then does up to 81 cell checks, so the cache would have paid for
## nothing and would have been this module's only mutable static — the one
## piece of state a test could leave dirty for the next test in the runner.
static func max_supply_radius() -> int:
	var m: int = SUPPLY_RADIUS_DEFAULT
	for t in SUPPLY_RADIUS_BY_TYPE:
		m = max(m, int(SUPPLY_RADIUS_BY_TYPE[t]))
	return m

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
## an invisible connection, with no test or visual signal. One predicate makes
## that unreachable.
##
## NOTHING CATCHES THE LOOSER DIRECTION EITHER, so do not read the above as
## "only one direction matters". An earlier draft of this docstring claimed
## the renderer's same-component guard caught it. It does not: both endpoints
## there come out of one poles_by_comp bucket, so their ids are equal by
## construction and the guard cannot fire under any predicate — see
## grid_world._draw_power_wires. Concretely, for TASK 7: an MST edge pass that
## skips this function and re-derives the rule has no backstop of any kind.
## Call it.
##
## RULE: EITHER-REACHES — chebyshev(a, b) <= max(range(a), range(b)).
## Symmetric, so the BFS stays an undirected flood fill and component grouping
## cannot depend on lex start order. It also mirrors the asymmetry the project
## already chose for consumers: a pole reaches OUT to things that do not reach
## back. A min() rule would cap a substation talking to basic poles at the
## basic pole's 3, making the backbone tier useless in mixed networks.
##
## ONE EXCEPTION TO THE RULE AS STATED, because the rule alone would say yes:
## a pole is NOT connected to ITSELF. chebyshev(a, a) is 0, which is within
## every range, so the arithmetic would return true. rebuild_topology's BFS
## depends on the false — it iterates all of pole_anchors including the pole
## it is expanding from, with no self-skip guard, and relies on this to avoid
## re-queueing it.
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
## either-reaches), populates world._pole_component[anchor] = comp_id AND
## world._pole_cells[footprint cell] = anchor. Clears
## supply/demand/satisfaction (they're recomputed by update_supply_demand).
##
## Deterministic via lex-sorted starting points (matches fluid network).
static func rebuild_topology(world) -> void:
	world._pole_component.clear()
	world._pole_cells.clear()
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
			# Index EVERY footprint cell back to this anchor. Consumer
			# queries hit raw cells and cannot know a 2x2 substation's
			# anchor, so without this map a multi-cell pole answers only
			# from its top-left cell and its supply box sits off-centre.
			var pole_fp: Vector2i = Buildings.footprint_of(world.buildings[p].type)
			for fy in range(pole_fp.y):
				for fx in range(pole_fp.x):
					world._pole_cells[p + Vector2i(fx, fy)] = p
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
	# EVERY pole tier, via Buildings.POLE_TYPES — the same set rebuild_topology
	# walks. Before Task 5 this read `nb.type != Buildings.Type.POWER_POLE`, so
	# a generator or accumulator flush against a medium pole or a substation
	# resolved to -1 and was skipped by update_supply_demand's Stage 1: zero
	# supply, while the pole was a network member, was drawn with wires, and
	# showed no error anywhere.
	#
	# MULTI-CELL POLES WORK HERE WITHOUT A _pole_cells LOOKUP, and it is worth
	# saying why, because the consumer paths DO need one. The scan walks the
	# GENERATOR's edge ring and hands each cell to world.building_at, which
	# resolves through `occupied` — so a cell belonging to a substation's
	# south-east quarter still returns the substation Building, whose `.anchor`
	# is the key _pole_component holds. The consumer side has no Building to
	# start from, only a raw cell, which is what _pole_cells exists for.
	for cell in Buildings.all_edge_cells(b.type, b.anchor):
		if not world.has_building_at(cell):
			continue
		var nb: Building = world.building_at(cell)
		if nb == null or not Buildings.POLE_TYPES.has(nb.type):
			continue
		if world._pole_component.has(nb.anchor):
			return int(world._pole_component[nb.anchor])
	return -1

## Find the component ID of a pole covering any cell of building `b`'s
## footprint. Returns -1 if nothing covers it. Used by CONSUMERS (lamps,
## electric inserters) — Factorio-style wireless supply. A basic pole at (5,5)
## with radius 1 covers consumers anywhere in the 3×3 area (4,4)..(6,6); the
## 2x2 substation with radius 4 covers ten cells per axis, not nine.
##
## Every cell decision is delegated to _covering_component_id, which is the
## single source of truth for the per-tier radius, the footprint projection
## and the nearest-pole tie-break. This function adds exactly one thing on top
## of it: the walk over the CONSUMER's own footprint, so a multi-cell consumer
## is powered when any of its cells is covered.
##
## FIRST COVERED FOOTPRINT CELL WINS, and it stops there. The nearest-pole
## tie-break inside _covering_component_id is per-cell, so a 2x2 consumer
## straddling two components takes whichever component covers the first cell
## this walk reaches. That order is ROW-MAJOR — `fy` outer, `fx` inner — and
## deliberately NOT the x-major lex order rebuild_topology sorts its pole
## anchors by (see its sort_custom). Do not call this one "lex-first": the two
## orders disagree for any footprint wider and taller than one cell, and the
## only reason that costs nothing today is that every consumer in the project
## is 1x1, which makes this loop a single iteration. A 2x2 consumer would make
## the difference real. Same documented v1 simplification
## _adjacent_component_id carries.
static func _supply_component_id(world, b: Building) -> int:
	var fp: Vector2i = Buildings.footprint_of(b.type)
	for fy in range(fp.y):
		for fx in range(fp.x):
			var comp_id: int = _covering_component_id(world, b.anchor + Vector2i(fx, fy))
			if comp_id >= 0:
				return comp_id
	return -1

## Public query: is the position within a pole's supply radius in a
## powered (sat > 0) network? Used for boolean checks. Most consumers
## should use power_satisfaction_at() instead.
static func is_powered_at(world, pos: Vector2i) -> bool:
	return power_satisfaction_at(world, pos) > 0.0

## Public query: per-tile satisfaction for consumers. Returns 0.0 if no
## pole covers `pos`. Returns [0.0, 1.0] otherwise.
## Consumers call this from their tick to drive brightness / throughput.
##
## A thin wrapper over _covering_component_id, which is the ONE place the
## "which pole covers this cell" rule lives. _supply_component_id calls the
## same function, so the two consumer-side paths cannot answer differently
## about the same cell — before Task 5 they could and did, and a lamp beside a
## medium pole lit up while contributing no demand.
static func power_satisfaction_at(world, pos: Vector2i) -> float:
	if world._power_network_dirty:
		rebuild_topology(world)
	var comp_id: int = _covering_component_id(world, pos)
	if comp_id < 0:
		return 0.0
	return float(world._component_satisfaction.get(comp_id, 0.0))

## Resolve which pole component covers `pos`, applying the nearest-pole
## tie-break. Returns -1 if nothing covers it.
##
## THE SCAN IS CONSUMER-OUTWARD and sized to max_supply_radius(), the widest
## radius any tier has, because the cell being asked about cannot know which
## tier might be covering it. Each candidate is then filtered against ITS OWN
## radius, so a basic pole found at distance 3 in the box is rejected while a
## substation at the same distance is not. Sizing the box to the widest tier
## is what makes that possible: if a pole covers `pos` at all, its nearest
## footprint cell is within its own radius, which is within the maximum, so
## that cell is inside the box.
##
## DISTANCE IS MEASURED TO THE MATCHED CELL, not to the anchor. world
## ._pole_cells maps every footprint cell back to its owner, so a 2x2
## substation is found from all four of its cells and its supply area is
## centred on its body rather than hanging off its top-left corner. That is
## the (2r+2)-per-axis coverage SUPPLY_RADIUS_BY_TYPE's docstring describes —
## ten cells per axis at radius 4, not nine.
##
## THE TIE-BREAK IS CURRENTLY UNOBSERVABLE, AND TASK 6 NEEDS TO KNOW THAT.
## The scan cannot early-return on the first hit *in principle*, because a
## nearer pole may appear later in the scan order — so it evaluates every
## candidate in the box and picks. But which candidate it picks cannot change
## the ANSWER today, because of this invariant:
##
##   ANY TWO POLES COVERING THE SAME CELL ARE ALREADY IN THE SAME COMPONENT.
##
## Proof. If A and B both cover `pos` then, Chebyshev being a metric and
## _pole_distance being footprint-to-footprint, the triangle inequality gives
## _pole_distance(A, B) <= dist(A, pos) + dist(pos, B) <= rA + rB. And every
## tier pair clears its own wire range with room to spare:
##
##   pair             rA + rB   max(range)
##   basic  + basic     1+1=2       3
##   basic  + medium    1+2=3       6
##   medium + medium    2+2=4       6
##   basic  + sub       1+4=5      11
##   medium + sub       2+4=6      11
##   sub    + sub       4+4=8      11
##
## So poles_connected() is true for every covering pair, the BFS put them in
## one component, and _pole_component[anchor] is the same integer whichever one
## wins. MUTATION RUN: replacing this whole block with a first-hit `return`
## leaves the suite at 45 passed, 0 failed.
##
## WHAT WOULD BREAK IT: a tier pair with rA + rB > max(range_A, range_B) — in
## the same-tier form, any tier whose supply radius exceeds HALF its own wire
## range. None of the three does (2 vs 3, 4 vs 6, 8 vs 11). Add one that does
## and this tie-break becomes load-bearing immediately, with nothing in the
## suite to notice it had been dead.
##
## DO NOT restore the early return on the strength of the above alone. It is
## an 81-cell scan whose cost Task 6 is about to measure, and the trade —
## exhaustive-but-dead versus fast-but-fragile — is a decision for that gate,
## with the measured number in hand. This docstring exists so whoever stands
## at that gate has the invariant in front of them.
static func _covering_component_id(world, pos: Vector2i) -> int:
	var radius: int = max_supply_radius()
	var best_comp: int = -1
	# radius + 1 is one past the largest distance the box can produce (dx and
	# dy are both bounded by radius, so dist = max(|dx|, |dy|) <= radius), so
	# it is a sentinel the first candidate always beats.
	var best_dist: int = radius + 1
	var best_radius: int = -1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell: Vector2i = pos + Vector2i(dx, dy)
			if not world._pole_cells.has(cell):
				continue
			var anchor: Vector2i = world._pole_cells[cell]
			# Defensive: confirm the anchor really still holds a pole. These
			# three probes CANNOT fire while the caches agree with
			# world.buildings — rebuild_topology clears and repopulates
			# _pole_cells and _pole_component on the same two lines, from a
			# pole_anchors list it filtered out of world.buildings by
			# POLE_TYPES. They are kept because "the caches agree" is an
			# assumption this repo has already broken once: audit finding #1
			# was world.buildings being cleared and rewritten with no dirty
			# flag, which leaves exactly these maps pointing at anchors that no
			# longer hold poles. Cheap insurance on a path that already costs
			# up to 81 cell probes.
			if not world._pole_component.has(anchor):
				continue
			var pole: Building = world.buildings.get(anchor, null)
			if pole == null or not Buildings.POLE_TYPES.has(pole.type):
				continue
			var dist: int = max(abs(dx), abs(dy))
			var r: int = supply_radius(pole.type)
			if dist > r:
				continue
			# Nearest wins, then the larger supply radius — and then, when a
			# pair ties on BOTH, whichever the box reached first, because the
			# comparison below is strict. So the real third key is the dy-then-
			# dx scan order above. It is deterministic only for as long as that
			# walk is: swapping the box scan for an iteration over a pole list
			# (the obvious Task 6 optimisation) silently changes which pole
			# wins a two-way tie. Harmless today — see the invariant in the
			# docstring, which makes every covering pole answer the same
			# component — but do not read the first two keys as the whole rule.
			if dist < best_dist or (dist == best_dist and r > best_radius):
				best_dist = dist
				best_radius = r
				best_comp = int(world._pole_component[anchor])
	return best_comp

## Public query: network ID (component ID) of the pole at `pos`, or -1
## if not a pole or not in network. Used by Q-inspect info_lines.
##
## `pos` is a pole ANCHOR, not any footprint cell — this reads _pole_component
## directly rather than going through _pole_cells. Every caller passes
## `b.anchor` (PowerPole.info_lines) or a 1x1 pole's own position (the tests),
## so the two are the same cell for them. A caller holding a raw cell that
## might belong to a substation's other three quarters wants
## _covering_component_id, or world.building_at(cell).anchor first.
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
