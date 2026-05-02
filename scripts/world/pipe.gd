class_name Pipe
extends RefCounted

## Pipe — passive carrier of fluids. No tick logic; the world's fluid
## network resolver computes connectivity from pipe positions on demand.
##
## Pipes auto-connect to adjacent (4-way) pipes, pumps, and fluid-consuming
## machines. Visual: continuous tube — a thick line from tile center to
## each connected neighbor's tile edge. Reads as a tube/pipe, distinct
## from belts (which use segmented slot rendering).
##
## State schema: empty (Pipe holds no per-instance state for Session B).
## A future flow simulation may add fluid-level fields here.

# Visual — pipe color depends on whether the network has a pump.
const TUBE_PUMP: Color = Color(0.30, 0.62, 0.95)        # bright saturated blue
const TUBE_DRY:  Color = Color(0.42, 0.50, 0.58)        # muted gray-blue (no pump)
const TUBE_OUTLINE: Color = Color(0.05, 0.10, 0.15)     # subtle dark trim
const HUB_PUMP: Color = Color(0.55, 0.78, 0.98)
const HUB_DRY:  Color = Color(0.55, 0.62, 0.70)

const DIRS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.PIPE, pos, {})

## Returns true if `b` (a building at neighbor pos) should auto-connect
## to a pipe — i.e. it's a pipe, a pump, or any processor whose current
## recipe declares a fluid input. Data-driven so new fluid-consuming
## machines don't need to be hard-listed here.
static func _is_connectable(b: Building) -> bool:
	if b == null:
		return false
	if b.type == Buildings.Type.PIPE or b.type == Buildings.Type.PUMP:
		return true
	if b.state.has("recipe_id"):
		var recipe: Dictionary = Recipes.get_recipe(b.state["recipe_id"])
		if not recipe.is_empty() and not recipe.get("inputs_fluid", []).is_empty():
			return true
	return false

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# `canvas` IS the GridWorld (grid_world._draw passes self). Cast lets us
	# query connectivity for color + per-direction stub auto-connect.
	var has_pump: bool = canvas.is_pipe_in_pump_component(b.anchor)
	var tube_color: Color = TUBE_PUMP if has_pump else TUBE_DRY
	var hub_color: Color = HUB_PUMP if has_pump else HUB_DRY

	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var thickness: float = float(tile_size) * 0.32
	var hub_radius: float = float(tile_size) * 0.20

	# Determine which neighbors connect; only draw stubs to actual neighbors.
	# Isolated pipes show just the hub — visually "an unconnected fitting".
	var connected: Array = []
	for dir_vec in DIRS:
		var neighbor: Building = null
		if canvas.has_building_at(b.anchor + dir_vec):
			neighbor = canvas.building_at(b.anchor + dir_vec)
		if _is_connectable(neighbor):
			connected.append(dir_vec)

	# Stub: solid filled rectangle from center to tile edge in the connect
	# direction. Continuous look — no segments, no slot boundaries.
	for dir_vec in connected:
		var dir_v: Vector2 = Vector2(dir_vec)
		var perp: Vector2 = Vector2(-dir_v.y, dir_v.x)
		var end_pt: Vector2 = center + dir_v * (float(tile_size) * 0.5)
		var corners := PackedVector2Array([
			center + perp * (thickness * 0.5),
			end_pt + perp * (thickness * 0.5),
			end_pt - perp * (thickness * 0.5),
			center - perp * (thickness * 0.5),
		])
		canvas.draw_colored_polygon(corners, tube_color)
		# Thin outline along the long edges so the tube reads against
		# busy backgrounds (e.g., overlapping pipes on stone).
		canvas.draw_line(center + perp * (thickness * 0.5), end_pt + perp * (thickness * 0.5), TUBE_OUTLINE, 1.0)
		canvas.draw_line(center - perp * (thickness * 0.5), end_pt - perp * (thickness * 0.5), TUBE_OUTLINE, 1.0)

	# Central hub fitting — drawn last so stubs tuck under it cleanly.
	canvas.draw_circle(center, hub_radius, hub_color)
	canvas.draw_arc(center, hub_radius, 0.0, TAU, 16, TUBE_OUTLINE, 1.0)

static func info_lines(b: Building) -> Array:
	return [
		"Pipe — auto-connects to adjacent pipes, pumps, and fluid consumers.",
		"No state. Network resolved by GridWorld.",
	]
