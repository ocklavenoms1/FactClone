extends RefCounted

## Inserter drop capacity on a SHARED in_buffer (audit finding #3).
##
## Oven and Mixer each declare TWO input slots bound to ONE state_field
## ("in_buffer") — a deliberate multi-type bag (see the slot_layout comments
## in buildings.gd). Processor caps that bag PER ITEM TYPE:
##
##   processor.gd:105  if _buffer_count(b.state["in_buffer"], item_type) >= capacity
##
## and buildings.gd documents slot max_stack as "per-item-type capacity in
## the slot's buffer". Inserter._drop_to_processor used to sum EVERY entry
## in the bag and compare that aggregate against one slot's max_stack (8),
## which is a different rule from the one the Processor and the slot
## descriptor both state.
##
## The consequence is a permanent deadlock, not a rounding error: a belt
## legitimately fills the Oven's dough input to 8, the recipe also needs a
## fuel briquette so it cannot start, the bag therefore never drains, and
## the aggregate check rejects the inserter's fuel forever. The inserter
## parks in STATE_BLOCKED_AT_DEST and the bread line halts. Belt-fed inputs
## are unaffected (Processor._try_pull_inputs already counts per type), so
## the defect is specific to the inserter-fed second input — a fully
## supported topology.
##
## Cases:
##   (1) BEHAVIOURAL — real Oven + real Inserter + real ticks: the fuel must
##       arrive and bread must come out of a dough-saturated oven.
##   (2) UNIT — 8 RISEN_DOUGH buffered, a FUEL_BRIQUETTE drop is ACCEPTED.
##   (3) UNIT — 8 RISEN_DOUGH buffered, a 9th RISEN_DOUGH is REJECTED.
##   (4) UNIT — the cap is per type, not per bag: a full bag of one type
##       does not raise the other type's ceiling above 8 either.
##   (5) UNIT — Mixer (the other shared-buffer input building) behaves the
##       same for inserter-fed yeast.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

## Both the Oven's dough/fuel slots and the Mixer's flour/yeast slots declare
## max_stack 8, and every recipe in recipes.gd declares input_capacity 8.
## Verified against buildings.gd (Type.OVEN / Type.MIXER slot_layout) and
## recipes.gd at the time of writing; (3) and (5) below would redden if a
## slot's max_stack moved without this constant following it.
const SLOT_CAP: int = 8

static func test_name() -> String:
	return "inserter shared-input cap (per-type, not aggregate: oven deadlock + mixer + cap retained)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ===========================================================================
	# (1) BEHAVIOURAL DEADLOCK REPRO — the finding is a wedged factory, so the
	# load-bearing assertion drives the real Inserter against a real Oven
	# through real ticks rather than calling the drop helper directly.
	#
	#   chest(8,10) --[inserter(9,10) facing E]--> oven anchored (10,10), 2x2
	#
	# The oven starts with its shared in_buffer holding 8 RISEN_DOUGH, which
	# is exactly what a belt on the dough edge produces when the oven is idle
	# for want of fuel. oven_bread needs 1 RISEN_DOUGH + 1 FUEL_BRIQUETTE, so
	# the oven cannot consume anything until the inserter lands the fuel.
	# ===========================================================================
	var world = _make_world(parent)
	if not world.place_building(Buildings.Type.OVEN, Vector2i(10, 10), Belt.DIR_E):
		_teardown(world)
		return { "ok": false, "message": "setup: oven placement failed: %s" % world.last_building_place_error }
	if not world.place_building(Buildings.Type.INSERTER, Vector2i(9, 10), Belt.DIR_E):
		_teardown(world)
		return { "ok": false, "message": "setup: inserter placement failed: %s" % world.last_building_place_error }
	if not world.place_building(Buildings.Type.CHEST, Vector2i(8, 10), Belt.DIR_E):
		_teardown(world)
		return { "ok": false, "message": "setup: source chest placement failed: %s" % world.last_building_place_error }

	var oven: Building = world.building_at(Vector2i(10, 10))
	var inserter: Building = world.building_at(Vector2i(9, 10))
	var fuel_chest: Building = world.building_at(Vector2i(8, 10))

	# Sanity-check the rig before trusting its verdict: a mis-aimed inserter
	# would produce the same "no fuel arrived" symptom as the defect.
	if Inserter.dest_tile(inserter) != Vector2i(10, 10):
		_teardown(world)
		return { "ok": false, "message": "setup: inserter dest is %s, expected (10, 10)" % Inserter.dest_tile(inserter) }
	if Inserter.source_tile(inserter) != Vector2i(8, 10):
		_teardown(world)
		return { "ok": false, "message": "setup: inserter source is %s, expected (8, 10)" % Inserter.source_tile(inserter) }
	if str(oven.state.get("recipe_id", "")) != "oven_bread":
		_teardown(world)
		return { "ok": false, "message": "setup: oven recipe is '%s', expected 'oven_bread'" % str(oven.state.get("recipe_id", "")) }

	# Belt-fed dough saturates the shared bag; fuel comes by inserter.
	oven.state["in_buffer"] = [[Items.Type.RISEN_DOUGH, SLOT_CAP]]
	oven.state["out_buffer"] = []
	fuel_chest.state["bag"] = [[Items.Type.FUEL_BRIQUETTE, 20]]
	# Pre-fuel the inserter so the burner path can't be confused for the
	# deadlock (basic inserter = 20 ticks/cycle; 1000 units is ample).
	inserter.state["fuel_buffer"] = 1000

	# 400 ticks = 20 inserter cycles and 3+ full 120-tick bakes.
	for _i in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var fuel_delivered: int = _buf_count(oven.state.get("in_buffer", []), Items.Type.FUEL_BRIQUETTE)
	var bread_made: int = _buf_count(oven.state.get("out_buffer", []), Items.Type.BREAD)
	var dough_left: int = _buf_count(oven.state.get("in_buffer", []), Items.Type.RISEN_DOUGH)

	_check(failures, fuel_delivered > 0 or bread_made > 0,
		"(1) DEADLOCK: inserter delivered 0 FUEL_BRIQUETTE into a dough-saturated oven in 400 ticks (aggregate cap rejects it forever)")
	_check(failures, bread_made > 0,
		"(1) DEADLOCK: oven baked 0 bread in 400 ticks with 8 dough buffered and fuel available next door, got %d" % bread_made)
	_check(failures, dough_left < SLOT_CAP,
		"(1) DEADLOCK: the dough bag never drained, still %d RISEN_DOUGH after 400 ticks" % dough_left)

	# SUSTAINED flow, not a single lucky drop: another 400 ticks must bake
	# more bread. A wedged line produces a flat count.
	for _i in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var bread_later: int = _buf_count(oven.state.get("out_buffer", []), Items.Type.BREAD)
	_check(failures, bread_later > bread_made,
		"(1) DEADLOCK: bread count flat at %d across ticks 400-800 — the line is not running" % bread_made)

	# The inserter DOES legitimately sit in STATE_BLOCKED_AT_DEST much of the
	# time once fuel reaches the per-type cap of 8 — that is correct
	# backpressure, not a wedge, so the instantaneous arm state proves
	# nothing on its own. The defect's signature is blocked-FOREVER: refusing
	# to deliver even when the fuel slot has room. Clear the fuel and the
	# inserter must resume within a couple of 20-tick cycles.
	oven.state["in_buffer"] = [[Items.Type.RISEN_DOUGH, SLOT_CAP]]
	for _i in 60:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	var refuelled: int = _buf_count(oven.state.get("in_buffer", []), Items.Type.FUEL_BRIQUETTE)
	_check(failures, refuelled > 0,
		"(1) DEADLOCK: with the fuel slot emptied and dough at %d, the inserter delivered 0 fuel in 60 ticks" % SLOT_CAP)

	_teardown(world)

	# ===========================================================================
	# (2) UNIT — ACCEPT the other type. Same saturated bag, drop helper called
	# directly so the verdict is unambiguous about which rule rejected it.
	# ===========================================================================
	var oven_b: Building = Oven.make(Vector2i(0, 0), Belt.DIR_E)
	oven_b.state["in_buffer"] = [[Items.Type.RISEN_DOUGH, SLOT_CAP]]
	var accepted: bool = Inserter._drop_to_processor(oven_b, Items.Type.FUEL_BRIQUETTE)
	_check(failures, accepted,
		"(2) a FUEL_BRIQUETTE drop must be ACCEPTED with %d RISEN_DOUGH buffered — the fuel slot is empty" % SLOT_CAP)
	_check(failures, _buf_count(oven_b.state.get("in_buffer", []), Items.Type.FUEL_BRIQUETTE) == 1,
		"(2) accepted drop must actually land 1 FUEL_BRIQUETTE in the bag, found %d"
			% _buf_count(oven_b.state.get("in_buffer", []), Items.Type.FUEL_BRIQUETTE))
	_check(failures, _buf_count(oven_b.state.get("in_buffer", []), Items.Type.RISEN_DOUGH) == SLOT_CAP,
		"(2) the drop must not disturb the %d buffered RISEN_DOUGH, found %d"
			% [SLOT_CAP, _buf_count(oven_b.state.get("in_buffer", []), Items.Type.RISEN_DOUGH)])

	# ===========================================================================
	# (3) UNIT — REJECT a 9th of the SAME type. This is the assertion that
	# stops the fix from degenerating into "delete the cap": (2) alone passes
	# just as happily with no capacity check at all.
	# ===========================================================================
	var oven_c: Building = Oven.make(Vector2i(0, 0), Belt.DIR_E)
	oven_c.state["in_buffer"] = [[Items.Type.RISEN_DOUGH, SLOT_CAP]]
	var over_cap: bool = Inserter._drop_to_processor(oven_c, Items.Type.RISEN_DOUGH)
	_check(failures, not over_cap,
		"(3) a %dth RISEN_DOUGH must be REJECTED — the per-type cap is %d" % [SLOT_CAP + 1, SLOT_CAP])
	_check(failures, _buf_count(oven_c.state.get("in_buffer", []), Items.Type.RISEN_DOUGH) == SLOT_CAP,
		"(3) rejected drop must leave the count at %d, found %d"
			% [SLOT_CAP, _buf_count(oven_c.state.get("in_buffer", []), Items.Type.RISEN_DOUGH)])

	# ===========================================================================
	# (4) UNIT — per-type means PER TYPE: a bag holding a full stack of the
	# other item does not lift this item's own ceiling. Guards against a fix
	# that keys capacity off the bag rather than off the item.
	# ===========================================================================
	var oven_d: Building = Oven.make(Vector2i(0, 0), Belt.DIR_E)
	oven_d.state["in_buffer"] = [[Items.Type.RISEN_DOUGH, SLOT_CAP], [Items.Type.FUEL_BRIQUETTE, SLOT_CAP]]
	var both_full: bool = Inserter._drop_to_processor(oven_d, Items.Type.FUEL_BRIQUETTE)
	_check(failures, not both_full,
		"(4) with both types already at %d, a further FUEL_BRIQUETTE must be REJECTED" % SLOT_CAP)
	_check(failures, _buf_count(oven_d.state.get("in_buffer", []), Items.Type.FUEL_BRIQUETTE) == SLOT_CAP,
		"(4) rejected drop must leave FUEL_BRIQUETTE at %d, found %d"
			% [SLOT_CAP, _buf_count(oven_d.state.get("in_buffer", []), Items.Type.FUEL_BRIQUETTE)])

	# ===========================================================================
	# (5) UNIT — MIXER, the other shared-buffer input building (flour + yeast
	# both bound to "in_buffer"). Belt-fed flour saturates the bag; the
	# inserter-fed yeast must still get in, and flour must still cap at 8.
	# ===========================================================================
	var mixer: Building = Mixer.make(Vector2i(0, 0), Belt.DIR_E)
	mixer.state["in_buffer"] = [[Items.Type.FLOUR, SLOT_CAP]]
	var yeast_ok: bool = Inserter._drop_to_processor(mixer, Items.Type.YEAST)
	_check(failures, yeast_ok,
		"(5) a YEAST drop must be ACCEPTED with %d FLOUR buffered — the yeast slot is empty" % SLOT_CAP)
	var flour_over: bool = Inserter._drop_to_processor(mixer, Items.Type.FLOUR)
	_check(failures, not flour_over,
		"(5) a %dth FLOUR must still be REJECTED on the mixer" % (SLOT_CAP + 1))

	if failures.is_empty():
		return { "ok": true, "message": "inserter drop caps shared in_buffer per item type (oven line runs, mixer yeast lands, cap still enforced)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 8))] }

# ---------- helpers ----------

static func _make_world(parent: Node) -> Node2D:
	var w = GridWorldScript.new()
	parent.add_child(w)
	# Oven and Chest both require STONE/PATH; Inserter accepts NONE but is
	# fine on stone. One overlay choice keeps placement uniform.
	for x in range(6, 15):
		for y in range(8, 14):
			w.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	return w

static func _buf_count(buf: Array, item_type: int) -> int:
	for entry in buf:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
