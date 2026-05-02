extends Node2D

const TOAST_DURATION: float = 2.0
const PLAYER_INVENTORY_CAPACITY: int = 16

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera
@onready var grid_world: Node2D = $GridWorld
@onready var hud_label: Label = $HUD/InfoLabel
@onready var toast_label: Label = $HUD/ToastLabel
@onready var hotbar: Control = $HUD/Hotbar
@onready var inventory_panel: Control = $HUD/InventoryPanel
@onready var info_panel: Control = $HUD/InfoPanel

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

func _ready() -> void:
	player_inventory = Inventory.new(PLAYER_INVENTORY_CAPACITY)
	grid_world.camera = camera
	inventory_panel.inventory = player_inventory

	if SaveSystem.save_exists():
		if SaveSystem.load_game(grid_world, player, player_inventory):
			_show_toast("World loaded from save")
		else:
			_show_toast(SaveSystem.last_load_error if SaveSystem.last_load_error != "" else "Save file present but failed to load")
	else:
		grid_world.generate_default_world()
		_show_toast("1-9 build · Tab category · R rotate · E drain · Q inspect · Esc close · F5/F9 save/load")

func _process(delta: float) -> void:
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

	if Input.is_action_pressed("place_tile"):
		_try_place(hover_tile)
	if Input.is_action_pressed("remove_tile"):
		_try_remove(hover_tile)

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
		if SaveSystem.save_game(grid_world, player, player_inventory):
			_show_toast("Saved")
		else:
			_show_toast("Save failed — see console")
	if Input.is_action_just_pressed("quick_load"):
		if SaveSystem.load_game(grid_world, player, player_inventory):
			_show_toast("Loaded")
		else:
			_show_toast(SaveSystem.last_load_error if SaveSystem.last_load_error != "" else "Nothing to load")

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

func _try_place(pos: Vector2i) -> void:
	match hotbar.current_kind():
		"terrain":
			if not grid_world.set_overlay(pos, hotbar.current_value()):
				_rate_limited_fail_toast(grid_world.last_place_error)
		"building":
			var t: int = hotbar.current_value()
			if grid_world.has_building_at(pos):
				return
			var dir: int = placement_direction if Buildings.supports_direction(t) else 0
			var extra = hotbar.current_extra()
			if not grid_world.place_building(t, pos, dir, extra):
				_rate_limited_fail_toast(grid_world.last_building_place_error)

func _try_remove(pos: Vector2i) -> void:
	if not grid_world.clear_tile(pos):
		_rate_limited_fail_toast(grid_world.last_remove_error)

## Rate-limit toasts during drag-place / drag-remove so they don't spam per tick.
func _rate_limited_fail_toast(msg: String) -> void:
	if msg == "":
		return
	if TickSystem.current_tick - _last_failed_place_tick > 10:
		_show_toast(msg)
		_last_failed_place_tick = TickSystem.current_tick

func _try_inspect(hover_tile: Vector2i) -> void:
	if grid_world.has_building_at(hover_tile):
		var b: Building = grid_world.building_at(hover_tile)
		info_panel.set_target(b, grid_world)
	else:
		info_panel.clear_target()

func _try_interact(player_tile: Vector2i) -> void:
	var b: Building = grid_world.find_adjacent_drainable(player_tile)
	if b == null:
		return
	var moved: int = Buildings.drain_into_player(b, player_inventory)
	if moved > 0:
		_show_toast("Drained %s (+%d items)" % [Buildings.name_of(b.type), moved])
	else:
		_show_toast("%s is empty" % Buildings.name_of(b.type))

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
	var cloth_plan: Array = [
		[Vector2i(0, 0), Terrain.Overlay.SOIL_TILLED, GRASS, Buildings.Type.PLANTER,   Items.Type.FLAX, 0],
		[Vector2i(0, 1), Terrain.Overlay.STONE,       GRASS, Buildings.Type.HARVESTER, null,            0],
		[Vector2i(0, 2), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,      null,            BLT_S],
		[Vector2i(0, 3), Terrain.Overlay.STONE,       GRASS, Buildings.Type.RETTER,    null,            0],
		[Vector2i(0, 4), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,      null,            BLT_S],
		[Vector2i(0, 5), Terrain.Overlay.STONE,       GRASS, Buildings.Type.LOOM,      null,            0],
		[Vector2i(0, 6), Terrain.Overlay.STONE,       GRASS, Buildings.Type.BELT,      null,            BLT_S],
		[Vector2i(0, 7), Terrain.Overlay.STONE,       GRASS, Buildings.Type.TAILOR,    null,            0],
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
