extends RefCounted

## QoL Cluster B Item 1 tests — tooltip + Items.gd description field.
##
## Sub-cases:
##   1. Items.description_of(WHEAT) returns a string (empty or real).
##   2. Items.description_of(-1) returns "" (safe fallback for unknown).
##   3. TooltipManager hover-start sets pending target; end_hover clears.
##       (Sub-case 3 lands in Task 4 when TooltipManager exists.)

static func test_name() -> String:
	return "tooltip manager (accessor + hover lifecycle)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ===========================================================================
	# (1) Items.description_of(WHEAT) returns a string (may be empty in Task 2,
	# real content in Task 3). Defensive: just confirm String return type.
	# ===========================================================================
	var d_wheat = Items.description_of(Items.Type.WHEAT)
	_check(failures, typeof(d_wheat) == TYPE_STRING,
		"(1) description_of(WHEAT) should return String, got type %d" % typeof(d_wheat))

	# ===========================================================================
	# (2) Items.description_of(-1) returns "" — unknown type fallback.
	# ===========================================================================
	var d_unknown = Items.description_of(-1)
	_check(failures, typeof(d_unknown) == TYPE_STRING and d_unknown == "",
		"(2) description_of(-1) should return empty String, got %s" % str(d_unknown))

	if failures.is_empty():
		return { "ok": true, "message": "2 sub-cases pass: description_of accessor + unknown-type fallback" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _check(failures: Array, condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
