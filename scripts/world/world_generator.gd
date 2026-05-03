class_name WorldGenerator
extends RefCounted

## Deterministic, seeded world generation — patch placement model.
##
## VERSION POLICY (read this before changing ANY generation logic):
##
## Any change to the following requires bumping `VERSION` and accepting
## that all existing saves will hard-fail to load:
##   - REGION_SIZE, PATCH_PROBABILITY, type weights
##   - BASE_RADIUS_MIN/MAX, distance size multiplier formula
##   - DISTANCE_SCALE, DISTANCE_POWER, BASE_RICHNESS values
##   - Resource priority order or weighted-pick algorithm
##   - Lake count range / radius range
##   - Tree forest count, radius, or density falloff
##   - Patch shape algorithm or perturbation amount
##   - Spawn safety net algorithm or thresholds
##   - hash3 mix function
##   - Iteration order (rx then ry, region presence before type, etc.)
##   - Per-roll seed offsets
##
## Why: procgen rehydration regenerates the world from `(seed, version)` on
## load. Any change produces a different world from the same seed, which
## would silently corrupt saves (player modifications applied to a different
## terrain). Hard-fail on version mismatch is the only correct behavior.
##
## To make a tweak that doesn't break saves: don't. There is no path. If a
## number genuinely needs adjusting, bump VERSION, document the diff in
## PROJECT_LOG, and tell the user to delete their save.

const VERSION: int = 3   # v1 = per-tile noise (deprecated). v2 = patch placement. v3 = + ambient scattered trees.

# ---------- world bounds ----------
const WORLD_MIN: int = -256
const WORLD_MAX: int = 256          # exclusive

# ---------- region grid ----------
# Regions are 32×32 tiles (Factorio chunk standard). Stage 3 will use the
# same primitive for chunked-infinite generation — region == chunk.
const REGION_SIZE: int = 32
# Stage 1 region range: -8..7 in each axis = 16 regions per axis = 256 total.
const REGION_MIN: int = -8
const REGION_MAX: int = 8           # exclusive

# ---------- patch placement ----------
const PATCH_PROBABILITY: float = 0.50      # ~128 patches per 256-region world

# Per-region patch base radius (before distance scaling). Tuned for ~5%
# total non-default coverage. Initial smoke at 2.5/5.0 produced 11% — too
# dense; halved to hit "start sparse, scale up only if needed."
const BASE_RADIUS_MIN: float = 1.5
const BASE_RADIUS_MAX: float = 3.0

# Boundary perturbation amount: ±X of base radius. Higher = more wavy
# boundaries. Implemented via shape noise multiplier (1.0 + perturb).
const SHAPE_PERTURB_AMOUNT: float = 0.4

# ---------- distance-gated resource availability ----------
# A resource type is eligible for a region IFF the region center is at
# least MIN_SPAWN_DISTANCE tiles from origin. Inner regions only get types
# that are eligible. Stone and clay are always eligible (MIN=0); ores
# require travel.
#
# This is the EXPLORATION LOOP — without it, every world looks the same
# at spawn and players have no reason to walk.
const MIN_SPAWN_DISTANCE: Dictionary = {
	ResourceNodes.Type.STONE:  0,
	ResourceNodes.Type.CLAY:   0,
	ResourceNodes.Type.COAL:   30,
	ResourceNodes.Type.IRON:   50,
	ResourceNodes.Type.COPPER: 100,
}

# Weighted-pick weights for resource type within a region. Higher weight =
# more likely. Stone/coal common (commodity, fuel), copper rare (advanced).
# Pick is over the SUBSET eligible for the region's distance.
const TYPE_WEIGHTS: Dictionary = {
	ResourceNodes.Type.STONE:  4,
	ResourceNodes.Type.COAL:   4,
	ResourceNodes.Type.CLAY:   3,
	ResourceNodes.Type.IRON:   3,
	ResourceNodes.Type.COPPER: 2,
}

# Iteration order for type weight loop — must be stable for determinism.
const TYPE_ORDER: Array[int] = [
	ResourceNodes.Type.STONE,
	ResourceNodes.Type.COAL,
	ResourceNodes.Type.CLAY,
	ResourceNodes.Type.IRON,
	ResourceNodes.Type.COPPER,
]

# ---------- richness scaling ----------
# richness = intra_intensity * BASE_RICHNESS[type] * distance_multiplier
# where intra_intensity = 1 - (dist_to_patch_center / radius)^2 (inverse-sq fade).
const DISTANCE_SCALE: float = 40.0
const DISTANCE_POWER: float = 2.5

const BASE_RICHNESS: Dictionary = {
	ResourceNodes.Type.STONE:  80,
	ResourceNodes.Type.COAL:   60,
	ResourceNodes.Type.IRON:   50,
	ResourceNodes.Type.COPPER: 50,
	ResourceNodes.Type.CLAY:   40,
}

# Patch radius distance scaling: bigger patches farther from origin.
# multiplier = 1 + sqrt(d / SIZE_SCALE_TILES).
const SIZE_SCALE_TILES: float = 200.0

# ---------- forests (tree clusters) ----------
const FOREST_COUNT_MIN: int = 6
const FOREST_COUNT_MAX: int = 10
const FOREST_RADIUS_MIN: int = 8
const FOREST_RADIUS_MAX: int = 25
# Density at cluster center; falls off as (1 - (d/r)^2). Avg density across
# disk ≈ PEAK / 2.
const FOREST_DENSITY_PEAK: float = 0.6

# ---------- ambient scattered trees (Path B refinement) ----------
# Forest clusters above place dense "destination" forests. The ambient pass
# adds individual trees scattered across plains, modulated by a low-frequency
# density noise so some regions are "lightly wooded grassland" (woody) and
# others are "open plains" (sparse). Avoids both uniform-speckle (noise
# everywhere at same density) and the forest-only pattern (long stretches
# with zero trees between clusters).
#
# Effective probability = AMBIENT_BASE_PROBABILITY × density_multiplier
# where density_multiplier = 0.5 + 1.5 * normalize(density_noise) ∈ [0.5, 2.0]
# so probability range = [BASE × 0.5, BASE × 2.0] across the world.
const AMBIENT_BASE_PROBABILITY: float = 0.002    # 0.2% per plains tile baseline
const AMBIENT_DENSITY_FREQUENCY: float = 0.005   # very large smooth regions

# ---------- lakes ----------
const LAKE_COUNT_MIN: int = 2
const LAKE_COUNT_MAX: int = 4
const LAKE_RADIUS_MIN: int = 12
const LAKE_RADIUS_MAX: int = 30

# ---------- spawn safety net ----------
const SPAWN_AREA_RADIUS:    int = 30   # 60×60 box centered on origin
const SPAWN_AREA_MIN_WATER: int = 12
const SPAWN_AREA_MAX_WATER: int = 900  # 25% of 60×60
const FALLBACK_LAKE_SIZE:   int = 4    # 4×4 = 16 tiles, comfortably above MIN
const FALLBACK_PICK_TOP_N:  int = 10

# ---------- seed offsets ----------
# Each independent random source uses a distinct offset so they don't correlate.
const SEED_OFFSET_REGION_PRESENCE: int = 200
const SEED_OFFSET_REGION_TYPE:     int = 201
const SEED_OFFSET_REGION_X:        int = 202
const SEED_OFFSET_REGION_Y:        int = 203
const SEED_OFFSET_REGION_SIZE:     int = 204
const SEED_OFFSET_SHAPE_NOISE:     int = 205   # FastNoiseLite seed

const SEED_OFFSET_FOREST_COUNT:    int = 210
const SEED_OFFSET_FOREST_BASE:     int = 211   # forest_i uses base + i

const SEED_OFFSET_LAKE_COUNT:      int = 220
const SEED_OFFSET_LAKE_BASE:       int = 221   # lake_i uses base + i

const SEED_OFFSET_AMBIENT_DENSITY: int = 230   # FastNoiseLite seed for density variation
const SEED_OFFSET_AMBIENT_TREE:    int = 231   # per-tile hash for scatter spawn

const SEED_OFFSET_LAKE_FALLBACK:   int = 100
const SEED_OFFSET_LAKE_CEILING:    int = 101

const SEED_OFFSET_TREE:            int = 8     # per-tile tree spawn within forest cluster

# ---------- shared noise instances ----------
# _shape_noise: per-patch boundary perturbation (one field across the world).
# _ambient_density_noise: low-freq variation for scattered tree density.
var _shape_noise: FastNoiseLite
var _ambient_density_noise: FastNoiseLite

func _build_noise(seed: int) -> void:
	_shape_noise = FastNoiseLite.new()
	_shape_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_shape_noise.seed = seed + SEED_OFFSET_SHAPE_NOISE
	_shape_noise.frequency = 0.30
	_shape_noise.fractal_octaves = 1

	_ambient_density_noise = FastNoiseLite.new()
	_ambient_density_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_ambient_density_noise.seed = seed + SEED_OFFSET_AMBIENT_DENSITY
	_ambient_density_noise.frequency = AMBIENT_DENSITY_FREQUENCY
	_ambient_density_noise.fractal_octaves = 2

# ---------- public entry point ----------

## Generate the entire Stage 1 world into the given GridWorld instance.
## Idempotent: clears tiles + resource_state + tile_modifications first.
## Deterministic: same seed → same output.
##
## Iteration ORDER MATTERS for determinism:
##   1. Lakes — placed first so ore patches see them.
##   2. Ore patches — region-by-region, explicit (rx, ry) loops.
##   3. Forest clusters — over remaining grass.
##   4. Spawn safety net floor (add water if too little).
##   5. Spawn safety net ceiling (remove water if too much).
func generate(world: GridWorld, seed: int) -> void:
	world.world_seed = seed
	world.tiles.clear()
	world.resource_state.clear()
	world.tile_modifications.clear()

	_build_noise(seed)

	# Pass 1: lakes (BEFORE ore so ore patches abort if center is in a lake).
	_place_lakes(world, seed)

	# Pass 2: ore patches via per-region rolls.
	# Explicit ordered loops; do NOT use dict iteration for determinism.
	for rx in range(REGION_MIN, REGION_MAX):
		for ry in range(REGION_MIN, REGION_MAX):
			_consider_region(world, seed, rx, ry)

	# Pass 3: forest clusters (dense destination forests).
	_place_forests(world, seed)

	# Pass 4: ambient scattered trees (low-density noise-modulated; gives
	# plains visual variety and ensures some trees visible from any spawn).
	_place_ambient_trees(world, seed)

	# Pass 5: spawn safety net floor.
	_ensure_spawn_area_water(world, seed)

	# Pass 6: spawn safety net ceiling.
	_clamp_spawn_area_water_max(world, seed)

# ---------- pass 1: lakes ----------

func _place_lakes(world: GridWorld, seed: int) -> void:
	var count_roll: float = _hash3_unit(seed + SEED_OFFSET_LAKE_COUNT, 0, 0)
	var count: int = LAKE_COUNT_MIN + int(count_roll * float(LAKE_COUNT_MAX - LAKE_COUNT_MIN + 1))
	count = clamp(count, LAKE_COUNT_MIN, LAKE_COUNT_MAX)

	for i in count:
		# Position: anywhere in the world, leaving margin equal to max radius.
		var margin: int = LAKE_RADIUS_MAX
		var x_roll: float = _hash3_unit(seed + SEED_OFFSET_LAKE_BASE + i, 1, 0)
		var y_roll: float = _hash3_unit(seed + SEED_OFFSET_LAKE_BASE + i, 0, 1)
		var size_roll: float = _hash3_unit(seed + SEED_OFFSET_LAKE_BASE + i, 2, 2)
		var cx: int = WORLD_MIN + margin + int(x_roll * float(WORLD_MAX - WORLD_MIN - 2 * margin))
		var cy: int = WORLD_MIN + margin + int(y_roll * float(WORLD_MAX - WORLD_MIN - 2 * margin))
		var radius: float = lerp(float(LAKE_RADIUS_MIN), float(LAKE_RADIUS_MAX), size_roll)
		_place_lake_patch(world, Vector2i(cx, cy), radius)

func _place_lake_patch(world: GridWorld, center: Vector2i, radius: float) -> void:
	var bound: int = int(ceil(radius * (1.0 + SHAPE_PERTURB_AMOUNT))) + 1
	for dx in range(-bound, bound + 1):
		for dy in range(-bound, bound + 1):
			var pos: Vector2i = center + Vector2i(dx, dy)
			if not _in_bounds(pos):
				continue
			# Lakes don't overwrite existing water (no-op if already there).
			# They DO overwrite anything else (lakes are pass-1 — nothing else exists yet).
			if world.tiles.has(pos) and world.tiles[pos].is_water():
				continue
			var dist: float = sqrt(float(dx * dx + dy * dy))
			var perturb: float = _shape_noise.get_noise_2d(pos.x, pos.y) * SHAPE_PERTURB_AMOUNT
			var effective_radius: float = radius * (1.0 + perturb)
			if dist > effective_radius:
				continue
			world.tiles[pos] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)

# ---------- pass 2: per-region ore patches ----------

func _consider_region(world: GridWorld, seed: int, rx: int, ry: int) -> void:
	# Roll: does this region get a patch?
	var presence: float = _hash3_unit(seed + SEED_OFFSET_REGION_PRESENCE, rx, ry)
	if presence >= PATCH_PROBABILITY:
		return

	# Region center (used for distance gating + size scaling).
	var center_x: int = rx * REGION_SIZE + REGION_SIZE / 2
	var center_y: int = ry * REGION_SIZE + REGION_SIZE / 2
	var center_distance: float = sqrt(float(center_x * center_x + center_y * center_y))

	# Type selection: weighted pick over eligibles (those whose MIN_SPAWN_DISTANCE
	# is within reach of this region's center).
	var type: int = _pick_resource_type(seed, rx, ry, center_distance)
	if type == ResourceNodes.Type.NONE:
		return  # no eligible types (shouldn't happen — stone/clay always eligible)

	# Patch center: random position within the region (margin of 4 from edges
	# so most patches stay inside their home region).
	var x_roll: float = _hash3_unit(seed + SEED_OFFSET_REGION_X, rx, ry)
	var y_roll: float = _hash3_unit(seed + SEED_OFFSET_REGION_Y, rx, ry)
	var px: int = rx * REGION_SIZE + 4 + int(x_roll * float(REGION_SIZE - 8))
	var py: int = ry * REGION_SIZE + 4 + int(y_roll * float(REGION_SIZE - 8))
	var patch_center := Vector2i(px, py)

	# Lake-collision check: if patch center is water, skip the region entirely.
	# Avoids half-moon artifacts where a patch is partially eaten by a lake.
	if world.tiles.has(patch_center) and world.tiles[patch_center].is_water():
		return

	# Patch base radius: lerp(MIN, MAX) by size roll, then scaled by distance.
	# Distance multiplier: 1 + sqrt(d/SIZE_SCALE_TILES). Bigger patches farther.
	var size_roll: float = _hash3_unit(seed + SEED_OFFSET_REGION_SIZE, rx, ry)
	var base_radius: float = lerp(BASE_RADIUS_MIN, BASE_RADIUS_MAX, size_roll)
	var size_multiplier: float = 1.0 + sqrt(center_distance / SIZE_SCALE_TILES)
	var radius: float = base_radius * size_multiplier

	_place_patch(world, patch_center, type, radius)

func _pick_resource_type(seed: int, rx: int, ry: int, region_distance: float) -> int:
	# Build eligibility list with weights (in canonical TYPE_ORDER for determinism).
	var total_weight: int = 0
	var eligible: Array = []   # [type, cumulative_weight] pairs
	for t in TYPE_ORDER:
		var min_d: int = int(MIN_SPAWN_DISTANCE.get(t, 0))
		if region_distance < float(min_d):
			continue
		total_weight += int(TYPE_WEIGHTS.get(t, 1))
		eligible.append([t, total_weight])
	if eligible.is_empty():
		return ResourceNodes.Type.NONE
	var roll_int: int = int(floor(_hash3_unit(seed + SEED_OFFSET_REGION_TYPE, rx, ry) * float(total_weight)))
	for entry in eligible:
		if roll_int < int(entry[1]):
			return int(entry[0])
	return int(eligible[-1][0])   # rounding edge case; pick last

func _place_patch(world: GridWorld, center: Vector2i, type: int, base_radius: float) -> void:
	var bound: int = int(ceil(base_radius * (1.0 + SHAPE_PERTURB_AMOUNT))) + 1
	for dx in range(-bound, bound + 1):
		for dy in range(-bound, bound + 1):
			var pos: Vector2i = center + Vector2i(dx, dy)
			if not _in_bounds(pos):
				continue
			# First-write-wins: skip lakes, skip already-placed patches.
			if world.tiles.has(pos):
				var existing: Tile = world.tiles[pos]
				if existing.is_water():
					continue
				if existing.resource_node != ResourceNodes.Type.NONE:
					continue
			var dist: float = sqrt(float(dx * dx + dy * dy))
			var perturb: float = _shape_noise.get_noise_2d(pos.x, pos.y) * SHAPE_PERTURB_AMOUNT
			var effective_radius: float = base_radius * (1.0 + perturb)
			if dist > effective_radius:
				continue
			# Within-patch richness: inverse-square fade from center.
			var intra_intensity: float = clamp(1.0 - pow(dist / base_radius, 2.0), 0.0, 1.0)
			# Distance scaling from world origin (corner patches richer).
			var origin_distance: float = sqrt(float(pos.x * pos.x + pos.y * pos.y))
			var distance_multiplier: float = 1.0 + pow(origin_distance / DISTANCE_SCALE, DISTANCE_POWER)
			var richness: int = int(round(intra_intensity * float(BASE_RICHNESS[type]) * distance_multiplier))
			world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, type)
			# original_richness: the canonical generated value; stays constant for the
			# lifetime of the patch so depletion alpha-fade can be proportional
			# (current/original) rather than absolute. Recomputable from seed at load
			# time, NOT persisted in save (resource_state_modifications stores only
			# `current` richness; original is rederived via WorldGenerator.generate).
			world.resource_state[pos] = {"richness": richness, "original_richness": richness}

# ---------- pass 3: forest clusters ----------

func _place_forests(world: GridWorld, seed: int) -> void:
	var count_roll: float = _hash3_unit(seed + SEED_OFFSET_FOREST_COUNT, 0, 0)
	var count: int = FOREST_COUNT_MIN + int(count_roll * float(FOREST_COUNT_MAX - FOREST_COUNT_MIN + 1))
	count = clamp(count, FOREST_COUNT_MIN, FOREST_COUNT_MAX)

	for i in count:
		var margin: int = FOREST_RADIUS_MAX
		var x_roll: float = _hash3_unit(seed + SEED_OFFSET_FOREST_BASE + i, 1, 0)
		var y_roll: float = _hash3_unit(seed + SEED_OFFSET_FOREST_BASE + i, 0, 1)
		var size_roll: float = _hash3_unit(seed + SEED_OFFSET_FOREST_BASE + i, 2, 2)
		var cx: int = WORLD_MIN + margin + int(x_roll * float(WORLD_MAX - WORLD_MIN - 2 * margin))
		var cy: int = WORLD_MIN + margin + int(y_roll * float(WORLD_MAX - WORLD_MIN - 2 * margin))
		var radius: float = lerp(float(FOREST_RADIUS_MIN), float(FOREST_RADIUS_MAX), size_roll)
		_place_forest_cluster(world, seed, Vector2i(cx, cy), radius)

func _place_forest_cluster(world: GridWorld, seed: int, center: Vector2i, radius: float) -> void:
	var bound: int = int(ceil(radius)) + 1
	for dx in range(-bound, bound + 1):
		for dy in range(-bound, bound + 1):
			var pos: Vector2i = center + Vector2i(dx, dy)
			if not _in_bounds(pos):
				continue
			if world.tiles.has(pos):
				continue   # skip water, ore, anything pre-existing
			var dist: float = sqrt(float(dx * dx + dy * dy))
			if dist > radius:
				continue
			# Density falloff: PEAK at center, 0 at edge (quadratic).
			var density: float = FOREST_DENSITY_PEAK * (1.0 - pow(dist / radius, 2.0))
			var roll: float = _hash3_unit(seed + SEED_OFFSET_TREE, pos.x, pos.y)
			if roll < density:
				world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)
				# Trees default to fully grown — no resource_state entry needed.

# ---------- pass 4: ambient scattered trees ----------

## Walks every tile in the world and spawns scattered ambient trees on
## plains tiles (no water, no ore, no existing tree). Per-tile probability
## is modulated by a low-frequency density noise, so some plains regions
## are "lightly wooded" (~0.4% density) and others are "open plains" (~0.1%).
##
## Avoids the uniform-speckle pattern that the patch architecture rejected
## by giving the per-tile probability a smooth spatial variation.
func _place_ambient_trees(world: GridWorld, seed: int) -> void:
	for x in range(WORLD_MIN, WORLD_MAX):
		for y in range(WORLD_MIN, WORLD_MAX):
			var pos := Vector2i(x, y)
			# Skip non-plains tiles (water, ore, existing tree).
			if world.tiles.has(pos):
				continue
			# Density multiplier from low-frequency noise: 0.5x to 2.0x base.
			var raw: float = _ambient_density_noise.get_noise_2d(x, y)         # -1..1
			var norm: float = (raw + 1.0) * 0.5                                  # 0..1
			var density_multiplier: float = 0.5 + norm * 1.5                     # 0.5..2.0
			var probability: float = AMBIENT_BASE_PROBABILITY * density_multiplier
			# Per-tile spawn roll.
			var roll: float = _hash3_unit(seed + SEED_OFFSET_AMBIENT_TREE, x, y)
			if roll < probability:
				world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)

# ---------- spawn safety net ----------

func _ensure_spawn_area_water(world: GridWorld, seed: int) -> void:
	var water_count: int = _count_spawn_water(world)
	if water_count >= SPAWN_AREA_MIN_WATER:
		return

	# Collect eligible 4×4 grass anchors in spawn area.
	var candidates: Array[Vector2i] = []
	var bound: int = SPAWN_AREA_RADIUS - FALLBACK_LAKE_SIZE
	for ax in range(-bound, bound + 1):
		for ay in range(-bound, bound + 1):
			if _is_NxN_clear(world, Vector2i(ax, ay), FALLBACK_LAKE_SIZE):
				candidates.append(Vector2i(ax, ay))
	if candidates.is_empty():
		push_warning("WorldGenerator: spawn-area lake fallback found no eligible position")
		return

	# Sort by distance ASC, then x, then y.
	candidates.sort_custom(func(a, b):
		var da: int = a.x * a.x + a.y * a.y
		var db: int = b.x * b.x + b.y * b.y
		if da != db: return da < db
		if a.x != b.x: return a.x < b.x
		return a.y < b.y
	)

	# Seeded pick from top N closest.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + SEED_OFFSET_LAKE_FALLBACK
	var top_n: int = min(FALLBACK_PICK_TOP_N, candidates.size())
	var pick_index: int = rng.randi_range(0, top_n - 1)
	var anchor: Vector2i = candidates[pick_index]

	# Place NxN water square.
	for dx in range(FALLBACK_LAKE_SIZE):
		for dy in range(FALLBACK_LAKE_SIZE):
			var pos: Vector2i = Vector2i(anchor.x + dx, anchor.y + dy)
			world.tiles[pos] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)

func _clamp_spawn_area_water_max(world: GridWorld, seed: int) -> void:
	var water_tiles: Array[Vector2i] = []
	for x in range(-SPAWN_AREA_RADIUS, SPAWN_AREA_RADIUS):
		for y in range(-SPAWN_AREA_RADIUS, SPAWN_AREA_RADIUS):
			var pos := Vector2i(x, y)
			if world.tiles.has(pos) and world.tiles[pos].is_water():
				water_tiles.append(pos)

	if water_tiles.size() <= SPAWN_AREA_MAX_WATER:
		return

	var excess: int = water_tiles.size() - SPAWN_AREA_MAX_WATER

	# Edge tiles first (low water-neighbor count) — shrink lakes from outside.
	var neighbor_counts: Dictionary = {}
	for pos in water_tiles:
		var n: int = 0
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var npos: Vector2i = pos + offset
			if world.tiles.has(npos) and world.tiles[npos].is_water():
				n += 1
		neighbor_counts[pos] = n

	water_tiles.sort_custom(func(a, b):
		var na: int = int(neighbor_counts[a])
		var nb: int = int(neighbor_counts[b])
		if na != nb:
			return na < nb
		var da: int = a.x * a.x + a.y * a.y
		var db: int = b.x * b.x + b.y * b.y
		if da != db:
			return da > db   # FAR first
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed + SEED_OFFSET_LAKE_CEILING
	var pick_pool_size: int = min(int(excess * 1.5), water_tiles.size())
	var pool: Array[Vector2i] = water_tiles.slice(0, pick_pool_size)
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var picks: Array[Vector2i] = pool.slice(0, excess)

	for pos in picks:
		world.tiles.erase(pos)

# ---------- helpers ----------

func _count_spawn_water(world: GridWorld) -> int:
	var n: int = 0
	for x in range(-SPAWN_AREA_RADIUS, SPAWN_AREA_RADIUS):
		for y in range(-SPAWN_AREA_RADIUS, SPAWN_AREA_RADIUS):
			var pos := Vector2i(x, y)
			if world.tiles.has(pos) and world.tiles[pos].is_water():
				n += 1
	return n

func _is_NxN_clear(world: GridWorld, anchor: Vector2i, n: int) -> bool:
	for dx in range(n):
		for dy in range(n):
			var pos: Vector2i = Vector2i(anchor.x + dx, anchor.y + dy)
			if world.tiles.has(pos):
				return false
	return true

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= WORLD_MIN and pos.x < WORLD_MAX and pos.y >= WORLD_MIN and pos.y < WORLD_MAX

## Deterministic 3-input hash returning a float in [0, 1).
## Pure function of (seed, x, y) — used for per-region rolls and per-tile
## tree spawn within forest clusters.
static func _hash3_unit(seed: int, x: int, y: int) -> float:
	var h: int = seed
	h = (h * 73856093) ^ (x * 19349663)
	h = (h * 83492791) ^ (y * 122949829)
	h = h ^ (h >> 13)
	h = h * 1274126177
	h = h ^ (h >> 16)
	h = h & 0x7FFFFFFF
	return float(h) / float(0x7FFFFFFF)
