class_name QuantityPickerModal
extends PopupPanel

## Ctrl+click quantity picker modal (QoL Cluster A — spec §4.2 / §6).
##
## Hard modal — uses popup_exclusive_on_parent() so Esc, click-outside,
## and modal blocking are handled natively by Godot's PopupPanel. While
## open, all other input behind it is blocked.
##
## Usage:
##   picker.open(slot_center, "Take", "Wheat", 8, 8, my_callable)
##
##   On Enter / OK   → calls my_callable.call(spinbox.value), closes.
##   On Esc / Cancel / click outside → closes, callback not invoked.
##
## Caller patterns by slot kind:
##   Player slot:    SlotClickHandler.ctrl_click_transfer(slot, cursor, n)
##   Chest slot:     chest_panel-side inline transfer logic
##   Building input: building_panel inline transfer logic
##   Fuel slot:      asymmetric label_item per direction (spec §6.2):
##     TAKE: label_item = "fuel units (returned as wood)"
##     DROP: label_item = Items.name_of(cursor.item_type)

@onready var _label: Label = $VBox/Label
@onready var _spinbox: SpinBox = $VBox/SpinBox
@onready var _ok_button: Button = $VBox/Buttons/OK
@onready var _cancel_button: Button = $VBox/Buttons/Cancel

var _confirm_cb: Callable = Callable()

func _ready() -> void:
	_ok_button.pressed.connect(_on_confirm)
	_cancel_button.pressed.connect(hide)
	close_requested.connect(hide)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Enter anywhere within the focused picker → commit. Esc is handled
	# natively by PopupPanel via close_requested signal.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_confirm()
			get_viewport().set_input_as_handled()

## Open the picker near `anchor` with the given parameters.
## - anchor: world position to place the picker near (slot center in global coords).
## - direction: "Take" or "Give" — first word of the label.
## - label_item: item name displayed (e.g., "Wheat") or "fuel units (returned as wood)" for fuel-take.
## - max_n: SpinBox max value (clamped from caller's ctrl_click_max-style calc).
## - default_n: SpinBox starting value (per spec §6.1: default = max).
## - confirm_cb: Callable(amount: int) invoked on Enter / OK.
##
## Pre-open gate is CALLER's responsibility: do not call open() with max_n <= 0
## (picker would show but have no meaningful range). Spec §6.1 caller gates
## on ctrl_click_max > 0 before invoking open().
func open(anchor: Vector2, direction: String, label_item: String,
		  max_n: int, default_n: int, confirm_cb: Callable) -> void:
	_confirm_cb = confirm_cb
	_label.text = "%s ___ %s" % [direction, label_item]
	_spinbox.min_value = 1
	_spinbox.max_value = max_n
	_spinbox.value = clamp(default_n, 1, max_n)
	# Anchor placement with viewport-edge flip per spec §4.3 / Q4b.
	var picker_size: Vector2 = size
	# PopupPanel extends Window, not CanvasItem — get_viewport_rect lives on
	# CanvasItem. Use the SceneTree root's size for edge-flip math, which
	# works regardless of parent type (Control in game, Node in tests).
	var vp: Vector2 = Vector2(get_tree().root.size)
	var pos: Vector2 = anchor + Vector2(60, -40)
	if pos.x + picker_size.x > vp.x:
		pos.x = anchor.x - (60 + picker_size.x)
	if pos.y + picker_size.y > vp.y:
		pos.y = anchor.y - (40 + picker_size.y)
	if pos.x < 0:
		pos.x = 4
	if pos.y < 0:
		pos.y = 4
	# Set Window position + size BEFORE popup_exclusive_on_parent, AND also pass
	# them as Rect2i (with explicit Vector2i conversion). Passing Vector2 to
	# Rect2i previously was silently broken — embedded popups landed at
	# top-left of viewport. Explicit Vector2i conversion fixes that.
	position = Vector2i(pos)
	size = Vector2i(picker_size)
	# Explicit visible flip — popup_exclusive_on_parent may not flip the flag
	# in headless mode (no display server). Setting here makes the contract
	# consistent across windowed AND headless contexts.
	visible = true
	popup_exclusive_on_parent(get_parent(), Rect2i(Vector2i(pos), Vector2i(picker_size)))
	_spinbox.grab_focus()
	_spinbox.get_line_edit().select_all()

func _on_confirm() -> void:
	if _confirm_cb.is_valid():
		_confirm_cb.call(int(_spinbox.value))
	hide()
