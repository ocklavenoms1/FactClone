class_name Doodads
extends RefCounted

## GROUND DOODADS — Ground Phase 2, Session 1.
##
## Small objects (pebbles, tufts, twigs) scattered on the grass, drawn beneath
## every building and suppressed where buildings sit.
##
## ⚠ THIS IS NOT THE SHADER SCATTER LAYER. `scripts/shaders/ground_grass.gdshader`
## ships untouched and is world-locked inside the shader. Doodads are a second,
## independent layer drawn by `GridWorld._draw_ground_doodads`.
##
## ---------------------------------------------------------------------------
## THE CONTRACT: LAYOUT IS A PURE FUNCTION OF (world_seed, cell)
## ---------------------------------------------------------------------------
## Nothing here is persisted. There is NO save-schema change, no doodad dict,
## no spawn pass at worldgen. Every frame re-derives the same answer from the
## world seed and the tile coordinate, and that is the whole design:
##
##   candidate  = hash says yes           (pure)
##   drawn      = candidate AND allowed_at (pure AND world-state filter)
##
## Suppression is a FILTER OVER the answer, never an INPUT TO it. That is what
## makes demolition restore the doodad that was there rather than roll a new
## one — see `test_doodads.gd` (B3).
##
## The purity is load-bearing and fragile in a specific way: the obvious
## "improvements" (a running counter, a cached previous cell, a time-based
## wobble, a `randf()` for variety) all produce a perfectly plausible ground
## that FLICKERS between two frames which must be identical. Nothing else in
## this project would notice — a shimmering tuft is not an error, not a wrong
## value and not a red test. `test_doodads.gd` group (A) exists for exactly
## that, and it bans the mechanism at source as well as sampling the symptom.
##
## ---------------------------------------------------------------------------
## ONE HASH, AND IT IS THE SHIPPED ONE
## ---------------------------------------------------------------------------
## `WorldGenerator.hash3_unit` — the same hash that places trees. It was made
## public in ONE place for this (see its docstring); the body was NOT copied
## here. Two hashes are two things that can drift apart, and the drift is
## invisible.
##
## ---------------------------------------------------------------------------
## NO SQUASH. NO ROTATION.
## ---------------------------------------------------------------------------
## `plan_squash` is 1.0 for every doodad and is ASSERTED, NEVER APPLIED.
## GROUND_SQUASH 0.86603 is already baked into the Blender render and already
## undone by the anamorphic downsample (art/PIPELINE.md:81-110); the
## calibration disc comes back as a ROUND 32x33 ink bbox. Applying plan_squash
## here would squash a second time — the ruined-read failure, and one nobody
## can catch by looking, because a slightly flattened pebble still reads as a
## pebble. `kind` ("ground" / "upright") carries NO geometry for this code; it
## is informational.
##
## Rotation is forbidden outright: the art is rendered under a fixed 60 degree
## projection, so a rotated doodad is lit from the wrong direction. Variety
## comes from variant selection and a horizontal MIRROR, which preserves the
## projection.
##
## ---------------------------------------------------------------------------
## INTEGER-PIXEL SNAPPING, AND WHY IT LIVES IN THE PURE LAYER
## ---------------------------------------------------------------------------
## A 4-16 px sprite drawn at a fractional world position shimmers as the camera
## moves. NO CAPTURE PAIR CAN SEE THIS: shimmer is motion-only, and any two
## paused frames are identical — which is precisely why the decision is made
## here at design time and written down rather than left to a gate.
##
## So `offset_px` is a `Vector2i` produced by the SELECTION, not a rounding
## applied in the draw call. A draw-call round would be unreachable headless
## (nothing here executes a `_draw` body); a Vector2i in the pure layer is
## asserted by `test_doodads.gd` (A1) as part of the golden literals.
##
## ---------------------------------------------------------------------------
## THE FALLBACK IS LOUD, DELIBERATELY
## ---------------------------------------------------------------------------
## Real sprites live in `art/`, owned by a concurrent Blender session. When one
## is missing or unloadable this module draws a PROCEDURAL PLACEHOLDER through
## the same placement / selection / mirror path — only the final blit differs.
## A silent fallback here would be this codebase's named failure shape
## (NOTES.md, "Protocol: silent compensation"): a procedural pebble and a
## rendered pebble both look like a working ground, so "no art" and "art fine"
## would be indistinguishable by looking.
##
## Therefore: `ensure_loaded()` PRINTS one line per variant naming its mode,
## and `loaded_count` / `placeholder_count` / `variant_mode()` / `load_notes`
## are queryable so a test and a human gate can ASSERT the mode instead of
## inferring it.

const MANIFEST_PATH: String = "res://art/doodads.json"
const SPRITE_DIR: String = "res://art/sprites/doodads"

## The variant table is the GAME's decision about which doodads exist, and it
## is deliberately NOT read from the manifest's ordering. If it were, art
## reordering `doodads.json` would silently re-bind variant 0 and re-roll the
## species of every doodad in every world anyone has ever seen. It is a copy of
## the manifest's `status == "real"` set, so — per NOTES.md, "read it, don't
## copy it; if you must copy it, assert the copy" — `test_doodads.gd` (D2)
## asserts it against the manifest.
## ROSTER, and it is a DELIBERATE EDIT every time. Updated 2026-08-28 when the
## art session replaced the confetti set (grass_tuft / weed_clump /
## fallen_twig) with three ground-cover patches, keeping pebble_cluster.
## test_doodads.gd (D2) reddened on the mismatch, which is the assertion
## doing its job: an automatic re-bind to whatever the manifest lists would
## silently re-roll every existing world's layout. Order IS the variant
## index, so reordering this array is also a layout change; it follows the
## manifest's own declaration order for the status=="real" entries.
## VARIANT_COUNT stayed 4 across this change, so no hash roll moved and
## every golden literal in the suite still holds.
const VARIANT_NAMES: Array = ["ground_cover_patch_A", "ground_cover_patch_B", "ground_cover_patch_C", "pebble_cluster"]
## The divisor in the variant roll. Changing it re-rolls every doodad
## everywhere; it is a constant and not `VARIANT_NAMES.size()` so that the
## re-roll cannot happen as a side effect of adding art.
const VARIANT_COUNT: int = 4

## Per-tile candidate probability.
##
## The brief asked for "~1 per 6-10 tiles". READ AS AREA: one candidate per
## 6-10 tiles OF AREA, i.e. a per-tile probability near 1/8. The other reading
## — one per 6-10-tile CELL, i.e. one per 36-100 tiles of area — is 4-8x
## SPARSER, and the two are easy to confuse in review because both sound like
## "one per eight tiles". 0.125 is the area reading. Measured over a fixed
## 40x40 rectangle at seed 42 it yields 197 candidates = 0.123125/tile, one per
## 8.12 tiles; that count is a LITERAL in `test_doodads.gd` (C), so a density
## change shows up as a number moving rather than as a vibe.
const CANDIDATE_PROBABILITY: float = 0.125

## Seed offsets. Distinct from every `WorldGenerator.SEED_OFFSET_*` (which
## occupy 8 and 100-231, plus FOREST_BASE/LAKE_BASE + i) so a doodad never
## correlates with a tree, a lake or a region boundary.
const SEED_OFFSET_PRESENCE: int = 300
const SEED_OFFSET_VARIANT: int = 301
const SEED_OFFSET_MIRROR: int = 302
const SEED_OFFSET_OFFSET_X: int = 303
const SEED_OFFSET_OFFSET_Y: int = 304

## Sub-tile placement. The doodad's ground-contact point lands at
## tile_origin + offset_px, inset from every tile edge so a 16 px sprite
## centred there cannot cross into the neighbour and produce a doodad that
## looks like it belongs to the wrong tile (which would then not be suppressed
## when THAT tile is built on).
const TILE_INSET_PX: int = 4
const OFFSET_SPAN_PX: int = 24          # 4..27 inclusive inside a 32 px tile

## ASSERTED, NEVER APPLIED. See the header.
const PLAN_SQUASH_REQUIRED: float = 1.0

## Placeholder ink. Chosen against the shipped ground green #2E3A26 (relative
## luminance 0.0375) to sit at contrast 1.22, under the manifest's 1.25 cap —
## the doodad-side reach of standing invariant 2 (the ground is the darkest
## thing on screen). #3E4636.
const PLACEHOLDER_INK: Color = Color(0.243137, 0.274510, 0.211765, 1.0)

## Procedural placeholder geometry, in LOCAL SPRITE PIXELS, one entry per
## variant index. `anchor` is the ground-contact point, matching the real
## sidecars' `anchor_mode: "ground_centre"`.
##
## ⚠ EVERY MARK IS AT LEAST 4 px IN BOTH AXES. Standing invariant 1 (NOTES.md,
## designer 2026-08-28) forbids ANY ground feature under 4 px, and it is about
## the FEATURE, not the bounding box: "a 2-px-wide blade is a violation even
## when the doodad's overall size is legal". The ground does not downsample, so
## sub-4-px marks put energy in a frequency band the LANCZOS-resampled
## buildings structurally cannot hold, and the eye reads the difference as the
## buildings being pasted onto the ground rather than standing on it. That is
## why these are blocky bars and not hairline blades.
##
## Index 3 is strongly ASYMMETRIC about its vertical axis — the
## side branch sits on one side only. It is the witness for the mirror bit: a
## broken mirror on a symmetric shape looks exactly like a working one.
const PLACEHOLDER_SPECS: Array = [
	{   # 0 — two upright bars of unequal height (asymmetric)
		"size": Vector2i(9, 10), "anchor": Vector2i(4, 9),
		"rects": [[0, 2, 4, 8], [5, 0, 4, 10]],
	},
	{   # 1 pebble_cluster — two low stones, offset (asymmetric)
		"size": Vector2i(10, 8), "anchor": Vector2i(5, 7),
		"rects": [[0, 3, 5, 5], [6, 0, 4, 5]],
	},
	{   # 2 — a broad low mass with one raised leaf (asymmetric)
		"size": Vector2i(12, 9), "anchor": Vector2i(6, 8),
		"rects": [[0, 4, 12, 5], [1, 0, 4, 4]],
	},
	{   # 3 — a stick with ONE side branch (the mirror witness)
		"size": Vector2i(14, 6), "anchor": Vector2i(7, 5),
		"rects": [[0, 2, 14, 4], [9, 0, 4, 4]],
	},
]

# ---------------------------------------------------------------------------
# LOAD STATE. Queryable on purpose — see "THE FALLBACK IS LOUD" above.
# ---------------------------------------------------------------------------
static var loaded_count: int = 0          # variants backed by a real sprite
static var placeholder_count: int = 0     # variants drawn procedurally
static var manifest_present: bool = false
static var load_notes: Array = []         # Array[String], one per variant
static var _loaded: bool = false
static var _variants: Array = []          # per index: { mode, texture, size, anchor, plan_squash }

# ===========================================================================
# SELECTION — the pure layer. Nothing in here may read the world, the clock,
# a frame counter, an RNG, or anything evaluated for another cell.
# ===========================================================================

## The RAW per-cell answer, BEFORE suppression. Pure function of
## (world_seed, cell).
##
## `variant`, `mirrored` and `offset_px` are rolled for EVERY cell, present or
## not. That is deliberate: it costs three hashes on a cell that draws nothing,
## and it buys the property that a cell's identity does not depend on whether
## it happened to be a candidate — so a doodad suppressed by a building and
## then un-suppressed by its demolition is THE SAME DOODAD, not a re-roll.
static func selection_at(world_seed: int, cell: Vector2i) -> Dictionary:
	var present: bool = WorldGenerator.hash3_unit(world_seed + SEED_OFFSET_PRESENCE, cell.x, cell.y) < CANDIDATE_PROBABILITY
	var variant: int = int(WorldGenerator.hash3_unit(world_seed + SEED_OFFSET_VARIANT, cell.x, cell.y) * float(VARIANT_COUNT))
	if variant > VARIANT_COUNT - 1:
		variant = VARIANT_COUNT - 1     # hash3_unit's range is [0, 1]; guard the closed end
	var mirrored: bool = WorldGenerator.hash3_unit(world_seed + SEED_OFFSET_MIRROR, cell.x, cell.y) < 0.5
	# INTEGER by construction, not by rounding at draw time. See the header.
	var ox: int = TILE_INSET_PX + int(WorldGenerator.hash3_unit(world_seed + SEED_OFFSET_OFFSET_X, cell.x, cell.y) * float(OFFSET_SPAN_PX))
	var oy: int = TILE_INSET_PX + int(WorldGenerator.hash3_unit(world_seed + SEED_OFFSET_OFFSET_Y, cell.x, cell.y) * float(OFFSET_SPAN_PX))
	return {
		"present": present,
		"variant": variant,
		"mirrored": mirrored,
		"offset_px": Vector2i(ox, oy),
	}

# ===========================================================================
# SUPPRESSION — ONE predicate, sharing placement's own footprint source.
# ===========================================================================

## May a doodad be drawn on `pos`?
##
## ⚠ THE BUILDING TEST IS `has_building_at`, WHICH ASKS `occupied`. That is the
## dictionary `place_building` writes via `_footprint_cells`, and the same
## source `can_place_building` validates against — so every cell of a 2x2
## smelter answers true, not just its anchor. Asking `buildings` instead (which
## is keyed by ANCHOR) is the tuft-under-smelter bug: it passes the anchor case
## and leaves a doodad growing through the middle of the machine. Re-deriving
## the footprint here is the same defect one step further along. There is one
## occupancy rule and this asks it.
##
## `world` is typed `Node2D` rather than `GridWorld` following this file's
## siblings (`Buildings.tick_one`), which keeps the class-name cycle out of
## the parser.
static func allowed_at(world: Node2D, pos: Vector2i) -> bool:
	if world == null:
		return false
	if world.has_building_at(pos):
		return false
	if world.base_at(pos) != Terrain.Base.GRASS:
		return false
	if world.overlay_at(pos) != Terrain.Overlay.NONE:
		return false
	var t: Tile = world.tiles.get(pos)
	if t != null and t.has_resource_node():
		return false
	return true

## Candidate-then-filter, in one call. The renderer asks THIS and never
## re-derives either half — a renderer that re-derived the selection would
## drift from what a query says is there, and the divergence is invisible
## until somebody wonders why a pebble is under a chest.
static func doodad_at(world: Node2D, pos: Vector2i) -> Dictionary:
	if world == null:
		return { "present": false, "variant": 0, "mirrored": false, "offset_px": Vector2i.ZERO }
	var s: Dictionary = selection_at(int(world.world_seed), pos)
	if bool(s["present"]) and not allowed_at(world, pos):
		s["present"] = false
	return s

# ===========================================================================
# ASSET LOADING — and its loud fallback.
# ===========================================================================

static func reset() -> void:
	_loaded = false
	_variants = []
	loaded_count = 0
	placeholder_count = 0
	manifest_present = false
	load_notes = []

## Idempotent. Called from the draw pass, so it must stay cheap after the
## first call.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_variants = []
	loaded_count = 0
	placeholder_count = 0
	load_notes = []

	var manifest: Dictionary = _read_manifest()
	manifest_present = not manifest.is_empty()

	for i in range(VARIANT_COUNT):
		var name: String = String(VARIANT_NAMES[i]) if i < VARIANT_NAMES.size() else "variant_%d" % i
		var entry: Dictionary = _load_variant(i, name, manifest)
		_variants.append(entry)
		if String(entry["mode"]) == "sprite":
			loaded_count += 1
		else:
			placeholder_count += 1
		load_notes.append(String(entry["note"]))
		# ONE LINE PER VARIANT, ALWAYS. The mode is stated, never inferred.
		print("[doodads] %s: %s — %s" % [name, String(entry["mode"]).to_upper(), String(entry["note"])])
	print("[doodads] %d sprite, %d placeholder (of %d variants); manifest %s"
		% [loaded_count, placeholder_count, VARIANT_COUNT,
			"present" if manifest_present else "ABSENT at " + MANIFEST_PATH])

static func _read_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var reader := JSON.new()
	if reader.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK:
		return {}
	if typeof(reader.data) != TYPE_DICTIONARY:
		return {}
	return reader.data

static func _manifest_entry(manifest: Dictionary, name: String) -> Dictionary:
	for e in manifest.get("doodads", []):
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("name", "")) == name:
			return e
	return {}

## Returns { mode: "sprite"|"placeholder", texture, size, anchor, plan_squash, note }.
## Every refusal path is a NAMED note, never a bare null — the note is what a
## human reads when the ground looks wrong.
static func _load_variant(index: int, name: String, manifest: Dictionary) -> Dictionary:
	var ph: Dictionary = _placeholder_entry(index, "")

	if manifest.is_empty():
		ph["note"] = "no manifest at %s" % MANIFEST_PATH
		return ph

	var m: Dictionary = _manifest_entry(manifest, name)
	if m.is_empty():
		ph["note"] = "'%s' is not in the manifest" % name
		return ph
	# CALIBRATION ENTRIES NEVER REACH PLACEMENT. `_calib_disc` is a 32 px unit
	# disc that exists to MEASURE the plan aspect ratio; in game it would be an
	# enormous grey coin lying on the grass.
	if str(m.get("status", "")) != "real":
		ph["note"] = "'%s' has status '%s', not 'real'" % [name, str(m.get("status", ""))]
		return ph

	var jpath: String = "%s/%s.json" % [SPRITE_DIR, name]
	var ppath: String = "%s/%s.png" % [SPRITE_DIR, name]
	if not FileAccess.file_exists(jpath) or not FileAccess.file_exists(ppath):
		ph["note"] = "sidecar or PNG missing (%s / %s)" % [jpath, ppath]
		return ph
	var sr := JSON.new()
	if sr.parse(FileAccess.get_file_as_string(jpath)) != OK or typeof(sr.data) != TYPE_DICTIONARY:
		ph["note"] = "%s is unparseable" % jpath
		return ph
	var sj: Dictionary = sr.data

	# ASSERTED, NEVER APPLIED. A non-1.0 value means the art pipeline's squash
	# accounting changed, and the correct response is to STOP and re-read
	# art/PIPELINE.md — not to start multiplying by it here.
	var squash: float = float(sj.get("plan_squash", -1.0))
	if not is_equal_approx(squash, PLAN_SQUASH_REQUIRED):
		ph["note"] = "%s has plan_squash %s, not %s — asserted, never applied (double-squash guard)" % [jpath, str(squash), str(PLAN_SQUASH_REQUIRED)]
		return ph

	var sp: Array = sj.get("sprite_px", [])
	if sp.size() != 2:
		ph["note"] = "%s has no 2-element sprite_px" % jpath
		return ph
	var want: Vector2i = Vector2i(int(sp[0]), int(sp[1]))
	var img := Image.new()
	if img.load(ppath) != OK:
		ph["note"] = "%s failed to load" % ppath
		return ph
	if img.get_size() != want:
		ph["note"] = "%s is %dx%d on disk but %s says %dx%d" % [ppath, img.get_size().x, img.get_size().y, jpath, want.x, want.y]
		return ph

	var ap: Array = sj.get("anchor_px", [])
	var anchor: Vector2 = Vector2(float(want.x) * 0.5, float(want.y))
	if ap.size() == 2:
		anchor = Vector2(float(ap[0]), float(ap[1]))
	return {
		"mode": "sprite",
		"texture": ImageTexture.create_from_image(img),
		"size": want,
		"anchor": anchor,
		"plan_squash": squash,
		"note": "%dx%d from %s" % [want.x, want.y, ppath],
	}

static func _placeholder_entry(index: int, note: String) -> Dictionary:
	var spec: Dictionary = PLACEHOLDER_SPECS[index]
	return {
		"mode": "placeholder",
		"texture": null,
		"size": spec["size"],
		"anchor": Vector2(spec["anchor"]),
		"plan_squash": PLAN_SQUASH_REQUIRED,
		"note": note,
	}

## "sprite" or "placeholder". Queryable so a test and a human gate can ASSERT
## the mode rather than infer it from a plausible-looking frame.
static func variant_mode(variant: int) -> String:
	ensure_loaded()
	if variant < 0 or variant >= _variants.size():
		return ""
	return String(_variants[variant]["mode"])

static func placeholder_spec(variant: int) -> Dictionary:
	if variant < 0 or variant >= PLACEHOLDER_SPECS.size():
		return { "size": Vector2i.ZERO, "anchor": Vector2i.ZERO, "rects": [] }
	return PLACEHOLDER_SPECS[variant]

# ===========================================================================
# DRAW. Unreachable headless (nothing here executes a `_draw` body) — every
# testable decision has been moved OUT of this function on purpose: the
# integer snap lives in `selection_at`, the mode lives in `variant_mode`, the
# geometry lives in `PLACEHOLDER_SPECS`, and the pass ORDER is pinned against
# grid_world.gd's source by `test_doodads.gd` (E). What is left here is the
# blit, and only the blit.
# ===========================================================================

## `at` is the doodad's GROUND-CONTACT point in world units, already integral.
## The sprite is placed by subtracting its anchor, exactly as
## `SpriteLibrary.draw_top_left` does for buildings — one convention for where
## art meets the ground.
##
## Mirroring is a horizontal flip and NOTHING ELSE. No rotation: the art is
## rendered under a fixed 60 degree projection, so a rotated doodad is lit from
## the wrong direction. No Y scale: see the header on plan_squash.
static func draw_one(canvas: CanvasItem, at: Vector2, variant: int, mirrored: bool) -> void:
	ensure_loaded()
	if canvas == null or variant < 0 or variant >= _variants.size():
		return
	var v: Dictionary = _variants[variant]
	var size: Vector2i = v["size"]
	var anchor: Vector2 = v["anchor"]
	# Integral by construction: `at` and the rounded anchor are both integers,
	# so the blit lands on whole pixels at 1x zoom.
	var top_left: Vector2 = Vector2(round(at.x - anchor.x), round(at.y - anchor.y))

	if String(v["mode"]) == "sprite":
		var tex: Texture2D = v["texture"]
		if tex == null:
			return
		# Negative width flips horizontally; Godot's draw_texture_rect accepts
		# a negative-size Rect2 for exactly this.
		var w: float = float(size.x)
		if mirrored:
			canvas.draw_texture_rect(tex, Rect2(top_left + Vector2(w, 0.0), Vector2(-w, float(size.y))), false)
		else:
			canvas.draw_texture_rect(tex, Rect2(top_left, Vector2(w, float(size.y))), false)
		return

	# Procedural placeholder — SAME placement, selection and mirror path; only
	# the blit differs.
	for r in PLACEHOLDER_SPECS[variant]["rects"]:
		var rx: int = int(r[0])
		var ry: int = int(r[1])
		var rw: int = int(r[2])
		var rh: int = int(r[3])
		if mirrored:
			rx = size.x - (rx + rw)
		canvas.draw_rect(Rect2(top_left + Vector2(float(rx), float(ry)), Vector2(float(rw), float(rh))), PLACEHOLDER_INK, true)
