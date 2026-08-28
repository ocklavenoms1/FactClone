extends RefCounted

## Electric drill — session-electricity-processors, Tasks 2 + 4.
##
## Task 2 pinned the ELECTRIC_DRILL registry row: the on-disk enum integer,
## the DATA row shape (name / footprint / overlays / direction), the no-fuel
## slot layout, the make() dispatch type, the swatch colour, and the
## ore-coverage placement rule (sub-cases 1-6). Task 4 adds the power half
## (sub-cases 7-18), mirroring test_electric_smelter.gd's families on the
## drill's own machine (drill_progress, deposit greed, richness drain,
## DEPLETED):
##
##   7.  Module tables + the two-direction burner guard: POWER_EPSILON pinned
##       to the literal 0.05, power_demand 10/0, is_electric true/false.
##   8.  The effective-target arithmetic, direct calls on a stub world:
##       sat 0.00 → 640 (pins epsilon + ratio + ceil in one literal),
##       sat 1.00 → 32, burner at sat 0.00 → 40 unchanged.
##   9.  sat 1.00 trajectory — ore N at tick 32N, both boundaries sampled
##       from both sides (31/32 and 63/64), plus the greedy-pick richness
##       literals (the drill's own path signal — which deposit paid).
##  10.  sat 0.50 brownout trajectory — T_eff 64; samples 63/64 and 127/128.
##  11.  The epsilon boundary — satisfaction EXACTLY 0.05 parks the machine
##       (state 5, the `<=` decision); progress frozen, deposit undrained.
##  12.  Constant demand — the literal 10 while IDLE and while DRILLING,
##       asserted with `==` in both states.
##  13.  3a fuel sentinel — a poked fuel_buffer survives 8 full cycles (8
##       chosen because DRILL_ORE_PER_FUEL is 8: a live consume_tick would
##       decrement the buffer exactly at ore #8 AND leave burn progress
##       nonzero for ores 1..7 — both assertions bite).
##  14.  3b wood on an edge belt is never eaten — MANDATORY for the drill:
##       the burner pulls fuel from ALL FOUR edges (try_pull_fuel -1), so
##       every edge is a fuel port to un-gate.
##  15.  Q3 dual-pin freeze — mid-accumulation outage: progress HELD at the
##       cut value AND the wall-clock completion identity (first ore at
##       start + outage + T_eff), with the richness-unchanged premise (a
##       runaway drill drains the deposit — the drill's extra signal).
##  16.  Q4 shape assertion — make()'s state key set as a sorted literal.
##  17.  Save round-trip mid-accumulation — type int 38, drill_progress
##       preserved, resumes to completion on the right tick.
##  18.  DEPLETED interaction — depletion still lands exactly like the
##       burner's, and DEPLETED WINS over NO_POWER (the permanent fact
##       outranks the transient one — locked precedence, Task 4).
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. The enum integer is written as 38
## (re-derived by hand on 2026-08-27 from the enum tail — UNDERGROUND_BELT_EXIT
## is 36, ELECTRIC_SMELTER 37), the footprint as Vector2i(2, 2) — the CODE'S
## drill footprint (buildings.gd MINING_DRILL row), not the plan text's "1×1",
## which the dispatch re-derivation corrected. State ints as literals: 1
## DRILLING, 4 DEPLETED, 5 NO_POWER. Nothing here asks mining_drill.gd for
## its own expectation.
##
## COLOUR FLOOR NOTE: test_inserter_body_colours.gd's ΔE ≥ 25 floor covers
## only Inserter.BODY_COLOR_BY_TYPE — DATA swatches are outside its domain,
## so this file pins the drill's swatch itself, reusing that suite's L*a*b*
## maths as a measuring instrument.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const ColourMath = preload("res://scripts/tests/test_inserter_body_colours.gd")

# Distinct filename from every other suite's save path so round-trip tests
# cannot collide if the runner order ever changes.
const TEST_SAVE_PATH: String = "user://test_electric_drill.json"

## Hand-chosen swatch literals (2026-08-27). See test_electric_smelter.gd's
## sub-case (5) header for the pin-plus-distance structure.
const SWATCH_ELECTRIC_DRILL := Color(0.48, 0.72, 0.68)    # pale cyan-green
const SWATCH_ELECTRIC_SMELTER := Color(0.10, 0.42, 0.50)  # deep electric teal (smelter suite pins it)
const SWATCH_BURNER_DRILL := Color(0.45, 0.40, 0.32)      # MINING_DRILL DATA row, re-derived by hand
const FLOOR_DE: float = 25.0

# ---------------------------------------------------------------------------
# Task 4 rig layout — the smelter rig's geometry with ore under the machine.
# Stone patch (6..12)x(5..11). The pole at (9,7) is the component everything
# hangs off: both windmills touch it cardinally (generator rule), the drill's
# anchor cell (8,8) sits inside the basic pole's 3x3 supply box (8,6)..(10,8)
# (consumer rule, _supply_component_id), and the ballast lamps / the
# accumulator take free covered cells at (9,6)/(10,6). The drill's four
# footprint cells (8,8) (9,8) (8,9) (9,9) each carry a STONE deposit.
# ---------------------------------------------------------------------------
const WINDMILL_A_POS: Vector2i = Vector2i(7, 6)
const WINDMILL_B_POS: Vector2i = Vector2i(10, 6)
const POLE_POS: Vector2i       = Vector2i(9, 7)
const DRILL_POS: Vector2i      = Vector2i(8, 8)
const LAMP_A_POS: Vector2i     = Vector2i(9, 6)   # brownout world only
const LAMP_B_POS: Vector2i     = Vector2i(10, 6)  # brownout world only (windmill B absent there)
const ACC_POS: Vector2i        = Vector2i(9, 6)   # epsilon world only (cardinal to the pole)
# The drill faces canonical east (output E edge, cells (10,8)/(10,9), left
# beltless so ore accumulates in output_buffer). The 3b belt sits on the S
# edge — for the BURNER any edge is a fuel port (try_pull_fuel scans all 4).
const FUEL_BELT_POS: Vector2i  = Vector2i(8, 10)

# The drill's four covered cells, in refresh_covered_deposits order (dx
# outer, dy inner): (8,8), (8,9), (9,8), (9,9).
const ORE_RICHNESS: int = 50

# Power units drawn by one ELECTRIC_DRILL — a LITERAL, never read back from
# mining_drill.gd's table (locked at the design pass: 10, same as the
# electric smelter; 2 smelters + 2 drills = the Task-6 rig's exact 40).
const ELECTRIC_DEMAND: int = 10

# Full-power world: two windmills at 6 each. 12 supply / 10 demand → sat 1.0.
const FULL_SUPPLY: int = 12
# Brownout world: ONE windmill (6), demand 10 (drill) + 2 lamps = 12.
# 6 / 12 = 0.5 exactly.
const BROWNOUT_SUPPLY: int = 6
const BROWNOUT_DEMAND: int = 12
# Epsilon world: NO generator; one accumulator poked to charge 0.5. The
# pre-pass discharges min(deficit 10, MAX_DISCHARGE_RATE 5, charge 0.5) =
# 0.5, so satisfaction = 0.5 / 10 = 0.05 — the accumulator-discharge trick
# from test_electric_inserter.gd sub-case 10: 0.5 and 10 are exactly
# representable, so the quotient is the same double as the literal 0.05.
const EPS_CHARGE: float = 0.5

# Hand-derivation (2026-08-27) of the sat-1.00 ore ticks, from
# mining_drill.gd's tick order (re-read at 28e6aa8):
#   Each tick: (1) fuel pull [electric: gated off] → (2) push outputs →
#   (3) pick deposit → [power gate] → (4) room check → (5) progress =
#   stored + 1; if progress < target: store, set DRILLING, return →
#   (6) production: drain 1 richness, append 1 ore, progress reset to 0.
#   tick 1:      progress 0+1 = 1 < 32 → stored; state DRILLING.
#   ticks 2..31: progress == t.
#   tick 32:     progress 31+1 = 32, NOT < 32 → production fires: ore #1
#                appended, deposit drained 50→49, progress 0.
#   tick 64:     same again → ore #2.
# UNLIKE the smelter there is no commit tick: the drill's cycle starts
# implicitly at progress 0 and produces on the tick its counter REACHES the
# target, so ore N lands at exactly tick 32N. (The burner's own literals
# already imply this shape: 1 ore per 40 ticks, gapless, at 40/80/120...)
# Sampled one tick either side of each boundary (the two-sample protocol).
const SAT100_SAMPLES: Array = [[31, 0], [32, 1], [63, 1], [64, 2]]

# Same derivation at sat 0.50: T_eff = ceil(32 / 0.5) = 64, recomputed per
# tick from LIVE satisfaction (target-stretch, the locked brownout rule).
# Ore #1 at tick 64, ore #2 at 128.
const SAT050_SAMPLES: Array = [[63, 0], [64, 1], [127, 1], [128, 2]]

# Sub-case 11 window: 40 direct ticks at the boundary — one full rated
# burner cycle, and longer than T_eff 32, so a machine that RAN instead of
# parking would have produced (and drained the deposit — the richness
# assertion is the drill's own discriminator).
const EPS_STALL_TICKS: int = 40

# Sub-case 13: 260 ticks covers exactly 8 electric cycles (8 x 32 = 256,
# 9th would land at 288). Eight ON PURPOSE — DRILL_ORE_PER_FUEL is 8, so a
# live (un-gated) Burner.consume_tick would leave fuel_burn_progress at
# 1..7 for the first seven ores and decrement fuel_buffer 7→6 exactly at
# ore #8: both sentinel assertions bite, not just one.
const SENTINEL_RUN_TICKS: int = 260
const SENTINEL_ORES: int = 8
const FUEL_SENTINEL: int = 7

# Sub-case 15 (Q3 dual-pin) numbers, with the identity written out
# (T_eff = 32, e = FREEZE_E, O = FREEZE_OUTAGE):
#   powered ticks 1..10   — progress accumulates to e == 10 at the cut
#   outage ticks 11..60   — parked (state 5); progress HELD at 10
#   restore; ticks 61..82 — progress 11..32; production fires after
#                           T_eff − e = 22 more ticks
#   first ore at machine tick e + O + (T_eff − e) = O + T_eff
#                           = 50 + 32 = 82.
# Constraints (locked at the design pass): e ≠ 0 (10), e < T_eff (10 < 32),
# O > T_eff − e (50 > 22), O mod T_eff ≠ 0 (50 mod 32 = 18). The last
# constraint is why even the elapsed pin catches a full-rate
# drain-through-the-outage: a drain of exactly k x T_eff ticks wraps
# progress back to e, and the elapsed form ALONE would sit green on it —
# the wall-clock identity is the pin that cannot be wrapped past.
const FREEZE_E: int = 10
const FREEZE_OUTAGE: int = 50
const FREEZE_REMAINDER: int = 22     # T_eff − e; identity total 10+50+22 = 82

# Sub-case 17: save at the same mid-accumulation point (drill_progress 10),
# so the post-load resume completes after the same 22-tick remainder.
const SAVE_PRE_TICKS: int = 10
const SAVE_REMAINDER: int = 22

# Sub-case 18: one deposit, richness 1 — ore #1 at tick 32 exhausts it;
# tick 33 finds no live deposit and parks DEPLETED (the literal 4).
const DEPLETED_RUN_TICKS: int = 40
const DEPLETED_OUTAGE_TICKS: int = 10

static func test_name() -> String:
	return "electric drill (registry row + power tables + effective target + trajectories + epsilon boundary + constant demand + fuel sentinels + freeze dual-pin + make() shape + save round-trip + DEPLETED precedence)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_1_enum_int(failures)
	_case_2_data_row_shape(failures)
	_case_3_no_fuel_slot(failures)
	_case_4_make_type_pin(failures)
	_case_5_swatch_colour(failures)
	_case_6_ore_coverage_rule(parent, failures)
	_case_7_power_tables(failures)
	_case_8_effective_target(failures)
	_case_9_full_power_trajectory(parent, failures)
	_case_10_brownout_trajectory(parent, failures)
	_case_11_epsilon_boundary(parent, failures)
	_case_12_constant_demand(parent, failures)
	_case_13_fuel_sentinel(parent, failures)
	_case_14_wood_belt_not_eaten(parent, failures)
	_case_15_freeze_dual_pin(parent, failures)
	_case_16_make_shape(failures)
	_case_17_save_roundtrip(parent, failures)
	_case_18_depleted_precedence(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "18 sub-cases pass: registry row (1-6) + power tables + effective target + both trajectories + epsilon boundary + constant demand + fuel sentinel + wood-belt guard + freeze dual-pin + make() shape + save round-trip + DEPLETED precedence" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) THE ON-DISK INTEGER — 38, forever. See test_electric_smelter.gd (1).
# ===========================================================================
static func _case_1_enum_int(failures: Array) -> void:
	if int(Buildings.Type.ELECTRIC_DRILL) != 38:
		failures.append("(1) Buildings.Type.ELECTRIC_DRILL is %d, expected the literal 38 — the append-only rule broke, and every save carrying a 38 now loads as the wrong machine"
			% int(Buildings.Type.ELECTRIC_DRILL))

# ===========================================================================
# (2) DATA ROW SHAPE — mirrors the burner MINING_DRILL row minus fuel.
# ===========================================================================
static func _case_2_data_row_shape(failures: Array) -> void:
	if Buildings.name_of(Buildings.Type.ELECTRIC_DRILL) != "Electric Drill":
		failures.append("(2) name is '%s', expected 'Electric Drill'"
			% Buildings.name_of(Buildings.Type.ELECTRIC_DRILL))
	if Buildings.footprint_of(Buildings.Type.ELECTRIC_DRILL) != Vector2i(2, 2):
		failures.append("(2) footprint is %s, expected Vector2i(2, 2) — the burner drill is 2x2 (the plan text's '1x1' was wrong; code wins)"
			% str(Buildings.footprint_of(Buildings.Type.ELECTRIC_DRILL)))
	var overlays: Array = Buildings.requires_overlay(Buildings.Type.ELECTRIC_DRILL)
	if overlays != [Terrain.Overlay.NONE, Terrain.Overlay.STONE]:
		failures.append("(2) requires_overlay is %s, expected [NONE, STONE] — must match the burner drill" % str(overlays))
	if not Buildings.supports_direction(Buildings.Type.ELECTRIC_DRILL):
		failures.append("(2) supports_direction is false, expected true — output port rotates like the burner's")

# ===========================================================================
# (3) NO FUEL SLOT — sweep plus exact id list. See test_electric_smelter (3).
# ===========================================================================
static func _case_3_no_fuel_slot(failures: Array) -> void:
	var layout: Array = Buildings.slot_layout_for(Buildings.Type.ELECTRIC_DRILL)
	var ids: Array = []
	for slot in layout:
		ids.append(str(slot.get("id", "")))
		if str(slot.get("kind", "")) == "fuel" or str(slot.get("id", "")) == "fuel":
			failures.append("(3) slot_layout carries a fuel slot (%s) — the electric tier draws from the power network, never from a fuel buffer" % str(slot))
	if ids != ["output"]:
		failures.append("(3) slot ids are %s, expected exactly ['output'] — the burner layout minus its fuel slot" % str(ids))

# ===========================================================================
# (4) make() STAMPS THE ELECTRIC TYPE — MiningDrill.make hardcoded the
# burner enum before this session. See test_electric_smelter.gd (4).
# ===========================================================================
static func _case_4_make_type_pin(failures: Array) -> void:
	var b: Building = Buildings.make(Buildings.Type.ELECTRIC_DRILL, Vector2i(3, 3))
	if b == null:
		failures.append("(4) Buildings.make(ELECTRIC_DRILL, ...) returned null — no make() dispatch arm")
		return
	if int(b.type) != 38:
		failures.append("(4) make(ELECTRIC_DRILL).type is %d, expected the literal 38 — the arm delegates to a make() that hardcodes the burner enum" % int(b.type))

# ===========================================================================
# (5) SWATCH COLOUR — pin plus distance. See test_electric_smelter.gd (5).
# ===========================================================================
static func _case_5_swatch_colour(failures: Array) -> void:
	var actual: Color = Buildings.swatch_color_of(Buildings.Type.ELECTRIC_DRILL)
	if actual != SWATCH_ELECTRIC_DRILL:
		failures.append("(5) swatch is %s, expected the pinned literal %s" % [str(actual), str(SWATCH_ELECTRIC_DRILL)])
	var d_burner: float = ColourMath.delta_e(actual, SWATCH_BURNER_DRILL)
	if d_burner < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the burner drill's %s (floor %.1f) — the two drills would read as shades of one another"
			% [str(actual), d_burner, str(SWATCH_BURNER_DRILL), FLOOR_DE])
	var d_sibling: float = ColourMath.delta_e(actual, SWATCH_ELECTRIC_SMELTER)
	if d_sibling < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the electric smelter's %s (floor %.1f) — the two electric processors would read as shades of one another"
			% [str(actual), d_sibling, str(SWATCH_ELECTRIC_SMELTER), FLOOR_DE])

# ===========================================================================
# (6) THE ORE-COVERAGE PLACEMENT RULE COVERS TYPE 38. Beyond the Task-2 RED
# list's registry sub-cases, deliberately: grid_world.gd's resource-node
# exemption and its validate_placement call both hardcoded MINING_DRILL, so
# without this pin the electric drill would be REJECTED on ore ("Mine the
# ore first") and its covered_deposits never populated — an extension whose
# absence is otherwise indistinguishable from success (the silent-
# compensation shape). Three assertions: on-ore placement succeeds AND
# populates covered_deposits with the exact tile AND stamps type 38;
# off-ore placement fails with the burner's own error message.
# ===========================================================================
static func _case_6_ore_coverage_rule(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)

	# One ore tile under the 2x2 footprint anchored at (0,0).
	_set_ore(world, Vector2i(0, 0), ResourceNodes.Type.STONE, 50)
	if not world.place_building(Buildings.Type.ELECTRIC_DRILL, Vector2i(0, 0), Belt.DIR_E):
		failures.append("(6) electric drill on ore rejected: %s — the MINING_DRILL exemption in can_place_building does not cover type 38"
			% world.last_building_place_error)
	else:
		var b: Building = world.building_at(Vector2i(0, 0))
		if b == null:
			failures.append("(6) placed electric drill not found at its anchor")
		else:
			if int(b.type) != 38:
				failures.append("(6) placed electric drill carries type %d, expected the literal 38" % int(b.type))
			if b.state.get("covered_deposits", []) != [[0, 0]]:
				failures.append("(6) covered_deposits is %s, expected [[0, 0]] — the refresh_covered_deposits placement hook does not cover type 38"
					% str(b.state.get("covered_deposits", [])))
		world.remove_building_at(Vector2i(0, 0))

	# Away from ore: same rejection, same player-facing message as the burner.
	if world.place_building(Buildings.Type.ELECTRIC_DRILL, Vector2i(20, 20), Belt.DIR_E):
		failures.append("(6) electric drill away from ore placed — the ore-coverage rule does not cover type 38")
		world.remove_building_at(Vector2i(20, 20))
	elif "ore deposit" not in world.last_building_place_error.to_lower():
		failures.append("(6) expected 'ore deposit' in the rejection message; got: %s" % world.last_building_place_error)

	_disconnect(world)
	world.queue_free()

# ===========================================================================
# (7) MODULE TABLES + THE TWO-DIRECTION BURNER GUARD (the electric-inserter
# (2a) pattern, both directions per half). power_demand reads the table with
# .get(t, 0) and is_electric with .has(t) — asserting BOTH on the burner
# catches the worse drift, a stray row valued 0 that silently routes the
# burner off its fuel path while looking like it draws nothing.
# ===========================================================================
static func _case_7_power_tables(failures: Array) -> void:
	# POWER_EPSILON pinned to the LITERAL 0.05 — documented-equal to
	# Inserter.POWER_EPSILON and Smelter.POWER_EPSILON (the lamp's on/off
	# threshold). Drift here would silently re-rate the brownout floor, and
	# the 640 literal in sub-case 8 would start disagreeing with the
	# module's own arithmetic.
	_check(failures, MiningDrill.POWER_EPSILON == 0.05,
		"(7) MiningDrill.POWER_EPSILON must be the literal 0.05, got %s — it is documented-equal to Inserter.POWER_EPSILON and the shared lamp threshold" % str(MiningDrill.POWER_EPSILON))
	_check(failures, MiningDrill.power_demand(Buildings.Type.ELECTRIC_DRILL) == 10,
		"(7) power_demand(ELECTRIC_DRILL) must be the literal 10, got %d" % MiningDrill.power_demand(Buildings.Type.ELECTRIC_DRILL))
	# The burner direction — BOTH reads of the table.
	_check(failures, MiningDrill.power_demand(Buildings.Type.MINING_DRILL) == 0,
		"(7) power_demand(MINING_DRILL) must stay 0, got %d — a burner registering demand would drag down every real consumer on its network" % MiningDrill.power_demand(Buildings.Type.MINING_DRILL))
	var burner: Building = MiningDrill.make(Vector2i(0, 0), Belt.DIR_E)
	_check(failures, MiningDrill.is_electric(burner) == false,
		"(7) is_electric(burner drill) must stay false — true would skip the whole fuel path in tick()")
	var elec: Building = MiningDrill.make(Vector2i(0, 0), Belt.DIR_E, Buildings.Type.ELECTRIC_DRILL)
	_check(failures, MiningDrill.is_electric(elec) == true,
		"(7) is_electric(electric drill) should be true — the variant is defined by its POWER_DEMAND_BY_TYPE row")

# ===========================================================================
# (8) THE EFFECTIVE-TARGET ARITHMETIC, direct calls on a stub world (pure
# arithmetic only — behaviour is asserted on real networks in 9-15). The
# drill is not recipe-driven: the base is its own DRILL_TICKS_PER_ORE, so
# _effective_target takes only (b, world).
# ===========================================================================
static func _case_8_effective_target(failures: Array) -> void:
	var elec: Building = MiningDrill.make(Vector2i(0, 0), Belt.DIR_E, Buildings.Type.ELECTRIC_DRILL)
	var burner: Building = MiningDrill.make(Vector2i(0, 0), Belt.DIR_E)
	# sat 0.00 → ceil(ceil(40 x 0.8) / max(0.05, 0.0)) = ceil(32 / 0.05) =
	# 640. This one literal pins the epsilon (0.05), the speed ratio (0.8)
	# AND the rounding mode (ceil) together — a drifted epsilon or ratio
	# cannot land on it.
	var at_zero: int = MiningDrill._effective_target(elec, StubPowerWorld.new(0.0))
	_check(failures, at_zero == 640,
		"(8) electric target at satisfaction 0.00 must be the literal 640 = ceil(32 / 0.05), got %d" % at_zero)
	# sat 1.00 → 32: the DATA-comment claim, electric 32 vs burner 40.
	var at_full: int = MiningDrill._effective_target(elec, StubPowerWorld.new(1.0))
	_check(failures, at_full == 32,
		"(8) electric target at satisfaction 1.00 must be the literal 32 = ceil(40 x 0.8), got %d" % at_full)
	# The burner returns its rated 40 UNCHANGED — and must return BEFORE the
	# satisfaction lookup, or a world with no power network (satisfaction
	# 0.0 everywhere) would stretch every burner drill's cycle to the floor.
	var burner_t: int = MiningDrill._effective_target(burner, StubPowerWorld.new(0.0))
	_check(failures, burner_t == 40,
		"(8) burner target must stay the rated 40 at ANY satisfaction, got %d — anything else means the satisfaction divisor reached the fuel tier" % burner_t)

# ===========================================================================
# (9) SAT 1.00 TRAJECTORY. The whole speed decision in four literals: ore #1
# at tick 32 (electric base = ceil(40 x 0.8), NOT the burner's 40), ore #2
# at 64, each boundary sampled from both sides — see SAT100_SAMPLES for the
# hand-derivation. Plus the drill's own path signal: WHICH deposit paid.
# All four start at 50; greedy pick with topmost-leftmost tiebreak takes
# (8,8) first (all tied), then (9,8) (the topmost-leftmost of the three
# still at 50 — (8,9) and (9,9) sit on row y=9). Hand-walked against
# _pick_best_deposit's loop over refresh order (8,8),(8,9),(9,8),(9,9).
# ===========================================================================
static func _case_9_full_power_trajectory(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(9)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	_verified_sat(world, failures, "(9)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	_run_samples(dr, SAT100_SAMPLES, failures, "(9)", "sat 1.00")
	_check(failures, world.richness_at(Vector2i(8, 8)) == 49,
		"(9) ore #1 must come from (8,8) (greedy tiebreak, all four tied at 50): expected richness 49, got %d" % world.richness_at(Vector2i(8, 8)))
	_check(failures, world.richness_at(Vector2i(9, 8)) == 49,
		"(9) ore #2 must come from (9,8) (topmost-leftmost of the remaining 50s): expected richness 49, got %d" % world.richness_at(Vector2i(9, 8)))
	_check(failures, world.richness_at(Vector2i(8, 9)) == 50 and world.richness_at(Vector2i(9, 9)) == 50,
		"(9) the y=9 deposits must be untouched at 50/50, got %d/%d" % [world.richness_at(Vector2i(8, 9)), world.richness_at(Vector2i(9, 9))])
	_disconnect(world); world.queue_free()

# ===========================================================================
# (10) SAT 0.50 BROWNOUT TRAJECTORY — target-stretch, not rate-scaling. Int
# progress advances 1 per tick; the TARGET is recomputed per tick from live
# satisfaction, so at 0.5 the 32-tick cycle stretches to 64. Ore #2 at the
# literal 128 — a machine still running its rated 32 would have four ore by
# then, and a burner-based 40 would put ore #2 at 80; neither can satisfy
# the 63/64 and 127/128 sample pairs.
# ===========================================================================
static func _case_10_brownout_trajectory(parent: Node, failures: Array) -> void:
	var world = _build_brownout_world(parent, failures, "(10)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	_verified_sat(world, failures, "(10)", BROWNOUT_SUPPLY, BROWNOUT_DEMAND, 0.5)
	_run_samples(dr, SAT050_SAMPLES, failures, "(10)", "sat 0.50")
	_disconnect(world); world.queue_free()

# ===========================================================================
# (11) THE EPSILON BOUNDARY. Satisfaction EXACTLY 0.05 must PARK the machine
# — the cutoff is `<=`, the same boundary the electric inserter, the
# electric smelter and the lamp's glow share. Direct ticks
# (Buildings.tick_one), NOT TickSystem: the grid pre-pass would drain the
# accumulator to 0.0 on the first tick and the boundary claim would go
# untested. The discriminator against `<`: at `<` the machine would RUN
# (satisfaction 0.05 is not below 0.05) at the 640-tick floor — progress
# would accumulate and state would read DRILLING; and a machine that ran
# free would eventually drain the deposit. Richness is the drill's own
# discriminator: a parked drill must not drain what it sits on.
# ===========================================================================
static func _case_11_epsilon_boundary(parent: Node, failures: Array) -> void:
	var world = _build_epsilon_world(parent, failures, "(11)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	PowerNetwork.update_supply_demand(world)
	var comp: int = PowerNetwork.network_id_at(world, POLE_POS)
	if comp < 0:
		_check(failures, false, "(11) SETUP: pole at %s is not in a power network" % str(POLE_POS))
		_disconnect(world); world.queue_free()
		return
	_check(failures, PowerNetwork.demand_for(world, comp) == ELECTRIC_DEMAND,
		"(11) SETUP: the only consumer should be the drill (demand %d), got %d" % [ELECTRIC_DEMAND, PowerNetwork.demand_for(world, comp)])
	var sat: float = world.power_satisfaction_at(DRILL_POS)
	_check(failures, sat == 0.05,
		"(11) SETUP: the drill's own lookup should see EXACTLY 0.05 (accumulator discharge 0.5 / demand 10), got %.6f — a boundary assertion built beside the boundary proves nothing" % sat)
	for _i in EPS_STALL_TICKS:
		Buildings.tick_one(dr, world)
	_check(failures, int(dr.state.get("state", -1)) == 5,
		"(11) at satisfaction exactly 0.05 the electric drill must park in STATE_NO_POWER (the literal 5): got state %d. 2 here means the machine reached the burner's NO_FUEL — the exact state an electric machine must never show; 1 means `<` instead of `<=`" % int(dr.state.get("state", -1)))
	_check(failures, dr.state.get("output_buffer", []).is_empty(),
		"(11) a parked machine must produce NOTHING across %d ticks, output buffer holds %s" % [EPS_STALL_TICKS, str(dr.state.get("output_buffer", []))])
	_check(failures, int(dr.state.get("drill_progress", -1)) == 0,
		"(11) drill_progress must stay 0 while parked, got %d — nonzero means the park is a crawl" % int(dr.state.get("drill_progress", -1)))
	_check(failures, world.richness_at(Vector2i(8, 8)) == 50,
		"(11) a parked drill must not drain its deposit: (8,8) should still be 50, got %d" % world.richness_at(Vector2i(8, 8)))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (12) CONSTANT DEMAND — the locked decision: the electric drill demands its
# 10 whenever placed, IDLE or DRILLING alike. Duty-cycling is undamped
# feedback (the pre-pass runs before the building loop, so any activity it
# sampled is one tick stale — see the ELECTRIC_INSERTER arm's rationale).
# Asserted with `==` in BOTH states, then `==` between them: a `>=` would
# bless a duty-cycled implementation in the idle half.
# ===========================================================================
static func _case_12_constant_demand(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(12)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	# --- IDLE: freshly placed, never ticked ---
	_check(failures, int(dr.state.get("state", -1)) == 0,
		"(12) SETUP: a fresh electric drill should be IDLE (0), got %d" % int(dr.state.get("state", -1)))
	PowerNetwork.update_supply_demand(world)
	var comp: int = PowerNetwork.network_id_at(world, POLE_POS)
	if comp < 0:
		_check(failures, false, "(12) SETUP: pole at %s is not in a power network" % str(POLE_POS))
		_disconnect(world); world.queue_free()
		return
	var demand_idle: int = PowerNetwork.demand_for(world, comp)
	_check(failures, demand_idle == 10,
		"(12) component demand with the drill IDLE should be the literal 10, got %d — 0 means the ELECTRIC_DRILL consumer arm is missing from PowerNetwork.update_supply_demand Stage 1" % demand_idle)
	# --- DRILLING: one tick over live ore ---
	_tick(1)
	_check(failures, int(dr.state.get("state", -1)) == 1,
		"(12) SETUP: one powered tick over live ore should read DRILLING (1), got %d" % int(dr.state.get("state", -1)))
	PowerNetwork.update_supply_demand(world)
	var demand_drilling: int = PowerNetwork.demand_for(world, comp)
	_check(failures, demand_drilling == 10,
		"(12) component demand with the drill DRILLING should be the literal 10, got %d" % demand_drilling)
	_check(failures, demand_idle == demand_drilling,
		"(12) demand must be CONSTANT (no duty-cycling): idle drew %d, drilling drew %d" % [demand_idle, demand_drilling])
	_disconnect(world); world.queue_free()

# ===========================================================================
# (13) 3a FUEL SENTINEL. Q4's locked shape: the Burner fields exist on the
# electric variant (make_state merge stays) but are DEAD. A sentinel poked
# into fuel_buffer must survive 8 full production cycles untouched — 8
# because DRILL_ORE_PER_FUEL is 8: a live consume_tick would decrement the
# buffer exactly at ore #8 (7→6) and leave fuel_burn_progress nonzero
# before that, so BOTH assertions discriminate (a fuel_buffer of 0 never
# could — consume_tick is a no-op on an empty buffer).
# ===========================================================================
static func _case_13_fuel_sentinel(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(13)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	dr.state["fuel_buffer"] = FUEL_SENTINEL
	dr.state["fuel_burn_progress"] = 0
	_tick(SENTINEL_RUN_TICKS)
	_check(failures, _out_count(dr) == SENTINEL_ORES,
		"(13) SETUP: the drill should have completed %d cycles inside %d ticks (otherwise the sentinel assertion is vacuous), got %d ore" % [SENTINEL_ORES, SENTINEL_RUN_TICKS, _out_count(dr)])
	_check(failures, int(dr.state.get("fuel_buffer", -1)) == FUEL_SENTINEL,
		"(13) the electric drill must never consume fuel: fuel_buffer should still be the sentinel %d after %d cycles, got %d — 6 means a live Burner.consume_tick paid for ore #8" % [FUEL_SENTINEL, SENTINEL_ORES, int(dr.state.get("fuel_buffer", -1))])
	_check(failures, int(dr.state.get("fuel_burn_progress", -1)) == 0,
		"(13) fuel_burn_progress must never advance on the electric tier, got %d" % int(dr.state.get("fuel_burn_progress", -1)))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (14) 3b WOOD ON AN EDGE BELT IS NOT EATEN — MANDATORY for the drill: the
# burner drill scans ALL FOUR edges for fuel (Burner.try_pull_fuel with -1,
# no fuel prefer_dir), so unlike the smelter there is no single fuel port to
# gate — every edge is one. Wood passing the S edge on a belt must stay on
# the belt. The belt runs parallel (dir E) with no downstream, so nothing
# else can account for the wood leaving.
# ===========================================================================
static func _case_14_wood_belt_not_eaten(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(14)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	if not world.place_building(Buildings.Type.BELT, FUEL_BELT_POS, Belt.DIR_E):
		_check(failures, false, "(14) SETUP: belt placement at %s failed" % str(FUEL_BELT_POS))
		_disconnect(world); world.queue_free()
		return
	var belt: Building = world.building_at(FUEL_BELT_POS)
	belt.state["slots"][0] = Items.Type.WOOD
	_tick(70)
	_check(failures, _out_count(dr) == 2,
		"(14) SETUP: the drill should have produced 2 ore inside 70 ticks (otherwise the wood assertion is vacuous), got %d" % _out_count(dr))
	_check(failures, _belt_item_count(belt, Items.Type.WOOD) == 1,
		"(14) the wood must STAY on the edge belt: expected 1 on the belt, found %d — 0 means the electric drill pulled it as fuel" % _belt_item_count(belt, Items.Type.WOOD))
	_check(failures, int(dr.state.get("fuel_buffer", -1)) == 0,
		"(14) fuel_buffer must stay 0 (nothing pulled), got %d" % int(dr.state.get("fuel_buffer", -1)))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (15) Q3 DUAL-PIN FREEZE. A mid-accumulation outage is pinned from BOTH
# ends (locked at the design pass — the user's own requirement):
#   (i)  at cut + O: drill_progress == e EXACTLY, no output, and the
#        deposit UNDRAINED — the freeze preserved the elapsed work and a
#        runaway drill drains the deposit (the richness premise, the
#        drill's extra path signal);
#   (ii) the wall-clock completion identity: the first ore lands at
#        machine tick e + O + (T_eff − e) = O + T_eff = 82 — the resume
#        spent the outage and kept the elapsed work.
# (ii) is the stronger pin: a resume that zeroes drill_progress still
# eventually produces — (i) alone stays green on it; the 82-tick identity
# does not. See FREEZE_E's constraint comment for why O mod T_eff ≠ 0.
# ===========================================================================
static func _case_15_freeze_dual_pin(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(15)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	_verified_sat(world, failures, "(15)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	_tick(FREEZE_E)
	_check(failures, int(dr.state.get("drill_progress", -1)) == FREEZE_E,
		"(15) PREMISE: after %d powered ticks drill_progress should be %d (+1 per tick from 0), got %d — the outage below must be taken MID-ACCUMULATION or the freeze claim is vacuous" % [FREEZE_E, FREEZE_E, int(dr.state.get("drill_progress", -1))])
	_check(failures, int(dr.state.get("state", -1)) == 1,
		"(15) PREMISE: the machine should be DRILLING (1) at the cut, got %d" % int(dr.state.get("state", -1)))
	_check(failures, _out_count(dr) == 0 and world.richness_at(Vector2i(8, 8)) == 50,
		"(15) PREMISE: at the cut nothing is produced and nothing drained, got out %d / richness %d" % [_out_count(dr), world.richness_at(Vector2i(8, 8))])
	_check(failures, world.remove_building_at(POLE_POS),
		"(15) SETUP: removing the pole at %s should succeed" % str(POLE_POS))
	_tick(FREEZE_OUTAGE)
	# --- (i) the at-M elapsed pin, with the richness premise ---
	_check(failures, int(dr.state.get("drill_progress", -1)) == FREEZE_E,
		"(15) THE FREEZE: after a %d-tick outage drill_progress must still be EXACTLY %d, got %d — more means the outage path kept incrementing (a crawl or a full-rate drain), less means something reset the cycle" % [FREEZE_OUTAGE, FREEZE_E, int(dr.state.get("drill_progress", -1))])
	_check(failures, int(dr.state.get("state", -1)) == 5,
		"(15) the outage must park the machine in STATE_NO_POWER (the literal 5), got %d" % int(dr.state.get("state", -1)))
	_check(failures, _out_count(dr) == 0 and world.richness_at(Vector2i(8, 8)) == 50,
		"(15) NOTHING moves across the outage: expected out 0 / richness 50, got out %d / richness %d — a drained deposit means the drill ran through the outage" % [_out_count(dr), world.richness_at(Vector2i(8, 8))])
	# --- power back; (ii) the wall-clock identity ---
	_check(failures, world.place_building(Buildings.Type.POWER_POLE, POLE_POS),
		"(15) SETUP: re-placing the pole at %s should succeed" % str(POLE_POS))
	_tick(FREEZE_REMAINDER - 1)   # machine ticks 61..81 — one short of the identity
	_check(failures, _out_count(dr) == 0,
		"(15) ore landed EARLY: at machine tick %d (one before the identity) the output should still be empty, got %d — the resume was credited work it never did" % [FREEZE_E + FREEZE_OUTAGE + FREEZE_REMAINDER - 1, _out_count(dr)])
	_tick(1)                      # machine tick 82 = e + O + (T_eff − e) = O + T_eff
	_check(failures, _out_count(dr) == 1,
		"(15) THE COMPLETION IDENTITY: ore #1 must land at machine tick %d = e(%d) + outage(%d) + remainder(%d), got %d ore there — later means the resume reset drill_progress (the reset hazard), never means the machine froze for good" % [FREEZE_E + FREEZE_OUTAGE + FREEZE_REMAINDER, FREEZE_E, FREEZE_OUTAGE, FREEZE_REMAINDER, _out_count(dr)])
	_check(failures, world.richness_at(Vector2i(8, 8)) == 49,
		"(15) the completed cycle must drain exactly its one richness from (8,8): expected 49, got %d" % world.richness_at(Vector2i(8, 8)))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (16) Q4 SHAPE ASSERTION. The electric variant's state key set, pinned as a
# sorted literal at make(). The Burner merge STAYS on the electric variant
# (locked Q4: fuel fields present-but-unused), so the set is the burner's
# set — and this assertion is the ONLY guard that notices a key quietly
# dropped or added: every reader of these keys on the drill tick path is a
# defensive .get() that would silently paper over an absence, and the state
# machine self-heals most of them on the first tick. The protection must
# not rest on a crash-by-absence — it rests here.
# ===========================================================================
static func _case_16_make_shape(failures: Array) -> void:
	var elec: Building = MiningDrill.make(Vector2i(0, 0), Belt.DIR_E, Buildings.Type.ELECTRIC_DRILL)
	var keys: Array = elec.state.keys()
	keys.sort()
	var want: Array = ["covered_deposits", "dir", "drill_progress", "fuel_buffer", "fuel_burn_progress", "last_fuel_item", "output_buffer", "state"]
	_check(failures, keys == want,
		"(16) make(ELECTRIC_DRILL) state keys must be exactly %s (sorted), got %s — the electric variant deliberately keeps the burner's full shape, fuel fields present-but-unused" % [str(want), str(keys)])

# ===========================================================================
# (17) SAVE ROUND-TRIP MID-ACCUMULATION. A powered electric drill saved at
# drill_progress 10 must come back as type 38 with its progress intact, and
# — the half a field-compare cannot fake — RESUME to completion at the
# right tick: 22 more ticks (T_eff 32 − 10), sampled from both sides. The
# loaded world's terrain is re-seeded by hand before the resume: terrain is
# procgen's cargo, not the save's (the procgen-rehydration model — see
# test_mining_drill.gd's sub-case 5 note); the drill's own state is what
# rides the save, and covered_deposits round-trips inside it.
# ===========================================================================
static func _case_17_save_roundtrip(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(17)")
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	_verified_sat(world, failures, "(17)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	_tick(SAVE_PRE_TICKS)
	_check(failures, int(dr.state.get("drill_progress", -1)) == SAVE_PRE_TICKS and int(dr.state.get("state", -1)) == 1,
		"(17) PREMISE: at save time the drill should be DRILLING (1) at drill_progress %d, got state %d progress %d" % [SAVE_PRE_TICKS, int(dr.state.get("state", -1)), int(dr.state.get("drill_progress", -1))])

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16), {}):
		_check(failures, false, "(17) save_game returned false")
		_save_cleanup(world, player_a, null, null, orig_path)
		return
	# From here only the LOADED world may tick.
	_disconnect(world)

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	if not result.success:
		_check(failures, false, "(17) load_game failed: %s" % result.error_message)
		_save_cleanup(world, player_a, world_b, player_b, orig_path)
		return
	var dr_b: Building = world_b.building_at(DRILL_POS)
	if dr_b == null:
		_check(failures, false, "(17) electric drill missing at %s after load" % str(DRILL_POS))
		_save_cleanup(world, player_a, world_b, player_b, orig_path)
		return
	_check(failures, int(dr_b.type) == 38,
		"(17) the loaded building's type must be the on-disk literal 38, got %d — anything else and the save format's pin on the enum is broken" % int(dr_b.type))
	_check(failures, int(dr_b.state.get("drill_progress", -1)) == SAVE_PRE_TICKS,
		"(17) drill_progress must round-trip: saved %d, loaded %d" % [SAVE_PRE_TICKS, int(dr_b.state.get("drill_progress", -1))])
	_check(failures, int(dr_b.state.get("state", -1)) == 1,
		"(17) state must round-trip as DRILLING (1), got %d" % int(dr_b.state.get("state", -1)))
	# Re-seed the terrain the hand-built world carried (procgen's cargo, not
	# the save's), then confirm the loaded network powers the machine BEFORE
	# the resume is timed.
	for cell in [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9)]:
		_set_ore(world_b, cell, ResourceNodes.Type.STONE, ORE_RICHNESS)
	_verified_sat(world_b, failures, "(17-loaded)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	_tick(SAVE_REMAINDER - 1)
	_check(failures, _out_count(dr_b) == 0,
		"(17) resume landed EARLY: one tick before the %d-tick remainder the output should still be empty, got %d" % [SAVE_REMAINDER, _out_count(dr_b)])
	_tick(1)
	_check(failures, _out_count(dr_b) == 1,
		"(17) the loaded machine must resume to completion after exactly %d more ticks (T_eff 32 − progress %d), got %d ore — 0 here usually means the loaded machine restarted its cycle or lost its power hookup" % [SAVE_REMAINDER, SAVE_PRE_TICKS, _out_count(dr_b)])
	_save_cleanup(world, player_a, world_b, player_b, orig_path)

# ===========================================================================
# (18) DEPLETED INTERACTION + PRECEDENCE. One deposit at richness 1: ore #1
# at tick 32 exhausts it and tick 33 parks the drill DEPLETED (the literal
# 4) — exactly the burner's depletion path, undisturbed by the power gates.
# Then the power is CUT and DEPLETED must HOLD: the deposit being gone is
# the permanent fact, the outage the transient one — a drill that flipped
# to NO_POWER would tell the player to fix their grid to revive a hole in
# the ground (locked precedence: the deposit check runs before the power
# gate).
# ===========================================================================
static func _case_18_depleted_precedence(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(18)", 1, true)
	if world == null:
		return
	var dr: Building = world.building_at(DRILL_POS)
	_verified_sat(world, failures, "(18)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	_tick(DEPLETED_RUN_TICKS)
	_check(failures, _out_count(dr) == 1,
		"(18) the single richness-1 deposit yields exactly 1 ore (at tick 32), got %d" % _out_count(dr))
	_check(failures, int(dr.state.get("state", -1)) == 4,
		"(18) an exhausted electric drill must read DEPLETED (the literal 4), got %d — the depletion path must survive the power gates untouched" % int(dr.state.get("state", -1)))
	_check(failures, world.richness_at(Vector2i(8, 8)) == 0,
		"(18) SETUP: the deposit should be exhausted, richness %d" % world.richness_at(Vector2i(8, 8)))
	# Cut the power: DEPLETED wins over NO_POWER.
	_check(failures, world.remove_building_at(POLE_POS),
		"(18) SETUP: removing the pole at %s should succeed" % str(POLE_POS))
	_tick(DEPLETED_OUTAGE_TICKS)
	_check(failures, int(dr.state.get("state", -1)) == 4,
		"(18) DEPLETED must HOLD through an outage (the permanent fact outranks the transient one): expected the literal 4, got %d — 5 means the power gate outranked the deposit check" % int(dr.state.get("state", -1)))
	_check(failures, _out_count(dr) == 1,
		"(18) no ore can appear after depletion, got %d" % _out_count(dr))
	_disconnect(world); world.queue_free()

# ---------- helpers (house style, mirroring test_electric_smelter.gd) ----------

## Duck-typed stand-in for GridWorld reporting a satisfaction of the test's
## choosing — _effective_target calls exactly one method on `world`, so a
## two-line RefCounted is a complete implementation of the interface under
## test. Used ONLY for the pure arithmetic in sub-case 8; everything about
## behaviour runs on a real GridWorld with real poles.
class StubPowerWorld extends RefCounted:
	var sat: float = 1.0
	func _init(s: float) -> void:
		sat = s
	func power_satisfaction_at(_pos: Vector2i) -> float:
		return sat

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _out_count(dr: Building) -> int:
	return _bag_count(dr.state.get("output_buffer", []), Items.Type.RAW_STONE)

static func _belt_item_count(belt: Building, item_type: int) -> int:
	var n: int = 0
	for slot_t in belt.state.get("slots", []):
		if int(slot_t) == item_type:
			n += 1
	return n

static func _tick(n: int) -> void:
	for _i in n:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

static func _set_ore(world, pos: Vector2i, ore_type: int, richness: int) -> void:
	world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ore_type)
	world.resource_state[pos] = {"richness": richness, "original_richness": richness}

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

## Walk the trajectory tick by tick, sampling the output count at the ticks
## the rows name. Rows are [tick, expected_out] — the two-sample protocol:
## each cycle boundary is pinned from both sides.
static func _run_samples(dr: Building, rows: Array, failures: Array, label: String, scenario: String) -> void:
	var by_tick: Dictionary = {}
	for row in rows:
		by_tick[int(row[0])] = int(row[1])
	var last_tick: int = int(rows[rows.size() - 1][0])
	for t in range(1, last_tick + 1):
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if by_tick.has(t):
			var got: int = _out_count(dr)
			_check(failures, got == by_tick[t],
				"%s %s: at machine tick %d the output should hold %d ore, got %d" % [label, scenario, t, by_tick[t], got])

## Stone patch + ore under the footprint + pole + electric drill — the base
## every rig shares. `single_ore` (sub-case 18) seeds ONLY the anchor cell.
static func _build_base_world(parent: Node, failures: Array, label: String, richness: int = ORE_RICHNESS, single_ore: bool = false):
	var world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(6, 13):
		for y in range(5, 12):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	if single_ore:
		_set_ore(world, DRILL_POS, ResourceNodes.Type.STONE, richness)
	else:
		for cell in [Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9)]:
			_set_ore(world, cell, ResourceNodes.Type.STONE, richness)
	if not world.place_building(Buildings.Type.POWER_POLE, POLE_POS):
		_check(failures, false, "%s SETUP: power pole placement at %s failed" % [label, str(POLE_POS)])
		_disconnect(world); world.queue_free()
		return null
	if not world.place_building(Buildings.Type.ELECTRIC_DRILL, DRILL_POS, Belt.DIR_E):
		_check(failures, false, "%s SETUP: electric drill placement at %s failed: %s" % [label, str(DRILL_POS), world.last_building_place_error])
		_disconnect(world); world.queue_free()
		return null
	return world

## Two windmills (12 supply) against the drill's 10 → satisfaction 1.0.
static func _build_powered_world(parent: Node, failures: Array, label: String, richness: int = ORE_RICHNESS, single_ore: bool = false):
	var world = _build_base_world(parent, failures, label, richness, single_ore)
	if world == null:
		return null
	for wm_pos in [WINDMILL_A_POS, WINDMILL_B_POS]:
		if not world.place_building(Buildings.Type.WINDMILL, wm_pos):
			_check(failures, false, "%s SETUP: windmill placement at %s failed" % [label, str(wm_pos)])
			_disconnect(world); world.queue_free()
			return null
	return world

## ONE windmill (6) against drill 10 + two ballast lamps = 12 → 0.5.
static func _build_brownout_world(parent: Node, failures: Array, label: String):
	var world = _build_base_world(parent, failures, label)
	if world == null:
		return null
	if not world.place_building(Buildings.Type.WINDMILL, WINDMILL_A_POS):
		_check(failures, false, "%s SETUP: windmill placement at %s failed" % [label, str(WINDMILL_A_POS)])
		_disconnect(world); world.queue_free()
		return null
	for lamp_pos in [LAMP_A_POS, LAMP_B_POS]:
		if not world.place_building(Buildings.Type.ELECTRIC_LAMP, lamp_pos):
			_check(failures, false, "%s SETUP: ballast lamp placement at %s failed" % [label, str(lamp_pos)])
			_disconnect(world); world.queue_free()
			return null
	return world

## Pole + drill + one accumulator poked to EPS_CHARGE, NO generator —
## satisfaction lands exactly on 0.05. See EPS_CHARGE for the arithmetic.
static func _build_epsilon_world(parent: Node, failures: Array, label: String):
	var world = _build_base_world(parent, failures, label)
	if world == null:
		return null
	if not world.place_building(Buildings.Type.ACCUMULATOR, ACC_POS):
		_check(failures, false, "%s SETUP: accumulator placement at %s failed" % [label, str(ACC_POS)])
		_disconnect(world); world.queue_free()
		return null
	var acc: Building = world.building_at(ACC_POS)
	acc.state["charge"] = EPS_CHARGE
	return world

## Recompute the network and confirm it is the scenario the caller thinks it
## is BEFORE anything is timed against it — supply and demand asserted
## alongside satisfaction so layout drift reports as the wrong number, not
## as a mysterious timing failure later.
static func _verified_sat(world, failures: Array, label: String, want_supply: int, want_demand: int, want_sat: float) -> void:
	PowerNetwork.update_supply_demand(world)
	var comp: int = PowerNetwork.network_id_at(world, POLE_POS)
	if comp < 0:
		_check(failures, false, "%s SETUP: pole at %s is not in a power network" % [label, str(POLE_POS)])
		return
	var supply: int = PowerNetwork.supply_for(world, comp)
	var demand: int = PowerNetwork.demand_for(world, comp)
	var sat: float = PowerNetwork.satisfaction_for(world, comp)
	_check(failures, supply == want_supply,
		"%s SETUP: component supply should be %d, got %d" % [label, want_supply, supply])
	_check(failures, demand == want_demand,
		"%s SETUP: component demand should be %d, got %d — a missing 10 means the ELECTRIC_DRILL arm is absent from update_supply_demand Stage 1" % [label, want_demand, demand])
	_check(failures, is_equal_approx(sat, want_sat),
		"%s SETUP: satisfaction should be %.3f (supply %d / demand %d), got %.6f — a trajectory built on an unverified satisfaction proves nothing" % [label, want_sat, supply, demand, sat])

static func _save_cleanup(world, player_a, world_b, player_b, orig_path: String) -> void:
	_disconnect(world)
	if world != null: world.queue_free()
	if player_a != null: player_a.queue_free()
	_disconnect(world_b)
	if world_b != null: world_b.queue_free()
	if player_b != null: player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
