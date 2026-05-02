extends RefCounted

## Wheat → Flour smoke chain (prefer_dir routing).
##
## Thresher emits grain → east port and straw → west port. The two outputs
## go to dedicated branches:
##
##                  Wheat Planter
##                       ↓
##                   Harvester
##                       ↓
##                  belt south (wheat)
##                       ↓
##   Straw Chest ← belt west ← Thresher → belt east → Mill → Flour Chest
##                          (-1,3)  (-2,3)            (1,3)        (2,3)        (3,3)
##
## After 5000 ticks (~4 minutes simulated) the chain should be in steady
## state: flour chest accumulating, straw chest accumulating, both
## thresher and mill alternating between Idle and Running, neither stuck.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "wheat → flour chain (prefer_dir routing)"

static func run(parent: Node) -> Dictionary:
	var world = GridWorldScript.new()
	parent.add_child(world)

	# Terrain.
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED)
	for offset in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3),
				   Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
				   Vector2i(-1, 3), Vector2i(-2, 3)]:
		world.set_overlay(offset, Terrain.Overlay.STONE)

	# Buildings.
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(0, 0), 0, Items.Type.WHEAT):
		return _fail(world, "wheat planter placement failed")
	if not world.place_building(Buildings.Type.HARVESTER, Vector2i(0, 1)):
		return _fail(world, "harvester placement failed")
	if not world.place_building(Buildings.Type.BELT, Vector2i(0, 2), Belt.DIR_S):
		return _fail(world, "wheat belt placement failed")
	if not world.place_building(Buildings.Type.THRESHER, Vector2i(0, 3)):
		return _fail(world, "thresher placement failed")
	# East branch (grain → mill → flour chest).
	if not world.place_building(Buildings.Type.BELT, Vector2i(1, 3), Belt.DIR_E):
		return _fail(world, "grain belt placement failed")
	if not world.place_building(Buildings.Type.MILL, Vector2i(2, 3)):
		return _fail(world, "mill placement failed")
	if not world.place_building(Buildings.Type.CHEST, Vector2i(3, 3)):
		return _fail(world, "flour chest placement failed")
	# West branch (straw → straw chest).
	if not world.place_building(Buildings.Type.BELT, Vector2i(-1, 3), Belt.DIR_W):
		return _fail(world, "straw belt placement failed")
	if not world.place_building(Buildings.Type.CHEST, Vector2i(-2, 3)):
		return _fail(world, "straw chest placement failed")

	# Tick budget: 5000 ticks ≈ 4 minutes simulated. With wheat planter
	# 600 ticks/wheat and a self-sustaining loop, we should see ~7-8 flour
	# and ~7-8 straw by then. Threshold ≥5 of each leaves comfortable
	# margin while still proving sustained operation.
	for _i in 5000:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var flour_chest: Building = world.building_at(Vector2i(3, 3))
	var straw_chest: Building = world.building_at(Vector2i(-2, 3))
	if flour_chest == null or straw_chest == null:
		return _fail(world, "chests vanished mid-test")

	var flour: int = _bag_count(flour_chest.state.get("bag", []), Items.Type.FLOUR)
	var straw: int = _bag_count(straw_chest.state.get("bag", []), Items.Type.STRAW)

	var failures: Array = []
	if flour < 5:
		failures.append("expected ≥5 flour in chest, got %d" % flour)
	if straw < 5:
		failures.append("expected ≥5 straw in chest, got %d" % straw)

	if not failures.is_empty():
		# Diagnostic dump.
		var thresher: Building = world.building_at(Vector2i(0, 3))
		var mill: Building = world.building_at(Vector2i(2, 3))
		var diag: String = ("tick=%d, thresher.state=%d, thresher.in=%s, thresher.out=%s, " +
				"mill.state=%d, mill.in=%s, mill.out=%s") % [
			TickSystem.current_tick,
			int(thresher.state.get("state", -1)) if thresher else -1,
			str(thresher.state.get("in_buffer", [])) if thresher else "?",
			str(thresher.state.get("out_buffer", [])) if thresher else "?",
			int(mill.state.get("state", -1)) if mill else -1,
			str(mill.state.get("in_buffer", [])) if mill else "?",
			str(mill.state.get("out_buffer", [])) if mill else "?",
		]
		_cleanup(world)
		return { "ok": false, "message": "%s. Diagnostics: %s" % ["; ".join(failures), diag] }

	_cleanup(world)
	return { "ok": true, "message": "chain ran continuously: flour=%d, straw=%d after 5000 ticks" % [flour, straw] }

# ---------- helpers ----------

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _fail(world, msg: String) -> Dictionary:
	_cleanup(world)
	return { "ok": false, "message": msg }

static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
