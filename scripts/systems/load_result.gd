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

var success: bool = false
var error_message: String = ""
var player_progression: Dictionary = {}
