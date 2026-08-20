extends RefCounted

## Inserter Arc Session 4 tests (session-inserter-electric).
##
## Locks in the ELECTRIC_INSERTER tier. This file GROWS across Tasks 4-8;
## each task appends its own `_case_*` function and wires it into `run()`,
## so the sub-case list below is the running index:
##
##   1. Registry + parametric tables (Task 4).
##   2. Existing-tier regression — adding rows disturbed nothing (Task 4).
##
## DELIBERATELY NO transport test yet: at Task 4 the electric tier still
## runs the Burner fuel check in Inserter.tick, and its DATA slot_layout
## has NO fuel slot, so a placed electric inserter parks in STATE_NO_FUEL
## immediately. Transport / power / brownout coverage belongs to Tasks 5-6.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "electric inserter (registry + parametric tables + existing-tier regression)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_registry_and_tables(parent, failures)
	_case_existing_tier_regression(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "2 sub-cases pass: registry/tables + existing-tier regression" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ===========================================================================
# (1) REGISTRY + PARAMETRIC TABLES.
# The electric tier must place like every other inserter (1x1, walkable)
# AND resolve its own row in each of the four `*_BY_TYPE` tables rather
# than falling through to the `*_DEFAULT` fallback.
#
# reach and arm_length are asserted even though their expected values
# coincide with REACH_DEFAULT / ARM_LENGTH_DEFAULT: the point is that the
# tier declares them explicitly, so a future change to either default
# cannot silently move the electric tier along with it.
# ===========================================================================
static func _case_registry_and_tables(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.ELECTRIC_INSERTER, Vector2i(10, 10), Belt.DIR_E):
		_check(failures, false, "(1) electric inserter placement failed")
		_disconnect(world); world.queue_free()
		return
	var b: Building = world.building_at(Vector2i(10, 10))
	_check(failures, b != null, "(1) no building at (10,10) after placing electric inserter")
	if b == null:
		_disconnect(world); world.queue_free()
		return
	_check(failures, b.type == Buildings.Type.ELECTRIC_INSERTER,
		"(1) placed building type should be ELECTRIC_INSERTER, got %d" % b.type)

	# --- registry (buildings.gd DATA) ---
	var fp: Vector2i = Buildings.footprint_of(Buildings.Type.ELECTRIC_INSERTER)
	_check(failures, fp == Vector2i(1, 1),
		"(1) footprint_of(ELECTRIC_INSERTER) should be (1,1), got %s" % str(fp))
	_check(failures, Buildings.is_walkable(Buildings.Type.ELECTRIC_INSERTER) == true,
		"(1) is_walkable(ELECTRIC_INSERTER) should be true")

	# --- parametric tables (inserter.gd) ---
	_check(failures, Inserter.cycle_ticks(b) == 5,
		"(1) cycle_ticks(electric) should be 5 (0.25s), got %d" % Inserter.cycle_ticks(b))
	_check(failures, Inserter.reach(b) == 1,
		"(1) reach(electric) should be 1, got %d" % Inserter.reach(b))
	var col: Color = Inserter.body_color(b)
	_check(failures, col == Color(0.25, 0.75, 0.80),
		"(1) body_color(electric) should be electric cyan (0.25,0.75,0.80), got %s" % str(col))
	_check(failures, is_equal_approx(Inserter.arm_length(b), 0.55),
		"(1) arm_length(electric) should be 0.55, got %f" % Inserter.arm_length(b))

	_disconnect(world); world.queue_free()

# ===========================================================================
# (2) EXISTING-TIER REGRESSION.
# Cheap insurance that adding the four ELECTRIC_INSERTER rows did not
# disturb the neighbouring rows in CYCLE_TICKS_BY_TYPE / REACH_BY_TYPE.
# ===========================================================================
static func _case_existing_tier_regression(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var placements: Array = [
		[Buildings.Type.INSERTER,            Vector2i(8, 9),  20, 1, "basic"],
		[Buildings.Type.FAST_INSERTER,       Vector2i(10, 9), 10, 1, "fast"],
		[Buildings.Type.LONG_REACH_INSERTER, Vector2i(12, 9), 30, 2, "long-reach"],
	]
	for p in placements:
		var t: int = int(p[0])
		var pos: Vector2i = p[1]
		var want_ticks: int = int(p[2])
		var want_reach: int = int(p[3])
		var label: String = String(p[4])
		if not world.place_building(t, pos, Belt.DIR_E):
			_check(failures, false, "(2) %s inserter placement failed at %s" % [label, str(pos)])
			continue
		var b: Building = world.building_at(pos)
		if b == null:
			_check(failures, false, "(2) no building at %s after placing %s inserter" % [str(pos), label])
			continue
		_check(failures, Inserter.cycle_ticks(b) == want_ticks,
			"(2) cycle_ticks(%s) should be %d, got %d" % [label, want_ticks, Inserter.cycle_ticks(b)])
		_check(failures, Inserter.reach(b) == want_reach,
			"(2) reach(%s) should be %d, got %d" % [label, want_reach, Inserter.reach(b)])
	_disconnect(world); world.queue_free()

# ---------- helpers (house style, copied from test_inserter.gd) ----------

static func _make_world(parent: Node) -> Node2D:
	var w = GridWorldScript.new()
	parent.add_child(w)
	# Stone overlay across the test area — one overlay choice keeps
	# placement uniform for every building type used here.
	for x in range(7, 14):
		for y in range(8, 13):
			w.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	return w

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
