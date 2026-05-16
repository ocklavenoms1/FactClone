extends RefCounted

## Building Interaction UI Session 4 tests (session-building-ui-4 — final
## session of the multi-session arc).
##
## Covers:
##   1. slot_layout entries for harvester, planter, thresher (correct
##      shapes, kinds, accepts).
##   2. ProcessorPanel reuse milestone hits 11 consumers (Thresher joins).
##   3. Multi-session UI arc COMPLETE: every "interactive" building has a
##      panel; only passive infrastructure (Pipe/Pump/Belt) lacks one.
##   4. PlanterPanel int-typed-output handling: take from ripe planter
##      drains output and resets growth (verifies the override path).
##   5. HarvesterPanel coverage scan returns expected enum states.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "building UI session 4 (extraction tier + thresher catch-up + arc COMPLETE)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. slot_layout shapes ----------
	# Harvester: single output_multi (buffer is multi-type bag).
	var harvester: Array = Buildings.slot_layout_for(Buildings.Type.HARVESTER)
	_check(failures, harvester.size() == 1, "harvester slot_layout size: expected 1, got %d" % harvester.size())
	if not harvester.is_empty():
		_check(failures, str(harvester[0]["kind"]) == "output_multi", "harvester slot kind should be output_multi")
		_check(failures, str(harvester[0]["state_field"]) == "buffer", "harvester state_field should be 'buffer'")
		_check(failures, int(harvester[0]["max_stack"]) == 50, "harvester max_stack should be BUFFER_CAPACITY (50)")
		_check(failures, int(harvester[0]["multi_count"]) == 6, "harvester multi_count should be 6")

	# Planter: single output (int-typed; PlanterPanel handles).
	var planter: Array = Buildings.slot_layout_for(Buildings.Type.PLANTER)
	_check(failures, planter.size() == 1, "planter slot_layout size: expected 1, got %d" % planter.size())
	if not planter.is_empty():
		_check(failures, str(planter[0]["kind"]) == "output", "planter slot kind should be 'output'")
		_check(failures, int(planter[0]["max_stack"]) == 1, "planter max_stack should be YIELD_PER_CYCLE (1)")
		_check(failures, str(planter[0]["state_field"]) == "output", "planter state_field should be 'output'")

	# Thresher: input + 2 outputs (grain + straw).
	var thresher: Array = Buildings.slot_layout_for(Buildings.Type.THRESHER)
	_check(failures, thresher.size() == 3, "thresher slot_layout size: expected 3 (input + 2 outputs)")
	if thresher.size() == 3:
		_check(failures, Items.Type.WHEAT in thresher[0]["accepts"], "thresher input accepts WHEAT")
		_check(failures, Items.Type.GRAIN in thresher[1]["accepts"], "thresher output 1 produces GRAIN")
		_check(failures, Items.Type.STRAW in thresher[2]["accepts"], "thresher output 2 produces STRAW")

	for t in [Buildings.Type.HARVESTER, Buildings.Type.PLANTER, Buildings.Type.THRESHER]:
		_check(failures, Buildings.has_interaction_ui(t),
			"%s should have interaction UI after session 4" % Buildings.name_of(t))

	# ---------- 2. ProcessorPanel reuse milestone: 11 consumers ----------
	# Static file scan: count panels that are pure `extends ProcessorPanel`
	# with no overrides (no _draw_building_specific or _building_slot_rects).
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
		"res://scripts/ui/thresher_panel.gd",
	]:
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			failures.append("can't open %s for reuse audit" % path)
			continue
		var content: String = f.get_as_text()
		f.close()
		if not "_draw_building_specific(" in content and not "_building_slot_rects(" in content:
			no_override_panels.append(path)
	_check(failures, no_override_panels.size() == 11,
		"ProcessorPanel reuse: expected 11 no-override panels post-Session-4, got %d" % no_override_panels.size())

	# ---------- 3. Multi-session arc COMPLETE: every interactive building has a panel ----------
	# All Buildings.Type values EXCEPT passive infrastructure should have
	# has_interaction_ui == true.
	var passive: Array = [Buildings.Type.PIPE, Buildings.Type.PUMP, Buildings.Type.BELT, Buildings.Type.POWER_POLE, Buildings.Type.WATER_WHEEL, Buildings.Type.ELECTRIC_LAMP]
	for type_value in Buildings.DATA.keys():
		var t: int = int(type_value)
		if t in passive:
			_check(failures, not Buildings.has_interaction_ui(t),
				"%s is passive infrastructure; should NOT have interaction UI" % Buildings.name_of(t))
		else:
			_check(failures, Buildings.has_interaction_ui(t),
				"%s should have interaction UI (multi-session arc complete)" % Buildings.name_of(t))

	# ---------- 4. PlanterPanel int-typed output drain ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED)
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(0, 0), 0, Items.Type.WHEAT):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "planter placement failed: %s" % world.last_building_place_error }
	var p: Building = world.building_at(Vector2i(0, 0))

	# Force the planter to ripe state (skip the 600-tick growth).
	p.state["growth"] = Planter.max_growth_for(Items.Type.WHEAT)
	p.state["output"] = 1
	_check(failures, Planter.is_ripe(p), "planter should be ripe after manual state-set")

	# Open PlanterPanel and run its take handler.
	var ppanel = preload("res://scripts/ui/planter_panel.gd").new()
	parent.add_child(ppanel)
	var inv := Inventory.new(8)
	var cursor := CursorStack.new()
	ppanel.cursor = cursor
	ppanel.inventory = inv
	ppanel.toast_callback = func(_msg): pass
	ppanel.open(p, world)

	# Take from output slot — should pick up 1 wheat to cursor and reset growth.
	var output_slot: Dictionary = planter[0]
	ppanel._take_from_slot(output_slot, -1, SlotClickHandler.MOD_NONE)
	_check(failures, cursor.item_type == Items.Type.WHEAT and cursor.count == 1,
		"PlanterPanel take: cursor should hold WHEAT ×1, got %s ×%d" % [Items.name_of(cursor.item_type), cursor.count])
	_check(failures, int(p.state.get("output", -1)) == 0, "planter output should be 0 after take")
	_check(failures, int(p.state.get("growth", -1)) == 0, "planter growth should reset to 0 after take")
	# Take with empty planter → no-op.
	cursor.clear()
	ppanel._take_from_slot(output_slot, -1, SlotClickHandler.MOD_NONE)
	_check(failures, not cursor.has_item(), "take from empty planter: cursor should remain empty")

	ppanel.queue_free()

	# ---------- 5. HarvesterPanel coverage scan ----------
	# Place harvester at (5, 5). Surround with various neighbors.
	world.set_overlay(Vector2i(5, 5), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.HARVESTER, Vector2i(5, 5)):
		_cleanup(world)
		return { "ok": false, "message": "harvester placement failed" }
	# (4, 5) = ripe planter
	world.set_overlay(Vector2i(4, 5), Terrain.Overlay.SOIL_TILLED)
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(4, 5), 0, Items.Type.WHEAT):
		_cleanup(world)
		return { "ok": false, "message": "ripe planter placement failed" }
	var ripe_planter: Building = world.building_at(Vector2i(4, 5))
	ripe_planter.state["output"] = 1
	# (6, 5) = growing planter (default state)
	world.set_overlay(Vector2i(6, 5), Terrain.Overlay.SOIL_TILLED)
	if not world.place_building(Buildings.Type.PLANTER, Vector2i(6, 5), 0, Items.Type.SUGAR_BEET):
		_cleanup(world)
		return { "ok": false, "message": "growing planter placement failed" }
	# (5, 4) = chest (non-planter building)
	world.set_overlay(Vector2i(5, 4), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.CHEST, Vector2i(5, 4)):
		_cleanup(world)
		return { "ok": false, "message": "chest placement failed" }
	# (5, 6) = empty (no overlay, no building)

	var hpanel = preload("res://scripts/ui/harvester_panel.gd").new()
	parent.add_child(hpanel)
	hpanel.cursor = cursor
	hpanel.inventory = inv
	hpanel.toast_callback = func(_msg): pass
	hpanel.open(world.building_at(Vector2i(5, 5)), world)

	# Verify coverage states.
	_check(failures, hpanel._coverage_status_for(Vector2i(4, 5)) == hpanel.COV_RIPE,
		"(4,5) should be RIPE planter")
	_check(failures, hpanel._coverage_status_for(Vector2i(6, 5)) == hpanel.COV_GROWING,
		"(6,5) should be GROWING planter")
	_check(failures, hpanel._coverage_status_for(Vector2i(5, 4)) == hpanel.COV_EMPTY,
		"(5,4) should be EMPTY (chest is not a planter)")
	_check(failures, hpanel._coverage_status_for(Vector2i(5, 6)) == hpanel.COV_EMPTY,
		"(5,6) should be EMPTY (no building)")

	hpanel.queue_free()
	_disconnect(world); world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all session 4 invariants hold; multi-session UI arc COMPLETE" }
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

static func _cleanup(world) -> void:
	_disconnect(world)
	if world != null: world.queue_free()
