extends RefCounted

## Underground PIPE tunnel — Belt Logistics Session 2, Piece 2.
##
## WHAT AN UNDERGROUND PIPE IS. One EDGE in the fluid connectivity graph and
## nothing else. No lanes, no volume, no timing, no state beyond `dir` —
## there is no fluid FLOW simulation to have latency in, so a tunnel that
## carried a delay constant would be inventing a number with no source. A
## paired entry/exit joins its two ends into one component; an unpaired half
## is an ordinary fitting that happens to connect to whatever pipes touch it.
##
## ─────────────────────────────────────────────────────────────────────────
## THIS FILE'S KEY CASE IS AUDIT #1's CLOSURE TEST, RE-AIMED (sub-case 2)
## ─────────────────────────────────────────────────────────────────────────
## Audit finding #1 was `mark_fluid_network_dirty()` sitting at ZERO callers
## for months while 44 green tests passed over it. The reason none of them
## saw it, stated in test_load_network_invalidation.gd's header: every one of
## those tests worked in a FRESH GridWorld, where `_fluid_network_dirty` is
## still `true` from init, so the first query rebuilt for a reason that had
## nothing to do with the code under test. A cold cache hides every
## invalidation bug there is.
##
## An underground pipe is a NEW WAY TO REACH THAT SAME HOLE. `grid_world.gd`'s
## place and remove paths used to read
##
##     if t == Buildings.Type.PIPE or t == Buildings.Type.PUMP:
##         _fluid_network_dirty = true
##
## — a hardcoded pair, one line above a MEMBERSHIP TEST against
## `Buildings.POWER_NETWORK_TYPES` doing the same job for power. Ship a third
## and fourth fluid type past that hardcoded pair and the building works, the
## save round-trips, every cold-cache test passes, and the tunnel simply does
## not exist to any player who places it into a world that has already been
## running. That is the project's named silent-compensation shape: absence
## indistinguishable from success. This session replaces both sites with
## `Buildings.FLUID_NETWORK_TYPES`.
##
## So sub-case (2) refuses to assert that a flag got set — a boolean flipping
## proves neither that the rebuild ran nor that its answer is right, which is
## the mistake test_load_network_invalidation.gd calls out by name. It
## RESOLVES the cache with a real public query first, asserts the answer is
## false, then places the two halves MID-SESSION with nothing else touched,
## and asks the same public query again. It then removes each half in turn,
## re-querying between every step so the cache is WARM before every single
## mutation. Four membership positions are covered: entry-on-place,
## entry-on-remove, exit-on-remove, exit-on-place.
##
## SUB-CASE (3) IS THE CONTROL, AND IT IS THE POINT. It builds the same
## layout in a FRESH world and queries ONCE — the cold-cache shape a
## save/load-based test has. It PASSES with the invalidation bug present.
## (2) and (3) differ in nothing but cache temperature, and only (2) reddens.
## A tunnel edge that appears only after a save/load is audit #1 reborn.
##
## ─────────────────────────────────────────────────────────────────────────
## Sub-case index
## ─────────────────────────────────────────────────────────────────────────
##   1. Registry literals — the two on-disk enum integers (39 / 40, pinned
##      forever by the save format), SAVE_VERSION 18 (no bump: append-only
##      enum, no new state), UNDERGROUND_MAX_SPAN 3 pinned from the PIPE side
##      (the Q6b rule — a belt-side rebalance must not silently rebalance
##      pipe tunnels), and the entry→exit family table.
##   2. THE MID-SESSION WARM-CACHE CASE. See above.
##   3. The cold-cache control that passes with the bug.
##   4. Pairing rules, each asserted BOTH through the predicate and
##      end-to-end through the fluid graph: span boundary, facing match,
##      cross-family refusal, gap-0 refusal.
##   5. The tunnel carries nothing — state is exactly {"dir"}, a tick and a
##      post_tick add no fields, and the cells the tunnel passes UNDER are
##      not in the network (it tunnels, it does not pave).
##   6. Save round-trip: both halves survive with their type and dir, and
##      the loaded world's tunnel edge resolves.
##   7. Determinism: component ids are independent of placement order (the
##      lexicographic anchor sort in _rebuild_fluid_network).
##   8. Participation: a tunnel half auto-connects to adjacent pipes exactly
##      as a pipe does (Pipe._is_connectable), and a BELT tunnel half does
##      not.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")
const TEST_SAVE_PATH: String = "user://test_underground_pipe.json"

# ---------------------------------------------------------------------------
# THE STANDARD RUN, on row y = 0. Every world this file builds is this row.
#
#   (0,0) WATER   (1,0) PUMP   (2,0) PIPE   (3,0) PIPE
#   (4,0) ENTRY facing E   (5,0) (6,0) covered ground   EXIT at 4+exit_dx
#   EXIT+1 PIPE   EXIT+2 PROBE
#
# The probe is adjacent to the far pipe only. The far pipe touches nothing but
# the exit. So the probe reads true IFF the tunnel edge exists — there is no
# second route, and no cell between the halves carries anything.
# ---------------------------------------------------------------------------
const WATER_CELL: Vector2i = Vector2i(0, 0)
const PUMP_CELL: Vector2i = Vector2i(1, 0)
const NEAR_PIPES: Array = [Vector2i(2, 0), Vector2i(3, 0)]
const ENTRY_CELL: Vector2i = Vector2i(4, 0)
# k = 3 from the entry: two covered cells, comfortably inside the span rather
# than at its boundary, so an unrelated span edit reads as sub-case (4)'s
# failure and not as this one's.
const PAIRED_DX: int = 3

static func test_name() -> String:
	return "underground pipe tunnel (mid-session warm-cache edge, span/facing/family pairing, no state)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	var orig_path: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	_case_registry_literals(failures)
	_case_mid_session_warm_cache(parent, failures)
	_case_cold_cache_control(parent, failures)
	_case_pairing_rules(parent, failures)
	_case_carries_nothing(parent, failures)
	_case_save_roundtrip(parent, failures)
	_case_determinism(parent, failures)
	_case_participation(parent, failures)

	SaveSystem.save_path = orig_path
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))

	if failures.is_empty():
		return { "ok": true, "message": "8 sub-cases pass: registry literals, mid-session warm-cache edge (4 membership positions), cold-cache control, pairing rules, carries-nothing, save round-trip, determinism, pipe participation" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) REGISTRY LITERALS.
#
# The two enum integers are LITERALS here because the save format fixes them
# forever: a reorder of the Type enum is a silent save corruption, and the
# only thing that can catch it is a number written down somewhere that is not
# the enum itself.
#
# UNDERGROUND_MAX_SPAN is pinned from the PIPE side as well as the belt side
# (test_underground.gd A7) on purpose — Q6b. Pipes share the belt's span
# CONSTANT, which means a rebalance of belt tunnel reach would silently
# rebalance pipe tunnel reach too. Two literals in two suites make that a
# deliberate two-file edit instead of a side effect.
# ===========================================================================
static func _case_registry_literals(failures: Array) -> void:
	_check(failures, int(Buildings.Type.UNDERGROUND_PIPE_ENTRY) == 39,
		"(1) UNDERGROUND_PIPE_ENTRY must be the on-disk integer 39 (appended after ELECTRIC_DRILL = 38). It reads %d — a reorder of the Type enum silently reinterprets every saved building" % int(Buildings.Type.UNDERGROUND_PIPE_ENTRY))
	_check(failures, int(Buildings.Type.UNDERGROUND_PIPE_EXIT) == 40,
		"(1) UNDERGROUND_PIPE_EXIT must be the on-disk integer 40. It reads %d" % int(Buildings.Type.UNDERGROUND_PIPE_EXIT))
	_check(failures, SaveSystem.SAVE_VERSION == 18,
		"(1) SAVE_VERSION must stay the literal 18 — the pipe tunnel is an append-only enum pair carrying no new state fields, so there is nothing to migrate. It reads %d" % SaveSystem.SAVE_VERSION)
	_check(failures, Underground.UNDERGROUND_MAX_SPAN == 3,
		"(1) UNDERGROUND_MAX_SPAN must be the literal 3 for PIPE tunnels as well as belt tunnels — pipes deliberately share the constant, so this literal is what makes a belt-side rebalance a deliberate edit here rather than a silent rebalance of every pipe tunnel in every save (Q6b). It reads %d" % Underground.UNDERGROUND_MAX_SPAN)

	# The family table: ONE function answers "which exit type may this entry
	# pair with", for both families. The belt/pipe distinction is a TABLE ROW,
	# not an emergent property of two similar scans.
	_check(failures, Underground.exit_type_for(Buildings.Type.UNDERGROUND_PIPE_ENTRY) == 40,
		"(1) exit_type_for(UNDERGROUND_PIPE_ENTRY) must be 40 (UNDERGROUND_PIPE_EXIT), got %d" % Underground.exit_type_for(Buildings.Type.UNDERGROUND_PIPE_ENTRY))
	_check(failures, Underground.exit_type_for(Buildings.Type.UNDERGROUND_BELT_ENTRY) == 36,
		"(1) exit_type_for(UNDERGROUND_BELT_ENTRY) must be 36 (UNDERGROUND_BELT_EXIT — SPLITTER 34, entry 35, exit 36, the trio test_belt_logistics_save_roundtrip.gd pins on disk) — the generalisation must not have moved the belt family, which is the arc's shipped behaviour. Got %d" % Underground.exit_type_for(Buildings.Type.UNDERGROUND_BELT_ENTRY))
	_check(failures, Underground.exit_type_for(Buildings.Type.UNDERGROUND_PIPE_EXIT) == -1,
		"(1) an EXIT is not an entry: exit_type_for(UNDERGROUND_PIPE_EXIT) must be -1, got %d" % Underground.exit_type_for(Buildings.Type.UNDERGROUND_PIPE_EXIT))
	_check(failures, Underground.exit_type_for(Buildings.Type.PIPE) == -1,
		"(1) a plain PIPE is not a tunnel entry: exit_type_for(PIPE) must be -1, got %d" % Underground.exit_type_for(Buildings.Type.PIPE))

	# The invalidation membership table. Its ABSENCE from a type is the bug
	# this whole file exists to catch, so the table's contents are pinned by
	# name and by size — an extra fluid type added without a row here would
	# repeat the finding exactly.
	for t in [Buildings.Type.PIPE, Buildings.Type.PUMP,
			Buildings.Type.UNDERGROUND_PIPE_ENTRY, Buildings.Type.UNDERGROUND_PIPE_EXIT]:
		_check(failures, Buildings.FLUID_NETWORK_TYPES.has(t),
			"(1) type %d must be in Buildings.FLUID_NETWORK_TYPES — that dictionary is what grid_world's place and remove paths test to decide whether to invalidate the fluid cache. A fluid type missing from it works, saves, and reloads, and is simply invisible to any world that was already running" % int(t))
	_check(failures, Buildings.FLUID_NETWORK_TYPES.size() == 4,
		"(1) FLUID_NETWORK_TYPES should hold exactly the 4 fluid types today (PIPE, PUMP, and the two pipe tunnel halves); it holds %d — if a type was added, add its literal above too" % Buildings.FLUID_NETWORK_TYPES.size())
	# The CARRIER subset — the nodes of the connectivity graph. PUMP is
	# deliberately NOT one: it marks a component, it is not a member of one.
	# Making the pump a node would merge two independent pipe runs that
	# happen to touch the same pump, which is a behaviour change disguised as
	# a table edit.
	_check(failures, not Buildings.FLUID_CARRIER_TYPES.has(Buildings.Type.PUMP),
		"(1) PUMP must NOT be in FLUID_CARRIER_TYPES — a pump is a SOURCE that marks a component, not a node in it. As a node it would silently merge two independent pipe runs that both touch it")
	for t in [Buildings.Type.PIPE, Buildings.Type.UNDERGROUND_PIPE_ENTRY,
			Buildings.Type.UNDERGROUND_PIPE_EXIT]:
		_check(failures, Buildings.FLUID_CARRIER_TYPES.has(t),
			"(1) type %d must be in Buildings.FLUID_CARRIER_TYPES — it is a node in the fluid connectivity graph" % int(t))

# ===========================================================================
# (2) THE MID-SESSION WARM-CACHE CASE — this file's reason to exist.
#
# Seven steps, each separated by a real public query so that the cache is
# RESOLVED before every mutation. The four membership positions:
#
#   step 3  place ENTRY last   → Buildings.FLUID_NETWORK_TYPES at PLACE, entry
#   step 4  remove ENTRY       → ... at REMOVE, entry
#   step 6  remove EXIT        → ... at REMOVE, exit
#   step 7  place EXIT last    → ... at PLACE, exit
#
# The ordering is load-bearing. If the halves were placed entry-then-exit, a
# missing ENTRY row would be masked by the EXIT's placement marking the cache
# dirty one call later, and the test would pass against the bug. Each half is
# therefore the LAST thing placed in the step that proves its row.
# ===========================================================================
static func _case_mid_session_warm_cache(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(PAIRED_DX, 0)
	var probe: Vector2i = exit_cell + Vector2i(2, 0)
	if not _pave_and_build_run(world, failures, PAIRED_DX):
		_teardown(world)
		return

	# --- step 1: resolve the cache through a public query, and pin false ---
	_check(failures, not world.fluid_available_at(probe),
		"(2.1) with no tunnel placed the far pipe is its own component and the probe at %s must read no fluid — the near run's pump is four cells and one gap away" % str(probe))
	# SETUP, not the outcome: if the flag were still dirty here, every
	# assertion below would rebuild for a reason unrelated to the fix, and the
	# whole sub-case would be vacuous. This is the exact line
	# test_load_network_invalidation.gd insists on for the same reason.
	_check(failures, not world._fluid_network_dirty,
		"(2.1) PREMISE: the fluid cache must be RESOLVED before the mid-session placements — with the dirty flag still true this sub-case tests nothing")

	# --- step 2: the EXIT alone is not an edge ---
	if not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E):
		_teardown(world)
		return
	_check(failures, not world.fluid_available_at(probe),
		"(2.2) an exit with no entry is an ordinary fitting, not a tunnel: the probe at %s must still read no fluid" % str(probe))

	# --- step 3: the ENTRY completes the pair, MID-SESSION, cache warm ---
	if not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E):
		_teardown(world)
		return
	_check(failures, world.fluid_available_at(probe),
		"(2.3) THE CASE. The entry at %s was placed into an ALREADY-RESOLVED world and completes a tunnel to the exit at %s, so the probe at %s must now see the pump. It reads false, which means placing a tunnel half never invalidated the fluid cache — the building works, the save round-trips, and the tunnel is invisible to the running session (audit #1's shape at a new site)" % [str(ENTRY_CELL), str(exit_cell), str(probe)])
	# The halves are graph NODES too, not just an edge between other people's
	# pipes: colouring and any per-cell fluid query must answer for them.
	_check(failures, world.is_pipe_in_pump_component(ENTRY_CELL),
		"(2.3) the entry cell %s is itself a node in the pump-bearing component — a tunnel mouth carries fluid exactly as the pipe it replaces did" % str(ENTRY_CELL))
	_check(failures, world.is_pipe_in_pump_component(exit_cell),
		"(2.3) the exit cell %s is itself a node in the pump-bearing component" % str(exit_cell))

	# --- step 4: removing the ENTRY cuts the edge, cache warm ---
	_check(failures, world.remove_building_at(ENTRY_CELL),
		"(2.4) PREMISE: could not remove the entry at %s" % str(ENTRY_CELL))
	_check(failures, not world.fluid_available_at(probe),
		"(2.4) removing the entry at %s destroys the only edge across the gap, so the probe at %s must go back to no fluid. It still reads true — removing a tunnel half never invalidated the cache, and the fluid keeps arriving through a tunnel the player just dug up" % [str(ENTRY_CELL), str(probe)])

	# --- step 5: re-place the entry (re-warm, and the edge comes back) ---
	if not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E):
		_teardown(world)
		return
	_check(failures, world.fluid_available_at(probe),
		"(2.5) re-placing the entry at %s restores the edge; pairing is recomputed on demand and never stored, so there is nothing to go stale" % str(ENTRY_CELL))

	# --- step 6: removing the EXIT cuts it from the other side ---
	_check(failures, world.remove_building_at(exit_cell),
		"(2.6) PREMISE: could not remove the exit at %s" % str(exit_cell))
	_check(failures, not world.fluid_available_at(probe),
		"(2.6) removing the exit at %s leaves an unpaired entry, so the probe at %s must read no fluid" % [str(exit_cell), str(probe)])

	# --- step 7: re-place the EXIT last, proving its own place-site row ---
	if not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E):
		_teardown(world)
		return
	_check(failures, world.fluid_available_at(probe),
		"(2.7) the exit at %s was the LAST thing placed into a resolved world, so this assertion is the one that fails if UNDERGROUND_PIPE_EXIT is missing from FLUID_NETWORK_TYPES at the place site" % str(exit_cell))
	_teardown(world)

# ===========================================================================
# (3) THE COLD-CACHE CONTROL.
#
# Byte-for-byte the same layout as (2)'s end state, built in a FRESH world and
# queried ONCE. A fresh GridWorld starts with _fluid_network_dirty == true, so
# the first query rebuilds no matter what the place path did or did not mark.
#
# THIS SUB-CASE PASSES WITH THE INVALIDATION BUG PRESENT. That is its entire
# job: it is the shape every save/load-based fluid test in this repo already
# has, and the reason 44 green tests never saw audit #1. If (3) is green and
# (2) is red, the defect is invalidation, not connectivity — and if BOTH are
# red the tunnel edge itself is missing from the resolver.
# ===========================================================================
static func _case_cold_cache_control(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(PAIRED_DX, 0)
	var probe: Vector2i = exit_cell + Vector2i(2, 0)
	if not _pave_and_build_run(world, failures, PAIRED_DX):
		_teardown(world)
		return
	if not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E):
		_teardown(world)
		return
	if not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E):
		_teardown(world)
		return
	_check(failures, world.fluid_available_at(probe),
		"(3) CONTROL: on a never-queried world the very first probe rebuilds from scratch, so a correct RESOLVER makes this true regardless of invalidation. Red here means the tunnel edge is missing from _rebuild_fluid_network itself, not that the cache went stale")
	_teardown(world)

# ===========================================================================
# (4) PAIRING RULES — span, facing, family, gap-0.
#
# Each rule is asserted TWICE: once against Underground.paired_exit (the
# predicate that is the single answer to "which exit does this entry feed?")
# and once end-to-end through the fluid graph. Two levels because the two
# failures are different bugs: a predicate that pairs too eagerly, and a
# resolver that builds an edge the predicate never sanctioned.
# ===========================================================================
static func _case_pairing_rules(parent: Node, failures: Array) -> void:
	# --- span. UNDERGROUND_MAX_SPAN is 3, and the scan runs k = 2 .. 4, so
	# an exit 4 cells ahead is the LAST that pairs and 5 ahead is the first
	# that does not. Both boundaries, because a span mutation that widens or
	# narrows the scan by one moves exactly one of them.
	_expect_pair(parent, failures, 2, Belt.DIR_E, Buildings.Type.UNDERGROUND_PIPE_EXIT, true,
		"(4a) an exit 2 cells ahead is the NEAREST legal pairing (k starts at 2, so a tunnel always covers at least one cell)")
	_expect_pair(parent, failures, 4, Belt.DIR_E, Buildings.Type.UNDERGROUND_PIPE_EXIT, true,
		"(4a) an exit UNDERGROUND_MAX_SPAN + 1 = 4 cells ahead is the FARTHEST legal pairing")
	_expect_pair(parent, failures, 5, Belt.DIR_E, Buildings.Type.UNDERGROUND_PIPE_EXIT, false,
		"(4a) an exit 5 cells ahead is out of span and must NOT pair — this is the assertion a widened scan reddens, and the one that keeps pipe tunnel reach pinned independently of the belt suite")

	# --- gap-0, which is the one rule whose two levels legitimately DISAGREE,
	# so it gets its own block rather than a row in _expect_pair.
	#
	# An exit placed immediately in front of an entry never PAIRS — a tunnel
	# must span something (RATIFIED as designed, design record 2026-08-28).
	# But the two halves are still cardinal neighbours, and both are carriers,
	# so they connect the ordinary way exactly as two adjacent pipes would.
	# Fluid crosses; no TUNNEL crosses. That distinction is worth pinning in
	# both directions: a resolver that refused the adjacency would make a pair
	# of touching fittings mysteriously inert, and a predicate that granted
	# the pairing would draw a dashed tunnel indicator across zero cells.
	_case_gap_zero(parent, failures)

	# --- facing. Fluid is undirected, but the pair's DIRECTION is a real
	# constraint on the scan: the entry looks along its own dir and requires
	# the exit to agree. Two halves facing different ways are two independent
	# fittings, exactly as in the belt family.
	_expect_pair(parent, failures, PAIRED_DX, Belt.DIR_S, Buildings.Type.UNDERGROUND_PIPE_EXIT, false,
		"(4b) an exit at the right distance but facing S while the entry faces E must NOT pair — dropping the dir match makes every crossing tunnel in a factory silently join")

	# --- family. The belt/pipe distinction is an explicit table row, not an
	# accident of two similar scans living in different files.
	_expect_pair(parent, failures, PAIRED_DX, Belt.DIR_E, Buildings.Type.UNDERGROUND_BELT_EXIT, false,
		"(4c) a PIPE entry must NOT pair with a BELT exit at the same distance and facing — items and fluid do not share tunnels, and the refusal must come from the family table rather than from the two families never meeting")

	# The mirror, at the predicate: a BELT entry must not pair with a PIPE
	# exit either. Asserted directly because a belt tunnel has no fluid probe.
	var world = _make_world(parent)
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(PAIRED_DX, 0)
	for cell in [ENTRY_CELL, exit_cell]:
		world.set_overlay(cell, Terrain.Overlay.STONE)
	if _place(world, failures, Buildings.Type.UNDERGROUND_BELT_ENTRY, ENTRY_CELL, Belt.DIR_E) \
			and _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E):
		var belt_entry: Building = world.building_at(ENTRY_CELL)
		_check(failures, Underground.paired_exit(belt_entry, world) == null,
			"(4c) the mirror: a BELT entry must not pair with a PIPE exit either. paired_exit returned a partner, which means the scan matches on 'looks like an exit' rather than on the entry's own family row")
	_teardown(world)

# ===========================================================================
# (5) THE TUNNEL CARRIES NOTHING.
#
# The locked decision, asserted as the absence of everything a carrier would
# need. `dir` and only `dir`; a tick and a post_tick add no fields (the pipe
# halves have no case in either dispatch, and a case added by mistake would
# materialise the belt entry's lane on the first call); and the cells the
# tunnel passes UNDER stay outside the network — it tunnels, it does not pave.
# ===========================================================================
static func _case_carries_nothing(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(PAIRED_DX, 0)
	var probe: Vector2i = exit_cell + Vector2i(2, 0)
	if not _pave_and_build_run(world, failures, PAIRED_DX) \
			or not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E) \
			or not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E):
		_teardown(world)
		return

	for pair in [[ENTRY_CELL, "entry"], [exit_cell, "exit"]]:
		var b: Building = world.building_at(pair[0])
		var keys: Array = b.state.keys()
		keys.sort()
		_check(failures, keys == ["dir"],
			"(5) the %s's state must be exactly {\"dir\"} — no lanes, no volume, no timing, because there is no fluid flow simulation for any of them to belong to. It holds %s" % [str(pair[1]), str(keys)])
		Buildings.tick_one(b, world)
		Buildings.post_tick_one(b, world)
		var after: Array = b.state.keys()
		after.sort()
		_check(failures, after == ["dir"],
			"(5) a tick and a post_tick must add nothing to the %s's state; it now holds %s. A pipe half wired into the belt entry's dispatch would materialise a lane here" % [str(pair[1]), str(after)])

	# The covered cells are ground, not pipe. A probe beside one of them sees
	# nothing: the tunnel passes under the surface and carries no fluid to it.
	for covered in [ENTRY_CELL + Vector2i(1, 0), ENTRY_CELL + Vector2i(2, 0)]:
		_check(failures, not world.is_pipe_in_pump_component(covered),
			"(5) %s is a cell the tunnel passes UNDER — it holds no building and must not be in the pipe component" % str(covered))
		_check(failures, not world.fluid_available_at(covered + Vector2i(0, -1)),
			"(5) %s sits beside a covered cell and nothing else, so it must read no fluid — a tunnel that fed the cells it passes under would be a pipe with extra steps" % str(covered + Vector2i(0, -1)))
	# ... while the run itself is live, so the negatives above are not a
	# world-wide false.
	_check(failures, world.fluid_available_at(probe),
		"(5) PREMISE: the run itself must be live, or the covered-cell negatives above prove nothing")
	_teardown(world)

# ===========================================================================
# (6) SAVE ROUND-TRIP.
#
# Append-only enum, no new state, SAVE_VERSION unchanged — so the round-trip
# is the whole migration story and it has to be shown rather than asserted in
# prose. Both halves come back with their type integer and their dir, and the
# LOADED world's tunnel edge resolves from those two facts alone (pairing is
# recomputed, never stored, so there is no partner field to have gone stale
# across the file).
# ===========================================================================
static func _case_save_roundtrip(parent: Node, failures: Array) -> void:
	var world_a = _make_world(parent)
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(PAIRED_DX, 0)
	var probe: Vector2i = exit_cell + Vector2i(2, 0)
	if not _pave_and_build_run(world_a, failures, PAIRED_DX) \
			or not _place(world_a, failures, Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E) \
			or not _place(world_a, failures, Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E):
		_teardown(world_a)
		return

	var player_a := Node2D.new()
	parent.add_child(player_a)
	var saved: bool = SaveSystem.save_game(world_a, player_a, Inventory.new(16))
	player_a.queue_free()
	_teardown(world_a)
	if not saved:
		_check(failures, false, "(6) PREMISE: save_game returned false")
		return

	var world_b = _make_world(parent)
	var player_b := Node2D.new()
	parent.add_child(player_b)
	var result = SaveSystem.load_game(world_b, player_b, Inventory.new(16))
	player_b.queue_free()
	if not bool(result.success):
		_check(failures, false, "(6) PREMISE: load_game returned !success: %s" % str(result.error_message))
		_teardown(world_b)
		return

	var loaded_entry: Building = world_b.building_at(ENTRY_CELL)
	var loaded_exit: Building = world_b.building_at(exit_cell)
	_check(failures, loaded_entry != null and int(loaded_entry.type) == 39 and int(loaded_entry.state.get("dir", -1)) == 0,
		"(6) the entry must come back at %s as type 39 facing 0 (E); got %s" % [str(ENTRY_CELL), "null" if loaded_entry == null else "type %d dir %s" % [int(loaded_entry.type), str(loaded_entry.state.get("dir", "absent"))]])
	_check(failures, loaded_exit != null and int(loaded_exit.type) == 40 and int(loaded_exit.state.get("dir", -1)) == 0,
		"(6) the exit must come back at %s as type 40 facing 0 (E); got %s" % [str(exit_cell), "null" if loaded_exit == null else "type %d dir %s" % [int(loaded_exit.type), str(loaded_exit.state.get("dir", "absent"))]])
	_check(failures, world_b.fluid_available_at(probe),
		"(6) the loaded world's tunnel edge must resolve from the two round-tripped halves alone — the probe at %s reads no fluid" % str(probe))
	_teardown(world_b)

# ===========================================================================
# (7) DETERMINISM.
#
# _rebuild_fluid_network sorts its seed anchors lexicographically so component
# ids do not depend on the order buildings happen to sit in the `buildings`
# dictionary. Adding tunnel halves to that seed set — and a link table built
# alongside it — is exactly the kind of change that quietly reintroduces
# insertion-order dependence, so the same layout is built twice in opposite
# orders and the resolved component maps are compared cell by cell.
# ===========================================================================
static func _case_determinism(parent: Node, failures: Array) -> void:
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(PAIRED_DX, 0)
	var forward = _make_world(parent)
	var backward = _make_world(parent)
	var rows: Array = []
	rows.append([Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E])
	rows.append([Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E])
	var ok: bool = _pave_and_build_run(forward, failures, PAIRED_DX) \
		and _pave_and_build_run(backward, failures, PAIRED_DX)
	if ok:
		for r in rows:
			ok = ok and _place(forward, failures, r[0], r[1], r[2])
		for i in range(rows.size() - 1, -1, -1):
			ok = ok and _place(backward, failures, rows[i][0], rows[i][1], rows[i][2])
	if ok:
		# Resolve both through a public query, never by calling the rebuild.
		forward.fluid_available_at(exit_cell)
		backward.fluid_available_at(exit_cell)
		var same: bool = forward._pipe_component.size() == backward._pipe_component.size()
		if same:
			for cell in forward._pipe_component:
				if not backward._pipe_component.has(cell) \
						or int(backward._pipe_component[cell]) != int(forward._pipe_component[cell]):
					same = false
					break
		_check(failures, same,
			"(7) the same layout placed in opposite orders must resolve to the SAME component ids — the lexicographic anchor sort is what guarantees it, and a tunnel-link table built by iterating `buildings` instead would make ids depend on placement history. forward=%s backward=%s" % [str(forward._pipe_component), str(backward._pipe_component)])
	_teardown(forward)
	_teardown(backward)

# ===========================================================================
# (8) PARTICIPATION.
#
# Pipe.draw asks Pipe._is_connectable which neighbours to grow a stub toward.
# A tunnel mouth is a fitting: adjacent pipes must reach for it exactly as
# they reach for another pipe, or a working tunnel reads as a pipe run that
# stops one tile short — the arc's already-recorded "signals by omission"
# shape, in the one place a player looks first.
#
# The BELT halves must stay unconnectable: they carry items, and a pipe
# reaching for one would draw a join that no fluid crosses.
# ===========================================================================
static func _case_participation(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var cells: Array = [Vector2i(0, 40), Vector2i(1, 40), Vector2i(2, 40), Vector2i(3, 40)]
	for cell in cells:
		world.set_overlay(cell, Terrain.Overlay.STONE)
	var rows: Array = [
		[Buildings.Type.UNDERGROUND_PIPE_ENTRY, cells[0], true, "a pipe tunnel ENTRY"],
		[Buildings.Type.UNDERGROUND_PIPE_EXIT, cells[1], true, "a pipe tunnel EXIT"],
		[Buildings.Type.UNDERGROUND_BELT_ENTRY, cells[2], false, "a BELT tunnel entry"],
		[Buildings.Type.UNDERGROUND_BELT_EXIT, cells[3], false, "a BELT tunnel exit"],
	]
	for row in rows:
		if not _place(world, failures, row[0], row[1], Belt.DIR_E):
			continue
		var b: Building = world.building_at(row[1])
		_check(failures, Pipe._is_connectable(b) == bool(row[2]),
			"(8) Pipe._is_connectable(%s) must be %s — an adjacent pipe draws its stub toward exactly the neighbours this predicate names" % [str(row[3]), str(row[2])])
	_check(failures, not Pipe._is_connectable(null),
		"(8) _is_connectable(null) must stay false — empty ground is not a fitting")
	_teardown(world)

## Gap-0: adjacent halves connect as fittings but form no tunnel. See the
## comment at its call site for why this is the one rule asserted with two
## different expectations at the two levels.
static func _case_gap_zero(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(1, 0)
	var probe: Vector2i = exit_cell + Vector2i(2, 0)
	if not _pave_and_build_run(world, failures, 1) \
			or not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E) \
			or not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_EXIT, exit_cell, Belt.DIR_E):
		_teardown(world)
		return
	var entry: Building = world.building_at(ENTRY_CELL)
	_check(failures, Underground.paired_exit(entry, world) == null,
		"(4d) an exit at %s is immediately in front of the entry at %s, and the scan starts at k = 2, so they must NOT pair — a tunnel has to span something. A partner here means the dashed indicator draws across zero cells" % [str(exit_cell), str(ENTRY_CELL)])
	_check(failures, world.fluid_available_at(probe),
		"(4d) ... and yet fluid must still cross: the two halves are cardinal neighbours and both are carriers, so they join exactly as two adjacent pipes do. The probe at %s reads false, which would make a pair of touching fittings mysteriously inert" % str(probe))
	_teardown(world)

# ---------- fixtures ----------

## Build one standard run in `world` at the given exit offset, WITHOUT the
## tunnel halves: water, pump, the two near pipes, the far pipe beyond the
## exit cell, and stone under everything including the two tunnel cells and
## the covered ground. Returns false on the first refused placement.
static func _pave_and_build_run(world, failures: Array, exit_dx: int) -> bool:
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(exit_dx, 0)
	var far_pipe: Vector2i = exit_cell + Vector2i(1, 0)
	var water := Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.tiles[WATER_CELL] = water
	world.tile_modifications[WATER_CELL] = water
	# Pave the whole row from the pump to the far pipe, so the tunnel cells and
	# the ground it passes under accept a building at any offset this file uses.
	for x in range(PUMP_CELL.x, far_pipe.x + 1):
		world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)

	if not _place(world, failures, Buildings.Type.PUMP, PUMP_CELL, 0):
		return false
	for p in NEAR_PIPES:
		if not _place(world, failures, Buildings.Type.PIPE, p, 0):
			return false
	return _place(world, failures, Buildings.Type.PIPE, far_pipe, 0)

## One full standard run WITH a tunnel whose exit sits `exit_dx` ahead facing
## `exit_dir`, of type `exit_type`. Asserts the probe against `expect` and, at
## the same time, Underground.paired_exit against the same expectation — the
## predicate and the resolver have to agree, and they fail differently.
static func _expect_pair(parent: Node, failures: Array, exit_dx: int, exit_dir: int, exit_type: int, expect: bool, label: String) -> void:
	var world = _make_world(parent)
	var exit_cell: Vector2i = ENTRY_CELL + Vector2i(exit_dx, 0)
	var probe: Vector2i = exit_cell + Vector2i(2, 0)
	if not _pave_and_build_run(world, failures, exit_dx) \
			or not _place(world, failures, Buildings.Type.UNDERGROUND_PIPE_ENTRY, ENTRY_CELL, Belt.DIR_E) \
			or not _place(world, failures, exit_type, exit_cell, exit_dir):
		_teardown(world)
		return
	var entry: Building = world.building_at(ENTRY_CELL)
	var partner: Building = Underground.paired_exit(entry, world)
	_check(failures, (partner != null) == expect,
		"%s — Underground.paired_exit returned %s, expected %s" % [label, "a partner at %s" % str(partner.anchor) if partner != null else "null", "a partner" if expect else "null"])
	_check(failures, world.fluid_available_at(probe) == expect,
		"%s — end-to-end, the probe at %s reads %s and must read %s" % [label, str(probe), str(not expect), str(expect)])
	_teardown(world)

static func _place(world, failures: Array, t: int, pos: Vector2i, dir: int) -> bool:
	if world.place_building(t, pos, dir):
		return true
	_check(failures, false,
		"PREMISE: could not place type %d at %s facing %d: %s" % [int(t), str(pos), dir, str(world.last_building_place_error)])
	return false

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

## A fresh GridWorld parented to `parent` so its _ready() runs. An empty
## `tiles` dict reads back GRASS / NONE everywhere, so every placement here is
## seed-independent once its overlay is painted.
static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	return world

## Disconnect BEFORE freeing: queue_free is deferred past the runner's
## synchronous run(), so a torn-down world would otherwise stay subscribed to
## TickSystem.tick for the rest of the suite. Same shape as
## test_load_network_invalidation.gd's _teardown.
static func _teardown(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
