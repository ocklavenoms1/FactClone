extends RefCounted

## MALFORMED SAVE SHAPES — load_game returns a LoadResult instead of crashing
## (audit finding #11, docs/audits/2026-07-19-flaw-review.md).
##
## THE DEFECT. `load_game` guarded only against JSON parse failure. Everything
## after that indexed player-authored data directly: `player_pos[0]`/`[1]` with
## no size check (and a typed `var player_pos: Array = ...` declaration that
## raises a runtime type error all by itself if the field is not an Array), and
## `entry[0]`..`entry[3]` for six collections plus `buildings`.
##
## WHY IT IS WORSE THAN "the load fails". A GDScript out-of-bounds index aborts
## `load_game` mid-function, so the caller receives **null**, not a LoadResult
## reporting failure. `main.gd:337-338` then dereferences `result.success` on
## null and the boot aborts there — which means the documented corrupt-save →
## fresh-world fallthrough (`main.gd:349-359`) never runs, and every subsequent
## boot repeats the same failure until the file is deleted by hand. A save the
## game could have walked away from instead bricks the game.
##
## FIXTURES ARE REAL SAVES, CORRUPTED. Every sub-case starts from a save written
## by the real `save_game`, reads it back as JSON, edits one field, and writes it
## back. That is what makes them genuinely malformed *v18* saves: `version`,
## `worldgen_version` and `world_seed` are whatever the shipping writer produces,
## so each fixture parses as valid JSON and passes every version check before it
## reaches the indexing this suite is about. A hand-authored dict could drift
## from the real format and start failing at a version check instead, which would
## pass this suite while testing nothing.
##
## SUB-CASES
##   1. `"player"` is a 1-element array  → loads, default spawn kept, counted.
##   2. `"player"` is a String, not an Array → same.
##   3. A 3-element `tile_modifications` entry beside valid ones → the valid
##      entries load, the malformed one is skipped and counted.
##   4. A whole collection field is a String / Dictionary instead of an Array →
##      `success == false` with an error_message naming the field, and a
##      non-null result so main.gd's fresh-world fallthrough fires.
##   5. A non-Dictionary `buildings` entry → skipped and counted, not crashed.
##   6. An untouched well-formed save still loads identically.
##
## Every assertion is on a LOADED FIELD VALUE (seed, player position, flour
## count, the surviving tile / building / soil entries), never on "the call
## returned true" — a load that returns success having applied nothing would
## pass the latter.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_load_malformed_save.json"

# The state every fixture is built from. Distinct, non-default values so no
# assertion can pass by reading a freshly generated world and matching a
# coincidence.
const SEED_OK: int = 50021
const POS_OK: Vector2 = Vector2(111.0, 222.0)
const FLOUR_OK: int = 23

# Where the player node sits BEFORE a load. Nothing in a fixture holds this
# value, so "position unchanged" and "position loaded" are distinguishable.
const SPAWN_SENTINEL: Vector2 = Vector2(-999.0, -999.0)

const TILE_POS := Vector2i(3, 4)
const BUILDING_POS := Vector2i(5, 6)
const SOIL_POS := Vector2i(7, 8)
const SOIL_VALUE: int = 42
const WASTE_POS := Vector2i(11, 12)

static func test_name() -> String:
	return "malformed save shapes return a LoadResult instead of crashing (audit #11)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	_scrub()

	_run_all(parent, failures)

	SaveSystem.save_path = orig_path
	_scrub()

	if failures.is_empty():
		return { "ok": true, "message": "6 sub-cases pass: a short player array, a non-Array player, a short tile_modifications entry and a non-Dictionary buildings entry all load with the bad data skipped and counted; a mistyped collection fails with a named field; a clean save is unaffected" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

static func _run_all(parent: Node, failures: Array) -> void:
	# One real save, written by the shipping writer. Every fixture below is this
	# file with one field edited.
	if not _write_reference_save(parent):
		failures.append("PREMISE: save_game returned false — no reference save to corrupt")
		return
	var reference = _read_json(TEST_SAVE_PATH)
	if reference == null:
		failures.append("PREMISE: the reference save did not parse back as a Dictionary")
		return
	# A surviving .bak would let load_game recover clean data behind the
	# corruption and pass every sub-case for the wrong reason.
	_check(failures, not FileAccess.file_exists(TEST_SAVE_PATH + SaveSystem.BAK_SUFFIX),
		"PREMISE: a .bak sidecar exists, so load_game could fall back to uncorrupted data and these sub-cases would prove nothing")

	# ===================================================================
	# (1) "player" is a 1-element array. player_pos[1] is the out-of-bounds
	#     read; pre-fix it aborts load_game and returns null.
	# ===================================================================
	var data_1: Dictionary = reference.duplicate(true)
	data_1["player"] = [12.0]
	_expect_loads_with_default_spawn(parent, failures, "(1)", data_1, 1)

	# ===================================================================
	# (2) "player" is a String. No index is even reached — pre-fix the typed
	#     `var player_pos: Array = ...` declaration raises on the assignment.
	# ===================================================================
	var data_2: Dictionary = reference.duplicate(true)
	data_2["player"] = "111,222"
	_expect_loads_with_default_spawn(parent, failures, "(2)", data_2, 1)

	# ===================================================================
	# (3) A 3-element tile_modifications entry among valid ones. The loop
	#     reads entry[0..3], so 3 elements is one short.
	# ===================================================================
	var data_3: Dictionary = reference.duplicate(true)
	var mods_3: Array = data_3["tile_modifications"]
	mods_3.append([90, 91, Terrain.Base.GRASS])
	data_3["tile_modifications"] = mods_3
	var loaded_3 = _load_fixture(parent, failures, "(3)", data_3)
	if loaded_3 != null:
		var world_3 = loaded_3["world"]
		_check(failures, loaded_3["result"].success,
			"(3) one short entry among valid ones must not fail the whole load — error_message=%s" % str(loaded_3["result"].error_message))
		_check(failures, world_3.tile_modifications.has(TILE_POS),
			"(3) the VALID tile modification at %s was dropped along with the malformed one — skipping is supposed to cost the player one row, not the collection" % str(TILE_POS))
		_check(failures, not world_3.tile_modifications.has(Vector2i(90, 91)),
			"(3) the 3-element entry at (90, 91) was applied anyway — it has no overlay field to apply")
		_check(failures, loaded_3["result"].skipped_entries == 1,
			"(3) skipped_entries is %d, expected 1 — the player has to be told a row was dropped, or buildings vanish with no indication" % loaded_3["result"].skipped_entries)
		_check_reference_fields(failures, "(3)", loaded_3, POS_OK)
		_teardown_loaded(loaded_3)

	# ===================================================================
	# (4) A whole collection is the wrong type. Nothing in it is salvageable,
	#     so this fails the load — with a non-null result, which is what lets
	#     main.gd's fresh-world fallthrough run.
	# ===================================================================
	var data_4a: Dictionary = reference.duplicate(true)
	data_4a["tile_soil_modifications"] = "not a list at all"
	_expect_mistyped_field(parent, failures, "(4a)", data_4a, "tile_soil_modifications")

	var data_4b: Dictionary = reference.duplicate(true)
	data_4b["buildings"] = { "chest": 1 }
	_expect_mistyped_field(parent, failures, "(4b)", data_4b, "buildings")

	# ===================================================================
	# (5) A non-Dictionary buildings entry. Building.from_dict takes a
	#     Dictionary; a String reaches it and aborts the load pre-fix.
	# ===================================================================
	var data_5: Dictionary = reference.duplicate(true)
	var buildings_5: Array = data_5["buildings"]
	buildings_5.append("this is not a building")
	data_5["buildings"] = buildings_5
	var loaded_5 = _load_fixture(parent, failures, "(5)", data_5)
	if loaded_5 != null:
		var world_5 = loaded_5["world"]
		_check(failures, loaded_5["result"].success,
			"(5) one junk building entry must not fail the whole load — error_message=%s" % str(loaded_5["result"].error_message))
		_check(failures, world_5.buildings.has(BUILDING_POS),
			"(5) the VALID building at %s was lost along with the junk entry" % str(BUILDING_POS))
		_check(failures, loaded_5["result"].skipped_entries == 1,
			"(5) skipped_entries is %d, expected 1 — a load that silently drops buildings is a worse failure than one that says so" % loaded_5["result"].skipped_entries)
		_check_reference_fields(failures, "(5)", loaded_5, POS_OK)
		_teardown_loaded(loaded_5)

	# ===================================================================
	# (6) The untouched reference save. Guards against a fix that hardened
	#     the load by quietly dropping data everybody's save contains.
	# ===================================================================
	var loaded_6 = _load_fixture(parent, failures, "(6)", reference)
	if loaded_6 != null:
		_check(failures, loaded_6["result"].success,
			"(6) a well-formed save must still load — error_message=%s" % str(loaded_6["result"].error_message))
		_check(failures, loaded_6["result"].skipped_entries == 0,
			"(6) skipped_entries is %d on a well-formed save; a non-zero count here means the guards reject valid rows" % loaded_6["result"].skipped_entries)
		_check_reference_fields(failures, "(6)", loaded_6, POS_OK)
		_teardown_loaded(loaded_6)

# ---------- sub-case shapes ----------

## Sub-cases 1 and 2: the load succeeds, everything except the player position
## survives, and the position is the pre-load sentinel rather than the saved one.
static func _expect_loads_with_default_spawn(parent: Node, failures: Array, label: String, data: Dictionary, want_skipped: int) -> void:
	var loaded = _load_fixture(parent, failures, label, data)
	if loaded == null:
		return
	_check(failures, loaded["result"].success,
		"%s an unreadable player position must not fail the whole load — error_message=%s" % [label, str(loaded["result"].error_message)])
	_check(failures, loaded["result"].skipped_entries == want_skipped,
		"%s skipped_entries is %d, expected %d" % [label, loaded["result"].skipped_entries, want_skipped])
	# The point of the sentinel: the position must be what it was BEFORE the
	# load, not the saved one and not a coincidental zero.
	_check_reference_fields(failures, label, loaded, SPAWN_SENTINEL)
	_teardown_loaded(loaded)

## Sub-case 4: a mistyped collection fails the load, names the field, and still
## hands back a LoadResult.
static func _expect_mistyped_field(parent: Node, failures: Array, label: String, data: Dictionary, field: String) -> void:
	var loaded = _load_fixture(parent, failures, label, data)
	if loaded == null:
		return
	var result = loaded["result"]
	_check(failures, not result.success,
		"%s '%s' is not a list, so there is nothing to load from it — success must be false" % [label, field])
	_check(failures, result.error_message != "",
		"%s error_message must be non-empty; the empty string is this API's 'no save file, start fresh' signal and would suppress the error main.gd surfaces" % label)
	_check(failures, result.error_message.find(field) >= 0,
		"%s error_message does not name the offending field '%s' — it reads '%s'" % [label, field, str(result.error_message)])
	_teardown_loaded(loaded)

## Every reference field the fixture did not corrupt. `want_pos` differs only
## for the sub-cases whose corruption IS the player position.
static func _check_reference_fields(failures: Array, label: String, loaded: Dictionary, want_pos: Vector2) -> void:
	var world = loaded["world"]
	var player: Node2D = loaded["player"]
	var inv: Inventory = loaded["inv"]
	if not loaded["result"].success:
		return
	_check(failures, world.world_seed == SEED_OK,
		"%s world_seed loaded as %d, expected %d" % [label, world.world_seed, SEED_OK])
	_check(failures, player.global_position == want_pos,
		"%s player position is %s, expected %s" % [label, str(player.global_position), str(want_pos)])
	_check(failures, inv.total_of(Items.Type.FLOUR) == FLOUR_OK,
		"%s flour count loaded as %d, expected %d" % [label, inv.total_of(Items.Type.FLOUR), FLOUR_OK])
	_check(failures, world.tile_modifications.has(TILE_POS) and world.tile_modifications[TILE_POS].overlay == Terrain.Overlay.SOIL_TILLED,
		"%s the tile modification at %s did not come back as a tilled tile" % [label, str(TILE_POS)])
	_check(failures, world.buildings.has(BUILDING_POS) and world.buildings[BUILDING_POS].type == Buildings.Type.CHEST,
		"%s the chest at %s did not come back" % [label, str(BUILDING_POS)])
	_check(failures, int(world.tile_soil_modifications.get(SOIL_POS, -1)) == SOIL_VALUE,
		"%s soil at %s loaded as %s, expected %d" % [label, str(SOIL_POS), str(world.tile_soil_modifications.get(SOIL_POS, -1)), SOIL_VALUE])
	_check(failures, world.tile_wasteland_state.has(WASTE_POS) and bool(world.tile_wasteland_state[WASTE_POS]["scarred"]),
		"%s the scarred wasteland tile at %s did not come back" % [label, str(WASTE_POS)])

# ---------- helpers ----------

## Save the reference state through the REAL save_game, so the fixture format is
## whatever the shipping writer produces rather than this file's idea of it.
static func _write_reference_save(parent: Node) -> bool:
	var world = _make_world(parent)
	world.world_seed = SEED_OK
	world.tile_modifications[TILE_POS] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.SOIL_TILLED)
	world.buildings[BUILDING_POS] = Building.new(Buildings.Type.CHEST, BUILDING_POS, {})
	world.tile_soil_modifications[SOIL_POS] = SOIL_VALUE
	world.tile_wasteland_state[WASTE_POS] = { "scarred": true, "decay_remaining": 0.0 }
	world.region_visibility[Vector2i(1, 1)] = 1
	var player := Node2D.new()
	parent.add_child(player)
	player.global_position = POS_OK
	var inv := Inventory.new(16)
	inv.add(Items.Type.FLOUR, FLOUR_OK)
	var ok: bool = SaveSystem.save_game(world, player, inv, {})
	player.queue_free()
	_teardown(world)
	return ok

## Write `data` to the fixture path and load it through the real load_game.
## Returns { world, player, inv, result } — or null, having recorded the
## failure, when load_game returned null instead of a LoadResult. That null
## check IS the finding: pre-fix, an out-of-bounds index aborts load_game
## mid-function and the caller gets nothing to branch on.
static func _load_fixture(parent: Node, failures: Array, label: String, data: Dictionary):
	if not _write_text(TEST_SAVE_PATH, JSON.stringify(data)):
		failures.append("%s PREMISE: could not write the fixture" % label)
		return null
	var world = _make_world(parent)
	var player := Node2D.new()
	parent.add_child(player)
	player.global_position = SPAWN_SENTINEL
	var inv := Inventory.new(16)
	var result = SaveSystem.load_game(world, player, inv)
	if result == null:
		failures.append("%s load_game returned NULL instead of a LoadResult — it aborted mid-function on a malformed entry, so main.gd's `result.success` dereferences null and the documented fresh-world fallthrough never runs (audit #11)" % label)
		player.queue_free()
		_teardown(world)
		return null
	return { "world": world, "player": player, "inv": inv, "result": result }

static func _teardown_loaded(loaded: Dictionary) -> void:
	loaded["player"].queue_free()
	_teardown(loaded["world"])

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed

static func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Remove the fixture and both sidecars. The runner scrubs sidecars after every
## test too; this keeps the suite correct on its own terms, since sub-case 4
## would read a stale .bak rather than the corrupted primary.
static func _scrub() -> void:
	for p in [TEST_SAVE_PATH, TEST_SAVE_PATH + SaveSystem.TMP_SUFFIX, TEST_SAVE_PATH + SaveSystem.BAK_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing. queue_free is deferred until after the runner's
## synchronous run() returns, so a torn-down world otherwise stays subscribed
## to TickSystem.tick for the rest of the suite.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
