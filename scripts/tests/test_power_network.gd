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

const TEST_SAVE_PATH: String = "user://test_power_network.json"

static func test_name() -> String:
	return "power network (topology + generator + consumer + linear satisfaction + save)"

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

	# ===========================================================================
	# (6) GENERATOR JOINS NETWORK — water wheel adjacent to pole contributes
	# MAX_OUTPUT (10) to that network's supply pool when active.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	# Paint a strip of stone + a water tile next to where the wheel will be.
	# Wheel is 2x2, so paint two rows. Also paint y=6 for the pole row's
	# southern neighbor of the wheel.
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	# Water tile at (3, 5) — wheel will be at (4, 5) covering (4,5)(5,5)(4,6)(5,6).
	# Water at (3, 5) is adjacent to (4, 5) — the wheel's west edge.
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	# Pole east of the wheel at (6, 5). Adjacent to wheel's (5, 5) cell.
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	# Place wheel facing west (DIR_W). DIR_W is Belt.DIR_W.
	if not world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W):
		_disconnect(world)
		return { "ok": false, "message": "(6) could not place water wheel at (4,5) — check water-overlay setup" }
	# Tick once to populate output_active.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	# Now run update_supply_demand explicitly (per-tick orchestrator will be
	# hooked into _on_tick in Task 7; for now call directly).
	PowerNetwork.update_supply_demand(world)
	# Verify: pole's component has supply >= MAX_OUTPUT.
	var comp_6: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, comp_6 >= 0, "(6) pole should be in a network, got comp_id %d" % comp_6)
	if comp_6 >= 0:
		var supply_6: int = PowerNetwork.supply_for(world, comp_6)
		_check(failures, supply_6 == WaterWheel.MAX_OUTPUT,
			"(6) network supply should equal MAX_OUTPUT (%d), got %d" % [WaterWheel.MAX_OUTPUT, supply_6])
		# Sanity: wheel's output_active should be true.
		var wheel_b: Building = world.building_at(Vector2i(4, 5))
		_check(failures, bool(wheel_b.state.get("output_active", false)),
			"(6) wheel should be output_active = true (water at (3,5) adjacent)")

	# ===========================================================================
	# (7) CONSUMER JOINS NETWORK — lamp adjacent to pole contributes DEMAND
	# to that network's demand pool.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	# Place pole at (5, 5), lamp at (6, 5) (adjacent).
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5))
	world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(6, 5))
	# update_supply_demand to populate demand.
	PowerNetwork.update_supply_demand(world)
	var comp_7: int = PowerNetwork.network_id_at(world, Vector2i(5, 5))
	_check(failures, comp_7 >= 0, "(7) pole should be in a network, got comp_id %d" % comp_7)
	if comp_7 >= 0:
		var demand_7: int = PowerNetwork.demand_for(world, comp_7)
		_check(failures, demand_7 == ElectricLamp.DEMAND,
			"(7) network demand should equal lamp DEMAND (%d), got %d" % [ElectricLamp.DEMAND, demand_7])


	# ===========================================================================
	# (8) SUPPLY SUFFICIENT — wheel (10) + lamp (1), satisfaction == 1.0.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	# Paint stone for both 2x2 footprint rows (wheel covers y=5+y=6).
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	# Layout: water (3,5), wheel (4,5) facing west, pole (6,5), lamp (7,5).
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(7, 5))
	# Tick once to populate wheel's output_active.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	# update_supply_demand now also runs as part of _on_tick (pre-pass).
	# But the test runner has TickSystem paused (test_runner.gd line 53),
	# so _on_tick doesn't fire automatically when tests emit ticks. Call
	# update_supply_demand explicitly to populate the state.
	PowerNetwork.update_supply_demand(world)
	var comp_8: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, comp_8 >= 0, "(8) pole should be in a network")
	if comp_8 >= 0:
		var sat_8: float = PowerNetwork.satisfaction_for(world, comp_8)
		_check(failures, abs(sat_8 - 1.0) < 0.001,
			"(8) satisfaction should be 1.0 (supply 10 > demand 1), got %f" % sat_8)
		# Tick lamp again to update its cached satisfaction.
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		var lamp_8: Building = world.building_at(Vector2i(7, 5))
		_check(failures, abs(float(lamp_8.state.get("satisfaction", -1.0)) - 1.0) < 0.001,
			"(8) lamp.state.satisfaction should be 1.0, got %f" % float(lamp_8.state.get("satisfaction", -1.0)))

	# ===========================================================================
	# (9) BROWNOUT — 1 wheel (10 supply) + 12+ lamps (12+ demand). Sat < 1.0.
	# Layout: stone strip 0..30, water at (3,5), wheel at (4,5) facing west,
	# chain of poles at 6/11/16/21/26 (5-tile spacing → all connected),
	# many lamps around those poles.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 30):
		for y in range(3, 8):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	# Chain of poles at 5-tile spacing — all in same component.
	for px in [6, 11, 16, 21, 26]:
		world.place_building(Buildings.Type.POWER_POLE, Vector2i(px, 5))
	# Place lamps adjacent to those poles. Use y=4 and y=6 (above/below
	# the pole row) plus column-adjacent cells where available.
	var lamps_placed: int = 0
	for px in [6, 11, 16, 21, 26]:
		# y=4 and y=6 for each pole — 2 lamps per pole × 5 poles = 10 lamps.
		for ly in [4, 6]:
			if world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(px, ly)):
				lamps_placed += 1
		# Column-adjacent cells (px-1, 5) and (px+1, 5) where not already taken.
		for dx in [-1, 1]:
			var col: int = px + dx
			if col == 4 or col == 5:  # wheel zone
				continue
			var taken: bool = false
			for other_px in [6, 11, 16, 21, 26]:
				if col == other_px:
					taken = true
					break
			if taken:
				continue
			if world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(col, 5)):
				lamps_placed += 1
	# Guard: confirm we actually placed enough lamps to force brownout. The
	# layout above targets ~12+ lamps adjacent to the 5 poles; if a future
	# place_building regression silently rejects placements, the brownout
	# precondition below could pass for the wrong reason. Lock the count.
	_check(failures, lamps_placed >= 12,
		"(9) expected >=12 lamps placed for brownout layout, got %d (place_building regression?)" % lamps_placed)
	# Tick once to populate wheel's output_active, then update_supply_demand.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var comp_9: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, comp_9 >= 0, "(9) pole should be in a network")
	if comp_9 >= 0:
		var sup_9: int = PowerNetwork.supply_for(world, comp_9)
		var dem_9: int = PowerNetwork.demand_for(world, comp_9)
		var sat_9: float = PowerNetwork.satisfaction_for(world, comp_9)
		var expected_sat: float = min(1.0, float(sup_9) / float(max(1, dem_9)))
		_check(failures, abs(sat_9 - expected_sat) < 0.001,
			"(9) brownout satisfaction should be %f (supply %d / demand %d), got %f" % [expected_sat, sup_9, dem_9, sat_9])
		# Sanity: brownout actually occurred (sup < dem).
		_check(failures, sup_9 < dem_9, "(9) brownout precondition: supply %d should be < demand %d" % [sup_9, dem_9])

	# ===========================================================================
	# (10) SAVE ROUND-TRIP — place network, save, reload, verify topology
	# reconstructed and lamp still powered. Validates that save schema
	# unchanged at v18 handles append-only enum entries (POWER_POLE /
	# WATER_WHEEL / ELECTRIC_LAMP) and that .get()-defaulted state fields
	# survive serialization. Network maps (_pole_component etc.) are NOT
	# serialized — rebuilt on load via dirty-flag.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	# Paint stone for both 2x2 wheel footprint rows.
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	# Water at (3,5). For save-roundtrip we MUST record in tile_modifications
	# so SaveSystem persists it (procgen regenerates canonical tiles on load;
	# tile_modifications overlays player edits). Direct `tiles[pos] = ...` is
	# in-memory only and would be lost across save/load. Distinct Tile.new()
	# instances per dict matches the pattern in set_overlay (no shared refs).
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.tile_modifications[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(11, 5))
	world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(7, 5))
	# Pre-save: tick + update + verify lamp powered.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var pre_comp: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	var pre_sat: float = PowerNetwork.satisfaction_for(world, pre_comp)
	_check(failures, abs(pre_sat - 1.0) < 0.001, "(10) pre-save: lamp should be fully powered, got sat %f" % pre_sat)

	# Save via SaveSystem (matches test_inserter.gd sub-case (15) pattern).
	var orig_path_10: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	var player_a_10 := Node2D.new()
	parent.add_child(player_a_10)
	if not SaveSystem.save_game(world, player_a_10, Inventory.new(16)):
		SaveSystem.save_path = orig_path_10
		_disconnect(world)
		player_a_10.queue_free()
		# Mirror load-failure cleanup: remove any partial save file even on
		# the save-failure path (unlikely but possible — keeps reruns clean).
		if FileAccess.file_exists(TEST_SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
		return { "ok": false, "message": "(10) save_game failed" }

	# Load into a fresh world.
	_disconnect(world)
	world = GridWorldScript.new()
	parent.add_child(world)
	var player_b_10 := Node2D.new()
	parent.add_child(player_b_10)
	var result_10: LoadResult = SaveSystem.load_game(world, player_b_10, Inventory.new(16))
	if not result_10.success:
		SaveSystem.save_path = orig_path_10
		_disconnect(world)
		player_a_10.queue_free()
		player_b_10.queue_free()
		if FileAccess.file_exists(TEST_SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
		return { "ok": false, "message": "(10) load_game failed: %s" % result_10.error_message }

	# Post-load: tick + update + verify lamp still powered (network reconstructed).
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var post_comp: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, post_comp >= 0, "(10) post-load: pole at (6,5) should be in a network, got %d" % post_comp)
	if post_comp >= 0:
		var post_sat: float = PowerNetwork.satisfaction_for(world, post_comp)
		_check(failures, abs(post_sat - 1.0) < 0.001, "(10) post-load: lamp should still be fully powered, got sat %f" % post_sat)
		# Sanity: wheel + 2 poles + 1 lamp all loaded as the correct types.
		_check(failures, world.has_building_at(Vector2i(4, 5)) and world.building_at(Vector2i(4, 5)).type == Buildings.Type.WATER_WHEEL,
			"(10) wheel at (4,5) should be loaded")
		_check(failures, world.has_building_at(Vector2i(6, 5)) and world.building_at(Vector2i(6, 5)).type == Buildings.Type.POWER_POLE,
			"(10) pole at (6,5) should be loaded")
		_check(failures, world.has_building_at(Vector2i(11, 5)) and world.building_at(Vector2i(11, 5)).type == Buildings.Type.POWER_POLE,
			"(10) pole at (11,5) should be loaded")
		_check(failures, world.has_building_at(Vector2i(7, 5)) and world.building_at(Vector2i(7, 5)).type == Buildings.Type.ELECTRIC_LAMP,
			"(10) lamp at (7,5) should be loaded")

	# Cleanup test save file + restore path.
	SaveSystem.save_path = orig_path_10
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	player_a_10.queue_free()
	player_b_10.queue_free()

	_disconnect(world)

	if failures.is_empty():
		return { "ok": true, "message": "10 sub-cases pass: + save round-trip (network rebuilt on load)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

static func _disconnect(world) -> void:
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.queue_free()
