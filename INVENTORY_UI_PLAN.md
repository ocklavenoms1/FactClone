# Inventory UI session — slot grid + two-way chest transfer

Future-session brief, parallel to `SESSION_E_PLAN.md`. Captured at the close of Session E final after a vocabulary unstick: the "bag-cap" mechanic shipped today expands the player's inventory slot count, but the inventory panel still aggregates by item type — so bag rewards are mostly invisible and the player has no way to manually deposit items into chests. Both gaps share the same UI subsystem and land together.

**Current state at hand-off:**
- Tag: `session-e-final` (commit `ee53cb0`) — bag-cap mechanic shipped.
- Save: v10. 9 tests passing.
- Bridge UX in place: inventory panel header shows `Bags: X/5 consumed | Slots: A/B used` so the bag reward is at least numerically visible. **This line gets retired when the grid ships** — see retirement trigger below.

---

## Goal

Replace the aggregated inventory panel with a Factorio-style slot grid that visualizes the per-slot reality of the existing inventory storage, and add two-way item transfer between player and chests so manual deposit becomes possible.

The underlying storage is already correct (slot-by-slot, max_stack-enforced per `Inventory.add()`'s two-pass logic). What's missing is the UI that surfaces it and the input flow that lets the player move items between containers.

## Why it matters

- **Bag-cap reward is invisible today.** Player consumes a bag → +4 slots → aggregated display shows the same item rows. Header line `Slots: A/B used` is the bridge but is purely numeric. Real visibility requires seeing the empty slots.
- **Player can only drain, not deposit.** `Buildings.drain_into_player` is one-directional. There is no code path or input action for "put items from inventory INTO chest." A player who picks up bread from a harvester output and wants to leave it in storage has no UI for that — the only way bread enters a chest today is via belt push from a Processor. **Real gameplay limit.**
- **The two problems share infrastructure.** Both want a slot grid, click/drag interactions, and a way to map clicks to inventory operations. Building one without the other duplicates the UI work later.

## Full scope (the six bullets)

1. **Slot grid visualization.** Player inventory rendered as an N-cell grid where each cell shows its item swatch + stack count, with empty slots distinct from filled. Grid size adapts to `Inventory.capacity` (16 base + 4×bags_consumed, range 16..36). Replaces the aggregated `inventory_panel.gd` rendering.

2. **Toggle key.** `I` (or similar — pick during design) opens / closes the main inventory grid. The grid is its own modal panel, not the persistent always-visible aggregate panel of today.

3. **Click pick / place.** Click an inventory slot to pick up its stack onto the cursor; click an empty slot to drop it. Click a partial-stack to top it up where stacking allows. Standard inventory UX.

4. **Chest grid.** When player presses `E` adjacent to a chest, open BOTH grids side-by-side (chest's bag + player's inventory). Click-to-transfer between them. Replaces the current "drain only" `E` behavior with a richer two-grid view.

5. **Shift-click for "transfer all of this stack" / "transfer all matching stacks."** Standard Factorio convention. From a chest, shift-click an item → all of that item type moves to player. From player, shift-click → all moves to chest.

6. **Mouse-drag for moving stacks.** Drag a stack from one slot to another for repositioning or partial transfers (drag-with-modifier for split). Lower priority than the above; could be a follow-up sub-slice if the session runs long.

## Not in scope

- No new gameplay mechanics, items, or buildings. Pure UI / input layer over existing systems.
- No change to the `Inventory` class storage shape. Slot-by-slot is already correct; only `slots_used()` is the new accessor and it stays.
- No changes to the save schema. Inventory state already persists per-slot.
- No automatic-sort, search, filter, or other inventory-management features beyond what the six bullets specify. Defer to a polish session if the grid lands and feels incomplete.
- The `inventory_panel.gd` aggregate display can either be **retired** (replaced by the grid as the primary view) or **kept** (as a quick-glance summary in the corner alongside the openable grid). Pick during design.

## Locked design decisions (post design pass)

### Modal vs. persistent
**Modal, key `I`, closes with `I` or `Esc`.** Modal-only — the world is the primary view; persistent grid eats real estate when not actively managing items. Aggregate panel in top-right stays for at-a-glance monitoring.

### Chest E behavior
**E adjacent to a chest auto-opens paired view (player grid + chest grid side-by-side). E or Esc closes both. Shift-click is the only transfer mechanism — no "Take All" button.** Hedging with both flows would mean half the design fails to land. Commits to Factorio convention exactly.

**Edge case:** if player presses E with cursor stack already held, **place cursor stack into chest's first empty slot first**, then open paired view. Avoids the "open paired view mid-pickup with cursor full" confusion.

### Layout
**Fixed 4-column grid, +1 row per bag consumed.**
- 16 slots = 4×4 (base, 0 bags consumed)
- 20 slots = 5×4 (1 bag)
- 24 slots = 6×4 (2 bags)
- 28 slots = 7×4 (3 bags)
- 32 slots = 8×4 (4 bags)
- 36 slots = 9×4 (5 bags, cap)

Each bag grants exactly +4 slots = exactly one new row. Bag consumption is **visually obvious** — new row appears at the bottom of the grid. Slot size 48px.

### Slot rendering
- **Empty:** dark fill (slightly lighter than panel bg), 1px gray border. Reuses hotbar's `SLOT_BG` / `SLOT_BORDER` palette.
- **Filled:** centered colored swatch (32px inside the 48px slot frame, leaves visible margin). Stack count overlay in bottom-right with white text + 1px black shadow.
- **Hovered:** yellow border (`SLOT_BORDER_SELECTED`). **Tooltip** near cursor: `ItemName: count / max_stack` (e.g., `Grain: 47 / 100`). v1 includes tooltip.

### Click interactions

**v1 (must-haves):**

| Action | Cursor empty | Cursor full |
|---|---|---|
| **Left-click filled slot** | Pick up entire stack to cursor. Slot becomes empty. | Slot has same item type → top-up to max_stack; remainder stays on cursor. Different item type → swap. |
| **Left-click empty slot** | No-op. | Place entire cursor stack into slot. |
| **Shift-click filled slot** | If chest grid open → transfer entire stack to other grid. If chest grid NOT open → no-op (defer reorder behavior to v2). | No-op. |
| **Press `I` / `Esc` / click outside** | Close grid. | **Auto-return cursor** — see below. |

**v2 (deferred):** right-click for half-stack pickup; drag-and-drop; ctrl-click for "transfer one"; selected-source highlight on cursor pickup.

### Auto-return on close — locked semantics

**Find first empty slot, place cursor stack there, toast `ItemName ×N returned to slot M`. If no empty slot exists, refuse close — toast `Place cursor stack before closing inventory.`**

The naive "return to original slot" fails when the original slot was modified during pickup (player swapped something into it). Three outcomes possible: lose the stack (unacceptable), find first empty slot (predictable IF announced), or refuse close (acceptable as last resort). First empty + toast + last-resort refuse = predictable enough because the toast always announces what happened.

### Cursor stack model

Lives on `InventoryGrid` controller as a single `ItemStack` field. Renders on a top CanvasLayer with `mouse_filter = IGNORE` so it doesn't intercept clicks. Drawn as a 32×32 swatch + count, follows mouse position each frame.

### Hotbar relationship
**Stays separate.** Hotbar = building/terrain placement. Inventory grid = held items. Different purposes; different keyboard mappings. Future "assign item to hotbar slot for quick placement" feature noted but not in v1.

### Drag-and-drop
**Pick-up-and-place v1; drag deferred.** Pick-up is universal; drag adds gesture detection complexity. Revisit if pick-up feels clunky in playtest.

### Aggregate panel — keep, partial trim
- **Keep** the aggregate panel in the top-right corner.
- **Drop** the `Slots: A/B used` line (slot count is implicit in the grid view).
- **Keep** the `Bags: X/5 consumed` line (lifetime cap is not visible in the grid).
- **Keep** the aggregated item rows for at-a-glance "do I have grain" without opening the modal.

### Chest internal storage — Path A (view adapter)
Chest's `state.bag = [[item_type, count], ...]` stays as-is. The chest grid renderer reads the bag and presents it as a 24-slot view (TOTAL_CAPACITY 2400 / 100 max_stack ≈ 24 slots equivalent). Each bag entry → one or more slots (split if exceeds max_stack). On commit, update the chest bag.

No schema bump. v10 saves stay valid. If players ever complain about slot-arrangement-not-persisting-in-chests, migrate later.

### Modal interaction with game state
While the inventory grid is open:
- Game tick continues (factory keeps running).
- Mouse clicks on world disabled (modal dim overlay intercepts).
- Player movement (WASD) disabled — `player.gd` gates on `inventory_grid.visible`.
- Hotbar / building placement input disabled — `main.gd` gates the relevant input handlers on `inventory_grid.visible`.
- `I` and `Esc` always handled (to close).

## Retirement trigger

When the slot grid ships, **strike the `Slots: A/B used` line from `inventory_panel.gd`'s header** (currently lives near the `Bags: X/5 consumed` line). Slot occupancy becomes implicit in the grid view — the bridge line is no longer needed.

The `Bags: X/5 consumed` line itself is debatable — the grid visually shows total slot count, but doesn't surface the lifetime cap (5 bags max). Probably keep the bags line; remove only the slots line.

`Inventory.slots_used()` stays — it's a generic primitive, not coupled to the bridge UX.

## Sizing as a session

Probably **1-2 sessions** depending on how clean the click/drag interaction layer is. Bullet 6 (mouse drag) is a natural sub-slice that could land in a follow-up if scope feels tight.

The session's design pass should answer the four open questions above before any code lands. UI work is high-friction to retrofit; getting modal-vs-persistent and trigger-mapping right up front is worth the planning time.

## Status before this session starts

- Bag-cap mechanic + bridge slots line shipped.
- Player inventory storage is correct (slot-by-slot).
- Chest interaction is one-directional (drain only).
- All 9 tests pass.
- No technical blockers to starting this session whenever scheduled.
