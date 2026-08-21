class_name Substation
extends RefCounted

## Substation — the backbone wire tier (Electricity Session 3).
##
## 2x2, wire range 11, supply radius 4 (a 9x9 covered area measured from the
## FOOTPRINT, not the anchor). It is the piece that bridges two separate pole
## clusters into one network.
##
## This is the project's first MULTI-CELL POLE. Every distance computation in
## power_network.gd that assumes a pole occupies exactly one cell has to be
## taught otherwise; that work lands in a later task.
##
## State: empty {} (network membership lives at world._pole_component).

const BODY_COLOR: Color = Color(0.38, 0.40, 0.46)        # cold steel-blue
const FRAME_COLOR: Color = Color(0.26, 0.28, 0.33)
const INSULATOR_COLOR: Color = Color(0.72, 0.74, 0.70)   # pale ceramic

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.SUBSTATION, pos, {})

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# Spans the full 2x2 footprint. world_pos is the ANCHOR cell's top-left,
	# so the body is 2 tiles on a side.
	var span: float = float(tile_size) * 2.0
	var inset: float = float(tile_size) * 0.18
	var body: Rect2 = Rect2(
		world_pos + Vector2(inset, inset),
		Vector2(span - inset * 2.0, span - inset * 2.0)
	)
	canvas.draw_rect(body, BODY_COLOR, true)
	canvas.draw_rect(body, FRAME_COLOR, false, 2.0)
	# Four insulators at the corners of the housing — reads as high-voltage
	# gear rather than a big box, and marks the four cells it occupies.
	var r: float = float(tile_size) * 0.13
	for corner in [Vector2(0.5, 0.5), Vector2(1.5, 0.5), Vector2(0.5, 1.5), Vector2(1.5, 1.5)]:
		canvas.draw_circle(world_pos + corner * float(tile_size), r, INSULATOR_COLOR)
