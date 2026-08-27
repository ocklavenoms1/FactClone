extends RefCounted

## Belt Logistics Session 1, Task 1 — DIR-AWARE FOOTPRINTS.
##
## The convention under test (single source: Buildings.footprint_for header):
## DATA's "footprint" is the CANONICAL shape at dir = Belt.DIR_E (0). Square
## footprints are identical at every dir. A non-square footprint keeps the
## canonical shape at DIR_E/DIR_W and SWAPS AXES at DIR_S/DIR_N. The anchor is
## always the top-left cell of the ROTATED rect.
##
## SPLITTER (2×1 canonical, rotatable) is the first non-square type; its
## registry row was pulled forward from Task 2 so these cases run through the
## REAL placement / occupancy / hover / save stack.
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. Nothing here asks footprint_of /
## footprint_for for its own expectation — the A/B-table incident showed a
## suite whose expectations come from the module under test is blind.
##
## ⚠ ASSERT THE PATH, NOT THE ANSWER: every rotation case includes at least
## one dir whose expected value DIFFERS from the canonical (type-fixed) one,
## so "rotation works" and "rotation ignored" cannot both pass.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

const TEST_SAVE_PATH: String = "user://test_dir_footprint.json"

# ---- Fixture anchors. Each sub-case owns its own cells; nothing shared. ----
# (4) occupancy: all three cells of BOTH orientations paved, so a placement
# that validates against the WRONG footprint still succeeds and the occupancy
# assertions — not a placement premise — are what catch it.
const A_OCC: Vector2i = Vector2i(40, 10)
# (3)/(5) asymmetry pair 1: chest at A_BLK_S + (0,1) blocks DIR_S only.
const A_BLK_S: Vector2i = Vector2i(20, 10)
# (3)/(5) asymmetry pair 2: chest at A_BLK_E + (1,0) blocks DIR_E only —
# the dir where the expected answer DIFFERS from the canonical one.
const A_BLK_E: Vector2i = Vector2i(30, 10)
# (7) save round-trip anchor.
const A_SAVE: Vector2i = Vector2i(50, 10)

static func test_name() -> String:
	return "dir-aware footprints (2x1 splitter: mechanism, placement, occupancy, hover, save)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	_run_all(parent, failures)

	SaveSystem.save_path = orig_path
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	if failures.is_empty():
		return { "ok": true, "message":
			"sub-cases pass: canonical/rotated footprint literals, rotated placement asymmetry, "
			+ "occupancy + removal by rotated cell, hover agreement with dir, rotated save round-trip" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 40))] }

static func _run_all(parent: Node, failures: Array) -> void:
	_case_mechanism(failures)
	_case_instance_form(failures)

	_case_edge_geometry(failures)

	var world = _make_world(parent)
	if not _pave_fixture(world, failures):
		_teardown(world)
		return
	_case_placement_asymmetry(world, failures)
	_case_hover_agreement(world, failures)
	_case_occupancy(world, failures)
	_teardown(world)

	_case_save_roundtrip(parent, failures)

# ===========================================================================
# (0)+(1) THE MECHANISM. DATA-row guard for the pulled-forward SPLITTER, then
# footprint_for against literals for all four dirs, plus square controls.
# ===========================================================================
static func _case_mechanism(failures: Array) -> void:
	# (0) The pull-forward stays pinned: enum + DATA row shape.
	_check(failures, Buildings.DATA.has(Buildings.Type.SPLITTER),
		"(0) SPLITTER must have a DATA row (Task 2 pull-forward)")
	_check(failures, Buildings.name_of(Buildings.Type.SPLITTER) == "Splitter",
		"(0) SPLITTER DATA name must be 'Splitter'")
	_check(failures, Buildings.footprint_of(Buildings.Type.SPLITTER) == Vector2i(2, 1),
		"(0) SPLITTER canonical footprint must be (2, 1), got %s"
			% str(Buildings.footprint_of(Buildings.Type.SPLITTER)))
	_check(failures, Buildings.supports_direction(Buildings.Type.SPLITTER),
		"(0) SPLITTER must be rotatable (supports_direction)")
	_check(failures, Buildings.is_walkable(Buildings.Type.SPLITTER),
		"(0) SPLITTER must be walkable (belt-family)")

	# (1) footprint_for literals. DIR_S and DIR_N are the cases whose expected
	# value differs from the canonical (2, 1) — the rotation discriminators.
	_check(failures, Buildings.footprint_for(Buildings.Type.SPLITTER, 0) == Vector2i(2, 1),
		"(1) footprint_for(SPLITTER, E) must be (2, 1), got %s"
			% str(Buildings.footprint_for(Buildings.Type.SPLITTER, 0)))
	_check(failures, Buildings.footprint_for(Buildings.Type.SPLITTER, 1) == Vector2i(1, 2),
		"(1) footprint_for(SPLITTER, S) must be (1, 2) — axes SWAP on the quarter turn, got %s"
			% str(Buildings.footprint_for(Buildings.Type.SPLITTER, 1)))
	_check(failures, Buildings.footprint_for(Buildings.Type.SPLITTER, 2) == Vector2i(2, 1),
		"(1) footprint_for(SPLITTER, W) must be (2, 1), got %s"
			% str(Buildings.footprint_for(Buildings.Type.SPLITTER, 2)))
	_check(failures, Buildings.footprint_for(Buildings.Type.SPLITTER, 3) == Vector2i(1, 2),
		"(1) footprint_for(SPLITTER, N) must be (1, 2) — axes SWAP on the quarter turn, got %s"
			% str(Buildings.footprint_for(Buildings.Type.SPLITTER, 3)))
	# Square controls: dir must be a NO-OP for square footprints, at the dirs
	# that swap a non-square one.
	_check(failures, Buildings.footprint_for(Buildings.Type.SMELTER, 1) == Vector2i(2, 2),
		"(1) footprint_for(SMELTER, S) must stay (2, 2) — square is dir-independent")
	_check(failures, Buildings.footprint_for(Buildings.Type.BELT, 3) == Vector2i(1, 1),
		"(1) footprint_for(BELT, N) must stay (1, 1) — square is dir-independent")

# ===========================================================================
# (2) THE INSTANCE FORM. A made splitter carries its dir in state and
# footprint_of_building reads THAT, not the canonical row.
# ===========================================================================
static func _case_instance_form(failures: Array) -> void:
	var b_n: Building = Buildings.make(Buildings.Type.SPLITTER, Vector2i(0, 0), 3)
	_check(failures, b_n != null, "(2) make(SPLITTER, dir=N) must return a building")
	if b_n == null:
		return
	_check(failures, Buildings.dir_of(b_n) == 3,
		"(2) dir_of must read state dir 3 (N), got %d" % Buildings.dir_of(b_n))
	_check(failures, Buildings.footprint_of_building(b_n) == Vector2i(1, 2),
		"(2) footprint_of_building(N-splitter) must be (1, 2) — differs from canonical (2, 1), got %s"
			% str(Buildings.footprint_of_building(b_n)))
	var b_e: Building = Buildings.make(Buildings.Type.SPLITTER, Vector2i(0, 0), 0)
	_check(failures, b_e != null and Buildings.footprint_of_building(b_e) == Vector2i(2, 1),
		"(2) footprint_of_building(E-splitter) must be canonical (2, 1)")

# ===========================================================================
# (3) PLACEMENT ASYMMETRY — the same anchor answers DIFFERENTLY per dir.
#
# Fixture A_BLK_S: chest at (20,11) blocks only the S orientation.
# Fixture A_BLK_E: chest at (31,10) blocks only the E orientation — the case
# whose expected answer DIFFERS from the canonical footprint's answer, so a
# can_place_building that ignores its dir cannot pass both fixtures.
# ===========================================================================
static func _case_placement_asymmetry(world, failures: Array) -> void:
	var c1: bool = world.place_building(Buildings.Type.CHEST, Vector2i(20, 11))
	var c2: bool = world.place_building(Buildings.Type.CHEST, Vector2i(31, 10))
	_check(failures, c1 and c2,
		"(3) PREMISE: both blocker chests must place (%s / %s)" % [str(c1), str(c2)])
	if not (c1 and c2):
		return
	_check(failures, world.can_place_building(Buildings.Type.SPLITTER, A_BLK_S, 0),
		"(3) E-splitter at (20,10) must be placeable — its rect (20,10)..(21,10) is clear: %s"
			% str(world.last_building_place_error))
	_check(failures, not world.can_place_building(Buildings.Type.SPLITTER, A_BLK_S, 1),
		"(3) S-splitter at (20,10) must be REFUSED — its rotated rect covers the chest at (20,11)")
	_check(failures, not world.can_place_building(Buildings.Type.SPLITTER, A_BLK_E, 0),
		"(3) E-splitter at (30,10) must be REFUSED — its canonical rect covers the chest at (31,10)")
	_check(failures, world.can_place_building(Buildings.Type.SPLITTER, A_BLK_E, 1),
		"(3) S-splitter at (30,10) must be placeable — the ROTATED rect (30,10)..(30,11) avoids the chest; refusing it means the dir was ignored: %s"
			% str(world.last_building_place_error))
	# place_building itself must consult the SAME dir-aware rule — a widened
	# can_place_building that place_building still calls dir-less ships
	# wrong-but-green (protocol: fixes are not monotone).
	_check(failures, not world.place_building(Buildings.Type.SPLITTER, A_BLK_S, 1),
		"(3) place_building(S-splitter, (20,10)) must REFUSE — if it placed, place_building validated against the canonical footprint, not the rotated one")

# ===========================================================================
# (5) HOVER AGREEMENT WITH DIR. hover_preview_blocked stays a pure delegation
# of NOT can_place_building — now over (type, anchor, dir). The dir-aware
# analogue of test_hover_preview_agreement's sweep, at the two fixtures where
# the two dirs disagree with each other.
# ===========================================================================
static func _case_hover_agreement(world, failures: Array) -> void:
	for row in [
		# [label, anchor, dir, expect_blocked]
		["(5) E at A_BLK_S previews FREE", A_BLK_S, 0, false],
		["(5) S at A_BLK_S previews BLOCKED", A_BLK_S, 1, true],
		["(5) E at A_BLK_E previews BLOCKED", A_BLK_E, 0, true],
		["(5) S at A_BLK_E previews FREE — a preview that reddens it ignored the dir", A_BLK_E, 1, false],
	]:
		var blocked: bool = world.hover_preview_blocked(Buildings.Type.SPLITTER, row[1], row[2])
		_check(failures, blocked == bool(row[3]),
			"%s (got blocked=%s)" % [String(row[0]), str(blocked)])
		# Agreement, not just the expected colour: the delegation must equal
		# NOT can_place_building for the same triple.
		var legal: bool = world.can_place_building(Buildings.Type.SPLITTER, row[1], row[2])
		_check(failures, blocked == not legal,
			"%s: preview (blocked=%s) disagrees with can_place_building (legal=%s) for the same dir" % [String(row[0]), str(blocked), str(legal)])
	# NEUTRAL guard unchanged: building_type < 0 returns before the dir (or
	# the placement rule) is ever consulted.
	_check(failures, not world.hover_preview_blocked(-1, A_BLK_S, 1),
		"(5) NEUTRAL hover must stay unblocked regardless of the dir argument")

# ===========================================================================
# (6) EDGE GEOMETRY FOLLOWS THE ROTATED RECT. edge_cells / footprint_contains
# take the building's orientation; literals for the orient that DIFFERS.
# Pure statics — no world.
# ===========================================================================
static func _case_edge_geometry(failures: Array) -> void:
	var e_canon: Array = Buildings.edge_cells(Buildings.Type.SPLITTER, Vector2i(60, 10), 0, 0)
	_check(failures, e_canon == [Vector2i(62, 10)],
		"(6) E edge of an E-splitter at (60,10) must be [(62,10)], got %s" % str(e_canon))
	var e_rot: Array = Buildings.edge_cells(Buildings.Type.SPLITTER, Vector2i(60, 10), 0, 1)
	_check(failures, e_rot == [Vector2i(61, 10), Vector2i(61, 11)],
		"(6) E edge of an S-splitter at (60,10) must be [(61,10), (61,11)] — 2 cells along the ROTATED tall side, got %s" % str(e_rot))
	_check(failures, Buildings.footprint_contains(Buildings.Type.SPLITTER, Vector2i(60, 10), Vector2i(60, 11), 1),
		"(6) (60,11) must be INSIDE the S-splitter's rotated rect")
	_check(failures, not Buildings.footprint_contains(Buildings.Type.SPLITTER, Vector2i(60, 10), Vector2i(60, 11), 0),
		"(6) (60,11) must be OUTSIDE the E-splitter's canonical rect")
	_check(failures, not Buildings.footprint_contains(Buildings.Type.SPLITTER, Vector2i(60, 10), Vector2i(61, 10), 1),
		"(6) (61,10) must be OUTSIDE the S-splitter's rotated rect — inside it means the orient was ignored")

# ===========================================================================
# (4) OCCUPANCY THROUGH THE REAL PLACE / REMOVE PATH.
#
# All cells of BOTH orientations at A_OCC are paved, so even a placement that
# validated against the WRONG (canonical) footprint succeeds — the occupancy
# literals below, not a placement premise, are what tell the two apart.
# ===========================================================================
static func _case_occupancy(world, failures: Array) -> void:
	var placed: bool = world.place_building(Buildings.Type.SPLITTER, A_OCC, 1)  # DIR_S
	_check(failures, placed,
		"(4) PREMISE: S-rotated splitter must place at %s: %s"
			% [str(A_OCC), str(world.last_building_place_error)])
	if not placed:
		return
	_check(failures, world.occupied.has(Vector2i(40, 10)),
		"(4) S-splitter at (40,10) must occupy its anchor (40,10)")
	_check(failures, world.occupied.has(Vector2i(40, 11)),
		"(4) S-splitter at (40,10) must occupy (40,11) — the ROTATED second cell")
	_check(failures, not world.occupied.has(Vector2i(41, 10)),
		"(4) S-splitter at (40,10) must NOT occupy (41,10) — that is the CANONICAL second cell; occupying it means rotation was ignored")
	var via_cell: Building = world.building_at(Vector2i(40, 11))
	_check(failures, via_cell != null and via_cell.type == Buildings.Type.SPLITTER,
		"(4) building_at((40,11)) must resolve to the splitter through `occupied`")
	# Removal BY THE ROTATED CELL must free both cells — the remove path
	# derives the same rotated footprint.
	_check(failures, world.remove_building_at(Vector2i(40, 11)),
		"(4) remove_building_at((40,11)) must succeed via the rotated cell")
	_check(failures, not world.occupied.has(Vector2i(40, 10)) and not world.occupied.has(Vector2i(40, 11)),
		"(4) removal must free BOTH rotated cells (40,10) and (40,11)")

# ===========================================================================
# (7) SAVE / LOAD OCCUPANCY ROUND-TRIP. A rotated 2×1 occupies the same two
# cells after load_game as before save_game — the load loop rebuilds
# `occupied` from each building's OWN dir, not the canonical row.
# Fixture save path only; the real slot is never touched.
# ===========================================================================
static func _case_save_roundtrip(parent: Node, failures: Array) -> void:
	var world_a = _make_world(parent)
	for cell in [Vector2i(50, 10), Vector2i(51, 10), Vector2i(50, 11)]:
		if not world_a.set_overlay(cell, Terrain.Overlay.STONE):
			_check(failures, false, "(7) PREMISE: could not pave %s" % str(cell))
			_teardown(world_a)
			return
	if not world_a.place_building(Buildings.Type.SPLITTER, A_SAVE, 1):  # DIR_S
		_check(failures, false, "(7) PREMISE: could not place S-splitter at %s: %s"
			% [str(A_SAVE), str(world_a.last_building_place_error)])
		_teardown(world_a)
		return
	var player_a := Node2D.new()
	parent.add_child(player_a)
	var inv_a: Inventory = Inventory.new(16)
	var saved: bool = SaveSystem.save_game(world_a, player_a, inv_a)
	player_a.queue_free()
	_teardown(world_a)
	if not saved:
		_check(failures, false, "(7) PREMISE: save_game returned false")
		return

	var world_b = _make_world(parent)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b: Inventory = Inventory.new(16)
	var result = SaveSystem.load_game(world_b, player_b, inv_b)
	player_b.queue_free()
	if not bool(result.success):
		_check(failures, false, "(7) PREMISE: load_game failed: %s" % str(result.error_message))
		_teardown(world_b)
		return
	var b: Building = world_b.building_at(Vector2i(50, 10))
	_check(failures, b != null and b.type == Buildings.Type.SPLITTER,
		"(7) the splitter must reload at its anchor (50,10)")
	_check(failures, b != null and Buildings.dir_of(b) == 1,
		"(7) the reloaded splitter must keep dir S (1), got %s"
			% (str(Buildings.dir_of(b)) if b != null else "<null>"))
	_check(failures, world_b.occupied.has(Vector2i(50, 11)),
		"(7) after load the splitter must occupy (50,11) — its ROTATED second cell")
	_check(failures, not world_b.occupied.has(Vector2i(51, 10)),
		"(7) after load the splitter must NOT occupy (51,10) — the canonical second cell; occupying it means load_game rebuilt occupancy from the type row instead of the instance dir")
	# Both directions of the occupancy answer, through the public rule:
	# the paved-but-free canonical cell accepts a building, the rotated cell
	# refuses one.
	_check(failures, world_b.can_place_building(Buildings.Type.CHEST, Vector2i(51, 10)),
		"(7) (51,10) is paved and NOT covered by the rotated splitter — a chest must be placeable there after load: %s"
			% str(world_b.last_building_place_error))
	_check(failures, not world_b.can_place_building(Buildings.Type.CHEST, Vector2i(50, 11)),
		"(7) (50,11) IS covered by the rotated splitter after load — a chest there must be refused")
	_teardown(world_b)

# ---------- helpers ----------

static func _pave_fixture(world, failures: Array) -> bool:
	# (4): both orientations' cells at A_OCC.
	# (3)/(5): anchor + both second cells + the blocker cell per fixture.
	var cells: Array = [
		Vector2i(40, 10), Vector2i(41, 10), Vector2i(40, 11),
		Vector2i(20, 10), Vector2i(21, 10), Vector2i(20, 11),
		Vector2i(30, 10), Vector2i(31, 10), Vector2i(30, 11),
	]
	for cell in cells:
		if not world.set_overlay(cell, Terrain.Overlay.STONE):
			_check(failures, false, "PREMISE: could not pave %s: %s"
				% [str(cell), str(world.last_place_error)])
			return false
	return true

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing — queue_free is deferred past the runner's
## synchronous run(), so a torn-down world otherwise stays subscribed to
## TickSystem.tick for the rest of the suite.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
