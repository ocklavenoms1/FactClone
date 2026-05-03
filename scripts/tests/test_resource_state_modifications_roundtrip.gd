extends RefCounted

## resource_state_modifications round-trip test (v13 → v14 shape).
##
## v13 stored richness as raw int; v14 stores per-tile Dict for generic
## state (richness for ore, regrowth_remaining for trees, etc.).
##
## THE critical test for save persistence of mining state. Without it, a
## bug where mining depletion doesn't persist would silently break saves:
## player mines a patch down to 47/100, saves, quits, loads — and finds
## the patch back at 100/100. Catastrophic UX.
##
## What this test locks in:
##   1. After deplete_resource, resource_state_modifications[pos] holds
##      the new richness, AND resource_state[pos]["richness"] matches.
##   2. After save → clear → load:
##      - resource_state_modifications[pos] preserved
##      - resource_state[pos]["richness"] preserved (loaded from modification)
##      - resource_state[pos]["original_richness"] preserved (rederived
##        from procgen, NOT loaded from save)
##   3. Fully-depleted tiles (richness 0): tile_modifications handles the
##      revert (resource_node = NONE); resource_state and
##      resource_state_modifications both empty for that pos.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const WorldGenScript  = preload("res://scripts/world/world_generator.gd")
const TEST_SAVE_PATH: String = "user://test_partial_depletion.json"
const TEST_SEED: int = 42

static func test_name() -> String:
	return "resource_state_modifications round-trip (partial depletion via mining)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	# ---- Build world A, generate, find an ore tile, deplete partially ----
	var world_a = GridWorldScript.new()
	parent.add_child(world_a)
	WorldGenScript.new().generate(world_a, TEST_SEED)

	# Find a stone tile (most common ore) for the depletion test.
	var target_pos: Vector2i = _find_first_ore_tile(world_a, ResourceNodes.Type.STONE)
	if target_pos == Vector2i(2147483647, 2147483647):
		_cleanup(world_a, null, orig_path)
		return { "ok": false, "message": "no stone tile found in seed %d (test setup issue)" % TEST_SEED }

	var canonical_richness: int = world_a.richness_at(target_pos)
	var canonical_original: int = world_a.original_richness_at(target_pos)
	# Sanity: original equals current at game start.
	if canonical_richness != canonical_original:
		failures.append("at game start, richness (%d) should equal original_richness (%d)" % [canonical_richness, canonical_original])

	# Deplete by half (rounded down). Picks a value safely > 0 and < canonical
	# so the tile is partially depleted, not fully depleted.
	if canonical_richness < 4:
		_cleanup(world_a, null, orig_path)
		return { "ok": false, "message": "stone tile at %s has richness %d — too low for partial-depletion test" % [str(target_pos), canonical_richness] }
	var to_extract: int = canonical_richness / 2
	var actually_extracted: int = world_a.deplete_resource(target_pos, to_extract)
	if actually_extracted != to_extract:
		failures.append("deplete_resource extracted %d but expected %d" % [actually_extracted, to_extract])

	var expected_after: int = canonical_richness - to_extract
	var post_deplete_richness: int = world_a.richness_at(target_pos)
	if post_deplete_richness != expected_after:
		failures.append("after deplete: richness %d, expected %d" % [post_deplete_richness, expected_after])
	if not world_a.resource_state_modifications.has(target_pos):
		failures.append("after deplete: resource_state_modifications missing entry at %s" % str(target_pos))
	else:
		var mod_a: Dictionary = world_a.resource_state_modifications[target_pos]
		if int(mod_a.get("richness", -1)) != expected_after:
			failures.append("after deplete: resource_state_modifications[%s].richness = %s, expected %d" % [str(target_pos), str(mod_a.get("richness")), expected_after])

	# ---- Save, then clear in-memory and load fresh ----
	var player_a := Node2D.new()
	parent.add_child(player_a)
	var inv_a := Inventory.new(16)
	if not SaveSystem.save_game(world_a, player_a, inv_a, {}):
		_cleanup(world_a, player_a, orig_path)
		return { "ok": false, "message": "save_game returned false" }

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b := Inventory.new(16)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, inv_b)
	if not result.success:
		_cleanup(world_a, player_a, orig_path)
		world_b.queue_free()
		player_b.queue_free()
		return { "ok": false, "message": "load_game failed: %s" % result.error_message }

	# ---- Assert v13 round-trip ----
	# (a) Current richness loaded from save (via resource_state_modifications).
	var loaded_richness: int = world_b.richness_at(target_pos)
	if loaded_richness != expected_after:
		failures.append("after load: richness at %s = %d, expected %d (modification didn't persist)" % [str(target_pos), loaded_richness, expected_after])

	# (b) original_richness rederived from procgen — equals canonical.
	var loaded_original: int = world_b.original_richness_at(target_pos)
	if loaded_original != canonical_original:
		failures.append("after load: original_richness at %s = %d, expected %d (procgen rerun didn't preserve original)" % [str(target_pos), loaded_original, canonical_original])

	# (c) resource_state_modifications loaded.
	if not world_b.resource_state_modifications.has(target_pos):
		failures.append("after load: resource_state_modifications missing entry at %s" % str(target_pos))
	else:
		var mod_b: Dictionary = world_b.resource_state_modifications[target_pos]
		if int(mod_b.get("richness", -1)) != expected_after:
			failures.append("after load: resource_state_modifications[%s].richness = %s, expected %d" % [str(target_pos), str(mod_b.get("richness")), expected_after])

	# ---- Now test FULL depletion path: drain rest, save, load, assert tile is grass ----
	world_b.deplete_resource(target_pos, expected_after)   # drain remaining
	var post_full_richness: int = world_b.richness_at(target_pos)
	if post_full_richness != 0:
		failures.append("after full deplete: richness = %d, expected 0" % post_full_richness)
	# Tile should have been removed from tiles dict (revert to default grass).
	if world_b.tiles.has(target_pos):
		failures.append("after full deplete: tile entry still present at %s (should be erased)" % str(target_pos))
	# resource_state and resource_state_modifications both cleared.
	if world_b.resource_state.has(target_pos):
		failures.append("after full deplete: resource_state still has entry at %s" % str(target_pos))
	if world_b.resource_state_modifications.has(target_pos):
		failures.append("after full deplete: resource_state_modifications still has entry at %s" % str(target_pos))
	# tile_modifications has the depleted-grass entry.
	if not world_b.tile_modifications.has(target_pos):
		failures.append("after full deplete: tile_modifications missing entry at %s (revert not recorded)" % str(target_pos))

	# Save once more, load again — fully-depleted tile should stay depleted.
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_game(world_b, player_b, inv_b, {})
	var world_c = GridWorldScript.new()
	parent.add_child(world_c)
	var player_c := Node2D.new()
	parent.add_child(player_c)
	var inv_c := Inventory.new(16)
	var result_c: LoadResult = SaveSystem.load_game(world_c, player_c, inv_c)
	if result_c.success:
		# Depleted tile should NOT have re-appeared from procgen rehydration —
		# tile_modifications overrides with resource_node=NONE.
		if world_c.tiles.has(target_pos):
			var t: Tile = world_c.tiles[target_pos]
			if t.resource_node != ResourceNodes.Type.NONE:
				failures.append("after full deplete + save+load: tile resource_node = %d (expected NONE; tile_modifications didn't apply)" % t.resource_node)
		if world_c.resource_state.has(target_pos):
			failures.append("after full deplete + save+load: resource_state has entry at %s (expected absent)" % str(target_pos))
	world_c.queue_free()
	player_c.queue_free()

	# ---- Cleanup ----
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
	_cleanup(world_a, player_a, "")   # already restored save_path
	world_b.queue_free()
	player_b.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "partial depletion + full depletion round-trip preserves richness, original_richness, and tile revert" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

# ---- helpers ----

static func _find_first_ore_tile(world: GridWorld, ore_type: int) -> Vector2i:
	# Iterate in a deterministic order (sorted positions) so test is stable.
	# Skip patch-edge tiles where intra_intensity rounds richness to 0 — those
	# exist as placeholders but aren't usable for a partial-depletion test.
	var positions: Array = []
	for pos in world.tiles.keys():
		var t: Tile = world.tiles[pos]
		if t.resource_node != ore_type:
			continue
		# Need richness ≥ 4 so partial-depletion (canonical / 2) leaves
		# a non-zero residue that's distinguishable from the 0-tile case.
		var r: int = world.richness_at(pos)
		if r < 4:
			continue
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
