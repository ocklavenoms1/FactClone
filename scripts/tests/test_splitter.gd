extends RefCounted

## Belt Logistics Session 1, Task 3 — SPLITTER CORE (the Q11 set for the core).
##
## The locked design under test (docs/scoping/belt-logistics-1.md):
##   - ONE belt-tile-equivalent internal lane (`state["slots"]`, length
##     Belt.SLOTS_PER_TILE), advancing only on `Belt.is_advance_tick()`.
##     Pass 1 (`Splitter.tick`) is a self-only shift; Pass 2
##     (`Splitter.post_tick`) is the handoff. The LATENCY IS LOCKED (user,
##     2026-08-26): a splitter costs exactly one belt tile of travel time, so
##     `belt → splitter → belt` walks the SAME resting positions as three
##     belts. Sub-case (B) pins that with the same literal path test_belt.gd
##     uses, and its assertion message names the lock.
##   - Round-robin via `state["next_out"]` (0 = LEFT branch, 1 = RIGHT),
##     toggled ONLY on successful delivery; refusals leave it unchanged, so
##     all-to-open falls out with zero extra state. Sub-cases (A) and (C).
##   - #14-style feeder guard: never deliver into a belt whose dir points
##     into the splitter's footprint. Sub-case (E), with the input-edge
##     refusals in (E2).
##   - `next_out` RESUMES across save/load (the Q2 decision). Sub-case (F).
##
## GEOMETRY USED THROUGHOUT (the module-header convention, restated so the
## literals below are readable): dir = FLOW direction, same enum as BELT. At
## dir = DIR_E the footprint is (2, 1): REAR/INPUT cell = anchor, FRONT cell =
## anchor + (1, 0). Items enter ONLY through the input edge (the rear cell's
## edge opposite the flow — W at canonical) and leave through the FRONT
## cell's two side edges: LEFT of flow (N at canonical) and RIGHT (S).
##
## The fixture line, used by every sub-case:
##
##       (11,9)  L branch belt          global slots 8..11 in (B)
##   (9,10)(10,10)(11,10)               U belt 0..3 → lane 4..7
##       (11,11) R branch belt
##
## U belt at (9,10) DIR_E feeds the splitter anchored (10,10) dir E through
## its input edge; branch belts sit on the two branch cells flowing AWAY.
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. Nothing here asks Splitter (or Belt)
## for its own expectation; due-tick arithmetic is derived from
## `TickSystem.current_tick / Belt.TICKS_PER_SLOT` exactly as test_belt.gd
## does — never from `Splitter.*` or `Belt.is_advance_tick()` (the M4
## lesson: an expectation computed by the code under test moves with it).
##
## ⚠ ARRIVAL ORDER IS READ OFF THE BELT, NOT LOGGED. Items on a no-consumer
## belt compress onto the head slots, so slot order IS reverse arrival
## order: first arrival at the front slot (3), second at 2, third at 1.
## The per-branch "labelled sequence" literals below are whole slots-array
## equalities, which pin count, types AND order in one comparison.
##
## REACHABILITY CONTROLS. As in test_belt.gd, every sub-case carries an
## assertion a dead (or never-delivering) splitter FAILS — items must
## actually arrive at branch ends — so "nothing crossed" can never read as
## "the guard worked".

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

const TEST_SAVE_PATH: String = "user://test_splitter.json"

## Resting positions of one item over U belt → lane → L branch belt, by
## advance-tick index — THE SAME LITERAL as test_belt.gd's EXPECTED_PATH,
## because the lane is one belt-tile-equivalent (the locked latency
## decision). Global index: U slot s = s, lane slot s = 4 + s, branch belt
## slot s = 8 + s. Derived from the two passes (Pass 1 shifts one slot,
## Pass 2 of the SAME tick empties a front slot across a boundary), not
## copied from a run: global slots 3 and 7 are boundary front slots and are
## never resting positions.
const EXPECTED_PATH: Array = [0, 1, 2, 4, 5, 6, 8, 9, 10, 11]

## Six distinct item types used as arrival-order labels 1..6 in (A)/(D).
const LABELS: Array = [
	Items.Type.GRAIN,    # item 1
	Items.Type.FLOUR,    # item 2
	Items.Type.WHEAT,    # item 3
	Items.Type.STRAW,    # item 4
	Items.Type.COAL,     # item 5
	Items.Type.WOOD,     # item 6
]

static func test_name() -> String:
	return "splitter core (locked lane, labelled round-robin, all-to-open, conservation, feeder guard, next_out resume)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_a_round_robin_labelled(parent, failures)
	_case_b_trajectory(parent, failures)
	_case_c_all_to_open(parent, failures)
	_case_d_conservation(parent, failures)
	_case_e_feeder_guard(parent, failures)
	_case_f_next_out_resume(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 24))] }

# ---------- fixture ----------

## Paves and places the standard line. `l_dir`/`r_dir` are the branch belts'
## directions (DIR_N / DIR_S flow away; a branch belt pointed INTO the
## splitter is sub-case (E)'s adversary). Returns
## { u, sp, l, r } or empty on placement failure.
static func _build_line(world, failures: Array, tag: String, l_dir: int, r_dir: int) -> Dictionary:
	for cell in [Vector2i(9, 10), Vector2i(10, 10), Vector2i(11, 10),
			Vector2i(11, 9), Vector2i(11, 11)]:
		if not world.set_overlay(cell, Terrain.Overlay.STONE):
			_check(failures, false, "%s PREMISE: could not pave %s" % [tag, str(cell)])
			return {}
	if not world.place_building(Buildings.Type.BELT, Vector2i(9, 10), Belt.DIR_E):
		_check(failures, false, "%s PREMISE: U belt placement failed" % tag)
		return {}
	if not world.place_building(Buildings.Type.SPLITTER, Vector2i(10, 10), Belt.DIR_E):
		_check(failures, false, "%s PREMISE: splitter placement failed: %s"
			% [tag, str(world.last_building_place_error)])
		return {}
	if not world.place_building(Buildings.Type.BELT, Vector2i(11, 9), l_dir):
		_check(failures, false, "%s PREMISE: L branch belt placement failed" % tag)
		return {}
	if not world.place_building(Buildings.Type.BELT, Vector2i(11, 11), r_dir):
		_check(failures, false, "%s PREMISE: R branch belt placement failed" % tag)
		return {}
	return {
		"u": world.building_at(Vector2i(9, 10)),
		"sp": world.building_at(Vector2i(10, 10)),
		"l": world.building_at(Vector2i(11, 9)),
		"r": world.building_at(Vector2i(11, 11)),
	}

# ===========================================================================
# (A) ROUND-ROBIN, LABELLED. Two items alternating is coincidence at n = 2,
# so this feeds SIX items of six distinct types (type = arrival-order label)
# and asserts the FULL per-branch sequence as a whole-array literal. A
# stuck-on-one-output splitter, an always-L splitter and a random splitter
# each produce a different pair of arrays; none produces this pair.
# next_out starts 0 = LEFT, so L gets items 1, 3, 5 and R gets 2, 4, 6.
# ===========================================================================
static func _case_a_round_robin_labelled(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var line: Dictionary = _build_line(world, failures, "(A)", Belt.DIR_N, Belt.DIR_S)
	if line.is_empty():
		_cleanup(world)
		return
	TickSystem.current_tick = 0

	var fed: int = 0
	for _t in 240:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < LABELS.size() and Belt.try_insert(line["u"], int(LABELS[fed])):
			fed += 1
	_check(failures, fed == 6, "(A) PREMISE: expected to feed 6 labelled items, fed %d" % fed)

	# The labelled per-branch sequences, as whole-array literals. Slot order
	# is reverse arrival order (head-compressed), so L = [_, 5, 3, 1] and
	# R = [_, 6, 4, 2] by label.
	_check(failures, _slots_of(line["l"]) == [-1, Items.Type.COAL, Items.Type.WHEAT, Items.Type.GRAIN],
		"(A) L branch must hold exactly items 5, 3, 1 (COAL, WHEAT, GRAIN toward the front) — got %s. A stuck next_out, an always-one-side splitter, or a random pick each breaks this literal"
			% str(_slots_of(line["l"])))
	_check(failures, _slots_of(line["r"]) == [-1, Items.Type.WOOD, Items.Type.STRAW, Items.Type.FLOUR],
		"(A) R branch must hold exactly items 6, 4, 2 (WOOD, STRAW, FLOUR toward the front) — got %s"
			% str(_slots_of(line["r"])))

	# REACHABILITY CONTROL: all six items reached the branch ends — nothing
	# is still in transit, so the literals above compared finished state.
	_check(failures, _occupied_count([line["u"], line["sp"]]) == 0,
		"(A) REACHABILITY CONTROL: U belt + lane must be empty once all six items have crossed, %d item(s) still in transit"
			% _occupied_count([line["u"], line["sp"]]))
	_check(failures, _occupied_count([line["l"], line["r"]]) == 6,
		"(A) REACHABILITY CONTROL: all 6 items must be on the branch belts, found %d"
			% _occupied_count([line["l"], line["r"]]))
	_cleanup(world)

# ===========================================================================
# (B) TRAJECTORY THROUGH THE SPLITTER. One item, ticks driven one at a time,
# exact occupied-slot assertion per tick against EXPECTED_PATH — the same
# literal shape as three belts, which is precisely the locked lane decision.
# Front-slot transience is inside the literal: global 3 (U front) and 7
# (lane front) never appear as resting positions.
# ===========================================================================
static func _case_b_trajectory(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var line: Dictionary = _build_line(world, failures, "(B)", Belt.DIR_N, Belt.DIR_S)
	if line.is_empty():
		_cleanup(world)
		return
	TickSystem.current_tick = 0

	# next_out starts 0 = LEFT, so the single item exits onto the L belt:
	# the walked chain is U (0..3) → lane (4..7) → L branch (8..11).
	var chain: Array = [line["u"], line["sp"], line["l"]]
	_check(failures, Belt.try_insert(line["u"], Items.Type.GRAIN),
		"(B) try_insert refused an empty U belt")
	_check(failures, _occupied(chain) == [0],
		"(B) item should start at global slot 0, got %s" % str(_occupied(chain)))

	for _t in 80:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		# Expected position indexed by WORLD ticks over TICKS_PER_SLOT — the
		# arithmetic source the M4 mutation cannot reach. Phase is 0 here.
		var due: int = TickSystem.current_tick / Belt.TICKS_PER_SLOT
		var expected: int = int(EXPECTED_PATH[mini(due, EXPECTED_PATH.size() - 1)])
		var occ: Array = _occupied(chain)
		_check_once(failures, "(B)path",
			occ == [expected],
			"(B) tick %d: expected exactly [%d], got %s — belt → splitter → belt must walk the SAME resting positions as three belts because the lane is ONE belt-tile-equivalent (the LOCKED latency decision); a zero-latency pass-through or a double-shift reddens here"
				% [TickSystem.current_tick, expected, str(occ)])

	# REACHABILITY CONTROL: a line that never advances (or a splitter that
	# never accepts / never delivers) leaves the item short of global 11.
	_check(failures, _occupied(chain) == [11],
		"(B) REACHABILITY CONTROL: the item must park at the L branch's front (global slot 11), got %s"
			% str(_occupied(chain)))
	# Nothing may have leaked onto the R branch on the way past.
	_check(failures, _occupied_count([line["r"]]) == 0,
		"(B) the single item exits LEFT (next_out starts 0); the R branch must stay empty, got %d item(s)"
			% _occupied_count([line["r"]]))
	_cleanup(world)

# ===========================================================================
# (C) ALL-TO-OPEN. Policy (module header): next_out is the branch tried
# FIRST; it flips on every successful delivery whichever branch accepted; a
# refusal leaves it unchanged. Jam the R branch: all four labelled items
# arrive on L, exact count and types, R's jam load untouched. After 4
# deliveries next_out has flipped 4 times from 0 → it is 0 again, so once
# both branches are cleared the next item goes LEFT, then RIGHT — the
# literal next-branch expectation that also pins the policy (the
# alternative "prefer the branch the last item did NOT take" policy would
# send the post-jam item RIGHT and redden here).
# ===========================================================================
static func _case_c_all_to_open(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var line: Dictionary = _build_line(world, failures, "(C)", Belt.DIR_N, Belt.DIR_S)
	if line.is_empty():
		_cleanup(world)
		return
	TickSystem.current_tick = 0

	# Jam the R branch: every slot full of COAL, no downstream, so nothing
	# drains and every delivery attempt at R refuses.
	var r_slots: Array = line["r"].state["slots"]
	for i in Belt.SLOTS_PER_TILE:
		r_slots[i] = Items.Type.COAL

	var fed: int = 0
	for _t in 240:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < 4 and Belt.try_insert(line["u"], int(LABELS[fed])):
			fed += 1
	_check(failures, fed == 4, "(C) PREMISE: expected to feed 4 items, fed %d" % fed)

	_check(failures, _slots_of(line["l"]) == [Items.Type.STRAW, Items.Type.WHEAT, Items.Type.FLOUR, Items.Type.GRAIN],
		"(C) with R jammed, ALL FOUR items must arrive on L in order (STRAW, WHEAT, FLOUR, GRAIN toward the front), got %s"
			% str(_slots_of(line["l"])))
	_check(failures, _slots_of(line["r"]) == [Items.Type.COAL, Items.Type.COAL, Items.Type.COAL, Items.Type.COAL],
		"(C) the jammed R branch must still hold exactly its four COAL — a delivery into a full belt, or a lost jam item, breaks this: %s"
			% str(_slots_of(line["r"])))
	_check(failures, _occupied_count([line["u"], line["sp"]]) == 0,
		"(C) REACHABILITY CONTROL: U belt + lane must have drained onto the open branch, %d item(s) stuck"
			% _occupied_count([line["u"], line["sp"]]))

	# Unjam: clear BOTH branch belts, then feed two more items. next_out is 0
	# (four flips from 0), so item 5 goes LEFT, item 6 RIGHT.
	var l_slots: Array = line["l"].state["slots"]
	for i in Belt.SLOTS_PER_TILE:
		l_slots[i] = -1
		r_slots[i] = -1
	fed = 0
	for _t in 160:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < 2 and Belt.try_insert(line["u"], int(LABELS[4 + fed])):
			fed += 1
	_check(failures, fed == 2, "(C) PREMISE: expected to feed 2 post-unjam items, fed %d" % fed)
	_check(failures, _slots_of(line["l"]) == [-1, -1, -1, Items.Type.COAL],
		"(C) first post-unjam item must go LEFT (next_out flipped an even number of times during the jam; refusals changed nothing), got %s"
			% str(_slots_of(line["l"])))
	_check(failures, _slots_of(line["r"]) == [-1, -1, -1, Items.Type.WOOD],
		"(C) second post-unjam item must go RIGHT — alternation resumed, got %s"
			% str(_slots_of(line["r"])))
	_cleanup(world)

# ===========================================================================
# (D) CONSERVATION. Exact occupied-count across the WHOLE layout (belts +
# splitter lane) after every insert and after every tick — never fewer
# (vanished at a handoff), never more (duplicated). The test_belt.gd case
# (4) counting pattern extended to read the splitter's lane: reading state
# to compare against the fed count is legitimate; computing the expectation
# from it would not be.
# ===========================================================================
static func _case_d_conservation(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var line: Dictionary = _build_line(world, failures, "(D)", Belt.DIR_N, Belt.DIR_S)
	if line.is_empty():
		_cleanup(world)
		return
	TickSystem.current_tick = 0

	var everything: Array = [line["u"], line["sp"], line["l"], line["r"]]
	var fed: int = 0
	for _t in 240:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(D)conserve-tick",
			_occupied_count(everything) == fed,
			"(D) conservation broke across tick %d: %d fed, %d on the layout"
				% [TickSystem.current_tick, fed, _occupied_count(everything)])
		if fed < LABELS.size() and Belt.try_insert(line["u"], int(LABELS[fed])):
			fed += 1
		_check_once(failures, "(D)conserve-insert",
			_occupied_count(everything) == fed,
			"(D) conservation broke after an insert at tick %d: %d fed, %d on the layout"
				% [TickSystem.current_tick, fed, _occupied_count(everything)])

	_check(failures, fed == 6, "(D) PREMISE: expected to feed 6 items, fed %d" % fed)
	# REACHABILITY CONTROL: conservation alone is satisfied by a frozen line.
	_check(failures, _occupied_count([line["l"], line["r"]]) == 6,
		"(D) REACHABILITY CONTROL: all 6 items must end on the branch belts, found %d"
			% _occupied_count([line["l"], line["r"]]))
	_cleanup(world)

# ===========================================================================
# (E) FEEDER GUARD + INPUT-EDGE REFUSALS.
#
# (E1) A belt on the L branch cell pointed INTO the splitter (DIR_S, into
# the front cell) is a FEEDER, not a sink — the #14 rule, processor.gd's
# `_belt_feeds_building` mirrored. It must NEVER be delivered to, asserted
# every tick; with R open, every item lands R (all-to-open through the
# guard). The every-tick form matters: an item delivered L and later moved
# would leave the end state clean.
#
# (E2) The input edge is the ONLY way in. A belt side-feeding the rear cell
# from the N, and a belt pushing into the FRONT cell head-on from the E,
# must both be refused — their items park on their own front slots. The
# reachability control for this geometry is every other sub-case: the same
# splitter accepts U's items through the real input edge.
# ===========================================================================
static func _case_e_feeder_guard(parent: Node, failures: Array) -> void:
	# --- (E1) branch belt pointed into the splitter ---
	var world = _make_world(parent)
	# L branch belt DIR_S: points at the front cell (11,10).
	var line: Dictionary = _build_line(world, failures, "(E1)", Belt.DIR_S, Belt.DIR_S)
	if line.is_empty():
		_cleanup(world)
		return
	TickSystem.current_tick = 0

	var fed: int = 0
	for _t in 240:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(E1)guard",
			_occupied_count([line["l"]]) == 0,
			"(E1) the splitter delivered onto a belt pointing INTO its footprint at tick %d — the #14 feeder guard did not fire"
				% TickSystem.current_tick)
		if fed < 3 and Belt.try_insert(line["u"], int(LABELS[fed])):
			fed += 1
	_check(failures, fed == 3, "(E1) PREMISE: expected to feed 3 items, fed %d" % fed)
	_check(failures, _slots_of(line["r"]) == [-1, Items.Type.WHEAT, Items.Type.FLOUR, Items.Type.GRAIN],
		"(E1) REACHABILITY CONTROL: with L refused by the guard, all 3 items must arrive on R (WHEAT, FLOUR, GRAIN toward the front), got %s"
			% str(_slots_of(line["r"])))
	_cleanup(world)

	# --- (E2) wrong-edge feeders are refused ---
	var world2 = _make_world(parent)
	for cell in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 9), Vector2i(12, 10)]:
		if not world2.set_overlay(cell, Terrain.Overlay.STONE):
			_check(failures, false, "(E2) PREMISE: could not pave %s" % str(cell))
			_cleanup(world2)
			return
	if not world2.place_building(Buildings.Type.SPLITTER, Vector2i(10, 10), Belt.DIR_E):
		_check(failures, false, "(E2) PREMISE: splitter placement failed")
		_cleanup(world2)
		return
	# Side-feeder: N of the REAR cell, pointing S into it — not the input edge.
	if not world2.place_building(Buildings.Type.BELT, Vector2i(10, 9), Belt.DIR_S):
		_check(failures, false, "(E2) PREMISE: side belt placement failed")
		_cleanup(world2)
		return
	# Head-on feeder: E of the FRONT cell, pointing W into it.
	if not world2.place_building(Buildings.Type.BELT, Vector2i(12, 10), Belt.DIR_W):
		_check(failures, false, "(E2) PREMISE: head-on belt placement failed")
		_cleanup(world2)
		return
	var sp2: Building = world2.building_at(Vector2i(10, 10))
	var side: Building = world2.building_at(Vector2i(10, 9))
	var head: Building = world2.building_at(Vector2i(12, 10))
	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(side, Items.Type.GRAIN), "(E2) side belt refused GRAIN")
	_check(failures, Belt.try_insert(head, Items.Type.FLOUR), "(E2) head-on belt refused FLOUR")
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(E2)lane",
			_occupied_count([sp2]) == 0,
			"(E2) an item entered the lane through a NON-INPUT edge at tick %d — the input-edge rule did not fire"
				% TickSystem.current_tick)
	var front: int = Belt.SLOTS_PER_TILE - 1
	_check(failures, _slots_of(side)[front] == Items.Type.GRAIN,
		"(E2) REACHABILITY CONTROL: the side belt advanced and parked its GRAIN on its own front slot (refused, visible backpressure), got %s"
			% str(_slots_of(side)))
	_check(failures, _slots_of(head)[front] == Items.Type.FLOUR,
		"(E2) REACHABILITY CONTROL: the head-on belt parked its FLOUR on its own front slot, got %s"
			% str(_slots_of(head)))
	_cleanup(world2)

# ===========================================================================
# (F) NEXT_OUT RESUMES ACROSS SAVE/LOAD — the Q2 decision's minimal
# behavioural pin (the full round-trip suite is Task 6). Drive exactly ONE
# delivery (next_out 0 → 1), save to a FIXTURE path, load, and assert both
# the literal state and the literal behaviour: the next item goes RIGHT. A
# load that resets next_out to 0 sends it LEFT and reddens both.
# ===========================================================================
static func _case_f_next_out_resume(parent: Node, failures: Array) -> void:
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	_case_f_body(parent, failures)

	SaveSystem.save_path = orig_path
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

static func _case_f_body(parent: Node, failures: Array) -> void:
	var world_a = _make_world(parent)
	var line: Dictionary = _build_line(world_a, failures, "(F)", Belt.DIR_N, Belt.DIR_S)
	if line.is_empty():
		_cleanup(world_a)
		return
	TickSystem.current_tick = 0

	# One item, one delivery: it exits LEFT and next_out flips 0 → 1.
	_check(failures, Belt.try_insert(line["u"], Items.Type.GRAIN), "(F) U belt refused GRAIN")
	for _t in 60:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, _slots_of(line["l"]) == [-1, -1, -1, Items.Type.GRAIN],
		"(F) PREMISE: the single item must have been delivered LEFT before saving, L is %s"
			% str(_slots_of(line["l"])))
	_check(failures, int(line["sp"].state.get("next_out", -99)) == 1,
		"(F) PREMISE: one delivery must leave next_out at the literal 1, got %s"
			% str(line["sp"].state.get("next_out", "<absent>")))

	var player_a := Node2D.new()
	parent.add_child(player_a)
	var inv_a: Inventory = Inventory.new(16)
	var saved: bool = SaveSystem.save_game(world_a, player_a, inv_a)
	player_a.queue_free()
	_cleanup(world_a)
	if not saved:
		_check(failures, false, "(F) PREMISE: save_game returned false")
		return

	var world_b = _make_world(parent)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b: Inventory = Inventory.new(16)
	var result = SaveSystem.load_game(world_b, player_b, inv_b)
	player_b.queue_free()
	if not bool(result.success):
		_check(failures, false, "(F) PREMISE: load_game failed: %s" % str(result.error_message))
		_cleanup(world_b)
		return
	var sp_b: Building = world_b.building_at(Vector2i(10, 10))
	if sp_b == null or sp_b.type != Buildings.Type.SPLITTER:
		_check(failures, false, "(F) PREMISE: the splitter did not reload at (10,10)")
		_cleanup(world_b)
		return
	_check(failures, int(sp_b.state.get("next_out", -99)) == 1,
		"(F) next_out must RESUME as the literal 1 across save/load (the Q2 decision), got %s"
			% str(sp_b.state.get("next_out", "<absent>")))

	# The behavioural half: the next item goes RIGHT.
	var u_b: Building = world_b.building_at(Vector2i(9, 10))
	var r_b: Building = world_b.building_at(Vector2i(11, 11))
	TickSystem.current_tick = 0
	_check(failures, u_b != null and Belt.try_insert(u_b, Items.Type.FLOUR),
		"(F) reloaded U belt refused FLOUR")
	for _t in 60:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, r_b != null and _slots_of(r_b) == [-1, -1, -1, Items.Type.FLOUR],
		"(F) the first post-load item must go RIGHT — a next_out reset on load sends it LEFT — R is %s"
			% (str(_slots_of(r_b)) if r_b != null else "<null>"))
	_cleanup(world_b)

# ---------- helpers ----------

## A building's slots array as plain ints, [] if it has none (yet). Reading
## state to COMPARE against a literal is legitimate; the literals never come
## from here.
static func _slots_of(b: Building) -> Array:
	var out: Array = []
	if b == null:
		return out
	for s in b.state.get("slots", []):
		out.append(int(s))
	return out

## Global slot indices occupied across `chain` (belts and/or the splitter,
## each contributing SLOTS_PER_TILE slots in chain order), ascending.
static func _occupied(chain: Array) -> Array:
	var out: Array = []
	for i in chain.size():
		var slots: Array = _slots_of(chain[i])
		for s in slots.size():
			if int(slots[s]) >= 0:
				out.append(i * Belt.SLOTS_PER_TILE + s)
	return out

static func _occupied_count(chain: Array) -> int:
	return _occupied(chain).size()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Per-tick assertions run hundreds of times; `key` groups them so only the
## FIRST breach of each distinct assertion is reported.
static func _check_once(failures: Array, key: String, condition: bool, label: String) -> void:
	if condition:
		return
	for existing in failures:
		if String(existing).begins_with(key):
			return
	failures.append("%s %s" % [key, label])

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
