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

func to_array() -> Array:
	var out: Array = []
	for s in slots:
		out.append([s.item_type, s.count])
	return out

func load_array(arr: Array) -> void:
	# Resize if needed.
	if arr.size() != capacity:
		capacity = arr.size()
		slots = []
		for i in capacity:
			slots.append(ItemStack.new())
	for i in capacity:
		var entry = arr[i]
		slots[i].item_type = int(entry[0])
		slots[i].count = int(entry[1])
