class_name Harvester
extends RefCounted

## Harvester — placed on stone. Every SCAN_PERIOD ticks, scans its 8
## neighbors for planters with output, extracts one item per scan into
## its own internal buffer.
##
## State schema:
##   buffer: Dictionary[int -> int]   item_type -> count (in-memory; serialized as Array of [type, count])
##   next_scan_tick: int              tick at or after which we scan
##
## The buffer is intentionally a small Dictionary, NOT an Inventory, because
## it has no slot structure — items are pooled by type. Belts will pull from
## this buffer once they exist; for now the player drains it via interact.

const SCAN_PERIOD: int = 10           # 0.5s @ 20 tps
const BUFFER_CAPACITY: int = 50       # total items across all types

# Visual
const BASE_COLOR: Color = Color(0.55, 0.55, 0.60)
const TRIM_COLOR: Color = Color(0.30, 0.30, 0.35)
const ARM_COLOR: Color = Color(0.85, 0.45, 0.20)
const FULL_COLOR: Color = Color(0.95, 0.30, 0.30)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.HARVESTER, pos, {
		"buffer": [],            # Array of [item_type, count] for JSON friendliness
		"next_scan_tick": 0,
	})

static func tick(b: Building, world: Node2D) -> void:
	# Output side: every tick, try to push 1 buffered item onto an adjacent belt.
	# Iterating cardinal neighbors only — corners aren't valid belt connections.
	_try_feed_belt(b, world)

	# Intake side: scan for ripe planters every SCAN_PERIOD ticks.
	var next_scan: int = int(b.state.get("next_scan_tick", 0))
	if TickSystem.current_tick < next_scan:
		return
	b.state["next_scan_tick"] = TickSystem.current_tick + SCAN_PERIOD

	if buffer_total(b) >= BUFFER_CAPACITY:
		return

	# Scan 8 neighbors (king moves). One extraction per scan keeps it
	# rate-limited and predictable — feels like a mechanical arm.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var npos: Vector2i = b.anchor + Vector2i(dx, dy)
			if not world.has_building_at(npos):
				continue
			var neighbor: Building = world.building_at(npos)
			if neighbor == null or neighbor.type != Buildings.Type.PLANTER:
				continue
			var item: int = Planter.try_extract(neighbor)
			if item >= 0:
				_add_to_buffer(b, item, 1)
				return  # one per scan

## Push one buffered item onto an adjacent destination. Two-pass priority:
##   Pass 1 — non-belt sinks (Chest, Void). Adjacency to these signals
##            "drain output here", overriding belt routing.
##   Pass 2 — belts. The standard downstream path.
static func _try_feed_belt(b: Building, world: Node2D) -> void:
	if buffer_total(b) <= 0:
		return
	var buf: Array = b.state.get("buffer", [])
	if buf.is_empty():
		return
	var item_type: int = int(buf[0][0])
	# Pass 1: non-belt sinks first.
	for dir in 4:
		var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
		if not world.has_building_at(npos):
			continue
		var neighbor: Building = world.building_at(npos)
		if neighbor == null:
			continue
		var pushed: bool = false
		if neighbor.type == Buildings.Type.CHEST:
			pushed = Chest.try_insert(neighbor, item_type, 1)
		if pushed:
			_remove_from_buffer(b, item_type, 1)
			return
	# Pass 2: belts.
	for dir in 4:
		var npos2: Vector2i = b.anchor + Belt.DIR_VECS[dir]
		if not world.has_building_at(npos2):
			continue
		var neighbor2: Building = world.building_at(npos2)
		if neighbor2 == null or neighbor2.type != Buildings.Type.BELT:
			continue
		if Belt.try_insert(neighbor2, item_type):
			_remove_from_buffer(b, item_type, 1)
			return

# ---------- buffer helpers ----------

static func _add_to_buffer(b: Building, item_type: int, count: int) -> void:
	var buf: Array = b.state.get("buffer", [])
	for entry in buf:
		if int(entry[0]) == item_type:
			entry[1] = int(entry[1]) + count
			return
	buf.append([item_type, count])
	b.state["buffer"] = buf

static func _remove_from_buffer(b: Building, item_type: int, count: int) -> int:
	var buf: Array = b.state.get("buffer", [])
	var removed: int = 0
	var keep: Array = []
	for entry in buf:
		if int(entry[0]) == item_type and removed < count:
			var take: int = min(int(entry[1]), count - removed)
			removed += take
			var leftover: int = int(entry[1]) - take
			if leftover > 0:
				keep.append([item_type, leftover])
		else:
			keep.append(entry)
	b.state["buffer"] = keep
	return removed

static func buffer_total(b: Building) -> int:
	var n: int = 0
	for entry in b.state.get("buffer", []):
		n += int(entry[1])
	return n

static func info_lines(b: Building) -> Array:
	var total: int = buffer_total(b)
	var buf: Array = b.state.get("buffer", [])
	var contents: String = "(empty)"
	if not buf.is_empty():
		var parts: Array = []
		for entry in buf:
			parts.append("%s ×%d" % [Items.name_of(int(entry[0])), int(entry[1])])
		contents = ", ".join(parts)
	var next_scan: int = int(b.state.get("next_scan_tick", 0))
	var ticks_to_scan: int = max(0, next_scan - TickSystem.current_tick)
	return [
		"Buffer: %s" % contents,
		"Capacity: %d / %d" % [total, BUFFER_CAPACITY],
		"Next scan in: %d ticks" % ticks_to_scan,
		"Drain with E (when adjacent)",
	]

## Drain the buffer into the given Inventory. Returns total items moved.
static func drain_into(b: Building, inv: Inventory) -> int:
	var moved: int = 0
	var buf: Array = b.state.get("buffer", [])
	var remaining: Array = []
	for entry in buf:
		var item_type: int = int(entry[0])
		var count: int = int(entry[1])
		var added: int = inv.add(item_type, count)
		moved += added
		var leftover: int = count - added
		if leftover > 0:
			remaining.append([item_type, leftover])
	b.state["buffer"] = remaining
	return moved

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BASE_COLOR, true)
	canvas.draw_rect(rect.grow(-3), TRIM_COLOR, true)
	canvas.draw_rect(rect, Color.BLACK, false, 2.0)

	# A small arm/claw rotating slowly to convey "this thing is working".
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var t: float = float(TickSystem.current_tick) * 0.05
	var arm_dir: Vector2 = Vector2(cos(t), sin(t))
	var arm_color: Color = FULL_COLOR if buffer_total(b) >= BUFFER_CAPACITY else ARM_COLOR
	canvas.draw_line(center, center + arm_dir * (tile_size * 0.32), arm_color, 3.0)
	canvas.draw_circle(center, 3.5, arm_color)

	# Tiny fill bar on the bottom edge to show buffer fullness.
	var pct: float = clamp(float(buffer_total(b)) / float(BUFFER_CAPACITY), 0.0, 1.0)
	var bar_w: float = (tile_size - 6) * pct
	canvas.draw_rect(Rect2(world_pos + Vector2(3, tile_size - 5), Vector2(bar_w, 3)), Color(0.4, 0.95, 0.4), true)
