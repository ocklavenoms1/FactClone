extends RefCounted

## Pole tiers (Electricity Session 3) — parametric POLE_RANGE / SUPPLY_RADIUS,
## either-reaches connection, multi-cell poles, nearest-pole supply tie-break.
##
## Sub-case index (each task appends its own _case_* and wires it into run()):
##   1. POWER_NETWORK_TYPES / POLE_TYPES membership (Task 1).

# Unused at Task 1 — the sub-cases from Task 2 onward build a world through
# _make_world(parent). Kept here so those tasks append a case rather than also
# having to restore the preload; do not "clean up" as dead code.
const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "pole tiers (network-type set)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []
	_case_network_type_set(failures)
	if failures.is_empty():
		return { "ok": true, "message": "1 sub-case passes: network-type set" }
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

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
