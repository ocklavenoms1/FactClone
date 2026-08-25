extends RefCounted

## INSERTER TIER COLOURS — no two tiers may be a shade of one another.
##
## `inserter.gd:87` (`BODY_COLOR_BY_TYPE`) is the whole of the map-level tier
## identity: four rectangles that differ only in fill. Adding a fifth tier is
## one dictionary row, and nothing today stops that row being a colour a player
## cannot tell from an existing one. This file is the thing that stops it.
##
## ---------------------------------------------------------------------------
## WHY CIE L*a*b* ΔE AND NOT RGB EUCLIDEAN DISTANCE
## ---------------------------------------------------------------------------
## sRGB is not perceptually uniform: equal steps in the cube are not equal steps
## to the eye, and the error is large enough to REORDER these very colours.
## Measured over the four shipped tiers with this file's own maths:
##
##   pair                            ΔE76     RGB euclidean
##   ------------------------------  -------  -------------
##   INSERTER    ↔ LONG_REACH         31.61        0.1972
##   FAST        ↔ ELECTRIC           34.20        0.3000
##   INSERTER    ↔ FAST               48.68        0.4243
##   INSERTER    ↔ ELECTRIC           58.22        0.6557
##   FAST        ↔ LONG_REACH         64.47        0.5770
##   LONG_REACH  ↔ ELECTRIC           84.66        0.8360
##
## The two rankings DISAGREE: RGB calls INSERTER↔ELECTRIC (0.6557) further apart
## than FAST↔LONG_REACH (0.5770), while ΔE puts them the other way round
## (58.22 < 64.47). A floor set in RGB would therefore be a floor on the wrong
## quantity — it would admit a pair the eye finds closer than one it rejects.
##
## LIMITATION, STATED RATHER THAN HIDDEN: this is ΔE*76, the 1976 CIE formula.
## It is a plain Euclidean distance in L*a*b*, which is far better than sRGB but
## still over-weights differences among saturated blues. Every pair here clears
## the floor by at least 26% (the tightest is 31.61 against a floor of 25), so
## the formula's error cannot flip a verdict at today's values. If a future pair ever lands within ~15% of the floor, upgrade
## this to CIEDE2000 rather than arguing about the margin.
##
## Godot `Color` components are treated as sRGB (non-linear) throughout the 2D
## canvas path, so the conversion below linearises first. Skipping that step is
## the single most common way to get L*a*b* wrong.
##
## ---------------------------------------------------------------------------
## THE FLOOR: ΔE ≥ 25
## ---------------------------------------------------------------------------
## A just-noticeable difference under ideal side-by-side viewing is ΔE ≈ 2.3.
## That is the wrong bar. These colours are read at a glance, on 32 px sprites,
## against varied terrain, MULTIPLIED by a state tint, never side by side. The
## bar is "obviously a different machine", not "technically a different colour".
##
## 25 is chosen against the measurement, not picked round:
##   - It is ~11x the JND (25 / 2.3 = 10.9), which is the "different colour at
##     a glance" region rather than the "tell them apart if you look" one.
##   - The tightest shipped pair is ΔE 31.61 (the two warm browns, bronze vs
##     rust), 26% above the floor. An intentional retune of those two does not
##     redden this file on the first nudge — but halving their separation does.
##   - Sub-case (3) proves the floor bites: two colours 0.02 apart in one channel
##     measure ΔE 2.86 and are rejected by name.
##
## ---------------------------------------------------------------------------
## `BODY_COLOR_DEFAULT` IS AN INTENTIONAL ALIAS, AND THE CODE SAYS SO
## ---------------------------------------------------------------------------
## `BODY_COLOR_DEFAULT` is byte-identical to `BODY_COLOR_BY_TYPE[INSERTER]`
## (ΔE 0.00), because the table's own docstring legislates "default fallback is
## bronze (basic)". So a naive "every pair in the set must differ" assertion is
## false on arrival.
##
## Handled by NAMING the alias rather than dropping the default from the set:
## sub-case (2) pins DEFAULT == the INSERTER row exactly, and sub-case (1) then
## skips exactly that one pair and requires every OTHER pair — including every
## tier against DEFAULT — to clear the floor. Consequences, both wanted:
##   - Retuning the basic tier's bronze without moving the default reddens (2).
##   - A fifth tier authored at the default's bronze reddens (1), because it is
##     not the pair (2) blessed.

const FLOOR_DE: float = 25.0

## Below this the "flat dark grey" claim on `TINT_NO_POWER` stops being true.
## Measured live in sub-case (4); the shipped value is 0.025.
const GREY_CHANNEL_SPREAD_MAX: float = 0.05

static func test_name() -> String:
	return "inserter tier colours (pairwise CIE L*a*b* ΔE floor over BODY_COLOR_BY_TYPE + BODY_COLOR_DEFAULT; every tier table carries every tier)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	var min_pair: Array = _case_1_every_pair_clears_the_floor(failures)
	_case_2_default_is_the_basic_tier_exactly(failures)
	_case_3_the_floor_actually_bites(failures)
	_case_4_electric_stall_tints_stay_distinct(failures)
	_case_5_every_tier_table_has_every_tier(failures)

	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: all %d colour pairs clear ΔE %.1f (tightest live pair %s ↔ %s at ΔE %.2f); BODY_COLOR_DEFAULT is exactly the INSERTER row; a 0.02-channel near-duplicate is rejected by name; the electric tier's four state tints stay ≥ ΔE %.1f apart and NO_POWER still lands on a flat grey; and BODY_COLOR / CYCLE_TICKS / REACH / ARM_LENGTH all carry the same tier set" % [_pair_count(), FLOOR_DE, min_pair[0], min_pair[1], float(min_pair[2]), FLOOR_DE] }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# ---------------------------------------------------------------------------
# colour maths — sRGB → linear → CIE XYZ (D65) → CIE L*a*b*
# ---------------------------------------------------------------------------

## sRGB transfer function, inverted. The piecewise linear segment near black
## matters here: three of the tint-multiplied colours in sub-case (4) sit under
## 0.25, where the pure 2.4 power curve is visibly wrong.
static func _srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)

## D65 white point, the reference sRGB is defined against.
const WHITE_X: float = 0.95047
const WHITE_Y: float = 1.00000
const WHITE_Z: float = 1.08883

static func _lab_f(t: float) -> float:
	if t > 0.008856:
		return pow(t, 1.0 / 3.0)
	return 7.787 * t + 16.0 / 116.0

## CIE L*a*b* triple for a Godot Color. Alpha is ignored — nothing in
## BODY_COLOR_BY_TYPE varies it, and a colour-distance claim about a
## half-transparent fill would depend on what is behind it.
static func to_lab(c: Color) -> Vector3:
	var r: float = _srgb_to_linear(c.r)
	var g: float = _srgb_to_linear(c.g)
	var b: float = _srgb_to_linear(c.b)
	var x: float = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
	var y: float = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
	var z: float = r * 0.0193339 + g * 0.1191920 + b * 0.9503041
	var fx: float = _lab_f(x / WHITE_X)
	var fy: float = _lab_f(y / WHITE_Y)
	var fz: float = _lab_f(z / WHITE_Z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))

## ΔE*76 — Euclidean distance in L*a*b*. See the header for why not ΔE2000.
static func delta_e(a: Color, b: Color) -> float:
	return to_lab(a).distance_to(to_lab(b))

## The comparison set: every tier row, plus the default fallback. Ordered so
## failure messages name tiers in table order rather than dictionary-hash order.
static func _comparison_set() -> Array:
	var out: Array = []
	for t in Inserter.BODY_COLOR_BY_TYPE.keys():
		out.append([Buildings.name_of(t), Inserter.BODY_COLOR_BY_TYPE[t], t])
	out.append(["BODY_COLOR_DEFAULT", Inserter.BODY_COLOR_DEFAULT, -1])
	return out

static func _pair_count() -> int:
	var n: int = _comparison_set().size()
	return n * (n - 1) / 2

# ===========================================================================
# (1) THE ASSERTION. Every pair in {tiers} ∪ {DEFAULT} clears the floor, with
# the one blessed alias (DEFAULT ≡ INSERTER, pinned by sub-case 2) skipped.
#
# Returns [name_a, name_b, dE] for the TIGHTEST live pair, which goes into the
# result message so the margin travels with the verdict rather than having to be
# recomputed by hand. ⚠ `test_runner.gd:155` prints only the suite NAME on PASS
# — the message surfaces on FAIL. So this is documentation for whoever is
# already reading a red run, not a green-run readout.
# ===========================================================================
static func _case_1_every_pair_clears_the_floor(failures: Array) -> Array:
	var entries: Array = _comparison_set()
	var min_d: float = 1.0e9
	var min_a: String = "?"
	var min_b: String = "?"
	for i in range(entries.size()):
		for j in range(i + 1, entries.size()):
			var na: String = str(entries[i][0])
			var nb: String = str(entries[j][0])
			var ca: Color = entries[i][1]
			var cb: Color = entries[j][1]
			# The blessed alias, and ONLY that exact pair. Identified by the
			# type keys rather than by "the colours happen to be equal", so a
			# second row that drifted onto bronze is not quietly excused too.
			if _is_blessed_alias(entries[i], entries[j]):
				continue
			var d: float = delta_e(ca, cb)
			if d < min_d:
				min_d = d
				min_a = na
				min_b = nb
			if d < FLOOR_DE:
				failures.append("(1) %s %s and %s %s are ΔE %.2f apart, below the ΔE %.1f floor — a player cannot tell these two tiers apart on the map. Repick one, or lower FLOOR_DE with a reason."
					% [na, str(ca), nb, str(cb), d, FLOOR_DE])
	return [min_a, min_b, min_d]

## True for the DEFAULT ↔ INSERTER pair in either order. Nothing else.
static func _is_blessed_alias(a: Array, b: Array) -> bool:
	var ka: int = int(a[2])
	var kb: int = int(b[2])
	if ka == -1 and kb == Buildings.Type.INSERTER:
		return true
	if kb == -1 and ka == Buildings.Type.INSERTER:
		return true
	return false

# ===========================================================================
# (2) The alias is REAL, not assumed. `BODY_COLOR_BY_TYPE`'s docstring says
# "default fallback is bronze (basic)"; this is the assertion that makes the
# sentence load-bearing.
#
# It also protects sub-case (1)'s skip: if someone retunes the basic tier and
# leaves the default behind, (1) would go on skipping a pair that is no longer
# an alias, and a genuinely-indistinguishable pair could hide behind the
# exemption. That cannot happen while this sub-case is green.
# ===========================================================================
static func _case_2_default_is_the_basic_tier_exactly(failures: Array) -> void:
	if not Inserter.BODY_COLOR_BY_TYPE.has(Buildings.Type.INSERTER):
		failures.append("(2) BODY_COLOR_BY_TYPE has no INSERTER row at all")
		return
	var basic: Color = Inserter.BODY_COLOR_BY_TYPE[Buildings.Type.INSERTER]
	if Inserter.BODY_COLOR_DEFAULT != basic:
		failures.append("(2) BODY_COLOR_DEFAULT %s is no longer the INSERTER row %s (ΔE %.2f). The table's docstring says the fallback IS bronze/basic; either restore it, or update the docstring AND the alias skip in sub-case (1)."
			% [str(Inserter.BODY_COLOR_DEFAULT), str(basic), delta_e(Inserter.BODY_COLOR_DEFAULT, basic)])
	# And the accessor must actually return it on a lookup miss, or the whole
	# fallback story is a constant nobody reads.
	var stray := Building.new(-999, Vector2i.ZERO, {})
	if Inserter.body_color(stray) != Inserter.BODY_COLOR_DEFAULT:
		failures.append("(2) Inserter.body_color() on an unlisted type returned %s, not BODY_COLOR_DEFAULT %s"
			% [str(Inserter.body_color(stray)), str(Inserter.BODY_COLOR_DEFAULT)])

# ===========================================================================
# (3) THE FLOOR BITES. Sub-case (1) passing tells you nothing unless a
# near-duplicate would fail it — this is the same reason
# test_sprite_manifest.gd carries a positive control.
#
# Two synthetic tiers 0.02 apart in one channel: the kind of "I'll just darken
# the bronze slightly for the stack inserter" edit that reads as reasonable in
# a diff and is invisible in the game.
# ===========================================================================
static func _case_3_the_floor_actually_bites(failures: Array) -> void:
	var a := Color(0.55, 0.45, 0.30)
	var b := Color(0.55, 0.45, 0.32)
	var d: float = delta_e(a, b)
	if d >= FLOOR_DE:
		failures.append("(3) two colours 0.02 apart in one channel measured ΔE %.2f, at or above the ΔE %.1f floor — the floor is set too low to catch a near-duplicate tier"
			% [d, FLOOR_DE])
	# And the metric must not be trivially zero-ish for everything: a real pair
	# has to clear it, or ΔE could be returning garbage and (1) would pass by
	# accident on a uniformly tiny scale.
	var far: float = delta_e(Color(0.0, 0.0, 0.0), Color(1.0, 1.0, 1.0))
	if far < 99.0 or far > 101.0:
		failures.append("(3) ΔE(black, white) = %.2f, expected 100.00 — the L*a*b* conversion is wrong, so every other number in this file is meaningless" % far)

# ===========================================================================
# (4) THE STALL TINTS ON THE ELECTRIC TIER.
#
# `inserter.gd`'s TINT_NO_POWER docstring makes two perceptual claims in prose:
# that against the electric tier's cyan it "lands on a flat dark grey", and
# that IDLE / NO_FUEL / NO_POWER "all remain distinct". Both are measurable and
# neither was measured. This is the measurement.
#
# ⚠ SCOPED TO THE ELECTRIC TIER ON PURPOSE, exactly as the comment scopes
# itself. The same check on the burner bodies FAILS and should: IDLE vs NO_FUEL
# on LONG_REACH is ΔE 12.29 and on INSERTER 15.74, both under the floor. That
# is a real legibility finding about the burner tiers' stall tints — but the
# comment does not claim otherwise about them, and widening this sub-case would
# turn a colour test into an unrequested retune of four constants. Recorded
# here so the number is not rediscovered from scratch.
# ===========================================================================
static func _case_4_electric_stall_tints_stay_distinct(failures: Array) -> void:
	var body: Color = Inserter.BODY_COLOR_BY_TYPE.get(Buildings.Type.ELECTRIC_INSERTER, Inserter.BODY_COLOR_DEFAULT)
	var tinted: Array = [
		["TINT_IDLE", _tint(body, Inserter.TINT_IDLE)],
		["TINT_NO_FUEL", _tint(body, Inserter.TINT_NO_FUEL)],
		["TINT_BLOCKED", _tint(body, Inserter.TINT_BLOCKED)],
		["TINT_NO_POWER", _tint(body, Inserter.TINT_NO_POWER)],
	]
	for i in range(tinted.size()):
		for j in range(i + 1, tinted.size()):
			var d: float = delta_e(tinted[i][1], tinted[j][1])
			if d < FLOOR_DE:
				failures.append("(4) on the electric tier's body %s, %s %s and %s %s are only ΔE %.2f apart (floor %.1f) — two stalls with different fixes would read the same on the map"
					% [str(body), str(tinted[i][0]), str(tinted[i][1]), str(tinted[j][0]), str(tinted[j][1]), d, FLOOR_DE])
	# "lands on a flat dark grey" — grey means the three channels agree.
	var np: Color = _tint(body, Inserter.TINT_NO_POWER)
	var spread: float = max(np.r, max(np.g, np.b)) - min(np.r, min(np.g, np.b))
	if spread > GREY_CHANNEL_SPREAD_MAX:
		failures.append("(4) TINT_NO_POWER on the electric body gives %s, channel spread %.3f > %.3f — inserter.gd's claim that it 'lands on a flat dark grey' no longer holds"
			% [str(np), spread, GREY_CHANNEL_SPREAD_MAX])

## What `Inserter.draw()` does to the body colour: per-channel multiply,
## clamped, alpha forced opaque. Mirrors the smelter/drill form.
static func _tint(body: Color, tint: Color) -> Color:
	return Color(
		clampf(body.r * tint.r, 0.0, 1.0),
		clampf(body.g * tint.g, 0.0, 1.0),
		clampf(body.b * tint.b, 0.0, 1.0),
		1.0,
	)

# ===========================================================================
# (5) A NEW TIER CANNOT ARRIVE WITHOUT A COLOUR.
#
# Sub-case (1) can only judge the rows that exist. A fifth tier added to
# CYCLE_TICKS_BY_TYPE but not to BODY_COLOR_BY_TYPE takes the bronze fallback
# and ships as a visual duplicate of the basic tier — the exact failure this
# file exists to prevent, arriving through the one door (1) does not watch.
#
# DERIVED from the sibling tables rather than from a hand-written tier list:
# a tier is not usable without a cycle length, so CYCLE_TICKS_BY_TYPE is the
# closest thing to a registry that exists. POWER_DEMAND_BY_TYPE is deliberately
# excluded — its docstring makes partial membership the definition of
# "electric", so requiring it to match would be asserting the opposite of the
# design.
# ===========================================================================
static func _case_5_every_tier_table_has_every_tier(failures: Array) -> void:
	var tables: Array = [
		["CYCLE_TICKS_BY_TYPE", Inserter.CYCLE_TICKS_BY_TYPE],
		["BODY_COLOR_BY_TYPE", Inserter.BODY_COLOR_BY_TYPE],
		["REACH_BY_TYPE", Inserter.REACH_BY_TYPE],
		["ARM_LENGTH_BY_TYPE", Inserter.ARM_LENGTH_BY_TYPE],
	]
	var reference: Dictionary = tables[0][1]
	for row in tables:
		var tname: String = str(row[0])
		var table: Dictionary = row[1]
		for t in reference.keys():
			if not table.has(t):
				failures.append("(5) %s has no row for %s, so that tier falls back to the default — for BODY_COLOR that means it renders as the basic tier's bronze and no other test notices"
					% [tname, Buildings.name_of(t)])
		for t in table.keys():
			if not reference.has(t):
				failures.append("(5) %s has a row for %s that CYCLE_TICKS_BY_TYPE does not — one of the two tables is out of date"
					% [tname, Buildings.name_of(t)])
