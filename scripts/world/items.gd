class_name Items
extends RefCounted

## Item type registry. Items are the things that flow through the game:
## crops, processed goods, eventually fluids and intermediates.
##
## Add a new item: APPEND to Type enum (never reorder — type ints are
## stored in saves). Add a DATA entry.
##
## NAMING CONVENTION (locked in mining-manual session):
##   RAW_*   — extracted form before processing (collision-dodge OR
##              substantial transformation expected). E.g., RAW_STONE
##              avoids collision with Terrain.Overlay.STONE; future
##              "stone crusher" would output STONE_BLOCK as the placeable
##              item that replaces today's free-stone painting.
##   *_ORE   — extracted form of metal that will be smelted to *_INGOT.
##              IRON_ORE → IRON_INGOT (future) → tools / electric tier.
##   bare    — extracted form usable as-is in chains. COAL goes straight
##              to fuel; CLAY goes straight to brick recipes.

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
	FLAX,
	FIBER,
	CLOTH,
	BAG,
	# --- mining (manual tier, session-mining-manual) ---
	RAW_STONE,
	COAL,
	IRON_ORE,
	COPPER_ORE,
	CLAY,
	# --- tree harvesting (session-tree-harvest) ---
	WOOD,
	# --- smelting (session-smelter) ---
	IRON_INGOT,
	COPPER_INGOT,
	# --- soil exhaustion arc (session-soil-exhaustion-3): fertilizer chain.
	# Two tiers this session; HIGH tier deferred to Session 4 (wasteland)
	# when bread-as-waste recovery makes thematic sense. Enum is append-
	# only so a future HIGH slot doesn't break v17 saves.
	COMPOST_LOW,
	COMPOST_MID,
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
	Type.FLAX:           { "name": "Flax",           "color": Color(0.55, 0.72, 0.78), "max_stack": 100 },
	Type.FIBER:          { "name": "Fiber",          "color": Color(0.86, 0.84, 0.76), "max_stack": 100 },
	Type.CLOTH:          { "name": "Cloth",          "color": Color(0.92, 0.80, 0.62), "max_stack": 100 },
	Type.BAG:            { "name": "Bag",            "color": Color(0.55, 0.30, 0.18), "max_stack": 100 },
	# --- mining (colors match ResourceNodes.color_of for visual continuity) ---
	Type.RAW_STONE:      { "name": "Raw Stone",      "color": Color(0.55, 0.55, 0.58), "max_stack": 200 },
	Type.COAL:           { "name": "Coal",           "color": Color(0.18, 0.18, 0.22), "max_stack": 200 },
	Type.IRON_ORE:       { "name": "Iron Ore",       "color": Color(0.62, 0.45, 0.38), "max_stack": 100 },
	Type.COPPER_ORE:     { "name": "Copper Ore",     "color": Color(0.45, 0.55, 0.65), "max_stack": 100 },
	Type.CLAY:           { "name": "Clay",           "color": Color(0.68, 0.50, 0.36), "max_stack": 200 },
	# --- tree harvesting (color matches tree trunk, not canopy — the produced item is wood) ---
	Type.WOOD:           { "name": "Wood",           "color": Color(0.50, 0.32, 0.18), "max_stack": 200 },
	# --- smelted ingots (refined materials; cooler/warmer than their ore counterparts
	# to visually signal "post-furnace transformation"). Stack 100 matches refined
	# materials (CLOTH, BREAD, FUEL_BRIQUETTE), not bulk raw (RAW_STONE/CLAY 200).
	Type.IRON_INGOT:     { "name": "Iron Ingot",     "color": Color(0.55, 0.55, 0.62), "max_stack": 100 },
	Type.COPPER_INGOT:   { "name": "Copper Ingot",   "color": Color(0.78, 0.55, 0.40), "max_stack": 100 },
	# --- composted fertilizer (session-soil-exhaustion-3) ---
	# Brown gradient: LOW = lighter (less concentrated), MID = darker (richer).
	# Stack 100 matches refined materials (FLOUR, CLOTH, FUEL_BRIQUETTE).
	Type.COMPOST_LOW:    { "name": "Low Compost",    "color": Color(0.55, 0.40, 0.25), "max_stack": 100 },
	Type.COMPOST_MID:    { "name": "Rich Compost",   "color": Color(0.38, 0.27, 0.16), "max_stack": 100 },
}

static func name_of(t: int) -> String:
	return DATA[t]["name"]

static func color_of(t: int) -> Color:
	return DATA[t]["color"]

static func max_stack_of(t: int) -> int:
	return DATA[t]["max_stack"]
