class_name Planter
extends RefCounted

## Planter — grows one crop per cycle, holds the output until extracted.
## Crop type is configured at placement time via `crop_type`. Different
## crops have different growth times (CROP_GROWTH_TICKS).
##
## State schema:
##   crop_type: int    Items.Type of the crop being grown (default WHEAT
##                     for forward-compat with pre-Session-C saves)
##   growth: int       0..max-growth-for-this-crop while growing
##   output: int       count of crop_type ready to extract (0 or 1 for now)
##
## Lifecycle:
##   tick: if output==0 and growth<MAX, growth++
##         when growth reaches MAX: output=YIELD, growth stays at MAX
##         while output>0, growth pauses (the slot is full)
##   extract: harvester or player calls try_extract() — drains 1 output,
##            and if output reaches 0, growth resets to 0 to start a new cycle.

const YIELD_PER_CYCLE: int = 1
const DEFAULT_CROP: int = Items.Type.WHEAT  # used by old saves predating crop_type

## Per-crop growth time. Add a crop = add it here AND register a hotbar
## slot pointing at it (see hotbar.gd).
const CROP_GROWTH_TICKS: Dictionary = {
	Items.Type.WHEAT:      600,   # 30s @ 20tps
	Items.Type.SUGAR_BEET: 800,   # 40s
	Items.Type.FLAX:       500,   # 25s
}

# Visual constants
const BASE_COLOR: Color = Color(0.30, 0.22, 0.14)
const SOIL_COLOR: Color = Color(0.42, 0.30, 0.18)
const SPROUT_COLOR: Color = Color(0.30, 0.65, 0.25)
const FRAME_COLOR: Color = Color(0.10, 0.07, 0.04)
const RIPE_GLOW: Color = Color(1.0, 0.95, 0.5, 0.9)

static func make(pos: Vector2i, crop_type: int = DEFAULT_CROP) -> Building:
	return Building.new(Buildings.Type.PLANTER, pos, {
		"growth": 0,
		"output": 0,
		"crop_type": crop_type,
	})

static func crop_of(b: Building) -> int:
	# .get with default so pre-Session-C saves (no crop_type field) still load:
	# they default to WHEAT which matches their original behavior.
	return int(b.state.get("crop_type", DEFAULT_CROP))

static func max_growth_for(crop_type: int) -> int:
	return int(CROP_GROWTH_TICKS.get(crop_type, 600))

static func tick(b: Building) -> void:
	var output: int = int(b.state.get("output", 0))
	if output > 0:
		return  # crop ready, waiting for extraction — pauses growth
	var growth: int = int(b.state.get("growth", 0))
	var max_growth: int = max_growth_for(crop_of(b))
	if growth < max_growth:
		b.state["growth"] = growth + 1
		if growth + 1 >= max_growth:
			b.state["output"] = YIELD_PER_CYCLE

static func info_lines(b: Building) -> Array:
	var growth: int = int(b.state.get("growth", 0))
	var output: int = int(b.state.get("output", 0))
	var crop: int = crop_of(b)
	var max_growth: int = max_growth_for(crop)
	var pct: int = int(round(growth_pct(b) * 100.0))
	var status: String = "Ripe (output ready)" if output > 0 else "Growing %d%%" % pct
	return [
		"Crop: %s" % Items.name_of(crop),
		"Status: %s" % status,
		"Cycle: %d / %d ticks" % [growth, max_growth],
	]

## Try to extract one item. Returns the item type (>=0) or -1 if nothing ready.
static func try_extract(b: Building) -> int:
	var output: int = int(b.state.get("output", 0))
	if output <= 0:
		return -1
	b.state["output"] = output - 1
	if int(b.state["output"]) <= 0:
		b.state["growth"] = 0  # restart cycle
	return crop_of(b)

static func is_ripe(b: Building) -> bool:
	return int(b.state.get("output", 0)) > 0

static func growth_pct(b: Building) -> float:
	if int(b.state.get("output", 0)) > 0:
		return 1.0
	var max_growth: int = max_growth_for(crop_of(b))
	return clamp(float(b.state.get("growth", 0)) / float(max_growth), 0.0, 1.0)

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# Frame + soil bed.
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BASE_COLOR, true)
	canvas.draw_rect(rect.grow(-2), SOIL_COLOR, true)
	canvas.draw_rect(rect, FRAME_COLOR, false, 2.0)

	# Crop visual — ripe color derives from the crop's item color, so
	# wheat planters show yellow, sugar-beet planters show red, etc.
	var crop: int = crop_of(b)
	var pct: float = growth_pct(b)
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var crop_radius: float = lerp(2.0, float(tile_size) * 0.36, pct)
	var ripe_color: Color = Items.color_of(crop)
	var crop_color: Color = SPROUT_COLOR.lerp(ripe_color, pct)
	canvas.draw_circle(center, crop_radius, crop_color)

	# Ripe glow.
	if is_ripe(b):
		canvas.draw_arc(center, crop_radius + 3.0, 0.0, TAU, 24, RIPE_GLOW, 1.5)
