extends Node

## Headless test runner.
##
## Runs in headless mode via:
##   godot --headless --main-scene res://scenes/test_runner.tscn
##
## Each test is a static class with `test_name()` and `run() -> Dictionary`.
## A run result is { "ok": bool, "message": String }.
##
## TestRunner prints PASS/FAIL per test and exits with code 0 if all pass,
## non-zero if any fail. Suitable for a CI loop.

const TESTS: Array = [
	preload("res://scripts/tests/test_placement_rules.gd"),
	preload("res://scripts/tests/test_save_load_roundtrip.gd"),
	preload("res://scripts/tests/test_wheat_to_flour.gd"),
	preload("res://scripts/tests/test_fluid_network.gd"),
	preload("res://scripts/tests/test_mixer_dough.gd"),
	preload("res://scripts/tests/test_thresher_multioutput.gd"),
	preload("res://scripts/tests/test_thresher_prefer_dir.gd"),
	preload("res://scripts/tests/test_thresher_rotation.gd"),
	preload("res://scripts/tests/test_cloth_prefer_dir.gd"),
	preload("res://scripts/tests/test_bag_cap.gd"),
	preload("res://scripts/tests/test_chest_paired_view.gd"),
	preload("res://scripts/tests/test_worldgen_determinism.gd"),
	preload("res://scripts/tests/test_worldgen_distance_scaling.gd"),
	preload("res://scripts/tests/test_worldgen_spawn_safety.gd"),
	preload("res://scripts/tests/test_random_seed_save_roundtrip.gd"),
	preload("res://scripts/tests/test_region_visibility.gd"),
	preload("res://scripts/tests/test_resource_state_modifications_roundtrip.gd"),
	preload("res://scripts/tests/test_tree_harvest_lifecycle.gd"),
	preload("res://scripts/tests/test_mining_drill.gd"),
	preload("res://scripts/tests/test_smelter.gd"),
	preload("res://scripts/tests/test_building_ui.gd"),
	preload("res://scripts/tests/test_building_ui_2.gd"),
	preload("res://scripts/tests/test_building_ui_3.gd"),
	preload("res://scripts/tests/test_building_ui_4.gd"),
	preload("res://scripts/tests/test_soil_exhaustion.gd"),
	preload("res://scripts/tests/test_zoom_trigger_map.gd"),
	preload("res://scripts/tests/test_fertilizer_chain.gd"),
	preload("res://scripts/tests/test_fertilizer_applicator.gd"),
	preload("res://scripts/tests/test_console.gd"),
	preload("res://scripts/tests/test_wasteland.gd"),
	preload("res://scripts/tests/test_save_migration.gd"),
	preload("res://scripts/tests/test_inserter.gd"),
	preload("res://scripts/tests/test_walkability.gd"),
	preload("res://scripts/tests/test_slot_click_handler.gd"),
	preload("res://scripts/tests/test_power_network.gd"),
	preload("res://scripts/tests/test_tooltip_manager.gd"),
	preload("res://scripts/tests/test_item_picker_modal.gd"),
	preload("res://scripts/tests/test_shared_buffer_slots.gd"),
	preload("res://scripts/tests/test_placement_terrain_guards.gd"),
	preload("res://scripts/tests/test_inserter_fuel_conservation.gd"),
	preload("res://scripts/tests/test_electric_inserter.gd"),
	preload("res://scripts/tests/test_electric_rig.gd"),
	preload("res://scripts/tests/test_pole_tiers.gd"),
	preload("res://scripts/tests/test_pole_tier_rig.gd"),
	preload("res://scripts/tests/test_pole_gameplay_rig.gd"),
	preload("res://scripts/tests/test_load_network_invalidation.gd"),
	preload("res://scripts/tests/test_mixed_tier_save_roundtrip.gd"),
	preload("res://scripts/tests/test_inserter_shared_input_cap.gd"),
	preload("res://scripts/tests/test_applicator_wasteland_recovery.gd"),
	preload("res://scripts/tests/test_save_atomicity.gd"),
	preload("res://scripts/tests/test_load_malformed_save.gd"),
	preload("res://scripts/tests/test_quick_load_refresh.gd"),
	# Guards THIS array. Asserts every test_*.gd on disk appears above, because
	# a dropped registration reddens nothing — see the file's header for the
	# incident that motivated it.
	preload("res://scripts/tests/test_registration_completeness.gd"),
]

## Directories that hold save fixtures, for the per-test sidecar scrub below.
## These are exactly the two shapes `SaveSystem._is_test_fixture_path` accepts:
## `user://test_*` at the root, and anything under `user://test_artifacts/`.
const FIXTURE_DIRS: Array = ["user://", "user://test_artifacts/"]

func _ready() -> void:
	# Pause the global tick system so each test can drive ticks manually.
	TickSystem.paused = true
	TickSystem.reset()

	var passed: int = 0
	var failed: int = 0
	print("\n=== Stewardship test suite ===\n")

	for test_class in TESTS:
		var name: String = test_class.test_name()
		var result: Dictionary = {}
		# Per-test isolation: reset tick counter and clear any tick listeners
		# from prior tests. Tests connect their own world's _on_tick.
		TickSystem.current_tick = 0
		_disconnect_all(TickSystem.tick)

		# Run; catch hard errors as best we can. GDScript doesn't have try/except
		# but @warning_ignore lets us surface assert failures readably.
		result = test_class.run(self)
		# Per-test teardown, AFTER the suite has restored its own save_path.
		_scrub_fixture_sidecars()

		var ok: bool = bool(result.get("ok", false))
		var message: String = String(result.get("message", ""))
		if ok:
			passed += 1
			print("  PASS  %s" % name)
		else:
			failed += 1
			print("  FAIL  %s — %s" % [name, message])

	print("\n%d passed, %d failed\n" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

## Delete the `.tmp` / `.bak` sidecars of every save fixture (audit #12 follow-up).
##
## `save_game` writes `<save_path>.tmp` and moves the live save to `<save_path>.bak`.
## Every save-using suite deletes its primary fixture and nothing else, so the
## sidecars belong to nobody. Nothing leaks today, but only incidentally: each
## existing suite happens to delete its primary before it saves to that path a
## second time, so the `.bak` branch never runs. A suite that saved twice without
## an intervening delete would strand `user://test_foo.json.bak` across runs — and
## since `load_game` falls back to `.bak` and `save_exists()` counts it, the next
## run's documented "no save file ⇒ silent fresh start" contract
## (`load_result.gd`) would quietly become "loads a stale save" for that path.
##
## Runner-side rather than a helper each suite calls, deliberately: a suite
## written later cannot forget to opt in, which is the whole failure mode. The
## sweep is scoped to the same paths `SaveSystem._is_test_fixture_path` accepts,
## so the scrub and the fault-injection gate agree on what a fixture is and the
## player's real save is never a candidate.
##
## This does NOT restore `SaveSystem.save_path` — that is audit #63 (runner
## restores neither `save_path` nor tick rate), which is broader and still live.
func _scrub_fixture_sidecars() -> void:
	for dir_path in FIXTURE_DIRS:
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if not (file_name.ends_with(SaveSystem.TMP_SUFFIX) or file_name.ends_with(SaveSystem.BAK_SUFFIX)):
				continue
			var full_path: String = dir_path + file_name
			if not SaveSystem._is_test_fixture_path(full_path):
				continue
			DirAccess.remove_absolute(ProjectSettings.globalize_path(full_path))

## Disconnect every connection on a signal — keeps tests isolated from
## leftovers from prior tests.
func _disconnect_all(sig: Signal) -> void:
	for c in sig.get_connections():
		sig.disconnect(c["callable"])
