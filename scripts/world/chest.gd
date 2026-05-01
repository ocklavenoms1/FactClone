class_name Chest
extends RefCounted

## Chest — pulls from any adjacent belt's nearest slot, stores items in
## an internal bag. Player drains via E like a harvester.
##
## Storage shape: Array of [item_type, count] (one entry per type).
## This matches Harvester and Processor for codebase-wide consistency.
## Chest IGNORES Items.max_stack_of — it's bulk storage, not slot-UI.
##
## Capacity model:
##   TOTAL_CAPACITY = 2400 items aggregate, equivalent to the previous
##   24-slot × 100-max_stack model. No per-type cap beyond the total.
##
## State schema:
##   bag: Array of [item_type, count]

const TOTAL_CAPACITY: int = 2400  # = 24 (old slots) × 100 (old max_stack)

# Visual
const WOOD_DARK: Color = Color(0.30, 0.20, 0.12)
const WOOD_MID: Color = Color(0.50, 0.34, 0.20)
const WOOD_HIGHLIGHT: Color = Color(0.65, 0.46, 0.28)
const TRIM: Color = Color(0.10, 0.06, 0.03)
const FILL_BAR: Color = Color(0.4, 0.95, 0.4)
const FULL_BAR: Color = Color(0.95, 0.30, 0.30)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.CHEST, pos, {
		"bag": [],
	})

# ---------- bag helpers (mirror Processor's, kept local for readability) ----------

static func _bag(b: Building) -> Array:
	# State always carries "bag"; defensive default for forward compatibility.
	if not b.state.has("bag"):
		b.state["bag"] = []
	return b.state["bag"]

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _bag_total(bag: Array) -> int:
	var n: int = 0
	for entry in bag:
		n += int(entry[1])
	return n

static func _bag_add(bag: Array, item_type: int, count: int) -> void:
	for entry in bag:
		if int(entry[0]) == item_type:
			entry[1] = int(entry[1]) + count
			return
	bag.append([item_type, count])

static func _bag_remove(bag: Array, item_type: int, count: int) -> int:
	for i in bag.size():
		var entry = bag[i]
		if int(entry[0]) == item_type:
			var take: int = min(int(entry[1]), count)
			entry[1] = int(entry[1]) - take
			if int(entry[1]) <= 0:
				bag.remove_at(i)
			return take
	return 0

static func free_capacity(b: Building) -> int:
	return max(0, TOTAL_CAPACITY - _bag_total(_bag(b)))

# ---------- tick ----------

static func tick(b: Building, world: Node2D) -> void:
	if free_capacity(b) <= 0:
		return
	var bag: Array = _bag(b)
	for dir in 4:
		var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
		if not world.has_building_at(npos):
			continue
		var neighbor: Building = world.building_at(npos)
		if neighbor == null or neighbor.type != Buildings.Type.BELT:
			continue
		var pulled: int = Belt.try_pull_matching(neighbor, b.anchor, [])  # accept any
		if pulled >= 0:
			_bag_add(bag, pulled, 1)
			break  # one pull per tick

# ---------- player drain ----------

## Empty the chest into player's inventory. Player's Inventory respects
## max_stack — items the inventory can't fit stay in the chest.
static func drain_into(b: Building, dest: Inventory) -> int:
	var bag: Array = _bag(b)
	var moved: int = 0
	# Iterate a copy of types to avoid mutating while iterating.
	var types: Array = []
	for entry in bag:
		types.append(int(entry[0]))
	for item_type in types:
		var avail: int = _bag_count(bag, item_type)
		if avail <= 0:
			continue
		var added: int = dest.add(item_type, avail)
		if added > 0:
			_bag_remove(bag, item_type, added)
			moved += added
	return moved

static func total_items(b: Building) -> int:
	return _bag_total(_bag(b))

static func info_lines(b: Building) -> Array:
	var bag: Array = _bag(b)
	var total: int = _bag_total(bag)
	var lines: Array = [
		"Capacity: %d / %d" % [total, TOTAL_CAPACITY],
	]
	if bag.is_empty():
		lines.append("Contents: (empty)")
	else:
		lines.append("Contents:")
		for entry in bag:
			lines.append("  %s ×%d" % [Items.name_of(int(entry[0])), int(entry[1])])
	lines.append("Drain with E (when adjacent)")
	return lines

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, WOOD_DARK, true)
	canvas.draw_rect(rect.grow(-3), WOOD_MID, true)
	# Plank lines.
	for i in 3:
		var y: float = world_pos.y + (i + 1) * float(tile_size) / 4.0
		canvas.draw_line(world_pos + Vector2(3, y - world_pos.y), world_pos + Vector2(tile_size - 3, y - world_pos.y), WOOD_HIGHLIGHT, 1.0)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Honest fill bar against TOTAL_CAPACITY.
	var bag: Array = _bag(b)
	var total: int = _bag_total(bag)
	var pct: float = clamp(float(total) / float(TOTAL_CAPACITY), 0.0, 1.0)
	var bar_w: float = (float(tile_size) - 6.0) * pct
	var bar_color: Color = FULL_BAR if pct >= 1.0 else FILL_BAR
	canvas.draw_rect(Rect2(world_pos + Vector2(3, tile_size - 5), Vector2(bar_w, 3)), bar_color, true)

	# Show first item type as an icon when not empty.
	if not bag.is_empty():
		var first_type: int = int(bag[0][0])
		var ic: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
		canvas.draw_circle(ic, float(tile_size) * 0.16, Items.color_of(first_type))
		canvas.draw_arc(ic, float(tile_size) * 0.16, 0.0, TAU, 16, TRIM, 1.0)
