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
			if _has_all_inputs(b, recipe) and _has_fluid_inputs(b, recipe, world) and _has_room_for_outputs(b, recipe):
				_consume_inputs(b, recipe)
				# Fluid is consumed conceptually but not buffered — connectivity-only model.
				b.state["progress"] = 1
				b.state["state"] = RUNNING
		RUNNING:
			var p: int = int(b.state["progress"]) + 1
			b.state["progress"] = p
			if p >= int(recipe["time_ticks"]):
				_emit_outputs(b, recipe)
				b.state["progress"] = 0
				# Decide next state based on whether outputs immediately cleared.
				b.state["state"] = IDLE if _has_room_for_outputs(b, recipe) else BLOCKED_OUTPUT
		BLOCKED_OUTPUT:
			# Re-check every tick. As soon as outputs clear, return to IDLE
			# so the next cycle can start.
			if _has_room_for_outputs(b, recipe):
				b.state["state"] = IDLE

	# 3. PUSH: try to ship one output item onto any adjacent belt.
	_try_push_outputs(b, world, recipe)

# ---------- helpers: inputs ----------

static func _try_pull_inputs(b: Building, world: Node2D, recipe: Dictionary) -> void:
	var capacity: int = int(recipe["input_capacity"])
	# Build accept list of input types we still want.
	var accept: Array = []
	for pair in recipe["inputs_solid"]:
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
	for pair in recipe["inputs_solid"]:
		var item_type: int = int(pair[0])
		var need: int = int(pair[1])
		if _buffer_count(b.state["in_buffer"], item_type) < need:
			return false
	return true

## Check that every fluid input the recipe needs is available adjacent
## to the building via the world's fluid network (pipe → pump). No buffer.
static func _has_fluid_inputs(b: Building, recipe: Dictionary, world: Node2D) -> bool:
	for pair in recipe.get("inputs_fluid", []):
		var fluid_type: int = int(pair[0])
		if not world.fluid_available_at(b.anchor, fluid_type):
			return false
	return true

static func _consume_inputs(b: Building, recipe: Dictionary) -> void:
	for pair in recipe["inputs_solid"]:
		_buffer_remove(b.state["in_buffer"], int(pair[0]), int(pair[1]))

# ---------- helpers: outputs ----------

static func _has_room_for_outputs(b: Building, recipe: Dictionary) -> bool:
	var capacity: int = int(recipe["output_capacity"])
	for pair in recipe["outputs_solid"]:
		var item_type: int = int(pair[0])
		var add: int = int(pair[1])
		if _buffer_count(b.state["out_buffer"], item_type) + add > capacity:
			return false
	return true

static func _emit_outputs(b: Building, recipe: Dictionary) -> void:
	for pair in recipe["outputs_solid"]:
		_buffer_add(b.state["out_buffer"], int(pair[0]), int(pair[1]))

## Push outputs to adjacent buildings.
##
## STRICT MODE (when output declares prefer_dir): only that direction is
## tried. If the neighbor at prefer_dir doesn't accept this tick, the item
## stays in the buffer until the port clears. This is the "dedicated
## output port" semantic — multi-output recipes (e.g. Thresher) declare
## "grain east, straw west" and items always go to their designated belt.
##
## DEFAULT (no prefer_dir, single-output recipes): try all 4 dirs.
## Chests preferred over belts (player intent: chest = sink).
##
## Outputs are processed in array order; first item that can push wins
## the tick. Two outputs preferring the same dir = first listed wins; the
## other waits.
static func _try_push_outputs(b: Building, world: Node2D, recipe: Dictionary) -> void:
	for pair in recipe["outputs_solid"]:
		var item_type: int = int(pair[0])
		if _buffer_count(b.state["out_buffer"], item_type) <= 0:
			continue
		# A 3rd element on the entry = preferred output direction (Belt.DIR_*).
		var prefer_dir: int = int(pair[2]) if pair.size() >= 3 else -1

		if prefer_dir >= 0:
			# Strict: try only the preferred direction.
			if _try_push_to_dir(b, world, item_type, prefer_dir):
				return
			# Push failed — item waits in buffer until preferred port clears.
		else:
			# No preference: try all 4 dirs, chests first then belts.
			for dir in 4:
				if _try_push_chest_to_dir(b, world, item_type, dir):
					return
			for dir in 4:
				if _try_push_belt_to_dir(b, world, item_type, dir):
					return

## Try to push one `item_type` to the building at `dir`. Accepts either
## a chest (direct insert) or a belt (try_insert). Returns true on success.
static func _try_push_to_dir(b: Building, world: Node2D, item_type: int, dir: int) -> bool:
	var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
	if not world.has_building_at(npos):
		return false
	var neighbor: Building = world.building_at(npos)
	if neighbor == null:
		return false
	var pushed: bool = false
	if neighbor.type == Buildings.Type.CHEST:
		pushed = Chest.try_insert(neighbor, item_type, 1)
	elif neighbor.type == Buildings.Type.BELT:
		pushed = Belt.try_insert(neighbor, item_type)
	if pushed:
		_buffer_remove(b.state["out_buffer"], item_type, 1)
	return pushed

static func _try_push_chest_to_dir(b: Building, world: Node2D, item_type: int, dir: int) -> bool:
	var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
	if not world.has_building_at(npos):
		return false
	var neighbor: Building = world.building_at(npos)
	if neighbor == null or neighbor.type != Buildings.Type.CHEST:
		return false
	if Chest.try_insert(neighbor, item_type, 1):
		_buffer_remove(b.state["out_buffer"], item_type, 1)
		return true
	return false

static func _try_push_belt_to_dir(b: Building, world: Node2D, item_type: int, dir: int) -> bool:
	var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
	if not world.has_building_at(npos):
		return false
	var neighbor: Building = world.building_at(npos)
	if neighbor == null or neighbor.type != Buildings.Type.BELT:
		return false
	if Belt.try_insert(neighbor, item_type):
		_buffer_remove(b.state["out_buffer"], item_type, 1)
		return true
	return false

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

## `world` is optional — pass it when fluid availability matters
## (Mixer & friends). Without world, fluid checks are skipped.
static func info_lines(b: Building, world = null) -> Array:
	var recipe: Dictionary = Recipes.get_recipe(b.state["recipe_id"])
	var s: int = int(b.state.get("state", IDLE))
	var lines: Array = [
		"Recipe: %s" % (recipe.get("display_name", b.state["recipe_id"]) if not recipe.is_empty() else "(none)"),
		"State: %s" % STATE_NAMES[s],
	]
	if not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		lines.append("Progress: %d / %d ticks" % [p, int(recipe["time_ticks"])])
		lines.append("In:  %s" % _fmt_buffer(b.state.get("in_buffer", [])))
		lines.append("Out: %s" % _fmt_buffer(b.state.get("out_buffer", [])))
		# Fluid requirement disclosed up-front (helps when network isn't built yet).
		var fluids: Array = recipe.get("inputs_fluid", [])
		if not fluids.is_empty():
			var parts: Array = []
			for pair in fluids:
				parts.append(Fluids.name_of(int(pair[0])))
			lines.append("Fluid in: %s (via adjacent pipe network)" % ", ".join(parts))
		# Output port assignments — visible so player knows where to place belts.
		var ports: Array = []
		for output_pair in recipe.get("outputs_solid", []):
			if output_pair.size() >= 3:
				var port_dir: int = int(output_pair[2])
				if port_dir >= 0:
					ports.append("%s → %s" % [Items.name_of(int(output_pair[0])), Belt.DIR_NAMES[port_dir]])
		if not ports.is_empty():
			lines.append("Output ports: %s" % ", ".join(ports))
		# Diagnostic: when stalled, name what's missing.
		if s == IDLE or s == BLOCKED_OUTPUT:
			var missing: Array = _missing_for_start(b, recipe, world)
			if not missing.is_empty():
				lines.append("Waiting for: %s" % ", ".join(missing))
	return lines

## Compute a human-readable list of what's blocking recipe-start. Solid
## inputs show "Item (have/need)"; fluid inputs show "Fluid (no network)";
## output backpressure names the specific output(s) that are full so the
## player can see at a glance which downstream sink to add.
static func _missing_for_start(b: Building, recipe: Dictionary, world) -> Array:
	var missing: Array = []
	for pair in recipe.get("inputs_solid", []):
		var item_type: int = int(pair[0])
		var need: int = int(pair[1])
		var have: int = _buffer_count(b.state.get("in_buffer", []), item_type)
		if have < need:
			missing.append("%s (%d/%d)" % [Items.name_of(item_type), have, need])
	if world != null:
		for pair in recipe.get("inputs_fluid", []):
			var fluid_type: int = int(pair[0])
			if not world.fluid_available_at(b.anchor, fluid_type):
				missing.append("%s (no pipe→pump)" % Fluids.name_of(fluid_type))
	# Per-output backpressure — name which output is jammed.
	var capacity: int = int(recipe.get("output_capacity", 0))
	for pair in recipe.get("outputs_solid", []):
		var item_type: int = int(pair[0])
		var add: int = int(pair[1])
		var have: int = _buffer_count(b.state.get("out_buffer", []), item_type)
		if have + add > capacity:
			missing.append("%s output full (%d/%d) — needs a sink" % [Items.name_of(item_type), have, capacity])
	return missing

static func _fmt_buffer(buf: Array) -> String:
	if buf.is_empty():
		return "(empty)"
	var parts: Array = []
	for entry in buf:
		parts.append("%s ×%d" % [Items.name_of(int(entry[0])), int(entry[1])])
	return ", ".join(parts)
