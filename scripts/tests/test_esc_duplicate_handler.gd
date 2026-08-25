extends RefCounted

## AUDIT #58 — "Leftover unconditional close_info_panel handler clears the
## info panel on the same Esc press that closed a modal via the priority chain."
##
## THE DEFECT. `main.gd:_process` polls
## `Input.is_action_just_pressed("close_info_panel")` TWICE. The first is the
## documented six-case Esc priority chain, whose step 4 clears the info panel
## only when nothing more urgent is open. The second sits far below, past the
## modal early-return, and calls `info_panel.clear_target()` unconditionally.
##
## The two are not mutually exclusive, because the early-return between them is
## evaluated AFTER the chain has already closed the modal: chain step 1 closes
## the inventory grid, the early-return then reads "no modal open" and does not
## return, and the polled action is still true for the whole frame — so the
## second handler runs too. The chain's precedence is undone on every press.
##
## WHAT THIS SUITE DELIBERATELY DOES NOT TOUCH. The modal used here is the
## INVENTORY GRID, which owns no `_input` handler of its own. The map panel and
## the dev console both do, and both are audit #22 — opening either here would
## make this suite redden for #22 as well, and the two findings would be
## indistinguishable. See the discrimination matrix in the cluster-H report.
##
## TESTABILITY, labelled honestly:
##   - case 2 is BEHAVIOURAL, running production `main.gd:_process`.
##   - case 3 is STRUCTURAL: it counts the `close_info_panel` polls in main.gd's
##     source. That count IS the finding's title, and a behavioural test cannot
##     see a duplicate handler whose effect happens to be masked.

const Harness = preload("res://scripts/tests/esc_input_harness.gd")

static func test_name() -> String:
	return "esc duplicate handler (#58: closing a modal must not also clear the info panel)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. PREMISE: the polled half of an Esc press registers ----------
	# Step 1 of the two-step protocol. This suite's Esc never needs to reach
	# `_input` (no `_input` handler is involved by design), but it MUST reach
	# the Input singleton or main's chain never runs and case 2 passes while
	# testing nothing.
	Harness.press_action("close_info_panel")
	_check(failures, Input.is_action_just_pressed("close_info_panel"),
		"(1) PREMISE: Input.is_action_just_pressed('close_info_panel') is false after action_press, so main's Esc chain would not run at all")

	var ctx: Dictionary = Harness.make_main(parent)
	var main: Node = ctx["main"]

	# ---------- 2. Esc that closes the inventory grid keeps the info panel ----------
	# The scenario from the finding: Q-inspect a tile (info panel showing),
	# open the inventory grid with I, press Esc once. The grid should close and
	# the inspected panel should survive — the player did not ask to dismiss it.
	main.hotbar.clear_selection()
	main.info_panel.set_tile_target(Vector2i(4, 4), main.grid_world)
	main.inventory_grid.toggle()
	_check(failures, main.inventory_grid.is_open(),
		"(2) PREMISE: inventory grid should be open before the Esc press")
	_check(failures, main.info_panel.has_target(),
		"(2) PREMISE: info panel should have a target before the Esc press")
	_check(failures, not main.map_panel.is_open() and not main.dev_console.is_open(),
		"(2) PREMISE: neither map nor console may be open — both own _input Esc handlers, and this case must not be able to redden for #22")

	Harness.press_action("close_info_panel")
	Harness.deliver(ctx, Harness.key_event(KEY_ESCAPE))
	main._process(0.0)

	_check(failures, not main.inventory_grid.is_open(),
		"(2) MECHANISM: one Esc with the inventory grid open must close it (chain step 1). If the grid is still open the chain never ran and the assertion below means nothing")
	_check(failures, main.info_panel.has_target(),
		"(2) the Esc that closed the inventory grid must NOT also clear the info panel. Chain step 1 closed the grid, the modal early-return below then read 'no modal open' and let execution continue to a second, unconditional close_info_panel handler which cleared the target on the same press")

	Harness.teardown(ctx)

	# ---------- 3. STRUCTURAL: exactly one close_info_panel poll ----------
	# The title is "duplicate handler", so the count is the claim. Pinned in
	# source because a second handler can be reintroduced anywhere in the file
	# and only misbehaves for the modal states case 2 does not cover.
	var main_src: String = FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(failures, main_src.length() > 0,
		"(3) PREMISE: could not read main.gd, so this structural check would pass while reading nothing")
	var polls: int = main_src.count("is_action_just_pressed(\"close_info_panel\")")
	_check(failures, polls == 1,
		"(3) main.gd polls close_info_panel %d times; exactly 1 is correct. The Esc priority chain is the single owner of that action — a second poll runs on the same frame as the chain and undoes its precedence (audit #58)" % polls)

	if failures.is_empty():
		return { "ok": true, "message": "3 sub-cases pass: the polled press registers, Esc closes the inventory grid without clearing the info panel, and main.gd polls close_info_panel exactly once" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 16))] }

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
