class_name Recipes
extends RefCounted

## Recipe registry — all crafting recipes in the game.
##
## Recipe IDs are STRINGS (not enum ints) because they're stored in
## building state and need to survive enum reordering and save round-trips.
##
## Recipe shape:
##   id: String
##   building_type: int          (Buildings.Type — validation only, not serialized)
##   inputs_solid:  Array[[item_type, count]]
##   inputs_fluid:  Array[[fluid_type, count]]   (count is reserved for future flow sim;
##                                                connectivity-only model treats it as "yes/no")
##   outputs_solid: Array[[item_type, count]]   (multiple entries = multi-output recipe)
##   time_ticks: int
##   input_capacity / output_capacity: max items the Processor will buffer (per item type)
##   display_name: String

const DATA: Dictionary = {
	# --- bread chain ---
	"thresher_wheat": {
		"id": "thresher_wheat",
		"building_type": Buildings.Type.THRESHER,
		"inputs_solid":  [[Items.Type.WHEAT, 1]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.GRAIN, 1], [Items.Type.STRAW, 1]],   # multi-output
		"time_ticks": 60,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Wheat → Grain + Straw",
	},
	"mill_grain_to_flour": {
		"id": "mill_grain_to_flour",
		"building_type": Buildings.Type.MILL,
		"inputs_solid":  [[Items.Type.GRAIN, 1]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.FLOUR, 1]],
		"time_ticks": 80,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Grain → Flour",
	},
	"mixer_dough": {
		"id": "mixer_dough",
		"building_type": Buildings.Type.MIXER,
		"inputs_solid":  [[Items.Type.FLOUR, 2], [Items.Type.YEAST, 1]],
		"inputs_fluid":  [[Fluids.Type.WATER, 1]],
		"outputs_solid": [[Items.Type.DOUGH, 1]],
		"time_ticks": 100,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Flour + Yeast + Water → Dough",
	},
	"proofer_rise": {
		"id": "proofer_rise",
		"building_type": Buildings.Type.PROOFER,
		"inputs_solid":  [[Items.Type.DOUGH, 1]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.RISEN_DOUGH, 1]],
		"time_ticks": 400,    # 20s — slow rise
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Dough → Risen Dough",
	},
	"oven_bread": {
		"id": "oven_bread",
		"building_type": Buildings.Type.OVEN,
		"inputs_solid":  [[Items.Type.RISEN_DOUGH, 1], [Items.Type.FUEL_BRIQUETTE, 1]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.BREAD, 1]],
		"time_ticks": 120,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Risen Dough + Fuel → Bread",
	},
	"packager_loaves": {
		"id": "packager_loaves",
		"building_type": Buildings.Type.PACKAGER,
		"inputs_solid":  [[Items.Type.BREAD, 4]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.LOAF_PACK, 1]],
		"time_ticks": 80,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "4× Bread → Loaf Pack",
	},
	"briquetter_fuel": {
		"id": "briquetter_fuel",
		"building_type": Buildings.Type.BRIQUETTER,
		"inputs_solid":  [[Items.Type.STRAW, 3]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.FUEL_BRIQUETTE, 1]],
		"time_ticks": 100,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "3× Straw → Fuel Briquette",
	},
	"yeast_culture": {
		"id": "yeast_culture",
		"building_type": Buildings.Type.YEAST_CULTURE,
		"inputs_solid":  [[Items.Type.SUGAR, 1]],
		"inputs_fluid":  [[Fluids.Type.WATER, 1]],
		"outputs_solid": [[Items.Type.YEAST, 2]],
		"time_ticks": 200,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Sugar + Water → 2× Yeast",
	},
	"press_sugar": {
		"id": "press_sugar",
		"building_type": Buildings.Type.SUGAR_PRESS,
		"inputs_solid":  [[Items.Type.SUGAR_BEET, 1]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.SUGAR, 1]],
		"time_ticks": 100,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Sugar Beet → Sugar",
	},
}

## Look up a recipe by id. Returns {} (empty dict) if not found.
##
## Logs a warning ONCE per unknown id (cached) — avoids per-tick spam if
## a save references a recipe ID that's been renamed/removed.
static var _warned_unknown: Dictionary = {}

static func get_recipe(id: String) -> Dictionary:
	if not DATA.has(id):
		if not _warned_unknown.has(id):
			push_warning("Recipes.get_recipe: unknown recipe id '%s' (warning shown once)" % id)
			_warned_unknown[id] = true
		return {}
	return DATA[id]

static func has_recipe(id: String) -> bool:
	return DATA.has(id)

## All recipes runnable by the given building type.
static func for_building(building_type: int) -> Array:
	var out: Array = []
	for id in DATA:
		if int(DATA[id]["building_type"]) == building_type:
			out.append(DATA[id])
	return out

## Default recipe id for a building type, or "" if none registered yet.
static func default_for(building_type: int) -> String:
	var matches: Array = for_building(building_type)
	return matches[0]["id"] if not matches.is_empty() else ""
