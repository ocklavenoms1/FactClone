extends RefCounted

## Inserter Arc Session 4 — held-item conservation across a mid-swing fuel
## outage (audit findings #2 / #6).
##
## THIS TEST IS EXPECTED TO FAIL until Task 2 lands the fix. It is a RED
## test written deliberately ahead of the repair.
##
## The bug (verified against scripts/world/inserter.gd @ HEAD):
##   - inserter.gd:181 — when fuel_buffer <= 0 and the FUEL_PORT_DIR (S edge)
##     pull fails, `b.state["state"] = STATE_NO_FUEL` is written
##     UNCONDITIONALLY, even for an inserter that is mid-swing holding an
##     item. The in-flight WORKING_OUT / BLOCKED_AT_DEST phase is clobbered.
##   - inserter.gd:191 — the match arm `STATE_IDLE, STATE_NO_FUEL:` runs
##     `_try_pickup()` then `_set_held()`. `_set_held` (inserter.gd:287-288)
##     does an unconditional `b.state["held_item_buffer"] = [[item_type, 1]]`,
##     so the item the arm was already carrying is overwritten.
##
## Net effect: an inserter that runs dry mid-swing and is later refuelled
## DESTROYS the item it was carrying. One item silently vanishes from the
## factory per outage — an item-conservation violation, the class of bug
## that is nearly impossible to diagnose from in-game symptoms.
##
## Sub-cases — the three FUEL-powered inserter tiers all route through the
## same Inserter.tick, so all three are expected to lose the item:
##   1. INSERTER            (reach 1, 20-tick cycle) — outage during WORKING_OUT
##   2. FAST_INSERTER       (reach 1, 10-tick cycle) — outage during WORKING_OUT
##   3. LONG_REACH_INSERTER (reach 2, 30-tick cycle) — outage during WORKING_OUT
##   4. INSERTER — outage during BLOCKED_AT_DEST (cycle_progress pinned at
##      0.5). Sub-cases 1-3 pin down the LOWER end of the phase; this one
##      pins the UPPER end, so a fix that mishandles exactly 0.5 cannot slip
##      through.
##
## Per sub-case shape:
##   place inserter facing E; chests at Inserter.source_tile / dest_tile
##   (NOT hardcoded offsets — reach differs per tier); NOTHING at the fuel
##   port (S edge) so the inserter cannot auto-refuel; tick until the arm is
##   verifiably PART-WAY THROUGH its swing (see MIDSWING_MIN/MAX — state +
##   held alone is not enough, see the constant's docstring); cut the fuel;
##   assert the item and the swing progress survive the outage and the
##   stall; refuel one tick and assert the inserter RESUMES rather than
##   restarting; drain the source; assert source + dest + held == N.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

# Items loaded into the source chest at the start of each sub-case.
const N_ITEMS: int = 5
# Safety bound on the "tick until mid-swing" loop. Deliberately NOT an exact
# tick count — cycle_progress accumulates 1.0/ticks floats, so exact-tick
# scheduling is fragile. We tick TO the state and assert we got there.
const MAX_SWING_TICKS: int = 200
# Target cycle_progress band for "verifiably mid-swing". The arm must have
# actually TRAVELLED, not merely picked up — inserter.gd:223-227 sets
# cycle_progress = 0.0 in the SAME tick it sets WORKING_OUT, so a predicate
# on (state, held) alone always fires at progress 0.0. The band is 0.20
# wide; the largest per-tick increment across the three tiers is 0.10
# (FAST_INSERTER, cycle 10), so no tier can step over it.
#
# MIDSWING_MAX carries a SECOND, load-bearing constraint: it must satisfy
# MIDSWING_MAX + max_inc < DROP_PROGRESS (0.35 + 0.10 = 0.45 < 0.5), so a
# resume tick that advances the swing cannot cross the drop point. Widen it
# to 0.45 and a fix that clamps-then-falls-through to the WORKING_OUT arm
# would step past 0.5 on the resume tick, succeed at _try_drop, and land in
# STATE_WORKING_IN — false-reddening the resume assertions below.
const MIDSWING_MIN: float = 0.15
const MIDSWING_MAX: float = 0.35
# cycle_progress at which WORKING_OUT hands off to the drop attempt. An
# inserter whose drop is refused parks here in BLOCKED_AT_DEST (sub-case 4).
const DROP_PROGRESS: float = 0.5
# Ticks spent stalled with an empty fuel buffer.
const STALL_TICKS: int = 20
# Ticks after refuelling. Slowest tier (long-reach) is 30 ticks/cycle + 1
# IDLE pickup tick = 31 ticks/item; 4 remaining items need ~124. 400 is a
# wide margin for every tier.
const DRAIN_TICKS: int = 400
# Fuel units poked straight into state (bypasses the pull path, same trick
# test_inserter.gd uses). Well above anything DRAIN_TICKS can burn.
const FUEL_UNITS: int = 100

static func test_name() -> String:
	return "inserter fuel conservation (held item + swing progress must survive a mid-swing fuel outage — basic / fast / long-reach / blocked-at-dest)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var tiers: Array = [
		{ "type": Buildings.Type.INSERTER,            "label": "(1) INSERTER" },
		{ "type": Buildings.Type.FAST_INSERTER,       "label": "(2) FAST_INSERTER" },
		{ "type": Buildings.Type.LONG_REACH_INSERTER, "label": "(3) LONG_REACH_INSERTER" },
	]
	for tier in tiers:
		# A non-empty return means the SETUP broke (placement failed, a sanity
		# check on the constructed world failed, never reached the mid-swing
		# band, ...) — that is a broken test, not the bug, so it aborts loudly
		# instead of being folded into `failures` where it could masquerade as
		# a genuine bug finding.
		var fatal: String = _run_tier(parent, failures, int(tier["type"]), str(tier["label"]))
		if fatal != "":
			return { "ok": false, "message": fatal }

	var fatal_blocked: String = _run_blocked_case(parent, failures, "(4) INSERTER blocked-at-dest")
	if fatal_blocked != "":
		return { "ok": false, "message": fatal_blocked }

	if failures.is_empty():
		return { "ok": true, "message": "4 sub-cases pass: held item and swing progress survive a mid-swing fuel outage and the inserter resumes (not restarts) on refuel — basic, fast, long-reach, and blocked-at-dest; full item conservation" }
	# slice(0, 37): worst case is 9 assertions x 3 tier sub-cases (27) + 10 in
	# the blocked-at-dest sub-case = 37. Truncating below the worst case would
	# hide real failures while the count prefix still claimed them.
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 37))] }

# ---------- sub-cases 1-3: outage during WORKING_OUT ----------

## Runs the mid-swing outage scenario for one inserter tier. Appends
## assertion failures to `failures`; returns "" normally, or a fatal setup
## message that aborts the whole test.
static func _run_tier(parent: Node, failures: Array, tier: int, label: String) -> String:
	var world = _make_world(parent)

	if not world.place_building(tier, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return "%s: inserter placement at (10,10) failed" % label
	var ins: Building = world.building_at(Vector2i(10, 10))
	if ins == null:
		_disconnect(world); world.queue_free()
		return "%s: building_at((10,10)) returned null after a successful placement" % label

	# Reach is tier-dependent (basic/fast = 1, long-reach = 2). Ask the
	# building where its ports are rather than hardcoding +/-1 offsets.
	var src_pos: Vector2i = Inserter.source_tile(ins)
	var dst_pos: Vector2i = Inserter.dest_tile(ins)
	var r: int = Inserter.reach(ins)
	if src_pos != Vector2i(10 - r, 10) or dst_pos != Vector2i(10 + r, 10):
		_disconnect(world); world.queue_free()
		return "%s SETUP: with reach=%d and dir=E, source/dest should be %s/%s, got %s/%s" % [label, r, str(Vector2i(10 - r, 10)), str(Vector2i(10 + r, 10)), str(src_pos), str(dst_pos)]

	if not world.place_building(Buildings.Type.CHEST, src_pos, Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return "%s: source chest placement at %s failed" % [label, str(src_pos)]
	if not world.place_building(Buildings.Type.CHEST, dst_pos, Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return "%s: dest chest placement at %s failed" % [label, str(dst_pos)]
	var src_chest: Building = world.building_at(src_pos)
	var dst_chest: Building = world.building_at(dst_pos)
	if src_chest == null or dst_chest == null:
		_disconnect(world); world.queue_free()
		return "%s: building_at() returned null for source %s (%s) or dest %s (%s) after successful placements" % [label, str(src_pos), "null" if src_chest == null else "ok", str(dst_pos), "null" if dst_chest == null else "ok"]

	# The fuel port (Inserter.FUEL_PORT_DIR = DIR_S, rotated by the building
	# dir) must stay EMPTY, otherwise the inserter quietly refuels itself and
	# never enters the outage we are trying to reproduce.
	var fuel_pos: Vector2i = _fuel_port_tile(ins)
	if world.has_building_at(fuel_pos):
		_disconnect(world); world.queue_free()
		return "%s SETUP: fuel port tile %s must be EMPTY so the inserter cannot auto-refuel, but a building is sitting there" % [label, str(fuel_pos)]

	src_chest.state["bag"] = [[Items.Type.WHEAT, N_ITEMS]]
	ins.state["fuel_buffer"] = FUEL_UNITS

	# ---- reach mid-swing by TICKING TO IT (never by exact tick math) ----
	# The arm must have TRAVELLED into MIDSWING_MIN..MAX. Stopping at the
	# first (WORKING_OUT + holding) tick would pin cycle_progress at 0.0,
	# where "resume the swing" and "restart the swing" are observationally
	# identical — which is precisely the distinction this test exists to make.
	var reached: bool = false
	var swing_progress: float = -1.0
	for _i in MAX_SWING_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if int(ins.state.get("state", -1)) != Inserter.STATE_WORKING_OUT:
			continue
		if Inserter.held_item_type(ins) < 0:
			continue
		var p: float = float(ins.state.get("cycle_progress", 0.0))
		if p >= MIDSWING_MIN and p <= MIDSWING_MAX:
			swing_progress = p
			reached = true
			break
	if not reached:
		var end_state: int = int(ins.state.get("state", -1))
		var end_held: int = Inserter.held_item_type(ins)
		var end_prog: float = float(ins.state.get("cycle_progress", 0.0))
		_disconnect(world); world.queue_free()
		return "%s SETUP: never observed STATE_WORKING_OUT + holding + cycle_progress in [%.2f, %.2f] within %d ticks (final state=%d, held=%d where -1 = holding nothing, cycle_progress=%.4f) — TEST SETUP is broken, not the code under test" % [label, MIDSWING_MIN, MIDSWING_MAX, MAX_SWING_TICKS, end_state, end_held, end_prog]

	# ---- cut the fuel mid-swing ----
	ins.state["fuel_buffer"] = 0
	ins.state["fuel_burn_progress"] = 0
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)

	var state_outage: int = int(ins.state.get("state", -1))
	var held_outage: int = Inserter.held_item_type(ins)
	var prog_outage: float = float(ins.state.get("cycle_progress", 0.0))
	# CONTRACT (deliberate, not an oversight): an unfuelled inserter reports
	# STATE_NO_FUEL even mid-swing. This ratifies the state write at
	# inserter.gd:181 that the docstring above calls bug half #1 — the write
	# itself is correct, what is missing is preserving the held item and the
	# swing progress alongside it. A stalled machine must read "NO FUEL", not
	# "Working"; showing a working state on a dead machine is a UX regression,
	# and Session 4's STATE_NO_POWER carries the same semantics. Task 2 must
	# keep this label, not route around it.
	_check(failures, state_outage == Inserter.STATE_NO_FUEL,
		"%s outage tick: state should be STATE_NO_FUEL (%d), got %d" % [label, Inserter.STATE_NO_FUEL, state_outage])
	# NOTE: item types compared as raw ints — Items.name_of(-1) throws, and
	# GDScript evaluates format args even when the assertion passes.
	_check(failures, held_outage == Items.Type.WHEAT,
		"%s outage tick: inserter must STILL hold the wheat it picked up (expected item type %d), got held=%d (-1 = holding nothing / item destroyed)" % [label, Items.Type.WHEAT, held_outage])
	# Passes at HEAD (inserter.gd:181-182 returns before touching progress).
	# Present as a guard against Task 2 regressing it.
	_check(failures, is_equal_approx(prog_outage, swing_progress),
		"%s outage tick: cycle_progress must be preserved across the NO_FUEL transition (was %.4f mid-swing, now %.4f)" % [label, swing_progress, prog_outage])

	# ---- stall unfuelled; the held item must not evaporate ----
	for _i in STALL_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var held_stall: int = Inserter.held_item_type(ins)
	var state_stall: int = int(ins.state.get("state", -1))
	_check(failures, held_stall == Items.Type.WHEAT,
		"%s after %d stalled unfuelled ticks: held item should still be wheat (expected item type %d), got held=%d (-1 = destroyed while stalled)" % [label, STALL_TICKS, Items.Type.WHEAT, held_stall])
	_check(failures, state_stall == Inserter.STATE_NO_FUEL,
		"%s after %d stalled unfuelled ticks: state should still be STATE_NO_FUEL (%d), got %d" % [label, STALL_TICKS, Inserter.STATE_NO_FUEL, state_stall])

	# ---- refuel ONE tick: the defect must show up here, on this exact tick ----
	# Holding an item, the inserter must RESUME the interrupted swing. Pulling
	# a fresh item from the source is the destruction event itself.
	var src_before_refuel: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WHEAT)
	ins.state["fuel_buffer"] = FUEL_UNITS
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	var src_after_refuel: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, src_after_refuel == src_before_refuel,
		"%s refuel tick: the inserter was already holding an item, so it must RESUME the interrupted swing, not start a new pickup — source went %d -> %d (a new item was pulled while one was still in hand — the in-hand item is now destroyed)" % [label, src_before_refuel, src_after_refuel])
	var state_resume: int = int(ins.state.get("state", -1))
	_check(failures, state_resume == Inserter.STATE_WORKING_OUT,
		"%s refuel tick: state should resume to STATE_WORKING_OUT (%d), got %d" % [label, Inserter.STATE_WORKING_OUT, state_resume])
	var prog_resume: float = float(ins.state.get("cycle_progress", 0.0))
	_check(failures, prog_resume >= MIDSWING_MIN and prog_resume <= DROP_PROGRESS,
		"%s refuel tick: resumed cycle_progress should stay within [%.2f, %.2f] — the swing continues from where it stopped, it does not rewind — got %.4f" % [label, MIDSWING_MIN, DROP_PROGRESS, prog_resume])

	# ---- let it drain the source ----
	for _i in DRAIN_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	# ---- THE KEY ASSERTION: item conservation ----
	# Every wheat that entered the system must still be somewhere: in the
	# source chest, in the dest chest, or in the inserter's hand.
	var src_left: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WHEAT)
	var dst_have: int = _bag_count(dst_chest.state.get("bag", []), Items.Type.WHEAT)
	var held_now: int = 1 if Inserter.held_item_type(ins) == Items.Type.WHEAT else 0
	var total: int = src_left + dst_have + held_now
	_check(failures, total == N_ITEMS,
		"%s CONSERVATION (outage taken at cycle_progress %.4f): source(%d) + dest(%d) + held(%d) = %d wheat, expected %d — off by %d (positive = items destroyed, negative = items duplicated) — the refuelled NO_FUEL tick overwrote held_item_buffer via _set_held()" % [label, swing_progress, src_left, dst_have, held_now, total, N_ITEMS, N_ITEMS - total])

	_disconnect(world); world.queue_free()
	return ""

# ---------- sub-case 4: outage during BLOCKED_AT_DEST ----------

## Same outage scenario, but taken at the UPPER end of the swing:
## cycle_progress pinned at exactly DROP_PROGRESS (0.5) with the arm parked
## at the destination. Sub-cases 1-3 only exercise the lower end of the
## phase, so a fix that mishandles exactly 0.5 would pass without this.
##
## To force BLOCKED_AT_DEST we omit the destination chest entirely:
## `_try_drop` returns false when the destination tile holds no building
## (inserter.gd:398-399). A CHEST destination cannot be used to block —
## `_drop_to_chest` (inserter.gd:415-428) unconditionally returns true.
static func _run_blocked_case(parent: Node, failures: Array, label: String) -> String:
	var world = _make_world(parent)

	if not world.place_building(Buildings.Type.INSERTER, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return "%s: inserter placement at (10,10) failed" % label
	var ins: Building = world.building_at(Vector2i(10, 10))
	if ins == null:
		_disconnect(world); world.queue_free()
		return "%s: building_at((10,10)) returned null after a successful placement" % label

	var src_pos: Vector2i = Inserter.source_tile(ins)
	var dst_pos: Vector2i = Inserter.dest_tile(ins)
	if not world.place_building(Buildings.Type.CHEST, src_pos, Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return "%s: source chest placement at %s failed" % [label, str(src_pos)]
	var src_chest: Building = world.building_at(src_pos)
	if src_chest == null:
		_disconnect(world); world.queue_free()
		return "%s: building_at(%s) returned null for the source chest after a successful placement" % [label, str(src_pos)]

	# The destination tile must stay EMPTY — that empty tile IS the blocker.
	if world.has_building_at(dst_pos):
		_disconnect(world); world.queue_free()
		return "%s SETUP: destination tile %s must be EMPTY so _try_drop is refused and the arm parks in BLOCKED_AT_DEST, but a building is sitting there" % [label, str(dst_pos)]
	var fuel_pos: Vector2i = _fuel_port_tile(ins)
	if world.has_building_at(fuel_pos):
		_disconnect(world); world.queue_free()
		return "%s SETUP: fuel port tile %s must be EMPTY so the inserter cannot auto-refuel, but a building is sitting there" % [label, str(fuel_pos)]

	src_chest.state["bag"] = [[Items.Type.WHEAT, N_ITEMS]]
	ins.state["fuel_buffer"] = FUEL_UNITS

	# ---- tick until the arm is parked at the destination, blocked ----
	var reached: bool = false
	for _i in MAX_SWING_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		if int(ins.state.get("state", -1)) == Inserter.STATE_BLOCKED_AT_DEST and Inserter.held_item_type(ins) >= 0:
			reached = true
			break
	if not reached:
		var end_state: int = int(ins.state.get("state", -1))
		var end_held: int = Inserter.held_item_type(ins)
		var end_prog: float = float(ins.state.get("cycle_progress", 0.0))
		_disconnect(world); world.queue_free()
		return "%s SETUP: never observed STATE_BLOCKED_AT_DEST + holding within %d ticks (final state=%d, held=%d where -1 = holding nothing, cycle_progress=%.4f) — TEST SETUP is broken, not the code under test" % [label, MAX_SWING_TICKS, end_state, end_held, end_prog]

	var swing_progress: float = float(ins.state.get("cycle_progress", 0.0))
	if not is_equal_approx(swing_progress, DROP_PROGRESS):
		_disconnect(world); world.queue_free()
		return "%s SETUP: BLOCKED_AT_DEST should pin cycle_progress at exactly %.2f, got %.4f" % [label, DROP_PROGRESS, swing_progress]

	# ---- cut the fuel while blocked ----
	ins.state["fuel_buffer"] = 0
	ins.state["fuel_burn_progress"] = 0
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)

	var state_outage: int = int(ins.state.get("state", -1))
	var held_outage: int = Inserter.held_item_type(ins)
	var prog_outage: float = float(ins.state.get("cycle_progress", 0.0))
	# CONTRACT (deliberate, not an oversight): an unfuelled inserter reports
	# STATE_NO_FUEL even mid-swing. This ratifies the state write at
	# inserter.gd:181 that the docstring above calls bug half #1 — the write
	# itself is correct, what is missing is preserving the held item and the
	# swing progress alongside it. A stalled machine must read "NO FUEL", not
	# "Working"; showing a working state on a dead machine is a UX regression,
	# and Session 4's STATE_NO_POWER carries the same semantics. Task 2 must
	# keep this label, not route around it.
	_check(failures, state_outage == Inserter.STATE_NO_FUEL,
		"%s outage tick: state should be STATE_NO_FUEL (%d), got %d" % [label, Inserter.STATE_NO_FUEL, state_outage])
	_check(failures, held_outage == Items.Type.WHEAT,
		"%s outage tick: inserter must STILL hold the wheat parked at the destination (expected item type %d), got held=%d (-1 = holding nothing / item destroyed)" % [label, Items.Type.WHEAT, held_outage])
	_check(failures, is_equal_approx(prog_outage, DROP_PROGRESS),
		"%s outage tick: cycle_progress must be preserved at the drop point across the NO_FUEL transition (was %.4f, now %.4f)" % [label, DROP_PROGRESS, prog_outage])

	# ---- stall unfuelled ----
	for _i in STALL_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var held_stall: int = Inserter.held_item_type(ins)
	var state_stall: int = int(ins.state.get("state", -1))
	_check(failures, held_stall == Items.Type.WHEAT,
		"%s after %d stalled unfuelled ticks: held item should still be wheat (expected item type %d), got held=%d (-1 = destroyed while stalled)" % [label, STALL_TICKS, Items.Type.WHEAT, held_stall])
	_check(failures, state_stall == Inserter.STATE_NO_FUEL,
		"%s after %d stalled unfuelled ticks: state should still be STATE_NO_FUEL (%d), got %d" % [label, STALL_TICKS, Inserter.STATE_NO_FUEL, state_stall])

	# ---- refuel ONE tick ----
	# The destination is still blocked and the arm is still holding, so the
	# correct resume is straight back to BLOCKED_AT_DEST at progress 0.5 —
	# retry the drop, do NOT rewind and do NOT grab a second item.
	var src_before_refuel: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WHEAT)
	ins.state["fuel_buffer"] = FUEL_UNITS
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	var src_after_refuel: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, src_after_refuel == src_before_refuel,
		"%s refuel tick: the inserter was already holding an item at the destination, so it must RESUME (retry the blocked drop), not start a new pickup — source went %d -> %d (a new item was pulled while one was still in hand — the in-hand item is now destroyed)" % [label, src_before_refuel, src_after_refuel])
	# Deliberately RELAXED to the observable set. Task 2's guard can correctly
	# take either shape: (a) clamp cycle_progress, set STATE_WORKING_OUT and
	# return — which reports WORKING_OUT on this tick and parks in
	# BLOCKED_AT_DEST on the next; or (b) clamp, then fall through to the
	# WORKING_OUT arm, which re-clamps to 0.5, fails _try_drop on the empty
	# destination, and reaches BLOCKED_AT_DEST on this very tick. Both
	# conserve the item; the only difference is a one-tick state label.
	# Pinning this to BLOCKED_AT_DEST would fail shape (a) despite it being
	# correct. The settle assertion below pins the actual intent instead.
	var state_resume: int = int(ins.state.get("state", -1))
	_check(failures, state_resume == Inserter.STATE_BLOCKED_AT_DEST or state_resume == Inserter.STATE_WORKING_OUT,
		"%s refuel tick: item still in hand and destination still empty, so state should resume to STATE_BLOCKED_AT_DEST (%d) or STATE_WORKING_OUT (%d) — anything else means the swing was abandoned or restarted — got %d" % [label, Inserter.STATE_BLOCKED_AT_DEST, Inserter.STATE_WORKING_OUT, state_resume])
	var prog_resume: float = float(ins.state.get("cycle_progress", 0.0))
	_check(failures, is_equal_approx(prog_resume, DROP_PROGRESS),
		"%s refuel tick: resumed cycle_progress should stay pinned at the drop point %.2f — the arm does not rewind to the source — got %.4f" % [label, DROP_PROGRESS, prog_resume])

	# One more tick: whichever shape the fix takes, it must settle back at the
	# blocked destination, still holding the original item.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	var state_settled: int = int(ins.state.get("state", -1))
	_check(failures, state_settled == Inserter.STATE_BLOCKED_AT_DEST,
		"%s one tick after refuel: destination is still empty and the item is still in hand, so the arm must settle back into STATE_BLOCKED_AT_DEST (%d), got %d" % [label, Inserter.STATE_BLOCKED_AT_DEST, state_settled])

	# ---- keep ticking; nothing further may be destroyed ----
	for _i in DRAIN_TICKS:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	# ---- conservation. There is no dest chest, so dest count is always 0. ----
	var src_left: int = _bag_count(src_chest.state.get("bag", []), Items.Type.WHEAT)
	var held_now: int = 1 if Inserter.held_item_type(ins) == Items.Type.WHEAT else 0
	var total: int = src_left + held_now
	_check(failures, total == N_ITEMS,
		"%s CONSERVATION (outage taken at cycle_progress %.4f, blocked at destination): source(%d) + held(%d) = %d wheat, expected %d — off by %d (positive = items destroyed, negative = items duplicated) — the refuelled NO_FUEL tick overwrote held_item_buffer via _set_held()" % [label, swing_progress, src_left, held_now, total, N_ITEMS, N_ITEMS - total])

	_disconnect(world); world.queue_free()
	return ""

# ---------- helpers ----------

static func _make_world(parent: Node) -> Node2D:
	var w = GridWorldScript.new()
	parent.add_child(w)
	# Stone overlay across the test area — chests require STONE/PATH/SOIL_TILLED.
	# x = 7..13 covers long-reach's 2-tile source (8,10) and dest (12,10) as well
	# as the reach-1 tiers' (9,10) / (11,10).
	for x in range(7, 14):
		for y in range(8, 13):
			w.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	return w

## World-space tile of the inserter's fuel input port (canonical S edge,
## rotated by the building's dir via Buildings.world_dir).
static func _fuel_port_tile(ins: Building) -> Vector2i:
	var fuel_dir: int = Buildings.world_dir(ins, Inserter.FUEL_PORT_DIR)
	var fuel_v: Vector2i = Belt.DIR_VECS[fuel_dir]
	return Vector2i(ins.anchor.x + fuel_v.x, ins.anchor.y + fuel_v.y)

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
