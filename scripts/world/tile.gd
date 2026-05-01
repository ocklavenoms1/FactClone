class_name Tile
extends RefCounted

## A single tile of the world. Stored sparsely in GridWorld.tiles —
## any position not in the dict is implicitly base=GRASS, overlay=NONE.
##
## Two-layer terrain model:
##   base    — natural substrate (GRASS, WATER). World-gen sets this.
##   overlay — player-placed top layer (NONE, SOIL_TILLED, PATH, STONE).
##
## Buildings, crops, items live in sibling dictionaries on GridWorld so
## they can be iterated independently of terrain.

var base: int = Terrain.Base.GRASS
var overlay: int = Terrain.Overlay.NONE

# Reserved for upcoming systems (Session B+):
# var moisture: float = 0.0
# var soil_health: float = 1.0
# var temperature: float = 20.0

func _init(b: int = Terrain.Base.GRASS, o: int = Terrain.Overlay.NONE) -> void:
	base = b
	overlay = o

func has_overlay() -> bool:
	return overlay != Terrain.Overlay.NONE

func is_water() -> bool:
	return base == Terrain.Base.WATER

func to_dict() -> Dictionary:
	return { "b": base, "o": overlay }

static func from_dict(d: Dictionary) -> Tile:
	return Tile.new(int(d.get("b", Terrain.Base.GRASS)), int(d.get("o", Terrain.Overlay.NONE)))
