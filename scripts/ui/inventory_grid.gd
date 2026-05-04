extends Control

## Modal Factorio-style slot grid for the player inventory.
##
## Visualizes the per-slot reality of `Inventory` (which has always been
## slot-by-slot, max_stack-enforced — the aggregate inventory_panel hid
## that). Lets the player pick up, place, swap, and combine stacks via
## click. v1 scope: own-inventory manipulation only. Chest paired view +
## transfers land in v2 of this same controller.
##
## Layout: fixed 4-column grid, rows = ceil(capacity / 4). Each bag
## consumed grants +4 slots = exactly +1 row, so bag rewards are
## visually obvious as the grid grows downward.
##
## Toggle: I (or Esc) opens / closes. While open: world clicks blocked by
## a dim overlay; player movement gated by `inventory_grid.visible`.

const COLS: int = 4
const SLOT_SIZE: int = 48
const SLOT_GAP: int = 4
const PADDING: int = 12
const TITLE_HEIGHT: int = 24
const FOOTER_HEIGHT: int = 6

# Reuses the hotbar's palette so slots feel like part of the same UI family.
const SLOT_BG: Color = Color(0.10, 0.10, 0.10, 0.92)
const SLOT_BG_EMPTY: Color = Color(0.16, 0.16, 0.16, 0.92)
const SLOT_BORDER: Color = Color(0.50, 0.50, 0.50, 0.95)
const SLOT_BORDER_HOVER: Color = Color(1.00, 0.92, 0.40, 1.00)
const PANEL_BG: Color = Color(0.08, 0.08, 0.10, 0.96)
const PANEL_BORDER: Color = Color(0.55, 0.55, 0.55, 0.95)
const DIM_OVERLAY: Color = Color(0, 0, 0, 0.55)
const TITLE_COLOR: Color = Color(1.00, 0.92, 0.55)
const COUNT_COLOR: Color = Color(1.00, 1.00, 1.00)
const COUNT_SHADOW: Color = Color(0, 0, 0, 0.85)
const TOOLTIP_BG: Color = Color(0.08, 0.08, 0.10, 0.96)
const TOOLTIP_BORDER: Color = Color(0.55, 0.55, 0.55)
const TOOLTIP_TEXT: Color = Color(0.95, 0.95, 0.85)

# Cursor stack — items the player has picked up, follows the mouse, drawn
# above slot grid. Shared object owned by main.gd, set via setter; same
# instance is also bound to BuildingPanel subclasses so the cursor persists
# across modal switches (player picks up wood here, closes inventory, opens
# smelter, drops wood into fuel slot — single object tracks the held stack).
var cursor: CursorStack = null

# Hover state — encoded as (grid_id, slot_idx). grid_id 0 = player, 1 =
# chest. -1 slot_idx means no slot under cursor.
var _hover_grid: int = -1
var _hover_slot: int = -1

# Chest paired view — non-null when E was pressed adjacent to a chest.
# Display widens to show two grids side-by-side (player left, chest right).
# View adapter splits chest.state.bag entries into max_stack-sized virtual
# slots for display; clicks resolve back to bag operations on commit.
var _chest_building: Building = null

# Set by main.gd before first show.
var inventory: Inventory = null

# Set by main.gd to push toasts up to the player's HUD when auto-return
# moves a stack to a different slot, or refuses close on a full inventory.
var toast_callback: Callable = Callable()

# Grid IDs for click routing. Internal constants — only the click handlers
# care which grid was hit.
const GRID_PLAYER: int = 0
const GRID_CHEST: int = 1

func _ready() -> void:
	# Modal: full-screen overlay so clicks outside the grid don't leak to
	# the world. mouse_filter STOP catches clicks at the root.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

# ---------- public API ----------

## Toggle visibility. main.gd calls this on I/Esc. Auto-return runs when
## closing if the cursor stack is non-empty.
func toggle() -> void:
	if visible:
		_close()
	else:
		_open()

func is_open() -> bool:
	return visible

## Open the player+chest paired view. Called by main.gd when E is pressed
## adjacent to a chest. Edge case: if cursor stack is non-empty, place it
## into the target chest first (chest is bulk storage, so as long as
## TOTAL_CAPACITY isn't exceeded, this always succeeds). If chest is also
## at capacity, refuse to open and toast — keeps the cursor state coherent.
func open_chest_paired_view(chest: Building) -> void:
	if chest == null or chest.type != Buildings.Type.CHEST:
		return
	# Cursor full → place into chest first.
	if cursor.item_type >= 0 and cursor.count > 0:
		if not Chest.try_insert(chest, cursor.item_type, cursor.count):
			_toast("Chest is full — clear cursor stack before opening.")
			return
		cursor.item_type = -1
		cursor.count = 0
	_chest_building = chest
	_open()

# ---------- open / close ----------

func _open() -> void:
	visible = true
	_hover_grid = -1
	_hover_slot = -1
	queue_redraw()

func _close() -> void:
	# Cursor stack persists across modal close (session-building-ui-1).
	# Player can pick up wood here, close, open the smelter, drop into fuel
	# slot. The cursor is shared across modals via the CursorStack object.
	#
	# (Old behavior: auto-returned cursor to first-empty-slot or chest, refused
	# close if neither had room. That created a UX trap when the player wanted
	# to drag from inventory directly into a building. Removed.)
	visible = false
	_chest_building = null
	_hover_grid = -1
	_hover_slot = -1

func _find_first_empty_slot() -> int:
	for i in inventory.slots.size():
		if inventory.slots[i].is_empty():
			return i
	return -1

# ---------- chest view adapter (Path A) ----------

## Convert a chest bag (Array of [item_type, count]) to a list of
## {item_type, count} dictionaries representing virtual slots, splitting
## bag entries into max_stack-sized chunks. Slot positions DON'T persist
## — re-rendering recomputes from the bag, so chest layout reorders after
## each change. Acceptable per design; migrate to per-slot chest storage
## later if it becomes painful.
##
## Static + pure so the test can call it with synthetic bags.
static func chest_bag_to_slot_views(bag: Array) -> Array:
	var views: Array = []
	for entry in bag:
		var item_type: int = int(entry[0])
		var remaining: int = int(entry[1])
		var max_stack: int = Items.max_stack_of(item_type)
		while remaining > 0:
			var portion: int = min(remaining, max_stack)
			views.append({"item_type": item_type, "count": portion})
			remaining -= portion
	return views

func _chest_slot_views() -> Array:
	if _chest_building == null:
		return []
	return chest_bag_to_slot_views(_chest_building.state.get("bag", []))

## Number of slots to render for the chest grid. Equals approximate
## TOTAL_CAPACITY / max_stack_of(typical_item) ≈ 24, but we always show
## at least max(active_views, 24) so the grid doesn't shrink visually as
## the player empties stacks.
func _chest_slot_capacity() -> int:
	var view_count: int = _chest_slot_views().size()
	# Match the legacy "24 slots × 100 max_stack" model from the v6 migration log.
	return max(24, view_count)

func _toast(msg: String) -> void:
	if toast_callback.is_valid():
		toast_callback.call(msg)

# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if not visible or inventory == null:
		return
	if event is InputEventMouseMotion:
		var hit: Array = _slot_under(event.position)
		_hover_grid = hit[0]
		_hover_slot = hit[1]
		queue_redraw()
		return
	if event is InputEventMouseButton:
		if not event.pressed:
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var hit: Array = _slot_under(event.position)
		var grid_id: int = hit[0]
		var slot_idx: int = hit[1]
		if slot_idx < 0:
			# Click outside any grid — close (auto-return runs).
			_close()
			return
		if event.shift_pressed:
			# Shift+left-click → transfer entire stack to the OTHER grid.
			# Only meaningful when chest paired view is open; in player-only
			# mode it's a no-op (no second grid to transfer to).
			if _chest_building != null:
				_handle_shift_click(grid_id, slot_idx)
			return
		_handle_left_click(grid_id, slot_idx)

func _handle_left_click(grid_id: int, slot_idx: int) -> void:
	if grid_id == GRID_PLAYER:
		_handle_left_click_player(slot_idx)
	elif grid_id == GRID_CHEST:
		_handle_left_click_chest(slot_idx)

## Player-grid left click: full pick / place / combine / swap semantics
## (player owns slot positioning).
func _handle_left_click_player(slot_idx: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	# Cursor empty → pick up slot's stack (if any).
	if cursor.item_type < 0:
		if slot.is_empty():
			return
		cursor.item_type = slot.item_type
		cursor.count = slot.count
		slot.clear()
		queue_redraw()
		return
	# Cursor full → place / combine / swap.
	if slot.is_empty():
		slot.item_type = cursor.item_type
		slot.count = cursor.count
		cursor.item_type = -1
		cursor.count = 0
	elif slot.item_type == cursor.item_type:
		var max_stack: int = Items.max_stack_of(slot.item_type)
		var space: int = max_stack - slot.count
		var moved: int = min(space, cursor.count)
		slot.count += moved
		cursor.count -= moved
		if cursor.count <= 0:
			cursor.item_type = -1
			cursor.count = 0
	else:
		var tmp_type: int = slot.item_type
		var tmp_count: int = slot.count
		slot.item_type = cursor.item_type
		slot.count = cursor.count
		cursor.item_type = tmp_type
		cursor.count = tmp_count
	queue_redraw()

## Chest-grid left click: simpler than player because chest is bulk
## storage (no per-slot position; bag aggregates by type).
##  - Cursor empty + slot has view → pick that view's stack to cursor.
##  - Cursor full + slot empty → drop entire cursor stack into chest bag.
##  - Cursor full + slot has view → drop cursor + pick up view (net swap),
##    works because chest bag handles the underlying add/remove.
func _handle_left_click_chest(slot_idx: int) -> void:
	if _chest_building == null:
		return
	var views: Array = _chest_slot_views()
	var view_present: bool = slot_idx < views.size()
	# Cursor empty → pick up the view's stack if present.
	if cursor.item_type < 0:
		if not view_present:
			return
		var v = views[slot_idx]
		var item_type: int = int(v["item_type"])
		var count: int = int(v["count"])
		Chest._bag_remove(_chest_building.state["bag"], item_type, count)
		cursor.item_type = item_type
		cursor.count = count
		queue_redraw()
		return
	# Cursor full → drop into chest, optionally swapping with the view.
	# Capacity check: chest TOTAL_CAPACITY is honored; if full, refuse drop.
	if Chest.free_capacity(_chest_building) < cursor.count:
		_toast("Chest full — cannot deposit (need %d more capacity)" % (cursor.count - Chest.free_capacity(_chest_building)))
		return
	# Drop cursor into chest first.
	Chest._bag_add(_chest_building.state["bag"], cursor.item_type, cursor.count)
	if view_present:
		# Swap path — pick up the view's stack onto the now-empty cursor.
		var v2 = views[slot_idx]
		var item_type2: int = int(v2["item_type"])
		var count2: int = int(v2["count"])
		Chest._bag_remove(_chest_building.state["bag"], item_type2, count2)
		cursor.item_type = item_type2
		cursor.count = count2
	else:
		cursor.item_type = -1
		cursor.count = 0
	queue_redraw()

## Shift-click: transfer entire stack to the OTHER grid (no cursor pickup).
## Only fires when chest paired view is open.
func _handle_shift_click(grid_id: int, slot_idx: int) -> void:
	if grid_id == GRID_PLAYER:
		# Player slot → chest. Try to deposit entire stack; partial-deposit
		# leaves remainder in the player slot.
		if slot_idx >= inventory.slots.size():
			return
		var slot: ItemStack = inventory.slots[slot_idx]
		if slot.is_empty():
			return
		var free: int = Chest.free_capacity(_chest_building)
		if free <= 0:
			_toast("Chest full")
			return
		var moved: int = min(slot.count, free)
		Chest._bag_add(_chest_building.state["bag"], slot.item_type, moved)
		slot.count -= moved
		if slot.count <= 0:
			slot.clear()
		queue_redraw()
	elif grid_id == GRID_CHEST:
		# Chest slot → player. Pick up that view, then route through
		# Inventory.add (which respects per-slot max_stack across the
		# player's slots).
		var views: Array = _chest_slot_views()
		if slot_idx >= views.size():
			return
		var v = views[slot_idx]
		var item_type: int = int(v["item_type"])
		var count: int = int(v["count"])
		var added: int = inventory.add(item_type, count)
		# Whatever was actually added → remove from chest bag.
		if added > 0:
			Chest._bag_remove(_chest_building.state["bag"], item_type, added)
		if added < count:
			_toast("Inventory full — %d/%d transferred" % [added, count])
		queue_redraw()

# ---------- geometry ----------

## Whether the layout is currently paired (chest open) or single (player only).
func _is_paired() -> bool:
	return _chest_building != null

## Returns Vector2 origin for a specific grid.
##  grid_id == GRID_PLAYER → player grid's top-left.
##  grid_id == GRID_CHEST → chest grid's top-left.
func _grid_origin_of(grid_id: int) -> Vector2:
	var view_size: Vector2 = get_viewport_rect().size
	var player_rows: int = _row_count_player()
	var chest_rows: int = _row_count_chest()
	var grid_w: int = COLS * SLOT_SIZE + (COLS - 1) * SLOT_GAP
	var panel_w: int = grid_w + PADDING * 2
	# Use the taller of the two grids so both panels are flush vertically.
	var max_rows: int = max(player_rows, chest_rows)
	var grid_h: int = max_rows * SLOT_SIZE + (max_rows - 1) * SLOT_GAP
	var panel_h: int = grid_h + PADDING * 2 + TITLE_HEIGHT + FOOTER_HEIGHT
	var origin_y: float = (view_size.y - panel_h) * 0.5
	if not _is_paired():
		# Single panel, centered horizontally.
		var origin_x: float = (view_size.x - panel_w) * 0.5
		return Vector2(origin_x, origin_y)
	# Paired: two panels side-by-side with a small gap between.
	var pair_gap: int = 16
	var total_w: int = panel_w * 2 + pair_gap
	var pair_origin_x: float = (view_size.x - total_w) * 0.5
	if grid_id == GRID_PLAYER:
		return Vector2(pair_origin_x, origin_y)
	# Chest panel sits to the right of the player panel.
	return Vector2(pair_origin_x + panel_w + pair_gap, origin_y)

func _row_count_player() -> int:
	if inventory == null:
		return 4
	return int(ceil(float(inventory.capacity) / float(COLS)))

func _row_count_chest() -> int:
	if _chest_building == null:
		return 0
	return int(ceil(float(_chest_slot_capacity()) / float(COLS)))

func _slot_rect_in_grid(grid_id: int, slot_idx: int) -> Rect2:
	var origin: Vector2 = _grid_origin_of(grid_id)
	var grid_top: float = origin.y + PADDING + TITLE_HEIGHT
	var grid_left: float = origin.x + PADDING
	var col: int = slot_idx % COLS
	var row: int = slot_idx / COLS
	var x: float = grid_left + col * (SLOT_SIZE + SLOT_GAP)
	var y: float = grid_top + row * (SLOT_SIZE + SLOT_GAP)
	return Rect2(x, y, SLOT_SIZE, SLOT_SIZE)

## Returns [grid_id, slot_idx]. slot_idx == -1 means no slot under cursor.
## grid_id is GRID_PLAYER or GRID_CHEST when slot_idx >= 0; -1 otherwise.
func _slot_under(pos: Vector2) -> Array:
	if inventory == null:
		return [-1, -1]
	for i in inventory.slots.size():
		if _slot_rect_in_grid(GRID_PLAYER, i).has_point(pos):
			return [GRID_PLAYER, i]
	if _is_paired():
		var chest_cap: int = _chest_slot_capacity()
		for i in chest_cap:
			if _slot_rect_in_grid(GRID_CHEST, i).has_point(pos):
				return [GRID_CHEST, i]
	return [-1, -1]

# ---------- rendering ----------

func _draw() -> void:
	if inventory == null:
		return

	# Full-screen dim overlay (separate from the panel) — clicks on it
	# trigger _gui_input → _close.
	var view_size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view_size), DIM_OVERLAY, true)

	var font: Font = ThemeDB.fallback_font
	_draw_panel(font, GRID_PLAYER, "Inventory", _row_count_player())
	if _is_paired():
		_draw_panel(font, GRID_CHEST, "Chest", _row_count_chest())

	# Cursor stack — always drawn last so it floats above slots.
	if cursor.item_type >= 0 and cursor.count > 0:
		_draw_cursor_stack(font)

	# Hover tooltip — slot under cursor with non-empty content.
	if _hover_slot >= 0:
		var ht: int = -1
		var hc: int = 0
		if _hover_grid == GRID_PLAYER and _hover_slot < inventory.slots.size():
			var hovered: ItemStack = inventory.slots[_hover_slot]
			if not hovered.is_empty():
				ht = hovered.item_type
				hc = hovered.count
		elif _hover_grid == GRID_CHEST:
			var views: Array = _chest_slot_views()
			if _hover_slot < views.size():
				ht = int(views[_hover_slot]["item_type"])
				hc = int(views[_hover_slot]["count"])
		if ht >= 0:
			_draw_tooltip(font, ht, hc)

## Draws panel background, title, and slot grid for one of the two grids.
## For GRID_PLAYER, slot content comes from `inventory.slots`. For GRID_CHEST,
## from the view-adapter `_chest_slot_views()`. Empty slots beyond the
## populated portion are still drawn (up to capacity) so the grid is
## visually whole.
func _draw_panel(font: Font, grid_id: int, title: String, rows: int) -> void:
	var grid_w: int = COLS * SLOT_SIZE + (COLS - 1) * SLOT_GAP
	# Use the taller grid for panel height so paired panels are flush.
	var max_rows: int = max(_row_count_player(), _row_count_chest()) if _is_paired() else rows
	var grid_h: int = max_rows * SLOT_SIZE + (max_rows - 1) * SLOT_GAP
	var panel_w: int = grid_w + PADDING * 2
	var panel_h: int = grid_h + PADDING * 2 + TITLE_HEIGHT + FOOTER_HEIGHT
	var origin: Vector2 = _grid_origin_of(grid_id)
	var panel_rect: Rect2 = Rect2(origin, Vector2(panel_w, panel_h))
	draw_rect(panel_rect, PANEL_BG, true)
	draw_rect(panel_rect, PANEL_BORDER, false, 2.0)
	draw_string(font, origin + Vector2(PADDING, PADDING + 16), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TITLE_COLOR)

	var slot_count: int = inventory.slots.size() if grid_id == GRID_PLAYER else _chest_slot_capacity()
	for i in slot_count:
		_draw_slot(font, grid_id, i)

func _draw_slot(font: Font, grid_id: int, slot_idx: int) -> void:
	var rect: Rect2 = _slot_rect_in_grid(grid_id, slot_idx)
	# Resolve slot content from the appropriate source.
	var item_type: int = -1
	var count: int = 0
	if grid_id == GRID_PLAYER:
		if slot_idx < inventory.slots.size():
			var slot: ItemStack = inventory.slots[slot_idx]
			item_type = slot.item_type
			count = slot.count
	elif grid_id == GRID_CHEST:
		var views: Array = _chest_slot_views()
		if slot_idx < views.size():
			item_type = int(views[slot_idx]["item_type"])
			count = int(views[slot_idx]["count"])

	var is_empty: bool = item_type < 0 or count <= 0
	var bg: Color = SLOT_BG_EMPTY if is_empty else SLOT_BG
	draw_rect(rect, bg, true)
	# Hover highlight wins.
	var hovered: bool = (_hover_grid == grid_id and _hover_slot == slot_idx)
	var border: Color = SLOT_BORDER_HOVER if hovered else SLOT_BORDER
	var border_w: float = 2.0 if hovered else 1.0
	draw_rect(rect, border, false, border_w)
	if is_empty:
		return
	# Item swatch — centered.
	var swatch_inset: float = (SLOT_SIZE - 32) * 0.5
	var swatch_rect: Rect2 = Rect2(rect.position + Vector2(swatch_inset, swatch_inset), Vector2(32, 32))
	draw_rect(swatch_rect, Items.color_of(item_type), true)
	draw_rect(swatch_rect, Color.BLACK, false, 1.0)
	# Count overlay — bottom-right of slot. With HORIZONTAL_ALIGNMENT_RIGHT
	# the text flushes to position.x + alignment_width, so the alignment
	# region's RIGHT EDGE is what we want at slot.x + SLOT_SIZE - 4. The
	# position.x is therefore offset back by alignment_width.
	var count_str: String = str(count)
	var alignment_width: int = SLOT_SIZE - 8
	var count_pos: Vector2 = rect.position + Vector2(4, SLOT_SIZE - 4)
	draw_string(font, count_pos + Vector2(1, 1), count_str,
		HORIZONTAL_ALIGNMENT_RIGHT, alignment_width, 14, COUNT_SHADOW)
	draw_string(font, count_pos, count_str,
		HORIZONTAL_ALIGNMENT_RIGHT, alignment_width, 14, COUNT_COLOR)

func _draw_cursor_stack(font: Font) -> void:
	# Floating swatch + count at mouse position. Drawn 32×32 like the
	# slot's centered swatch, so the cursor "looks like" what it'll
	# become when placed. Count sits just below-right of the swatch with
	# left-alignment (no rectangle math) so it always reads near the cursor.
	var mouse_pos: Vector2 = get_local_mouse_position()
	var swatch_rect: Rect2 = Rect2(mouse_pos - Vector2(16, 16), Vector2(32, 32))
	draw_rect(swatch_rect, Items.color_of(cursor.item_type), true)
	draw_rect(swatch_rect, Color.BLACK, false, 1.0)
	var count_str: String = str(cursor.count)
	var count_pos: Vector2 = mouse_pos + Vector2(8, 18)
	draw_string(font, count_pos + Vector2(1, 1), count_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COUNT_SHADOW)
	draw_string(font, count_pos, count_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COUNT_COLOR)

func _draw_tooltip(font: Font, item_type: int, count: int) -> void:
	var name: String = Items.name_of(item_type)
	var max_stack: int = Items.max_stack_of(item_type)
	var label: String = "%s: %d / %d" % [name, count, max_stack]
	# Position tooltip near cursor but offset so it doesn't sit under it.
	var mouse_pos: Vector2 = get_local_mouse_position()
	var tooltip_w: int = 180
	var tooltip_h: int = 24
	var tooltip_pos: Vector2 = mouse_pos + Vector2(16, 16)
	# Clamp tooltip into screen bounds so it doesn't fall off the right edge.
	var view_size: Vector2 = get_viewport_rect().size
	if tooltip_pos.x + tooltip_w > view_size.x:
		tooltip_pos.x = view_size.x - tooltip_w - 4
	if tooltip_pos.y + tooltip_h > view_size.y:
		tooltip_pos.y = view_size.y - tooltip_h - 4
	var tooltip_rect: Rect2 = Rect2(tooltip_pos, Vector2(tooltip_w, tooltip_h))
	draw_rect(tooltip_rect, TOOLTIP_BG, true)
	draw_rect(tooltip_rect, TOOLTIP_BORDER, false, 1.0)
	draw_string(font, tooltip_pos + Vector2(8, 17), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TOOLTIP_TEXT)
