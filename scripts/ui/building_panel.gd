class_name BuildingPanel
extends Control

## Base class for building interaction modals (session-building-ui-1).
##
## Provides:
##   - Modal lifecycle (open/close), full-screen dim overlay, MOUSE_FILTER_STOP
##   - Player inventory grid rendered at bottom (slot widget reuse)
##   - Drag-drop with kind-validation (input/output/fuel) + lossy fuel take-back
##   - Shared CursorStack so picked-up items survive modal switches
##   - Click resolution + slot_layout-driven generic render
##
## Subclasses (smelter_panel.gd, drill_panel.gd) override:
##   - _draw_building_specific(area)  — paints widgets in the upper region
##                                       (progress bar, coverage display, etc.)
##   - _slot_rect_for(slot_def, sub_idx) — positions slot widgets
##                                          building-specifically
##
## All buildings share the bottom player-inventory grid + the slot_layout-
## driven drag-drop logic. Building-specific layout is the upper region.

const TITLE_HEIGHT: int = 32
const PADDING: int = 16
const PLAYER_GRID_COLS: int = 4
const PLAYER_GRID_GAP: int = 4
const SECTION_GAP: int = 12
const FUEL_PORT_LABEL_HEIGHT: int = 18

# Color palette (consistent with inventory_grid).
const PANEL_BG: Color = Color(0.08, 0.08, 0.10, 0.96)
const PANEL_BORDER: Color = Color(0.55, 0.55, 0.55, 0.95)
const DIM_OVERLAY: Color = Color(0, 0, 0, 0.55)
const TITLE_COLOR: Color = Color(1.00, 0.92, 0.55)
const TEXT_COLOR: Color = Color(0.95, 0.95, 0.85)
const TEXT_DIM: Color = Color(0.60, 0.60, 0.55)
const STATUS_GOOD: Color = Color(0.55, 0.85, 0.55)
const STATUS_WARN: Color = Color(1.00, 0.85, 0.30)
const STATUS_BAD: Color = Color(1.00, 0.45, 0.45)

# Externally-set refs (main.gd populates after _ready).
var cursor: CursorStack = null
var inventory: Inventory = null
var toast_callback: Callable = Callable()

# Building this panel is currently bound to. Set by open(); cleared by close().
var building: Building = null
var world: Node = null

# Hover tracking — encoded as Variant. Same pattern as inventory_grid:
# Dictionary {kind, idx} for building slots, int for inventory slot, -1 = none.
var _hover: Variant = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Anchor full-screen so the dim overlay covers everything.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

# ---------- public API ----------

func open(b: Building, w: Node) -> void:
	building = b
	world = w
	visible = true
	_hover = -1
	queue_redraw()

func close() -> void:
	# Cursor persists across close — see CursorStack docs. Player drops via
	# explicit click in next modal, or right-click in NEUTRAL mode (future).
	visible = false
	building = null
	world = null
	_hover = -1

func is_open() -> bool:
	return visible

# ---------- layout ----------

const PANEL_W: int = 640
const PANEL_TOP_AREA_H_DEFAULT: int = 280     # subclass override via _top_area_height()

## Subclass override hook — buildings whose top area needs more vertical
## room (e.g., ChestPanel's bag grid) override this to widen the panel.
## Default 280px fits typical Processor layouts (input+output+fuel+status).
func _top_area_height() -> int:
	return PANEL_TOP_AREA_H_DEFAULT

func _player_grid_rect() -> Rect2:
	# Player inventory grid sits at the bottom of the panel.
	var view_size: Vector2 = get_viewport_rect().size
	var slot: int = SlotWidget.SIZE
	var rows: int = int(ceil(float(inventory.capacity) / float(PLAYER_GRID_COLS))) if inventory != null else 4
	var grid_h: int = rows * slot + (rows - 1) * PLAYER_GRID_GAP
	var grid_w: int = PLAYER_GRID_COLS * slot + (PLAYER_GRID_COLS - 1) * PLAYER_GRID_GAP
	var top_area_h: int = _top_area_height()
	var panel_h: int = PADDING + TITLE_HEIGHT + top_area_h + SECTION_GAP + 24 + grid_h + PADDING
	var panel_x: float = (view_size.x - PANEL_W) * 0.5
	var panel_y: float = (view_size.y - panel_h) * 0.5
	var grid_x: float = panel_x + (PANEL_W - grid_w) * 0.5
	var grid_y: float = panel_y + PADDING + TITLE_HEIGHT + top_area_h + SECTION_GAP + 24
	return Rect2(grid_x, grid_y, grid_w, grid_h)

func _panel_rect() -> Rect2:
	var view_size: Vector2 = get_viewport_rect().size
	var slot: int = SlotWidget.SIZE
	var rows: int = int(ceil(float(inventory.capacity) / float(PLAYER_GRID_COLS))) if inventory != null else 4
	var grid_h: int = rows * slot + (rows - 1) * PLAYER_GRID_GAP
	var top_area_h: int = _top_area_height()
	var panel_h: int = PADDING + TITLE_HEIGHT + top_area_h + SECTION_GAP + 24 + grid_h + PADDING
	var panel_x: float = (view_size.x - PANEL_W) * 0.5
	var panel_y: float = (view_size.y - panel_h) * 0.5
	return Rect2(panel_x, panel_y, PANEL_W, panel_h)

func _top_area_rect() -> Rect2:
	# Region above the player inventory where the building-specific layout
	# renders (slots, progress bars, status text).
	var p: Rect2 = _panel_rect()
	return Rect2(
		p.position.x + PADDING,
		p.position.y + PADDING + TITLE_HEIGHT,
		p.size.x - PADDING * 2,
		_top_area_height(),
	)

func _player_slot_rect(slot_idx: int) -> Rect2:
	var grid: Rect2 = _player_grid_rect()
	var col: int = slot_idx % PLAYER_GRID_COLS
	var row: int = slot_idx / PLAYER_GRID_COLS
	var x: float = grid.position.x + col * (SlotWidget.SIZE + PLAYER_GRID_GAP)
	var y: float = grid.position.y + row * (SlotWidget.SIZE + PLAYER_GRID_GAP)
	return Rect2(x, y, SlotWidget.SIZE, SlotWidget.SIZE)

# ---------- slot resolution (subclass override) ----------

## Default building slot layout: lay out slots horizontally in the top area.
## Smelter and drill override this for specialized layouts (smelter has flow
## arrows; drill has coverage panel).
##
## Subclass returns: Array of {slot_def: Dict, rect: Rect2, sub_idx: int}.
##   slot_def is one entry from Buildings.slot_layout_for(b.type).
##   For "output_multi" kind, multi_count entries are emitted (one per sub_idx).
func _building_slot_rects() -> Array:
	var out: Array = []
	if building == null:
		return out
	var layout: Array = Buildings.slot_layout_for(building.type)
	var area: Rect2 = _top_area_rect()
	var x: float = area.position.x
	var y: float = area.position.y + 30   # below title-area-height padding
	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		if kind == "output_multi":
			var n: int = int(slot_def.get("multi_count", 1))
			for sub_idx in n:
				out.append({"slot_def": slot_def, "rect": Rect2(x, y, SlotWidget.SIZE, SlotWidget.SIZE), "sub_idx": sub_idx})
				x += SlotWidget.SIZE + 8
		else:
			out.append({"slot_def": slot_def, "rect": Rect2(x, y, SlotWidget.SIZE, SlotWidget.SIZE), "sub_idx": -1})
			x += SlotWidget.SIZE + 24
	return out

## Subclass override hook — paint progress bars, coverage panel, status
## text, etc. in the top area. Default does nothing.
func _draw_building_specific(_area: Rect2, _font: Font) -> void:
	pass

# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if not visible or building == null or inventory == null or cursor == null:
		return
	if event is InputEventMouseMotion:
		_hover = _hit_test(event.position)
		queue_redraw()
		return
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		var hit = _hit_test(event.position)
		if hit is int and hit < 0:
			# Click outside any slot — close panel (cursor persists).
			close()
			return
		if hit is int:
			# Player inventory slot.
			_handle_player_slot_click(int(hit))
		elif hit is Dictionary:
			# Building slot.
			_handle_building_slot_click(hit)

func _hit_test(pos: Vector2) -> Variant:
	# Player inventory slots first.
	if inventory != null:
		for i in inventory.slots.size():
			if _player_slot_rect(i).has_point(pos):
				return i
	# Building slots.
	for entry in _building_slot_rects():
		if (entry["rect"] as Rect2).has_point(pos):
			return entry
	return -1

# ---------- click: player inventory slot ----------
# Same semantics as inventory_grid._handle_left_click_player but inlined here
# (avoids cross-modal coupling; both modals share CursorStack and slot_widget
# rendering, but click handlers stay local for clarity).

func _handle_player_slot_click(slot_idx: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	if not cursor.has_item():
		if slot.is_empty():
			return
		cursor.pick(slot.item_type, slot.count)
		slot.clear()
		queue_redraw()
		return
	if slot.is_empty():
		slot.item_type = cursor.item_type
		slot.count = cursor.count
		cursor.clear()
	elif slot.item_type == cursor.item_type:
		var max_stack: int = Items.max_stack_of(slot.item_type)
		var space: int = max_stack - slot.count
		var moved: int = min(space, cursor.count)
		slot.count += moved
		cursor.count -= moved
		if cursor.count <= 0:
			cursor.clear()
	else:
		var tmp_t: int = slot.item_type
		var tmp_c: int = slot.count
		slot.item_type = cursor.item_type
		slot.count = cursor.count
		cursor.pick(tmp_t, tmp_c)
	queue_redraw()

# ---------- click: building slot ----------

func _handle_building_slot_click(hit: Dictionary) -> void:
	var slot_def: Dictionary = hit["slot_def"]
	var sub_idx: int = int(hit.get("sub_idx", -1))
	var kind: String = str(slot_def.get("kind", ""))
	# Cursor empty → take from this slot (if applicable).
	if not cursor.has_item():
		_take_from_slot(slot_def, sub_idx)
		queue_redraw()
		return
	# Cursor has item → drop into this slot (if it accepts).
	_drop_into_slot(slot_def, sub_idx)
	queue_redraw()

# ---------- drop validation + commit ----------

## Try to drop the cursor stack into the given slot. Validates kind + accepts;
## toasts on rejection.
func _drop_into_slot(slot_def: Dictionary, sub_idx: int) -> void:
	var kind: String = str(slot_def.get("kind", ""))
	# Output slots are read-only.
	if kind == "output" or kind == "output_multi":
		_toast("Output slot is read-only — items appear here as the building produces them.")
		return
	# Check accepts list.
	var accepts: Array = slot_def.get("accepts", [])
	if not accepts.is_empty() and not (cursor.item_type in accepts):
		var names: Array = []
		for t in accepts:
			names.append(Items.name_of(int(t)))
		_toast("This slot accepts: %s" % ", ".join(names))
		return
	# Kind-specific commit.
	match kind:
		"input":
			_drop_into_input(slot_def)
		"fuel":
			_drop_into_fuel(slot_def)
		_:
			_toast("Slot does not accept items.")

## Append cursor's stack into b.state[state_field] (a buffer of [type, count]).
## Respects max_stack. Cursor decrements by the amount actually accepted.
func _drop_into_input(slot_def: Dictionary) -> void:
	var field: String = str(slot_def.get("state_field", "in_buffer"))
	var max_stack: int = int(slot_def.get("max_stack", 8))
	var buf: Array = building.state.get(field, [])
	var current: int = _buffer_count(buf, cursor.item_type)
	var space: int = max_stack - current
	if space <= 0:
		_toast("%s slot is full." % Items.name_of(cursor.item_type))
		return
	var moved: int = min(space, cursor.count)
	_buffer_add(buf, cursor.item_type, moved)
	building.state[field] = buf
	cursor.count -= moved
	if cursor.count <= 0:
		cursor.clear()

## Convert cursor's items to fuel units, deposit into b.state.fuel_buffer.
## Respects FUEL_BUFFER_CAPACITY. 1 wood = 1 unit, 1 coal = 4, 1 briquette = 8.
## Refuses partial-conversion items (player drops 5 coals, only 3 fit in
## terms of units (12 of 16) — accepts 3 coals, rejects 2 with toast).
func _drop_into_fuel(slot_def: Dictionary) -> void:
	if not Burner.FUEL_VALUES.has(cursor.item_type):
		_toast("That item isn't fuel.")
		return
	var energy_per: int = int(Burner.FUEL_VALUES[cursor.item_type])
	var max_units: int = int(slot_def.get("max_stack", Burner.FUEL_BUFFER_CAPACITY))
	var current_units: int = int(building.state.get("fuel_buffer", 0))
	var free_units: int = max_units - current_units
	if free_units <= 0:
		_toast("Fuel slot is full.")
		return
	# How many items can fit (atomic — can't split a coal into half-coals).
	var items_that_fit: int = free_units / energy_per
	if items_that_fit <= 0:
		_toast("Fuel slot too full to accept %s (1 = %d units)." % [Items.name_of(cursor.item_type), energy_per])
		return
	var moved_items: int = min(items_that_fit, cursor.count)
	building.state["fuel_buffer"] = current_units + moved_items * energy_per
	# Track for display: fuel_buffer stores generic energy units, but the
	# slot UI needs an item type to render an icon. Mirror what the auto-
	# pull path (Burner._try_pull_from_*) records.
	building.state["last_fuel_item"] = cursor.item_type
	cursor.count -= moved_items
	if cursor.count <= 0:
		cursor.clear()

## Take from a slot to the cursor.
func _take_from_slot(slot_def: Dictionary, sub_idx: int) -> void:
	var kind: String = str(slot_def.get("kind", ""))
	var field: String = str(slot_def.get("state_field", ""))
	match kind:
		"input", "output":
			# Pull whichever item type is in the buffer (one entry — any type).
			var buf: Array = building.state.get(field, [])
			if buf.is_empty():
				return
			var entry = buf[0]
			cursor.pick(int(entry[0]), int(entry[1]))
			buf.clear()
			building.state[field] = buf
		"output_multi":
			# Pull the sub_idx'th entry from the multi-bag. Entries shift up
			# when an entry is removed (Array.remove_at handles this).
			var buf2: Array = building.state.get(field, [])
			if sub_idx < 0 or sub_idx >= buf2.size():
				return
			var entry2 = buf2[sub_idx]
			cursor.pick(int(entry2[0]), int(entry2[1]))
			buf2.remove_at(sub_idx)
			building.state[field] = buf2
		"fuel":
			# Lossy take-back per Q7 pushback: convert fuel_buffer units to
			# wood equivalent (1 unit = 1 wood). Player who loaded coal accepts
			# the efficiency loss on retrieval — simpler than tracking loaded
			# items, no UX trap from auto-conversion accidents.
			var units: int = int(building.state.get("fuel_buffer", 0))
			if units <= 0:
				return
			cursor.pick(Items.Type.WOOD, units)
			building.state["fuel_buffer"] = 0
			building.state["fuel_burn_progress"] = 0
			_toast("Retrieved %d wood (lossy: 1 fuel unit = 1 wood)." % units)

# ---------- buffer helpers (Array of [type, count]) ----------

static func _buffer_count(buf: Array, item_type: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _buffer_add(buf: Array, item_type: int, count: int) -> void:
	for entry in buf:
		if int(entry[0]) == item_type:
			entry[1] = int(entry[1]) + count
			return
	buf.append([item_type, count])

# ---------- toast wrapper ----------

func _toast(msg: String) -> void:
	if toast_callback.is_valid():
		toast_callback.call(msg)

# ---------- shared fluid_indicator widget ----------
#
# Render a fluid-connection indicator (filled dot if pipe-fed, hollow ring if
# not) + a name label. Used by ANY panel that has a fluid_indicator slot in
# its slot_layout — extracted here so MixerPanel and ProcessorPanel-fluid
# (Retter, Yeast Culture) share one source of truth for "how a fluid input
# looks." Refactoring a single helper > divergent renders.
#
# Returns the Y-coordinate just below the rendered widget so the caller can
# stack subsequent rows without overlapping.

const FLUID_DOT_RADIUS: float = 6.0
const FLUID_CONNECTED: Color = Color(0.30, 0.70, 1.00)    # blue (active)
const FLUID_NONE: Color = Color(0.45, 0.45, 0.48)         # gray (no pipe)
const FLUID_ROW_HEIGHT: int = 22

## Draw the fluid indicator at (origin_x, origin_y). Reads the building's
## pipe-network state via world.fluid_available_for_building.
##
## Returns origin_y + FLUID_ROW_HEIGHT for callers that want to stack
## additional rows below.
func draw_fluid_indicator(font: Font, slot_def: Dictionary, origin_x: float, origin_y: float) -> float:
	var fluid_type: int = int(slot_def.get("fluid_type", Fluids.Type.WATER))
	var connected: bool = false
	if world != null and building != null:
		connected = world.fluid_available_for_building(building, fluid_type)
	var dot_color: Color = FLUID_CONNECTED if connected else FLUID_NONE
	var dot_pos: Vector2 = Vector2(origin_x + 6.0, origin_y + 7.0)
	if connected:
		draw_circle(dot_pos, FLUID_DOT_RADIUS, dot_color)
	else:
		draw_arc(dot_pos, FLUID_DOT_RADIUS, 0.0, TAU, 16, dot_color, 2.0)
	var label: String = "%s: %s" % [
		Fluids.name_of(fluid_type),
		"connected" if connected else "no pipe network",
	]
	var label_color: Color = TEXT_COLOR if connected else TEXT_DIM
	draw_string(font, Vector2(origin_x + 22.0, origin_y + 12.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_color)
	return origin_y + FLUID_ROW_HEIGHT

# ---------- rendering ----------

func _draw() -> void:
	if building == null or inventory == null:
		return
	var view_size: Vector2 = get_viewport_rect().size
	# Full-screen dim overlay.
	draw_rect(Rect2(Vector2.ZERO, view_size), DIM_OVERLAY, true)

	var font: Font = ThemeDB.fallback_font
	var panel: Rect2 = _panel_rect()
	draw_rect(panel, PANEL_BG, true)
	draw_rect(panel, PANEL_BORDER, false, 2.0)

	# Title — centered.
	var title: String = Buildings.name_of(building.type)
	draw_string(font, panel.position + Vector2(0, PADDING + 22), title,
		HORIZONTAL_ALIGNMENT_CENTER, int(panel.size.x), 20, TITLE_COLOR)

	# Top area — building-specific layout (subclass override).
	# Default: render slots horizontally in the top area.
	var area: Rect2 = _top_area_rect()
	_draw_building_specific(area, font)
	# Generic slot render — only renders if subclass didn't already draw
	# slots (subclass overrides _building_slot_rects to provide custom positions).
	_draw_slots(font)

	# Player inventory section.
	var grid: Rect2 = _player_grid_rect()
	# "Inventory" label.
	draw_string(font, Vector2(grid.position.x, grid.position.y - 8), "Inventory",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)
	for i in inventory.slots.size():
		var slot: ItemStack = inventory.slots[i]
		var rect: Rect2 = _player_slot_rect(i)
		var hovered: bool = (_hover is int and int(_hover) == i)
		SlotWidget.draw_slot(self, font, rect, slot.item_type, slot.count, hovered)

	# Cursor stack — drawn last so it floats above.
	SlotWidget.draw_cursor_stack(self, font, get_local_mouse_position(), cursor)

func _draw_slots(font: Font) -> void:
	for entry in _building_slot_rects():
		var slot_def: Dictionary = entry["slot_def"]
		var rect: Rect2 = entry["rect"]
		var sub_idx: int = int(entry.get("sub_idx", -1))
		var kind: String = str(slot_def.get("kind", ""))
		var item_type: int = -1
		var count: int = 0
		var field: String = str(slot_def.get("state_field", ""))
		match kind:
			"input", "output":
				var buf: Array = building.state.get(field, [])
				if not buf.is_empty():
					item_type = int(buf[0][0])
					count = int(buf[0][1])
			"output_multi":
				var buf2: Array = building.state.get(field, [])
				if sub_idx >= 0 and sub_idx < buf2.size():
					item_type = int(buf2[sub_idx][0])
					count = int(buf2[sub_idx][1])
			"fuel":
				var units: int = int(building.state.get(field, 0))
				if units > 0:
					# fuel_buffer stores energy units, not items. Use last_fuel_item
					# (set by drag-drop and Burner pull paths) to pick the icon, and
					# render `count` as item-equivalents (units / energy_per_item) so
					# coal shows "COAL ×3" not "COAL ×12 (units)".
					var last: int = int(building.state.get("last_fuel_item", -1))
					if last >= 0 and Burner.FUEL_VALUES.has(last):
						item_type = last
						var energy_per: int = int(Burner.FUEL_VALUES[last])
						# Floor division — if buffer has a partial unit (e.g., 3 units
						# left after burning 1 of 4 from a coal), we under-report by 1
						# rather than overstate. Caller reads the precise unit count
						# from the panel's Fuel-units text line.
						count = units / energy_per
						# Edge case: 1-3 units left from coal-tier burns shouldn't
						# show ×0; bump to 1 to keep the icon meaningful.
						if count <= 0:
							count = 1
					else:
						# Defensive fallback (shouldn't happen post-fix, but handles
						# old saves where last_fuel_item is missing).
						item_type = Items.Type.WOOD
						count = units
		# Hover highlight.
		var hovered: bool = false
		if _hover is Dictionary:
			var h: Dictionary = _hover
			if h.get("slot_def", {}) == slot_def and int(h.get("sub_idx", -1)) == sub_idx:
				hovered = true
		var border_tint: Color = SlotWidget.border_for_kind(kind)
		SlotWidget.draw_slot(self, font, rect, item_type, count, hovered, border_tint)
