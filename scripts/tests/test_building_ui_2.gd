extends RefCounted

## Building Interaction UI Session 2 tests (session-building-ui-2).
##
## Covers the architectural pieces shipped this session:
##   1. slot_layout entries for chest, mill, oven, proofer, packager, mixer
##      (correct shapes, kinds, accepts lists)
##   2. ChestPanel drag-drop semantics (pick from bag, drop into bag,
##      capacity check, swap)
##   3. Multi-input dispatch (oven: 2 input slots, both writing to
##      in_buffer; different accepts per slot; cross-type buffer coexistence)
##   4. Mixer's fluid_indicator slot kind (read-only, not click-target,
##      no state_field)
##   5. E-key adjacent-interactable scan (4-direction including own tile)
##   6. SlotWidget.chest_bag_to_slot_views relocation (test it works as
##      a public helper from new home)

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "building UI session 2 (chest panel + multi-input + mixer fluid + E-key scan)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. slot_layout shapes ----------
	# Chest: single "chest_bag" entry.
	var chest_layout: Array = Buildings.slot_layout_for(Buildings.Type.CHEST)
	_check(failures, chest_layout.size() == 1, "chest slot_layout size: expected 1, got %d" % chest_layout.size())
	if not chest_layout.is_empty():
		_check(failures, str(chest_layout[0]["kind"]) == "chest_bag", "chest slot kind: expected 'chest_bag'")
		_check(failures, int(chest_layout[0]["max_stack"]) == 2400, "chest max_stack should be 2400 (TOTAL_CAPACITY)")
	_check(failures, Buildings.has_interaction_ui(Buildings.Type.CHEST), "chest has_interaction_ui should be true")

	# Mill: input GRAIN → output FLOUR, no fuel.
	var mill_layout: Array = Buildings.slot_layout_for(Buildings.Type.MILL)
	_check(failures, mill_layout.size() == 2, "mill slot_layout size: expected 2 (input+output)")
	if mill_layout.size() == 2:
		_check(failures, Items.Type.GRAIN in mill_layout[0]["accepts"], "mill input should accept GRAIN")
		_check(failures, Items.Type.FLOUR in mill_layout[1]["accepts"], "mill output should produce FLOUR")

	# Oven: 2 input slots (both kind=input), 1 output. Both inputs write to
	# in_buffer (multi-type bag).
	var oven_layout: Array = Buildings.slot_layout_for(Buildings.Type.OVEN)
	_check(failures, oven_layout.size() == 3, "oven slot_layout size: expected 3 (2 inputs + output)")
	var oven_input_count: int = 0
	for s in oven_layout:
		if str(s.get("kind", "")) == "input":
			oven_input_count += 1
			_check(failures, str(s.get("state_field", "")) == "in_buffer",
				"oven input state_field: expected 'in_buffer', got '%s'" % str(s.get("state_field", "")))
	_check(failures, oven_input_count == 2, "oven should have 2 input slots; got %d" % oven_input_count)
	# Each input slot has a distinct accepts list.
	var dough_slot: Dictionary = {}
	var fuel_slot: Dictionary = {}
	for s in oven_layout:
		if str(s.get("kind", "")) == "input":
			if Items.Type.RISEN_DOUGH in s.get("accepts", []):
				dough_slot = s
			elif Items.Type.FUEL_BRIQUETTE in s.get("accepts", []):
				fuel_slot = s
	_check(failures, not dough_slot.is_empty(), "oven should have a slot accepting RISEN_DOUGH")
	_check(failures, not fuel_slot.is_empty(), "oven should have a slot accepting FUEL_BRIQUETTE")

	# Mixer: 2 inputs (flour + yeast) + fluid_indicator + output.
	var mixer_layout: Array = Buildings.slot_layout_for(Buildings.Type.MIXER)
	_check(failures, mixer_layout.size() == 4, "mixer slot_layout size: expected 4")
	var mixer_kinds: Array = []
	for s in mixer_layout:
		mixer_kinds.append(str(s["kind"]))
	_check(failures, "fluid_indicator" in mixer_kinds, "mixer should have a fluid_indicator slot")
	# fluid_indicator has no state_field (display-only, not click-target).
	for s in mixer_layout:
		if str(s["kind"]) == "fluid_indicator":
			_check(failures, not s.has("state_field"),
				"fluid_indicator slot should NOT have state_field (display-only)")
			_check(failures, int(s.get("fluid_type", -1)) == Fluids.Type.WATER,
				"mixer fluid_indicator should specify Fluids.Type.WATER")

	# Proofer + Packager are simple Processor shape.
	var proofer_layout: Array = Buildings.slot_layout_for(Buildings.Type.PROOFER)
	_check(failures, proofer_layout.size() == 2, "proofer slot_layout size: expected 2 (input+output)")
	var packager_layout: Array = Buildings.slot_layout_for(Buildings.Type.PACKAGER)
	_check(failures, packager_layout.size() == 2, "packager slot_layout size: expected 2 (input+output)")

	# ---------- 2. ChestPanel drag-drop ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.CHEST, Vector2i(0, 0)):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "chest placement failed" }
	var chest: Building = world.building_at(Vector2i(0, 0))

	# Pre-load chest with content via Chest._bag_add (mirrors gameplay where
	# upstream belt fed items in).
	Chest._bag_add(chest.state["bag"], Items.Type.WHEAT, 50)
	Chest._bag_add(chest.state["bag"], Items.Type.FLOUR, 30)

	# Verify SlotWidget.chest_bag_to_slot_views works from its new home.
	var views: Array = SlotWidget.chest_bag_to_slot_views(chest.state["bag"])
	# 50 wheat (max_stack 100) → 1 view of 50; 30 flour (max_stack 100) → 1 view of 30.
	_check(failures, views.size() == 2, "bag_to_slot_views: expected 2 views, got %d" % views.size())

	# Instantiate ChestPanel and run its click handlers directly.
	var panel = preload("res://scripts/ui/chest_panel.gd").new()
	parent.add_child(panel)
	var inv := Inventory.new(8)
	var cursor := CursorStack.new()
	panel.cursor = cursor
	panel.inventory = inv
	panel.toast_callback = func(_msg): pass
	panel.open(chest, world)

	# Click chest slot 0 with empty cursor → cursor picks up first view (wheat ×50).
	panel._handle_chest_slot_click(0, SlotClickHandler.MOD_NONE)
	_check(failures, cursor.has_item() and cursor.item_type == Items.Type.WHEAT and cursor.count == 50,
		"chest pick: cursor should hold wheat ×50, got %s ×%d" % [Items.name_of(cursor.item_type), cursor.count])
	# Bag now has only flour.
	_check(failures, Chest._bag_count(chest.state["bag"], Items.Type.WHEAT) == 0, "wheat should be gone from bag")
	_check(failures, Chest._bag_count(chest.state["bag"], Items.Type.FLOUR) == 30, "flour should remain in bag")

	# Click chest empty slot with cursor full → drop wheat back into bag.
	# (slot index 1 — past the last view (flour) is empty.)
	panel._handle_chest_slot_click(2, SlotClickHandler.MOD_NONE)
	_check(failures, not cursor.has_item(), "after drop: cursor should be empty")
	_check(failures, Chest._bag_count(chest.state["bag"], Items.Type.WHEAT) == 50, "wheat back in bag (50)")

	# Capacity check: load chest near cap, try to drop more than free.
	# Chest TOTAL_CAPACITY = 2400. We have 50+30 = 80, so free = 2320.
	# Cursor with 3000 items would exceed. Test this.
	cursor.pick(Items.Type.IRON_ORE, 3000)
	var toasted: Array = []
	panel.toast_callback = func(msg): toasted.append(msg)
	panel._handle_chest_slot_click(2, SlotClickHandler.MOD_NONE)
	_check(failures, cursor.has_item() and cursor.count == 3000,
		"over-capacity drop: cursor should still hold all 3000")
	_check(failures, toasted.size() == 1 and "full" in str(toasted[0]).to_lower(),
		"over-capacity drop: should toast 'full'")

	cursor.clear()
	panel.queue_free()

	# ---------- 3. Multi-input dispatch (oven: drop into specific input slot) ----------
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for dx in 2:
		for dy in 2:
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.OVEN, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "oven placement failed: %s" % world.last_building_place_error }
	var oven: Building = world.building_at(Vector2i(0, 0))

	# BuildingPanel base used here (oven_panel just extends ProcessorPanel
	# which extends BuildingPanel — drag-drop comes from base).
	var bpanel = preload("res://scripts/ui/processor_panel.gd").new()
	parent.add_child(bpanel)
	bpanel.cursor = cursor
	bpanel.inventory = inv
	bpanel.toast_callback = func(_msg): pass
	bpanel.open(oven, world)

	# Drop RISEN_DOUGH into the dough slot.
	cursor.pick(Items.Type.RISEN_DOUGH, 3)
	bpanel._drop_into_slot(dough_slot, -1, SlotClickHandler.MOD_NONE)
	_check(failures, BuildingPanel._buffer_count(oven.state["in_buffer"], Items.Type.RISEN_DOUGH) == 3,
		"dough slot drop: in_buffer should have 3 RISEN_DOUGH")

	# Drop FUEL_BRIQUETTE into the fuel-briquette input slot. Both write to
	# same in_buffer (multi-type bag); they coexist.
	cursor.pick(Items.Type.FUEL_BRIQUETTE, 2)
	bpanel._drop_into_slot(fuel_slot, -1, SlotClickHandler.MOD_NONE)
	_check(failures, BuildingPanel._buffer_count(oven.state["in_buffer"], Items.Type.FUEL_BRIQUETTE) == 2,
		"briquette slot drop: in_buffer should have 2 FUEL_BRIQUETTE")
	_check(failures, BuildingPanel._buffer_count(oven.state["in_buffer"], Items.Type.RISEN_DOUGH) == 3,
		"briquette drop should not disturb RISEN_DOUGH count (still 3)")

	# Reject wrong-type into the fuel input slot — drop WHEAT into the slot
	# that accepts only FUEL_BRIQUETTE.
	cursor.pick(Items.Type.WHEAT, 5)
	var oven_toasts: Array = []
	bpanel.toast_callback = func(msg): oven_toasts.append(msg)
	bpanel._drop_into_slot(fuel_slot, -1, SlotClickHandler.MOD_NONE)
	_check(failures, cursor.has_item() and cursor.count == 5,
		"wrong-type drop: cursor should still have WHEAT ×5")
	_check(failures, oven_toasts.size() == 1 and "accepts" in str(oven_toasts[0]).to_lower(),
		"wrong-type drop: should toast 'accepts' list")
	cursor.clear()
	bpanel.queue_free()

	# ---------- 4. E-key adjacent scan (4-direction + own tile) ----------
	# Place a chest at (5, 5). Player at (5, 6) → adjacent → should find it.
	world.set_overlay(Vector2i(5, 5), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.CHEST, Vector2i(5, 5)):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "second chest placement failed" }
	# Static helper logic: replicate _find_adjacent_interactable here for test.
	var adjacent: Array = [
		Vector2i(5, 6), Vector2i(5, 4), Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 5),
	]
	for cell in adjacent:
		_check(failures, _find_first_interactable(world, cell) != null,
			"player at %s should find chest at (5,5)" % str(cell))
	# 2 tiles away → no find.
	_check(failures, _find_first_interactable(world, Vector2i(7, 5)) == null,
		"player at (7,5) (Manhattan 2) should NOT find chest")

	_disconnect(world); world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all session 2 panel invariants hold" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Mirror of main.gd::_find_adjacent_interactable for unit testing without
## main.gd. Scan 4-adjacent cells (including own tile) for first building
## with has_interaction_ui registered.
static func _find_first_interactable(world, player_tile: Vector2i):
	var scan: Array = [
		player_tile,
		player_tile + Vector2i(1, 0),
		player_tile + Vector2i(-1, 0),
		player_tile + Vector2i(0, 1),
		player_tile + Vector2i(0, -1),
	]
	for cell in scan:
		if world.has_building_at(cell):
			var b: Building = world.building_at(cell)
			if b != null and Buildings.has_interaction_ui(b.type):
				return b
	return null

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
