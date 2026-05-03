extends Control

## Compact inventory display in the top-right corner.
## Shows aggregated counts per item type (one row per type that exists).
##
## Set `inventory` from main.gd. The panel polls aggregates each frame —
## inventories are tiny so this is fine.

const ROW_HEIGHT: int = 24
const SWATCH_SIZE: int = 16
const PADDING: int = 8
const PANEL_WIDTH: int = 180
const BG_COLOR: Color = Color(0.10, 0.10, 0.10, 0.85)
const BORDER_COLOR: Color = Color(0.6, 0.6, 0.6, 0.9)
const TEXT_COLOR: Color = Color(0.95, 0.95, 0.85)

var inventory: Inventory = null
## Set by main.gd. Read by reference each redraw to display "Bags: X/5
## consumed" — Dictionary is shared, so updates from the bag-consume flow
## are reflected automatically without a setter call. Empty-or-null means
## "don't draw the bags row" (keeps the panel clean for tests / non-game
## screens that don't have progression state).
var player_progression: Dictionary = {}

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -16
	# Position below minimap. Minimap is at top=10, height=224 (y-bottom=234).
	# Add 10px gap so the two panels are visually distinct.
	offset_top = 244
	offset_left = -16 - PANEL_WIDTH
	mouse_filter = MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if inventory == null:
		return
	var agg: Dictionary = inventory.aggregate()
	# Bags header is its own row above the items. Always shown when
	# progression dict is set, even at 0/5 — gives the player a visible
	# anchor for what they're working toward.
	var has_bags_row: bool = not player_progression.is_empty()
	# Always reserve at least one row's height so the panel is visible even when empty.
	var item_rows: int = max(1, agg.size())
	var bags_row_h: int = ROW_HEIGHT if has_bags_row else 0
	var height: float = PADDING * 2 + ROW_HEIGHT * item_rows + 22 + bags_row_h
	var rect: Rect2 = Rect2(0, 0, PANEL_WIDTH, height)
	offset_bottom = offset_top + height
	draw_rect(rect, BG_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, 1.5)

	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(PADDING, PADDING + 12), "Inventory", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)

	var y: float = PADDING + 22
	if has_bags_row:
		# Bags line — surfaces the lifetime cap (5), which the slot grid
		# can't show. Slot occupancy used to live here too but is now
		# implicit in the inventory grid view; line trimmed when grid shipped.
		var n: int = int(player_progression.get("bags_consumed", 0))
		var label: String = "Bags: %d / 5 consumed" % n
		draw_string(font, Vector2(PADDING, y + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.7, 0.5))
		y += ROW_HEIGHT
	if agg.is_empty():
		draw_string(font, Vector2(PADDING, y + 12), "(empty)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.65))
		return
	for item_type in agg.keys():
		var swatch_rect: Rect2 = Rect2(PADDING, y + (ROW_HEIGHT - SWATCH_SIZE) * 0.5, SWATCH_SIZE, SWATCH_SIZE)
		draw_rect(swatch_rect, Items.color_of(item_type), true)
		draw_rect(swatch_rect, Color.BLACK, false, 1.0)
		var label: String = "%s: %d" % [Items.name_of(item_type), agg[item_type]]
		draw_string(font, Vector2(PADDING + SWATCH_SIZE + 8, y + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
		y += ROW_HEIGHT
