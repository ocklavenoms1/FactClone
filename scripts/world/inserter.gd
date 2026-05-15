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
## Fuel-powered via Burner module. Cycle speed is FIXED per tier — fuel
## tier (wood / coal / briquette) determines fuel ECONOMY (how often you
## need to refill), NOT speed. Reversal #7 from session-inserter-
## foundation PAUSE 1: tying speed to fuel tier conflated two orthogonal
## axes. Throughput upgrades come via building TYPE (basic → fast →
## electric), not via fuel choice.
##
## State machine (5 phases):
##   IDLE              — arm at rest (source side); waiting for source/dest/fuel
##   WORKING_OUT       — arm interpolating source → destination, holding item
##   BLOCKED_AT_DEST   — arm at destination, holding item, drop blocked
##   WORKING_IN        — arm interpolating destination → source, returning empty
##   NO_FUEL           — like IDLE but explicit "out of fuel"
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

# Per-tier cycle duration (ticks @ 20 TPS). Add a row when a new inserter
# tier ships; tick logic reads via `cycle_ticks(b)` lookup. Default
# fallback (lookup miss) = 20, matching the basic tier.
#   INSERTER:      20 ticks = 1.0s — basic (Session 1)
#   FAST_INSERTER: row added at session-inserter-fast-filter (Session 2)
const CYCLE_TICKS_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             20,    # 1.0s — basic
	Buildings.Type.FAST_INSERTER:        10,    # 0.5s — twice as fast
	Buildings.Type.LONG_REACH_INSERTER:  30,    # 1.5s — slower, balances reach
}
const CYCLE_TICKS_DEFAULT: int = 20

# Per-tier body color. New tiers add an entry; default fallback is bronze
# (basic). Pattern mirrored in CYCLE_TICKS_BY_TYPE, REACH_BY_TYPE, and
# ARM_LENGTH_BY_TYPE below.
#   INSERTER:            bronze (basic — Session 1)
#   FAST_INSERTER:       row added at session-inserter-fast-filter (Session 2)
#   LONG_REACH_INSERTER: row added at session-inserter-long-reach (Session 3)
const BODY_COLOR_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             Color(0.55, 0.45, 0.30),    # bronze
	Buildings.Type.FAST_INSERTER:        Color(0.45, 0.55, 0.70),    # cool blue-grey
	Buildings.Type.LONG_REACH_INSERTER:  Color(0.65, 0.30, 0.22),    # rust-red — "reach" tier
}
const BODY_COLOR_DEFAULT: Color = Color(0.55, 0.45, 0.30)

# Per-tier reach (in tiles). Source = anchor - reach*DIR_VECS[dir]; dest =
# anchor + reach*DIR_VECS[dir]. New table introduced at session-inserter-
# long-reach to support reach as an orthogonal upgrade axis from speed.
# Default fallback = 1 (basic-equivalent — preserves existing tier behavior).
#   INSERTER:             1 — basic (Session 1)
#   FAST_INSERTER:        1 — fast (Session 2)
#   LONG_REACH_INSERTER:  added at session-inserter-long-reach (Session 3)
const REACH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             1,
	Buildings.Type.FAST_INSERTER:        1,
	Buildings.Type.LONG_REACH_INSERTER:  2,
}
const REACH_DEFAULT: int = 1

# Per-tier arm length (fraction of tile_size). REFACTORED from a single
# `const ARM_LENGTH = 0.55` at session-inserter-long-reach — long-reach
# tier needs a longer arm visual, so the param becomes per-type. Baseline
# 0.55 preserved for INSERTER / FAST_INSERTER (pure additive change).
#   INSERTER:             0.55 — basic
#   FAST_INSERTER:        0.55 — fast (visually identical to basic)
#   LONG_REACH_INSERTER:  added at session-inserter-long-reach (Session 3)
const ARM_LENGTH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:             0.55,
	Buildings.Type.FAST_INSERTER:        0.55,
	Buildings.Type.LONG_REACH_INSERTER:  1.10,    # 2x — visually communicates reach
}
const ARM_LENGTH_DEFAULT: float = 0.55

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
## cycle_ticks(b) lookup.
##
## Order of operations:
##   1. Try to refuel if buffer empty.
##   2. If no fuel after refuel attempt → STATE_NO_FUEL, return.
##   3. Run state machine based on current state.
static func tick(b: Building, world) -> void:
	# (1 + 2) Fuel check + pull. Restricted to FUEL_PORT_DIR (rotated by
	# building dir) — see constant docstring for the source-tile-as-fuel
	# bug rationale (caught at session-inserter-fast-filter PAUSE 1).
	var fuel_units: int = int(b.state.get("fuel_buffer", 0))
	if fuel_units <= 0:
		if not Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR)):
			b.state["state"] = STATE_NO_FUEL
			return
	# (3) State machine.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var ticks: int = cycle_ticks(b)
	# Per-tick cycle increment. One full cycle (0→1) spans `ticks` ticks;
	# each half-cycle (swing-out OR swing-in) is ticks/2 ticks.
	var inc: float = 1.0 / float(ticks)

	match s:
		STATE_IDLE, STATE_NO_FUEL:
			# Try to start a new cycle: source has item AND destination accepts.
			var picked: int = _try_pickup(b, world)
			if picked >= 0:
				_set_held(b, picked)
				b.state["cycle_progress"] = 0.0
				b.state["state"] = STATE_WORKING_OUT
				# Consume one fuel-burn tick this cycle.
				Burner.consume_tick(b, ticks)
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
	lines.append("Status: %s" % status)
	# Held item.
	var held: int = held_item_type(b)
	if held >= 0:
		lines.append("Holding: %s" % Items.name_of(held))
	# Cycle.
	var cycle_progress: float = float(b.state.get("cycle_progress", 0.0))
	lines.append("Cycle: %.0f%% (%.1fs per cycle)" % [cycle_progress * 100.0, float(cycle_ticks(b)) / 20.0])
	# Filter (fast/electric tier only — basic doesn't surface this line).
	if b.type == Buildings.Type.FAST_INSERTER:
		var filter: int = int(b.state.get("filter_item_type", -1))
		if filter >= 0:
			lines.append("Filter: %s" % Items.name_of(filter))
		else:
			lines.append("Filter: (none — picks any item)")
	# Burner fuel display.
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
	#   IDLE / NO_FUEL: pointing toward source (180°, west) = PI radians
	#   WORKING_OUT (cycle_progress 0..0.5): interpolates 180° → 0°
	#   BLOCKED_AT_DEST: pointing toward destination (0°, east) = 0
	#   WORKING_IN (cycle_progress 0.5..1.0): interpolates 0° → 180°
	# Rotation by dir adds dir * 90° (PI/2) to the canonical angle.
	var canonical_angle: float = PI   # default: pointing west (toward source)
	match s:
		STATE_IDLE, STATE_NO_FUEL:
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
