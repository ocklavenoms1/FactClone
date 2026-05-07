class_name Composter
extends RefCounted

## Composter — converts crops to compost (fertilizer) item.
## Multi-recipe processor (like Smelter): recipe selected at runtime by
## inspecting input buffer (FIFO — first-arrived crop wins) or peeking
## adjacent belts.
##
## Recipes (registered in recipes.gd):
##   wheat × 2      → COMPOST_LOW × 1   (5s)
##   flax  × 2      → COMPOST_LOW × 1   (5s)
##   sugar_beet × 2 → COMPOST_MID × 1   (7s)
##
## No fuel (biological process) — recipe runs purely on input availability.
## No prefer_dir on inputs/outputs — composter is 1×1 non-rotatable; any
## adjacent belt works for both pull and push.
##
## Architectural note: this is the second multi-recipe processor (after
## Smelter). Pattern: thin building-specific shim with `_maybe_select_recipe`
## + delegation to Processor.tick for the rest.
## Future multi-recipe processors (e.g. a Composter v2 with more crop tiers)
## should follow the same pattern. If the count grows past ~3, consider a
## generic `MultiRecipeProcessor.tick` that takes an `_input_to_recipe`
## map as a per-building static const.

# Item-type → recipe-id map for runtime recipe selection. Hardcoded for v1
# (only 3 recipes). If this grows past ~5 entries, derive from
# Recipes.for_building(COMPOSTER) instead.
const _INPUT_TO_RECIPE: Dictionary = {
	Items.Type.WHEAT:      "composter_low_wheat",
	Items.Type.FLAX:       "composter_low_flax",
	Items.Type.SUGAR_BEET: "composter_mid_beet",
}

# Visual constants — earthy compost-bin look.
const BODY_COLOR: Color = Color(0.40, 0.30, 0.18)        # warm dirt
const BODY_DARK: Color = Color(0.22, 0.16, 0.10)         # plank slats
const HEAP_COLOR: Color = Color(0.55, 0.42, 0.25)        # interior compost heap
const TRIM_COLOR: Color = Color(0.10, 0.07, 0.04)
const RUNNING_TINT: Color = Color(1.0, 0.85, 0.45)       # warm glow when active

## Initial state has recipe_id = "" — auto-selected on first tick by
## _maybe_select_recipe based on what the player is feeding in.
## Mirrors Smelter's "" default. Old saves predating Composter don't exist
## (this is the first session it ships in), so no backfill needed.
static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.COMPOSTER, pos, Processor.make_state(""))

static func tick(b: Building, world) -> void:
	# Pre-step: when IDLE (no recipe in flight), auto-select based on what's
	# in the buffer or coming down adjacent belts. Once RUNNING, recipe is
	# pinned for that batch — same contract as Smelter.
	if int(b.state.get("state", Processor.IDLE)) == Processor.IDLE:
		_maybe_select_recipe(b, world)
	Processor.tick(b, world)

## Pick recipe_id at IDLE based on what crop is available.
##
## Order of precedence (mirrors Smelter):
##   1. in_buffer first (FIFO — first-arrived item wins).
##   2. Port peek — scan ALL 4 adjacent belts (composter is non-rotatable
##      and has no prefer_dir, so any side counts).
##   3. Otherwise leave recipe_id unchanged (will be "" on a fresh composter).
static func _maybe_select_recipe(b: Building, world) -> void:
	# (1) in_buffer.
	for entry in b.state.get("in_buffer", []):
		var item_type: int = int(entry[0])
		if int(entry[1]) > 0 and _INPUT_TO_RECIPE.has(item_type):
			b.state["recipe_id"] = _INPUT_TO_RECIPE[item_type]
			return
	# (2) port peek — all 4 sides.
	for d in [Belt.DIR_E, Belt.DIR_S, Belt.DIR_W, Belt.DIR_N]:
		for cell in Buildings.edge_cells(Buildings.Type.COMPOSTER, b.anchor, d):
			var src: Building = world.building_at(cell)
			if src == null or src.type != Buildings.Type.BELT:
				continue
			for slot_t in src.state.get("slots", []):
				var t: int = int(slot_t)
				if t >= 0 and _INPUT_TO_RECIPE.has(t):
					b.state["recipe_id"] = _INPUT_TO_RECIPE[t]
					return
	# (3) leave recipe_id as-is (likely "" → Processor.tick early-returns).

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# Wooden compost bin: dark plank frame around a warm dirt interior with
	# a heap mound suggesting the active pile. Glows warmer when running.
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BODY_DARK, true)
	canvas.draw_rect(rect.grow(-3), BODY_COLOR, true)
	canvas.draw_rect(rect, TRIM_COLOR, false, 2.0)

	# Heap mound — central blob whose color brightens when running, like the
	# Mill's millstone progress hint.
	var is_running: bool = int(b.state.get("state", Processor.IDLE)) == Processor.RUNNING
	var heap_color: Color = HEAP_COLOR if not is_running else HEAP_COLOR * RUNNING_TINT
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.55)
	var heap_radius: float = float(tile_size) * 0.28
	canvas.draw_circle(center, heap_radius, heap_color)
	canvas.draw_arc(center, heap_radius, 0.0, TAU, 24, TRIM_COLOR, 1.0)

	# Plank slats — three short vertical lines on the front face for visual
	# texture. Cheap detail, makes the building distinguishable at a glance.
	for i in 3:
		var x: float = world_pos.x + 6.0 + float(i) * (float(tile_size) - 12.0) / 2.0
		canvas.draw_line(Vector2(x, world_pos.y + 4), Vector2(x, world_pos.y + tile_size - 4), BODY_DARK, 1.0)

	# Progress arc when running — same idiom as Mill / Smelter.
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	if is_running and not recipe.is_empty():
		var progress: int = int(b.state.get("progress", 0))
		var time_ticks: int = int(recipe["time_ticks"])
		if time_ticks > 0:
			var pct: float = float(progress) / float(time_ticks)
			canvas.draw_arc(center, heap_radius + 3.0, -PI * 0.5, -PI * 0.5 + TAU * pct, 24, Color(0.4, 0.95, 0.4, 0.9), 2.0)
