class_name Pump
extends RefCounted

## Pump — fluid source. Must be placed adjacent to a base=WATER tile.
## Connects to the pipe network through its non-water neighbors.
##
## The pump itself has no fluid output rate in the connectivity-only model;
## any pipe network that contains a pump and is also reachable from a fluid
## consumer reports water as available.
##
## Placement validation (in addition to overlay rules):
##   - At least one of 4 cardinal neighbors must be base=WATER.
##   - Must be on a buildable overlay (handled via requires_overlay).
##
## State schema: empty for Session B (no flow sim).

# Visual
const BG_COLOR: Color = Color(0.40, 0.40, 0.45)
const TRIM_COLOR: Color = Color(0.08, 0.08, 0.10)
const TANK_COLOR: Color = Color(0.55, 0.62, 0.70)
const VALVE_COLOR: Color = Color(0.85, 0.45, 0.20)
const WATER_INDICATOR: Color = Color(0.30, 0.55, 0.85)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.PUMP, pos, {})

## Validation hook — called by GridWorld.can_place_building before normal rules.
## Returns true iff at least one cardinal neighbor is a water base tile.
static func is_valid_placement(world: Node2D, pos: Vector2i) -> bool:
	for dir_vec in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		if world.is_water_at(pos + dir_vec):
			return true
	return false

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BG_COLOR, true)
	canvas.draw_rect(rect.grow(-3), TANK_COLOR, true)
	canvas.draw_rect(rect, TRIM_COLOR, false, 2.0)

	# Pulsing water indicator dot in the center, animated subtly.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var pulse: float = 0.5 + 0.5 * sin(float(TickSystem.current_tick) * 0.15)
	var radius: float = float(tile_size) * (0.18 + 0.04 * pulse)
	canvas.draw_circle(center, radius, WATER_INDICATOR)
	canvas.draw_arc(center, radius, 0.0, TAU, 16, TRIM_COLOR, 1.0)

	# Valve nubs on each side hint at directional output.
	for dir_vec in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var nub: Vector2 = center + Vector2(dir_vec) * (float(tile_size) * 0.36)
		canvas.draw_circle(nub, 2.0, VALVE_COLOR)

static func info_lines(b: Building) -> Array:
	return [
		"Pump — draws from adjacent water tile.",
		"Connects to pipe network through non-water sides.",
		"Any pipe network containing this pump = water available.",
	]
