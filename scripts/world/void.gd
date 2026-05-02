class_name Void
extends RefCounted

## Void — destroys any items dropped on it. Used as a "no-sink-yet" cap for
## byproducts the player doesn't have a downstream use for (e.g. fuel
## briquettes before an Oven exists, straw before a Briquetter exists).
##
## Pulls from adjacent belts (any item type), and accepts direct pushes
## from upstream Processors and Harvesters. Has no capacity limit and
## never blocks — by design, it's a release valve.
##
## Tracks `destroyed` count for diagnostics; useful in info panel to
## confirm the Void is doing its job.

# Visual
const BG_COLOR: Color = Color(0.06, 0.04, 0.10)
const FRAME_COLOR: Color = Color(0.22, 0.18, 0.30)
const PIT_DEEP: Color = Color(0.0, 0.0, 0.0)
const PIT_RIM: Color = Color(0.30, 0.20, 0.40)
const SPIRAL_COLOR: Color = Color(0.55, 0.40, 0.70)
const SPARK_COLOR: Color = Color(0.85, 0.65, 0.95)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.VOID, pos, { "destroyed": 0 })

static func tick(b: Building, world: Node2D) -> void:
	# Pull one item per tick from any adjacent belt — accept anything.
	for dir in 4:
		var npos: Vector2i = b.anchor + Belt.DIR_VECS[dir]
		if not world.has_building_at(npos):
			continue
		var neighbor: Building = world.building_at(npos)
		if neighbor == null or neighbor.type != Buildings.Type.BELT:
			continue
		var pulled: int = Belt.try_pull_matching(neighbor, b.anchor, [])
		if pulled >= 0:
			b.state["destroyed"] = int(b.state.get("destroyed", 0)) + 1
			return

## Direct-insert API used by upstream Processors / Harvesters that push
## outputs to adjacent buildings. Always accepts; item is destroyed
## immediately. Never blocks the upstream machine.
static func try_insert(b: Building, _item_type: int, count: int = 1) -> bool:
	b.state["destroyed"] = int(b.state.get("destroyed", 0)) + count
	return true

static func info_lines(b: Building) -> Array:
	return [
		"Void — destroys items dropped on it.",
		"Items destroyed: %d" % int(b.state.get("destroyed", 0)),
		"Never blocks. Use as a sink for unwanted byproducts.",
	]

# ---------- visual ----------

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(rect, BG_COLOR, true)
	canvas.draw_rect(rect, FRAME_COLOR, false, 2.0)

	# Black pit with a slowly rotating spiral inside.
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var pit_radius: float = float(tile_size) * 0.36
	canvas.draw_circle(center, pit_radius, PIT_DEEP)
	canvas.draw_arc(center, pit_radius, 0.0, TAU, 32, PIT_RIM, 1.5)

	# Spiral arms — 3 rotating dots at decreasing radii.
	var t: float = float(TickSystem.current_tick) * 0.08
	for i in 3:
		var arm_angle: float = t + float(i) * (TAU / 3.0)
		var arm_radius: float = pit_radius * (0.75 - 0.18 * float(i))
		var p: Vector2 = center + Vector2(cos(arm_angle), sin(arm_angle)) * arm_radius
		canvas.draw_circle(p, 2.0 - 0.4 * float(i), SPIRAL_COLOR)

	# Spark every few ticks to convey "it's eating something".
	if int(b.state.get("destroyed", 0)) > 0 and TickSystem.current_tick % 10 == 0:
		canvas.draw_circle(center, 1.5, SPARK_COLOR)
