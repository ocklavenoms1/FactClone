class_name Items
extends RefCounted

## Item type registry. Items are the things that flow through the game:
## crops, processed goods, eventually fluids and intermediates.
##
## Add a new item: add to Type enum (keep order!) and add a DATA entry.

enum Type {
	WHEAT,
	FLOUR,
	YEAST,
	DOUGH,
	# RISEN_DOUGH, BREAD, FUEL_BRIQUETTE, ... will land here.
}

const DATA: Dictionary = {
	Type.WHEAT: { "name": "Wheat", "color": Color(0.95, 0.80, 0.25), "max_stack": 100 },
	Type.FLOUR: { "name": "Flour", "color": Color(0.95, 0.92, 0.85), "max_stack": 100 },
	Type.YEAST: { "name": "Yeast", "color": Color(0.85, 0.75, 0.55), "max_stack": 50  },
	Type.DOUGH: { "name": "Dough", "color": Color(0.92, 0.86, 0.70), "max_stack": 50  },
}

static func name_of(t: int) -> String:
	return DATA[t]["name"]

static func color_of(t: int) -> Color:
	return DATA[t]["color"]

static func max_stack_of(t: int) -> int:
	return DATA[t]["max_stack"]
