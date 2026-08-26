extends RefCounted

## Audit finding #26 — "Belt two-pass tick semantics have no dedicated test".
##
## This is a TEST-GAP finding. `belt.gd` is correct today; nothing here fixes a
## defect. What this file does is make a documented determinism law falsifiable.
##
## THE LAW (CONVENTIONS.md:142, "Tick determinism"):
##   "Two-pass tick (Belt) lives in `Buildings.tick_one` / `post_tick_one`.
##    Don't add hidden cross-building reads inside Pass 1."
## and belt.gd:10-15, which is the mechanism the two passes actually promise:
##   Pass 1 (shift):   each belt shifts items forward WITHIN ITS OWN SLOTS.
##   Pass 2 (handoff): each belt's FRONT slot tries to push into the next
##                     consumer.
##
## Re-derived against this commit:
##   Pass 1  `Belt.tick`       belt.gd:54-61  — reads/writes `b.state["slots"]`
##                                              and NOTHING else. Self only.
##   Pass 2  `Belt.post_tick`  belt.gd:64-88  — the only place a belt touches a
##                                              neighbour. No-neighbour early
##                                              return belt.gd:73-74,
##                                              opposite-facing guard belt.gd:82,
##                                              handoff clear belt.gd:87.
##   Advance gate `Belt.is_advance_tick` belt.gd:49-50; TICKS_PER_SLOT = 4
##                                       (belt.gd:22), SLOTS_PER_TILE = 4 (:21).
##   Dispatch    `Buildings.tick_one` buildings.gd:1081 /
##               `Buildings.post_tick_one` buildings.gd:1129, driven by the two
##               loops in `GridWorld._on_tick` grid_world.gd:694-697.
##
## WHY THIS WENT UNTESTED, AND WHY EVERY ASSERTION BELOW IS AN EXACT EQUALITY.
## Belts appear in the suite only as incidental transport, behind LOWER BOUNDS:
## test_wheat_to_flour.gd:77 (`flour < 7`), test_thresher_prefer_dir.gd:77-78
## (`>= 9` grain / straw), test_thresher_rotation.gd:127/132 (`< 9`). A belt that
## advanced two slots per tick everywhere, or DUPLICATED an item at every
## boundary, makes transport faster or richer — and passes all of them. The
## exact-count suites that could have caught it use no belts at all
## (test_thresher_multioutput.gd:28 pre-loads `in_buffer` directly). A lower
## bound is what let this gap exist, so no `>=` threshold appears in this file.
##
## ─────────────────────────────────────────────────────────────────────────────
## ⚠ WHAT #26's OWN FIX TEXT GETS WRONG — MEASURED, AND DELIBERATELY NOT ENCODED
## ─────────────────────────────────────────────────────────────────────────────
## #26 prescribes asserting that the item "occupies exactly one expected slot
## index/belt (12 slots total path)". It is not a 12-slot path. Pass 1 runs
## BEFORE Pass 2 on the same tick, so the advance tick that carries an item into
## its belt's FRONT slot is the same tick on which Pass 2 hands that item across
## the boundary: the item moves TWO global slots that tick, and a front slot is
## never a resting position while a handoff is available. Over a three-belt line
## the resting positions are
##
##     0, 1, 2, 4, 5, 6, 8, 9, 10, 11        (global slots 3 and 7 skipped)
##
## — 11 slots crossed in 9 advance ticks, ten resting positions, not twelve. A
## test written literally to #26's prescription FAILS against correct code.
##
## That sequence is DERIVED from the two passes above, not copied from a run:
## Pass 1 advances one slot, Pass 2 then empties the front slot into the next
## belt's slot 0. The exception is the end of the line, where `post_tick`
## early-returns for want of a neighbour (belt.gd:73-74) and the item does park
## on a front slot — which is why case (1) asserts BOTH that slots 3 and 7 are
## never occupied and that slot 11 is.
##
## #26 also names the wrong double-move. "An item entering `next_slots[0]` in
## Pass 2 must not move again that tick" is TRUE and holds: the receiving belt's
## Pass 1 has already run. The double-move that does happen is the other one,
## slot N-2 → front (Pass 1) → next belt's slot 0 (Pass 2), and it is a designed
## consequence of the documented pass order, not a defect: every belt completes
## Pass 1 before any belt begins Pass 2, so it is deterministic and independent
## of insertion order.
##
## REPORTED, NOT ENCODED: belt.gd:6-7's prose — "Items advance one slot per
## 'belt tick'" — is therefore a false simplification of belt.gd:10-12's own
## mechanism at every belt boundary. This suite asserts the MECHANISM (the two
## passes), which is the load-bearing law; it does not assert the prose sentence,
## in either direction. Correcting that sentence is a doc-drift question for the
## tracker, not something a test should settle.
##
## TICK PHASE. `is_advance_tick()` keys off the GLOBAL `TickSystem.current_tick`,
## so these cases depend on tick PHASE, not merely on tick count. The runner does
## reset it: test_runner.gd:145 sets `TickSystem.current_tick = 0` before every
## suite. Each case below ALSO resets it to 0 explicitly, so no case inherits a
## phase from the one before it and none depends on the runner's reset staying
## where it is. At phase 0, world ticks 4, 8, 12, ... are the advance ticks.
##
## REACHABILITY CONTROLS. A belt that never advances leaves its item at slot 0 —
## which is exactly the expected position at tick 0, and exactly the state in
## which "no handoff occurred" and "the ring conserved N items" are both
## trivially true. Every case therefore carries an assertion a dead belt FAILS,
## marked `REACHABILITY CONTROL`:
##   (1)  the item must arrive at the far end of the line (global slot 11);
##   (2a) the four items must settle on the HEAD slots {8,9,10,11}, not on the
##        insertion-end slots {0,1,2,3};
##   (3b) an entire extra sub-case whose only job is to prove a handoff CAN
##        happen between these two tiles, so (3a)'s silence means the guard
##        fired rather than that nothing ever moves;
##   (4)  every one of the ring's twelve non-front slots must be visited.
##
## ─────────────────────────────────────────────────────────────────────────────
## NAMED GAP — machine-adjacent belt TIMING is deliberately NOT covered here.
## ─────────────────────────────────────────────────────────────────────────────
## Audit #17 ("Pass-1 belt mutations make item timing depend on building
## insertion order") is LIVE and UNDECIDED. Its mechanism needs a MACHINE: the
## processors run inside Pass 1 (`Processor.tick` reaches `Belt.try_pull_matching`
## at processor.gd:195 and `Belt.try_insert` at processor.gd:349/373, dispatched
## from `Buildings.tick_one`), so a machine that iterates before its output belt
## inserts into slot 0 and the belt's own Pass-1 shift moves it again the same
## tick, while a machine that iterates after does not.
##
## A BELTS-ONLY WORLD CANNOT EXHIBIT #17 — verified, not assumed: Pass 1 for a
## belt touches only its own `slots` array, so with nothing but belts in the
## insertion-ordered `buildings` dict there is no cross-building read in Pass 1
## at all. That is why this suite is belts-only, and it is also why this suite
## does not decide #17.
##
## #17's own fix option (b) prescribes "a regression test placing mill-then-belt
## and belt-then-mill asserting the exact per-order slot timing". That test is
## deliberately NOT written here: it would ENCODE the disagreement rather than
## test the law, and if #17 resolves the other way (option (a): move machine↔belt
## exchanges into Pass 2) it would have to be DELETED rather than amended. Leave
## the hole visible. Do not fill it with a characterization test that pins
## whatever today's insertion order happens to produce.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

## Resting positions of one item on a three-belt DIR_E line, by advance-tick
## index. Derived from the two passes — see the header. Index 0 is the state
## before any tick; the item parks on the last entry once it reaches the end.
const EXPECTED_PATH: Array = [0, 1, 2, 4, 5, 6, 8, 9, 10, 11]

static func test_name() -> String:
	return "belt two-pass tick (#26: pass-1 shift, pass-2 handoff, conserved, guarded)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_single_item_advance(parent, failures)
	_case_jam_compression(parent, failures)
	_case_opposite_facing_guard(parent, failures)
	_case_conservation_ring(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": " | ".join(failures) }

## (1) SINGLE-ITEM ADVANCE. Three belts in a line, all DIR_E, one item, ticks
## driven ONE AT A TIME. After every world tick the item must occupy EXACTLY ONE
## slot, and that slot must be the one EXPECTED_PATH names for the number of
## advance ticks that have fired.
##
## What this shape catches that a lower bound cannot:
##   - a double-shift inside Pass 1 (the item would be at global 2 after one
##     advance tick, and off the front of the path from there on);
##   - a Pass 2 that fires without Pass 1, or twice;
##   - the front-slot assertions below pin WHICH mechanism produced the skip.
##     Global slots 3 and 7 are front slots with a neighbour: an item reaching
##     them in Pass 1 must be gone by the end of the same tick. Global slot 11
##     is a front slot WITHOUT a neighbour: the item must park there. Same slot
##     index within its belt, opposite outcome, and the only difference is the
##     Pass-2 neighbour check at belt.gd:73-74.
static func _case_single_item_advance(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	TickSystem.current_tick = 0

	var belts: Array = []
	for x in 3:
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
		if not world.place_building(Buildings.Type.BELT, Vector2i(x, 0), Belt.DIR_E):
			_check(failures, false, "(1) belt placement failed at x=%d" % x)
			_cleanup(world)
			return
		belts.append(world.building_at(Vector2i(x, 0)))

	var end_slot: int = 3 * Belt.SLOTS_PER_TILE - 1          # 11
	_check(failures, Belt.try_insert(belts[0], Items.Type.GRAIN),
		"(1) try_insert refused an empty belt")
	_check(failures, _occupied(belts) == [EXPECTED_PATH[0]],
		"(1) item should start at global slot %d, got %s" % [EXPECTED_PATH[0], str(_occupied(belts))])

	# Front slots that have a neighbour to hand off to. An item must never be
	# resting on one of these when a tick ends.
	var transient_fronts: Array = [Belt.SLOTS_PER_TILE - 1, 2 * Belt.SLOTS_PER_TILE - 1]   # 3, 7
	var advances: int = 0
	for _t in 80:
		TickSystem.current_tick += 1
		var was_advance: bool = Belt.is_advance_tick()
		TickSystem.tick.emit(TickSystem.current_tick)
		if was_advance:
			advances += 1
		# The expected position is indexed by WORLD ticks over TICKS_PER_SLOT,
		# NOT by `advances`. Deriving it from `Belt.is_advance_tick()` would make
		# this assertion blind to that very function: mutate the gate to `return
		# true` and the item advances every tick, `advances` counts every tick,
		# and the two stay in agreement all the way down. Measured — that
		# mutation left this assertion silent and only the control below caught
		# it. Phase is 0 here (reset above), so after `t` world ticks exactly
		# `t / TICKS_PER_SLOT` advance ticks have fired.
		var due: int = TickSystem.current_tick / Belt.TICKS_PER_SLOT
		var expected: int = int(EXPECTED_PATH[mini(due, EXPECTED_PATH.size() - 1)])
		var occ: Array = _occupied(belts)
		_check_once(failures, "(1)path",
			occ == [expected],
			"(1) tick %d (%d advance ticks): expected exactly [%d], got %s" \
				% [TickSystem.current_tick, advances, expected, str(occ)])
		# DIAGNOSTIC, NOT LOAD-BEARING — said plainly so nobody trusts it for more
		# than it does. EXPECTED_PATH contains neither 3 nor 7, so any state this
		# rejects is a state "(1)path" already rejects: it is redundant BY
		# CONSTRUCTION and no mutation in the pass that shipped this file reddened
		# it on its own. It stays because it turns a numeric mismatch into a
		# named diagnosis. Do not count it as coverage.
		_check_once(failures, "(1)front",
			not (occ.size() == 1 and int(occ[0]) in transient_fronts),
			"(1) item rested on front slot %s at tick %d — Pass 2 did not hand it across in the same tick as the Pass-1 shift" \
				% [str(occ), TickSystem.current_tick])

	# REACHABILITY CONTROL. A belt that never advances leaves the item at global
	# slot 0 — which IS EXPECTED_PATH[0], so every per-tick equality above would
	# be satisfied at every step by a completely dead belt. This is the
	# assertion a dead belt cannot pass.
	_check(failures, advances == 20,
		"(1) control: expected 20 advance ticks in 80 world ticks, counted %d" % advances)
	_check(failures, _occupied(belts) == [end_slot],
		"(1) REACHABILITY CONTROL: item never reached the end of the line (global slot %d), got %s — belts are not advancing" \
			% [end_slot, str(_occupied(belts))])
	_cleanup(world)

## (2) JAM / COMPRESSION. Three-belt line with NO consumer past the head
## (`post_tick` early-returns at belt.gd:73-74 when the next tile is empty).
##
## (2a) compression: four items inserted one per advance tick, then left to run.
## They must settle on the four HEAD slots and stop. Exact set, exact count.
## (2b) saturation: insert every tick until the line is full. The number of
## items on the belts must equal the number of accepted inserts after EVERY
## insert and after EVERY tick — never fewer (vanished), never more (duplicated).
static func _case_jam_compression(parent: Node, failures: Array) -> void:
	# --- (2a) items compress onto the head slots ---
	var world = GridWorldScript.new()
	parent.add_child(world)
	TickSystem.current_tick = 0

	var belts: Array = []
	for x in 3:
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
		if not world.place_building(Buildings.Type.BELT, Vector2i(x, 0), Belt.DIR_E):
			_check(failures, false, "(2a) belt placement failed at x=%d" % x)
			_cleanup(world)
			return
		belts.append(world.building_at(Vector2i(x, 0)))

	var inserted: int = 0
	for _t in 240:
		TickSystem.current_tick += 1
		var was_advance: bool = Belt.is_advance_tick()
		TickSystem.tick.emit(TickSystem.current_tick)
		if was_advance and inserted < 4:
			if Belt.try_insert(belts[0], Items.Type.GRAIN):
				inserted += 1
		_check_once(failures, "(2a)conserve",
			_occupied(belts).size() == inserted,
			"(2a) conservation broke at tick %d: %d items inserted, %d on the belts" \
				% [TickSystem.current_tick, inserted, _occupied(belts).size()])

	_check(failures, inserted == 4, "(2a) expected 4 accepted inserts, got %d" % inserted)
	# REACHABILITY CONTROL. A dead belt holds these four at {0,1,2,3} — the
	# INSERTION end. Requiring the HEAD end is what a dead belt fails.
	_check(failures, _occupied(belts) == [8, 9, 10, 11],
		"(2a) REACHABILITY CONTROL: items must compress onto the head slots [8, 9, 10, 11], got %s" \
			% str(_occupied(belts)))
	_cleanup(world)

	# --- (2b) saturation, with conservation checked on both sides of every tick ---
	var world2 = GridWorldScript.new()
	parent.add_child(world2)
	TickSystem.current_tick = 0

	var belts2: Array = []
	for x in 3:
		world2.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
		if not world2.place_building(Buildings.Type.BELT, Vector2i(x, 0), Belt.DIR_E):
			_check(failures, false, "(2b) belt placement failed at x=%d" % x)
			_cleanup(world2)
			return
		belts2.append(world2.building_at(Vector2i(x, 0)))

	var accepted: int = 0
	for _t in 400:
		if Belt.try_insert(belts2[0], Items.Type.GRAIN):
			accepted += 1
		_check_once(failures, "(2b)conserve-insert",
			_occupied(belts2).size() == accepted,
			"(2b) conservation broke after an insert at tick %d: %d accepted, %d on the belts" \
				% [TickSystem.current_tick, accepted, _occupied(belts2).size()])
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(2b)conserve-tick",
			_occupied(belts2).size() == accepted,
			"(2b) conservation broke across tick %d: %d accepted, %d on the belts" \
				% [TickSystem.current_tick, accepted, _occupied(belts2).size()])

	var capacity: int = 3 * Belt.SLOTS_PER_TILE              # 12
	_check(failures, accepted == capacity,
		"(2b) a jammed 3-belt line must accept exactly %d items, accepted %d" % [capacity, accepted])
	_check(failures, _occupied(belts2).size() == capacity,
		"(2b) expected %d items on the jammed line, got %d" % [capacity, _occupied(belts2).size()])
	_check(failures, _type_count(belts2, Items.Type.GRAIN) == capacity,
		"(2b) every occupied slot must still hold GRAIN, got %d of %d" \
			% [_type_count(belts2, Items.Type.GRAIN), capacity])
	_check(failures, not Belt.try_insert(belts2[0], Items.Type.GRAIN),
		"(2b) a full belt accepted a %dth item" % (capacity + 1))
	_cleanup(world2)

## (3) OPPOSITE-FACING GUARD (belt.gd:82).
##
## (3a) Two belts facing each other must NEVER hand off, in either direction —
## asserted every tick, not only at the end. Note the contrast with case (1):
## here the items DO rest on their belts' front slots, because the guard, not
## the absence of a neighbour, is what stops the handoff.
## (3b) REACHABILITY CONTROL, and the reason it is a separate sub-case: the same
## two tiles with the second belt turned to DIR_E. The handoff MUST happen. With
## (3b) absent, (3a) passes just as well against a belt that never hands off to
## anyone, which is a different program.
static func _case_opposite_facing_guard(parent: Node, failures: Array) -> void:
	# --- (3a) the guard ---
	var world = GridWorldScript.new()
	parent.add_child(world)
	TickSystem.current_tick = 0

	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.BELT, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_W)
	var west: Building = world.building_at(Vector2i(0, 0))
	var east: Building = world.building_at(Vector2i(1, 0))
	if west == null or east == null:
		_check(failures, false, "(3a) belt placement failed")
		_cleanup(world)
		return

	_check(failures, Belt.try_insert(west, Items.Type.GRAIN), "(3a) west belt refused GRAIN")
	_check(failures, Belt.try_insert(east, Items.Type.FLOUR), "(3a) east belt refused FLOUR")

	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(3a)east-west",
			_type_count([west], Items.Type.FLOUR) == 0,
			"(3a) FLOUR crossed westward at tick %d — the opposite-facing guard did not fire" \
				% TickSystem.current_tick)
		_check_once(failures, "(3a)west-east",
			_type_count([east], Items.Type.GRAIN) == 0,
			"(3a) GRAIN crossed eastward at tick %d — the opposite-facing guard did not fire" \
				% TickSystem.current_tick)

	var front: int = Belt.SLOTS_PER_TILE - 1
	# Each item must be parked on its OWN belt's front slot: proof that the belts
	# advanced and that the guard, not inertia, is what stopped the handoff.
	_check(failures, _occupied([west]) == [front],
		"(3a) REACHABILITY CONTROL: GRAIN must sit alone on the west belt's front slot %d, got %s" \
			% [front, str(_occupied([west]))])
	_check(failures, _occupied([east]) == [front],
		"(3a) REACHABILITY CONTROL: FLOUR must sit alone on the east belt's front slot %d, got %s" \
			% [front, str(_occupied([east]))])
	_check(failures, _occupied([west, east]).size() == 2,
		"(3a) expected exactly 2 items across the pair, got %d" % _occupied([west, east]).size())
	_cleanup(world)

	# --- (3b) the same geometry, guard not applicable: handoff MUST occur ---
	var world2 = GridWorldScript.new()
	parent.add_child(world2)
	TickSystem.current_tick = 0

	world2.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world2.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world2.place_building(Buildings.Type.BELT, Vector2i(0, 0), Belt.DIR_E)
	world2.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_E)
	var src: Building = world2.building_at(Vector2i(0, 0))
	var dst: Building = world2.building_at(Vector2i(1, 0))
	if src == null or dst == null:
		_check(failures, false, "(3b) belt placement failed")
		_cleanup(world2)
		return

	_check(failures, Belt.try_insert(src, Items.Type.GRAIN), "(3b) source belt refused GRAIN")
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		_check_once(failures, "(3b)count",
			_occupied([src, dst]).size() == 1,
			"(3b) item count changed at tick %d: %d items on a two-belt line that started with 1" \
				% [TickSystem.current_tick, _occupied([src, dst]).size()])

	var pair_end: int = 2 * Belt.SLOTS_PER_TILE - 1
	_check(failures, _occupied([src, dst]) == [pair_end],
		"(3b) REACHABILITY CONTROL: a DIR_E → DIR_E pair must hand off and park the item at global slot %d, got %s" \
			% [pair_end, str(_occupied([src, dst]))])
	_cleanup(world2)

## (4) CONSERVATION RING. Four belts in a 2×2 square — (0,0) E → (1,0) S →
## (1,1) W → (0,1) N → (0,0) — a closed loop with no source and no sink. Five
## items of five distinct types. Over several hundred ticks the occupied-slot
## count must stay EXACTLY five, and the multiset of item types must stay exactly
## the one it started with, so a type cannot be silently rewritten either.
static func _case_conservation_ring(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	TickSystem.current_tick = 0

	# Ring order matters: index i hands off to index i+1.
	var cells: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	var dirs: Array = [Belt.DIR_E, Belt.DIR_S, Belt.DIR_W, Belt.DIR_N]
	var ring: Array = []
	for i in cells.size():
		world.set_overlay(cells[i], Terrain.Overlay.STONE)
		if not world.place_building(Buildings.Type.BELT, cells[i], dirs[i]):
			_check(failures, false, "(4) belt placement failed at %s" % str(cells[i]))
			_cleanup(world)
			return
		ring.append(world.building_at(cells[i]))

	# Five items, spread around the loop, one distinct type each.
	var seeds: Array = [
		[0, Items.Type.GRAIN],
		[3, Items.Type.FLOUR],
		[6, Items.Type.WHEAT],
		[9, Items.Type.STRAW],
		[12, Items.Type.COAL],
	]
	for seed in seeds:
		var g: int = int(seed[0])
		ring[g / Belt.SLOTS_PER_TILE].state["slots"][g % Belt.SLOTS_PER_TILE] = int(seed[1])

	var item_count: int = seeds.size()
	var ring_slots: int = ring.size() * Belt.SLOTS_PER_TILE   # 16
	var expected_types: Array = _types(ring)
	expected_types.sort()
	_check(failures, expected_types.size() == item_count,
		"(4) setup: expected %d seeded items, found %d" % [item_count, expected_types.size()])

	# Visited is recorded from POST-TICK observations only. Front slots are
	# transient while a handoff is available (see case (1)), so the control below
	# asks only about the twelve non-front slots.
	var visited: Array = []
	for _i in ring_slots:
		visited.append(false)

	for _t in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
		var occ: Array = _occupied(ring)
		for g in occ:
			visited[g] = true
		_check_once(failures, "(4)count",
			occ.size() == item_count,
			"(4) ring holds %d items at tick %d, must hold exactly %d" \
				% [occ.size(), TickSystem.current_tick, item_count])
		var types: Array = _types(ring)
		types.sort()
		_check_once(failures, "(4)types",
			types == expected_types,
			"(4) item types changed at tick %d: %s, expected %s" \
				% [TickSystem.current_tick, str(types), str(expected_types)])

	# REACHABILITY CONTROL. A ring whose belts never advance conserves five items
	# perfectly and forever, and would satisfy every assertion above. Requiring
	# every non-front slot to have been occupied at some point is what separates
	# "circulating" from "frozen".
	var unvisited: Array = []
	for g in ring_slots:
		if g % Belt.SLOTS_PER_TILE == Belt.SLOTS_PER_TILE - 1:
			continue                                          # front slot; transient
		if not visited[g]:
			unvisited.append(g)
	_check(failures, unvisited.is_empty(),
		"(4) REACHABILITY CONTROL: ring slots %s were never occupied — items are not circulating" \
			% str(unvisited))
	_cleanup(world)

# ---------- helpers ----------

## Global slot indices occupied across `belts`, ascending. The global index of
## belt `i` slot `s` is `i * SLOTS_PER_TILE + s`.
static func _occupied(belts: Array) -> Array:
	var out: Array = []
	for i in belts.size():
		var slots: Array = belts[i].state["slots"]
		for s in Belt.SLOTS_PER_TILE:
			if int(slots[s]) >= 0:
				out.append(i * Belt.SLOTS_PER_TILE + s)
	return out

## Item types present across `belts`, in global slot order.
static func _types(belts: Array) -> Array:
	var out: Array = []
	for b in belts:
		for s in b.state["slots"]:
			if int(s) >= 0:
				out.append(int(s))
	return out

static func _type_count(belts: Array, item_type: int) -> int:
	var n: int = 0
	for t in _types(belts):
		if t == item_type:
			n += 1
	return n

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Per-tick assertions run hundreds of times. `key` groups them so only the
## FIRST breach of each distinct assertion is reported — one broken belt must
## not bury the rest of the report under four hundred copies of one message.
static func _check_once(failures: Array, key: String, condition: bool, label: String) -> void:
	if condition:
		return
	for existing in failures:
		if String(existing).begins_with(key):
			return
	failures.append("%s %s" % [key, label])

static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
