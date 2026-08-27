extends RefCounted

## Belt Logistics Session 1, Task 5 — UNDERGROUND BELT CORE.
##
## The locked design under test (docs/scoping/belt-logistics-1.md, Q6/Q6b/Q7/
## Q8 + the task brief's three mandated items):
##
##   - PAIRING IS RECOMPUTED, NEVER STORED (Q6). `Underground.paired_exit`
##     is the single predicate — the `poles_connected` of this arc — scanning
##     k = 2 .. UNDERGROUND_MAX_SPAN+1 cells along the ENTRY'S OWN dir for the
##     nearest UNDERGROUND_BELT_EXIT whose dir EQUALS the entry's. Sub-case
##     (A) asserts the pairing AND the non-pairing layouts as literals, with a
##     wrong-dir poison exit inside range in every pairing layout.
##   - SPAN CONSTANT (Q6b): `UNDERGROUND_MAX_SPAN` is the underground module's
##     OWN constant, documented-equal to the basic pole's POLE_RANGE_BY_TYPE
##     row and pinned HERE by the literal 3 — deliberately NOT compared to the
##     power table (a cross-module cite would let a pole rebalance silently
##     rebalance tunnels; a prose equality drifts, a test literal reddens).
##   - UNPAIRED ENTRY REFUSES INPUT (Q7). It acts full: the upstream belt
##     jams and items pile up as whole-array literals on the feeding belts —
##     never into the entry. Inert-but-accepting is the #19 infinite-sink
##     shape, disqualified by name in the record. Sub-case (C), with
##     conservation counted across the layout during the refusal.
##   - TUNNEL AS SLOTS, NOT TELEPORT (Q8). The entry owns ALL moving state:
##     a 4-slot surface lane (its own tile — the splitter's one-belt-tile-
##     equivalent arithmetic) plus `state["tunnel"]`, length gap ×
##     Belt.SLOTS_PER_TILE organised as gap belt-tile SEGMENTS whose internal
##     boundaries behave exactly like belt-to-belt handoffs (front slots
##     transient). Crossing entry → belt-beyond-exit therefore costs exactly
##     (gap+1) belt tiles of travel, and the trajectory literal is the SAME
##     EXPECTED_PATH shape as a surface run of (gap+1) belts — sub-case (B)
##     asserts the underground chain and a six-belt surface twin against the
##     SAME literal array, per advance tick, in the same world on the same
##     clock.
##
## ⚠ THE EXIT-CELL DISCOUNT, STATED OUT LOUD: the EXIT is passive (no tick
## case, no lane) and the pass-2 handoff from the tunnel front lands on the
## belt BEYOND it, so the exit's own cell is crossed in the handoff — one
## cell of footprint with no lane behind it. This mirrors the splitter's
## locked latency exactly (2×1 footprint, ONE belt-tile lane), and it is why
## the "equivalent surface run" in (B) is gap+1 belts, not gap+2. If the arc
## ever decides the exit cell must cost a tile, the tunnel grows a segment
## and (B)'s literal moves — say it out loud, don't absorb it.
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. Nothing here asks Underground (or
## Belt) for its own expectation; due-tick arithmetic is derived from
## `TickSystem.current_tick / Belt.TICKS_PER_SLOT` exactly as test_belt.gd
## does — never from `Underground.*` or `Belt.is_advance_tick()` (the M4
## lesson: an expectation computed by the code under test moves with it).
##
## ⚠ REACHABILITY CONTROLS: every guard sub-case is paired with flow that
## must ARRIVE, so "nothing crossed" can never read as "the guard worked".
##
## Mid-transit re-pair (the design pass's truncate-by-delivery rule):
##   - re-pair NEARER (E): the tunnel's length re-syncs to the new pairing
##     distance; in-flight items beyond the new length surface at the NEW
##     exit, one per advance tick, drained from the tunnel's far end —
##     truncate-by-delivery, never drop. Conservation is asserted per tick.
##   - re-pair FARTHER (F): the tunnel grows with EMPTY far slots; the item
##     walks every grown slot — no teleport. The post-swap trajectory equals
##     the gap-3 literal from (B), because after the growth that is exactly
##     what the geometry is.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

## Resting positions of one item over feeder belt → entry lane → gap-3
## tunnel → downstream belt, by advance-tick index. Chain global index:
## feeder slot s = s, entry lane slot s = 4 + s, tunnel slot j = 8 + j,
## downstream belt slot s = 20 + s. The SAME literal a run of SIX surface
## belts produces (test_belt.gd's EXPECTED_PATH construction extended):
## every 4th global slot is a boundary front slot, transient because the
## same advance tick that fills it also crosses it. Derived by hand from
## the two-pass mechanics, not copied from a run.
const PATH24: Array = [0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 16, 17, 18, 20, 21, 22, 23]

## The gap-1 form of the same construction (feeder → lane → 4-slot tunnel →
## downstream belt = 16 global slots, the four-surface-belt literal).
const PATH16: Array = [0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 15]

## Distinct item types used as arrival-order labels 1..6 — slot order on a
## jammed belt is reverse arrival order, so whole-array literals pin count,
## types AND order in one comparison (test_splitter.gd's pattern).
const LABELS: Array = [
	Items.Type.GRAIN,    # item 1
	Items.Type.FLOUR,    # item 2
	Items.Type.WHEAT,    # item 3
	Items.Type.STRAW,    # item 4
	Items.Type.COAL,     # item 5
	Items.Type.WOOD,     # item 6
]

static func test_name() -> String:
	return "underground belt core (pairing scan + span pin, lane+tunnel trajectory vs surface twin, refuse-when-unpaired backpressure, conservation, mid-transit re-pair both ways, #14 emit guard, input-edge refusals, rotated run)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_a_pairing_predicate(parent, failures)
	_case_b_trajectory_and_twin(parent, failures)
	_case_c_refuse_unpaired_then_repair(parent, failures)
	_case_d_conservation_and_jam(parent, failures)
	_case_e_repair_nearer(parent, failures)
	_case_f_repair_farther(parent, failures)
	_case_g_rotated_west_run(parent, failures)
	_case_h_emit_feeder_guard(parent, failures)
	_case_i_input_edge_refusals(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 24))] }

# ===========================================================================
# (A) THE PAIRING PREDICATE, AS LITERALS. Layouts on separate rows of one
# world; every expected partner is a literal anchor, every non-pairing case a
# literal null. Each PAIRING layout carries a wrong-dir poison exit inside
# range that must never win — with the facing check deleted, the poison wins
# and the expected-anchor literal reddens.
# ===========================================================================
static func _case_a_pairing_predicate(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)

	# (A1) gap-3 pair + poison. Entry (10,20) E; poison exit (12,20) facing N
	# (in range, wrong dir); real exit (14,20) E — k = 4 = MAX_SPAN+1, the
	# farthest legal partner, companion to (A5)'s just-out-of-range literal.
	if _pave(world, failures, "(A1)", [Vector2i(10, 20), Vector2i(12, 20), Vector2i(14, 20)]):
		var a1_entry: Building = _place(world, failures, "(A1)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 20), Belt.DIR_E)
		_place(world, failures, "(A1)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 20), Belt.DIR_N)
		_place(world, failures, "(A1)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(14, 20), Belt.DIR_E)
		if a1_entry != null:
			var a1_pe: Building = Underground.paired_exit(a1_entry, world)
			_check(failures, a1_pe != null and a1_pe.anchor == Vector2i(14, 20),
				"(A1) entry (10,20)E must pair with the E-facing exit at the literal (14,20) — the N-facing poison at (12,20) is nearer but must NEVER win (a deleted facing check pairs the poison and reddens here); got %s"
					% (str(a1_pe.anchor) if a1_pe != null else "null"))

	# (A2) nearest wins + poison. Exits at gap 1 (12,22) and gap 3 (14,22),
	# both E; wrong-dir poison between them at (13,22) facing S.
	if _pave(world, failures, "(A2)", [Vector2i(10, 22), Vector2i(12, 22), Vector2i(13, 22), Vector2i(14, 22)]):
		var a2_entry: Building = _place(world, failures, "(A2)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 22), Belt.DIR_E)
		_place(world, failures, "(A2)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 22), Belt.DIR_E)
		_place(world, failures, "(A2)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(13, 22), Belt.DIR_S)
		_place(world, failures, "(A2)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(14, 22), Belt.DIR_E)
		if a2_entry != null:
			var a2_pe: Building = Underground.paired_exit(a2_entry, world)
			_check(failures, a2_pe != null and a2_pe.anchor == Vector2i(12, 22),
				"(A2) with valid exits at gap 1 and gap 3, the NEAR one at the literal (12,22) pairs (a farthest-wins scan returns (14,22) and reddens here); got %s"
					% (str(a2_pe.anchor) if a2_pe != null else "null"))

	# (A3) an exit facing PERPENDICULAR, in range, alone → no pair.
	if _pave(world, failures, "(A3)", [Vector2i(10, 24), Vector2i(12, 24)]):
		var a3_entry: Building = _place(world, failures, "(A3)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 24), Belt.DIR_E)
		_place(world, failures, "(A3)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 24), Belt.DIR_N)
		if a3_entry != null:
			_check(failures, Underground.paired_exit(a3_entry, world) == null,
				"(A3) an in-range exit facing N must NOT pair with an E entry — dir must match, not merely 'an exit exists in range'")

	# (A4) two entries in a row: an entry is not an exit, and the second
	# entry does not chain — both literal nulls.
	if _pave(world, failures, "(A4)", [Vector2i(10, 26), Vector2i(12, 26)]):
		var a4_first: Building = _place(world, failures, "(A4)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 26), Belt.DIR_E)
		var a4_second: Building = _place(world, failures, "(A4)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(12, 26), Belt.DIR_E)
		if a4_first != null and a4_second != null:
			_check(failures, Underground.paired_exit(a4_first, world) == null,
				"(A4) an ENTRY ahead is not an exit — the first entry must not pair")
			_check(failures, Underground.paired_exit(a4_second, world) == null,
				"(A4) the second entry has nothing ahead and must not 'chain' off the first — literal null")

	# (A5) exit beyond span: k = 5 = UNDERGROUND_MAX_SPAN + 2 — THE literal
	# that pins the constant. Span 3→4 turns this into a pair and reddens.
	if _pave(world, failures, "(A5)", [Vector2i(10, 28), Vector2i(15, 28)]):
		var a5_entry: Building = _place(world, failures, "(A5)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 28), Belt.DIR_E)
		_place(world, failures, "(A5)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(15, 28), Belt.DIR_E)
		if a5_entry != null:
			_check(failures, Underground.paired_exit(a5_entry, world) == null,
				"(A5) an E exit 5 cells out (gap 4) is BEYOND span and must not pair — this literal pins UNDERGROUND_MAX_SPAN at 3; a span bump to 4 pairs it and reddens here")

	# (A6) rotation: the scan follows the ENTRY'S OWN dir. South pair with an
	# E-facing poison beside the tunnel line; west pair with an N-facing
	# poison. Expected anchors differ under rotation by construction.
	if _pave(world, failures, "(A6S)", [Vector2i(10, 30), Vector2i(10, 32), Vector2i(10, 33)]):
		var a6s_entry: Building = _place(world, failures, "(A6S)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 30), Belt.DIR_S)
		_place(world, failures, "(A6S)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(10, 32), Belt.DIR_E)
		_place(world, failures, "(A6S)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(10, 33), Belt.DIR_S)
		if a6s_entry != null:
			var a6s_pe: Building = Underground.paired_exit(a6s_entry, world)
			_check(failures, a6s_pe != null and a6s_pe.anchor == Vector2i(10, 33),
				"(A6S) a S entry scans SOUTH: pair is the S exit at the literal (10,33), never the nearer E poison at (10,32) inside scan range; got %s"
					% (str(a6s_pe.anchor) if a6s_pe != null else "null"))
	if _pave(world, failures, "(A6W)", [Vector2i(20, 30), Vector2i(18, 30), Vector2i(16, 30)]):
		var a6w_entry: Building = _place(world, failures, "(A6W)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(20, 30), Belt.DIR_W)
		_place(world, failures, "(A6W)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(18, 30), Belt.DIR_N)
		_place(world, failures, "(A6W)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(16, 30), Belt.DIR_W)
		if a6w_entry != null:
			var a6w_pe: Building = Underground.paired_exit(a6w_entry, world)
			_check(failures, a6w_pe != null and a6w_pe.anchor == Vector2i(16, 30),
				"(A6W) a W entry scans WEST: pair is the W exit at the literal (16,30), never the N poison at (18,30); got %s"
					% (str(a6w_pe.anchor) if a6w_pe != null else "null"))

	# (A7) the Q6b span pin itself: the module's OWN constant, the literal 3.
	# Documented-equal to the basic pole's POLE_RANGE_BY_TYPE row — in PROSE,
	# on purpose. Comparing the two constants here would couple the power
	# table to the belt module and let a pole rebalance silently rebalance
	# tunnels (the named silent-compensation shape).
	_check(failures, Underground.UNDERGROUND_MAX_SPAN == 3,
		"(A7) UNDERGROUND_MAX_SPAN must be the literal 3 (Q6b: documented-equal to the basic pole's range, pinned here as its own literal), got %d"
			% Underground.UNDERGROUND_MAX_SPAN)

	# (A8) an exit DIRECTLY ADJACENT (k = 1) does not pair: the scan starts
	# at k = 2, so the minimum tunnel is one covered cell. (The task brief's
	# scan bounds k ∈ 2..MAX_SPAN+1 fix gap to 1..3; the record's Q8 prose
	# says "gap 0..3" — the shipped scan follows the mandated bounds, and
	# this literal makes that resolution visible instead of silent.)
	if _pave(world, failures, "(A8)", [Vector2i(10, 34), Vector2i(11, 34)]):
		var a8_entry: Building = _place(world, failures, "(A8)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 34), Belt.DIR_E)
		_place(world, failures, "(A8)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(11, 34), Belt.DIR_E)
		if a8_entry != null:
			_check(failures, Underground.paired_exit(a8_entry, world) == null,
				"(A8) an exit in the entry's immediately-adjacent cell (k=1) must not pair — the scan starts at k=2 (minimum one covered cell)")

	_cleanup(world)

# ===========================================================================
# (B) TRAJECTORY, AND THE SURFACE TWIN ASSERTED AGAINST THE SAME LITERAL.
# Row 10: feeder belt → entry → 3 covered cells → exit → downstream belt.
# Row 14: SIX plain belts — the equivalent surface run (gap+1 belt-tile
# equivalents + the two real belts; the exit cell is crossed in the handoff,
# see the header). One item each, inserted on the same tick, asserted per
# advance tick against the ONE literal PATH24. A tunnel that teleports, adds
# latency, skips its segment boundaries, or shifts on the wrong clock parts
# ways with the twin and reddens — the twin is the parity control.
# ===========================================================================
static func _case_b_trajectory_and_twin(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var u_cells: Array = []
	for x in range(4, 11):
		u_cells.append(Vector2i(x, 10))
	var t_cells: Array = []
	for x in range(4, 10):
		t_cells.append(Vector2i(x, 14))
	if not _pave(world, failures, "(B)", u_cells + t_cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(B)", Buildings.Type.BELT, Vector2i(4, 10), Belt.DIR_E)
	var entry: Building = _place(world, failures, "(B)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(5, 10), Belt.DIR_E)
	var exit_b: Building = _place(world, failures, "(B)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E)
	var o: Building = _place(world, failures, "(B)", Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_E)
	var twin: Array = []
	for x in range(4, 10):
		twin.append(_place(world, failures, "(B)twin", Buildings.Type.BELT, Vector2i(x, 14), Belt.DIR_E))
	if f == null or entry == null or exit_b == null or o == null or twin.has(null):
		_cleanup(world)
		return
	var b_pe: Building = Underground.paired_exit(entry, world)
	_check(failures, b_pe != null and b_pe.anchor == Vector2i(9, 10),
		"(B) PREMISE: entry (5,10)E must pair with the exit at (9,10) (gap 3) before the trajectory means anything")

	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(f, Items.Type.GRAIN), "(B) feeder belt refused GRAIN")
	_check(failures, Belt.try_insert(twin[0], Items.Type.GRAIN), "(B) twin's first belt refused GRAIN")
	_check(failures, _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)]) == [0],
		"(B) the underground item should start at global slot 0")

	for _t in 100:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		# Expected position indexed by WORLD ticks over TICKS_PER_SLOT — the
		# arithmetic source the M4 mutation cannot reach.
		var due: int = TickSystem.current_tick / Belt.TICKS_PER_SLOT
		var expected: int = int(PATH24[mini(due, PATH24.size() - 1)])
		var u_occ: Array = _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])
		_check_once(failures, "(B)u-path",
			u_occ == [expected],
			"(B) tick %d: underground chain expected exactly [%d], got %s — feeder → entry lane → gap-3 tunnel → downstream belt must walk the SAME resting positions as a six-belt surface run (the lane and every tunnel segment are belt-tile equivalents; segment fronts are transient). A teleport, an extra-latency lane, a skipped tunnel shift or a wrong-clock advance reddens here"
				% [TickSystem.current_tick, expected, str(u_occ)])
		var t_occ: Array = _occupied_arrays([_slots_of(twin[0]), _slots_of(twin[1]), _slots_of(twin[2]), _slots_of(twin[3]), _slots_of(twin[4]), _slots_of(twin[5])])
		_check_once(failures, "(B)twin-path",
			t_occ == [expected],
			"(B) tick %d: the six-belt surface twin expected exactly [%d], got %s — the twin is the parity control; if THIS reddens the belt substrate moved, not the underground"
				% [TickSystem.current_tick, expected, str(t_occ)])

	_check(failures, _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)]) == [23],
		"(B) REACHABILITY CONTROL: the underground item must park at the downstream belt's front (global slot 23), got %s"
			% str(_occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])))
	_check(failures, _tunnel_of(entry).size() == 12,
		"(B) a gap-3 tunnel is 3 × SLOTS_PER_TILE = the literal 12 slots, got %d"
			% _tunnel_of(entry).size())
	_cleanup(world)

# ===========================================================================
# (C) REFUSE-WHEN-UNPAIRED, VISIBLE IN THE TRAJECTORY — then automatic
# re-pair. Feeder chain F → F2 → entry, NO exit anywhere. Four labelled
# items: all four must pile up on F2 as a whole-array literal (reverse
# arrival order), the entry's lane and tunnel stay empty EVERY tick, and
# conservation holds across the layout — an entry that quietly accepts is
# the #19 sink and reddens three ways. Then the exit is placed and the SAME
# four items drain, in order, onto the new downstream belt: re-pair is
# automatic by construction (no stored partner to refresh).
# ===========================================================================
static func _case_c_refuse_unpaired_then_repair(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = []
	for x in range(4, 11):
		cells.append(Vector2i(x, 10))
	if not _pave(world, failures, "(C)", cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(C)", Buildings.Type.BELT, Vector2i(4, 10), Belt.DIR_E)
	var f2: Building = _place(world, failures, "(C)", Buildings.Type.BELT, Vector2i(5, 10), Belt.DIR_E)
	var entry: Building = _place(world, failures, "(C)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(6, 10), Belt.DIR_E)
	if f == null or f2 == null or entry == null:
		_cleanup(world)
		return
	_check(failures, Underground.paired_exit(entry, world) == null,
		"(C) PREMISE: the entry must be UNPAIRED for the refusal phase")

	TickSystem.current_tick = 0
	var fed: int = 0
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < 4 and Belt.try_insert(f, int(LABELS[fed])):
			fed += 1
		_check_once(failures, "(C)sink",
			_count_arrays([_slots_of(entry), _tunnel_of(entry)]) == 0,
			"(C) an item entered the UNPAIRED entry at tick %d — an unpaired entry acts FULL (Q7); accepting while unpaired is the #19 infinite-sink shape"
				% TickSystem.current_tick)
		_check_once(failures, "(C)conserve",
			_count_arrays([_slots_of(f), _slots_of(f2), _slots_of(entry), _tunnel_of(entry)]) == fed,
			"(C) conservation broke during the refusal at tick %d: %d fed, %d on the layout"
				% [TickSystem.current_tick, fed, _count_arrays([_slots_of(f), _slots_of(f2), _slots_of(entry), _tunnel_of(entry)])])
	_check(failures, fed == 4, "(C) PREMISE: expected to feed 4 items, fed %d" % fed)
	_check(failures, _slots_of(f2) == [Items.Type.STRAW, Items.Type.WHEAT, Items.Type.FLOUR, Items.Type.GRAIN],
		"(C) the refusal must be VISIBLE: all four items pile up on the feeding belt F2 in reverse arrival order (STRAW, WHEAT, FLOUR, GRAIN toward the front), got %s"
			% str(_slots_of(f2)))
	_check(failures, _slots_of(f) == [-1, -1, -1, -1],
		"(C) with only four items, F drains fully into the jam on F2, got %s" % str(_slots_of(f)))

	# Re-pair: place the exit (gap 2) and a downstream belt. No stored
	# partner exists to refresh — the next advance tick's recompute finds it.
	var exit_b: Building = _place(world, failures, "(C)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E)
	var o: Building = _place(world, failures, "(C)", Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_E)
	if exit_b == null or o == null:
		_cleanup(world)
		return
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(C)conserve2",
			_count_arrays([_slots_of(f), _slots_of(f2), _slots_of(entry), _tunnel_of(entry), _slots_of(o)]) == 4,
			"(C) conservation broke during the post-re-pair drain at tick %d: 4 fed, %d on the layout"
				% [TickSystem.current_tick, _count_arrays([_slots_of(f), _slots_of(f2), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])])
	_check(failures, _slots_of(o) == [Items.Type.STRAW, Items.Type.WHEAT, Items.Type.FLOUR, Items.Type.GRAIN],
		"(C) REACHABILITY CONTROL: after the exit lands, the SAME four items drain through the tunnel IN ORDER onto the downstream belt (STRAW, WHEAT, FLOUR, GRAIN toward the front) — a reordering tunnel or a stuck re-pair reddens here; got %s"
			% str(_slots_of(o)))
	_check(failures, _count_arrays([_slots_of(f), _slots_of(f2), _slots_of(entry), _tunnel_of(entry)]) == 0,
		"(C) everything upstream must have drained, %d item(s) stuck"
			% _count_arrays([_slots_of(f), _slots_of(f2), _slots_of(entry), _tunnel_of(entry)]))
	_check(failures, _tunnel_of(entry).size() == 8,
		"(C) a gap-2 tunnel is 2 × SLOTS_PER_TILE = the literal 8 slots, got %d" % _tunnel_of(entry).size())
	_cleanup(world)

# ===========================================================================
# (D) CONSERVATION AND THE JAM. Full line (gap 3), six labelled items, no
# consumer downstream — the downstream belt fills, the line backs up INTO
# the tunnel, and nothing is lost or duplicated at any boundary: exact
# occupied-count across the whole layout after every tick and every insert
# (test_splitter.gd (D)'s pattern with the tunnel in the ring).
# ===========================================================================
static func _case_d_conservation_and_jam(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = []
	for x in range(4, 11):
		cells.append(Vector2i(x, 10))
	if not _pave(world, failures, "(D)", cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(D)", Buildings.Type.BELT, Vector2i(4, 10), Belt.DIR_E)
	var entry: Building = _place(world, failures, "(D)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(5, 10), Belt.DIR_E)
	var exit_b: Building = _place(world, failures, "(D)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E)
	var o: Building = _place(world, failures, "(D)", Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_E)
	if f == null or entry == null or exit_b == null or o == null:
		_cleanup(world)
		return

	TickSystem.current_tick = 0
	var fed: int = 0
	for _t in 300:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(D)conserve-tick",
			_count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)]) == fed,
			"(D) conservation broke across tick %d: %d fed, %d on the layout"
				% [TickSystem.current_tick, fed, _count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])])
		if fed < LABELS.size() and Belt.try_insert(f, int(LABELS[fed])):
			fed += 1
		_check_once(failures, "(D)conserve-insert",
			_count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)]) == fed,
			"(D) conservation broke after an insert at tick %d: %d fed, %d on the layout"
				% [TickSystem.current_tick, fed, _count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])])
	_check(failures, fed == 6, "(D) PREMISE: expected to feed 6 items, fed %d" % fed)

	_check(failures, _slots_of(o) == [Items.Type.STRAW, Items.Type.WHEAT, Items.Type.FLOUR, Items.Type.GRAIN],
		"(D) the downstream belt fills in arrival order (STRAW, WHEAT, FLOUR, GRAIN toward the front), got %s"
			% str(_slots_of(o)))
	_check(failures, _tunnel_of(entry) == [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, Items.Type.WOOD, Items.Type.COAL],
		"(D) the jam backs up INTO the tunnel: items 5 and 6 park against the blocked front (COAL at the front slot, WOOD behind it), got %s"
			% str(_tunnel_of(entry)))
	_check(failures, _slots_of(entry) == [-1, -1, -1, -1] and _slots_of(f) == [-1, -1, -1, -1],
		"(D) lane and feeder must have drained into the jam, lane %s feeder %s"
			% [str(_slots_of(entry)), str(_slots_of(f))])
	_cleanup(world)

# ===========================================================================
# (E) MID-TRANSIT RE-PAIR, NEARER. Gap-3 pair with two labelled items deep
# in the tunnel (beyond the future length); the exit is destroyed and a new
# one placed at gap 1. The tunnel re-syncs to the new pairing distance and
# the in-flight items BEYOND it surface at the NEW exit, farthest first, one
# per advance tick — truncate-by-delivery, NEVER drop. Conservation every
# tick; the old exit's downstream belt must never see an item.
# ===========================================================================
static func _case_e_repair_nearer(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = []
	for x in range(9, 16):
		cells.append(Vector2i(x, 10))
	if not _pave(world, failures, "(E)", cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(E)", Buildings.Type.BELT, Vector2i(9, 10), Belt.DIR_E)
	var entry: Building = _place(world, failures, "(E)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 10), Belt.DIR_E)
	var old_exit: Building = _place(world, failures, "(E)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(14, 10), Belt.DIR_E)
	var old_o: Building = _place(world, failures, "(E)", Buildings.Type.BELT, Vector2i(15, 10), Belt.DIR_E)
	if f == null or entry == null or old_exit == null or old_o == null:
		_cleanup(world)
		return

	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(f, Items.Type.GRAIN), "(E) feeder refused GRAIN")
	var fed: int = 1
	for _t in 48:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if fed < 2 and Belt.try_insert(f, Items.Type.FLOUR):
			fed += 1
	_check(failures, fed == 2, "(E) PREMISE: expected both items fed, fed %d" % fed)
	# Tick 48 = advance tick 12. GRAIN entered at due 0 and sits at PATH24[12]
	# = 16 (tunnel slot 8); FLOUR entered at due 1 (the first tick GRAIN
	# vacated the feeder's back slot) and sits at PATH24[11] = 14 (tunnel
	# slot 6). Both are beyond the future 4-slot tunnel.
	var e_pre: Array = _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry)])
	_check(failures, e_pre == [14, 16],
		"(E) PREMISE: at tick 48 the items must rest at global slots [14, 16] (tunnel slots 6 and 8, both beyond the future length), got %s" % str(e_pre))

	# The swap: destroy the far exit, place a gap-1 exit and its downstream
	# belt on what was a covered cell.
	_check(failures, world.remove_building_at(Vector2i(14, 10)),
		"(E) PREMISE: could not remove the old exit")
	var new_exit: Building = _place(world, failures, "(E)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 10), Belt.DIR_E)
	var n1: Building = _place(world, failures, "(E)", Buildings.Type.BELT, Vector2i(13, 10), Belt.DIR_E)
	if new_exit == null or n1 == null:
		_cleanup(world)
		return
	var e_pe: Building = Underground.paired_exit(entry, world)
	_check(failures, e_pe != null and e_pe.anchor == Vector2i(12, 10),
		"(E) PREMISE: after the swap the entry re-pairs to the literal (12,10) with no stored partner to refresh")

	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(E)conserve",
			_count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(n1), _slots_of(old_o)]) == 2,
			"(E) truncate-by-delivery DROPPED an item at tick %d: 2 fed, %d on the layout — in-flight items beyond the new length must hand off at the new exit, never vanish"
				% [TickSystem.current_tick, _count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(n1), _slots_of(old_o)])])
		_check_once(failures, "(E)old-exit",
			_count_arrays([_slots_of(old_o)]) == 0,
			"(E) an item reached the DESTROYED exit's downstream belt at tick %d — the old pairing is gone and nothing may still deliver along it"
				% TickSystem.current_tick)

	_check(failures, _slots_of(n1) == [-1, -1, Items.Type.FLOUR, Items.Type.GRAIN],
		"(E) both stranded items surface at the NEW exit in travel order (GRAIN was farther along and lands first, so the front holds GRAIN, then FLOUR), got %s"
			% str(_slots_of(n1)))
	_check(failures, _tunnel_of(entry) == [-1, -1, -1, -1],
		"(E) after the drain the tunnel is the new pairing's literal 4 empty slots, got %s"
			% str(_tunnel_of(entry)))
	_cleanup(world)

# ===========================================================================
# (F) MID-TRANSIT RE-PAIR, FARTHER. Gap-1 pair with one item mid-tunnel; the
# exit is destroyed and a new one placed at gap 3. The tunnel GROWS with
# empty far slots and the item walks every one of them — a teleport to the
# new front reddens the per-tick literal. After the growth the geometry IS
# the gap-3 layout, so the post-swap trajectory is PATH24's tail, verbatim.
# The old downstream belt is left standing on what is now a covered cell:
# it must never receive anything (the tunnel passes UNDER surface belts).
# ===========================================================================
static func _case_f_repair_farther(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = []
	for x in range(9, 16):
		cells.append(Vector2i(x, 10))
	if not _pave(world, failures, "(F)", cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(F)", Buildings.Type.BELT, Vector2i(9, 10), Belt.DIR_E)
	var entry: Building = _place(world, failures, "(F)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 10), Belt.DIR_E)
	var old_exit: Building = _place(world, failures, "(F)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 10), Belt.DIR_E)
	var b1: Building = _place(world, failures, "(F)", Buildings.Type.BELT, Vector2i(13, 10), Belt.DIR_E)
	if f == null or entry == null or old_exit == null or b1 == null:
		_cleanup(world)
		return

	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(f, Items.Type.GRAIN), "(F) feeder refused GRAIN")
	for _t in 28:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Tick 28 = advance tick 7: the item rests at PATH16[7] = 9 — tunnel
	# slot 1 of the old 4-slot tunnel.
	var f_pre: Array = _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(b1)])
	_check(failures, f_pre == [9],
		"(F) PREMISE: at tick 28 the item must rest at global slot 9 (tunnel slot 1), got %s" % str(f_pre))

	_check(failures, world.remove_building_at(Vector2i(12, 10)),
		"(F) PREMISE: could not remove the old exit")
	var new_exit: Building = _place(world, failures, "(F)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(14, 10), Belt.DIR_E)
	var n2: Building = _place(world, failures, "(F)", Buildings.Type.BELT, Vector2i(15, 10), Belt.DIR_E)
	if new_exit == null or n2 == null:
		_cleanup(world)
		return
	var f_pe: Building = Underground.paired_exit(entry, world)
	_check(failures, f_pe != null and f_pe.anchor == Vector2i(14, 10),
		"(F) PREMISE: after the swap the entry re-pairs to the literal (14,10)")

	for _t in 72:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		var due: int = TickSystem.current_tick / Belt.TICKS_PER_SLOT
		var expected: int = int(PATH24[mini(due, PATH24.size() - 1)])
		var occ: Array = _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(n2)])
		_check_once(failures, "(F)path",
			occ == [expected],
			"(F) tick %d: expected exactly [%d], got %s — after re-pairing farther the item must WALK the grown tunnel slot by slot (the post-swap geometry is the gap-3 layout, so PATH24 applies verbatim); a teleport to the new front, or a tunnel that failed to grow, reddens here"
				% [TickSystem.current_tick, expected, str(occ)])
		_check_once(failures, "(F)covered-belt",
			_count_arrays([_slots_of(b1)]) == 0,
			"(F) the belt stranded on a COVERED cell received an item at tick %d — the tunnel passes UNDER surface belts; nothing surfaces before the exit"
				% TickSystem.current_tick)

	_check(failures, _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(n2)]) == [23],
		"(F) REACHABILITY CONTROL: the item must park at the new downstream belt's front (global slot 23), got %s"
			% str(_occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(n2)])))
	_check(failures, _tunnel_of(entry).size() == 12,
		"(F) the re-paired gap-3 tunnel is the literal 12 slots, got %d" % _tunnel_of(entry).size())
	_cleanup(world)

# ===========================================================================
# (G) ROTATED RUN (dir = W, gap 1). The scan direction, the input edge and
# the emit target all rotate with the entry's dir; an implementation that
# leaks canonical-E geometry anywhere refuses the feed or emits into the
# wrong cell, and the same-shape literal reddens. Expected cells differ from
# (B)'s under rotation by construction.
# ===========================================================================
static func _case_g_rotated_west_run(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = []
	for x in range(6, 11):
		cells.append(Vector2i(x, 10))
	if not _pave(world, failures, "(G)", cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(G)", Buildings.Type.BELT, Vector2i(10, 10), Belt.DIR_W)
	var entry: Building = _place(world, failures, "(G)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(9, 10), Belt.DIR_W)
	var exit_b: Building = _place(world, failures, "(G)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 10), Belt.DIR_W)
	var o: Building = _place(world, failures, "(G)", Buildings.Type.BELT, Vector2i(6, 10), Belt.DIR_W)
	if f == null or entry == null or exit_b == null or o == null:
		_cleanup(world)
		return
	var g_pe: Building = Underground.paired_exit(entry, world)
	_check(failures, g_pe != null and g_pe.anchor == Vector2i(7, 10),
		"(G) PREMISE: the W entry at (9,10) must pair WESTWARD with the exit at the literal (7,10)")

	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(f, Items.Type.GRAIN), "(G) feeder refused GRAIN")
	for _t in 64:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		var due: int = TickSystem.current_tick / Belt.TICKS_PER_SLOT
		var expected: int = int(PATH16[mini(due, PATH16.size() - 1)])
		var occ: Array = _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])
		_check_once(failures, "(G)path",
			occ == [expected],
			"(G) tick %d: westward run expected exactly [%d], got %s — rotation must not change the trajectory's shape, only the cells it maps to"
				% [TickSystem.current_tick, expected, str(occ)])
	_check(failures, _occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)]) == [15],
		"(G) REACHABILITY CONTROL: the item must park at the W downstream belt's front (global slot 15), got %s"
			% str(_occupied_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(o)])))
	_check(failures, _tunnel_of(entry).size() == 4,
		"(G) a gap-1 tunnel is 1 × SLOTS_PER_TILE = the literal 4 slots, got %d" % _tunnel_of(entry).size())
	_cleanup(world)

# ===========================================================================
# (H) THE #14 FEEDER GUARD AT THE EMIT. The belt beyond the exit points
# BACK INTO the exit's cell — it is a feeder, not a sink, and must never be
# delivered to, asserted every tick (an item delivered and later moved would
# leave the end state clean). The refused tunnel item jams at the tunnel
# front: visible backpressure. The adversary's own item parks on its own
# front slot (the exit accepts nothing — it is passive).
# ===========================================================================
static func _case_h_emit_feeder_guard(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = []
	for x in range(9, 14):
		cells.append(Vector2i(x, 10))
	if not _pave(world, failures, "(H)", cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(H)", Buildings.Type.BELT, Vector2i(9, 10), Belt.DIR_E)
	var entry: Building = _place(world, failures, "(H)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 10), Belt.DIR_E)
	var exit_b: Building = _place(world, failures, "(H)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 10), Belt.DIR_E)
	var adv: Building = _place(world, failures, "(H)", Buildings.Type.BELT, Vector2i(13, 10), Belt.DIR_W)
	if f == null or entry == null or exit_b == null or adv == null:
		_cleanup(world)
		return

	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(adv, Items.Type.COAL), "(H) adversary belt refused COAL")
	_check(failures, Belt.try_insert(f, Items.Type.GRAIN), "(H) feeder refused GRAIN")
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(H)guard",
			_count_arrays([_slots_of(adv)]) == 1,
			"(H) the entry delivered onto a belt pointing INTO the exit's cell at tick %d — the #14 feeder guard at the emit did not fire"
				% TickSystem.current_tick)
		_check_once(failures, "(H)conserve",
			_count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(adv)]) == 2,
			"(H) conservation broke at tick %d: 2 items on the layout expected, %d found"
				% [TickSystem.current_tick, _count_arrays([_slots_of(f), _slots_of(entry), _tunnel_of(entry), _slots_of(adv)])])
	_check(failures, _tunnel_of(entry) == [-1, -1, -1, Items.Type.GRAIN],
		"(H) the refused item jams at the tunnel front — visible backpressure, got %s"
			% str(_tunnel_of(entry)))
	_check(failures, _slots_of(adv) == [-1, -1, -1, Items.Type.COAL],
		"(H) the adversary's COAL parks on its own front slot (the passive exit accepts nothing), got %s"
			% str(_slots_of(adv)))
	_cleanup(world)

# ===========================================================================
# (I) INPUT-EDGE REFUSALS. The entry's input edge is its REAR (the cell edge
# opposite the flow) and nothing else: a belt side-feeding from the N and a
# belt pushing head-on into the entry's face are both refused, their items
# parking on their own front slots. The entry is PAIRED here on purpose —
# otherwise the refusals would be the unpaired kind and this would pin the
# wrong gate. The reachability control for this geometry is every flowing
# sub-case above: the same entry type accepts through its real input edge.
# ===========================================================================
static func _case_i_input_edge_refusals(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	if not _pave(world, failures, "(I)", [Vector2i(10, 13), Vector2i(10, 14), Vector2i(11, 14), Vector2i(12, 14)]):
		_cleanup(world)
		return
	var entry: Building = _place(world, failures, "(I)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(10, 14), Belt.DIR_E)
	var exit_b: Building = _place(world, failures, "(I)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 14), Belt.DIR_E)
	var side: Building = _place(world, failures, "(I)", Buildings.Type.BELT, Vector2i(10, 13), Belt.DIR_S)
	var head: Building = _place(world, failures, "(I)", Buildings.Type.BELT, Vector2i(11, 14), Belt.DIR_W)
	if entry == null or exit_b == null or side == null or head == null:
		_cleanup(world)
		return
	_check(failures, Underground.paired_exit(entry, world) != null,
		"(I) PREMISE: the entry must be PAIRED so a refusal is an edge refusal, not an unpaired one")

	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(side, Items.Type.GRAIN), "(I) side belt refused GRAIN")
	_check(failures, Belt.try_insert(head, Items.Type.FLOUR), "(I) head-on belt refused FLOUR")
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(I)edge",
			_count_arrays([_slots_of(entry), _tunnel_of(entry)]) == 0,
			"(I) an item entered the entry through a NON-INPUT edge at tick %d — the input-edge rule did not fire"
				% TickSystem.current_tick)
	_check(failures, _slots_of(side) == [-1, -1, -1, Items.Type.GRAIN],
		"(I) the side-feeding belt parks its GRAIN on its own front slot (refused, visible backpressure), got %s"
			% str(_slots_of(side)))
	_check(failures, _slots_of(head) == [-1, -1, -1, Items.Type.FLOUR],
		"(I) the head-on belt (standing on the covered cell, pushing into the entry's face) parks its FLOUR on its own front slot, got %s"
			% str(_slots_of(head)))
	_cleanup(world)

# ---------- helpers ----------

## A building's surface slots as plain ints, [] if it has none. Reading state
## to COMPARE against a literal is legitimate; the literals never come from
## here.
static func _slots_of(b: Building) -> Array:
	var out: Array = []
	if b == null:
		return out
	for s in b.state.get("slots", []):
		out.append(int(s))
	return out

## The entry's tunnel as plain ints, [] before the first paired advance tick.
static func _tunnel_of(b: Building) -> Array:
	var out: Array = []
	if b == null:
		return out
	for s in b.state.get("tunnel", []):
		out.append(int(s))
	return out

## Global slot indices occupied across `unit_arrays` (each an Array of ints,
## contributing its own length to the running offset), ascending. Variable
## lengths are the point: the tunnel contributes gap × SLOTS_PER_TILE slots.
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
