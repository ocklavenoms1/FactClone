class_name Mixer
extends RefCounted

## Mixer — visual shim for a Processor that runs the dough recipe.
## Tick logic is `Processor.tick`. This file owns only `make()` (which
## chooses the default recipe) and `draw()`.
##
## Recipe: "mixer_dough" — flour ×2 + yeast ×1 + water (fluid) → dough ×1
## over 100 ticks (5s). Water comes from any adjacent pipe whose network
## contains a pump.

const DEFAULT_RECIPE_ID: String = "mixer_dough"

# Visual
const SHELL_DARK: Color = Color(0.28, 0.30, 0.34)
const SHELL_MID: Color = Color(0.45, 0.48, 0.55)
const SHELL_LIGHT: Color = Color(0.65, 0.68, 0.75)
const TRIM_COLOR: Color = Color(0.08, 0.07, 0.06)
const BOWL_COLOR: Color = Color(0.92, 0.86, 0.70)        # dough color
const PADDLE_COLOR: Color = Color(0.18, 0.12, 0.08)
const HOPPER_IN: Color = Color(0.95, 0.92, 0.85)         # flour-ish
const HOPPER_OUT: Color = Color(0.92, 0.86, 0.70)
const WATER_INLET: Color = Color(0.30, 0.55, 0.85)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.MIXER, pos, Processor.make_state(DEFAULT_RECIPE_ID))

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, SHELL_DARK, true)
	canvas.draw_rect(rect.grow(-3), SHELL_MID, true)
	canvas.draw_rect(rect, TRIM_COLOR, false, 2.0)

	# Mixing bowl + paddle.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var bowl_radius: float = float(tile_size) * 0.30
	canvas.draw_circle(center, bowl_radius, BOWL_COLOR)
	canvas.draw_arc(center, bowl_radius, 0.0, TAU, 32, TRIM_COLOR, 1.5)

	var s: int = int(b.state.get("state", Processor.IDLE))
	var paddle_speed: float = 0.0
	match s:
		Processor.RUNNING: paddle_speed = 0.30
		Processor.BLOCKED_OUTPUT: paddle_speed = 0.05
		_: paddle_speed = 0.05
	var spin: float = float(TickSystem.current_tick) * paddle_speed
	# Two crossed paddle bars rotating together.
	for i in 2:
		var ang: float = spin + i * (PI * 0.5)
		var p1: Vector2 = center + Vector2(cos(ang), sin(ang)) * bowl_radius * 0.8
		var p2: Vector2 = center - Vector2(cos(ang), sin(ang)) * bowl_radius * 0.8
		canvas.draw_line(p1, p2, PADDLE_COLOR, 2.0)

	# Progress arc when running.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	if s == Processor.RUNNING and not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		if tt > 0:
			var pct: float = float(p) / float(tt)
			canvas.draw_arc(center, bowl_radius + 3.0, -PI * 0.5, -PI * 0.5 + TAU * pct, 32, Color(0.4, 0.95, 0.4, 0.9), 2.0)

	# Top: input hopper bar (flour/yeast). Bottom: output (dough). Side: water inlet dot.
	if not recipe.is_empty():
		var in_total: int = _buffer_total(b.state.get("in_buffer", []))
		var out_total: int = _buffer_total(b.state.get("out_buffer", []))
		var in_cap: int = int(recipe["input_capacity"])
		var out_cap: int = int(recipe["output_capacity"])
		var bar_w: float = float(tile_size) - 6.0
		canvas.draw_rect(Rect2(world_pos + Vector2(3, 2), Vector2(bar_w * clamp(float(in_total) / float(in_cap), 0.0, 1.0), 2)), HOPPER_IN, true)
		canvas.draw_rect(Rect2(world_pos + Vector2(3, tile_size - 4), Vector2(bar_w * clamp(float(out_total) / float(out_cap), 0.0, 1.0), 2)), HOPPER_OUT, true)
		# Water inlet indicator (left edge).
		canvas.draw_circle(world_pos + Vector2(3, tile_size * 0.5), 2.5, WATER_INLET)

static func _buffer_total(buf: Array) -> int:
	var n: int = 0
	for entry in buf:
		n += int(entry[1])
	return n
