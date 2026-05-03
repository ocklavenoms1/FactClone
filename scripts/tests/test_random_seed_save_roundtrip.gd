extends RefCounted

## Stage 1 final smoke (lightweight): random seed at fresh start round-trips.
##
## Generates a world with a "freshly randomized" seed, saves, loads into a
## blank world, asserts the loaded world's seed and content match.
##
## Catches: seed not persisted; load picks wrong seed; load doesn't run
## procgen rehydration; etc. End-to-end check that step 6 + step 8 are wired.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const WorldGenScript  = preload("res://scripts/world/world_generator.gd")
const TEST_SAVE_PATH: String = "user://test_random_seed.json"

static func test_name() -> String:
	return "random seed at fresh start round-trips through save"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# Generate ten "random" seeds and ensure they're not all identical.
	# (Pseudo-random via Time + index; just needs to vary.)
	var seeds: Array[int] = []
	for i in 10:
		seeds.append(int(Time.get_ticks_usec() + i * 1000) & 0x7FFFFFFF)
	var unique := {}
	for s in seeds: unique[s] = true
	if unique.size() < 10:
		failures.append("randomized seeds not unique across 10 calls (got %d unique)" % unique.size())

	# Round-trip one seed through save/load.
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	var test_seed: int = seeds[0]
	var world_a = GridWorldScript.new()
	parent.add_child(world_a)
	WorldGenScript.new().generate(world_a, test_seed)
	var sample_tile_count_a: int = world_a.tiles.size()

	var player_a := Node2D.new()
	parent.add_child(player_a)
	player_a.global_position = Vector2.ZERO
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

	if world_b.world_seed != test_seed:
		failures.append("seed mismatch after load: expected %d, got %d" % [test_seed, world_b.world_seed])
	if world_a.tiles.size() != world_b.tiles.size():
		failures.append("tile count mismatch after rehydration: %d vs %d" % [world_a.tiles.size(), world_b.tiles.size()])

	# Cleanup.
	_cleanup(world_a, player_a, orig_path)
	world_b.queue_free()
	player_b.queue_free()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	if failures.is_empty():
		return { "ok": true, "message": "seed %d round-trips; %d unique random seeds; %d tiles regenerated" % [test_seed, unique.size(), sample_tile_count_a] }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _cleanup(world, player, orig_path: String) -> void:
	if world != null:
		if TickSystem.tick.is_connected(world._on_tick):
			TickSystem.tick.disconnect(world._on_tick)
		world.queue_free()
	if player != null:
		player.queue_free()
	SaveSystem.save_path = orig_path
