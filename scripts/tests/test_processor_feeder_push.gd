extends RefCounted

## Audit finding #14 — a processor must never push its output onto a belt
## that feeds it.
##
## `Processor._try_push_outputs` scans for somewhere to put a finished item.
## Neither the no-preference sweep nor the strict prefer_dir path used to look
## at the neighbour belt's DIRECTION, so a belt pointing INTO the building was
## an eligible sink. Pushing there is always wrong: `Belt.try_insert` drops the
## item in slot 0 and the belt carries it toward the machine that just made it,
## the machine will not re-accept its own output, and the item parks in the
## front slot forever. Repeat once per tick and the feeder belt saturates with
## output — the input line is dead, and the item is stranded.
##
## MEASURED before the fix (mill + one E-pointing feeder belt on the W side,
## 400 ticks): feeder slots went [GRAIN,GRAIN,GRAIN,GRAIN] -> [FLOUR x4] and
## `Belt.try_insert(feeder, GRAIN)` returned false. The grain supply line was
## permanently blocked by the mill's own flour.
##
## Reached via the four recipes whose outputs declare no prefer_dir —
## mill_grain_to_flour, briquetter_fuel, yeast_culture, press_sugar (the
## no-preference branch), and via any prefer_dir output whose declared edge
## happens to hold an inward-pointing belt (the strict branch). Both branches
## are covered below; case (5) pins that the guard does NOT over-block.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "processor feeder push (#14: outputs must not go onto an input belt)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_no_sink(parent, failures)
	_case_real_sink(parent, failures)
	_case_jammed_sink(parent, failures)
	_case_strict_path(parent, failures)
	_case_sideways_belt_still_valid(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "" }
	return { "ok": false, "message": " | ".join(failures) }

## (1) Mill with ONE neighbour: an E-pointing belt on its W side (a feeder).
## The mill's only push candidate is the belt that feeds it. It must decline
## and hold the flour in its own out_buffer.
static func _case_no_sink(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.BELT, Vector2i(0, 0), Belt.DIR_E)   # -> into mill
	world.place_building(Buildings.Type.MILL, Vector2i(1, 0), Belt.DIR_E)
	var feeder: Building = world.building_at(Vector2i(0, 0))
	var mill: Building = world.building_at(Vector2i(1, 0))

	mill.state["in_buffer"] = [[Items.Type.GRAIN, 4]]
	for i in Belt.SLOTS_PER_TILE:
		feeder.state["slots"][i] = Items.Type.GRAIN

	for _t in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var flour_on_feeder: int = _slot_count(feeder, Items.Type.FLOUR)
	_check(failures, flour_on_feeder == 0,
		"(1) mill pushed %d FLOUR back onto its own feeder belt" % flour_on_feeder)
	var buffered: int = _bag_count(mill.state["out_buffer"], Items.Type.FLOUR)
	_check(failures, buffered > 0,
		"(1) flour should have accumulated in out_buffer with no valid sink, got %d" % buffered)
	_cleanup(world)

## (2) The normal layout: feeder on W, output belt on E. Flour must go east,
## and the feeder must stay clean.
static func _case_real_sink(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	for x in 3:
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.BELT, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.MILL, Vector2i(1, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(2, 0), Belt.DIR_E)
	var feeder: Building = world.building_at(Vector2i(0, 0))
	var mill: Building = world.building_at(Vector2i(1, 0))
	var sink: Building = world.building_at(Vector2i(2, 0))

	mill.state["in_buffer"] = [[Items.Type.GRAIN, 4]]
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	_check(failures, _slot_count(feeder, Items.Type.FLOUR) == 0,
		"(2) flour reached the feeder belt even though a real sink existed")
	# The sink belt moves items on, so "ever received" is what matters; the
	# mill must have shipped at least one flour off-machine.
	var shipped: bool = _slot_count(sink, Items.Type.FLOUR) > 0 \
		or _bag_count(mill.state["out_buffer"], Items.Type.FLOUR) < 2
	_check(failures, shipped, "(2) mill did not ship flour to the east sink belt")
	_cleanup(world)

## (3) Output belt exists but is jammed solid. The mill must hold the flour,
## NOT fall through to the feeder. This is the case the guard exists for:
## the fall-through only triggers once the real sink stops accepting.
static func _case_jammed_sink(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	for x in 3:
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.BELT, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.MILL, Vector2i(1, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(2, 0), Belt.DIR_E)
	var feeder: Building = world.building_at(Vector2i(0, 0))
	var mill: Building = world.building_at(Vector2i(1, 0))
	var sink: Building = world.building_at(Vector2i(2, 0))

	mill.state["in_buffer"] = [[Items.Type.GRAIN, 8]]
	for i in Belt.SLOTS_PER_TILE:
		sink.state["slots"][i] = Items.Type.FLOUR      # downstream backed up
	feeder.state["slots"][3] = Items.Type.GRAIN

	for _t in 400:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var flour_on_feeder: int = _slot_count(feeder, Items.Type.FLOUR)
	_check(failures, flour_on_feeder == 0,
		"(3) jammed sink made the mill push %d FLOUR backward onto the feeder" % flour_on_feeder)
	_cleanup(world)

## (4) STRICT path (output declares prefer_dir). A composter's compost port is
## canonical E; put an inward-pointing belt on that very edge. The composter
## must decline rather than poison its own supply.
static func _case_strict_path(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.COMPOSTER, Vector2i(0, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_W)   # -> into composter
	var comp: Building = world.building_at(Vector2i(0, 0))
	var belt: Building = world.building_at(Vector2i(1, 0))

	comp.state["recipe_id"] = "composter_low_wheat"
	comp.state["out_buffer"] = [[Items.Type.COMPOST_LOW, 3]]

	for _t in 50:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var compost_on_belt: int = _slot_count(belt, Items.Type.COMPOST_LOW)
	_check(failures, compost_on_belt == 0,
		"(4) strict prefer_dir path pushed %d COMPOST onto an inward-pointing belt" % compost_on_belt)
	_cleanup(world)

## (5) The guard must block INWARD belts only. A belt running past the building
## (pointing somewhere else entirely) is a legitimate sink and must still work.
## Without this case the guard could pass by refusing every belt.
static func _case_sideways_belt_still_valid(parent: Node, failures: Array) -> void:
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.set_overlay(Vector2i(1, 1), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(1, 0), Terrain.Overlay.STONE)
	world.set_overlay(Vector2i(2, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.MILL, Vector2i(1, 1), Belt.DIR_E)
	# Belt on the mill's N edge pointing E — target (2,0) is NOT in the mill's
	# footprint, so it is a pass-by belt, not a feeder.
	world.place_building(Buildings.Type.BELT, Vector2i(1, 0), Belt.DIR_E)
	world.place_building(Buildings.Type.BELT, Vector2i(2, 0), Belt.DIR_E)
	var mill: Building = world.building_at(Vector2i(1, 1))
	var passby: Building = world.building_at(Vector2i(1, 0))

	mill.state["in_buffer"] = [[Items.Type.GRAIN, 4]]
	for _t in 200:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

	var buffered: int = _bag_count(mill.state["out_buffer"], Items.Type.FLOUR)
	_check(failures, buffered < 2,
		"(5) guard over-blocked: mill refused a legitimate pass-by belt, %d flour stuck in buffer" % buffered)
	_check(failures, passby != null, "(5) pass-by belt missing")
	_cleanup(world)

# ---------- helpers ----------

static func _slot_count(belt: Building, item_type: int) -> int:
	var n: int = 0
	for s in belt.state.get("slots", []):
		if int(s) == item_type:
			n += 1
	return n

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
