extends BuildingPanel

## Inserter-specialized building panel
## (session-inserter-foundation, Inserter Arc Session 1).
##
## Layout:
##   ╔══════════════ Inserter ═══════════════╗
##   ║                                       ║
##   ║   Holding: ┌──┐    Status: WORKING    ║
##   ║           │ ●│    Cycle: 47%         ║
##   ║           └──┘                        ║
##   ║   ▓▓▓▓▓░░░░░░  cycle progress bar     ║
##   ║                                       ║
##   ║   Source:      Belt at (4, 5)         ║
##   ║   Destination: Chest at (6, 5)        ║
##   ║                                       ║
##   ║   ┌──┐                                ║
##   ║   │██│  Fuel: 12 / 16 units           ║
##   ║   └──┘  Cycle speed: 1.0s              ║
##   ║                                       ║
##   ║   Facing: E (R to rotate)             ║
##   ║                                       ║
##   ╠═══════════════════════════════════════╣
##   ║         Player inventory               ║
##   ╚════════════════════════════════════════╝

const PROGRESS_BAR_W: float = 220.0
const PROGRESS_BAR_H: float = 14.0
const BAR_BG: Color = Color(0.12, 0.10, 0.08, 1.0)
const BAR_BORDER: Color = Color(0.40, 0.32, 0.20, 1.0)
const BAR_FILL_WORKING: Color = Color(0.85, 0.65, 0.20, 1.0)        # bronze-orange
const BAR_FILL_BLOCKED: Color = Color(1.00, 0.85, 0.30, 1.0)        # yellow

# Status colors per inserter state.
const COLOR_WORKING: Color = Color(0.85, 0.95, 0.65)
const COLOR_BLOCKED: Color = Color(1.00, 0.85, 0.30)
const COLOR_NO_FUEL: Color = Color(0.55, 0.70, 1.00)
const COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

func _top_area_height() -> int:
	# Held item slot row (~70) + cycle bar row (~40) + source/dest text
	# (~50) + fuel slot row (~70) + facing line (~24) + padding.
	return 280

func _building_slot_rects() -> Array:
	# Two slots: held_item (top-left) + fuel (lower-left). Both small,
	# positioned so the right side of the panel can render text.
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var slot_size: int = SlotWidget.SIZE
	var rects: Array = []
	var x: float = area.position.x + 24
	var layout: Array = Buildings.slot_layout_for(building.type)
	# held_item slot at y_offset 30
	# fuel slot at y_offset 160
	var y_offsets: Dictionary = {
		"held_item": 30,
		"fuel": 160,
	}
	for slot_def in layout:
		var sid: String = str(slot_def.get("id", ""))
		var y_off = y_offsets.get(sid, 30)
		rects.append({
			"slot_def": slot_def,
			"rect": Rect2(x, area.position.y + float(y_off), slot_size, slot_size),
			"sub_idx": -1,
		})
	return rects

func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null:
		return
	var slot_size: int = SlotWidget.SIZE
	var label_x: float = area.position.x + 24 + slot_size + 18

	# --- Held item label ---
	draw_string(font, Vector2(label_x, area.position.y + 30 + 16),
		"Holding:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)
	var held_tier: int = Inserter.held_item_type(building)
	if held_tier >= 0:
		draw_string(font, Vector2(label_x, area.position.y + 30 + 36),
			Items.name_of(held_tier), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Items.color_of(held_tier))
	else:
		draw_string(font, Vector2(label_x, area.position.y + 30 + 36),
			"(empty)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_DIM)

	# --- Status (top-right) ---
	var s: int = int(building.state.get("state", Inserter.STATE_IDLE))
	var status_text: String
	var status_color: Color
	match s:
		Inserter.STATE_IDLE:
			status_text = "Status: IDLE"
			status_color = COLOR_IDLE
		Inserter.STATE_WORKING_OUT:
			status_text = "Status: WORKING (out)"
			status_color = COLOR_WORKING
		Inserter.STATE_BLOCKED_AT_DEST:
			status_text = "Status: BLOCKED at destination"
			status_color = COLOR_BLOCKED
		Inserter.STATE_WORKING_IN:
			status_text = "Status: WORKING (returning)"
			status_color = COLOR_WORKING
		Inserter.STATE_NO_FUEL:
			status_text = "Status: NO FUEL"
			status_color = COLOR_NO_FUEL
	draw_string(font, Vector2(label_x + 160, area.position.y + 30 + 16),
		status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, status_color)

	# --- Cycle progress bar ---
	var bar_x: float = label_x
	var bar_y: float = area.position.y + 30 + 56
	var cycle_progress: float = float(building.state.get("cycle_progress", 0.0))
	draw_rect(Rect2(bar_x, bar_y, PROGRESS_BAR_W, PROGRESS_BAR_H), BAR_BG, true)
	var fill_color: Color = BAR_FILL_BLOCKED if s == Inserter.STATE_BLOCKED_AT_DEST else BAR_FILL_WORKING
	draw_rect(Rect2(bar_x, bar_y, PROGRESS_BAR_W * cycle_progress, PROGRESS_BAR_H), fill_color, true)
	draw_rect(Rect2(bar_x, bar_y, PROGRESS_BAR_W, PROGRESS_BAR_H), BAR_BORDER, false, 1.5)
	draw_string(font, Vector2(bar_x + PROGRESS_BAR_W + 12, bar_y + 12),
		"%.0f%%" % (cycle_progress * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)

	# --- Source / destination summary ---
	var src_y: float = area.position.y + 30 + 88
	var src: Vector2i = Inserter.source_tile(building)
	var dst: Vector2i = Inserter.dest_tile(building)
	draw_string(font, Vector2(label_x, src_y),
		"Source:      %s" % _tile_summary(src),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)
	draw_string(font, Vector2(label_x, src_y + 18),
		"Destination: %s" % _tile_summary(dst),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)

	# --- Fuel info next to fuel slot ---
	var fuel_y: float = area.position.y + 160 + 16
	var fuel: int = int(building.state.get("fuel_buffer", 0))
	draw_string(font, Vector2(label_x, fuel_y),
		"Fuel: %d / %d units" % [fuel, Burner.FUEL_BUFFER_CAPACITY],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
	# Cycle speed is fixed (independent of fuel tier — see inserter.gd
	# header for the reversal rationale). Fuel tier affects fuel ECONOMY
	# (energy density: wood=1, coal=4, briquette=8 units per item).
	var cycle_seconds: float = float(Inserter.CYCLE_TICKS) / 20.0
	draw_string(font, Vector2(label_x, fuel_y + 22),
		"Cycle speed: %.1fs (fixed)" % cycle_seconds,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)

	# --- Facing ---
	var dir: int = int(building.state.get("dir", 0))
	draw_string(font, Vector2(area.position.x + 24, area.position.y + 240),
		"Facing: %s   (R to rotate before placing; in NEUTRAL hover R rotates the placed inserter)" % Belt.DIR_NAMES[dir],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)

func _tile_summary(pos: Vector2i) -> String:
	if world == null:
		return "(no world ref)"
	if not world.has_building_at(pos):
		return "(empty) at %s" % str(pos)
	var b: Building = world.building_at(pos)
	if b == null:
		return "(empty) at %s" % str(pos)
	return "%s at %s" % [Buildings.name_of(b.type), str(pos)]
