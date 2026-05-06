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
	# Single output slot, centered.
	var slot_x: float = area.position.x + (area.size.x - SLOT_LARGE) * 0.5
	var slot_y: float = area.position.y + 130
	for slot_def in layout:
		if str(slot_def.get("kind", "")) == "output":
			rects.append({"slot_def": slot_def, "rect": Rect2(slot_x, slot_y, SLOT_LARGE, SLOT_LARGE), "sub_idx": -1})
	return rects

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

	# Status text.
	var status_text: String
	var status_color: Color
	if ripe:
		status_text = "Status: Ripe — extract to start next cycle"
		status_color = STATUS_RIPE
	else:
		status_text = "Status: Growing %d%%" % int(round(pct * 100.0))
		status_color = STATUS_GROWING
	draw_string(font, Vector2(x, area.position.y + 100),
		status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_color)

	# "Output:" label above the centered output slot.
	draw_string(font, Vector2(x, area.position.y + 124),
		"Output:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)

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

func _take_from_slot(slot_def: Dictionary, _sub_idx: int) -> void:
	var kind: String = str(slot_def.get("kind", ""))
	if kind != "output":
		return    # planter has only an output slot; no other take paths
	var output: int = int(building.state.get("output", 0))
	if output <= 0:
		return
	# Use Planter.try_extract — same primitive harvester uses, so growth
	# resets correctly (Planter.try_extract resets growth=0 when output→0).
	var crop_type: int = Planter.try_extract(building)
	if crop_type < 0:
		return
	cursor.pick(crop_type, 1)

# ---------- override drop to reject any drop attempts on output ----------
# Standard BuildingPanel._drop_into_slot already rejects "output" kind via
# the read-only branch; that path works unchanged for planter. No override
# needed.
