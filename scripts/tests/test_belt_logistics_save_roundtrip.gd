extends RefCounted

## Belt Logistics Session 1, Task 6 — SAVE ROUND-TRIP for SPLITTER and the
## UNDERGROUND pair. Three hazards, each from this project's own findings
## (docs/scoping/belt-logistics-1.md Q2/Q8/Q10; the pole-tier session's
## test_mixed_tier_save_roundtrip.gd is the precedent for (1)):
##
##   (1) ENUM-INTEGER PINNING. All three new types are tail-appends, and the
##       integer written to disk IS the compatibility surface with saves this
##       binary did not write. Inside one binary there is no behavioural form
##       of the assertion — save_game and load_game read the same enum, so a
##       reordered enum agrees with itself everywhere. Only a literal can
##       disagree with a reorder. SAVE_VERSION is pinned here too (Q10's
##       no-bump claim, as a drift alarm).
##   (2) RESUME-NOT-RESET, in the save-at-N-continue-to-M form. Run a
##       trajectory to tick N, save, load into a FRESH world, continue to M:
##       the merged run must equal the uninterrupted literal — the same
##       arrays test_splitter.gd (A) and test_underground.gd (B) already pin.
##       (a) the splitter mid-alternation: next_out = 1 at save, and the
##       post-load labelled sequence CONTINUES the alternation. A reset
##       changes which belt every subsequent item lands on — a player
##       reports that as "my balancer broke after reload" and nobody traces
##       it to serialization. (b) the underground with items IN FLIGHT:
##       tunnel lanes mid-transit, arrival dues unchanged across the load —
##       possible because the "tick" field round-trips (save_game writes
##       TickSystem.current_tick; load_game restores it before rebuilding
##       the world — both asserted here as restored literals).
##   (3) PARTIAL OCCUPANCY. The pole-tier session found round-trip losing
##       partially-occupied state WITH THE SUITE GREEN — full and empty both
##       round-trip fine, the middle drops. Pinned explicitly: a gap-3
##       tunnel holding ONE item in its middle slot (others -1); an entry
##       whose own input slot is occupied while the tunnel is entirely
##       empty; a splitter lane with one item mid-lane. The assertions are
##       EXACT slot-array literals — position preserved, not just count. A
##       serialization that "compresses" away -1 entries keeps every count
##       and loses every position: the array literals redden where a
##       count-only assertion stays green.
##
## Plus the #11-guard interaction the design pass verified only in theory:
## a v18 save whose splitter/entry states LACK the new fields (`next_out`,
## `slots`, `tunnel` absent — a Task-1/2-era save, or a hand-edited one)
## loads with `.get()` defaults engaged — no skip, no crash, and the lazy
## defaults observably regrow on the first advance tick.
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. Nothing here asks Splitter,
## Underground, Belt or SaveSystem for its own expectation; due-tick
## arithmetic is TickSystem.current_tick / Belt.TICKS_PER_SLOT exactly as
## test_belt.gd derives it. The pinned type integers were re-derived from
## the enum by hand on 2026-08-27 and written down as numbers; a
## Buildings.Type.SPLITTER round-trip here would be the module confirming
## itself (protocol 3).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

const TEST_SAVE_PATH: String = "user://test_belt_logistics_save_roundtrip.json"

## The integers that are already sitting in players' save files from the
## moment this session ships. Mirrors test_mixed_tier_save_roundtrip.gd's
## PINNED_TYPE_INTS — see its sub-case (4) header for why literals are the
## only form of this assertion that can redden. A legitimate future APPEND
## changes none of these and needs no edit here.
const PINNED_TYPE_INTS: Array = [
	["SPLITTER", Buildings.Type.SPLITTER, 34],
	["UNDERGROUND_BELT_ENTRY", Buildings.Type.UNDERGROUND_BELT_ENTRY, 35],
	["UNDERGROUND_BELT_EXIT", Buildings.Type.UNDERGROUND_BELT_EXIT, 36],
]

## test_underground.gd's PATH24, restated: resting positions of one item over
## feeder belt → entry lane → gap-3 tunnel → downstream belt, by advance-tick
## index. Global index: feeder slot s = s, lane slot s = 4 + s, tunnel slot
## j = 8 + j, downstream slot s = 20 + s. Boundary front slots (every 4th
## global slot) are transient. Sub-case (2b) drives the SAME run test_
## underground.gd (B) pins — interrupted by a save/load at tick 48 — and
## the merged run must keep walking THIS array.
const PATH24: Array = [0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 16, 17, 18, 20, 21, 22, 23]

static func test_name() -> String:
	return "belt-logistics save round-trip (pinned type ints + SAVE_VERSION, splitter next_out resume at N→M, underground mid-flight tunnel resume, partial-occupancy literals, v18 save missing the new fields)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	var orig_tick: int = TickSystem.current_tick
	SaveSystem.save_path = TEST_SAVE_PATH
	_delete_fixture()

	_run_all(parent, failures)

	SaveSystem.save_path = orig_path
	TickSystem.current_tick = orig_tick
	_delete_fixture()

	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 24))] }

## Everything between the save_path swap and its restore. Split out so the
## restore in run() cannot be skipped by an early return in here.
static func _run_all(parent: Node, failures: Array) -> void:
	# First, because it needs no fixture and no world — a fixture that fails
	# to build cannot hide it behind an early return.
	_case_1_wire_format(failures)
	_delete_fixture()
	_case_2a_splitter_resume(parent, failures)
	_delete_fixture()
	_case_2b_underground_midflight(parent, failures)
	_delete_fixture()
	# (3) saves the fixture that (4) then hand-edits — keep them adjacent.
	_case_3_partial_occupancy_and_4_missing_fields(parent, failures)

# ===========================================================================
# (1) THE ON-DISK WIRE FORMAT: type integers and SAVE_VERSION, as literals.
#
# The three new types were APPENDED after SUBSTATION (pinned at 33 by the
# pole-tier suite), so every save written from today forward names them by
# these integers — forever. Verified the same way the precedent was: an
# insertion or reorder ahead of the tail shifts these and ONLY these
# assertions redden; the rest of the suite round-trips a reordered enum in
# perfect agreement with itself.
# ===========================================================================
static func _case_1_wire_format(failures: Array) -> void:
	for row in PINNED_TYPE_INTS:
		var label: String = String(row[0])
		var actual: int = int(row[1])
		var pinned: int = int(row[2])
		_check(failures, actual == pinned,
			"(1) Buildings.Type.%s is %d but the pinned wire integer is %d. A save written today must name this type by the same integer forever — the enum was reordered rather than appended to, and every existing save will reload this building as the wrong type with no version mismatch to catch it" % [label, actual, pinned])
	_check(failures, SaveSystem.SAVE_VERSION == 18,
		"(1) SAVE_VERSION must be the literal 18 (the Q10 no-schema-bump decision: append-only enum + .get()-defaulted flat state fields). It reads %d — if a bump was intended it must be a deliberate pass over this suite's fixtures and the design record, not a drift" % SaveSystem.SAVE_VERSION)

# ===========================================================================
# (2a) SPLITTER RESUME-NOT-RESET, save-at-N-continue-to-M. Feed three
# labelled items (deliveries L, R, L — next_out ends at the literal 1,
# mid-alternation), save at tick 140, load into a FRESH world, feed three
# more. The merged per-branch arrays must equal test_splitter.gd (A)'s
# uninterrupted six-item literals EXACTLY: L = [_, COAL, WHEAT, GRAIN],
# R = [_, WOOD, STRAW, FLOUR]. A load that resets next_out (or drops it from
# state so the .get() default engages) sends item 4 LEFT instead of RIGHT
# and every subsequent item lands on the wrong belt.
# ===========================================================================
static func _case_2a_splitter_resume(parent: Node, failures: Array) -> void:
	var world_a = _make_world(parent)
	var line: Dictionary = _build_splitter_line(world_a, failures, "(2a)")
	if line.is_empty():
		_cleanup(world_a)
		return
	TickSystem.current_tick = 0

	# Phase 1 — items 1..3: GRAIN → L, FLOUR → R, WHEAT → L.
	var fed: int = 0
	var labels: Array = [Items.Type.GRAIN, Items.Type.FLOUR, Items.Type.WHEAT]
	for _t in 140:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < 3 and Belt.try_insert(line["u"], int(labels[fed])):
			fed += 1
	_check(failures, fed == 3, "(2a) PREMISE: expected to feed 3 items before the save, fed %d" % fed)
	_check(failures, _slots_of(line["l"]) == [-1, -1, Items.Type.WHEAT, Items.Type.GRAIN],
		"(2a) PREMISE: before the save L must hold items 1 and 3 (WHEAT, GRAIN toward the front), got %s"
			% str(_slots_of(line["l"])))
	_check(failures, _slots_of(line["r"]) == [-1, -1, -1, Items.Type.FLOUR],
		"(2a) PREMISE: before the save R must hold item 2 (FLOUR at the front), got %s"
			% str(_slots_of(line["r"])))
	_check(failures, int(line["sp"].state.get("next_out", -99)) == 1,
		"(2a) PREMISE: three deliveries flip next_out 0→1→0→1 — it must be the literal 1 (MID-alternation) at the save, got %s"
			% str(line["sp"].state.get("next_out", "<absent>")))

	if not _save_ok(parent, world_a, failures, "(2a)"):
		_cleanup(world_a)
		return
	_cleanup(world_a)

	# Fresh world; load. current_tick was 140 at the save and must come back
	# as 140 — save_game writes the "tick" field from TickSystem.current_tick
	# and load_game restores it (the Q2 enabler; see also (2b)).
	var world_b = _make_world(parent)
	if _load_into(parent, world_b, failures, "(2a)") == null:
		_cleanup(world_b)
		return
	_check(failures, TickSystem.current_tick == 140,
		"(2a) the saved tick was the literal 140 and load_game must restore it, got %d" % TickSystem.current_tick)
	var sp_b: Building = world_b.building_at(Vector2i(10, 10))
	var u_b: Building = world_b.building_at(Vector2i(9, 10))
	var l_b: Building = world_b.building_at(Vector2i(11, 9))
	var r_b: Building = world_b.building_at(Vector2i(11, 11))
	if sp_b == null or u_b == null or l_b == null or r_b == null or sp_b.type != Buildings.Type.SPLITTER:
		_check(failures, false, "(2a) PREMISE: the fixture line did not reload intact")
		_cleanup(world_b)
		return
	_check(failures, int(sp_b.state.get("next_out", -99)) == 1,
		"(2a) next_out must RESUME as the literal 1 across the load — a reset (or an omit-from-state) reads 0 here and reroutes every post-load item, got %s"
			% str(sp_b.state.get("next_out", "<absent>")))
	_check(failures, _slots_of(l_b) == [-1, -1, Items.Type.WHEAT, Items.Type.GRAIN],
		"(2a) L's slots must round-trip position-exact, got %s" % str(_slots_of(l_b)))
	_check(failures, _slots_of(r_b) == [-1, -1, -1, Items.Type.FLOUR],
		"(2a) R's slots must round-trip position-exact, got %s" % str(_slots_of(r_b)))

	# Phase 2 — items 4..6 into the LOADED world: STRAW → R, COAL → L,
	# WOOD → R, continuing the alternation from next_out = 1.
	fed = 0
	var labels2: Array = [Items.Type.STRAW, Items.Type.COAL, Items.Type.WOOD]
	for _t in 140:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < 3 and Belt.try_insert(u_b, int(labels2[fed])):
			fed += 1
	_check(failures, fed == 3, "(2a) PREMISE: expected to feed 3 post-load items, fed %d" % fed)
	_check(failures, _slots_of(l_b) == [-1, Items.Type.COAL, Items.Type.WHEAT, Items.Type.GRAIN],
		"(2a) MERGED L must equal the uninterrupted six-item literal [_, COAL, WHEAT, GRAIN] (test_splitter.gd (A)) — a next_out reset on load sends item 4 LEFT and every later item to the wrong belt ('my balancer broke after reload', untraced to serialization); got %s"
			% str(_slots_of(l_b)))
	_check(failures, _slots_of(r_b) == [-1, Items.Type.WOOD, Items.Type.STRAW, Items.Type.FLOUR],
		"(2a) MERGED R must equal the uninterrupted six-item literal [_, WOOD, STRAW, FLOUR], got %s"
			% str(_slots_of(r_b)))
	_cleanup(world_b)

# ===========================================================================
# (2b) UNDERGROUND MID-FLIGHT RESUME. test_underground.gd (B)'s gap-3 run,
# interrupted: GRAIN + FLOUR are driven to tick 48 — resting at global slots
# [14, 16], BOTH INSIDE THE TUNNEL — saved, loaded into a fresh world, and
# driven on to tick 100. The CONSERVATION COUNT is asserted first and on
# every post-load tick: a load that drops the tunnel loses items in a way a
# trajectory mismatch could excuse as timing, and the count is what names it
# LOSS. Then the per-tick merged trajectory must keep walking PATH24 with
# arrival dues unchanged — possible only because the "tick" field
# round-trips (save_game stores TickSystem.current_tick, load_game restores
# it; asserted below as the literal 48).
# ===========================================================================
static func _case_2b_underground_midflight(parent: Node, failures: Array) -> void:
	var world_a = _make_world(parent)
	var cells: Array = []
	for x in range(4, 11):
		cells.append(Vector2i(x, 10))
	if not _pave(world_a, failures, "(2b)", cells):
		_cleanup(world_a)
		return
	var f: Building = _place(world_a, failures, "(2b)", Buildings.Type.BELT, Vector2i(4, 10), Belt.DIR_E)
	var entry: Building = _place(world_a, failures, "(2b)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(5, 10), Belt.DIR_E)
	var exit_a: Building = _place(world_a, failures, "(2b)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E)
	var o: Building = _place(world_a, failures, "(2b)", Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_E)
	if f == null or entry == null or exit_a == null or o == null:
		_cleanup(world_a)
		return

	# Phase 1 — the (B)/(E) drive: GRAIN at due 0, FLOUR at due 1, 48 ticks.
	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(f, Items.Type.GRAIN), "(2b) feeder refused GRAIN")
	var fed: int = 1
	for _t in 48:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < 2 and Belt.try_insert(f, Items.Type.FLOUR):
			fed += 1
	_check(failures, fed == 2, "(2b) PREMISE: expected both items fed, fed %d" % fed)
	var pre: Array = _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])
	_check(failures, pre == [14, 16],
		"(2b) PREMISE: at tick 48 the items must rest at global slots [14, 16] — tunnel slots 6 and 8, mid-transit (test_underground.gd (E)'s own literal) — got %s" % str(pre))

	if not _save_ok(parent, world_a, failures, "(2b)"):
		_cleanup(world_a)
		return
	_cleanup(world_a)

	# Fresh world; load; the tick and the in-flight items must both be back.
	var world_b = _make_world(parent)
	if _load_into(parent, world_b, failures, "(2b)") == null:
		_cleanup(world_b)
		return
	var f_b: Building = world_b.building_at(Vector2i(4, 10))
	var entry_b: Building = world_b.building_at(Vector2i(5, 10))
	var o_b: Building = world_b.building_at(Vector2i(10, 10))
	if f_b == null or entry_b == null or o_b == null or entry_b.type != Buildings.Type.UNDERGROUND_BELT_ENTRY:
		_check(failures, false, "(2b) PREMISE: the fixture line did not reload intact")
		_cleanup(world_b)
		return
	# CONSERVATION FIRST: two items went into the save, two must come out.
	# This is the assertion that catches a tunnel dropped on load AS LOSS —
	# a bare trajectory mismatch could be misread as a timing artifact.
	_check(failures, _count_arrays([_slots_of(f_b), _slots_of(entry_b), _tunnel_of(entry_b), _slots_of(o_b)]) == 2,
		"(2b) ITEMS LOST ACROSS THE LOAD: 2 items were saved mid-tunnel, %d are on the loaded layout — a load that clears (or omits) state[\"tunnel\"] destroys in-flight items and nothing else in the game will ever say so"
			% _count_arrays([_slots_of(f_b), _slots_of(entry_b), _tunnel_of(entry_b), _slots_of(o_b)]))
	_check(failures, TickSystem.current_tick == 48,
		"(2b) the saved tick was the literal 48 and load_game must restore it (save_game writes the \"tick\" field, load_game reads it back — the round-trip that keeps arrival dues unchanged), got %d" % TickSystem.current_tick)
	_check(failures, _occupied_arrays([_slots_of(f_b), _slots_of(entry_b), _tunnel_of(entry_b), _slots_of(o_b)]) == [14, 16],
		"(2b) the in-flight items must reload at the SAME global slots [14, 16], got %s"
			% str(_occupied_arrays([_slots_of(f_b), _slots_of(entry_b), _tunnel_of(entry_b), _slots_of(o_b)])))

	# Phase 2 — continue to tick 100 against PATH24, dues indexed by the
	# RESTORED world tick. GRAIN walks PATH24[due], FLOUR one due behind;
	# GRAIN parks at 23 (due 18), FLOUR against it at 22.
	for _t in 52:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		var due: int = TickSystem.current_tick / Belt.TICKS_PER_SLOT
		var g_expected: int = int(PATH24[mini(due, PATH24.size() - 1)])
		var f_expected: int = int(PATH24[mini(due - 1, PATH24.size() - 2)])
		var occ: Array = _occupied_arrays([_slots_of(f_b), _slots_of(entry_b), _tunnel_of(entry_b), _slots_of(o_b)])
		_check_once(failures, "(2b)path",
			occ == [f_expected, g_expected],
			"(2b) tick %d: merged trajectory expected exactly [%d, %d], got %s — the post-load run must keep walking test_underground.gd (B)'s PATH24 with dues unchanged; a tick reset, a cleared tunnel, or a re-based due arithmetic reddens here"
				% [TickSystem.current_tick, f_expected, g_expected, str(occ)])
		_check_once(failures, "(2b)conserve",
			_count_arrays([_slots_of(f_b), _slots_of(entry_b), _tunnel_of(entry_b), _slots_of(o_b)]) == 2,
			"(2b) conservation broke post-load at tick %d: 2 items expected on the layout, %d found"
				% [TickSystem.current_tick, _count_arrays([_slots_of(f_b), _slots_of(entry_b), _tunnel_of(entry_b), _slots_of(o_b)])])

	_check(failures, _slots_of(o_b) == [-1, -1, Items.Type.FLOUR, Items.Type.GRAIN],
		"(2b) REACHABILITY CONTROL: both items must finish on the downstream belt in arrival order (GRAIN at the front, FLOUR behind), got %s"
			% str(_slots_of(o_b)))
	_cleanup(world_b)

# ===========================================================================
# (3) PARTIAL OCCUPANCY, and (4) the v18 save MISSING the new fields.
#
# (3): three part-full fixtures in ONE world, saved and reloaded with NO
# ticks in between, asserted as EXACT slot-array literals. Full and empty
# both round-trip through any plausible serialization; the pole-tier session
# proved it is the MIDDLE that drops with the suite green. A -1-dropping
# "compression" keeps all three occupied COUNTS and loses all three
# positions (and the empty tunnel's length) — the literals redden where a
# count-only assertion stays green.
#
# (4): the SAME save file is then hand-edited on disk into a Task-1/2-era
# shape — the splitter's state stripped to {"dir"} (no next_out, no slots),
# the gap-3 entry's stripped to {"dir"} (no tunnel, no slots) — and loaded.
# The #11 shape guards must not skip these buildings (skipped_entries stays
# 0), nothing crashes, and the .get() defaults observably engage: one
# advance tick later the splitter's lane exists at the literal length 4 and
# the paired entry's tunnel at the literal length 12.
# ===========================================================================
static func _case_3_partial_occupancy_and_4_missing_fields(parent: Node, failures: Array) -> void:
	var world_a = _make_world(parent)
	var cells: Array = []
	for x in range(5, 10):
		cells.append(Vector2i(x, 10))   # E1 pair row
		cells.append(Vector2i(x, 14))   # E2 pair row
	cells.append(Vector2i(10, 22))      # S1 splitter (2x1 at dir E)
	cells.append(Vector2i(11, 22))
	if not _pave(world_a, failures, "(3)", cells):
		_cleanup(world_a)
		return
	var e1: Building = _place(world_a, failures, "(3)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(5, 10), Belt.DIR_E)
	var x1: Building = _place(world_a, failures, "(3)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E)
	var e2: Building = _place(world_a, failures, "(3)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(5, 14), Belt.DIR_E)
	var x2: Building = _place(world_a, failures, "(3)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 14), Belt.DIR_E)
	var s1: Building = _place(world_a, failures, "(3)", Buildings.Type.SPLITTER, Vector2i(10, 22), Belt.DIR_E)
	if e1 == null or x1 == null or e2 == null or x2 == null or s1 == null:
		_cleanup(world_a)
		return

	# The three part-full states, set directly — a round-trip does not care
	# how the state arose, and direct placement makes the slot indices exact.
	# E1: gap-3 tunnel (12 slots), ONE item in the middle slot (index 5).
	e1.state["tunnel"] = [-1, -1, -1, -1, -1, Items.Type.WHEAT, -1, -1, -1, -1, -1, -1]
	# E2: own input slot occupied, tunnel present and ENTIRELY empty.
	e2.state["slots"] = [Items.Type.COAL, -1, -1, -1]
	e2.state["tunnel"] = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]
	# S1: one item mid-lane (index 1).
	s1.state["slots"] = [-1, Items.Type.GRAIN, -1, -1]

	if not _save_ok(parent, world_a, failures, "(3)"):
		_cleanup(world_a)
		return
	_cleanup(world_a)

	var world_b = _make_world(parent)
	if _load_into(parent, world_b, failures, "(3)") == null:
		_cleanup(world_b)
		return
	var e1_b: Building = world_b.building_at(Vector2i(5, 10))
	var e2_b: Building = world_b.building_at(Vector2i(5, 14))
	var s1_b: Building = world_b.building_at(Vector2i(10, 22))
	if e1_b == null or e2_b == null or s1_b == null:
		_check(failures, false, "(3) PREMISE: the three fixtures did not reload")
		_cleanup(world_b)
		return
	_check(failures, _tunnel_of(e1_b) == [-1, -1, -1, -1, -1, Items.Type.WHEAT, -1, -1, -1, -1, -1, -1],
		"(3) the part-full tunnel must reload POSITION-EXACT: one WHEAT in the middle slot (index 5) of 12 — a serialization that compresses away -1 slots keeps the COUNT (1) and loses the POSITION, so a count-only assertion stays green while the item teleports toward the exit; got %s"
			% str(_tunnel_of(e1_b)))
	_check(failures, _slots_of(e2_b) == [Items.Type.COAL, -1, -1, -1],
		"(3) the entry's own occupied input slot must reload at index 0 exactly, got %s"
			% str(_slots_of(e2_b)))
	_check(failures, _tunnel_of(e2_b) == [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
		"(3) the ENTIRELY EMPTY 12-slot tunnel must reload at its full length — a -1-dropping compression collapses it to [] and the next sync silently rebuilds it as if never travelled; got %s"
			% str(_tunnel_of(e2_b)))
	_check(failures, _slots_of(s1_b) == [-1, Items.Type.GRAIN, -1, -1],
		"(3) the splitter's mid-lane item must reload at slot index 1 exactly (position, not just count), got %s"
			% str(_slots_of(s1_b)))
	_cleanup(world_b)

	# ---- (4) hand-edit the SAME v18 file into the fields-absent shape ----
	var raw: String = FileAccess.get_file_as_string(TEST_SAVE_PATH)
	var data = JSON.parse_string(raw)
	if not (data is Dictionary):
		_check(failures, false, "(4) PREMISE: could not parse the saved fixture as JSON")
		return
	var stripped_splitter: bool = false
	var stripped_entry: bool = false
	for bdict in data.get("buildings", []):
		if not (bdict is Dictionary):
			continue
		var s = bdict.get("s", {})
		if not (s is Dictionary):
			continue
		if int(bdict.get("t", -1)) == 34 and int(bdict.get("x", -1)) == 10 and int(bdict.get("y", -1)) == 22:
			s.erase("next_out")
			s.erase("slots")
			stripped_splitter = true
		if int(bdict.get("t", -1)) == 35 and int(bdict.get("x", -1)) == 5 and int(bdict.get("y", -1)) == 10:
			s.erase("tunnel")
			s.erase("slots")
			stripped_entry = true
	_check(failures, stripped_splitter and stripped_entry,
		"(4) PREMISE: expected to strip the splitter (t=34 at 10,22) and the entry (t=35 at 5,10) from the fixture JSON; splitter=%s entry=%s" % [str(stripped_splitter), str(stripped_entry)])
	var out := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if out == null:
		_check(failures, false, "(4) PREMISE: could not rewrite the fixture")
		return
	out.store_string(JSON.stringify(data))
	out.close()

	var world_c = _make_world(parent)
	var result = _load_into(parent, world_c, failures, "(4)")
	if result == null:
		_cleanup(world_c)
		return
	_check(failures, int(result.skipped_entries) == 0,
		"(4) a v18 save whose splitter/entry states lack the new fields must load with NO skipped entries (the #11 shape guards validate containers, and {\"dir\"} is a valid state dict) — skipped_entries is %d"
			% int(result.skipped_entries))
	var sp_c: Building = world_c.building_at(Vector2i(10, 22))
	var e1_c: Building = world_c.building_at(Vector2i(5, 10))
	if sp_c == null or e1_c == null or sp_c.type != Buildings.Type.SPLITTER or e1_c.type != Buildings.Type.UNDERGROUND_BELT_ENTRY:
		_check(failures, false, "(4) PREMISE: the stripped buildings did not reload as their own types")
		_cleanup(world_c)
		return
	_check(failures, not sp_c.state.has("next_out") and not sp_c.state.has("slots"),
		"(4) PREMISE: the loaded splitter state must genuinely LACK next_out and slots (the load must not resurrect them), keys: %s" % str(sp_c.state.keys()))
	_check(failures, not e1_c.state.has("tunnel") and not e1_c.state.has("slots"),
		"(4) PREMISE: the loaded entry state must genuinely LACK tunnel and slots, keys: %s" % str(e1_c.state.keys()))
	# One advance tick: the .get()/lazy defaults must engage — no crash, and
	# the arrays regrow at their canonical lengths (the entry is PAIRED with
	# the exit at (9,10), so its tunnel syncs to gap 3 = the literal 12).
	TickSystem.current_tick = 0
	for _t in 4:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, sp_c.state.has("slots") and (sp_c.state["slots"] as Array).size() == 4,
		"(4) after one advance tick the splitter's lane must have lazily regrown to the literal 4 slots (the .get() default engaging in practice), state: %s" % str(sp_c.state))
	_check(failures, e1_c.state.has("tunnel") and (e1_c.state["tunnel"] as Array).size() == 12,
		"(4) after one advance tick the paired entry's tunnel must have lazily regrown to the literal 12 slots, state: %s" % str(e1_c.state))
	_cleanup(world_c)

# ---------- fixture builders ----------

## test_splitter.gd's standard line: U belt (9,10)E → splitter (10,10)E,
## L branch belt (11,9) flowing N, R branch belt (11,11) flowing S.
static func _build_splitter_line(world, failures: Array, tag: String) -> Dictionary:
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
	if not world.place_building(Buildings.Type.BELT, Vector2i(11, 9), Belt.DIR_N):
		_check(failures, false, "%s PREMISE: L branch belt placement failed" % tag)
		return {}
	if not world.place_building(Buildings.Type.BELT, Vector2i(11, 11), Belt.DIR_S):
		_check(failures, false, "%s PREMISE: R branch belt placement failed" % tag)
		return {}
	return {
		"u": world.building_at(Vector2i(9, 10)),
		"sp": world.building_at(Vector2i(10, 10)),
		"l": world.building_at(Vector2i(11, 9)),
		"r": world.building_at(Vector2i(11, 11)),
	}

# ---------- save/load helpers ----------

static func _save_ok(parent: Node, world, failures: Array, tag: String) -> bool:
	var player := Node2D.new()
	parent.add_child(player)
	var inv: Inventory = Inventory.new(16)
	var ok: bool = SaveSystem.save_game(world, player, inv)
	player.queue_free()
	if not ok:
		_check(failures, false, "%s PREMISE: save_game returned false" % tag)
	return ok

static func _load_into(parent: Node, world, failures: Array, tag: String) -> LoadResult:
	var player := Node2D.new()
	parent.add_child(player)
	var inv: Inventory = Inventory.new(16)
	var result = SaveSystem.load_game(world, player, inv)
	player.queue_free()
	if result == null or not bool(result.success):
		_check(failures, false, "%s PREMISE: load_game failed: %s"
			% [tag, ("<null result>" if result == null else str(result.error_message))])
		return null
	return result

static func _delete_fixture() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

# ---------- state readers (compare-only; literals never come from here) ----------

static func _slots_of(b: Building) -> Array:
	var out: Array = []
	if b == null:
		return out
	for s in b.state.get("slots", []):
		out.append(int(s))
	return out

static func _tunnel_of(b: Building) -> Array:
	var out: Array = []
	if b == null:
		return out
	for s in b.state.get("tunnel", []):
		out.append(int(s))
	return out

## Global slot indices occupied across `unit_arrays` (each an Array of ints,
## contributing its own length to the running offset), ascending.
static func _occupied_arrays(unit_arrays: Array) -> Array:
	var out: Array = []
	var base: int = 0
	for arr in unit_arrays:
		for i in arr.size():
			if int(arr[i]) >= 0:
				out.append(base + i)
		base += arr.size()
	return out

static func _count_arrays(unit_arrays: Array) -> int:
	return _occupied_arrays(unit_arrays).size()

# ---------- generic scaffolding ----------

static func _pave(world, failures: Array, tag: String, cells: Array) -> bool:
	for cell in cells:
		if not world.set_overlay(cell, Terrain.Overlay.STONE):
			_check(failures, false, "%s PREMISE: could not pave %s" % [tag, str(cell)])
			return false
	return true

static func _place(world, failures: Array, tag: String, t: int, pos: Vector2i, dir: int) -> Building:
	if not world.place_building(t, pos, dir):
		_check(failures, false, "%s PREMISE: could not place %s at %s: %s"
			% [tag, Buildings.name_of(t), str(pos), str(world.last_building_place_error)])
		return null
	return world.building_at(pos)

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
