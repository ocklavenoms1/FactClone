class_name PowerPole
extends RefCounted

## Power Pole — the BASIC (cheapest, shortest) of three wire tiers, and the
## passive carrier of the electric network.
##
## The tiers are POWER_POLE, MEDIUM_POLE (medium_pole.gd) and SUBSTATION
## (substation.gd). They differ in three numbers — wire range, supply radius,
## footprint — and the footprint drags one behavioural difference along with
## it: the 2x2 substation is the only non-walkable tier (see substation.gd,
## which paints its body edge-to-edge for exactly that reason). Ranges live in
## PowerNetwork.POLE_RANGE_BY_TYPE (this one is 3) and supply radii in
## SUPPLY_RADIUS_BY_TYPE (this one is 1). Two poles auto-connect when their
## Chebyshev distance is within EITHER one's range — max(), not min() — so a
## substation reaches a basic pole that cannot reach back; the rule lives in
## PowerNetwork.poles_connected and nowhere else.
##
## THE TIERS ARE EQUAL as of Task 5, on all three of the paths that used to
## treat POWER_POLE as the only pole. Wiring landed in Task 4 (all three tiers
## form network components and are drawn with wires); what a pole does for
## OTHER buildings landed in Task 5:
##
##   _supply_component_id   walks the consumer's footprint and delegates each
##   power_satisfaction_at  cell to _covering_component_id. ONE function, so
##                          these two cannot answer differently about the same
##                          cell — they used to, and a lamp beside a medium
##                          pole lit up while contributing no demand.
##   _adjacent_component_id filters on Buildings.POLE_TYPES, so a generator or
##                          accumulator touching any tier feeds its supply in.
##
## _covering_component_id sizes its scan to the WIDEST tier's radius and then
## filters each candidate against that pole's own, and it measures distance to
## the matched FOOTPRINT CELL (via world._pole_cells) rather than to the
## anchor — which is what makes the 2x2 substation cover equally far in all
## four directions instead of hanging its area off its top-left corner.
##
## No tick logic; network membership is computed on demand by
## PowerNetwork.rebuild_topology(world). Visual: dark wood base + tall pole +
## small "T" crossarm at top. Wires drawn globally by
## grid_world._draw_power_wires (NOT per-pole, to avoid double-drawing).
##
## State: empty {} (network membership tracked at world._pole_component level).

const BODY_COLOR: Color = Color(0.50, 0.38, 0.25)         # dark wood-brown
const POLE_COLOR: Color = Color(0.45, 0.32, 0.20)         # slightly darker shaft
const CROSSARM_COLOR: Color = Color(0.40, 0.28, 0.18)     # darkest

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.POWER_POLE, pos, {})

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	# Base square — small footprint reading as "thin pole standing here".
	var base_size: float = float(tile_size) * 0.30
	var base_rect: Rect2 = Rect2(
		center - Vector2(base_size * 0.5, base_size * 0.5),
		Vector2(base_size, base_size)
	)
	canvas.draw_rect(base_rect, BODY_COLOR, true)
	canvas.draw_rect(base_rect, CROSSARM_COLOR, false, 1.5)
	# Pole shaft — tall vertical bar from base to top of tile.
	var shaft_width: float = float(tile_size) * 0.10
	var shaft_rect: Rect2 = Rect2(
		Vector2(center.x - shaft_width * 0.5, world_pos.y + float(tile_size) * 0.10),
		Vector2(shaft_width, float(tile_size) * 0.55)
	)
	canvas.draw_rect(shaft_rect, POLE_COLOR, true)
	# Crossarm — small horizontal bar near top.
	var crossarm_width: float = float(tile_size) * 0.55
	var crossarm_height: float = float(tile_size) * 0.08
	var crossarm_rect: Rect2 = Rect2(
		Vector2(center.x - crossarm_width * 0.5, world_pos.y + float(tile_size) * 0.16),
		Vector2(crossarm_width, crossarm_height)
	)
	canvas.draw_rect(crossarm_rect, CROSSARM_COLOR, true)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	var comp_id: int = PowerNetwork.network_id_at(world, b.anchor)
	if comp_id < 0:
		lines.append("Network: (not connected)")
		return lines
	var supply: int = PowerNetwork.supply_for(world, comp_id)
	var demand: int = PowerNetwork.demand_for(world, comp_id)
	var sat: float = PowerNetwork.satisfaction_for(world, comp_id)
	lines.append("Network: #%d" % comp_id)
	lines.append("Capacity: %d / %d units" % [supply, demand])
	lines.append("Satisfaction: %d%%" % int(sat * 100.0))
	return lines
