class_name MiningDrill
extends RefCounted

## Burner Mining Drill — automated ore extractor.
##
## 2×2 footprint covering up to 4 ore deposits. Pulls fuel from adjacent
## belts/chests via the generic Burner module. Each ore-production tick:
## drains 1 richness from the highest-richness covered deposit (greedy
## strategy per Q7), produces 1 corresponding ore item into output_buffer,
## consumes fuel via Burner.consume_tick.
##
## Output port: prefer_dir, rotates with building.dir. Default canonical-east.
## Fuel input: any of 4 edges (no fuel prefer_dir for v1).
##
## Stops when:
##   - All covered deposits depleted (STATE_DEPLETED)
##   - Fuel buffer empty (STATE_NO_FUEL — burner only)
##   - Output buffer full and prefer_dir won't accept (STATE_BLOCKED_OUTPUT)
##   - Electric only: network satisfaction <= POWER_EPSILON (STATE_NO_POWER;
##     drill_progress HELD wherever the outage found it, output pushes keep
##     running — see the power gate in tick())
##
## ELECTRIC VARIANT (session-electricity-processors, Task 4): the same state
## machine, parametrised — NOT a second module (duplicating a shipped state
## machine is the #15/#18 drift shape, refused at design time). Every Burner
## call site is gated on is_electric(b); the Burner.make_state() merge in
## make() deliberately STAYS ungated (locked Q4: fuel fields present-but-
## unused on the electric variant — the shape assertion in the test suite
## pins the key set). Speed: electric drills 1 ore per
## ceil(40 × ELECTRIC_SPEED_RATIO) = 32 ticks vs the burner's 40, stretched
## by network satisfaction — see _effective_target.

# Per-ore-tick rate. At 20 sim ticks/sec, 40 ticks = 0.5 ore/sec uniform.
# Slower than manual mining for stone/coal/clay (which is 2/sec) but
# faster than manual iron/copper (1/sec). Tradeoff: drill doesn't need
# player attention. The electric drill upgrades this rate machine-side:
# ceil(40 × 0.8) = 32 — see ELECTRIC_SPEED_RATIO.
const DRILL_TICKS_PER_ORE: int = 40

# Ore produced per fuel unit consumed. Combined with DRILL_TICKS_PER_ORE,
# gives: 1 wood (1 fuel unit) → 8 ore = 16 sec; 1 coal (4 units) → 32 ore = 64 sec.
const DRILL_ORE_PER_FUEL: int = 8

# Output buffer capacity per item type (matches Processor pattern).
const OUTPUT_BUFFER_CAPACITY: int = 16

# State machine values (mirror Processor's IDLE/RUNNING/BLOCKED_OUTPUT plus
# drill-specific NO_FUEL and DEPLETED).
const STATE_IDLE: int = 0          # no work this tick (rare; usually transitions to one of the others)
const STATE_DRILLING: int = 1
const STATE_NO_FUEL: int = 2
const STATE_BLOCKED_OUTPUT: int = 3
const STATE_DEPLETED: int = 4
# APPEND-ONLY from here: the state int round-trips through saves, so the
# values above can never be renumbered. NO_POWER is the ELECTRIC variant's
# stall state (a burner can never reach it), written by the power gate in
# tick() when network satisfaction is at or below POWER_EPSILON. It sits
# AFTER the deposit check on purpose: DEPLETED outranks NO_POWER — the
# deposit being gone is the permanent fact, the outage the transient one.
const STATE_NO_POWER: int = 5

# Visuals
const BODY_COLOR: Color = Color(0.45, 0.40, 0.32)
const BODY_BORDER: Color = Color(0.20, 0.18, 0.14)
const HEAD_COLOR: Color = Color(0.65, 0.55, 0.40)
const NO_FUEL_TINT: Color = Color(1.0, 0.5, 0.5)        # red tint
const BLOCKED_TINT: Color = Color(1.0, 0.95, 0.4)       # yellow tint
const DEPLETED_TINT: Color = Color(0.55, 0.55, 0.55)    # dim gray

const DEFAULT_RECIPE_ID: String = ""   # drill is NOT recipe-driven

# ---------------------------------------------------------------------------
# Electric variant (session-electricity-processors, Task 4).
# ---------------------------------------------------------------------------

# The single source of truth for "is this drill power-driven": is_electric
# is DERIVED from membership, so "draws power" and "is not a burner" cannot
# drift apart — the shipped electric-inserter shape (inserter.gd's table).
#
# 10 units — the electric smelter's own number (2× the electric inserter's
# 5), locked at the design pass: 2 electric smelters + 2 electric drills =
# the Task-6 rig's exact 40. Flagged as the likeliest playtest retune.
#
# The draw is CONSTANT, never duty-cycled — an IDLE electric drill still
# draws its full 10. PowerNetwork.update_supply_demand is a pre-pass that
# runs BEFORE the building tick loop, so any activity state it sampled
# would be one tick stale; gating demand on activity would close a delayed-
# feedback loop (undamped — the network sizing itself to last tick's
# activity) and lamps sharing the component would flicker. See the
# ELECTRIC_DRILL arm in power_network.gd Stage 1.
const POWER_DEMAND_BY_TYPE: Dictionary = {
	Buildings.Type.ELECTRIC_DRILL: 10,
}

# Floor on the satisfaction divisor in _effective_target, AND the NO_POWER
# cutoff (`sat <= POWER_EPSILON` parks the machine). Documented-equal to
# Inserter.POWER_EPSILON and Smelter.POWER_EPSILON: 0.05 is the
# ELECTRIC_LAMP's on/off threshold, so "too dark to bother" and "too weak
# to run" stay the SAME point on the dial across every electric consumer.
# A test literal pins 0.05, so drift from the shared value reddens instead
# of silently re-rating the brownout.
const POWER_EPSILON: float = 0.05

# Electric speed multiplier — the machine-side half of the locked speed
# decision: the electric drill produces 1 ore per ceil(40 × 0.8) = 32
# ticks vs the burner's 40, ratio 0.8. MACHINE-SIDE MULTIPLIER ONLY:
# DRILL_TICKS_PER_ORE stays the burner's rated 40 (the ELECTRIC_DRILL DATA
# row records the same numbers for the next balance pass). If the user
# ever corrects the balance base, only this multiplier moves.
const ELECTRIC_SPEED_RATIO: float = 0.8

## Power units this drill draws from its network per tick. 0 for the
## burner (lookup miss). Read by PowerNetwork.update_supply_demand Stage 1
## to accumulate component demand. Takes the TYPE, not the building: the
## demand is a property of the registry row, and Stage 1's arm has the
## type in hand.
static func power_demand(t: int) -> int:
	return int(POWER_DEMAND_BY_TYPE.get(t, 0))

## True if this drill is power-driven rather than fuel-driven. Derived
## from POWER_DEMAND_BY_TYPE membership on purpose — one source of truth,
## see the table's docstring. Gates every Burner call site in tick() and
## info_lines().
static func is_electric(b: Building) -> bool:
	return POWER_DEMAND_BY_TYPE.has(b.type)

## The tick count drill_progress must reach before an ore is produced —
## the brownout rule (target-stretch, locked at the design pass): int
## drill_progress accumulates 1 per tick, and THIS TARGET is recomputed
## every tick from live satisfaction, so elapsed work is revalued when
## satisfaction changes. No float progress, no rate scaling.
##
##   burner:   DRILL_TICKS_PER_ORE (40), UNCHANGED — returned BEFORE the
##             satisfaction lookup runs. The early return is load-bearing,
##             not a micro-optimisation: a world with no power network
##             reports satisfaction 0.0 everywhere, and a burner that fell
##             through would crawl at the 640-tick floor.
##   electric: ceil(ceil(40 × 0.8) / max(POWER_EPSILON, sat))
##             sat 1.00 → 32    sat 0.50 → 64    sat 0.05 → 640 (the floor)
##
## The form is copied from the shipped inserter/smelter
## (Inserter.effective_cycle_ticks, Smelter._effective_target) — NOT from
## the stale Session-1 formula comments in power_network.gd (Task 7 fixes
## those).
static func _effective_target(b: Building, world) -> int:
	if not is_electric(b):
		return DRILL_TICKS_PER_ORE
	var base_ticks: int = int(ceil(float(DRILL_TICKS_PER_ORE) * ELECTRIC_SPEED_RATIO))
	var sat: float = world.power_satisfaction_at(b.anchor)
	return int(ceil(float(base_ticks) / maxf(POWER_EPSILON, sat)))

## Build initial state. Called from Buildings.make.
##
## covered_deposits is populated at placement time by scanning the footprint
## for ore tiles; persists in state across save/load (deterministic, no
## need to recompute).
##
## NOTE: covered_deposits is filled by mining_drill.refresh_covered_deposits
## after placement (which has access to the world). make() can't see the
## world from here, so we initialize empty and refresh in place_building's
## post-hook.
##
## `b_type` (Electric Processors Task 2, the Inserter.make pattern): the
## ELECTRIC_DRILL dispatch arm passes its own enum so the building dict
## carries the on-disk 38; every existing caller keeps the burner default.
##
## The Burner.make_state() merge below is deliberately UNGATED — for BOTH
## variants (locked Q4: fuel fields present-but-unused on the electric
## variant; the test suite's shape assertion pins the key set, and the
## fuel-sentinel case pins that the fields stay dead).
static func make(pos: Vector2i, dir: int = 0, b_type: int = Buildings.Type.MINING_DRILL) -> Building:
	var state: Dictionary = {
		"dir": dir,
		"drill_progress": 0,
		"output_buffer": [],
		"covered_deposits": [],   # Array of [x, y] — populated by refresh_covered_deposits
		"state": STATE_IDLE,
	}
	# Merge in burner state (fuel_buffer, fuel_burn_progress).
	for k in Burner.make_state().keys():
		state[k] = Burner.make_state()[k]
	return Building.new(b_type, pos, state)

## Scan the building's 2×2 footprint, collect positions of ore tiles into
## `covered_deposits`. Called once at placement. Cached so tick doesn't
## re-scan each frame.
##
## Trees in footprint were rejected at placement (Q9 rule); ore tiles are
## the only resource_node type captured here. Tile.resource_node = NONE
## tiles (grass, depleted-tree-stumps, depleted-ore-stumps) are skipped.
static func refresh_covered_deposits(b: Building, world) -> void:
	var deposits: Array = []
	var fp: Vector2i = Buildings.footprint_of_building(b)
	for dx in fp.x:
		for dy in fp.y:
			var pos: Vector2i = Vector2i(b.anchor.x + dx, b.anchor.y + dy)
			if not world.tiles.has(pos):
				continue
			var t: Tile = world.tiles[pos]
			if ResourceNodes.is_ore(t.resource_node):
				deposits.append([pos.x, pos.y])
	b.state["covered_deposits"] = deposits

## Placement validation: check Q9 rules. Called from main.gd or
## Buildings.can_place_building extension.
##
## `b_type` (Electric Processors Task 2): the rule is shared by both drill
## types — grid_world passes the type being placed so the footprint scan
## follows the right DATA row (both are 2x2 today; the parameter keeps that
## an accident of data rather than a hidden dependency).
##
## Returns "" on valid; otherwise a player-facing error string for toast.
static func validate_placement(world, anchor: Vector2i, b_type: int = Buildings.Type.MINING_DRILL) -> String:
	var fp: Vector2i = Buildings.footprint_of(b_type)
	var has_ore: bool = false
	for dx in fp.x:
		for dy in fp.y:
			var pos: Vector2i = Vector2i(anchor.x + dx, anchor.y + dy)
			if world.tiles.has(pos):
				var t: Tile = world.tiles[pos]
				if t.is_water():
					return "Drill can't extend into water."
				if t.resource_node == ResourceNodes.Type.TREE:
					return "Chop trees from drill area first."
				if ResourceNodes.is_ore(t.resource_node):
					has_ore = true
	if not has_ore:
		return "Drill must cover an ore deposit."
	return ""

## Per-tick logic. Dispatched from Buildings.tick_one — both MINING_DRILL
## and ELECTRIC_DRILL route here; the differences are the `electric` gates
## on the Burner call sites and the power gate between the deposit check
## and the room check.
static func tick(b: Building, world) -> void:
	# The electric variant is not a burner: no fuel slot in DATA, no fuel
	# pull, no fuel commit, and it must never show a fuel state. Every
	# Burner call site below is gated on this one flag (the shipped
	# electric-inserter/smelter pattern).
	var electric: bool = is_electric(b)

	# Step 1: pull fuel (any edge) — burner only. The burner drill has no
	# fuel prefer_dir (try_pull_fuel -1 scans all four edges), so ungated
	# EVERY edge of an electric drill would eat wood passing on a belt —
	# the source-tile-as-fuel bug times four.
	if not electric:
		Burner.try_pull_fuel(b, world, -1)

	# Step 2: try to push existing output buffer (might unblock from prior tick).
	_try_push_outputs(b, world)

	# Step 3: pick the best deposit (highest richness, deterministic tiebreak).
	# This runs BEFORE the power gate on purpose (locked precedence, Task
	# 4): DEPLETED outranks NO_POWER — the deposit being gone is the
	# permanent fact, the outage the transient one. A drill that flipped to
	# NO_POWER here would tell the player to fix their grid to revive a
	# hole in the ground.
	var target: Vector2i = _pick_best_deposit(b, world)
	if target == Vector2i(2147483647, 2147483647):
		b.state["state"] = STATE_DEPLETED
		return

	# Step 3b (electric only): the POWER GATE. At or below POWER_EPSILON —
	# `<=`, the exact comparison the electric inserter, the electric
	# smelter and the lamp's glow share — the machine PARKS: drill_progress
	# is HELD exactly where the outage found it (mid-accumulation,
	# wherever it stands — unlike burner NO_FUEL, which only ever parks AT
	# the threshold, because fuel is committed at production time while
	# power is a precondition for every accumulation tick). The park is a
	# state label plus a return and NOTHING else: steps 1-3 above keep
	# running, so output pushes continue through the outage (locked stall
	# scope, mirroring burner NO_FUEL's minimal diff).
	#
	# RESUME (power back while parked) needs no arm of its own: the gate
	# simply stops firing and step 5 below continues accumulating from the
	# held drill_progress toward the live effective target, consuming
	# nothing — the drill has no commit step to re-enter, so there is no
	# reset-and-double-consume hazard here; the wall-clock completion
	# identity in the test suite pins the resume anyway.
	if electric and world.power_satisfaction_at(b.anchor) <= POWER_EPSILON:
		b.state["state"] = STATE_NO_POWER
		return

	# Step 4: decide if we can drill this tick.
	# Output capacity check: would the produced ore fit?
	var ore_type: int = world.tiles[target].resource_node
	var item_type: int = int(_RESOURCE_TO_ITEM[ore_type])
	if not _output_has_room(b, item_type):
		b.state["state"] = STATE_BLOCKED_OUTPUT
		return

	# Step 5: advance drill progress.
	# EFFECTIVE, not rated: recomputed every tick from live satisfaction
	# for the electric variant (target-stretch), the rated
	# DRILL_TICKS_PER_ORE unchanged for the burner.
	var progress: int = int(b.state.get("drill_progress", 0)) + 1
	if progress < _effective_target(b, world):
		b.state["drill_progress"] = progress
		b.state["state"] = STATE_DRILLING
		return

	# Step 6: full ore production tick. Consume fuel + drain richness + produce ore.
	# Burner: the fuel commit happens HERE, at production time (the
	# structural difference from the smelter, which commits at cycle
	# start). Electric: the commit is free — its cost is the CONSTANT
	# network demand, already registered by the pre-pass, never a
	# per-ore debit (the fuel-sentinel test pins that consume_tick is
	# never even called), so production is unconditional on fuel.
	var fuel_ok: bool = true
	if not electric:
		fuel_ok = Burner.consume_tick(b, DRILL_ORE_PER_FUEL)
	if not fuel_ok and not electric:
		# `and not electric`, not a bare `if not fuel_ok`: NO_FUEL and its
		# park-at-threshold are burner-only — an electric machine must
		# never show 2, and only NO_POWER may park it (mid-accumulation,
		# not at the threshold). With the commit gate above intact this
		# extra guard is unreachable for the electric variant; it exists
		# so a future edit that breaks that gate cannot ALSO park an
		# electric machine in a fuel state it has no way to leave.
		# No fuel — keep progress at threshold; will produce as soon as fuel arrives.
		b.state["drill_progress"] = DRILL_TICKS_PER_ORE
		b.state["state"] = STATE_NO_FUEL
		return

	# Drill the deposit.
	world.deplete_resource(target, 1)
	# Append to output buffer.
	_append_output(b, item_type, 1)
	# Reset drill timer.
	b.state["drill_progress"] = 0
	b.state["state"] = STATE_DRILLING

	# If the deposit just depleted, refresh covered list (the depleted tile
	# is now grass; tile.resource_node = NONE, so it'll be filtered next pick).
	# Actually no refresh needed — _pick_best_deposit re-checks each tick.
	# covered_deposits cache stays stable; we filter via richness_at(pos) > 0.

	# Try push immediately so the buffer doesn't stay full.
	_try_push_outputs(b, world)

# ---------- helpers ----------

# Resource_node → item type produced when drilled.
const _RESOURCE_TO_ITEM: Dictionary = {
	ResourceNodes.Type.STONE:  Items.Type.RAW_STONE,
	ResourceNodes.Type.COAL:   Items.Type.COAL,
	ResourceNodes.Type.IRON:   Items.Type.IRON_ORE,
	ResourceNodes.Type.COPPER: Items.Type.COPPER_ORE,
	ResourceNodes.Type.CLAY:   Items.Type.CLAY,
}

const _MAX_VECTOR2I: Vector2i = Vector2i(2147483647, 2147483647)

## Pick the highest-richness deposit covered by this drill. Tiebreak:
## topmost-leftmost (sort by y, then x). Returns _MAX_VECTOR2I if all
## covered deposits are depleted.
static func _pick_best_deposit(b: Building, world) -> Vector2i:
	var best: Vector2i = _MAX_VECTOR2I
	var best_richness: int = 0
	for entry in b.state.get("covered_deposits", []):
		var pos: Vector2i = Vector2i(int(entry[0]), int(entry[1]))
		var r: int = world.richness_at(pos)
		if r <= 0:
			continue
		if r > best_richness:
			best = pos
			best_richness = r
		elif r == best_richness:
			# Tiebreak: topmost-leftmost (smaller y, then smaller x).
			if pos.y < best.y or (pos.y == best.y and pos.x < best.x):
				best = pos
	return best

## Return true if `item_type` can fit in the output buffer (count < CAPACITY
## for that item type, OR the item type isn't present yet).
static func _output_has_room(b: Building, item_type: int) -> bool:
	var buf: Array = b.state.get("output_buffer", [])
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1]) < OUTPUT_BUFFER_CAPACITY
	# Item type not yet in buffer; slot will be created on append.
	return true

## Add `count` of `item_type` to the output buffer.
static func _append_output(b: Building, item_type: int, count: int) -> void:
	var buf: Array = b.state.get("output_buffer", [])
	for entry in buf:
		if int(entry[0]) == item_type:
			entry[1] = int(entry[1]) + count
			return
	buf.append([item_type, count])

## Try to push items from the output buffer to adjacent belt/chest in the
## building's prefer_dir output direction. Pushes 1 item per tick (matches
## Processor pattern).
static func _try_push_outputs(b: Building, world) -> void:
	var buf: Array = b.state.get("output_buffer", [])
	if buf.is_empty():
		return
	var b_dir: int = int(b.state.get("dir", 0))
	# Default output direction: canonical East, rotated by b.dir.
	var output_dir: int = (Belt.DIR_E + b_dir) % 4
	# Try each entry in the buffer.
	for entry in buf:
		var item_type: int = int(entry[0])
		var count: int = int(entry[1])
		if count <= 0:
			continue
		for cell in Buildings.edge_cells(b.type, b.anchor, output_dir, Buildings.dir_of(b)):
			if _try_push_to(world, cell, item_type):
				entry[1] = count - 1
				if int(entry[1]) <= 0:
					buf.erase(entry)
				return   # 1 item pushed per tick
	# Nothing pushed — caller's state machine handles BLOCKED_OUTPUT.

## Try to push one item to a cell. Returns true on success.
static func _try_push_to(world, cell: Vector2i, item_type: int) -> bool:
	var dest: Building = world.building_at(cell)
	if dest == null:
		return false
	if dest.type == Buildings.Type.BELT:
		return Belt.try_insert(dest, item_type)
	if dest.type == Buildings.Type.CHEST:
		return Chest.try_insert(dest, item_type, 1)
	return false

# ---------- Q-inspect / info_lines ----------

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	# State line — most prominent.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var status: String = "(idle)"
	match s:
		STATE_DRILLING:
			status = "Drilling"
		STATE_NO_FUEL:
			status = "NO FUEL"
		STATE_BLOCKED_OUTPUT:
			status = "Output blocked"
		STATE_DEPLETED:
			status = "Depleted"
		STATE_NO_POWER:
			# Electric only. Without this arm a parked machine would fall
			# through to "(idle)" — the exact lie the inserter panel work
			# exists to prevent (the panels' own arms are Task 5).
			status = "NO POWER"
	lines.append("Status: %s" % status)

	# Currently producing — Q11 prominent line. Reflects highest-richness
	# pick at this instant; changes over time as deposits drain.
	if s == STATE_DRILLING or s == STATE_BLOCKED_OUTPUT:
		var target: Vector2i = _pick_best_deposit(b, world)
		if target != _MAX_VECTOR2I:
			var ore_type: int = world.tiles[target].resource_node
			var item_type: int = int(_RESOURCE_TO_ITEM[ore_type])
			lines.append("Currently producing: %s" % Items.name_of(item_type))

	# Fuel from Burner — burner only: the electric variant's deliberately-
	# kept-but-dead fuel fields would otherwise render as a live fuel gauge
	# (and a spurious "NO FUEL" hint) on a machine with no fuel path.
	if not is_electric(b):
		for line in Burner.info_lines(b):
			lines.append(line)

	# Output buffer.
	var buf: Array = b.state.get("output_buffer", [])
	if buf.is_empty():
		lines.append("Output: (empty)")
	else:
		for entry in buf:
			lines.append("Output: %d %s" % [int(entry[1]), Items.name_of(int(entry[0]))])

	# Covered deposits sorted by richness desc.
	var deposits_with_richness: Array = []
	for entry in b.state.get("covered_deposits", []):
		var pos: Vector2i = Vector2i(int(entry[0]), int(entry[1]))
		var r: int = world.richness_at(pos)
		if r > 0:
			deposits_with_richness.append([pos, r])
	deposits_with_richness.sort_custom(func(a, b_): return int(a[1]) > int(b_[1]))
	if deposits_with_richness.is_empty():
		lines.append("Coverage: all depleted")
	else:
		for entry in deposits_with_richness:
			var p: Vector2i = entry[0]
			var ore_t: int = world.tiles[p].resource_node
			lines.append("  %s @ (%d, %d): %d" % [ResourceNodes.name_of(ore_t), p.x, p.y, int(entry[1])])

	# Facing.
	lines.append("Facing: %s (R to rotate before placing)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])

	return lines

# ---------- rendering ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# 2×2 footprint: cover the full 64×64 area centered at world_pos.
	var fp: Vector2i = Buildings.footprint_of_building(b)
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size * fp.x, tile_size * fp.y))
	# Body color tinted by state.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var tint: Color = Color(1, 1, 1, 1)
	match s:
		STATE_NO_FUEL:
			tint = NO_FUEL_TINT
		STATE_BLOCKED_OUTPUT:
			tint = BLOCKED_TINT
		STATE_DEPLETED:
			tint = DEPLETED_TINT
	var body_color: Color = Color(BODY_COLOR.r * tint.r, BODY_COLOR.g * tint.g, BODY_COLOR.b * tint.b, 1.0)
	canvas.draw_rect(rect, body_color, true)
	canvas.draw_rect(rect, BODY_BORDER, false, 2.0)
	# Drill head: smaller centered square.
	var head_size: float = float(tile_size) * 0.6
	var head_rect: Rect2 = Rect2(
		world_pos + Vector2((tile_size * fp.x - head_size) * 0.5, (tile_size * fp.y - head_size) * 0.5),
		Vector2(head_size, head_size),
	)
	var head_color: Color = Color(HEAD_COLOR.r * tint.r, HEAD_COLOR.g * tint.g, HEAD_COLOR.b * tint.b, 1.0)
	canvas.draw_rect(head_rect, head_color, true)
	canvas.draw_rect(head_rect, BODY_BORDER, false, 1.5)
