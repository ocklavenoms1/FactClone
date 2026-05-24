# QoL Cluster B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 5 UX polish items — item hover tooltips, filter dropdown picker, filter status diagnostic, E-key hover-aware dispatch, chest silent-merge on same-type.

**Architecture:** Single TooltipManager Control (mirrors `QuantityPickerModal` pattern), Items.gd `description` field with code-citation-grounded text, new `ItemPickerModal` (cloned from `QuantityPickerModal` for list-vs-spinbox UI shape). E-key hover-aware via `grid_world.world_to_tile(mouse_world)` lookup with fallback to current scan. Chest fix is 5-line silent-merge branch at `chest_panel.gd:218` + new test sub-case.

**Tech Stack:** Godot 4.6.2 / GDScript / static modules (`class_name X extends RefCounted` or `extends PopupPanel` / `extends Control`). Headless test runner at `scripts/tests/test_runner.gd`. Save schema v18 unchanged.

**Plan source:** `docs/superpowers/specs/2026-05-15-qol-cluster-b-design.md` (committed at `1c1c2f1`).

---

## File map

| File | Purpose | Change type |
|---|---|---|
| `scripts/world/items.gd` | Item type registry | Modify — add `description` field to 27 DATA entries + `description_of(t)` accessor |
| `scripts/ui/tooltip_manager.gd` | Hover-tracking + tooltip rendering | NEW |
| `scenes/tooltip_manager.tscn` | Tooltip widget (PanelContainer + 2 Labels) | NEW |
| `scripts/ui/item_picker_modal.gd` | Filter dropdown picker | NEW |
| `scenes/item_picker_modal.tscn` | Picker scene (PopupPanel + ScrollContainer + buttons) | NEW |
| `scripts/ui/inventory_grid.gd` | Player + chest grids | Modify — wire mouse-motion handler → TooltipManager |
| `scripts/ui/building_panel.gd` | Generic building panel | Modify — wire slot hover-motion → TooltipManager |
| `scripts/ui/chest_panel.gd` | Chest panel | Modify — same-type silent-merge at line 218 + slot hover-motion |
| `scripts/ui/fast_inserter_panel.gd` | Fast inserter panel | Modify — filter-slot plain-LMB → open ItemPickerModal + slot hover-motion |
| `scripts/world/inserter.gd` | Inserter info_lines | Modify — append filter-status diagnostic + `_source_has_matching_item` helper |
| `scripts/main.gd` | E-key dispatch + HUD | Modify — instantiate TooltipManager + ItemPickerModal in HUD; hover-aware `_try_interact` |
| `scripts/tests/test_tooltip_manager.gd` | Tooltip tests | NEW (~3 sub-cases) |
| `scripts/tests/test_item_picker_modal.gd` | Picker tests | NEW (~3 sub-cases) |
| `scripts/tests/test_inserter.gd` | Inserter tests | Modify — append filter-status sub-case |
| `scripts/tests/test_building_ui_2.gd` | Building UI tests | Modify — append same-type silent-merge sub-case |
| `scripts/tests/test_runner.gd` | Test runner registry | Modify — append 2 new test files to TESTS array |
| `PROJECT_LOG.md` | Session log | Modify — prepend session entry |
| `NOTES.md` | Working protocols + backlog | Modify — mark Cluster B SHIPPED, remove items 4/5/7/9 from backlog |

11 production files (2 NEW + 9 modified), 4 test files (2 NEW + 2 modified), 2 housekeeping files.

---

## Task overview

| # | Task | TDD red | TDD green | Manual gate |
|---|---|---|---|---|
| 1 | Threshold audit (35/35 baseline) | — | run tests | — |
| 2 | Items.gd description field + accessor (empty strings) | accessor returns "" by default — test added | field + accessor + 27 empty entries | — |
| 3 | **Draft 27 descriptions (code-citation grounded)** | — | implementer reads Recipes/Burner/etc., drafts → batch user review | **user review gate** |
| 4 | TooltipManager module + scene | (visual; no tests) | class + scene + hover-timing logic | — |
| 5 | Wire TooltipManager into 4 slot-owning Controls | (visual) | mouse-motion handlers in inventory_grid + 3 panels | — |
| 6 | ItemPickerModal class + scene (mirrors QuantityPickerModal) | (visual + test sub-cases) | class + scene + confirm-callback API | — |
| 7 | Wire ItemPickerModal into FastInserterPanel filter slot | (manual visual + sub-case) | plain-LMB handler when cursor empty → open picker | — |
| 8 | Filter status diagnostic line in Inserter.info_lines | sub-case fails | append line + `_source_has_matching_item` helper | — |
| 9 | E-key hover-aware dispatch in main.gd | sub-case fails | `_try_interact` mouse-tile-first lookup with fallback | — |
| 10 | Chest silent-merge at chest_panel.gd:218 + NEW test sub-case | sub-case fails | 5-line silent-merge branch | — |
| 11 | PAUSE 1: visual smoke (hover tooltips + filter picker + E-key + chest) | — | — | user smoke |
| 12 | PAUSE 2: full gameplay (all 5 items exercised in normal play) | — | — | user smoke |
| 13 | Ship (PROJECT_LOG + NOTES + tag + push) | — | — | — |

**Subagent triad per code task** (T2 + T4-T10): implementer + spec reviewer + code quality reviewer with line-quoting. T3 is hybrid (subagent drafts → user gate). T11 + T12 are manual user gates. T13 is controller-orchestrated.

**Validated protocols apply:**
- Design Brief Verification (5+ catches across multi-session run)
- UX iteration trap (after 2 failed visual iterations, force the rule — wire rendering taught this)
- Magic-number-in-tests audit (cascade-grep before constant changes)
- Variable name pre-check before multi-edit on shared test files
- `--headless --import` parse verification for new `.gd` files with unusual base classes
- Line-quoting on reviewers (0 false positives across 17+ post-protocol reviews)

---

## Task 1: Threshold audit

**Files:** none (verification only)

**Purpose:** Confirm 35/35 PASS baseline. HEAD must be `1c1c2f1` (Cluster B spec commit).

- [ ] **Step 1: Verify HEAD + working tree**

Run:
```bash
git status
git log --oneline -1
```
Expected: working tree clean (icon.svg.import / project.godot autogen drift is OK), HEAD = `1c1c2f1` (Spec: QoL Cluster B).

- [ ] **Step 2: Run full test suite**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `35 passed, 0 failed`. Three intentional stderr noises (save-migration negative paths, slot-handler headless popup-parent reuse). None are failures.

- [ ] **Step 3: No commit (verification only)**

Proceed to Task 2.

---

## Task 2: Items.gd description field + accessor

**Files:**
- Modify: `scripts/world/items.gd` (add `description` field to all 27 DATA entries with empty string defaults + `description_of(t)` accessor)
- Create: `scripts/tests/test_tooltip_manager.gd` (sub-case 1 only — accessor sanity)
- Modify: `scripts/tests/test_runner.gd` (append new test file)

**Purpose:** Land the field shape with empty strings (real text comes in Task 3 after user reviews drafts). Decouples mechanical "field exists" from content authoring.

- [ ] **Step 1: Write the failing test (sub-case 1 — accessor sanity)**

Create `scripts/tests/test_tooltip_manager.gd`:

```gdscript
extends RefCounted

## QoL Cluster B Item 1 tests — tooltip + Items.gd description field.
##
## Sub-cases:
##   1. Items.description_of(WHEAT) returns a string (empty or real).
##   2. Items.description_of(-1) returns "" (safe fallback for unknown).
##   3. TooltipManager hover-start sets pending target; end_hover clears.

static func test_name() -> String:
	return "tooltip manager (accessor + hover lifecycle)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ===========================================================================
	# (1) Items.description_of(WHEAT) returns a string (may be empty in Task 2,
	# real content in Task 3). Defensive: just confirm String return type.
	# ===========================================================================
	var d_wheat = Items.description_of(Items.Type.WHEAT)
	_check(failures, typeof(d_wheat) == TYPE_STRING,
		"(1) description_of(WHEAT) should return String, got type %d" % typeof(d_wheat))

	# ===========================================================================
	# (2) Items.description_of(-1) returns "" — unknown type fallback.
	# ===========================================================================
	var d_unknown = Items.description_of(-1)
	_check(failures, typeof(d_unknown) == TYPE_STRING and d_unknown == "",
		"(2) description_of(-1) should return empty String, got %s" % str(d_unknown))

	if failures.is_empty():
		return { "ok": true, "message": "2 sub-cases pass: description_of accessor + unknown-type fallback" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _check(failures: Array, condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
```

Sub-case 3 (hover lifecycle) lands in Task 4 when TooltipManager exists. Test file ships with sub-cases 1-2 only in this task.

Append `test_tooltip_manager.gd` to TESTS array in `scripts/tests/test_runner.gd`. Find the existing TESTS array end (last preload line + closing `]`) and add:
```gdscript
	preload("res://scripts/tests/test_tooltip_manager.gd"),
]
```

- [ ] **Step 2: Run tests to verify (1) and (2) fail (Items.description_of doesn't exist yet)**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: parse error or runtime error on `Items.description_of(...)` (function doesn't exist). Test suite reports failure on `test_tooltip_manager.gd`.

- [ ] **Step 3: Add description field to all 27 Items.DATA entries**

In `scripts/world/items.gd`, locate the DATA dictionary. For EACH of the 27 entries, append `"description": ""` to the inline dict. Example transformation:

Before:
```gdscript
Type.WHEAT: { "name": "Wheat", "color": Color(0.95, 0.80, 0.25), "max_stack": 100 },
```

After:
```gdscript
Type.WHEAT: { "name": "Wheat", "color": Color(0.95, 0.80, 0.25), "max_stack": 100, "description": "" },
```

Apply to all 27 entries. Empty string is intentional — real content authored in Task 3.

- [ ] **Step 4: Add description_of accessor**

In `scripts/world/items.gd`, locate the existing `name_of` function (search for `static func name_of`). Append immediately after `name_of`:

```gdscript

## Description text for tooltips. Returns empty string for unknown types
## (safe fallback so callers don't need to null-check).
##
## Authored at QoL Cluster B Item 1: text in Items.DATA "description" field
## is reviewed by user before tooltip widget integration (Task 3 gate).
static func description_of(t: int) -> String:
	if not DATA.has(t):
		return ""
	return str(DATA[t].get("description", ""))
```

- [ ] **Step 5: Run tests — expect 36/36 PASS**

Run the test command. Expected: `36 passed, 0 failed`. New PASS line: `tooltip manager (accessor + hover lifecycle)`.

- [ ] **Step 6: Commit**

```bash
git add scripts/world/items.gd scripts/tests/test_tooltip_manager.gd scripts/tests/test_runner.gd
git commit -m "$(cat <<'EOF'
Task 2: Items.gd description field + accessor (empty defaults)

Adds "description" field to all 27 Items.DATA entries (empty string
defaults) and static Items.description_of(t) accessor with safe ""
fallback for unknown types.

Field shape only — real text content authored in Task 3 (subagent
drafts with code-citation grounding, user reviews before tooltip
widget integration).

NEW test file test_tooltip_manager.gd with 2 sub-cases (accessor
returns String for known type, returns "" for unknown). Runner count
35 -> 36. Hover-lifecycle sub-case lands in Task 4.
EOF
)"
```

---

## Task 3: Draft 27 item descriptions (code-citation grounded)

**Files:** `scripts/world/items.gd` (replace empty strings with real text in 27 entries)

**Purpose:** Author description text by reading actual game mechanics from `Recipes.gd`, `Burner.gd`, processor modules. NOT generic filler — each description references the real recipe chain / fuel value / processing building.

**This task has a USER REVIEW GATE.** Subagent drafts all 27, presents as a batch, user reviews/tweaks, then implementer commits the final text.

### Pre-flight grounding (subagent reads these for content)

Before drafting any description, the subagent MUST read:

- `scripts/world/recipes.gd` — every Items.Type appears in inputs/outputs of some recipe (or is unused — flag those)
- `scripts/world/burner.gd` — `FUEL_VALUES` dict gives fuel energy per item (WOOD/COAL/FUEL_BRIQUETTE)
- `scripts/world/items.gd:54-58` — comment block explaining COMPOST_HIGH theme (wasteland recovery)
- `scripts/world/processor.gd` and the per-processor modules (mill.gd, mixer.gd, etc.) — to confirm building names

### Drafting protocol

For each of the 27 items, write a single-line description (~50-80 chars, no line breaks) following this template:

> [Origin/source phrase]. [Use case / next chain step / building name].

Tone calibration (matches spec §4 examples):

| Item | Draft (anchor for tone) |
|---|---|
| WHEAT | Raw grain. Mill into Flour for the bread chain. |
| FLOUR | Milled wheat. Mix with Water + Yeast in a Mixer to make Dough. |
| YEAST | Live culture. Grown in Yeast Culture from Sugar + Water. |
| DOUGH | Unleavened mix. Proof in a Proofer to make Risen Dough. |
| FUEL_BRIQUETTE | Densest fuel (8 energy units). Crafted in a Briquetter. |
| WOOD | Tree-felling product. Basic fuel (1 energy unit). |
| COAL | Mined fuel. 4 energy units. |

The spec §4 has all 27 drafts as anchors — implementer may refine them or write fresh, but MUST cite code source for fuel values, recipe inputs, building names.

### Implementer task

- [ ] **Step 1: Read the grounding files**

```bash
grep -n "FUEL_VALUES" scripts/world/burner.gd
grep -n "Items.Type\." scripts/world/recipes.gd | head -40
```

Inspect outputs. Note any items that DON'T appear in any recipe (e.g., RAW_STONE / COMPOST_HIGH may be unused or theme-only).

- [ ] **Step 2: Draft all 27 descriptions**

Update `scripts/world/items.gd` — replace the empty `"description": ""` strings with real text for all 27 entries. Use spec §4 drafts as anchor; refine per code-grounded findings.

- [ ] **Step 3: Run tests — descriptions are still just strings, no behavior change**

Expected: `36 passed, 0 failed`. test_tooltip_manager.gd sub-case (1) still passes (String return type unchanged).

- [ ] **Step 4: USER REVIEW GATE — present descriptions for review**

Report to controller:
- All 27 descriptions in a single markdown table (item name | description)
- Any items found unused in recipes (flagged for user decision)
- Any descriptions that referenced future-session mechanics (Sessions 5+) — confirm intent

Controller relays to user. **DO NOT COMMIT** until user approves the batch.

- [ ] **Step 5: Apply user tweaks (if any)**

If user requests changes, apply them. Re-run tests.

- [ ] **Step 6: Commit (after user approval)**

```bash
git add scripts/world/items.gd
git commit -m "$(cat <<'EOF'
Task 3: Draft 27 item descriptions (code-citation grounded)

Authored description text for all 27 Items.DATA entries. Drafted by
implementer with grounding from Recipes.gd / Burner.FUEL_VALUES /
processor module names; user-reviewed before commit per Cluster B
spec gate.

Tone: factual, mechanically informative, mentions recipe chain or
building name. ~50-80 chars each.

No tests change (descriptions are still strings; behavior identical
to Task 2). Runner count stays 36.
EOF
)"
```

---

## Task 4: TooltipManager module + scene

**Files:**
- Create: `scripts/ui/tooltip_manager.gd` (Control with hover-tracking + show/hide logic)
- Create: `scenes/tooltip_manager.tscn` (PanelContainer + VBox + 2 Labels)
- Modify: `scripts/tests/test_tooltip_manager.gd` (append sub-case 3 — hover lifecycle)

**Purpose:** Single shared tooltip widget. Owned by main HUD; called from any slot-owning Control via `start_hover(item_type, mouse_pos)` / `end_hover()`. Internal 500ms delay timer.

- [ ] **Step 1: Write the failing test (sub-case 3 — hover lifecycle)**

Append to `scripts/tests/test_tooltip_manager.gd` BEFORE the final `if failures.is_empty()` return:

```gdscript

	# ===========================================================================
	# (3) TooltipManager hover lifecycle — start_hover sets pending target;
	# end_hover clears it. Internal timer not exercised (no _process loop in
	# headless tests); just verify the state-tracking API.
	# ===========================================================================
	var TooltipManagerScript = preload("res://scripts/ui/tooltip_manager.gd")
	var tip: Node = TooltipManagerScript.new()
	parent.add_child(tip)
	tip.start_hover(Items.Type.WHEAT, Vector2(100, 100))
	_check(failures, tip._hover_target == Items.Type.WHEAT,
		"(3) start_hover should set _hover_target to WHEAT, got %d" % tip._hover_target)
	tip.end_hover()
	_check(failures, tip._hover_target == -1,
		"(3) end_hover should reset _hover_target to -1, got %d" % tip._hover_target)
	tip.queue_free()
```

Update success message at end of `run()`:
```gdscript
		return { "ok": true, "message": "3 sub-cases pass: description_of accessor + unknown fallback + hover lifecycle" }
```

- [ ] **Step 2: Run tests — expect parse error on TooltipManagerScript.new()**

Run the test command. Expected: parse error on `preload("res://scripts/ui/tooltip_manager.gd")` since file doesn't exist yet.

- [ ] **Step 3: Create `scripts/ui/tooltip_manager.gd`**

```gdscript
class_name TooltipManager
extends Control

## Hover-tracking + tooltip rendering. Single shared widget; lives in main
## HUD ($HUD/TooltipManager). Slot-owning Controls (inventory_grid,
## chest_panel, building_panel subclasses) call start_hover(item_type,
## mouse_pos) when mouse enters a slot rect, end_hover() when mouse
## leaves. After HOVER_DELAY_MS ms of stable hover, the tooltip widget
## appears at mouse_pos + offset.
##
## Empty slots and unknown item types are no-ops (no tooltip shown).
##
## Tooltip content: item name (bold) + description (wrap-text body).
## Layout: PanelContainer > VBoxContainer > 2 Labels. Floats above all
## panels (z-index handled by scene tree order — TooltipManager is the
## last child of HUD).

# Tooltip appears after this many ms of stable hover.
const HOVER_DELAY_MS: int = 500

# Pixel offset from mouse cursor. Edge-flipped if would overflow viewport.
const TOOLTIP_OFFSET: Vector2 = Vector2(16, 16)

# Visual constants.
const BG_COLOR: Color = Color(0.10, 0.10, 0.15, 0.92)
const BORDER_COLOR: Color = Color(0.40, 0.40, 0.50, 1.0)
const NAME_COLOR: Color = Color(1.0, 1.0, 1.0)
const DESC_COLOR: Color = Color(0.85, 0.85, 0.85)

# Hover state.
var _hover_target: int = -1                # Items.Type or -1
var _hover_start_ms: int = 0
var _hover_pos: Vector2 = Vector2.ZERO
var _tooltip_visible: bool = false

# Scene refs — populated by _ready if the scene is loaded.
@onready var _panel: PanelContainer = $PanelContainer if has_node("PanelContainer") else null
@onready var _name_label: Label = $PanelContainer/VBox/NameLabel if has_node("PanelContainer/VBox/NameLabel") else null
@onready var _desc_label: Label = $PanelContainer/VBox/DescLabel if has_node("PanelContainer/VBox/DescLabel") else null

func _ready() -> void:
	# Tests instantiate via `TooltipManagerScript.new()` (no scene load) —
	# in that case _panel etc. are null. Guard rendering on _panel != null.
	if _panel != null:
		_panel.visible = false
	# Tooltip should not block input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Begin hovering over a slot with the given item. Call from owning
## Control's mouse-motion handler when mouse enters a slot rect with a
## known item type. Empty slots: pass -1, treated as no hover.
##
## Repeated calls with the SAME item_type are idempotent (timer not reset).
## Different item_type restarts the timer.
func start_hover(item_type: int, mouse_pos: Vector2) -> void:
	if item_type < 0:
		end_hover()
		return
	if item_type == _hover_target:
		# Same target — just update position for tooltip placement.
		_hover_pos = mouse_pos
		if _tooltip_visible and _panel != null:
			_position_tooltip()
		return
	_hover_target = item_type
	_hover_start_ms = Time.get_ticks_msec()
	_hover_pos = mouse_pos
	_hide_tooltip()

## End hover. Resets state and hides tooltip.
func end_hover() -> void:
	_hover_target = -1
	_hover_start_ms = 0
	_hide_tooltip()

func _process(_delta: float) -> void:
	if _hover_target < 0 or _tooltip_visible:
		return
	if Time.get_ticks_msec() - _hover_start_ms < HOVER_DELAY_MS:
		return
	_show_tooltip()

func _show_tooltip() -> void:
	if _panel == null or _name_label == null or _desc_label == null:
		return   # headless test path — no scene
	_name_label.text = Items.name_of(_hover_target)
	_desc_label.text = Items.description_of(_hover_target)
	_panel.visible = true
	_tooltip_visible = true
	_position_tooltip()

func _hide_tooltip() -> void:
	if _panel == null:
		return
	_panel.visible = false
	_tooltip_visible = false

func _position_tooltip() -> void:
	if _panel == null:
		return
	# Edge-flip if would overflow viewport right/bottom.
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_size: Vector2 = _panel.size
	var pos: Vector2 = _hover_pos + TOOLTIP_OFFSET
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = _hover_pos.x - panel_size.x - TOOLTIP_OFFSET.x
	if pos.y + panel_size.y > viewport_size.y:
		pos.y = _hover_pos.y - panel_size.y - TOOLTIP_OFFSET.y
	_panel.position = pos
```

- [ ] **Step 4: Create `scenes/tooltip_manager.tscn`**

Open Godot editor. Create new scene with root `Control` (script: `scripts/ui/tooltip_manager.gd`). Add child `PanelContainer` named `PanelContainer`. Inside `PanelContainer`, add `VBoxContainer` named `VBox`. Inside `VBox`, add two `Label` nodes named `NameLabel` and `DescLabel`. Set:

- `NameLabel`: theme override `font_color = Color(1.0, 1.0, 1.0)`, `font_size = 16`
- `DescLabel`: theme override `font_color = Color(0.85, 0.85, 0.85)`, `font_size = 14`, `autowrap_mode = WORD_SMART`, `custom_minimum_size.x = 240`
- `PanelContainer`: theme override `panel.bg_color = Color(0.10, 0.10, 0.15, 0.92)`, `panel.border_color = Color(0.40, 0.40, 0.50, 1.0)`, `panel.border_width = 1`

Save scene to `scenes/tooltip_manager.tscn`.

(Subagent: if you can't drive the editor, write the .tscn file directly. Use existing scene file like `scenes/quantity_picker_modal.tscn` as a structural reference.)

- [ ] **Step 5: Verify parse**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" --quit 2>&1 | tail -10
```
Expected: no parse errors. TooltipManager registers as a class.

- [ ] **Step 6: Run tests — expect 36 PASS with sub-case 3 added**

Run the test command. Expected: `36 passed, 0 failed`. PASS line: `tooltip manager (accessor + hover lifecycle)` with 3 sub-cases listed in success message.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/tooltip_manager.gd scenes/tooltip_manager.tscn scripts/tests/test_tooltip_manager.gd
git commit -m "$(cat <<'EOF'
Task 4: TooltipManager module + scene

NEW scripts/ui/tooltip_manager.gd — class_name TooltipManager extends
Control. Hover-tracking API: start_hover(item_type, mouse_pos),
end_hover(). Internal 500ms HOVER_DELAY_MS timer; tooltip appears at
mouse_pos + (16,16) with edge-flip on viewport overflow.

NEW scenes/tooltip_manager.tscn — PanelContainer with VBox containing
NameLabel (bold, 16pt) and DescLabel (wrap-text, 14pt). Dark
background, subtle border. mouse_filter=IGNORE so tooltip doesn't
block input.

test_tooltip_manager.gd sub-case (3) added: start_hover sets target,
end_hover clears. 36/36 PASS. Wiring into slot-owning Controls
follows in Task 5.
EOF
)"
```

---

## Task 5: Wire TooltipManager into slot-owning Controls

**Files:**
- Modify: `scripts/main.gd` (instantiate TooltipManager in HUD)
- Modify: `scripts/ui/inventory_grid.gd` (mouse-motion → TooltipManager calls)
- Modify: `scripts/ui/chest_panel.gd` (slot-area mouse-motion handler)
- Modify: `scripts/ui/building_panel.gd` (slot-area mouse-motion handler)
- Modify: `scripts/ui/fast_inserter_panel.gd` (filter slot also gets hover)

**Purpose:** Hook TooltipManager into every slot-rendering Control. Mouse moves over a slot rect → TooltipManager.start_hover(item_type, mouse_pos). Mouse leaves → TooltipManager.end_hover().

- [ ] **Step 1: DBV — verify exact slot-rect determination pattern in each owning Control**

Run:
```bash
grep -n "_gui_input\|_input\|slot_idx" scripts/ui/inventory_grid.gd | head -10
grep -n "_gui_input\|_handle_chest_slot_click" scripts/ui/chest_panel.gd | head -5
grep -n "_gui_input\|_handle_player_slot\|_handle_building_slot" scripts/ui/building_panel.gd | head -10
```

Each Control has its own way of mapping mouse positions to slot indexes (e.g., `inventory_grid` uses a grid layout; panels use absolute slot rects). For each Control, identify the existing function that converts `mouse_pos → slot_idx`. The hover wiring uses the same function.

If a Control has no such helper, add a small helper `_slot_at(mouse_pos: Vector2) -> int` that returns slot_idx or -1.

- [ ] **Step 2: Instantiate TooltipManager in main HUD**

In `scripts/main.gd`, locate the `@onready var` block where other HUD elements are declared (search for `@onready var inserter_panel` or similar). Add:

```gdscript
@onready var tooltip_manager: TooltipManager = $HUD/TooltipManager
```

In the main scene `scenes/main.tscn` (or whichever scene `main.gd` is attached to), add a `TooltipManager` instance as the LAST child of `$HUD`. The scene-tree last-child renders on top.

If editing the scene directly isn't possible from the subagent, write a brief `_ready` initialization that instantiates the scene:

```gdscript
# In main.gd _ready, AFTER existing HUD setup:
var tooltip_scene := preload("res://scenes/tooltip_manager.tscn")
tooltip_manager = tooltip_scene.instantiate()
$HUD.add_child(tooltip_manager)
tooltip_manager.z_index = 100
```

- [ ] **Step 3: Wire inventory_grid.gd mouse-motion**

In `scripts/ui/inventory_grid.gd`, locate the `_gui_input(event)` function. Add a `MouseMotion` branch ABOVE the click handling:

```gdscript
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_hover(event.position)
		# Don't return — let click handling continue if relevant.
	# ... existing click handling unchanged ...

func _handle_hover(local_pos: Vector2) -> void:
	if tooltip_manager == null:
		return   # may not be wired in test/headless contexts
	var slot_idx: int = _slot_at(local_pos)
	if slot_idx < 0:
		tooltip_manager.end_hover()
		return
	var item_type: int = _slot_item_type(slot_idx)   # existing helper or new
	if item_type < 0:
		tooltip_manager.end_hover()
		return
	# Convert local_pos to global for tooltip positioning.
	var global_pos: Vector2 = get_global_mouse_position()
	tooltip_manager.start_hover(item_type, global_pos)
```

`tooltip_manager` reference: pass it in via the parent (main.gd) or use a project-level singleton/autoload. Cleanest: add a `var tooltip_manager: TooltipManager = null` and set it from main.gd after instantiation.

`_slot_at(local_pos)` and `_slot_item_type(slot_idx)`: if these helpers don't exist, add them based on the existing slot-rendering logic in inventory_grid.

- [ ] **Step 4: Wire chest_panel.gd mouse-motion**

Same pattern as inventory_grid — find `_gui_input`, add MouseMotion handler at top, dispatch to `_handle_hover_chest_slot(local_pos)`. Add `_slot_at_chest(local_pos)` helper if missing. Item type from `bag` views.

- [ ] **Step 5: Wire building_panel.gd mouse-motion**

Same pattern. Building panel slot rects vary by `slot_layout`; reuse the existing slot-rect computation that the click handler uses.

- [ ] **Step 6: Wire fast_inserter_panel.gd mouse-motion**

Same pattern. Filter slot is a single-item-type slot — hover over filter slot shows the filter item's tooltip (or no tooltip if filter unset).

- [ ] **Step 7: Run tests — expect 36 PASS (mouse-motion not exercised in headless)**

Expected: `36 passed, 0 failed`. Visual verification deferred to PAUSE 1.

- [ ] **Step 8: Commit**

```bash
git add scripts/main.gd scripts/ui/inventory_grid.gd scripts/ui/chest_panel.gd scripts/ui/building_panel.gd scripts/ui/fast_inserter_panel.gd
git commit -m "$(cat <<'EOF'
Task 5: Wire TooltipManager into 4 slot-owning Controls

main.gd: TooltipManager instantiated as last child of $HUD (renders on
top, z_index=100). Passed by reference into the 4 slot-owning Controls
during their setup.

inventory_grid.gd / chest_panel.gd / building_panel.gd /
fast_inserter_panel.gd: mouse-motion handler in _gui_input maps
local_pos to slot_idx (existing or new _slot_at helper), reads
item_type from the slot, calls tooltip_manager.start_hover(...) or
end_hover() accordingly.

mouse_filter on TooltipManager set to IGNORE so tooltip doesn't block
input. Visual verification deferred to PAUSE 1.

36/36 PASS — mouse-motion not exercised in headless tests.
EOF
)"
```

---

## Task 6: ItemPickerModal class + scene

**Files:**
- Create: `scripts/ui/item_picker_modal.gd` (PopupPanel, mirrors QuantityPickerModal)
- Create: `scenes/item_picker_modal.tscn` (PopupPanel + ScrollContainer + item button list)
- Create: `scripts/tests/test_item_picker_modal.gd` (3 sub-cases — open returns chosen item, callback API, current_filter highlighting state)
- Modify: `scripts/tests/test_runner.gd` (append new test file)

**Purpose:** Reusable item picker modal for the filter dropdown (Task 7) and any future picker needs. Clone of QuantityPickerModal pattern with list-based UI.

- [ ] **Step 1: Write the failing tests (3 sub-cases)**

Create `scripts/tests/test_item_picker_modal.gd`:

```gdscript
extends RefCounted

## QoL Cluster B Item 2 tests — ItemPickerModal.
##
## Sub-cases:
##   1. open() with current_filter=-1 sets internal state, callback unset.
##   2. _on_item_selected(WHEAT) invokes callback with WHEAT, hides modal.
##   3. open() with current_filter=COAL exposes COAL as the highlighted item.

const ItemPickerModalScript = preload("res://scripts/ui/item_picker_modal.gd")

static func test_name() -> String:
	return "item picker modal (open + callback + current-highlight)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ===========================================================================
	# (1) open() sets internal state, no callback fires yet.
	# ===========================================================================
	var picker = ItemPickerModalScript.new()
	parent.add_child(picker)
	var captured_item: Array = [-1]
	picker.open(Vector2(100, 100), -1, func(item_type): captured_item[0] = item_type)
	_check(failures, picker._current_filter == -1,
		"(1) open with current_filter=-1 should set _current_filter to -1, got %d" % picker._current_filter)
	_check(failures, captured_item[0] == -1,
		"(1) callback should NOT have fired yet (no item selected), captured: %d" % captured_item[0])

	# ===========================================================================
	# (2) _on_item_selected invokes callback, hides modal.
	# ===========================================================================
	picker._on_item_selected(Items.Type.WHEAT)
	_check(failures, captured_item[0] == Items.Type.WHEAT,
		"(2) _on_item_selected(WHEAT) should fire callback with WHEAT, got %d" % captured_item[0])

	# ===========================================================================
	# (3) open() with current_filter=COAL — state exposed for highlighting.
	# ===========================================================================
	var picker2 = ItemPickerModalScript.new()
	parent.add_child(picker2)
	picker2.open(Vector2(100, 100), Items.Type.COAL, func(_t): pass)
	_check(failures, picker2._current_filter == Items.Type.COAL,
		"(3) open with current_filter=COAL should set _current_filter to COAL, got %d" % picker2._current_filter)

	picker.queue_free()
	picker2.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "3 sub-cases pass: open state + callback fires + current-highlight" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _check(failures: Array, condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
```

Append `test_item_picker_modal.gd` to TESTS array in `scripts/tests/test_runner.gd`.

- [ ] **Step 2: Run tests — expect parse error (file doesn't exist)**

Expected: parse error on `ItemPickerModalScript = preload(...)`.

- [ ] **Step 3: Create `scripts/ui/item_picker_modal.gd`**

```gdscript
class_name ItemPickerModal
extends PopupPanel

## Filter dropdown picker. Opens at anchor (e.g., filter slot's screen
## position + offset); shows a scrollable list of all Items.Type entries
## as clickable buttons. Click an item → fires confirm_cb with the chosen
## Items.Type; modal closes. Esc / click-outside cancels (callback not
## invoked).
##
## Mirrors QuantityPickerModal pattern (hard-modal via
## popup_exclusive_on_parent, callback-based result). Cloned not shared
## because UI shape diverges (list vs spinbox).
##
## Used by FastInserterPanel filter slot (and future filter-capable
## inserter tiers). Complements drop-to-set (both paths set filter).

@onready var _list_container: VBoxContainer = $ScrollContainer/VBox if has_node("ScrollContainer/VBox") else null

var _confirm_cb: Callable = Callable()
var _current_filter: int = -1

func _ready() -> void:
	close_requested.connect(hide)

## Open the picker at anchor with current_filter (highlighted item).
## Pass -1 for current_filter if no filter currently set.
##
## On item selection → confirm_cb.call(item_type), then hides.
## On Esc / click-outside → hides; callback NOT invoked.
func open(anchor: Vector2, current_filter: int, confirm_cb: Callable) -> void:
	_confirm_cb = confirm_cb
	_current_filter = current_filter
	_populate_list()
	# Hard modal — Esc + click-outside cancel handled by PopupPanel.
	position = Vector2i(anchor)
	size = Vector2i(280, 320)
	popup_exclusive_on_parent(get_parent(), Rect2i(Vector2i(anchor), Vector2i(280, 320)))
	visible = true

func _populate_list() -> void:
	if _list_container == null:
		return   # headless test path — no scene
	# Clear existing children.
	for child in _list_container.get_children():
		child.queue_free()
	# Add a row per Items.Type.
	for type_value in Items.Type.values():
		var btn := Button.new()
		var name_text: String = Items.name_of(type_value)
		var desc_text: String = Items.description_of(type_value)
		btn.text = "%s — %s" % [name_text, desc_text] if desc_text != "" else name_text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 28)
		if type_value == _current_filter:
			# Highlight current selection via modulate (cheap, no theme override).
			btn.modulate = Color(1.0, 1.0, 0.4)   # warm yellow
		btn.pressed.connect(func(): _on_item_selected(type_value))
		_list_container.add_child(btn)

func _on_item_selected(item_type: int) -> void:
	if _confirm_cb.is_valid():
		_confirm_cb.call(item_type)
	hide()
```

- [ ] **Step 4: Create `scenes/item_picker_modal.tscn`**

PopupPanel root (script: `scripts/ui/item_picker_modal.gd`) → ScrollContainer named `ScrollContainer` → VBoxContainer named `VBox`. Set ScrollContainer.size_flags_horizontal = FILL, ScrollContainer.size_flags_vertical = FILL. PopupPanel min_size = Vector2(280, 320).

(Subagent: write .tscn file directly if needed, using `scenes/quantity_picker_modal.tscn` as structural reference.)

- [ ] **Step 5: Verify parse**

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" --quit 2>&1 | tail -10
```
Expected: no parse errors. ItemPickerModal registers as a class.

- [ ] **Step 6: Run tests — expect 37 PASS (new test file added)**

Expected: `37 passed, 0 failed`. New PASS line: `item picker modal (open + callback + current-highlight)`.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/item_picker_modal.gd scenes/item_picker_modal.tscn scripts/tests/test_item_picker_modal.gd scripts/tests/test_runner.gd
git commit -m "$(cat <<'EOF'
Task 6: ItemPickerModal class + scene + 3 test sub-cases

NEW scripts/ui/item_picker_modal.gd — class_name ItemPickerModal
extends PopupPanel. open(anchor, current_filter, confirm_cb) populates
a scrollable button list (one per Items.Type), highlights current
filter via warm-yellow modulate, fires callback on click with chosen
Items.Type, closes. Esc/click-outside cancels.

Mirrors QuantityPickerModal pattern (popup_exclusive_on_parent for
hard modal, Callable-based result). Cloned not shared due to UI shape
divergence (list vs spinbox).

NEW scenes/item_picker_modal.tscn — PopupPanel > ScrollContainer >
VBoxContainer. 280x320 min size. Buttons populated dynamically.

NEW test_item_picker_modal.gd with 3 sub-cases: open state, callback
fires, current_filter highlighting. Runner count 36 -> 37.

Wiring into FastInserterPanel filter slot follows in Task 7.
EOF
)"
```

---

## Task 7: Wire ItemPickerModal into FastInserterPanel

**Files:**
- Modify: `scripts/ui/fast_inserter_panel.gd` (filter slot plain-LMB → open picker)
- Modify: `scripts/main.gd` (instantiate ItemPickerModal in HUD; pass reference)

**Purpose:** Plain-LMB click on filter slot when cursor is empty → opens ItemPickerModal. Drop-to-set (existing path) preserved as complement.

- [ ] **Step 1: DBV — locate FastInserterPanel filter slot click handling**

Run:
```bash
grep -n "filter\|_handle.*filter\|drop_to_set" scripts/ui/fast_inserter_panel.gd | head -10
```

Identify the existing function that handles filter slot clicks (drop-to-set and RMB-clear). Add the plain-LMB-with-empty-cursor branch there.

- [ ] **Step 2: Instantiate ItemPickerModal in main HUD**

Same pattern as TooltipManager (Task 5). In `main.gd`, add:

```gdscript
@onready var item_picker_modal: ItemPickerModal = $HUD/ItemPickerModal
```

Add ItemPickerModal as a child of `$HUD` (or `_ready` instantiation if scene editing unavailable). Pass reference to FastInserterPanel via existing initialization wiring.

- [ ] **Step 3: Wire plain-LMB-with-empty-cursor on filter slot**

In `scripts/ui/fast_inserter_panel.gd`, find the filter slot click handler. Add a branch at the top:

```gdscript
# Plain LMB on filter slot when cursor is empty → open ItemPickerModal.
# (Drop-to-set and RMB-clear paths unchanged, follow this branch.)
if mods == SlotClickHandler.MOD_NONE and not cursor.has_item():
	if item_picker_modal != null:
		var current_filter: int = int(building.state.get("filter_item_type", -1))
		var slot_global_pos: Vector2 = _filter_slot_global_position()   # use existing rect helper
		item_picker_modal.open(
			slot_global_pos + Vector2(0, 48),   # drop below slot
			current_filter,
			func(item_type): _apply_filter_from_picker(item_type)
		)
	return

# ... existing drop-to-set and RMB-clear logic unchanged ...

func _apply_filter_from_picker(item_type: int) -> void:
	building.state["filter_item_type"] = item_type
	queue_redraw()
```

- [ ] **Step 4: Run tests — expect 37 PASS**

Expected: `37 passed, 0 failed`. Visual verification (picker actually opens) deferred to PAUSE 1.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/fast_inserter_panel.gd scripts/main.gd
git commit -m "$(cat <<'EOF'
Task 7: Wire ItemPickerModal into FastInserterPanel filter slot

main.gd: ItemPickerModal instantiated as child of $HUD. Reference
passed to FastInserterPanel during initialization.

fast_inserter_panel.gd: plain-LMB on filter slot when cursor is empty
opens ItemPickerModal at filter_slot_global_pos + (0, 48) (drops
down). Callback sets state.filter_item_type and triggers redraw.

Drop-to-set and RMB-clear paths (Cluster A behavior) unchanged. Both
paths produce the same filter set — picker complements drop-to-set
per Cluster B spec.

37/37 PASS. Visual verification deferred to PAUSE 1.
EOF
)"
```

---

## Task 8: Filter status diagnostic line in Inserter.info_lines

**Files:**
- Modify: `scripts/world/inserter.gd` (append filter-status line + `_source_has_matching_item` helper)
- Modify: `scripts/tests/test_inserter.gd` (append sub-case for filter-status line presence/absence)

**Purpose:** Add `Status: IDLE (no items match filter)` line to inserter info_lines when filter set AND no matching items in source.

- [ ] **Step 1: Variable name pre-check for new test sub-case**

Run:
```bash
grep -n "^\s*var \(filter_status_b\|comp_filter\)\b" scripts/tests/test_inserter.gd
```
No collisions expected. Sub-case will use locals like `panel_b`, `info`, `has_status_line` — verify no collisions with prior sub-cases.

- [ ] **Step 2: Append failing sub-case to `test_inserter.gd`**

Append a new sub-case at the end of `test_inserter.gd run()` (before final disconnect/return). Use the variable-name pre-check protocol.

```gdscript

	# ===========================================================================
	# (NEW) FILTER STATUS DIAGNOSTIC LINE — when fast inserter has filter set
	# but no matching items in source, info_lines includes "Status: IDLE (no
	# items match filter)". When filter unset OR source has matching items,
	# line is absent.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(10, 5), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(9, 5), Belt.DIR_E)
	var fast_b_fs: Building = world.building_at(Vector2i(10, 5))
	var src_chest_fs: Building = world.building_at(Vector2i(9, 5))
	# Scenario A: filter set to WHEAT, source has FLAX → status line present.
	fast_b_fs.state["filter_item_type"] = Items.Type.WHEAT
	src_chest_fs.state["bag"] = [[Items.Type.FLAX, 5]]
	var info_a: Array = Inserter.info_lines(fast_b_fs, world)
	var has_status_a: bool = false
	for line in info_a:
		if str(line).find("no items match filter") >= 0:
			has_status_a = true
			break
	_check(failures, has_status_a, "filter status: source has only FLAX while filter=WHEAT, should show 'no items match filter' line")
	# Scenario B: filter set to WHEAT, source has WHEAT → status line absent.
	src_chest_fs.state["bag"] = [[Items.Type.WHEAT, 5]]
	var info_b: Array = Inserter.info_lines(fast_b_fs, world)
	var has_status_b: bool = false
	for line in info_b:
		if str(line).find("no items match filter") >= 0:
			has_status_b = true
			break
	_check(failures, not has_status_b, "filter status: source has matching WHEAT, status line should be ABSENT")
	# Scenario C: filter UNSET, source has any items → status line absent.
	fast_b_fs.state["filter_item_type"] = -1
	src_chest_fs.state["bag"] = [[Items.Type.FLAX, 5]]
	var info_c: Array = Inserter.info_lines(fast_b_fs, world)
	var has_status_c: bool = false
	for line in info_c:
		if str(line).find("no items match filter") >= 0:
			has_status_c = true
			break
	_check(failures, not has_status_c, "filter status: filter unset, status line should be ABSENT regardless of source")
```

- [ ] **Step 3: Run tests — expect this sub-case to FAIL**

Expected: `1 failure` in test_inserter.gd — "filter status: source has only FLAX..." (line not found because the helper hasn't been added yet).

- [ ] **Step 4: Add filter-status line + helper in `scripts/world/inserter.gd`**

In `scripts/world/inserter.gd`, locate the filter line block (search for `Filter:` — should be around line 475-479). Inside the `if filter >= 0:` branch (where the current Filter line is appended), add the status check AFTER the existing Filter append:

```gdscript
# Filter (fast/electric tier only — basic doesn't surface this line).
if b.type == Buildings.Type.FAST_INSERTER:
	var filter: int = int(b.state.get("filter_item_type", -1))
	if filter >= 0:
		lines.append("Filter: %s" % Items.name_of(filter))
		# NEW (QoL Cluster B Item 3): if filter set AND source has no
		# matching items, surface that as a status line. Helps players
		# debug "why is my inserter idle?".
		if world != null and not _source_has_matching_item(world, source_tile(b), filter):
			lines.append("Status: IDLE (no items match filter)")
	else:
		lines.append("Filter: (none — picks any item)")
```

Then add the helper function near the other private helpers (e.g., after `_tile_summary`):

```gdscript

## Read-only mirror of _try_pickup's source-scanning logic, but filtered
## to a SPECIFIC item type. Returns true if any cell of the source tile's
## building contains at least one item of `item_type`. Used by
## info_lines to surface "no items match filter" diagnostic.
##
## Source types covered: BELT, CHEST, recipe-driven Processor (out_buffer).
## Same dispatch as _try_pickup; if source is not a recognized type,
## returns false (so the filter status line shows IDLE).
static func _source_has_matching_item(world, src_pos: Vector2i, item_type: int) -> bool:
	if not world.has_building_at(src_pos):
		return false
	var src_b: Building = world.building_at(src_pos)
	if src_b == null:
		return false
	# Belt: read slot facing the inserter.
	if src_b.type == Buildings.Type.BELT:
		var slots: Array = src_b.state.get("slots", [])
		for s in slots:
			if int(s) == item_type:
				return true
		return false
	# Chest: scan bag.
	if src_b.type == Buildings.Type.CHEST:
		var bag: Array = src_b.state.get("bag", [])
		for entry in bag:
			if int(entry[0]) == item_type and int(entry[1]) > 0:
				return true
		return false
	# Recipe-driven Processor: scan out_buffer.
	if _is_processor_with_output(src_b):
		var out_buf: Array = src_b.state.get("out_buffer", [])
		for entry in out_buf:
			if int(entry[0]) == item_type and int(entry[1]) > 0:
				return true
		return false
	return false
```

- [ ] **Step 5: Run tests — expect all 3 scenarios PASS**

Expected: `37 passed, 0 failed`. test_inserter.gd's PASS message reflects the new sub-case (its internal sub-case count grew).

- [ ] **Step 6: Commit**

```bash
git add scripts/world/inserter.gd scripts/tests/test_inserter.gd
git commit -m "$(cat <<'EOF'
Task 8: Filter status diagnostic line in Inserter.info_lines

Adds 'Status: IDLE (no items match filter)' line to fast inserter's
info_lines when filter is set AND source has no matching items. Helps
players debug 'why is my inserter idle?' instead of just seeing 'IDLE'.

Implementation: append the line inside the existing 'if filter >= 0:'
branch after the 'Filter:' line, gated by a new static helper
_source_has_matching_item(world, src_pos, item_type) that mirrors
_try_pickup's source-scanning logic (BELT/CHEST/Processor) read-only.

Only fires for FAST_INSERTER (the tier with filter capability). Future
electric/multi-filter inserters add their type to the gate.

test_inserter.gd: NEW sub-case covers all 3 scenarios:
- filter=WHEAT, source=FLAX → line present
- filter=WHEAT, source=WHEAT → line absent
- filter=-1, source=anything → line absent

37/37 PASS.
EOF
)"
```

---

## Task 9: E-key hover-aware dispatch in main.gd

**Files:**
- Modify: `scripts/main.gd` (`_try_interact` checks mouse tile first; fallback to existing scan)
- Modify: `scripts/tests/test_building_ui_2.gd` (append 2 sub-cases for hover dispatch)

**Purpose:** Mouse hovering over an adjacent interactable building → press E → open THAT one. Mouse not over an adjacent building → existing scan (E→W→S→N) wins.

- [ ] **Step 1: DBV — read current _try_interact and confirm mouse-tile helper**

Run:
```bash
grep -n "_try_interact\|_find_adjacent_interactable\|world_to_tile" scripts/main.gd | head -20
```

Confirm:
- `_try_interact(player_tile: Vector2i)` exists at line 998 (verified at re-orientation)
- `_find_adjacent_interactable(player_tile)` exists at line 1023
- `world_to_tile(world_pos: Vector2)` exists on grid_world at line 230

- [ ] **Step 2: Variable name pre-check for new sub-cases**

Run:
```bash
grep -n "^\s*var \(player_a\|inserter_a\|chest_a\|interact_target\)\b" scripts/tests/test_building_ui_2.gd
```
If collisions, suffix with `_ek` (E-key).

- [ ] **Step 3: Append failing sub-cases to `test_building_ui_2.gd`**

Append BEFORE the final `if failures.is_empty()` return:

```gdscript

	# ===========================================================================
	# (NEW) E-KEY HOVER-AWARE DISPATCH — mouse over an adjacent interactable
	# building wins over the default scan order.
	#
	# Headless caveat: we can't drive Input.mouse_position from a test
	# directly. Test the underlying helper `_find_interactable_for_e_key`
	# which takes player_tile + explicit mouse_tile (extracted from
	# _try_interact's existing logic).
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	for x in range(0, 15):
		for y in range(0, 15):
			world.set_overlay(Vector2i(x, y), Terrain.Overlay.STONE)
	# Layout: player at (10, 10). Inserter east at (11, 10). Chest south at
	# (10, 11). Default scan order is player → E → W → S → N, so E (inserter)
	# wins by default.
	world.place_building(Buildings.Type.INSERTER, Vector2i(11, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(10, 11), Belt.DIR_E)
	# Scenario A: mouse over chest tile (10, 11) → chest wins.
	var b_hover_chest: Building = parent.find_interactable_for_e_key_test(Vector2i(10, 10), Vector2i(10, 11), world)
	_check(failures, b_hover_chest != null and b_hover_chest.type == Buildings.Type.CHEST,
		"E-key hover: mouse over chest → chest opens (not inserter), got %s" % (Buildings.name_of(b_hover_chest.type) if b_hover_chest else "null"))
	# Scenario B: mouse over a non-adjacent tile (e.g., (5, 5)) → fallback scan, inserter wins.
	var b_no_hover: Building = parent.find_interactable_for_e_key_test(Vector2i(10, 10), Vector2i(5, 5), world)
	_check(failures, b_no_hover != null and b_no_hover.type == Buildings.Type.INSERTER,
		"E-key fallback: mouse far from player → scan returns inserter, got %s" % (Buildings.name_of(b_no_hover.type) if b_no_hover else "null"))
```

This test relies on a test-only helper on `parent` (the test_runner Node). Cleanest: have main.gd expose a static `_find_interactable_for_e_key(player_tile, mouse_tile, world)` function (or method on main itself) and have the test invoke it via the parent if parent is the main scene's test fixture, OR factor the logic out into a static helper.

For test isolation, factor the hover-dispatch logic into a STATIC function in main.gd (or a new helper module):

```gdscript
# In main.gd:
static func find_interactable_for_e_key(player_tile: Vector2i, mouse_tile: Vector2i, world) -> Building:
	# Hover-priority check: if mouse_tile is one of the player's 5 adjacent
	# cells (player + cardinal neighbors) AND has an interactable building,
	# return that building (mouse intent wins).
	var dx: int = abs(mouse_tile.x - player_tile.x)
	var dy: int = abs(mouse_tile.y - player_tile.y)
	if (dx + dy) <= 1:   # Manhattan dist ≤ 1 = on player or cardinal neighbor
		if world.has_building_at(mouse_tile):
			var b: Building = world.building_at(mouse_tile)
			if b != null and Buildings.has_interaction_ui(b.type):
				return b
	# Fallback: existing scan order (player → E → W → S → N).
	return _find_adjacent_interactable_static(player_tile, world)

static func _find_adjacent_interactable_static(player_tile: Vector2i, world) -> Building:
	var scan: Array = [
		player_tile,
		player_tile + Vector2i(1, 0),
		player_tile + Vector2i(-1, 0),
		player_tile + Vector2i(0, 1),
		player_tile + Vector2i(0, -1),
	]
	for cell in scan:
		if world.has_building_at(cell):
			var b: Building = world.building_at(cell)
			if b != null and Buildings.has_interaction_ui(b.type):
				return b
	return null
```

Then the test calls `Main.find_interactable_for_e_key(...)` directly (no `parent.find_interactable_for_e_key_test` helper needed). Update test code accordingly:

Replace the test's `parent.find_interactable_for_e_key_test(...)` calls with:
```gdscript
var MainScript = preload("res://scripts/main.gd")
var b_hover_chest: Building = MainScript.find_interactable_for_e_key(Vector2i(10, 10), Vector2i(10, 11), world)
# ... etc.
```

- [ ] **Step 4: Run tests — expect failure (function doesn't exist yet)**

Expected: parse error on `MainScript.find_interactable_for_e_key(...)`.

- [ ] **Step 5: Add the static helpers + wire into _try_interact in `scripts/main.gd`**

Add the two static functions defined above (`find_interactable_for_e_key` + `_find_adjacent_interactable_static`).

Modify `_try_interact(player_tile)`:

```gdscript
func _try_interact(player_tile: Vector2i) -> void:
	# E-key unified dispatch (session-building-ui-2 + QoL Cluster B Item 4
	# hover-aware update):
	#   1. Mouse over an adjacent interactable building → open THAT one.
	#   2. Else: scan player_tile → E → W → S → N → first interactable.
	#   3. Else: legacy drainable harvester fallback.
	#   4. Else: silent no-op.
	var mouse_world: Vector2 = get_global_mouse_position()
	var mouse_tile: Vector2i = grid_world.world_to_tile(mouse_world)
	var b: Building = find_interactable_for_e_key(player_tile, mouse_tile, grid_world)
	if b != null:
		_try_open_building_ui(b.anchor, player_tile)
		return
	# Drainable fallback (existing behavior unchanged).
	var d: Building = grid_world.find_adjacent_drainable(player_tile)
	if d == null:
		return
	var moved: int = Buildings.drain_into_player(d, player_inventory)
	if moved > 0:
		_show_toast("Drained %s (+%d items)" % [Buildings.name_of(d.type), moved])
	else:
		_show_toast("%s is empty" % Buildings.name_of(d.type))
```

The old `_find_adjacent_interactable(player_tile)` instance method can either be removed (callers updated to use the static) OR kept as a thin wrapper that delegates to `_find_adjacent_interactable_static(player_tile, grid_world)`. Implementer's call.

- [ ] **Step 6: Run tests — expect 37 PASS with both new sub-cases**

Expected: `37 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add scripts/main.gd scripts/tests/test_building_ui_2.gd
git commit -m "$(cat <<'EOF'
Task 9: E-key hover-aware dispatch

main.gd: _try_interact now checks mouse tile FIRST. If mouse is over
one of the 5 adjacent cells (player_tile + cardinal neighbors) AND
that cell has an interactable building, open THAT building. Else
fall back to existing scan order (player_tile → E → W → S → N).

Logic extracted to static find_interactable_for_e_key(player_tile,
mouse_tile, world) + _find_adjacent_interactable_static helpers for
test isolation (headless tests can't drive Input.mouse_position).

Existing instance method _find_adjacent_interactable preserved as a
thin wrapper.

test_building_ui_2.gd: 2 NEW sub-cases — mouse over chest beats E-scan
inserter; mouse off-grid falls back to scan. 37/37 PASS.

Preserves tap-E-without-aiming UX (no mouse intent → scan as before)
while letting players target a specific building when they want to.
Closes session-electricity-foundation Cluster B candidate.
EOF
)"
```

---

## Task 10: Chest silent-merge fix + new test sub-case

**Files:**
- Modify: `scripts/ui/chest_panel.gd` (silent-merge branch at line 218 area)
- Modify: `scripts/tests/test_building_ui_2.gd` (NEW sub-case for same-type silent-merge)

**Purpose:** Fix the deposit-and-take-back bug. When clicking a chest slot whose content type matches cursor, silently merge (cursor empties, chest gains). NOTES item 9 claimed `test_building_ui_2.gd:122` locks the bug — DBV showed that test asserts a DIFFERENT path (empty slot drop). No existing assertion to flip; this task adds a NEW test sub-case.

- [ ] **Step 1: Variable name pre-check**

Run:
```bash
grep -n "^\s*var \(chest_sm\|wheat_count_sm\|panel_sm\)\b" scripts/tests/test_building_ui_2.gd
```
No collisions expected — suffix `_sm` for silent-merge clarity.

- [ ] **Step 2: Append failing sub-case to `test_building_ui_2.gd`**

Append BEFORE the final `if failures.is_empty()` return:

```gdscript

	# ===========================================================================
	# (NEW) CHEST DEPOSIT ON SAME-TYPE SLOT — silent merge (Cluster B Item 5).
	# Previously: cursor with N wheat + clicking chest slot with M wheat would
	# _bag_add then swap-pickup the combined (N+M) wheat back → chest empty,
	# cursor has N+M. Player intent ("deposit my wheat") gave wrong outcome.
	#
	# Fixed: when types match, silently merge (cursor empties, chest gains).
	# Swap only when types differ.
	# ===========================================================================
	_disconnect_chest_test(world, panel)
	world = _make_world(parent)
	for x in range(0, 5):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.CHEST, Vector2i(0, 0), Belt.DIR_E)
	var chest_sm: Building = world.building_at(Vector2i(0, 0))
	chest_sm.state["bag"] = [[Items.Type.WHEAT, 10]]
	cursor.pick(Items.Type.WHEAT, 5)
	# Build a panel and click slot 0 (wheat view).
	var panel_sm = preload("res://scripts/ui/chest_panel.gd").new()
	parent.add_child(panel_sm)
	panel_sm.building = chest_sm
	panel_sm.cursor = cursor
	panel_sm.toast_callback = func(_m): pass
	panel_sm._handle_chest_slot_click(0, SlotClickHandler.MOD_NONE)
	# Expected: silent merge — chest has 15 wheat, cursor empty.
	var wheat_count_sm: int = Chest._bag_count(chest_sm.state["bag"], Items.Type.WHEAT)
	_check(failures, wheat_count_sm == 15,
		"same-type silent merge: chest should have 15 wheat (5 + 10), got %d" % wheat_count_sm)
	_check(failures, not cursor.has_item(),
		"same-type silent merge: cursor should be empty, got %s ×%d" % [Items.name_of(cursor.item_type), cursor.count])
	# Verify swap still works for DIFFERENT type — load chest with FLAX, cursor with WHEAT.
	cursor.clear()
	chest_sm.state["bag"] = [[Items.Type.FLAX, 7]]
	cursor.pick(Items.Type.WHEAT, 5)
	panel_sm._handle_chest_slot_click(0, SlotClickHandler.MOD_NONE)
	# Expected: swap — chest has WHEAT 5, cursor has FLAX 7.
	var wheat_in_chest: int = Chest._bag_count(chest_sm.state["bag"], Items.Type.WHEAT)
	var flax_in_chest: int = Chest._bag_count(chest_sm.state["bag"], Items.Type.FLAX)
	_check(failures, wheat_in_chest == 5 and flax_in_chest == 0,
		"different-type swap: chest should have WHEAT 5 + FLAX 0, got W%d F%d" % [wheat_in_chest, flax_in_chest])
	_check(failures, cursor.has_item() and cursor.item_type == Items.Type.FLAX and cursor.count == 7,
		"different-type swap: cursor should hold FLAX ×7, got %s ×%d" % [Items.name_of(cursor.item_type), cursor.count])
	panel_sm.queue_free()
```

(`_disconnect_chest_test` is a placeholder — implementer may inline `world.queue_free()` if the existing test helper doesn't exist.)

- [ ] **Step 3: Run tests — expect both new assertions to FAIL**

Expected: 2 failures in test_building_ui_2.gd:
- "same-type silent merge: chest should have 15 wheat..." — current behavior gives chest=0, cursor=15
- "same-type silent merge: cursor should be empty..." — current behavior leaves cursor full

- [ ] **Step 4: Apply 5-line silent-merge fix in `scripts/ui/chest_panel.gd`**

In `scripts/ui/chest_panel.gd`, locate the plain-LMB "drop into chest" block (around line 214-227). Add the silent-merge branch BEFORE the swap-pickup:

```gdscript
	# Cursor full → drop into chest. Capacity check.
	if Chest.free_capacity(building) < cursor.count:
		_toast("Chest full — cannot deposit (need %d more capacity)" % (cursor.count - Chest.free_capacity(building)))
		return
	# QoL Cluster B Item 5: silent-merge when types match — Factorio
	# convention. Without this branch, _bag_add merges into the existing
	# same-type entry, then the swap-pickup branch below picks the merged
	# entry back, leaving the chest empty (deposit-and-take-back bug).
	if view_present and int(views[slot_idx]["item_type"]) == cursor.item_type:
		Chest._bag_add(bag, cursor.item_type, cursor.count)
		cursor.clear()
		return
	Chest._bag_add(bag, cursor.item_type, cursor.count)
	if view_present:
		# Swap path: pick up the view's stack onto the now-empty cursor.
		var v2 = views[slot_idx]
		var item_type2: int = int(v2["item_type"])
		var c2: int = int(v2["count"])
		Chest._bag_remove(bag, item_type2, c2)
		cursor.pick(item_type2, c2)
	else:
		cursor.clear()
```

- [ ] **Step 5: Run tests — expect 37 PASS with both new assertions passing**

Expected: `37 passed, 0 failed`. Same-type silent merge works; different-type swap still works.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/chest_panel.gd scripts/tests/test_building_ui_2.gd
git commit -m "$(cat <<'EOF'
Task 10: Chest deposit-on-same-type silent-merge fix

chest_panel.gd: add silent-merge branch BEFORE the swap-pickup in
plain-LMB drop logic. When cursor's item type matches the existing
view's item type, _bag_add the cursor's count and clear cursor —
return early. Swap-pickup only fires when types differ.

Fixes the deposit-and-take-back bug: previously, clicking a chest slot
that already had the same item type as cursor would (1) merge cursor
into bag, then (2) immediately pick the merged stack back, leaving
chest empty and cursor with combined count.

NOTES item 9's claim that test_building_ui_2.gd:122 locked the bug
was incorrect — DBV showed that test asserts a DIFFERENT path (drop
into EMPTY slot). No assertion to flip; this commit adds a NEW
sub-case covering both merge (same type) and swap (different type)
paths.

37/37 PASS.
EOF
)"
```

---

## Task 11: PAUSE 1 — visual smoke

**Files:** none (manual gate)

**Purpose:** User-driven visual verification. All 5 items exercised individually in-game.

- [ ] **Step 1: Launch game**

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9"
```

- [ ] **Step 2: User verifies 5-item smoke matrix**

| Item | Verification |
|---|---|
| 1 — Tooltips | Hover any inventory or panel slot for ~500ms → tooltip appears with item name + description. Move to empty slot → no tooltip. Move to different item → new tooltip after 500ms. |
| 2 — Filter picker | Right-click on fast inserter to open panel. Click filter slot with empty cursor → ItemPickerModal opens with all 27 items. Click an item → filter set, picker closes. Drop-to-set still works (alternate path preserved). |
| 3 — Filter status | Fast inserter with filter set to WHEAT, source chest with only FLAX → Q-inspect on inserter shows "Status: IDLE (no items match filter)". Add WHEAT to source chest → next Q-inspect, that line is gone. |
| 4 — E-key hover | Stand adjacent to inserter+chest. Mouse over chest → press E → CHEST opens. Mouse over inserter → press E → INSERTER opens. Mouse off both → press E → first-found in scan order opens (existing behavior). |
| 5 — Chest silent-merge | Cursor with N wheat, chest slot with M wheat, click slot → chest gains N+M, cursor empty (no swap-back). Cursor with wheat, chest slot with flax, click → swap (cursor flax, chest wheat). |

- [ ] **Step 3: User reports PASS or FAIL with detail**

If FAIL: report specific item + describe what was wrong. Per UX iteration trap protocol, after 2 visual iterations on a single item, STOP and force a rule conversation.

- [ ] **Step 4: Close game on PASS, proceed to PAUSE 2**

---

## Task 12: PAUSE 2 — full gameplay

**Files:** none (manual gate)

**Purpose:** All 5 items exercised in concert during normal play. Confirms no inter-feature regressions.

- [ ] **Step 1: Launch game (same command as Task 11)**

- [ ] **Step 2: User plays a typical session segment**

Suggested 5-10 minute session:

- Build a wheat → flour → bread chain
- Use tooltips to identify items in inventory + chest contents
- Set up a fast inserter with a filter (use picker)
- Read the filter status line to debug an idle inserter
- Use E-key with mouse-aim to open specific buildings in a chain
- Cursor-pickup + deposit cycles into chests (verify silent merge)
- Mid-session save → reload → all 5 items still work post-load

- [ ] **Step 3: User reports PASS or FAIL**

PASS criteria: all 5 items work AND no existing-feature regressions surfaced.

- [ ] **Step 4: Close game on PASS, proceed to ship**

---

## Task 13: Ship — PROJECT_LOG + NOTES + tag + push

**Files:**
- Modify: `PROJECT_LOG.md` (prepend session entry)
- Modify: `NOTES.md` (mark Cluster B SHIPPED; remove items 4/5/7/9 from backlog; add any earned protocols)

- [ ] **Step 1: Prepend PROJECT_LOG entry**

Open `PROJECT_LOG.md`. Insert new entry at the top (after the file header, before the previous most-recent entry). Use this template, filling in actual commit SHAs from the session:

```markdown
---

## QoL Cluster B — UX polish (5 items)

**Date:** 2026-05-15
**Tag:** `session-qol-cluster-b`
**Save schema:** v18 unchanged (all UI-layer)
**Test count:** 35 → 37 (2 new test files: tooltip_manager + item_picker_modal; sub-cases added to inserter + building_ui_2)

5 backlog items from NOTES.md shipped: item hover tooltips, filter dropdown picker, filter status diagnostic, E-key hover-aware dispatch, chest silent-merge on same-type. All UI-layer; no save schema impact.

### What shipped

- **Item 1 — Tooltips**: NEW `TooltipManager` Control (single shared widget in $HUD with 500ms hover delay, edge-flip placement). Items.gd `description` field added to all 27 entries with code-citation-grounded text. Slot-owning Controls (inventory_grid, chest_panel, building_panel, fast_inserter_panel) call `start_hover`/`end_hover` from `_gui_input` mouse-motion handlers.
- **Item 2 — Filter picker**: NEW `ItemPickerModal` PopupPanel cloning QuantityPickerModal pattern. Plain-LMB on fast inserter's filter slot with empty cursor → opens scrollable list of all 27 items with current filter highlighted. Click → sets filter. Esc/click-outside cancels. Drop-to-set preserved as alternate path.
- **Item 3 — Filter status**: Inserter.info_lines appends `Status: IDLE (no items match filter)` when filter set AND source has no matching items. New static helper `_source_has_matching_item` mirrors `_try_pickup`'s dispatch (BELT/CHEST/Processor) read-only.
- **Item 4 — E-key hover**: main.gd `_try_interact` checks mouse tile first (if on player's adjacent cells AND has interactable, open it); else falls back to existing scan order (player → E → W → S → N). Static helpers `find_interactable_for_e_key` + `_find_adjacent_interactable_static` extracted for test isolation. Preserves tap-E-without-aiming UX.
- **Item 5 — Chest silent-merge**: chest_panel.gd plain-LMB drop adds silent-merge branch before swap-pickup. When cursor type matches existing view's type, _bag_add + cursor.clear + return (no swap). Different types still swap. Fix is 5 production lines.

### Decisions

- Tooltip approach (a) confirmed: single `TooltipManager` Control in $HUD, called by slot-owning Controls. Per-slot embedded logic (option b) rejected as duplicative.
- Description authoring approach (c) used: implementer drafted all 27 with code-citation grounding from Recipes.gd + Burner.FUEL_VALUES + processor module names; user reviewed and approved batch before tooltip widget integration (Task 3 gate).
- ItemPickerModal cloned not shared with QuantityPickerModal — UI shape diverges (list vs spinbox).
- E-key rule: hover-with-fallback (option a). Pure-mouse (option b) and inserter-deprioritized (option c) rejected.
- Chest UX: silent merge on same type, swap on different type (Factorio convention).
- NOTES item 9 claim about `test_building_ui_2.gd:122` was INCORRECT (DBV finding) — that test asserts a different code path. Chest fix added NEW test sub-case, did not flip an existing one.

### Lessons

- **Design Brief Verification at 6+ catches**: Cluster A Task 14 (refuse-clamp), Inserter Session 3 Q4 (REACH accessor), Inserter Session 3 Task 6 (SaveSystem API), Electricity Foundation Q1 (graph+dirty-flag), Electricity Foundation Task 2 (forward references), Cluster B Item 5 (test line number from NOTES was wrong; assertion was for different path). DBV protocol earning compound value across 6 incidents.
- **NOTES line references can go stale**: NOTES item 9 cited `test_building_ui_2.gd:122` — actual relevant assertion was at line 127 AND was for a different code path entirely. Trust the code search, not the line number in legacy notes.
- **Visual-feature integration test gap**: tooltip and picker tests cover state-tracking APIs (start_hover lifecycle, callback firing) but not actual rendered display. Visual verification still requires PAUSE 1 manual smoke. Acceptable for v1 — headless rendering tests would require Godot's CI/visual-regression infrastructure not in scope.

### Cluster B status

- All 4 NOTES backlog items (4 + 5 + 7 + 9) shipped this session.
- E-key item (Cluster B candidate from session-electricity-foundation) shipped this session.
- **Cluster B backlog now empty.** Future polish items go to a new Cluster C / D as they accumulate.
```

- [ ] **Step 2: Update NOTES.md — mark items SHIPPED, clean backlog**

Open `NOTES.md`. Update the "QoL Polish Session — Clusters A+C SHIPPED, B queued (3 items)" section header to "Clusters A+B+C SHIPPED, backlog empty" (or similar). For each of items 4, 5, 7, 9: mark `**SHIPPED** (Cluster B — session-qol-cluster-b)` with brief one-liner of what landed. Mark the E-key Cluster B candidate (from session-electricity-foundation cross-cutting note) as SHIPPED too.

If any earned working protocols, add new sections (e.g., "Working protocol: NOTES line references can go stale"). Otherwise just update the trackers.

- [ ] **Step 3: Final test run**

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `37 passed, 0 failed`.

- [ ] **Step 4: Commit ship entry**

```bash
git add PROJECT_LOG.md NOTES.md
git commit -m "$(cat <<'EOF'
Ship session-qol-cluster-b: PROJECT_LOG entry + NOTES updates

PROJECT_LOG: full session entry. What shipped (5 items: tooltips,
filter picker, filter status, E-key hover, chest silent-merge).
Decisions (TooltipManager option a, description authoring option c
with user gate, ItemPickerModal cloned not shared, E-key
hover-with-fallback, chest silent-merge-on-same-type). Lessons (DBV
at 6+ catches; NOTES line references can go stale; visual-feature
integration test gap acknowledged).

NOTES: marked Cluster B backlog items 4 + 5 + 7 + 9 + E-key SHIPPED.
QoL Polish Session header updated to reflect Clusters A+B+C all
shipped, backlog empty.

Final test count: 37/37 PASS. Ready for tag + push.
EOF
)"
```

- [ ] **Step 5: Tag commit**

```bash
git tag session-qol-cluster-b
git log --oneline -1
git tag --list | grep -i cluster
```
Expected: `session-qol-cluster-a` and `session-qol-cluster-b` both present.

- [ ] **Step 6: Push branch + tag**

```bash
git push origin claude/silly-bardeen-3279e9
git push origin session-qol-cluster-b
```

- [ ] **Step 7: Verify on origin**

```bash
git ls-remote origin refs/heads/claude/silly-bardeen-3279e9 refs/tags/session-qol-cluster-b
```
Expected: both refs at the ship commit SHA.

- [ ] **Step 8: Report to user**

Report: ship commit SHA, tag pushed, test count (35 → 37), total commits this session, total tag count.

---

## Self-review (writing-plans skill, completed at plan-write time)

**Spec coverage:**

- Spec §4 (Tooltips): Tasks 2 (field), 3 (descriptions), 4 (module), 5 (wiring) ✓
- Spec §5 (Filter picker): Tasks 6 (modal), 7 (wiring) ✓
- Spec §6 (Filter status): Task 8 ✓
- Spec §7 (E-key hover): Task 9 ✓
- Spec §8 (Chest silent-merge): Task 10 ✓
- Spec §9 (Test coverage): each task has its own TDD red/green; runner count goes 35 → 37 with 2 new files ✓
- Spec §10 (No save bump): explicitly stated in PROJECT_LOG template ✓
- Spec §11 (Touchpoint inventory): all 17 files (11 production + 4 test + 2 housekeeping) appear in file map at plan start ✓
- Spec §12 (Implementation order): Item 1 first as foundation, 2/3 together, 4/5 standalone — reflected in Task 2-10 sequence ✓
- Spec §13 (Validation criteria 14 items): reflected in PAUSE 1 smoke matrix (Task 11) + PAUSE 2 acceptance (Task 12) ✓
- Spec §14 (Out-of-scope reminders): documented in PROJECT_LOG decision log + carried as principles ✓

**Placeholder scan:** No TBD / "implement appropriately" / "similar to Task N" patterns. Each task has complete code blocks. Item 5 (chest fix) acknowledges NOTES line reference was stale and adds NEW test rather than flipping a non-existent assertion.

**Type consistency:**

- `Items.description_of(t: int) -> String` — used consistently across tasks 2, 4, 6, 11
- `TooltipManager.start_hover(item_type, mouse_pos)` / `end_hover()` — consistent across Tasks 4, 5, 11
- `ItemPickerModal.open(anchor, current_filter, confirm_cb)` — consistent across Tasks 6, 7, 11
- `_source_has_matching_item(world, src_pos, item_type)` — defined Task 8, referenced Task 8 only
- `find_interactable_for_e_key(player_tile, mouse_tile, world)` — defined Task 9, tested Task 9
- `Buildings.has_interaction_ui(b.type)` — existing helper, used Task 9 helper
- Variable name pre-check protocol mentioned per task with new test sub-cases (Tasks 8, 9, 10) ✓

No type-name drift between tasks. Plan ready for execution.
