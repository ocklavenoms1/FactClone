extends RefCounted

## AUDIT #22 — "One Esc press performs two actions: modal Esc handlers in
## `_input` race main's polled Esc priority chain in the same frame."
##
## THE DEFECT. `map_panel.gd` and `console.gd` each close their own modal from
## `_input` on raw KEY_ESCAPE and call `get_viewport().set_input_as_handled()`.
## That call stops EVENT PROPAGATION and nothing else. `main.gd`'s Esc priority
## chain does not read events — it polls
## `Input.is_action_just_pressed("close_info_panel")` from `_process`, which
## runs later in the SAME frame and is untouched by the handled flag. By then
## the modal is already closed, so the chain's own step for that modal is
## skipped and it falls through to the next live step. One press, two actions.
##
## WHAT THIS SUITE DELIBERATELY DOES NOT OBSERVE. The fall-through victim used
## here is always the HOTBAR SELECTION (chain step 5), never the info panel
## (step 4). Audit #58 is a second, unconditional `close_info_panel` handler
## lower in the same `_process`; if this suite watched the info panel it would
## also redden for #58 and the two findings would be indistinguishable. Three
## findings in this cluster all answer "which handler saw the key", so each
## suite is built to redden for its own defect and stay green under the other
## two. See the discrimination matrix in the cluster-H report.
##
## TESTABILITY, labelled honestly:
##   - cases 2, 3 and 4 are BEHAVIOURAL. The Esc reaches `_input` through real
##     viewport propagation, and the polled half runs production
##     `main.gd:_process`. Nothing is mirrored in the test.
##   - case 5 is STRUCTURAL. It asserts `map_panel.gd` names KEY_ESCAPE in no
##     line of code, which is the shape the fix chose; a behavioural test
##     cannot tell "map_panel no longer closes it in `_input`" from "it still
##     does, but something downstream compensated".
##   - NOT COVERED, and hand-only: anything of the form "and the NEXT press
##     behaves normally". `Input.is_action_just_pressed` is a frame-stamp
##     comparison and the runner never advances a frame, so an action pressed
##     once reads as just-pressed for the rest of the run and successive
##     presses are indistinguishable. Case 4 works around this by driving the
##     SECOND `_process` off the same sticky press, which is enough to catch a
##     stranded latch but is not a real second press. The hand ritual is in
##     the cluster-H report.

const Harness = preload("res://scripts/tests/esc_input_harness.gd")

static func test_name() -> String:
	return "esc modal race (#22: one Esc, one action — map and console routes)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. PREMISE: the repro can reach the code at all ----------
	# Step 1 of the two-step protocol. A push_input that silently delivers
	# nothing would make every case below vacuously green — the exact shape
	# where a broken repro is indistinguishable from a fixed bug.
	var ctx: Dictionary = Harness.make_main(parent)
	var main: Node = ctx["main"]
	var reach: Dictionary = Harness.probe_input_reaches_tree(ctx)
	_check(failures, int(reach["input"]) == 1,
		"(1) PREMISE: push_input did not reach _input (%d calls). Every case below drives Esc that way, so they would all pass while testing nothing" % int(reach["input"]))
	_check(failures, int(reach["unhandled"]) == 1,
		"(1) PREMISE: push_input did not reach _unhandled_input (%d calls)" % int(reach["unhandled"]))

	# ---------- 2. ROUTE A — MAP PANEL ----------
	# Player has a hotbar selection and opens the map. One Esc must close the
	# map (chain step 3) and do NOTHING else. The bug: map_panel._input closes
	# it first, the chain then sees is_open()==false and runs step 5 instead.
	main.info_panel.clear_target()
	main.hotbar.set_selection_in_current(0)
	main.map_panel.toggle()
	_check(failures, main.map_panel.is_open(),
		"(2) PREMISE: map panel should be open before the Esc press")
	_check(failures, main.hotbar.has_selection(),
		"(2) PREMISE: hotbar should have a selection before the Esc press")
	_check(failures, not main.info_panel.has_target(),
		"(2) PREMISE: info panel must have NO target, so this case cannot redden for #58")

	Harness.press_action("close_info_panel")
	Harness.deliver(ctx, Harness.key_event(KEY_ESCAPE))
	_check(failures, Input.is_action_just_pressed("close_info_panel"),
		"(2) PREMISE: the polled half of the press did not register, so main's Esc chain would not run and this case would pass without exercising it")
	main._process(0.0)

	_check(failures, not main.map_panel.is_open(),
		"(2) one Esc with the map open must close the map")
	_check(failures, main.hotbar.has_selection(),
		"(2) one Esc that closed the MAP must not ALSO clear the hotbar selection. map_panel._input closed the map during the input phase, then main's polled chain found is_open()==false and fell through to step 5")

	# ---------- 3. ROUTE B — DEV CONSOLE ----------
	# Same shape through the other `_input` handler. console.gd's KEY_ESCAPE
	# branch closes the console, so main's console gate (`if dev_console
	# .is_open(): return`, above the chain) no longer fires either, and the
	# chain runs on a press that was already spent.
	main.hotbar.set_selection_in_current(0)
	main.info_panel.clear_target()
	main.dev_console.toggle()
	_check(failures, main.dev_console.is_open(),
		"(3) PREMISE: dev console should be open before the Esc press")
	_check(failures, main.hotbar.has_selection(),
		"(3) PREMISE: hotbar should have a selection before the Esc press")
	_check(failures, not main.map_panel.is_open(),
		"(3) PREMISE: map must be closed, so this case exercises the console route only")

	Harness.press_action("close_info_panel")
	Harness.deliver(ctx, Harness.key_event(KEY_ESCAPE))
	_check(failures, not main.dev_console.is_open(),
		"(3) MECHANISM: console.gd's _input should have closed the console during the input phase — if it did not, the race this case is about never happened and the result below means nothing")
	main._process(0.0)

	_check(failures, main.hotbar.has_selection(),
		"(3) one Esc that closed the CONSOLE must not ALSO clear the hotbar selection. The console closed itself in _input, main's console gate then read is_open()==false, and the polled chain spent the same press a second time")

	# ---------- 4. The latch must not strand itself into a later frame ----------
	# This case guards a DESIGN DECISION the audit's fix text did not make, so it
	# gets its own assertion rather than riding on case 3. The console's Esc latch
	# is one-shot and read-and-clear, and main.gd reads it ABOVE the dev-console
	# and quantity-picker gates — both of which can `return` before the Esc chain.
	# Read it below them instead and a latch set on a frame that bailed early
	# survives into a later frame, where it silently swallows an unrelated Esc:
	# the same "one press, wrong number of actions" family the finding is about,
	# reintroduced by its own fix.
	#
	# The reachable route is the console over the quantity picker — main.gd's
	# _unhandled_input deliberately lets backtick through the picker gate, so the
	# console CAN be opened on top of it.
	_check(failures, main.quantity_picker != null,
		"(4) PREMISE: no quantity_picker on this Main, so the early-return this case needs cannot be produced")
	if main.quantity_picker != null:
		main.hotbar.set_selection_in_current(0)
		main.dev_console.toggle()
		main.quantity_picker.visible = true
		_check(failures, main.dev_console.is_open() and main.quantity_picker.visible,
			"(4) PREMISE: console open on top of a visible quantity picker")

		Harness.press_action("close_info_panel")
		Harness.deliver(ctx, Harness.key_event(KEY_ESCAPE))
		_check(failures, not main.dev_console.is_open(),
			"(4) MECHANISM: the Esc should have closed the console in _input, setting the latch this case is about")
		# This _process bails at the quantity-picker gate, BELOW where the latch
		# is read and ABOVE the Esc chain.
		main._process(0.0)

		# Picker dismissed; a later, unrelated Esc must still reach the chain.
		main.quantity_picker.visible = false
		main.map_panel.toggle()
		_check(failures, main.map_panel.is_open(),
			"(4) PREMISE: map should be open for the follow-up press")
		main._process(0.0)
		_check(failures, not main.map_panel.is_open(),
			"(4) a later Esc must still close the map. The console's latch was set on a frame whose _process returned early at the quantity-picker gate; if it is not read above that gate it stays set and swallows this press instead")

	Harness.teardown(ctx)

	# ---------- 5. STRUCTURAL: map_panel owns no Esc handler ----------
	# The fix for the map route is deletion, not compensation: main's chain
	# step 3 already closes the map on Esc. If a future change reintroduces a
	# KEY_ESCAPE branch in map_panel._input, the race returns in a form case 2
	# might not catch (a compensating guard elsewhere would keep case 2 green
	# while the two handlers were both live again).
	#
	# CODE lines only. The deleted handler was replaced by a comment that names
	# the key it must not handle — that comment is the record of why the absence
	# is deliberate, and a whole-file string search would read it as the defect
	# and redden on the fix's own documentation.
	var map_src: String = FileAccess.get_file_as_string("res://scripts/ui/map_panel.gd")
	_check(failures, map_src.length() > 0,
		"(5) PREMISE: could not read map_panel.gd, so this structural check would pass while reading nothing")
	var esc_code_lines: Array = []
	var line_no: int = 0
	for raw_line in map_src.split("\n"):
		line_no += 1
		var line: String = String(raw_line).strip_edges()
		if line.begins_with("#"):
			continue
		if line.find("KEY_ESCAPE") >= 0:
			esc_code_lines.append(str(line_no))
	_check(failures, esc_code_lines.is_empty(),
		"(5) map_panel.gd names KEY_ESCAPE in code at line(s) %s. Esc for the map belongs to main.gd's priority chain (step 3) alone — a second handler in _input closes the map before the chain polls, and the chain then spends the press on the next step down (audit #22)" % ", ".join(esc_code_lines))

	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: input reaches the tree, one Esc closes the map without clearing the hotbar, one Esc closes the console without clearing the hotbar, the console latch does not strand across an early-returning frame, and map_panel owns no Esc handler" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 16))] }

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
