extends Control

## Modal Factorio-style slot grid for the player inventory.
##
## Visualizes the per-slot reality of `Inventory` (which has always been
## slot-by-slot, max_stack-enforced — the aggregate inventory_panel hid
## that). Lets the player pick up, place, swap, and combine stacks via
## click. Cursor stack persists across modal close (shared CursorStack
## with all building panels via main.gd).
##
## Layout: fixed 4-column grid, rows = ceil(capacity / 4). Each bag
## consumed grants +4 slots = exactly +1 row, so bag rewards are
## visually obvious as the grid grows downward.
##
## Toggle: I (or Esc) opens / closes. While open: world clicks blocked by
## a dim overlay; player movement gated by `inventory_grid.visible`.
##
## History (session-building-ui-2): Chest paired-view was REMOVED from this
## file. Chest interaction now lives in scripts/ui/chest_panel.gd; the bag→
## slot-views adapter moved to SlotWidget.chest_bag_to_slot_views. This file
## now does ONE thing: render the player inventory.

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

# Cursor stack — shared across all modals (set by main.gd, same instance
# bound to every BuildingPanel subclass). Picks up wood here → can drop into
# smelter fuel slot without "dropping" mid-flow.
var cursor: CursorStack = null

# Hover state — slot index, -1 if no slot under cursor.
var _hover_slot: int = -1

# Set by main.gd before first show.
var inventory: Inventory = null

# Set by main.gd to push toasts up to the player's HUD.
var toast_callback: Callable = Callable()

func _ready() -> void:
	# Modal: full-screen overlay so clicks outside the grid don't leak to
	# the world. mouse_filter STOP catches clicks at the root.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

# ---------- public API ----------

## Toggle visibility. main.gd calls this on I/Esc.
func toggle() -> void:
	if visible:
		_close()
	else:
		_open()

func is_open() -> bool:
	return visible

# ---------- open / close ----------

func _open() -> void:
	visible = true
	_hover_slot = -1
	queue_redraw()

func _close() -> void:
	# Cursor stack persists across modal close (session-building-ui-1).
	visible = false
	_hover_slot = -1

func _toast(msg: String) -> void:
	if toast_callback.is_valid():
		toast_callback.call(msg)

# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if not visible or inventory == null or cursor == null:
		return
	if event is InputEventMouseMotion:
		_hover_slot = _slot_under(event.position)
		queue_redraw()
		return
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		var slot_idx: int = _slot_under(event.position)
		if slot_idx < 0:
			# Click outside any slot — close (cursor persists).
			_close()
			return
		_handle_left_click_player(slot_idx, _extract_mods(event))

## Player-grid left click: full pick / place / combine / swap semantics.
func _handle_left_click_player(slot_idx: int, mods: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	SlotClickHandler.handle_player_slot(slot, cursor, mods)
	queue_redraw()

# ---------- geometry ----------

func _grid_origin() -> Vector2:
	var view_size: Vector2 = get_viewport_rect().size
	var rows: int = _row_count()
	var grid_w: int = COLS * SLOT_SIZE + (COLS - 1) * SLOT_GAP
	var grid_h: int = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP
	var panel_w: int = grid_w + PADDING * 2
	var panel_h: int = grid_h + PADDING * 2 + TITLE_HEIGHT + FOOTER_HEIGHT
	return Vector2((view_size.x - panel_w) * 0.5, (view_size.y - panel_h) * 0.5)

func _row_count() -> int:
	if inventory == null:
		return 4
	return int(ceil(float(inventory.capacity) / float(COLS)))

func _slot_rect(slot_idx: int) -> Rect2:
	var origin: Vector2 = _grid_origin()
	var grid_top: float = origin.y + PADDING + TITLE_HEIGHT
	var grid_left: float = origin.x + PADDING
	var col: int = slot_idx % COLS
	var row: int = slot_idx / COLS
	var x: float = grid_left + col * (SLOT_SIZE + SLOT_GAP)
	var y: float = grid_top + row * (SLOT_SIZE + SLOT_GAP)
	return Rect2(x, y, SLOT_SIZE, SLOT_SIZE)

## Returns slot index under cursor, or -1 if none.
func _slot_under(pos: Vector2) -> int:
	if inventory == null:
		return -1
	for i in inventory.slots.size():
		if _slot_rect(i).has_point(pos):
			return i
	return -1

# ---------- rendering ----------

func _draw() -> void:
	if inventory == null:
		return
	var view_size: Vector2 = get_viewport_rect().size
	# Full-screen dim overlay — clicks on it trigger _gui_input → _close.
	draw_rect(Rect2(Vector2.ZERO, view_size), DIM_OVERLAY, true)

	var font: Font = ThemeDB.fallback_font
	_draw_panel(font)

	# Cursor stack — drawn last so it floats above slots.
	if cursor != null and cursor.has_item():
		_draw_cursor_stack(font)

	# Hover tooltip — slot under cursor with non-empty content.
	if _hover_slot >= 0 and _hover_slot < inventory.slots.size():
		var hovered: ItemStack = inventory.slots[_hover_slot]
		if not hovered.is_empty():
			_draw_tooltip(font, hovered.item_type, hovered.count)

func _draw_panel(font: Font) -> void:
	var rows: int = _row_count()
	var grid_w: int = COLS * SLOT_SIZE + (COLS - 1) * SLOT_GAP
	var grid_h: int = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP
	var panel_w: int = grid_w + PADDING * 2
	var panel_h: int = grid_h + PADDING * 2 + TITLE_HEIGHT + FOOTER_HEIGHT
	var origin: Vector2 = _grid_origin()
	var panel_rect: Rect2 = Rect2(origin, Vector2(panel_w, panel_h))
	draw_rect(panel_rect, PANEL_BG, true)
	draw_rect(panel_rect, PANEL_BORDER, false, 2.0)
	draw_string(font, origin + Vector2(PADDING, PADDING + 16), "Inventory",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TITLE_COLOR)
	for i in inventory.slots.size():
		_draw_slot(font, i)

func _draw_slot(font: Font, slot_idx: int) -> void:
	var rect: Rect2 = _slot_rect(slot_idx)
	var slot: ItemStack = inventory.slots[slot_idx]
	var hovered: bool = (_hover_slot == slot_idx)
	SlotWidget.draw_slot(self, font, rect, slot.item_type, slot.count, hovered)

func _draw_cursor_stack(font: Font) -> void:
	SlotWidget.draw_cursor_stack(self, font, get_local_mouse_position(), cursor)

func _draw_tooltip(font: Font, item_type: int, count: int) -> void:
	var name: String = Items.name_of(item_type)
	var max_stack: int = Items.max_stack_of(item_type)
	var label: String = "%s: %d / %d" % [name, count, max_stack]
	var mouse_pos: Vector2 = get_local_mouse_position()
	var tooltip_w: int = 180
	var tooltip_h: int = 24
	var tooltip_pos: Vector2 = mouse_pos + Vector2(16, 16)
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

## Extract a SlotClickHandler.MOD_* bitfield from a MouseButton event.
static func _extract_mods(event: InputEventMouseButton) -> int:
	var mods: int = SlotClickHandler.MOD_NONE
	if event.shift_pressed:
		mods |= SlotClickHandler.MOD_SHIFT
	if event.ctrl_pressed:
		mods |= SlotClickHandler.MOD_CTRL
	return mods
