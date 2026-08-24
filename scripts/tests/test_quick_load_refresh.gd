extends RefCounted

## F9 quick-load must leave vision and the map describing the world it loaded.
##
## Audit finding #13 (MEDIUM), docs/audits/2026-07-19-flaw-review.md —
## "F9 quick-load leaves vision and the map stale".
##
## `SaveSystem.load_game` CLEARS `region_visibility` and restores every explored
## region as FOG, documenting at that line that active state "will be set by
## main.gd's vision update after load completes". The boot path honoured that
## contract; the F9 path called `load_game` and stopped. `_process` re-runs
## `update_vision` only when the player's region CHANGES, so the common case —
## F5 then F9 without moving — updated nothing and the 5×5 around the player
## stayed fog. Separately, a region explored in this session but absent from the
## save was erased from `region_visibility` with nothing marking the map dirty,
## so the M-map and the minimap kept rendering exploration the loaded world does
## not have.
##
## THE PROPERTY, NOT THE CALL. Nothing here asserts that a particular function
## ran. Sub-cases 1 and 3 read `region_visibility` state values (2 = active,
## 1 = fog, absent = unrevealed) and sub-case 2 reads PIXELS back out of the map
## panel's own image, which is the thing the player actually looks at. A fix
## that called the helper and then failed to repaint fails sub-case 2.
##
## WHY IT DRIVES `Main._quick_load()` RATHER THAN THE SHARED HELPER. The finding
## IS the divergence between the two load paths. A test that called the shared
## refresh helper directly would pass against a `main.gd` that never called it
## from F9 — which is the bug. So the harness builds a `main.gd` instance with
## its node references assigned by hand (the script is never added to the tree,
## so `_ready` and its `@onready` lookups never run) and calls the real F9 entry
## point. `player` is a CharacterBody2D and not a bare Node2D because that is
## what the field is statically typed as; a Node2D would fail the assignment.
##
## Sub-case index:
##   1. Quick-load STANDING IN THE SAME REGION as the saved position — the case
##      that reproduces the bug, because `_player_last_region` is unchanged and
##      `_process` therefore never fires. The 5×5 must come back ACTIVE, not fog.
##   2. A region explored in-session but absent from the save. The map is built
##      to completion first (so the region is genuinely painted), then quick-
##      loaded, then the build is driven to completion again. The region's pixels
##      must end BLACK — unrevealed — not the fog green they were painted.
##   3. Quick-load into a DIFFERENT region. Guards the region-change path against
##      the fix: the 5×5 around the LOADED region must be active, and
##      `_player_last_region` must have been synced to it so `_process` does not
##      re-run the same update on the next frame.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const MainScript = preload("res://scripts/main.gd")
const MapPanelScript = preload("res://scripts/ui/map_panel.gd")

const TEST_SAVE_PATH: String = "user://test_quick_load_refresh.json"
const SEED: int = 51001

# TILE_SIZE (32) × REGION_SIZE (32) = 1024 world px per region, so a position
# of 100 px lands well inside region 0 and 4 × 1024 + 100 well inside region 4.
const POS_SAVED: Vector2 = Vector2(100.0, 100.0)
const REGION_SAVED: Vector2i = Vector2i(0, 0)
const POS_FAR: Vector2 = Vector2(4196.0, 4196.0)
const REGION_FAR: Vector2i = Vector2i(4, 4)

## The region explored in-session but absent from the save (sub-case 2).
## Chebyshev distance 5 from REGION_SAVED, so the post-load vision update cannot
## re-reveal it and it must genuinely go dark; and inside REGION_MIN/MAX (-8..7)
## so it is a real region the map builds.
const REGION_STALE: Vector2i = Vector2i(5, 5)

static func test_name() -> String:
	return "F9 quick-load refreshes vision and the map (audit #13)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	_scrub()

	_case_same_region(parent, failures)
	_case_stale_map_region(parent, failures)
	_case_different_region(parent, failures)

	SaveSystem.save_path = orig_path
	_scrub()

	if failures.is_empty():
		return { "ok": true, "message": "3 sub-cases pass: quick-loading without moving re-activates the 5×5; a region the save does not know about goes black on the map; quick-loading into a different region activates it and syncs _player_last_region" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===================================================================
# (1) Same region — the reproducing case.
# ===================================================================
static func _case_same_region(parent: Node, failures: Array) -> void:
	if not _save_world(parent, POS_SAVED, REGION_SAVED):
		failures.append("(1) PREMISE: save_game returned false")
		return
	var harness: Dictionary = _make_harness(parent)
	var m = harness["main"]
	# F5 then F9 standing still: the region the player was last known to be in
	# is the region the save puts them back in, so nothing in _process changes.
	m._player_last_region = REGION_SAVED
	m._quick_load()

	_check(failures, m.grid_world.region_visibility.size() > 0,
		"(1) PREMISE: the load left region_visibility empty, so nothing below is testing a load that happened")
	_expect_active_5x5(failures, m.grid_world, REGION_SAVED, "(1)")
	_teardown_harness(harness)

# ===================================================================
# (2) A region explored in-session that the save does not carry.
# ===================================================================
static func _case_stale_map_region(parent: Node, failures: Array) -> void:
	if not _save_world(parent, POS_SAVED, REGION_SAVED):
		failures.append("(2) PREMISE: save_game returned false")
		return
	var harness: Dictionary = _make_harness(parent)
	var m = harness["main"]
	var panel = harness["panel"]
	panel.world = m.grid_world

	# In-session exploration the save knows nothing about.
	m.grid_world.region_visibility[REGION_STALE] = 1
	_build_map_fully(panel)

	var px: Vector2i = _region_sample_pixel(REGION_STALE)
	var before: Color = panel._map_image.get_pixel(px.x, px.y)
	# PREMISE. If this region were already black the sub-case would pass without
	# the fix doing anything, so the "explored" state has to be visible first.
	_check(failures, before.g > 0.05,
		"(2) PREMISE: region %s was marked explored and the map built, so its pixels should be painted, but got %s" % [str(REGION_STALE), str(before)])

	m._player_last_region = REGION_SAVED
	m._quick_load()

	# PREMISE. The erasure is load_game's doing, and sub-case 2 is only about
	# whether the MAP follows it. If the entry survived, the map has nothing to
	# correct and a black pixel below would mean something else went wrong.
	_check(failures, not m.grid_world.region_visibility.has(REGION_STALE),
		"(2) PREMISE: load_game is supposed to clear region_visibility, but %s survived the load" % str(REGION_STALE))

	_build_map_fully(panel)
	var after: Color = panel._map_image.get_pixel(px.x, px.y)
	_check(failures, after.r < 0.02 and after.g < 0.02 and after.b < 0.02,
		"(2) %s is unrevealed in the loaded world, so the map must repaint it black — got %s. The map is still showing exploration from before the load." % [str(REGION_STALE), str(after)])
	_teardown_harness(harness)

# ===================================================================
# (3) A different region — the region-change path must still work.
# ===================================================================
static func _case_different_region(parent: Node, failures: Array) -> void:
	if not _save_world(parent, POS_FAR, REGION_FAR):
		failures.append("(3) PREMISE: save_game returned false")
		return
	var harness: Dictionary = _make_harness(parent)
	var m = harness["main"]
	m._player_last_region = REGION_SAVED   # deliberately NOT where the save lands
	m._quick_load()

	_expect_active_5x5(failures, m.grid_world, REGION_FAR, "(3)")
	# Syncing this is what stops _process from re-running the identical vision
	# update on the very next frame, and what makes the next genuine region
	# cross compare against the right baseline.
	_check(failures, m._player_last_region == REGION_FAR,
		"(3) _player_last_region is %s after loading a save placed in %s — it must track the loaded position" % [str(m._player_last_region), str(REGION_FAR)])
	_teardown_harness(harness)

# ---------- helpers ----------

## Save a world with the player at `pos` and the 5×5 around `region` explored,
## so the fixture carries real `explored_regions` for the load to restore as fog.
static func _save_world(parent: Node, pos: Vector2, region: Vector2i) -> bool:
	var world = _make_world(parent)
	world.world_seed = SEED
	var player := CharacterBody2D.new()
	parent.add_child(player)
	player.global_position = pos
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			world.region_visibility[region + Vector2i(dx, dy)] = 2
	var ok: bool = SaveSystem.save_game(world, player, Inventory.new(16), {})
	player.queue_free()
	_teardown(world)
	return ok

## A `main.gd` instance wired by hand. Never added to the tree — `_ready` would
## resolve `@onready var player = $Player` against a scene this test does not
## build — so the fields are assigned directly instead.
static func _make_harness(parent: Node) -> Dictionary:
	var m = MainScript.new()
	m.grid_world = _make_world(parent)
	var player := CharacterBody2D.new()
	parent.add_child(player)
	m.player = player
	m.player_inventory = Inventory.new(16)
	var panel = MapPanelScript.new()
	# Added to the tree so its _ready allocates _map_image / _map_texture; the
	# panel stays closed, so its own _process does nothing for the rest of the run.
	parent.add_child(panel)
	m.map_panel = panel
	var label := Label.new()
	parent.add_child(label)
	m.toast_label = label
	return { "main": m, "player": player, "panel": panel, "label": label }

static func _teardown_harness(harness: Dictionary) -> void:
	_teardown(harness["main"].grid_world)
	harness["player"].queue_free()
	harness["panel"].queue_free()
	harness["label"].queue_free()
	harness["main"].queue_free()

## Drive the background build to completion. Bounded so a build that never
## finishes fails the sub-case's assertions instead of hanging the suite.
static func _build_map_fully(panel) -> void:
	var guard: int = 0
	while not panel._initial_built and guard < 2000:
		panel.tick_background_build()
		guard += 1

## A pixel inside `region`'s block in the map image. Mirrors map_panel's own
## origin arithmetic; +8 keeps the sample away from the block's edges.
static func _region_sample_pixel(region: Vector2i) -> Vector2i:
	var origin_x: int = (region.x * MapPanelScript.REGION_TILES - WorldGenerator.WORLD_MIN) * MapPanelScript.PIXELS_PER_TILE
	var origin_y: int = (region.y * MapPanelScript.REGION_TILES - WorldGenerator.WORLD_MIN) * MapPanelScript.PIXELS_PER_TILE
	return Vector2i(origin_x + 8, origin_y + 8)

## Every region within VISION_RADIUS of `center` must be ACTIVE (state 2).
## Reported as one failure naming the offenders rather than 25 separate ones.
static func _expect_active_5x5(failures: Array, world, center: Vector2i, label: String) -> void:
	var wrong: Array = []
	for dx in range(-GridWorldScript.VISION_RADIUS, GridWorldScript.VISION_RADIUS + 1):
		for dy in range(-GridWorldScript.VISION_RADIUS, GridWorldScript.VISION_RADIUS + 1):
			var r: Vector2i = center + Vector2i(dx, dy)
			var state: int = int(world.region_visibility.get(r, 0))
			if state != 2:
				wrong.append("%s=%d" % [str(r), state])
	_check(failures, wrong.is_empty(),
		"%s the 5×5 around %s must be active (2) after the load; these are not: %s (1 = fog, 0 = unrevealed)" % [label, str(center), ", ".join(wrong.slice(0, 8))])

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _scrub() -> void:
	for p in [TEST_SAVE_PATH, TEST_SAVE_PATH + SaveSystem.TMP_SUFFIX, TEST_SAVE_PATH + SaveSystem.BAK_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing. queue_free is deferred until after the runner's
## synchronous run() returns, so a torn-down world otherwise stays subscribed
## to TickSystem.tick for the rest of the suite.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
