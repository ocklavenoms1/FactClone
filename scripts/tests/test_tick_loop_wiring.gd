extends RefCounted

## TICK-LOOP WIRING — the simulation loop actually CALLS the systems it drives.
##
## Every other suite in this project invokes a system function DIRECTLY with
## hand-supplied arguments: `world._tick_soil_regen(1.0)`, `Belt.tick(b, w)`,
## `PowerNetwork.update_supply_demand(world)`. None of them goes through
## `GridWorld._on_tick` or `GridWorld._process`. So a deleted CALL SITE ships
## green — remove `_tick_soil_regen(delta)` from `_process` and all 44
## soil-arc sub-suites still pass, because they never went through `_process`
## in the first place. The suite pins the FUNCTIONS; nothing pinned the WIRING.
##
## That is the same failure class `test_registration_completeness.gd` guards:
## absence indistinguishable from success. A dropped call site reddens no
## assertion and prints no warning; the systems simply stop running and the
## suite keeps reporting the same green count. This file is the detector.
##
## ---------------------------------------------------------------------------
## MEASURED, not assumed — the seven call sites were deleted one at a time
## ---------------------------------------------------------------------------
##
## Each row was produced by removing that one line from `grid_world.gd` and
## running the full suite. "suite before" is the 54-suite run WITHOUT this
## file; "reddens here" is the sub-case(s) of this file that caught it.
##
##   call site (grid_world.gd)          suite before   reddens here
##   ---------------------------------  -------------  ------------
##   _ready  TickSystem.tick.connect    18 suites red  (1)(2)(3)(4)(5)(6)
##   _on_tick  update_supply_demand      2 suites red  (2)
##   _on_tick  Buildings.tick_one       18 suites red  (3)(5)(6)
##   _on_tick  Buildings.post_tick_one   ALL 54 GREEN  (4)
##   _process  _tick_regrowth            ALL 54 GREEN  (7)
##   _process  _tick_fertilizer_decay    ALL 54 GREEN  (8)
##   _process  _tick_soil_regen          ALL 54 GREEN  (9)
##
## So FOUR of the seven were genuinely undetectable: delete
## `Buildings.post_tick_one` and belt-to-belt handoff stops everywhere in the
## game while the suite prints "54 passed, 0 failed". Belt CHAINS are the
## casualty and no suite noticed. What makes that possible: belt-to-belt
## handoff is the ONLY thing `post_tick_one` dispatches, and every other
## consumer takes items off a belt by pulling (`Chest.tick`,
## `Processor._try_pull_inputs`, `Inserter._try_pickup`) rather than by being
## pushed to. So a suite can run a belt end-to-end into a chest and never
## exercise pass 2 at all.
##
## The other three DO redden existing suites, but only with downstream
## symptoms — "expected ≥9 grain, got 0", "satisfaction should be 1.0, got
## 0.0" — spread across up to 18 suites at once, with nothing naming the
## cause. Those rows are still worth their sub-cases: a wall of red that says
## the factory stopped is a worse diagnostic than one line that says which
## call went missing.
##
## ---------------------------------------------------------------------------
## ⚠ THIS FILE PINS THE WIRING AS IT IS TODAY. IT DOES NOT BLESS IT.
## ---------------------------------------------------------------------------
##
## `GridWorld` today runs TWO CLOCKS. Buildings, belts, processors, inserters
## and the power pre-pass advance on `TickSystem.tick`. Tree regrowth,
## fertilizer decay and soil regen advance on the raw engine frame delta in
## `_process`. That split was **audit finding #31**, scoped in full at
## `docs/scoping/r1-two-clocks.md` — **DECIDED 2026-08-26: option 2.** The
## split is deliberate (tick clock = factory sim; wall-clock = slow world
## processes), the old "only clock" comment was the defect, and this file's
## pinned wiring is now the RATIFIED design, not a snapshot of an open
## question. Sub-cases 7-9 going red now means someone moved the three
## systems off wall-clock — which reverses a recorded decision and must be
## said out loud, not absorbed.
##
## ⚠ A LATENT ACCIDENT WORTH KNOWING, measured in the #31 design pass: under
## a hypothetical every-N-ticks wiring (the rejected option 4, N=20), the
## tick-side NEGATIVE halves of (7) and (8) would stay green BY LUCK — this
## file's single emissions land on ticks 7 and 8, neither ≡ 0 mod 20, so an
## N-gate would simply never fire during the test. Any emission added earlier
## in this file shifts which ticks those land on. If an N-gated wiring is
## ever evaluated again, do NOT read those negatives as the contract holding;
## emit N consecutive ticks so the gate provably fires.
##
## What it does do is make the split VISIBLE. Each sub-case asserts both
## directions: the tick path drives what it drives AND does not drive what it
## does not; the `_process` path likewise. So the day #31 is decided and the
## three environmental systems move onto ticks (options 1/3/4), sub-cases 7-9
## go RED and the author has to come here and say so. If instead the law is
## amended to name two clocks deliberately (option 2), the file already
## documents the wiring that decision ratifies and nothing needs to change.
##
## A test written to accept EITHER wiring would recreate the exact gap it
## exists to close, so the negative halves are load-bearing, not decoration.
## `docs/scoping/r1-two-clocks.md` says "the first work item under any option
## is a test that exercises the wiring". This is that work item.
##
## ---------------------------------------------------------------------------
## The seven wiring points, all of them mutation-tested
## ---------------------------------------------------------------------------
##
## `grid_world.gd` `_ready` — the top-level subscription. If this line goes,
## everything below it stops and nothing else notices:
##   0. `TickSystem.tick.connect(_on_tick)`               → sub-case (1)
##
## `grid_world.gd` `_on_tick`, reached via a `TickSystem.tick` emission:
##   1. `PowerNetwork.update_supply_demand(self)`         → sub-case (2)
##   2. `Buildings.tick_one(...)` for every building      → sub-cases (3)(5)(6)
##   3. `Buildings.post_tick_one(...)` for every building → sub-case (4)
##
## `grid_world.gd` `_process(delta)`:
##   4. `_tick_regrowth(delta)`                           → sub-case (7)
##   5. `_tick_fertilizer_decay(delta)`                   → sub-case (8)
##   6. `_tick_soil_regen(delta)`                         → sub-case (9)
##
## Sub-case (10) is the reverse pin for 1-3: `_process` must NOT advance
## buildings. Sub-cases (7)-(9) carry the reverse pin for 4-6 inline.
##
## Belts, processors and inserters all route through `Buildings.tick_one` /
## `post_tick_one`, so they are covered by placing one of each and asserting
## the OBSERVABLE STATE CHANGE one tick produces — an item advancing a belt
## slot, a mill consuming its input and entering RUNNING, an inserter picking
## an item up. Never "the function was called": no call-counter, no
## instrumentation, nothing added to production code for this file's benefit.
##
## Every sub-case carries a PREMISE check before it asserts anything, for the
## same reason `test_registration_completeness.gd` does: a sub-case that finds
## zero buildings to tick, or a starting state that already looks like the
## expected outcome, would pass while checking nothing.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "tick-loop wiring (TickSystem.tick drives power pre-pass + both building passes; _process drives regrowth + fertilizer decay + soil regen)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_1_world_subscribes_to_tick(parent, failures)
	_case_2_tick_drives_power_pre_pass(parent, failures)
	_case_3_tick_drives_building_pass_1(parent, failures)
	_case_4_tick_drives_building_pass_2(parent, failures)
	_case_5_tick_drives_processor(parent, failures)
	_case_6_tick_drives_inserter(parent, failures)
	_case_7_process_drives_regrowth(parent, failures)
	_case_8_process_drives_fertilizer_decay(parent, failures)
	_case_9_process_drives_soil_regen(parent, failures)
	_case_10_process_does_not_drive_buildings(parent, failures)

	if failures.is_empty():
		return { "ok": true, "message": "10 sub-cases pass: world subscribes to TickSystem.tick; a tick drives the power pre-pass, building pass 1 (belt shift, mill, inserter) and building pass 2 (belt handoff); _process drives regrowth, fertilizer decay and soil regen; neither clock does the other's work" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# ===========================================================================
# (1) THE SUBSCRIPTION ITSELF — `TickSystem.tick.connect(_on_tick)` in
# GridWorld._ready.
#
# Pinned on its own because it is the single line every other tick assertion
# in the repo silently depends on. Delete it and `_on_tick` becomes dead code:
# no belt moves, no processor advances, no power number updates.
#
# This one is NOT invisible to the existing suite — measured, its deletion
# reddens 18 other suites. What they do not do is say why: they report grain
# that never arrived and satisfaction stuck at zero, 18 suites deep, and a
# reader has to work backwards to a missing `connect`. This sub-case reports
# the missing `connect`.
# ===========================================================================
static func _case_1_world_subscribes_to_tick(parent: Node, failures: Array) -> void:
	# PREMISE: the runner disconnects every listener between suites, so a
	# stray connection carried in from an earlier suite would make the
	# assertion below true without this world having subscribed at all.
	var pre_existing: int = TickSystem.tick.get_connections().size()
	_check(failures, pre_existing == 0,
		"(1) PREMISE: %d listener(s) were already on TickSystem.tick before this world was built, so 'is_connected' cannot attribute the connection to GridWorld._ready" % pre_existing)

	var world = _bare_world(parent)
	_check(failures, TickSystem.tick.is_connected(world._on_tick),
		"(1) GridWorld is NOT connected to TickSystem.tick after entering the tree. Nothing in _on_tick can ever run — no belts, no processors, no power pre-pass — and every other tick assertion in this repo is unreachable through the real wiring. Restore `TickSystem.tick.connect(_on_tick)` in GridWorld._ready")
	_teardown(world)

# ===========================================================================
# (2) POWER PRE-PASS — `PowerNetwork.update_supply_demand(self)`, the first
# statement of _on_tick.
#
# `world._component_demand` is written in exactly one place in the whole
# project (power_network.gd, inside update_supply_demand), and
# update_supply_demand itself is called from exactly one non-test place
# (grid_world.gd, inside _on_tick). So demand appearing on a component is
# unambiguous evidence that the pre-pass ran, and this sub-case deliberately
# never calls update_supply_demand itself.
# ===========================================================================
static func _case_2_tick_drives_power_pre_pass(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.POWER_POLE, Vector2i(8, 8)):
		_check(failures, false, "(2) SETUP: could not place power pole at (8,8)")
		_teardown(world)
		return
	if not world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(9, 8)):
		_check(failures, false, "(2) SETUP: could not place electric lamp at (9,8)")
		_teardown(world)
		return

	# Resolve the component. This also forces the topology rebuild, which
	# clears _component_demand — so the "before" reading below is a real
	# post-rebuild zero, not an untouched-dict zero.
	var comp: int = PowerNetwork.network_id_at(world, Vector2i(8, 8))
	_check(failures, comp >= 0,
		"(2) PREMISE: pole at (8,8) resolved to no power component (got %d), so demand could never be attributed to it" % comp)
	if comp < 0:
		_teardown(world)
		return
	_check(failures, world.buildings.size() == 2,
		"(2) PREMISE: expected 2 buildings (pole + lamp) for the pre-pass to aggregate, found %d" % world.buildings.size())
	_check(failures, ElectricLamp.DEMAND > 0,
		"(2) PREMISE: ElectricLamp.DEMAND is %d, so a populated pre-pass would be indistinguishable from an absent one" % ElectricLamp.DEMAND)
	_check(failures, PowerNetwork.demand_for(world, comp) == 0,
		"(2) PREMISE: component demand was already %d before any tick, so the assertion below cannot show the pre-pass ran" % PowerNetwork.demand_for(world, comp))

	# The OTHER clock must not do this work.
	world._process(1.0)
	_check(failures, PowerNetwork.demand_for(world, comp) == 0,
		"(2) _process advanced the power pre-pass (demand %d). The pre-pass belongs to _on_tick; if this moved deliberately, this sub-case is the record that it moved" % PowerNetwork.demand_for(world, comp))

	_emit_one_tick()
	_check(failures, PowerNetwork.demand_for(world, comp) == ElectricLamp.DEMAND,
		"(2) after one TickSystem.tick emission, component demand should be the lamp's DEMAND (%d), got %d. _on_tick is not calling PowerNetwork.update_supply_demand(self) — the power pre-pass never runs, so every consumer reads a network that is permanently at zero supply and zero demand" % [ElectricLamp.DEMAND, PowerNetwork.demand_for(world, comp)])
	_teardown(world)

# ===========================================================================
# (3) BUILDING PASS 1 — `Buildings.tick_one(...)`, via a belt shifting an
# item forward WITHIN its own slots.
#
# A lone belt with nothing downstream is the point: `Belt.post_tick` returns
# at its `has_building_at` guard, so pass 2 cannot contribute anything here
# and the observed movement is pass 1 alone.
# ===========================================================================
static func _case_3_tick_drives_building_pass_1(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_E):
		_check(failures, false, "(3) SETUP: could not place belt at (10,10)")
		_teardown(world)
		return
	var belt: Building = world.building_at(Vector2i(10, 10))
	_check(failures, Belt.try_insert(belt, Items.Type.WHEAT),
		"(3) SETUP: belt refused the seed item")

	_check(failures, world.buildings.size() == 1,
		"(3) PREMISE: expected exactly 1 building (the belt) so nothing else can move the item, found %d" % world.buildings.size())
	_check(failures, not world.has_building_at(Vector2i(11, 10)),
		"(3) PREMISE: something is downstream of the belt, so pass 2 could account for the movement this sub-case attributes to pass 1")
	var slots: Array = belt.state["slots"]
	_check(failures, int(slots[0]) == Items.Type.WHEAT and int(slots[1]) == -1,
		"(3) PREMISE: belt should start as [item, empty, ...], got %s" % str(slots))

	# Belts only shift on an advance tick, so land the emission on one.
	TickSystem.current_tick = Belt.TICKS_PER_SLOT
	_check(failures, Belt.is_advance_tick(),
		"(3) PREMISE: tick %d is not a belt advance tick, so a correctly-wired pass 1 would move nothing" % TickSystem.current_tick)
	TickSystem.tick.emit(TickSystem.current_tick)

	_check(failures, int(slots[1]) == Items.Type.WHEAT and int(slots[0]) == -1,
		"(3) after one belt advance tick the item should have shifted from slot 0 to slot 1, slots are %s. _on_tick is not calling Buildings.tick_one — pass 1 never runs, so nothing on the map advances its own internal state: belts freeze, processors never start, inserters never pick up" % str(slots))
	_teardown(world)

# ===========================================================================
# (4) BUILDING PASS 2 — `Buildings.post_tick_one(...)`, via a belt handing
# its front item to the belt downstream.
#
# BELT is the only type `post_tick_one` dispatches, so this handoff is the
# whole observable surface of pass 2. The item is seeded in the FRONT slot,
# which pass 1 cannot move (`Belt.tick` only fills empty slots from behind),
# so a crossing item is pass 2 and nothing else — measured: deleting
# `Buildings.tick_one` reddens sub-cases (3), (5) and (6) but leaves this one
# green, and deleting `post_tick_one` reddens this one alone.
#
# This is the call site that was WHOLLY uncovered. Removing
# `Buildings.post_tick_one` from _on_tick and running the pre-existing suite
# gives "54 passed, 0 failed" with belt chains dead across the entire game.
# ===========================================================================
static func _case_4_tick_drives_building_pass_2(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_E):
		_check(failures, false, "(4) SETUP: could not place upstream belt at (10,10)")
		_teardown(world)
		return
	if not world.place_building(Buildings.Type.BELT, Vector2i(11, 10), Belt.DIR_E):
		_check(failures, false, "(4) SETUP: could not place downstream belt at (11,10)")
		_teardown(world)
		return
	var up: Building = world.building_at(Vector2i(10, 10))
	var down: Building = world.building_at(Vector2i(11, 10))
	var up_slots: Array = up.state["slots"]
	var down_slots: Array = down.state["slots"]
	var front: int = Belt.SLOTS_PER_TILE - 1
	up_slots[front] = Items.Type.WHEAT

	_check(failures, world.buildings.size() == 2,
		"(4) PREMISE: expected 2 belts for a handoff, found %d" % world.buildings.size())
	_check(failures, int(down_slots[0]) == -1,
		"(4) PREMISE: downstream belt's back slot already holds %d, so a handoff would be invisible" % int(down_slots[0]))
	_check(failures, int(up_slots[front]) == Items.Type.WHEAT,
		"(4) PREMISE: upstream belt's front slot should hold the seeded item, got %d" % int(up_slots[front]))

	TickSystem.current_tick = Belt.TICKS_PER_SLOT
	_check(failures, Belt.is_advance_tick(),
		"(4) PREMISE: tick %d is not a belt advance tick, so a correctly-wired pass 2 would move nothing" % TickSystem.current_tick)
	TickSystem.tick.emit(TickSystem.current_tick)

	_check(failures, int(down_slots[0]) == Items.Type.WHEAT,
		"(4) after one belt advance tick the item should have crossed into the downstream belt's back slot, got %d. _on_tick is not calling Buildings.post_tick_one — pass 2 never runs, so items ride to the end of a belt tile and stop there: every belt chain in the game deadlocks one tile short of its destination" % int(down_slots[0]))
	_check(failures, int(up_slots[front]) == -1,
		"(4) upstream belt's front slot should have been vacated by the handoff, still holds %d" % int(up_slots[front]))
	_teardown(world)

# ===========================================================================
# (5) PROCESSORS ride pass 1 — a Mill consuming its input and entering
# RUNNING.
#
# Covers the user's "processors" line. A loaded, idle Mill takes exactly one
# tick to consume its grain and set progress to 1; with no adjacent belts the
# pull and push halves of Processor.tick are no-ops, so the state change is
# the recipe machine and nothing else.
# ===========================================================================
static func _case_5_tick_drives_processor(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.MILL, Vector2i(10, 10)):
		_check(failures, false, "(5) SETUP: could not place mill at (10,10)")
		_teardown(world)
		return
	var mill: Building = world.building_at(Vector2i(10, 10))
	mill.state["in_buffer"] = [[Items.Type.GRAIN, 1]]
	mill.state["out_buffer"] = []
	mill.state["state"] = Processor.IDLE
	mill.state["progress"] = 0

	_check(failures, world.buildings.size() == 1,
		"(5) PREMISE: expected exactly 1 building (the mill), found %d" % world.buildings.size())
	var recipe: Dictionary = Recipes.get_recipe(String(mill.state["recipe_id"]))
	_check(failures, not recipe.is_empty(),
		"(5) PREMISE: mill has no resolvable recipe (%s), so Processor.tick returns immediately and could never advance" % String(mill.state["recipe_id"]))
	_check(failures, int(mill.state["progress"]) == 0 and int(mill.state["state"]) == Processor.IDLE,
		"(5) PREMISE: mill should start IDLE at progress 0, got state %d progress %d" % [int(mill.state["state"]), int(mill.state["progress"])])

	_emit_one_tick()

	_check(failures, int(mill.state["state"]) == Processor.RUNNING,
		"(5) after one tick the loaded mill should be RUNNING (%d), got %d. Buildings.tick_one is not being called from _on_tick, so no recipe machine in the game ever starts a cycle" % [Processor.RUNNING, int(mill.state["state"])])
	_check(failures, int(mill.state["progress"]) == 1,
		"(5) after one tick the mill's progress should be 1, got %d" % int(mill.state["progress"]))
	_check(failures, _bag_count(mill.state["in_buffer"], Items.Type.GRAIN) == 0,
		"(5) the mill should have consumed its grain when the cycle started, %d left in the input buffer" % _bag_count(mill.state["in_buffer"], Items.Type.GRAIN))
	_teardown(world)

# ===========================================================================
# (6) INSERTERS ride pass 1 — an inserter starting a cycle.
#
# Covers the user's "inserters" line. A fuelled basic inserter with a stocked
# source takes exactly one tick to pick an item up and enter WORKING_OUT.
# Chests only pull from adjacent BELTS, and there are none here, so neither
# chest can move an item on its own.
# ===========================================================================
static func _case_6_tick_drives_inserter(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.INSERTER, Vector2i(10, 10), Belt.DIR_E):
		_check(failures, false, "(6) SETUP: could not place inserter at (10,10)")
		_teardown(world)
		return
	if not world.place_building(Buildings.Type.CHEST, Vector2i(9, 10)):
		_check(failures, false, "(6) SETUP: could not place source chest at (9,10)")
		_teardown(world)
		return
	if not world.place_building(Buildings.Type.CHEST, Vector2i(11, 10)):
		_check(failures, false, "(6) SETUP: could not place destination chest at (11,10)")
		_teardown(world)
		return
	var ins: Building = world.building_at(Vector2i(10, 10))
	var src: Building = world.building_at(Vector2i(9, 10))
	ins.state["fuel_buffer"] = 100
	src.state["bag"] = [[Items.Type.WHEAT, 5]]

	_check(failures, world.buildings.size() == 3,
		"(6) PREMISE: expected 3 buildings (source chest, inserter, destination chest), found %d" % world.buildings.size())
	_check(failures, Inserter.held_item_type(ins) == -1,
		"(6) PREMISE: inserter starts with an item already in hand (%d), so a pickup would be invisible" % Inserter.held_item_type(ins))
	_check(failures, _bag_count(src.state["bag"], Items.Type.WHEAT) == 5,
		"(6) PREMISE: source chest should start with 5 wheat, got %d" % _bag_count(src.state["bag"], Items.Type.WHEAT))

	_emit_one_tick()

	_check(failures, Inserter.held_item_type(ins) == Items.Type.WHEAT,
		"(6) after one tick the inserter should be holding a wheat, holds %d. Buildings.tick_one is not being called from _on_tick, so no inserter in the game ever starts a cycle and the whole factory stops moving items between machines" % Inserter.held_item_type(ins))
	_check(failures, int(ins.state["state"]) == Inserter.STATE_WORKING_OUT,
		"(6) after one tick the inserter should be in STATE_WORKING_OUT (%d), got %d" % [Inserter.STATE_WORKING_OUT, int(ins.state["state"])])
	_check(failures, _bag_count(src.state["bag"], Items.Type.WHEAT) == 4,
		"(6) the picked-up wheat should have left the source chest (5 → 4), chest holds %d" % _bag_count(src.state["bag"], Items.Type.WHEAT))
	_teardown(world)

# ===========================================================================
# (7) REGROWTH runs on `_process` — `_tick_regrowth(delta)`.
#
# ⚠ THE NEGATIVE HALF IS DELIBERATE AND IS FINDING #31's TRIPWIRE. Asserting
# that a tick does NOT advance regrowth pins today's split rather than
# accepting either clock. If the three environmental systems move onto
# `TickSystem.tick`, this sub-case goes red — by design. It is not a claim
# that the split is correct; see the file header and
# `docs/scoping/r1-two-clocks.md`.
# ===========================================================================
static func _case_7_process_drives_regrowth(parent: Node, failures: Array) -> void:
	var world = _bare_world(parent)
	var pos: Vector2i = Vector2i(5, 5)
	# Seed through the real public path, NOT by writing resource_state
	# directly. Since audit #29 (2026-08-26) _tick_regrowth iterates the
	# _active_regrowth index that chop_tree maintains; a hand-written
	# resource_state entry is invisible to it, and this sub-case would
	# have reported "(_process is not calling _tick_regrowth" — a false
	# diagnosis. The two pinned claims below (a tick does NOT advance the
	# timer; _process DOES) are unchanged: this is a fixture change, not a
	# clock change.
	world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)
	world.chop_tree(pos)
	var start: float = world.regrowth_remaining_at(pos)

	_check(failures, absf(start - GridWorldScript.TREE_REGROWTH_SECONDS) < 0.001,
		"(7) PREMISE: seeded regrowth timer reads %f, expected %f" % [start, GridWorldScript.TREE_REGROWTH_SECONDS])
	_check(failures, start > 2.0,
		"(7) PREMISE: regrowth timer starts at %f, too short to survive the 1.0s step below without restoring the tree and erasing the value being measured" % start)

	_emit_one_tick()
	_check(failures, absf(world.regrowth_remaining_at(pos) - start) < 0.001,
		"(7) a TickSystem.tick emission advanced the regrowth timer (%f → %f). Regrowth is wired to _process today, NOT to ticks — this is audit finding #31's split. If it moved onto ticks deliberately, update this sub-case and say so; do not make it accept both clocks" % [start, world.regrowth_remaining_at(pos)])

	world._process(1.0)
	_check(failures, absf(world.regrowth_remaining_at(pos) - (start - 1.0)) < 0.001,
		"(7) after _process(1.0) the regrowth timer should read %f, got %f. GridWorld._process is not calling _tick_regrowth(delta) — chopped trees never come back, on either clock" % [start - 1.0, world.regrowth_remaining_at(pos)])
	_teardown(world)

# ===========================================================================
# (8) FERTILIZER DECAY runs on `_process` — `_tick_fertilizer_decay(delta)`.
#
# Same two-sided shape as (7); the negative half is the #31 tripwire.
# ===========================================================================
static func _case_8_process_drives_fertilizer_decay(parent: Node, failures: Array) -> void:
	var world = _bare_world(parent)
	var pos: Vector2i = Vector2i(6, 6)
	var tier: int = Items.Type.COMPOST_HIGH
	# Exactly the shape GridWorld.try_apply_fertilizer writes.
	world.tile_fertilizer_state[pos] = {"tier": tier, "remaining": world.fertilizer_duration(tier)}
	var start: float = world.tile_fertilizer_remaining(pos)

	_check(failures, start > 2.0,
		"(8) PREMISE: seeded fertilizer boost has %f seconds left, too short to survive the 1.0s step below without expiring and erasing the entry being measured" % start)
	_check(failures, world.tile_fertilizer_tier(pos) == tier,
		"(8) PREMISE: seeded boost tier reads %d, expected %d" % [world.tile_fertilizer_tier(pos), tier])

	_emit_one_tick()
	_check(failures, absf(world.tile_fertilizer_remaining(pos) - start) < 0.001,
		"(8) a TickSystem.tick emission decayed the fertilizer boost (%f → %f). Fertilizer decay is wired to _process today, NOT to ticks — audit finding #31's split. If it moved onto ticks deliberately, update this sub-case; do not make it accept both clocks" % [start, world.tile_fertilizer_remaining(pos)])

	world._process(1.0)
	_check(failures, absf(world.tile_fertilizer_remaining(pos) - (start - 1.0)) < 0.001,
		"(8) after _process(1.0) the boost should read %f seconds, got %f. GridWorld._process is not calling _tick_fertilizer_decay(delta) — an applied boost never expires, so fertilizer becomes permanent" % [start - 1.0, world.tile_fertilizer_remaining(pos)])
	_teardown(world)

# ===========================================================================
# (9) SOIL REGEN runs on `_process` — `_tick_soil_regen(delta)`.
#
# Same two-sided shape as (7) and (8); the negative half is the #31 tripwire.
#
# The tile starts at soil 3 rather than 0 so the wasteland grace branch is not
# involved: this sub-case is about the regen call site, not about scarring.
# The step below is deliberately one SECONDS_PER_SOIL_POINT plus a margin, so
# `int(prog)` clears 1 without sitting on the rounding boundary.
# ===========================================================================
static func _case_9_process_drives_soil_regen(parent: Node, failures: Array) -> void:
	var world = _bare_world(parent)
	var pos: Vector2i = Vector2i(7, 7)
	world.tile_soil_modifications[pos] = 3

	_check(failures, world.tile_soil_health(pos) == 3,
		"(9) PREMISE: seeded soil reads %d, expected 3" % world.tile_soil_health(pos))
	_check(failures, world.buildings.is_empty(),
		"(9) PREMISE: %d building(s) present; an active planter's 3x3 would suppress regen on this tile and the sub-case would measure nothing" % world.buildings.size())
	_check(failures, not world.is_wasteland_at(pos),
		"(9) PREMISE: tile is already scarred, and scarred tiles skip regen entirely")

	_emit_one_tick()
	_check(failures, world.tile_soil_health(pos) == 3,
		"(9) a TickSystem.tick emission regenerated soil (3 → %d). Soil regen is wired to _process today, NOT to ticks — audit finding #31's split. If it moved onto ticks deliberately, update this sub-case; do not make it accept both clocks" % world.tile_soil_health(pos))

	# One soil point is SECONDS_PER_SOIL_POINT of unboosted regen; +1.0 keeps
	# the truncation off its boundary.
	world._process(GridWorldScript.SECONDS_PER_SOIL_POINT + 1.0)
	_check(failures, world.tile_soil_health(pos) == 4,
		"(9) after _process(%.1f) the tile should have gained exactly 1 soil point (3 → 4), reads %d. GridWorld._process is not calling _tick_soil_regen(delta) — depleted soil never recovers and no soil-0 tile ever starts its wasteland grace countdown" % [GridWorldScript.SECONDS_PER_SOIL_POINT + 1.0, world.tile_soil_health(pos)])
	_teardown(world)

# ===========================================================================
# (10) THE REVERSE PIN FOR THE TICK SIDE — `_process` must NOT advance
# buildings.
#
# Sub-cases (7)-(9) assert ticks do not do `_process`'s work. This is the
# mirror: `_process` does not do the tick loop's work. Together they mean the
# file cannot be satisfied by "either path works", which is the failure mode
# that would recreate the gap this file exists to close.
#
# Note what this sub-case does NOT do: it is not covered by deleting any of
# the seven call sites (those all redden sub-cases 1-9). It reddens on the
# REVERSE move — someone adding a building tick to `_process`.
# ===========================================================================
static func _case_10_process_does_not_drive_buildings(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_E):
		_check(failures, false, "(10) SETUP: could not place belt at (10,10)")
		_teardown(world)
		return
	if not world.place_building(Buildings.Type.MILL, Vector2i(10, 12)):
		_check(failures, false, "(10) SETUP: could not place mill at (10,12)")
		_teardown(world)
		return
	var belt: Building = world.building_at(Vector2i(10, 10))
	var mill: Building = world.building_at(Vector2i(10, 12))
	_check(failures, Belt.try_insert(belt, Items.Type.WHEAT),
		"(10) SETUP: belt refused the seed item")
	mill.state["in_buffer"] = [[Items.Type.GRAIN, 1]]
	mill.state["state"] = Processor.IDLE
	mill.state["progress"] = 0

	# PREMISE: park the clock on a belt advance tick, so a belt that WERE
	# ticked from _process would visibly move. Without this the negative below
	# would hold for the wrong reason.
	TickSystem.current_tick = Belt.TICKS_PER_SLOT
	_check(failures, Belt.is_advance_tick(),
		"(10) PREMISE: tick %d is not a belt advance tick, so an incorrectly _process-driven belt would stand still anyway and the assertion would prove nothing" % TickSystem.current_tick)
	_check(failures, world.buildings.size() == 2,
		"(10) PREMISE: expected 2 buildings to leave un-advanced, found %d" % world.buildings.size())

	for _i in 20:
		world._process(TickSystem.TICK_INTERVAL_SEC)

	var slots: Array = belt.state["slots"]
	_check(failures, int(slots[0]) == Items.Type.WHEAT,
		"(10) 20 _process calls advanced the belt (slots %s). Buildings advance on TickSystem.tick, not on the frame clock; a building tick added to _process would double-drive every machine in the game" % str(slots))
	_check(failures, int(mill.state["state"]) == Processor.IDLE and int(mill.state["progress"]) == 0,
		"(10) 20 _process calls advanced the mill (state %d, progress %d). Processors advance on TickSystem.tick, not on the frame clock" % [int(mill.state["state"]), int(mill.state["progress"])])
	_teardown(world)

# ---------- helpers ----------

## A world with no terrain painted — for the tile-level systems, which read
## dictionaries directly and need no placeable ground.
static func _bare_world(parent: Node):
	var w = GridWorldScript.new()
	parent.add_child(w)
	return w

## A world with a STONE patch wide enough for every building this file places.
## STONE satisfies belt, chest, mill, pole, lamp and inserter placement rules
## alike, so one overlay choice keeps the setups uniform.
static func _make_world(parent: Node):
	var w = _bare_world(parent)
	for x in range(6, 14):
		for y in range(6, 14):
			w.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	return w

## The established emission idiom — grep any recent suite.
static func _emit_one_tick() -> void:
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)

## Audit #69: disconnect BEFORE queue_free, on every path including the early
## returns above. A freed world still on TickSystem.tick is a dangling
## listener that later suites pay for.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
