extends RefCounted

## AUDIT #59 — "Backtick opens the dev console but cannot close it: the focused
## LineEdit consumes the key before `_unhandled_input`."
##
## THE DEFECT. The toggle lives in `main.gd:_unhandled_input`, which by
## definition only runs for events nothing earlier consumed. While the console
## is open its LineEdit holds focus, and a focused LineEdit eats printable keys
## at GUI dispatch — one stage BEFORE `_unhandled_input`. `console.gd:_input`
## runs before GUI dispatch and could intercept it, but its `match` covers
## ENTER / TAB / UP / DOWN / ESCAPE and not backtick. So the close direction of
## the toggle is unreachable, and the key is typed into the command field as a
## literal '`' instead.
##
## The stray character is the sharper observable of the two and is asserted
## separately: a console that closes but still leaves '`' in the field would be
## half-fixed, and "the console closed" alone cannot see that.
##
## WHY THIS SUITE CANNOT REDDEN FOR THE OTHER TWO CLUSTER-H FINDINGS. It never
## presses Esc, never opens the map, and never reads the info panel or the
## hotbar. #22 and #58 are both Esc-only. See the discrimination matrix in the
## cluster-H report.
##
## TESTABILITY: fully BEHAVIOURAL. The backtick travels the real pipeline —
## `_input`, then GUI dispatch to the focused LineEdit, then
## `_unhandled_input` — through `Viewport.push_input`, which was measured to
## work headless. The LineEdit really does receive and insert the character
## under `--headless`, so the stray-character assertion is a genuine
## observation and not a stand-in for one.
##
## SEVERITY CONTEXT: the console is debug-build-gated (`OS.is_debug_build()`,
## main.gd), so this never reaches a production export. `OS.is_debug_build()`
## is true under the test binary, which is why the open direction is testable
## here at all; case 1 asserts that premise rather than assuming it.

const Harness = preload("res://scripts/tests/esc_input_harness.gd")

static func test_name() -> String:
	return "console backtick toggle (#59: backtick closes the console it opened)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. PREMISE ----------
	var ctx: Dictionary = Harness.make_main(parent)
	var main: Node = ctx["main"]
	var reach: Dictionary = Harness.probe_input_reaches_tree(ctx)
	_check(failures, int(reach["input"]) == 1 and int(reach["unhandled"]) == 1,
		"(1) PREMISE: push_input reached _input %d times and _unhandled_input %d times; both must be 1 or every case below is vacuous" % [int(reach["input"]), int(reach["unhandled"])])
	_check(failures, OS.is_debug_build(),
		"(1) PREMISE: OS.is_debug_build() is false, so main.gd's backtick branch is gated off and this suite would be testing a disabled feature")

	# ---------- 2. CONTROL: backtick OPENS the console ----------
	# The open direction goes through main.gd's `_unhandled_input`, which does
	# receive the key because nothing has focus yet. Asserted so that a case-3
	# failure cannot be blamed on the event never arriving.
	_check(failures, not main.dev_console.is_open(),
		"(2) PREMISE: dev console should start closed")
	Harness.deliver(ctx, Harness.key_event(KEY_QUOTELEFT, 96))
	_check(failures, main.dev_console.is_open(),
		"(2) MECHANISM: backtick with the console CLOSED must open it via main.gd's _unhandled_input. If this fails the event is not arriving and case 3 proves nothing")

	# ---------- 3. THE FINDING: backtick CLOSES the console ----------
	var field: LineEdit = main.dev_console._input_field
	_check(failures, field != null and field.has_focus(),
		"(3) PREMISE: the console's LineEdit should hold focus while open — that focus is the mechanism that swallows the key")
	_check(failures, field != null and field.text == "",
		"(3) PREMISE: the command field should be empty before the backtick press")

	Harness.deliver(ctx, Harness.key_event(KEY_QUOTELEFT, 96))

	_check(failures, not main.dev_console.is_open(),
		"(3) backtick with the console OPEN must close it. The toggle lives in main.gd's _unhandled_input, and the focused LineEdit consumes the key at GUI dispatch before that ever runs — console.gd's _input has to claim it first")
	_check(failures, field != null and field.text == "",
		"(3) backtick must not be typed into the command field. The field now holds '%s' — the key reached the LineEdit instead of being intercepted, which is the same fact as the console staying open" % [("" if field == null else field.text)])

	Harness.teardown(ctx)

	if failures.is_empty():
		return { "ok": true, "message": "3 sub-cases pass: input reaches the tree in a debug build, backtick opens the console, and backtick closes it without leaving a stray character in the command field" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 16))] }

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
