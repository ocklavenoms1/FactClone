extends RefCounted

## Wasteland mechanics tests (session-soil-exhaustion-4).
##
## Closes the soil arc: tile soil at 0 for grace period → scarred → only
## Premium Compost restores. Tests cover the full lifecycle:
##   1. Trigger: tile at soil 0 + grace expiry → scarred.
##   2. Grace reset: soil rises above 0 before grace expires → no scar.
##   3. Wasteland blocks regen: scarred tile, 60 sec ticks, soil stays 0.
##   4. Planter idle on wasteland: planter on scarred tile won't grow.
##   5. Premium Compost on wasteland: scarred flag erased, soil → 30,
##      fertilizer state HIGH/120s.
##   6. Save round-trip preserves both grace and scarred states (v18).
##   7. Composter recipes: BREAD × 2 → HIGH × 1, LOAF_PACK × 1 → HIGH × 1.
##   8. Stacking: HIGH > MID > LOW (apply MID to HIGH-fertilized rejected).
##   9. (14i) Grace rescue: HIGH applied during grace clears wasteland
##      state path — though strictly the test exercises any-tier rescue
##      (the grace-clear happens via _tick_soil_regen on next tick when
##      soil rises above 0).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_wasteland.json"

static func test_name() -> String:
	return "wasteland (trigger + grace + recovery + planter idle + save v18 + grace-rescue)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. Trigger: soil 0 + grace expiry → scarred ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	# Set a tile to soil 0 directly (skip the depletion machinery; we're
	# testing the wasteland trigger, not the depletion math).
	world.tile_soil_modifications[Vector2i(10, 10)] = 0
	# First regen tick at soil 0: starts grace timer.
	world._tick_soil_regen(0.1)
	_check(failures, world.tile_wasteland_state.has(Vector2i(10, 10)),
		"first tick at soil 0 should start grace timer")
	_check(failures, not world.is_wasteland_at(Vector2i(10, 10)),
		"tile is in grace, not yet scarred")
	var grace_remaining_initial: float = world.tile_wasteland_grace_remaining(Vector2i(10, 10))
	_check(failures, abs(grace_remaining_initial - (GridWorldScript.WASTELAND_GRACE_SEC - 0.1)) < 0.01,
		"after 0.1s tick, grace remaining ≈ %.1fs, got %f" % [GridWorldScript.WASTELAND_GRACE_SEC - 0.1, grace_remaining_initial])

	# Advance past grace period.
	world._tick_soil_regen(GridWorldScript.WASTELAND_GRACE_SEC + 1.0)
	_check(failures, world.is_wasteland_at(Vector2i(10, 10)),
		"after %.1fs+ at soil 0, tile should be scarred" % GridWorldScript.WASTELAND_GRACE_SEC)
	_disconnect(world); world.queue_free()

	# ---------- 2. Grace reset: soil rises above 0 before expiry ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	world.tile_soil_modifications[Vector2i(20, 20)] = 0
	# Start grace.
	world._tick_soil_regen(0.5)
	_check(failures, world.tile_wasteland_state.has(Vector2i(20, 20)),
		"grace started")
	# Bring soil above 0 BEFORE grace expires (emulate fertilizer-driven recovery).
	world.tile_soil_modifications[Vector2i(20, 20)] = 5
	# Next regen tick should detect soil > 0 and erase grace.
	world._tick_soil_regen(0.1)
	_check(failures, not world.tile_wasteland_state.has(Vector2i(20, 20)),
		"soil rose above 0 → grace state cleared")
	_check(failures, not world.is_wasteland_at(Vector2i(20, 20)),
		"tile should not be scarred (grace was reset)")
	_disconnect(world); world.queue_free()

	# ---------- 3. Wasteland blocks regen ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	# Force a tile straight to scarred state (skipping grace via direct
	# write — we're testing that scarred blocks regen, not the trigger).
	world.tile_soil_modifications[Vector2i(30, 30)] = 0
	world.tile_wasteland_state[Vector2i(30, 30)] = {"scarred": true, "decay_remaining": 0.0}
	# Tick 60 sec — regen would normally restore 2 soil points (1 per 30s).
	world._tick_soil_regen(60.0)
	_check(failures, world.tile_soil_health(Vector2i(30, 30)) == 0,
		"scarred tile soil should remain at 0 after 60s ticks, got %d" % world.tile_soil_health(Vector2i(30, 30)))
	_check(failures, world.is_wasteland_at(Vector2i(30, 30)),
		"scarred tile should remain scarred (no auto-clearing)")
	_disconnect(world); world.queue_free()

	# ---------- 4. Planter idle on wasteland ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	# Planter requires SOIL_TILLED overlay.
	world.set_overlay(Vector2i(40, 40), Terrain.Overlay.SOIL_TILLED)
	# Place a planter on a tile we'll force-scar.
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(40, 40), 0, Items.Type.WHEAT):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "planter placement failed: %s" % world.last_building_place_error }
	# Force the tile to scarred state.
	world.tile_soil_modifications[Vector2i(40, 40)] = 0
	world.tile_wasteland_state[Vector2i(40, 40)] = {"scarred": true, "decay_remaining": 0.0}
	var planter: Building = world.building_at(Vector2i(40, 40))
	# Tick the planter many times — growth must stay 0 (gated by wasteland check).
	for _i in 100:
		Planter.tick(planter, world)
	_check(failures, int(planter.state.get("growth", -1)) == 0,
		"planter on wasteland should stay at growth 0 after 100 ticks, got %d" % int(planter.state.get("growth", -1)))
	_disconnect(world); world.queue_free()

	# ---------- 5. Premium Compost on wasteland (de-wastelanding) ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	world.tile_soil_modifications[Vector2i(50, 50)] = 0
	world.tile_wasteland_state[Vector2i(50, 50)] = {"scarred": true, "decay_remaining": 0.0}
	# Apply HIGH — should de-wasteland AND apply boost.
	var applied: bool = world.try_apply_fertilizer(Vector2i(50, 50), Items.Type.COMPOST_HIGH)
	_check(failures, applied, "HIGH on wasteland should succeed")
	_check(failures, not world.is_wasteland_at(Vector2i(50, 50)),
		"after HIGH apply: scarred flag should be erased")
	_check(failures, world.tile_soil_health(Vector2i(50, 50)) == GridWorldScript.WASTELAND_RESTORE_SOIL,
		"after HIGH apply: soil should snap to %d, got %d" % [GridWorldScript.WASTELAND_RESTORE_SOIL, world.tile_soil_health(Vector2i(50, 50))])
	_check(failures, world.tile_fertilizer_tier(Vector2i(50, 50)) == Items.Type.COMPOST_HIGH,
		"after HIGH apply: tile fertilizer tier = HIGH")
	_check(failures, abs(world.tile_fertilizer_remaining(Vector2i(50, 50)) - 120.0) < 0.001,
		"after HIGH apply: fertilizer remaining = 120s, got %f" % world.tile_fertilizer_remaining(Vector2i(50, 50)))

	# Lower-than-HIGH on wasteland → REJECTED.
	world.tile_wasteland_state[Vector2i(51, 50)] = {"scarred": true, "decay_remaining": 0.0}
	world.tile_soil_modifications[Vector2i(51, 50)] = 0
	var low_on_waste: bool = world.try_apply_fertilizer(Vector2i(51, 50), Items.Type.COMPOST_LOW)
	_check(failures, not low_on_waste,
		"LOW on wasteland should be REJECTED (only HIGH restores)")
	_check(failures, world.is_wasteland_at(Vector2i(51, 50)),
		"after rejected LOW apply: tile still scarred")
	var mid_on_waste: bool = world.try_apply_fertilizer(Vector2i(51, 50), Items.Type.COMPOST_MID)
	_check(failures, not mid_on_waste,
		"MID on wasteland should be REJECTED (only HIGH restores)")
	_disconnect(world); world.queue_free()

	# ---------- 6. Save round-trip preserves grace + scarred (v18) ----------
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	world = GridWorldScript.new()
	parent.add_child(world)
	# Tile A: in grace, decay_remaining = 25.0 (specific value, easy to check).
	world.tile_soil_modifications[Vector2i(60, 60)] = 0
	world.tile_wasteland_state[Vector2i(60, 60)] = {"scarred": false, "decay_remaining": 25.0}
	# Tile B: scarred.
	world.tile_soil_modifications[Vector2i(61, 60)] = 0
	world.tile_wasteland_state[Vector2i(61, 60)] = {"scarred": true, "decay_remaining": 0.0}

	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16), {}):
		_cleanup(world, player_a, null, null, orig_path)
		return { "ok": false, "message": "save_game returned false at v18 round-trip" }

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_cleanup(world, player_a, world_b, player_b, orig_path)
		return { "ok": false, "message": "load_game failed at v18: %s" % result.error_message }

	# Verify both states preserved.
	_check(failures, not world_b.is_wasteland_at(Vector2i(60, 60)),
		"save round-trip: tile A (grace) NOT scarred")
	_check(failures, abs(world_b.tile_wasteland_grace_remaining(Vector2i(60, 60)) - 25.0) < 0.001,
		"save round-trip: tile A grace_remaining preserved at 25.0, got %f" % world_b.tile_wasteland_grace_remaining(Vector2i(60, 60)))
	_check(failures, world_b.is_wasteland_at(Vector2i(61, 60)),
		"save round-trip: tile B (scarred) preserved as wasteland")
	_check(failures, world_b.tile_wasteland_state.size() == 2,
		"save round-trip: only 2 wasteland-state entries in dict, got %d" % world_b.tile_wasteland_state.size())

	_cleanup(world, player_a, world_b, player_b, orig_path)

	# ---------- 7. Composter HIGH recipes ----------
	# (a) BREAD × 2 → COMPOST_HIGH × 1.
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.COMPOSTER, Vector2i(70, 70)):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "composter placement failed" }
	var composter: Building = world.building_at(Vector2i(70, 70))
	composter.state["in_buffer"] = [[Items.Type.BREAD, 2]]
	# Recipe is 200 ticks — run 220 to clear the cycle.
	for _i in 220:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, str(composter.state.get("recipe_id", "")) == "composter_high_bread",
		"BREAD → composter_high_bread, got '%s'" % str(composter.state.get("recipe_id", "")))
	var hi_count: int = _bag_count(composter.state.get("out_buffer", []), Items.Type.COMPOST_HIGH)
	_check(failures, hi_count == 1, "expected 1 COMPOST_HIGH from bread, got %d" % hi_count)

	# (b) LOAF_PACK × 1 → COMPOST_HIGH × 1. Reset + drive new cycle.
	composter.state["in_buffer"] = [[Items.Type.LOAF_PACK, 1]]
	composter.state["out_buffer"] = []
	composter.state["state"] = Processor.IDLE
	composter.state["progress"] = 0
	composter.state["recipe_id"] = ""
	for _i in 220:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, str(composter.state.get("recipe_id", "")) == "composter_high_loafpack",
		"LOAF_PACK → composter_high_loafpack, got '%s'" % str(composter.state.get("recipe_id", "")))
	var hi_count_2: int = _bag_count(composter.state.get("out_buffer", []), Items.Type.COMPOST_HIGH)
	_check(failures, hi_count_2 == 1, "expected 1 COMPOST_HIGH from loaf_pack, got %d" % hi_count_2)
	_disconnect(world); world.queue_free()

	# ---------- 8. Stacking: HIGH > MID > LOW ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	world.tile_soil_modifications[Vector2i(80, 80)] = 50
	# Apply HIGH first.
	world.try_apply_fertilizer(Vector2i(80, 80), Items.Type.COMPOST_HIGH)
	# MID on HIGH should reject.
	var mid_on_high: bool = world.try_apply_fertilizer(Vector2i(80, 80), Items.Type.COMPOST_MID)
	_check(failures, not mid_on_high,
		"MID on HIGH-fertilized tile should be REJECTED")
	_check(failures, world.tile_fertilizer_tier(Vector2i(80, 80)) == Items.Type.COMPOST_HIGH,
		"tier remains HIGH after rejected MID apply")
	# LOW on HIGH should also reject.
	var low_on_high: bool = world.try_apply_fertilizer(Vector2i(80, 80), Items.Type.COMPOST_LOW)
	_check(failures, not low_on_high,
		"LOW on HIGH-fertilized tile should be REJECTED")
	# But MID-then-HIGH should upgrade.
	world.tile_soil_modifications[Vector2i(81, 80)] = 50
	world.try_apply_fertilizer(Vector2i(81, 80), Items.Type.COMPOST_MID)
	var high_on_mid: bool = world.try_apply_fertilizer(Vector2i(81, 80), Items.Type.COMPOST_HIGH)
	_check(failures, high_on_mid, "HIGH on MID-fertilized tile should UPGRADE")
	_check(failures, world.tile_fertilizer_tier(Vector2i(81, 80)) == Items.Type.COMPOST_HIGH,
		"after upgrade: tier = HIGH")
	_disconnect(world); world.queue_free()

	# ---------- 9. (14i) Grace rescue ----------
	# Setup: tile soil = 0, grace started, NOT yet scarred.
	# Action: try_apply_fertilizer — any tier (even LOW). Boost added.
	# Next regen tick: soil rises above 0 → grace state erased.
	# Tile recovers normally (not scarred).
	world = GridWorldScript.new()
	parent.add_child(world)
	world.tile_soil_modifications[Vector2i(90, 90)] = 0
	# Start grace.
	world._tick_soil_regen(1.0)
	_check(failures, world.tile_wasteland_state.has(Vector2i(90, 90)) and not world.is_wasteland_at(Vector2i(90, 90)),
		"setup: tile in grace, not scarred")
	var grace_before: float = world.tile_wasteland_grace_remaining(Vector2i(90, 90))
	# Apply LOW — works on non-wasteland (grace is NOT wasteland).
	var rescue_applied: bool = world.try_apply_fertilizer(Vector2i(90, 90), Items.Type.COMPOST_LOW)
	_check(failures, rescue_applied, "LOW apply during grace should succeed (grace ≠ wasteland)")
	_check(failures, world.tile_fertilizer_tier(Vector2i(90, 90)) == Items.Type.COMPOST_LOW,
		"fertilizer tier = LOW after grace-rescue apply")
	# Drive the boosted regen — at 2× rate, soil should climb above 0
	# within a couple of seconds. Run 30 sec of ticks total (fits in
	# WASTELAND_GRACE_SEC=60 → won't scar).
	world._tick_soil_regen(30.0)
	_check(failures, world.tile_soil_health(Vector2i(90, 90)) > 0,
		"after grace-rescue + 30s boosted regen, soil > 0, got %d" % world.tile_soil_health(Vector2i(90, 90)))
	_check(failures, not world.tile_wasteland_state.has(Vector2i(90, 90)),
		"grace state should be erased (soil rose above 0)")
	_check(failures, not world.is_wasteland_at(Vector2i(90, 90)),
		"tile should NOT be scarred (rescued during grace)")
	_disconnect(world); world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all 9 sub-suites passed (trigger + grace + recovery + planter + save v18 + recipes + stacking + grace-rescue)" }
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
