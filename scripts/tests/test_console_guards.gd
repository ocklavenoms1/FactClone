extends RefCounted

## DEV CONSOLE GUARDS — audit cluster G (#23, #24, #47, #79).
##
## Four unrelated defects that happen to share one file. Each section below
## reproduces the CONSEQUENCE the audit named, not merely the mechanism; where
## the two diverged, the divergence is written down beside the assertion.
##
## ---------------------------------------------------------------------------
## #23 — `place` paved the anchor only, and its rollback never rolled anything
## ---------------------------------------------------------------------------
## `_cmd_place` advertises "Bypasses overlay check". It bypassed it for exactly
## one cell: on failure it painted the building's required overlay at the anchor
## and retried. Every 2×2 overlay-requiring building (Mixer, Oven, Proofer,
## Packager) therefore failed anyway, because `can_place_building` checks the
## overlay on every footprint cell.
##
## The second half is the one that was nearly filed as fixed. The rollback line
##
##     grid_world.set_overlay(pos, pre_overlay)
##
## has existed since the console's first commit (42e46f0), so reading the code
## says "the overlay is restored on failure". It is not: `pre_overlay` is
## Overlay.NONE on bare grass, and `Terrain.can_place_overlay` returns false for
## NONE (terrain.gd:85-86 — "use clear path, not paint"). The call returns false
## and does nothing. The paint is already in `tile_modifications`, which is
## save-persisted, so a failed `place` left a permanent stone tile behind.
##
## A restore that exists and never runs is indistinguishable, from the source,
## from a restore that works. That is the whole point of testing the outcome.
##
## ---------------------------------------------------------------------------
## #24 — unbounded radius
## ---------------------------------------------------------------------------
## Both `deplete_area` and `tile` rejected radius < 0 and nothing else. Measured
## on this machine at 0.68 µs per cell, `deplete_area 0 0 999999` visits
## (2r+1)² ≈ 4.0e12 cells: about 755 hours. One extra keystroke — 9999 instead
## of 999 — is four and a half minutes of frozen main thread.
##
## The two commands get different fixes because the costs differ. deplete_area's
## cost is iteration over a 512×512 world, so its loop is CLIPPED to the world
## and every radius keeps its meaning. `tile`'s cost is the output string it
## builds (≈4 chars/cell, so r=99999 is ~1.6e11 characters), and no clip helps
## because the grid is printed, not stored — so it takes a hard cap.
##
## ---------------------------------------------------------------------------
## #47 — set_soil left the scar behind
## ---------------------------------------------------------------------------
## `set_soil x y 100` erased the soil modification and the regen progress and
## left `tile_wasteland_state` untouched, so the console's own `tile` dump
## printed "Soil: 100 / 100" and "Wasteland: SCARRED" three lines apart, and the
## tile kept refusing planters and bouncing LOW/MID compost.
##
## ---------------------------------------------------------------------------
## #79 — the header's command list
## ---------------------------------------------------------------------------
## console.gd's header said "12 commands" and named twelve; the registry held
## fourteen. Correcting the number would have re-created the finding the next
## time a command landed — this project has re-encountered that class often
## enough to have a name for it. So the header is parsed here and checked
## against `_register_commands()`, count AND names.
##
## The parser fails LOUD, never open. If the header block is missing, appears
## twice, or is reformatted past recognition, this test fails rather than
## finding nothing and agreeing with itself.

const ConsoleScript = preload("res://scripts/ui/console.gd")
const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const CONSOLE_PATH: String = "res://scripts/ui/console.gd"

## Wall-clock ceiling for the whole-world deplete_area sweep, in microseconds.
##
## Both numbers below are measured on this machine, not estimated. Clipped, the
## sweep touches the 262144 in-bounds tiles at ~0.68 µs each ≈ 0.18 s. Unclipped
## it also visits every out-of-bounds cell, which costs ~0.17 µs each: radius
## 2000 measured 2.79 s over 16.0M cells, so radius 6000 (144M cells) is ~25 s.
##
## The first draft of this used radius 2000 against the same 2.0 s budget — a
## 1.4× margin on the failing side, which is a coin-flip on a loaded machine,
## not a test. 6000 puts the budget ~11× above the passing cost and ~12× below
## the failing one.
const DEPLETE_SWEEP_BUDGET_USEC: int = 2_000_000
const SWEEP_RADIUS: int = 6000

## Must equal console.gd's TILE_GRID_RADIUS_MAX. Deliberately duplicated — see
## the note beside its use.
const TILE_GRID_RADIUS_MAX: int = 16

static func test_name() -> String:
	return "console guards (place footprint + rollback, radius bounds, set_soil wasteland, header inventory)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_test_place_footprint(parent, failures)
	_test_place_rollback(parent, failures)
	_test_radius_bounds(parent, failures)
	_test_set_soil_clears_wasteland(parent, failures)
	_test_header_inventory(failures)
	if failures.is_empty():
		return { "ok": true, "message": "all console guard checks passed" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------------------------------------------------------------------------
# #23 (a) — the whole footprint gets paved, not just the anchor
# ---------------------------------------------------------------------------

static func _test_place_footprint(parent: Node, failures: Array) -> void:
	var rig: Array = _rig(parent)
	var console = rig[0]
	var world = rig[1]

	# MIXER is 2×2 and requires [STONE, PATH]. On bare grass the anchor-only
	# paint left three cells unpaved and the retry failed every time.
	_check(failures, Buildings.footprint_of(Buildings.Type.MIXER) == Vector2i(2, 2),
		"precondition: MIXER should be 2×2, got %s" % str(Buildings.footprint_of(Buildings.Type.MIXER)))
	var out: String = console.execute("place mixer 5 5")
	_check(failures, out.begins_with("Placed"),
		"`place mixer 5 5` on bare grass should succeed (help text says it bypasses the overlay check), got '%s'" % out)
	_check(failures, world.has_building_at(Vector2i(5, 5)),
		"`place mixer 5 5` should leave a building at the anchor")
	for cell in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		_check(failures, world.overlay_at(cell) == Terrain.Overlay.STONE,
			"every MIXER footprint cell should be paved, %s is %s" % [
				str(cell), Terrain.overlay_name(world.overlay_at(cell))])
	_teardown(console, world)

# ---------------------------------------------------------------------------
# #23 (b) — a failed place leaves the terrain exactly as it found it
# ---------------------------------------------------------------------------

static func _test_place_rollback(parent: Node, failures: Array) -> void:
	# 1×1 case. PUMP requires [STONE, PATH] and additionally must touch water.
	# The overlay paint succeeds, the retry fails on the water rule, and the
	# rollback used to no-op — leaving stone on a tile with nothing on it.
	var rig: Array = _rig(parent)
	var console = rig[0]
	var world = rig[1]
	var pos := Vector2i(10, 10)
	var out: String = console.execute("place pump 10 10")
	_check(failures, out.begins_with("Cannot place"),
		"`place pump 10 10` with no water anywhere should fail, got '%s'" % out)
	_check(failures, world.overlay_at(pos) == Terrain.Overlay.NONE,
		"a failed `place` must leave no stray overlay; (10, 10) is %s" % Terrain.overlay_name(world.overlay_at(pos)))
	_check(failures, not world.tile_modifications.has(pos),
		"a failed `place` must not record a tile modification — tile_modifications is save-persisted")
	# The reported reason must be the one that actually stopped the placement,
	# not the overlay error the console itself already resolved.
	_check(failures, out.to_lower().find("water") >= 0,
		"the failure message should name the reason the RETRY failed, got '%s'" % out)
	_teardown(console, world)

	# Multi-cell case: three cells get painted, the fourth cannot be painted at
	# all (a building sits on it), and all three must be rolled back.
	rig = _rig(parent)
	console = rig[0]
	world = rig[1]
	# COMPOSTER is 1×1 and accepts Overlay.NONE, so it sits on bare grass inside
	# the Mixer's footprint without needing any paving of its own.
	_check(failures, world.place_building(Buildings.Type.COMPOSTER, Vector2i(6, 6), Belt.DIR_E),
		"precondition: composter should place on bare grass at (6, 6)")
	out = console.execute("place mixer 5 5")
	_check(failures, out.begins_with("Cannot place"),
		"`place mixer 5 5` with a composter inside the footprint should fail, got '%s'" % out)
	for cell in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)]:
		_check(failures, world.overlay_at(cell) == Terrain.Overlay.NONE,
			"partial paint must be rolled back; %s is %s" % [
				str(cell), Terrain.overlay_name(world.overlay_at(cell))])
		_check(failures, not world.tile_modifications.has(cell),
			"rolled-back cell %s must leave no tile_modifications record" % str(cell))
	_check(failures, world.has_building_at(Vector2i(6, 6)),
		"the rollback must not remove the composter that blocked the placement")
	_teardown(console, world)

# ---------------------------------------------------------------------------
# #24 — radius bounds
# ---------------------------------------------------------------------------

static func _test_radius_bounds(parent: Node, failures: Array) -> void:
	var rig: Array = _rig(parent)
	var console = rig[0]
	var world = rig[1]
	var world_tiles: int = (WorldGenerator.WORLD_MAX - WorldGenerator.WORLD_MIN) \
		* (WorldGenerator.WORLD_MAX - WorldGenerator.WORLD_MIN)

	# A radius that overhangs the world on all four sides must cost no more than
	# the world itself. Radius 2000 is 16.0M cells unclipped and 262144 clipped.
	var t0: int = Time.get_ticks_usec()
	var out: String = console.execute("deplete_area 0 0 %d 1" % SWEEP_RADIUS)
	var elapsed: int = Time.get_ticks_usec() - t0
	_check(failures, elapsed < DEPLETE_SWEEP_BUDGET_USEC,
		"deplete_area radius %d must be clipped to the world: took %d us, budget %d us" % [
			SWEEP_RADIUS, elapsed, DEPLETE_SWEEP_BUDGET_USEC])
	# Clipping must not change what the command MEANS: every in-bounds tile is
	# still depleted, so the count is the whole world.
	_check(failures, out.find("Depleted %d tiles" % world_tiles) >= 0,
		"a world-spanning deplete_area should still report all %d tiles, got '%s'" % [world_tiles, out])
	_check(failures, world.tile_soil_health(Vector2i(WorldGenerator.WORLD_MIN, WorldGenerator.WORLD_MIN)) == GridWorld.TILE_SOIL_FULL - 1,
		"the far corner tile must actually have been depleted")
	# The bound must hold for an argument that overflows int64 when you add to
	# it, not just for a big one. `_parse_int` hands through anything
	# `is_valid_int` accepts, and without the clamp `center.x + dx` wraps: the
	# span comes out empty and the command reports "Depleted 0 tiles around
	# (0, 0)" — measured, by deleting the clamp and running this. Silently doing
	# nothing and saying so in the past tense is the worse of the two failures
	# the clamp prevents; the frozen main thread at least announces itself.
	var overflow: String = console.execute("deplete_area 0 0 9223372036854775807 1")
	_check(failures, overflow.find("Depleted %d tiles" % world_tiles) >= 0,
		"an int64-max radius should still deplete the whole world, got '%s'" % overflow)

	# The center has to be a real tile. Before, an out-of-bounds center swept a
	# region containing no world and reported "Depleted 0 tiles" — an answer
	# shaped like a success. It is also the precondition that makes the radius
	# clamp exact, so it is asserted rather than assumed.
	var bad_center: String = console.execute("deplete_area 10000 0 5")
	_check(failures, bad_center.find("outside world bounds") >= 0,
		"an out-of-bounds deplete_area center should be refused, got '%s'" % bad_center)

	# A small radius is untouched by the bound.
	var small: String = console.execute("deplete_area 0 0 2 1")
	_check(failures, small.find("Depleted 25 tiles") >= 0,
		"deplete_area radius 2 should still report 25 tiles, got '%s'" % small)
	# Negative radius keeps its own message.
	_check(failures, console.execute("deplete_area 0 0 -1").find("must be >= 0") >= 0,
		"negative radius should still be refused by name")

	# `tile` grid mode is capped, because its cost is the string it prints.
	# The bound is written here as a literal rather than read from
	# console.gd's constant on purpose: moving the cap should have to move this
	# test too, so the number is chosen once and deliberately, in both places.
	var over: String = console.execute("tile 0 0 %d" % (TILE_GRID_RADIUS_MAX + 1))
	_check(failures, ConsoleScript._is_refusal(over),
		"tile radius above the cap must be refused, got '%s'" % _oneline(over))
	# Checked as a phrase, not as `find("16")`. The first draft looked for the
	# bare number and passed against the UNFIXED code, because a radius-17 soil
	# grid prints a column header reading "16".
	_check(failures, over.to_lower().find("must be <= %d" % TILE_GRID_RADIUS_MAX) >= 0,
		"the tile cap refusal should name the cap, got '%s'" % _oneline(over))
	var at_cap: String = console.execute("tile 0 0 %d" % TILE_GRID_RADIUS_MAX)
	_check(failures, at_cap.begins_with("Soil grid centered on"),
		"tile AT the cap must still work, got '%s'" % _oneline(at_cap))
	_check(failures, console.execute("tile 0 0 -1").find("must be >= 0") >= 0,
		"negative tile radius should still be refused by name")
	_teardown(console, world)

# ---------------------------------------------------------------------------
# #47 — set_soil to full clears the scar
# ---------------------------------------------------------------------------

static func _test_set_soil_clears_wasteland(parent: Node, failures: Array) -> void:
	var rig: Array = _rig(parent)
	var console = rig[0]
	var world = rig[1]
	var pos := Vector2i(3, 3)

	console.execute("wasteland 3 3")
	_check(failures, world.is_wasteland_at(pos),
		"precondition: `wasteland 3 3` should scar the tile")
	var out: String = console.execute("set_soil 3 3 100")
	_check(failures, out.find("soil → 100") >= 0,
		"`set_soil 3 3 100` should report the new value, got '%s'" % out)
	_check(failures, not world.is_wasteland_at(pos),
		"soil restored to full must clear the scar — otherwise the tile reads 100 and stays dead")
	_check(failures, not world.tile_wasteland_state.has(pos),
		"the wasteland entry itself should be gone, not just the scarred flag")
	# The consequence, stated as the console states it: its own tile dump used to
	# print full soil and SCARRED in the same four lines.
	var dump: String = console.execute("tile 3 3")
	_check(failures, dump.find("Soil: 100 / 100") >= 0,
		"tile dump should read full soil, got '%s'" % dump)
	_check(failures, dump.find("SCARRED") < 0,
		"tile dump must not report SCARRED on a full-soil tile, got '%s'" % dump)
	# Downstream: the two behaviours the scar was blocking.
	_check(failures, world.try_apply_fertilizer(pos, Items.Type.COMPOST_LOW),
		"LOW compost should be accepted once the scar is cleared")
	world.set_overlay(pos, Terrain.Overlay.SOIL_TILLED)
	_check(failures, world.place_building(Buildings.Type.PLANTER, pos, Belt.DIR_E, Items.Type.WHEAT),
		"precondition: planter should place on the restored tile")
	var planter = world.building_at(pos)
	Planter.tick(planter, world)
	_check(failures, int(planter.state.get("growth", 0)) > 0,
		"a planter on the restored tile should grow; growth stayed at %s" % str(planter.state.get("growth", 0)))

	# The deliberate boundary: BELOW full, the scar stays. A scarred tile is
	# damaged on a second axis and only Premium Compost (or a full soil reset)
	# clears it. Asserted so a future reader can tell this apart from an
	# oversight of the same shape as the one above.
	console.execute("wasteland 3 3")
	console.execute("set_soil 3 3 99")
	_check(failures, world.is_wasteland_at(pos),
		"set_soil BELOW full must leave the scar in place — only a full restore clears it")
	_teardown(console, world)

# ---------------------------------------------------------------------------
# #79 — the header's command list must match the registry
# ---------------------------------------------------------------------------

## Header shape this parses:
##     ##   - COMMANDS (14): clear, deplete_area, destroy, fertilize, give,
##     ##     help, place, ... wasteland.
## The name list continues across `##` lines until one ends in a period.
const HEADER_CONTINUATION_MAX: int = 6

static func _test_header_inventory(failures: Array) -> void:
	var f = FileAccess.open(CONSOLE_PATH, FileAccess.READ)
	if f == null:
		failures.append("could not open %s to check the header inventory" % CONSOLE_PATH)
		return
	var lines: PackedStringArray = f.get_as_text().split("\n")
	f.close()

	var head := RegEx.new()
	head.compile("^##\\s+-\\s+COMMANDS \\((\\d+)\\):\\s*(.*)$")
	var cont := RegEx.new()
	cont.compile("^##\\s+(\\S.*)$")

	var matches: Array = []
	for i in range(lines.size()):
		var m = head.search(lines[i])
		if m != null:
			matches.append([i, int(m.get_string(1)), m.get_string(2)])
	# Loud on absence and on ambiguity. A parser that finds nothing and reports
	# success is the failure this whole finding is about.
	if matches.size() != 1:
		failures.append("expected exactly one '##   - COMMANDS (N): ...' header line in %s, found %d — if the header was reformatted, update this parser rather than deleting the claim" % [CONSOLE_PATH, matches.size()])
		return

	var start: int = int(matches[0][0])
	var claimed_count: int = int(matches[0][1])
	var text: String = String(matches[0][2]).strip_edges()
	var consumed: int = 0
	while not text.ends_with(".") and consumed < HEADER_CONTINUATION_MAX:
		consumed += 1
		var idx: int = start + consumed
		if idx >= lines.size():
			break
		var cm = cont.search(lines[idx])
		if cm == null:
			break
		text += " " + String(cm.get_string(1)).strip_edges()
	if not text.ends_with("."):
		failures.append("the COMMANDS header name list did not terminate in a period within %d continuation lines; got '%s'" % [HEADER_CONTINUATION_MAX, text])
		return

	var claimed_names: Array = []
	for raw in text.substr(0, text.length() - 1).split(","):
		var n: String = String(raw).strip_edges()
		if n != "":
			claimed_names.append(n)
	claimed_names.sort()

	var console = ConsoleScript.new()
	console._register_commands()
	var actual_names: Array = console._commands.keys()
	actual_names.sort()

	_check(failures, claimed_count == actual_names.size(),
		"console.gd header claims %d commands; _register_commands() has %d" % [claimed_count, actual_names.size()])
	_check(failures, claimed_count == claimed_names.size(),
		"console.gd header claims %d commands but names %d of them" % [claimed_count, claimed_names.size()])
	_check(failures, claimed_names == actual_names,
		"console.gd header names %s; the registry has %s" % [str(claimed_names), str(actual_names)])
	console.free()

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

static func _rig(parent: Node) -> Array:
	var console = ConsoleScript.new()
	parent.add_child(console)
	var world = GridWorldScript.new()
	parent.add_child(world)
	console.grid_world = world
	return [console, world]

static func _teardown(console, world) -> void:
	console.queue_free()
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Multi-line console output collapsed to one readable line, so a failure label
## carrying a soil grid does not push every other label off the report.
static func _oneline(s: String) -> String:
	return s.substr(0, 120).replace("\n", " ⏎ ")
