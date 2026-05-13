class_name SlotClickHandler
extends RefCounted

## Shared click-handling logic for slot widgets (player inventory, chest,
## building input/output/fuel/filter). See spec:
## docs/superpowers/specs/2026-05-10-qol-cluster-a-design.md
##
## Static module — mirrors Burner / Processor / Inserter / Belt pattern.
## Pure functions; no scene-tree dependency.

const MOD_NONE: int = 0
const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2

## Returns ceil(n / 2). The shared half-split math used by every kind's
## shift+LMB branch. Always non-negative; split_half(0) = 0.
static func split_half(n: int) -> int:
	if n <= 0:
		return 0
	return int(ceil(n / 2.0))


## Player-slot click (LMB / shift+LMB / ctrl+LMB).
## Mutates `slot` and `cursor` in place. `mods` is a bitfield of MOD_*.
##
## Plain LMB (mods == MOD_NONE) replicates the pre-extraction behavior
## from BuildingPanel._handle_player_slot_click and
## inventory_grid._handle_left_click_player byte-for-byte.
##
## (shift/ctrl branches added in Phase 2 / Phase 3.)
static func handle_player_slot(slot: ItemStack, cursor: CursorStack, mods: int) -> void:
	# Plain LMB path.
	if not cursor.has_item():
		# Empty cursor → pick up slot's stack.
		if slot.is_empty():
			return
		cursor.pick(slot.item_type, slot.count)
		slot.clear()
		return
	# Cursor has item → place / merge / swap.
	if slot.is_empty():
		slot.item_type = cursor.item_type
		slot.count = cursor.count
		cursor.clear()
		return
	if slot.item_type == cursor.item_type:
		var max_stack: int = Items.max_stack_of(slot.item_type)
		var space: int = max_stack - slot.count
		var moved: int = min(space, cursor.count)
		slot.count += moved
		cursor.count -= moved
		if cursor.count <= 0:
			cursor.clear()
		return
	# Different types → swap.
	var tmp_t: int = slot.item_type
	var tmp_c: int = slot.count
	slot.item_type = cursor.item_type
	slot.count = cursor.count
	cursor.pick(tmp_t, tmp_c)
