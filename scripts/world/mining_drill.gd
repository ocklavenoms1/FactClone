class_name MiningDrill
extends RefCounted

## Burner Mining Drill — automated ore extractor.
##
## 2×2 footprint covering up to 4 ore deposits. Pulls fuel from adjacent
## belts/chests via the generic Burner module. Each ore-production tick:
## drains 1 richness from the highest-richness covered deposit (greedy
## strategy per Q7), produces 1 corresponding ore item into output_buffer,
## consumes fuel via Burner.consume_tick.
##
## Output port: prefer_dir, rotates with building.dir. Default canonical-east.
## Fuel input: any of 4 edges (no fuel prefer_dir for v1).
##
## Stops when:
##   - All covered deposits depleted (STATE_DEPLETED)
##   - Fuel buffer empty (STATE_NO_FUEL)
##   - Output buffer full and prefer_dir won't accept (STATE_BLOCKED_OUTPUT)

# Per-ore-tick rate. At 20 sim ticks/sec, 40 ticks = 0.5 ore/sec uniform.
# Slower than manual mining for stone/coal/clay (which is 2/sec) but
# faster than manual iron/copper (1/sec). Tradeoff: drill doesn't need
# player attention. Future electric drill upgrades this rate.
const DRILL_TICKS_PER_ORE: int = 40

# Ore produced per fuel unit consumed. Combined with DRILL_TICKS_PER_ORE,
# gives: 1 wood (1 fuel unit) → 8 ore = 16 sec; 1 coal (4 units) → 32 ore = 64 sec.
const DRILL_ORE_PER_FUEL: int = 8

# Output buffer capacity per item type (matches Processor pattern).
const OUTPUT_BUFFER_CAPACITY: int = 16

# State machine values (mirror Processor's IDLE/RUNNING/BLOCKED_OUTPUT plus
# drill-specific NO_FUEL and DEPLETED).
const STATE_IDLE: int = 0          # no work this tick (rare; usually transitions to one of the others)
const STATE_DRILLING: int = 1
const STATE_NO_FUEL: int = 2
const STATE_BLOCKED_OUTPUT: int = 3
const STATE_DEPLETED: int = 4

# Visuals
const BODY_COLOR: Color = Color(0.45, 0.40, 0.32)
const BODY_BORDER: Color = Color(0.20, 0.18, 0.14)
const HEAD_COLOR: Color = Color(0.65, 0.55, 0.40)
const NO_FUEL_TINT: Color = Color(1.0, 0.5, 0.5)        # red tint
const BLOCKED_TINT: Color = Color(1.0, 0.95, 0.4)       # yellow tint
const DEPLETED_TINT: Color = Color(0.55, 0.55, 0.55)    # dim gray

const DEFAULT_RECIPE_ID: String = ""   # drill is NOT recipe-driven

## Build initial state. Called from Buildings.make.
##
## covered_deposits is populated at placement time by scanning the footprint
## for ore tiles; persists in state across save/load (deterministic, no
## need to recompute).
##
## NOTE: covered_deposits is filled by mining_drill.refresh_covered_deposits
## after placement (which has access to the world). make() can't see the
## world from here, so we initialize empty and refresh in place_building's
## post-hook.
static func make(pos: Vector2i, dir: int = 0) -> Building:
	var state: Dictionary = {
		"dir": dir,
		"drill_progress": 0,
		"output_buffer": [],
		"covered_deposits": [],   # Array of [x, y] — populated by refresh_covered_deposits
		"state": STATE_IDLE,
	}
	# Merge in burner state (fuel_buffer, fuel_burn_progress).
	for k in Burner.make_state().keys():
		state[k] = Burner.make_state()[k]
	return Building.new(Buildings.Type.MINING_DRILL, pos, state)

## Scan the building's 2×2 footprint, collect positions of ore tiles into
## `covered_deposits`. Called once at placement. Cached so tick doesn't
## re-scan each frame.
##
## Trees in footprint were rejected at placement (Q9 rule); ore tiles are
## the only resource_node type captured here. Tile.resource_node = NONE
## tiles (grass, depleted-tree-stumps, depleted-ore-stumps) are skipped.
static func refresh_covered_deposits(b: Building, world) -> void:
	var deposits: Array = []
	var fp: Vector2i = Buildings.footprint_of(b.type)
	for dx in fp.x:
		for dy in fp.y:
			var pos: Vector2i = Vector2i(b.anchor.x + dx, b.anchor.y + dy)
			if not world.tiles.has(pos):
				continue
			var t: Tile = world.tiles[pos]
			if ResourceNodes.is_ore(t.resource_node):
				deposits.append([pos.x, pos.y])
	b.state["covered_deposits"] = deposits

## Placement validation: check Q9 rules. Called from main.gd or
## Buildings.can_place_building extension.
##
## Returns "" on valid; otherwise a player-facing error string for toast.
static func validate_placement(world, anchor: Vector2i) -> String:
	var fp: Vector2i = Buildings.footprint_of(Buildings.Type.MINING_DRILL)
	var has_ore: bool = false
	for dx in fp.x:
		for dy in fp.y:
			var pos: Vector2i = Vector2i(anchor.x + dx, anchor.y + dy)
			if world.tiles.has(pos):
				var t: Tile = world.tiles[pos]
				if t.is_water():
					return "Drill can't extend into water."
				if t.resource_node == ResourceNodes.Type.TREE:
					return "Chop trees from drill area first."
				if ResourceNodes.is_ore(t.resource_node):
					has_ore = true
	if not has_ore:
		return "Drill must cover an ore deposit."
	return ""

## Per-tick logic. Dispatched from Buildings.tick_one.
static func tick(b: Building, world) -> void:
	# Step 1: pull fuel (any edge).
	Burner.try_pull_fuel(b, world, -1)

	# Step 2: try to push existing output buffer (might unblock from prior tick).
	_try_push_outputs(b, world)

	# Step 3: pick the best deposit (highest richness, deterministic tiebreak).
	var target: Vector2i = _pick_best_deposit(b, world)
	if target == Vector2i(2147483647, 2147483647):
		b.state["state"] = STATE_DEPLETED
		return

	# Step 4: decide if we can drill this tick.
	# Output capacity check: would the produced ore fit?
	var ore_type: int = world.tiles[target].resource_node
	var item_type: int = int(_RESOURCE_TO_ITEM[ore_type])
	if not _output_has_room(b, item_type):
		b.state["state"] = STATE_BLOCKED_OUTPUT
		return

	# Step 5: advance drill progress.
	var progress: int = int(b.state.get("drill_progress", 0)) + 1
	if progress < DRILL_TICKS_PER_ORE:
		b.state["drill_progress"] = progress
		b.state["state"] = STATE_DRILLING
		return

	# Step 6: full ore production tick. Consume fuel + drain richness + produce ore.
	if not Burner.consume_tick(b, DRILL_ORE_PER_FUEL):
		# No fuel — keep progress at threshold; will produce as soon as fuel arrives.
		b.state["drill_progress"] = DRILL_TICKS_PER_ORE
		b.state["state"] = STATE_NO_FUEL
		return

	# Drill the deposit.
	world.deplete_resource(target, 1)
	# Append to output buffer.
	_append_output(b, item_type, 1)
	# Reset drill timer.
	b.state["drill_progress"] = 0
	b.state["state"] = STATE_DRILLING

	# If the deposit just depleted, refresh covered list (the depleted tile
	# is now grass; tile.resource_node = NONE, so it'll be filtered next pick).
	# Actually no refresh needed — _pick_best_deposit re-checks each tick.
	# covered_deposits cache stays stable; we filter via richness_at(pos) > 0.

	# Try push immediately so the buffer doesn't stay full.
	_try_push_outputs(b, world)

# ---------- helpers ----------

# Resource_node → item type produced when drilled.
const _RESOURCE_TO_ITEM: Dictionary = {
	ResourceNodes.Type.STONE:  Items.Type.RAW_STONE,
	ResourceNodes.Type.COAL:   Items.Type.COAL,
	ResourceNodes.Type.IRON:   Items.Type.IRON_ORE,
	ResourceNodes.Type.COPPER: Items.Type.COPPER_ORE,
	ResourceNodes.Type.CLAY:   Items.Type.CLAY,
}

const _MAX_VECTOR2I: Vector2i = Vector2i(2147483647, 2147483647)

## Pick the highest-richness deposit covered by this drill. Tiebreak:
## topmost-leftmost (sort by y, then x). Returns _MAX_VECTOR2I if all
## covered deposits are depleted.
static func _pick_best_deposit(b: Building, world) -> Vector2i:
	var best: Vector2i = _MAX_VECTOR2I
	var best_richness: int = 0
	for entry in b.state.get("covered_deposits", []):
		var pos: Vector2i = Vector2i(int(entry[0]), int(entry[1]))
		var r: int = world.richness_at(pos)
		if r <= 0:
			continue
		if r > best_richness:
			best = pos
			best_richness = r
		elif r == best_richness:
			# Tiebreak: topmost-leftmost (smaller y, then smaller x).
			if pos.y < best.y or (pos.y == best.y and pos.x < best.x):
				best = pos
	return best

## Return true if `item_type` can fit in the output buffer (count < CAPACITY
## for that item type, OR the item type isn't present yet).
static func _output_has_room(b: Building, item_type: int) -> bool:
	var buf: Array = b.state.get("output_buffer", [])
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1]) < OUTPUT_BUFFER_CAPACITY
	# Item type not yet in buffer; slot will be created on append.
	return true

## Add `count` of `item_type` to the output buffer.
static func _append_output(b: Building, item_type: int, count: int) -> void:
	var buf: Array = b.state.get("output_buffer", [])
	for entry in buf:
		if int(entry[0]) == item_type:
			entry[1] = int(entry[1]) + count
			return
	buf.append([item_type, count])

## Try to push items from the output buffer to adjacent belt/chest in the
## building's prefer_dir output direction. Pushes 1 item per tick (matches
## Processor pattern).
static func _try_push_outputs(b: Building, world) -> void:
	var buf: Array = b.state.get("output_buffer", [])
	if buf.is_empty():
		return
	var b_dir: int = int(b.state.get("dir", 0))
	# Default output direction: canonical East, rotated by b.dir.
	var output_dir: int = (Belt.DIR_E + b_dir) % 4
	# Try each entry in the buffer.
	for entry in buf:
		var item_type: int = int(entry[0])
		var count: int = int(entry[1])
		if count <= 0:
			continue
		for cell in Buildings.edge_cells(b.type, b.anchor, output_dir):
			if _try_push_to(world, cell, item_type):
				entry[1] = count - 1
				if int(entry[1]) <= 0:
					buf.erase(entry)
				return   # 1 item pushed per tick
	# Nothing pushed — caller's state machine handles BLOCKED_OUTPUT.

## Try to push one item to a cell. Returns true on success.
static func _try_push_to(world, cell: Vector2i, item_type: int) -> bool:
	var dest: Building = world.building_at(cell)
	if dest == null:
		return false
	if dest.type == Buildings.Type.BELT:
		return Belt.try_insert(dest, item_type)
	if dest.type == Buildings.Type.CHEST:
		return Chest.try_insert(dest, item_type, 1)
	return false

# ---------- Q-inspect / info_lines ----------

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	# State line — most prominent.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var status: String = "(idle)"
	match s:
		STATE_DRILLING:
			status = "Drilling"
		STATE_NO_FUEL:
			status = "NO FUEL"
		STATE_BLOCKED_OUTPUT:
			status = "Output blocked"
		STATE_DEPLETED:
			status = "Depleted"
	lines.append("Status: %s" % status)

	# Currently producing — Q11 prominent line. Reflects highest-richness
	# pick at this instant; changes over time as deposits drain.
	if s == STATE_DRILLING or s == STATE_BLOCKED_OUTPUT:
		var target: Vector2i = _pick_best_deposit(b, world)
		if target != _MAX_VECTOR2I:
			var ore_type: int = world.tiles[target].resource_node
			var item_type: int = int(_RESOURCE_TO_ITEM[ore_type])
			lines.append("Currently producing: %s" % Items.name_of(item_type))

	# Fuel from Burner.
	for line in Burner.info_lines(b):
		lines.append(line)

	# Output buffer.
	var buf: Array = b.state.get("output_buffer", [])
	if buf.is_empty():
		lines.append("Output: (empty)")
	else:
		for entry in buf:
			lines.append("Output: %d %s" % [int(entry[1]), Items.name_of(int(entry[0]))])

	# Covered deposits sorted by richness desc.
	var deposits_with_richness: Array = []
	for entry in b.state.get("covered_deposits", []):
		var pos: Vector2i = Vector2i(int(entry[0]), int(entry[1]))
		var r: int = world.richness_at(pos)
		if r > 0:
			deposits_with_richness.append([pos, r])
	deposits_with_richness.sort_custom(func(a, b_): return int(a[1]) > int(b_[1]))
	if deposits_with_richness.is_empty():
		lines.append("Coverage: all depleted")
	else:
		for entry in deposits_with_richness:
			var p: Vector2i = entry[0]
			var ore_t: int = world.tiles[p].resource_node
			lines.append("  %s @ (%d, %d): %d" % [ResourceNodes.name_of(ore_t), p.x, p.y, int(entry[1])])

	# Facing.
	lines.append("Facing: %s (R to rotate before placing)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])

	return lines

# ---------- rendering ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# 2×2 footprint: cover the full 64×64 area centered at world_pos.
	var fp: Vector2i = Buildings.footprint_of(b.type)
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size * fp.x, tile_size * fp.y))
	# Body color tinted by state.
	var s: int = int(b.state.get("state", STATE_IDLE))
	var tint: Color = Color(1, 1, 1, 1)
	match s:
		STATE_NO_FUEL:
			tint = NO_FUEL_TINT
		STATE_BLOCKED_OUTPUT:
			tint = BLOCKED_TINT
		STATE_DEPLETED:
			tint = DEPLETED_TINT
	var body_color: Color = Color(BODY_COLOR.r * tint.r, BODY_COLOR.g * tint.g, BODY_COLOR.b * tint.b, 1.0)
	canvas.draw_rect(rect, body_color, true)
	canvas.draw_rect(rect, BODY_BORDER, false, 2.0)
	# Drill head: smaller centered square.
	var head_size: float = float(tile_size) * 0.6
	var head_rect: Rect2 = Rect2(
		world_pos + Vector2((tile_size * fp.x - head_size) * 0.5, (tile_size * fp.y - head_size) * 0.5),
		Vector2(head_size, head_size),
	)
	var head_color: Color = Color(HEAD_COLOR.r * tint.r, HEAD_COLOR.g * tint.g, HEAD_COLOR.b * tint.b, 1.0)
	canvas.draw_rect(head_rect, head_color, true)
	canvas.draw_rect(head_rect, BODY_BORDER, false, 1.5)
