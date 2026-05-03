extends Control

## Info Panel — primary debugging tool.
##
## Activated by pressing `inspect_building` (Q key or middle mouse) while
## hovering a tile. Two target kinds:
##   - BUILDING: shows per-building info_lines (recipe state, port directions,
##     buffers, etc.). Tracks by anchor; auto-closes if building is removed.
##   - RESOURCE: shows resource type + richness (ore) or growth state (tree)
##     from world.resource_state. Auto-closes if the tile loses its
##     resource_node (e.g., player paints over it).
##
## Tracks the inspected target by world coordinate (Vector2i), NOT by object
## reference, so we detect deletion / replacement / paint-over cleanly.

const PANEL_WIDTH: int = 240
const PADDING: int = 10
const HEADER_HEIGHT: int = 22
const LINE_HEIGHT: int = 18
const BG_COLOR: Color = Color(0.10, 0.10, 0.10, 0.88)
const BORDER_COLOR: Color = Color(0.65, 0.55, 0.35, 0.95)
const HEADER_COLOR: Color = Color(1.00, 0.92, 0.55)
const TEXT_COLOR: Color = Color(0.95, 0.95, 0.85)
const SUBTEXT_COLOR: Color = Color(0.70, 0.70, 0.65)

enum TargetKind { NONE, BUILDING, RESOURCE }

var target_kind: int = TargetKind.NONE
var target_anchor: Vector2i = Vector2i.ZERO
var world: Node2D = null

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = -16
	offset_left = -16 - PANEL_WIDTH
	# Below the inventory panel, which sits below the minimap.
	# Layout: minimap top=10..234, gap, inventory top=244..~440 (varies by
	# item count), gap, info panel top=560.
	offset_top = 560
	offset_bottom = offset_top + 40
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false

## Set a building target. Pass null to close.
func set_target(b: Building, w: Node2D) -> void:
	if b == null:
		clear_target()
		return
	target_anchor = b.anchor
	world = w
	target_kind = TargetKind.BUILDING
	visible = true

## Set a resource-tile target.
func set_resource_target(pos: Vector2i, w: Node2D) -> void:
	target_anchor = pos
	world = w
	target_kind = TargetKind.RESOURCE
	visible = true

func clear_target() -> void:
	target_kind = TargetKind.NONE
	visible = false

func _process(_delta: float) -> void:
	match target_kind:
		TargetKind.NONE:
			return
		TargetKind.BUILDING:
			if world == null or not world.has_building_at(target_anchor):
				clear_target()
				return
		TargetKind.RESOURCE:
			if world == null:
				clear_target()
				return
			if not world.tiles.has(target_anchor):
				clear_target()
				return
			var t: Tile = world.tiles[target_anchor]
			if t.resource_node == ResourceNodes.Type.NONE:
				# Resource gone (mined out / removed) — close.
				# Note: overlay-obscures-deposit case can't happen under
				# the "no overlay on deposits" invariant, but the
				# resource_node==NONE check covers the post-mining revert.
				clear_target()
				return
	queue_redraw()

func _draw() -> void:
	match target_kind:
		TargetKind.BUILDING:
			_draw_building()
		TargetKind.RESOURCE:
			_draw_resource()
		_:
			return

# ---------- building draw ----------

func _draw_building() -> void:
	if world == null:
		return
	var b: Building = world.building_at(target_anchor)
	if b == null:
		return

	var lines: Array = Buildings.info_lines_for(b, world)
	var height: float = PADDING * 2 + HEADER_HEIGHT + LINE_HEIGHT * lines.size() + 2
	offset_bottom = offset_top + height

	var rect: Rect2 = Rect2(0, 0, PANEL_WIDTH, height)
	draw_rect(rect, BG_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, 1.5)

	var font: Font = ThemeDB.fallback_font
	var header: String = "%s @ (%d, %d)" % [Buildings.name_of(b.type), target_anchor.x, target_anchor.y]
	draw_string(font, Vector2(PADDING, PADDING + 14), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HEADER_COLOR)
	draw_line(Vector2(PADDING, PADDING + HEADER_HEIGHT - 2), Vector2(PANEL_WIDTH - PADDING, PADDING + HEADER_HEIGHT - 2), SUBTEXT_COLOR, 1.0)
	var y: float = PADDING + HEADER_HEIGHT + 14
	for line in lines:
		draw_string(font, Vector2(PADDING, y), str(line), HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - PADDING * 2, 12, TEXT_COLOR)
		y += LINE_HEIGHT

# ---------- resource draw ----------

func _draw_resource() -> void:
	if world == null or not world.tiles.has(target_anchor):
		return
	var t: Tile = world.tiles[target_anchor]
	var lines: Array = _resource_lines(t)
	var height: float = PADDING * 2 + HEADER_HEIGHT + LINE_HEIGHT * lines.size() + 2
	offset_bottom = offset_top + height

	var rect: Rect2 = Rect2(0, 0, PANEL_WIDTH, height)
	draw_rect(rect, BG_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, 1.5)

	var font: Font = ThemeDB.fallback_font
	var header: String = "%s @ (%d, %d)" % [ResourceNodes.name_of(t.resource_node), target_anchor.x, target_anchor.y]
	draw_string(font, Vector2(PADDING, PADDING + 14), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HEADER_COLOR)
	draw_line(Vector2(PADDING, PADDING + HEADER_HEIGHT - 2), Vector2(PANEL_WIDTH - PADDING, PADDING + HEADER_HEIGHT - 2), SUBTEXT_COLOR, 1.0)
	var y: float = PADDING + HEADER_HEIGHT + 14
	for line in lines:
		draw_string(font, Vector2(PADDING, y), str(line), HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - PADDING * 2, 12, TEXT_COLOR)
		y += LINE_HEIGHT

func _resource_lines(t: Tile) -> Array:
	var lines: Array = []
	var state: Dictionary = world.resource_state.get(target_anchor, {})
	if t.resource_node == ResourceNodes.Type.TREE:
		# Mature tree (no regrowth state means the tree is at canonical full).
		# Chopped+regrowing tiles have resource_node == NONE, so they don't
		# reach this branch via the standard Q-inspect target flow.
		lines.append("Mature (renewable)")
		var wood: int = GridWorld.wood_yield_for_tree(target_anchor)
		lines.append("Yields %d wood" % wood)
		lines.append("Hold Space adjacent to chop")
	elif ResourceNodes.is_ore(t.resource_node):
		# Ore: finite richness, drains 1 per mining tick.
		var richness: int = int(state.get("richness", 0))
		var original: int = int(state.get("original_richness", 0))
		if original > 0:
			var pct: float = 100.0 * float(richness) / float(original)
			lines.append("Richness: %d / %d (%.0f%%)" % [richness, original, pct])
		else:
			lines.append("Richness: %d" % richness)
		lines.append("Hold Space adjacent to mine")
	else:
		lines.append("(no extra info)")
	return lines
