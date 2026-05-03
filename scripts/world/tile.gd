class_name Tile
extends RefCounted

## A single tile of the world. Stored sparsely in GridWorld.tiles —
## any position not in the dict is implicitly base=GRASS, overlay=NONE,
## resource_node=NONE.
##
## Three-layer model:
##   base          — natural substrate (GRASS, WATER). World-gen sets this.
##   overlay       — player-placed top layer (NONE, SOIL_TILLED, PATH, STONE).
##   resource_node — natural deposit (stone, ore, wood). World-gen sets this.
##                   Forward-prep as of Session B; no buildings interact yet.
##                   See NOTES.md for the mining roadmap.
##
## Buildings, crops, items live in sibling dictionaries on GridWorld so
## they can be iterated independently of terrain.

var base: int = Terrain.Base.GRASS
var overlay: int = Terrain.Overlay.NONE
var resource_node: int = ResourceNodes.DEFAULT

# Reserved for upcoming systems (Session B+):
# var moisture: float = 0.0
# var soil_health: float = 1.0
# var temperature: float = 20.0

func _init(b: int = Terrain.Base.GRASS, o: int = Terrain.Overlay.NONE, r: int = ResourceNodes.DEFAULT) -> void:
	base = b
	overlay = o
	resource_node = r

func has_overlay() -> bool:
	return overlay != Terrain.Overlay.NONE

func is_water() -> bool:
	return base == Terrain.Base.WATER

func has_resource_node() -> bool:
	return resource_node != ResourceNodes.Type.NONE

## Player can walk through this tile? Generic passability check; today only
## water blocks, but extensible for future cliffs / walls / structures.
## Resource_node tiles (deposits, trees) stay passable — player walks
## through ore patches and forests freely; they're "stuff on the ground"
## not "obstacles."
func is_passable() -> bool:
	return base != Terrain.Base.WATER

func to_dict() -> Dictionary:
	return { "b": base, "o": overlay, "r": resource_node }

static func from_dict(d: Dictionary) -> Tile:
	return Tile.new(
		int(d.get("b", Terrain.Base.GRASS)),
		int(d.get("o", Terrain.Overlay.NONE)),
		int(d.get("r", ResourceNodes.DEFAULT)),
	)
