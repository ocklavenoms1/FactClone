class_name Smelter
extends RefCounted

## Burner Smelter — first multi-recipe processor.
##
## 2×2 building that smelts ore into ingots. Two recipes registered:
## smelt_iron (IRON_ORE → IRON_INGOT) and smelt_copper (COPPER_ORE →
## COPPER_INGOT). Recipe is selected at runtime by inspecting input
## buffer (FIFO — first-arrived ore wins) or peeking the input port.
## See _maybe_select_recipe.
##
## Port layout (canonical, b.dir = DIR_E):
##   W edge: ore input (recipe prefer_dir)
##   E edge: ingot output (recipe prefer_dir)
##   S edge: fuel input (NOT a recipe field — handled by Burner module)
##   N edge: unused
## All ports rotate together via Buildings.world_dir().
##
## State machine (4 states):
##   IDLE             - no recipe-eligible inputs OR waiting for room/fuel
##   SMELTING         - running; fuel committed; progress incrementing
##   NO_FUEL          - has inputs and room, but fuel_buffer == 0
##   BLOCKED_OUTPUT   - has inputs and fuel, but output buffer full
##
## Fuel: 1 fuel unit per ingot (committed at IDLE→SMELTING transition via
## Burner.consume_tick(b, 1)). 1 wood = 1 ingot, 1 coal = 4, 1 briquette = 8.
## Smelting is 8× more fuel-per-output than drilling — reflects the energy
## cost of sustained heat vs mechanical extraction.

# State enum (smelter-specific; mirrors Processor's IDLE/RUNNING/BLOCKED_OUTPUT
# plus burner-specific NO_FUEL).
const STATE_IDLE: int            = 0
const STATE_SMELTING: int        = 1
const STATE_NO_FUEL: int         = 2
const STATE_BLOCKED_OUTPUT: int  = 3

# Fuel input port direction (canonical orientation; rotates with b.dir).
# NOT a recipe field — Burner is generic infrastructure, not recipe-aware.
const FUEL_PORT_DIR: int = Belt.DIR_S

# Fuel cost — 1 unit per ingot, paid up-front at IDLE→SMELTING.
const FUEL_PER_INGOT: int = 1

# Item-type → recipe-id map for runtime recipe selection. Hardcoded for v1
# (only 2 recipes). Adding a third smelter recipe = add one entry here AND
# one entry in Recipes.DATA. If this grows beyond ~5 entries, derive from
# Recipes.for_building(SMELTER) instead.
const _INPUT_TO_RECIPE: Dictionary = {
	Items.Type.IRON_ORE:   "smelt_iron",
	Items.Type.COPPER_ORE: "smelt_copper",
}

# Visuals
const BODY_COLOR: Color = Color(0.30, 0.28, 0.25)       # anthracite
const BODY_BORDER: Color = Color(0.10, 0.09, 0.08)
const HEAD_COLOR: Color = Color(0.45, 0.40, 0.35)       # chimney/vent — slightly lighter
# State tints (multiplied with body color).
const TINT_SMELTING: Color = Color(1.5, 0.8, 0.5)       # orange-red glow
const TINT_NO_FUEL: Color = Color(0.6, 0.6, 1.0)        # cool blue
const TINT_BLOCKED: Color = Color(1.0, 0.95, 0.4)       # yellow

## Build initial smelter state. Recipe defaults to "" (auto-selected on first
## tick). Burner state merged in.
static func make(pos: Vector2i, dir: int = 0) -> Building:
	var state: Dictionary = {
		"recipe_id": "",                # auto-selected by _maybe_select_recipe
		"state": STATE_IDLE,
		"progress": 0,
		"in_buffer": [],
		"out_buffer": [],
		"dir": dir,
	}
	# Merge Burner fields (fuel_buffer, fuel_burn_progress).  [BURNER LINE 1/N]
	for k in Burner.make_state().keys():
		state[k] = Burner.make_state()[k]
	return Building.new(Buildings.Type.SMELTER, pos, state)

## Per-tick logic. Dispatched from Buildings.tick_one.
static func tick(b: Building, world) -> void:
	# Step 1: fuel pull (S edge, rotated).  [BURNER LINE 2/N]
	Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR))

	# Step 2: maybe pick a recipe based on what's available.
	if int(b.state.get("state", STATE_IDLE)) == STATE_IDLE:
		_maybe_select_recipe(b, world)

	# Step 3: bail if no recipe set yet (no eligible ore anywhere).
	var recipe: Dictionary = Recipes.get_recipe(b.state.get("recipe_id", ""))
	if recipe.is_empty():
		return

	# Step 4: pull inputs — Processor's helper handles prefer_dir, multi-tile,
	# capacity gates. Underscore-prefixed but callable; pattern shared by
	# multi-recipe processors that need pre-tick logic before Processor.tick.
	Processor._try_pull_inputs(b, world, recipe)

	# Step 5: state machine.
	var s: int = int(b.state.get("state", STATE_IDLE))
	match s:
		STATE_IDLE:
			if Processor._has_all_inputs(b, recipe) and Processor._has_room_for_outputs(b, recipe):
				# Try to commit 1 fuel unit. If consume_tick returns false, no
				# fuel — set NO_FUEL and don't consume inputs (recipe waits).
				if Burner.consume_tick(b, FUEL_PER_INGOT):       # [BURNER LINE 3/N]
					Processor._consume_inputs(b, recipe)
					b.state["progress"] = 1
					b.state["state"] = STATE_SMELTING
				else:
					b.state["state"] = STATE_NO_FUEL              # [BURNER LINE 4/N]
		STATE_SMELTING:
			var p: int = int(b.state.get("progress", 0)) + 1
			b.state["progress"] = p
			if p >= int(recipe["time_ticks"]):
				Processor._emit_outputs(b, recipe)
				b.state["progress"] = 0
				b.state["state"] = STATE_IDLE if Processor._has_room_for_outputs(b, recipe) else STATE_BLOCKED_OUTPUT
		STATE_NO_FUEL:                                            # [BURNER LINE 5/N]
			# Re-check fuel each tick. As soon as fuel arrives AND we still
			# have inputs+room, restart the cycle.
			if Processor._has_all_inputs(b, recipe) and Processor._has_room_for_outputs(b, recipe):
				if Burner.consume_tick(b, FUEL_PER_INGOT):        # [BURNER LINE 6/N]
					Processor._consume_inputs(b, recipe)
					b.state["progress"] = 1
					b.state["state"] = STATE_SMELTING
			# else: still stalled (input/output may have changed, re-check next tick).
		STATE_BLOCKED_OUTPUT:
			if Processor._has_room_for_outputs(b, recipe):
				b.state["state"] = STATE_IDLE

	# Step 6: push outputs.
	Processor._try_push_outputs(b, world, recipe)

# ---------- recipe selection (the multi-recipe architectural meat) ----------

## Pick recipe_id at IDLE based on what ore is available.
##
## Order of precedence:
##   1. in_buffer: if any item in the buffer matches a known recipe, pick
##      THAT recipe (FIFO via array order — first item wins). This is the
##      key "belt routing IS the recipe selector" contract: items pulled
##      first get smelted first, even if a different ore arrives later.
##   2. Input port peek: if buffer is empty, scan adjacent W-edge belts
##      for any recipe-eligible ore. First found wins.
##   3. Otherwise: leave recipe_id unchanged (will be "" on a fresh smelter).
##
## Recipe-switching only happens when the buffer is empty AT IDLE — once
## SMELTING, the recipe is pinned for the duration of that batch.
static func _maybe_select_recipe(b: Building, world) -> void:
	# (1) in_buffer first — FIFO ordering preserves first-arrived-wins.
	for entry in b.state.get("in_buffer", []):
		var item_type: int = int(entry[0])
		if int(entry[1]) > 0 and _INPUT_TO_RECIPE.has(item_type):
			b.state["recipe_id"] = _INPUT_TO_RECIPE[item_type]
			return
	# (2) port peek.
	var ore_dir: int = Buildings.world_dir(b, Belt.DIR_W)
	for cell in Buildings.edge_cells(b.type, b.anchor, ore_dir):
		var src: Building = world.building_at(cell)
		if src == null or src.type != Buildings.Type.BELT:
			continue
		for slot_t in src.state.get("slots", []):
			var t: int = int(slot_t)
			if t >= 0 and _INPUT_TO_RECIPE.has(t):
				b.state["recipe_id"] = _INPUT_TO_RECIPE[t]
				return
	# (3) leave recipe_id as-is.

# ---------- Q-inspect / info_lines ----------

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	# Status — most prominent.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var status: String = "Idle"
	match s:
		STATE_SMELTING:
			status = "Smelting"
		STATE_NO_FUEL:
			status = "NO FUEL"
		STATE_BLOCKED_OUTPUT:
			status = "Output blocked"
	lines.append("Status: %s" % status)

	# Currently smelting — prominent. Reflects auto-selected recipe.
	var recipe_id: String = str(b.state.get("recipe_id", ""))
	var recipe: Dictionary = Recipes.get_recipe(recipe_id) if recipe_id != "" else {}
	if not recipe.is_empty():
		lines.append("Currently smelting: %s" % recipe.get("display_name", recipe_id))
	else:
		lines.append("Currently smelting: (none — feed iron or copper ore)")

	# Progress bar (when SMELTING).
	if s == STATE_SMELTING and not recipe.is_empty():
		var p: int = int(b.state.get("progress", 0))
		lines.append("Progress: %d / %d ticks" % [p, int(recipe["time_ticks"])])

	# Input / output buffers.
	lines.append("In:  %s" % _fmt_buffer(b.state.get("in_buffer", [])))
	lines.append("Out: %s" % _fmt_buffer(b.state.get("out_buffer", [])))

	# Fuel from Burner.                                            [BURNER LINE 7/N]
	for line in Burner.info_lines(b):                              # [BURNER LINE 8/N]
		lines.append(line)

	# Port assignments — visible so player knows where to place belts.
	if not recipe.is_empty():
		var input_ports: Array = []
		for input_pair in recipe.get("inputs_solid", []):
			if input_pair.size() >= 3:
				var canonical_in: int = int(input_pair[2])
				var world_in: int = Buildings.world_dir(b, canonical_in)
				if world_in >= 0:
					input_ports.append("%s ← %s" % [Items.name_of(int(input_pair[0])), Belt.DIR_NAMES[world_in]])
		if not input_ports.is_empty():
			lines.append("Input ports: %s" % ", ".join(input_ports))
		var output_ports: Array = []
		for output_pair in recipe.get("outputs_solid", []):
			if output_pair.size() >= 3:
				var canonical_out: int = int(output_pair[2])
				var world_out: int = Buildings.world_dir(b, canonical_out)
				if world_out >= 0:
					output_ports.append("%s → %s" % [Items.name_of(int(output_pair[0])), Belt.DIR_NAMES[world_out]])
		if not output_ports.is_empty():
			lines.append("Output ports: %s" % ", ".join(output_ports))

	# Fuel port (always shown; not recipe-dependent).
	var fuel_world: int = Buildings.world_dir(b, FUEL_PORT_DIR)
	lines.append("Fuel port: ← %s" % Belt.DIR_NAMES[fuel_world])

	# Facing.
	lines.append("Facing: %s (R to rotate before placing)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])
	return lines

static func _fmt_buffer(buf: Array) -> String:
	if buf.is_empty():
		return "(empty)"
	var parts: Array = []
	for entry in buf:
		parts.append("%s ×%d" % [Items.name_of(int(entry[0])), int(entry[1])])
	return ", ".join(parts)

# ---------- rendering ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var fp: Vector2i = Buildings.footprint_of(b.type)
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size * fp.x, tile_size * fp.y))
	# Body color tinted by state.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var tint: Color = Color(1, 1, 1, 1)
	match s:
		STATE_SMELTING:
			tint = TINT_SMELTING
		STATE_NO_FUEL:
			tint = TINT_NO_FUEL
		STATE_BLOCKED_OUTPUT:
			tint = TINT_BLOCKED
	var body_color: Color = Color(
		clamp(BODY_COLOR.r * tint.r, 0.0, 1.0),
		clamp(BODY_COLOR.g * tint.g, 0.0, 1.0),
		clamp(BODY_COLOR.b * tint.b, 0.0, 1.0),
		1.0,
	)
	canvas.draw_rect(rect, body_color, true)
	canvas.draw_rect(rect, BODY_BORDER, false, 2.0)

	# Chimney detail: tall narrow rectangle near the back (north edge in
	# canonical orientation), suggesting heat venting. Doesn't rotate with
	# b.dir — purely cosmetic; fuel/ports are the rotation-relevant features.
	var chimney_w: float = float(tile_size) * 0.30
	var chimney_h: float = float(tile_size) * 0.55
	var chimney_x: float = world_pos.x + (tile_size * fp.x - chimney_w) * 0.5
	var chimney_y: float = world_pos.y + tile_size * 0.18
	var chimney_rect: Rect2 = Rect2(Vector2(chimney_x, chimney_y), Vector2(chimney_w, chimney_h))
	var head_color: Color = Color(
		clamp(HEAD_COLOR.r * tint.r, 0.0, 1.0),
		clamp(HEAD_COLOR.g * tint.g, 0.0, 1.0),
		clamp(HEAD_COLOR.b * tint.b, 0.0, 1.0),
		1.0,
	)
	canvas.draw_rect(chimney_rect, head_color, true)
	canvas.draw_rect(chimney_rect, BODY_BORDER, false, 1.5)

	# Forge mouth: orange-red square in the center, brightens when SMELTING.
	# Visual hint that heat is the work being done here.
	var mouth_size: float = float(tile_size) * 0.40
	var mouth_x: float = world_pos.x + (tile_size * fp.x - mouth_size) * 0.5
	var mouth_y: float = world_pos.y + tile_size * fp.y - mouth_size - tile_size * 0.20
	var mouth_rect: Rect2 = Rect2(Vector2(mouth_x, mouth_y), Vector2(mouth_size, mouth_size))
	var mouth_color: Color
	match s:
		STATE_SMELTING:
			mouth_color = Color(1.00, 0.55, 0.20, 1.0)   # bright orange-red — fire
		STATE_NO_FUEL:
			mouth_color = Color(0.25, 0.25, 0.35, 1.0)   # cold mouth
		_:
			mouth_color = Color(0.40, 0.18, 0.10, 1.0)   # dim ember
	canvas.draw_rect(mouth_rect, mouth_color, true)
	canvas.draw_rect(mouth_rect, BODY_BORDER, false, 1.0)
