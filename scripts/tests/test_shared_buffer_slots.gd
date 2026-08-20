extends RefCounted

## DIAGNOSTIC RED REPRO — shared-buffer slot addressing (audit #8/#9).
##
## Three buildings bind TWO panel slots to ONE state_field:
##   MIXER    input_flour  + input_yeast  → "in_buffer"
##   OVEN     input_dough  + input_fuel   → "in_buffer"
##   THRESHER output_grain + output_straw → "out_buffer"
##
## Every `input`/`output` arm in building_panel.gd addresses such a buffer
## as `buf[0]` and empties it with `buf.clear()`, so the panel cannot tell
## the two slots apart. The adjacent `output_multi` arms in the SAME
## functions do it correctly via `buf[sub_idx]` / `remove_at(sub_idx)` —
## see the diagnostic report.
##
## This suite is written to FAIL on current code. Each sub-case asserts the
## behavior a player expects; the failure messages state what actually
## happens today.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const BuildingPanelScript = preload("res://scripts/ui/building_panel.gd")

static func test_name() -> String:
	return "shared-buffer slots (Mixer/Oven/Thresher: one field, two slots)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 12):
		for y in range(0, 8):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)

	var panel = BuildingPanelScript.new()
	parent.add_child(panel)
	var cursor := CursorStack.new()
	panel.cursor = cursor
	panel.inventory = Inventory.new(8)
	panel.toast_callback = func(_msg): pass

	# =========================================================================
	# (1) THRESHER — out_buffer naturally holds GRAIN + STRAW (recipe emits
	# both). Clicking the Straw slot must yield STRAW and leave GRAIN alone.
	# =========================================================================
	if not world.place_building(Buildings.Type.THRESHER, Vector2i(1, 1), Belt.DIR_E):
		_teardown(world, panel)
		return { "ok": false, "message": "setup: thresher placement failed: %s" % world.last_building_place_error }
	var thresher: Building = world.building_at(Vector2i(1, 1))
	thresher.state["out_buffer"] = [[Items.Type.GRAIN, 3], [Items.Type.STRAW, 2]]
	panel.open(thresher, world)

	var straw_slot: Dictionary = _slot_by_id(Buildings.Type.THRESHER, "output_straw")
	_check(failures, not straw_slot.is_empty(), "(1) setup: thresher output_straw slot_def not found")
	panel._take_from_slot(straw_slot, -1)

	_check(failures, cursor.has_item() and cursor.item_type == Items.Type.STRAW,
		"(1) clicking the STRAW slot must yield STRAW, got %s (today: yields buf[0] = GRAIN)"
			% (Items.name_of(cursor.item_type) if cursor.has_item() else "nothing"))
	_check(failures, cursor.has_item() and cursor.count == 2,
		"(1) should take all 2 straw, got %d" % (cursor.count if cursor.has_item() else 0))
	_check(failures, _buf_count(thresher.state.get("out_buffer", []), Items.Type.GRAIN) == 3,
		"(1) ITEM DESTRUCTION: the 3 GRAIN must survive a straw take, %d left (today: buf.clear() wipes them)"
			% _buf_count(thresher.state.get("out_buffer", []), Items.Type.GRAIN))
	cursor.clear()
	panel.close()

	# =========================================================================
	# (2) MIXER — in_buffer holds FLOUR + YEAST. Clicking Yeast must yield
	# YEAST and leave FLOUR alone.
	# =========================================================================
	if not world.place_building(Buildings.Type.MIXER, Vector2i(4, 1), Belt.DIR_E):
		_teardown(world, panel)
		return { "ok": false, "message": "setup: mixer placement failed: %s" % world.last_building_place_error }
	var mixer: Building = world.building_at(Vector2i(4, 1))
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 2], [Items.Type.YEAST, 3]]
	panel.open(mixer, world)

	var yeast_slot: Dictionary = _slot_by_id(Buildings.Type.MIXER, "input_yeast")
	var flour_slot: Dictionary = _slot_by_id(Buildings.Type.MIXER, "input_flour")
	_check(failures, not yeast_slot.is_empty() and not flour_slot.is_empty(),
		"(2) setup: mixer input slot_defs not found")
	panel._take_from_slot(yeast_slot, -1)

	_check(failures, cursor.has_item() and cursor.item_type == Items.Type.YEAST,
		"(2) clicking the YEAST slot must yield YEAST, got %s (today: yields buf[0] = FLOUR)"
			% (Items.name_of(cursor.item_type) if cursor.has_item() else "nothing"))
	_check(failures, _buf_count(mixer.state.get("in_buffer", []), Items.Type.FLOUR) == 2,
		"(2) ITEM DESTRUCTION: the 2 FLOUR must survive a yeast take, %d left"
			% _buf_count(mixer.state.get("in_buffer", []), Items.Type.FLOUR))
	cursor.clear()

	# =========================================================================
	# (3) NO-OP — a slot whose item type is absent from the shared buffer
	# must take nothing (never a sibling's item).
	# =========================================================================
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 2]]
	panel._take_from_slot(yeast_slot, -1)
	_check(failures, not cursor.has_item(),
		"(3) YEAST slot with only FLOUR buffered must be a NO-OP, cursor got %s"
			% (Items.name_of(cursor.item_type) if cursor.has_item() else "nothing"))
	_check(failures, _buf_count(mixer.state.get("in_buffer", []), Items.Type.FLOUR) == 2,
		"(3) the flour must be untouched by that no-op, %d left"
			% _buf_count(mixer.state.get("in_buffer", []), Items.Type.FLOUR))
	cursor.clear()

	# =========================================================================
	# (4) DISPLAY / TOOLTIP — _hover_item_type resolves what the player sees.
	# Hovering the Yeast slot must report YEAST, not buf[0]. (Cluster B's
	# tooltip helper inherited the same buf[0] lookup as the renderer.)
	# =========================================================================
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 2], [Items.Type.YEAST, 3]]
	var hover_yeast: int = panel._hover_item_type({ "slot_def": yeast_slot, "sub_idx": -1 })
	var hover_flour: int = panel._hover_item_type({ "slot_def": flour_slot, "sub_idx": -1 })
	_check(failures, hover_yeast == Items.Type.YEAST,
		"(4) tooltip over the YEAST slot must say YEAST, says %s" % Items.name_of(hover_yeast))
	_check(failures, hover_flour == Items.Type.FLOUR,
		"(4) tooltip over the FLOUR slot must say FLOUR, says %s" % Items.name_of(hover_flour))
	# A slot whose type isn't buffered should read empty, not a sibling's item.
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 2]]
	var hover_absent: int = panel._hover_item_type({ "slot_def": yeast_slot, "sub_idx": -1 })
	_check(failures, hover_absent == -1,
		"(4) tooltip over an empty YEAST slot must read empty (-1), says %s" % Items.name_of(hover_absent))

	# =========================================================================
	# (5) CTRL-PICKER PATH — _input_output_ctrl_take is a SECOND copy of the
	# same buf[0]/clear() logic (Cluster A). Taking a slot's full count must
	# not wipe the sibling entry.
	# =========================================================================
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, 2], [Items.Type.YEAST, 3]]
	panel._input_output_ctrl_take(flour_slot, "in_buffer", -1, 2, "input")
	_check(failures, _buf_count(mixer.state.get("in_buffer", []), Items.Type.YEAST) == 3,
		"(5) ITEM DESTRUCTION (ctrl path): taking all FLOUR must leave 3 YEAST, %d left"
			% _buf_count(mixer.state.get("in_buffer", []), Items.Type.YEAST))
	cursor.clear()
	panel.close()

	_teardown(world, panel)

	if failures.is_empty():
		return { "ok": true, "message": "shared-buffer slots address their own entry (take, no-op, tooltip, ctrl path)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

static func _slot_by_id(b_type: int, slot_id: String) -> Dictionary:
	for slot in Buildings.slot_layout_for(b_type):
		if str(slot.get("id", "")) == slot_id:
			return slot
	return {}

static func _buf_count(buf: Array, item_type: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _teardown(world, panel) -> void:
	if panel != null:
		panel.queue_free()
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
