class_name Splitter
extends RefCounted

## Splitter — belt-family 2×1 that merges one input stream and deals it out
## round-robin over two branches. Belt Logistics Session 1, Task 3; design
## record: docs/scoping/belt-logistics-1.md.
##
## ─────────────────────────────────────────────────────────────────────────
## THE CONVENTION (single source for input/output geometry under rotation)
## ─────────────────────────────────────────────────────────────────────────
## `state["dir"]` is the FLOW direction, the same Belt.DIR_* enum a belt
## carries — a splitter placed with the same dir as the belts around it
## moves items the same way they do. Ports are declared here in CANONICAL
## orientation (dir = DIR_E = 0, the same convention world_dir and the
## recipes use) and rotate in lockstep with dir:
##
##   Canonical (dir = E, footprint (2, 1); Task 1's convention at
##   Buildings.footprint_for — anchor is the top-left of the ROTATED rect):
##
##        input          [REAR]  [FRONT]  → LEFT branch (N of front)
##        edge (W) ────►  anchor  +(1,0)  → RIGHT branch (S of front)
##
##   - REAR / INPUT cell: the cell the flow enters. It is the anchor for
##     E/S flows and the far cell for W/N flows (the anchor is a rect
##     corner, not a flow-relative point — see rear_cell()).
##   - INPUT EDGE: the rear cell's edge OPPOSITE the flow (W at canonical).
##     Items are accepted ONLY from a feeder sitting on that edge and
##     pushing along the flow — try_accept() is the single gate. A belt
##     side-feeding the rear cell, or pushing into the front or side cells,
##     is refused and jams visibly (the Q7 backpressure philosophy; an
##     accepting non-edge would be quiet over-acceptance).
##   - OUTPUT BRANCHES: the FRONT cell's two side edges. LEFT of flow
##     (out 0) is (dir + 3) % 4, RIGHT (out 1) is (dir + 1) % 4 — N and S
##     at canonical, in Godot's Y-down CW direction order E→S→W→N.
##
## ─────────────────────────────────────────────────────────────────────────
## THE LANE — latency is LOCKED (user, 2026-08-26)
## ─────────────────────────────────────────────────────────────────────────
## One belt-tile-equivalent internal lane: `state["slots"]`, length
## Belt.SLOTS_PER_TILE, advancing only on Belt.is_advance_tick(). Crossing a
## splitter costs exactly one belt tile of travel time, so
## belt → splitter → belt walks the SAME resting positions as three belts
## (test_belt.gd's measured 0,1,2,4,5,6,8,9,10,11 — front slots transient
## at handoffs). Zero latency would be the first exception to a timing
## model where everything on the belt clock takes time proportional to
## distance — exceptions are where throughput bugs hide. test_splitter.gd
## case (B) pins this with the same literal path.
##
## Two-pass contract, same as Belt: Pass 1 (`tick`, from Buildings.tick_one)
## shifts the lane SELF-ONLY; Pass 2 (`post_tick`, from post_tick_one) is
## the only place a splitter touches a neighbour. The splitter has NO
## Pass-1 belt interaction — feeding it by Pass-1 pull was refused at
## design time (#17 is live and this module does not widen it).
##
## ─────────────────────────────────────────────────────────────────────────
## ROUND-ROBIN POLICY (the Q3 decision, stated once)
## ─────────────────────────────────────────────────────────────────────────
## `state["next_out"]` (0 = LEFT, 1 = RIGHT, `.get()`-defaulted to 0,
## int()-read) is the branch tried FIRST. It FLIPS on every successful
## delivery, whichever branch accepted; a refusal leaves it unchanged.
## All-to-open-side falls out of that rule with zero extra state: when the
## preferred branch refuses, the same pass tries the other, and the flip
## still happens on the delivery. next_out RESUMES across save/load (Q2 —
## `current_tick` round-trips, so a reset would be the only tick-relevant
## state that forgets).
##
## Delivery targets are BELTS only for now, guarded by the #14 rule
## (mirroring processor.gd's _belt_feeds_building): a belt whose dir points
## into this splitter's footprint is a FEEDER, not a sink, and is never
## delivered to. Chest / downstream-splitter consumers land here the same
## way belt.gd's own Pass 2 grows consumers — when a task ships them with
## coverage, not before.
##
## State schema (flat, JSON-safe — Q10: no schema bump):
##   dir: int           0=E, 1=S, 2=W, 3=N — the flow direction
##   slots: Array[int]  length Belt.SLOTS_PER_TILE, item type or -1
##   next_out: int      0=LEFT, 1=RIGHT — branch tried first, resumes

static func make(pos: Vector2i, dir: int = Belt.DIR_E) -> Building:
	var slots: Array = []
	for i in Belt.SLOTS_PER_TILE:
		slots.append(-1)
	return Building.new(Buildings.Type.SPLITTER, pos, {
		"dir": dir,
		"slots": slots,
		"next_out": 0,
	})

# ---------- geometry (the convention above, in code) ----------

## The REAR (input) cell of the rotated rect. The anchor is the top-left
## corner of the rect (Task 1's convention), which is the flow-rear for E/S
## and the flow-front for W/N — hence the two offset cases.
static func rear_cell(b: Building) -> Vector2i:
	match Buildings.dir_of(b):
		Belt.DIR_W:
			return b.anchor + Vector2i(1, 0)
		Belt.DIR_N:
			return b.anchor + Vector2i(0, 1)
	return b.anchor

## The FRONT (output) cell: one step along the flow from the rear cell.
static func front_cell(b: Building) -> Vector2i:
	return rear_cell(b) + Belt.DIR_VECS[Buildings.dir_of(b)]

## World direction of branch `out_idx` (0 = LEFT of flow, 1 = RIGHT).
static func out_dir(b: Building, out_idx: int) -> int:
	return (Buildings.dir_of(b) + (3 if out_idx == 0 else 1)) % 4

## The cell branch `out_idx` delivers into: off the FRONT cell's side edge.
static func branch_cell(b: Building, out_idx: int) -> Vector2i:
	return front_cell(b) + Belt.DIR_VECS[out_dir(b, out_idx)]

# ---------- input (called from Belt.post_tick's splitter branch) ----------

## The single acceptance gate. `feeder_anchor`/`feeder_dir` describe the
## pushing belt: it must sit on the INPUT EDGE (so its push lands on the
## rear cell) and push ALONG the flow. Everything else — side-feeds into
## the rear cell, head-on pushes into the front cell — is refused, and the
## feeder's item stays where it is: visible backpressure, not quiet loss.
## Returns true if the item was taken into the lane's back slot.
static func try_accept(b: Building, item_type: int, feeder_anchor: Vector2i, feeder_dir: int) -> bool:
	var d: int = Buildings.dir_of(b)
	if feeder_dir != d:
		return false
	if feeder_anchor + Belt.DIR_VECS[d] != rear_cell(b):
		return false
	var slots: Array = _lane(b)
	if int(slots[0]) >= 0:
		return false
	slots[0] = item_type
	return true

# ---------- two-pass tick ----------

## Pass 1 — shift the lane forward, SELF ONLY, on advance ticks. Identical
## mechanism to Belt.tick: front-most empty slot fills from behind.
static func tick(b: Building, _world: Node2D) -> void:
	if not Belt.is_advance_tick():
		return
	var slots: Array = _lane(b)
	for i in range(Belt.SLOTS_PER_TILE - 1, 0, -1):
		if int(slots[i]) < 0 and int(slots[i - 1]) >= 0:
			slots[i] = slots[i - 1]
			slots[i - 1] = -1

## Pass 2 — deal the lane's front item to a branch. Tries the preferred
## branch (next_out), then the other; flips next_out only when a delivery
## actually happened (the policy in the header).
static func post_tick(b: Building, world: Node2D) -> void:
	if not Belt.is_advance_tick():
		return
	var slots: Array = _lane(b)
	var front_idx: int = Belt.SLOTS_PER_TILE - 1
	var item_type: int = int(slots[front_idx])
	if item_type < 0:
		return
	var preferred: int = int(b.state.get("next_out", 0))
	for attempt in 2:
		var out_idx: int = (preferred + attempt) % 2
		if _try_deliver(b, world, branch_cell(b, out_idx), item_type):
			slots[front_idx] = -1
			# Toggle ONLY on successful delivery — refusals never touch it.
			b.state["next_out"] = 1 - preferred
			return

## Push one item into the building at `cell`. Belts only for now (see
## header). The #14 feeder guard lives here: a belt pointing into this
## splitter's footprint is an input, not a sink.
static func _try_deliver(b: Building, world: Node2D, cell: Vector2i, item_type: int) -> bool:
	if not world.has_building_at(cell):
		return false
	var neighbor: Building = world.building_at(cell)
	if neighbor == null or neighbor.type != Buildings.Type.BELT:
		return false
	if _belt_feeds_splitter(neighbor, b):
		return false      # #14: a belt pointing into us is an input, not a sink
	return Belt.try_insert(neighbor, item_type)

## Mirror of processor.gd's _belt_feeds_building, on the splitter's ROTATED
## footprint (Task 1's footprint_contains / dir_of forms).
static func _belt_feeds_splitter(belt: Building, b: Building) -> bool:
	var d: int = int(belt.state.get("dir", 0))
	return Buildings.footprint_contains(b.type, b.anchor, belt.anchor + Belt.DIR_VECS[d], Buildings.dir_of(b))

# ---------- state access ----------

## The lane, `.get()`-defaulted (Q10): a Task-1-era save carries only
## {"dir"} — grow the lane lazily and store it so it round-trips thereafter.
static func _lane(b: Building) -> Array:
	if not b.state.has("slots"):
		var slots: Array = []
		for i in Belt.SLOTS_PER_TILE:
			slots.append(-1)
		b.state["slots"] = slots
	return b.state["slots"]

static func info_lines(b: Building) -> Array:
	var occupied: int = 0
	for s in _lane(b):
		if int(s) >= 0:
			occupied += 1
	return [
		"Flow: %s" % Belt.DIR_NAMES[Buildings.dir_of(b)],
		"Lane: %d / %d" % [occupied, Belt.SLOTS_PER_TILE],
		"Next branch: %s" % ("LEFT" if int(b.state.get("next_out", 0)) == 0 else "RIGHT"),
	]

# ---------- visual ----------

## Task 6. Brass plate over the ROTATED footprint, with the belt chevron
## language marking the three ports of the T: grey chevrons entering through
## the INPUT EDGE on the rear cell (pointing along the flow, into the body)
## and one BRIGHT chevron leaving through each OUTPUT EDGE on the front cell
## (the belt's own front-chevron colour, pointing out of the body — bright is
## where items go, exactly as on a belt). Every position comes from the port
## accessors above, so the glyphs rotate with dir and CANNOT disagree with
## where try_accept and post_tick actually move items. Draws strictly inside
## the footprint — the only sanctioned cross-tile drawing in this arc is
## grid_world's dedicated pair-indicator pass (the z-order finding).
static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var fp: Vector2i = Buildings.footprint_of_building(b)
	var rect: Rect2 = Rect2(world_pos, Vector2(tile_size * fp.x, tile_size * fp.y))
	canvas.draw_rect(rect, Buildings.DATA[Buildings.Type.SPLITTER]["swatch_color"], true)
	canvas.draw_rect(rect, Belt.TRIM_COLOR, false, 1.5)

	var d: int = Buildings.dir_of(b)
	var ts: float = float(tile_size)
	var rear_centre: Vector2 = world_pos + (Vector2(rear_cell(b) - b.anchor) + Vector2(0.5, 0.5)) * ts
	var front_centre: Vector2 = world_pos + (Vector2(front_cell(b) - b.anchor) + Vector2(0.5, 0.5)) * ts
	# INPUT: two grey chevrons walking in from the input edge along the flow.
	_draw_chevron(canvas, rear_centre - _dirv(d) * ts * 0.30, d, ts, Belt.ARROW_COLOR)
	_draw_chevron(canvas, rear_centre, d, ts, Belt.ARROW_COLOR)
	# OUTPUTS: one bright chevron just inside each branch edge, pointing out.
	for out_idx in 2:
		var od: int = out_dir(b, out_idx)
		_draw_chevron(canvas, front_centre + _dirv(od) * ts * 0.30, od, ts, Belt.ARROW_BRIGHT)

static func _dirv(d: int) -> Vector2:
	return Vector2(Belt.DIR_VECS[d])

## One belt-language chevron: tip along `d`, wings across.
static func _draw_chevron(canvas: CanvasItem, centre: Vector2, d: int, tile_size: float, color: Color) -> void:
	var along: Vector2 = _dirv(d)
	var across: Vector2 = Vector2(-along.y, along.x)
	var size: float = tile_size * 0.18
	var tip: Vector2 = centre + along * size
	canvas.draw_line(centre + across * size, tip, color, 1.5)
	canvas.draw_line(centre - across * size, tip, color, 1.5)
