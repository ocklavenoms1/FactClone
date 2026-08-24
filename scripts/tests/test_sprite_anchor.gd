extends RefCounted

## SPRITE ANCHOR CONVENTION — and the fact that the three shipped assets
## cannot test it.
##
## The stated contract: `anchor_px` is the offset from the sprite's top-left to
## the FOOTPRINT's bottom-centre; draw at `footprint_bottom_centre - anchor_px`.
##
## MEASURED across all three shipped assets (art/sprites/*.json, read
## 2026-08-24):
##
##   asset        cell_tiles   sprite_px   anchor_px    footprint (Buildings)
##   -----------  -----------  ----------  -----------  ---------------------
##   chest        [1, 2]       32 x 64     [16, 64]     1 x 1
##   smelter      [2, 3]       64 x 96     [32, 96]     2 x 2
##   power_pole   [1, 3]       32 x 96     [16, 96]     1 x 1
##
## In EVERY row `anchor_px == [sprite_w / 2, sprite_h]`, AND
## `sprite_w == footprint_w * 32` (32 = 1x32, 64 = 2x32, 32 = 1x32). So the
## footprint's bottom-centre and the SPRITE's own bottom-centre are the same
## point, and a renderer that implements "sprite bottom-centre" emits
## pixel-identical output to one that implements "footprint bottom-centre".
## Overflow is purely vertical at all three; nothing overflows sideways.
##
## The honest verdict on "was the anchor convention right?" is therefore not
## right and not wrong but UNTESTED — and sub-case (1) below is what makes that
## claim a measurement rather than an opinion. Sub-case (4) then constructs the
## asset that DOES separate the two readings, which is the cheap version of
## discovering the problem at asset twenty.
##
## ⚠ NOTE ON `cell_tiles`. `cell_tiles[0]` is footprint WIDTH in tiles;
## `cell_tiles[1]` is SPRITE HEIGHT in tiles, NOT footprint depth. No JSON key
## in the shipped contract carries footprint depth at all, so the renderer must
## take depth from `Buildings.footprint_of(type).y`. Sub-case (6) pins the size
## of the mistake: reading `cell_tiles[1]` as depth puts the smelter 32 px too
## low.

const TS: int = 32   # GridWorld.TILE_SIZE

static func test_name() -> String:
	return "sprite anchor convention (general form; the three shipped assets cannot distinguish it from sprite-centred; a synthetic wide sprite can)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	_case_1_shipped_assets_cannot_discriminate(failures)
	_case_2_anchor_lands_on_footprint_bottom_centre(failures)
	_case_3_shipped_assets_place_correctly(failures)
	_case_4_wide_sprite_discriminates(failures)
	_case_5_scales_with_tile_size(failures)
	_case_6_cell_tiles_y_is_not_footprint_depth(failures)
	_case_7_glow_pulse_is_bounded_and_state_driven(failures)

	if failures.is_empty():
		return { "ok": true, "message": "7 sub-cases pass: the three shipped assets place identically under both readings of the contract (so they do not test it), the general form puts anchor_px exactly on the footprint's bottom-centre, a synthetic sprite wider than its footprint separates the two readings by 32 px with only the general form correct, placement scales with tile_size, cell_tiles[1] is proven not to be footprint depth, and the glow pulse is bounded and phase-driven" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# Asset table, transcribed from the shipped JSONs. Kept literal rather than
# re-read from disk so this file states what it believes and fails loudly if
# the art changes underneath it — test_sprite_manifest.gd is the one that
# reads the real files.
const SHIPPED: Array = [
	# name, sprite_px, anchor_px, footprint tiles
	["chest",      Vector2i(32, 64), Vector2(16, 64), Vector2i(1, 1)],
	["smelter",    Vector2i(64, 96), Vector2(32, 96), Vector2i(2, 2)],
	["power_pole", Vector2i(32, 96), Vector2(16, 96), Vector2i(1, 1)],
]

# ===========================================================================
# (1) THE CENTRAL FINDING: at the three shipped assets the general form and
# the degenerate "sprite bottom-centre" form produce THE SAME PIXEL.
#
# This sub-case exists to be true today and to STOP being true the moment
# someone adds an asset whose sprite is wider than its footprint or whose
# anchor is not sprite-centred. When it goes red, the message is not "the
# renderer broke" — it is "the shipped assets finally exercise the anchor
# convention, go look at sub-case (4)".
# ===========================================================================
static func _case_1_shipped_assets_cannot_discriminate(failures: Array) -> void:
	for row in SHIPPED:
		var name: String = row[0]
		var sprite_px: Vector2i = row[1]
		var anchor: Vector2 = row[2]
		var fp: Vector2i = row[3]
		# The degeneracy has two halves; assert both, so a future asset that
		# breaks only one of them still reports which one.
		if anchor != Vector2(float(sprite_px.x) * 0.5, float(sprite_px.y)):
			failures.append("(1) %s: anchor_px %s is no longer [sprite_w/2, sprite_h] %s — the two readings now differ, see sub-case (4)"
				% [name, anchor, Vector2(float(sprite_px.x) * 0.5, float(sprite_px.y))])
		if sprite_px.x != fp.x * SpriteLibrary.SPRITE_PX_PER_TILE:
			failures.append("(1) %s: sprite_w %d is no longer footprint_w %d x %d — the two readings now differ, see sub-case (4)"
				% [name, sprite_px.x, fp.x, SpriteLibrary.SPRITE_PX_PER_TILE])
		# And the consequence: same output from both forms, at two different
		# world positions so a coincidence at the origin cannot pass this.
		for origin in [Vector2(0.0, 0.0), Vector2(-224.0, 96.0)]:
			var general: Vector2 = SpriteLibrary.draw_top_left(origin, fp, anchor, TS)
			var degenerate: Vector2 = SpriteLibrary.draw_top_left_sprite_centred(origin, fp, sprite_px, TS)
			if general != degenerate:
				failures.append("(1) %s at %s: general %s != sprite-centred %s — sub-case (4) is now the live test"
					% [name, origin, general, degenerate])

# ===========================================================================
# (2) The general form's defining property: adding anchor_px back to the
# returned top-left must land exactly on the footprint's bottom-centre.
# This is the contract restated as an equation, so a sign error or a swapped
# axis cannot pass.
# ===========================================================================
static func _case_2_anchor_lands_on_footprint_bottom_centre(failures: Array) -> void:
	for row in SHIPPED:
		var name: String = row[0]
		var anchor: Vector2 = row[2]
		var fp: Vector2i = row[3]
		var origin := Vector2(160.0, -64.0)
		var tl: Vector2 = SpriteLibrary.draw_top_left(origin, fp, anchor, TS)
		var expected := origin + Vector2(float(fp.x * TS) * 0.5, float(fp.y * TS))
		if tl + anchor != expected:
			failures.append("(2) %s: top_left %s + anchor %s = %s, expected footprint bottom-centre %s"
				% [name, tl, anchor, tl + anchor, expected])

# ===========================================================================
# (3) Concrete placement of each shipped asset, spelled out in absolute
# numbers. A regression in the scale factor or in the bottom-centre term
# would still satisfy sub-case (2)'s identity while moving every building.
# ===========================================================================
static func _case_3_shipped_assets_place_correctly(failures: Array) -> void:
	# Building anchored at tile (0, 0), tile_size 32.
	#   chest      fp 1x1  bottom-centre (16, 32)  anchor (16, 64)  -> (0, -32)
	#   smelter    fp 2x2  bottom-centre (32, 64)  anchor (32, 96)  -> (0, -32)
	#   power_pole fp 1x1  bottom-centre (16, 32)  anchor (16, 96)  -> (0, -64)
	var expected: Dictionary = {
		"chest": Vector2(0.0, -32.0),
		"smelter": Vector2(0.0, -32.0),
		"power_pole": Vector2(0.0, -64.0),
	}
	for row in SHIPPED:
		var name: String = row[0]
		var sprite_px: Vector2i = row[1]
		var anchor: Vector2 = row[2]
		var fp: Vector2i = row[3]
		var tl: Vector2 = SpriteLibrary.draw_top_left(Vector2.ZERO, fp, anchor, TS)
		if tl != expected[name]:
			failures.append("(3) %s: top_left %s, expected %s" % [name, tl, expected[name]])
		# The sprite's bottom edge must sit exactly on the footprint's bottom
		# edge, and its horizontal span must exactly cover the footprint.
		if tl.y + float(sprite_px.y) != float(fp.y * TS):
			failures.append("(3) %s: sprite bottom %f != footprint bottom %d"
				% [name, tl.y + float(sprite_px.y), fp.y * TS])
		if tl.x != 0.0 or tl.x + float(sprite_px.x) != float(fp.x * TS):
			failures.append("(3) %s: sprite x-span [%f, %f] does not cover footprint [0, %d]"
				% [name, tl.x, tl.x + float(sprite_px.x), fp.x * TS])

# ===========================================================================
# (4) THE DISCRIMINATING CASE — the asset the pipeline has not produced yet.
#
# A 3-tile-wide sprite whose footprint is the LEFT tile only: a machine with a
# gantry arm reaching to the right, say. sprite_px 96x64, footprint 1x1,
# anchor_px [16, 64] — 16 px in from the sprite's left edge, on its bottom.
##
## This is the cheap version of finding the bug at asset twenty: the anchor
## convention is unfalsifiable at the three assets that exist, so the only way
## to test it now is to construct the asset that would falsify it.
##
## The two readings diverge by exactly (sprite_w / 2 - anchor_x) = 48 - 16 =
## 32 px, and ONLY the general form puts the footprint under the machine's
## base. The degenerate form centres the sprite on the tile, so the gantry's
## base hangs 32 px to the left of the tile the game thinks it occupies.
# ===========================================================================
static func _case_4_wide_sprite_discriminates(failures: Array) -> void:
	var sprite_px := Vector2i(96, 64)
	var anchor := Vector2(16.0, 64.0)
	var fp := Vector2i(1, 1)
	var origin := Vector2.ZERO

	var general: Vector2 = SpriteLibrary.draw_top_left(origin, fp, anchor, TS)
	var degenerate: Vector2 = SpriteLibrary.draw_top_left_sprite_centred(origin, fp, sprite_px, TS)

	# They must DISAGREE — if they ever agree here, either the general form
	# has collapsed into the degenerate one or this fixture stopped being a
	# discriminating case, and both are the same bug for our purposes.
	if general == degenerate:
		failures.append("(4) general %s == sprite-centred %s on a 96x64 sprite with a 1-tile footprint — the renderer is no longer implementing the general form"
			% [general, degenerate])
	if general.x - degenerate.x != 32.0:
		failures.append("(4) expected the two readings to differ by exactly 32 px in x, got %f"
			% [general.x - degenerate.x])

	# The general form is the correct one: the footprint's bottom-centre
	# (16, 32) must sit exactly anchor_px in from the sprite's top-left.
	if general != Vector2(0.0, -32.0):
		failures.append("(4) general form gave %s, expected (0, -32) — sprite left edge flush with the footprint tile" % general)
	if general + anchor != Vector2(16.0, 32.0):
		failures.append("(4) general form does not land the anchor on the footprint bottom-centre: %s != (16, 32)" % (general + anchor))
	# And the degenerate form is wrong in a specific, nameable way: it puts the
	# sprite's left edge 32 px WEST of the footprint tile.
	if degenerate != Vector2(-32.0, -32.0):
		failures.append("(4) sprite-centred form gave %s, expected (-32, -32)" % degenerate)

# ===========================================================================
# (5) tile_size is a variable, not the constant 32. The art is authored at 32
# px per tile (SPRITE_PX_PER_TILE); if TILE_SIZE ever changes, the sprite must
# SCALE, not shear off its anchor.
# ===========================================================================
static func _case_5_scales_with_tile_size(failures: Array) -> void:
	var anchor := Vector2(32.0, 96.0)     # smelter
	var fp := Vector2i(2, 2)
	# At tile_size 64 every distance doubles: bottom-centre (64, 128),
	# anchor scaled (64, 192), top-left (0, -64).
	var tl: Vector2 = SpriteLibrary.draw_top_left(Vector2.ZERO, fp, anchor, 64)
	if tl != Vector2(0.0, -64.0):
		failures.append("(5) smelter at tile_size 64: top_left %s, expected (0, -64)" % tl)
	# And the identity from sub-case (2) still holds, with the anchor scaled.
	var scale: float = 64.0 / float(SpriteLibrary.SPRITE_PX_PER_TILE)
	if tl + anchor * scale != Vector2(64.0, 128.0):
		failures.append("(5) scaled anchor does not land on the footprint bottom-centre: %s != (64, 128)"
			% (tl + anchor * scale))

# ===========================================================================
# (6) `cell_tiles[1]` IS NOT FOOTPRINT DEPTH.
#
# The smelter's cell_tiles is [2, 3] and its game footprint is 2x2. Reading
# cell_tiles[1] as depth is the single most inviting misreading of this
# contract, because for the chest and the pole it is only off by one tile in a
# direction that happens to look plausible. This sub-case measures the cost so
# the number is on record: 32 px, one full tile, straight down.
# ===========================================================================
static func _case_6_cell_tiles_y_is_not_footprint_depth(failures: Array) -> void:
	var anchor := Vector2(32.0, 96.0)
	var correct: Vector2 = SpriteLibrary.draw_top_left(Vector2.ZERO, Vector2i(2, 2), anchor, TS)
	var misread: Vector2 = SpriteLibrary.draw_top_left(Vector2.ZERO, Vector2i(2, 3), anchor, TS)
	if correct == misread:
		failures.append("(6) reading cell_tiles[1] as footprint depth no longer changes the smelter's placement — the fixture has stopped discriminating")
	if misread.y - correct.y != 32.0:
		failures.append("(6) expected the misreading to drop the smelter by exactly 32 px, got %f" % [misread.y - correct.y])
	# And confirm the game's own table says 2, not 3.
	if Buildings.footprint_of(Buildings.Type.SMELTER) != Vector2i(2, 2):
		failures.append("(6) Buildings.footprint_of(SMELTER) is %s, not (2, 2) — this test's premise changed"
			% Buildings.footprint_of(Buildings.Type.SMELTER))

# ===========================================================================
# (7) The glow pulse. Pinned here rather than in the manifest suite because
# it is pure maths, like the anchor: bounded, symmetric, and driven by a phase
# rather than by elapsed seconds.
#
# The tick-vs-wall-clock DECISION is argued in sprite_library.gd; what this
# pins is that the function it produced takes a phase and nothing else, so no
# later edit can quietly reintroduce a wall clock without changing the
# signature this sub-case calls.
# ===========================================================================
static func _case_7_glow_pulse_is_bounded_and_state_driven(failures: Array) -> void:
	for p in [0.0, 0.13, 0.25, 0.5, 0.77, 1.0]:
		var a: float = SpriteLibrary.glow_alpha(p)
		if a < SpriteLibrary.GLOW_ALPHA_MIN - 0.0001 or a > SpriteLibrary.GLOW_ALPHA_MAX + 0.0001:
			failures.append("(7) glow_alpha(%f) = %f is outside [%f, %f]"
				% [p, a, SpriteLibrary.GLOW_ALPHA_MIN, SpriteLibrary.GLOW_ALPHA_MAX])
	# Phase 0 and phase 1 must both be at the trough: the pulse has to close
	# its loop, or a smelter finishing a cycle jumps in brightness.
	if absf(SpriteLibrary.glow_alpha(0.0) - SpriteLibrary.GLOW_ALPHA_MIN) > 0.0001:
		failures.append("(7) glow_alpha(0) = %f, expected the trough %f"
			% [SpriteLibrary.glow_alpha(0.0), SpriteLibrary.GLOW_ALPHA_MIN])
	if absf(SpriteLibrary.glow_alpha(1.0) - SpriteLibrary.GLOW_ALPHA_MIN) > 0.0001:
		failures.append("(7) glow_alpha(1) = %f, expected the trough %f"
			% [SpriteLibrary.glow_alpha(1.0), SpriteLibrary.GLOW_ALPHA_MIN])
	# Out-of-range phases clamp rather than wrapping to a random brightness.
	if SpriteLibrary.glow_alpha(-3.0) != SpriteLibrary.glow_alpha(0.0):
		failures.append("(7) glow_alpha(-3) does not clamp to glow_alpha(0)")
	if SpriteLibrary.glow_alpha(9.0) != SpriteLibrary.glow_alpha(1.0):
		failures.append("(7) glow_alpha(9) does not clamp to glow_alpha(1)")
	# GLOW_PULSES_PER_CYCLE = 2 means a peak at quarter-phase.
	if absf(SpriteLibrary.glow_alpha(0.25) - SpriteLibrary.GLOW_ALPHA_MAX) > 0.0001:
		failures.append("(7) with 2 pulses per cycle, glow_alpha(0.25) should be the peak %f, got %f"
			% [SpriteLibrary.GLOW_ALPHA_MAX, SpriteLibrary.glow_alpha(0.25)])
	# A smelter that is NOT smelting must report "do not pulse" (-1), not 0.0
	# — 0.0 is a legal phase and would leave the glow drawn at trough alpha.
	var idle: Building = Buildings.make(Buildings.Type.SMELTER, Vector2i(0, 0))
	if idle != null:
		idle.state["state"] = Smelter.STATE_IDLE
		if SpriteLibrary.glow_phase_for(idle) >= 0.0:
			failures.append("(7) an IDLE smelter reports glow phase %f; a non-working machine must report < 0 so no glow is drawn at all"
				% SpriteLibrary.glow_phase_for(idle))
		# A chest has no glow concept at all.
		var chest: Building = Buildings.make(Buildings.Type.CHEST, Vector2i(0, 0))
		if chest != null and SpriteLibrary.glow_phase_for(chest) >= 0.0:
			failures.append("(7) a chest reports a glow phase")
