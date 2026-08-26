extends RefCounted

## Bag-cap mechanic test.
##
## Four things to lock in:
##   1. `Inventory.expand(n)` grows capacity by N empty slots; existing
##      items are unaffected.
##   2. The cap rule: BAG_CAP bags can be consumed; the next attempt fails
##      and the bag stays.
##   3. Failure ordering: when cap is reached AND the player is also out
##      of bags, the cap-reached message takes priority. (The player should
##      hear about the more permanent state first; "save bags for trade"
##      is a strategy hint, "no bag" is just an inventory check.)
##   4. Both B-key handlers actually route through the shared seam.
##
## ⚠ AUDIT #27 — THIS SUITE USED TO TEST ITS OWN COPY.
## Phases 2 and 3 ran against a static `_try_consume` in this file, over
## test-local `BAG_CAP`/`SLOTS_PER_BAG`/`STARTING_CAPACITY` constants that
## duplicated `main.gd:4, 9, 10`. Production could drift arbitrarily and the
## suite stayed green. Measured 2026-08-25 against the pre-fix code: BAG_CAP
## doubled to 10 AND the two precondition checks swapped in
## `_confirm_bag_consume` gave **68 passed, 0 failed, 0 SCRIPT ERROR**.
##
## The mirror is gone. The ordering rule and the remove+expand+increment now
## live in `main.gd`'s `bag_consume_verdict` / `try_consume_bag` statics, and
## this file calls them. The three design VALUES are pinned once, in phase 0,
## so a constant change reddens with a message that names it; everything
## after phase 0 reads the production constants, so the phases test the
## mechanic rather than re-asserting the numbers.
##
## This test still does NOT exercise the two-press confirm UI flow (the
## pending-confirm window, the toast text). What phase 4 adds instead is a
## structural pin on the two call sites, because delegation the call sites
## bypass is delegation that proves nothing.

const MainScript = preload("res://scripts/main.gd")
const MAIN_SRC_PATH: String = "res://scripts/main.gd"

# The design values, asserted (not re-declared) in phase 0.
const EXPECTED_SLOTS_PER_BAG: int = 4
const EXPECTED_BAG_CAP: int = 5
const EXPECTED_STARTING_CAPACITY: int = 16

static func test_name() -> String:
	return "bag-cap mechanic (expand, cap, failure ordering, seam delegation)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	# --- Phase 0: pin the production constants ---
	# The ONLY place this suite states a number the game also states. Every
	# later phase reads MainScript.*, so this is the single drift alarm.
	_check(failures, MainScript.SLOTS_PER_BAG == EXPECTED_SLOTS_PER_BAG,
		"main.gd SLOTS_PER_BAG changed: design value is %d, code says %d" % [EXPECTED_SLOTS_PER_BAG, MainScript.SLOTS_PER_BAG])
	_check(failures, MainScript.BAG_CAP == EXPECTED_BAG_CAP,
		"main.gd BAG_CAP changed: design value is %d, code says %d" % [EXPECTED_BAG_CAP, MainScript.BAG_CAP])
	_check(failures, MainScript.PLAYER_INVENTORY_CAPACITY == EXPECTED_STARTING_CAPACITY,
		"main.gd PLAYER_INVENTORY_CAPACITY changed: design value is %d, code says %d" % [EXPECTED_STARTING_CAPACITY, MainScript.PLAYER_INVENTORY_CAPACITY])

	var slots_per_bag: int = MainScript.SLOTS_PER_BAG
	var bag_cap: int = MainScript.BAG_CAP
	var start_cap: int = MainScript.PLAYER_INVENTORY_CAPACITY

	# --- Phase 1: Inventory.expand correctness ---
	var inv: Inventory = Inventory.new(start_cap)
	inv.add(Items.Type.WHEAT, 7)
	_check(failures, inv.capacity == start_cap, "starting capacity: expected %d, got %d" % [start_cap, inv.capacity])
	_check(failures, inv.total_of(Items.Type.WHEAT) == 7, "pre-expand wheat: expected 7, got %d" % inv.total_of(Items.Type.WHEAT))

	inv.expand(slots_per_bag)
	_check(failures, inv.capacity == start_cap + slots_per_bag, "post-expand capacity: expected %d, got %d" % [start_cap + slots_per_bag, inv.capacity])
	_check(failures, inv.slots.size() == start_cap + slots_per_bag, "slots array size mismatch: %d" % inv.slots.size())
	_check(failures, inv.total_of(Items.Type.WHEAT) == 7, "items unaffected by expand: expected 7 wheat, got %d" % inv.total_of(Items.Type.WHEAT))

	# expand(0) and expand(-N) are no-ops.
	inv.expand(0)
	_check(failures, inv.capacity == start_cap + slots_per_bag, "expand(0) should be no-op")
	inv.expand(-3)
	_check(failures, inv.capacity == start_cap + slots_per_bag, "expand(-N) should be no-op")

	# slots_used: 7 wheat at max_stack=100 fits in 1 slot. After expand by
	# slots_per_bag, capacity grew but used slots didn't.
	_check(failures, inv.slots_used() == 1, "slots_used after 7 wheat: expected 1, got %d" % inv.slots_used())
	_check(failures, inv.capacity - inv.slots_used() == slots_per_bag + (start_cap - 1), "free slot count mismatch after expand")

	# --- Phase 2: cap lifecycle, driven through production ---
	# Every attempt below is a real call to main.gd's try_consume_bag, with a
	# throwaway Inventory and a throwaway progression dict standing in for
	# player_inventory / player_progression.
	var inv2: Inventory = Inventory.new(start_cap)
	# Stock one MORE bag than the cap allows, so the over-cap attempt still has
	# a bag available — that separates the cap-rejection case (this phase) from
	# the no-bag case (phase 3).
	inv2.add(Items.Type.BAG, bag_cap + 1)
	var progression: Dictionary = { "bags_consumed": 0 }

	for i in bag_cap:
		var verdict: String = MainScript.try_consume_bag(inv2, progression)
		_check(failures, verdict == "", "attempt %d (within cap) should consume, got verdict '%s'" % [i + 1, verdict])
		_check(failures, int(progression.get("bags_consumed", -1)) == i + 1, "after attempt %d, bags_consumed: expected %d, got %s" % [i + 1, i + 1, str(progression.get("bags_consumed", "MISSING"))])
		_check(failures, inv2.capacity == start_cap + (i + 1) * slots_per_bag, "after attempt %d, capacity: expected %d, got %d" % [i + 1, start_cap + (i + 1) * slots_per_bag, inv2.capacity])

	_check(failures, int(progression.get("bags_consumed", -1)) == bag_cap, "bags_consumed after %d successes: expected %d, got %s" % [bag_cap, bag_cap, str(progression.get("bags_consumed", "MISSING"))])
	_check(failures, inv2.capacity == start_cap + bag_cap * slots_per_bag, "capacity at cap: expected %d, got %d" % [start_cap + bag_cap * slots_per_bag, inv2.capacity])
	# The bag REMOVAL is a production side effect now, so this counts it:
	# stocked bag_cap + 1, consumed bag_cap, exactly 1 must be left.
	_check(failures, inv2.total_of(Items.Type.BAG) == 1, "bags remaining after %d consumed (started with %d): expected 1, got %d" % [bag_cap, bag_cap + 1, inv2.total_of(Items.Type.BAG)])

	# Over-cap attempt — has a bag, but cap is reached. Must fail with the cap
	# verdict, and the bag must remain in inventory.
	var over_cap: String = MainScript.try_consume_bag(inv2, progression)
	_check(failures, over_cap == "cap", "over-cap attempt should fail with 'cap', got '%s'" % over_cap)
	_check(failures, inv2.total_of(Items.Type.BAG) == 1, "bag must remain after capped attempt: got %d" % inv2.total_of(Items.Type.BAG))
	_check(failures, inv2.capacity == start_cap + bag_cap * slots_per_bag, "capacity must not change on capped attempt")
	_check(failures, int(progression.get("bags_consumed", -1)) == bag_cap, "bags_consumed must not advance on capped attempt")

	# --- Phase 3: failure ordering ---
	# When BOTH cap reached AND no bag in inventory, cap-reached wins.
	# Same inv2, but remove the remaining bag first.
	inv2.remove(Items.Type.BAG, 1)
	_check(failures, inv2.total_of(Items.Type.BAG) == 0, "preflight: inv2 should have 0 bags now")
	var both_failure: String = MainScript.try_consume_bag(inv2, progression)
	_check(failures, both_failure == "cap", "with cap reached AND no bag, verdict should be 'cap' (cap takes priority over 'no_bag'); got '%s'" % both_failure)

	# Sanity: no-bag-only (cap not reached) returns 'no_bag', not 'cap'.
	var inv3: Inventory = Inventory.new(start_cap)
	var fresh_progression: Dictionary = { "bags_consumed": 0 }
	var nobag_only: String = MainScript.try_consume_bag(inv3, fresh_progression)
	_check(failures, nobag_only == "no_bag", "with cap-not-reached AND no bag, verdict should be 'no_bag'; got '%s'" % nobag_only)
	_check(failures, inv3.capacity == start_cap, "failed no-bag attempt must not expand capacity")

	# The verdict half on its own, at the boundary. bag_consume_verdict is what
	# BOTH key handlers branch on, so it is asserted directly rather than only
	# through try_consume_bag.
	_check(failures, MainScript.bag_consume_verdict(bag_cap - 1, 1) == "", "verdict one below cap with a bag should be '' (proceed)")
	_check(failures, MainScript.bag_consume_verdict(bag_cap, 1) == "cap", "verdict at cap with a bag should be 'cap'")
	_check(failures, MainScript.bag_consume_verdict(0, 0) == "no_bag", "verdict under cap with no bag should be 'no_bag'")
	_check(failures, MainScript.bag_consume_verdict(bag_cap, 0) == "cap", "verdict at cap AND no bag should be 'cap' — ordering")

	# --- Phase 4: the call sites actually use the seam ---
	_check_call_sites(failures)

	if failures.is_empty():
		return { "ok": true, "message": "expand grows capacity, production cap holds at %d, cap-priority over no-bag confirmed, both B-key handlers route through the seam" % bag_cap }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

# ---------- helpers ----------

## Structural pin (audit #27's residual gap).
##
## Phases 2-3 prove the SEAM behaves. They cannot prove the game calls it —
## `_request_bag_consume` / `_confirm_bag_consume` need a live Node2D with a
## `toast_label`, which `test_runner.gd` has no scene for. Measured: with the
## seam in place and the suite delegating, re-inlining a swapped-order copy
## into `_confirm_bag_consume` leaves everything green. So the call sites are
## pinned by reading the source.
##
## The guard's own failure mode matters: if a function cannot be found at all
## (renamed, moved), this fails loudly rather than passing over an empty body.
static func _check_call_sites(failures: Array) -> void:
	var f: FileAccess = FileAccess.open(MAIN_SRC_PATH, FileAccess.READ)
	if f == null:
		_check(failures, false, "(4) SETUP: cannot open %s for the call-site scan" % MAIN_SRC_PATH)
		return
	var lines: PackedStringArray = f.get_as_text().split("\n")
	f.close()

	var request_body: Array = _func_body(lines, "func _request_bag_consume(")
	var confirm_body: Array = _func_body(lines, "func _confirm_bag_consume(")

	_check(failures, not request_body.is_empty(), "(4) main.gd has no `func _request_bag_consume(` body — the call-site scan found nothing to check")
	_check(failures, not confirm_body.is_empty(), "(4) main.gd has no `func _confirm_bag_consume(` body — the call-site scan found nothing to check")

	var request_src: String = "\n".join(request_body)
	var confirm_src: String = "\n".join(confirm_body)

	_check(failures, request_src.contains("bag_consume_verdict("),
		"(4) _request_bag_consume must branch on bag_consume_verdict() — it does not")
	_check(failures, not request_src.contains(">= BAG_CAP"),
		"(4) _request_bag_consume re-states the cap check (`>= BAG_CAP`); the ordering rule belongs to bag_consume_verdict alone")

	_check(failures, confirm_src.contains("try_consume_bag("),
		"(4) _confirm_bag_consume must delegate to try_consume_bag() — it does not")
	_check(failures, not confirm_src.contains(">= BAG_CAP"),
		"(4) _confirm_bag_consume re-states the cap check (`>= BAG_CAP`); the ordering rule belongs to bag_consume_verdict alone")
	_check(failures, not confirm_src.contains("remove(Items.Type.BAG"),
		"(4) _confirm_bag_consume removes the bag itself; the side effect belongs to try_consume_bag, which is what this suite asserts")
	_check(failures, not confirm_src.contains(".expand("),
		"(4) _confirm_bag_consume expands the inventory itself; the side effect belongs to try_consume_bag, which is what this suite asserts")

## Collect a function body: the `func` line plus every following line until the
## next line that starts at column 0 with non-whitespace (the next top-level
## declaration or comment). Returns [] if the header is not found.
static func _func_body(lines: PackedStringArray, header_prefix: String) -> Array:
	var body: Array = []
	var inside: bool = false
	for raw in lines:
		var line: String = raw.rstrip("\r")
		if not inside:
			if line.begins_with(header_prefix):
				inside = true
				body.append(line)
			continue
		if line.strip_edges() != "" and not (line.begins_with("\t") or line.begins_with(" ")):
			break
		body.append(line)
	return body

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
