extends RefCounted

## Thresher rotation test — verifies Buildings.world_dir() correctly rotates
## recipe-declared prefer_dir ports through all four orientations.
##
## The thresher_wheat recipe declares grain → DIR_E and straw → DIR_W in
## CANONICAL orientation (state.dir = 0). For each of the 4 building
## orientations, a different pair of world directions should receive the
## outputs:
##
##   building.dir = 0 (E, canonical): grain E, straw W
##   building.dir = 1 (S, +90° CW):   grain S, straw N
##   building.dir = 2 (W, +180°):     grain W, straw E
##   building.dir = 3 (N, +270° CW):  grain N, straw S
##
## Y-down note: Godot's Belt.DIR_* enum is laid out so visual-clockwise
## rotation = +1 step (E=0 → S=1 → W=2 → N=3). The "visual CW = math CCW"
## footgun lives in screen-space rendering, not in our discrete dir math:
## adding building.dir to a recipe direction always advances visually CW
## as the player perceives it. The 90° and 270° cases below are the ones
## that catch CW-vs-CCW confusion.
##
## Layout per case: thresher at (0,0), chests at (±2,0) and (0,±2) with
## belts pointing OUTWARD from the thresher in between. Pre-load 10 wheat
## directly into the thresher's input buffer; tick 1500; assert that the
## chests in the EXPECTED rotated directions have ≥5 of their respective
## items, and the chests in OTHER directions are empty.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "thresher rotation (4 orientations)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# Each case: building.dir, expected world-dir for grain, expected world-dir for straw.
	var cases: Array = [
		{ "dir": Belt.DIR_E, "grain_dir": Belt.DIR_E, "straw_dir": Belt.DIR_W, "label": "dir=E (canonical)" },
		{ "dir": Belt.DIR_S, "grain_dir": Belt.DIR_S, "straw_dir": Belt.DIR_N, "label": "dir=S (+90° CW)" },
		{ "dir": Belt.DIR_W, "grain_dir": Belt.DIR_W, "straw_dir": Belt.DIR_E, "label": "dir=W (+180°)" },
		{ "dir": Belt.DIR_N, "grain_dir": Belt.DIR_N, "straw_dir": Belt.DIR_S, "label": "dir=N (+270° CW)" },
	]

	for case in cases:
		var case_failures: Array = []
		_run_case(parent, case, case_failures)
		for f in case_failures:
			failures.append("[%s] %s" % [case["label"], f])

	if failures.is_empty():
		return { "ok": true, "message": "all 4 rotations route grain and straw to expected world edges" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

# ---------- per-case ----------

static func _run_case(parent: Node, case: Dictionary, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)

	# 5×5 stone area centered on (0,0) so all chest/belt positions are paveable.
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)

	# Thresher at origin with the case's direction.
	if not world.place_building(Buildings.Type.THRESHER, Vector2i(0, 0), int(case["dir"])):
		failures.append("thresher placement failed")
		_cleanup(world)
		return

	# Belts and chests in all four cardinal directions. Each belt points
	# OUTWARD (away from the thresher) so items it receives travel away
	# from the thresher, ending in the chest one cell further.
	#
	# DIR_E (1, 0): belt at (1,0) → chest at (2,0)
	# DIR_S (0, 1): belt at (0,1) → chest at (0,2)
	# DIR_W (-1, 0): belt at (-1,0) → chest at (-2,0)
	# DIR_N (0, -1): belt at (0,-1) → chest at (0,-2)
	for dir in 4:
		var v: Vector2i = Belt.DIR_VECS[dir]
		var belt_pos: Vector2i = v
		var chest_pos: Vector2i = v * 2
		if not world.place_building(Buildings.Type.BELT, belt_pos, dir):
			failures.append("belt %s placement failed" % Belt.DIR_NAMES[dir])
			_cleanup(world)
			return
		if not world.place_building(Buildings.Type.CHEST, chest_pos):
			failures.append("chest %s placement failed" % Belt.DIR_NAMES[dir])
			_cleanup(world)
			return

	# Pre-load thresher input buffer.
	var thresher: Building = world.building_at(Vector2i(0, 0))
	thresher.state["in_buffer"] = [[Items.Type.WHEAT, 10]]
	thresher.state["out_buffer"] = []
	thresher.state["state"] = Processor.IDLE
	thresher.state["progress"] = 0

	# Run.
	for _i in 1500:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	# Assert: only the chest in the rotated grain direction has grain;
	# only the chest in the rotated straw direction has straw; the other
	# two chests are empty.
	var expected_grain_dir: int = int(case["grain_dir"])
	var expected_straw_dir: int = int(case["straw_dir"])

	# Threshold ≥9 of 10 produced: 10 wheat pre-loaded, single-belt transit
	# leaves at most 1 in flight at budget end. Diagnostic instrumentation
	# during the Session E threshold audit confirmed all four rotations
	# deliver an identical 10/10 — the rotation math is symmetric and the
	# belt geometry is the same in every direction. If a future change
	# breaks symmetry (e.g., direction-dependent push order), one rotation
	# will fail this test before others, naming the case.
	for dir in 4:
		var v: Vector2i = Belt.DIR_VECS[dir]
		var chest: Building = world.building_at(v * 2)
		var bag: Array = chest.state.get("bag", [])
		var grain_count: int = _bag_count(bag, Items.Type.GRAIN)
		var straw_count: int = _bag_count(bag, Items.Type.STRAW)

		if dir == expected_grain_dir:
			if grain_count < 9:
				failures.append("%s chest expected ≥9 grain of 10, got %d" % [Belt.DIR_NAMES[dir], grain_count])
			if straw_count != 0:
				failures.append("%s chest got unexpected straw ×%d (should be grain-only)" % [Belt.DIR_NAMES[dir], straw_count])
		elif dir == expected_straw_dir:
			if straw_count < 9:
				failures.append("%s chest expected ≥9 straw of 10, got %d" % [Belt.DIR_NAMES[dir], straw_count])
			if grain_count != 0:
				failures.append("%s chest got unexpected grain ×%d (should be straw-only)" % [Belt.DIR_NAMES[dir], grain_count])
		else:
			# Neutral edge: must be empty.
			if grain_count != 0 or straw_count != 0:
				failures.append("%s chest should be empty (rotation routed nothing here), got grain×%d straw×%d" % [Belt.DIR_NAMES[dir], grain_count, straw_count])

	_cleanup(world)

# ---------- helpers ----------

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
