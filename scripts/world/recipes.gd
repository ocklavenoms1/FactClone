class_name Recipes
extends RefCounted

## Recipe registry — all crafting recipes in the game.
##
## Recipe IDs are STRINGS (not enum ints) because:
##   - they're stored in building state and survive enum reordering
##   - they're self-documenting in saves
##   - they're stable for save compatibility across sessions
##
## Each recipe declares:
##   - building_type: which Buildings.Type can run it (validation only, not serialized)
##   - inputs:        Array of [item_type:int, count:int]
##   - outputs:       Array of [item_type:int, count:int]
##   - process_ticks: how many ticks one cycle takes (20Hz, so 80 = 4s)
##   - input_capacity / output_capacity: max items the Processor will buffer
##
## Adding a recipe = add an entry here. No code changes elsewhere.

const DATA: Dictionary = {
	"mill_wheat_to_flour": {
		"id": "mill_wheat_to_flour",
		"building_type": Buildings.Type.MILL,
		"inputs":  [[Items.Type.WHEAT, 1]],
		"outputs": [[Items.Type.FLOUR, 1]],
		"process_ticks": 80,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Wheat → Flour",
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
