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
## supply/demand/satisfaction (they're recomputed by update_supply_demand
## in Task 7).
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

## Find the component ID of any pole adjacent to building `b`. Returns -1
## if no adjacent pole. Used by generators (supply) and consumers (demand)
## once they exist. Lex-first iteration order resolves the ambiguity when
## a building borders TWO different networks (documented v1 simplification).
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
