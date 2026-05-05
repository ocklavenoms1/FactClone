extends RefCounted

## Chest paired view test — locks the view-adapter splitting logic and the
## underlying transfer primitives that the InventoryGrid click handlers
## orchestrate. Doesn't simulate clicks; tests the state-transition layer
## directly so the unit scope stays clean.
##
## Three phases:
##   1. View adapter: chest bag → slot views (max_stack-sized splits).
##   2. Player → chest deposit semantics (mirror shift-click player→chest).
##   3. Chest → player pickup semantics with overflow (mirror shift-click
##      chest→player when player can't fit the whole stack).

# NOTE (session-building-ui-2): chest paired-view was removed from
# inventory_grid.gd; the bag→slot-views adapter moved to SlotWidget.
# Test still locks in the SAME pure adapter logic + the chest transfer
# primitives the new ChestPanel relies on.

static func test_name() -> String:
	return "chest paired view (adapter + transfer semantics)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	# --- Phase 1: view adapter ---
	# 250 grain (max_stack 100) → [100, 100, 50]
	var bag1: Array = [[Items.Type.GRAIN, 250]]
	var views1: Array = SlotWidget.chest_bag_to_slot_views(bag1)
	_check(failures, views1.size() == 3, "250 grain should split into 3 views; got %d" % views1.size())
	if views1.size() == 3:
		_check(failures, int(views1[0]["count"]) == 100, "view 0 count: expected 100, got %d" % int(views1[0]["count"]))
		_check(failures, int(views1[1]["count"]) == 100, "view 1 count: expected 100, got %d" % int(views1[1]["count"]))
		_check(failures, int(views1[2]["count"]) == 50, "view 2 count: expected 50 (remainder), got %d" % int(views1[2]["count"]))
		for v in views1:
			_check(failures, int(v["item_type"]) == Items.Type.GRAIN, "view item_type should be GRAIN")

	# Multi-type bag: 100 grain + 50 flour → 2 views [grain 100, flour 50]
	var bag2: Array = [[Items.Type.GRAIN, 100], [Items.Type.FLOUR, 50]]
	var views2: Array = SlotWidget.chest_bag_to_slot_views(bag2)
	_check(failures, views2.size() == 2, "2 entries each within max_stack should yield 2 views; got %d" % views2.size())
	if views2.size() == 2:
		_check(failures, int(views2[0]["item_type"]) == Items.Type.GRAIN, "view 0 type: expected GRAIN")
		_check(failures, int(views2[1]["item_type"]) == Items.Type.FLOUR, "view 1 type: expected FLOUR")

	# Empty bag → empty views.
	var views3: Array = SlotWidget.chest_bag_to_slot_views([])
	_check(failures, views3.size() == 0, "empty bag → empty views; got %d" % views3.size())

	# Edge: count exactly at max_stack → 1 view, not 2.
	var bag4: Array = [[Items.Type.GRAIN, 100]]
	var views4: Array = SlotWidget.chest_bag_to_slot_views(bag4)
	_check(failures, views4.size() == 1, "exactly max_stack → 1 view (not 1+0 split); got %d" % views4.size())

	# --- Phase 2: Player → chest deposit (shift-click player→chest) ---
	# Mirrors _handle_shift_click(GRID_PLAYER, slot_idx) when chest has room.
	var inv: Inventory = Inventory.new(16)
	inv.add(Items.Type.WHEAT, 100)
	var chest: Building = Chest.make(Vector2i(0, 0))
	# Chest free capacity must be >= 100 for the test to be meaningful.
	_check(failures, Chest.free_capacity(chest) >= 100, "preflight: chest must have room")

	var src_slot: ItemStack = inv.slots[0]
	_check(failures, src_slot.item_type == Items.Type.WHEAT and src_slot.count == 100, "preflight: 100 wheat in player slot 0")

	var free: int = Chest.free_capacity(chest)
	var moved: int = min(src_slot.count, free)
	Chest._bag_add(chest.state["bag"], src_slot.item_type, moved)
	src_slot.count -= moved
	if src_slot.count <= 0:
		src_slot.clear()

	_check(failures, src_slot.is_empty(), "after deposit: player slot 0 empty")
	_check(failures, Chest.total_items(chest) == 100, "after deposit: chest holds 100 wheat; got %d" % Chest.total_items(chest))

	# --- Phase 3: Chest → player pickup with player full ---
	# Mirrors _handle_shift_click(GRID_CHEST, ...) — calls inventory.add()
	# which respects max_stack across player slots; partial-add returns the
	# count actually added, leaving the rest in the chest.
	var inv2: Inventory = Inventory.new(2)  # only 2 slots
	# Pre-fill BOTH slots with full FLOUR stacks so the player has zero room.
	inv2.add(Items.Type.FLOUR, Items.max_stack_of(Items.Type.FLOUR))
	inv2.add(Items.Type.FLOUR, Items.max_stack_of(Items.Type.FLOUR))
	_check(failures, inv2.slots[0].count == 100 and inv2.slots[1].count == 100, "preflight: both player slots full of flour")

	var chest2: Building = Chest.make(Vector2i(0, 0))
	Chest._bag_add(chest2.state["bag"], Items.Type.GRAIN, 50)
	# Pick view 0 → grain 50. Try to add to player. Should add 0 (no room
	# for grain — both slots full of flour). Chest stays at 50 grain.
	var views: Array = SlotWidget.chest_bag_to_slot_views(chest2.state["bag"])
	_check(failures, views.size() == 1, "preflight: chest has 1 view (50 grain)")
	var v = views[0]
	var added: int = inv2.add(int(v["item_type"]), int(v["count"]))
	if added > 0:
		Chest._bag_remove(chest2.state["bag"], int(v["item_type"]), added)
	_check(failures, added == 0, "with player full, transfer should add 0; got %d" % added)
	_check(failures, Chest.total_items(chest2) == 50, "chest unchanged after refused transfer; got %d" % Chest.total_items(chest2))

	# Variant: partial transfer (player has room for some, not all).
	var inv3: Inventory = Inventory.new(2)
	inv3.add(Items.Type.GRAIN, 80)  # one slot, partial — room for 20 more
	# Second slot empty → another full max_stack of room (100).
	# So total room for grain = 20 + 100 = 120.
	var chest3: Building = Chest.make(Vector2i(0, 0))
	Chest._bag_add(chest3.state["bag"], Items.Type.GRAIN, 200)  # > player room
	# Player picks up first chest view (grain 100). inventory.add(GRAIN, 100):
	#   pass 1: top up slot 0 from 80 → 100, +20.
	#   pass 2: fill slot 1 with 80 grain (remaining), +80.
	# Total added: 100 (the entire view). Chest drops to 100.
	var views3b: Array = SlotWidget.chest_bag_to_slot_views(chest3.state["bag"])
	_check(failures, int(views3b[0]["count"]) == 100, "preflight: first chest view is 100 grain (max_stack)")
	var added3: int = inv3.add(int(views3b[0]["item_type"]), int(views3b[0]["count"]))
	if added3 > 0:
		Chest._bag_remove(chest3.state["bag"], int(views3b[0]["item_type"]), added3)
	_check(failures, added3 == 100, "partial-room: should add full 100; got %d" % added3)
	_check(failures, Chest.total_items(chest3) == 100, "chest after partial transfer: 100 grain remaining; got %d" % Chest.total_items(chest3))

	if failures.is_empty():
		return { "ok": true, "message": "view adapter splits correctly; chest↔player transfer semantics consistent" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
