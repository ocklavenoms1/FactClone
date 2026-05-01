class_name Terrain
extends RefCounted

## Terrain is split into two layers:
##   Base    — natural substrate. Either GRASS (default) or WATER (lakes,
##             rivers; spawned by world-gen, not the player). Base is NOT
##             player-paintable.
##   Overlay — what the player places on top of grass. NONE / SOIL_TILLED
##             / PATH / STONE. Overlays only go on grass-base tiles.
##
## Rendering: draw the base color first, then the overlay if not NONE.
## Sparse storage: a tile only exists in GridWorld.tiles when base != GRASS
## or overlay != NONE. The grass background canvas covers the rest.
##
## Removal: RMB clears the overlay back to NONE. Base is never directly
## removed — it's natural terrain. RMB on a bare-grass or water tile is
## a silent no-op (nothing to remove).

enum Base {
	GRASS,
	WATER,
}

enum Overlay {
	NONE,
	SOIL_TILLED,
	PATH,
	STONE,
}

const DEFAULT_BASE: int = Base.GRASS
const DEFAULT_OVERLAY: int = Overlay.NONE

const BASE_DATA: Dictionary = {
	Base.GRASS: { "name": "Grass", "color": Color(0.22, 0.42, 0.22) },
	Base.WATER: { "name": "Water", "color": Color(0.20, 0.40, 0.60) },
}

const OVERLAY_DATA: Dictionary = {
	Overlay.NONE:        { "name": "(none)",      "color": Color(0, 0, 0, 0),         "buildable": false },
	Overlay.SOIL_TILLED: { "name": "Tilled Soil", "color": Color(0.45, 0.32, 0.20),   "buildable": true  },
	Overlay.PATH:        { "name": "Path",        "color": Color(0.55, 0.50, 0.40),   "buildable": false },
	Overlay.STONE:       { "name": "Stone",       "color": Color(0.50, 0.50, 0.55),   "buildable": true  },
}

## Overlay placement ladder. For each overlay, the list of OVERLAYS it can
## be painted on top of. (Base must always be GRASS — overlays never go
## on water.) Same-type painting is idempotent and always allowed.
const OVERLAY_PLACEABLE_ON: Dictionary = {
	Overlay.SOIL_TILLED: [Overlay.NONE],
	Overlay.PATH:        [Overlay.NONE, Overlay.SOIL_TILLED],
	Overlay.STONE:       [Overlay.NONE, Overlay.SOIL_TILLED, Overlay.PATH],
}

## Hotbar order. WATER is intentionally absent — it's natural terrain.
const HOTBAR_ORDER: Array = [Overlay.SOIL_TILLED, Overlay.PATH, Overlay.STONE]

# ---------- accessors ----------

static func base_name(b: int) -> String:
	return BASE_DATA[b]["name"]

static func base_color(b: int) -> Color:
	return BASE_DATA[b]["color"]

static func overlay_name(o: int) -> String:
	return OVERLAY_DATA[o]["name"]

static func overlay_color(o: int) -> Color:
	return OVERLAY_DATA[o]["color"]

static func is_overlay_buildable(o: int) -> bool:
	return OVERLAY_DATA[o]["buildable"]

## Player-facing name for what a tile "is": the overlay if present, else the base.
static func effective_name(b: int, o: int) -> String:
	return overlay_name(o) if o != Overlay.NONE else base_name(b)

# ---------- placement rules ----------

## True iff `overlay` can be painted on a tile with the given base + current overlay.
static func can_place_overlay(overlay: int, base: int, current_overlay: int) -> bool:
	if base != Base.GRASS:
		return false  # overlays never go on water (or any future non-grass base)
	if overlay == Overlay.NONE:
		return false  # use clear path, not paint
	if overlay == current_overlay:
		return true   # idempotent drag-paint
	var allowed: Array = OVERLAY_PLACEABLE_ON.get(overlay, [])
	return current_overlay in allowed
