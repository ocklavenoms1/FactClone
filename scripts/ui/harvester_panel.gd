extends BuildingPanel

## Harvester UI (session-building-ui-4). 3×3 coverage display showing the
## harvester's tile + 8 King-move neighbors with planter status, plus
## output buffer (multi-type bag) drag-out, plus status text.
##
## Layout (per Q5 design pass):
##   ╔════════════ Harvester ═══════════════╗
##   ║  Coverage:                            ║
##   ║   ┌──┬──┬──┐                          ║
##   ║   │R │_ │G │   R = ripe planter       ║
##   ║   ├──┼──┼──┤   G = growing planter    ║
##   ║   │G │■ │_ │   ■ = harvester (this)   ║
##   ║   ├──┼──┼──┤   _ = empty / non-planter║
##   ║   │_ │R │G │                          ║
##   ║   └──┴──┴──┘                          ║
##   ║                                       ║
##   ║  Output buffer:                       ║
##   ║  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐
##   ║  │ W4 │ │ SB1│ │    │ │    │ │    │ │    │
##   ║  └────┘ └────┘ └────┘ └────┘ └────┘ └────┘
##   ║                                       ║
##   ║  Status: Scanning… (next in 4 ticks)  ║
##   ║  Buffer: 5 / 50                       ║
##   ╠═══════════════════════════════════════╣
##   ║         Player inventory              ║
##   ╚═══════════════════════════════════════╝
##
## Coverage state read on-the-fly per frame from world tile/building data
## (per Q2 design pass). Per-cell rendering color-coded by planter status.

const COVERAGE_CELL: int = 48
const COVERAGE_GAP: int = 2
const OUTPUT_GAP: int = 8

# Coverage cell state enum (local, not shared — only HarvesterPanel renders).
const COV_EMPTY: int = 0       # no building or non-planter
const COV_GROWING: int = 1     # planter, not yet ripe
const COV_RIPE: int = 2        # planter ready for harvest
const COV_SELF: int = 3        # the harvester's own tile (center)

const COLOR_EMPTY: Color = Color(0.18, 0.18, 0.20, 0.95)
const COLOR_GROWING: Color = Color(0.40, 0.65, 0.30, 0.95)    # leafy green
const COLOR_RIPE: Color = Color(0.90, 0.75, 0.30, 0.95)       # ripe gold
const COLOR_SELF: Color = Color(0.50, 0.45, 0.40, 0.95)        # mechanical brown

const STATUS_COLOR_OK: Color = Color(0.55, 0.85, 0.55)
const STATUS_COLOR_FULL: Color = Color(1.00, 0.45, 0.45)

func _building_slot_rects() -> Array:
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var layout: Array = Buildings.slot_layout_for(building.type)
	var rects: Array = []
	# Output buffer row sits below the 3×3 coverage display.
	# Coverage grid: 3 cells × COVERAGE_CELL height = 144px, plus header gap.
	var output_row_y: float = area.position.y + 32 + 3 * (COVERAGE_CELL + COVERAGE_GAP) + 24
	var output_row_x: float = area.position.x + 24
	for slot_def in layout:
		if str(slot_def.get("kind", "")) == "output_multi":
			var n: int = int(slot_def.get("multi_count", 1))
			for sub_idx in n:
				var x: float = output_row_x + sub_idx * (SlotWidget.SIZE + OUTPUT_GAP)
				rects.append({"slot_def": slot_def, "rect": Rect2(x, output_row_y, SlotWidget.SIZE, SlotWidget.SIZE), "sub_idx": sub_idx})
	return rects

func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null or world == null:
		return

	# "Coverage:" header.
	var cov_x: float = area.position.x + 24
	var cov_y: float = area.position.y + 28
	draw_string(font, Vector2(cov_x, cov_y - 4), "Coverage:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)

	# 3×3 mini-grid centered on the harvester's tile.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var rect_x: float = cov_x + (dx + 1) * (COVERAGE_CELL + COVERAGE_GAP)
			var rect_y: float = cov_y + 6 + (dy + 1) * (COVERAGE_CELL + COVERAGE_GAP)
			var cell_rect: Rect2 = Rect2(rect_x, rect_y, COVERAGE_CELL, COVERAGE_CELL)
			var state: int = COV_EMPTY
			if dx == 0 and dy == 0:
				state = COV_SELF
			else:
				var cell_pos: Vector2i = building.anchor + Vector2i(dx, dy)
				state = _coverage_status_for(cell_pos)
			# Background per state.
			var bg: Color
			var label: String
			match state:
				COV_SELF:
					bg = COLOR_SELF
					label = "■"
				COV_RIPE:
					bg = COLOR_RIPE
					label = "R"
				COV_GROWING:
					bg = COLOR_GROWING
					label = "G"
				_:
					bg = COLOR_EMPTY
					label = "_"
			draw_rect(cell_rect, bg, true)
			draw_rect(cell_rect, Color.BLACK, false, 1.0)
			# Center the letter.
			draw_string(font, Vector2(cell_rect.position.x, cell_rect.position.y + COVERAGE_CELL * 0.5 + 5),
				label, HORIZONTAL_ALIGNMENT_CENTER, COVERAGE_CELL, 16, Color.WHITE)

	# Coverage legend on the right of the grid.
	var legend_x: float = cov_x + 3 * (COVERAGE_CELL + COVERAGE_GAP) + 32
	var legend_y: float = cov_y + 6
	draw_string(font, Vector2(legend_x, legend_y), "Legend:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)
	draw_string(font, Vector2(legend_x, legend_y + 18),
		"R = ripe planter", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_RIPE)
	draw_string(font, Vector2(legend_x, legend_y + 32),
		"G = growing planter", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_GROWING)
	draw_string(font, Vector2(legend_x, legend_y + 46),
		"■ = this harvester", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)
	draw_string(font, Vector2(legend_x, legend_y + 60),
		"_ = empty / other", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)

	# "Output buffer:" label above the slot row.
	var output_row_y: float = area.position.y + 32 + 3 * (COVERAGE_CELL + COVERAGE_GAP) + 24
	draw_string(font, Vector2(area.position.x + 24, output_row_y - 6),
		"Output buffer:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)

	# Status row below output slots.
	var status_y: float = output_row_y + SlotWidget.SIZE + 24
	var buffer_total: int = Harvester.buffer_total(building)
	var capacity: int = Harvester.BUFFER_CAPACITY
	var next_scan: int = int(building.state.get("next_scan_tick", 0))
	var ticks_to_scan: int = max(0, next_scan - TickSystem.current_tick)
	var status_text: String
	var status_color: Color
	if buffer_total >= capacity:
		status_text = "Status: Buffer full — drain to resume scanning"
		status_color = STATUS_COLOR_FULL
	else:
		status_text = "Status: Scanning… (next scan in %d ticks)" % ticks_to_scan
		status_color = STATUS_COLOR_OK
	draw_string(font, Vector2(area.position.x + 24, status_y),
		status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_color)
	draw_string(font, Vector2(area.position.x + 24, status_y + 22),
		"Buffer: %d / %d items" % [buffer_total, capacity],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
	draw_string(font, Vector2(area.position.x + 24, status_y + 40),
		"Drag items from buffer to inventory below, or place a chest/belt adjacent for auto-drain.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)

## Read-on-the-fly per Q2 design. Returns enum value for the cell at
## `cell_pos`. Coverage is the 8 King-move neighbors of the harvester.
func _coverage_status_for(cell_pos: Vector2i) -> int:
	if not world.has_building_at(cell_pos):
		return COV_EMPTY
	var nb: Building = world.building_at(cell_pos)
	if nb == null or nb.type != Buildings.Type.PLANTER:
		return COV_EMPTY
	if Planter.is_ripe(nb):
		return COV_RIPE
	return COV_GROWING

## Override _top_area_height to fit the 3×3 coverage + output row + status.
## Coverage: ~150px, output row: ~48 + label, status: ~70px.
func _top_area_height() -> int:
	return 380
