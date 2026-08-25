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
##
## `dir` is the building's orientation (Belt.DIR_E etc). Defaults to 0
## (canonical) for buildings whose recipes don't declare prefer_dir ports;
## rotatable processors thread their construction-time direction in here so
## Buildings.world_dir() can rotate recipe ports at tick time.
static func make_state(recipe_id: String, dir: int = 0) -> Dictionary:
	return {
		"recipe_id": recipe_id,
		"state": IDLE,
		"progress": 0,
		"in_buffer":  [],
		"out_buffer": [],
		"dir": dir,
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

# ---------- the recipe-pin rule (shared by Smelter and Composter) ----------
#
# Both multi-recipe machines pin `recipe_id` and re-run selection only while
# IDLE. Audit findings #15 and #18 are the same defect in the two files: the
# pin had no release path, so a bad pin was permanent. Two ways it goes bad,
# one measured per file — see scripts/tests/test_recipe_pin_release.gd.
#
# THE RULE: a recipe_id may stay pinned only while it is RESOLVABLE and
# STARTABLE. These two helpers are the single source of it; Smelter and
# Composter both call both, so the files cannot drift apart again.

## True when `recipe` could begin RIGHT NOW from what is already in in_buffer.
##
## Selection uses this so it does not pin a recipe the buffer cannot satisfy.
## The composter is where this bites: every composter recipe but the loaf-pack
## one needs TWO of its input, so a lone crop maps to a recipe that can never
## start, and because `_try_pull_inputs` filters belt pulls by the PINNED
## recipe, nothing else is ever pulled or even seen. All smelter recipes
## currently need 1, which makes this a no-op there TODAY — not "optional
## future-proofing". The first smelter recipe that needs two of an ore (steel,
## an alloy) wedges exactly like the composter, and the rule is cheaper to
## keep uniform than to re-derive.
static func can_start_from_buffer(b: Building, recipe: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	return _has_all_inputs(b, recipe)

## Release a pinned recipe_id the registry can no longer resolve, returning
## the machine to IDLE so selection can run again. Returns true if it fired.
##
## `Recipes.get_recipe` returns {} for an unknown id and its own comment names
## the cause: "if a save references a recipe ID that's been renamed/removed".
## SaveSystem restores building state verbatim and never validates recipe_id,
## so a machine saved mid-batch whose recipe is later renamed reloads NON-IDLE
## with an unresolvable pin. Both tick functions then bail at
## `if recipe.is_empty(): return` BEFORE their state machine, while selection
## is gated on IDLE — no path back, and one push_warning per id, ever.
##
## recipe_id "" is NOT a dead pin: it is the documented "nothing selected yet"
## sentinel a fresh Smelter/Composter is built with. Left alone deliberately.
##
## Any inputs already consumed into the in-flight batch are gone — the recipe
## that said what to emit is gone with them. in_buffer is left untouched so
## everything not yet consumed survives the release.
static func release_unresolvable_recipe(b: Building) -> bool:
	var id: String = str(b.state.get("recipe_id", ""))
	if id == "":
		return false
	if not Recipes.get_recipe(id).is_empty():
		return false
	b.state["recipe_id"] = ""
	# Processor.IDLE and Smelter.STATE_IDLE are separate enums that both == 0;
	# this line is correct for either caller because of that coincidence.
	b.state["state"] = IDLE
	b.state["progress"] = 0
	return true

# ---------- helpers: inputs ----------

## Pull inputs from adjacent belts. Multi-tile aware: scans every cell
## along the relevant edge of the building's footprint.
##
## STRICT MODE (when input declares prefer_dir): scan only the rotated
## world-edge for that specific item. The recipe's prefer_dir is canonical
## (declared as if the building faced east); Buildings.world_dir() rotates
## it by the building's current orientation so a rotated processor pulls
## from the rotated edge, not the world-absolute one.
##
## DEFAULT (no prefer_dir): scan all 4 edges, all cells, accepting any
## of the recipe's input items.
static func _try_pull_inputs(b: Building, world: Node2D, recipe: Dictionary) -> void:
	var capacity: int = int(recipe["input_capacity"])
	# Group inputs by WORLD direction (after rotation). -1 = no preference.
	# default_accept gathers items that should be pulled from any edge.
	# per_dir_accept[world_dir] gathers items pinned to a specific edge.
	var default_accept: Array = []
	var per_dir_accept: Dictionary = {}
	for pair in recipe["inputs_solid"]:
		var item_type: int = int(pair[0])
		if _buffer_count(b.state["in_buffer"], item_type) >= capacity:
			continue  # already at cap for this input
		var canonical_dir: int = int(pair[2]) if pair.size() >= 3 else -1
		var world_dir: int = Buildings.world_dir(b, canonical_dir)
		if world_dir < 0:
			default_accept.append(item_type)
		else:
			if not per_dir_accept.has(world_dir):
				per_dir_accept[world_dir] = []
			per_dir_accept[world_dir].append(item_type)

	# Pinned inputs first: scan their (rotated) declared edge only.
	for world_dir in per_dir_accept.keys():
		var accept: Array = per_dir_accept[world_dir]
		for cell in Buildings.edge_cells(b.type, b.anchor, world_dir):
			if _try_pull_from_cell(b, world, cell, accept):
				return  # one pull per tick

	# Default-scan inputs: scan all 4 edges.
	if not default_accept.is_empty():
		for dir in 4:
			for cell in Buildings.edge_cells(b.type, b.anchor, dir):
				if _try_pull_from_cell(b, world, cell, default_accept):
					return

## Try to pull one item from a belt at `cell` matching `accept` list.
## Returns true on successful pull.
static func _try_pull_from_cell(b: Building, world: Node2D, cell: Vector2i, accept: Array) -> bool:
	if not world.has_building_at(cell):
		return false
	var neighbor: Building = world.building_at(cell)
	if neighbor == null or neighbor.type != Buildings.Type.BELT:
		return false
	var pulled: int = Belt.try_pull_matching(neighbor, b.anchor, accept)
	if pulled >= 0:
		_buffer_add(b.state["in_buffer"], pulled, 1)
		return true
	return false

static func _has_all_inputs(b: Building, recipe: Dictionary) -> bool:
	for pair in recipe["inputs_solid"]:
		var item_type: int = int(pair[0])
		var need: int = int(pair[1])
		if _buffer_count(b.state["in_buffer"], item_type) < need:
			return false
	return true

## Check that every fluid input the recipe needs is available somewhere
## adjacent to the building. Multi-tile aware.
##
## STRICT MODE (fluid input declares prefer_dir): the recipe's canonical
## prefer_dir is rotated by the building's orientation, then only cells
## along that world-edge are scanned for a pipe in a pump-bearing network.
##
## DEFAULT (no prefer_dir): scan all perimeter cells (4× chances on a 2×2).
##
## Today no recipe declares fluid prefer_dir; the strict path is forward-
## compat for recipes that need a dedicated water inlet on a specific edge.
static func _has_fluid_inputs(b: Building, recipe: Dictionary, world: Node2D) -> bool:
	for pair in recipe.get("inputs_fluid", []):
		var fluid_type: int = int(pair[0])
		var canonical_dir: int = int(pair[2]) if pair.size() >= 3 else -1
		var world_dir: int = Buildings.world_dir(b, canonical_dir)
		if world_dir >= 0:
			if not world.fluid_available_for_building_edge(b, world_dir, fluid_type):
				return false
		else:
			if not world.fluid_available_for_building(b, fluid_type):
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

## Push outputs to adjacent buildings. Multi-tile aware: iterates every
## cell along the relevant edge of the footprint.
##
## STRICT MODE (output declares prefer_dir): scan only the rotated world-edge.
## Recipes declare prefer_dir in canonical orientation; Buildings.world_dir()
## rotates by the building's current dir. If no neighbor on that edge
## accepts, item waits.
##
## DEFAULT (no prefer_dir): scan all 4 edges, chests first then belts.
##
## Outputs processed in array order; first push that succeeds wins the
## tick. Two outputs preferring the same edge = first listed wins.
static func _try_push_outputs(b: Building, world: Node2D, recipe: Dictionary) -> void:
	for pair in recipe["outputs_solid"]:
		var item_type: int = int(pair[0])
		if _buffer_count(b.state["out_buffer"], item_type) <= 0:
			continue
		var canonical_dir: int = int(pair[2]) if pair.size() >= 3 else -1
		var world_dir: int = Buildings.world_dir(b, canonical_dir)

		if world_dir >= 0:
			# Strict: try only the (rotated) preferred edge's cells.
			for cell in Buildings.edge_cells(b.type, b.anchor, world_dir):
				if _try_push_to_cell(b, world, item_type, cell):
					return
			# Push failed — item waits.
		else:
			# No preference: chests first across all edges, then belts.
			for dir in 4:
				for cell in Buildings.edge_cells(b.type, b.anchor, dir):
					if _try_push_chest_to_cell(b, world, item_type, cell):
						return
			for dir in 4:
				for cell in Buildings.edge_cells(b.type, b.anchor, dir):
					if _try_push_belt_to_cell(b, world, item_type, cell):
						return

## True when `belt` carries items INTO building `b` — that is, the cell the
## belt points at is inside b's footprint. Such a belt is a FEEDER, and is
## never a legal output sink (audit finding #14).
##
## Why it is never legal: `Belt.try_insert` drops the item in slot 0 and the
## belt then carries it toward the machine that just made it. The machine will
## not re-accept its own output — `_try_pull_inputs` accepts only the current
## recipe's inputs — so the item reaches the front slot and parks there
## forever. Repeat once per tick and the feeder saturates with output: the
## supply line is dead and the items are stranded. MEASURED before this guard,
## on a mill with one E-pointing belt on its W side: 400 ticks turned
## [GRAIN,GRAIN,GRAIN,GRAIN] into four FLOUR and `Belt.try_insert(feeder,
## GRAIN)` began returning false.
##
## Deliberately narrow. Only belts pointing INTO the footprint are refused; a
## belt running PAST the building is a legitimate sink and still accepts.
## test_processor_feeder_push.gd case (5) pins that distinction — a guard that
## simply refused every belt would pass every other case in that file.
##
## Deterministic: a pure function of the belt's dir and anchor and the
## building's type and anchor. No dict iteration, no build order.
static func _belt_feeds_building(belt: Building, b: Building) -> bool:
	var d: int = int(belt.state.get("dir", 0))
	return Buildings.footprint_contains(b.type, b.anchor, belt.anchor + Belt.DIR_VECS[d])

## Try to push one `item_type` to whatever building is at `cell`. Accepts
## chests (direct insert) and belts (try_insert). Returns true on success.
##
## This is the STRICT (prefer_dir) path. It needs the feeder guard just as
## much as the no-preference sweep does: a recipe's declared output edge is
## wherever the player put a belt, and nothing stops that belt pointing back
## into the machine. Finding #14 cited only the no-preference branch; the
## defect is in both, and test_processor_feeder_push.gd case (4) reproduced it
## here on the composter's canonical-E compost port.
static func _try_push_to_cell(b: Building, world: Node2D, item_type: int, cell: Vector2i) -> bool:
	if not world.has_building_at(cell):
		return false
	var neighbor: Building = world.building_at(cell)
	if neighbor == null:
		return false
	var pushed: bool = false
	if neighbor.type == Buildings.Type.CHEST:
		pushed = Chest.try_insert(neighbor, item_type, 1)
	elif neighbor.type == Buildings.Type.BELT:
		if _belt_feeds_building(neighbor, b):
			return false
		pushed = Belt.try_insert(neighbor, item_type)
	if pushed:
		_buffer_remove(b.state["out_buffer"], item_type, 1)
	return pushed

static func _try_push_chest_to_cell(b: Building, world: Node2D, item_type: int, cell: Vector2i) -> bool:
	if not world.has_building_at(cell):
		return false
	var neighbor: Building = world.building_at(cell)
	if neighbor == null or neighbor.type != Buildings.Type.CHEST:
		return false
	if Chest.try_insert(neighbor, item_type, 1):
		_buffer_remove(b.state["out_buffer"], item_type, 1)
		return true
	return false

static func _try_push_belt_to_cell(b: Building, world: Node2D, item_type: int, cell: Vector2i) -> bool:
	if not world.has_building_at(cell):
		return false
	var neighbor: Building = world.building_at(cell)
	if neighbor == null or neighbor.type != Buildings.Type.BELT:
		return false
	if _belt_feeds_building(neighbor, b):
		return false      # #14: a belt pointing into us is an input, not a sink
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
		# Input port assignments — visible so player knows where to place belts.
		# Show WORLD directions (after rotation), since that's where the player
		# must put belts to feed this building right now.
		var input_ports: Array = []
		for input_pair in recipe.get("inputs_solid", []):
			if input_pair.size() >= 3:
				var canonical_in: int = int(input_pair[2])
				var world_in: int = Buildings.world_dir(b, canonical_in)
				if world_in >= 0:
					input_ports.append("%s ← %s" % [Items.name_of(int(input_pair[0])), Belt.DIR_NAMES[world_in]])
		if not input_ports.is_empty():
			lines.append("Input ports: %s" % ", ".join(input_ports))
		# Output port assignments — visible so player knows where to place belts.
		var ports: Array = []
		for output_pair in recipe.get("outputs_solid", []):
			if output_pair.size() >= 3:
				var canonical_out: int = int(output_pair[2])
				var world_out: int = Buildings.world_dir(b, canonical_out)
				if world_out >= 0:
					ports.append("%s → %s" % [Items.name_of(int(output_pair[0])), Belt.DIR_NAMES[world_out]])
		if not ports.is_empty():
			lines.append("Output ports: %s" % ", ".join(ports))
		# Orientation, so player can correlate ports with what they see.
		if Buildings.is_rotatable(b.type):
			lines.append("Facing: %s (R to rotate before placing)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])
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
			var canonical_dir: int = int(pair[2]) if pair.size() >= 3 else -1
			var world_dir: int = Buildings.world_dir(b, canonical_dir)
			var available: bool
			if world_dir >= 0:
				available = world.fluid_available_for_building_edge(b, world_dir, fluid_type)
			else:
				available = world.fluid_available_for_building(b, fluid_type)
			if not available:
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
