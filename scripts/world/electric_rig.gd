class_name ElectricRig
extends RefCounted

## ELECTRIC INSERTER SMOKE-TEST RIG (session-inserter-electric, PAUSE 1).
##
## A pre-built, self-contained power scenario whose only control is "how many
## steam generators have fuel". It exists so the electric tier's brownout path
## can be EYEBALLED without hand-placing 34 buildings first.
##
## The whole point is that demand is pinned at EXACTLY 40 and supply arrives in
## 20-unit blocks, so the three lever positions land on three exact
## satisfaction values:
##
##   generators fuelled | raw supply | satisfaction | hero inserter cycle
##   -------------------|------------|--------------|---------------------
##   2                  | 40         | 1.00         |   5 ticks (0.25 s)
##   1                  | 20         | 0.50         |  10 ticks (0.50 s)
##   0                  |  0         | 0.00         |  STATE_NO_POWER
##
## 20.0 / 40 is exactly representable in binary floating point, so the middle
## row is a true 0.50 and ceil(5 / 0.5) is exactly 10, never 11.
##
## Demand composition (must sum to 40 or the 0.50 midpoint is missed):
##    4 x ELECTRIC_INSERTER @ Inserter.POWER_DEMAND_BY_TYPE = 5  -> 20
##   20 x ELECTRIC_LAMP     @ ElectricLamp.DEMAND           = 1  -> 20
## Lamps are over-represented relative to their tile cost on purpose: PAUSE 2
## has to confirm lamps on the same network do NOT flicker, and lamp
## brightness modulates with satisfaction, which is what makes a brownout
## legible at a glance.
##
## Deliberately ABSENT from this rig, and they must stay absent:
##   - ACCUMULATOR — PowerNetwork Stage 2 charges it on excess and discharges
##     it into deficit, which smears the three crisp states into ramps. Those
##     crisp states are the entire signal the smoke test is looking for.
##   - WINDMILL — its supply arm reads state.get("output_active", TRUE)
##     (PowerNetwork Stage 1, power_network.gd:180), so one placed CARDINALLY
##     TOUCHING any pole on the bus — the GENERATOR rule, _adjacent_component_id,
##     not the consumers' Chebyshev supply area — silently adds 6 units and
##     moves the midpoint off 0.50. A windmill merely NEAR the bus contributes
##     nothing; POLE_RANGE governs pole-to-pole joining only.
##
## This module owns the LAYOUT and the LEVER. main.gd owns the key bindings,
## the dedup flag and the toast. The headless test drives these same two entry
## points, so what the test proves and what the user looks at cannot drift.

# Rig origin, relative to the player tile at spawn time. Puts the rig BELOW
# the player (+y is screen-down) and west by half its width, so the 20-wide
# paved footprint (PAVE_MIN.x -2 .. PAVE_MAX.x 17) straddles the player's
# column and the camera, which centres on the player, frames it horizontally.
#
# The y offset was MEASURED, not derived. At the earlier value of 3 the rig's
# last row landed at screen y~600-627 in a 1280x720 capture, with the hotbar
# strip starting around y~635 — under 10px of clearance, and the fill bars on
# the bottom-row chests read as cut off. Pulling it to 1 lifts the whole rig
# two tiles clear. Do not "tidy" this back toward the player without
# re-capturing: the arithmetic in the previous version of this comment was
# wrong about the tile pitch, which is how it drifted into the hotbar.
#
# y starts at ORIGIN_OFFSET.y + PAVE_MIN.y = 2, so the paved area never
# reaches the player's own tile at y=0. That matters: dropping a
# non-walkable building on the player is guarded against elsewhere, and a rig
# that trips that guard would spawn INCOMPLETE.
const ORIGIN_OFFSET: Vector2i = Vector2i(-8, 1)

# Phase 1 paving rectangle, INCLUSIVE, in rig-relative coordinates. Strictly
# contains every building cell (x -1..16, y 2..5) with a one-tile margin.
const PAVE_MIN: Vector2i = Vector2i(-2, 1)
const PAVE_MAX: Vector2i = Vector2i(17, 6)

# Landmarks the lever and the tests need by name. Rig-relative.
const GEN_A_OFFSET: Vector2i        = Vector2i(0, 2)
const GEN_B_OFFSET: Vector2i        = Vector2i(3, 2)
const SOURCE_CHEST_OFFSET: Vector2i = Vector2i(7, 5)
const HERO_OFFSET: Vector2i         = Vector2i(8, 5)
const DEST_CHEST_OFFSET: Vector2i   = Vector2i(9, 5)

# What the hero inserter ferries. IRON_ORE specifically because it is NOT in
# Burner.FUEL_VALUES — a layout mistake that put the source chest against a
# generator's fuel port could not then silently feed the payload into the
# boiler and desync the lever from the fuel it believes it controls.
const SOURCE_ITEM: int = Items.Type.IRON_ORE

# Chest.TOTAL_CAPACITY, so the chest's fill bar reads honestly (a chest seeded
# past its own capacity would draw a full-but-lying bar). At full power the
# hero moves roughly 2.9 items/s, so this is about 14 minutes of work.
const SOURCE_COUNT: int = Chest.TOTAL_CAPACITY

# Lever positions.
const POWER_FULL: int     = 0
const POWER_BROWNOUT: int = 1
const POWER_ZERO: int     = 2
const POWER_STATE_COUNT: int = 3

# How many generators carry fuel in each lever position, indexed by the
# constants above. The single source of truth for the lever.
const FUELLED_BY_STATE: Array = [2, 1, 0]

# The expected placement count and the expected demand total deliberately do
# NOT live here. They are literals in test_electric_rig.gd instead: a constant
# in this file would be edited in the same breath as the plan it describes, so
# the test would ratify the new arithmetic instead of failing on it.

# Fuel level at which sustain_fuel() tops a LIT generator back up. Exactly 1,
# not "<= 1": burning steps fuel_buffer down one unit at a time (Burner.
# consume_tick), so a generator the rig is sustaining passes through 1 on its
# way down and never reaches 0. A buffer AT 0 therefore means something other
# than burning emptied it — the player, through the generator's fuel slot —
# and the rig leaves that alone rather than silently refunding it (see the
# item-duplication note on sustain_fuel).
const SUSTAIN_REFUEL_AT: int = 1

## The build plan: [offset: Vector2i, building_type: int, dir: int].
##
## No overlay/base columns (unlike main.gd's _spawn_demo_chain plans) because
## build() paves the ENTIRE rectangle in a separate first phase. That split is
## load-bearing, not tidiness: can_place_building validates the FULL footprint,
## so the 2x2 STEAM_GENERATORs need STONE on all four of their cells before the
## anchor row runs. _spawn_demo_chain's interleaved style emits the 2x2 Mixer's
## anchor BEFORE the rows that pave its expansion cells, which only lands when
## world-gen happened to leave those cells buildable. Copying that here would
## make both generators seed-dependent, and a missing generator means supply is
## 20 instead of 40 and every satisfaction number above is wrong.
static func plan() -> Array:
	return [
		# --- generators: 2x2, dir = DIR_E so the fuel port (canonical S,
		# rotated by dir) stays on the world S edge. That edge faces a pole
		# and bare stone — neither is a BELT or a CHEST, the only two things
		# Burner.try_pull_fuel reacts to — so neither generator can ever pull
		# fuel from the world. That is what makes the lever authoritative:
		# fuel_buffer only changes because the lever wrote it or because the
		# generator burned a unit. Keep (1,4) and (4,4) empty for this reason.
		[GEN_A_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E],
		[GEN_B_OFFSET, Buildings.Type.STEAM_GENERATOR, Belt.DIR_E],

		# --- pole bus: row y=4, spacing 3 == PowerNetwork.POLE_RANGE. That
		# spacing is the MAXIMUM that still yields a single component, and
		# with SUPPLY_RADIUS 1 the poles' 3x3 supply areas abut exactly,
		# covering x -1..16 by y 3..5 with no gaps and no wasted poles.
		# Generators use the OTHER rule (_adjacent_component_id): gen A's S
		# edge cell (0,4) and gen B's (3,4) are poles, so both touch the bus.
		[Vector2i(0, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(3, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(6, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(9, 4),  Buildings.Type.POWER_POLE, 0],
		[Vector2i(12, 4), Buildings.Type.POWER_POLE, 0],
		[Vector2i(15, 4), Buildings.Type.POWER_POLE, 0],

		# --- HERO rig: loaded chest -> electric inserter (facing E) -> empty
		# chest. The ONLY inserter flanked by chests, and therefore the only
		# one whose arm visibly changes speed. All four share the cyan body
		# and all four go dark-grey at zero power, so the flanking chests are
		# the user's only way to identify which machine to watch.
		[SOURCE_CHEST_OFFSET, Buildings.Type.CHEST,             0],
		[HERO_OFFSET,         Buildings.Type.ELECTRIC_INSERTER, Belt.DIR_E],
		[DEST_CHEST_OFFSET,   Buildings.Type.CHEST,             0],

		# --- load inserters: pure demand, 5 units each. Faced N so their
		# source tile is bare stone at y=6 and their dest is the pole row.
		# Neither is a belt/chest/processor, so they idle forever and can
		# never touch the hero chain. Their demand still counts: the
		# ELECTRIC_INSERTER arm of PowerNetwork Stage 1 is unconditional.
		[Vector2i(12, 5), Buildings.Type.ELECTRIC_INSERTER, Belt.DIR_N],
		[Vector2i(13, 5), Buildings.Type.ELECTRIC_INSERTER, Belt.DIR_N],
		[Vector2i(14, 5), Buildings.Type.ELECTRIC_INSERTER, Belt.DIR_N],

		# --- 10 lamps on row y=3. x=10 and x=11 are left open on purpose as
		# a walk-in corridor down to the bus row: lamps and chests are
		# walkable:false, poles are walkable:true, and a player who cannot
		# reach the rig cannot press E or Q on anything inside it.
		[Vector2i(5, 3),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(6, 3),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(7, 3),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(8, 3),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(9, 3),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(12, 3), Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(13, 3), Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(14, 3), Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(15, 3), Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(16, 3), Buildings.Type.ELECTRIC_LAMP, 0],

		# --- 10 lamps on row y=5.
		[Vector2i(-1, 5), Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(0, 5),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(1, 5),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(2, 5),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(3, 5),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(4, 5),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(5, 5),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(6, 5),  Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(10, 5), Buildings.Type.ELECTRIC_LAMP, 0],
		[Vector2i(11, 5), Buildings.Type.ELECTRIC_LAMP, 0],
	]

## Build the rig with its origin at `origin` (an ABSOLUTE tile).
##
## Returns a plain-data report:
##   { "placed": int, "skipped": int, "gen_anchors": Array[Vector2i],
##     "source_chest": Vector2i, "hero": Vector2i, "dest_chest": Vector2i }
##
## gen_anchors is ORDERED — the lever fuels the FIRST N of them, so index 0 is
## the generator that stays lit in the brownout state.
static func build(world, origin: Vector2i) -> Dictionary:
	# ---- Phase 1: pave. ----
	# Writing a fresh Tile does three jobs at once, and all three are needed
	# for the rig to land on ANY world seed:
	#   1. clears a WATER base, which can_place_building rejects outright;
	#   2. resets resource_node to ResourceNodes.DEFAULT (Tile._init's third
	#      default), which is what lets set_overlay past its deposit/tree
	#      guard and stops can_place_building's own resource-node guard firing;
	#   3. clears any stale overlay so the STONE write below is the only one.
	# STONE and PATH are the only two overlays accepted by all five building
	# types used here (the intersection of their requires_overlay lists);
	# STONE is chosen for contrast against the surrounding grass. CHEST and
	# STEAM_GENERATOR are the traps — CHEST's requires_overlay is
	# [STONE, PATH, SOIL_TILLED] and the generator's is [STONE, PATH], neither
	# with Overlay.NONE, so bare grass fails for both.
	#
	# This IS destructive: it overwrites base, overlay and resource_node across
	# 120 tiles and discards their regrowth timers. Deliberate — it is the only
	# way to make placement seed-independent.
	#
	# The direct `world.tiles[pos] =` write does not itself record into
	# tile_modifications, but it does not need to: the set_overlay on the next
	# line records the WHOLE tile (base, overlay AND resource_node — see
	# grid_world.gd:347) once it has applied, so the base reset is saved too.
	# That only holds because the Tile written here always carries Overlay.NONE,
	# which keeps set_overlay off its `current_overlay == overlay` idempotent
	# early return (grid_world.gd:337) — the one path that records nothing.
	for y in range(PAVE_MIN.y, PAVE_MAX.y + 1):
		for x in range(PAVE_MIN.x, PAVE_MAX.x + 1):
			var pos: Vector2i = origin + Vector2i(x, y)
			# Never repaint under someone else's building. set_overlay would
			# refuse anyway, but the Tile.new above it would already have
			# stripped that building's terrain out from under it.
			if world.has_building_at(pos):
				continue
			world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
			world.set_overlay(pos, Terrain.Overlay.STONE)

	# ---- Phase 2: build, or ADOPT a rig that is already standing. ----
	#
	# Three outcomes, and telling them apart is not bookkeeping pedantry —
	# each one wants different treatment in Phase 3:
	#
	#   BUILT    — every planned cell was empty and got its building. Normal.
	#   ADOPTED  — every planned cell was ALREADY occupied by a building of
	#              exactly the planned type, anchored exactly where the plan
	#              puts it. That is what a relaunch onto a saved game looks
	#              like (`-- --scenario=electric_rig` on a save that already
	#              holds the rig, or F10 after F9). The right answer there is
	#              to RE-ATTACH the lever to the rig on the ground: hand back
	#              its real generator anchors instead of an empty array, which
	#              would leave a visibly complete rig that F8 refuses to touch
	#              and that goes dark 16 seconds later.
	#   COLLIDED — anything in between: the plan overlaps the player's own
	#              base. This gets NEITHER treatment. In particular Phase 3
	#              must not seed a chest we did not place, because a player's
	#              chest is type-identical to ours and `bag = [[IRON_ORE, N]]`
	#              would destroy everything they had stored in it with no undo.
	#
	# Type AND anchor are both checked. building_at() resolves any footprint
	# cell to its owning anchor, so a 2x2 generator sitting one tile off would
	# otherwise report as "already exactly ours" from the wrong cell.
	var entries: Array = plan()
	var placed: int = 0
	var skipped: int = 0
	var matched: int = 0              # collided with a building identical to the plan's
	var built_gens: Array = []
	var existing_gens: Array = []
	var built_source: bool = false
	var existing_source: bool = false
	var source_pos: Vector2i = origin + SOURCE_CHEST_OFFSET
	for entry in entries:
		var pos: Vector2i = origin + (entry[0] as Vector2i)
		var btype: int = int(entry[1])
		var dir: int = int(entry[2])
		if world.has_building_at(pos):
			skipped += 1
			var sitting: Building = world.building_at(pos)
			if sitting != null and sitting.type == btype and sitting.anchor == pos:
				matched += 1
				if btype == Buildings.Type.STEAM_GENERATOR:
					existing_gens.append(pos)
				elif btype == Buildings.Type.CHEST and pos == source_pos:
					existing_source = true
			continue
		if not world.place_building(btype, pos, dir):
			skipped += 1
			continue
		placed += 1
		if btype == Buildings.Type.STEAM_GENERATOR:
			built_gens.append(pos)
		elif btype == Buildings.Type.CHEST and pos == source_pos:
			built_source = true

	# Adoption is all-or-nothing on purpose. "Some of it was already here" is
	# the collision case, and a half-adopted rig has the wrong demand total.
	var adopted: bool = placed == 0 and matched == entries.size()
	var gen_anchors: Array = existing_gens if adopted else built_gens
	var source_is_ours: bool = existing_source if adopted else built_source

	# ---- Phase 3: seed state (plain data only — house law). ----
	# Only ever seed a chest this call placed, or one adoption proved is the
	# rig's own. See the COLLIDED case above.
	if source_is_ours:
		refill_source(world, source_pos)
	# Start at FULL, with seed_output true — the ONLY call that seeds it. A
	# freshly placed generator still reads output_active == false on tick 1
	# because update_supply_demand is a PRE-PASS that runs before the
	# generators' own tick, so without the seed the rig is dark for its first
	# two ticks. From tick 2 on, output_active is the generator's own
	# derivation from fuel and nothing here overwrites it.
	apply_power_state(world, gen_anchors, POWER_FULL, true)
	# Belt and braces — the six poles already set the flag inside
	# place_building, but topology correctness is the whole rig.
	world.mark_power_network_dirty()

	return {
		"placed": placed,
		"skipped": skipped,
		"adopted": adopted,
		"gen_anchors": gen_anchors,
		"source_seeded": source_is_ours,
		"source_chest": source_pos,
		"hero": origin + HERO_OFFSET,
		"dest_chest": origin + DEST_CHEST_OFFSET,
	}

## THE LEVER. Fuels the first FUELLED_BY_STATE[state] generators in
## `gen_anchors` and starves the rest.
##
## fuel_buffer is the lever and output_active is NOT, even though output_active
## is the field PowerNetwork actually reads. SteamGenerator.tick ends with
## `b.state["output_active"] = consumed` — an unconditional write, every tick —
## so this writes fuel and lets the generator derive the rest. Burner.
## consume_tick returns false the moment `int(b.state.get("fuel_buffer", 0))
## <= 0` and true on every tick above it. Nothing else gates it: there is no
## ignition flag, no warm-up counter, and no "was this fuel pulled through a
## port" bit, so a directly written fuel_buffer is sufficient and no physical
## fuel feed is required.
##
## `seed_output` writes output_active directly, and build() is the ONLY caller
## that passes true. It must stay that way. The autoload TickSystem._process
## runs before Main._process every frame and emits the tick synchronously, so
## anything main.gd writes to output_active during _process is what the NEXT
## tick's update_supply_demand pre-pass reads — ahead of, and instead of, the
## generator's own derivation. Re-asserting it per frame would therefore hold
## the rig at FULL POWER even with the fuel -> output_active -> supply path
## completely broken, which is the one path this whole scenario exists to put
## in front of a human. Per-frame holding is sustain_fuel()'s job, and it
## deliberately touches fuel only.
static func apply_power_state(world, gen_anchors: Array, state: int, seed_output: bool = false) -> void:
	var fuelled: int = int(FUELLED_BY_STATE[clampi(state, 0, POWER_STATE_COUNT - 1)])
	for i in gen_anchors.size():
		var anchor: Vector2i = gen_anchors[i]
		if not world.has_building_at(anchor):
			continue
		var gen: Building = world.building_at(anchor)
		if gen == null or gen.type != Buildings.Type.STEAM_GENERATOR:
			continue
		var lit: bool = i < fuelled
		# FUEL_BUFFER_CAPACITY, not some huge number. Burner.info_lines prints
		# "Fuel: N / 16 units" with no clamp anywhere in the codebase, so an
		# over-seed of 100000 is mechanically legal but renders an absurd
		# Q-inspect line during exactly the inspection this rig exists for.
		# 16 units is only 16 seconds at CYCLE_TICKS 20 / 20 TPS, so the caller
		# tops it back up via sustain_fuel().
		gen.state["fuel_buffer"] = Burner.FUEL_BUFFER_CAPACITY if lit else 0
		if seed_output:
			gen.state["output_active"] = lit

## Hold the CURRENT lever position indefinitely. Called every frame by
## main.gd's _sustain_rig_power.
##
## Narrow on purpose, in three separate ways:
##
##   - fuel ONLY. output_active is left to SteamGenerator.tick, for the
##     tick-ordering reason spelled out on apply_power_state above.
##   - LIT generators only. The lever already wrote 0 to the dark ones; if a
##     player hand-feeds coal into a dark generator's fuel slot, that is a
##     visible action with a visible result, and zeroing it one frame later
##     would silently eat their coal. The next F8 press re-zeroes it.
##   - only at EXACTLY SUSTAIN_REFUEL_AT units. Burning walks the buffer down
##     one unit per second, so a sustained generator hits 1 and is topped back
##     to 16 roughly every 15 s and never reaches 0. A buffer the player
##     emptied through the panel's Take is therefore NOT refunded — it sits at
##     0 and that generator stays dark until the next F8 press, which is
##     recoverable and honest, rather than regenerating 16 units per frame
##     into the player's cursor.
##
## Hand-editing a rig generator's fuel slot is still not a meaningful thing to
## do — the lever, not the slot, decides what the rig is showing.
static func sustain_fuel(world, gen_anchors: Array, state: int) -> void:
	var fuelled: int = int(FUELLED_BY_STATE[clampi(state, 0, POWER_STATE_COUNT - 1)])
	for i in gen_anchors.size():
		if i >= fuelled:
			continue
		var anchor: Vector2i = gen_anchors[i]
		if not world.has_building_at(anchor):
			continue
		var gen: Building = world.building_at(anchor)
		if gen == null or gen.type != Buildings.Type.STEAM_GENERATOR:
			continue
		if int(gen.state.get("fuel_buffer", 0)) != SUSTAIN_REFUEL_AT:
			continue
		gen.state["fuel_buffer"] = Burner.FUEL_BUFFER_CAPACITY

## Refill the hero's source chest to SOURCE_COUNT. Called on spawn and on every
## lever press: an empty source chest drops the hero to STATE_IDLE, which looks
## exactly like a power fault to someone watching the arm stop.
static func refill_source(world, chest_pos: Vector2i) -> void:
	if not world.has_building_at(chest_pos):
		return
	var chest: Building = world.building_at(chest_pos)
	if chest == null or chest.type != Buildings.Type.CHEST:
		return
	chest.state["bag"] = [[SOURCE_ITEM, SOURCE_COUNT]]

## Human-readable lever description, including the numbers the user is meant to
## check against the Q-inspect panel. The toast is their only feedback about
## which of the three states they are in, so it states all three facts.
static func state_label(state: int) -> String:
	match clampi(state, 0, POWER_STATE_COUNT - 1):
		POWER_FULL:
			return "POWER: FULL — 2 of 2 generators fuelled, satisfaction 1.00, inserter 5 ticks/cycle"
		POWER_BROWNOUT:
			return "POWER: BROWNOUT — 1 of 2 generators fuelled, satisfaction 0.50, inserter 10 ticks/cycle"
		_:
			return "POWER: ZERO — 0 of 2 generators fuelled, satisfaction 0.00, inserter NO POWER"
