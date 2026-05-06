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

## Per-crop properties (session-soil-exhaustion-1). Co-located so
## growth_ticks + soil_cost can't drift apart. Add a crop = add it here AND
## register a hotbar slot pointing at it (see hotbar.gd).
##
## soil_cost: amount each successful harvest depletes the planter's region
##   soil_health (0..100). Different crops feed differently:
##     - light feeders (FLAX): 3 — minimal soil draw
##     - baseline (WHEAT):     5 — average
##     - heavy feeders (SUGAR_BEET): 8 — heavier draw
##     - future legumes: negative cost (heal soil)
const CROP_DATA: Dictionary = {
	Items.Type.WHEAT:      {"growth_ticks": 600, "soil_cost": 5},   # 30s @ 20tps, baseline
	Items.Type.SUGAR_BEET: {"growth_ticks": 800, "soil_cost": 8},   # 40s, heavy feeder
	Items.Type.FLAX:       {"growth_ticks": 500, "soil_cost": 3},   # 25s, light feeder
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
	return int(CROP_DATA.get(crop_type, {}).get("growth_ticks", 600))

## Per-harvest soil cost for the given crop (session-soil-exhaustion-1).
## Future legumes can return negative to heal soil. Default 0 (no cost) for
## unknown crop types — defensive against pre-Session-soil saves that might
## have crop_type values not yet in CROP_DATA.
static func soil_cost_for(crop_type: int) -> int:
	return int(CROP_DATA.get(crop_type, {}).get("soil_cost", 0))

static func tick(b: Building, world = null) -> void:
	var output: int = int(b.state.get("output", 0))
	if output > 0:
		return  # crop ready, waiting for extraction — pauses growth

	var growth: int = int(b.state.get("growth", 0))
	var max_growth: int = max_growth_for(crop_of(b))

	# Soil-zero gate (session-soil-exhaustion-1): block START of a new
	# growth cycle when the planter's region soil_health is 0. In-progress
	# crops (growth > 0) keep ticking and finish gracefully — graceful Q5
	# behavior. Player gets the in-flight harvest, then planter idles in
	# dead soil. Recovery comes Session 2.
	if growth == 0 and world != null:
		var region: Vector2i = GridWorld.region_of(b.anchor)
		if world.region_soil_health(region) <= 0:
			return  # idle: don't start a new cycle in dead soil

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
##
## When extraction succeeds, the planter's region soil_health is decremented
## by the crop's soil_cost (session-soil-exhaustion-1). Soil deplete fires at
## the planter's anchor region (where the crop GREW), not the consumer's —
## a harvester at region (1, 0) extracting from a planter at region (0, 0)
## still depletes (0, 0). Cause-effect tied to the grow site.
static func try_extract(b: Building, world = null) -> int:
	var output: int = int(b.state.get("output", 0))
	if output <= 0:
		return -1
	var crop_type: int = crop_of(b)
	b.state["output"] = output - 1
	if int(b.state["output"]) <= 0:
		b.state["growth"] = 0  # restart cycle (gated by soil-zero check on next tick)
	# Deplete region soil for the harvested crop. Defensive null-check for
	# tests without a world reference.
	if world != null:
		var region: Vector2i = GridWorld.region_of(b.anchor)
		world.deplete_region_soil(region, soil_cost_for(crop_type))
	return crop_type

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
