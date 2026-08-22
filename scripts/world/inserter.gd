class_name Inserter
extends RefCounted

## Inserter — connective tissue of the factory.
##
## Tier-parametric: serves both the basic INSERTER (1.0s cycle, no filter)
## and the FAST_INSERTER (0.5s cycle, single-slot filter), and is
## designed to extend to future variants (electric, long-reach, stack)
## by adding rows to the `*_BY_TYPE` tables below + dispatch cases in
## buildings.gd. The refactor at session-inserter-fast-filter generalized
## the originally-single-tier shape from session-inserter-foundation.
##
## Picks up an item from the source tile (one cell behind the inserter,
## opposite of `dir`), swings the arm to the destination tile (one cell
## ahead, in `dir`), drops the item, swings back. Universal source/dest:
## belts, chests, and recipe-driven processor I/O ports.
##
## Fuel-powered via Burner module (BURNER tiers only; the electric tier
## draws from the power network instead). Cycle speed is FIXED per tier for
## burner tiers — the electric tier stretches with satisfaction since Task 6.
## For burner tiers, fuel
## tier (wood / coal / briquette) determines fuel ECONOMY (how often you
## need to refill), NOT speed. Reversal #7 from session-inserter-
## foundation PAUSE 1: tying speed to fuel tier conflated two orthogonal
## axes. Throughput upgrades come via building TYPE (basic → fast →
## electric), not via fuel choice.
##
## State machine (6 phases):
##   IDLE              — arm at rest (source side); waiting for source/dest/fuel
##   WORKING_OUT       — arm interpolating source → destination, holding item
##   BLOCKED_AT_DEST   — arm at destination, holding item, drop blocked
##   WORKING_IN        — arm interpolating destination → source, returning empty
##   NO_FUEL           — like IDLE but explicit "out of fuel"   (burner tiers)
##   NO_POWER          — like IDLE but explicit "out of power"  (electric tiers)
##
## NO_FUEL and NO_POWER are HOLDING stalls: both are written before tick()
## touches held_item_buffer or cycle_progress, so an outage taken mid-swing
## keeps the item in hand and resumes the same delivery afterwards. Both are
## named in the IDLE arm of tick()'s state machine — see the resume-guard
## comment there for why a stall must never get an arm of its own.
##
## Architectural notes:
##   - cycle_progress (0.0..1.0) drives both phase transitions AND arm
##     animation angle. Per-tick stepping; no sub-tick interpolation.
##   - filter_item_type (state field, default -1) gates pickup. Universal
##     across tiers in DATA — only fast/electric tier UI exposes setting
##     it, but tick logic checks it on every inserter (no-op when -1).
##   - Port layout (canonical, dir = DIR_E): W = source, E = destination,
##     S = fuel input. Restricting fuel to a perpendicular edge protects
##     the source-tile items from being eaten as fuel — see FUEL_PORT_DIR
##     constant docstring.

# State machine values.
const STATE_IDLE: int            = 0
const STATE_WORKING_OUT: int     = 1
const STATE_BLOCKED_AT_DEST: int = 2
const STATE_WORKING_IN: int      = 3
const STATE_NO_FUEL: int         = 4
# NO POWER — the electric-tier counterpart of NO_FUEL (Session 4 Task 7).
# Entered when network satisfaction is at or below POWER_EPSILON. Like
# NO_FUEL it is a HOLDING stall: the tick() write returns before touching
# held_item_buffer / cycle_progress, so the item in hand and the swing
# position both survive the outage. Burner tiers can never reach it.
const STATE_NO_POWER: int        = 5

# Per-tier cycle duration (ticks @ 20 TPS). Add a row when a new inserter
# tier ships; tick logic reads via `cycle_ticks(b)` lookup. Default
# fallback (lookup miss) = 20, matching the basic tier.
#   INSERTER:          20 ticks = 1.0s — basic (Session 1)
#   FAST_INSERTER:     row added at session-inserter-fast-filter (Session 2)
#   ELECTRIC_INSERTER: row added at session-inserter-electric (Session 4)
const CYCLE_TICKS_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             20,    # 1.0s — basic
	Buildings.Type.FAST_INSERTER:        10,    # 0.5s — twice as fast
	Buildings.Type.LONG_REACH_INSERTER:  30,    # 1.5s — slower, balances reach
	Buildings.Type.ELECTRIC_INSERTER:    5,     # 0.25s at full power — twice the fast tier
}
const CYCLE_TICKS_DEFAULT: int = 20

# Per-tier body color. New tiers add an entry; default fallback is bronze
# (basic). Pattern mirrored in CYCLE_TICKS_BY_TYPE, REACH_BY_TYPE, and
# ARM_LENGTH_BY_TYPE below.
#   INSERTER:            bronze (basic — Session 1)
#   FAST_INSERTER:       row added at session-inserter-fast-filter (Session 2)
#   LONG_REACH_INSERTER: row added at session-inserter-long-reach (Session 3)
#   ELECTRIC_INSERTER:   row added at session-inserter-electric (Session 4)
const BODY_COLOR_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             Color(0.55, 0.45, 0.30),    # bronze
	Buildings.Type.FAST_INSERTER:        Color(0.45, 0.55, 0.70),    # cool blue-grey
	Buildings.Type.LONG_REACH_INSERTER:  Color(0.65, 0.30, 0.22),    # rust-red — "reach" tier
	Buildings.Type.ELECTRIC_INSERTER:    Color(0.25, 0.75, 0.80),    # electric cyan — matches DATA swatch
}
const BODY_COLOR_DEFAULT: Color = Color(0.55, 0.45, 0.30)

# Per-tier reach (in tiles). Source = anchor - reach*DIR_VECS[dir]; dest =
# anchor + reach*DIR_VECS[dir]. New table introduced at session-inserter-
# long-reach to support reach as an orthogonal upgrade axis from speed.
# Default fallback = 1 (basic-equivalent — preserves existing tier behavior).
#   INSERTER:             1 — basic (Session 1)
#   FAST_INSERTER:        1 — fast (Session 2)
#   LONG_REACH_INSERTER:  added at session-inserter-long-reach (Session 3)
#   ELECTRIC_INSERTER:    1 — added at session-inserter-electric (Session 4).
#     Equals REACH_DEFAULT, but listed explicitly like every other tier:
#     the row documents intent, and stops a future default change from
#     silently moving the electric tier along with it.
const REACH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             1,
	Buildings.Type.FAST_INSERTER:        1,
	Buildings.Type.LONG_REACH_INSERTER:  2,
	Buildings.Type.ELECTRIC_INSERTER:    1,
}
const REACH_DEFAULT: int = 1

# Per-tier arm length (fraction of tile_size). REFACTORED from a single
# `const ARM_LENGTH = 0.55` at session-inserter-long-reach — long-reach
# tier needs a longer arm visual, so the param becomes per-type. Baseline
# 0.55 preserved for INSERTER / FAST_INSERTER (pure additive change).
#   INSERTER:             0.55 — basic
#   FAST_INSERTER:        0.55 — fast (visually identical to basic)
#   LONG_REACH_INSERTER:  added at session-inserter-long-reach (Session 3)
#   ELECTRIC_INSERTER:    0.55 — added at session-inserter-electric (Session 4).
#     Same explicit-over-fallback rationale as REACH_BY_TYPE above.
const ARM_LENGTH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             0.55,
	Buildings.Type.FAST_INSERTER:        0.55,
	Buildings.Type.LONG_REACH_INSERTER:  2.00,    # physically reaches 2-tile-away source/dest
	Buildings.Type.ELECTRIC_INSERTER:    0.55,    # visually identical to basic / fast
}
const ARM_LENGTH_DEFAULT: float = 0.55

# Per-tier POWER draw, in network units per tick. Introduced at session-
# inserter-electric (Session 4, Task 5). This table is the SINGLE SOURCE OF
# TRUTH for "is this tier electric": a tier listed here draws from the power
# network and runs no Burner logic; a tier absent from it is a burner and
# keeps the fuel path. Deriving is_electric() from the demand table rather
# than a parallel list means a future electric tier is exactly one row, and
# the two facts can never disagree.
#
# Balance rationale for 5 units. Reference points on the same network:
# an ELECTRIC_LAMP draws 1; a WINDMILL supplies 6, a WATER_WHEEL 10, a
# STEAM_GENERATOR 20. So one windmill runs roughly one electric inserter
# and little else — the tier is a real infrastructure commitment, which is
# the intended price for twice the fast tier's speed (5-tick cycle vs 10)
# with no fuel logistics at all. A water wheel covers two; a steam
# generator four.
#
# The draw is CONSTANT, not duty-cycled — an idle inserter still draws its
# full 5. PowerNetwork.update_supply_demand runs as a pre-pass BEFORE the
# building tick loop, so any activity state it sampled would be one tick
# stale; gating demand on activity would close a delayed-feedback loop and
# make lamps on the same network flicker. See the ELECTRIC_INSERTER arm in
# power_network.gd Stage 1.
const POWER_DEMAND_BY_TYPE: Dictionary = {
	Buildings.Type.ELECTRIC_INSERTER: 5,
}

# Floor on the satisfaction divisor in effective_cycle_ticks. Below this,
# a network is not browning out, it is off.
#
# 0.05 is not arbitrary: it is the ELECTRIC_LAMP's documented on/off
# threshold (electric_lamp.gd draw() — the glow halo appears at
# `sat > 0.05`). Sharing the number means "too dark to bother" and "too
# weak to run" are the SAME point on the dial, so a player watching lamps
# die can read the moment their inserters give up. Task 7 reuses this
# constant as the STATE_NO_POWER cutoff for exactly that reason.
#
# As a divisor floor it caps the worst case: the electric tier's 5-tick
# cycle stretches to at most ceil(5 / 0.05) = 100 ticks, a 20x slowdown.
# Without the floor a satisfaction of 0.0 would divide by zero.
const POWER_EPSILON: float = 0.05

# Fuel input port direction (canonical orientation; rotates with b.dir
# via Buildings.world_dir). Mirrors the Smelter pattern from session-
# smelter — restricting fuel intake to ONE specific perpendicular edge
# prevents the source-tile-as-fuel bug where wood items in the source
# chest get auto-pulled and burned as fuel instead of transported.
#
# Canonical port layout (b.dir = DIR_E):
#   W edge: source (opposite of dir)
#   E edge: destination (dir)
#   S edge: fuel input (this constant)
#   N edge: unused (reserved for future filter signal / 2nd fuel port)
#
# All ports rotate together via Buildings.world_dir(b, canonical).
const FUEL_PORT_DIR: int = Belt.DIR_S

# Visuals shared across all tiers.
const BODY_DARK: Color = Color(0.18, 0.13, 0.08)
const ARM_COLOR: Color = Color(0.20, 0.16, 0.10)
const PIVOT_COLOR: Color = Color(0.30, 0.25, 0.18)
const TINT_IDLE: Color = Color(0.60, 0.60, 0.60)        # dim when idle / no_fuel
const TINT_NO_FUEL: Color = Color(0.55, 0.55, 0.85)     # cool blue tint
const TINT_BLOCKED: Color = Color(1.0, 0.95, 0.40)      # yellow when blocked
# NO POWER (electric tiers only — a burner can never reach this state).
# Deliberately NOT a variant of TINT_NO_FUEL's cool blue: the two stalls have
# different causes and different fixes, so they must be tellable apart at a
# glance on the map rather than only in the panel.
#
# Warm and red-weighted, which matters because these tints MULTIPLY the body
# colour. Against the electric tier's cyan (0.25, 0.75, 0.80) it lands on a
# flat dark grey — the machine reads as switched off, the same "the lights
# went out" cue ELECTRIC_LAMP gives, at the same POWER_EPSILON threshold.
# TINT_IDLE leaves the body recognisably cyan and TINT_NO_FUEL pushes it
# blue, so all three remain distinct.
const TINT_NO_POWER: Color = Color(0.85, 0.30, 0.25)

## Cycle ticks for this inserter's tier. Public API — also called by
## InserterPanel / FastInserterPanel for "Cycle: Xs" displays.
static func cycle_ticks(b: Building) -> int:
	return int(CYCLE_TICKS_BY_TYPE.get(b.type, CYCLE_TICKS_DEFAULT))

## Body color for this inserter's tier. Public API — used by draw().
static func body_color(b: Building) -> Color:
	return BODY_COLOR_BY_TYPE.get(b.type, BODY_COLOR_DEFAULT)

## Reach (in tiles) for this inserter's tier. Public API — used by
## source_tile() and dest_tile() to compute the offset along b.dir.
## Default fallback = 1 (basic-equivalent).
static func reach(b: Building) -> int:
	return int(REACH_BY_TYPE.get(b.type, REACH_DEFAULT))

## Arm length (fraction of tile_size) for this inserter's tier. Public API
## — used by draw(). Default fallback = 0.55 (basic-equivalent baseline).
static func arm_length(b: Building) -> float:
	return float(ARM_LENGTH_BY_TYPE.get(b.type, ARM_LENGTH_DEFAULT))

## Power units this inserter draws from its network per tick. 0 for burner
## tiers (lookup miss). Public API — read by PowerNetwork.update_supply_demand
## Stage 1 to accumulate component demand.
static func power_demand(b: Building) -> int:
	return int(POWER_DEMAND_BY_TYPE.get(b.type, 0))

## True if this tier is power-driven rather than fuel-driven. Derived from
## POWER_DEMAND_BY_TYPE membership on purpose — see that table's docstring:
## one source of truth, so "draws power" and "is not a burner" cannot drift
## apart. Gates the Burner fuel path in tick().
static func is_electric(b: Building) -> bool:
	return POWER_DEMAND_BY_TYPE.has(b.type)

## Cycle ticks AFTER power-satisfaction scaling — the brownout rule.
## Public API — tick() derives its per-tick cycle increment from this.
##
##   effective = ceil(cycle_ticks(b) / max(POWER_EPSILON, satisfaction))
##
##   sat 1.00 ->  5 ticks (full speed)   sat 0.25 -> 20 ticks
##   sat 0.50 -> 10 ticks (half speed)   sat 0.05 -> 100 ticks (the floor)
##
## BURNER tiers are returned UNCHANGED, and return BEFORE the satisfaction
## lookup runs. That early return is load-bearing, not a micro-optimisation:
## a world with no power network reports satisfaction 0.0 everywhere, so a
## burner that fell through would divide by POWER_EPSILON and crawl at
## ceil(20 / 0.05) = 400 ticks — every fuel inserter in the game frozen by a
## feature that was never meant to reach them.
##
## Deliberately SEPARATE from cycle_ticks(b), which stays pure and
## world-free: InserterPanel reads it for the "Cycle: Xs" display and has no
## world reference to hand in. cycle_ticks is the tier's rating; this is what
## the tier actually manages on the network it happens to be standing on.
static func effective_cycle_ticks(b: Building, world) -> int:
	var base_ticks: int = cycle_ticks(b)
	if not is_electric(b):
		return base_ticks
	var sat: float = world.power_satisfaction_at(b.anchor)
	return int(ceil(float(base_ticks) / maxf(POWER_EPSILON, sat)))

## Build initial state. dir defaults to canonical east (DIR_E = 0).
## b_type defaults to INSERTER; pass FAST_INSERTER (or future tiers) for
## tier-specific buildings. State shape is uniform across tiers — the
## filter_item_type field exists on every inserter (default -1 = no
## filter), but only fast/electric tier UI exposes setting it.
##
## Cycle speed is fixed per tier (see CYCLE_TICKS_BY_TYPE) regardless of
## fuel tier — see file-level docstring for the reversal rationale.
static func make(pos: Vector2i, dir: int = 0, b_type: int = Buildings.Type.INSERTER) -> Building:
	var state: Dictionary = {
		"dir": dir,
		"held_item_buffer": [],          # [[item_type, count]]; count ∈ {0, 1}
		"cycle_progress": 0.0,
		"state": STATE_IDLE,
		"filter_item_type": -1,          # -1 = no filter; else Items.Type
	}
	for k in Burner.make_state().keys():
		state[k] = Burner.make_state()[k]
	return Building.new(b_type, pos, state)

## Tick logic. Dispatched from Buildings.tick_one. Both INSERTER and
## FAST_INSERTER (and future tiers) route here; differences resolved via
## the effective_cycle_ticks(b, world) lookup — the tier's rated
## cycle_ticks(b), scaled by network satisfaction for electric tiers.
##
## Order of operations:
##   1. Try to refuel if buffer empty.        — BURNER tiers only
##   2. If no fuel after refuel attempt → STATE_NO_FUEL, return.  — ditto
##   3. Run state machine based on current state.
##
## Steps 1-2 (and the consume_tick calls inside step 3's arms) are skipped
## entirely for POWER-driven tiers — see is_electric / POWER_DEMAND_BY_TYPE.
static func tick(b: Building, world) -> void:
	# Electric tiers are not burners: they have no fuel slot in DATA, so they
	# could never satisfy the fuel check below and would park in
	# STATE_NO_FUEL forever. Skip the whole fuel path for them (both the
	# pull attempt here and the consume_tick calls in the state arms), and
	# let the state machine run unconditionally. Electric tiers get their OWN
	# supply check instead, immediately below: a soft one (Task 6 — the cycle
	# STRETCHES with network satisfaction, see effective_cycle_ticks) and a
	# hard one (Task 7 — at or below POWER_EPSILON the machine stops).
	var electric: bool = is_electric(b)
	# (1 + 2) Fuel check + pull. Restricted to FUEL_PORT_DIR (rotated by
	# building dir) — see constant docstring for the source-tile-as-fuel
	# bug rationale (caught at session-inserter-fast-filter PAUSE 1).
	if not electric:
		var fuel_units: int = int(b.state.get("fuel_buffer", 0))
		if fuel_units <= 0:
			if not Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR)):
				b.state["state"] = STATE_NO_FUEL
				return
	else:
		# (1' + 2') POWER check — the electric-tier mirror of the fuel check
		# above, and deliberately the SAME SHAPE. Writing the stall state and
		# returning BEFORE anything touches held_item_buffer or cycle_progress
		# is the load-bearing part: the item in hand and the swing position
		# both survive the outage, so the resume guard in the
		# STATE_IDLE/NO_FUEL/NO_POWER arm below can pick the interrupted
		# delivery back up when power returns. That is the Session 4 Task 2
		# item-conservation fix applying to outages as well as to fuel.
		#
		# `sat <= POWER_EPSILON`, NOT `<`. electric_lamp.gd lights its glow at
		# `sat > 0.05`, so a lamp at exactly 0.05 is dark; matching the
		# comparison makes the two consumers agree on the boundary, and a
		# player watching lamps die can read the exact moment their inserters
		# give up. POWER_EPSILON's docstring records the shared-threshold
		# intent from the other end.
		#
		# CONSEQUENCE worth knowing: this makes effective_cycle_ticks'
		# maxf(POWER_EPSILON, sat) divisor floor purely DEFENSIVE. Anything at
		# or below epsilon now stalls here instead of crawling, so the 100-tick
		# worst case that floor caps is no longer reachable through tick() —
		# only through a direct effective_cycle_ticks call.
		#
		# The satisfaction lookup happens twice on a powered tick (here and
		# inside effective_cycle_ticks below). Accepted deliberately: it is a
		# dictionary read behind a small fixed scan, and the alternative —
		# threading the value into effective_cycle_ticks — would cost that
		# function the world-free purity InserterPanel depends on.
		if world.power_satisfaction_at(b.anchor) <= POWER_EPSILON:
			b.state["state"] = STATE_NO_POWER
			return
	# (3) State machine.
	var s: int = int(b.state.get("state", STATE_IDLE))
	# EFFECTIVE, not rated. For electric tiers this is cycle_ticks(b)
	# stretched by network satisfaction (Task 6 brownout); burner tiers get
	# their rated cycle_ticks(b) back unchanged, so the
	# `Burner.consume_tick(b, ticks)` calls in the arms below still burn one
	# fuel unit per rated cycle exactly as they did before.
	var ticks: int = effective_cycle_ticks(b, world)
	# Per-tick cycle increment. One full cycle (0→1) spans `ticks` ticks;
	# each half-cycle (swing-out OR swing-in) is ticks/2 ticks. Every state
	# arm advances cycle_progress by this ONE value, so a stretched cycle
	# interpolates smoothly across its longer span for free — the arm sweeps
	# slower rather than stalling and then leaping. That is why the brownout
	# needed no new interpolation code.
	var inc: float = 1.0 / float(ticks)

	match s:
		STATE_IDLE, STATE_NO_FUEL, STATE_NO_POWER:
			# RESUME GUARD — item-conservation fix (Inserter Arc Session 4,
			# audit findings #2 / #6).
			#
			# An inserter that runs dry MID-SWING reports STATE_NO_FUEL while
			# still holding its item: the fuel check above writes NO_FUEL and
			# returns BEFORE touching held_item_buffer / cycle_progress. That
			# write is deliberate — a stalled machine must read "NO FUEL", not
			# "Working". But it means the refuel tick lands HERE, in the
			# start-a-NEW-cycle arm, where _set_held() below does an
			# unconditional overwrite of held_item_buffer — silently destroying
			# the item already in hand. At most one item per outage: the
			# destruction needs the refuel-tick _try_pickup to SUCCEED, so an
			# empty source merely defers it until the next item arrives.
			#
			# STATE_NO_POWER joined this header at Task 7 for exactly that
			# reason, and the rule generalises: any future stall state that
			# holds its item must be added to THIS arm header, never given an
			# arm of its own — a separate arm re-creates the destruction bug,
			# and NO arm at all freezes the machine permanently, because this
			# match has no `_:` default and nothing outside the arms writes
			# b.state["state"]. (Unnamed is the worse of the two: it is silent,
			# and it survives power being restored. test_electric_inserter.gd
			# sub-case 9 is the tripwire.) Note this "extend, don't add" rule is
			# specific to the two multi-state arms (here and draw()'s arm-angle
			# match); info_lines and the draw tint DO have their own NO_POWER
			# entries, since that state needs distinct text and colour.
			#
			# Do NOT hoist the guard above the match: held_item_type(b) >= 0 is
			# also true in WORKING_OUT and BLOCKED_AT_DEST, so a hoisted guard
			# would fire every tick, return, and livelock the machine.
			#
			# A full hand means there is an interrupted DELIVERY to resume, not
			# a new pickup to start. Deliberately progress-INDEPENDENT: the
			# outage can be taken anywhere across the swing-out half (0.0 at
			# pickup .. 0.5 parked at a blocked destination), so gating on a
			# particular progress value would leave the rest of the band broken.
			#
			# The clamp is DEFENSIVE, not corrective — cycle_progress already
			# survives the outage untouched, and WORKING_OUT re-clamps on the
			# next tick anyway. Its one unique job is externally-supplied
			# state: cycle_progress arrives from JSON.parse_string on a
			# player-editable save file (and from an 18-version migration
			# chain), so a save carrying progress 0.9 with a full hand would
			# otherwise render the arm at a nonsensical angle for one tick
			# before WORKING_OUT corrects it. Resuming at WORKING_OUT (rather than jumping straight
			# to BLOCKED_AT_DEST) lets the existing WORKING_OUT arm re-attempt
			# the drop on the next tick, which settles a still-blocked
			# destination back into BLOCKED_AT_DEST on its own.
			if held_item_type(b) >= 0:
				b.state["cycle_progress"] = clampf(float(b.state.get("cycle_progress", 0.0)), 0.0, 0.5)
				b.state["state"] = STATE_WORKING_OUT
				return
			# Try to start a new cycle: source has item AND destination accepts.
			var picked: int = _try_pickup(b, world)
			if picked >= 0:
				_set_held(b, picked)
				b.state["cycle_progress"] = 0.0
				b.state["state"] = STATE_WORKING_OUT
				# Consume one fuel-burn tick this cycle. Burner tiers
				# only — an electric tier has no fuel buffer to burn.
				if not electric:
					Burner.consume_tick(b, ticks)
			else:
				# STALE-STATUS FIX (Session 4 Task 7, item B). Until this
				# `else` existed, b.state["state"] was written ONLY on the
				# successful-pickup path, so a machine that reached this arm
				# from a stall and found its source empty kept reporting the
				# stall it had already recovered FROM — a refuelled inserter
				# stuck on "NO FUEL", a repowered one stuck on "NO POWER",
				# indefinitely, with the player's actual fix already applied.
				#
				# Safe for burner tiers: an unfuelled one never reaches this
				# arm at all (the fuel check at the top of tick() writes
				# NO_FUEL and returns), so anything standing here is supplied
				# and genuinely idle. Same reasoning for power.
				b.state["state"] = STATE_IDLE
		STATE_WORKING_OUT:
			# Advance toward destination. cycle_progress 0 → 0.5.
			var p: float = float(b.state.get("cycle_progress", 0.0)) + inc
			if p >= 0.5:
				p = 0.5
				# Try to drop. If destination accepts, transition to WORKING_IN
				# (item placed, swing back). If blocked, hold + transition to
				# BLOCKED_AT_DEST.
				if _try_drop(b, world):
					_clear_held(b)
					b.state["state"] = STATE_WORKING_IN
				else:
					b.state["state"] = STATE_BLOCKED_AT_DEST
			b.state["cycle_progress"] = p
			if not electric:
				Burner.consume_tick(b, ticks)
		STATE_BLOCKED_AT_DEST:
			# Held item, arm pinned at destination. Try to drop every tick.
			# NO fuel consumption while blocked (arm isn't moving).
			if _try_drop(b, world):
				_clear_held(b)
				b.state["state"] = STATE_WORKING_IN
				# cycle_progress stays at 0.5; advances on next WORKING_IN tick.
		STATE_WORKING_IN:
			# Returning toward source. cycle_progress 0.5 → 1.0.
			var p2: float = float(b.state.get("cycle_progress", 0.5)) + inc
			if p2 >= 1.0:
				# Cycle complete. Reset and immediately try next pickup.
				p2 = 0.0
				b.state["state"] = STATE_IDLE
			b.state["cycle_progress"] = p2
			if not electric:
				Burner.consume_tick(b, ticks)

# ---------- helpers ----------

## Source tile = anchor + opposite-of-dir * reach. dir=E, reach=1 → source
## is west (1 tile away); reach=2 → source is 2 tiles west.
static func source_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	var r: int = reach(b)
	return Vector2i(b.anchor.x - v.x * r, b.anchor.y - v.y * r)

## Destination tile = anchor + dir * reach. dir=E, reach=1 → destination
## is east (1 tile away); reach=2 → destination is 2 tiles east.
static func dest_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	var r: int = reach(b)
	return Vector2i(b.anchor.x + v.x * r, b.anchor.y + v.y * r)

## Held item type or -1 if empty.
static func held_item_type(b: Building) -> int:
	var buf: Array = b.state.get("held_item_buffer", [])
	if buf.is_empty():
		return -1
	return int(buf[0][0])

static func _set_held(b: Building, item_type: int) -> void:
	b.state["held_item_buffer"] = [[item_type, 1]]

static func _clear_held(b: Building) -> void:
	b.state["held_item_buffer"] = []

# ---------- pickup logic ----------

## Try to pick one item from source tile. Returns the picked item type
## or -1 if nothing pickable.
##
## Filter semantics:
##   - filter_item_type == -1 (default for basic, unset on fast): pick
##     any item (basic-equivalent FIFO behavior — preserves backwards
##     compat exactly).
##   - filter_item_type == X (set on fast tier via FastInserterPanel
##     drop-to-set): pick ONLY items of type X. Non-matching items are
##     left in place (belt slot stays occupied, chest entries stay).
##     Mid-cycle filter changes don't affect already-held items —
##     in-flight cycles complete; filter gates next pickup.
##
## Source priority by building type:
##   BELT  → take item from the slot facing the inserter, IF it matches
##           filter (or no filter). No "scan further down the belt" —
##           that would be the long-reach variant or different design.
##   CHEST → scan bag for first matching item (filter set) or first non-
##           empty entry (filter unset).
##   Recipe-driven Processor → scan out_buffer same as chest.
##   Otherwise: no-op.
static func _try_pickup(b: Building, world) -> int:
	var src: Vector2i = source_tile(b)
	if not world.has_building_at(src):
		return -1
	var src_b: Building = world.building_at(src)
	if src_b == null:
		return -1
	var filter: int = int(b.state.get("filter_item_type", -1))
	# Belt: pull from the slot facing the inserter.
	if src_b.type == Buildings.Type.BELT:
		return _pickup_from_belt(b, src_b, filter)
	# Chest: FIFO from bag (or first matching entry if filter set).
	if src_b.type == Buildings.Type.CHEST:
		return _pickup_from_chest(src_b, filter)
	# Recipe-driven Processor: pull from out_buffer (FIFO or filter match).
	if _is_processor_with_output(src_b):
		return _pickup_from_processor(src_b, filter)
	return -1

static func _pickup_from_belt(b: Building, belt: Building, filter: int) -> int:
	# The slot index facing the inserter = the slot at the END of the
	# belt closest to the inserter. Belt slots are direction-flow ordered;
	# `Belt.slot_facing_external` already implements this for cross-belt
	# handoffs. We piggyback on it.
	var slot_idx: int = Belt.slot_facing_external(belt, b.anchor)
	if slot_idx < 0:
		return -1
	var slots: Array = belt.state.get("slots", [])
	if slot_idx >= slots.size():
		return -1
	var item_t: int = int(slots[slot_idx])
	if item_t < 0:
		return -1
	# Filter check BEFORE consumption — leave non-matching items on belt.
	if filter >= 0 and item_t != filter:
		return -1
	slots[slot_idx] = -1
	return item_t

static func _pickup_from_chest(chest: Building, filter: int) -> int:
	var bag: Array = chest.state.get("bag", [])
	for entry in bag:
		var item_t: int = int(entry[0])
		var count: int = int(entry[1])
		if count <= 0:
			continue
		# Filter check BEFORE consumption — skip non-matching entries.
		if filter >= 0 and item_t != filter:
			continue
		entry[1] = count - 1
		if int(entry[1]) <= 0:
			bag.erase(entry)
		return item_t
	return -1

static func _pickup_from_processor(src: Building, filter: int) -> int:
	# Pull from out_buffer (FIFO, or first matching entry if filter set).
	# Mirrors the buffer-remove pattern from Processor / FertilizerApplicator.
	var out_buf: Array = src.state.get("out_buffer", [])
	for entry in out_buf:
		var item_t: int = int(entry[0])
		var count: int = int(entry[1])
		if count <= 0:
			continue
		# Filter check BEFORE consumption.
		if filter >= 0 and item_t != filter:
			continue
		entry[1] = count - 1
		if int(entry[1]) <= 0:
			out_buf.erase(entry)
		return item_t
	return -1

# ---------- drop logic ----------

## Try to drop the held item at destination. Returns true on success
## (caller clears held_item).
static func _try_drop(b: Building, world) -> bool:
	var item: int = held_item_type(b)
	if item < 0:
		return true   # nothing to drop — vacuous success
	var dst: Vector2i = dest_tile(b)
	if not world.has_building_at(dst):
		return false
	var dst_b: Building = world.building_at(dst)
	if dst_b == null:
		return false
	# Belt: insert via existing API. Item enters at slot[0] of the belt
	# (the "back of the queue") — consistent with how Processors push.
	if dst_b.type == Buildings.Type.BELT:
		return Belt.try_insert(dst_b, item)
	# Chest: append to bag.
	if dst_b.type == Buildings.Type.CHEST:
		return _drop_to_chest(dst_b, item)
	# Recipe-driven Processor: drop into in_buffer if recipe accepts.
	if _is_processor_with_input(dst_b):
		return _drop_to_processor(dst_b, item)
	return false

static func _drop_to_chest(chest: Building, item: int) -> bool:
	# Mirror the chest-add pattern: try to top up an existing entry,
	# otherwise append a new one. Chest cap check (TOTAL_CAPACITY = 2400)
	# is generous; for v1 we don't enforce per-stack caps inside the bag
	# (chest uses aggregate capacity, not per-slot).
	var bag: Array = chest.state.get("bag", [])
	# Top-up existing entry if present.
	for entry in bag:
		if int(entry[0]) == item:
			entry[1] = int(entry[1]) + 1
			return true
	# New entry.
	bag.append([item, 1])
	return true

static func _drop_to_processor(dst: Building, item: int) -> bool:
	# Drop to in_buffer ONLY if the building's recipe (current OR any
	# recipe registered for this building type) accepts the item.
	# Mirrors the slot_layout.accepts check that Processor's pull uses.
	var layout: Array = Buildings.slot_layout_for(dst.type)
	for slot in layout:
		if str(slot.get("kind", "")) != "input":
			continue
		var accepts: Array = slot.get("accepts", [])
		if not accepts.is_empty() and not accepts.has(item):
			continue
		# Capacity check: don't exceed input_capacity (recipe-defined).
		var in_buf: Array = dst.state.get("in_buffer", [])
		var current_total: int = 0
		for entry in in_buf:
			current_total += int(entry[1])
		# Use recipe capacity if a recipe is set; otherwise use the
		# slot's max_stack as fallback.
		var cap: int = int(slot.get("max_stack", 8))
		if current_total >= cap:
			return false
		# Top-up or append.
		for entry in in_buf:
			if int(entry[0]) == item:
				entry[1] = int(entry[1]) + 1
				dst.state["in_buffer"] = in_buf
				return true
		in_buf.append([item, 1])
		dst.state["in_buffer"] = in_buf
		return true
	return false

## True if `b` is a recipe-driven Processor with a non-empty out_buffer
## (eligible source for inserter pickup).
static func _is_processor_with_output(b: Building) -> bool:
	# Heuristic: building has an "out_buffer" state field. Covers Mill,
	# Mixer, Composter, Smelter, etc. Not foolproof (a future non-
	# Processor with an out_buffer would also match), but matches all
	# current cases.
	return b.state.has("out_buffer")

## True if `b` has a recipe-input slot (eligible destination for
## inserter drop).
static func _is_processor_with_input(b: Building) -> bool:
	for slot in Buildings.slot_layout_for(b.type):
		if str(slot.get("kind", "")) == "input":
			return true
	return false

## Read-only mirror of _try_pickup's source-scanning logic, filtered to a
## SPECIFIC item type. Returns true if any cell of the source tile's
## building contains at least one item of `item_type`. Used by info_lines
## to surface the "no items match filter" diagnostic.
##
## Source types covered: BELT, CHEST, recipe-driven Processor (out_buffer).
## Same TYPE dispatch as _try_pickup (BELT/CHEST/Processor); BELT body
## diverges intentionally — see comment on the BELT branch below.
## Returns false for unrecognized source types (which is correct — IDLE
## status line will appear, hinting that the source isn't a valid item
## source).
static func _source_has_matching_item(world, src_pos: Vector2i, item_type: int) -> bool:
	if not world.has_building_at(src_pos):
		return false
	var src_b: Building = world.building_at(src_pos)
	if src_b == null:
		return false
	# Belt: scan ALL slots for the matching item, not just the facing
	# slot (which is what _try_pickup does via Belt.slot_facing_external).
	# Intentional divergence: this is a diagnostic, not a pickup. A
	# matching item ANYWHERE on the source belt means the filter is
	# correctly configured and items will flow through eventually — no
	# need to nag the player with "no items match filter" during transient
	# belt flow. Avoids false-positive IDLE-status flicker.
	if src_b.type == Buildings.Type.BELT:
		var slots: Array = src_b.state.get("slots", [])
		for s in slots:
			if int(s) == item_type:
				return true
		return false
	# Chest: scan bag for matching item with count > 0.
	if src_b.type == Buildings.Type.CHEST:
		var bag: Array = src_b.state.get("bag", [])
		for entry in bag:
			if int(entry[0]) == item_type and int(entry[1]) > 0:
				return true
		return false
	# Recipe-driven Processor: scan out_buffer.
	if _is_processor_with_output(src_b):
		var out_buf: Array = src_b.state.get("out_buffer", [])
		for entry in out_buf:
			if int(entry[0]) == item_type and int(entry[1]) > 0:
				return true
		return false
	return false

# ---------- info_lines (Q-inspect) ----------

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	# Status.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var status: String = "Idle"
	match s:
		STATE_WORKING_OUT:
			status = "Working (out)"
		STATE_BLOCKED_AT_DEST:
			status = "BLOCKED — destination full or rejecting item"
		STATE_WORKING_IN:
			status = "Working (returning)"
		STATE_NO_FUEL:
			status = "NO FUEL — feed wood, coal, or fuel briquette"
		STATE_NO_POWER:
			# Its OWN entry, not folded into the NO_FUEL arm: the two stalls
			# have different fixes, and the whole value of the line is telling
			# the player WHICH one they are looking at.
			#
			# The remedy names the supply rule literally, and since Task 5 that
			# rule is PER-TIER: every pole tier projects its own supply area,
			# so a basic pole has to be within 1 while a substation reaches 4.
			# Both numbers are READ FROM THE TABLE — supply_radius() and
			# max_supply_radius() over PowerNetwork.SUPPLY_RADIUS_BY_TYPE — so
			# retuning a tier retunes this line instead of leaving it lying.
			# It used to say "within 1 tile" flat, which was exactly right only
			# while the basic pole was the one tier that projected anything.
			status = "NO POWER — no pole in range (a basic pole reaches %d, the widest tier %d)" % [
				PowerNetwork.supply_radius(Buildings.Type.POWER_POLE),
				PowerNetwork.max_supply_radius(),
			]
	lines.append("Status: %s" % status)
	# Held item.
	var held: int = held_item_type(b)
	if held >= 0:
		lines.append("Holding: %s" % Items.name_of(held))
	# Cycle — EFFECTIVE, with the tier's rating named alongside it when the
	# two differ. Before Task 7 this line reported cycle_ticks(b) alone, so a
	# browned-out electric inserter insisted it ran at 0.25s while its arm
	# visibly took 0.50s. Showing both makes the brownout self-diagnosing:
	# "slower than rated" is the symptom, and the panel says so.
	#
	# Two decimals, not one: the electric tier's rating is 0.25s, which %.1f
	# renders as the wrong number ("0.3s").
	#
	# world may be null (info_lines' own signature allows it, and the
	# source/destination block below already guards for it), in which case
	# there is nothing to scale by and the rating is the honest answer.
	var cycle_progress: float = float(b.state.get("cycle_progress", 0.0))
	var rated_ticks: int = cycle_ticks(b)
	var eff_ticks: int = rated_ticks if world == null else effective_cycle_ticks(b, world)
	if eff_ticks == rated_ticks:
		lines.append("Cycle: %.0f%% (%.2fs per cycle)" % [cycle_progress * 100.0, float(rated_ticks) / 20.0])
	else:
		lines.append("Cycle: %.0f%% (%.2fs per cycle, rated %.2fs)"
			% [cycle_progress * 100.0, float(eff_ticks) / 20.0, float(rated_ticks) / 20.0])
	# Filter (fast + electric tiers — basic and long-reach have no filter
	# slot, so the line would always read "(none)" for them).
	if b.type == Buildings.Type.FAST_INSERTER or is_electric(b):
		var filter: int = int(b.state.get("filter_item_type", -1))
		if filter >= 0:
			lines.append("Filter: %s" % Items.name_of(filter))
			# QoL Cluster B Item 3: if filter set AND source has no matching
			# items, surface diagnostic line so players know WHY the inserter
			# is idle. Without this, "IDLE" + "Filter: X" requires manual
			# source-inspection to find the empty-supply cause.
			if world != null and not _source_has_matching_item(world, source_tile(b), filter):
				lines.append("Status: IDLE (no items match filter)")
		else:
			lines.append("Filter: (none — picks any item)")
	# Burner fuel display — BURNER TIERS ONLY.
	#
	# Inserter.make copies Burner.make_state() onto EVERY tier, electric
	# included, so an electric inserter carries a fuel_buffer that is
	# permanently 0. Burner.info_lines emits "Status: NO FUEL — feed wood,
	# coal, or fuel briquette" whenever the buffer is empty, so before this
	# gate a perfectly healthy electric inserter reported a fuel problem it
	# has no fuel slot to fix — directly contradicting the "Status:" line four
	# lines above it. Gated on is_electric for the same one-source-of-truth
	# reason tick() uses it: the tier list lives in POWER_DEMAND_BY_TYPE and
	# nowhere else.
	if not is_electric(b):
		for line in Burner.info_lines(b):
			lines.append(line)
	# Source / destination summary.
	if world != null:
		var src: Vector2i = source_tile(b)
		var dst: Vector2i = dest_tile(b)
		lines.append("Source: %s" % _tile_summary(world, src))
		lines.append("Destination: %s" % _tile_summary(world, dst))
	# Facing.
	lines.append("Facing: %s (R to rotate)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])
	return lines

static func _tile_summary(world, pos: Vector2i) -> String:
	if not world.has_building_at(pos):
		return "(empty) at %s" % str(pos)
	var b: Building = world.building_at(pos)
	if b == null:
		return "(empty) at %s" % str(pos)
	return "%s at %s" % [Buildings.name_of(b.type), str(pos)]

# ---------- rendering ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var s: int = int(b.state.get("state", STATE_IDLE))
	var dir: int = int(b.state.get("dir", 0))
	var cycle_progress: float = float(b.state.get("cycle_progress", 0.0))

	# Body — bronze tinted by state.
	var tint: Color = Color.WHITE
	match s:
		STATE_IDLE:
			tint = TINT_IDLE
		STATE_NO_FUEL:
			tint = TINT_NO_FUEL
		STATE_NO_POWER:
			# Its OWN entry, not folded into the NO_FUEL arm: the two stalls
			# need different colours. Contrast the arm-angle match below,
			# which EXTENDS its NO_FUEL arm because both stalls park the arm
			# in the same place.
			tint = TINT_NO_POWER
		STATE_BLOCKED_AT_DEST:
			tint = TINT_BLOCKED
	var base: Color = body_color(b)
	var body: Color = Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, 1.0)
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, body, true)
	canvas.draw_rect(rect, BODY_DARK, false, 2.0)

	# Pivot — central circle (the "shoulder" of the arm).
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	canvas.draw_circle(center, float(tile_size) * 0.12, PIVOT_COLOR)
	canvas.draw_arc(center, float(tile_size) * 0.12, 0.0, TAU, 16, BODY_DARK, 1.0)

	# Arm angle. Canonical (dir=E):
	#   IDLE / NO_FUEL / NO_POWER: pointing toward source (180°, west) = PI
	#   WORKING_OUT (cycle_progress 0..0.5): interpolates 180° → 0°
	#   BLOCKED_AT_DEST: pointing toward destination (0°, east) = 0
	#   WORKING_IN (cycle_progress 0.5..1.0): interpolates 0° → 180°
	# Rotation by dir adds dir * 90° (PI/2) to the canonical angle.
	var canonical_angle: float = PI   # default: pointing west (toward source)
	match s:
		STATE_IDLE, STATE_NO_FUEL, STATE_NO_POWER:
			# NO_POWER EXTENDS this arm rather than getting its own: a stalled
			# machine parks its arm at rest, which is what NO_FUEL already
			# does, and an arm frozen halfway through a sweep would read as a
			# rendering bug rather than as a stopped machine. The underlying
			# cycle_progress is untouched by the stall, so the swing resumes
			# from where it left off when power returns.
			canonical_angle = PI
		STATE_WORKING_OUT:
			# 0..0.5 maps to PI..0 (linear).
			canonical_angle = PI - (cycle_progress / 0.5) * PI
		STATE_BLOCKED_AT_DEST:
			canonical_angle = 0.0
		STATE_WORKING_IN:
			# 0.5..1.0 maps to 0..PI (linear).
			canonical_angle = ((cycle_progress - 0.5) / 0.5) * PI
	var dir_offset: float = float(dir) * (PI * 0.5)
	var arm_angle: float = canonical_angle + dir_offset

	# Draw arm — line from pivot to arm tip. Arm length is per-tier
	# (long-reach uses 2x); see ARM_LENGTH_BY_TYPE.
	var arm_len: float = float(tile_size) * arm_length(b)
	var arm_dir: Vector2 = Vector2(cos(arm_angle), sin(arm_angle))
	var arm_tip: Vector2 = center + arm_dir * arm_len
	canvas.draw_line(center, arm_tip, ARM_COLOR, 3.0)
	# Small "hand" circle at the tip.
	canvas.draw_circle(arm_tip, float(tile_size) * 0.08, ARM_COLOR)

	# Held item — circle in item color at arm tip.
	var held: int = held_item_type(b)
	if held >= 0:
		canvas.draw_circle(arm_tip, float(tile_size) * 0.13, Items.color_of(held))
		canvas.draw_arc(arm_tip, float(tile_size) * 0.13, 0.0, TAU, 16, BODY_DARK, 1.0)

	# Direction hint — small triangle on the destination side.
	var dest_v: Vector2i = Belt.DIR_VECS[dir]
	var dest_center: Vector2 = center + Vector2(float(dest_v.x), float(dest_v.y)) * (float(tile_size) * 0.42)
	canvas.draw_circle(dest_center, float(tile_size) * 0.05, BODY_DARK)
