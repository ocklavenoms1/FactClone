class_name PoleTierRig
extends RefCounted

## POLE TIER SMOKE-TEST RIG (session-electricity-pole-tiers, PAUSE 1).
##
## Two things to look at, side by side, in one screen. Both blocks sit BELOW
## the player and run west-to-east across seven building rows (y 0..6, paved
## y 0..7), so the whole rig is one glance with no scrolling. The row count is
## not cosmetic — ORIGIN_OFFSET's clearance measurement is derived from where
## the LAST row lands, so anything that adds a row has to re-measure.
##
##   THE BUS (west, x -1..20) — the MIXED-TIER topology demo. Two basic-pole
##   clusters too far apart to see each other, each with its OWN steam
##   generator and its own consumers, plus a MEDIUM POLE and ONE SUBSTATION
##   positioned to bridge them. Without the substation there are two networks;
##   with it there is one. That is what makes the either-reaches rule and the
##   substation's range 11 visible rather than merely asserted.
##
##   THE CONTROL BLOCK (east, x 26..29) — the MST REGRESSION CONTROL. Basic
##   poles ONLY, four of them in a square 3 apart on both axes, which is the
##   dense arrangement behind the original complaint: POLE_RANGE was cut from
##   5 to 3 at Foundation PAUSE 1 because a 5-tile range "produced too many
##   in-range pairs in dense layouts (K4 with 6 wires for 4 poles)" — see the
##   POLE_RANGE_BY_TYPE docstring in power_network.gd, which is where that
##   history moved when Task 4 replaced the flat POLE_RANGE const with the
##   per-tier table. Session 3 replaces mesh
##   rendering with a minimum spanning tree, which changes SHIPPED,
##   GATE-APPROVED visuals, so the simple basic-pole case needs to be judged
##   against what it looked like before. All six pairs in this square are at
##   Chebyshev exactly 3 — still the whole K4 under the CURRENT range — so the
##   mesh renderer draws six wires here and the MST must draw three.
##
## Demand is pinned at exactly 40, matching the electric rig, so the
## satisfaction numbers read the same and the F8 lever behaves identically.
## Composition:
##    4 x ELECTRIC_INSERTER @ Inserter.POWER_DEMAND_BY_TYPE = 5  -> 20
##   20 x ELECTRIC_LAMP     @ ElectricLamp.DEMAND           = 1  -> 20
## ALL of it sits on the BUS. The control block carries no consumers at all:
## it is a wire-rendering exhibit, and a lamp inside it would split the demand
## total across two components and move the brownout midpoint off 0.50.
##
## Deliberately ABSENT, and must stay absent: ACCUMULATOR (Stage 2 charge and
## discharge smears the crisp 1.00 / 0.50 / 0.00 states into ramps) and
## WINDMILL (its supply arm reads state.get("output_active", TRUE) —
## power_network.gd Stage 1 — so one touching any pole on the bus silently
## adds 6 units and moves the midpoint off 0.50). There are also no CHESTs and
## no BELTs anywhere in this rig: nothing here is meant to move items, and
## Burner.try_pull_fuel reacts to exactly those two types, so their absence is
## what makes the F8 lever the only thing that can change a generator's fuel.
##
## This module owns the LAYOUT. main.gd owns the key binding and the toast.
## The power LEVER is reused verbatim from ElectricRig — the two rigs share a
## generator contract, so there is exactly one implementation of "how many
## generators have fuel" and it cannot drift between scenarios.

# Rig origin relative to the player tile at spawn time. The rig is wide and
# short so both blocks fit one 1280x720 screen with the bottom row clear of
# the hotbar strip.
#
# MEASURED, not derived, exactly as ElectricRig.ORIGIN_OFFSET was. The
# arithmetic that makes the measurement checkable: TILE_SIZE is 32, the
# camera in scenes/main.tscn is authored at zoom 1.5, and the 1920x1080
# viewport is presented in a 1280x720 window (2/3), so 32 * 1.5 * 2/3 = 32
# screen pixels per tile at capture resolution. The camera centres on the
# player, so the tile row N below the player has its top edge at screen
# y = 344 + 32N.
#
# The hotbar's top edge, derived from hotbar.gd rather than eyeballed: its
# height is HEADER_HEIGHT 22 + SLOT_SIZE 64 + LABEL_AREA_HEIGHT 32 + 8 = 126,
# and _apply_layout anchors it to the viewport bottom with offset_top =
# -h - 12. So it starts at 1080 - 138 = 942 in viewport units, which is
# 942 * 2/3 = 628 on the captured 720-px frame.
#
# With y = 1 the paved rows are player+1 .. player+8 and the lowest BUILDING
# row (rig y 6) spans screen y 568..600, clearing the hotbar by 28 px. That is
# under a full tile, so this offset is not free to drift downward — but it is
# comfortably more than the ~8 px that had the electric rig's bottom-row fill
# bars reading as cut off. The whole rig is below the player, so the player's
# own tile is never inside the footprint and can never collide with a
# placement. x = -14 centres the 33-column paved rectangle on the player's
# column.
const ORIGIN_OFFSET: Vector2i = Vector2i(-14, 1)

# Phase 1 paving rectangle, INCLUSIVE, in rig-relative coordinates. Strictly
# contains every building cell (x -1..29, y 0..6) with a one-tile margin on
# three sides. There is no margin above row 0 on purpose: a row of stone above
# the top lamps would be the first thing the eye lands on and it borders
# nothing.
const PAVE_MIN: Vector2i = Vector2i(-2, 0)
const PAVE_MAX: Vector2i = Vector2i(30, 7)

# --- THE BUS: mixed-tier bridge demo ---------------------------------------
# Everything that carries power sits on row y = 2. Cluster A basic poles at
# x = 0 and 3 (Chebyshev 3 apart: exactly POLE_RANGE, so they join). Cluster B
# at x = 16 and 19. The clusters are 13 apart, far beyond basic range 3, and
# the medium pole cannot bridge them either: it reaches cluster A at 5 but is
# 8 from cluster B. Only the substation closes that gap.
#
# CLUSTER B SITS AT 16/19 FOR SCREEN FIT, not for the topology. The plan put
# it at 22/25, which collides with the MST control block's isolation distance
# (see MST_CONTROL_POLES) and pushes the rig past one 1280x720 screen. Do NOT
# "restore" it eastward without re-measuring both — and read the next
# paragraph first, because the short B link is a consequence of this choice.
#
# THE NUMBERS ARE THE TEST. Distances below are FOOTPRINT to FOOTPRINT, per
# PowerNetwork._pole_distance (Task 4). The substation is 2x2 occupying
# x 12..13 with its ANCHOR on the west column, so the two metrics disagree
# in one direction only: westward they are identical (a pole at x=3 is 9
# away by either), while eastward anchor-to-anchor OVER-measures by 1 (a
# pole at x=16 is 4 by anchor, 3 by footprint) and therefore understates the
# substation's real eastward reach.
#
# Two links, and ONLY these two, are min-rule TRIPWIRES — they exist because
# the joining rule is either-reaches, max(range_a, range_b), and vanish under
# a both-reaches min():
#
#   substation <-> cluster A's far pole (3,2): distance 9.
#     max(11, 3) = 11 -> joins.   min(11, 3) = 3 -> 9 > 3, does NOT join.
#   medium pole <-> cluster A's far pole (3,2): distance 5.
#     max(6, 3)  = 6  -> joins.   min(6, 3)  = 3 -> 5 > 3, does NOT join.
#
# The substation's link to cluster B's near pole (16,2) is NOT a tripwire.
# It is only 3 (4 anchor-to-anchor), which is inside basic range, so it forms
# under either rule — a direct consequence of pulling cluster B west for
# screen fit. Do not cite it as evidence for the either-reaches decision.
#
# The exhibit still works, through cluster A. Flip the rule to min and both
# tripwire links vanish at once, severing cluster A from everything: the rig
# goes from 2 components to 3 and visibly splits on screen.
const CLUSTER_A_POLES: Array = [Vector2i(0, 2), Vector2i(3, 2)]
const CLUSTER_B_POLES: Array = [Vector2i(16, 2), Vector2i(19, 2)]

# 2x2, anchored top-left, so it occupies (12,2) (13,2) (12,3) (13,3).
const SUBSTATION_OFFSET: Vector2i = Vector2i(12, 2)

# A medium pole at x=8, 5 from cluster A's far pole (x=3). 5 > 3 and 5 <= 6,
# so it reaches the basic pole but the basic pole cannot reach it: the
# asymmetric case, on screen. It is 8 from cluster B's near pole (x=16), which
# is what makes removing the substation ORPHAN cluster B rather than leaving
# the medium pole to bridge it — 8 > 6.
const MEDIUM_POLE_OFFSET: Vector2i = Vector2i(8, 2)

# --- THE CONTROL BLOCK: MST regression control -----------------------------
# Four basic poles, 3 apart on both axes, so all six pairs are at Chebyshev
# exactly 3 — the K4. Mesh: six wires. MST: three.
#
# ITS SEPARATION FROM THE BUS IS LOAD-BEARING and is why it sits this far
# east. A pole anywhere within 11 of the substation joins the bus under
# either-reaches, and the substation's east footprint column is x = 13, so the
# block has to start at x >= 25 to be out of reach at all. x = 26 gives
# footprint distance 13 against range 11 — a margin of 2, and the tighter of
# the two readings: anchor-to-anchor is 14 (margin 3), because the substation's
# anchor sits on its WEST column and so over-measures eastward by exactly 1.
# Quoting 13 is therefore the safe number, and the block stays isolated
# whichever way Task 4 ends up measuring. It is also 7 from cluster B's far
# pole (x = 19) against basic range 3.
#
# If this block ever merges into the bus, its wire count stops being
# comparable to the pre-MST behaviour and the exhibit is worthless — which is
# exactly what sub-case (3) of test_pole_tier_rig.gd pins.
const MST_CONTROL_POLES: Array = [
	Vector2i(26, 2), Vector2i(29, 2), Vector2i(26, 5), Vector2i(29, 5),
]

# Generators. Two steam generators (2x2, MAX_OUTPUT 20 each), one per cluster,
# each CARDINALLY TOUCHING that cluster's near pole. Generators use
# PowerNetwork._adjacent_component_id, NOT the consumers' wireless supply
# area, so "near a pole" is not enough and a diagonal step off the bus
# contributes nothing while looking perfectly correct on screen.
#
# The arithmetic, from Buildings.edge_cells: a 2x2 at anchor (ax, ay) has its
# N edge at y = ay - 1 across x in {ax, ax+1}. Anchoring at y = 3 therefore
# puts the N edge on row 2, which IS the pole row:
#   gen A (0,3) -> N edge (0,2) (1,2); (0,2) is cluster A's near pole.
#   gen B (16,3) -> N edge (16,2) (17,2); (16,2) is cluster B's near pole.
#
# Placed with dir 0 (Belt.DIR_E, the canonical orientation), which leaves the
# fuel port on the S edge — (0,5) (1,5) and (16,5) (17,5). Those are bare
# stone and a lamp respectively, and Burner._try_pull_fuel_at_cell reacts to
# BELT and CHEST only, so neither generator can ever pull fuel from the world.
# That is what makes the lever authoritative: fuel_buffer changes only because
# the lever wrote it or because the generator burned a unit.
#
# One generator per cluster is also the failure mode worth seeing: in
# BROWNOUT only gen A stays lit, so if the bridge is broken cluster B goes
# dark instead of merely dimming.
const GEN_A_OFFSET: Vector2i = Vector2i(0, 3)
const GEN_B_OFFSET: Vector2i = Vector2i(16, 3)

# The four ELECTRIC_INSERTERs — 5 units each, 20 total. Pure LOAD: constant
# demand means an inserter with nothing to move still draws its full 5, which
# is the session-inserter-electric design decision doing work here.
#
# Faced Belt.DIR_S so the SOURCE tile is the one to the NORTH (dest is south —
# see the load inserters in ElectricRig.plan for the same convention). Every
# source lands on row 0, which is bare paved stone in all four columns, so
# there is provably nothing for them to pick up and they idle forever. Their
# dests are lamps, which have no inventory.
const INSERTER_OFFSETS: Array = [
	Vector2i(-1, 1), Vector2i(4, 1), Vector2i(15, 1), Vector2i(20, 1),
]

# The 20 lamp positions — 1 unit each, 20 total. Each must sit within the
# supply radius of SOME pole on the BUS or it contributes no demand and the 40
# total is missed.
#
# Supply radius is projected from ALL of a pole's footprint cells and measured
# to the NEAREST one — see the plan's _covering_component_id, which walks
# world._pole_cells and takes `max(abs(dx), abs(dy))` to the matched cell. For
# the 1x1 tiers that is the same as anchor distance; for the 2x2 substation
# (cells x 12..13, y 2..3) it is not, and the numbers below use the footprint
# rule because that is the rule that will run.
#
# WHICH LAMPS PIN WHICH RADIUS, which is what makes Task 5 load-bearing rather
# than decorative:
#
#   - all SIX medium-pole lamps are at Chebyshev exactly 2 from (8,2), and all
#     sit at x <= 7, outside the substation's covered span (x 8..17 — TEN
#     columns, anchor-4 .. anchor+1+4, per the 10x10 coverage corrected in
#     commit f476ef7) and 3+ from cluster A's far pole. Nothing but
#     SUPPLY_RADIUS 2 reaches them, so all six drop out if the medium tier
#     regresses to radius 1.
#   - of the four substation lamps, (8,5) is at footprint distance exactly 4
#     and is the ONE that pins SUPPLY_RADIUS 4: at radius 3 it drops out,
#     demand becomes 39 and sub-case (2) reddens. The other three — (16,5),
#     (10,6), (14,6) — are at footprint distance 3. They are still substation-
#     EXCLUSIVE (no basic pole is within 1, the medium pole is not within 2),
#     so they pin "wider than the medium tier", but not the 4 specifically.
#     One lamp is enough to pin the exact value, and moving the others out to
#     4 would disturb a layout whose 24 consumer positions are all verified.
#
# The cluster lamps overlap other areas and that is fine — every pole here is
# on the same component once the bridge forms, so which one covers a lamp
# changes nothing. (15,2), and the inserter at (15,1), fall inside both cluster
# B's basic area and the substation's.
const LAMP_OFFSETS: Array = [
	# Cluster A basic poles (0,2) and (3,2), radius 1: 6 lamps.
	Vector2i(0, 1), Vector2i(-1, 2), Vector2i(1, 2),
	Vector2i(2, 2), Vector2i(3, 1), Vector2i(4, 2),
	# Medium pole (8,2), radius 2: 6 lamps, every one at Chebyshev exactly 2.
	Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2),
	Vector2i(6, 3), Vector2i(6, 4), Vector2i(7, 0),
	# Substation (12,2)-(13,3), radius 4: 4 lamps, none reachable by any other
	# pole. (8,5) is the one at footprint distance exactly 4.
	Vector2i(8, 5), Vector2i(16, 5), Vector2i(10, 6), Vector2i(14, 6),
	# Cluster B basic poles (16,2) and (19,2), radius 1: 4 lamps.
	Vector2i(15, 2), Vector2i(17, 2), Vector2i(18, 2), Vector2i(20, 2),
]

# Power-state lever values, re-exported from ElectricRig so callers need only
# one import. These are the SAME ints, not parallel definitions.
const POWER_FULL: int     = ElectricRig.POWER_FULL
const POWER_BROWNOUT: int = ElectricRig.POWER_BROWNOUT
const POWER_ZERO: int     = ElectricRig.POWER_ZERO

# The expected placement count, the expected demand total and the expected
# supply total deliberately do NOT live here. They are literals in
# test_pole_tier_rig.gd instead, for the reason spelled out on the equivalent
# comment in electric_rig.gd: a constant beside the plan gets edited in the
# same breath as the plan, so the test would ratify the new arithmetic instead
# of failing on it. Changing this layout must mean changing a number in the
# TEST file, on purpose.

## Build the rig. Returns a dictionary with the same shape ElectricRig.build
## returns, so main.gd's spawn/toast handling is identical for both.
##
## Keys: placed, skipped, gen_anchors, substation, adopted.
##
## DELIBERATE DUPLICATION. Phase 2's adopt-or-collide classifier is a near copy
## of ElectricRig.build's, minus the source-chest arm this rig has no use for.
## The obvious move is to extract a shared RigSupport with pave_rect() and
## place_or_adopt() and route both rigs through it — and that is the right
## refactor for a THIRD rig to trigger. It was not done now because
## electric_rig.gd is this session's untouched control: test_electric_rig.gd
## pins exact satisfaction values with == rather than is_equal_approx, and
## restructuring the module underneath it would put the one stable reference
## point in the session at risk for a structural win nothing yet needs.
static func build(world, origin: Vector2i) -> Dictionary:
	# PHASE 1 — pave the whole rectangle BEFORE placing anything.
	# can_place_building validates the FULL footprint, so the 2x2 generators
	# and the 2x2 substation need their overlay on all four cells before their
	# anchor row runs. Interleaving paving with placement makes the rig
	# seed-dependent: it would succeed or fail based on what terrain the world
	# happened to generate underneath. ElectricRig.build has the same split for
	# the same reason.
	#
	# Writing a fresh Tile first clears a WATER base (which can_place_building
	# rejects) and resets resource_node to its default (which is what lets the
	# set_overlay past its deposit/tree guard). The set_overlay that follows
	# records the WHOLE tile into tile_modifications, so the base reset is
	# saved too — that only holds because the Tile written here carries
	# Overlay.NONE, which keeps set_overlay off its idempotent early return.
	#
	# STONE is legal for every type this rig places: POWER_POLE, MEDIUM_POLE,
	# SUBSTATION, ELECTRIC_LAMP and ELECTRIC_INSERTER all accept
	# [NONE, STONE, PATH, SOIL_TILLED], and STEAM_GENERATOR — the strict one —
	# accepts [STONE, PATH]. STONE is the intersection, and it reads as a
	# deliberate pad against the surrounding grass.
	for y in range(PAVE_MIN.y, PAVE_MAX.y + 1):
		for x in range(PAVE_MIN.x, PAVE_MAX.x + 1):
			var cell: Vector2i = origin + Vector2i(x, y)
			# Never repaint under someone else's building. set_overlay would
			# refuse anyway, but the Tile.new above it would already have
			# stripped that building's terrain out from under it.
			if world.has_building_at(cell):
				continue
			world.tiles[cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
			world.set_overlay(cell, Terrain.Overlay.STONE)

	# PHASE 2 — build, or ADOPT a rig that is already standing.
	#
	# Three outcomes, and telling them apart is what keeps the F8 lever alive:
	#
	#   BUILT    — every planned cell was empty and got its building. Normal.
	#   ADOPTED  — every planned cell was ALREADY occupied by a building of
	#              exactly the planned type, anchored exactly where the plan
	#              puts it. That is what a relaunch onto a saved game looks
	#              like, or F7 after Shift+F7 without moving. The right answer
	#              is to RE-ATTACH the lever: hand back the real generator
	#              anchors instead of an empty array, which would otherwise
	#              leave a visibly complete rig that F8 refuses to touch and
	#              that goes dark 16 seconds later when its fuel buffers run
	#              out. Same reasoning, verbatim, as ElectricRig.build's.
	#   COLLIDED — anything in between: the plan overlaps the player's own
	#              base, or a second rig. main.gd reports it as INCOMPLETE.
	#
	# Type AND anchor are both checked. building_at() resolves any footprint
	# cell to its owning anchor, so a 2x2 generator or substation sitting one
	# tile off would otherwise report as "already exactly ours" from the wrong
	# cell. Adoption is all-or-nothing for the same reason it is in ElectricRig:
	# "some of it was already here" is the collision case, and a half-adopted
	# rig has the wrong demand total.
	#
	# There is no source-chest arm here. ElectricRig carries one because seeding
	# a chest it did not place would destroy a player's stored items; this rig
	# places no chests at all, so the only thing adoption has to recover is the
	# generator list.
	var entries: Array = plan()
	var placed: int = 0
	var skipped: int = 0
	var matched: int = 0              # collided with a building identical to the plan's
	var built_gens: Array = []
	var existing_gens: Array = []

	for entry in entries:
		var pos: Vector2i = origin + (entry[0] as Vector2i)
		var t: int = int(entry[1])
		var dir: int = int(entry[2])
		if world.has_building_at(pos):
			skipped += 1
			var sitting: Building = world.building_at(pos)
			if sitting != null and sitting.type == t and sitting.anchor == pos:
				matched += 1
				if t == Buildings.Type.STEAM_GENERATOR:
					existing_gens.append(pos)
			continue
		if not world.place_building(t, pos, dir):
			skipped += 1
			continue
		placed += 1
		if t == Buildings.Type.STEAM_GENERATOR:
			built_gens.append(pos)

	var adopted: bool = placed == 0 and matched == entries.size()
	var gen_anchors: Array = existing_gens if adopted else built_gens

	# PHASE 3 — light the generators. Same contract as ElectricRig: seed
	# fuel_buffer directly and let the generator's own tick flip output_active
	# from there. seed_output is true because update_supply_demand is a
	# PRE-PASS that runs before the generators' own tick, so without it the rig
	# is dark for its first two ticks.
	ElectricRig.apply_power_state(world, gen_anchors, POWER_FULL, true)
	# Belt and braces — every pole already set the flag inside place_building,
	# but topology correctness is the whole rig.
	world.mark_power_network_dirty()

	return {
		"placed": placed,
		"skipped": skipped,
		"gen_anchors": gen_anchors,
		"substation": origin + SUBSTATION_OFFSET,
		"adopted": adopted,
	}

## The full placement list as [rig_relative_offset, building_type, dir]
## triples. Walked by build() and asserted against by test_pole_tier_rig.gd, so
## the test and the game can never disagree about what the rig contains.
##
## PUBLIC and named `plan()`, with the offset first, to match
## ElectricRig.plan() exactly. Both facts were wrong in the first draft — an
## underscore-private name called from another file, and the tuple inverted to
## [type, offset, dir] — which is the kind of near-miss that makes a reader
## moving between the two rig modules misread one of them.
##
## dir is 0 (Belt.DIR_E, canonical) for everything that does not care, and is
## explicit rather than defaulted for the two types that DO: STEAM_GENERATOR,
## whose fuel port rotates, and ELECTRIC_INSERTER, whose source and dest tiles
## rotate together.
static func plan() -> Array:
	var out: Array = []
	for p in CLUSTER_A_POLES:
		out.append([p, Buildings.Type.POWER_POLE, 0])
	for p in CLUSTER_B_POLES:
		out.append([p, Buildings.Type.POWER_POLE, 0])
	for p in MST_CONTROL_POLES:
		out.append([p, Buildings.Type.POWER_POLE, 0])
	out.append([MEDIUM_POLE_OFFSET, Buildings.Type.MEDIUM_POLE, 0])
	out.append([SUBSTATION_OFFSET, Buildings.Type.SUBSTATION, 0])
	# Generators before consumers so gen_anchors comes out in A, B order —
	# the lever fuels the FIRST N anchors, so index 0 is the generator that
	# stays lit in BROWNOUT.
	out.append([GEN_A_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E])
	out.append([GEN_B_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E])
	for p in INSERTER_OFFSETS:
		out.append([p, Buildings.Type.ELECTRIC_INSERTER, Belt.DIR_S])
	for p in LAMP_OFFSETS:
		out.append([p, Buildings.Type.ELECTRIC_LAMP, 0])
	return out

