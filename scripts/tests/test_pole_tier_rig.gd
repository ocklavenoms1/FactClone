extends RefCounted

## POLE TIER RIG (Electricity Session 3, PAUSE 1) — the layout the human looks
## at, asserted headlessly so what the test proves and what they see cannot
## drift. Drives PoleTierRig.build, the same entry point main.gd calls.
##
## THIS TEST IS RED UNTIL TASK 7. That is deliberate: the rig is built BEFORE
## the tier logic (last session's lesson — a gate should be a looking exercise,
## not a construction exercise), so this file is the scenario-level RED that
## Tasks 4-7 turn green.
##
## Expected state of each sub-case as of Task 3, with why:
##
##   (1) layout lands ......................... PASSES. Both tiers became
##       placeable at Task 2, so nothing here depends on network logic.
##   (2) demand is exactly 40 ................. FAILS at 30. rebuild_topology
##       still collects only Buildings.Type.POWER_POLE, so the ten lamps that
##       only the medium pole and the substation can reach resolve to no
##       component and contribute nothing.
##   (3) the substation bridges ............... FAILS at 3 components instead
##       of 2. The two new tiers are invisible to BFS, so the bridge does not
##       exist and cluster A / cluster B / the control block are three islands.
##   (4a) total raw supply is 40 .............. PASSES, and must keep passing.
##       Catches a generator that does not touch a pole — a defect this layout
##       has already had once. Sub-case (2) cannot see that defect, because
##       demand is 40 whether or not any generator is connected; (1)'s edge-ring
##       check sees it too, and the two are complementary rather than redundant
##       (see (1)'s header).
##   (4b) all 40 supply and all 40 demand on
##        ONE component, satisfaction 1.00 .... FAILS. The bus is split in two
##       and each half has 20 supply against a partial demand.
##   (5) re-spawn adopts ...................... PASSES, and must keep passing.
##       Pure spawn plumbing, independent of the tier logic.
##
## Do NOT "fix" (2) or (4b) by moving lamps next to basic poles. Those lamp
## positions are what prove the wide supply areas work once Task 5 lands.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Rig origin used by every sub-case. Non-zero on purpose: the rig carries
# negative rig-relative x on both the paving rectangle (PAVE_MIN.x = -2) and
# the building set (a lamp at x = -1), so an origin at (0,0) would let a sign
# error in the absolutise step hide behind coordinates that happen to still be
# legal.
const RIG_ORIGIN: Vector2i = Vector2i(40, 40)

# The totals the whole design rests on, as LITERALS and deliberately HERE
# rather than in pole_tier_rig.gd — the same decision, for the same reason, as
# EXPECTED_PLACEMENTS / EXPECTED_DEMAND in test_electric_rig.gd. A constant
# that lives beside the plan gets edited in the same breath as the plan, which
# would make these assertions self-referential: delete a lamp, adjust the
# neighbouring const, and the suite stays green while the brownout midpoint
# quietly becomes 20/39 = 0.5128.
#
#   36 placements = 8 basic poles + 1 medium pole + 1 substation
#                 + 2 steam generators + 4 electric inserters + 20 lamps
#   40 demand     = 4 inserters x 5 + 20 lamps x 1
#   40 supply     = 2 steam generators x SteamGenerator.MAX_OUTPUT (20)
const EXPECTED_PLACEMENTS: int = 36
const EXPECTED_DEMAND: int = 40
const EXPECTED_SUPPLY: int = 40

static func test_name() -> String:
	return "pole tier rig (layout lands + demand 40 + substation bridges + MST control block stays separate + supply 40 on one bus + re-spawn adopts)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_layout(parent, failures)
	_case_demand(parent, failures)
	_case_bridge(parent, failures)
	_case_supply(parent, failures)
	_case_adoption(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: layout lands + demand 40 + substation bridges + 40 supply on one bus at satisfaction 1.00 + re-spawn adopts" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) THE LAYOUT LANDS.
# Every number below is downstream of the rig being built in full. A silent
# skip (terrain guard, collision) makes later assertions fail for a reason that
# has nothing to do with what they claim to test, so this runs first.
#
# The generator-touches-a-pole check is not decoration. Generators feed the
# network through PowerNetwork._adjacent_component_id, which wants a pole in
# the CARDINAL EDGE RING — the consumers' wireless supply area does not apply
# to them. An earlier draft of this layout anchored both generators one row
# too far south, which put the pole row outside their rings: every placement
# still succeeded, demand was still exactly 40, and raw supply was silently 0
# in all three lever positions.
#
# This check and (4a) are COMPLEMENTARY, not redundant — the mutation was run
# and BOTH fire. Keep both. This one names the offending generator's
# coordinates, so it says where to look; (4a) reports the supply shortfall, so
# it also catches a bus that split for some reason having nothing to do with
# edge rings. Deleting either because the other exists loses real diagnosis.
# ===========================================================================
static func _case_layout(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleTierRig.build(world, RIG_ORIGIN)

	_check(failures, int(rig.get("skipped", -1)) == 0,
		"(1) the rig skipped %d placements, so the layout is incomplete and every later number is wrong" % int(rig.get("skipped", -1)))
	_check(failures, int(rig.get("placed", -1)) == EXPECTED_PLACEMENTS,
		"(1) placed %d buildings, expected exactly %d" % [int(rig.get("placed", -1)), EXPECTED_PLACEMENTS])
	# Cannot fail while the two checks above pass: build() increments exactly
	# one of placed/skipped per plan entry, so skipped == 0 and placed == 36
	# already force the plan to hold 36. Kept anyway, because that invariant is
	# a property of build()'s LOOP, not of the plan — an added `continue` that
	# skips an entry without counting it would break the chain, and this is the
	# assertion that would still notice. No single-line mutation reddens it
	# alone, and that is expected.
	_check(failures, PoleTierRig.plan().size() == EXPECTED_PLACEMENTS,
		"(1) the placement plan lists %d entries, expected exactly %d" % [PoleTierRig.plan().size(), EXPECTED_PLACEMENTS])

	var gens: Array = rig.get("gen_anchors", [])
	_check(failures, gens.size() == 2,
		"(1) expected 2 steam generators, got %d" % gens.size())
	for anchor in gens:
		_check(failures, _touches_pole(world, anchor),
			"(1) steam generator at %s does not CARDINALLY touch a power pole, so it feeds nothing" % str(anchor))

	# The substation is the building sub-case (3) removes, so its anchor has to
	# be a substation and not, say, a cell the plan drifted off.
	var sub: Building = world.building_at(rig["substation"])
	_check(failures, sub != null and sub.type == Buildings.Type.SUBSTATION and sub.anchor == rig["substation"],
		"(1) no SUBSTATION anchored at the reported substation cell %s" % str(rig["substation"]))
	_teardown(world)

# ===========================================================================
# (2) DEMAND IS EXACTLY 40.
# Asserted with == on purpose, mirroring test_electric_rig.gd. The three lever
# positions land on 1.00 / 0.50 / 0.00 only because supply arrives in 20-unit
# blocks against a demand of exactly 40. Miss by one lamp and brownout quietly
# becomes 20/39 = 0.5128 while every test still passes.
#
# Summed across ALL components rather than read off one: before Task 4 the bus
# is split, and a per-component read would need to already know which half to
# look at. The total is the number that has to reach 40 however the poles
# happen to be grouped.
# ===========================================================================
static func _case_demand(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	PoleTierRig.build(world, RIG_ORIGIN)
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)
	var total: int = 0
	for comp_id in _unique_components(world):
		total += PowerNetwork.demand_for(world, comp_id)
	_check(failures, total == EXPECTED_DEMAND,
		"(2) total network demand is %d, expected exactly %d — the lever's 0.50 midpoint depends on this" % [total, EXPECTED_DEMAND])
	_teardown(world)

# ===========================================================================
# (3) THE SUBSTATION BRIDGES, AND THE CONTROL BLOCK STAYS SEPARATE.
#
# With the substation: cluster A + the medium pole + the substation + cluster B
# are ONE component. The MST control block (east, basic poles only) is a SECOND
# component — it is a rendering control and must not be wired into the bus, or
# its wire count stops being comparable to the pre-MST behaviour.
#
# Without the substation: the bus splits. Cluster A and the medium pole stay
# joined (distance 5 <= the medium pole's 6, either-reaches), but cluster B is
# orphaned — it is 8 from the medium pole and 13 from cluster A. So removing
# one building goes 2 components -> 3.
#
# This sub-case IS the either-reaches decision, but through CLUSTER A only.
# Two links are min-rule tripwires — substation <-> cluster A's far pole at
# distance 9, and medium pole <-> that same pole at distance 5 — and both
# vanish under a both-reaches min(), severing cluster A and making this count
# 3 instead of 2. The substation's link to cluster B is only 3 footprint to
# footprint, which is inside basic range, so it forms under EITHER rule and is
# not evidence for anything. See the THE NUMBERS ARE THE TEST block in
# pole_tier_rig.gd, which carries the full arithmetic and the reason cluster B
# sits close enough for that to be true.
#
# NOTE for the Task 4 GREEN step: the SECOND half of this sub-case passes today
# for the wrong reason. Before Task 4 the substation is not in the topology at
# all, so removing it changes nothing and the count is 3 either way. Only the
# first half is a real RED right now.
# ===========================================================================
static func _case_bridge(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleTierRig.build(world, RIG_ORIGIN)
	PowerNetwork.rebuild_topology(world)
	var with_sub: int = _unique_components(world).size()
	_check(failures, with_sub == 2,
		"(3) with the substation there should be exactly 2 components (the bridged bus and the MST control block), got %d" % with_sub)

	# remove_building_at, NOT remove_building — see grid_world.gd, which has
	# only the former.
	world.remove_building_at(rig["substation"])
	PowerNetwork.rebuild_topology(world)
	var without_sub: int = _unique_components(world).size()
	_check(failures, without_sub == 3,
		"(3) removing the substation should orphan cluster B, giving 3 components, got %d — if this says 2 the bridge was never load-bearing" % without_sub)
	_teardown(world)

# ===========================================================================
# (4) SUPPLY. Two assertions with deliberately different lifetimes, because
# they fail for completely different reasons and collapsing them would hide
# one behind the other.
#
# (4a) TOTAL raw supply across every component is 40 — two generators at
#      SteamGenerator.MAX_OUTPUT 20. This is GREEN TODAY and must stay green
#      through Tasks 4-7. It does not care how the poles are grouped, only
#      that each generator found SOME pole in its cardinal edge ring, so it is
#      the assertion that catches the layout defect described on sub-case (1).
#      Sub-case (2) cannot catch it: demand is 40 whether or not any generator
#      is connected, so a rig with zero power ships looking green.
#
# (4b) All of that supply and all 40 of the demand land on ONE component, at
#      satisfaction exactly 1.00. This is the RED that Tasks 4, 5 and 7 turn
#      green, and it is the number the human actually reads off the Q-inspect
#      panel at PAUSE 1. Today the bus is two islands of 20 supply each,
#      carrying 16 and 14 demand, so there is no single component with 40 of
#      either.
#
# No ticking. PoleTierRig.build ends with apply_power_state(POWER_FULL,
# seed_output = true), which writes output_active directly, so the supply
# pre-pass sees both generators lit on its very first run. Ticking here would
# only add SteamGenerator's own fuel-derived rewrite of the same value.
#
# supply_for() returns _component_supply, which update_supply_demand sets to
# raw_supply + accumulator_supply - accumulator_drain. This rig contains no
# ACCUMULATOR by design, so that is raw supply exactly.
# ===========================================================================
static func _case_supply(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	PoleTierRig.build(world, RIG_ORIGIN)
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)

	var comps: Array = _unique_components(world)
	var total_supply: int = 0
	var bus_ids: Array = []
	for comp_id in comps:
		total_supply += PowerNetwork.supply_for(world, comp_id)
		if PowerNetwork.demand_for(world, comp_id) > 0:
			bus_ids.append(comp_id)

	# --- (4a) ---
	_check(failures, total_supply == EXPECTED_SUPPLY,
		"(4a) total raw supply across all %d components is %d, expected exactly %d — a generator that does not cardinally touch a pole contributes 0, and demand stays 40 either way, so sub-case (2) cannot see this" % [comps.size(), total_supply, EXPECTED_SUPPLY])

	# --- (4b) ---
	_check(failures, bus_ids.size() == 1,
		"(4b) %d components carry demand, expected exactly 1 (the bridged bus) — the MST control block must stay consumer-free and the bus must not be split" % bus_ids.size())
	if bus_ids.size() != 1:
		_teardown(world)
		return
	var bus: int = int(bus_ids[0])
	var bus_supply: int = PowerNetwork.supply_for(world, bus)
	var bus_demand: int = PowerNetwork.demand_for(world, bus)
	_check(failures, bus_supply == EXPECTED_SUPPLY,
		"(4b) the bus carries %d supply, expected exactly %d" % [bus_supply, EXPECTED_SUPPLY])
	_check(failures, bus_demand == EXPECTED_DEMAND,
		"(4b) the bus carries %d demand, expected exactly %d" % [bus_demand, EXPECTED_DEMAND])
	# Compared EXACTLY, not is_equal_approx: 40/40 is exact in binary floating
	# point and the whole lever design claims these values are exact.
	var sat: float = PowerNetwork.satisfaction_for(world, bus)
	_check(failures, sat == 1.0,
		"(4b) bus satisfaction at POWER_FULL is %f, expected exactly 1.0" % sat)
	_teardown(world)

# ===========================================================================
# (5) RE-SPAWNING ONTO THE STANDING RIG ADOPTS IT.
#
# GREEN TODAY, and unlike the rest of this file it has nothing to do with the
# tier logic — it is pure spawn plumbing, so it must stay green through Tasks
# 4-7 as well.
#
# The failure it guards is silent and slow. F7 -> Shift+F7 -> F7 without
# moving collides on all 36 cells. Without adoption that yields placed == 0 and
# an EMPTY gen_anchors, main.gd stores the empty array, _sustain_rig_power
# early-returns on it, and the rig on screen — visibly complete — burns its
# 16-unit fuel buffers and goes dark about 16 seconds later with F8 refusing to
# touch it. Nothing about that reads as "the respawn did not take".
#
# So the assertion that matters is the THIRD one: adoption has to hand back the
# generators standing on the ground, not merely report a boolean.
# ===========================================================================
static func _case_adoption(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var first: Dictionary = PoleTierRig.build(world, RIG_ORIGIN)
	var again: Dictionary = PoleTierRig.build(world, RIG_ORIGIN)

	_check(failures, bool(again.get("adopted", false)),
		"(5) a second build over an intact rig did not report adopted")
	_check(failures, int(again["placed"]) == 0,
		"(5) adoption placed %d buildings — it must build nothing" % int(again["placed"]))
	_check(failures, (again["gen_anchors"] as Array) == (first["gen_anchors"] as Array),
		"(5) adopted gen_anchors %s do not match the rig on the ground %s — an empty or wrong list is what silently kills the F8 lever" % [str(again["gen_anchors"]), str(first["gen_anchors"])])

	# A PARTIAL overlap must NOT read as adoptable: that is the collision case,
	# and reporting it as adopted would tell the user the lever re-attached to a
	# rig that is actually missing pieces. One foreign building on a planned
	# cell is enough to prove the all-or-nothing rule.
	var world_c = _make_world(parent)
	var lamp_cell: Vector2i = RIG_ORIGIN + PoleTierRig.LAMP_OFFSETS[0]
	world_c.tiles[lamp_cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
	world_c.set_overlay(lamp_cell, Terrain.Overlay.STONE)
	world_c.place_building(Buildings.Type.CHEST, lamp_cell, 0)
	var partial: Dictionary = PoleTierRig.build(world_c, RIG_ORIGIN)
	_check(failures, not bool(partial.get("adopted", false)),
		"(5) a rig with one foreign building on a planned cell must NOT read as adoptable")
	_check(failures, int(partial["skipped"]) == 1,
		"(5) expected exactly 1 skipped placement against one foreign building, got %d" % int(partial["skipped"]))
	_teardown(world_c)
	_teardown(world)

# ---------- helpers ----------

static func _unique_components(world) -> Array:
	var seen: Dictionary = {}
	for pos in world._pole_component:
		seen[int(world._pole_component[pos])] = true
	return seen.keys()

## Does a POWER_POLE sit on one of the building's edge cells? Reimplements the
## generator-side adjacency rule through the same Buildings.all_edge_cells
## helper PowerNetwork._adjacent_component_id uses, rather than asserting on
## coordinates the layout could quietly move.
static func _touches_pole(world, anchor: Vector2i) -> bool:
	var b: Building = world.building_at(anchor)
	if b == null:
		return false
	for cell in Buildings.all_edge_cells(b.type, b.anchor):
		if not world.has_building_at(cell):
			continue
		var nb: Building = world.building_at(cell)
		if nb != null and nb.type == Buildings.Type.POWER_POLE:
			return true
	return false

## There is NO generate_default_world() on GridWorld — it does not exist in the
## repo. A fresh GridWorld has an empty `tiles` dict, so every cell reads
## DEFAULT_BASE (GRASS) / DEFAULT_OVERLAY (NONE), and PoleTierRig.build paves
## its own rectangle regardless. House pattern, shared with
## test_electric_rig.gd.
static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE queue_free. queue_free is deferred until after the
## runner's synchronous _ready returns, and this file builds four worlds in
## sequence, so without the disconnect every world built here would still be
## listening on TickSystem.tick while later tests emit ticks. Same shape as
## test_electric_rig.gd's _teardown.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
