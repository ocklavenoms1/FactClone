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
