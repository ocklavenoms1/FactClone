extends BuildingPanel

## Planter UI (session-building-ui-4). Single panel handles all 3 planter
## variants (Wheat / Sugar Beet / Flax) — they share Buildings.Type.PLANTER
## with crop_type set at placement time. Panel reads crop_type from state
## per-open and adjusts the title and output slot color/label accordingly.
##
## Layout (per Q4 design pass):
##   ╔═══════ <Crop> Planter ════════════════╗
##   ║  Crop: <Crop name>                    ║
##   ║                                       ║
##   ║  Growth: ━━━━━━░░░ 470 / 600 ticks   ║
##   ║  Status: Growing 78%                   ║
##   ║                                       ║
##   ║  Output: ┌────┐                       ║
##   ║          │  W │  (ripe)               ║
##   ║          └────┘                       ║
##   ╠═══════════════════════════════════════╣
##   ║         Player inventory              ║
##   ╚═══════════════════════════════════════╝
##
## Diverges from ProcessorPanel because:
##   - Planter's `output` is an int (0 or 1), not Array of [type, count].
##     Standard slot_layout drag-drop assumes array-shaped buffers; planter
##     overrides _take_from_slot for the single output to handle the int.
##   - No input slot (crops grow autonomously; type set at placement).
##   - Growth fraction comes from Planter.growth_pct(b), not recipe progress.

const SLOT_LARGE: int = 64
const PROGRESS_BAR_W: float = 240.0
const PROGRESS_BAR_H: float = 18.0

const STATUS_GROWING: Color = Color(0.55, 0.85, 0.55)
const STATUS_RIPE: Color = Color(1.00, 0.85, 0.30)
const STATUS_DEPLETED: Color = Color(0.95, 0.45, 0.45)    # red — soil dead
const SOIL_REGEN_COLOR: Color = Color(0.55, 0.85, 0.55)   # green — regen
const SOIL_ACTIVE_COLOR: Color = Color(0.95, 0.80, 0.40)  # yellow — active farming

const BAR_BG: Color = Color(0.12, 0.10, 0.08, 1.0)
const BAR_BORDER: Color = Color(0.40, 0.32, 0.20, 1.0)
const BAR_FILL_GROWING: Color = Color(0.50, 0.75, 0.35, 1.0)    # leafy green
const BAR_FILL_RIPE: Color = Color(1.00, 0.85, 0.30, 1.0)       # ripe yellow

func _building_slot_rects() -> Array:
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var layout: Array = Buildings.slot_layout_for(building.type)
	var rects: Array = []
	# Single output slot, centered. Lower position than Session 1 to make
	# room for the 3×3 soil mini-grid above.
	var slot_x: float = area.position.x + (area.size.x - SLOT_LARGE) * 0.5
	var slot_y: float = area.position.y + 200
	for slot_def in layout:
		if str(slot_def.get("kind", "")) == "output":
			rects.append({"slot_def": slot_def, "rect": Rect2(slot_x, slot_y, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})
	return rects

## Override _top_area_height — soil mini-grid + status + output slot need
## ~290px (vs default 280). Slight bump.
func _top_area_height() -> int:
	return 300

func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null:
		return
	var crop_type: int = Planter.crop_of(building)
	var growth: int = int(building.state.get("growth", 0))
	var output: int = int(building.state.get("output", 0))
	var max_growth: int = Planter.max_growth_for(crop_type)
	var pct: float = Planter.growth_pct(building)
	var ripe: bool = output > 0

	var x: float = area.position.x + 24

	# Crop label (replaces the default "<building name>" title).
	var crop_text: String = "Crop: %s" % Items.name_of(crop_type)
	draw_string(font, Vector2(x, area.position.y + 28),
		crop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)

	# Progress bar.
	var bar_x: float = x
	var bar_y: float = area.position.y + 60
	var bar_rect: Rect2 = Rect2(bar_x, bar_y, PROGRESS_BAR_W, PROGRESS_BAR_H)
	draw_rect(bar_rect, BAR_BG, true)
	if pct > 0.0:
		var fill_color: Color = BAR_FILL_RIPE if ripe else BAR_FILL_GROWING
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), fill_color, true)
	draw_rect(bar_rect, BAR_BORDER, false, 1.0)
	# Bar overlay text.
	var bar_text: String = "%d / %d ticks" % [growth, max_growth]
	draw_string(font, bar_rect.position + Vector2(0, PROGRESS_BAR_H - 4),
		bar_text, HORIZONTAL_ALIGNMENT_CENTER, int(PROGRESS_BAR_W), 12, TEXT_COLOR)

	# Soil 3×3 mini-grid (session-soil-exhaustion-2 per-tile refactor).
	# Renders the planter's center tile + 8 neighbors with each cell
	# color-coded by SoilLevel and labeled with the soil value. Center
	# cell highlighted. Average across 9 tiles displayed alongside.
	if world != null:
		_draw_soil_grid_3x3(font, x, area.position.y + 80)

	# Center-tile soil — gates new growth (Session 1 behavior preserved).
	# This is the "soil that matters for *this* planter starting a new cycle."
	# Neighbors track soil too but don't gate this planter.
	var center_soil: int = world.tile_soil_health(building.anchor) if world != null else 100

	# Status text. Soil-zero behavior keys off CENTER tile soil (the gate
	# logic in Planter.tick checks tile_soil_health(b.anchor)).
	# Wasteland (session-soil-exhaustion-4) is the most prominent state —
	# overrides the soil-zero messaging because it's a more permanent
	# loss that requires a specific recovery action.
	var center_wasteland: bool = world != null and world.is_wasteland_at(building.anchor)
	var status_text: String
	var status_color: Color
	if center_wasteland and growth == 0:
		# Wasteland blocks new cycles entirely — Premium Compost required.
		status_text = "Status: IDLE — tile %s is WASTELAND" % str(building.anchor)
		status_color = STATUS_DEPLETED
	elif ripe:
		if center_soil <= 0:
			status_text = "Status: Ripe — extract; center soil depleted, no new crop"
			status_color = STATUS_DEPLETED
		else:
			status_text = "Status: Ripe — extract to start next cycle"
			status_color = STATUS_RIPE
	elif center_soil <= 0 and growth == 0:
		status_text = "Status: Center tile DEPLETED — no new crops"
		status_color = STATUS_DEPLETED
	elif center_soil <= 0 and growth > 0:
		status_text = "Status: Growing %d%% (soil depleted; cycle finishes)" % int(round(pct * 100.0))
		status_color = STATUS_DEPLETED
	else:
		status_text = "Status: Growing %d%%" % int(round(pct * 100.0))
		status_color = STATUS_GROWING
	draw_string(font, Vector2(x, area.position.y + 168),
		status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_color)
	# Wasteland action prompt — second line below the status, only when
	# the planter is wasteland-idled.
	if center_wasteland and growth == 0:
		draw_string(font, Vector2(x, area.position.y + 184),
			"Action: Apply Premium Compost to %s." % str(building.anchor),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, STATUS_DEPLETED)

	# "Output:" label above the centered output slot (now at y=200).
	draw_string(font, Vector2(x, area.position.y + 192),
		"Output:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)

# ---------- 3×3 soil mini-grid (session-soil-exhaustion-2) ----------

const MINI_CELL: int = 28
const MINI_GAP: int = 2

# Tints for each soil level (alpha-blended over a dark cell background).
const MINI_TINT_PRISTINE: Color = Color(0.30, 0.55, 0.30, 0.95)   # rich green
const MINI_TINT_HEALTHY: Color  = Color(0.45, 0.60, 0.30, 0.95)   # mild green
const MINI_TINT_DAMAGED: Color  = Color(0.85, 0.75, 0.35, 0.95)   # yellow-brown
const MINI_TINT_DYING: Color    = Color(0.65, 0.45, 0.25, 0.95)   # brown
const MINI_TINT_DEAD: Color     = Color(0.35, 0.20, 0.12, 0.95)   # dark cracked

const MINI_BORDER_NORMAL: Color = Color(0.10, 0.08, 0.06, 1.0)
const MINI_BORDER_CENTER: Color = Color(1.00, 0.92, 0.55, 1.0)    # highlight planter's tile

## Render the 3×3 soil mini-grid at top-left (origin_x, origin_y). Each
## cell shows its tile's soil value tinted by SoilLevel. Center cell has
## a yellow border (planter's anchor tile). Aggregate average shown to
## the right.
func _draw_soil_grid_3x3(font: Font, origin_x: float, origin_y: float) -> void:
	var anchor: Vector2i = building.anchor
	var total: int = 0
	# Mini-grid header.
	draw_string(font, Vector2(origin_x, origin_y), "Soil area (3×3):",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
	# 9 cells.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var pos: Vector2i = Vector2i(anchor.x + dx, anchor.y + dy)
			var soil: int = world.tile_soil_health(pos)
			total += soil
			var rect_x: float = origin_x + (dx + 1) * (MINI_CELL + MINI_GAP)
			var rect_y: float = origin_y + 16 + (dy + 1) * (MINI_CELL + MINI_GAP)
			var cell: Rect2 = Rect2(rect_x, rect_y, MINI_CELL, MINI_CELL)
			var tint: Color = _mini_tint_for_level(world.tile_soil_level(pos))
			draw_rect(cell, tint, true)
			# Border — center tile highlighted.
			var is_center: bool = (dx == 0 and dy == 0)
			var border: Color = MINI_BORDER_CENTER if is_center else MINI_BORDER_NORMAL
			var border_w: float = 2.0 if is_center else 1.0
			draw_rect(cell, border, false, border_w)
			# Soil value label centered in cell.
			draw_string(font, Vector2(cell.position.x, cell.position.y + MINI_CELL * 0.5 + 4),
				str(soil), HORIZONTAL_ALIGNMENT_CENTER, MINI_CELL, 11, Color.WHITE)

	# Aggregate / status to the right of the grid.
	var avg: int = total / 9
	var grid_right_x: float = origin_x + 3 * (MINI_CELL + MINI_GAP) + 16
	var center_pos: Vector2i = anchor
	var center_soil: int = world.tile_soil_health(center_pos)
	var center_level: int = world.tile_soil_level(center_pos)
	var level_text: String = _level_name(center_level)
	draw_string(font, Vector2(grid_right_x, origin_y + 24),
		"Center: %d / 100" % center_soil,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _level_color(center_level))
	draw_string(font, Vector2(grid_right_x, origin_y + 40),
		"  (%s)" % level_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _level_color(center_level))
	draw_string(font, Vector2(grid_right_x, origin_y + 60),
		"Average: %d / 100" % avg,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)
	# Activity status (active farming nearby / regenerating).
	var center_activity: int = world.tile_soil_activity(center_pos)
	var activity_text: String = ""
	var activity_color: Color = TEXT_DIM
	match center_activity:
		GridWorld.SoilActivity.ACTIVE_FARMING:
			activity_text = "active farming"
			activity_color = SOIL_ACTIVE_COLOR
		GridWorld.SoilActivity.REGENERATING:
			activity_text = "regenerating"
			activity_color = SOIL_REGEN_COLOR
		GridWorld.SoilActivity.NONE:
			activity_text = "pristine"
			activity_color = TEXT_DIM
	draw_string(font, Vector2(grid_right_x, origin_y + 76),
		activity_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, activity_color)

static func _mini_tint_for_level(level: int) -> Color:
	match level:
		GridWorld.SoilLevel.PRISTINE:
			return MINI_TINT_PRISTINE
		GridWorld.SoilLevel.HEALTHY:
			return MINI_TINT_HEALTHY
		GridWorld.SoilLevel.DAMAGED:
			return MINI_TINT_DAMAGED
		GridWorld.SoilLevel.DYING:
			return MINI_TINT_DYING
		GridWorld.SoilLevel.DEAD:
			return MINI_TINT_DEAD
	return MINI_TINT_PRISTINE

static func _level_name(level: int) -> String:
	match level:
		GridWorld.SoilLevel.PRISTINE: return "pristine"
		GridWorld.SoilLevel.HEALTHY:  return "healthy"
		GridWorld.SoilLevel.DAMAGED:  return "damaged"
		GridWorld.SoilLevel.DYING:    return "dying"
		GridWorld.SoilLevel.DEAD:     return "DEAD"
	return ""

static func _level_color(level: int) -> Color:
	match level:
		GridWorld.SoilLevel.DAMAGED, GridWorld.SoilLevel.DYING:
			return SOIL_ACTIVE_COLOR
		GridWorld.SoilLevel.DEAD:
			return STATUS_DEPLETED
	return TEXT_COLOR

# ---------- override slot data lookup for int-typed output ----------
#
# BuildingPanel's _draw_slots assumes state[field] is an Array of [type, count].
# Planter's output is `int` (0 or 1 of crop_type). Override to render
# correctly when the output is ripe.

func _draw_slots(font: Font) -> void:
	if building == null:
		return
	for entry in _building_slot_rects():
		var slot_def: Dictionary = entry["slot_def"]
		var rect: Rect2 = entry["rect"]
		var output: int = int(building.state.get("output", 0))
		var item_type: int = -1
		var count: int = 0
		if output > 0:
			item_type = Planter.crop_of(building)
			count = output
		var hovered: bool = false
		if _hover is Dictionary:
			var h: Dictionary = _hover
			if h.get("slot_def", {}) == slot_def:
				hovered = true
		var border_tint: Color = SlotWidget.border_for_kind(str(slot_def.get("kind", "")))
		SlotWidget.draw_slot(self, font, rect, item_type, count, hovered, border_tint)

# ---------- override take to handle int-typed output ----------

func _take_from_slot(slot_def: Dictionary, _sub_idx: int, _mods: int = SlotClickHandler.MOD_NONE) -> void:
	var kind: String = str(slot_def.get("kind", ""))
	if kind != "output":
		return    # planter has only an output slot; no other take paths
	var output: int = int(building.state.get("output", 0))
	if output <= 0:
		return
	# Use Planter.try_extract — same primitive harvester uses, so growth
	# resets correctly (Planter.try_extract resets growth=0 when output→0).
	var crop_type: int = Planter.try_extract(building, world)
	if crop_type < 0:
		return
	cursor.pick(crop_type, 1)

# ---------- override drop to reject any drop attempts on output ----------
# Standard BuildingPanel._drop_into_slot already rejects "output" kind via
# the read-only branch; that path works unchanged for planter. No override
# needed.
