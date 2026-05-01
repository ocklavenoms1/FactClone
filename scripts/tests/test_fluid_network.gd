extends RefCounted

## Fluid network resolver test.
##
## Builds explicit pipe + pump topologies and asserts that
## fluid_available_at() answers correctly for various adjacencies.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "fluid network connectivity"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	var world = GridWorldScript.new()
	parent.add_child(world)

	# Seed a single water tile at (0, 0) so a pump can sit next to it.
	world.tiles[Vector2i(0, 0)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)

	# Lay overlay (stone) at (1,0)..(5,0) so we can place stuff there.
	for x in range(1, 6):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)

	# Pump at (1,0) — adjacent to water at (0,0).
	if not world.place_building(Buildings.Type.PUMP, Vector2i(1, 0)):
		return _fail(world, "could not place pump adjacent to water")

	# Pump in the middle of nowhere (no water neighbor) should fail to place.
	world.set_overlay(Vector2i(20, 20), Terrain.Overlay.STONE)
	var rejected_pump: bool = world.place_building(Buildings.Type.PUMP, Vector2i(20, 20))
	_check(failures, not rejected_pump, "pump placement should fail without adjacent water")

	# Pipes connecting pump → consumer position.
	for x in range(2, 5):
		if not world.place_building(Buildings.Type.PIPE, Vector2i(x, 0)):
			return _fail(world, "could not place pipe at (%d, 0)" % x)

	# Position (5, 0) is adjacent to a pipe; (4, 0) is in same network as pump.
	# Therefore fluid_available_at((5, 0)) should be true.
	_check(failures, world.fluid_available_at(Vector2i(5, 0)), "fluid should be available at (5,0): adjacent to pipe network with pump")

	# Position (10, 0): far from any pipe → no fluid.
	_check(failures, not world.fluid_available_at(Vector2i(10, 0)), "fluid should NOT be available at (10,0): no adjacent pipe")

	# Disconnect by removing the middle pipe. Network splits into [pipe@2]
	# (still connected to pump) and [pipe@4] (orphan, no pump).
	if not world.remove_building_at(Vector2i(3, 0)):
		return _fail(world, "could not remove middle pipe")

	# (2,0) side: still connected to pump → fluid available adjacent.
	#   But the consumer needs to be adjacent to a pipe; let's check (2,1)
	#   which is south of pipe@2 (still in pump's component).
	_check(failures, world.fluid_available_at(Vector2i(2, 1)), "after disconnect, fluid still available adjacent to pump-side pipe")

	# (5,0) side: pipe@4 is now an orphan; fluid_available_at((5,0)) should be false.
	_check(failures, not world.fluid_available_at(Vector2i(5, 0)), "after disconnect, fluid NOT available adjacent to orphan pipe")

	# Add a pump that's cardinally adjacent to pipe@4 so the orphan pipe
	# joins a new pump-bearing component. Need: water tile next to the pump
	# location, and the pump location adjacent to pipe@4 (cardinal).
	# pipe@4 is at (4, 0). (3, 0) is now empty (we removed the pipe there).
	# Place water at (3, 1) (south of (3, 0)), then pump at (3, 0).
	world.tiles[Vector2i(3, 1)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	# (3, 0) already has a stone overlay from the earlier loop.
	if not world.place_building(Buildings.Type.PUMP, Vector2i(3, 0)):
		return _fail(world, "could not place second pump at (3,0)")

	# pipe@4 is cardinally adjacent to pump@(3,0) → in same component.
	# Consumer at (5,0) (east of pipe@4) → fluid available again.
	_check(failures, world.fluid_available_at(Vector2i(5, 0)), "second pump restores fluid availability at (5,0)")

	# Cleanup.
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "pipe/pump connectivity behaves as specified" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _fail(world, msg: String) -> Dictionary:
	if world != null:
		if TickSystem.tick.is_connected(world._on_tick):
			TickSystem.tick.disconnect(world._on_tick)
		world.queue_free()
	return { "ok": false, "message": msg }
