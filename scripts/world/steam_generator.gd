class_name SteamGenerator
extends RefCounted

## Steam Generator — fuel-powered electric generator.
##
## 2x2 footprint. Burner module 5th consumer (after Drill, Smelter,
## Inserter, Fast Inserter). MAX_OUTPUT = 20 power units when active.
## Cycle-based fuel: 1 fuel unit per CYCLE_TICKS (20 ticks = 1.0s).
##
## Fuel economy:
##   - 1 WOOD = 1 unit = 1 second of 20-power output
##   - 1 COAL = 4 units = 4 seconds of 20-power output
##   - 1 FUEL_BRIQUETTE = 8 units = 8 seconds of 20-power output
##
## State:
##   dir: int                    — facing direction (fuel input port rotates)
##   output_active: bool         — set per-tick based on fuel availability
##   fuel_buffer: int            — Burner units remaining
##   fuel_burn_progress: int     — Burner ticks toward next unit
##   last_fuel_item: int         — Burner display field (-1 = none yet)
##
## Power network contract: when output_active, contributes MAX_OUTPUT to
## the supply of the component containing any adjacent pole. Adjacency
## resolved by Buildings.all_edge_cells() — strict cardinal generator rule.

const MAX_OUTPUT: int = 20
const CYCLE_TICKS: int = 20                          # 1 fuel unit per cycle (1.0s @ 20 TPS)

const FUEL_PORT_DIR: int = Belt.DIR_S                # restrict fuel intake to S edge (canonical)

const BODY_COLOR: Color = Color(0.40, 0.35, 0.32)    # dark iron
const STACK_COLOR: Color = Color(0.30, 0.25, 0.22)   # darker smokestack
const STEAM_COLOR: Color = Color(0.90, 0.90, 0.92, 0.7)  # translucent white steam
const IDLE_TINT: Color = Color(0.55, 0.55, 0.55)

## Build initial state. Burner fields merged in via Burner.make_state().
static func make(pos: Vector2i, dir: int = 0) -> Building:
	var state: Dictionary = {
		"dir": dir,
		"output_active": false,
	}
	for k in Burner.make_state().keys():
		state[k] = Burner.make_state()[k]
	return Building.new(Buildings.Type.STEAM_GENERATOR, pos, state)

## Tick: pull fuel, consume fuel unit per cycle, update output_active.
static func tick(b: Building, world) -> void:
	# Step 1: pull fuel into buffer if low (S edge, rotated by b.dir).
	Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR))
	# Step 2: try to consume 1 fuel unit this cycle. If success, output_active.
	var consumed: bool = Burner.consume_tick(b, CYCLE_TICKS)
	b.state["output_active"] = consumed

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var active: bool = bool(b.state.get("output_active", false))
	var tint: Color = Color.WHITE if active else IDLE_TINT
	# 2x2 body.
	var body_rect: Rect2 = Rect2(world_pos, Vector2(tile_size * 2, tile_size * 2))
	canvas.draw_rect(body_rect, BODY_COLOR * tint, true)
	canvas.draw_rect(body_rect, STACK_COLOR, false, 2.0)
	# Smokestack — vertical bar on right half.
	var stack_w: float = float(tile_size) * 0.35
	var stack_rect: Rect2 = Rect2(
		Vector2(world_pos.x + float(tile_size) * 1.3, world_pos.y + float(tile_size) * 0.2),
		Vector2(stack_w, float(tile_size) * 0.9)
	)
	canvas.draw_rect(stack_rect, STACK_COLOR, true)
	# Steam puff visual when active — 3 translucent circles above smokestack.
	if active:
		var stack_top: Vector2 = stack_rect.position + Vector2(stack_w * 0.5, 0)
		for i in range(3):
			var offset: Vector2 = Vector2(float(i - 1) * 4.0, -float(tile_size) * (0.15 + 0.10 * float(i)))
			canvas.draw_circle(stack_top + offset, float(tile_size) * 0.10, STEAM_COLOR)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	var active: bool = bool(b.state.get("output_active", false))
	var output_str: String = "%d / %d units" % [MAX_OUTPUT if active else 0, MAX_OUTPUT]
	var status_str: String = "active" if active else "no fuel"
	lines.append("Output: %s (%s)" % [output_str, status_str])
	# Burner.info_lines provides fuel buffer state, current fuel item, etc.
	for line in Burner.info_lines(b):
		lines.append(line)
	# Network info.
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
	else:
		lines.append("Network: #%d" % comp_id)
	# Facing.
	lines.append("Facing: %s (R to rotate; fuel port on S edge of canonical)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])
	return lines
