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
##   5. Brownout duration — at 0.5 satisfaction the swing takes twice as
##      long, and the item lands on a SPECIFIC tick (Task 6).
##   6. Brownout smoothness — cycle_progress strictly increases on every
##      single tick of the stretched swing (Task 6).
##   7. Fuel tiers unaffected — the satisfaction lookup must not leak into
##      the burner path (Task 6).
##
## Sub-cases 5 and 6 are a PAIR and neither is sufficient alone: correct
## duration proves the arithmetic, strictly-increasing progress proves the
## arm actually interpolates rather than stalling and then leaping. A
## stretched cycle that froze for four ticks and jumped on the fifth would
## satisfy sub-case 5 while feeling broken to the player.
##
## STATE_NO_POWER (the below-epsilon cutoff) is Task 7, not here.

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

# ---------------------------------------------------------------------------
# Task 6 (brownout) layout + expected numbers.
# ---------------------------------------------------------------------------

# Ballast that drags the network to EXACTLY 0.5 satisfaction. The windmill
# supplies 6 (Windmill.MAX_OUTPUT); the inserter under test draws 5; seven
# lamps at ElectricLamp.DEMAND = 1 each bring total demand to 12. 6/12 = 0.5.
#
# The ballast hangs off a SECOND pole at (9,11) — Chebyshev 3 from POLE_POS
# (9,8), which is exactly PowerNetwork.POLE_RANGE, so the two poles form ONE
# component and one satisfaction number covers both. A second pole rather
# than more lamps around the first because the first pole's 3x3 supply area
# is already full: the windmill footprint, the source chest and the inserter.
#
# LAMPS, not more electric inserters, on purpose — the world must hold
# exactly ONE inserter, so a timing failure can only come from the machine
# under test rather than from a neighbour competing for the same chests.
const BALLAST_POLE_POS: Vector2i = Vector2i(9, 11)
const BALLAST_LAMP_POS: Array = [
	Vector2i(8, 10), Vector2i(9, 10), Vector2i(10, 10),
	Vector2i(8, 11),                 Vector2i(10, 11),
	Vector2i(8, 12), Vector2i(9, 12),
]
const BROWNOUT_SAT: float = 0.5
const BROWNOUT_DEMAND: int = 12          # 5 (inserter) + 7 (lamps)
const FULL_POWER_SAT: float = 1.0

# Basic (burner) inserter for sub-case 7 — its own world, no power anywhere.
const BASIC_INS_POS: Vector2i = Vector2i(10, 10)

# Tick (1-based, counted from the first tick after setup) on which the FIRST
# item lands in the destination chest.
#
# Derivation — Inserter.tick advances exactly one step per tick:
#   tick 1       STATE_IDLE       -> _try_pickup succeeds, cycle_progress = 0.0
#   ticks 2..N   STATE_WORKING_OUT, cycle_progress += 1/effective_ticks
#   the tick whose cycle_progress reaches 0.5 performs the drop.
# So delivery lands on tick 1 + (number of increments needed to reach 0.5).
#   full power   (effective  5, inc 0.20): 1 +  3 =  4
#   brownout     (effective 10, inc 0.10): 1 +  5 =  6
#   basic burner (effective 20, inc 0.05): 1 + 11 = 12
# The burner number is 11 increments, not the algebraic 10: accumulating
# 0.05 ten times lands on 0.49999999999999994, one ULP short of 0.5, so the
# drop slips one tick. Recorded as the OBSERVED value on purpose — this
# constant is a regression pin for existing burner timing, not a derivation.
const DELIVERY_TICK_FULL_POWER: int = 4
const DELIVERY_TICK_BROWNOUT: int = 6
const DELIVERY_TICK_BASIC_BURNER: int = 12

# Upper bound on the "tick until the destination chest receives" loop. Well
# clear of every expected number above; a miss returns -1 promptly instead
# of hanging.
const DELIVERY_WATCH_TICKS: int = 40

# Sub-case 6 sampling window. 10 ticks covers the whole stretched swing —
# the pickup tick (0.0), five swing-out increments through the drop at 0.5,
# and four swing-in increments up to 0.9 — while stopping two ticks short of
# the cycle wrap at tick 12, where cycle_progress legitimately resets to 0.0.
#
# CAUTION on that margin: only ONE of those two ticks is real. Algebraically
# the wrap belongs on tick 11; it slips to 12 because tick 11 accumulates to
# 0.9999999999999999 < 1.0 — the same ULP artifact documented for the burner
# above. If the window is ever widened, or the effective tick count retuned,
# 6a will fail on a CORRECT implementation the moment the window crosses the
# wrap. Sub-case 5's exact `half_eff == 10` assertion fails first and more
# legibly, which is the intended tripwire.
const PROGRESS_SAMPLE_TICKS: int = 10

# Expected per-tick cycle_progress delta at 0.5 satisfaction (1/10) versus at
# full power (1/5). The tolerance is deliberately far smaller than the gap
# between the two, so a full-power increment can never satisfy the brownout
# assertion by slipping inside the band.
#
# 6b silently assumes an EVEN effective tick count, so the drop's clamp to
# exactly 0.5 (inserter.gd, WORKING_OUT arm) lands on a tick boundary and
# yields a full increment. At an odd count it does not: at satisfaction 0.3
# (17 ticks) the swing-out reaches 0.4706 and clamps to 0.5 — a delta of
# 0.0294, roughly a third of a step, which fails 6b while 6a still passes.
# Retuning BROWNOUT_SAT to anything yielding an odd count needs this band
# reconsidered, not just the constants edited.
const BROWNOUT_INC: float = 0.1
const FULL_POWER_INC: float = 0.2
const INC_TOLERANCE: float = 0.02

static func test_name() -> String:
	return "electric inserter (registry + tables + no-fuel path + constant power demand + brownout scaling)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_registry_and_tables(parent, failures)
	_case_existing_tier_regression(parent, failures)
	_case_no_fuel_path(parent, failures)
	_case_constant_demand(parent, failures)
	_case_brownout_duration(parent, failures)
	_case_brownout_smooth_progress(parent, failures)
	_case_fuel_tier_unaffected(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "7 sub-cases pass: registry/tables + existing-tier regression + no-fuel path + constant power demand + brownout duration + brownout smoothness + fuel tiers unaffected" }
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
#
# BOTH halves run on a fully POWERED world. Task 5 wrote them on a bare
# world with no network at all, which was harmless while satisfaction had no
# consequence; Task 6 made it fatal. An unpowered electric inserter now
# reports satisfaction 0.0, stretches to ceil(5 / POWER_EPSILON) = 100 ticks,
# and moves nothing inside TRANSPORT_TICKS — so 3a's "it must actually work"
# assertion would fail for a reason that has nothing to do with fuel.
# Powering the rig keeps each sub-case testing ONE thing: 3 is about the fuel
# path, 5-6 are about the brownout. It is also forward-proof for Task 7,
# where an unpowered electric inserter will park in STATE_NO_POWER outright.
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
	# Powered rig, source chest stocked with WHEAT — not a fuel item. Nothing
	# in this world is burnable (windmill, pole, two chests, the inserter),
	# and the fuel port tile (FUEL_PORT_DIR = S, rotated by dir=E -> (10,10))
	# is empty, so there is no refuel path even if one were attempted.
	var world = _build_powered_world(parent, true, failures, "(3a)")
	if world == null:
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(3a) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	# Sub-case 3 runs on the powered rig (a bare world would stretch the cycle
	# to the POWER_EPSILON floor and deliver nothing inside the budget). Pin
	# the premise, so layout drift reports itself as a power-setup problem
	# rather than masquerading as a fuel failure below.
	_verified_satisfaction(world, failures, "(3a)", FULL_POWER_SAT, ELECTRIC_DEMAND)
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
		"(3a) unFUELLED (but powered) electric inserter should still transport items, delivered %d" % delivered)
	_check(failures, int(ins.state.get("fuel_buffer", 0)) == 0,
		"(3a) fuel_buffer must stay 0 (never topped up), got %d" % int(ins.state.get("fuel_buffer", 0)))
	_disconnect(world); world.queue_free()

	# --- 3b: sentinel fuel must not be consumed ---
	var world2 = _build_powered_world(parent, true, failures, "(3b)")
	if world2 == null:
		return
	var ins2: Building = world2.building_at(ELEC_INS_POS)
	if ins2 == null:
		_check(failures, false, "(3b) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world2); world2.queue_free()
		return
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

# ===========================================================================
# (5) BROWNOUT — CORRECT DURATION.
# Under partial power the electric tier slows PROPORTIONALLY:
#
#   effective_cycle_ticks = ceil(cycle_ticks(b) / max(POWER_EPSILON, sat))
#
# At satisfaction 0.5 the 5-tick cycle becomes 10 ticks, so the swing takes
# twice as long. Asserted as a SPECIFIC delivery tick, never "eventually" —
# an "eventually" assertion passes just as happily at full speed.
#
# Two worlds, identical except for the seven ballast lamps, so the only
# variable between the control and the measurement is network satisfaction.
# Both worlds' satisfaction is VERIFIED against supply and demand before
# anything is timed: a brownout test built on an unverified satisfaction
# value proves nothing at all.
# ===========================================================================
static func _case_brownout_duration(parent: Node, failures: Array) -> void:
	# --- control: fully satisfied network, unstretched 5-tick cycle ---
	var full_world = _build_powered_world(parent, true, failures, "(5-full)")
	if full_world == null:
		return
	var full_ins: Building = full_world.building_at(ELEC_INS_POS)
	if full_ins == null:
		_check(failures, false, "(5) SETUP: no electric inserter at %s in the full-power world" % str(ELEC_INS_POS))
		_disconnect(full_world); full_world.queue_free()
		return
	var full_sat: float = _verified_satisfaction(full_world, failures, "(5-full)", FULL_POWER_SAT, ELECTRIC_DEMAND)
	var full_eff: int = Inserter.effective_cycle_ticks(full_ins, full_world)
	_check(failures, full_eff == 5,
		"(5) CONTROL: effective_cycle_ticks at satisfaction %.3f should be 5 (unstretched), got %d" % [full_sat, full_eff])
	var full_tick: int = _first_delivery_tick(full_world, full_ins, DELIVERY_WATCH_TICKS)
	_check(failures, full_tick == DELIVERY_TICK_FULL_POWER,
		"(5) CONTROL: at full power the first item should land on tick %d, landed on tick %d (-1 = never within %d ticks)"
			% [DELIVERY_TICK_FULL_POWER, full_tick, DELIVERY_WATCH_TICKS])
	_disconnect(full_world); full_world.queue_free()

	# --- measurement: half-satisfied network, stretched 10-tick cycle ---
	var half_world = _build_brownout_world(parent, failures, "(5-half)")
	if half_world == null:
		return
	var half_ins: Building = half_world.building_at(ELEC_INS_POS)
	if half_ins == null:
		_check(failures, false, "(5) SETUP: no electric inserter at %s in the brownout world" % str(ELEC_INS_POS))
		_disconnect(half_world); half_world.queue_free()
		return
	var half_sat: float = _verified_satisfaction(half_world, failures, "(5-half)", BROWNOUT_SAT, BROWNOUT_DEMAND)
	var half_eff: int = Inserter.effective_cycle_ticks(half_ins, half_world)
	_check(failures, half_eff == 10,
		"(5) effective_cycle_ticks at satisfaction %.3f should be 10 (ceil(5 / 0.5)), got %d" % [half_sat, half_eff])
	var half_tick: int = _first_delivery_tick(half_world, half_ins, DELIVERY_WATCH_TICKS)
	_check(failures, half_tick == DELIVERY_TICK_BROWNOUT,
		"(5) at satisfaction %.3f the first item should land on tick %d (a 10-tick cycle), landed on tick %d — tick %d would mean the inserter ignored the brownout and ran at full speed"
			% [half_sat, DELIVERY_TICK_BROWNOUT, half_tick, DELIVERY_TICK_FULL_POWER])
	_disconnect(half_world); half_world.queue_free()

# ===========================================================================
# (6) BROWNOUT — STRICTLY-INCREASING PROGRESS.
# The feel assertion. Sub-case 5 proves the stretched cycle takes the right
# NUMBER of ticks; it says nothing about how the arm gets there. An
# implementation that stalled cycle_progress for four ticks and then leaped
# by a full-power increment on the fifth would deliver on exactly the same
# tick and pass sub-case 5 — while rendering an arm that twitches instead of
# sweeping. So: sample cycle_progress after EVERY tick of a stretched swing
# and require that it advance on every single one of them, by the STRETCHED
# increment rather than the full-power one.
#
# Both assertions print the whole sampled sequence on failure. If this ever
# breaks, the sequence is the diagnosis — a run of repeated values means a
# stall, a 0.2 step means the satisfaction scaling never reached `inc`.
# ===========================================================================
static func _case_brownout_smooth_progress(parent: Node, failures: Array) -> void:
	var world = _build_brownout_world(parent, failures, "(6)")
	if world == null:
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(6) SETUP: no electric inserter at %s in the brownout world" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	var sat: float = _verified_satisfaction(world, failures, "(6)", BROWNOUT_SAT, BROWNOUT_DEMAND)

	# Sample AFTER each tick: seq[i] is cycle_progress once tick i+1 has run.
	var seq: Array = []
	for _i in PROGRESS_SAMPLE_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		seq.append(float(ins.state.get("cycle_progress", -1.0)))
	var shown: String = _fmt_seq(seq)

	# (6a) STRICTLY increasing — every adjacent pair, no exceptions.
	var stall: String = ""
	for i in range(1, seq.size()):
		if float(seq[i]) <= float(seq[i - 1]):
			stall = "tick %d failed to advance (%.6f -> %.6f)" % [i + 1, float(seq[i - 1]), float(seq[i])]
			break
	_check(failures, stall == "",
		"(6) cycle_progress must STRICTLY increase on EVERY tick of a brownout swing — %s. Sampled sequence over %d ticks at satisfaction %.3f: %s"
			% [stall, PROGRESS_SAMPLE_TICKS, sat, shown])

	# (6b) Every step is the STRETCHED increment, never the full-power one.
	var bad: String = ""
	for i in range(1, seq.size()):
		var d: float = float(seq[i]) - float(seq[i - 1])
		if absf(d - BROWNOUT_INC) > INC_TOLERANCE:
			bad = "tick %d advanced by %.6f" % [i + 1, d]
			break
	_check(failures, bad == "",
		"(6) every brownout tick should advance cycle_progress by ~%.3f (1/10), never ~%.3f (1/5, the full-power step) — %s. Sampled sequence over %d ticks at satisfaction %.3f: %s"
			% [BROWNOUT_INC, FULL_POWER_INC, bad, PROGRESS_SAMPLE_TICKS, sat, shown])
	_disconnect(world); world.queue_free()

# ===========================================================================
# (7) FUEL TIERS UNAFFECTED.
# The satisfaction lookup must apply to electric tiers ONLY. This world has
# no windmill, no pole and no lamp, so power_satisfaction_at reports 0.0
# everywhere in it. If the lookup leaked into the burner path the divisor
# would fall back to POWER_EPSILON and a basic inserter would crawl at
# ceil(20 / 0.05) = 400 ticks — every burner inserter in the game frozen by
# a feature that was never meant to touch them.
#
# Asserted twice over: the arithmetic (effective == cycle_ticks == 20) and
# the behaviour (the item still lands on the pre-Task-6 tick).
# ===========================================================================
static func _case_fuel_tier_unaffected(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var basic: Building = _place_inserter_with_chests(world, Buildings.Type.INSERTER, BASIC_INS_POS, failures, "(7)")
	if basic == null:
		_disconnect(world); world.queue_free()
		return

	# SETUP sanity: an unpowered world really does report 0.0, so the
	# assertions below are exercising the guard rather than a lucky 1.0.
	var sat_here: float = world.power_satisfaction_at(BASIC_INS_POS)
	_check(failures, sat_here == 0.0,
		"(7) SETUP: a world with no power network should report satisfaction 0.0 at %s, got %.6f" % [str(BASIC_INS_POS), sat_here])

	var eff: int = Inserter.effective_cycle_ticks(basic, world)
	_check(failures, eff == 20,
		"(7) a BURNER tier must ignore power satisfaction entirely: effective_cycle_ticks(basic) should be 20, got %d (400 would mean the POWER_EPSILON divisor leaked into the fuel path)" % eff)
	_check(failures, eff == Inserter.cycle_ticks(basic),
		"(7) effective_cycle_ticks(basic) should equal cycle_ticks(basic) exactly, got %d vs %d" % [eff, Inserter.cycle_ticks(basic)])

	# Behavioural half. Fuel poked straight into state (same trick as 3b) so
	# the run is about timing, not about the refuel path.
	basic.state["fuel_buffer"] = FUEL_SENTINEL
	basic.state["fuel_burn_progress"] = 0
	var src: Building = world.building_at(Inserter.source_tile(basic))
	src.state["bag"] = [[Items.Type.WHEAT, 3]]
	var got: int = _first_delivery_tick(world, basic, DELIVERY_WATCH_TICKS)
	_check(failures, got == DELIVERY_TICK_BASIC_BURNER,
		"(7) an unpowered basic inserter should still deliver on tick %d (its unchanged 20-tick cycle), landed on tick %d (-1 = never within %d ticks)"
			% [DELIVERY_TICK_BASIC_BURNER, got, DELIVERY_WATCH_TICKS])
	_disconnect(world); world.queue_free()

# ---------- helpers (house style, copied from test_inserter.gd) ----------

## Place an electric inserter at `pos` facing east, with chests on its
## source and destination tiles (asked for via Inserter.source_tile /
## dest_tile rather than hardcoded offsets). Returns the inserter Building,
## or null after appending a setup failure.
static func _place_electric_with_chests(world, pos: Vector2i, failures: Array, label: String) -> Building:
	return _place_inserter_with_chests(world, Buildings.Type.ELECTRIC_INSERTER, pos, failures, label)

## Tier-parameterised form of the above — sub-case 7 needs a BURNER-tier
## inserter with the same chest rig. The electric helper delegates here so
## there is one placement path, and its call sites stay untouched.
static func _place_inserter_with_chests(world, b_type: int, pos: Vector2i, failures: Array, label: String) -> Building:
	if not world.place_building(b_type, pos, Belt.DIR_E):
		_check(failures, false, "%s SETUP: inserter (type %d) placement at %s failed" % [label, b_type, str(pos)])
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

## _build_powered_world plus the ballast that halves satisfaction: a second
## pole (in range of the first, so one component) and seven lamps hanging off
## it. Supply stays at one windmill's 6; demand rises from 5 to 12.
## Returns the world, or null after appending a setup failure.
static func _build_brownout_world(parent: Node, failures: Array, label: String):
	var world = _build_powered_world(parent, true, failures, label)
	if world == null:
		return null
	if not world.place_building(Buildings.Type.POWER_POLE, BALLAST_POLE_POS):
		_check(failures, false, "%s SETUP: ballast pole placement at %s failed" % [label, str(BALLAST_POLE_POS)])
		_disconnect(world); world.queue_free()
		return null
	for lamp_pos in BALLAST_LAMP_POS:
		if not world.place_building(Buildings.Type.ELECTRIC_LAMP, lamp_pos):
			_check(failures, false, "%s SETUP: ballast lamp placement at %s failed" % [label, str(lamp_pos)])
			_disconnect(world); world.queue_free()
			return null
	return world

## Recompute the network and confirm it is the scenario the caller thinks it
## is BEFORE anything is timed against it. Returns the measured satisfaction
## (or -1.0 if the pole is not in a network at all).
##
## Supply and demand are asserted alongside satisfaction so a layout drift —
## a lamp landing outside SUPPLY_RADIUS, the ballast pole falling out of
## POLE_RANGE — is diagnosed as the wrong number rather than as a mysterious
## timing failure several assertions later.
static func _verified_satisfaction(world, failures: Array, label: String, want_sat: float, want_demand: int) -> float:
	PowerNetwork.update_supply_demand(world)
	var comp: int = PowerNetwork.network_id_at(world, POLE_POS)
	if comp < 0:
		_check(failures, false, "%s SETUP: pole at %s is not in a power network" % [label, str(POLE_POS)])
		return -1.0
	var supply: int = PowerNetwork.supply_for(world, comp)
	var demand: int = PowerNetwork.demand_for(world, comp)
	var sat: float = PowerNetwork.satisfaction_for(world, comp)
	_check(failures, supply == Windmill.MAX_OUTPUT,
		"%s SETUP: component supply should be %d (one windmill), got %d" % [label, Windmill.MAX_OUTPUT, supply])
	_check(failures, demand == want_demand,
		"%s SETUP: component demand should be %d, got %d" % [label, want_demand, demand])
	_check(failures, is_equal_approx(sat, want_sat),
		"%s SETUP: satisfaction should be %.3f (supply %d / demand %d), got %.6f — a brownout assertion built on an unverified satisfaction proves nothing" % [label, want_sat, supply, demand, sat])
	return sat

## Drive ticks and report the 1-based tick on which the destination chest
## FIRST holds a wheat item, or -1 if that never happened within max_ticks.
static func _first_delivery_tick(world, ins: Building, max_ticks: int) -> int:
	var dst: Building = world.building_at(Inserter.dest_tile(ins))
	if dst == null:
		return -1
	for i in range(1, max_ticks + 1):
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if _bag_count(dst.state.get("bag", []), Items.Type.WHEAT) > 0:
			return i
	return -1

## Render a sampled cycle_progress sequence for a failure message. Full
## six-decimal precision on purpose — the point of printing the sequence is
## to see stalls and oversized steps, and %.2f would hide both.
static func _fmt_seq(seq: Array) -> String:
	var parts: Array = []
	for v in seq:
		parts.append("%.6f" % float(v))
	return "[" + ", ".join(parts) + "]"

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
