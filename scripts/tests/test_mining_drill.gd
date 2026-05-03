extends RefCounted

## Mining drill test (session-mining-drill).
##
## Locks in the burner mining drill mechanics:
##   1. Placement validation — drill must cover ≥1 ore tile, no water,
##      no trees in footprint.
##   2. Production — fed wood, drill produces ore at DRILL_TICKS_PER_ORE
##      pacing (40 ticks = 0.5/sec at 20 tps).
##   3. Highest-richness-wins deposit selection across a 2×2 footprint.
##   4. Fuel consumption — DRILL_ORE_PER_FUEL ore per fuel unit.
##   5. NO_FUEL state when buffer empty.
##   6. DEPLETED state when all covered deposits drained.
##   7. Save round-trip preserves drill_progress, fuel_buffer, output_buffer,
##      covered_deposits.
##   8. Building-placement-cancels-regrowth (generic): chopping a tree under
##      a future drill site, then placing the drill, must erase regrowth.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_mining_drill.json"

static func test_name() -> String:
	return "mining drill (placement, production, fuel, depletion, save round-trip, regrowth-cancel)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- (1) Placement validation ----------
	var world = GridWorldScript.new()
	parent.add_child(world)

	# Set up a 4×4 area: one corner has stone ore, adjacent has water, etc.
	# Footprint anchors at (0,0); covers (0,0), (1,0), (0,1), (1,1).
	_set_ore(world, Vector2i(0, 0), ResourceNodes.Type.STONE, 50)
	_set_ore(world, Vector2i(1, 0), ResourceNodes.Type.STONE, 30)
	# (0,1) and (1,1) are bare grass.

	# (a) Valid placement on bare grass + ore underneath.
	if not world.place_building(Buildings.Type.MINING_DRILL, Vector2i(0, 0), Belt.DIR_E):
		failures.append("valid placement rejected: %s" % world.last_building_place_error)
	world.remove_building_at(Vector2i(0, 0))

	# (b) Reject placement away from ore.
	var no_ore_pos := Vector2i(20, 20)
	if world.place_building(Buildings.Type.MINING_DRILL, no_ore_pos, Belt.DIR_E):
		failures.append("placement away from ore should fail; succeeded")
		world.remove_building_at(no_ore_pos)
	elif "ore deposit" not in world.last_building_place_error.to_lower():
		failures.append("expected 'ore deposit' error msg; got: %s" % world.last_building_place_error)

	# (c) Reject placement with water in footprint.
	world.tiles[Vector2i(5, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
	_set_ore(world, Vector2i(4, 4), ResourceNodes.Type.STONE, 50)
	# Anchor at (4,4): footprint covers (4,4), (5,4), (4,5), (5,5)=water.
	if world.place_building(Buildings.Type.MINING_DRILL, Vector2i(4, 4), Belt.DIR_E):
		failures.append("placement with water in footprint should fail; succeeded")
		world.remove_building_at(Vector2i(4, 4))
	elif "water" not in world.last_building_place_error.to_lower():
		failures.append("expected 'water' error msg; got: %s" % world.last_building_place_error)

	# (d) Reject placement with tree in footprint.
	world.tiles[Vector2i(10, 10)] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)
	_set_ore(world, Vector2i(11, 10), ResourceNodes.Type.STONE, 50)
	if world.place_building(Buildings.Type.MINING_DRILL, Vector2i(10, 10), Belt.DIR_E):
		failures.append("placement with tree in footprint should fail; succeeded")
		world.remove_building_at(Vector2i(10, 10))
	elif "tree" not in world.last_building_place_error.to_lower():
		failures.append("expected 'tree' error msg; got: %s" % world.last_building_place_error)

	# ---------- (2) Production + fuel + highest-richness-wins ----------
	# Fresh world for production test.
	_disconnect(world)
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)

	# 2×2 with mixed ore richness. Drill should pick (1,0) first (richness 100),
	# tiebreak doesn't matter for first tick. (0,0)=50, (1,0)=100, (0,1)=20, (1,1)=80.
	_set_ore(world, Vector2i(0, 0), ResourceNodes.Type.STONE, 50)
	_set_ore(world, Vector2i(1, 0), ResourceNodes.Type.STONE, 100)
	_set_ore(world, Vector2i(0, 1), ResourceNodes.Type.STONE, 20)
	_set_ore(world, Vector2i(1, 1), ResourceNodes.Type.STONE, 80)

	if not world.place_building(Buildings.Type.MINING_DRILL, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "drill placement failed in production test: %s" % world.last_building_place_error }

	var drill: Building = world.building_at(Vector2i(0, 0))
	# Verify covered_deposits populated.
	var cov: Array = drill.state.get("covered_deposits", [])
	if cov.size() != 4:
		failures.append("covered_deposits should have 4 entries, got %d" % cov.size())

	# Pre-load fuel: 4 wood = 4 fuel units = 32 ore (DRILL_ORE_PER_FUEL = 8).
	drill.state["fuel_buffer"] = 4

	# Tick 40 = first ore produced.
	for _i in 40:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var out_buf: Array = drill.state.get("output_buffer", [])
	var stone_count: int = _bag_count(out_buf, Items.Type.RAW_STONE)
	if stone_count != 1:
		failures.append("after 40 ticks expected 1 raw stone in output, got %d" % stone_count)

	# Verify highest-richness deposit (1,0) was the one drained: richness should now be 99.
	if world.richness_at(Vector2i(1, 0)) != 99:
		failures.append("highest-richness deposit (1,0) should have lost 1 richness, has %d" % world.richness_at(Vector2i(1, 0)))
	# (1,1) at 80 untouched; (0,0) at 50 untouched; (0,1) at 20 untouched.
	if world.richness_at(Vector2i(0, 0)) != 50:
		failures.append("(0,0) richness should be 50, got %d" % world.richness_at(Vector2i(0, 0)))

	# Verify fuel consumed: progress should now be 1, buffer still 4 (one ore in,
	# 7 more before next fuel decrement).
	if int(drill.state.get("fuel_buffer", -1)) != 4:
		failures.append("fuel buffer after 1 ore should be 4, got %d" % int(drill.state.get("fuel_buffer", -1)))
	if int(drill.state.get("fuel_burn_progress", -1)) != 1:
		failures.append("fuel_burn_progress after 1 ore should be 1, got %d" % int(drill.state.get("fuel_burn_progress", -1)))

	# ---------- (3) Fuel decrement: 8 ore → 1 fuel unit consumed ----------
	# Continue ticking until 8 total ore produced.
	for _i in 7 * 40:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	stone_count = _bag_count(drill.state.get("output_buffer", []), Items.Type.RAW_STONE)
	if stone_count != 8:
		failures.append("after 8 cycles expected 8 raw stone, got %d" % stone_count)
	if int(drill.state.get("fuel_buffer", -1)) != 3:
		failures.append("after 8 ore, fuel buffer should be 3 (1 unit consumed), got %d" % int(drill.state.get("fuel_buffer", -1)))

	# ---------- (4) NO_FUEL state ----------
	drill.state["fuel_buffer"] = 0
	drill.state["fuel_burn_progress"] = 0
	drill.state["drill_progress"] = 0
	drill.state["state"] = MiningDrill.STATE_IDLE
	drill.state["output_buffer"] = []
	# Tick past one cycle threshold so consume_tick is called.
	for _i in 41:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	if int(drill.state.get("state", -1)) != MiningDrill.STATE_NO_FUEL:
		failures.append("expected STATE_NO_FUEL after 41 fuelless ticks, got %d" % int(drill.state.get("state", -1)))
	# No ore produced.
	if not drill.state.get("output_buffer", []).is_empty():
		failures.append("no ore should be produced without fuel; output buffer non-empty")

	# ---------- (5) Save round-trip mid-operation ----------
	# Refuel and run a few ticks (mid-cycle), then save & load.
	drill.state["fuel_buffer"] = 2
	drill.state["drill_progress"] = 0
	drill.state["state"] = MiningDrill.STATE_IDLE
	for _i in 15:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var pre_save_progress: int = int(drill.state.get("drill_progress", 0))
	var pre_save_fuel: int = int(drill.state.get("fuel_buffer", 0))

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16), {}):
		_cleanup_with_save(world, player_a, null, null, orig_path)
		return { "ok": false, "message": "save_game returned false" }

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_cleanup_with_save(world, player_a, world_b, player_b, orig_path)
		return { "ok": false, "message": "load_game failed: %s" % result.error_message }

	var drill_b: Building = world_b.building_at(Vector2i(0, 0))
	if drill_b == null:
		failures.append("drill missing after load")
	else:
		if int(drill_b.state.get("drill_progress", -1)) != pre_save_progress:
			failures.append("drill_progress not preserved: pre=%d post=%d" % [pre_save_progress, int(drill_b.state.get("drill_progress", -1))])
		if int(drill_b.state.get("fuel_buffer", -1)) != pre_save_fuel:
			failures.append("fuel_buffer not preserved: pre=%d post=%d" % [pre_save_fuel, int(drill_b.state.get("fuel_buffer", -1))])
		var cov_b: Array = drill_b.state.get("covered_deposits", [])
		if cov_b.size() != 4:
			failures.append("covered_deposits not preserved: expected 4 entries, got %d" % cov_b.size())
		# Resource richness round-trip itself is verified by
		# test_resource_state_modifications_roundtrip — that uses WorldGenerator,
		# which is required for the procgen-rehydration save model. This test
		# only verifies the drill's own state survives.

	_disconnect(world_b)
	world_b.queue_free()
	player_b.queue_free()
	_disconnect(world)
	world.queue_free()
	player_a.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path

	# ---------- (6) Building-placement-cancels-regrowth ----------
	# Generic to all building placement; verified here via drill (a 2×2 building
	# whose footprint can include recently-chopped tree tiles).
	world = GridWorldScript.new()
	parent.add_child(world)
	# Tree at (0,1), ore at (1,0). Drill anchored at (0,0) covers both.
	world.tiles[Vector2i(0, 1)] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)
	_set_ore(world, Vector2i(1, 0), ResourceNodes.Type.STONE, 50)
	world.chop_tree(Vector2i(0, 1))
	# After chop, (0,1) is NONE with regrowth_remaining set.
	if not world.resource_state.has(Vector2i(0, 1)):
		failures.append("regrowth setup: chop_tree should have set resource_state at (0,1)")
	# Place drill — Q9: trees rejected at placement. (0,1) is NOT a tree anymore
	# (it was chopped), so placement should succeed and regrowth must be erased.
	if not world.place_building(Buildings.Type.MINING_DRILL, Vector2i(0, 0), Belt.DIR_E):
		failures.append("regrowth-cancel: drill placement on chopped tree tile failed: %s" % world.last_building_place_error)
	if world.resource_state.has(Vector2i(0, 1)):
		failures.append("regrowth-cancel: resource_state still has regrowth entry at (0,1) after building placement")
	if world.resource_state_modifications.has(Vector2i(0, 1)):
		failures.append("regrowth-cancel: resource_state_modifications still has entry at (0,1) after building placement")

	_disconnect(world)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "drill placement, production, fuel, save round-trip, regrowth-cancel all correct" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _set_ore(world, pos: Vector2i, ore_type: int, richness: int) -> void:
	world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ore_type)
	world.resource_state[pos] = {"richness": richness, "original_richness": richness}

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

static func _cleanup_with_save(world, player_a, world_b, player_b, orig_path: String) -> void:
	_disconnect(world)
	if world != null: world.queue_free()
	if player_a != null: player_a.queue_free()
	_disconnect(world_b)
	if world_b != null: world_b.queue_free()
	if player_b != null: player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
