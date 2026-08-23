extends RefCounted

## Fertilizer Applicator — Premium Compost (HIGH) intake + wasteland
## targeting. Regression suite for audit findings #4 and #5, which
## interlock and were fixed as one unit.
##
## #4 — `buildings.gd`'s FERTILIZER_APPLICATOR input slot accepted
## COMPOST_HIGH ("so applicators can be belt-fed Premium Compost for
## wasteland-recovery automation") but the tick logic never did: the belt
## pull's accept list was [LOW, MID] and the buffer-selection helper
## checked MID then LOW. A HIGH item therefore sat in the buffer consuming
## capacity forever, and the machine reported IDLE while holding input.
##
## #5 — the target picker filtered on soil and tier but never asked
## `GridWorld.is_wasteland_at`. A scarred tile sits at soil 0 and never
## regens, so it always wins the most-depleted sort — but
## `try_apply_fertilizer` rejects every tier below HIGH on scarred ground.
## One scarred tile in coverage therefore wedged the applicator in
## STATE_BLOCKED forever, re-picking the same rejected target every tick,
## while ordinary depleted tiles in the same 5×5 went untouched.
##
## The two are one defect: #5's wedge only fired for LOW/MID because
## LOW/MID was all the applicator could hold. The combined rule is "skip
## wasteland tiles unless the selected tier restores wasteland", and
## sub-suite 4 is what distinguishes it from simply skipping every
## wasteland tile.
##
## Sub-suites:
##   1. Belt-fed HIGH reaches the buffer (#4, automation intake).
##   2. HIGH in the buffer is selected and applied, and outranks MID/LOW
##      (#4, selection path).
##   3. A scarred tile does not wedge a LOW/MID-loaded applicator (#5).
##   4. A HIGH-loaded applicator DOES target the scarred tile and restores
##      it (the combined rule — and the automation the slot advertises).
##   5. Drift guard, both directions: every tier the input slot accepts is
##      belt-pullable AND applicable, and every tier in TIER_PREFERENCE is
##      on the slot's accepts list. This is the assertion that would have
##      caught #4.
##   6. The aggregate INPUT_BUFFER_CAPACITY bound still holds with HIGH
##      counted in the mix.
##   7. The panel's coverage grid paints a rejected scar as CELL_WASTELAND,
##      not as CELL_PRISTINE — and still paints it CELL_ELIGIBLE when HIGH
##      is loaded. Follow-up to the #4/#5 fix: _cell_color was routed
##      through _tile_eligible but had no wasteland branch, so a scar the
##      machine had just refused rendered in the "healthy, nothing to do"
##      colour, and nothing in the suite ever constructed a panel.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const ApplicatorPanelScript = preload("res://scripts/ui/fertilizer_applicator_panel.gd")

static func test_name() -> String:
	return "applicator wasteland recovery (HIGH intake + scarred-tile targeting)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. Belt-fed HIGH reaches the buffer (#4) ----------
	# Applicator at (0,0) with dir=DIR_E puts its canonical-W input port at
	# world DIR_W (world_dir = (DIR_W + DIR_E) % 4 = DIR_W), so the feeding
	# belt goes at (-1, 0) pointing east into it.
	var world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (belt-fed HIGH): %s" % world.last_building_place_error }
	# Belts need a hard overlay (Stone / Path / Tilled Soil) under them.
	world.set_overlay(Vector2i(-1, 0), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.BELT, Vector2i(-1, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "belt placement failed (belt-fed HIGH): %s" % world.last_building_place_error }
	var app: Building = world.building_at(Vector2i(0, 0))
	var belt: Building = world.building_at(Vector2i(-1, 0))
	# Fill all 4 belt slots with Premium Compost. A belt whose facing
	# neighbour is not another belt parks its front item (Belt.post_tick
	# only hands off to belts), so nothing leaves except by the pull.
	var belt_slots: Array = belt.state["slots"]
	for i in belt_slots.size():
		belt_slots[i] = Items.Type.COMPOST_HIGH
	# 12 ticks — the pull is 1/tick, so 4 is enough; the rest is margin.
	# Well short of APPLY_INTERVAL_TICKS (100), so no apply confuses the count.
	_tick(12)
	_check(failures, _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_HIGH) == 4,
		"belt-fed HIGH: expected 4 Premium Compost pulled into the buffer, got %d" % _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_HIGH))
	var belt_left: int = 0
	for i in belt_slots.size():
		if int(belt_slots[i]) >= 0:
			belt_left += 1
	_check(failures, belt_left == 0,
		"belt-fed HIGH: belt should be drained, %d slots still occupied" % belt_left)
	_disconnect(world); world.queue_free()

	# ---------- 2. HIGH in the buffer is selected and applied (#4) ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (HIGH selection): %s" % world.last_building_place_error }
	app = world.building_at(Vector2i(0, 0))
	# 2a. HIGH-only buffer. Pre-fix this returned -1 from tier selection and
	# the machine went STATE_IDLE while holding input. Two items are loaded
	# so one survives the single apply in this window — IDLE-with-an-empty-
	# buffer is correct behaviour and would mask the defect being tested.
	app.state["in_buffer"] = [[Items.Type.COMPOST_HIGH, 2]]
	world.tile_soil_modifications[Vector2i(1, 0)] = 50
	_tick(110)
	_check(failures, world.tile_fertilizer_tier(Vector2i(1, 0)) == Items.Type.COMPOST_HIGH,
		"HIGH-only buffer: tile (1,0) should carry HIGH, got tier %d" % world.tile_fertilizer_tier(Vector2i(1, 0)))
	_check(failures, int(app.state.get("state", -1)) != FertilizerApplicator.STATE_IDLE,
		"HIGH-only buffer: machine must not report IDLE while still holding a HIGH item")
	_check(failures, _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_HIGH) == 1,
		"HIGH-only buffer: exactly 1 HIGH should have been consumed, %d left of 2" % _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_HIGH))

	# 2b. Mixed buffer — HIGH outranks MID, which outranks LOW.
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, 1], [Items.Type.COMPOST_MID, 1], [Items.Type.COMPOST_HIGH, 1]]
	world.tile_soil_modifications[Vector2i(2, 0)] = 50
	_tick(110)
	_check(failures, world.tile_fertilizer_tier(Vector2i(2, 0)) == Items.Type.COMPOST_HIGH,
		"mixed buffer: tile (2,0) should take HIGH ahead of MID/LOW, got tier %d" % world.tile_fertilizer_tier(Vector2i(2, 0)))
	_check(failures, _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_MID) == 1
		and _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_LOW) == 1,
		"mixed buffer: MID and LOW should both be untouched, MID=%d LOW=%d" % [
			_buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_MID),
			_buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_LOW)])
	_disconnect(world); world.queue_free()

	# ---------- 3. A scarred tile must not wedge LOW/MID (#5) ----------
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (wedge): %s" % world.last_building_place_error }
	app = world.building_at(Vector2i(10, 10))
	var scar: Vector2i = Vector2i(11, 10)
	var ordinary: Vector2i = Vector2i(12, 10)
	# Force the scar directly (same idiom as test_wasteland.gd sub-suite 3):
	# we are testing the applicator's targeting, not the scar trigger.
	_scar(world, scar)
	world.tile_soil_modifications[ordinary] = 40
	app.state["in_buffer"] = [[Items.Type.COMPOST_MID, 2]]
	_tick(110)
	# THE assertion. Pre-fix the picker returned the scarred tile every
	# tick (soil 0 always wins the most-depleted sort), try_apply_fertilizer
	# rejected MID on scarred ground, and the machine sat in STATE_BLOCKED
	# with this ordinary tile one step away and never touched.
	_check(failures, world.tile_fertilizer_tier(ordinary) == Items.Type.COMPOST_MID,
		"scarred wedge: ordinary depleted tile (12,10) should have taken MID, got tier %d" % world.tile_fertilizer_tier(ordinary))
	_check(failures, int(app.state.get("state", -1)) == FertilizerApplicator.STATE_SCANNING,
		"scarred wedge: machine should be SCANNING after a successful apply, got state %d" % int(app.state.get("state", -1)))
	_check(failures, _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_MID) == 1,
		"scarred wedge: exactly 1 MID should have been consumed, %d left of 2" % _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_MID))
	# The scarred tile itself is untouched — MID cannot restore it, and no
	# boost state may be written to a tile try_apply_fertilizer rejects.
	_check(failures, world.is_wasteland_at(scar),
		"scarred wedge: scarred tile must stay scarred under MID")
	_check(failures, world.tile_fertilizer_tier(scar) == -1,
		"scarred wedge: scarred tile must not receive a MID boost, got tier %d" % world.tile_fertilizer_tier(scar))
	_disconnect(world); world.queue_free()

	# ---------- 4. HIGH targets and restores the scarred tile ----------
	# The combined rule, and what separates it from "skip all wasteland":
	# the scarred tile is still soil 0, so it still wins the most-depleted
	# sort — and with HIGH selected it is a LEGAL target, so it wins outright.
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(20, 20), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (HIGH restore): %s" % world.last_building_place_error }
	app = world.building_at(Vector2i(20, 20))
	var scar_hi: Vector2i = Vector2i(21, 20)
	var ordinary_hi: Vector2i = Vector2i(22, 20)
	_scar(world, scar_hi)
	world.tile_soil_modifications[ordinary_hi] = 40
	# Two loaded, one applied in this window — see 2a on why an empty buffer
	# would make the trailing STATE_SCANNING assertion vacuous.
	app.state["in_buffer"] = [[Items.Type.COMPOST_HIGH, 2]]
	_tick(110)
	_check(failures, not world.is_wasteland_at(scar_hi),
		"HIGH restore: scarred flag should be erased by the applicator's HIGH apply")
	_check(failures, world.tile_soil_health(scar_hi) == GridWorldScript.WASTELAND_RESTORE_SOIL,
		"HIGH restore: soil should snap to %d, got %d" % [GridWorldScript.WASTELAND_RESTORE_SOIL, world.tile_soil_health(scar_hi)])
	_check(failures, world.tile_fertilizer_tier(scar_hi) == Items.Type.COMPOST_HIGH,
		"HIGH restore: restored tile should carry the HIGH boost, got tier %d" % world.tile_fertilizer_tier(scar_hi))
	# The ordinary tile is the control: it proves the scarred tile was
	# CHOSEN over it, not merely tolerated after the ordinary one was served.
	_check(failures, world.tile_fertilizer_tier(ordinary_hi) == -1,
		"HIGH restore: the soil-40 tile should lose the most-depleted sort to the soil-0 scar, got tier %d" % world.tile_fertilizer_tier(ordinary_hi))
	_check(failures, int(app.state.get("state", -1)) == FertilizerApplicator.STATE_SCANNING,
		"HIGH restore: machine should be SCANNING after the restore, got state %d" % int(app.state.get("state", -1)))
	_disconnect(world); world.queue_free()

	# ---------- 5. Drift guard: accepts and TIER_PREFERENCE are set-equal ----------
	# #4 was a drift between the input slot's accepts list in buildings.gd
	# and the two hardcoded tier lists in fertilizer_applicator.gd. This
	# walks the slot's own accepts list and proves each entry survives the
	# whole path: belt pull → buffer → selection → applied boost.
	var accepts: Array = _input_slot_accepts(Buildings.Type.FERTILIZER_APPLICATOR)
	_check(failures, accepts.size() >= 3,
		"drift guard: expected the applicator input slot to accept 3 compost tiers, found %d" % accepts.size())
	for tier in accepts:
		var res: Dictionary = _tier_round_trip(parent, int(tier))
		if not bool(res.get("placed", false)):
			# No world to tear down here: the previous sub-suite's world was
			# already disconnected and freed, and _tier_round_trip frees its
			# own on every failure path.
			return { "ok": false, "message": "drift guard: setup failed for tier %s -- %s" % [Items.name_of(int(tier)), str(res.get("error", ""))] }
		_check(failures, bool(res["pulled"]),
			"drift guard: %s is in the slot's accepts list but is never pulled from a belt" % Items.name_of(int(tier)))
		_check(failures, bool(res["applied"]),
			"drift guard: %s is in the slot's accepts list but never lands on a tile" % Items.name_of(int(tier)))
	# The reverse direction. The walk above only proves accepts ⊆ usable; the
	# comment on TIER_PREFERENCE claims the two are SET-EQUAL. A tier added to
	# TIER_PREFERENCE but not to the slot is belt-pullable and appliable, yet
	# drag-drop and the inserter both refuse it — the same drift mirrored, and
	# invisible to every assertion above it.
	for tier in FertilizerApplicator.TIER_PREFERENCE:
		_check(failures, int(tier) in accepts,
			"drift guard: %s is in TIER_PREFERENCE (belt-pullable) but missing from the input slot's accepts list" % Items.name_of(int(tier)))

	# ---------- 6. Aggregate buffer bound still holds with HIGH ----------
	# INPUT_BUFFER_CAPACITY is an AGGREGATE bound across every tier the one
	# slot accepts (inserter.gd relies on this too). Adding HIGH to the belt
	# pull must not turn it into a per-tier bound.
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (capacity): %s" % world.last_building_place_error }
	world.set_overlay(Vector2i(-1, 0), Terrain.Overlay.STONE)
	if not world.place_building(Buildings.Type.BELT, Vector2i(-1, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "belt placement failed (capacity): %s" % world.last_building_place_error }
	app = world.building_at(Vector2i(0, 0))
	belt = world.building_at(Vector2i(-1, 0))
	var cap: int = FertilizerApplicator.INPUT_BUFFER_CAPACITY
	# One short of the cap, split across LOW and MID; belt offers HIGH.
	app.state["in_buffer"] = [[Items.Type.COMPOST_LOW, cap - 8], [Items.Type.COMPOST_MID, 7]]
	belt_slots = belt.state["slots"]
	for i in belt_slots.size():
		belt_slots[i] = Items.Type.COMPOST_HIGH
	_tick(12)
	_check(failures, _buffer_total(app.state.get("in_buffer", [])) == cap,
		"aggregate cap: buffer should stop at %d in total, got %d" % [cap, _buffer_total(app.state.get("in_buffer", []))])
	_check(failures, _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_HIGH) == 1,
		"aggregate cap: exactly 1 HIGH should have fit in the last free slot, got %d" % _buffer_count(app.state.get("in_buffer", []), Items.Type.COMPOST_HIGH))
	_disconnect(world); world.queue_free()

	# ---------- 7. Panel coverage grid paints the scar (_cell_color) ----------
	# The grid is the only place the eligibility rule is SHOWN. The #4/#5 fix
	# routed _cell_color through _tile_eligible — correct — but added no
	# wasteland branch, so a scar the machine had just refused fell through to
	# CELL_PRISTINE, the "healthy, nothing to do" dim sage. A BLOCKED applicator
	# holding Rich Compost therefore rendered 25 identical cells with no hint of
	# which tile needed Premium. Nothing in the suite constructed a panel, so a
	# revert of _cell_color to its own soil-and-tier test would have stayed green.
	world = GridWorldScript.new()
	parent.add_child(world)
	if not world.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(30, 30), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "applicator placement failed (cell colour): %s" % world.last_building_place_error }
	app = world.building_at(Vector2i(30, 30))
	var scar_px: Vector2i = Vector2i(31, 30)      # scarred, soil 0
	var ordinary_px: Vector2i = Vector2i(32, 30)  # ordinary depleted, soil 40
	var boosted_px: Vector2i = Vector2i(29, 30)   # already carrying a HIGH boost
	_scar(world, scar_px)
	world.tile_soil_modifications[ordinary_px] = 40
	world.tile_soil_modifications[boosted_px] = 50
	if not world.try_apply_fertilizer(boosted_px, Items.Type.COMPOST_HIGH):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "cell colour: setup failed -- HIGH boost would not apply to (29,30)" }
	var panel = ApplicatorPanelScript.new()
	parent.add_child(panel)
	panel.open(app, world)

	# 7a. MID loaded: the scar is refused, so it must read as dead ground —
	# explicitly NOT mustard (the machine will not act on it) and NOT sage
	# (which is what "nothing to do here" means everywhere else in the grid).
	app.state["in_buffer"] = [[Items.Type.COMPOST_MID, 2]]
	var scar_mid: Color = panel._cell_color(scar_px)
	_check(failures, scar_mid == ApplicatorPanelScript.CELL_WASTELAND,
		"cell colour (MID): scarred tile should paint CELL_WASTELAND, got %s" % str(scar_mid))
	_check(failures, scar_mid != ApplicatorPanelScript.CELL_ELIGIBLE,
		"cell colour (MID): scarred tile must not paint CELL_ELIGIBLE — MID cannot restore it")
	_check(failures, scar_mid != ApplicatorPanelScript.CELL_PRISTINE,
		"cell colour (MID): scarred tile must not paint CELL_PRISTINE — that is the untouched-grass colour")
	# 7b. Control: an ordinary depleted tile in the same grid, same buffer, IS
	# actionable and must still read mustard.
	var ord_mid: Color = panel._cell_color(ordinary_px)
	_check(failures, ord_mid == ApplicatorPanelScript.CELL_ELIGIBLE,
		"cell colour (MID): ordinary soil-40 tile should paint CELL_ELIGIBLE, got %s" % str(ord_mid))

	# 7c. HIGH loaded: the scar is now the machine's next move, so the
	# actionable signal wins over the dead-ground signal.
	app.state["in_buffer"] = [[Items.Type.COMPOST_HIGH, 2]]
	var scar_high: Color = panel._cell_color(scar_px)
	_check(failures, scar_high == ApplicatorPanelScript.CELL_ELIGIBLE,
		"cell colour (HIGH): scarred tile should paint CELL_ELIGIBLE — HIGH restores it, got %s" % str(scar_high))

	# 7d. A tile already carrying a HIGH boost outranks every eligibility
	# question — it is fertilized, whatever the buffer holds.
	var boosted_col: Color = panel._cell_color(boosted_px)
	_check(failures, boosted_col == ApplicatorPanelScript.CELL_FERT_HIGH,
		"cell colour: tile carrying a HIGH boost should paint CELL_FERT_HIGH, got %s" % str(boosted_col))
	panel.queue_free()
	_disconnect(world); world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all 7 sub-suites passed (belt-fed HIGH + HIGH selection + scarred wedge + HIGH restore + drift guard + aggregate cap + panel cell colours)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 5))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Advance the sim `n` ticks. Building ticks only — GridWorld._process
## (soil regen, fertilizer decay) does not run inside a synchronous loop,
## which is what keeps these sub-suites deterministic.
static func _tick(n: int) -> void:
	for _i in n:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

## Force `pos` to fully-scarred wasteland, skipping the grace-timer path.
## Mirrors test_wasteland.gd's direct-write setup.
static func _scar(world, pos: Vector2i) -> void:
	world.tile_soil_modifications[pos] = 0
	world.tile_wasteland_state[pos] = {"scarred": true, "decay_remaining": 0.0}

## The `accepts` list declared on the building's input-kind slot.
static func _input_slot_accepts(building_type: int) -> Array:
	var out: Array = []
	for slot_def in Buildings.slot_layout_for(building_type):
		if str(slot_def.get("kind", "")) != "input":
			continue
		for t in slot_def.get("accepts", []):
			out.append(int(t))
	return out

## Drive one tier through the full automation path in a throwaway world:
## belt pull → buffer → selection → boost on a depleted tile. Returns
## { placed, error, pulled, applied }.
static func _tier_round_trip(parent: Node, tier: int) -> Dictionary:
	var w = GridWorldScript.new()
	parent.add_child(w)
	if not w.place_building(Buildings.Type.FERTILIZER_APPLICATOR, Vector2i(0, 0), Belt.DIR_E):
		var err_a: String = w.last_building_place_error
		_disconnect(w); w.queue_free()
		return { "placed": false, "error": err_a, "pulled": false, "applied": false }
	w.set_overlay(Vector2i(-1, 0), Terrain.Overlay.STONE)
	if not w.place_building(Buildings.Type.BELT, Vector2i(-1, 0), Belt.DIR_E):
		var err_b: String = w.last_building_place_error
		_disconnect(w); w.queue_free()
		return { "placed": false, "error": err_b, "pulled": false, "applied": false }
	var a: Building = w.building_at(Vector2i(0, 0))
	var bl: Building = w.building_at(Vector2i(-1, 0))
	bl.state["slots"][0] = tier
	var target: Vector2i = Vector2i(1, 0)
	w.tile_soil_modifications[target] = 50
	# 12 ticks to pull (1/tick), sampled before any apply can fire.
	_tick(12)
	var pulled: bool = _buffer_count(a.state.get("in_buffer", []), tier) == 1
	# Then past the apply threshold.
	_tick(110)
	var applied: bool = w.tile_fertilizer_tier(target) == tier
	_disconnect(w); w.queue_free()
	return { "placed": true, "error": "", "pulled": pulled, "applied": applied }

static func _buffer_total(buf: Array) -> int:
	var n: int = 0
	for entry in buf:
		n += int(entry[1])
	return n

static func _buffer_count(buf: Array, item_type: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
