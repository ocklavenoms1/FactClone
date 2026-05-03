extends RefCounted

## Worldgen distance-scaling test — deposits at distance 200+ have higher
## average richness than deposits at distance 30-100.
##
## Locks in the design intent: "richer patches are farther away," driving
## the exploration loop. If someone changes BASE_RICHNESS, DISTANCE_SCALE,
## or DISTANCE_POWER such that this property breaks, the test fires.
##
## Threshold: far/near richness ratio must be ≥ 3.0. Picked so the test
## passes comfortably at current tuning (ratio is ~10-15 in practice) but
## still fails if someone accidentally inverts or flattens the curve.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const WorldGenScript  = preload("res://scripts/world/world_generator.gd")

const TEST_SEED: int = 42
# Strict bands per the design intent: spawn-area (0-30) vs. far (200-300).
# Inner-band ore is sparse (most spawn regions don't roll a patch + distance
# gating excludes ores past stone/clay). Test will fail if there's no inner
# ore at all — which would indicate the spawn area is over-clearing or the
# patch model has stopped placing anything near origin.
const NEAR_BAND_LO: float = 0.0
const NEAR_BAND_HI: float = 30.0
const FAR_BAND_LO:  float = 200.0
const FAR_BAND_HI:  float = 300.0
# Far-band richness must be at least 5× near-band richness.
# Empirical at current tuning: ~100x. 5x leaves headroom for
# tuning drift while still firing if someone flattens the curve.
const MIN_RICHNESS_RATIO: float = 5.0

static func test_name() -> String:
	return "worldgen distance-scaling (far patches richer than near)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	var world = GridWorldScript.new()
	parent.add_child(world)
	WorldGenScript.new().generate(world, TEST_SEED)

	var near_sum: int = 0
	var near_count: int = 0
	var far_sum: int = 0
	var far_count: int = 0

	for pos in world.tiles:
		var t: Tile = world.tiles[pos]
		if not ResourceNodes.is_ore(t.resource_node):
			continue
		var d: float = sqrt(float(pos.x * pos.x + pos.y * pos.y))
		var r: int = int(world.resource_state.get(pos, {}).get("richness", 0))
		if d >= NEAR_BAND_LO and d < NEAR_BAND_HI:
			near_sum += r
			near_count += 1
		elif d >= FAR_BAND_LO and d < FAR_BAND_HI:
			far_sum += r
			far_count += 1

	if near_count == 0:
		failures.append("no near-band ore tiles found (band %d-%d)" % [int(NEAR_BAND_LO), int(NEAR_BAND_HI)])
	if far_count == 0:
		failures.append("no far-band ore tiles found (band %d-%d)" % [int(FAR_BAND_LO), int(FAR_BAND_HI)])

	if near_count > 0 and far_count > 0:
		var near_avg: float = float(near_sum) / float(near_count)
		var far_avg: float = float(far_sum) / float(far_count)
		var ratio: float = far_avg / near_avg if near_avg > 0.0 else 0.0
		if ratio < MIN_RICHNESS_RATIO:
			failures.append("far/near richness ratio too low: %.2f (need ≥ %.1f). near avg %.1f, far avg %.1f" % [ratio, MIN_RICHNESS_RATIO, near_avg, far_avg])

	_cleanup(world)

	if failures.is_empty():
		var n_avg: float = float(near_sum) / float(near_count)
		var f_avg: float = float(far_sum) / float(far_count)
		return { "ok": true, "message": "near band avg %.1f vs far band avg %.1f (ratio %.2fx)" % [n_avg, f_avg, f_avg / n_avg] }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _cleanup(world) -> void:
	if world == null: return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
