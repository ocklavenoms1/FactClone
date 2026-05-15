extends Node2D

const TOAST_DURATION: float = 2.0
const PLAYER_INVENTORY_CAPACITY: int = 16

# Bag-cap mechanic (Session E final). Bags are consumed by the player to
# permanently expand inventory. SLOTS_PER_BAG slots per bag, capped at
# BAG_CAP total bags consumed (lifetime, persists across save/load).
const SLOTS_PER_BAG: int = 4
const BAG_CAP: int = 5
const BAG_CONFIRM_WINDOW: float = 3.0   # seconds; "press B again to confirm"

# Camera zoom range. Computed against the 1080-px viewport short axis:
#   ZOOM_MIN = 1080 / (TILE_SIZE * 40 tiles) ≈ 0.84   → ~40-tile overview
#   ZOOM_MAX = 1080 / (TILE_SIZE * 5 tiles)  ≈ 6.75   → ~5-tile detail
# Each wheel notch multiplies target_zoom by ZOOM_STEP (or 1/ZOOM_STEP).
# Smoothing lerps actual camera.zoom toward target_zoom each frame.
const ZOOM_MIN: float = 0.85
const ZOOM_MAX: float = 6.75
const ZOOM_STEP: float = 1.15
const ZOOM_SMOOTH_RATE: float = 12.0
var target_zoom: float = 1.0

# ---------- harvesting (manual tier — ore mining + tree chopping) ----------
# Per-resource tick interval (seconds). Each tick extracts 1 ore (drains
# 1 richness) for ore types, OR chops 1 tree (single-shot) for trees.
# Stone/coal/clay are commodity-tier ore (2/sec); iron/copper are mid-tier
# (1/sec). Trees are 2 sec/chop (single-shot).
const HARVEST_TICK_INTERVAL: Dictionary = {
	ResourceNodes.Type.STONE:  0.5,
	ResourceNodes.Type.COAL:   0.5,
	ResourceNodes.Type.IRON:   1.0,
	ResourceNodes.Type.COPPER: 1.0,
	ResourceNodes.Type.CLAY:   0.5,
	ResourceNodes.Type.TREE:   2.0,
}

# Resource → item produced per harvest tick.
const HARVEST_RESOURCE_TO_ITEM: Dictionary = {
	ResourceNodes.Type.STONE:  Items.Type.RAW_STONE,
	ResourceNodes.Type.COAL:   Items.Type.COAL,
	ResourceNodes.Type.IRON:   Items.Type.IRON_ORE,
	ResourceNodes.Type.COPPER: Items.Type.COPPER_ORE,
	ResourceNodes.Type.CLAY:   Items.Type.CLAY,
	ResourceNodes.Type.TREE:   Items.Type.WOOD,
}

# Sentinel — represents "no current harvest target".
const HARVEST_INVALID_TARGET: Vector2i = Vector2i(2147483647, 2147483647)
var _harvest_target: Vector2i = HARVEST_INVALID_TARGET
var _harvest_progress: float = 0.0   # accumulated time toward next tick
var _last_harvest_full_inv_tick: int = -100   # rate-limit "Inventory full" toast

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera
@onready var grid_world: Node2D = $GridWorld
@onready var hud_label: Label = $HUD/InfoLabel
@onready var toast_label: Label = $HUD/ToastLabel
@onready var hotbar: Control = $HUD/Hotbar
@onready var inventory_panel: Control = $HUD/InventoryPanel
@onready var info_panel: Control = $HUD/InfoPanel
@onready var inventory_grid: Control = $HUD/InventoryGrid
@onready var map_panel: MapPanel = $HUD/MapPanel
# Building Interaction UI (session-building-ui-1). Three panel nodes; main.gd
# routes click-to-open to the right one based on b.type. building_panel is
# the generic fallback for buildings whose slot_layout is registered but
# don't yet have a specialized panel (everything except smelter + drill in
# Session 1; future sessions add specialized panels).
@onready var building_panel: Control = $HUD/BuildingPanel
@onready var smelter_panel: Control = $HUD/SmelterPanel
@onready var drill_panel: Control = $HUD/DrillPanel
# Session 2 panels (session-building-ui-2):
@onready var chest_panel: Control = $HUD/ChestPanel
@onready var mill_panel: Control = $HUD/MillPanel
@onready var oven_panel: Control = $HUD/OvenPanel
@onready var proofer_panel: Control = $HUD/ProoferPanel
@onready var packager_panel: Control = $HUD/PackagerPanel
@onready var mixer_panel: Control = $HUD/MixerPanel
# Session 3 panels (session-building-ui-3): cloth chain + remaining processors.
@onready var loom_panel: Control = $HUD/LoomPanel
@onready var tailor_panel: Control = $HUD/TailorPanel
@onready var briquetter_panel: Control = $HUD/BriquetterPanel
@onready var sugar_press_panel: Control = $HUD/SugarPressPanel
@onready var retter_panel: Control = $HUD/RetterPanel
@onready var yeast_culture_panel: Control = $HUD/YeastCulturePanel
# Session 4 panels (session-building-ui-4): extraction tier + thresher catch-up.
@onready var thresher_panel: Control = $HUD/ThresherPanel
@onready var planter_panel: Control = $HUD/PlanterPanel
@onready var harvester_panel: Control = $HUD/HarvesterPanel
# Soil exhaustion arc (session-soil-exhaustion-3): Composter feeds the
# fertilizer chain. ProcessorPanel-based — no specialized layout needed.
@onready var composter_panel: Control = $HUD/ComposterPanel
# Soil exhaustion arc (session-soil-exhaustion-3-5): Fertilizer Applicator
# auto-applies compost to depleted tiles in 5×5 coverage. Specialized
# panel renders the coverage grid + status; extends BuildingPanel.
@onready var applicator_panel: Control = $HUD/FertilizerApplicatorPanel
# Inserter Arc Session 1 (session-inserter-foundation): basic inserter
# specialized panel — held item display + fuel slot + source/dest text +
# cycle progress bar. Extends BuildingPanel directly.
@onready var inserter_panel: Control = $HUD/InserterPanel
# Inserter Arc Session 2 (session-inserter-fast-filter): fast inserter
# panel — extends InserterPanel; adds filter slot row (drop-to-set,
# right-click-to-clear). Same scene-tree neighbor pattern as Session 1.
@onready var fast_inserter_panel: Control = $HUD/FastInserterPanel
@onready var minimap: Control = $HUD/Minimap
# Dev Console (session-dev-console). Backtick toggles. Debug-build-only —
# activation gated in _unhandled_input. Replaces "build a chain to test"
# with one-line console state setup. See PROJECT_LOG entry for design.
# Untyped so runtime duck-typing finds is_open() on the actual instance
# (typing as Control accepts the assignment but fails resolution at the
# .is_open() call site; typing as DevConsole hits class_name registration
# race in tests and parse cycles).
@onready var dev_console = $HUD/DevConsole
# Quantity picker (QoL Cluster A — spec §4.2 / §6). Hard-modal popup
# instantiated as a HUD child via ext_resource in main.tscn. Wired into
# inventory_grid (Task 19); future Tasks 20-21 add chest_panel and
# BuildingPanel wire-up. Gated alongside dev_console in _process /
# _unhandled_input to suppress polled inputs while open.
@onready var quantity_picker: QuantityPickerModal = $HUD/QuantityPickerModal

var player_inventory: Inventory
var toast_timer: float = 0.0
var _last_failed_place_tick: int = -1

var placement_direction: int = Belt.DIR_E   # 0=E, 1=S, 2=W, 3=N

# F11 demo state. Tracks whether a demo has been spawned this session, plus
# the player tile it was spawned at. Subsequent F11 presses no-op with a
# toast (saved an hour of "where did F11 spawn?" debugging once already).
# Shift+F11 clears the flag for an explicit respawn — non-destructive; the
# player manually cleans up old demo buildings if they want a fresh layout.
var _demo_spawned: bool = false
var _demo_origin: Vector2i = Vector2i.ZERO

# Vision tracking: which region the player was in last frame. When the player
# crosses a region boundary, GridWorld.update_vision() is called to upgrade
# new in-range regions to active and demote out-of-range ones to fog.
# Sentinel value (large) ensures the first frame triggers an update.
var _player_last_region: Vector2i = Vector2i(99999, 99999)

# Player progression — single dict so future progression state (score,
# achievements, etc.) lives in one persistent container instead of
# accumulating as parallel vars on main.gd.
#
# Today's only key is `bags_consumed: int` (0..BAG_CAP), set by the bag-
# consume flow and read by inventory_panel + the cap-check on B presses.
# Persists via SaveSystem; load returns it on LoadResult.player_progression.
var player_progression: Dictionary = {
	"bags_consumed": 0,
}

# Shared cursor stack — passed by reference to inventory_grid + every building
# panel so picked-up items survive modal switches (player picks up wood in the
# inventory grid, closes it, opens the smelter panel, drops into fuel slot).
# Persists across save/load via player_progression["cursor"] (additive field;
# no save schema bump).
var cursor: CursorStack = CursorStack.new()

# Two-press confirm state for bag consumption. First B press shows a
# prompt and arms the confirm window; second press within the window
# consumes the bag. Window expires silently. See _process loop for the
# decay-before-input ordering.
var _bag_confirm_pending: bool = false
var _bag_confirm_expires_at: float = 0.0

func _ready() -> void:
	player_inventory = Inventory.new(PLAYER_INVENTORY_CAPACITY)
	grid_world.camera = camera
	inventory_panel.inventory = player_inventory
	# Inventory panel reads progression by reference — Dictionary is shared,
	# panel re-reads on every redraw to display "Bags: X/5 consumed".
	inventory_panel.player_progression = player_progression
	# Inventory grid (modal) — same Inventory ref so changes are live.
	# Toast callback so auto-return events surface in the HUD.
	inventory_grid.inventory = player_inventory
	inventory_grid.toast_callback = _show_toast
	# Shared cursor — same instance used by every building panel.
	inventory_grid.cursor = cursor
	# Quantity picker ref for ctrl+LMB dispatch (Task 19). Inventory grid
	# computes max via SlotClickHandler.ctrl_click_max and opens the picker
	# with a confirm Callable that runs ctrl_click_transfer.
	inventory_grid.quantity_picker = quantity_picker
	# Hotbar gets a player_inventory ref so item_apply slots dim when the
	# player has 0 of the item (session-soil-exhaustion-3). Optional —
	# slots fall back to never-dim if ref is null.
	hotbar.player_inventory = player_inventory
	# Hotbar also gets a dev_console ref so its action checks
	# (Tab/Shift+Tab/number keys) are gated when the console is open
	# (post-PAUSE-1 hotfix, session-inserter-foundation).
	hotbar.dev_console = dev_console
	# Building panels share the same cursor + player inventory + toast.
	# Session 2: chest, mill, oven, proofer, packager, mixer panels join.
	# Session 3: loom, tailor, briquetter, sugar_press, retter, yeast_culture.
	# Session 4: thresher, planter, harvester. Multi-session UI arc COMPLETE.
	var all_panels: Array = [
		building_panel, smelter_panel, drill_panel, composter_panel, applicator_panel,
		chest_panel, mill_panel, oven_panel, proofer_panel, packager_panel, mixer_panel,
		loom_panel, tailor_panel, briquetter_panel, sugar_press_panel,
		retter_panel, yeast_culture_panel,
		thresher_panel, planter_panel, harvester_panel,
		inserter_panel, fast_inserter_panel,
	]
	for panel in all_panels:
		if panel != null:
			panel.cursor = cursor
			panel.inventory = player_inventory
			panel.toast_callback = _show_toast
	# Player gates movement on any building panel being open.
	player.building_panels = all_panels
	# Player gates its movement on inventory_grid.is_open() — wire the ref.
	player.inventory_grid = inventory_grid
	# Map panel needs world + player references for rendering and the
	# player-position marker. Background build runs from _process below.
	map_panel.world = grid_world
	map_panel.player = player
	# Player gates movement on map_panel.is_open() too.
	player.map_panel = map_panel
	# Player needs grid_world for tile-passability collision (water blocks).
	player.grid_world = grid_world
	# Minimap shares the map_panel's cached texture (samples a region each frame).
	minimap.world = grid_world
	minimap.player = player
	minimap.map_panel = map_panel
	# Resource depletion → map dirty hookup. When mining changes a tile's
	# resource state, the map texture for that tile's region needs redraw.
	grid_world.resource_changed.connect(_on_resource_changed)
	# Dev Console wiring (session-dev-console). Wire game-state references
	# AFTER they exist (player_inventory was just constructed). Activation
	# gating happens in _unhandled_input.
	dev_console.grid_world = grid_world
	dev_console.player = player
	dev_console.player_inventory = player_inventory
	# Player gates movement on dev_console.is_open() so WASD doesn't move
	# the player while the LineEdit captures keystrokes as text.
	player.dev_console = dev_console
	# Initialize zoom from whatever the camera was authored at, so target
	# tracking starts in lockstep instead of snapping on first wheel input.
	target_zoom = camera.zoom.x

	if SaveSystem.save_exists():
		var result: LoadResult = SaveSystem.load_game(grid_world, player, player_inventory)
		if result.success:
			_apply_loaded_progression(result.player_progression)
			_show_toast("World loaded from save (seed %d)" % grid_world.world_seed)
		else:
			# Hotfix (post-3.5, NOTES.md "Schema-mismatch UX gap"): when load
			# fails (schema mismatch, corrupt JSON, missing fields, etc.),
			# fall through to fresh-world generation. Previous behavior left
			# the world in default empty state — player thought "world has
			# no resources" rather than "save load failed." Error from
			# load_game is already surfaced via OS.alert + push_error in
			# save_system.gd; we add a toast and proceed.
			push_warning("Save load failed (%s) — generating fresh world." % result.error_message)
			var fail_msg: String = "Save incompatible — fresh world (seed %d)" % _generate_fresh_world()
			_show_toast(fail_msg)
	else:
		var seed_msg: int = _generate_fresh_world()
		_show_toast("New world (seed %d) · 1-9 build · Tab · R rotate · F5 save · B bag · M map" % seed_msg)

	# Run an initial vision update from the player's spawn position — upgrades
	# the 5×5 around player from fog (or unrevealed) to active. Same call site
	# for both fresh-start and loaded-save paths.
	_player_last_region = GridWorld.region_of_world_pos(player.global_position)
	grid_world.update_vision(_player_last_region)

## Apply a loaded progression dict to runtime state. Missing keys keep the
## defaults that main.gd's `player_progression` was initialized with — this
## is the forward-compat read pattern from CONVENTIONS.md.
func _apply_loaded_progression(loaded: Dictionary) -> void:
	for key in loaded.keys():
		player_progression[key] = loaded[key]
	# Restore cursor stack (additive field, session-building-ui-1).
	# Old saves don't have this key → cursor stays empty.
	if loaded.has("cursor") and loaded["cursor"] is Dictionary:
		cursor.from_dict(loaded["cursor"])

## Pre-save hook — fold the live cursor stack into player_progression so
## SaveSystem captures it. Missing items (cursor.has_item() == false) still
## serialize as {-1, 0}; load_dict normalizes to clear().
func _capture_cursor_in_progression() -> void:
	player_progression["cursor"] = cursor.to_dict()

## Forward GridWorld.resource_changed signal to the map panel's dirty
## tracking so M-map / minimap re-render the affected region next frame.
func _on_resource_changed(pos: Vector2i) -> void:
	if map_panel != null:
		map_panel.mark_tile_dirty(pos)

## Pick a safe (passable) spawn position for fresh-start play. Scans tiles
## within a small radius of origin, collects passable candidates sorted by
## distance to origin, and uses seeded RNG to pick from the closest N.
##
## Deterministic per seed: same world_seed → same spawn. Different seeds
## produce different spawns, giving fresh-start variety while keeping
## save/load consistent.
const SPAWN_SEARCH_RADIUS: int = 30
const SPAWN_PICK_TOP_N: int = 20
const SPAWN_SEED_OFFSET: int = 999

## Fresh-world generation. Called from `_ready` for both the no-save path
## AND the save-load-failed-fallthrough path (hotfix post-3.5: schema-
## mismatch UX gap). Returns the generated seed so callers can include
## it in their toast.
##
## Side effects: assigns grid_world.world_seed, runs WorldGenerator.generate,
## sets initial reveal radius, places player at a safe spawn. Idempotent
## relative to a default-state grid_world (loaded but empty after a failed
## load is fine — generate() rebuilds tiles from the seed).
func _generate_fresh_world() -> int:
	grid_world.world_seed = randi()
	var generator: WorldGenerator = WorldGenerator.new()
	generator.generate(grid_world, grid_world.world_seed)
	# Initial reveal: mark the spawn-vicinity 7×7 region area as fog so the
	# map shows context on first M-press, not all-black.
	grid_world.initial_reveal()
	# Spawn position: seeded-random from passable tiles near origin so the
	# player isn't dropped into water/lakes.
	player.global_position = _safe_spawn_position()
	return grid_world.world_seed

func _safe_spawn_position() -> Vector2:
	var candidates: Array[Vector2i] = []
	for x in range(-SPAWN_SEARCH_RADIUS, SPAWN_SEARCH_RADIUS + 1):
		for y in range(-SPAWN_SEARCH_RADIUS, SPAWN_SEARCH_RADIUS + 1):
			var pos: Vector2i = Vector2i(x, y)
			if grid_world.is_passable_at(pos):
				candidates.append(pos)
	if candidates.is_empty():
		# Defensive: no passable tile in spawn area (extreme seed). Fall back
		# to (0, 0) — player will start on water but the move-and-slide
		# escape valve in player.gd lets them walk off.
		return Vector2(0, 0)
	# Sort by distance from origin so we pick from the closest passable tiles.
	candidates.sort_custom(func(a, b):
		return (a.x * a.x + a.y * a.y) < (b.x * b.x + b.y * b.y)
	)
	var top_n: int = min(SPAWN_PICK_TOP_N, candidates.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = grid_world.world_seed + SPAWN_SEED_OFFSET
	var picked: Vector2i = candidates[rng.randi_range(0, top_n - 1)]
	# Center of tile in world coords (TILE_SIZE = 32).
	var ts: float = float(GridWorld.TILE_SIZE)
	return Vector2(picked.x * ts + ts * 0.5, picked.y * ts + ts * 0.5)

func _process(delta: float) -> void:
	# Vision update on region cross. Cheap: one Vector2i compare per frame;
	# only does work on the rare frames where player crosses a region boundary
	# (typically every several seconds at walking speed).
	var current_region: Vector2i = GridWorld.region_of_world_pos(player.global_position)
	if current_region != _player_last_region:
		var changed: Array = grid_world.update_vision(current_region)
		map_panel.mark_regions_dirty(changed)
		_player_last_region = current_region

	# Background build of the map texture: ~8 regions per frame from game
	# start until the full 16×16 = 256 regions are built. Total ~32 frames
	# at 60fps = ~0.5 sec; per-frame cost ~0.8ms (invisible).
	map_panel.tick_background_build()

	# Minimap visibility: hide when a fullscreen modal is open (M-map,
	# inventory grid, or any building panel). Cheap conditional, polled per
	# frame.
	minimap.visible = not (map_panel.is_open() or inventory_grid.is_open() or _any_building_panel_open())

	# Dev Console gate (session-inserter-foundation post-PAUSE-1 hotfix):
	# when console is open, suppress ALL gameplay action input.
	# Input.is_action_just_pressed reads from InputMap regardless of
	# keyboard focus — without this gate, typing 'M' or 'I' or 'F5' into
	# the console LineEdit also triggers the corresponding game action.
	# Console handles its own input (Esc-to-close, history nav, submit)
	# via its own LineEdit + _input handler.
	if dev_console != null and dev_console.is_open():
		return
	# Quantity picker gate (Task 19). popup_exclusive_on_parent blocks
	# UI-level events automatically, but Input.is_action_just_pressed
	# (polled here) bypasses modal routing. Suppresses hotbar keys,
	# building placement, Q-inspect, etc., while the picker is open.
	if quantity_picker != null and quantity_picker.visible:
		return

	# Inventory toggle (I) — always handled, even while grid is open
	# (lets I close the grid).
	if Input.is_action_just_pressed("toggle_inventory"):
		inventory_grid.toggle()
	# Map toggle (M) — always handled. M while open also closes (matches I/inventory).
	if Input.is_action_just_pressed("toggle_map"):
		map_panel.toggle()
	# Esc priority chain (session-building-ui-1):
	#   1. inventory_grid open  → close it
	#   2. building panel open  → close it
	#   3. map panel open       → close it
	#   4. info panel has target → clear target
	#   5. hotbar has selection → clear (enter NEUTRAL)
	#   6. else                  → no-op (future: pause menu)
	if Input.is_action_just_pressed("close_info_panel"):
		if inventory_grid.is_open():
			inventory_grid.toggle()
		elif _any_building_panel_open():
			_close_active_building_panel()
		elif map_panel.is_open():
			map_panel.toggle()
		elif info_panel.has_target():
			info_panel.clear_target()
		elif hotbar.has_selection():
			hotbar.clear_selection()
			_show_toast("Hotbar cleared — click a building to interact, or press 1-9 to re-select.")

	# Smooth-zoom: lerp camera.zoom toward target_zoom each frame.
	# Pure visual update — runs regardless of modal state so an in-flight
	# zoom-out animation completes even if the player opens inventory
	# mid-scroll. Wheel input updates target_zoom in _unhandled_input
	# below; that path IS gated when modal is open.
	var z: float = lerp(camera.zoom.x, target_zoom, clamp(delta * ZOOM_SMOOTH_RATE, 0.0, 1.0))
	camera.zoom = Vector2(z, z)

	# When inventory grid OR map panel OR building panel is open: skip
	# world / hotbar / placement / inspect / save / consume input. Game tick
	# still runs (factory keeps producing); player movement gated separately
	# in player.gd.
	if inventory_grid.is_open() or map_panel.is_open() or _any_building_panel_open():
		# Toast timer still ticks so auto-return / "place cursor" toasts
		# still surface and fade.
		if toast_timer > 0.0:
			toast_timer -= delta
			if toast_timer <= 0.0:
				toast_label.text = ""
		return

	var mouse_world: Vector2 = get_global_mouse_position()
	var hover_tile: Vector2i = grid_world.world_to_tile(mouse_world)
	var player_tile: Vector2i = grid_world.world_to_tile(player.global_position)

	grid_world.hover_tile = hover_tile
	grid_world.show_hover = true
	# Direction preview for directional building placements (Belt + every
	# rotatable processor). For multi-tile rotatable buildings the arrow
	# is centered on the footprint via the existing hover_arrow_dir path.
	if hotbar.current_kind() == "building" and Buildings.supports_direction(hotbar.current_value()):
		grid_world.hover_arrow_dir = placement_direction
	else:
		grid_world.hover_arrow_dir = -1
	# Footprint preview for multi-tile buildings (Mixer/Oven/Proofer/Packager).
	if hotbar.current_kind() == "building":
		grid_world.hover_building_type = hotbar.current_value()
	else:
		grid_world.hover_building_type = -1

	if Input.is_action_just_pressed("rotate_placement"):
		# Three cases for R:
		#   1. Holding a rotatable building → rotate placement direction.
		#   2. Holding a non-rotatable building → toast (silent no-op feels
		#      like a bug; tell the player why nothing happened).
		#   3. Hand empty / non-building selection → rotate the placed
		#      building under the cursor in-place if it's rotatable. Lets
		#      the player adjust port orientations without rebuilding —
		#      Factorio convention. Square footprint (1×1, 2×2) means
		#      rotation only swaps port directions, no cell relocation.
		var holding_building: bool = hotbar.current_kind() == "building"
		if holding_building and Buildings.supports_direction(hotbar.current_value()):
			placement_direction = (placement_direction + 1) % 4
		elif holding_building:
			_show_toast("%s has no directional ports" % Buildings.name_of(hotbar.current_value()))
		elif grid_world.has_building_at(hover_tile):
			var hovered: Building = grid_world.building_at(hover_tile)
			if Buildings.supports_direction(hovered.type):
				hovered.state["dir"] = (int(hovered.state.get("dir", 0)) + 1) % 4
				_show_toast("%s rotated to %s" % [Buildings.name_of(hovered.type), Belt.DIR_NAMES[int(hovered.state["dir"])]])
			else:
				_show_toast("%s has no directional ports" % Buildings.name_of(hovered.type))

	# NEUTRAL cursor mode (Esc-cleared hotbar): single LMB click on a
	# building tile opens its interaction UI. Adjacency-gated (Manhattan ≤ 1
	# from any footprint cell) per session-building-ui-1 design — consistent
	# with E-drain, manual mining, manual chopping. Held-LMB doesn't fire
	# here (use just_pressed) since modals are single-shot opens.
	if hotbar.current_kind() == "":
		if Input.is_action_just_pressed("place_tile"):
			_try_open_building_ui(hover_tile, player_tile)
	else:
		# `item_apply` slots use `just_pressed` (discrete consume per click) —
		# holding the button would otherwise drain inventory at frame rate.
		# Terrain / building slots use `pressed` (drag-to-paint / drag-to-
		# place semantics — placement at the same tile is idempotent).
		var trigger_pressed: bool
		if hotbar.current_kind() == "item_apply":
			trigger_pressed = Input.is_action_just_pressed("place_tile")
		else:
			trigger_pressed = Input.is_action_pressed("place_tile")
		if trigger_pressed:
			_try_place(hover_tile)
	if Input.is_action_pressed("remove_tile"):
		_try_remove(hover_tile)

	# Harvesting (manual tier). Spacebar held + cursor over an adjacent
	# resource_node tile (ore deposit OR tree) = harvest ticks every
	# HARVEST_TICK_INTERVAL[type] seconds. Ore drains 1 richness/tick;
	# trees chop in a single 2-second tick + start regrowth timer.
	_update_harvest(delta, hover_tile, player_tile)

	if Input.is_action_just_pressed("interact"):
		_try_interact(player_tile)

	if Input.is_action_just_pressed("inspect_building"):
		_try_inspect(hover_tile)
	if Input.is_action_just_pressed("close_info_panel"):
		info_panel.clear_target()

	# Debug: F11 spawns a complete working wheat→flour chain east of the
	# player, including a Briquetter+Void byproduct sink. Useful for
	# demoing the chain without manual layout. Removed when the bread
	# chain has a natural early-game placement tutorial.
	#
	# Dedup: the demo is offsets-from-player-at-press-time, so pressing F11
	# at two different positions silently scatters two demo copies (with
	# unrelated collisions skipped). Track a flag; subsequent presses toast
	# instead of spawning. Shift+F11 clears the flag for an explicit respawn.
	if Input.is_action_just_pressed("debug_spawn_demo"):
		if Input.is_key_pressed(KEY_SHIFT):
			_demo_spawned = false
			_show_toast("[debug] Demo flag cleared. Next F11 spawns fresh; clean up old demo manually.")
		elif _demo_spawned:
			_show_toast("[debug] Demo already exists at %s. Shift+F11 to allow respawn." % str(_demo_origin))
		else:
			_spawn_demo_chain(player_tile)
			_demo_spawned = true
			_demo_origin = player_tile

	if Input.is_action_just_pressed("quick_save"):
		_capture_cursor_in_progression()
		if SaveSystem.save_game(grid_world, player, player_inventory, player_progression):
			_show_toast("Saved")
		else:
			_show_toast("Save failed — see console")
	if Input.is_action_just_pressed("quick_load"):
		var result: LoadResult = SaveSystem.load_game(grid_world, player, player_inventory)
		if result.success:
			_apply_loaded_progression(result.player_progression)
			_show_toast("Loaded")
		else:
			_show_toast(result.error_message if result.error_message != "" else "Nothing to load")

	# Bag consume — two-press confirm. Decay BEFORE input check so an
	# expiry-frame press always reads as a fresh first press, never a
	# stale confirm. Time.get_ticks_msec is monotonic + pause-independent;
	# if a future "pause game" feature freezes _process, the prompt would
	# still expire by wall clock — which matches player perception.
	if _bag_confirm_pending and Time.get_ticks_msec() / 1000.0 >= _bag_confirm_expires_at:
		_bag_confirm_pending = false
	if Input.is_action_just_pressed("consume_bag"):
		if _bag_confirm_pending:
			_confirm_bag_consume()
		else:
			_request_bag_consume()

	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer <= 0.0:
			toast_label.text = ""

	var dir_indicator: String = ""
	if hotbar.current_kind() == "building" and Buildings.supports_direction(hotbar.current_value()):
		dir_indicator = "  Dir: %s" % Belt.DIR_NAMES[placement_direction]

	hud_label.text = "Player: %s   Hover: %s   Buildings: %d   Tick: %d   Holding: %s%s" % [
		str(player_tile), str(hover_tile),
		grid_world.buildings.size(),
		TickSystem.current_tick, hotbar.current_label(), dir_indicator
	]

## Mouse-wheel zoom. Wheel up zooms in (closer), wheel down zooms out
## (farther). Updates `target_zoom`; the lerp in _process smooths the
## actual camera.zoom toward it. Clamped to [ZOOM_MIN, ZOOM_MAX] so the
## player can't zoom past the spec'd range.
##
## Modal gating: the InventoryGrid uses MOUSE_FILTER_STOP, so when it's
## visible Godot's input routing intercepts wheel events at the Control
## level and they don't propagate here. The explicit is_open() guard
## below is belt-and-suspenders — keeps the design intent visible if
## the InventoryGrid's mouse_filter ever changes.
func _unhandled_input(event: InputEvent) -> void:
	# Dev Console toggle (session-dev-console). Debug-build-only: production
	# exports never see the console at all. Backtick (`/~ key) toggles.
	# Done BEFORE the inventory-grid early-return so the player can still
	# open the console while another modal is up (and using the console
	# actively bypasses normal-flow gating — that's the dev workflow).
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:   # backtick
			if dev_console != null:
				dev_console.toggle()
				get_viewport().set_input_as_handled()
				return
	# When the console is open, suppress all other input (place, zoom,
	# rotate, etc.). Console handles its own Escape via the LineEdit's
	# focus + KEY_ESCAPE branch in console.gd's _input.
	if dev_console != null and dev_console.is_open():
		return
	# Quantity picker gate (Task 19) — sibling of dev_console gate.
	if quantity_picker != null and quantity_picker.visible:
		return
	if inventory_grid != null and inventory_grid.is_open():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_handle_zoom_wheel(+1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_handle_zoom_wheel(-1)

## Apply a wheel-zoom step. `direction = +1` is zoom-in (wheel-up),
## `-1` is zoom-out (wheel-down). Thin instance wrapper around the pure
## static `_compute_zoom_action` so tests exercise the decision logic
## without instantiating Main's full @onready scene graph.
##
## Three behaviors layer on top of plain zoom (session-zoom-to-map):
##
##   A. Modal open + wheel-up  → close the modal. No zoom change. Player
##      wheels up again to actually zoom in.
##   B. Modal open + wheel-down → no-op. Modal blocks further wheel
##      events; this prevents rapid wheel input from re-triggering the
##      open/close toggle (clean state-machine debouncing).
##   C. World view + wheel-down at ZOOM_MIN floor → open the M-key map
##      modal. Same modal as the M key — fog-of-war, drag-pan, click-to-
##      pan all preserved. The threshold IS the existing zoom floor; no
##      new constant. Tolerance epsilon handles floating-point drift in
##      the lerp-converged target_zoom value.
##
## Architectural note: an earlier attempt built a separate MapBackdrop
## node + dual textures + cross-fade rendering. User clarification
## revealed the desired feature was "wheel-out triggers the existing
## M-key modal." Discarded the separate-render approach; this trigger
## replaces ~600 lines of work. See PROJECT_LOG (reversal #N).
const _ZOOM_FLOOR_EPSILON: float = 1.0e-4

func _handle_zoom_wheel(direction: int) -> void:
	var modal_open: bool = map_panel != null and map_panel.is_open()
	var action: Dictionary = _compute_zoom_action(target_zoom, modal_open, direction)
	target_zoom = action["new_zoom"]
	if action["toggle_modal"] and map_panel != null:
		map_panel.toggle()

## Pure decision function for wheel-zoom — no side effects, no Main
## instance required. Returns a dict with the new target_zoom value and
## whether the caller should toggle the map modal. Static + pure so
## tests can call it directly without standing up a scene tree.
##
## Inputs:
##   current_zoom   — caller's current target_zoom
##   modal_open     — is the map modal currently open?
##   direction      — +1 (wheel-up) or -1 (wheel-down); 0 is a no-op
## Returns:
##   { "new_zoom": float, "toggle_modal": bool }
##
## Branch order matters — modal-open dominates floor-trigger dominates
## normal zoom. See `_handle_zoom_wheel` docstring for the three layered
## behaviors (A, B, C) this function encodes.
static func _compute_zoom_action(current_zoom: float, modal_open: bool, direction: int) -> Dictionary:
	# A + B. Modal open: wheel-up closes, wheel-down is a no-op.
	if modal_open:
		return { "new_zoom": current_zoom, "toggle_modal": direction > 0 }
	# C. Wheel-down at the floor: open the modal, leave zoom at floor.
	if direction < 0 and current_zoom <= ZOOM_MIN + _ZOOM_FLOOR_EPSILON:
		return { "new_zoom": current_zoom, "toggle_modal": true }
	# Normal zoom — clamped to [ZOOM_MIN, ZOOM_MAX].
	var new_zoom: float = current_zoom
	if direction > 0:
		new_zoom = clamp(current_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	elif direction < 0:
		new_zoom = clamp(current_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	return { "new_zoom": new_zoom, "toggle_modal": false }

func _try_place(pos: Vector2i) -> void:
	match hotbar.current_kind():
		"terrain":
			if not grid_world.set_overlay(pos, hotbar.current_value()):
				_rate_limited_fail_toast(grid_world.last_place_error)
			else:
				map_panel.mark_tile_dirty(pos)
		"building":
			var t: int = hotbar.current_value()
			if grid_world.has_building_at(pos):
				return
			# Cluster C (post-session-inserter-fast-filter): if any cell of the
			# proposed footprint contains the player's tile, reject — placing a
			# non-walkable building on yourself would trap you (only the player's
			# `on_impassable` escape valve in `_move_with_passability` would let
			# you off, requiring movement input to leave). Console-placed buildings
			# bypass this check (devs accept the consequences). Belts skip the
			# check via the walkable flag — players can pave a belt under
			# themselves and walk off freely.
			var fp_check: Vector2i = Buildings.footprint_of(t)
			if not Buildings.is_walkable(t):
				var player_tile: Vector2i = grid_world.world_to_tile(player.global_position)
				for dx in fp_check.x:
					for dy in fp_check.y:
						if Vector2i(pos.x + dx, pos.y + dy) == player_tile:
							_rate_limited_fail_toast("Can't place %s on yourself — step off first." % Buildings.name_of(t))
							return
			var dir: int = placement_direction if Buildings.supports_direction(t) else 0
			var extra = hotbar.current_extra()
			if not grid_world.place_building(t, pos, dir, extra):
				_rate_limited_fail_toast(grid_world.last_building_place_error)
			else:
				# Mark all footprint regions dirty (multi-tile buildings can span 2 regions).
				for dx in fp_check.x:
					for dy in fp_check.y:
						map_panel.mark_tile_dirty(Vector2i(pos.x + dx, pos.y + dy))
		"item_apply":
			# Hand-apply consumable item (session-soil-exhaustion-3): consumes
			# 1 of the item from player inventory + applies its effect to the
			# tile. Today: fertilizer (COMPOST_LOW / COMPOST_MID). Future
			# kinds (seeds, wasteland restorers, etc.) extend the dispatch
			# inside _try_apply_item.
			_try_apply_item(pos, hotbar.current_value())

func _try_remove(pos: Vector2i) -> void:
	if not grid_world.clear_tile(pos):
		_rate_limited_fail_toast(grid_world.last_remove_error)
	else:
		map_panel.mark_tile_dirty(pos)

## Hand-apply a hotbar item_apply slot to a tile (session-soil-exhaustion-3).
## Dispatches by item type — today only fertilizers (COMPOST_LOW/MID) are
## valid; future item_apply kinds (seeds, wasteland restorers, etc.) add
## cases here.
##
## Behavior contract per item_type:
##   1. Confirm player_inventory has at least 1 of the item.
##   2. Apply effect to tile via grid_world helper. Helper returns whether
##      the application succeeded (lower-tier-onto-higher-tier rejected).
##   3. On success: consume 1 from inventory + toast.
##   4. On rejection: toast, do NOT consume.
##   5. If no inventory: toast (the dim-on-empty hotbar slot is the upstream
##      hint; this toast is the click-time confirmation).
func _try_apply_item(pos: Vector2i, item_type: int) -> void:
	# Inventory check first — dim-on-empty hotbar slot is the upstream
	# affordance, but we double-check here in case the player clicked a
	# previously-not-empty slot whose count just dropped to 0 (e.g., after
	# a previous fertilizer apply this same drag).
	if player_inventory.total_of(item_type) <= 0:
		_rate_limited_fail_toast("No %s in inventory." % Items.name_of(item_type))
		return
	# Fertilizer dispatch — three tiers as of Session 4.
	if item_type == Items.Type.COMPOST_LOW or item_type == Items.Type.COMPOST_MID or item_type == Items.Type.COMPOST_HIGH:
		# Capture wasteland state BEFORE applying so we can surface
		# "Restored wasteland tile" feedback on the de-wasteland path.
		var was_wasteland: bool = grid_world.is_wasteland_at(pos)
		var applied: bool = grid_world.try_apply_fertilizer(pos, item_type)
		if not applied:
			# Two reject reasons: lower-tier-on-higher OR non-HIGH on wasteland.
			if grid_world.is_wasteland_at(pos):
				_rate_limited_fail_toast("Tile is wasteland — only Premium Compost restores it.")
			else:
				_rate_limited_fail_toast("Tile already has higher-tier compost.")
			return
		player_inventory.remove(item_type, 1)
		if was_wasteland:
			_show_toast("Restored wasteland tile %s with %s." % [str(pos), Items.name_of(item_type)])
		else:
			_show_toast("Applied %s." % Items.name_of(item_type))
		return
	# Unknown item_apply type — defensive.
	_rate_limited_fail_toast("(No effect for %s yet.)" % Items.name_of(item_type))

## Rate-limit toasts during drag-place / drag-remove so they don't spam per tick.
func _rate_limited_fail_toast(msg: String) -> void:
	if msg == "":
		return
	if TickSystem.current_tick - _last_failed_place_tick > 10:
		_show_toast(msg)
		_last_failed_place_tick = TickSystem.current_tick

# ---------- mining ----------

## Resolve the current harvest target. Returns HARVEST_INVALID_TARGET if any
## condition fails (no adjacency / no harvestable resource).
##
## Rules:
##   - Manhattan distance from player_tile to hover_tile must be ≤ 1
##     (4-directional including self)
##   - hover_tile must have a resource_node in HARVEST_TICK_INTERVAL
##     (ore deposit OR tree)
##   - Tree tiles in regrowth state (resource_node == NONE but
##     resource_state has regrowth_remaining) are NOT harvestable —
##     player must wait for regrowth to complete
func _resolve_harvest_target(hover_tile: Vector2i, player_tile: Vector2i) -> Vector2i:
	var manhattan: int = abs(player_tile.x - hover_tile.x) + abs(player_tile.y - hover_tile.y)
	if manhattan > 1:
		return HARVEST_INVALID_TARGET
	if not grid_world.tiles.has(hover_tile):
		return HARVEST_INVALID_TARGET
	var t: Tile = grid_world.tiles[hover_tile]
	if not HARVEST_TICK_INTERVAL.has(t.resource_node):
		return HARVEST_INVALID_TARGET
	return hover_tile

func _update_harvest(delta: float, hover_tile: Vector2i, player_tile: Vector2i) -> void:
	var harvest_held: bool = Input.is_action_pressed("mine")
	var valid_target: Vector2i = HARVEST_INVALID_TARGET
	if harvest_held:
		valid_target = _resolve_harvest_target(hover_tile, player_tile)

	if valid_target == HARVEST_INVALID_TARGET:
		if _harvest_target != HARVEST_INVALID_TARGET:
			_harvest_target = HARVEST_INVALID_TARGET
			_harvest_progress = 0.0
			grid_world.clear_harvest_indicator()
		return

	# Active harvest tick.
	if valid_target != _harvest_target:
		_harvest_target = valid_target
		_harvest_progress = 0.0
	var resource_type: int = grid_world.tiles[_harvest_target].resource_node
	var tick_interval: float = float(HARVEST_TICK_INTERVAL[resource_type])
	_harvest_progress += delta
	while _harvest_progress >= tick_interval:
		_harvest_progress -= tick_interval
		_try_harvest_tick(_harvest_target, resource_type)
		# Tile may have just transitioned (ore depleted, tree chopped) —
		# re-check target validity. is_harvestable check covers both:
		# depleted ore tiles have resource_node == NONE; chopped trees too.
		if not grid_world.tiles.has(_harvest_target) \
		or not HARVEST_TICK_INTERVAL.has(grid_world.tiles[_harvest_target].resource_node):
			_harvest_target = HARVEST_INVALID_TARGET
			_harvest_progress = 0.0
			grid_world.clear_harvest_indicator()
			return

	grid_world.set_harvest_indicator(_harvest_target, _harvest_progress / tick_interval)

## Per-tick harvest action. Dispatches on resource type:
##   - Ore (is_ore): drain 1 richness, add 1 ore item to inventory.
##   - Tree (TREE): single-shot chop — tile becomes empty, regrowth timer
##     starts, N wood added (N = GridWorld.wood_yield_for_tree(pos),
##     varies 1-4 based on visible tree size).
##
## Inventory-full handling shared across both paths: rate-limited toast,
## skip the tick (no extraction).
func _try_harvest_tick(pos: Vector2i, resource_type: int) -> void:
	var item_type: int = int(HARVEST_RESOURCE_TO_ITEM[resource_type])
	# Compute amount up front: ore is always 1; trees yield 1-4 based on
	# visible tree size (deterministic per-position hash).
	var amount: int = 1
	if resource_type == ResourceNodes.Type.TREE:
		amount = GridWorld.wood_yield_for_tree(pos)
	if not player_inventory.has_room_for(item_type, amount):
		if TickSystem.current_tick - _last_harvest_full_inv_tick > 30:
			_show_toast("Inventory full.")
			_last_harvest_full_inv_tick = TickSystem.current_tick
		return
	player_inventory.add(item_type, amount)
	if ResourceNodes.is_ore(resource_type):
		grid_world.deplete_resource(pos, 1)
	elif resource_type == ResourceNodes.Type.TREE:
		grid_world.chop_tree(pos)

func _try_inspect(hover_tile: Vector2i) -> void:
	# Building takes priority — the info panel is primarily a building debugger.
	if grid_world.has_building_at(hover_tile):
		var b: Building = grid_world.building_at(hover_tile)
		info_panel.set_target(b, grid_world)
		return
	# Fall through to resource inspect: tile has resource_node.
	# (Under the "no overlay on deposits" invariant, deposits never carry
	# an overlay, so no need to check for obscured-by-paint here.)
	if grid_world.tiles.has(hover_tile):
		var t: Tile = grid_world.tiles[hover_tile]
		if t.resource_node != ResourceNodes.Type.NONE:
			info_panel.set_resource_target(hover_tile, grid_world)
			return
	# Fall through to TILE target (session-soil-exhaustion-1) — Q on empty
	# grass shows region info + soil_health. Player gets useful info on
	# every Q press; never goes to clear-target via Q.
	info_panel.set_tile_target(hover_tile, grid_world)

# ---------- Building Interaction UI (session-building-ui-1, extended in 2) ----------

## All registered panels — single list so iteration stays consistent across
## is-open checks, close-active dispatch, and shared-cursor wiring.
func _all_building_panels() -> Array:
	return [
		building_panel, smelter_panel, drill_panel, composter_panel, applicator_panel,
		chest_panel, mill_panel, oven_panel, proofer_panel, packager_panel, mixer_panel,
		loom_panel, tailor_panel, briquetter_panel, sugar_press_panel,
		retter_panel, yeast_culture_panel,
		thresher_panel, planter_panel, harvester_panel,
		inserter_panel, fast_inserter_panel,
	]

## True if any specialized building panel (or the generic fallback) is open.
func _any_building_panel_open() -> bool:
	for panel in _all_building_panels():
		if panel != null and panel.is_open():
			return true
	return false

## Close whichever building panel is currently open. Called by the Esc chain.
func _close_active_building_panel() -> void:
	for panel in _all_building_panels():
		if panel != null and panel.is_open():
			panel.close()
			return

## Click-to-open dispatch. Called when in NEUTRAL cursor mode (no hotbar
## selection) and player LMB-clicks a tile. Resolves the click to its
## owning building (multi-tile aware via grid_world.occupied), checks
## adjacency, then routes to the right specialized panel.
##
## Adjacency rule (per Q4 user pushback): Manhattan ≤ 1 from any cell of
## the building's footprint. Consistent with E-drain, manual mining,
## manual chopping. Click on a remote building → toast "Move closer".
func _try_open_building_ui(hover_tile: Vector2i, player_tile: Vector2i) -> void:
	if not grid_world.has_building_at(hover_tile):
		return    # silent no-op — clicked empty tile
	var b: Building = grid_world.building_at(hover_tile)
	if b == null:
		return
	# Adjacency check: Manhattan distance from player_tile to ANY cell of
	# the footprint must be ≤ 1.
	if not _is_adjacent_to_building(b, player_tile):
		_show_toast("Move closer to interact with %s." % Buildings.name_of(b.type))
		return
	# Dispatch to specialized panel by type. Buildings without a slot_layout
	# (mill, chest, etc.) toast — UI lands in future sessions.
	if not Buildings.has_interaction_ui(b.type):
		_show_toast("(No interaction UI yet for %s — coming in a future session.)" % Buildings.name_of(b.type))
		return
	match b.type:
		Buildings.Type.SMELTER:
			smelter_panel.open(b, grid_world)
		Buildings.Type.MINING_DRILL:
			drill_panel.open(b, grid_world)
		Buildings.Type.CHEST:
			chest_panel.open(b, grid_world)
		Buildings.Type.MILL:
			mill_panel.open(b, grid_world)
		Buildings.Type.OVEN:
			oven_panel.open(b, grid_world)
		Buildings.Type.PROOFER:
			proofer_panel.open(b, grid_world)
		Buildings.Type.PACKAGER:
			packager_panel.open(b, grid_world)
		Buildings.Type.MIXER:
			mixer_panel.open(b, grid_world)
		Buildings.Type.LOOM:
			loom_panel.open(b, grid_world)
		Buildings.Type.TAILOR:
			tailor_panel.open(b, grid_world)
		Buildings.Type.BRIQUETTER:
			briquetter_panel.open(b, grid_world)
		Buildings.Type.SUGAR_PRESS:
			sugar_press_panel.open(b, grid_world)
		Buildings.Type.RETTER:
			retter_panel.open(b, grid_world)
		Buildings.Type.YEAST_CULTURE:
			yeast_culture_panel.open(b, grid_world)
		Buildings.Type.THRESHER:
			thresher_panel.open(b, grid_world)
		Buildings.Type.PLANTER:
			planter_panel.open(b, grid_world)
		Buildings.Type.HARVESTER:
			harvester_panel.open(b, grid_world)
		Buildings.Type.COMPOSTER:
			composter_panel.open(b, grid_world)
		Buildings.Type.FERTILIZER_APPLICATOR:
			applicator_panel.open(b, grid_world)
		Buildings.Type.INSERTER:
			inserter_panel.open(b, grid_world)
		Buildings.Type.FAST_INSERTER:
			fast_inserter_panel.open(b, grid_world)
		_:
			# Future buildings whose slot_layout exists but specialized panel
			# doesn't: open the generic fallback. (Post-Session 4 the multi-
			# session UI arc is complete; remaining UI-less buildings are
			# passive infrastructure — Pipe/Pump/Belt — and won't reach here
			# because they have no slot_layout entry.)
			if building_panel != null:
				building_panel.open(b, grid_world)

## Manhattan ≤ 1 from any cell of building b's footprint (any direction
## including the building tile itself).
static func _is_adjacent_to_building(b: Building, player_tile: Vector2i) -> bool:
	var fp: Vector2i = Buildings.footprint_of(b.type)
	for dx in fp.x:
		for dy in fp.y:
			var cell: Vector2i = Vector2i(b.anchor.x + dx, b.anchor.y + dy)
			if abs(player_tile.x - cell.x) + abs(player_tile.y - cell.y) <= 1:
				return true
	return false

func _try_interact(player_tile: Vector2i) -> void:
	# E-key unified dispatch (session-building-ui-2):
	#   1. Adjacent building with interaction UI → open its panel
	#      (same as click-to-open in NEUTRAL cursor mode, but E ignores
	#       hotbar state — works whether holding an item or not).
	#   2. Adjacent drainable building (no UI) → drain into player inventory
	#      (legacy harvester behavior; preserved until Session 4 adds its UI).
	#   3. Else → silent no-op (don't toast on E with no target; players
	#      tap E speculatively).
	var b: Building = _find_adjacent_interactable(player_tile)
	if b != null:
		_try_open_building_ui(b.anchor, player_tile)
		return
	var d: Building = grid_world.find_adjacent_drainable(player_tile)
	if d == null:
		return
	var moved: int = Buildings.drain_into_player(d, player_inventory)
	if moved > 0:
		_show_toast("Drained %s (+%d items)" % [Buildings.name_of(d.type), moved])
	else:
		_show_toast("%s is empty" % Buildings.name_of(d.type))

## Scan the player's 4-adjacent cells (including own tile) for a building
## with `has_interaction_ui` registered. Returns null if none. Used by
## E-key dispatch to find what to open.
func _find_adjacent_interactable(player_tile: Vector2i) -> Building:
	var scan: Array = [
		player_tile,
		player_tile + Vector2i(1, 0),
		player_tile + Vector2i(-1, 0),
		player_tile + Vector2i(0, 1),
		player_tile + Vector2i(0, -1),
	]
	for cell in scan:
		if grid_world.has_building_at(cell):
			var b: Building = grid_world.building_at(cell)
			if b != null and Buildings.has_interaction_ui(b.type):
				return b
	return null

## Debug-only: spawns four minimal chains east of the player.
##
## Wheat chain (origin = player + (3, 0)):
##   Planter → Harvester → belt → Thresher
##                                ↓ east port → Belt → Mill → Flour Chest
##                                ↑ west port → Belt → Straw Chest
##
## Sugar chain (origin = player + (10, 0)):
##   Planter → Harvester → belt → Sugar Press → belt → Yeast Culture → Yeast Chest
##                                                    ↑
##                                                    pipe ← Pump ← Water tile
##   (Sugar keeps its own pump+water; only bread+cloth share, see below.)
##
## Cloth chain (origin = player + (10, 8)):
##   Flax Planter → Harvester → belt → Retter → belt → Loom → belt → Tailor → belt → Bag Chest
##   Pre-loaded: planter at 80% growth, harvester with 2 flax, so first flax
##   ripens in ~5s instead of 25s and the chain warmups quickly. NOT pre-
##   loading downstream stages — full end-to-end production must run.
##   Expected steady-state: ~1-2 bags in chest after 3 minutes. 0 bags = chain
##   stuck upstream, investigate. 5+ bags = unexpectedly fast (tick-rate
##   drift?), investigate. Calibration baseline.
##
## Bread mini (origin = player + (15, 8)): integration check for rotation +
## multi-tile. Mixer is 2×2 rotated DIR_S (90° CW). After rotation the
## canonical "flour W / yeast N / dough E" ports become world N / E / S.
##   Pre-loaded flour-chest above → flour belt south into mixer N edge
##   Pre-loaded yeast-chest right → yeast belt west into mixer E edge
##   Mixer south edge              → dough belt south → dough chest
##   Water comes from the SHARED network (Mixer W edge).
##
## Shared water network: ONE pump+water tile feeding both the Cloth chain's
## Retter AND the Bread mini's Mixer. The integration test for multi-consumer
## fluid networks. If both Retter and Mixer report water connected on F11
## spawn, the shared network works. If either fails, a pipe coordinate is off.
##
## Each chain is independently verifiable. Full bread chain (combining
## flour + yeast + water → dough → bread) lands when each piece passes.
func _spawn_demo_chain(player_tile: Vector2i) -> void:
	var GRASS: int = -1
	var BLT_E: int = Belt.DIR_E
	var BLT_S: int = Belt.DIR_S
	var BLT_W: int = Belt.DIR_W

	# Wheat chain
	var wheat_o: Vector2i = player_tile + Vector2i(3, 0)
	var wheat_plan: Array = [
		[Vector2i(0, 0),  Terrain.Overlay.SOIL_TILLED, GRASS, Buildings.Type.PLANTER,    Items.Type.WHEAT, 0],
		[Vector2i(0, 1),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.HARVESTER,  null,             0],
		[Vector2i(0, 2),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,       null,             BLT_S],
		[Vector2i(0, 3),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.THRESHER,   null,             0],
		[Vector2i(1, 3),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,       null,             BLT_E],
		[Vector2i(2, 3),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.MILL,       null,             0],
		[Vector2i(3, 3),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.CHEST,      null,             0],
		[Vector2i(-1, 3), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,       null,             BLT_W],
		[Vector2i(-2, 3), Terrain.Overlay.STONE,       GRASS, Buildings.Type.CHEST,      null,             0],
	]

	# Sugar / yeast chain. Includes a small water tile + pump + pipe so
	# the Yeast Culture has fluid input. Pump is east of YC, water east
	# of pump, pipe between YC and pump.
	var sugar_o: Vector2i = player_tile + Vector2i(10, 0)
	var sugar_plan: Array = [
		[Vector2i(0, 0),  Terrain.Overlay.SOIL_TILLED, GRASS, Buildings.Type.PLANTER,      Items.Type.SUGAR_BEET, 0],
		[Vector2i(0, 1),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.HARVESTER,    null,                  0],
		[Vector2i(0, 2),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,         null,                  BLT_S],
		[Vector2i(0, 3),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.SUGAR_PRESS,  null,                  0],
		[Vector2i(0, 4),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,         null,                  BLT_S],
		[Vector2i(0, 5),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.YEAST_CULTURE, null,                 0],
		[Vector2i(0, 6),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.CHEST,        null,                  0],
		# Water network east of YC.
		[Vector2i(1, 5),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.PIPE,         null,                  0],
		[Vector2i(2, 5),  Terrain.Overlay.STONE,       GRASS, Buildings.Type.PUMP,         null,                  0],
		[Vector2i(3, 5),  -1,                          Terrain.Base.WATER, -1,             null,                  0],
	]

	# Bread mini-chain: rotated 2×2 Mixer (dir=DIR_S → ports rotate 90° CW).
	# Canonical flour-W → world N. Canonical yeast-N → world E. Canonical
	# dough-E → world S. Mixer occupies (0,0)..(1,1) (anchor at 0,0).
	# Water is supplied by the SHARED network defined further down — no
	# standalone water/pump in this plan.
	var BLT_N: int = Belt.DIR_N
	var bread_o: Vector2i = player_tile + Vector2i(15, 8)
	var bread_plan: Array = [
		# Mixer 2×2 at (0,0)..(1,1), facing south.
		[Vector2i(0, 0),  Terrain.Overlay.STONE, GRASS, Buildings.Type.MIXER, null, BLT_S],
		# Stone for the rest of the mixer footprint (place_building handles
		# the anchor's overlay check; expansion cells need overlay too).
		[Vector2i(1, 0),  Terrain.Overlay.STONE, GRASS, -1,    null, 0],
		[Vector2i(0, 1),  Terrain.Overlay.STONE, GRASS, -1,    null, 0],
		[Vector2i(1, 1),  Terrain.Overlay.STONE, GRASS, -1,    null, 0],
		# Flour source: chest pre-loaded with flour above the N edge,
		# belt at (0,-1) pushes south into the mixer's N edge.
		[Vector2i(0, -2), Terrain.Overlay.STONE, GRASS, Buildings.Type.CHEST, null, 0],
		[Vector2i(0, -1), Terrain.Overlay.STONE, GRASS, Buildings.Type.BELT,  null, BLT_S],
		# Yeast source: chest at (3,0) east of mixer, belt at (2,0)
		# pushes west into the mixer's E edge.
		[Vector2i(3, 0),  Terrain.Overlay.STONE, GRASS, Buildings.Type.CHEST, null, 0],
		[Vector2i(2, 0),  Terrain.Overlay.STONE, GRASS, Buildings.Type.BELT,  null, BLT_W],
		# Dough sink: belt at (0,2) below the mixer S edge, chest catches.
		[Vector2i(0, 2),  Terrain.Overlay.STONE, GRASS, Buildings.Type.BELT,  null, BLT_S],
		[Vector2i(0, 3),  Terrain.Overlay.STONE, GRASS, Buildings.Type.CHEST, null, 0],
	]

	# Cloth chain: Flax Planter at top, vertical south-running line down to
	# Bag chest at bottom. Retter draws water from the SHARED network defined
	# below — its E perimeter is at column +1 of the chain, where the shared
	# network's western pipe terminates.
	var cloth_o: Vector2i = player_tile + Vector2i(10, 8)
	# Cloth processors rotated to face S (BLT_S): canonical W input → world N
	# (pulls from belt above), canonical E output → world S (pushes to belt
	# below). Water has no prefer_dir, still arrives via shared pipe network
	# regardless of building rotation.
	var cloth_plan: Array = [
		[Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED, GRASS, Buildings.Type.PLANTER,   Items.Type.FLAX, 0],
		[Vector2i(0, 1), Terrain.Overlay.STONE,       GRASS, Buildings.Type.HARVESTER, null,            0],
		[Vector2i(0, 2), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,      null,            BLT_S],
		[Vector2i(0, 3), Terrain.Overlay.STONE,       GRASS, Buildings.Type.RETTER,    null,            BLT_S],
		[Vector2i(0, 4), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,      null,            BLT_S],
		[Vector2i(0, 5), Terrain.Overlay.STONE,       GRASS, Buildings.Type.LOOM,      null,            BLT_S],
		[Vector2i(0, 6), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,      null,            BLT_S],
		[Vector2i(0, 7), Terrain.Overlay.STONE,       GRASS, Buildings.Type.TAILOR,    null,            BLT_S],
		[Vector2i(0, 8), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,      null,            BLT_S],
		[Vector2i(0, 9), Terrain.Overlay.STONE,       GRASS, Buildings.Type.CHEST,     null,            0],
	]

	# Shared water network — one pump, one water tile, two consumers (Cloth
	# Retter + Bread Mixer). Layout in player-relative coords:
	#   Water at (13, 12), Pump at (13, 11), pipes form an L:
	#     west:  (12, 11), (11, 11)  →  reaches Retter E perimeter at (11, 11)
	#     N+E:   (13, 10), (14, 10), (14, 9)  →  reaches Mixer W perimeter at (14, 9)
	# Water is placed FIRST so the pump's adjacency check passes when the
	# pump entry is processed.
	var shared_o: Vector2i = player_tile
	var shared_plan: Array = [
		[Vector2i(13, 12), -1,                    Terrain.Base.WATER, -1,            null, 0],
		[Vector2i(13, 11), Terrain.Overlay.STONE, GRASS,              Buildings.Type.PUMP, null, 0],
		# Pipes — order doesn't matter for connectivity (rebuilt lazily).
		[Vector2i(12, 11), Terrain.Overlay.STONE, GRASS,              Buildings.Type.PIPE, null, 0],
		[Vector2i(11, 11), Terrain.Overlay.STONE, GRASS,              Buildings.Type.PIPE, null, 0],
		[Vector2i(13, 10), Terrain.Overlay.STONE, GRASS,              Buildings.Type.PIPE, null, 0],
		[Vector2i(14, 10), Terrain.Overlay.STONE, GRASS,              Buildings.Type.PIPE, null, 0],
		[Vector2i(14, 9),  Terrain.Overlay.STONE, GRASS,              Buildings.Type.PIPE, null, 0],
	]

	var plan: Array = []
	for entry in wheat_plan:
		plan.append([wheat_o + entry[0], entry[1], entry[2], entry[3], entry[4], entry[5]])
	for entry in sugar_plan:
		plan.append([sugar_o + entry[0], entry[1], entry[2], entry[3], entry[4], entry[5]])
	for entry in bread_plan:
		plan.append([bread_o + entry[0], entry[1], entry[2], entry[3], entry[4], entry[5]])
	for entry in cloth_plan:
		plan.append([cloth_o + entry[0], entry[1], entry[2], entry[3], entry[4], entry[5]])
	for entry in shared_plan:
		plan.append([shared_o + entry[0], entry[1], entry[2], entry[3], entry[4], entry[5]])
	var placed: int = 0
	var skipped: int = 0
	for entry in plan:
		var pos: Vector2i = entry[0]   # already absolute (offset baked in above)
		var overlay: int = entry[1]
		var base: int = entry[2]
		var btype: int = entry[3]
		var extra = entry[4]
		var dir: int = entry[5]
		# Set base if requested.
		if base != -1:
			grid_world.tiles[pos] = Tile.new(base, Terrain.Overlay.NONE)
		# Set overlay if requested.
		if overlay != -1:
			grid_world.set_overlay(pos, overlay)
		# Place building if requested.
		if btype == -1:
			placed += 1
			continue
		if grid_world.has_building_at(pos):
			skipped += 1
			continue
		if grid_world.place_building(btype, pos, dir, extra):
			placed += 1
		else:
			skipped += 1
	# Pre-load the rotated mixer's input buffer so dough flows immediately.
	# (Chests are passive — they don't push to belts. Sourcing items onto
	# the belt would require a Harvester+crop or chaining to the wheat
	# chain's mill output, both of which add geometry without strengthening
	# the integration test. The unit tests already cover rotated PULL on
	# multiple edges via the 4-direction thresher rotation test; this F11
	# demo exists to verify rotated PUSH and visual placement of a 2×2.)
	var bread_mixer_pos: Vector2i = bread_o + Vector2i(0, 0)
	if grid_world.has_building_at(bread_mixer_pos):
		var mixer: Building = grid_world.building_at(bread_mixer_pos)
		mixer.state["in_buffer"] = [[Items.Type.FLOUR, 100], [Items.Type.YEAST, 50]]
	# Pre-load the Flax Planter to ~80% growth and the Harvester with 2 flax
	# already buffered. First flax lands in the chain in ~5s instead of 25s,
	# so verification doesn't have to wait a full cold start. Downstream
	# stages (Retter, Loom, Tailor) are NOT pre-loaded — they must run from
	# scratch, so the chain genuinely flows end-to-end.
	var flax_planter_pos: Vector2i = cloth_o + Vector2i(0, 0)
	if grid_world.has_building_at(flax_planter_pos):
		var planter: Building = grid_world.building_at(flax_planter_pos)
		planter.state["growth"] = 400  # 80% of the 500-tick flax cycle
	var flax_harvester_pos: Vector2i = cloth_o + Vector2i(0, 1)
	if grid_world.has_building_at(flax_harvester_pos):
		var harvester: Building = grid_world.building_at(flax_harvester_pos)
		harvester.state["buffer"] = [[Items.Type.FLAX, 2]]
	_show_toast("[debug] Demo chain: %d placed, %d skipped at origin %s" % [placed, skipped, str(player_tile)])

func _overlay_list_str(overlays: Array) -> String:
	var parts: Array = []
	for o in overlays:
		parts.append(Terrain.overlay_name(o))
	return ", ".join(parts)

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_timer = TOAST_DURATION

# ---------- bag consume ----------

## First-press path. Validates preconditions; only enters the pending-confirm
## state on a valid request. Failure ordering: cap-reached takes priority
## over no-bag (cap is the more permanent state — message helps the player
## stop trying).
func _request_bag_consume() -> void:
	if int(player_progression.get("bags_consumed", 0)) >= BAG_CAP:
		_show_toast("Inventory at maximum. Save bags for trade.")
		return
	if player_inventory.total_of(Items.Type.BAG) <= 0:
		_show_toast("No bag to consume.")
		return
	_bag_confirm_pending = true
	_bag_confirm_expires_at = Time.get_ticks_msec() / 1000.0 + BAG_CONFIRM_WINDOW
	_show_toast("Consume bag for +%d slots? Press B again to confirm." % SLOTS_PER_BAG)

## Second-press path. Defensive re-check of preconditions in case state
## changed between prompt and confirm (no current code path mutates these
## while a prompt is pending, but the check is cheap and future-proofs).
func _confirm_bag_consume() -> void:
	_bag_confirm_pending = false
	if int(player_progression.get("bags_consumed", 0)) >= BAG_CAP:
		_show_toast("Inventory at maximum. Save bags for trade.")
		return
	if player_inventory.total_of(Items.Type.BAG) <= 0:
		_show_toast("No bag to consume.")
		return
	player_inventory.remove(Items.Type.BAG, 1)
	player_inventory.expand(SLOTS_PER_BAG)
	var n: int = int(player_progression.get("bags_consumed", 0)) + 1
	player_progression["bags_consumed"] = n
	_show_toast("Inventory expanded: %d/%d bags consumed, +%d slots" % [n, BAG_CAP, SLOTS_PER_BAG])
