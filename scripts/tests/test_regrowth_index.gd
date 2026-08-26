extends RefCounted

## Audit #29 — the `_active_regrowth` index and EVERY one of its
## invalidation edges (session 2026-08-26).
##
## Why this suite exists: worldgen seeds `resource_state` with an entry for
## every ore tile (8,428 at seed 42), so `_tick_regrowth`'s old early-out
## (`resource_state.is_empty()`) could never fire and the walk cost a
## measured ~1.0 ms/frame with zero chopped trees. The fix iterates a
## sparse index instead — which makes STALENESS the new failure mode, and
## a stale index is silent compensation in both directions: a missed ADD
## means a chopped tree never regrows and nothing reds; a missed ERASE
## means `_tick_regrowth` faults loudly (deliberately unguarded read).
##
## So every write site gets a sub-case that reddens when its index line is
## dropped — mutation-measured, one at a time, on 2026-08-26:
##   M1 drop the add in chop_tree            → (2) reddens (timer frozen)
##   M2 drop the erase in _restore_tree      → (4) reddens (index not empty)
##   M3 drop the erase in set_overlay        → (5) reddens (index not empty)
##   M4 drop the erase in place_building     → (6) reddens (index not empty)
##   M5 drop the add in save_system load     → (7) reddens (loaded timer inert)
##   M6 drop the clear in WorldGenerator     → (8) reddens (index survives regen)
##
## White-box asserts on `_active_regrowth` are deliberate: the behavioural
## consequence of a stale entry is a SCRIPT ERROR (which the suite summary
## does not count — the three-count run protocol does), so the index state
## itself is the assertable surface. Each white-box assert is paired with a
## behavioural one where a behavioural consequence exists.
##
## Expected values are literals or explicit arithmetic on production
## CONSTANTS with hand-supplied deltas — never a value computed by the
## functions under test (NOTES.md evidence-table rule).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const WorldGenScript = preload("res://scripts/world/world_generator.gd")
const TEST_SEED: int = 42
const TEST_SAVE_PATH: String = "user://test_regrowth_index.json"

static func test_name() -> String:
	return "regrowth index (#29: sparse timer index + all 6 invalidation edges)"

static func _check(failures: Array, cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

static func _find_trees(world, count: int) -> Array:
	var found: Array = []
	for pos in world.tiles:
		if world.tiles[pos].resource_node == ResourceNodes.Type.TREE:
			found.append(pos)
			if found.size() >= count:
				break
	return found

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var world = GridWorldScript.new()
	parent.add_child(world)
	WorldGenScript.new().generate(world, TEST_SEED)

	# ---- (1) PREMISE + the finding's core fact: a fresh worldgen world has
	# a NON-empty resource_state (the old early-out could never fire) and an
	# EMPTY index (the new early-out fires immediately).
	_check(failures, world.resource_state.size() > 1000,
		"(1) PREMISE: worldgen should seed resource_state with thousands of ore entries, got %d — the finding's premise (early-out never fires) no longer holds; re-derive #29" % world.resource_state.size())
	_check(failures, world._active_regrowth.is_empty(),
		"(1) fresh worldgen world: _active_regrowth should be empty, has %d entries" % world._active_regrowth.size())

	var trees: Array = _find_trees(world, 4)
	if trees.size() < 4:
		world.queue_free()
		return { "ok": false, "message": "setup: seed %d yielded %d trees, need 4" % [TEST_SEED, trees.size()] }

	# ---- (2) chop-ADD edge (M1). Chop through the public path; the timer
	# must be indexed AND actually tick.
	var pos_a: Vector2i = trees[0]
	world.chop_tree(pos_a)
	_check(failures, world._active_regrowth.has(pos_a),
		"(2) after chop_tree, _active_regrowth should contain %s — dropped add in chop_tree means the tree silently never regrows" % str(pos_a))
	_check(failures, absf(world.regrowth_remaining_at(pos_a) - GridWorldScript.TREE_REGROWTH_SECONDS) < 0.001,
		"(2) PREMISE: chop should set timer to %f, got %f" % [GridWorldScript.TREE_REGROWTH_SECONDS, world.regrowth_remaining_at(pos_a)])
	world._tick_regrowth(1.0)
	_check(failures, absf(world.regrowth_remaining_at(pos_a) - (GridWorldScript.TREE_REGROWTH_SECONDS - 1.0)) < 0.001,
		"(2) after _tick_regrowth(1.0) the timer should read %f, got %f — an unindexed timer is frozen" % [GridWorldScript.TREE_REGROWTH_SECONDS - 1.0, world.regrowth_remaining_at(pos_a)])

	# ---- (3) the save mirror tracks the live timer (in-place mutation —
	# the #29 fix stopped allocating a fresh Dictionary per timer per frame).
	var mirror = world.resource_state_modifications.get(pos_a)
	_check(failures, mirror != null and absf(float(mirror.get("regrowth_remaining", -1.0)) - (GridWorldScript.TREE_REGROWTH_SECONDS - 1.0)) < 0.001,
		"(3) resource_state_modifications[%s] should mirror the ticked timer at %f, got %s — the save would capture a stale value" % [str(pos_a), GridWorldScript.TREE_REGROWTH_SECONDS - 1.0, str(mirror)])

	# ---- (4) restore-ERASE edge (M2). Expire the timer; the tree must come
	# back and the index entry must go with it.
	world._tick_regrowth(GridWorldScript.TREE_REGROWTH_SECONDS + 1.0)
	_check(failures, world.tiles.has(pos_a) and world.tiles[pos_a].resource_node == ResourceNodes.Type.TREE,
		"(4) after expiry the tree at %s should be restored" % str(pos_a))
	_check(failures, not world._active_regrowth.has(pos_a),
		"(4) after _restore_tree, _active_regrowth still contains %s — the next _tick_regrowth faults on the erased resource_state entry, every frame" % str(pos_a))

	# ---- (5) set_overlay cancel-ERASE edge (M3).
	var pos_b: Vector2i = trees[1]
	world.chop_tree(pos_b)
	_check(failures, world._active_regrowth.has(pos_b),
		"(5) PREMISE: chop at %s should index the timer" % str(pos_b))
	var overlay_ok: bool = world.set_overlay(pos_b, Terrain.Overlay.STONE)
	_check(failures, overlay_ok,
		"(5) PREMISE: set_overlay on the chopped tile rejected: %s" % world.last_place_error)
	_check(failures, not world._active_regrowth.has(pos_b),
		"(5) after overlay-cancels-regrowth, _active_regrowth still contains %s — stale entry faults _tick_regrowth" % str(pos_b))
	world._tick_regrowth(GridWorldScript.TREE_REGROWTH_SECONDS + 1.0)
	_check(failures, not (world.tiles.has(pos_b) and world.tiles[pos_b].resource_node == ResourceNodes.Type.TREE),
		"(5) a cancelled regrowth at %s still restored a tree through the paved tile" % str(pos_b))

	# ---- (6) place_building cancel-ERASE edge (M4).
	var pos_c: Vector2i = trees[2]
	world.chop_tree(pos_c)
	_check(failures, world._active_regrowth.has(pos_c),
		"(6) PREMISE: chop at %s should index the timer" % str(pos_c))
	# COMPOSTER: 1x1 and accepts Overlay.NONE, so it places on the bare
	# grass a chopped tree leaves behind (CHEST requires paving, and paving
	# first would cancel the regrowth through the OTHER edge).
	var placed: bool = world.place_building(Buildings.Type.COMPOSTER, pos_c)
	_check(failures, placed,
		"(6) PREMISE: composter placement on the chopped tile failed: %s" % world.last_building_place_error)
	_check(failures, not world._active_regrowth.has(pos_c),
		"(6) after building-cancels-regrowth, _active_regrowth still contains %s — stale entry faults _tick_regrowth" % str(pos_c))
	world._tick_regrowth(GridWorldScript.TREE_REGROWTH_SECONDS + 1.0)
	_check(failures, not (world.tiles.has(pos_c) and world.tiles[pos_c].resource_node == ResourceNodes.Type.TREE),
		"(6) a cancelled regrowth at %s still restored a tree under the composter" % str(pos_c))

	# ---- (7) load-ADD edge (M5). A saved mid-regrowth timer must be
	# re-indexed on load, or it reads back correctly and never ticks —
	# the exact half test_tree_harvest_lifecycle's round-trip cannot see
	# (it asserts the loaded VALUE, never a post-load tick).
	var pos_d: Vector2i = trees[3]
	world.chop_tree(pos_d)
	world._tick_regrowth(GridWorldScript.TREE_REGROWTH_SECONDS * 0.4)
	var pre_save: float = world.regrowth_remaining_at(pos_d)
	_check(failures, pre_save > 2.0,
		"(7) PREMISE: pre-save remaining %f too small to survive the post-load 1.0s tick" % pre_save)

	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	var player_a := Node2D.new()
	parent.add_child(player_a)
	var inv_a := Inventory.new(16)
	var saved: bool = SaveSystem.save_game(world, player_a, inv_a, {})
	if not saved:
		SaveSystem.save_path = orig_path
		world.queue_free()
		player_a.queue_free()
		return { "ok": false, "message": "(7) save_game returned false" }

	var world_b = GridWorldScript.new()
	parent.add_child(world_b)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var inv_b := Inventory.new(16)
	var result: LoadResult = SaveSystem.load_game(world_b, player_b, inv_b)
	if not result.success:
		SaveSystem.save_path = orig_path
		world.queue_free()
		player_a.queue_free()
		world_b.queue_free()
		player_b.queue_free()
		return { "ok": false, "message": "(7) load_game failed: %s" % result.error_message }
	_check(failures, world_b._active_regrowth.has(pos_d),
		"(7) after load, _active_regrowth should contain %s — dropped registration in save_system means every loaded timer is inert" % str(pos_d))
	world_b._tick_regrowth(1.0)
	_check(failures, absf(world_b.regrowth_remaining_at(pos_d) - (pre_save - 1.0)) < 0.01,
		"(7) after load + _tick_regrowth(1.0) the timer should read %f, got %f — the loaded timer reads back fine but does not TICK" % [pre_save - 1.0, world_b.regrowth_remaining_at(pos_d)])

	# ---- (8) generate-CLEAR edge (M6). Re-generating a world that has an
	# indexed timer must drop the index with resource_state, or the stale
	# entry faults _tick_regrowth on a world whose trees are all mature.
	_check(failures, not world_b._active_regrowth.is_empty(),
		"(8) PREMISE: world_b should still hold the indexed timer before regenerate")
	WorldGenScript.new().generate(world_b, TEST_SEED)
	_check(failures, world_b._active_regrowth.is_empty(),
		"(8) after WorldGenerator.generate, _active_regrowth should be empty, has %d entries — the bulk clear beside resource_state.clear() was dropped" % world_b._active_regrowth.size())

	# Cleanup.
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	SaveSystem.save_path = orig_path
	world.queue_free()
	player_a.queue_free()
	world_b.queue_free()
	player_b.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "8 sub-cases pass: fresh-world premise + empty index; chop indexes and ticks; mirror tracks in place; restore, overlay-cancel, building-cancel and regenerate all invalidate; load re-indexes and the loaded timer ticks" }
	return { "ok": false, "message": "%d failure(s): %s" % [failures.size(), "; ".join(failures)] }
