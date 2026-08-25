extends RefCounted

## INSERTER STATUS LINES — the two state→string maps, and the states they must
## be able to tell apart.
##
## `inserter_panel.gd:122` is `"Status: NO POWER"`, a plain assignment in a
## state→string mapping. The original scoping called this "assert the RENDERED
## string"; it is not a rendering problem at all. The mapping is pure data with
## a `draw_string` on the end of it, and this file asserts the mapping.
## `docs/scoping/visual-verification.md` route A.
##
## ---------------------------------------------------------------------------
## THERE ARE TWO COPIES, AND THAT IS DELIBERATE — checked before writing this
## ---------------------------------------------------------------------------
## The brief asked whether "Status: NO POWER" is constructed anywhere else,
## because a test that pins one of two copies leaves the other free to drift.
## Grepped across `scripts/`; the answer is yes, and the situation is more
## interesting than a duplicate:
##
##   1. `InserterPanel.status_line`     — "Status: NO POWER"
##      The open-panel line. Short, because it shares its row with the cycle
##      readout.
##   2. `Inserter.info_lines`           — "Status: NO POWER — connect a pole"
##      The hover info panel. Carries the FIX, because that panel is the one a
##      confused player is looking at. Its own docstring records the width
##      measurements that produced the wording (211 px against a 220 px panel;
##      the longer candidates measured 282 px and 457 px and were visibly cut).
##
## Two more matches exist and are NOT this mapping: `electric_lamp.gd:80` sets
## `status = "NO POWER"` for a different building's info line, and
## `electric_rig.gd:429` is a debug-rig summary string. `burner.gd:145` /
## `drill_panel.gd:189` / `smelter_panel.gd:151` carry the NO FUEL wording for
## the burner machines. None of them is a second copy of the inserter's map.
##
## So (1) and (2) are two audiences, not a duplication to be merged. Merging
## them would either put an imperative fix in a row that has no space for one,
## or strip the fix from the panel that exists to give it. What they must NOT do
## is diverge on WHICH STATES THEY CAN TELL APART — and that, not the wording,
## is what sub-case (3) pins across both.
##
## ---------------------------------------------------------------------------
## THE STATE LIST IS DERIVED, NOT TRANSCRIBED
## ---------------------------------------------------------------------------
## Sub-case (3) reads `STATE_*` out of `inserter.gd`'s constant map at runtime.
## A seventh state added tomorrow enters this test automatically and reddens it
## until both maps have an arm for it. A hand-written list here would have to be
## updated by the same person who forgot to update the maps, which is the
## count-drift shape this project keeps re-encountering.

const InserterScript = preload("res://scripts/world/inserter.gd")
const InserterPanelScript = preload("res://scripts/ui/inserter_panel.gd")

## ΔE maths, borrowed rather than re-implemented. One implementation of a
## colour metric in the suite; see that file's header for why it is L*a*b* and
## not RGB. Sub-case (4) is the only consumer here.
const Colour = preload("res://scripts/tests/test_inserter_body_colours.gd")

## The status colours carry meaning ("NO FUEL is cool blue, NO POWER is warm
## amber"), so they need a real separation. Same ΔE 25 floor as the body
## colours, deliberately: these are drawn as TEXT on a dark panel at size 13
## rather than as 32 px fills under a state tint, which is an EASIER
## discrimination, so reusing the map-level floor is conservative rather than
## lax, and one number is easier to reason about than two.
##
## Measured: the tightest live pair is COLOR_BLOCKED ↔ COLOR_NO_POWER at ΔE
## 34.12 — the yellow and the amber, which are the two that look closest and
## still clear the floor by 36%. The pair the panel's own comment names,
## NO_FUEL ↔ NO_POWER, is ΔE 106.02.
const STATUS_COLOUR_FLOOR_DE: float = 25.0

## Constants of a script, read at runtime.
##
## ⚠ Takes a `Script`-typed PARAMETER rather than calling
## `<TheScriptConst>.get_script_constant_map()` directly.
## `get_script_constant_map` is an instance method on `Script`, and a
## preloaded const is a CLASS
## reference, so the direct form is `Parse Error: Cannot call non-static
## function "get_script_constant_map()" on the class "Inserter" directly` —
## which, under warnings-as-errors, takes the whole runner down with it
## (measured: `exit=124`, six Parse Errors, no summary line). Binding the class
## ref to a `Script` parameter is the coercion the parser accepts.
static func _constants_of(s: Script) -> Dictionary:
	return s.get_script_constant_map()

static func test_name() -> String:
	return "inserter status lines (both state→string maps are total over STATE_*, mutually distinct, and colour-separated)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	_case_1_panel_map_is_exact(failures)
	_case_2_info_lines_map_is_exact(failures)
	var n_states: int = _case_3_both_maps_are_total_over_every_state(failures)
	_case_4_status_colours_are_separable(failures)
	_case_5_the_fallback_is_reachable_and_loud(failures)

	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: all 6 panel status strings and all 6 info_lines status strings are pinned verbatim; both maps are total and injective over the %d STATE_* constants read from inserter.gd; the five status colours clear ΔE %.1f; and an unmapped state falls to a magenta \"Status: ?\" rather than an empty black string" % [n_states, STATUS_COLOUR_FLOOR_DE] }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# ===========================================================================
# (1) THE PANEL MAP, verbatim.
#
# Pinned as literals rather than derived from anything, because the literal IS
# the product: these six strings are what a player reads. A test that computed
# them from the same source the panel computes them from would assert nothing.
# ===========================================================================
const PANEL_EXPECTED: Array = [
	["STATE_IDLE", "Status: IDLE", "COLOR_IDLE"],
	["STATE_WORKING_OUT", "Status: WORKING (out)", "COLOR_WORKING"],
	["STATE_BLOCKED_AT_DEST", "Status: BLOCKED at destination", "COLOR_BLOCKED"],
	["STATE_WORKING_IN", "Status: WORKING (returning)", "COLOR_WORKING"],
	["STATE_NO_FUEL", "Status: NO FUEL", "COLOR_NO_FUEL"],
	["STATE_NO_POWER", "Status: NO POWER", "COLOR_NO_POWER"],
]

static func _case_1_panel_map_is_exact(failures: Array) -> void:
	var consts: Dictionary = _constants_of(InserterScript)
	var panel_consts: Dictionary = _constants_of(InserterPanelScript)
	for row in PANEL_EXPECTED:
		var state_name: String = str(row[0])
		if not consts.has(state_name):
			failures.append("(1) inserter.gd has no constant %s — this test's expectations are stale" % state_name)
			continue
		var got: Dictionary = InserterPanelScript.status_line(int(consts[state_name]))
		if String(got["text"]) != str(row[1]):
			failures.append("(1) %s → \"%s\", expected \"%s\"" % [state_name, String(got["text"]), str(row[1])])
		var want_colour_name: String = str(row[2])
		if not panel_consts.has(want_colour_name):
			failures.append("(1) inserter_panel.gd has no constant %s" % want_colour_name)
			continue
		if got["color"] != panel_consts[want_colour_name]:
			failures.append("(1) %s → colour %s, expected %s (%s)"
				% [state_name, str(got["color"]), str(panel_consts[want_colour_name]), want_colour_name])

# ===========================================================================
# (2) THE INFO-PANEL MAP, verbatim. `Inserter.info_lines` puts the status on
# row 0; the rows below it are per-tier detail and belong to other tests.
#
# `world` is passed as null on purpose — `info_lines`' own signature allows it
# and the status arm never touches it, so this stays a mapping assertion rather
# than dragging a GridWorld in to read six strings.
# ===========================================================================
const INFO_EXPECTED: Array = [
	["STATE_IDLE", "Status: Idle"],
	["STATE_WORKING_OUT", "Status: Working (out)"],
	["STATE_BLOCKED_AT_DEST", "Status: BLOCKED — destination full or rejecting item"],
	["STATE_WORKING_IN", "Status: Working (returning)"],
	["STATE_NO_FUEL", "Status: NO FUEL — feed wood, coal, or fuel briquette"],
	["STATE_NO_POWER", "Status: NO POWER — connect a pole"],
]

static func _case_2_info_lines_map_is_exact(failures: Array) -> void:
	var consts: Dictionary = _constants_of(InserterScript)
	for row in INFO_EXPECTED:
		var state_name: String = str(row[0])
		if not consts.has(state_name):
			failures.append("(2) inserter.gd has no constant %s — this test's expectations are stale" % state_name)
			continue
		var got: String = _info_status(int(consts[state_name]))
		if got != str(row[1]):
			failures.append("(2) info_lines %s → \"%s\", expected \"%s\"" % [state_name, got, str(row[1])])

## Row 0 of `Inserter.info_lines` for a burner-tier inserter parked in `state`.
## LONG_REACH rather than ELECTRIC so the rows below the status line stay on the
## burner path; nothing here reads them, but a tier change would make the
## helper's output depend on the power network.
static func _info_status(state: int) -> String:
	var b: Building = Inserter.make(Vector2i.ZERO, Belt.DIR_E, Buildings.Type.LONG_REACH_INSERTER)
	b.state["state"] = state
	var lines: Array = Inserter.info_lines(b, null)
	if lines.is_empty():
		return "(info_lines returned nothing)"
	return str(lines[0])

# ===========================================================================
# (3) BOTH MAPS ARE TOTAL AND INJECTIVE OVER EVERY STATE_* CONSTANT.
#
# This is the sub-case that survives a seventh state. The constant list is read
# out of `inserter.gd` at runtime, so a new `STATE_STACKING` arrives here
# without anybody editing this file — and reddens twice over until both maps
# have an arm for it:
#
#   - the PANEL falls to STATUS_UNKNOWN_TEXT, which sub-case (5) forbids for a
#     real state;
#   - `info_lines` falls to its initialiser "Idle", which collides with
#     STATE_IDLE's own row and fails the injectivity check below.
#
# The `info_lines` fallback is the more dangerous of the two and is the reason
# injectivity is asserted rather than just non-emptiness: an unmapped state
# there does not look broken, it looks IDLE. Absence indistinguishable from
# success — NOTES.md, "Protocol: silent compensation". It is pinned rather than
# fixed because changing that initialiser is a production behaviour change this
# task did not scope; the guard makes the omission loud, which is what the
# protocol asks for.
#
# Returns the number of states found, for the pass message.
# ===========================================================================
static func _case_3_both_maps_are_total_over_every_state(failures: Array) -> int:
	var consts: Dictionary = _constants_of(InserterScript)
	var states: Array = []
	for k in consts.keys():
		var kn: String = str(k)
		if kn.begins_with("STATE_") and typeof(consts[k]) == TYPE_INT:
			states.append([kn, int(consts[k])])
	if states.size() < 6:
		failures.append("(3) found only %d STATE_* constants in inserter.gd; the file declared 6 when this test was written, so either the enum shrank or the constant map is not being read" % states.size())
	var panel_seen: Dictionary = {}
	var info_seen: Dictionary = {}
	for row in states:
		var sname: String = str(row[0])
		var sval: int = int(row[1])
		var ptext: String = String(InserterPanelScript.status_line(sval)["text"])
		var itext: String = _info_status(sval)
		if ptext == InserterPanelScript.STATUS_UNKNOWN_TEXT:
			failures.append("(3) InserterPanel.status_line has no arm for %s (= %d); it falls through to \"%s\" and the panel shows a placeholder instead of a status"
				% [sname, sval, InserterPanelScript.STATUS_UNKNOWN_TEXT])
		if ptext.strip_edges() == "":
			failures.append("(3) InserterPanel.status_line returned an EMPTY string for %s — the panel would draw nothing where the status belongs" % sname)
		if panel_seen.has(ptext):
			failures.append("(3) panel: %s and %s both read \"%s\" — two states a player cannot tell apart"
				% [str(panel_seen[ptext]), sname, ptext])
		else:
			panel_seen[ptext] = sname
		if info_seen.has(itext):
			failures.append("(3) info_lines: %s and %s both read \"%s\" — %s has no arm in the match and is falling through to the initialiser, so a stalled inserter reports as working"
				% [str(info_seen[itext]), sname, itext, sname])
		else:
			info_seen[itext] = sname
		# Every status line, in both maps, is a "Status: " row. Cheap, and it
		# catches the arm that returns a bare verb.
		if not ptext.begins_with("Status: "):
			failures.append("(3) panel %s → \"%s\" does not begin with \"Status: \"" % [sname, ptext])
		if not itext.begins_with("Status: "):
			failures.append("(3) info_lines %s → \"%s\" does not begin with \"Status: \"" % [sname, itext])
	return states.size()

# ===========================================================================
# (4) THE STATUS COLOURS ARE SEPARABLE.
#
# `inserter_panel.gd:39-44` claims NO POWER is "warm amber against COLOR_NO_FUEL's
# cool blue — the two stalls have different causes and different fixes, so the
# status line must distinguish them by colour as well as by text". A prose claim
# about colour, unmeasured until here.
#
# WORKING_OUT and WORKING_IN share COLOR_WORKING on purpose (they are the same
# condition mid-swing, told apart by the text), so the set compared is the
# DISTINCT colours, not one per state.
# ===========================================================================
static func _case_4_status_colours_are_separable(failures: Array) -> void:
	var consts: Dictionary = _constants_of(InserterScript)
	var by_colour: Dictionary = {}
	for row in PANEL_EXPECTED:
		if not consts.has(str(row[0])):
			continue
		var c: Color = InserterPanelScript.status_line(int(consts[str(row[0])]))["color"]
		if not by_colour.has(c):
			by_colour[c] = str(row[2])
	var names: Array = by_colour.values()
	var cols: Array = by_colour.keys()
	for i in range(cols.size()):
		for j in range(i + 1, cols.size()):
			var d: float = Colour.delta_e(cols[i], cols[j])
			if d < STATUS_COLOUR_FLOOR_DE:
				failures.append("(4) status colours %s %s and %s %s are only ΔE %.2f apart (floor %.1f) — two states meant to be told apart at a glance would read the same"
					% [str(names[i]), str(cols[i]), str(names[j]), str(cols[j]), d, STATUS_COLOUR_FLOOR_DE])
	# The specific pair the comment names.
	var nf: Color = InserterPanelScript.COLOR_NO_FUEL
	var np: Color = InserterPanelScript.COLOR_NO_POWER
	if Colour.delta_e(nf, np) < STATUS_COLOUR_FLOOR_DE:
		failures.append("(4) COLOR_NO_FUEL %s and COLOR_NO_POWER %s are ΔE %.2f apart — inserter_panel.gd's \"warm amber against a cool blue\" no longer holds"
			% [str(nf), str(np), Colour.delta_e(nf, np)])

# ===========================================================================
# (5) THE FALLBACK EXISTS, AND IS LOUD.
#
# Before this task the inline `match` had no default arm: an unrecognised state
# left `status_text` at "" and `status_color` at the Color default, so the panel
# drew an empty black string — a missing status line reads as "this panel has no
# status line", not as a bug. Positive control for sub-case (3): if the fallback
# were removed and replaced with an empty string, (3)'s STATUS_UNKNOWN_TEXT
# check would silently stop being able to fire.
# ===========================================================================
static func _case_5_the_fallback_is_reachable_and_loud(failures: Array) -> void:
	var consts: Dictionary = _constants_of(InserterScript)
	# A value no STATE_* constant holds.
	var bogus: int = 9999
	for k in consts.keys():
		if str(k).begins_with("STATE_") and typeof(consts[k]) == TYPE_INT and int(consts[k]) == bogus:
			failures.append("(5) 9999 is now a real STATE_* value; pick a different sentinel")
			return
	var got: Dictionary = InserterPanelScript.status_line(bogus)
	if String(got["text"]) != InserterPanelScript.STATUS_UNKNOWN_TEXT:
		failures.append("(5) an unmapped state returned \"%s\", expected \"%s\" — sub-case (3)'s check cannot fire"
			% [String(got["text"]), InserterPanelScript.STATUS_UNKNOWN_TEXT])
	if String(got["text"]).strip_edges() == "":
		failures.append("(5) an unmapped state returns an empty string; the panel would draw nothing where the status belongs")
	var c: Color = got["color"]
	if c.a <= 0.0:
		failures.append("(5) the unknown-state colour %s is transparent — the placeholder would be invisible" % str(c))
	# It must not be one of the real status colours, or the placeholder is
	# camouflaged as a real state.
	for row in PANEL_EXPECTED:
		if not consts.has(str(row[0])):
			continue
		var real: Color = InserterPanelScript.status_line(int(consts[str(row[0])]))["color"]
		if c == real:
			failures.append("(5) the unknown-state colour %s is also %s's colour — the placeholder is camouflaged" % [str(c), str(row[0])])
