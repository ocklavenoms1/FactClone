class_name ProcessorPanel
extends BuildingPanel

## Intermediate base class for input → progress → output processors.
##
## Default layout (per Q1 design pass at session-building-ui-2):
##   ╔════════════ <Building Name> ══════════════╗
##   ║  ┌────┐                       ┌────┐      ║
##   ║  │ in │ ━━━━ <prog>/<max> ━━▶ │ out│      ║
##   ║  └────┘                       └────┘      ║
##   ║   <input item>     (status)   <output>    ║
##   ║                                           ║
##   ║  ┌────┐ <only if 2nd input slot exists>   ║
##   ║  │ in2│  Fuel Briquette / etc.            ║
##   ║  └────┘                                   ║
##   ║                                           ║
##   ║  Status: <Idle | Running | Blocked>       ║
##   ║  Recipe: <display name>                   ║
##   ╠═══════════════════════════════════════════╣
##   ║              Player inventory             ║
##   ╚═══════════════════════════════════════════╝
##
## Subclasses (Mill, Proofer, Packager, Oven) typically override NOTHING —
## just `extends ProcessorPanel`. The slot_layout in Buildings.DATA drives
## what slots get rendered; the recipe drives the progress bar.
##
## Buildings whose layout diverges (Mixer with fluid input, Smelter with
## multi-recipe selector) extend BuildingPanel directly instead of this class.

const SLOT_LARGE: int = 64
const PROGRESS_BAR_W: float = 200.0
const PROGRESS_BAR_H: float = 18.0

# Status colors per Processor state enum (IDLE=0, RUNNING=1, BLOCKED_OUTPUT=2).
const STATUS_COLOR_RUNNING: Color = Color(0.55, 0.85, 0.55)
const STATUS_COLOR_BLOCKED: Color = Color(1.00, 0.95, 0.40)
const STATUS_COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

const BAR_BG: Color = Color(0.12, 0.10, 0.08, 1.0)
const BAR_BORDER: Color = Color(0.40, 0.32, 0.20, 1.0)
const BAR_FILL_RUNNING: Color = Color(0.85, 0.65, 0.30, 1.0)    # warm amber
const BAR_FILL_IDLE: Color = Color(0.40, 0.40, 0.42, 1.0)

## Position slot widgets per the slot_layout. Inputs on the left (stacked
## vertically when there's more than one), outputs on the right, fuel slot
## (if present) bottom-left below inputs.
##
## Layout constants:
##   SLOT_LARGE      — each input/output slot is 64×64
##   LABEL_HEIGHT    — 18px below each slot for the item-name label
##   SLOT_VGAP       — 12px between stacked input slots (so label fits)
##
## Total per-row vertical: SLOT_LARGE + LABEL_HEIGHT + SLOT_VGAP = 94px.
##
## We split slots into three categories by kind, then position by category.
## Returns Array of {slot_def, rect, sub_idx}.
const LABEL_HEIGHT: int = 18
const SLOT_VGAP: int = 12

func _building_slot_rects() -> Array:
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var layout: Array = Buildings.slot_layout_for(building.type)
	var rects: Array = []

	# Categorize. fluid_indicator is render-only (not click-targetable);
	# it's not added to rects. Subclasses inheriting ProcessorPanel get
	# fluid-input rendering for free via _draw_building_specific below.
	var inputs: Array = []
	var outputs: Array = []
	var fuels: Array = []
	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		match kind:
			"input":
				inputs.append(slot_def)
			"output":
				outputs.append(slot_def)
			"fuel":
				fuels.append(slot_def)

	# Layout positions.
	var top_y: float = area.position.y + 28
	var left_x: float = area.position.x + 24
	var right_x: float = area.position.x + area.size.x - SLOT_LARGE - 24
	var row_h: int = SLOT_LARGE + LABEL_HEIGHT + SLOT_VGAP

	# Input column on the left. Stack vertically if multiple.
	for i in inputs.size():
		var y: float = top_y + i * row_h
		rects.append({"slot_def": inputs[i], "rect": Rect2(left_x, y, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})

	# Output column on the right.
	for i in outputs.size():
		var y2: float = top_y + i * row_h
		rects.append({"slot_def": outputs[i], "rect": Rect2(right_x, y2, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})

	# Fuel slot below the input column.
	if not fuels.is_empty():
		var fuel_y: float = top_y + inputs.size() * row_h + 8
		rects.append({"slot_def": fuels[0], "rect": Rect2(left_x, fuel_y, SlotWidget.SIZE, SlotWidget.SIZE), "sub_idx": -1})

	return rects

## Y-coordinate where status text should start, computed below the deepest
## column (input col, output col, fuel slot, or fluid_indicator widget).
## Subclasses inheriting ProcessorPanel use this to keep status from
## overlapping slots/widgets.
func _status_y() -> float:
	if building == null:
		return 0.0
	var area: Rect2 = _top_area_rect()
	var top_y: float = area.position.y + 28
	var layout: Array = Buildings.slot_layout_for(building.type)
	var input_count: int = 0
	var output_count: int = 0
	var has_fuel: bool = false
	var has_fluid: bool = false
	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		match kind:
			"input":
				input_count += 1
			"output":
				output_count += 1
			"fuel":
				has_fuel = true
			"fluid_indicator":
				has_fluid = true
	var row_h: int = SLOT_LARGE + LABEL_HEIGHT + SLOT_VGAP
	var input_bottom: float = top_y + max(1, input_count) * row_h
	var output_bottom: float = top_y + max(1, output_count) * row_h
	var fuel_bottom: float = 0.0
	if has_fuel:
		fuel_bottom = top_y + input_count * row_h + 8 + SlotWidget.SIZE + LABEL_HEIGHT
	var fluid_bottom: float = 0.0
	if has_fluid:
		fluid_bottom = top_y + input_count * row_h + 8 + FLUID_ROW_HEIGHT
	return max(input_bottom, max(output_bottom, max(fuel_bottom, fluid_bottom))) + 8

## Paint progress bar between input and output, slot labels, status text,
## recipe display.
func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null:
		return
	var recipe_id: String = str(building.state.get("recipe_id", ""))
	var recipe: Dictionary = Recipes.get_recipe(recipe_id) if recipe_id != "" else {}
	var s: int = int(building.state.get("state", Processor.IDLE))
	var top_y: float = area.position.y + 28
	var left_x: float = area.position.x + 24
	var right_x: float = area.position.x + area.size.x - SLOT_LARGE - 24

	# Slot labels under input(s) and output(s). Each row is (slot + label + gap).
	var layout: Array = Buildings.slot_layout_for(building.type)
	var input_count: int = 0
	var output_count: int = 0
	var row_h: int = SLOT_LARGE + LABEL_HEIGHT + SLOT_VGAP
	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		match kind:
			"input":
				var label: String = "Input"
				var accepts: Array = slot_def.get("accepts", [])
				if accepts.size() == 1:
					label = Items.name_of(int(accepts[0]))
				var ly: float = top_y + input_count * row_h + SLOT_LARGE + 14
				draw_string(font, Vector2(left_x, ly), label,
					HORIZONTAL_ALIGNMENT_LEFT, SLOT_LARGE + 80, 12, TEXT_DIM)
				input_count += 1
			"output":
				var olabel: String = "Output"
				var oaccepts: Array = slot_def.get("accepts", [])
				if oaccepts.size() == 1:
					olabel = Items.name_of(int(oaccepts[0]))
				var oy: float = top_y + output_count * row_h + SLOT_LARGE + 14
				draw_string(font, Vector2(right_x, oy), olabel,
					HORIZONTAL_ALIGNMENT_LEFT, SLOT_LARGE + 80, 12, TEXT_DIM)
				output_count += 1

	# Progress bar — centered between input column and output column,
	# vertically aligned with the FIRST input/output row.
	var progress: int = int(building.state.get("progress", 0))
	var max_progress: int = int(recipe.get("time_ticks", 1)) if not recipe.is_empty() else 1
	var fraction: float = clamp(float(progress) / float(max_progress), 0.0, 1.0) if max_progress > 0 else 0.0
	var bar_x: float = (left_x + SLOT_LARGE + right_x - PROGRESS_BAR_W) * 0.5
	var bar_y: float = top_y + (SLOT_LARGE - PROGRESS_BAR_H) * 0.5
	var bar_rect: Rect2 = Rect2(bar_x, bar_y, PROGRESS_BAR_W, PROGRESS_BAR_H)
	draw_rect(bar_rect, BAR_BG, true)
	if fraction > 0.0:
		var fill_color: Color = BAR_FILL_RUNNING if s == Processor.RUNNING else BAR_FILL_IDLE
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y)), fill_color, true)
	draw_rect(bar_rect, BAR_BORDER, false, 1.0)
	# Progress text overlay.
	var progress_text: String = "%d / %d" % [progress, max_progress]
	draw_string(font, bar_rect.position + Vector2(0, PROGRESS_BAR_H - 4),
		progress_text, HORIZONTAL_ALIGNMENT_CENTER, int(PROGRESS_BAR_W), 12, TEXT_COLOR)
	# Arrow head pointing right.
	var arrow_y: float = bar_y + PROGRESS_BAR_H * 0.5
	var arrow_tip_x: float = bar_x + PROGRESS_BAR_W + 12
	draw_line(Vector2(arrow_tip_x - 12, arrow_y - 6), Vector2(arrow_tip_x, arrow_y), TEXT_COLOR, 2.0)
	draw_line(Vector2(arrow_tip_x - 12, arrow_y + 6), Vector2(arrow_tip_x, arrow_y), TEXT_COLOR, 2.0)

	# Fuel-slot label (if present).
	for slot_def in layout:
		if str(slot_def.get("kind", "")) == "fuel":
			var fuel_y: float = top_y + input_count * row_h + 8
			var fuel_units: int = int(building.state.get(str(slot_def.get("state_field", "fuel_buffer")), 0))
			var fuel_cap: int = int(slot_def.get("max_stack", Burner.FUEL_BUFFER_CAPACITY))
			draw_string(font, Vector2(left_x + SlotWidget.SIZE + 12, fuel_y + 18),
				"Fuel: %d / %d units" % [fuel_units, fuel_cap],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)

	# Fluid-indicator widget (Retter, Yeast Culture). Positioned just below
	# the input column — same vertical band where a fuel slot would go for
	# fuel-using processors. Delegates to BuildingPanel.draw_fluid_indicator
	# (shared with MixerPanel) for visual uniformity.
	for slot_def in layout:
		if str(slot_def.get("kind", "")) == "fluid_indicator":
			var fluid_y: float = top_y + input_count * row_h + 8
			draw_fluid_indicator(font, slot_def, left_x, fluid_y)

	# Status row — below ALL columns (input, output, fuel, fluid_indicator).
	var status_y: float = _status_y()
	var status_text: String = "Status: " + Processor.STATE_NAMES[s] if s >= 0 and s < Processor.STATE_NAMES.size() else "Status: ?"
	var status_color: Color = STATUS_COLOR_IDLE
	match s:
		Processor.RUNNING:
			status_color = STATUS_COLOR_RUNNING
		Processor.BLOCKED_OUTPUT:
			status_color = STATUS_COLOR_BLOCKED
	draw_string(font, Vector2(left_x, status_y), status_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, status_color)

	# Recipe row.
	var recipe_y: float = status_y + 22
	var recipe_text: String
	if not recipe.is_empty():
		recipe_text = "Recipe: %s" % str(recipe.get("display_name", recipe_id))
	else:
		recipe_text = "Recipe: (none)"
	draw_string(font, Vector2(left_x, recipe_y), recipe_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)

	# Subclass-overridable subline (e.g. "Currently smelting: <recipe>" for
	# multi-recipe buildings). Default empty.
	var sub: String = _status_subline()
	if sub != "":
		draw_string(font, Vector2(left_x, recipe_y + 18), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)

## Subclass override hook for additional status text below the recipe line.
## Default empty. (Smelter would override to show "Currently smelting: ..."
## but smelter currently has its own independent panel; deferred refactor.)
func _status_subline() -> String:
	return ""
