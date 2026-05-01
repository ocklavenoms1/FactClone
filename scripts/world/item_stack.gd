class_name ItemStack
extends RefCounted

## A single inventory slot. item_type < 0 means empty.

var item_type: int = -1
var count: int = 0

func _init(t: int = -1, c: int = 0) -> void:
	item_type = t
	count = c

func is_empty() -> bool:
	return item_type < 0 or count <= 0

func clear() -> void:
	item_type = -1
	count = 0
