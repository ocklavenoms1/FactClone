extends RefCounted

## Pole tiers (Electricity Session 3) — parametric POLE_RANGE_BY_TYPE /
## SUPPLY_RADIUS_BY_TYPE, either-reaches connection, multi-cell poles,
## nearest-pole supply tie-break.
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

# Used from Task 2 on: the world-building sub-cases instantiate GridWorld
# through _make_world(parent).
const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const HotbarScript = preload("res://scripts/ui/hotbar.gd")

static func test_name() -> String:
	return "pole tiers (network-type set + registration + either-reaches + order independence + predicate is the graph)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_network_type_set(failures)
	_case_registration(parent, failures)
	_case_either_reaches(parent, failures)
	_case_order_independence(parent, failures)
	_case_predicate_is_the_graph(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: network-type set, registration, either-reaches, order independence, predicate is the graph" }
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
# The two GROUPING assertions catch a directed predicate. The "should be
# connected" assertion catches the degenerate opposite — a predicate that
# returns false for everything groups both layouts identically (all singletons)
# and would slip past the comparison alone.
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

	var forward = _make_world(parent)
	forward.place_building(Buildings.Type.MEDIUM_POLE, f_medium)
	forward.place_building(Buildings.Type.POWER_POLE, f_basic)
	forward.place_building(Buildings.Type.POWER_POLE, f_far)
	PowerNetwork.rebuild_topology(forward)
	var f_joined: bool = int(forward._pole_component.get(f_medium, -1)) == int(forward._pole_component.get(f_basic, -2))
	var f_far_joined: bool = int(forward._pole_component.get(f_medium, -1)) == int(forward._pole_component.get(f_far, -2))
	var f_comps: int = _component_count(forward)
	_teardown(forward)

	var mirror = _make_world(parent)
	mirror.place_building(Buildings.Type.MEDIUM_POLE, m_medium)
	mirror.place_building(Buildings.Type.POWER_POLE, m_basic)
	mirror.place_building(Buildings.Type.POWER_POLE, m_far)
	PowerNetwork.rebuild_topology(mirror)
	var m_joined: bool = int(mirror._pole_component.get(m_medium, -1)) == int(mirror._pole_component.get(m_basic, -2))
	var m_far_joined: bool = int(mirror._pole_component.get(m_medium, -1)) == int(mirror._pole_component.get(m_far, -2))
	var m_comps: int = _component_count(mirror)
	_teardown(mirror)

	_check(failures, f_joined == m_joined,
		"(4) the medium pole and the basic pole 5 away group differently in the mirrored layout (forward=%s mirror=%s), which means the connection predicate is not symmetric — it is reading the range of whichever pole the lex-sorted walk expanded from" % [str(f_joined), str(m_joined)])
	_check(failures, f_far_joined == m_far_joined,
		"(4) the far pole groups differently in the mirrored layout (forward=%s mirror=%s)" % [str(f_far_joined), str(m_far_joined)])
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
