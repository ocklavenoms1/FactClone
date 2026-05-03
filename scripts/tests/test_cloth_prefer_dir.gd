extends RefCounted

## Cloth chain prefer_dir test — verifies that retter_fiber declares its
## fiber output with prefer_dir = DIR_E (canonical) and that
## supports_direction is true on RETTER, so the F11 cloth chain layout
## (which runs N→S) requires the building's state.dir = DIR_S.
##
## Two cases:
##
##   Case A (dir=0, east canonical): fiber output port is world E. Belts are
##   placed at N and S only (NO belt at E). Push must NOT happen, so the
##   Retter's out_buffer retains its pre-loaded fiber and BOTH N/S chests
##   stay empty. Locks in "prefer_dir is strict, not a fallback."
##
##   Case B (dir=S): canonical E rotates to world S. Belt+chest at S
##   receives fiber. North chest stays empty (canonical W rotates to world
##   N, but Retter has NO output declared on canonical W — only the input).
##   Locks in "rotation actually rotates the output port to the right edge."
##
## Why this test exists: the cloth chain shipped in Session E with NO
## prefer_dir, so any adjacent neighbor could grab fiber. A chest dropped
## next to a Retter would steal the south belt's fiber, breaking the chain.
## This test catches that regression — if someone removes prefer_dir from
## retter_fiber, Case A fails (fiber would push to N or S because no edge
## is preferred).
##
## We pre-load out_buffer directly to skip the water+flax+recipe-cycle
## setup. The PUSH path is what we're testing; pull and recipe correctness
## are covered by other tests (mixer_dough, thresher_*).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "cloth chain prefer_dir (retter rotation)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_run_case_a_dir_0(parent, failures)
	_run_case_b_dir_s(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "retter prefer_dir strict at dir=0; rotates correctly at dir=S" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

# ---------- Case A: dir=0, fiber should NOT flow N or S ----------

static func _run_case_a_dir_0(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)

	# 3×5 stone area centered on origin.
	for dx in range(-1, 2):
		for dy in range(-2, 3):
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)

	# Retter at origin, dir=0 (east-canonical).
	if not world.place_building(Buildings.Type.RETTER, Vector2i(0, 0), Belt.DIR_E):
		failures.append("[A] retter placement failed")
		_cleanup(world)
		return

	# Belt+chest at N (going N) and S (going S). NO belt at E or W.
	if not world.place_building(Buildings.Type.BELT, Vector2i(0, -1), Belt.DIR_N):
		failures.append("[A] N belt placement failed")
		_cleanup(world)
		return
	if not world.place_building(Buildings.Type.CHEST, Vector2i(0, -2)):
		failures.append("[A] N chest placement failed")
		_cleanup(world)
		return
	if not world.place_building(Buildings.Type.BELT, Vector2i(0, 1), Belt.DIR_S):
		failures.append("[A] S belt placement failed")
		_cleanup(world)
		return
	if not world.place_building(Buildings.Type.CHEST, Vector2i(0, 2)):
		failures.append("[A] S chest placement failed")
		_cleanup(world)
		return

	# Pre-load fiber directly into out_buffer; skip recipe cycle entirely.
	# Empty in_buffer so the IDLE→RUNNING transition doesn't fire.
	var retter: Building = world.building_at(Vector2i(0, 0))
	retter.state["out_buffer"] = [[Items.Type.FIBER, 10]]
	retter.state["in_buffer"] = []
	retter.state["state"] = Processor.IDLE
	retter.state["progress"] = 0

	# Run.
	for _i in 1500:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	# Assert: both chests empty (no E belt → push has nowhere strict-correct
	# to go; fiber stays in out_buffer or the recipe's port is honored as
	# strict).
	var n_chest: Building = world.building_at(Vector2i(0, -2))
	var s_chest: Building = world.building_at(Vector2i(0, 2))
	var n_count: int = _bag_count(n_chest.state.get("bag", []), Items.Type.FIBER)
	var s_count: int = _bag_count(s_chest.state.get("bag", []), Items.Type.FIBER)

	if n_count != 0:
		failures.append("[A dir=0] N chest received fiber ×%d (prefer_dir=E should block N push)" % n_count)
	if s_count != 0:
		failures.append("[A dir=0] S chest received fiber ×%d (prefer_dir=E should block S push)" % s_count)

	# Sanity check: fiber should still be in the Retter's out_buffer.
	var out_buf: Array = retter.state.get("out_buffer", [])
	var retained: int = _bag_count(out_buf, Items.Type.FIBER)
	if retained < 10:
		failures.append("[A dir=0] retter out_buffer leaked fiber (started 10, now %d)" % retained)

	_cleanup(world)

# ---------- Case B: dir=S, fiber should flow south ----------

static func _run_case_b_dir_s(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)

	# 3×5 stone area centered on origin.
	for dx in range(-1, 2):
		for dy in range(-2, 3):
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)

	# Retter at origin, dir=S.
	if not world.place_building(Buildings.Type.RETTER, Vector2i(0, 0), Belt.DIR_S):
		failures.append("[B] retter placement failed (does RETTER.supports_direction = true?)")
		_cleanup(world)
		return

	# Belt+chest at N (going N) and S (going S).
	if not world.place_building(Buildings.Type.BELT, Vector2i(0, -1), Belt.DIR_N):
		failures.append("[B] N belt placement failed")
		_cleanup(world)
		return
	if not world.place_building(Buildings.Type.CHEST, Vector2i(0, -2)):
		failures.append("[B] N chest placement failed")
		_cleanup(world)
		return
	if not world.place_building(Buildings.Type.BELT, Vector2i(0, 1), Belt.DIR_S):
		failures.append("[B] S belt placement failed")
		_cleanup(world)
		return
	if not world.place_building(Buildings.Type.CHEST, Vector2i(0, 2)):
		failures.append("[B] S chest placement failed")
		_cleanup(world)
		return

	var retter: Building = world.building_at(Vector2i(0, 0))
	retter.state["out_buffer"] = [[Items.Type.FIBER, 10]]
	retter.state["in_buffer"] = []
	retter.state["state"] = Processor.IDLE
	retter.state["progress"] = 0

	for _i in 1500:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var n_chest: Building = world.building_at(Vector2i(0, -2))
	var s_chest: Building = world.building_at(Vector2i(0, 2))
	var n_count: int = _bag_count(n_chest.state.get("bag", []), Items.Type.FIBER)
	var s_count: int = _bag_count(s_chest.state.get("bag", []), Items.Type.FIBER)

	# S chest should receive ≥9 of 10 (1 in flight at budget end).
	if s_count < 9:
		failures.append("[B dir=S] S chest expected ≥9 fiber of 10, got %d" % s_count)
	# N chest should be empty (no canonical W output declared).
	if n_count != 0:
		failures.append("[B dir=S] N chest got unexpected fiber ×%d (canonical W has no output)" % n_count)

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
