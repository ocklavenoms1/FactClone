class_name Building
extends RefCounted

## A single building instance. Pure data — no behavior.
## Logic is dispatched by Buildings.tick_one() / draw_one() based on `type`.
##
## `state` is a free-form per-type dictionary. Each building type owns
## its own keys (e.g. Planter uses `state.growth`).

var type: int = 0
var anchor: Vector2i = Vector2i.ZERO
var state: Dictionary = {}

func _init(t: int = 0, pos: Vector2i = Vector2i.ZERO, initial_state: Dictionary = {}) -> void:
	type = t
	anchor = pos
	state = initial_state.duplicate(true)

func to_dict() -> Dictionary:
	return {
		"t": type,
		"x": anchor.x,
		"y": anchor.y,
		"s": state,
	}

## Rehydrate a building from `to_dict()` output, or NULL when `d` cannot be read
## as one. Callers must check — `SaveSystem.load_game` skips and counts.
##
## Returning null instead of trusting `d["s"]`. `_init` takes `initial_state` as
## a typed `Dictionary`, so a save whose `"s"` is a String or a number does not
## produce a wrong building — it raises a runtime type error ON THE CALL, which
## aborts `from_dict`, returns null anyway, and then aborts `load_game` at the
## caller's `b.anchor`. The caller gets null instead of a LoadResult, `main.gd`
## dereferences it, and the boot bricks on every subsequent run until the file is
## deleted by hand. That is audit #11's failure mode reached through a door
## #11's fix did not cover: `_first_mistyped_array_field` validates the
## `buildings` CONTAINER, and `load_game` checks each entry is a Dictionary, but
## neither looks inside one.
##
## Checked explicitly rather than left to abort. Deleting the check does NOT
## redden the suite — `load_game`'s `if b == null` guard still catches it, since
## an aborted `-> Building` returns null anyway — but it does put one SCRIPT
## ERROR back in the log (measured: 54 passed, SCRIPT ERROR 0 → 1) for a shape
## the game handles deliberately. The two guards are independent: removing
## `load_game`'s instead reddens sub-case 9 of test_load_malformed_save.gd with
## the null-result failure. Keep both — this one keeps the null return
## INTENTIONAL rather than a side effect of how GDScript unwinds a type error.
static func from_dict(d: Dictionary) -> Building:
	var initial_state = d.get("s", {})
	if not (initial_state is Dictionary):
		push_warning("Building.from_dict: entry has an unreadable 's' state (%s) — dropping the building" % str(initial_state))
		return null
	return Building.new(
		int(d.get("t", 0)),
		Vector2i(int(d.get("x", 0)), int(d.get("y", 0))),
		initial_state
	)
