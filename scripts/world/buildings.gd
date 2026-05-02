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
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.THRESHER: {
		"name": "Thresher",
		"swatch_color": Color(0.65, 0.55, 0.40),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.PROOFER: {
		"name": "Proofer",
		"swatch_color": Color(0.78, 0.66, 0.50),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.OVEN: {
		"name": "Oven",
		"swatch_color": Color(0.65, 0.32, 0.20),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
		"player_drainable": false,
	},
	Type.PACKAGER: {
		"name": "Packager",
		"swatch_color": Color(0.55, 0.50, 0.45),
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": false,
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
			return Mixer.make(pos)
		Type.THRESHER:
			return Thresher.make(pos)
		Type.PROOFER:
			return Proofer.make(pos)
		Type.OVEN:
			return Oven.make(pos)
		Type.PACKAGER:
			return Packager.make(pos)
		Type.BRIQUETTER:
			return Briquetter.make(pos)
		Type.YEAST_CULTURE:
			return YeastCulture.make(pos)
		Type.SUGAR_PRESS:
			return SugarPress.make(pos)
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
		Type.PACKAGER, Type.BRIQUETTER, Type.YEAST_CULTURE, Type.SUGAR_PRESS:
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
		Type.BRIQUETTER, Type.YEAST_CULTURE, Type.SUGAR_PRESS:
			return Processor.info_lines(b, world)
	# Generic fallback: dump state keys.
	var lines: Array = ["(no custom info — generic fallback)"]
	for k in b.state.keys():
		lines.append("%s: %s" % [str(k), str(b.state[k])])
	return lines
