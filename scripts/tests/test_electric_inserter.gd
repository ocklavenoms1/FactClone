extends RefCounted

## Inserter Arc Session 4 tests (session-inserter-electric).
##
## Locks in the ELECTRIC_INSERTER tier. This file GROWS across Tasks 4-8;
## each task appends its own `_case_*` function and wires it into `run()`,
## so the sub-case list below is the running index:
##
##   1. Registry + parametric tables (Task 4).
##   2. Existing-tier regression — adding rows disturbed nothing (Task 4).
##   3. No fuel path — the tier has no fuel slot, so it must never report a
##      fuel problem and must never burn fuel (Task 5).
##   4. Constant power demand — registered on the component, and identical
##      whether the arm is idle or mid-swing (Task 5).
##
## Power CONSEQUENCES (satisfaction scaling, STATE_NO_POWER) are Tasks 6-7;
## Task 5 only removes the fuel dependency and registers the draw.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Power units drawn by one ELECTRIC_INSERTER. Asserted as a LITERAL rather
# than read back from Inserter's own table: the point of sub-case 4 is to
# pin the balance number independently of the implementation, so a silent
# edit to the table shows up as a test failure instead of being ratified by
# a self-referential assertion. Windmill supplies 6, so one windmill runs
# roughly one electric inserter.
const ELECTRIC_DEMAND: int = 5

# Sub-case 4 layout (inside the stone patch painted by _make_world).
# Windmill 2x2 at (7,8) covers (7,8)(8,8)(7,9)(8,9); the pole sits on its
# east edge cell, and the inserter sits at Chebyshev 1 from the pole so it
# falls inside PowerNetwork.SUPPLY_RADIUS.
const WINDMILL_POS: Vector2i  = Vector2i(7, 8)
const POLE_POS: Vector2i      = Vector2i(9, 8)
const ELEC_INS_POS: Vector2i  = Vector2i(10, 9)

# Bound on the "tick until the arm is holding something" loop. The electric
# tier's cycle is 5 ticks, so a pickup lands on tick 1; 40 is a wide margin
# that still terminates promptly when the pickup never happens.
const MAX_PICKUP_TICKS: int = 40

# Ticks allowed for sub-case 3's transport run. 5-tick cycle + 1 IDLE
# pickup tick ~= 7 ticks per item; 40 comfortably moves several items.
const TRANSPORT_TICKS: int = 40

# Sentinel poked into fuel_buffer in sub-case 3b. Any value > 0 works; a
# distinctive one makes an unexpected decrement obvious in the failure text.
const FUEL_SENTINEL: int = 7

static func test_name() -> String:
	return "electric inserter (registry + tables + no-fuel path + constant power demand)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_registry_and_tables(parent, failures)
	_case_existing_tier_regression(parent, failures)
	_case_no_fuel_path(parent, failures)
	_case_constant_demand(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "4 sub-cases pass: registry/tables + existing-tier regression + no-fuel path + constant power demand" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

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

# ===========================================================================
# (3) NO FUEL PATH.
# The electric tier's DATA slot_layout declares no "fuel" slot, so it can
# never BE fuelled. A machine that cannot be fuelled must never report a
# fuel problem, and must never burn fuel.
#
# Two halves, deliberately in separate worlds so they cannot contaminate
# each other:
#   3a — NO fuel anywhere. The inserter must not park in STATE_NO_FUEL, and
#        must actually move items. This is the player-visible bug: at Task 4
#        a placed electric inserter froze in "NO FUEL" forever.
#   3b — a sentinel fuel_buffer poked straight into state. It must come back
#        UNTOUCHED. 3a alone cannot catch a live Burner.consume_tick call,
#        because consume_tick is a no-op on an empty buffer — it would pass
#        even with the fuel path fully wired up.
# ===========================================================================
static func _case_no_fuel_path(parent: Node, failures: Array) -> void:
	# --- DATA: the tier declares no fuel slot ---
	var layout: Array = Buildings.slot_layout_for(Buildings.Type.ELECTRIC_INSERTER)
	var fuel_slots: int = 0
	for slot in layout:
		if str(slot.get("kind", "")) == "fuel":
			fuel_slots += 1
	_check(failures, fuel_slots == 0,
		"(3) slot_layout_for(ELECTRIC_INSERTER) must declare NO 'fuel' slot, found %d" % fuel_slots)

	# --- 3a: no fuel anywhere ---
	var world = _make_world(parent)
	var ins: Building = _place_electric_with_chests(world, Vector2i(10, 10), failures, "(3a)")
	if ins == null:
		_disconnect(world); world.queue_free()
		return
	# WHEAT, not a fuel item — nothing in this world is burnable, and the
	# fuel port tile (FUEL_PORT_DIR = S, rotated by dir=E -> (10,11)) is
	# empty, so there is no refuel path even if one were attempted.
	var src_chest: Building = world.building_at(Inserter.source_tile(ins))
	src_chest.state["bag"] = [[Items.Type.WHEAT, 3]]
	_check(failures, int(ins.state.get("fuel_buffer", 0)) == 0,
		"(3a) SETUP: electric inserter should start with an empty fuel buffer, got %d" % int(ins.state.get("fuel_buffer", 0)))

	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	var state_after_1: int = int(ins.state.get("state", -1))
	_check(failures, state_after_1 != Inserter.STATE_NO_FUEL,
		"(3a) a tier with no fuel slot must never report STATE_NO_FUEL, got state %d after one tick" % state_after_1)

	# It must not merely avoid the NO_FUEL label — it must actually work.
	for _i in TRANSPORT_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var dst_chest: Building = world.building_at(Inserter.dest_tile(ins))
	var delivered: int = _bag_count(dst_chest.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, delivered > 0,
		"(3a) unfuelled electric inserter should still transport items, delivered %d" % delivered)
	_check(failures, int(ins.state.get("fuel_buffer", 0)) == 0,
		"(3a) fuel_buffer must stay 0 (never topped up), got %d" % int(ins.state.get("fuel_buffer", 0)))
	_disconnect(world); world.queue_free()

	# --- 3b: sentinel fuel must not be consumed ---
	var world2 = _make_world(parent)
	var ins2: Building = _place_electric_with_chests(world2, Vector2i(10, 10), failures, "(3b)")
	if ins2 == null:
		_disconnect(world2); world2.queue_free()
		return
	var src2: Building = world2.building_at(Inserter.source_tile(ins2))
	src2.state["bag"] = [[Items.Type.WHEAT, 3]]
	# Poke fuel straight into state (bypasses the pull path — same trick
	# test_inserter.gd and test_inserter_fuel_conservation.gd use).
	ins2.state["fuel_buffer"] = FUEL_SENTINEL
	ins2.state["fuel_burn_progress"] = 0
	for _i in TRANSPORT_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var dst2: Building = world2.building_at(Inserter.dest_tile(ins2))
	_check(failures, _bag_count(dst2.state.get("bag", []), Items.Type.WHEAT) > 0,
		"(3b) SETUP: inserter should have run (otherwise the fuel assertion below is vacuous)")
	_check(failures, int(ins2.state.get("fuel_buffer", -1)) == FUEL_SENTINEL,
		"(3b) electric tier must not consume fuel: fuel_buffer should still be %d, got %d" % [FUEL_SENTINEL, int(ins2.state.get("fuel_buffer", -1))])
	_check(failures, int(ins2.state.get("fuel_burn_progress", -1)) == 0,
		"(3b) electric tier must not advance fuel_burn_progress, got %d" % int(ins2.state.get("fuel_burn_progress", -1)))
	_disconnect(world2); world2.queue_free()

# ===========================================================================
# (4) CONSTANT POWER DEMAND.
# The electric inserter registers ELECTRIC_DEMAND on the component that
# supplies it (CONSUMER rule — Chebyshev SUPPLY_RADIUS around a pole, the
# same rule lamps use), and that draw is CONSTANT.
#
# Constant, not duty-cycled, is a locked design decision. PowerNetwork.
# update_supply_demand runs as a PRE-PASS in grid_world._on_tick, BEFORE the
# building tick loop, so any activity state it read would be one tick stale.
# Gating demand on activity would therefore close a delayed-feedback loop:
# the network would size itself to last tick's activity, and lamps sharing
# the component would flicker in response. An idle inserter draws full
# power — that is the intended cost of the tier.
#
# Two worlds, identical layout, differing only in whether the source chest
# has anything in it: one inserter sits idle, one is caught mid-swing
# holding an item. The component demand must be the same number.
# ===========================================================================
static func _case_constant_demand(parent: Node, failures: Array) -> void:
	# --- idle: empty source chest, never ticked ---
	var idle_world = _build_powered_world(parent, false, failures, "(4-idle)")
	if idle_world == null:
		return
	PowerNetwork.update_supply_demand(idle_world)
	var comp_idle: int = PowerNetwork.network_id_at(idle_world, POLE_POS)
	var demand_idle: int = -1
	_check(failures, comp_idle >= 0,
		"(4) SETUP: pole at %s should be in a network, got comp_id %d" % [str(POLE_POS), comp_idle])
	if comp_idle >= 0:
		# Setup sanity: without supply the demand numbers would still be
		# right but the scenario would not be the "powered network" the
		# design decision is about.
		var supply_idle: int = PowerNetwork.supply_for(idle_world, comp_idle)
		_check(failures, supply_idle == Windmill.MAX_OUTPUT,
			"(4) SETUP: windmill should supply %d to the component, got %d" % [Windmill.MAX_OUTPUT, supply_idle])
		demand_idle = PowerNetwork.demand_for(idle_world, comp_idle)
		_check(failures, demand_idle == ELECTRIC_DEMAND,
			"(4) component demand should include the electric inserter's %d, got %d" % [ELECTRIC_DEMAND, demand_idle])
	var ins_idle: Building = idle_world.building_at(ELEC_INS_POS)
	_check(failures, ins_idle != null and Inserter.held_item_type(ins_idle) < 0,
		"(4) SETUP: idle-case inserter should be empty-handed")
	_disconnect(idle_world); idle_world.queue_free()

	# --- mid-swing: stocked source chest, ticked until the arm is loaded ---
	var swing_world = _build_powered_world(parent, true, failures, "(4-swing)")
	if swing_world == null:
		return
	var ins_swing: Building = swing_world.building_at(ELEC_INS_POS)
	if ins_swing == null:
		_check(failures, false, "(4) SETUP: no electric inserter at %s in the mid-swing world" % str(ELEC_INS_POS))
		_disconnect(swing_world); swing_world.queue_free()
		return
	var holding: bool = false
	for _i in MAX_PICKUP_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if Inserter.held_item_type(ins_swing) >= 0:
			holding = true
			break
	_check(failures, holding,
		"(4) SETUP: electric inserter never picked an item up within %d ticks — cannot measure mid-swing demand" % MAX_PICKUP_TICKS)
	# Recompute explicitly so demand is measured WHILE the arm is loaded,
	# not from the pre-pass that ran before this tick's pickup.
	PowerNetwork.update_supply_demand(swing_world)
	var comp_swing: int = PowerNetwork.network_id_at(swing_world, POLE_POS)
	var demand_swing: int = -1
	_check(failures, comp_swing >= 0,
		"(4) SETUP: pole at %s should be in a network (mid-swing world), got comp_id %d" % [str(POLE_POS), comp_swing])
	if comp_swing >= 0:
		demand_swing = PowerNetwork.demand_for(swing_world, comp_swing)
		_check(failures, demand_swing == ELECTRIC_DEMAND,
			"(4) mid-swing component demand should be %d, got %d" % [ELECTRIC_DEMAND, demand_swing])
	_disconnect(swing_world); swing_world.queue_free()

	# The design decision itself: activity must not move the number.
	_check(failures, demand_idle == demand_swing,
		"(4) demand must be CONSTANT (no duty-cycling): idle drew %d, mid-swing drew %d" % [demand_idle, demand_swing])

# ---------- helpers (house style, copied from test_inserter.gd) ----------

## Place an electric inserter at `pos` facing east, with chests on its
## source and destination tiles (asked for via Inserter.source_tile /
## dest_tile rather than hardcoded offsets). Returns the inserter Building,
## or null after appending a setup failure.
static func _place_electric_with_chests(world, pos: Vector2i, failures: Array, label: String) -> Building:
	if not world.place_building(Buildings.Type.ELECTRIC_INSERTER, pos, Belt.DIR_E):
		_check(failures, false, "%s SETUP: electric inserter placement at %s failed" % [label, str(pos)])
		return null
	var ins: Building = world.building_at(pos)
	if ins == null:
		_check(failures, false, "%s SETUP: building_at(%s) returned null after a successful placement" % [label, str(pos)])
		return null
	var src_pos: Vector2i = Inserter.source_tile(ins)
	var dst_pos: Vector2i = Inserter.dest_tile(ins)
	if not world.place_building(Buildings.Type.CHEST, src_pos, Belt.DIR_E):
		_check(failures, false, "%s SETUP: source chest placement at %s failed" % [label, str(src_pos)])
		return null
	if not world.place_building(Buildings.Type.CHEST, dst_pos, Belt.DIR_E):
		_check(failures, false, "%s SETUP: dest chest placement at %s failed" % [label, str(dst_pos)])
		return null
	return ins

## Windmill + pole + electric inserter + source/dest chests, all inside the
## stone patch painted by _make_world. `stocked` decides whether the source
## chest starts with items (mid-swing case) or empty (idle case).
## Returns the world, or null after appending a setup failure.
static func _build_powered_world(parent: Node, stocked: bool, failures: Array, label: String):
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.WINDMILL, WINDMILL_POS):
		_check(failures, false, "%s SETUP: windmill placement at %s failed" % [label, str(WINDMILL_POS)])
		_disconnect(world); world.queue_free()
		return null
	if not world.place_building(Buildings.Type.POWER_POLE, POLE_POS):
		_check(failures, false, "%s SETUP: power pole placement at %s failed" % [label, str(POLE_POS)])
		_disconnect(world); world.queue_free()
		return null
	var ins: Building = _place_electric_with_chests(world, ELEC_INS_POS, failures, label)
	if ins == null:
		_disconnect(world); world.queue_free()
		return null
	if stocked:
		var src_chest: Building = world.building_at(Inserter.source_tile(ins))
		src_chest.state["bag"] = [[Items.Type.WHEAT, 3]]
	return world

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
