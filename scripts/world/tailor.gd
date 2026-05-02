class_name Tailor
extends RefCounted

## Tailor — assembles 4 cloth into 1 bag.
## Workbench with cloth pile and a needle that bobs while running.

const DEFAULT_RECIPE_ID: String = "tailor_bag"

const SHELL: Color = Color(0.42, 0.45, 0.62)         # tailor's slate-blue
const FRAME: Color = Color(0.18, 0.18, 0.28)
const TRIM: Color = Color(0.05, 0.05, 0.08)
const BENCH: Color = Color(0.55, 0.42, 0.28)         # warm wood bench
const CLOTH_COLOR: Color = Color(0.92, 0.80, 0.62)
const BAG_COLOR: Color = Color(0.55, 0.30, 0.18)
const NEEDLE: Color = Color(0.85, 0.85, 0.85)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.TAILOR, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Bench across the bottom half.
	var bench_rect: Rect2 = Rect2(world_pos + Vector2(tile_size * 0.12, tile_size * 0.55),
		Vector2(tile_size * 0.76, tile_size * 0.30))
	canvas.draw_rect(bench_rect, BENCH, true)
	canvas.draw_rect(bench_rect, TRIM, false, 1.0)

	# Stitched piece on the bench: color lerps CLOTH → BAG with cycle progress.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	var pct: float = 0.0
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		pct = clamp(float(p) / float(tt), 0.0, 1.0) if tt > 0 else 0.0
	var piece_color: Color = CLOTH_COLOR.lerp(BAG_COLOR, pct)
	var piece_rect: Rect2 = Rect2(bench_rect.position + Vector2(bench_rect.size.x * 0.20, bench_rect.size.y * 0.18),
		Vector2(bench_rect.size.x * 0.60, bench_rect.size.y * 0.55))
	canvas.draw_rect(piece_rect, piece_color, true)
	canvas.draw_rect(piece_rect, TRIM, false, 1.0)

	# Needle: bobs vertically while running, parked above the piece when idle.
	var s: int = int(b.state.get("state", Processor.IDLE))
	var bob: float = 0.0
	if s == Processor.RUNNING:
		bob = sin(float(TickSystem.current_tick) * 0.55) * (float(tile_size) * 0.04)
	var needle_top: Vector2 = piece_rect.position + Vector2(piece_rect.size.x * 0.5, -float(tile_size) * 0.06 + bob)
	var needle_bot: Vector2 = needle_top + Vector2(0, float(tile_size) * 0.10)
	canvas.draw_line(needle_top, needle_bot, NEEDLE, 1.5)
