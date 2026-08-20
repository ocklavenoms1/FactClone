extends RefCounted

## h4 — terrain guards for Overlay.NONE-accepting buildings.
##
## Water, ore-deposit, and tree tiles all carry Overlay.NONE (overlays are
## forbidden on them), so every building whose requires_overlay includes
## NONE passes the overlay check on those tiles. That admits a smelter
## mid-lake, a power pole on an iron vein, a lamp on a mature tree —
## burying the resource and cancelling tree regrowth.
##
## Affected today (requires_overlay contains NONE): SMELTER, COMPOSTER,
## INSERTER, FAST_INSERTER, LONG_REACH_INSERTER, FERTILIZER_APPLICATOR,
## POWER_POLE, ELECTRIC_LAMP.
##
## NOT affected: WATER_WHEEL (STONE/PATH only — the overlay list already
## blocks water, since water can never carry an overlay). Its water
## ADJACENCY is deliberately gated at production, not placement
## (WaterWheel.tick recomputes output_active every tick), so a dry wheel
## is a legal-but-idle placement. This suite locks that in as intended
## behavior rather than treating it as a defect.
##
## MINING_DRILL is exempt from the resource-node rule — it must sit on ore.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Buildings that accept Overlay.NONE and must be rejected on water/ore/tree.
const GUARDED: Array = [
	Buildings.Type.SMELTER,
	Buildings.Type.COMPOSTER,
	Buildings.Type.INSERTER,
	Buildings.Type.FAST_INSERTER,
	Buildings.Type.LONG_REACH_INSERTER,
	Buildings.Type.FERTILIZER_APPLICATOR,
	Buildings.Type.POWER_POLE,
	Buildings.Type.ELECTRIC_LAMP,
	# Electricity Session 2 — both accept Overlay.NONE, so both need the guard.
	Buildings.Type.WINDMILL,
	Buildings.Type.ACCUMULATOR,
]

static func test_name() -> String:
	return "placement terrain guards (no building on water / ore / tree)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var world = GridWorldScript.new()
	parent.add_child(world)

	# Clean land strip for positive controls.
	for x in range(0, 40):
		for y in range(0, 10):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)

	# ---- Hazard tiles. Each gets its own column so 2x2 buildings anchored
	# at the hazard always overlap it, and nothing bleeds between cases.
	var water_pos := Vector2i(50, 2)
	var ore_pos := Vector2i(55, 2)
	var tree_pos := Vector2i(60, 2)
	world.tiles[water_pos] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
	world.tiles[ore_pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.IRON)
	world.tiles[tree_pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)

	# =========================================================================
	# (1) Every Overlay.NONE-accepting building is rejected on all 3 hazards.
	# =========================================================================
	for b_type in GUARDED:
		var name: String = Buildings.name_of(b_type)
		_check(failures, not world.can_place_building(b_type, water_pos),
			"(1) %s must be REJECTED on water" % name)
		_check(failures, not world.can_place_building(b_type, ore_pos),
			"(1) %s must be REJECTED on an iron deposit (bury = unmineable)" % name)
		_check(failures, not world.can_place_building(b_type, tree_pos),
			"(1) %s must be REJECTED on a mature tree" % name)

	# =========================================================================
	# (2) Rejection messaging mirrors set_overlay's wording.
	# =========================================================================
	world.can_place_building(Buildings.Type.POWER_POLE, water_pos)
	_check(failures, "water" in world.last_building_place_error.to_lower(),
		"(2) water rejection should mention water, got '%s'" % world.last_building_place_error)
	world.can_place_building(Buildings.Type.POWER_POLE, ore_pos)
	_check(failures, "mine" in world.last_building_place_error.to_lower(),
		"(2) ore rejection should say 'Mine the iron first', got '%s'" % world.last_building_place_error)

	# =========================================================================
	# (3) Rejected placement must not disturb resource state.
	# =========================================================================
	world.resource_state[tree_pos] = {"regrowth_remaining": 42.0}
	world.can_place_building(Buildings.Type.ELECTRIC_LAMP, tree_pos)
	_check(failures, float(world.resource_state.get(tree_pos, {}).get("regrowth_remaining", -1.0)) == 42.0,
		"(3) a rejected placement must leave tree regrowth untouched")
	_check(failures, world.tiles[ore_pos].resource_node == ResourceNodes.Type.IRON,
		"(3) a rejected placement must leave the ore deposit intact")

	# =========================================================================
	# (4) POSITIVE CONTROLS — the guard must not over-reject.
	# =========================================================================
	_check(failures, world.can_place_building(Buildings.Type.POWER_POLE, Vector2i(2, 2)),
		"(4) power pole on plain stone must still place: %s" % world.last_building_place_error)
	_check(failures, world.can_place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(4, 2)),
		"(4) electric lamp on plain stone must still place: %s" % world.last_building_place_error)
	# Bare grass (no tiles entry at all) is legal for NONE-accepting buildings.
	_check(failures, world.can_place_building(Buildings.Type.POWER_POLE, Vector2i(80, 80)),
		"(4) power pole on bare grass must still place: %s" % world.last_building_place_error)
	# MINING_DRILL keeps its ore exemption.
	world.resource_state[ore_pos] = {"richness": 50, "original_richness": 50}
	_check(failures, world.can_place_building(Buildings.Type.MINING_DRILL, ore_pos),
		"(4) MINING_DRILL must STILL place on ore (exempt): %s" % world.last_building_place_error)

	# =========================================================================
	# (5) WATER_WHEEL — intended behavior, locked in.
	# Overlay list already blocks water. Adjacency is a PRODUCTION gate, not
	# a placement gate: a dry wheel places legally and simply idles.
	# =========================================================================
	_check(failures, not world.can_place_building(Buildings.Type.WATER_WHEEL, water_pos),
		"(5) water wheel must not sit ON water (overlay list blocks it)")
	# Steam Generator has the same posture: STONE/PATH only, so the overlay
	# list already excludes water/ore/tree and it needs no explicit guard.
	# (Confirmed from DATA, not inferred — it does NOT accept Overlay.NONE.)
	_check(failures, not world.can_place_building(Buildings.Type.STEAM_GENERATOR, water_pos),
		"(5) steam generator must not sit on water")
	_check(failures, not world.can_place_building(Buildings.Type.STEAM_GENERATOR, ore_pos),
		"(5) steam generator must not bury an ore deposit")
	_check(failures, world.can_place_building(Buildings.Type.STEAM_GENERATOR, Vector2i(8, 2)),
		"(5) steam generator on plain stone must still place: %s" % world.last_building_place_error)
	_check(failures, world.can_place_building(Buildings.Type.WATER_WHEEL, Vector2i(6, 2)),
		"(5) water wheel on stone with NO adjacent water must still PLACE (idle, not illegal): %s"
			% world.last_building_place_error)
	# ...and it reports itself inactive until water shows up.
	if world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(6, 2), Belt.DIR_E):
		var wheel: Building = world.building_at(Vector2i(6, 2))
		WaterWheel.tick(wheel, world)
		_check(failures, not bool(wheel.state.get("output_active", true)),
			"(5) a dry water wheel must report output_active = false")

	_disconnect(world)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "water/ore/tree rejected for all 8 NONE-accepting types; drill exempt; water wheel places dry and idles" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
