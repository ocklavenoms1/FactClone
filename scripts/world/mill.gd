class_name Mill
extends RefCounted

## Mill — visual shim. All behavior is provided by Processor + a recipe.
##
## When placed, the Mill is initialized with recipe "mill_wheat_to_flour".
## Buildings.tick_one dispatches Type.MILL to Processor.tick.
##
## This file owns ONLY: the recipe assignment at placement (`make`) and the
## millstone visual (`draw`). Future processor machines (Oven, Press) follow
## the same pattern: a thin shim with their own `make` and `draw`, sharing
## Processor.tick.

const DEFAULT_RECIPE_ID: String = "mill_wheat_to_flour"

# Visual
const STONE_DARK: Color = Color(0.32, 0.30, 0.28)
const STONE_MID: Color = Color(0.50, 0.46, 0.42)
const STONE_LIGHT: Color = Color(0.72, 0.68, 0.62)
const TRIM_COLOR: Color = Color(0.06, 0.05, 0.04)
const HOPPER_IN: Color = Color(0.95, 0.80, 0.25)   # wheat color
const HOPPER_OUT: Color = Color(0.95, 0.92, 0.85)  # flour color

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.MILL, pos, Processor.make_state(DEFAULT_RECIPE_ID))

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, STONE_DARK, true)
	canvas.draw_rect(rect.grow(-3), STONE_MID, true)
	canvas.draw_rect(rect, TRIM_COLOR, false, 2.0)

	# Spinning millstone — speed scales with running state so it visibly "works".
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var radius: float = float(tile_size) * 0.32
	canvas.draw_circle(center, radius, STONE_LIGHT)
	canvas.draw_arc(center, radius, 0.0, TAU, 32, TRIM_COLOR, 1.5)

	var is_running: bool = int(b.state.get("state", Processor.IDLE)) == Processor.RUNNING
	var spin: float = float(TickSystem.current_tick) * (0.25 if is_running else 0.05)
	for i in 4:
		var ang: float = spin + i * (TAU / 4.0)
		var p: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius * 0.65
		canvas.draw_circle(p, 2.0, TRIM_COLOR)

	# Progress arc around the millstone when running.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	if is_running and not recipe.is_empty():
		var progress: int = int(b.state.get("progress", 0))
		var time_ticks: int = int(recipe["time_ticks"])
		if time_ticks > 0:
			var pct: float = float(progress) / float(time_ticks)
			canvas.draw_arc(center, radius + 3.0, -PI * 0.5, -PI * 0.5 + TAU * pct, 32, Color(0.4, 0.95, 0.4, 0.9), 2.0)

	# In/out hopper indicators — aggregate buffer total / recipe capacity.
	if not recipe.is_empty():
		var in_total: int = _buffer_total(b.state.get("in_buffer", []))
		var out_total: int = _buffer_total(b.state.get("out_buffer", []))
		var in_cap: int = int(recipe["input_capacity"])
		var out_cap: int = int(recipe["output_capacity"])
		var in_pct: float = clamp(float(in_total) / float(in_cap), 0.0, 1.0) if in_cap > 0 else 0.0
		var out_pct: float = clamp(float(out_total) / float(out_cap), 0.0, 1.0) if out_cap > 0 else 0.0
		var bar_w: float = float(tile_size) - 6.0
		canvas.draw_rect(Rect2(world_pos + Vector2(3, 2), Vector2(bar_w * in_pct, 2)), HOPPER_IN, true)
		canvas.draw_rect(Rect2(world_pos + Vector2(3, tile_size - 4), Vector2(bar_w * out_pct, 2)), HOPPER_OUT, true)

static func _buffer_total(buf: Array) -> int:
	var n: int = 0
	for entry in buf:
		n += int(entry[1])
	return n
