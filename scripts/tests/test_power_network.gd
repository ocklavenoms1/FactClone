extends RefCounted

## Power network resolver tests.
##
## Sub-cases cover topology (single pole, in-range merge, out-of-range
## separation, bridge merge, split on bridge removal), generator/consumer
## association (water wheel adjacency, lamp adjacency), linear
## satisfaction (supply >= demand, brownout), and save round-trip.
##
## Sub-cases (1)-(5) shipped in Task 3 (topology only). Sub-cases (6)-(10)
## land in Tasks 5, 6, 7, 9 respectively.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "power network (topology)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var world = GridWorldScript.new()
	parent.add_child(world)

	# Lay overlay (STONE) across a horizontal strip so we can place poles
	# on any column 0..30. POWER_POLE accepts NONE/STONE/PATH/SOIL_TILLED
	# so STONE is fine.
	for x in range(0, 31):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)

	# ===========================================================================
	# (1) PLACE SINGLE POLE — component id 0 assigned.
	# ===========================================================================
	if not world.place_building(Buildings.Type.POWER_POLE, Vector2i(0, 5)):
		_disconnect(world)
		return { "ok": false, "message": "(1) could not place single pole at (0,5)" }
	# Trigger topology rebuild via a query.
	var comp_1: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	_check(failures, comp_1 == 0, "(1) single pole should be component 0, got %d" % comp_1)

	# ===========================================================================
	# (2) TWO POLES IN RANGE — within 5-tile Chebyshev, same component.
	# Place 2nd pole 5 tiles away (just at the edge of the connection range).
	# ===========================================================================
	if not world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5)):
		_disconnect(world)
		return { "ok": false, "message": "(2) could not place pole at (5,5)" }
	var comp_2a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var comp_2b: int = PowerNetwork.network_id_at(world, Vector2i(5, 5))
	_check(failures, comp_2a == comp_2b, "(2) poles at (0,5) and (5,5) should share component, got %d vs %d" % [comp_2a, comp_2b])

	# ===========================================================================
	# (3) TWO POLES OUT OF RANGE — 6+ tiles apart, different components.
	# Reset world, place poles at (0,5) and (11,5) (Chebyshev dist 11 > 5).
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 31):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(0, 5))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(11, 5))
	var comp_3a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var comp_3b: int = PowerNetwork.network_id_at(world, Vector2i(11, 5))
	_check(failures, comp_3a != comp_3b, "(3) poles at (0,5) and (11,5) should be different components, both got %d" % comp_3a)

	# ===========================================================================
	# (4) BRIDGE MERGES NETWORKS — place a third pole linking two separate.
	# Layout: (0,5) and (10,5) are 10 apart → different networks.
	# Bridge at (5,5): 5 tiles from each → in range of both → merges.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 31):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(0, 5))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(10, 5))
	# Before bridge: different components.
	var pre_bridge_a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var pre_bridge_b: int = PowerNetwork.network_id_at(world, Vector2i(10, 5))
	_check(failures, pre_bridge_a != pre_bridge_b, "(4) pre-bridge: (0,5) and (10,5) should be separate, both got %d" % pre_bridge_a)
	# Place bridge.
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5))
	var post_bridge_a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var post_bridge_b: int = PowerNetwork.network_id_at(world, Vector2i(10, 5))
	var post_bridge_mid: int = PowerNetwork.network_id_at(world, Vector2i(5, 5))
	_check(failures, post_bridge_a == post_bridge_b, "(4) post-bridge: ends should share component, got %d vs %d" % [post_bridge_a, post_bridge_b])
	_check(failures, post_bridge_a == post_bridge_mid, "(4) bridge itself should share component with both ends")

	# ===========================================================================
	# (5) REMOVE BRIDGE SPLITS NETWORK — remove the middle pole, network
	# splits back into two separate components.
	# ===========================================================================
	world.remove_building_at(Vector2i(5, 5))
	var post_remove_a: int = PowerNetwork.network_id_at(world, Vector2i(0, 5))
	var post_remove_b: int = PowerNetwork.network_id_at(world, Vector2i(10, 5))
	_check(failures, post_remove_a != post_remove_b, "(5) post-remove: ends should be separate components again, both got %d" % post_remove_a)

	_disconnect(world)

	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: single pole + in-range merge + out-of-range + bridge merge + split on remove" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

static func _disconnect(world) -> void:
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.queue_free()
