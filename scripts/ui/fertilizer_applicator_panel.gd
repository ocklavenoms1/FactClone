extends BuildingPanel

## Fertilizer-Applicator-specialized building panel
## (session-soil-exhaustion-3-5).
##
## Layout (per Q6 design):
##   ╔═══════ Fertilizer Applicator ══════╗
##   ║                                     ║
##   ║  Coverage: 5×5 (25 tiles)           ║
##   ║  Eligible: N    Next apply: in X.Xs ║
##   ║                                     ║
##   ║  ┌──┬──┬──┬──┬──┐                   ║
##   ║  │  │● │  │● │  │   ● fertilized    ║
##   ║  ├──┼──┼──┼──┼──┤   ▲ eligible      ║
##   ║  │● │▲ │▲ │  │  │   · pristine      ║
##   ║  ├──┼──┼──┼──┼──┤   ▓ impassable    ║
##   ║  │  │▲ │A │▲ │  │   A applicator    ║
##   ║  ├──┼──┼──┼──┼──┤                   ║
##   ║  │  │  │▲ │● │  │                   ║
##   ║  ├──┼──┼──┼──┼──┤                   ║
##   ║  │  │  │  │  │  │                   ║
##   ║  └──┴──┴──┴──┴──┘                   ║
##   ║                                     ║
##   ║       ┌────┐                        ║
##   ║       │ in │  Status: SCANNING      ║
##   ║       └────┘                        ║
##   ║                                     ║
##   ╠═════════════════════════════════════╣
##   ║         Player inventory             ║
##   ╚══════════════════════════════════════╝

const COVERAGE_CELL: int = 46
const COVERAGE_GAP: int = 2
const COVERAGE_GRID_PX: int = COVERAGE_CELL * 5 + COVERAGE_GAP * 4   # 238

# Cell colors per state.
const CELL_PRISTINE: Color = Color(0.20, 0.30, 0.20, 0.85)         # dim sage
const CELL_ELIGIBLE: Color = Color(0.55, 0.50, 0.20, 0.95)         # mustard yellow
const CELL_FERT_LOW: Color = Color(0.45, 0.75, 0.35, 0.95)         # light green
const CELL_FERT_MID: Color = Color(0.20, 0.55, 0.25, 0.95)         # saturated green
const CELL_IMPASSABLE: Color = Color(0.10, 0.12, 0.15, 0.85)       # near-black
const CELL_BORDER: Color = Color(0.05, 0.05, 0.05)
const CELL_BORDER_ANCHOR: Color = Color(1.0, 0.92, 0.40)           # bright yellow on the applicator's own cell

# Status colors (mirror FertilizerApplicator state ints).
const COLOR_SCANNING: Color = Color(0.60, 0.95, 0.55)
const COLOR_BLOCKED: Color = Color(1.00, 0.85, 0.30)
const COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

func _top_area_height() -> int:
	# Header (~50) + grid (238) + below-grid status row (~70) + padding.
	return 380

func _building_slot_rects() -> Array:
	# Single input slot, centered horizontally below the coverage grid.
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var grid_top: float = area.position.y + 60
	var grid_bottom: float = grid_top + COVERAGE_GRID_PX
	var slot_y: float = grid_bottom + 24
	var slot_x: float = area.position.x + (area.size.x - SlotWidget.SIZE) * 0.5 - 60
	# Single slot: input.
	var layout: Array = Buildings.slot_layout_for(building.type)
	var rects: Array = []
	for slot_def in layout:
		if str(slot_def.get("kind", "")) == "input":
			rects.append({"slot_def": slot_def, "rect": Rect2(slot_x, slot_y, SlotWidget.SIZE, SlotWidget.SIZE), "sub_idx": -1})
	return rects

func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null or world == null:
		return

	# --- Header: Coverage + Eligible + Next apply ---
	var hx: float = area.position.x + 24
	var hy: float = area.position.y + 14
	draw_string(font, Vector2(hx, hy), "Coverage: 5×5 (25 tiles)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)

	# Eligible count + next-apply countdown on second header line.
	var tier: int = FertilizerApplicator._select_fertilizer_from_buffer(building)
	var eligible_text: String
	if tier >= 0:
		var n: int = FertilizerApplicator._count_eligible_tiles(building, world, tier)
		eligible_text = "Eligible: %d (for %s)" % [n, Items.name_of(tier)]
	else:
		eligible_text = "Eligible: — (no fertilizer in input)"
	draw_string(font, Vector2(hx, hy + 18), eligible_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)

	# Next-apply countdown in the header — only shown while SCANNING (where
	# the countdown is meaningful). IDLE / BLOCKED rely on the bottom Status
	# line for state communication; duplicating "BLOCKED" in the header
	# both wastes space and overflows the panel right edge.
	var s: int = int(building.state.get("state", FertilizerApplicator.STATE_IDLE))
	if s == FertilizerApplicator.STATE_SCANNING:
		var remaining_ticks: int = FertilizerApplicator.APPLY_INTERVAL_TICKS - int(building.state.get("scan_progress", 0))
		var remaining_sec: float = float(remaining_ticks) / 20.0
		var countdown_text: String = "Next apply: in %.1fs" % remaining_sec
		draw_string(font, Vector2(hx + 240, hy + 18), countdown_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_SCANNING)

	# --- 5×5 coverage mini-grid ---
	# Centered horizontally in the panel area.
	var grid_left: float = area.position.x + (area.size.x - COVERAGE_GRID_PX) * 0.5
	var grid_top: float = area.position.y + 60

	for dy in range(-FertilizerApplicator.COVERAGE_RADIUS, FertilizerApplicator.COVERAGE_RADIUS + 1):
		for dx in range(-FertilizerApplicator.COVERAGE_RADIUS, FertilizerApplicator.COVERAGE_RADIUS + 1):
			var col: int = dx + FertilizerApplicator.COVERAGE_RADIUS   # 0..4
			var row: int = dy + FertilizerApplicator.COVERAGE_RADIUS   # 0..4
			var cell_x: float = grid_left + col * (COVERAGE_CELL + COVERAGE_GAP)
			var cell_y: float = grid_top + row * (COVERAGE_CELL + COVERAGE_GAP)
			var cell_rect: Rect2 = Rect2(cell_x, cell_y, COVERAGE_CELL, COVERAGE_CELL)
			var pos: Vector2i = Vector2i(building.anchor.x + dx, building.anchor.y + dy)

			# Determine cell color based on tile state.
			var bg: Color = _cell_color(pos)
			draw_rect(cell_rect, bg, true)
			# Anchor cell gets a bright border so the applicator's own
			# position stands out in the grid.
			if dx == 0 and dy == 0:
				draw_rect(cell_rect, CELL_BORDER_ANCHOR, false, 2.5)
			else:
				draw_rect(cell_rect, CELL_BORDER, false, 1.0)

	# --- Status text next to input slot ---
	# Slot is positioned at slot_x by _building_slot_rects; status text
	# sits to its right.
	var status_x: float = area.position.x + (area.size.x - SlotWidget.SIZE) * 0.5 + 24
	var status_y: float = grid_top + COVERAGE_GRID_PX + 24 + SlotWidget.SIZE * 0.5 + 6
	var status_text: String
	var status_color: Color
	match s:
		FertilizerApplicator.STATE_IDLE:
			status_text = "Status: IDLE — drop fertilizer in input slot or feed via belt."
			status_color = COLOR_IDLE
		FertilizerApplicator.STATE_SCANNING:
			status_text = "Status: SCANNING"
			status_color = COLOR_SCANNING
		FertilizerApplicator.STATE_BLOCKED:
			status_text = "Status: BLOCKED — coverage is fully fertilized or pristine."
			status_color = COLOR_BLOCKED
	draw_string(font, Vector2(status_x, status_y), status_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, status_color)

	# Facing — input port direction.
	var input_dir: int = Buildings.world_dir(building, FertilizerApplicator.INPUT_PORT_DIR)
	var facing_text: String = "Input port: %s" % Belt.DIR_NAMES[input_dir]
	draw_string(font, Vector2(status_x, status_y + 18), facing_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)

## Compute the display color for a coverage cell at world position `pos`.
## Color hierarchy (most-specific wins):
##   1. Impassable (water OR has another building) → near-black.
##   2. Currently fertilized → green tint matching tier.
##   3. Eligible (depleted soil, no/lower fertilizer for highest available tier) → yellow.
##   4. Pristine → dim sage.
func _cell_color(pos: Vector2i) -> Color:
	# Out-of-world: render as impassable.
	if pos.x < WorldGenerator.WORLD_MIN or pos.x >= WorldGenerator.WORLD_MAX:
		return CELL_IMPASSABLE
	if pos.y < WorldGenerator.WORLD_MIN or pos.y >= WorldGenerator.WORLD_MAX:
		return CELL_IMPASSABLE
	# Water or another building (not the applicator itself) → impassable.
	if world.is_water_at(pos):
		return CELL_IMPASSABLE
	# Cell occupied by a different building.
	if world.has_building_at(pos):
		var other_anchor = world.occupied.get(pos, pos)
		if other_anchor != building.anchor:
			return CELL_IMPASSABLE
	# Currently fertilized?
	var fert_tier: int = world.tile_fertilizer_tier(pos)
	if fert_tier == Items.Type.COMPOST_LOW:
		return CELL_FERT_LOW
	if fert_tier == Items.Type.COMPOST_MID:
		return CELL_FERT_MID
	# Eligible? (depleted soil, no current fertilizer of equal-or-better
	# tier for what's available to apply right now)
	var soil: int = world.tile_soil_health(pos)
	if soil < GridWorld.TILE_SOIL_FULL:
		var available_tier: int = FertilizerApplicator._select_fertilizer_from_buffer(building)
		if available_tier >= 0 and (fert_tier == -1 or fert_tier < available_tier):
			return CELL_ELIGIBLE
	return CELL_PRISTINE
