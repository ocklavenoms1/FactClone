class_name Items
extends RefCounted

## Item type registry. Items are the things that flow through the game:
## crops, processed goods, eventually fluids and intermediates.
##
## Add a new item: APPEND to Type enum (never reorder — type ints are
## stored in saves). Add a DATA entry.

enum Type {
	WHEAT,
	FLOUR,
	YEAST,
	DOUGH,
	SUGAR_BEET,
	SUGAR,
	GRAIN,
	STRAW,
	RISEN_DOUGH,
	BREAD,
	LOAF_PACK,
	FUEL_BRIQUETTE,
}

const DATA: Dictionary = {
	Type.WHEAT:          { "name": "Wheat",          "color": Color(0.95, 0.80, 0.25), "max_stack": 100 },
	Type.FLOUR:          { "name": "Flour",          "color": Color(0.95, 0.92, 0.85), "max_stack": 100 },
	Type.YEAST:          { "name": "Yeast",          "color": Color(0.85, 0.75, 0.55), "max_stack":  50 },
	Type.DOUGH:          { "name": "Dough",          "color": Color(0.92, 0.86, 0.70), "max_stack":  50 },
	Type.SUGAR_BEET:     { "name": "Sugar Beet",     "color": Color(0.65, 0.20, 0.30), "max_stack": 100 },
	Type.SUGAR:          { "name": "Sugar",          "color": Color(0.98, 0.96, 0.94), "max_stack": 100 },
	Type.GRAIN:          { "name": "Grain",          "color": Color(0.88, 0.72, 0.32), "max_stack": 100 },
	Type.STRAW:          { "name": "Straw",          "color": Color(0.85, 0.78, 0.40), "max_stack": 100 },
	Type.RISEN_DOUGH:    { "name": "Risen Dough",    "color": Color(0.95, 0.88, 0.74), "max_stack":  50 },
	Type.BREAD:          { "name": "Bread",          "color": Color(0.78, 0.55, 0.30), "max_stack":  50 },
	Type.LOAF_PACK:      { "name": "Loaf Pack",      "color": Color(0.55, 0.40, 0.25), "max_stack":  50 },
	Type.FUEL_BRIQUETTE: { "name": "Fuel Briquette", "color": Color(0.30, 0.22, 0.18), "max_stack": 100 },
}

static func name_of(t: int) -> String:
	return DATA[t]["name"]

static func color_of(t: int) -> Color:
	return DATA[t]["color"]

static func max_stack_of(t: int) -> int:
	return DATA[t]["max_stack"]
