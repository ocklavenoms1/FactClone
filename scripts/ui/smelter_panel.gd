extends BuildingPanel

## Smelter-specialized building panel (session-building-ui-1).
##
## Layout (per Q9 design):
##   ╔══════════════ Smelter ══════════════╗
##   ║  ┌────┐                  ┌────┐     ║
##   ║  │ in │ ━━━━ 18/40 ━━▶  │ out│     ║
##   ║  └────┘                  └────┘     ║
##   ║   Iron Ore   (smelting)  Iron Ingot ║
##   ║                                     ║
##   ║       ┌────┐                        ║
##   ║       │fuel│  Fuel: 5 / 16 units    ║
##   ║       └────┘                        ║
##   ║                                     ║
##   ║  Status: Smelting Iron Ingot        ║
##   ║  Currently smelting: Iron → Iron... ║
##   ╠═════════════════════════════════════╣
##   ║         Player inventory             ║
##   ╚══════════════════════════════════════╝
##
## Inherits drag-drop, validation, modal lifecycle, player-inventory-render
## from BuildingPanel. Overrides:
##   _building_slot_rects() — positions in/out/fuel slots per the layout above
##   _draw_building_specific(area, font) — paints title, progress bar,
##                                          status text, fuel hint

const SLOT_LARGE: int = 64           # input + output slots
const FUEL_SLOT_SIZE: int = 48
const PROGRESS_BAR_W: float = 200.0
const PROGRESS_BAR_H: float = 18.0

# State tints for the progress bar (mirrors smelter.gd's body tints).
const BAR_BG: Color = Color(0.12, 0.10, 0.08, 1.0)
const BAR_BORDER: Color = Color(0.40, 0.32, 0.20, 1.0)
const BAR_FILL_SMELTING: Color = Color(1.00, 0.55, 0.20, 1.0)    # orange-red
const BAR_FILL_IDLE: Color = Color(0.40, 0.40, 0.42, 1.0)        # neutral gray

# Status colors per state.
const COLOR_SMELTING: Color = Color(1.00, 0.85, 0.30)
const COLOR_NO_FUEL: Color = Color(0.50, 0.65, 1.00)
const COLOR_BLOCKED: Color = Color(1.00, 0.95, 0.40)
const COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

## Override slot positions for smelter's flow layout. Returns the same
## structure as the base class (Array of {slot_def, rect, sub_idx}); just
## with custom positions matching the visual flow.
func _building_slot_rects() -> Array:
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var layout: Array = Buildings.slot_layout_for(building.type)
	var rects: Array = []

	# Top row: input (left), arrow + progress (center), output (right).
	var row1_y: float = area.position.y + 28
	var input_x: float = area.position.x + 24
	var output_x: float = area.position.x + area.size.x - SLOT_LARGE - 24

	# Bottom row: fuel slot centered.
	var row2_y: float = row1_y + SLOT_LARGE + 50
	var fuel_x: float = area.position.x + 24

	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		match kind:
			"input":
				rects.append({"slot_def": slot_def, "rect": Rect2(input_x, row1_y, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})
			"output":
				rects.append({"slot_def": slot_def, "rect": Rect2(output_x, row1_y, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})
			"fuel":
				rects.append({"slot_def": slot_def, "rect": Rect2(fuel_x, row2_y, FUEL_SLOT_SIZE, FUEL_SLOT_SIZE), "sub_idx": -1})
	return rects

## Paint the flow arrow + progress bar between input and output slots, plus
## fuel-slot label and status text. Slots themselves render via the base
## class's _draw_slots (which calls _building_slot_rects).
func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null:
		return
	var s: int = int(building.state.get("state", 0))   # Smelter.STATE_IDLE
	var recipe_id: String = str(building.state.get("recipe_id", ""))
	var recipe: Dictionary = Recipes.get_recipe(recipe_id) if recipe_id != "" else {}

	# Slot labels under input/output.
	var row1_y: float = area.position.y + 28
	var input_x: float = area.position.x + 24
	var output_x: float = area.position.x + area.size.x - SLOT_LARGE - 24
	# Slot labels (small text below each slot).
	var label_y: float = row1_y + SLOT_LARGE + 18
	var input_label: String = "Input"
	var output_label: String = "Output"
	if not recipe.is_empty():
		var inputs: Array = recipe.get("inputs_solid", [])
		if not inputs.is_empty():
			input_label = Items.name_of(int(inputs[0][0]))
		var outputs: Array = recipe.get("outputs_solid", [])
		if not outputs.is_empty():
			output_label = Items.name_of(int(outputs[0][0]))
	draw_string(font, Vector2(input_x, label_y), input_label,
		HORIZONTAL_ALIGNMENT_LEFT, SLOT_LARGE, 12, TEXT_DIM)
	draw_string(font, Vector2(output_x, label_y), output_label,
		HORIZONTAL_ALIGNMENT_LEFT, SLOT_LARGE, 12, TEXT_DIM)

	# Progress bar between input and output.
	var bar_x: float = (input_x + SLOT_LARGE + output_x - PROGRESS_BAR_W) * 0.5
	var bar_y: float = row1_y + (SLOT_LARGE - PROGRESS_BAR_H) * 0.5
	var bar_rect: Rect2 = Rect2(bar_x, bar_y, PROGRESS_BAR_W, PROGRESS_BAR_H)
	draw_rect(bar_rect, BAR_BG, true)
	# Fill — proportional to smelter progress / time_ticks.
	var progress: int = int(building.state.get("progress", 0))
	var max_progress: int = int(recipe.get("time_ticks", 1)) if not recipe.is_empty() else 1
	var fraction: float = clamp(float(progress) / float(max_progress), 0.0, 1.0) if max_progress > 0 else 0.0
	if fraction > 0.0:
		var fill_color: Color = BAR_FILL_SMELTING if s == 1 else BAR_FILL_IDLE
		var fill_rect: Rect2 = Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y))
		draw_rect(fill_rect, fill_color, true)
	draw_rect(bar_rect, BAR_BORDER, false, 1.0)
	# Progress text overlay.
	var progress_text: String = "%d / %d" % [progress, max_progress]
	draw_string(font, bar_rect.position + Vector2(0, PROGRESS_BAR_H - 4),
		progress_text, HORIZONTAL_ALIGNMENT_CENTER, int(PROGRESS_BAR_W), 12, TEXT_COLOR)
	# Arrow head pointing right (input → output).
	var arrow_y: float = bar_y + PROGRESS_BAR_H * 0.5
	var arrow_tip_x: float = bar_x + PROGRESS_BAR_W + 12
	var arrow_color: Color = TEXT_COLOR
	draw_line(Vector2(arrow_tip_x - 12, arrow_y - 6), Vector2(arrow_tip_x, arrow_y), arrow_color, 2.0)
	draw_line(Vector2(arrow_tip_x - 12, arrow_y + 6), Vector2(arrow_tip_x, arrow_y), arrow_color, 2.0)

	# Fuel slot label (right of the fuel slot).
	var row2_y: float = row1_y + SLOT_LARGE + 50
	var fuel_x: float = area.position.x + 24
	var fuel_label_x: float = fuel_x + FUEL_SLOT_SIZE + 16
	var fuel_units: int = int(building.state.get("fuel_buffer", 0))
	var fuel_cap: int = int(Burner.FUEL_BUFFER_CAPACITY)
	var fuel_text: String = "Fuel: %d / %d units" % [fuel_units, fuel_cap]
	draw_string(font, Vector2(fuel_label_x, row2_y + 18),
		fuel_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)
	draw_string(font, Vector2(fuel_label_x, row2_y + 36),
		"(accepts: Wood, Coal, Briquette)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)

	# Status row below fuel.
	var status_y: float = row2_y + FUEL_SLOT_SIZE + 24
	var status_text: String = "Status: Idle"
	var status_color: Color = COLOR_IDLE
	match s:
		1:    # SMELTING
			status_text = "Status: Smelting"
			status_color = COLOR_SMELTING
		2:    # NO_FUEL
			status_text = "Status: NO FUEL — feed wood, coal, or fuel briquette"
			status_color = COLOR_NO_FUEL
		3:    # BLOCKED_OUTPUT
			status_text = "Status: Output blocked"
			status_color = COLOR_BLOCKED
	draw_string(font, Vector2(area.position.x + 24, status_y),
		status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, status_color)

	# Currently smelting line (sits below status, smaller).
	var current_text: String
	if not recipe.is_empty():
		current_text = "Currently smelting: %s" % str(recipe.get("display_name", recipe_id))
	else:
		current_text = "Currently smelting: (none — feed iron or copper ore)"
	draw_string(font, Vector2(area.position.x + 24, status_y + 22),
		current_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)
