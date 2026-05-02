extends RefCounted

## Mixer end-to-end test — sustained run + fluid-gating.
##
## Phase 1: pre-load 5 cycles' worth of inputs (10 flour, 5 yeast) into the
## mixer with a working pump+pipe network, tick 1500, assert ≥5 dough
## produced and inputs fully consumed. Catches "single cycle works, multi
## cycle hangs" regressions.
##
## Phase 2: remove the pump, reload inputs, tick — recipe must not start.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "mixer dough recipe (flour+yeast+water)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	var world = GridWorldScript.new()
	parent.add_child(world)

	# Layout: water at (0,0), pump at (1,0), pipe at (2,0), mixer at (3,0).
	world.tiles[Vector2i(0, 0)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	for x in range(1, 4):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)

	if not world.place_building(Buildings.Type.PUMP, Vector2i(1, 0)):
		return _fail(world, "pump placement failed")
	if not world.place_building(Buildings.Type.PIPE, Vector2i(2, 0)):
		return _fail(world, "pipe placement failed")
	if not world.place_building(Buildings.Type.MIXER, Vector2i(3, 0)):
		return _fail(world, "mixer placement failed")

	_check(failures, world.fluid_available_at(Vector2i(3, 0)), "mixer should see water available adjacent")

	# --- Phase 1: sustained 5-cycle run ---
	# Pre-load 5 cycles' worth: 10 flour + 5 yeast (recipe consumes 2 flour
	# and 1 yeast per cycle).
	var mixer: Building = world.building_at(Vector2i(3, 0))
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 10], [Items.Type.YEAST, 5]]
	mixer.state["out_buffer"] = []
	mixer.state["state"] = Processor.IDLE
	mixer.state["progress"] = 0

	# 5 cycles × 100 ticks/cycle = 500 ticks; 1500 gives generous margin.
	for _i in 1500:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var out_dough: int = _bag_count(mixer.state.get("out_buffer", []), Items.Type.DOUGH)
	_check(failures, out_dough >= 5, "expected ≥5 dough from sustained run, got %d. State: %s" % [out_dough, str(mixer.state)])

	var in_flour: int = _bag_count(mixer.state.get("in_buffer", []), Items.Type.FLOUR)
	var in_yeast: int = _bag_count(mixer.state.get("in_buffer", []), Items.Type.YEAST)
	_check(failures, in_flour == 0, "expected 0 flour after 5 cycles, got %d" % in_flour)
	_check(failures, in_yeast == 0, "expected 0 yeast after 5 cycles, got %d" % in_yeast)

	# --- Phase 2: fluid-gating (no pump → no cycles) ---
	world.remove_building_at(Vector2i(1, 0))
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 10], [Items.Type.YEAST, 5]]
	mixer.state["out_buffer"] = []
	mixer.state["state"] = Processor.IDLE
	mixer.state["progress"] = 0
	for _i in 500:
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
		return { "ok": true, "message": "mixer ran 5 sustained cycles with water; refused all cycles without" }
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
