extends RefCounted

## Tree harvest lifecycle test.
##
## Locks in the manual-tree-harvesting mechanics shipped at session-tree-harvest:
##   1. chop_tree(pos): tile.resource_node becomes NONE, regrowth_remaining set,
##      tile_modifications and resource_state_modifications recorded.
##   2. _tick_regrowth (driven by GridWorld._process via delta): regrowth_remaining
##      decrements per-tick. At 0, tree restored: tile.resource_node back to TREE,
##      resource_state[pos] erased, tile_modifications erased.
##   3. v14 save round-trip mid-regrowth: regrowth_remaining persists; on load,
##      tile is empty (NONE), resource_state has the timer, _tick_regrowth
##      resumes from saved value.
##   4. Overlay placement on a regrowing tile cancels the regrowth (player committed).
##   5. WOOD item exists with expected properties.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const WorldGenScript  = preload("res://scripts/world/world_generator.gd")
const TEST_SAVE_PATH: String = "user://test_tree_harvest.json"
const TEST_SEED: int = 42

static func test_name() -> String:
	return "tree harvest lifecycle (chop, regrowth tick, save mid-regrowth, overlay-cancels-regrowth)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# (6) Wood yield varies per tree (1-4) with most trees yielding 1-2.
	# Sample 1000 positions to verify the distribution.
	var yield_counts: Array = [0, 0, 0, 0, 0]   # index 1-4 used
	for i in 1000:
		var sample_pos := Vector2i(i % 50 - 25, i / 50 - 10)
		var y: int = GridWorldScript.wood_yield_for_tree(sample_pos)
		if y < 1 or y > 4:
			failures.append("wood_yield_for_tree returned %d (expected 1..4) at %s" % [y, str(sample_pos)])
			break
		yield_counts[y] += 1
	# Distribution sanity: yield 1 should be most common; yield 4 should be rare.
	if yield_counts[1] < 400:
		failures.append("yield distribution skewed: yield=1 count %d (expected ≥400 of 1000)" % yield_counts[1])
	if yield_counts[4] > 100:
		failures.append("yield distribution skewed: yield=4 count %d (expected ≤100 of 1000, large trees rare)" % yield_counts[4])
	# Determinism: same position → same yield.
	var det_pos := Vector2i(7, 13)
	var y1: int = GridWorldScript.wood_yield_for_tree(det_pos)
	var y2: int = GridWorldScript.wood_yield_for_tree(det_pos)
	if y1 != y2:
		failures.append("wood_yield_for_tree not deterministic: same pos returned %d then %d" % [y1, y2])

	# (5) WOOD item exists.
	if not Items.DATA.has(Items.Type.WOOD):
		return { "ok": false, "message": "Items.Type.WOOD missing from registry" }
	var wood_data: Dictionary = Items.DATA[Items.Type.WOOD]
	if int(wood_data.get("max_stack", 0)) != 200:
		failures.append("WOOD max_stack: expected 200, got %d" % int(wood_data.get("max_stack", 0)))
	if str(wood_data.get("name", "")) != "Wood":
		failures.append("WOOD name: expected 'Wood', got '%s'" % str(wood_data.get("name", "")))

	# Setup world for chop tests.
	var world = GridWorldScript.new()
	parent.add_child(world)
	WorldGenScript.new().generate(world, TEST_SEED)

	var tree_pos: Vector2i = _find_first_tree(world)
	if tree_pos == Vector2i(2147483647, 2147483647):
		_cleanup(world, null, "")
		return { "ok": false, "message": "no tree found in seed %d (test setup issue)" % TEST_SEED }

	# (1) chop_tree mutates tile + sets regrowth.
	world.chop_tree(tree_pos)
	# Tile's resource_node should be NONE now (either via tile entry or via erase + tile_modifications).
	# Helper: the post-chop state is "tree gone, regrowth pending."
	var post_chop_resource_node: int = ResourceNodes.Type.NONE
	if world.tiles.has(tree_pos):
		post_chop_resource_node = world.tiles[tree_pos].resource_node
	if post_chop_resource_node != ResourceNodes.Type.NONE:
		failures.append("after chop: tile resource_node = %d, expected NONE" % post_chop_resource_node)
	# resource_state has the regrowth timer.
	if not world.resource_state.has(tree_pos):
		failures.append("after chop: resource_state missing regrowth timer entry")
	else:
		var s: Dictionary = world.resource_state[tree_pos]
		if not s.has("regrowth_remaining"):
			failures.append("after chop: resource_state[%s] missing 'regrowth_remaining' key" % str(tree_pos))
		elif abs(float(s["regrowth_remaining"]) - GridWorldScript.TREE_REGROWTH_SECONDS) > 0.001:
			failures.append("after chop: regrowth_remaining = %f, expected %f" % [float(s["regrowth_remaining"]), GridWorldScript.TREE_REGROWTH_SECONDS])
	# tile_modifications records the chop.
	if not world.tile_modifications.has(tree_pos):
		failures.append("after chop: tile_modifications missing entry at %s" % str(tree_pos))
	# resource_state_modifications mirrors the timer (v14 Dict shape).
	if not world.resource_state_modifications.has(tree_pos):
		failures.append("after chop: resource_state_modifications missing entry at %s" % str(tree_pos))
	else:
		var rsm: Dictionary = world.resource_state_modifications[tree_pos]
		if not rsm.has("regrowth_remaining"):
			failures.append("after chop: resource_state_modifications[%s] missing 'regrowth_remaining'" % str(tree_pos))

	# (2) Manual tick: invoke _tick_regrowth with delta = TREE_REGROWTH_SECONDS to fully expire.
	world._tick_regrowth(GridWorldScript.TREE_REGROWTH_SECONDS + 1.0)
	# Tree should be restored.
	if not world.tiles.has(tree_pos):
		failures.append("after full regrowth: tiles missing entry at %s (tree should be restored)" % str(tree_pos))
	else:
		var t: Tile = world.tiles[tree_pos]
		if t.resource_node != ResourceNodes.Type.TREE:
			failures.append("after full regrowth: tile resource_node = %d, expected TREE" % t.resource_node)
	if world.resource_state.has(tree_pos):
		failures.append("after full regrowth: resource_state still has entry at %s" % str(tree_pos))
	if world.tile_modifications.has(tree_pos):
		failures.append("after full regrowth: tile_modifications still has entry at %s (should be erased)" % str(tree_pos))

	# (3) Save round-trip mid-regrowth. Chop again, advance partway, save, load, verify.
	world.chop_tree(tree_pos)
	# Advance the timer to 60% remaining (e.g., 180s if total is 300).
	var partial: float = GridWorldScript.TREE_REGROWTH_SECONDS * 0.4
	world._tick_regrowth(partial)
	var pre_save_remaining: float = world.regrowth_remaining_at(tree_pos)
	if pre_save_remaining <= 0.0:
		failures.append("partial regrowth: pre-save remaining = %f, expected > 0" % pre_save_remaining)

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	var player_a := Node2D.new()
	parent.add_child(player_a)
	var inv_a := Inventory.new(16)
	if not SaveSystem.save_game(world, player_a, inv_a, {}):
		_cleanup(world, player_a, orig_path)
		return { "ok": false, "message": "save_game returned false" }

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b := Inventory.new(16)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, inv_b)
	if not result.success:
		_cleanup(world, player_a, orig_path)
		world_b.queue_free()
		player_b.queue_free()
		return { "ok": false, "message": "load_game failed: %s" % result.error_message }

	# After load: tile should be NONE (chopped state), resource_state has regrowth timer.
	var post_load_resource_node: int = ResourceNodes.Type.NONE
	if world_b.tiles.has(tree_pos):
		post_load_resource_node = world_b.tiles[tree_pos].resource_node
	if post_load_resource_node != ResourceNodes.Type.NONE:
		failures.append("after load: tile resource_node = %d, expected NONE" % post_load_resource_node)
	var post_load_remaining: float = world_b.regrowth_remaining_at(tree_pos)
	if abs(post_load_remaining - pre_save_remaining) > 0.01:
		failures.append("after load: remaining = %f, expected %f (timer didn't round-trip)" % [post_load_remaining, pre_save_remaining])

	# (4) Overlay-cancels-regrowth: paint stone overlay on the regrowing tile.
	# Should erase the regrowth timer (player committed to paving).
	var ok: bool = world_b.set_overlay(tree_pos, Terrain.Overlay.STONE)
	if not ok:
		failures.append("set_overlay on regrowing tile rejected: %s" % world_b.last_place_error)
	if world_b.resource_state.has(tree_pos):
		failures.append("after overlay-on-regrowing: resource_state still has entry (regrowth should be cancelled)")
	if world_b.resource_state_modifications.has(tree_pos):
		failures.append("after overlay-on-regrowing: resource_state_modifications still has entry")
	if world_b.tiles.has(tree_pos):
		var t2: Tile = world_b.tiles[tree_pos]
		if t2.overlay != Terrain.Overlay.STONE:
			failures.append("after overlay-on-regrowing: overlay = %d, expected STONE" % t2.overlay)

	# Cleanup.
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
	_cleanup(world, player_a, "")
	world_b.queue_free()
	player_b.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "tree chop, regrowth tick, save mid-regrowth, overlay-cancels — all correct" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

# ---- helpers ----

static func _find_first_tree(world: GridWorld) -> Vector2i:
	var positions: Array = []
	for pos in world.tiles.keys():
		var t: Tile = world.tiles[pos]
		if t.resource_node == ResourceNodes.Type.TREE:
			positions.append(pos)
	if positions.is_empty():
		return Vector2i(2147483647, 2147483647)
	positions.sort_custom(func(a, b):
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	return positions[0]

static func _cleanup(world, player, orig_path: String) -> void:
	if world != null:
		if TickSystem.tick.is_connected(world._on_tick):
			TickSystem.tick.disconnect(world._on_tick)
		world.queue_free()
	if player != null:
		player.queue_free()
	if orig_path != "":
		SaveSystem.save_path = orig_path
