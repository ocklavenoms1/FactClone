class_name Planter
extends RefCounted

## Planter — grows one wheat per cycle, holds the output until extracted.
##
## State schema:
##   growth: int       0..MAX_GROWTH while growing
##   output: int       count of OUTPUT_ITEM ready to extract (0 or 1 for now)
##
## Lifecycle:
##   tick: if output==0 and growth<MAX, growth++
##         when growth reaches MAX: output=YIELD, growth stays at MAX
##         while output>0, growth pauses (the slot is full)
##   extract: harvester or player calls try_extract() — drains 1 output,
##            and if output reaches 0, growth resets to 0 to start a new cycle.

const MAX_GROWTH: int = 600                 # 30s @ 20 ticks/sec
const YIELD_PER_CYCLE: int = 1
const OUTPUT_ITEM: int = Items.Type.WHEAT

# Visual constants
const BASE_COLOR: Color = Color(0.30, 0.22, 0.14)
const SOIL_COLOR: Color = Color(0.42, 0.30, 0.18)
const SPROUT_COLOR: Color = Color(0.30, 0.65, 0.25)
const RIPE_COLOR: Color = Color(0.95, 0.80, 0.25)
const FRAME_COLOR: Color = Color(0.10, 0.07, 0.04)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.PLANTER, pos, { "growth": 0, "output": 0 })

static func tick(b: Building) -> void:
	var output: int = int(b.state.get("output", 0))
	if output > 0:
		return  # crop ready, waiting for extraction — pauses growth
	var growth: int = int(b.state.get("growth", 0))
	if growth < MAX_GROWTH:
		b.state["growth"] = growth + 1
		if growth + 1 >= MAX_GROWTH:
			b.state["output"] = YIELD_PER_CYCLE

static func info_lines(b: Building) -> Array:
	var growth: int = int(b.state.get("growth", 0))
	var output: int = int(b.state.get("output", 0))
	var pct: int = int(round(growth_pct(b) * 100.0))
	var status: String = "Ripe (output ready)" if output > 0 else "Growing %d%%" % pct
	return [
		"Crop: %s" % Items.name_of(OUTPUT_ITEM),
		"Status: %s" % status,
		"Cycle: %d / %d ticks" % [growth, MAX_GROWTH],
	]

## Try to extract one item. Returns the item type (>=0) or -1 if nothing ready.
static func try_extract(b: Building) -> int:
	var output: int = int(b.state.get("output", 0))
	if output <= 0:
		return -1
	b.state["output"] = output - 1
	if int(b.state["output"]) <= 0:
		b.state["growth"] = 0  # restart cycle
	return OUTPUT_ITEM

static func is_ripe(b: Building) -> bool:
	return int(b.state.get("output", 0)) > 0

static func growth_pct(b: Building) -> float:
	if int(b.state.get("output", 0)) > 0:
		return 1.0
	return clamp(float(b.state.get("growth", 0)) / float(MAX_GROWTH), 0.0, 1.0)

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# Frame + soil bed.
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BASE_COLOR, true)
	canvas.draw_rect(rect.grow(-2), SOIL_COLOR, true)
	canvas.draw_rect(rect, FRAME_COLOR, false, 2.0)

	# Crop visual.
	var pct: float = growth_pct(b)
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var crop_radius: float = lerp(2.0, float(tile_size) * 0.36, pct)
	var crop_color: Color = SPROUT_COLOR.lerp(RIPE_COLOR, pct)
	canvas.draw_circle(center, crop_radius, crop_color)

	# Ripe glow.
	if is_ripe(b):
		canvas.draw_arc(center, crop_radius + 3.0, 0.0, TAU, 24, Color(1.0, 0.95, 0.5, 0.9), 1.5)
