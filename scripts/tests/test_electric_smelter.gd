extends RefCounted

## Electric smelter — session-electricity-processors, Task 2: REGISTRY ROW ONLY.
##
## Pins the ELECTRIC_SMELTER registry row: the on-disk enum integer, the DATA
## row shape (name / footprint / overlays / direction), the no-fuel slot
## layout, the make() dispatch type, and the swatch colour. Task 3 extends
## this file with the power state machine cases (satisfaction trajectories,
## the freeze/resume dual pin, fuel sentinels, save round-trip).
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. Nothing here asks Buildings for its
## own expectation: the enum integer is written as 37 (re-derived by hand on
## 2026-08-27 from the enum tail — UNDERGROUND_BELT_EXIT is 36), the footprint
## as Vector2i(2, 2), the burner smelter's swatch as the Color literal from
## its DATA row. An `int(Buildings.Type.ELECTRIC_SMELTER) ==
## int(Buildings.Type.ELECTRIC_SMELTER)` round-trip would be the module
## confirming itself.
##
## COLOUR FLOOR NOTE: test_inserter_body_colours.gd's ΔE ≥ 25 floor is scoped
## to Inserter.BODY_COLOR_BY_TYPE — inserter tiers only. DATA swatch colours
## are OUTSIDE its domain, so the electric processors' swatches are pinned
## HERE instead, reusing that suite's L*a*b* maths as a measuring instrument
## (the colour maths is not the module under test; the floor and both swatch
## literals are this file's own).

const ColourMath = preload("res://scripts/tests/test_inserter_body_colours.gd")

## Hand-chosen swatch literals (2026-08-27). The DATA row must carry the
## electric literal EXACTLY (sub-case 5 pins it), and the row's actual value
## must clear the ΔE floor against both colours it could be confused with:
## the burner smelter it sits beside on the map, and the electric drill it
## sits beside on the hotbar.
const SWATCH_ELECTRIC_SMELTER := Color(0.10, 0.42, 0.50)  # deep electric teal
const SWATCH_ELECTRIC_DRILL := Color(0.48, 0.72, 0.68)    # pale cyan-green (drill suite pins it)
const SWATCH_BURNER_SMELTER := Color(0.30, 0.28, 0.25)    # SMELTER DATA row, re-derived by hand
const FLOOR_DE: float = 25.0

static func test_name() -> String:
	return "electric smelter registry row (enum int 37, 2x2 footprint, no-fuel slot layout, make() type pin, swatch colour distance)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []
	_case_1_enum_int(failures)
	_case_2_data_row_shape(failures)
	_case_3_no_fuel_slot(failures)
	_case_4_make_type_pin(failures)
	_case_5_swatch_colour(failures)
	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# ===========================================================================
# (1) THE ON-DISK INTEGER. The save format pins this forever: a save written
# today holds `"t": 37` and must load as an electric smelter in every future
# build. The literal is the assertion — a symbolic comparison could drift
# with the enum and stay green.
# ===========================================================================
static func _case_1_enum_int(failures: Array) -> void:
	if int(Buildings.Type.ELECTRIC_SMELTER) != 37:
		failures.append("(1) Buildings.Type.ELECTRIC_SMELTER is %d, expected the literal 37 — the append-only rule broke, and every save carrying a 37 now loads as the wrong machine"
			% int(Buildings.Type.ELECTRIC_SMELTER))

# ===========================================================================
# (2) DATA ROW SHAPE — mirrors the burner SMELTER row minus fuel.
# ===========================================================================
static func _case_2_data_row_shape(failures: Array) -> void:
	if Buildings.name_of(Buildings.Type.ELECTRIC_SMELTER) != "Electric Smelter":
		failures.append("(2) name is '%s', expected 'Electric Smelter'"
			% Buildings.name_of(Buildings.Type.ELECTRIC_SMELTER))
	if Buildings.footprint_of(Buildings.Type.ELECTRIC_SMELTER) != Vector2i(2, 2):
		failures.append("(2) footprint is %s, expected Vector2i(2, 2) — must match the burner smelter"
			% str(Buildings.footprint_of(Buildings.Type.ELECTRIC_SMELTER)))
	var overlays: Array = Buildings.requires_overlay(Buildings.Type.ELECTRIC_SMELTER)
	if overlays != [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH]:
		failures.append("(2) requires_overlay is %s, expected [NONE, STONE, PATH] — must match the burner smelter" % str(overlays))
	if not Buildings.supports_direction(Buildings.Type.ELECTRIC_SMELTER):
		failures.append("(2) supports_direction is false, expected true — all 3 ports rotate together like the burner's")

# ===========================================================================
# (3) NO FUEL SLOT, asserted over the ACTUAL layout: sweep every slot for a
# "fuel" id or kind, AND pin the id list exactly. The sweep alone would stay
# green on an empty layout; the exact id list catches that.
# ===========================================================================
static func _case_3_no_fuel_slot(failures: Array) -> void:
	var layout: Array = Buildings.slot_layout_for(Buildings.Type.ELECTRIC_SMELTER)
	var ids: Array = []
	for slot in layout:
		ids.append(str(slot.get("id", "")))
		if str(slot.get("kind", "")) == "fuel" or str(slot.get("id", "")) == "fuel":
			failures.append("(3) slot_layout carries a fuel slot (%s) — the electric tier draws from the power network, never from a fuel buffer" % str(slot))
	if ids != ["input", "output"]:
		failures.append("(3) slot ids are %s, expected exactly ['input', 'output'] — the burner layout minus its fuel slot" % str(ids))

# ===========================================================================
# (4) make() STAMPS THE ELECTRIC TYPE. Smelter.make hardcoded the burner
# enum before this session; the ELECTRIC_SMELTER dispatch arm must produce a
# building whose type is the on-disk 37, or every electric smelter saves as
# a burner and loads with a fuel slot.
# ===========================================================================
static func _case_4_make_type_pin(failures: Array) -> void:
	var b: Building = Buildings.make(Buildings.Type.ELECTRIC_SMELTER, Vector2i(3, 3))
	if b == null:
		failures.append("(4) Buildings.make(ELECTRIC_SMELTER, ...) returned null — no make() dispatch arm")
		return
	if int(b.type) != 37:
		failures.append("(4) make(ELECTRIC_SMELTER).type is %d, expected the literal 37 — the arm delegates to a make() that hardcodes the burner enum" % int(b.type))

# ===========================================================================
# (5) SWATCH COLOUR: the exact literal, plus ΔE ≥ 25 against the burner
# smelter and against the electric drill, measured on the ROW'S OWN VALUE so
# a drifted row cannot hide behind a green literal-vs-literal distance.
# ===========================================================================
static func _case_5_swatch_colour(failures: Array) -> void:
	var actual: Color = Buildings.swatch_color_of(Buildings.Type.ELECTRIC_SMELTER)
	if actual != SWATCH_ELECTRIC_SMELTER:
		failures.append("(5) swatch is %s, expected the pinned literal %s" % [str(actual), str(SWATCH_ELECTRIC_SMELTER)])
	var d_burner: float = ColourMath.delta_e(actual, SWATCH_BURNER_SMELTER)
	if d_burner < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the burner smelter's %s (floor %.1f) — the two smelters would read as shades of one another"
			% [str(actual), d_burner, str(SWATCH_BURNER_SMELTER), FLOOR_DE])
	var d_sibling: float = ColourMath.delta_e(actual, SWATCH_ELECTRIC_DRILL)
	if d_sibling < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the electric drill's %s (floor %.1f) — the two electric processors would read as shades of one another"
			% [str(actual), d_sibling, str(SWATCH_ELECTRIC_DRILL), FLOOR_DE])
