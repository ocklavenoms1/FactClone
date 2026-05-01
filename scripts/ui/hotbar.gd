extends Control

## Hotbar — categorized slots with Tab/Shift-Tab category switching.
##
## Layout:
##   Categories run left-to-right (Terrain · Logistics · Production · Storage).
##   Number keys 1..9 select within the *active* category.
##   Tab cycles to next category, Shift+Tab to previous.
##   Each category remembers its own last selection.
##
## Each slot is a dict { "kind": String, "value": int }:
##   kind = "terrain"  -> value is a Terrain.Overlay (player paints overlays)
##   kind = "building" -> value is a Buildings.Type

const SLOT_SIZE: int = 56
const SLOT_GAP: int = 6
const SLOTS_PER_CATEGORY_MAX: int = 9
const SLOT_BG: Color = Color(0.10, 0.10, 0.10, 0.85)
const SLOT_BORDER: Color = Color(0.60, 0.60, 0.60, 0.90)
const SLOT_BORDER_SELECTED: Color = Color(1.00, 0.92, 0.40, 1.00)
const HEADER_BG: Color = Color(0.10, 0.10, 0.10, 0.85)
const HEADER_TEXT: Color = Color(1.00, 0.92, 0.55)
const HEADER_DIM: Color = Color(0.55, 0.55, 0.55)
const HEADER_HEIGHT: int = 22
const LABEL_HEIGHT: int = 16

signal selection_changed(kind: String, value: int)

var categories: Array = []   # [{ "name": String, "slots": Array, "selected": int }]
var current_category: int = 0

func _ready() -> void:
	_build_categories()
	_apply_layout()
	queue_redraw()

func _build_categories() -> void:
	categories = []

	var terrain_slots: Array = []
	for overlay_value in Terrain.HOTBAR_ORDER:
		terrain_slots.append({ "kind": "terrain", "value": overlay_value })
	categories.append({ "name": "Terrain", "slots": terrain_slots, "selected": 0 })

	categories.append({
		"name": "Logistics",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.BELT },
			{ "kind": "building", "value": Buildings.Type.PIPE },
		],
		"selected": 0,
	})

	categories.append({
		"name": "Production",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.PLANTER },
			{ "kind": "building", "value": Buildings.Type.HARVESTER },
			{ "kind": "building", "value": Buildings.Type.MILL },
			{ "kind": "building", "value": Buildings.Type.MIXER },
			{ "kind": "building", "value": Buildings.Type.PUMP },
		],
		"selected": 0,
	})

	categories.append({
		"name": "Storage",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.CHEST },
		],
		"selected": 0,
	})

func _apply_layout() -> void:
	var w: int = _max_row_width()
	custom_minimum_size = Vector2(w, HEADER_HEIGHT + SLOT_SIZE + LABEL_HEIGHT + 8)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -(HEADER_HEIGHT + SLOT_SIZE + LABEL_HEIGHT + 8) - 12
	offset_bottom = -12

func _max_row_width() -> int:
	var max_slots: int = 0
	for cat in categories:
		max_slots = max(max_slots, cat["slots"].size())
	max_slots = max(max_slots, 4)  # never collapse to a sliver
	return max_slots * SLOT_SIZE + (max_slots - 1) * SLOT_GAP

# ---------- input ----------

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("next_category"):
		_cycle_category(1)
	if Input.is_action_just_pressed("prev_category"):
		_cycle_category(-1)
	for i in SLOTS_PER_CATEGORY_MAX:
		var action: String = "hotbar_%d" % (i + 1)
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			set_selection_in_current(i)

func _cycle_category(delta: int) -> void:
	var n: int = categories.size()
	if n <= 0:
		return
	current_category = ((current_category + delta) % n + n) % n
	queue_redraw()
	_emit_changed()

func set_selection_in_current(idx: int) -> void:
	var slots: Array = categories[current_category]["slots"]
	if idx < 0 or idx >= slots.size():
		return
	if idx == int(categories[current_category]["selected"]):
		return
	categories[current_category]["selected"] = idx
	queue_redraw()
	_emit_changed()

func _emit_changed() -> void:
	selection_changed.emit(current_kind(), current_value())

# ---------- public api (unchanged surface for main.gd) ----------

func current_slot() -> Dictionary:
	var slots: Array = categories[current_category]["slots"]
	return slots[int(categories[current_category]["selected"])]

func current_kind() -> String:
	return current_slot()["kind"]

func current_value() -> int:
	return current_slot()["value"]

func current_label() -> String:
	var s = current_slot()
	return Terrain.overlay_name(s["value"]) if s["kind"] == "terrain" else Buildings.name_of(s["value"])

# ---------- visual ----------

func _color_for(slot: Dictionary) -> Color:
	return Terrain.overlay_color(slot["value"]) if slot["kind"] == "terrain" else Buildings.swatch_color_of(slot["value"])

func _label_for(slot: Dictionary) -> String:
	return Terrain.overlay_name(slot["value"]) if slot["kind"] == "terrain" else Buildings.name_of(slot["value"])

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var w: int = _max_row_width()

	# Header — single centered string, no overlap risk for any category name length.
	var header_rect: Rect2 = Rect2(0, 0, w, HEADER_HEIGHT)
	draw_rect(header_rect, HEADER_BG, true)
	var header_text: String = "◀  [ %s ]  ▶" % categories[current_category]["name"]
	draw_string(font, Vector2(0, HEADER_HEIGHT - 6), header_text, HORIZONTAL_ALIGNMENT_CENTER, w, 14, HEADER_TEXT)

	# Slots row — center the row within the panel width.
	var slots: Array = categories[current_category]["slots"]
	var selected_idx: int = int(categories[current_category]["selected"])
	var row_w: int = slots.size() * SLOT_SIZE + (slots.size() - 1) * SLOT_GAP
	var row_x: int = int((w - row_w) * 0.5)
	var row_y: int = HEADER_HEIGHT + 4

	for i in slots.size():
		var x: float = row_x + i * (SLOT_SIZE + SLOT_GAP)
		var slot_rect: Rect2 = Rect2(x, row_y, SLOT_SIZE, SLOT_SIZE)
		draw_rect(slot_rect, SLOT_BG, true)
		var border := SLOT_BORDER_SELECTED if i == selected_idx else SLOT_BORDER
		var border_width: float = 3.0 if i == selected_idx else 1.5
		draw_rect(slot_rect, border, false, border_width)

		# Color swatch.
		var swatch_rect: Rect2 = Rect2(x + 8, row_y + 8, SLOT_SIZE - 16, SLOT_SIZE - 28)
		draw_rect(swatch_rect, _color_for(slots[i]), true)
		if slots[i]["kind"] == "building":
			draw_rect(swatch_rect, Color.BLACK, false, 1.5)

		# Slot number.
		draw_string(font, Vector2(x + 6, row_y + SLOT_SIZE - 6), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		# Item label below the slot.
		draw_string(font, Vector2(x, row_y + SLOT_SIZE + LABEL_HEIGHT), _label_for(slots[i]), HORIZONTAL_ALIGNMENT_LEFT, SLOT_SIZE, 12, Color(0.9, 0.9, 0.85))
