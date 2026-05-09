class_name Inserter
extends RefCounted

## Inserter — connective tissue of the factory (session-inserter-foundation,
## Inserter Arc Session 1 of N).
##
## Picks up an item from the source tile (one cell behind the inserter,
## opposite of `dir`), swings the arm to the destination tile (one cell
## ahead, in `dir`), drops the item, swings back. Universal source/dest:
## belts, chests, and recipe-driven processor I/O ports.
##
## Fuel-powered via Burner module (3rd consumer after Smelter + Mining
## Drill). Cycle speed is FIXED at 1.0 second per pickup-and-deliver
## cycle — fuel tier (wood / coal / briquette) determines fuel ECONOMY
## (how often you need to refill), NOT speed. Reversal #7 from PAUSE 1:
## tying speed to fuel tier conflated two orthogonal axes (energy density
## and machine throughput) and made the basic inserter feel inconsistent.
## Future inserter variants (Fast Inserter, Stack Inserter) will get
## faster cycles via separate building types, not via fuel.
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
##
## Future variants (filter / multi-filter / long-reach / fast / stack)
## reuse this animation system parametrically (ARM_LENGTH, CYCLE_TICKS,
## source/dest offset).

# State machine values.
const STATE_IDLE: int            = 0
const STATE_WORKING_OUT: int     = 1
const STATE_BLOCKED_AT_DEST: int = 2
const STATE_WORKING_IN: int      = 3
const STATE_NO_FUEL: int         = 4

# Fixed cycle duration. 20 ticks @ 20 TPS = 1.0 second per full cycle
# (pickup + swing-out + drop + swing-back). Chosen to feel snappier than
# Factorio's basic inserter (0.83s effective) but still clearly slower
# than future Fast Inserter variants. Independent of fuel tier.
const CYCLE_TICKS: int = 20

# Animation parameters. ARM_LENGTH is per-variant — future LONG_INSERTER
# would override to ~1.2 (extends beyond adjacent tile).
const ARM_LENGTH: float = 0.55       # fraction of tile_size

# Visuals.
const BODY_COLOR: Color = Color(0.55, 0.45, 0.30)
const BODY_DARK: Color = Color(0.18, 0.13, 0.08)
const ARM_COLOR: Color = Color(0.20, 0.16, 0.10)
const PIVOT_COLOR: Color = Color(0.30, 0.25, 0.18)
const TINT_IDLE: Color = Color(0.60, 0.60, 0.60)        # dim when idle / no_fuel
const TINT_NO_FUEL: Color = Color(0.55, 0.55, 0.85)     # cool blue tint
const TINT_BLOCKED: Color = Color(1.0, 0.95, 0.40)      # yellow when blocked

## Build initial state. dir defaults to canonical east (DIR_E = 0).
## Cycle speed is fixed (CYCLE_TICKS) regardless of fuel tier — see
## file-level docstring for the reversal rationale.
static func make(pos: Vector2i, dir: int = 0) -> Building:
	var state: Dictionary = {
		"dir": dir,
		"held_item_buffer": [],          # [[item_type, count]]; count ∈ {0, 1}
		"cycle_progress": 0.0,
		"state": STATE_IDLE,
	}
	for k in Burner.make_state().keys():
		state[k] = Burner.make_state()[k]
	return Building.new(Buildings.Type.INSERTER, pos, state)

## Tick logic. Dispatched from Buildings.tick_one.
##
## Order of operations:
##   1. Try to refuel if buffer empty.
##   2. If no fuel after refuel attempt → STATE_NO_FUEL, return.
##   3. Run state machine based on current state.
static func tick(b: Building, world) -> void:
	# (1 + 2) Fuel check + pull.
	var fuel_units: int = int(b.state.get("fuel_buffer", 0))
	if fuel_units <= 0:
		if not Burner.try_pull_fuel(b, world, -1):
			b.state["state"] = STATE_NO_FUEL
			return
	# (3) State machine.
	var s: int = int(b.state.get("state", STATE_IDLE))
	# Per-tick cycle increment. One full cycle (0→1) spans CYCLE_TICKS
	# ticks; each half-cycle (swing-out OR swing-in) is CYCLE_TICKS/2 ticks.
	var inc: float = 1.0 / float(CYCLE_TICKS)

	match s:
		STATE_IDLE, STATE_NO_FUEL:
			# Try to start a new cycle: source has item AND destination accepts.
			var picked: int = _try_pickup(b, world)
			if picked >= 0:
				_set_held(b, picked)
				b.state["cycle_progress"] = 0.0
				b.state["state"] = STATE_WORKING_OUT
				# Consume one fuel-burn tick this cycle.
				Burner.consume_tick(b, CYCLE_TICKS)
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
			Burner.consume_tick(b, CYCLE_TICKS)
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
			Burner.consume_tick(b, CYCLE_TICKS)

# ---------- helpers ----------

## Source tile = anchor + opposite-of-dir. dir=E → source is west.
static func source_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	return Vector2i(b.anchor.x - v.x, b.anchor.y - v.y)

## Destination tile = anchor + dir. dir=E → destination is east.
static func dest_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	return Vector2i(b.anchor.x + v.x, b.anchor.y + v.y)

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
## Source priority by building type:
##   BELT  → take item from the slot facing the inserter (the slot
##           closest to the inserter, the one that would otherwise be
##           handed off NEXT toward the inserter direction).
##   CHEST → take any item (FIFO — first non-empty bag entry).
##   Recipe-driven Processor → take from out_buffer (FIFO).
##   Otherwise: no-op.
static func _try_pickup(b: Building, world) -> int:
	var src: Vector2i = source_tile(b)
	if not world.has_building_at(src):
		return -1
	var src_b: Building = world.building_at(src)
	if src_b == null:
		return -1
	# Belt: pull from the slot facing the inserter.
	if src_b.type == Buildings.Type.BELT:
		return _pickup_from_belt(b, src_b)
	# Chest: FIFO from bag.
	if src_b.type == Buildings.Type.CHEST:
		return _pickup_from_chest(src_b)
	# Recipe-driven Processor: pull from out_buffer (FIFO).
	if _is_processor_with_output(src_b):
		return _pickup_from_processor(src_b)
	return -1

static func _pickup_from_belt(b: Building, belt: Building) -> int:
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
	slots[slot_idx] = -1
	return item_t

static func _pickup_from_chest(chest: Building) -> int:
	var bag: Array = chest.state.get("bag", [])
	for entry in bag:
		var item_t: int = int(entry[0])
		var count: int = int(entry[1])
		if count <= 0:
			continue
		entry[1] = count - 1
		if int(entry[1]) <= 0:
			bag.erase(entry)
		return item_t
	return -1

static func _pickup_from_processor(src: Building) -> int:
	# Pull from out_buffer (FIFO). Mirrors the buffer-remove pattern from
	# Processor / FertilizerApplicator.
	var out_buf: Array = src.state.get("out_buffer", [])
	for entry in out_buf:
		var item_t: int = int(entry[0])
		var count: int = int(entry[1])
		if count <= 0:
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
	lines.append("Cycle: %.0f%% (%.1fs per cycle)" % [cycle_progress * 100.0, float(CYCLE_TICKS) / 20.0])
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
	var body_color: Color = Color(BODY_COLOR.r * tint.r, BODY_COLOR.g * tint.g, BODY_COLOR.b * tint.b, 1.0)
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, body_color, true)
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

	# Draw arm — line from pivot to arm tip.
	var arm_len: float = float(tile_size) * ARM_LENGTH
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
