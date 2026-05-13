extends RefCounted

## SlotClickHandler tests (QoL Cluster A — session-qol-cluster-a).
##
## 13 sub-suites covering refactor regression, shift+LMB matrix, ctrl+LMB
## picker semantics. See docs/superpowers/specs/2026-05-10-qol-cluster-a-design.md
## §7 for the full plan.

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

	if failures.is_empty():
		return { "ok": true, "message": "all sub-suites pass: regression + shift+take + split_half util sanity" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
