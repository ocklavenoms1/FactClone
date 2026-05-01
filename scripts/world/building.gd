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

static func from_dict(d: Dictionary) -> Building:
	return Building.new(
		int(d.get("t", 0)),
		Vector2i(int(d.get("x", 0)), int(d.get("y", 0))),
		d.get("s", {})
	)
