class_name Tile
extends RefCounted

## A single tile of the world. Stored sparsely in GridWorld.tiles —
## any position not in the dict is implicitly default grass.
##
## Tile holds *terrain only*. Buildings, crops, items live in
## sibling dictionaries on GridWorld so we can iterate them
## independently without scanning every tile.

var terrain: int = Terrain.Type.GRASS

# Reserved fields for upcoming systems. Keeping them here documents intent
# and gives save/load a stable schema target.
# var moisture: float = 0.0       # 0..1, drives crop growth
# var soil_health: float = 1.0    # 0..1, depletes with monoculture
# var temperature: float = 20.0   # celsius, ambient + machine heat

func _init(t: int = Terrain.Type.GRASS) -> void:
	terrain = t

func to_dict() -> Dictionary:
	return { "t": terrain }

static func from_dict(d: Dictionary) -> Tile:
	return Tile.new(int(d.get("t", Terrain.Type.GRASS)))
