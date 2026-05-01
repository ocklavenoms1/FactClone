class_name Pipe
extends RefCounted

## Pipe — passive carrier of fluids. No tick logic; the world's fluid
## network resolver computes connectivity from pipe positions on demand.
##
## Pipes auto-connect to adjacent (4-way) pipes, pumps, and fluid-consuming
## machines. Visual is drawn based on which neighbors are connectable.
##
## State schema: empty (Pipe holds no per-instance state for Session B).
## A future flow simulation may add fluid-level fields here.

# Visual
const BG_COLOR: Color = Color(0.18, 0.20, 0.22)
const TRIM_COLOR: Color = Color(0.05, 0.05, 0.06)
const PIPE_BODY: Color = Color(0.45, 0.55, 0.65)
const PIPE_HIGHLIGHT: Color = Color(0.65, 0.78, 0.90)
const HUB_COLOR: Color = Color(0.30, 0.40, 0.50)

const DIRS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.PIPE, pos, {})

## Returns true if `b` (a building at neighbor pos) should auto-connect
## to a pipe — i.e. it's a pipe, a pump, or a fluid-consuming machine.
static func _is_connectable(b: Building) -> bool:
	if b == null:
		return false
	match b.type:
		Buildings.Type.PIPE, Buildings.Type.PUMP, Buildings.Type.MIXER:
			return true
	return false

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BG_COLOR, true)
	canvas.draw_rect(rect, TRIM_COLOR, false, 1.5)

	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var pipe_half_thick: float = float(tile_size) * 0.18
	var hub_radius: float = float(tile_size) * 0.16

	# We can't query the world from a static draw method without it being
	# passed in, so check connectivity by reading siblings via the global
	# building_at lookup. We need access to the world — drawn from
	# Buildings.draw_one which doesn't pass world. Solution: walk the
	# tree to GridWorld via an autoload-style pattern would work, but the
	# simplest fix is to draw all 4 stub pipes always (X cross) — readable
	# enough at this art tier. Future: pass world into draw_one.
	# For now: draw a clean 4-way cross so pipes look like pipes; the
	# auto-connect visual upgrade lands when we route world into draw.
	for dir_vec in DIRS:
		var end_local: Vector2 = Vector2(tile_size * 0.5, tile_size * 0.5) + Vector2(dir_vec) * (float(tile_size) * 0.5)
		var perp: Vector2 = Vector2(-dir_vec.y, dir_vec.x)
		var rect_corners: Array = [
			world_pos + Vector2(tile_size * 0.5, tile_size * 0.5) + perp * pipe_half_thick,
			world_pos + end_local + perp * pipe_half_thick,
			world_pos + end_local - perp * pipe_half_thick,
			world_pos + Vector2(tile_size * 0.5, tile_size * 0.5) - perp * pipe_half_thick,
		]
		canvas.draw_colored_polygon(PackedVector2Array(rect_corners), PIPE_BODY)

	# Central hub.
	canvas.draw_circle(center, hub_radius, HUB_COLOR)
	canvas.draw_arc(center, hub_radius, 0.0, TAU, 16, TRIM_COLOR, 1.0)

	# Highlight along the cross to add a sense of depth.
	canvas.draw_line(world_pos + Vector2(tile_size * 0.1, tile_size * 0.5 - 2), world_pos + Vector2(tile_size * 0.9, tile_size * 0.5 - 2), PIPE_HIGHLIGHT, 1.0)

static func info_lines(b: Building) -> Array:
	return [
		"Pipe — auto-connects to adjacent pipes, pumps, and fluid consumers.",
		"No state. Network resolved by GridWorld.",
	]
