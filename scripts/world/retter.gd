class_name Retter
extends RefCounted

## Retter — soaks flax in water until it breaks down to fiber.
## Vat with water level; flax color shifts toward fiber as cycle completes.

const DEFAULT_RECIPE_ID: String = "retter_fiber"

const SHELL: Color = Color(0.40, 0.55, 0.45)         # mossy vat exterior
const FRAME: Color = Color(0.18, 0.22, 0.18)
const TRIM: Color = Color(0.05, 0.08, 0.05)
const WATER: Color = Color(0.35, 0.50, 0.55, 0.85)   # murky retting water
const FLAX_COLOR: Color = Color(0.55, 0.72, 0.78)
const FIBER_COLOR: Color = Color(0.86, 0.84, 0.76)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.RETTER, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Vat opening showing water surface; bundle floats inside.
	var vat_rect: Rect2 = Rect2(world_pos + Vector2(tile_size * 0.18, tile_size * 0.22),
		Vector2(tile_size * 0.64, tile_size * 0.62))
	canvas.draw_rect(vat_rect, WATER, true)
	canvas.draw_rect(vat_rect, TRIM, false, 1.5)

	# Bundle: color lerps FLAX → FIBER as cycle progresses.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	var pct: float = 0.0
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		pct = clamp(float(p) / float(tt), 0.0, 1.0) if tt > 0 else 0.0
	var bundle_color: Color = FLAX_COLOR.lerp(FIBER_COLOR, pct)
	var bundle_rect: Rect2 = Rect2(vat_rect.position + Vector2(vat_rect.size.x * 0.15, vat_rect.size.y * 0.30),
		Vector2(vat_rect.size.x * 0.70, vat_rect.size.y * 0.40))
	canvas.draw_rect(bundle_rect, bundle_color, true)
	canvas.draw_rect(bundle_rect, TRIM, false, 1.0)
