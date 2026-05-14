extends RefCounted

## Building Interaction UI Session 3 tests (session-building-ui-3).
##
## Covers the architectural pieces shipped this session:
##   1. slot_layout entries for retter, loom, tailor, briquetter, sugar_press,
##      yeast_culture (correct shapes, kinds, accepts, recipe alignment)
##   2. ProcessorPanel-fluid pattern: Retter/Yeast Culture extend
##      ProcessorPanel directly (no overrides) and render fluid_indicator
##      via the shared helper. Verify drag-drop validation:
##        - Drop FLAX into Retter input → in_buffer accepts
##        - Drop wrong-type into Retter input → rejected
##        - Click on Retter's fluid indicator → no-op (not a slot, not in
##          _building_slot_rects)
##   3. ProcessorPanel reuse milestone: count buildings whose panel
##      `extends ProcessorPanel` with no overrides — confirms the pattern
##      reaches 10 consumers post-Session-3.
##   4. Shared `draw_fluid_indicator` helper exists on BuildingPanel base
##      (verifies extraction; sanity check of the method signature).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "building UI session 3 (cloth chain + fluid Processor + 10-consumer milestone)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. slot_layout shapes for all 6 new buildings ----------
	var briquetter: Array = Buildings.slot_layout_for(Buildings.Type.BRIQUETTER)
	_check(failures, briquetter.size() == 2, "briquetter slot_layout size: expected 2 (input+output)")
	if briquetter.size() == 2:
		_check(failures, Items.Type.STRAW in briquetter[0]["accepts"], "briquetter input accepts STRAW")
		_check(failures, Items.Type.FUEL_BRIQUETTE in briquetter[1]["accepts"], "briquetter output is FUEL_BRIQUETTE")

	var sugar_press: Array = Buildings.slot_layout_for(Buildings.Type.SUGAR_PRESS)
	_check(failures, sugar_press.size() == 2, "sugar_press slot_layout size: expected 2")
	if sugar_press.size() == 2:
		_check(failures, Items.Type.SUGAR_BEET in sugar_press[0]["accepts"], "sugar_press input accepts SUGAR_BEET")
		_check(failures, Items.Type.SUGAR in sugar_press[1]["accepts"], "sugar_press output is SUGAR")

	var loom: Array = Buildings.slot_layout_for(Buildings.Type.LOOM)
	_check(failures, loom.size() == 2, "loom slot_layout size: expected 2")
	if loom.size() == 2:
		_check(failures, Items.Type.FIBER in loom[0]["accepts"], "loom input accepts FIBER")
		_check(failures, Items.Type.CLOTH in loom[1]["accepts"], "loom output is CLOTH")

	var tailor: Array = Buildings.slot_layout_for(Buildings.Type.TAILOR)
	_check(failures, tailor.size() == 2, "tailor slot_layout size: expected 2")
	if tailor.size() == 2:
		_check(failures, Items.Type.CLOTH in tailor[0]["accepts"], "tailor input accepts CLOTH")
		_check(failures, Items.Type.BAG in tailor[1]["accepts"], "tailor output is BAG")

	# Retter: 1 solid + 1 fluid_indicator + 1 output (3 entries).
	var retter: Array = Buildings.slot_layout_for(Buildings.Type.RETTER)
	_check(failures, retter.size() == 3, "retter slot_layout size: expected 3 (input+fluid+output)")
	var retter_kinds: Array = []
	for s in retter:
		retter_kinds.append(str(s["kind"]))
	_check(failures, retter_kinds == ["input", "fluid_indicator", "output"],
		"retter slot kinds: expected [input, fluid_indicator, output], got %s" % str(retter_kinds))
	# Verify fluid_indicator's fluid_type is WATER.
	for s in retter:
		if str(s["kind"]) == "fluid_indicator":
			_check(failures, int(s.get("fluid_type", -1)) == Fluids.Type.WATER,
				"retter fluid_indicator should specify Fluids.Type.WATER")

	# Yeast Culture: same shape as Retter.
	var yc: Array = Buildings.slot_layout_for(Buildings.Type.YEAST_CULTURE)
	_check(failures, yc.size() == 3, "yeast_culture slot_layout size: expected 3")
	var yc_kinds: Array = []
	for s in yc:
		yc_kinds.append(str(s["kind"]))
	_check(failures, yc_kinds == ["input", "fluid_indicator", "output"],
		"yeast_culture slot kinds: expected [input, fluid_indicator, output], got %s" % str(yc_kinds))

	# All 6 have has_interaction_ui == true.
	for t in [Buildings.Type.BRIQUETTER, Buildings.Type.SUGAR_PRESS, Buildings.Type.LOOM,
	          Buildings.Type.TAILOR, Buildings.Type.RETTER, Buildings.Type.YEAST_CULTURE]:
		_check(failures, Buildings.has_interaction_ui(t),
			"%s should have interaction UI after session 3" % Buildings.name_of(t))

	# ---------- 2. ProcessorPanel-fluid pattern: Retter drag-drop ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.RETTER, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "retter placement failed: %s" % world.last_building_place_error }
	var retter_b: Building = world.building_at(Vector2i(0, 0))

	# Open RetterPanel via ProcessorPanel base (no overrides — should work
	# identical to Mill/Loom/Tailor).
	var panel = preload("res://scripts/ui/retter_panel.gd").new()
	parent.add_child(panel)
	var inv := Inventory.new(8)
	var cursor := CursorStack.new()
	var toasted: Array = []
	panel.cursor = cursor
	panel.inventory = inv
	panel.toast_callback = func(msg): toasted.append(msg)
	panel.open(retter_b, world)

	# Drop FLAX into the input slot.
	cursor.pick(Items.Type.FLAX, 4)
	var flax_slot: Dictionary = retter[0]   # first slot is input_flax
	panel._drop_into_slot(flax_slot, -1, SlotClickHandler.MOD_NONE)
	_check(failures, BuildingPanel._buffer_count(retter_b.state["in_buffer"], Items.Type.FLAX) == 4,
		"retter flax drop: in_buffer should have 4 FLAX")

	# Drop wrong-type (CLOTH) into FLAX-only slot — rejected.
	cursor.pick(Items.Type.CLOTH, 1)
	toasted.clear()
	panel._drop_into_slot(flax_slot, -1, SlotClickHandler.MOD_NONE)
	_check(failures, cursor.has_item() and cursor.item_type == Items.Type.CLOTH,
		"wrong-type drop: cursor should still hold CLOTH")
	_check(failures, toasted.size() == 1 and "accepts" in str(toasted[0]).to_lower(),
		"wrong-type drop: should toast 'accepts' list")
	cursor.clear()

	# Confirm the fluid_indicator slot is NOT in _building_slot_rects (not
	# a click-target). Iterate the rect list and verify no entry has
	# kind="fluid_indicator".
	var rects: Array = panel._building_slot_rects()
	for entry in rects:
		var kind: String = str(entry["slot_def"].get("kind", ""))
		_check(failures, kind != "fluid_indicator",
			"fluid_indicator should NOT appear in _building_slot_rects (render-only)")

	panel.queue_free()
	_disconnect(world); world.queue_free()

	# ---------- 3. ProcessorPanel reuse milestone: 10 consumers ----------
	# Count buildings whose panel script is just `extends ProcessorPanel`
	# with no overrides. Static check via file content — looks for files
	# that do NOT define _draw_building_specific or _building_slot_rects.
	var no_override_panels: Array = []
	for path in [
		"res://scripts/ui/mill_panel.gd",
		"res://scripts/ui/oven_panel.gd",
		"res://scripts/ui/proofer_panel.gd",
		"res://scripts/ui/packager_panel.gd",
		"res://scripts/ui/loom_panel.gd",
		"res://scripts/ui/tailor_panel.gd",
		"res://scripts/ui/briquetter_panel.gd",
		"res://scripts/ui/sugar_press_panel.gd",
		"res://scripts/ui/retter_panel.gd",
		"res://scripts/ui/yeast_culture_panel.gd",
	]:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			failures.append("can't open %s for reuse audit" % path)
			continue
		var content: String = f.get_as_text()
		f.close()
		# Pure subclass: no `_draw_building_specific(` or `_building_slot_rects(` definition.
		if not "_draw_building_specific(" in content and not "_building_slot_rects(" in content:
			no_override_panels.append(path)
	# Expected: ALL 10 are pure subclasses (no overrides).
	_check(failures, no_override_panels.size() == 10,
		"ProcessorPanel reuse: expected 10 no-override panels, got %d" % no_override_panels.size())

	# ---------- 4. Shared fluid helper exists on BuildingPanel base ----------
	# Sanity check: the method exists on the class. Calling it requires
	# real arguments, so we just verify the class has it via instantiation.
	var bp = preload("res://scripts/ui/building_panel.gd").new()
	parent.add_child(bp)
	_check(failures, bp.has_method("draw_fluid_indicator"),
		"BuildingPanel.draw_fluid_indicator should exist (extracted at session 3)")
	bp.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all session 3 panels valid; ProcessorPanel reuse at 10 consumers; fluid helper centralized" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
