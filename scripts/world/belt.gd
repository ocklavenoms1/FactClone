class_name Belt
extends RefCounted

## Belt — moves items one tile in its facing direction.
##
## Model: each belt tile has SLOTS_PER_TILE discrete slots. Items advance
## one slot per "belt tick" (every TICKS_PER_SLOT world ticks). Belts are
## ticked in TWO PASSES per belt-tick to avoid order-dependent jitter:
##
##   Pass 1 (shift): each belt shifts items forward within its own slots.
##   Pass 2 (handoff): each belt's front slot tries to push into the next
##                      consumer (another belt, later: a mill, etc).
##
## Both passes must read a stable "current state" — that's what the two
## passes guarantee.
##
## State schema:
##   dir: int           0=East, 1=South, 2=West, 3=North
##   slots: Array[int]  length=SLOTS_PER_TILE, item type per slot or -1

const SLOTS_PER_TILE: int = 4
const TICKS_PER_SLOT: int = 4   # 4 ticks/slot @ 20tps = 5 slots/sec → ~1.25 tiles/sec

# Directions
const DIR_E: int = 0
const DIR_S: int = 1
const DIR_W: int = 2
const DIR_N: int = 3
const DIR_VECS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const DIR_NAMES: Array = ["E", "S", "W", "N"]

# Visual
const BG_COLOR: Color = Color(0.20, 0.20, 0.22)
const TRIM_COLOR: Color = Color(0.05, 0.05, 0.06)
const ARROW_COLOR: Color = Color(0.55, 0.55, 0.58)
const ARROW_BRIGHT: Color = Color(0.85, 0.85, 0.30)

static func make(pos: Vector2i, dir: int = DIR_E) -> Building:
	var slots: Array = []
	for i in SLOTS_PER_TILE:
		slots.append(-1)
	return Building.new(Buildings.Type.BELT, pos, {
		"dir": dir,
		"slots": slots,
	})

## True on the world ticks where belts advance. All belts advance in lockstep
## so chains move uniformly.
static func is_advance_tick() -> bool:
	return TickSystem.current_tick % TICKS_PER_SLOT == 0

## Pass 1 — shift items forward within this belt only.
## Front (highest index) gets first opportunity to be filled from behind.
static func tick(b: Building, _world: Node2D) -> void:
	if not is_advance_tick():
		return
	var slots: Array = b.state["slots"]
	for i in range(SLOTS_PER_TILE - 1, 0, -1):
		if int(slots[i]) < 0 and int(slots[i - 1]) >= 0:
			slots[i] = slots[i - 1]
			slots[i - 1] = -1

## Pass 2 — try to push the front slot to the next consumer.
static func post_tick(b: Building, world: Node2D) -> void:
	if not is_advance_tick():
		return
	var slots: Array = b.state["slots"]
	var front_idx: int = SLOTS_PER_TILE - 1
	if int(slots[front_idx]) < 0:
		return
	var dir: int = int(b.state["dir"])
	var next_pos: Vector2i = b.anchor + DIR_VECS[dir]
	if not world.has_building_at(next_pos):
		return
	var next_b: Building = world.building_at(next_pos)
	if next_b == null:
		return
	if next_b.type == Buildings.Type.BELT:
		# Don't feed back into the belt we'd be facing if it's pointed at us
		# (would create instant ping-pong loops). Allow side-feeding fine.
		var next_dir: int = int(next_b.state["dir"])
		if next_dir == _opposite(dir):
			return
		var next_slots: Array = next_b.state["slots"]
		if int(next_slots[0]) < 0:
			next_slots[0] = slots[front_idx]
			slots[front_idx] = -1
	# Mill / chest / etc. consumers will land here once they exist.

static func _opposite(dir: int) -> int:
	return (dir + 2) % 4

## Try to insert an item into this belt's back slot. Used by harvesters and
## later by player-drop / inserters.
## Returns true if the item was accepted.
static func try_insert(b: Building, item_type: int) -> bool:
	var slots: Array = b.state["slots"]
	if int(slots[0]) >= 0:
		return false
	slots[0] = item_type
	return true

## Pick the slot index of `belt` that lies nearest to `target_pos`.
## For a belt pointing TOWARD target_pos → returns the front slot (highest index).
## For any other adjacency (away, side) → returns the back slot (index 0).
## Used by external consumers (Mill, Chest, Processor) to know which slot to read.
static func slot_facing_external(belt: Building, target_pos: Vector2i) -> int:
	var dir: int = int(belt.state["dir"])
	var to_target: Vector2i = target_pos - belt.anchor
	if to_target == DIR_VECS[dir]:
		return SLOTS_PER_TILE - 1
	return 0

## External consumer (mill / chest / processor at `consumer_pos`) tries to pull
## one item from the slot of `belt` that faces it. Pulls only if the slot's
## item_type appears in `accept` (an Array[int]). Pass an empty `accept` to
## accept any item.
##
## Returns the item_type pulled (>=0) or -1 if nothing was pulled.
static func try_pull_matching(belt: Building, consumer_pos: Vector2i, accept: Array) -> int:
	var slot_idx: int = slot_facing_external(belt, consumer_pos)
	var slots: Array = belt.state["slots"]
	var item_type: int = int(slots[slot_idx])
	if item_type < 0:
		return -1
	if not accept.is_empty() and not (item_type in accept):
		return -1
	slots[slot_idx] = -1
	return item_type

static func info_lines(b: Building) -> Array:
	var dir: int = int(b.state.get("dir", 0))
	var slots: Array = b.state.get("slots", [])
	var occupied: int = 0
	var contents: Array = []
	for i in slots.size():
		var item_type: int = int(slots[i])
		if item_type >= 0:
			occupied += 1
			contents.append("[%d]=%s" % [i, Items.name_of(item_type)])
	var contents_str: String = ", ".join(contents) if not contents.is_empty() else "(empty)"
	return [
		"Direction: %s" % DIR_NAMES[dir],
		"Slots filled: %d / %d" % [occupied, SLOTS_PER_TILE],
		"Contents: %s" % contents_str,
	]

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BG_COLOR, true)
	canvas.draw_rect(rect, TRIM_COLOR, false, 1.5)

	var dir: int = int(b.state["dir"])
	# Animate arrows so the belt visibly "scrolls" — purely cosmetic.
	var phase: float = fmod(float(TickSystem.current_tick) / float(TICKS_PER_SLOT), 1.0)
	_draw_arrows(canvas, world_pos, tile_size, dir, phase)

	# Draw items at their slot positions.
	var slots: Array = b.state["slots"]
	for i in SLOTS_PER_TILE:
		if int(slots[i]) < 0:
			continue
		var slot_center: Vector2 = world_pos + _slot_offset(i, tile_size, dir)
		var item_type: int = int(slots[i])
		canvas.draw_circle(slot_center, tile_size * 0.10, Items.color_of(item_type))
		canvas.draw_arc(slot_center, tile_size * 0.10, 0.0, TAU, 12, Color.BLACK, 1.0)

static func _slot_offset(slot_idx: int, tile_size: int, dir: int) -> Vector2:
	# Center of slot `slot_idx` within the tile, given direction.
	# Slots run from "back" (idx 0) to "front" (idx SLOTS_PER_TILE-1) along dir.
	var t: float = (float(slot_idx) + 0.5) / float(SLOTS_PER_TILE)  # 0..1 along belt axis
	var along: float = t * float(tile_size)
	var across: float = float(tile_size) * 0.5
	match dir:
		DIR_E: return Vector2(along, across)
		DIR_S: return Vector2(across, along)
		DIR_W: return Vector2(float(tile_size) - along, across)
		DIR_N: return Vector2(across, float(tile_size) - along)
	return Vector2(across, across)

static func _draw_arrows(canvas: CanvasItem, world_pos: Vector2, tile_size: int, dir: int, phase: float) -> void:
	# Three chevrons spaced along the belt, scrolled by `phase`.
	var n: int = 3
	for i in n:
		var t: float = (float(i) + phase) / float(n)
		var center_local: Vector2 = _slot_offset(int(t * SLOTS_PER_TILE), tile_size, dir)
		# Re-place exactly along axis (slot_offset rounds; that's fine).
		var t_along: float = t * float(tile_size)
		var across: float = float(tile_size) * 0.5
		var along_axis: Vector2
		var across_axis: Vector2
		match dir:
			DIR_E: along_axis = Vector2(1, 0); across_axis = Vector2(0, 1); center_local = Vector2(t_along, across)
			DIR_S: along_axis = Vector2(0, 1); across_axis = Vector2(1, 0); center_local = Vector2(across, t_along)
			DIR_W: along_axis = Vector2(-1, 0); across_axis = Vector2(0, 1); center_local = Vector2(float(tile_size) - t_along, across)
			DIR_N: along_axis = Vector2(0, -1); across_axis = Vector2(1, 0); center_local = Vector2(across, float(tile_size) - t_along)
		var size: float = float(tile_size) * 0.18
		var tip: Vector2 = world_pos + center_local + along_axis * size
		var l: Vector2 = world_pos + center_local + across_axis * size
		var r: Vector2 = world_pos + center_local - across_axis * size
		var color: Color = ARROW_BRIGHT if i == n - 1 else ARROW_COLOR
		canvas.draw_line(l, tip, color, 1.5)
		canvas.draw_line(r, tip, color, 1.5)
