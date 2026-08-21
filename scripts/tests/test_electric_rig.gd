extends RefCounted

## ELECTRIC RIG — headless proof of the PAUSE 1 smoke-test scenario.
##
## The rig (scripts/world/electric_rig.gd) exists so a human can LOOK at the
## ELECTRIC_INSERTER brownout path. This file is the half of that claim a human
## cannot check by looking: that the arithmetic underneath the lever is exact.
##
## The rig's whole design rests on demand landing on EXACTLY 40 while supply
## arrives in 20-unit blocks. Miss by one lamp and the brownout satisfaction
## slides off 0.50; miss by one inserter and it slides far enough to change the
## observed cycle length. Neither failure is visible on screen — the arm just
## moves at a slightly different speed than the design says it should — so it
## has to be pinned here.
##
## Sub-cases:
##   1. The layout lands. Every planned building placed, nothing skipped, and
##      the hero inserter's source/dest resolve to the two flanking chests.
##   2. One network, demand exactly 40.
##   3. FULL     — satisfaction exactly 1.00, effective cycle 5 ticks.
##   4. BROWNOUT — satisfaction exactly 0.50, effective cycle 10 ticks.
##   5. ZERO     — satisfaction exactly 0.00, effective cycle 100 ticks, and
##      the hero sits in STATE_NO_POWER.
##   6. The lever is STABLE. Fuel sustained each tick, brownout holds 0.50 well
##      past the point a one-shot fuel seed would have burned out — plus the
##      negative control proving that sustaining is load-bearing and not
##      decoration.
##   7. End to end: the hero actually ferries items, faster at full power than
##      in brownout, and not at all at zero.
##   8. Spawning onto occupied ground: an intact rig is ADOPTED (the lever
##      re-attaches to it), while a lone player-owned chest on the source cell
##      is refused and its contents left alone.
##
## Sub-case 5's 100 is VERIFIED here rather than trusted. It comes out of
## `int(ceil(float(base) / maxf(POWER_EPSILON, sat)))` with base 5 and sat 0.0,
## i.e. 5 / 0.05 — and 0.05 has no exact binary representation, so the division
## lands just under 100 and only ceil() brings it back. A different rounding
## mode would give 99.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Rig origin used by every sub-case. Non-zero on purpose: the rig carries
# negative coordinates on both axes it is absolutised along — the plan's
# westmost lamp is at x = -1 (electric_rig.gd) and the paving rectangle starts
# at PAVE_MIN = (-2, 1) — so an origin at (0,0) would let a sign error in the
# absolutise step hide behind coordinates that happen to still be legal.
const ORIGIN: Vector2i = Vector2i(40, 40)

# The two totals the whole design rests on, as LITERALS and deliberately HERE
# rather than in electric_rig.gd. A constant that lives beside the plan gets
# edited in the same breath as the plan, which would make this assertion
# self-referential: delete a lamp row, adjust the neighbouring const, and the
# suite stays green while brownout satisfaction quietly becomes 20/39 = 0.5128.
# Changing the layout must mean changing a number in THIS file, on purpose.
#   34 placements = 2 generators + 6 poles + 2 chests + 4 inserters + 20 lamps
#   40 demand     = 4 inserters x 5 + 20 lamps x 1
const EXPECTED_PLACEMENTS: int = 34
const EXPECTED_DEMAND: int = 40

# The three tier facts this rig is built around, asserted as LITERALS rather
# than read back from Inserter's tables. The point is to pin the balance
# numbers independently of the implementation — read back from the table and a
# silent edit to the table would be ratified instead of caught.
const RATED_CYCLE_TICKS: int = 5
const BROWNOUT_CYCLE_TICKS: int = 10
# ceil(5 / POWER_EPSILON) = ceil(5 / 0.05). Unreachable through tick() (which
# stalls at or below epsilon) but reachable through a direct
# effective_cycle_ticks call, which is what sub-case 5 makes.
const NO_POWER_CYCLE_TICKS: int = 100

# Ticks each end-to-end throughput run gets in sub-case 7. 200 ticks = 10 s at
# 20 TPS: comfortably more than a dozen full 5-tick cycles at full power, and
# still more than a dozen 10-tick cycles in brownout, so both counts are large
# enough that the comparison is not down to a single boundary cycle.
const THROUGHPUT_TICKS: int = 200

# Sub-case 6's horizon. Burner.FUEL_BUFFER_CAPACITY is 16 units and
# SteamGenerator burns exactly one per second (CYCLE_TICKS 20 at 20 TPS), so a
# one-shot seed dies at tick ~320. 500 ticks (25 s) clears that with margin.
const DRIFT_TICKS: int = 500

static func test_name() -> String:
	return "electric rig (layout lands + single network + demand 40 + full/brownout/zero satisfaction + cycle scaling + lever stability + end-to-end throughput + adopt-or-refuse)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_layout_lands(parent, failures)
	_case_single_network_demand_40(parent, failures)
	_case_three_power_states(parent, failures)
	_case_lever_is_stable(parent, failures)
	_case_end_to_end_throughput(parent, failures)
	_case_respawn_and_collision(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "8 sub-cases pass: layout lands + single network + demand 40 + full 1.00/5t + brownout 0.50/10t + zero 0.00/100t + lever stability + end-to-end throughput + adopt-or-refuse on occupied ground" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) THE LAYOUT LANDS.
# Every satisfaction number in this file is downstream of the rig being built
# in full. A silently skipped generator halves supply; a silently skipped lamp
# moves demand off 40. Both would show up here as a nonzero skip count, so this
# sub-case runs first and the rest are only meaningful once it passes.
# ===========================================================================
static func _case_layout_lands(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ElectricRig.build(world, ORIGIN)

	_check(failures, int(rig["placed"]) == EXPECTED_PLACEMENTS,
		"(1) placed %d buildings, expected %d" % [int(rig["placed"]), EXPECTED_PLACEMENTS])
	_check(failures, int(rig["skipped"]) == 0,
		"(1) %d planned buildings were skipped — the rig is incomplete" % int(rig["skipped"]))
	_check(failures, (rig["gen_anchors"] as Array).size() == 2,
		"(1) expected 2 steam generators, got %d" % (rig["gen_anchors"] as Array).size())

	# The hero is identified in-game ONLY by the two chests flanking it, so the
	# flanking has to actually resolve through Inserter's own geometry rather
	# than by the plan happening to list three adjacent offsets.
	var hero: Building = world.building_at(rig["hero"])
	if hero == null or hero.type != Buildings.Type.ELECTRIC_INSERTER:
		_check(failures, false, "(1) no electric inserter at the hero anchor %s" % str(rig["hero"]))
		_teardown(world)
		return
	_check(failures, Inserter.source_tile(hero) == rig["source_chest"],
		"(1) hero source tile %s is not the source chest at %s" % [str(Inserter.source_tile(hero)), str(rig["source_chest"])])
	_check(failures, Inserter.dest_tile(hero) == rig["dest_chest"],
		"(1) hero dest tile %s is not the dest chest at %s" % [str(Inserter.dest_tile(hero)), str(rig["dest_chest"])])
	_check(failures, _chest_count(world, rig["source_chest"], ElectricRig.SOURCE_ITEM) == ElectricRig.SOURCE_COUNT,
		"(1) source chest was not seeded to %d items" % ElectricRig.SOURCE_COUNT)
	_check(failures, _chest_count(world, rig["dest_chest"], ElectricRig.SOURCE_ITEM) == 0,
		"(1) dest chest should start empty")

	# Both generators must CARDINALLY touch a pole — generators use
	# _adjacent_component_id, not the consumers' Chebyshev supply area, so a
	# generator one diagonal step off the bus contributes nothing and the
	# failure is invisible until the satisfaction numbers come out wrong.
	for anchor in rig["gen_anchors"]:
		_check(failures, _touches_pole(world, anchor),
			"(1) steam generator at %s does not cardinally touch a power pole" % str(anchor))

	_teardown(world)

# ===========================================================================
# (2) ONE NETWORK, DEMAND EXACTLY 40.
# The 0.50 midpoint is arithmetic, not approximation: 20 / 40 is exact in
# binary floating point and 20 / 39 is not. Demand also has to land on ONE
# component — six poles that split into two networks would give two half-sized
# demands and two half-sized supplies, which still looks plausible on screen.
# ===========================================================================
static func _case_single_network_demand_40(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ElectricRig.build(world, ORIGIN)
	_advance(world, 2)

	var comps: Dictionary = {}
	for comp_id in world._pole_component.values():
		comps[comp_id] = true
	_check(failures, comps.size() == 1,
		"(2) expected a single power component, found %d" % comps.size())

	var total_demand: int = 0
	for comp_id in comps:
		total_demand += int(world._component_demand.get(comp_id, 0))
	_check(failures, total_demand == EXPECTED_DEMAND,
		"(2) network demand is %d, expected exactly %d" % [total_demand, EXPECTED_DEMAND])

	_teardown(world)

# ===========================================================================
# (3)(4)(5) THE THREE LEVER POSITIONS.
# One world, three lever presses, no rebuilding — which is also the property
# the user is relying on when they cycle the key mid-observation. Satisfaction
# is compared EXACTLY (==, not is_equal_approx) on purpose: the design claims
# these are exact binary values, and an approximate assertion would pass on a
# layout that had drifted to 0.5128.
# ===========================================================================
static func _case_three_power_states(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = ElectricRig.build(world, ORIGIN)
	var hero: Building = world.building_at(rig["hero"])
	if hero == null:
		_check(failures, false, "(3) no hero inserter to measure")
		_teardown(world)
		return

	# --- FULL ---
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_FULL)
	_advance(world, 2)
	var sat_full: float = world.power_satisfaction_at(hero.anchor)
	_check(failures, sat_full == 1.0,
		"(3) FULL satisfaction is %f, expected exactly 1.0" % sat_full)
	_check(failures, Inserter.effective_cycle_ticks(hero, world) == RATED_CYCLE_TICKS,
		"(3) FULL cycle is %d ticks, expected %d" % [Inserter.effective_cycle_ticks(hero, world), RATED_CYCLE_TICKS])

	# --- BROWNOUT ---
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_BROWNOUT)
	_advance(world, 2)
	var sat_brown: float = world.power_satisfaction_at(hero.anchor)
	_check(failures, sat_brown == 0.5,
		"(4) BROWNOUT satisfaction is %f, expected exactly 0.5" % sat_brown)
	_check(failures, Inserter.effective_cycle_ticks(hero, world) == BROWNOUT_CYCLE_TICKS,
		"(4) BROWNOUT cycle is %d ticks, expected %d" % [Inserter.effective_cycle_ticks(hero, world), BROWNOUT_CYCLE_TICKS])

	# --- ZERO ---
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_ZERO)
	_advance(world, 2)
	var sat_zero: float = world.power_satisfaction_at(hero.anchor)
	_check(failures, sat_zero == 0.0,
		"(5) ZERO satisfaction is %f, expected exactly 0.0" % sat_zero)
	# The divisor floor, not the rated cycle. 5 / 0.05 in doubles lands just
	# below 100 and ceil() carries it up, so this also pins the rounding mode.
	_check(failures, Inserter.effective_cycle_ticks(hero, world) == NO_POWER_CYCLE_TICKS,
		"(5) ZERO cycle is %d ticks, expected %d (the POWER_EPSILON divisor floor)" % [Inserter.effective_cycle_ticks(hero, world), NO_POWER_CYCLE_TICKS])
	_check(failures, int(hero.state.get("state", -1)) == Inserter.STATE_NO_POWER,
		"(5) hero state is %d, expected STATE_NO_POWER (%d)" % [int(hero.state.get("state", -1)), Inserter.STATE_NO_POWER])

	# The lever must be symmetric — going back up has to restore full supply
	# with nothing rebuilt, which is the property the user relies on most.
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_FULL)
	_advance(world, 2)
	_check(failures, world.power_satisfaction_at(hero.anchor) == 1.0,
		"(5) returning the lever to FULL did not restore satisfaction 1.0")

	_teardown(world)

# ===========================================================================
# (6) THE LEVER IS STABLE.
# The failure this guards against is silent and expensive: seed the fuel once,
# walk away, and the generators burn through 16 units in 16 seconds, so the
# state the user believes they are looking at quietly becomes a different one
# partway through the observation. The fix is that the lever is re-asserted
# every frame (main.gd _sustain_rig_power).
#
# Both halves are needed. The positive half proves re-assertion holds the
# state; the NEGATIVE control proves re-assertion is what is doing it — without
# it, this exact horizon collapses to zero. Drop the negative half and the
# positive one would pass just as happily on a build where fuel never drained.
# ===========================================================================
static func _case_lever_is_stable(parent: Node, failures: Array) -> void:
	# --- positive: sustained every tick, brownout holds. ---
	var world = _make_world(parent)
	var rig: Dictionary = ElectricRig.build(world, ORIGIN)
	var hero: Building = world.building_at(rig["hero"])
	if hero == null:
		_check(failures, false, "(6) no hero inserter to measure")
		_teardown(world)
		return
	ElectricRig.apply_power_state(world, rig["gen_anchors"], ElectricRig.POWER_BROWNOUT)
	# Settle before measuring. build() seeds output_active for FULL and the
	# lever writes fuel ONLY, so the generator this press darkened keeps
	# contributing supply until its own next tick derives output_active from
	# its now-empty buffer. That is the same ~0.1 s lag the user sees after an
	# F8 press (documented at main.gd's _cycle_rig_power); this sub-case is
	# about what happens over the following 25 seconds, not about the settle.
	_advance(world, 2)
	var drifted: float = -1.0
	for i in DRIFT_TICKS:
		# sustain_fuel, NOT apply_power_state — exactly what main.gd's
		# _process does. It writes fuel and nothing else, so every
		# satisfaction reading below is the generator's own
		# fuel -> output_active derivation rather than a value this loop
		# planted for the pre-pass to find.
		ElectricRig.sustain_fuel(world, rig["gen_anchors"], ElectricRig.POWER_BROWNOUT)
		_advance(world, 1)
		var s: float = world.power_satisfaction_at(hero.anchor)
		if s != 0.5:
			drifted = s
			break
	_check(failures, drifted < 0.0,
		"(6) sustained BROWNOUT drifted to satisfaction %f within %d ticks" % [drifted, DRIFT_TICKS])
	_teardown(world)

	# --- negative control: seed once, never sustain, and it dies. ---
	var world_b = _make_world(parent)
	var rig_b: Dictionary = ElectricRig.build(world_b, ORIGIN)
	var hero_b: Building = world_b.building_at(rig_b["hero"])
	if hero_b == null:
		_check(failures, false, "(6) negative control: no hero inserter to measure")
		_teardown(world_b)
		return
	ElectricRig.apply_power_state(world_b, rig_b["gen_anchors"], ElectricRig.POWER_BROWNOUT)
	_advance(world_b, DRIFT_TICKS)
	_check(failures, world_b.power_satisfaction_at(hero_b.anchor) == 0.0,
		"(6) negative control: a one-shot fuel seed still read %f after %d ticks, so this test cannot tell whether sustaining matters" % [world_b.power_satisfaction_at(hero_b.anchor), DRIFT_TICKS])
	_teardown(world_b)

# ===========================================================================
# (7) END TO END.
# Satisfaction and cycle length are both derived numbers. This is the only
# sub-case that asserts the thing the user will actually watch: iron ore
# crossing from the source chest into the dest chest, visibly slower in
# brownout and stopped dead at zero.
# ===========================================================================
static func _case_end_to_end_throughput(parent: Node, failures: Array) -> void:
	var moved_full: int = _run_throughput(parent, ElectricRig.POWER_FULL)
	var moved_brown: int = _run_throughput(parent, ElectricRig.POWER_BROWNOUT)
	var moved_zero: int = _run_throughput(parent, ElectricRig.POWER_ZERO)

	_check(failures, moved_full > 0,
		"(7) hero delivered nothing in %d ticks at FULL power" % THROUGHPUT_TICKS)
	_check(failures, moved_brown > 0,
		"(7) hero delivered nothing in %d ticks in BROWNOUT — it should be slower, not stopped" % THROUGHPUT_TICKS)
	_check(failures, moved_brown < moved_full,
		"(7) BROWNOUT delivered %d and FULL delivered %d — brownout must be strictly slower" % [moved_brown, moved_full])
	_check(failures, moved_zero == 0,
		"(7) hero delivered %d items at ZERO power — STATE_NO_POWER must stall it completely" % moved_zero)

# ===========================================================================
# (8) SPAWNING ONTO OCCUPIED GROUND.
# The rig is placed relative to the PLAYER, so the interesting cases are not
# the empty-field one. Two of them, with opposite right answers:
#
#   ADOPTION  — the rig is already there in full (relaunch onto a save, or F10
#               after F9). build() must hand back the generators standing on
#               the ground, because an empty gen_anchors makes main.gd's lever
#               and per-frame sustain both early-return: a visually perfect rig
#               that F8 refuses to touch and that goes dark 16 s later.
#   COLLISION — one PLAYER-owned chest happens to sit on the source cell. It is
#               type-identical to the rig's own, so nothing but "did we place
#               it" can tell them apart, and seeding it would overwrite the
#               player's stored items with 2400 iron ore and no undo.
# ===========================================================================
static func _case_respawn_and_collision(parent: Node, failures: Array) -> void:
	# --- adoption: build the same rig twice on one world. ---
	var world = _make_world(parent)
	var first: Dictionary = ElectricRig.build(world, ORIGIN)
	var again: Dictionary = ElectricRig.build(world, ORIGIN)
	_check(failures, bool(again.get("adopted", false)),
		"(8) a second build over an intact rig did not report adopted")
	_check(failures, int(again["placed"]) == 0,
		"(8) adoption placed %d buildings — it must build nothing" % int(again["placed"]))
	_check(failures, (again["gen_anchors"] as Array) == (first["gen_anchors"] as Array),
		"(8) adopted gen_anchors %s do not match the rig on the ground %s" % [str(again["gen_anchors"]), str(first["gen_anchors"])])
	_check(failures, bool(again.get("source_seeded", false)),
		"(8) adoption should re-seed the rig's OWN source chest")
	_teardown(world)

	# --- collision: a player's chest is already on the source cell. ---
	var world_c = _make_world(parent)
	var source_pos: Vector2i = ORIGIN + ElectricRig.SOURCE_CHEST_OFFSET
	world_c.tiles[source_pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
	world_c.set_overlay(source_pos, Terrain.Overlay.STONE)
	world_c.place_building(Buildings.Type.CHEST, source_pos, 0)
	var players_chest: Building = world_c.building_at(source_pos)
	if players_chest == null:
		_check(failures, false, "(8) could not stage a player chest at the source cell")
		_teardown(world_c)
		return
	players_chest.state["bag"] = [[Items.Type.COAL, 7]]

	var rig_c: Dictionary = ElectricRig.build(world_c, ORIGIN)
	_check(failures, not bool(rig_c.get("adopted", false)),
		"(8) one pre-existing chest must NOT read as an adoptable rig")
	_check(failures, int(rig_c["skipped"]) == 1,
		"(8) expected exactly 1 skipped placement, got %d" % int(rig_c["skipped"]))
	_check(failures, not bool(rig_c.get("source_seeded", false)),
		"(8) a chest the rig did not place must not be reported as seeded")
	_check(failures, _chest_count(world_c, source_pos, Items.Type.COAL) == 7,
		"(8) the player's 7 coal were destroyed by the rig seeding their chest")
	_teardown(world_c)

# ---------- helpers ----------

## Build a fresh rig, hold `state` for THROUGHPUT_TICKS with the lever
## re-asserted every tick (mirroring main.gd's per-frame sustain), and return
## how many items reached the dest chest.
static func _run_throughput(parent: Node, state: int) -> int:
	var world = _make_world(parent)
	var rig: Dictionary = ElectricRig.build(world, ORIGIN)
	# One lever press with seed_output, then fuel-only sustain — the in-game
	# sequence. The seed matters here and only here: build() leaves both
	# generators seeded ACTIVE for FULL, so without it a run measuring ZERO
	# would spend its first tick at satisfaction 1.00 while the generators
	# caught up to their emptied buffers.
	ElectricRig.apply_power_state(world, rig["gen_anchors"], state, true)
	for i in THROUGHPUT_TICKS:
		ElectricRig.sustain_fuel(world, rig["gen_anchors"], state)
		_advance(world, 1)
	var moved: int = _chest_count(world, rig["dest_chest"], ElectricRig.SOURCE_ITEM)
	_teardown(world)
	return moved

static func _make_world(parent: Node) -> Node2D:
	# No terrain prep — ElectricRig.build() paves its own rectangle, and that
	# self-sufficiency is precisely what makes it seed-independent in game.
	var w = GridWorldScript.new()
	parent.add_child(w)
	return w

static func _advance(world, ticks: int) -> void:
	for i in ticks:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

static func _chest_count(world, pos: Vector2i, item_type: int) -> int:
	if not world.has_building_at(pos):
		return -1
	var chest: Building = world.building_at(pos)
	if chest == null or chest.type != Buildings.Type.CHEST:
		return -1
	for entry in chest.state.get("bag", []):
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

## Does a POWER_POLE sit on one of the building's edge cells? Reimplements the
## generator-side adjacency rule via the same Buildings.all_edge_cells helper
## PowerNetwork._adjacent_component_id uses.
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
