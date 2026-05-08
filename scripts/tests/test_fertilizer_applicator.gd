extends RefCounted

## Fertilizer Applicator tests (session-soil-exhaustion-3-5).
##
## Locks in the automation tier of the fertilizer chain: a custom-tick
## building that pulls compost from belts/drag-drop and applies it to
## the most-depleted eligible tile in its 5×5 coverage at a rate-limited
## interval.
##
## Sub-suites cover:
##   1. Apply rate — pre-load 5 LOW, tick 30 sec, verify 5 applies.
##      Plus: BLOCKED state when no eligible tiles exist (steady-state hold).
##   2. Tier preference — buffer with both LOW and MID, verify MID consumed first.
##      Plus: same-cycle subsequent tiles take MID until exhausted, then LOW.
##   3. Most-depleted-first targeting — tiles with soil 30/50/70 in coverage,
##      verify soil-30 fertilized first; tiebreak topmost-leftmost.
##   4. Coverage edge case — applicator near world edge; out-of-bounds
##      tiles excluded from scan (no crash, no spurious fertilization).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "fertilizer applicator (apply rate + tier preference + most-depleted + edge of world)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. Apply rate ----------
	# Place an applicator. Pre-load 5 LOW into in_buffer. Set up 5 depleted
	# tiles in coverage so each apply has a target. Tick 30 sec (600 ticks).
	# Expect 5 applies: in_buffer empties + 5 tiles fertilized.
	var world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed: %s" % world.last_building_place_error }
	var app: Building = world.building_at(Vector2i(0, 0))
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, 5]]
	# 5 depleted tiles in coverage (within 5×5 around (0,0)).
	var depleted_tiles: Array = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(2, 0),
	]
	for pos in depleted_tiles:
		world.tile_soil_modifications[pos] = 50
	# Tick 600 sim ticks (30 sec at 20 tps).
	for _i in 600:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Verify 5 applies happened.
	var fertilized_count: int = 0
	for pos in depleted_tiles:
		if world.tile_fertilizer_tier(pos) == Items.Type.COMPOST_LOW:
			fertilized_count += 1
	_check(failures, fertilized_count == 5,
		"after 30 sec: expected all 5 depleted tiles fertilized, got %d" % fertilized_count)
	# Buffer should be empty.
	var buf_total: int = _buffer_total(app.state.get("in_buffer", []))
	_check(failures, buf_total == 0,
		"in_buffer should be empty after 5 applies, got %d items" % buf_total)
	# State should be IDLE (no input remaining).
	_check(failures, int(app.state.get("state", -1)) == FertilizerApplicator.STATE_IDLE,
		"after exhaustion: expected STATE_IDLE, got %d" % int(app.state.get("state", -1)))

	# ---------- 1b. BLOCKED steady-state when no eligible tiles ----------
	# Re-load buffer but leave NO eligible tiles (all depleted tiles already
	# fertilized at LOW; with LOW available, no upgrade possible).
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, 3]]
	# Tick another 200 sim ticks (10 sec — enough for ≥1 apply attempt).
	for _i in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Buffer untouched (no apply happened).
	var buf_total_after_blocked: int = _buffer_total(app.state.get("in_buffer", []))
	_check(failures, buf_total_after_blocked == 3,
		"BLOCKED: buffer should remain at 3 (no apply), got %d" % buf_total_after_blocked)
	_check(failures, int(app.state.get("state", -1)) == FertilizerApplicator.STATE_BLOCKED,
		"BLOCKED: expected STATE_BLOCKED, got %d" % int(app.state.get("state", -1)))

	_disconnect(world); world.queue_free()

	# ---------- 2. Tier preference (MID before LOW) ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (tier test)" }
	app = world.building_at(Vector2i(0, 0))
	# Buffer: 1 LOW + 1 MID. MID should be consumed first.
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, 1], [Items.Type.COMPOST_MID, 1]]
	# 1 depleted tile in coverage.
	world.tile_soil_modifications[Vector2i(1, 0)] = 50
	# Tick 110 sim ticks (slightly past one apply cycle).
	for _i in 110:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Verify the tile got MID, not LOW.
	_check(failures, world.tile_fertilizer_tier(Vector2i(1, 0)) == Items.Type.COMPOST_MID,
		"tier preference: tile should have MID (not LOW), got tier %d" % world.tile_fertilizer_tier(Vector2i(1, 0)))
	# MID consumed (count 0), LOW intact (count 1).
	_check(failures, _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_MID) == 0,
		"tier preference: MID should be consumed, but count is %d" % _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_MID))
	_check(failures, _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_LOW) == 1,
		"tier preference: LOW should be untouched, but count is %d" % _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_LOW))

	# Subsequent tile: with MID gone, LOW should be used. Add another
	# eligible tile + tick another cycle.
	world.tile_soil_modifications[Vector2i(2, 0)] = 50
	for _i in 110:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, world.tile_fertilizer_tier(Vector2i(2, 0)) == Items.Type.COMPOST_LOW,
		"tier fallthrough: tile (2,0) should have LOW after MID exhausted, got tier %d" % world.tile_fertilizer_tier(Vector2i(2, 0)))

	_disconnect(world); world.queue_free()

	# ---------- 3. Most-depleted-first targeting ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(50, 50), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (most-depleted test)" }
	app = world.building_at(Vector2i(50, 50))
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, 1]]
	# Three tiles in coverage with different soil values.
	world.tile_soil_modifications[Vector2i(51, 50)] = 70   # least depleted
	world.tile_soil_modifications[Vector2i(52, 50)] = 50   # middle
	world.tile_soil_modifications[Vector2i(49, 50)] = 30   # MOST depleted — should win
	# Tick one apply cycle.
	for _i in 110:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Verify the most-depleted tile (soil=30) got fertilized.
	_check(failures, world.tile_fertilizer_tier(Vector2i(49, 50)) == Items.Type.COMPOST_LOW,
		"most-depleted-first: tile soil=30 should be fertilized, tier=%d" % world.tile_fertilizer_tier(Vector2i(49, 50)))
	_check(failures, world.tile_fertilizer_tier(Vector2i(51, 50)) == -1,
		"most-depleted-first: tile soil=70 should NOT be fertilized")
	_check(failures, world.tile_fertilizer_tier(Vector2i(52, 50)) == -1,
		"most-depleted-first: tile soil=50 should NOT be fertilized")

	# Tiebreak: same soil → topmost-leftmost (smaller y, then smaller x).
	# Set up two tiles at soil=20 with different positions; soil-20 wins
	# over soil=30 (lower); among the two soil=20s, topmost-leftmost wins.
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, 1]]
	world.tile_soil_modifications[Vector2i(51, 49)] = 20   # north → smaller y, wins tiebreak
	world.tile_soil_modifications[Vector2i(51, 51)] = 20   # south → larger y, loses
	for _i in 110:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, world.tile_fertilizer_tier(Vector2i(51, 49)) == Items.Type.COMPOST_LOW,
		"tiebreak: north tile (smaller y) should win, got tier %d" % world.tile_fertilizer_tier(Vector2i(51, 49)))
	_check(failures, world.tile_fertilizer_tier(Vector2i(51, 51)) == -1,
		"tiebreak: south tile should NOT be fertilized (lost tiebreak)")

	_disconnect(world); world.queue_free()

	# ---------- 4. Coverage edge case (world edge) ----------
	# Place applicator at WORLD_MIN x — left half of coverage extends
	# out-of-bounds. Verify no crash, no spurious fertilization, eligible
	# scan filters correctly.
	world = GridWorldScript.new()
	parent.add_child(world)
	var edge_pos: Vector2i = Vector2i(WorldGenerator.WORLD_MIN, 0)   # (-256, 0)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, edge_pos, Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement at world edge failed" }
	app = world.building_at(edge_pos)
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, 1]]
	# Set up one in-bounds depleted tile in coverage. The 5×5 around
	# (-256, 0) extends from x=(-258 to -254). Tiles at x ∈ {-258, -257}
	# are out-of-bounds (x < WORLD_MIN). In-bounds set: x ∈ {-256, -255, -254}.
	# Place an eligible tile at the in-bounds easternmost cell.
	world.tile_soil_modifications[Vector2i(-254, 0)] = 30
	for _i in 110:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# In-bounds tile should be fertilized.
	_check(failures, world.tile_fertilizer_tier(Vector2i(-254, 0)) == Items.Type.COMPOST_LOW,
		"edge: in-bounds tile should be fertilized, tier %d" % world.tile_fertilizer_tier(Vector2i(-254, 0)))
	# Out-of-bounds tile should NOT be in tile_fertilizer_state.
	_check(failures, world.tile_fertilizer_tier(Vector2i(-258, 0)) == -1,
		"edge: out-of-bounds tile should never get fertilizer state")
	# No crash by reaching this assertion. (Crash would have aborted the test.)

	_disconnect(world); world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all 4 sub-suites passed (apply rate + tier preference + most-depleted + edge of world)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _buffer_total(buf: Array) -> int:
	var n: int = 0
	for entry in buf:
		n += int(entry[1])
	return n

static func _buffer_count(buf: Array, item_type: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
