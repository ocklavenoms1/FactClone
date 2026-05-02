class_name Packager
extends RefCounted

## Packager — bundles 4 bread loaves into a Loaf Pack.

const DEFAULT_RECIPE_ID: String = "packager_loaves"

const SHELL: Color = Color(0.55, 0.50, 0.45)
const FRAME: Color = Color(0.20, 0.18, 0.15)
const TRIM: Color = Color(0.06, 0.05, 0.04)
const BOX_COLOR: Color = Color(0.55, 0.40, 0.25)
const BREAD_COLOR: Color = Color(0.78, 0.55, 0.30)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.PACKAGER, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Open box outline + 4 bread pellets that fill in over the cycle.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var box_size: Vector2 = Vector2(tile_size * 0.5, tile_size * 0.5)
	var box_rect: Rect2 = Rect2(center - box_size * 0.5, box_size)
	canvas.draw_rect(box_rect, BOX_COLOR, true)
	canvas.draw_rect(box_rect, TRIM, false, 1.5)

	# Loaves placed quarter-by-quarter as progress climbs.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		var loaves_visible: int = clamp(int(4.0 * float(p) / float(tt)) if tt > 0 else 0, 0, 4)
		var positions: Array = [
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
		]
		for i in loaves_visible:
			var p_offset: Vector2 = positions[i] * (box_size.x * 0.22)
			canvas.draw_rect(Rect2(center + p_offset - Vector2(3, 2), Vector2(6, 4)), BREAD_COLOR, true)
