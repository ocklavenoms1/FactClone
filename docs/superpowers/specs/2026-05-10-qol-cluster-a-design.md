# QoL Cluster A — Click-handling extraction + shift/ctrl stack ops

**Session tag (planned):** `session-qol-cluster-a`
**Date:** 2026-05-10
**Save schema impact:** none (v18, no bump)
**Test count target:** 33 → 46 (+13 sub-suites)
**Methodology:** Superpowers brainstorming → writing-plans → TDD → verification-before-completion, wrapped by CLAUDE.md project protocols (design pass / PAUSE checkpoints / PROJECT_LOG / tagged commit).

---

## 1. Context

Two related UX gaps, locked as Cluster A in `NOTES.md` ("QoL Polish Session — Cluster C SHIPPED, A+B queued"):

1. `BuildingPanel._handle_player_slot_click` and `inventory_grid._handle_left_click_player` are line-for-line duplicated (~30 lines of pick / place / merge / swap).
2. No shift+click stack-split and no ctrl+click quantity picker. Players moving large stacks must drag the entire stack and re-pick the residue, or open multiple modals to chip away.

Cluster A's *extraction* is also the architectural prerequisite for clusters 4–5–7 (tooltip / filter dropdown / filter diagnostic), but those remain Cluster B and OUT OF SCOPE here.

## 2. Scope (locked — do not extend)

**In:**

- Extract the duplicated player-slot click logic to a shared `SlotClickHandler` static module.
- Add **shift+LMB** = half-stack take/drop across the relevant slot-kind matrix (see §5).
- Add **ctrl+LMB** = quantity picker modal across the same matrix (see §6).

**Out (deferred to Cluster B / future):**

- Item hover tooltips
- Filter dropdown picker
- Filter status diagnostic line
- Any RMB behavior change (FastInserterPanel's RMB-clear stays untouched)

## 3. Methodology layering

The wrapper stays as CLAUDE.md prescribes; Superpowers slots into the design + inner loop:

| Project protocol | Superpowers layer |
|---|---|
| Design pass before code | `brainstorming` → this spec |
| Implementation plan | `writing-plans` → stepwise plan file |
| Each step coded | `test-driven-development` for the inner loop |
| PAUSE 1 (visual smoke after wire-up) | `verification-before-completion` + manual smoke |
| PAUSE 2 (full gameplay verification) | `verification-before-completion` + `requesting-code-review` |
| PROJECT_LOG.md + tag | `finishing-a-development-branch` |
| Stuck | `systematic-debugging` |

The handoff's critical gate (regression-check after each migration before adding features) maps to a TDD step boundary: the refactor lands as **N green tests still green** before any shift/ctrl test enters the suite.

## 4. Architecture

### 4.1 New module: `SlotClickHandler` (static)

**File:** `scripts/ui/slot_click_handler.gd` (new, ~80 lines).
**Pattern:** static module — mirrors `Burner`, `Processor`, `Inserter`, `Belt`, `Buildings`. No scene-tree dependency. Pure functions.

**API surface (locked):**

```gdscript
class_name SlotClickHandler

const MOD_NONE: int = 0
const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2

# Plain LMB / shift+LMB on a player-inventory ItemStack.
# Mutates slot and cursor in place.
static func handle_player_slot(slot: ItemStack, cursor: CursorStack, mods: int) -> void

# Returns the SpinBox max for ctrl+click on a player slot. Caller uses
# the returned value > 0 as the pre-open gate (0 → no-op, do not open).
static func ctrl_click_max(slot: ItemStack, cursor: CursorStack) -> int

# Commits an exact-N transfer (player slot path) on picker confirm.
# Direction inferred from cursor/slot state at call time.
static func ctrl_click_transfer(slot: ItemStack, cursor: CursorStack, n: int) -> void

# Shared math util used by handler AND by per-kind dispatchers in
# BuildingPanel / ChestPanel for their own shift/ctrl branches.
static func split_half(n: int) -> int  # returns int(ceil(n / 2.0))
```

**Why static module over alternatives:**

- Matches established static-module pattern; zero scene-tree coupling; pure functions are trivial to unit-test.
- Rejected: method on `CursorStack` — would double the size of a currently-pure data model.
- Rejected: method on `SlotWidget` — CLAUDE.md explicitly forbids click logic in SlotWidget (pure render helpers).
- Rejected: universal entry point that dispatches across all slot kinds — would couple SlotClickHandler to `Burner.FUEL_VALUES`, `Buildings.slot_layout_for`, `Chest._bag_*`, etc. Per "isolation and clarity," each slot kind keeps its own context; the shared seam is `split_half(n)`, not a god dispatcher.

### 4.2 New widget: `QuantityPickerModal`

**Files:**
- `scripts/ui/quantity_picker_modal.gd` (new, ~120 lines): extends `PopupPanel`.
- `scenes/quantity_picker_modal.tscn` (new): scene wrapping the PopupPanel with child `VBoxContainer { Label, SpinBox, HBoxContainer { OK, Cancel } }`.

**Why PopupPanel over alternatives:**

- `popup_exclusive_on_parent()` gives Esc-close, click-outside-close, and modal blocking for free.
- `ConfirmationDialog` rejected: centers on screen with title bar; wrong shape.
- Custom Control overlay rejected: would re-implement Esc handling, click-outside, modal blocking — all built into PopupPanel.
- Godot `Window` rejected: OS-level window; overkill.

**API:**

```gdscript
class_name QuantityPickerModal

# direction: "Take" or "Give" (used in label).
# label_item: item name displayed in the label (or "fuel units" for fuel-take).
# confirm_cb: Callable(amount: int) -> void, invoked on Enter/OK.
func open(anchor: Vector2, direction: String, label_item: String,
          max_n: int, default_n: int, confirm_cb: Callable) -> void
```

**Behavior:**

- On open: `grab_focus()` on the SpinBox + `get_line_edit().select_all()`.
- **Enter** anywhere → OK (commit, call confirm_cb, close).
- **Esc** → cancel (close, no transfer).
- **Click outside** → cancel.
- OK / Cancel buttons mirror Enter / Esc.

**Placement (anchor logic):**

- Anchor = clicked slot's center, offset `+60px right, -40px up`.
- If would clip right viewport edge → flip to `-(60 + picker_width) left`.
- If would clip bottom edge → flip up.

**Lifecycle:**

- Owned by `main.gd` as a HUD singleton (`@onready var quantity_picker`). Loaded via `scenes/main.tscn` `ext_resource`.
- Modal is hard: while open, all other input blocked (panels, world, hotbar, Tab).
- Ephemeral state — never serialized. On game load, picker is closed.

### 4.3 Modifier extraction

In each `_gui_input(event)` that needs it:

```gdscript
var mods: int = SlotClickHandler.MOD_NONE
if event.shift_pressed: mods |= SlotClickHandler.MOD_SHIFT
if event.ctrl_pressed:  mods |= SlotClickHandler.MOD_CTRL
```

Mods threading:
- `inventory_grid._handle_left_click_player(slot_idx)` → calls `SlotClickHandler.handle_player_slot(slot, cursor, mods)` (mods captured in `_gui_input`).
- `BuildingPanel._handle_player_slot_click(slot_idx)` → same call.
- `BuildingPanel._handle_building_slot_click(hit)` → threads `mods` into `_take_from_slot` and `_drop_into_slot`.
- `chest_panel._handle_chest_slot_click(slot_idx)` → threads `mods` into its body.

Ctrl is handled at the dispatcher level: when `mods & MOD_CTRL != 0`, the dispatcher computes max inline (or via `SlotClickHandler.ctrl_click_max` for the player path), gates on `> 0`, and either opens the picker (with the right `confirm_cb`) or silently no-ops.

## 5. Shift+LMB semantics (locked)

### 5.1 (cursor × slot) matrix

| Cursor | Slot | Plain LMB (unchanged) | Shift+LMB |
|---|---|---|---|
| Empty | Empty | No-op | No-op |
| Empty | N items | Take all N | **Take ceil(N/2)** |
| M items | Empty | Drop all M | **Drop ceil(M/2)** |
| M items | K items, same type | Merge into slot (clamped to max_stack) | **Drop ceil(M/2), clamp to remaining space** |
| M items | K items, different type | Swap | **No-op** |

Same-type drop clamp example: cursor 10 wheat, slot 8 wheat, max_stack 10. `ceil(10/2) = 5` wants to drop, only 2 space available → drop 2 (silent clamp, matches plain-LMB silent-on-full).

Different-type no-op: shift never swaps. Plain LMB still swaps; shift-misclick stays safe.

Empty-slot drop residue: cursor keeps `floor(M/2)`. Same arithmetic as the take case (slot keeps `floor(N/2)`).

### 5.2 Slot-kind matrix

| Slot kind | Locus today | Shift behavior |
|---|---|---|
| Player (`Inventory.slots` → `ItemStack`) | `SlotClickHandler.handle_player_slot` | per §5.1 directly |
| Chest (bag Array via `Chest._bag_*`) | `chest_panel._handle_chest_slot_click` | §5.1 semantics via inline branches; uses `SlotClickHandler.split_half(n)`. **Drop clamp differs from player slot:** chest's existing LMB rejects with toast when `cursor.count > free_capacity` (no partial drop). Shift+drop preserves that — if `split_half(cursor.count) > free_capacity`, refuse with the same toast. Player-slot's silent-clamp does NOT inherit here. |
| Building input (`b.state[field]` Array) | `BuildingPanel._drop_into_input` / `_take_from_slot` "input" branch | §5.1 semantics via inline branches; uses `split_half` |
| Building output / output_multi (take-only) | `BuildingPanel._take_from_slot` "output" / "output_multi" | Take ceil(count/2) of the addressed entry (sub_idx scopes for multi) |
| Building fuel (`b.state.fuel_buffer` units + FUEL_VALUES) | `BuildingPanel._drop_into_fuel` / fuel branch of `_take_from_slot` | Take: `split_half(units)` wood (lossy); Drop: `split_half(cursor.count)` items, atomic via FUEL_VALUES, silent-clamp to free units |
| Building filter (scalar int metadata) | `BuildingPanel._drop_into_filter` | **No-op**, no toast |

## 6. Ctrl+LMB picker semantics (locked)

### 6.1 SpinBox bounds per state

| State | Direction | Min | Max | Default |
|---|---|---|---|---|
| Empty + N items | TAKE | 1 | N | N |
| M cursor + empty slot | GIVE | 1 | M | M |
| M cursor + K slot, same type, max_stack S | GIVE | 1 | min(M, S−K) | min(M, S−K) |
| M cursor + K slot, different type | — | picker does not open |
| Empty + empty | — | picker does not open |

Default = max ("Minecraft convention"): "transfer all unless you change it."

**Pre-open gate:** caller computes max via `SlotClickHandler.ctrl_click_max(slot, cursor)` (or kind-specific equivalent for chest/input/fuel). If returned max ≤ 0 → silent no-op, picker is not opened. Examples that trip the gate:

- Same-type drop where slot is at max_stack (S−K = 0).
- TAKE on empty source.
- Fuel drop where free units < energy_per (can't fit one atomic item).

### 6.2 Fuel-slot picker (asymmetric labels — semantic honesty)

| Direction | SpinBox label | Min | Max | Default | On confirm |
|---|---|---|---|---|---|
| TAKE | "Take ___ fuel units (returned as wood)" | 1 | `buffer_units` | `buffer_units` | `cursor.pick(WOOD, N); fuel_buffer -= N` |
| DROP | "Give ___ <last_fuel_item name>" | 1 | `min(cursor.count, free_units / energy_per)` | same as max | atomic drop of N items, `fuel_buffer += N * energy_per` |

DROP default is the actually-fitting count, not cursor.count. Picker never suggests a number that would clamp. Verified in test sub-suite #11 (e.g., cursor 10 coal, free=16 units (items_that_fit=4) → default=4, max=4).

TAKE label density acknowledged. Ship as proposed; verify at PAUSE smoke. If non-developer reading confuses the math, follow-up with tooltip-on-hover or rephrase — not a blocker.

### 6.3 Modal behavior recap

- Hard modal — blocks all other input until Esc/Cancel/OK.
- Picker state ephemeral (never serialized).
- Cursor cannot change between open and confirm (4f / 4h locked).
- Filter slot: no picker, no-op, no toast.

## 7. Test plan (33 → 46, +13 sub-suites)

New file: `scripts/tests/test_slot_click_handler.gd`. Registered in `test_runner.gd`.

| # | Sub-suite name | What it covers |
|---|---|---|
| 1 | `player_slot_regression` | Plain LMB across 5 (cursor × slot) cells matches pre-refactor behavior. Asserts byte-identical state mutation for empty+empty, empty+N pick, M+empty drop, M+same merge with clamp, M+different swap. **The critical gate test.** |
| 2 | `shift_take_player_half` | Empty cursor + slot with N → take ceil(N/2). Cases N=1 (degenerate take all), N=2 (take 1, leave 1), N=7 (take 4, leave 3). |
| 3 | `shift_drop_player_half_empty` | M cursor + empty slot → drop ceil(M/2). Cases M=1, M=7. |
| 4 | `shift_drop_player_half_matching` | M cursor + K slot same type → drop ceil(M/2) merged. Includes **capacity-clamp**: cursor 10 wheat, slot 8 wheat, max_stack 10 → drop 2 (not 5, not no-op). |
| 5 | `shift_player_diff_type_noop` | M cursor + K slot different type → no-op, no swap, no state change. |
| 6 | `shift_chest_take_and_drop` | Shift+LMB on chest bag slot: take ceil(N/2), drop ceil(M/2). Includes chest-specific refuse-with-toast when `split_half(M) > free_capacity` (NOT silent clamp — chest preserves LMB convention per §5.2). |
| 7 | `shift_building_input_and_output` | Shift+LMB on building input: take/drop via `_take_from_slot` / `_drop_into_input`. Shift+LMB on output_multi sub_idx: take ceil(entry.count/2) of the addressed entry. |
| 8 | `shift_fuel_take_units` | Buffer = 16 units (was 4 coal). Shift+take → cursor gets 8 wood, buffer left at 8. Lossy precedent preserved. |
| 9 | `shift_fuel_drop_items_atomic` | Cursor 6 coal, free 8 units (items_that_fit=2). split_half(6)=3 but clamp → drop 2 atomic. Cursor = 4 coal, buffer += 8 units. |
| 10 | `shift_filter_noop` | Shift+LMB on FastInserter filter slot → no-op, no toast, filter unchanged. |
| 11 | `ctrl_picker_open_default_max` | For each kind (player, chest, input, fuel-take, fuel-drop): ctrl+LMB opens picker with correct max/default. Includes DROP picker default-shows-actually-fits assertion (cursor 10 coal, free=16 units (items_that_fit=4) → default=4, max=4). |
| 12 | `ctrl_picker_confirm_cancel_gate` | Enter commits transfer (state changes by N). Esc cancels (no state change). Max-zero gate: ctrl+LMB on full same-type slot / empty source / fuel-drop with no atomic fit → picker does not open. |
| 13 | `ctrl_picker_outside_click_no_propagation` | Open picker on a slot. Simulate mouse click at position outside picker's rect. Assert: (a) picker closes (cancel behavior), (b) `confirm_cb` NOT invoked, (c) cursor/slot state unchanged, (d) click did NOT propagate to underlying panel (no `SlotClickHandler.handle_player_slot` fired, no other slot clicked). Rationale: PopupPanel provides click-outside-close natively, but a future mouse_filter regression could break propagation suppression silently. Esc-cancel test #12 covers a different code path through Godot's input system. |

Sub-suite naming convention follows `test_inserter.gd` and other test files.

## 8. Implementation phases (honoring the critical gate)

### Phase 1 — Refactor: extract SlotClickHandler (LMB only)

- Create `scripts/ui/slot_click_handler.gd` with `handle_player_slot`, `split_half`. (NO shift/ctrl branches yet — keep behavior byte-identical.)
- Replace `inventory_grid._handle_left_click_player` body with the helper call.
- Replace `BuildingPanel._handle_player_slot_click` body with the helper call.
- Create `scripts/tests/test_slot_click_handler.gd` with sub-suite #1 only.
- Register in `test_runner.gd`.

**GATE 1 (the handoff's critical gate):** 33 + 1 = 34 tests pass. Manual smoke:
- Open inventory grid, pick/place/swap/merge across slots.
- Open chest panel, pick/place across player slots and chest slots.
- Open a building panel (e.g., smelter), pick/place across player slots.

No behavior change visible to player. Plain LMB everywhere matches pre-refactor.

### Phase 2 — Shift+LMB across the matrix

- Add `MOD_*` constants to SlotClickHandler. Extend `handle_player_slot` with shift branches per §5.1.
- Thread `mods` param through `BuildingPanel._take_from_slot` / `_drop_into_slot` / `_drop_into_input` / `_drop_into_fuel`; add shift branches.
- Thread `mods` through `chest_panel._handle_chest_slot_click`; add shift branches.
- Extract modifier flags in each panel's `_gui_input` (shift_pressed / ctrl_pressed → mods bitfield).
- Add sub-suites #2–#10 (9 tests). Now 34 + 9 = 43.

**GATE 2:** All 43 pass. Manual smoke for shift on each kind: player, chest, building input, output_multi, fuel, filter (no-op). RMB-clear on fast inserter filter still works (regression on §2-out-of-scope).

### Phase 3 — Ctrl+LMB picker

- Create `scripts/ui/quantity_picker_modal.gd` + `scenes/quantity_picker_modal.tscn`.
- Wire `@onready var quantity_picker` in `main.gd`; bump `scenes/main.tscn` load_steps; add HUD node.
- Add `SlotClickHandler.ctrl_click_max` / `ctrl_click_transfer` for player path.
- For chest / input / fuel: compute `max` **inline** in each dispatcher's ctrl branch (no separate helpers — each kind's max is 2–3 lines and tightly coupled to its data shape; helpers would be near-empty wrappers).
- Add ctrl branches in dispatchers: pre-open gate (`max > 0`) → open picker with `confirm_cb` Callable.
- Add sub-suites #11–#13 (3 tests). Now 43 + 3 = **46**.

**PAUSE 2 (full gameplay verification):** All 46 pass. Manual smoke for picker on each kind. Confirmations:
- Picker placement avoids viewport edge (flips when needed).
- Enter / Esc / click-outside / OK / Cancel all behave as locked.
- Hotbar number-key, Tab, world clicks all blocked while picker open.
- After Esc/Cancel: input restored to normal.
- Save/load cycle does not surface picker (ephemerality verified manually by saving with a building panel open and reloading).

### Commit & ship

- `git add` only the files touched by this session. Commit message references `session-qol-cluster-a`.
- Tag the commit `session-qol-cluster-a`.
- Push to origin.
- Write PROJECT_LOG.md entry (newest on top): What shipped / Decisions / Lessons.
- Update NOTES.md "QoL Polish Session" header — mark Cluster A SHIPPED, leave Cluster B (items 4 / 5 / 7) queued.

## 9. Files touched

**New:**

- `scripts/ui/slot_click_handler.gd` (~80 lines)
- `scripts/ui/quantity_picker_modal.gd` (~120 lines)
- `scenes/quantity_picker_modal.tscn` (small)
- `scripts/tests/test_slot_click_handler.gd` (~430 lines, 13 sub-suites)

**Modified (estimated diff):**

- `scripts/ui/building_panel.gd` (~60 line diff): mods threading on `_take_from_slot` / `_drop_into_slot` / `_drop_into_input` / `_drop_into_fuel`; ctrl-picker call sites; LMB body delegates to SlotClickHandler.
- `scripts/ui/inventory_grid.gd` (~15 line diff): `_handle_left_click_player` body → helper call; mods extraction from event.
- `scripts/ui/chest_panel.gd` (~40 line diff): mods threading on `_handle_chest_slot_click`; shift/ctrl branches.
- `scripts/main.gd` (~10 line diff): `@onready var quantity_picker`; pass to panels.
- `scenes/main.tscn` (~3 line diff): load_steps bump + HUD node ext_resource.
- `scripts/tests/test_runner.gd` (~3 line diff): register new test.

**Unchanged (explicit):**

- `scripts/ui/slot_widget.gd` (CLAUDE.md rule: pure render helpers, no click logic).
- `scripts/ui/cursor_stack.gd` (Q1: keep data/serialization undiluted).
- `scripts/ui/fast_inserter_panel.gd` (RMB-clear stays; Cluster A doesn't touch RMB anywhere).

## 10. Acceptance criteria

- [ ] 33 → 46 tests passing (33 baseline + 13 new sub-suites).
- [ ] Plain LMB behavior on player slot identical to pre-refactor (verified at GATE 1 by sub-suite #1 + manual smoke).
- [ ] Shift+LMB matches §5 across all kinds in the matrix.
- [ ] Ctrl+LMB picker matches §6, including pre-open max-zero gate.
- [ ] FastInserter RMB-clear still works (no regression).
- [ ] Save schema unchanged (v18, no migration registered).
- [ ] Manual smoke at PAUSE 2 confirms: picker placement edge-flip, modal blocking, hotbar/Tab/world all gated while picker open, picker ephemerality across save/load.
- [ ] Commit tagged `session-qol-cluster-a`, pushed to origin.
- [ ] PROJECT_LOG.md entry written (newest on top).
- [ ] NOTES.md updated: Cluster A SHIPPED; Cluster B (items 4/5/7) remains queued.

## 11. Out-of-scope reminders (don't drift)

- Item hover tooltips (NOTES.md item 4)
- Filter dropdown picker (NOTES.md item 5)
- Filter status diagnostic line (NOTES.md item 7)
- Any RMB behavior change
- Save schema bump of any kind
- Generalizing SlotClickHandler beyond the player-slot path (per Q2 — wait for evidence)
- Tooltip on the fuel TAKE picker label (mark for follow-up if PAUSE smoke confuses, not a blocker)
