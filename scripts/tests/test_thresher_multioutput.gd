extends RefCounted

## Multi-output recipe test — Thresher converts wheat into grain + straw.
##
## Verifies that:
##   - Single cycle: both outputs land in out_buffer; input consumed.
##   - Multi-cycle sustained: 5 cycles produce exactly 5 grain + 5 straw.
##   - BLOCKED_OUTPUT gate: recipe doesn't start when an output would
##     overflow capacity.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "thresher multi-output (wheat → grain + straw)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	var world = GridWorldScript.new()
	parent.add_child(world)

	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.THRESHER, Vector2i(0, 0)):
		return _fail(world, "thresher placement failed")

	var thresher: Building = world.building_at(Vector2i(0, 0))
	# Pre-load one wheat in the input buffer (skip belt feeding for clarity).
	thresher.state["in_buffer"] = [[Items.Type.WHEAT, 1]]

	# Recipe is 60 ticks; tick generously to ensure cycle completes.
	for _i in 120:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var grain_count: int = _bag_count(thresher.state.get("out_buffer", []), Items.Type.GRAIN)
	var straw_count: int = _bag_count(thresher.state.get("out_buffer", []), Items.Type.STRAW)
	_check(failures, grain_count == 1, "expected 1 grain, got %d" % grain_count)
	_check(failures, straw_count == 1, "expected 1 straw, got %d" % straw_count)

	# Verify wheat input was consumed.
	var wheat_left: int = _bag_count(thresher.state.get("in_buffer", []), Items.Type.WHEAT)
	_check(failures, wheat_left == 0, "expected 0 wheat after consume, got %d" % wheat_left)

	# --- Phase 2: 5 cycles sustained ---
	# Pre-load 5 wheat. Reset state. Tick enough for 5 full cycles.
	thresher.state["in_buffer"] = [[Items.Type.WHEAT, 5]]
	thresher.state["out_buffer"] = []
	thresher.state["state"] = Processor.IDLE
	thresher.state["progress"] = 0
	# 5 cycles × 60 ticks = 300 ticks. 600 gives margin.
	for _i in 600:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var grain_5: int = _bag_count(thresher.state.get("out_buffer", []), Items.Type.GRAIN)
	var straw_5: int = _bag_count(thresher.state.get("out_buffer", []), Items.Type.STRAW)
	_check(failures, grain_5 == 5, "expected exactly 5 grain after 5-cycle run, got %d" % grain_5)
	_check(failures, straw_5 == 5, "expected exactly 5 straw after 5-cycle run, got %d" % straw_5)
	var wheat_5: int = _bag_count(thresher.state.get("in_buffer", []), Items.Type.WHEAT)
	_check(failures, wheat_5 == 0, "expected 0 wheat after 5 cycles, got %d" % wheat_5)

	# Now overload the output buffer to test BLOCKED_OUTPUT gate.
	# Capacity is 8 per type. Fill grain to 8, load 1 wheat, run a cycle,
	# verify BLOCKED_OUTPUT (recipe didn't start because grain at cap).
	thresher.state["out_buffer"] = [[Items.Type.GRAIN, 8], [Items.Type.STRAW, 0]]
	thresher.state["in_buffer"] = [[Items.Type.WHEAT, 1]]
	thresher.state["state"] = Processor.IDLE
	thresher.state["progress"] = 0
	# Tick a few; recipe shouldn't start because grain is at capacity.
	for _i in 30:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var wheat_after_block: int = _bag_count(thresher.state.get("in_buffer", []), Items.Type.WHEAT)
	_check(failures, wheat_after_block == 1, "wheat should NOT have been consumed (output blocked); got %d" % wheat_after_block)
	# State should be IDLE (not RUNNING — recipe never started since outputs would overflow).
	_check(failures, int(thresher.state.get("state", -1)) == Processor.IDLE, "expected IDLE while output blocked, got %d" % int(thresher.state.get("state", -1)))

	# Cleanup.
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "multi-output cycle works; output backpressure gates recipe-start" }
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
