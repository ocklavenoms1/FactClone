extends RefCounted

## Save/load round-trip test — locks the v7 schema.
##
## Builds a world with diverse content (water, every overlay type, every
## building type, items in inventory, mid-tick mill state), saves to a
## scratch path, loads into a blank world, and asserts every observable
## piece of state matches.
##
## Catches: tile shape regressions (base/overlay schema), building state
## losses, inventory shape drifts, footprint occupancy desyncs.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_roundtrip.json"

static func test_name() -> String:
	return "save/load round-trip (v7)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# Override save path so we don't clobber the user's save.
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH

	# Clean up any leftover from a prior failed run.
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	# --- Build world A with diverse content ---
	var world_a = GridWorldScript.new()
	parent.add_child(world_a)

	# Water tile (simulating world-gen).
	world_a.tiles[Vector2i(5, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	# One of each overlay.
	world_a.set_overlay(Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED)
	world_a.set_overlay(Vector2i(1, 0), Terrain.Overlay.PATH)
	world_a.set_overlay(Vector2i(2, 0), Terrain.Overlay.STONE)
	world_a.set_overlay(Vector2i(3, 0), Terrain.Overlay.STONE)
	world_a.set_overlay(Vector2i(4, 0), Terrain.Overlay.STONE)

	# One of each building type.
	if not world_a.place_building(Buildings.Type.PLANTER, Vector2i(0, 0)):
		return _fail(world_a, orig_path, "could not place planter")
	if not world_a.place_building(Buildings.Type.HARVESTER, Vector2i(2, 0)):
		return _fail(world_a, orig_path, "could not place harvester")
	if not world_a.place_building(Buildings.Type.BELT, Vector2i(3, 0), Belt.DIR_E):
		return _fail(world_a, orig_path, "could not place belt")
	if not world_a.place_building(Buildings.Type.MILL, Vector2i(4, 0)):
		return _fail(world_a, orig_path, "could not place mill")
	# Chest needs an overlay too.
	world_a.set_overlay(Vector2i(0, 1), Terrain.Overlay.STONE)
	if not world_a.place_building(Buildings.Type.CHEST, Vector2i(0, 1)):
		return _fail(world_a, orig_path, "could not place chest")

	# Mutate building state so we have non-default values to round-trip:
	#   - planter mid-growth
	#   - harvester with one wheat in buffer
	#   - belt with an item in slot 1
	#   - mill mid-running
	#   - chest with mixed contents
	var planter_a: Building = world_a.building_at(Vector2i(0, 0))
	planter_a.state["growth"] = 137

	var harvester_a: Building = world_a.building_at(Vector2i(2, 0))
	harvester_a.state["buffer"] = [[Items.Type.WHEAT, 3]]
	harvester_a.state["next_scan_tick"] = 50

	var belt_a: Building = world_a.building_at(Vector2i(3, 0))
	belt_a.state["slots"] = [Items.Type.WHEAT, -1, -1, -1]

	var mill_a: Building = world_a.building_at(Vector2i(4, 0))
	mill_a.state["state"] = Processor.RUNNING
	mill_a.state["progress"] = 42
	mill_a.state["in_buffer"] = [[Items.Type.WHEAT, 2]]
	mill_a.state["out_buffer"] = [[Items.Type.FLOUR, 1]]

	var chest_a: Building = world_a.building_at(Vector2i(0, 1))
	chest_a.state["bag"] = [[Items.Type.WHEAT, 50], [Items.Type.FLOUR, 25]]

	# Player + inventory state.
	var player_a := Node2D.new()
	parent.add_child(player_a)
	player_a.global_position = Vector2(123.45, -67.89)

	var inv_a: Inventory = Inventory.new(16)
	inv_a.add(Items.Type.FLOUR, 17)
	inv_a.add(Items.Type.WHEAT, 5)

	# Tick counter.
	TickSystem.current_tick = 4242

	# --- Save ---
	if not SaveSystem.save_game(world_a, player_a, inv_a):
		return _fail(world_a, orig_path, "save_game returned false")
	if not FileAccess.file_exists(TEST_SAVE_PATH):
		return _fail(world_a, orig_path, "save file does not exist after save_game")

	# --- Build blank world B and load into it ---
	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b: Inventory = Inventory.new(16)

	if not SaveSystem.load_game(world_b, player_b, inv_b):
		return _fail(world_a, orig_path, "load_game returned false: %s" % SaveSystem.last_load_error)

	# --- Assertions ---
	# Tick counter restored.
	_check(failures, TickSystem.current_tick == 4242, "tick counter should be 4242, got %d" % TickSystem.current_tick)

	# Player position restored (tolerate float precision).
	_check(failures, abs(player_b.global_position.x - 123.45) < 0.01, "player x mismatch: %f vs 123.45" % player_b.global_position.x)
	_check(failures, abs(player_b.global_position.y - (-67.89)) < 0.01, "player y mismatch: %f vs -67.89" % player_b.global_position.y)

	# Tile counts match.
	_check(failures, world_a.tiles.size() == world_b.tiles.size(), "tile count mismatch: %d vs %d" % [world_a.tiles.size(), world_b.tiles.size()])

	# Per-tile base+overlay match.
	for pos in world_a.tiles:
		var ta: Tile = world_a.tiles[pos]
		if not world_b.tiles.has(pos):
			failures.append("missing tile at %s in world_b" % str(pos))
			continue
		var tb: Tile = world_b.tiles[pos]
		_check(failures, ta.base == tb.base, "base mismatch at %s: %d vs %d" % [str(pos), ta.base, tb.base])
		_check(failures, ta.overlay == tb.overlay, "overlay mismatch at %s: %d vs %d" % [str(pos), ta.overlay, tb.overlay])

	# Building counts match.
	_check(failures, world_a.buildings.size() == world_b.buildings.size(), "building count mismatch: %d vs %d" % [world_a.buildings.size(), world_b.buildings.size()])

	# Per-building type + state match.
	for anchor in world_a.buildings:
		var ba: Building = world_a.buildings[anchor]
		if not world_b.buildings.has(anchor):
			failures.append("missing building at %s in world_b" % str(anchor))
			continue
		var bb: Building = world_b.buildings[anchor]
		_check(failures, ba.type == bb.type, "building type mismatch at %s: %d vs %d" % [str(anchor), ba.type, bb.type])
		_check(failures, ba.anchor == bb.anchor, "building anchor mismatch")
		# Use semantic comparison: JSON round-trip turns all ints into floats,
		# but runtime code int()-coerces on read so this is harmless.
		_check(failures, _values_equal(ba.state, bb.state), "building state mismatch at %s:\n  A=%s\n  B=%s" % [str(anchor), str(ba.state), str(bb.state)])

	# Footprint occupancy rebuilt (test the multi-tile mapping doesn't desync).
	_check(failures, world_a.occupied.size() == world_b.occupied.size(), "occupied size mismatch: %d vs %d" % [world_a.occupied.size(), world_b.occupied.size()])
	for pos in world_a.occupied:
		_check(failures, world_b.occupied.get(pos, Vector2i(-9999, -9999)) == world_a.occupied[pos], "occupied entry mismatch at %s" % str(pos))

	# Player inventory contents match.
	_check(failures, inv_b.total_of(Items.Type.FLOUR) == 17, "inventory flour count: expected 17, got %d" % inv_b.total_of(Items.Type.FLOUR))
	_check(failures, inv_b.total_of(Items.Type.WHEAT) == 5, "inventory wheat count: expected 5, got %d" % inv_b.total_of(Items.Type.WHEAT))

	# --- Cleanup ---
	for w in [world_a, world_b]:
		if TickSystem.tick.is_connected(w._on_tick):
			TickSystem.tick.disconnect(w._on_tick)
		w.queue_free()
	player_a.queue_free()
	player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path

	if failures.is_empty():
		return { "ok": true, "message": "v7 round-trip preserves tiles, buildings, state, inventory, tick" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Deep-equals with numeric type coercion. JSON has only one number type, so
## ints become floats on round-trip; this helper treats 0 and 0.0 as equal.
## Recurses into Dictionary and Array.
static func _values_equal(a, b) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return float(a) == float(b)
	if ta == TYPE_DICTIONARY and tb == TYPE_DICTIONARY:
		if a.keys().size() != b.keys().size():
			return false
		for k in a.keys():
			if not b.has(k):
				return false
			if not _values_equal(a[k], b[k]):
				return false
		return true
	if ta == TYPE_ARRAY and tb == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _values_equal(a[i], b[i]):
				return false
		return true
	return a == b

static func _fail(world_a, orig_path: String, msg: String) -> Dictionary:
	if world_a != null and TickSystem.tick.is_connected(world_a._on_tick):
		TickSystem.tick.disconnect(world_a._on_tick)
	if world_a != null:
		world_a.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
	return { "ok": false, "message": msg }
