class_name YeastCulture
extends RefCounted

## Yeast Culture — grows yeast from sugar + water.
## Bubbling tank visual; needs water from adjacent pipe network.

const DEFAULT_RECIPE_ID: String = "yeast_culture"

const SHELL: Color = Color(0.50, 0.50, 0.55)
const FRAME: Color = Color(0.18, 0.18, 0.20)
const TRIM: Color = Color(0.06, 0.06, 0.07)
const FLUID: Color = Color(0.85, 0.75, 0.55, 0.85)
const BUBBLE: Color = Color(0.95, 0.92, 0.78)
const WATER_INLET: Color = Color(0.30, 0.55, 0.85)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.YEAST_CULTURE, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Tank fluid takes the lower 60% of the tile.
	var tank_top: float = float(tile_size) * 0.30
	var tank_bot: float = float(tile_size) - 6.0
	canvas.draw_rect(Rect2(world_pos + Vector2(6, tank_top), Vector2(tile_size - 12, tank_bot - tank_top)), FLUID, true)

	# Bubbles rising while running.
	var s: int = int(b.state.get("state", Processor.IDLE))
	if s == Processor.RUNNING:
		var t: float = float(TickSystem.current_tick) * 0.10
		for i in 3:
			var phase: float = fmod(t + i * 0.33, 1.0)
			var bx: float = float(tile_size) * (0.30 + 0.18 * float(i))
			var by: float = lerp(tank_bot - 2.0, tank_top + 2.0, phase)
			canvas.draw_circle(world_pos + Vector2(bx, by), 2.0, BUBBLE)

	# Water inlet indicator on left edge.
	canvas.draw_circle(world_pos + Vector2(3, tile_size * 0.5), 2.5, WATER_INLET)
