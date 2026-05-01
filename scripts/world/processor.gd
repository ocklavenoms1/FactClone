class_name Processor
extends RefCounted

## Generic recipe-driven machine logic.
##
## Any Building whose tick handler is `Processor.tick` runs a recipe from
## the Recipes registry. The Building's TYPE (Mill, Oven, Press, ...) decides
## the visual and terrain rules; the recipe_id in its state decides what it
## actually does. This is the "data-driven Path B" payoff:
##   - new processor machines = new Buildings.Type entry + new draw + new recipe
##   - same tick logic for all of them
##
## State schema (Building.state):
##   recipe_id: String       # which recipe is currently programmed
##   state: int              # IDLE | RUNNING | BLOCKED_OUTPUT  (see constants below)
##   progress: int           # 0..recipe.process_ticks
##   in_buffer:  Array       # [[item_type, count], ...] — small unordered bag
##   out_buffer: Array       # [[item_type, count], ...] — same shape
##
## All fields are JSON-clean (ints, strings, arrays of ints). Do NOT put an
## Inventory object in state — it'd silently degrade across save round-trip.

# State enum
const IDLE: int = 0
const RUNNING: int = 1
const BLOCKED_OUTPUT: int = 2  # Reserved for future use (currently we just stay IDLE)

const STATE_NAMES: Array = ["Idle", "Running", "Blocked: output full"]

## Construct the initial state dict for a freshly placed Processor.
## Call this from a building's make() function.
static func make_state(recipe_id: String) -> Dictionary:
	return {
		"recipe_id": recipe_id,
		"state": IDLE,
		"progress": 0,
		"in_buffer":  [],
		"out_buffer": [],
	}

# ---------- tick ----------

static func tick(b: Building, world: Node2D) -> void:
	var recipe: Dictionary = Recipes.get_recipe(b.state["recipe_id"])
	if recipe.is_empty():
		return

	# 1. PULL: try to bring in one needed input from any adjacent belt.
	_try_pull_inputs(b, world, recipe)

	# 2. STATE MACHINE
	var s: int = int(b.state["state"])
	match s:
		IDLE:
			if _has_all_inputs(b, recipe) and _has_room_for_outputs(b, recipe):
				_consume_inputs(b, recipe)
				b.state["progress"] = 1
				b.state["state"] = RUNNING
		RUNNING:
			var p: int = int(b.state["progress"]) + 1
			b.state["progress"] = p
			if p >= int(recipe["process_ticks"]):
				_emit_outputs(b, recipe)
				b.state["progress"] = 0
				b.state["state"] = IDLE
		BLOCKED_OUTPUT:
			# Currently unreachable — IDLE handles output-room check.
			b.state["state"] = IDLE

	# 3. PUSH: try to ship one output item onto any adjacent belt.
	_try_push_outputs(b, world, recipe)

# ---------- helpers: inputs ----------

static func _try_pull_inputs(b: Building, world: Node2D, recipe: Dictionary) -> void:
	var capacity: int = int(recipe["input_capacity"])
	# Build accept list of input types we still want.
	var accept: Array = []
	for pair in recipe["inputs"]:
		var item_type: int = int(pair[0])
		if _buffer_count(b.state["in_buffer"], item_type) < capacity:
			accept.append(item_type)
	if accept.is_empty():
		return
	for dir in 4:
		var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
		if not world.has_building_at(npos):
			continue
		var neighbor: Building = world.building_at(npos)
		if neighbor == null or neighbor.type != Buildings.Type.BELT:
			continue
		var pulled: int = Belt.try_pull_matching(neighbor, b.anchor, accept)
		if pulled >= 0:
			_buffer_add(b.state["in_buffer"], pulled, 1)
			return  # one pull per tick

static func _has_all_inputs(b: Building, recipe: Dictionary) -> bool:
	for pair in recipe["inputs"]:
		var item_type: int = int(pair[0])
		var need: int = int(pair[1])
		if _buffer_count(b.state["in_buffer"], item_type) < need:
			return false
	return true

static func _consume_inputs(b: Building, recipe: Dictionary) -> void:
	for pair in recipe["inputs"]:
		_buffer_remove(b.state["in_buffer"], int(pair[0]), int(pair[1]))

# ---------- helpers: outputs ----------

static func _has_room_for_outputs(b: Building, recipe: Dictionary) -> bool:
	var capacity: int = int(recipe["output_capacity"])
	for pair in recipe["outputs"]:
		var item_type: int = int(pair[0])
		var add: int = int(pair[1])
		if _buffer_count(b.state["out_buffer"], item_type) + add > capacity:
			return false
	return true

static func _emit_outputs(b: Building, recipe: Dictionary) -> void:
	for pair in recipe["outputs"]:
		_buffer_add(b.state["out_buffer"], int(pair[0]), int(pair[1]))

static func _try_push_outputs(b: Building, world: Node2D, recipe: Dictionary) -> void:
	for pair in recipe["outputs"]:
		var item_type: int = int(pair[0])
		if _buffer_count(b.state["out_buffer"], item_type) <= 0:
			continue
		for dir in 4:
			var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
			if not world.has_building_at(npos):
				continue
			var neighbor: Building = world.building_at(npos)
			if neighbor == null or neighbor.type != Buildings.Type.BELT:
				continue
			if Belt.try_insert(neighbor, item_type):
				_buffer_remove(b.state["out_buffer"], item_type, 1)
				return  # one push per tick

# ---------- buffer (Array of [type, count]) helpers ----------

static func _buffer_count(buf: Array, item_type: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _buffer_add(buf: Array, item_type: int, count: int) -> void:
	for entry in buf:
		if int(entry[0]) == item_type:
			entry[1] = int(entry[1]) + count
			return
	buf.append([item_type, count])

static func _buffer_remove(buf: Array, item_type: int, count: int) -> int:
	for i in buf.size():
		var entry = buf[i]
		if int(entry[0]) == item_type:
			var take: int = min(int(entry[1]), count)
			entry[1] = int(entry[1]) - take
			if int(entry[1]) <= 0:
				buf.remove_at(i)
			return take
	return 0

# ---------- info panel ----------

static func info_lines(b: Building) -> Array:
	var recipe: Dictionary = Recipes.get_recipe(b.state["recipe_id"])
	var s: int = int(b.state.get("state", IDLE))
	var lines: Array = [
		"Recipe: %s" % (recipe.get("display_name", b.state["recipe_id"]) if not recipe.is_empty() else "(none)"),
		"State: %s" % STATE_NAMES[s],
	]
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		lines.append("Progress: %d / %d ticks" % [p, int(recipe["process_ticks"])])
		lines.append("In:  %s" % _fmt_buffer(b.state.get("in_buffer", [])))
		lines.append("Out: %s" % _fmt_buffer(b.state.get("out_buffer", [])))
	return lines

static func _fmt_buffer(buf: Array) -> String:
	if buf.is_empty():
		return "(empty)"
	var parts: Array = []
	for entry in buf:
		parts.append("%s ×%d" % [Items.name_of(int(entry[0])), int(entry[1])])
	return ", ".join(parts)
