class_name Thresher
extends RefCounted

## Thresher — splits raw wheat into grain + straw.
## Multi-output recipe; demonstrates that the Processor base handles
## both products in one cycle.

const DEFAULT_RECIPE_ID: String = "thresher_wheat"

const SHELL: Color = Color(0.45, 0.40, 0.35)
const FRAME: Color = Color(0.20, 0.18, 0.15)
const TRIM: Color = Color(0.06, 0.05, 0.04)
const BLADE: Color = Color(0.85, 0.82, 0.78)
const GRAIN_COLOR: Color = Color(0.88, 0.72, 0.32)
const STRAW_COLOR: Color = Color(0.85, 0.78, 0.40)

static func make(pos: Vector2i, dir: int = 0) -> Building:
	return Building.new(Buildings.Type.THRESHER, pos, Processor.make_state(DEFAULT_RECIPE_ID, dir))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Threshing drum: two crossed blades that spin while running.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var s: int = int(b.state.get("state", Processor.IDLE))
	var spin_rate: float = 0.35 if s == Processor.RUNNING else 0.04
	var spin: float = float(TickSystem.current_tick) * spin_rate
	var blade_len: float = float(tile_size) * 0.32
	for i in 2:
		var ang: float = spin + i * (PI * 0.5)
		var d: Vector2 = Vector2(cos(ang), sin(ang)) * blade_len
		canvas.draw_line(center - d, center + d, BLADE, 2.5)

	# Top hopper bar (wheat in), split bottom (grain + straw out).
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	if not recipe.is_empty():
		var in_total: int = _buf_total(b.state.get("in_buffer", []))
		var grain_count: int = _buf_count(b.state.get("out_buffer", []), Items.Type.GRAIN)
		var straw_count: int = _buf_count(b.state.get("out_buffer", []), Items.Type.STRAW)
		var in_cap: int = int(recipe["input_capacity"])
		var out_cap: int = int(recipe["output_capacity"])
		var bar_w: float = float(tile_size) - 6.0
		canvas.draw_rect(Rect2(world_pos + Vector2(3, 2), Vector2(bar_w * clamp(float(in_total) / float(in_cap), 0.0, 1.0), 2)), Color(0.95, 0.80, 0.25), true)
		# Two output bars (left half = grain, right half = straw).
		var half_w: float = bar_w * 0.5
		canvas.draw_rect(Rect2(world_pos + Vector2(3, tile_size - 4), Vector2(half_w * clamp(float(grain_count) / float(out_cap), 0.0, 1.0), 2)), GRAIN_COLOR, true)
		canvas.draw_rect(Rect2(world_pos + Vector2(3 + half_w + 1, tile_size - 4), Vector2(half_w * clamp(float(straw_count) / float(out_cap), 0.0, 1.0), 2)), STRAW_COLOR, true)

static func _buf_total(buf: Array) -> int:
	var n: int = 0
	for entry in buf:
		n += int(entry[1])
	return n

static func _buf_count(buf: Array, item_type: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0
