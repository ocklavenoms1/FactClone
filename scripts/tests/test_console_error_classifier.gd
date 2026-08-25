extends RefCounted

## CONSOLE OUTPUT CLASSIFIER — every message this file can emit, judged.
##
## `Console._is_refusal` decides whether a command's reply is drawn in
## ERROR_COLOR or TEXT_COLOR. Its predecessor `_looks_like_error` matched
## ERROR-shaped prose and defaulted to "normal output", so a refusal it did not
## recognise rendered exactly like a success. Twelve of them did.
##
## ---------------------------------------------------------------------------
## THE ASSERTION THIS FILE HAS TO MAKE
## ---------------------------------------------------------------------------
## "The test must fail if a future message is added that reads as a refusal but
## classifies as success." A test cannot read prose, so it cannot know a NEW
## message is a refusal — unless the question is turned round:
##
##     EVERY message this file can emit must classify as a refusal,
##     UNLESS it is one of the successes listed here by hand.
##
## The message list is SCANNED OUT OF console.gd's source rather than
## transcribed, so a message added tomorrow is in this test tomorrow. If it
## classifies as a refusal (the default) it passes silently, which is correct —
## red is the safe colour. If it classifies as a SUCCESS and is not on the
## hand-written list below, this file goes red and names it. That is the
## required property, and it is the only arrangement that has it.
##
## The reverse rot is guarded too: every entry in SUCCESS_MESSAGES must still be
## found in the source, so the list cannot quietly outlive the message.
##
## ---------------------------------------------------------------------------
## WHAT "EVERY MESSAGE" MEANS, AND THE PART THE SCAN CANNOT SEE
## ---------------------------------------------------------------------------
## The scan finds `return "…"` string literals — 79 of them. Five more outputs
## are built by appending to an array and returning `"\n".join(lines)`, and a
## regex over return statements sees only the `"\n"`. Those five are enumerated
## by hand in JOINED_OUTPUTS with a representative first line, AND sub-case (4)
## asserts each producing function still exists, so the hand-written half cannot
## silently stop corresponding to anything.
##
## SKIPPED, with reasons, rather than filtered by a clever rule that might eat a
## real message: `return ""` (empty input; `_submit_line` never appends it) and
## `_color_to_bbcode`'s `"#%02x%02x%02x"` (a colour literal, not console output).
##
## ---------------------------------------------------------------------------
## FORMAT SPECIFIERS ARE FILLED TWICE
## ---------------------------------------------------------------------------
## These literals carry `%s` / `%d` / `%.1f`. Each is rendered in two variants —
## `%s` as a tile "(3, 4)" and as a bare word "wibble" — and BOTH must classify
## the same way. One variant alone would miss a rule that only fires on
## parenthesised text, which is exactly the class of mistake the old
## `begins_with("tile (")` rule was.

const ConsoleScript = preload("res://scripts/ui/console.gd")
const CONSOLE_PATH: String = "res://scripts/ui/console.gd"

## Literals that are not console output. Listed, not pattern-matched.
const SKIP_LITERALS: Array = [
	"",                     # empty input; _submit_line returns before appending
	"\\n",                  # the separator in `"\n".join(lines)` — see JOINED_OUTPUTS
	"#%02x%02x%02x",        # _color_to_bbcode; a colour, not a message
]

## Outputs assembled from an array and returned via `"\n".join(lines)`, which
## the return-literal scan cannot see. First line is representative; the
## classifier only ever looks at prefixes and needles, and every needle used
## lives on the first two lines of these.
##
## `_format_tile_detail` appears TWICE on purpose: in bounds it emits a Soil row
## and is a success; out of bounds it emits "(out of world bounds)" and is a
## refusal. Same function, same prefix, opposite verdicts — this pair is why the
## classifier's tile rule is a needle rather than a prefix.
const JOINED_OUTPUTS: Array = [
	# [producing function, is_success, sample text]
	["_cmd_help", true, "Commands (type 'help <cmd>' for usage):\n  clear\n  destroy"],
	["_cmd_sprites", true, "[sprites] dir=res://art/sprites declared=3 loaded=3 failed=0 flag=true"],
	["_format_tile_detail", true, "Tile (3, 4):\n  Soil: 100 / 100\n  Base: Grass, Overlay: None"],
	["_format_tile_detail", false, "Tile (3, 4):\n  (out of world bounds)"],
	["_format_tile_grid", true, "Soil grid centered on (3, 4), radius 1:\n         3    4\n    3 100 100"],
]

## THE HAND-WRITTEN HALF. Every message that is allowed to render as normal
## output, as it appears in the SOURCE (before format-filling). Adding a row
## here is the review moment: it is a claim that this message means the command
## succeeded.
const SUCCESS_MESSAGES: Array = [
	"World seed: %d",
	"Added %d× %s to inventory.",
	"Added %d× %s (inventory partially full — %d items dropped).",
	"Player → tile %s.",
	"Tile %s soil → %d.",
	"Depleted %d tiles around %s by %d.",
	"Tile %s fertilized: %s (%.1fs).",
	"Placed %s at %s (auto-set %s overlay).",
	"Placed %s at %s (dir %s).",
	"Removed %s from %s.",
	"Cleared player inventory (%d slots).",
	"Cleared chest at %s.",
	"Tick speed → %.2f× (was %.2fx).",
	"Tile %s → WASTELAND (scarred). Apply Premium Compost to restore.",
]

## The twelve refusals the OLD classifier drew as normal output, with their
## line numbers at the time of the fix. Kept verbatim so the regression has a
## name and a shape rather than only a count — if a future rewrite of
## SUCCESS_SHAPES lets any of these through again, sub-case (3) says which.
const OLD_MISCLASSIFIED: Array = [
	[495, "Count must be > 0 (got 3)."],
	[512, "Tile (3, 4) is outside world bounds [3, 3)."],
	[528, "Tile (3, 4) is outside world bounds."],
	[556, "Radius must be >= 0 (got 3)."],
	[585, "Tier must be 'low', 'mid', or 'high' (got 'wibble')."],
	[588, "Tile (3, 4) is outside world bounds."],
	[614, "Direction 'wibble' invalid. Use E|S|W|N or 0|1|2|3."],
	[617, "Tile (3, 4) is outside world bounds."],
	[656, "Tile (3, 4) is outside world bounds."],
	[697, "Building at (3, 4) is not a Chest."],
	[744, "Tile (3, 4) is outside world bounds."],
	[769, "Radius must be >= 0 (got 3)."],
]

static func test_name() -> String:
	return "console output classifier (every message console.gd can emit is a refusal unless listed; the twelve that used to read as successes)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []

	var scanned: Array = _scan_return_literals()
	# A FLOOR, not an equality: adding a console command legitimately raises the
	# count and should not redden anything. 79 at the time of writing; 70 leaves
	# room for a command to be retired and still catches the regex silently
	# matching nothing, which would make every sub-case below vacuously green.
	if scanned.size() < 70:
		failures.append("(0) the source scan found only %d return literals in %s; it found 79 when this test was written, so the regex or the file layout changed and every sub-case below is now measuring nothing"
			% [scanned.size(), CONSOLE_PATH])

	var counts: Array = _case_1_nothing_unlisted_classifies_as_success(scanned, failures)
	_case_2_every_listed_success_exists_and_classifies(scanned, failures)
	_case_3_the_twelve_are_refusals(failures)
	_case_4_joined_producers_still_exist(failures)
	_case_5_the_default_is_refusal(failures)

	if failures.is_empty():
		return { "ok": true, "message": "5 sub-cases pass: %d messages scanned from console.gd (%d literal returns + %d joined producers), %d classify as normal output and every one of them is on the hand-written success list; the remaining %d are refusals, including all twelve that the old _looks_like_error drew as successes; and an unrecognised message defaults to refusal" % [counts[0], scanned.size(), JOINED_OUTPUTS.size(), counts[1], counts[0] - counts[1]] }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 12))] }

# ---------------------------------------------------------------------------
# the scan
# ---------------------------------------------------------------------------

## Every `return "…"` literal in console.gd, as [line_number, raw_literal].
## Raw meaning still escaped and still carrying its format specifiers — the
## caller unescapes and fills, so SUCCESS_MESSAGES can be written as they appear
## in the source.
static func _scan_return_literals() -> Array:
	var src: String = FileAccess.get_file_as_string(CONSOLE_PATH)
	var out: Array = []
	var re := RegEx.new()
	# The literal, allowing escaped quotes inside it.
	re.compile("return \"((?:[^\"\\\\]|\\\\.)*)\"")
	var lines: PackedStringArray = src.split("\n")
	for i in range(lines.size()):
		# ⚠ COMMENT LINES ARE SKIPPED, and this is not cosmetic. console.gd's own
		# block comment about the classifier quotes `return "…"` while explaining
		# how the messages were measured, and without this the scan judged that
		# fragment as if it were a message the console could emit. Measured: 80
		# hits with comments included, 79 without. It passed either way — "…"
		# classifies as a refusal — which is precisely why it had to be caught by
		# counting rather than by the suite going red.
		#
		# LIMITATION: only whole-line comments. A trailing `# return "x"` after
		# code on the same line would still be scanned. None exists today.
		if lines[i].strip_edges().begins_with("#"):
			continue
		var m: RegExMatch = re.search(lines[i])
		if m == null:
			continue
		var raw: String = m.get_string(1)
		if SKIP_LITERALS.has(raw):
			continue
		out.append([i + 1, raw])
	return out

static func _unescape(s: String) -> String:
	return s.replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"")

## Both renderings of one format string. `%s` is the only specifier whose shape
## can change a verdict, so it gets the two shapes that matter.
static func _variants(fmt: String) -> Array:
	var base: String = fmt
	var re := RegEx.new()
	re.compile("%\\d*\\.\\d+f")
	base = re.sub(base, "3.00", true)
	base = base.replace("%d", "3")
	return [base.replace("%s", "(3, 4)"), base.replace("%s", "wibble")]

# ===========================================================================
# (1) THE REQUIRED PROPERTY. Nothing this file can emit classifies as normal
# output unless a human put it on SUCCESS_MESSAGES.
#
# A future refusal is not on that list, so if a rewritten classifier starts
# calling it a success, this reddens and names it. A future SUCCESS is also not
# on the list — it classifies as a refusal, renders red, and passes here. That
# asymmetry is deliberate: red is the safe colour, and "a success renders red"
# is a cosmetic bug the author sees the first time they run the command.
#
# Returns [total_messages, success_count] for the pass message.
# ===========================================================================
static func _case_1_nothing_unlisted_classifies_as_success(scanned: Array, failures: Array) -> Array:
	var allowed: Dictionary = {}
	for s in SUCCESS_MESSAGES:
		for v in _variants(str(s)):
			allowed[v] = true
	var total: int = 0
	var successes: int = 0
	for row in scanned:
		var line_no: int = int(row[0])
		var fmt: String = _unescape(str(row[1]))
		for v in _variants(fmt):
			total += 1
			if ConsoleScript._is_refusal(v):
				continue
			successes += 1
			if not allowed.has(v):
				failures.append("(1) console.gd:%d emits \"%s\", which classifies as NORMAL OUTPUT but is not on SUCCESS_MESSAGES. If it is a refusal, the classifier is drawing a rejected command like a successful one — that is the bug this file exists to catch. If it really is a success, add it to SUCCESS_MESSAGES and say so."
					% [line_no, v.replace("\n", "\\n")])
	for row in JOINED_OUTPUTS:
		var fn: String = str(row[0])
		var want_success: bool = bool(row[1])
		var sample: String = str(row[2])
		total += 1
		var is_refusal: bool = ConsoleScript._is_refusal(sample)
		if want_success:
			successes += 1
			if is_refusal:
				failures.append("(1) %s's output \"%s\" classifies as a REFUSAL; it is a successful command's report and would render red"
					% [fn, sample.replace("\n", "\\n")])
		elif not is_refusal:
			failures.append("(1) %s's out-of-bounds output \"%s\" classifies as NORMAL OUTPUT — a tile query that could not answer would render like one that did"
				% [fn, sample.replace("\n", "\\n")])
	return [total, successes]

# ===========================================================================
# (2) THE LIST CANNOT ROT. Every SUCCESS_MESSAGES entry must still be a literal
# in console.gd, and must still classify as normal output.
#
# Without this, rewording "Placed %s at %s (dir %s)." to something the
# classifier does not recognise would leave a stale allowlist entry behind and
# the reworded message rendering red, with nothing saying so.
# ===========================================================================
static func _case_2_every_listed_success_exists_and_classifies(scanned: Array, failures: Array) -> void:
	var in_source: Dictionary = {}
	for row in scanned:
		in_source[_unescape(str(row[1]))] = int(row[0])
	for s in SUCCESS_MESSAGES:
		var fmt: String = str(s)
		if not in_source.has(fmt):
			failures.append("(2) SUCCESS_MESSAGES lists \"%s\" but no `return` in console.gd emits it any more — either it was reworded (update this list AND check Console.SUCCESS_SHAPES still matches it) or it was deleted (drop the row)."
				% fmt.replace("\n", "\\n"))
			continue
		for v in _variants(fmt):
			if ConsoleScript._is_refusal(v):
				failures.append("(2) console.gd:%d's \"%s\" is listed as a success but classifies as a REFUSAL — Console.SUCCESS_SHAPES no longer covers it, so a working command renders red"
					% [int(in_source[fmt]), v.replace("\n", "\\n")])

# ===========================================================================
# (3) THE TWELVE, BY NAME. The regression this task fixed, pinned as text.
#
# Sub-case (1) would catch a repeat in the aggregate; this one says WHICH, and
# survives the messages being reworded later (these are the strings as they read
# at the time of the fix, not a live scan).
# ===========================================================================
static func _case_3_the_twelve_are_refusals(failures: Array) -> void:
	for row in OLD_MISCLASSIFIED:
		var msg: String = str(row[1])
		if not ConsoleScript._is_refusal(msg):
			failures.append("(3) console.gd:%d \"%s\" classifies as normal output again — this is one of the twelve refusals the old _looks_like_error drew like successes"
				% [int(row[0]), msg])
	# The one message that DID carry the wording the old rule was written
	# against. It must still be a refusal, and it is the reason the tile rule is
	# a needle rather than a prefix.
	if not ConsoleScript._is_refusal("Tile (3, 4):\n  (out of world bounds)"):
		failures.append("(3) _format_tile_detail's out-of-bounds output classifies as normal output")

# ===========================================================================
# (4) THE HAND-WRITTEN HALF STILL CORRESPONDS TO SOMETHING.
#
# JOINED_OUTPUTS names five producing functions. If one is renamed or deleted,
# its row becomes a string this test carries around and judges while nothing in
# the game emits it — a green assertion about nothing, which is the same shape
# as the dropped test registration in NOTES.md.
# ===========================================================================
static func _case_4_joined_producers_still_exist(failures: Array) -> void:
	var src: String = FileAccess.get_file_as_string(CONSOLE_PATH)
	for row in JOINED_OUTPUTS:
		var fn: String = str(row[0])
		if src.find("func %s(" % fn) < 0:
			failures.append("(4) JOINED_OUTPUTS names %s, which no longer exists in console.gd — its row is judging a message nothing emits" % fn)
	# And the join idiom itself: if these stopped being built that way, the scan
	# would start seeing them and JOINED_OUTPUTS would be double-counting.
	if src.find("\"\\n\".join(lines)") < 0:
		failures.append("(4) console.gd no longer builds any output with `\"\\n\".join(lines)`; JOINED_OUTPUTS is describing a mechanism that is gone")

# ===========================================================================
# (5) THE DEFAULT IS REFUSAL. The whole point of the change.
#
# A message matching nothing must come back red. If someone reinstates an
# error-shaped allowlist, this is the sub-case that says so — every other
# sub-case above would still pass under the OLD classifier for the messages it
# happened to cover.
# ===========================================================================
static func _case_5_the_default_is_refusal(failures: Array) -> void:
	for msg in [
		"Frobnicated the widget.",                       # plausible future success
		"The quick brown fox.",                          # no shape at all
		"",                                              # empty
		"wibble",                                        # one word
		"Something went sideways and nobody knows why",   # plausible future refusal
	]:
		if not ConsoleScript._is_refusal(msg):
			failures.append("(5) \"%s\" matched a success shape; an unrecognised message must default to refusal" % msg)
	# And a success shape must still be recognisable, or (5) passes by the
	# classifier having become "always true", which would fail (1) and (2) but
	# is worth naming here where the default is the subject.
	if ConsoleScript._is_refusal("Placed Chest at (3, 4) (dir E)."):
		failures.append("(5) a known success now classifies as a refusal — the classifier has degenerated to always-refuse")
