extends RefCounted

## A mid-session load must invalidate the cached networks.
##
## Audit finding #1 (HIGH), docs/audits/2026-07-19-flaw-review.md — "load_game
## replaces all buildings without invalidating the fluid-network cache".
##
## SaveSystem.load_game clears and repopulates grid_world.buildings and
## grid_world.occupied DIRECTLY. place_building and remove_building_at are the
## only paths that set _fluid_network_dirty / _power_network_dirty, and load
## goes through neither. Both flags initialise true (grid_world.gd), so the
## boot-time load is safe and every prior test loads into a FRESH GridWorld
## where the flag is still true — which is exactly why 44 green tests never
## saw this. The live failure is the mid-session F9 quick-load (main.gd),
## which reuses the standing GridWorld whose caches were resolved long ago.
##
## WHY IT LANDS IN THE POLE-TIERS SESSION. Task 5 added world._pole_cells, a
## SECOND cache on the same lifecycle as _pole_component. Shipping another
## cache into a known-live invalidation hole widens the finding rather than
## leaving it where it was.
##
## WHAT THIS TEST DELIBERATELY DOES NOT DO. It does not assert that
## _power_network_dirty is true after loading. That would prove a boolean
## flipped and nothing else: not that the rebuild happens, not that the
## rebuilt topology is right, and not that the flag survived to the end of
## load_game. It calls SaveSystem.load_game for real and then asks the PUBLIC
## queries — PowerNetwork.network_id_at, PowerNetwork.power_satisfaction_at,
## GridWorld.fluid_available_at — the same three a caller would use. One
## assertion set, three distinct defects caught: a missing flag, a flag set
## where something later clears it, and a rebuild that produces the wrong
## answer.
##
## Sub-case index:
##   1. Power topology — world A's components replace world B's, and a
##      coordinate that held a pole only in B reports no network.
##   2. Power satisfaction — a lamp that only a SUBSTATION's radius-4 supply
##      area can reach reads as fully powered after the load, which is the
##      Session 3 resolver running against the rebuilt caches rather than
##      against B's.
##   3. Fluid connectivity — the other half of the same defect, at the same
##      fix site. Split from the power half only in reporting: they are one
##      bug, and separating the FIXES is how one gets done and the other
##      forgotten.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_load_network_invalidation.json"
const TEST_SEED: int = 90210

# --- world A: the SAVED world. Multi-tier on purpose. -----------------------
# SUBSTATION 2x2 at (0,5), so it occupies (0,5)..(1,6). Its footprint cells —
# not just its anchor — have to be back in world._pole_cells after the load or
# sub-case (2)'s lamp resolves to nothing.
const A_SUBSTATION: Vector2i = Vector2i(0, 5)
# Basic pole 9 from the substation's east column (x=1). 9 <= max(11, 3), so it
# JOINS the substation under either-reaches. Comfortably inside 11 rather than
# at the boundary: this file is about cache invalidation, and a boundary link
# here would make an unrelated range edit read as a load bug.
const A_JOINED_POLE: Vector2i = Vector2i(10, 5)
# 39 from the substation's east column and 30 from A_JOINED_POLE, so it is a
# SECOND component under any tier's range. Two components is what sub-case (1)
# compares against world B's three.
const A_LONE_POLE: Vector2i = Vector2i(40, 5)
# 2x2 generator whose WEST edge is x = 1 across y 5..6 — both of those are
# substation cells, so it satisfies _adjacent_component_id's cardinal-touch
# rule against a NON-ANCHOR cell of a multi-cell pole.
const A_GENERATOR: Vector2i = Vector2i(2, 5)
# Chebyshev 4 from the substation's nearest footprint cell (0,6), which is the
# outermost ring radius 4 reaches, and 10 from A_JOINED_POLE. NOTHING but the
# substation's supply area covers it.
const A_LAMP: Vector2i = Vector2i(0, 10)
# Pump + two pipes on their own row. The probe cell is cardinally adjacent to
# the far pipe, and the pump is cardinally adjacent to the near one, so
# fluid_available_at(A_FLUID_PROBE) is true once the pipe component knows it
# has a pump.
const A_PUMP: Vector2i = Vector2i(0, 20)
const A_WATER: Vector2i = Vector2i(0, 21)
const A_PIPES: Array = [Vector2i(1, 20), Vector2i(2, 20)]
const A_FLUID_PROBE: Vector2i = Vector2i(3, 20)

# --- world B: the LIVE world being loaded into. ----------------------------
# Three basic poles far enough apart to be three separate components, at
# coordinates world A never touches. The count (3) differs from A's (2) and
# every coordinate is A-free, so a stale answer and a correct one cannot be
# confused for each other.
const B_POLES: Array = [Vector2i(100, 100), Vector2i(200, 100), Vector2i(300, 100)]

static func test_name() -> String:
	return "load invalidates cached networks (power topology + satisfaction + fluid)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	var orig_tick: int = TickSystem.current_tick
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	_run_all(parent, failures)

	SaveSystem.save_path = orig_path
	TickSystem.current_tick = orig_tick
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	if failures.is_empty():
		return { "ok": true, "message": "3 sub-cases pass: power topology replaced, substation supply area resolves after load, fluid connectivity replaced" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

## Everything between the save_path swap and its restore. Split out so the
## restore above cannot be skipped by an early return in here.
static func _run_all(parent: Node, failures: Array) -> void:
	# ---------- world A: build, resolve, save ----------
	var world_a = _make_world(parent)
	world_a.world_seed = TEST_SEED
	if not _build_world_a(world_a, failures):
		_teardown(world_a)
		return

	PowerNetwork.rebuild_topology(world_a)
	var a_comps: int = _component_count(world_a)
	_check(failures, a_comps == 2,
		"PREMISE: world A should resolve to exactly 2 pole components (substation + joined pole, and the lone pole), got %d" % a_comps)
	_check(failures, world_a.fluid_available_at(A_FLUID_PROBE),
		"PREMISE: world A's probe at %s should see the pump through the pipe run before anything is saved" % str(A_FLUID_PROBE))

	var player_a := Node2D.new()
	parent.add_child(player_a)
	var inv_a: Inventory = Inventory.new(16)
	if not SaveSystem.save_game(world_a, player_a, inv_a):
		_check(failures, false, "PREMISE: save_game returned false for world A")
		player_a.queue_free()
		_teardown(world_a)
		return
	player_a.queue_free()
	_teardown(world_a)

	# ---------- world B: build, RESOLVE, then load A into it ----------
	# The resolve is the whole scenario. A world whose caches were never built
	# has both dirty flags still true from init, which is why every existing
	# save test loads correctly and none of them covers this.
	var world_b = _make_world(parent)
	for pole in B_POLES:
		if not world_b.place_building(Buildings.Type.POWER_POLE, pole):
			_check(failures, false,
				"PREMISE: could not place world B's pole at %s: %s" % [str(pole), str(world_b.last_building_place_error)])
			_teardown(world_b)
			return
	# Resolve through the PUBLIC queries, the way a running game does — a
	# pipe draw or a lamp tick, not an explicit rebuild call.
	var b_first: int = PowerNetwork.network_id_at(world_b, B_POLES[0])
	var b_fluid: bool = world_b.fluid_available_at(A_FLUID_PROBE)
	var b_comps: int = _component_count(world_b)
	_check(failures, b_comps == 3 and b_first >= 0,
		"PREMISE: world B should resolve to 3 pole components with its first pole in one of them, got %d components and id %d" % [b_comps, b_first])
	_check(failures, not b_fluid,
		"PREMISE: world B has no pipes at all, so its probe at %s must read false before the load" % str(A_FLUID_PROBE))
	# Asserted as SETUP, not as the outcome: if either flag were still true
	# here, the load would rebuild for a reason that has nothing to do with
	# the fix and all three sub-cases below would pass against unfixed code.
	_check(failures, not world_b._power_network_dirty and not world_b._fluid_network_dirty,
		"PREMISE: world B's caches are supposed to be RESOLVED before the load (power dirty=%s, fluid dirty=%s) — with either still dirty this whole test is vacuous" % [str(world_b._power_network_dirty), str(world_b._fluid_network_dirty)])

	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b: Inventory = Inventory.new(16)
	var result = SaveSystem.load_game(world_b, player_b, inv_b)
	player_b.queue_free()
	if not bool(result.success):
		_check(failures, false, "PREMISE: load_game returned !success: %s" % str(result.error_message))
		_teardown(world_b)
		return
	# NOTHING between here and the assertions rebuilds anything by hand. Every
	# query below is one a caller would make, and each has to trigger its own
	# lazy rebuild off the flag load_game is responsible for setting.

	_case_power_topology(world_b, failures)
	_case_power_satisfaction(world_b, failures)
	_case_fluid(world_b, failures)
	_teardown(world_b)

# ===========================================================================
# (1) THE POWER TOPOLOGY IS WORLD A'S, NOT WORLD B'S.
#
# Three assertions, and they fail for three different shapes of wrongness:
#
#   - the component COUNT is A's 2 rather than B's 3. Catches "no rebuild
#     happened at all" from the coarsest angle.
#   - the substation and the pole 9 away SHARE a component, and the lone pole
#     40 away does not. Catches a rebuild that ran but grouped wrongly — a
#     count alone would be satisfied by any 2-way split.
#   - a coordinate that held a pole ONLY in world B reports -1. Catches the
#     reverse leak: B's entries surviving into the loaded world. A rebuild
#     clears _pole_component before refilling it, so this is the assertion
#     that notices if it ever stops.
# ===========================================================================
static func _case_power_topology(world_b, failures: Array) -> void:
	var comps: int = _resolved_component_count(world_b)
	_check(failures, comps == 2,
		"(1) after loading world A into a resolved world B, the power topology should hold world A's 2 components, got %d — world B had 3, so an unchanged 3 means load_game never invalidated the cache" % comps)

	var sub_id: int = PowerNetwork.network_id_at(world_b, A_SUBSTATION)
	var joined_id: int = PowerNetwork.network_id_at(world_b, A_JOINED_POLE)
	var lone_id: int = PowerNetwork.network_id_at(world_b, A_LONE_POLE)
	_check(failures, sub_id >= 0 and joined_id >= 0 and lone_id >= 0,
		"(1) world A's poles are not in any network after the load (substation %s -> %d, joined pole %s -> %d, lone pole %s -> %d) — the loaded buildings are present but the cached topology still describes world B" % [str(A_SUBSTATION), sub_id, str(A_JOINED_POLE), joined_id, str(A_LONE_POLE), lone_id])
	_check(failures, sub_id == joined_id,
		"(1) the substation at %s and the pole at %s are 9 apart, inside the substation's wire range 11, and must share a component after the load — got %d and %d" % [str(A_SUBSTATION), str(A_JOINED_POLE), sub_id, joined_id])
	_check(failures, lone_id != sub_id,
		"(1) the lone pole at %s is 39 from the substation and must be its OWN component after the load, but it came back as %d alongside the substation" % [str(A_LONE_POLE), lone_id])

	for pole in B_POLES:
		_check(failures, PowerNetwork.network_id_at(world_b, pole) == -1,
			"(1) %s held a pole in world B only. World A has no building there, so it must report no network after the load — a real id here means world B's _pole_component entries survived" % str(pole))

# ===========================================================================
# (2) THE SUBSTATION'S SUPPLY AREA RESOLVES AGAINST THE REBUILT CACHES.
#
# A_LAMP sits at Chebyshev 4 from the substation's nearest footprint cell and
# 10 from the only other pole in its component. Nothing but Task 5's resolver
# reaches it: it needs SUPPLY_RADIUS_BY_TYPE's substation row (4) AND
# world._pole_cells, the second of the two caches load_game must invalidate.
# So this sub-case would still fail if _pole_component were rebuilt and
# _pole_cells were not.
#
# The generator round-trips with output_active already true, written before
# the save, so no ticking is needed and the supply is 20 against a demand of
# 1 — satisfaction exactly 1.0. Compared with == because 20/1 clamps to a
# value that is exact in binary floating point.
# ===========================================================================
static func _case_power_satisfaction(world_b, failures: Array) -> void:
	PowerNetwork.update_supply_demand(world_b)
	var sat: float = PowerNetwork.power_satisfaction_at(world_b, A_LAMP)
	_check(failures, sat == 1.0,
		"(2) the lamp at %s is Chebyshev 4 from the substation's nearest footprint cell and unreachable by any other pole, so after the load it must read satisfaction 1.0 (supply %d against demand %d) — got %f" % [str(A_LAMP), SteamGenerator.MAX_OUTPUT, ElectricLamp.DEMAND, sat])
	for pole in B_POLES:
		_check(failures, PowerNetwork.power_satisfaction_at(world_b, pole) == 0.0,
			"(2) %s is a world-B-only coordinate with no building in world A, so it must read satisfaction exactly 0.0 after the load" % str(pole))

# ===========================================================================
# (3) THE FLUID NETWORK, SAME DEFECT AND SAME FIX SITE.
#
# World B carries no pipes and its probe was queried before the load, which
# both resolved the cache and pinned the answer at false. World A carries a
# pump feeding two pipes, so the same probe must read true afterwards.
#
# This half is the one the audit actually describes — its failure scenario is
# a Mixer that keeps producing dough from a pipe run that only exists in the
# world the player just loaded away from. The power half is the same bug
# reached through a different cache.
# ===========================================================================
static func _case_fluid(world_b, failures: Array) -> void:
	_check(failures, world_b.fluid_available_at(A_FLUID_PROBE),
		"(3) world A's pump feeds two pipes ending beside %s, so after the load that probe must see fluid. It reads false, which is world B's pipeless answer still cached" % str(A_FLUID_PROBE))
	# The other direction, so a fix that simply hardcoded true would not pass:
	# a cell nowhere near the loaded pipe run still has no fluid.
	var dry: Vector2i = A_FLUID_PROBE + Vector2i(0, 5)
	_check(failures, not world_b.fluid_available_at(dry),
		"(3) %s is five tiles off the loaded pipe run and must still read no fluid" % str(dry))

# ---------- world A construction ----------

## Lay terrain, then place world A's buildings. Returns false on the first
## refused placement, with the world's own error text.
##
## ORDER MATTERS: set_overlay refuses to paint under a building, so all the
## paving runs before any placement.
static func _build_world_a(world, failures: Array) -> bool:
	# The pump's water. Written into tile_modifications as well as tiles —
	# SaveSystem only persists tile_modifications, so a bare tiles[] write
	# would vanish on load. It has no effect on the queries this file makes
	# (Pump.is_valid_placement runs at PLACEMENT time, not at load), but a
	# loaded world holding a pump with no water beside it is an incoherent
	# fixture to leave behind.
	var water := Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.tiles[A_WATER] = water
	world.tile_modifications[A_WATER] = water
	# STONE for the strict types. STEAM_GENERATOR requires [STONE, PATH],
	# PUMP the same, PIPE [STONE, PATH, SOIL_TILLED]. The pole tiers and the
	# lamp all accept Overlay.NONE, which a bare GridWorld reads back
	# everywhere, so they need no paving.
	var paved: Array = [A_PUMP]
	paved.append_array(A_PIPES)
	for dy in 2:
		for dx in 2:
			paved.append(A_GENERATOR + Vector2i(dx, dy))
	for cell in paved:
		world.tiles[cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
		world.set_overlay(cell, Terrain.Overlay.STONE)

	var rows: Array = [
		[Buildings.Type.SUBSTATION, A_SUBSTATION],
		[Buildings.Type.STEAM_GENERATOR, A_GENERATOR],
		[Buildings.Type.POWER_POLE, A_JOINED_POLE],
		[Buildings.Type.POWER_POLE, A_LONE_POLE],
		[Buildings.Type.ELECTRIC_LAMP, A_LAMP],
		[Buildings.Type.PUMP, A_PUMP],
	]
	for pipe in A_PIPES:
		rows.append([Buildings.Type.PIPE, pipe])
	for row in rows:
		var t: int = int(row[0])
		var pos: Vector2i = row[1]
		if not world.place_building(t, pos):
			_check(failures, false,
				"PREMISE: world A could not place type %d at %s: %s" % [t, str(pos), str(world.last_building_place_error)])
			return false

	# output_active is the ONLY field update_supply_demand's STEAM_GENERATOR
	# arm reads, and Building.to_dict carries state verbatim, so writing it
	# here is what makes the loaded generator supply. fuel_buffer rides along
	# so the saved state is coherent rather than a generator running on
	# nothing. Nothing in this file ticks.
	var gen: Building = world.building_at(A_GENERATOR)
	if gen == null:
		_check(failures, false, "PREMISE: no steam generator at %s after placement" % str(A_GENERATOR))
		return false
	gen.state["fuel_buffer"] = 16
	gen.state["output_active"] = true
	return true

# ---------- helpers ----------

## Distinct component ids currently in world._pole_component, WITHOUT forcing
## a rebuild. Used on worlds whose topology has just been resolved on purpose.
static func _component_count(world) -> int:
	var seen: Dictionary = {}
	for pos in world._pole_component:
		seen[int(world._pole_component[pos])] = true
	return seen.size()

## Same count, but reached the way a caller reaches it: a public query first,
## so any pending rebuild happens through the dirty flag rather than because
## the test asked for one. Reading _pole_component directly after a load would
## still be reading a cache nobody told to refresh.
static func _resolved_component_count(world) -> int:
	PowerNetwork.network_id_at(world, A_SUBSTATION)
	return _component_count(world)

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## A fresh GridWorld parented to `parent` so its _ready() runs. No terrain is
## laid: an empty `tiles` dict reads back GRASS / NONE everywhere, which is
## what makes the pole and lamp placements seed-independent.
static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing. queue_free is deferred until after the runner's
## synchronous run() returns, so a torn-down world stays subscribed to
## TickSystem.tick for the rest of the suite otherwise. Same shape as
## test_pole_tiers.gd's _teardown.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
