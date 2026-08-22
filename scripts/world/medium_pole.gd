class_name MediumPole
extends RefCounted

## Medium Pole — the middle wire tier (Electricity Session 3).
##
## 1x1 like the basic pole, but wire range 6 (vs 3) and supply radius 2
## (vs 1), so it covers a 5x5 area instead of 3x3. Those numbers live in
## power_network.gd's POLE_RANGE_BY_TYPE and SUPPLY_RADIUS_BY_TYPE, NOT here
## — this module owns only identity and pixels.
##
## Visually distinguished from the basic pole by a taller shaft, a second
## crossarm, and a cooler grey-brown body. Both tiers must be tellable apart
## at a glance on a dense bus, which is a PAUSE 1 check.
##
## State: empty {} (network membership lives at world._pole_component).

const BODY_COLOR: Color = Color(0.45, 0.42, 0.38)        # weathered grey-brown
const POLE_COLOR: Color = Color(0.38, 0.35, 0.32)
const CROSSARM_COLOR: Color = Color(0.30, 0.28, 0.26)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.MEDIUM_POLE, pos, {})

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var base_size: float = float(tile_size) * 0.34
	var base_rect: Rect2 = Rect2(
		center - Vector2(base_size * 0.5, base_size * 0.5),
		Vector2(base_size, base_size)
	)
	canvas.draw_rect(base_rect, BODY_COLOR, true)
	canvas.draw_rect(base_rect, CROSSARM_COLOR, false, 1.5)
	# Taller shaft than the basic pole (0.68 vs 0.55 of a tile).
	var shaft_width: float = float(tile_size) * 0.12
	var shaft_rect: Rect2 = Rect2(
		Vector2(center.x - shaft_width * 0.5, world_pos.y + float(tile_size) * 0.04),
		Vector2(shaft_width, float(tile_size) * 0.68)
	)
	canvas.draw_rect(shaft_rect, POLE_COLOR, true)
	# TWO crossarms — the at-a-glance tell versus the basic pole's one.
	var crossarm_width: float = float(tile_size) * 0.62
	var crossarm_height: float = float(tile_size) * 0.08
	for y_frac in [0.10, 0.26]:
		var arm: Rect2 = Rect2(
			Vector2(center.x - crossarm_width * 0.5, world_pos.y + float(tile_size) * y_frac),
			Vector2(crossarm_width, crossarm_height)
		)
		canvas.draw_rect(arm, CROSSARM_COLOR, true)
