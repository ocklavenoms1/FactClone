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
	_check(failures, s1a.is_empty() and not c1a.has_item(),
		"(1a) empty+empty → no-op")

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

	if failures.is_empty():
		return { "ok": true, "message": "2 sub-suites pass: regression + split_half util sanity" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
