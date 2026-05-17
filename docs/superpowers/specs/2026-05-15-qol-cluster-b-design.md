# QoL Cluster B — UX polish (5 items)

**Session tag (planned):** `session-qol-cluster-b`
**Date:** 2026-05-15
**Save schema impact:** none (all UI-layer)
**Test count target:** 35 → ~40 (one new test file for tooltips/picker + 1-2 sub-cases per other item)
**Methodology:** Superpowers brainstorming → writing-plans → subagent-driven TDD. Layered onto validated CLAUDE.md project protocols (design pass / PAUSE checkpoints / PROJECT_LOG / tagged commit).

---

## 1. Context

Cluster B is the second polish sweep after Cluster A shipped at `session-qol-cluster-a` (2026-05-15). Five items collected over the multi-arc run:

| # | Item | Origin | Type |
|---|---|---|---|
| 1 | Item hover tooltips with descriptions | NOTES item 4 (post-session-mining-manual backlog) | NEW feature |
| 2 | Filter dropdown picker | NOTES item 5 (post-Cluster-A backlog) | NEW feature |
| 3 | Filter status diagnostic line | NOTES item 7 (post-session-inserter-fast-filter PAUSE 2) | Polish |
| 4 | E-key hover-aware dispatch | NOTES item from session-electricity-foundation Cluster B candidate | UX fix |
| 5 | Chest deposit-on-same-type silent-merge | NOTES item 9 (Cluster A GATE 2 discovery) | UX fix |

Items 1-3 form a discoverability cluster (tooltips support the filter picker, status line completes the inserter panel feedback loop). Items 4-5 are standalone UX fixes.

Validated session-by-session protocols apply (Design Brief Verification — now at 5 catches, UX iteration trap, magic-number audit, variable-pre-check, line-quoting on reviewers). All items are UI-layer; **save schema stays at v18**.

## 2. Scope (locked — do not extend)

**In:** all 5 items as specified in sections 4-8. See implementation order in section 12.

**Out (deferred to Cluster C / future sessions):**

- Localization / i18n of tooltip descriptions (English-only this session)
- Custom tooltip styling / theming beyond a single Label widget
- Filter picker fuzzy-search / type-to-filter
- Filter picker showing item icons (text-only this session — pixel-art icons are a separate art pass)
- E-key visualization (no highlight over the building that E would open — pure dispatch fix)
- Chest "all-of-this-type" pickup hotkey (separate UX request, not in NOTES)
- Inventory grid tooltip details beyond name + description (e.g., max_stack, current count breakdown)

## 3. Methodology layering

Subagent triad per task. Line-quoting on reviewers. Strengthened scope-deviation protocol. Design Brief Verification continues. UX iteration trap protocol applies (after 2 failed visual iterations, force the rule).

Per-task estimated time: Item 1 = ~1 hour (largest — tooltip widget + 27 descriptions); Items 2-3 = ~30 min each; Items 4-5 = ~20 min each. **Total estimated ~3 hours.**

## 4. Item 1 — Item hover tooltips

### Decision

**Approach (a) — single `TooltipManager` widget reusable across slots.** Verified against project patterns: `SlotWidget`, `QuantityPickerModal`, `SlotClickHandler` are all single-responsibility shared modules. Per-slot embedded logic (option b) would duplicate hover-tracking across `InventoryGrid`, `BuildingPanel`, `ChestPanel`. Godot's built-in `Control.tooltip_text` (option c) doesn't compose well with `_gui_input`-based slot widgets that draw their own rects (not Control children).

### Components

- **`scripts/ui/tooltip_manager.gd`** — NEW `class_name TooltipManager extends Control`. Singleton-style: one instance lives in main scene (`$HUD/TooltipManager`), accessed by all panels. Tracks current hover target + hover-start timestamp; shows the tooltip after 500ms hover delay; hides on mouse-leave or mouse-move-to-different-target.
- **`scripts/world/items.gd`** — each `Items.Type` DATA entry gains a `"description"` field (~27 entries). Example shape:
  ```gdscript
  Type.WHEAT: { "name": "Wheat", "color": ..., "max_stack": 100, "description": "Raw grain. Mill it into Flour for the bread chain." }
  ```
- **`Items.description_of(t: int) -> String`** — accessor with empty-string fallback for unknown types.
- **Slot widgets** (`SlotWidget` / inventory grid renderer / panel renderers) call `TooltipManager.start_hover(item_type, mouse_pos)` and `TooltipManager.end_hover()` from `_input` / `_gui_input` mouse-motion handlers. Pass `-1` for empty slots → no tooltip.

### Tooltip widget rendering

- `PanelContainer` with VBox containing two `Label`s (name in bold, description as wrap-text body).
- Floats at `mouse_pos + Vector2(16, 16)` (offset to avoid covering cursor). Edge-flip if would overflow viewport right/bottom edges.
- White text on dark `Color(0.10, 0.10, 0.15, 0.92)` background, 1-px lighter border.
- z-index above all panels.

### Hover delay

- 500ms (`HOVER_DELAY_MS: int = 500`) — matches Factorio / common game convention. Prevents tooltip thrash on quick mouse traversal.
- Timer-based: when hover starts, set `_hover_start_tick = Time.get_ticks_msec()`; in `_process`, if `_hover_target != null and (now - _hover_start_tick) >= HOVER_DELAY_MS` and tooltip not yet shown, show.

### Item descriptions (content authoring)

27 entries — examples for tone calibration:

| Item | Description |
|---|---|
| WHEAT | Raw grain. Mill into Flour for the bread chain. |
| FLOUR | Milled wheat. Mix with Water + Yeast in a Mixer to make Dough. |
| YEAST | Live culture. Grown in Yeast Culture from Sugar + Water. |
| DOUGH | Unleavened mix. Proof in a Proofer to make Risen Dough. |
| RISEN_DOUGH | Proofed bread base. Bake in an Oven to make Bread. |
| BREAD | Edible. Pack 4 loaves in a Packager to make a Loaf Pack. |
| LOAF_PACK | Compact food. Composts to high-tier fertilizer; also fuel. |
| FUEL_BRIQUETTE | Densest fuel (8 energy units). Crafted in a Briquetter. |
| WOOD | Tree-felling product. Basic fuel (1 unit) or building chain input. |
| COAL | Mined fuel. 4 energy units. |
| RAW_STONE | Mined material. Future stone-crafting chain (Session 5+). |
| IRON_ORE | Smelt in a Smelter to make Iron Ingot. |
| IRON_INGOT | Smelted iron. Future tool / electric chains (Session 5+). |
| COPPER_ORE | Smelt in a Smelter to make Copper Ingot. |
| COPPER_INGOT | Smelted copper. Future electric chains (Session 5+). |
| CLAY | Mined material. Future brick chain (Session 5+). |
| FLAX | Crop. Ret in a Retter to make Fiber. |
| FIBER | Retted flax. Weave in a Loom to make Cloth. |
| CLOTH | Woven fiber. Sew in a Tailor to make a Bag. |
| BAG | Player inventory upgrade — increases bag-cap by N slots. |
| SUGAR_BEET | Sugar crop. Press in a Sugar Press to make Sugar. |
| SUGAR | Refined sugar. Feeds Yeast Culture. |
| GRAIN | Thresher output. Mill into Flour (parallel route to direct Wheat→Flour). |
| STRAW | Thresher byproduct. Future bedding / composting input. |
| COMPOST_LOW | Tier-1 fertilizer. Applied via Fertilizer Applicator. |
| COMPOST_MID | Tier-2 fertilizer. Stronger regen than LOW. |
| COMPOST_HIGH | Tier-3 fertilizer. Restores wasteland tiles. |

Tone: factual, mechanically informative, mentions recipe chain or building name. ~50-80 chars each.

### Tests

- `test_tooltip_manager.gd` — sub-cases for: hover starts timer, end_hover clears, different-target restarts timer, `description_of(-1)` returns empty string. ~3 sub-cases.

## 5. Item 2 — Filter dropdown picker

### Decision

**NEW `ItemPickerModal extends PopupPanel`** — mirrors `QuantityPickerModal` pattern (validated at Cluster A). Single-responsibility: shows scrollable list of all items, click → call confirm callback with chosen `Items.Type`. Different UI shape from `QuantityPickerModal` (list vs spinbox) makes shared parent unhelpful; clone the pattern.

### Components

- **`scripts/ui/item_picker_modal.gd`** — `class_name ItemPickerModal extends PopupPanel`. Methods:
  ```gdscript
  func open(anchor: Vector2, current_filter: int, confirm_cb: Callable) -> void
  func _on_item_selected(item_type: int) -> void  # calls confirm_cb.call(item_type), hides
  ```
- **`scenes/item_picker_modal.tscn`** — PopupPanel containing `VBoxContainer > ScrollContainer > VBoxContainer` of clickable item rows. Each row: `Button` with text `"%s — %s" % [item_name, item_description]` (uses Item 1's description field). Highlight current_filter selection.
- **Trigger:** `FastInserterPanel` (and future tier panels) detects plain-LMB click on filter slot when cursor is empty → opens `ItemPickerModal`. Drop-to-set (existing path) unchanged — both paths produce the same filter set.
- **`popup_exclusive_on_parent`** for hard-modal behavior (Esc, click-outside cancel; matches QuantityPickerModal protocol).

### Position

- Picker opens at filter slot's screen position + Vector2(0, slot_size) (drops down below slot). Edge-flip if would overflow viewport bottom.
- Size: ~250px wide × ~300px tall (scrollable). 27 items fit roughly 12 rows at 25px each → scroll for the rest.

### Tests

- `test_item_picker_modal.gd` (or fold into `test_slot_click_handler.gd` if smaller scope warrants) — sub-cases for: open returns the chosen item via callback, Esc cancels (callback not called), current_filter highlighted on open. ~3 sub-cases.

## 6. Item 3 — Filter status diagnostic line

### Decision

Append a single line to `Inserter.info_lines(b, world)` when `filter_item_type >= 0` AND no matching items present in source:

```
Status: IDLE (no items match filter — set filter cleared or refill source with matching items)
```

Only fires for inserters that have filter capability (currently `FAST_INSERTER`; future tiers via the parametric pattern). Place after the existing `Filter:` line, before the `Burner.info_lines` block.

### Detection logic

In `Inserter.info_lines`, after the filter line, run a quick source-side scan:

```gdscript
if b.type == Buildings.Type.FAST_INSERTER:
    var filter: int = int(b.state.get("filter_item_type", -1))
    if filter >= 0:
        var src_pos: Vector2i = source_tile(b)
        var has_matching: bool = _source_has_matching_item(world, src_pos, filter)
        if not has_matching:
            lines.append("Status: IDLE (no items match filter)")
```

Where `_source_has_matching_item(world, pos, item_type)` is a small static helper that handles belt / chest / processor source types — same dispatch as `_pickup_from_belt` / `_pickup_from_chest` / `_pickup_from_processor` but read-only.

### Tests

Append sub-case to `test_inserter.gd`: fast inserter with filter set + source chest empty → info_lines contains "no items match filter". Then load source with matching item → line removed. ~1 sub-case.

## 7. Item 4 — E-key hover-aware dispatch

### Decision

**Rule (locked by user):** mouse cursor over an adjacent building → open THAT one. Else fall back to current scan.

### Implementation

Modify `_try_interact(player_tile)` in `scripts/main.gd:998-1018`:

1. Compute `mouse_tile` from current mouse position (existing helpers — `grid_world.world_pos_to_tile` or similar).
2. Check: is `mouse_tile` one of the player's adjacent cells (player_tile + 0 / ±1 / ±0 ±1, the same 5-cell scan area)?
3. If yes AND has an interactable building at `mouse_tile` → open that building.
4. Else → existing `_find_adjacent_interactable(player_tile)` scan order (player_tile → E → W → S → N).

### Edge cases

- Mouse outside the 5-cell adjacency area → fallback to scan (preserves "tap E without aiming" UX)
- Mouse on player_tile itself with a building under player → that building wins (player_tile is first in current scan order anyway, so no behavior change)
- Mouse outside viewport / over UI → fallback to scan (mouse_tile would be `-1, -1` or similar — explicit guard)

### Tests

`test_interact.gd` (or fold into `test_building_ui_2.gd`) — 2 sub-cases:
1. Player adjacent to inserter AND chest; mouse over chest; press E → chest opens (not inserter, which would have won the scan).
2. Player adjacent to inserter only (no chest); mouse over empty tile; press E → inserter opens (fallback to scan works).

## 8. Item 5 — Chest deposit-on-same-type silent-merge

### Decision

**5-line fix at `scripts/ui/chest_panel.gd:218`** per NOTES item 9. Add silent-merge branch BEFORE the swap-pickup at line 219:

```gdscript
# Cursor full → drop into chest. Capacity check.
if Chest.free_capacity(building) < cursor.count:
    _toast("Chest full — cannot deposit (need %d more capacity)" % (cursor.count - Chest.free_capacity(building)))
    return
# NEW: silent-merge when types match — Factorio convention.
# Prevents the deposit-and-take-back loop where _bag_add merges into
# an existing same-type entry and the swap-pickup branch immediately
# picks the merged entry back, leaving the chest empty.
if view_present and int(views[slot_idx]["item_type"]) == cursor.item_type:
    Chest._bag_add(bag, cursor.item_type, cursor.count)
    cursor.clear()
    return
Chest._bag_add(bag, cursor.item_type, cursor.count)
if view_present:
    # Swap path: pick up the view's stack onto the now-empty cursor.
    var v2 = views[slot_idx]
    ...
```

### Test update required

`test_building_ui_2.gd:122` asserts the OLD (buggy) behavior:
```gdscript
# OLD: After deposit, chest has 50 wheat (the cursor's 50 + chest's existing pre-test).
_check(failures, Chest._bag_count(chest.state.bag, Items.Type.WHEAT) == 50, ...)
```

Must flip to the NEW (correct) behavior — chest gains the deposited count, cursor empties. Exact assertion depends on the test's setup state; the implementer should read the test's pre-state and compute the post-state per the new rule, NOT guess.

### Tests

The test update is the main "test" for this item — no NEW sub-cases needed. Validates the bug doesn't recur.

## 9. Test coverage summary

| Item | Test additions |
|---|---|
| 1 — Tooltips | NEW `test_tooltip_manager.gd` with ~3 sub-cases |
| 2 — Filter picker | NEW `test_item_picker_modal.gd` (or fold into existing) with ~3 sub-cases |
| 3 — Filter status | +1 sub-case in `test_inserter.gd` |
| 4 — E-key hover | +2 sub-cases (new file or fold into `test_building_ui_2.gd`) |
| 5 — Chest silent-merge | Update existing `test_building_ui_2.gd:122` assertion (flip) |

**Runner count:** 35 → ~37 (2 new test files; sub-case additions to existing files don't change runner count). May fold tooltip + picker tests into one combined file if sub-case counts are small.

## 10. Save schema: NO bump (stays v18)

All 5 items are UI-layer changes:
- Item 1: new field on Items.DATA (in-memory only — Items.DATA is constant, never serialized)
- Item 2: new modal class (UI scene)
- Item 3: info_lines text change (display only)
- Item 4: input dispatch logic (no state change)
- Item 5: click handler branch (no state change)

No building state shape changes, no enum entries, no save format touches. Save schema stays at v18.

## 11. Touchpoint inventory

| File | Item | Change |
|---|---|---|
| `scripts/world/items.gd` | 1 | Add `description` field to all 27 DATA entries + `description_of(t)` accessor |
| `scripts/ui/tooltip_manager.gd` | 1 | NEW — TooltipManager Control + hover-tracking logic |
| `scenes/tooltip_manager.tscn` | 1 | NEW — PanelContainer + 2 Labels |
| `scripts/ui/slot_widget.gd` (and/or inventory_grid.gd / panel_renderers) | 1 | Call TooltipManager.start_hover / end_hover from mouse-motion handlers |
| `scripts/main.gd` | 1 + 4 | Instantiate TooltipManager in HUD; modify `_try_interact` for hover-aware |
| `scripts/ui/item_picker_modal.gd` | 2 | NEW — ItemPickerModal PopupPanel |
| `scenes/item_picker_modal.tscn` | 2 | NEW — PopupPanel + ScrollContainer + item buttons |
| `scripts/ui/fast_inserter_panel.gd` | 2 | Wire plain-LMB on filter slot → ItemPickerModal.open |
| `scripts/world/inserter.gd` | 3 | Add filter-status line in `info_lines` + `_source_has_matching_item` helper |
| `scripts/ui/chest_panel.gd` | 5 | Silent-merge branch at line 218 |
| `scripts/tests/test_inserter.gd` | 3 | +1 sub-case |
| `scripts/tests/test_building_ui_2.gd` | 5 | Flip assertion at line 122 |
| `scripts/tests/test_tooltip_manager.gd` | 1 | NEW — ~3 sub-cases |
| `scripts/tests/test_item_picker_modal.gd` | 2 | NEW — ~3 sub-cases |
| `scripts/tests/test_runner.gd` | 1 + 2 | Append new test files to TESTS array |

**Total: 11 production files modified/created + 4 test files modified/created.**

## 12. Implementation order

1. **Threshold audit** — confirm 35/35 PASS pre-change.
2. **Item 1 — Tooltips foundation** (largest single piece; foundation for Item 2's picker showing item descriptions):
   - 1a. Add `description` field to Items.DATA + `description_of(t)` accessor. Author all 27 descriptions in one pass.
   - 1b. NEW TooltipManager script + scene. Hover-tracking + show/hide logic.
   - 1c. Wire into SlotWidget / inventory_grid / panel renderers via mouse-motion handlers.
3. **Item 2 — Filter picker** (uses Item 1's description field for picker rows).
4. **Item 3 — Filter status diagnostic** (small completion piece for inserter panel).
5. **Item 4 — E-key hover dispatch** (standalone).
6. **Item 5 — Chest silent-merge** (standalone, smallest piece).
7. **PAUSE 1: visual smoke** — manual gate. Hover tooltips, click filter picker, observe filter status, E-key on inserter+chest layout, chest deposit-on-same-type.
8. **PAUSE 2: full gameplay** — build a multi-station factory, exercise all 5 items in normal play.
9. **Ship** — PROJECT_LOG entry + NOTES updates (mark Cluster B SHIPPED, update remaining backlog) + tag `session-qol-cluster-b` + push.

**Estimated 9-12 tasks.** Mid-range between Cluster A (27) and Long-Reach (8) in scope.

## 13. Validation criteria at commit

- [ ] Hover any inventory slot for ~500ms → tooltip with item name + description appears
- [ ] Hover an empty slot → no tooltip (no flicker)
- [ ] Move mouse → tooltip follows after 500ms re-hover
- [ ] Click filter slot of fast inserter → ItemPickerModal opens with all 27 items
- [ ] Click an item in picker → filter is set, picker closes
- [ ] Esc or click-outside picker → picker closes, filter unchanged
- [ ] Drop-to-set on filter slot still works (Cluster A behavior preserved)
- [ ] Fast inserter with filter set + empty source → info_lines shows "Status: IDLE (no items match filter)"
- [ ] Fast inserter with filter set + source has matching item → no "no items match" line
- [ ] Player adjacent to inserter + chest, mouse over chest, press E → chest opens
- [ ] Player adjacent to inserter only, mouse anywhere, press E → inserter opens (fallback works)
- [ ] Cursor with N wheat + click chest slot containing same-type wheat → chest gains N wheat, cursor empties (silent merge)
- [ ] Cursor with N wheat + click chest slot containing different-type item → swap (chest has wheat, cursor has the different item)
- [ ] All 5 items work in concert in a normal play session (PAUSE 2)
- [ ] 35 → ~37 tests passing
- [ ] Save schema unchanged at v18
- [ ] Tagged `session-qol-cluster-b`, pushed to origin

## 14. Out-of-scope reminders (anti-scope-creep)

- **No item icons** — tooltips and picker rows are text-only (name + description). Icons are a separate art-pass session.
- **No localization** — English-only descriptions. i18n is a separate framework decision.
- **No tooltip styling** — single dark panel, white text. Theming is future polish.
- **No E-key highlight** — pure dispatch fix, no visual indicator of "what E will open".
- **No filter picker search** — list-based selection only. Fuzzy search / type-to-filter is a future enhancement.
- **No new chest behavior** — only the silent-merge fix; other deposit/withdraw paths unchanged.
- **No tooltip on buildings** — only on item slots. Building Q-inspect info_lines already serves the equivalent purpose for buildings.

## 15. Decision log (for PROJECT_LOG entry at session end)

- **Item 1 approach**: TooltipManager singleton-style module + scene (option a). Single shared widget; per-slot embedded logic rejected as duplicative.
- **Item 1 hover delay**: 500ms.
- **Item 1 description authoring**: 27 entries done in one pass at field-addition time; tone is factual + mechanically informative + mentions recipe chain.
- **Item 2 approach**: NEW ItemPickerModal mirroring QuantityPickerModal pattern; cloned not shared (different UI shape).
- **Item 2 trigger**: plain-LMB on filter slot when cursor is empty. Drop-to-set (existing path) preserved as complement.
- **Item 3 wording**: "Status: IDLE (no items match filter)". Only fires for tiers with filter capability (currently FAST_INSERTER).
- **Item 4 rule**: mouse over adjacent building → open that one; else fallback to current scan. Preserves tap-E-without-aiming UX.
- **Item 5 rule**: silent merge when types match (Factorio convention); swap when types differ.
- **No save schema bump**: all UI-layer changes.
- **Cluster B exhausted after this session**: no remaining items in NOTES.md after the 5 ship.
