extends Control

## Hotbar — categorized slots with Tab/Shift-Tab category switching.
##
## Layout:
##   Categories run left-to-right (Terrain · Logistics · Production · Storage).
##   Number keys 1..9 select within the *active* category.
##   Tab cycles to next category, Shift+Tab to previous.
##   Each category remembers its own last selection.
##
## Each slot is a dict { "kind": String, "value": int, optional "extra": Variant, optional "label": String }:
##   kind = "terrain"  -> value is a Terrain.Overlay (player paints overlays)
##   kind = "building" -> value is a Buildings.Type
##                        extra (optional) is forwarded to Buildings.make
##                        — used today for Planter crop variants (Wheat / Sugar Beet)
##                        label (optional) overrides the default name shown
##                        below the slot (e.g. "Wheat Planter" instead of "Planter").

const SLOT_SIZE: int = 64
const SLOT_GAP: int = 6
const SLOTS_PER_CATEGORY_MAX: int = 9
const SLOT_BG: Color = Color(0.10, 0.10, 0.10, 0.85)
const SLOT_BORDER: Color = Color(0.60, 0.60, 0.60, 0.90)
const SLOT_BORDER_SELECTED: Color = Color(1.00, 0.92, 0.40, 1.00)
const HEADER_BG: Color = Color(0.10, 0.10, 0.10, 0.85)
const HEADER_TEXT: Color = Color(1.00, 0.92, 0.55)
const HEADER_DIM: Color = Color(0.55, 0.55, 0.55)
const HEADER_HEIGHT: int = 22
const LABEL_FONT_SIZE: int = 11
const LABEL_LINE_HEIGHT: int = 13
const LABEL_AREA_HEIGHT: int = 32   # space below slots for up to two label lines

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
			# Planter variants — same building type, different crop_type via `extra`.
			{ "kind": "building", "value": Buildings.Type.PLANTER, "extra": Items.Type.WHEAT,      "label": "Wheat Planter" },
			{ "kind": "building", "value": Buildings.Type.PLANTER, "extra": Items.Type.SUGAR_BEET, "label": "Sugar Planter" },
			{ "kind": "building", "value": Buildings.Type.PLANTER, "extra": Items.Type.FLAX,       "label": "Flax Planter" },
			{ "kind": "building", "value": Buildings.Type.HARVESTER },
			{ "kind": "building", "value": Buildings.Type.PUMP },
			# Cloth chain processors — Refining is at 9/9, so these live here.
			{ "kind": "building", "value": Buildings.Type.RETTER },
			{ "kind": "building", "value": Buildings.Type.LOOM },
			{ "kind": "building", "value": Buildings.Type.TAILOR },
		],
		"selected": 0,
	})

	# Mining tier — extraction + smelting + (future) kilns and lumber camp.
	# Drill moved here from Production at session-smelter; Production was at
	# 9/9 with no thematic home for the smelter.
	categories.append({
		"name": "Mining",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.MINING_DRILL },
			{ "kind": "building", "value": Buildings.Type.SMELTER },
		],
		"selected": 0,
	})

	categories.append({
		"name": "Refining",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.THRESHER },
			{ "kind": "building", "value": Buildings.Type.MILL },
			{ "kind": "building", "value": Buildings.Type.MIXER },
			{ "kind": "building", "value": Buildings.Type.PROOFER },
			{ "kind": "building", "value": Buildings.Type.OVEN },
			{ "kind": "building", "value": Buildings.Type.PACKAGER },
			{ "kind": "building", "value": Buildings.Type.BRIQUETTER },
			{ "kind": "building", "value": Buildings.Type.YEAST_CULTURE },
			{ "kind": "building", "value": Buildings.Type.SUGAR_PRESS },
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
	var h: int = HEADER_HEIGHT + SLOT_SIZE + LABEL_AREA_HEIGHT + 8
	custom_minimum_size = Vector2(w, h)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -h - 12
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
	var idx: int = int(categories[current_category].get("selected", NO_SELECTION))
	if idx < 0 or idx >= slots.size():
		return {}     # NEUTRAL — no slot selected (Esc-cleared or out of range)
	return slots[idx]

func current_kind() -> String:
	# NEUTRAL → empty string. main.gd's match-statement falls through, no
	# placement, hover preview suppressed.
	var slot: Dictionary = current_slot()
	return str(slot.get("kind", "")) if not slot.is_empty() else ""

func current_value() -> int:
	var slot: Dictionary = current_slot()
	return int(slot.get("value", -1)) if not slot.is_empty() else -1

## Per-slot free-form payload, forwarded to Buildings.make. null when absent.
func current_extra():
	var slot: Dictionary = current_slot()
	return slot.get("extra", null) if not slot.is_empty() else null

func current_label() -> String:
	var slot: Dictionary = current_slot()
	return _label_for(slot) if not slot.is_empty() else "(neutral)"

# ---------- selection clear (session-building-ui-1) ----------
#
# Esc-with-no-modal-open → clear hotbar selection → enter NEUTRAL cursor mode.
# Once cleared, current_kind() returns "" (main.gd's match-statement
# falls through, no placement happens). Click on a slot or press a number
# key to re-enter selection.
const NO_SELECTION: int = -1

func has_selection() -> bool:
	return int(categories[current_category].get("selected", NO_SELECTION)) >= 0

func clear_selection() -> void:
	categories[current_category]["selected"] = NO_SELECTION
	queue_redraw()
	_emit_changed()

# ---------- visual ----------

func _color_for(slot: Dictionary) -> Color:
	return Terrain.overlay_color(slot["value"]) if slot["kind"] == "terrain" else Buildings.swatch_color_of(slot["value"])

func _label_for(slot: Dictionary) -> String:
	# Explicit per-slot label wins (e.g. "Wheat Planter" instead of "Planter").
	if slot.has("label"):
		return slot["label"]
	return Terrain.overlay_name(slot["value"]) if slot["kind"] == "terrain" else Buildings.name_of(slot["value"])

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var w: int = _max_row_width()

	# Header — single centered string, no overlap risk for any category name length.
	# In NEUTRAL mode (no slot selected), brackets dim out so the player sees
	# something changed when Esc was pressed.
	var header_rect: Rect2 = Rect2(0, 0, w, HEADER_HEIGHT)
	draw_rect(header_rect, HEADER_BG, true)
	var header_text: String
	var header_color: Color
	if has_selection():
		header_text = "◀  [ %s ]  ▶" % categories[current_category]["name"]
		header_color = HEADER_TEXT
	else:
		header_text = "◀  %s  (neutral — click building to interact)  ▶" % categories[current_category]["name"]
		header_color = HEADER_DIM
	draw_string(font, Vector2(0, HEADER_HEIGHT - 6), header_text, HORIZONTAL_ALIGNMENT_CENTER, w, 14, header_color)

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
		# Centered, optionally two-line label below the slot.
		_draw_label_below(canvas_font_or(font), Vector2(x, row_y + SLOT_SIZE + 4), _label_for(slots[i]))

## Helper: render a label centered below the slot, wrapping to a second line
## at the first space if the label has multiple words. Keeps long names like
## "Wheat Planter" / "Yeast Culture" aligned without overflow.
func _draw_label_below(font: Font, top_left: Vector2, label: String) -> void:
	var color: Color = Color(0.9, 0.9, 0.85)
	# Find first space to split on.
	var space_idx: int = label.find(" ")
	if space_idx < 0:
		# Single-word label — one centered line.
		draw_string(font, Vector2(top_left.x, top_left.y + LABEL_LINE_HEIGHT), label, HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE, LABEL_FONT_SIZE, color)
		return
	var line1: String = label.substr(0, space_idx)
	var line2: String = label.substr(space_idx + 1)
	draw_string(font, Vector2(top_left.x, top_left.y + LABEL_LINE_HEIGHT), line1, HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE, LABEL_FONT_SIZE, color)
	draw_string(font, Vector2(top_left.x, top_left.y + LABEL_LINE_HEIGHT * 2), line2, HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE, LABEL_FONT_SIZE, color)

func canvas_font_or(default_font: Font) -> Font:
	# Indirection so future themed fonts can plug in here without rewriting callers.
	return default_font
