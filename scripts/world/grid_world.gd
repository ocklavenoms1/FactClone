extends Node2D

## The world. Source of truth for terrain and buildings.
## Sparse storage — only modified tiles exist in the dicts.
##
## Buildings are dumb data (Building class). Behavior is dispatched
## by Buildings.tick_one() / draw_one() based on type.

const TILE_SIZE: int = 32
const GRID_COLOR: Color = Color(0.25, 0.35, 0.25, 0.6)
const VIEW_PADDING_TILES: int = 4

# Default-world lake bounds — exposed so tests and Session B's Pump
# placement logic can reference these coordinates directly.
const DEFAULT_LAKE_X_RANGE: Array = [8, 12]   # [start, end_exclusive]
const DEFAULT_LAKE_Y_RANGE: Array = [4, 6]    # [start, end_exclusive] -> 4×2 = 8 tiles

var tiles: Dictionary = {}            # Vector2i -> Tile
var buildings: Dictionary = {}        # Vector2i (anchor) -> Building
var occupied: Dictionary = {}         # Vector2i (any footprint cell) -> Vector2i (anchor)

var hover_tile: Vector2i = Vector2i.ZERO
var show_hover: bool = false

## Failure reasons set by set_overlay / clear_tile when they return false.
## main.gd reads these to surface a user-friendly toast.
var last_place_error: String = ""
var last_remove_error: String = ""

@export var camera: Camera2D

func _ready() -> void:
	TickSystem.tick.connect(_on_tick)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))

func tile_to_world_origin(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

func tile_to_world_center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)

# ---------- tile accessors ----------

## Read base at pos (default GRASS for tiles not in the dict).
func base_at(pos: Vector2i) -> int:
	if tiles.has(pos):
		return tiles[pos].base
	return Terrain.DEFAULT_BASE

## Read overlay at pos (default NONE for tiles not in the dict).
func overlay_at(pos: Vector2i) -> int:
	if tiles.has(pos):
		return tiles[pos].overlay
	return Terrain.DEFAULT_OVERLAY

## Convenience: is this a water tile?
func is_water_at(pos: Vector2i) -> bool:
	return base_at(pos) == Terrain.Base.WATER

# ---------- placement / removal ----------

## Paint an overlay at pos. Returns true on success.
## Sets last_place_error on failure.
func set_overlay(pos: Vector2i, overlay: int) -> bool:
	last_place_error = ""
	if has_building_at(pos):
		last_place_error = "Can't paint terrain under a building"
		return false
	var base: int = base_at(pos)
	var current_overlay: int = overlay_at(pos)
	if not Terrain.can_place_overlay(overlay, base, current_overlay):
		last_place_error = "Can't place %s on %s" % [
			Terrain.overlay_name(overlay),
			Terrain.effective_name(base, current_overlay),
		]
		return false
	if current_overlay == overlay:
		return true  # idempotent
	# Mutate or insert.
	if tiles.has(pos):
		tiles[pos].overlay = overlay
	else:
		tiles[pos] = Tile.new(Terrain.DEFAULT_BASE, overlay)
	return true

## RMB action. Returns true on success (or harmless no-op).
##   - building present: remove building (always allowed)
##   - overlay present:  clear overlay back to NONE (always allowed; player placed it)
##   - bare base (grass or water): silent no-op (nothing to remove)
func clear_tile(pos: Vector2i) -> bool:
	last_remove_error = ""
	if has_building_at(pos):
		remove_building_at(pos)
		return true
	if not tiles.has(pos):
		return true  # implicit grass — nothing here
	var t: Tile = tiles[pos]
	if t.has_overlay():
		t.overlay = Terrain.Overlay.NONE
		# If the entry collapses to pure default, drop it.
		if t.base == Terrain.DEFAULT_BASE:
			tiles.erase(pos)
		return true
	# Bare base tile (water, or an explicit grass entry — though we don't keep those).
	return true

## Seed a fresh world with natural features. Called by main.gd ONLY when
## no save file exists. Currently: a fixed 4×2 water lake at tile coords
## (8..11, 4..5) — 8 tiles total, 6+ tiles east of player spawn (2, 2).
## Coordinates exposed via DEFAULT_LAKE_X_RANGE / Y_RANGE for tests.
func generate_default_world() -> void:
	for x in range(DEFAULT_LAKE_X_RANGE[0], DEFAULT_LAKE_X_RANGE[1]):
		for y in range(DEFAULT_LAKE_Y_RANGE[0], DEFAULT_LAKE_Y_RANGE[1]):
			tiles[Vector2i(x, y)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)

# ---------- buildings ----------

func has_building_at(pos: Vector2i) -> bool:
	return occupied.has(pos)

func building_at(pos: Vector2i) -> Building:
	if not occupied.has(pos):
		return null
	return buildings.get(occupied[pos], null)

## Footprint cells for a building of given type with anchor at `pos`.
func _footprint_cells(t: int, pos: Vector2i) -> Array:
	var fp: Vector2i = Buildings.footprint_of(t)
	var cells: Array = []
	for dx in fp.x:
		for dy in fp.y:
			cells.append(Vector2i(pos.x + dx, pos.y + dy))
	return cells

## Can a building of `type` be placed with anchor at `pos`?
## Checks footprint vacancy + overlay compatibility (buildings sit on
## overlays, never directly on water/grass).
func can_place_building(t: int, pos: Vector2i) -> bool:
	var allowed_overlays: Array = Buildings.requires_overlay(t)
	for cell in _footprint_cells(t, pos):
		if has_building_at(cell):
			return false
		if not (overlay_at(cell) in allowed_overlays):
			return false
	return true

func place_building(t: int, pos: Vector2i, dir: int = 0) -> bool:
	if not can_place_building(t, pos):
		return false
	var b: Building = Buildings.make(t, pos, dir)
	if b == null:
		return false
	buildings[pos] = b
	for cell in _footprint_cells(t, pos):
		occupied[cell] = pos
	return true

func remove_building_at(pos: Vector2i) -> bool:
	if not occupied.has(pos):
		return false
	var anchor: Vector2i = occupied[pos]
	var b: Building = buildings.get(anchor, null)
	if b == null:
		return false
	for cell in _footprint_cells(b.type, anchor):
		occupied.erase(cell)
	buildings.erase(anchor)
	return true

# ---------- simulation ----------

func _on_tick(_tick_no: int) -> void:
	# Two-pass tick: pass 1 mutates self only, pass 2 hands items to neighbors.
	# Reading neighbor state in pass 2 is safe because pass 1 has finished
	# everywhere — order-independent for chain belts.
	for anchor in buildings:
		Buildings.tick_one(buildings[anchor], self)
	for anchor in buildings:
		Buildings.post_tick_one(buildings[anchor], self)

## Find any drainable building (harvester, chest) adjacent to or under
## the given tile. Returns the Building or null.
func find_adjacent_drainable(center: Vector2i) -> Building:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p: Vector2i = center + Vector2i(dx, dy)
			if has_building_at(p):
				var b: Building = building_at(p)
				if b != null and Buildings.is_player_drainable(b.type):
					return b
	return null

# ---------- rendering ----------

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var view_min: Vector2
	var view_max: Vector2
	if camera:
		var half = get_viewport_rect().size * 0.5 / camera.zoom
		view_min = camera.global_position - half
		view_max = camera.global_position + half
	else:
		view_min = Vector2.ZERO
		view_max = get_viewport_rect().size

	var min_tile: Vector2i = world_to_tile(view_min) - Vector2i(VIEW_PADDING_TILES, VIEW_PADDING_TILES)
	var max_tile: Vector2i = world_to_tile(view_max) + Vector2i(VIEW_PADDING_TILES, VIEW_PADDING_TILES)

	# Terrain tiles — base first, overlay on top.
	for tile_key in tiles:
		var tp: Vector2i = tile_key
		if tp.x < min_tile.x or tp.x > max_tile.x:
			continue
		if tp.y < min_tile.y or tp.y > max_tile.y:
			continue
		var t: Tile = tiles[tp]
		var rect: Rect2 = Rect2(tp.x * TILE_SIZE, tp.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		# Base layer: only draw if non-default (default grass is the canvas background).
		if t.base != Terrain.DEFAULT_BASE:
			draw_rect(rect, Terrain.base_color(t.base), true)
		# Overlay layer: draw if present.
		if t.overlay != Terrain.Overlay.NONE:
			draw_rect(rect, Terrain.overlay_color(t.overlay), true)

	# Grid lines.
	for x in range(min_tile.x, max_tile.x + 1):
		var x_pos: float = x * TILE_SIZE
		draw_line(Vector2(x_pos, min_tile.y * TILE_SIZE), Vector2(x_pos, max_tile.y * TILE_SIZE), GRID_COLOR, 1.0)
	for y in range(min_tile.y, max_tile.y + 1):
		var y_pos: float = y * TILE_SIZE
		draw_line(Vector2(min_tile.x * TILE_SIZE, y_pos), Vector2(max_tile.x * TILE_SIZE, y_pos), GRID_COLOR, 1.0)

	# Buildings.
	for anchor_key in buildings:
		var anchor: Vector2i = anchor_key
		var b: Building = buildings[anchor]
		var fp: Vector2i = Buildings.footprint_of(b.type)
		# Cull: skip if entire footprint is offscreen.
		if anchor.x + fp.x - 1 < min_tile.x or anchor.x > max_tile.x:
			continue
		if anchor.y + fp.y - 1 < min_tile.y or anchor.y > max_tile.y:
			continue
		Buildings.draw_one(b, self, tile_to_world_origin(anchor), TILE_SIZE)

	# Hover indicator.
	if show_hover:
		var hover_rect: Rect2 = Rect2(hover_tile.x * TILE_SIZE, hover_tile.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		var blocked: bool = tiles.has(hover_tile) or has_building_at(hover_tile)
		var hover_color: Color = Color(1.0, 0.4, 0.4, 0.6) if blocked else Color(1.0, 1.0, 1.0, 0.5)
		draw_rect(hover_rect, hover_color, false, 2.0)
