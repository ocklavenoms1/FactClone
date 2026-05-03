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

func _physics_process(_delta: float) -> void:
	var modal_open: bool = (inventory_grid != null and inventory_grid.is_open()) \
		or (map_panel != null and map_panel.is_open())
	if modal_open:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var input_vec: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	velocity = input_vec * SPEED
	move_and_slide()

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, BODY_COLOR)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, OUTLINE_COLOR, 1.5)
