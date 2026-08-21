extends InserterPanel

## Item picker modal reference (Task 7 of qol-cluster-b). Assigned by main.gd
## AFTER the all_panels init loop (FastInserterPanel uniquely owns the
## filter slot among panels), gated on null. Plain-LMB on filter slot with
## empty cursor opens the picker; callback sets filter_item_type and
## redraws. Drop-to-set (cursor with item) and RMB-clear paths unchanged —
## picker complements drop-to-set per spec section 5.
var item_picker_modal: Node = null

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
##   ║   └──┘  Cycle speed: 0.50s                 ║
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
	# Basic inserter panel = 280, putting ITS facing line at y=240 via
	# area.size.y - 40. Coincidence warning: that 240 is unrelated to our
	# filter row's 240 two lines below — same number, different derivation.
	# Fast adds the filter row + ~50px breathing room above the facing line so
	# the hint text doesn't visually run into the facing line:
	#   filter label at y=234
	#   filter slot at y=240 (spans 240..288, SlotWidget.SIZE=48)
	#   hint lines at y=258 + y=278
	#   facing line at y = _top_area_height - 40 = 360 - 40 = 320
	#   gap between hint (y=278) and facing (y=320) = 42px (comfortable)
	#
	# This 360 is HAND-DERIVED from _slot_y_offsets()["filter"] and is the one
	# copy of that coupling the code declines to compute: the invariant is
	# filter_y + SlotWidget.SIZE < _top_area_height() - 40, i.e. 288 < 320.
	# test_electric_inserter.gd sub-case 14 asserts that inequality directly,
	# so moving either number far enough to collide reddens the suite.
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
## All Y positions are anchored to the filter slot's Y offset so moving the
## slot in _slot_y_offsets() keeps the labels aligned.
##
## That anchoring is DERIVED, not merely claimed. It used to be an
## independent `const FILTER_Y: int = 240` that happened to agree with
## _slot_y_offsets()["filter"], and the two could drift in one direction
## silently: sub-case 14 of test_electric_inserter.gd pins the filter ROW to
## 240, so editing _slot_y_offsets() reddens a test — but editing the literal
## moved the header, name and hint TEXT off the slot with nothing watching.
## The fallback is 30 and NOT 240 — it deliberately mirrors the fallback in
## InserterPanel._building_slot_rects (`y_offsets.get(sid, 30)`), because the
## point is for text and slot to stay TOGETHER, not for either to stay where
## it is today. A subclass that overrode _slot_y_offsets() without a "filter"
## key would put the slot at 30; falling back to 240 here would strand the
## header over blank space and re-create by another route exactly the desync
## this refactor removed.
func _draw_filter_section(area: Rect2, font: Font) -> void:
	var filter_y: int = int(_slot_y_offsets().get("filter", 30))
	var slot_size: int = SlotWidget.SIZE
	var label_x: float = area.position.x + 24 + slot_size + 18
	# "FILTER" header above the slot row.
	draw_string(font, Vector2(area.position.x + 24, area.position.y + filter_y - 6),
		"FILTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.45, 0.85, 1.00, 1.0))    # cyan to match slot border
	# Filter content next to slot.
	var filter: int = int(building.state.get("filter_item_type", -1))
	if filter >= 0:
		draw_string(font, Vector2(label_x, area.position.y + filter_y + 18),
			Items.name_of(filter), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Items.color_of(filter))
		draw_string(font, Vector2(label_x, area.position.y + filter_y + 38),
			"Right-click to clear", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)
	else:
		draw_string(font, Vector2(label_x, area.position.y + filter_y + 18),
			"(any item)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)
		draw_string(font, Vector2(label_x, area.position.y + filter_y + 38),
			"Drop an item from inventory to set filter", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)

## Right-click-to-clear the filter. Defers all other events to the
## parent (LMB hits, motion, etc.) so existing behavior is preserved.
##
## RMB is consumed only when it lands on the filter slot — RMB elsewhere
## on the panel falls through to super(event) which itself ignores RMB.
## And RMB outside the panel doesn't reach _gui_input at all (Control's
## MOUSE_FILTER_STOP absorbs it; main.gd's _process gates on
## _any_building_panel_open() to suppress world-level RMB removal too).
##
## Tooltip hover (Task 5 qol-cluster-b): the filter slot is part of
## slot_layout with kind="filter", so BuildingPanel's `_handle_hover` already
## resolves the slot_def → filter_item_type → tooltip via the "filter" arm in
## `_hover_item_type`. MouseMotion events flow through super(event) here and
## land in BuildingPanel._gui_input which invokes _handle_hover. No filter-
## specific code needed in this subclass — the only requirement is that
## tooltip_manager is set on `self` (handled by main.gd panel-init loop).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var hit = _hit_test(event.position)
		if hit is Dictionary and str(hit["slot_def"].get("kind", "")) == "filter":
			building.state["filter_item_type"] = -1
			queue_redraw()
			accept_event()
			return
	# Task 7 (qol-cluster-b): plain-LMB on filter slot with empty cursor →
	# open ItemPickerModal. Drop-to-set (cursor with item) flows through
	# super(event) → BuildingPanel._handle_building_slot_click → _drop_into_filter.
	# Modifier-key clicks (shift/ctrl) also flow through to super(event) which
	# no-ops on filter per spec §5.2 / §6.3.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed \
			and cursor != null and not cursor.has_item() and item_picker_modal != null:
		var hit2 = _hit_test(event.position)
		if hit2 is Dictionary and str(hit2["slot_def"].get("kind", "")) == "filter":
			var slot_def: Dictionary = hit2["slot_def"]
			var slot_center: Vector2 = _building_slot_anchor(slot_def, -1)
			# Anchor: drop below the slot. _building_slot_anchor returns the slot
			# CENTER in viewport-global coords; offset down by half-slot to land
			# just under the slot's bottom edge.
			var anchor: Vector2 = slot_center + Vector2(0, SlotWidget.SIZE / 2)
			var current_filter: int = int(building.state.get("filter_item_type", -1))
			item_picker_modal.open(anchor, current_filter,
				func(item_type: int): _apply_filter_from_picker(item_type))
			accept_event()
			return
	super(event)

## Picker callback (Task 7). Sets filter_item_type and triggers redraw so
## the filter section reflects the new selection immediately.
func _apply_filter_from_picker(item_type: int) -> void:
	building.state["filter_item_type"] = item_type
	queue_redraw()
