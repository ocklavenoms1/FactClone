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
##   8. STATE_NO_POWER stalls and HOLDS — the item in hand survives the
##      outage, nothing is delivered (Task 7).
##   9. THE FREEZE TEST — a long MID-SWING outage followed by restored power
##      must RESUME and DELIVER, with the item AND the swing position intact
##      and no item destroyed anywhere in the rig (Task 7).
##  10. The epsilon boundary — satisfaction EXACTLY POWER_EPSILON stalls
##      (the `<=` decision), one notch above it does not (Task 7).
##  11. ceil() coverage — the rounding mode is asserted at satisfactions no
##      integer supply/demand pair produces (Task 7).
##  12. Stale-status + vestigial-fuel + rated-vs-effective display
##      regressions (Task 7 items B / C / D).
##  13. THE FILTER GATES PICKUP — the filtered type moves, the other type is
##      never touched and never even held (Task 8).
##  14. Panel filter UI against the TWO-slot electric layout: geometry,
##      drop-to-set, right-click-to-clear (Task 8).
##  15. Panel routing — main.gd sends this tier to FastInserterPanel (Task 8).
##  16. Supply-area boundary — Chebyshev 1 runs, Chebyshev 2 stalls (Task 8).
##  17. Save round-trip of a MID-SWING inserter with a filter set (Task 8).
##
## Sub-cases 5 and 6 are a PAIR and neither is sufficient alone: correct
## duration proves the arithmetic, strictly-increasing progress proves the
## arm actually interpolates rather than stalling and then leaping. A
## stretched cycle that froze for four ticks and jumped on the fifth would
## satisfy sub-case 5 while feeling broken to the player.
##
## Sub-cases 8 and 9 are the same kind of pair. 8 proves the machine STOPS
## correctly; 9 proves it can ever START again. 8 passes just as happily on
## an inserter that is permanently frozen, which is the specific failure
## mode Task 7 was most at risk of introducing — see 9's own header.

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

# ---------------------------------------------------------------------------
# Task 7 (STATE_NO_POWER) layout + expected numbers.
# ---------------------------------------------------------------------------

# Sub-case 8's stall window. 120 ticks is 24x the electric tier's 5-tick
# cycle and comfortably past the 100-tick POWER_EPSILON worst case, so an
# inserter that merely CRAWLED instead of stopping would have completed a
# cycle and delivered inside it.
const NO_POWER_STALL_TICKS: int = 120

# Sub-case 9's outage length. Deliberately far past every plausible cycle:
# the epsilon-floor worst case is 100 ticks, so 320 is over three full
# worst-case cycles. Nothing about a correct implementation cares how long
# the outage runs; the number is large so that a "it eventually times out
# and recovers on its own" implementation cannot pass by accident.
const FREEZE_TICKS: int = 320

# Ticks allowed for the post-restoration delivery in sub-case 9. The resume
# lands mid-swing (the arm kept its item and its progress), so the first
# delivery arrives within a few ticks; 40 is a wide margin that still
# reports -1 promptly rather than hanging.
const RESUME_WATCH_TICKS: int = 40

# Powered ticks run BEFORE the outage in sub-case 9, so that the outage is
# taken MID-SWING rather than at the cycle boundary. Derived, then VERIFIED
# by the sub-case itself rather than trusted:
#   tick 1   STATE_IDLE      -> pickup, cycle_progress = 0.0, WORKING_OUT
#   tick 2   WORKING_OUT     -> progress 0.0 + 1/5 = 0.2
#   tick 3   WORKING_OUT     -> progress 0.4
#   tick 4   progress would reach 0.6, clamps to 0.5, and DROPS
# So 3 is the last tick that leaves the arm strictly between "just picked
# up" and "already delivered". Observed value: 0.4.
#
# The assertion checks the BAND (0.0, 0.5), not the exact 0.4: what this
# sub-case needs is that progress is nonzero, and pinning the number would
# duplicate sub-case 5's timing assertion for no extra coverage.
const PRE_OUTAGE_TICKS: int = 3

# WHEAT seeded into the source chest by _build_powered_world(stocked=true).
# Named because sub-case 9's conservation assertion counts against it — the
# helper and the expectation must not be able to drift apart.
const SEEDED_WHEAT: int = 3

# --- Sub-case 10: a network sitting EXACTLY on POWER_EPSILON. -------------
#
# Integer supply over integer demand cannot land on 0.05 at any sane scale:
# the smallest generator supplies 6 (Windmill.MAX_OUTPUT), so 6/120 needs
# 115 ballast lamps and about fifteen poles. An ACCUMULATOR gets there in
# three buildings, because accumulator discharge is the one FLOAT term in
# PowerNetwork's supply arithmetic (power_network.gd Stage 2/3):
#
#   raw_supply      0     (no generator in this world at all)
#   demand          5     (the inserter, and nothing else)
#   deficit         5     -> the single accumulator discharges
#   discharged      min(deficit 5.0, MAX_DISCHARGE_RATE 5, charge 0.25) = 0.25
#   satisfaction    0.25 / 5 = 0.05   ← exactly POWER_EPSILON
#
# 0.25 and 5 are both exactly representable, and IEEE division is correctly
# rounded, so the quotient is the same double as the literal 0.05 — the
# assertion below can and does use exact equality.
#
# The accumulator must be CARDINALLY adjacent to the pole (accumulators use
# _adjacent_component_id, not the consumer supply radius). (8,8) touches the
# pole at (9,8) and is inside the stone patch. There is no windmill in this
# world, so the windmill's usual footprint cells are free.
const EPS_ACC_POS: Vector2i = Vector2i(8, 8)

# Charge that lands satisfaction exactly ON the epsilon boundary, and the
# charge that lands it just above. 0.30 / 5 = 0.06 = 1.2x epsilon — close
# enough that the pair pins the comparison as `<=` rather than `<`, and far
# enough that no rounding argument is needed to tell them apart.
const EPS_CHARGE_AT: float = 0.25
const EPS_CHARGE_ABOVE: float = 0.30

# --- Sub-case 11: satisfactions no real network can produce. -------------
# [satisfaction, expected effective ticks] for the electric tier's 5-tick
# rating. Two of the rows discriminate a rounding mode; the other three pin
# claims made in prose elsewhere:
#
#   1.00 ->   5   integral control. All three modes agree.
#   0.30 ->  17   5/0.3 = 16.67. ceil 17, round 17, FLOOR 16.   ← discriminates
#   0.45 ->  12   5/0.45 = 11.11. ceil 12, ROUND 11, FLOOR 11.  ← discriminates
#   0.05 -> 100   POWER_EPSILON's documented worst case, asserted rather than
#                 assumed. (5.0 / 0.05 lands on exactly 100.0 in doubles, so
#                 this row does NOT tell the rounding modes apart — it pins
#                 the number, which is a different job.)
#   0.00 -> 100   the maxf(POWER_EPSILON, sat) divisor floor doing its one job:
#                 without it this is a division by zero.
#
# The 0.45 row is the load-bearing one — it is the only row that separates
# ceil from round. Both satisfactions this file can build from real buildings
# are integral ratios (5/1.0 and 5/0.5), so before these rows ceil, round and
# floor were literally indistinguishable, while POWER_EPSILON's docstring
# staked its 100-tick worst-case claim on ceil. Verified to bite: with `ceil`
# temporarily swapped for `floor`, the 0.30 and 0.45 rows fail (16 and 11).
const CEIL_CASES: Array = [
	[1.00, 5],
	[0.30, 17],
	[0.45, 12],
	[0.05, 100],
	[0.00, 100],
]

# --- Sub-case 12c: the rated-vs-effective cycle line. --------------------
# At BROWNOUT_SAT the electric tier's 5-tick rating stretches to 10 ticks.
# Q-inspect must report the 0.50s the arm ACTUALLY takes, and name the
# 0.25s rating alongside it so the brownout is diagnosable rather than
# mysterious. PAUSE 1 asks a human to confirm "visibly slower" against
# exactly this text, so a line that still claimed 0.25s would turn a
# correct implementation into a failed gate.
const BROWNOUT_CYCLE_TEXT: String = "0.50s"
const RATED_CYCLE_TEXT: String = "rated 0.25s"

# ---------------------------------------------------------------------------
# Task 8 (panel wiring + the filter proven end to end) layout + numbers.
# ---------------------------------------------------------------------------

# Sub-case 13's source-chest stock. Two DIFFERENT counts so a mixed-up
# assertion reads as the wrong number rather than as a coincidence, and the
# DECOY is listed FIRST in the bag on purpose: _pickup_from_chest scans the
# bag in order, so an inserter that ignored its filter reaches for the flax
# on its very first cycle. A wheat-first bag would let a broken filter pass
# three cycles in a row before it ever picked anything wrong.
const FILTER_TARGET_COUNT: int = 3      # WHEAT — the filtered type
const FILTER_DECOY_COUNT: int = 4       # FLAX  — must never be touched

# Ticks for sub-case 13's transport run. Roughly 7 ticks per item at full
# power (1 IDLE pickup tick + a 5-tick cycle + slop), so three wheat need
# about 21. 60 is a wide margin that still ends with the arm idle and the
# flax filtered out, rather than mid-swing.
const FILTER_RUN_TICKS: int = 60

# Sub-case 14 geometry. FILTER_ROW_Y is the filter slot's y-offset inside
# the panel's top area (fast_inserter_panel.gd _slot_y_offsets), and
# FACING_LINE_INSET is where InserterPanel anchors its facing line relative
# to the BOTTOM of that area (inserter_panel.gd draws at area.size.y - 40).
# Both are re-derived from the live panel in the assertions — named here so
# the failure text can say what the numbers mean.
const FILTER_ROW_Y: float = 240.0
const FACING_LINE_INSET: float = 40.0

# Cursor stack size for the drop-to-set test. Greater than 1 on purpose:
# "the cursor is NOT consumed" is then a claim about the whole stack rather
# than about a single item that could have been silently replaced.
const DROP_FILTER_COUNT: int = 4

# Sub-case 15: main.gd's panel dispatch, pinned by a static file scan.
# Main._try_open_building_ui is an instance method on a node that needs the
# whole scene tree (@onready panel refs, grid_world, player) to construct,
# so the arm is read out of the source the same way test_building_ui_4.gd
# reads the processor panels for its reuse audit. What this can and cannot
# prove is spelled out in the sub-case header.
const MAIN_SRC_PATH: String = "res://scripts/main.gd"
const ROUTING_ARM_LABEL: String = "Buildings.Type.ELECTRIC_INSERTER:"
const ROUTING_ARM_BODY: String = "fast_inserter_panel.open(b, grid_world)"

# Sub-case 16: a SECOND electric inserter, one ring OUTSIDE the pole's
# supply area. Chebyshev 2 from POLE_POS (9,8), inside the stone patch
# painted by _make_world, and clear of every building _build_powered_world
# places. Its own source/dest chests land at (10,10) and (12,10), also free.
const FAR_INS_POS: Vector2i = Vector2i(11, 10)

# Ticks for sub-case 16. Same budget as sub-case 13, so "the far one
# delivered nothing" is a statement about a machine that had every chance.
const SUPPLY_RUN_TICKS: int = 60

# Sub-case 17. Distinct filename from test_inserter.gd's TEST_SAVE_PATH so
# the two round-trip tests cannot collide if the runner order ever changes.
const TEST_SAVE_PATH: String = "user://test_electric_inserter.json"

# Tolerance for the round-tripped cycle_progress. JSON is TEXT: the float is
# formatted on write and parsed back on read, and neither step is
# contractually bit-exact, so an exact == would assert something SaveSystem
# never promised. 1e-4 is three orders of magnitude tighter than the
# electric tier's 0.2 per-tick step, so a progress that was actually lost or
# reset to zero cannot hide inside the band.
const CYCLE_PROGRESS_TOL: float = 0.0001

## Duck-typed stand-in for GridWorld that reports a satisfaction of the
## test's choosing. `world` is untyped all the way through PowerNetwork and
## Inserter (see power_network.gd's "world is intentionally untyped" note),
## and effective_cycle_ticks calls exactly one method on it, so a two-line
## RefCounted is a complete implementation of the interface under test.
##
## Used ONLY for pure arithmetic. Anything about behaviour is asserted
## against a real GridWorld with real poles, because a stub cannot tell you
## whether the machine is wired to the network correctly.
class StubPowerWorld extends RefCounted:
	var sat: float = 1.0
	func _init(s: float) -> void:
		sat = s
	func power_satisfaction_at(_pos: Vector2i) -> float:
		return sat

static func test_name() -> String:
	return "electric inserter (registry + tables + no-fuel path + constant power demand + brownout scaling + STATE_NO_POWER + filter end-to-end + panel wiring + supply area + save)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_registry_and_tables(parent, failures)
	_case_existing_tier_regression(parent, failures)
	_case_no_fuel_path(parent, failures)
	_case_constant_demand(parent, failures)
	_case_brownout_duration(parent, failures)
	_case_brownout_smooth_progress(parent, failures)
	_case_fuel_tier_unaffected(parent, failures)
	_case_no_power_stall_and_hold(parent, failures)
	_case_no_power_resumes_after_long_outage(parent, failures)
	_case_epsilon_boundary(parent, failures)
	_case_ceil_rounding(parent, failures)
	_case_status_and_display_regressions(parent, failures)
	_case_filter_gates_pickup(parent, failures)
	_case_panel_filter_ui(parent, failures)
	_case_panel_routing(failures)
	_case_supply_area_boundary(parent, failures)
	_case_save_roundtrip(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "17 sub-cases pass: registry/tables + existing-tier regression + no-fuel path + constant power demand + brownout duration + brownout smoothness + fuel tiers unaffected + no-power stall/hold + resume after long outage + epsilon boundary + ceil rounding + status/display regressions + filter gates pickup + panel filter UI + panel routing + supply-area boundary + save round-trip" }
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

# ===========================================================================
# (8) NO POWER — STALLS AND HOLDS.
# The electric-tier counterpart of the Session 4 Task 2 fuel-outage fix. An
# inserter whose network dies mid-swing must: park in STATE_NO_POWER, KEEP
# the item already in its hand, and deliver nothing at all until power comes
# back.
#
# "Delivers nothing" is asserted over a long window on purpose. Before Task 7
# an unpowered electric inserter did not stop — it crawled at the
# POWER_EPSILON floor of 100 ticks per cycle. A short window cannot tell a
# stall from a crawl; NO_POWER_STALL_TICKS is longer than that worst case, so
# a crawling implementation delivers inside it and fails here.
#
# The outage is produced by REMOVING THE POLE rather than by poking state:
# that is the move a player actually makes, and it exercises the real
# supply-area lookup (no pole within SUPPLY_RADIUS -> satisfaction 0.0)
# instead of a value the test invented.
# ===========================================================================
static func _case_no_power_stall_and_hold(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, true, failures, "(8)")
	if world == null:
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(8) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	_verified_satisfaction(world, failures, "(8)", FULL_POWER_SAT, ELECTRIC_DEMAND)

	# One powered tick puts an item in the hand (pickup lands on tick 1), so
	# the outage below is taken WITH something to lose — which is the point.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	var held_before: int = Inserter.held_item_type(ins)
	_check(failures, held_before >= 0,
		"(8) SETUP: the inserter should be holding an item after one powered tick, held %d — without an item in hand the conservation assertions below are vacuous" % held_before)

	_check(failures, world.remove_building_at(POLE_POS),
		"(8) SETUP: removing the pole at %s should succeed" % str(POLE_POS))

	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	var state_1: int = int(ins.state.get("state", -1))
	_check(failures, state_1 == Inserter.STATE_NO_POWER,
		"(8) the first unpowered tick should park the inserter in STATE_NO_POWER (%d), got %d" % [Inserter.STATE_NO_POWER, state_1])
	_check(failures, Inserter.held_item_type(ins) == held_before,
		"(8) the outage tick must return BEFORE touching held_item_buffer: held %d before the outage, %d after" % [held_before, Inserter.held_item_type(ins)])

	for _i in NO_POWER_STALL_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var state_n: int = int(ins.state.get("state", -1))
	_check(failures, state_n == Inserter.STATE_NO_POWER,
		"(8) after %d unpowered ticks the state should still be STATE_NO_POWER (%d), got %d" % [NO_POWER_STALL_TICKS, Inserter.STATE_NO_POWER, state_n])
	_check(failures, Inserter.held_item_type(ins) == held_before,
		"(8) after %d unpowered ticks the held item should still be %d, got %d — the item must survive the whole outage, not just its first tick" % [NO_POWER_STALL_TICKS, held_before, Inserter.held_item_type(ins)])
	var dst: Building = world.building_at(Inserter.dest_tile(ins))
	var delivered: int = _bag_count(dst.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, delivered == 0,
		"(8) an unpowered inserter must deliver NOTHING across %d ticks, delivered %d (a crawl at the %d-tick POWER_EPSILON floor would finish a cycle inside this window)"
			% [NO_POWER_STALL_TICKS, delivered, 100])
	_disconnect(world); world.queue_free()

# ===========================================================================
# (9) THE FREEZE TEST — RESUME AFTER A LONG MID-SWING OUTAGE.
# This sub-case enforces the whole "extend, don't add" rule for
# STATE_NO_POWER's place in tick()'s `match`. There are TWO wrong ways to
# spend that state and BOTH are silent, so there are two assertions:
#
#   UNNAMED  -> caught by the DELIVERY assertion.
#     tick()'s `match s:` has no `_:` default arm and nothing outside the
#     arms writes b.state["state"], so a NO_POWER value named in no arm
#     header matches nothing: tick() becomes a permanent no-op, the state
#     never changes again, and the machine stays frozen FOREVER — through
#     power restoration, through any number of ticks, with no error and no
#     visible difference from "still out of power".
#
#   OWN ARM  -> caught by the CONSERVATION assertion.
#     Only the STATE_IDLE/NO_FUEL/NO_POWER arm carries the Task 2 resume
#     guard, so an own arm re-creates the item-destruction bug: the item
#     held through the outage is overwritten by a fresh pickup out of the
#     source chest, and the inserter still DELIVERS on schedule. The
#     delivery assertion passes on it. The wheat total does not.
#
# Sub-case 8 catches neither: a permanently frozen inserter also holds its
# item and delivers nothing, and the stall arm never executes during an
# outage at all because tick() returns at the power check first.
#
# The outage is taken MID-SWING — PRE_OUTAGE_TICKS powered ticks first — so
# that cycle_progress is nonzero when power dies. That is the only way to
# test the swing-position half of what the NO_POWER write promises; an
# outage at the cycle boundary leaves progress at 0.0, where "preserved" and
# "reset" are the same number.
#
# Delivery is asserted, never a state change: a state change could be
# produced by an arm that transitions and then stalls somewhere else.
# ===========================================================================
static func _case_no_power_resumes_after_long_outage(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, true, failures, "(9)")
	if world == null:
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(9) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	_verified_satisfaction(world, failures, "(9)", FULL_POWER_SAT, ELECTRIC_DEMAND)

	# Run PRE_OUTAGE_TICKS powered ticks, so the outage is taken genuinely
	# MID-SWING: an item in hand AND cycle_progress strictly between the
	# pickup and the drop. Reached by TICKING to the state rather than by
	# poking it, the same way test_inserter_fuel_conservation.gd reaches its
	# own outage.
	for _i in PRE_OUTAGE_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var held_before: int = Inserter.held_item_type(ins)
	_check(failures, held_before >= 0,
		"(9) SETUP: the inserter should be holding an item after %d powered ticks, held %d" % [PRE_OUTAGE_TICKS, held_before])
	var progress_before: float = float(ins.state.get("cycle_progress", -1.0))
	_check(failures, progress_before > 0.0 and progress_before < 0.5,
		"(9) SETUP: the outage must be taken MID-SWING — cycle_progress after %d powered ticks should be strictly inside (0.0, 0.5), got %.6f. At 0.0 the swing-position half of the conservation claim goes untested (the IDLE arm sets progress to 0.0 on pickup, so a one-tick setup never leaves it) — at 0.5 or beyond the item has already been delivered"
			% [PRE_OUTAGE_TICKS, progress_before])
	var total_before: int = _rig_wheat_total(world, ins)
	_check(failures, total_before == SEEDED_WHEAT,
		"(9) SETUP: the rig should account for all %d seeded wheat (source chest + destination chest + the hand), counted %d — the conservation assertion below is only as good as this baseline" % [SEEDED_WHEAT, total_before])
	_check(failures, world.remove_building_at(POLE_POS),
		"(9) SETUP: removing the pole at %s should succeed" % str(POLE_POS))

	for _i in FREEZE_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var frozen_state: int = int(ins.state.get("state", -1))
	_check(failures, frozen_state == Inserter.STATE_NO_POWER,
		"(9) PREMISE: after %d unpowered ticks the inserter should be in STATE_NO_POWER (%d), got %d — the resume assertion below only means something if it was really stalled" % [FREEZE_TICKS, Inserter.STATE_NO_POWER, frozen_state])
	var dst_mid: Building = world.building_at(Inserter.dest_tile(ins))
	_check(failures, _bag_count(dst_mid.state.get("bag", []), Items.Type.WHEAT) == 0,
		"(9) PREMISE: nothing should have been delivered during the %d-tick outage" % FREEZE_TICKS)
	_check(failures, Inserter.held_item_type(ins) == held_before,
		"(9) the item in hand must survive the whole outage: held %d before, %d after %d unpowered ticks" % [held_before, Inserter.held_item_type(ins), FREEZE_TICKS])

	# SWING POSITION, not just the item. The stall write returns before
	# cycle_progress is assigned, so the arm resumes the SAME swing rather
	# than restarting it. Without this, an implementation that preserved the
	# held item but reset progress to 0.0 would satisfy every other assertion
	# in sub-cases 8 and 9 — the item would simply take a second trip.
	var progress_after: float = float(ins.state.get("cycle_progress", -1.0))
	_check(failures, is_equal_approx(progress_after, progress_before),
		"(9) the outage must leave cycle_progress UNTOUCHED: %.6f before, %.6f after %d unpowered ticks. The NO_POWER write in tick() has to return BEFORE cycle_progress is assigned, exactly as the NO_FUEL write does"
			% [progress_before, progress_after, FREEZE_TICKS])

	# Power comes back.
	_check(failures, world.place_building(Buildings.Type.POWER_POLE, POLE_POS),
		"(9) SETUP: re-placing the pole at %s should succeed" % str(POLE_POS))
	var resumed_tick: int = _first_delivery_tick(world, ins, RESUME_WATCH_TICKS)
	_check(failures, resumed_tick > 0,
		"(9) after power is restored the inserter MUST resume and DELIVER, got tick %d (-1 = never within %d ticks). -1 here almost certainly means STATE_NO_POWER is not named in any tick() match arm: that match has no `_:` default, so an unnamed state makes tick() a permanent no-op and the machine never recovers"
			% [resumed_tick, RESUME_WATCH_TICKS])

	# ITEM CONSERVATION — the OTHER half of the "extend, don't add" rule.
	# The delivery assertion above catches an UNNAMED state; it does not
	# catch NO_POWER being given its OWN arm, because an own arm without the
	# resume guard destroys the held item, picks a fresh one out of the
	# source chest, and delivers that instead. Same visible delivery, one
	# item short.
	var total_after: int = _rig_wheat_total(world, ins)
	_check(failures, total_after == total_before,
		"(9) ITEM CONSERVATION across the outage: %d wheat before, %d after (source chest + destination chest + the hand). A SHORTFALL here means the item held during the outage was destroyed and replaced by a fresh pickup — which is what happens when STATE_NO_POWER is given its OWN tick() arm instead of being added to the existing STATE_IDLE/STATE_NO_FUEL header, since only that arm carries the Task 2 resume guard"
			% [total_before, total_after])
	_disconnect(world); world.queue_free()

# ===========================================================================
# (10) THE EPSILON BOUNDARY.
# The cutoff is `sat <= POWER_EPSILON`, not `<`. That choice is not
# cosmetic: electric_lamp.gd draws its glow at `sat > 0.05`, so a lamp at
# EXACTLY 0.05 is dark. Matching the comparison makes the two consumers agree
# on the boundary, and a player watching the lamps die can read the exact
# moment the inserters give up.
#
# A consequence worth stating: this makes effective_cycle_ticks'
# maxf(POWER_EPSILON, sat) floor purely defensive. Anything at or below
# epsilon now stalls outright, so the 100-tick worst case is unreachable
# through tick() — only sub-case 11 can still observe it.
#
# Asserted from BOTH sides, because a one-sided boundary test cannot tell
# `<=` from `<`. See EPS_ACC_POS for how a real network is made to land
# exactly on 0.05 with three buildings.
# ===========================================================================
static func _case_epsilon_boundary(parent: Node, failures: Array) -> void:
	# --- ON the boundary: must stall ---
	var at_world = _build_epsilon_world(parent, EPS_CHARGE_AT, failures, "(10-at)")
	if at_world == null:
		return
	var at_ins: Building = at_world.building_at(ELEC_INS_POS)
	if at_ins == null:
		_check(failures, false, "(10-at) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(at_world); at_world.queue_free()
		return
	var at_sat: float = _epsilon_rig_satisfaction(at_world, failures, "(10-at)")
	_check(failures, at_sat == Inserter.POWER_EPSILON,
		"(10) SETUP: the rig must sit EXACTLY on the boundary — satisfaction should equal POWER_EPSILON (%.17f), got %.17f. A boundary test built on an unverified value proves nothing" % [Inserter.POWER_EPSILON, at_sat])
	# Ticked DIRECTLY rather than through TickSystem: the network pre-pass
	# drains the accumulator, so a signal-driven tick would spend the charge
	# and measure the tick AFTER the boundary instead of the one on it.
	Inserter.tick(at_ins, at_world)
	var at_state: int = int(at_ins.state.get("state", -1))
	_check(failures, at_state == Inserter.STATE_NO_POWER,
		"(10) at satisfaction EXACTLY POWER_EPSILON (%.6f) the inserter must stall — the cutoff is `sat <= POWER_EPSILON`, matching electric_lamp.gd's `sat > 0.05` for lit. Expected STATE_NO_POWER (%d), got %d"
			% [at_sat, Inserter.STATE_NO_POWER, at_state])
	_disconnect(at_world); at_world.queue_free()

	# --- one notch ABOVE: must NOT stall ---
	var up_world = _build_epsilon_world(parent, EPS_CHARGE_ABOVE, failures, "(10-above)")
	if up_world == null:
		return
	var up_ins: Building = up_world.building_at(ELEC_INS_POS)
	if up_ins == null:
		_check(failures, false, "(10-above) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(up_world); up_world.queue_free()
		return
	var up_sat: float = _epsilon_rig_satisfaction(up_world, failures, "(10-above)")
	_check(failures, up_sat > Inserter.POWER_EPSILON,
		"(10) SETUP: the above-boundary rig should report a satisfaction strictly above POWER_EPSILON (%.6f), got %.6f" % [Inserter.POWER_EPSILON, up_sat])
	Inserter.tick(up_ins, up_world)
	var up_state: int = int(up_ins.state.get("state", -1))
	_check(failures, up_state != Inserter.STATE_NO_POWER,
		"(10) at satisfaction %.6f — ABOVE POWER_EPSILON — the inserter must keep running (crawling, not stalling), got STATE_NO_POWER. A `<` boundary would be off by one notch in the other direction" % up_sat)
	_disconnect(up_world); up_world.queue_free()

# ===========================================================================
# (11) ceil() COVERAGE — THE ROUNDING MODE ITSELF.
# Gap found reviewing Task 6: both satisfactions this file could build from
# real buildings are integral ratios (5/1.0 = 5, 5/0.5 = 10), so ceil, round
# and floor were literally indistinguishable — while POWER_EPSILON's
# docstring stakes its 100-tick worst-case claim on ceil.
#
# `world` is duck-typed all the way down, so a stub closes the gap with no
# world at all. Pure arithmetic, no placement, no ticking: this sub-case is
# about the formula, and every behavioural claim in this file is still made
# against a real GridWorld.
# ===========================================================================
static func _case_ceil_rounding(_parent: Node, failures: Array) -> void:
	var b: Building = Inserter.make(Vector2i(0, 0), Belt.DIR_E, Buildings.Type.ELECTRIC_INSERTER)
	for row in CEIL_CASES:
		var sat: float = float(row[0])
		var want: int = int(row[1])
		var stub := StubPowerWorld.new(sat)
		var got: int = Inserter.effective_cycle_ticks(b, stub)
		_check(failures, got == want,
			"(11) effective_cycle_ticks at satisfaction %.2f should be %d (ceil(%d / max(%.2f, %.2f))), got %d — floor or round would land on a different number here, which is the whole point of this row"
				% [sat, want, Inserter.cycle_ticks(b), Inserter.POWER_EPSILON, sat, got])

# ===========================================================================
# (12) STATUS + DISPLAY REGRESSIONS (Task 7 items B, C, D).
# Three warts opened up by the same pass, each with its own player-visible
# symptom:
#
#   B  stale status. tick()'s IDLE/stall arm wrote b.state["state"] only
#      inside `if picked >= 0:`, so a machine that recovered but found its
#      source empty went on reporting the stall it recovered FROM, forever.
#   C  vestigial fuel. Inserter.make copies Burner state onto every tier and
#      info_lines appended Burner.info_lines unconditionally, so a healthy
#      ELECTRIC inserter — a tier with no fuel slot at all — reported
#      "Fuel: 0 / 16 units" and "Status: NO FUEL".
#   D  rated-vs-effective cycle. info_lines reported cycle_ticks(b), the
#      tier's RATING. Under brownout it claimed 0.25s while the arm took
#      0.50s. PAUSE 1 asks a human to confirm the slowdown against this
#      text, so the wart would have turned a correct implementation into a
#      failed gate.
# ===========================================================================
static func _case_status_and_display_regressions(parent: Node, failures: Array) -> void:
	# --- 12a (B): recovered + empty source must read IDLE, not the stall ---
	# Source chest deliberately EMPTY: the recovery tick therefore takes the
	# `picked < 0` path, which is the exact path that used to write nothing.
	var world = _build_powered_world(parent, false, failures, "(12a)")
	if world == null:
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(12a) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	_check(failures, world.remove_building_at(POLE_POS),
		"(12a) SETUP: removing the pole at %s should succeed" % str(POLE_POS))
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, int(ins.state.get("state", -1)) == Inserter.STATE_NO_POWER,
		"(12a) PREMISE: the unpowered inserter should be in STATE_NO_POWER (%d), got %d" % [Inserter.STATE_NO_POWER, int(ins.state.get("state", -1))])
	_check(failures, world.place_building(Buildings.Type.POWER_POLE, POLE_POS),
		"(12a) SETUP: re-placing the pole at %s should succeed" % str(POLE_POS))
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	var recovered: int = int(ins.state.get("state", -1))
	_check(failures, recovered == Inserter.STATE_IDLE,
		"(12a) a repowered inserter with an EMPTY source must report STATE_IDLE (%d), got %d — %d would mean the stall state is stale, written once and never cleared because the arm only assigns inside `if picked >= 0:`"
			% [Inserter.STATE_IDLE, recovered, Inserter.STATE_NO_POWER])

	# --- 12b (C): no fuel display on a tier that has no fuel slot ---
	var lines: Array = Inserter.info_lines(ins, world)
	var fuel_line: String = ""
	for line in lines:
		var text: String = str(line)
		if text.begins_with("Fuel:") or text.contains("NO FUEL"):
			fuel_line = text
			break
	_check(failures, fuel_line == "",
		"(12b) a healthy ELECTRIC inserter must show no fuel information at all — the tier has no fuel slot, and Inserter.make copies Burner state onto every tier so fuel_buffer is permanently 0. Found: \"%s\" in %s" % [fuel_line, str(lines)])
	_disconnect(world); world.queue_free()

	# --- 12c (D): the cycle line reports EFFECTIVE, and names the rating ---
	var bw = _build_brownout_world(parent, failures, "(12c)")
	if bw == null:
		return
	var bins: Building = bw.building_at(ELEC_INS_POS)
	if bins == null:
		_check(failures, false, "(12c) SETUP: no electric inserter at %s in the brownout world" % str(ELEC_INS_POS))
		_disconnect(bw); bw.queue_free()
		return
	_verified_satisfaction(bw, failures, "(12c)", BROWNOUT_SAT, BROWNOUT_DEMAND)
	var blines: Array = Inserter.info_lines(bins, bw)
	var cycle_line: String = ""
	for line in blines:
		if str(line).begins_with("Cycle:"):
			cycle_line = str(line)
			break
	_check(failures, cycle_line.contains(BROWNOUT_CYCLE_TEXT),
		"(12c) under brownout the Cycle line must report the EFFECTIVE %s the arm actually takes, got \"%s\"" % [BROWNOUT_CYCLE_TEXT, cycle_line])
	_check(failures, cycle_line.contains(RATED_CYCLE_TEXT),
		"(12c) the Cycle line must also name the tier's rating (\"%s\") so the brownout is diagnosable rather than mysterious, got \"%s\"" % [RATED_CYCLE_TEXT, cycle_line])
	_disconnect(bw); bw.queue_free()

# ===========================================================================
# (13) THE FILTER GATES PICKUP.
#
# The `filter` slot, the drop-to-set path and ItemPickerModal all arrived
# with QoL Cluster B and have only ever been exercised against
# FAST_INSERTER. The electric tier's slot_layout copies the filter slot
# verbatim — but that is a claim about DATA. This is the sub-case that turns
# it into a claim about BEHAVIOUR, and it is the one that matters: wiring a
# panel proves the row can be drawn, not that the filter does anything.
#
# Two independent assertions, and the FIRST is the load-bearing one:
#   - the arm NEVER HELD the unfiltered type on ANY tick of the run, and
#   - the end state (all wheat moved, all flax still in the source chest).
# An inserter that picked a flax up and put it straight back leaves the end
# state perfect while being exactly the bug worth catching, so the end state
# alone is not enough. The per-tick watch is what closes that hole.
# ===========================================================================
static func _case_filter_gates_pickup(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, false, failures, "(13)")
	if world == null:
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(13) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	var src: Building = world.building_at(Inserter.source_tile(ins))
	var dst: Building = world.building_at(Inserter.dest_tile(ins))
	if src == null or dst == null:
		_check(failures, false, "(13) SETUP: source and/or destination chest missing around %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	# Built with stocked=false so the bag is ours to shape — the helper's
	# single-type stock cannot express "two types, decoy first".
	src.state["bag"] = [[Items.Type.FLAX, FILTER_DECOY_COUNT], [Items.Type.WHEAT, FILTER_TARGET_COUNT]]
	ins.state["filter_item_type"] = Items.Type.WHEAT
	_verified_satisfaction(world, failures, "(13)", FULL_POWER_SAT, ELECTRIC_DEMAND)

	var flax_in_hand_ticks: int = 0
	for _i in FILTER_RUN_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if Inserter.held_item_type(ins) == Items.Type.FLAX:
			flax_in_hand_ticks += 1

	var dst_wheat: int = _bag_count(dst.state.get("bag", []), Items.Type.WHEAT)
	var dst_flax: int = _bag_count(dst.state.get("bag", []), Items.Type.FLAX)
	var src_wheat: int = _bag_count(src.state.get("bag", []), Items.Type.WHEAT)
	var src_flax: int = _bag_count(src.state.get("bag", []), Items.Type.FLAX)

	_check(failures, flax_in_hand_ticks == 0,
		"(13) the arm must NEVER hold the unfiltered type. Filter is WHEAT (type %d) yet the arm held FLAX (type %d) on %d of %d ticks — a pick-then-return leaves every chest total correct and is still the bug"
			% [Items.Type.WHEAT, Items.Type.FLAX, flax_in_hand_ticks, FILTER_RUN_TICKS])
	_check(failures, dst_wheat == FILTER_TARGET_COUNT,
		"(13) all %d filtered WHEAT should have reached the destination in %d ticks, it holds %d"
			% [FILTER_TARGET_COUNT, FILTER_RUN_TICKS, dst_wheat])
	_check(failures, dst_flax == 0,
		"(13) the destination must hold NO flax when the filter is set to WHEAT, it holds %d" % dst_flax)
	_check(failures, src_flax == FILTER_DECOY_COUNT,
		"(13) all %d unfiltered FLAX must remain UNTOUCHED in the source chest, %d are left"
			% [FILTER_DECOY_COUNT, src_flax])
	_check(failures, src_wheat == 0,
		"(13) the source chest should be out of WHEAT after the run, %d are left" % src_wheat)
	_disconnect(world); world.queue_free()

# ===========================================================================
# (14) PANEL FILTER UI ON THE TWO-SLOT ELECTRIC LAYOUT.
#
# FastInserterPanel was written for FAST_INSERTER's THREE slots (held_item +
# fuel + filter). The electric tier has TWO (held_item + filter, no fuel), so
# nothing about the layout transferring is obvious enough to assume.
#
# 14a is the geometry, 14b/14c are the two write paths (drop-to-set and
# right-click-to-clear) driven through the panel's own _gui_input rather than
# through the handler functions directly, so the hit test is exercised too —
# a filter row placed at the wrong y would still pass a direct handler call.
# 14d records WHY the routing goes to this panel and not the basic one.
# ===========================================================================
static func _case_panel_filter_ui(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.ELECTRIC_INSERTER, ELEC_INS_POS, Belt.DIR_E):
		_check(failures, false, "(14) SETUP: electric inserter placement at %s failed" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(14) SETUP: building_at(%s) returned null after a successful placement" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return

	var panel = preload("res://scripts/ui/fast_inserter_panel.gd").new()
	parent.add_child(panel)
	panel.cursor = CursorStack.new()
	panel.inventory = Inventory.new(8)
	panel.toast_callback = func(_msg): pass
	panel.open(ins, world)

	# --- 14a: the two-slot geometry -------------------------------------
	var by_id: Dictionary = _slot_rects_by_id(panel)
	_check(failures, by_id.size() == 2 and by_id.has("held_item") and by_id.has("filter"),
		"(14a) FastInserterPanel on the ELECTRIC tier should lay out exactly two slots (held_item + filter), got %s" % str(by_id.keys()))
	_check(failures, not by_id.has("fuel"),
		"(14a) the electric tier declares no fuel slot, so the panel must emit no fuel rect — _building_slot_rects drives off slot_layout_for(type), got %s" % str(by_id.keys()))
	if by_id.has("held_item") and by_id.has("filter"):
		var area: Rect2 = panel._top_area_rect()
		var held_r: Rect2 = by_id["held_item"]
		var filt_r: Rect2 = by_id["filter"]
		_check(failures, not held_r.intersects(filt_r),
			"(14a) the filter row must not collide with the held-item row, held=%s filter=%s" % [str(held_r), str(filt_r)])
		_check(failures, is_equal_approx(filt_r.position.y - area.position.y, FILTER_ROW_Y),
			"(14a) the filter row should sit at y+%.0f inside the top area exactly as it does on the FAST tier — slots are placed BY ID, so the missing fuel row must not move it. Got y+%.1f"
				% [FILTER_ROW_Y, filt_r.position.y - area.position.y])
		var facing_off: float = area.size.y - FACING_LINE_INSET
		_check(failures, filt_r.position.y + filt_r.size.y - area.position.y < facing_off,
			"(14a) the filter slot must end ABOVE InserterPanel's facing line. Slot bottom y+%.1f vs facing line y+%.1f"
				% [filt_r.position.y + filt_r.size.y - area.position.y, facing_off])

	# --- 14b: drop-to-set, through the real click path -------------------
	panel.cursor.pick(Items.Type.FLAX, DROP_FILTER_COUNT)
	_check(failures, _click_filter_slot(panel, MOUSE_BUTTON_LEFT),
		"(14b) SETUP: the panel emitted no filter rect to left-click on")
	_check(failures, int(ins.state.get("filter_item_type", -99)) == Items.Type.FLAX,
		"(14b) drop-to-set should copy the cursor's TYPE into filter_item_type (FLAX is type %d), got %d"
			% [Items.Type.FLAX, int(ins.state.get("filter_item_type", -99))])
	_check(failures, panel.cursor.has_item() and panel.cursor.item_type == Items.Type.FLAX and panel.cursor.count == DROP_FILTER_COUNT,
		"(14b) drop-to-set is a COPY, not a move — the cursor must still hold %d of type %d, got count=%d type=%d"
			% [DROP_FILTER_COUNT, Items.Type.FLAX, panel.cursor.count, panel.cursor.item_type])
	panel.cursor.clear()

	# --- 14c: right-click clears ----------------------------------------
	# Pre-set explicitly rather than leaning on 14b's write, so a drop-to-set
	# regression reddens ONE assertion instead of quietly satisfying this one.
	ins.state["filter_item_type"] = Items.Type.WHEAT
	_check(failures, _click_filter_slot(panel, MOUSE_BUTTON_RIGHT),
		"(14c) SETUP: the panel emitted no filter rect to right-click on")
	_check(failures, int(ins.state.get("filter_item_type", -99)) == -1,
		"(14c) right-click on the filter slot should clear filter_item_type back to -1, got %d"
			% int(ins.state.get("filter_item_type", -99)))
	panel.queue_free()

	# --- 14d: why the routing is FastInserterPanel and NOT InserterPanel --
	var basic = preload("res://scripts/ui/inserter_panel.gd").new()
	parent.add_child(basic)
	basic.cursor = CursorStack.new()
	basic.inventory = Inventory.new(8)
	basic.toast_callback = func(_msg): pass
	basic.open(ins, world)
	var basic_by_id: Dictionary = _slot_rects_by_id(basic)
	var collides: bool = basic_by_id.has("held_item") and basic_by_id.has("filter") \
		and (basic_by_id["held_item"] as Rect2).intersects(basic_by_id["filter"] as Rect2)
	# Assert the IMPLICATION, not the antecedent. Asserting `collides` flatly
	# would turn this suite red the day someone TEACHES InserterPanel about
	# filters — a correct change failing on an improvement. A good failure
	# message is not enough mitigation: a red suite is a forcing function
	# whatever it says. So branch on whether the basic panel knows about
	# filters at all, and assert what should hold in each world.
	if not basic._slot_y_offsets().has("filter"):
		_check(failures, collides,
			"(14d) PREMISE behind sub-case 15's routing: the BASIC InserterPanel has no \"filter\" key in _slot_y_offsets(), so the electric tier's filter slot falls back to the default offset and should land ON TOP of the held-item slot. Rects: %s" % str(basic_by_id))
	else:
		_check(failures, not collides,
			"(14d) InserterPanel now declares a \"filter\" y-offset, so it has grown filter support — but its rects still collide for this tier. Either finish that support or revisit the ELECTRIC_INSERTER routing in main.gd, which currently sends this tier to FastInserterPanel precisely because the basic panel could not place a filter slot. Rects: %s" % str(basic_by_id))
	basic.queue_free()
	_disconnect(world); world.queue_free()

# ===========================================================================
# (15) PANEL ROUTING — the electric tier opens FastInserterPanel.
#
# WHAT THIS CAN AND CANNOT PROVE, stated plainly because the technique is
# unusual. The dispatch lives in Main._try_open_building_ui, an instance
# method on a node whose panel references are @onready lookups into a scene
# tree (HUD/FastInserterPanel and two dozen siblings) and whose body also
# touches grid_world and the player. Constructing that headless is a scene
# fixture, not a unit test, so the arm is pinned by a STATIC FILE SCAN — the
# same technique test_building_ui_4.gd uses for its ProcessorPanel reuse
# audit.
#
# Proved here: the match arm EXISTS, appears exactly once, and its first
# executable statement is `fast_inserter_panel.open(b, grid_world)` — so the
# tier can no longer fall through to the generic building_panel, and is not
# routed to the basic InserterPanel either.
# NOT proved here: that the identifier `fast_inserter_panel` resolves to a
# live FastInserterPanel at runtime. That is the scene file's job.
# What IS proved about the panel itself is sub-case 14 — FastInserterPanel
# lays this tier out correctly and both filter write paths work on it.
# ===========================================================================
static func _case_panel_routing(failures: Array) -> void:
	var f: FileAccess = FileAccess.open(MAIN_SRC_PATH, FileAccess.READ)
	if f == null:
		_check(failures, false, "(15) SETUP: cannot open %s for the routing scan" % MAIN_SRC_PATH)
		return
	var lines: PackedStringArray = f.get_as_text().split("\n")
	f.close()

	var arm_line: int = -1
	var arm_count: int = 0
	for i in lines.size():
		if lines[i].strip_edges() == ROUTING_ARM_LABEL:
			arm_count += 1
			if arm_line < 0:
				arm_line = i
	_check(failures, arm_count == 1,
		"(15) main.gd should contain exactly ONE `%s` match arm, found %d — the scan below reads the first" % [ROUTING_ARM_LABEL, arm_count])
	if arm_line < 0:
		_check(failures, false,
			"(15) main.gd has NO `%s` arm in its panel dispatch, so the tier falls through to the generic building_panel — which has no filter row at all" % ROUTING_ARM_LABEL)
		return

	# First executable line under the arm, skipping blanks and comments.
	var body: String = ""
	var j: int = arm_line + 1
	while j < lines.size():
		var t: String = lines[j].strip_edges()
		if t == "" or t.begins_with("#"):
			j += 1
			continue
		body = t
		break
	_check(failures, body == ROUTING_ARM_BODY,
		"(15) the ELECTRIC_INSERTER panel arm must call `%s`. The tier's slot_layout carries a `filter` slot, and FastInserterPanel is the only panel that draws the FILTER header, the name/placeholder, the drop-to-set hint and the right-click-to-clear handler. Got `%s`"
			% [ROUTING_ARM_BODY, body])

# ===========================================================================
# (16) SUPPLY-AREA BOUNDARY.
#
# PowerNetwork.SUPPLY_RADIUS is 1, so a consumer is powered at Chebyshev 1
# from a pole and unpowered at Chebyshev 2. Asserted from BOTH sides, and
# behaviourally as well as by query: the query half proves the topology, the
# tick half proves the inserter actually reads it. A machine that queried
# correctly and ran anyway would pass the first half alone.
#
# The far inserter contributes NO demand — power_network.gd's ELECTRIC_
# INSERTER arm skips consumers whose _supply_component_id is -1 — so the
# near inserter's satisfaction is unchanged by its presence.
# ===========================================================================
static func _case_supply_area_boundary(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, true, failures, "(16)")
	if world == null:
		return
	var near_ins: Building = world.building_at(ELEC_INS_POS)
	if near_ins == null:
		_check(failures, false, "(16) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	var far_ins: Building = _place_electric_with_chests(world, FAR_INS_POS, failures, "(16-far)")
	if far_ins == null:
		_disconnect(world); world.queue_free()
		return
	var far_src: Building = world.building_at(Inserter.source_tile(far_ins))
	var far_dst: Building = world.building_at(Inserter.dest_tile(far_ins))
	var near_dst: Building = world.building_at(Inserter.dest_tile(near_ins))
	if far_src == null or far_dst == null or near_dst == null:
		_check(failures, false, "(16) SETUP: a source or destination chest is missing around %s / %s" % [str(ELEC_INS_POS), str(FAR_INS_POS)])
		_disconnect(world); world.queue_free()
		return
	far_src.state["bag"] = [[Items.Type.WHEAT, SEEDED_WHEAT]]

	var near_cheb: int = _chebyshev(POLE_POS, ELEC_INS_POS)
	var far_cheb: int = _chebyshev(POLE_POS, FAR_INS_POS)
	_check(failures, near_cheb == PowerNetwork.SUPPLY_RADIUS,
		"(16) PREMISE: the near inserter should sit at Chebyshev %d from the pole, measured %d" % [PowerNetwork.SUPPLY_RADIUS, near_cheb])
	_check(failures, far_cheb == PowerNetwork.SUPPLY_RADIUS + 1,
		"(16) PREMISE: the far inserter should sit ONE ring outside the supply area at Chebyshev %d, measured %d" % [PowerNetwork.SUPPLY_RADIUS + 1, far_cheb])

	PowerNetwork.update_supply_demand(world)
	var near_sat: float = PowerNetwork.power_satisfaction_at(world, ELEC_INS_POS)
	var far_sat: float = PowerNetwork.power_satisfaction_at(world, FAR_INS_POS)
	_check(failures, near_sat > Inserter.POWER_EPSILON,
		"(16) Chebyshev %d is INSIDE the supply area — satisfaction should be above POWER_EPSILON, got %.4f" % [PowerNetwork.SUPPLY_RADIUS, near_sat])
	_check(failures, far_sat == 0.0,
		"(16) Chebyshev %d is OUTSIDE the supply area — satisfaction should be exactly 0.0, got %.4f" % [PowerNetwork.SUPPLY_RADIUS + 1, far_sat])

	for _i in SUPPLY_RUN_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var near_delivered: int = _bag_count(near_dst.state.get("bag", []), Items.Type.WHEAT)
	var far_delivered: int = _bag_count(far_dst.state.get("bag", []), Items.Type.WHEAT)
	var far_left: int = _bag_count(far_src.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, near_delivered > 0,
		"(16) the inserter at Chebyshev %d is powered and should have delivered within %d ticks, its destination holds %d" % [PowerNetwork.SUPPLY_RADIUS, SUPPLY_RUN_TICKS, near_delivered])
	_check(failures, far_delivered == 0,
		"(16) the inserter at Chebyshev %d has no power and must deliver NOTHING, its destination holds %d" % [PowerNetwork.SUPPLY_RADIUS + 1, far_delivered])
	_check(failures, far_left == SEEDED_WHEAT,
		"(16) the unpowered inserter must not even pick up — its source should still hold %d wheat, it holds %d" % [SEEDED_WHEAT, far_left])
	_check(failures, int(far_ins.state.get("state", -99)) == Inserter.STATE_NO_POWER,
		"(16) the out-of-range inserter should report STATE_NO_POWER (%d), got %d" % [Inserter.STATE_NO_POWER, int(far_ins.state.get("state", -99))])
	_disconnect(world); world.queue_free()

# ===========================================================================
# (17) SAVE ROUND-TRIP OF A MID-SWING FILTERED INSERTER.
#
# MID-SWING on purpose. A save taken at the cycle boundary round-trips an
# empty hand and a zero progress, which survive any serializer including one
# that dropped the fields entirely. The arm is therefore driven to
# PRE_OUTAGE_TICKS first — the same "strictly between pickup and delivery"
# point sub-case 9 derives and verifies — and the premise is re-asserted
# here rather than assumed, so a timing drift reads as a setup failure
# instead of as a mysterious serialization one.
#
# JSON coerces every number to a float, so the ints are read back through
# int() and the float through a tolerance (see CYCLE_PROGRESS_TOL).
# ===========================================================================
static func _case_save_roundtrip(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, true, failures, "(17)")
	if world == null:
		return
	var ins: Building = world.building_at(ELEC_INS_POS)
	if ins == null:
		_check(failures, false, "(17) SETUP: no electric inserter at %s" % str(ELEC_INS_POS))
		_disconnect(world); world.queue_free()
		return
	ins.state["filter_item_type"] = Items.Type.WHEAT
	for _i in PRE_OUTAGE_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var progress_before: float = float(ins.state.get("cycle_progress", -1.0))
	var held_before: int = Inserter.held_item_type(ins)
	var state_before: int = int(ins.state.get("state", -99))
	_check(failures, held_before == Items.Type.WHEAT,
		"(17) PREMISE: after %d powered ticks the arm should be holding WHEAT (type %d), holds type %d" % [PRE_OUTAGE_TICKS, Items.Type.WHEAT, held_before])
	_check(failures, progress_before > 0.0 and progress_before < 0.5,
		"(17) PREMISE: after %d powered ticks the arm should be strictly MID-SWING (0.0 < progress < 0.5), progress is %.6f" % [PRE_OUTAGE_TICKS, progress_before])

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16)):
		_check(failures, false, "(17) save_game failed")
		_save_cleanup(world, player_a, null, null, orig_path)
		return
	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_check(failures, false, "(17) load_game failed: %s" % result.error_message)
		_save_cleanup(world, player_a, world_b, player_b, orig_path)
		return

	var ins_b: Building = world_b.building_at(ELEC_INS_POS)
	if ins_b == null:
		_check(failures, false, "(17) no building at %s after load" % str(ELEC_INS_POS))
	else:
		_check(failures, ins_b.type == Buildings.Type.ELECTRIC_INSERTER,
			"(17) building type should still be ELECTRIC_INSERTER (%d) after load, got %d" % [Buildings.Type.ELECTRIC_INSERTER, ins_b.type])
		_check(failures, int(ins_b.state.get("filter_item_type", -99)) == Items.Type.WHEAT,
			"(17) filter_item_type should still be WHEAT (type %d) after load, got %d" % [Items.Type.WHEAT, int(ins_b.state.get("filter_item_type", -99))])
		var progress_after: float = float(ins_b.state.get("cycle_progress", -1.0))
		_check(failures, absf(progress_after - progress_before) < CYCLE_PROGRESS_TOL,
			"(17) cycle_progress should survive the round-trip — saved %.6f, loaded %.6f. A reset to 0.0 means the arm teleports back to the source on every reload" % [progress_before, progress_after])
		_check(failures, Inserter.held_item_type(ins_b) == Items.Type.WHEAT,
			"(17) the held item must survive the round-trip — the arm was carrying WHEAT (type %d), after load it carries type %d. Losing it destroys an item on every save/load" % [Items.Type.WHEAT, Inserter.held_item_type(ins_b)])
		_check(failures, int(ins_b.state.get("state", -99)) == state_before,
			"(17) the state machine's state should survive the round-trip, saved %d and loaded %d" % [state_before, int(ins_b.state.get("state", -99))])
	_save_cleanup(world, player_a, world_b, player_b, orig_path)

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
		src_chest.state["bag"] = [[Items.Type.WHEAT, SEEDED_WHEAT]]
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

## Pole + accumulator + electric inserter + chests, and NO generator. The
## accumulator's discharge is therefore the component's entire supply, which
## is the only FLOAT term in PowerNetwork's arithmetic — see EPS_ACC_POS for
## why that is the practical way to land on a non-integral satisfaction.
## `charge` is poked straight into state (same trick sub-case 3b uses for
## fuel); the rig is about the satisfaction it produces, not about how the
## accumulator got charged. Returns the world, or null after a setup failure.
static func _build_epsilon_world(parent: Node, charge: float, failures: Array, label: String):
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.POWER_POLE, POLE_POS):
		_check(failures, false, "%s SETUP: power pole placement at %s failed" % [label, str(POLE_POS)])
		_disconnect(world); world.queue_free()
		return null
	if not world.place_building(Buildings.Type.ACCUMULATOR, EPS_ACC_POS):
		_check(failures, false, "%s SETUP: accumulator placement at %s failed" % [label, str(EPS_ACC_POS)])
		_disconnect(world); world.queue_free()
		return null
	# Source chest left EMPTY on purpose: the above-boundary half of sub-case
	# 10 then lands in STATE_IDLE, which is unambiguously "not stalled".
	var ins: Building = _place_electric_with_chests(world, ELEC_INS_POS, failures, label)
	if ins == null:
		_disconnect(world); world.queue_free()
		return null
	var acc: Building = world.building_at(EPS_ACC_POS)
	if acc == null:
		_check(failures, false, "%s SETUP: building_at(%s) returned null after placing the accumulator" % [label, str(EPS_ACC_POS)])
		_disconnect(world); world.queue_free()
		return null
	acc.state["charge"] = charge
	return world

## Recompute the epsilon rig's network and report its satisfaction, pinning
## the premise (no raw supply, demand from the one inserter) so a layout
## drift is diagnosed as a setup problem rather than as a mystifying state
## assertion two lines later.
##
## NOTE: update_supply_demand DRAINS the accumulator it just discharged, so
## this must be called exactly once per rig, and callers must tick the
## inserter directly rather than through TickSystem afterwards.
static func _epsilon_rig_satisfaction(world, failures: Array, label: String) -> float:
	PowerNetwork.update_supply_demand(world)
	var comp: int = PowerNetwork.network_id_at(world, POLE_POS)
	if comp < 0:
		_check(failures, false, "%s SETUP: pole at %s is not in a power network" % [label, str(POLE_POS)])
		return -1.0
	_check(failures, PowerNetwork.demand_for(world, comp) == ELECTRIC_DEMAND,
		"%s SETUP: the only consumer should be the inserter (demand %d), got %d" % [label, ELECTRIC_DEMAND, PowerNetwork.demand_for(world, comp)])
	return PowerNetwork.satisfaction_for(world, comp)

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

## Every WHEAT item anywhere in one inserter's rig: source chest, plus
## destination chest, plus whatever the arm is holding. Held items live in
## held_item_buffer with a count of 0 or 1, so held_item_type >= 0 is worth
## exactly one item.
##
## Conservation across an outage is the assertion that separates "EXTENDED
## the stall arm header" from "gave the stall its OWN arm". An own arm
## without the resume guard destroys the item in hand, picks a FRESH one out
## of the source chest, and still delivers — so a delivery-only assertion
## passes on it, and the total does not.
static func _rig_wheat_total(world, ins: Building) -> int:
	var total: int = 0
	var src: Building = world.building_at(Inserter.source_tile(ins))
	if src != null:
		total += _bag_count(src.state.get("bag", []), Items.Type.WHEAT)
	var dst: Building = world.building_at(Inserter.dest_tile(ins))
	if dst != null:
		total += _bag_count(dst.state.get("bag", []), Items.Type.WHEAT)
	if Inserter.held_item_type(ins) == Items.Type.WHEAT:
		total += 1
	return total

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

## slot id -> Rect2 for every slot a panel lays out. Keyed by ID because
## every geometry claim in sub-case 14 is about WHICH row a slot landed in,
## and the electric tier's layout has no fuel row to count positions from.
static func _slot_rects_by_id(panel) -> Dictionary:
	var out: Dictionary = {}
	for entry in panel._building_slot_rects():
		out[str(entry["slot_def"].get("id", ""))] = entry["rect"]
	return out

## Synthesize a mouse-button press at the CENTRE of the panel's filter slot
## and push it through the panel's own _gui_input, so the whole real path
## runs — hit test, then _handle_building_slot_click -> _drop_into_slot ->
## _drop_into_filter for LMB, or FastInserterPanel's own RMB arm for
## MOUSE_BUTTON_RIGHT. Calling those handlers directly instead would skip the
## hit test, and a filter row placed at the wrong y would still pass.
## Returns false if the panel emitted no filter rect at all.
static func _click_filter_slot(panel, button_index: int) -> bool:
	var by_id: Dictionary = _slot_rects_by_id(panel)
	if not by_id.has("filter"):
		return false
	var r: Rect2 = by_id["filter"]
	var ev := InputEventMouseButton.new()
	ev.button_index = button_index
	ev.pressed = true
	ev.position = r.position + r.size * 0.5
	panel._gui_input(ev)
	return true

## Chebyshev (chessboard) distance — the metric PowerNetwork.SUPPLY_RADIUS
## is expressed in.
static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Tear down sub-case 17's two worlds, delete the scratch save file, and put
## SaveSystem.save_path back. Mirrors test_inserter.gd's _cleanup, but routed
## through this file's own _disconnect and TEST_SAVE_PATH.
static func _save_cleanup(world, player_a, world_b, player_b, orig_path: String) -> void:
	_disconnect(world)
	if world != null:
		world.queue_free()
	if player_a != null:
		player_a.queue_free()
	_disconnect(world_b)
	if world_b != null:
		world_b.queue_free()
	if player_b != null:
		player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path

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
