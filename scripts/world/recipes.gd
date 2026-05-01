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
##   outputs_solid: Array[[item_type, count]]
##   time_ticks: int
##   input_capacity / output_capacity: max items the Processor will buffer (per item type)
##   display_name: String

const DATA: Dictionary = {
	"mill_wheat_to_flour": {
		"id": "mill_wheat_to_flour",
		"building_type": Buildings.Type.MILL,
		"inputs_solid":  [[Items.Type.WHEAT, 1]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.FLOUR, 1]],
		"time_ticks": 80,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Wheat → Flour",
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
}

## Look up a recipe by id. Returns {} (empty dict) if not found.
## Named `get_recipe` (not `get`) to avoid clashing with Object.get.
static func get_recipe(id: String) -> Dictionary:
	if not DATA.has(id):
		push_error("Recipes.get_recipe: unknown recipe id '%s'" % id)
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
