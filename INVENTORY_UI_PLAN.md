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

## Open questions for the session's design pass

- **Modal vs. persistent grid.** Factorio uses both: a persistent hotbar/quickbar always visible AND a modal main inventory toggled by E. Should Stewardship match that two-tier model, or pick one? Tradeoffs:
  - Persistent grid eats screen real estate but always shows state.
  - Modal-only is cleaner but adds a key-press friction.
  - Hybrid (current aggregate panel stays as glance-summary, grid opens on demand) is reasonable.
- **Does chest E auto-open both grids, or are they separate triggers?** Options:
  - E always opens both grids (chest + player) when adjacent to a chest.
  - E drains as today; a different trigger (Shift+E, click on chest) opens the two-grid view.
  - Auto-open is more discoverable; separate trigger preserves current "tap E to grab" muscle memory.
- **How does slot grid layout scale at 16, 20, 24, 28, 32, 36 slots?** Options:
  - Fixed columns (e.g., 8 wide), rows grow as slot count grows. Simple, predictable.
  - Fixed grid size (e.g., always 6×6 = 36 slots), unused slots show as "locked" until earned. Communicates progression visually.
  - Aspect-ratio adaptive (4 wide for 16, 5 wide for 20-25, etc.). More complex.
- **Cursor item rendering.** When the player has picked up a stack and is moving it between slots, where does it render? Options: follow cursor as a floating swatch, or live in a "hand" slot above the grid. Factorio uses follow-cursor.
- **Hotbar / quickbar interaction.** Today's hotbar holds buildings + terrain overlays, not items. Once items are clickable, does the hotbar gain item slots too (Factorio-style place-from-hotbar)? Possibly out of scope for this first pass — capture as a follow-up.

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
