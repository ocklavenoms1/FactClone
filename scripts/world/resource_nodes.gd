class_name ResourceNodes
extends RefCounted

## Resource node types — natural mineable deposits placed by world-gen.
##
## Forward-prep only as of Session B. No buildings interact with these
## yet; the Tile struct stores `resource_node: int` so future world-gen
## can populate them without bumping save schema again.
##
## Target session for full implementation: G or H. See NOTES.md for the
## design plan (mining → raw items → processing → consumable materials).
##
## Add a new resource node type by appending to the Type enum (never
## reorder; saves store these as ints).

enum Type {
	NONE,
	# STONE_DEPOSIT, ORE_DEPOSIT, WOOD_GROVE — populated when mining lands.
}

const DEFAULT: int = Type.NONE

static func name_of(t: int) -> String:
	match t:
		Type.NONE:
			return "(none)"
	return "(unknown)"
