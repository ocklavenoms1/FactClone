class_name FertilizerApplicator
extends RefCounted

## Fertilizer Applicator — automation tier for the fertilizer chain
## (session-soil-exhaustion-3-5).
##
## 1×1 footprint, 5×5 coverage area centered on anchor. Pulls COMPOST_LOW
## or COMPOST_MID from belts at the input port (canonical W edge, rotates
## with b.dir), or accepts drag-drop into the input slot. Once per
## APPLY_INTERVAL_TICKS, scans the 5×5 area for the most-depleted eligible
## tile and applies one fertilizer item via GridWorld.try_apply_fertilizer
## — same call hand-apply uses, same stacking rules.
##
## Pre-cut from session-soil-exhaustion-3 per the manual-before-automation
## pattern (third instance: mining-manual → mining-drill, soil-3 hand-apply
## → soil-3.5 automation).
##
## Architectural note: applicator does NOT use Processor.tick. There's no
## recipe — no recipe-driven I/O, no progress timer matched to recipe
## time_ticks. Custom tick mirrors MiningDrill's structure (its own state
## machine + bespoke pull/apply logic).
##
## tile_fertilizer_state is the single source of truth (defined in
## GridWorld at session-soil-exhaustion-3). Applicator reads via
## tile_fertilizer_tier(pos) and writes via try_apply_fertilizer(pos,
## tier). No new state, no duplicated logic.

# Rate limit: one application per 100 ticks = 5 sec at 20 tps.
# At 25 tiles in coverage: 125 sec to fertilize all from scratch (matches
# rotation maintenance, not fast-recovery). Player who needs fast recovery
# uses hand-apply (Session 3) or multiple applicators.
const APPLY_INTERVAL_TICKS: int = 100

# 5×5 coverage area around anchor — Chebyshev distance ≤ 2 (radius 2).
const COVERAGE_RADIUS: int = 2

# Input port direction (canonical orientation; rotates with b.dir).
# Rotates per Buildings.world_dir(b, INPUT_PORT_DIR).
const INPUT_PORT_DIR: int = Belt.DIR_W

# Per-input-pull rate. Like Processor: 1 item/tick max, prevents flood
# from a packed belt. The rate-limited application (every 100 ticks)
# means even a tightly-packed belt won't overflow the 16-stack buffer
# — applicator burns 1 item per 100 ticks, belt feeds at most 1 per tick.
const INPUT_BUFFER_CAPACITY: int = 16

# State machine values. APPLYING is collapsed into a single-tick
# transition (apply happens, state goes back to SCANNING).
const STATE_IDLE: int     = 0    # no input fertilizer
const STATE_SCANNING: int = 1    # has input; counting toward next apply
const STATE_BLOCKED: int  = 2    # has input; threshold reached, no eligible tiles

# Sentinel for "no eligible tile found" — large negative so it never
# collides with real tile coords (world bounds are ±256).
const _NO_TARGET: Vector2i = Vector2i(-99999, -99999)

# Visuals — sprinkler aesthetic. State tints multiplied with body color.
const BODY_COLOR: Color = Color(0.55, 0.70, 0.55)        # sage green
const BODY_BORDER: Color = Color(0.20, 0.30, 0.20)
const NOZZLE_COLOR: Color = Color(0.35, 0.55, 0.35)
const TINT_IDLE: Color = Color(0.55, 0.55, 0.55)         # dim gray when no input
const TINT_BLOCKED: Color = Color(1.0, 0.95, 0.4)        # yellow when blocked
const TINT_NORMAL: Color = Color(1.0, 1.0, 1.0)

## Build initial state. Called from Buildings.make.
static func make(pos: Vector2i, dir: int = 0) -> Building:
	return Building.new(Buildings.Type.FERTILIZER_APPLICATOR, pos, {
		"in_buffer": [],
		"scan_progress": 0,
		"dir": dir,
		"state": STATE_IDLE,
	})

## Per-tick logic. Dispatched from Buildings.tick_one.
##
## Order of operations:
##   1. Pull 1 fertilizer from input port (rate-limited, like Processor).
##   2. Update state based on whether buffer has anything.
##   3. Advance scan_progress (skip if BLOCKED — see below).
##   4. If at threshold (or BLOCKED): try apply.
##
## BLOCKED handling (per design pushback): when BLOCKED, scan_progress
## stays at threshold — re-checks eligibility every tick. As soon as a
## tile becomes eligible (e.g. player just hand-applied to a different
## tile, or a planter just depleted a fresh tile), applicator fires
## immediately. Avoids the "Next apply" UI jumping backwards from 5.0s
## to 1.0s when entering BLOCKED.
static func tick(b: Building, world) -> void:
	# (1) Pull fertilizer from input port. 1/tick max.
	_try_pull_input(b, world)

	# (2) State based on buffer content. If nothing to apply, stay IDLE.
	var has_input: bool = _buffer_total(b.state.get("in_buffer", [])) > 0
	if not has_input:
		b.state["state"] = STATE_IDLE
		# Don't advance scan_progress while IDLE — preserves whatever
		# countdown was in flight when input ran out, so refilling resumes
		# without artificial delay (player-friendly).
		return

	# (3) Has input. Advance scan_progress UNLESS already at threshold
	# (i.e. SCANNING just hit threshold last tick, or we're sitting in
	# BLOCKED). The threshold gate below handles both cases identically.
	var scan_progress: int = int(b.state.get("scan_progress", 0))
	if scan_progress < APPLY_INTERVAL_TICKS:
		scan_progress += 1
		b.state["scan_progress"] = scan_progress
		b.state["state"] = STATE_SCANNING
		# Below threshold: nothing more to do this tick.
		if scan_progress < APPLY_INTERVAL_TICKS:
			return

	# (4) At threshold — try to apply.
	var selected_tier: int = _select_fertilizer_from_buffer(b)
	# Defensive: has_input said true but tier selection failed — would
	# only happen if buffer entries had count <= 0 (corruption). Treat
	# as IDLE.
	if selected_tier < 0:
		b.state["state"] = STATE_IDLE
		return

	var target: Vector2i = _pick_most_depleted_eligible_tile(b, world, selected_tier)
	if target == _NO_TARGET:
		# No eligible tiles in coverage. Hold scan_progress at threshold
		# and re-poll next tick. UI shows "BLOCKED" instead of countdown.
		b.state["state"] = STATE_BLOCKED
		return

	# Apply. try_apply_fertilizer returns false only on lower-tier-rejected,
	# which _pick_most_depleted_eligible_tile already filters — so the
	# `false` branch is defensive (treat as BLOCKED if it ever fires).
	if world.try_apply_fertilizer(target, selected_tier):
		_buffer_remove(b.state["in_buffer"], selected_tier, 1)
		b.state["scan_progress"] = 0
		b.state["state"] = STATE_SCANNING
	else:
		b.state["state"] = STATE_BLOCKED

# ---------- input pull ----------

## Pull 1 fertilizer item from the input port (canonical W, rotated by
## b.dir). Mirrors Processor._try_pull_from_cell pattern but inlined
## because applicator has no recipe — accepts list is a fixed const.
static func _try_pull_input(b: Building, world) -> void:
	# Capacity check — don't overfill the buffer.
	if _buffer_total(b.state.get("in_buffer", [])) >= INPUT_BUFFER_CAPACITY:
		return
	var input_dir: int = Buildings.world_dir(b, INPUT_PORT_DIR)
	for cell in Buildings.edge_cells(Buildings.Type.FERTILIZER_APPLICATOR, b.anchor, input_dir):
		if not world.has_building_at(cell):
			continue
		var neighbor: Building = world.building_at(cell)
		if neighbor == null or neighbor.type != Buildings.Type.BELT:
			continue
		var pulled: int = Belt.try_pull_matching(neighbor, b.anchor,
			[Items.Type.COMPOST_LOW, Items.Type.COMPOST_MID])
		if pulled >= 0:
			_buffer_add(b.state["in_buffer"], pulled, 1)
			return  # 1 pull per tick

# ---------- tier + tile selection ----------

## Select highest-tier fertilizer in buffer (MID before LOW). Two-pass
## because the buffer is short (≤2 entries — only 2 valid item types).
## Returns -1 if buffer empty or all entries have count <= 0.
##
## Static + pure: tests call directly.
static func _select_fertilizer_from_buffer(b: Building) -> int:
	var buf: Array = b.state.get("in_buffer", [])
	# Pass 1: prefer MID.
	for entry in buf:
		if int(entry[1]) > 0 and int(entry[0]) == Items.Type.COMPOST_MID:
			return Items.Type.COMPOST_MID
	# Pass 2: fall back to LOW.
	for entry in buf:
		if int(entry[1]) > 0 and int(entry[0]) == Items.Type.COMPOST_LOW:
			return Items.Type.COMPOST_LOW
	return -1

## Find the most-depleted eligible tile in the 5×5 coverage area for the
## given fertilizer tier. Returns _NO_TARGET if no eligible tiles.
##
## Eligibility:
##   - tile soil < 100 (depleted)
##   - tile fertilizer tier < selected_tier OR no fertilizer present
##     (i.e., applying selected_tier would actually upgrade or freshly
##      apply — same rule as hand-apply Q5 stacking, enforced upstream
##      by try_apply_fertilizer)
##
## Tile sort: lowest soil_health first. Tiebreak: topmost-leftmost
## (smaller y, then smaller x) — mirrors MiningDrill's deterministic
## tiebreak. Static + pure: tests call directly.
##
## Edge-of-world: out-of-bounds tiles are silently dropped. Applicator
## near the world edge scans only the in-bounds subset of its 5×5.
static func _pick_most_depleted_eligible_tile(b: Building, world, selected_tier: int) -> Vector2i:
	var best: Vector2i = _NO_TARGET
	var best_soil: int = 101   # higher than max so first match wins
	for dx in range(-COVERAGE_RADIUS, COVERAGE_RADIUS + 1):
		for dy in range(-COVERAGE_RADIUS, COVERAGE_RADIUS + 1):
			var pos: Vector2i = Vector2i(b.anchor.x + dx, b.anchor.y + dy)
			# In-world bounds: WORLD_MIN ≤ pos < WORLD_MAX (per WorldGenerator).
			if pos.x < WorldGenerator.WORLD_MIN or pos.x >= WorldGenerator.WORLD_MAX:
				continue
			if pos.y < WorldGenerator.WORLD_MIN or pos.y >= WorldGenerator.WORLD_MAX:
				continue
			# Eligibility check.
			var soil: int = world.tile_soil_health(pos)
			if soil >= GridWorld.TILE_SOIL_FULL:
				continue   # pristine — no benefit from fertilizer
			var current_tier: int = world.tile_fertilizer_tier(pos)
			if current_tier >= selected_tier:
				continue   # already has equal-or-better fertilizer
			# Eligible. Track most-depleted (smallest soil); tiebreak
			# topmost-leftmost.
			if soil < best_soil:
				best = pos
				best_soil = soil
			elif soil == best_soil:
				if pos.y < best.y or (pos.y == best.y and pos.x < best.x):
					best = pos
	return best

# ---------- buffer helpers (mirror Processor's pattern) ----------

static func _buffer_total(buf: Array) -> int:
	var n: int = 0
	for entry in buf:
		n += int(entry[1])
	return n

static func _buffer_add(buf: Array, item_type: int, count: int) -> void:
	for entry in buf:
		if int(entry[0]) == item_type:
			entry[1] = int(entry[1]) + count
			return
	buf.append([item_type, count])

static func _buffer_remove(buf: Array, item_type: int, count: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			var taken: int = min(int(entry[1]), count)
			entry[1] = int(entry[1]) - taken
			if int(entry[1]) <= 0:
				buf.erase(entry)
			return taken
	return 0

# ---------- Q-inspect / info_lines ----------

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	# Status — most prominent.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var status: String = "Idle (no fertilizer)"
	match s:
		STATE_SCANNING:
			status = "Scanning"
		STATE_BLOCKED:
			status = "BLOCKED — no eligible tiles in coverage"
	lines.append("Status: %s" % status)

	# Buffer.
	var buf: Array = b.state.get("in_buffer", [])
	if buf.is_empty():
		lines.append("Input: (empty)")
	else:
		for entry in buf:
			lines.append("Input: %d %s" % [int(entry[1]), Items.name_of(int(entry[0]))])

	# Next apply countdown — only meaningful when SCANNING.
	if s == STATE_SCANNING:
		var remaining_ticks: int = APPLY_INTERVAL_TICKS - int(b.state.get("scan_progress", 0))
		var remaining_sec: float = float(remaining_ticks) / 20.0
		lines.append("Next apply: in %.1fs" % remaining_sec)

	# Coverage — count eligible tiles for the highest available tier.
	var tier: int = _select_fertilizer_from_buffer(b)
	if tier >= 0 and world != null:
		var eligible: int = _count_eligible_tiles(b, world, tier)
		lines.append("Eligible tiles in 5×5: %d (for %s)" % [eligible, Items.name_of(tier)])

	# Facing — input port edge.
	lines.append("Input port: %s (R to rotate before placing)" % Belt.DIR_NAMES[Buildings.world_dir(b, INPUT_PORT_DIR)])

	return lines

## Count eligible tiles in coverage for the given tier. Used by info_lines
## + ApplicatorPanel header. Same eligibility test as
## _pick_most_depleted_eligible_tile but doesn't track best — just counts.
static func _count_eligible_tiles(b: Building, world, selected_tier: int) -> int:
	var n: int = 0
	for dx in range(-COVERAGE_RADIUS, COVERAGE_RADIUS + 1):
		for dy in range(-COVERAGE_RADIUS, COVERAGE_RADIUS + 1):
			var pos: Vector2i = Vector2i(b.anchor.x + dx, b.anchor.y + dy)
			if pos.x < WorldGenerator.WORLD_MIN or pos.x >= WorldGenerator.WORLD_MAX:
				continue
			if pos.y < WorldGenerator.WORLD_MIN or pos.y >= WorldGenerator.WORLD_MAX:
				continue
			if world.tile_soil_health(pos) >= GridWorld.TILE_SOIL_FULL:
				continue
			if world.tile_fertilizer_tier(pos) >= selected_tier:
				continue
			n += 1
	return n

# ---------- rendering ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# Body — sage-green tinted by state.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var tint: Color = TINT_NORMAL
	match s:
		STATE_IDLE:
			tint = TINT_IDLE
		STATE_BLOCKED:
			tint = TINT_BLOCKED
	var body_color: Color = Color(BODY_COLOR.r * tint.r, BODY_COLOR.g * tint.g, BODY_COLOR.b * tint.b, 1.0)
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, body_color, true)
	canvas.draw_rect(rect, BODY_BORDER, false, 2.0)

	# Sprinkler nozzle — central circle with 4 short lines radiating outward
	# in cardinal directions. Suggests "spreading" without animation.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var nozzle_radius: float = float(tile_size) * 0.18
	canvas.draw_circle(center, nozzle_radius, NOZZLE_COLOR)
	canvas.draw_arc(center, nozzle_radius, 0.0, TAU, 16, BODY_BORDER, 1.0)

	# Spray lines — 4 cardinals from nozzle edge outward to ~70% of tile.
	var spray_len: float = float(tile_size) * 0.30
	for ang_idx in 4:
		var ang: float = ang_idx * (TAU / 4.0)
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var p1: Vector2 = center + dir * (nozzle_radius + 1.0)
		var p2: Vector2 = center + dir * (nozzle_radius + spray_len)
		canvas.draw_line(p1, p2, NOZZLE_COLOR, 1.5)
