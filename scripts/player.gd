extends CharacterBody2D

const SPEED: float = 220.0
const RADIUS: float = 10.0
const BODY_COLOR: Color = Color(0.9, 0.78, 0.5)
const OUTLINE_COLOR: Color = Color(0.2, 0.15, 0.1)

# Set by main.gd at _ready. When any modal UI is open (inventory grid OR
# map panel), player input is suspended. velocity is zeroed each tick so a
# stale movement vector doesn't slide the player while the modal is up.
var inventory_grid: Control = null
var map_panel: Control = null
# Set by main.gd at _ready. Used for tile-based passability checks
# (water blocks movement; future obstacles via Tile.is_passable()).
var grid_world: GridWorld = null

func _physics_process(delta: float) -> void:
	var modal_open: bool = (inventory_grid != null and inventory_grid.is_open()) \
		or (map_panel != null and map_panel.is_open())
	if modal_open:
		velocity = Vector2.ZERO
		return

	var input_vec: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	# Custom tile-aware movement: bypass move_and_slide() (which only sees
	# Godot's physics-collision shapes — none for tiles) and instead check
	# each axis against Tile.is_passable() for sliding-along-edge feel.
	#
	# We scale the per-frame delta by SPEED * delta and resolve passability
	# per axis. velocity is kept for diagnostic / animation parity, but
	# movement is applied via direct global_position updates.
	velocity = input_vec * SPEED
	if grid_world != null:
		_move_with_passability(velocity * delta)
	else:
		# Defensive: no world reference (e.g., tests / scripted scenes) —
		# fall back to original move_and_slide() behavior.
		move_and_slide()

## Apply a movement delta with per-axis passability sliding. Player walks
## up to a water edge; diagonal motion glides along the edge instead of
## stopping dead.
##
## Edge cases:
##   - Player's tile is itself impassable (e.g., spawned on water somehow):
##     allow free movement off it (don't trap them).
##   - delta_pos is the FULL frame's movement (already SPEED-scaled).
func _move_with_passability(delta_pos: Vector2) -> void:
	if delta_pos == Vector2.ZERO:
		return
	var current_pos: Vector2 = global_position
	var current_tile: Vector2i = _world_pos_to_tile(current_pos)
	var on_impassable: bool = not grid_world.is_passable_at(current_tile)

	var target_pos: Vector2 = current_pos + delta_pos
	var target_tile: Vector2i = _world_pos_to_tile(target_pos)

	# Allow movement if:
	#  - target tile is passable, OR
	#  - target tile == current tile (movement within the same tile, even if it's water — defensive), OR
	#  - player is on impassable terrain (escape valve)
	if on_impassable or grid_world.is_passable_at(target_tile) or target_tile == current_tile:
		global_position = target_pos
		return

	# Try sliding: each axis independently. If only the X component would
	# stay on a passable tile, allow that; same for Y. Produces the "glide
	# along the water edge" feel for diagonal input.
	var x_only_pos: Vector2 = current_pos + Vector2(delta_pos.x, 0.0)
	var x_only_tile: Vector2i = _world_pos_to_tile(x_only_pos)
	if grid_world.is_passable_at(x_only_tile) or x_only_tile == current_tile:
		global_position = x_only_pos
		return
	var y_only_pos: Vector2 = current_pos + Vector2(0.0, delta_pos.y)
	var y_only_tile: Vector2i = _world_pos_to_tile(y_only_pos)
	if grid_world.is_passable_at(y_only_tile) or y_only_tile == current_tile:
		global_position = y_only_pos
		return
	# Else: both axes lead into impassable terrain — fully blocked, no movement.

func _world_pos_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / float(GridWorld.TILE_SIZE))),
		int(floor(world_pos.y / float(GridWorld.TILE_SIZE))),
	)

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, BODY_COLOR)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, OUTLINE_COLOR, 1.5)
