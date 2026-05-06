extends RefCounted

## Wheel-trigger M-key map tests (session-zoom-to-map).
##
## Exercises the pure-static `_compute_zoom_action` so the wheel-zoom
## decision logic is verified without instantiating Main's full scene
## tree. Modal toggle is reported as a flag; the production wrapper
## actually calls `map_panel.toggle()` from `_handle_zoom_wheel`.
##
## Sub-suites (mirror the design pass test list, with #7 added as the
## refactor regression test):
##   1. Wheel-down decreases zoom above min, modal stays closed.
##   2. Wheel-down at min triggers map open, target_zoom unchanged.
##   3. Modal open blocks wheel-down (no zoom change, no extra toggle).
##   4. Modal open + wheel-up requests close.
##   5. Wheel-up after modal closed zooms in normally.
##   6. M-key direct toggle is independent of wheel state (covered by
##      simply observing that _compute_zoom_action makes no decisions
##      based on M-key activity — the modal-open input parameter is
##      the ONLY modal-state coupling).
##   7. Regression: wheel-up in world view at any zoom < ZOOM_MAX zooms
##      in normally; multiple steps approach ZOOM_MAX without exceeding.

const MainScript = preload("res://scripts/main.gd")

static func test_name() -> String:
	return "wheel-trigger M-key map (zoom ↓ floor opens modal, ↑ closes)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. wheel-down decreases zoom above min ----------
	var r1: Dictionary = MainScript._compute_zoom_action(1.0, false, -1)
	# 1.0 / 1.15 ≈ 0.870
	_check(failures, r1["new_zoom"] < 1.0 and r1["new_zoom"] > MainScript.ZOOM_MIN,
		"wheel-down at zoom 1.0 should decrease zoom but stay above min, got %f" % r1["new_zoom"])
	_check(failures, not r1["toggle_modal"],
		"wheel-down at zoom 1.0 should NOT toggle modal")

	# ---------- 2. wheel-down at min triggers map open ----------
	var r2: Dictionary = MainScript._compute_zoom_action(MainScript.ZOOM_MIN, false, -1)
	_check(failures, r2["toggle_modal"],
		"wheel-down at ZOOM_MIN should request modal toggle")
	_check(failures, abs(r2["new_zoom"] - MainScript.ZOOM_MIN) < 1e-5,
		"wheel-down at ZOOM_MIN should leave zoom unchanged at floor, got %f" % r2["new_zoom"])

	# Floor-trigger should also fire just slightly above ZOOM_MIN (within
	# epsilon) so floating-point drift from the lerp doesn't strand the
	# trigger. Use ZOOM_MIN + 1e-5 (under epsilon = 1e-4).
	var r2b: Dictionary = MainScript._compute_zoom_action(MainScript.ZOOM_MIN + 1.0e-5, false, -1)
	_check(failures, r2b["toggle_modal"],
		"wheel-down within float-epsilon of ZOOM_MIN should still trigger modal")

	# ---------- 3. modal-open blocks wheel-down (no-op) ----------
	var r3: Dictionary = MainScript._compute_zoom_action(MainScript.ZOOM_MIN, true, -1)
	_check(failures, not r3["toggle_modal"],
		"wheel-down with modal open should NOT toggle (debounce)")
	_check(failures, abs(r3["new_zoom"] - MainScript.ZOOM_MIN) < 1e-5,
		"wheel-down with modal open should leave zoom unchanged")

	# Same at higher zoom values.
	var r3b: Dictionary = MainScript._compute_zoom_action(2.0, true, -1)
	_check(failures, not r3b["toggle_modal"],
		"wheel-down with modal open at zoom 2.0 should NOT toggle")
	_check(failures, abs(r3b["new_zoom"] - 2.0) < 1e-5,
		"wheel-down with modal open at zoom 2.0 should leave zoom unchanged")

	# ---------- 4. modal-open + wheel-up requests close ----------
	var r4: Dictionary = MainScript._compute_zoom_action(MainScript.ZOOM_MIN, true, +1)
	_check(failures, r4["toggle_modal"],
		"wheel-up with modal open should request close")
	_check(failures, abs(r4["new_zoom"] - MainScript.ZOOM_MIN) < 1e-5,
		"wheel-up with modal open should leave zoom unchanged at floor")

	# ---------- 5. wheel-up after modal closed zooms in ----------
	# Simulate the post-close state: modal closed, zoom at floor.
	var r5: Dictionary = MainScript._compute_zoom_action(MainScript.ZOOM_MIN, false, +1)
	_check(failures, r5["new_zoom"] > MainScript.ZOOM_MIN,
		"wheel-up at floor with modal closed should increase zoom, got %f" % r5["new_zoom"])
	_check(failures, not r5["toggle_modal"],
		"wheel-up at floor with modal closed should NOT toggle modal")

	# ---------- 6. modal toggle independent of wheel state ----------
	# The static helper exposes only `modal_open` as a coupling parameter.
	# Pressing M directly to toggle the modal happens outside this function.
	# Verified structurally: identical inputs (with only direction varying)
	# don't suddenly start/stop reporting toggle requests beyond the
	# documented modal-open and at-floor branches.
	var r6_a: Dictionary = MainScript._compute_zoom_action(2.0, false, +1)
	var r6_b: Dictionary = MainScript._compute_zoom_action(2.0, false, -1)
	_check(failures, not r6_a["toggle_modal"] and not r6_b["toggle_modal"],
		"mid-zoom + modal closed: neither direction should toggle (M-key is the only path here)")

	# ---------- 7. REGRESSION: wheel-up zooms in normally across range ----------
	# Refactor regression test: walk wheel-up from ZOOM_MIN approaching
	# ZOOM_MAX. Each step strictly increases until clamped at the ceiling.
	var z: float = MainScript.ZOOM_MIN
	var prev: float = z
	var steps_taken: int = 0
	# 30 wheel-ups is more than enough to clamp at the ceiling
	# (0.85 * 1.15^N >= 6.75 → N ≈ 15). Loop 30 to verify post-clamp stability.
	for _i in range(30):
		var r: Dictionary = MainScript._compute_zoom_action(z, false, +1)
		_check(failures, not r["toggle_modal"],
			"wheel-up in world view should never toggle modal, but did at step %d" % steps_taken)
		_check(failures, r["new_zoom"] >= prev,
			"wheel-up should never decrease zoom (step %d: prev=%f new=%f)" % [steps_taken, prev, r["new_zoom"]])
		_check(failures, r["new_zoom"] <= MainScript.ZOOM_MAX + 1e-5,
			"wheel-up should clamp at ZOOM_MAX (step %d: got %f)" % [steps_taken, r["new_zoom"]])
		prev = r["new_zoom"]
		z = r["new_zoom"]
		steps_taken += 1
	_check(failures, abs(z - MainScript.ZOOM_MAX) < 1e-5,
		"after 30 wheel-ups from floor, zoom should be clamped at ZOOM_MAX, got %f" % z)

	if failures.is_empty():
		return { "ok": true, "message": "all 7 sub-suites passed (modal trigger + close + debounce + regression)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
