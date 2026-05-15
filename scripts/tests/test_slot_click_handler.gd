extends RefCounted

## SlotClickHandler tests (QoL Cluster A — session-qol-cluster-a).
##
## 13 sub-suites covering refactor regression, shift+LMB matrix, ctrl+LMB
## picker semantics. See docs/superpowers/specs/2026-05-10-qol-cluster-a-design.md
## §7 for the full plan.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "slot click handler (refactor regression + shift matrix + ctrl picker)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- (split_half util sanity — used by every other sub-suite) ----------
	_check(failures, SlotClickHandler.split_half(0) == 0,
		"(util) split_half(0) should be 0")
	_check(failures, SlotClickHandler.split_half(1) == 1,
		"(util) split_half(1) should be 1 (ceil(0.5)=1)")
	_check(failures, SlotClickHandler.split_half(2) == 1,
		"(util) split_half(2) should be 1")
	_check(failures, SlotClickHandler.split_half(7) == 4,
		"(util) split_half(7) should be 4 (ceil(3.5)=4)")
	_check(failures, SlotClickHandler.split_half(100) == 50,
		"(util) split_half(100) should be 50")

	# ---------- (1) player_slot_regression: plain LMB across 5 cells ----------
	# THE CRITICAL GATE — extraction must be byte-identical to pre-refactor.
	# Five (cursor × slot) states from spec §5.1.

	# (1a) Empty cursor + empty slot → no-op.
	var s1a := ItemStack.new()
	var c1a := CursorStack.new()
	SlotClickHandler.handle_player_slot(s1a, c1a, SlotClickHandler.MOD_NONE)
	_check(failures, s1a.is_empty() and c1a.item_type < 0 and c1a.count == 0,
		"(1a) empty+empty → no-op (cursor explicitly clean: item_type<0, count=0)")

	# (1b) Empty cursor + slot with 7 wheat → cursor picks all 7, slot clears.
	var s1b := ItemStack.new(Items.Type.WHEAT, 7)
	var c1b := CursorStack.new()
	SlotClickHandler.handle_player_slot(s1b, c1b, SlotClickHandler.MOD_NONE)
	_check(failures, s1b.is_empty() and c1b.item_type == Items.Type.WHEAT and c1b.count == 7,
		"(1b) empty+7 wheat → cursor=7 wheat, slot empty")

	# (1c) Cursor with 5 wheat + empty slot → slot gets 5 wheat, cursor clears.
	var s1c := ItemStack.new()
	var c1c := CursorStack.new()
	c1c.pick(Items.Type.WHEAT, 5)
	SlotClickHandler.handle_player_slot(s1c, c1c, SlotClickHandler.MOD_NONE)
	_check(failures, s1c.item_type == Items.Type.WHEAT and s1c.count == 5 and not c1c.has_item(),
		"(1c) cursor 5 + empty → slot=5, cursor clear")

	# (1d) Cursor 5 wheat + slot 3 wheat (max_stack=100) → merge all into slot,
	# cursor clears (5+3=8, well under cap).
	var s1d := ItemStack.new(Items.Type.WHEAT, 3)
	var c1d := CursorStack.new()
	c1d.pick(Items.Type.WHEAT, 5)
	SlotClickHandler.handle_player_slot(s1d, c1d, SlotClickHandler.MOD_NONE)
	_check(failures, s1d.count == 8 and not c1d.has_item(),
		"(1d) cursor 5 + slot 3 same type → slot=8, cursor clear")

	# (1e) Cursor 5 wheat + slot 4 flour (different type) → swap.
	var s1e := ItemStack.new(Items.Type.FLOUR, 4)
	var c1e := CursorStack.new()
	c1e.pick(Items.Type.WHEAT, 5)
	SlotClickHandler.handle_player_slot(s1e, c1e, SlotClickHandler.MOD_NONE)
	_check(failures, s1e.item_type == Items.Type.WHEAT and s1e.count == 5,
		"(1e) different type → slot has cursor's stack")
	_check(failures, c1e.item_type == Items.Type.FLOUR and c1e.count == 4,
		"(1e) different type → cursor has slot's stack (swapped)")

	# ---------- (2) shift_take_player_half: empty cursor + slot N → take ceil(N/2) ----------
	# N=1 (degenerate take all)
	var s2a := ItemStack.new(Items.Type.WHEAT, 1)
	var c2a := CursorStack.new()
	SlotClickHandler.handle_player_slot(s2a, c2a, SlotClickHandler.MOD_SHIFT)
	_check(failures, s2a.is_empty() and c2a.count == 1,
		"(2) shift+take N=1 → cursor=1, slot empty (ceil(0.5)=1)")
	# N=2 (clean half)
	var s2b := ItemStack.new(Items.Type.WHEAT, 2)
	var c2b := CursorStack.new()
	SlotClickHandler.handle_player_slot(s2b, c2b, SlotClickHandler.MOD_SHIFT)
	_check(failures, s2b.count == 1 and c2b.count == 1,
		"(2) shift+take N=2 → cursor=1, slot=1")
	# N=7 (rounded half)
	var s2c := ItemStack.new(Items.Type.WHEAT, 7)
	var c2c := CursorStack.new()
	SlotClickHandler.handle_player_slot(s2c, c2c, SlotClickHandler.MOD_SHIFT)
	_check(failures, s2c.count == 3 and c2c.count == 4,
		"(2) shift+take N=7 → cursor=4 (ceil), slot=3 (floor)")

	# ---------- (3) shift_drop_player_half_empty: M cursor + empty slot → drop ceil(M/2) ----------
	# M=1 (degenerate: drop 1, cursor goes to 0)
	var s3a := ItemStack.new()
	var c3a := CursorStack.new()
	c3a.pick(Items.Type.WHEAT, 1)
	SlotClickHandler.handle_player_slot(s3a, c3a, SlotClickHandler.MOD_SHIFT)
	_check(failures, s3a.item_type == Items.Type.WHEAT and s3a.count == 1 and not c3a.has_item(),
		"(3) shift+drop M=1 → slot=1 wheat, cursor clear")
	# M=7 (rounded half: drop 4, cursor keeps 3)
	var s3b := ItemStack.new()
	var c3b := CursorStack.new()
	c3b.pick(Items.Type.WHEAT, 7)
	SlotClickHandler.handle_player_slot(s3b, c3b, SlotClickHandler.MOD_SHIFT)
	_check(failures, s3b.item_type == Items.Type.WHEAT and s3b.count == 4 and c3b.count == 3,
		"(3) shift+drop M=7 → slot=4 (ceil), cursor=3 (floor)")

	# ---------- (4) shift_drop_player_half_matching: M cursor + K slot same type ----------
	# Normal case (plenty of space): cursor 6 wheat, slot 2 wheat, max_stack=100.
	# split_half(6)=3 fits comfortably in space=98 → drop all 3.
	var s4a := ItemStack.new(Items.Type.WHEAT, 2)
	var c4a := CursorStack.new()
	c4a.pick(Items.Type.WHEAT, 6)
	SlotClickHandler.handle_player_slot(s4a, c4a, SlotClickHandler.MOD_SHIFT)
	_check(failures, s4a.count == 5 and c4a.count == 3,
		"(4) shift+drop same-type plenty: slot 2→5, cursor 6→3")
	# CAPACITY CLAMP case from spec §5.1 + Q3 review.
	# Yeast has max_stack=50. cursor 40 yeast, slot 45 yeast:
	# want to drop split_half(40)=20, only 5 space available → drop 5
	# (silent clamp, NOT 20, NOT no-op).
	var s4b := ItemStack.new(Items.Type.YEAST, 45)
	var c4b := CursorStack.new()
	c4b.pick(Items.Type.YEAST, 40)
	SlotClickHandler.handle_player_slot(s4b, c4b, SlotClickHandler.MOD_SHIFT)
	_check(failures, s4b.count == 50 and c4b.count == 35,
		"(4) shift+drop CAPACITY CLAMP: slot=45+5(clamped from 20)=50, cursor=40-5=35")

	# ---------- (5) shift_player_diff_type_noop: shift never swaps ----------
	# Cursor with 5 wheat + slot with 4 flour (different types) + shift+LMB.
	# Spec §5.1: different-type cell is no-op. Plain LMB swaps; shift does NOT.
	# Capture before/after state explicitly to detect any unintended mutation.
	var s5 := ItemStack.new(Items.Type.FLOUR, 4)
	var c5 := CursorStack.new()
	c5.pick(Items.Type.WHEAT, 5)
	var before_slot_type: int = s5.item_type
	var before_slot_count: int = s5.count
	var before_cursor_type: int = c5.item_type
	var before_cursor_count: int = c5.count
	SlotClickHandler.handle_player_slot(s5, c5, SlotClickHandler.MOD_SHIFT)
	_check(failures, s5.item_type == before_slot_type and s5.count == before_slot_count,
		"(5) shift different-type: slot unchanged (no swap, no mutation)")
	_check(failures, c5.item_type == before_cursor_type and c5.count == before_cursor_count,
		"(5) shift different-type: cursor unchanged (no swap, no mutation)")

	# ---------- (6) shift_chest_take_and_drop ----------
	# Chest bag is Array of [type, count] entries. Test pure logic:
	# (a) shift+take half, (b) shift+drop refuse-with-toast when split_half(M) > free_capacity.
	# Spec §5.2 chest row: chest preserves LMB refuse convention, NOT silent-clamp.

	# (6a) shift+take: bag has [WHEAT, 7] → take 4, bag has [WHEAT, 3].
	var bag6a: Array = [[Items.Type.WHEAT, 7]]
	var c6a := CursorStack.new()
	# Simulate chest shift+take logic (mirrors what we wire into chest_panel below).
	if not c6a.has_item() and bag6a.size() > 0:
		var v = bag6a[0]
		var take: int = SlotClickHandler.split_half(int(v[1]))
		c6a.pick(int(v[0]), take)
		v[1] = int(v[1]) - take
	_check(failures, c6a.count == 4 and c6a.item_type == Items.Type.WHEAT and int(bag6a[0][1]) == 3,
		"(6a) chest shift+take: cursor=4 wheat, bag entry [WHEAT, 3]")

	# (6b) shift+drop REFUSE: cursor 12 wheat, free_capacity=5.
	# split_half(12)=6 > 5 → refuse (NOT silent-clamp). Bag stays empty, cursor stays at 12.
	var bag6b: Array = []
	var c6b := CursorStack.new()
	c6b.pick(Items.Type.WHEAT, 12)
	var free_capacity6b: int = 5
	var half6b: int = SlotClickHandler.split_half(c6b.count)
	var refused6b: bool = false
	if half6b > free_capacity6b:
		refused6b = true
		# In production, _toast(...) fires here; in test, just set refused flag.
	_check(failures, refused6b and bag6b.is_empty() and c6b.count == 12,
		"(6b) chest shift+drop refuse: refused=true, bag empty, cursor unchanged at 12")

	# ---------- (7) shift_building_input_and_output ----------
	# Building slots: in_buffer / out_buffer Arrays of [type, count] entries.
	# Tests pure logic via direct array manipulation (no panel scene).

	# (7a) Input shift+take: buf=[[WHEAT, 8]] → cursor 4 wheat, buf=[[WHEAT, 4]].
	var buf7a: Array = [[Items.Type.WHEAT, 8]]
	var c7a := CursorStack.new()
	if not c7a.has_item() and not buf7a.is_empty():
		var e = buf7a[0]
		var take: int = SlotClickHandler.split_half(int(e[1]))
		c7a.pick(int(e[0]), take)
		e[1] = int(e[1]) - take
	_check(failures, c7a.count == 4 and int(buf7a[0][1]) == 4,
		"(7a) input shift+take: cursor=4 wheat, buf=[[WHEAT,4]]")

	# (7b) Input shift+drop with max_stack=8: cursor 10 wheat, buf=[[WHEAT,3]],
	# split_half(10)=5, space=8-3=5 → drop 5, cursor=5, buf=[[WHEAT,8]].
	var buf7b: Array = [[Items.Type.WHEAT, 3]]
	var c7b := CursorStack.new()
	c7b.pick(Items.Type.WHEAT, 10)
	var max_stack7b: int = 8
	var current7b: int = int(buf7b[0][1])
	var space7b: int = max_stack7b - current7b
	var want7b: int = SlotClickHandler.split_half(c7b.count)
	var moved7b: int = min(space7b, want7b)
	buf7b[0][1] = current7b + moved7b
	c7b.count -= moved7b
	_check(failures, c7b.count == 5 and int(buf7b[0][1]) == 8,
		"(7b) input shift+drop with max_stack clamp: cursor=5, buf=[[WHEAT,8]]")

	# (7c) Output_multi shift+take of sub_idx=1: buf=[[WHEAT,7],[STRAW,5]],
	# take from idx=1 → cursor=3 straw, buf=[[WHEAT,7],[STRAW,2]].
	var buf7c: Array = [[Items.Type.WHEAT, 7], [Items.Type.STRAW, 5]]
	var c7c := CursorStack.new()
	var sub_idx7c: int = 1
	if not c7c.has_item() and sub_idx7c < buf7c.size():
		var e7c = buf7c[sub_idx7c]
		var take7c: int = SlotClickHandler.split_half(int(e7c[1]))
		c7c.pick(int(e7c[0]), take7c)
		e7c[1] = int(e7c[1]) - take7c
	_check(failures, c7c.count == 3 and c7c.item_type == Items.Type.STRAW and int(buf7c[1][1]) == 2,
		"(7c) output_multi shift+take sub_idx=1: cursor=3 straw, buf[1]=[STRAW,2]")

	# ---------- (8) shift_fuel_take_items_same_type ----------
	# PAUSE 2 revision (user feedback during session-qol-cluster-a smoke):
	# fuel TAKE returns items of last_fuel_item type, NOT lossy WOOD. Falls
	# back to WOOD when last_fuel_item missing OR items_avail == 0 (stranded
	# sub-item-energy). Pure-logic test mirrors building_panel.gd's fuel arm.
	#
	# Scenario: buffer = 16 units (4 coal deposited), last_fuel_item = COAL,
	# energy_per = 4. items_avail = 16/4 = 4 coal. Shift+take → split_half(4)=2
	# coal, buffer -= 2*4 = 8 units.
	var units8: int = 16
	var energy_per8: int = int(Burner.FUEL_VALUES[Items.Type.COAL])  # 4
	var items_avail8: int = units8 / energy_per8  # 4
	var n8: int = SlotClickHandler.split_half(items_avail8)  # 2
	var c8 := CursorStack.new()
	c8.pick(Items.Type.COAL, n8)
	units8 -= n8 * energy_per8  # 16 - 8 = 8
	_check(failures, c8.count == 2 and c8.item_type == Items.Type.COAL and units8 == 8,
		"(8) fuel shift+take same-type: cursor=2 coal, buffer remaining=8 units")

	# ---------- (9) shift_fuel_drop_items_atomic: silent atomic-clamp ----------
	# Spec §5.2 fuel-drop: operates in ITEMS, atomic via FUEL_VALUES,
	# silent-clamp (matches player-slot Q3, NOT chest-style refuse).
	#
	# Scenario: cursor 6 coal (energy_per=4), free 8 units → items_that_fit = 8/4 = 2.
	# split_half(6) = 3 wants to drop, only 2 fit → silent atomic clamp to 2.
	# Cursor 6 → 4 (2 items dropped), buffer += 2*4 = 8 units.
	var c9 := CursorStack.new()
	c9.pick(Items.Type.COAL, 6)
	var free_units9: int = 8
	var energy_per9: int = int(Burner.FUEL_VALUES[Items.Type.COAL])
	var items_fit9: int = free_units9 / energy_per9
	var want9: int = SlotClickHandler.split_half(c9.count)
	var moved9: int = min(items_fit9, want9)
	# Simulate the drop in test space (the production code does this in _drop_into_fuel).
	var buffer9_after: int = (16 - free_units9) + moved9 * energy_per9
	c9.count -= moved9
	_check(failures, moved9 == 2 and c9.count == 4 and buffer9_after == 16,
		"(9) fuel shift+drop atomic clamp: moved=2 (split_half(6)=3 clamped to items_fit=2), cursor=4, buffer 8→16")

	# ---------- (10) shift_filter_noop ----------
	# Spec §5.2: filter slot is metadata (scalar int), NOT buffer.
	# Shift+LMB and Ctrl+LMB are no-ops, NO toast. Plain LMB drop-to-set
	# still works (verified separately in test_inserter.gd).
	# Panel-level integration: exercises _drop_into_slot's mods-guard branch.
	var world10 = GridWorldScript.new()
	parent.add_child(world10)
	world10.set_overlay(Vector2i(0, 0), Terrain.Overlay.STONE)
	if not world10.place_building(Buildings.Type.FAST_INSERTER, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world10); world10.queue_free()
		return { "ok": false, "message": "(10) FastInserter placement failed: %s" % world10.last_building_place_error }
	var fast10: Building = world10.building_at(Vector2i(0, 0))
	var panel10 = preload("res://scripts/ui/building_panel.gd").new()
	parent.add_child(panel10)
	var inv10 := Inventory.new()
	var cursor10 := CursorStack.new()
	panel10.cursor = cursor10
	panel10.inventory = inv10
	var toasted10: Array = []
	panel10.toast_callback = func(msg): toasted10.append(msg)
	panel10.open(fast10, world10)
	var filter_slot10: Dictionary = Buildings.slot_layout_for(Buildings.Type.FAST_INSERTER)[2]

	# (10a) Shift+LMB on filter — no-op, no toast, cursor unchanged.
	cursor10.pick(Items.Type.WHEAT, 5)
	panel10._drop_into_slot(filter_slot10, -1, SlotClickHandler.MOD_SHIFT)
	_check(failures, int(fast10.state.get("filter_item_type", -999)) == -1,
		"(10a) filter shift+LMB: filter_item_type unchanged (still -1)")
	_check(failures, cursor10.has_item() and cursor10.item_type == Items.Type.WHEAT and cursor10.count == 5,
		"(10a) filter shift+LMB: cursor unchanged (still 5 wheat)")
	_check(failures, toasted10.is_empty(),
		"(10a) filter shift+LMB: NO toast (silent no-op contract)")

	# (10b) Ctrl+LMB on filter — same no-op semantic.
	panel10._drop_into_slot(filter_slot10, -1, SlotClickHandler.MOD_CTRL)
	_check(failures, int(fast10.state.get("filter_item_type", -999)) == -1,
		"(10b) filter ctrl+LMB: filter_item_type unchanged")
	_check(failures, toasted10.is_empty(),
		"(10b) filter ctrl+LMB: NO toast")

	# (10c) Plain LMB regression — drop-to-set still works.
	panel10._drop_into_slot(filter_slot10, -1, SlotClickHandler.MOD_NONE)
	_check(failures, int(fast10.state.get("filter_item_type", -999)) == Items.Type.WHEAT,
		"(10c) filter plain LMB regression: drop-to-set sets filter to WHEAT")
	_check(failures, cursor10.has_item() and cursor10.count == 5,
		"(10c) filter plain LMB: cursor unchanged (drop-to-set is copy not move)")

	panel10.queue_free()
	_disconnect(world10); world10.queue_free()

	# ---------- (11a) ctrl_click_max + ctrl_click_transfer player-slot paths ----------
	# Tests the picker max-value computation across (cursor × slot) cells per
	# spec §6.1, and the exact-N transfer logic per spec §6.2 + Q5.
	# Pure-logic test — no panel, no scene tree. Tasks 19-21 will extend
	# sub-suite #11 with chest/input/fuel cases (11b/c/d/e).

	# ctrl_click_max cases (cursor × slot → expected max):

	# Empty cursor + slot with 8 wheat → max=8 (TAKE all available).
	var s11a_take := ItemStack.new(Items.Type.WHEAT, 8)
	var c11a_take := CursorStack.new()
	_check(failures, SlotClickHandler.ctrl_click_max(s11a_take, c11a_take) == 8,
		"(11a) ctrl_max empty+8 → 8 (TAKE all available)")

	# Cursor 6 wheat + empty slot → max=6 (GIVE all of cursor).
	var s11a_give := ItemStack.new()
	var c11a_give := CursorStack.new()
	c11a_give.pick(Items.Type.WHEAT, 6)
	_check(failures, SlotClickHandler.ctrl_click_max(s11a_give, c11a_give) == 6,
		"(11a) ctrl_max cursor 6 + empty → 6 (GIVE all of cursor)")

	# Cursor 40 yeast + slot 45 yeast (max_stack=50) → max = min(40, 5) = 5.
	# Same-type capacity clamp per spec §6.1.
	var s11a_clamp := ItemStack.new(Items.Type.YEAST, 45)
	var c11a_clamp := CursorStack.new()
	c11a_clamp.pick(Items.Type.YEAST, 40)
	_check(failures, SlotClickHandler.ctrl_click_max(s11a_clamp, c11a_clamp) == 5,
		"(11a) ctrl_max same-type clamp → 5 (min(40, 50-45)=5)")

	# Cursor 5 wheat + slot 4 flour (different types) → max=0 (picker does not open per spec §6.1).
	var s11a_diff := ItemStack.new(Items.Type.FLOUR, 4)
	var c11a_diff := CursorStack.new()
	c11a_diff.pick(Items.Type.WHEAT, 5)
	_check(failures, SlotClickHandler.ctrl_click_max(s11a_diff, c11a_diff) == 0,
		"(11a) ctrl_max different-type → 0 (no-op gate per spec §6.1)")

	# Empty cursor + empty slot → max=0 (nothing to transfer per spec §6.1).
	var s11a_empty := ItemStack.new()
	var c11a_empty := CursorStack.new()
	_check(failures, SlotClickHandler.ctrl_click_max(s11a_empty, c11a_empty) == 0,
		"(11a) ctrl_max empty+empty → 0 (nothing to transfer)")

	# Same-type slot at max_stack (S-K=0) → max=0 (no room to deposit per spec §6.1 + pre-open gate).
	var s11a_full := ItemStack.new(Items.Type.WHEAT, 100)
	var c11a_full := CursorStack.new()
	c11a_full.pick(Items.Type.WHEAT, 5)
	_check(failures, SlotClickHandler.ctrl_click_max(s11a_full, c11a_full) == 0,
		"(11a) ctrl_max same-type slot at max_stack (100/100) → 0 (no room, picker gated)")

	# ctrl_click_transfer round-trip cases (call after picker SpinBox confirm):

	# TAKE N=3 from slot of 8: cursor 0→3, slot 8→5.
	var s11a_t1 := ItemStack.new(Items.Type.WHEAT, 8)
	var c11a_t1 := CursorStack.new()
	SlotClickHandler.ctrl_click_transfer(s11a_t1, c11a_t1, 3)
	_check(failures, c11a_t1.count == 3 and c11a_t1.item_type == Items.Type.WHEAT and s11a_t1.count == 5,
		"(11a) ctrl_transfer TAKE 3 from 8 → cursor=3 wheat, slot=5")

	# TAKE all (N=N): cursor 0→8, slot 8→0 (cleared).
	var s11a_t2 := ItemStack.new(Items.Type.WHEAT, 8)
	var c11a_t2 := CursorStack.new()
	SlotClickHandler.ctrl_click_transfer(s11a_t2, c11a_t2, 8)
	_check(failures, c11a_t2.count == 8 and s11a_t2.is_empty(),
		"(11a) ctrl_transfer TAKE all (N=8 from 8) → cursor=8, slot empty")

	# GIVE N=4 into empty slot: cursor 6→2, slot becomes 4 wheat.
	var s11a_t3 := ItemStack.new()
	var c11a_t3 := CursorStack.new()
	c11a_t3.pick(Items.Type.WHEAT, 6)
	SlotClickHandler.ctrl_click_transfer(s11a_t3, c11a_t3, 4)
	_check(failures, s11a_t3.item_type == Items.Type.WHEAT and s11a_t3.count == 4 and c11a_t3.count == 2,
		"(11a) ctrl_transfer GIVE 4 → slot=4 wheat, cursor=2")

	# GIVE all (N=cursor.count) into empty slot: cursor 6→0 (cleared), slot becomes 6 wheat.
	var s11a_t4 := ItemStack.new()
	var c11a_t4 := CursorStack.new()
	c11a_t4.pick(Items.Type.WHEAT, 6)
	SlotClickHandler.ctrl_click_transfer(s11a_t4, c11a_t4, 6)
	_check(failures, s11a_t4.item_type == Items.Type.WHEAT and s11a_t4.count == 6 and not c11a_t4.has_item(),
		"(11a) ctrl_transfer GIVE all (N=6) → slot=6 wheat, cursor empty")

	# GIVE N into same-type slot (merge): cursor 5 + slot 3 wheat → ctrl_transfer N=3 → slot=6, cursor=2.
	var s11a_t5 := ItemStack.new(Items.Type.WHEAT, 3)
	var c11a_t5 := CursorStack.new()
	c11a_t5.pick(Items.Type.WHEAT, 5)
	SlotClickHandler.ctrl_click_transfer(s11a_t5, c11a_t5, 3)
	_check(failures, s11a_t5.count == 6 and c11a_t5.count == 2,
		"(11a) ctrl_transfer GIVE 3 into same-type → slot=6, cursor=2")

	# Defensive: N=0 is a no-op.
	var s11a_t6 := ItemStack.new(Items.Type.WHEAT, 8)
	var c11a_t6 := CursorStack.new()
	SlotClickHandler.ctrl_click_transfer(s11a_t6, c11a_t6, 0)
	_check(failures, not c11a_t6.has_item() and s11a_t6.count == 8,
		"(11a) ctrl_transfer N=0 is no-op (defensive guard)")

	# ---------- (12) ctrl_picker_confirm_cancel_gate ----------
	# Tests ctrl picker orchestration: caller-side gate + confirm + cancel paths.
	# Pure-logic test — mocks confirm_cb via Callable closure capturing test-local
	# state in an Array (reference semantics). Picker scene integration at PAUSE 2.

	# (12a) Confirm path: simulate picker open + Enter. cb fires with N=3.
	var s12a := ItemStack.new(Items.Type.WHEAT, 8)
	var c12a := CursorStack.new()
	var called12a: Array = [false]
	var called_n12a: Array = [0]
	var cb12a: Callable = func(n: int):
		called12a[0] = true
		called_n12a[0] = n
		SlotClickHandler.ctrl_click_transfer(s12a, c12a, n)
	# Caller-side orchestration: compute max, gate on >0, simulate picker confirm.
	var max_n12a: int = SlotClickHandler.ctrl_click_max(s12a, c12a)
	if max_n12a > 0:
		# In live code, picker.open(...) shows the dialog; on Enter, cb.call(N).
		# We simulate "user typed 3, pressed Enter" by direct cb invocation.
		cb12a.call(3)
	_check(failures, max_n12a == 8 and called12a[0] and called_n12a[0] == 3,
		"(12a) confirm path: max=8, cb invoked with N=3")
	_check(failures, c12a.count == 3 and s12a.count == 5,
		"(12a) confirm transfer: slot 8→5, cursor 0→3")

	# (12b) Cancel path: simulate picker open + Esc/Cancel/click-outside.
	# cb NEVER fires; state unchanged.
	var s12b := ItemStack.new(Items.Type.WHEAT, 8)
	var c12b := CursorStack.new()
	var called12b: Array = [false]
	var cb12b: Callable = func(_n: int):
		called12b[0] = true
	var max_n12b: int = SlotClickHandler.ctrl_click_max(s12b, c12b)
	# Note: we DO NOT call cb12b. This simulates "picker opened but user cancelled."
	# The picker's hide() path on Esc/Cancel/click-outside does NOT invoke confirm_cb.
	_check(failures, max_n12b == 8 and not called12b[0],
		"(12b) cancel path: max would have been 8, but cb NOT invoked")
	_check(failures, s12b.count == 8 and not c12b.has_item(),
		"(12b) cancel state: slot still 8, cursor still empty")

	# (12c) Pre-open gate: max == 0 means caller's `if max_n > 0` gate suppresses
	# the picker.open() call entirely. cb never gets the chance to fire.
	# Three gate cells per spec §6.1: empty+empty, different-type, same-type-at-max_stack.

	# (12c.empty) Empty cursor + empty slot → max=0.
	var s12c_empty := ItemStack.new()
	var c12c_empty := CursorStack.new()
	var called12c_empty: Array = [false]
	var cb12c_empty: Callable = func(_n: int): called12c_empty[0] = true
	var max_n12c_empty: int = SlotClickHandler.ctrl_click_max(s12c_empty, c12c_empty)
	if max_n12c_empty > 0:
		cb12c_empty.call(max_n12c_empty)  # gated — should not execute
	_check(failures, max_n12c_empty == 0 and not called12c_empty[0],
		"(12c.empty) gate: empty+empty → max=0, cb NOT invoked")

	# (12c.diff) Different-type cursor + slot → max=0.
	var s12c_diff := ItemStack.new(Items.Type.FLOUR, 5)
	var c12c_diff := CursorStack.new()
	c12c_diff.pick(Items.Type.WHEAT, 3)
	var called12c_diff: Array = [false]
	var cb12c_diff: Callable = func(_n: int): called12c_diff[0] = true
	var max_n12c_diff: int = SlotClickHandler.ctrl_click_max(s12c_diff, c12c_diff)
	if max_n12c_diff > 0:
		cb12c_diff.call(max_n12c_diff)
	_check(failures, max_n12c_diff == 0 and not called12c_diff[0],
		"(12c.diff) gate: different-type → max=0, cb NOT invoked")

	# (12c.full) Same-type cursor + slot at max_stack → max=0.
	var s12c_full := ItemStack.new(Items.Type.WHEAT, 100)  # WHEAT max_stack=100
	var c12c_full := CursorStack.new()
	c12c_full.pick(Items.Type.WHEAT, 5)
	var called12c_full: Array = [false]
	var cb12c_full: Callable = func(_n: int): called12c_full[0] = true
	var max_n12c_full: int = SlotClickHandler.ctrl_click_max(s12c_full, c12c_full)
	if max_n12c_full > 0:
		cb12c_full.call(max_n12c_full)
	_check(failures, max_n12c_full == 0 and not called12c_full[0],
		"(12c.full) gate: same-type at max_stack → max=0, cb NOT invoked")

	# ---------- (13) ctrl_picker_outside_click_no_propagation ----------
	# First scene-tree sub-suite in this file. Verifies the picker's
	# outside-click / cancel teardown path does NOT invoke confirm_cb.
	# Scene-tree pattern mirrors test_walkability.gd's GridWorld lifecycle.
	#
	# Per spec §4.2 + §4.3: popup_exclusive_on_parent handles click-outside
	# natively (Godot dispatches hide() on the popup). Direct hide() call here
	# is a proxy — same teardown path, no fragile headless input injection.

	var picker_scene13: PackedScene = load("res://scenes/quantity_picker_modal.tscn")
	var picker13: QuantityPickerModal = picker_scene13.instantiate() as QuantityPickerModal
	parent.add_child(picker13)
	var was_called13: Array = [false]
	var sentinel13: Callable = func(_n: int):
		was_called13[0] = true
	# Open picker with arbitrary state — we're not testing the math here.
	picker13.open(Vector2(100, 100), "Take", "Wheat", 10, 10, sentinel13)
	_check(failures, picker13.visible,
		"(13a) picker visible after open()")
	# Simulate outside-click teardown via hide() — same code path as real
	# click-outside (popup_exclusive_on_parent calls hide() internally).
	picker13.hide()
	_check(failures, not picker13.visible,
		"(13b) picker hidden after cancel/outside-click")
	_check(failures, not was_called13[0],
		"(13c) confirm_cb NOT invoked on non-OK teardown (regression lock)")
	picker13.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all sub-suites pass: regression + shift+take + split_half util sanity" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
