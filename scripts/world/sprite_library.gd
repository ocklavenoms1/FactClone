class_name SpriteLibrary
extends RefCounted

## Flagged sprite render path for buildings that have real art (session-art-probe-1).
##
## PURPOSE: this is a CONTRACT PROBE, not the shipping renderer. Three assets
## exist (chest, smelter, power_pole). The point is to find out whether the
## anchor convention, the per-state file layout, the animation clock and the
## failure story survive contact with the engine — at asset three, where the
## cost of being wrong is one session, instead of at asset twenty.
##
## OFF BY DEFAULT. `SpriteLibrary.enabled` is the single toggle, and the dev
## console's `sprites on|off` flips it. With it false every building — including
## the three — goes through `Buildings.draw_one()` exactly as before; the added
## per-building work at the `grid_world.gd:1709` building loop is one local bool
## init, two reads of this static, and three branches. Measured, not asserted:
## six flag-off frames — three at 42f6758, three with this file in place — are
## byte-identical PNGs (md5 4a2f646cf8fe8f65cb987697f5e38fd7, 0 of 921600
## pixels differing). `Buildings.draw_one()` is untouched.
##
## ---------------------------------------------------------------------------
## HOW THE PNGs ARE LOADED, AND WHY IT IS NOT `load()`
## ---------------------------------------------------------------------------
## `art/sprites/*.png` have NO `.import` sidecars — `.godot/imported/` contains
## only `icon.svg`. Measured 2026-08-24:
##
##     ResourceLoader.exists("res://art/sprites/chest.png")  -> false
##     FileAccess.file_exists(same)                          -> true
##     load(same)  -> ERROR: No loader found for resource
##     Image.load(same) -> OK, size (32, 64)
##
## Generating the sidecars means running the editor, which WRITES into `art/`.
## `art/` is owned by a concurrent Blender session and is read-only to this
## code path, so the import route is unavailable. `Image.load()` +
## `ImageTexture.create_from_image()` reads the raw bytes and writes nothing.
##
## CONSEQUENCE FOR SHIPPING, recorded here so it is not rediscovered later:
## `Image.load()` on a `res://` path works in editor and debug builds; in an
## exported build unimported files are not packed unless added to the export
## filter. Whoever ships this must either (a) let Godot import the PNGs, which
## means `art/` stops being write-protected, or (b) add `art/sprites/*` to the
## export include filter. This probe does not decide that.
##
## ---------------------------------------------------------------------------
## THE JSON CONTRACT, AS VERIFIED AGAINST ALL THREE ASSETS
## ---------------------------------------------------------------------------
##   cell_tiles  [w, h]  w = FOOTPRINT WIDTH in tiles, h = SPRITE HEIGHT in tiles
##   sprite_px   [w, h]  always cell_tiles * 32
##   anchor_px   [x, y]  offset from sprite top-left to the FOOTPRINT's
##                       bottom-centre
##   footprint_tiles     float, duplicates cell_tiles[0] (width only)
##   masters             array; each entry has `state` (null | "idle" |
##                       "smelting") and `sprite` (a res:// path)
##
## Footprint is read as: WIDTH from `cell_tiles[0]`, cross-checked against
## `footprint_tiles` and against `Buildings.footprint_of(type).x`; DEPTH from
## `Buildings.footprint_of(type).y` ONLY, because no JSON key carries depth.
## `cell_tiles[1]` is sprite height, not footprint depth — reading it as depth
## would place the smelter 32 px too low (3 tiles vs its real 2).
##
## Shadows carry their own `<asset>_shadow.json` with their own `anchor_px`.
## Measured: for all three it equals the body's anchor exactly, and the shadow
## JSON says so in its own `blend` field ("draw UNDER the body sprite, same
## anchor"). This code READS the shadow's own anchor rather than inheriting the
## body's, and VALIDATES that the two agree — inheriting would make a future
## shadow with a genuine offset silently wrong, and the file already carries
## the field, so there is nothing to gain by ignoring it.
##
## `smelter_glow.png` has NO JSON. It is 64x96, identical to the body. Rule:
## the glow inherits the body's geometry, and that is validated on load.

const SPRITE_DIR: String = "res://art/sprites"

## Pixels per tile the art is authored at. GridWorld.TILE_SIZE happens to be
## the same number today; they are different concepts and are kept separate so
## a tile-size change scales the art instead of breaking the anchor maths.
const SPRITE_PX_PER_TILE: int = 32

# ---------------------------------------------------------------------------
# THE ZERO-PADDING RULE
# ---------------------------------------------------------------------------
#
# DECIDED 2026-08-24 (NOTES.md, art-probe finding 3). `anchor_px` is
# `[sprite_w/2, sprite_h]` on every shipped asset, so the anchor names the
# sprite's bottom EDGE. If the artwork stops short of that edge, "sprite bottom
# edge" and "where the object meets the ground" are different rows and nothing
# in the JSON says by how much. At three assets that is invisible. At twenty it
# is per-asset vertical jitter with every sprite "correctly placed" by the
# contract and sitting at a different apparent height.
#
# The rejected alternative was a `ground_contact_px` schema field: a
# hand-maintained number no test can verify, which is the count-drift shape this
# project keeps re-encountering. Instead the constraint is enforced here, where
# the loader can check it: THE BOTTOM ROW MUST CARRY ARTWORK.
#
# ⚠ ALL THREE CURRENT ASSETS FAIL THIS AND WILL NOT LOAD until art re-exports
# them. That is the point. Being wrong is loud: the manifest line reports
# `loaded=0 failed=3`, `report()` push_errors, and any declared building that
# fell back gets a magenta cross in the frame. The sprite path is off by
# default, so nothing user-facing changes.
#
# ---------------------------------------------------------------------------
# WHY A THRESHOLD AND NOT "NON-ZERO ALPHA"
# ---------------------------------------------------------------------------
# The rule as first written was "at least one non-zero alpha pixel". MEASURED
# against the real assets, that rule GRANDFATHERS THE SMELTER: both smelter
# masters carry a single stray pixel of alpha 3/255 in their bottom row — about
# 1% opacity, which shifts a composited channel by one 8-bit step and is
# invisible. A strict-zero test passes an asset that is, to the eye, padded.
# That is the same absence-indistinguishable-from-success shape the rule exists
# to close, reappearing inside the rule.
#
# So the rule takes a threshold, and the threshold is measured rather than
# picked. Per-row maximum alpha over the bottom rows of the three bodies:
#
#   chest.png       … 255, 255, 255, 255, 130,   0,   4,   0, 0, 0, 0, 0
#   smelter_idle    … 255, 255, 255, 255, 255, 255, 255,  57, 0, 3
#   power_pole.png  … 255, 233,  18,   0,   1,   0,   0,   0, 0, 0, 0, 0
#
# There is a clean gap. Renderer anti-aliasing noise lands at 1, 3 and 4; real
# silhouette lands at 18, 57, 130, 233, 255. Nothing at all falls between 5 and
# 17. A threshold of 8 sits in that gap, so it separates artwork from noise
# without being sensitive to where exactly it is put.
const BOTTOM_ROW_MIN_ALPHA: float = 8.0 / 255.0

# ---------- the flag ----------

## Single toggle. False = every building renders through Buildings.draw_one().
static var enabled: bool = false

## When the sprite path is on and a DECLARED building fell back to the vector
## renderer, paint an unmissable marker over it. See the silent-compensation
## note on `draw_fallback_marker`.
static var mark_fallbacks: bool = true

# ---------- glow pulse ----------

const GLOW_ALPHA_MIN: float = 0.20
const GLOW_ALPHA_MAX: float = 0.85

## Pulses per smelt cycle. 2 means the glow breathes twice per item smelted,
## so the animation is legible without being frantic at default tick rate.
const GLOW_PULSES_PER_CYCLE: float = 2.0

# ---------- fallback marker ----------

const FALLBACK_MARKER: Color = Color(1.0, 0.0, 1.0, 0.85)
const FALLBACK_MARKER_WIDTH: float = 3.0

# ---------- state ----------

static var _entries: Dictionary = {}       # base_name -> entry Dictionary
static var _failures: Array = []           # Array[String], human-readable
static var _notes: Array = []              # Array[String], non-fatal
static var _loaded: bool = false
static var _declared: Dictionary = {}      # Buildings.Type -> base_name

## Buildings that are DECLARED to have art. This table, not the contents of
## `art/sprites`, is what the manifest audit compares against: "how many did we
## intend to load" is the only number that can detect a missing one.
static func declared() -> Dictionary:
	if _declared.is_empty():
		_declared = {
			Buildings.Type.CHEST: "chest",
			Buildings.Type.SMELTER: "smelter",
			Buildings.Type.POWER_POLE: "power_pole",
		}
	return _declared

# ---------------------------------------------------------------------------
# anchor maths — pure, and deliberately testable without a renderer
# ---------------------------------------------------------------------------

## Sprite top-left in world pixels. THE GENERAL FORM:
##
##     top_left = footprint_bottom_centre - anchor_px * scale
##
## where footprint_bottom_centre = world_pos + (fp_w * ts / 2, fp_h * ts).
##
## WHY THE GENERAL FORM WHEN THE DEGENERATE ONE WOULD DO: at all three shipped
## assets `anchor_px == [sprite_w/2, sprite_h]` AND `sprite_w == fp_w * 32`
## (32=1x32, 64=2x32, 32=1x32). The footprint's bottom-centre and the SPRITE's
## bottom-centre therefore coincide, and a renderer implementing "sprite
## bottom-centre" produces pixel-identical output on every one of them. The
## convention is not confirmed by these assets — it is UNTESTED by them.
## `draw_top_left_sprite_centred` below exists only so the test suite can show
## the two agree here and disagree on a sprite wider than its footprint.
static func draw_top_left(world_pos: Vector2, footprint_tiles: Vector2i, anchor_px: Vector2, tile_size: int) -> Vector2:
	var scale: float = float(tile_size) / float(SPRITE_PX_PER_TILE)
	var bottom_centre: Vector2 = world_pos + Vector2(
		float(footprint_tiles.x) * float(tile_size) * 0.5,
		float(footprint_tiles.y) * float(tile_size),
	)
	return bottom_centre - anchor_px * scale

## The DEGENERATE reading of the same contract: "put the sprite's own
## bottom-centre on the footprint's bottom-centre". NOT used by the renderer.
## It exists so `test_sprite_anchor.gd` can prove the two readings are
## indistinguishable at the three shipped assets and distinguishable at a
## synthetic one. Deleting it should redden that test.
static func draw_top_left_sprite_centred(world_pos: Vector2, footprint_tiles: Vector2i, sprite_px: Vector2i, tile_size: int) -> Vector2:
	var scale: float = float(tile_size) / float(SPRITE_PX_PER_TILE)
	var bottom_centre: Vector2 = world_pos + Vector2(
		float(footprint_tiles.x) * float(tile_size) * 0.5,
		float(footprint_tiles.y) * float(tile_size),
	)
	return bottom_centre - Vector2(float(sprite_px.x) * 0.5, float(sprite_px.y)) * scale

## Pulse alpha from a 0..1 cycle phase. Cosine so it eases at both ends
## instead of sawtoothing. Pure function; pinned by test.
static func glow_alpha(cycle_phase: float) -> float:
	var p: float = clampf(cycle_phase, 0.0, 1.0)
	var t: float = 0.5 * (1.0 - cos(TAU * GLOW_PULSES_PER_CYCLE * p))
	return GLOW_ALPHA_MIN + (GLOW_ALPHA_MAX - GLOW_ALPHA_MIN) * t

# ---------------------------------------------------------------------------
# loading + validation
# ---------------------------------------------------------------------------

static func reset() -> void:
	_entries.clear()
	_failures.clear()
	_notes.clear()
	_loaded = false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_entries.clear()
	_failures.clear()
	_notes.clear()
	for t in declared().keys():
		var base: String = declared()[t]
		var res: Dictionary = load_asset(SPRITE_DIR, base, Buildings.footprint_of(t).x)
		if bool(res["ok"]):
			_entries[base] = res["entry"]
			for n in res["notes"]:
				_notes.append("%s: %s" % [base, n])
		else:
			_failures.append("%s: %s" % [base, res["error"]])
	report()

static func failures() -> Array:
	return _failures.duplicate()

static func entry_names() -> Array:
	return _entries.keys()

static func has_entry(base: String) -> bool:
	return _entries.has(base)

static func entry(base: String):
	return _entries.get(base, null)

## Load and validate one asset from an arbitrary directory. Directory-agnostic
## on purpose: the test suite feeds it synthetic assets written to `user://`,
## which is the only way to exercise the malformed cases without touching the
## read-only `art/` tree.
##
## Returns { ok: bool, error: String, notes: Array[String], entry: Dictionary }.
## `error` is written to be actionable on its own — it names the file and the
## two numbers that disagree, because the person reading it will be reading it
## in a console line at asset nineteen, not here.
static func load_asset(dir_path: String, base: String, expected_footprint_width: int) -> Dictionary:
	var notes: Array = []
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "notes": notes, "entry": {}}

	var json_path: String = "%s/%s.json" % [dir_path, base]
	if not FileAccess.file_exists(json_path):
		return fail.call("JSON missing at %s" % json_path)
	var text: String = FileAccess.get_file_as_string(json_path)
	# JSON instance rather than the JSON.parse_string static: the static logs
	# an engine-level ERROR line on bad input, which would put a red herring in
	# every suite log that exercises the malformed-JSON fixtures. The instance
	# API returns the code and carries the line number and message, which are
	# what a person debugging a broken export actually needs.
	var reader := JSON.new()
	var perr: int = reader.parse(text)
	if perr != OK:
		return fail.call("JSON at %s is unparseable: line %d, %s"
			% [json_path, reader.get_error_line(), reader.get_error_message()])
	var parsed = reader.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return fail.call("JSON at %s is a %s, expected an object" % [json_path, type_string(typeof(parsed))])
	var j: Dictionary = parsed

	# --- required keys and shapes ---
	for k in ["cell_tiles", "sprite_px", "anchor_px", "masters"]:
		if not j.has(k):
			return fail.call("%s.json has no '%s' key" % [base, k])
	if typeof(j["cell_tiles"]) != TYPE_ARRAY or (j["cell_tiles"] as Array).size() != 2:
		return fail.call("%s.json cell_tiles must be a 2-element array" % base)
	if typeof(j["sprite_px"]) != TYPE_ARRAY or (j["sprite_px"] as Array).size() != 2:
		return fail.call("%s.json sprite_px must be a 2-element array" % base)
	if typeof(j["anchor_px"]) != TYPE_ARRAY or (j["anchor_px"] as Array).size() != 2:
		return fail.call("%s.json anchor_px must be a 2-element array" % base)
	if typeof(j["masters"]) != TYPE_ARRAY or (j["masters"] as Array).is_empty():
		return fail.call("%s.json masters must be a non-empty array" % base)

	var cell_tiles := Vector2i(int(j["cell_tiles"][0]), int(j["cell_tiles"][1]))
	var sprite_px := Vector2i(int(j["sprite_px"][0]), int(j["sprite_px"][1]))
	var anchor_px := Vector2(float(j["anchor_px"][0]), float(j["anchor_px"][1]))

	# --- cell_tiles consistent with sprite_px ---
	var derived: Vector2i = cell_tiles * SPRITE_PX_PER_TILE
	if derived != sprite_px:
		return fail.call("%s.json cell_tiles %s x %d = %s, but sprite_px says %s"
			% [base, cell_tiles, SPRITE_PX_PER_TILE, derived, sprite_px])

	# --- footprint width agrees with the game's own table ---
	if cell_tiles.x != expected_footprint_width:
		return fail.call("%s.json cell_tiles[0] = %d footprint tiles, but Buildings.footprint_of says %d"
			% [base, cell_tiles.x, expected_footprint_width])
	if j.has("footprint_tiles") and int(round(float(j["footprint_tiles"]))) != cell_tiles.x:
		return fail.call("%s.json footprint_tiles = %s disagrees with cell_tiles[0] = %d"
			% [base, j["footprint_tiles"], cell_tiles.x])

	# --- anchor inside the sprite ---
	if anchor_px.x < 0.0 or anchor_px.y < 0.0 or anchor_px.x > float(sprite_px.x) or anchor_px.y > float(sprite_px.y):
		return fail.call("%s.json anchor_px %s is outside the sprite bounds %s"
			% [base, anchor_px, sprite_px])

	# --- body masters ---
	var states: Dictionary = {}
	for m in (j["masters"] as Array):
		if typeof(m) != TYPE_DICTIONARY:
			return fail.call("%s.json has a masters entry that is not an object" % base)
		var md: Dictionary = m
		if not md.has("sprite"):
			return fail.call("%s.json masters entry '%s' has no 'sprite' key" % [base, str(md.get("tag", "?"))])
		var spath: String = str(md["sprite"])
		if not spath.begins_with("res://") and not spath.begins_with("user://"):
			spath = "res://" + spath
		if not FileAccess.file_exists(spath):
			return fail.call("%s.json masters entry '%s' names %s, which does not exist"
				% [base, str(md.get("tag", "?")), spath])
		var tex_res: Dictionary = _load_texture(spath, sprite_px)
		if not bool(tex_res["ok"]):
			return fail.call("%s: %s" % [base, tex_res["error"]])
		var skey: String = "" if md.get("state", null) == null else str(md["state"])
		states[skey] = tex_res["texture"]
	if states.is_empty():
		return fail.call("%s.json produced no usable body sprite" % base)

	# --- shadow (optional layer, own JSON, own anchor) ---
	var shadow_tex: ImageTexture = null
	var shadow_anchor: Vector2 = anchor_px
	var shadow_json: String = "%s/%s_shadow.json" % [dir_path, base]
	var shadow_png: String = "%s/%s_shadow.png" % [dir_path, base]
	if FileAccess.file_exists(shadow_json) or FileAccess.file_exists(shadow_png):
		if not FileAccess.file_exists(shadow_png):
			return fail.call("%s has a shadow JSON but no %s_shadow.png" % [base, base])
		if not FileAccess.file_exists(shadow_json):
			return fail.call("%s has %s_shadow.png but no shadow JSON to anchor it" % [base, base])
		var sreader := JSON.new()
		if sreader.parse(FileAccess.get_file_as_string(shadow_json)) != OK:
			return fail.call("%s_shadow.json is unparseable: line %d, %s"
				% [base, sreader.get_error_line(), sreader.get_error_message()])
		if typeof(sreader.data) != TYPE_DICTIONARY:
			return fail.call("%s_shadow.json is not an object" % base)
		var sj: Dictionary = sreader.data
		if not sj.has("anchor_px") or typeof(sj["anchor_px"]) != TYPE_ARRAY or (sj["anchor_px"] as Array).size() != 2:
			return fail.call("%s_shadow.json has no usable anchor_px" % base)
		shadow_anchor = Vector2(float(sj["anchor_px"][0]), float(sj["anchor_px"][1]))
		if shadow_anchor != anchor_px:
			# Not silently accepted. The shipped contract says the shadow shares
			# the body's anchor; a divergence is either a real design change or
			# a pipeline bug, and both need a human.
			return fail.call("%s_shadow.json anchor_px %s differs from the body's %s"
				% [base, shadow_anchor, anchor_px])
		var stex: Dictionary = _load_texture(shadow_png, sprite_px)
		if not bool(stex["ok"]):
			return fail.call("%s shadow: %s" % [base, stex["error"]])
		shadow_tex = stex["texture"]
	else:
		notes.append("no shadow layer")

	# --- glow (optional, no JSON of its own; inherits body geometry) ---
	var glow_tex: ImageTexture = null
	var glow_png: String = "%s/%s_glow.png" % [dir_path, base]
	if FileAccess.file_exists(glow_png):
		# No ground-contact requirement — see `_load_texture`. A glow is an
		# additive overlay on the hot part of a machine, not a silhouette.
		var gtex: Dictionary = _load_texture(glow_png, sprite_px, false)
		if not bool(gtex["ok"]):
			return fail.call("%s glow: %s" % [base, gtex["error"]])
		glow_tex = gtex["texture"]

	return {
		"ok": true,
		"error": "",
		"notes": notes,
		"entry": {
			"name": base,
			"cell_tiles": cell_tiles,
			"sprite_px": sprite_px,
			"anchor_px": anchor_px,
			"footprint_width_tiles": cell_tiles.x,
			"states": states,
			"shadow": shadow_tex,
			"shadow_anchor_px": shadow_anchor,
			"glow": glow_tex,
		},
	}

## Load one PNG and check its real pixel size against what the JSON claims.
## Split out because "sprite_px disagreeing with the actual PNG" has to be
## checked on EVERY layer — body, shadow, glow — not just the first.
##
## `require_ground_contact` applies the zero-padding rule (see
## BOTTOM_ROW_MIN_ALPHA above). TRUE for body masters and for shadows: both are
## ground-plane silhouettes, and the shadow shares the body's anchor by
## contract, so if the body is flush the shadow must be too. FALSE for the glow,
## and that is not an exemption granted to make things pass — a glow is an
## additive overlay over the hot part of a machine, not a silhouette.
## `smelter_glow.png` is legitimately empty for its bottom 12 rows because the
## forge mouth is not on the floor.
static func _load_texture(path: String, expect_px: Vector2i, require_ground_contact: bool = true) -> Dictionary:
	var img := Image.new()
	var err: int = img.load(path)
	if err != OK:
		return {"ok": false, "error": "%s failed to load (Image.load err %d)" % [path, err], "texture": null}
	var got := img.get_size()
	if got != expect_px:
		return {"ok": false, "error": "%s is %dx%d on disk but the JSON says sprite_px %dx%d"
			% [path, got.x, got.y, expect_px.x, expect_px.y], "texture": null}
	if require_ground_contact:
		var empty: int = empty_bottom_rows(img)
		if empty > 0:
			return {"ok": false, "error": "%s has %d fully transparent bottom row%s (bottom row's strongest pixel is alpha %d of 255; at least one pixel at %d or more is required). anchor_px.y is the sprite's bottom edge AND its ground-contact row, so the silhouette must reach the bottom edge — re-export with no transparent bottom padding."
				% [path, empty, "" if empty == 1 else "s", int(round(_row_max_alpha(img, got.y - 1) * 255.0)), int(round(BOTTOM_ROW_MIN_ALPHA * 255.0))], "texture": null}
	return {"ok": true, "error": "", "texture": ImageTexture.create_from_image(img)}

## How many rows at the bottom of `img` carry no pixel at or above
## BOTTOM_ROW_MIN_ALPHA. 0 means the artwork reaches the bottom edge, which is
## the whole of the rule; the larger number is carried only so the failure
## message can say HOW far off the export is rather than just that it is off.
##
## Public so `test_sprite_manifest.gd` can report the per-asset counts without
## re-implementing the scan — one definition of "empty", so the rule and the
## number in the message cannot drift apart.
static func empty_bottom_rows(img: Image) -> int:
	var h: int = img.get_size().y
	var n: int = 0
	for y in range(h - 1, -1, -1):
		if _row_max_alpha(img, y) >= BOTTOM_ROW_MIN_ALPHA:
			return n
		n += 1
	return n

static func _row_max_alpha(img: Image, y: int) -> float:
	var w: int = img.get_size().x
	var best: float = 0.0
	for x in range(w):
		var a: float = img.get_pixel(x, y).a
		if a > best:
			best = a
	return best

# ---------------------------------------------------------------------------
# the LOUD guard
# ---------------------------------------------------------------------------
#
# Read NOTES.md "Protocol: silent compensation". The sprite path is a textbook
# instance: a sprite that fails to load falls back to draw_one(), the building
# still renders, and a broken asset therefore LOOKS LIKE A WORKING GAME. At
# three assets someone is watching. At nineteen it means half the art quietly
# is not rendering and nothing looks wrong.
#
# Four layers, because each one covers a case the others miss:
#
#   1. `report()` — a manifest line printed the first time the library loads,
#      comparing DECLARED against LOADED. Catches "one asset vanished" even
#      when nobody is looking at that particular building.
#   2. push_error + printerr per failure, naming the file and the two numbers
#      that disagree. Catches it in a log after the fact.
#   3. `draw_fallback_marker` — magenta cross-hatch over any declared building
#      that fell back, while the flag is on. Catches it IN THE FRAME, which is
#      the artefact actually being looked at during art work.
#   4. `test_sprite_manifest.gd` — reddens the suite. The only layer that
#      catches it when nobody runs the game at all.
#
# Layer 4 deliberately couples the suite to `art/`, which a concurrent Blender
# session owns. That is the intended trade: an asset broken at source SHOULD
# stop the build. The failure message names the file, so a mid-write collision
# is diagnosable in one line rather than mysterious.

static func manifest_report_lines() -> Array:
	var lines: Array = []
	var d: Dictionary = declared()
	if not _loaded:
		# Distinguished from "loaded 0 of 3", which is the alarm state. Nothing
		# is loaded because nothing asked — the flag is off and the library
		# does no I/O at all in that configuration.
		lines.append("[sprites] dir=%s declared=%d NOT LOADED (flag=%s, nothing has requested a sprite yet)"
			% [SPRITE_DIR, d.size(), str(enabled)])
		return lines
	lines.append("[sprites] dir=%s declared=%d loaded=%d failed=%d flag=%s"
		% [SPRITE_DIR, d.size(), _entries.size(), _failures.size(), str(enabled)])
	for f in _failures:
		lines.append("[sprites] FAILED %s" % f)
	for n in _notes:
		lines.append("[sprites] note %s" % n)
	# Informational: JSONs on disk that no declared asset claims. Not a
	# failure — art/sprites also holds calibration objects and abandoned
	# probes (_calib_floor, smelter_rot, *_remap, *_nomatnorm).
	var claimed: Dictionary = {}
	for base in d.values():
		claimed[base + ".json"] = true
		claimed[base + "_shadow.json"] = true
	var dir := DirAccess.open(SPRITE_DIR)
	if dir != null:
		var undeclared: Array = []
		for f in dir.get_files():
			if f.ends_with(".json") and not claimed.has(f):
				undeclared.append(f)
		if not undeclared.is_empty():
			undeclared.sort()
			lines.append("[sprites] %d JSON(s) on disk not declared by any building: %s"
				% [undeclared.size(), ", ".join(undeclared)])
	return lines

static func report() -> void:
	for line in manifest_report_lines():
		print(line)
	if not _failures.is_empty():
		var msg: String = "SpriteLibrary: %d of %d declared sprites failed to load — those buildings are rendering as untextured fallbacks." % [_failures.size(), declared().size()]
		printerr(msg)
		push_error(msg)
		for f in _failures:
			push_warning("SpriteLibrary: " + f)

# ---------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------

## Returns true if this building was fully drawn from sprites. False means the
## caller must fall back to `Buildings.draw_one()`.
##
## Layer order per building: shadow, then body. The glow is NOT drawn here —
## see `GlowLayer` for why it cannot be, and what that costs.
static func draw_building(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> bool:
	if not enabled:
		return false
	if not declared().has(b.type):
		return false
	ensure_loaded()
	var e = _entries.get(declared()[b.type], null)
	if e == null:
		return false
	var fp: Vector2i = Buildings.footprint_of(b.type)
	var scale: float = float(tile_size) / float(SPRITE_PX_PER_TILE)
	var size: Vector2 = Vector2(e["sprite_px"]) * scale

	if e["shadow"] != null:
		var stl: Vector2 = draw_top_left(world_pos, fp, e["shadow_anchor_px"], tile_size)
		canvas.draw_texture_rect(e["shadow"], Rect2(stl, size), false)

	var tex = e["states"].get(state_key_for(b), null)
	if tex == null:
		tex = e["states"].get("", null)
	if tex == null:
		return false
	var tl: Vector2 = draw_top_left(world_pos, fp, e["anchor_px"], tile_size)
	canvas.draw_texture_rect(tex, Rect2(tl, size), false)
	return true

## Painted over any DECLARED building that fell back to the vector renderer.
## Magenta because nothing in the game's palette is magenta — the marker has to
## be unmistakable at a glance, not tasteful.
static func draw_fallback_marker(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	if not enabled or not mark_fallbacks:
		return
	if not declared().has(b.type):
		return
	var fp: Vector2i = Buildings.footprint_of(b.type)
	var rect := Rect2(world_pos, Vector2(float(fp.x * tile_size), float(fp.y * tile_size)))
	canvas.draw_rect(rect, FALLBACK_MARKER, false, FALLBACK_MARKER_WIDTH)
	canvas.draw_line(rect.position, rect.position + rect.size, FALLBACK_MARKER, FALLBACK_MARKER_WIDTH)
	canvas.draw_line(rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), FALLBACK_MARKER, FALLBACK_MARKER_WIDTH)

## Which `masters[].state` string applies to this building right now.
## "" means the asset is stateless (chest, power_pole).
static func state_key_for(b: Building) -> String:
	if b.type == Buildings.Type.SMELTER:
		return "smelting" if int(b.state.get("state", Smelter.STATE_IDLE)) == Smelter.STATE_SMELTING else "idle"
	return ""

# ---------------------------------------------------------------------------
# Q3 — the glow pulse runs on the TICK clock, not the wall clock
# ---------------------------------------------------------------------------
#
# `docs/scoping/r1-two-clocks.md` scopes audit finding #31: three `_process`
# systems take the raw frame delta while `tick_system.gd:5-7` legislates that
# TickSystem is "the *only* clock the simulation should care about". #31 is
# OPEN. Adding a fourth `_process`-driven timer would enlarge an open finding
# in the same session that documents it.
#
# The precedent is already in the codebase and it went the other way:
# `inserter.gd:944` reads `cycle_progress` out of building state and
# `inserter.gd:990` / `:995` interpolate the arm angle from it — a swing driven
# by simulation state, not by elapsed seconds. `inserter.gd:981-986` records
# why: "The underlying cycle_progress is untouched by the stall, so the swing
# resumes from where it left off when power returns."
#
# DECISION: state-driven. The smelter already counts `progress` in ticks
# (`smelter.gd:111-113`) against `recipe["time_ticks"]`. `glow_phase_for` turns
# that into 0..1 and `glow_alpha` turns that into a pulse. Consequences, all of
# them wanted:
#
#   - `tick_speed 10` speeds the pulse up 10x, exactly like the arm and the
#     progress bar. A wall-clock pulse would desync from `tick_speed`, which IS
#     finding #31's two-clocks problem, one asset at a time.
#   - A stalled smelter (NO_FUEL / BLOCKED_OUTPUT) holds its glow still instead
#     of breathing while doing nothing. Same reasoning as the parked arm.
#   - No new timer, no new `_process` subscriber, nothing new to migrate when
#     #31 is finally decided.
#   - Frame rate does not affect it. Two machines at different fps show the
#     same glow at the same tick.
#
# COST, stated plainly: the pulse is quantised to ticks. At 20 Hz and a smelt
# cycle of N ticks the alpha moves in N steps. For iron (see Recipes) that is
# smooth enough; a 4-tick recipe would visibly step. The fix if that ever
# matters is to interpolate between ticks using the tick accumulator — still
# the tick clock, still not a fourth timer.

## 0..1 progress through the current work cycle, or -1 when the building is not
## working and should not pulse at all.
static func glow_phase_for(b: Building) -> float:
	if b.type != Buildings.Type.SMELTER:
		return -1.0
	if int(b.state.get("state", Smelter.STATE_IDLE)) != Smelter.STATE_SMELTING:
		return -1.0
	var recipe_id: String = str(b.state.get("recipe_id", ""))
	if recipe_id == "":
		return -1.0
	var recipe: Dictionary = Recipes.get_recipe(recipe_id)
	if recipe.is_empty():
		return -1.0
	var total: int = int(recipe.get("time_ticks", 0))
	if total <= 0:
		return -1.0
	return clampf(float(int(b.state.get("progress", 0))) / float(total), 0.0, 1.0)

## Additive glow pass.
##
## WHY IT IS A SEPARATE CanvasItem. Godot's immediate-mode 2D API has no
## per-draw-call blend mode: `draw_texture_rect` has no blend argument, and
## blend mode lives on `CanvasItemMaterial`, which is per-CanvasItem. GridWorld
## is one CanvasItem, so an additive draw inside `GridWorld._draw` is not
## expressible. A child CanvasItem carrying BLEND_MODE_ADD is.
##
## WHAT THAT COSTS: every glow composites above every building, not just above
## its own body. The brief's stated order is shadow, body, glow PER BUILDING.
## With exactly one glow asset in existence the two orders are pixel-identical,
## so nothing is currently wrong — but they diverge the moment a second glowing
## building can overlap the first. The general fix is a depth-sorted multi-pass
## renderer, which is the same work item as the missing z-sort reported this
## session, and is deliberately NOT built here.
class GlowLayer extends Node2D:
	var world: Node2D = null

	func _draw() -> void:
		if world == null or not SpriteLibrary.enabled:
			return
		SpriteLibrary.draw_glows(world, self)

## Build the additive child layer. Called by GridWorld only while the flag is
## on, so the node does not exist at all in the default configuration.
static func make_glow_layer(world: Node2D) -> Node2D:
	var layer := GlowLayer.new()
	layer.name = "SpriteGlowLayer"
	layer.world = world
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	layer.material = mat
	layer.z_index = 1
	return layer

static func draw_glows(world: Node2D, canvas: CanvasItem) -> void:
	if not enabled:
		return
	ensure_loaded()
	for anchor_key in world.buildings:
		var anchor: Vector2i = anchor_key
		var b: Building = world.buildings[anchor]
		if not declared().has(b.type):
			continue
		var e = _entries.get(declared()[b.type], null)
		if e == null or e["glow"] == null:
			continue
		var phase: float = glow_phase_for(b)
		if phase < 0.0:
			continue
		var ts: int = world.TILE_SIZE
		var fp: Vector2i = Buildings.footprint_of(b.type)
		var world_pos: Vector2 = world.tile_to_world_origin(anchor)
		var scale: float = float(ts) / float(SPRITE_PX_PER_TILE)
		var tl: Vector2 = draw_top_left(world_pos, fp, e["anchor_px"], ts)
		var size: Vector2 = Vector2(e["sprite_px"]) * scale
		canvas.draw_texture_rect(e["glow"], Rect2(tl, size), false, Color(1.0, 1.0, 1.0, glow_alpha(phase)))
