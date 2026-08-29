extends RefCounted

## GROUND PHASE 2, SESSION 1 — GROUND DOODADS.
##
## Doodads are small objects (pebbles, tufts, twigs) scattered on the grass,
## drawn beneath every building and suppressed where buildings sit. They are
## NOT the shader scatter layer (`ground_grass.gdshader`), which ships
## untouched and is world-locked in the shader itself.
##
## The locked design this file guards:
##   * Placement is DERIVED PER FRAME from world position. Nothing is
##     persisted; there is no save-schema change. Layout is a PURE FUNCTION
##     of (world_seed, cell).
##   * Candidate-then-filter: a hash decides a candidate per tile, then one
##     suppression predicate filters it.
##   * Hash-selected variant + hash mirror. NO ROTATION (it breaks the fixed
##     60 degree projection).
##   * NO SQUASH IN OUR CODE — see sub-case (D1).
##   * Integer-pixel snapping, decided at design time — see sub-case (A1).
##
## ---------------------------------------------------------------------------
## WHY GROUP (A) EXISTS AT ALL
## ---------------------------------------------------------------------------
## The shader scatter layer never needed a purity suite: nothing interacts with
## it, so nothing could make it frame- or state-dependent. Doodads are
## different — they have a suppression predicate today and will grow terrain
## inputs later, and every one of those is an invitation to reach for state
## that is NOT (seed, cell). Group (A) is the assertion that reddens when
## someone "improves" the hash with anything order-, frame- or state-dependent:
## a running counter, a cached previous cell, `Time.get_ticks_msec()`, a
## `randi()`, or a read of `TickSystem.current_tick`. Each of those makes the
## same doodad appear, move or change species between two frames that should be
## identical, and NOTHING ELSE IN THE PROJECT WOULD NOTICE — a shimmering tuft
## is not an error, a wrong value or a red test. It is the silent-compensation
## shape one more time (NOTES.md), in the one system whose entire contract is
## "the same input gives the same answer forever".
##
## ---------------------------------------------------------------------------
## EVERY EXPECTATION IS A LITERAL, AND THE LITERALS ARE FOREIGN
## ---------------------------------------------------------------------------
## The golden triples, the density count and the seed-sensitivity counts below
## were derived by an INDEPENDENT re-implementation of
## `WorldGenerator.hash3_unit` in Python (64-bit signed wrapping multiply,
## arithmetic right shift), run outside Godot, and transcribed here by hand.
## Nothing in this file asks `Doodads` what to expect. If the hash, the
## probability, the variant count, the mirror rule or the offset rule changes,
## these go red and a human has to decide whether the change was intended —
## which is the entire point, because the layout is a thing PLAYERS have seen.
##
## ---------------------------------------------------------------------------
## WHAT THIS FILE CANNOT DO
## ---------------------------------------------------------------------------
## `test_runner.gd` calls `run()` synchronously inside `_ready`, so no
## `await get_tree().process_frame` is reachable here and no `_draw()` body
## executes (docs/scoping/visual-verification.md — the ceiling splits: draw
## code IS reachable when something yields a frame, pixels never are). So:
##   * frame-independence is pinned in the reachable form — TICK-independence,
##     plus a source scan proving the selection path never reads a clock;
##   * draw ORDER is pinned against the SOURCE (route A), mirroring
##     `test_underground_indicator_contract.gd`.
## Both limits are stated rather than worked around.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const DOODADS_PATH: String = "res://scripts/world/doodads.gd"
const GRID_WORLD_PATH: String = "res://scripts/world/grid_world.gd"
const MANIFEST_PATH: String = "res://art/doodads.json"
const SPRITE_DIR: String = "res://art/sprites/doodads"

# The seed every literal below was derived at.
const SEED: int = 42
const OTHER_SEED: int = 43

# ---------------------------------------------------------------------------
# (A1) GOLDEN LITERALS — [cell_x, cell_y, present, variant, mirrored, off_x, off_y]
# Ten cells, chosen to cover: both presence states, all four variants, both
# mirror states, and negative coordinates in both axes.
# ---------------------------------------------------------------------------
const GOLDEN: Array = [
	[0, 0, false, 0, true, 22, 11],
	[1, 0, false, 2, false, 11, 20],
	[5, 7, true, 3, true, 19, 11],
	[-3, -5, true, 1, false, 25, 16],
	[1, -5, true, 0, true, 27, 23],
	[1, -2, true, 2, true, 24, 16],
	[-1, -1, true, 2, false, 14, 25],
	[-3, 0, true, 0, false, 6, 18],
	[100, 100, false, 0, true, 23, 19],
	[-40, -40, false, 0, false, 7, 24],
]

# Cells the golden set does NOT contain, used to interleave in (A2).
const UNRELATED: Array = [
	Vector2i(7, 7), Vector2i(-9, 3), Vector2i(31, -17), Vector2i(200, -200),
]

# ---------------------------------------------------------------------------
# (C) DENSITY. The rectangle is x in [0, 40), y in [0, 40) = 1600 cells.
# ---------------------------------------------------------------------------
const DENSITY_RECT_SIZE: int = 40
const DENSITY_CELLS: int = 1600
## Literal. 197 / 1600 = 0.123125 candidates per tile — ONE DOODAD PER 8.12
## TILES OF AREA. If this number moves, the ground got denser or sparser and
## somebody must look at it; a range would have absorbed exactly that.
const DENSITY_COUNT_SEED_42: int = 197
## (A5) The converse of purity: the seed must actually REACH the hash.
const DENSITY_COUNT_SEED_43: int = 221
## Cells whose PRESENCE flips between seed 42 and seed 43 over the same
## rectangle. Not 0 (seed ignored) and not 1600 (which would mean the two
## layouts are complements rather than independent).
const PRESENCE_DIFFERING_CELLS: int = 356
## Cells whose FULL tuple differs. Every cell's variant/mirror/offset is
## re-rolled by a different seed, so this is all 1600.
const TUPLE_DIFFERING_CELLS: int = 1600

# ---------------------------------------------------------------------------
# (B) SUPPRESSION FIXTURE ANCHORS.
# ---------------------------------------------------------------------------
## (B2) THE TUFT-UNDER-SMELTER BUG. SMELTER is 2x2, so anchor (0,0) occupies
## (0,0) (1,0) (0,1) (1,1). Cell (1,1) IS a candidate at seed 42 and is NOT
## the anchor. A predicate written as `buildings.has(pos)` — which asks for
## ANCHORS — passes the (B1) anchor case and leaves a tuft growing through the
## middle of the smelter here. This is its own sub-case for that reason.
const SMELTER_ANCHOR_NONANCHOR: Vector2i = Vector2i(0, 0)
const NONANCHOR_CANDIDATE: Vector2i = Vector2i(1, 1)
## (B1) An anchor cell that is itself a candidate.
const SMELTER_ANCHOR_ONCANDIDATE: Vector2i = Vector2i(-3, 0)
## (B4)/(B5)/(B6) terrain suppression cells, each a candidate at seed 42.
const OVERLAY_CANDIDATE: Vector2i = Vector2i(1, -2)
const WATER_CANDIDATE: Vector2i = Vector2i(-1, -1)
const RESOURCE_CANDIDATE: Vector2i = Vector2i(1, -5)

# ---------------------------------------------------------------------------
# (F) THE TWO STANDING TERRAIN INVARIANTS (NOTES.md, designer 2026-08-28).
# ---------------------------------------------------------------------------
## Invariant 1: no ground FEATURE smaller than 4 px, ever. The rule is about
## the smallest coherent MARK, not the bounding box — "a 2-px-wide blade is a
## violation even when the doodad's overall size is legal". So every rectangle
## a placeholder is built from is measured, not just its bbox.
const MIN_FEATURE_PX: int = 4
## The doodad size band from the brief: every dimension within 4..16 px.
const MAX_DOODAD_PX: int = 16
## Invariant 2 (the ground is the darkest thing on screen) reaches doodads as
## the manifest's own contrast cap against the shipped ground green.
const CONTRAST_CAP: float = 1.25
const GROUND_HEX: String = "#2E3A26"

static func test_name() -> String:
	return "ground doodads (pure-function layout, footprint-shared suppression, density literal, manifest contract, draw-order pin)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	Doodads.reset()
	Doodads.ensure_loaded()

	_a1_golden_literals(failures)
	_a2_order_independence(failures)
	_a3_state_independence(parent, failures)
	_a4_tick_independence(failures)
	_a5_seed_sensitivity(failures)

	_b_suppression(parent, failures)

	_c_density(failures)

	_d_manifest_contract(failures)

	_e_draw_order_pin(failures)

	_f_invariants(failures)

	_g_plan_squash_never_applied(failures)

	if failures.is_empty():
		return { "ok": true, "message":
			"sub-cases pass: layout is a pure function of (seed, cell) — golden triples, order/state/tick independence, and the seed actually reaches the hash; "
			+ "suppression shares place_building's own footprint source (the non-anchor cell of a 2x2 is covered, and removal RESTORES the same variant and mirror); "
			+ "density is 197 candidates in 1600 cells (1 per 8.12 tiles of area); plan_squash is 1.0 everywhere and is asserted, never applied; "
			+ "calibration entries never reach placement; the sprite/placeholder mode is COUNTED, not inferred; the pass draws after the grid lines and before every building" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 24))] }

# ===========================================================================
# (A1) GOLDEN LITERALS. A hash change reddens this.
#
# The OFFSET is part of the golden tuple on purpose. Integer-pixel snapping is
# LOCKED DESIGN DECISION 7: a 4-16 px sprite drawn at a fractional world
# position shimmers as the camera moves, and NO capture pair can see it —
# shimmer is motion-only, and any two paused frames are identical. So the snap
# is moved OUT of the draw call (where nothing headless can reach it) and INTO
# the pure selection, where `offset_px` is a Vector2i by construction and this
# assertion is what holds it there.
# ===========================================================================
static func _a1_golden_literals(failures: Array) -> void:
	for row in GOLDEN:
		var cell: Vector2i = Vector2i(int(row[0]), int(row[1]))
		var s: Dictionary = Doodads.selection_at(SEED, cell)
		_check(failures, bool(s["present"]) == bool(row[2]),
			"(A1) selection_at(42, %s).present must be %s, got %s — the presence hash moved"
				% [str(cell), str(row[2]), str(s["present"])])
		_check(failures, int(s["variant"]) == int(row[3]),
			"(A1) selection_at(42, %s).variant must be %d, got %d — the variant hash moved"
				% [str(cell), int(row[3]), int(s["variant"])])
		_check(failures, bool(s["mirrored"]) == bool(row[4]),
			"(A1) selection_at(42, %s).mirrored must be %s, got %s — the mirror hash moved"
				% [str(cell), str(row[4]), str(s["mirrored"])])
		_check(failures, s["offset_px"] == Vector2i(int(row[5]), int(row[6])),
			"(A1) selection_at(42, %s).offset_px must be %s, got %s — either the offset hash moved or the integer snap was lost"
				% [str(cell), str(Vector2i(int(row[5]), int(row[6]))), str(s["offset_px"])])
		_check(failures, typeof(s["offset_px"]) == TYPE_VECTOR2I,
			"(A1) offset_px at %s must be a Vector2i — a float offset is the sub-pixel shimmer decision 7 forbids, and no capture can see it"
				% str(cell))

	# Variant is always in range, presence or not: the variant roll is
	# computed for EVERY cell so that a suppressed doodad returning is the
	# same doodad (see B3).
	for row in GOLDEN:
		var s2: Dictionary = Doodads.selection_at(SEED, Vector2i(int(row[0]), int(row[1])))
		_check(failures, int(s2["variant"]) >= 0 and int(s2["variant"]) < Doodads.VARIANT_COUNT,
			"(A1) variant at %s must be in [0, %d)" % [str(Vector2i(int(row[0]), int(row[1]))), Doodads.VARIANT_COUNT])

	_check(failures, Doodads.VARIANT_COUNT == 4,
		"(A1) VARIANT_COUNT must be 4 — it is the divisor in the variant roll, so changing it re-rolls every doodad in every world that has ever been seen")
	_check(failures, is_equal_approx(Doodads.CANDIDATE_PROBABILITY, 0.125),
		"(A1) CANDIDATE_PROBABILITY must be 0.125 — one candidate per 8 tiles of AREA")

# ===========================================================================
# (A2) ORDER INDEPENDENCE. Same cells forward, reversed, and interleaved with
# unrelated cells: identical results. Reddens on any accumulator, cursor or
# "previous cell" cache in the selection path.
# ===========================================================================
static func _a2_order_independence(failures: Array) -> void:
	var forward: Array = []
	for row in GOLDEN:
		forward.append(Doodads.selection_at(SEED, Vector2i(int(row[0]), int(row[1]))))

	var reversed_cells: Array = GOLDEN.duplicate()
	reversed_cells.reverse()
	var backward: Array = []
	for row in reversed_cells:
		backward.append(Doodads.selection_at(SEED, Vector2i(int(row[0]), int(row[1]))))
	backward.reverse()

	var interleaved: Array = []
	var u: int = 0
	for row in GOLDEN:
		Doodads.selection_at(SEED, UNRELATED[u % UNRELATED.size()])
		u += 1
		interleaved.append(Doodads.selection_at(SEED, Vector2i(int(row[0]), int(row[1]))))
		Doodads.selection_at(SEED, UNRELATED[u % UNRELATED.size()])

	for i in range(GOLDEN.size()):
		_check(failures, _same(forward[i], backward[i]),
			"(A2) cell %s answers differently when the set is walked in reverse: %s vs %s — the selection is carrying state between calls"
				% [str(Vector2i(int(GOLDEN[i][0]), int(GOLDEN[i][1]))), str(forward[i]), str(backward[i])])
		_check(failures, _same(forward[i], interleaved[i]),
			"(A2) cell %s answers differently when unrelated cells are evaluated between: %s vs %s — an evaluation of ANY other cell must not be observable"
				% [str(Vector2i(int(GOLDEN[i][0]), int(GOLDEN[i][1]))), str(forward[i]), str(interleaved[i])])

# ===========================================================================
# (A3) STATE INDEPENDENCE. Build, demolish, paint, tick — then ask for the RAW
# selection again. Unchanged. Suppression is a FILTER over this answer, never
# an input to it; if the world can change what the hash says, then removing a
# building cannot restore the doodad that was there (B3).
# ===========================================================================
static func _a3_state_independence(parent: Node, failures: Array) -> void:
	var before: Array = []
	for row in GOLDEN:
		before.append(Doodads.selection_at(SEED, Vector2i(int(row[0]), int(row[1]))))

	var world = _make_world(parent, SEED)
	world.place_building(Buildings.Type.SMELTER, Vector2i(0, 0), 0)
	world.place_building(Buildings.Type.SMELTER, Vector2i(-3, 0), 0)
	world.set_overlay(Vector2i(5, 7), Terrain.Overlay.STONE)
	world.tiles[Vector2i(-1, -1)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
	for i in range(5):
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	world.remove_building_at(Vector2i(0, 0))
	world.clear_tile(Vector2i(5, 7))
	TickSystem.current_tick = 0

	var after: Array = []
	for row in GOLDEN:
		after.append(Doodads.selection_at(SEED, Vector2i(int(row[0]), int(row[1]))))
	_teardown(world)

	for i in range(GOLDEN.size()):
		_check(failures, _same(before[i], after[i]),
			"(A3) cell %s changed its RAW selection after buildings were placed and removed, terrain was painted and cleared, and five ticks ran: %s -> %s — world state must never be an INPUT to the hash, only a filter over it"
				% [str(Vector2i(int(GOLDEN[i][0]), int(GOLDEN[i][1]))), str(before[i]), str(after[i])])

# ===========================================================================
# (A4) FRAME / TICK INDEPENDENCE.
#
# ⚠ `await get_tree().process_frame` IS NOT REACHABLE HERE. `test_runner.gd`
# calls `run()` synchronously from `_ready` (see this file's header and
# docs/scoping/visual-verification.md), so a frame boundary cannot be crossed
# inside a suite. Saying that plainly rather than pretending otherwise:
# frame-independence is pinned in the two forms that ARE reachable —
#   (i)  TICK independence, driven directly at several tick numbers, and
#   (ii) a SOURCE scan proving the selection path never reads a clock at all,
#        which is the stronger of the two because it forbids the mechanism
#        rather than sampling the symptom.
# ===========================================================================
static func _a4_tick_independence(failures: Array) -> void:
	var at_zero: Array = []
	TickSystem.current_tick = 0
	for row in GOLDEN:
		at_zero.append(Doodads.selection_at(SEED, Vector2i(int(row[0]), int(row[1]))))

	for t in [1, 7, 999, 123456]:
		TickSystem.current_tick = t
		TickSystem.tick.emit(t)
		for i in range(GOLDEN.size()):
			var cell: Vector2i = Vector2i(int(GOLDEN[i][0]), int(GOLDEN[i][1]))
			var now: Dictionary = Doodads.selection_at(SEED, cell)
			_check(failures, _same(at_zero[i], now),
				"(A4) cell %s answers differently at tick %d: %s vs %s — the layout must not move with the clock"
					% [str(cell), t, str(at_zero[i]), str(now)])
	TickSystem.current_tick = 0

	# (ii) The mechanism, forbidden at source. Anything time-, frame- or
	# RNG-shaped in doodads.gd defeats the whole contract; the sampled
	# assertion above can only catch it if the sample happens to land.
	var src: String = FileAccess.get_file_as_string(DOODADS_PATH)
	if src == "":
		_check(failures, false, "(A4) could not read %s" % DOODADS_PATH)
		return
	var banned: Array = [
		"Time.get_ticks", "Time.get_unix", "OS.get_ticks", "Engine.get_frames_drawn",
		"Engine.get_process_frames", "Engine.get_physics_frames",
		"TickSystem.current_tick", "randi", "randf", "RandomNumberGenerator",
		"get_process_delta_time", "get_physics_process_delta_time",
	]
	for token in banned:
		_check(failures, _stripped_source(src).find(token) < 0,
			"(A4) doodads.gd mentions '%s' — the layout is a PURE FUNCTION of (world_seed, cell); a clock, a frame counter or an RNG in this file makes doodads flicker between two frames that must be identical, and nothing else in the project would notice"
				% token)

# ===========================================================================
# (A5) SEED SENSITIVITY — the converse of (A1)-(A4). A layout that is stable
# for the WRONG reason (the seed never reaching the hash) passes every purity
# case above perfectly. Both counts are literals.
# ===========================================================================
static func _a5_seed_sensitivity(failures: Array) -> void:
	var presence_diff: int = 0
	var tuple_diff: int = 0
	var count43: int = 0
	for y in range(0, DENSITY_RECT_SIZE):
		for x in range(0, DENSITY_RECT_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			var a: Dictionary = Doodads.selection_at(SEED, cell)
			var b: Dictionary = Doodads.selection_at(OTHER_SEED, cell)
			if bool(a["present"]) != bool(b["present"]):
				presence_diff += 1
			if not _same(a, b):
				tuple_diff += 1
			if bool(b["present"]):
				count43 += 1

	_check(failures, presence_diff == PRESENCE_DIFFERING_CELLS,
		"(A5) seed 42 vs 43 must flip PRESENCE on exactly %d of %d cells, got %d — 0 means the seed never reaches the hash and every world has an identical ground"
			% [PRESENCE_DIFFERING_CELLS, DENSITY_CELLS, presence_diff])
	_check(failures, tuple_diff == TUPLE_DIFFERING_CELLS,
		"(A5) seed 42 vs 43 must differ in the FULL tuple on all %d cells, got %d"
			% [TUPLE_DIFFERING_CELLS, tuple_diff])
	_check(failures, count43 == DENSITY_COUNT_SEED_43,
		"(A5) seed 43 must yield exactly %d candidates in the same rectangle, got %d"
			% [DENSITY_COUNT_SEED_43, count43])

# ===========================================================================
# (B) SUPPRESSION. One predicate, sharing place_building's own footprint
# source — GridWorld.occupied, written by place_building via _footprint_cells,
# which is the same source can_place_building validates against.
# ===========================================================================
static func _b_suppression(parent: Node, failures: Array) -> void:
	var world = _make_world(parent, SEED)

	# Premises: all five fixture cells must be candidates before anything is
	# placed, or every assertion below passes vacuously.
	for cell in [NONANCHOR_CANDIDATE, SMELTER_ANCHOR_ONCANDIDATE, OVERLAY_CANDIDATE, WATER_CANDIDATE, RESOURCE_CANDIDATE]:
		_check(failures, bool(Doodads.doodad_at(world, cell)["present"]),
			"(B) PREMISE: %s must carry a doodad on clean grass at seed 42, or its suppression case proves nothing" % str(cell))

	# (B1) Anchor cell.
	var before_anchor: Dictionary = Doodads.doodad_at(world, SMELTER_ANCHOR_ONCANDIDATE)
	var placed_anchor: bool = world.place_building(Buildings.Type.SMELTER, SMELTER_ANCHOR_ONCANDIDATE, 0)
	_check(failures, placed_anchor,
		"(B1) PREMISE: could not place the smelter at %s: %s" % [str(SMELTER_ANCHOR_ONCANDIDATE), world.last_building_place_error])
	_check(failures, not bool(Doodads.doodad_at(world, SMELTER_ANCHOR_ONCANDIDATE)["present"]),
		"(B1) a doodad on the smelter's ANCHOR cell %s must be suppressed" % str(SMELTER_ANCHOR_ONCANDIDATE))

	# (B2) THE TUFT-UNDER-SMELTER BUG. A non-anchor footprint cell of a 2x2.
	# `buildings.has(pos)` passes (B1) and fails HERE.
	var before_nonanchor: Dictionary = Doodads.doodad_at(world, NONANCHOR_CANDIDATE)
	var placed_2x2: bool = world.place_building(Buildings.Type.SMELTER, SMELTER_ANCHOR_NONANCHOR, 0)
	_check(failures, placed_2x2,
		"(B2) PREMISE: could not place the smelter at %s: %s" % [str(SMELTER_ANCHOR_NONANCHOR), world.last_building_place_error])
	_check(failures, world.buildings.has(SMELTER_ANCHOR_NONANCHOR) and not world.buildings.has(NONANCHOR_CANDIDATE),
		"(B2) PREMISE: %s must be a NON-ANCHOR footprint cell — it is the whole discriminator" % str(NONANCHOR_CANDIDATE))
	_check(failures, world.occupied.has(NONANCHOR_CANDIDATE),
		"(B2) PREMISE: place_building must have written %s into `occupied`" % str(NONANCHOR_CANDIDATE))
	_check(failures, not Doodads.allowed_at(world, NONANCHOR_CANDIDATE),
		"(B2) allowed_at must refuse %s — it is inside the 2x2 smelter's footprint but is NOT its anchor. A predicate written against `buildings` (which is keyed by ANCHOR) passes the (B1) case and leaves a tuft growing through the middle of the machine. Ask the same source place_building writes: `occupied` / has_building_at" % str(NONANCHOR_CANDIDATE))
	_check(failures, not bool(Doodads.doodad_at(world, NONANCHOR_CANDIDATE)["present"]),
		"(B2) the doodad at the non-anchor footprint cell %s must stop being drawn" % str(NONANCHOR_CANDIDATE))

	# (B3) REMOVAL RESTORES THE SAME DOODAD — proves derivation, not
	# regeneration. A module that cached or randomised on demolition would
	# hand back a different species here.
	_check(failures, world.remove_building_at(SMELTER_ANCHOR_NONANCHOR),
		"(B3) PREMISE: could not remove the smelter at %s" % str(SMELTER_ANCHOR_NONANCHOR))
	var after_nonanchor: Dictionary = Doodads.doodad_at(world, NONANCHOR_CANDIDATE)
	_check(failures, _same(before_nonanchor, after_nonanchor),
		"(B3) removing the building must restore the SAME doodad at %s — was %s, now %s. A different variant or mirror here means the layout is being REGENERATED rather than DERIVED"
			% [str(NONANCHOR_CANDIDATE), str(before_nonanchor), str(after_nonanchor)])
	_check(failures, world.remove_building_at(SMELTER_ANCHOR_ONCANDIDATE),
		"(B3) PREMISE: could not remove the smelter at %s" % str(SMELTER_ANCHOR_ONCANDIDATE))
	_check(failures, _same(before_anchor, Doodads.doodad_at(world, SMELTER_ANCHOR_ONCANDIDATE)),
		"(B3) removing the building must restore the SAME doodad at the anchor cell %s" % str(SMELTER_ANCHOR_ONCANDIDATE))

	# (B4) Overlay.
	_check(failures, world.set_overlay(OVERLAY_CANDIDATE, Terrain.Overlay.STONE),
		"(B4) PREMISE: could not pave %s: %s" % [str(OVERLAY_CANDIDATE), world.last_place_error])
	_check(failures, not Doodads.allowed_at(world, OVERLAY_CANDIDATE),
		"(B4) a paved tile (overlay != NONE) must suppress its doodad at %s — a pebble in the middle of a stone path reads as a rendering bug" % str(OVERLAY_CANDIDATE))
	_check(failures, world.clear_tile(OVERLAY_CANDIDATE),
		"(B4) PREMISE: could not clear %s" % str(OVERLAY_CANDIDATE))
	_check(failures, Doodads.allowed_at(world, OVERLAY_CANDIDATE),
		"(B4) clearing the overlay must restore the doodad at %s" % str(OVERLAY_CANDIDATE))

	# (B5) Base != GRASS.
	world.tiles[WATER_CANDIDATE] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
	_check(failures, not Doodads.allowed_at(world, WATER_CANDIDATE),
		"(B5) a non-GRASS base must suppress its doodad at %s — doodads are a GRASS feature; a twig floating on a lake is the failure" % str(WATER_CANDIDATE))

	# (B6) Resource node.
	world.tiles[RESOURCE_CANDIDATE] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.IRON)
	_check(failures, not Doodads.allowed_at(world, RESOURCE_CANDIDATE),
		"(B6) a resource node must suppress its doodad at %s — the deposit inset and the tree canopy both already draw inside the tile" % str(RESOURCE_CANDIDATE))
	world.tiles[RESOURCE_CANDIDATE] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)
	_check(failures, not Doodads.allowed_at(world, RESOURCE_CANDIDATE),
		"(B6) a TREE must suppress its doodad at %s too" % str(RESOURCE_CANDIDATE))

	# Clean grass is the permissive case — a predicate that refuses everything
	# passes every assertion above.
	world.tiles.erase(RESOURCE_CANDIDATE)
	world.tiles.erase(WATER_CANDIDATE)
	_check(failures, Doodads.allowed_at(world, RESOURCE_CANDIDATE) and Doodads.allowed_at(world, WATER_CANDIDATE),
		"(B) clean unmodified grass must ALLOW doodads — a predicate that refuses everything satisfies every suppression case above")

	_teardown(world)

# ===========================================================================
# (C) DENSITY, as an exact count. Not a range: a range is how a density change
# ships without anybody deciding it.
# ===========================================================================
static func _c_density(failures: Array) -> void:
	var n: int = 0
	for y in range(0, DENSITY_RECT_SIZE):
		for x in range(0, DENSITY_RECT_SIZE):
			if bool(Doodads.selection_at(SEED, Vector2i(x, y))["present"]):
				n += 1
	_check(failures, n == DENSITY_COUNT_SEED_42,
		"(C) seed 42 must yield exactly %d candidates over the %dx%d rectangle (= 0.123125 per tile, ONE DOODAD PER 8.12 TILES OF AREA), got %d"
			% [DENSITY_COUNT_SEED_42, DENSITY_RECT_SIZE, DENSITY_RECT_SIZE, n])

# ===========================================================================
# (D) MANIFEST CONTRACT + THE LOUD FALLBACK.
# ===========================================================================
static func _d_manifest_contract(failures: Array) -> void:
	# (D4) THE COUNTERS EXIST AND ARE QUERYABLE. This is the assertion that
	# makes "no sprites" distinguishable from "sprites fine" — the codebase's
	# named failure shape (NOTES.md, "Protocol: silent compensation"). A
	# procedural placeholder drawn through the same placement path renders a
	# plausible ground either way; only a COUNT can tell the two apart.
	_check(failures, Doodads.loaded_count + Doodads.placeholder_count == Doodads.VARIANT_COUNT,
		"(D4) loaded_count (%d) + placeholder_count (%d) must account for all %d variants — a variant in neither bucket is a mode nobody can query"
			% [Doodads.loaded_count, Doodads.placeholder_count, Doodads.VARIANT_COUNT])
	for i in range(Doodads.VARIANT_COUNT):
		var mode: String = Doodads.variant_mode(i)
		_check(failures, mode == "sprite" or mode == "placeholder",
			"(D4) variant %d must report mode 'sprite' or 'placeholder', got '%s'" % [i, mode])

	if not Doodads.manifest_present:
		# LOUD, not silent. The manifest lives in `art/`, owned by a concurrent
		# Blender session. If it is absent the content gates below cannot run —
		# so instead of skipping quietly, assert the FALLBACK MODE positively
		# and say so in the failure text of every later run.
		print("[test_doodads] MANIFEST ABSENT at %s — (D1)-(D3) assert the fallback mode instead of manifest content." % MANIFEST_PATH)
		_check(failures, Doodads.placeholder_count == Doodads.VARIANT_COUNT,
			"(D) the manifest is absent, so EVERY variant must be a placeholder and say so: placeholder_count is %d of %d"
				% [Doodads.placeholder_count, Doodads.VARIANT_COUNT])
		_check(failures, Doodads.loaded_count == 0,
			"(D) the manifest is absent, so loaded_count must be 0, got %d" % Doodads.loaded_count)
		return

	var reader := JSON.new()
	if reader.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK:
		_check(failures, false, "(D) %s is unparseable: line %d, %s"
			% [MANIFEST_PATH, reader.get_error_line(), reader.get_error_message()])
		return
	if typeof(reader.data) != TYPE_DICTIONARY:
		_check(failures, false, "(D) %s is not a JSON object" % MANIFEST_PATH)
		return
	var manifest: Dictionary = reader.data
	var entries: Array = manifest.get("doodads", [])
	_check(failures, entries.size() > 0, "(D) %s declares no doodads" % MANIFEST_PATH)

	var real_names: Array = []
	for e in entries:
		var d: Dictionary = e
		var name: String = str(d.get("name", "?"))

		# (D1) plan_squash IS 1.0 EVERYWHERE, AND IS ASSERTED, NEVER APPLIED.
		# GROUND_SQUASH 0.86603 is already baked into the Blender render and
		# undone by the anamorphic downsample (art/PIPELINE.md:81-110); the
		# calibration disc measures a ROUND 32x33 ink bbox. Applying
		# plan_squash in our draw would squash a second time — the ruined-read
		# failure, and one nobody can see by looking because a slightly
		# flattened pebble still looks like a pebble.
		_check(failures, typeof(d.get("plan_squash", null)) == TYPE_FLOAT or typeof(d.get("plan_squash", null)) == TYPE_INT,
			"(D1) manifest entry '%s' has no numeric plan_squash" % name)
		_check(failures, is_equal_approx(float(d.get("plan_squash", -1.0)), 1.0),
			"(D1) manifest entry '%s' has plan_squash %s, not 1.0. This value is ASSERTED and NEVER APPLIED: the camera squash is already undone by the anamorphic downsample, so applying it again DOUBLE-SQUASHES the doodad and it becomes the only object in the game disagreeing with its own tile grid"
				% [name, str(d.get("plan_squash", null))])

		if str(d.get("status", "")) == "real":
			real_names.append(name)

	# (D2) CALIBRATION ENTRIES ARE EXCLUDED FROM PLACEMENT. `_calib_disc` is a
	# 32 px unit disc that exists to MEASURE the plan aspect ratio. If it ever
	# appears in game it is an enormous grey coin lying on the grass.
	for e2 in entries:
		var d2: Dictionary = e2
		if str(d2.get("status", "")) != "calibration":
			continue
		_check(failures, not (str(d2.get("name", "?")) in Doodads.VARIANT_NAMES),
			"(D2) calibration entry '%s' must NEVER be placeable — it is a measurement target, not art. Doodads.VARIANT_NAMES is %s"
				% [str(d2.get("name", "?")), str(Doodads.VARIANT_NAMES)])

	# The variant table is the game's decision about WHICH doodads exist, and
	# it is deliberately NOT read from the manifest (manifest order must not be
	# able to silently re-bind variant 0). That makes it a copy — so, per
	# NOTES.md ("read it, don't copy it; if you must copy it, assert the
	# copy"), the copy is asserted against its source.
	real_names.sort()
	var declared: Array = Doodads.VARIANT_NAMES.duplicate()
	declared.sort()
	_check(failures, real_names == declared,
		"(D2) the manifest's status=='real' entries %s must be exactly Doodads.VARIANT_NAMES %s — if art adds or renames a doodad, the variant table is a deliberate edit here, not an automatic re-bind that silently re-rolls every world's layout"
			% [str(real_names), str(declared)])

	# The manifest's photometric cap is DELIBERATELY NOT ASSERTED HERE, and this
	# comment is why, so it does not get "restored" by a future session.
	# The game reads sprite_px, anchor_px, plan_squash and status. It does not
	# read the cap. Asserting it here made THIS suite -- the game's placement
	# suite -- go red on 2026-08-28 when the art session renamed contrast_cap to
	# median_cap while redesigning the gate, a change with no bearing on any
	# line of placement code. Cross-boundary photometric consistency is a
	# GATE-layer concern and lives in scripts/tools/ground_verify.py, which
	# caught the same drift on the same run and is the right place for it.
	# The rule: this suite asserts what the game READS; the gate layer asserts
	# what the two sides must AGREE on.
	_check(failures, str(manifest.get("ground_hex", "")) == GROUND_HEX,
		"(D) manifest ground_hex must be %s, got %s" % [GROUND_HEX, str(manifest.get("ground_hex", ""))])

	# (D3) Sidecar sprite_px matches the PNG on disk, wherever the PNG exists.
	# Same trade `test_sprite_manifest.gd` takes deliberately: an asset broken
	# at source should stop the build rather than ship as an invisible
	# fallback, and the message names the two numbers that disagree.
	for name2 in Doodads.VARIANT_NAMES:
		var jpath: String = "%s/%s.json" % [SPRITE_DIR, name2]
		var ppath: String = "%s/%s.png" % [SPRITE_DIR, name2]
		if not FileAccess.file_exists(jpath) or not FileAccess.file_exists(ppath):
			continue
		var sr := JSON.new()
		if sr.parse(FileAccess.get_file_as_string(jpath)) != OK or typeof(sr.data) != TYPE_DICTIONARY:
			_check(failures, false, "(D3) sidecar %s is unparseable" % jpath)
			continue
		var sj: Dictionary = sr.data
		var sp: Array = sj.get("sprite_px", [])
		_check(failures, sp.size() == 2, "(D3) sidecar %s has no 2-element sprite_px" % jpath)
		if sp.size() != 2:
			continue
		var img := Image.new()
		if img.load(ppath) != OK:
			_check(failures, false, "(D3) %s failed to load" % ppath)
			continue
		_check(failures, img.get_size() == Vector2i(int(sp[0]), int(sp[1])),
			"(D3) %s is %dx%d on disk but %s says sprite_px %dx%d"
				% [ppath, img.get_size().x, img.get_size().y, jpath, int(sp[0]), int(sp[1])])
		_check(failures, is_equal_approx(float(sj.get("plan_squash", -1.0)), 1.0),
			"(D1) sidecar %s has plan_squash %s, not 1.0 — see the double-squash note above" % [jpath, str(sj.get("plan_squash", null))])

		# (D4, the other half) With every sprite present, NOTHING may be a
		# placeholder. This is the assertion that fires when the loader
		# silently stops loading.
		_check(failures, Doodads.variant_mode(Doodads.VARIANT_NAMES.find(name2)) == "sprite",
			"(D4) %s exists on disk with a matching sidecar, so variant '%s' must be in SPRITE mode, not placeholder. It reported '%s'. Notes: %s"
				% [ppath, name2, Doodads.variant_mode(Doodads.VARIANT_NAMES.find(name2)), str(Doodads.load_notes)])

# ===========================================================================
# (E) DRAW-ORDER STRUCTURAL PIN.
#
# Headless cannot execute a `_draw` body (docs/scoping/visual-verification.md,
# route A), so the ONE locked ordering obligation is pinned against the
# SOURCE, exactly as test_underground_indicator_contract.gd pins the
# pair-indicator's: the doodad pass runs AFTER the grid-line pass and BEFORE
# the buildings loop. Doodads under buildings is the whole point — a pebble
# drawn on top of a smelter is not a subtle defect.
#
# Comment-aware, unlike the substring searches in the file it mirrors: every
# line is stripped of its comment (quote-aware) before matching, so a
# commented-out call CANNOT satisfy the pin.
# ===========================================================================
const DOODAD_PASS_NAME: String = "_draw_ground_doodads"

static func _e_draw_order_pin(failures: Array) -> void:
	var src: String = FileAccess.get_file_as_string(GRID_WORLD_PATH)
	if src == "":
		_check(failures, false, "(E) could not read %s" % GRID_WORLD_PATH)
		return

	var lines: Array = src.split("\n")
	var def_line: int = -1
	var grid_line: int = -1
	var doodad_call: int = -1
	var buildings_line: int = -1
	for i in range(lines.size()):
		var code: String = _strip_comment(String(lines[i]))
		var t: String = code.strip_edges()
		if t == "":
			continue
		if t.begins_with("func %s(" % DOODAD_PASS_NAME):
			def_line = i
			continue
		# The grid-line pass is an inline loop, identified by its colour
		# constant; take the LAST such draw so "after the grid lines" means
		# after all of them.
		if t.find("GRID_COLOR") >= 0 and t.find("draw_line(") >= 0:
			grid_line = i
		# The call site: tab-indented statement inside _draw, never the
		# column-0 definition.
		if code.begins_with("\t") and t == "%s(min_tile, max_tile)" % DOODAD_PASS_NAME:
			doodad_call = i
		if buildings_line < 0 and t == "for anchor_key in buildings:":
			buildings_line = i

	_check(failures, def_line >= 0,
		"(E) grid_world.gd must define the dedicated pass 'func %s(' — ONE new pass with a defined layer. If it was renamed or inlined into the per-building loop, the z-order finding just lost its layer; rename it here too and re-justify" % DOODAD_PASS_NAME)
	_check(failures, grid_line >= 0,
		"(E) could not find the grid-line pass (a draw_line using GRID_COLOR) in grid_world.gd")
	_check(failures, buildings_line >= 0,
		"(E) could not find the buildings pass ('for anchor_key in buildings:') in grid_world.gd")
	_check(failures, doodad_call >= 0,
		"(E) _draw must CALL %s(min_tile, max_tile) as a real, uncommented statement — a commented-out call cannot satisfy this pin" % DOODAD_PASS_NAME)

	if grid_line >= 0 and doodad_call >= 0:
		_check(failures, grid_line < doodad_call,
			"(E) the doodad pass (line %d) must run AFTER the grid-line pass (line %d)" % [doodad_call + 1, grid_line + 1])
	if doodad_call >= 0 and buildings_line >= 0:
		_check(failures, doodad_call < buildings_line,
			"(E) the doodad pass (line %d) must run BEFORE the buildings loop (line %d) — doodads go UNDER every building, and a doodad drawn over a smelter is not a subtle defect"
				% [doodad_call + 1, buildings_line + 1])

	# The pass must not be reached from inside the per-building loop.
	if def_line >= 0:
		var body_end: int = src.find("\nfunc ", src.find("func %s(" % DOODAD_PASS_NAME) + 1)
		var body: String = src.substr(src.find("func %s(" % DOODAD_PASS_NAME), (body_end - src.find("func %s(" % DOODAD_PASS_NAME)) if body_end > 0 else -1)
		_check(failures, _stripped_source(body).find("Doodads.doodad_at(") >= 0,
			"(E) the doodad pass must ask Doodads.doodad_at — the ONE predicate that ANDs the pure selection with the suppression filter. Re-deriving either half in the renderer is how the drawn ground and the queried ground drift apart")

# ===========================================================================
# (F) THE TWO STANDING TERRAIN INVARIANTS (NOTES.md, designer 2026-08-28),
# applied to the placeholders, which are OUR art and therefore ours to gate.
# ===========================================================================
static func _f_invariants(failures: Array) -> void:
	var ground: Color = Color(GROUND_HEX)
	for i in range(Doodads.VARIANT_COUNT):
		var spec: Dictionary = Doodads.placeholder_spec(i)
		var size: Vector2i = spec["size"]
		_check(failures, size.x >= MIN_FEATURE_PX and size.y >= MIN_FEATURE_PX
				and size.x <= MAX_DOODAD_PX and size.y <= MAX_DOODAD_PX,
			"(F) placeholder %d is %dx%d — every dimension must sit within %d..%d px"
				% [i, size.x, size.y, MIN_FEATURE_PX, MAX_DOODAD_PX])
		var rects: Array = spec["rects"]
		_check(failures, rects.size() > 0, "(F) placeholder %d draws nothing" % i)
		for r in rects:
			var rw: int = int(r[2])
			var rh: int = int(r[3])
			# INVARIANT 1, and it is about the FEATURE, not the bounding box:
			# "a 2-px-wide blade is a violation even when the doodad's overall
			# size is legal". The ground does not downsample, so sub-4-px marks
			# put energy in a band the LANCZOS-resampled buildings structurally
			# cannot hold, and the eye reads it as buildings pasted ON the
			# ground rather than standing on it.
			_check(failures, rw >= MIN_FEATURE_PX and rh >= MIN_FEATURE_PX,
				"(F) placeholder %d has a %dx%d mark — invariant 1 forbids ANY ground feature under %d px, measured on the smallest coherent MARK and not the bbox"
					% [i, rw, rh, MIN_FEATURE_PX])
			_check(failures, int(r[0]) >= 0 and int(r[1]) >= 0
					and int(r[0]) + rw <= size.x and int(r[1]) + rh <= size.y,
				"(F) placeholder %d has a mark outside its own %dx%d bounds" % [i, size.x, size.y])

	# At least one placeholder must be ASYMMETRIC about its vertical axis, or
	# the mirror bit is invisible and (A1)'s mirror literals are decorative.
	var asymmetric: int = 0
	for i2 in range(Doodads.VARIANT_COUNT):
		if _is_asymmetric(Doodads.placeholder_spec(i2)):
			asymmetric += 1
	_check(failures, asymmetric >= 1,
		"(F) at least one placeholder must be asymmetric about its vertical axis — otherwise the hash mirror bit cannot be SEEN, and a broken mirror looks exactly like a working one")

	# INVARIANT 2 reaches doodads as the manifest's contrast cap against the
	# shipped ground green. The ground stays the darkest thing on screen; the
	# ink on it must not exceed the cap.
	var ratio: float = _contrast(Doodads.PLACEHOLDER_INK, ground)
	_check(failures, ratio <= CONTRAST_CAP,
		"(F) placeholder ink %s sits at contrast %f against the ground %s — the cap is %f. Invariant 2 (the ground is the darkest thing on screen) is what keeps buildings STANDING ON the ground instead of pasted onto it"
			% [Doodads.PLACEHOLDER_INK.to_html(false), ratio, GROUND_HEX, CONTRAST_CAP])
	_check(failures, ratio > 1.0,
		"(F) placeholder ink is indistinguishable from the ground (contrast %f) — a placeholder nobody can see is a silent fallback wearing a different hat" % ratio)

# ===========================================================================
# (G) plan_squash IS NEVER APPLIED — structural, and STRUCTURAL IS ALL THERE
# CAN BE.
#
# Stated plainly because it matters: plan_squash is 1.0 in every sidecar, so
# APPLYING it is arithmetically a NO-OP TODAY. No runtime assertion anywhere
# can distinguish "asserted and ignored" from "multiplied in". The defect this
# guards against only becomes visible the day art ships a non-1.0 value, by
# which time the multiply is old code nobody re-reads. So the mechanism is
# forbidden at source instead of the outcome being sampled.
# ===========================================================================
static func _g_plan_squash_never_applied(failures: Array) -> void:
	var src: String = FileAccess.get_file_as_string(DOODADS_PATH)
	if src == "":
		_check(failures, false, "(G) could not read %s" % DOODADS_PATH)
		return
	var lines: Array = src.split("\n")
	var asserted: bool = false
	for i in range(lines.size()):
		var code: String = _strip_comment(String(lines[i]))
		if code.find("plan_squash") < 0:
			continue
		if code.find("PLAN_SQUASH_REQUIRED") >= 0:
			asserted = true
		_check(failures, code.find("*") < 0 and code.find("scale") < 0,
			"(G) doodads.gd line %d uses plan_squash in an arithmetic/scale expression: '%s'. It is ASSERTED, NEVER APPLIED — the render already had GROUND_SQUASH baked in and the anamorphic downsample already took it back out (art/PIPELINE.md:81-110), so a second application double-squashes and the doodad becomes the only object in the game disagreeing with its own tile grid"
				% [i + 1, code.strip_edges()])
	_check(failures, asserted,
		"(G) doodads.gd must ASSERT plan_squash against PLAN_SQUASH_REQUIRED. Deleting the assertion is how a non-1.0 value starts arriving unnoticed")

# ===========================================================================
# helpers
# ===========================================================================
static func _same(a: Dictionary, b: Dictionary) -> bool:
	return bool(a["present"]) == bool(b["present"]) \
		and int(a["variant"]) == int(b["variant"]) \
		and bool(a["mirrored"]) == bool(b["mirrored"]) \
		and a["offset_px"] == b["offset_px"]

static func _is_asymmetric(spec: Dictionary) -> bool:
	var size: Vector2i = spec["size"]
	var have: Dictionary = {}
	for r in spec["rects"]:
		have["%d,%d,%d,%d" % [int(r[0]), int(r[1]), int(r[2]), int(r[3])]] = true
	for r2 in spec["rects"]:
		var mx: int = size.x - (int(r2[0]) + int(r2[2]))
		if not have.has("%d,%d,%d,%d" % [mx, int(r2[1]), int(r2[2]), int(r2[3])]):
			return true
	return false

## WCAG relative luminance / contrast, the same formula NOTES.md's invariant 2
## derivation uses.
static func _rel_luminance(c: Color) -> float:
	var ch: Array = [c.r, c.g, c.b]
	var lin: Array = []
	for v in ch:
		lin.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * float(lin[0]) + 0.7152 * float(lin[1]) + 0.0722 * float(lin[2])

static func _contrast(a: Color, b: Color) -> float:
	var la: float = _rel_luminance(a)
	var lb: float = _rel_luminance(b)
	var hi: float = max(la, lb)
	var lo: float = min(la, lb)
	return (hi + 0.05) / (lo + 0.05)

## Quote-aware comment strip: cut at the first `#` that is NOT inside a string
## literal, so a hex colour like "#2E3A26" does not truncate the line.
static func _strip_comment(line: String) -> String:
	var in_s: bool = false
	var q: String = ""
	for i in range(line.length()):
		var ch: String = line[i]
		if in_s:
			if ch == "\\":
				continue
			if ch == q:
				in_s = false
			continue
		if ch == "\"" or ch == "'":
			in_s = true
			q = ch
			continue
		if ch == "#":
			return line.substr(0, i)
	return line

static func _stripped_source(src: String) -> String:
	var out: Array = []
	for line in src.split("\n"):
		out.append(_strip_comment(String(line)))
	return "\n".join(out)

static func _make_world(parent: Node, seed_value: int):
	var world = GridWorldScript.new()
	world.world_seed = seed_value
	parent.add_child(world)
	return world

static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
