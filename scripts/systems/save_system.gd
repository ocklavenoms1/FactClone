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

const SAVE_VERSION: int = 9
const DEFAULT_SAVE_PATH: String = "user://save_slot_1.json"

## Path used by save_game / load_game / save_exists. Tests override this
## to a scratch path so they don't clobber the player's save. Restore to
## DEFAULT_SAVE_PATH after the test.
static var save_path: String = DEFAULT_SAVE_PATH

## Set by load_game on failure. main.gd reads this to surface a toast.
static var last_load_error: String = ""

static func save_game(grid_world: Node2D, player: Node2D, player_inventory: Inventory) -> bool:
	var tiles_data: Array = []
	for tile_key in grid_world.tiles:
		var pos: Vector2i = tile_key
		var t: Tile = grid_world.tiles[pos]
		tiles_data.append([pos.x, pos.y, t.base, t.overlay, t.resource_node])

	var buildings_data: Array = []
	for anchor_key in grid_world.buildings:
		var b: Building = grid_world.buildings[anchor_key]
		buildings_data.append(b.to_dict())

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"player": [player.global_position.x, player.global_position.y],
		"tick": TickSystem.current_tick,
		"tiles": tiles_data,
		"buildings": buildings_data,
		"player_inventory": player_inventory.to_array(),
	}

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save file for writing: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

static func load_game(grid_world: Node2D, player: Node2D, player_inventory: Inventory) -> bool:
	last_load_error = ""
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		last_load_error = "Could not open save file for reading."
		push_error(last_load_error)
		return false
	var text: String = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		last_load_error = "Save file is corrupt or unreadable."
		push_error(last_load_error)
		return false

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
		last_load_error = "Save incompatible (v%d vs v%d) — see dialog." % [version, SAVE_VERSION]
		push_error(msg)
		OS.alert(msg, "Save incompatible")
		return false

	var player_pos: Array = data.get("player", [0, 0])
	player.global_position = Vector2(float(player_pos[0]), float(player_pos[1]))

	grid_world.tiles.clear()
	grid_world.buildings.clear()
	grid_world.occupied.clear()
	TickSystem.current_tick = int(data.get("tick", 0))

	for entry in data.get("tiles", []):
		var pos := Vector2i(int(entry[0]), int(entry[1]))
		# entry[4] = resource_node (added v8). Use .get-style fallback so a
		# malformed v8 file with truncated entries still loads the base+overlay.
		var rnode: int = int(entry[4]) if entry.size() > 4 else ResourceNodes.DEFAULT
		grid_world.tiles[pos] = Tile.new(int(entry[2]), int(entry[3]), rnode)

	for bdict in data.get("buildings", []):
		var b: Building = Building.from_dict(bdict)
		grid_world.buildings[b.anchor] = b
		var fp: Vector2i = Buildings.footprint_of(b.type)
		for dx in fp.x:
			for dy in fp.y:
				grid_world.occupied[Vector2i(b.anchor.x + dx, b.anchor.y + dy)] = b.anchor

	if data.has("player_inventory"):
		player_inventory.load_array(data["player_inventory"])

	return true

static func save_exists() -> bool:
	return FileAccess.file_exists(save_path)
