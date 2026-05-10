extends RefCounted

## Building walkability tests (Cluster C, post-session-inserter-fast-filter).
##
## Locks in the building-blocks-movement mechanic:
##   1. Belts are walkable (only opt-in walkable building today).
##   2. Smelters block (default = false).
##   3. Multi-tile (2×2) drill blocks ALL 4 footprint cells, not just anchor.
##   4. Water still blocks regardless of building presence (regression
##      that the new building-layer check doesn't break the tile-base check).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "building walkability (belts walkable, others block, multi-tile + water regression)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- (0) Helper sanity: Buildings.is_walkable per type ----------
	# Walkable: BELT + INSERTER + FAST_INSERTER (thin devices — base is
	# small, mechanism extends overhead/sideways without filling the tile).
	# Blocked: SMELTER + CHEST + PIPE + everything else (default false).
	_check(failures, Buildings.is_walkable(Buildings.Type.BELT),
		"(0) Buildings.is_walkable(BELT) should be true")
	_check(failures, Buildings.is_walkable(Buildings.Type.INSERTER),
		"(0) Buildings.is_walkable(INSERTER) should be true (thin device, arm overhead)")
	_check(failures, Buildings.is_walkable(Buildings.Type.FAST_INSERTER),
		"(0) Buildings.is_walkable(FAST_INSERTER) should be true (same as basic)")
	_check(failures, not Buildings.is_walkable(Buildings.Type.SMELTER),
		"(0) Buildings.is_walkable(SMELTER) should be false (default)")
	_check(failures, not Buildings.is_walkable(Buildings.Type.PIPE),
		"(0) Buildings.is_walkable(PIPE) should be false (per Q4 — pipes blocked)")
	_check(failures, not Buildings.is_walkable(Buildings.Type.CHEST),
		"(0) Buildings.is_walkable(CHEST) should be false")

	# ---------- (1) Belt: walkable. Place belt → is_passable_at returns true ----------
	var world = GridWorldScript.new()
	parent.add_child(world)
	# Stone overlay so belt placement passes.
	world.set_overlay(Vector2i(5, 5), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.BELT, Vector2i(5, 5), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(1) belt placement failed: %s" % world.last_building_place_error }
	_check(failures, world.is_passable_at(Vector2i(5, 5)),
		"(1) tile with belt should be passable (belts are walkable)")
	_disconnect(world); world.queue_free()

	# ---------- (2) Smelter: blocks. Place 2×2 smelter → is_passable_at returns false on anchor ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	# Stone overlay across the 2×2 footprint.
	for dx in 2:
		for dy in 2:
			world.set_overlay(Vector2i(10 + dx, 10 + dy), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.SMELTER, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(2) smelter placement failed: %s" % world.last_building_place_error }
	_check(failures, not world.is_passable_at(Vector2i(10, 10)),
		"(2) tile with smelter (anchor) should NOT be passable")
	_disconnect(world); world.queue_free()

	# ---------- (3) Multi-tile drill: ALL 4 footprint cells block ----------
	# Mining drill is 2×2; verify every cell is impassable, not just anchor.
	# Drill needs a deposit on at least one footprint cell (validate_placement).
	world = GridWorldScript.new()
	parent.add_child(world)
	# Set up a 2×2 grass area with one iron deposit (drill needs ore in footprint).
	for dx in 2:
		for dy in 2:
			var pos := Vector2i(20 + dx, 20 + dy)
			world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
	world.tiles[Vector2i(20, 20)] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.IRON)
	world.resource_state[Vector2i(20, 20)] = {"richness": 50, "original_richness": 50}
	if not world.place_building(Buildings.Type.MINING_DRILL, Vector2i(20, 20), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(3) drill placement failed: %s" % world.last_building_place_error }
	# Each of the 4 footprint cells should be impassable (multi-tile blocking
	# works automatically via the `occupied` map mapping every cell to the
	# building's anchor).
	for dx in 2:
		for dy in 2:
			var cell := Vector2i(20 + dx, 20 + dy)
			_check(failures, not world.is_passable_at(cell),
				"(3) 2×2 drill cell %s should NOT be passable (multi-tile auto-blocks all cells)" % str(cell))
	_disconnect(world); world.queue_free()

	# ---------- (4) Water still blocks (regression for layer 1 = tile base) ----------
	# Pre-Cluster-C, only water blocked. The new building layer must not
	# regress this — a water tile with no building should still report
	# is_passable_at = false.
	world = GridWorldScript.new()
	parent.add_child(world)
	world.tiles[Vector2i(30, 30)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
	_check(failures, not world.is_passable_at(Vector2i(30, 30)),
		"(4) water tile should still block (Cluster C must not regress the tile-base check)")
	# Default-grass tile (no entry in `tiles`) should be passable.
	_check(failures, world.is_passable_at(Vector2i(40, 40)),
		"(4) default-grass tile (no entry in tiles dict) should be passable")
	_disconnect(world); world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "4 sub-suites pass: belts walkable + non-belt buildings block + 2×2 multi-tile blocks all cells + water regression intact" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
