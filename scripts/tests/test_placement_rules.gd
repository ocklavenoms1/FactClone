extends RefCounted

## Placement rules unit test (base/overlay model).
##
## Asserts Terrain.can_place_overlay rules + GridWorld.set_overlay /
## clear_tile semantics. Catches regressions on terrain configuration.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "terrain placement rules (base/overlay)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# --- can_place_overlay: pure rule lookups ---
	# Soil only on bare grass.
	_check(failures, Terrain.can_place_overlay(Terrain.Overlay.SOIL_TILLED, Terrain.Base.GRASS, Terrain.Overlay.NONE), "soil on bare grass should pass")
	_check(failures, not Terrain.can_place_overlay(Terrain.Overlay.SOIL_TILLED, Terrain.Base.GRASS, Terrain.Overlay.STONE), "soil over stone should fail (must clear stone first)")
	_check(failures, not Terrain.can_place_overlay(Terrain.Overlay.SOIL_TILLED, Terrain.Base.WATER, Terrain.Overlay.NONE), "soil on water should fail (no overlays on water)")

	# Path on grass or soil.
	_check(failures, Terrain.can_place_overlay(Terrain.Overlay.PATH, Terrain.Base.GRASS, Terrain.Overlay.NONE), "path on bare grass should pass")
	_check(failures, Terrain.can_place_overlay(Terrain.Overlay.PATH, Terrain.Base.GRASS, Terrain.Overlay.SOIL_TILLED), "path over soil should pass")
	_check(failures, not Terrain.can_place_overlay(Terrain.Overlay.PATH, Terrain.Base.WATER, Terrain.Overlay.NONE), "path on water should fail")

	# Stone on grass, soil, path.
	_check(failures, Terrain.can_place_overlay(Terrain.Overlay.STONE, Terrain.Base.GRASS, Terrain.Overlay.NONE), "stone on bare grass should pass")
	_check(failures, Terrain.can_place_overlay(Terrain.Overlay.STONE, Terrain.Base.GRASS, Terrain.Overlay.SOIL_TILLED), "stone over soil should pass")
	_check(failures, Terrain.can_place_overlay(Terrain.Overlay.STONE, Terrain.Base.GRASS, Terrain.Overlay.PATH), "stone over path should pass")
	_check(failures, not Terrain.can_place_overlay(Terrain.Overlay.STONE, Terrain.Base.WATER, Terrain.Overlay.NONE), "stone on water should fail")

	# Idempotent same-overlay painting.
	_check(failures, Terrain.can_place_overlay(Terrain.Overlay.STONE, Terrain.Base.GRASS, Terrain.Overlay.STONE), "stone over stone should pass (idempotent)")

	# Hotbar contents are all valid overlays (not NONE, not out of range).
	# We can't directly check "water not in HOTBAR_ORDER" because water is a base
	# and HOTBAR_ORDER holds overlays — different namespaces. The structural check
	# is: every entry must be a defined overlay in OVERLAY_DATA.
	for h in Terrain.HOTBAR_ORDER:
		_check(failures, Terrain.OVERLAY_DATA.has(h), "HOTBAR_ORDER contains undefined overlay value %d" % h)
		_check(failures, h != Terrain.Overlay.NONE, "HOTBAR_ORDER must not contain Overlay.NONE")

	# --- GridWorld integration ---
	var world = GridWorldScript.new()
	parent.add_child(world)

	# Pre-seed a water tile (simulating world-gen).
	world.tiles[Vector2i(0, 0)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)

	# Stone overlay on water tile: should fail with toast-ready error.
	var ok: bool = world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	_check(failures, not ok, "set_overlay stone on water should return false")
	_check(failures, world.last_place_error != "", "last_place_error must be populated after failure")
	_check(failures, world.is_water_at(Vector2i(0, 0)), "water tile must remain water after failed paint")

	# Soil on bare grass at (1, 0): should pass.
	ok = world.set_overlay(Vector2i(1, 0), Terrain.Overlay.SOIL_TILLED)
	_check(failures, ok, "set_overlay soil on bare grass should return true")
	_check(failures, world.overlay_at(Vector2i(1, 0)) == Terrain.Overlay.SOIL_TILLED, "overlay should now be tilled soil")

	# Stone over the soil at (1, 0): should pass (escalating ladder).
	ok = world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	_check(failures, ok, "set_overlay stone over soil should return true")
	_check(failures, world.overlay_at(Vector2i(1, 0)) == Terrain.Overlay.STONE, "overlay should now be stone")

	# Try to demote stone → soil (not allowed by ladder).
	ok = world.set_overlay(Vector2i(1, 0), Terrain.Overlay.SOIL_TILLED)
	_check(failures, not ok, "set_overlay soil over stone should fail (no demotion)")
	_check(failures, world.overlay_at(Vector2i(1, 0)) == Terrain.Overlay.STONE, "tile should still be stone after failed demote")

	# RMB-clear water: should be a silent no-op (water is base; nothing to remove).
	var removed: bool = world.clear_tile(Vector2i(0, 0))
	_check(failures, removed, "clear_tile on bare water should return true (silent no-op)")
	_check(failures, world.is_water_at(Vector2i(0, 0)), "water tile must remain water after RMB")

	# RMB-clear stone: removes the overlay, reveals grass underneath.
	removed = world.clear_tile(Vector2i(1, 0))
	_check(failures, removed, "clear_tile on stone overlay should return true")
	_check(failures, world.overlay_at(Vector2i(1, 0)) == Terrain.Overlay.NONE, "overlay should clear to NONE after RMB")
	_check(failures, world.base_at(Vector2i(1, 0)) == Terrain.Base.GRASS, "base should be GRASS after clearing overlay")

	# Building placement still respects overlay.
	world.set_overlay(Vector2i(2, 0), Terrain.Overlay.SOIL_TILLED)
	_check(failures, world.place_building(Buildings.Type.PLANTER, Vector2i(2, 0)), "planter on tilled soil should succeed")
	_check(failures, not world.place_building(Buildings.Type.PLANTER, Vector2i(0, 0)), "planter on water should fail")
	_check(failures, not world.place_building(Buildings.Type.PLANTER, Vector2i(99, 99)), "planter on bare grass should fail")

	# Cleanup.
	for w in [world]:
		if TickSystem.tick.is_connected(w._on_tick):
			TickSystem.tick.disconnect(w._on_tick)
		w.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all overlay rules + lake placement verified" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
