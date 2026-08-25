extends RefCounted

## SPRITE MANIFEST + MALFORMED-ASSET GUARDS.
##
## ⚠ Read NOTES.md, "Protocol: silent compensation — when absence is
## indistinguishable from success". The sprite path is a textbook instance of
## that shape, and this file is the layer of the guard that works when nobody
## is running the game.
##
## The mechanism: a sprite that fails to load falls back to
## `Buildings.draw_one()`. The building still renders. A broken asset therefore
## LOOKS LIKE A WORKING GAME. At three assets someone is watching every frame;
## at nineteen it means half the art quietly is not rendering and nothing looks
## wrong. The compensator — the thing that makes it invisible — is the fallback
## renderer, which is good design and is exactly why this survives review.
##
## The detection question, answered rather than assumed: if the sprite loader
## silently stopped loading anything, what would notice? Without this file:
## NOTHING in the suite. Every other assertion in the project runs headless
## with no renderer and never touches a texture. Sub-case (1) is the answer.
##
## ---------------------------------------------------------------------------
## Sub-case (1) deliberately couples the suite to `art/`
## ---------------------------------------------------------------------------
## `art/` is owned by a concurrent Blender session. If an asset there is broken
## or half-written, THIS SUITE GOES RED. That is the intended trade: an asset
## broken at source should stop the build rather than ship as an invisible
## fallback. The failure message names the file and the two numbers that
## disagree, so a mid-write collision is a one-line diagnosis, not a mystery.
##
## Sub-cases (2)-(11) and (14) touch no real asset at all. They write synthetic
## assets into `user://` — the only way to exercise corruption without writing
## into the read-only art tree.

const TMP: String = "user://sprite_probe_fixtures"
const ConsoleScript = preload("res://scripts/ui/console.gd")

static func test_name() -> String:
	return "sprite manifest + malformed-asset guards (all 3 declared assets are REJECTED for bottom padding and await re-export; 10 corruption shapes are each rejected by name, not silently absorbed)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	_case_1_declared_assets_are_rejected_for_bottom_padding(failures)
	_case_1b_shipped_geometry_still_matches_the_json_on_disk(failures)

	# Corruption shapes. Each writes a fixture, loads it, and asserts BOTH
	# that it was rejected AND that the message identifies the problem — a
	# guard that rejects everything with "error" is not a guard.
	_reset_tmp()
	_case_2_unparseable_json(failures)
	_case_3_sprite_px_disagrees_with_png(failures)
	_case_4_anchor_outside_sprite(failures)
	_case_5_cell_tiles_inconsistent_with_sprite_px(failures)
	_case_6_master_names_missing_file(failures)
	_case_7_shadow_without_body(failures)
	_case_8_shadow_anchor_diverges(failures)
	_case_9_footprint_width_disagrees_with_game(failures)
	_case_10_glow_size_mismatch(failures)
	_case_11_valid_synthetic_asset_loads(failures)
	_case_12_flag_is_off_by_default(failures)
	_case_13_console_toggle(parent, failures)
	_case_14_transparent_bottom_padding(failures)

	if failures.is_empty():
		return { "ok": true, "message": "15 sub-cases pass: all 3 declared assets are rejected for transparent bottom padding (chest 7 rows, smelter 2, power_pole 9) and their JSON geometry still matches disk; unparseable JSON, PNG/sprite_px size disagreement, out-of-bounds anchor, cell_tiles/sprite_px inconsistency, a master naming a missing file, a shadow with no body, a shadow anchor diverging from the body's, a footprint width disagreeing with Buildings, a glow of the wrong size, and a body or shadow with transparent bottom padding are each rejected with a message naming the fault; a well-formed synthetic asset still loads and a padded GLOW still loads; the flag is off by default; and `sprites on|off` in the dev console flips it and reports the manifest" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# ===========================================================================
# (1) THE MANIFEST — and ⚠ IT IS INVERTED FROM WHAT IT USED TO ASSERT.
#
# This sub-case used to require all three declared sprites to LOAD. Since the
# zero-padding rule (sprite_library.gd, BOTTOM_ROW_MIN_ALPHA) all three are
# REJECTED, and that is the intended, decided state: the assets must be
# re-exported with no transparent bottom padding before the sprite path renders
# them again.
#
# ⚠ THIS IS NOT GRANDFATHERING, AND THE DIFFERENCE MATTERS. Nothing here
# exempts the three assets, downgrades the rule to a warning, or lets them
# load. They fail, loudly: the manifest line reads `loaded=0 failed=3`,
# `report()` push_errors, and any declared building that fell back gets a
# magenta cross painted over it in the frame. This sub-case RECORDS that state
# so a permanently-red suite does not train everyone to ignore it — and it is
# written to redden AGAIN, from the other direction, the moment the re-export
# lands. When it does, the fix is to restore the positive assertions this
# comment describes, not to update the numbers.
#
# The measured counts are pinned per asset, so a PARTIAL re-export (one asset
# fixed, two not) also reddens rather than sitting in the same green box.
# ===========================================================================

## Empty bottom rows measured 2026-08-24, per BODY master, at
## SpriteLibrary.BOTTOM_ROW_MIN_ALPHA. All three must be 0 for the assets to
## load; none is.
##
## ⚠ NOTE the NOTES.md art-probe finding recorded "8 empty bottom rows each" for
## all three. That was wrong for all three — re-measured here from the files.
## The smelter is the interesting one: its bottom row is not empty at all under
## a strict alpha>0 reading (one stray pixel at alpha 3/255), which is exactly
## why the rule carries a threshold instead.
const EXPECTED_EMPTY_BOTTOM_ROWS: Dictionary = {
	"res://art/sprites/chest.png": 7,
	"res://art/sprites/smelter_idle.png": 2,
	"res://art/sprites/smelter_smelting.png": 2,
	"res://art/sprites/power_pole.png": 9,
}

static func _case_1_declared_assets_are_rejected_for_bottom_padding(failures: Array) -> void:
	SpriteLibrary.reset()
	SpriteLibrary.ensure_loaded()
	var declared: Dictionary = SpriteLibrary.declared()
	var loaded: Array = SpriteLibrary.entry_names()
	var failed: Array = SpriteLibrary.failures()

	if not loaded.is_empty():
		failures.append("(1) %d declared sprite(s) LOADED (%s). If art has re-exported them with the bottom row flush, that is good news and this sub-case is now stale: restore the positive manifest assertions (loaded == declared, sprite_px / anchor_px / state counts / shadow / glow per asset) that this file carried before the zero-padding rule, and delete EXPECTED_EMPTY_BOTTOM_ROWS."
			% [loaded.size(), ", ".join(loaded)])
	if failed.size() != declared.size():
		failures.append("(1) %d of %d declared sprites failed; expected all %d to fail on bottom padding. Failures: %s"
			% [failed.size(), declared.size(), declared.size(), " ; ".join(failed)])

	# The failure must be THE PADDING ONE. A guard that rejects everything for
	# any reason would satisfy the counts above while hiding a real regression
	# in the JSON validation that runs before the texture step.
	for f in failed:
		var msg: String = str(f)
		for needle in ["below the alpha-8 opacity threshold", "re-export"]:
			if not msg.contains(needle):
				failures.append("(1) a declared sprite failed for something OTHER than bottom padding — expected '%s' in \"%s\"" % [needle, msg])
		# Every asset is named by its own file, not by a generic message.
		if not msg.contains(".png"):
			failures.append("(1) a failure message does not name a file: \"%s\"" % msg)

	# Per-asset, measured directly rather than parsed out of the message.
	for path in EXPECTED_EMPTY_BOTTOM_ROWS.keys():
		var img := Image.new()
		if img.load(str(path)) != OK:
			failures.append("(1) could not read %s to measure its bottom padding" % str(path))
			continue
		var got: int = SpriteLibrary.empty_bottom_rows(img)
		var want: int = int(EXPECTED_EMPTY_BOTTOM_ROWS[path])
		if got != want:
			failures.append("(1) %s has %d empty bottom rows, recorded as %d. If it is now 0 the re-export landed — see the note on this sub-case. Otherwise the asset changed and NOTES.md's art-probe counts are stale."
				% [str(path), got, want])
	# The layers the rule deliberately does NOT apply to, and the ones it does.
	# Measured: all three shadows already reach the bottom row; the smelter's
	# glow does not, and must not be required to.
	for path in ["res://art/sprites/chest_shadow.png", "res://art/sprites/smelter_shadow.png", "res://art/sprites/power_pole_shadow.png"]:
		var simg := Image.new()
		if simg.load(path) != OK:
			failures.append("(1) could not read %s" % path)
			continue
		if SpriteLibrary.empty_bottom_rows(simg) != 0:
			failures.append("(1) %s has %d empty bottom rows; shadows are ground-plane silhouettes and the rule applies to them too, so this asset is a second re-export"
				% [path, SpriteLibrary.empty_bottom_rows(simg)])
	var gimg := Image.new()
	if gimg.load("res://art/sprites/smelter_glow.png") == OK:
		if SpriteLibrary.empty_bottom_rows(gimg) == 0:
			failures.append("(1) smelter_glow.png now reaches the bottom row. Harmless, but the glow exemption in _load_texture was justified by this asset legitimately NOT reaching it — re-read that comment before trusting it.")

# ===========================================================================
# (1b) THE GEOMETRY COVERAGE THE PADDING RULE WOULD OTHERWISE HAVE DELETED.
#
# Sub-case (1) used to read sprite_px / anchor_px / state count / shadow / glow
# off the LOADED entry. Nothing loads any more, so those assertions would have
# quietly stopped running — a rule that makes the suite green by removing what
# it was checking. Exactly the shape NOTES.md's silent-compensation protocol
# names.
#
# So the same facts are read straight off the JSON on disk instead. This is the
# link `test_sprite_anchor.gd` explicitly delegates here: that file pins the
# same numbers as LITERALS and says "test_sprite_manifest.gd is the one that
# reads the real files". Without this the two would be one unchecked belief.
# ===========================================================================
const SHIPPED_JSON: Array = [
	# base, sprite_px, anchor_px, master count, has shadow, has glow
	["chest", Vector2i(32, 64), Vector2(16, 64), 1, true, false],
	["smelter", Vector2i(64, 96), Vector2(32, 96), 2, true, true],
	["power_pole", Vector2i(32, 96), Vector2(16, 96), 1, true, false],
]

static func _case_1b_shipped_geometry_still_matches_the_json_on_disk(failures: Array) -> void:
	for row in SHIPPED_JSON:
		var base: String = str(row[0])
		var jpath: String = "%s/%s.json" % [SpriteLibrary.SPRITE_DIR, base]
		if not FileAccess.file_exists(jpath):
			failures.append("(1b) %s is missing from the art tree" % jpath)
			continue
		var reader := JSON.new()
		if reader.parse(FileAccess.get_file_as_string(jpath)) != OK:
			failures.append("(1b) %s is unparseable: line %d, %s" % [jpath, reader.get_error_line(), reader.get_error_message()])
			continue
		var j: Dictionary = reader.data
		var spx := Vector2i(int(j["sprite_px"][0]), int(j["sprite_px"][1]))
		var anc := Vector2(float(j["anchor_px"][0]), float(j["anchor_px"][1]))
		if spx != row[1]:
			failures.append("(1b) %s sprite_px %s, expected %s — a silent re-export at a different resolution shifts the building by half a tile" % [base, spx, row[1]])
		if anc != row[2]:
			failures.append("(1b) %s anchor_px %s, expected %s" % [base, anc, row[2]])
		if (j["masters"] as Array).size() != int(row[3]):
			failures.append("(1b) %s has %d master(s), expected %d" % [base, (j["masters"] as Array).size(), int(row[3])])
		# The anchor convention itself: bottom-centre of the sprite.
		if anc != Vector2(float(spx.x) * 0.5, float(spx.y)):
			failures.append("(1b) %s anchor_px %s is no longer [sprite_w/2, sprite_h] %s — the zero-padding rule's whole premise is that anchor_px.y IS the bottom edge"
				% [base, anc, Vector2(float(spx.x) * 0.5, float(spx.y))])
		# Footprint width against the game's own table.
		var t: int = _type_for_base(base)
		if t >= 0 and int(j["cell_tiles"][0]) != Buildings.footprint_of(t).x:
			failures.append("(1b) %s cell_tiles[0] = %d but Buildings.footprint_of(%s).x = %d"
				% [base, int(j["cell_tiles"][0]), Buildings.name_of(t), Buildings.footprint_of(t).x])
		# Shadow and glow presence, from the files rather than from a loaded entry.
		var has_shadow: bool = FileAccess.file_exists("%s/%s_shadow.png" % [SpriteLibrary.SPRITE_DIR, base])
		if has_shadow != bool(row[4]):
			failures.append("(1b) %s shadow layer present=%s, expected %s" % [base, str(has_shadow), str(bool(row[4]))])
		var has_glow: bool = FileAccess.file_exists("%s/%s_glow.png" % [SpriteLibrary.SPRITE_DIR, base])
		if has_glow != bool(row[5]):
			failures.append("(1b) %s glow layer present=%s, expected %s" % [base, str(has_glow), str(bool(row[5]))])

static func _type_for_base(base: String) -> int:
	for t in SpriteLibrary.declared().keys():
		if str(SpriteLibrary.declared()[t]) == base:
			return int(t)
	return -1

# ---------------------------------------------------------------------------
# fixture helpers — synthetic assets in user://, never in art/
# ---------------------------------------------------------------------------

static func _reset_tmp() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	if d.dir_exists(TMP):
		var sub := DirAccess.open(TMP)
		if sub != null:
			for f in sub.get_files():
				sub.remove(f)
	else:
		d.make_dir_recursive(TMP)

static func _write_png(name: String, w: int, h: int) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 1.0, 1.0))
	var path: String = "%s/%s" % [TMP, name]
	img.save_png(path)
	return path

static func _write_text(name: String, text: String) -> String:
	var path: String = "%s/%s" % [TMP, name]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path

## A well-formed JSON body for a synthetic asset, with overridable fields.
static func _json(base: String, cell: Array, spx: Array, anchor: Array, sprite_file: String) -> String:
	return JSON.stringify({
		"name": base,
		"footprint_tiles": float(cell[0]),
		"cell_tiles": cell,
		"sprite_px": spx,
		"anchor_px": anchor,
		"overhangs_front_edge": false,
		"masters": [{"tag": base, "state": null, "sprite": "%s/%s" % [TMP, sprite_file]}],
	})

## Assert: rejected, AND the message contains every needle. The needle check
## is what separates "the guard fired" from "the guard fired for the reason we
## think" — a loader that returned {"ok": false, "error": "error"} for
## everything would satisfy the first and fail the second.
static func _expect_reject(failures: Array, case_id: String, res: Dictionary, needles: Array) -> void:
	if bool(res["ok"]):
		failures.append("%s ACCEPTED a malformed asset — this is the silent-compensation failure this file exists to catch" % case_id)
		return
	var err: String = str(res["error"])
	for n in needles:
		if not err.contains(str(n)):
			failures.append("%s rejected it, but the message does not say why: expected '%s' in \"%s\""
				% [case_id, str(n), err])

# ===========================================================================
# (2) Corrupt / unparseable JSON.
# ===========================================================================
static func _case_2_unparseable_json(failures: Array) -> void:
	_write_png("c2.png", 32, 64)
	_write_text("c2.json", "{ \"name\": \"c2\", \"cell_tiles\": [1, 2],")   # truncated
	_expect_reject(failures, "(2)", SpriteLibrary.load_asset(TMP, "c2", 1), ["unparseable"])

# ===========================================================================
# (3) sprite_px disagrees with the PNG's real dimensions.
#
# The most likely real-world corruption: an artist re-exports at a different
# resolution and the JSON is not regenerated. Without this check the sprite is
# drawn stretched into the rect the JSON claims, which reads as "the art looks
# a bit off" rather than as an error.
# ===========================================================================
static func _case_3_sprite_px_disagrees_with_png(failures: Array) -> void:
	_write_png("c3.png", 32, 48)                              # real: 32x48
	_write_text("c3.json", _json("c3", [1, 2], [32, 64], [16, 64], "c3.png"))   # claims 32x64
	_expect_reject(failures, "(3)", SpriteLibrary.load_asset(TMP, "c3", 1), ["32x48", "32x64"])

# ===========================================================================
# (4) anchor_px outside the sprite bounds.
# ===========================================================================
static func _case_4_anchor_outside_sprite(failures: Array) -> void:
	_write_png("c4.png", 32, 64)
	_write_text("c4.json", _json("c4", [1, 2], [32, 64], [16, 200], "c4.png"))
	_expect_reject(failures, "(4)", SpriteLibrary.load_asset(TMP, "c4", 1), ["anchor_px", "outside"])
	# Negative is out of bounds too, and on the other axis.
	_write_text("c4b.json", _json("c4b", [1, 2], [32, 64], [-1, 64], "c4.png"))
	_expect_reject(failures, "(4b)", SpriteLibrary.load_asset(TMP, "c4b", 1), ["anchor_px", "outside"])

# ===========================================================================
# (5) cell_tiles inconsistent with sprite_px.
# ===========================================================================
static func _case_5_cell_tiles_inconsistent_with_sprite_px(failures: Array) -> void:
	_write_png("c5.png", 32, 64)
	_write_text("c5.json", _json("c5", [1, 3], [32, 64], [16, 64], "c5.png"))   # 1x3 tiles = 32x96
	_expect_reject(failures, "(5)", SpriteLibrary.load_asset(TMP, "c5", 1), ["cell_tiles", "sprite_px"])

# ===========================================================================
# (6) A masters entry naming a sprite file that does not exist.
# ===========================================================================
static func _case_6_master_names_missing_file(failures: Array) -> void:
	_write_text("c6.json", _json("c6", [1, 2], [32, 64], [16, 64], "c6_does_not_exist.png"))
	_expect_reject(failures, "(6)", SpriteLibrary.load_asset(TMP, "c6", 1), ["c6_does_not_exist.png", "does not exist"])

# ===========================================================================
# (7) A shadow layer present but the body missing.
#
# Two shapes, both rejected: shadow PNG with no shadow JSON to anchor it, and
# shadow JSON with no shadow PNG. Drawing a shadow with a guessed anchor is
# the worst outcome — a correctly-placed body with a shadow 32 px off reads as
# an art bug, not a loader bug.
# ===========================================================================
static func _case_7_shadow_without_body(failures: Array) -> void:
	_write_png("c7.png", 32, 64)
	_write_text("c7.json", _json("c7", [1, 2], [32, 64], [16, 64], "c7.png"))
	_write_png("c7_shadow.png", 32, 64)                      # PNG but no shadow JSON
	_expect_reject(failures, "(7)", SpriteLibrary.load_asset(TMP, "c7", 1), ["no shadow JSON"])

	_write_png("c7b.png", 32, 64)
	_write_text("c7b.json", _json("c7b", [1, 2], [32, 64], [16, 64], "c7b.png"))
	_write_text("c7b_shadow.json", JSON.stringify({"anchor_px": [16, 64]}))   # JSON but no PNG
	_expect_reject(failures, "(7b)", SpriteLibrary.load_asset(TMP, "c7b", 1), ["c7b_shadow.png"])

# ===========================================================================
# (8) The shadow's own anchor diverging from the body's.
#
# All three shipped shadows carry an anchor identical to their body's, and the
# shadow JSON's own `blend` field says "same anchor". This code READS the
# shadow's anchor rather than inheriting it — so a divergence has to be
# reported rather than absorbed, or the file's own field becomes decoration.
# ===========================================================================
static func _case_8_shadow_anchor_diverges(failures: Array) -> void:
	_write_png("c8.png", 32, 64)
	_write_png("c8_shadow.png", 32, 64)
	_write_text("c8.json", _json("c8", [1, 2], [32, 64], [16, 64], "c8.png"))
	_write_text("c8_shadow.json", JSON.stringify({"anchor_px": [16, 32]}))
	_expect_reject(failures, "(8)", SpriteLibrary.load_asset(TMP, "c8", 1), ["shadow", "differs"])

# ===========================================================================
# (9) The JSON's footprint width disagreeing with the game's own table.
#
# The JSON is authored by the art pipeline and `Buildings.DATA` by the game.
# Nothing keeps them in step, so this is the join that will actually drift.
# ===========================================================================
static func _case_9_footprint_width_disagrees_with_game(failures: Array) -> void:
	_write_png("c9.png", 64, 64)
	_write_text("c9.json", _json("c9", [2, 2], [64, 64], [32, 64], "c9.png"))
	# Game says the building is 1 tile wide; the art says 2.
	_expect_reject(failures, "(9)", SpriteLibrary.load_asset(TMP, "c9", 1), ["footprint"])
	# And the internal duplicate must agree too: footprint_tiles vs cell_tiles[0].
	var bad: String = JSON.stringify({
		"name": "c9b",
		"footprint_tiles": 3.0,
		"cell_tiles": [1, 2],
		"sprite_px": [32, 64],
		"anchor_px": [16, 64],
		"masters": [{"tag": "c9b", "state": null, "sprite": "%s/c9b.png" % TMP}],
	})
	_write_png("c9b.png", 32, 64)
	_write_text("c9b.json", bad)
	_expect_reject(failures, "(9b)", SpriteLibrary.load_asset(TMP, "c9b", 1), ["footprint_tiles", "cell_tiles"])

# ===========================================================================
# (10) A glow layer whose dimensions do not match the body.
#
# `smelter_glow.png` has NO JSON of its own — it inherits the body's geometry.
# That makes an out-of-step glow undetectable from data alone unless the size
# is checked, and a mis-sized glow composites additively over the wrong pixels.
# ===========================================================================
static func _case_10_glow_size_mismatch(failures: Array) -> void:
	_write_png("c10.png", 64, 96)
	_write_png("c10_glow.png", 96, 96)
	_write_text("c10.json", _json("c10", [2, 3], [64, 96], [32, 96], "c10.png"))
	_expect_reject(failures, "(10)", SpriteLibrary.load_asset(TMP, "c10", 2), ["glow", "96x96", "64x96"])

# ===========================================================================
# (11) POSITIVE CONTROL. A well-formed synthetic asset — body, shadow and glow
# — must LOAD. Without this, every sub-case above would still pass if
# `load_asset` returned ok=false unconditionally.
# ===========================================================================
static func _case_11_valid_synthetic_asset_loads(failures: Array) -> void:
	_write_png("c11.png", 64, 96)
	_write_png("c11_shadow.png", 64, 96)
	_write_png("c11_glow.png", 64, 96)
	_write_text("c11.json", _json("c11", [2, 3], [64, 96], [32, 96], "c11.png"))
	_write_text("c11_shadow.json", JSON.stringify({"anchor_px": [32, 96]}))
	var res: Dictionary = SpriteLibrary.load_asset(TMP, "c11", 2)
	if not bool(res["ok"]):
		failures.append("(11) a well-formed synthetic asset was REJECTED: %s" % str(res["error"]))
		return
	var e: Dictionary = res["entry"]
	if e["sprite_px"] != Vector2i(64, 96):
		failures.append("(11) sprite_px %s, expected (64, 96)" % e["sprite_px"])
	if e["anchor_px"] != Vector2(32, 96):
		failures.append("(11) anchor_px %s, expected (32, 96)" % e["anchor_px"])
	if e["shadow"] == null:
		failures.append("(11) shadow did not load")
	if e["glow"] == null:
		failures.append("(11) glow did not load")
	# An asset with no shadow at all is legal, and must say so rather than
	# failing — the note is what the manifest line reports.
	_write_png("c11b.png", 32, 64)
	_write_text("c11b.json", _json("c11b", [1, 2], [32, 64], [16, 64], "c11b.png"))
	var res2: Dictionary = SpriteLibrary.load_asset(TMP, "c11b", 1)
	if not bool(res2["ok"]):
		failures.append("(11) a shadowless asset was rejected: %s" % str(res2["error"]))
	elif not str(res2["notes"]).contains("no shadow"):
		failures.append("(11) a shadowless asset loaded without recording a note")

# ===========================================================================
# (12) The flag is OFF by default, and the fallback marker is on.
#
# The whole byte-identical guarantee rests on the default. A future edit that
# flips it to true would change every frame of the game and redden nothing
# else in the suite — the sprite path renders fine, it is just not the thing
# anybody agreed to ship.
# ===========================================================================
static func _case_12_flag_is_off_by_default(failures: Array) -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/world/sprite_library.gd")
	if not src.contains("static var enabled: bool = false"):
		failures.append("(12) sprite_library.gd no longer declares `static var enabled: bool = false` — the sprite path may now be on by default")
	if not src.contains("static var mark_fallbacks: bool = true"):
		failures.append("(12) sprite_library.gd no longer declares `static var mark_fallbacks: bool = true` — a silent fallback would stop being marked in the frame")
	# The draw hook must still be gated. A hook that called draw_building()
	# unconditionally would ignore the flag entirely.
	var gw: String = FileAccess.get_file_as_string("res://scripts/world/grid_world.gd")
	if not gw.contains("if SpriteLibrary.enabled:"):
		failures.append("(12) grid_world.gd no longer gates the sprite path behind SpriteLibrary.enabled")
	if not gw.contains("Buildings.draw_one(b, self, tile_to_world_origin(anchor), TILE_SIZE)"):
		failures.append("(12) grid_world.gd no longer calls Buildings.draw_one on the fallback path")
	if not gw.contains("SpriteLibrary.draw_fallback_marker"):
		failures.append("(12) grid_world.gd no longer marks fallen-back buildings in the frame")
	# THE CALL SITE ITSELF. Measured: replacing this one line with
	# `drew_sprite = false` deletes the entire sprite path and leaves the
	# suite at 57 passed, 0 failed — the loop-level call site was, like
	# `Buildings.post_tick_one` before `test_tick_loop_wiring.gd`, wholly
	# uncovered.
	#
	# ⚠ THIS IS A SOURCE-TEXT PIN, NOT AN EXECUTION PIN, and the difference
	# matters. `test_runner.gd` calls each suite synchronously (`:134`) and
	# never yields a frame, so no CanvasItem in this project ever receives
	# NOTIFICATION_DRAW during a headless run: the suite structurally cannot
	# execute a draw path. The executed check is the windowed capture harness,
	# which asserts the flag-on frame DIFFERS from the flag-off frame — if the
	# call site were gone, the two would be identical.
	if not gw.contains("SpriteLibrary.draw_building(b, self, tile_to_world_origin(anchor), TILE_SIZE)"):
		failures.append("(12) grid_world.gd no longer calls SpriteLibrary.draw_building in the building draw loop — the sprite path is disconnected and every building silently renders as vectors")

# ===========================================================================
# (13) THE TOGGLE IS REACHABLE. `SpriteLibrary.enabled` being a static var is
# only a flag if something can flip it; without a console command the "single
# toggle" is a source edit, which is not a toggle.
#
# Restores the flag to false afterwards — a test that left the sprite path on
# would silently change what every later suite in this run renders.
# ===========================================================================
static func _case_13_console_toggle(parent: Node, failures: Array) -> void:
	var was: bool = SpriteLibrary.enabled
	var console = ConsoleScript.new()
	parent.add_child(console)

	var on_out: String = console.execute("sprites on")
	if not SpriteLibrary.enabled:
		failures.append("(13) `sprites on` did not set SpriteLibrary.enabled")
	if not on_out.contains("declared=3"):
		failures.append("(13) `sprites on` did not report the manifest: %s" % on_out)
	# `loaded=0 failed=3` since the zero-padding rule — see sub-case (1). This
	# line is the loud half of the guard: it is what a person sees when they turn
	# the flag on and wonder why nothing is textured. When the re-export lands it
	# becomes loaded=3 failed=0 and this reddens alongside (1).
	if not on_out.contains("loaded=0 failed=3"):
		failures.append("(13) `sprites on` reported an unexpected load count — expected `loaded=0 failed=3` while the three assets await re-export: %s" % on_out)
	if not on_out.contains("untextured fallbacks"):
		failures.append("(13) `sprites on` did not warn that the failed buildings render as untextured fallbacks: %s" % on_out)

	var off_out: String = console.execute("sprites off")
	if SpriteLibrary.enabled:
		failures.append("(13) `sprites off` did not clear SpriteLibrary.enabled")
	if not off_out.contains("declared=3"):
		failures.append("(13) `sprites off` did not report the manifest: %s" % off_out)

	# Bare `sprites` reports without toggling — the "is my art actually loaded"
	# question has to be answerable without changing what the game is doing.
	var before: bool = SpriteLibrary.enabled
	var bare: String = console.execute("sprites")
	if SpriteLibrary.enabled != before:
		failures.append("(13) bare `sprites` changed the flag; it must only report")
	if not bare.contains("declared="):
		failures.append("(13) bare `sprites` did not report the manifest: %s" % bare)

	if not console.execute("sprites wibble").begins_with("Usage:"):
		failures.append("(13) `sprites wibble` did not return a usage line")
	if not console.execute("sprites on off").begins_with("Usage:"):
		failures.append("(13) `sprites on off` did not return a usage line")

	# `help` must list it, or nobody discovers the toggle exists.
	if not console.execute("help").contains("sprites"):
		failures.append("(13) `help` does not list the sprites command")

	console.queue_free()
	SpriteLibrary.enabled = was

# ===========================================================================
# (14) TRANSPARENT BOTTOM PADDING — the rule, on synthetic assets.
#
# Sub-case (1) shows the rule firing on the real art. This one shows it firing
# for the RIGHT REASON, on assets whose only fault is the padding, and shows the
# three boundaries the rule has to get right:
#
#   a. a body with padding is rejected, and the message says how many rows;
#   b. a SHADOW with padding is rejected too (shadows are ground-plane
#      silhouettes and share the body's anchor by contract);
#   c. a GLOW with padding LOADS. That exemption is the one place the rule is
#      deliberately not applied, and an untested exemption is just a hole.
#
# And (d): the threshold, which is the part a "non-zero alpha" reading gets
# wrong. A bottom row whose strongest pixel is alpha 3/255 is padding to the
# eye, and both real smelter masters are exactly that case.
# ===========================================================================
static func _case_14_transparent_bottom_padding(failures: Array) -> void:
	_reset_tmp()

	# (a) body with 4 transparent bottom rows.
	_write_png_padded("c14.png", 32, 64, 4, 255)
	_write_text("c14.json", _json("c14", [1, 2], [32, 64], [16, 64], "c14.png"))
	_expect_reject(failures, "(14a)", SpriteLibrary.load_asset(TMP, "c14", 1),
		["c14.png", "4 bottom rows below the alpha-8 opacity threshold", "re-export"])

	# (b) clean body, padded shadow.
	_write_png_padded("c14b.png", 32, 64, 0, 255)
	_write_png_padded("c14b_shadow.png", 32, 64, 3, 255)
	_write_text("c14b.json", _json("c14b", [1, 2], [32, 64], [16, 64], "c14b.png"))
	_write_text("c14b_shadow.json", JSON.stringify({"anchor_px": [16, 64]}))
	_expect_reject(failures, "(14b)", SpriteLibrary.load_asset(TMP, "c14b", 1),
		["c14b_shadow.png", "3 bottom rows below the alpha-8 opacity threshold"])

	# (c) clean body, padded GLOW — must LOAD. The exemption, exercised.
	_write_png_padded("c14c.png", 32, 64, 0, 255)
	_write_png_padded("c14c_glow.png", 32, 64, 12, 255)
	_write_text("c14c.json", _json("c14c", [1, 2], [32, 64], [16, 64], "c14c.png"))
	var res_glow: Dictionary = SpriteLibrary.load_asset(TMP, "c14c", 1)
	if not bool(res_glow["ok"]):
		failures.append("(14c) an asset with a clean body and a padded GLOW was rejected: %s. The glow is an additive overlay on the hot part of a machine, not a ground silhouette — smelter_glow.png is legitimately empty for its bottom 12 rows." % str(res_glow["error"]))
	elif res_glow["entry"]["glow"] == null:
		failures.append("(14c) the padded glow did not load even though the asset was accepted")

	# (d) THE THRESHOLD. A bottom row whose strongest pixel is alpha 3 of 255 is
	# padding, and a strict alpha>0 rule would accept it — which is precisely
	# how both real smelter masters would have been grandfathered in.
	# NOTE the shape: ZERO fully-transparent rows, and the bottom row itself
	# painted at alpha 3. That is the smelter's exact geometry, and a strict
	# "at least one non-zero alpha pixel" rule accepts it.
	_write_png_padded("c14d.png", 32, 64, 0, 3)
	_write_text("c14d.json", _json("c14d", [1, 2], [32, 64], [16, 64], "c14d.png"))
	_expect_reject(failures, "(14d)", SpriteLibrary.load_asset(TMP, "c14d", 1),
		["c14d.png", "alpha 3 of 255"])

	# (e) POSITIVE CONTROL for the threshold: alpha 8 is enough. Without this,
	# (d) would still pass if the rule had degenerated to "reject everything
	# that is not fully opaque".
	_write_png_padded("c14e.png", 32, 64, 0, 8)
	_write_text("c14e.json", _json("c14e", [1, 2], [32, 64], [16, 64], "c14e.png"))
	var res_thresh: Dictionary = SpriteLibrary.load_asset(TMP, "c14e", 1)
	if not bool(res_thresh["ok"]):
		failures.append("(14e) a body whose bottom row sits exactly at the alpha threshold (8/255) was rejected: %s — the rule is stricter than BOTTOM_ROW_MIN_ALPHA says" % str(res_thresh["error"]))

	_reset_tmp()

## A PNG that is opaque magenta except for `empty_rows` fully transparent rows
## at the bottom, with the last non-empty row painted at `bottom_alpha` (0-255)
## so the threshold itself can be exercised.
static func _write_png_padded(name: String, w: int, h: int, empty_rows: int, bottom_alpha: int) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 1.0, 1.0))
	for y in range(h - empty_rows, h):
		for x in range(w):
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	var last: int = h - empty_rows - 1
	if last >= 0:
		for x in range(w):
			img.set_pixel(x, last, Color(1.0, 0.0, 1.0, float(bottom_alpha) / 255.0))
	var path: String = "%s/%s" % [TMP, name]
	img.save_png(path)
	return path
