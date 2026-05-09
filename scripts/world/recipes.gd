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
		# Multi-output with dedicated output ports: grain → east, straw → west.
		# Player must place a belt (or chest) at each port; otherwise that
		# output stays buffered until the port is built.
		"outputs_solid": [
			[Items.Type.GRAIN, 1, Belt.DIR_E],
			[Items.Type.STRAW, 1, Belt.DIR_W],
		],
		"time_ticks": 60,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Wheat → Grain (E) + Straw (W)",
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
		# 2×2 footprint: flour pulls from W edge, yeast from N edge.
		# Water comes from any adjacent pipe (any of the 8 perimeter cells).
		"inputs_solid":  [[Items.Type.FLOUR, 2, Belt.DIR_W], [Items.Type.YEAST, 1, Belt.DIR_N]],
		"inputs_fluid":  [[Fluids.Type.WATER, 1]],
		"outputs_solid": [[Items.Type.DOUGH, 1, Belt.DIR_E]],
		"time_ticks": 100,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Flour (W) + Yeast (N) + Water → Dough (E)",
	},
	"proofer_rise": {
		"id": "proofer_rise",
		"building_type": Buildings.Type.PROOFER,
		# 2×2: dough in from W, risen dough out to E (canonical orientation;
		# rotates with building.dir).
		"inputs_solid":  [[Items.Type.DOUGH, 1, Belt.DIR_W]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.RISEN_DOUGH, 1, Belt.DIR_E]],
		"time_ticks": 400,    # 20s — slow rise
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Dough (W) → Risen Dough (E)",
	},
	"oven_bread": {
		"id": "oven_bread",
		"building_type": Buildings.Type.OVEN,
		# 2×2: risen dough in from W (main feed), fuel briquette in from S
		# (fuel branch can split off perpendicular to the main bread line).
		# Bread out to E.
		"inputs_solid":  [[Items.Type.RISEN_DOUGH, 1, Belt.DIR_W], [Items.Type.FUEL_BRIQUETTE, 1, Belt.DIR_S]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.BREAD, 1, Belt.DIR_E]],
		"time_ticks": 120,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Risen Dough (W) + Fuel (S) → Bread (E)",
	},
	"packager_loaves": {
		"id": "packager_loaves",
		"building_type": Buildings.Type.PACKAGER,
		# 2×2: bread in from W, loaf pack out to E.
		"inputs_solid":  [[Items.Type.BREAD, 4, Belt.DIR_W]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.LOAF_PACK, 1, Belt.DIR_E]],
		"time_ticks": 80,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "4× Bread (W) → Loaf Pack (E)",
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
	# --- cloth chain (Session E groundwork; buildings ship with the
	# Session E proper commit. Recipes are inert until then because no
	# Building of these types can be placed yet — DATA entries don't exist).
	"retter_fiber": {
		"id": "retter_fiber",
		"building_type": Buildings.Type.RETTER,
		# Canonical (east-facing) ports: flax in from W, fiber out to E.
		# Water has no prefer_dir — accepts a pump/pipe network adjacent to
		# any of the 4 perimeter cells, regardless of building.dir.
		"inputs_solid":  [[Items.Type.FLAX, 1, Belt.DIR_W]],
		"inputs_fluid":  [[Fluids.Type.WATER, 1]],
		"outputs_solid": [[Items.Type.FIBER, 1, Belt.DIR_E]],
		"time_ticks": 160,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Flax (W) + Water → Fiber (E)",
	},
	"loom_cloth": {
		"id": "loom_cloth",
		"building_type": Buildings.Type.LOOM,
		# Canonical (east-facing) ports: fiber in from W, cloth out to E.
		"inputs_solid":  [[Items.Type.FIBER, 3, Belt.DIR_W]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.CLOTH, 1, Belt.DIR_E]],
		"time_ticks": 120,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "3× Fiber (W) → Cloth (E)",
	},
	"tailor_bag": {
		"id": "tailor_bag",
		"building_type": Buildings.Type.TAILOR,
		# Canonical (east-facing) ports: cloth in from W, bag out to E.
		"inputs_solid":  [[Items.Type.CLOTH, 4, Belt.DIR_W]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.BAG, 1, Belt.DIR_E]],
		"time_ticks": 160,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "4× Cloth (W) → Bag (E)",
	},
	# --- smelting chain (session-smelter) ---
	# Smelter is the first MULTI-RECIPE building: which recipe is active is
	# decided at runtime by smelter.gd's _maybe_select_recipe based on what
	# ore arrives. Both recipes share port layout (W in, E out) and timing
	# (40 ticks = 2s = 0.5 ingot/sec, matching the drill's 0.5 ore/sec rate
	# for 1:1 drill→smelter pairing). Fuel goes in via S edge (handled by
	# Burner module — NOT a recipe field; see smelter.gd FUEL_PORT_DIR).
	"smelt_iron": {
		"id": "smelt_iron",
		"building_type": Buildings.Type.SMELTER,
		"inputs_solid":  [[Items.Type.IRON_ORE, 1, Belt.DIR_W]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.IRON_INGOT, 1, Belt.DIR_E]],
		"time_ticks": 40,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Iron Ore (W) → Iron Ingot (E)",
	},
	"smelt_copper": {
		"id": "smelt_copper",
		"building_type": Buildings.Type.SMELTER,
		"inputs_solid":  [[Items.Type.COPPER_ORE, 1, Belt.DIR_W]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.COPPER_INGOT, 1, Belt.DIR_E]],
		"time_ticks": 40,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Copper Ore (W) → Copper Ingot (E)",
	},
	# --- composting (session-soil-exhaustion-3) ---
	# Multi-recipe building (like Smelter): Composter selects a recipe at
	# runtime based on what input arrives. No prefer_dir on inputs/outputs
	# (Composter is 1×1 non-rotatable; Processor falls back to any-side
	# accept). No fuel; biological process.
	#
	# Heaviest soil-cost crop (sugar beet) → richest compost — thematic
	# closure of the soil cycle: what depleted the soil heals it most.
	# Composter outputs declare prefer_dir = canonical E so the rotated
	# east edge is the only push target. Without prefer_dir, a jammed
	# downstream belt would cause Processor._try_push_outputs to fall
	# through to other directions — including pushing compost BACKWARD
	# onto the input belt, mixing wheat with compost. Recipe inputs stay
	# direction-free so feeders can arrive from any side.
	"composter_low_wheat": {
		"id": "composter_low_wheat",
		"building_type": Buildings.Type.COMPOSTER,
		"inputs_solid":  [[Items.Type.WHEAT, 2]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.COMPOST_LOW, 1, Belt.DIR_E]],
		"time_ticks": 100,        # 5s @ 20 tps
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "2× Wheat → Low Compost (E)",
	},
	"composter_low_flax": {
		"id": "composter_low_flax",
		"building_type": Buildings.Type.COMPOSTER,
		"inputs_solid":  [[Items.Type.FLAX, 2]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.COMPOST_LOW, 1, Belt.DIR_E]],
		"time_ticks": 100,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "2× Flax → Low Compost (E)",
	},
	"composter_mid_beet": {
		"id": "composter_mid_beet",
		"building_type": Buildings.Type.COMPOSTER,
		"inputs_solid":  [[Items.Type.SUGAR_BEET, 2]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.COMPOST_MID, 1, Belt.DIR_E]],
		"time_ticks": 140,        # 7s — premium tier slower
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "2× Sugar Beet → Rich Compost (E)",
	},
	# Wasteland recovery tier (session-soil-exhaustion-4). Food-waste
	# inputs make thematic sense — finished food → top-quality compost.
	# Both recipes 200 ticks (10s — slowest tier; matches "premium"
	# framing). Loaf pack is the better deal (1 input vs 2, but 1 loaf
	# pack costs 4 bread upstream); design pressure to build the full
	# Packager chain for sustainable wasteland recovery.
	"composter_high_bread": {
		"id": "composter_high_bread",
		"building_type": Buildings.Type.COMPOSTER,
		"inputs_solid":  [[Items.Type.BREAD, 2]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.COMPOST_HIGH, 1, Belt.DIR_E]],
		"time_ticks": 200,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "2× Bread → Premium Compost (E)",
	},
	"composter_high_loafpack": {
		"id": "composter_high_loafpack",
		"building_type": Buildings.Type.COMPOSTER,
		"inputs_solid":  [[Items.Type.LOAF_PACK, 1]],
		"inputs_fluid":  [],
		"outputs_solid": [[Items.Type.COMPOST_HIGH, 1, Belt.DIR_E]],
		"time_ticks": 200,
		"input_capacity":  8,
		"output_capacity": 8,
		"display_name": "Loaf Pack → Premium Compost (E)",
	},
}

## Look up a recipe by id. Returns {} (empty dict) if not found.
##
## Logs a warning ONCE per unknown id (cached) — avoids per-tick spam if
## a save references a recipe ID that's been renamed/removed.
static var _warned_unknown: Dictionary = {}

static func get_recipe(id: String) -> Dictionary:
	# Empty-string is the smelter's "no recipe selected yet" sentinel —
	# silent miss, not a typo. Buildings call this each tick during
	# IDLE-with-empty-buffer, and we don't want to spam the log.
	if id == "":
		return {}
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
