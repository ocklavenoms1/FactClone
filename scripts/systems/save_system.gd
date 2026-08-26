class_name SaveSystem
extends RefCounted

## Save schema migration log:
##   v4 → v5: Mill became Processor; state shape changed from
##            { in_count, out_count, progress } to
##            { recipe_id, state, progress, in_buffer, out_buffer }.
##   v5 → v6: Chest migrated from Inventory to bag format.
##            { inv: Array (Inventory.to_array()) } → { bag: Array of [type, count] }.
##            TOTAL_CAPACITY = 2400 (equivalent to old 24 slots × 100 max_stack).
##   v6 → v7: Tile model split into base + overlay. Tile entry shape
##            [x, y, terrain] → [x, y, base, overlay]. Player paints
##            overlays on grass; water is a base, not paintable.
##   v7 → v8: Tile gains `resource_node` field (forward-prep for world-gen
##            stone/ore/wood deposits, target session G/H — see NOTES.md).
##            Tile entry shape [x, y, base, overlay] → [x, y, base, overlay, resource_node].
##            No buildings consume resource_nodes yet; the bump just locks
##            the save format so we don't bump twice when mining lands.
##            No migration code — old saves hard-fail with OS.alert.
##   v8 → v9: Multi-tile buildings + rotation. Mixer/Oven/Proofer/Packager
##            footprint changed from 1×1 to 2×2 — v8 saves with these
##            buildings would load with mismatched `occupied` cells (only
##            the anchor mapped, not the 3 expansion cells). Rotatable
##            processors (Mixer/Oven/Proofer/Packager/Thresher) now carry
##            `dir` in their state so prefer_dir ports rotate with the
##            building. v8 saves where these buildings were 1×1 / non-
##            directional cannot be safely upgraded — hard-fail.
##   v9 → v10: Player gains bag-cap progression. New top-level field
##            `player_progression: Dictionary` with `bags_consumed: int`
##            (0..5) tracking lifetime bag consumption. Inventory capacity
##            persists implicitly via load_array's resize logic; the
##            progression dict is the explicit counter and the future home
##            for additional progression state (score/value, achievements,
##            etc.). v9 saves don't have this field — hard-fail.
##  v10 → v11: WORLDGEN STAGE 1 — procgen rehydration model.
##            New top-level fields:
##              - `world_seed: int` — the seed used to generate this world
##              - `worldgen_version: int` — must match WorldGenerator.VERSION
##                or load hard-fails (procgen logic changes invalidate saves)
##            Tile data shape change:
##              - `tiles` → `tile_modifications`. Stores ONLY tiles that
##                differ from procgen-canonical state. Saves are dramatically
##                smaller (KB instead of MB) since most world content is
##                regenerated from the seed.
##            Load procedure changes:
##              - 1. Read seed + worldgen_version (hard-fail mismatch)
##              - 2. Run WorldGenerator.generate(world, seed) to rebuild canon
##              - 3. Apply tile_modifications on top
##              - 4. Restore buildings / player / progression as before
##            v10 saves don't have a seed and use the hardcoded-lake world.
##            They cannot be safely upgraded — hard-fail.
##  v11 → v12: M-key map + fog-of-war. New top-level field
##            `explored_regions: Array of [rx, ry]` — sparse list of region
##            coords ever charted (state >= 1 = fog or active).
##            Active state (state == 2, currently in vision) is recomputed
##            from player position at load time, not persisted. Avoids the
##            "saved active but loaded somewhere else" inconsistency.
##            v11 saves don't have this field — hard-fail.
##  v12 → v13: Manual mining mechanics. New top-level field
##            `resource_state_modifications: Array of [x, y, richness]` —
##            sparse list of ore-deposit tiles whose richness has been
##            depleted by mining. Parallel to `tile_modifications`: only
##            deltas from procgen-canonical state persist.
##            On load: WorldGenerator regenerates canonical resource_state
##            (with original_richness intact) from seed, then apply
##            modifications to overwrite richness. Fully-depleted tiles
##            (richness=0) are handled by tile_modifications setting
##            resource_node=NONE; the resource_state_modifications entry
##            for those is erased at depletion time.
##            DUAL REASON for v12 hard-fail at this bump:
##              (1) the new resource_state_modifications field
##              (2) the "no overlay on deposits" rule reversal — v12 saves
##                  could have stale overlay-on-deposit tiles which are
##                  now invalid state.
##            v12 saves don't have either — hard-fail.
##  v13 → v14: Tree harvesting + generic resource state modifications.
##            resource_state_modifications shape changed from
##              Array of [x, y, richness:int]
##            to
##              Array of [x, y, dict]
##            where dict contains state fields per resource type:
##              ore:  {"richness": int}
##              tree: {"regrowth_remaining": float}
##            The Dictionary inner shape supports future resource types
##            (crops, berries, etc.) by adding keys without further
##            schema bumps. Each entry stores ONLY the fields relevant
##            to its resource type.
##            v13 saves have Array of [x, y, int] — incompatible with
##            the new Dict shape — hard-fail.

## Save format migration log:
##   v14 → v15: added `region_soil_modifications` (Array of [rx, ry, soil])
##              for the soil exhaustion arc (session-soil-exhaustion-1).
##              Sparse — absent regions default to SOIL_HEALTH_FULL (100).
##              Hard-fail v14 saves per existing schema-bump policy.
##   v15 → v16: REFACTOR region-scoped soil to per-tile soil
##              (session-soil-exhaustion-2). Field renamed
##              `region_soil_modifications` → `tile_soil_modifications`
##              with shape Array of [x, y, soil] where (x, y) is a TILE
##              position, not a region coord. Sparse — absent tiles default
##              to TILE_SOIL_FULL (100). Hard-fail v15 saves; no migration
##              (region values would synthesize artificial uniform tiles).
##   v16 → v17: Fertilizer chain (session-soil-exhaustion-3). New top-level
##              field `tile_fertilizer_state`: sparse Array of
##              [x, y, tier_int, remaining_float] where tier_int is an
##              Items.Type (COMPOST_LOW or COMPOST_MID), and remaining is
##              the seconds left on the active boost. Absent tile = no
##              boost (default behavior, regen at 1×). v16 saves don't have
##              the field — hard-fail with OS.alert per existing policy.
##              Items enum gained COMPOST_LOW + COMPOST_MID at the end
##              (append-only — no enum-int reuse risk for v16 ints).
##   v17 → v18: Wasteland mechanics (session-soil-exhaustion-4). New top-
##              level field `tile_wasteland_state`: sparse Array of
##              [x, y, scarred_bool, decay_remaining_float]. Absent tile =
##              healthy (no grace, no scar). Scarred persists; grace is
##              countdown to scarring.
##              Items enum gained COMPOST_HIGH (append-only). Composter
##              now accepts BREAD + LOAF_PACK as recipe inputs.
##              v17 saves don't have the wasteland field — hard-fail with
##              OS.alert per existing policy.
const SAVE_VERSION: int = 18
const DEFAULT_SAVE_PATH: String = "user://save_slot_1.json"

## Path used by save_game / load_game / save_exists. Tests override this
## to a scratch path so they don't clobber the player's save. Restore to
## DEFAULT_SAVE_PATH after the test.
static var save_path: String = DEFAULT_SAVE_PATH

## True if the given path looks like a test fixture (test files set save_path
## to scratch paths during negative-path tests; those should NEVER trigger
## user-facing OS.alert popups even if the test runs windowed). push_error
## still fires for logging in both cases.
##
## TWO callers, and the second is the consequential one:
##   1. `load_game`'s error branches, to suppress OS.alert under test.
##   2. `_should_interrupt`, which is what keeps `save_game`'s fault-injection
##      seam from ever firing on a real save.
## Loosening this predicate to fix an alert edge case therefore also widens the
## fault-injection gate. Change it with (2) in mind, not only (1).
static func _is_test_fixture_path(path: String) -> bool:
	return path.begins_with("user://test_") or path.find("/test_artifacts/") >= 0

## Suffixes for the two sidecars the atomic write uses (audit finding #12).
const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"

## Suffix for the copy `load_game` sets aside when it refuses a save written by
## a NEWER build than this one (audit finding #21). Distinct from BAK_SUFFIX on
## purpose — see `_preserve_incompatible` for why the rotation slot cannot be
## reused for this, and `save_exists` for why this suffix is not counted there.
const INCOMPAT_SUFFIX: String = ".incompatible"

## TEST-ONLY fault injection for `save_game`. Set to a stage name to make
## save_game return false at that exact point, leaving on disk precisely what
## a process kill at that moment would leave. Production never sets this; it
## defaults to "" and `_should_interrupt` additionally refuses to fire unless
## `save_path` is a test fixture path, so a value leaked into a shipped build
## still cannot touch a real save.
##
## Recognised stages (see save_game):
##   "tmp_written"     — the .tmp is fully written and closed, no rename yet.
##   "backup_renamed"  — the live save has been moved to .bak and the .tmp is
##                       not yet in place, so `save_path` DOES NOT EXIST. This
##                       is the window the atomic write itself introduces and
##                       the one the .bak fallback exists to cover.
## Covered by scripts/tests/test_save_atomicity.gd.
static var _interrupt_after_stage: String = ""

## True when the test seam should abort `save_game` right now.
##
## The `_is_test_fixture_path` gate is deliberate. `_interrupt_after_stage` is
## a static, so a test that failed to restore it (an early return past its
## cleanup) would otherwise leave every subsequent save in the process — the
## player's included, in an editor session — silently returning false or, at
## the "backup_renamed" stage, with no save file on disk at all. Gating narrows
## that to exactly one claim: a leak cannot reach a REAL save. It is not
## harmless in the suite — a leaked value still makes `save_game` return false,
## or leave no file, for every fixture path, which is every save the tests
## perform. What the gate buys is that the blast radius stops at the fixtures.
## The cost is that a future test
## using a non-fixture path would find the seam inert; that cannot pass
## vacuously, because every sub-case asserts the on-disk state an abort
## produces, and a completed save fails those assertions.
static func _should_interrupt(stage: String) -> bool:
	if _interrupt_after_stage != stage:
		return false
	return _is_test_fixture_path(save_path)

# ---------- migration framework (session-save-migration) ----------
#
# Replaces the prior hard-fail-on-version-mismatch behavior. When loading
# a save with version < SAVE_VERSION, the chain `_migrate_vN_to_v(N+1)`
# steps the parsed Dictionary forward one version at a time until it
# matches the current schema. Each migration is responsible for adding
# new fields with sensible defaults, transforming/restructuring as
# needed, and bumping `data["version"]` to its target.
#
# **Breaking-change reset point: v17.** Saves before v17 are NOT
# preserved — the v14/v15/v16 schema versions exist only as schema-
# history reference; no production saves at those versions ever
# existed. If a v<17 save is encountered (extremely unlikely), the
# missing-migration path fires, load fails, and main.gd's post-3.5
# hotfix regenerates a fresh world. See NOTES.md / CONVENTIONS.md.
#
# Forward-only by design: a save with version > SAVE_VERSION (running
# an OLDER game binary against a NEWER save) hard-fails. Backward
# migration is out of scope.
const MIGRATIONS: Dictionary = {
	# 17 → 18: Wasteland mechanics. New top-level `tile_wasteland_state`
	# field; absent in v17, populated to empty Array (no scarred tiles).
	17: "_migrate_v17_to_v18",
}

## Migrate `data` (parsed save dict) from `from_version` to `to_version`
## by walking the MIGRATIONS chain one step at a time. Returns the
## migrated Dictionary on success, OR null on any failure (gap in chain,
## migration didn't bump version correctly, etc.). Caller surfaces the
## error and main.gd's hotfix regenerates a fresh world.
##
## Pure data transformation — no game state mutation, no I/O.
##
## Defensive: each step verifies the migration produced an N+1 version,
## so a bug in a migration function is caught at the failing step
## (named in the error) rather than producing a downstream silent
## corruption.
static func _try_migrate(data: Dictionary, from_version: int, to_version: int) -> Variant:
	var current: int = from_version
	while current < to_version:
		if not MIGRATIONS.has(current):
			push_error("SaveSystem._try_migrate: no migration registered from v%d (target v%d)" % [current, to_version])
			return null
		var method_name: String = MIGRATIONS[current]
		# Static method dispatch via match-statement. GDScript's Object.call()
		# is instance-only and Callable(SaveSystem, name) on a static method
		# is unreliable; explicit dispatch is the foolproof pattern. Each
		# new migration adds one match case below — small cost, clear errors.
		var migrated = _dispatch_migration(method_name, data)
		if typeof(migrated) != TYPE_DICTIONARY:
			push_error("SaveSystem._try_migrate: %s returned non-Dictionary (%s)" % [method_name, typeof(migrated)])
			return null
		data = migrated
		var new_version: int = int(data.get("version", -1))
		if new_version != current + 1:
			push_error("SaveSystem._try_migrate: %s did not bump version: expected %d, got %d" % [method_name, current + 1, new_version])
			return null
		current = new_version
	return data

## Dispatch a migration by name. Each migration registered in MIGRATIONS
## must have a corresponding match case here. Failure to register both
## sides is a parse-error / runtime-error pair: MIGRATIONS lookup returns
## a name that this dispatcher doesn't recognize → push_error + null.
static func _dispatch_migration(method_name: String, data: Dictionary) -> Variant:
	match method_name:
		"_migrate_v17_to_v18":
			return _migrate_v17_to_v18(data)
	push_error("SaveSystem._dispatch_migration: unknown migration '%s'" % method_name)
	return null

## v17 → v18: add `tile_wasteland_state` field with empty Array default.
## Schema diff: this field was added in session-soil-exhaustion-4 to
## persist per-tile wasteland state (scarred flag + grace decay timer).
## v17 saves predate the wasteland mechanic entirely — no scarred tiles
## could exist. Default-empty Array is the canonical "healthy world."
##
## The Items enum also gained COMPOST_HIGH at v18, but that's stored as
## an int in player_inventory and recipe state — nothing to migrate
## (the int 26, or whatever the enum value is, simply wouldn't appear
## in a v17 save). No COMPOST_HIGH in player_inventory at v17 by
## construction, so nothing to backfill.
static func _migrate_v17_to_v18(data: Dictionary) -> Dictionary:
	data["tile_wasteland_state"] = []
	data["version"] = 18
	return data

## `player_progression` is a free-form Dictionary tracked by main.gd.
## Default-empty so existing tests / call sites that don't yet pass
## progression don't break the signature; the caller stays in charge of
## defaulting missing keys on the load side.
static func save_game(grid_world: Node2D, player: Node2D, player_inventory: Inventory, player_progression: Dictionary = {}) -> bool:
	# v11: serialize ONLY player-modified tiles. The world is reconstructed
	# from world_seed + worldgen_version on load.
	var modifications_data: Array = []
	for tile_key in grid_world.tile_modifications:
		var pos: Vector2i = tile_key
		var t: Tile = grid_world.tile_modifications[pos]
		modifications_data.append([pos.x, pos.y, t.base, t.overlay, t.resource_node])

	var buildings_data: Array = []
	for anchor_key in grid_world.buildings:
		var b: Building = grid_world.buildings[anchor_key]
		buildings_data.append(b.to_dict())

	# v12: serialize explored regions (state >= 1). Active state collapses to
	# fog on save; load-time vision update re-derives active from player pos.
	var explored_data: Array = []
	for region in grid_world.region_visibility.keys():
		if int(grid_world.region_visibility[region]) >= 1:
			explored_data.append([region.x, region.y])

	# v14: serialize resource_state_modifications. Generic shape:
	#   ore  → [x, y, {"richness": N}]
	#   tree → [x, y, {"regrowth_remaining": F}]
	# Inner dict can grow new keys for future resource types without bumping
	# the save schema; only the field shape change required v13→v14.
	var resource_mods_data: Array = []
	for pos in grid_world.resource_state_modifications.keys():
		var state: Dictionary = grid_world.resource_state_modifications[pos]
		# duplicate() so save snapshot can't mutate via shared reference.
		resource_mods_data.append([pos.x, pos.y, state.duplicate()])

	# v16: serialize tile_soil_modifications. Sparse — only modified tiles
	# appear (default TILE_SOIL_FULL = 100 is implicit, absent).
	# Shape: Array of [x, y, soil_health] where (x, y) is a tile position.
	var tile_soil_data: Array = []
	for pos in grid_world.tile_soil_modifications.keys():
		tile_soil_data.append([pos.x, pos.y, int(grid_world.tile_soil_modifications[pos])])

	# v17: serialize tile_fertilizer_state. Sparse — only tiles with active
	# boost appear. Shape: Array of [x, y, tier, remaining_sec] where tier
	# is an Items.Type (COMPOST_LOW, COMPOST_MID, or COMPOST_HIGH at v18)
	# and remaining is the seconds left until the boost expires. Absent
	# tile = no boost.
	var tile_fert_data: Array = []
	for pos in grid_world.tile_fertilizer_state.keys():
		var s: Dictionary = grid_world.tile_fertilizer_state[pos]
		tile_fert_data.append([pos.x, pos.y, int(s["tier"]), float(s["remaining"])])

	# v18: serialize tile_wasteland_state. Sparse — only tiles in grace
	# OR scarred appear. Shape: Array of [x, y, scarred_bool,
	# decay_remaining_float]. Both fields persist (grace remaining
	# survives save/load so a tile mid-scarring picks up where it left
	# off). Absent tile = healthy.
	var tile_wasteland_data: Array = []
	for pos in grid_world.tile_wasteland_state.keys():
		var ws: Dictionary = grid_world.tile_wasteland_state[pos]
		tile_wasteland_data.append([pos.x, pos.y, bool(ws.get("scarred", false)), float(ws.get("decay_remaining", 0.0))])

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"world_seed": grid_world.world_seed,
		"worldgen_version": WorldGenerator.VERSION,
		"player": [player.global_position.x, player.global_position.y],
		"tick": TickSystem.current_tick,
		"tile_modifications": modifications_data,
		"resource_state_modifications": resource_mods_data,
		"tile_soil_modifications": tile_soil_data,
		"tile_fertilizer_state": tile_fert_data,
		"tile_wasteland_state": tile_wasteland_data,
		"explored_regions": explored_data,
		"buildings": buildings_data,
		"player_inventory": player_inventory.to_array(),
		"player_progression": player_progression,
	}

	# ---- ATOMIC WRITE (audit finding #12) ----------------------------------
	# FileAccess.WRITE TRUNCATES ON OPEN. Writing straight to save_path meant
	# any interruption between the truncation and the flush left the single
	# save slot empty or half-written, and load_game had no fallback: the
	# partial file fails JSON.parse_string and main.gd's hotfix regenerates a
	# fresh world. Instead: write .tmp, move the live save aside to .bak, move
	# .tmp into place. At every instant at least one complete save exists.
	# Both sidecars are derived from the CURRENT `save_path`, never from
	# DEFAULT_SAVE_PATH — tests override `save_path`, and sidecars pinned to the
	# default would have them writing .tmp/.bak beside the player's real save.
	var tmp_path: String = save_path + TMP_SUFFIX
	var bak_path: String = save_path + BAK_SUFFIX

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open temp save file for writing: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.close()

	# Crash here and save_path still holds the previous save, untouched.
	if _should_interrupt("tmp_written"):
		return false

	# Move the live save ASIDE before moving the new one in — not merely so a
	# backup exists, but because renaming .tmp straight over a live save_path
	# would not be atomic. DirAccess.rename_absolute deletes an existing
	# destination first (DirAccessWindows::rename), so a direct overwrite has
	# its own delete-then-rename window in which save_path does not exist and
	# nothing has been backed up. With the live file moved to .bak first, the
	# destination of the second rename is guaranteed absent and no delete runs.
	if FileAccess.file_exists(save_path):
		var bak_err: int = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(bak_path))
		if bak_err != OK:
			push_error("Save aborted: could not move the existing save to %s (error %d). The original is untouched." % [bak_path, bak_err])
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
			return false

	# Crash here and save_path DOES NOT EXIST — this is the window the fix
	# itself introduces, and .bak is the only copy of the player's progress.
	# load_game's backup fallback and save_exists' backup check are what make
	# it survivable.
	if _should_interrupt("backup_renamed"):
		return false

	var live_err: int = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(save_path))
	if live_err != OK:
		# Nothing was destroyed: the previous save is complete at .bak, which
		# load_game reads and save_exists counts. Deliberately NOT rolled back
		# here — a rollback that itself fails would leave two error paths to
		# reason about, and the .bak fallback already covers this state as the
		# same state a crash one line earlier produces.
		push_error("Save aborted: could not move %s into place (error %d). The previous save is preserved at %s." % [tmp_path, live_err, bak_path])
		return false
	return true

## A `user://` path rewritten as something the player can paste into a file
## manager. Backslashes on Windows because `globalize_path` returns forward
## slashes there and a mixed-separator path is not one a player can act on.
##
## Only ever used inside dialog text — never to open a file. Every read and
## write in this file goes through `save_path` and its suffixes.
static func _native_path(path: String) -> String:
	var native: String = ProjectSettings.globalize_path(path)
	if OS.get_name() == "Windows":
		native = native.replace("/", "\\")
	return native

## Copy a save this build refuses to load somewhere `save_game` never writes,
## and return that path ("" if the copy could not be made).
##
## NOT `.bak`. That is the atomic write's ROTATION slot: it holds whatever the
## live save was one F5 ago, so a file left there survives exactly one more save.
## The forward-incompat save has to outlive an unbounded number of them, because
## the player is being asked to go and update the game while the fresh world they
## were dropped into keeps saving over the slot.
##
## A byte copy, not a re-serialisation of the parsed Dictionary. The point of the
## file is that a NEWER build can read it, and this build cannot know what in it
## matters — round-tripping through `JSON.stringify` would silently renormalise
## number formatting and key order for a schema this build does not implement.
## What gets preserved must be what was on disk.
##
## The destination is keyed to `save_path` even when the source is the `.bak`
## sidecar: one preservation slot per save slot, holding the most recent save
## this build had to refuse.
##
## Deliberately NOT counted by `save_exists`. Counting it would make every
## subsequent boot find "a save", hand `load_game` a file it has already refused,
## and re-run the alert forever instead of loading the fresh world the player has
## been playing since. Pinned by sub-case 7 of
## scripts/tests/test_forward_incompat_save.gd.
static func _preserve_incompatible(source_path: String) -> String:
	var dest: String = save_path + INCOMPAT_SUFFIX
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		push_error("SaveSystem: could not read %s to set it aside; it has NOT been preserved." % source_path)
		return ""
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: could not write the preserved copy at %s (error %d); the save has NOT been preserved." % [dest, FileAccess.get_open_error()])
		return ""
	f.store_buffer(bytes)
	f.close()
	return dest

## Open `path` and parse it as a save Dictionary. Returns the Dictionary, or
## null if the file cannot be opened, is not valid JSON, or parses to
## something other than a Dictionary — i.e. every shape an interrupted write
## leaves behind (empty file, truncated JSON) collapses to the same null.
static func _read_save_dict(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return null
	return parsed

## Returns a LoadResult. Convention:
## - result.success == false, error_message == "" → no save file (silent).
## - result.success == false, error_message != "" → load failed; caller surfaces error.
## - result.success == true → grid_world / player / player_inventory mutated;
##   result.player_progression carries any progression state the caller needs to apply.
##   result.used_backup is true iff the data came from the .bak sidecar.
##
## Backup fallback (audit finding #12): the primary save can be absent (a crash
## between save_game's two renames) or unparseable (a pre-fix truncating write
## that was interrupted). Either way the previous save is complete at .bak and
## is tried before the load is declared a failure.
static func load_game(grid_world: Node2D, player: Node2D, player_inventory: Inventory) -> LoadResult:
	var result := LoadResult.new()
	var bak_path: String = save_path + BAK_SUFFIX
	var primary_exists: bool = FileAccess.file_exists(save_path)
	var backup_exists: bool = FileAccess.file_exists(bak_path)
	if not primary_exists and not backup_exists:
		return result   # silent failure; treat as "fresh start"

	var used_backup: bool = false
	# Which file the data actually came from. The failure paths below quote a
	# path back to the player and one of them copies that file aside, and both
	# are wrong if they assume the primary: reaching this function through the
	# backup is a supported, ordinary outcome (finding #12).
	var source_path: String = save_path
	var candidate = _read_save_dict(save_path) if primary_exists else null
	if candidate == null:
		candidate = _read_save_dict(bak_path) if backup_exists else null
		if candidate == null:
			# Both unusable — or the primary is corrupt and there is no backup
			# at all, which is what a save interrupted before it ever had a
			# predecessor looks like. Fail with a non-empty error_message so
			# the caller surfaces it; used_backup stays false.
			result.error_message = "Save file is corrupt or unreadable." if primary_exists else "Save file is missing and no usable backup was found."
			push_error(result.error_message)
			return result
		used_backup = true
		source_path = bak_path
		push_warning("SaveSystem.load_game: %s is missing or unreadable; recovering from %s." % [save_path, bak_path])

	var data: Dictionary = candidate
	var version: int = int(data.get("version", 0))
	# Migration framework (session-save-migration): older saves migrate
	# forward through the MIGRATIONS chain. Newer saves (running an old
	# binary) hard-fail — backward migration is out of scope.
	if version < SAVE_VERSION:
		var migrated = _try_migrate(data, version, SAVE_VERSION)
		if migrated == null:
			# Gap in the chain (e.g., v14 → v18 has no path), or a migration
			# returned malformed data. Caller's post-3.5 hotfix catches and
			# regenerates fresh world; player isn't stranded but their save
			# data is genuinely lost.
			result.error_message = "Save migration failed: no path from v%d to v%d." % [version, SAVE_VERSION]
			push_error(result.error_message)
			if not _is_test_fixture_path(save_path):
				OS.alert(result.error_message + "\n\nA fresh world will be generated. Original save will be overwritten on next F5.", "Save incompatible")
			return result
		data = migrated
		version = int(data.get("version", 0))   # now equals SAVE_VERSION
	elif version > SAVE_VERSION:
		# Forward-incompat: save is from a newer game binary than what's
		# running. Migration framework only walks forward; can't downgrade.
		#
		# Audit finding #21. This branch tells the player their save is
		# RECOVERABLE — update the game and it loads — and then returns the same
		# `success = false` that main.gd's post-3.5 hotfix turns into a playable
		# fresh world. The player is standing in a world that saves over the file
		# the dialog just told them to keep.
		#
		# The atomic write (finding #12) softened this without closing it: the
		# first F5 MOVES the newer save to `.bak` rather than destroying it. But
		# `.bak` is a rotating slot — the second F5 moves the fresh world onto it
		# and the newer save is gone. Two keypresses, not one. So the copy goes
		# to a suffix `save_game` never writes, and the dialog says where.
		#
		# Deliberately NOT a `success = true`, and deliberately no blocking of
		# the fresh world: CONVENTIONS.md keeps this a hard failure ("Forward
		# incompatibility ... hard-fails with a clear 'update the game' message.
		# Backward migration is out of scope"). Preserving the file and telling
		# the truth about the overwrite is the whole fix.
		var preserved: String = _preserve_incompatible(source_path)
		var msg: String = "Save is v%d; this game is v%d.\n\nUpdate the game to load this save:\n%s" % [version, SAVE_VERSION, _native_path(source_path)]
		if preserved != "":
			msg += "\n\nA fresh world will be generated. That save will be overwritten on next F5, so a copy has been kept at:\n%s" % _native_path(preserved)
		else:
			msg += "\n\nA fresh world will be generated and that save will be overwritten on next F5. A copy could NOT be made — move the file somewhere safe before playing on."
		result.error_message = "Save is from a newer game (v%d vs v%d)." % [version, SAVE_VERSION]
		push_error(msg)
		if not _is_test_fixture_path(save_path):
			OS.alert(msg, "Save incompatible")
		return result

	# v11: also hard-fail on worldgen_version mismatch. Any change to procgen
	# logic produces a different world from the same seed — applying old
	# modifications onto a different terrain would silently corrupt the save.
	var saved_worldgen_version: int = int(data.get("worldgen_version", 0))
	if saved_worldgen_version != WorldGenerator.VERSION:
		# NOT preserved, unlike the forward-incompat branch above, and that is the
		# deliberate scope of audit #21. A worldgen mismatch is not recoverable by
		# any build — the terrain the save's positions refer to cannot be
		# regenerated — so there is nothing to keep the file for, and
		# CONVENTIONS.md sanctions this fallthrough outright: "Better to surface
		# the failure and let the post-3.5 hotfix regenerate fresh."
		#
		# `source_path`, NOT `save_path`. This alert asks the player to go and
		# DELETE a file, so quoting the wrong one sends them after a file that
		# does not exist. Reaching this branch through the `.bak` fallback is an
		# ordinary outcome (finding #12): a crash between save_game's two renames
		# leaves only the backup, and a backup can have a worldgen mismatch like
		# any other save. The player then deletes nothing, the real file sits at
		# `.bak`, and the second F5 rotates it away.
		#
		# The forward-incompat branch above was fixed at `1198233`; this one was
		# missed, which is the whole reason to state the rule here rather than
		# rely on the two sites happening to agree: EVERY message that quotes a
		# path to the player quotes the path the data was read from.
		#
		# Not pinned by a test. `error_message` deliberately does not carry the
		# path (main.gd toasts it, and a full native path belongs in the modal,
		# not a toast), and the dialog text reaches only `push_error` and a
		# fixture-gated `OS.alert` — neither observable from the suite. Sub-case 8
		# of test_forward_incompat_save.gd pins that this branch is genuinely
		# REACHABLE through `.bak`, which is the precondition the defect needed;
		# the string itself is guarded by this comment and review.
		var msg: String = "Save was generated with worldgen v%d; current version is v%d.\n\nProcgen logic changed; old saves cannot be regenerated correctly. Delete the file to start fresh:\n%s" % [saved_worldgen_version, WorldGenerator.VERSION, _native_path(source_path)]
		result.error_message = "Worldgen version mismatch (v%d vs v%d) — see dialog." % [saved_worldgen_version, WorldGenerator.VERSION]
		push_error(msg)
		if not _is_test_fixture_path(save_path):
			OS.alert(msg, "Save incompatible")
		return result

	# ---- SHAPE VALIDATION (audit finding #11) ------------------------------
	# Everything below this point reads player-authored data by index. Saves
	# "may have been hand-edited, partially corrupted" (CONVENTIONS.md), and an
	# out-of-bounds index does not fail the load — it ABORTS load_game, so the
	# caller receives null rather than a LoadResult, main.gd's `result.success`
	# dereferences null, and the documented corrupt-save → fresh-world
	# fallthrough never runs. Every boot then repeats it until someone deletes
	# the file by hand. Validating shape is what keeps a bad save recoverable.
	var mistyped: String = _first_mistyped_array_field(data)
	if mistyped != "":
		result.error_message = "Save field '%s' has the wrong type: expected a list, found %s." % [mistyped, type_string(typeof(data[mistyped]))]
		push_error(result.error_message)
		return result

	# Entries dropped for being unreadable. Reported on the result so the player
	# is told; see LoadResult.skipped_entries for why silence is worse.
	var skipped: int = 0

	# Untyped on purpose. A typed `var player_pos: Array = ...` raises a runtime
	# type error on the ASSIGNMENT for a non-Array field — before any guard here
	# could run — which is one of the two crashes this finding is about.
	var player_pos = data.get("player", [0, 0])
	if player_pos is Array and player_pos.size() >= 2:
		player.global_position = Vector2(float(player_pos[0]), float(player_pos[1]))
	else:
		# Keep the default spawn and carry on: an unreadable position is one
		# field, not a reason to throw away a world full of buildings.
		push_warning("SaveSystem.load_game: 'player' is not a 2-element list (%s) — keeping the default spawn." % str(player_pos))
		skipped += 1

	grid_world.buildings.clear()
	grid_world.occupied.clear()
	TickSystem.current_tick = int(data.get("tick", 0))

	# v11 procgen rehydration: regenerate the canonical world from the seed,
	# then apply player modifications on top.
	var saved_seed: int = int(data.get("world_seed", 0))
	var generator := WorldGenerator.new()
	generator.generate(grid_world, saved_seed)

	# Apply player modifications. Each entry overwrites the canonical tile
	# at that position — represents what the player did to that tile.
	# Also sync resource_state: if a modification cleared the resource_node,
	# erase any stale richness state; otherwise leave (richness regenerated).
	for entry in data.get("tile_modifications", []):
		# 4 = highest index read unconditionally (entry[3]) + 1. entry[4] keeps
		# its own inline guard: it arrived at v8 and is genuinely optional.
		if not _entry_ok(entry, 4, "tile_modifications"):
			skipped += 1
			continue
		var pos := Vector2i(int(entry[0]), int(entry[1]))
		var rnode: int = int(entry[4]) if entry.size() > 4 else ResourceNodes.DEFAULT
		var modified := Tile.new(int(entry[2]), int(entry[3]), rnode)
		grid_world.tiles[pos] = modified
		grid_world.tile_modifications[pos] = modified
		if modified.resource_node == ResourceNodes.Type.NONE:
			grid_world.resource_state.erase(pos)

	# v14: apply resource_state_modifications (generic Dict shape).
	# WorldGenerator already restored canonical resource_state from seed
	# (with original_richness for ore patches); this overlay merges the
	# saved state fields on top:
	#   {"richness": N}            → ore: overwrite richness, keep original
	#   {"regrowth_remaining": F}  → tree: insert regrowth state (tile.resource_node
	#                                already cleared by tile_modifications above)
	grid_world.resource_state_modifications.clear()
	for entry in data.get("resource_state_modifications", []):
		# 2 = entry[1] + 1. entry[2] already had this file's one defensive read
		# — the pattern every guard here mirrors.
		if not _entry_ok(entry, 2, "resource_state_modifications"):
			skipped += 1
			continue
		var rs_pos := Vector2i(int(entry[0]), int(entry[1]))
		# A row that passed `_entry_ok(entry, 2, …)` can still be missing its
		# payload — `min_size` is 2 because entry[1] is the highest UNCONDITIONAL
		# read, and entry[2] is read behind this test. Until this branch existed
		# the payload was replaced with `{}`, which was a drop with two costs the
		# skip counter never saw: the tile's saved richness or regrowth was gone,
		# and the empty dict was written into `resource_state_modifications`, so
		# `save_game` re-serialised the junk row on the next F5 and it persisted
		# for the life of the save. Skipping the row entirely stops that.
		if not (entry.size() > 2 and entry[2] is Dictionary):
			push_warning("SaveSystem.load_game: skipping 'resource_state_modifications' entry with an unreadable payload: %s" % str(entry))
			skipped += 1
			continue
		var rs_state: Dictionary = entry[2]
		# Store the modification as-is (defensive copy).
		grid_world.resource_state_modifications[rs_pos] = rs_state.duplicate()
		# Merge into resource_state. For ore tiles, the canonical state already
		# has richness + original_richness from procgen — overwrite richness.
		# For tree-regrowth tiles, the canonical state may not exist (tree was
		# at default mature) — create the entry from the saved dict.
		if rs_state.has("richness"):
			if grid_world.resource_state.has(rs_pos):
				grid_world.resource_state[rs_pos]["richness"] = int(rs_state["richness"])
			# else: tile not present in canonical resource_state.
			#
			# DELIBERATELY NOT COUNTED, unlike the payload drop above, and the
			# difference is whether anything was lost. The entry was stored into
			# `resource_state_modifications` two lines up, so it round-trips to
			# disk intact and a later build that regenerates ore there will apply
			# it. Nothing is dropped — a saved richness simply has no canonical
			# state to merge into, which means the save and procgen disagree about
			# what is at this tile, and `worldgen_version` hard-fails the only
			# thing that causes that at scale. Counting it would put "1 damaged
			# entry skipped" in front of the player for data that is intact.
		elif rs_state.has("regrowth_remaining"):
			# Tree regrowth: canonical state is "mature" (no entry). Insert
			# the regrowth dict AND register it in the regrowth index —
			# _tick_regrowth iterates the index, not resource_state (audit
			# #29), so without the second line a loaded timer never ticks
			# and the tree silently never regrows.
			grid_world.resource_state[rs_pos] = rs_state.duplicate()
			grid_world._active_regrowth[rs_pos] = true

	# v16: restore tile_soil_modifications. Sparse — absent entries default
	# to TILE_SOIL_FULL (100) on read via tile_soil_health(). Old v15 saves
	# (region-scoped) hard-fail at the version check above; no migration.
	grid_world.tile_soil_modifications.clear()
	for entry in data.get("tile_soil_modifications", []):
		if not _entry_ok(entry, 3, "tile_soil_modifications"):   # entry[2] + 1
			skipped += 1
			continue
		var soil_tile := Vector2i(int(entry[0]), int(entry[1]))
		grid_world.tile_soil_modifications[soil_tile] = int(entry[2])

	# v17: restore tile_fertilizer_state. Sparse — absent tiles have no
	# active boost (default behavior, regen at 1×). Default-empty get() so
	# v16 saves promoted to v17 (after a hard-fail + manual delete + fresh
	# game) just have an empty dict. Pre-v17 saves hard-fail at version
	# check above.
	grid_world.tile_fertilizer_state.clear()
	for entry in data.get("tile_fertilizer_state", []):
		if not _entry_ok(entry, 4, "tile_fertilizer_state"):   # entry[3] + 1
			skipped += 1
			continue
		var fert_tile := Vector2i(int(entry[0]), int(entry[1]))
		grid_world.tile_fertilizer_state[fert_tile] = {
			"tier": int(entry[2]),
			"remaining": float(entry[3]),
		}

	# v18: restore tile_wasteland_state. Sparse — absent tiles are
	# healthy (no grace, no scar). Both fields persist so a tile
	# mid-scarring picks up from its saved decay_remaining. Pre-v18
	# saves hard-fail at version check above.
	grid_world.tile_wasteland_state.clear()
	for entry in data.get("tile_wasteland_state", []):
		if not _entry_ok(entry, 4, "tile_wasteland_state"):   # entry[3] + 1
			skipped += 1
			continue
		var ws_tile := Vector2i(int(entry[0]), int(entry[1]))
		grid_world.tile_wasteland_state[ws_tile] = {
			"scarred": bool(entry[2]),
			"decay_remaining": float(entry[3]),
		}

	# v12: restore explored regions as fog. Active state will be set by
	# main.gd's vision update after load completes (running update_vision
	# from the loaded player position).
	grid_world.region_visibility.clear()
	for entry in data.get("explored_regions", []):
		if not _entry_ok(entry, 2, "explored_regions"):   # entry[1] + 1
			skipped += 1
			continue
		grid_world.region_visibility[Vector2i(int(entry[0]), int(entry[1]))] = 1

	for bdict in data.get("buildings", []):
		# Dictionary entries, not Arrays — Building.from_dict takes a Dictionary
		# and a non-Dictionary aborts the load at the call, not inside it.
		if not (bdict is Dictionary):
			push_warning("SaveSystem.load_game: skipping malformed 'buildings' entry: %s" % str(bdict))
			skipped += 1
			continue
		# `from_dict` returns null when the entry is a Dictionary but not a
		# READABLE one — today that means a non-Dictionary `"s"`. Without this
		# check the next line dereferences null and aborts the whole load, which
		# is the bricked-boot shape audit #11 is about; the container and
		# entry-type guards above both pass such an entry through.
		var b: Building = Building.from_dict(bdict)
		if b == null:
			skipped += 1
			continue
		grid_world.buildings[b.anchor] = b
		var fp: Vector2i = Buildings.footprint_of(b.type)
		for dx in fp.x:
			for dy in fp.y:
				grid_world.occupied[Vector2i(b.anchor.x + dx, b.anchor.y + dy)] = b.anchor

	# LAST WORLD MUTATION ABOVE. Everything from here down touches the player's
	# inventory and the LoadResult, not grid_world — so this is the end of the
	# world-mutation section and the only correct place for the two lines below.
	#
	# The buildings loop rewrote grid_world.buildings and .occupied DIRECTLY.
	# place_building and remove_building_at are the only paths that set the
	# network dirty flags, and this function goes through neither, so without
	# these calls every cache keyed off the building set stays describing the
	# world we just replaced: GridWorld._pipe_component / _component_has_pump
	# on the fluid side, and PowerNetwork's _pole_component / _pole_cells on
	# the power side.
	#
	# A BOOT-TIME load was always safe — both flags initialise true — which is
	# why this survived to be audit finding #1 (HIGH,
	# docs/audits/2026-07-19-flaw-review.md). The live failure is the
	# MID-SESSION F9 quick-load: main.gd reuses the standing GridWorld, whose
	# flags were cleared to false by any earlier query (a pipe draw, a lamp
	# tick), so the loaded world answers connectivity questions about the
	# previous one until the player happens to place or remove something.
	#
	# BOTH halves, deliberately. They are one defect at one site, and fixing
	# the half whose symptom was reported is how the other gets forgotten.
	# Regression coverage: scripts/tests/test_load_network_invalidation.gd.
	grid_world.mark_power_network_dirty()
	grid_world.mark_fluid_network_dirty()

	if data.has("player_inventory"):
		# No `is Array` check needed for the FIELD: it is in ARRAY_FIELDS, so a
		# non-Array already failed the load above, and `load_array` is typed
		# `(arr: Array)` so a non-Array would abort on the call itself.
		#
		# That covers the container and NOTHING ELSE — the rows inside it are
		# player-authored too, and this comment used to stop at the sentence
		# above, which read as "this line is guarded". It was not. An unguarded
		# `entry[1]` inside `load_array` aborted only `load_array`, so control
		# returned here and ran on to `result.success = true` with every slot
		# from the bad row onward silently unwritten. `load_array` guards its own
		# rows now and RETURNS the count, which has to be added to `skipped` —
		# dropping the return value on the floor restores the silent truncation
		# with the guard still in place.
		skipped += player_inventory.load_array(data["player_inventory"])

	# Type-checked before assignment. `LoadResult.player_progression` is a typed
	# `Dictionary`, so a save whose `player_progression` is a String or a list
	# raises on the ASSIGNMENT — aborting `load_game` after every world mutation
	# above has already been applied, handing `main.gd` null, and bricking the
	# boot exactly as audit #11 describes. `ARRAY_FIELDS` cannot cover this one:
	# the field is supposed to be a Dictionary, so the array-field validator has
	# nothing to say about it. Dropping it costs the player their bag-cap
	# progression and cursor stack, which is a skipped entry like any other.
	var loaded_progression = data.get("player_progression", {})
	if loaded_progression is Dictionary:
		result.player_progression = loaded_progression
	else:
		push_warning("SaveSystem.load_game: 'player_progression' is %s, not a Dictionary — keeping the caller's defaults." % type_string(typeof(loaded_progression)))
		skipped += 1
	# Same convention as used_backup below: reported on success only. Set here
	# rather than at each skip site so there is exactly one place where the
	# count reaches the caller.
	result.skipped_entries = skipped
	if skipped > 0:
		push_warning("SaveSystem.load_game: %d unreadable entr%s skipped." % [skipped, "y was" if skipped == 1 else "ies were"])
	# Set here, not where the source was chosen: the convention is that
	# used_backup is meaningful only on success, and every error branch above
	# returns before this point rather than reporting a backup for a load that
	# did not happen.
	result.used_backup = used_backup
	result.success = true
	return result

## Every top-level save field `load_game` iterates as an Array (audit #11).
##
## A field present with the WRONG TYPE — a String or Dictionary where a list
## belongs — is a whole-collection failure, not a skippable entry: nothing in it
## can be salvaged, and quietly loading an empty collection over a real save is
## the same silent data loss the finding is about. It fails the load with a
## named field so `main.gd` regenerates a fresh world and says why.
##
## Note the loops below iterate a String character-by-character and a Dictionary
## key-by-key perfectly happily, so without this check a mistyped field does not
## announce itself — it crashes several rows in, on a character.
const ARRAY_FIELDS: Array = [
	"tile_modifications",
	"resource_state_modifications",
	"tile_soil_modifications",
	"tile_fertilizer_state",
	"tile_wasteland_state",
	"explored_regions",
	"buildings",
	"player_inventory",
]

## Name of the first ARRAY_FIELDS entry that is present but is not an Array, or
## "" when every present field is well-typed. Absent fields are fine — every
## loop uses `data.get(name, [])` and sparse collections are the norm.
##
## Checked BEFORE the first world mutation on purpose: a mistyped field found
## half-way through would leave grid_world rebuilt from the seed with some
## collections applied and others not, and the caller cannot tell that apart
## from a successful load.
static func _first_mistyped_array_field(data: Dictionary) -> String:
	for field in ARRAY_FIELDS:
		if data.has(field) and typeof(data[field]) != TYPE_ARRAY:
			return field
	return ""

## True if `entry` is an Array long enough for the caller's highest direct
## index. `min_size` is that index + 1, derived per collection at each call
## site from the code immediately below it.
##
## A malformed row is SKIPPED rather than fatal: one hand-corrupted line should
## cost the player that line, not the world. Callers increment their own counter
## so the number reaches LoadResult; this only reports readability and warns.
## Mirrors the one defensive read this file already had, at the
## resource_state_modifications loop's `entry[2] is Dictionary` test.
static func _entry_ok(entry, min_size: int, field: String) -> bool:
	if entry is Array and entry.size() >= min_size:
		return true
	push_warning("SaveSystem.load_game: skipping malformed '%s' entry: %s" % [field, str(entry)])
	return false

## True if there is anything to load. Counts the .bak sidecar (audit #12): a
## crash between save_game's two renames leaves save_path absent while .bak
## holds the whole of the player's progress, and main.gd gates its load call
## on this — a save_path-only check would skip straight to fresh-world
## generation and lose a save that load_game could have recovered.
static func save_exists() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + BAK_SUFFIX)
