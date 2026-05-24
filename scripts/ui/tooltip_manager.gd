class_name TooltipManager
extends Control

## Hover-tracking + tooltip rendering. Single shared widget; lives in main
## HUD ($HUD/TooltipManager). Slot-owning Controls (inventory_grid,
## chest_panel, building_panel subclasses) call start_hover(item_type,
## mouse_pos) when mouse enters a slot rect, end_hover() when mouse
## leaves. After HOVER_DELAY_MS ms of stable hover, the tooltip widget
## appears at mouse_pos + offset.
##
## Empty slots and unknown item types are no-ops (no tooltip shown).
##
## Tooltip content: item name (bold) + description (wrap-text body).
## Layout: PanelContainer > VBoxContainer > 2 Labels. Floats above all
## panels (z-index handled by scene tree order — TooltipManager is the
## last child of HUD).

# Tooltip appears after this many ms of stable hover.
const HOVER_DELAY_MS: int = 500

# Pixel offset from mouse cursor. Edge-flipped if would overflow viewport.
const TOOLTIP_OFFSET: Vector2 = Vector2(16, 16)

# Hover state.
var _hover_target: int = -1                # Items.Type or -1
var _hover_start_ms: int = 0
var _hover_pos: Vector2 = Vector2.ZERO
var _tooltip_visible: bool = false

# Scene refs — populated by _ready if the scene is loaded. Headless test
# path uses `TooltipManagerScript.new()` without scene → these stay null.
@onready var _panel: PanelContainer = $PanelContainer if has_node("PanelContainer") else null
@onready var _name_label: Label = $PanelContainer/VBox/NameLabel if has_node("PanelContainer/VBox/NameLabel") else null
@onready var _desc_label: Label = $PanelContainer/VBox/DescLabel if has_node("PanelContainer/VBox/DescLabel") else null

func _ready() -> void:
	# Tooltip should not block input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _panel != null:
		_panel.visible = false

## Begin hovering over a slot with the given item. Call from owning
## Control's mouse-motion handler when mouse enters a slot rect with a
## known item type. Empty slots: pass -1, treated as no hover.
##
## Repeated calls with the SAME item_type are idempotent (timer not reset).
## Different item_type restarts the timer.
func start_hover(item_type: int, mouse_pos: Vector2) -> void:
	if item_type < 0:
		end_hover()
		return
	if item_type == _hover_target:
		# Same target — just update position for tooltip placement.
		_hover_pos = mouse_pos
		if _tooltip_visible and _panel != null:
			_position_tooltip()
		return
	_hover_target = item_type
	_hover_start_ms = Time.get_ticks_msec()
	_hover_pos = mouse_pos
	_hide_tooltip()

## End hover. Resets state and hides tooltip.
func end_hover() -> void:
	_hover_target = -1
	_hover_start_ms = 0
	_hide_tooltip()

func _process(_delta: float) -> void:
	if _hover_target < 0 or _tooltip_visible:
		return
	if Time.get_ticks_msec() - _hover_start_ms < HOVER_DELAY_MS:
		return
	_show_tooltip()

func _show_tooltip() -> void:
	if _panel == null or _name_label == null or _desc_label == null:
		return   # headless test path — no scene
	_name_label.text = Items.name_of(_hover_target)
	_desc_label.text = Items.description_of(_hover_target)
	_panel.visible = true
	_tooltip_visible = true
	_position_tooltip()

func _hide_tooltip() -> void:
	if _panel == null:
		return
	_panel.visible = false
	_tooltip_visible = false

func _position_tooltip() -> void:
	if _panel == null:
		return
	# Edge-flip if would overflow viewport right/bottom.
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_size: Vector2 = _panel.size
	var pos: Vector2 = _hover_pos + TOOLTIP_OFFSET
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = _hover_pos.x - panel_size.x - TOOLTIP_OFFSET.x
	if pos.y + panel_size.y > viewport_size.y:
		pos.y = _hover_pos.y - panel_size.y - TOOLTIP_OFFSET.y
	_panel.position = pos
