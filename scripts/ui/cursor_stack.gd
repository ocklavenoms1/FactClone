class_name CursorStack
extends RefCounted

## Shared cursor stack — the "what the player is currently holding" model.
##
## Replaces inventory_grid.gd's internal _cursor_item_type/_cursor_count fields
## so cursor state is shareable across modals: the player can pick up an item
## in the inventory grid, close it, open a building panel, and drop the item
## into a building slot without losing the held stack mid-flow.
##
## Owned by main.gd; passed by reference to inventory_grid + every BuildingPanel.
## All click handlers read/write the same instance.
##
## Persistence: serialized as part of `player_progression` (additive field, no
## save schema bump). On load, cursor is restored exactly as it was at save time.

# -1 / 0 = empty cursor.
var item_type: int = -1
var count: int = 0

func has_item() -> bool:
	return item_type >= 0 and count > 0

func pick(t: int, c: int) -> void:
	item_type = t
	count = c

func clear() -> void:
	item_type = -1
	count = 0

## Try to return the cursor's stack to the player's inventory. Returns true on
## full return (cursor cleared), false if the inventory couldn't hold all of
## it (cursor still has the remainder).
##
## Used:
##   - When the player explicitly drops the cursor (e.g. right-click in
##     neutral mode with a held stack)
##   - At save time as a sanity check (refused if it can't return — but we
##     now SERIALIZE the cursor instead, so this is no longer the save-time
##     code path)
func return_to_inventory(inv: Inventory) -> bool:
	if not has_item():
		return true
	var added: int = inv.add(item_type, count)
	if added <= 0:
		return false
	count -= added
	if count <= 0:
		clear()
		return true
	return false

# ---------- save/load (additive serialization) ----------

## Serialize to a JSON-clean dict for storage in player_progression.
## Empty cursor → {"item_type": -1, "count": 0}.
func to_dict() -> Dictionary:
	return {"item_type": item_type, "count": count}

## Restore from a dict (typically read from player_progression on load).
## Missing or malformed entries reset to empty.
func from_dict(d: Dictionary) -> void:
	var t: int = int(d.get("item_type", -1))
	var c: int = int(d.get("count", 0))
	if t < 0 or c <= 0:
		clear()
		return
	item_type = t
	count = c
