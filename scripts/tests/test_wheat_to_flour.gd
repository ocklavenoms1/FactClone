extends RefCounted

## Smoke test — full wheat→flour automation chain.
##
## Layout (left to right):
##   (0,0) tilled soil + Planter
##   (1,0) stone     + Harvester  (scans planter at (0,0), pushes to belt east)
##   (2,0) stone     + Belt east  (carries wheat eastward)
##   (3,0) stone     + Mill       (pulls wheat from belt at (2,0), outputs flour east)
##   (4,0) stone     + Belt east  (carries flour eastward)
##   (5,0) stone     + Chest      (sinks flour)
##
## Asserts: after 1000 ticks (~50s simulated time), chest contains >=1 flour.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "wheat → flour smoke chain"

static func run(parent: Node) -> Dictionary:
	# Build a fresh world.
	var world = GridWorldScript.new()
	parent.add_child(world)  # triggers _ready, which connects to TickSystem.tick

	# Terrain (overlays on grass base).
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED)
	for x in range(1, 6):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)

	# Buildings.
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(0, 0)):
		return _fail(world, "could not place planter")
	if not world.place_building(Buildings.Type.HARVESTER, Vector2i(1, 0)):
		return _fail(world, "could not place harvester")
	if not world.place_building(Buildings.Type.BELT, Vector2i(2, 0), Belt.DIR_E):
		return _fail(world, "could not place belt #1")
	if not world.place_building(Buildings.Type.MILL, Vector2i(3, 0)):
		return _fail(world, "could not place mill")
	if not world.place_building(Buildings.Type.BELT, Vector2i(4, 0), Belt.DIR_E):
		return _fail(world, "could not place belt #2")
	if not world.place_building(Buildings.Type.CHEST, Vector2i(5, 0)):
		return _fail(world, "could not place chest")

	# Drive 1000 ticks manually.
	# Planter takes 600 ticks to ripen; transport + 1 mill cycle adds ~120.
	# 1000 ticks gives generous safety margin for any future timing changes.
	for _i in 1000:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	# Assert: chest has at least 1 flour.
	var chest: Building = world.building_at(Vector2i(5, 0))
	if chest == null:
		return _fail(world, "chest disappeared from world")
	var flour_in_chest: int = _bag_count(chest.state.get("bag", []), Items.Type.FLOUR)
	if flour_in_chest < 1:
		# Useful diagnostics for investigating a regression.
		var planter: Building = world.building_at(Vector2i(0, 0))
		var harvester: Building = world.building_at(Vector2i(1, 0))
		var mill: Building = world.building_at(Vector2i(3, 0))
		var diag: String = "tick=%d, planter.growth=%d, planter.output=%d, harvester.buffer=%s, mill.state=%d, mill.in=%s, mill.out=%s, chest.bag=%s" % [
			TickSystem.current_tick,
			int(planter.state.get("growth", 0)) if planter else -1,
			int(planter.state.get("output", 0)) if planter else -1,
			str(harvester.state.get("buffer", [])) if harvester else "?",
			int(mill.state.get("state", 0)) if mill else -1,
			str(mill.state.get("in_buffer", [])) if mill else "?",
			str(mill.state.get("out_buffer", [])) if mill else "?",
			str(chest.state.get("bag", [])),
		]
		_cleanup(world)
		return { "ok": false, "message": "expected >=1 flour in chest, got %d. Diagnostics: %s" % [flour_in_chest, diag] }

	_cleanup(world)
	return { "ok": true, "message": "chest has %d flour after 1000 ticks" % flour_in_chest }

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
