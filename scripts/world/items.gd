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
	# --- soil exhaustion Session 4 (wasteland). HIGH tier activated:
	# food-waste in (bread / loaf_pack) → restoration fuel out. Restores
	# scarred wasteland tiles + provides 8× regen for 120s.
	COMPOST_HIGH,
}

const DATA: Dictionary = {
	Type.WHEAT:          { "name": "Wheat",          "color": Color(0.95, 0.80, 0.25), "max_stack": 100, "description": "Raw grain crop. Thresh into Grain + Straw, or compost 2 in a Composter for Low Compost." },
	Type.FLOUR:          { "name": "Flour",          "color": Color(0.95, 0.92, 0.85), "max_stack": 100, "description": "Milled grain. Mix 2 Flour with Yeast and Water in a Mixer to produce Dough." },
	Type.YEAST:          { "name": "Yeast",          "color": Color(0.85, 0.75, 0.55), "max_stack":  50, "description": "Live culture grown in a Yeast Culture from Sugar + Water. One yeast per Mixer batch." },
	Type.DOUGH:          { "name": "Dough",          "color": Color(0.92, 0.86, 0.70), "max_stack":  50, "description": "Unleavened mix from the Mixer. Proof slowly in a Proofer (20s) to make Risen Dough." },
	Type.SUGAR_BEET:     { "name": "Sugar Beet",     "color": Color(0.65, 0.20, 0.30), "max_stack": 100, "description": "Root crop. Press in a Sugar Press to make Sugar, or compost 2 for Rich Compost." },
	Type.SUGAR:          { "name": "Sugar",          "color": Color(0.98, 0.96, 0.94), "max_stack": 100, "description": "Pressed from Sugar Beet. Feeds the Yeast Culture (Sugar + Water yields 2 Yeast)." },
	Type.GRAIN:          { "name": "Grain",          "color": Color(0.88, 0.72, 0.32), "max_stack": 100, "description": "Thresher east-port output. Mill in a Mill to produce Flour for the bread chain." },
	Type.STRAW:          { "name": "Straw",          "color": Color(0.85, 0.78, 0.40), "max_stack": 100, "description": "Thresher west-port byproduct. Compress 3 in a Briquetter to make one Fuel Briquette." },
	Type.RISEN_DOUGH:    { "name": "Risen Dough",    "color": Color(0.95, 0.88, 0.74), "max_stack":  50, "description": "Proofed dough. Bake in an Oven with a Fuel Briquette (S edge) to make Bread." },
	Type.BREAD:          { "name": "Bread",          "color": Color(0.78, 0.55, 0.30), "max_stack":  50, "description": "Baked food. Pack 4 in a Packager for a Loaf Pack, or compost 2 for Premium Compost." },
	Type.LOAF_PACK:      { "name": "Loaf Pack",      "color": Color(0.55, 0.40, 0.25), "max_stack":  50, "description": "Bundled food (4 Bread). Composts to Premium Compost (1 input) — best wasteland-recovery deal." },
	Type.FUEL_BRIQUETTE: { "name": "Fuel Briquette", "color": Color(0.30, 0.22, 0.18), "max_stack": 100, "description": "Compressed straw fuel. 8 energy units per item — the densest fuel, made in a Briquetter." },
	Type.FLAX:           { "name": "Flax",           "color": Color(0.55, 0.72, 0.78), "max_stack": 100, "description": "Fiber crop. Ret in a Retter with Water to produce Fiber, or compost 2 for Low Compost." },
	Type.FIBER:          { "name": "Fiber",          "color": Color(0.86, 0.84, 0.76), "max_stack": 100, "description": "Retted flax. Weave 3 Fiber in a Loom to produce one bolt of Cloth." },
	Type.CLOTH:          { "name": "Cloth",          "color": Color(0.92, 0.80, 0.62), "max_stack": 100, "description": "Woven cloth from the Loom. Sew 4 Cloth in a Tailor to produce one Bag." },
	Type.BAG:            { "name": "Bag",            "color": Color(0.55, 0.30, 0.18), "max_stack": 100, "description": "Inventory upgrade. Press B to consume one and gain +4 slots (lifetime cap: 5 bags consumed)." },
	# --- mining (colors match ResourceNodes.color_of for visual continuity) ---
	Type.RAW_STONE:      { "name": "Raw Stone",      "color": Color(0.55, 0.55, 0.58), "max_stack": 200, "description": "Mined from stone deposits with a Mining Drill. Reserved for the future stone-crafting chain." },
	Type.COAL:           { "name": "Coal",           "color": Color(0.18, 0.18, 0.22), "max_stack": 200, "description": "Mined fuel worth 4 energy units per item (4× Wood). Feeds drills, smelters, and inserters." },
	Type.IRON_ORE:       { "name": "Iron Ore",       "color": Color(0.62, 0.45, 0.38), "max_stack": 100, "description": "Mined ore. Feed into a Smelter (W edge) with fuel (S edge) to produce Iron Ingot." },
	Type.COPPER_ORE:     { "name": "Copper Ore",     "color": Color(0.45, 0.55, 0.65), "max_stack": 100, "description": "Mined ore. Feed into a Smelter (W edge) with fuel (S edge) to produce Copper Ingot." },
	Type.CLAY:           { "name": "Clay",           "color": Color(0.68, 0.50, 0.36), "max_stack": 200, "description": "Mined from clay deposits with a Mining Drill. Reserved for the future brick-crafting chain." },
	# --- tree harvesting (color matches tree trunk, not canopy — the produced item is wood) ---
	Type.WOOD:           { "name": "Wood",           "color": Color(0.50, 0.32, 0.18), "max_stack": 200, "description": "Harvested from felled trees. Basic fuel worth 1 energy unit per item — cheapest burner feed." },
	# --- smelted ingots (refined materials; cooler/warmer than their ore counterparts
	# to visually signal "post-furnace transformation"). Stack 100 matches refined
	# materials (CLOTH, BREAD, FUEL_BRIQUETTE), not bulk raw (RAW_STONE/CLAY 200).
	Type.IRON_INGOT:     { "name": "Iron Ingot",     "color": Color(0.55, 0.55, 0.62), "max_stack": 100, "description": "Smelted from Iron Ore in a Smelter. Reserved for future tool and electric-tier chains." },
	Type.COPPER_INGOT:   { "name": "Copper Ingot",   "color": Color(0.78, 0.55, 0.40), "max_stack": 100, "description": "Smelted from Copper Ore in a Smelter. Reserved for the future electric-tier chain." },
	# --- composted fertilizer (session-soil-exhaustion-3) ---
	# Brown gradient: LOW = lighter (less concentrated), MID = darker (richer).
	# Stack 100 matches refined materials (FLOUR, CLOTH, FUEL_BRIQUETTE).
	Type.COMPOST_LOW:    { "name": "Low Compost",    "color": Color(0.55, 0.40, 0.25), "max_stack": 100, "description": "Tier-1 fertilizer from 2× Wheat or Flax. Apply via Fertilizer Applicator: +2 regen for 30s." },
	Type.COMPOST_MID:    { "name": "Rich Compost",   "color": Color(0.38, 0.27, 0.16), "max_stack": 100, "description": "Tier-2 fertilizer from 2× Sugar Beet. Apply via Fertilizer Applicator: +4 regen for 60s." },
	# Premium Compost (Session 4): near-black brown — top of the gradient.
	# Made from food waste (bread / loaf_pack); restores wasteland.
	Type.COMPOST_HIGH:   { "name": "Premium Compost", "color": Color(0.22, 0.16, 0.10), "max_stack": 100, "description": "Tier-3 fertilizer from 2× Bread or 1× Loaf Pack. Restores wasteland tiles: +8 regen for 120s." },
}

static func name_of(t: int) -> String:
	return DATA[t]["name"]

## Description text for tooltips. Returns empty string for unknown types
## (safe fallback so callers don't need to null-check).
##
## Authored at QoL Cluster B Item 1: text in Items.DATA "description" field
## is reviewed by user before tooltip widget integration (Task 3 gate).
static func description_of(t: int) -> String:
	if not DATA.has(t):
		return ""
	return str(DATA[t].get("description", ""))

static func color_of(t: int) -> Color:
	return DATA[t]["color"]

static func max_stack_of(t: int) -> int:
	return DATA[t]["max_stack"]
