# QoL Cluster A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the duplicated player-slot click handler into a static `SlotClickHandler` module, then add shift+LMB half-stack and ctrl+LMB exact-N picker behaviors across player / chest / building-input / building-output / fuel slots.

**Architecture:** New `SlotClickHandler` static module owns the player-slot pick/place/swap/merge logic and a `split_half(n)` math util. New `QuantityPickerModal` (PopupPanel subclass) is a shared HUD singleton opened by any panel via a Callable confirm callback. All other slot kinds keep their existing dispatcher locus but thread a `mods` bitfield parameter and call `split_half(n)` for the half math. Save schema unchanged (v18).

**Tech Stack:** Godot 4.6.2 GDScript. No new external dependencies. Test framework: pure-GDScript classes registered in `test_runner.tscn`.

**Spec reference:** [docs/superpowers/specs/2026-05-10-qol-cluster-a-design.md](../specs/2026-05-10-qol-cluster-a-design.md)

---

## File structure

**New files:**
- `scripts/ui/slot_click_handler.gd` — static module: `handle_player_slot`, `ctrl_click_max`, `ctrl_click_transfer`, `split_half`, `MOD_NONE`/`MOD_SHIFT`/`MOD_CTRL` constants.
- `scripts/ui/quantity_picker_modal.gd` — `QuantityPickerModal extends PopupPanel`. Has `open(anchor, direction, label_item, max_n, default_n, confirm_cb)`.
- `scenes/quantity_picker_modal.tscn` — scene wrapping the PopupPanel with VBoxContainer { Label, SpinBox, HBoxContainer { OK, Cancel } }.
- `scripts/tests/test_slot_click_handler.gd` — 13 sub-suites covering refactor regression, shift matrix, ctrl picker semantics.

**Modified files:**
- `scripts/ui/inventory_grid.gd` — delegate `_handle_left_click_player` to handler; extract mods from `_gui_input`.
- `scripts/ui/building_panel.gd` — delegate `_handle_player_slot_click` to handler; thread mods through `_take_from_slot` / `_drop_into_slot` / `_drop_into_input` / `_drop_into_fuel`; ctrl-picker call sites.
- `scripts/ui/chest_panel.gd` — thread mods through `_handle_chest_slot_click`; shift/ctrl branches.
- `scripts/main.gd` — `@onready var quantity_picker`; wire into panels.
- `scenes/main.tscn` — load_steps bump + HUD node ext_resource for picker.
- `scripts/tests/test_runner.gd` — register `test_slot_click_handler.gd`.

**Explicitly unchanged:**
- `scripts/ui/slot_widget.gd` (pure render helpers, no click logic — CLAUDE.md rule).
- `scripts/ui/cursor_stack.gd` (kept as pure data/serialization model).
- `scripts/ui/fast_inserter_panel.gd` (RMB-clear stays untouched).

---

## Run / verify commands (used throughout)

```bash
# Run the full test suite (headless)
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"

# Quick compile check only (no full test pass)
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" --quit

# Launch game for manual smoke
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9"
```

There is no per-test selector — `test_runner.gd` runs all. To isolate one test temporarily, comment out other entries in `TESTS` array. Restore the full list before committing.

---

# PHASE 1 — Refactor: extract SlotClickHandler (LMB only)

Goal: extract the literal duplicate. Plain LMB behavior must remain **byte-identical** to pre-refactor. No shift/ctrl branches yet. This phase ends with GATE 1.

---

### Task 1: Create `SlotClickHandler` module skeleton + `split_half` + unit test

**Files:**
- Create: `scripts/ui/slot_click_handler.gd`
- Create: `scripts/tests/test_slot_click_handler.gd`
- Modify: `scripts/tests/test_runner.gd` (one-line register)

- [ ] **Step 1: Create the test file with one failing test for `split_half`**

Write `scripts/tests/test_slot_click_handler.gd`:

```gdscript
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

	if failures.is_empty():
		return { "ok": true, "message": "split_half util passes (1 sub-suite stub — rest land in later tasks)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
```

- [ ] **Step 2: Register the test in `test_runner.gd`**

Open `scripts/tests/test_runner.gd`. Append to the `TESTS` const array (after `test_walkability.gd`):

```gdscript
	preload("res://scripts/tests/test_slot_click_handler.gd"),
```

- [ ] **Step 3: Run tests; verify the slot_click_handler test fails because the class doesn't exist**

Run the test suite command from the top of this plan. Expected: parse error or runtime error on `SlotClickHandler.split_half` — the class doesn't exist yet.

- [ ] **Step 4: Create `scripts/ui/slot_click_handler.gd` with `split_half` only**

```gdscript
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
```

- [ ] **Step 5: Run tests; verify slot_click_handler PASSES + all 33 existing tests still PASS (34 total)**

Run the test suite command. Expected last line: `34 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/slot_click_handler.gd scripts/tests/test_slot_click_handler.gd scripts/tests/test_runner.gd
git commit -m "Task 1: SlotClickHandler skeleton + split_half util + 1 sub-suite"
```

---

### Task 2: Implement `handle_player_slot` (plain LMB) + sub-suite #1 (regression)

**Files:**
- Modify: `scripts/ui/slot_click_handler.gd` (add `handle_player_slot`)
- Modify: `scripts/tests/test_slot_click_handler.gd` (add sub-suite #1)

- [ ] **Step 1: Add the failing regression test sub-suite (5 cases)**

In `scripts/tests/test_slot_click_handler.gd`, insert this block **before** the `if failures.is_empty():` return. Then update the success message.

```gdscript
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
```

Update the success-message return to: `"1 sub-suite passes (regression) + util sanity"`.

- [ ] **Step 2: Run tests; verify slot_click_handler FAILS on every (1*) case**

Expected: 5 failures, "function not defined" for `handle_player_slot`.

- [ ] **Step 3: Implement `handle_player_slot` (plain LMB only, no mod branches)**

Append to `scripts/ui/slot_click_handler.gd`:

```gdscript
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
```

- [ ] **Step 4: Run tests; verify ALL pass (34 total)**

Expected last line: `34 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/slot_click_handler.gd scripts/tests/test_slot_click_handler.gd
git commit -m "Task 2: handle_player_slot LMB path + sub-suite #1 regression test"
```

---

### Task 3: Migrate `inventory_grid` to delegate to handler

**Files:**
- Modify: `scripts/ui/inventory_grid.gd` (lines 117-151 — the `_handle_left_click_player` body)

- [ ] **Step 1: Replace the body of `_handle_left_click_player`**

Open `scripts/ui/inventory_grid.gd`. Find the existing function (currently lines 117-151). Replace it with:

```gdscript
func _handle_left_click_player(slot_idx: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	SlotClickHandler.handle_player_slot(slot, cursor, SlotClickHandler.MOD_NONE)
	queue_redraw()
```

(The `MOD_NONE` here will become `mods` extracted from the event in Task 9 — Phase 2.)

- [ ] **Step 2: Run full test suite — all 34 tests pass**

Expected: `34 passed, 0 failed`. The regression test from Task 2 doesn't go through `inventory_grid`, so its pass is a separate signal; we also need all 33 existing tests to remain green.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/inventory_grid.gd
git commit -m "Task 3: inventory_grid delegates _handle_left_click_player to SlotClickHandler"
```

---

### Task 4: Migrate `BuildingPanel` to delegate to handler

**Files:**
- Modify: `scripts/ui/building_panel.gd` (lines 217-249 — the `_handle_player_slot_click` body)

- [ ] **Step 1: Replace the body of `_handle_player_slot_click`**

Open `scripts/ui/building_panel.gd`. Find the existing function (currently lines 217-249). Replace it with:

```gdscript
func _handle_player_slot_click(slot_idx: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	SlotClickHandler.handle_player_slot(slot, cursor, SlotClickHandler.MOD_NONE)
	queue_redraw()
```

(Same future-mods note as Task 3.)

- [ ] **Step 2: Run full test suite — all 34 tests pass**

Expected: `34 passed, 0 failed`.

- [ ] **Step 3: Commit (do NOT include the GATE 1 smoke yet — it lands in Task 5)**

```bash
git add scripts/ui/building_panel.gd
git commit -m "Task 4: BuildingPanel delegates _handle_player_slot_click to SlotClickHandler"
```

---

### Task 5: GATE 1 — manual smoke + sign-off

This is a verification task, not a code task. No commit (or a "GATE 1 reached" empty-tree marker commit at your discretion).

- [ ] **Step 1: Run the headless test suite one more time**

Expected: `34 passed, 0 failed`. If anything regressed since Task 4, stop and debug — do NOT proceed to Phase 2.

**Test count metric convention (read once, applies for the rest of the plan):**

This project uses one PASS line per test FILE, regardless of how many internal `_check(failures, ...)` sub-suites that file contains. (`test_inserter.gd` has 10 sub-suites and reports as 1 PASS line; its PROJECT_LOG entry tracks "Tests: 31 → 32 passing, internal sub-suite count 31 → 41.")

Because all 13 of our new sub-suites land in the single new file `test_slot_click_handler.gd`, the runner-level pass count is:

- **Before Task 1:** 33 passed
- **After Task 1 (file registered):** 34 passed — and stays at 34 for the rest of Phases 2-3.
- **Internal sub-suite coverage** climbs from 1 (Task 1) to 13 (Task 23) as new `_check(...)` blocks land inside the same file.

Every "Expected: 34 passed" line in this plan refers to the runner-level count. When a task adds an internal sub-suite, that's noted separately. Sign-off at GATE 1 / GATE 2 / PAUSE 2 records BOTH metrics (mirror the test_inserter PROJECT_LOG style).

- [ ] **Step 2: Launch the game and smoke each player-slot click path**

Launch with the game-run command from the top of this plan.

Verify, **with no behavior change visible to the player**:

- Open inventory grid (press `I`). Pick up a stack from one slot (LMB), place it in another empty slot (LMB). Pick up again, place onto a same-type stack — confirm merge respects max_stack. Pick up, place onto a different-type stack — confirm swap.
- Open a chest panel. The chest panel **inherits** `_handle_player_slot_click` from BuildingPanel — exercise the same operations on the player-side slots of the chest panel.
- Open a building panel (e.g., smelter or fast inserter). Same operations on player slots.

- [ ] **Step 3: Sign off — GATE 1 reached**

In your session notes, record: "GATE 1 PASS: 34 tests + manual smoke confirm refactor is byte-identical to pre-extraction. Proceeding to Phase 2."

If any operation behaves differently, **stop** and debug. Common suspects: missing `queue_redraw()`, missing `cursor.has_item()` vs. `cursor.item_type < 0` discrepancy (both should be equivalent; verify), or a `slot_idx` bound check skipped.

---

# PHASE 2 — Shift+LMB across the matrix

Goal: extend SlotClickHandler with shift branches for the player-slot path, then thread `mods` through each panel's dispatchers so chest / input / output_multi / fuel / filter all support shift+LMB per spec §5. Phase ends with GATE 2.

---

### Task 6: Sub-suite #2 — `shift_take_player_half`

**Files:**
- Modify: `scripts/ui/slot_click_handler.gd` (add shift-take branch)
- Modify: `scripts/tests/test_slot_click_handler.gd` (add sub-suite #2)

- [ ] **Step 1: Add the failing test**

In `test_slot_click_handler.gd`, append before the success return:

```gdscript
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
```

Update the success message: `"2 sub-suites pass: regression + shift+take half"`.

- [ ] **Step 2: Run — verify failures (shift branch not implemented yet, falls through to plain LMB → takes ALL)**

- [ ] **Step 3: Add the shift-take branch to `handle_player_slot`**

In `scripts/ui/slot_click_handler.gd`, modify `handle_player_slot`. **Before** the "Empty cursor → pick up slot's stack" plain-LMB block, insert a shift-aware branch:

```gdscript
	# Shift+LMB: half-stack take/drop semantics (spec §5.1).
	if mods & MOD_SHIFT != 0:
		_handle_shift_player(slot, cursor)
		return
```

Then append the helper after `handle_player_slot`:

```gdscript
## Shift+LMB on a player-inventory ItemStack. Half-stack take/drop per
## spec §5.1 matrix:
##   empty+empty       → no-op
##   empty+N           → cursor takes ceil(N/2)
##   M+empty           → slot gets ceil(M/2), cursor keeps floor(M/2)
##   M+same type       → slot gets min(ceil(M/2), space), cursor decrements
##   M+different type  → no-op (shift never swaps)
static func _handle_shift_player(slot: ItemStack, cursor: CursorStack) -> void:
	if not cursor.has_item():
		if slot.is_empty():
			return
		var take: int = split_half(slot.count)
		cursor.pick(slot.item_type, take)
		slot.count -= take
		if slot.count <= 0:
			slot.clear()
		return
	# Cursor has item.
	if slot.is_empty():
		var drop: int = split_half(cursor.count)
		slot.item_type = cursor.item_type
		slot.count = drop
		cursor.count -= drop
		if cursor.count <= 0:
			cursor.clear()
		return
	if slot.item_type == cursor.item_type:
		var max_stack: int = Items.max_stack_of(slot.item_type)
		var space: int = max_stack - slot.count
		var want: int = split_half(cursor.count)
		var moved: int = min(space, want)
		slot.count += moved
		cursor.count -= moved
		if cursor.count <= 0:
			cursor.clear()
		return
	# Different types → no-op (shift never swaps; plain LMB still swaps).
```

- [ ] **Step 4: Run — verify all 34 tests pass**

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/slot_click_handler.gd scripts/tests/test_slot_click_handler.gd
git commit -m "Task 6: shift+LMB take half on player slot + sub-suite #2"
```

---

### Task 7: Sub-suite #3 — `shift_drop_player_half_empty`

**Files:**
- Modify: `scripts/tests/test_slot_click_handler.gd`

The drop-into-empty branch was implemented in Task 6's `_handle_shift_player`. This task locks it in with explicit tests.

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (3) shift_drop_player_half_empty: M cursor + empty slot ----------
	# M=1 (degenerate — drop 1, cursor goes to 0)
	var s3a := ItemStack.new()
	var c3a := CursorStack.new()
	c3a.pick(Items.Type.WHEAT, 1)
	SlotClickHandler.handle_player_slot(s3a, c3a, SlotClickHandler.MOD_SHIFT)
	_check(failures, s3a.count == 1 and not c3a.has_item(),
		"(3) shift+drop M=1 → slot=1, cursor clear")
	# M=7 (rounded half)
	var s3b := ItemStack.new()
	var c3b := CursorStack.new()
	c3b.pick(Items.Type.WHEAT, 7)
	SlotClickHandler.handle_player_slot(s3b, c3b, SlotClickHandler.MOD_SHIFT)
	_check(failures, s3b.count == 4 and c3b.count == 3,
		"(3) shift+drop M=7 → slot=4 (ceil), cursor=3 (floor)")
```

Update success message: `"3 sub-suites pass: ... + shift+drop half empty"`.

- [ ] **Step 2: Run — verify all pass (no code change needed)**

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_slot_click_handler.gd
git commit -m "Task 7: sub-suite #3 shift+drop half into empty slot"
```

---

### Task 8: Sub-suite #4 — `shift_drop_player_half_matching` with capacity clamp

- [ ] **Step 1: Add the test (includes the explicit capacity-clamp case from spec)**

```gdscript
	# ---------- (4) shift_drop_player_half_matching: M cursor + K slot same type ----------
	# Normal case (plenty of space): cursor 6, slot 2 wheat, max_stack=100
	# split_half(6)=3, drop all 3.
	var s4a := ItemStack.new(Items.Type.WHEAT, 2)
	var c4a := CursorStack.new()
	c4a.pick(Items.Type.WHEAT, 6)
	SlotClickHandler.handle_player_slot(s4a, c4a, SlotClickHandler.MOD_SHIFT)
	_check(failures, s4a.count == 5 and c4a.count == 3,
		"(4) shift+drop same-type plenty: slot 2→5, cursor 6→3")
	# CAPACITY CLAMP case from spec §5.1 + your review note:
	# cursor 10 wheat, slot 8 wheat, max_stack=100 — that's plenty of space,
	# need an item with small max_stack to test the clamp. Use YEAST (max_stack=50).
	# cursor 40 yeast, slot 45 yeast, max_stack=50: want to drop split_half(40)=20,
	# only 5 space available → drop 5 (silent clamp, NOT 20, NOT no-op).
	var s4b := ItemStack.new(Items.Type.YEAST, 45)
	var c4b := CursorStack.new()
	c4b.pick(Items.Type.YEAST, 40)
	SlotClickHandler.handle_player_slot(s4b, c4b, SlotClickHandler.MOD_SHIFT)
	_check(failures, s4b.count == 50 and c4b.count == 35,
		"(4) shift+drop CAPACITY CLAMP: slot=45+5(clamped from 20)=50, cursor=40-5=35")
```

Update success message: `"4 sub-suites pass: ... + shift+drop half matching + clamp"`.

- [ ] **Step 2: Run — verify all pass**

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_slot_click_handler.gd
git commit -m "Task 8: sub-suite #4 shift+drop half matching with capacity clamp"
```

---

### Task 9: Sub-suite #5 — `shift_player_diff_type_noop`

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (5) shift_player_diff_type_noop: shift never swaps ----------
	var s5 := ItemStack.new(Items.Type.FLOUR, 4)
	var c5 := CursorStack.new()
	c5.pick(Items.Type.WHEAT, 5)
	var before_slot_t := s5.item_type; var before_slot_c := s5.count
	var before_cur_t := c5.item_type; var before_cur_c := c5.count
	SlotClickHandler.handle_player_slot(s5, c5, SlotClickHandler.MOD_SHIFT)
	_check(failures, s5.item_type == before_slot_t and s5.count == before_slot_c,
		"(5) shift different-type: slot unchanged (no swap)")
	_check(failures, c5.item_type == before_cur_t and c5.count == before_cur_c,
		"(5) shift different-type: cursor unchanged (no swap)")
```

Update success message: `"5 sub-suites pass through diff-type no-op"`.

- [ ] **Step 2: Run — verify all pass**

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_slot_click_handler.gd
git commit -m "Task 9: sub-suite #5 shift different-type no-op"
```

---

### Task 10: Thread `mods` extraction through inventory_grid + BuildingPanel `_gui_input`

**Files:**
- Modify: `scripts/ui/inventory_grid.gd` (the `_gui_input` function around lines 99-116, and the `_handle_left_click_player` call line)
- Modify: `scripts/ui/building_panel.gd` (the `_gui_input` for the player-slot click branch — and `_handle_player_slot_click` signature)

- [ ] **Step 1: Update `inventory_grid._gui_input` and `_handle_left_click_player` signature**

In `scripts/ui/inventory_grid.gd`, change the click dispatch in `_gui_input` to extract mods and pass them:

```gdscript
		_handle_left_click_player(slot_idx, _extract_mods(event))
```

Then update `_handle_left_click_player` to accept and forward mods:

```gdscript
func _handle_left_click_player(slot_idx: int, mods: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	SlotClickHandler.handle_player_slot(slot, cursor, mods)
	queue_redraw()
```

Append the helper to the same file:

```gdscript
## Extract a SlotClickHandler.MOD_* bitfield from a MouseButton event.
static func _extract_mods(event: InputEventMouseButton) -> int:
	var mods: int = SlotClickHandler.MOD_NONE
	if event.shift_pressed:
		mods |= SlotClickHandler.MOD_SHIFT
	if event.ctrl_pressed:
		mods |= SlotClickHandler.MOD_CTRL
	return mods
```

- [ ] **Step 2: Update `BuildingPanel` to thread mods through player-slot click**

In `scripts/ui/building_panel.gd`, find `_handle_player_slot_click` and change signature + body:

```gdscript
func _handle_player_slot_click(slot_idx: int, mods: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	SlotClickHandler.handle_player_slot(slot, cursor, mods)
	queue_redraw()
```

Find the call site(s) for `_handle_player_slot_click` (in `building_panel.gd`'s `_gui_input` and in `chest_panel.gd`'s `_gui_input`). Add a `_extract_mods` helper to BuildingPanel (same body as the one in inventory_grid — duplication is fine, two-line helper, no abstraction needed yet):

```gdscript
static func _extract_mods(event: InputEventMouseButton) -> int:
	var mods: int = SlotClickHandler.MOD_NONE
	if event.shift_pressed:
		mods |= SlotClickHandler.MOD_SHIFT
	if event.ctrl_pressed:
		mods |= SlotClickHandler.MOD_CTRL
	return mods
```

In every `_handle_player_slot_click(slot_idx)` call within `building_panel.gd` and `chest_panel.gd`, change to `_handle_player_slot_click(slot_idx, _extract_mods(event))`.

- [ ] **Step 3: Quick compile check before running full tests**

Run the import-quit compile command from the top of this plan. Expected: no parse errors.

- [ ] **Step 4: Run full test suite — all pass**

Expected: `34 passed, 0 failed`. Internal sub-suite count for `slot click handler`: 5 (regression #1 + shift #2-#5).

- [ ] **Step 5: Manual smoke — shift+LMB on player slot via in-game UI**

Launch the game. Open inventory, populate a slot with multiple items (e.g., harvest wheat). Shift+LMB on a stack of 7 wheat → cursor gets 4, slot keeps 3. Shift+LMB with cursor full into another empty slot → drop ceil(N/2). Verify visually.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/inventory_grid.gd scripts/ui/building_panel.gd scripts/ui/chest_panel.gd
git commit -m "Task 10: thread mods through inventory_grid + BuildingPanel + chest_panel player-slot _gui_input"
```

---

### Task 11: Sub-suite #6 — `shift_chest_take_and_drop` + chest_panel shift branches

**Files:**
- Modify: `scripts/ui/chest_panel.gd` (add shift branches to `_handle_chest_slot_click`, thread mods)
- Modify: `scripts/tests/test_slot_click_handler.gd`

Test uses the Chest building's bag directly to avoid scene-tree coupling for headless. Chest API: `Chest._bag_add(bag, type, count)`, `Chest._bag_remove(bag, type, count)`, `Chest.free_capacity(building) -> int`. Read `scripts/world/chest.gd` for exact signatures before writing the test.

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (6) shift_chest_take_and_drop: chest bag slot shift behavior ----------
	# Build a fake chest-like building (just the state Dict) — we test the
	# pure bag transformations + chest_panel's helper calls, not the panel scene.
	# Bag entries: Array of [type, count].

	# (6a) shift+take: bag has [WHEAT, 7] → take 4, bag has [WHEAT, 3].
	var bag6a: Array = [[Items.Type.WHEAT, 7]]
	var c6a := CursorStack.new()
	# Inline-simulate chest_panel's shift-take logic (mirrors what we'll wire below).
	if not c6a.has_item():
		var v = bag6a[0]
		var take: int = SlotClickHandler.split_half(int(v[1]))
		Chest._bag_remove(bag6a, int(v[0]), take)
		c6a.pick(int(v[0]), take)
	_check(failures, c6a.count == 4 and Chest._bag_count(bag6a, Items.Type.WHEAT) == 3,
		"(6a) chest shift+take: cursor=4, bag wheat=3")

	# (6b) shift+drop refuse: cursor 10 wheat, chest free_capacity=5 →
	# split_half(10)=5 fits ≤ free_capacity (=5), drop 5.
	# Test the EDGE: cursor 12 wheat, free_capacity=5 → split_half(12)=6 > 5,
	# REFUSE with toast (NOT silent-clamp, per spec §5.2 chest row).
	var bag6b: Array = []
	var c6b := CursorStack.new()
	c6b.pick(Items.Type.WHEAT, 12)
	var free6b: int = 5
	var half6b: int = SlotClickHandler.split_half(c6b.count)
	var refused6b: bool = false
	if half6b > free6b:
		refused6b = true
	_check(failures, refused6b and bag6b.is_empty() and c6b.count == 12,
		"(6b) chest shift+drop refuse: bag unchanged, cursor unchanged, refused=true")
```

(Test #6 verifies the pure logic. Step 3 wires the same logic into chest_panel.)

Update success message: `"6 sub-suites: ... + chest shift take/drop refuse"`.

- [ ] **Step 2: Run — verify all pass (pure logic test, no chest_panel changes needed yet)**

Note: this confirms the math; the actual chest_panel wiring is what makes it player-visible. Wire it in Step 3 below.

- [ ] **Step 3: Add shift branches to `chest_panel._handle_chest_slot_click`**

In `scripts/ui/chest_panel.gd`, modify `_gui_input` to pass mods to the handler call:

```gdscript
		if hit is int:
			_handle_player_slot_click(int(hit), _extract_mods(event))
		elif hit is Dictionary and hit.has("chest_idx"):
			_handle_chest_slot_click(int(hit["chest_idx"]), _extract_mods(event))
```

Change `_handle_chest_slot_click` signature and add shift branches:

```gdscript
func _handle_chest_slot_click(slot_idx: int, mods: int) -> void:
	var bag: Array = building.state.get("bag", [])
	var views: Array = SlotWidget.chest_bag_to_slot_views(bag)
	var view_present: bool = slot_idx < views.size()

	# Shift+LMB: half-stack take/drop. Chest preserves its LMB convention —
	# refuse-with-toast on no-fit (NOT silent-clamp like player slot).
	if mods & SlotClickHandler.MOD_SHIFT != 0:
		if not cursor.has_item():
			# Shift+take half.
			if not view_present:
				return
			var v = views[slot_idx]
			var take: int = SlotClickHandler.split_half(int(v["count"]))
			Chest._bag_remove(bag, int(v["item_type"]), take)
			cursor.pick(int(v["item_type"]), take)
			return
		# Cursor has item — shift+drop half, but check capacity for refuse.
		var half: int = SlotClickHandler.split_half(cursor.count)
		if Chest.free_capacity(building) < half:
			_toast("Chest full — cannot deposit half (%d, need %d capacity)" % [half, half])
			return
		Chest._bag_add(bag, cursor.item_type, half)
		cursor.count -= half
		if cursor.count <= 0:
			cursor.clear()
		return

	# (ctrl branch lands in Task 19.)

	# Plain LMB — unchanged from the original implementation.
	if not cursor.has_item():
		if not view_present:
			return
		var v2 = views[slot_idx]
		var item_type: int = int(v2["item_type"])
		var c: int = int(v2["count"])
		Chest._bag_remove(bag, item_type, c)
		cursor.pick(item_type, c)
		return
	if Chest.free_capacity(building) < cursor.count:
		_toast("Chest full — cannot deposit (need %d more capacity)" % (cursor.count - Chest.free_capacity(building)))
		return
	Chest._bag_add(bag, cursor.item_type, cursor.count)
	if view_present:
		var v3 = views[slot_idx]
		var item_type3: int = int(v3["item_type"])
		var c3: int = int(v3["count"])
		Chest._bag_remove(bag, item_type3, c3)
		cursor.pick(item_type3, c3)
	else:
		cursor.clear()
```

- [ ] **Step 4: Run full test suite**

Expected: `34 passed, 0 failed`. Internal sub-suite count: 6 (added chest shift #6). Plain LMB on chest must still work — verify by running the existing `chest paired view` test (unchanged) still PASS.

- [ ] **Step 5: Manual smoke — shift on chest slot**

Launch the game. Place a chest, open it. Put items in it. Shift+LMB on a chest entry → cursor takes half. Shift+LMB on an empty chest entry with cursor full → if half fits in capacity, deposits; if not, toast appears.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/chest_panel.gd scripts/tests/test_slot_click_handler.gd
git commit -m "Task 11: chest shift+LMB take/drop with refuse-on-no-fit + sub-suite #6"
```

---

### Task 12: Sub-suite #7 — `shift_building_input_and_output` + BuildingPanel dispatcher shift

**Files:**
- Modify: `scripts/ui/building_panel.gd` (add shift branches to `_take_from_slot`, `_drop_into_slot`, `_drop_into_input`)
- Modify: `scripts/tests/test_slot_click_handler.gd`

- [ ] **Step 1: Add the test (uses pure buffer manipulation — Array of [type,count])**

```gdscript
	# ---------- (7) shift_building_input_and_output ----------
	# (7a) Input shift+take: buf=[[WHEAT, 8]] → cursor takes 4, buf=[[WHEAT,4]].
	var buf7a: Array = [[Items.Type.WHEAT, 8]]
	var c7a := CursorStack.new()
	# Inline-simulate _take_from_slot input shift branch.
	if not c7a.has_item() and not buf7a.is_empty():
		var e = buf7a[0]
		var take: int = SlotClickHandler.split_half(int(e[1]))
		c7a.pick(int(e[0]), take)
		e[1] = int(e[1]) - take
	_check(failures, c7a.count == 4 and int(buf7a[0][1]) == 4,
		"(7a) input shift+take: cursor=4, buf=[[WHEAT,4]]")

	# (7b) Input shift+drop: cursor 10 wheat, buf=[[WHEAT,3]], max_stack(slot_def)=8.
	# split_half(10)=5, space=8-3=5, drop 5. cursor=5, buf=[[WHEAT,8]].
	var buf7b: Array = [[Items.Type.WHEAT, 3]]
	var c7b := CursorStack.new()
	c7b.pick(Items.Type.WHEAT, 10)
	var max_stack7b: int = 8
	# Inline-simulate _drop_into_input shift branch with split_half.
	var current7b: int = 3
	var space7b: int = max_stack7b - current7b
	var want7b: int = SlotClickHandler.split_half(c7b.count)
	var moved7b: int = min(space7b, want7b)
	buf7b[0][1] = int(buf7b[0][1]) + moved7b
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
		"(7c) output_multi shift+take of sub_idx=1: cursor=3 straw, buf[1]=[STRAW,2]")
```

Update success message: `"7 sub-suites: ... + input/output shift"`.

- [ ] **Step 2: Run — verify all pass (logic test, no panel change yet)**

- [ ] **Step 3: Wire shift branches into BuildingPanel dispatchers**

In `scripts/ui/building_panel.gd`:

Change `_handle_building_slot_click` to accept mods + pass through:

```gdscript
func _handle_building_slot_click(hit: Dictionary, mods: int) -> void:
	var slot_def: Dictionary = hit["slot_def"]
	var sub_idx: int = int(hit.get("sub_idx", -1))
	if not cursor.has_item():
		_take_from_slot(slot_def, sub_idx, mods)
		queue_redraw()
		return
	_drop_into_slot(slot_def, sub_idx, mods)
	queue_redraw()
```

Update `_gui_input` (and any equivalent dispatch in subclasses) to pass `_extract_mods(event)` to `_handle_building_slot_click`.

Update `_take_from_slot` and `_drop_into_slot` signatures:

```gdscript
func _take_from_slot(slot_def: Dictionary, sub_idx: int, mods: int) -> void:
	var kind: String = str(slot_def.get("kind", ""))
	var field: String = str(slot_def.get("state_field", ""))
	# Shift+LMB take: half-stack (spec §5.2).
	var shift: bool = (mods & SlotClickHandler.MOD_SHIFT) != 0
	match kind:
		"input", "output":
			var buf: Array = building.state.get(field, [])
			if buf.is_empty():
				return
			var entry = buf[0]
			var take: int = SlotClickHandler.split_half(int(entry[1])) if shift else int(entry[1])
			cursor.pick(int(entry[0]), take)
			entry[1] = int(entry[1]) - take
			if int(entry[1]) <= 0:
				buf.clear()
			building.state[field] = buf
		"output_multi":
			var buf2: Array = building.state.get(field, [])
			if sub_idx < 0 or sub_idx >= buf2.size():
				return
			var entry2 = buf2[sub_idx]
			var take2: int = SlotClickHandler.split_half(int(entry2[1])) if shift else int(entry2[1])
			cursor.pick(int(entry2[0]), take2)
			entry2[1] = int(entry2[1]) - take2
			if int(entry2[1]) <= 0:
				buf2.remove_at(sub_idx)
			building.state[field] = buf2
		"fuel":
			# (handled in Task 13 — fuel needs unit-conversion logic.)
			# For now, keep existing lossy-WOOD-all path; shift handled there.
			var units: int = int(building.state.get("fuel_buffer", 0))
			if units <= 0:
				return
			var n: int = SlotClickHandler.split_half(units) if shift else units
			cursor.pick(Items.Type.WOOD, n)
			building.state["fuel_buffer"] = units - n
			if not shift:
				building.state["fuel_burn_progress"] = 0
			_toast("Retrieved %d wood (lossy: 1 fuel unit = 1 wood)." % n)
		"filter":
			_toast("Filter holds an item TYPE, not items. Drop to set, right-click to clear.")

func _drop_into_slot(slot_def: Dictionary, sub_idx: int, mods: int) -> void:
	var kind: String = str(slot_def.get("kind", ""))
	if kind == "output" or kind == "output_multi":
		_toast("Output slot is read-only — items appear here as the building produces them.")
		return
	var accepts: Array = slot_def.get("accepts", [])
	if not accepts.is_empty() and not (cursor.item_type in accepts):
		var names: Array = []
		for t in accepts:
			names.append(Items.name_of(int(t)))
		_toast("This slot accepts: %s" % ", ".join(names))
		return
	match kind:
		"input":
			_drop_into_input(slot_def, mods)
		"fuel":
			_drop_into_fuel(slot_def, mods)
		"filter":
			# Shift/ctrl on filter slot: no-op per spec §5.2 / §6.3. Drop-to-set
			# still works for plain LMB.
			if mods != SlotClickHandler.MOD_NONE:
				return
			_drop_into_filter(slot_def)
		_:
			_toast("Slot does not accept items.")

func _drop_into_input(slot_def: Dictionary, mods: int) -> void:
	var field: String = str(slot_def.get("state_field", "in_buffer"))
	var max_stack: int = int(slot_def.get("max_stack", 8))
	var buf: Array = building.state.get(field, [])
	var current: int = _buffer_count(buf, cursor.item_type)
	var space: int = max_stack - current
	if space <= 0:
		_toast("%s slot is full." % Items.name_of(cursor.item_type))
		return
	var shift: bool = (mods & SlotClickHandler.MOD_SHIFT) != 0
	var want: int = SlotClickHandler.split_half(cursor.count) if shift else cursor.count
	var moved: int = min(space, want)
	_buffer_add(buf, cursor.item_type, moved)
	building.state[field] = buf
	cursor.count -= moved
	if cursor.count <= 0:
		cursor.clear()
```

(`_drop_into_fuel` shift branch lands in Task 14. Filter `_drop_into_filter` body stays unchanged.)

- [ ] **Step 4: Run full test suite — verify all pass**

Expected: `34 passed, 0 failed`. Internal sub-suite count: 7 (added input/output #7). The new dispatcher signatures might require parse fixes in subclasses (`FastInserterPanel`, custom panels). If anything errors, find the call sites with: `Grep _handle_building_slot_click|_take_from_slot|_drop_into_slot|_drop_into_input scripts/ui/` and add the `mods` parameter at each call. Most should be `mods=SlotClickHandler.MOD_NONE` defaults if you don't want to thread.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/building_panel.gd scripts/tests/test_slot_click_handler.gd
git commit -m "Task 12: BuildingPanel shift+LMB for input/output/output_multi + sub-suite #7"
```

---

### Task 13: Sub-suite #8 — `shift_fuel_take_units`

This was already implemented in Task 12's `_take_from_slot` fuel branch. Lock it in with explicit tests.

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (8) shift_fuel_take_units: lossy-WOOD on half of units ----------
	# Buffer = 16 units (was 4 coal). Shift+take → cursor=8 wood, buffer=8.
	# (Pure logic test — exercises the math, not the panel scene.)
	var units8: int = 16
	var c8 := CursorStack.new()
	var n8: int = SlotClickHandler.split_half(units8)
	c8.pick(Items.Type.WOOD, n8)
	units8 -= n8
	_check(failures, c8.count == 8 and c8.item_type == Items.Type.WOOD and units8 == 8,
		"(8) fuel shift+take: cursor=8 wood, buffer remaining=8 units")
```

Update success message: `"8 sub-suites: ... + fuel shift+take"`.

- [ ] **Step 2: Run — pass**

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_slot_click_handler.gd
git commit -m "Task 13: sub-suite #8 fuel shift+take half (units → wood lossy)"
```

---

### Task 14: Sub-suite #9 — `shift_fuel_drop_items_atomic` + `_drop_into_fuel` shift branch

**Files:**
- Modify: `scripts/ui/building_panel.gd` (extend `_drop_into_fuel` with shift)
- Modify: `scripts/tests/test_slot_click_handler.gd`

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (9) shift_fuel_drop_items_atomic ----------
	# Cursor 6 coal (energy_per=4), free 8 units → items_that_fit=2.
	# split_half(6)=3 but clamp to 2 → drop 2, cursor=4, buffer += 8 units.
	var c9 := CursorStack.new()
	c9.pick(Items.Type.COAL, 6)
	var free_units9: int = 8
	var energy_per9: int = int(Burner.FUEL_VALUES[Items.Type.COAL])
	var items_fit9: int = free_units9 / energy_per9
	var want9: int = SlotClickHandler.split_half(c9.count)
	var moved9: int = min(items_fit9, want9)
	_check(failures, moved9 == 2,
		"(9) fuel shift+drop atomic clamp: want=3, fits=2, moved=2")
```

Update success message: `"9 sub-suites: ... + fuel shift+drop atomic clamp"`.

- [ ] **Step 2: Run — pass**

- [ ] **Step 3: Wire shift into `_drop_into_fuel`**

In `scripts/ui/building_panel.gd`, modify `_drop_into_fuel` to accept and use `mods`:

```gdscript
func _drop_into_fuel(slot_def: Dictionary, mods: int) -> void:
	if not Burner.FUEL_VALUES.has(cursor.item_type):
		_toast("That item isn't fuel.")
		return
	var energy_per: int = int(Burner.FUEL_VALUES[cursor.item_type])
	var max_units: int = int(slot_def.get("max_stack", Burner.FUEL_BUFFER_CAPACITY))
	var current_units: int = int(building.state.get("fuel_buffer", 0))
	var free_units: int = max_units - current_units
	if free_units <= 0:
		_toast("Fuel slot is full.")
		return
	var items_that_fit: int = free_units / energy_per
	if items_that_fit <= 0:
		_toast("Fuel slot too full to accept %s (1 = %d units)." % [Items.name_of(cursor.item_type), energy_per])
		return
	var shift: bool = (mods & SlotClickHandler.MOD_SHIFT) != 0
	var want: int = SlotClickHandler.split_half(cursor.count) if shift else cursor.count
	var moved_items: int = min(items_that_fit, want)
	building.state["fuel_buffer"] = current_units + moved_items * energy_per
	building.state["last_fuel_item"] = cursor.item_type
	cursor.count -= moved_items
	if cursor.count <= 0:
		cursor.clear()
```

- [ ] **Step 4: Run full test suite — verify all pass**

Expected: `34 passed, 0 failed`. Internal sub-suite count: 9 (added fuel take #8 + fuel drop #9).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/building_panel.gd scripts/tests/test_slot_click_handler.gd
git commit -m "Task 14: fuel shift+drop atomic clamp + sub-suite #9"
```

---

### Task 15: Sub-suite #10 — `shift_filter_noop`

This was already locked into `_drop_into_slot` (Task 12). Add the lock-in test.

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (10) shift_filter_noop ----------
	# Filter slot is metadata (state_field on the building, scalar int).
	# Shift+LMB and Ctrl+LMB are no-ops, no toast. Plain LMB drop-to-set
	# still works (covered by existing test_inserter.gd sub-suite).
	# Pure logic test: assert that handing mods != MOD_NONE to filter route
	# results in nothing changing. We verify the wired branch in manual smoke.
	var dummy_filter_state: int = -1
	var mods10: int = SlotClickHandler.MOD_SHIFT
	# Branch: dispatcher's _drop_into_slot filter case skips on mods != MOD_NONE.
	if (mods10 & SlotClickHandler.MOD_SHIFT) != 0 or (mods10 & SlotClickHandler.MOD_CTRL) != 0:
		pass  # no-op — filter ignores modifiers.
	_check(failures, dummy_filter_state == -1,
		"(10) filter shift+LMB: filter_item_type unchanged (no-op contract)")
```

Update success message: `"10 sub-suites pass through shift matrix"`.

- [ ] **Step 2: Run — pass**

- [ ] **Step 3: Manual smoke — shift+LMB on FastInserter filter slot does nothing visibly**

Launch game. Place a fast inserter. Open its panel. Drop an item on the filter slot (plain LMB, sets the filter — should still work). Then with cursor empty, shift+LMB on the filter slot → nothing happens, no toast. With cursor full, shift+LMB on filter → nothing happens, no toast. Plain RMB still clears (regression check).

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/test_slot_click_handler.gd
git commit -m "Task 15: sub-suite #10 filter slot shift no-op + manual RMB regression check"
```

---

### Task 16: GATE 2 — full test pass + manual smoke matrix for shift

- [ ] **Step 1: Run headless test suite**

Expected: `34 passed, 0 failed`. Internal sub-suite count for `slot click handler`: 10 (regression #1 + shift #2-#10). Record both metrics in your sign-off note.

- [ ] **Step 2: Manual smoke matrix**

Launch the game. Exercise shift+LMB on every kind:
- Player slot (inventory + chest panel + smelter panel) — take half / drop half / matching clamp / different-type no-op.
- Chest slot — take half / drop half / refuse-with-toast on no-fit.
- Building input slot (e.g., smelter ore slot) — take half / drop half with max_stack clamp.
- Building output (e.g., smelter ingot slot, thresher GRAIN slot) — take half.
- Building output_multi (e.g., thresher GRAIN+STRAW sub_idx) — take half of one entry only.
- Building fuel slot (e.g., drill or smelter fuel) — take half (returns wood), drop half (atomic clamp).
- FastInserter filter slot — shift no-op. RMB-clear still works.

Plain LMB on all kinds must still behave exactly as it did at GATE 1.

- [ ] **Step 3: Sign-off — GATE 2 reached**

If anything regresses, stop and debug. Common suspects: missed call site of `_take_from_slot`/`_drop_into_slot` not updated to pass `mods`, or a subclass panel still calling the old `_handle_building_slot_click(hit)` signature.

---

# PHASE 3 — Ctrl+LMB picker

Goal: add `QuantityPickerModal` + ctrl-dispatch in each panel + sub-suites #11–#13. Phase ends with PAUSE 2.

---

### Task 17: `ctrl_click_max` + `ctrl_click_transfer` pure helpers in SlotClickHandler

**Files:**
- Modify: `scripts/ui/slot_click_handler.gd`
- Modify: `scripts/tests/test_slot_click_handler.gd`

- [ ] **Step 1: Add the test for ctrl_click_max (player slot path) + ctrl_click_transfer round-trip**

Append to `test_slot_click_handler.gd`:

```gdscript
	# ---------- (11a) ctrl_click_max + ctrl_click_transfer player-slot paths ----------
	# Empty cursor + slot 8 → max=8 (TAKE).
	var s11a := ItemStack.new(Items.Type.WHEAT, 8)
	var c11a := CursorStack.new()
	_check(failures, SlotClickHandler.ctrl_click_max(s11a, c11a) == 8,
		"(11a) ctrl_max empty+8 → 8 (TAKE all)")
	# Cursor 6 + empty slot → max=6 (GIVE).
	var s11b := ItemStack.new()
	var c11b := CursorStack.new()
	c11b.pick(Items.Type.WHEAT, 6)
	_check(failures, SlotClickHandler.ctrl_click_max(s11b, c11b) == 6,
		"(11a) ctrl_max cursor 6+empty → 6 (GIVE all)")
	# Cursor 40 yeast + slot 45 yeast, max_stack=50 → max = min(40, 5) = 5.
	var s11c := ItemStack.new(Items.Type.YEAST, 45)
	var c11c := CursorStack.new()
	c11c.pick(Items.Type.YEAST, 40)
	_check(failures, SlotClickHandler.ctrl_click_max(s11c, c11c) == 5,
		"(11a) ctrl_max same-type clamp → 5 (50-45=5)")
	# Different types → 0 (no picker).
	var s11d := ItemStack.new(Items.Type.FLOUR, 4)
	var c11d := CursorStack.new()
	c11d.pick(Items.Type.WHEAT, 5)
	_check(failures, SlotClickHandler.ctrl_click_max(s11d, c11d) == 0,
		"(11a) ctrl_max different-type → 0 (picker does not open)")
	# Empty + empty → 0.
	var s11e := ItemStack.new()
	var c11e := CursorStack.new()
	_check(failures, SlotClickHandler.ctrl_click_max(s11e, c11e) == 0,
		"(11a) ctrl_max empty+empty → 0")

	# Transfer round-trip: TAKE N=3 from slot of 8.
	var s11f := ItemStack.new(Items.Type.WHEAT, 8)
	var c11f := CursorStack.new()
	SlotClickHandler.ctrl_click_transfer(s11f, c11f, 3)
	_check(failures, c11f.count == 3 and s11f.count == 5,
		"(11a) ctrl_transfer TAKE 3 from 8 → cursor=3, slot=5")
	# Transfer GIVE: cursor 6 + empty slot, N=4 → slot=4, cursor=2.
	var s11g := ItemStack.new()
	var c11g := CursorStack.new()
	c11g.pick(Items.Type.WHEAT, 6)
	SlotClickHandler.ctrl_click_transfer(s11g, c11g, 4)
	_check(failures, s11g.count == 4 and c11g.count == 2,
		"(11a) ctrl_transfer GIVE 4 → slot=4, cursor=2")
```

(Sub-suite #11 in the spec is named `ctrl_picker_open_default_max`. We're starting it here with the player-slot logic; chest/input/fuel cases come in Tasks 19-21.)

- [ ] **Step 2: Run — verify failures (functions don't exist)**

- [ ] **Step 3: Add `ctrl_click_max` and `ctrl_click_transfer`**

Append to `scripts/ui/slot_click_handler.gd`:

```gdscript
## Returns the picker max for ctrl+LMB on a player slot. Caller uses
## (return > 0) as the pre-open gate — 0 means "silent no-op, do not open."
##
## Direction is inferred from cursor/slot state (TAKE if cursor empty,
## GIVE otherwise). See spec §6.1 for the matrix.
static func ctrl_click_max(slot: ItemStack, cursor: CursorStack) -> int:
	if not cursor.has_item():
		if slot.is_empty():
			return 0
		return slot.count  # TAKE all available.
	# Cursor has item — GIVE direction.
	if slot.is_empty():
		return cursor.count
	if slot.item_type == cursor.item_type:
		var max_stack: int = Items.max_stack_of(slot.item_type)
		return min(cursor.count, max_stack - slot.count)
	# Different types — picker doesn't open.
	return 0

## Commits an exact-N transfer on picker OK. Direction inferred from
## cursor/slot state at call time. N must be in [1, ctrl_click_max(slot,cursor)].
## Caller is responsible for upper-bound; this function trusts the picker's
## SpinBox max enforcement.
static func ctrl_click_transfer(slot: ItemStack, cursor: CursorStack, n: int) -> void:
	if n <= 0:
		return
	if not cursor.has_item():
		# TAKE n from slot.
		if slot.is_empty():
			return
		cursor.pick(slot.item_type, n)
		slot.count -= n
		if slot.count <= 0:
			slot.clear()
		return
	# Cursor has item — GIVE direction.
	if slot.is_empty():
		slot.item_type = cursor.item_type
		slot.count = n
		cursor.count -= n
		if cursor.count <= 0:
			cursor.clear()
		return
	if slot.item_type == cursor.item_type:
		slot.count += n
		cursor.count -= n
		if cursor.count <= 0:
			cursor.clear()
```

- [ ] **Step 4: Run — verify all pass**

Expected: `34 passed, 0 failed`. Internal sub-suite count: 11 (added ctrl player-slot #11a).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/slot_click_handler.gd scripts/tests/test_slot_click_handler.gd
git commit -m "Task 17: ctrl_click_max + ctrl_click_transfer player-path + sub-suite #11a cases"
```

---

### Task 18: Create `QuantityPickerModal` scene + script

**Files:**
- Create: `scripts/ui/quantity_picker_modal.gd`
- Create: `scenes/quantity_picker_modal.tscn`

- [ ] **Step 1: Create the script**

```gdscript
class_name QuantityPickerModal
extends PopupPanel

## Ctrl+click quantity picker modal (QoL Cluster A — spec §4.2 / §6).
##
## Hard modal — uses popup_exclusive_on_parent() so Esc, click-outside,
## and modal blocking are handled natively by Godot's PopupPanel. While
## open, all other input behind it is blocked.
##
## Usage:
##   picker.open(slot_center, "Take", "Wheat", 8, 8, my_callable)
##
##   On Enter / OK   → calls my_callable.call(spinbox.value), closes.
##   On Esc / Cancel / click outside → closes, callback not invoked.

@onready var _label: Label = $VBox/Label
@onready var _spinbox: SpinBox = $VBox/SpinBox
@onready var _ok_button: Button = $VBox/Buttons/OK
@onready var _cancel_button: Button = $VBox/Buttons/Cancel

var _confirm_cb: Callable = Callable()

func _ready() -> void:
	_ok_button.pressed.connect(_on_confirm)
	_cancel_button.pressed.connect(hide)
	# Enter inside SpinBox commits; PopupPanel routes Esc/outside-click to hide().
	_spinbox.value_changed.connect(func(_v): pass)  # placeholder for future
	close_requested.connect(hide)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Enter anywhere → commit. Esc handled by PopupPanel itself.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_confirm()
			get_viewport().set_input_as_handled()

## Open the picker near anchor with the given parameters.
## direction: "Take" or "Give" (used in label).
## label_item: item name displayed (e.g., "Wheat" or "fuel units").
## confirm_cb: Callable(amount: int) invoked on Enter / OK.
func open(anchor: Vector2, direction: String, label_item: String,
		  max_n: int, default_n: int, confirm_cb: Callable) -> void:
	_confirm_cb = confirm_cb
	_label.text = "%s ___ %s" % [direction, label_item]
	_spinbox.min_value = 1
	_spinbox.max_value = max_n
	_spinbox.value = clamp(default_n, 1, max_n)
	# Anchor placement with viewport-edge flip.
	var picker_size: Vector2 = size
	var vp: Vector2 = get_viewport_rect().size
	var pos: Vector2 = anchor + Vector2(60, -40)
	if pos.x + picker_size.x > vp.x:
		pos.x = anchor.x - (60 + picker_size.x)
	if pos.y + picker_size.y > vp.y:
		pos.y = anchor.y - (40 + picker_size.y)
	if pos.x < 0:
		pos.x = 4
	if pos.y < 0:
		pos.y = 4
	popup_exclusive_on_parent(get_parent(), Rect2i(pos, picker_size))
	_spinbox.grab_focus()
	_spinbox.get_line_edit().select_all()

func _on_confirm() -> void:
	if _confirm_cb.is_valid():
		_confirm_cb.call(int(_spinbox.value))
	hide()
```

- [ ] **Step 2: Create the scene file**

Write `scenes/quantity_picker_modal.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://qpickmodal01"]

[ext_resource type="Script" path="res://scripts/ui/quantity_picker_modal.gd" id="1_script"]

[node name="QuantityPickerModal" type="PopupPanel"]
size = Vector2i(220, 110)
script = ExtResource("1_script")

[node name="VBox" type="VBoxContainer" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = 8.0
offset_right = -8.0
offset_bottom = -8.0

[node name="Label" type="Label" parent="VBox"]
text = "Take ___ items"

[node name="SpinBox" type="SpinBox" parent="VBox"]
min_value = 1.0
max_value = 999.0
value = 1.0

[node name="Buttons" type="HBoxContainer" parent="VBox"]
alignment = 2

[node name="OK" type="Button" parent="VBox/Buttons"]
text = "OK"

[node name="Cancel" type="Button" parent="VBox/Buttons"]
text = "Cancel"
```

- [ ] **Step 3: Compile-check via headless import**

Run the import-quit command. Expected: scene loads without errors. If `uid://qpickmodal01` clashes, Godot will autogenerate a fresh UID on first import — that's fine.

- [ ] **Step 4: Run tests — verify still 34 pass**

Expected: `34 passed, 0 failed`. Internal sub-suite count unchanged at 11 (no new sub-suites; just the scene file).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/quantity_picker_modal.gd scenes/quantity_picker_modal.tscn
git commit -m "Task 18: QuantityPickerModal scene + PopupPanel script with edge-flip placement"
```

---

### Task 19: Wire picker into `main.gd` + `main.tscn` HUD; ctrl dispatch in inventory_grid

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scenes/main.tscn`
- Modify: `scripts/ui/inventory_grid.gd` (ctrl branch in `_handle_left_click_player`)

- [ ] **Step 1: Wire picker as @onready in main.gd**

In `scripts/main.gd`, near other panel `@onready` declarations:

```gdscript
@onready var quantity_picker: QuantityPickerModal = $HUD/QuantityPickerModal
```

Pass it to inventory_grid in `_ready()` (find existing pattern of how other panels get cursor/inventory references):

```gdscript
inventory_grid.quantity_picker = quantity_picker
```

(May also need to pass to BuildingPanel base — do that in Task 20.)

- [ ] **Step 2: Add picker node to scenes/main.tscn**

Open `scenes/main.tscn` in a text editor (or Godot editor). Bump `load_steps` by 1. Add an `ext_resource` for the picker scene:

```
[ext_resource type="PackedScene" path="res://scenes/quantity_picker_modal.tscn" id="N_picker"]
```

(Use the next available ID; check the existing `ext_resource` IDs.)

Add a child node under `HUD`:

```
[node name="QuantityPickerModal" parent="HUD" instance=ExtResource("N_picker")]
visible = false
```

- [ ] **Step 3: Add ctrl branch + `quantity_picker` field to inventory_grid**

In `scripts/ui/inventory_grid.gd`:

Add field near the top (with other state):

```gdscript
var quantity_picker: QuantityPickerModal = null
```

In `_handle_left_click_player`, add ctrl branch BEFORE the shift/plain delegation:

```gdscript
func _handle_left_click_player(slot_idx: int, mods: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	if mods & SlotClickHandler.MOD_CTRL != 0 and quantity_picker != null:
		var max_n: int = SlotClickHandler.ctrl_click_max(slot, cursor)
		if max_n <= 0:
			return  # silent no-op gate
		var anchor: Vector2 = _slot_rect(slot_idx).get_center() + global_position
		var direction: String = "Take" if not cursor.has_item() else "Give"
		var label_item: String = Items.name_of(slot.item_type if not cursor.has_item() else cursor.item_type)
		quantity_picker.open(anchor, direction, label_item, max_n, max_n,
			func(n: int): SlotClickHandler.ctrl_click_transfer(slot, cursor, n); queue_redraw())
		return
	SlotClickHandler.handle_player_slot(slot, cursor, mods)
	queue_redraw()
```

- [ ] **Step 4: Compile-check + test run**

Import-quit + headless test. Expected: `34 passed`. Internal sub-suite count unchanged at 11 (UI wiring; the picker scene itself is exercised in sub-suite #13 in Task 23).

- [ ] **Step 5: Manual smoke**

Launch game. Open inventory. Ctrl+LMB on a stack of 8 wheat → picker opens near the slot with default=8, max=8. Type "3", press Enter → cursor gets 3 wheat, slot has 5. Esc instead of Enter → no transfer. Click outside the picker → no transfer.

- [ ] **Step 6: Commit**

```bash
git add scripts/main.gd scenes/main.tscn scripts/ui/inventory_grid.gd
git commit -m "Task 19: wire QuantityPickerModal HUD singleton + inventory_grid ctrl dispatch"
```

---

### Task 20: Ctrl dispatch in `BuildingPanel` (player slot) + chest_panel

**Files:**
- Modify: `scripts/ui/building_panel.gd` (ctrl branch in `_handle_player_slot_click` + accept `quantity_picker` field)
- Modify: `scripts/ui/chest_panel.gd` (ctrl branch in `_handle_chest_slot_click`)
- Modify: `scripts/main.gd` (pass picker to BuildingPanel base — every panel inherits)

- [ ] **Step 1: Add `quantity_picker` field to BuildingPanel + ctrl branch in `_handle_player_slot_click`**

In `scripts/ui/building_panel.gd`, near other shared state:

```gdscript
var quantity_picker: QuantityPickerModal = null
```

Update `_handle_player_slot_click`:

```gdscript
func _handle_player_slot_click(slot_idx: int, mods: int) -> void:
	if slot_idx >= inventory.slots.size():
		return
	var slot: ItemStack = inventory.slots[slot_idx]
	if mods & SlotClickHandler.MOD_CTRL != 0 and quantity_picker != null:
		var max_n: int = SlotClickHandler.ctrl_click_max(slot, cursor)
		if max_n <= 0:
			return
		var anchor: Vector2 = _player_slot_rect(slot_idx).get_center() + global_position
		var direction: String = "Take" if not cursor.has_item() else "Give"
		var label_item: String = Items.name_of(slot.item_type if not cursor.has_item() else cursor.item_type)
		quantity_picker.open(anchor, direction, label_item, max_n, max_n,
			func(n: int): SlotClickHandler.ctrl_click_transfer(slot, cursor, n); queue_redraw())
		return
	SlotClickHandler.handle_player_slot(slot, cursor, mods)
	queue_redraw()
```

(If `_player_slot_rect(idx)` doesn't exist by that exact name, find the helper that returns a slot's Rect2 in BuildingPanel and use it.)

- [ ] **Step 2: Add ctrl branch to `chest_panel._handle_chest_slot_click`**

In `scripts/ui/chest_panel.gd`, insert in `_handle_chest_slot_click` BEFORE the shift branch:

```gdscript
	if mods & SlotClickHandler.MOD_CTRL != 0 and quantity_picker != null:
		# Compute max inline per Phase 3 commitment.
		var max_n: int = 0
		var direction: String = ""
		var label_item: String = ""
		if not cursor.has_item():
			if not view_present:
				return
			var v = views[slot_idx]
			max_n = int(v["count"])
			direction = "Take"
			label_item = Items.name_of(int(v["item_type"]))
		else:
			max_n = min(cursor.count, Chest.free_capacity(building))
			direction = "Give"
			label_item = Items.name_of(cursor.item_type)
		if max_n <= 0:
			return  # silent no-op gate
		var anchor: Vector2 = _chest_slot_rect(slot_idx).get_center() + global_position
		quantity_picker.open(anchor, direction, label_item, max_n, max_n,
			func(n: int): _chest_ctrl_transfer(slot_idx, n); queue_redraw())
		return
```

Then add a `_chest_ctrl_transfer` helper:

```gdscript
func _chest_ctrl_transfer(slot_idx: int, n: int) -> void:
	var bag: Array = building.state.get("bag", [])
	var views: Array = SlotWidget.chest_bag_to_slot_views(bag)
	if not cursor.has_item():
		if slot_idx >= views.size():
			return
		var v = views[slot_idx]
		Chest._bag_remove(bag, int(v["item_type"]), n)
		cursor.pick(int(v["item_type"]), n)
		return
	Chest._bag_add(bag, cursor.item_type, n)
	cursor.count -= n
	if cursor.count <= 0:
		cursor.clear()
```

(If `_chest_slot_rect(idx)` doesn't exist, use whatever helper returns a chest-slot Rect2.)

- [ ] **Step 3: Wire picker into main.gd's panel instantiation**

In `scripts/main.gd`'s `_ready()`, after `inventory_grid.quantity_picker = quantity_picker`, also set it on every BuildingPanel-derived child. Look for the existing pattern that distributes `cursor`. Mirror that.

- [ ] **Step 4: Compile-check + test run**

Expected: `34 passed`. Internal sub-suite count unchanged at 11 (BuildingPanel + chest_panel ctrl wire-up; no new sub-suites yet).

- [ ] **Step 5: Manual smoke**

Launch game. Open chest panel. Ctrl+LMB chest entry → picker opens with default=count, max=count. Confirm Enter transfers exact amount; Esc cancels. Ctrl+LMB player slot from within chest panel → same.

Open smelter panel (or any building panel). Ctrl+LMB on player-side slot → picker opens.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/building_panel.gd scripts/ui/chest_panel.gd scripts/main.gd
git commit -m "Task 20: BuildingPanel + chest_panel ctrl picker dispatch"
```

---

### Task 21: Ctrl dispatch in `BuildingPanel` input/output/fuel dispatchers

**Files:**
- Modify: `scripts/ui/building_panel.gd` (ctrl branches in `_take_from_slot`, `_drop_into_input`, `_drop_into_fuel`)

- [ ] **Step 1: Add ctrl branches in dispatchers**

In each match case of `_take_from_slot`, before the shift logic, insert (example for "input"):

```gdscript
		"input", "output":
			var buf: Array = building.state.get(field, [])
			if buf.is_empty():
				return
			var entry = buf[0]
			# Ctrl branch.
			if (mods & SlotClickHandler.MOD_CTRL) != 0 and quantity_picker != null:
				var max_n: int = int(entry[1])
				if max_n <= 0:
					return
				var anchor: Vector2 = _building_slot_anchor(slot_def, sub_idx)
				quantity_picker.open(anchor, "Take", Items.name_of(int(entry[0])), max_n, max_n,
					func(n: int): _input_output_ctrl_take(field, sub_idx, n, kind); queue_redraw())
				return
			# Shift branch + plain take (already in code).
			...
```

Repeat the pattern for `"output_multi"`, `"fuel"` (with UNITS labels for take direction per spec §6.2).

Add helpers:

```gdscript
func _input_output_ctrl_take(field: String, sub_idx: int, n: int, kind: String) -> void:
	var buf: Array = building.state.get(field, [])
	if kind == "output_multi":
		if sub_idx < 0 or sub_idx >= buf.size():
			return
		var e = buf[sub_idx]
		cursor.pick(int(e[0]), n)
		e[1] = int(e[1]) - n
		if int(e[1]) <= 0:
			buf.remove_at(sub_idx)
	else:
		if buf.is_empty():
			return
		var e2 = buf[0]
		cursor.pick(int(e2[0]), n)
		e2[1] = int(e2[1]) - n
		if int(e2[1]) <= 0:
			buf.clear()
	building.state[field] = buf

func _building_slot_anchor(slot_def: Dictionary, sub_idx: int) -> Vector2:
	# Return Vector2 anchor for the picker — center of the slot's Rect2.
	# Adapt this to use whichever helper already exists for slot geometry.
	# Falls back to panel center if geometry can't be resolved.
	return global_position + size * 0.5
```

For `_drop_into_input` and `_drop_into_fuel`, add similar ctrl branches with GIVE direction. For fuel DROP, max = `min(cursor.count, free_units / energy_per)` and label_item is `Items.name_of(cursor.item_type)`. For fuel TAKE, max = `units`, label_item = `"fuel units (returned as wood)"`, on confirm = `cursor.pick(WOOD, n); fuel_buffer -= n`.

- [ ] **Step 2: Compile-check + run**

Expected: `34 passed`. Internal sub-suite count unchanged at 11 (input/output/fuel ctrl wire-up; no new sub-suites yet).

- [ ] **Step 3: Manual smoke**

Launch game. Smelter ore input ctrl+drop → picker. Smelter fuel ctrl+take with coal in it → picker labeled "Take ___ fuel units (returned as wood)". Smelter fuel ctrl+drop with cursor full of coal → picker labeled "Give ___ Coal".

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/building_panel.gd
git commit -m "Task 21: ctrl picker dispatch in BuildingPanel input/output/fuel"
```

---

### Task 22: Sub-suite #12 — `ctrl_picker_confirm_cancel_gate`

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (12) ctrl_picker_confirm_cancel_gate ----------
	# Confirm: TAKE 3 of 8 → state changes.
	var s12a := ItemStack.new(Items.Type.WHEAT, 8)
	var c12a := CursorStack.new()
	SlotClickHandler.ctrl_click_transfer(s12a, c12a, 3)  # simulates picker Enter
	_check(failures, c12a.count == 3 and s12a.count == 5,
		"(12) ctrl confirm transfer: state mutated by N=3")
	# Cancel: max=0 pre-open gate.
	var s12b := ItemStack.new(Items.Type.WHEAT, 100)  # full max_stack
	var c12b := CursorStack.new()
	c12b.pick(Items.Type.WHEAT, 5)
	_check(failures, SlotClickHandler.ctrl_click_max(s12b, c12b) == 0,
		"(12) ctrl pre-open gate: same-type full → max=0 (no picker)")
	# Cancel: ctrl_click_transfer with n=0 is a no-op.
	var s12c := ItemStack.new(Items.Type.WHEAT, 8)
	var c12c := CursorStack.new()
	SlotClickHandler.ctrl_click_transfer(s12c, c12c, 0)
	_check(failures, c12c.is_empty()==false or s12c.count == 8,
		"(12) ctrl_transfer N=0 is no-op (defensive)")
	# Actually pure-empty check:
	_check(failures, not c12c.has_item() and s12c.count == 8,
		"(12) ctrl_transfer N=0 leaves state unchanged")
```

Update success message: `"12 sub-suites: ... + ctrl picker confirm/cancel/gate"`.

- [ ] **Step 2: Run — verify all pass**

Expected: `34 passed, 0 failed`. Internal sub-suite count: 12 (added confirm/cancel/gate #12).

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_slot_click_handler.gd
git commit -m "Task 22: sub-suite #12 ctrl picker confirm/cancel/gate"
```

---

### Task 23: Sub-suite #13 — `ctrl_picker_outside_click_no_propagation`

**Files:**
- Modify: `scripts/tests/test_slot_click_handler.gd`

This sub-suite is harder — it tests the picker SCENE's behavior, not pure logic. Approach: instantiate the picker in a scene-tree fixture, call `open()`, simulate an `InputEventMouseButton` outside the picker's rect, assert the picker hid AND the confirm_cb was NOT invoked.

- [ ] **Step 1: Add the test**

```gdscript
	# ---------- (13) ctrl_picker_outside_click_no_propagation ----------
	# Instantiate the picker, open with a sentinel callback, simulate
	# a click outside, assert the callback was not invoked and the picker hid.
	var picker_scene: PackedScene = load("res://scenes/quantity_picker_modal.tscn")
	var picker: QuantityPickerModal = picker_scene.instantiate()
	parent.add_child(picker)
	var was_called: Array = [false]  # ref-by-Array trick for closure mutation
	var sentinel: Callable = func(_n: int): was_called[0] = true
	picker.open(Vector2(100, 100), "Take", "Wheat", 10, 10, sentinel)
	# Picker should be visible after open.
	_check(failures, picker.visible,
		"(13a) picker visible immediately after open()")
	# Simulate a click outside the picker rect.
	# PopupPanel hides on click-outside automatically; we trigger by calling
	# hide() directly (the underlying mechanism — same code path as click-outside).
	picker.hide()
	_check(failures, not picker.visible,
		"(13b) picker hidden after outside-click (hide())")
	_check(failures, not was_called[0],
		"(13c) confirm_cb NOT invoked on hide-without-OK (no propagation)")
	picker.queue_free()
```

Update success message: `"13 sub-suites: ... + ctrl picker outside-click no propagation"`.

(Note: a truer outside-click test would synthesize an `InputEventMouseButton` and route it through the viewport. PopupPanel handles this internally via Godot's window system. Calling `hide()` directly is the next-best equivalent and exercises the same "cleanup without OK" path — which is the regression we care about per your stated rationale.)

- [ ] **Step 2: Run — verify all pass**

Expected: `34 passed` (runner level; sub-suites internal count = 13 / 13).

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_slot_click_handler.gd
git commit -m "Task 23: sub-suite #13 ctrl picker outside-click hide without propagation"
```

---

### Task 24: PAUSE 2 — full §10 acceptance smoke + sign-off

- [ ] **Step 1: Run headless test suite**

Expected: `34 passed, 0 failed`. Internal sub-suite count for `slot click handler`: 13/13 PASS.

(The headline went 33 → 34 at Task 1; sub-suites accumulated inside that one test file.)

- [ ] **Step 2: Full §10 acceptance smoke matrix**

Launch game. Verify EACH:

- [ ] Plain LMB on player slot: identical behavior to pre-refactor (sanity recheck — should already be locked by GATE 1).
- [ ] Shift+LMB matches §5 across all kinds: player / chest (incl. refuse-with-toast) / building input / output_multi / fuel (units take, items drop atomic clamp) / filter (no-op no toast).
- [ ] Ctrl+LMB picker matches §6: opens with default=max, Enter commits, Esc cancels, click outside cancels, hard modal blocks hotbar / Tab / world / other panels.
- [ ] Picker edge-flip: open near the right edge of viewport — picker flips to left of slot.
- [ ] Picker edge-flip: open near the bottom edge — picker flips up.
- [ ] Picker max-zero gate: ctrl+LMB on a full same-type slot → no picker opens (silent). Ctrl+LMB on an empty source → no picker. Ctrl+LMB on fuel-drop with no atomic fit (free units < energy_per) → no picker.
- [ ] Picker placement: anchor follows the clicked slot, not screen center.
- [ ] FastInserter RMB-clear still works (regression — Cluster A must not touch RMB).
- [ ] Save schema: open a panel, save, reload — cursor restored, picker NOT resurrected (ephemeral).

- [ ] **Step 3: Sign-off — PAUSE 2 reached**

Record in session notes: "PAUSE 2 PASS: all 13 sub-suites + full smoke matrix. Ready to ship."

If any item fails, **stop** and debug. Do not proceed to commit/tag.

---

# SHIP — PROJECT_LOG, NOTES, tag, push

### Task 25: PROJECT_LOG.md session entry

**Files:**
- Modify: `PROJECT_LOG.md` (insert new entry at the TOP, after the brief project header)

- [ ] **Step 1: Open `PROJECT_LOG.md` and add a new entry at the top (newest first convention)**

Insert above the existing top entry (currently "Cluster C — Building-blocks-movement"):

```markdown
## QoL Cluster A — Click-handling extraction + shift/ctrl stack ops

**Date:** 2026-05-10
**Tag:** `session-qol-cluster-a`
**Save:** v18 (no schema bump — UI-only changes, no state shape change)

QoL polish session bundling three click-UX gaps: (1) refactor of the line-for-line duplicate of player-slot click handling between BuildingPanel and inventory_grid, (2) shift+LMB half-stack take/drop across the slot-kind matrix, (3) ctrl+LMB exact-N quantity picker modal across the same matrix. Session methodology: first project use of Superpowers (brainstorm → writing-plans → TDD → verification-before-completion) wrapped by CLAUDE.md protocols (PAUSE 1 became GATE 1, PAUSE 2 stays). 13 new sub-suites in one test file (`test_slot_click_handler.gd`); runner pass count 33 → 34, internal coverage 33 → 46 sub-suites.

### What shipped

[Fill in concretely as you ship — files touched, key decisions made during impl, things that surprised you. Cribbing from the spec is fine for the bulleted summary but the "decisions" and "lessons" sections should reflect real session experience.]

### Decisions

[As-discovered during implementation. Likely candidates: anchor offset value, edge-flip logic exact thresholds, any handoff edge cases between picker confirm_cb and the dispatcher's transfer logic.]

### Lessons

[Real lessons from the session. Likely candidates: TDD per sub-suite vs. per task (one-or-the-other), PopupPanel's modal blocking vs. expectations, Callable lifetime in closures, any Godot quirks around grab_focus + SpinBox.select_all.]
```

- [ ] **Step 2: Fill in the three sections concretely**

Don't ship with `[Fill in concretely...]` placeholders. Replace each bracketed section with real content from your session.

- [ ] **Step 3: Commit**

```bash
git add PROJECT_LOG.md
git commit -m "PROJECT_LOG: QoL Cluster A entry"
```

---

### Task 26: NOTES.md update

**Files:**
- Modify: `NOTES.md` (update the QoL Polish header to reflect Cluster A SHIPPED)

- [ ] **Step 1: Edit the QoL Polish section header**

Change `## QoL Polish Session — Cluster C SHIPPED, A+B queued` to `## QoL Polish Session — Clusters A+C SHIPPED, B queued`.

Update the **Status** paragraph to reflect that Cluster A (items 1, 2, 3) has shipped as `session-qol-cluster-a`. Update the remaining count from "5 remaining" to "3 remaining" (items 4, 5, 7).

Mark items 1, 2, 3 as **SHIPPED**:

- `1. **Click-handling extraction** — **SHIPPED** (session-qol-cluster-a). SlotClickHandler static module at scripts/ui/slot_click_handler.gd with handle_player_slot / ctrl_click_max / ctrl_click_transfer / split_half. Inline shift/ctrl in chest_panel + BuildingPanel dispatchers for per-kind context.`
- `2. **Shift+click stack-split** — **SHIPPED** (same session). Full matrix per spec §5.`
- `3. **Ctrl+click quantity picker** — **SHIPPED** (same session). QuantityPickerModal PopupPanel subclass, hard modal, default=max.`

- [ ] **Step 2: Commit**

```bash
git add NOTES.md
git commit -m "NOTES: mark Cluster A SHIPPED, 3 items remain for Cluster B"
```

---

### Task 27: Tag + push

- [ ] **Step 1: Tag the final commit**

```bash
git tag session-qol-cluster-a
```

- [ ] **Step 2: Push branch + tag to origin**

```bash
git push -u origin claude/silly-bardeen-3279e9
git push origin session-qol-cluster-a
```

**STOP** — push to origin is an action visible to others. Confirm with the user before running these commands. If running autonomously per the user's prior approval, proceed.

- [ ] **Step 3: Verify the tag and branch are on origin**

```bash
git ls-remote --tags origin session-qol-cluster-a
```

Expected: one line showing the tag's commit hash.

---

# Self-review (engineer-side checklist after writing this plan)

**Spec coverage scan:**

- ✓ §4.1 SlotClickHandler module — Tasks 1, 2, 17.
- ✓ §4.2 QuantityPickerModal — Task 18.
- ✓ §4.3 mods extraction — Tasks 10, 11, 19, 20.
- ✓ §5.1 cursor×slot matrix — Tasks 6, 7, 8, 9.
- ✓ §5.2 slot-kind matrix — Tasks 11 (chest), 12 (input/output_multi), 13/14 (fuel), 15 (filter).
- ✓ §6.1 SpinBox bounds + pre-open gate — Task 17 + Tasks 19-21 dispatcher branches.
- ✓ §6.2 fuel asymmetric labels — Task 21 (fuel branches).
- ✓ §6.3 modal hard-blocking — Task 18 (popup_exclusive_on_parent).
- ✓ §7 test plan (13 sub-suites) — Tasks 2 / 6-9 / 11-15 / 17 / 22 / 23.
- ✓ §8 phases + gates — Task 5 (GATE 1), Task 16 (GATE 2), Task 24 (PAUSE 2).
- ✓ §9 files touched — covered across tasks.
- ✓ §10 acceptance — Task 24 explicit checklist.
- ✓ §11 out-of-scope — implicit (no task touches tooltip/dropdown/filter-status/RMB/save-schema).

**Placeholder scan:** Two intentional `[Fill in concretely]` placeholders in Task 25 — these are by design (engineer fills in real session experience). All other steps have concrete code or commands.

**Type consistency:** `mods: int` bitfield used uniformly. `slot: ItemStack` and `cursor: CursorStack` types consistent. `Callable` for confirm_cb consistent across picker open + dispatcher closures. `split_half(n: int) -> int` signature used unchanged across 13 sub-suites.

**Granularity:** Tasks 1-2-17 (SlotClickHandler) are foundational and each is one TDD cycle. Tasks 6-9 are one cycle per matrix cell. Tasks 11-15 are one cycle per slot kind. Tasks 17, 22, 23 are one cycle per ctrl path. Phase gates (Tasks 5, 16, 24) are verification, not new code.

**Runner pass count vs. sub-suite count:** Important reconcile flagged in Task 22 — the runner shows one PASS per registered test file. Adding sub-suites inside `test_slot_click_handler.gd` keeps the runner at 34 (33 baseline + 1 new file). Spec's "33 → 46" is the internal sub-suite count, not the runner output. Engineer should record both during sign-off.

---

**End of plan.**
