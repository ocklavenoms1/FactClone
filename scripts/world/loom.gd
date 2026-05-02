class_name Loom
extends RefCounted

## Loom — weaves 3 fiber into 1 cloth.
## Wooden frame with horizontal warp threads; shuttle slides across while running.

const DEFAULT_RECIPE_ID: String = "loom_cloth"

const SHELL: Color = Color(0.72, 0.50, 0.28)         # warm wood
const FRAME: Color = Color(0.30, 0.18, 0.10)
const TRIM: Color = Color(0.08, 0.05, 0.03)
const WARP: Color = Color(0.86, 0.84, 0.76)          # fiber-colored warp threads
const SHUTTLE: Color = Color(0.92, 0.80, 0.62)       # cloth-colored shuttle
const FABRIC: Color = Color(0.92, 0.80, 0.62)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.LOOM, pos, Processor.make_state(DEFAULT_RECIPE_ID))

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, FRAME, true)
	canvas.draw_rect(rect.grow(-3), SHELL, true)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Horizontal warp lines spanning the frame.
	var inset: float = float(tile_size) * 0.18
	var lane_top: float = float(tile_size) * 0.30
	var lane_bot: float = float(tile_size) * 0.70
	var lane_count: int = 5
	for i in lane_count:
		var t: float = float(i) / float(lane_count - 1)
		var y: float = lerp(lane_top, lane_bot, t)
		canvas.draw_line(world_pos + Vector2(inset, y), world_pos + Vector2(tile_size - inset, y), WARP, 1.0)

	# Shuttle: slides across while running, parked at left when idle.
	var s: int = int(b.state.get("state", Processor.IDLE))
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	var pct: float = 0.0
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		var tt: int = int(recipe["time_ticks"])
		pct = clamp(float(p) / float(tt), 0.0, 1.0) if tt > 0 else 0.0
	# Shuttle bounces left↔right twice per cycle so motion reads as weaving.
	var traverse: float = abs(sin(pct * TAU))
	var shuttle_x: float = lerp(inset, float(tile_size) - inset, traverse) if s == Processor.RUNNING else inset
	canvas.draw_circle(world_pos + Vector2(shuttle_x, (lane_top + lane_bot) * 0.5), float(tile_size) * 0.06, SHUTTLE)

	# Woven fabric strip below the warp, growing with progress.
	var fabric_h: float = lerp(0.0, float(tile_size) * 0.10, pct)
	if fabric_h > 0.5:
		canvas.draw_rect(Rect2(world_pos + Vector2(inset, lane_bot + 2.0), Vector2(float(tile_size) - inset * 2.0, fabric_h)), FABRIC, true)
