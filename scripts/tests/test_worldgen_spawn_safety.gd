extends RefCounted

## Worldgen spawn safety net — over a sample of seeds, the 60×60 spawn area
## always has water in [SPAWN_AREA_MIN_WATER, SPAWN_AREA_MAX_WATER].
##
## Locks in:
##   1. Floor: lowest-water seed has at least the safety-net floor.
##   2. Ceiling: highest-water seed is below 25% of spawn area.
##
## Sample size: 50 seeds (range 1-50). Catches floor and ceiling violations
## reliably across the parameter space.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const WorldGenScript  = preload("res://scripts/world/world_generator.gd")

const SAMPLE_SIZE: int = 50

static func test_name() -> String:
	return "worldgen spawn-area safety (water count in [floor, ceiling] across seeds)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var min_water: int = 999999
	var max_water: int = 0
	var min_seed: int = 0
	var max_seed: int = 0

	for sample_seed in range(1, SAMPLE_SIZE + 1):
		var world = GridWorldScript.new()
		parent.add_child(world)
		WorldGenScript.new().generate(world, sample_seed)

		var w: int = 0
		for x in range(-WorldGenScript.SPAWN_AREA_RADIUS, WorldGenScript.SPAWN_AREA_RADIUS):
			for y in range(-WorldGenScript.SPAWN_AREA_RADIUS, WorldGenScript.SPAWN_AREA_RADIUS):
				if world.tiles.has(Vector2i(x, y)) and world.tiles[Vector2i(x, y)].is_water():
					w += 1
		if w < min_water:
			min_water = w
			min_seed = sample_seed
		if w > max_water:
			max_water = w
			max_seed = sample_seed
		if w < WorldGenScript.SPAWN_AREA_MIN_WATER:
			failures.append("seed %d: spawn-area water %d below floor %d" % [sample_seed, w, WorldGenScript.SPAWN_AREA_MIN_WATER])
		if w > WorldGenScript.SPAWN_AREA_MAX_WATER:
			failures.append("seed %d: spawn-area water %d above ceiling %d" % [sample_seed, w, WorldGenScript.SPAWN_AREA_MAX_WATER])
		_cleanup(world)

	if failures.is_empty():
		return { "ok": true, "message": "%d seeds tested; spawn water range [%d (seed %d), %d (seed %d)]" % [SAMPLE_SIZE, min_water, min_seed, max_water, max_seed] }
	return { "ok": false, "message": "%d failures (first 5): %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

static func _cleanup(world) -> void:
	if world == null: return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
