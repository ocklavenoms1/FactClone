class_name GridWorld
extends Node2D

## The world. Source of truth for terrain and buildings.
## Sparse storage — only modified tiles exist in the dicts.
##
## Buildings are dumb data (Building class). Behavior is dispatched
## by Buildings.tick_one() / draw_one() based on type.

const TILE_SIZE: int = 32
const GRID_COLOR: Color = Color(0.25, 0.35, 0.25, 0.6)
const VIEW_PADDING_TILES: int = 4

# World boundary — Stage 1 generates a finite 512×512 region centered on origin.
# Stage 3 extends to chunked infinite generation (capped at 1M each direction).
# Tile coords valid range: [WORLD_MIN, WORLD_MAX-1] inclusive in each axis.
const WORLD_HALF_EXTENT: int = 256                              # Stage 1: 512×512 = 256 each side
const WORLD_MIN: int = -WORLD_HALF_EXTENT                       # -256
const WORLD_MAX: int = WORLD_HALF_EXTENT                        # 256 (exclusive)

# World generation seed. Set by main.gd at startup (random for new game,
# loaded from save for existing). WorldGenerator uses this to seed every
# noise instance + the tree-placement hash.
var world_seed: int = 0

# tile_modifications: Vector2i -> Tile. Sparse storage of tiles that DIFFER
# from worldgen output. The full world is the procgen-canonical generation
# of `world_seed` (see WorldGenerator) PLUS these modifications applied on top.
# Save/load only persists this dict; loaded worlds are reconstructed by
# regenerating from seed and applying modifications.
#
# `tiles` (the rendered/queried dict) holds the FULL post-rehydration view —
# both procgen output and modifications merged. Reads use `tiles`; writes
# go through helpers that ALSO update `tile_modifications` so saves stay correct.
var tiles: Dictionary = {}            # Vector2i -> Tile (post-rehydration view)
var tile_modifications: Dictionary = {}  # Vector2i -> Tile (player edits only)
var resource_state: Dictionary = {}   # Vector2i -> Dictionary (richness/original_richness/growth, sparse)

# resource_state_modifications: Vector2i -> int (current richness).
# Sparse delta from procgen-canonical resource_state, persisted in v13+ saves.
# Parallel architecture to tile_modifications: WorldGenerator.generate()
# repopulates resource_state from seed at load; resource_state_modifications
# overlays player-driven mining changes on top. original_richness is NOT
# persisted (rederived from procgen).
var resource_state_modifications: Dictionary = {}

# Sparse index of ACTIVE tree-regrowth timers: Vector2i -> true. This exists
# because worldgen seeds resource_state with an entry for EVERY ore tile
# (~8.4k entries at seed 42), so `resource_state.is_empty()` is never true and
# a per-frame walk over all of it costs ~1.0 ms/frame with zero chopped trees
# (measured 2026-08-26, audit #29). _tick_regrowth iterates THIS dict instead.
#
# INVARIANT: pos is in _active_regrowth IFF resource_state[pos] has
# "regrowth_remaining". _tick_regrowth indexes resource_state[pos] WITHOUT a
# guard on purpose: a stale index entry faults loudly (SCRIPT ERROR every
# frame) instead of being silently healed — silent compensation is this
# project's recurring failure shape, and a tolerant read here would hide a
# missed invalidation edge forever. The write sites, each mutation-tested by
# test_regrowth_index.gd: chop_tree (add), _restore_tree (erase), the
# set_overlay and place_building cancel paths (erase), the save-load regrowth
# branch in save_system.gd (add), and WorldGenerator.generate (bulk clear,
# beside resource_state.clear()). Not serialized — rebuilt from the save's
# resource_state_modifications on load.
var _active_regrowth: Dictionary = {}
var buildings: Dictionary = {}        # Vector2i (anchor) -> Building
var occupied: Dictionary = {}         # Vector2i (any footprint cell) -> Vector2i (anchor)

# region_visibility: Vector2i (region coords) -> int state
#   0 = unrevealed (sparse — no entry means unrevealed)
#   1 = fog (charted but not currently in vision; persisted)
#   2 = active (currently in player's 5×5 vision; recomputed at load)
#
# Save format persists ONLY entries with value >= 1 as `explored_regions`
# (state collapses to 1 on save). On load, all loaded entries enter as
# state=1, then update_vision() upgrades the 5×5 around player to state=2.
var region_visibility: Dictionary = {}

# Soil exhaustion (session-soil-exhaustion-1, refactored to per-tile at
# session-soil-exhaustion-2). Each TILE has its own soil_health 0..100.
# Default 100 (pristine) — sparse storage; only modified tiles appear.
#
# Architectural reversal from Session 1's region-based model: playtest
# revealed that 32×32 region scope made one planter affect 1024 tiles,
# disconnecting cause from effect. Per-tile scope localizes depletion to
# the immediate 3×3 around each planter (see deplete_planter_area).
#
# Save format: `tile_soil_modifications` field (Array of [x, y, soil]).
# Saves at v16. v15 saves hard-fail (region-scoped data not migrated;
# soil mechanic is fresh enough that no meaningful save state lost).
var tile_soil_modifications: Dictionary = {}    # Vector2i (tile pos) -> int (0..100)

# Per-tile "pristine" baseline. Anchored as a constant so future sessions
# (fertilizer chain, wasteland) reference the canonical full value.
const TILE_SOIL_FULL: int = 100

# Soil regen (session-soil-exhaustion-2). Per-frame fractional progress
# accumulated when a tile is depleted AND no active planter's 3×3 area
# overlaps it. When progress >= 1.0, soil increments by floor(progress)
# and the float remainder carries over.
#
# Per design Q5: NOT serialized. Save/load loses up to SECONDS_PER_SOIL_POINT
# of pending regen progress per tile. Negligible UX cost.
#
# Per design Q3 (locked): 1 point per 30 sec. Full pristine recovery
# (0 → 100) takes 50 minutes wall-clock when no active farming nearby.
var tile_regen_progress: Dictionary = {}    # Vector2i (tile) -> float (0..1+)
const SECONDS_PER_SOIL_POINT: float = 30.0

# Per-tile fertilizer state (session-soil-exhaustion-3). Sparse — only
# tiles with active boost appear. Decays in real time independently of
# soil state; expired tiles are erased.
#
# Shape: Vector2i (tile) -> { "tier": Items.Type (LOW or MID), "remaining": float (sec) }
#
# Save format: `tile_fertilizer_state` field at v17. Sparse Array of
# [x, y, tier_int, remaining_float]. v16 hard-fails (no migration).
#
# Storage choice (parallel sparse dict, NOT extending tile_soil_modifications):
# fertilizer + soil have different lifetimes (fertilizer expires after
# 30-60 sec; soil mods can persist for the full game). Coupling them
# in one dict creates entry-erase ordering bugs. Mirrors the Tree
# regrowth pattern (separate `resource_state_modifications` dict).
var tile_fertilizer_state: Dictionary = {}

# Fertilizer per-tier configuration is inlined in the two static helpers
# below. Three tiers post-Session-4 (LOW/MID/HIGH). Tier value IS the
# Items.Type so stacking comparisons are direct (HIGH > MID > LOW because
# COMPOST_HIGH > COMPOST_MID > COMPOST_LOW in enum order — append-only
# enum locks the ordering invariant).

# Wasteland state (session-soil-exhaustion-4). Sparse parallel dict —
# only tiles in grace OR scarred have entries.
#
# Shape: Vector2i (tile) -> { "scarred": bool, "decay_remaining": float }
#   - "scarred" == false, decay_remaining > 0: tile in grace period;
#     will scar when remaining hits 0.
#   - "scarred" == true:                       tile is wasteland;
#     decay_remaining ignored (kept for save-shape stability).
#
# Save format: tile_wasteland_state field at v18, sparse Array of
# [x, y, scarred_bool, decay_remaining_float]. v17 hard-fails (no migration).
#
# Trigger: in _tick_soil_regen, any tile in tile_soil_modifications
# whose soil_health == 0 starts/advances the grace timer. Soil rising
# above 0 (via fertilizer + regen) before grace expiry erases the entry
# (no scar). Once scarred, only Premium Compost via try_apply_fertilizer
# clears the entry (de-wastelanding).
var tile_wasteland_state: Dictionary = {}

# Grace period before a soil-0 tile scars. 60 sec gives the player ~2
# wheat-harvest cycles to react. Tunable from playtest data.
const WASTELAND_GRACE_SEC: float = 60.0

# Soil value Premium Compost snaps a wasteland tile to. Partial restoration
# (DAMAGED range, not full healing). Combined with the 8× boost / 120s,
# total wasteland-to-fully-healed is designed at ~21 min:
#   30 → 62  via 8× boost in 120 sec (32 points)
#   62 → 100 via natural regen (38 pts × 30 sec/pt) ≈ 19 min
# This is intentional — wasteland is a real loss. Tunable from playtest.
const WASTELAND_RESTORE_SOIL: int = 30

## Returns the regen multiplier for a given fertilizer tier (item type).
## Returns 1.0 for unknown tiers (defensive — old saves with future tiers
## should regen at normal rate, not crash).
static func fertilizer_multiplier(tier: int) -> float:
	if tier == Items.Type.COMPOST_LOW: return 2.0
	if tier == Items.Type.COMPOST_MID: return 4.0
	if tier == Items.Type.COMPOST_HIGH: return 8.0
	return 1.0

## Returns the active-boost duration (sec) for a given fertilizer tier.
## Returns 0.0 for unknown tiers (defensive).
static func fertilizer_duration(tier: int) -> float:
	if tier == Items.Type.COMPOST_LOW: return 30.0
	if tier == Items.Type.COMPOST_MID: return 60.0
	if tier == Items.Type.COMPOST_HIGH: return 120.0
	return 0.0

## Soil level enum (per-tile). Pure function of soil_health value; NOT
## related to nearby planter state. Used by visual rendering and Q-inspect
## status labels.
enum SoilLevel {
	PRISTINE,    # 100         (no modifications entry)
	HEALTHY,     # 70..99      (no visual tint — same as PRISTINE visually)
	DAMAGED,     # 30..69      (yellow-brown overlay)
	DYING,       # 1..29       (brown overlay)
	DEAD,        # 0           (dark cracked-earth tint)
}

## Soil activity enum (per-tile). Orthogonal to SoilLevel — tracks
## whether a planter is currently affecting this tile vs whether the tile
## is being passively recovered.
enum SoilActivity {
	NONE,             # tile is pristine (not modified) OR fully recovered
	ACTIVE_FARMING,   # an active planter's 3×3 area overlaps this tile
	REGENERATING,     # in modifications, soil < 100, no active planter affects
}

# Vision parameters. VISION_RADIUS is Chebyshev distance; the 5×5 area is
# (2*VISION_RADIUS + 1)^2 = 25 regions when radius = 2.
const VISION_RADIUS: int = 2

# Initial reveal at fresh game start: regions within INITIAL_REVEAL_RADIUS
# of (0, 0) start as fog. Provides "spawn vicinity" context on first M-press.
# Radius 3 → 7×7 area = 49 regions ≈ 19% of the 16×16 world. Most of map
# remains unrevealed for exploration.
const INITIAL_REVEAL_RADIUS: int = 3

var hover_tile: Vector2i = Vector2i.ZERO
var show_hover: bool = false
## When the hotbar selection is a directional building, main.gd sets this
## to the placement direction (Belt.DIR_E etc). -1 = no direction preview.
var hover_arrow_dir: int = -1
## When the hotbar selection is a building, main.gd sets this so the hover
## preview shows the full footprint (e.g. 2×2 for Mixer). -1 = single tile.
var hover_building_type: int = -1

## Failure reasons set by set_overlay / clear_tile / can_place_building.
## main.gd reads these to surface a user-friendly toast.
var last_place_error: String = ""
var last_remove_error: String = ""
var last_building_place_error: String = ""

# ---------- fluid network state ----------
# Connectivity-only model. No flow simulation; queries answer "is there
# a pipe-network with a pump reachable from this position?"
#
# Rebuilt lazily via BFS over pipe positions. Any place_building/remove_building
# touching a PIPE or PUMP marks the network dirty.
var _fluid_network_dirty: bool = true
var _pipe_component: Dictionary = {}      # Vector2i -> int (component id)
var _component_has_pump: Dictionary = {}  # int -> bool

# Power network — mirrors fluid network pattern (BFS + dirty-flag). See
# scripts/world/power_network.gd for the resolver module. Linear-
# satisfaction model: each component has a ratio in [0, 1] applied by
# consumers to scale their throughput/visual feedback.
var _pole_component: Dictionary = {}              # Vector2i (pole ANCHOR) → int (component id)
# Every footprint cell of every pole, mapped back to that pole's anchor.
# Rebuilt alongside _pole_component by PowerNetwork.rebuild_topology and read
# by PowerNetwork._covering_component_id. A 1x1 pole contributes one entry
# that duplicates its _pole_component key; the 2x2 substation contributes
# four, which is the whole reason this exists — consumer queries arrive as raw
# cells and cannot know a multi-cell pole's anchor.
var _pole_cells: Dictionary = {}                  # Vector2i (any pole footprint cell) → Vector2i (that pole's anchor)
var _component_supply: Dictionary = {}            # int (comp_id) → int (units)
var _component_demand: Dictionary = {}            # int (comp_id) → int (units)
var _component_satisfaction: Dictionary = {}      # int (comp_id) → float in [0, 1]
var _power_network_dirty: bool = true
# Electricity Session 2 (session-electricity-generators-storage) — accumulator
# 3-stage update_supply_demand needs additional per-component intermediate
# state. Populated by PowerNetwork.update_supply_demand each tick.
var _component_raw_supply: Dictionary = {}            # int (comp_id) → int (units; generators only, before accumulator effects)
var _component_accumulators: Dictionary = {}          # int (comp_id) → Array[Building] (accumulator buildings per component)
var _component_accumulator_supply: Dictionary = {}    # int (comp_id) → float (total discharge contribution)
var _component_accumulator_drain: Dictionary = {}     # int (comp_id) → float (total charge consumption)

@export var camera: Camera2D

# Additive glow pass for the sprite path (session-art-probe-1). Null unless
# SpriteLibrary.enabled has been true at least once this run — see _process.
var _sprite_glow_layer: Node2D = null

func _ready() -> void:
	TickSystem.tick.connect(_on_tick)

func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))

func tile_to_world_origin(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

func tile_to_world_center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)

# ---------- tile accessors ----------

## Read base at pos (default GRASS for tiles not in the dict).
func base_at(pos: Vector2i) -> int:
	if tiles.has(pos):
		return tiles[pos].base
	return Terrain.DEFAULT_BASE

## Read overlay at pos (default NONE for tiles not in the dict).
func overlay_at(pos: Vector2i) -> int:
	if tiles.has(pos):
		return tiles[pos].overlay
	return Terrain.DEFAULT_OVERLAY

## Convenience: is this a water tile?
func is_water_at(pos: Vector2i) -> bool:
	return base_at(pos) == Terrain.Base.WATER

## Player passability check at a tile coord. Three layers:
##   1. Tile base — water blocks (Tile.is_passable returns false on WATER).
##   2. Building — non-walkable buildings block (per-DATA `walkable` flag,
##      default false). Multi-tile buildings block all their footprint
##      cells automatically because `occupied` maps each cell to the same
##      Building instance.
##   3. Default-grass tiles (no entry in `tiles`) are passable.
##
## Extended at Cluster C (post-session-inserter-fast-filter): the building
## layer was added to fix the "player walks visually through buildings"
## UX wart. Belts are the only currently-walkable building (Factorio
## convention).
func is_passable_at(pos: Vector2i) -> bool:
	# Layer 1: tile base (water).
	if tiles.has(pos) and not tiles[pos].is_passable():
		return false
	# Layer 2: building.
	if occupied.has(pos):
		var b: Building = building_at(pos)
		if b != null and not Buildings.is_walkable(b.type):
			return false
	# Layer 3: default-grass tiles fall through as passable.
	return true

# ---------- placement / removal ----------

## Paint an overlay at pos. Returns true on success.
## Sets last_place_error on failure.
##
## RULE (locked in mining-manual session, reversing yesterday's design):
## Overlays cannot be placed on tiles with a resource_node. Player must
## mine the deposit out (richness → 0, tile reverts to grass) before
## paving. Reasoning: prevents the UX trap where a player accidentally
## paves over a deposit and loses track of it. Matches the stewardship
## theme — you mine an iron vein, you don't pave over it.
##
## (Trees are also resource_nodes; they can't be paved over either. Tree
## harvesting is a future-session mechanic; for now, players can't pave
## tree tiles. They can paint around them.)
func set_overlay(pos: Vector2i, overlay: int) -> bool:
	last_place_error = ""
	if has_building_at(pos):
		last_place_error = "Can't paint terrain under a building"
		return false
	# Block overlay placement on deposit / tree tiles.
	if tiles.has(pos) and tiles[pos].resource_node != ResourceNodes.Type.NONE:
		var rname: String = ResourceNodes.name_of(tiles[pos].resource_node)
		if ResourceNodes.is_ore(tiles[pos].resource_node):
			last_place_error = "Mine the %s first." % rname.to_lower()
		else:
			last_place_error = "Can't pave over %s." % rname.to_lower()
		return false
	# Cancel any active tree regrowth at this position. Player paving a
	# chopped tile committed to that decision — the tree won't regrow here.
	# Specifically check for "regrowth_remaining" rather than blanket-erasing
	# resource_state — defensive against future code paths that programmatically
	# call set_overlay on tiles with other resource state shapes.
	if resource_state.has(pos):
		var rstate: Dictionary = resource_state[pos]
		if rstate.has("regrowth_remaining"):
			resource_state.erase(pos)
			resource_state_modifications.erase(pos)
			# Index invalidation (audit #29): this erase lands together with
			# the two above — a surviving index entry faults _tick_regrowth.
			_active_regrowth.erase(pos)
		# Else: leave other state intact (overlay-on-ore is blocked above
		# at the resource_node validation; this branch shouldn't fire for
		# ore tiles, but stays defensive).
	var base: int = base_at(pos)
	var current_overlay: int = overlay_at(pos)
	if not Terrain.can_place_overlay(overlay, base, current_overlay):
		last_place_error = "Can't place %s on %s" % [
			Terrain.overlay_name(overlay),
			Terrain.effective_name(base, current_overlay),
		]
		return false
	if current_overlay == overlay:
		return true  # idempotent
	# Mutate or insert. resource_node is GUARANTEED to be NONE here (early
	# return above blocks any deposit/tree tile), so the new tile carries
	# Tile.resource_node = NONE.
	if tiles.has(pos):
		tiles[pos].overlay = overlay
	else:
		tiles[pos] = Tile.new(Terrain.DEFAULT_BASE, overlay, ResourceNodes.DEFAULT)
	# Record as modification so save/load preserves the player's edit.
	tile_modifications[pos] = Tile.new(tiles[pos].base, tiles[pos].overlay, tiles[pos].resource_node)
	return true

## RMB action. Returns true on success (or harmless no-op).
##   - building present: remove building (always allowed)
##   - overlay present:  clear overlay back to NONE (always allowed; player placed it)
##   - bare base (grass or water): silent no-op (nothing to remove)
##
## Clearing the overlay preserves base + resource_node. With the
## "no overlay on deposits" rule, resource_node is always NONE on tiles
## that have an overlay — but the preservation path stays defensive
## (cheap, future-proof if rule changes).
func clear_tile(pos: Vector2i) -> bool:
	last_remove_error = ""
	if has_building_at(pos):
		remove_building_at(pos)
		return true
	if not tiles.has(pos):
		return true  # implicit grass — nothing here
	var t: Tile = tiles[pos]
	if t.has_overlay():
		t.overlay = Terrain.Overlay.NONE
		# Record as modification so save/load preserves the cleared state.
		# Even if the resulting tile matches procgen-default exactly, we
		# record it; save-time optimization could prune at serialize time.
		tile_modifications[pos] = Tile.new(t.base, t.overlay, t.resource_node)
		# If the entry collapses to pure default AND has no resource_node,
		# drop from tiles. The modification record stays so save knows the
		# player explicitly cleared this position.
		if t.base == Terrain.DEFAULT_BASE and t.resource_node == ResourceNodes.DEFAULT:
			tiles.erase(pos)
		return true
	# Bare base tile (water, or an explicit grass entry — though we don't keep those).
	return true


# ---------- buildings ----------

func has_building_at(pos: Vector2i) -> bool:
	return occupied.has(pos)

func building_at(pos: Vector2i) -> Building:
	if not occupied.has(pos):
		return null
	return buildings.get(occupied[pos], null)

## Footprint cells for a building of given type with anchor at `pos`.
func _footprint_cells(t: int, pos: Vector2i) -> Array:
	var fp: Vector2i = Buildings.footprint_of(t)
	var cells: Array = []
	for dx in fp.x:
		for dy in fp.y:
			cells.append(Vector2i(pos.x + dx, pos.y + dy))
	return cells

## Can a building of `type` be placed with anchor at `pos`?
## Checks footprint vacancy + overlay compatibility, plus type-specific
## constraints (e.g. Pump must have an adjacent water tile).
## On failure, sets last_building_place_error to a user-friendly reason.
func can_place_building(t: int, pos: Vector2i) -> bool:
	last_building_place_error = ""
	var allowed_overlays: Array = Buildings.requires_overlay(t)
	for cell in _footprint_cells(t, pos):
		if has_building_at(cell):
			last_building_place_error = "%s: tile already occupied" % Buildings.name_of(t)
			return false
		# Water / deposits / trees all carry Overlay.NONE (overlays are
		# forbidden on them), so the overlay check below reads their
		# PROTECTED status as permission. Guard them explicitly, or every
		# Overlay.NONE-accepting building (smelter, composter, inserters,
		# applicator, power pole, lamp) places mid-lake or buries a
		# deposit. Same invariant set_overlay enforces, same messaging.
		if base_at(cell) == Terrain.Base.WATER:
			last_building_place_error = "%s can't be placed on water" % Buildings.name_of(t)
			return false
		# MINING_DRILL is exempt — it must sit on ore. Its own
		# validate_placement rejects water and trees in-footprint.
		if t != Buildings.Type.MINING_DRILL and tiles.has(cell) \
				and tiles[cell].resource_node != ResourceNodes.Type.NONE:
			var rname: String = ResourceNodes.name_of(tiles[cell].resource_node)
			if ResourceNodes.is_ore(tiles[cell].resource_node):
				last_building_place_error = "Mine the %s first." % rname.to_lower()
			else:
				last_building_place_error = "Can't build over %s." % rname.to_lower()
			return false
		if not (overlay_at(cell) in allowed_overlays):
			var names: Array = []
			for o in allowed_overlays:
				names.append(Terrain.overlay_name(o))
			last_building_place_error = "%s needs: %s" % [Buildings.name_of(t), ", ".join(names)]
			return false
	# Type-specific extra rules.
	if t == Buildings.Type.PUMP and not Pump.is_valid_placement(self, pos):
		last_building_place_error = "Pump must be placed adjacent to water"
		return false
	if t == Buildings.Type.MINING_DRILL:
		var err: String = MiningDrill.validate_placement(self, pos)
		if err != "":
			last_building_place_error = err
			return false
	return true

## Should the placement hover preview render RED at `anchor` while the player
## holds `building_type`?
##
## EXTRACTED FROM `_draw` DELIBERATELY (audit #16). The predicate used to sit
## inline in the hover branch, where nothing could test it: `test_runner.gd`
## never yields a frame, so no `CanvasItem` here receives NOTIFICATION_DRAW
## (NOTES.md, "A structural ceiling"). A one-line correction applied in place
## would have shipped green with no assertion able to touch it. It lives here
## so `test_hover_preview_agreement.gd` can call it without a frame.
##
## `building_type < 0` means NEUTRAL mode — the hover rect is highlighting an
## EXISTING building's footprint, which is not a placement intent and has no
## blocked state. It must return false, never fall through to the placement
## rule: `Buildings.footprint_of(-1)` is an invalid DATA index.
##
## THE BODY IS A DELEGATION AND MUST STAY ONE. It used to re-derive the rule as
## `tiles.has(cell) or has_building_at(cell)`, which asks "has this tile ever
## been MODIFIED", not "is it occupied" — a different question, wrong in both
## directions. `set_overlay` writes a `tiles` entry for every paved cell, so
## every legal placement on prepared ground previewed red; bare grass has no
## entry, so everything illegal on grass previewed free; and neither the Pump's
## water adjacency nor the drill's ore coverage was consulted at all. Re-deriving
## the rule anywhere is how the two answers drift apart; there is one rule and
## this asks it. Covered by `test_hover_preview_agreement.gd` in both directions.
##
## NO last_building_place_error SAVE/RESTORE, DELIBERATELY — the audit's fix text
## prescribed one. `_draw` does clobber the string every frame, but all three
## readers consume it inside the same synchronous call as the failed placement
## that set it (`main.gd` `_try_place`, `console.gd` `_cmd_place` twice), so no
## frame can interleave and there is nothing to protect. Two untested defensive
## lines are not free here: they would read as a live hazard that does not exist.
## The premise is asserted, not assumed — that suite's (E2) reddens if any
## reading function ever becomes a coroutine, which is the condition that would
## make the save/restore necessary.
func hover_preview_blocked(building_type: int, anchor: Vector2i) -> bool:
	if building_type < 0:
		return false
	return not can_place_building(building_type, anchor)

## `extra` is forwarded to Buildings.make for type-specific payload
## (currently only PLANTER uses it — for crop_type).
func place_building(t: int, pos: Vector2i, dir: int = 0, extra = null) -> bool:
	if not can_place_building(t, pos):
		return false
	var b: Building = Buildings.make(t, pos, dir, extra)
	if b == null:
		return false
	# Cancel any active tree regrowth in footprint cells. Player committed
	# to this build site — same rule as set_overlay (overlay-cancels-regrowth);
	# generalized to building placement so future 2×2+ buildings (Mixer,
	# Oven, MiningDrill, etc.) consistently nullify regrowth where they sit.
	# Defensive: only cancels for "regrowth_remaining" specifically; doesn't
	# touch ore richness or other resource_state fields.
	for cell in _footprint_cells(t, pos):
		if resource_state.has(cell):
			var rs: Dictionary = resource_state[cell]
			if rs.has("regrowth_remaining"):
				resource_state.erase(cell)
				resource_state_modifications.erase(cell)
				# Index invalidation (audit #29): lands together with the two
				# erases above — a surviving index entry faults _tick_regrowth.
				_active_regrowth.erase(cell)
	buildings[pos] = b
	for cell in _footprint_cells(t, pos):
		occupied[cell] = pos
	if t == Buildings.Type.PIPE or t == Buildings.Type.PUMP:
		_fluid_network_dirty = true
	if Buildings.POWER_NETWORK_TYPES.has(t):
		_power_network_dirty = true
	# Post-make placement hooks: building types that need world context to
	# finish their initial state populate it here. (make() runs before the
	# building is registered, so it can't see the world via has_building_at.)
	if t == Buildings.Type.MINING_DRILL:
		MiningDrill.refresh_covered_deposits(b, self)
	return true

func remove_building_at(pos: Vector2i) -> bool:
	if not occupied.has(pos):
		return false
	var anchor: Vector2i = occupied[pos]
	var b: Building = buildings.get(anchor, null)
	if b == null:
		return false
	for cell in _footprint_cells(b.type, anchor):
		occupied.erase(cell)
	buildings.erase(anchor)
	if b.type == Buildings.Type.PIPE or b.type == Buildings.Type.PUMP:
		_fluid_network_dirty = true
	if Buildings.POWER_NETWORK_TYPES.has(b.type):
		_power_network_dirty = true
	return true

# ---------- fluid network resolver ----------

const _CARDINALS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Mark the fluid network as needing a rebuild on next query.
##
## For code paths that mutate `buildings` without going through
## place_building / remove_building — those two are the ONLY ones that set the
## flag themselves. SaveSystem.load_game is the real one: it clears and
## repopulates `buildings` and `occupied` directly, and until it called this
## (audit finding #1) a mid-session quick-load answered pipe connectivity
## questions about the world it had just replaced.
func mark_fluid_network_dirty() -> void:
	_fluid_network_dirty = true

## Mark the power network as needing a topology rebuild on next query.
##
## Same contract and the same caller as mark_fluid_network_dirty above, and it
## invalidates BOTH power caches at once — _pole_component and _pole_cells are
## rebuilt together by PowerNetwork.rebuild_topology off this one flag. Also
## called belt-and-braces at the end of both rigs' build() (ElectricRig,
## PoleTierRig), which covers their adopt-an-existing-layout path.
func mark_power_network_dirty() -> void:
	_power_network_dirty = true

## Wrapper around PowerNetwork.power_satisfaction_at — convenience for
## consumers in their tick: `var sat = world.power_satisfaction_at(b.anchor)`.
func power_satisfaction_at(pos: Vector2i) -> float:
	return PowerNetwork.power_satisfaction_at(self, pos)

## Returns true iff the given position is adjacent to a pipe whose
## connected component contains at least one pump.
##
## `_fluid_type` is reserved for future per-fluid networks (e.g. oil vs
## water). For Session B all networks carry water; the parameter is unused
## but documents intent at the call site.
func fluid_available_at(pos: Vector2i, _fluid_type: int = Fluids.Type.WATER) -> bool:
	if _fluid_network_dirty:
		_rebuild_fluid_network()
	for dir_vec in _CARDINALS:
		var n: Vector2i = pos + dir_vec
		if not _pipe_component.has(n):
			continue
		var comp_id: int = _pipe_component[n]
		if _component_has_pump.get(comp_id, false):
			return true
	return false

## Multi-tile-aware variant: scans every cell along the building's full
## footprint perimeter for an adjacent pipe in a pump-bearing component.
## A 1×1 building's perimeter is 4 cells (identical to fluid_available_at);
## a 2×2 has 8 perimeter cells, so 4× more chances to satisfy the input.
func fluid_available_for_building(b: Building, _fluid_type: int = Fluids.Type.WATER) -> bool:
	if _fluid_network_dirty:
		_rebuild_fluid_network()
	for cell in Buildings.all_edge_cells(b.type, b.anchor):
		if _pipe_component.has(cell):
			var comp_id: int = _pipe_component[cell]
			if _component_has_pump.get(comp_id, false):
				return true
	return false

## Direct query: is the pipe at `pos` part of a pump-bearing component?
## Used by render code to color pipes by connectivity. Returns false for
## non-pipe positions or pipes in disconnected components.
func is_pipe_in_pump_component(pos: Vector2i) -> bool:
	if _fluid_network_dirty:
		_rebuild_fluid_network()
	if not _pipe_component.has(pos):
		return false
	return _component_has_pump.get(_pipe_component[pos], false)

## Per-edge variant for recipes that pin a fluid input to a specific edge.
## `world_dir` is already-rotated (caller has applied Buildings.world_dir).
## A 2×2 has 2 cells along that edge; a 1×1 has 1.
func fluid_available_for_building_edge(b: Building, world_dir: int, _fluid_type: int = Fluids.Type.WATER) -> bool:
	if _fluid_network_dirty:
		_rebuild_fluid_network()
	for cell in Buildings.edge_cells(b.type, b.anchor, world_dir):
		if _pipe_component.has(cell):
			var comp_id: int = _pipe_component[cell]
			if _component_has_pump.get(comp_id, false):
				return true
	return false

## Rebuild pipe → component map and mark each component with whether it
## contains an adjacent pump. BFS from each unvisited pipe; sort starting
## points to keep component IDs deterministic across runs.
func _rebuild_fluid_network() -> void:
	_pipe_component.clear()
	_component_has_pump.clear()

	var pipe_anchors: Array = []
	for anchor in buildings:
		if buildings[anchor].type == Buildings.Type.PIPE:
			pipe_anchors.append(anchor)
	# Determinism: sort lexicographically.
	pipe_anchors.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))

	var next_id: int = 0
	for start in pipe_anchors:
		if _pipe_component.has(start):
			continue
		var has_pump: bool = false
		var queue: Array = [start]
		while not queue.is_empty():
			var p: Vector2i = queue.pop_front()
			if _pipe_component.has(p):
				continue
			_pipe_component[p] = next_id
			# Walk cardinal neighbors.
			for dir_vec in _CARDINALS:
				var n: Vector2i = p + dir_vec
				if not has_building_at(n):
					continue
				var nb: Building = building_at(n)
				if nb == null:
					continue
				if nb.type == Buildings.Type.PIPE and not _pipe_component.has(n):
					queue.append(n)
				elif nb.type == Buildings.Type.PUMP:
					has_pump = true
		_component_has_pump[next_id] = has_pump
		next_id += 1

	_fluid_network_dirty = false

# ---------- simulation ----------

func _on_tick(_tick_no: int) -> void:
	# Pre-pass: update power network supply/demand/satisfaction. Generators
	# and consumers read/write state during their own tick (output_active /
	# satisfaction); this pre-pass aggregates those into the per-component
	# numbers, so consumers see the CURRENT-tick numbers when their tick
	# runs in the building loop below.
	#
	# Tick-ordering subtlety: generator's output_active is set during its
	# own tick (which fires AFTER this pre-pass). So on the FIRST tick
	# after a generator is placed, supply will be 0 (output_active is still
	# false from initial state). Subsequent ticks see correct supply.
	# Acceptable for v1; refine in Session 2 if it surfaces as UX issue.
	PowerNetwork.update_supply_demand(self)
	# Two-pass tick: pass 1 mutates self only, pass 2 hands items to neighbors.
	# Reading neighbor state in pass 2 is safe because pass 1 has finished
	# everywhere — order-independent for chain belts.
	for anchor in buildings:
		Buildings.tick_one(buildings[anchor], self)
	for anchor in buildings:
		Buildings.post_tick_one(buildings[anchor], self)

## Find any drainable building (harvester, chest) adjacent to or under
## the given tile. Returns the Building or null.
func find_adjacent_drainable(center: Vector2i) -> Building:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p: Vector2i = center + Vector2i(dx, dy)
			if has_building_at(p):
				var b: Building = building_at(p)
				if b != null and Buildings.is_player_drainable(b.type):
					return b
	return null

# ---------- region visibility / vision ----------

## Convert a tile position to its containing region coordinate.
## Region (rx, ry) covers tiles [rx*REGION_SIZE, rx*REGION_SIZE + REGION_SIZE-1]
## in each axis.
static func region_of(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(tile_pos.x) / float(WorldGenerator.REGION_SIZE))),
		int(floor(float(tile_pos.y) / float(WorldGenerator.REGION_SIZE))),
	)

## Convert a player world-space position (Vector2 in pixels) to region coord.
static func region_of_world_pos(world_pos: Vector2) -> Vector2i:
	var tile_x: int = int(floor(world_pos.x / float(TILE_SIZE)))
	var tile_y: int = int(floor(world_pos.y / float(TILE_SIZE)))
	return region_of(Vector2i(tile_x, tile_y))

## Region bounds check (matches WORLD_MIN/MAX in tile-space).
func _in_region_bounds(region: Vector2i) -> bool:
	return region.x >= WorldGenerator.REGION_MIN and region.x < WorldGenerator.REGION_MAX \
		and region.y >= WorldGenerator.REGION_MIN and region.y < WorldGenerator.REGION_MAX

# ---------- soil exhaustion (per-tile, session-soil-exhaustion-2) ----------

## Read tile soil health. Default TILE_SOIL_FULL (100) if not in
## modifications dict — sparse storage means absent = pristine.
func tile_soil_health(pos: Vector2i) -> int:
	return int(tile_soil_modifications.get(pos, TILE_SOIL_FULL))

## Decrement tile soil_health by `amount`, clamped at 0 (this session;
## future sessions allow negative for wasteland). Updates the modifications
## dict; if the new value happens to be TILE_SOIL_FULL again (only possible
## when amount <= 0 — defensive), erases the entry to keep the dict sparse.
##
## Returns the new soil_health value.
func deplete_tile_soil(pos: Vector2i, amount: int) -> int:
	var current: int = tile_soil_health(pos)
	var new_value: int = max(0, current - amount)
	if new_value >= TILE_SOIL_FULL:
		tile_soil_modifications.erase(pos)
	else:
		tile_soil_modifications[pos] = new_value
	return new_value

## Compute the neighbor falloff cost. Center loses center_cost; each of
## the 8 neighbors loses this amount. Formula (per locked design Q5):
##   max(1, ceil(center_cost * 0.6))
##
## Verification: Wheat 5 → 3, Sugar Beet 8 → 5, Flax 3 → 2.
## The max(1, ...) ensures any future tiny-cost crop still touches
## neighbors at least 1.
static func _neighbor_falloff_cost(center_cost: int) -> int:
	return max(1, int(ceil(float(center_cost) * 0.6)))

## Apply soil depletion to the 9-tile area centered at `anchor` (the
## planter's tile + its 8 King-move neighbors). Center tile loses the
## full center_cost; neighbors lose the falloff cost.
##
## Each tile's soil clamped at 0 individually. Tiles that don't need
## visualization (e.g., stone, water) still track soil values internally —
## the rendering layer decides what to show.
##
## Aggregate per-harvest depletion (across all 9 tiles):
##   Wheat (cost 5):     5 + 8×3 = 29
##   Sugar Beet (cost 8): 8 + 8×5 = 48
##   Flax (cost 3):      3 + 8×2 = 19
func deplete_planter_area(anchor: Vector2i, center_cost: int) -> void:
	var neighbor_cost: int = _neighbor_falloff_cost(center_cost)
	deplete_tile_soil(anchor, center_cost)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			deplete_tile_soil(Vector2i(anchor.x + dx, anchor.y + dy), neighbor_cost)

# ---------- fertilizer (per-tile, session-soil-exhaustion-3) ----------

## Apply a fertilizer item to a tile. Caller (main.gd) is responsible for
## the inventory check + consumption — this function only validates the
## stacking rule and writes/refreshes the per-tile boost state.
##
## Stacking rules (locked design Q5, extended Session 4):
##   - tile has no active boost → set new boost.
##   - same tier as active     → refresh timer (full duration).
##   - higher tier than active → upgrade (replace tier + reset timer).
##   - lower tier than active  → REJECT (don't waste lower-tier on richer
##                               boost). Caller toasts "already has higher".
##
## **Wasteland branch (session 4):** when `tier == COMPOST_HIGH` AND the
## tile is scarred (wasteland), the call ALSO de-wastelands: erases the
## scarred flag and snaps soil to WASTELAND_RESTORE_SOIL (30). Then
## proceeds to apply the boost normally. Single function, two effects.
##
## **Grace rescue (test 14i):** applying any tier during the grace
## period interacts with `_tick_soil_regen` cleanly — fertilizer
## doesn't directly clear grace state, but the boost multiplies regen →
## regen tick lifts soil > 0 → grace entry erased on the next regen pass.
## This function itself NEVER adds soil to an unscarred tile; it only
## writes boost state. The soil comes from `_tick_soil_regen`.
##
## That indirection used to make the rescue a no-op under active farming,
## which is where scarring actually happens (audit #7): the active-tiles
## early-out skipped the boost read entirely, so the compost was consumed
## and the tile scarred anyway. `_tick_soil_regen` now carries a soil-0-
## with-boost exception to that early-out, so the rescue reaches the tiles
## it was always advertised for. It buys the player out of scarring only —
## regen stops again at soil 1, and the planter takes it back to 0.
##
## **Late applies are refused (audit #7 follow-up):** the boost needs
## SECONDS_PER_SOIL_POINT / multiplier seconds to deliver that first soil
## point, so applying with less grace left than that still ends in a scar
## with the compost spent. `grace_admits_tier()` gates those out — see it
## for the reasoning and for who else asks it.
##
## Returns true if the boost was applied (caller should consume 1 from
## inventory). Returns false if rejected (caller should toast and NOT
## consume).
func try_apply_fertilizer(pos: Vector2i, tier: int) -> bool:
	if fertilizer_duration(tier) <= 0.0:
		return false   # unknown tier — defensive guard
	# Wasteland branch: a restoring tier on a scarred tile triggers
	# de-wastelanding BEFORE the normal apply path. _restore_wasteland
	# erases the scarred flag and snaps soil to 30; apply path then writes
	# the boost state. Non-restoring tiers on a scarred tile would
	# otherwise fall through to the normal stacking-rule path, which (since
	# scarred tiles never have an active boost — fertilizer state is
	# decoupled) would freshly apply LOW or MID. But that's useless:
	# scarred tiles don't regen, so the boost multiplies zero progress. We
	# REJECT them explicitly so the player isn't silently wasting compost.
	#
	# The tier test itself lives in wasteland_accepts_tier() so callers that
	# need to know the answer BEFORE committing — the Fertilizer Applicator
	# picks a target tile a tick before it applies to it — ask this same
	# predicate instead of keeping a second copy that can drift.
	if is_wasteland_at(pos):
		if not wasteland_accepts_tier(tier):
			return false   # only Premium Compost restores wasteland
		_restore_wasteland(pos)
		# Fall through to apply HIGH boost on the now-restored tile.
	var current = tile_fertilizer_state.get(pos)
	if current != null and tier < int(current["tier"]):
		return false   # lower-tier rejected; caller surfaces toast
	# The stacking rule is settled by here, so this gate only ever refuses an
	# apply that would otherwise have been accepted AND consumed. Ordered this
	# way on purpose: a lower-tier-on-higher apply keeps its own, more precise
	# toast rather than being relabelled a timing problem.
	if not grace_admits_tier(pos, tier):
		return false   # too late for the boost to land; caller surfaces toast
	# No boost (fresh), same tier (refresh) or higher tier (upgrade): one write.
	tile_fertilizer_state[pos] = {"tier": tier, "remaining": fertilizer_duration(tier)}
	return true

## Can `tier`'s boost still lift this tile's soil by one point before the
## tile's wasteland grace runs out? Applying a boost is the ONLY way an
## unscarred soil-0 tile gets out of grace (this function never adds soil
## itself), and the boost takes SECONDS_PER_SOIL_POINT / multiplier seconds
## to deliver that point: 3.75s (HIGH), 7.5s (MID), 15s (LOW). Applied with
## less grace left than that, the compost is spent and the tile scars anyway
## — which is exactly what audit #7's repro measured, and what the
## "will scar in Xs" countdown (info_panel.gd, console.gd) invites.
##
## So we refuse, on the same reasoning as the LOW/MID-on-scar rejection
## above: don't let the player silently waste compost on an application that
## cannot do anything. The player keeps the item; the tile scars either way.
##
## Public for the same reason wasteland_accepts_tier() is: the Fertilizer
## Applicator picks a target a tick before it applies to it, and a soil-0
## tile in grace wins its most-depleted sort every time. A picker that
## nominated tiles this gate then refused would re-nominate the same tile
## every tick and sit BLOCKED — audit #5's shape, bounded by the remaining
## grace instead of permanent. main.gd also asks it, to pick its toast.
##
## Deliberately ignores accumulated tile_regen_progress, which would make the
## threshold tighter but is not serialized (design Q5) — an accept/reject
## decision must not flip across a save/load. Ignoring it can only produce a
## conservative refusal on a tile that then rescues itself from the boost it
## already has, which costs the player nothing.
##
## Returns true when the tile is not in unscarred grace at all: healthy soil
## has no grace entry, and a scarred tile is the _restore_wasteland branch's
## business (that snaps soil to 30 outright and never waits on regen).
##
## Frame pacing: the decision is a pure function of (decay_remaining, tier)
## against a fixed threshold — no hysteresis, no dependence on how many frames
## it took to reach that grace value, so the same tile state always decides the
## same way. One residual, deliberately left: _tick_soil_regen decrements grace
## and checks for the scar BEFORE it runs regen, so a rescue that lands on the
## very tick grace expires loses the tie. The boost delivers its point on the
## first tick at or past the threshold, which is up to one frame delta late, so
## grace in [threshold, threshold rounded up to a tick] is accepted here and
## still scars. That window is narrower than one frame (~16 ms at 60 fps)
## against a 60-second grace — TRUE ONLY ON THE WALL-CLOCK CLOCK, which is
## the deliberate wiring (audit #31, decided 2026-08-26). Measured in that
## design pass: on a fixed 0.05 s tick the window widens to a fixed 50 ms,
## and on a 1 s cadence (the rejected option 4) it becomes 1-2 s per tier
## and re-opens audit #7. If this code ever moves clocks, this claim moves
## with it — do not inherit it as universal.
## The alternative is an arbitrary margin constant
## that no game constant derives, which is worse than a sub-frame edge. Tests
## pin decay_remaining directly rather than accumulating it, so 11a's boundary
## cases assert the return value only — 11b's outcome assertions are the ones
## driven by real ticks, and they sit well clear of the tie.
func grace_admits_tier(pos: Vector2i, tier: int) -> bool:
	var grace: float = tile_wasteland_grace_remaining(pos)
	if grace <= 0.0:
		return true   # not in grace (healthy soil, or scarred → 0.0)
	return grace >= SECONDS_PER_SOIL_POINT / fertilizer_multiplier(tier)

## Read the active fertilizer tier on a tile. Returns -1 if no active boost.
func tile_fertilizer_tier(pos: Vector2i) -> int:
	var s = tile_fertilizer_state.get(pos)
	return int(s["tier"]) if s != null else -1

## Read remaining seconds on a tile's active boost. Returns 0.0 if none.
func tile_fertilizer_remaining(pos: Vector2i) -> float:
	var s = tile_fertilizer_state.get(pos)
	return float(s["remaining"]) if s != null else 0.0

## Per-frame decay of all active fertilizer states. Called from _process
## alongside _tick_soil_regen. Decays in real time INDEPENDENT of soil
## state — fertilizer expires whether or not the tile is currently being
## regenerated. Matches real-world fertilizer behavior (boost diminishes
## with time, not with use).
func _tick_fertilizer_decay(delta: float) -> void:
	if tile_fertilizer_state.is_empty():
		return
	# Snapshot keys() so we can erase mid-iteration.
	var to_remove: Array[Vector2i] = []
	for pos in tile_fertilizer_state.keys():
		var s: Dictionary = tile_fertilizer_state[pos]
		var new_remaining: float = float(s["remaining"]) - delta
		if new_remaining <= 0.0:
			to_remove.append(pos)
		else:
			s["remaining"] = new_remaining
	for pos in to_remove:
		tile_fertilizer_state.erase(pos)

# ---------- wasteland (session-soil-exhaustion-4) ----------

## True if `pos` is fully scarred (post-grace wasteland). Read-only.
func is_wasteland_at(pos: Vector2i) -> bool:
	var s = tile_wasteland_state.get(pos)
	return s != null and bool(s.get("scarred", false))

## True if `tier` is allowed to be applied to a scarred (wasteland) tile.
## Only Premium Compost restores wasteland — everything below it is
## rejected rather than silently wasted (see try_apply_fertilizer).
##
## This is the ONE place that rule is written down. try_apply_fertilizer
## gates on it, and the Fertilizer Applicator's tile picker asks it while
## choosing a target, so the picker can never nominate a tile the apply
## would then refuse. Before this predicate existed the picker had no
## wasteland test at all: a scarred tile sits at soil 0 forever (regen
## skips it), so it always won the most-depleted sort, the LOW/MID apply
## bounced, and the applicator re-picked the identical target every tick
## — permanently BLOCKED with eligible tiles beside it (audit #5).
func wasteland_accepts_tier(tier: int) -> bool:
	return tier == Items.Type.COMPOST_HIGH

## Read grace-period remaining (seconds). Returns 0.0 if not in grace
## (either healthy soil OR already scarred). Used by Q-inspect to show
## the "DEAD — will scar in Xs" countdown.
func tile_wasteland_grace_remaining(pos: Vector2i) -> float:
	var s = tile_wasteland_state.get(pos)
	if s == null or bool(s.get("scarred", false)):
		return 0.0
	return float(s["decay_remaining"])

## Restore a wasteland tile to soil = WASTELAND_RESTORE_SOIL (30) and
## erase the scarred flag. Called from try_apply_fertilizer when a
## Premium Compost (HIGH) is applied to a scarred tile. Caller is
## responsible for applying the boost separately (try_apply_fertilizer
## does the boost write after this restore step).
##
## Returns true if the tile was scarred and is now restored, false if
## tile wasn't scarred (caller should fall through to normal apply).
func _restore_wasteland(pos: Vector2i) -> bool:
	if not is_wasteland_at(pos):
		return false
	tile_wasteland_state.erase(pos)
	# Snap soil to 30 — partial restoration (DAMAGED range). Combined
	# with the HIGH-tier 8× boost, climb to fully-healed takes ~21 min.
	tile_soil_modifications[pos] = WASTELAND_RESTORE_SOIL
	tile_regen_progress.erase(pos)   # fresh start on regen accumulator
	return true

## Per-tile regen multiplier from any active fertilizer boost. Returns 1.0
## (no boost) when no fertilizer state is present. Keep cheap — called
## once per modified tile per frame in _tick_soil_regen.
func _fertilizer_boost_multiplier(pos: Vector2i) -> float:
	var s = tile_fertilizer_state.get(pos)
	if s == null:
		return 1.0
	return fertilizer_multiplier(int(s["tier"]))

## Recompute active-vs-fog for the current player region. Returns the list
## of regions whose visibility CHANGED so the map texture can be marked
## dirty for those regions only (avoids full rebuild).
##
## Algorithm:
##   1. Downgrade currently-active regions that exited the vision radius to fog
##   2. Upgrade in-range regions to active (covers fog→active and unrevealed→active)
##
## Cost: O(active_count + (2R+1)^2) ≈ 50 dict ops total.
func update_vision(player_region: Vector2i) -> Array:
	var changed: Array = []

	# Downgrade out-of-range active regions to fog.
	# Iterate keys (snapshot) since we mutate the dict.
	for region in region_visibility.keys():
		if int(region_visibility[region]) == 2:
			var dist: int = max(abs(region.x - player_region.x), abs(region.y - player_region.y))
			if dist > VISION_RADIUS:
				region_visibility[region] = 1
				changed.append(region)

	# Upgrade in-range regions to active.
	for dx in range(-VISION_RADIUS, VISION_RADIUS + 1):
		for dy in range(-VISION_RADIUS, VISION_RADIUS + 1):
			var r: Vector2i = player_region + Vector2i(dx, dy)
			if not _in_region_bounds(r):
				continue
			var prev: int = int(region_visibility.get(r, 0))
			if prev != 2:
				region_visibility[r] = 2
				changed.append(r)

	return changed

## Initial reveal: mark all regions within INITIAL_REVEAL_RADIUS Chebyshev
## of origin as fog. Called once after fresh world generation, before the
## first vision update. Vision update will then upgrade the 5×5 around
## player position to active.
func initial_reveal() -> void:
	for dx in range(-INITIAL_REVEAL_RADIUS, INITIAL_REVEAL_RADIUS + 1):
		for dy in range(-INITIAL_REVEAL_RADIUS, INITIAL_REVEAL_RADIUS + 1):
			var r: Vector2i = Vector2i(dx, dy)
			if not _in_region_bounds(r):
				continue
			region_visibility[r] = 1   # fog (later upgraded by vision update)

# ---------- resource depletion (manual mining) ----------

# Signal listeners (e.g. main.gd → map_panel) hook in for dirty tracking.
# Emitted whenever a tile's resource state changes — partial depletion or
# full revert. Position is the tile that changed; receiver typically marks
# its enclosing region dirty in the map texture.
signal resource_changed(pos: Vector2i)

## Decrement the richness at `pos` by `amount`. Handles full depletion
## (richness reaches 0 → tile.resource_node = NONE, tile_modifications
## records the revert, resource_state[pos] erased).
##
## No-op if pos has no resource_state entry (defensive against double-deplete).
##
## Returns the amount actually extracted (clamped if richness < amount).
func deplete_resource(pos: Vector2i, amount: int) -> int:
	if not resource_state.has(pos):
		return 0
	var current: int = int(resource_state[pos].get("richness", 0))
	var extracted: int = min(amount, current)
	var new_richness: int = current - extracted
	if new_richness > 0:
		resource_state[pos]["richness"] = new_richness
		# v14 shape: per-tile state dict (richness for ore, regrowth_remaining
		# for tree). Each tile stores ONLY the fields relevant to its type.
		resource_state_modifications[pos] = {"richness": new_richness}
	else:
		# Tile fully depleted — resource_node reverts to NONE, tile becomes
		# default if no overlay. Tile_modifications records the change so
		# save/load preserves the post-depletion state.
		resource_state.erase(pos)
		resource_state_modifications.erase(pos)
		var t: Tile = tiles.get(pos, null)
		if t != null:
			t.resource_node = ResourceNodes.Type.NONE
			# If the tile collapses to pure default (grass / no overlay /
			# no resource), erase from tiles AND record an explicit erase
			# in tile_modifications by storing the default value.
			if t.base == Terrain.Base.GRASS and t.overlay == Terrain.Overlay.NONE:
				tile_modifications[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
				tiles.erase(pos)
			else:
				# Has water or overlay — keep tile entry, just clear resource_node.
				tile_modifications[pos] = Tile.new(t.base, t.overlay, ResourceNodes.Type.NONE)
	emit_signal("resource_changed", pos)
	return extracted

## Read the current richness at a tile (0 if no resource).
func richness_at(pos: Vector2i) -> int:
	return int(resource_state.get(pos, {}).get("richness", 0))

## Read the canonical original (procgen) richness at a tile (0 if no resource).
## Used by visuals for proportional depletion fade.
func original_richness_at(pos: Vector2i) -> int:
	return int(resource_state.get(pos, {}).get("original_richness", 0))

# ---------- tree chopping (manual harvest, single-shot) ----------

# Tree regrowth timer (seconds). Long enough that re-visiting feels rewarding
# (trees came back), short enough that a 30-min play session sees a full
# cycle. Tunable; constant lives here so future drill/lumber-camp sessions
# can reference it.
const TREE_REGROWTH_SECONDS: float = 300.0

## Chop the tree at `pos`. Single-shot: tile.resource_node becomes NONE,
## resource_state[pos] gets a regrowth timer, tile_modifications records
## the chopped state. When the timer expires (via _tick_regrowth in
## _process), tree restores via _restore_tree.
##
## No-op if pos has no tree (defensive).
func chop_tree(pos: Vector2i) -> void:
	if not tiles.has(pos):
		return
	var t: Tile = tiles[pos]
	if t.resource_node != ResourceNodes.Type.TREE:
		return
	# Mark tile as chopped: tree gone, regrowth in progress.
	t.resource_node = ResourceNodes.Type.NONE
	resource_state[pos] = {"regrowth_remaining": TREE_REGROWTH_SECONDS}
	resource_state_modifications[pos] = {"regrowth_remaining": TREE_REGROWTH_SECONDS}
	# Index registration (audit #29): without this line the timer above is
	# invisible to _tick_regrowth and the tree never regrows — silently.
	_active_regrowth[pos] = true
	# tile_modifications records the chopped state. If tile collapses to pure
	# default (grass / no overlay / no resource), erase from tiles dict but
	# KEEP the tile_modifications entry — that entry is what overrides procgen
	# canonical (which says TREE) on save/load.
	if t.base == Terrain.Base.GRASS and t.overlay == Terrain.Overlay.NONE:
		tile_modifications[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.NONE)
		tiles.erase(pos)
	else:
		tile_modifications[pos] = Tile.new(t.base, t.overlay, ResourceNodes.Type.NONE)
	emit_signal("resource_changed", pos)

## Restore a tree at `pos` (regrowth timer expired). Inverse of chop_tree:
## resource_node back to TREE, erase the regrowth state, erase the tile
## modification (now matches procgen canonical = tree present).
##
## No-op if no regrowth timer is active here.
func _restore_tree(pos: Vector2i) -> void:
	if not resource_state.has(pos):
		return
	if not resource_state[pos].has("regrowth_remaining"):
		return
	resource_state.erase(pos)
	resource_state_modifications.erase(pos)
	# Index invalidation (audit #29): lands together with the two erases
	# above — a surviving index entry faults _tick_regrowth next frame.
	_active_regrowth.erase(pos)
	# Restore tile to canonical procgen state (Tile(GRASS, NONE, TREE)).
	# tile_modifications is erased so the tile matches canonical from now on.
	tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, ResourceNodes.Type.TREE)
	tile_modifications.erase(pos)
	emit_signal("resource_changed", pos)

## Read the regrowth time remaining at a tile (0 if no timer active).
## Used by Q-inspect for the "Regrowing: X%" display.
func regrowth_remaining_at(pos: Vector2i) -> float:
	return float(resource_state.get(pos, {}).get("regrowth_remaining", 0.0))

## Wood yield for chopping the tree at `pos`. Deterministic per-position
## hash so the same tree always yields the same amount (and the same
## tree continues to yield the same amount after regrowth — yield is a
## property of the position, not a per-instance value).
##
## Correlates with the visual size_jitter in _draw_tree (uses the same
## byte of the position hash) so visibly-bigger trees yield more wood.
##
## Distribution (skewed toward small trees):
##   ~50%  yield 1 (the most common scrubby tree)
##   ~35%  yield 2
##   ~10%  yield 3
##   ~5%   yield 4 (rare big tree — visibly large in the world)
## Average ≈ 1.7 wood per tree.
static func wood_yield_for_tree(pos: Vector2i) -> int:
	var jitter_h: int = (pos.x * 73856093) ^ (pos.y * 19349663)
	var size_byte: int = jitter_h & 0xFF   # same byte _draw_tree uses for size_jitter
	# Convert to the same -0.125..+0.125 range _draw_tree uses, then to 0..1
	# normalized "size factor" so yield maps to canopy size.
	var size_norm: float = float(size_byte) / 255.0
	if size_norm < 0.50:
		return 1
	elif size_norm < 0.85:
		return 2
	elif size_norm < 0.95:
		return 3
	return 4

# ---------- harvest indicator (visual feedback while player mines or chops a tile) ----------

const HARVEST_INDICATOR_INVALID: Vector2i = Vector2i(2147483647, 2147483647)
var harvest_indicator_pos: Vector2i = HARVEST_INDICATOR_INVALID
var harvest_indicator_progress: float = 0.0   # 0..1, where 1 = next tick imminent

func set_harvest_indicator(pos: Vector2i, progress: float) -> void:
	harvest_indicator_pos = pos
	harvest_indicator_progress = clamp(progress, 0.0, 1.0)

func clear_harvest_indicator() -> void:
	harvest_indicator_pos = HARVEST_INDICATOR_INVALID
	harvest_indicator_progress = 0.0

## Draw the harvest progress arc on the currently-targeted tile.
## Filled clockwise from 12 o'clock as progress approaches 1.0 (next tick).
const HARVEST_ARC_RADIUS_RATIO: float = 0.42   # tile-radius factor
const HARVEST_ARC_WIDTH: float = 3.0
const HARVEST_ARC_COLOR: Color = Color(1.0, 0.92, 0.4, 0.95)
const HARVEST_ARC_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.4)

func _draw_harvest_indicator() -> void:
	var pos: Vector2i = harvest_indicator_pos
	var center: Vector2 = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	var radius: float = TILE_SIZE * HARVEST_ARC_RADIUS_RATIO
	# Background ring (full circle, dim) — gives the arc a "track" to fill.
	draw_arc(center, radius, 0.0, TAU, 32, HARVEST_ARC_BG_COLOR, HARVEST_ARC_WIDTH)
	# Foreground arc — bright yellow, fills based on progress (0..1) clockwise
	# from 12 o'clock. Godot's draw_arc takes radians; -PI/2 = 12 o'clock.
	var start_angle: float = -PI * 0.5
	var end_angle: float = start_angle + TAU * harvest_indicator_progress
	if harvest_indicator_progress > 0.0:
		draw_arc(center, radius, start_angle, end_angle, max(8, int(32.0 * harvest_indicator_progress)), HARVEST_ARC_COLOR, HARVEST_ARC_WIDTH)

# ---------- rendering ----------

func _process(delta: float) -> void:
	_tick_regrowth(delta)
	# Fertilizer decay must run BEFORE soil regen so boost-expired tiles
	# are no longer in tile_fertilizer_state when _tick_soil_regen reads
	# the multiplier. Otherwise a tile fires its last boosted regen tick
	# AFTER its timer hit 0 — small bug, but eliminates a 1-frame edge
	# case where fertilizer "leaks" past expiry by one frame's regen.
	_tick_fertilizer_decay(delta)
	_tick_soil_regen(delta)
	queue_redraw()
	# Additive glow pass (session-art-probe-1). Created lazily and ONLY while
	# the sprite flag is on, so the default configuration has no such node.
	#
	# This is NOT a fourth clock. `delta` is not read here and no timer is
	# advanced — the pulse phase comes from the smelter's tick-counted
	# `progress` (see SpriteLibrary.glow_phase_for). This line requests a
	# redraw, the same thing the `queue_redraw()` above it does, and finding
	# #31 explicitly excludes `queue_redraw` from its scope
	# (docs/scoping/r1-two-clocks.md, correction dated 2026-08-24).
	if SpriteLibrary.enabled:
		if _sprite_glow_layer == null:
			_sprite_glow_layer = SpriteLibrary.make_glow_layer(self)
			add_child(_sprite_glow_layer)
		_sprite_glow_layer.queue_redraw()
	elif _sprite_glow_layer != null:
		_sprite_glow_layer.queue_free()
		_sprite_glow_layer = null

# ---------- per-tile soil regen (session-soil-exhaustion-2) ----------

## Per-frame fallow regen tick. Iterates `tile_soil_modifications` (sparse)
## and regenerates soil in tiles where no active planter's 3×3 area overlaps.
##
## Active-tile detection: one pass over ALL of `buildings` (the planter
## filter walks every building, not just planters) plus O(active planters
## × 9) marking. Measured 2026-08-26 (audit #32): whole function 186 µs at
## 150 buildings / 300 modified tiles, 758 µs at 500 / 1,000, 3.3 ms at
## 2,800 / 4,800 — and the rebuild below is only 23-32% of that; the
## dominant cost is the per-tile second pass, which is inherent per-frame
## work at the wall-clock rate the R1 decision pinned. The prescribed
## caches (planter registry, scarred-tile exclusion) were measured and
## DECLINED — see #32's tracker entry before reaching for one.
##
## Active farming = at least one planter with growth > 0 OR output > 0
## whose 3×3 area covers the tile. Idle planters (growth==0 AND output==0)
## DON'T mark their area active — this enables the single-planter-
## oscillation edge case (idle planter on dead tile → tile regens to 1 →
## planter activates → consumes → tile drops → idle → cycle). PlanterPanel
## mini-grid shows the flicker visually.
##
## **3×3 boundary exactness**: planter at (50,50) marks tiles (49..51,
## 49..51) active. A tile at (53, 50) is OUTSIDE that 3×3 area and
## regenerates independently of the planter's state.
##
## When a tile transitions ACTIVE→REGENERATING (or vice versa), partial
## tile_regen_progress is reset to 0. Conceptual simplicity: "active
## farming = no regen" — with exactly ONE exception, a soil-0 tile carrying
## a fertilizer boost (audit #7; see the active-tiles check below for why
## the countdown must keep running and what the exception costs). Player
## loses up to SECONDS_PER_SOIL_POINT of pending progress on activation.
func _tick_soil_regen(delta: float) -> void:
	if tile_soil_modifications.is_empty():
		return

	# Single pass: mark all tiles in active planters' 3×3 areas.
	var active_tiles: Dictionary = {}
	for anchor in buildings:
		var b: Building = buildings[anchor]
		if b == null or b.type != Buildings.Type.PLANTER:
			continue
		if not Planter.is_active(b):
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				active_tiles[Vector2i(b.anchor.x + dx, b.anchor.y + dy)] = true

	# Second pass: regen non-active depleted tiles + advance wasteland
	# grace timers for soil-0 tiles.
	# Snapshot keys() because we may mutate tile_soil_modifications mid-loop
	# (full-recovery erase). Same iteration pattern as _tick_regrowth.
	var to_restore: Array[Vector2i] = []
	for pos in tile_soil_modifications.keys():
		# Wasteland grace-timer logic (session-soil-exhaustion-4):
		#   - Tile at soil 0 + not yet scarred → advance grace timer.
		#     When timer hits 0, tile becomes scarred (persistent).
		#   - Tile at soil 0 + already scarred → skip ALL regen (no
		#     passive recovery from wasteland; player must apply HIGH).
		#   - Tile soil > 0 + has grace entry → erase entry (rescued).
		var soil_now: int = int(tile_soil_modifications[pos])
		if soil_now == 0:
			var ws = tile_wasteland_state.get(pos)
			if ws == null:
				# First frame at soil 0 — start grace timer (initialized
				# at MAX, then decremented THIS tick so behavior is
				# predictable: 1 tick of dt seconds always = MAX − dt
				# remaining).
				ws = {"scarred": false, "decay_remaining": WASTELAND_GRACE_SEC}
				tile_wasteland_state[pos] = ws
			if not bool(ws.get("scarred", false)):
				# Advance timer (also fires on the just-created entry —
				# init-and-decrement, same tick).
				ws["decay_remaining"] = float(ws["decay_remaining"]) - delta
				if ws["decay_remaining"] <= 0.0:
					ws["scarred"] = true
					ws["decay_remaining"] = 0.0
					tile_regen_progress.erase(pos)   # scarred = no carry-over
		else:
			# Soil rose above 0 — clear any grace entry that hasn't scarred.
			# (Scarred tiles can't reach this branch: their soil stays at
			# 0 because regen is blocked below.)
			var ws_existing = tile_wasteland_state.get(pos)
			if ws_existing != null and not bool(ws_existing.get("scarred", false)):
				tile_wasteland_state.erase(pos)

		# Wasteland-scarred tiles skip regen entirely. Even with active
		# fertilizer boost, scarred soil doesn't recover — only Premium
		# Compost via try_apply_fertilizer can restore them.
		if is_wasteland_at(pos):
			continue

		# Active farming this frame — clear partial regen so a brief active
		# period doesn't leave stale progress accumulated.
		#
		# ONE exception (audit #7): a tile at soil 0 carrying a fertilizer
		# boost regenerates even while actively farmed. Without it the grace
		# timer above counts a soil-0 tile down to scarring while its soil can
		# never rise, so the rescue try_apply_fertilizer advertises is a
		# silent no-op exactly where scarring actually happens — the player
		# spends Premium Compost, main.gd consumes it, and the tile scars
		# anyway. (try_apply_fertilizer writes boost state only; it never adds
		# soil to an unscarred tile, so the boost is the sole route back.)
		#
		# Scoped deliberately to soil == 0 AND a live boost. A boosted tile
		# above soil 0 still gets nothing: "active farming = no regen" holds
		# everywhere the rescue promise does not reach. _fertilizer_boost_
		# multiplier returns exactly 1.0 with no boost, so `> 1.0` is the
		# has-a-boost test; `and` short-circuits, so the lookup only happens
		# for active tiles already at 0. Scarred tiles continue above, so the
		# exception can never apply to one.
		#
		# Downstream, and intended: the moment soil reaches 1 the tile is no
		# longer soil-0, the exception lapses, regen stops there, and the
		# planter's next harvest takes it back to 0. Fertilizer buys the
		# player out of SCARRING, not out of depletion.
		#
		# The audit's own prescribed fix — pausing the grace countdown while
		# a tile is actively farmed — was rejected: PROJECT_LOG.md:775 records
		# active planters pinning soil at 0 as THE organic scarring path, and
		# pausing grace on active tiles pins a continuously-active planter's
		# neighbours at grace = 60.00 forever, killing the one scarring route
		# the player can find and understand. test_wasteland.gd sub-suite 10b
		# is the regression guard for that.
		#
		# Note what the rejection does NOT rest on: "an inactive soil-0 tile
		# always self-rescues" is false as stated, and b92a769's commit message
		# carries that false premise (see the tracker entry for #7, which is the
		# correcting record — the commit is on a shared index and cannot be
		# amended). Self-rescue is only guaranteed for a tile inactive across
		# the WHOLE grace window from soil-0 onset: SECONDS_PER_SOIL_POINT (30)
		# beats WASTELAND_GRACE_SEC (60) only from a full 60. Measured
		# counter-example — burn a soil-0 tile's grace to 15.0s under an active
		# planter, then let the planter go idle; tile_regen_progress was erased
		# on the last active frame, so the tile needs 30s for +1 soil and has
		# 15s, and it scars while fully inactive. An oscillating planter can
		# therefore still scar a tile even with grace paused. The conclusion
		# holds anyway on the documented-path argument above.
		if active_tiles.has(pos) and not (soil_now == 0 and _fertilizer_boost_multiplier(pos) > 1.0):
			tile_regen_progress.erase(pos)
			continue

		# Accumulate progress, scaled by any active fertilizer boost.
		# Multiplier is 1.0 (no boost), 2.0 (LOW), 4.0 (MID), or 8.0
		# (HIGH) per fertilizer_multiplier(). Cheap dict lookup per
		# modified tile; no boost = early-return 1.0.
		var boost: float = _fertilizer_boost_multiplier(pos)
		var prog: float = float(tile_regen_progress.get(pos, 0.0)) + (delta * boost) / SECONDS_PER_SOIL_POINT
		var increment: int = int(prog)
		if increment > 0:
			var current: int = int(tile_soil_modifications[pos])
			var new_val: int = current + increment
			tile_regen_progress[pos] = prog - float(increment)
			if new_val >= TILE_SOIL_FULL:
				to_restore.append(pos)
			else:
				tile_soil_modifications[pos] = new_val
				# Same-tick grace rescue (session-soil-exhaustion-4): if
				# this tick lifted soil from 0 to >0 AND we're still in
				# grace, erase the grace entry. Without this, grace state
				# would persist to the next tick (where soil_now reads as
				# >0 and the else branch above clears it). Same-tick
				# erasure makes "rescue during grace" feel responsive.
				if new_val > 0:
					var ws_post = tile_wasteland_state.get(pos)
					if ws_post != null and not bool(ws_post.get("scarred", false)):
						tile_wasteland_state.erase(pos)
		else:
			tile_regen_progress[pos] = prog

	# Pristine restoration: erase from both dicts (sparse return to default 100).
	for pos in to_restore:
		tile_soil_modifications.erase(pos)
		tile_regen_progress.erase(pos)

## Derived tile soil level (session-soil-exhaustion-2). Pure function of
## soil_health value. Used by visual rendering (tint selection) and
## Q-inspect / PlanterPanel labels.
func tile_soil_level(pos: Vector2i) -> int:
	var soil: int = tile_soil_health(pos)
	if soil >= TILE_SOIL_FULL:
		return SoilLevel.PRISTINE
	if soil >= 70:
		return SoilLevel.HEALTHY
	if soil >= 30:
		return SoilLevel.DAMAGED
	if soil >= 1:
		return SoilLevel.DYING
	return SoilLevel.DEAD

## Derived tile soil activity (session-soil-exhaustion-2). Orthogonal to
## tile_soil_level; tracks whether a planter is currently affecting this
## tile vs whether the tile is passively regenerating.
##
## NONE: pristine (not in modifications) — no activity-relevant state.
## ACTIVE_FARMING: an active planter's 3×3 area covers this tile.
## REGENERATING: tile in modifications, soil < 100, no active planter
##                affects this tile — regen ticks running.
func tile_soil_activity(pos: Vector2i) -> int:
	if not tile_soil_modifications.has(pos):
		return SoilActivity.NONE
	if _is_tile_actively_farmed(pos):
		return SoilActivity.ACTIVE_FARMING
	return SoilActivity.REGENERATING

## True if any planter's 3×3 area covers `pos` AND that planter is active.
## Read-side O(planters) scan called from tile_soil_activity (Q-inspect,
## panel render). Hot-path is _tick_soil_regen which avoids this by doing
## one pass over planters and one pass over modified tiles.
func _is_tile_actively_farmed(pos: Vector2i) -> bool:
	for anchor in buildings:
		var b: Building = buildings[anchor]
		if b == null or b.type != Buildings.Type.PLANTER:
			continue
		if not Planter.is_active(b):
			continue
		# 3×3 boundary check — Chebyshev distance ≤ 1.
		if abs(pos.x - b.anchor.x) <= 1 and abs(pos.y - b.anchor.y) <= 1:
			return true
	return false

# ---------- soil visual tints (session-soil-exhaustion-2) ----------

# Alpha-blended overlay tints per SoilLevel. PRISTINE + HEALTHY render
# nothing (zero alpha); only DAMAGED/DYING/DEAD tints visibly modify the
# tile color. Restriction below: only tilled or plain-grass tiles get
# tinted; stone/path/water are "infrastructure" and look unchanged.
const SOIL_TINT_DAMAGED: Color = Color(0.95, 0.85, 0.55, 0.40)   # yellow-brown
const SOIL_TINT_DYING: Color   = Color(0.75, 0.55, 0.35, 0.55)   # brown
const SOIL_TINT_DEAD: Color    = Color(0.50, 0.32, 0.20, 0.85)   # dark cracked-earth
# Fertilizer tints (session-soil-exhaustion-3) — overlaid ON TOP of soil
# tints. A damaged-but-fertilized tile shows red-ish + green-ish blend.
# Cooler-and-saturated for higher tier so the tier is visible at a glance.
const FERT_TINT_LOW: Color     = Color(0.40, 0.70, 0.30, 0.20)   # light green, faint
const FERT_TINT_MID: Color     = Color(0.20, 0.55, 0.20, 0.30)   # saturated green
const FERT_TINT_HIGH: Color    = Color(0.10, 0.45, 0.18, 0.40)   # deep saturated green
# Wasteland (session-soil-exhaustion-4): distinct from DEAD. DEAD is
# "soil at 0, recoverable"; wasteland is "scarred, only HIGH compost
# restores." Near-black brown undertone + faint X-shaped crack lines.
const WASTELAND_TINT: Color    = Color(0.18, 0.13, 0.10, 0.95)
const WASTELAND_CRACK: Color   = Color(0.05, 0.03, 0.02, 1.00)

## Compute the soil tint for a tile at `pos`. Returns a transparent color
## (alpha 0) when no tint should render — the caller skips the draw.
##
## Tint applies only to tiles where soil affects gameplay:
##   - Plain grass (unmapped tile, OR tile in dict with base=GRASS,
##     overlay=NONE): tint shows (extends "dead zone" visually).
##   - SOIL_TILLED tiles (player has tilled): tint shows.
##   - Stone/Path/Water: NO tint (these are infrastructure / water).
##
## Note: an unmapped tile (not in `tiles` dict) is implicitly
## base=GRASS, overlay=NONE — the default. Most regen-tracked tiles
## without a building are in this state.
func _soil_tint_for_tile(pos: Vector2i) -> Color:
	# First, check if this tile's overlay/base allows soil tinting.
	var base: int = Terrain.Base.GRASS
	var overlay: int = Terrain.Overlay.NONE
	if tiles.has(pos):
		var t: Tile = tiles[pos]
		base = t.base
		overlay = t.overlay
	# Filter: water is impassable infrastructure; stone/path are paved.
	if base == Terrain.Base.WATER:
		return Color(0, 0, 0, 0)
	if overlay == Terrain.Overlay.STONE or overlay == Terrain.Overlay.PATH:
		return Color(0, 0, 0, 0)
	# Lookup tint by SoilLevel.
	match tile_soil_level(pos):
		SoilLevel.DAMAGED:
			return SOIL_TINT_DAMAGED
		SoilLevel.DYING:
			return SOIL_TINT_DYING
		SoilLevel.DEAD:
			return SOIL_TINT_DEAD
		_:
			return Color(0, 0, 0, 0)   # PRISTINE / HEALTHY: no tint

## Per-frame regrowth tick. Iterates the _active_regrowth index (chopped
## trees only), decrements each timer, and restores trees when a timer
## hits zero.
##
## Cost: O(active timers) — true again since 2026-08-26 (audit #29).
## This docstring used to make that claim while the loop walked ALL of
## resource_state, which worldgen seeds with every ore tile: measured
## ~1.0 ms/frame over 8,428 entries with ZERO chopped trees (the
## `resource_state.is_empty()` early-out could never fire). The index
## makes it real: ~0 idle, ~0.45 µs per active timer.
func _tick_regrowth(delta: float) -> void:
	if _active_regrowth.is_empty():
		return
	var to_restore: Array[Vector2i] = []
	# Iterate keys snapshot — _restore_tree (below) erases from
	# _active_regrowth. Snapshot avoids modify-during-iter pathology.
	var keys: Array = _active_regrowth.keys()
	for pos in keys:
		# NO existence guard, deliberately: the index invariant says this
		# entry exists and has the key. A stale index faults loudly here
		# every frame — do not "fix" that with resource_state.get(); a
		# tolerant read would hide a missed invalidation edge (see the
		# _active_regrowth declaration and test_regrowth_index.gd).
		var state: Dictionary = resource_state[pos]
		var remaining: float = float(state["regrowth_remaining"]) - delta
		if remaining <= 0.0:
			to_restore.append(pos)
		else:
			state["regrowth_remaining"] = remaining
			# Mirror to modifications so save captures current timer value.
			# Mutate the existing mirror entry in place (chop_tree and the
			# load path both seed it); allocating a fresh Dictionary here
			# cost a measured 0.19 µs per timer per frame.
			var mirror = resource_state_modifications.get(pos)
			if mirror != null:
				mirror["regrowth_remaining"] = remaining
			else:
				resource_state_modifications[pos] = {"regrowth_remaining": remaining}
	for pos in to_restore:
		_restore_tree(pos)

## Convert "I want at least N pixels on screen" to "this many world units,
## given the current camera zoom." Returns max(world_px, world_px / zoom):
##   - At zoom >= 1: returns world_px (the value is the floor).
##   - At zoom <  1: returns world_px / zoom, which renders as exactly
##     world_px screen pixels — keeps a line/outline visible when zoomed out.
##
## Used selectively: hover rect outline (where vanishing-at-low-zoom is
## the worse failure mode than 0.15-screen-px overshoot at min zoom).
## NOT used for grid lines, building borders, port dots — those stay in
## world units to match tile boundaries exactly. The trade-off is per-call.
func screen_px(world_px: float) -> float:
	if camera == null:
		return world_px
	return max(world_px, world_px / camera.zoom.x)

## Draw a resource deposit or tree at the given tile rect.
##   - Ore (stone, coal, iron, copper, clay): inset filled rectangle with
##     resource color + 1-px darker outline. Inset shows underlying grass on
##     all sides so deposits read as "things sitting on the ground" rather
##     than "the whole tile is colored."
##   - Tree: dark-brown trunk rectangle + dark-green canopy circle. Trunk
##     centered, canopy slightly offset upward (visual reading: tree base at
##     center, foliage above). Per-tree color jitter (deterministic from
##     position) gives a forest organic variation.
func _draw_resource(resource_type: int, tile_rect: Rect2, tile_pos: Vector2i) -> void:
	if resource_type == ResourceNodes.Type.TREE:
		_draw_tree(tile_rect)
		return
	# Ore deposit: inset filled rect with proportional alpha-fade based on
	# (current richness / original richness). At full richness: full alpha.
	# Drained to 0 (immediately before erase): fades to MIN_DEPOSIT_ALPHA.
	# Player can read at-a-glance how much is left without Q-inspecting.
	var alpha: float = _depletion_alpha_at(tile_pos)
	var inset: float = TILE_SIZE * 0.10
	var inner: Rect2 = Rect2(tile_rect.position + Vector2(inset, inset), tile_rect.size - Vector2(inset * 2, inset * 2))
	var base: Color = ResourceNodes.color_of(resource_type)
	var color: Color = Color(base.r, base.g, base.b, alpha)
	draw_rect(inner, color, true)
	# Subtle darker outline for definition. Outline alpha matches fill alpha.
	var outline: Color = Color(base.r * 0.6, base.g * 0.6, base.b * 0.6, alpha)
	draw_rect(inner, outline, false, 1.0)

const MIN_DEPOSIT_ALPHA: float = 0.35
const FULL_DEPOSIT_ALPHA: float = 1.0

## Compute proportional alpha for a deposit tile based on
## current_richness / original_richness. Defensive: returns full alpha if
## original is missing (e.g., loaded from older save without the field).
func _depletion_alpha_at(pos: Vector2i) -> float:
	if not resource_state.has(pos):
		return FULL_DEPOSIT_ALPHA
	var current: int = int(resource_state[pos].get("richness", 0))
	var original: int = int(resource_state[pos].get("original_richness", 0))
	if original <= 0:
		return FULL_DEPOSIT_ALPHA
	var ratio: float = float(current) / float(original)
	return lerp(MIN_DEPOSIT_ALPHA, FULL_DEPOSIT_ALPHA, clamp(ratio, 0.0, 1.0))

## Tree rendering: trunk + canopy. Position-derived jitter keeps each tree
## slightly distinct without a per-tree resource_state entry.
func _draw_tree(tile_rect: Rect2) -> void:
	var center: Vector2 = tile_rect.position + tile_rect.size * 0.5
	# Position hash for deterministic jitter (size + color + offset).
	var tx: int = int(tile_rect.position.x / TILE_SIZE)
	var ty: int = int(tile_rect.position.y / TILE_SIZE)
	var jitter_h: int = (tx * 73856093) ^ (ty * 19349663)
	var size_jitter: float = float((jitter_h & 0xFF) - 128) / 1024.0   # ±0.125
	var color_jitter: float = float(((jitter_h >> 8) & 0xFF) - 128) / 1280.0   # ±0.10
	# Trunk: small dark-brown rectangle at center.
	var trunk_w: float = TILE_SIZE * 0.12
	var trunk_h: float = TILE_SIZE * 0.20
	var trunk_rect: Rect2 = Rect2(center.x - trunk_w * 0.5, center.y, trunk_w, trunk_h)
	draw_rect(trunk_rect, Color(0.30, 0.20, 0.10), true)
	# Canopy: dark-green circle, offset upward so the tree "sits" on the trunk base.
	var canopy_r: float = TILE_SIZE * (0.32 + size_jitter)
	var canopy_center: Vector2 = Vector2(center.x, center.y - TILE_SIZE * 0.05)
	var base_canopy: Color = ResourceNodes.color_of(ResourceNodes.Type.TREE)
	var canopy: Color = Color(
		clamp(base_canopy.r + color_jitter, 0.0, 1.0),
		clamp(base_canopy.g + color_jitter * 0.5, 0.0, 1.0),
		clamp(base_canopy.b + color_jitter, 0.0, 1.0),
		1.0,
	)
	draw_circle(canopy_center, canopy_r, canopy)
	# Subtle darker rim.
	var rim: Color = Color(canopy.r * 0.7, canopy.g * 0.7, canopy.b * 0.7, 1.0)
	draw_arc(canopy_center, canopy_r, 0.0, TAU, 24, rim, 1.0)

func _draw() -> void:
	var view_min: Vector2
	var view_max: Vector2
	if camera:
		var half = get_viewport_rect().size * 0.5 / camera.zoom
		view_min = camera.global_position - half
		view_max = camera.global_position + half
	else:
		view_min = Vector2.ZERO
		view_max = get_viewport_rect().size

	var min_tile: Vector2i = world_to_tile(view_min) - Vector2i(VIEW_PADDING_TILES, VIEW_PADDING_TILES)
	var max_tile: Vector2i = world_to_tile(view_max) + Vector2i(VIEW_PADDING_TILES, VIEW_PADDING_TILES)

	# Terrain + resources, one pass over the VISIBLE RECT with tiles.get()
	# lookups — NOT over the tiles dict with per-entry culling (audit #30).
	# Measured 2026-08-26 (windowed off-screen run, --fixed-fps 60, seed 42,
	# debug build): the dict walk cost 980-1,506 µs/frame — 15,641 entries at
	# ~0.063 µs each, of which only 21-429 were visible — ~6% of a 60 fps
	# frame budget from game start. The rect walk costs ~90 µs at default
	# zoom (49×31 cells incl. padding) and ~277 µs at the 0.85 zoom floor
	# (79×49), and is O(view) however large the world or the factory grows.
	# The two enumerations draw the same set (a tile is drawn iff it is in
	# `tiles` AND inside the rect), and the reordering cannot show on screen:
	# every terrain draw — base rect, overlay rect, ore inset, tree canopy at
	# max 0.495·TILE from center (_draw_tree) — stays inside its own tile
	# rect, so no two tiles' draws overlap. Verified by six-frame md5
	# comparison, ticks paused, dict walk vs this loop: byte-identical PNGs.
	# The rect is bounded by the zoom floor; the dict is seeded with ~15k
	# entries by WorldGenerator, so visible ≪ total at every reachable zoom
	# and the inversion wins ~4-11× today, more as the world grows.
	# Layer order per tile: base → overlay → resource_node (if no overlay).
	# Resource hidden under player overlay paint; revealed on RMB-clear via
	# set_overlay/clear_tile preserving resource_node through modifications.
	for draw_y in range(min_tile.y, max_tile.y + 1):
		for draw_x in range(min_tile.x, max_tile.x + 1):
			var tp: Vector2i = Vector2i(draw_x, draw_y)
			var t: Tile = tiles.get(tp)
			if t == null:
				continue
			var rect: Rect2 = Rect2(tp.x * TILE_SIZE, tp.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			# Base layer: only draw if non-default (default grass is the canvas background).
			if t.base != Terrain.DEFAULT_BASE:
				draw_rect(rect, Terrain.base_color(t.base), true)
			# Overlay layer: draw if present.
			if t.overlay != Terrain.Overlay.NONE:
				draw_rect(rect, Terrain.overlay_color(t.overlay), true)
			# Resource layer: draw deposit/tree.
			# Under the "no overlay on deposits" invariant, t.overlay is always
			# NONE when t.resource_node != NONE — but the defensive check stays
			# (cheap; future-proof if rule changes).
			# (Water tiles never have resource_node; defensive base check too.)
			if t.overlay == Terrain.Overlay.NONE and t.resource_node != ResourceNodes.Type.NONE and t.base != Terrain.Base.WATER:
				_draw_resource(t.resource_node, rect, tp)

	# Soil tint pass (session-soil-exhaustion-2). Iterate sparse
	# tile_soil_modifications and overlay a tint per tile based on its
	# SoilLevel. Restricted to tiles where soil mechanic is gameplay-
	# relevant: SOIL_TILLED (planted) and plain unmodified grass.
	# Stone/Path/Water tiles ignore the tint (their overlays/bases are
	# "infrastructure" or "water" — not soil-relevant). Pristine + Healthy
	# levels render no tint (visually identical to default).
	for pos in tile_soil_modifications.keys():
		if pos.x < min_tile.x or pos.x > max_tile.x:
			continue
		if pos.y < min_tile.y or pos.y > max_tile.y:
			continue
		var tint: Color = _soil_tint_for_tile(pos)
		if tint.a > 0.0:
			draw_rect(Rect2(pos.x * TILE_SIZE, pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), tint, true)

	# Fertilizer tint pass (session-soil-exhaustion-3, extended Session 4).
	# Overlaid on top of the soil tint so a damaged-but-fertilized tile
	# shows blended red+green. Iterates the sparse fertilizer dict.
	for pos in tile_fertilizer_state.keys():
		if pos.x < min_tile.x or pos.x > max_tile.x:
			continue
		if pos.y < min_tile.y or pos.y > max_tile.y:
			continue
		var ft: int = int(tile_fertilizer_state[pos]["tier"])
		var ftint: Color = FERT_TINT_LOW
		if ft == Items.Type.COMPOST_MID:
			ftint = FERT_TINT_MID
		elif ft == Items.Type.COMPOST_HIGH:
			ftint = FERT_TINT_HIGH
		draw_rect(Rect2(pos.x * TILE_SIZE, pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), ftint, true)

	# Wasteland tint + crack pattern pass (session-soil-exhaustion-4).
	# Drawn ABOVE soil + fertilizer tints — wasteland is the dominant
	# visual state. Crack pattern: 2 short diagonal lines forming a
	# faint X near tile center, suggesting "broken earth."
	for pos in tile_wasteland_state.keys():
		if pos.x < min_tile.x or pos.x > max_tile.x:
			continue
		if pos.y < min_tile.y or pos.y > max_tile.y:
			continue
		if not bool(tile_wasteland_state[pos].get("scarred", false)):
			continue   # in-grace tile — keep the existing DEAD tint, no wasteland visual yet
		var rect: Rect2 = Rect2(pos.x * TILE_SIZE, pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		draw_rect(rect, WASTELAND_TINT, true)
		# X-shaped cracks: 2 diagonal lines from the tile corners, inset
		# by 6 px so the cracks live within the tile interior.
		var inset: float = 6.0
		var p_tl: Vector2 = rect.position + Vector2(inset, inset)
		var p_tr: Vector2 = rect.position + Vector2(rect.size.x - inset, inset)
		var p_bl: Vector2 = rect.position + Vector2(inset, rect.size.y - inset)
		var p_br: Vector2 = rect.position + Vector2(rect.size.x - inset, rect.size.y - inset)
		draw_line(p_tl, p_br, WASTELAND_CRACK, 1.5)
		draw_line(p_tr, p_bl, WASTELAND_CRACK, 1.5)

	# Grid lines — width in world units so the line scales with the tile.
	# At low zoom this fades the line slightly (sub-pixel anti-aliased),
	# but keeps the line visually flush with tile boundaries instead of
	# overshooting them at low zoom (the trade-off the "overlay matches
	# tile" verification criterion picks).
	for x in range(min_tile.x, max_tile.x + 1):
		var x_pos: float = x * TILE_SIZE
		draw_line(Vector2(x_pos, min_tile.y * TILE_SIZE), Vector2(x_pos, max_tile.y * TILE_SIZE), GRID_COLOR, 1.0)
	for y in range(min_tile.y, max_tile.y + 1):
		var y_pos: float = y * TILE_SIZE
		draw_line(Vector2(min_tile.x * TILE_SIZE, y_pos), Vector2(max_tile.x * TILE_SIZE, y_pos), GRID_COLOR, 1.0)

	# Buildings.
	for anchor_key in buildings:
		var anchor: Vector2i = anchor_key
		var b: Building = buildings[anchor]
		var fp: Vector2i = Buildings.footprint_of(b.type)
		# Cull: skip if entire footprint is offscreen.
		if anchor.x + fp.x - 1 < min_tile.x or anchor.x > max_tile.x:
			continue
		if anchor.y + fp.y - 1 < min_tile.y or anchor.y > max_tile.y:
			continue
		# Sprite path (session-art-probe-1) — OFF by default. With
		# SpriteLibrary.enabled false the added per-building work is exactly:
		# one local bool init, two reads of a static bool, and three branches.
		# No draw call changes, and Buildings.draw_one() below is reached
		# unchanged for every building including the three that have art —
		# measured, not assumed: six flag-off frames, three at 42f6758 and
		# three with this code in place, are byte-identical PNGs (md5
		# 4a2f646cf8fe8f65cb987697f5e38fd7, 0 of 921600 pixels differing).
		# Buildings.draw_one() itself is untouched.
		var drew_sprite: bool = false
		if SpriteLibrary.enabled:
			drew_sprite = SpriteLibrary.draw_building(b, self, tile_to_world_origin(anchor), TILE_SIZE)
		if not drew_sprite:
			Buildings.draw_one(b, self, tile_to_world_origin(anchor), TILE_SIZE)
			# A building that HAS art but fell back still renders, and a
			# rendering fallback is therefore invisible — the silent-
			# compensation shape NOTES.md warns about. Mark it in the frame.
			if SpriteLibrary.enabled:
				SpriteLibrary.draw_fallback_marker(b, self, tile_to_world_origin(anchor), TILE_SIZE)

	# Power wire pass — between buildings and post-pass indicators so wires
	# render on the building layer but below hover/harvest UI.
	_draw_power_wires()

	# Harvest progress arc — yellow arc on the targeted tile, fills 0 → TAU
	# clockwise as the next tick approaches. Visual feedback for "this tile
	# is being harvested" (mined for ore, chopped for tree).
	if harvest_indicator_pos != HARVEST_INDICATOR_INVALID:
		_draw_harvest_indicator()

	# Hover indicator.
	if show_hover:
		# Three cases for the hover rect:
		# 1. Holding a building (hover_building_type >= 0): show that building's
		#    footprint at hover_tile (placement preview).
		# 2. Hover_building_type < 0 AND tile has an existing building: show the
		#    existing building's full footprint, anchored at its actual anchor.
		#    Lets the player see the whole 2×2 smelter when hovering any of its
		#    cells in NEUTRAL mode.
		# 3. Neither: 1×1 hover at hover_tile.
		var fp_size: Vector2i = Vector2i(1, 1)
		var rect_anchor: Vector2i = hover_tile
		if hover_building_type >= 0:
			fp_size = Buildings.footprint_of(hover_building_type)
		elif occupied.has(hover_tile):
			rect_anchor = occupied[hover_tile]
			var existing: Building = buildings.get(rect_anchor, null)
			if existing != null:
				fp_size = Buildings.footprint_of(existing.type)
		var hover_rect: Rect2 = Rect2(rect_anchor.x * TILE_SIZE, rect_anchor.y * TILE_SIZE, TILE_SIZE * fp_size.x, TILE_SIZE * fp_size.y)
		# Red if this placement would be refused. The rule lives in
		# hover_preview_blocked() and NOT here, because nothing headless can
		# reach a _draw body — see that method's header.
		var blocked: bool = hover_preview_blocked(hover_building_type, rect_anchor)
		var hover_color: Color = Color(1.0, 0.4, 0.4, 0.6) if blocked else Color(1.0, 1.0, 1.0, 0.5)
		# Hover outline width: 2 world units AT zoom >= 1 (so it scales
		# with the tile and stays exactly aligned with tile boundaries),
		# floored at 2 screen pixels at lower zoom (so it stays visible
		# when zoomed out and doesn't fade to sub-pixel anti-aliased
		# lines). screen_px(2.0) returns max(2.0, 2.0 / camera.zoom.x):
		#   zoom = 1.5 (default): 2.0 world units → 3.0 screen px (clear).
		#   zoom = 6.75 (max):    2.0 world units → 13.5 screen px (chunky, proportional).
		#   zoom = 0.85 (min):    2.353 world units → 2.0 screen px (floored).
		# At low zoom the outline overshoots the tile by ~0.18 world units
		# on each side (~0.15 screen pixels) — much smaller than the
		# pre-camera-zoom-session overshoot bug, and the visibility win
		# outweighs it (per NOTES.md "minimum-pixel-floor" deferred fix).
		draw_rect(hover_rect, hover_color, false, screen_px(2.0))
		# Direction preview arrow for directional placements (belts and every
		# rotatable processor). Centered on the footprint, not the anchor
		# cell — for a 2×2 building this puts the arrow at the visual middle.
		if hover_arrow_dir >= 0 and hover_arrow_dir < Belt.DIR_VECS.size():
			var center: Vector2 = Vector2(rect_anchor.x * TILE_SIZE + TILE_SIZE * 0.5 * fp_size.x, rect_anchor.y * TILE_SIZE + TILE_SIZE * 0.5 * fp_size.y)
			var dir_vec: Vector2 = Vector2(Belt.DIR_VECS[hover_arrow_dir])
			var perp: Vector2 = Vector2(-dir_vec.y, dir_vec.x)
			var tip: Vector2 = center + dir_vec * (TILE_SIZE * 0.32)
			var base_l: Vector2 = center + perp * (TILE_SIZE * 0.16) - dir_vec * (TILE_SIZE * 0.05)
			var base_r: Vector2 = center - perp * (TILE_SIZE * 0.16) - dir_vec * (TILE_SIZE * 0.05)
			var arrow_color: Color = Color(1.0, 0.92, 0.4, 0.95)
			draw_line(base_l, tip, arrow_color, 2.5)
			draw_line(base_r, tip, arrow_color, 2.5)
			draw_line(center - dir_vec * (TILE_SIZE * 0.30), center + dir_vec * (TILE_SIZE * 0.20), arrow_color, 2.0)


# ---------- power network rendering ----------

# How far down its tile a 1x1 pole's wires attach, as a fraction of TILE_SIZE.
# Matches power_pole.gd's crossarm offset exactly. See _pole_wire_anchor.
const MAST_WIRE_Y: float = 0.16

## Draw wires between poles: the GABRIEL GRAPH of each component, restricted to
## reachable pairs. A wire is drawn between two in-range poles unless a third
## pole they can BOTH reach sits inside the circle on that wire as diameter.
##
## Two shapes have been tried here and rejected. The MESH (every in-range pair)
## read as a hairball once ranges widened. The MINIMUM SPANNING TREE that
## replaced it at Session 3 Task 7 failed the visual gate for the second time —
## it routes through intermediates, so the dense four-pole square came out as a
## 3-wire star with the far corner reaching across the DIAGONAL. Gabriel draws
## that square as a square: four wires, no diagonals. NOTES.md's "Wire
## rendering" section carries the full history; read it before changing this.
##
## THIS FUNCTION OWNS NO PART OF THE RULE. Which poles are wired, which
## component they belong to and which of the in-range pairs survive the Gabriel
## filter are all decided by PowerNetwork.wire_edges — which asks
## PowerNetwork.poles_connected, the same predicate rebuild_topology's BFS
## walks. Grepping this module for a range identifier must still come back
## empty: with per-tier ranges a second derivation would drift, and the
## dangerous direction is silent — a renderer stricter than the BFS draws no
## wire between two poles that ARE on one network, and nothing reports it.
##
## All that is left here is presentation: where a wire terminates
## (_pole_wire_anchor) and what colour it is. Color reflects component
## satisfaction: golden if any power, dark brown if dead. The component is
## read off either endpoint — wire_edges never emits an edge whose ends are in
## different components, which test_pole_tiers sub-case (11) asserts directly.
##
## Called from _draw between building draws and post-pass indicators, so
## wire_edges runs ONCE PER FRAME. Its cost is O(N²) per component — an
## adjacency build over every pair — and is timed by test_pole_tiers sub-case
## (12) on every suite run. The quadratic pair scan is INHERITED, not
## introduced by any one formulation: mesh, MST and Gabriel all have to ask
## poles_connected about all N(N-1)/2 pairs. The fix, when it is wanted, is to
## cache the edge list and invalidate on _power_network_dirty, since topology
## only changes on placement. Read sub-case (12)'s printed table for the
## current figures rather than quoting numbers here, where they go stale
## silently.
func _draw_power_wires() -> void:
	# NO LOCAL rebuild_topology GUARD. There was one here, an MST-era leftover,
	# and it guarded nothing: wire_edges opens with the identical check and is
	# the only thing called below, so the rebuild happened either way. It did
	# not protect the _component_satisfaction read either — rebuild_topology
	# CLEARS that dict, so a dirty network reads satisfaction 0.0 and draws
	# every wire dead whichever path does the rebuilding.
	#
	# Colors named for the network state they represent, not for the hue
	# (live = any power, dead = zero supply). const, not var: these are
	# compile-time Colors and this function runs once per frame.
	const WIRE_THICKNESS: float = 2.0
	const WIRE_COLOR_LIVE: Color = Color(0.85, 0.70, 0.40)  # golden — network has power
	const WIRE_COLOR_DEAD: Color = Color(0.30, 0.22, 0.15)  # dark brown — no supply
	for edge in PowerNetwork.wire_edges(self):
		var pa: Vector2i = edge[0]
		var pb: Vector2i = edge[1]
		var cid: int = int(_pole_component.get(pa, -1))
		var sat: float = float(_component_satisfaction.get(cid, 0.0))
		var wire_color: Color = WIRE_COLOR_LIVE if sat > 0.0 else WIRE_COLOR_DEAD
		# Footprint-derived at BOTH ends — see _pole_wire_anchor.
		draw_line(_pole_wire_anchor(pa), _pole_wire_anchor(pb), wire_color, WIRE_THICKNESS)

## Where one pole's wires terminate, in world pixels.
##
## NOT the anchor cell's centre-top, which is what this used to be. The anchor
## of a multi-cell tier is its WEST/NORTH cell, so an anchor-based endpoint
## puts every substation wire over the TOP-LEFT QUARTER of a body that is two
## tiles on a side. Task 4 created that: substations only entered
## _pole_component then, so they only started being wire-drawn then. Derived
## from the FOOTPRINT instead, which is orientation-independent.
##
## Horizontally: the footprint's centre, always.
##
## Vertically: the 1x1 mast tiers terminate near the top, at MAST_WIRE_Y —
## power_pole.gd draws its single crossarm at exactly that offset, and on
## medium_pole.gd (crossarms at 0.10 and 0.26) it lands on the shaft between
## the two, which reads correctly. The 2x2 substation has NO mast:
## substation.gd paints a solid body with insulators at the four cell centres,
## so its wires meet the body centre, the only point equidistant from all four.
## Footprint HEIGHT is the discriminator because in this project the mast
## tiers are exactly the 1x1 ones — if a 1x2 masted tier ever exists, this
## needs a real per-tier attachment point rather than a shape test.
##
## For every 1x1 pole this returns bit-identical values to the old inline
## expression, so no shipped basic-pole visual moved.
##
## Every rewrite of the edge RULE — mesh, MST, and now the Gabriel graph —
## draws a different SET of wires but terminates them at the same points, and
## must call this rather than recomputing. Horizontally this is the footprint
## centre, the same geometry point PowerNetwork._pole_centre_doubled measures
## the Gabriel blocker test from — halved, and in pixels rather than doubled
## tiles. The two are independent derivations of one idea and are allowed to
## be: this one also has to answer a vertical question the blocker test does
## not have (mast crossarm versus body centre).
func _pole_wire_anchor(anchor: Vector2i) -> Vector2:
	var b: Building = buildings.get(anchor, null)
	var fp: Vector2i = Vector2i(1, 1) if b == null else Buildings.footprint_of(b.type)
	var x: float = (float(anchor.x) + float(fp.x) * 0.5) * float(TILE_SIZE)
	if fp.y == 1:
		return Vector2(x, float(anchor.y) * float(TILE_SIZE) + float(TILE_SIZE) * MAST_WIRE_Y)
	return Vector2(x, (float(anchor.y) + float(fp.y) * 0.5) * float(TILE_SIZE))
