class_name Oven
extends RefCounted

## Oven — bakes risen_dough + fuel_briquette → bread. Brick exterior with
## a fire glow when burning.

const DEFAULT_RECIPE_ID: String = "oven_bread"

const BRICK_DARK: Color = Color(0.45, 0.22, 0.15)
const BRICK_MID: Color = Color(0.65, 0.32, 0.20)
const MORTAR: Color = Color(0.30, 0.18, 0.12)
const TRIM: Color = Color(0.10, 0.05, 0.03)
const FIRE_INNER: Color = Color(1.00, 0.85, 0.30)
const FIRE_OUTER: Color = Color(0.95, 0.40, 0.10, 0.7)
const COLD_HEARTH: Color = Color(0.20, 0.10, 0.06)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.OVEN, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BRICK_DARK, true)
	canvas.draw_rect(rect.grow(-3), BRICK_MID, true)
	# Mortar grid for brick texture.
	canvas.draw_line(world_pos + Vector2(0, tile_size * 0.5), world_pos + Vector2(tile_size, tile_size * 0.5), MORTAR, 1.0)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Hearth opening with fire when running.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var hearth_size: Vector2 = Vector2(tile_size * 0.45, tile_size * 0.32)
	var hearth_rect: Rect2 = Rect2(center - hearth_size * 0.5, hearth_size)
	canvas.draw_rect(hearth_rect, COLD_HEARTH, true)

	var s: int = int(b.state.get("state", Processor.IDLE))
	if s == Processor.RUNNING:
		# Flicker by sampling a noise-y sin.
		var t: float = float(TickSystem.current_tick) * 0.4
		var flicker: float = 0.7 + 0.3 * sin(t) * cos(t * 1.3 + 1.0)
		var fire_size: Vector2 = hearth_size * (0.6 + 0.15 * flicker)
		canvas.draw_rect(Rect2(center - fire_size * 0.5, fire_size), FIRE_OUTER, true)
		canvas.draw_rect(Rect2(center - fire_size * 0.35, fire_size * 0.7), FIRE_INNER, true)
