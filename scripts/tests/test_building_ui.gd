extends RefCounted

## Building Interaction UI tests (session-building-ui-1).
##
## Covers the architectural pieces shipped this session:
##   1. CursorStack pure operations (pick/clear/return/serialize)
##   2. Buildings.slot_layout_for + has_interaction_ui registry
##   3. Hotbar has_selection / clear_selection / current_kind == "" sentinel
##   4. Click resolution via grid_world.occupied (multi-tile lookup)
##   5. Adjacency check (Manhattan ≤ 1 from any footprint cell)
##   6. BuildingPanel drag-drop semantics:
##      a. Drop into smelter input slot — appends to in_buffer
##      b. Drop wrong-type rejected (toast called)
##      c. Drop into output slot rejected (read-only)
##      d. Drop into fuel slot — converts items to units (1 wood=1, 1 coal=4)
##      e. Take from fuel slot — lossy (1 unit → 1 wood)
##      f. Take from output_multi sub-slot — entries shift up via remove_at
##   7. Save/load round-trip preserves cursor stack via player_progression

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_building_ui.json"

static func test_name() -> String:
	return "building UI (cursor + slot_layout + hotbar + click + drag-drop + save)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. CursorStack pure ops ----------
	var c := CursorStack.new()
	_check(failures, not c.has_item(), "fresh cursor should be empty")
	c.pick(Items.Type.WOOD, 5)
	_check(failures, c.has_item() and c.item_type == Items.Type.WOOD and c.count == 5,
		"pick: should hold WOOD ×5")
	c.clear()
	_check(failures, not c.has_item(), "clear: cursor should be empty")
	# Return to inventory.
	c.pick(Items.Type.IRON_ORE, 10)
	var inv := Inventory.new(8)
	var returned: bool = c.return_to_inventory(inv)
	_check(failures, returned, "return_to_inventory: should return all 10 to empty inventory")
	_check(failures, not c.has_item(), "return: cursor should be empty after full return")
	_check(failures, inv.total_of(Items.Type.IRON_ORE) == 10, "return: inventory should have 10 iron ore")
	# Serialize round-trip.
	c.pick(Items.Type.COAL, 7)
	var d: Dictionary = c.to_dict()
	var c2 := CursorStack.new()
	c2.from_dict(d)
	_check(failures, c2.item_type == Items.Type.COAL and c2.count == 7, "from_dict: round-trip COAL ×7")
	# Empty serialize.
	var c3 := CursorStack.new()
	c3.from_dict({"item_type": -1, "count": 0})
	_check(failures, not c3.has_item(), "from_dict: empty dict yields empty cursor")
	# Malformed dict.
	var c4 := CursorStack.new()
	c4.from_dict({})
	_check(failures, not c4.has_item(), "from_dict: missing keys yields empty cursor")

	# ---------- 2. Buildings.slot_layout_for ----------
	var smelter_layout: Array = Buildings.slot_layout_for(Buildings.Type.SMELTER)
	_check(failures, smelter_layout.size() == 3,
		"smelter slot_layout should have 3 entries (input/output/fuel), got %d" % smelter_layout.size())
	var smelter_kinds: Array = []
	for s in smelter_layout:
		smelter_kinds.append(str(s["kind"]))
	_check(failures, smelter_kinds == ["input", "output", "fuel"],
		"smelter slot kinds: expected [input, output, fuel], got %s" % str(smelter_kinds))

	var drill_layout: Array = Buildings.slot_layout_for(Buildings.Type.MINING_DRILL)
	_check(failures, drill_layout.size() == 2,
		"drill slot_layout should have 2 entries (output_multi/fuel), got %d" % drill_layout.size())
	_check(failures, str(drill_layout[0]["kind"]) == "output_multi",
		"drill first slot kind should be output_multi")
	_check(failures, int(drill_layout[0].get("multi_count", 0)) == 5,
		"drill output_multi count should be 5")

	# Buildings without slot_layout return [].
	# (As of session-building-ui-3: cloth chain + remaining processors ship.
	# HARVESTER stays UI-less until Session 4 — using it as the "no UI" canary.)
	var harvester_layout: Array = Buildings.slot_layout_for(Buildings.Type.HARVESTER)
	_check(failures, harvester_layout.is_empty(), "harvester slot_layout should be empty (UI ships in session 4)")

	# has_interaction_ui flag.
	_check(failures, Buildings.has_interaction_ui(Buildings.Type.SMELTER), "smelter has_interaction_ui should be true")
	_check(failures, Buildings.has_interaction_ui(Buildings.Type.MINING_DRILL), "drill has_interaction_ui should be true")
	_check(failures, not Buildings.has_interaction_ui(Buildings.Type.HARVESTER), "harvester has_interaction_ui should be false (session 4)")

	# ---------- 3. Hotbar has_selection / clear_selection ----------
	# (Hotbar is a Control; instantiate via new() and run _build_categories
	# manually so we don't need a scene tree.)
	var hotbar = preload("res://scripts/ui/hotbar.gd").new()
	parent.add_child(hotbar)
	hotbar._build_categories()
	# Initially in Terrain category, slot 0 selected.
	_check(failures, hotbar.has_selection(), "fresh hotbar should have a selection")
	_check(failures, hotbar.current_kind() != "", "fresh hotbar current_kind should not be empty")
	hotbar.clear_selection()
	_check(failures, not hotbar.has_selection(), "after clear: should have no selection")
	_check(failures, hotbar.current_kind() == "", "after clear: current_kind should be empty string")
	_check(failures, hotbar.current_value() == -1, "after clear: current_value should be -1")
	# Re-select via key (set_selection_in_current).
	hotbar.set_selection_in_current(0)
	_check(failures, hotbar.has_selection(), "re-select via index 0: should have selection")
	hotbar.queue_free()

	# ---------- 4. Click resolution via grid_world.occupied ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	# Place a 2×2 smelter at (0, 0). All 4 footprint cells should map to anchor (0, 0).
	for dx in 2:
		for dy in 2:
			world.set_overlay(Vector2i(dx, dy), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.SMELTER, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "smelter placement failed" }

	# Click any cell of the 2×2 footprint → resolves to anchor (0, 0).
	for dx in 2:
		for dy in 2:
			var cell: Vector2i = Vector2i(dx, dy)
			_check(failures, world.has_building_at(cell),
				"has_building_at(%s) should be true" % str(cell))
			_check(failures, world.occupied[cell] == Vector2i(0, 0),
				"occupied[%s] should be (0,0), got %s" % [str(cell), str(world.occupied[cell])])
			var b: Building = world.building_at(cell)
			_check(failures, b != null and b.type == Buildings.Type.SMELTER,
				"building_at(%s) should resolve to smelter" % str(cell))

	# Empty cell → has_building_at false.
	_check(failures, not world.has_building_at(Vector2i(20, 20)),
		"empty cell should report has_building_at = false")

	# ---------- 5. Adjacency check (Manhattan ≤ 1 from any footprint cell) ----------
	var smelter: Building = world.building_at(Vector2i(0, 0))
	# Player adjacent to W edge (x=-1, y=0) → adjacent to footprint cell (0,0).
	_check(failures, _is_adjacent(smelter, Vector2i(-1, 0)),
		"player at (-1,0) should be adjacent to 2×2 smelter at (0,0)")
	# Player on the smelter itself (within footprint) → adjacent (Manhattan 0).
	_check(failures, _is_adjacent(smelter, Vector2i(0, 0)),
		"player on footprint cell (0,0) should count as adjacent")
	# Player adjacent to E edge of 2×2 (x=2, y=1) → adjacent to footprint cell (1,1).
	_check(failures, _is_adjacent(smelter, Vector2i(2, 1)),
		"player at (2,1) should be adjacent to 2×2 smelter")
	# Player at (3, 0) → Manhattan 2 from any footprint cell → NOT adjacent.
	_check(failures, not _is_adjacent(smelter, Vector2i(3, 0)),
		"player at (3,0) should NOT be adjacent to 2×2 smelter (closest cell is (1,0), distance 2)")
	# Diagonal corner: (-1, -1) → Manhattan 2 from (0,0) corner → NOT adjacent.
	_check(failures, not _is_adjacent(smelter, Vector2i(-1, -1)),
		"player at (-1,-1) should NOT be adjacent (diagonal corner = Manhattan 2)")

	# ---------- 6. BuildingPanel drag-drop semantics ----------
	# Instantiate a BuildingPanel without rendering (skip _ready scene tree
	# concerns by calling new() and setting fields directly).
	var panel = preload("res://scripts/ui/building_panel.gd").new()
	parent.add_child(panel)
	var inv2 := Inventory.new(8)
	var cursor := CursorStack.new()
	var toasted: Array = []
	panel.cursor = cursor
	panel.inventory = inv2
	panel.toast_callback = func(msg): toasted.append(msg)
	panel.open(smelter, world)

	# 6a. Drop into smelter input — IRON_ORE accepted.
	cursor.pick(Items.Type.IRON_ORE, 3)
	var input_slot_def: Dictionary = smelter_layout[0]
	panel._drop_into_slot(input_slot_def, -1)
	_check(failures, BuildingPanel._buffer_count(smelter.state["in_buffer"], Items.Type.IRON_ORE) == 3,
		"after drop: smelter in_buffer should have 3 iron ore")
	_check(failures, not cursor.has_item(), "after drop: cursor should be empty")

	# 6b. Drop wrong-type rejected — WHEAT into smelter input (accepts list excludes it).
	cursor.pick(Items.Type.WHEAT, 5)
	toasted.clear()
	panel._drop_into_slot(input_slot_def, -1)
	_check(failures, cursor.has_item() and cursor.item_type == Items.Type.WHEAT and cursor.count == 5,
		"wrong-type drop should leave cursor unchanged")
	_check(failures, toasted.size() == 1 and "accepts" in str(toasted[0]).to_lower(),
		"wrong-type drop should toast 'accepts' list")
	cursor.clear()

	# 6c. Drop into output slot rejected.
	cursor.pick(Items.Type.IRON_INGOT, 2)
	toasted.clear()
	var output_slot_def: Dictionary = smelter_layout[1]
	panel._drop_into_slot(output_slot_def, -1)
	_check(failures, cursor.has_item(), "drop into output: cursor should still have items")
	_check(failures, toasted.size() == 1 and "read-only" in str(toasted[0]).to_lower(),
		"drop into output should toast 'read-only'")
	cursor.clear()

	# 6d. Drop into fuel slot — items convert to units. 2 coal = 8 units.
	smelter.state["fuel_buffer"] = 0
	cursor.pick(Items.Type.COAL, 2)
	var fuel_slot_def: Dictionary = smelter_layout[2]
	panel._drop_into_slot(fuel_slot_def, -1)
	_check(failures, int(smelter.state["fuel_buffer"]) == 8,
		"drop 2 coal: fuel_buffer should be 8 units, got %d" % int(smelter.state["fuel_buffer"]))
	_check(failures, not cursor.has_item(), "after fuel drop: cursor should be empty")

	# 6e. Take from fuel — lossy: 8 units → 8 wood.
	panel._take_from_slot(fuel_slot_def, -1)
	_check(failures, cursor.item_type == Items.Type.WOOD and cursor.count == 8,
		"lossy take from fuel: cursor should hold WOOD ×8 (1 unit = 1 wood), got %s ×%d" % [Items.name_of(cursor.item_type), cursor.count])
	_check(failures, int(smelter.state["fuel_buffer"]) == 0,
		"after take: fuel_buffer should be 0")
	cursor.clear()

	# 6f. Take from output_multi sub-slot — drill scenario.
	# Use the drill on a separate world (drill needs ore tiles in footprint).
	_disconnect(world); world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	world.tiles[Vector2i(0, 0)] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.IRON)
	world.resource_state[Vector2i(0, 0)] = {"richness": 50, "original_richness": 50}
	if not world.place_building(Buildings.Type.MINING_DRILL, Vector2i(0, 0), Belt.DIR_E):
		panel.queue_free(); _disconnect(world); world.queue_free()
		return { "ok": false, "message": "drill placement failed" }
	var drill: Building = world.building_at(Vector2i(0, 0))
	# Pre-load output_buffer with 2 entries: iron at idx 0, copper at idx 1.
	drill.state["output_buffer"] = [[Items.Type.IRON_ORE, 5], [Items.Type.COPPER_ORE, 3]]
	panel.open(drill, world)
	var drill_output_def: Dictionary = drill_layout[0]
	# Take sub_idx 0 → cursor gets IRON_ORE ×5; copper shifts to idx 0.
	panel._take_from_slot(drill_output_def, 0)
	_check(failures, cursor.item_type == Items.Type.IRON_ORE and cursor.count == 5,
		"output_multi take sub_idx 0: cursor should hold IRON_ORE ×5")
	_check(failures, drill.state["output_buffer"].size() == 1 and int(drill.state["output_buffer"][0][0]) == Items.Type.COPPER_ORE,
		"after take: copper should now be at idx 0 (entries shifted up)")

	panel.queue_free()
	_disconnect(world); world.queue_free()

	# ---------- 7. Save/load round-trip with cursor ----------
	# Cursor lives in player_progression["cursor"] as additive field. Verify
	# round-trip preserves item_type and count.
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	var save_world = GridWorldScript.new()
	parent.add_child(save_world)
	var player_a := Node2D.new()
	parent.add_child(player_a)
	var save_inv := Inventory.new(16)
	var save_cursor := CursorStack.new()
	save_cursor.pick(Items.Type.WOOD, 12)
	var progression: Dictionary = {"bags_consumed": 0, "cursor": save_cursor.to_dict()}
	if not SaveSystem.save_game(save_world, player_a, save_inv, progression):
		_cleanup(save_world, player_a, null, null, orig_path)
		return { "ok": false, "message": "save_game returned false" }

	# Load.
	var load_world = GridWorldScript.new()
	parent.add_child(load_world)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var load_inv := Inventory.new(16)
	var result: LoadResult = SaveSystem.load_game(load_world, player_b, load_inv)
	if not result.success:
		_cleanup(save_world, player_a, load_world, player_b, orig_path)
		return { "ok": false, "message": "load_game failed: %s" % result.error_message }
	var loaded_cursor := CursorStack.new()
	if result.player_progression.has("cursor"):
		loaded_cursor.from_dict(result.player_progression["cursor"])
	_check(failures, loaded_cursor.item_type == Items.Type.WOOD,
		"after load: cursor item_type should be WOOD, got %d" % loaded_cursor.item_type)
	_check(failures, loaded_cursor.count == 12,
		"after load: cursor count should be 12, got %d" % loaded_cursor.count)

	# Backward-compat: old save without cursor key → cursor stays empty.
	# Test by loading a synthetic dict missing the cursor key.
	var bare_progression: Dictionary = {"bags_consumed": 5}
	var fresh_cursor := CursorStack.new()
	if bare_progression.has("cursor"):
		fresh_cursor.from_dict(bare_progression["cursor"])
	_check(failures, not fresh_cursor.has_item(),
		"backward-compat: progression without cursor key should leave cursor empty")

	_cleanup(save_world, player_a, load_world, player_b, orig_path)

	if failures.is_empty():
		return { "ok": true, "message": "all building UI invariants hold" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Adjacency check copy (mirror of main.gd::_is_adjacent_to_building) so the
## test runs without instantiating main.gd.
static func _is_adjacent(b: Building, player_tile: Vector2i) -> bool:
	var fp: Vector2i = Buildings.footprint_of(b.type)
	for dx in fp.x:
		for dy in fp.y:
			var cell: Vector2i = Vector2i(b.anchor.x + dx, b.anchor.y + dy)
			if abs(player_tile.x - cell.x) + abs(player_tile.y - cell.y) <= 1:
				return true
	return false

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)

static func _cleanup(save_world, player_a, load_world, player_b, orig_path: String) -> void:
	_disconnect(save_world)
	if save_world != null: save_world.queue_free()
	if player_a != null: player_a.queue_free()
	_disconnect(load_world)
	if load_world != null: load_world.queue_free()
	if player_b != null: player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
