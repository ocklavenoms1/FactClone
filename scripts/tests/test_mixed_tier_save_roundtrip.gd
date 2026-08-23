extends RefCounted

## Mixed-tier save round-trip — the pole tiers need NO save schema bump, and
## this file is what holds that claim up.
##
## Three things make the claim true, and only two of them were testable:
##   - Buildings.Type is APPEND-ONLY. MEDIUM_POLE and SUBSTATION went on the
##     END, so every previously-saved type keeps the integer already written
##     into players' save files. Sub-case (4).
##   - Poles carry EMPTY state, so there is nothing per-building to migrate.
##     Nothing to assert: an empty dict round-trips through Building.to_dict /
##     from_dict the same way every other state dict does, which
##     test_save_load_roundtrip.gd already exercises on five building types.
##   - world._pole_component / ._pole_cells are never serialized. They rebuild
##     off the dirty flag, which is test_load_network_invalidation.gd's whole
##     subject and is NOT restated here.
##
## WHAT THIS FILE IS ACTUALLY FOR: the 2x2 SUBSTATION's OCCUPANCY.
## SaveSystem.load_game clears grid_world.occupied and refills it from
## Buildings.footprint_of(b.type). A footprint the load loop expands WRONGLY
## corrupts collision only after a reload, silently, until the player tries to
## build on a tile that looks empty and is actually half a substation.
##
## ---------------------------------------------------------------------------
## OVERLAP WITH test_load_network_invalidation.gd — MEASURED, NOT ASSUMED.
##
## That file already performs a real save/load with a substation in it, so the
## question of whether it already covers this was settled by mutation rather
## than by reading. Two mutations of load_game's refill loop, each run against
## the whole 45-test suite:
##
##   fp = Vector2i(1, 1)                  — anchor only, total loss.
##       CAUGHT, by test_load_network_invalidation.gd alone. Not by an
##       occupancy assertion — it has none. Its world A parks a 2x2 steam
##       generator whose west edge lands on the substation's (1,5) and (1,6),
##       and PowerNetwork._adjacent_component_id resolves those through
##       world.building_at, i.e. through `occupied`. Drop the non-anchor cells
##       and the generator touches nothing, supplies nothing, and that file's
##       lamp reads 0.0 instead of 1.0. Real coverage, but incidental: it
##       reports a satisfaction number for an occupancy defect, and it
##       evaporates if anyone ever moves that generator off the substation.
##
##   fp = Vector2i(footprint_of(type).x, 1)  — the bottom row of every 2x2
##       building silently dropped on load.
##       NOT CAUGHT. 45 passed, 0 failed. The generator's west edge still
##       finds (1,5), so the network half is satisfied and stays quiet, while
##       (0,6) and (1,6) — and the bottom row of every 2x2 in the game — read
##       back as empty ground after a reload.
##
## THAT partial case is the gap this file exists for, and sub-case (2) is the
## only assertion in the suite that sees it. Its negative-space twin is
## sub-case (4): the enum ordering was equally unguarded — moving MEDIUM_POLE
## and SUBSTATION from the end of the enum to just after POWER_POLE, which is
## exactly what the no-bump claim says did not happen, also left the suite at
## 45 passed, 0 failed.
##
## test_pole_tiers.gd sub-case (2) does assert all four substation cells are
## occupied, and its comment even names save/load as the reason — but it
## asserts that at PLACEMENT time and never reloads, so neither mutation above
## touches it. test_save_load_roundtrip.gd does compare world A's `occupied`
## against world B's, but every building in its fixture is 1x1, so there is no
## multi-cell footprint in that comparison at all.
##
## Sub-case index:
##   1. All three tiers come back as their own types.
##   2. The 2x2 substation's occupancy — the four cells resolve to it, and
##      placement is still refused on them.
##   3. The 1x1 tiers stay 1x1 — the load expands by each type's OWN
##      footprint, not blanket-expands everything.
##   4. The on-disk type integers are pinned.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_mixed_tier_save_roundtrip.json"
const TEST_SEED: int = 51776

# --- world A: the SAVED world. One of each pole tier. -----------------------
# SUBSTATION 2x2 at (50,50), so it holds (50,50) (51,50) (50,51) (51,51).
const A_SUBSTATION: Vector2i = Vector2i(50, 50)
const A_MEDIUM: Vector2i = Vector2i(55, 50)
const A_BASIC: Vector2i = Vector2i(58, 50)
## Offsets of the substation's four cells from its anchor. (0,1) and (1,1) are
## the pair the y-collapse mutation drops, and they are the reason this list is
## walked in full rather than spot-checked at the diagonal.
const SUB_OFFSETS: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
## One row SOUTH of the substation's south row (y 51), so it is outside the
## footprint by exactly one tile. The negative control for sub-case (2): it
## proves a refusal on a footprint cell is about THAT CELL and not about the
## loaded world being unbuildable everywhere.
const A_SOUTH_OF_SUB: Vector2i = Vector2i(50, 52)
## Directly east of the 1x1 medium pole, and the cell a 2x2 medium pole would
## have taken. Sub-case (3)'s probe.
const A_EAST_OF_MEDIUM: Vector2i = Vector2i(56, 50)

## Every cell this file hands to can_place_building AFTER the load, plus the
## substation's own footprint.
##
## They are PAVED, and the paving is load-bearing twice over. load_game reruns
## WorldGenerator against the saved seed and then applies tile_modifications on
## top, so an unpaved cell would come back as whatever procgen put there —
## water, an ore deposit, a tree — and can_place_building would refuse it for a
## terrain reason that has nothing to do with occupancy. set_overlay records
## each cell into tile_modifications, which pins it to GRASS / STONE / no
## resource node on the far side of the load regardless of the seed. STONE is
## in requires_overlay for all three pole tiers, so on these cells OCCUPANCY is
## the only rule left that can refuse a pole.
static func _paved_cells() -> Array:
	var cells: Array = [A_MEDIUM, A_BASIC, A_SOUTH_OF_SUB, A_EAST_OF_MEDIUM]
	for off in SUB_OFFSETS:
		cells.append(A_SUBSTATION + off)
	return cells

## The integers that are already sitting in players' save files.
##
## Pinned as literals because inside ONE binary there is no behavioural form of
## this assertion: save_game and load_game read the same enum, so a reordered
## enum round-trips perfectly and every downstream query agrees with it. The
## integer written to disk IS the compatibility surface with saves the running
## binary did not write, and a literal is the only thing that can disagree with
## a reorder.
##
## PLANTER anchors the head of the enum. POWER_POLE through ELECTRIC_INSERTER
## is the seven-member electricity block the pole tiers were appended after —
## PLANTER and POWER_POLE between them already catch an insertion at any point
## up to POWER_POLE, and the rest of the block is here to catch a REORDER
## INSIDE it, which those two alone would not see. MEDIUM_POLE and SUBSTATION
## pin this session's own additions to the tail.
##
## A legitimate future APPEND changes none of these and needs no edit here.
const PINNED_TYPE_INTS: Array = [
	["PLANTER", Buildings.Type.PLANTER, 0],
	["POWER_POLE", Buildings.Type.POWER_POLE, 25],
	["WATER_WHEEL", Buildings.Type.WATER_WHEEL, 26],
	["ELECTRIC_LAMP", Buildings.Type.ELECTRIC_LAMP, 27],
	["WINDMILL", Buildings.Type.WINDMILL, 28],
	["STEAM_GENERATOR", Buildings.Type.STEAM_GENERATOR, 29],
	["ACCUMULATOR", Buildings.Type.ACCUMULATOR, 30],
	["ELECTRIC_INSERTER", Buildings.Type.ELECTRIC_INSERTER, 31],
	["MEDIUM_POLE", Buildings.Type.MEDIUM_POLE, 32],
	["SUBSTATION", Buildings.Type.SUBSTATION, 33],
]

static func test_name() -> String:
	return "mixed-tier save round-trip (tier identity + 2x2 occupancy + enum wire format)"

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
		return { "ok": true, "message": "4 sub-cases pass: tiers reload as themselves, substation occupies all four cells and still blocks placement, thin tiers stay 1x1, type integers unchanged" }
	# " | " rather than "; " so no joiner can be confused for text inside a
	# label. No label in this file contains either.
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 16))] }

## Everything between the save_path swap and its restore. Split out so the
## restore above cannot be skipped by an early return in here.
static func _run_all(parent: Node, failures: Array) -> void:
	# First, because it needs no fixture and no world — so a fixture that
	# fails to build cannot hide it behind an early return.
	_case_enum_wire_format(failures)

	# ---------- world A: build, save ----------
	var world_a = _make_world(parent)
	world_a.world_seed = TEST_SEED
	if not _build_world_a(world_a, failures):
		_teardown(world_a)
		return

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

	# ---------- world B: a DIFFERENT world, then load A into it ----------
	# World B puts a 1x1 POWER_POLE on the exact cell world A's substation
	# anchors at. That is what makes every assertion below able to fail: a load
	# that never touched `occupied` leaves a one-cell pole sitting there, so
	# sub-case (1) reads the wrong type and sub-case (2) finds three of the four
	# cells empty. The before and after states differ at the same coordinate,
	# in the same two queries the assertions use.
	var world_b = _make_world(parent)
	if not world_b.place_building(Buildings.Type.POWER_POLE, A_SUBSTATION):
		_check(failures, false,
			"PREMISE: could not place world B's basic pole at %s: %s" % [str(A_SUBSTATION), str(world_b.last_building_place_error)])
		_teardown(world_b)
		return
	var pre: Building = world_b.building_at(A_SUBSTATION)
	_check(failures, pre != null and pre.type == Buildings.Type.POWER_POLE,
		"PREMISE: world B should hold a basic POWER_POLE at %s before the load" % str(A_SUBSTATION))
	# The far corner of the substation-to-be. FREE and PLACEABLE right now — if
	# it were already blocked, sub-case (2)'s "blocked after the load" would
	# prove nothing at all.
	var far: Vector2i = A_SUBSTATION + Vector2i(1, 1)
	_check(failures, not world_b.has_building_at(far),
		"PREMISE: %s is world A's substation far corner and must be EMPTY in world B before the load, or sub-case (2) is vacuous" % str(far))
	_check(failures, world_b.can_place_building(Buildings.Type.POWER_POLE, far),
		"PREMISE: %s must accept a pole in world B before the load, so that the refusal after the load is a change and not the status quo" % str(far))

	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b: Inventory = Inventory.new(16)
	var result = SaveSystem.load_game(world_b, player_b, inv_b)
	player_b.queue_free()
	if not bool(result.success):
		_check(failures, false, "PREMISE: load_game returned !success: %s" % str(result.error_message))
		_teardown(world_b)
		return

	_case_tier_identity(world_b, failures)
	_case_substation_occupancy(world_b, failures)
	_case_thin_tiers_stay_thin(world_b, failures)
	_teardown(world_b)

# ===========================================================================
# (1) EACH TIER RELOADS AS ITSELF.
#
# Deliberately NOT claimed as enum-ordering coverage: to_dict and from_dict
# read the same Buildings.Type, so a reordered enum agrees with itself and
# sails through here. Sub-case (4) is the only thing that sees that.
#
# What this DOES catch is a load that left world B's own building in place at
# the substation anchor, and a from_dict that lost or defaulted the type. The
# MEDIUM_POLE row is the one carrying weight no other file does: making
# from_dict rehydrate a saved MEDIUM_POLE as a POWER_POLE — a silent demotion
# from wire range 6 / supply radius 2 to 3 / 1 — failed this sub-case and
# nothing else in the suite. No other test saves a medium pole at all.
# ===========================================================================
static func _case_tier_identity(world_b, failures: Array) -> void:
	var rows: Array = [
		[A_SUBSTATION, Buildings.Type.SUBSTATION, "substation"],
		[A_MEDIUM, Buildings.Type.MEDIUM_POLE, "medium pole"],
		[A_BASIC, Buildings.Type.POWER_POLE, "basic pole"],
	]
	for row in rows:
		var pos: Vector2i = row[0]
		var want: int = int(row[1])
		var label: String = String(row[2])
		var b: Building = world_b.building_at(pos)
		if b == null:
			_check(failures, false,
				"(1) no building at all at %s after the load, where world A saved a %s" % [str(pos), label])
			continue
		_check(failures, b.type == want,
			"(1) %s at %s came back as type %d instead of %d" % [label, str(pos), int(b.type), want])
		_check(failures, b.anchor == pos,
			"(1) the %s reloaded at %s reports anchor %s" % [label, str(pos), str(b.anchor)])

# ===========================================================================
# (2) THE 2x2 SUBSTATION OCCUPIES ALL FOUR CELLS AFTER A REAL LOAD.
#
# THE REASON THIS FILE EXISTS, and the only assertion in the project that
# sees the defect. Verified by mutation: collapsing load_game's refill to the
# anchor row only — fp = Vector2i(footprint_of(type).x, 1) — took the suite
# from 46 passed / 0 failed to 45 passed / 1 failed, the single failure being
# this sub-case. Every other test in the project stayed green. See the overlap
# note at the top of the file for the whole measurement.
#
# Two queries per cell, because they fail for different reasons:
#   - building_at resolves the cell to the substation. A cell missing from
#     `occupied` returns null here.
#   - can_place_building REFUSES a pole on the cell. This is the half the
#     player actually feels: the corrupted state is invisible until someone
#     builds on ground that looks empty. Occupancy is the FIRST rule
#     can_place_building checks per cell, and _paved_cells() has already made
#     every other rule on these cells permissive, so a refusal here can only
#     be occupancy — which the error text is checked for rather than assumed.
#
# A_SOUTH_OF_SUB is the negative control. It is paved identically and sits one
# tile outside the footprint, so it must still ACCEPT a pole. Without it, a
# load_game that marked the whole world occupied would pass every assertion
# above.
# ===========================================================================
static func _case_substation_occupancy(world_b, failures: Array) -> void:
	for off in SUB_OFFSETS:
		var cell: Vector2i = A_SUBSTATION + off
		var b: Building = world_b.building_at(cell)
		if b == null:
			_check(failures, false,
				"(2) substation cell %s (anchor %s offset %s) resolves to NO building after the load — load_game refilled `occupied` without expanding the 2x2 footprint, so this tile reads as empty ground" % [str(cell), str(A_SUBSTATION), str(off)])
			continue
		_check(failures, b.type == Buildings.Type.SUBSTATION,
			"(2) substation cell %s resolves to type %d, not the substation" % [str(cell), int(b.type)])
		_check(failures, b.anchor == A_SUBSTATION,
			"(2) substation cell %s resolves to a building anchored at %s instead of %s" % [str(cell), str(b.anchor), str(A_SUBSTATION)])

	# The three NON-anchor cells. The anchor is excluded on purpose: it is
	# occupied even by a load loop that ignores footprints entirely, so a
	# refusal there would be the one result that proves nothing.
	for off in SUB_OFFSETS:
		if off == Vector2i(0, 0):
			continue
		var cell: Vector2i = A_SUBSTATION + off
		var placeable: bool = world_b.can_place_building(Buildings.Type.POWER_POLE, cell)
		var err: String = String(world_b.last_building_place_error)
		_check(failures, not placeable,
			"(2) a pole can still be placed on substation cell %s after the load. The substation is standing there and this tile is inside it, so placement here overlaps two buildings" % str(cell))
		if not placeable:
			_check(failures, err.find("occupied") >= 0,
				"(2) placement on substation cell %s was refused for the wrong reason. Expected the occupancy rule, got: %s" % [str(cell), err])

	# Negative control.
	var free_ok: bool = world_b.can_place_building(Buildings.Type.POWER_POLE, A_SOUTH_OF_SUB)
	_check(failures, free_ok,
		"(2) %s is paved, one tile south of the substation footprint and holds nothing, so it must still ACCEPT a pole after the load. It was refused: %s" % [str(A_SOUTH_OF_SUB), str(world_b.last_building_place_error)])

# ===========================================================================
# (3) THE 1x1 TIERS STAY 1x1.
#
# The mirror of (2). Sub-case (2) alone is satisfied by a load loop that marks
# a 2x2 block around EVERY building regardless of type — which would quietly
# steal three tiles per pole from the player. The medium pole's east neighbour
# is paved and empty in world A, and must still be buildable, while the cell
# east of the substation ANCHOR is inside a real 2x2 and must not be. Same
# query, same terrain, opposite answers, decided only by the type's own
# footprint.
# ===========================================================================
static func _case_thin_tiers_stay_thin(world_b, failures: Array) -> void:
	_check(failures, not world_b.has_building_at(A_EAST_OF_MEDIUM),
		"(3) %s is east of the 1x1 medium pole at %s and holds nothing in world A, but it came back OCCUPIED — the load expanded a 1x1 footprint into more than one cell" % [str(A_EAST_OF_MEDIUM), str(A_MEDIUM)])
	_check(failures, world_b.can_place_building(Buildings.Type.POWER_POLE, A_EAST_OF_MEDIUM),
		"(3) %s must accept a pole after the load. It was refused: %s" % [str(A_EAST_OF_MEDIUM), str(world_b.last_building_place_error)])
	# The same relationship one tier up, where the answer is the opposite.
	var east_of_sub: Vector2i = A_SUBSTATION + Vector2i(1, 0)
	_check(failures, world_b.has_building_at(east_of_sub),
		"(3) %s is east of the substation ANCHOR and inside its 2x2, so unlike the medium pole's east neighbour it must be occupied after the load" % str(east_of_sub))

# ===========================================================================
# (4) THE ON-DISK TYPE INTEGERS ARE UNCHANGED.
#
# The whole no-schema-bump claim rests on the tiers having been APPENDED. If
# they had been inserted anywhere before POWER_POLE, every save written by an
# earlier build would reload with its buildings shifted to the wrong types —
# a lamp becoming a windmill — with no version mismatch to catch it, because
# the schema shape did not change at all.
#
# Verified by mutation, and it is the only assertion in the project that pins
# these: moving MEDIUM_POLE and SUBSTATION out of the tail and in behind
# POWER_POLE left the pre-existing 45-test suite entirely green, and with this
# sub-case in place takes the run to 45 passed / 1 failed — the single failure
# being this one, reporting all eight shifted values.
# ===========================================================================
static func _case_enum_wire_format(failures: Array) -> void:
	for row in PINNED_TYPE_INTS:
		var label: String = String(row[0])
		var actual: int = int(row[1])
		var pinned: int = int(row[2])
		_check(failures, actual == pinned,
			"(4) Buildings.Type.%s is %d but every save file on disk was written with %d. The enum was reordered rather than appended to, so existing saves will reload their buildings as the wrong types" % [label, actual, pinned])

# ---------- world A construction ----------

## Pave the queried cells, then place one of each pole tier. Returns false on
## the first refusal, with the world's own error text.
##
## ORDER MATTERS: set_overlay refuses to paint under a building, so all the
## paving runs before any placement.
static func _build_world_a(world, failures: Array) -> bool:
	for cell in _paved_cells():
		world.tiles[cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
		if not world.set_overlay(cell, Terrain.Overlay.STONE):
			_check(failures, false,
				"PREMISE: could not pave %s in world A: %s" % [str(cell), str(world.last_place_error)])
			return false

	var rows: Array = [
		[Buildings.Type.SUBSTATION, A_SUBSTATION],
		[Buildings.Type.MEDIUM_POLE, A_MEDIUM],
		[Buildings.Type.POWER_POLE, A_BASIC],
	]
	for row in rows:
		var t: int = int(row[0])
		var pos: Vector2i = row[1]
		if not world.place_building(t, pos):
			_check(failures, false,
				"PREMISE: world A could not place type %d at %s: %s" % [t, str(pos), str(world.last_building_place_error)])
			return false
	return true

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## A fresh GridWorld parented to `parent` so its _ready() runs. No terrain is
## laid beyond _build_world_a's paving: an empty `tiles` dict reads back GRASS
## / NONE everywhere, which is what lets world B place its pole with no setup.
static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing. queue_free is deferred until after the runner's
## synchronous run() returns, so a torn-down world stays subscribed to
## TickSystem.tick for the rest of the suite otherwise. Same shape as
## test_load_network_invalidation.gd's _teardown.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
