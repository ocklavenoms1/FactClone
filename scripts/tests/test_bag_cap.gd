extends RefCounted

## Bag-cap mechanic test.
##
## Three things to lock in:
##   1. `Inventory.expand(n)` grows capacity by N empty slots; existing
##      items are unaffected.
##   2. The cap-of-5 rule: 5 bags can be consumed; the 6th attempt fails
##      and the bag stays.
##   3. Failure ordering: when cap is reached AND the player is also out
##      of bags, the cap-reached message takes priority. (The player should
##      hear about the more permanent state first; "save bags for trade"
##      is a strategy hint, "no bag" is just an inventory check.)
##
## This test does NOT exercise the two-press confirm UI flow — that's
## main.gd's _request_bag_consume / _confirm_bag_consume layered over the
## same primitives. The unit-test scope is the underlying state changes
## (Inventory.expand + cap check + bag.remove).

const SLOTS_PER_BAG: int = 4
const BAG_CAP: int = 5
const STARTING_CAPACITY: int = 16

static func test_name() -> String:
	return "bag-cap mechanic (expand, cap, failure ordering)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	# --- Phase 1: Inventory.expand correctness ---
	var inv: Inventory = Inventory.new(STARTING_CAPACITY)
	inv.add(Items.Type.WHEAT, 7)
	_check(failures, inv.capacity == STARTING_CAPACITY, "starting capacity: expected %d, got %d" % [STARTING_CAPACITY, inv.capacity])
	_check(failures, inv.total_of(Items.Type.WHEAT) == 7, "pre-expand wheat: expected 7, got %d" % inv.total_of(Items.Type.WHEAT))

	inv.expand(SLOTS_PER_BAG)
	_check(failures, inv.capacity == STARTING_CAPACITY + SLOTS_PER_BAG, "post-expand capacity: expected %d, got %d" % [STARTING_CAPACITY + SLOTS_PER_BAG, inv.capacity])
	_check(failures, inv.slots.size() == STARTING_CAPACITY + SLOTS_PER_BAG, "slots array size mismatch: %d" % inv.slots.size())
	_check(failures, inv.total_of(Items.Type.WHEAT) == 7, "items unaffected by expand: expected 7 wheat, got %d" % inv.total_of(Items.Type.WHEAT))

	# expand(0) and expand(-N) are no-ops.
	inv.expand(0)
	_check(failures, inv.capacity == STARTING_CAPACITY + SLOTS_PER_BAG, "expand(0) should be no-op")
	inv.expand(-3)
	_check(failures, inv.capacity == STARTING_CAPACITY + SLOTS_PER_BAG, "expand(-N) should be no-op")

	# slots_used: 7 wheat at max_stack=100 fits in 1 slot. After expand by
	# SLOTS_PER_BAG, capacity grew but used slots didn't.
	_check(failures, inv.slots_used() == 1, "slots_used after 7 wheat: expected 1, got %d" % inv.slots_used())
	_check(failures, inv.capacity - inv.slots_used() == SLOTS_PER_BAG + (STARTING_CAPACITY - 1), "free slot count mismatch after expand")

	# --- Phase 2: cap-of-5 lifecycle ---
	# Simulate the consume-bag flow as a state machine over 6 attempts.
	# Mirrors main.gd's _confirm_bag_consume() preconditions + actions
	# without reaching into main.gd directly (test stays unit-scoped).
	var inv2: Inventory = Inventory.new(STARTING_CAPACITY)
	# Stock 6 bags so the LAST attempt has a bag available — separates the
	# cap-rejection case (this phase) from the no-bag case (phase 3).
	inv2.add(Items.Type.BAG, 6)
	var bags_consumed: int = 0

	for i in 5:
		var ok: Dictionary = _try_consume(inv2, bags_consumed)
		_check(failures, ok["consumed"], "attempt %d (within cap) should consume: %s" % [i + 1, ok["reason"]])
		if ok["consumed"]:
			bags_consumed += 1
		_check(failures, inv2.capacity == STARTING_CAPACITY + (i + 1) * SLOTS_PER_BAG, "after attempt %d, capacity: expected %d, got %d" % [i + 1, STARTING_CAPACITY + (i + 1) * SLOTS_PER_BAG, inv2.capacity])

	_check(failures, bags_consumed == BAG_CAP, "bags_consumed after 5 successes: expected %d, got %d" % [BAG_CAP, bags_consumed])
	_check(failures, inv2.capacity == STARTING_CAPACITY + BAG_CAP * SLOTS_PER_BAG, "capacity at cap: expected %d, got %d" % [STARTING_CAPACITY + BAG_CAP * SLOTS_PER_BAG, inv2.capacity])
	_check(failures, inv2.total_of(Items.Type.BAG) == 1, "bags remaining after 5 consumed (started with 6): expected 1, got %d" % inv2.total_of(Items.Type.BAG))

	# 6th attempt — has a bag, but cap is reached. Must fail with cap message,
	# and the bag must remain in inventory.
	var sixth: Dictionary = _try_consume(inv2, bags_consumed)
	_check(failures, not sixth["consumed"], "6th attempt should fail (cap reached)")
	_check(failures, sixth["reason"] == "cap", "6th attempt fail reason: expected 'cap', got '%s'" % sixth["reason"])
	_check(failures, inv2.total_of(Items.Type.BAG) == 1, "bag must remain after capped attempt: got %d" % inv2.total_of(Items.Type.BAG))
	_check(failures, inv2.capacity == STARTING_CAPACITY + BAG_CAP * SLOTS_PER_BAG, "capacity must not change on capped attempt")

	# --- Phase 3: failure ordering ---
	# When BOTH cap reached AND no bag in inventory, cap-reached wins.
	# Same inv2, but remove the remaining bag first.
	inv2.remove(Items.Type.BAG, 1)
	_check(failures, inv2.total_of(Items.Type.BAG) == 0, "preflight: inv2 should have 0 bags now")
	var both_failure: Dictionary = _try_consume(inv2, bags_consumed)
	_check(failures, not both_failure["consumed"], "attempt with cap+no-bag should fail")
	_check(failures, both_failure["reason"] == "cap", "with cap reached AND no bag, fail reason should be 'cap' (cap takes priority over 'no_bag'); got '%s'" % both_failure["reason"])

	# Sanity: no-bag-only (cap not reached) returns 'no_bag', not 'cap'.
	var inv3: Inventory = Inventory.new(STARTING_CAPACITY)
	# bags_consumed = 0 (under cap), inventory empty.
	var nobag_only: Dictionary = _try_consume(inv3, 0)
	_check(failures, not nobag_only["consumed"], "attempt with no-bag-only should fail")
	_check(failures, nobag_only["reason"] == "no_bag", "with cap-not-reached AND no bag, fail reason should be 'no_bag'; got '%s'" % nobag_only["reason"])

	if failures.is_empty():
		return { "ok": true, "message": "expand grows capacity, cap holds at %d, cap-priority over no-bag confirmed" % BAG_CAP }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

# ---------- helpers ----------

## Mirrors the precondition + action ordering in main.gd's
## _confirm_bag_consume(). Returns a dict { "consumed": bool, "reason": String }.
## Reasons: "ok" (consumed), "cap" (cap reached), "no_bag" (no bag available).
## **Cap-reached check fires BEFORE no-bag check** — locking in the failure
## ordering documented in the design.
static func _try_consume(inv: Inventory, bags_consumed: int) -> Dictionary:
	if bags_consumed >= BAG_CAP:
		return { "consumed": false, "reason": "cap" }
	if inv.total_of(Items.Type.BAG) <= 0:
		return { "consumed": false, "reason": "no_bag" }
	inv.remove(Items.Type.BAG, 1)
	inv.expand(SLOTS_PER_BAG)
	return { "consumed": true, "reason": "ok" }

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
