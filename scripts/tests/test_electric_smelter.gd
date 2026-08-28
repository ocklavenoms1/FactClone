extends RefCounted

## Electric smelter — session-electricity-processors, Tasks 2 + 3.
##
## Task 2 pinned the ELECTRIC_SMELTER registry row: the on-disk enum integer,
## the DATA row shape (name / footprint / overlays / direction), the no-fuel
## slot layout, the make() dispatch type, and the swatch colour (sub-cases
## 1-5). Task 3 adds the power half (sub-cases 6-16):
##
##   6.  Module tables + the two-direction burner guard: POWER_EPSILON pinned
##       to the literal 0.05, power_demand 10/0, is_electric true/false.
##   7.  The effective-target arithmetic, direct calls on a stub world:
##       sat 0.00 → 640 (pins epsilon + ratio + ceil in one literal),
##       sat 1.00 → 32, burner at sat 0.00 → 40 unchanged.
##   8.  sat 1.00 trajectory — two-sample protocol at both batch boundaries
##       (31/32 and 63/64).
##   9.  sat 0.50 brownout trajectory — T_eff 64; samples 63/64 and 127/128.
##  10.  The epsilon boundary — satisfaction EXACTLY 0.05 parks the machine
##       (state 4, the `<=` decision); inputs stay at full preload.
##  11.  Constant demand — component demand is the literal 10 while IDLE and
##       while SMELTING, asserted with `==` in both states.
##  12.  3a fuel sentinel — a poked fuel_buffer is never consumed.
##  13.  3b wood on the fuel-port belt is never eaten.
##  14.  Q3 dual-pin freeze — mid-batch outage: progress HELD at the cut
##       value AND the wall-clock completion identity (first output at
##       start + outage + T_eff).
##  15.  Q4 shape assertion — make()'s state key set as a sorted literal.
##  16.  Save round-trip mid-batch — type int 37, progress preserved,
##       resumes to completion on the right tick.
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. Nothing here asks Buildings for its
## own expectation: the enum integer is written as 37 (re-derived by hand on
## 2026-08-27 from the enum tail — UNDERGROUND_BELT_EXIT is 36), the footprint
## as Vector2i(2, 2), the burner smelter's swatch as the Color literal from
## its DATA row. An `int(Buildings.Type.ELECTRIC_SMELTER) ==
## int(Buildings.Type.ELECTRIC_SMELTER)` round-trip would be the module
## confirming itself.
##
## COLOUR FLOOR NOTE: test_inserter_body_colours.gd's ΔE ≥ 25 floor is scoped
## to Inserter.BODY_COLOR_BY_TYPE — inserter tiers only. DATA swatch colours
## are OUTSIDE its domain, so the electric processors' swatches are pinned
## HERE instead, reusing that suite's L*a*b* maths as a measuring instrument
## (the colour maths is not the module under test; the floor and both swatch
## literals are this file's own).

const ColourMath = preload("res://scripts/tests/test_inserter_body_colours.gd")
const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Distinct filename from every other suite's save path so round-trip tests
# cannot collide if the runner order ever changes (the electric-inserter
# suite's convention).
const TEST_SAVE_PATH: String = "user://test_electric_smelter.json"

## Hand-chosen swatch literals (2026-08-27). The DATA row must carry the
## electric literal EXACTLY (sub-case 5 pins it), and the row's actual value
## must clear the ΔE floor against both colours it could be confused with:
## the burner smelter it sits beside on the map, and the electric drill it
## sits beside on the hotbar.
const SWATCH_ELECTRIC_SMELTER := Color(0.10, 0.42, 0.50)  # deep electric teal
const SWATCH_ELECTRIC_DRILL := Color(0.48, 0.72, 0.68)    # pale cyan-green (drill suite pins it)
const SWATCH_BURNER_SMELTER := Color(0.30, 0.28, 0.25)    # SMELTER DATA row, re-derived by hand
const FLOOR_DE: float = 25.0

# ---------------------------------------------------------------------------
# Task 3 rig layout. One stone patch, (6..12)x(5..11). The pole at (9,7) is
# the component everything hangs off: both windmills touch it cardinally
# (generator rule, _adjacent_component_id), the smelter's anchor cell (8,8)
# sits inside the basic pole's 3x3 supply box (8,6)..(10,8) (consumer rule,
# _supply_component_id), and the two ballast lamps / the accumulator take
# free covered cells at (9,6)/(10,6).
# ---------------------------------------------------------------------------
const WINDMILL_A_POS: Vector2i = Vector2i(7, 6)
const WINDMILL_B_POS: Vector2i = Vector2i(10, 6)
const POLE_POS: Vector2i       = Vector2i(9, 7)
const SMELTER_POS: Vector2i    = Vector2i(8, 8)
const LAMP_A_POS: Vector2i     = Vector2i(9, 6)   # brownout world only
const LAMP_B_POS: Vector2i     = Vector2i(10, 6)  # brownout world only (windmill B absent there)
const ACC_POS: Vector2i        = Vector2i(9, 6)   # epsilon world only (cardinal to the pole)
# The smelter faces canonical east, so its fuel port is the world S edge:
# cells (8,10) and (9,10). The 3b belt sits on the first of them.
const FUEL_BELT_POS: Vector2i  = Vector2i(8, 10)

# Power units drawn by one ELECTRIC_SMELTER — a LITERAL, never read back from
# smelter.gd's table (locked at the design pass: 10, 2x the electric
# inserter's 5; four smelters = 40 = exactly two steam generators).
const ELECTRIC_DEMAND: int = 10

# Full-power world: two windmills at 6 each. 12 supply / 10 demand → sat 1.0.
const FULL_SUPPLY: int = 12
# Brownout world: ONE windmill (6), demand 10 (smelter) + 2 lamps = 12.
# 6 / 12 = 0.5 exactly.
const BROWNOUT_SUPPLY: int = 6
const BROWNOUT_DEMAND: int = 12
# Epsilon world: NO generator; one accumulator poked to charge 0.5. The
# pre-pass discharges min(deficit 10, MAX_DISCHARGE_RATE 5, charge 0.5) =
# 0.5, so satisfaction = 0.5 / 10 = 0.05 — the accumulator-discharge trick
# from test_electric_inserter.gd sub-case 10: discharge is the one FLOAT
# term in the supply arithmetic, and 0.5 and 10 are exactly representable,
# so the quotient is the same double as the literal 0.05.
const EPS_CHARGE: float = 0.5

# Hand-derivation (2026-08-27) of the sat-1.00 completion ticks, from
# smelter.gd's tick order (re-read at efd09cf):
#   tick 1:      state IDLE → _maybe_select_recipe pins smelt_iron; the IDLE
#                arm commits INSTANTLY on the same tick — _consume_inputs
#                takes ore #1 (2→1) and progress is SET TO 1, so the commit
#                tick is also the first progress tick. (The burner literals
#                in test_smelter.gd already imply this: 4 ingots land at
#                40/80/120/160, gapless, from a 40-tick recipe.)
#   ticks 2..31: SMELTING arm, progress +1 per tick → progress == t.
#   tick 32:     progress reaches 32 == T_eff (ceil(40 x 0.8) / sat 1.0) →
#                emit ingot #1, progress 0, back to IDLE (room available).
#   tick 33:     IDLE commits batch #2 (ore 1→0), progress 1.
#   tick 64:     progress 32 → ingot #2.
# So the FIRST ingot lands at tick 32 (not 64); the SECOND at 64. Sampled
# one tick either side of each boundary (the two-sample protocol): a
# machine that is merely "roughly right" cannot satisfy both samples.
const SAT100_SAMPLES: Array = [[31, 0], [32, 1], [63, 1], [64, 2]]

# Same derivation at sat 0.50: T_eff = ceil(32 / 0.5) = 64, recomputed per
# tick from LIVE satisfaction (target-stretch, the locked brownout rule).
# Commit on tick 1, ingot #1 at tick 64, commit #2 at 65, ingot #2 at 128.
const SAT050_SAMPLES: Array = [[63, 0], [64, 1], [127, 1], [128, 2]]

# Sub-case 10 window: 40 direct ticks at the boundary — one full rated
# burner cycle, and longer than T_eff 32, so a machine that RAN instead of
# parking would have produced (at `<` instead of `<=` it commits on tick 1
# and the input preload drops — that consumption is the discriminator).
const EPS_STALL_TICKS: int = 40

# Sub-case 12: 100 ticks covers two full electric batches (32 + 32) with
# slack — and would cover two burner batches (40 + 40) too, so the sanity
# "it really ran" assertion cannot fail for a mere speed reason.
const SENTINEL_RUN_TICKS: int = 100
const FUEL_SENTINEL: int = 7

# Sub-case 14 (Q3 dual-pin) numbers, with the identity written out
# (T_eff = 32, e = FREEZE_E, O = FREEZE_OUTAGE):
#   powered ticks 1..10   — commit on tick 1; progress == e == 10 at the cut
#   outage ticks 11..60   — parked (state 4); progress HELD at 10
#   restore; ticks 61..82 — progress 11..32; T_eff reached after
#                           T_eff − e = 22 more ticks
#   first output at machine tick e + O + (T_eff − e) = O + T_eff
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

# Sub-case 16: save at the same mid-batch point (progress 10), so the
# post-load resume completes after the same 22-tick remainder.
const SAVE_PRE_TICKS: int = 10
const SAVE_REMAINDER: int = 22

static func test_name() -> String:
	return "electric smelter (registry row + power tables + effective target + trajectories + epsilon boundary + constant demand + fuel sentinels + freeze dual-pin + make() shape + save round-trip)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_1_enum_int(failures)
	_case_2_data_row_shape(failures)
	_case_3_no_fuel_slot(failures)
	_case_4_make_type_pin(failures)
	_case_5_swatch_colour(failures)
	_case_6_power_tables(failures)
	_case_7_effective_target(failures)
	_case_8_full_power_trajectory(parent, failures)
	_case_9_brownout_trajectory(parent, failures)
	_case_10_epsilon_boundary(parent, failures)
	_case_11_constant_demand(parent, failures)
	_case_12_fuel_sentinel(parent, failures)
	_case_13_wood_belt_not_eaten(parent, failures)
	_case_14_freeze_dual_pin(parent, failures)
	_case_15_make_shape(failures)
	_case_16_save_roundtrip(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "16 sub-cases pass: registry row (1-5) + power tables + effective target + both trajectories + epsilon boundary + constant demand + fuel sentinel + wood-belt guard + freeze dual-pin + make() shape + save round-trip" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) THE ON-DISK INTEGER. The save format pins this forever: a save written
# today holds `"t": 37` and must load as an electric smelter in every future
# build. The literal is the assertion — a symbolic comparison could drift
# with the enum and stay green.
# ===========================================================================
static func _case_1_enum_int(failures: Array) -> void:
	if int(Buildings.Type.ELECTRIC_SMELTER) != 37:
		failures.append("(1) Buildings.Type.ELECTRIC_SMELTER is %d, expected the literal 37 — the append-only rule broke, and every save carrying a 37 now loads as the wrong machine"
			% int(Buildings.Type.ELECTRIC_SMELTER))

# ===========================================================================
# (2) DATA ROW SHAPE — mirrors the burner SMELTER row minus fuel.
# ===========================================================================
static func _case_2_data_row_shape(failures: Array) -> void:
	if Buildings.name_of(Buildings.Type.ELECTRIC_SMELTER) != "Electric Smelter":
		failures.append("(2) name is '%s', expected 'Electric Smelter'"
			% Buildings.name_of(Buildings.Type.ELECTRIC_SMELTER))
	if Buildings.footprint_of(Buildings.Type.ELECTRIC_SMELTER) != Vector2i(2, 2):
		failures.append("(2) footprint is %s, expected Vector2i(2, 2) — must match the burner smelter"
			% str(Buildings.footprint_of(Buildings.Type.ELECTRIC_SMELTER)))
	var overlays: Array = Buildings.requires_overlay(Buildings.Type.ELECTRIC_SMELTER)
	if overlays != [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH]:
		failures.append("(2) requires_overlay is %s, expected [NONE, STONE, PATH] — must match the burner smelter" % str(overlays))
	if not Buildings.supports_direction(Buildings.Type.ELECTRIC_SMELTER):
		failures.append("(2) supports_direction is false, expected true — all 3 ports rotate together like the burner's")

# ===========================================================================
# (3) NO FUEL SLOT, asserted over the ACTUAL layout: sweep every slot for a
# "fuel" id or kind, AND pin the id list exactly. The sweep alone would stay
# green on an empty layout; the exact id list catches that.
# ===========================================================================
static func _case_3_no_fuel_slot(failures: Array) -> void:
	var layout: Array = Buildings.slot_layout_for(Buildings.Type.ELECTRIC_SMELTER)
	var ids: Array = []
	for slot in layout:
		ids.append(str(slot.get("id", "")))
		if str(slot.get("kind", "")) == "fuel" or str(slot.get("id", "")) == "fuel":
			failures.append("(3) slot_layout carries a fuel slot (%s) — the electric tier draws from the power network, never from a fuel buffer" % str(slot))
	if ids != ["input", "output"]:
		failures.append("(3) slot ids are %s, expected exactly ['input', 'output'] — the burner layout minus its fuel slot" % str(ids))

# ===========================================================================
# (4) make() STAMPS THE ELECTRIC TYPE. Smelter.make hardcoded the burner
# enum before this session; the ELECTRIC_SMELTER dispatch arm must produce a
# building whose type is the on-disk 37, or every electric smelter saves as
# a burner and loads with a fuel slot.
# ===========================================================================
static func _case_4_make_type_pin(failures: Array) -> void:
	var b: Building = Buildings.make(Buildings.Type.ELECTRIC_SMELTER, Vector2i(3, 3))
	if b == null:
		failures.append("(4) Buildings.make(ELECTRIC_SMELTER, ...) returned null — no make() dispatch arm")
		return
	if int(b.type) != 37:
		failures.append("(4) make(ELECTRIC_SMELTER).type is %d, expected the literal 37 — the arm delegates to a make() that hardcodes the burner enum" % int(b.type))

# ===========================================================================
# (5) SWATCH COLOUR: the exact literal, plus ΔE ≥ 25 against the burner
# smelter and against the electric drill, measured on the ROW'S OWN VALUE so
# a drifted row cannot hide behind a green literal-vs-literal distance.
# ===========================================================================
static func _case_5_swatch_colour(failures: Array) -> void:
	var actual: Color = Buildings.swatch_color_of(Buildings.Type.ELECTRIC_SMELTER)
	if actual != SWATCH_ELECTRIC_SMELTER:
		failures.append("(5) swatch is %s, expected the pinned literal %s" % [str(actual), str(SWATCH_ELECTRIC_SMELTER)])
	var d_burner: float = ColourMath.delta_e(actual, SWATCH_BURNER_SMELTER)
	if d_burner < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the burner smelter's %s (floor %.1f) — the two smelters would read as shades of one another"
			% [str(actual), d_burner, str(SWATCH_BURNER_SMELTER), FLOOR_DE])
	var d_sibling: float = ColourMath.delta_e(actual, SWATCH_ELECTRIC_DRILL)
	if d_sibling < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the electric drill's %s (floor %.1f) — the two electric processors would read as shades of one another"
			% [str(actual), d_sibling, str(SWATCH_ELECTRIC_DRILL), FLOOR_DE])

# ===========================================================================
# (6) MODULE TABLES + THE TWO-DIRECTION BURNER GUARD (the electric-inserter
# (2a) pattern, both directions per half). power_demand reads the table with
# .get(t, 0) and is_electric with .has(t) — asserting BOTH on the burner
# catches the worse drift, a stray row valued 0 that silently routes the
# burner off its fuel path while looking like it draws nothing.
# ===========================================================================
static func _case_6_power_tables(failures: Array) -> void:
	# POWER_EPSILON pinned to the LITERAL 0.05 — documented-equal to
	# Inserter.POWER_EPSILON (the lamp's on/off threshold). Drift here would
	# silently re-rate the brownout floor, and the 640 literal in sub-case 7
	# would start disagreeing with the module's own arithmetic.
	_check(failures, Smelter.POWER_EPSILON == 0.05,
		"(6) Smelter.POWER_EPSILON must be the literal 0.05, got %s — it is documented-equal to Inserter.POWER_EPSILON and the shared lamp threshold" % str(Smelter.POWER_EPSILON))
	_check(failures, Smelter.power_demand(Buildings.Type.ELECTRIC_SMELTER) == 10,
		"(6) power_demand(ELECTRIC_SMELTER) must be the literal 10, got %d" % Smelter.power_demand(Buildings.Type.ELECTRIC_SMELTER))
	# The burner direction — BOTH reads of the table.
	_check(failures, Smelter.power_demand(Buildings.Type.SMELTER) == 0,
		"(6) power_demand(SMELTER) must stay 0, got %d — a burner registering demand would drag down every real consumer on its network" % Smelter.power_demand(Buildings.Type.SMELTER))
	var burner: Building = Smelter.make(Vector2i(0, 0), Belt.DIR_E)
	_check(failures, Smelter.is_electric(burner) == false,
		"(6) is_electric(burner smelter) must stay false — true would skip the whole fuel path in tick()")
	var elec: Building = Smelter.make(Vector2i(0, 0), Belt.DIR_E, Buildings.Type.ELECTRIC_SMELTER)
	_check(failures, Smelter.is_electric(elec) == true,
		"(6) is_electric(electric smelter) should be true — the variant is defined by its POWER_DEMAND_BY_TYPE row")

# ===========================================================================
# (7) THE EFFECTIVE-TARGET ARITHMETIC, direct calls on a stub world (pure
# arithmetic only — behaviour is asserted on real networks in 8-14). The
# recipe is a LITERAL dict carrying the smelt rows' time_ticks 40, so
# nothing here asks smelter.gd (or recipes.gd) for its own expectation.
# ===========================================================================
static func _case_7_effective_target(failures: Array) -> void:
	var recipe: Dictionary = { "time_ticks": 40 }
	var elec: Building = Smelter.make(Vector2i(0, 0), Belt.DIR_E, Buildings.Type.ELECTRIC_SMELTER)
	var burner: Building = Smelter.make(Vector2i(0, 0), Belt.DIR_E)
	# sat 0.00 → ceil(ceil(40 x 0.8) / max(0.05, 0.0)) = ceil(32 / 0.05) =
	# 640. This one literal pins the epsilon (0.05), the speed ratio (0.8)
	# AND the rounding mode (ceil) together — floor or round of 32/0.05
	# agree at 640, but a drifted epsilon or ratio cannot land on it.
	var at_zero: int = Smelter._effective_target(elec, StubPowerWorld.new(0.0), recipe)
	_check(failures, at_zero == 640,
		"(7) electric target at satisfaction 0.00 must be the literal 640 = ceil(32 / 0.05), got %d" % at_zero)
	# sat 1.00 → 32: the DATA-comment claim, electric 32 vs burner 40.
	var at_full: int = Smelter._effective_target(elec, StubPowerWorld.new(1.0), recipe)
	_check(failures, at_full == 32,
		"(7) electric target at satisfaction 1.00 must be the literal 32 = ceil(40 x 0.8), got %d" % at_full)
	# The burner returns its rated 40 UNCHANGED — and must return BEFORE the
	# satisfaction lookup, or a world with no power network (satisfaction
	# 0.0 everywhere) would stretch every burner smelter to 640 ticks.
	var burner_t: int = Smelter._effective_target(burner, StubPowerWorld.new(0.0), recipe)
	_check(failures, burner_t == 40,
		"(7) burner target must stay the rated 40 at ANY satisfaction, got %d — %d would mean the satisfaction divisor reached the fuel tier" % [burner_t, 640])

# ===========================================================================
# (8) SAT 1.00 TRAJECTORY. The whole speed decision in four literals: the
# first ingot at tick 32 (electric base = ceil(40 x 0.8), NOT the burner's
# 40 and NOT the plan's misremembered 64), the second at 64, each boundary
# sampled from both sides. See SAT100_SAMPLES for the hand-derivation.
# ===========================================================================
static func _case_8_full_power_trajectory(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(8)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	_verified_sat(world, failures, "(8)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	_run_samples(sm, SAT100_SAMPLES, failures, "(8)", "sat 1.00")
	_check(failures, _in_count(sm) == 0,
		"(8) both preloaded ore should be consumed by tick 64, %d left" % _in_count(sm))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (9) SAT 0.50 BROWNOUT TRAJECTORY — target-stretch, not rate-scaling. Int
# progress advances 1 per tick; the TARGET is recomputed per tick from live
# satisfaction, so at 0.5 the 32-tick batch stretches to 64. Second ingot at
# the literal 128 — a machine still running its rated 32 would have finished
# four batches by then, and a burner-based 40 would put the second at 80;
# neither can satisfy the 63/64 and 127/128 sample pairs.
# ===========================================================================
static func _case_9_brownout_trajectory(parent: Node, failures: Array) -> void:
	var world = _build_brownout_world(parent, failures, "(9)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	_verified_sat(world, failures, "(9)", BROWNOUT_SUPPLY, BROWNOUT_DEMAND, 0.5)
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	_run_samples(sm, SAT050_SAMPLES, failures, "(9)", "sat 0.50")
	_disconnect(world); world.queue_free()

# ===========================================================================
# (10) THE EPSILON BOUNDARY. Satisfaction EXACTLY 0.05 must PARK the machine
# — the cutoff is `<=`, the same boundary the electric inserter and the
# lamp's glow share, so all three consumers give up at the same point on the
# dial. Direct ticks (Buildings.tick_one), NOT TickSystem: the grid pre-pass
# would drain the accumulator to 0.0 on the first tick and the boundary
# claim would go untested — the electric-inserter suite documents the same
# constraint on its epsilon rig.
#
# The discriminator against `<`: at `<` the machine would COMMIT on tick 1
# (satisfaction 0.05 is not below 0.05), consuming an ore and entering
# SMELTING — so "inputs still at full preload" and "state == 4" both break.
# ===========================================================================
static func _case_10_epsilon_boundary(parent: Node, failures: Array) -> void:
	var world = _build_epsilon_world(parent, failures, "(10)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	PowerNetwork.update_supply_demand(world)
	var comp: int = PowerNetwork.network_id_at(world, POLE_POS)
	if comp < 0:
		_check(failures, false, "(10) SETUP: pole at %s is not in a power network" % str(POLE_POS))
		_disconnect(world); world.queue_free()
		return
	_check(failures, PowerNetwork.demand_for(world, comp) == ELECTRIC_DEMAND,
		"(10) SETUP: the only consumer should be the smelter (demand %d), got %d" % [ELECTRIC_DEMAND, PowerNetwork.demand_for(world, comp)])
	var sat: float = world.power_satisfaction_at(SMELTER_POS)
	_check(failures, sat == 0.05,
		"(10) SETUP: the smelter's own lookup should see EXACTLY 0.05 (accumulator discharge 0.5 / demand 10), got %.6f — a boundary assertion built beside the boundary proves nothing" % sat)
	for _i in EPS_STALL_TICKS:
		Buildings.tick_one(sm, world)
	_check(failures, int(sm.state.get("state", -1)) == 4,
		"(10) at satisfaction exactly 0.05 the electric smelter must park in STATE_NO_POWER (the literal 4): got state %d. 2 here means the machine reached the burner's NO_FUEL — the exact state an electric machine must never show; 1 means `<` instead of `<=`" % int(sm.state.get("state", -1)))
	_check(failures, _out_count(sm) == 0,
		"(10) a parked machine must produce NOTHING across %d ticks, got %d ingots" % [EPS_STALL_TICKS, _out_count(sm)])
	_check(failures, _in_count(sm) == 2,
		"(10) inputs must stay at the FULL preload of 2 — got %d. A missing ore means the IDLE arm committed a batch at the boundary (`<` instead of `<=`)" % _in_count(sm))
	_check(failures, int(sm.state.get("progress", -1)) == 0,
		"(10) progress must stay 0 while parked from IDLE, got %d" % int(sm.state.get("progress", -1)))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (11) CONSTANT DEMAND — the locked decision: the electric smelter demands
# its 10 whenever placed, IDLE or SMELTING alike. Duty-cycling is undamped
# feedback (the pre-pass runs before the building loop, so any activity it
# sampled is one tick stale — see the ELECTRIC_INSERTER arm's rationale).
# Asserted with `==` in BOTH states, then `==` between them: a `>=` would
# bless a duty-cycled implementation in the idle half.
# ===========================================================================
static func _case_11_constant_demand(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(11)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	# --- IDLE: empty in_buffer, never ticked ---
	_check(failures, int(sm.state.get("state", -1)) == 0,
		"(11) SETUP: a fresh electric smelter should be IDLE (0), got %d" % int(sm.state.get("state", -1)))
	PowerNetwork.update_supply_demand(world)
	var comp: int = PowerNetwork.network_id_at(world, POLE_POS)
	if comp < 0:
		_check(failures, false, "(11) SETUP: pole at %s is not in a power network" % str(POLE_POS))
		_disconnect(world); world.queue_free()
		return
	var demand_idle: int = PowerNetwork.demand_for(world, comp)
	_check(failures, demand_idle == 10,
		"(11) component demand with the smelter IDLE should be the literal 10, got %d — 0 means the ELECTRIC_SMELTER consumer arm is missing from PowerNetwork.update_supply_demand Stage 1" % demand_idle)
	# --- SMELTING: preload ore, one tick commits ---
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	_tick(1)
	_check(failures, int(sm.state.get("state", -1)) == 1,
		"(11) SETUP: one powered tick should commit the batch (state SMELTING = 1), got %d" % int(sm.state.get("state", -1)))
	PowerNetwork.update_supply_demand(world)
	var demand_smelting: int = PowerNetwork.demand_for(world, comp)
	_check(failures, demand_smelting == 10,
		"(11) component demand with the smelter SMELTING should be the literal 10, got %d" % demand_smelting)
	_check(failures, demand_idle == demand_smelting,
		"(11) demand must be CONSTANT (no duty-cycling): idle drew %d, smelting drew %d" % [demand_idle, demand_smelting])
	_disconnect(world); world.queue_free()

# ===========================================================================
# (12) 3a FUEL SENTINEL. Q4's locked shape: the Burner fields exist on the
# electric variant (make_state merge stays) but are DEAD. A sentinel poked
# into fuel_buffer must survive a full production run untouched — this is
# the case that catches a live Burner.consume_tick, which a fuel_buffer of 0
# never can (consume_tick is a no-op on an empty buffer).
# ===========================================================================
static func _case_12_fuel_sentinel(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(12)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	sm.state["fuel_buffer"] = FUEL_SENTINEL
	sm.state["fuel_burn_progress"] = 0
	_tick(SENTINEL_RUN_TICKS)
	_check(failures, _out_count(sm) == 2,
		"(12) SETUP: the smelter should have completed both batches inside %d ticks (otherwise the sentinel assertion is vacuous), got %d ingots" % [SENTINEL_RUN_TICKS, _out_count(sm)])
	_check(failures, int(sm.state.get("fuel_buffer", -1)) == FUEL_SENTINEL,
		"(12) the electric smelter must never consume fuel: fuel_buffer should still be the sentinel %d after a full batch run, got %d" % [FUEL_SENTINEL, int(sm.state.get("fuel_buffer", -1))])
	_check(failures, int(sm.state.get("fuel_burn_progress", -1)) == 0,
		"(12) fuel_burn_progress must never advance on the electric tier, got %d" % int(sm.state.get("fuel_burn_progress", -1)))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (13) 3b WOOD ON THE FUEL-PORT BELT IS NOT EATEN. The burner smelter pulls
# fuel from its S edge; the electric smelter has no fuel path, so wood
# passing that same edge on a belt must stay on the belt — the
# source-tile-as-fuel bug (session-inserter-fast-filter PAUSE 1) from the
# other direction. The belt runs parallel (dir E) so nothing else can
# account for the wood leaving.
# ===========================================================================
static func _case_13_wood_belt_not_eaten(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(13)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	if not world.place_building(Buildings.Type.BELT, FUEL_BELT_POS, Belt.DIR_E):
		_check(failures, false, "(13) SETUP: belt placement at %s failed" % str(FUEL_BELT_POS))
		_disconnect(world); world.queue_free()
		return
	var belt: Building = world.building_at(FUEL_BELT_POS)
	belt.state["slots"][0] = Items.Type.WOOD
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 1]]
	_tick(60)
	_check(failures, _out_count(sm) == 1,
		"(13) SETUP: the smelter should have produced its one ingot inside 60 ticks (otherwise the wood assertion is vacuous), got %d" % _out_count(sm))
	_check(failures, _belt_item_count(belt, Items.Type.WOOD) == 1,
		"(13) the wood must STAY on the fuel-port belt: expected 1 on the belt, found %d — 0 means the electric smelter pulled it as fuel" % _belt_item_count(belt, Items.Type.WOOD))
	_check(failures, int(sm.state.get("fuel_buffer", -1)) == 0,
		"(13) fuel_buffer must stay 0 (nothing pulled), got %d" % int(sm.state.get("fuel_buffer", -1)))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (14) Q3 DUAL-PIN FREEZE. A mid-batch outage is pinned from BOTH ends
# (locked at the design pass — the user's own requirement):
#   (i)  at cut + O: progress == e EXACTLY and the buffers unchanged —
#        the freeze preserved the elapsed work;
#   (ii) the wall-clock completion identity: the first output lands at
#        machine tick e + O + (T_eff − e) = O + T_eff = 82 — the resume
#        spent the outage, kept the elapsed work, and consumed NOTHING new.
# (ii) is the stronger pin: a resume that re-enters through the IDLE arm
# re-commits the batch (progress reset AND a second ore consumed) yet still
# eventually produces — (i) alone stays green on it; the 82-tick identity
# does not. See FREEZE_E's constraint comment for why O mod T_eff ≠ 0.
# ===========================================================================
static func _case_14_freeze_dual_pin(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(14)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	_verified_sat(world, failures, "(14)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	_tick(FREEZE_E)
	_check(failures, int(sm.state.get("progress", -1)) == FREEZE_E,
		"(14) PREMISE: after %d powered ticks progress should be %d (commit on tick 1, +1 per tick), got %d — the outage below must be taken MID-BATCH or the freeze claim is vacuous" % [FREEZE_E, FREEZE_E, int(sm.state.get("progress", -1))])
	_check(failures, int(sm.state.get("state", -1)) == 1,
		"(14) PREMISE: the machine should be SMELTING (1) at the cut, got %d" % int(sm.state.get("state", -1)))
	_check(failures, _in_count(sm) == 1 and _out_count(sm) == 0,
		"(14) PREMISE: at the cut exactly one ore is committed (1 left) and nothing emitted, got in %d out %d" % [_in_count(sm), _out_count(sm)])
	_check(failures, world.remove_building_at(POLE_POS),
		"(14) SETUP: removing the pole at %s should succeed" % str(POLE_POS))
	_tick(FREEZE_OUTAGE)
	# --- (i) the at-M elapsed pin ---
	_check(failures, int(sm.state.get("progress", -1)) == FREEZE_E,
		"(14) THE FREEZE: after a %d-tick outage progress must still be EXACTLY %d, got %d — more means the outage path kept incrementing (a crawl or a full-rate drain), less means something reset the batch" % [FREEZE_OUTAGE, FREEZE_E, int(sm.state.get("progress", -1))])
	_check(failures, int(sm.state.get("state", -1)) == 4,
		"(14) the outage must park the machine in STATE_NO_POWER (the literal 4), got %d" % int(sm.state.get("state", -1)))
	_check(failures, _in_count(sm) == 1 and _out_count(sm) == 0,
		"(14) buffers must be UNCHANGED across the outage: expected in 1 / out 0, got in %d / out %d" % [_in_count(sm), _out_count(sm)])
	# --- power back; (ii) the wall-clock identity ---
	_check(failures, world.place_building(Buildings.Type.POWER_POLE, POLE_POS),
		"(14) SETUP: re-placing the pole at %s should succeed" % str(POLE_POS))
	_tick(FREEZE_REMAINDER - 1)   # machine ticks 61..81 — one short of the identity
	_check(failures, _out_count(sm) == 0,
		"(14) output landed EARLY: at machine tick %d (one before the identity) the output should still be empty, got %d — the resume was credited work it never did" % [FREEZE_E + FREEZE_OUTAGE + FREEZE_REMAINDER - 1, _out_count(sm)])
	_tick(1)                      # machine tick 82 = e + O + (T_eff − e) = O + T_eff
	_check(failures, _out_count(sm) == 1,
		"(14) THE COMPLETION IDENTITY: the first ingot must land at machine tick %d = e(%d) + outage(%d) + remainder(%d), got %d ingots there — later means the resume re-entered through the IDLE arm and re-committed the batch (the reset-AND-double-consume hazard), never means the machine froze for good" % [FREEZE_E + FREEZE_OUTAGE + FREEZE_REMAINDER, FREEZE_E, FREEZE_OUTAGE, FREEZE_REMAINDER, _out_count(sm)])
	_check(failures, _in_count(sm) == 1,
		"(14) the resume must consume NOTHING: the second ore should still be waiting at tick 82, got %d in the buffer — 0 means the batch was re-committed from IDLE on resume" % _in_count(sm))
	_disconnect(world); world.queue_free()

# ===========================================================================
# (15) Q4 SHAPE ASSERTION. The electric variant's state key set, pinned as a
# sorted literal at make(). The Burner merge STAYS on the electric variant
# (locked Q4: fuel fields present-but-unused), so the set is the burner's
# set — and this assertion is the ONLY guard that notices a key quietly
# dropped or added: every reader of these keys on the smelter tick path is
# a defensive .get() that would silently paper over an absence, and the
# state machine self-heals most of them on the first commit. The protection
# must not rest on a crash-by-absence — it rests here.
# ===========================================================================
static func _case_15_make_shape(failures: Array) -> void:
	var elec: Building = Smelter.make(Vector2i(0, 0), Belt.DIR_E, Buildings.Type.ELECTRIC_SMELTER)
	var keys: Array = elec.state.keys()
	keys.sort()
	var want: Array = ["dir", "fuel_buffer", "fuel_burn_progress", "in_buffer", "last_fuel_item", "out_buffer", "progress", "recipe_id", "state"]
	_check(failures, keys == want,
		"(15) make(ELECTRIC_SMELTER) state keys must be exactly %s (sorted), got %s — the electric variant deliberately keeps the burner's full shape, fuel fields present-but-unused" % [str(want), str(keys)])

# ===========================================================================
# (16) SAVE ROUND-TRIP MID-BATCH. A powered electric smelter saved at
# progress 10 must come back as type 37 with its progress intact, and — the
# half a field-compare cannot fake — RESUME to completion at the right tick:
# 22 more ticks (T_eff 32 − 10), sampled from both sides.
# ===========================================================================
static func _case_16_save_roundtrip(parent: Node, failures: Array) -> void:
	var world = _build_powered_world(parent, failures, "(16)")
	if world == null:
		return
	var sm: Building = world.building_at(SMELTER_POS)
	_verified_sat(world, failures, "(16)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 2]]
	_tick(SAVE_PRE_TICKS)
	_check(failures, int(sm.state.get("progress", -1)) == SAVE_PRE_TICKS and int(sm.state.get("state", -1)) == 1,
		"(16) PREMISE: at save time the smelter should be SMELTING (1) at progress %d, got state %d progress %d" % [SAVE_PRE_TICKS, int(sm.state.get("state", -1)), int(sm.state.get("progress", -1))])

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	var player_a := Node2D.new()
	parent.add_child(player_a)
	if not SaveSystem.save_game(world, player_a, Inventory.new(16), {}):
		_check(failures, false, "(16) save_game returned false")
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
		_check(failures, false, "(16) load_game failed: %s" % result.error_message)
		_save_cleanup(world, player_a, world_b, player_b, orig_path)
		return
	var sm_b: Building = world_b.building_at(SMELTER_POS)
	if sm_b == null:
		_check(failures, false, "(16) electric smelter missing at %s after load" % str(SMELTER_POS))
		_save_cleanup(world, player_a, world_b, player_b, orig_path)
		return
	_check(failures, int(sm_b.type) == 37,
		"(16) the loaded building's type must be the on-disk literal 37, got %d — anything else and the save format's pin on the enum is broken" % int(sm_b.type))
	_check(failures, int(sm_b.state.get("progress", -1)) == SAVE_PRE_TICKS,
		"(16) progress must round-trip: saved %d, loaded %d" % [SAVE_PRE_TICKS, int(sm_b.state.get("progress", -1))])
	_check(failures, int(sm_b.state.get("state", -1)) == 1,
		"(16) state must round-trip as SMELTING (1), got %d" % int(sm_b.state.get("state", -1)))
	# The loaded network must actually power the machine before resume is timed.
	_verified_sat(world_b, failures, "(16-loaded)", FULL_SUPPLY, ELECTRIC_DEMAND, 1.0)
	_tick(SAVE_REMAINDER - 1)
	_check(failures, _out_count(sm_b) == 0,
		"(16) resume landed EARLY: one tick before the %d-tick remainder the output should still be empty, got %d" % [SAVE_REMAINDER, _out_count(sm_b)])
	_tick(1)
	_check(failures, _out_count(sm_b) == 1,
		"(16) the loaded machine must resume to completion after exactly %d more ticks (T_eff 32 − progress %d), got %d ingots — 0 here usually means the loaded machine restarted its batch or lost its power hookup" % [SAVE_REMAINDER, SAVE_PRE_TICKS, _out_count(sm_b)])
	_save_cleanup(world, player_a, world_b, player_b, orig_path)

# ---------- helpers (house style, mirroring test_electric_inserter.gd) ----------

## Duck-typed stand-in for GridWorld reporting a satisfaction of the test's
## choosing — _effective_target calls exactly one method on `world`, so a
## two-line RefCounted is a complete implementation of the interface under
## test. Used ONLY for the pure arithmetic in sub-case 7; everything about
## behaviour runs on a real GridWorld with real poles (the electric-inserter
## suite's StubPowerWorld rule).
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

static func _in_count(sm: Building) -> int:
	return _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE)

static func _out_count(sm: Building) -> int:
	return _bag_count(sm.state.get("out_buffer", []), Items.Type.IRON_INGOT)

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

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

## Walk the trajectory tick by tick, sampling the output count at the ticks
## the rows name. Rows are [tick, expected_out] — the two-sample protocol:
## each batch boundary is pinned from both sides.
static func _run_samples(sm: Building, rows: Array, failures: Array, label: String, scenario: String) -> void:
	var by_tick: Dictionary = {}
	for row in rows:
		by_tick[int(row[0])] = int(row[1])
	var last_tick: int = int(rows[rows.size() - 1][0])
	for t in range(1, last_tick + 1):
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if by_tick.has(t):
			var got: int = _out_count(sm)
			_check(failures, got == by_tick[t],
				"%s %s: at machine tick %d the output should hold %d ingot(s), got %d" % [label, scenario, t, by_tick[t], got])

## Stone patch + pole + electric smelter — the base every rig shares.
static func _build_base_world(parent: Node, failures: Array, label: String):
	var world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(6, 13):
		for y in range(5, 12):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.POWER_POLE, POLE_POS):
		_check(failures, false, "%s SETUP: power pole placement at %s failed" % [label, str(POLE_POS)])
		_disconnect(world); world.queue_free()
		return null
	if not world.place_building(Buildings.Type.ELECTRIC_SMELTER, SMELTER_POS, Belt.DIR_E):
		_check(failures, false, "%s SETUP: electric smelter placement at %s failed" % [label, str(SMELTER_POS)])
		_disconnect(world); world.queue_free()
		return null
	return world

## Two windmills (12 supply) against the smelter's 10 → satisfaction 1.0.
static func _build_powered_world(parent: Node, failures: Array, label: String):
	var world = _build_base_world(parent, failures, label)
	if world == null:
		return null
	for wm_pos in [WINDMILL_A_POS, WINDMILL_B_POS]:
		if not world.place_building(Buildings.Type.WINDMILL, wm_pos):
			_check(failures, false, "%s SETUP: windmill placement at %s failed" % [label, str(wm_pos)])
			_disconnect(world); world.queue_free()
			return null
	return world

## ONE windmill (6) against smelter 10 + two ballast lamps = 12 → 0.5.
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

## Pole + smelter + one accumulator poked to EPS_CHARGE, NO generator —
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
## as a mysterious timing failure later (the electric-inserter suite's
## _verified_satisfaction pattern).
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
		"%s SETUP: component demand should be %d, got %d — a missing 10 means the ELECTRIC_SMELTER arm is absent from update_supply_demand Stage 1" % [label, want_demand, demand])
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
