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

static func make(t: int, pos: Vector2i, dir: int = 0) -> Building:
	match t:
		Type.PLANTER:
			return Planter.make(pos)
		Type.HARVESTER:
			return Harvester.make(pos)
		Type.BELT:
			return Belt.make(pos, dir)
		Type.MILL:
			return Mill.make(pos)
		Type.CHEST:
			return Chest.make(pos)
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
		Type.MILL:
			Processor.tick(b, world)
		Type.CHEST:
			Chest.tick(b, world)

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
static func info_lines_for(b: Building) -> Array:
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
			return Processor.info_lines(b)
		Type.CHEST:
			return Chest.info_lines(b)
	# Generic fallback: dump state keys.
	var lines: Array = ["(no custom info — generic fallback)"]
	for k in b.state.keys():
		lines.append("%s: %s" % [str(k), str(b.state[k])])
	return lines
