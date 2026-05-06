extends RefCounted

## Soil exhaustion Session 1 tests (session-soil-exhaustion-1).
##
## Locks in the foundation mechanics shipped this session:
##   1. region_soil_health helper: sparse storage, default 100.
##   2. deplete_region_soil clamped at 0; sparse erase when restored to 100.
##   3. Per-crop soil_cost: WHEAT=5, SUGAR_BEET=8, FLAX=3.
##   4. Depletion-on-extract: try_extract decrements region soil correctly.
##   5. Multi-region isolation: harvests in region A don't affect region B.
##   6. Soil-zero gate: planter at growth=0 in dead region stays idle.
##   7. In-progress finish: planter at growth>0 in dead region keeps ticking
##      and finishes; output reaches ripe; soil clamps at 0.
##   8. Save round-trip preserves region_soil_modifications (v15 schema).
##   9. Edge case: planter placed in already-dead region stays idle from
##      tick 1 (no grace period).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_soil_exhaustion.json"

static func test_name() -> String:
	return "soil exhaustion (region depletion + zero-gate + isolation + save)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. region_soil_health helper ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	# Default 100 for any region not in modifications.
	_check(failures, world.region_soil_health(Vector2i(0, 0)) == 100,
		"default soil should be 100 for absent region")
	_check(failures, world.region_soil_health(Vector2i(-3, 7)) == 100,
		"default soil should be 100 for any pristine region")

	# ---------- 2. deplete_region_soil ----------
	var new_val: int = world.deplete_region_soil(Vector2i(1, 1), 5)
	_check(failures, new_val == 95, "after deplete 5: should be 95, got %d" % new_val)
	_check(failures, world.region_soil_health(Vector2i(1, 1)) == 95,
		"region (1,1) read should now be 95")
	# Modifications dict has the entry.
	_check(failures, world.region_soil_modifications.has(Vector2i(1, 1)),
		"depleted region should appear in modifications dict")
	# Other regions still default 100.
	_check(failures, world.region_soil_health(Vector2i(2, 2)) == 100,
		"region (2,2) should still be 100 (multi-region isolation)")
	# Depleting again accumulates.
	world.deplete_region_soil(Vector2i(1, 1), 30)
	_check(failures, world.region_soil_health(Vector2i(1, 1)) == 65,
		"after another 30: should be 65, got %d" % world.region_soil_health(Vector2i(1, 1)))
	# Over-depletion clamped at 0.
	world.deplete_region_soil(Vector2i(1, 1), 999)
	_check(failures, world.region_soil_health(Vector2i(1, 1)) == 0,
		"over-deplete should clamp at 0, got %d" % world.region_soil_health(Vector2i(1, 1)))

	# ---------- 3. Per-crop soil_cost values ----------
	_check(failures, Planter.soil_cost_for(Items.Type.WHEAT) == 5, "WHEAT soil_cost should be 5")
	_check(failures, Planter.soil_cost_for(Items.Type.SUGAR_BEET) == 8, "SUGAR_BEET soil_cost should be 8")
	_check(failures, Planter.soil_cost_for(Items.Type.FLAX) == 3, "FLAX soil_cost should be 3")
	_check(failures, Planter.max_growth_for(Items.Type.WHEAT) == 600, "WHEAT growth_ticks should be 600")
	# Backward-compat: max_growth_for unchanged callers.

	# ---------- 4. Depletion-on-extract via try_extract ----------
	# Reset to fresh world for clarity.
	_disconnect(world); world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	# Place a WHEAT planter at tile (0, 0) → region (0, 0).
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED)
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(0, 0), 0, Items.Type.WHEAT):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "wheat planter placement failed" }
	var p1: Building = world.building_at(Vector2i(0, 0))
	# Force ripe state (skip 600-tick growth).
	p1.state["growth"] = Planter.max_growth_for(Items.Type.WHEAT)
	p1.state["output"] = 1
	# Extract — soil should drop 5.
	var extracted: int = Planter.try_extract(p1, world)
	_check(failures, extracted == Items.Type.WHEAT, "extract should return WHEAT")
	_check(failures, world.region_soil_health(Vector2i(0, 0)) == 95,
		"after 1 wheat extract: region (0,0) soil should be 95, got %d" % world.region_soil_health(Vector2i(0, 0)))
	# Try-extract on empty planter → no-op, no soil change.
	var none: int = Planter.try_extract(p1, world)
	_check(failures, none == -1, "try_extract on empty planter should return -1")
	_check(failures, world.region_soil_health(Vector2i(0, 0)) == 95,
		"empty extract should NOT touch soil (still 95), got %d" % world.region_soil_health(Vector2i(0, 0)))

	# ---------- 5. Multi-region isolation ----------
	# Place SUGAR_BEET planter at tile (40, 40) → region (1, 1) (40 / 32 = 1).
	world.set_overlay(Vector2i(40, 40), Terrain.Overlay.SOIL_TILLED)
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(40, 40), 0, Items.Type.SUGAR_BEET):
		_cleanup(world)
		return { "ok": false, "message": "sugar beet planter placement failed" }
	var p2: Building = world.building_at(Vector2i(40, 40))
	p2.state["growth"] = Planter.max_growth_for(Items.Type.SUGAR_BEET)
	p2.state["output"] = 1
	# Extract → only region (1, 1) drops.
	Planter.try_extract(p2, world)
	_check(failures, world.region_soil_health(Vector2i(1, 1)) == 92,
		"after sugar beet extract: region (1,1) should be 92, got %d" % world.region_soil_health(Vector2i(1, 1)))
	_check(failures, world.region_soil_health(Vector2i(0, 0)) == 95,
		"region (0,0) should remain at 95 — no global leak from (1,1) extract")
	_check(failures, world.region_soil_health(Vector2i(2, 2)) == 100,
		"region (2,2) should still be 100 — completely untouched")

	# ---------- 6. Soil-zero gate: planter at growth=0 stays idle ----------
	# Force region (0, 0) to 0.
	world.region_soil_modifications[Vector2i(0, 0)] = 0
	# Reset planter state to "just finished, ready to start new cycle".
	p1.state["growth"] = 0
	p1.state["output"] = 0
	# Tick once. Growth must NOT increment (soil-zero gate).
	Planter.tick(p1, world)
	_check(failures, int(p1.state["growth"]) == 0,
		"soil-zero gate: planter at growth=0 in dead region should stay at 0, got %d" % int(p1.state["growth"]))

	# ---------- 7. In-progress crop finishes despite zero soil ----------
	# Set planter to mid-growth.
	p1.state["growth"] = 300
	p1.state["output"] = 0
	# Region (0, 0) soil is still 0.
	_check(failures, world.region_soil_health(Vector2i(0, 0)) == 0,
		"setup: region (0,0) should be at 0")
	# Tick once: growth should advance to 301 (in-progress, soil-gate doesn't block).
	Planter.tick(p1, world)
	_check(failures, int(p1.state["growth"]) == 301,
		"in-progress crop should keep growing in dead soil; expected 301, got %d" % int(p1.state["growth"]))
	# Tick to completion.
	for _i in 600:
		Planter.tick(p1, world)
	_check(failures, int(p1.state["output"]) == 1,
		"in-progress crop should finish even in dead soil; output should be 1, got %d" % int(p1.state["output"]))
	# Extract — soil drops further? It's already 0 (clamped). Stay 0.
	Planter.try_extract(p1, world)
	_check(failures, world.region_soil_health(Vector2i(0, 0)) == 0,
		"over-deplete clamped at 0; should still be 0")

	# ---------- 8. Edge case: planter placed in already-dead region ----------
	# Place a fresh planter in region (1, 1) which is already at 92 — but
	# manually set region (5, 5) to 0, then place planter there.
	world.region_soil_modifications[Vector2i(5, 5)] = 0
	# Tile (160, 160) → region (5, 5) (160/32 = 5).
	world.set_overlay(Vector2i(160, 160), Terrain.Overlay.SOIL_TILLED)
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(160, 160), 0, Items.Type.FLAX):
		_cleanup(world)
		return { "ok": false, "message": "dead-region planter placement failed" }
	var p3: Building = world.building_at(Vector2i(160, 160))
	# Tick once; growth must stay at 0 (no grace period — gate fires from
	# tick 1 in already-dead region).
	Planter.tick(p3, world)
	_check(failures, int(p3.state.get("growth", -1)) == 0,
		"dead-region planter: growth should stay at 0 from tick 1, got %d" % int(p3.state.get("growth", -1)))
	# Tick 100 more times. Still 0.
	for _i in 100:
		Planter.tick(p3, world)
	_check(failures, int(p3.state.get("growth", -1)) == 0,
		"dead-region planter: growth should still be 0 after 100 ticks, got %d" % int(p3.state.get("growth", -1)))

	# ---------- 9. Save round-trip preserves region_soil_modifications ----------
	# Capture current state.
	var pre_save_r0: int = world.region_soil_health(Vector2i(0, 0))      # 0
	var pre_save_r1: int = world.region_soil_health(Vector2i(1, 1))      # 92
	var pre_save_r5: int = world.region_soil_health(Vector2i(5, 5))      # 0
	var pre_save_r99: int = world.region_soil_health(Vector2i(99, 99))   # 100 (default)

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16), {}):
		_cleanup_full(world, player_a, null, null, orig_path)
		return { "ok": false, "message": "save_game returned false" }

	# Load into fresh world.
	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_cleanup_full(world, player_a, world_b, player_b, orig_path)
		return { "ok": false, "message": "load_game failed: %s" % result.error_message }

	_check(failures, world_b.region_soil_health(Vector2i(0, 0)) == pre_save_r0,
		"save round-trip: region (0,0) pre=%d post=%d" % [pre_save_r0, world_b.region_soil_health(Vector2i(0, 0))])
	_check(failures, world_b.region_soil_health(Vector2i(1, 1)) == pre_save_r1,
		"save round-trip: region (1,1) pre=%d post=%d" % [pre_save_r1, world_b.region_soil_health(Vector2i(1, 1))])
	_check(failures, world_b.region_soil_health(Vector2i(5, 5)) == pre_save_r5,
		"save round-trip: region (5,5) pre=%d post=%d" % [pre_save_r5, world_b.region_soil_health(Vector2i(5, 5))])
	_check(failures, world_b.region_soil_health(Vector2i(99, 99)) == pre_save_r99,
		"save round-trip: pristine region (99,99) should default to 100, got %d" % world_b.region_soil_health(Vector2i(99, 99)))
	# Save format: depleted regions present, pristine NOT in modifications dict.
	_check(failures, not world_b.region_soil_modifications.has(Vector2i(99, 99)),
		"save round-trip: pristine region (99,99) should NOT appear in modifications dict (sparse)")

	_cleanup_full(world, player_a, world_b, player_b, orig_path)

	if failures.is_empty():
		return { "ok": true, "message": "soil depletion + zero-gate + isolation + save round-trip + dead-region edge case all correct" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

static func _cleanup(world) -> void:
	_disconnect(world)
	if world != null: world.queue_free()

static func _cleanup_full(world, player_a, world_b, player_b, orig_path: String) -> void:
	_disconnect(world)
	if world != null: world.queue_free()
	if player_a != null: player_a.queue_free()
	_disconnect(world_b)
	if world_b != null: world_b.queue_free()
	if player_b != null: player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
