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
## State machine (5 states):
##   IDLE             - no recipe-eligible inputs OR waiting for room/fuel
##   SMELTING         - running; fuel committed; progress incrementing
##   NO_FUEL          - has inputs and room, but fuel_buffer == 0 (burner only)
##   BLOCKED_OUTPUT   - has inputs and fuel, but output buffer full
##   NO_POWER         - electric only: network satisfaction <= POWER_EPSILON;
##                      progress is HELD, belt pulls and output pushes keep
##                      running (see the power gate in tick())
##
## Fuel: 1 fuel unit per ingot (committed at IDLE→SMELTING transition via
## Burner.consume_tick(b, 1)). 1 wood = 1 ingot, 1 coal = 4, 1 briquette = 8.
## Smelting is 8× more fuel-per-output than drilling — reflects the energy
## cost of sustained heat vs mechanical extraction.
##
## ELECTRIC VARIANT (session-electricity-processors, Task 3): the same state
## machine, parametrised — NOT a second module (duplicating a shipped state
## machine is the #15/#18 drift shape, refused at design time). Every Burner
## call site is gated on is_electric(b); the Burner.make_state() merge in
## make() deliberately STAYS ungated (locked Q4: fuel fields present-but-
## unused on the electric variant — the shape assertion in the test suite
## pins the key set). Speed: electric runs the shared 40-tick recipes in
## ceil(40 × ELECTRIC_SPEED_RATIO) = 32 ticks, stretched by network
## satisfaction — see _effective_target.

# State enum (smelter-specific; mirrors Processor's IDLE/RUNNING/BLOCKED_OUTPUT
# plus burner-specific NO_FUEL).
const STATE_IDLE: int            = 0
const STATE_SMELTING: int        = 1
const STATE_NO_FUEL: int         = 2
const STATE_BLOCKED_OUTPUT: int  = 3
# APPEND-ONLY from here: the state int round-trips through saves, so the
# values above can never be renumbered. NO_POWER is the ELECTRIC variant's
# stall state (a burner can never reach it), written by the power gate in
# tick() when network satisfaction is at or below POWER_EPSILON.
const STATE_NO_POWER: int        = 4

# Fuel input port direction (canonical orientation; rotates with b.dir).
# NOT a recipe field — Burner is generic infrastructure, not recipe-aware.
const FUEL_PORT_DIR: int = Belt.DIR_S

# Fuel cost — 1 unit per ingot, paid up-front at IDLE→SMELTING.
const FUEL_PER_INGOT: int = 1

# ---------------------------------------------------------------------------
# Electric variant (session-electricity-processors, Task 3).
# ---------------------------------------------------------------------------

# The single source of truth for "is this smelter power-driven": is_electric
# is DERIVED from membership, so "draws power" and "is not a burner" cannot
# drift apart — the shipped electric-inserter shape (inserter.gd's table).
#
# 10 units — 2× the electric inserter's 5, locked at the design pass: four
# electric smelters = 40 = exactly two steam generators or four water
# wheels. Flagged as the likeliest playtest retune.
#
# The draw is CONSTANT, never duty-cycled — an IDLE electric smelter still
# draws its full 10. PowerNetwork.update_supply_demand is a pre-pass that
# runs BEFORE the building tick loop, so any activity state it sampled would
# be one tick stale; gating demand on activity would close a delayed-
# feedback loop (undamped — the network sizing itself to last tick's
# activity) and lamps sharing the component would flicker. See the
# ELECTRIC_SMELTER arm in power_network.gd Stage 1.
const POWER_DEMAND_BY_TYPE: Dictionary = {
	Buildings.Type.ELECTRIC_SMELTER: 10,
}

# Floor on the satisfaction divisor in _effective_target, AND the NO_POWER
# cutoff (`sat <= POWER_EPSILON` parks the machine). Documented-equal to
# Inserter.POWER_EPSILON: 0.05 is the ELECTRIC_LAMP's on/off threshold, so
# "too dark to bother" and "too weak to run" stay the SAME point on the dial
# across every electric consumer. A test literal pins 0.05, so drift from
# the inserter's value reddens instead of silently re-rating the brownout.
const POWER_EPSILON: float = 0.05

# Electric speed multiplier — the machine-side half of the locked speed
# decision: electric smelts the shared recipes in ceil(40 × 0.8) = 32 ticks
# vs the burner's 40, ratio 0.8. MACHINE-SIDE MULTIPLIER ONLY: recipes.gd's
# shared time_ticks 40 stays untouched (the ELECTRIC_SMELTER DATA row
# records the same numbers for the next balance pass). If the user ever
# corrects the balance base, only this multiplier moves.
const ELECTRIC_SPEED_RATIO: float = 0.8

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

## Power units this smelter draws from its network per tick. 0 for the
## burner (lookup miss). Read by PowerNetwork.update_supply_demand Stage 1
## to accumulate component demand. Takes the TYPE, not the building: the
## demand is a property of the registry row, and Stage 1's arm has the type
## in hand.
static func power_demand(t: int) -> int:
	return int(POWER_DEMAND_BY_TYPE.get(t, 0))

## True if this smelter is power-driven rather than fuel-driven. Derived
## from POWER_DEMAND_BY_TYPE membership on purpose — one source of truth,
## see the table's docstring. Gates every Burner call site in tick() and
## info_lines().
static func is_electric(b: Building) -> bool:
	return POWER_DEMAND_BY_TYPE.has(b.type)

## The tick count a batch must reach before it emits — the brownout rule
## (target-stretch, locked at the design pass): int progress accumulates 1
## per tick while SMELTING, and THIS TARGET is recomputed every tick from
## live satisfaction, so elapsed work is revalued when satisfaction changes.
## No float progress, no rate scaling.
##
##   burner:   recipe time_ticks, UNCHANGED — returned BEFORE the
##             satisfaction lookup runs. The early return is load-bearing,
##             not a micro-optimisation: a world with no power network
##             reports satisfaction 0.0 everywhere, and a burner that fell
##             through would crawl at ceil(40 / 0.05) = 800 ticks.
##   electric: ceil(ceil(time_ticks × 0.8) / max(POWER_EPSILON, sat))
##             sat 1.00 → 32    sat 0.50 → 64    sat 0.05 → 640 (the floor)
##
## The form is copied from the shipped inserter
## (Inserter.effective_cycle_ticks, inserter.gd) — NOT from the stale
## Session-1 formula comments in power_network.gd (Task 7 fixes those).
static func _effective_target(b: Building, world, recipe: Dictionary) -> int:
	var base_ticks: int = int(recipe["time_ticks"])
	if not is_electric(b):
		return base_ticks
	base_ticks = int(ceil(float(base_ticks) * ELECTRIC_SPEED_RATIO))
	var sat: float = world.power_satisfaction_at(b.anchor)
	return int(ceil(float(base_ticks) / maxf(POWER_EPSILON, sat)))

## Build initial smelter state. Recipe defaults to "" (auto-selected on first
## tick). Burner state merged in — for BOTH variants: the electric smelter
## deliberately keeps the burner's full state shape, fuel fields present-
## but-unused (locked Q4; the test suite's shape assertion pins the key
## set, and the fuel-sentinel case pins that the fields stay dead).
##
## `b_type` (Electric Processors Task 2, the Inserter.make pattern): the
## ELECTRIC_SMELTER dispatch arm passes its own enum so the building dict
## carries the on-disk 37; every existing caller keeps the burner default.
static func make(pos: Vector2i, dir: int = 0, b_type: int = Buildings.Type.SMELTER) -> Building:
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
	return Building.new(b_type, pos, state)

## Per-tick logic. Dispatched from Buildings.tick_one — both SMELTER and
## ELECTRIC_SMELTER route here; the differences are the `electric` gates on
## the Burner call sites and the power gate above the state machine.
static func tick(b: Building, world) -> void:
	# The electric variant is not a burner: no fuel slot in DATA, no fuel
	# pull, no fuel commit, and it must never show a fuel state. Every
	# Burner call site below is gated on this one flag (the shipped
	# electric-inserter pattern).
	var electric: bool = is_electric(b)

	# Step 1: fuel pull (S edge, rotated) — burner only. Ungated, an
	# electric smelter would eat wood arriving on its (nonexistent) fuel
	# port — the source-tile-as-fuel bug from the other direction.
	if not electric:
		Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR))  # [BURNER LINE 2/N]

	# Step 1b: release a pin the registry can no longer resolve. Must run BEFORE
	# the IDLE gate below AND before step 3's `recipe.is_empty(): return`,
	# because the wedge it clears is precisely a NON-IDLE state holding a dead
	# recipe_id — the bail fires first and selection never gets a turn. See
	# audit #18 and Processor.release_unresolvable_recipe. Same call, same
	# place, in Composter.
	Processor.release_unresolvable_recipe(b)

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

	# Step 5a (electric only): the POWER GATE. At or below POWER_EPSILON —
	# `<=`, the exact comparison the electric inserter and the lamp's glow
	# share, so every electric consumer gives up at the same point on the
	# dial — the machine PARKS: the match below is skipped (STATE_NO_POWER
	# is deliberately named in no arm), so the int progress is HELD exactly
	# where the outage found it. The park is a state label plus a skipped
	# match and NOTHING else: step 4 above and step 6 below keep running,
	# so belt pulls into in_buffer and output pushes continue through the
	# outage (locked stall scope, mirroring burner NO_FUEL's minimal diff).
	#
	# RESUME (power back while parked): progress > 0 means a committed
	# batch was frozen mid-flight — re-enter SMELTING directly, consuming
	# NOTHING; the elapsed work resumes at the live effective target.
	# Routing the resume through the IDLE arm instead would re-commit the
	# batch: progress reset to 1 AND a second set of inputs consumed — the
	# reset-AND-double-consume hazard the test suite's wall-clock
	# completion identity pins against. progress == 0 means the outage
	# caught the machine BETWEEN batches; IDLE is then the correct
	# re-entry and commits normally.
	if electric:
		if world.power_satisfaction_at(b.anchor) <= POWER_EPSILON:
			b.state["state"] = STATE_NO_POWER
			s = STATE_NO_POWER
		elif s == STATE_NO_POWER:
			s = STATE_SMELTING if int(b.state.get("progress", 0)) > 0 else STATE_IDLE
			b.state["state"] = s

	match s:
		STATE_IDLE:
			if Processor._has_all_inputs(b, recipe) and Processor._has_room_for_outputs(b, recipe):
				# Burner: try to commit 1 fuel unit up front; on failure,
				# NO_FUEL and don't consume inputs (recipe waits).
				# Electric: the commit is free — its cost is the CONSTANT
				# network demand, already registered by the pre-pass, never
				# a per-batch debit (the fuel-sentinel test pins that
				# consume_tick is never even called).
				var fuel_ok: bool = true
				if not electric:
					fuel_ok = Burner.consume_tick(b, FUEL_PER_INGOT)  # [BURNER LINE 3/N]
				if fuel_ok:
					Processor._consume_inputs(b, recipe)
					b.state["progress"] = 1
					b.state["state"] = STATE_SMELTING
				elif not electric:
					# `elif not electric`, not a bare `else`: NO_FUEL is a
					# burner-only state — an electric machine must never
					# show 2. With the commit gate above intact this guard
					# is unreachable for the electric variant; it exists so
					# a future edit that breaks that gate cannot ALSO park
					# an electric machine in a fuel state it has no way to
					# leave. The electric stall is STATE_NO_POWER, written
					# by the power gate above the match.
					b.state["state"] = STATE_NO_FUEL              # [BURNER LINE 4/N]
		STATE_SMELTING:
			var p: int = int(b.state.get("progress", 0)) + 1
			b.state["progress"] = p
			# EFFECTIVE, not rated: recomputed every tick from live
			# satisfaction for the electric variant (target-stretch), the
			# rated time_ticks unchanged for the burner.
			if p >= _effective_target(b, world, recipe):
				Processor._emit_outputs(b, recipe)
				b.state["progress"] = 0
				b.state["state"] = STATE_IDLE if Processor._has_room_for_outputs(b, recipe) else STATE_BLOCKED_OUTPUT
		STATE_NO_FUEL:                                            # [BURNER LINE 5/N]
			# Re-check fuel each tick. As soon as fuel arrives AND we still
			# have inputs+room, restart the cycle.
			if Processor._has_all_inputs(b, recipe) and Processor._has_room_for_outputs(b, recipe):
				# `electric or`: no writer puts an electric machine in
				# NO_FUEL, but a hand-edited save can carry state 2. The
				# gate keeps "no Burner call ever runs for an electric
				# machine" true even then — the arm commits for free and
				# the machine self-heals into SMELTING.
				if electric or Burner.consume_tick(b, FUEL_PER_INGOT):        # [BURNER LINE 6/N]
					Processor._consume_inputs(b, recipe)
					b.state["progress"] = 1
					b.state["state"] = STATE_SMELTING
			elif not Processor._has_all_inputs(b, recipe):
				# Inputs went away underneath us — the player emptied the input
				# slot from the panel (SMELTER's slot_layout binds an "input"
				# slot to in_buffer, and BuildingPanel._take_from_slot removes
				# the entry outright). STATE_NO_FUEL asserts "inputs and room,
				# just no fuel"; with the inputs gone that is a lie, and nothing
				# else can undo it — this arm needs _has_all_inputs to fire,
				# _maybe_select_recipe is gated on STATE_IDLE, and
				# _try_pull_inputs filters belt pulls by the still-pinned
				# recipe. So the machine would accept the pinned ore and nothing
				# else, forever. Audit #18, measured: 400 ticks with fuel 8 and
				# four copper ore on the W belt produced nothing.
				#
				# Deliberately an `elif` on missing INPUTS, not an unconditional
				# `else`. #18's fix text justified the narrow form by saying an
				# unconditional `else` would "oscillate IDLE<->NO_FUEL every
				# tick" in the ordinary fuel-starved case. **That rationale is
				# wrong for this code and was mutation-tested to be wrong**: the
				# `else` would bind to the OUTER `if inputs and room`, not to
				# the inner fuel check, so with inputs present it never runs and
				# nothing oscillates. Swapping this `elif` for `else` keeps the
				# whole suite green.
				#
				# The real difference, which case (J) pins: an unconditional
				# `else` ALSO fires when inputs are present but the output
				# buffer is full, reporting "Idle" for a machine that is
				# actually short of fuel and short of a sink. The rule kept is
				# the narrow one — leave a state only when that state's own
				# precondition is violated. NO_FUEL claims "inputs and room, no
				# fuel"; missing inputs falsifies it, a full output does not
				# make "Idle" any truer and _try_push_outputs is draining it.
				b.state["state"] = STATE_IDLE
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
##   1. in_buffer: if any item in the buffer matches a known recipe AND that
##      recipe can start from what is buffered, pick THAT recipe (FIFO via
##      array order — first startable item wins). This is the key "belt
##      routing IS the recipe selector" contract: items pulled first get
##      smelted first, even if a different ore arrives later.
##   2. Input port peek: scan adjacent W-edge belts for any recipe-eligible
##      ore. First found wins.
##   3. Fall back to the first buffer match, so the panel still names the ore
##      that is waiting when nothing can start and no belt offers anything.
##   4. Otherwise: leave recipe_id unchanged (will be "" on a fresh smelter).
##
## Recipe-switching only happens when the buffer is empty AT IDLE — once
## SMELTING, the recipe is pinned for the duration of that batch.
##
## The "can start" test in (1) is a NO-OP for every smelter recipe shipping
## today, because all of them need exactly 1 ore. It is here anyway: this is
## the same rule Composter runs (audit #15/#18 are one defect in two files),
## and the first smelter recipe needing 2+ of an ore would otherwise wedge the
## machine exactly as a lone wheat wedged the composter. Keeping the two
## selectors identical is what stops them drifting apart again.
static func _maybe_select_recipe(b: Building, world) -> void:
	# (1) in_buffer first — FIFO ordering preserves first-arrived-wins.
	var first_match: String = ""
	for entry in b.state.get("in_buffer", []):
		var item_type: int = int(entry[0])
		if int(entry[1]) <= 0 or not _INPUT_TO_RECIPE.has(item_type):
			continue
		var rid: String = _INPUT_TO_RECIPE[item_type]
		if first_match == "":
			first_match = rid
		if Processor.can_start_from_buffer(b, Recipes.get_recipe(rid)):
			b.state["recipe_id"] = rid
			return
	# (2) port peek.
	var ore_dir: int = Buildings.world_dir(b, Belt.DIR_W)
	for cell in Buildings.edge_cells(b.type, b.anchor, ore_dir, Buildings.dir_of(b)):
		var src: Building = world.building_at(cell)
		if src == null or src.type != Buildings.Type.BELT:
			continue
		for slot_t in src.state.get("slots", []):
			var t: int = int(slot_t)
			if t >= 0 and _INPUT_TO_RECIPE.has(t):
				b.state["recipe_id"] = _INPUT_TO_RECIPE[t]
				return
	# (3) nothing startable and no eligible belt — name the waiting ore anyway.
	if first_match != "":
		b.state["recipe_id"] = first_match
		return
	# (4) leave recipe_id as-is.

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
		STATE_NO_POWER:
			# Electric only. Without this arm a parked machine would fall
			# through to "Idle" — the exact lie the inserter panel work
			# exists to prevent (the panels' own arms are Task 5).
			status = "NO POWER"
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

	# Fuel from Burner — burner only: the electric variant's deliberately-
	# kept-but-dead fuel fields would otherwise render as a live fuel gauge
	# on a machine with no fuel slot.                              [BURNER LINE 7/N]
	if not is_electric(b):
		for line in Burner.info_lines(b):                          # [BURNER LINE 8/N]
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

	# Fuel port (burner only, always shown; not recipe-dependent). The
	# electric variant has no fuel path — advertising a port it refuses
	# (test sub-case 13 pins the refusal) would send a player belting wood
	# into a wall.
	if not is_electric(b):
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
	var fp: Vector2i = Buildings.footprint_of_building(b)
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
