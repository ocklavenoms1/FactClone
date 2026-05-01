extends Control

## Hotbar — number-key (1..N) selection of what the player will place.
##
## Each slot is a dict { "kind": String, "value": int }:
##   kind = "terrain"  -> value is a Terrain.Type (paints terrain)
##   kind = "building" -> value is a Buildings.Type (places a building)
##
## main.gd reads `current_kind()` / `current_value()` to dispatch placement.

const SLOT_SIZE: int = 56
const SLOT_GAP: int = 6
const SLOT_BG: Color = Color(0.10, 0.10, 0.10, 0.85)
const SLOT_BORDER: Color = Color(0.60, 0.60, 0.60, 0.90)
const SLOT_BORDER_SELECTED: Color = Color(1.00, 0.92, 0.40, 1.00)

signal selection_changed(kind: String, value: int)

var slots: Array = []
var selected_index: int = 0

func _ready() -> void:
	_build_slots()
	_apply_layout()
	queue_redraw()

func _build_slots() -> void:
	slots.clear()
	for terrain_value in Terrain.HOTBAR_ORDER:
		slots.append({ "kind": "terrain", "value": terrain_value })
	# Buildings — append after terrains. Order will become a designed loadout later.
	slots.append({ "kind": "building", "value": Buildings.Type.PLANTER })
	slots.append({ "kind": "building", "value": Buildings.Type.HARVESTER })
	slots.append({ "kind": "building", "value": Buildings.Type.BELT })
	slots.append({ "kind": "building", "value": Buildings.Type.MILL })
	slots.append({ "kind": "building", "value": Buildings.Type.CHEST })

func _apply_layout() -> void:
	var w: int = _slots_width()
	custom_minimum_size = Vector2(w, SLOT_SIZE + 24)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -(SLOT_SIZE + 24) - 12
	offset_bottom = -12

func _slots_width() -> int:
	var n: int = slots.size()
	return n * SLOT_SIZE + (n - 1) * SLOT_GAP

func _process(_delta: float) -> void:
	for i in slots.size():
		var action: String = "hotbar_%d" % (i + 1)
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			set_selection(i)

func set_selection(idx: int) -> void:
	idx = clamp(idx, 0, slots.size() - 1)
	if idx == selected_index:
		return
	selected_index = idx
	queue_redraw()
	selection_changed.emit(current_kind(), current_value())

func current_kind() -> String:
	return slots[selected_index]["kind"]

func current_value() -> int:
	return slots[selected_index]["value"]

func current_label() -> String:
	var s = slots[selected_index]
	return Terrain.name_of(s["value"]) if s["kind"] == "terrain" else Buildings.name_of(s["value"])

func _color_for(slot: Dictionary) -> Color:
	return Terrain.color_of(slot["value"]) if slot["kind"] == "terrain" else Buildings.swatch_color_of(slot["value"])

func _label_for(slot: Dictionary) -> String:
	return Terrain.name_of(slot["value"]) if slot["kind"] == "terrain" else Buildings.name_of(slot["value"])

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for i in slots.size():
		var x: float = i * (SLOT_SIZE + SLOT_GAP)
		var slot_rect: Rect2 = Rect2(x, 0, SLOT_SIZE, SLOT_SIZE)
		draw_rect(slot_rect, SLOT_BG, true)
		var border := SLOT_BORDER_SELECTED if i == selected_index else SLOT_BORDER
		var border_width: float = 3.0 if i == selected_index else 1.5
		draw_rect(slot_rect, border, false, border_width)

		# Color swatch.
		var swatch_rect: Rect2 = Rect2(x + 8, 8, SLOT_SIZE - 16, SLOT_SIZE - 28)
		draw_rect(swatch_rect, _color_for(slots[i]), true)
		# Tiny visual cue: buildings have a black outline on the swatch
		# so they read distinctly from raw terrain.
		if slots[i]["kind"] == "building":
			draw_rect(swatch_rect, Color.BLACK, false, 1.5)

		# Slot number.
		draw_string(font, Vector2(x + 6, SLOT_SIZE - 6), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		# Label below the slot.
		draw_string(font, Vector2(x, SLOT_SIZE + 16), _label_for(slots[i]), HORIZONTAL_ALIGNMENT_LEFT, SLOT_SIZE, 12, Color(0.9, 0.9, 0.85))
