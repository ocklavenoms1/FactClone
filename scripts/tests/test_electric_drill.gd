extends RefCounted

## Electric drill — session-electricity-processors, Task 2: REGISTRY ROW ONLY.
##
## Pins the ELECTRIC_DRILL registry row: the on-disk enum integer, the DATA
## row shape (name / footprint / overlays / direction), the no-fuel slot
## layout, the make() dispatch type, the swatch colour, and the ore-coverage
## placement rule (grid_world's MINING_DRILL exemption and validate_placement
## call must both cover type 38, or the electric drill is either rejected on
## ore or accepted off it). Task 4 extends this file with the power state
## machine cases.
##
## ⚠ EVERY EXPECTED VALUE IS A LITERAL. The enum integer is written as 38
## (re-derived by hand on 2026-08-27 from the enum tail — UNDERGROUND_BELT_EXIT
## is 36, ELECTRIC_SMELTER 37), the footprint as Vector2i(2, 2) — the CODE'S
## drill footprint (buildings.gd MINING_DRILL row), not the plan text's "1×1",
## which the dispatch re-derivation corrected.
##
## COLOUR FLOOR NOTE: test_inserter_body_colours.gd's ΔE ≥ 25 floor covers
## only Inserter.BODY_COLOR_BY_TYPE — DATA swatches are outside its domain,
## so this file pins the drill's swatch itself, reusing that suite's L*a*b*
## maths as a measuring instrument.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const ColourMath = preload("res://scripts/tests/test_inserter_body_colours.gd")

## Hand-chosen swatch literals (2026-08-27). See test_electric_smelter.gd's
## sub-case (5) header for the pin-plus-distance structure.
const SWATCH_ELECTRIC_DRILL := Color(0.48, 0.72, 0.68)    # pale cyan-green
const SWATCH_ELECTRIC_SMELTER := Color(0.10, 0.42, 0.50)  # deep electric teal (smelter suite pins it)
const SWATCH_BURNER_DRILL := Color(0.45, 0.40, 0.32)      # MINING_DRILL DATA row, re-derived by hand
const FLOOR_DE: float = 25.0

static func test_name() -> String:
	return "electric drill registry row (enum int 38, 2x2 footprint, no-fuel slot layout, make() type pin, swatch colour distance, ore-coverage placement rule)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_1_enum_int(failures)
	_case_2_data_row_shape(failures)
	_case_3_no_fuel_slot(failures)
	_case_4_make_type_pin(failures)
	_case_5_swatch_colour(failures)
	_case_6_ore_coverage_rule(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# ===========================================================================
# (1) THE ON-DISK INTEGER — 38, forever. See test_electric_smelter.gd (1).
# ===========================================================================
static func _case_1_enum_int(failures: Array) -> void:
	if int(Buildings.Type.ELECTRIC_DRILL) != 38:
		failures.append("(1) Buildings.Type.ELECTRIC_DRILL is %d, expected the literal 38 — the append-only rule broke, and every save carrying a 38 now loads as the wrong machine"
			% int(Buildings.Type.ELECTRIC_DRILL))

# ===========================================================================
# (2) DATA ROW SHAPE — mirrors the burner MINING_DRILL row minus fuel.
# ===========================================================================
static func _case_2_data_row_shape(failures: Array) -> void:
	if Buildings.name_of(Buildings.Type.ELECTRIC_DRILL) != "Electric Drill":
		failures.append("(2) name is '%s', expected 'Electric Drill'"
			% Buildings.name_of(Buildings.Type.ELECTRIC_DRILL))
	if Buildings.footprint_of(Buildings.Type.ELECTRIC_DRILL) != Vector2i(2, 2):
		failures.append("(2) footprint is %s, expected Vector2i(2, 2) — the burner drill is 2x2 (the plan text's '1x1' was wrong; code wins)"
			% str(Buildings.footprint_of(Buildings.Type.ELECTRIC_DRILL)))
	var overlays: Array = Buildings.requires_overlay(Buildings.Type.ELECTRIC_DRILL)
	if overlays != [Terrain.Overlay.NONE, Terrain.Overlay.STONE]:
		failures.append("(2) requires_overlay is %s, expected [NONE, STONE] — must match the burner drill" % str(overlays))
	if not Buildings.supports_direction(Buildings.Type.ELECTRIC_DRILL):
		failures.append("(2) supports_direction is false, expected true — output port rotates like the burner's")

# ===========================================================================
# (3) NO FUEL SLOT — sweep plus exact id list. See test_electric_smelter (3).
# ===========================================================================
static func _case_3_no_fuel_slot(failures: Array) -> void:
	var layout: Array = Buildings.slot_layout_for(Buildings.Type.ELECTRIC_DRILL)
	var ids: Array = []
	for slot in layout:
		ids.append(str(slot.get("id", "")))
		if str(slot.get("kind", "")) == "fuel" or str(slot.get("id", "")) == "fuel":
			failures.append("(3) slot_layout carries a fuel slot (%s) — the electric tier draws from the power network, never from a fuel buffer" % str(slot))
	if ids != ["output"]:
		failures.append("(3) slot ids are %s, expected exactly ['output'] — the burner layout minus its fuel slot" % str(ids))

# ===========================================================================
# (4) make() STAMPS THE ELECTRIC TYPE — MiningDrill.make hardcoded the
# burner enum before this session. See test_electric_smelter.gd (4).
# ===========================================================================
static func _case_4_make_type_pin(failures: Array) -> void:
	var b: Building = Buildings.make(Buildings.Type.ELECTRIC_DRILL, Vector2i(3, 3))
	if b == null:
		failures.append("(4) Buildings.make(ELECTRIC_DRILL, ...) returned null — no make() dispatch arm")
		return
	if int(b.type) != 38:
		failures.append("(4) make(ELECTRIC_DRILL).type is %d, expected the literal 38 — the arm delegates to a make() that hardcodes the burner enum" % int(b.type))

# ===========================================================================
# (5) SWATCH COLOUR — pin plus distance. See test_electric_smelter.gd (5).
# ===========================================================================
static func _case_5_swatch_colour(failures: Array) -> void:
	var actual: Color = Buildings.swatch_color_of(Buildings.Type.ELECTRIC_DRILL)
	if actual != SWATCH_ELECTRIC_DRILL:
		failures.append("(5) swatch is %s, expected the pinned literal %s" % [str(actual), str(SWATCH_ELECTRIC_DRILL)])
	var d_burner: float = ColourMath.delta_e(actual, SWATCH_BURNER_DRILL)
	if d_burner < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the burner drill's %s (floor %.1f) — the two drills would read as shades of one another"
			% [str(actual), d_burner, str(SWATCH_BURNER_DRILL), FLOOR_DE])
	var d_sibling: float = ColourMath.delta_e(actual, SWATCH_ELECTRIC_SMELTER)
	if d_sibling < FLOOR_DE:
		failures.append("(5) swatch %s is only ΔE %.2f from the electric smelter's %s (floor %.1f) — the two electric processors would read as shades of one another"
			% [str(actual), d_sibling, str(SWATCH_ELECTRIC_SMELTER), FLOOR_DE])

# ===========================================================================
# (6) THE ORE-COVERAGE PLACEMENT RULE COVERS TYPE 38. Beyond the Task-2 RED
# list's registry sub-cases, deliberately: grid_world.gd's resource-node
# exemption and its validate_placement call both hardcoded MINING_DRILL, so
# without this pin the electric drill would be REJECTED on ore ("Mine the
# ore first") and its covered_deposits never populated — an extension whose
# absence is otherwise indistinguishable from success (the silent-
# compensation shape). Three assertions: on-ore placement succeeds AND
# populates covered_deposits with the exact tile AND stamps type 38;
# off-ore placement fails with the burner's own error message.
# ===========================================================================
static func _case_6_ore_coverage_rule(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)

	# One ore tile under the 2x2 footprint anchored at (0,0).
	_set_ore(world, Vector2i(0, 0), ResourceNodes.Type.STONE, 50)
	if not world.place_building(Buildings.Type.ELECTRIC_DRILL, Vector2i(0, 0), Belt.DIR_E):
		failures.append("(6) electric drill on ore rejected: %s — the MINING_DRILL exemption in can_place_building does not cover type 38"
			% world.last_building_place_error)
	else:
		var b: Building = world.building_at(Vector2i(0, 0))
		if b == null:
			failures.append("(6) placed electric drill not found at its anchor")
		else:
			if int(b.type) != 38:
				failures.append("(6) placed electric drill carries type %d, expected the literal 38" % int(b.type))
			if b.state.get("covered_deposits", []) != [[0, 0]]:
				failures.append("(6) covered_deposits is %s, expected [[0, 0]] — the refresh_covered_deposits placement hook does not cover type 38"
					% str(b.state.get("covered_deposits", [])))
		world.remove_building_at(Vector2i(0, 0))

	# Away from ore: same rejection, same player-facing message as the burner.
	if world.place_building(Buildings.Type.ELECTRIC_DRILL, Vector2i(20, 20), Belt.DIR_E):
		failures.append("(6) electric drill away from ore placed — the ore-coverage rule does not cover type 38")
		world.remove_building_at(Vector2i(20, 20))
	elif "ore deposit" not in world.last_building_place_error.to_lower():
		failures.append("(6) expected 'ore deposit' in the rejection message; got: %s" % world.last_building_place_error)

	_disconnect(world)
	world.queue_free()

static func _set_ore(world, pos: Vector2i, ore_type: int, richness: int) -> void:
	world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ore_type)
	world.resource_state[pos] = {"richness": richness, "original_richness": richness}

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
