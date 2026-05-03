extends Control

## Minimap — always-visible top-right HUD widget showing 7×7 regions of
## fog-of-war world state centered on player.
##
## Renders by SAMPLING the MapPanel's cached map texture via
## draw_texture_rect_region (no duplicate pixel work — fully reuses the
## main map's incremental rendering and dirty tracking).
##
## Visibility states match the main map (unrevealed black / fog × 0.45 /
## active full color) since we sample the same source.
##
## Hidden when M-map or inventory grid is open (main.gd toggles visibility).
## Click-through (mouse_filter = IGNORE) so cursor over minimap area still
## reaches the world (e.g., player can place a building "behind" the minimap).

const MINIMAP_SIZE: int = 224           # 7×7 regions × 32 tiles × 1 px/tile-display
const MARGIN_RIGHT: int = 20
const MARGIN_TOP: int = 10

# Source rect dimensions in main map texture coordinates.
# 7×7 regions × 32 tiles/region × 2 pixels/tile (MapPanel.PIXELS_PER_TILE) = 448
const SAMPLE_TEX_PIXELS: int = 448

const BORDER_COLOR: Color = Color(0.65, 0.55, 0.35, 0.95)
const PLAYER_MARKER_COLOR: Color = Color(1.0, 0.92, 0.4)
const PLAYER_MARKER_RADIUS: float = 3.0

# Set by main.gd at _ready.
var world: GridWorld = null
var player: Node2D = null
var map_panel: MapPanel = null

func _ready() -> void:
	# Click-through: minimap doesn't intercept input, world clicks pass through.
	# Cursor over the minimap area still reaches the world (e.g., player can
	# place a building "behind" the minimap).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchors set in scene file to fill viewport — Control's local coord
	# system matches viewport coords so the minimap_rect computed in _draw
	# (using absolute viewport-relative coords) renders at the right place.

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if map_panel == null or player == null or world == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var minimap_rect := Rect2(
		viewport_size.x - float(MINIMAP_SIZE) - float(MARGIN_RIGHT),
		float(MARGIN_TOP),
		float(MINIMAP_SIZE),
		float(MINIMAP_SIZE),
	)

	# Black underlay — guarantees clean black where the source rect extends
	# past texture bounds (player near world edge), and provides a base layer
	# while background build is in progress.
	draw_rect(minimap_rect, Color(0, 0, 0, 1), true)

	# Source rect: 448×448 pixel region of main map texture, centered on player.
	var player_tex: Vector2 = _player_tex_position()
	var half: float = float(SAMPLE_TEX_PIXELS) * 0.5
	var src_rect := Rect2(player_tex.x - half, player_tex.y - half, float(SAMPLE_TEX_PIXELS), float(SAMPLE_TEX_PIXELS))

	var tex: ImageTexture = map_panel.get_shared_texture()
	if tex != null:
		# clip_uv=true (default) clips source UVs at texture bounds. Since the
		# texture's edges are unrevealed (black-filled at init), past-world
		# pixels show as black — correct behavior for "world doesn't extend
		# past boundary."
		draw_texture_rect_region(tex, minimap_rect, src_rect)

	# Border for definition against background.
	draw_rect(minimap_rect, BORDER_COLOR, false, 1.0)

	# Player marker — yellow dot at minimap center.
	var center: Vector2 = minimap_rect.get_center()
	draw_circle(center, PLAYER_MARKER_RADIUS, PLAYER_MARKER_COLOR)
	draw_arc(center, PLAYER_MARKER_RADIUS, 0.0, TAU, 16, Color(0, 0, 0, 1), 1.0)

## Convert player world-space position to main map texture coordinates.
func _player_tex_position() -> Vector2:
	var tile_x: float = player.global_position.x / float(GridWorld.TILE_SIZE)
	var tile_y: float = player.global_position.y / float(GridWorld.TILE_SIZE)
	var tex_x: float = (tile_x - float(WorldGenerator.WORLD_MIN)) * float(MapPanel.PIXELS_PER_TILE)
	var tex_y: float = (tile_y - float(WorldGenerator.WORLD_MIN)) * float(MapPanel.PIXELS_PER_TILE)
	return Vector2(tex_x, tex_y)
