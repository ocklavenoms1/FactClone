class_name SaveSystem
extends RefCounted

## Save schema migration log:
##   v4 → v5: Mill became Processor; state shape changed from
##            { in_count, out_count, progress } to
##            { recipe_id, state, progress, in_buffer, out_buffer }.
##   v5 → v6: Chest migrated from Inventory to bag format.
##            { inv: Array (Inventory.to_array()) } → { bag: Array of [type, count] }.
##            TOTAL_CAPACITY = 2400 (equivalent to old 24 slots × 100 max_stack).
##   v6 → v7: Tile model split into base + overlay. Tile entry shape
##            [x, y, terrain] → [x, y, base, overlay]. Player paints
##            overlays on grass; water is a base, not paintable.
##   v7 → v8: Tile gains `resource_node` field (forward-prep for world-gen
##            stone/ore/wood deposits, target session G/H — see NOTES.md).
##            Tile entry shape [x, y, base, overlay] → [x, y, base, overlay, resource_node].
##            No buildings consume resource_nodes yet; the bump just locks
##            the save format so we don't bump twice when mining lands.
##            No migration code — old saves hard-fail with OS.alert.
##   v8 → v9: Multi-tile buildings + rotation. Mixer/Oven/Proofer/Packager
##            footprint changed from 1×1 to 2×2 — v8 saves with these
##            buildings would load with mismatched `occupied` cells (only
##            the anchor mapped, not the 3 expansion cells). Rotatable
##            processors (Mixer/Oven/Proofer/Packager/Thresher) now carry
##            `dir` in their state so prefer_dir ports rotate with the
##            building. v8 saves where these buildings were 1×1 / non-
##            directional cannot be safely upgraded — hard-fail.
##   v9 → v10: Player gains bag-cap progression. New top-level field
##            `player_progression: Dictionary` with `bags_consumed: int`
##            (0..5) tracking lifetime bag consumption. Inventory capacity
##            persists implicitly via load_array's resize logic; the
##            progression dict is the explicit counter and the future home
##            for additional progression state (score/value, achievements,
##            etc.). v9 saves don't have this field — hard-fail.
##  v10 → v11: WORLDGEN STAGE 1 — procgen rehydration model.
##            New top-level fields:
##              - `world_seed: int` — the seed used to generate this world
##              - `worldgen_version: int` — must match WorldGenerator.VERSION
##                or load hard-fails (procgen logic changes invalidate saves)
##            Tile data shape change:
##              - `tiles` → `tile_modifications`. Stores ONLY tiles that
##                differ from procgen-canonical state. Saves are dramatically
##                smaller (KB instead of MB) since most world content is
##                regenerated from the seed.
##            Load procedure changes:
##              - 1. Read seed + worldgen_version (hard-fail mismatch)
##              - 2. Run WorldGenerator.generate(world, seed) to rebuild canon
##              - 3. Apply tile_modifications on top
##              - 4. Restore buildings / player / progression as before
##            v10 saves don't have a seed and use the hardcoded-lake world.
##            They cannot be safely upgraded — hard-fail.
##  v11 → v12: M-key map + fog-of-war. New top-level field
##            `explored_regions: Array of [rx, ry]` — sparse list of region
##            coords ever charted (state >= 1 = fog or active).
##            Active state (state == 2, currently in vision) is recomputed
##            from player position at load time, not persisted. Avoids the
##            "saved active but loaded somewhere else" inconsistency.
##            v11 saves don't have this field — hard-fail.
##  v12 → v13: Manual mining mechanics. New top-level field
##            `resource_state_modifications: Array of [x, y, richness]` —
##            sparse list of ore-deposit tiles whose richness has been
##            depleted by mining. Parallel to `tile_modifications`: only
##            deltas from procgen-canonical state persist.
##            On load: WorldGenerator regenerates canonical resource_state
##            (with original_richness intact) from seed, then apply
##            modifications to overwrite richness. Fully-depleted tiles
##            (richness=0) are handled by tile_modifications setting
##            resource_node=NONE; the resource_state_modifications entry
##            for those is erased at depletion time.
##            DUAL REASON for v12 hard-fail at this bump:
##              (1) the new resource_state_modifications field
##              (2) the "no overlay on deposits" rule reversal — v12 saves
##                  could have stale overlay-on-deposit tiles which are
##                  now invalid state.
##            v12 saves don't have either — hard-fail.
##  v13 → v14: Tree harvesting + generic resource state modifications.
##            resource_state_modifications shape changed from
##              Array of [x, y, richness:int]
##            to
##              Array of [x, y, dict]
##            where dict contains state fields per resource type:
##              ore:  {"richness": int}
##              tree: {"regrowth_remaining": float}
##            The Dictionary inner shape supports future resource types
##            (crops, berries, etc.) by adding keys without further
##            schema bumps. Each entry stores ONLY the fields relevant
##            to its resource type.
##            v13 saves have Array of [x, y, int] — incompatible with
##            the new Dict shape — hard-fail.

## Save format migration log:
##   v14 → v15: added `region_soil_modifications` (Array of [rx, ry, soil])
##              for the soil exhaustion arc (session-soil-exhaustion-1).
##              Sparse — absent regions default to SOIL_HEALTH_FULL (100).
##              Hard-fail v14 saves per existing schema-bump policy.
##   v15 → v16: REFACTOR region-scoped soil to per-tile soil
##              (session-soil-exhaustion-2). Field renamed
##              `region_soil_modifications` → `tile_soil_modifications`
##              with shape Array of [x, y, soil] where (x, y) is a TILE
##              position, not a region coord. Sparse — absent tiles default
##              to TILE_SOIL_FULL (100). Hard-fail v15 saves; no migration
##              (region values would synthesize artificial uniform tiles).
##   v16 → v17: Fertilizer chain (session-soil-exhaustion-3). New top-level
##              field `tile_fertilizer_state`: sparse Array of
##              [x, y, tier_int, remaining_float] where tier_int is an
##              Items.Type (COMPOST_LOW or COMPOST_MID), and remaining is
##              the seconds left on the active boost. Absent tile = no
##              boost (default behavior, regen at 1×). v16 saves don't have
##              the field — hard-fail with OS.alert per existing policy.
##              Items enum gained COMPOST_LOW + COMPOST_MID at the end
##              (append-only — no enum-int reuse risk for v16 ints).
##   v17 → v18: Wasteland mechanics (session-soil-exhaustion-4). New top-
##              level field `tile_wasteland_state`: sparse Array of
##              [x, y, scarred_bool, decay_remaining_float]. Absent tile =
##              healthy (no grace, no scar). Scarred persists; grace is
##              countdown to scarring.
##              Items enum gained COMPOST_HIGH (append-only). Composter
##              now accepts BREAD + LOAF_PACK as recipe inputs.
##              v17 saves don't have the wasteland field — hard-fail with
##              OS.alert per existing policy.
const SAVE_VERSION: int = 18
const DEFAULT_SAVE_PATH: String = "user://save_slot_1.json"

## Path used by save_game / load_game / save_exists. Tests override this
## to a scratch path so they don't clobber the player's save. Restore to
## DEFAULT_SAVE_PATH after the test.
static var save_path: String = DEFAULT_SAVE_PATH

## True if the given path looks like a test fixture (test files set save_path
## to scratch paths during negative-path tests; those should NEVER trigger
## user-facing OS.alert popups even if the test runs windowed). Used to gate
## OS.alert calls in load_game error branches. push_error still fires for
## logging in both cases.
static func _is_test_fixture_path(path: String) -> bool:
	return path.begins_with("user://test_") or path.find("/test_artifacts/") >= 0

# ---------- migration framework (session-save-migration) ----------
#
# Replaces the prior hard-fail-on-version-mismatch behavior. When loading
# a save with version < SAVE_VERSION, the chain `_migrate_vN_to_v(N+1)`
# steps the parsed Dictionary forward one version at a time until it
# matches the current schema. Each migration is responsible for adding
# new fields with sensible defaults, transforming/restructuring as
# needed, and bumping `data["version"]` to its target.
#
# **Breaking-change reset point: v17.** Saves before v17 are NOT
# preserved — the v14/v15/v16 schema versions exist only as schema-
# history reference; no production saves at those versions ever
# existed. If a v<17 save is encountered (extremely unlikely), the
# missing-migration path fires, load fails, and main.gd's post-3.5
# hotfix regenerates a fresh world. See NOTES.md / CONVENTIONS.md.
#
# Forward-only by design: a save with version > SAVE_VERSION (running
# an OLDER game binary against a NEWER save) hard-fails. Backward
# migration is out of scope.
const MIGRATIONS: Dictionary = {
	# 17 → 18: Wasteland mechanics. New top-level `tile_wasteland_state`
	# field; absent in v17, populated to empty Array (no scarred tiles).
	17: "_migrate_v17_to_v18",
}

## Migrate `data` (parsed save dict) from `from_version` to `to_version`
## by walking the MIGRATIONS chain one step at a time. Returns the
## migrated Dictionary on success, OR null on any failure (gap in chain,
## migration didn't bump version correctly, etc.). Caller surfaces the
## error and main.gd's hotfix regenerates a fresh world.
##
## Pure data transformation — no game state mutation, no I/O.
##
## Defensive: each step verifies the migration produced an N+1 version,
## so a bug in a migration function is caught at the failing step
## (named in the error) rather than producing a downstream silent
## corruption.
static func _try_migrate(data: Dictionary, from_version: int, to_version: int) -> Variant:
	var current: int = from_version
	while current < to_version:
		if not MIGRATIONS.has(current):
			push_error("SaveSystem._try_migrate: no migration registered from v%d (target v%d)" % [current, to_version])
			return null
		var method_name: String = MIGRATIONS[current]
		# Static method dispatch via match-statement. GDScript's Object.call()
		# is instance-only and Callable(SaveSystem, name) on a static method
		# is unreliable; explicit dispatch is the foolproof pattern. Each
		# new migration adds one match case below — small cost, clear errors.
		var migrated = _dispatch_migration(method_name, data)
		if typeof(migrated) != TYPE_DICTIONARY:
			push_error("SaveSystem._try_migrate: %s returned non-Dictionary (%s)" % [method_name, typeof(migrated)])
			return null
		data = migrated
		var new_version: int = int(data.get("version", -1))
		if new_version != current + 1:
			push_error("SaveSystem._try_migrate: %s did not bump version: expected %d, got %d" % [method_name, current + 1, new_version])
			return null
		current = new_version
	return data

## Dispatch a migration by name. Each migration registered in MIGRATIONS
## must have a corresponding match case here. Failure to register both
## sides is a parse-error / runtime-error pair: MIGRATIONS lookup returns
## a name that this dispatcher doesn't recognize → push_error + null.
static func _dispatch_migration(method_name: String, data: Dictionary) -> Variant:
	match method_name:
		"_migrate_v17_to_v18":
			return _migrate_v17_to_v18(data)
	push_error("SaveSystem._dispatch_migration: unknown migration '%s'" % method_name)
	return null

## v17 → v18: add `tile_wasteland_state` field with empty Array default.
## Schema diff: this field was added in session-soil-exhaustion-4 to
## persist per-tile wasteland state (scarred flag + grace decay timer).
## v17 saves predate the wasteland mechanic entirely — no scarred tiles
## could exist. Default-empty Array is the canonical "healthy world."
##
## The Items enum also gained COMPOST_HIGH at v18, but that's stored as
## an int in player_inventory and recipe state — nothing to migrate
## (the int 26, or whatever the enum value is, simply wouldn't appear
## in a v17 save). No COMPOST_HIGH in player_inventory at v17 by
## construction, so nothing to backfill.
static func _migrate_v17_to_v18(data: Dictionary) -> Dictionary:
	data["tile_wasteland_state"] = []
	data["version"] = 18
	return data

## `player_progression` is a free-form Dictionary tracked by main.gd.
## Default-empty so existing tests / call sites that don't yet pass
## progression don't break the signature; the caller stays in charge of
## defaulting missing keys on the load side.
static func save_game(grid_world: Node2D, player: Node2D, player_inventory: Inventory, player_progression: Dictionary = {}) -> bool:
	# v11: serialize ONLY player-modified tiles. The world is reconstructed
	# from world_seed + worldgen_version on load.
	var modifications_data: Array = []
	for tile_key in grid_world.tile_modifications:
		var pos: Vector2i = tile_key
		var t: Tile = grid_world.tile_modifications[pos]
		modifications_data.append([pos.x, pos.y, t.base, t.overlay, t.resource_node])

	var buildings_data: Array = []
	for anchor_key in grid_world.buildings:
		var b: Building = grid_world.buildings[anchor_key]
		buildings_data.append(b.to_dict())

	# v12: serialize explored regions (state >= 1). Active state collapses to
	# fog on save; load-time vision update re-derives active from player pos.
	var explored_data: Array = []
	for region in grid_world.region_visibility.keys():
		if int(grid_world.region_visibility[region]) >= 1:
			explored_data.append([region.x, region.y])

	# v14: serialize resource_state_modifications. Generic shape:
	#   ore  → [x, y, {"richness": N}]
	#   tree → [x, y, {"regrowth_remaining": F}]
	# Inner dict can grow new keys for future resource types without bumping
	# the save schema; only the field shape change required v13→v14.
	var resource_mods_data: Array = []
	for pos in grid_world.resource_state_modifications.keys():
		var state: Dictionary = grid_world.resource_state_modifications[pos]
		# duplicate() so save snapshot can't mutate via shared reference.
		resource_mods_data.append([pos.x, pos.y, state.duplicate()])

	# v16: serialize tile_soil_modifications. Sparse — only modified tiles
	# appear (default TILE_SOIL_FULL = 100 is implicit, absent).
	# Shape: Array of [x, y, soil_health] where (x, y) is a tile position.
	var tile_soil_data: Array = []
	for pos in grid_world.tile_soil_modifications.keys():
		tile_soil_data.append([pos.x, pos.y, int(grid_world.tile_soil_modifications[pos])])

	# v17: serialize tile_fertilizer_state. Sparse — only tiles with active
	# boost appear. Shape: Array of [x, y, tier, remaining_sec] where tier
	# is an Items.Type (COMPOST_LOW, COMPOST_MID, or COMPOST_HIGH at v18)
	# and remaining is the seconds left until the boost expires. Absent
	# tile = no boost.
	var tile_fert_data: Array = []
	for pos in grid_world.tile_fertilizer_state.keys():
		var s: Dictionary = grid_world.tile_fertilizer_state[pos]
		tile_fert_data.append([pos.x, pos.y, int(s["tier"]), float(s["remaining"])])

	# v18: serialize tile_wasteland_state. Sparse — only tiles in grace
	# OR scarred appear. Shape: Array of [x, y, scarred_bool,
	# decay_remaining_float]. Both fields persist (grace remaining
	# survives save/load so a tile mid-scarring picks up where it left
	# off). Absent tile = healthy.
	var tile_wasteland_data: Array = []
	for pos in grid_world.tile_wasteland_state.keys():
		var ws: Dictionary = grid_world.tile_wasteland_state[pos]
		tile_wasteland_data.append([pos.x, pos.y, bool(ws.get("scarred", false)), float(ws.get("decay_remaining", 0.0))])

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"world_seed": grid_world.world_seed,
		"worldgen_version": WorldGenerator.VERSION,
		"player": [player.global_position.x, player.global_position.y],
		"tick": TickSystem.current_tick,
		"tile_modifications": modifications_data,
		"resource_state_modifications": resource_mods_data,
		"tile_soil_modifications": tile_soil_data,
		"tile_fertilizer_state": tile_fert_data,
		"tile_wasteland_state": tile_wasteland_data,
		"explored_regions": explored_data,
		"buildings": buildings_data,
		"player_inventory": player_inventory.to_array(),
		"player_progression": player_progression,
	}

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save file for writing: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## Returns a LoadResult. Convention:
## - result.success == false, error_message == "" → no save file (silent).
## - result.success == false, error_message != "" → load failed; caller surfaces error.
## - result.success == true → grid_world / player / player_inventory mutated;
##   result.player_progression carries any progression state the caller needs to apply.
static func load_game(grid_world: Node2D, player: Node2D, player_inventory: Inventory) -> LoadResult:
	var result := LoadResult.new()
	if not FileAccess.file_exists(save_path):
		return result   # silent failure; treat as "fresh start"

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		result.error_message = "Could not open save file for reading."
		push_error(result.error_message)
		return result
	var text: String = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		result.error_message = "Save file is corrupt or unreadable."
		push_error(result.error_message)
		return result

	var data: Dictionary = parsed
	var version: int = int(data.get("version", 0))
	# Migration framework (session-save-migration): older saves migrate
	# forward through the MIGRATIONS chain. Newer saves (running an old
	# binary) hard-fail — backward migration is out of scope.
	if version < SAVE_VERSION:
		var migrated = _try_migrate(data, version, SAVE_VERSION)
		if migrated == null:
			# Gap in the chain (e.g., v14 → v18 has no path), or a migration
			# returned malformed data. Caller's post-3.5 hotfix catches and
			# regenerates fresh world; player isn't stranded but their save
			# data is genuinely lost.
			result.error_message = "Save migration failed: no path from v%d to v%d." % [version, SAVE_VERSION]
			push_error(result.error_message)
			if not _is_test_fixture_path(save_path):
				OS.alert(result.error_message + "\n\nA fresh world will be generated. Original save will be overwritten on next F5.", "Save incompatible")
			return result
		data = migrated
		version = int(data.get("version", 0))   # now equals SAVE_VERSION
	elif version > SAVE_VERSION:
		# Forward-incompat: save is from a newer game binary than what's
		# running. Migration framework only walks forward; can't downgrade.
		var native_path: String = ProjectSettings.globalize_path(save_path)
		if OS.get_name() == "Windows":
			native_path = native_path.replace("/", "\\")
		var msg: String = "Save is v%d; this game is v%d.\n\nUpdate the game to load this save, or delete to start fresh:\n%s" % [version, SAVE_VERSION, native_path]
		result.error_message = "Save is from a newer game (v%d vs v%d)." % [version, SAVE_VERSION]
		push_error(msg)
		if not _is_test_fixture_path(save_path):
			OS.alert(msg, "Save incompatible")
		return result

	# v11: also hard-fail on worldgen_version mismatch. Any change to procgen
	# logic produces a different world from the same seed — applying old
	# modifications onto a different terrain would silently corrupt the save.
	var saved_worldgen_version: int = int(data.get("worldgen_version", 0))
	if saved_worldgen_version != WorldGenerator.VERSION:
		var native_path: String = ProjectSettings.globalize_path(save_path)
		if OS.get_name() == "Windows":
			native_path = native_path.replace("/", "\\")
		var msg: String = "Save was generated with worldgen v%d; current version is v%d.\n\nProcgen logic changed; old saves cannot be regenerated correctly. Delete the file to start fresh:\n%s" % [saved_worldgen_version, WorldGenerator.VERSION, native_path]
		result.error_message = "Worldgen version mismatch (v%d vs v%d) — see dialog." % [saved_worldgen_version, WorldGenerator.VERSION]
		push_error(msg)
		if not _is_test_fixture_path(save_path):
			OS.alert(msg, "Save incompatible")
		return result

	var player_pos: Array = data.get("player", [0, 0])
	player.global_position = Vector2(float(player_pos[0]), float(player_pos[1]))

	grid_world.buildings.clear()
	grid_world.occupied.clear()
	TickSystem.current_tick = int(data.get("tick", 0))

	# v11 procgen rehydration: regenerate the canonical world from the seed,
	# then apply player modifications on top.
	var saved_seed: int = int(data.get("world_seed", 0))
	var generator := WorldGenerator.new()
	generator.generate(grid_world, saved_seed)

	# Apply player modifications. Each entry overwrites the canonical tile
	# at that position — represents what the player did to that tile.
	# Also sync resource_state: if a modification cleared the resource_node,
	# erase any stale richness state; otherwise leave (richness regenerated).
	for entry in data.get("tile_modifications", []):
		var pos := Vector2i(int(entry[0]), int(entry[1]))
		var rnode: int = int(entry[4]) if entry.size() > 4 else ResourceNodes.DEFAULT
		var modified := Tile.new(int(entry[2]), int(entry[3]), rnode)
		grid_world.tiles[pos] = modified
		grid_world.tile_modifications[pos] = modified
		if modified.resource_node == ResourceNodes.Type.NONE:
			grid_world.resource_state.erase(pos)

	# v14: apply resource_state_modifications (generic Dict shape).
	# WorldGenerator already restored canonical resource_state from seed
	# (with original_richness for ore patches); this overlay merges the
	# saved state fields on top:
	#   {"richness": N}            → ore: overwrite richness, keep original
	#   {"regrowth_remaining": F}  → tree: insert regrowth state (tile.resource_node
	#                                already cleared by tile_modifications above)
	grid_world.resource_state_modifications.clear()
	for entry in data.get("resource_state_modifications", []):
		var rs_pos := Vector2i(int(entry[0]), int(entry[1]))
		var rs_state: Dictionary = entry[2] if entry.size() > 2 and entry[2] is Dictionary else {}
		# Store the modification as-is (defensive copy).
		grid_world.resource_state_modifications[rs_pos] = rs_state.duplicate()
		# Merge into resource_state. For ore tiles, the canonical state already
		# has richness + original_richness from procgen — overwrite richness.
		# For tree-regrowth tiles, the canonical state may not exist (tree was
		# at default mature) — create the entry from the saved dict.
		if rs_state.has("richness"):
			if grid_world.resource_state.has(rs_pos):
				grid_world.resource_state[rs_pos]["richness"] = int(rs_state["richness"])
			# else: tile not present in canonical resource_state (rare;
			# defensive — skip silently)
		elif rs_state.has("regrowth_remaining"):
			# Tree regrowth: canonical state is "mature" (no entry). Insert
			# the regrowth dict so _tick_regrowth picks it up next frame.
			grid_world.resource_state[rs_pos] = rs_state.duplicate()

	# v16: restore tile_soil_modifications. Sparse — absent entries default
	# to TILE_SOIL_FULL (100) on read via tile_soil_health(). Old v15 saves
	# (region-scoped) hard-fail at the version check above; no migration.
	grid_world.tile_soil_modifications.clear()
	for entry in data.get("tile_soil_modifications", []):
		var soil_tile := Vector2i(int(entry[0]), int(entry[1]))
		grid_world.tile_soil_modifications[soil_tile] = int(entry[2])

	# v17: restore tile_fertilizer_state. Sparse — absent tiles have no
	# active boost (default behavior, regen at 1×). Default-empty get() so
	# v16 saves promoted to v17 (after a hard-fail + manual delete + fresh
	# game) just have an empty dict. Pre-v17 saves hard-fail at version
	# check above.
	grid_world.tile_fertilizer_state.clear()
	for entry in data.get("tile_fertilizer_state", []):
		var fert_tile := Vector2i(int(entry[0]), int(entry[1]))
		grid_world.tile_fertilizer_state[fert_tile] = {
			"tier": int(entry[2]),
			"remaining": float(entry[3]),
		}

	# v18: restore tile_wasteland_state. Sparse — absent tiles are
	# healthy (no grace, no scar). Both fields persist so a tile
	# mid-scarring picks up from its saved decay_remaining. Pre-v18
	# saves hard-fail at version check above.
	grid_world.tile_wasteland_state.clear()
	for entry in data.get("tile_wasteland_state", []):
		var ws_tile := Vector2i(int(entry[0]), int(entry[1]))
		grid_world.tile_wasteland_state[ws_tile] = {
			"scarred": bool(entry[2]),
			"decay_remaining": float(entry[3]),
		}

	# v12: restore explored regions as fog. Active state will be set by
	# main.gd's vision update after load completes (running update_vision
	# from the loaded player position).
	grid_world.region_visibility.clear()
	for entry in data.get("explored_regions", []):
		grid_world.region_visibility[Vector2i(int(entry[0]), int(entry[1]))] = 1

	for bdict in data.get("buildings", []):
		var b: Building = Building.from_dict(bdict)
		grid_world.buildings[b.anchor] = b
		var fp: Vector2i = Buildings.footprint_of(b.type)
		for dx in fp.x:
			for dy in fp.y:
				grid_world.occupied[Vector2i(b.anchor.x + dx, b.anchor.y + dy)] = b.anchor

	if data.has("player_inventory"):
		player_inventory.load_array(data["player_inventory"])

	result.player_progression = data.get("player_progression", {})
	result.success = true
	return result

static func save_exists() -> bool:
	return FileAccess.file_exists(save_path)
