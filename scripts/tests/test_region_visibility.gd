extends RefCounted

## Region visibility / vision-update test.
##
## Locks in the M-key map fog-of-war mechanics:
##   1. initial_reveal() marks 7×7 = 49 regions as fog (state=1)
##   2. update_vision(player_region) upgrades 5×5 around player to active (state=2)
##   3. update_vision returns the list of changed regions (for map dirty tracking)
##   4. Region cross demotes out-of-range active regions to fog;
##      upgrades new in-range regions to active
##   5. Boundary clipping: at world corner, vision area clips to 3×3 (9 regions)
##   6. No out-of-bounds regions are ever tracked
##   7. region_of_world_pos correctly maps world position to region coord

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "region visibility (initial reveal + vision updates + boundary clipping)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var world = GridWorldScript.new()
	parent.add_child(world)

	# 1. initial_reveal: 49 fog regions, no active.
	world.initial_reveal()
	_check(failures, _count_state(world, 1) == 49, "initial_reveal: expected 49 fog regions, got %d" % _count_state(world, 1))
	_check(failures, _count_state(world, 2) == 0, "initial_reveal: expected 0 active regions, got %d" % _count_state(world, 2))

	# 2. update_vision(0, 0): 25 active (5×5), 24 fog (49 - 25).
	var changed_first: Array = world.update_vision(Vector2i(0, 0))
	_check(failures, _count_state(world, 2) == 25, "update_vision(0,0): expected 25 active, got %d" % _count_state(world, 2))
	_check(failures, _count_state(world, 1) == 24, "update_vision(0,0): expected 24 fog, got %d" % _count_state(world, 1))
	# 3. Returned changed list: 25 regions (all upgraded from fog/unrevealed to active).
	_check(failures, changed_first.size() == 25, "update_vision(0,0) changed list: expected 25, got %d" % changed_first.size())

	# 4. Region cross to (3, 0). 5×5 around (3, 0) = (1..5, -2..2).
	# Overlap with (0, 0)'s 5×5 (-2..2, -2..2) = (1..2, -2..2) = 10 regions.
	# So 15 new active, 15 demoted to fog. Changed = 30.
	var changed_move: Array = world.update_vision(Vector2i(3, 0))
	_check(failures, _count_state(world, 2) == 25, "after cross to (3,0): still 25 active, got %d" % _count_state(world, 2))
	_check(failures, changed_move.size() == 30, "cross to (3,0) changed list: expected 30, got %d" % changed_move.size())

	# 5. Boundary clipping: move to world corner. WORLD_MIN=-8, WORLD_MAX=8;
	# valid region range is [-8, 7] in each axis. At (7, 7), 5×5 area would
	# be (5..9, 5..9), clipped at REGION_MAX=8 (exclusive) → (5..7, 5..7) = 3×3 = 9.
	world.update_vision(Vector2i(7, 7))
	_check(failures, _count_state(world, 2) == 9, "boundary at (7,7): expected 9 active (3×3 clipped), got %d" % _count_state(world, 2))

	# 6. No out-of-bounds regions tracked.
	var oob: int = 0
	for r in world.region_visibility.keys():
		if r.x < WorldGenerator.REGION_MIN or r.x >= WorldGenerator.REGION_MAX \
		or r.y < WorldGenerator.REGION_MIN or r.y >= WorldGenerator.REGION_MAX:
			oob += 1
	_check(failures, oob == 0, "out-of-bounds regions tracked: %d (expected 0)" % oob)

	# 7. region_of_world_pos: convert player world position to region coords.
	# Player at world tile (0, 0): region (0, 0). At (32, 32): region (1, 1).
	# At (-1, -1): region (-1, -1). At (95, 31): region (2, 0).
	var TILE: int = GridWorldScript.TILE_SIZE
	_check(failures, GridWorldScript.region_of_world_pos(Vector2(0, 0)) == Vector2i(0, 0), "region_of_world_pos(0,0) wrong")
	_check(failures, GridWorldScript.region_of_world_pos(Vector2(32 * TILE, 32 * TILE)) == Vector2i(1, 1), "region_of_world_pos(32,32 tiles) wrong")
	_check(failures, GridWorldScript.region_of_world_pos(Vector2(-TILE, -TILE)) == Vector2i(-1, -1), "region_of_world_pos(-1,-1 tiles) wrong")
	_check(failures, GridWorldScript.region_of_world_pos(Vector2(95 * TILE, 31 * TILE)) == Vector2i(2, 0), "region_of_world_pos(95,31 tiles) wrong")

	_cleanup(world)

	if failures.is_empty():
		return { "ok": true, "message": "initial_reveal + 5×5 vision + region cross + boundary clipping all correct" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _count_state(world: GridWorld, state: int) -> int:
	var n: int = 0
	for r in world.region_visibility.keys():
		if int(world.region_visibility[r]) == state:
			n += 1
	return n

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _cleanup(world) -> void:
	if world == null: return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
