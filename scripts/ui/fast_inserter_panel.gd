extends InserterPanel

## Fast Inserter panel — extends InserterPanel with the filter slot row
## (session-inserter-fast-filter, Inserter Arc Session 2).
##
## Inherits Session 1's panel layout entirely; adds:
##   - Filter slot rendering (icon-only, cyan border, "(any item)" placeholder)
##   - Drop-to-set already handled by BuildingPanel._drop_into_filter via
##     the "filter" slot kind dispatch
##   - Right-click on filter slot → clear filter (override _gui_input)
##
## Layout extends InserterPanel's:
##   ╔══════════════ Fast Inserter ═══════════════╗
##   ║                                            ║
##   ║   Holding: ┌──┐    Status: WORKING (out)   ║
##   ║           │ ●│    Cycle: 47%              ║
##   ║           └──┘                             ║
##   ║   ▓▓▓▓▓░░░░░░  cycle progress bar (0.5s)   ║
##   ║                                            ║
##   ║   Source:      Belt at (4, 5)              ║
##   ║   Destination: Chest at (6, 5)             ║
##   ║                                            ║
##   ║   ┌──┐                                     ║
##   ║   │██│  Fuel: 12 / 16 units                ║
##   ║   └──┘  Cycle speed: 0.5s (fixed)          ║
##   ║                                            ║
##   ║   FILTER                                   ║   ← NEW row (y=240)
##   ║   ┌──┐  Wheat                              ║
##   ║   │ ●│  Drop to set, right-click to clear  ║
##   ║   └──┘                                     ║
##   ║                                            ║
##   ║   Facing: E (R to rotate)                  ║
##   ║                                            ║
##   ╠════════════════════════════════════════════╣
##   ║          Player inventory                  ║
##   ╚════════════════════════════════════════════╝

func _top_area_height() -> int:
	# Basic inserter panel = 280 (facing line at y=240 via area.size.y - 40).
	# Fast adds the filter row + ~50px breathing room above the facing line so
	# the hint text doesn't visually run into the facing line:
	#   filter label at y=234
	#   filter slot at y=240 (spans 240..288, SlotWidget.SIZE=48)
	#   hint lines at y=258 + y=278
	#   facing line at y = _top_area_height - 40 = 360 - 40 = 320
	#   gap between hint (y=278) and facing (y=320) = 42px (comfortable)
	return 360

## Override the y_offsets dict to inject the filter slot row at y=240.
func _slot_y_offsets() -> Dictionary:
	return {
		"held_item": 30,
		"fuel":      160,
		"filter":    240,
	}

## Inject filter UI elements after the parent draws basic layout.
## InserterPanel's facing-line draw is anchored to area.size.y - 40, so
## with our taller _top_area_height() it lands BELOW our filter row
## automatically. No override needed.
func _draw_building_specific(area: Rect2, font: Font) -> void:
	super(area, font)
	_draw_filter_section(area, font)

## Draw the filter section: label + name/hint text next to the slot.
## The slot itself is rendered by BuildingPanel._draw_slots via the
## "filter" slot kind dispatch.
##
## All Y positions are anchored to the filter slot's Y offset (240) so
## moving the slot in _slot_y_offsets() keeps the labels aligned.
func _draw_filter_section(area: Rect2, font: Font) -> void:
	const FILTER_Y: int = 240
	var slot_size: int = SlotWidget.SIZE
	var label_x: float = area.position.x + 24 + slot_size + 18
	# "FILTER" header above the slot row.
	draw_string(font, Vector2(area.position.x + 24, area.position.y + FILTER_Y - 6),
		"FILTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.45, 0.85, 1.00, 1.0))    # cyan to match slot border
	# Filter content next to slot.
	var filter: int = int(building.state.get("filter_item_type", -1))
	if filter >= 0:
		draw_string(font, Vector2(label_x, area.position.y + FILTER_Y + 18),
			Items.name_of(filter), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Items.color_of(filter))
		draw_string(font, Vector2(label_x, area.position.y + FILTER_Y + 38),
			"Right-click to clear", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)
	else:
		draw_string(font, Vector2(label_x, area.position.y + FILTER_Y + 18),
			"(any item)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)
		draw_string(font, Vector2(label_x, area.position.y + FILTER_Y + 38),
			"Drop an item from inventory to set filter", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)

## Right-click-to-clear the filter. Defers all other events to the
## parent (LMB hits, motion, etc.) so existing behavior is preserved.
##
## RMB is consumed only when it lands on the filter slot — RMB elsewhere
## on the panel falls through to super(event) which itself ignores RMB.
## And RMB outside the panel doesn't reach _gui_input at all (Control's
## MOUSE_FILTER_STOP absorbs it; main.gd's _process gates on
## _any_building_panel_open() to suppress world-level RMB removal too).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var hit = _hit_test(event.position)
		if hit is Dictionary and str(hit["slot_def"].get("kind", "")) == "filter":
			building.state["filter_item_type"] = -1
			queue_redraw()
			accept_event()
			return
	super(event)
