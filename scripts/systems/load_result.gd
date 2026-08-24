class_name LoadResult
extends RefCounted

## Result of `SaveSystem.load_game`. Carries success/failure + any data
## the caller needs to apply to runtime state after the load.
##
## Future load-time fields (achievements unlocked, score, etc.) become new
## members here, NOT new static vars on SaveSystem. Static load state
## accumulates badly; this class is the explicit container.
##
## Conventions:
## - `success == false` AND `error_message == ""` ⇒ "no save file" (silent
##   case). Caller should treat as "fresh start" not "load failed."
## - `success == false` AND `error_message != ""` ⇒ load attempted and
##   failed. Caller should surface error_message to the user.
## - `success == true` ⇒ all fields below were populated from the save.
##   Empty-but-present `player_progression` ({}) is acceptable for forward-
##   compatibility — caller should keep its own defaults if the dict is
##   missing keys.
## - `used_backup` is meaningful ONLY when `success == true`; it is never set
##   on a failure path. It cannot be signalled through `error_message`,
##   because recovering from the backup is a SUCCESS and the convention above
##   reads a non-empty `error_message` as failure. That is why it is its own
##   field rather than the note the audit's fix text suggested.

var success: bool = false
var error_message: String = ""
var player_progression: Dictionary = {}

## True when `load_game` could not use the primary save file and read the
## `.bak` sidecar instead (audit finding #12 — the primary was absent because
## a crash landed between save_game's two renames, or unparseable because an
## older non-atomic write was interrupted). The load succeeded; the caller
## should tell the player that the newest save was lost so they know the state
## they are looking at is one save behind.
var used_backup: bool = false

## How many entries `load_game` could not read and dropped (audit finding #11).
## Counts a malformed row in any of the save's collections, plus the `"player"`
## field when it is too short or not an Array at all — in that case the player
## keeps the default spawn, which is lost data the player would otherwise read
## as the game teleporting them.
##
## Set on the SUCCESS path only, exactly like `used_backup` above, and for the
## same reason: it describes a load that happened. A failed load reports through
## `error_message` and this stays 0.
##
## Surfaced rather than merely counted. Skipping is the right response to one
## corrupt row — it costs the player that row instead of the whole world — but a
## load that silently drops forty buildings is a worse failure than one that
## says so, because the player has no way to tell it from the game deleting
## their base. Both `main.gd` load sites append the count to their toast.
##
## WHAT IT DOES NOT MEASURE. This is a count of ROWS, and rows are not a common
## unit. One `buildings` row is one building; one `player_inventory` row is a
## whole stack, up to that item's max_stack; one `player` field is the spawn
## position; one `tile_soil_modifications` row is a single tile. So `2` can mean
## "two tiles" or "a chest and 100 planks". The number is an INCIDENCE count —
## how many pieces of the save could not be read — and says nothing about volume.
##
## KEPT SCALAR, DELIBERATELY, and the reasoning is worth recording because the
## obvious alternative is a per-collection Dictionary so the toast could name
## which data was lost. Two things decided it. First, the case that most wants
## naming does not reach this field at all: a collection that is present but
## MISTYPED (`"buildings": {...}`) is not skipped row-by-row, it fails the load
## outright through `_first_mistyped_array_field` with the field named in
## `error_message` — so "your whole base is gone" is already reported as a named
## failure, not as a count of 1. Second, what remains is genuinely per-row damage,
## where a per-collection breakdown would render as "1 buildings, 1 tiles" and
## still not tell the player how much was in them. The volume question is not
## answerable from a corrupt row at all — the data needed to size it is the data
## that could not be read.
##
## So the limit is handled where it is actually read: `main.gd._skipped_suffix`
## tells the player to go and look rather than implying the number is a measure.
## If a future collection makes per-collection counts genuinely actionable, this
## is the field to widen — and that paragraph is the argument to overturn.
var skipped_entries: int = 0
