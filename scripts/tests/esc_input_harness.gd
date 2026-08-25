extends RefCounted

## Shared harness for the three Esc / input-routing suites (audit cluster H:
## #22, #58, #59). NOT a test itself — it has no `test_name()` and is not
## registered in `test_runner.gd`. `test_registration_completeness.gd` only
## scans `test_*.gd`, so this filename is deliberately outside that pattern.
##
## ---------------------------------------------------------------------------
## WHAT IS AND IS NOT DRIVEABLE HEADLESS — measured, not assumed
## ---------------------------------------------------------------------------
##
## The cluster exists because Godot has TWO input mechanisms and main.gd uses
## both: `_input` / `_unhandled_input` receive propagated events, while
## `Input.is_action_just_pressed` polls a global singleton. A test that drives
## only one of them cannot see a defect living in the seam between them, so
## this harness drives both, separately, in the engine's own order.
##
## Measured on Godot 4.6.3 `--headless`, inside `test_runner.tscn`:
##
##   1. ⚠ `get_viewport().push_input(ev)` ON THE ROOT WINDOW DELIVERS NOTHING
##      here. Zero `_input` calls, zero `_unhandled_input` calls, for a key
##      nothing binds — while the same call on the same root Window works when
##      made from a `--script` SceneTree during a real frame. The root's
##      `is_input_handled()` reads true and stays true, i.e. `push_input`
##      returns before the reset it normally performs first (verified
##      separately: a FORCED handled flag does not block delivery, so the
##      stuck flag is a symptom of the early return, not its cause). The
##      remaining difference is that the runner does all its work inside
##      `_ready`, before the first frame — the same no-frame property behind
##      the `_draw` ceiling in NOTES.md. The exact gate inside
##      `Viewport::push_input` was not identified; what matters is that the
##      root Window is NOT a usable input channel here, and a suite that
##      pushed into it would be green and empty.
##
##   2. A `SubViewport` IS a usable channel, in the same `_ready`, with no
##      frame yielded: `_input` and `_unhandled_input` both fire, repeatably
##      across successive pushes, including after a handler has called
##      `set_input_as_handled()`. So `Main` is parented into a SubViewport and
##      every event is pushed there. This also isolates these suites from
##      whatever state other suites leave on the root viewport.
##      `probe_input_reaches_tree()` re-measures the channel at the top of
##      every suite rather than trusting the sentence you are reading — a
##      repro that silently delivers nothing is indistinguishable from a fixed
##      bug, which is the whole reason this project writes premise assertions.
##
##   3. `push_input` does NOT update the `Input` singleton's action state. An
##      `InputEventKey` pushed through a viewport leaves
##      `Input.is_action_just_pressed("close_info_panel")` FALSE. Action state
##      is written only by `Input.parse_input_event` (the OS path) and by
##      `Input.action_press`. So a faithful "the player pressed Esc" is BOTH
##      calls. That is not a shortcut around the finding — it IS the finding:
##      the two mechanisms are independent, and #22 lives in the gap.
##
##   4. ⚠ `Input.action_press` STICKS. `is_action_just_pressed` is
##      `pressed_process_frame == Engine.get_process_frames()`, and the runner
##      never yields a frame, so `get_process_frames()` is 0 all run. Once an
##      action is pressed it reads as "just pressed" for every later poll in
##      the process, and `Input.action_release` does NOT undo it (measured:
##      `pressed` goes false, `just_pressed` stays true). Consequence: a suite
##      CANNOT test "and the next press behaves differently". Anything of that
##      shape is hand-only; say so rather than faking it.
##
##   5. `OS.is_debug_build()` is TRUE under the headless test binary, so the
##      debug-gated dev-console paths in `main.gd:_unhandled_input` are live
##      and testable here. They are NOT live in a production export — see the
##      severity note in the cluster-H report.
##
##   6. A real `Main` from `main.tscn` instantiates, enters the tree and runs
##      `_ready` headless; `@onready` refs (`dev_console`, `map_panel`,
##      `info_panel`, `hotbar`, `inventory_grid`) all resolve, and the
##      console's LineEdit really does take focus and really does receive
##      typed characters. Suites therefore exercise production main.gd rather
##      than an in-test mirror of it — audit #27 is the standing example of
##      why a mirror is worthless.

const MainScene = preload("res://scenes/main.tscn")

## A save path that must not exist, so `Main._ready` takes its
## `_generate_fresh_world()` branch instead of loading whatever fixture a
## previous suite left `SaveSystem.save_path` pointing at. Audit #63 (the
## runner restores neither `save_path` nor the tick rate between tests) is
## still LIVE, so this cannot be left to the runner.
const ABSENT_SAVE_PATH: String = "user://test_esc_routing_absent_save.json"

## Build a real `Main` inside its own SubViewport, with a guarded save path.
## Returns a context Dictionary to hand back to `teardown`.
static func make_main(parent: Node) -> Dictionary:
	var saved_save_path: String = SaveSystem.save_path
	SaveSystem.save_path = ABSENT_SAVE_PATH
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	parent.add_child(viewport)
	var main: Node = MainScene.instantiate()
	viewport.add_child(main)
	return { "main": main, "viewport": viewport, "saved_save_path": saved_save_path }

## Free the Main and its viewport, and restore the save path.
##
## `free()`, NOT `queue_free()`, and that is not a style choice: the runner
## never yields a frame, so a queued free never happens. The Main would stay in
## the tree for the rest of the run with its `_process` and `_input` live,
## eating events out from under every later suite.
static func teardown(ctx: Dictionary) -> void:
	var viewport: Node = ctx.get("viewport")
	if viewport != null and is_instance_valid(viewport):
		if viewport.get_parent() != null:
			viewport.get_parent().remove_child(viewport)
		viewport.free()
	SaveSystem.save_path = String(ctx["saved_save_path"])
	release_all()

## Best-available scrub of the actions these suites press. See note 4: this
## clears `pressed`, it does NOT clear the "just pressed" frame stamp.
static func release_all() -> void:
	for action in ["close_info_panel", "toggle_inventory", "toggle_map"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)

static func key_event(code: int, unicode: int = 0) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.unicode = unicode
	ev.pressed = true
	return ev

## Deliver a key through real viewport propagation: `_input` first, then GUI
## dispatch to whatever holds focus, then `_unhandled_input` — the engine's
## own order, which is the ordering all three findings are about.
static func deliver(ctx: Dictionary, ev: InputEventKey) -> void:
	ctx["viewport"].push_input(ev)

## Press an action on the `Input` singleton, which is the only thing
## `Input.is_action_just_pressed` reads. See note 3.
static func press_action(action: String) -> void:
	Input.action_press(action)

## STEP-1 EVIDENCE: prove the repro reaches the code at all before believing
## anything it reports. Uses KEY_F13, which nothing in this project binds or
## handles, so the answer depends only on whether propagation works and never
## on the state of the finding under test.
## Deliberately goes through `deliver()` rather than calling push_input itself,
## so this measures the path the suites actually use. A probe that took its own
## shortcut would keep reporting a healthy channel after the shared one broke.
static func probe_input_reaches_tree(ctx: Dictionary) -> Dictionary:
	var viewport: Node = ctx["viewport"]
	var probe := InputProbe.new()
	viewport.add_child(probe)
	deliver(ctx, key_event(KEY_F13))
	var result: Dictionary = { "input": probe.input_seen, "unhandled": probe.unhandled_seen }
	viewport.remove_child(probe)
	probe.free()
	return result

class InputProbe extends Node:
	var input_seen: int = 0
	var unhandled_seen: int = 0
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode == KEY_F13:
			input_seen += 1
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode == KEY_F13:
			unhandled_seen += 1
