extends RefCounted

## POLE TIER GAMEPLAY RIG (Electricity Session 3, PAUSE 2) — the four-scenario
## layout the human looks at, asserted headlessly so what the test proves and
## what they see cannot drift. Drives PoleGameplayRig.build and
## PoleGameplayRig.toggle_bridge, the same two entry points main.gd calls.
##
## WHY EACH SUB-CASE EXISTS. A gate rig fails SILENTLY — every placement
## succeeds, the screen looks right, and the thing being demonstrated is not
## happening. PoleTierRig shipped a draft with both generators one row off:
## 36/36 placed, demand exactly 40, raw supply 0 in all three lever positions,
## nothing visibly wrong until someone read the Q-inspect panel. Each sub-case
## below is aimed at one such silent failure:
##
##   (1) the layout lands ........ zero skips, exact placement count, and the
##       generators are in a pole's CARDINAL EDGE RING. That last check is the
##       one that catches the PoleTierRig defect at the point of cause; (7)
##       catches the same defect by its effect, and both are kept because they
##       say different things about where to look.
##   (2) the toggle merges and splits ... the whole reason this rig exists.
##       Component counts and edge SETS, never coordinates.
##   (3) the toggle is idempotent ....... ten presses alternate cleanly. A
##       toggle that stacked substations would still show "merged" on every odd
##       press and would be invisible to (2).
##   (4) the overlap consumer ........... covered by a basic pole AND the
##       substation, and still covered when the substation goes. It does NOT
##       assert anything about the nearest-pole tie-break, which is currently
##       unobservable — see OVERLAP_LAMP in the rig module.
##   (5) the 5-tile basic <-> medium link ... the either-reaches rule. Asserted
##       through PowerNetwork.poles_connected (the predicate that runs) AND
##       through wire_edges (the thing the human actually sees), because a rule
##       that holds in the BFS but draws no wire is an invisible connection.
##   (6) the dense block ................ one component, 16 poles, all three
##       tiers. The WIRE COUNT is deliberately not asserted — it is the
##       judgement the gate is for.
##   (7) the power arithmetic ........... 40 supply and 40 demand bridged, and
##       an exact 20/20 split when the bridge goes. The split is what makes
##       BROWNOUT-with-the-bridge-gone read as "cluster B goes dark" instead of
##       "everything dims a bit".
##   (8) re-spawn adopts ................ pure spawn plumbing, shared with the
##       other two rigs, and the failure it guards is a dead F8 lever.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Rig origin used by every sub-case. Non-zero on purpose: the rig carries
# negative rig-relative coordinates on all three paving rectangles (each starts
# at -1 on one axis or the other), so an origin at (0,0) would let a sign error
# in the absolutise step hide behind coordinates that happen to still be legal.
const RIG_ORIGIN: Vector2i = Vector2i(40, 40)

# The totals the whole design rests on, as LITERALS and deliberately HERE rather
# than in pole_gameplay_rig.gd — the same decision, for the same reason, as
# EXPECTED_PLACEMENTS in test_electric_rig.gd and test_pole_tier_rig.gd. A
# constant that lives beside the plan gets edited in the same breath as the
# plan, which would make these assertions self-referential: delete a lamp,
# adjust the neighbouring const, and the suite stays green while the brownout
# midpoint quietly becomes 20/39 = 0.5128.
#
#   48 placements = 16 dense-block poles (2 substation + 4 medium + 10 basic)
#                 + 4 cluster poles + 2 scenario-3 poles
#                 + 2 steam generators + 4 electric inserters + 20 lamps.
#                 The BRIDGE substation is NOT among them — it is owned by
#                 set_bridge(), see BRIDGE_OFFSET in the rig module.
#   40 demand     = 4 inserters x 5 + 20 lamps x 1
#   40 supply     = 2 steam generators x SteamGenerator.MAX_OUTPUT (20)
#   20 / 20       = that demand and that supply, split one per cluster, which
#                   is what the bridge-absent state reads.
const EXPECTED_PLACEMENTS: int = 48
const EXPECTED_DEMAND: int = 40
const EXPECTED_SUPPLY: int = 40
const EXPECTED_CLUSTER_DEMAND: int = 20
const EXPECTED_CLUSTER_SUPPLY: int = 20

# Pole components on a rig-only world. Bridged: dense block + the joined bus +
# the scenario-3 pair. Split: the same, with the bus in two halves.
const EXPECTED_COMPONENTS_BRIDGED: int = 3
const EXPECTED_COMPONENTS_SPLIT: int = 4

# The dense block's pole count, and the tiers it must contain.
const EXPECTED_DENSE_POLES: int = 16

# Scenario 3's separation, and the two ranges that make it the rule made
# visible: 5 > 3 so a both-reaches min() would refuse, 5 <= 6 so either-reaches
# accepts.
const SCENARIO3_DISTANCE: int = 5

# How many times sub-case (3) presses the toggle. Even, so the rig ends where it
# started and the "nothing accumulated" comparison is against the spawn state.
const TOGGLE_PRESSES: int = 10

static func test_name() -> String:
	return "pole gameplay rig (layout lands + bridge merges and splits + toggle is idempotent + overlap consumer + 5-tile either-reaches link + dense block is one component + 40/40 bridged and 20/20 split + re-spawn adopts)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_layout(parent, failures)
	_case_bridge(parent, failures)
	_case_toggle_idempotent(parent, failures)
	_case_overlap_consumer(parent, failures)
	_case_either_reaches_link(parent, failures)
	_case_dense_block(parent, failures)
	_case_power(parent, failures)
	_case_adoption(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "8 sub-cases pass: layout lands + bridge merges 4 components to 3 and splits back + 10 presses alternate cleanly + overlap consumer survives the toggle + the 5-tile link exists as one wire + dense block is 16 poles on one component + 40/40 bridged and 20/20 split + re-spawn adopts" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) THE LAYOUT LANDS.
#
# Every number in this file is downstream of the rig being built in full. A
# silent skip (terrain guard, collision) makes later assertions fail for a
# reason that has nothing to do with what they claim to test, so this runs
# first.
#
# The generator check is not decoration. Generators feed the network through
# PowerNetwork._adjacent_component_id, which wants a pole in the CARDINAL EDGE
# RING — the consumers' wireless supply area does not apply to them. It is
# reimplemented here through the same Buildings.all_edge_cells helper that
# function uses, rather than asserting on coordinates the layout could quietly
# move.
#
# This check and (7)'s supply total are COMPLEMENTARY, not redundant. This one
# names the offending generator's coordinates, so it says where to look; (7)
# reports the supply shortfall, so it also catches a bus that split for some
# reason having nothing to do with edge rings.
# ===========================================================================
static func _case_layout(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)

	_check(failures, int(rig.get("skipped", -1)) == 0,
		"(1) the rig skipped %d placements, so the layout is incomplete and every later number is wrong" % int(rig.get("skipped", -1)))
	_check(failures, int(rig.get("placed", -1)) == EXPECTED_PLACEMENTS,
		"(1) placed %d buildings, expected exactly %d" % [int(rig.get("placed", -1)), EXPECTED_PLACEMENTS])
	_check(failures, PoleGameplayRig.plan().size() == EXPECTED_PLACEMENTS,
		"(1) the placement plan lists %d entries, expected exactly %d" % [PoleGameplayRig.plan().size(), EXPECTED_PLACEMENTS])

	# The bridge is placed OUTSIDE the plan loop, so "placed == 48" says nothing
	# about it. Assert it separately, and assert build() reported it.
	_check(failures, bool(rig.get("bridge_present", false)),
		"(1) build() did not report the bridge substation present — the rig must spawn BRIDGED")
	var bridge_anchor: Vector2i = rig.get("bridge_anchor", Vector2i.ZERO)
	_check(failures, PoleGameplayRig.bridge_is_present(world, bridge_anchor),
		"(1) no SUBSTATION anchored at the reported bridge cell %s" % str(bridge_anchor))

	var gens: Array = rig.get("gen_anchors", [])
	_check(failures, gens.size() == 2,
		"(1) expected exactly 2 steam generators, got %d — ElectricRig.FUELLED_BY_STATE is [2, 1, 0] and fuels the first N, so a third would be dark in every lever position" % gens.size())
	for anchor in gens:
		_check(failures, _touches_pole(world, anchor),
			"(1) steam generator at %s does not CARDINALLY touch a pole, so it feeds nothing and raw supply is 0 while every placement still succeeds" % str(anchor))
	_teardown(world)

# ===========================================================================
# (2) THE BRIDGE MERGES AND SPLITS — scenario 1, the reason this rig exists.
#
# Bridged, a rig-only world holds 3 pole components: the dense block, the joined
# bus, and the scenario-3 pair. With the bridge gone the bus halves and it is 4.
# Removing ONE building therefore changes the count by exactly one, and that
# delta IS the bridge.
#
# Counting alone would pass if the bridge merged the wrong things, so the
# cluster-co-membership check is what pins WHICH components moved: cluster A's
# far pole and cluster B's near pole share a component bridged and do not share
# one split.
#
# EDGES, NOT COORDINATES. The wire assertions read the SET of edges
# PowerNetwork.wire_edges emits — the only thing grid_world._draw_power_wires
# walks — so they describe what is on screen rather than where.
#
# Bridged, the bus draws a four-wire CHAIN A1-A2-BRIDGE-B1-B2. Six pairs are
# reachable, not four: the bridge's range of 11 also reaches A1 (7 away) and B2
# (7 away). Gabriel suppresses exactly those two, because A2 sits inside the
# circle on A1-BRIDGE as diameter and B1 sits inside the one on BRIDGE-B2. So
# the four asserted below are the whole edge set, and this sub-case would notice
# a renderer that started drawing the two long skips over the intermediate
# poles. Split, the two cross wires vanish and the two intra-cluster wires stay.
#
# Both cross links are min-rule TRIPWIRES: each is at footprint distance 4,
# which is > the basic tier's range of 3, so both exist only because
# poles_connected takes max(range_a, range_b). Flip that to min() and this
# sub-case reads 4 components with the bridge standing.
# ===========================================================================
static func _case_bridge(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)
	var a_far: Vector2i = RIG_ORIGIN + PoleGameplayRig.CLUSTER_A_POLES[1]
	var b_near: Vector2i = RIG_ORIGIN + PoleGameplayRig.CLUSTER_B_POLES[0]
	var a_near: Vector2i = RIG_ORIGIN + PoleGameplayRig.CLUSTER_A_POLES[0]
	var b_far: Vector2i = RIG_ORIGIN + PoleGameplayRig.CLUSTER_B_POLES[1]
	var bridge: Vector2i = rig.get("bridge_anchor", Vector2i.ZERO)

	PowerNetwork.rebuild_topology(world)
	var bridged: int = _unique_components(world).size()
	_check(failures, bridged == EXPECTED_COMPONENTS_BRIDGED,
		"(2) bridged, there should be exactly %d pole components (dense block, joined bus, scenario-3 pair), got %d" % [EXPECTED_COMPONENTS_BRIDGED, bridged])
	# component_count() is what the toast prints. Tie it to this file's own
	# independent count once, so a wrong toast cannot pass unnoticed.
	_check(failures, PoleGameplayRig.component_count(world) == bridged,
		"(2) PoleGameplayRig.component_count says %d while this test counts %d — the toggle toast would lie" % [PoleGameplayRig.component_count(world), bridged])

	var id_a: int = PowerNetwork.network_id_at(world, a_far)
	var id_b: int = PowerNetwork.network_id_at(world, b_near)
	_check(failures, id_a >= 0 and id_a == id_b,
		"(2) bridged, cluster A %s and cluster B %s are on components %d and %d — the bridge is not bridging" % [str(a_far), str(b_near), id_a, id_b])

	var edges_on: Array = PowerNetwork.wire_edges(world)
	_check(failures, _has_edge(edges_on, a_far, bridge),
		"(2) bridged, no wire is drawn between cluster A's far pole %s and the bridge %s — the poles are in one component with no visible connection" % [str(a_far), str(bridge)])
	_check(failures, _has_edge(edges_on, bridge, b_near),
		"(2) bridged, no wire is drawn between the bridge %s and cluster B's near pole %s" % [str(bridge), str(b_near)])
	_check(failures, _has_edge(edges_on, a_near, a_far),
		"(2) bridged, no wire inside cluster A between %s and %s" % [str(a_near), str(a_far)])
	_check(failures, _has_edge(edges_on, b_near, b_far),
		"(2) bridged, no wire inside cluster B between %s and %s" % [str(b_near), str(b_far)])
	# The four above are the WHOLE bus edge set, asserted as a count so the two
	# suppressed long skips cannot come back unnoticed.
	_check(failures, _edges_among(edges_on, [a_near, a_far, bridge, b_near, b_far]) == 4,
		"(2) bridged, the bus draws %d wires between its 5 poles, expected exactly 4 — a chain, not a chain plus the bridge's two long skips over A2 and B1" % _edges_among(edges_on, [a_near, a_far, bridge, b_near, b_far]))

	PoleGameplayRig.set_bridge(world, RIG_ORIGIN, false)
	PowerNetwork.rebuild_topology(world)
	var split: int = _unique_components(world).size()
	_check(failures, split == EXPECTED_COMPONENTS_SPLIT,
		"(2) with the bridge removed the bus should split, giving %d components, got %d — if this equals the bridged count the bridge was never load-bearing" % [EXPECTED_COMPONENTS_SPLIT, split])
	var id_a2: int = PowerNetwork.network_id_at(world, a_far)
	var id_b2: int = PowerNetwork.network_id_at(world, b_near)
	_check(failures, id_a2 >= 0 and id_b2 >= 0 and id_a2 != id_b2,
		"(2) with the bridge removed, cluster A %s and cluster B %s still share component %d — they are 9 apart and no basic pole reaches that" % [str(a_far), str(b_near), id_a2])

	var edges_off: Array = PowerNetwork.wire_edges(world)
	_check(failures, not _has_edge(edges_off, a_far, bridge) and not _has_edge(edges_off, bridge, b_near),
		"(2) with the bridge removed, a wire to the bridge cell %s is still being drawn" % str(bridge))
	_check(failures, _has_edge(edges_off, a_near, a_far) and _has_edge(edges_off, b_near, b_far),
		"(2) removing the bridge also took out an intra-cluster wire — the clusters must survive the toggle intact")
	_check(failures, _edges_among(edges_off, [a_near, a_far, b_near, b_far]) == 2,
		"(2) split, the four cluster poles draw %d wires, expected exactly 2 — one inside each cluster and nothing across the 9-tile gap" % _edges_among(edges_off, [a_near, a_far, b_near, b_far]))
	_teardown(world)

# ===========================================================================
# (3) THE TOGGLE IS IDEMPOTENT AND REPEATABLE.
#
# The human holds a key. Ten presses must alternate cleanly rather than stack
# substations, strand the rig un-bridged, or quietly rebuild anything else.
#
# Sub-case (2) cannot see any of that: it calls set_bridge once, in each
# direction, from a known state. What it cannot see is a set_bridge that has
# stopped being a function of the CURRENT world — one that tracked the intended
# state in a static, say, and drifted out of step with the ground after any call
# that did not do what it thought. That drift shows up as a press that reports a
# state the world is not in, or as a press that changes nothing, and both are
# invisible until you press more than twice.
#
# Three invariants, checked every press:
#   the reported state alternates;
#   the world holds 2 or 3 SUBSTATIONs (the dense block's two, plus the bridge
#     when it is on) and never more;
#   the total building count returns to its spawn value on even presses.
#
# And the LEVER must survive: the two generator anchors still hold STEAM_
# GENERATORs at the end, because main.gd keeps pointing _rig_gen_anchors at them
# across every press and a dead anchor there is the silent-16-second-death this
# project has already shipped once.
# ===========================================================================
static func _case_toggle_idempotent(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)
	var gens: Array = rig.get("gen_anchors", [])
	var spawn_buildings: int = world.buildings.size()
	var spawn_subs: int = _count_type(world, Buildings.Type.SUBSTATION)

	# Asking for the state it is already in must build nothing. This is the
	# assertion that fails if set_bridge ever grows an unconditional place call.
	var noop: Dictionary = PoleGameplayRig.set_bridge(world, RIG_ORIGIN, true)
	_check(failures, not bool(noop.get("changed", true)) and bool(noop.get("present", false)),
		"(3) set_bridge(present) on an already-bridged rig reported changed=%s present=%s — it must be a no-op" % [str(noop.get("changed", true)), str(noop.get("present", false))])
	_check(failures, world.buildings.size() == spawn_buildings,
		"(3) a no-op set_bridge changed the building count from %d to %d" % [spawn_buildings, world.buildings.size()])

	var expect_present: bool = true
	for i in range(TOGGLE_PRESSES):
		var res: Dictionary = PoleGameplayRig.toggle_bridge(world, RIG_ORIGIN)
		expect_present = not expect_present
		_check(failures, bool(res.get("present", not expect_present)) == expect_present,
			"(3) press %d reported present=%s, expected %s — the toggle is not alternating" % [i + 1, str(res.get("present", null)), str(expect_present)])
		_check(failures, bool(res.get("changed", false)),
			"(3) press %d reported changed=false — a press that does nothing reads to the user as a dead key" % (i + 1))
		_check(failures, not bool(res.get("blocked", true)),
			"(3) press %d reported blocked — nothing may stand on the bridge cell in a rig-only world" % (i + 1))
		var subs: int = _count_type(world, Buildings.Type.SUBSTATION)
		var want_subs: int = spawn_subs if expect_present else spawn_subs - 1
		_check(failures, subs == want_subs,
			"(3) after press %d the world holds %d substations, expected %d — substations are accumulating or the dense block lost one" % [i + 1, subs, want_subs])
		_check(failures, int(res.get("components", -1)) == (EXPECTED_COMPONENTS_BRIDGED if expect_present else EXPECTED_COMPONENTS_SPLIT),
			"(3) press %d reported %d components, expected %d — this number goes straight into the toast" % [i + 1, int(res.get("components", -1)), EXPECTED_COMPONENTS_BRIDGED if expect_present else EXPECTED_COMPONENTS_SPLIT])

	_check(failures, expect_present,
		"(3) TOGGLE_PRESSES must be even so the rig ends bridged and the comparison below is against the spawn state")
	_check(failures, world.buildings.size() == spawn_buildings,
		"(3) after %d presses the world holds %d buildings, expected the spawn count %d" % [TOGGLE_PRESSES, world.buildings.size(), spawn_buildings])
	for anchor in gens:
		var g: Building = world.building_at(anchor)
		_check(failures, g != null and g.type == Buildings.Type.STEAM_GENERATOR and g.anchor == anchor,
			"(3) the toggle disturbed the generator at %s — main.gd's lever points at that anchor for the whole session" % str(anchor))
	_teardown(world)

# ===========================================================================
# (4) THE OVERLAP CONSUMER — scenario 2.
#
# One lamp inside a basic pole's radius-1 AND the bridge substation's radius-4.
# What is asserted is exactly what the human can see:
#
#   both poles really do cover it (distance vs that tier's SUPPLY_RADIUS_BY_TYPE
#     entry, read through PowerNetwork.supply_radius rather than hard-coded);
#   it resolves to a component with the bridge present;
#   it STILL resolves, to cluster A's component, with the bridge gone;
#   it is powered in both states.
#
# WHAT IS NOT ASSERTED, on purpose: which pole wins. The nearest-pole tie-break
# in _covering_component_id is currently unobservable — any two poles covering
# the same cell are already in the same component, proved in that function's
# docstring — so an assertion about the winner would be an assertion about dead
# code, and would go green whichever pole the scan happened to reach first.
#
# _covering_component_id is reached into directly because there is no public
# per-CELL component query: network_id_at answers for pole ANCHORS only. It is
# also the single source of truth for the radius rule, which is the rule this
# sub-case is about, so asserting through it is the point rather than a
# shortcut.
# ===========================================================================
static func _case_overlap_consumer(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)
	var lamp: Vector2i = RIG_ORIGIN + PoleGameplayRig.OVERLAP_LAMP
	var basic: Vector2i = RIG_ORIGIN + PoleGameplayRig.CLUSTER_A_POLES[1]
	var bridge: Vector2i = rig.get("bridge_anchor", Vector2i.ZERO)

	var lamp_b: Building = world.building_at(lamp)
	_check(failures, lamp_b != null and lamp_b.type == Buildings.Type.ELECTRIC_LAMP,
		"(4) OVERLAP_LAMP %s does not hold an ELECTRIC_LAMP" % str(lamp))

	var d_basic: int = _cheb_to_footprint(lamp, basic, Buildings.Type.POWER_POLE)
	var d_sub: int = _cheb_to_footprint(lamp, bridge, Buildings.Type.SUBSTATION)
	_check(failures, d_basic <= PowerNetwork.supply_radius(Buildings.Type.POWER_POLE),
		"(4) the overlap lamp is %d from the basic pole %s, outside its supply radius %d" % [d_basic, str(basic), PowerNetwork.supply_radius(Buildings.Type.POWER_POLE)])
	_check(failures, d_sub <= PowerNetwork.supply_radius(Buildings.Type.SUBSTATION),
		"(4) the overlap lamp is %d from the bridge footprint %s, outside its supply radius %d — then it is not an OVERLAP at all" % [d_sub, str(bridge), PowerNetwork.supply_radius(Buildings.Type.SUBSTATION)])
	# The overlap has to be a real one: strictly inside BOTH, not merely inside
	# the wide tier while the basic pole happens to be one tile too far.
	_check(failures, d_basic > 0 and d_sub > d_basic,
		"(4) the overlap lamp is %d from the basic pole and %d from the substation — the exhibit wants two DIFFERENT tiers covering it" % [d_basic, d_sub])

	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)
	var comp_on: int = PowerNetwork._covering_component_id(world, lamp)
	_check(failures, comp_on >= 0,
		"(4) bridged, the overlap lamp %s resolves to no component" % str(lamp))
	_check(failures, comp_on == PowerNetwork.network_id_at(world, basic),
		"(4) bridged, the overlap lamp resolves to component %d but its basic pole is on %d — bridged they are the same network, so these cannot differ" % [comp_on, PowerNetwork.network_id_at(world, basic)])
	_check(failures, PowerNetwork.power_satisfaction_at(world, lamp) > 0.0,
		"(4) bridged, the overlap lamp is unpowered")

	PoleGameplayRig.set_bridge(world, RIG_ORIGIN, false)
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)
	var comp_off: int = PowerNetwork._covering_component_id(world, lamp)
	_check(failures, comp_off >= 0,
		"(4) with the bridge removed the overlap lamp %s resolves to no component — the basic pole one tile away must still cover it" % str(lamp))
	_check(failures, comp_off == PowerNetwork.network_id_at(world, basic),
		"(4) with the bridge removed the overlap lamp resolves to component %d, not its basic pole's %d" % [comp_off, PowerNetwork.network_id_at(world, basic)])
	_check(failures, PowerNetwork.power_satisfaction_at(world, lamp) > 0.0,
		"(4) with the bridge removed the overlap lamp went dark — staying lit across the toggle is the entire exhibit")
	_teardown(world)

# ===========================================================================
# (5) THE 5-TILE BASIC <-> MEDIUM LINK — scenario 3, the either-reaches rule as
# one wire.
#
# 5 > POLE_RANGE_BY_TYPE[POWER_POLE] (3) and 5 <= POLE_RANGE_BY_TYPE
# [MEDIUM_POLE] (6). So max(3, 6) = 6 joins the pair and min(3, 6) = 3 does not.
# Both range constants are read through PowerNetwork.pole_range rather than
# written as literals, so a tier retune reddens this instead of silently
# turning the exhibit into a pair of poles that would connect under any rule.
#
# Asserted THREE ways, and they fail for different reasons:
#   the predicate — poles_connected, the single source of truth for "wired";
#   the component — the pair is a component of exactly TWO, so nothing else on
#     the screen has drifted into reach of it;
#   the wire — wire_edges emits the edge, because a link the BFS believes in
#     and the renderer does not draw is invisible to the human at the gate.
# ===========================================================================
static func _case_either_reaches_link(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	PoleGameplayRig.build(world, RIG_ORIGIN)
	var basic: Vector2i = RIG_ORIGIN + PoleGameplayRig.SCENARIO3_BASIC
	var medium: Vector2i = RIG_ORIGIN + PoleGameplayRig.SCENARIO3_MEDIUM

	var mb: Building = world.building_at(medium)
	_check(failures, mb != null and mb.type == Buildings.Type.MEDIUM_POLE,
		"(5) SCENARIO3_MEDIUM %s does not hold a MEDIUM_POLE" % str(medium))
	var d: int = _cheb_to_footprint(basic, medium, Buildings.Type.MEDIUM_POLE)
	_check(failures, d == SCENARIO3_DISTANCE,
		"(5) the pair is %d apart, expected exactly %d" % [d, SCENARIO3_DISTANCE])
	_check(failures, d > PowerNetwork.pole_range(Buildings.Type.POWER_POLE),
		"(5) %d is within the basic tier's range %d, so this pair would connect under a both-reaches min() too and proves nothing" % [d, PowerNetwork.pole_range(Buildings.Type.POWER_POLE)])
	_check(failures, d <= PowerNetwork.pole_range(Buildings.Type.MEDIUM_POLE),
		"(5) %d is beyond the medium tier's range %d, so the pair does not connect at all" % [d, PowerNetwork.pole_range(Buildings.Type.MEDIUM_POLE)])

	PowerNetwork.rebuild_topology(world)
	_check(failures, PowerNetwork.poles_connected(world, basic, medium),
		"(5) poles_connected says %s and %s are not wired — either-reaches is max(range_a, range_b) and the medium tier's 6 covers 5" % [str(basic), str(medium)])
	var id_basic: int = PowerNetwork.network_id_at(world, basic)
	_check(failures, id_basic >= 0 and id_basic == PowerNetwork.network_id_at(world, medium),
		"(5) the pair is on components %d and %d" % [id_basic, PowerNetwork.network_id_at(world, medium)])
	_check(failures, _component_size(world, id_basic) == 2,
		"(5) scenario 3's component holds %d poles, expected exactly 2 — something else has drifted into reach and the exhibit is no longer one wire" % _component_size(world, id_basic))
	_check(failures, _has_edge(PowerNetwork.wire_edges(world), basic, medium),
		"(5) no wire is drawn between %s and %s — the rule holds in the BFS but the human sees nothing" % [str(basic), str(medium)])
	_teardown(world)

# ===========================================================================
# (6) THE DENSE BLOCK — scenario 4.
#
# 16 poles across all three tiers, on ONE component, and separate from
# everything else. The WIRE COUNT is deliberately NOT asserted: whether Gabriel
# reads as noisy at this density is the judgement PAUSE 2 exists to make, and an
# expected-count literal here would turn a judgement into a ratification.
#
# What IS asserted is everything the judgement depends on being true:
#   all 16 poles are actually in one component, so the wires the human counts
#     are the wires of one graph rather than several;
#   all three tiers are present, so it is a MIXED-tier block;
#   its component holds exactly 16, so neither cluster nor the scenario-3 pair
#     has leaked into it. That last one is the isolation margin — 3 tiles at its
#     tightest, the bridge substation's reach of 11 against 14 — under test.
# ===========================================================================
static func _case_dense_block(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	PoleGameplayRig.build(world, RIG_ORIGIN)
	PowerNetwork.rebuild_topology(world)

	var dense: Array = []
	for p in PoleGameplayRig.DENSE_SUBSTATIONS:
		dense.append(RIG_ORIGIN + (p as Vector2i))
	for p in PoleGameplayRig.DENSE_MEDIUM_POLES:
		dense.append(RIG_ORIGIN + (p as Vector2i))
	for p in PoleGameplayRig.DENSE_BASIC_POLES:
		dense.append(RIG_ORIGIN + (p as Vector2i))
	_check(failures, dense.size() == EXPECTED_DENSE_POLES,
		"(6) the dense block lists %d poles, expected exactly %d" % [dense.size(), EXPECTED_DENSE_POLES])

	var tiers: Dictionary = {}
	for anchor in dense:
		var b: Building = world.building_at(anchor)
		if b == null:
			_check(failures, false, "(6) no building at dense-block cell %s" % str(anchor))
			continue
		tiers[b.type] = true
	_check(failures, tiers.has(Buildings.Type.POWER_POLE) and tiers.has(Buildings.Type.MEDIUM_POLE) and tiers.has(Buildings.Type.SUBSTATION),
		"(6) the dense block is not mixed-tier — it must hold all three of POWER_POLE, MEDIUM_POLE and SUBSTATION")

	var first_id: int = PowerNetwork.network_id_at(world, dense[0])
	_check(failures, first_id >= 0,
		"(6) the dense block's first pole %s is on no component" % str(dense[0]))
	for anchor in dense:
		_check(failures, PowerNetwork.network_id_at(world, anchor) == first_id,
			"(6) dense-block pole %s is on component %d, not the block's %d" % [str(anchor), PowerNetwork.network_id_at(world, anchor), first_id])
	_check(failures, _component_size(world, first_id) == EXPECTED_DENSE_POLES,
		"(6) the dense block's component holds %d poles, expected exactly %d — anything else has merged into it and its wire count stops being a fair reading of this block" % [_component_size(world, first_id), EXPECTED_DENSE_POLES])
	_teardown(world)

# ===========================================================================
# (7) THE POWER ARITHMETIC — what the F8 lever's satisfaction maths needs.
#
# (7a) Total raw supply across every component is 40, two generators at
#      SteamGenerator.MAX_OUTPUT. It does not care how the poles are grouped,
#      only that each generator found SOME pole in its cardinal edge ring, so it
#      is the assertion that catches the layout defect (1) describes. Sub-case
#      (2) cannot: components merge and split identically whether or not a
#      single generator is connected.
#
# (7b) Total demand is exactly 40, summed across ALL components rather than read
#      off one, because in the split state there is no single component holding
#      it. Asserted with == on purpose, mirroring both older rigs: the three
#      lever positions land on 1.00 / 0.50 / 0.00 only because supply arrives in
#      20-unit blocks against a demand of exactly 40. Miss by one lamp and
#      brownout quietly becomes 20/39 = 0.5128 while every test still passes.
#
# (7c) BRIDGED, all 40 of each land on ONE component at satisfaction exactly
#      1.00. 40/40 is exact in binary floating point, so == rather than
#      is_equal_approx.
#
# (7d) SPLIT, exactly two components carry demand and each carries 20 supply
#      against 20 demand. This is the assertion that makes the split state worth
#      looking at: an 11/29 split would still merge and split correctly and
#      would still total 40, and BROWNOUT would then read as two half-lit
#      clusters instead of one bright and one black.
#
# (7e) SPLIT and browned out, cluster A holds 1.00 and cluster B holds 0.00.
#      ElectricRig.FUELLED_BY_STATE is [2, 1, 0] and fuels the FIRST anchors, so
#      this also pins plan()'s generator ORDER: swap the two and the human
#      watches the wrong half go dark.
#
# No ticking anywhere. build() ends with apply_power_state(POWER_FULL,
# seed_output = true), which writes output_active directly, so the supply
# pre-pass sees both generators lit on its first run. supply_for() returns
# raw + accumulator terms, and this rig contains no ACCUMULATOR by design, so it
# is raw supply exactly.
# ===========================================================================
static func _case_power(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)

	var comps: Array = _unique_components(world)
	var total_supply: int = 0
	var total_demand: int = 0
	var bus_ids: Array = []
	for comp_id in comps:
		total_supply += PowerNetwork.supply_for(world, comp_id)
		total_demand += PowerNetwork.demand_for(world, comp_id)
		if PowerNetwork.demand_for(world, comp_id) > 0:
			bus_ids.append(comp_id)

	# --- (7a) ---
	_check(failures, total_supply == EXPECTED_SUPPLY,
		"(7a) total raw supply across all %d components is %d, expected exactly %d — a generator that does not cardinally touch a pole contributes 0, and demand stays 40 either way, so nothing else here can see that" % [comps.size(), total_supply, EXPECTED_SUPPLY])
	# --- (7b) ---
	_check(failures, total_demand == EXPECTED_DEMAND,
		"(7b) total network demand is %d, expected exactly %d — the lever's 0.50 midpoint depends on this" % [total_demand, EXPECTED_DEMAND])

	# --- (7c) ---
	_check(failures, bus_ids.size() == 1,
		"(7c) bridged, %d components carry demand, expected exactly 1 — the dense block and the scenario-3 pair must stay consumer-free and the bus must not be split" % bus_ids.size())
	if bus_ids.size() == 1:
		var bus: int = int(bus_ids[0])
		_check(failures, PowerNetwork.supply_for(world, bus) == EXPECTED_SUPPLY,
			"(7c) the bridged bus carries %d supply, expected exactly %d" % [PowerNetwork.supply_for(world, bus), EXPECTED_SUPPLY])
		_check(failures, PowerNetwork.demand_for(world, bus) == EXPECTED_DEMAND,
			"(7c) the bridged bus carries %d demand, expected exactly %d" % [PowerNetwork.demand_for(world, bus), EXPECTED_DEMAND])
		_check(failures, PowerNetwork.satisfaction_for(world, bus) == 1.0,
			"(7c) bridged bus satisfaction at POWER_FULL is %f, expected exactly 1.0" % PowerNetwork.satisfaction_for(world, bus))

	# --- (7d) ---
	PoleGameplayRig.set_bridge(world, RIG_ORIGIN, false)
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)
	var loaded: Array = []
	for comp_id in _unique_components(world):
		if PowerNetwork.demand_for(world, comp_id) > 0:
			loaded.append(comp_id)
	_check(failures, loaded.size() == 2,
		"(7d) split, %d components carry demand, expected exactly 2 — one per cluster" % loaded.size())
	for comp_id in loaded:
		_check(failures, PowerNetwork.demand_for(world, comp_id) == EXPECTED_CLUSTER_DEMAND,
			"(7d) split, component %d carries %d demand, expected exactly %d per cluster" % [comp_id, PowerNetwork.demand_for(world, comp_id), EXPECTED_CLUSTER_DEMAND])
		_check(failures, PowerNetwork.supply_for(world, comp_id) == EXPECTED_CLUSTER_SUPPLY,
			"(7d) split, component %d carries %d supply, expected exactly %d — each cluster owns one generator" % [comp_id, PowerNetwork.supply_for(world, comp_id), EXPECTED_CLUSTER_SUPPLY])

	# --- (7e) ---
	var gens: Array = rig.get("gen_anchors", [])
	ElectricRig.apply_power_state(world, gens, PoleGameplayRig.POWER_BROWNOUT, true)
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)
	var a_far: Vector2i = RIG_ORIGIN + PoleGameplayRig.CLUSTER_A_POLES[1]
	var b_near: Vector2i = RIG_ORIGIN + PoleGameplayRig.CLUSTER_B_POLES[0]
	var sat_a: float = PowerNetwork.satisfaction_for(world, PowerNetwork.network_id_at(world, a_far))
	var sat_b: float = PowerNetwork.satisfaction_for(world, PowerNetwork.network_id_at(world, b_near))
	_check(failures, sat_a == 1.0,
		"(7e) split and browned out, cluster A reads %f, expected exactly 1.0 — it owns gen_anchors[0], the one the lever keeps fuelled" % sat_a)
	_check(failures, sat_b == 0.0,
		"(7e) split and browned out, cluster B reads %f, expected exactly 0.0 — going fully dark is what makes the split state worth looking at" % sat_b)
	_teardown(world)

# ===========================================================================
# (8) RE-SPAWNING ONTO THE STANDING RIG ADOPTS IT.
#
# Shared plumbing with the other two rigs, and the failure it guards is silent
# and slow: the spawn key twice on the same tile collides on all 48 cells,
# without adoption that yields placed == 0 and an EMPTY gen_anchors, main.gd
# stores the empty array, _sustain_rig_power early-returns on it, and the rig on
# screen — visibly complete — burns its 16-unit fuel buffers and goes dark about
# 16 seconds later with F8 refusing to touch it.
#
# So the assertion that matters is the THIRD one: adoption has to hand back the
# generators standing on the ground, not merely report a boolean.
#
# THE BRIDGE HAS ITS OWN ARM HERE, and it is the reason it is not in plan(). A
# re-spawn onto a rig the user has toggled OFF must still adopt — 48 planned
# cells are all exactly right, and the missing substation is a user-facing
# variable, not a broken rig. It must also RESTORE the bridge, so what the
# player gets back is the rig as it spawns rather than half of it.
# ===========================================================================
static func _case_adoption(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var first: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)
	var again: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)

	_check(failures, bool(again.get("adopted", false)),
		"(8) a second build over an intact rig did not report adopted")
	_check(failures, int(again["placed"]) == 0,
		"(8) adoption placed %d buildings — it must build nothing" % int(again["placed"]))
	_check(failures, (again["gen_anchors"] as Array) == (first["gen_anchors"] as Array),
		"(8) adopted gen_anchors %s do not match the rig on the ground %s — an empty or wrong list is what silently kills the F8 lever" % [str(again["gen_anchors"]), str(first["gen_anchors"])])

	# Toggled OFF, then re-spawned: still adoption, and the bridge comes back.
	PoleGameplayRig.set_bridge(world, RIG_ORIGIN, false)
	var after_off: Dictionary = PoleGameplayRig.build(world, RIG_ORIGIN)
	_check(failures, bool(after_off.get("adopted", false)),
		"(8) re-spawning onto a rig whose bridge is toggled OFF did not adopt — the bridge is a user-facing variable, not a missing piece, which is why it is outside plan()")
	_check(failures, bool(after_off.get("bridge_present", false)),
		"(8) re-spawning did not restore the bridge — a re-spawn must hand back the rig as it spawns")
	_check(failures, (after_off["gen_anchors"] as Array) == (first["gen_anchors"] as Array),
		"(8) re-spawning over a toggled-off rig lost the generator anchors")

	# A PARTIAL overlap must NOT read as adoptable: that is the collision case,
	# and reporting it as adopted would tell the user the lever re-attached to a
	# rig that is actually missing pieces. One foreign building on a planned cell
	# is enough to prove the all-or-nothing rule.
	var world_c = _make_world(parent)
	var lamp_cell: Vector2i = RIG_ORIGIN + PoleGameplayRig.LAMPS_CLUSTER_A[0]
	world_c.tiles[lamp_cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
	world_c.set_overlay(lamp_cell, Terrain.Overlay.STONE)
	world_c.place_building(Buildings.Type.CHEST, lamp_cell, 0)
	var partial: Dictionary = PoleGameplayRig.build(world_c, RIG_ORIGIN)
	_check(failures, not bool(partial.get("adopted", false)),
		"(8) a rig with one foreign building on a planned cell must NOT read as adoptable")
	_check(failures, int(partial["skipped"]) == 1,
		"(8) expected exactly 1 skipped placement against one foreign building, got %d" % int(partial["skipped"]))
	_teardown(world_c)
	_teardown(world)

# ---------- helpers ----------

static func _unique_components(world) -> Array:
	var seen: Dictionary = {}
	for pos in world._pole_component:
		seen[int(world._pole_component[pos])] = true
	return seen.keys()

## How many poles carry component id `comp_id`.
static func _component_size(world, comp_id: int) -> int:
	var n: int = 0
	for pos in world._pole_component:
		if int(world._pole_component[pos]) == comp_id:
			n += 1
	return n

static func _count_type(world, t: int) -> int:
	var n: int = 0
	for anchor in world.buildings:
		if world.buildings[anchor].type == t:
			n += 1
	return n

## Is [a, b] (in either order) in the edge list PowerNetwork.wire_edges emitted?
##
## Both orders are accepted although wire_edges emits lex-smaller first: the
## renderer draws a segment, which has no direction, so an assertion that
## depended on emission order would be pinning an implementation detail rather
## than what is on screen.
static func _has_edge(edges: Array, a: Vector2i, b: Vector2i) -> bool:
	for e in edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return true
	return false

## How many emitted edges have BOTH endpoints in `anchors`. The counterpart to
## _has_edge: that one pins wires that must be there, this one pins that nothing
## ELSE is, which is the half a set of existence checks cannot cover.
static func _edges_among(edges: Array, anchors: Array) -> int:
	var n: int = 0
	for e in edges:
		if anchors.has(e[0]) and anchors.has(e[1]):
			n += 1
	return n

## Chebyshev distance from a single cell to the NEAREST footprint cell of the
## building anchored at `anchor`. That is the metric _covering_component_id uses
## for supply areas and the one _pole_distance reduces to when one side is 1x1,
## and it is written out here rather than reused so a change to either of those
## reddens this file instead of moving with it.
static func _cheb_to_footprint(cell: Vector2i, anchor: Vector2i, t: int) -> int:
	var fp: Vector2i = Buildings.footprint_of(t)
	var best: int = -1
	for dy in range(fp.y):
		for dx in range(fp.x):
			var c: Vector2i = anchor + Vector2i(dx, dy)
			var d: int = max(abs(cell.x - c.x), abs(cell.y - c.y))
			if best < 0 or d < best:
				best = d
	return best

## Does a POLE of any tier sit on one of the building's edge cells? Reimplements
## the generator-side adjacency rule through the same Buildings.all_edge_cells
## helper PowerNetwork._adjacent_component_id uses, rather than asserting on
## coordinates the layout could quietly move.
##
## Buildings.POLE_TYPES, not POWER_POLE specifically: this rig's generators
## happen to touch basic poles, but the rule _adjacent_component_id runs accepts
## any tier, and a test stricter than the rule would redden a correct layout.
static func _touches_pole(world, anchor: Vector2i) -> bool:
	var b: Building = world.building_at(anchor)
	if b == null:
		return false
	for cell in Buildings.all_edge_cells(b.type, b.anchor):
		if not world.has_building_at(cell):
			continue
		var nb: Building = world.building_at(cell)
		if nb != null and Buildings.POLE_TYPES.has(nb.type):
			return true
	return false

## There is NO generate_default_world() on GridWorld — it does not exist in the
## repo. A fresh GridWorld has an empty `tiles` dict, so every cell reads
## DEFAULT_BASE (GRASS) / DEFAULT_OVERLAY (NONE), and PoleGameplayRig.build paves
## its own rectangles regardless. House pattern, shared with test_electric_rig.gd
## and test_pole_tier_rig.gd.
static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE queue_free. queue_free is deferred until after the runner's
## synchronous _ready returns, and this file builds several worlds in sequence,
## so without the disconnect every world built here would still be listening on
## TickSystem.tick while later tests emit ticks. Same shape as
## test_pole_tier_rig.gd's _teardown.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
