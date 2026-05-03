class_name ResourceNodes
extends RefCounted

## Resource node types — natural deposits placed by world generation.
##
## Stored as int on Tile.resource_node (a single int, not behavior). Per-tile
## state (richness for ore, growth for trees) lives in a parallel sparse
## dictionary on GridWorld (`resource_state: Dictionary[Vector2i, Dictionary]`).
## Most tiles with a resource_node have NO entry in resource_state — they're
## at "default" state (full richness for ore, fully grown for trees).
##
## Type identity is independent of behavior. Renewable vs finite is a
## *property* of the type, queried via is_renewable() — code branches on that
## when the behavior diverges (harvest depletes ore richness; tree harvest
## starts a regrowth timer).
##
## DO NOT REORDER values; saves store these as ints. Append new types only.

enum Type {
	NONE   = 0,
	TREE   = 1,    # renewable
	STONE  = 2,
	COAL   = 3,
	IRON   = 4,
	COPPER = 5,
	CLAY   = 6,
	# Reserved 7-15 for future biome-specific deposits (sand, salt, etc.)
}

const DEFAULT: int = Type.NONE

## Resources that regrow / refill over time. Today only TREE; future types
## (e.g. moss patches, kelp) would join here. Ore deposits are finite and
## NOT included.
const RENEWABLE: Array[int] = [Type.TREE]

static func is_renewable(t: int) -> bool:
	return t in RENEWABLE

static func is_ore(t: int) -> bool:
	return t == Type.STONE or t == Type.COAL or t == Type.IRON or t == Type.COPPER or t == Type.CLAY

static func name_of(t: int) -> String:
	match t:
		Type.NONE:
			return "(none)"
		Type.TREE:
			return "Tree"
		Type.STONE:
			return "Stone"
		Type.COAL:
			return "Coal"
		Type.IRON:
			return "Iron"
		Type.COPPER:
			return "Copper"
		Type.CLAY:
			return "Clay"
	return "(unknown)"

## Display color for the deposit. Used by GridWorld._draw to render a tile's
## resource_node. Trees use their own draw path (canopy + trunk); these
## colors are used for the ore-style filled-rect rendering.
##
## Palette per Q11 design pass:
##   stone  — neutral cool gray
##   iron   — gray with rust tint
##   copper — gray with verdigris blue
##   coal   — near black with cool sheen
##   clay   — warm orange-brown
##   tree   — used by tree-draw path (not as fill rect)
static func color_of(t: int) -> Color:
	match t:
		Type.STONE:
			return Color(0.55, 0.55, 0.58)
		Type.IRON:
			return Color(0.62, 0.45, 0.38)
		Type.COPPER:
			return Color(0.45, 0.55, 0.65)
		Type.COAL:
			return Color(0.18, 0.18, 0.22)
		Type.CLAY:
			return Color(0.68, 0.50, 0.36)
		Type.TREE:
			return Color(0.20, 0.45, 0.20)   # canopy color (trunk handled separately)
	return Color(1.0, 0.0, 1.0)              # magenta = "missing draw" signal
