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
##   7. A malformed ROW inside a well-typed `player_inventory` (five shapes) →
##      that slot is dropped, every later slot still loads, and the drop is
##      counted. See the block below — this one is not #11.
##   8. `player_progression` is not a Dictionary → dropped and counted, not an
##      aborted load. Not an ARRAY_FIELDS shape; see the sub-case.
##   9. A `buildings` entry whose "s" state is not a Dictionary → that building
##      is dropped and counted; the load survives.
##  10. A `resource_state_modifications` row whose payload is unreadable → the
##      row is dropped and counted, rather than stored with an empty payload
##      that re-serialises on every later save.
##
## SUB-CASE 7 IS A DIFFERENT DEFECT FROM 1-6, AND A QUIETER ONE.
## #11's failure is loud: `load_game` aborts, the caller gets null, the boot
## bricks. `Inventory.load_array` fails the opposite way. A GDScript runtime
## error aborts only the INNERMOST function, so an unguarded `entry[1]` killed
## `load_array` and `load_game` carried straight on to `result.success = true`.
## Every slot from the bad row onward was never written, `skipped_entries`
## stayed 0, and the player was toasted a clean load. The next F5 then wrote the
## truncated inventory over the only save slot.
##
## The `"xy"` shape is the one that has to be in this list. A String is indexable
## and `int("x")` is 0, so it raises NO error at all: pre-fix it produced a slot
## with `item_type == 0` — a real item id — and a skip nobody counted. Nothing in
## the log, nothing in the toast. That is why sub-case 7 asserts on
## `item_type == -1` rather than on `is_empty()`, which a zero-count slot
## satisfies either way.
##
## Every assertion is on a LOADED FIELD VALUE (seed, player position, flour
## count, the surviving inventory stacks, the surviving tile / building / soil
## entries), never on "the call returned true" — a load that returns success
## having applied nothing would pass the latter.

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

# Sub-case 7's inventory geometry. The capacity matches what `_load_fixture`
# constructs, so `load_array` takes its NO-RESIZE path — the one where a skipped
# row would otherwise keep whatever the live inventory already held, which is
# what a mid-session F9 quick-load actually does (main.gd reuses the standing
# `player_inventory`).
const INV_CAPACITY: int = 16
# A second stack, placed AFTER the row each fixture corrupts. Reading it back is
# the whole point: pre-fix `load_array` died at BAD_SLOT and never wrote this
# one, so it returned 0 while `load_game` reported a clean load.
const MARKER_SLOT: int = 5
const MARKER_ITEM: int = Items.Type.WHEAT
const MARKER_COUNT: int = 17
const BAD_SLOT: int = 2

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
		return { "ok": true, "message": "10 sub-cases pass: a short player array, a non-Array player, a short tile_modifications entry, a non-Dictionary buildings entry and five shapes of malformed player_inventory row all load with the bad data skipped and counted; an unreadable progression dict, building state and resource-state payload are each dropped and counted; a mistyped collection fails with a named field; a clean save is unaffected" }
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

	# ===================================================================
	# (7) A malformed ROW inside a well-typed player_inventory. Five shapes,
	#     because they fail in three different ways and only one of them is
	#     noisy:
	#       7a [7]        — Array, one element. entry[1] is out of bounds.
	#       7b 7          — not indexable at all; entry[0] raises.
	#       7c "xy"       — indexable, and int("x") is 0. NO error is raised;
	#                       pre-fix this wrote item id 0 into the slot and
	#                       counted nothing. The silent one.
	#       7d {"a": 1}   — Dictionary; entry[0] is a missing KEY, not an index.
	#       7e []         — empty Array; entry[0] is out of bounds.
	#     A premise check first: the row being corrupted has to be one the
	#     reference actually stores between two live stacks, or the sub-case
	#     proves nothing about truncation.
	# ===================================================================
	var inv_rows = reference.get("player_inventory")
	_check(failures, inv_rows is Array and inv_rows.size() == INV_CAPACITY,
		"(7) PREMISE: the reference save's player_inventory is %s, expected an Array of %d rows" % [str(inv_rows), INV_CAPACITY])
	_check(failures, BAD_SLOT < MARKER_SLOT,
		"(7) PREMISE: the corrupted row (%d) must come BEFORE the marker stack (%d), or a truncating load would drop the marker for the wrong reason" % [BAD_SLOT, MARKER_SLOT])
	_expect_inventory_row_skipped(parent, failures, "(7a)", reference, [7])
	_expect_inventory_row_skipped(parent, failures, "(7b)", reference, 7)
	_expect_inventory_row_skipped(parent, failures, "(7c)", reference, "xy")
	_expect_inventory_row_skipped(parent, failures, "(7d)", reference, { "a": 1 })
	_expect_inventory_row_skipped(parent, failures, "(7e)", reference, [])

	# ===================================================================
	# (8) `player_progression` is not a Dictionary.
	#
	# NOT reachable through ARRAY_FIELDS — the field is supposed to BE a
	# Dictionary, so the array-field validator has nothing to say about it,
	# and `LoadResult.player_progression` is typed, so the assignment itself
	# raised. Measured before the guard: load_game aborted at the assignment
	# and returned null, having already applied every world mutation, which
	# is #11's bricked-boot shape reached through a door #11's fix left open.
	# ===================================================================
	var data_8: Dictionary = reference.duplicate(true)
	data_8["player_progression"] = "not a dictionary"
	var loaded_8 = _load_fixture(parent, failures, "(8)", data_8)
	if loaded_8 != null:
		_check(failures, loaded_8["result"].success,
			"(8) an unreadable progression dict must not fail the whole load — error_message=%s" % str(loaded_8["result"].error_message))
		_check(failures, loaded_8["result"].player_progression is Dictionary,
			"(8) player_progression must still be a Dictionary the caller can iterate")
		_check(failures, loaded_8["result"].skipped_entries == 1,
			"(8) skipped_entries is %d, expected 1 — losing bag-cap progression and the cursor stack is lost data like any other" % loaded_8["result"].skipped_entries)
		_check_reference_fields(failures, "(8)", loaded_8, POS_OK)
		_teardown_loaded(loaded_8)

	# ===================================================================
	# (9) A `buildings` entry that IS a Dictionary but whose "s" state is not.
	#
	# Passes the container check AND the per-entry `is Dictionary` check, then
	# hits `Building._init`'s typed `initial_state` param. Same bricked-boot
	# shape as (8): from_dict aborted, returned null, and `b.anchor` on null
	# aborted the load.
	# ===================================================================
	var data_9: Dictionary = reference.duplicate(true)
	var buildings_9: Array = data_9["buildings"]
	buildings_9.append({ "t": 1, "x": 40, "y": 41, "s": "not a dictionary" })
	data_9["buildings"] = buildings_9
	var loaded_9 = _load_fixture(parent, failures, "(9)", data_9)
	if loaded_9 != null:
		_check(failures, loaded_9["result"].success,
			"(9) one building with an unreadable state must not fail the whole load — error_message=%s" % str(loaded_9["result"].error_message))
		_check(failures, not loaded_9["world"].buildings.has(Vector2i(40, 41)),
			"(9) the unreadable building was placed anyway — its state dict is what every type reads its buffers from")
		_check(failures, loaded_9["result"].skipped_entries == 1,
			"(9) skipped_entries is %d, expected 1" % loaded_9["result"].skipped_entries)
		_check_reference_fields(failures, "(9)", loaded_9, POS_OK)
		_teardown_loaded(loaded_9)

	# ===================================================================
	# (10) A `resource_state_modifications` row whose payload is unreadable.
	#
	# Long enough for `_entry_ok(entry, 2, …)` — 2 is the highest UNCONDITIONAL
	# index plus one — so it reaches the payload read behind that guard.
	# Measured before the fix: success=true, skipped=0, and an empty dict
	# written back into resource_state_modifications, which `save_game` then
	# re-serialised on every subsequent F5. An uncounted drop that propagated.
	# ===================================================================
	var data_10: Dictionary = reference.duplicate(true)
	var rsm_10: Array = data_10.get("resource_state_modifications", [])
	rsm_10.append([70, 71, "not a dictionary"])
	data_10["resource_state_modifications"] = rsm_10
	var loaded_10 = _load_fixture(parent, failures, "(10)", data_10)
	if loaded_10 != null:
		_check(failures, loaded_10["result"].success,
			"(10) one unreadable resource-state payload must not fail the whole load — error_message=%s" % str(loaded_10["result"].error_message))
		_check(failures, not loaded_10["world"].resource_state_modifications.has(Vector2i(70, 71)),
			"(10) the row was stored with an empty payload — it carries nothing, and save_game re-serialises it on the next F5, so the junk row outlives the save that introduced it")
		_check(failures, loaded_10["result"].skipped_entries == 1,
			"(10) skipped_entries is %d, expected 1 — this was one of the two drop sites the count did not reach" % loaded_10["result"].skipped_entries)
		_check_reference_fields(failures, "(10)", loaded_10, POS_OK)
		_teardown_loaded(loaded_10)

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

## Sub-case 7: replace ONE row of a well-typed `player_inventory` with `bad_row`
## and require that only that row is lost.
##
## The load must still succeed — a single hand-corrupted slot is not a reason to
## throw away a world — but the slot must come back EMPTY, the slots on both
## sides of it must come back intact, and the drop must reach
## `LoadResult.skipped_entries`. The last two are the assertions that fail
## pre-fix, and they fail for different fixtures: 7a/7b/7d/7e truncated the
## inventory (so the marker was lost), 7c did not truncate but reported nothing.
static func _expect_inventory_row_skipped(parent: Node, failures: Array, label: String, reference: Dictionary, bad_row) -> void:
	var data: Dictionary = reference.duplicate(true)
	var rows: Array = data["player_inventory"]
	rows[BAD_SLOT] = bad_row
	data["player_inventory"] = rows
	var loaded = _load_fixture(parent, failures, label, data)
	if loaded == null:
		return
	var result = loaded["result"]
	var inv: Inventory = loaded["inv"]
	_check(failures, result.success,
		"%s one malformed inventory row must not fail the whole load — error_message=%s" % [label, str(result.error_message)])
	_check(failures, inv.capacity == INV_CAPACITY,
		"%s inventory capacity is %d, expected %d" % [label, inv.capacity, INV_CAPACITY])
	# The row itself: dropped, and dropped to EMPTY. `item_type == -1` rather
	# than `is_empty()` on purpose — a slot holding item id 0 with count 0 is
	# "empty" by that predicate, and id 0 with count 0 is exactly what the
	# unguarded `int("x")` path produced for 7c.
	if inv.slots.size() > BAD_SLOT:
		_check(failures, inv.slots[BAD_SLOT].item_type == -1 and inv.slots[BAD_SLOT].count == 0,
			"%s slot %d came back as item_type=%d count=%d, expected an empty slot (-1 / 0) — an unreadable row must be dropped, not half-parsed into a real item id" % [label, BAD_SLOT, inv.slots[BAD_SLOT].item_type, inv.slots[BAD_SLOT].count])
	# THE TRUNCATION ASSERTION. Pre-fix `load_array` aborted at BAD_SLOT and
	# every later slot stayed empty, while `load_game` reported success.
	_check(failures, inv.total_of(MARKER_ITEM) == MARKER_COUNT,
		"%s the stack stored at row %d came back as %d, expected %d — the rows AFTER the malformed one were never written, and the load reported success anyway" % [label, MARKER_SLOT, inv.total_of(MARKER_ITEM), MARKER_COUNT])
	# And the row before it, so "nothing loaded at all" cannot pass the above.
	_check(failures, inv.total_of(Items.Type.FLOUR) == FLOUR_OK,
		"%s the stack before the malformed row came back as %d flour, expected %d" % [label, inv.total_of(Items.Type.FLOUR), FLOUR_OK])
	_check(failures, result.skipped_entries >= 1,
		"%s skipped_entries is %d — a dropped inventory slot has to be counted, or the player is told 'World loaded from save' with no suffix and F5s the truncated inventory over the only save" % [label, result.skipped_entries])
	_check_reference_fields(failures, label, loaded, POS_OK)
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
	# The marker stack sub-case 7 reads back. Asserted for EVERY sub-case, not
	# just 7: it is the only thing in this suite that would notice a fix which
	# hardened `load_array` by dropping the tail of a perfectly good inventory.
	_check(failures, inv.total_of(MARKER_ITEM) == MARKER_COUNT,
		"%s the stack at inventory row %d loaded as %d, expected %d" % [label, MARKER_SLOT, inv.total_of(MARKER_ITEM), MARKER_COUNT])
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
	var inv := Inventory.new(INV_CAPACITY)
	inv.add(Items.Type.FLOUR, FLOUR_OK)
	# Placed by index rather than through `add`, which would fill the first free
	# slot (row 1) and leave nothing after sub-case 7's corrupted row.
	inv.slots[MARKER_SLOT].item_type = MARKER_ITEM
	inv.slots[MARKER_SLOT].count = MARKER_COUNT
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
