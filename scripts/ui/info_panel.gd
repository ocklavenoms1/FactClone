extends Control

## Building Info Panel — primary debugging tool.
##
## Activated by pressing `inspect_building` (Q key or middle mouse) while
## hovering a tile with a building. Displays per-building info_lines.
##
## Tracks the inspected building by its anchor (Vector2i), NOT by Building
## reference, so we detect deletion/replacement cleanly.

const PANEL_WIDTH: int = 240
const PADDING: int = 10
const HEADER_HEIGHT: int = 22
const LINE_HEIGHT: int = 18
const BG_COLOR: Color = Color(0.10, 0.10, 0.10, 0.88)
const BORDER_COLOR: Color = Color(0.65, 0.55, 0.35, 0.95)
const HEADER_COLOR: Color = Color(1.00, 0.92, 0.55)
const TEXT_COLOR: Color = Color(0.95, 0.95, 0.85)
const SUBTEXT_COLOR: Color = Color(0.70, 0.70, 0.65)

var target_anchor: Vector2i = Vector2i.ZERO
var has_target: bool = false
var world: Node2D = null

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -16
	offset_left = -16 - PANEL_WIDTH
	offset_top = 240   # leave room for the inventory panel above
	offset_bottom = offset_top + 40
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false

## Set the inspected building. Pass null to close the panel.
func set_target(b: Building, w: Node2D) -> void:
	if b == null:
		clear_target()
		return
	target_anchor = b.anchor
	world = w
	has_target = true
	visible = true

func clear_target() -> void:
	has_target = false
	visible = false

func _process(_delta: float) -> void:
	if not has_target:
		return
	# Building may have been removed since we set the target — close cleanly.
	if world == null or not world.has_building_at(target_anchor):
		clear_target()
		return
	queue_redraw()

func _draw() -> void:
	if not has_target or world == null:
		return
	var b: Building = world.building_at(target_anchor)
	if b == null:
		return

	var lines: Array = Buildings.info_lines_for(b, world)
	var height: float = PADDING * 2 + HEADER_HEIGHT + LINE_HEIGHT * lines.size() + 2
	offset_bottom = offset_top + height

	var rect: Rect2 = Rect2(0, 0, PANEL_WIDTH, height)
	draw_rect(rect, BG_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, 1.5)

	var font: Font = ThemeDB.fallback_font

	# Header: building name + anchor position.
	var header: String = "%s @ (%d, %d)" % [Buildings.name_of(b.type), target_anchor.x, target_anchor.y]
	draw_string(font, Vector2(PADDING, PADDING + 14), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HEADER_COLOR)
	draw_line(Vector2(PADDING, PADDING + HEADER_HEIGHT - 2), Vector2(PANEL_WIDTH - PADDING, PADDING + HEADER_HEIGHT - 2), SUBTEXT_COLOR, 1.0)

	# Info lines.
	var y: float = PADDING + HEADER_HEIGHT + 14
	for line in lines:
		draw_string(font, Vector2(PADDING, y), str(line), HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - PADDING * 2, 12, TEXT_COLOR)
		y += LINE_HEIGHT
