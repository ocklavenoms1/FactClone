extends RefCounted

## Pole tiers (Electricity Session 3) — parametric POLE_RANGE / SUPPLY_RADIUS,
## either-reaches connection, multi-cell poles, nearest-pole supply tie-break.
##
## Sub-case index (each task appends its own _case_* and wires it into run()):
##   1. POWER_NETWORK_TYPES / POLE_TYPES membership (Task 1).
##   2. Registration — DATA rows, footprints, placement (Task 2).

# Used from Task 2 on: the world-building sub-cases instantiate GridWorld
# through _make_world(parent).
const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "pole tiers (network-type set + registration)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_network_type_set(failures)
	_case_registration(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "2 sub-cases pass: network-type set, registration" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) POWER_NETWORK_TYPES — the single source of truth for "placing or
# removing this marks the power topology dirty".
#
# Previously an `or` chain duplicated at grid_world.gd's place and remove
# paths. Two hand-maintained copies of one list is how a seventh type gets
# added to one and not the other; the failure is silent (the network simply
# never rebuilds) until anything else marks it dirty — any place/remove of a
# type already in the set, or an explicit mark_power_network_dirty().
#
# POLE_TYPES is checked here too: it is the pole subset, and a pole missing
# from it is invisible to the BFS that builds network components.
# ===========================================================================
static func _case_network_type_set(failures: Array) -> void:
	# [type, label] parallel rows. The label is a LITERAL, deliberately not
	# Buildings.name_of(t): name_of is DATA[t]["name"], MEDIUM_POLE and
	# SUBSTATION have no DATA row until Task 2, and GDScript evaluates the
	# operand of `%` eagerly — so a name_of() here would fault on every run,
	# not just on failure. The literal is what lets this case cover the two
	# new tiers before they become placeable.
	var want: Array = [
		[Buildings.Type.POWER_POLE, "POWER_POLE"],
		[Buildings.Type.MEDIUM_POLE, "MEDIUM_POLE"],
		[Buildings.Type.SUBSTATION, "SUBSTATION"],
		[Buildings.Type.WATER_WHEEL, "WATER_WHEEL"],
		[Buildings.Type.ELECTRIC_LAMP, "ELECTRIC_LAMP"],
		[Buildings.Type.WINDMILL, "WINDMILL"],
		[Buildings.Type.STEAM_GENERATOR, "STEAM_GENERATOR"],
		[Buildings.Type.ACCUMULATOR, "ACCUMULATOR"],
		[Buildings.Type.ELECTRIC_INSERTER, "ELECTRIC_INSERTER"],
	]
	for row in want:
		var t: int = int(row[0])
		var label: String = String(row[1])
		_check(failures, Buildings.POWER_NETWORK_TYPES.has(t),
			"(1) POWER_NETWORK_TYPES is missing %s, so placing one would not mark the topology dirty" % label)
	_check(failures, not Buildings.POWER_NETWORK_TYPES.has(Buildings.Type.BELT),
		"(1) POWER_NETWORK_TYPES contains BELT, which would rebuild the power topology on every belt placement")

	# All three pole tiers must be in POLE_TYPES.
	var want_poles: Array = [
		[Buildings.Type.POWER_POLE, "POWER_POLE"],
		[Buildings.Type.MEDIUM_POLE, "MEDIUM_POLE"],
		[Buildings.Type.SUBSTATION, "SUBSTATION"],
	]
	for prow in want_poles:
		var pt: int = int(prow[0])
		var plabel: String = String(prow[1])
		_check(failures, Buildings.POLE_TYPES.has(pt),
			"(1) POLE_TYPES is missing %s, so the BFS would never treat it as a pole" % plabel)

	# POLE_TYPES must be a strict subset of POWER_NETWORK_TYPES. A pole that
	# forms components but does not mark the topology dirty on placement is
	# exactly the silent failure this pair of sets exists to prevent.
	for pole_t in Buildings.POLE_TYPES:
		_check(failures, Buildings.POWER_NETWORK_TYPES.has(int(pole_t)),
			"(1) POLE_TYPES has enum value %d but POWER_NETWORK_TYPES does not" % int(pole_t))

	# ...and only poles. Generators and consumers belong to the network but
	# do not form components or project a supply area.
	_check(failures, not Buildings.POLE_TYPES.has(Buildings.Type.WATER_WHEEL),
		"(1) POLE_TYPES contains WATER_WHEEL, but a generator is not a pole")
	_check(failures, not Buildings.POLE_TYPES.has(Buildings.Type.ELECTRIC_LAMP),
		"(1) POLE_TYPES contains ELECTRIC_LAMP, but a consumer is not a pole")

# ===========================================================================
# (2) REGISTRATION — both tiers exist, are placeable, and carry the numbers
# the whole session's arithmetic depends on.
#
# Footprint is asserted as a LITERAL rather than read back from DATA: the
# point is to pin the design decision (substation is 2x2) independently of
# the implementation, so a silent edit to DATA reddens here.
# ===========================================================================
static func _case_registration(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rows: Array = [
		[Buildings.Type.POWER_POLE,  Vector2i(1, 1), Vector2i(5, 5),  "basic"],
		[Buildings.Type.MEDIUM_POLE, Vector2i(1, 1), Vector2i(10, 5), "medium"],
		[Buildings.Type.SUBSTATION,  Vector2i(2, 2), Vector2i(15, 5), "substation"],
	]
	for row in rows:
		var t: int = int(row[0])
		var want_fp: Vector2i = row[1]
		var pos: Vector2i = row[2]
		var label: String = String(row[3])
		_check(failures, Buildings.footprint_of(t) == want_fp,
			"(2) footprint_of(%s) should be %s, got %s" % [label, str(want_fp), str(Buildings.footprint_of(t))])
		_check(failures, Buildings.POLE_TYPES.has(t),
			"(2) POLE_TYPES is missing %s, so BFS will never treat it as a pole" % label)
		_check(failures, world.place_building(t, pos),
			"(2) placing a %s at %s failed: %s" % [label, str(pos), str(world.last_building_place_error)])
		var b: Building = world.building_at(pos)
		_check(failures, b != null and b.type == t,
			"(2) no %s building at %s after placement" % [label, str(pos)])
	# The substation occupies all FOUR of its cells, not just the anchor.
	# occupied is what save/load rehydrates from, so a wrong footprint here
	# silently corrupts collision after a reload.
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_check(failures, world.has_building_at(Vector2i(15, 5) + d),
			"(2) substation cell %s is not marked occupied" % str(Vector2i(15, 5) + d))
	_teardown(world)

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## A fresh GridWorld parented to `parent` so its _ready() runs.
##
## No terrain is laid: a new GridWorld has an empty `tiles` dict, so every
## cell reads back Terrain.DEFAULT_OVERLAY (NONE) and Terrain.DEFAULT_BASE
## (GRASS). All three pole tiers list Overlay.NONE in requires_overlay, and
## GRASS is not WATER, so can_place_building passes on bare ground.
static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

static func _teardown(world) -> void:
	if world == null:
		return
	world.queue_free()
