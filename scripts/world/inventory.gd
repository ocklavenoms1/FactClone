class_name Inventory
extends RefCounted

## A bag of ItemStacks. Used for the player and as building buffers
## (harvester, mill, chest, etc.).

var slots: Array = []   # Array[ItemStack]
var capacity: int = 0

func _init(c: int = 8) -> void:
	capacity = c
	slots = []
	for i in capacity:
		slots.append(ItemStack.new())

## Add up to `count` items of `item_type`. Returns the count actually added.
## Tops up existing matching stacks first, then fills empty slots.
func add(item_type: int, count: int) -> int:
	if count <= 0 or item_type < 0:
		return 0
	var max_stack: int = Items.max_stack_of(item_type)
	var remaining: int = count
	# Pass 1: top up existing stacks.
	for s in slots:
		if remaining <= 0:
			break
		if s.item_type == item_type and s.count < max_stack:
			var space: int = max_stack - s.count
			var added: int = min(space, remaining)
			s.count += added
			remaining -= added
	# Pass 2: fill empty slots.
	for s in slots:
		if remaining <= 0:
			break
		if s.is_empty():
			var added: int = min(max_stack, remaining)
			s.item_type = item_type
			s.count = added
			remaining -= added
	return count - remaining

## True iff `add(item_type, count)` would accept all `count` items without
## dropping any. Read-only — does not mutate the inventory. Mirrors `add`'s
## two-pass logic (top up matching stacks, then fill empty slots).
func has_room_for(item_type: int, count: int) -> bool:
	if count <= 0 or item_type < 0:
		return true
	var max_stack: int = Items.max_stack_of(item_type)
	var remaining: int = count
	for s in slots:
		if remaining <= 0:
			return true
		if s.item_type == item_type and s.count < max_stack:
			remaining -= min(max_stack - s.count, remaining)
	for s in slots:
		if remaining <= 0:
			return true
		if s.is_empty():
			remaining -= min(max_stack, remaining)
	return remaining <= 0

## Remove up to `count` items of `item_type`. Returns count actually removed.
func remove(item_type: int, count: int) -> int:
	if count <= 0 or item_type < 0:
		return 0
	var remaining: int = count
	for s in slots:
		if remaining <= 0:
			break
		if s.item_type == item_type and s.count > 0:
			var taken: int = min(s.count, remaining)
			s.count -= taken
			remaining -= taken
			if s.count <= 0:
				s.clear()
	return count - remaining

## Total count of an item type across all stacks.
func total_of(item_type: int) -> int:
	var n: int = 0
	for s in slots:
		if s.item_type == item_type:
			n += s.count
	return n

## True if every slot is empty.
func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true

## Count of slots currently holding any item. Used by the inventory panel
## to display "Slots: A/B used" so capacity changes (e.g., bag consumption
## growing capacity) are visible to the player. Aggregate display by item
## type hides the slot dimension; this exposes it.
func slots_used() -> int:
	var n: int = 0
	for s in slots:
		if not s.is_empty():
			n += 1
	return n

## Total items across all stacks. Useful for capacity-style checks.
func total_count() -> int:
	var n: int = 0
	for s in slots:
		n += s.count
	return n

## Aggregate by item type for compact display. Returns Dictionary[int -> int].
func aggregate() -> Dictionary:
	var agg: Dictionary = {}
	for s in slots:
		if s.is_empty():
			continue
		agg[s.item_type] = agg.get(s.item_type, 0) + s.count
	return agg

## Grow capacity by `n` empty slots. Existing items are unaffected.
## Generic primitive — used by the bag-cap mechanic and any future
## inventory-upgrade source (quest rewards, NPC trade, etc.).
##
## No-op if `n <= 0`. Slots are appended (not prepended), so existing
## stack indices remain stable for any code that holds slot references.
func expand(n: int) -> void:
	if n <= 0:
		return
	capacity += n
	for i in n:
		slots.append(ItemStack.new())

func to_array() -> Array:
	var out: Array = []
	for s in slots:
		out.append([s.item_type, s.count])
	return out

## Rebuild this inventory from `to_array()` output. Returns the number of rows
## that could not be read and were dropped.
##
## THE RETURN VALUE IS NOT DECORATION. It is the only way the caller learns that
## slots went missing, and `SaveSystem.load_game` folds it into
## `LoadResult.skipped_entries` so `main.gd`'s toast says so.
##
## Why each row is guarded rather than trusted. `arr` is player-authored data —
## saves "may have been hand-edited, partially corrupted" (CONVENTIONS.md) — and
## an unguarded `entry[1]` here does NOT fail the load. A GDScript runtime error
## aborts only the INNERMOST function, so it killed `load_array` alone and
## `load_game` carried on to `result.success = true`: every slot from the bad
## row onward was silently never written, the player was told the world loaded
## cleanly, and the next F5 wrote the truncated inventory over the only save
## slot. That is quieter and worse than a crash, which is why the fix is a guard
## plus a count rather than a guard alone.
##
## The `slots[i].clear()` is load-bearing on the NO-RESIZE path. When `arr.size()`
## already equals `capacity` the slots are reused in place, so a row skipped
## without clearing would leave whatever the live inventory held there — and
## `main.gd`'s F9 quick-load passes the standing `player_inventory`, so that is
## the player's CURRENT item surviving into a slot the save could not describe.
## An unreadable row means "this slot is unknown", so it is emptied.
##
## `int(entry[0])` on a partially-readable row is not a middle ground worth
## taking: a one-element `[7]` would leave item id 7 with count 0, and a String
## row leaves id 0, both of which read as real item ids to everything downstream.
## A row is taken whole or dropped whole.
func load_array(arr: Array) -> int:
	# Resize if needed.
	if arr.size() != capacity:
		capacity = arr.size()
		slots = []
		for i in capacity:
			slots.append(ItemStack.new())
	var skipped: int = 0
	for i in capacity:
		var entry = arr[i]
		if not (entry is Array and entry.size() >= 2):
			push_warning("Inventory.load_array: skipping malformed slot %d: %s" % [i, str(entry)])
			slots[i].clear()
			skipped += 1
			continue
		slots[i].item_type = int(entry[0])
		slots[i].count = int(entry[1])
	return skipped
