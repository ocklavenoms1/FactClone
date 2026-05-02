class_name SugarPress
extends RefCounted

## Sugar Press — extracts sugar from sugar beets.

const DEFAULT_RECIPE_ID: String = "press_sugar"

const SHELL: Color = Color(0.55, 0.45, 0.45)
const FRAME: Color = Color(0.22, 0.15, 0.18)
const TRIM: Color = Color(0.06, 0.04, 0.05)
const PLATE: Color = Color(0.70, 0.60, 0.60)
const BEET_COLOR: Color = Color(0.65, 0.20, 0.30)
const SUGAR_COLOR: Color = Color(0.98, 0.96, 0.94)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.SUGAR_PRESS, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Press apparatus: like Briquetter but the pellet color goes BEET → SUGAR.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var anvil_y: float = float(tile_size) * 0.78
	var plate_w: float = float(tile_size) * 0.55
	canvas.draw_rect(Rect2(world_pos + Vector2(tile_size * 0.5 - plate_w * 0.5, anvil_y), Vector2(plate_w, 4)), TRIM, true)

	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	var pct: float = 0.0
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		pct = clamp(float(p) / float(tt), 0.0, 1.0) if tt > 0 else 0.0
	var pellet_color: Color = BEET_COLOR.lerp(SUGAR_COLOR, pct)
	var pellet_h: float = lerp(float(tile_size) * 0.22, float(tile_size) * 0.10, pct)
	canvas.draw_rect(Rect2(world_pos + Vector2(tile_size * 0.5 - plate_w * 0.4, anvil_y - pellet_h), Vector2(plate_w * 0.8, pellet_h)), pellet_color, true)

	var plate_y: float = lerp(float(tile_size) * 0.10, anvil_y - pellet_h - 4.0, pct)
	canvas.draw_rect(Rect2(world_pos + Vector2(tile_size * 0.5 - plate_w * 0.5, plate_y), Vector2(plate_w, 4)), PLATE, true)
