extends RefCounted

## A save this build is too OLD to read must survive being played past.
##
## Audit finding #21 (MEDIUM), docs/audits/2026-07-19-flaw-review.md —
## "forward-incompatible save is armed for destruction".
##
## `load_game` tells the player a forward-incompatible save is RECOVERABLE
## ("Update the game to load this save"), and then returns the same
## `success = false` that `main.gd`'s post-3.5 hotfix turns into a playable fresh
## world. The player is left standing in a world that saves over the file the
## dialog just told them to keep.
##
## SCOPED TO THE FORWARD-INCOMPAT CASE ONLY. The finding as written also names
## worldgen mismatch and migration failure, but CONVENTIONS.md sanctions the
## fresh-world fallthrough for both of those explicitly — "Migration returns
## `null` ... `main.gd`'s post-3.5 hotfix catches this and falls through to
## fresh-world generation" (Failure handling) and "Better to surface the failure
## and let the post-3.5 hotfix regenerate fresh" (Worldgen version is a separate
## axis). Sub-cases 5 and 6 are the regression guard on that narrowing: they pin
## those two paths as failure-with-a-message, which is exactly what `main.gd`
## keys its fresh-world generation off, and pin that neither preserves anything.
##
## WHAT THE ATOMIC WRITE ALREADY DID, AND WHAT IT DID NOT. Finding #12 made
## `save_game` rename the live save to `.bak` before moving the new one into
## place, so the FIRST F5 after the fallthrough moves the newer save aside
## rather than destroying it. Sub-case 2 asserts that mitigation directly, so it
## cannot be quietly lost. But `.bak` is a ROTATING slot: the second F5 moves the
## fresh world onto it and the newer save is gone. Sub-case 3 pins that rotation
## and pins the preserved copy surviving it. Two keypresses was the real window,
## not one, which is why the copy goes to a suffix `save_game` never writes.
##
## Sub-case index:
##   1. A save one version above SAVE_VERSION fails the load with the
##      forward-incompat message — naming both versions — and not a generic
##      corrupt-file message, and the copy is set aside before the call returns.
##   2. First F5. The copy still parses as the newer save. Also asserts the
##      `.bak` mitigation is genuinely in play at this point.
##   3. Second F5 rotates `.bak` onto the first fresh save — the newer save is
##      gone from there — while the preserved copy is still byte-identical to
##      the original fixture.
##   4. Only a newer `.bak` on disk and no primary. `save_exists()` still reports
##      a save, so `main.gd` calls `load_game`, and the copy is taken from the
##      backup rather than from a primary that does not exist.
##   5. Worldgen mismatch still fails with a message and preserves nothing.
##   6. Migration failure still fails with a message and preserves nothing.
##   7. With only the preserved copy left on disk, `save_exists()` reports no
##      save — the copy is kept for a future build, not offered to this one.
##   8. A worldgen mismatch reached only through `.bak` still fails the same way
##      and still preserves nothing. Reachability guard for the alert that
##      quotes a path the player is told to delete — see the note there.
##   9. A second refused save overwrites the first preserved copy: one
##      preservation slot per save slot, as `_preserve_incompatible` documents.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_forward_incompat.json"

## One above whatever this build writes, derived rather than hardcoded so the
## sub-cases keep meaning "from the next build" if SAVE_VERSION ever moves.
const FUTURE_BUMP: int = 1

## A field only the newer build knows about. Its survival is what makes the
## preserved copy useful to that build rather than merely present.
const FUTURE_FIELD: String = "some_future_field"
const FUTURE_MARKER: String = "written-by-a-newer-build"

## Below the v17 breaking-change reset point, so `_try_migrate` finds no
## registered step and the migration chain fails (sub-case 6).
const UNMIGRATABLE_VERSION: int = 14

const SEED_FUTURE: int = 61001
const SEED_FRESH_1: int = 61002
const SEED_FRESH_2: int = 61003

static func test_name() -> String:
	return "a forward-incompatible save survives being played past (audit #21)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	_scrub()

	_run_all(parent, failures)

	SaveSystem.save_path = orig_path
	_scrub()

	if failures.is_empty():
		return { "ok": true, "message": "9 sub-cases pass: a newer save fails with the forward-incompat message and is copied aside; the copy survives the first F5 and the .bak rotation the second one causes; a newer save reached only through .bak is preserved too; worldgen mismatch and migration failure still fail with a message and preserve nothing, including a worldgen mismatch reached only through .bak; the copy is not counted as a loadable save; a second refused save overwrites the first preserved copy" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

static func _run_all(parent: Node, failures: Array) -> void:
	var bak_path: String = TEST_SAVE_PATH + SaveSystem.BAK_SUFFIX
	var kept_path: String = TEST_SAVE_PATH + SaveSystem.INCOMPAT_SUFFIX
	var future_version: int = SaveSystem.SAVE_VERSION + FUTURE_BUMP

	# ===================================================================
	# (1) A newer save fails the load, and is copied aside.
	# ===================================================================
	if not _write_future_save(parent, SEED_FUTURE):
		failures.append("(1) PREMISE: could not produce the newer-save fixture")
		return
	# The bytes every later "still recoverable" claim is measured against.
	var original: PackedByteArray = FileAccess.get_file_as_bytes(TEST_SAVE_PATH)
	if original.is_empty():
		failures.append("(1) PREMISE: the fixture at %s is empty" % TEST_SAVE_PATH)
		return

	var r1: LoadResult = _load(parent)
	_check(failures, not r1.success,
		"(1) a save from a newer build cannot be read by this one and must not report success")
	# The message has to identify WHICH failure this is. A player told their save
	# is corrupt deletes it; a player told their game is out of date updates it.
	_check(failures, r1.error_message.find(str(future_version)) >= 0 and r1.error_message.find(str(SaveSystem.SAVE_VERSION)) >= 0,
		"(1) error_message must name both versions so this reads as 'your game is old', not 'your save is broken' — got '%s'" % r1.error_message)
	_check(failures, r1.error_message.find("corrupt") < 0,
		"(1) error_message must not describe a well-formed newer save as corrupt — got '%s'" % r1.error_message)
	_check(failures, not r1.used_backup,
		"(1) the primary was present and readable, so used_backup must be false")
	# Before the caller can act on the failure at all — main.gd generates the
	# fresh world the instant load_game returns.
	_check(failures, FileAccess.file_exists(kept_path),
		"(1) the copy at %s must exist by the time load_game returns; main.gd generates a fresh world immediately after" % kept_path)

	# ===================================================================
	# (2) First F5.
	# ===================================================================
	if not _save_fresh(parent, SEED_FRESH_1):
		failures.append("(2) PREMISE: save_game returned false")
		return
	_expect_kept(failures, "(2)", kept_path, future_version, SEED_FUTURE)
	# The finding #12 mitigation, asserted so it cannot silently regress: the
	# first F5 moves the newer save aside rather than destroying it. If this ever
	# flips, the two-keypress window this whole suite is about becomes one.
	var bak_2 = _read_json(bak_path)
	_check(failures, bak_2 != null and int(bak_2.get("version", -1)) == future_version,
		"(2) the atomic write is supposed to move the live save to %s, so it should still hold the newer save here — got %s" % [bak_path, str(bak_2)])

	# ===================================================================
	# (3) Second F5 — the rotation that used to be the end of the save.
	# ===================================================================
	if not _save_fresh(parent, SEED_FRESH_2):
		failures.append("(3) PREMISE: the second save_game returned false")
		return
	# PREMISE for this sub-case: the rotation really does overwrite. If .bak
	# still held the newer save, sub-case 3 would be testing nothing.
	var bak_3 = _read_json(bak_path)
	_check(failures, bak_3 != null and int(bak_3.get("world_seed", -1)) == SEED_FRESH_1,
		"(3) PREMISE: the second save rotates the first fresh save onto %s, overwriting the newer save that was there — expected seed %d, got %s" % [bak_path, SEED_FRESH_1, str(bak_3)])
	_expect_kept(failures, "(3)", kept_path, future_version, SEED_FUTURE)
	_check(failures, FileAccess.get_file_as_bytes(kept_path) == original,
		"(3) the preserved copy must still be byte-identical to the save that was on disk — a newer build has to be able to read it")

	# ===================================================================
	# (4) Only a newer .bak, no primary.
	# ===================================================================
	_scrub()
	if not _write_future_save(parent, SEED_FUTURE):
		failures.append("(4) PREMISE: could not produce the newer-save fixture")
		return
	# Move it to the backup slot and leave no primary — what a crash between
	# save_game's two renames leaves behind.
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEST_SAVE_PATH), ProjectSettings.globalize_path(bak_path))
	_check(failures, not FileAccess.file_exists(TEST_SAVE_PATH),
		"(4) PREMISE: the primary should be gone")
	# main.gd gates its whole load path on this call.
	_check(failures, SaveSystem.save_exists(),
		"(4) save_exists() counts the backup, so it must still report a save here")
	var r4: LoadResult = _load(parent)
	_check(failures, not r4.success, "(4) the backup is a newer save and must not load")
	_check(failures, r4.error_message.find(str(future_version)) >= 0,
		"(4) error_message must still be the forward-incompat one — got '%s'" % r4.error_message)
	_check(failures, FileAccess.file_exists(kept_path),
		"(4) the save reached through %s is just as unrecoverable and must be copied aside too" % bak_path)

	# ===================================================================
	# (5) Worldgen mismatch — narrowed scope, must NOT be preserved.
	# ===================================================================
	_scrub()
	if not _write_mutated_save(parent, SEED_FUTURE, {"worldgen_version": WorldGenerator.VERSION + 1000}):
		failures.append("(5) PREMISE: could not produce the worldgen-mismatch fixture")
		return
	var r5: LoadResult = _load(parent)
	_check(failures, not r5.success, "(5) a worldgen mismatch must still fail the load")
	# main.gd reads a non-empty error_message as "load failed, generate fresh";
	# an empty one is this API's silent "no save file" signal.
	_check(failures, r5.error_message != "",
		"(5) error_message must be non-empty so main.gd falls through to fresh-world generation, as CONVENTIONS.md requires")
	_check(failures, not FileAccess.file_exists(kept_path),
		"(5) #21 was scoped down to the forward-incompat case; a worldgen mismatch is a sanctioned fresh-world fallthrough and must not start setting saves aside")

	# ===================================================================
	# (6) Migration failure — narrowed scope, must NOT be preserved.
	# ===================================================================
	_scrub()
	if not _write_mutated_save(parent, SEED_FUTURE, {"version": UNMIGRATABLE_VERSION}):
		failures.append("(6) PREMISE: could not produce the unmigratable fixture")
		return
	var r6: LoadResult = _load(parent)
	_check(failures, not r6.success, "(6) a save with no migration path must still fail the load")
	_check(failures, r6.error_message != "",
		"(6) error_message must be non-empty so main.gd falls through to fresh-world generation, as CONVENTIONS.md requires")
	_check(failures, not FileAccess.file_exists(kept_path),
		"(6) a migration failure is a sanctioned fresh-world fallthrough — its alert already warns about the F5 overwrite — and must not start setting saves aside")

	# ===================================================================
	# (7) The preserved copy is not itself a save.
	# ===================================================================
	_scrub()
	if not _write_future_save(parent, SEED_FUTURE):
		failures.append("(7) PREMISE: could not produce the newer-save fixture")
		return
	_load(parent)   # makes the copy
	for suffix in ["", SaveSystem.BAK_SUFFIX]:
		var p: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_check(failures, FileAccess.file_exists(kept_path),
		"(7) PREMISE: the preserved copy should be the only thing left on disk")
	# If save_exists() counted it, every subsequent boot would hand load_game a
	# file it has already refused and re-run the alert forever, instead of
	# loading the fresh world the player has been playing since.
	_check(failures, not SaveSystem.save_exists(),
		"(7) save_exists() must not count the preserved copy — it is a file kept for a future build, not a save this one can load")

	# ===================================================================
	# (8) Worldgen mismatch reached ONLY through .bak.
	#
	# The precondition for the path-quoting defect this sub-case exists for:
	# the worldgen alert asks the player to DELETE the file it names, and it
	# quoted `save_path` unconditionally. If this branch were unreachable
	# except via the primary, that would be harmless. It is not — a crash
	# between save_game's two renames leaves only `.bak`, and a `.bak` can
	# carry a worldgen mismatch like any other save. The player is then told
	# to delete a file that does not exist while the real one sits at `.bak`
	# and is rotated away by the second F5.
	#
	# HONEST LIMIT: this pins REACHABILITY, not the string. The path appears
	# only in `push_error` + a fixture-gated `OS.alert`, and deliberately not
	# in `error_message` (main.gd toasts that, and a native path belongs in
	# the modal). Neither is observable from here. See the comment at the
	# branch in save_system.gd.
	# ===================================================================
	_scrub()
	if not _write_mutated_save(parent, SEED_FUTURE, {"worldgen_version": WorldGenerator.VERSION + 1000}):
		failures.append("(8) PREMISE: could not produce the worldgen-mismatch fixture")
		return
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEST_SAVE_PATH), ProjectSettings.globalize_path(bak_path))
	_check(failures, not FileAccess.file_exists(TEST_SAVE_PATH),
		"(8) PREMISE: the primary should be gone, leaving only the backup")
	_check(failures, SaveSystem.save_exists(),
		"(8) PREMISE: save_exists() counts the backup, so main.gd still calls load_game here")
	var r8: LoadResult = _load(parent)
	_check(failures, not r8.success,
		"(8) a worldgen mismatch reached through .bak must fail the load exactly as one reached through the primary does")
	_check(failures, r8.error_message.find(str(WorldGenerator.VERSION)) >= 0,
		"(8) the failure must still be the worldgen one, naming this build's version — got '%s'" % r8.error_message)
	_check(failures, not FileAccess.file_exists(kept_path),
		"(8) the narrowed #21 scope holds through the backup path too: a worldgen mismatch preserves nothing")

	# ===================================================================
	# (9) A SECOND newer save overwrites the first preserved copy.
	#
	# Documented as intended at `_preserve_incompatible` — "one preservation
	# slot per save slot, holding the most recent save this build had to
	# refuse" — and pinned here because it is a data-loss-shaped decision
	# nothing else covers. The alternative (accumulating numbered copies)
	# would be a defensible design; what must not happen is the code doing
	# one thing while the doc claims the other.
	# ===================================================================
	_scrub()
	if not _write_future_save(parent, SEED_FUTURE):
		failures.append("(9) PREMISE: could not produce the first newer-save fixture")
		return
	_load(parent)
	_expect_kept(failures, "(9 first)", kept_path, future_version, SEED_FUTURE)
	# A second newer save lands in the same slot — a different seed, so which
	# of the two survived is decidable rather than a matter of timestamps.
	if not _write_future_save(parent, SEED_FRESH_1):
		failures.append("(9) PREMISE: could not produce the second newer-save fixture")
		return
	_load(parent)
	_expect_kept(failures, "(9 second)", kept_path, future_version, SEED_FRESH_1)

# ---------- helpers ----------

## Assert the preserved copy is on disk AND parses as the newer save. Contents,
## not existence: a zero-byte or truncated file at the right path would satisfy
## "it was preserved" while being useless to the newer build it exists for.
static func _expect_kept(failures: Array, label: String, kept_path: String, want_version: int, want_seed: int) -> void:
	var kept = _read_json(kept_path)
	if kept == null:
		failures.append("%s %s is missing or does not parse — the save the dialog told the player to keep is gone" % [label, kept_path])
		return
	_check(failures, int(kept.get("version", -1)) == want_version,
		"%s the preserved copy is version %s, expected %d" % [label, str(kept.get("version", "absent")), want_version])
	_check(failures, int(kept.get("world_seed", -1)) == want_seed,
		"%s the preserved copy has world_seed %s, expected %d" % [label, str(kept.get("world_seed", "absent")), want_seed])
	_check(failures, str(kept.get(FUTURE_FIELD, "")) == FUTURE_MARKER,
		"%s the preserved copy lost '%s' — the fields only the newer build understands are the whole reason to keep it" % [label, FUTURE_FIELD])

## Write a well-formed save through the real save_game, then bump its version
## past this build's and add a field this build knows nothing about. Going
## through save_game first means the ONLY thing wrong with the fixture is its
## version — nothing else can be blamed for the load failing.
static func _write_future_save(parent: Node, world_seed: int) -> bool:
	return _write_mutated_save(parent, world_seed, {
		"version": SaveSystem.SAVE_VERSION + FUTURE_BUMP,
		FUTURE_FIELD: FUTURE_MARKER,
	})

## Save a real world, then overwrite the given top-level fields on disk.
## Clears the sidecars save_game may have left so each fixture starts clean.
static func _write_mutated_save(parent: Node, world_seed: int, overrides: Dictionary) -> bool:
	if not _save_fresh(parent, world_seed):
		return false
	var data = _read_json(TEST_SAVE_PATH)
	if data == null:
		return false
	for key in overrides:
		data[key] = overrides[key]
	if not _write_text(TEST_SAVE_PATH, JSON.stringify(data)):
		return false
	for suffix in [SaveSystem.TMP_SUFFIX, SaveSystem.BAK_SUFFIX]:
		var p: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	return true

## One ordinary save through the real save_game — an F5.
static func _save_fresh(parent: Node, world_seed: int) -> bool:
	var world = _make_world(parent)
	world.world_seed = world_seed
	var player := Node2D.new()
	parent.add_child(player)
	var ok: bool = SaveSystem.save_game(world, player, Inventory.new(16), {})
	player.queue_free()
	_teardown(world)
	return ok

static func _load(parent: Node) -> LoadResult:
	var world = _make_world(parent)
	var player := Node2D.new()
	parent.add_child(player)
	var result: LoadResult = SaveSystem.load_game(world, player, Inventory.new(16))
	player.queue_free()
	_teardown(world)
	return result

static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed

static func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## Remove the fixture and ALL THREE sidecars. The preserved copy is included
## because it is the one file `save_game` never rotates away — a leftover from a
## previous run would make sub-cases 5 and 6 fail, and sub-case 1 pass, for
## entirely the wrong reason.
static func _scrub() -> void:
	for suffix in ["", SaveSystem.TMP_SUFFIX, SaveSystem.BAK_SUFFIX, SaveSystem.INCOMPAT_SUFFIX]:
		var p: String = TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing. queue_free is deferred until after the runner's
## synchronous run() returns, so a torn-down world otherwise stays subscribed
## to TickSystem.tick for the rest of the suite.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
