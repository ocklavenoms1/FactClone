class_name Burner
extends RefCounted

## Generic burner-fuel mechanic shared by buildings that consume fuel.
##
## Today's only consumer: MINING_DRILL. Future consumers: smelter, charcoal
## kiln, brick kiln, etc. Each calls into Burner.try_pull_fuel +
## Burner.consume_tick from its own tick handler; per-building tick rate
## (ORE_PER_FUEL etc.) lives in the building module, not here.
##
## State convention on the building's `state` dict:
##   fuel_buffer: int          — fuel UNITS remaining (not item count; items
##                                are converted to units via FUEL_VALUES on pull)
##   fuel_burn_progress: int   — ticks accumulated toward consuming next unit
##   last_fuel_item: int       — most recently deposited fuel item type (Items.Type),
##                                for display only. -1 if never fed. Mixed-tier
##                                buffers show whichever item was added last; this
##                                is acceptable since players typically feed one
##                                tier at a time.
##
## Fuel item → energy unit values: WOOD = 1, COAL = 4, FUEL_BRIQUETTE = 8.
## Tunable per item by editing FUEL_VALUES below; future items (CHARCOAL,
## planks?) just append entries.

# Fuel item types and their energy values (units of fuel per ITEM consumed).
const FUEL_VALUES: Dictionary = {
	Items.Type.WOOD:           1,
	Items.Type.COAL:           4,
	Items.Type.FUEL_BRIQUETTE: 8,
}

# Maximum fuel units a building can hold in its buffer. Tunable per
# building if needed (most burners use this default; could become a
# parameter if some burners need bigger buffers).
const FUEL_BUFFER_CAPACITY: int = 16

## Try to pull one fuel item from belt or chest cells adjacent to building b.
## fuel_edge_dir: which world-space edge to scan (Belt.DIR_E/S/W/N) — if -1,
## scans all 4 edges. Buildings with a "fuel input port" pass their port
## direction; buildings without one (e.g., drill in v1, inserters) pass -1.
##
## Returns true if a fuel item was pulled (state.fuel_buffer increased).
static func try_pull_fuel(b: Building, world, fuel_edge_dir: int = -1) -> bool:
	var current: int = int(b.state.get("fuel_buffer", 0))
	if current >= FUEL_BUFFER_CAPACITY:
		return false
	var dirs: Array = [fuel_edge_dir] if fuel_edge_dir >= 0 else [Belt.DIR_E, Belt.DIR_S, Belt.DIR_W, Belt.DIR_N]
	for d in dirs:
		for cell in Buildings.edge_cells(b.type, b.anchor, d):
			if _try_pull_fuel_at_cell(b, world, cell, current):
				return true
	return false

static func _try_pull_fuel_at_cell(b: Building, world, cell: Vector2i, current_units: int) -> bool:
	var src: Building = world.building_at(cell)
	if src == null:
		return false
	if src.type == Buildings.Type.BELT:
		return _try_pull_from_belt(b, src, current_units)
	if src.type == Buildings.Type.CHEST:
		return _try_pull_from_chest(b, src, current_units)
	return false

static func _try_pull_from_belt(b: Building, belt: Building, current_units: int) -> bool:
	var slots: Array = belt.state.get("slots", [])
	for i in slots.size():
		var item_t: int = int(slots[i])
		if item_t < 0:
			continue
		if not FUEL_VALUES.has(item_t):
			continue
		var energy: int = int(FUEL_VALUES[item_t])
		# Don't overfill: skip if adding would exceed capacity.
		# (Belt items are atomic; we either pull the whole item or none.)
		if current_units + energy > FUEL_BUFFER_CAPACITY:
			continue
		slots[i] = -1
		b.state["fuel_buffer"] = current_units + energy
		b.state["last_fuel_item"] = item_t
		return true
	return false

static func _try_pull_from_chest(b: Building, chest: Building, current_units: int) -> bool:
	var bag: Array = chest.state.get("bag", [])
	for entry in bag:
		var item_t: int = int(entry[0])
		if not FUEL_VALUES.has(item_t):
			continue
		var energy: int = int(FUEL_VALUES[item_t])
		if current_units + energy > FUEL_BUFFER_CAPACITY:
			continue
		entry[1] = int(entry[1]) - 1
		if int(entry[1]) <= 0:
			bag.erase(entry)
		b.state["fuel_buffer"] = current_units + energy
		b.state["last_fuel_item"] = item_t
		return true
	return false

## Consume one fuel-burn tick. Caller passes ticks_per_unit — the number of
## drill/smelt/etc. ticks it takes to burn 1 fuel unit. After ticks_per_unit
## calls, fuel_buffer decrements by 1.
##
## Returns true if a tick was burned (fuel was available); false if no fuel
## (buffer empty), in which case the building should set its NO_FUEL state.
##
## Convention: caller calls this ONCE per ore-produced (or smelt-completed,
## or other unit-of-work). With 8 ore per fuel unit, ticks_per_unit = 8.
static func consume_tick(b: Building, ticks_per_unit: int) -> bool:
	if int(b.state.get("fuel_buffer", 0)) <= 0:
		return false
	var p: int = int(b.state.get("fuel_burn_progress", 0)) + 1
	if p >= ticks_per_unit:
		b.state["fuel_buffer"] = int(b.state["fuel_buffer"]) - 1
		b.state["fuel_burn_progress"] = 0
	else:
		b.state["fuel_burn_progress"] = p
	return true

## Q-inspect helper. Returns lines for a burner's fuel display:
##   "Fuel: 3 / 16 units"
##   "Status: NO FUEL"   (only if fuel_buffer == 0)
## Buildings call this from their info_lines() and append additional lines
## for their building-specific state.
static func info_lines(b: Building) -> Array:
	var fuel: int = int(b.state.get("fuel_buffer", 0))
	var lines: Array = ["Fuel: %d / %d units" % [fuel, FUEL_BUFFER_CAPACITY]]
	if fuel == 0:
		lines.append("Status: NO FUEL — feed wood, coal, or fuel briquette")
	return lines

## Default fuel-buffer state for new burner buildings. Call this from your
## make() function and merge into the rest of state.
static func make_state() -> Dictionary:
	return {
		"fuel_buffer": 0,
		"fuel_burn_progress": 0,
		"last_fuel_item": -1,
	}
