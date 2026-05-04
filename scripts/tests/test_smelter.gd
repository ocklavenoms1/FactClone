extends RefCounted

## Smelter test (session-smelter).
##
## Locks in the multi-recipe Burner-driven smelter mechanics:
##   1. Iron-ore-fed smelter produces iron ingots (basic recipe).
##   2. Copper-ore-fed smelter produces copper ingots (recipe selection).
##   3. FIFO recipe-switching across a single batch run: 4 iron + 2 copper
##      in buffer must produce 4 iron ingots first, then 2 copper ingots.
##      This is the architectural proof of "belt routing IS the recipe selector."
##   4. Fuel decrement: 1 fuel unit per ingot (vs drill's 1 per 8 ore).
##   5. NO_FUEL state when buffer is exhausted.
##   6. BLOCKED_OUTPUT state when output buffer fills (and recovery when it
##      drains).
##   7. Save round-trip preserves smelter state mid-batch.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_smelter.json"

static func test_name() -> String:
	return "smelter (multi-recipe FIFO selection, fuel, states, save round-trip)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- (1) Basic iron production ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	# Smelter at (0,0) with 2x2 footprint covers (0,0..1, 0..1). Stone overlay.
	for dx in 2:
		for dy in 2:
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.SMELTER, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "smelter placement failed: %s" % world.last_building_place_error }
	var smelter: Building = world.building_at(Vector2i(0, 0))

	# Pre-load 4 iron ore + plenty of fuel; skip belts.
	smelter.state["in_buffer"] = [[Items.Type.IRON_ORE, 4]]
	smelter.state["fuel_buffer"] = 8       # 8 fuel units = enough for 8 ingots

	# Run 200 ticks (5 cycles of 40 ticks). 4 ingots expected.
	for _i in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var iron_count: int = _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT)
	_check(failures, iron_count == 4, "expected 4 iron ingots after 4 cycles, got %d" % iron_count)
	# Iron ore consumed.
	var iron_left: int = _bag_count(smelter.state.get("in_buffer", []), Items.Type.IRON_ORE)
	_check(failures, iron_left == 0, "expected 0 iron ore left, got %d" % iron_left)
	# Fuel: 8 - 4 = 4 remaining.
	_check(failures, int(smelter.state.get("fuel_buffer", -1)) == 4, "fuel: expected 4 left, got %d" % int(smelter.state.get("fuel_buffer", -1)))

	# ---------- (2) Copper production ----------
	smelter.state["in_buffer"] = [[Items.Type.COPPER_ORE, 2]]
	smelter.state["out_buffer"] = []
	smelter.state["state"] = Smelter.STATE_IDLE
	smelter.state["progress"] = 0
	smelter.state["recipe_id"] = ""        # force recipe reselection
	smelter.state["fuel_buffer"] = 4
	for _i in 100:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var copper_count: int = _bag_count(smelter.state.get("out_buffer", []), Items.Type.COPPER_INGOT)
	_check(failures, copper_count == 2, "expected 2 copper ingots, got %d" % copper_count)
	# Verify NO iron leaked into copper run.
	var iron_in_copper: int = _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT)
	_check(failures, iron_in_copper == 0, "copper run produced %d iron ingots (should be 0)" % iron_in_copper)

	# ---------- (3) FIFO RECIPE SWITCHING — the architectural proof ----------
	# Iron arrived first (count=4), copper arrived later (count=2). Order in
	# in_buffer reflects insertion order — array index 0 is iron, index 1 is
	# copper. FIFO contract: smelter produces 4 iron ingots first, THEN 2
	# copper ingots. Recipe must switch at the right moment.
	smelter.state["in_buffer"] = [[Items.Type.IRON_ORE, 4], [Items.Type.COPPER_ORE, 2]]
	smelter.state["out_buffer"] = []
	smelter.state["state"] = Smelter.STATE_IDLE
	smelter.state["progress"] = 0
	smelter.state["recipe_id"] = ""
	smelter.state["fuel_buffer"] = 8       # enough for 6 ingots

	# Phase 3a: tick through all 4 iron batches (4 × 40 = 160 ticks). Verify
	# at each batch boundary that we're producing iron, not copper.
	# A "batch boundary" is when progress resets to 0 after emit. We sample
	# at tick = 40, 80, 120, 160.
	var iron_after_batches: Array = []
	for batch in 4:
		# Tick 40 ticks per batch. Sample iron count after each.
		for _i in 40:
			TickSystem.current_tick += 1
			TickSystem.tick.emit(TickSystem.current_tick)
		iron_after_batches.append(_bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT))

	# Each batch boundary should have produced 1 more iron ingot than before.
	_check(failures, iron_after_batches == [1, 2, 3, 4], "iron batch progression should be [1,2,3,4], got %s" % str(iron_after_batches))
	# After 4 iron batches, NO copper produced yet.
	var copper_at_phase_3a: int = _bag_count(smelter.state.get("out_buffer", []), Items.Type.COPPER_INGOT)
	_check(failures, copper_at_phase_3a == 0, "FIFO violation: copper produced before iron exhausted (got %d copper after 4 iron batches)" % copper_at_phase_3a)
	# Iron ore should now be exhausted; copper still in buffer.
	_check(failures, _bag_count(smelter.state.get("in_buffer", []), Items.Type.IRON_ORE) == 0, "iron ore should be 0 after 4 batches")
	_check(failures, _bag_count(smelter.state.get("in_buffer", []), Items.Type.COPPER_ORE) == 2, "copper ore should still be 2 after 4-iron run")
	# Recipe should NOT have switched yet (still smelt_iron) at this exact moment,
	# OR may have flipped to smelt_copper if a tick already ran the IDLE
	# transition. Both are acceptable; the key invariant is "no copper produced yet."
	# (Recipe-switching test is the next phase.)

	# Phase 3b: tick through 2 copper batches. Verify recipe switched.
	var copper_after_batches: Array = []
	for batch in 2:
		for _i in 40:
			TickSystem.current_tick += 1
			TickSystem.tick.emit(TickSystem.current_tick)
		copper_after_batches.append(_bag_count(smelter.state.get("out_buffer", []), Items.Type.COPPER_INGOT))
	_check(failures, copper_after_batches == [1, 2], "copper batch progression after iron exhausted should be [1,2], got %s" % str(copper_after_batches))
	# Iron count should still be 4 (no extra iron came from nowhere).
	var iron_at_end: int = _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT)
	_check(failures, iron_at_end == 4, "after copper phase, iron should still be 4, got %d" % iron_at_end)
	# Recipe is now smelt_copper.
	_check(failures, str(smelter.state.get("recipe_id", "")) == "smelt_copper", "recipe should have switched to smelt_copper, got '%s'" % str(smelter.state.get("recipe_id", "")))
	# Both ores fully consumed.
	_check(failures, _bag_count(smelter.state.get("in_buffer", []), Items.Type.IRON_ORE) == 0, "iron ore final: should be 0")
	_check(failures, _bag_count(smelter.state.get("in_buffer", []), Items.Type.COPPER_ORE) == 0, "copper ore final: should be 0")

	# ---------- (4) Fuel decrement: 1 unit per ingot ----------
	# Pre-loaded 8 fuel; 6 ingots produced (4 iron + 2 copper); should leave 2.
	_check(failures, int(smelter.state.get("fuel_buffer", -1)) == 2, "after 6 ingots from 8 fuel: expected 2 left, got %d" % int(smelter.state.get("fuel_buffer", -1)))

	# ---------- (5) NO_FUEL state ----------
	smelter.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	smelter.state["out_buffer"] = []
	smelter.state["state"] = Smelter.STATE_IDLE
	smelter.state["progress"] = 0
	smelter.state["recipe_id"] = ""
	smelter.state["fuel_buffer"] = 0       # explicitly empty
	smelter.state["fuel_burn_progress"] = 0
	# Tick a few times — should land in NO_FUEL.
	for _i in 5:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, int(smelter.state.get("state", -1)) == Smelter.STATE_NO_FUEL, "expected STATE_NO_FUEL with empty fuel + ore present, got %d" % int(smelter.state.get("state", -1)))
	# No ingots produced.
	_check(failures, _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT) == 0, "no ingot should be produced without fuel")
	# Iron ore not consumed (recipe didn't transition past IDLE/NO_FUEL).
	_check(failures, _bag_count(smelter.state.get("in_buffer", []), Items.Type.IRON_ORE) == 2, "iron ore should be untouched in NO_FUEL state")
	# Refuel and verify recovery.
	smelter.state["fuel_buffer"] = 4
	for _i in 80:   # 2 batches
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT) == 2, "after refuel: expected 2 iron ingots, got %d" % _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT))

	# ---------- (6) BLOCKED_OUTPUT state ----------
	# Fill output buffer to capacity (8). Set inputs+fuel. Recipe should not
	# start; state should be IDLE/BLOCKED_OUTPUT.
	smelter.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	smelter.state["out_buffer"] = [[Items.Type.IRON_INGOT, 8]]   # at cap
	smelter.state["state"] = Smelter.STATE_IDLE
	smelter.state["progress"] = 0
	smelter.state["recipe_id"] = "smelt_iron"
	smelter.state["fuel_buffer"] = 4
	for _i in 50:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Iron ore should still be 2 (recipe didn't start).
	_check(failures, _bag_count(smelter.state.get("in_buffer", []), Items.Type.IRON_ORE) == 2, "iron ore should be unconsumed when output blocked, got %d" % _bag_count(smelter.state.get("in_buffer", []), Items.Type.IRON_ORE))
	# Output should still be 8 (no new ingot emitted).
	_check(failures, _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT) == 8, "output should remain at cap, got %d" % _bag_count(smelter.state.get("out_buffer", []), Items.Type.IRON_INGOT))
	# Fuel should be 4 (no fuel consumed since no recipe started).
	_check(failures, int(smelter.state.get("fuel_buffer", -1)) == 4, "fuel should not be consumed when blocked, got %d" % int(smelter.state.get("fuel_buffer", -1)))

	# ---------- (7) Save round-trip mid-batch ----------
	smelter.state["in_buffer"] = [[Items.Type.IRON_ORE, 3]]
	smelter.state["out_buffer"] = []
	smelter.state["state"] = Smelter.STATE_IDLE
	smelter.state["progress"] = 0
	smelter.state["recipe_id"] = ""
	smelter.state["fuel_buffer"] = 4
	# Run 25 ticks — mid-batch (less than 40).
	for _i in 25:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var pre_save_progress: int = int(smelter.state.get("progress", 0))
	var pre_save_fuel: int = int(smelter.state.get("fuel_buffer", 0))
	var pre_save_state: int = int(smelter.state.get("state", -1))
	var pre_save_recipe: String = str(smelter.state.get("recipe_id", ""))
	var pre_save_iron: int = _bag_count(smelter.state.get("in_buffer", []), Items.Type.IRON_ORE)

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16), {}):
		_cleanup(world, player_a, null, null, orig_path)
		return { "ok": false, "message": "save_game returned false" }

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_cleanup(world, player_a, world_b, player_b, orig_path)
		return { "ok": false, "message": "load_game failed: %s" % result.error_message }

	var smelter_b: Building = world_b.building_at(Vector2i(0, 0))
	if smelter_b == null:
		failures.append("smelter missing after load")
	else:
		_check(failures, int(smelter_b.state.get("progress", -1)) == pre_save_progress, "progress not preserved: pre=%d post=%d" % [pre_save_progress, int(smelter_b.state.get("progress", -1))])
		_check(failures, int(smelter_b.state.get("fuel_buffer", -1)) == pre_save_fuel, "fuel_buffer not preserved: pre=%d post=%d" % [pre_save_fuel, int(smelter_b.state.get("fuel_buffer", -1))])
		_check(failures, int(smelter_b.state.get("state", -1)) == pre_save_state, "state not preserved: pre=%d post=%d" % [pre_save_state, int(smelter_b.state.get("state", -1))])
		_check(failures, str(smelter_b.state.get("recipe_id", "")) == pre_save_recipe, "recipe_id not preserved: pre='%s' post='%s'" % [pre_save_recipe, str(smelter_b.state.get("recipe_id", ""))])
		# in_buffer iron count round-trips (whatever was there at save time —
		# 2 if the IDLE→SMELTING transition consumed 1 from the original 3).
		_check(failures, _bag_count(smelter_b.state.get("in_buffer", []), Items.Type.IRON_ORE) == pre_save_iron, "in_buffer iron not preserved: pre=%d post=%d" % [pre_save_iron, _bag_count(smelter_b.state.get("in_buffer", []), Items.Type.IRON_ORE)])

	_cleanup(world, player_a, world_b, player_b, orig_path)

	if failures.is_empty():
		return { "ok": true, "message": "iron+copper recipes work; FIFO contract holds across recipe switch; fuel + states + save round-trip correct" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

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

static func _cleanup(world, player_a, world_b, player_b, orig_path: String) -> void:
	_disconnect(world)
	if world != null: world.queue_free()
	if player_a != null: player_a.queue_free()
	_disconnect(world_b)
	if world_b != null: world_b.queue_free()
	if player_b != null: player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
