class_name ProcessorRig
extends RefCounted

## ELECTRIC PROCESSOR SMOKE-TEST RIG (session-electricity-processors, Task 6).
##
## A pre-built, self-contained power scenario whose only control is "how many
## steam generators have fuel". It exists so the ELECTRIC_SMELTER and
## ELECTRIC_DRILL brownout paths can be EYEBALLED — a running smelter visibly
## stretching its cycle, a drill slowing on its ore — without hand-placing a
## bus, machines, deposits and feeds first.
##
## The whole point is that demand is pinned at EXACTLY 40 and supply arrives
## in 20-unit blocks, so the three lever positions land on three exact
## satisfaction values:
##
##   generators fuelled | raw supply | satisfaction | machine cycle
##   -------------------|------------|--------------|----------------------
##   2                  | 40         | 1.00         | 32 ticks (1.6 s)
##   1                  | 20         | 0.50         | 64 ticks (3.2 s)
##   0                  |  0         | 0.00         | STATE_NO_POWER (4 / 5)
##
## 20.0 / 40 is exactly representable in binary floating point, so the middle
## row is a true 0.50 and ceil(32 / 0.5) is exactly 64, never 65.
##
## Demand composition (must sum to 40 or the 0.50 midpoint is missed):
##   2 x ELECTRIC_SMELTER @ Smelter.POWER_DEMAND_BY_TYPE     = 10 -> 20
##   2 x ELECTRIC_DRILL   @ MiningDrill.POWER_DEMAND_BY_TYPE = 10 -> 20
## The four output chests, six poles and two generators bill nothing.
##
## Deliberately ABSENT from this rig, and they must stay absent (the same two
## exclusions as ElectricRig, for the same reasons):
##   - ACCUMULATOR — PowerNetwork Stage 2 charges it on excess and discharges
##     it into deficit, which smears the three crisp states into ramps. Those
##     crisp states are the entire signal the smoke test is looking for.
##   - WINDMILL — its supply arm reads state.get("output_active", TRUE)
##     (PowerNetwork Stage 1), so one placed CARDINALLY TOUCHING any pole on
##     the bus — the GENERATOR rule, _adjacent_component_id, not the
##     consumers' Chebyshev supply area — silently adds 6 units and moves the
##     midpoint off 0.50. A windmill merely NEAR the bus contributes nothing;
##     POLE_RANGE governs pole-to-pole joining only.
##
## FEED CHOICE (Task 6 decision): the smelters are PRELOADED with iron ore in
## in_buffer at spawn, and every machine pushes into its own chest. Preload
## is the only feed that keeps demand at exactly 40 — an electric inserter
## feeder would add 5 to the sum, and a burner feeder would add a fuel clock
## the lever does not control (its stall reads exactly like a power fault).
## 400 ore = 400 batches: ~10.6 min of continuous smelting at T_eff 32 and
## ~21 min at 64, so a running smelter is available to stretch for the whole
## PAUSE-gate observation. The drills' deposits are seeded at richness 200
## per covered cell (4 cells each = 800 ore, ~21 min at full rate) so no
## drill reaches DEPLETED mid-observation.
##
## This module owns the LAYOUT and the SEEDS. The LEVER stays ElectricRig's
## (apply_power_state / sustain_fuel) — it has had exactly one implementation
## since the second rig shipped (see rig_support.gd's header on what
## deliberately does not move), and main.gd drives it identically for every
## rig kind. main.gd owns the key bindings (F3 spawn/re-attach, F8 lever),
## the dedup flag and the toast. The headless test (test_processor_rig.gd)
## drives these same entry points, so what the test proves and what the user
## looks at cannot drift.
##
## NOT PERSISTED, deliberately (the ElectricRig precedent): the rig's
## BUILDINGS are ordinary world state and ride the save, but the hand-seeded
## DEPOSIT RICHNESS is session bookkeeping — richness_at() reads
## resource_state, which regenerates from procgen on load, and procgen never
## put ore under these tiles. After F5/F9 the drills therefore read
## "Depleted" (never a crash: richness 0 is filtered before the ore-type
## lookup) until one F3 press re-attaches AND re-seeds — the same
## one-keypress recovery the electric rig documents for its lever.

# Rig origin, relative to the player tile at spawn time. Below the player
# (+y is screen-down) and west by half the paved width (20 tiles, x -1..18),
# so the rig straddles the player's column and the camera frames it.
# ORIGIN_OFFSET.y + PAVE_MIN.y = 1, so the paved area never reaches the
# player's own row at y=0 (a non-walkable building dropped on the player
# would trip the placement guard and spawn the rig INCOMPLETE). The paved
# rectangle bottoms out at player-relative y=7 — exactly the electric rig's
# MEASURED hotbar-safe bottom row (see its ORIGIN_OFFSET comment), reached
# here by pulling the offset to 0 instead: this rig is one paved row taller
# (2x2 consumers below the bus, where the electric rig has 1x1s), and the
# extra row was taken from the empty top margin rather than pushed toward
# the hotbar.
const ORIGIN_OFFSET: Vector2i = Vector2i(-8, 0)

# Phase 1 paving rectangle, INCLUSIVE, in rig-relative coordinates. Strictly
# contains every building cell (x 0..17, y 2..6) with a one-tile margin.
const PAVE_MIN: Vector2i = Vector2i(-1, 1)
const PAVE_MAX: Vector2i = Vector2i(18, 7)

# Landmarks the lever, the seeds and the tests need by name. Rig-relative.
#
# EVERY MACHINE ANCHOR SITS ON ROW y=5, DIRECTLY UNDER THE BUS, AND THAT IS
# LOAD-BEARING: the demand pre-pass finds a consumer through ANY covered
# footprint cell (_supply_component_id walks the footprint), but the
# machines' own tick reads world.power_satisfaction_at(b.anchor) — a
# per-TILE lookup. An anchor one row outside the poles' 3x3 supply boxes
# therefore BILLS its 10 demand while the machine itself reads satisfaction
# 0.0 and parks NO_POWER forever — a rig that looks complete, sums to 40,
# and never runs. (Found the hard way: this rig's first layout anchored the
# machines at y=2, two rows above the bus.)
const GEN_A_OFFSET: Vector2i = Vector2i(0, 2)
const GEN_B_OFFSET: Vector2i = Vector2i(3, 2)
const SM_A_OFFSET: Vector2i  = Vector2i(5, 5)
const SM_B_OFFSET: Vector2i  = Vector2i(9, 5)
const DR_A_OFFSET: Vector2i  = Vector2i(12, 5)
const DR_B_OFFSET: Vector2i  = Vector2i(15, 5)
# Each machine faces E and pushes into its own chest on its E edge — the
# chest fill is the user's cadence readout, one chest per machine.
const SM_A_CHEST_OFFSET: Vector2i = Vector2i(7, 5)
const SM_B_CHEST_OFFSET: Vector2i = Vector2i(11, 5)
const DR_A_CHEST_OFFSET: Vector2i = Vector2i(14, 5)
const DR_B_CHEST_OFFSET: Vector2i = Vector2i(17, 5)

# What the smelters eat. IRON_ORE specifically because it is NOT in
# Burner.FUEL_VALUES — a layout mistake that put a seeded buffer against a
# generator's fuel port could not silently feed the boiler and desync the
# lever from the fuel it believes it controls. The drills mine STONE
# deposits for the same reason: RAW_STONE is not fuel either.
const SMELTER_ORE_ITEM: int = Items.Type.IRON_ORE

# Batches per smelter at spawn and on every re-attach. See FEED CHOICE in
# the header for the arithmetic (~10.6 min at T_eff 32). Written into
# in_buffer directly — plain data, the same write the panel's slot binds to.
const SMELTER_ORE_COUNT: int = 400

# Richness per seeded deposit cell. 4 cells per drill = 800 ore = ~21 min of
# full-rate drilling before the first DEPLETED — longer than any gate
# session, which is the premise the freeze sub-cases rely on (a deposit that
# depletes mid-observation reads exactly like a machine fault).
const ORE_RICHNESS: int = 200

# The expected placement count and the expected demand total deliberately do
# NOT live here. They are literals in test_processor_rig.gd instead: a
# constant in this file would be edited in the same breath as the plan it
# describes, so the test would ratify the new arithmetic instead of failing
# on it. (Same rule as ElectricRig.)

## The build plan: [offset: Vector2i, building_type: int, dir: int].
##
## Paving happens in a separate first phase (see ElectricRig.plan's note on
## why the split is load-bearing for 2x2 footprints); the ore seeding is a
## phase of its own between paving and placement, because
## MiningDrill.validate_placement refuses a drill with no covered ore.
static func plan() -> Array:
	return [
		# --- generators: 2x2, dir = DIR_E so the fuel port (canonical S,
		# rotated by dir) stays on the world S edge. That edge faces a pole
		# and bare stone — neither is a BELT or a CHEST, the only two things
		# Burner.try_pull_fuel reacts to — so neither generator can ever pull
		# fuel from the world. That is what makes the lever authoritative.
		# Keep (1,4) and (4,4) empty for this reason.
		[GEN_A_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E],
		[GEN_B_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E],

		# --- pole bus: row y=4, spacing 3 == PowerNetwork.POLE_RANGE — the
		# maximum that still yields a single component. Generators touch the
		# bus by the GENERATOR rule (gen A's S-edge cell (0,4) and gen B's
		# (3,4) are poles); the four machines are covered by the CONSUMER
		# rule — and, per the ANCHOR note above, each machine's ANCHOR cell
		# itself is Chebyshev-1 from a pole: smelter A's (5,5) under the
		# (6,4) pole, smelter B's (9,5) under (9,4), drill A's (12,5) under
		# (12,4), drill B's (15,5) under (15,4).
		[Vector2i(0, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(3, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(6, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(9, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(12, 4), Buildings.Type.POWER_POLE, 0],
		[Vector2i(15, 4), Buildings.Type.POWER_POLE, 0],

		# --- smelters: 2x2, facing E, ingot output onto the chest beside
		# each. Column x=8 stays empty as a walk-in corridor from the north
		# rows down to the bus (as do x=2 between the generators and the
		# paved margin rows y=1 / y=7 around the whole rig).
		[SM_A_OFFSET, Buildings.Type.ELECTRIC_SMELTER, Belt.DIR_E],
		[SM_A_CHEST_OFFSET, Buildings.Type.CHEST, 0],
		[SM_B_OFFSET, Buildings.Type.ELECTRIC_SMELTER, Belt.DIR_E],
		[SM_B_CHEST_OFFSET, Buildings.Type.CHEST, 0],

		# --- drills: 2x2, facing E, ore output onto the chest beside each.
		# Their footprints sit on the seeded deposits (see seed_deposits).
		# Chests flush against the next drill's W edge are harmless: the
		# electric drill's fuel pull is gated off, and its output is E-only.
		[DR_A_OFFSET, Buildings.Type.ELECTRIC_DRILL, Belt.DIR_E],
		[DR_A_CHEST_OFFSET, Buildings.Type.CHEST, 0],
		[DR_B_OFFSET, Buildings.Type.ELECTRIC_DRILL, Belt.DIR_E],
		[DR_B_CHEST_OFFSET, Buildings.Type.CHEST, 0],
	]

## The eight rig-relative cells that carry a seeded STONE deposit — the full
## 2x2 footprint of each drill, so refresh_covered_deposits caches all four
## and the greedy pick has its normal spread to walk.
static func deposit_offsets() -> Array:
	var cells: Array = []
	for anchor in [DR_A_OFFSET, DR_B_OFFSET]:
		for dx in 2:
			for dy in 2:
				cells.append((anchor as Vector2i) + Vector2i(dx, dy))
	return cells

## Build the rig with its origin at `origin` (an ABSOLUTE tile).
##
## Returns a plain-data report:
##   { "placed": int, "skipped": int, "adopted": bool,
##     "gen_anchors": Array[Vector2i], "smelter_anchors": Array[Vector2i],
##     "drill_anchors": Array[Vector2i], "smelter_chests": Array[Vector2i],
##     "drill_chests": Array[Vector2i], "seeded_smelters": int }
##
## gen_anchors is ORDERED — the lever fuels the FIRST N of them, so index 0
## is the generator that stays lit in the brownout state.
static func build(world, origin: Vector2i) -> Dictionary:
	# ---- Phase 1: pave. ----
	# RigSupport.pave_rect carries the shared reasoning. The rig-specific
	# fact: STONE is in the requires_overlay intersection of every type used
	# here — STEAM_GENERATOR is the strict one at [STONE, PATH], CHEST allows
	# [STONE, PATH, SOIL_TILLED], the two electric machines both accept STONE.
	RigSupport.pave_rect(world, origin, PAVE_MIN, PAVE_MAX)

	# ---- Phase 1b: seed the drill deposits (fresh-build path). ----
	# Runs BETWEEN pave and placement because MiningDrill.validate_placement
	# refuses a drill with no covered ore — RigSupport.place_or_adopt cannot
	# express "prepare the ground this entry needs", and it should not: ore
	# is this rig's LAYOUT, not shared scaffolding. Cells that already hold a
	# building are skipped here for the same reason pave_rect skips them
	# (never strip terrain out from under someone else's building); the
	# rig's OWN standing drills get their deposits refreshed in Phase 3,
	# after adoption has proved they are ours.
	for off in deposit_offsets():
		var cell: Vector2i = origin + (off as Vector2i)
		if world.has_building_at(cell):
			continue
		_seed_deposit(world, cell)

	# ---- Phase 2: build, or ADOPT a rig that is already standing. ----
	# The BUILT / ADOPTED / COLLIDED classification lives on
	# RigSupport.place_or_adopt. The stakes for THIS rig: ADOPTED must hand
	# back the real machine anchors (or F8/F3 refuse a visibly complete
	# rig), and COLLIDED must not let Phase 3 seed a machine we did not
	# place — a player's ELECTRIC_SMELTER is type-identical to ours and the
	# in_buffer write below would destroy whatever they had loaded, no undo.
	# owned_anchors applies exactly that rule.
	var report: Dictionary = RigSupport.place_or_adopt(world, origin, plan())
	var gen_anchors: Array = RigSupport.owned_anchors(report, Buildings.Type.STEAM_GENERATOR)
	var smelter_anchors: Array = RigSupport.owned_anchors(report, Buildings.Type.ELECTRIC_SMELTER)
	var drill_anchors: Array = RigSupport.owned_anchors(report, Buildings.Type.ELECTRIC_DRILL)

	# ---- Phase 3: seed state (plain data only — house law). ----
	# Only ever seed machines this call placed, or ones adoption proved are
	# the rig's own. See the COLLIDED case above.
	var seeded_smelters: int = 0
	for anchor in smelter_anchors:
		if seed_smelter(world, anchor):
			seeded_smelters += 1
	# Re-seed the deposits under OWNED drills — the refill_source analog:
	# on adoption (a relaunch, or F3 after F9) the hand-seeded richness is
	# gone or drained, and a deposit sliding toward DEPLETED mid-observation
	# reads exactly like a machine fault. refresh_covered_deposits afterward
	# re-caches the footprint scan against the ground just written.
	for anchor in drill_anchors:
		var dr: Building = world.building_at(anchor)
		if dr == null or dr.type != Buildings.Type.ELECTRIC_DRILL:
			continue
		for dx in 2:
			for dy in 2:
				_seed_deposit(world, (anchor as Vector2i) + Vector2i(dx, dy))
		MiningDrill.refresh_covered_deposits(dr, world)

	# Start at FULL, with seed_output true — the ONLY call that seeds it
	# outside a test (ElectricRig.apply_power_state's docstring carries the
	# tick-ordering reason: a freshly placed generator derives output_active
	# one tick late, and the boot-order precondition in the test suite pins
	# that the first machine tick already sees satisfaction 1.0).
	ElectricRig.apply_power_state(world, gen_anchors, ElectricRig.POWER_FULL, true)
	# Belt and braces — the six poles already set the flag inside
	# place_building, but topology correctness is the whole rig.
	world.mark_power_network_dirty()

	return {
		"placed": int(report["placed"]),
		"skipped": int(report["skipped"]),
		"adopted": bool(report["adopted"]),
		"gen_anchors": gen_anchors,
		"smelter_anchors": smelter_anchors,
		"drill_anchors": drill_anchors,
		"smelter_chests": [origin + SM_A_CHEST_OFFSET, origin + SM_B_CHEST_OFFSET],
		"drill_chests": [origin + DR_A_CHEST_OFFSET, origin + DR_B_CHEST_OFFSET],
		"seeded_smelters": seeded_smelters,
	}

## Load one owned smelter's input buffer to SMELTER_ORE_COUNT. Returns true
## if a smelter was seeded. Called only with anchors owned_anchors approved.
static func seed_smelter(world, anchor: Vector2i) -> bool:
	if not world.has_building_at(anchor):
		return false
	var sm: Building = world.building_at(anchor)
	if sm == null or sm.type != Buildings.Type.ELECTRIC_SMELTER:
		return false
	sm.state["in_buffer"] = [[SMELTER_ORE_ITEM, SMELTER_ORE_COUNT]]
	return true

## Write one STONE deposit tile at full richness.
##
## Three writes, and why each:
##   tiles[cell]              — the live ground: GRASS base, Overlay.NONE
##                              (the drill's requires_overlay accepts NONE;
##                              set_overlay cannot be used here because its
##                              deposit guard refuses ore tiles — the same
##                              guard pave_rect resets resource_node to get
##                              past).
##   tile_modifications[cell] — the same Tile object, so the ORE TILE (not
##                              the paved-stone tile pave_rect recorded a
##                              moment ago) is what a save/load restores.
##                              Storing the shared object is the load path's
##                              own pattern (SaveSystem applies
##                              tile_modifications with one Tile in both
##                              maps). Without this the loaded ground would
##                              be blank stone with phantom drill coverage.
##   resource_state[cell]     — richness == original_richness, so the
##                              regrowth-index invariant holds (only
##                              regrowing/drained tiles belong in the
##                              index, and deplete_resource manages both
##                              the index and resource_state_modifications
##                              from here on).
## Richness itself does NOT ride the save — see NOT PERSISTED in the header.
static func _seed_deposit(world, cell: Vector2i) -> void:
	var t: Tile = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.STONE)
	world.tiles[cell] = t
	world.tile_modifications[cell] = t
	world.resource_state[cell] = {"richness": ORE_RICHNESS, "original_richness": ORE_RICHNESS}

## Human-readable lever description with the numbers the user is meant to
## check against the Q-inspect panels. Same three-state shape as
## ElectricRig.state_label; main.gd picks this one when the processor rig is
## the registered kind, so the toast never quotes the inserter's cycle
## numbers at a smelter.
static func state_label(state: int) -> String:
	match clampi(state, 0, ElectricRig.POWER_STATE_COUNT - 1):
		ElectricRig.POWER_FULL:
			return "POWER: FULL — 2 of 2 generators fuelled, satisfaction 1.00, smelters+drills 32 ticks/cycle"
		ElectricRig.POWER_BROWNOUT:
			return "POWER: BROWNOUT — 1 of 2 generators fuelled, satisfaction 0.50, smelters+drills 64 ticks/cycle"
		_:
			return "POWER: ZERO — 0 of 2 generators fuelled, satisfaction 0.00, all four machines NO POWER"
