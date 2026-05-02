class_name Briquetter
extends RefCounted

## Briquetter — compresses 3 straw into a fuel briquette.
## Press machine: descending plate while running.

const DEFAULT_RECIPE_ID: String = "briquetter_fuel"

const SHELL: Color = Color(0.35, 0.32, 0.30)
const FRAME: Color = Color(0.15, 0.13, 0.10)
const TRIM: Color = Color(0.05, 0.04, 0.03)
const PLATE: Color = Color(0.60, 0.55, 0.50)
const STRAW_COLOR: Color = Color(0.85, 0.78, 0.40)
const BRIQUETTE: Color = Color(0.30, 0.22, 0.18)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.BRIQUETTER, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Anvil at bottom with straw on it; plate descends from top while running.
	var anvil_y: float = float(tile_size) * 0.78
	var plate_w: float = float(tile_size) * 0.55
	var anvil_rect: Rect2 = Rect2(world_pos + Vector2(tile_size * 0.5 - plate_w * 0.5, anvil_y), Vector2(plate_w, 4))
	canvas.draw_rect(anvil_rect, TRIM, true)

	# Straw on the anvil — color shifts toward briquette as cycle completes.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	var pct: float = 0.0
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		pct = clamp(float(p) / float(tt), 0.0, 1.0) if tt > 0 else 0.0
	var press_color: Color = STRAW_COLOR.lerp(BRIQUETTE, pct)
	var pellet_h: float = lerp(float(tile_size) * 0.22, float(tile_size) * 0.08, pct)
	var pellet_y: float = anvil_y - pellet_h
	canvas.draw_rect(Rect2(world_pos + Vector2(tile_size * 0.5 - plate_w * 0.4, pellet_y), Vector2(plate_w * 0.8, pellet_h)), press_color, true)

	# Plate descends as pct climbs.
	var plate_y: float = lerp(float(tile_size) * 0.10, anvil_y - pellet_h - 4.0, pct)
	canvas.draw_rect(Rect2(world_pos + Vector2(tile_size * 0.5 - plate_w * 0.5, plate_y), Vector2(plate_w, 4)), PLATE, true)
