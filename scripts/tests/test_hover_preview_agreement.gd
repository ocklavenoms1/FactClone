extends RefCounted

## Audit #16 — the placement hover preview must agree with `can_place_building`
## in BOTH directions.
##
## The title of the finding is the claim, and it names two failures, not one:
##
##   1. A LEGAL placement previewing RED. Every overlay-requiring building on
##      prepared ground: `set_overlay` writes a `tiles` entry for every STONE /
##      PATH / SOIL_TILLED cell, and the old predicate read `tiles.has(cell)`
##      as "occupied".
##   2. An ILLEGAL placement previewing WHITE. Bare grass has NO `tiles` entry,
##      so a building that cannot stand on grass previewed as free.
##
## Plus a third clause the title's "contradicts" covers: the old predicate knew
## nothing of the type-specific rules (Pump water adjacency, MiningDrill ore
## coverage) that `can_place_building` enforces.
##
## ⚠ WHY THIS SUITE EXISTS IN THIS SHAPE. The predicate used to be an inline
## loop inside `GridWorld._draw`, and `test_runner.gd` never yields a frame, so
## no `CanvasItem` here is ever sent NOTIFICATION_DRAW (NOTES.md, "A structural
## ceiling"). The audit prescribed a three-line swap in place — which would have
## been correct AND completely untestable, shipping green with nothing able to
## touch it. The predicate was therefore EXTRACTED to
## `GridWorld.hover_preview_blocked()` first; this suite calls that method
## directly, without a frame. If a future refactor inlines it back into `_draw`,
## this suite stops compiling rather than stops meaning anything.
##
## It cannot assert the preview's COLOUR — headless has no pixels. It asserts
## the boolean that chooses the colour, which is the whole of the defect.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# ---- Fixture coordinates. Each case owns its own cells; nothing is shared
# between a case that must agree and a case that must disagree pre-fix.
const STONE_1x1: Vector2i = Vector2i(5, 5)        # paved, empty
const GRASS_1x1: Vector2i = Vector2i(7, 5)        # bare, empty
const STONE_CHEST: Vector2i = Vector2i(9, 5)      # paved, occupied by a chest
const STONE_2x2: Vector2i = Vector2i(11, 5)       # paved 2x2, empty
const GRASS_2x2: Vector2i = Vector2i(15, 5)       # bare 2x2
const STONE_2x2_BLOCKED: Vector2i = Vector2i(18, 5)  # paved 2x2, chest in far corner
const WATER: Vector2i = Vector2i(21, 5)
const STONE_BY_WATER: Vector2i = Vector2i(22, 5)  # paved, adjacent to WATER
const STONE_DRY: Vector2i = Vector2i(25, 5)       # paved, no water within reach
const ORE_2x2: Vector2i = Vector2i(30, 5)         # 2x2 of iron
const GRASS_DRILL: Vector2i = Vector2i(34, 5)     # bare 2x2, no ore
const FAR_EMPTY: Vector2i = Vector2i(400, 400)    # nothing has ever touched it

## Every (type, anchor) pair the by-construction sweep visits.
const SWEEP_POSITIONS: Array = [
	STONE_1x1, GRASS_1x1, STONE_CHEST, STONE_2x2, GRASS_2x2,
	STONE_2x2_BLOCKED, WATER, STONE_BY_WATER, STONE_DRY,
	ORE_2x2, GRASS_DRILL, FAR_EMPTY,
]

static func test_name() -> String:
	return "hover preview agrees with can_place_building (audit #16, both directions)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var world = GridWorldScript.new()
	parent.add_child(world)

	# ---- Fixture ------------------------------------------------------------
	world.set_overlay(STONE_1x1, Terrain.Overlay.STONE)
	world.set_overlay(STONE_CHEST, Terrain.Overlay.STONE)
	for dx in 2:
		for dy in 2:
			world.set_overlay(STONE_2x2 + Vector2i(dx, dy), Terrain.Overlay.STONE)
			world.set_overlay(STONE_2x2_BLOCKED + Vector2i(dx, dy), Terrain.Overlay.STONE)
			world.tiles[ORE_2x2 + Vector2i(dx, dy)] = Tile.new(
				Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.IRON)
	world.set_overlay(STONE_BY_WATER, Terrain.Overlay.STONE)
	world.set_overlay(STONE_DRY, Terrain.Overlay.STONE)
	world.tiles[WATER] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
	# Two chests: one alone on stone, one in the far corner of a legal 2x2.
	var chest_ok: bool = world.place_building(Buildings.Type.CHEST, STONE_CHEST)
	var chest2_ok: bool = world.place_building(
		Buildings.Type.CHEST, STONE_2x2_BLOCKED + Vector2i(1, 1))
	_check(failures, chest_ok and chest2_ok,
		"PREMISE: both fixture chests must place (%s / %s)"
			% [str(chest_ok), str(chest2_ok)])

	# =========================================================================
	# (C) REACHABILITY CONTROL — a case that AGREED even before the fix.
	#
	# Read this first. It is here so the silence of (A) and (B) means
	# something: if the harness were not reaching the predicate at all, this
	# case would fail too. An inserter accepts Overlay.NONE, so bare grass is
	# legal for it AND carries no `tiles` entry — the one combination where
	# the old predicate happened to be right.
	# =========================================================================
	_check(failures, world.can_place_building(Buildings.Type.INSERTER, GRASS_1x1),
		"(C) PREMISE: an inserter must be placeable on bare grass: %s"
			% world.last_building_place_error)
	_check(failures, not world.hover_preview_blocked(Buildings.Type.INSERTER, GRASS_1x1),
		"(C) CONTROL: inserter on bare grass is legal and must preview FREE — "
		+ "if this fails the harness is not reaching the predicate and (A)/(B) prove nothing")

	# =========================================================================
	# (A) DIRECTION ONE — legal placement, previewed RED.
	# Every one of these was measured red before the fix.
	# =========================================================================
	_agree(failures, world, "(A1) belt on stone", Buildings.Type.BELT, STONE_1x1, true)
	_agree(failures, world, "(A2) oven on a paved 2x2", Buildings.Type.OVEN, STONE_2x2, true)
	# Type-specific rule the old predicate could not see: Pump needs water
	# ADJACENT, and this tile has it.
	_agree(failures, world, "(A3) pump on stone beside water",
		Buildings.Type.PUMP, STONE_BY_WATER, true)
	# ...and the drill's ore EXEMPTION: an ore tile is a `tiles` entry, so the
	# old predicate called the drill's only legal ground blocked.
	_agree(failures, world, "(A4) mining drill on its ore deposit",
		Buildings.Type.MINING_DRILL, ORE_2x2, true)

	# =========================================================================
	# (B) DIRECTION TWO — illegal placement, previewed FREE.
	# =========================================================================
	_agree(failures, world, "(B1) belt on bare grass", Buildings.Type.BELT, GRASS_1x1, false)
	_agree(failures, world, "(B2) oven on a bare 2x2", Buildings.Type.OVEN, GRASS_2x2, false)
	# Type-specific rule, other direction: no ore anywhere in the footprint.
	_agree(failures, world, "(B3) mining drill on bare grass with no ore",
		Buildings.Type.MINING_DRILL, GRASS_DRILL, false)

	# =========================================================================
	# (R) RETENTION — what the OLD predicate got right must still be true.
	# These agreed before the fix and must agree after it. They are the half
	# of the change that a delegation could silently drop.
	# =========================================================================
	_agree(failures, world, "(R1) belt onto an occupied tile",
		Buildings.Type.BELT, STONE_CHEST, false)
	_agree(failures, world, "(R2) oven whose FAR footprint corner is occupied",
		Buildings.Type.OVEN, STONE_2x2_BLOCKED, false)
	_agree(failures, world, "(R3) pump on stone with no water in reach",
		Buildings.Type.PUMP, STONE_DRY, false)
	# Water carries a `tiles` entry, so the old predicate reddened it for the
	# right answer by the wrong reason. It must stay red for the right one.
	_agree(failures, world, "(R4) belt on water", Buildings.Type.BELT, WATER, false)

	# =========================================================================
	# (N) THE NEUTRAL BRANCH — `building_type < 0`.
	#
	# With nothing held, the hover rect outlines an EXISTING building so the
	# player can see a 2x2's whole footprint. That is not a placement intent
	# and has no blocked state: it must NEVER be red, and must NEVER reach the
	# placement rule at all.
	#
	# ⚠ N1-N4 ARE NOT SUFFICIENT ON THEIR OWN AND N5 IS NOT OPTIONAL. Measured:
	# with the `building_type < 0` guard deleted, N1-N4 all still PASS. The
	# fall-through faults twice per call — `Buildings.requires_overlay(-1)` and
	# `Buildings.footprint_of(-1)` are both out-of-bounds Dictionary reads — and
	# GDScript's aborted-function default hands `_footprint_cells` back an empty
	# Array, so `can_place_building` walks over nothing and returns TRUE. The
	# preview then reads `not true` = false, which is the right answer arrived
	# at by crashing twice. The only visible trace is 8 `SCRIPT ERROR` lines in
	# the run log, which no assertion here reads.
	#
	# N5 asserts the mechanism instead of the answer: a NEUTRAL hover must not
	# CONSULT the placement rule. `can_place_building` clears
	# `last_building_place_error` on its first line, so a surviving sentinel is
	# proof the guard returned before delegating.
	# =========================================================================
	_check(failures, not world.hover_preview_blocked(-1, STONE_CHEST),
		"(N1) NEUTRAL hover over an existing building must not preview blocked")
	_check(failures, not world.hover_preview_blocked(-1, STONE_1x1),
		"(N2) NEUTRAL hover over a paved empty tile must not preview blocked")
	_check(failures, not world.hover_preview_blocked(-1, WATER),
		"(N3) NEUTRAL hover over water must not preview blocked")
	_check(failures, not world.hover_preview_blocked(-1, FAR_EMPTY),
		"(N4) NEUTRAL hover over untouched grass must not preview blocked")
	var sentinel: String = "sentinel: no neutral hover may reach the placement rule"
	for neutral_pos in [STONE_CHEST, STONE_1x1, WATER, FAR_EMPTY]:
		world.last_building_place_error = sentinel
		world.hover_preview_blocked(-1, neutral_pos)
		_check(failures, world.last_building_place_error == sentinel,
			("(N5) NEUTRAL hover at %s reached can_place_building — the type < 0 guard "
			+ "is gone. It returns the right colour only by faulting twice per call; "
			+ "error string was '%s'") % [str(neutral_pos), world.last_building_place_error])

	# =========================================================================
	# (S) THE INVARIANT, SWEPT. The point of the fix is that preview and
	# placement cannot disagree BY CONSTRUCTION, so assert exactly that over
	# every type x every fixture cell rather than only over the cases someone
	# thought of. This is the assertion that catches a HALF-delegation — one
	# that wires up one direction and leaves the other reading `tiles`.
	# =========================================================================
	var disagreements: Array = []
	for t in [Buildings.Type.BELT, Buildings.Type.INSERTER, Buildings.Type.OVEN,
			Buildings.Type.MINING_DRILL, Buildings.Type.PUMP, Buildings.Type.CHEST,
			Buildings.Type.POWER_POLE, Buildings.Type.SMELTER]:
		for pos in SWEEP_POSITIONS:
			var legal: bool = world.can_place_building(t, pos)
			var blocked: bool = world.hover_preview_blocked(t, pos)
			if blocked == legal:
				disagreements.append("%s@%s (can_place=%s, preview_blocked=%s)"
					% [Buildings.name_of(t), str(pos), str(legal), str(blocked)])
	_check(failures, disagreements.is_empty(),
		"(S) preview must equal NOT can_place_building for every type x cell; %d disagreed: %s"
			% [disagreements.size(), "; ".join(disagreements.slice(0, 6))])

	# =========================================================================
	# (E) WHY THERE IS NO last_building_place_error SAVE/RESTORE.
	#
	# The audit's fix text wrapped the delegation in a save/restore because
	# `_draw` now calls `can_place_building` every frame and clobbers the
	# string. It is NOT needed, and the reason is a timing property, not a
	# preference: all three production readers consume the string in the same
	# synchronous call as the failed placement that set it
	# (`main.gd` `_try_place`, `console.gd` `_cmd_place` twice), so no frame —
	# and therefore no `_draw` — can interleave.
	#
	# (E1) pins the interleaving behaviourally: a hover query immediately
	# before a failed placement must not corrupt that placement's reason.
	# (E2) pins the PREMISE the determination rests on, which is the part that
	# can rot: if a future edit makes any reader's function a coroutine, a
	# frame CAN intervene and the save/restore stops being optional. That is
	# the condition, so that is what is asserted.
	# =========================================================================
	world.hover_preview_blocked(Buildings.Type.BELT, STONE_1x1)   # legal: clears the string
	var placed: bool = world.place_building(Buildings.Type.BELT, GRASS_1x1)
	_check(failures, not placed,
		"(E1) PREMISE: a belt on bare grass must be refused")
	_check(failures, "needs" in world.last_building_place_error.to_lower(),
		"(E1) a failed placement must still report its own reason after a hover query; got '%s'"
			% world.last_building_place_error)
	for reader in ["res://scripts/main.gd", "res://scripts/ui/console.gd"]:
		var bad: Array = _coroutine_readers(reader)
		_check(failures, bad.is_empty(),
			("(E2) %s: every function reading last_building_place_error must be "
			+ "synchronous, or hover_preview_blocked needs a save/restore. Coroutines: %s")
				% [reader, ", ".join(bad)])

	_disconnect(world)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message":
			"preview == NOT can_place over 8 types x 12 cells; both #16 directions pinned, "
			+ "neutral branch and both error-string premises hold" }
	return { "ok": false, "message": "%d failures: %s"
		% [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

## Assert BOTH halves of one cell: that `can_place_building` says what the case
## claims, and that the preview agrees with it.
##
## The `expect_legal` premise is not decoration. Without it a case that stopped
## exercising its mechanism — an oven that became NONE-accepting, an ore fixture
## that stopped being ore — would keep passing while testing nothing, which is
## this project's named silent-compensation shape.
static func _agree(failures: Array, world, label: String, t: int, pos: Vector2i,
		expect_legal: bool) -> void:
	var legal: bool = world.can_place_building(t, pos)
	var err: String = world.last_building_place_error
	if legal != expect_legal:
		failures.append("%s PREMISE: expected can_place=%s, got %s (%s)"
			% [label, str(expect_legal), str(legal), err])
		return
	var blocked: bool = world.hover_preview_blocked(t, pos)
	if blocked == legal:
		failures.append("%s: can_place=%s but preview_blocked=%s — preview %s"
			% [label, str(legal), str(blocked),
				"REDDENS a legal placement" if legal else "FREES an illegal placement"])

## Names of functions in `path` that both read `last_building_place_error` and
## contain an `await`. Function bodies are delimited by top-level `func ` lines,
## which is exactly how both files are written.
static func _coroutine_readers(path: String) -> Array:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ["<could not open %s>" % path]
	var out: Array = []
	var current: String = "<file scope>"
	var reads: bool = false
	var awaits: bool = false
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.begins_with("func ") or line.begins_with("static func "):
			if reads and awaits:
				out.append(current)
			current = line.strip_edges()
			reads = false
			awaits = false
			continue
		if "last_building_place_error" in line:
			reads = true
		# `await` as a statement or an expression, never as part of a word.
		if line.strip_edges().begins_with("await ") or " await " in line:
			awaits = true
	if reads and awaits:
		out.append(current)
	f.close()
	return out

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
