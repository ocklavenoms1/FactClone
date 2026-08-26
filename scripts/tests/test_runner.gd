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
	preload("res://scripts/tests/test_inserter_chest_overfill.gd"),
	preload("res://scripts/tests/test_applicator_wasteland_recovery.gd"),
	preload("res://scripts/tests/test_save_atomicity.gd"),
	preload("res://scripts/tests/test_load_malformed_save.gd"),
	preload("res://scripts/tests/test_quick_load_refresh.gd"),
	preload("res://scripts/tests/test_forward_incompat_save.gd"),
	# Guards the CALL SITES. Every other suite reaches the simulation systems
	# by calling them directly, so a dropped call site in _on_tick or _process
	# reddens nothing — see the file's header, and audit finding #31 for why
	# the two clocks it pins are pinned as-is rather than blessed.
	preload("res://scripts/tests/test_tick_loop_wiring.gd"),
	# Sprite render path (session-art-probe-1). The anchor suite is pure maths
	# and pins the general form against the degenerate one the three shipped
	# assets cannot distinguish it from. The manifest suite is the layer of the
	# silent-compensation guard that fires when nobody runs the game: a sprite
	# that fails to load falls back to draw_one() and the building still
	# renders, so a broken asset otherwise looks like a working game.
	preload("res://scripts/tests/test_sprite_anchor.gd"),
	preload("res://scripts/tests/test_sprite_manifest.gd"),
	# Pure-data assertions about things that are only ever seen, never computed
	# with: the per-tier body colours, and the state→string map behind the
	# inserter panel's status line. Neither needs a frame — see
	# docs/scoping/visual-verification.md, route A.
	preload("res://scripts/tests/test_inserter_body_colours.gd"),
	preload("res://scripts/tests/test_inserter_status_strings.gd"),
	# Scans console.gd's source for every message it can emit and judges each
	# one. The only arrangement that reddens when a FUTURE refusal starts
	# rendering like a success — see the file's header.
	preload("res://scripts/tests/test_console_error_classifier.gd"),
	# Guards THIS array. Asserts every test_*.gd on disk appears above, because
	# a dropped registration reddens nothing — see the file's header for the
	# incident that motivated it.
	preload("res://scripts/tests/test_registration_completeness.gd"),
	# The four console guards from audit cluster G: place's footprint paving and
	# its rollback, the radius bounds on deplete_area / tile, set_soil's
	# wasteland clear, and the header-vs-registry command inventory.
	preload("res://scripts/tests/test_console_guards.gd"),
	# Audit cluster C, #15/#18: the shared recipe-pin rule for Smelter and
	# Composter — a pin may stay only while it is resolvable AND startable.
	preload("res://scripts/tests/test_recipe_pin_release.gd"),
	# Audit cluster C, #14: a processor must never push its output onto a belt
	# that feeds it — measured, the feeder saturates and the input line dies.
	preload("res://scripts/tests/test_processor_feeder_push.gd"),
	# Audit cluster H — Esc / input routing. Three findings that all answer the
	# same question ("which handler saw the key, and did more than one thing act
	# on it"), which is exactly why they are three separate suites: fixing any
	# one of them turns a naive "Esc closes the console" check green. Each one
	# below reddens only for its own defect — see the discrimination matrix in
	# the cluster-H report and the header of each file.
	#
	# They share `esc_input_harness.gd`, which is NOT registered here: it has no
	# test_name(), and its filename is outside the `test_*.gd` pattern
	# test_registration_completeness.gd scans.
	preload("res://scripts/tests/test_esc_modal_race.gd"),
	preload("res://scripts/tests/test_esc_duplicate_handler.gd"),
	preload("res://scripts/tests/test_console_backtick_toggle.gd"),
	# Audit #16: the placement hover preview must agree with can_place_building
	# in both directions. The predicate was EXTRACTED out of GridWorld._draw to
	# make this suite possible at all — nothing headless can reach a _draw body,
	# so a correction applied in place would have been unverifiable. See the
	# file's header.
	preload("res://scripts/tests/test_hover_preview_agreement.gd"),
	# Audit #26: the two-pass belt tick. Belts had no suite of their own — they
	# appeared only as incidental transport behind LOWER-BOUND thresholds, which
	# a faster-than-correct or item-duplicating belt satisfies. Everything in
	# this one is an exact equality. It is belts-only on purpose, and the hole
	# it leaves (machine-adjacent timing, audit #17) is named in its header.
	preload("res://scripts/tests/test_belt.gd"),
	# Audit #25: the nine bread- and cloth-chain recipes, none of which any test
	# had ever ticked. A test-gap row like #26 — the data is correct; what was
	# missing was a SECOND statement of it. Every expected count, ratio, output
	# identity and cycle length in that file is a literal, deliberately: a suite
	# that asked `Recipes` what to expect would move with the table it guards.
	preload("res://scripts/tests/test_processor_recipes.gd"),
	# Audit #29: _tick_regrowth iterated ALL of resource_state (worldgen
	# seeds every ore tile, so the is_empty early-out never fired — measured
	# ~1.0 ms/frame with zero chopped trees). It now iterates the sparse
	# _active_regrowth index, which makes STALENESS the failure mode; this
	# suite pins the index and every one of its six invalidation edges,
	# each mutation-verified. See the file header.
	preload("res://scripts/tests/test_regrowth_index.gd"),
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
		# Per-test isolation: reset tick counter and clear any tick listeners
		# from prior tests. Tests connect their own world's _on_tick.
		TickSystem.current_tick = 0
		_disconnect_all(TickSystem.tick)

		# UNTYPED, AND THAT IS THE POINT. GDScript has no try/except, so a suite
		# that hits a runtime error simply stops: `run()` aborts and hands back
		# whatever its declared return type defaults to. For `-> Dictionary`
		# that is `{}`, which reads as a FAIL and costs one suite. For an
		# UNDECLARED return type it is `null`, and a typed
		# `var result: Dictionary = test_class.run(self)` rejects null on the
		# ASSIGNMENT — a second runtime error, this one inside `_ready`, which
		# aborts the runner itself. Measured before this line was written: nine
		# PASS lines, then nothing. No summary, no `get_tree().quit()`, and
		# `--headless` sat there until the CI timeout killed it (`exit=124`) —
		# the same signature as the compile-error hang this project has already
		# been bitten by, and just as uninformative.
		#
		# So the result is taken into an untyped local, which cannot fail, and
		# the shape is checked afterwards. A suite that errors now costs one
		# suite and says so, exactly like one that fails.
		var raw = test_class.run(self)
		# Per-test teardown. Covers PASS, FAIL and ERROR alike, which is why it
		# sits above the branch rather than inside it — the errored suite is the
		# one MOST likely to have left a fixture behind.
		#
		# Note this does NOT depend on the suite having restored `SaveSystem.save_path`
		# first, as this comment used to imply. The sweep scans FIXTURE_DIRS and
		# filters what it finds through `_is_test_fixture_path`; it never reads
		# `save_path` at all.
		_scrub_fixture_sidecars()

		if not (raw is Dictionary):
			failed += 1
			print("  ERROR %s — run() returned %s instead of a result Dictionary. The suite aborted on a runtime error; look for the SCRIPT ERROR above." % [name, type_string(typeof(raw))])
			continue
		var result: Dictionary = raw

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

## Delete the `.tmp` / `.bak` / `.incompatible` sidecars of every save fixture
## (audit #12 follow-up; `.incompatible` joined at audit #21).
##
## `save_game` writes `<save_path>.tmp` and moves the live save to `<save_path>.bak`.
## `load_game` writes `<save_path>.incompatible` when it refuses a save from a
## newer build — and that one is never rotated away by design, so a stranded copy
## would persist across runs rather than being overwritten by the next save.
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
			if not (file_name.ends_with(SaveSystem.TMP_SUFFIX) or file_name.ends_with(SaveSystem.BAK_SUFFIX) or file_name.ends_with(SaveSystem.INCOMPAT_SUFFIX)):
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
