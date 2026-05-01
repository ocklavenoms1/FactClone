extends RefCounted

## Mixer end-to-end test.
##
## Builds a Mixer with flour + yeast pre-loaded into its input buffer and
## a working pipe network feeding it water. Ticks for one process cycle
## (100 ticks) and asserts the mixer produced 1 dough.
##
## We pre-load the buffer manually instead of routing belts to keep the
## test focused on the fluid-input + recipe execution path.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "mixer dough recipe (flour+yeast+water)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	var world = GridWorldScript.new()
	parent.add_child(world)

	# Layout:
	#   (0,0) WATER
	#   (1,0) stone + Pump (adjacent to water)
	#   (2,0) stone + Pipe
	#   (3,0) stone + Mixer (adjacent to pipe)
	world.tiles[Vector2i(0, 0)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	for x in range(1, 4):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)

	if not world.place_building(Buildings.Type.PUMP, Vector2i(1, 0)):
		return _fail(world, "pump placement failed")
	if not world.place_building(Buildings.Type.PIPE, Vector2i(2, 0)):
		return _fail(world, "pipe placement failed")
	if not world.place_building(Buildings.Type.MIXER, Vector2i(3, 0)):
		return _fail(world, "mixer placement failed")

	# Sanity: water available at mixer position.
	_check(failures, world.fluid_available_at(Vector2i(3, 0)), "mixer should see water available adjacent")

	# Pre-load mixer input buffer with flour×2 and yeast×1 (one full recipe).
	var mixer: Building = world.building_at(Vector2i(3, 0))
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 2], [Items.Type.YEAST, 1]]

	# Tick for 200 ticks — recipe is 100, plus margin to ensure cycle completes
	# and inputs are consumed.
	for _i in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	# Assertions: dough produced, inputs consumed, mixer back to IDLE
	# (since output is in buffer; nothing to push to since no belt).
	var out_dough: int = _bag_count(mixer.state.get("out_buffer", []), Items.Type.DOUGH)
	_check(failures, out_dough >= 1, "expected ≥1 dough in mixer output, got %d. State: %s" % [out_dough, str(mixer.state)])

	var in_flour: int = _bag_count(mixer.state.get("in_buffer", []), Items.Type.FLOUR)
	var in_yeast: int = _bag_count(mixer.state.get("in_buffer", []), Items.Type.YEAST)
	_check(failures, in_flour == 0, "expected 0 flour after consume, got %d" % in_flour)
	_check(failures, in_yeast == 0, "expected 0 yeast after consume, got %d" % in_yeast)

	# Now verify the fluid-blocked path: remove the pump, reload mixer with
	# fresh inputs, tick — recipe should NOT start because no water.
	world.remove_building_at(Vector2i(1, 0))
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 2], [Items.Type.YEAST, 1]]
	mixer.state["out_buffer"] = []
	mixer.state["state"] = Processor.IDLE
	mixer.state["progress"] = 0
	for _i in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var out_dough_no_water: int = _bag_count(mixer.state.get("out_buffer", []), Items.Type.DOUGH)
	_check(failures, out_dough_no_water == 0, "expected 0 dough without pump, got %d (recipe ran without water!)" % out_dough_no_water)
	_check(failures, int(mixer.state.get("state", -1)) == Processor.IDLE, "mixer should stay IDLE without water, got state %d" % int(mixer.state.get("state", -1)))

	# Cleanup.
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "mixer produces dough with water, refuses without" }
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

static func _fail(world, msg: String) -> Dictionary:
	if world != null:
		if TickSystem.tick.is_connected(world._on_tick):
			TickSystem.tick.disconnect(world._on_tick)
		world.queue_free()
	return { "ok": false, "message": msg }
