class_name MapPanel
extends Control

## Map Panel — modal fullscreen world map with three-state visibility.
##
## Activated by `toggle_map` (M key) or closed by Esc / M again.
## Renders the world as a 1024x1024 bitmap texture, cached and updated
## incrementally:
##   - Initial build runs in the background (8 regions/frame from main.gd)
##     so the texture is fully built well before the player opens the map.
##   - Per-region dirty tracking: vision changes / tile modifications mark
##     specific regions dirty; only those redraw on next visible frame.
##   - GPU upload via ImageTexture.update() (~7 µs measured) — effectively free.
##
## Visibility states (per region):
##   0 = unrevealed: black
##   1 = fog:        tile color × 0.45 (dimmed, color identity preserved)
##   2 = active:     tile color × 1.0 (full brightness)
##
## Player position drawn ON TOP each frame as a small bright-yellow circle.

const TEX_SIZE: int = 1024              # full map texture dimension
const PIXELS_PER_TILE: int = 2          # 512 tiles × 2 = 1024
const REGION_TILES: int = 32            # WorldGenerator.REGION_SIZE
const REGION_PIXEL_SIZE: int = REGION_TILES * PIXELS_PER_TILE   # 64

# Fullscreen sizing: map covers whole viewport with substantial pan room
# in BOTH axes. Display scale chosen as 1.5× the viewport MAX-axis (not
# min) so the rendered texture is meaningfully larger than viewport on any
# aspect ratio — both horizontal and vertical drag are visible.
#
# At 1920×1080 viewport: scale = max(2.5, 1920 * 1.5 / 1024) = 2.81
#   → 2880×2880 texture. Pan range ±480 horiz, ±900 vert.
# At 3840×2160 (4K): scale = max(2.5, 3840 * 1.5 / 1024) = 5.62
#   → 5760×5760 texture. Pan range ±960 horiz, ±1800 vert.
const MIN_DISPLAY_SCALE: float = 2.5
const VIEWPORT_OVERSCAN: float = 1.5    # texture is 1.5× viewport max-axis
const FOG_DIMMING: float = 0.45         # fog brightness multiplier

const REGIONS_PER_BUILD_FRAME: int = 8  # incremental build pace

const BORDER_COLOR: Color = Color(0.65, 0.55, 0.35, 0.95)
const PLAYER_MARKER_COLOR: Color = Color(1.0, 0.92, 0.4)
const PLAYER_MARKER_RADIUS: float = 5.0

# Set by main.gd before first use.
var world: GridWorld = null
var player: Node2D = null

var _is_open: bool = false
var _map_image: Image = null
var _map_texture: ImageTexture = null

# Build progression: regions are built in deterministic order. _build_index
# steps through 0..256 over multiple frames at REGIONS_PER_BUILD_FRAME pace.
var _build_index: int = 0
var _build_total: int = 0   # set when build starts; _build_index >= this means done
var _initial_built: bool = false

# Regions changed since last redraw — set externally via mark_region_dirty().
var _dirty_regions: Array[Vector2i] = []

# Pan state — texture_origin is where the top-left of the rendered map
# texture sits in viewport coordinates. Updated by mouse drag; clamped so
# map always covers the viewport (no edges visible past the texture).
var _texture_origin: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_last_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Fill viewport. Mouse filter STOP when open (block world clicks); IGNORE when closed.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	# Initialize image to all-black (unrevealed default).
	_map_image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	_map_image.fill(Color(0, 0, 0, 1))
	_map_texture = ImageTexture.create_from_image(_map_image)
	# Build pace: 256 regions total in our 16x16 world.
	_build_total = (WorldGenerator.REGION_MAX - WorldGenerator.REGION_MIN) * (WorldGenerator.REGION_MAX - WorldGenerator.REGION_MIN)

func is_open() -> bool:
	return _is_open

## Toggle visibility. Called by main.gd from M-key handler.
func toggle() -> void:
	_is_open = not _is_open
	visible = _is_open
	mouse_filter = Control.MOUSE_FILTER_STOP if _is_open else Control.MOUSE_FILTER_IGNORE
	if _is_open:
		# If background build hasn't finished, finish it now (one-time hitch).
		if not _initial_built:
			_finish_initial_build()
		# Drain dirty regions accumulated while closed.
		_apply_dirty_regions()
		# Re-center on player position (per spec: re-centers when M closes and reopens).
		_center_on_player()
		_is_dragging = false
		queue_redraw()

func close() -> void:
	if _is_open:
		toggle()

## Mark a region for redraw on next visible frame. Called by main.gd when
## vision changes (region cross) or when player modifies a tile.
func mark_region_dirty(region: Vector2i) -> void:
	if not _dirty_regions.has(region):
		_dirty_regions.append(region)

func mark_regions_dirty(regions: Array) -> void:
	for r in regions:
		mark_region_dirty(r)

## Mark the region containing a specific tile as dirty. Used when player
## modifies a tile (set_overlay / clear_tile / building placement).
func mark_tile_dirty(tile_pos: Vector2i) -> void:
	mark_region_dirty(GridWorld.region_of(tile_pos))

## Background build step — called from main.gd::_process every frame. Builds
## REGIONS_PER_BUILD_FRAME regions per call until _initial_built is true.
## Per-frame cost ~ 0.8 ms (8 regions × 0.1 ms/region per Q9 measurement).
func tick_background_build() -> void:
	if _initial_built or world == null:
		return
	var end_index: int = min(_build_index + REGIONS_PER_BUILD_FRAME, _build_total)
	while _build_index < end_index:
		var region: Vector2i = _build_order_index_to_region(_build_index)
		_redraw_region(region)
		_build_index += 1
	# Update the shared texture every frame during background build, so the
	# minimap progressively reveals as the build advances (avoids a "snap to
	# full" jolt at the end of the ~0.5s background build).
	_map_texture.update(_map_image)
	if _build_index >= _build_total:
		_initial_built = true

## Public getter for the cached map texture. Used by Minimap (which samples
## a region of this texture each frame via draw_texture_rect_region).
func get_shared_texture() -> ImageTexture:
	return _map_texture

func _finish_initial_build() -> void:
	if _initial_built:
		return
	while _build_index < _build_total:
		var region: Vector2i = _build_order_index_to_region(_build_index)
		_redraw_region(region)
		_build_index += 1
	_initial_built = true
	_map_texture.update(_map_image)

func _apply_dirty_regions() -> void:
	if _dirty_regions.is_empty():
		return
	for r in _dirty_regions:
		_redraw_region(r)
	_dirty_regions.clear()
	_map_texture.update(_map_image)

# ---------- region rendering ----------

## Map a build index 0..255 to a region coordinate. Row-major over the
## full region grid: (rx, ry) where rx = idx % width, ry = idx / width.
func _build_order_index_to_region(idx: int) -> Vector2i:
	var width: int = WorldGenerator.REGION_MAX - WorldGenerator.REGION_MIN
	var rx_offset: int = idx % width
	var ry_offset: int = idx / width
	return Vector2i(WorldGenerator.REGION_MIN + rx_offset, WorldGenerator.REGION_MIN + ry_offset)

## Redraw a single region into _map_image. Writes pixels for each of the
## 32×32 tiles in the region. Visibility state determines brightness.
func _redraw_region(region: Vector2i) -> void:
	if world == null:
		return
	var visibility: int = int(world.region_visibility.get(region, 0))
	var origin_x: int = (region.x * REGION_TILES - WorldGenerator.WORLD_MIN) * PIXELS_PER_TILE
	var origin_y: int = (region.y * REGION_TILES - WorldGenerator.WORLD_MIN) * PIXELS_PER_TILE

	if visibility == 0:
		# Unrevealed: fill region's pixel block with black.
		_map_image.fill_rect(Rect2i(origin_x, origin_y, REGION_PIXEL_SIZE, REGION_PIXEL_SIZE), Color(0, 0, 0, 1))
		return

	# Iterate the region's tiles and paint each as a 2x2 pixel block.
	for tx in range(REGION_TILES):
		for ty in range(REGION_TILES):
			var tile_pos: Vector2i = Vector2i(region.x * REGION_TILES + tx, region.y * REGION_TILES + ty)
			var color: Color = _color_for_tile(tile_pos, visibility)
			_paint_tile_block(origin_x + tx * PIXELS_PER_TILE, origin_y + ty * PIXELS_PER_TILE, color)

func _paint_tile_block(px_x: int, px_y: int, color: Color) -> void:
	# Inline loop instead of fill_rect — fill_rect call overhead exceeds
	# the cost of 4 set_pixel calls at this granularity.
	for dx in PIXELS_PER_TILE:
		for dy in PIXELS_PER_TILE:
			_map_image.set_pixel(px_x + dx, px_y + dy, color)

## Compute the color for a tile, applying visibility-based dimming.
func _color_for_tile(tile_pos: Vector2i, visibility: int) -> Color:
	var color: Color = _base_tile_color(tile_pos)
	# Building marker overlay: if a building is anchored at this tile, tint
	# bright (visible distinction from terrain at map zoom).
	if world.has_building_at(tile_pos):
		color = Color(1.0, 0.55, 0.15)   # bright orange for buildings
	if visibility == 1:
		return Color(color.r * FOG_DIMMING, color.g * FOG_DIMMING, color.b * FOG_DIMMING, 1.0)
	return color

func _base_tile_color(tile_pos: Vector2i) -> Color:
	var t: Tile = world.tiles.get(tile_pos, null)
	if t == null:
		return Color(0.27, 0.55, 0.27)   # default grass green
	if t.is_water():
		return Color(0.20, 0.40, 0.62)   # water blue
	if t.has_overlay():
		match t.overlay:
			Terrain.Overlay.SOIL_TILLED:
				return Color(0.40, 0.28, 0.18)
			Terrain.Overlay.PATH:
				return Color(0.60, 0.50, 0.35)
			Terrain.Overlay.STONE:
				return Color(0.50, 0.50, 0.52)
			_:
				return Color(0.5, 0.5, 0.5)
	if t.resource_node != ResourceNodes.Type.NONE:
		return ResourceNodes.color_of(t.resource_node)
	return Color(0.27, 0.55, 0.27)   # plain grass

# ---------- screen layout + drawing ----------

func _process(_delta: float) -> void:
	if _is_open:
		# Pick up any vision/modification changes that fired while open.
		_apply_dirty_regions()
		queue_redraw()

func _input(event: InputEvent) -> void:
	# Esc closes (M is handled in main.gd to share the close-on-M-while-open path).
	if _is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return
	# Mouse-drag pan: hold left button, move mouse, map shifts under cursor.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_last_pos = event.position
			else:
				_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		var delta: Vector2 = event.position - _drag_last_pos
		_drag_last_pos = event.position
		_texture_origin += delta
		_clamp_texture_origin()
		queue_redraw()

## Compute display scale: large enough that rendered texture is
## VIEWPORT_OVERSCAN × the viewport max-axis. Ensures the texture is
## meaningfully larger than viewport in both axes (so drag-pan is visible
## both horizontally and vertically), with MIN_DISPLAY_SCALE as a floor.
func _display_scale() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	var max_axis: float = max(viewport_size.x, viewport_size.y)
	return max(MIN_DISPLAY_SCALE, max_axis * VIEWPORT_OVERSCAN / float(TEX_SIZE))

## Set _texture_origin so the player's tex position is at the viewport center.
func _center_on_player() -> void:
	if player == null:
		_texture_origin = Vector2.ZERO
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _display_scale()
	var player_tex_x: float = (player.global_position.x / float(GridWorld.TILE_SIZE) - float(WorldGenerator.WORLD_MIN)) * float(PIXELS_PER_TILE)
	var player_tex_y: float = (player.global_position.y / float(GridWorld.TILE_SIZE) - float(WorldGenerator.WORLD_MIN)) * float(PIXELS_PER_TILE)
	# Player should appear at viewport center: viewport_center = origin + player_tex * scale
	# => origin = viewport_center - player_tex * scale
	_texture_origin = viewport_size * 0.5 - Vector2(player_tex_x, player_tex_y) * scale
	_clamp_texture_origin()

## Clamp pan offset so the rendered map texture always covers the viewport
## (no edges visible past the texture). At display scale S, texture is
## TEX_SIZE * S pixels in each axis. Origin must be in:
##   [viewport_size - TEX_SIZE * S, 0]
## If TEX_SIZE * S < viewport_size in some axis (huge window, small scale),
## the texture can't cover viewport — center it instead of clamping.
func _clamp_texture_origin() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _display_scale()
	var tex_size_screen: float = float(TEX_SIZE) * scale
	if tex_size_screen >= viewport_size.x:
		_texture_origin.x = clamp(_texture_origin.x, viewport_size.x - tex_size_screen, 0.0)
	else:
		_texture_origin.x = (viewport_size.x - tex_size_screen) * 0.5
	if tex_size_screen >= viewport_size.y:
		_texture_origin.y = clamp(_texture_origin.y, viewport_size.y - tex_size_screen, 0.0)
	else:
		_texture_origin.y = (viewport_size.y - tex_size_screen) * 0.5

func _draw() -> void:
	if not _is_open:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _display_scale()
	var tex_size_screen: float = float(TEX_SIZE) * scale

	# Solid black fill across the full viewport FIRST. Without this, areas of
	# the Control NOT covered by the texture are transparent — the world below
	# bleeds through. Black fill guarantees the map looks like a fullscreen
	# overlay regardless of texture size or pan position.
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 1), true)

	# Render the texture at scale, positioned by _texture_origin (drag pan state).
	# draw_texture_rect handles scaling automatically.
	var map_rect: Rect2 = Rect2(_texture_origin, Vector2(tex_size_screen, tex_size_screen))
	draw_texture_rect(_map_texture, map_rect, false)

	# Border around the map texture (visible when window > texture and we letterbox).
	draw_rect(map_rect, BORDER_COLOR, false, 2.0)

	# Player position marker, drawn on top.
	if player != null:
		var marker_pos: Vector2 = _player_screen_position()
		draw_circle(marker_pos, PLAYER_MARKER_RADIUS, PLAYER_MARKER_COLOR)
		# Outline for contrast against bright tiles.
		draw_arc(marker_pos, PLAYER_MARKER_RADIUS, 0.0, TAU, 16, Color(0, 0, 0, 1), 1.5)

	# Hint text top-left, slight margin, with shadow.
	var font: Font = ThemeDB.fallback_font
	var hint: String = "Drag to pan · M / Esc to close"
	draw_string(font, Vector2(20, 28), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(19, 27), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.92, 0.6))

## Compute the player marker's screen position given current pan state.
func _player_screen_position() -> Vector2:
	var scale: float = _display_scale()
	var tile_x: float = player.global_position.x / float(GridWorld.TILE_SIZE)
	var tile_y: float = player.global_position.y / float(GridWorld.TILE_SIZE)
	var tex_x: float = (tile_x - float(WorldGenerator.WORLD_MIN)) * float(PIXELS_PER_TILE)
	var tex_y: float = (tile_y - float(WorldGenerator.WORLD_MIN)) * float(PIXELS_PER_TILE)
	return _texture_origin + Vector2(tex_x, tex_y) * scale
