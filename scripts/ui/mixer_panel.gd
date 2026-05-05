extends BuildingPanel

## Mixer UI (session-building-ui-2). Multi-input processor: flour + yeast
## solid + water fluid → dough.
##
## Layout (per Q9/Q10 design pass at session-building-ui-2):
##   ╔══════════════ Mixer ═══════════════════════╗
##   ║  ┌────┐ ┌────┐                ┌────┐       ║
##   ║  │Fl  │ │Yst │ ━━━ 40/100 ━━▶ │out │       ║
##   ║  └────┘ └────┘                └────┘       ║
##   ║   Flour  Yeast  (running)     Dough        ║
##   ║                                            ║
##   ║  Water: ◉ connected   (or ○ no pipe)       ║
##   ║                                            ║
##   ║  Status: Running                           ║
##   ╠════════════════════════════════════════════╣
##   ║              Player inventory              ║
##   ╚════════════════════════════════════════════╝
##
## Diverges from ProcessorPanel because of:
##   - 2 solid inputs side-by-side (not stacked)
##   - Fluid indicator widget (read-only — water is pipe-fed, not drag-drop)

const SLOT_LARGE: int = 64
const PROGRESS_BAR_W: float = 180.0
const PROGRESS_BAR_H: float = 18.0

const STATUS_COLOR_RUNNING: Color = Color(0.55, 0.85, 0.55)
const STATUS_COLOR_BLOCKED: Color = Color(1.00, 0.95, 0.40)
const STATUS_COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

const BAR_BG: Color = Color(0.12, 0.10, 0.08, 1.0)
const BAR_BORDER: Color = Color(0.40, 0.32, 0.20, 1.0)
const BAR_FILL_RUNNING: Color = Color(0.85, 0.65, 0.30, 1.0)
const BAR_FILL_IDLE: Color = Color(0.40, 0.40, 0.42, 1.0)

const FLUID_CONNECTED: Color = Color(0.30, 0.70, 1.00)    # blue (active)
const FLUID_NONE: Color = Color(0.45, 0.45, 0.48)         # gray (no pipe)

func _building_slot_rects() -> Array:
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var layout: Array = Buildings.slot_layout_for(building.type)
	var rects: Array = []

	# Top row: 2 input slots side-by-side on the left, output on the right.
	var top_y: float = area.position.y + 28
	var left_x: float = area.position.x + 24
	var right_x: float = area.position.x + area.size.x - SLOT_LARGE - 24

	var input_idx: int = 0
	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		match kind:
			"input":
				var x: float = left_x + input_idx * (SLOT_LARGE + 8)
				rects.append({"slot_def": slot_def, "rect": Rect2(x, top_y, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})
				input_idx += 1
			"output":
				rects.append({"slot_def": slot_def, "rect": Rect2(right_x, top_y, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})
			# fluid_indicator is render-only; not a click target.
	return rects

func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null:
		return
	var recipe_id: String = str(building.state.get("recipe_id", ""))
	var recipe: Dictionary = Recipes.get_recipe(recipe_id) if recipe_id != "" else {}
	var s: int = int(building.state.get("state", Processor.IDLE))
	var top_y: float = area.position.y + 28
	var left_x: float = area.position.x + 24
	var right_x: float = area.position.x + area.size.x - SLOT_LARGE - 24

	# Slot labels.
	var layout: Array = Buildings.slot_layout_for(building.type)
	var input_idx: int = 0
	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		if kind == "input":
			var lx: float = left_x + input_idx * (SLOT_LARGE + 8)
			var label: String = "Input"
			var accepts: Array = slot_def.get("accepts", [])
			if accepts.size() == 1:
				label = Items.name_of(int(accepts[0]))
			draw_string(font, Vector2(lx, top_y + SLOT_LARGE + 16), label,
				HORIZONTAL_ALIGNMENT_LEFT, SLOT_LARGE, 12, TEXT_DIM)
			input_idx += 1
		elif kind == "output":
			var olabel: String = "Output"
			var oaccepts: Array = slot_def.get("accepts", [])
			if oaccepts.size() == 1:
				olabel = Items.name_of(int(oaccepts[0]))
			draw_string(font, Vector2(right_x, top_y + SLOT_LARGE + 16), olabel,
				HORIZONTAL_ALIGNMENT_LEFT, SLOT_LARGE, 12, TEXT_DIM)

	# Progress bar between input column and output.
	var progress: int = int(building.state.get("progress", 0))
	var max_progress: int = int(recipe.get("time_ticks", 1)) if not recipe.is_empty() else 1
	var fraction: float = clamp(float(progress) / float(max_progress), 0.0, 1.0) if max_progress > 0 else 0.0
	var inputs_right_edge: float = left_x + (input_idx * (SLOT_LARGE + 8)) - 8 + SLOT_LARGE
	var bar_x: float = (inputs_right_edge + right_x - PROGRESS_BAR_W) * 0.5
	var bar_y: float = top_y + (SLOT_LARGE - PROGRESS_BAR_H) * 0.5
	var bar_rect: Rect2 = Rect2(bar_x, bar_y, PROGRESS_BAR_W, PROGRESS_BAR_H)
	draw_rect(bar_rect, BAR_BG, true)
	if fraction > 0.0:
		var fill_color: Color = BAR_FILL_RUNNING if s == Processor.RUNNING else BAR_FILL_IDLE
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * fraction, bar_rect.size.y)), fill_color, true)
	draw_rect(bar_rect, BAR_BORDER, false, 1.0)
	draw_string(font, bar_rect.position + Vector2(0, PROGRESS_BAR_H - 4),
		"%d / %d" % [progress, max_progress],
		HORIZONTAL_ALIGNMENT_CENTER, int(PROGRESS_BAR_W), 12, TEXT_COLOR)
	# Arrow head.
	var arrow_y: float = bar_y + PROGRESS_BAR_H * 0.5
	var arrow_tip_x: float = bar_x + PROGRESS_BAR_W + 12
	draw_line(Vector2(arrow_tip_x - 12, arrow_y - 6), Vector2(arrow_tip_x, arrow_y), TEXT_COLOR, 2.0)
	draw_line(Vector2(arrow_tip_x - 12, arrow_y + 6), Vector2(arrow_tip_x, arrow_y), TEXT_COLOR, 2.0)

	# Fluid indicator row — below input row.
	var fluid_y: float = top_y + SLOT_LARGE + 36
	for slot_def in layout:
		if str(slot_def.get("kind", "")) == "fluid_indicator":
			var fluid_type: int = int(slot_def.get("fluid_type", Fluids.Type.WATER))
			var connected: bool = false
			if world != null:
				connected = world.fluid_available_for_building(building, fluid_type)
			var dot_color: Color = FLUID_CONNECTED if connected else FLUID_NONE
			var dot_pos: Vector2 = Vector2(left_x + 6, fluid_y + 7)
			# Filled dot if connected, hollow ring if not.
			if connected:
				draw_circle(dot_pos, 6.0, dot_color)
			else:
				draw_arc(dot_pos, 6.0, 0.0, TAU, 16, dot_color, 2.0)
			var label: String = "%s: %s" % [
				Fluids.name_of(fluid_type),
				"connected" if connected else "no pipe network",
			]
			draw_string(font, Vector2(left_x + 22, fluid_y + 12), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR if connected else TEXT_DIM)

	# Status row.
	var status_y: float = fluid_y + 28
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
	var recipe_text: String = "Recipe: " + str(recipe.get("display_name", recipe_id)) if not recipe.is_empty() else "Recipe: (none)"
	draw_string(font, Vector2(left_x, recipe_y), recipe_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
