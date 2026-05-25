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

## STUB draw — placeholder body only. Full fill-bar visual lands in Task 6.
static func draw(_b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var body_rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(body_rect, BASE_COLOR, true)
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
