extends RefCounted

## Fertilizer chain tests (session-soil-exhaustion-3).
##
## Locks in the per-tile fertilizer mechanic + Composter recipe selection.
## Sub-suites cover everything from design Q15:
##   1. Composter selects recipe from input (multi-recipe like Smelter):
##      wheat → composter_low_wheat, sugar_beet → composter_mid_beet.
##      Verifies recipe_id auto-set + correct compost item produced.
##   2. Hand-apply state set correctly: try_apply_fertilizer writes the
##      tile_fertilizer_state dict with the right tier + duration.
##   3. Stacking rules (Q5):
##        a) lower-tier on higher-tier → REJECTED (no state change).
##        b) same tier → timer refreshed.
##        c) higher tier → state upgraded (tier + duration replaced).
##   4. Boost regen rate: LOW = 2× normal (1 point per 15 sec), MID = 4×
##      (1 point per 7.5 sec). 30 sec of LOW boost → ~2 points soil
##      recovered (vs ~1 unboosted).
##   5. Save round-trip preserves tile_fertilizer_state (v17 schema).
##      Pre-save apply, save, load into fresh world, verify state matches.
##      Plus: pristine tiles (no fertilizer) NOT in dict after load.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_fertilizer_chain.json"

static func test_name() -> String:
	return "fertilizer chain (composter recipes + hand-apply + stacking + boost regen + save v17)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. Composter recipe selection ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	# Place a Composter on plain ground.
	if not world.place_building(Buildings.Type.COMPOSTER, Vector2i(0, 0)):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "composter placement failed: %s" % world.last_building_place_error }
	var composter: Building = world.building_at(Vector2i(0, 0))

	# (1a) Wheat input → "composter_low_wheat" recipe → COMPOST_LOW × 1.
	composter.state["in_buffer"] = [[Items.Type.WHEAT, 2]]
	# Run 110 ticks (recipe is 100 ticks; 10-tick buffer for IDLE→RUNNING).
	for _i in 110:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, str(composter.state.get("recipe_id", "")) == "composter_low_wheat",
		"wheat → composter_low_wheat, got '%s'" % str(composter.state.get("recipe_id", "")))
	var low_count: int = _bag_count(composter.state.get("out_buffer", []), Items.Type.COMPOST_LOW)
	_check(failures, low_count == 1, "expected 1 COMPOST_LOW, got %d" % low_count)

	# (1b) Sugar Beet input → "composter_mid_beet" recipe → COMPOST_MID × 1.
	# Reset the composter (drain output + force IDLE so recipe re-selects).
	composter.state["in_buffer"] = [[Items.Type.SUGAR_BEET, 2]]
	composter.state["out_buffer"] = []
	composter.state["state"] = Processor.IDLE
	composter.state["progress"] = 0
	composter.state["recipe_id"] = ""
	# Sugar Beet recipe is 140 ticks; 150-tick window.
	for _i in 150:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, str(composter.state.get("recipe_id", "")) == "composter_mid_beet",
		"sugar_beet → composter_mid_beet, got '%s'" % str(composter.state.get("recipe_id", "")))
	var mid_count: int = _bag_count(composter.state.get("out_buffer", []), Items.Type.COMPOST_MID)
	_check(failures, mid_count == 1, "expected 1 COMPOST_MID, got %d" % mid_count)

	_disconnect(world); world.queue_free()

	# ---------- 2. Hand-apply state set correctly ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	# Deplete a tile so it's eligible for fertilizer (any soil-modified tile
	# qualifies; helper accepts any pos but boost is meaningless on pristine).
	world.tile_soil_modifications[Vector2i(50, 50)] = 50
	var applied: bool = world.try_apply_fertilizer(Vector2i(50, 50), Items.Type.COMPOST_LOW)
	_check(failures, applied, "try_apply_fertilizer should succeed on fresh tile")
	_check(failures, world.tile_fertilizer_tier(Vector2i(50, 50)) == Items.Type.COMPOST_LOW,
		"tile tier should be COMPOST_LOW, got %d" % world.tile_fertilizer_tier(Vector2i(50, 50)))
	_check(failures, abs(world.tile_fertilizer_remaining(Vector2i(50, 50)) - 30.0) < 0.001,
		"LOW remaining should be 30.0 sec, got %f" % world.tile_fertilizer_remaining(Vector2i(50, 50)))

	# ---------- 3. Stacking rules ----------
	# (3a) Same tier → timer refresh (verify by decaying then re-applying).
	world._tick_fertilizer_decay(10.0)   # 30 → 20 sec remaining
	_check(failures, abs(world.tile_fertilizer_remaining(Vector2i(50, 50)) - 20.0) < 0.001,
		"after 10s decay, LOW remaining should be 20.0, got %f" % world.tile_fertilizer_remaining(Vector2i(50, 50)))
	var refresh_applied: bool = world.try_apply_fertilizer(Vector2i(50, 50), Items.Type.COMPOST_LOW)
	_check(failures, refresh_applied, "same-tier re-apply should succeed (timer refresh)")
	_check(failures, abs(world.tile_fertilizer_remaining(Vector2i(50, 50)) - 30.0) < 0.001,
		"timer should refresh to 30.0, got %f" % world.tile_fertilizer_remaining(Vector2i(50, 50)))

	# (3b) Higher tier upgrade → tier replaced + new duration.
	var upgrade_applied: bool = world.try_apply_fertilizer(Vector2i(50, 50), Items.Type.COMPOST_MID)
	_check(failures, upgrade_applied, "higher-tier apply (LOW → MID) should succeed (upgrade)")
	_check(failures, world.tile_fertilizer_tier(Vector2i(50, 50)) == Items.Type.COMPOST_MID,
		"tier upgraded to MID")
	_check(failures, abs(world.tile_fertilizer_remaining(Vector2i(50, 50)) - 60.0) < 0.001,
		"MID remaining should be 60.0 sec, got %f" % world.tile_fertilizer_remaining(Vector2i(50, 50)))

	# (3c) Lower tier on higher tier → REJECTED.
	var reject_applied: bool = world.try_apply_fertilizer(Vector2i(50, 50), Items.Type.COMPOST_LOW)
	_check(failures, not reject_applied, "lower-tier-on-higher should REJECT (return false)")
	_check(failures, world.tile_fertilizer_tier(Vector2i(50, 50)) == Items.Type.COMPOST_MID,
		"tier should remain MID after rejected lower apply")
	_check(failures, abs(world.tile_fertilizer_remaining(Vector2i(50, 50)) - 60.0) < 0.001,
		"timer should remain at 60.0 (not refreshed by rejected apply)")

	_disconnect(world); world.queue_free()

	# ---------- 4a. Boost regen rate (isolated from decay) ----------
	# Decay-before-regen ordering in production means a 30-sec single-call
	# regen with a 30-sec LOW boost would lose the boost BEFORE regen runs.
	# That's correct for production (per-frame deltas are tiny so the
	# boost gets ~1800 boosted ticks before its 1-tick expiry). For testing
	# the multiplier in isolation, set the fertilizer state directly with
	# a long `remaining` so no decay fires during the regen call.
	world = GridWorldScript.new()
	parent.add_child(world)
	# Unfertilized control: 30 sec at 1× rate → +1 point.
	world.tile_soil_modifications[Vector2i(80, 80)] = 50
	world._tick_soil_regen(30.0)
	_check(failures, world.tile_soil_health(Vector2i(80, 80)) == 51,
		"unfertilized 30 sec from 50: expected 51 (1× rate), got %d" % world.tile_soil_health(Vector2i(80, 80)))

	# LOW boost: 30 sec at 2× rate → +2 points. Set state directly to
	# isolate from decay.
	world.tile_soil_modifications[Vector2i(70, 70)] = 50
	world.tile_fertilizer_state[Vector2i(70, 70)] = {"tier": Items.Type.COMPOST_LOW, "remaining": 200.0}
	world._tick_soil_regen(30.0)
	_check(failures, world.tile_soil_health(Vector2i(70, 70)) == 52,
		"LOW boost 30 sec from 50: expected 52 (2× rate), got %d" % world.tile_soil_health(Vector2i(70, 70)))

	# MID boost: 30 sec at 4× rate → +4 points.
	world.tile_soil_modifications[Vector2i(72, 72)] = 50
	world.tile_fertilizer_state[Vector2i(72, 72)] = {"tier": Items.Type.COMPOST_MID, "remaining": 200.0}
	world._tick_soil_regen(30.0)
	_check(failures, world.tile_soil_health(Vector2i(72, 72)) == 54,
		"MID boost 30 sec from 50: expected 54 (4× rate), got %d" % world.tile_soil_health(Vector2i(72, 72)))

	# ---------- 4b. Decay erases state when remaining hits 0 ----------
	# LOW with 30s remaining → after 30s decay → erased.
	world.tile_fertilizer_state[Vector2i(90, 90)] = {"tier": Items.Type.COMPOST_LOW, "remaining": 30.0}
	world._tick_fertilizer_decay(30.0)
	_check(failures, world.tile_fertilizer_tier(Vector2i(90, 90)) == -1,
		"LOW boost with 30s remaining should erase after 30s decay")
	# MID with 60s remaining → after 30s decay → still present, 30s left.
	world.tile_fertilizer_state[Vector2i(91, 91)] = {"tier": Items.Type.COMPOST_MID, "remaining": 60.0}
	world._tick_fertilizer_decay(30.0)
	_check(failures, world.tile_fertilizer_tier(Vector2i(91, 91)) == Items.Type.COMPOST_MID,
		"MID with 60s remaining should still be active after 30s decay")
	_check(failures, abs(world.tile_fertilizer_remaining(Vector2i(91, 91)) - 30.0) < 0.001,
		"MID remaining should be 30.0 after 30s decay, got %f" % world.tile_fertilizer_remaining(Vector2i(91, 91)))

	_disconnect(world); world.queue_free()

	# ---------- 5. Save round-trip preserves tile_fertilizer_state (v17) ----------
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	world = GridWorldScript.new()
	parent.add_child(world)
	# Set up two fertilized tiles + one pristine (control: should not appear in dict).
	world.tile_soil_modifications[Vector2i(100, 100)] = 50
	world.tile_soil_modifications[Vector2i(101, 100)] = 30
	world.try_apply_fertilizer(Vector2i(100, 100), Items.Type.COMPOST_LOW)
	world.try_apply_fertilizer(Vector2i(101, 100), Items.Type.COMPOST_MID)
	# Decay one slightly so we save with non-default remaining (stress field).
	world._tick_fertilizer_decay(7.0)
	var pre_save_low_remaining: float = world.tile_fertilizer_remaining(Vector2i(100, 100))
	var pre_save_mid_remaining: float = world.tile_fertilizer_remaining(Vector2i(101, 100))

	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16), {}):
		_cleanup(world, player_a, null, null, orig_path)
		return { "ok": false, "message": "save_game returned false at v17 round-trip" }

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_cleanup(world, player_a, world_b, player_b, orig_path)
		return { "ok": false, "message": "load_game failed at v17 round-trip: %s" % result.error_message }

	_check(failures, world_b.tile_fertilizer_tier(Vector2i(100, 100)) == Items.Type.COMPOST_LOW,
		"save round-trip: LOW tier preserved at (100, 100)")
	_check(failures, abs(world_b.tile_fertilizer_remaining(Vector2i(100, 100)) - pre_save_low_remaining) < 0.001,
		"save round-trip: LOW remaining preserved (pre=%f post=%f)" % [pre_save_low_remaining, world_b.tile_fertilizer_remaining(Vector2i(100, 100))])
	_check(failures, world_b.tile_fertilizer_tier(Vector2i(101, 100)) == Items.Type.COMPOST_MID,
		"save round-trip: MID tier preserved at (101, 100)")
	_check(failures, abs(world_b.tile_fertilizer_remaining(Vector2i(101, 100)) - pre_save_mid_remaining) < 0.001,
		"save round-trip: MID remaining preserved")
	# Pristine tile: no fertilizer state.
	_check(failures, world_b.tile_fertilizer_tier(Vector2i(999, 999)) == -1,
		"save round-trip: pristine tile has no fertilizer state (sparse default)")
	_check(failures, world_b.tile_fertilizer_state.size() == 2,
		"save round-trip: only 2 fertilized tiles in dict, got %d" % world_b.tile_fertilizer_state.size())

	_cleanup(world, player_a, world_b, player_b, orig_path)

	if failures.is_empty():
		return { "ok": true, "message": "all 5 sub-suites passed (composter + hand-apply + stacking + boost + save v17)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _bag_count(bag: Array, item_type: int) -> int:
	var n: int = 0
	for entry in bag:
		if int(entry[0]) == item_type:
			n += int(entry[1])
	return n

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

static func _cleanup(world, player_a, world_b, player_b, orig_path: String) -> void:
	_disconnect(world)
	if world != null:
		world.queue_free()
	if player_a != null:
		player_a.queue_free()
	_disconnect(world_b)
	if world_b != null:
		world_b.queue_free()
	if player_b != null:
		player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
