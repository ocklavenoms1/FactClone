extends RefCounted

## Thresher prefer_dir routing test (Session C semantic lock-in).
##
## Verifies that grain goes ONLY to the east belt and straw goes ONLY to
## the west belt — neither output ever appears on the wrong side. Catches
## any regression in the strict prefer_dir push behavior.
##
## Layout:
##                    Thresher (0, 0)
##   west belt (-1,0) ←  ← east belt (1, 0) →
##   straw chest (-2,0)         flour-mill-or-chest at (2, 0)
##
## We use plain chests at the ends of both belts so items collect for
## inspection. Pre-load 10 wheat directly into thresher's input buffer
## (skip the planter+harvester upstream — focus on routing).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "thresher prefer_dir routing (grain east, straw west)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	var world = GridWorldScript.new()
	parent.add_child(world)

	# Terrain.
	for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(-2, 0)]:
		world.set_overlay(offset, Terrain.Overlay.STONE)

	# Buildings.
	if not world.place_building(Buildings.Type.THRESHER, Vector2i(0, 0)):
		return _fail(world, "thresher placement failed")
	if not world.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_E):
		return _fail(world, "east belt placement failed")
	if not world.place_building(Buildings.Type.CHEST, Vector2i(2, 0)):
		return _fail(world, "east chest placement failed")
	if not world.place_building(Buildings.Type.BELT, Vector2i(-1, 0), Belt.DIR_W):
		return _fail(world, "west belt placement failed")
	if not world.place_building(Buildings.Type.CHEST, Vector2i(-2, 0)):
		return _fail(world, "west chest placement failed")

	# Pre-load thresher with 10 wheat for ~10 cycles of output.
	var thresher: Building = world.building_at(Vector2i(0, 0))
	thresher.state["in_buffer"] = [[Items.Type.WHEAT, 10]]
	thresher.state["out_buffer"] = []
	thresher.state["state"] = Processor.IDLE
	thresher.state["progress"] = 0

	# 10 cycles × 60 ticks = 600 ticks of generation, plus belt transit.
	# 1500 leaves ample margin for items to reach the chests.
	for _i in 1500:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var east_chest: Building = world.building_at(Vector2i(2, 0))
	var west_chest: Building = world.building_at(Vector2i(-2, 0))
	var east_belt: Building = world.building_at(Vector2i(1, 0))
	var west_belt: Building = world.building_at(Vector2i(-1, 0))

	# East side should have ONLY grain, west side should have ONLY straw.
	# Check chests and belts for contamination.
	_assert_only_contains(failures, east_chest.state.get("bag", []), Items.Type.GRAIN, "east chest")
	_assert_only_contains(failures, west_chest.state.get("bag", []), Items.Type.STRAW, "west chest")
	_assert_belt_only(failures, east_belt.state.get("slots", []), Items.Type.GRAIN, "east belt")
	_assert_belt_only(failures, west_belt.state.get("slots", []), Items.Type.STRAW, "west belt")

	# Sustained-throughput check: each chest should have non-trivial counts
	# (the belts can hold up to 4 each, chests collect the rest).
	var grain_total: int = _bag_count(east_chest.state.get("bag", []), Items.Type.GRAIN)
	var straw_total: int = _bag_count(west_chest.state.get("bag", []), Items.Type.STRAW)
	_check(failures, grain_total >= 5, "east chest should have ≥5 grain (sustained run), got %d" % grain_total)
	_check(failures, straw_total >= 5, "west chest should have ≥5 straw (sustained run), got %d" % straw_total)

	# Cleanup.
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "grain → east only, straw → west only; %d grain + %d straw collected" % [grain_total, straw_total] }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

## Assert a chest's bag contains only the expected item type (no other types).
static func _assert_only_contains(failures: Array, bag: Array, expected_type: int, label: String) -> void:
	for entry in bag:
		var t: int = int(entry[0])
		if t != expected_type:
			failures.append("%s contains unexpected item type %s (expected only %s)" % [label, Items.name_of(t), Items.name_of(expected_type)])

## Assert a belt's slots are either empty or hold only the expected item type.
static func _assert_belt_only(failures: Array, slots: Array, expected_type: int, label: String) -> void:
	for slot_item in slots:
		var t: int = int(slot_item)
		if t < 0:
			continue  # empty slot ok
		if t != expected_type:
			failures.append("%s has %s in a slot (expected only %s)" % [label, Items.name_of(t), Items.name_of(expected_type)])

static func _fail(world, msg: String) -> Dictionary:
	if world != null:
		if TickSystem.tick.is_connected(world._on_tick):
			TickSystem.tick.disconnect(world._on_tick)
		world.queue_free()
	return { "ok": false, "message": msg }
