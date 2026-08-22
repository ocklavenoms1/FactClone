class_name Substation
extends RefCounted

## Substation — the backbone wire tier (Electricity Session 3).
##
## 2x2, wire range 11, supply radius 4. It is the piece that bridges two
## separate pole clusters into one network.
##
## Coverage is measured from the FOOTPRINT, not the anchor: radius 4 beyond
## every one of the four footprint cells reaches anchor-4 .. anchor+1+4 on
## each axis, which is TEN cells per axis — a 10x10 covered area.
##
## Beware the two different 9s in this session. 9x9 is (2*4+1)^2, the 1x1
## formula, and it is what a CONSUMER searches: power_satisfaction_at scans
## (2r + 1)^2 outward from the consumer itself, independent of any pole's
## footprint. That box is odd-sided because it centres on a single cell —
## which is exactly why it cannot describe an even-sided footprint. Sizing a
## substation's scan box to 9 silently drops its far edge.
##
## The r above is NOT yet 4, or per-tier at all. Task 4 landed
## PowerNetwork.SUPPLY_RADIUS_BY_TYPE and supply_radius() but wired neither
## consumer path to them: power_satisfaction_at and _supply_component_id both
## still use SUPPLY_RADIUS_DEFAULT (1). Task 5 connects them, and only then
## does this substation project anything.
##
## This is the project's first MULTI-CELL POLE. Every distance computation in
## power_network.gd that assumes a pole occupies exactly one cell has to be
## taught otherwise. The WIRE side learned in Task 4 — PowerNetwork
## ._pole_distance measures footprint to footprint, and
## grid_world._pole_wire_anchor hangs this tier's wires from its body centre
## rather than its anchor cell. The SUPPLY side is still Task 5's.
##
## State: empty {} (network membership lives at world._pole_component).

const BODY_COLOR: Color = Color(0.38, 0.40, 0.46)        # cold steel-blue
const FRAME_COLOR: Color = Color(0.26, 0.28, 0.33)
const INSULATOR_COLOR: Color = Color(0.72, 0.74, 0.70)   # pale ceramic

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.SUBSTATION, pos, {})

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# Edge-to-edge across the full 2x2 footprint: world_pos is the ANCHOR
	# cell's top-left and the body really is 2 tiles on a side, so a hover
	# outline or ghost-preview rect built as Rect2(world_pos, tile_size * 2)
	# aligns with it exactly. Matches every other 2x2 building — water_wheel,
	# windmill and steam_generator all draw that same rect. It matters more
	# here than for them: the substation is the only non-walkable pole tier,
	# so any unpainted margin would read as ground the player can neither
	# stand on nor build in.
	var body: Rect2 = Rect2(world_pos, Vector2(float(tile_size) * 2.0, float(tile_size) * 2.0))
	canvas.draw_rect(body, BODY_COLOR, true)
	canvas.draw_rect(body, FRAME_COLOR, false, 2.0)
	# One insulator at each of the four CELL CENTRES — not the body's corners
	# — so the piece reads as high-voltage gear rather than a big box while
	# marking the four cells it occupies.
	var r: float = float(tile_size) * 0.13
	for cell_center in [Vector2(0.5, 0.5), Vector2(1.5, 0.5), Vector2(0.5, 1.5), Vector2(1.5, 1.5)]:
		canvas.draw_circle(world_pos + cell_center * float(tile_size), r, INSULATOR_COLOR)
