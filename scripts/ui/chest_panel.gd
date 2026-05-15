extends BuildingPanel

## Chest UI (session-building-ui-2). Bulk-storage grid + player inventory.
## Replaces the inventory_grid paired-view (removed at this session).
##
## Layout:
##   ╔═══════════════ Chest ══════════════════════╗
##   ║                                            ║
##   ║  ┌──┐ ┌──┐ ┌──┐ ┌──┐  Capacity: 138 / 2400 ║
##   ║  │Wh│ │Fl│ │  │ │  │                       ║
##   ║  │ 8│ │12│ │  │ │  │                       ║
##   ║  └──┘ └──┘ └──┘ └──┘                       ║
##   ║  ┌──┐ ┌──┐ ┌──┐ ┌──┐                       ║
##   ║  ...                                       ║
##   ║                                            ║
##   ╠════════════════════════════════════════════╣
##   ║              Player inventory              ║
##   ╚════════════════════════════════════════════╝
##
## Click semantics:
##   - Cursor empty + click chest slot with content → pick to cursor.
##   - Cursor full + click chest slot (empty or otherwise) → drop into bag,
##     capacity-checked. Swap-on-overlap simulated via remove-then-add (chest
##     is bulk; no per-slot ordering, so swap == sequential drop+pick).
##
## Chest slot positions DON'T persist — re-rendering recomputes from the bag
## via SlotWidget.chest_bag_to_slot_views (max_stack-sized splits). Layout
## reorders after each change. Acceptable per Path A design carried over.

const COLS: int = 4
const SLOT_GAP: int = 4
const MIN_ROWS: int = 6                 # always show at least 6 rows for visual stability
const HEADER_GAP: int = 32

## ChestPanel needs a taller top area than the default (280px) — the bag
## grid is 6 rows × 52px = 312px plus the capacity header (~46px). Override
## to make room and prevent the chest grid overlapping into the player
## inventory region below.
func _top_area_height() -> int:
	return MIN_ROWS * (SlotWidget.SIZE + SLOT_GAP) + HEADER_GAP + 14 + 8   # ≈ 380

func _building_slot_rects() -> Array:
	# Chest panel doesn't use the slot_layout-driven generic render. We
	# return empty so BuildingPanel's _draw_slots and click hit-test don't
	# try to render the "chest_bag" entry. ChestPanel handles its own grid.
	return []

func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null:
		return
	# Capacity header.
	var bag: Array = building.state.get("bag", [])
	var total: int = 0
	for entry in bag:
		total += int(entry[1])
	var cap_text: String = "Capacity: %d / %d" % [total, 2400]   # Chest.TOTAL_CAPACITY
	draw_string(font, Vector2(area.position.x + 24, area.position.y + 22),
		"Chest contents", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)
	draw_string(font, Vector2(area.position.x + area.size.x - 200, area.position.y + 22),
		cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)

	# Slot grid.
	var views: Array = SlotWidget.chest_bag_to_slot_views(bag)
	var rows: int = max(MIN_ROWS, int(ceil(float(views.size()) / float(COLS))))
	var grid_x: float = area.position.x + 24
	var grid_y: float = area.position.y + HEADER_GAP + 14
	# Render slot_count = rows * COLS so empty slots render too (visual stability).
	var slot_count: int = rows * COLS
	for i in slot_count:
		var col: int = i % COLS
		var row: int = i / COLS
		var x: float = grid_x + col * (SlotWidget.SIZE + SLOT_GAP)
		var y: float = grid_y + row * (SlotWidget.SIZE + SLOT_GAP)
		var rect: Rect2 = Rect2(x, y, SlotWidget.SIZE, SlotWidget.SIZE)
		var item_type: int = -1
		var count: int = 0
		if i < views.size():
			item_type = int(views[i]["item_type"])
			count = int(views[i]["count"])
		var hovered: bool = (_hover is Dictionary and int(_hover.get("chest_idx", -1)) == i)
		SlotWidget.draw_slot(self, font, rect, item_type, count, hovered)

# ---------- input override ----------
#
# BuildingPanel's _hit_test only tests player slots + slot_layout-derived
# building slots. Chest grid is rendered by us; we override hit-testing to
# include chest grid cells, then handle clicks ourselves.

func _gui_input(event: InputEvent) -> void:
	if not visible or building == null or inventory == null or cursor == null:
		return
	if event is InputEventMouseMotion:
		var hit = _hit_test_chest(event.position)
		_hover = hit
		queue_redraw()
		return
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		var hit = _hit_test_chest(event.position)
		if hit is int and hit < 0:
			# Click inside panel rect but not on a slot → no-op. Only Esc / close
			# button / outside-panel-rect click should close (NOTES.md "Close-on-
			# padding-click UX" item 8 — surfaced GATE 1 + PAUSE 2 user feedback).
			return
		if hit is int:
			_handle_player_slot_click(int(hit), _extract_mods(event))
		elif hit is Dictionary and hit.has("chest_idx"):
			_handle_chest_slot_click(int(hit["chest_idx"]), _extract_mods(event))
		queue_redraw()

## Hit-test that combines player inventory slots + chest grid slots.
## Returns int (player slot index) OR Dictionary {chest_idx: int} OR -1.
func _hit_test_chest(pos: Vector2) -> Variant:
	# Player inventory first.
	if inventory != null:
		for i in inventory.slots.size():
			if _player_slot_rect(i).has_point(pos):
				return i
	# Chest grid.
	var bag: Array = building.state.get("bag", [])
	var rows: int = max(MIN_ROWS, int(ceil(float(SlotWidget.chest_bag_to_slot_views(bag).size()) / float(COLS))))
	var slot_count: int = rows * COLS
	for i in slot_count:
		if _chest_slot_rect(i).has_point(pos):
			return {"chest_idx": i}
	return -1

## Rect for chest-bag slot index `i`. Shared between _hit_test_chest and
## the ctrl-picker anchor in _handle_chest_slot_click (Task 20).
func _chest_slot_rect(i: int) -> Rect2:
	var area: Rect2 = _top_area_rect()
	var grid_x: float = area.position.x + 24
	var grid_y: float = area.position.y + HEADER_GAP + 14
	var col: int = i % COLS
	var row: int = i / COLS
	var x: float = grid_x + col * (SlotWidget.SIZE + SLOT_GAP)
	var y: float = grid_y + row * (SlotWidget.SIZE + SLOT_GAP)
	return Rect2(x, y, SlotWidget.SIZE, SlotWidget.SIZE)

## Click on a chest slot. Cursor empty + content → pick. Cursor full →
## drop into bag (atomic; capacity-checked).
func _handle_chest_slot_click(slot_idx: int, mods: int) -> void:
	var bag: Array = building.state.get("bag", [])
	var views: Array = SlotWidget.chest_bag_to_slot_views(bag)
	var view_present: bool = slot_idx < views.size()

	# Shift+LMB: half-stack take/drop. Chest preserves LMB convention —
	# refuse-with-toast on no-fit (NOT silent-clamp like player slot).
	if mods & SlotClickHandler.MOD_SHIFT != 0:
		if not cursor.has_item():
			# Shift+take half.
			if not view_present:
				return
			var v = views[slot_idx]
			var take: int = SlotClickHandler.split_half(int(v["count"]))
			Chest._bag_remove(bag, int(v["item_type"]), take)
			cursor.pick(int(v["item_type"]), take)
			return
		# Cursor has item — shift+drop half, check capacity for refuse.
		var half: int = SlotClickHandler.split_half(cursor.count)
		if Chest.free_capacity(building) < half:
			_toast("Chest full — cannot deposit half (%d, need %d capacity)" % [half, half])
			return
		Chest._bag_add(bag, cursor.item_type, half)
		cursor.count -= half
		if cursor.count <= 0:
			cursor.clear()
		return

	# Ctrl+LMB → quantity picker (spec §6.1). Inline max computation —
	# chest uses bag entries and free_capacity, not ItemStack, so
	# SlotClickHandler.ctrl_click_max doesn't apply (Q2 minimal-extraction).
	if mods & SlotClickHandler.MOD_CTRL != 0 and quantity_picker != null:
		var giving: bool = cursor.has_item()
		var max_n: int = 0
		var direction: String = ""
		var label_item: String = ""
		if not giving:
			# TAKE: cursor empty. Pick up `n` items from the addressed bag entry.
			if not view_present:
				return  # empty slot, nothing to take
			var v = views[slot_idx]
			max_n = int(v["count"])
			direction = "Take"
			label_item = Items.name_of(int(v["item_type"]))
		else:
			# GIVE: cursor has items. Deposit `n` items into chest, clamped to
			# free_capacity (chest's whole-cursor refuse-on-overflow LMB convention
			# does NOT apply here — picker is exact-N, caller chose a specific
			# value, and the max already accounts for free_capacity).
			max_n = min(cursor.count, Chest.free_capacity(building))
			direction = "Give"
			label_item = Items.name_of(cursor.item_type)
		if max_n <= 0:
			return  # pre-open gate
		var anchor: Vector2 = _chest_slot_rect(slot_idx).get_center() + global_position
		quantity_picker.open(anchor, direction, label_item, max_n, max_n,
			func(n: int):
				_chest_ctrl_transfer(slot_idx, n)
				queue_redraw())
		return

	# Plain LMB — unchanged from pre-Task-11 implementation.
	if not cursor.has_item():
		if not view_present:
			return
		var v = views[slot_idx]
		var item_type: int = int(v["item_type"])
		var c: int = int(v["count"])
		Chest._bag_remove(bag, item_type, c)
		cursor.pick(item_type, c)
		return
	# Cursor full → drop into chest. Capacity check.
	if Chest.free_capacity(building) < cursor.count:
		_toast("Chest full — cannot deposit (need %d more capacity)" % (cursor.count - Chest.free_capacity(building)))
		return
	Chest._bag_add(bag, cursor.item_type, cursor.count)
	if view_present:
		# Swap path: pick up the view's stack onto the now-empty cursor.
		var v2 = views[slot_idx]
		var item_type2: int = int(v2["item_type"])
		var c2: int = int(v2["count"])
		Chest._bag_remove(bag, item_type2, c2)
		cursor.pick(item_type2, c2)
	else:
		cursor.clear()

## Commits an exact-N transfer for chest ctrl+LMB. Direction inferred from
## cursor state at call time. Caller (quantity_picker confirm Callable)
## responsible for n <= pre-computed max.
func _chest_ctrl_transfer(slot_idx: int, n: int) -> void:
	if n <= 0:
		return
	var bag: Array = building.state.get("bag", [])
	var views: Array = SlotWidget.chest_bag_to_slot_views(bag)
	if not cursor.has_item():
		# TAKE n from chest's bag at slot_idx.
		if slot_idx >= views.size():
			return
		var v = views[slot_idx]
		Chest._bag_remove(bag, int(v["item_type"]), n)
		cursor.pick(int(v["item_type"]), n)
		return
	# GIVE n from cursor into chest.
	Chest._bag_add(bag, cursor.item_type, n)
	cursor.count -= n
	if cursor.count <= 0:
		cursor.clear()
