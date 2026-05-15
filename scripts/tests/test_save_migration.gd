extends RefCounted

## Save migration framework tests (session-save-migration).
##
## Replaces hard-fail-on-mismatch with chained migrations. Tests cover
## the framework primitives + the v17→v18 migration shipped this
## session, plus failure modes the framework must handle gracefully.
##
## Sub-suites:
##   1. MIGRATIONS registry shape — keys are int source versions, values
##      are method names dispatched in _dispatch_migration.
##   2. _migrate_v17_to_v18 happy path — minimal v17 dict in, v18 dict
##      out, tile_wasteland_state added with empty Array, version bumped.
##   3. _try_migrate single-step — v17 → v18 chain runs one step.
##   4. _try_migrate no-op — already-current version returns input dict.
##   5. _try_migrate no-path failure — v14 input → null.
##   6. _try_migrate version-bump verification — broken migration (test
##      fixture: dispatch a known-bad name) → null with push_error.
##   7. End-to-end via load_game — write a v17 save file with realistic
##      data, call load_game, assert success + tile_wasteland_state in
##      the loaded GridWorld is empty (sane default for v17 → v18).
##   8. End-to-end forward incompatibility — v19 save (synthetic) fails
##      with "Save is from a newer game" message.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_artifacts/test_save_migration.json"
const TEST_ARTIFACTS_DIR: String = "user://test_artifacts/"

static func test_name() -> String:
	return "save migration framework (registry + v17→v18 + no-path + end-to-end)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. Registry shape ----------
	# All keys must be ints; all values must be strings (method names);
	# at least the v17→v18 migration must exist for this session's ship.
	for key in SaveSystem.MIGRATIONS.keys():
		_check(failures, typeof(key) == TYPE_INT,
			"MIGRATIONS key %s should be int, got %d" % [str(key), typeof(key)])
		_check(failures, typeof(SaveSystem.MIGRATIONS[key]) == TYPE_STRING,
			"MIGRATIONS value for %s should be String (method name)" % str(key))
	_check(failures, SaveSystem.MIGRATIONS.has(17),
		"MIGRATIONS must include v17→v18 migration entry (session-save-migration)")

	# ---------- 2. _migrate_v17_to_v18 happy path ----------
	# Minimal v17 save dict: just version + a representative existing field.
	# Real v17 saves have many more fields — migration is purely additive,
	# so they pass through verbatim.
	var v17_in: Dictionary = {
		"version": 17,
		"world_seed": 12345,
		"player": [100.0, 200.0],
		"tile_soil_modifications": [[5, 5, 50]],
		"tile_fertilizer_state": [],
	}
	var v18_out: Dictionary = SaveSystem._migrate_v17_to_v18(v17_in)
	_check(failures, int(v18_out.get("version", -1)) == 18,
		"v17→v18 should bump version to 18, got %d" % int(v18_out.get("version", -1)))
	_check(failures, v18_out.has("tile_wasteland_state"),
		"v17→v18 must add tile_wasteland_state field")
	_check(failures, typeof(v18_out["tile_wasteland_state"]) == TYPE_ARRAY \
			and (v18_out["tile_wasteland_state"] as Array).is_empty(),
		"tile_wasteland_state default must be empty Array")
	# Pre-existing fields preserved verbatim.
	_check(failures, int(v18_out.get("world_seed", -1)) == 12345,
		"world_seed preserved through migration")
	_check(failures, (v18_out.get("tile_soil_modifications", []) as Array).size() == 1,
		"tile_soil_modifications preserved through migration")

	# ---------- 3. _try_migrate single-step ----------
	var single_step_in: Dictionary = {"version": 17, "marker": "v17"}
	var single_step_out: Variant = SaveSystem._try_migrate(single_step_in, 17, 18)
	_check(failures, single_step_out != null,
		"_try_migrate(17, 18) should succeed when MIGRATIONS[17] exists")
	if single_step_out is Dictionary:
		_check(failures, int(single_step_out.get("version", -1)) == 18,
			"chained result should be at v18")
		_check(failures, str(single_step_out.get("marker", "")) == "v17",
			"non-version fields preserved through chain")

	# ---------- 4. _try_migrate no-op (already current) ----------
	var noop_in: Dictionary = {"version": 18, "tile_wasteland_state": []}
	var noop_out: Variant = SaveSystem._try_migrate(noop_in, 18, 18)
	_check(failures, noop_out != null,
		"_try_migrate(18, 18) should be a no-op (return input dict, not null)")
	if noop_out is Dictionary:
		_check(failures, int(noop_out.get("version", -1)) == 18,
			"no-op leaves version at 18")

	# ---------- 5. _try_migrate no-path failure ----------
	# Hypothetical v14 save — no MIGRATIONS[14] registered. Chain bails.
	var no_path_in: Dictionary = {"version": 14, "ancient": true}
	var no_path_out: Variant = SaveSystem._try_migrate(no_path_in, 14, 18)
	_check(failures, no_path_out == null,
		"_try_migrate from v14 should fail (no MIGRATIONS[14] registered)")

	# ---------- 6. _dispatch_migration unknown name ----------
	# Direct call to dispatcher with a name that doesn't match any case.
	var bad_dispatch: Variant = SaveSystem._dispatch_migration("_migrate_nonexistent", {"version": 0})
	_check(failures, bad_dispatch == null,
		"_dispatch_migration with unknown name returns null")

	# ---------- 7. End-to-end via load_game ----------
	# Write a synthetic v17 save (realistic shape; missing tile_wasteland_state),
	# call load_game, assert success + GridWorld state matches expectations.
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	# Ensure the test artifacts subdirectory exists. Subdirectory is used so
	# the game's save scanner (which enumerates user_data top level) cannot
	# accidentally pick up this v19 fixture and show a "Save incompatible"
	# popup at game launch. See NOTES.md "Test fixture leakage into game saves."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ARTIFACTS_DIR))
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	# Build a v17 save dict using current world's serialization (which
	# produces v18 data), then mutate version → 17 and remove the v18-only
	# field. This matches the real-world "old save loads after upgrade"
	# scenario.
	var setup_world = GridWorldScript.new()
	parent.add_child(setup_world)
	# Add a soil modification + fertilizer entry so we can verify they
	# survive the migration end-to-end.
	setup_world.tile_soil_modifications[Vector2i(10, 20)] = 50
	setup_world.tile_fertilizer_state[Vector2i(10, 20)] = {
		"tier": Items.Type.COMPOST_LOW,
		"remaining": 25.0,
	}

	var setup_player := Node2D.new()
	parent.add_child(setup_player)
	setup_player.global_position = Vector2(64.0, 96.0)

	if not SaveSystem.save_game(setup_world, setup_player, Inventory.new(16), {}):
		_cleanup(setup_world, setup_player, null, null, orig_path)
		return { "ok": false, "message": "save_game returned false during v17 setup" }

	# Read back the just-written v18 save, mutate version → 17 + drop the
	# v18-only field, write back. This mimics a player upgrading their game.
	var f := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	if f == null:
		_cleanup(setup_world, setup_player, null, null, orig_path)
		return { "ok": false, "message": "could not re-read setup save for v17 mutation" }
	var saved: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	saved["version"] = 17
	saved.erase("tile_wasteland_state")
	var f2 := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f2.store_string(JSON.stringify(saved))
	f2.close()

	# Now load — should auto-migrate v17 → v18.
	var load_world = GridWorldScript.new()
	parent.add_child(load_world)
	var load_player := Node2D.new()
	parent.add_child(load_player)
	var load_inv := Inventory.new(16)
	var load_result: LoadResult = SaveSystem.load_game(load_world, load_player, load_inv)

	_check(failures, load_result.success,
		"v17 save load should succeed via migration, error: '%s'" % load_result.error_message)
	# tile_soil_modifications preserved.
	_check(failures, load_world.tile_soil_health(Vector2i(10, 20)) == 50,
		"soil tile preserved through v17→v18 migration: expected 50, got %d" % load_world.tile_soil_health(Vector2i(10, 20)))
	# tile_fertilizer_state preserved.
	_check(failures, load_world.tile_fertilizer_tier(Vector2i(10, 20)) == Items.Type.COMPOST_LOW,
		"fertilizer tier preserved through migration")
	# tile_wasteland_state default-empty after migration.
	_check(failures, load_world.tile_wasteland_state.size() == 0,
		"tile_wasteland_state empty after v17→v18 migration, got %d entries" % load_world.tile_wasteland_state.size())

	# ---------- 8. End-to-end forward-incompatibility ----------
	# Mutate the same save to version 19 (simulating "save from a newer
	# game"). load_game should hard-fail; result.success == false.
	saved["version"] = 19
	var f3 := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f3.store_string(JSON.stringify(saved))
	f3.close()
	var fwd_world = GridWorldScript.new()
	parent.add_child(fwd_world)
	var fwd_player := Node2D.new()
	parent.add_child(fwd_player)
	var fwd_result: LoadResult = SaveSystem.load_game(fwd_world, fwd_player, Inventory.new(16))
	_check(failures, not fwd_result.success,
		"v19 (newer-than-game) save should fail to load")
	_check(failures, fwd_result.error_message.find("newer game") >= 0,
		"forward-incompat error should mention 'newer game', got '%s'" % fwd_result.error_message)

	_cleanup(setup_world, setup_player, load_world, load_player, orig_path)
	if fwd_world != null:
		_disconnect(fwd_world)
		fwd_world.queue_free()
	if fwd_player != null:
		fwd_player.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all 8 sub-suites passed (registry + migration + chain + no-path + dispatcher + end-to-end + forward-incompat)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

static func _cleanup(setup_world, setup_player, load_world, load_player, orig_path: String) -> void:
	_disconnect(setup_world)
	if setup_world != null:
		setup_world.queue_free()
	if setup_player != null:
		setup_player.queue_free()
	_disconnect(load_world)
	if load_world != null:
		load_world.queue_free()
	if load_player != null:
		load_player.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
