extends RefCounted

## Pole tiers (Electricity Session 3) — parametric POLE_RANGE_BY_TYPE /
## SUPPLY_RADIUS_BY_TYPE, either-reaches connection, multi-cell poles,
## per-tier supply areas.
##
## NOT the nearest-pole tie-break, which an earlier draft of this line
## advertised. No sub-case exercises it and none CAN: any two poles covering
## one cell are already in the same component, so every candidate answers with
## the same id — see the invariant proved in _covering_component_id's
## docstring. Claiming coverage this file cannot have is worse than claiming
## none.
##
## Sub-case index (each task appends its own _case_* and wires it into run()):
##   1. POWER_NETWORK_TYPES / POLE_TYPES membership (Task 1).
##   2. Registration — DATA rows, footprints, placement (Task 2).
##   3. Either-reaches — the max() connection rule, at every tier boundary
##      distance (Task 4).
##   4. Order independence — the predicate is symmetric, so a MIRRORED layout
##      groups identically even though the lex-sorted walk reaches the tiers in
##      the opposite order (Task 4).
##   5. The predicate IS the graph — the BFS components are exactly the
##      connected components of PowerNetwork.poles_connected, the same function
##      grid_world._draw_power_wires calls to decide what to draw (Task 4).
##   6. Multi-cell supply symmetry — the 2x2 substation's supply area is
##      projected from all FOUR of its cells, so it reaches equally far east
##      and west (Task 5).
##   7. The consumer paths agree, and they agree at the WIDE radius — a lamp
##      inside a medium pole's radius 2 both reads as powered AND lands in the
##      component's demand total (Task 5).
##   8. The generator path sees the new tiers — a steam generator flush against
##      a substation feeds its supply in (Task 5).
##   9. The panel row that renders the tier table still FITS the info panel —
##      adding a tier widens a player-facing string (Task 5 review).

# Used from Task 2 on: the world-building sub-cases instantiate GridWorld
# through _make_world(parent).
const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const HotbarScript = preload("res://scripts/ui/hotbar.gd")
# Sub-case (9) reads LINE_BUDGET / BODY_FONT_SIZE off the panel itself rather
# than restating them, so the guard and the thing guarded cannot drift.
const InfoPanelScript = preload("res://scripts/ui/info_panel.gd")

## Short on purpose, and NO LONGER AN ENUMERATION. The sub-case index in this
## file's header is the list, and it is the thing that stays accurate — a name
## that concatenates every sub-case grows unreadable across Tasks 5-7 and
## drifts the moment one is added without renaming. Which is exactly what
## happened: this read "tables + either-reaches + shared predicate" while Task
## 5 added three sub-cases and the review a fourth, so the three named had
## become the minority and the name argued against its own docstring. Failures
## print their own "(N) ..." prefix, so the runner line never needs to say what
## passed.
static func test_name() -> String:
	return "pole tiers"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_network_type_set(failures)
	_case_registration(parent, failures)
	_case_either_reaches(parent, failures)
	_case_order_independence(parent, failures)
	_case_predicate_is_the_graph(parent, failures)
	_case_multicell_supply_symmetry(parent, failures)
	_case_consumer_paths_agree(parent, failures)
	_case_generator_against_substation(parent, failures)
	_case_reach_row_fits_panel(failures)
	if failures.is_empty():
		return { "ok": true, "message": "9 sub-cases pass — see the sub-case index in test_pole_tiers.gd" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) POWER_NETWORK_TYPES — the single source of truth for "placing or
# removing this marks the power topology dirty".
#
# Previously an `or` chain duplicated at grid_world.gd's place and remove
# paths. Two hand-maintained copies of one list is how a seventh type gets
# added to one and not the other; the failure is silent (the network simply
# never rebuilds) until anything else marks it dirty — any place/remove of a
# type already in the set, or an explicit mark_power_network_dirty().
#
# POLE_TYPES is checked here too: it is the pole subset, and a pole missing
# from it is invisible to the BFS that builds network components.
# ===========================================================================
static func _case_network_type_set(failures: Array) -> void:
	# [type, label] parallel rows. The label is a LITERAL, deliberately not
	# Buildings.name_of(t): name_of is DATA[t]["name"], MEDIUM_POLE and
	# SUBSTATION have no DATA row until Task 2, and GDScript evaluates the
	# operand of `%` eagerly — so a name_of() here would fault on every run,
	# not just on failure. The literal is what lets this case cover the two
	# new tiers before they become placeable.
	var want: Array = [
		[Buildings.Type.POWER_POLE, "POWER_POLE"],
		[Buildings.Type.MEDIUM_POLE, "MEDIUM_POLE"],
		[Buildings.Type.SUBSTATION, "SUBSTATION"],
		[Buildings.Type.WATER_WHEEL, "WATER_WHEEL"],
		[Buildings.Type.ELECTRIC_LAMP, "ELECTRIC_LAMP"],
		[Buildings.Type.WINDMILL, "WINDMILL"],
		[Buildings.Type.STEAM_GENERATOR, "STEAM_GENERATOR"],
		[Buildings.Type.ACCUMULATOR, "ACCUMULATOR"],
		[Buildings.Type.ELECTRIC_INSERTER, "ELECTRIC_INSERTER"],
	]
	for row in want:
		var t: int = int(row[0])
		var label: String = String(row[1])
		_check(failures, Buildings.POWER_NETWORK_TYPES.has(t),
			"(1) POWER_NETWORK_TYPES is missing %s, so placing one would not mark the topology dirty" % label)
	_check(failures, not Buildings.POWER_NETWORK_TYPES.has(Buildings.Type.BELT),
		"(1) POWER_NETWORK_TYPES contains BELT, which would rebuild the power topology on every belt placement")

	# All three pole tiers must be in POLE_TYPES.
	var want_poles: Array = [
		[Buildings.Type.POWER_POLE, "POWER_POLE"],
		[Buildings.Type.MEDIUM_POLE, "MEDIUM_POLE"],
		[Buildings.Type.SUBSTATION, "SUBSTATION"],
	]
	for prow in want_poles:
		var pt: int = int(prow[0])
		var plabel: String = String(prow[1])
		_check(failures, Buildings.POLE_TYPES.has(pt),
			"(1) POLE_TYPES is missing %s, so the BFS would never treat it as a pole" % plabel)

	# POLE_TYPES must be a strict subset of POWER_NETWORK_TYPES. A pole that
	# forms components but does not mark the topology dirty on placement is
	# exactly the silent failure this pair of sets exists to prevent.
	for pole_t in Buildings.POLE_TYPES:
		_check(failures, Buildings.POWER_NETWORK_TYPES.has(int(pole_t)),
			"(1) POLE_TYPES has enum value %d but POWER_NETWORK_TYPES does not" % int(pole_t))

	# ...and only poles. Generators and consumers belong to the network but
	# do not form components or project a supply area.
	_check(failures, not Buildings.POLE_TYPES.has(Buildings.Type.WATER_WHEEL),
		"(1) POLE_TYPES contains WATER_WHEEL, but a generator is not a pole")
	_check(failures, not Buildings.POLE_TYPES.has(Buildings.Type.ELECTRIC_LAMP),
		"(1) POLE_TYPES contains ELECTRIC_LAMP, but a consumer is not a pole")

# ===========================================================================
# (2) REGISTRATION — both tiers exist, are placeable, and carry the numbers
# the whole session's arithmetic depends on.
#
# Footprint is asserted as a LITERAL rather than read back from DATA: the
# point is to pin the design decision (substation is 2x2) independently of
# the implementation, so a silent edit to DATA reddens here.
# ===========================================================================
static func _case_registration(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rows: Array = [
		[Buildings.Type.POWER_POLE,  Vector2i(1, 1), Vector2i(5, 5),  "basic"],
		[Buildings.Type.MEDIUM_POLE, Vector2i(1, 1), Vector2i(10, 5), "medium"],
		[Buildings.Type.SUBSTATION,  Vector2i(2, 2), Vector2i(15, 5), "substation"],
	]
	for row in rows:
		var t: int = int(row[0])
		var want_fp: Vector2i = row[1]
		var pos: Vector2i = row[2]
		var label: String = String(row[3])
		_check(failures, Buildings.footprint_of(t) == want_fp,
			"(2) footprint_of(%s) should be %s, got %s" % [label, str(want_fp), str(Buildings.footprint_of(t))])
		_check(failures, Buildings.POLE_TYPES.has(t),
			"(2) POLE_TYPES is missing %s, so BFS will never treat it as a pole" % label)
		_check(failures, world.place_building(t, pos),
			"(2) placing a %s at %s failed: %s" % [label, str(pos), str(world.last_building_place_error)])
		var b: Building = world.building_at(pos)
		_check(failures, b != null and b.type == t,
			"(2) no %s building at %s after placement" % [label, str(pos)])
	# The substation occupies all FOUR of its cells, not just the anchor.
	# occupied is what save/load rehydrates from, so a wrong footprint here
	# silently corrupts collision after a reload.
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_check(failures, world.has_building_at(Vector2i(15, 5) + d),
			"(2) substation cell %s is not marked occupied" % str(Vector2i(15, 5) + d))
	_teardown(world)
	_check_hotbar_budget(failures, parent)

## Registration is not finished until a PLAYER can reach the tier, so the
## hotbar is part of sub-case (2) rather than a case of its own.
##
## The budget check matters because overflow is silent: SLOTS_PER_CATEGORY_MAX
## is read in exactly one place besides its own definition — hotbar.gd's
## number-key loop — while _draw iterates slots.size() with no ceiling. A 10th
## slot is therefore drawn perfectly and simply cannot be selected. Power sits
## at 8 of 9 and is the category most likely to overflow next. Same guard as
## test_electric_inserter.gd's "Inserters" sub-case.
static func _check_hotbar_budget(failures: Array, parent: Node) -> void:
	var hotbar = HotbarScript.new()
	parent.add_child(hotbar)
	hotbar._build_categories()
	var slots: Array = []
	var found: bool = false
	for entry in hotbar.categories:
		if String(entry.get("name", "")) == "Power":
			slots = entry.get("slots", [])
			found = true
			break
	if not found:
		_check(failures, false,
			"(2) the hotbar has no `Power` category at all, so neither wire tier is placeable by a player")
		hotbar.queue_free()
		return
	for pair in [[Buildings.Type.MEDIUM_POLE, "medium pole"], [Buildings.Type.SUBSTATION, "substation"]]:
		var want: int = int(pair[0])
		var label: String = String(pair[1])
		var present: bool = false
		for slot in slots:
			if String(slot.get("kind", "")) == "building" and int(slot.get("value", -1)) == want:
				present = true
				break
		_check(failures, present,
			"(2) no `Power` hotbar slot points at the %s, so the tier stays dev-console-only" % label)
	_check(failures, slots.size() <= HotbarScript.SLOTS_PER_CATEGORY_MAX,
		"(2) the `Power` category holds %d slots, past the %d that the number keys can reach" % [slots.size(), HotbarScript.SLOTS_PER_CATEGORY_MAX])
	hotbar.queue_free()

# ===========================================================================
# (3) EITHER-REACHES — the locked connection rule.
#
# rule: chebyshev(a, b) <= max(range(a), range(b))
#
# A basic pole (range 3) and a medium pole (range 6) five tiles apart are
# CONNECTED, because 5 <= max(3, 6). Under a both-reaches (min) rule they
# would not be: 5 > min(3, 6) = 3. This sub-case IS the design decision, so
# it must go red if anyone flips the rule.
#
# The rule has to be SYMMETRIC or the BFS becomes a directed flood fill whose
# component grouping depends on lex walk order — see sub-case (4).
#
# THE DIRECTION RULE, stated once so it is not re-derived from scratch every
# time: a substation's anchor is its WEST/NORTH cell, so its footprint grows
# in +x/+y only. Anchor distance and footprint distance therefore differ for a
# pole on the substation's +x/+y side (footprint reads one LESS, because the
# gap really is shorter) and are IDENTICAL for a pole on its -x/-y side.
#
# THESE ROWS DO NOT DISCRIMINATE ANCHOR FROM FOOTPRINT. The second pole is
# always placed EAST of the first, which puts the first pole on the
# substation's -x side — the identical case. That is deliberate: this case is
# about the max() rule, not about _pole_distance. Sub-case (5) carries the
# +x pairing (E basic at (32,5), EAST of the substation at (20,5)) where
# anchor-to-anchor reads 12 and footprint reads 11.
# ===========================================================================
static func _case_either_reaches(parent: Node, failures: Array) -> void:
	var rows: Array = [
		# [type_a, type_b, distance, connected?, why]
		[Buildings.Type.POWER_POLE,  Buildings.Type.POWER_POLE,  3,  true,  "basic-basic at exactly range 3"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.POWER_POLE,  4,  false, "basic-basic one past range 3"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.MEDIUM_POLE, 5,  true,  "basic-medium at 5: only medium reaches, max(3,6)=6"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.MEDIUM_POLE, 6,  true,  "basic-medium at exactly 6"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.MEDIUM_POLE, 7,  false, "basic-medium at 7: past both, max(3,6)=6"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.SUBSTATION,  9,  true,  "basic-substation at 9: only substation reaches, max(3,11)=11"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.SUBSTATION,  12, false, "basic-substation one past 11"],
		[Buildings.Type.MEDIUM_POLE, Buildings.Type.SUBSTATION,  11, true,  "medium-substation at exactly 11"],
		[Buildings.Type.MEDIUM_POLE, Buildings.Type.SUBSTATION,  12, false, "medium-substation one past 11"],
	]
	for row in rows:
		var ta: int = int(row[0])
		var tb: int = int(row[1])
		var dist: int = int(row[2])
		var want: bool = bool(row[3])
		var why: String = String(row[4])
		var world = _make_world(parent)
		var pa: Vector2i = Vector2i(5, 5)
		var pb: Vector2i = Vector2i(5 + dist, 5)
		if not world.place_building(ta, pa) or not world.place_building(tb, pb):
			_check(failures, false, "(3) SETUP failed placing the pair for case: %s" % why)
			_teardown(world)
			continue
		PowerNetwork.rebuild_topology(world)
		var same: bool = int(world._pole_component.get(pa, -1)) == int(world._pole_component.get(pb, -2))
		_check(failures, same == want,
			"(3) %s: expected connected=%s, got %s" % [why, str(want), str(same)])
		_teardown(world)

# ===========================================================================
# (4) ORDER INDEPENDENCE — the trap a directed predicate falls into.
#
# If the BFS predicate were `dist <= range_of(the pole being expanded FROM)`
# rather than a symmetric max(), the pole graph would be DIRECTED. Flood fill
# over a directed graph produces components that depend on which node the walk
# starts from, and rebuild_topology walks its start points in lex order. The
# result would be deterministic but ARBITRARY: whether two poles share a
# network would hinge on which of them had the smaller (x, y).
#
# WHY THIS MIRRORS THE LAYOUT AND NOT THE PLACEMENT ORDER. Placing the same
# poles in a different order proves nothing here and CANNOT fail: pole_anchors
# is lex-sorted before the walk, the comparator is a total order on distinct
# anchors, so the sorted array — and therefore the whole walk — is a function
# of the anchor SET alone. Building the poles backwards produces a bit-identical
# topology under any predicate, symmetric or not. What does change the walk is
# WHICH TIER the lex-first pole is, so the mirror here is geometric: reflect
# every anchor about x = 20 and the medium pole swaps from lex-first to
# lex-last while every pairwise distance is preserved.
#
#   forward: medium(5,5)  basic(10,5)  far basic(30,5)
#   mirror:  far basic(10,5)  basic(30,5)  medium(35,5)
#
# Under either-reaches both group as {medium, basic} + {far}. Under the
# directed form the forward walk expands FROM the medium (range 6, reaches 5)
# and joins, while the mirror walk reaches the basic first (range 3, does not
# reach 5) and leaves three singletons. The grouping comparison below is what
# catches that.
#
# FOUR assertions, and each one has a mutation that reaches it and no other:
#   1. joined-grouping matches      <- directed predicate (verified: forward
#                                      true, mirror false)
#   2. component count matches      <- same, from the other side (2 vs 3)
#   3. the pair IS joined           <- a predicate that returns false for
#                                      everything, which groups both layouts
#                                      identically and slips past 1 and 2
#   4. the far pole is NOT joined   <- a predicate that returns true for
#                                      everything, same reason
#
# There was a FIFTH — "the far pole groups the same in both layouts" — and it
# is deleted rather than kept for symmetry, because no single-line change to
# the predicate could redden it. The layout is exactly mirror-symmetric and
# the far pair is 25 apart against a maximum table range of 11, so joining
# them at all takes a predicate that ignores distance, which then joins them
# in BOTH layouts and leaves the comparison equal. Assertion 2 already covers
# far-pole grouping and assertion 4 already covers the distance-blind case.
# We replaced the plan's original sub-case (4) for carrying an assertion that
# could not fail. The replacement does not get to carry one forward.
# ===========================================================================
static func _case_order_independence(parent: Node, failures: Array) -> void:
	# Forward layout: the medium pole is lex-FIRST.
	var f_medium: Vector2i = Vector2i(5, 5)
	var f_basic: Vector2i = Vector2i(10, 5)
	var f_far: Vector2i = Vector2i(30, 5)
	# Mirror about x = 20 (x' = 40 - x): same tiers, same pairwise distances,
	# medium pole now lex-LAST.
	var m_medium: Vector2i = Vector2i(35, 5)
	var m_basic: Vector2i = Vector2i(30, 5)
	var m_far: Vector2i = Vector2i(10, 5)

	# Placement is CHECKED, as it is in (3) and (5). Silently dropping a pole
	# would leave both layouts with the same too-few poles, so all three
	# comparisons would agree at 0 == 0 and the only red would be assertion 3,
	# which reads as a range bug. Nothing about that failure would point at
	# the setup.
	var forward = _make_world(parent)
	if not _place_all(forward, [
			[Buildings.Type.MEDIUM_POLE, f_medium], [Buildings.Type.POWER_POLE, f_basic],
			[Buildings.Type.POWER_POLE, f_far]], failures, "(4) forward"):
		_teardown(forward)
		return
	PowerNetwork.rebuild_topology(forward)
	var f_joined: bool = int(forward._pole_component.get(f_medium, -1)) == int(forward._pole_component.get(f_basic, -2))
	var f_far_joined: bool = int(forward._pole_component.get(f_medium, -1)) == int(forward._pole_component.get(f_far, -2))
	var f_comps: int = _component_count(forward)
	_teardown(forward)

	var mirror = _make_world(parent)
	if not _place_all(mirror, [
			[Buildings.Type.MEDIUM_POLE, m_medium], [Buildings.Type.POWER_POLE, m_basic],
			[Buildings.Type.POWER_POLE, m_far]], failures, "(4) mirror"):
		_teardown(mirror)
		return
	PowerNetwork.rebuild_topology(mirror)
	var m_joined: bool = int(mirror._pole_component.get(m_medium, -1)) == int(mirror._pole_component.get(m_basic, -2))
	var m_comps: int = _component_count(mirror)
	_teardown(mirror)

	_check(failures, f_joined == m_joined,
		"(4) the medium pole and the basic pole 5 away group differently in the mirrored layout (forward=%s mirror=%s), which means the connection predicate is not symmetric — it is reading the range of whichever pole the lex-sorted walk expanded from" % [str(f_joined), str(m_joined)])
	_check(failures, f_comps == m_comps,
		"(4) the mirrored layout produces a different number of components (forward=%d mirror=%d) from the same tiers at the same distances" % [f_comps, m_comps])
	_check(failures, f_joined,
		"(4) the medium pole at %s and the basic pole at %s are 5 apart and should be connected under either-reaches, max(6,3)=6" % [str(f_medium), str(f_basic)])
	_check(failures, not f_far_joined,
		"(4) the far basic pole at %s is 25 from the medium pole and must NOT join it — if it does, the predicate is not measuring distance at all" % str(f_far))

# ===========================================================================
# (5) THE PREDICATE IS THE GRAPH.
#
# Sub-cases (3) and (4) pin the RULE. This one pins the STRUCTURE that makes
# the rule safe: PowerNetwork.poles_connected is the only place the rule
# exists, and grid_world._draw_power_wires calls that same function to decide
# which wires to draw. So the edge set the renderer draws and the edge set the
# BFS walked are the same object, and the failure the user cares about — a
# renderer STRICTER than the BFS, leaving poles on one network with no wire
# between them and no signal anywhere — is unreachable rather than untested.
#
# THIS CASE DELIBERATELY DOES NOT REDERIVE THE ARITHMETIC. A test that
# computed max(abs(dx), abs(dy)) <= max(range_a, range_b) for itself and
# compared that to the BFS would be a THIRD implementation of the rule, and it
# would agree with a buggy predicate exactly as happily as with a correct one.
# It calls poles_connected and compares the answer against actual component
# membership, in both directions:
#
#   (5a) every pair the predicate joins is in ONE component — the BFS is not
#        stricter than the renderer.
#   (5b) every component is CONNECTED under predicate edges alone — the
#        renderer is not stricter than the BFS. This is the invisible-wire
#        direction, and it is why the layout is a CHAIN: A reaches B reaches C
#        reaches D reaches E with no shortcuts, so a component only spans if
#        every intermediate edge really is drawn.
#   (5c) the partition is the expected one. Without this a predicate that
#        returned true for every pair would satisfy both (5a) and (5b) —
#        one component, trivially spanned.
#
# THE LAYOUT, and what each link is for. Distances are FOOTPRINT to footprint
# (PowerNetwork._pole_distance); the substation at (20,5) is 2x2 and occupies
# x 20..21, y 5..6.
#
#   A basic      (0,5)
#   B basic      (3,5)   A-B = 3   = max(3,3)   boundary, basic tier
#   C medium     (9,5)   B-C = 6   = max(3,6)   boundary, either-reaches
#   D substation (20,5)  C-D = 11  = max(6,11)  boundary, WEST side: anchor
#                                               and footprint both read 11
#   E basic      (32,5)  D-E = 11  = max(3,11)  boundary, EAST side: footprint
#                                               reads 32-21 = 11 and joins,
#                                               anchor-to-anchor reads 32-20 =
#                                               12 and does NOT. This link is
#                                               the one that dies if
#                                               _pole_distance regresses to
#                                               anchor distance.
#   F basic      (45,5)  F-E = 13, F-D = 24     out of reach of everything
#   G medium     (45,11) G-F = 6   = max(3,6)   second component, so (5c) is
#                                               pinning a real partition and
#                                               not just "everything joins"
#
# A-C is 9 against max(3,6)=6 and A-D is 20 against 11, so the first component
# genuinely has no shortcut edges.
# ===========================================================================
static func _case_predicate_is_the_graph(parent: Node, failures: Array) -> void:
	var rows: Array = [
		[Buildings.Type.POWER_POLE,  Vector2i(0, 5),   "A basic"],
		[Buildings.Type.POWER_POLE,  Vector2i(3, 5),   "B basic"],
		[Buildings.Type.MEDIUM_POLE, Vector2i(9, 5),   "C medium"],
		[Buildings.Type.SUBSTATION,  Vector2i(20, 5),  "D substation"],
		[Buildings.Type.POWER_POLE,  Vector2i(32, 5),  "E basic"],
		[Buildings.Type.POWER_POLE,  Vector2i(45, 5),  "F basic"],
		[Buildings.Type.MEDIUM_POLE, Vector2i(45, 11), "G medium"],
	]
	var world = _make_world(parent)
	var anchors: Array = []
	var labels: Dictionary = {}
	for row in rows:
		var t: int = int(row[0])
		var pos: Vector2i = row[1]
		var label: String = String(row[2])
		if not world.place_building(t, pos):
			_check(failures, false,
				"(5) SETUP failed placing %s at %s: %s" % [label, str(pos), str(world.last_building_place_error)])
			_teardown(world)
			return
		anchors.append(pos)
		labels[pos] = label
	PowerNetwork.rebuild_topology(world)

	# --- (5a) the predicate never joins poles the BFS split apart ---
	for i in range(anchors.size()):
		for j in range(i + 1, anchors.size()):
			var pa: Vector2i = anchors[i]
			var pb: Vector2i = anchors[j]
			if not PowerNetwork.poles_connected(world, pa, pb):
				continue
			var ca: int = int(world._pole_component.get(pa, -1))
			var cb: int = int(world._pole_component.get(pb, -2))
			_check(failures, ca == cb,
				"(5a) poles_connected says %s and %s are wired together, so the wire renderer will draw that wire, but the BFS put them in components %d and %d" % [String(labels[pa]), String(labels[pb]), ca, cb])

	# --- (5b) every component is spanned by predicate edges alone ---
	# The walk below uses ONLY poles_connected, exactly as the renderer does.
	# If it cannot reach every member of a component, then some pair the BFS
	# relied on is one the renderer will refuse to draw — the invisible
	# connection, which nothing else in the suite would notice.
	var comps: Dictionary = {}
	for pos in anchors:
		var cid: int = int(world._pole_component.get(pos, -1))
		if not comps.has(cid):
			comps[cid] = []
		comps[cid].append(pos)
	for cid in comps:
		var members: Array = comps[cid]
		var seen: Dictionary = {}
		var queue: Array = [members[0]]
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			if seen.has(cur):
				continue
			seen[cur] = true
			for m in members:
				if seen.has(m):
					continue
				if PowerNetwork.poles_connected(world, cur, m):
					queue.append(m)
		_check(failures, seen.size() == members.size(),
			"(5b) component %d holds %d poles but only %d of them are reachable using poles_connected edges, so the BFS joined poles the wire renderer will not connect — an invisible link" % [cid, members.size(), seen.size()])

	# --- (5c) the partition is the expected one ---
	var group_one: Array = [Vector2i(0, 5), Vector2i(3, 5), Vector2i(9, 5), Vector2i(20, 5), Vector2i(32, 5)]
	var group_two: Array = [Vector2i(45, 5), Vector2i(45, 11)]
	_check(failures, comps.size() == 2,
		"(5c) expected exactly 2 components from this layout, got %d — see the layout table above for which link changed" % comps.size())
	for group in [group_one, group_two]:
		var head: int = int(world._pole_component.get(group[0], -1))
		_check(failures, head >= 0,
			"(5c) %s is not in any component at all" % String(labels[group[0]]))
		for member in group:
			_check(failures, int(world._pole_component.get(member, -2)) == head,
				"(5c) %s should share a component with %s but does not" % [String(labels[member]), String(labels[group[0]])])
	_check(failures, int(world._pole_component.get(group_one[0], -1)) != int(world._pole_component.get(group_two[0], -2)),
		"(5c) the two groups must stay in SEPARATE components — the closest pair across them is F basic at (45,5) and E basic at (32,5) at distance 13 against basic range 3, and F against the substation at footprint distance 24 against range 11. %s and %s came back in one component" % [String(labels[group_one[0]]), String(labels[group_two[0]])])
	_teardown(world)

# ===========================================================================
# (6) MULTI-CELL SUPPLY SYMMETRY.
#
# A 2x2 substation at anchor (10,10) occupies (10,10)..(11,11). With supply
# radius 4, coverage must extend 4 tiles beyond the FOOTPRINT in every
# direction: x from 6 to 15, y from 6 to 15. That is TEN cells per axis, not
# nine — (2r+1) is the 1x1 formula.
#
# The bug this catches: _pole_component holds only the ANCHOR, so a raw-cell
# lookup finds the substation only at (10,10). Coverage would then run
# (6..14, 6..14) — correct on the anchor side, one short on the far side. The
# FAR EDGE is the direction that fails, so it is asserted explicitly. A test
# that only probed left and up would pass against the broken code.
#
# MUTATION RUN, not assumed: _covering_component_id's `max(abs(dx), abs(dy))`
# (distance to the MATCHED CELL) replaced by distance to the anchor. Exactly
# three assertions fired — (15,10), (10,15) and (15,15) — and (6,10) and
# (10,6) stayed silent, which is the near/far split above.
#
# WHY THERE IS A LAMP HERE AND NOT JUST A GENERATOR. Every probe below reads
# the SAME number — power_satisfaction_at returns the component's
# satisfaction, so the only thing being discriminated is covered versus not
# covered, and that needs the covered answer to be above zero. A generator on
# its own does not establish that, and the reason is worth writing down
# because it is counter-intuitive: update_supply_demand's Stage 3 hands a
# component with ZERO demand a satisfaction of 1.0 outright (`1.0 if dem ==
# 0`), so a substation with nothing attached to it already reads powered.
# MUTATION RUN: with the generator and the lamp both deleted and only the
# substation standing, all nine probes below still pass. The LAMP is what puts
# real demand on the component and the GENERATOR is what covers it — 20 units
# against 1 — so the 1.0 the probes read is arithmetic and not that shortcut.
# The lamp sits at (11,13), well inside coverage and off every probe cell, so
# it cannot double as one of them.
#
# The generator is 2x2 at (12,10), which puts its WEST edge on (11,10) and
# (11,11) — two of the substation's own cells. That is the cardinal touch
# _adjacent_component_id demands. Sub-case (8) is the one that pins that rule
# on its own, so the PREMISE check below points there when supply is missing
# rather than letting nine coverage assertions redden for a supply reason.
# ===========================================================================
static func _case_multicell_supply_symmetry(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var sub: Vector2i = Vector2i(10, 10)
	var gen: Vector2i = Vector2i(12, 10)
	var lamp: Vector2i = Vector2i(11, 13)
	_pave(world, gen, Vector2i(2, 2))
	if not _place_all(world, [
			[Buildings.Type.SUBSTATION, sub],
			[Buildings.Type.STEAM_GENERATOR, gen],
			[Buildings.Type.ELECTRIC_LAMP, lamp]], failures, "(6)"):
		_teardown(world)
		return
	_light_generator(world, gen)
	PowerNetwork.update_supply_demand(world)

	var comp: int = int(world._pole_component.get(sub, -1))
	_check(failures, comp >= 0,
		"(6) PREMISE: the substation at %s is in no component at all, so every probe below reads 0.0 for a topology reason" % str(sub))
	_check(failures, PowerNetwork.satisfaction_for(world, comp) > 0.0,
		"(6) PREMISE: the substation's component reads satisfaction %f, so the 'powered' probes below would fail for a SUPPLY reason and not a coverage one — see sub-case (8)" % PowerNetwork.satisfaction_for(world, comp))

	# Covered: the four axis extremes at exactly radius 4 from the nearest
	# footprint cell, plus the far corner. (15,*) and (*,15) are the ones that
	# an anchor-only lookup gets wrong.
	for row in [
			[Vector2i(15, 10), "the EAST edge, 4 beyond the footprint column x=11"],
			[Vector2i(10, 15), "the SOUTH edge, 4 beyond the footprint row y=11"],
			[Vector2i(15, 15), "the SOUTH-EAST corner, 4 beyond on both axes"],
			[Vector2i(6, 10),  "the WEST edge, 4 beyond the anchor column x=10"],
			[Vector2i(10, 6),  "the NORTH edge, 4 beyond the anchor row y=10"]]:
		var cell: Vector2i = row[0]
		var why: String = String(row[1])
		_check(failures, PowerNetwork.power_satisfaction_at(world, cell) > 0.0,
			"(6) %s is NOT covered by the substation at %s — %s. Radius 4 measured from the 2x2 FOOTPRINT spans x 6..15 and y 6..15, ten cells per axis" % [str(cell), str(sub), why])

	# Not covered: one ring past, on all four sides. Without these the whole
	# sub-case would pass against a resolver that simply answered "powered"
	# everywhere.
	for row_out in [
			[Vector2i(16, 10), "east"],
			[Vector2i(10, 16), "south"],
			[Vector2i(5, 10),  "west"],
			[Vector2i(10, 5),  "north"]]:
		var out_cell: Vector2i = row_out[0]
		var side: String = String(row_out[1])
		_check(failures, PowerNetwork.power_satisfaction_at(world, out_cell) == 0.0,
			"(6) %s is one tile PAST the substation's %s edge and must read exactly 0.0, got %f" % [str(out_cell), side, PowerNetwork.power_satisfaction_at(world, out_cell)])
	_teardown(world)

# ===========================================================================
# (7) THE TWO CONSUMER PATHS AGREE, AND THEY AGREE AT THE WIDE RADIUS.
#
# Before Task 5 the two consumer-side functions disagreed with each other:
#
#   power_satisfaction_at   no type check at all, box sized to
#                           SUPPLY_RADIUS_DEFAULT (1). Answers for ANY pole
#                           whose ANCHOR is within 1.
#   _supply_component_id    same box, plus a hard `type != POWER_POLE`. Never
#                           answers for a medium pole or a substation.
#
# So a lamp at CHEBYSHEV 1 from a medium pole lit up while contributing no
# demand: the first function said powered, the second said "no pole in supply
# range" and update_supply_demand's ELECTRIC_LAMP arm skipped it. That is the
# split, and it lives at Chebyshev 1 — not at 2. The plan for this task
# asserted the same lamp at Chebyshev 2 would read powered today. It would
# not: at 2 it is outside the radius-1 box as well, so BOTH functions return
# nothing and there is no asymmetry to see. Chebyshev 1 is the only distance
# where the two disagreed.
#
# THREE LAMPS, at Chebyshev 1, 2 and 3 from a MEDIUM_POLE (supply radius 2):
#
#   (5,6) at 1 — inside radius 2, and also inside a BASIC pole's radius 1.
#                This is the lamp that reads POWERED today while contributing
#                nothing, so it carries the asymmetry.
#   (5,7) at 2 — inside radius 2 only. Reads unpowered today. This is the
#                lamp that pins the medium tier's radius as 2 rather than 1.
#   (5,8) at 3 — OUTSIDE radius 2. It is never counted, in any version, and it
#                is here so the demand total below fails in the over-reach
#                direction too: a resolver that used max_supply_radius() for
#                every pole instead of the pole's own would pull it in and
#                make the total 3. MUTATION RUN — `var r: int =
#                supply_radius(pole.type)` replaced by `var r: int = radius`
#                inside _covering_component_id reads demand 3, and the (5,8)
#                probe below reads 1.0 instead of 0.0. Both fire.
#
# The generator is not decoration. Once the lamps DO contribute, the
# component carries demand, and Stage 3 computes supply / demand — so without
# a generator feeding this component the post-fix satisfaction would be 0/2 =
# 0.0 and the two "reads as powered" assertions would go red on a correct
# fix. 2x2 at (6,5) puts its WEST edge on (5,5) and (5,6): (5,5) is the
# medium pole.
# ===========================================================================
static func _case_consumer_paths_agree(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var pole: Vector2i = Vector2i(5, 5)
	var gen: Vector2i = Vector2i(6, 5)
	var near: Vector2i = Vector2i(5, 6)
	var edge: Vector2i = Vector2i(5, 7)
	var beyond: Vector2i = Vector2i(5, 8)
	_pave(world, gen, Vector2i(2, 2))
	if not _place_all(world, [
			[Buildings.Type.MEDIUM_POLE, pole],
			[Buildings.Type.STEAM_GENERATOR, gen],
			[Buildings.Type.ELECTRIC_LAMP, near],
			[Buildings.Type.ELECTRIC_LAMP, edge],
			[Buildings.Type.ELECTRIC_LAMP, beyond]], failures, "(7)"):
		_teardown(world)
		return
	_light_generator(world, gen)
	PowerNetwork.update_supply_demand(world)

	var comp: int = int(world._pole_component.get(pole, -1))
	_check(failures, comp >= 0,
		"(7) PREMISE: the medium pole at %s is in no component at all" % str(pole))

	# --- the asymmetry, from the side that already passed ---
	_check(failures, PowerNetwork.power_satisfaction_at(world, near) > 0.0,
		"(7) the lamp at %s is Chebyshev 1 from the medium pole at %s and must read as POWERED" % [str(near), str(pole)])
	# --- the asymmetry, from the side that did not ---
	var want_demand: int = 2 * ElectricLamp.DEMAND
	var got_demand: int = PowerNetwork.demand_for(world, comp)
	_check(failures, got_demand == want_demand,
		"(7) the medium pole's component carries %d demand, expected exactly %d — the lamps at %s (Chebyshev 1) and %s (Chebyshev 2) are both inside its supply radius %d, and the lamp at %s (Chebyshev 3) is outside it. A lamp that reads as powered while contributing no demand is the exact split this sub-case exists for" % [got_demand, want_demand, str(near), str(edge), PowerNetwork.supply_radius(Buildings.Type.MEDIUM_POLE), str(beyond)])
	# --- the radius itself: 2, not the basic tier's 1 ---
	_check(failures, PowerNetwork.power_satisfaction_at(world, edge) > 0.0,
		"(7) the lamp at %s is Chebyshev 2 from the medium pole at %s, inside its supply radius %d, and must read as POWERED — at the basic tier's radius 1 it does not" % [str(edge), str(pole), PowerNetwork.supply_radius(Buildings.Type.MEDIUM_POLE)])
	_check(failures, PowerNetwork.power_satisfaction_at(world, beyond) == 0.0,
		"(7) the lamp at %s is Chebyshev 3 from the medium pole at %s, one ring OUTSIDE its supply radius %d, and must read exactly 0.0 — got %f" % [str(beyond), str(pole), PowerNetwork.supply_radius(Buildings.Type.MEDIUM_POLE), PowerNetwork.power_satisfaction_at(world, beyond)])
	_teardown(world)

# ===========================================================================
# (8) A GENERATOR FLUSH AGAINST A SUBSTATION FEEDS IT.
#
# Generators do NOT use the consumers' wireless supply area. They use
# _adjacent_component_id, which walks the generator's own cardinal edge ring
# and wants a pole standing on it. That function carried the third
# `type != POWER_POLE` filter, so a steam generator built hard against a
# substation contributed ZERO supply while looking perfectly connected — the
# substation is a network member, it is drawn with wires, and nothing on
# screen says otherwise.
#
# The layout: substation 2x2 at (20,20) occupying (20,20)..(21,21), steam
# generator 2x2 at (22,20) occupying (22,20)..(23,21). The generator's WEST
# edge is x = 21 across y 20..21, which is the substation's east column. No
# basic pole exists anywhere in this world, so the supply below can only have
# arrived through the substation.
#
# It also exercises the multi-cell half of the same function: the pole the
# edge ring lands on is a NON-ANCHOR cell of the substation, and
# _adjacent_component_id resolves it through world.building_at, which maps any
# footprint cell to its owner and then keys _pole_component by nb.anchor.
# ===========================================================================
static func _case_generator_against_substation(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var sub: Vector2i = Vector2i(20, 20)
	var gen: Vector2i = Vector2i(22, 20)
	_pave(world, gen, Vector2i(2, 2))
	if not _place_all(world, [
			[Buildings.Type.SUBSTATION, sub],
			[Buildings.Type.STEAM_GENERATOR, gen]], failures, "(8)"):
		_teardown(world)
		return
	_light_generator(world, gen)
	PowerNetwork.update_supply_demand(world)

	# PREMISE, through Buildings.all_edge_cells rather than by eye: if the
	# layout ever drifts so the generator no longer touches, the supply
	# assertion below would redden and read as a filter bug.
	var gen_b: Building = world.building_at(gen)
	var touches: bool = false
	for cell in Buildings.all_edge_cells(Buildings.Type.STEAM_GENERATOR, gen):
		var nb: Building = world.building_at(cell)
		if nb != null and nb.anchor == sub:
			touches = true
			break
	_check(failures, gen_b != null and touches,
		"(8) PREMISE: the steam generator at %s does not have the substation at %s on its cardinal edge ring, so this sub-case is testing nothing" % [str(gen), str(sub)])

	var comp: int = int(world._pole_component.get(sub, -1))
	_check(failures, comp >= 0,
		"(8) PREMISE: the substation at %s is in no component at all" % str(sub))
	var got_supply: int = PowerNetwork.supply_for(world, comp)
	_check(failures, got_supply == SteamGenerator.MAX_OUTPUT,
		"(8) the substation's component carries %d supply, expected exactly %d — a fuelled steam generator cardinally touching a SUBSTATION must feed it exactly as it would a basic pole" % [got_supply, SteamGenerator.MAX_OUTPUT])
	_teardown(world)

# ===========================================================================
# (9) THE PANEL ROW THAT RENDERS THE TIER TABLE STILL FITS THE PANEL.
#
# Inserter.info_lines' STATE_NO_POWER arm composes one row listing every tier
# in Buildings.POLE_TYPES with its supply radius — "Power 1, Medium 2,
# Substation 4". ADDING A TIER WIDENS A PLAYER-FACING STRING, by roughly 55-90
# px against 24 px of headroom, and info_panel.gd draws body rows through
# draw_string, whose overrun behaviour defaults to OVERRUN_NO_TRIMMING: an
# over-long row is not clipped, it spills across the panel border and then off
# the right of the viewport. So the failure is silent and it is invisible to
# every other test in the project.
#
# THIS SUB-CASE EXISTS BECAUSE THAT DEFECT ALREADY SHIPPED ONCE. Task 5a
# replaced the flat "connect a pole within 1 tile" with a per-tier string that
# measured 457 px against a 220 px budget and read, on screen, as "NO POWER —
# no pole in ran" — both numbers, the entire point of the change, off-viewport.
# A reviewer caught it, not the suite. This is the guard the suite did not
# have, placed with the TRIGGER rather than with the panel: what breaks the
# row is a change to the pole tiers, so it reddens in the pole-tiers file.
#
# IT MEASURES, IT DOES NOT COUNT CHARACTERS. Width comes from
# ThemeDB.fallback_font — the same object info_panel.gd draws with, not a
# stand-in — at InfoPanelScript.BODY_FONT_SIZE, against
# InfoPanelScript.LINE_BUDGET. Both constants were extracted from that file's
# draw_string calls for this, so the budget cannot drift from the thing being
# budgeted. Character count would have been the dishonest version: "Substation
# 4" and "Illlllllll 4" are the same length and nowhere near the same width.
#
# DELIBERATELY NARROW. This is NOT a panel-wide audit. Two sibling status
# strings are over budget right now and are not asserted here — BLOCKED at 303
# px and NO FUEL at 305 px, both predating this session and both visibly cut —
# because pinning them would either redden the suite on someone else's bug or
# require fixing player-facing copy this task has no mandate over. A general
# info-panel width guard is a real task and this is not it. What this pins is
# the two rows Task 5 added and the one edit that silently breaks them.
# ===========================================================================
static func _case_reach_row_fits_panel(failures: Array) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		_check(failures, false,
			"(9) ThemeDB.fallback_font is null, so no row width can be measured. Failing loudly rather than passing vacuously — a width guard that silently measures nothing is worse than none")
		return
	# No world needed: info_lines' own signature allows a null world, and the
	# reach rows read only Buildings.POLE_TYPES and SUPPLY_RADIUS_BY_TYPE.
	var ins: Building = Inserter.make(Vector2i(0, 0), 0, Buildings.Type.ELECTRIC_INSERTER)
	ins.state["state"] = Inserter.STATE_NO_POWER
	var lines: Array = Inserter.info_lines(ins, null)
	var label_idx: int = -1
	for i in range(lines.size()):
		if str(lines[i]).begins_with("Pole reach"):
			label_idx = i
			break
	_check(failures, label_idx >= 0 and label_idx + 1 < lines.size(),
		"(9) the STATE_NO_POWER panel has no `Pole reach` row followed by a data row, so this sub-case is measuring nothing. If those rows were removed on purpose, delete this sub-case in the same breath. Got %s" % str(lines))
	if label_idx < 0 or label_idx + 1 >= lines.size():
		return

	# EVERY tier must appear, checked before the width is. A tier added to the
	# table but dropped from the panel would leave a SHORTER string that sails
	# through the width assertion while being exactly the bug — the player
	# holding the new pole is told nothing about its reach.
	#
	# DELIBERATELY FORMAT-TOLERANT: it accepts the tier's DATA name either in
	# full or with the " Pole" suffix the panel trims, because which of the two
	# is rendered is a layout decision and this assertion is about CONTENT. An
	# earlier draft hardcoded the trimmed form, and when the width mutation
	# below was run it fired here too, reporting "the player is told nothing
	# about its supply radius" about a row that named every tier and every
	# radius. A presence check that reddens on a relabel is a presence check
	# that lies about what broke. Width is the other assertion's job.
	var data: String = str(lines[label_idx + 1])
	for pole_t in Buildings.POLE_TYPES:
		var pt: int = int(pole_t)
		var full: String = Buildings.name_of(pt)
		var r: int = PowerNetwork.supply_radius(pt)
		var present: bool = data.contains("%s %d" % [full, r]) or data.contains("%s %d" % [full.trim_suffix(" Pole"), r])
		_check(failures, present,
			"(9) the panel's pole-reach row never pairs `%s` with its supply radius %d, so a player holding that tier is told nothing about its reach. The row reads \"%s\"" % [full, r, data])

	var budget: int = int(InfoPanelScript.LINE_BUDGET)
	for idx in [label_idx, label_idx + 1]:
		var text: String = str(lines[idx])
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(InfoPanelScript.BODY_FONT_SIZE)).x
		_check(failures, w <= float(budget),
			"(9) the info-panel row \"%s\" measures %.0f px against info_panel.gd's %d px line budget. draw_string does NOT trim, so it spills past the panel border and off the right of the viewport — which is the exact regression adding a pole tier recreates. Split the row or shorten the labels" % [text, w, budget])

## Lay STONE over a `size` rectangle anchored at `anchor`.
##
## _make_world lays no terrain at all, so every cell reads GRASS / NONE.
## Every pole tier and the lamp accept Overlay.NONE, but STEAM_GENERATOR's
## requires_overlay is [STONE, PATH] — it is the strict one — so its four
## cells have to be paved before its anchor row runs. Writing a fresh Tile
## first keeps set_overlay off its idempotent early return, same as
## PoleTierRig.build does.
static func _pave(world, anchor: Vector2i, size: Vector2i) -> void:
	for dy in range(size.y):
		for dx in range(size.x):
			var cell: Vector2i = anchor + Vector2i(dx, dy)
			world.tiles[cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
			world.set_overlay(cell, Terrain.Overlay.STONE)

## Put a placed STEAM_GENERATOR into its supplying state without ticking.
##
## update_supply_demand's STEAM_GENERATOR arm reads exactly one field —
## state["output_active"] — so writing it is what makes the generator supply.
## fuel_buffer is loaded alongside it so the state is COHERENT rather than a
## generator that claims to be running on nothing: SteamGenerator.tick would
## rewrite output_active from Burner.consume_tick, and a sub-case that later
## grew a tick loop would otherwise silently go dark. Nothing here ticks.
static func _light_generator(world, anchor: Vector2i) -> void:
	var b: Building = world.building_at(anchor)
	if b == null:
		return
	b.state["fuel_buffer"] = 16
	b.state["output_active"] = true

## Place every [type, anchor] row, reporting the world's own placement error
## on the first failure. Returns false if any placement was refused, so the
## caller can abandon a sub-case rather than assert against a partial layout.
static func _place_all(world, rows: Array, failures: Array, prefix: String) -> bool:
	for row in rows:
		var t: int = int(row[0])
		var pos: Vector2i = row[1]
		if not world.place_building(t, pos):
			_check(failures, false,
				"%s SETUP failed placing type %d at %s: %s" % [prefix, t, str(pos), str(world.last_building_place_error)])
			return false
	return true

## Number of distinct component ids currently in world._pole_component.
static func _component_count(world) -> int:
	var seen: Dictionary = {}
	for pos in world._pole_component:
		seen[int(world._pole_component[pos])] = true
	return seen.size()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## A fresh GridWorld parented to `parent` so its _ready() runs.
##
## No terrain is laid: a new GridWorld has an empty `tiles` dict, so every
## cell reads back Terrain.DEFAULT_OVERLAY (NONE) and Terrain.DEFAULT_BASE
## (GRASS). All three pole tiers list Overlay.NONE in requires_overlay, and
## GRASS is not WATER, so can_place_building passes on bare ground.
static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing, mirroring test_electric_rig.gd's _teardown.
##
## queue_free() is deferred until after the runner's synchronous run()
## returns, and test_runner.gd's _disconnect_all(TickSystem.tick) fires only
## between test FILES, never between sub-cases. Without the disconnect a torn
## down world stays subscribed for the rest of this file, so the first
## sub-case that advances ticks would tick this one alongside it.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
