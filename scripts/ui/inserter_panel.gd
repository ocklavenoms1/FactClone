class_name InserterPanel
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
##   ║   └──┘  Cycle speed: 1.00s             ║
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
# NO POWER (electric tiers). Warm amber against COLOR_NO_FUEL's cool blue —
# the two stalls have different causes and different fixes, so the status
# line must distinguish them by colour as well as by text. Unlike the map
# tints in inserter.gd these are drawn directly rather than multiplied into
# a body colour, so an actual amber is available here.
const COLOR_NO_POWER: Color = Color(1.00, 0.62, 0.25)
const COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

func _top_area_height() -> int:
	# Held item slot row (~70) + cycle bar row (~40) + source/dest text
	# (~50) + fuel slot row (~70) + facing line (~24) + padding.
	return 280

## Y-offset of each slot id within the panel's top area. Virtual hook
## for subclasses (FastInserterPanel adds a "filter" entry; future tiers
## extend the same way). Default = basic inserter (held_item + fuel).
func _slot_y_offsets() -> Dictionary:
	return {
		"held_item": 30,
		"fuel":      160,
	}

func _building_slot_rects() -> Array:
	# Slots positioned by id via _slot_y_offsets() — subclasses inject
	# additional rows by overriding the virtual.
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var slot_size: int = SlotWidget.SIZE
	var rects: Array = []
	var x: float = area.position.x + 24
	var layout: Array = Buildings.slot_layout_for(building.type)
	var y_offsets: Dictionary = _slot_y_offsets()
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
		Inserter.STATE_NO_POWER:
			# Its own entry, not folded into NO_FUEL: distinct text and
			# distinct colour are the entire point of the line.
			status_text = "Status: NO POWER"
			status_color = COLOR_NO_POWER
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
	# BURNER TIERS ONLY. Inserter.make copies Burner state onto every tier,
	# so an electric inserter carries a permanently-zero fuel_buffer and this
	# row used to report "Fuel: 0 / 16 units" on a tier with no fuel slot at
	# all — the same wart Task 7 item C fixed in Inserter.info_lines. The
	# cycle line moves up into the vacated row when it is skipped.
	var fuel_y: float = area.position.y + 160 + 16
	var cycle_y: float = fuel_y
	if not Inserter.is_electric(building):
		var fuel: int = int(building.state.get("fuel_buffer", 0))
		draw_string(font, Vector2(label_x, fuel_y),
			"Fuel: %d / %d units" % [fuel, Burner.FUEL_BUFFER_CAPACITY],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
		cycle_y = fuel_y + 22

	# Cycle speed. Fixed per tier for BURNER tiers (independent of fuel tier
	# — see inserter.gd header for the reversal rationale; fuel tier affects
	# fuel ECONOMY, energy density wood=1 / coal=4 / briquette=8, not speed).
	# NOT fixed for the electric tier: since Task 6 its cycle stretches with
	# network satisfaction, which is why the old "(fixed)" label is gone — it
	# became false for one tier, and PAUSE 1 asks a human to confirm the
	# slowdown against exactly this text.
	#
	# So: report the EFFECTIVE cycle, and name the rating beside it when the
	# two differ — which is precisely the case a player needs explained. Two
	# decimals because the electric tier's 0.25s rating renders as the wrong
	# number ("0.3s") under %.1f.
	#
	# effective_cycle_ticks needs a world; BuildingPanel.world is set in
	# open() and cleared in close(), and _tile_summary below already treats
	# null as reachable, so fall back to the rating rather than assuming.
	var rated_ticks: int = Inserter.cycle_ticks(building)
	var eff_ticks: int = rated_ticks
	if world != null:
		eff_ticks = Inserter.effective_cycle_ticks(building, world)
	var cycle_text: String = "Cycle speed: %.2fs" % (float(eff_ticks) / 20.0)
	if eff_ticks != rated_ticks:
		cycle_text = "Cycle speed: %.2fs (rated %.2fs)" % [float(eff_ticks) / 20.0, float(rated_ticks) / 20.0]
	draw_string(font, Vector2(label_x, cycle_y),
		cycle_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)

	# --- Facing ---
	# Anchored 40px from the bottom of the top area so subclasses with
	# additional rows (FastInserterPanel adds a filter slot row) get the
	# facing line in the right place automatically.
	var dir: int = int(building.state.get("dir", 0))
	draw_string(font, Vector2(area.position.x + 24, area.position.y + area.size.y - 40),
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
