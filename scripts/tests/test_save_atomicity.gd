extends RefCounted

## An interrupted save must not destroy the save that was already on disk.
##
## Audit finding #12 (MEDIUM), docs/audits/2026-07-19-flaw-review.md —
## "save_game writes the save file non-atomically — a crash mid-write destroys
## the only save slot".
##
## THE PROPERTY, NOT THE SHAPE. Nothing here asserts that save_game writes a
## .tmp and renames it. That would prove the code's shape and would keep
## passing over an implementation that renamed the temp file into place while
## the handle was still open. Every sub-case below constructs state A on disk,
## interrupts a write of state B, and then asks load_game what it gets back,
## comparing the LOADED FIELD VALUES — world_seed, player position, flour
## count, all three different between A and B. A save that returned true while
## leaving the slot unreadable fails these; so does a load that "succeeded"
## into an empty world.
##
## HOW THE INTERRUPTION IS PRODUCED. A headless test cannot kill the process,
## so save_game carries a test-only seam, `SaveSystem._interrupt_after_stage`
## (documented at its declaration). It aborts AFTER the work of the named
## stage has actually been done, so the on-disk state is exactly what a crash
## at that instant would leave — a seam that short-circuited before doing the
## work would leave the disk untouched and test nothing. Sub-case (2) checks
## this directly: it asserts the .tmp exists AND parses to B's seed, which is
## only true if the abort came after a real write.
##
## Sub-case index:
##   1. State A saves and loads back as A. The premise everything else rests
##      on, and the source of the byte snapshot (2) compares against.
##   2. Interrupted after the .tmp is written, before any rename. save_path
##      must be byte-identical to (1) and must still load as A.
##   3. Interrupted BETWEEN THE TWO RENAMES — the live save is at .bak and the
##      .tmp is not yet in place, so save_path does not exist. This is the
##      window the fix itself introduces, and the one that is not covered by
##      simply not having truncated anything. A must come back from the
##      backup, load_game must say so, and save_exists must still report a
##      save (main.gd gates its whole load path on that call).
##   4. Garbage in save_path with a valid .bak — the case the audit's fix text
##      prescribes, and what an interrupted PRE-FIX truncating write leaves.
##   5. Garbage in save_path with NO .bak. Must fail with a non-empty
##      error_message, and must NOT claim a backup was used. Without this,
##      "recover from anything" and "silently succeed on nothing" look alike.
##   6. A successful save leaves no stray .tmp, and actually replaces the live
##      save (it loads back as B, not as the A that was there before).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_save_atomicity.json"

# A and B differ in all three asserted fields, so no sub-case can pass by
# reading the wrong state and matching on a field they share.
const SEED_A: int = 40001
const POS_A: Vector2 = Vector2(11.0, 22.0)
const FLOUR_A: int = 17
const SEED_B: int = 40002
const POS_B: Vector2 = Vector2(333.0, 444.0)
const FLOUR_B: int = 3

## What an interrupted pre-fix write left behind: FileAccess.WRITE truncated
## save_path and store_string got part-way through. Valid JSON prefix, invalid
## JSON document.
const PARTIAL_JSON: String = '{"version": 18, "world_seed": 400'

static func test_name() -> String:
	return "interrupted save preserves the previous save (audit #12)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	_scrub()

	_run_all(parent, failures)

	# Restored here, not inside _run_all: every early return in there skips its
	# own cleanup, and a leaked _interrupt_after_stage would break later suites
	# rather than this one.
	SaveSystem._interrupt_after_stage = ""
	SaveSystem.save_path = orig_path
	_scrub()

	if failures.is_empty():
		return { "ok": true, "message": "6 sub-cases pass: A round-trips; aborts after the tmp write and between the two renames both preserve A; .bak recovers a corrupt primary; a corrupt primary with no backup fails loudly; a clean save leaves no .tmp" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

static func _run_all(parent: Node, failures: Array) -> void:
	var tmp_path: String = TEST_SAVE_PATH + SaveSystem.TMP_SUFFIX
	var bak_path: String = TEST_SAVE_PATH + SaveSystem.BAK_SUFFIX

	# ===================================================================
	# (1) State A saves and loads back as A.
	# ===================================================================
	if not _save_state(parent, SEED_A, POS_A, FLOUR_A):
		failures.append("PREMISE: save_game(A) returned false")
		return
	_expect_loads(parent, failures, "(1)", SEED_A, POS_A, FLOUR_A, false)
	if not FileAccess.file_exists(TEST_SAVE_PATH):
		failures.append("PREMISE: save_game(A) left nothing at %s" % TEST_SAVE_PATH)
		return
	# The byte snapshot (2) compares against. "Still loads as A" alone would be
	# satisfied by a rewrite that produced equivalent-but-different bytes; the
	# claim is that the interrupted write did not touch this file at all.
	var bytes_a: PackedByteArray = FileAccess.get_file_as_bytes(TEST_SAVE_PATH)
	if bytes_a.is_empty():
		failures.append("PREMISE: %s is empty after saving A" % TEST_SAVE_PATH)
		return

	# ===================================================================
	# (2) Interrupted after the .tmp write, before any rename.
	# ===================================================================
	SaveSystem._interrupt_after_stage = "tmp_written"
	var saved_2: bool = _save_state(parent, SEED_B, POS_B, FLOUR_B)
	SaveSystem._interrupt_after_stage = ""
	_check(failures, not saved_2, "(2) an interrupted save must report failure, but save_game returned true")

	# The seam has to have aborted AFTER real work. A .tmp holding B's seed is
	# what proves it; without this the sub-case would pass just as well against
	# a seam that returned before writing anything, which tests nothing.
	var tmp_dict = _read_json(tmp_path)
	_check(failures, tmp_dict != null and int(tmp_dict.get("world_seed", -1)) == SEED_B,
		"(2) the abort is supposed to happen AFTER the temp file is fully written — %s should parse to seed %d, got %s" % [tmp_path, SEED_B, str(tmp_dict)])

	_check(failures, FileAccess.get_file_as_bytes(TEST_SAVE_PATH) == bytes_a,
		"(2) %s changed during the interrupted write of B — the live save must be byte-identical to what saving A left" % TEST_SAVE_PATH)
	_expect_loads(parent, failures, "(2)", SEED_A, POS_A, FLOUR_A, false)

	# ===================================================================
	# (3) Interrupted BETWEEN THE TWO RENAMES.
	# ===================================================================
	SaveSystem._interrupt_after_stage = "backup_renamed"
	var saved_3: bool = _save_state(parent, SEED_B, POS_B, FLOUR_B)
	SaveSystem._interrupt_after_stage = ""
	_check(failures, not saved_3, "(3) an interrupted save must report failure, but save_game returned true")
	# The window is only real if save_path is genuinely gone here. If this
	# assertion ever flips to "still present", sub-case (3) has quietly become
	# a second copy of (2) and stops covering the fix's own dangerous window.
	_check(failures, not FileAccess.file_exists(TEST_SAVE_PATH),
		"(3) PREMISE: this sub-case is about the instant where the live save has been moved aside and the temp file is not yet in place, so %s must NOT exist" % TEST_SAVE_PATH)
	_check(failures, FileAccess.file_exists(bak_path),
		"(3) the live save was moved to %s and that is now the only copy of the player's progress — it must exist" % bak_path)
	# main.gd calls save_exists() before it ever calls load_game; a
	# save_path-only check here regenerates a fresh world over a recoverable
	# backup, which is the same progress loss by a different route.
	_check(failures, SaveSystem.save_exists(),
		"(3) save_exists() must report a save when only the backup survives, or main.gd skips the load entirely and generates a fresh world")
	_expect_loads(parent, failures, "(3)", SEED_A, POS_A, FLOUR_A, true)

	# ===================================================================
	# (4) Garbage in save_path, valid .bak present.
	# ===================================================================
	if not _write_text(TEST_SAVE_PATH, PARTIAL_JSON):
		failures.append("(4) PREMISE: could not write the partial save fixture")
		return
	_check(failures, FileAccess.file_exists(bak_path), "(4) PREMISE: the backup from (3) should still be on disk")
	_expect_loads(parent, failures, "(4)", SEED_A, POS_A, FLOUR_A, true)

	# ===================================================================
	# (5) Garbage in save_path, no .bak at all.
	# ===================================================================
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
	_check(failures, not FileAccess.file_exists(bak_path), "(5) PREMISE: the backup should be gone")
	var world_5 = _make_world(parent)
	var player_5 := Node2D.new()
	parent.add_child(player_5)
	var result_5: LoadResult = SaveSystem.load_game(world_5, player_5, Inventory.new(16))
	player_5.queue_free()
	_teardown(world_5)
	_check(failures, not result_5.success,
		"(5) a corrupt save with no backup has nothing to recover from and must not report success")
	_check(failures, result_5.error_message != "",
		"(5) error_message must be non-empty — the empty string is this API's 'no save file, start fresh' signal, and a corrupt save is not that")
	_check(failures, not result_5.used_backup,
		"(5) there is no backup on disk, so used_backup must be false — a true here would have main.gd tell the player it recovered something")

	# ===================================================================
	# (6) A successful save leaves no stray .tmp, and really does replace
	#     the live save.
	# ===================================================================
	if not _save_state(parent, SEED_B, POS_B, FLOUR_B):
		failures.append("(6) PREMISE: an uninterrupted save_game(B) returned false")
		return
	_check(failures, not FileAccess.file_exists(tmp_path),
		"(6) %s survived a successful save — the temp file is supposed to be renamed into place, not copied and left behind" % tmp_path)
	_expect_loads(parent, failures, "(6)", SEED_B, POS_B, FLOUR_B, false)

# ---------- helpers ----------

## Build a throwaway world/player/inventory carrying the given state and save
## it through the real save_game. The world is not generated from the seed —
## load_game regenerates it — so this stays cheap.
static func _save_state(parent: Node, world_seed: int, pos: Vector2, flour: int) -> bool:
	var world = _make_world(parent)
	world.world_seed = world_seed
	var player := Node2D.new()
	parent.add_child(player)
	player.global_position = pos
	var inv := Inventory.new(16)
	inv.add(Items.Type.FLOUR, flour)
	var ok: bool = SaveSystem.save_game(world, player, inv, {})
	player.queue_free()
	_teardown(world)
	return ok

## Load into a blank world and assert every asserted field came back with the
## expected value, plus whether the backup was used.
static func _expect_loads(parent: Node, failures: Array, label: String, world_seed: int, pos: Vector2, flour: int, want_backup: bool) -> void:
	var world = _make_world(parent)
	var player := Node2D.new()
	parent.add_child(player)
	var inv := Inventory.new(16)
	var result: LoadResult = SaveSystem.load_game(world, player, inv)
	if not result.success:
		failures.append("%s load_game failed (error_message=%s) — the previous save was supposed to survive" % [label, str(result.error_message)])
	else:
		_check(failures, world.world_seed == world_seed,
			"%s world_seed loaded as %d, expected %d" % [label, world.world_seed, world_seed])
		_check(failures, player.global_position == pos,
			"%s player position loaded as %s, expected %s" % [label, str(player.global_position), str(pos)])
		_check(failures, inv.total_of(Items.Type.FLOUR) == flour,
			"%s flour count loaded as %d, expected %d" % [label, inv.total_of(Items.Type.FLOUR), flour])
		_check(failures, result.used_backup == want_backup,
			"%s used_backup is %s, expected %s" % [label, str(result.used_backup), str(want_backup)])

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

## Remove the fixture and BOTH sidecars. Called before and after the run, so a
## crash mid-suite cannot leave a .tmp or .bak that makes the next run pass (or
## fail) for the wrong reason.
static func _scrub() -> void:
	for p in [TEST_SAVE_PATH, TEST_SAVE_PATH + SaveSystem.TMP_SUFFIX, TEST_SAVE_PATH + SaveSystem.BAK_SUFFIX]:
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
