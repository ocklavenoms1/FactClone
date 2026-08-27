extends RefCounted

## Belt Logistics Session 1, Task 6 — the pair-indicator CONTRACT, at grep
## level. Headless cannot execute a _draw body (the recorded ceiling), so the
## renderer's two structural obligations are pinned against the SOURCE:
##
##   1. grid_world.gd has a DEDICATED indicator pass, and _draw calls it
##      immediately after _draw_power_wires — the defined layer the z-order
##      finding mandates, never the per-building loop.
##   2. The pass answers "which exit?" ONLY via Underground.paired_exit —
##      the predicate's docstring names the renderer as its contracted
##      second caller. A re-derived distance scan here is exactly the drift
##      the contract forbids (the renderer-stricter-than-BFS divergence
##      poles_connected exists to prevent), so the pass body must contain
##      the predicate call and must NOT mention UNDERGROUND_MAX_SPAN — the
##      constant a re-derived scan cannot be written without.
##
## Source-scanning has precedent (test_console_error_classifier.gd,
## test_registration_completeness.gd). Like those, this file reds on the
## ABSENCE of a structure: a refactor that renames the pass, inlines it, or
## moves it off the wire pass's layer must come here and say so.

const GRID_WORLD_PATH: String = "res://scripts/world/grid_world.gd"
const PASS_NAME: String = "_draw_underground_pair_indicators"

static func test_name() -> String:
	return "underground pair-indicator contract (dedicated pass beside _draw_power_wires; paired_exit is the only pairing answer)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []
	var src: String = FileAccess.get_file_as_string(GRID_WORLD_PATH)
	if src == "":
		return { "ok": false, "message": "could not read %s" % GRID_WORLD_PATH }

	# (1a) the dedicated pass exists.
	var def_idx: int = src.find("func %s()" % PASS_NAME)
	_check(failures, def_idx >= 0,
		"(1) grid_world.gd must define the dedicated pass 'func %s()' — if it was renamed or inlined into the per-building loop, the z-order finding just lost its defined layer; rename it here too and re-justify" % PASS_NAME)

	# (1b) _draw CALLS it, and does so after the _draw_power_wires() call.
	# Both call sites are tab-indented; the definitions are column-0, so the
	# "\t" prefix cannot match them.
	var wires_call: int = src.find("\t_draw_power_wires()")
	var pass_call: int = src.find("\t%s()" % PASS_NAME)
	_check(failures, wires_call >= 0 and pass_call >= 0 and wires_call < pass_call,
		"(1) _draw must CALL %s() after the _draw_power_wires() call (wire call at %d, indicator call at %d) — the indicator rides the wire pass's layer: on the buildings, under the hover/harvest UI" % [PASS_NAME, wires_call, pass_call])

	# (1c) IMMEDIATELY after: nothing but blank lines and comments between
	# the two calls, so no other pass can slide in and change the layer.
	if wires_call >= 0 and pass_call > wires_call:
		var wires_stmt: String = "\t_draw_power_wires()"
		var between: String = src.substr(wires_call + wires_stmt.length(), pass_call - wires_call - wires_stmt.length())
		for line in between.split("\n"):
			var t: String = line.strip_edges()
			if t != "" and not t.begins_with("#"):
				_check(failures, false,
					"(1) a non-comment line sits between the wire pass and the indicator pass: '%s' — the indicator pass must run IMMEDIATELY after _draw_power_wires" % t)
				break

	# (2) the predicate contract, on the pass body only (definition to the
	# next column-0 func).
	if def_idx >= 0:
		var body_end: int = src.find("\nfunc ", def_idx + 1)
		var body: String = src.substr(def_idx, (body_end - def_idx) if body_end > def_idx else -1)
		_check(failures, body.find("Underground.paired_exit(") >= 0,
			"(2) the indicator pass must ask Underground.paired_exit which exit an entry feeds — it is the predicate's contracted second caller; anything else can drift from where items actually flow, and the divergence is invisible until a tunnel draws where no items move")
		_check(failures, body.find("UNDERGROUND_MAX_SPAN") < 0,
			"(2) the indicator pass mentions UNDERGROUND_MAX_SPAN — a re-derived distance scan is exactly the drift the paired_exit contract forbids; call the predicate instead")

	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures)] }

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
