class_name ItemPickerModal
extends PopupPanel

## Filter dropdown picker. Opens at anchor (e.g., filter slot's screen
## position + offset); shows a scrollable list of all Items.Type entries
## as clickable buttons. Click an item → fires confirm_cb with the chosen
## Items.Type; modal closes. Esc / click-outside cancels (callback not
## invoked).
##
## Mirrors QuantityPickerModal pattern (hard-modal via
## popup_exclusive_on_parent, callback-based result). Cloned not shared
## because UI shape diverges (list vs spinbox).
##
## Used by FastInserterPanel filter slot (Task 7 wires it). Complements
## drop-to-set (both paths set filter; user choice).

# Picker dimensions — shared constant so script + scene + modal call
# all read from one place.
const PICKER_SIZE: Vector2i = Vector2i(280, 320)

@onready var _list_container: VBoxContainer = $ScrollContainer/VBox if has_node("ScrollContainer/VBox") else null

var _confirm_cb: Callable = Callable()
var _current_filter: int = -1

func _ready() -> void:
	close_requested.connect(hide)

## Open the picker at anchor with current_filter (highlighted item).
## Pass -1 for current_filter if no filter currently set.
##
## On item selection → confirm_cb.call(item_type), then hides.
## On Esc / click-outside → hides; callback NOT invoked.
func open(anchor: Vector2, current_filter: int, confirm_cb: Callable) -> void:
	_confirm_cb = confirm_cb
	_current_filter = current_filter
	_populate_list()
	# Hard modal — Esc + click-outside cancel handled by PopupPanel.
	position = Vector2i(anchor)
	size = PICKER_SIZE
	# Headless test path: get_parent() may be the test_runner Node, not a
	# valid Window for popup_exclusive_on_parent. Guard the modal call.
	var p = get_parent()
	if p != null and p is Window:
		popup_exclusive_on_parent(p, Rect2i(Vector2i(anchor), PICKER_SIZE))
	visible = true

func _populate_list() -> void:
	if _list_container == null:
		return   # headless test path — no scene
	# Clear existing children.
	for child in _list_container.get_children():
		child.queue_free()
	# Add a row per Items.Type.
	for type_value in Items.Type.values():
		var btn := Button.new()
		var name_text: String = Items.name_of(type_value)
		var desc_text: String = Items.description_of(type_value)
		btn.text = "%s — %s" % [name_text, desc_text] if desc_text != "" else name_text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 28)
		if type_value == _current_filter:
			# Highlight current selection via modulate. Reuse SlotWidget's
			# established hover-yellow color for visual consistency across
			# the project's "current/active" affordance.
			btn.modulate = SlotWidget.BORDER_HOVER
		btn.pressed.connect(func(): _on_item_selected(type_value))
		_list_container.add_child(btn)

func _on_item_selected(item_type: int) -> void:
	if _confirm_cb.is_valid():
		_confirm_cb.call(item_type)
	hide()
