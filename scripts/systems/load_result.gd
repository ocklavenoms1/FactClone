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
var skipped_entries: int = 0
