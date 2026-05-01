class_name Chest
extends RefCounted

## Chest — pulls from any adjacent belt's nearest slot, stores items in
## an internal Inventory. Player drains via E like a harvester.
##
## State schema:
##   inventory: Array (Inventory.to_array() format)

const CAPACITY: int = 24

# Visual
const WOOD_DARK: Color = Color(0.30, 0.20, 0.12)
const WOOD_MID: Color = Color(0.50, 0.34, 0.20)
const WOOD_HIGHLIGHT: Color = Color(0.65, 0.46, 0.28)
const TRIM: Color = Color(0.10, 0.06, 0.03)
const FILL_BAR: Color = Color(0.4, 0.95, 0.4)
const FULL_BAR: Color = Color(0.95, 0.30, 0.30)

static func make(pos: Vector2i) -> Building:
	var inv: Inventory = Inventory.new(CAPACITY)
	return Building.new(Buildings.Type.CHEST, pos, {
		"inv": inv.to_array(),
	})

## Helper: get a fresh Inventory wrapping the building's inv array.
## We keep the canonical state as an array (JSON-friendly) and rehydrate
## on demand. Inventory ops mutate the array via load_array / to_array dance.
static func _inv_view(b: Building) -> Inventory:
	var inv: Inventory = Inventory.new(CAPACITY)
	inv.load_array(b.state["inv"])
	return inv

static func _save_inv(b: Building, inv: Inventory) -> void:
	b.state["inv"] = inv.to_array()

static func tick(b: Building, world: Node2D) -> void:
	var inv: Inventory = _inv_view(b)
	var changed: bool = false
	for dir in 4:
		var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
		if not world.has_building_at(npos):
			continue
		var neighbor: Building = world.building_at(npos)
		if neighbor == null or neighbor.type != Buildings.Type.BELT:
			continue
		# Peek the slot facing us; only consume if our inventory will accept it.
		var pull_idx: int = Belt.slot_facing_external(neighbor, b.anchor)
		var slots: Array = neighbor.state["slots"]
		var item_type: int = int(slots[pull_idx])
		if item_type < 0:
			continue
		# has_room_for would be cleaner but Inventory doesn't have it yet (lands in step 7).
		# For now: try add; if 0 added, the inventory is full for this stack — leave the
		# item on the belt and stop scanning this tick.
		var added: int = inv.add(item_type, 1)
		if added > 0:
			slots[pull_idx] = -1
			changed = true
			break  # one pull per tick keeps timing predictable
	if changed:
		_save_inv(b, inv)

## Player E-interact uses this to empty the chest into player's inventory.
static func drain_into(b: Building, dest: Inventory) -> int:
	var inv: Inventory = _inv_view(b)
	var moved: int = 0
	for s in inv.slots:
		if s.is_empty():
			continue
		var added: int = dest.add(s.item_type, s.count)
		moved += added
		s.count -= added
		if s.count <= 0:
			s.clear()
	_save_inv(b, inv)
	return moved

static func total_items(b: Building) -> int:
	var inv: Inventory = _inv_view(b)
	return inv.total_count()

static func info_lines(b: Building) -> Array:
	var inv: Inventory = _inv_view(b)
	var agg: Dictionary = inv.aggregate()
	var lines: Array = ["Slots: %d (capacity)" % CAPACITY]
	if agg.is_empty():
		lines.append("Contents: (empty)")
	else:
		lines.append("Contents:")
		for item_type in agg.keys():
			lines.append("  %s ×%d" % [Items.name_of(item_type), agg[item_type]])
	lines.append("Drain with E (when adjacent)")
	return lines

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, WOOD_DARK, true)
	canvas.draw_rect(rect.grow(-3), WOOD_MID, true)
	# Plank lines for visual texture.
	for i in 3:
		var y: float = world_pos.y + (i + 1) * float(tile_size) / 4.0
		canvas.draw_line(world_pos + Vector2(3, y - world_pos.y), world_pos + Vector2(tile_size - 3, y - world_pos.y), WOOD_HIGHLIGHT, 1.0)
	canvas.draw_rect(rect, TRIM, false, 2.0)

	# Aggregate item count → fill bar.
	var inv: Inventory = _inv_view(b)
	var total: int = inv.total_count()
	var pct: float = clamp(float(total) / float(CAPACITY * 100), 0.0, 1.0)  # rough display heuristic
	var bar_w: float = (float(tile_size) - 6.0) * pct
	var bar_color: Color = FULL_BAR if pct >= 1.0 else FILL_BAR
	canvas.draw_rect(Rect2(world_pos + Vector2(3, tile_size - 5), Vector2(bar_w, 3)), bar_color, true)

	# Show top item icon when not empty.
	var agg: Dictionary = inv.aggregate()
	if not agg.is_empty():
		var first_type: int = agg.keys()[0]
		var ic: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
		canvas.draw_circle(ic, float(tile_size) * 0.16, Items.color_of(first_type))
		canvas.draw_arc(ic, float(tile_size) * 0.16, 0.0, TAU, 16, TRIM, 1.0)
