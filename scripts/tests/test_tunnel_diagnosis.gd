extends RefCounted

## Belt Logistics Session 2, Piece 3 — the tunnel-failure marker's DECISION
## functions. Route A throughout (docs/scoping/visual-verification.md): draw
## bodies cannot execute headless, so this file tests the data that DRIVES the
## drawing — the diagnosis reporter, the blocked-exit predicate, the panel
## strings — plus two source-text structural pins for the render-side
## obligations no headless run can reach.
##
## THE TWO GATE FINDINGS THIS CLOSES (design record, belt-logistics-1.md):
##   - "Gate finding (PAUSE 1)": an unpaired entry is visually
##     indistinguishable from a working one except by the ABSENCE of the
##     dashed indicator — signalling by omission, the silent-compensation
##     shape in UX form.
##   - "Second instance, same gate": a PAIRED exit whose beyond-cell holds no
##     belt jams the tunnel at its front slot — correct end-of-line
##     behaviour, invisible underground.
##
## THE ONE-PREDICATE RULE, EXTENDED TO THE REPORTER. paired_exit stays THE
## pairing predicate. pairing_diagnosis is a REPORTER beside it — it names
## what the axis scan SAW, it never re-answers whether the pair exists. Every
## sub-case therefore asserts (diagnosis.kind == "paired") ==
## (predicate != null): a reporter that disagrees with the predicate is two
## derivations drifting, the exact failure the contract exists to prevent.
##
## Sub-case index
##   1. pairing_diagnosis kinds, BELT family, entry side: paired /
##      out_of_range / wrong_facing / wrong_type / none, each with its
##      distance and panel-line LITERAL, plus nearest-wins classification and
##      the bounded overshoot (an exit 8 tiles out reads "none", not a hint).
##   2. pairing_diagnosis kinds, PIPE family — including the spec's exact
##      cross-family line ("That is a belt tunnel exit — pipe tunnels need a
##      pipe exit"), and exit_blocked == false on a healthy PIPE exit (pipes
##      carry no volume; the blocked state does not exist for them).
##   3. EXIT-side diagnosis (the backward scan): both halves of an incomplete
##      tunnel must say so, with entry/exit wording swapped.
##   4. GAP-0 PIPE TRUTHFUL COEXISTENCE: adjacent pipe halves do not pair
##      (a tunnel must span something — RATIFIED) but fluid STILL crosses
##      (both carriers, cardinal neighbours). The panel must say UNPAIRED
##      without claiming the network is cut, beside "Fluid: pump reachable".
##      Pinned as a whole-array literal.
##   5. BLOCKED-EXIT PREDICATE, built through the REAL tick path (the
##      false-negative repro rule: the item walks lane and tunnel and jams at
##      the front slot with the beyond-cell empty — the live-traced gate
##      state — before the detector is asked anything).
##   6. Structural pins, source-text and comment-aware (test_doodads.gd's
##      route-A precedent): the indicator pass iterates EXIT_TYPE_FOR_ENTRY
##      (closing the pipe filter gap — pipes had NO dashed indicator at all),
##      and _fluid_active no longer pre-filters on `!= Type.PIPE` (the known
##      gap the design record left for Piece 3 by name).
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL — kinds, distances, dir ints, whole
## panel lines. Nothing here asks Underground for its own expectation.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const GRID_WORLD_PATH: String = "res://scripts/world/grid_world.gd"
const BUILDINGS_PATH: String = "res://scripts/world/buildings.gd"

static func test_name() -> String:
	return "tunnel-failure diagnosis (pairing_diagnosis both families + exit side, reporter never disagrees with paired_exit, gap-0 truthful coexistence, blocked exit via the real jam, indicator/_fluid_active structural pins)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_1_belt_entry_kinds(parent, failures)
	_case_2_pipe_family_kinds(parent, failures)
	_case_3_exit_side(parent, failures)
	_case_4_gap0_pipe_coexistence(parent, failures)
	_case_5_blocked_exit_jam(parent, failures)
	_case_6_structural_pins(failures)
	if failures.is_empty():
		return { "ok": true, "message": "6 sub-cases pass: belt-entry diagnosis kinds + literals, pipe-family kinds + cross-family line, exit-side backward scan, gap-0 truthful coexistence, blocked-exit via the real jam path, both structural pins" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) BELT ENTRY DIAGNOSIS KINDS. Entry at (4,10) facing E in every layout;
# what sits ahead varies. Distances are anchor-to-anchor tiles — the same k
# the pairing scan walks (k = 2..4 pairs; the gate finding's own trace spoke
# of "distance 5, out of range" in exactly this unit).
# ===========================================================================
static func _case_1_belt_entry_kinds(parent: Node, failures: Array) -> void:
	# (1a) paired — exit at k=3.
	var diag: Dictionary = _belt_entry_diag(parent, failures, "(1a)",
		[[Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 10), Belt.DIR_E]])
	_check(failures, String(diag.get("kind", "")) == "paired",
		"(1a) an exit 3 tiles ahead facing E pairs: kind must be the literal \"paired\", got \"%s\"" % String(diag.get("kind", "")))
	_check(failures, int(diag.get("distance", -1)) == 3,
		"(1a) paired distance must be the literal 3 (anchor tiles), got %s" % str(diag.get("distance", "absent")))
	_check(failures, diag.get("partner", Vector2i(-999, -999)) == Vector2i(7, 10),
		"(1a) paired partner must be the literal (7, 10), got %s" % str(diag.get("partner", "absent")))

	# (1b) out_of_range — exit at k=5, one past the scan (max k = 4). This IS
	# the recorded gate finding: entry/exit distance 5, refuse-when-unpaired
	# healthy, and nothing on screen says why.
	diag = _belt_entry_diag(parent, failures, "(1b)",
		[[Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E]])
	_check(failures, String(diag.get("kind", "")) == "out_of_range",
		"(1b) a right-type right-dir exit 5 tiles ahead is beyond the span: kind must be the literal \"out_of_range\", got \"%s\" — this is the PAUSE-1 gate finding's exact layout, and \"nothing found\" here would repeat the omission the marker exists to close" % String(diag.get("kind", "")))
	_check(failures, int(diag.get("distance", -1)) == 5,
		"(1b) out_of_range distance must be the literal 5, got %s" % str(diag.get("distance", "absent")))

	# (1c) wrong_facing — exit at k=3 facing S. The OTHER player error: not
	# too far, rotated. The two errors have different fixes (move closer vs
	# rotate/replace) and must not collapse into one message.
	diag = _belt_entry_diag(parent, failures, "(1c)",
		[[Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 10), Belt.DIR_S]])
	_check(failures, String(diag.get("kind", "")) == "wrong_facing",
		"(1c) a right-type exit 3 tiles ahead facing S is in range but rotated: kind must be the literal \"wrong_facing\", got \"%s\"" % String(diag.get("kind", "")))
	_check(failures, int(diag.get("distance", -1)) == 3,
		"(1c) wrong_facing distance must be the literal 3, got %s" % str(diag.get("distance", "absent")))
	_check(failures, int(diag.get("seen_dir", -1)) == 1,
		"(1c) wrong_facing seen_dir must be the literal 1 (DIR_S), got %s" % str(diag.get("seen_dir", "absent")))

	# (1d) wrong_type — a PIPE exit ahead of a BELT entry. The family refusal
	# is the EXIT_TYPE_FOR_ENTRY table (P4); the diagnosis names the confusion
	# instead of reporting empty ground.
	diag = _belt_entry_diag(parent, failures, "(1d)",
		[[Buildings.Type.UNDERGROUND_PIPE_EXIT, Vector2i(7, 10), Belt.DIR_E]])
	_check(failures, String(diag.get("kind", "")) == "wrong_type",
		"(1d) a PIPE exit 3 tiles ahead of a BELT entry is the cross-family error: kind must be the literal \"wrong_type\", got \"%s\"" % String(diag.get("kind", "")))
	_check(failures, int(diag.get("seen_type", -1)) == 40,
		"(1d) wrong_type seen_type must be the on-disk literal 40 (UNDERGROUND_PIPE_EXIT), got %s" % str(diag.get("seen_type", "absent")))

	# (1e) none — a lone entry.
	diag = _belt_entry_diag(parent, failures, "(1e)", [])
	_check(failures, String(diag.get("kind", "")) == "none",
		"(1e) a lone entry sees nothing: kind must be the literal \"none\", got \"%s\"" % String(diag.get("kind", "")))

	# (1f) nearest-wins classification: a wrong-facing exit at k=3 AND a
	# right exit at k=5. The in-range finding is the actionable one — the
	# player's nearest mistake — and must win over the out-of-range hint.
	diag = _belt_entry_diag(parent, failures, "(1f)",
		[[Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 10), Belt.DIR_S],
		 [Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E]])
	_check(failures, String(diag.get("kind", "")) == "wrong_facing" and int(diag.get("distance", -1)) == 3,
		"(1f) with a wrong-facing exit at 3 tiles AND a right exit at 5, the IN-RANGE finding wins: expected wrong_facing at 3, got \"%s\" at %s" % [String(diag.get("kind", "")), str(diag.get("distance", "absent"))])

	# (1g) the overshoot is BOUNDED: a right exit 8 tiles out reads "none".
	# The hint scans a few tiles past the span, not the whole axis.
	diag = _belt_entry_diag(parent, failures, "(1g)",
		[[Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(12, 10), Belt.DIR_E]])
	_check(failures, String(diag.get("kind", "")) == "none",
		"(1g) an exit 8 tiles ahead is beyond the bounded out-of-range hint (span 3 + overshoot 3 = max k 7): kind must be \"none\", got \"%s\" — an unbounded axis scan would hint at exits across the map" % String(diag.get("kind", "")))

	# --- the panel-line literals for the three unpaired kinds (1b/1c/1e),
	# rebuilt fresh so each line is asserted against its own layout.
	_check_line(parent, failures, "(1b-line)",
		[[Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 10), Belt.DIR_E]],
		"Exit found at 5 tiles — max span 3")
	_check_line(parent, failures, "(1c-line)",
		[[Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 10), Belt.DIR_S]],
		"Exit at 3 tiles faces S — must face E")
	_check_line(parent, failures, "(1d-line)",
		[[Buildings.Type.UNDERGROUND_PIPE_EXIT, Vector2i(7, 10), Belt.DIR_E]],
		"That is a pipe tunnel exit — belt tunnels need a belt exit")
	_check_line(parent, failures, "(1e-line)", [],
		"No exit within span (3)")

# ===========================================================================
# (2) PIPE FAMILY. The same reporter, the other table row — including the
# spec's exact cross-family sentence, and the pipes-cannot-jam pin.
# ===========================================================================
static func _case_2_pipe_family_kinds(parent: Node, failures: Array) -> void:
	# (2a) a BELT exit ahead of a PIPE entry → wrong_type, with the exact
	# sentence from the design brief.
	var world = _make_world(parent)
	if _pave(world, failures, "(2a)", _row_cells(4, 12, 20)):
		var entry: Building = _place(world, failures, "(2a)", Buildings.Type.UNDERGROUND_PIPE_ENTRY, Vector2i(4, 20), Belt.DIR_E)
		_place(world, failures, "(2a)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 20), Belt.DIR_E)
		if entry != null:
			var diag: Dictionary = _diag_agreeing(world, entry, failures, "(2a)")
			_check(failures, String(diag.get("kind", "")) == "wrong_type",
				"(2a) a BELT exit 3 tiles ahead of a PIPE entry: kind must be \"wrong_type\", got \"%s\"" % String(diag.get("kind", "")))
			_check(failures, int(diag.get("seen_type", -1)) == 36,
				"(2a) seen_type must be the on-disk literal 36 (UNDERGROUND_BELT_EXIT), got %s" % str(diag.get("seen_type", "absent")))
			_check(failures, Underground.diagnosis_line(entry, diag) == "That is a belt tunnel exit — pipe tunnels need a pipe exit",
				"(2a) the cross-family line must be the design brief's exact sentence \"That is a belt tunnel exit — pipe tunnels need a pipe exit\", got \"%s\"" % Underground.diagnosis_line(entry, diag))
	_cleanup(world)

	# (2b) out_of_range for pipes, same literal shape as belts — one
	# vocabulary for both families.
	world = _make_world(parent)
	if _pave(world, failures, "(2b)", _row_cells(4, 12, 20)):
		var entry2: Building = _place(world, failures, "(2b)", Buildings.Type.UNDERGROUND_PIPE_ENTRY, Vector2i(4, 20), Belt.DIR_E)
		_place(world, failures, "(2b)", Buildings.Type.UNDERGROUND_PIPE_EXIT, Vector2i(9, 20), Belt.DIR_E)
		if entry2 != null:
			var diag2: Dictionary = _diag_agreeing(world, entry2, failures, "(2b)")
			_check(failures, String(diag2.get("kind", "")) == "out_of_range" and int(diag2.get("distance", -1)) == 5,
				"(2b) a pipe exit 5 tiles ahead: kind \"out_of_range\" at distance 5, got \"%s\" at %s" % [String(diag2.get("kind", "")), str(diag2.get("distance", "absent"))])
			_check(failures, Underground.diagnosis_line(entry2, diag2) == "Exit found at 5 tiles — max span 3",
				"(2b) the pipe out-of-range line must be \"Exit found at 5 tiles — max span 3\", got \"%s\"" % Underground.diagnosis_line(entry2, diag2))
	_cleanup(world)

	# (2c) a healthy paired pipe: kind "paired", and exit_blocked is FALSE —
	# pipes carry no volume, so the blocked state does not exist for them.
	world = _make_world(parent)
	if _pave(world, failures, "(2c)", _row_cells(4, 12, 20)):
		var entry3: Building = _place(world, failures, "(2c)", Buildings.Type.UNDERGROUND_PIPE_ENTRY, Vector2i(4, 20), Belt.DIR_E)
		var pexit: Building = _place(world, failures, "(2c)", Buildings.Type.UNDERGROUND_PIPE_EXIT, Vector2i(6, 20), Belt.DIR_E)
		if entry3 != null and pexit != null:
			var diag3: Dictionary = _diag_agreeing(world, entry3, failures, "(2c)")
			_check(failures, String(diag3.get("kind", "")) == "paired" and int(diag3.get("distance", -1)) == 2,
				"(2c) a pipe exit 2 tiles ahead pairs: kind \"paired\" at distance 2, got \"%s\" at %s" % [String(diag3.get("kind", "")), str(diag3.get("distance", "absent"))])
			_check(failures, Underground.exit_blocked(pexit, world) == false,
				"(2c) exit_blocked on a paired PIPE exit must be false — a pipe tunnel carries nothing, so there is no jam state to detect; inventing one would draw a fault on a healthy network")
	_cleanup(world)

# ===========================================================================
# (3) EXIT-SIDE DIAGNOSIS — the backward scan. Both halves of an incomplete
# tunnel must say so: the stub and the panel line point back toward where the
# missing entry would be, with the entry/exit wording swapped.
# ===========================================================================
static func _case_3_exit_side(parent: Node, failures: Array) -> void:
	# (3a) a lone exit → none, with the exit-side wording.
	var world = _make_world(parent)
	if _pave(world, failures, "(3a)", _row_cells(4, 12, 30)):
		var lone: Building = _place(world, failures, "(3a)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 30), Belt.DIR_E)
		if lone != null:
			var diag: Dictionary = _diag_agreeing(world, lone, failures, "(3a)")
			_check(failures, String(diag.get("kind", "")) == "none",
				"(3a) a lone EXIT sees nothing behind it: kind must be \"none\", got \"%s\"" % String(diag.get("kind", "")))
			_check(failures, Underground.diagnosis_line(lone, diag) == "No entry within span (3)",
				"(3a) the exit-side none line must be \"No entry within span (3)\", got \"%s\"" % Underground.diagnosis_line(lone, diag))
	_cleanup(world)

	# (3b) entry 5 tiles behind → out_of_range from the exit's side too. One
	# incomplete tunnel, two truthful halves.
	world = _make_world(parent)
	if _pave(world, failures, "(3b)", _row_cells(4, 12, 30)):
		var entry: Building = _place(world, failures, "(3b)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(4, 30), Belt.DIR_E)
		var exit_b: Building = _place(world, failures, "(3b)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 30), Belt.DIR_E)
		if entry != null and exit_b != null:
			var diag2: Dictionary = _diag_agreeing(world, exit_b, failures, "(3b)")
			_check(failures, String(diag2.get("kind", "")) == "out_of_range" and int(diag2.get("distance", -1)) == 5,
				"(3b) the exit's backward scan finds the entry 5 tiles behind: kind \"out_of_range\" at distance 5, got \"%s\" at %s" % [String(diag2.get("kind", "")), str(diag2.get("distance", "absent"))])
			_check(failures, Underground.diagnosis_line(exit_b, diag2) == "Entry found at 5 tiles — max span 3",
				"(3b) the exit-side out-of-range line must be \"Entry found at 5 tiles — max span 3\", got \"%s\"" % Underground.diagnosis_line(exit_b, diag2))
	_cleanup(world)

	# (3c) paired from the exit's side: paired_entry finds the entry, the
	# reporter agrees, and BOTH halves report kind "paired".
	world = _make_world(parent)
	if _pave(world, failures, "(3c)", _row_cells(4, 12, 30)):
		var entry2: Building = _place(world, failures, "(3c)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(4, 30), Belt.DIR_E)
		var exit2: Building = _place(world, failures, "(3c)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 30), Belt.DIR_E)
		if entry2 != null and exit2 != null:
			var pe: Building = Underground.paired_entry(exit2, world)
			_check(failures, pe != null and pe.anchor == Vector2i(4, 30),
				"(3c) paired_entry must find the entry at the literal (4, 30) — and it must find it THROUGH paired_exit, never a second scan; got %s" % (str(pe.anchor) if pe != null else "null"))
			var diag3: Dictionary = _diag_agreeing(world, exit2, failures, "(3c)")
			_check(failures, String(diag3.get("kind", "")) == "paired" and diag3.get("partner", Vector2i(-999, -999)) == Vector2i(4, 30),
				"(3c) the exit's diagnosis: kind \"paired\" with partner (4, 30), got \"%s\" partner %s" % [String(diag3.get("kind", "")), str(diag3.get("partner", "absent"))])
	_cleanup(world)

	# (3d) wrong_facing from the exit's side: a rotated entry 3 tiles behind.
	world = _make_world(parent)
	if _pave(world, failures, "(3d)", _row_cells(4, 12, 30)):
		var entry3: Building = _place(world, failures, "(3d)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(4, 30), Belt.DIR_S)
		var exit3: Building = _place(world, failures, "(3d)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 30), Belt.DIR_E)
		if entry3 != null and exit3 != null:
			var diag4: Dictionary = _diag_agreeing(world, exit3, failures, "(3d)")
			_check(failures, String(diag4.get("kind", "")) == "wrong_facing" and int(diag4.get("distance", -1)) == 3 and int(diag4.get("seen_dir", -1)) == 1,
				"(3d) an entry 3 tiles behind facing S: kind \"wrong_facing\" at 3 with seen_dir 1, got \"%s\" at %s seen_dir %s" % [String(diag4.get("kind", "")), str(diag4.get("distance", "absent")), str(diag4.get("seen_dir", "absent"))])
			_check(failures, Underground.diagnosis_line(exit3, diag4) == "Entry at 3 tiles faces S — must face E",
				"(3d) the exit-side wrong-facing line must be \"Entry at 3 tiles faces S — must face E\", got \"%s\"" % Underground.diagnosis_line(exit3, diag4))
	_cleanup(world)

	# (3e) wrong_type from the exit's side: a PIPE entry behind a BELT exit.
	world = _make_world(parent)
	if _pave(world, failures, "(3e)", _row_cells(4, 12, 30)):
		var pentry: Building = _place(world, failures, "(3e)", Buildings.Type.UNDERGROUND_PIPE_ENTRY, Vector2i(4, 30), Belt.DIR_E)
		var exit4: Building = _place(world, failures, "(3e)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(7, 30), Belt.DIR_E)
		if pentry != null and exit4 != null:
			var diag5: Dictionary = _diag_agreeing(world, exit4, failures, "(3e)")
			_check(failures, String(diag5.get("kind", "")) == "wrong_type" and int(diag5.get("seen_type", -1)) == 39,
				"(3e) a PIPE entry 3 tiles behind a BELT exit: kind \"wrong_type\" with seen_type 39, got \"%s\" seen_type %s" % [String(diag5.get("kind", "")), str(diag5.get("seen_type", "absent"))])
			_check(failures, Underground.diagnosis_line(exit4, diag5) == "That is a pipe tunnel entry — belt tunnels need a belt entry",
				"(3e) the exit-side cross-family line must be \"That is a pipe tunnel entry — belt tunnels need a belt entry\", got \"%s\"" % Underground.diagnosis_line(exit4, diag5))
	_cleanup(world)

# ===========================================================================
# (4) GAP-0 PIPE — THE TRUTHFUL-COEXISTENCE PIN. Standard pump run (the
# test_underground_pipe.gd row shape): water, pump, two pipes, entry (4,0),
# exit ADJACENT at (5,0), far pipe (6,0), probe (7,0). The pair does not
# pair (a tunnel must span something — RATIFIED) yet fluid crosses (both
# halves are carriers and cardinal neighbours). The panel must hold all
# three truths at once: UNPAIRED, what the scan saw, and pump-reachable —
# and must NOT claim "the network is cut here", because it is not.
# ===========================================================================
static func _case_4_gap0_pipe_coexistence(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var water := Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.tiles[Vector2i(0, 0)] = water
	world.tile_modifications[Vector2i(0, 0)] = water
	for x in range(1, 7):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
	var ok: bool = _place(world, failures, "(4)", Buildings.Type.PUMP, Vector2i(1, 0), 0) != null \
		and _place(world, failures, "(4)", Buildings.Type.PIPE, Vector2i(2, 0), 0) != null \
		and _place(world, failures, "(4)", Buildings.Type.PIPE, Vector2i(3, 0), 0) != null
	var entry: Building = _place(world, failures, "(4)", Buildings.Type.UNDERGROUND_PIPE_ENTRY, Vector2i(4, 0), Belt.DIR_E)
	var exit_b: Building = _place(world, failures, "(4)", Buildings.Type.UNDERGROUND_PIPE_EXIT, Vector2i(5, 0), Belt.DIR_E)
	ok = ok and _place(world, failures, "(4)", Buildings.Type.PIPE, Vector2i(6, 0), 0) != null
	if not ok or entry == null or exit_b == null:
		_cleanup(world)
		return

	# The two premises whose combination is the whole point.
	_check(failures, Underground.paired_exit(entry, world) == null,
		"(4) PREMISE: adjacent halves must NOT pair (k starts at 2 — a tunnel must span something)")
	_check(failures, world.fluid_available_at(Vector2i(7, 0)),
		"(4) PREMISE: fluid must still cross the adjacency — both halves are carriers and cardinal neighbours; the probe at (7, 0) reads false")

	var diag: Dictionary = _diag_agreeing(world, entry, failures, "(4)")
	_check(failures, String(diag.get("kind", "")) == "none",
		"(4) the gap-0 neighbour sits at k=1, outside the scan: kind must be \"none\", got \"%s\"" % String(diag.get("kind", "")))

	# THE PIN: the whole panel, as one literal array. UNPAIRED without a cut
	# claim, the diagnosis line, and the live fluid line — all at once.
	var lines: Array = Underground.info_lines(entry, world)
	var expected: Array = [
		"Facing: E (pairing axis — fluid itself is undirected)",
		"Carries nothing: one edge in the fluid network.",
		"UNPAIRED — no tunnel edge",
		"No exit within span (3)",
		"Fluid: pump reachable",
	]
	_check(failures, lines == expected,
		"(4) THE COEXISTENCE PIN: the gap-0 entry's panel must be exactly %s — UNPAIRED (the tunnel IS incomplete) beside \"Fluid: pump reachable\" (the network is NOT cut), with no line claiming a cut. Got %s" % [str(expected), str(lines)])

	# The exit half tells the same coexisting truths, exit-side wording.
	var exit_lines: Array = Underground.info_lines(exit_b, world)
	var exit_expected: Array = [
		"Facing: E (pairing axis — fluid itself is undirected)",
		"Carries nothing: one edge in the fluid network.",
		"Passive half — the entry owns the pairing scan.",
		"UNPAIRED — no tunnel edge",
		"No entry within span (3)",
		"Fluid: pump reachable",
	]
	_check(failures, exit_lines == exit_expected,
		"(4) the exit half's panel must be exactly %s, got %s" % [str(exit_expected), str(exit_lines)])
	_cleanup(world)

# ===========================================================================
# (5) THE BLOCKED-EXIT PREDICATE, VIA THE REAL JAM. The live-traced second
# gate instance rebuilt end-to-end: feeder → entry → gap-3 tunnel → exit
# with NOTHING beyond. One item walks the whole lane and tunnel through the
# REAL tick path and stalls at the tunnel's front slot — asserted as a slot
# literal, so the detector is only asked about a jam that verifiably reached
# the mechanism (the false-negative repro rule). Then the missing belt is
# placed and the detector must clear IMMEDIATELY (before any tick — the
# fault is the outlet, and the outlet is fixed), and the item must arrive.
# ===========================================================================
static func _case_5_blocked_exit_jam(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = _row_cells(4, 11, 40)
	if not _pave(world, failures, "(5)", cells):
		_cleanup(world)
		return
	var f: Building = _place(world, failures, "(5)", Buildings.Type.BELT, Vector2i(4, 40), Belt.DIR_E)
	var entry: Building = _place(world, failures, "(5)", Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(5, 40), Belt.DIR_E)
	var exit_b: Building = _place(world, failures, "(5)", Buildings.Type.UNDERGROUND_BELT_EXIT, Vector2i(9, 40), Belt.DIR_E)
	if f == null or entry == null or exit_b == null:
		_cleanup(world)
		return

	_check(failures, Underground.exit_blocked(exit_b, world) == false,
		"(5) an EMPTY paired tunnel with no belt beyond is not blocked — nothing is jammed yet; a detector that fires here cries wolf on every freshly built tunnel")

	TickSystem.current_tick = 0
	_check(failures, Belt.try_insert(f, Items.Type.GRAIN), "(5) PREMISE: feeder belt refused GRAIN")
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	# The jam must have REACHED THE MECHANISM: the item sits in the tunnel's
	# front slot (gap 3 → 12 slots, front index 11), exactly where post_tick
	# fails to deliver it.
	var tunnel: Array = entry.state.get("tunnel", [])
	_check(failures, tunnel.size() == 12 and int(tunnel[11]) == Items.Type.GRAIN,
		"(5) PREMISE: after 200 ticks the item must be jammed in the tunnel's front slot (index 11 of the literal 12), got %s — if the item never reaches the mechanism, a green detector proves nothing" % str(tunnel))
	_check(failures, Underground.exit_blocked(exit_b, world) == true,
		"(5) THE CASE. The tunnel front holds an item and the beyond-cell (10, 40) is empty — the live-traced gate state: correct end-of-line behaviour, invisible underground. exit_blocked must be true, and false here means the failure marker reads some other state than the real jam")

	# Fix the outlet: the detector clears BEFORE any tick — the blocked state
	# IS "the beyond-cell cannot receive", and now it can.
	var o: Building = _place(world, failures, "(5)", Buildings.Type.BELT, Vector2i(10, 40), Belt.DIR_E)
	if o == null:
		_cleanup(world)
		return
	_check(failures, Underground.exit_blocked(exit_b, world) == false,
		"(5) placing the missing belt clears the detector immediately (no tick needed) — the tint must drop the instant the outlet exists, or the player reads their own fix as having failed")
	for _t in 8:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var delivered: int = 0
	for s in o.state.get("slots", []):
		if int(s) >= 0:
			delivered += 1
	_check(failures, delivered == 1 and int(entry.state.get("tunnel", [])[11]) == -1,
		"(5) REACHABILITY CONTROL: after the fix the jammed item must actually surface onto the new belt (1 item on it, tunnel front empty) — got %d on the belt, tunnel %s" % [delivered, str(entry.state.get("tunnel", []))])

	# #14 coherence: a belt on the beyond-cell pointing back INTO the exit is
	# a feeder, not a sink — the detector must agree with _try_deliver's own
	# guard and stay blocked.
	_check(failures, world.remove_building_at(Vector2i(10, 40)),
		"(5) PREMISE: could not remove the outgoing belt")
	var back: Building = _place(world, failures, "(5)", Buildings.Type.BELT, Vector2i(10, 40), Belt.DIR_W)
	if back != null:
		# Re-jam: feed a second item to the front (the first is gone).
		_check(failures, Belt.try_insert(f, Items.Type.WHEAT), "(5) PREMISE: feeder refused WHEAT")
		for _t in 200:
			TickSystem.current_tick += 1
			TickSystem.tick.emit(TickSystem.current_tick)
		_check(failures, Underground.exit_blocked(exit_b, world) == true,
			"(5) a belt pointing back INTO the exit is a #14 feeder, not a sink: delivery refuses it, so the detector must read blocked — a detector that only checks \"is there a belt\" diverges from where items actually flow")
	_cleanup(world)

# ===========================================================================
# (6) STRUCTURAL PINS — source-text, comment-aware (comments are stripped
# before searching, so prose mentioning the forbidden text cannot mask it and
# a code mention cannot hide in prose).
#
#   6a. The indicator pass iterates EXIT_TYPE_FOR_ENTRY and does not hardcode
#       the belt entry type. The pre-Piece-3 pass filtered on
#       `b.type != Buildings.Type.UNDERGROUND_BELT_ENTRY`, which is why PIPE
#       tunnels had NO dashed indicator at all — a working pipe tunnel was
#       invisible, the omission shape verbatim.
#   6b. _fluid_active no longer contains the `!= Type.PIPE` pre-filter — the
#       gap the design record left for Piece 3 BY NAME: a machine fed off a
#       tunnel mouth drew a dark fluid port while fluid arrived.
#       is_pipe_in_pump_component already answers false for non-members, so
#       the deletion is the whole fix.
# ===========================================================================
static func _case_6_structural_pins(failures: Array) -> void:
	var gw: String = FileAccess.get_file_as_string(GRID_WORLD_PATH)
	if gw == "":
		_check(failures, false, "(6) could not read %s" % GRID_WORLD_PATH)
		return
	var pass_body: String = _strip_comments(_func_body(gw, "func _draw_underground_pair_indicators()"))
	_check(failures, pass_body != "",
		"(6a) grid_world.gd must still define func _draw_underground_pair_indicators() — the dedicated-pass contract lives in test_underground_indicator_contract.gd; this pin only needs the body to exist")
	_check(failures, pass_body.find("EXIT_TYPE_FOR_ENTRY") >= 0,
		"(6a) the indicator pass must select tunnel halves by membership in Underground.EXIT_TYPE_FOR_ENTRY — the family table P4 made a lookup — so a new tunnel family gets its indicator for free. A hardcoded type check here is the exact filter that left PIPE tunnels with no dashed indicator at all")
	_check(failures, pass_body.find("Type.UNDERGROUND_BELT_ENTRY") < 0,
		"(6a) the indicator pass must NOT hardcode Type.UNDERGROUND_BELT_ENTRY — that is the pre-Piece-3 belt-only filter; membership in EXIT_TYPE_FOR_ENTRY is the rule")

	var bsrc: String = FileAccess.get_file_as_string(BUILDINGS_PATH)
	if bsrc == "":
		_check(failures, false, "(6) could not read %s" % BUILDINGS_PATH)
		return
	var fluid_body: String = _strip_comments(_func_body(bsrc, "static func _fluid_active("))
	_check(failures, fluid_body != "",
		"(6b) buildings.gd must still define _fluid_active — if the helper was renamed, move this pin with it")
	_check(failures, fluid_body.find("!= Type.PIPE") < 0,
		"(6b) _fluid_active must no longer pre-filter on `nb.type != Type.PIPE` — that check made a machine fed off a tunnel mouth draw a dark fluid port while fluid arrived (the design record's named Piece-3 gap). is_pipe_in_pump_component answers false for non-members on its own")
	_check(failures, fluid_body.find("is_pipe_in_pump_component") >= 0,
		"(6b) positive control: _fluid_active must still answer via is_pipe_in_pump_component — if the port indicator stopped asking the fluid resolver, this pin's negative above proves nothing")

# ---------- fixtures ----------

## Diagnose `b` AND assert the one-predicate agreement in the same breath:
## (kind == "paired") must equal what THE predicate says, on every layout this
## file builds. paired_exit answers for entries; paired_entry (itself
## contracted to answer through paired_exit) answers for exits.
static func _diag_agreeing(world, b: Building, failures: Array, tag: String) -> Dictionary:
	var diag: Dictionary = Underground.pairing_diagnosis(b, world)
	var predicate_paired: bool
	if Underground.EXIT_TYPE_FOR_ENTRY.has(b.type):
		predicate_paired = Underground.paired_exit(b, world) != null
	else:
		predicate_paired = Underground.paired_entry(b, world) != null
	_check(failures, (String(diag.get("kind", "")) == "paired") == predicate_paired,
		"%s THE REPORTER MUST NEVER DISAGREE WITH THE PREDICATE: diagnosis kind \"%s\" but the pairing predicate says %s — pairing_diagnosis is a reporter BESIDE paired_exit, never a second answer to whether the pair exists; a desync is two derivations drifting, the failure the one-predicate contract exists to prevent" % [tag, String(diag.get("kind", "")), "paired" if predicate_paired else "unpaired"])
	return diag

## Build a belt ENTRY at (4,10) facing E plus the given extra buildings
## ([type, pos, dir] rows), run the agreement check, return the diagnosis.
static func _belt_entry_diag(parent: Node, failures: Array, tag: String, extras: Array) -> Dictionary:
	var world = _make_world(parent)
	var diag: Dictionary = {}
	if _pave(world, failures, tag, _row_cells(4, 13, 10)):
		var entry: Building = _place(world, failures, tag, Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(4, 10), Belt.DIR_E)
		var ok: bool = entry != null
		for row in extras:
			ok = ok and _place(world, failures, tag, row[0], row[1], row[2]) != null
		if ok:
			diag = _diag_agreeing(world, entry, failures, tag)
	_cleanup(world)
	return diag

## Same layout builder, asserting the entry's panel diagnosis LINE literal.
static func _check_line(parent: Node, failures: Array, tag: String, extras: Array, expected: String) -> void:
	var world = _make_world(parent)
	if _pave(world, failures, tag, _row_cells(4, 13, 10)):
		var entry: Building = _place(world, failures, tag, Buildings.Type.UNDERGROUND_BELT_ENTRY, Vector2i(4, 10), Belt.DIR_E)
		var ok: bool = entry != null
		for row in extras:
			ok = ok and _place(world, failures, tag, row[0], row[1], row[2]) != null
		if ok:
			var got: String = Underground.diagnosis_line(entry, Underground.pairing_diagnosis(entry, world))
			_check(failures, got == expected,
				"%s the panel line must be the literal \"%s\", got \"%s\" — the two player errors (move closer vs rotate/replace) and the two vocabularies (belt/pipe, entry/exit) must stay distinguishable in the Q-inspect text" % [tag, expected, got])
			# ... and info_lines must actually CARRY it (the panel is the
			# delivery vehicle; a correct line nobody surfaces is omission
			# with extra steps).
			_check(failures, Underground.info_lines(entry, world).has(expected),
				"%s info_lines on the unpaired entry must include the diagnosis line \"%s\", got %s" % [tag, expected, str(Underground.info_lines(entry, world))])
	_cleanup(world)

static func _row_cells(x0: int, x1: int, y: int) -> Array:
	var out: Array = []
	for x in range(x0, x1):
		out.append(Vector2i(x, y))
	return out

## The body of the function whose signature starts with `sig`, from the
## signature to the next top-level func declaration (or end of file).
static func _func_body(src: String, sig: String) -> String:
	var start: int = src.find(sig)
	if start < 0:
		return ""
	var end_a: int = src.find("\nfunc ", start + 1)
	var end_b: int = src.find("\nstatic func ", start + 1)
	var end: int = end_a
	if end < 0 or (end_b >= 0 and end_b < end):
		end = end_b
	if end < 0:
		return src.substr(start)
	return src.substr(start, end - start)

## Comment-aware: everything from the first `#` of each line is dropped
## before searching. (Neither pinned body puts a `#` inside a string literal,
## so the naive cut is exact here.)
static func _strip_comments(body: String) -> String:
	var out: Array = []
	for line in body.split("\n"):
		var hash_idx: int = String(line).find("#")
		out.append(String(line).substr(0, hash_idx) if hash_idx >= 0 else String(line))
	return "\n".join(out)

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

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing (queue_free is deferred past the runner's
## synchronous run()) — test_underground_pipe.gd's _teardown shape.
static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
