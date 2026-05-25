class_name Windmill
extends RefCounted

## Windmill — wind-powered generator.
##
## 2x2 footprint. No resource dependency — output_active=true from
## placement. MAX_OUTPUT = 6 power units (60% of WaterWheel's 10,
## reflecting placement flexibility tradeoff: free placement vs lower
## throughput).
##
## State:
##   output_active: bool        — always true (kept for power_network
##                                interface parity with other generators)
##   blade_rotation: float      — visual rotation accumulator [0, TAU)
##
## Power network contract: when output_active (always for windmill),
## contributes MAX_OUTPUT to the supply of the component containing any
## adjacent pole. Adjacency resolved by Buildings.all_edge_cells() via
## PowerNetwork._adjacent_component_id (strict cardinal — generator rule).

const MAX_OUTPUT: int = 6
const ROTATION_PER_TICK: float = 0.10 * TAU / 20.0      # ~1 full rotation / 10 sec (slower than WaterWheel)

const SAIL_COLOR: Color = Color(0.92, 0.90, 0.82)       # off-white canvas
const FRAME_COLOR: Color = Color(0.45, 0.35, 0.25)      # wooden frame
const HUB_COLOR: Color = Color(0.30, 0.25, 0.20)        # dark hub center
const BASE_COLOR: Color = Color(0.55, 0.50, 0.45)       # stone base

static func make(pos: Vector2i) -> Building:
	var state: Dictionary = {
		"output_active": true,         # always true — no resource dep
		"blade_rotation": 0.0,
	}
	return Building.new(Buildings.Type.WINDMILL, pos, state)

## Tick: advance blade_rotation. output_active stays true (no condition).
static func tick(b: Building, _world) -> void:
	var rot: float = float(b.state.get("blade_rotation", 0.0)) + ROTATION_PER_TICK
	if rot >= TAU:
		rot -= TAU
	b.state["blade_rotation"] = rot

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# 2x2 base — stone foundation.
	var base_rect: Rect2 = Rect2(world_pos, Vector2(tile_size * 2, tile_size * 2))
	canvas.draw_rect(base_rect, BASE_COLOR, true)
	canvas.draw_rect(base_rect, FRAME_COLOR, false, 2.0)
	# Central tower — vertical bar from base to top.
	var center: Vector2 = world_pos + Vector2(tile_size, tile_size)
	var tower_w: float = float(tile_size) * 0.20
	var tower_rect: Rect2 = Rect2(
		Vector2(center.x - tower_w * 0.5, world_pos.y + float(tile_size) * 0.35),
		Vector2(tower_w, float(tile_size) * 1.3)
	)
	canvas.draw_rect(tower_rect, FRAME_COLOR, true)
	# 4 rotating sails — cross pattern from hub.
	var rot: float = float(b.state.get("blade_rotation", 0.0))
	var sail_len: float = float(tile_size) * 0.80
	for i in range(4):
		var angle: float = rot + (TAU / 4.0) * float(i)
		var tip: Vector2 = center + Vector2(cos(angle), sin(angle)) * sail_len
		canvas.draw_line(center, tip, SAIL_COLOR, 4.0)
	# Hub circle at center.
	canvas.draw_circle(center, float(tile_size) * 0.10, HUB_COLOR)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	lines.append("Output: %d / %d units (always active)" % [MAX_OUTPUT, MAX_OUTPUT])
	# Network info — only meaningful if adjacent to a pole.
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
	else:
		lines.append("Network: #%d" % comp_id)
	# Output_active suppression for symmetry with other generators in info display.
	lines.append("Status: %s" % ("Active" if bool(b.state.get("output_active", true)) else "Idle"))
	return lines
