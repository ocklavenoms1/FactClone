extends Node2D

## The world. Source of truth for terrain and buildings.
## Sparse storage — only modified tiles exist in the dicts.
##
## Buildings are dumb data (Building class). Behavior is dispatched
## by Buildings.tick_one() / draw_one() based on type.

const TILE_SIZE: int = 32
const GRID_COLOR: Color = Color(0.25, 0.35, 0.25, 0.6)
const VIEW_PADDING_TILES: int = 4
const DEFAULT_TERRAIN: int = Terrain.Type.GRASS

var tiles: Dictionary = {}            # Vector2i -> Tile
var buildings: Dictionary = {}        # Vector2i (anchor) -> Building
var occupied: Dictionary = {}         # Vector2i (any footprint cell) -> Vector2i (anchor) — fast collision

var hover_tile: Vector2i = Vector2i.ZERO
var show_hover: bool = false

@export var camera: Camera2D

func _ready() -> void:
	TickSystem.tick.connect(_on_tick)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))

func tile_to_world_origin(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

func tile_to_world_center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)

# ---------- terrain ----------

func set_terrain(pos: Vector2i, terrain_type: int) -> void:
	if has_building_at(pos):
		return  # don't change terrain under a building
	if terrain_type == DEFAULT_TERRAIN:
		tiles.erase(pos)
		return
	if tiles.has(pos):
		tiles[pos].terrain = terrain_type
	else:
		tiles[pos] = Tile.new(terrain_type)

func get_terrain(pos: Vector2i) -> int:
	if tiles.has(pos):
		return tiles[pos].terrain
	return DEFAULT_TERRAIN

func clear_tile(pos: Vector2i) -> void:
	if has_building_at(pos):
		remove_building_at(pos)
	else:
		tiles.erase(pos)

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
## Checks footprint vacancy + terrain compatibility.
func can_place_building(t: int, pos: Vector2i) -> bool:
	var allowed_terrains: Array = Buildings.requires_terrain(t)
	for cell in _footprint_cells(t, pos):
		if has_building_at(cell):
			return false
		if not (get_terrain(cell) in allowed_terrains):
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

	# Terrain tiles.
	for tile_key in tiles:
		var tp: Vector2i = tile_key
		if tp.x < min_tile.x or tp.x > max_tile.x:
			continue
		if tp.y < min_tile.y or tp.y > max_tile.y:
			continue
		var rect: Rect2 = Rect2(tp.x * TILE_SIZE, tp.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		draw_rect(rect, Terrain.color_of(tiles[tp].terrain), true)

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
