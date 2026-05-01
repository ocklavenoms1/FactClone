class_name Fluids
extends RefCounted

## Fluid type registry. Fluids are conceptually distinct from Items — they
## flow through pipes (not belts) and are queried via the world's fluid
## network resolver rather than buffered in machine inventories.
##
## Add a fluid: append to Type enum (never reorder; keep stable for save
## compat) and add an entry to DATA.

enum Type {
	WATER,
	# MILK, OIL, FERTILIZER, ... will land here.
}

const DATA: Dictionary = {
	Type.WATER: { "name": "Water", "color": Color(0.20, 0.50, 0.80) },
}

static func name_of(t: int) -> String:
	return DATA[t]["name"]

static func color_of(t: int) -> Color:
	return DATA[t]["color"]
