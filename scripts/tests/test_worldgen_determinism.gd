extends RefCounted

## Worldgen determinism test — same seed must produce identical worlds.
##
## Generates the same world twice (seed=42), asserts all tile keys, base,
## overlay, resource_node, and resource_state values match exactly.
##
## If anything in WorldGenerator changes the world from the same seed (noise
## param, hash function, iteration order, type weights, etc.), this test
## fails — and that's the signal to bump WorldGenerator.VERSION.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const WorldGenScript  = preload("res://scripts/world/world_generator.gd")

const TEST_SEED: int = 42

static func test_name() -> String:
	return "worldgen determinism (same seed → same world)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# Generate twice with the same seed.
	var world_a = GridWorldScript.new()
	parent.add_child(world_a)
	WorldGenScript.new().generate(world_a, TEST_SEED)

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	WorldGenScript.new().generate(world_b, TEST_SEED)

	# Tile counts match.
	if world_a.tiles.size() != world_b.tiles.size():
		failures.append("tile count mismatch: A=%d vs B=%d" % [world_a.tiles.size(), world_b.tiles.size()])

	# Per-tile content match.
	var tile_mismatches: int = 0
	for pos in world_a.tiles:
		if not world_b.tiles.has(pos):
			tile_mismatches += 1
			if tile_mismatches <= 3:
				failures.append("tile only in A at %s" % str(pos))
			continue
		var ta: Tile = world_a.tiles[pos]
		var tb: Tile = world_b.tiles[pos]
		if ta.base != tb.base or ta.overlay != tb.overlay or ta.resource_node != tb.resource_node:
			tile_mismatches += 1
			if tile_mismatches <= 3:
				failures.append("tile mismatch at %s: A=(%d,%d,%d) B=(%d,%d,%d)" % [str(pos), ta.base, ta.overlay, ta.resource_node, tb.base, tb.overlay, tb.resource_node])
	if tile_mismatches > 3:
		failures.append("(... %d total tile mismatches)" % tile_mismatches)

	# resource_state count + content match.
	if world_a.resource_state.size() != world_b.resource_state.size():
		failures.append("resource_state count mismatch: A=%d vs B=%d" % [world_a.resource_state.size(), world_b.resource_state.size()])
	var rs_mismatches: int = 0
	for pos in world_a.resource_state:
		if not world_b.resource_state.has(pos):
			rs_mismatches += 1
			continue
		var ra: Dictionary = world_a.resource_state[pos]
		var rb: Dictionary = world_b.resource_state[pos]
		if int(ra.get("richness", 0)) != int(rb.get("richness", 0)):
			rs_mismatches += 1
	if rs_mismatches > 0:
		failures.append("%d resource_state mismatches" % rs_mismatches)

	# world_seed assigned correctly on both.
	if world_a.world_seed != TEST_SEED or world_b.world_seed != TEST_SEED:
		failures.append("world_seed not set correctly: A=%d B=%d" % [world_a.world_seed, world_b.world_seed])

	# Spot checks: specific tiles at known positions must produce specific
	# content for seed 42. Catches "two equally-broken runs" (both empty,
	# both crash, both nondeterministic-in-the-same-way) where the bulk
	# tile-by-tile compare would still report match. Coordinates and content
	# captured from the worldgen-stage1 smoke output for seed 42 — locking
	# the exact procgen output of seed 42 at WorldGenerator.VERSION = 3.
	#
	# If WorldGenerator changes, these will fail FIRST and force a VERSION bump.
	var spot_checks: Array = [
		# [pos, expected_kind, label]
		# Positions verified empirically for seed 42 at WorldGenerator.VERSION = 3:
		[Vector2i(0, 0),    "grass",  "spawn (0,0) is empty grass"],
		[Vector2i(45, 45),  "water",  "(45, 45) is in the southeast lake"],
		[Vector2i(3, 46),   "tree",   "(3, 46) is in the southern forest cluster"],
	]
	for sc in spot_checks:
		var pos: Vector2i = sc[0]
		var expected: String = sc[1]
		var label: String = sc[2]
		var actual_a: String = _classify_tile(world_a, pos)
		var actual_b: String = _classify_tile(world_b, pos)
		if actual_a != expected:
			failures.append("[seed %d] %s: expected %s, got %s in run A" % [TEST_SEED, label, expected, actual_a])
		if actual_b != expected:
			failures.append("[seed %d] %s: expected %s, got %s in run B" % [TEST_SEED, label, expected, actual_b])

	# Distance-scaling spot check: there must be at least one stone tile far
	# from origin (d > 200) with richness > 1000. Locks in that the richness
	# formula produces meaningfully large numbers at distance.
	var found_rich_stone: bool = false
	for pos in world_a.tiles:
		var t: Tile = world_a.tiles[pos]
		if t.resource_node != ResourceNodes.Type.STONE:
			continue
		var d: float = sqrt(float(pos.x * pos.x + pos.y * pos.y))
		if d <= 200.0:
			continue
		var r: int = int(world_a.resource_state.get(pos, {}).get("richness", 0))
		if r > 1000:
			found_rich_stone = true
			break
	if not found_rich_stone:
		failures.append("[seed %d] no stone tile beyond d=200 with richness > 1000" % TEST_SEED)

	_cleanup(world_a)
	_cleanup(world_b)

	if failures.is_empty():
		return { "ok": true, "message": "two generations with seed %d match exactly (%d tiles, %d resource_state entries)" % [TEST_SEED, world_a.tiles.size(), world_a.resource_state.size()] }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

## Classify a tile into one of: "grass" (no entry / default), "water",
## "tree", "stone", "coal", "iron", "copper", "clay".
static func _classify_tile(world, pos: Vector2i) -> String:
	if not world.tiles.has(pos):
		return "grass"
	var t: Tile = world.tiles[pos]
	if t.is_water():
		return "water"
	match t.resource_node:
		ResourceNodes.Type.NONE:   return "grass"
		ResourceNodes.Type.TREE:   return "tree"
		ResourceNodes.Type.STONE:  return "stone"
		ResourceNodes.Type.COAL:   return "coal"
		ResourceNodes.Type.IRON:   return "iron"
		ResourceNodes.Type.COPPER: return "copper"
		ResourceNodes.Type.CLAY:   return "clay"
	return "unknown"

static func _cleanup(world) -> void:
	if world == null: return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
