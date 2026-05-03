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
]

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

## Disconnect every connection on a signal — keeps tests isolated from
## leftovers from prior tests.
func _disconnect_all(sig: Signal) -> void:
	for c in sig.get_connections():
		sig.disconnect(c["callable"])
