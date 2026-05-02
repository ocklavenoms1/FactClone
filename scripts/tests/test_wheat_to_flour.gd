extends RefCounted

## Wheat → Flour smoke chain (post-Session-C).
##
## Mill no longer accepts raw wheat — it needs grain. So the chain now
## includes a Thresher between the harvester and mill:
##
##   (0,0) tilled soil + Wheat Planter
##   (1,0) stone       + Harvester
##   (2,0) stone       + Belt-E   (wheat)
##   (3,0) stone       + Thresher (wheat → grain + straw)
##   (4,0) stone       + Belt-E   (grain)
##   (5,0) stone       + Mill     (grain → flour)
##   (6,0) stone       + Belt-E   (flour)
##   (7,0) stone       + Chest    (sinks flour)
##
## After ~1500 ticks, asserts the chest has at least 1 flour. Straw piles
## up in the thresher's out_buffer (no second consumer); after ~8 cycles
## the thresher BLOCKED_OUTPUTs and stops. By then enough grain has flowed
## through that flour reaches the chest.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "wheat → flour chain (with Thresher)"

static func run(parent: Node) -> Dictionary:
	var world = GridWorldScript.new()
	parent.add_child(world)

	# Terrain.
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED)
	for x in range(1, 8):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)

	# Buildings.
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(0, 0), 0, Items.Type.WHEAT):
		return _fail(world, "could not place wheat planter")
	if not world.place_building(Buildings.Type.HARVESTER, Vector2i(1, 0)):
		return _fail(world, "could not place harvester")
	if not world.place_building(Buildings.Type.BELT, Vector2i(2, 0), Belt.DIR_E):
		return _fail(world, "could not place belt #1")
	if not world.place_building(Buildings.Type.THRESHER, Vector2i(3, 0)):
		return _fail(world, "could not place thresher")
	if not world.place_building(Buildings.Type.BELT, Vector2i(4, 0), Belt.DIR_E):
		return _fail(world, "could not place belt #2")
	if not world.place_building(Buildings.Type.MILL, Vector2i(5, 0)):
		return _fail(world, "could not place mill")
	if not world.place_building(Buildings.Type.BELT, Vector2i(6, 0), Belt.DIR_E):
		return _fail(world, "could not place belt #3")
	if not world.place_building(Buildings.Type.CHEST, Vector2i(7, 0)):
		return _fail(world, "could not place chest")

	# Tick budget: planter cycle is the bottleneck at 600 ticks. 3000 ticks
	# = 5 planter cycles, so ~5 wheat → grain → flour pipeline. Threshold
	# is set to ≥3 so we catch the "deadlock after first cycle" regression
	# (where straw clogs the front of the belt and mill goes IDLE forever)
	# while staying tolerant of pipeline latency.
	for _i in 3000:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var chest: Building = world.building_at(Vector2i(7, 0))
	if chest == null:
		return _fail(world, "chest disappeared from world")
	var flour_in_chest: int = _bag_count(chest.state.get("bag", []), Items.Type.FLOUR)
	if flour_in_chest < 3:
		var planter: Building = world.building_at(Vector2i(0, 0))
		var thresher: Building = world.building_at(Vector2i(3, 0))
		var mill: Building = world.building_at(Vector2i(5, 0))
		var diag: String = "tick=%d, planter.growth=%d, thresher.in=%s, thresher.out=%s, mill.in=%s, mill.out=%s, chest.bag=%s" % [
			TickSystem.current_tick,
			int(planter.state.get("growth", 0)) if planter else -1,
			str(thresher.state.get("in_buffer", [])) if thresher else "?",
			str(thresher.state.get("out_buffer", [])) if thresher else "?",
			str(mill.state.get("in_buffer", [])) if mill else "?",
			str(mill.state.get("out_buffer", [])) if mill else "?",
			str(chest.state.get("bag", [])),
		]
		_cleanup(world)
		return { "ok": false, "message": "expected ≥3 flour in chest after 3000 ticks, got %d. Diagnostics: %s" % [flour_in_chest, diag] }

	_cleanup(world)
	return { "ok": true, "message": "chest has %d flour after 3000 ticks (chain incl. Thresher)" % flour_in_chest }

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
