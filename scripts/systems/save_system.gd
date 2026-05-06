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
const SAVE_VERSION: int = 15
const DEFAULT_SAVE_PATH: String = "user://save_slot_1.json"

## Path used by save_game / load_game / save_exists. Tests override this
## to a scratch path so they don't clobber the player's save. Restore to
## DEFAULT_SAVE_PATH after the test.
static var save_path: String = DEFAULT_SAVE_PATH

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

	# v15: serialize region_soil_modifications. Sparse — only depleted
	# regions appear (default SOIL_HEALTH_FULL = 100 is implicit, absent).
	# Shape: Array of [rx, ry, soil_health].
	var region_soil_data: Array = []
	for region in grid_world.region_soil_modifications.keys():
		region_soil_data.append([region.x, region.y, int(grid_world.region_soil_modifications[region])])

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"world_seed": grid_world.world_seed,
		"worldgen_version": WorldGenerator.VERSION,
		"player": [player.global_position.x, player.global_position.y],
		"tick": TickSystem.current_tick,
		"tile_modifications": modifications_data,
		"resource_state_modifications": resource_mods_data,
		"region_soil_modifications": region_soil_data,
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
	if version != SAVE_VERSION:
		# Normalize path slashes for the user-facing dialog. globalize_path
		# returns forward slashes on Windows; convert to native backslashes
		# so the path is copy-pasteable into File Explorer / cmd.
		var native_path: String = ProjectSettings.globalize_path(save_path)
		if OS.get_name() == "Windows":
			native_path = native_path.replace("/", "\\")
		var msg: String = "Save file is v%d; current version is v%d.\n\nOld saves are not compatible. Delete the file to start fresh:\n%s" % [version, SAVE_VERSION, native_path]
		result.error_message = "Save incompatible (v%d vs v%d) — see dialog." % [version, SAVE_VERSION]
		push_error(msg)
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

	# v15: restore region soil_health modifications. Sparse — absent entries
	# default to SOIL_HEALTH_FULL (100) on read via region_soil_health().
	# Old v14 saves miss this field entirely (hard-fail prevented load), but
	# defensive .get() with default keeps the additive shape forward-compat.
	grid_world.region_soil_modifications.clear()
	for entry in data.get("region_soil_modifications", []):
		var soil_region := Vector2i(int(entry[0]), int(entry[1]))
		grid_world.region_soil_modifications[soil_region] = int(entry[2])

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
