class_name Buildings
extends RefCounted

## Building type registry. Every placeable machine gets:
##  - an enum value here (keep order stable for save compatibility)
##  - an entry in DATA (display + footprint metadata)
##  - a logic file (e.g. planter.gd) implementing tick / draw / make
##  - a case in `make()`, `tick_one()`, `post_tick_one()`, `draw_one()` below
##
## CHECKLIST FOR ADDING A BUILDING:
##   1. Add to Type enum below (APPEND ONLY — never reorder, breaks saves).
##   2. Add a DATA entry (name, swatch_color, footprint, requires_terrain, flags).
##   3. Create scripts/world/<name>.gd with `make`, `draw`,
##      and optionally `tick`, `info_lines`, `drain_into`.
##   4. Add case in `make()`.
##   5. Add case in `tick_one()` if the building does anything per-tick.
##   6. Add case in `post_tick_one()` only if it has phase-2 (handoff) logic (belts).
##   7. Add case in `draw_one()`.
##   8. Add case in `drain_into_player()` if `player_drainable: true`.
##   9. Add case in `info_lines_for()` if you want a custom info panel display.
##  10. Add a hotbar slot in scripts/ui/hotbar.gd if it should be placeable.
##
## Future processor machines (Oven, Press, etc.) are usually just steps 1-4
## + 7 + 9-10 because they reuse Processor.tick.

enum Type {
	PLANTER,
	HARVESTER,
	BELT,
	MILL,
	CHEST,
	PIPE,
	PUMP,
	MIXER,
	THRESHER,
	PROOFER,
	OVEN,
	PACKAGER,
	BRIQUETTER,
	YEAST_CULTURE,
	SUGAR_PRESS,
	# Cloth chain — enum slots reserved by Session E groundwork.
	# DATA + make()/tick_one()/draw_one() dispatch land when the buildings
	# themselves ship. Recipes already reference these enum values.
	RETTER,
	LOOM,
	TAILOR,
}

const DATA: Dictionary = {
	Type.PLANTER: {
		"name": "Planter",
		"swatch_color": Color(0.4, 0.6, 0.3),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.HARVESTER: {
		"name": "Harvester",
		"swatch_color": Color(0.55, 0.55, 0.60),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": true,
	},
	Type.BELT: {
		"name": "Belt",
		"swatch_color": Color(0.30, 0.30, 0.32),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": true,
		"player_drainable": false,
	},
	Type.MILL: {
		"name": "Mill",
		"swatch_color": Color(0.60, 0.55, 0.50),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.CHEST: {
		"name": "Chest",
		"swatch_color": Color(0.50, 0.34, 0.20),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": true,
	},
	Type.PIPE: {
		"name": "Pipe",
		"swatch_color": Color(0.45, 0.55, 0.65),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.PUMP: {
		"name": "Pump",
		"swatch_color": Color(0.30, 0.55, 0.85),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.MIXER: {
		"name": "Mixer",
		"swatch_color": Color(0.65, 0.68, 0.75),
		"footprint": Vector2i(2, 2),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": true,
		"player_drainable": false,
	},
	Type.THRESHER: {
		"name": "Thresher",
		"swatch_color": Color(0.65, 0.55, 0.40),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": true,
		"player_drainable": false,
	},
	Type.PROOFER: {
		"name": "Proofer",
		"swatch_color": Color(0.78, 0.66, 0.50),
		"footprint": Vector2i(2, 2),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": true,
		"player_drainable": false,
	},
	Type.OVEN: {
		"name": "Oven",
		"swatch_color": Color(0.65, 0.32, 0.20),
		"footprint": Vector2i(2, 2),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": true,
		"player_drainable": false,
	},
	Type.PACKAGER: {
		"name": "Packager",
		"swatch_color": Color(0.55, 0.50, 0.45),
		"footprint": Vector2i(2, 2),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": true,
		"player_drainable": false,
	},
	Type.BRIQUETTER: {
		"name": "Briquetter",
		"swatch_color": Color(0.40, 0.35, 0.32),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.YEAST_CULTURE: {
		"name": "Yeast Culture",
		"swatch_color": Color(0.85, 0.75, 0.55),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.SUGAR_PRESS: {
		"name": "Sugar Press",
		"swatch_color": Color(0.65, 0.45, 0.45),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.RETTER: {
		"name": "Retter",
		"swatch_color": Color(0.40, 0.55, 0.45),    # mossy vat green
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.LOOM: {
		"name": "Loom",
		"swatch_color": Color(0.72, 0.50, 0.28),    # warm wood
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.TAILOR: {
		"name": "Tailor",
		"swatch_color": Color(0.42, 0.45, 0.62),    # tailor's slate-blue
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE],
		"supports_direction": false,
		"player_drainable": false,
	},
}

static func name_of(t: int) -> String:
	return DATA[t]["name"]

static func swatch_color_of(t: int) -> Color:
	return DATA[t]["swatch_color"]

static func footprint_of(t: int) -> Vector2i:
	return DATA[t]["footprint"]

static func requires_overlay(t: int) -> Array:
	return DATA[t]["requires_overlay"]

static func supports_direction(t: int) -> bool:
	return DATA[t].get("supports_direction", false)

static func is_player_drainable(t: int) -> bool:
	return DATA[t].get("player_drainable", false)

## Cells immediately outside a building's footprint along a given edge.
## For a 1×1 building, returns one cell (= anchor + DIR_VECS[dir]).
## For a 2×2 building, returns 2 cells along the edge. Generalizes to any size.
##
##   anchor = top-left footprint cell, footprint size from DATA[t].
##
##   N edge: cells at y = anchor.y - 1, x ∈ [anchor.x .. anchor.x + size.x - 1]
##   E edge: cells at x = anchor.x + size.x, y ∈ [anchor.y .. anchor.y + size.y - 1]
##   S edge: cells at y = anchor.y + size.y, x ∈ [anchor.x .. anchor.x + size.x - 1]
##   W edge: cells at x = anchor.x - 1, y ∈ [anchor.y .. anchor.y + size.y - 1]
static func edge_cells(t: int, anchor: Vector2i, dir: int) -> Array:
	var size: Vector2i = footprint_of(t)
	var cells: Array = []
	match dir:
		0:  # DIR_E
			var x: int = anchor.x + size.x
			for dy in size.y:
				cells.append(Vector2i(x, anchor.y + dy))
		1:  # DIR_S
			var y: int = anchor.y + size.y
			for dx in size.x:
				cells.append(Vector2i(anchor.x + dx, y))
		2:  # DIR_W
			var x: int = anchor.x - 1
			for dy in size.y:
				cells.append(Vector2i(x, anchor.y + dy))
		3:  # DIR_N
			var y: int = anchor.y - 1
			for dx in size.x:
				cells.append(Vector2i(anchor.x + dx, y))
	return cells

## All cells immediately outside the footprint, all 4 edges. Useful for
## "scan all neighbors of this building" when no edge is specified.
static func all_edge_cells(t: int, anchor: Vector2i) -> Array:
	var cells: Array = []
	for dir in 4:
		cells.append_array(edge_cells(t, anchor, dir))
	return cells

## Rotate a recipe-declared direction (DIR_E/S/W/N) by the building's
## current orientation. Recipes always declare ports in CANONICAL orientation
## (state.dir = DIR_E = 0). When the player rotates a building, every port
## (solid input, fluid input, output) shifts in lockstep.
##
## Direction enum (Belt.DIR_*): E=0, S=1, W=2, N=3. The values are arranged
## in visual-CW order in Godot's Y-down coordinate system: E → S → W → N → E.
## Hence rotation by the building's dir is just `(recipe_dir + b.dir) % 4`.
##
## Use this everywhere a recipe's prefer_dir is consumed — never read pair[2]
## directly in tick code. Buildings without a `dir` key in state default to
## 0 (canonical orientation), preserving today's behavior for non-rotatable
## buildings and old saves.
static func world_dir(b: Building, recipe_dir: int) -> int:
	if recipe_dir < 0:
		return -1  # no preference; rotation doesn't apply
	var b_dir: int = int(b.state.get("dir", 0))
	return (recipe_dir + b_dir) % 4

## Bool form for reuse — mirrors the DATA flag, but readable at call sites.
static func is_rotatable(t: int) -> bool:
	return DATA[t].get("supports_direction", false)

## `extra` is a per-type free-form payload. For PLANTER it's the crop_type
## (Items.Type) the new planter should grow. Other types ignore it.
static func make(t: int, pos: Vector2i, dir: int = 0, extra = null) -> Building:
	match t:
		Type.PLANTER:
			return Planter.make(pos, int(extra) if extra != null else Planter.DEFAULT_CROP)
		Type.HARVESTER:
			return Harvester.make(pos)
		Type.BELT:
			return Belt.make(pos, dir)
		Type.MILL:
			return Mill.make(pos)
		Type.CHEST:
			return Chest.make(pos)
		Type.PIPE:
			return Pipe.make(pos)
		Type.PUMP:
			return Pump.make(pos)
		Type.MIXER:
			return Mixer.make(pos, dir)
		Type.THRESHER:
			return Thresher.make(pos, dir)
		Type.PROOFER:
			return Proofer.make(pos, dir)
		Type.OVEN:
			return Oven.make(pos, dir)
		Type.PACKAGER:
			return Packager.make(pos, dir)
		Type.BRIQUETTER:
			return Briquetter.make(pos)
		Type.YEAST_CULTURE:
			return YeastCulture.make(pos)
		Type.SUGAR_PRESS:
			return SugarPress.make(pos)
		Type.RETTER:
			return Retter.make(pos)
		Type.LOOM:
			return Loom.make(pos)
		Type.TAILOR:
			return Tailor.make(pos)
	push_error("Buildings.make: unknown type %d" % t)
	return null

static func tick_one(b: Building, world: Node2D) -> void:
	match b.type:
		Type.PLANTER:
			Planter.tick(b)
		Type.HARVESTER:
			Harvester.tick(b, world)
		Type.BELT:
			Belt.tick(b, world)
		Type.CHEST:
			Chest.tick(b, world)
		# All recipe-driven processors share Processor.tick:
		Type.MILL, Type.MIXER, Type.THRESHER, Type.PROOFER, Type.OVEN, \
		Type.PACKAGER, Type.BRIQUETTER, Type.YEAST_CULTURE, Type.SUGAR_PRESS, \
		Type.RETTER, Type.LOOM, Type.TAILOR:
			Processor.tick(b, world)
		# PIPE and PUMP are passive — no per-tick logic in connectivity-only model.

static func post_tick_one(b: Building, world: Node2D) -> void:
	match b.type:
		Type.BELT:
			Belt.post_tick(b, world)

static func draw_one(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	match b.type:
		Type.PLANTER:
			Planter.draw(b, canvas, world_pos, tile_size)
		Type.HARVESTER:
			Harvester.draw(b, canvas, world_pos, tile_size)
		Type.BELT:
			Belt.draw(b, canvas, world_pos, tile_size)
		Type.MILL:
			Mill.draw(b, canvas, world_pos, tile_size)
		Type.CHEST:
			Chest.draw(b, canvas, world_pos, tile_size)
		Type.PIPE:
			Pipe.draw(b, canvas, world_pos, tile_size)
		Type.PUMP:
			Pump.draw(b, canvas, world_pos, tile_size)
		Type.MIXER:
			Mixer.draw(b, canvas, world_pos, tile_size)
		Type.THRESHER:
			Thresher.draw(b, canvas, world_pos, tile_size)
		Type.PROOFER:
			Proofer.draw(b, canvas, world_pos, tile_size)
		Type.OVEN:
			Oven.draw(b, canvas, world_pos, tile_size)
		Type.PACKAGER:
			Packager.draw(b, canvas, world_pos, tile_size)
		Type.BRIQUETTER:
			Briquetter.draw(b, canvas, world_pos, tile_size)
		Type.YEAST_CULTURE:
			YeastCulture.draw(b, canvas, world_pos, tile_size)
		Type.SUGAR_PRESS:
			SugarPress.draw(b, canvas, world_pos, tile_size)
		Type.RETTER:
			Retter.draw(b, canvas, world_pos, tile_size)
		Type.LOOM:
			Loom.draw(b, canvas, world_pos, tile_size)
		Type.TAILOR:
			Tailor.draw(b, canvas, world_pos, tile_size)
	# Post-pass: draw multi-tile footprint border and port indicators on top
	# of every per-type draw. Single helpers handle this for all buildings;
	# moving them out of per-type draws keeps the visual language consistent.
	_draw_multitile_border(b, canvas, world_pos, tile_size)
	_draw_port_indicators(b, canvas, tile_size)

# ---------- post-pass visual helpers ----------

const _MULTITILE_BORDER_COLOR: Color = Color(0.05, 0.04, 0.03)
const _MULTITILE_BORDER_WIDTH: float = 2.0
const _PORT_RADIUS: float = 4.0
const _PORT_COLOR_ITEM: Color = Color(1.0, 0.85, 0.20)        # yellow
const _PORT_COLOR_FLUID: Color = Color(0.30, 0.70, 1.00)      # blue
const _PORT_OUTLINE: Color = Color(0.05, 0.04, 0.03)

## Draw an unmistakable 2px border around the entire footprint of a multi-
## tile building. Single-tile buildings get nothing extra (their own draw
## already paints a tile-bound trim border).
static func _draw_multitile_border(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var fp: Vector2i = footprint_of(b.type)
	if fp.x <= 1 and fp.y <= 1:
		return
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size * fp.x, tile_size * fp.y))
	canvas.draw_rect(rect, _MULTITILE_BORDER_COLOR, false, _MULTITILE_BORDER_WIDTH)

## Draw small filled / hollow circles on each edge cell that hosts a recipe
## port (input or output). Yellow for solid items, blue for fluid. Filled
## means the port currently has a usable neighbor (belt with right item, or
## pipe in pump-bearing component); hollow means the port exists but isn't
## currently functional.
##
## Recipes declare prefer_dir in canonical orientation; world_dir() rotates
## to the building's actual facing. Ports without prefer_dir scan all edges,
## so we don't draw indicators for them — that would be 8 dots on a 2×2,
## visual noise — the info panel still reports them by name.
static func _draw_port_indicators(b: Building, canvas: CanvasItem, tile_size: int) -> void:
	if not b.state.has("recipe_id"):
		return
	var recipe: Dictionary = Recipes.get_recipe(b.state["recipe_id"])
	if recipe.is_empty():
		return

	# Solid inputs.
	for pair in recipe.get("inputs_solid", []):
		var canonical_dir: int = int(pair[2]) if pair.size() >= 3 else -1
		if canonical_dir < 0:
			continue
		var dir: int = world_dir(b, canonical_dir)
		var item_type: int = int(pair[0])
		for cell in edge_cells(b.type, b.anchor, dir):
			var active: bool = _solid_input_active(canvas, cell, item_type)
			_draw_port_dot(canvas, cell, dir, tile_size, _PORT_COLOR_ITEM, active)

	# Solid outputs.
	for pair in recipe.get("outputs_solid", []):
		var canonical_dir: int = int(pair[2]) if pair.size() >= 3 else -1
		if canonical_dir < 0:
			continue
		var dir: int = world_dir(b, canonical_dir)
		var item_type: int = int(pair[0])
		for cell in edge_cells(b.type, b.anchor, dir):
			var active: bool = _solid_output_active(canvas, cell, item_type)
			_draw_port_dot(canvas, cell, dir, tile_size, _PORT_COLOR_ITEM, active)

	# Fluid inputs.
	#   With prefer_dir: per-cell filled/hollow on the rotated edge, same
	#   as solid ports — explicit port pinning, hollow flags missing pipe.
	#   Without prefer_dir (any-edge, today's Mixer water): draw a filled
	#   blue dot ONLY on cells where a pipe is actively connected. Skips
	#   hollow dots to avoid 8-dot noise around a 2×2; still signals
	#   "water flows in here" when the pipe lights up.
	for pair in recipe.get("inputs_fluid", []):
		var canonical_dir: int = int(pair[2]) if pair.size() >= 3 else -1
		if canonical_dir >= 0:
			var dir: int = world_dir(b, canonical_dir)
			for cell in edge_cells(b.type, b.anchor, dir):
				var active: bool = _fluid_active(canvas, cell)
				_draw_port_dot(canvas, cell, dir, tile_size, _PORT_COLOR_FLUID, active)
		else:
			# Any-edge: highlight only active connections.
			for d in 4:
				for cell in edge_cells(b.type, b.anchor, d):
					if _fluid_active(canvas, cell):
						_draw_port_dot(canvas, cell, d, tile_size, _PORT_COLOR_FLUID, true)

## Draw the indicator on the edge cell, offset toward the building so it
## sits on the "inside" of the edge cell (visually attached to the building's
## boundary). Filled = active; hollow ring = inactive.
static func _draw_port_dot(canvas: CanvasItem, cell: Vector2i, port_dir: int, tile_size: int, color: Color, active: bool) -> void:
	var cell_origin: Vector2 = Vector2(cell.x * tile_size, cell.y * tile_size)
	var center: Vector2 = cell_origin + Vector2(tile_size * 0.5, tile_size * 0.5)
	# Push toward the building (opposite of port_dir — the edge cell is one
	# step in port_dir from the building, so subtract to nudge inward).
	var nudge: Vector2 = -Vector2(Belt.DIR_VECS[port_dir]) * (tile_size * 0.40)
	var dot_pos: Vector2 = center + nudge
	if active:
		canvas.draw_circle(dot_pos, _PORT_RADIUS, color)
		canvas.draw_arc(dot_pos, _PORT_RADIUS, 0.0, TAU, 16, _PORT_OUTLINE, 1.0)
	else:
		canvas.draw_arc(dot_pos, _PORT_RADIUS, 0.0, TAU, 16, color, 1.5)

# Connectivity probes — `canvas` here is the GridWorld instance (it's what
# grid_world._draw passes as `self`). GDScript's dynamic dispatch lets us
# call its methods even though the static type is CanvasItem.
static func _solid_input_active(canvas: CanvasItem, cell: Vector2i, item_type: int) -> bool:
	if not canvas.has_building_at(cell):
		return false
	var nb: Building = canvas.building_at(cell)
	if nb == null or nb.type != Type.BELT:
		return false
	for slot_item in nb.state.get("slots", []):
		if int(slot_item) == item_type:
			return true
	return false

static func _solid_output_active(canvas: CanvasItem, cell: Vector2i, _item_type: int) -> bool:
	if not canvas.has_building_at(cell):
		return false
	var nb: Building = canvas.building_at(cell)
	if nb == null:
		return false
	if nb.type == Type.CHEST:
		# Chests almost always have room; treat as active. (Chest.try_insert
		# enforces capacity at tick time.)
		return true
	if nb.type == Type.BELT:
		# Active if any slot is empty — Processor pushes only into open slots.
		for slot_item in nb.state.get("slots", []):
			if int(slot_item) < 0:
				return true
		return false
	return false

static func _fluid_active(canvas: CanvasItem, cell: Vector2i) -> bool:
	# Pipe at this cell that's part of a pump-bearing fluid network.
	if not canvas.has_building_at(cell):
		return false
	var nb: Building = canvas.building_at(cell)
	if nb == null or nb.type != Type.PIPE:
		return false
	# fluid_available_at scans 4-neighbors of `cell` for a connected component.
	# A cell that IS a pipe in a pump component will be true on its own
	# neighbors, so we check the pipe's own component via the same probe at
	# any neighbor — using the cell itself works because the pipe lookup is
	# one step removed in fluid_available_at. Simpler: ask GridWorld directly
	# via its private maps, but those aren't exposed; the public probe at
	# this cell answers "does an adjacent network have a pump", which is
	# weaker than what we want. Use a wrapper.
	return canvas.is_pipe_in_pump_component(cell)

## Drain a player-drainable building into the player's inventory.
## Returns count moved. Returns 0 if `b` is not drainable.
static func drain_into_player(b: Building, dest: Inventory) -> int:
	match b.type:
		Type.HARVESTER:
			return Harvester.drain_into(b, dest)
		Type.CHEST:
			return Chest.drain_into(b, dest)
	return 0

## Lines of human-readable text to render in the Info Panel for the given
## building. Each building file optionally defines `static func info_lines(b)`;
## this dispatches by type. Generic fallback introspects `b.state` keys so
## even un-customized buildings are debuggable.
##
## `world` is forwarded to building types that need it (currently: Processor
## subtypes — Mill and Mixer — to consult the fluid network when reporting
## "what's missing"). Other types ignore it.
static func info_lines_for(b: Building, world = null) -> Array:
	if b == null:
		return []
	match b.type:
		Type.PLANTER:
			return Planter.info_lines(b)
		Type.HARVESTER:
			return Harvester.info_lines(b)
		Type.BELT:
			return Belt.info_lines(b)
		Type.MILL:
			return Processor.info_lines(b, world)
		Type.CHEST:
			return Chest.info_lines(b)
		Type.PIPE:
			return Pipe.info_lines(b)
		Type.PUMP:
			return Pump.info_lines(b)
		# All recipe-driven processors use Processor.info_lines:
		Type.MIXER, Type.THRESHER, Type.PROOFER, Type.OVEN, Type.PACKAGER, \
		Type.BRIQUETTER, Type.YEAST_CULTURE, Type.SUGAR_PRESS, \
		Type.RETTER, Type.LOOM, Type.TAILOR:
			return Processor.info_lines(b, world)
	# Generic fallback: dump state keys.
	var lines: Array = ["(no custom info — generic fallback)"]
	for k in b.state.keys():
		lines.append("%s: %s" % [str(k), str(b.state[k])])
	return lines
