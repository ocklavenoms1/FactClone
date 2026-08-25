extends RefCounted

## Inserter drop into a FULL chest (audit finding #19).
##
## `Chest` bounds itself in AGGREGATE: `TOTAL_CAPACITY = 2400` items across
## every bag entry, no per-type cap (chest.gd:9-18). `Chest.try_insert`
## (chest.gd:77-81) is the enforcement point — `free_capacity(b) < count`
## refuses — and every other producer goes through it:
##
##   processor.gd:345, 360   harvester.gd:83   mining_drill.gd:252
##
## `Inserter._drop_to_chest` did not. It reimplemented the top-up-or-append
## body inline against `chest.state.get("bag", [])` and returned `true`
## unconditionally, which has two consequences the state machine cannot see:
##
##   (a) the bag grows past 2400 without bound, and
##   (b) `STATE_BLOCKED_AT_DEST` is unreachable for a chest destination —
##       `_try_drop` (inserter.gd:619-638) has no other gate on that branch,
##       so the WORKING_OUT arm always takes the success path.
##
## The intended backpressure — inserter stalls, upstream belt backs up — is
## therefore impossible against a chest, and the in-world fill bar
## (chest.gd:157) clamps at 100% while the real count keeps climbing.
##
## ⚠ WHAT THIS IS NOT. Measured, not inherited: items are neither
## DUPLICATED nor DESTROYED on this path. One item leaves the source and one
## arrives in the destination, so the world total is conserved — case (3)
## asserts exactly that, and it holds before and after the fix. The defect
## is unbounded storage past a cap the rest of the codebase enforces. The
## one destruction path is case (7), and it needs a chest whose state has no
## "bag" key at all.
##
## Cases:
##   (1) REACHABILITY — with room in the destination, the rig delivers.
##       Proves the ticks reach `_drop_to_chest` before (2) reads silence
##       as a result.
##   (2) BEHAVIOURAL — destination at TOTAL_CAPACITY: the total must stay
##       at TOTAL_CAPACITY, the source must not drain, and the arm must
##       park in STATE_BLOCKED_AT_DEST.
##   (3) CONSERVATION — the same run, item-accounted. Invariant, recorded
##       because it is the evidence behind the severity call.
##   (4) UNIT — at the cap, `_drop_to_chest` returns false and adds nothing.
##   (5) UNIT — one below the cap it returns true and lands exactly one, so
##       the fix is a cap and not a blanket refusal.
##   (6) RETENTION — per-STACK caps are still not enforced. The comment the
##       fix removed claimed this as the design decision; it is Chest's
##       decision, it survives via `_bag_add`, and it is asserted here
##       rather than restated in a comment nothing can check.
##   (7) A chest whose state carries no "bag" key. `Dictionary.get` hands
##       back the DEFAULT array, so the old body appended into a temporary
##       and reported success — the item was destroyed. Reachable through
##       `Building.from_dict` (building.gd:49-58), which passes a save's
##       `"s"` dictionary straight through with no shape repair.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

## The item the rig moves. Anything with a max_stack below TOTAL_CAPACITY
## works; (6) reads its max_stack rather than pinning a number.
const CARGO: int = Items.Type.COAL

static func test_name() -> String:
	return "inserter into a full chest (aggregate cap enforced, arm blocks, per-stack cap still waived, bagless chest not swallowed)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var cap: int = Chest.TOTAL_CAPACITY

	# ===========================================================================
	# (1) REACHABILITY. Same rig as (2) with an EMPTY destination. A mis-aimed
	# inserter, an unfuelled one, or a chest the pickup cannot read would all
	# produce (2)'s "nothing was overfilled" reading without the defect being
	# fixed — the absence-equals-success shape. This case is what makes (2)'s
	# silence mean something.
	#
	#   chest(8,10) --[inserter(9,10) facing E]--> chest(10,10)
	# ===========================================================================
	var rig_a: Dictionary = _build_rig(parent)
	if not rig_a.get("ok", false):
		return { "ok": false, "message": str(rig_a.get("message", "rig setup failed")) }
	var world_a = rig_a["world"]
	var src_a: Building = rig_a["src"]
	var dst_a: Building = rig_a["dst"]
	var ins_a: Building = rig_a["ins"]

	src_a.state["bag"] = [[CARGO, 50]]
	dst_a.state["bag"] = []
	_run_ticks(100)

	var delivered: int = Chest.total_items(dst_a)
	_check(failures, delivered > 0,
		"(1) REACHABILITY: an empty destination received 0 items in 100 ticks — the rig never reaches _drop_to_chest, so (2) proves nothing")
	_check(failures, Chest.total_items(src_a) == 50 - delivered,
		"(1) REACHABILITY: source should have dropped by exactly the %d delivered, holds %d of 50"
			% [delivered, Chest.total_items(src_a)])
	_teardown(world_a)

	# ===========================================================================
	# (2) BEHAVIOURAL OVERFILL — the finding's title, reproduced. The
	# destination starts at exactly TOTAL_CAPACITY, which is the state
	# `Chest.tick` and `Chest.try_insert` both treat as "no room".
	# ===========================================================================
	var rig_b: Dictionary = _build_rig(parent)
	if not rig_b.get("ok", false):
		return { "ok": false, "message": str(rig_b.get("message", "rig setup failed")) }
	var world_b = rig_b["world"]
	var src_b: Building = rig_b["src"]
	var dst_b: Building = rig_b["dst"]
	var ins_b: Building = rig_b["ins"]

	# Fill the destination to the cap through Chest's own API, so the
	# premise is the module's notion of full and not the test's.
	dst_b.state["bag"] = []
	Chest._bag_add(dst_b.state["bag"], Items.Type.IRON_ORE, cap)
	src_b.state["bag"] = [[CARGO, 50]]

	if Chest.free_capacity(dst_b) != 0:
		_teardown(world_b)
		return { "ok": false, "message": "setup: destination should have 0 free capacity, has %d" % Chest.free_capacity(dst_b) }

	var total_before: int = Chest.total_items(src_b) + Chest.total_items(dst_b)

	# 200 ticks = 10 basic-inserter cycles (20 ticks each).
	_run_ticks(200)

	var dst_total: int = Chest.total_items(dst_b)
	var src_total: int = Chest.total_items(src_b)
	var arm_state: int = int(ins_b.state.get("state", -1))
	# One item is legitimately IN FLIGHT: the arm picks up, swings out, and
	# only then discovers the destination is full, so it parks holding it.
	# `held_item_buffer` holds a count in {0, 1} by construction
	# (inserter.gd:276), which is the bound the source-drain check uses.
	var in_flight: int = _held_count(ins_b)

	_check(failures, dst_total == cap,
		"(2) OVERFILL: destination holds %d items against TOTAL_CAPACITY %d — the aggregate cap was bypassed by %d"
			% [dst_total, cap, dst_total - cap])
	_check(failures, src_total + in_flight == 50,
		"(2) OVERFILL: a full destination must drain the source by no more than the one item on the arm; source holds %d with %d in flight, of 50"
			% [src_total, in_flight])
	_check(failures, in_flight <= 1,
		"(2) OVERFILL: the arm may hold at most 1 item, holds %d" % in_flight)
	_check(failures, arm_state == Inserter.STATE_BLOCKED_AT_DEST,
		"(2) BLOCKED_AT_DEST: arm is in state %d after 200 ticks against a full chest, expected STATE_BLOCKED_AT_DEST (%d)"
			% [arm_state, Inserter.STATE_BLOCKED_AT_DEST])

	# ===========================================================================
	# (3) CONSERVATION — the severity evidence, not a regression guard. It
	# holds on both sides of the fix. The finding asserts "item duplication
	# or destruction depending on which side of the bypass you land on"; if
	# either were true of THIS path, this assertion would fail before the fix.
	# It does not. Held items count: the arm can be carrying one mid-cycle.
	# ===========================================================================
	var total_after: int = src_total + dst_total + in_flight
	_check(failures, total_after == total_before,
		"(3) CONSERVATION: %d items before, %d after (%d in chests + %d on the arm) — the drop path neither duplicates nor destroys"
			% [total_before, total_after, src_total + dst_total, in_flight])

	# Recovery, so (2) pins a CAP and not a permanent wedge: free one slot
	# and the parked arm must deliver within a cycle or two.
	Chest._bag_remove(dst_b.state["bag"], Items.Type.IRON_ORE, 5)
	_run_ticks(120)
	_check(failures, Chest.total_items(dst_b) > cap - 5,
		"(2) RECOVERY: with 5 slots freed the blocked arm delivered nothing in 120 ticks — that is a wedge, not backpressure (total %d)"
			% Chest.total_items(dst_b))
	_check(failures, Chest.total_items(dst_b) <= cap,
		"(2) RECOVERY: after refilling the freed room the total ran to %d, past TOTAL_CAPACITY %d"
			% [Chest.total_items(dst_b), cap])
	_teardown(world_b)

	# ===========================================================================
	# (4) UNIT — at the cap, refuse. The helper is called directly so the
	# verdict cannot be blamed on fuel, aim, or tick counts.
	# ===========================================================================
	var full_chest: Building = Chest.make(Vector2i(0, 0))
	Chest._bag_add(full_chest.state["bag"], Items.Type.IRON_ORE, cap)
	var over: bool = Inserter._drop_to_chest(full_chest, CARGO)
	_check(failures, not over,
		"(4) _drop_to_chest must return FALSE at TOTAL_CAPACITY (%d); returning true is what makes BLOCKED_AT_DEST unreachable" % cap)
	_check(failures, Chest.total_items(full_chest) == cap,
		"(4) a refused drop must add nothing: total is %d, expected %d" % [Chest.total_items(full_chest), cap])

	# ===========================================================================
	# (5) UNIT — one below the cap, accept exactly one. Without this, (4)
	# passes just as happily against a body that refuses every drop.
	# ===========================================================================
	var nearly: Building = Chest.make(Vector2i(0, 0))
	Chest._bag_add(nearly.state["bag"], Items.Type.IRON_ORE, cap - 1)
	var last_one: bool = Inserter._drop_to_chest(nearly, CARGO)
	_check(failures, last_one,
		"(5) _drop_to_chest must ACCEPT the item that fills the chest exactly (%d of %d used)" % [cap - 1, cap])
	_check(failures, Chest.total_items(nearly) == cap,
		"(5) the accepted drop must land exactly one item: total is %d, expected %d" % [Chest.total_items(nearly), cap])
	_check(failures, not Inserter._drop_to_chest(nearly, CARGO),
		"(5) the very next drop must be refused — the chest is now at %d" % cap)

	# ===========================================================================
	# (6) RETENTION — the removed comment's real content. Chest deliberately
	# IGNORES Items.max_stack_of (chest.gd:9): the bag holds ONE entry per
	# type at any count, and only the aggregate is bounded. Delegating to
	# Chest.try_insert routes through _bag_add, which tops up in place, so
	# the decision is preserved rather than restated. This asserts it; the
	# comment could not.
	# ===========================================================================
	var stacky: Building = Chest.make(Vector2i(0, 0))
	var max_stack: int = Items.max_stack_of(CARGO)
	for _i in max_stack + 1:
		Inserter._drop_to_chest(stacky, CARGO)
	var stack_bag: Array = stacky.state["bag"]
	_check(failures, stack_bag.size() == 1,
		"(6) RETENTION: %d drops of one type must stay ONE bag entry (chest waives per-stack caps), found %d entries"
			% [max_stack + 1, stack_bag.size()])
	_check(failures, stack_bag.size() == 1 and int(stack_bag[0][1]) == max_stack + 1,
		"(6) RETENTION: the single entry must hold %d, past the %d max_stack, found %s"
			% [max_stack + 1, max_stack, str(stack_bag)])

	# ===========================================================================
	# (7) A chest with NO "bag" key. `chest.state.get("bag", [])` returns the
	# default literal — a temporary — so appending to it wrote the item
	# nowhere while reporting success, and `_clear_held` then discarded it.
	# `Chest._bag` (chest.gd:36-39) exists precisely to repair this shape,
	# and `try_insert` goes through it.
	#
	# Reachable, not theoretical: Building.from_dict hands `d["s"]` to the
	# constructor unchanged whenever it is a Dictionary, so a save whose
	# chest state is `{}` produces exactly this building.
	# ===========================================================================
	var bagless: Building = Building.new(Buildings.Type.CHEST, Vector2i(0, 0), {})
	var bagless_ok: bool = Inserter._drop_to_chest(bagless, CARGO)
	_check(failures, Chest.total_items(bagless) == 1,
		"(7) BAGLESS: the drop reported %s but the chest holds %d items — the item went into the get() default array and was destroyed"
			% [str(bagless_ok), Chest.total_items(bagless)])
	_check(failures, bagless_ok,
		"(7) BAGLESS: a repaired empty chest has room, so the drop must report success")

	if failures.is_empty():
		return { "ok": true, "message": "inserter honours Chest.TOTAL_CAPACITY (%d): blocks at the cap, recovers, waives per-stack caps, repairs a bagless chest" % cap }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

## chest(8,10) --[inserter(9,10) facing E]--> chest(10,10), pre-fuelled.
## Returns {ok, world, src, ins, dst} or {ok=false, message}.
static func _build_rig(parent: Node) -> Dictionary:
	var w = GridWorldScript.new()
	parent.add_child(w)
	for x in range(6, 15):
		for y in range(8, 14):
			w.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	for spec in [[Buildings.Type.CHEST, Vector2i(8, 10)], [Buildings.Type.INSERTER, Vector2i(9, 10)], [Buildings.Type.CHEST, Vector2i(10, 10)]]:
		if not w.place_building(spec[0], spec[1], Belt.DIR_E):
			_teardown(w)
			return { "ok": false, "message": "setup: placement failed at %s: %s" % [str(spec[1]), w.last_building_place_error] }
	var ins: Building = w.building_at(Vector2i(9, 10))
	# Aim check before the verdict is trusted — a mis-aimed inserter
	# reproduces "nothing overfilled" without the bug being gone.
	if Inserter.source_tile(ins) != Vector2i(8, 10) or Inserter.dest_tile(ins) != Vector2i(10, 10):
		_teardown(w)
		return { "ok": false, "message": "setup: inserter aims %s -> %s, expected (8, 10) -> (10, 10)"
			% [str(Inserter.source_tile(ins)), str(Inserter.dest_tile(ins))] }
	# Basic inserter is a burner tier; starve it and every case reads
	# STATE_NO_FUEL instead of the state under test.
	ins.state["fuel_buffer"] = 100000
	return {
		"ok": true,
		"world": w,
		"src": w.building_at(Vector2i(8, 10)),
		"ins": ins,
		"dst": w.building_at(Vector2i(10, 10)),
	}

static func _run_ticks(n: int) -> void:
	for _i in n:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

static func _held_count(ins: Building) -> int:
	var n: int = 0
	for entry in ins.state.get("held_item_buffer", []):
		n += int(entry[1])
	return n

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
