extends RefCounted

## Inserter Arc Session 2 tests (session-inserter-fast-filter).
##
## Locks in the fast-tier + filter mechanic + parametric refactor regression
## + fuel-port-dir bug fix:
##
##   1. Basic inserter cycle unchanged (regression after parametric refactor).
##   2. Fast inserter cycles in half the ticks (10 vs 20).
##   3. Filter unset → behaves like basic (FIFO from chest, any item).
##   4. Filter set on chest source → only matching item picked, others remain.
##   5. Filter set on belt source → matching item picked.
##   6. Filter set on belt source → wrong-type item NOT picked (stays on belt).
##   7. Panel drop-to-set: cursor item TYPE copied to filter, cursor unchanged.
##   8. Panel right-click clears filter to -1.
##   9. Save round-trip preserves filter_item_type across all states.
##  10. FUEL_PORT_DIR fix: wood in source chest NOT consumed as fuel
##      (caught at PAUSE 1, fixed by mirroring Smelter pattern).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_inserter.json"

static func test_name() -> String:
	return "inserter (parametric refactor + filter pickup + drop-to-set + RMB-clear + save + fuel-port fix + refactor regression + long-reach tier)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ===========================================================================
	# (1) BASIC INSERTER CYCLE UNCHANGED — regression for parametric refactor.
	# Basic inserter must still take 20 ticks per full cycle, pick any item
	# from chest. Validates Inserter.cycle_ticks(b) lookup wired correctly.
	# ===========================================================================
	var world = _make_world(parent)
	# Place inserter at (10,10) facing E. Source = (9,10), dest = (11,10), fuel = (10,11).
	if not world.place_building(Buildings.Type.INSERTER, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "basic inserter placement failed" }
	if not world.place_building(Buildings.Type.CHEST, Vector2i(9, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "source chest placement failed" }
	if not world.place_building(Buildings.Type.CHEST, Vector2i(11, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "dest chest placement failed" }
	var inserter: Building = world.building_at(Vector2i(10, 10))
	var src_chest: Building = world.building_at(Vector2i(9, 10))
	var dst_chest: Building = world.building_at(Vector2i(11, 10))
	# Pre-fuel the inserter via state (skip fuel-pull path for cycle measurement).
	inserter.state["fuel_buffer"] = 100
	# Source chest has 5 wheat to transport.
	src_chest.state["bag"] = [[Items.Type.WHEAT, 5]]
	# Run 20 ticks — basic inserter should complete exactly one cycle (1 item moved).
	for _i in 20:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var basic_dst_count: int = _bag_count(dst_chest.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, basic_dst_count == 1,
		"(1) basic inserter @ 20 ticks should move exactly 1 wheat to dest, got %d" % basic_dst_count)
	# Verify cycle_ticks lookup returns 20 for basic.
	_check(failures, Inserter.cycle_ticks(inserter) == 20,
		"(1) Inserter.cycle_ticks(basic) should be 20, got %d" % Inserter.cycle_ticks(inserter))

	# ===========================================================================
	# (2) FAST INSERTER CYCLE — 10 ticks per cycle (half of basic).
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	if not world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "fast inserter placement failed" }
	world.place_building(Buildings.Type.CHEST, Vector2i(9, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(11, 10), Belt.DIR_E)
	var fast: Building = world.building_at(Vector2i(10, 10))
	src_chest = world.building_at(Vector2i(9, 10))
	dst_chest = world.building_at(Vector2i(11, 10))
	fast.state["fuel_buffer"] = 100
	src_chest.state["bag"] = [[Items.Type.WHEAT, 5]]
	# Cycle ticks lookup.
	_check(failures, Inserter.cycle_ticks(fast) == 10,
		"(2) Inserter.cycle_ticks(fast) should be 10, got %d" % Inserter.cycle_ticks(fast))
	# Run 10 ticks → 1 item moved.
	for _i in 10:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var fast_dst_count: int = _bag_count(dst_chest.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, fast_dst_count == 1,
		"(2) fast inserter @ 10 ticks should move exactly 1 wheat, got %d" % fast_dst_count)
	# Run another 10 ticks → 2 total.
	for _i in 10:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	fast_dst_count = _bag_count(dst_chest.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, fast_dst_count == 2,
		"(2) fast inserter @ 20 ticks should have moved 2 wheat (twice as fast as basic), got %d" % fast_dst_count)

	# ===========================================================================
	# (3) FILTER UNSET — fast inserter behaves like basic (any item picked).
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(9, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(11, 10), Belt.DIR_E)
	fast = world.building_at(Vector2i(10, 10))
	src_chest = world.building_at(Vector2i(9, 10))
	dst_chest = world.building_at(Vector2i(11, 10))
	fast.state["fuel_buffer"] = 100
	# Filter is -1 by default (set in Inserter.make).
	_check(failures, int(fast.state.get("filter_item_type", -2)) == -1,
		"(3) fast inserter filter should default to -1 (no filter)")
	# Source has wheat+flax. Either should be picked (FIFO order: wheat first).
	src_chest.state["bag"] = [[Items.Type.WHEAT, 2], [Items.Type.FLAX, 2]]
	# Cycle is 11 ticks for fast (1 IDLE pickup + 5 swing-out + 5 swing-in).
	# 4 items needs 44 ticks of cycling; bump to 60 for safety margin.
	for _i in 60:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var dst_total: int = _total_in_bag(dst_chest.state.get("bag", []))
	_check(failures, dst_total == 4,
		"(3) filter unset: 60 ticks should move all 4 items, got %d" % dst_total)

	# ===========================================================================
	# (4) FILTER SET ON CHEST SOURCE — only matching item picked, others stay.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(9, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(11, 10), Belt.DIR_E)
	fast = world.building_at(Vector2i(10, 10))
	src_chest = world.building_at(Vector2i(9, 10))
	dst_chest = world.building_at(Vector2i(11, 10))
	fast.state["fuel_buffer"] = 100
	fast.state["filter_item_type"] = Items.Type.WHEAT
	src_chest.state["bag"] = [[Items.Type.WHEAT, 3], [Items.Type.FLAX, 3]]
	# Run 40 ticks → all 3 wheat picked, all 3 flax should remain.
	for _i in 40:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var src_wheat_left: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WHEAT)
	var src_flax_left: int = _bag_count(src_chest.state.get("bag", []), Items.Type.FLAX)
	var dst_wheat: int = _bag_count(dst_chest.state.get("bag", []), Items.Type.WHEAT)
	var dst_flax: int = _bag_count(dst_chest.state.get("bag", []), Items.Type.FLAX)
	_check(failures, src_wheat_left == 0,
		"(4) filter=WHEAT: source should have 0 wheat left, got %d" % src_wheat_left)
	_check(failures, src_flax_left == 3,
		"(4) filter=WHEAT: source flax should be untouched (3), got %d" % src_flax_left)
	_check(failures, dst_wheat == 3,
		"(4) filter=WHEAT: dest should have 3 wheat, got %d" % dst_wheat)
	_check(failures, dst_flax == 0,
		"(4) filter=WHEAT: dest should have 0 flax, got %d" % dst_flax)

	# ===========================================================================
	# (5) FILTER SET ON BELT — matching item in facing slot is picked.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(9, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(11, 10), Belt.DIR_E)
	fast = world.building_at(Vector2i(10, 10))
	var src_belt: Building = world.building_at(Vector2i(9, 10))
	dst_chest = world.building_at(Vector2i(11, 10))
	fast.state["fuel_buffer"] = 100
	fast.state["filter_item_type"] = Items.Type.WHEAT
	# Set the belt slot facing the inserter to wheat. slot_facing_external
	# returns the index; place a wheat there.
	var face_idx: int = Belt.slot_facing_external(src_belt, fast.anchor)
	if face_idx >= 0 and face_idx < src_belt.state["slots"].size():
		src_belt.state["slots"][face_idx] = Items.Type.WHEAT
	# Run 10 ticks (one fast cycle) → wheat should be picked.
	for _i in 10:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	dst_wheat = _bag_count(dst_chest.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, dst_wheat == 1,
		"(5) filter=WHEAT, belt has wheat → should pick 1 wheat, got %d" % dst_wheat)

	# ===========================================================================
	# (6) FILTER SET ON BELT — wrong-type item NOT picked, stays on belt.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(9, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(11, 10), Belt.DIR_E)
	fast = world.building_at(Vector2i(10, 10))
	src_belt = world.building_at(Vector2i(9, 10))
	dst_chest = world.building_at(Vector2i(11, 10))
	fast.state["fuel_buffer"] = 100
	fast.state["filter_item_type"] = Items.Type.WHEAT
	# Belt has FLAX in the facing slot — wrong type for the filter.
	face_idx = Belt.slot_facing_external(src_belt, fast.anchor)
	if face_idx >= 0 and face_idx < src_belt.state["slots"].size():
		src_belt.state["slots"][face_idx] = Items.Type.FLAX
	# Run 30 ticks (3 cycles) → flax should NOT be picked.
	for _i in 30:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var dst_total_6: int = _total_in_bag(dst_chest.state.get("bag", []))
	_check(failures, dst_total_6 == 0,
		"(6) filter=WHEAT, belt has flax → nothing should be picked, dst total = %d" % dst_total_6)
	# Flax should still be on the belt.
	var slot_after: int = int(src_belt.state["slots"][face_idx]) if face_idx >= 0 else -1
	_check(failures, slot_after == Items.Type.FLAX,
		"(6) flax should still be on belt (filter rejected pickup), got slot=%d" % slot_after)

	# ===========================================================================
	# (7) PANEL DROP-TO-SET — cursor item type copied to filter, cursor unchanged.
	# Tests BuildingPanel._drop_into_filter directly without scene-tree concerns.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E)
	fast = world.building_at(Vector2i(10, 10))
	var panel = preload("res://scripts/ui/building_panel.gd").new()
	parent.add_child(panel)
	var inv := Inventory.new(8)
	var cursor := CursorStack.new()
	panel.cursor = cursor
	panel.inventory = inv
	panel.toast_callback = func(_msg): pass
	panel.open(fast, world)
	# Cursor has 5 wheat. Drop onto filter slot.
	cursor.pick(Items.Type.WHEAT, 5)
	var filter_slot_def: Dictionary = Buildings.slot_layout_for(Buildings.Type.FAST_INSERTER)[2]    # filter is 3rd slot
	_check(failures, str(filter_slot_def.get("kind", "")) == "filter",
		"(7) sanity: 3rd slot of FAST_INSERTER should be 'filter' kind, got '%s'" % str(filter_slot_def.get("kind", "")))
	panel._drop_into_slot(filter_slot_def, -1, SlotClickHandler.MOD_NONE)
	_check(failures, int(fast.state.get("filter_item_type", -1)) == Items.Type.WHEAT,
		"(7) drop-to-set: filter_item_type should be WHEAT, got %d" % int(fast.state.get("filter_item_type", -1)))
	_check(failures, cursor.has_item() and cursor.item_type == Items.Type.WHEAT and cursor.count == 5,
		"(7) drop-to-set: cursor should be UNCHANGED (still 5 wheat), got type=%d count=%d" % [cursor.item_type, cursor.count])
	cursor.clear()
	panel.queue_free()

	# ===========================================================================
	# (8) PANEL RIGHT-CLICK CLEARS FILTER. Tests FastInserterPanel._gui_input
	# branch directly via simulated InputEventMouseButton.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E)
	fast = world.building_at(Vector2i(10, 10))
	fast.state["filter_item_type"] = Items.Type.WHEAT     # pre-set
	var fast_panel = preload("res://scripts/ui/fast_inserter_panel.gd").new()
	parent.add_child(fast_panel)
	fast_panel.cursor = CursorStack.new()
	fast_panel.inventory = Inventory.new(8)
	fast_panel.toast_callback = func(_msg): pass
	fast_panel.open(fast, world)
	# Find the filter slot rect and synthesize a right-click on it.
	var rects: Array = fast_panel._building_slot_rects()
	var filter_rect: Rect2 = Rect2(0, 0, 0, 0)
	for entry in rects:
		if str(entry["slot_def"].get("kind", "")) == "filter":
			filter_rect = entry["rect"]
			break
	_check(failures, filter_rect.size.x > 0,
		"(8) sanity: should find filter slot rect among _building_slot_rects()")
	var rmb_event := InputEventMouseButton.new()
	rmb_event.button_index = MOUSE_BUTTON_RIGHT
	rmb_event.pressed = true
	rmb_event.position = filter_rect.position + filter_rect.size * 0.5    # center of rect
	fast_panel._gui_input(rmb_event)
	_check(failures, int(fast.state.get("filter_item_type", -2)) == -1,
		"(8) RMB on filter slot should clear filter to -1, got %d" % int(fast.state.get("filter_item_type", -2)))
	fast_panel.queue_free()

	# ===========================================================================
	# (9) SAVE ROUND-TRIP — filter_item_type preserved across save+load.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 10), Belt.DIR_E)
	fast = world.building_at(Vector2i(10, 10))
	fast.state["filter_item_type"] = Items.Type.WHEAT
	fast.state["fuel_buffer"] = 7
	fast.state["last_fuel_item"] = Items.Type.COAL
	# Save.
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16)):
		_cleanup(world, player_a, null, null, orig_path)
		return { "ok": false, "message": "save_game failed during (9) save-roundtrip test" }
	# Load into fresh world.
	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_cleanup(world, player_a, world_b, player_b, orig_path)
		return { "ok": false, "message": "load_game failed during (9): %s" % result.error_message }
	var fast_b: Building = world_b.building_at(Vector2i(10, 10))
	if fast_b == null:
		failures.append("(9) fast inserter missing after load")
	else:
		_check(failures, int(fast_b.state.get("filter_item_type", -2)) == Items.Type.WHEAT,
			"(9) filter_item_type should be WHEAT after load, got %d" % int(fast_b.state.get("filter_item_type", -2)))
		_check(failures, int(fast_b.state.get("fuel_buffer", -1)) == 7,
			"(9) fuel_buffer should be 7 after load, got %d" % int(fast_b.state.get("fuel_buffer", -1)))
		_check(failures, fast_b.type == Buildings.Type.FAST_INSERTER,
			"(9) building type should be FAST_INSERTER after load, got %d" % fast_b.type)

	# ===========================================================================
	# (10) FUEL_PORT_DIR FIX — wood in source chest NOT consumed as fuel.
	# Bug caught at PAUSE 1 (Inserter.tick called Burner.try_pull_fuel with
	# -1 = scan all edges; source chest with wood was eaten as fuel instead
	# of being transported). Fix: restrict fuel pull to FUEL_PORT_DIR (S).
	# ===========================================================================
	_cleanup(world, player_a, world_b, player_b, orig_path)
	world = _make_world(parent)
	world.place_building(Buildings.Type.INSERTER, Vector2i(10, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(9, 10), Belt.DIR_E)    # source (W)
	world.place_building(Buildings.Type.CHEST, Vector2i(11, 10), Belt.DIR_E)   # dest (E)
	# NO fuel chest at S (10,11) — inserter has zero fuel access.
	inserter = world.building_at(Vector2i(10, 10))
	src_chest = world.building_at(Vector2i(9, 10))
	dst_chest = world.building_at(Vector2i(11, 10))
	# Source chest has WOOD (fuel-eligible item). Pre-fix bug: would be eaten.
	src_chest.state["bag"] = [[Items.Type.WOOD, 3]]
	# Inserter starts with zero fuel.
	inserter.state["fuel_buffer"] = 0
	# Run 50 ticks. The inserter should be NO_FUEL (no fuel from S edge);
	# source wood should be UNTOUCHED (NOT consumed as fuel).
	for _i in 50:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var src_wood_left: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WOOD)
	_check(failures, src_wood_left == 3,
		"(10) FUEL_PORT_DIR fix: source chest wood should be untouched (3), got %d (bug: got eaten as fuel)" % src_wood_left)
	_check(failures, int(inserter.state.get("fuel_buffer", -1)) == 0,
		"(10) fuel_buffer should still be 0 (no fuel from S edge), got %d" % int(inserter.state.get("fuel_buffer", -1)))
	# Verify inserter went into NO_FUEL state.
	_check(failures, int(inserter.state.get("state", -1)) == Inserter.STATE_NO_FUEL,
		"(10) inserter should be in STATE_NO_FUEL, got %d" % int(inserter.state.get("state", -1)))
	# Now place fuel chest at S edge with wood — inserter should pull from there.
	world.place_building(Buildings.Type.CHEST, Vector2i(10, 11), Belt.DIR_E)
	var fuel_chest: Building = world.building_at(Vector2i(10, 11))
	fuel_chest.state["bag"] = [[Items.Type.WOOD, 5]]
	# Basic cycle is 21 ticks (1 IDLE + 10 swing-out + 10 swing-in). Run 100
	# ticks for ~4-5 complete cycles — more than enough to drain the source.
	for _i in 100:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Inserter should have pulled fuel from S chest (not source W chest).
	_check(failures, int(inserter.state.get("fuel_buffer", 0)) > 0 or _bag_count(fuel_chest.state.get("bag", []), Items.Type.WOOD) < 5,
		"(10) inserter should have pulled fuel from S chest")
	# Wood conservation: account for in-flight items held in held_item_buffer.
	# Source wood + dest wood + held wood should equal the original 3, with
	# zero loss to the fuel buffer (the fuel was supplied by S chest, not W).
	var src_wood_after: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WOOD)
	var dst_wood: int = _bag_count(dst_chest.state.get("bag", []), Items.Type.WOOD)
	var held_wood: int = 1 if Inserter.held_item_type(inserter) == Items.Type.WOOD else 0
	_check(failures, src_wood_after + dst_wood + held_wood == 3,
		"(10) wood conservation: source(%d) + dest(%d) + held(%d) should = 3 (none lost to fuel)" % [src_wood_after, dst_wood, held_wood])

	# ===========================================================================
	# (11) PARAMETRIC REFACTOR REGRESSION — Session 3 (long-reach prep).
	# Guards the ARM_LENGTH const → ARM_LENGTH_BY_TYPE refactor and the new
	# REACH_BY_TYPE accessor. Asserts that basic + fast tiers' values are
	# unchanged after the refactor.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.INSERTER, Vector2i(10, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(15, 10), Belt.DIR_E)
	# Note: variables suffixed `_r` (regression) to avoid scope collision with
	# `fast_b` already declared earlier in this function at sub-case (2).
	var basic_r: Building = world.building_at(Vector2i(10, 10))
	var fast_r: Building = world.building_at(Vector2i(15, 10))
	# Cycle ticks unchanged (already covered by (1)(2), repeated here as a
	# package — readers landing on (11) get the full refactor contract).
	_check(failures, Inserter.cycle_ticks(basic_r) == 20,
		"(11) basic cycle_ticks should remain 20, got %d" % Inserter.cycle_ticks(basic_r))
	_check(failures, Inserter.cycle_ticks(fast_r) == 10,
		"(11) fast cycle_ticks should remain 10, got %d" % Inserter.cycle_ticks(fast_r))
	# NEW: reach() accessor returns 1 for both pre-existing tiers.
	_check(failures, Inserter.reach(basic_r) == 1,
		"(11) basic reach should be 1, got %d" % Inserter.reach(basic_r))
	_check(failures, Inserter.reach(fast_r) == 1,
		"(11) fast reach should be 1, got %d" % Inserter.reach(fast_r))
	# NEW: arm_length() accessor returns 0.55 for both pre-existing tiers
	# (was a const before the refactor; baseline preserved).
	_check(failures, abs(Inserter.arm_length(basic_r) - 0.55) < 0.001,
		"(11) basic arm_length should be 0.55, got %f" % Inserter.arm_length(basic_r))
	_check(failures, abs(Inserter.arm_length(fast_r) - 0.55) < 0.001,
		"(11) fast arm_length should be 0.55, got %f" % Inserter.arm_length(fast_r))
	# source_tile / dest_tile remain 1-tile offset for both tiers across rotations.
	for dir_r in [Belt.DIR_E, Belt.DIR_S, Belt.DIR_W, Belt.DIR_N]:
		basic_r.state["dir"] = dir_r
		fast_r.state["dir"] = dir_r
		var v_r: Vector2i = Belt.DIR_VECS[dir_r]
		var basic_expected_src: Vector2i = Vector2i(basic_r.anchor.x - v_r.x, basic_r.anchor.y - v_r.y)
		var basic_expected_dst: Vector2i = Vector2i(basic_r.anchor.x + v_r.x, basic_r.anchor.y + v_r.y)
		_check(failures, Inserter.source_tile(basic_r) == basic_expected_src,
			"(11) basic source_tile dir=%d should be %s, got %s" % [dir_r, str(basic_expected_src), str(Inserter.source_tile(basic_r))])
		_check(failures, Inserter.dest_tile(basic_r) == basic_expected_dst,
			"(11) basic dest_tile dir=%d should be %s, got %s" % [dir_r, str(basic_expected_dst), str(Inserter.dest_tile(basic_r))])
		var fast_expected_src: Vector2i = Vector2i(fast_r.anchor.x - v_r.x, fast_r.anchor.y - v_r.y)
		var fast_expected_dst: Vector2i = Vector2i(fast_r.anchor.x + v_r.x, fast_r.anchor.y + v_r.y)
		_check(failures, Inserter.source_tile(fast_r) == fast_expected_src,
			"(11) fast source_tile dir=%d should be %s, got %s" % [dir_r, str(fast_expected_src), str(Inserter.source_tile(fast_r))])
		_check(failures, Inserter.dest_tile(fast_r) == fast_expected_dst,
			"(11) fast dest_tile dir=%d should be %s, got %s" % [dir_r, str(fast_expected_dst), str(Inserter.dest_tile(fast_r))])

	# ===========================================================================
	# (12) LONG-REACH INSERTER CYCLE TIMING — 30 ticks per cycle (1.5s @ 20 TPS).
	# Drop fires when cycle_progress first reaches 0.5; with inc = 1/30, that's
	# the 15th tick of WORKING_OUT.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	if not world.place_building(Buildings.Type.LONG_REACH_INSERTER, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(12) long-reach inserter placement failed" }
	# Source 2 tiles west of inserter; dest 2 tiles east.
	world.place_building(Buildings.Type.CHEST, Vector2i(8, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(12, 10), Belt.DIR_E)
	var lr: Building = world.building_at(Vector2i(10, 10))
	var src_12: Building = world.building_at(Vector2i(8, 10))
	var dst_12: Building = world.building_at(Vector2i(12, 10))
	lr.state["fuel_buffer"] = 100
	src_12.state["bag"] = [[Items.Type.WHEAT, 5]]
	# Cycle ticks lookup returns 30.
	_check(failures, Inserter.cycle_ticks(lr) == 30,
		"(12) long-reach cycle_ticks should be 30, got %d" % Inserter.cycle_ticks(lr))
	# Reach lookup returns 2.
	_check(failures, Inserter.reach(lr) == 2,
		"(12) long-reach reach should be 2, got %d" % Inserter.reach(lr))
	# Arm length returns 1.10.
	_check(failures, abs(Inserter.arm_length(lr) - 1.10) < 0.001,
		"(12) long-reach arm_length should be 1.10, got %f" % Inserter.arm_length(lr))
	# Body color returns the rust-red entry (not the default).
	var lr_color: Color = Inserter.body_color(lr)
	# Tolerance 0.001 matches arm_length comparison above — Color floats are
	# exact to <1e-6, so the looser 0.01 used pre-fix-up was 10000x slack.
	_check(failures, abs(lr_color.r - 0.65) < 0.001 and abs(lr_color.g - 0.30) < 0.001 and abs(lr_color.b - 0.22) < 0.001,
		"(12) long-reach body_color should be rust-red (0.65, 0.30, 0.22), got (%f, %f, %f)" % [lr_color.r, lr_color.g, lr_color.b])

	# ===========================================================================
	# (13) LONG-REACH 2-TILE REACH — source/dest tiles offset by 2 across all
	# 4 rotations. Validates that source_tile() / dest_tile() multiply by reach(b).
	# ===========================================================================
	for dir_13 in [Belt.DIR_E, Belt.DIR_S, Belt.DIR_W, Belt.DIR_N]:
		lr.state["dir"] = dir_13
		var v_13: Vector2i = Belt.DIR_VECS[dir_13]
		var expected_src: Vector2i = Vector2i(lr.anchor.x - v_13.x * 2, lr.anchor.y - v_13.y * 2)
		var expected_dst: Vector2i = Vector2i(lr.anchor.x + v_13.x * 2, lr.anchor.y + v_13.y * 2)
		_check(failures, Inserter.source_tile(lr) == expected_src,
			"(13) long-reach source_tile dir=%d should be %s, got %s" % [dir_13, str(expected_src), str(Inserter.source_tile(lr))])
		_check(failures, Inserter.dest_tile(lr) == expected_dst,
			"(13) long-reach dest_tile dir=%d should be %s, got %s" % [dir_13, str(expected_dst), str(Inserter.dest_tile(lr))])

	_disconnect(world); world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "13 sub-cases pass: basic cycle + fast cycle + filter unset + filter chest + filter belt match + filter belt mismatch + drop-to-set + RMB clear + save round-trip + fuel-port fix + parametric refactor regression + long-reach tier + long-reach 2-tile reach" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

static func _make_world(parent: Node) -> Node2D:
	var w = GridWorldScript.new()
	parent.add_child(w)
	# Stone overlay across the test area — chests / belts / drills all
	# require STONE/PATH/SOIL_TILLED. Inserter accepts NONE but is fine
	# on stone too. One overlay choice keeps placement uniform.
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

static func _total_in_bag(bag: Array) -> int:
	var n: int = 0
	for entry in bag:
		n += int(entry[1])
	return n

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

static func _cleanup(world, player_a, world_b, player_b, orig_path: String) -> void:
	_disconnect(world)
	if world != null: world.queue_free()
	if player_a != null: player_a.queue_free()
	_disconnect(world_b)
	if world_b != null: world_b.queue_free()
	if player_b != null: player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
