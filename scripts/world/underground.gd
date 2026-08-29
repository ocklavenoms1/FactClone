class_name Underground
extends RefCounted

## Underground tunnels — TWO FAMILIES, one pairing predicate.
##
## BELT family (Belt Logistics Session 1, Task 5; design record:
## docs/scoping/belt-logistics-1.md — Q6, Q6b, Q7, Q8). The ENTRY owns
## everything that moves; the EXIT is passive. Everything below the pairing
## section describes this family and only this family.
##
## PIPE family (Belt Logistics Session 2, Piece 2). A paired underground pipe
## is ONE EDGE in the fluid connectivity graph and NOTHING ELSE: no lanes, no
## volume, no timing, no state but `dir`. There is no fluid flow simulation
## for any of those to belong to, so a tunnel carrying a latency constant
## would be inventing a number with no source — the opposite of the belt
## family's locked one-belt-tile lane, which is derivable from
## Belt.SLOTS_PER_TILE. The whole of the pipe family's behaviour is
## `make_pipe_half` below, its row in EXIT_TYPE_FOR_ENTRY, and the tunnel-link
## step in GridWorld._rebuild_fluid_network that reads that row through
## paired_exit. Fluid is UNDIRECTED: entry vs exit is a player-facing
## CONVENTION kept for glyph legibility and family consistency, not a
## constraint the fluid obeys — recorded so a future one-type simplification
## is a decision on the shelf rather than one re-derived from scratch.
##
## ─────────────────────────────────────────────────────────────────────────
## THE CONVENTION (single source for the pair's geometry under rotation)
## ─────────────────────────────────────────────────────────────────────────
## Both halves are 1×1 and carry `state["dir"]` — the FLOW direction, the
## same Belt.DIR_* enum a belt carries (canonical = DIR_E, as everywhere).
## For the ENTRY, dir is the direction the tunnel runs; its INPUT EDGE is
## its REAR — the cell edge opposite the flow. Items are accepted ONLY from
## a feeder sitting on that edge pushing along the flow — try_accept() is
## the single gate; side-feeds and head-on pushes are refused and the
## feeder's item stays where it is (the Q7 backpressure philosophy: visible
## jams, never quiet loss). For the EXIT, dir is where items resurface: the
## EMIT TARGET is the cell ONE STEP BEYOND the exit along dir — belts only
## for now (chest / splitter / machine consumers land there the same way
## belt.gd's own Pass 2 grows consumers: when a task ships them with
## coverage, not before). The #14 feeder guard applies at the emit: a belt
## on the target cell whose dir points back INTO the exit's cell is a
## feeder, not a sink, and is never delivered to.
##
## ─────────────────────────────────────────────────────────────────────────
## PAIRING — recomputed, never stored (Q6)
## ─────────────────────────────────────────────────────────────────────────
## paired_exit() is THE predicate; its docstring carries the two-caller
## contract. No partner field exists anywhere in state, so staleness cannot
## exist and re-pair after any place/remove is automatic by construction.
## UNDERGROUND_MAX_SPAN below is this module's OWN constant — documented-
## equal to the basic pole's POLE_RANGE_BY_TYPE row (both are 3) and pinned
## by the literal 3 in test_underground.gd (A7). DELIBERATELY not a shared
## constant and not compared across modules anywhere: coupling the power
## table to the belt module would let a pole rebalance silently rebalance
## tunnels (Q6b — the named silent-compensation shape; prose equalities
## drift, test literals redden).
##
## ─────────────────────────────────────────────────────────────────────────
## THE TUNNEL — slots, not teleport (Q8); the exit-cell discount, stated
## ─────────────────────────────────────────────────────────────────────────
## The entry owns a 4-slot surface lane (`state["slots"]`, its own tile —
## the splitter's one-belt-tile-equivalent arithmetic) and `state["tunnel"]`
## — gap × Belt.SLOTS_PER_TILE slots (gap = covered cells strictly between
## the pair, 1..UNDERGROUND_MAX_SPAN), organised as gap belt-tile SEGMENTS.
## Within a segment items shift exactly as a belt shifts; between segments
## (and between the lane and the tunnel) the front slot crosses in the same
## advance tick it fills — the transient-front arithmetic of a real
## belt-to-belt handoff. Crossing entry → belt-beyond-exit therefore costs
## exactly (gap+1) belt tiles of travel, and the whole trajectory is the
## surface EXPECTED_PATH shape — test_underground.gd (B) pins it against a
## six-belt surface twin on the same clock, against ONE shared literal.
##
## THE EXIT CELL COSTS NOTHING: the Pass-2 handoff from the tunnel front
## lands one step BEYOND the exit, so the exit contributes footprint, not
## lane — the splitter's locked latency shape exactly (2×1 footprint, ONE
## belt-tile lane). If the arc ever wants the exit cell to cost a tile, the
## tunnel grows one segment and (B)'s literal moves — say it out loud.
##
## Two-pass contract, same as Belt/Splitter: Pass 1 (`tick`) moves lane and
## tunnel SELF-ONLY; Pass 2 (`post_tick`) is the only place the entry
## touches a neighbour. The entry is FED in the feeder belt's own Pass 2
## (belt.gd's entry branch) — #17's never-feed-by-Pass-1-pull stands.
##
## ─────────────────────────────────────────────────────────────────────────
## UNPAIRED = FULL (Q7), and what destruction does
## ─────────────────────────────────────────────────────────────────────────
## An unpaired entry REFUSES INPUT — try_accept returns false, the upstream
## belt jams, and the pile-up is visible on the feeding belts as literal
## slot states. An accepting-but-inert entry would be the #19 infinite
## sink, disqualified by name in the record. While unpaired the entry is
## frozen whole (no shift, no delivery): items already in the lane or
## tunnel keep their places and resume when a matching exit lands.
## DESTROYING THE ENTRY DROPS THE LANE AND TUNNEL CONTENTS with it — the
## belt-slots precedent (a removed belt's slots vanish the same way).
## Destroying the EXIT strands nothing: all state lives on the entry.
##
## ─────────────────────────────────────────────────────────────────────────
## MID-TRANSIT RE-PAIR — truncate-by-delivery, never drop
## ─────────────────────────────────────────────────────────────────────────
## The tunnel's length re-syncs to the CURRENT pairing distance each
## advance tick (_sync_length):
##   - re-pair FARTHER: empty far slots are appended instantly (no item
##     moves) and every item walks the grown distance — no teleport.
##   - re-pair NEARER: the tunnel never shrinks past an undelivered item.
##     Trailing EMPTY slots beyond the new length pop freely; an in-flight
##     ITEM beyond the new length surfaces at the NEW exit — delivered from
##     the array's far end at belt rate (one per advance tick), its slot
##     popped on success. Items short of the new length keep travelling
##     normally; slots at/beyond it are collapsed ground and do not shift
##     while the drain lasts.
##
## State schema (flat, JSON-safe — Q10: no schema bump; both array fields
## are `.get()`-defaulted so a Task-2-era save carrying only {"dir"} loads):
##   ENTRY  dir: int           0=E, 1=S, 2=W, 3=N — the flow direction
##          slots: Array[int]  length Belt.SLOTS_PER_TILE, item type or -1
##          tunnel: Array[int] gap × Belt.SLOTS_PER_TILE, item type or -1;
##                             created on the first paired advance tick
##   EXIT   dir: int           where items resurface. Nothing else, ever.

## Maximum covered cells between entry and exit — the pairing scan looks
## 2 .. UNDERGROUND_MAX_SPAN+1 cells ahead of the entry. Module-own and
## pinned by a test literal on purpose; see the header (Q6b).
##
## BOTH FAMILIES SHARE THIS ONE CONSTANT, deliberately: a belt tunnel and a
## pipe tunnel reach the same distance, and a player who has learned one has
## learned the other. The consequence is that a belt-side rebalance rebalances
## every pipe tunnel in every save, which is exactly the silent-compensation
## shape Q6b named — so the literal 3 is pinned TWICE, once in
## test_underground.gd (A7, belts) and once in test_underground_pipe.gd (1,
## pipes). Two suites reddening is what makes a rebalance a deliberate
## two-file edit instead of a side effect.
const UNDERGROUND_MAX_SPAN: int = 3

## THE FAMILY TABLE — entry type → the ONE exit type it may pair with.
##
## This dictionary IS the belt/pipe distinction. It is written down rather
## than emergent: without it the two families would be kept apart only by the
## accident of never being placed next to each other, and the first player to
## run a pipe tunnel alongside a belt tunnel would find them pairing. A miss
## returns -1 from exit_type_for below, which means "not a tunnel entry of any
## family" — the answer for an EXIT, for a PIPE, and for everything else.
##
## A new tunnel family (a longer tier, a fluid-specific tunnel) is one row
## here and nothing else in this file.
const EXIT_TYPE_FOR_ENTRY: Dictionary = {
	Buildings.Type.UNDERGROUND_BELT_ENTRY: Buildings.Type.UNDERGROUND_BELT_EXIT,
	Buildings.Type.UNDERGROUND_PIPE_ENTRY: Buildings.Type.UNDERGROUND_PIPE_EXIT,
}

## The exit type `entry_type` may pair with, or -1 if it is not a tunnel entry.
static func exit_type_for(entry_type: int) -> int:
	return int(EXIT_TYPE_FOR_ENTRY.get(entry_type, -1))

static func make_entry(pos: Vector2i, dir: int = Belt.DIR_E) -> Building:
	var slots: Array = []
	for i in Belt.SLOTS_PER_TILE:
		slots.append(-1)
	return Building.new(Buildings.Type.UNDERGROUND_BELT_ENTRY, pos, {
		"dir": dir,
		"slots": slots,
	})

static func make_exit(pos: Vector2i, dir: int = Belt.DIR_E) -> Building:
	return Building.new(Buildings.Type.UNDERGROUND_BELT_EXIT, pos, {
		"dir": dir,
	})

## BOTH pipe halves, from one constructor, because they ARE the same building:
## `dir` and nothing else. The belt pair needs two constructors because the
## entry carries a lane and a tunnel array and the exit carries neither; the
## pipe pair carries nothing on either side, so two functions would be two
## copies of one line. `t` is the caller's enum value (Buildings.make passes
## it straight through), and it is what the ramp glyph and the family table
## read to tell the halves apart.
##
## `dir` reuses the Belt.DIR_* enum — the same four-direction vocabulary every
## rotatable building in the registry speaks (Buildings.dir_of reads it). For
## the pipe family it fixes the pairing scan's AXIS, not a flow direction:
## fluid crosses a paired tunnel in whichever direction the network demands.
static func make_pipe_half(pos: Vector2i, dir: int, t: int) -> Building:
	return Building.new(t, pos, {
		"dir": dir,
	})

# ---------- pairing (the Q6 decision, in code) ----------

## THE pairing predicate — the `poles_connected` of this arc — for BOTH
## families, belt and pipe.
##
## CONTRACT: this function is the ONLY answer to "which exit does this
## entry feed?". Every caller — try_accept's refuse-when-unpaired gate,
## both tick passes, info_lines, the renderer's dedicated indicator
## pass (GridWorld._draw_underground_pair_indicators, Task 6's dashed
## tunnel indicator), and the fluid resolver's tunnel-link step
## (GridWorld._rebuild_fluid_network, Session 2 Piece 2) — must call THIS,
## never re-derive the scan from a distance check. Two derivations drift, and
## the divergence is invisible until a tunnel draws where no items flow, or
## joins a fluid network no player can see joined — the same failure
## poles_connected and wasteland_accepts_tier exist to prevent. Recomputed
## on demand, never stored (Q6): there is no partner field to go stale.
##
## ONE FUNCTION, BOTH FAMILIES, THE DISTINCTION EXPLICIT. The exit type this
## scan will accept comes from EXIT_TYPE_FOR_ENTRY — the entry's OWN row —
## and never from "does this look like an exit". A belt entry therefore
## cannot pair with a pipe exit at any distance or facing, and vice versa,
## because the refusal is a table lookup rather than a consequence of the two
## families never meeting on a map. An entry type with no row (and any EXIT,
## and any other building) returns null immediately.
##
## The scan: walk k = 2 .. UNDERGROUND_MAX_SPAN+1 cells from the entry's
## anchor along the ENTRY'S OWN dir; the NEAREST exit of the entry's paired
## type whose dir EQUALS the entry's dir wins. Anything else — an exit facing
## another way, an exit of the other family, another entry, any other
## building, empty ground — is SKIPPED, not a blocker (the tunnel passes under
## the surface). k starts at 2, so a pair always covers at least one cell and
## the tunnel is never zero-length.
static func paired_exit(entry: Building, world: Node2D) -> Building:
	var want: int = exit_type_for(entry.type)
	if want < 0:
		return null
	var d: int = Buildings.dir_of(entry)
	var step: Vector2i = Belt.DIR_VECS[d]
	for k in range(2, UNDERGROUND_MAX_SPAN + 2):
		var candidate: Building = world.building_at(entry.anchor + step * k)
		if candidate == null:
			continue
		if candidate.type != want:
			continue
		if Buildings.dir_of(candidate) != d:
			continue
		return candidate
	return null

## Covered cells strictly between the pair: anchors k cells apart → k − 1.
static func gap_between(entry: Building, exit: Building) -> int:
	var delta: Vector2i = exit.anchor - entry.anchor
	return absi(delta.x + delta.y) - 1

# ---------- input (called from the feeder belt's Pass 2 entry branch) ----------

## The single acceptance gate. `feeder_anchor`/`feeder_dir` describe the
## pushing belt: it must sit on the INPUT EDGE (the entry's rear, so its
## push lands on the entry's cell) and push ALONG the flow — and the entry
## must be PAIRED (Q7: an unpaired entry acts full; accepting while
## unpaired is the #19 sink). Everything else is refused and the feeder's
## item stays where it is. The position clause is unreachable from belt.gd
## today (a dir-matched belt pushing into a 1×1 entry IS on its rear edge);
## it stays as the defensive mirror of the splitter's multi-cell gate for
## any future non-belt caller.
static func try_accept(b: Building, item_type: int, feeder_anchor: Vector2i, feeder_dir: int, world: Node2D) -> bool:
	var d: int = Buildings.dir_of(b)
	if feeder_dir != d:
		return false
	if feeder_anchor + Belt.DIR_VECS[d] != b.anchor:
		return false
	if paired_exit(b, world) == null:
		return false
	var lane: Array = _lane(b)
	if int(lane[0]) >= 0:
		return false
	lane[0] = item_type
	return true

# ---------- two-pass tick ----------

## Pass 1 — SELF-ONLY movement, on advance ticks, only while paired (an
## unpaired entry is frozen whole — Q7). Inside one advance tick: sync the
## tunnel's length, shift the lane and every in-length tunnel segment (the
## belt Pass-1 analogue), then cross the internal boundaries front → next
## back (the belt Pass-2 analogue, internal to this one building) — so
## boundary front slots are transient exactly as at a real handoff, and
## the trajectory literal is the surface shape.
static func tick(b: Building, world: Node2D) -> void:
	if not Belt.is_advance_tick():
		return
	var exit: Building = paired_exit(b, world)
	if exit == null:
		return
	var target_len: int = gap_between(b, exit) * Belt.SLOTS_PER_TILE
	var lane: Array = _lane(b)
	var tunnel: Array = _tunnel(b)
	_sync_length(tunnel, target_len)
	# Slots at/beyond target_len are collapsed ground mid-drain (nearer
	# re-pair): frozen here, drained from the far end by post_tick.
	var seg_count: int = mini(tunnel.size(), target_len) / Belt.SLOTS_PER_TILE
	_shift_segment(lane, 0)
	for s in seg_count:
		_shift_segment(tunnel, s * Belt.SLOTS_PER_TILE)
	# Boundary crossings. Each reads one segment's front and writes the
	# NEXT segment's back — all slot pairs disjoint, so their order is
	# immaterial (the same property that makes belt Pass 2 order-free).
	if seg_count > 0 and int(lane[Belt.SLOTS_PER_TILE - 1]) >= 0 and int(tunnel[0]) < 0:
		tunnel[0] = lane[Belt.SLOTS_PER_TILE - 1]
		lane[Belt.SLOTS_PER_TILE - 1] = -1
	for s in range(seg_count - 1):
		var front: int = s * Belt.SLOTS_PER_TILE + (Belt.SLOTS_PER_TILE - 1)
		var back: int = (s + 1) * Belt.SLOTS_PER_TILE
		if int(tunnel[front]) >= 0 and int(tunnel[back]) < 0:
			tunnel[back] = tunnel[front]
			tunnel[front] = -1

## Pass 2 — the only place the entry touches a neighbour: recompute the
## pairing, hand the tunnel's far end into the belt one step BEYOND the
## exit (#14 guard in _try_deliver). While the tunnel is oversized after a
## nearer re-pair, the far end IS the stranded region, so truncate-by-
## delivery falls out of the same single delivery site: deliver, then pop
## the slot instead of clearing it.
static func post_tick(b: Building, world: Node2D) -> void:
	if not Belt.is_advance_tick():
		return
	var exit: Building = paired_exit(b, world)
	if exit == null:
		return
	var target_len: int = gap_between(b, exit) * Belt.SLOTS_PER_TILE
	var tunnel: Array = _tunnel(b)
	_sync_length(tunnel, target_len)
	if tunnel.is_empty():
		return
	var last: int = tunnel.size() - 1
	var item_type: int = int(tunnel[last])
	if item_type < 0:
		return
	if not _try_deliver(world, exit.anchor + Belt.DIR_VECS[Buildings.dir_of(b)], exit, item_type):
		return
	if tunnel.size() > target_len:
		tunnel.remove_at(last)   # truncate-by-delivery: the slot leaves with its item
	else:
		tunnel[last] = -1

## Push one item into the building at `cell`. Belts only for now (see the
## header). The #14 feeder guard lives here: a belt pointing back into the
## exit's cell is an input to the surface line, not a sink.
static func _try_deliver(world: Node2D, cell: Vector2i, exit: Building, item_type: int) -> bool:
	if not world.has_building_at(cell):
		return false
	var neighbor: Building = world.building_at(cell)
	if neighbor == null or neighbor.type != Buildings.Type.BELT:
		return false
	if _belt_feeds_exit(neighbor, exit):
		return false      # #14: a belt pointing into the exit is a feeder, not a sink
	return Belt.try_insert(neighbor, item_type)

## Mirror of processor.gd's _belt_feeds_building for the 1×1 exit: does this
## belt's push land on the exit's cell?
static func _belt_feeds_exit(belt: Building, exit: Building) -> bool:
	var d: int = int(belt.state.get("dir", 0))
	return belt.anchor + Belt.DIR_VECS[d] == exit.anchor

# ---------- state access ----------

## The surface lane, `.get()`-defaulted (Q10): a Task-2-era save carries
## only {"dir"} — grow it lazily and store it so it round-trips thereafter.
static func _lane(b: Building) -> Array:
	if not b.state.has("slots"):
		var slots: Array = []
		for i in Belt.SLOTS_PER_TILE:
			slots.append(-1)
		b.state["slots"] = slots
	return b.state["slots"]

## The tunnel, `.get()`-defaulted the same way. Created empty; _sync_length
## sizes it to the live pairing distance on each paired advance tick.
static func _tunnel(b: Building) -> Array:
	if not b.state.has("tunnel"):
		b.state["tunnel"] = []
	return b.state["tunnel"]

## Re-sync the tunnel array to the current pairing distance. Growing
## appends EMPTY far slots (instant — no item moves, and items must then
## walk the added distance). Shrinking pops trailing EMPTY slots only —
## an item beyond the target keeps its slot until post_tick delivers it
## (truncate-by-delivery, never drop).
static func _sync_length(tunnel: Array, target_len: int) -> void:
	while tunnel.size() < target_len:
		tunnel.append(-1)
	while tunnel.size() > target_len and int(tunnel[tunnel.size() - 1]) < 0:
		tunnel.remove_at(tunnel.size() - 1)

## One belt tile's worth of Pass-1 shift over arr[base .. base+3]: the
## front-most empty slot fills from behind — identical mechanism to
## Belt.tick, applied per segment.
static func _shift_segment(arr: Array, base: int) -> void:
	for i in range(Belt.SLOTS_PER_TILE - 1, 0, -1):
		if int(arr[base + i]) < 0 and int(arr[base + i - 1]) >= 0:
			arr[base + i] = arr[base + i - 1]
			arr[base + i - 1] = -1

# ---------- info ----------

static func info_lines(b: Building, world = null) -> Array:
	if is_pipe_half(b.type):
		return _pipe_info_lines(b, world)
	if b.type == Buildings.Type.UNDERGROUND_BELT_EXIT:
		return [
			"Flow: %s" % Belt.DIR_NAMES[Buildings.dir_of(b)],
			"Passive — items and tunnel state live on the paired entry.",
		]
	var lane_occupied: int = 0
	for s in _lane(b):
		if int(s) >= 0:
			lane_occupied += 1
	var tunnel: Array = b.state.get("tunnel", [])
	var tunnel_occupied: int = 0
	for s in tunnel:
		if int(s) >= 0:
			tunnel_occupied += 1
	var lines: Array = [
		"Flow: %s" % Belt.DIR_NAMES[Buildings.dir_of(b)],
		"Lane: %d / %d" % [lane_occupied, Belt.SLOTS_PER_TILE],
		"Tunnel: %d / %d" % [tunnel_occupied, tunnel.size()],
	]
	if world != null:
		var exit: Building = paired_exit(b, world)
		if exit != null:
			lines.append("Paired exit: %s" % str(exit.anchor))
		else:
			lines.append("UNPAIRED — refusing input (upstream will jam)")
	return lines

## Is `t` one of the PIPE family's two halves? The one place that question is
## asked, so the two enum values never get spelled out at a call site.
static func is_pipe_half(t: int) -> bool:
	return t == Buildings.Type.UNDERGROUND_PIPE_ENTRY or t == Buildings.Type.UNDERGROUND_PIPE_EXIT

## The pipe family's panel. It reports three things, and deliberately not a
## fourth: the facing (with its convention caveat spelled out, because a
## player who sees a direction on a fluid building will assume it constrains
## flow), the PAIRING — through the same paired_exit every other caller uses,
## so the panel can never claim an edge the resolver did not build — and the
## live connectivity of the half's own cell. There is no throughput line, no
## contents line and no fill line, because a pipe tunnel carries nothing.
static func _pipe_info_lines(b: Building, world) -> Array:
	var lines: Array = [
		"Facing: %s (pairing axis — fluid itself is undirected)" % Belt.DIR_NAMES[Buildings.dir_of(b)],
		"Carries nothing: one edge in the fluid network.",
	]
	if world == null:
		return lines
	if b.type == Buildings.Type.UNDERGROUND_PIPE_ENTRY:
		var exit: Building = paired_exit(b, world)
		if exit != null:
			lines.append("Paired exit: %s" % str(exit.anchor))
		else:
			lines.append("UNPAIRED — the network is cut here")
	else:
		lines.append("Passive half — the entry owns the pairing scan.")
	lines.append("Fluid: %s" % ("pump reachable" if world.is_pipe_in_pump_component(b.anchor) else "no pump in this network"))
	return lines

# ---------- visual ----------

## Task 6. Entry vs exit must be DISTINGUISHABLE at a glance (a named
## PAUSE-gate item): both are belt-dark plates speaking the belt chevron
## language, but the ENTRY is a ramp INTO the ground — chevrons running
## toward a dark tunnel mouth on its FRONT edge, ramp walls converging into
## it — and the EXIT the mirrored ramp OUT: the mouth on its REAR edge, ramp
## walls spreading from it toward where items resurface. All geometry is
## built on the flow axis from Buildings.dir_of, so both glyphs stay
## direction-readable under rotation, and the bright chevron sits nearest
## where items are headed (into the mouth on the entry, off the emit edge on
## the exit — the belt's own bright-front convention). Draws strictly inside
## the 1x1 footprint; the dashed pair-indicator between the halves is
## grid_world's DEDICATED pass, never drawn here (the z-order finding).
##
## SESSION 2 PIECE 2 — the same glyph, the other family's palette. The pipe
## halves reuse every line of geometry below (a ramp into the ground is a ramp
## into the ground) and swap the belt's trim/chevron colours for the pipe's
## tube colours, INCLUDING Pipe's live-vs-dry distinction: a tunnel mouth in a
## pump-bearing network reads bright exactly as the pipe beside it does, and a
## dry one reads muted. `canvas` IS the GridWorld (grid_world._draw passes
## self), the same duck-typed connectivity query Pipe.draw already makes.
static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var ts: float = float(tile_size)
	var rect: Rect2 = Rect2(world_pos, Vector2(ts, ts))
	# The entry half of EITHER family is the one with a row in the family
	# table; that is the same question the pairing scan asks, so the glyph and
	# the predicate can never disagree about which end is which.
	var is_entry: bool = EXIT_TYPE_FOR_ENTRY.has(b.type)
	var trim: Color = Belt.TRIM_COLOR
	var mark: Color = Belt.ARROW_COLOR
	var mark_bright: Color = Belt.ARROW_BRIGHT
	if is_pipe_half(b.type):
		var live: bool = canvas.is_pipe_in_pump_component(b.anchor)
		trim = Pipe.TUBE_OUTLINE
		mark = Pipe.TUBE_PUMP if live else Pipe.TUBE_DRY
		mark_bright = Pipe.HUB_PUMP if live else Pipe.HUB_DRY
	canvas.draw_rect(rect, Buildings.DATA[b.type]["swatch_color"], true)
	canvas.draw_rect(rect, trim, false, 1.5)

	var d: int = Buildings.dir_of(b)
	if is_entry:
		# Mouth on the front edge; ramp walls converge into it; chevrons
		# walk the rear half toward it, bright last.
		canvas.draw_colored_polygon(_axis_quad(world_pos, ts, d, 0.66, 1.00, 0.10, 0.90), trim)
		canvas.draw_line(_axis_point(world_pos, ts, d, 0.06, 0.10), _axis_point(world_pos, ts, d, 0.66, 0.24), mark, 1.5)
		canvas.draw_line(_axis_point(world_pos, ts, d, 0.06, 0.90), _axis_point(world_pos, ts, d, 0.66, 0.76), mark, 1.5)
		_draw_chevron(canvas, _axis_point(world_pos, ts, d, 0.16, 0.5), d, ts, mark)
		_draw_chevron(canvas, _axis_point(world_pos, ts, d, 0.44, 0.5), d, ts, mark_bright)
	else:
		# Mirrored: mouth on the rear edge; ramp walls spread out of it;
		# chevrons walk the front half away from it, bright at the emit edge.
		canvas.draw_colored_polygon(_axis_quad(world_pos, ts, d, 0.00, 0.34, 0.10, 0.90), trim)
		canvas.draw_line(_axis_point(world_pos, ts, d, 0.34, 0.24), _axis_point(world_pos, ts, d, 0.94, 0.10), mark, 1.5)
		canvas.draw_line(_axis_point(world_pos, ts, d, 0.34, 0.76), _axis_point(world_pos, ts, d, 0.94, 0.90), mark, 1.5)
		_draw_chevron(canvas, _axis_point(world_pos, ts, d, 0.56, 0.5), d, ts, mark)
		_draw_chevron(canvas, _axis_point(world_pos, ts, d, 0.84, 0.5), d, ts, mark_bright)

## Map flow-axis coordinates into world pixels inside this 1x1 tile:
## t_along runs 0 (rear edge, where the feeder pushes in) to 1 (front edge,
## the tunnel direction) along dir; t_across runs 0..1 across it.
static func _axis_point(world_pos: Vector2, ts: float, d: int, t_along: float, t_across: float) -> Vector2:
	var along: Vector2 = Vector2(Belt.DIR_VECS[d])
	var across: Vector2 = Vector2(-along.y, along.x)
	var centre: Vector2 = world_pos + Vector2(ts, ts) * 0.5
	return centre + along * ((t_along - 0.5) * ts) + across * ((t_across - 0.5) * ts)

## An axis-aligned (in flow coordinates) quad, as polygon points.
static func _axis_quad(world_pos: Vector2, ts: float, d: int, a0: float, a1: float, c0: float, c1: float) -> PackedVector2Array:
	return PackedVector2Array([
		_axis_point(world_pos, ts, d, a0, c0),
		_axis_point(world_pos, ts, d, a1, c0),
		_axis_point(world_pos, ts, d, a1, c1),
		_axis_point(world_pos, ts, d, a0, c1),
	])

## One belt-language chevron: tip along `d`, wings across.
static func _draw_chevron(canvas: CanvasItem, centre: Vector2, d: int, ts: float, color: Color) -> void:
	var along: Vector2 = Vector2(Belt.DIR_VECS[d])
	var across: Vector2 = Vector2(-along.y, along.x)
	var size: float = ts * 0.16
	var tip: Vector2 = centre + along * size
	canvas.draw_line(centre + across * size, tip, color, 1.5)
	canvas.draw_line(centre - across * size, tip, color, 1.5)
