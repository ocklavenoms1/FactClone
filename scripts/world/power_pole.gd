class_name PowerPole
extends RefCounted

## Power Pole — passive carrier of the electric network.
##
## Auto-connects to other poles within 5-tile Chebyshev range (POLE_RANGE
## in power_network.gd). No tick logic; network membership is computed on
## demand by PowerNetwork.rebuild_topology(world). Visual: dark wood base
## + tall pole + small "T" crossarm at top. Wires drawn globally by
## grid_world._draw_power_wires (Task 4, NOT per-pole, to avoid double-drawing).
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
