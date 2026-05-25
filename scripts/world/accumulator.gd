class_name Accumulator
extends RefCounted

## Accumulator — battery storage for the electricity arc.
##
## 1x1 footprint. Stores power between excess/deficit cycles. Charge
## mutation happens in PowerNetwork.update_supply_demand 3-stage pre-pass
## (Stage 2: charge from excess, discharge into deficit). Accumulator's
## own tick() is a no-op — building has no per-tick visual animation.
##
## State:
##   charge: float        — current stored energy [0.0, MAX_CAPACITY]
##                          Float allows even-distribution fractions when
##                          multiple accumulators on same network split
##                          excess that doesn't divide evenly (e.g., 3 acc
##                          + 4 excess = 1.33 per accumulator).
##
## Constants:
##   MAX_CAPACITY: int = 50           — max storable units
##   MAX_CHARGE_RATE: int = 5         — units per tick when supply > demand
##   MAX_DISCHARGE_RATE: int = 5      — units per tick when supply < demand
##
## Power network contract: accumulator joins network via _adjacent_component_id
## (strict cardinal — same as generators). PowerNetwork.update_supply_demand
## classifies it in Stage 1, mutates its charge in Stage 2, computes
## effective_supply (raw + accumulator_supply - accumulator_drain) in Stage 3.

const MAX_CAPACITY: int = 50
const MAX_CHARGE_RATE: int = 5
const MAX_DISCHARGE_RATE: int = 5

const OFF_COLOR: Color = Color(0.30, 0.30, 0.30)    # empty bar
const FULL_COLOR: Color = Color(0.95, 0.78, 0.30)   # full bar (matches SlotWidget.BORDER_HOVER family)
const BASE_COLOR: Color = Color(0.30, 0.30, 0.40)   # body / battery casing
const FRAME_COLOR: Color = Color(0.20, 0.20, 0.28)  # bar frame outline

static func make(pos: Vector2i) -> Building:
	var state: Dictionary = {
		"charge": 0.0,
	}
	return Building.new(Buildings.Type.ACCUMULATOR, pos, state)

## Full visual: body + vertical fill-bar (bottom-up) + frame outline.
## Bar color lerps from OFF_COLOR (empty) to FULL_COLOR (full).
##
## Z-order (bottom to top):
##   1. Body rect (BASE_COLOR)
##   2. Bar frame outline (FRAME_COLOR, just the outline of the bar inset)
##   3. Bar fill (lerped color, scales bottom-up by charge fraction)
##   4. Body frame outline (FRAME_COLOR, on top of everything)
##
## Bar geometry: ~60% of building height (top 20% to bottom 20% are inset
## frame margin). Bar fills bottom-up: empty bar is just the frame outline;
## full bar fills the inner rect entirely.
static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var charge: float = float(b.state.get("charge", 0.0))
	var fraction: float = clamp(charge / float(MAX_CAPACITY), 0.0, 1.0)
	# 1. Body rect.
	var body_rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(body_rect, BASE_COLOR, true)
	# 2. Bar frame outline (inset).
	var inset: float = float(tile_size) * 0.20
	var bar_outer: Rect2 = Rect2(
		world_pos + Vector2(inset, inset),
		Vector2(float(tile_size) - 2.0 * inset, float(tile_size) - 2.0 * inset)
	)
	canvas.draw_rect(bar_outer, FRAME_COLOR, false, 1.5)
	# 3. Bar fill (bottom-up). Inner rect tracks bar_outer bounds minus 1px
	# frame width.
	if fraction > 0.0:
		var bar_inner_max_height: float = bar_outer.size.y - 2.0
		var fill_height: float = bar_inner_max_height * fraction
		var bar_fill: Rect2 = Rect2(
			bar_outer.position + Vector2(1.0, bar_outer.size.y - 1.0 - fill_height),
			Vector2(bar_outer.size.x - 2.0, fill_height)
		)
		var bar_color: Color = OFF_COLOR.lerp(FULL_COLOR, fraction)
		canvas.draw_rect(bar_fill, bar_color, true)
	# 4. Body frame outline (on top).
	canvas.draw_rect(body_rect, FRAME_COLOR, false, 2.0)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	var charge: float = float(b.state.get("charge", 0.0))
	var pct: int = int(round((charge / float(MAX_CAPACITY)) * 100.0))
	lines.append("Charge: %d / %d units (%d%%)" % [int(round(charge)), MAX_CAPACITY, pct])
	# Network info.
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
	else:
		lines.append("Network: #%d" % comp_id)
	return lines
