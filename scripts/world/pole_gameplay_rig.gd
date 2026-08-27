class_name PoleGameplayRig
extends RefCounted

## POLE TIER GAMEPLAY RIG (session-electricity-pole-tiers, PAUSE 2).
##
## FOUR SCENARIOS IN ONE 1280x720 SCREEN, so the gate is a looking-and-pressing
## exercise rather than a building exercise. The rig spawns below-left of the
## player; the bridge substation is added and removed with a single key while
## the human watches two networks merge and split.
##
##   (1) THE TOGGLE          two basic-pole clusters, 9 apart, each with its own
##                           steam generator and its own 20 units of demand, and
##                           a SUBSTATION between them that a key adds and
##                           removes. Absent: two networks. Present: one.
##   (2) OVERLAPPING COVER   one lamp inside a basic pole's radius-1 AND the
##                           bridge substation's radius-4. What it shows is that
##                           it stays powered across the toggle. It does NOT
##                           show the nearest-pole tie-break — see OVERLAP_LAMP.
##   (3) THE RULE, AS ONE WIRE   a basic pole exactly 5 from a medium pole.
##                           5 > 3 and 5 <= 6, so either-reaches joins them and
##                           a both-reaches min() would not.
##   (4) THE DENSITY JUDGEMENT   16 poles across all three tiers, packed. Not an
##                           assertion about wire count — a picture the human
##                           looks at and decides whether Gabriel reads noisy.
##
## Everything below is RIG-RELATIVE. The rig origin is the player tile plus
## ORIGIN_OFFSET, so rig (0, 0) is the top-left corner of the dense block.
##
## THE THREE BLOCKS MUST NOT MERGE INTO EACH OTHER, and that is the hard part of
## this layout, not the arithmetic inside each block. A SUBSTATION joins any
## pole within Chebyshev 11 under the either-reaches rule, which is a 23x23 box
## — wider than this screen is tall. So blocks 1 and 4 (each holding at least
## one substation) are separated ALONG X, and block 3 is separated ALONG Y from
## both. The measured margins, in tiles beyond the reach that would join them:
##
##   block 4 <-> block 1   3   basic (9,0) to the bridge footprint: 14 vs 11
##   block 4 <-> block 3   4   substation (0,0) to (16,14):         15 vs 11
##   block 1 <-> block 3   2   the bridge footprint to (16,14):     13 vs 11
##
## The last one is the tightest thing in the rig: block 3 cannot move north by
## more than two rows, and the bridge substation cannot move south at all,
## without the two merging and scenario 3 ceasing to be a separate exhibit.
##
## Demand is pinned at exactly 40, matching ElectricRig and PoleTierRig, so the
## F8 lever's three positions land on the same three satisfaction values and the
## brownout midpoint is a true 0.50. Composition:
##    4 x ELECTRIC_INSERTER @ Inserter.POWER_DEMAND_BY_TYPE = 5  -> 20
##   20 x ELECTRIC_LAMP     @ ElectricLamp.DEMAND           = 1  -> 20
## ALL of it sits in block 1, split 20 / 20 between the two clusters. Blocks 3
## and 4 carry no consumers and no generators at all: they are topology and
## wire-rendering exhibits, and a lamp in either would move demand off 40 and
## split it across components the lever cannot reason about.
##
## WHAT THE SPLIT BUYS, and why it is worth the extra care: the lever fuels
## gen_anchors[0] first (ElectricRig.FUELLED_BY_STATE is [2, 1, 0]), and gen A
## is cluster A's. So at BROWNOUT with the bridge PRESENT the whole bus dims to
## 0.50, while at BROWNOUT with the bridge ABSENT cluster A stays at 1.00 and
## cluster B goes fully dark. One key press changes which of those two the human
## is looking at.
##
## Deliberately ABSENT, and must stay absent, for the reasons PoleTierRig states
## at length: ACCUMULATOR (smears the crisp states into ramps), WINDMILL (its
## supply arm defaults output_active to TRUE, so one touching a pole silently
## adds 6 units), and CHEST / BELT (Burner._try_pull_fuel_at_cell reacts to
## exactly those two types, so their absence is what makes the F8 lever the only
## thing that can change a generator's fuel).
##
## This module owns the LAYOUT and the BRIDGE. main.gd owns the key bindings and
## the toasts. The power LEVER is reused verbatim from ElectricRig — three rigs
## now share one implementation of "how many generators have fuel".

# Rig origin relative to the player tile at spawn time.
#
# MEASURED, not derived, exactly as ElectricRig.ORIGIN_OFFSET and
# PoleTierRig.ORIGIN_OFFSET were. The arithmetic that makes the measurement
# checkable: TILE_SIZE is 32, the camera in scenes/main.tscn is authored at zoom
# 1.5, and the 1920x1080 viewport is presented in a 1280x720 window (2/3), so
# 32 * 1.5 * 2/3 = 32 screen pixels per tile at capture resolution. The camera
# centres on the player, so the player's own tile spans screen y 344..376 and
# x 624..656, and the tile at player-relative (M, N) has its top-left corner at
# screen (624 + 32M, 344 + 32N).
#
# Four HUD edges bound the usable area, all read off a 1280x720 capture rather
# than computed:
#
#   hotbar strip     top edge y = 628. Paved row 15 (player row 7) spans
#                    568..600 and clears it by 28 px.
#   status + toast   two text lines at roughly y 8..24 and y 32..48. Paved row
#                    -1 (player row -9) spans 56..88 and clears them by 8 px.
#   minimap panel    x >= 1120, y <= 155.
#   inventory panel  x >= 1140, y 160..218.
#
# The last two are why block 1 stops where it does: its east-most BUILDING
# column is player column 14, whose right edge is 1104, clearing the minimap's
# 1120 by 16 px. PAVE_RECTS[1] therefore has no east margin — a margin column
# there would be the one thing on screen half-hidden behind the panel.
#
# x = -18 puts the dense block's west edge at player column -19 (screen x 16)
# and y = -8 puts the top paved row at player row -9. The whole rig is above and
# beside the player except block 3, and no paved rectangle contains the player's
# own tile at rig (18, 8), so a placement can never collide with the player.
const ORIGIN_OFFSET: Vector2i = Vector2i(-18, -8)

# Phase 1 paving, as [min, max] INCLUSIVE rectangles in rig-relative
# coordinates. THREE rectangles rather than one: the four scenarios are meant to
# read as four separate exhibits, and a single slab spanning rig x -1..32 would
# draw them as one installation. The gaps are also the isolation distances doing
# their job visibly.
#
# Each rectangle strictly contains its block's buildings with a one-tile margin,
# except PAVE_RECTS[1]'s east edge — see ORIGIN_OFFSET on why that margin is
# omitted. Contents, for the reader checking the margins:
#   [0] dense block   buildings x 0..9,   y 0..6
#   [1] blocks 1 + 2  buildings x 15..32, y 0..3
#   [2] block 3       buildings x 16, 21, y 14
const PAVE_RECTS: Array = [
	[Vector2i(-1, -1), Vector2i(10, 7)],
	[Vector2i(14, -1), Vector2i(32, 4)],
	[Vector2i(15, 13), Vector2i(22, 15)],
]

# --- SCENARIO 1: THE TOGGLE ------------------------------------------------
# Two basic-pole clusters on row y = 1, each a pair at Chebyshev exactly 3 —
# the basic tier's whole range, so each pair joins and neither pair can reach
# the other.
#
# THE GAP IS 9, NOT 8. The brief asked for "~8 apart", and 8 works for the
# merge/split demo, but it cannot give the bridge four tiles of clearance on
# BOTH sides: with a 2x2 substation in an 8-tile gap the two link distances sum
# to 7, so one of them is always <= 3 and forms under a both-reaches min() rule
# as well. At 9 they sum to 8 and both come out at 4, which is > the basic
# tier's 3 — so BOTH links are either-reaches evidence rather than one of them
# being a link that would exist under any rule. PoleTierRig had to disclaim
# exactly this about its own east link; one extra column buys it here.
#
# The numbers, FOOTPRINT to FOOTPRINT per PowerNetwork._pole_distance. The
# bridge is 2x2 anchored on its west column, so it occupies x 23..24:
#
#   A1 (16,1) <-> A2 (19,1)      3   max(3, 3)  = 3  -> joins
#   A2 (19,1) <-> bridge x23     4   max(3, 11) = 11 -> joins  | min(3,11)=3
#   bridge x24 <-> B1 (28,1)     4   max(11, 3) = 11 -> joins  | min = 3
#   B1 (28,1) <-> B2 (31,1)      3   max(3, 3)  = 3  -> joins
#   A2 (19,1) <-> B1 (28,1)      9   max(3, 3)  = 3  -> NEVER joins
#
# The two middle rows are min-rule TRIPWIRES: 4 > 3, so both vanish under a
# both-reaches rule and the bridge stops bridging anything. The last row is what
# makes the clusters genuinely separate with the bridge gone — no basic pole
# reaches 9, and there is no medium pole anywhere near this block.
const CLUSTER_A_POLES: Array = [Vector2i(16, 1), Vector2i(19, 1)]
const CLUSTER_B_POLES: Array = [Vector2i(28, 1), Vector2i(31, 1)]

# The toggleable bridge. 2x2 anchored top-left, so it occupies (23,0) (24,0)
# (23,1) (24,1) — one row above the pole row and one row on it.
#
# NOT IN plan(). Every other building in this rig is, and the difference is
# deliberate: build()'s adopt-or-collide classifier is all-or-nothing, so a plan
# entry standing on a cell the user has just toggled EMPTY would come back as
# "placed 1, skipped 47, adopted false", which hands main.gd an empty
# gen_anchors and silently kills the F8 lever. The bridge is owned by
# set_bridge() instead, which build() calls once with present = true — so a
# re-spawn restores the rig to its spawn state (bridged) whatever the toggle was
# left at, and the placement count never depends on it.
const BRIDGE_OFFSET: Vector2i = Vector2i(23, 0)

# --- SCENARIO 2: OVERLAPPING COVERAGE --------------------------------------
# One lamp covered by two poles of different tiers at once:
#
#   to A2 (19,1), a basic pole:      Chebyshev 1, and its supply radius is 1.
#   to the bridge footprint (x 23):  Chebyshev 3, and its supply radius is 4.
#
# BE HONEST ABOUT WHAT THIS DOES NOT SHOW. It does not put the nearest-pole
# tie-break on display, because that tie-break is currently UNOBSERVABLE: any
# two poles covering the same cell are already in the SAME component. The proof
# is in _covering_component_id's docstring — Chebyshev's triangle inequality
# bounds their separation by rA + rB, and every tier pair clears its own
# max(range) with room to spare (basic+sub is 1+4 = 5 against 11). So whichever
# pole wins here, the answer is the same integer.
#
# What the human CAN see is that this lamp stays lit across the toggle. With the
# bridge present it is covered by both; with the bridge gone the basic pole
# still covers it and it stays on the cluster-A network. That is a real property
# and it is what sub-case (2) of the test asserts.
#
# It is also an ordinary member of LAMPS_CLUSTER_A and contributes its 1 unit
# there — this constant only NAMES it so the test does not have to hard-code an
# index into that list.
const OVERLAP_LAMP: Vector2i = Vector2i(20, 1)

# --- SCENARIO 3: THE EITHER-REACHES RULE, AS ONE WIRE ----------------------
# A basic pole and a medium pole at Chebyshev exactly 5, alone on their own
# paved pad at the bottom of the screen.
#
#   5 >  3   the basic pole cannot reach the medium one.
#   5 <= 6   the medium pole CAN reach the basic one.
#
# So max(3, 6) = 6 joins them and min(3, 6) = 3 does not. One wire on screen,
# and it is the entire rule.
#
# ITS ROW IS LOAD-BEARING. y = 14 is 13 rows below the bridge substation's
# footprint (which ends at y = 1), against the substation's reach of 11 — a
# margin of two rows, the tightest separation in the rig. Vertical is the ONLY
# separation available to this pair: a substation's 23-column halo is wider than
# the screen, so no horizontal position on a 1280x720 screen puts these two
# poles out of the bridge's reach. Moving this block north merges it into
# block 1 and scenario 3 stops existing.
const SCENARIO3_BASIC: Vector2i  = Vector2i(16, 14)
const SCENARIO3_MEDIUM: Vector2i = Vector2i(21, 14)

# --- SCENARIO 4: THE DENSITY JUDGEMENT -------------------------------------
# 16 poles across all three tiers on a 10x7 pad: 2 SUBSTATION, 4 MEDIUM_POLE,
# 10 POWER_POLE, on a lattice 3 apart in x and 2 apart in y. Every basic pair on
# that lattice is at Chebyshev 3 (horizontal 3, vertical 2, diagonal
# max(3,2) = 3), which is exactly the basic tier's range, so the REACHABILITY
# graph here is dense — and the substations, whose 11 reaches every cell of the
# pad, make it denser still by joining all 16 into one component directly.
#
# That is the point. This is not an assertion about wire count; it is the
# picture the human judges. Gabriel's answer on this block is 26 wires for 16
# poles — 1.62 per pole, against the ~1.8 per pole the POLE_RANGE_BY_TYPE
# docstring reports for a 100-pole grid, MST's n-1 = 15, and a mesh's O(n^2).
# If 26 wires over this block reads as a hairball, the renderer decision is
# wrong at scale and that is what PAUSE 2 is for. The test asserts the block is
# ONE component of 16 poles and leaves the count to the eye.
#
# TIER PLACEMENT IS CONSTRAINED BY BLOCK 1, not by taste. Reading east to west,
# the separation each tier needs from block 1's west-most pole A1 (16,1) and
# from the bridge footprint (x 23..24):
#
#   SUBSTATION  reach 11 vs A1      -> anchor x <= 3.  Both are at x = 0.
#   MEDIUM      reach 6  vs A1      -> x <= 9.         All four are at x <= 6.
#   BASIC       reach 11 vs bridge  -> x <= 11.        All are at x <= 9.
#
# Worked, so the bounds are checkable: a substation anchored at x occupies
# x .. x+1, so its distance to A1 is 16 - (x + 1), which must exceed 11 -> x < 4.
# A medium pole at x is 16 - x from A1, which must exceed 6 -> x < 10. A basic
# pole is 3 from A1's tier but 11 from the bridge, whose footprint starts at
# x = 23, so 23 - x must exceed 11 -> x < 12, and that is the binding one.
#
# The medium poles sit at x <= 6 rather than the permitted 9 on purpose: at
# x = 9 the margin against A1 would be exactly 1 tile (7 vs reach 6), and every
# other separation in this rig has at least 2. Do not "fill the gap" by moving a
# medium pole east.
#
# Both substations are anchored at x = 0 because only the pad's west end clears
# block 1 at all (x <= 3 of the ten columns available) — and they are stacked
# vertically (y 0 and y 5) rather than side by side, which would read as one 4x2
# slab rather than two installations.
const DENSE_SUBSTATIONS: Array = [Vector2i(0, 0), Vector2i(0, 5)]
const DENSE_MEDIUM_POLES: Array = [
	Vector2i(3, 0), Vector2i(6, 0),
	Vector2i(3, 4), Vector2i(6, 4),
]
const DENSE_BASIC_POLES: Array = [
	Vector2i(9, 0),
	Vector2i(0, 2), Vector2i(3, 2), Vector2i(6, 2), Vector2i(9, 2),
	Vector2i(0, 4), Vector2i(9, 4),
	Vector2i(3, 6), Vector2i(6, 6), Vector2i(9, 6),
]

# --- GENERATORS ------------------------------------------------------------
# Two STEAM_GENERATORs (2x2, MAX_OUTPUT 20 each), one per cluster, each
# CARDINALLY TOUCHING that cluster's west pole. Generators feed the network
# through PowerNetwork._adjacent_component_id — the consumers' wireless supply
# area does NOT apply to them — so "inside the cluster" is not enough and a
# generator one row off contributes nothing while looking perfectly correct on
# screen. PoleTierRig's first draft shipped exactly that fault and every
# placement still succeeded with demand still at 40.
#
# The arithmetic, from Buildings.edge_cells: a 2x2 at anchor (ax, ay) has its N
# edge at y = ay - 1 across x in {ax, ax+1}. Anchoring at y = 2 puts that edge on
# row 1, which IS the pole row:
#   gen A (16,2) -> N edge (16,1) (17,1); (16,1) is cluster A's west pole.
#   gen B (28,2) -> N edge (28,1) (29,1); (28,1) is cluster B's west pole.
#
# EXACTLY TWO, and that is a hard constraint rather than a layout choice:
# ElectricRig.FUELLED_BY_STATE is [2, 1, 0] and fuels the FIRST N anchors, so a
# third generator would be dark in every lever position while looking identical
# to the other two.
#
# Placed with dir 0 (Belt.DIR_E, canonical), which leaves the fuel port on the S
# edge — SteamGenerator.FUEL_PORT_DIR is Belt.DIR_S and Buildings.world_dir
# rotates it by the building's dir, which is 0. Those cells are (16,4) (17,4)
# and (28,4) (29,4), all bare paved stone inside PAVE_RECTS[1], and this rig
# contains no CHEST and no BELT anywhere, which are the only two types
# Burner._try_pull_fuel_at_cell reacts to. So no generator can ever pull fuel
# from the world and the lever is the only thing that moves fuel_buffer.
const GEN_A_OFFSET: Vector2i = Vector2i(16, 2)
const GEN_B_OFFSET: Vector2i = Vector2i(28, 2)

# --- CONSUMERS -------------------------------------------------------------
# 20 units of demand per cluster: 2 x ELECTRIC_INSERTER (5 each) + 10 x
# ELECTRIC_LAMP (1 each). The 20/20 split is what makes the bridge-absent state
# read cleanly — each cluster then has exactly its own generator's 20 units
# against exactly 20 of demand, so both sit at satisfaction 1.00 until the lever
# darkens one of them.
#
# EVERY CONSUMER IS COVERED BY A BASIC POLE, never by the bridge alone. That is
# a requirement, not an accident: a consumer only the substation could reach
# would leave the network when the bridge is removed, so total demand would drop
# below 40 and the lever's 0.50 midpoint would move every time the human pressed
# the toggle. The cluster poles' radius-1 areas are the 3x3 boxes around
# (16,1) (19,1) (28,1) (31,1), which is columns 15..20 and 27..32 across rows
# 0..2, and every offset below is inside one of them.
#
# The inserters face Belt.DIR_S, so per Inserter.REACH_BY_TYPE (1) their SOURCE
# is the cell to the NORTH and their dest is the cell to the south. All four
# sources land on row -1, the paved margin, which is empty stone; their dests
# are lamps, which have no inventory. Nothing in this rig can ever be picked up,
# so they idle at full 5-unit draw forever — the constant-demand decision from
# session-inserter-electric doing the work.
const INSERTER_OFFSETS: Array = [
	Vector2i(15, 0), Vector2i(18, 0),   # cluster A
	Vector2i(27, 0), Vector2i(30, 0),   # cluster B
]

# The 10 cluster-A lamps. (20,1) is OVERLAP_LAMP, scenario 2's exhibit; it is
# listed here like any other because it draws its 1 unit like any other.
const LAMPS_CLUSTER_A: Array = [
	Vector2i(16, 0), Vector2i(17, 0), Vector2i(19, 0), Vector2i(20, 0),
	Vector2i(15, 1), Vector2i(17, 1), Vector2i(18, 1), Vector2i(20, 1),
	Vector2i(18, 2), Vector2i(20, 2),
]

# The 10 cluster-B lamps, the mirror of cluster A's about the bridge.
const LAMPS_CLUSTER_B: Array = [
	Vector2i(28, 0), Vector2i(29, 0), Vector2i(31, 0), Vector2i(32, 0),
	Vector2i(27, 1), Vector2i(29, 1), Vector2i(30, 1), Vector2i(32, 1),
	Vector2i(30, 2), Vector2i(32, 2),
]

# Power-state lever values, re-exported from ElectricRig so callers need only
# one import. These are the SAME ints, not parallel definitions.
const POWER_FULL: int     = ElectricRig.POWER_FULL
const POWER_BROWNOUT: int = ElectricRig.POWER_BROWNOUT
const POWER_ZERO: int     = ElectricRig.POWER_ZERO

# The expected placement count, demand total, supply total and component counts
# deliberately do NOT live here. They are literals in test_pole_gameplay_rig.gd,
# for the reason spelled out on the equivalent comments in electric_rig.gd and
# pole_tier_rig.gd: a constant beside the plan gets edited in the same breath as
# the plan, so the test would ratify the new arithmetic instead of failing on
# it. Changing this layout must mean changing a number in the TEST file, on
# purpose.

## Build the rig. Returns a dictionary shaped like ElectricRig.build's and
## PoleTierRig.build's, so main.gd's spawn/toast handling reads the same for
## all three.
##
## Keys: placed, skipped, gen_anchors, adopted, bridge_anchor, bridge_present.
##
## Phase 1's pave loop and phase 2's adopt-or-collide classifier — carried here
## as DELIBERATE DUPLICATION, third occurrence, when this rig shipped — now
## live on RigSupport, extracted at the top of Electricity Session 4 once the
## fourth rig was queued. This rig was the trigger PoleTierRig's header asked
## for; the cut waited only for a session in which electric_rig.gd was not the
## untouched control.
static func build(world, origin: Vector2i) -> Dictionary:
	# PHASE 1 — pave every rectangle BEFORE placing anything.
	# can_place_building validates the FULL footprint, so the 2x2 generators and
	# the 2x2 substations need their overlay on all four cells before their
	# anchor row runs. Interleaving paving with placement makes the rig
	# seed-dependent: it would succeed or fail based on the terrain the world
	# happened to generate underneath. RigSupport.pave_rect carries the
	# fresh-Tile reasoning; THREE rectangles rather than one is this rig's own
	# shape (see PAVE_RECTS), so it calls the helper once per rectangle.
	#
	# The rig-specific fact: STONE is legal for every type this rig places —
	# POWER_POLE, MEDIUM_POLE, SUBSTATION, ELECTRIC_LAMP and ELECTRIC_INSERTER
	# all accept [NONE, STONE, PATH, SOIL_TILLED], and STEAM_GENERATOR — the
	# strict one — accepts [STONE, PATH]. STONE is the intersection, and it
	# reads as a deliberate pad against the surrounding grass.
	for rect in PAVE_RECTS:
		RigSupport.pave_rect(world, origin, rect[0], rect[1])

	# PHASE 2 — build, or ADOPT a rig that is already standing. The BUILT /
	# ADOPTED / COLLIDED classification (type AND anchor checked,
	# all-or-nothing adoption) lives on RigSupport.place_or_adopt; what
	# ADOPTED buys here is the F8 lever re-attaching to a rig relaunched from
	# a save, or the spawn key after Shift+spawn without moving.
	#
	# The BRIDGE is not in the plan — see BRIDGE_OFFSET for why it must not
	# be: the classifier is all-or-nothing, and a plan entry standing on a
	# cell the user has just toggled EMPTY would break adoption and silently
	# kill the F8 lever.
	var report: Dictionary = RigSupport.place_or_adopt(world, origin, plan())
	var gen_anchors: Array = RigSupport.owned_anchors(report, Buildings.Type.STEAM_GENERATOR)

	# PHASE 3 — the bridge, always ON at spawn. Idempotent, so adopting a rig
	# that is already bridged builds nothing, and adopting one the user had
	# toggled OFF restores it. Either way the placement count above is untouched.
	var bridge: Dictionary = set_bridge(world, origin, true)

	# PHASE 4 — light the generators. Same contract as the other two rigs: seed
	# fuel_buffer directly and let the generator's own tick flip output_active
	# from there. seed_output is true because update_supply_demand is a PRE-PASS
	# that runs before the generators' own tick, so without it the rig is dark
	# for its first two ticks.
	ElectricRig.apply_power_state(world, gen_anchors, POWER_FULL, true)
	# Belt and braces — every pole already set the flag inside place_building,
	# but topology correctness is the whole rig.
	world.mark_power_network_dirty()

	return {
		"placed": int(report["placed"]),
		"skipped": int(report["skipped"]),
		"gen_anchors": gen_anchors,
		"adopted": bool(report["adopted"]),
		"bridge_anchor": origin + BRIDGE_OFFSET,
		"bridge_present": bool(bridge.get("present", false)),
	}

## The full placement list as [rig_relative_offset, building_type, dir] triples.
## Walked by build() and asserted against by test_pole_gameplay_rig.gd, so the
## test and the game can never disagree about what the rig contains.
##
## PUBLIC and named `plan()`, with the offset first, to match ElectricRig.plan()
## and PoleTierRig.plan() exactly.
##
## The BRIDGE SUBSTATION IS NOT HERE. It is the one building in this rig whose
## presence is a user-facing variable rather than part of the layout — see
## BRIDGE_OFFSET.
##
## dir is 0 (Belt.DIR_E, canonical) for everything that does not care, and is
## explicit rather than defaulted for the two types that DO: STEAM_GENERATOR,
## whose fuel port rotates, and ELECTRIC_INSERTER, whose source and dest tiles
## rotate together.
static func plan() -> Array:
	var out: Array = []
	for p in DENSE_SUBSTATIONS:
		out.append([p, Buildings.Type.SUBSTATION, 0])
	for p in DENSE_MEDIUM_POLES:
		out.append([p, Buildings.Type.MEDIUM_POLE, 0])
	for p in DENSE_BASIC_POLES:
		out.append([p, Buildings.Type.POWER_POLE, 0])
	for p in CLUSTER_A_POLES:
		out.append([p, Buildings.Type.POWER_POLE, 0])
	for p in CLUSTER_B_POLES:
		out.append([p, Buildings.Type.POWER_POLE, 0])
	out.append([SCENARIO3_BASIC, Buildings.Type.POWER_POLE, 0])
	out.append([SCENARIO3_MEDIUM, Buildings.Type.MEDIUM_POLE, 0])
	# Generators before consumers so gen_anchors comes out in A, B order — the
	# lever fuels the FIRST N anchors, so index 0 is the generator that stays lit
	# in BROWNOUT, and it must be cluster A's.
	out.append([GEN_A_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E])
	out.append([GEN_B_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E])
	for p in INSERTER_OFFSETS:
		out.append([p, Buildings.Type.ELECTRIC_INSERTER, Belt.DIR_S])
	for p in LAMPS_CLUSTER_A:
		out.append([p, Buildings.Type.ELECTRIC_LAMP, 0])
	for p in LAMPS_CLUSTER_B:
		out.append([p, Buildings.Type.ELECTRIC_LAMP, 0])
	return out

## Is OUR bridge substation — a SUBSTATION anchored exactly at `anchor` —
## standing there right now?
##
## Anchor equality, not merely "a substation overlaps this cell": building_at
## resolves any footprint cell to its owner, so a substation sitting one tile off
## would otherwise read as ours and the toggle would start removing the player's
## building instead of its own.
static func bridge_is_present(world, anchor: Vector2i) -> bool:
	var b: Building = world.building_at(anchor)
	return b != null and b.type == Buildings.Type.SUBSTATION and b.anchor == anchor

## Drive the bridge substation to `present`. THE single mutation path for it —
## build() and the toggle key both come through here, so there is one definition
## of what "the bridge is on" means.
##
## IDEMPOTENT IN BOTH DIRECTIONS, which is the whole contract: asking for a state
## the world is already in builds nothing, removes nothing, and reports
## changed = false. Ten presses of the toggle therefore alternate cleanly instead
## of stacking substations or leaving a hole.
##
## IT NEVER TOUCHES A FOREIGN BUILDING. If something else is standing on any of
## the four cells, place_building fails its own footprint check and this reports
## blocked = true; and the removal arm runs only when bridge_is_present already
## said the substation there is ours. Removing a player's building because it
## happened to sit on the bridge cell would be a data-loss bug, and the toggle is
## a key the user can hold down.
##
## `present` in the returned dict is RE-READ from the world rather than echoed
## from the request, so a blocked call cannot report a substation that is not
## there.
##
## Returns: anchor, present, changed, blocked, components.
static func set_bridge(world, origin: Vector2i, present: bool) -> Dictionary:
	var anchor: Vector2i = origin + BRIDGE_OFFSET
	var ours: bool = bridge_is_present(world, anchor)
	var changed: bool = false
	var blocked: bool = false
	if present and not ours:
		# place_building validates the WHOLE 2x2 footprint, so a foreign
		# building on any of the four cells fails here rather than producing a
		# half-substation.
		if world.place_building(Buildings.Type.SUBSTATION, anchor, 0):
			changed = true
		else:
			blocked = true
	elif not present and ours:
		# remove_building_at takes any footprint cell, clears all four, and sets
		# the power dirty flag itself.
		if world.remove_building_at(anchor):
			changed = true
		else:
			blocked = true
	# Belt and braces, exactly as build()'s tail: place_building and
	# remove_building_at both set the flag, but every number the caller is about
	# to put in a toast is read back through the topology.
	world.mark_power_network_dirty()
	return {
		"anchor": anchor,
		"present": bridge_is_present(world, anchor),
		"changed": changed,
		"blocked": blocked,
		"components": component_count(world),
	}

## Flip the bridge. Same returned dict as set_bridge, which is what main.gd puts
## in its toast.
static func toggle_bridge(world, origin: Vector2i) -> Dictionary:
	return set_bridge(world, origin, not bridge_is_present(world, origin + BRIDGE_OFFSET))

## How many distinct pole components exist ON THE WHOLE MAP.
##
## Not rig-scoped, and the toast that prints it says "on the map" for that
## reason: the rig cannot tell its own poles from ones the player built, and a
## number that quietly excluded the player's own network would be the more
## confusing of the two lies. On a rig-only world — which is what the test builds
## and what the scenario flag boots — the two readings are the same.
##
## Rebuilds the topology first. Every caller reaches this immediately after a
## mutation, so reading a stale _pole_component here would report the count from
## before the press that asked for it.
static func component_count(world) -> int:
	PowerNetwork.rebuild_topology(world)
	var seen: Dictionary = {}
	for anchor in world._pole_component:
		seen[int(world._pole_component[anchor])] = true
	return seen.size()
