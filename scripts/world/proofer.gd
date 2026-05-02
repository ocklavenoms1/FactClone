class_name Proofer
extends RefCounted

## Proofer — slow rise: dough → risen_dough over 20s. Warm cream chamber.

const DEFAULT_RECIPE_ID: String = "proofer_rise"

const SHELL: Color = Color(0.78, 0.66, 0.50)
const FRAME: Color = Color(0.40, 0.30, 0.20)
const TRIM: Color = Color(0.10, 0.08, 0.05)
const WARMTH: Color = Color(0.95, 0.80, 0.50, 0.5)
const DOUGH_COLOR: Color = Color(0.92, 0.86, 0.70)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.PROOFER, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	var s: int = int(b.state.get("state", Processor.IDLE))
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)

	# Warmth halo when running.
	if s == Processor.RUNNING:
		var pulse: float = 0.5 + 0.5 * sin(float(TickSystem.current_tick) * 0.06)
		var halo_radius: float = float(tile_size) * (0.34 + 0.04 * pulse)
		canvas.draw_circle(center, halo_radius, WARMTH)

	# Rising dough: lump grows over the cycle, then resets.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		var pct: float = clamp(float(p) / float(tt), 0.0, 1.0) if tt > 0 else 0.0
		var lump: float = lerp(float(tile_size) * 0.18, float(tile_size) * 0.34, pct)
		canvas.draw_circle(center, lump, DOUGH_COLOR)
		canvas.draw_arc(center, lump, 0.0, TAU, 24, TRIM, 1.0)
		# Progress arc ring.
		if s == Processor.RUNNING:
			canvas.draw_arc(center, lump + 4.0, -PI * 0.5, -PI * 0.5 + TAU * pct, 32, Color(0.4, 0.95, 0.4, 0.9), 2.0)
