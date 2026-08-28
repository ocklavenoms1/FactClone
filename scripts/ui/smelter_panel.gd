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
# NO POWER (electric variant). Warm amber against COLOR_NO_FUEL's cool blue —
# the two stalls have different causes and different fixes, so the status
# line must distinguish them by colour as well as by text. Copied verbatim
# from inserter_panel.gd's COLOR_NO_POWER (the shipped precedent);
# test_electric_smelter.gd pins the literal.
const COLOR_NO_POWER: Color = Color(1.00, 0.62, 0.25)
const COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

## The panel's state → status-line mapping. PURE, and static, so it can be
## asserted without a font, a frame or a window — the smelter-panel sub-cases
## of test_electric_smelter.gd are the assertion. It used to live inline in
## _draw_building_specific, where no suite could reach it (test_runner.gd
## never yields a frame, so no CanvasItem receives NOTIFICATION_DRAW during a
## headless run — docs/scoping/visual-verification.md route A, the
## InserterPanel.status_line precedent).
##
## Returns { "text": String, "color": Color }.
##
## The fallback arm preserves the pre-Task-5 inline default EXACTLY: an
## unmatched state (including STATE_IDLE's 0) reads "Status: Idle". The
## inserter panel's loud magenta "Status: ?" fallback is the better shape,
## but adopting it here changes what an out-of-range state renders, and
## Task 5's burner contract is byte-identity — left for a scoped session.
static func status_line(state: int) -> Dictionary:
	match state:
		Smelter.STATE_SMELTING:
			return {"text": "Status: Smelting", "color": COLOR_SMELTING}
		Smelter.STATE_NO_FUEL:
			return {"text": "Status: NO FUEL — feed wood, coal, or fuel briquette", "color": COLOR_NO_FUEL}
		Smelter.STATE_BLOCKED_OUTPUT:
			return {"text": "Status: Output blocked", "color": COLOR_BLOCKED}
		Smelter.STATE_NO_POWER:
			# Its own arm, not folded into NO_FUEL: distinct text and distinct
			# colour are the entire point of the line. ⚠ Smelter's NO_POWER is
			# 4; MiningDrill's is 5 (its 4 is DEPLETED) — always the MODULE
			# constant here, never a literal shared with the drill panel.
			return {"text": "Status: NO POWER", "color": COLOR_NO_POWER}
	return {"text": "Status: Idle", "color": COLOR_IDLE}

## Whether the fuel LABEL/units row renders. The fuel slot RECT already
## vanishes on its own for the electric variant (no "fuel" slot_def in
## ELECTRIC_SMELTER's slot_layout — pinned by test_electric_smelter.gd (3));
## this predicate is the text half of the same fact. Gated on the MODULE's
## is_electric, never a local type check — one source of truth.
static func shows_fuel_row(b: Building) -> bool:
	return not Smelter.is_electric(b)

## The denominator the progress bar renders against (fill fraction AND the
## "N / M" overlay). Burner: the recipe's rated time_ticks, unchanged.
## Electric: the EFFECTIVE target — recomputed from live satisfaction, the
## same number the machine itself races (target-stretch), so a brownout
## visibly stretches the bar instead of the bar lying about time remaining.
## The empty-recipe guard runs FIRST for both variants: _effective_target
## indexes recipe["time_ticks"], and "no recipe selected yet" must stay the
## pre-Task-5 "0 / 1" render, not a crash.
static func progress_target(b: Building, world_ref, recipe: Dictionary) -> int:
	if recipe.is_empty():
		return 1
	if Smelter.is_electric(b):
		return Smelter._effective_target(b, world_ref, recipe)
	return int(recipe.get("time_ticks", 1))

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

	# Bottom row: fuel slot. The electric variants inherit this row layout;
	# the empty fuel-row gap is DELIBERATE (user decision 2026-08-27) — do
	# not compact it blind: the gap is where the burner's fuel slot sits,
	# and compaction is a design decision, not a cleanup.
	# test_electric_smelter.gd (21) pins this comment's phrase.
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
	var max_progress: int = progress_target(building, world, recipe)
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

	# Fuel slot label (right of the fuel slot). The slot RECT is layout-driven
	# and vanishes on its own for the electric variant; the label is drawn
	# here, so it carries its own gate.
	var row2_y: float = row1_y + SLOT_LARGE + 50
	if shows_fuel_row(building):
		var fuel_x: float = area.position.x + 24
		var fuel_label_x: float = fuel_x + FUEL_SLOT_SIZE + 16
		var fuel_units: int = int(building.state.get("fuel_buffer", 0))
		var fuel_cap: int = int(Burner.FUEL_BUFFER_CAPACITY)
		var fuel_text: String = "Fuel: %d / %d units" % [fuel_units, fuel_cap]
		draw_string(font, Vector2(fuel_label_x, row2_y + 18),
			fuel_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)
		draw_string(font, Vector2(fuel_label_x, row2_y + 36),
			"(accepts: Wood, Coal, Briquette)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)

	# Status row below fuel. The mapping lives in status_line (pure, static)
	# so the suite can assert it — route A.
	var status_y: float = row2_y + FUEL_SLOT_SIZE + 24
	var status: Dictionary = status_line(s)
	draw_string(font, Vector2(area.position.x + 24, status_y),
		String(status["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, status["color"])

	# Currently smelting line (sits below status, smaller).
	var current_text: String
	if not recipe.is_empty():
		current_text = "Currently smelting: %s" % str(recipe.get("display_name", recipe_id))
	else:
		current_text = "Currently smelting: (none — feed iron or copper ore)"
	draw_string(font, Vector2(area.position.x + 24, status_y + 22),
		current_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)
