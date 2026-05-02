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
	# Direction preview for directional building placements.
	if hotbar.current_kind() == "building" and Buildings.supports_direction(hotbar.current_value()):
		grid_world.hover_arrow_dir = placement_direction
	else:
		grid_world.hover_arrow_dir = -1

	if Input.is_action_just_pressed("rotate_placement"):
		placement_direction = (placement_direction + 1) % 4

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
	if Input.is_action_just_pressed("debug_spawn_demo"):
		_spawn_demo_chain(player_tile)

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

## Debug-only: spawns a working wheat → flour chain east of the player.
## Layout is vertical; a Briquetter+Void pair sits west of the thresher-
## output belt to drain straw so the chain runs continuously.
func _spawn_demo_chain(player_tile: Vector2i) -> void:
	# Origin is 3 tiles east of player so it doesn't overlap walking space.
	var o: Vector2i = player_tile + Vector2i(3, 0)
	# (offset_from_origin, overlay, building_type, extra_payload)
	var plan: Array = [
		[Vector2i(0, 0),  Terrain.Overlay.SOIL_TILLED, Buildings.Type.PLANTER,    Items.Type.WHEAT],
		[Vector2i(0, 1),  Terrain.Overlay.STONE,       Buildings.Type.HARVESTER,  null],
		[Vector2i(0, 2),  Terrain.Overlay.STONE,       Buildings.Type.BELT,       null],
		[Vector2i(0, 3),  Terrain.Overlay.STONE,       Buildings.Type.BELT,       null],
		[Vector2i(0, 4),  Terrain.Overlay.STONE,       Buildings.Type.THRESHER,   null],
		[Vector2i(0, 5),  Terrain.Overlay.STONE,       Buildings.Type.BELT,       null],
		[Vector2i(-1, 5), Terrain.Overlay.STONE,       Buildings.Type.BRIQUETTER, null],
		[Vector2i(-2, 5), Terrain.Overlay.STONE,       Buildings.Type.VOID,       null],
		[Vector2i(0, 6),  Terrain.Overlay.STONE,       Buildings.Type.MILL,       null],
		[Vector2i(0, 7),  Terrain.Overlay.STONE,       Buildings.Type.BELT,       null],
		[Vector2i(0, 8),  Terrain.Overlay.STONE,       Buildings.Type.CHEST,      null],
	]
	var placed: int = 0
	var skipped: int = 0
	for entry in plan:
		var pos: Vector2i = o + entry[0]
		var overlay: int = entry[1]
		var btype: int = entry[2]
		var extra = entry[3]
		grid_world.set_overlay(pos, overlay)
		if grid_world.has_building_at(pos):
			skipped += 1
			continue
		var dir: int = Belt.DIR_S if btype == Buildings.Type.BELT else 0
		if grid_world.place_building(btype, pos, dir, extra):
			placed += 1
		else:
			skipped += 1
	_show_toast("[debug] Demo chain: %d placed, %d skipped" % [placed, skipped])

func _overlay_list_str(overlays: Array) -> String:
	var parts: Array = []
	for o in overlays:
		parts.append(Terrain.overlay_name(o))
	return ", ".join(parts)

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_timer = TOAST_DURATION
