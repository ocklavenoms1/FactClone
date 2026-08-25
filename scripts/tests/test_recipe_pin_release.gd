extends RefCounted

## Audit findings #15 and #18 — the SAME defect in two files.
##
## Smelter and Composter both pin `recipe_id` and both re-run selection only
## while the machine is IDLE. Neither had a path back when the pin went bad, so
## a bad pin was permanent. Two ways a pin goes bad, one measured per file:
##
##   #15 UNSTARTABLE PIN (composter, reachable in ordinary play).
##       `_maybe_select_recipe` branch (1) returns on the FIRST buffer entry
##       that maps to a recipe, without asking whether that recipe can run.
##       Every composter recipe except the loaf-pack one needs TWO of its
##       input. A lone WHEAT therefore pins `composter_low_wheat` forever,
##       and `Processor._try_pull_inputs` — which filters by the pinned
##       recipe — then refuses to pull anything else. MEASURED before the fix:
##       600 ticks with in_buffer [[WHEAT,1]] and a four-slot FLAX belt on the
##       E edge left recipe_id='composter_low_wheat', out_buffer empty and all
##       four flax still on the belt. The branch-(2) port peek exists precisely
##       to notice that flax; branch (1)'s early return made it unreachable.
##       (Verified by clearing the lone wheat and re-running selection: it then
##       picked 'composter_low_flax' — the peek could see the flax all along.)
##
##   #18 UNRESOLVABLE PIN (both files, reachable from any save).
##       `Recipes.get_recipe` returns {} for an id not in the registry, and
##       says so in its own comment: "if a save references a recipe ID that's
##       been renamed/removed". SaveSystem restores building state verbatim and
##       never validates recipe_id. A machine saved mid-batch whose recipe is
##       later renamed reloads non-IDLE with an unresolvable pin; the tick then
##       bails at `if recipe.is_empty(): return` BEFORE the state machine, while
##       selection is gated on IDLE and so can never run. MEASURED before the
##       fix: a smelter forced to NO_FUEL with recipe 'smelt_mithril', 4 ore and
##       99 fuel sat for 400 ticks with state=2, ore untouched, output empty;
##       a composter forced to RUNNING with recipe 'composter_gone' and 4 wheat
##       did the same for 400 ticks. One push_warning, once per id, ever.
##
## NOTE ON #18's ORIGINAL TITLE — "STATE_NO_FUEL has no fallback". That is
## false and case (F) pins it false: `Burner.try_pull_fuel` is step 1 of
## `Smelter.tick` and runs unconditionally, including while NO_FUEL, and the
## STATE_NO_FUEL arm re-checks and restarts. A NO_FUEL smelter with a valid
## recipe recovers on its own the tick fuel arrives, from a belt. The real
## defect is the unresolvable pin above.
##
## THE SHARED RULE, applied identically to both files:
##   A recipe_id may stay pinned only while it is RESOLVABLE and STARTABLE.
##   Every tick that finds it unresolvable releases the pin; selection prefers
##   a buffer entry that can actually start, and falls through to the port peek
##   rather than pinning one that cannot.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "recipe pin release (#15 unstartable pin, #18 unresolvable pin)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_a_composter_starved_pin(parent, failures)
	_case_b_satisfiable_pin_not_abandoned(parent, failures)
	_case_c_smelter_fifo_preserved(parent, failures)
	_case_d_smelter_dead_recipe(parent, failures)
	_case_e_composter_dead_recipe(parent, failures)
	_case_f_no_fuel_still_recovers(parent, failures)
	_case_g_fresh_machine_unaffected(parent, failures)
	_case_h_stalled_crop_is_named(parent, failures)
	_case_i_no_fuel_survives_input_removal(parent, failures)
	_case_j_no_fuel_narrowness(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": " | ".join(failures) }

## (A) #15. A lone wheat must not shadow a belt full of flax.
static func _case_a_composter_starved_pin(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.COMPOSTER, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_W)
	var comp: Building = world.building_at(Vector2i(0, 0))
	var belt: Building = world.building_at(Vector2i(1, 0))

	comp.state["in_buffer"] = [[Items.Type.WHEAT, 1]]     # needs 2 — unstartable
	for i in Belt.SLOTS_PER_TILE:
		belt.state["slots"][i] = Items.Type.FLAX          # 4 flax, needs 2

	for _t in 600:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var compost: int = _bag_count(comp.state["out_buffer"], Items.Type.COMPOST_LOW) \
		+ _slot_count(belt, Items.Type.COMPOST_LOW)
	_check(failures, compost > 0,
		"(A) lone wheat pinned the composter: 600 ticks, 0 compost, recipe='%s', in=%s, belt=%s"
			% [str(comp.state["recipe_id"]), str(comp.state["in_buffer"]), str(belt.state["slots"])])
	# The wheat must still be sitting there — reselection must not destroy it.
	_check(failures, _bag_count(comp.state["in_buffer"], Items.Type.WHEAT) == 1,
		"(A) the unstartable wheat was lost, expected it to stay buffered")
	_cleanup(world)

## (B) The other direction: a pin that IS satisfiable (more of the same crop is
## coming) must NOT be abandoned. Guards against "fall through on any partial".
static func _case_b_satisfiable_pin_not_abandoned(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.COMPOSTER, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_W)
	var comp: Building = world.building_at(Vector2i(0, 0))
	var belt: Building = world.building_at(Vector2i(1, 0))

	comp.state["in_buffer"] = [[Items.Type.WHEAT, 1]]
	for i in Belt.SLOTS_PER_TILE:
		belt.state["slots"][i] = Items.Type.WHEAT         # same crop, so the pin is fine

	for _t in 600:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var compost: int = _bag_count(comp.state["out_buffer"], Items.Type.COMPOST_LOW) \
		+ _slot_count(belt, Items.Type.COMPOST_LOW)
	_check(failures, compost > 0,
		"(B) wheat-fed composter produced no compost, recipe='%s' in=%s"
			% [str(comp.state["recipe_id"]), str(comp.state["in_buffer"])])
	_cleanup(world)

## (C) The FIFO contract test_smelter.gd locks must survive. Iron arrived
## first, so iron is selected first even with copper also buffered.
static func _case_c_smelter_fifo_preserved(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	for dx in 2:
		for dy in 2:
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.SMELTER, Vector2i(0, 0), Belt.DIR_E)
	var sm: Building = world.building_at(Vector2i(0, 0))
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 4], [Items.Type.COPPER_ORE, 2]]
	sm.state["recipe_id"] = ""
	sm.state["state"] = Smelter.STATE_IDLE
	sm.state["fuel_buffer"] = 8

	Smelter._maybe_select_recipe(sm, world)
	_check(failures, str(sm.state["recipe_id"]) == "smelt_iron",
		"(C) FIFO broken: first-arrived iron should win, got '%s'" % str(sm.state["recipe_id"]))
	_cleanup(world)

## (D) #18 on the smelter: NO_FUEL + a recipe id the registry no longer knows.
## Ore and fuel are both present; it must recover and smelt.
static func _case_d_smelter_dead_recipe(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	for dx in 2:
		for dy in 2:
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.SMELTER, Vector2i(0, 0), Belt.DIR_E)
	var sm: Building = world.building_at(Vector2i(0, 0))
	sm.state["state"] = Smelter.STATE_NO_FUEL
	sm.state["recipe_id"] = "smelt_mithril"        # renamed/removed by a later version
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 4]]
	sm.state["fuel_buffer"] = 99

	for _t in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var ingots: int = _bag_count(sm.state["out_buffer"], Items.Type.IRON_INGOT)
	_check(failures, ingots > 0,
		"(D) smelter wedged on dead recipe: 400 ticks, state=%d recipe='%s' in=%s out=%s"
			% [int(sm.state["state"]), str(sm.state["recipe_id"]),
			   str(sm.state["in_buffer"]), str(sm.state["out_buffer"])])
	_cleanup(world)

## (E) #18 on the composter: RUNNING + a dead recipe id. Same wedge, same fix.
## This is the half #18's own fix text called "optional future-proofing".
static func _case_e_composter_dead_recipe(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.COMPOSTER, Vector2i(0, 0), Belt.DIR_E)
	var comp: Building = world.building_at(Vector2i(0, 0))
	comp.state["state"] = Processor.RUNNING
	comp.state["recipe_id"] = "composter_gone"
	comp.state["in_buffer"] = [[Items.Type.WHEAT, 4]]

	for _t in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var compost: int = _bag_count(comp.state["out_buffer"], Items.Type.COMPOST_LOW)
	_check(failures, compost > 0,
		"(E) composter wedged on dead recipe: 400 ticks, state=%d recipe='%s' in=%s out=%s"
			% [int(comp.state["state"]), str(comp.state["recipe_id"]),
			   str(comp.state["in_buffer"]), str(comp.state["out_buffer"])])
	_cleanup(world)

## (F) RETENTION. #18's stated mechanism was that NO_FUEL cannot recover. It
## always could, and this case keeps it that way: a smelter with a VALID recipe
## that runs out of fuel must resume the tick fuel arrives on its belt. If a
## future "fix" clears the pin on entering NO_FUEL, this reddens.
static func _case_f_no_fuel_still_recovers(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	for dx in 2:
		for dy in 3:
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.SMELTER, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(0, 2), Belt.DIR_N)   # S edge fuel port
	var sm: Building = world.building_at(Vector2i(0, 0))
	var fuelbelt: Building = world.building_at(Vector2i(0, 2))
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 1]]
	sm.state["fuel_buffer"] = 0
	sm.state["recipe_id"] = ""
	sm.state["state"] = Smelter.STATE_IDLE

	for _t in 3:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, int(sm.state["state"]) == Smelter.STATE_NO_FUEL,
		"(F) expected NO_FUEL with ore but no fuel, got state=%d" % int(sm.state["state"]))

	for i in Belt.SLOTS_PER_TILE:
		fuelbelt.state["slots"][i] = Items.Type.WOOD
	for _t in 100:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	_check(failures, _bag_count(sm.state["out_buffer"], Items.Type.IRON_INGOT) > 0,
		"(F) NO_FUEL smelter did not resume once belt fuel arrived: state=%d fuel=%d out=%s"
			% [int(sm.state["state"]), int(sm.state["fuel_buffer"]), str(sm.state["out_buffer"])])
	_cleanup(world)

## (G) RETENTION. recipe_id "" is the legitimate "nothing selected yet"
## sentinel, not a dead pin. A fresh composter fed from a belt must still work.
static func _case_g_fresh_machine_unaffected(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.COMPOSTER, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_W)
	var comp: Building = world.building_at(Vector2i(0, 0))
	var belt: Building = world.building_at(Vector2i(1, 0))
	_check(failures, str(comp.state["recipe_id"]) == "",
		"(G) fresh composter should start with recipe_id ''")
	for i in Belt.SLOTS_PER_TILE:
		belt.state["slots"][i] = Items.Type.SUGAR_BEET

	for _t in 600:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var mid: int = _bag_count(comp.state["out_buffer"], Items.Type.COMPOST_MID) \
		+ _slot_count(belt, Items.Type.COMPOST_MID)
	_check(failures, mid > 0,
		"(G) fresh belt-fed composter produced no compost: recipe='%s' in=%s out=%s"
			% [str(comp.state["recipe_id"]), str(comp.state["in_buffer"]), str(comp.state["out_buffer"])])
	_cleanup(world)

## (I) The THIRD wedge route, and the only one reachable without a save file.
##
## STATE_NO_FUEL means "I have inputs and room, but no fuel". Take the inputs away
## and that state is a lie, and nothing restored the truth: the NO_FUEL arm needs
## `_has_all_inputs` to fire, selection is gated on IDLE, and `_try_pull_inputs`
## filters belt pulls by the still-pinned recipe. So a smelter stalled on iron whose
## ore is removed accepts iron and nothing else, forever.
##
## Reachable in ordinary play: SMELTER's slot_layout declares an "input" slot bound
## to in_buffer (buildings.gd), and BuildingPanel._take_from_slot handles kind
## "input" by removing the entry outright. Emptying a stuck smelter from its panel
## is a reasonable thing for a player to do.
##
## This is the one part of #18 that is genuinely smelter-specific, and the reason is
## structural rather than incidental: the composter's non-IDLE states (RUNNING,
## BLOCKED_OUTPUT) do not depend on in_buffer — RUNNING has already consumed its
## inputs and completes regardless, BLOCKED_OUTPUT re-checks room and drains via the
## push. NO_FUEL is the only input-dependent non-IDLE state in either machine.
static func _case_i_no_fuel_survives_input_removal(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 4):
		for y in range(0, 4):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.SMELTER, Vector2i(1, 1), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(0, 1), Belt.DIR_E)   # W edge, into smelter
	var sm: Building = world.building_at(Vector2i(1, 1))
	var orebelt: Building = world.building_at(Vector2i(0, 1))

	# Drive it into NO_FUEL on iron.
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 1]]
	sm.state["fuel_buffer"] = 0
	sm.state["recipe_id"] = ""
	sm.state["state"] = Smelter.STATE_IDLE
	for _t in 3:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, int(sm.state["state"]) == Smelter.STATE_NO_FUEL,
		"(I) setup: expected NO_FUEL, got state=%d" % int(sm.state["state"]))
	_check(failures, str(sm.state["recipe_id"]) == "smelt_iron",
		"(I) setup: expected smelt_iron pinned, got '%s'" % str(sm.state["recipe_id"]))

	# Player empties the input slot from the panel, then supplies fuel and COPPER.
	sm.state["in_buffer"] = []
	sm.state["fuel_buffer"] = 8
	for i in Belt.SLOTS_PER_TILE:
		orebelt.state["slots"][i] = Items.Type.COPPER_ORE

	for _t in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	_check(failures, _bag_count(sm.state["out_buffer"], Items.Type.COPPER_INGOT) > 0,
		"(I) NO_FUEL smelter wedged after its inputs were taken: 400 ticks, state=%d recipe='%s' in=%s out=%s fuel=%d belt=%s"
			% [int(sm.state["state"]), str(sm.state["recipe_id"]), str(sm.state["in_buffer"]),
			   str(sm.state["out_buffer"]), int(sm.state["fuel_buffer"]), str(orebelt.state["slots"])])
	_cleanup(world)

## (J) RETENTION, and the reason case (I)'s guard is an `elif` and not an `else`.
##
## The narrow guard leaves NO_FUEL only when NO_FUEL's own precondition — inputs
## present — is violated. An unconditional `else` would also fire when inputs are
## present but the OUTPUT buffer is full, reporting "Idle" for a machine that is in
## fact short of fuel and short of a sink.
##
## This case exists because the rationale #18's fix text gave for preferring `elif`
## — that `else` would "oscillate IDLE<->NO_FUEL every tick" — is false here, and
## was measured false: the `else` binds to the outer `if inputs and room`, so with
## inputs present it never runs. Swapping `elif` for `else` left the entire suite
## green, which is exactly why this case had to be written rather than trusting the
## inherited reasoning.
static func _case_j_no_fuel_narrowness(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	for dx in 2:
		for dy in 2:
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.SMELTER, Vector2i(0, 0), Belt.DIR_E)
	var sm: Building = world.building_at(Vector2i(0, 0))
	sm.state["in_buffer"] = [[Items.Type.IRON_ORE, 4]]
	sm.state["fuel_buffer"] = 0
	sm.state["recipe_id"] = ""
	sm.state["state"] = Smelter.STATE_IDLE

	for _t in 3:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, int(sm.state["state"]) == Smelter.STATE_NO_FUEL,
		"(J) setup: expected NO_FUEL, got state=%d" % int(sm.state["state"]))

	# Now jam the output too. Inputs are still there, so NO_FUEL is still the
	# honest state and must survive.
	sm.state["out_buffer"] = [[Items.Type.IRON_INGOT, 8]]   # output_capacity is 8
	for _t in 20:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	_check(failures, int(sm.state["state"]) == Smelter.STATE_NO_FUEL,
		"(J) a fuel-starved smelter with inputs reported state=%d once its output filled; NO_FUEL must survive a full output because inputs are still present"
			% int(sm.state["state"]))
	_check(failures, _bag_count(sm.state["in_buffer"], Items.Type.IRON_ORE) == 4,
		"(J) inputs must be untouched, got %s" % str(sm.state["in_buffer"]))
	_cleanup(world)

## (H) Selection branch (3): nothing startable AND no belt offering anything.
## The pin must still name the crop that is waiting, because that is what makes
## `Processor._missing_for_start` produce the "Waiting for: Wheat (1/2)" line —
## that diagnostic is gated on the recipe being non-empty, so with recipe_id ""
## a composter holding un-runnable wheat would explain nothing to the player.
##
## Without this case the branch-(3) fallback is unexercised: it was added with
## the #15 fix, and deleting it left the whole suite green at 63/63.
static func _case_h_stalled_crop_is_named(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.COMPOSTER, Vector2i(0, 0), Belt.DIR_E)
	var comp: Building = world.building_at(Vector2i(0, 0))
	comp.state["in_buffer"] = [[Items.Type.WHEAT, 1]]     # needs 2, and no belts exist

	for _t in 20:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	_check(failures, str(comp.state["recipe_id"]) == "composter_low_wheat",
		"(H) stalled composter should still name the waiting crop, recipe='%s'"
			% str(comp.state["recipe_id"]))
	var waiting: bool = false
	for line in Processor.info_lines(comp, world):
		if str(line).begins_with("Waiting for:"):
			waiting = true
	_check(failures, waiting,
		"(H) panel gave no 'Waiting for:' line for a composter stalled on a partial stack")
	_cleanup(world)

# ---------- helpers ----------

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _slot_count(belt: Building, item_type: int) -> int:
	var n: int = 0
	for s in belt.state.get("slots", []):
		if int(s) == item_type:
			n += 1
	return n

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
