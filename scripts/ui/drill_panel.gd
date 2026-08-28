extends BuildingPanel

## Mining-Drill-specialized building panel (session-building-ui-1).
##
## Layout (per Q10 design):
##   ╔════════════ Mining Drill ═══════════╗
##   ║  Coverage:        Currently mining: ║
##   ║  ┌──┬──┐          Iron Ore @(12,5)  ║
##   ║  │Fe│Fe│          247/300 richness  ║
##   ║  ├──┼──┤          Active deposits:  ║
##   ║  │Cu│ -│          • Iron @(12,5)    ║
##   ║  └──┴──┘          • Iron @(13,5)    ║
##   ║                                     ║
##   ║  Output:                            ║
##   ║  ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐            ║
##   ║  │Fe│ │Cu│ │  │ │  │ │  │            ║
##   ║  └──┘ └──┘ └──┘ └──┘ └──┘            ║
##   ║                                     ║
##   ║       ┌────┐                        ║
##   ║       │fuel│  Fuel: 12/16 units     ║
##   ║       └────┘                        ║
##   ║                                     ║
##   ║  Status: Drilling                   ║
##   ╠═════════════════════════════════════╣
##   ║         Player inventory             ║
##   ╚══════════════════════════════════════╝
##
## Output is multi-stack: each sub-slot maps to output_buffer[sub_idx]
## per Q8 user pushback. Click on sub-slot N → take output_buffer[N] to
## cursor (entries shift up via remove_at).

const COVERAGE_CELL: int = 56
const COVERAGE_GAP: int = 2
const OUTPUT_SLOT_GAP: int = 8
const FUEL_SLOT_SIZE: int = 48

# Status colors per state (matches MiningDrill state ints).
const COLOR_DRILLING: Color = Color(1.00, 0.85, 0.30)
const COLOR_NO_FUEL: Color = Color(0.50, 0.65, 1.00)
const COLOR_BLOCKED: Color = Color(1.00, 0.95, 0.40)
const COLOR_DEPLETED: Color = Color(0.55, 0.55, 0.55)
# NO POWER (electric variant). Warm amber against COLOR_NO_FUEL's cool blue —
# the two stalls have different causes and different fixes, so the status
# line must distinguish them by colour as well as by text. Copied verbatim
# from inserter_panel.gd's COLOR_NO_POWER (the shipped precedent);
# test_electric_drill.gd pins the literal.
const COLOR_NO_POWER: Color = Color(1.00, 0.62, 0.25)
const COLOR_IDLE: Color = Color(0.75, 0.75, 0.75)

## The panel's state → status-line mapping. PURE, and static, so it can be
## asserted without a font, a frame or a window — the drill-panel sub-cases
## of test_electric_drill.gd are the assertion. It used to live inline in
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
		MiningDrill.STATE_DRILLING:
			return {"text": "Status: Drilling", "color": COLOR_DRILLING}
		MiningDrill.STATE_NO_FUEL:
			return {"text": "Status: NO FUEL — feed wood, coal, or fuel briquette", "color": COLOR_NO_FUEL}
		MiningDrill.STATE_BLOCKED_OUTPUT:
			return {"text": "Status: Output blocked", "color": COLOR_BLOCKED}
		MiningDrill.STATE_DEPLETED:
			return {"text": "Status: Depleted — relocate drill", "color": COLOR_DEPLETED}
		MiningDrill.STATE_NO_POWER:
			# Its own arm, not folded into NO_FUEL: distinct text and distinct
			# colour are the entire point of the line. ⚠ MiningDrill's
			# NO_POWER is 5 — its 4 is DEPLETED, and the SMELTER's NO_POWER
			# is 4 — always the MODULE constant here, never a literal shared
			# with the smelter panel.
			return {"text": "Status: NO POWER", "color": COLOR_NO_POWER}
	return {"text": "Status: Idle", "color": COLOR_IDLE}

## Whether the fuel LABEL/units row renders. The fuel slot RECT already
## vanishes on its own for the electric variant (no "fuel" slot_def in
## ELECTRIC_DRILL's slot_layout — pinned by test_electric_drill.gd (3));
## this predicate is the text half of the same fact. Gated on the MODULE's
## is_electric, never a local type check — one source of truth.
static func shows_fuel_row(b: Building) -> bool:
	return not MiningDrill.is_electric(b)

## The denominator the "Drill progress: N / M" sub-line renders against.
## Burner: the rated DRILL_TICKS_PER_ORE (40), unchanged — _effective_target
## early-returns it before any satisfaction lookup. Electric: the EFFECTIVE
## target — recomputed from live satisfaction, the same number the machine
## itself races (target-stretch), so a brownout visibly stretches the
## sub-line instead of it lying about time remaining.
static func progress_target(b: Building, world_ref) -> int:
	return MiningDrill._effective_target(b, world_ref)

## Override slot positions for drill's row layout. Output sub-slots in a
## horizontal row, fuel below.
func _building_slot_rects() -> Array:
	if building == null:
		return []
	var area: Rect2 = _top_area_rect()
	var layout: Array = Buildings.slot_layout_for(building.type)
	var rects: Array = []

	# Output row sits below the coverage panel and currently-mining text.
	var output_row_y: float = area.position.y + COVERAGE_CELL * 2 + 50
	var output_row_x: float = area.position.x + 24
	# Fuel row sits below outputs. The electric variants inherit this row
	# layout; the empty fuel-row gap is DELIBERATE (user decision 2026-08-27)
	# — do not compact it blind: the gap is where the burner's fuel slot
	# sits, and compaction is a design decision, not a cleanup.
	# test_electric_smelter.gd (21) pins this comment's phrase.
	var fuel_row_y: float = output_row_y + SlotWidget.SIZE + 30
	var fuel_x: float = area.position.x + 24

	for slot_def in layout:
		var kind: String = str(slot_def.get("kind", ""))
		match kind:
			"output_multi":
				var n: int = int(slot_def.get("multi_count", 1))
				for sub_idx in n:
					var x: float = output_row_x + sub_idx * (SlotWidget.SIZE + OUTPUT_SLOT_GAP)
					rects.append({"slot_def": slot_def, "rect": Rect2(x, output_row_y, SlotWidget.SIZE, SlotWidget.SIZE), "sub_idx": sub_idx})
			"fuel":
				rects.append({"slot_def": slot_def, "rect": Rect2(fuel_x, fuel_row_y, FUEL_SLOT_SIZE, FUEL_SLOT_SIZE), "sub_idx": -1})
	return rects

func _draw_building_specific(area: Rect2, font: Font) -> void:
	if building == null or world == null:
		return

	# Coverage panel — top-left, 2×2 mini-grid of footprint cells.
	var cov_x: float = area.position.x + 24
	var cov_y: float = area.position.y + 28
	# "Coverage:" label.
	draw_string(font, Vector2(cov_x, cov_y - 6), "Coverage:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
	# Render the 2×2 mini-grid: each cell colored by its ore type and
	# labeled with remaining richness, OR neutral if no ore there.
	var fp: Vector2i = Buildings.footprint_of_building(building)
	for dx in fp.x:
		for dy in fp.y:
			var cell_pos: Vector2i = Vector2i(building.anchor.x + dx, building.anchor.y + dy)
			var rect_x: float = cov_x + dx * (COVERAGE_CELL + COVERAGE_GAP)
			var rect_y: float = cov_y + 6 + dy * (COVERAGE_CELL + COVERAGE_GAP)
			var cell_rect: Rect2 = Rect2(rect_x, rect_y, COVERAGE_CELL, COVERAGE_CELL)
			# Background per ore presence.
			var ore_type: int = ResourceNodes.Type.NONE
			if world.tiles.has(cell_pos):
				ore_type = world.tiles[cell_pos].resource_node
			var bg: Color
			if ResourceNodes.is_ore(ore_type):
				bg = ResourceNodes.color_of(ore_type)
				bg.a = 0.85
			else:
				bg = Color(0.20, 0.20, 0.22, 0.85)
			draw_rect(cell_rect, bg, true)
			draw_rect(cell_rect, Color.BLACK, false, 1.0)
			# Richness label centered.
			if ResourceNodes.is_ore(ore_type):
				var richness: int = world.richness_at(cell_pos)
				var label: String
				if richness > 0:
					label = "%s\n%d" % [ResourceNodes.name_of(ore_type), richness]
				else:
					label = "(depleted)"
				# Two-line render: name on top, richness below.
				var lines: PackedStringArray = label.split("\n")
				draw_string(font, Vector2(cell_rect.position.x, cell_rect.position.y + 18),
					lines[0], HORIZONTAL_ALIGNMENT_CENTER, COVERAGE_CELL, 11, Color.WHITE)
				if lines.size() > 1:
					draw_string(font, Vector2(cell_rect.position.x, cell_rect.position.y + 36),
						lines[1], HORIZONTAL_ALIGNMENT_CENTER, COVERAGE_CELL, 13, Color.WHITE)
			else:
				draw_string(font, Vector2(cell_rect.position.x, cell_rect.position.y + COVERAGE_CELL * 0.5 + 4),
					"—", HORIZONTAL_ALIGNMENT_CENTER, COVERAGE_CELL, 14, TEXT_DIM)

	# Currently-mining + active deposits panel — top-right.
	var info_x: float = cov_x + COVERAGE_CELL * 2 + COVERAGE_GAP + 32
	var info_y: float = cov_y + 6
	var deposits: Array = _active_deposits_sorted()
	# Currently-mining: the highest-richness deposit (drill's pick).
	if deposits.is_empty():
		draw_string(font, Vector2(info_x, info_y), "Currently mining: (depleted)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_DEPLETED)
	else:
		var top: Array = deposits[0]
		var pos: Vector2i = top[0]
		var ore_t: int = top[1]
		var richness: int = top[2]
		var orig: int = world.original_richness_at(pos)
		draw_string(font, Vector2(info_x, info_y),
			"Currently mining: %s @ (%d, %d)" % [ResourceNodes.name_of(ore_t), pos.x, pos.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_DRILLING)
		draw_string(font, Vector2(info_x, info_y + 18),
			"%d / %d richness" % [richness, orig],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)
		# Drill progress sub-line. The denominator comes from progress_target
		# (pure, static) so the suite can assert it — route A.
		var dprog: int = int(building.state.get("drill_progress", 0))
		draw_string(font, Vector2(info_x, info_y + 36),
			"Drill progress: %d / %d" % [dprog, progress_target(building, world)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)
	# Active deposits list — sorted by richness desc, max 4 lines.
	draw_string(font, Vector2(info_x, info_y + 60), "Active deposits:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)
	var line_y: float = info_y + 78
	var max_lines: int = min(deposits.size(), 4)
	for i in max_lines:
		var entry: Array = deposits[i]
		var pos2: Vector2i = entry[0]
		var ore2: int = entry[1]
		var rich2: int = entry[2]
		draw_string(font, Vector2(info_x + 8, line_y),
			"• %s @(%d,%d): %d" % [ResourceNodes.name_of(ore2), pos2.x, pos2.y, rich2],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_DIM)
		line_y += 14

	# "Output:" label above the output row.
	var output_row_y: float = area.position.y + COVERAGE_CELL * 2 + 50
	draw_string(font, Vector2(area.position.x + 24, output_row_y - 6),
		"Output:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR)

	# Fuel slot label. The slot RECT is layout-driven and vanishes on its own
	# for the electric variant; the label is drawn here, so it carries its
	# own gate.
	var fuel_row_y: float = output_row_y + SlotWidget.SIZE + 30
	if shows_fuel_row(building):
		var fuel_label_x: float = area.position.x + 24 + FUEL_SLOT_SIZE + 16
		var fuel_units: int = int(building.state.get("fuel_buffer", 0))
		var fuel_cap: int = int(Burner.FUEL_BUFFER_CAPACITY)
		draw_string(font, Vector2(fuel_label_x, fuel_row_y + 18),
			"Fuel: %d / %d units" % [fuel_units, fuel_cap],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)
		draw_string(font, Vector2(fuel_label_x, fuel_row_y + 36),
			"(accepts: Wood, Coal, Briquette)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_DIM)

	# Status row. The mapping lives in status_line (pure, static) so the
	# suite can assert it — route A.
	var status_y: float = fuel_row_y + FUEL_SLOT_SIZE + 18
	var s: int = int(building.state.get("state", 0))
	var status: Dictionary = status_line(s)
	draw_string(font, Vector2(area.position.x + 24, status_y),
		String(status["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, status["color"])

## Sorted active deposits (richness desc, tiebreak topmost-leftmost — same
## logic as MiningDrill._pick_best_deposit). Returns Array of [pos, ore_type,
## richness]. Skips depleted deposits (richness == 0).
func _active_deposits_sorted() -> Array:
	var out: Array = []
	for entry in building.state.get("covered_deposits", []):
		var pos: Vector2i = Vector2i(int(entry[0]), int(entry[1]))
		var r: int = world.richness_at(pos)
		if r <= 0:
			continue
		var ore_t: int = ResourceNodes.Type.NONE
		if world.tiles.has(pos):
			ore_t = world.tiles[pos].resource_node
		out.append([pos, ore_t, r])
	# Sort by richness desc; tiebreak topmost-leftmost.
	out.sort_custom(func(a, b):
		if int(a[2]) != int(b[2]):
			return int(a[2]) > int(b[2])
		var pa: Vector2i = a[0]
		var pb: Vector2i = b[0]
		if pa.y != pb.y:
			return pa.y < pb.y
		return pa.x < pb.x
	)
	return out
