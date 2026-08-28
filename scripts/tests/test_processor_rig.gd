extends RefCounted

## PROCESSOR RIG — headless proof of the Electric Processors PAUSE-gate scenario.
##
## The rig (scripts/world/processor_rig.gd) exists so a human can LOOK at the
## ELECTRIC_SMELTER / ELECTRIC_DRILL brownout path: two of each on one bus,
## demand EXACTLY 40 against 2x20 steam blocks, driven by the same F8 lever as
## the electric rig. This file is the half of that claim a human cannot check
## by looking: that the arithmetic underneath the lever is exact.
##
## Sub-cases:
##   1. The layout lands. Every planned building placed, nothing skipped, ore
##      seeded under both drills, both smelters preloaded.
##   2. BOOT-ORDER PRECONDITION — the first rig tick sees satisfaction 1.0
##      (its own NAMED check; see the block comment on the case).
##   3. One network, demand exactly 40.
##   4. FULL     — satisfaction exactly 1.00; both smelters complete at T_eff
##      32 and both drills produce at 32 (two-sample literals at 31/32/63/64).
##   5. BROWNOUT — satisfaction exactly 0.50; cycles at 64 (63/64/127/128).
##   6. ZERO     — satisfaction exactly 0.00; all four machines in their
##      NO_POWER states (smelter 4, drill 5), progress frozen where the
##      outage found it.
##   7. Lever back to 2 — resume WITHOUT re-consuming: the Q3 rule at rig
##      scale, pinned by one smelter's wall-clock completion identity.
##   8. Spawning onto occupied ground: an intact rig is ADOPTED (deposits and
##      input buffers re-seeded), a lone player-owned smelter on a planned
##      anchor is refused and its buffer left alone.
##
## Demand and placement totals are LITERALS here, not reads from ProcessorRig
## — same reasoning as test_electric_rig.gd's EXPECTED_* block: a constant
## beside the plan gets edited in the same breath as the plan, and the suite
## would ratify the new arithmetic instead of failing on it.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Rig origin used by every sub-case. Non-zero for the same reason as the
# electric rig suite's: the paving rectangle starts at PAVE_MIN = (-1, 1), so
# an origin at (0,0) would let an absolutise sign error hide behind
# coordinates that happen to still be legal.
const ORIGIN: Vector2i = Vector2i(40, 40)

# The two totals the whole design rests on, as LITERALS and deliberately HERE
# rather than in processor_rig.gd (see the file header).
#   16 placements = 2 generators + 6 poles + 2 smelters + 2 drills + 4 chests
#   40 demand     = 2 smelters x 10 + 2 drills x 10
# 40 EXACTLY because supply arrives in 20-unit steam blocks: 20 / 40 is exact
# in binary floating point, so the one-generator lever position is a true
# 0.50 — miss the sum by one machine and the midpoint slides off it.
const EXPECTED_PLACEMENTS: int = 16
const EXPECTED_DEMAND: int = 40

# Machine-cycle facts the rig is built around, as LITERALS rather than reads
# from Smelter/MiningDrill tables (a silent table edit must redden, not be
# ratified): T_eff = ceil(ceil(40 x 0.8) / max(0.05, sat)).
const RATED_CYCLE_TICKS: int = 32       # sat 1.00
const BROWNOUT_CYCLE_TICKS: int = 64    # sat 0.50
# NO_POWER state ints, pinned as save-format literals (append-only enums).
const SMELTER_NO_POWER: int = 4
const DRILL_NO_POWER: int = 5

# Spawn-seed literals (what ProcessorRig writes; pinned here so a quiet
# richness or preload cut reddens instead of shortening the gate session).
const ORE_PRELOAD: int = 400
const ORE_RICHNESS: int = 200

# Two-sample trajectory rows [machine_tick, expected_items_in_chest]. Each
# cycle boundary pinned from both sides. Derivation (re-read at d86bc31):
# smelter commits at tick 1 (progress 1) and emits when p >= T_eff, i.e. at
# tick 32N for item N; the drill's counter reaches T_eff at tick 32N with no
# commit tick. Both machines push to their chest on the SAME tick they
# produce (Processor step 6 / MiningDrill step 6 both end in a push).
const SAT100_SAMPLES: Array = [[31, 0], [32, 1], [63, 1], [64, 2]]
const SAT050_SAMPLES: Array = [[63, 0], [64, 1], [127, 1], [128, 2]]

# Sub-cases 6/7 freeze numbers, with the identity written out
# (T_eff = 32, e = FREEZE_E, O = FREEZE_OUTAGE):
#   powered ticks 1..10   — progress accumulates to e == 10 at the cut
#   outage ticks 11..60   — parked; progress HELD at 10
#   restore; ticks 61..82 — progress 11..32; the batch completes after
#                           T_eff - e = 22 more ticks
#   first ingot at machine tick e + O + (T_eff - e) = O + T_eff = 82.
# Constraints (locked at the design pass): e != 0 (10), e < T_eff (10 < 32),
# O > T_eff - e (50 > 22), O mod T_eff != 0 (50 mod 32 = 18) — the last is
# what stops a full-rate drain-through-the-outage wrapping progress back to e
# and sitting green under the elapsed pin alone.
const FREEZE_E: int = 10
const FREEZE_OUTAGE: int = 50
const FREEZE_IDENTITY_TICK: int = 82    # 10 + 50 + 22

# Sub-case 6's shorter outage window (the freeze check needs held progress,
# not the completion identity — that is sub-case 7's job).
const HOLD_OUTAGE: int = 20

# Sub-case 8's pre-adoption run: 40 ticks = one production from each machine
# kind (smelter commits at 1 and 33 -> in_buffer 398; each drill drains 1
# richness at tick 32 -> anchor deposit 199), so the re-seed on adoption has
# something visible to restore.
const ADOPT_PRE_TICKS: int = 40

static func test_name() -> String:
	return "processor rig (layout lands + boot-order precondition + single network + demand 40 + full 1.00/32t + brownout 0.50/64t + zero freeze + resume identity + adopt-or-refuse)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_layout_lands(parent, failures)
	_case_boot_order_precondition(parent, failures)
	_case_single_network_demand_40(parent, failures)
	_case_full_power_trajectories(parent, failures)
	_case_brownout_trajectories(parent, failures)
	_case_zero_power_freeze(parent, failures)
	_case_resume_identity(parent, failures)
	_case_respawn_and_collision(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "8 sub-cases pass: layout lands + boot-order precondition + single network + demand 40 + full 1.00/32t + brownout 0.50/64t + zero freeze (4/5) + resume identity 82 + adopt-or-refuse on occupied ground" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) THE LAYOUT LANDS.
# Every satisfaction number in this file is downstream of the rig being built
# in full. A skipped generator halves supply; a skipped machine moves demand
# off 40; an unseeded drill cannot even be PLACED (validate_placement wants
# ore), so a zero skip count is also the proof the ore seeding ran.
# ===========================================================================
static func _case_layout_lands(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ProcessorRig.build(world, ORIGIN)

	_check(failures, int(rig["placed"]) == EXPECTED_PLACEMENTS,
		"(1) placed %d buildings, expected %d" % [int(rig["placed"]), EXPECTED_PLACEMENTS])
	_check(failures, int(rig["skipped"]) == 0,
		"(1) %d planned buildings were skipped — the rig is incomplete" % int(rig["skipped"]))
	_check(failures, (rig["gen_anchors"] as Array).size() == 2,
		"(1) expected 2 steam generators, got %d" % (rig["gen_anchors"] as Array).size())
	_check(failures, (rig["smelter_anchors"] as Array).size() == 2,
		"(1) expected 2 electric smelters, got %d" % (rig["smelter_anchors"] as Array).size())
	_check(failures, (rig["drill_anchors"] as Array).size() == 2,
		"(1) expected 2 electric drills, got %d" % (rig["drill_anchors"] as Array).size())

	# Generators must CARDINALLY touch a pole (the GENERATOR rule) — a
	# diagonal miss contributes nothing and is invisible until satisfaction
	# comes out wrong.
	for anchor in rig["gen_anchors"]:
		_check(failures, _touches_pole(world, anchor),
			"(1) steam generator at %s does not cardinally touch a power pole" % str(anchor))

	# Both smelters preloaded to the literal, output chests standing empty.
	for i in (rig["smelter_anchors"] as Array).size():
		var sm: Building = world.building_at((rig["smelter_anchors"] as Array)[i])
		if sm == null or sm.type != Buildings.Type.ELECTRIC_SMELTER:
			_check(failures, false, "(1) no electric smelter at anchor %s" % str((rig["smelter_anchors"] as Array)[i]))
			continue
		_check(failures, _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE) == ORE_PRELOAD,
			"(1) smelter %d in_buffer holds %d iron ore, expected the %d preload" % [i, _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE), ORE_PRELOAD])
	for chest_pos in (rig["smelter_chests"] as Array) + (rig["drill_chests"] as Array):
		_check(failures, _chest_total(world, chest_pos) == 0,
			"(1) output chest at %s should start empty" % str(chest_pos))

	# Both drills cover exactly their own four seeded deposits, each at the
	# full richness literal. covered_deposits order is refresh_covered_deposits'
	# dx-outer/dy-inner walk.
	for anchor in rig["drill_anchors"]:
		var dr: Building = world.building_at(anchor)
		if dr == null or dr.type != Buildings.Type.ELECTRIC_DRILL:
			_check(failures, false, "(1) no electric drill at anchor %s" % str(anchor))
			continue
		var a: Vector2i = anchor
		var want: Array = [[a.x, a.y], [a.x, a.y + 1], [a.x + 1, a.y], [a.x + 1, a.y + 1]]
		_check(failures, dr.state.get("covered_deposits", []) == want,
			"(1) drill at %s covers %s, expected all four footprint deposits %s" % [str(a), str(dr.state.get("covered_deposits", [])), str(want)])
		for cell_pair in want:
			var cell: Vector2i = Vector2i(int(cell_pair[0]), int(cell_pair[1]))
			_check(failures, world.richness_at(cell) == ORE_RICHNESS,
				"(1) deposit at %s has richness %d, expected the %d seed" % [str(cell), world.richness_at(cell), ORE_RICHNESS])

	_teardown(world)

# ===========================================================================
# (2) BOOT-ORDER PRECONDITION (user disposition, 2026-08-27).
# The first rig tick must see satisfaction 1.0 — and that is a CONTRACT on
# tick order, not luck: the power pre-pass (PowerNetwork.update_supply_demand)
# runs BEFORE the building loop in GridWorld._on_tick, so a machine's first
# tick already sees the network truth (ProcessorRig.build seeds output_active
# for the same reason ElectricRig.build does — a generator derives it one
# tick late from fuel). If a future boot or tick reordering breaks that, THIS
# named check reddens and names the suspect, instead of every trajectory
# literal in this suite reddening at once at the wrong one.
# ===========================================================================
static func _case_boot_order_precondition(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ProcessorRig.build(world, ORIGIN)
	_advance(world, 1)

	var sat: float = world.power_satisfaction_at((rig["smelter_anchors"] as Array)[0])
	_check(failures, sat == 1.0,
		"(2) BOOT-ORDER PRECONDITION: the first rig tick saw satisfaction %f, expected exactly 1.0 — the update_supply_demand pre-pass no longer runs before the building loop, or build() stopped seeding output_active" % sat)

	# The machines' own first tick is the other half of the contract: they
	# must have STARTED (commit/accumulate), not parked in NO_POWER on a
	# stale zero.
	for anchor in rig["smelter_anchors"]:
		var sm: Building = world.building_at(anchor)
		_check(failures, sm != null and int(sm.state.get("state", -1)) == 1 and int(sm.state.get("progress", -1)) == 1,
			"(2) smelter at %s after tick 1: state %d progress %d, expected SMELTING (1) with progress 1 — its first tick did not see the network truth" % [str(anchor), int(sm.state.get("state", -1)) if sm != null else -99, int(sm.state.get("progress", -1)) if sm != null else -99])
	for anchor in rig["drill_anchors"]:
		var dr: Building = world.building_at(anchor)
		_check(failures, dr != null and int(dr.state.get("state", -1)) == 1 and int(dr.state.get("drill_progress", -1)) == 1,
			"(2) drill at %s after tick 1: state %d progress %d, expected DRILLING (1) with drill_progress 1 — its first tick did not see the network truth" % [str(anchor), int(dr.state.get("state", -1)) if dr != null else -99, int(dr.state.get("drill_progress", -1)) if dr != null else -99])

	_teardown(world)

# ===========================================================================
# (3) ONE NETWORK, DEMAND EXACTLY 40.
# 40 because the composition is 2 x ELECTRIC_SMELTER @ 10 + 2 x
# ELECTRIC_DRILL @ 10, against supply in 20-unit steam blocks — one fuelled
# generator is then EXACTLY 20/40 = 0.50, the true binary midpoint the whole
# three-position lever design rests on. `==`, never `>=` (#26 is the record
# of what lower bounds cost); a demand of 39 or 41 still lights every machine
# and is invisible on screen.
# ===========================================================================
static func _case_single_network_demand_40(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var _rig: Dictionary = ProcessorRig.build(world, ORIGIN)
	_advance(world, 2)

	var comps: Dictionary = {}
	for comp_id in world._pole_component.values():
		comps[comp_id] = true
	_check(failures, comps.size() == 1,
		"(3) expected a single power component, found %d" % comps.size())

	var total_demand: int = 0
	for comp_id in comps:
		total_demand += int(world._component_demand.get(comp_id, 0))
	_check(failures, total_demand == EXPECTED_DEMAND,
		"(3) network demand is %d, expected exactly %d" % [total_demand, EXPECTED_DEMAND])

	_teardown(world)

# ===========================================================================
# (4) FULL POWER — satisfaction exactly 1.00, all four machines on the
# 32-tick cadence, pinned in the CHESTS (the thing the user actually
# watches), two samples per boundary.
# ===========================================================================
static func _case_full_power_trajectories(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ProcessorRig.build(world, ORIGIN)
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_FULL, true)
	_sample_all_chests(world, rig, ElectricRig.POWER_FULL, SAT100_SAMPLES, 1.0, failures, "(4)")
	_teardown(world)

# ===========================================================================
# (5) BROWNOUT — one generator, satisfaction exactly 0.50, every cycle
# stretched to 64 (target-stretch recomputed from live satisfaction).
# ===========================================================================
static func _case_brownout_trajectories(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ProcessorRig.build(world, ORIGIN)
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_BROWNOUT, true)
	_sample_all_chests(world, rig, ElectricRig.POWER_BROWNOUT, SAT050_SAMPLES, 0.5, failures, "(5)")
	_teardown(world)

# ===========================================================================
# (6) ZERO — satisfaction exactly 0.00, all four machines parked in their
# NO_POWER states (smelter 4 / drill 5, save-format ints), progress HELD at
# the literal the outage found it on, nothing produced, nothing drained,
# nothing re-consumed.
# ===========================================================================
static func _case_zero_power_freeze(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ProcessorRig.build(world, ORIGIN)
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_FULL, true)
	_drive(world, rig["gen_anchors"], ElectricRig.POWER_FULL, FREEZE_E)

	# Premise: the cut lands mid-batch, e != 0.
	var sm0: Building = world.building_at((rig["smelter_anchors"] as Array)[0])
	_check(failures, sm0 != null and int(sm0.state.get("progress", -1)) == FREEZE_E,
		"(6) PREMISE: smelter progress should be %d at the cut, got %d" % [FREEZE_E, int(sm0.state.get("progress", -1)) if sm0 != null else -99])

	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_ZERO, true)
	_drive(world, rig["gen_anchors"], ElectricRig.POWER_ZERO, HOLD_OUTAGE)

	var sat: float = world.power_satisfaction_at((rig["smelter_anchors"] as Array)[0])
	_check(failures, sat == 0.0,
		"(6) ZERO satisfaction is %f, expected exactly 0.0" % sat)
	for anchor in rig["smelter_anchors"]:
		var sm: Building = world.building_at(anchor)
		_check(failures, sm != null and int(sm.state.get("state", -1)) == SMELTER_NO_POWER,
			"(6) smelter at %s state is %d, expected STATE_NO_POWER (%d)" % [str(anchor), int(sm.state.get("state", -1)) if sm != null else -99, SMELTER_NO_POWER])
		_check(failures, sm != null and int(sm.state.get("progress", -1)) == FREEZE_E,
			"(6) smelter at %s progress is %d, expected HELD at %d" % [str(anchor), int(sm.state.get("progress", -1)) if sm != null else -99, FREEZE_E])
		_check(failures, sm != null and _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE) == ORE_PRELOAD - 1,
			"(6) smelter at %s in_buffer is %d, expected %d — the outage must not consume" % [str(anchor), _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE) if sm != null else -99, ORE_PRELOAD - 1])
	for anchor in rig["drill_anchors"]:
		var dr: Building = world.building_at(anchor)
		_check(failures, dr != null and int(dr.state.get("state", -1)) == DRILL_NO_POWER,
			"(6) drill at %s state is %d, expected STATE_NO_POWER (%d)" % [str(anchor), int(dr.state.get("state", -1)) if dr != null else -99, DRILL_NO_POWER])
		_check(failures, dr != null and int(dr.state.get("drill_progress", -1)) == FREEZE_E,
			"(6) drill at %s drill_progress is %d, expected HELD at %d" % [str(anchor), int(dr.state.get("drill_progress", -1)) if dr != null else -99, FREEZE_E])
		_check(failures, dr != null and world.richness_at(anchor) == ORE_RICHNESS,
			"(6) a parked drill must not drain its deposit: %s should still be %d, got %d" % [str(anchor), ORE_RICHNESS, world.richness_at(anchor)])
	for chest_pos in (rig["smelter_chests"] as Array) + (rig["drill_chests"] as Array):
		_check(failures, _chest_total(world, chest_pos) == 0,
			"(6) chest at %s holds %d items — nothing may be produced before or during the outage" % [str(chest_pos), _chest_total(world, chest_pos)])

	_teardown(world)

# ===========================================================================
# (7) RESUME WITHOUT RE-CONSUMING — the Q3 rule at rig scale, pinned by one
# smelter's WALL-CLOCK COMPLETION IDENTITY: first ingot at machine tick
# e + O + (T_eff - e) = O + T_eff = 50 + 32 = 82, with in_buffer still at
# preload - 1 when it lands. A resume routed through the IDLE arm would
# re-commit (progress reset AND a second ore consumed) and land late with
# in_buffer at preload - 2; a drain-during-outage would land early. The
# identity catches both; the elapsed form alone catches neither.
# ===========================================================================
static func _case_resume_identity(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ProcessorRig.build(world, ORIGIN)
	var sm_anchor: Vector2i = (rig["smelter_anchors"] as Array)[0]
	var sm_chest: Vector2i = (rig["smelter_chests"] as Array)[0]
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_FULL, true)
	_drive(world, rig["gen_anchors"], ElectricRig.POWER_FULL, FREEZE_E)

	var sm: Building = world.building_at(sm_anchor)
	if sm == null:
		_check(failures, false, "(7) no smelter at %s to measure" % str(sm_anchor))
		_teardown(world)
		return
	_check(failures, int(sm.state.get("progress", -1)) == FREEZE_E and _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE) == ORE_PRELOAD - 1,
		"(7) PREMISE: at the cut progress should be %d with in_buffer %d, got %d / %d" % [FREEZE_E, ORE_PRELOAD - 1, int(sm.state.get("progress", -1)), _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE)])

	# The outage. O > T_eff - e and O mod T_eff != 0 (see the constants).
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_ZERO, true)
	_drive(world, rig["gen_anchors"], ElectricRig.POWER_ZERO, FREEZE_OUTAGE)
	_check(failures, int(sm.state.get("progress", -1)) == FREEZE_E and _chest_total(world, sm_chest) == 0,
		"(7) NOTHING moves across the outage: expected progress %d / chest 0, got %d / %d" % [FREEZE_E, int(sm.state.get("progress", -1)), _chest_total(world, sm_chest)])

	# Restore, and walk to one tick BEFORE the identity: still nothing.
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_FULL, true)
	_drive(world, rig["gen_anchors"], ElectricRig.POWER_FULL, FREEZE_IDENTITY_TICK - FREEZE_E - FREEZE_OUTAGE - 1)
	_check(failures, _chest_total(world, sm_chest) == 0,
		"(7) the first ingot arrived EARLY (before machine tick %d) — elapsed work was not preserved as-is" % FREEZE_IDENTITY_TICK)

	# The identity tick itself.
	_drive(world, rig["gen_anchors"], ElectricRig.POWER_FULL, 1)
	_check(failures, _chest_count(world, sm_chest, Items.Type.IRON_INGOT) == 1,
		"(7) first ingot must land at machine tick %d (= outage %d + T_eff %d), chest holds %d" % [FREEZE_IDENTITY_TICK, FREEZE_OUTAGE, RATED_CYCLE_TICKS, _chest_count(world, sm_chest, Items.Type.IRON_INGOT)])
	_check(failures, _bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE) == ORE_PRELOAD - 1,
		"(7) in_buffer is %d at completion, expected %d — the resume re-consumed a second ore" % [_bag_count(sm.state.get("in_buffer", []), Items.Type.IRON_ORE), ORE_PRELOAD - 1])
	_check(failures, int(sm.state.get("progress", -1)) == 0,
		"(7) progress should reset to 0 after the completed batch, got %d" % int(sm.state.get("progress", -1)))

	_teardown(world)

# ===========================================================================
# (8) SPAWNING ONTO OCCUPIED GROUND. Two cases, opposite right answers:
#
#   ADOPTION  — the rig is already there in full (relaunch onto a save, or F3
#               after F9). build() must hand back the anchors standing on the
#               ground AND re-seed what drains: smelter in_buffers and the
#               drill deposits (hand-seeded terrain is session bookkeeping —
#               it does not ride procgen, so re-attach is also the recovery
#               path that restores it).
#   COLLISION — one PLAYER-owned electric smelter happens to sit exactly on a
#               planned anchor. It is type-identical to the rig's own, so
#               nothing but "did we place it" can tell them apart — and
#               seeding it would overwrite the player's in_buffer with 400
#               iron ore, no undo.
# ===========================================================================
static func _case_respawn_and_collision(parent: Node, failures: Array) -> void:
	# --- adoption: build the same rig twice on one world, with wear between. ---
	var world = _make_world(parent)
	var first: Dictionary = ProcessorRig.build(world, ORIGIN)
	# Explicit lever press rather than trusting build()'s spawn default —
	# every trajectory case does the same, so ONLY the boot-order sub-case
	# depends on the default and a mutated default reddens exactly there.
	ElectricRig.apply_power_state(world, first["gen_anchors"], ElectricRig.POWER_FULL, true)
	_drive(world, first["gen_anchors"], ElectricRig.POWER_FULL, ADOPT_PRE_TICKS)

	var sm_a: Building = world.building_at((first["smelter_anchors"] as Array)[0])
	var dr_a_anchor: Vector2i = (first["drill_anchors"] as Array)[0]
	_check(failures, sm_a != null and _bag_count(sm_a.state.get("in_buffer", []), Items.Type.IRON_ORE) == ORE_PRELOAD - 2,
		"(8) PREMISE: after %d ticks the smelter should have consumed 2 ore (%d left), got %d" % [ADOPT_PRE_TICKS, ORE_PRELOAD - 2, _bag_count(sm_a.state.get("in_buffer", []), Items.Type.IRON_ORE) if sm_a != null else -99])
	_check(failures, world.richness_at(dr_a_anchor) == ORE_RICHNESS - 1,
		"(8) PREMISE: after %d ticks the drill should have drained its anchor deposit to %d, got %d" % [ADOPT_PRE_TICKS, ORE_RICHNESS - 1, world.richness_at(dr_a_anchor)])

	var again: Dictionary = ProcessorRig.build(world, ORIGIN)
	_check(failures, bool(again.get("adopted", false)),
		"(8) a second build over an intact rig did not report adopted")
	_check(failures, int(again["placed"]) == 0,
		"(8) adoption placed %d buildings — it must build nothing" % int(again["placed"]))
	_check(failures, (again["gen_anchors"] as Array) == (first["gen_anchors"] as Array),
		"(8) adopted gen_anchors %s do not match the rig on the ground %s" % [str(again["gen_anchors"]), str(first["gen_anchors"])])
	_check(failures, (again["smelter_anchors"] as Array) == (first["smelter_anchors"] as Array),
		"(8) adopted smelter_anchors %s do not match %s" % [str(again["smelter_anchors"]), str(first["smelter_anchors"])])
	_check(failures, (again["drill_anchors"] as Array) == (first["drill_anchors"] as Array),
		"(8) adopted drill_anchors %s do not match %s" % [str(again["drill_anchors"]), str(first["drill_anchors"])])
	_check(failures, sm_a != null and _bag_count(sm_a.state.get("in_buffer", []), Items.Type.IRON_ORE) == ORE_PRELOAD,
		"(8) adoption must re-seed the rig's OWN smelter to %d, got %d" % [ORE_PRELOAD, _bag_count(sm_a.state.get("in_buffer", []), Items.Type.IRON_ORE) if sm_a != null else -99])
	_check(failures, world.richness_at(dr_a_anchor) == ORE_RICHNESS,
		"(8) adoption must re-seed the rig's OWN deposits to %d, got %d" % [ORE_RICHNESS, world.richness_at(dr_a_anchor)])
	_teardown(world)

	# --- collision: a player's electric smelter on the first smelter anchor. ---
	var world_c = _make_world(parent)
	var sm_pos: Vector2i = ORIGIN + ProcessorRig.SM_A_OFFSET
	for dx in 2:
		for dy in 2:
			var cell: Vector2i = sm_pos + Vector2i(dx, dy)
			world_c.tiles[cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
			world_c.set_overlay(cell, Terrain.Overlay.STONE)
	world_c.place_building(Buildings.Type.ELECTRIC_SMELTER, sm_pos, Belt.DIR_E)
	var players_smelter: Building = world_c.building_at(sm_pos)
	if players_smelter == null:
		_check(failures, false, "(8) could not stage a player smelter at %s" % str(sm_pos))
		_teardown(world_c)
		return
	players_smelter.state["in_buffer"] = [[Items.Type.COPPER_ORE, 3]]

	var rig_c: Dictionary = ProcessorRig.build(world_c, ORIGIN)
	_check(failures, not bool(rig_c.get("adopted", false)),
		"(8) one pre-existing smelter must NOT read as an adoptable rig")
	_check(failures, int(rig_c["skipped"]) == 1,
		"(8) expected exactly 1 skipped placement, got %d" % int(rig_c["skipped"]))
	_check(failures, int(rig_c["placed"]) == EXPECTED_PLACEMENTS - 1,
		"(8) expected %d placements around the collision, got %d" % [EXPECTED_PLACEMENTS - 1, int(rig_c["placed"])])
	_check(failures, _bag_count(players_smelter.state.get("in_buffer", []), Items.Type.COPPER_ORE) == 3,
		"(8) the player's 3 copper ore were destroyed by the rig seeding their smelter")
	_check(failures, _bag_count(players_smelter.state.get("in_buffer", []), Items.Type.IRON_ORE) == 0,
		"(8) the rig seeded %d iron ore into a smelter it did not place" % _bag_count(players_smelter.state.get("in_buffer", []), Items.Type.IRON_ORE))
	_teardown(world_c)

# ---------- helpers ----------

## Drive `ticks` ticks with the lever held at `state` — sustain_fuel then one
## tick, exactly main.gd's per-frame sequence (and test_electric_rig's).
static func _drive(world, gens: Array, state: int, ticks: int) -> void:
	for _i in ticks:
		ElectricRig.sustain_fuel(world, gens, state)
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

## Walk a trajectory tick by tick from machine tick 1, checking ALL FOUR
## output chests at every sampled tick (rows are [tick, expected_count]) and
## the exact satisfaction at each sample.
static func _sample_all_chests(world, rig: Dictionary, state: int, rows: Array, want_sat: float, failures: Array, label: String) -> void:
	var by_tick: Dictionary = {}
	for row in rows:
		by_tick[int(row[0])] = int(row[1])
	var last_tick: int = int(rows[rows.size() - 1][0])
	var sm_chests: Array = rig["smelter_chests"]
	var dr_chests: Array = rig["drill_chests"]
	for t in range(1, last_tick + 1):
		ElectricRig.sustain_fuel(world, rig["gen_anchors"], state)
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if not by_tick.has(t):
			continue
		var want: int = by_tick[t]
		var sat: float = world.power_satisfaction_at((rig["smelter_anchors"] as Array)[0])
		_check(failures, sat == want_sat,
			"%s satisfaction at machine tick %d is %f, expected exactly %f" % [label, t, sat, want_sat])
		for i in sm_chests.size():
			_check(failures, _chest_count(world, sm_chests[i], Items.Type.IRON_INGOT) == want,
				"%s smelter %d chest at machine tick %d holds %d ingots, expected %d" % [label, i, t, _chest_count(world, sm_chests[i], Items.Type.IRON_INGOT), want])
		for i in dr_chests.size():
			_check(failures, _chest_count(world, dr_chests[i], Items.Type.RAW_STONE) == want,
				"%s drill %d chest at machine tick %d holds %d stone, expected %d" % [label, i, t, _chest_count(world, dr_chests[i], Items.Type.RAW_STONE), want])

static func _make_world(parent: Node) -> Node2D:
	# No terrain prep — ProcessorRig.build() paves and seeds its own ground,
	# and that self-sufficiency is precisely what makes it seed-independent
	# in game.
	var w = GridWorldScript.new()
	parent.add_child(w)
	return w

static func _advance(world, ticks: int) -> void:
	for _i in ticks:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _chest_count(world, pos: Vector2i, item_type: int) -> int:
	if not world.has_building_at(pos):
		return -1
	var chest: Building = world.building_at(pos)
	if chest == null or chest.type != Buildings.Type.CHEST:
		return -1
	return _bag_count(chest.state.get("bag", []), item_type)

static func _chest_total(world, pos: Vector2i) -> int:
	if not world.has_building_at(pos):
		return -1
	var chest: Building = world.building_at(pos)
	if chest == null or chest.type != Buildings.Type.CHEST:
		return -1
	var total: int = 0
	for entry in chest.state.get("bag", []):
		total += int(entry[1])
	return total

## Does a POWER_POLE sit on one of the building's edge cells? Same helper as
## test_electric_rig.gd — the generator-side adjacency rule via
## Buildings.all_edge_cells.
static func _touches_pole(world, anchor: Vector2i) -> bool:
	var b: Building = world.building_at(anchor)
	if b == null:
		return false
	for cell in Buildings.all_edge_cells(b.type, b.anchor):
		if not world.has_building_at(cell):
			continue
		var nb: Building = world.building_at(cell)
		if nb != null and nb.type == Buildings.Type.POWER_POLE:
			return true
	return false

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
