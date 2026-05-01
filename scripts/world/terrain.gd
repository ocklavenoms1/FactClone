class_name Terrain
extends RefCounted

## Terrain type enum and shared metadata for tile terrains.
## Add a new terrain by:
##   1. Adding a value to the Type enum (keep order stable for save compatibility).
##   2. Adding an entry to DATA below.
##   3. Optionally adding it to HOTBAR_ORDER.

enum Type {
	GRASS,        ## untouched ground, cannot build
	SOIL_TILLED,  ## farmable soil, can host crops
	PATH,         ## walkable path, slight speed bonus later
	STONE,        ## hard surface, can host machines
	WATER,        ## blocks placement, source for irrigation later
}

const DATA: Dictionary = {
	Type.GRASS:       { "name": "Grass",       "color": Color(0.22, 0.42, 0.22), "buildable": false },
	Type.SOIL_TILLED: { "name": "Tilled Soil", "color": Color(0.45, 0.32, 0.20), "buildable": true  },
	Type.PATH:        { "name": "Path",        "color": Color(0.55, 0.50, 0.40), "buildable": false },
	Type.STONE:       { "name": "Stone",       "color": Color(0.50, 0.50, 0.55), "buildable": true  },
	Type.WATER:       { "name": "Water",       "color": Color(0.20, 0.40, 0.60), "buildable": false },
}

## Order tile types appear in the hotbar (slots 1..N).
const HOTBAR_ORDER: Array = [Type.SOIL_TILLED, Type.PATH, Type.STONE, Type.WATER]

static func name_of(t: int) -> String:
	return DATA[t]["name"]

static func color_of(t: int) -> Color:
	return DATA[t]["color"]

static func is_buildable(t: int) -> bool:
	return DATA[t]["buildable"]
