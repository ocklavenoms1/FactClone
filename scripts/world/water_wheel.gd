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
