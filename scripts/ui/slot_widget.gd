class_name SlotWidget
extends RefCounted

## Static slot rendering helpers. Used by inventory_grid.gd (for player+chest
## grids) and building_panel.gd subclasses (for input/output/fuel slots).
##
## Keeps slot visual identity uniform: same background, border, swatch size,
## count overlay across every modal. Behavior (click handlers) lives in the
## owning Control; this module is render-only.

# Standard slot size matching inventory_grid.
const SIZE: int = 48
const SIZE_LARGE: int = 64       # for prominent slots (smelter input/output)
const SWATCH_INSET_STD: int = 8
const SWATCH_INSET_LARGE: int = 12

# Color palette (matches inventory_grid.gd).
const BG: Color = Color(0.10, 0.10, 0.10, 0.92)
const BG_EMPTY: Color = Color(0.16, 0.16, 0.16, 0.92)
const BORDER: Color = Color(0.50, 0.50, 0.50, 0.95)
const BORDER_HOVER: Color = Color(1.00, 0.92, 0.40, 1.00)
# Per-kind border tints (subtle hue on top of the base gray) so slot kind
# is recognizable at a glance.
const BORDER_INPUT: Color = Color(0.50, 0.55, 0.65, 0.95)    # cool gray-blue
const BORDER_OUTPUT: Color = Color(0.55, 0.65, 0.50, 0.95)   # cool gray-green
const BORDER_FUEL: Color = Color(0.65, 0.55, 0.40, 0.95)     # warm fuel-orange
const COUNT_COLOR: Color = Color(1.0, 1.0, 1.0)
const COUNT_SHADOW: Color = Color(0, 0, 0, 0.85)

## Draw a single slot at `rect`. `item_type < 0` = empty slot; only the box
## is drawn. Otherwise the swatch + count overlay render on top.
##
## `kind_border_tint` lets building panels pass an input/output/fuel-tinted
## border. Pass null/empty Color to use the default gray.
##
## `hovered` overrides the kind-tint with the hover yellow.
static func draw_slot(canvas: CanvasItem, font: Font, rect: Rect2, item_type: int, count: int, hovered: bool = false, kind_border_tint: Color = BORDER) -> void:
	var is_empty: bool = item_type < 0 or count <= 0
	canvas.draw_rect(rect, BG_EMPTY if is_empty else BG, true)
	var border: Color = BORDER_HOVER if hovered else kind_border_tint
	var border_w: float = 2.0 if hovered else 1.0
	canvas.draw_rect(rect, border, false, border_w)
	if is_empty:
		return
	# Swatch — centered. Size proportional to slot size.
	var swatch_size: float = max(rect.size.x, rect.size.y) * 0.65
	var swatch_inset: Vector2 = (rect.size - Vector2(swatch_size, swatch_size)) * 0.5
	var swatch_rect: Rect2 = Rect2(rect.position + swatch_inset, Vector2(swatch_size, swatch_size))
	canvas.draw_rect(swatch_rect, Items.color_of(item_type), true)
	canvas.draw_rect(swatch_rect, Color.BLACK, false, 1.0)
	# Count — bottom-right with shadow.
	var count_str: String = str(count)
	var count_pos: Vector2 = rect.position + Vector2(4, rect.size.y - 4)
	var alignment_width: int = int(rect.size.x) - 8
	canvas.draw_string(font, count_pos + Vector2(1, 1), count_str,
		HORIZONTAL_ALIGNMENT_RIGHT, alignment_width, 14, COUNT_SHADOW)
	canvas.draw_string(font, count_pos, count_str,
		HORIZONTAL_ALIGNMENT_RIGHT, alignment_width, 14, COUNT_COLOR)

## Helper: pick the kind-appropriate border tint for slot rendering.
## Maps slot_kind string from slot_layout to a Color.
static func border_for_kind(kind: String) -> Color:
	match kind:
		"input":
			return BORDER_INPUT
		"output", "output_multi":
			return BORDER_OUTPUT
		"fuel":
			return BORDER_FUEL
	return BORDER

## Draw the floating cursor stack at `mouse_pos` (used by every modal that
## holds a CursorStack). Same swatch+count style as a slot, no background.
static func draw_cursor_stack(canvas: CanvasItem, font: Font, mouse_pos: Vector2, cursor: CursorStack) -> void:
	if not cursor.has_item():
		return
	var swatch_rect: Rect2 = Rect2(mouse_pos - Vector2(16, 16), Vector2(32, 32))
	canvas.draw_rect(swatch_rect, Items.color_of(cursor.item_type), true)
	canvas.draw_rect(swatch_rect, Color.BLACK, false, 1.0)
	var count_str: String = str(cursor.count)
	var count_pos: Vector2 = mouse_pos + Vector2(8, 18)
	canvas.draw_string(font, count_pos + Vector2(1, 1), count_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COUNT_SHADOW)
	canvas.draw_string(font, count_pos, count_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COUNT_COLOR)
