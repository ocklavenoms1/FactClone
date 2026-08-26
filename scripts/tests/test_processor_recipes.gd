extends RefCounted

## Audit finding #25 — "Nine processor recipes (bread + cloth chains) are never
## executed by any test".
##
## This is a TEST-GAP finding. `recipes.gd` is correct today; nothing here fixes
## a defect. What this file does is give the nine dispatch-table rows something
## to disagree with.
##
## ─────────────────────────────────────────────────────────────────────────────
## ⚠ EVERY EXPECTED VALUE BELOW IS A LITERAL. NOTHING IS READ FROM `Recipes`.
## ─────────────────────────────────────────────────────────────────────────────
## NOTES.md, "An assertion that derives its expectation from the code under test
## cannot see it change." A suite that asked `Recipes.get_recipe(id)["outputs_solid"]`
## what to expect, or took its tick budget from `recipe["time_ticks"]`, would draw
## expectation and behaviour from the SAME source: swap an output item, change a
## ratio, halve a duration, and test and production move together and agree. That
## is precisely the defect this finding exists to prevent, reproduced inside its
## own fix — and it would be the third instance in this project (#27 duplicated
## production, #26's M4 CALLED it).
##
## So the table below is a SECOND, INDEPENDENT statement of the nine rows.
## Counts, ratios, output identities and cycle lengths are written out here.
## `Recipes` is never consulted at any point in this file — grep it: the string
## `Recipes.` does not appear below this header.
##
## What IS taken from production, deliberately: `Buildings.Type.*` and
## `Items.Type.*` (enum NAMES, not recipe data — the recipe claim being locked is
## the ASSOCIATION "a Proofer turns 1 Dough into 1 Risen Dough in 400 ticks", and
## that association is stated here in full), and `Processor.IDLE` / `RUNNING`.
## Those two state constants are pinned against literals in `_case_state_enum` so
## the dependence is visible rather than assumed.
##
## ─────────────────────────────────────────────────────────────────────────────
## RE-DERIVED FROM `recipes.gd` AT THIS COMMIT — not inherited from the finding.
## ─────────────────────────────────────────────────────────────────────────────
##   proofer_rise      :64   1 DOUGH (W)              → 1 RISEN_DOUGH (E)   400
##   oven_bread        :77   1 RISEN_DOUGH (W)
##                           + 1 FUEL_BRIQUETTE (S)   → 1 BREAD (E)         120
##   packager_loaves   :91   4 BREAD (W)              → 1 LOAF_PACK (E)      80
##   briquetter_fuel   :103  3 STRAW                  → 1 FUEL_BRIQUETTE    100
##   yeast_culture     :114  1 SUGAR + WATER          → 2 YEAST             200
##   press_sugar       :125  1 SUGAR_BEET             → 1 SUGAR             100
##   retter_fiber      :139  1 FLAX (W) + WATER       → 1 FIBER (E)         160
##   loom_cloth        :153  3 FIBER (W)              → 1 CLOTH (E)         120
##   tailor_bag        :165  4 CLOTH (W)              → 1 BAG (E)           160
##
## All nine: `input_capacity` 8, `output_capacity` 8, `Terrain.Overlay.STONE`
## accepted. PROOFER / OVEN / PACKAGER are 2×2 (buildings.gd:321, :342, :372);
## the other six are 1×1. All nine dispatch through ONE shared `Processor.tick`
## arm (buildings.gd:1092-1095), and every `make()` wires
## `Processor.make_state(DEFAULT_RECIPE_ID)`, so no test needs to set `recipe_id`
## — which is itself an assertion here, one per row.
##
## NONE of the nine is Burner-driven: `grep -c Burner` is 0 in all nine building
## scripts. `oven_bread`'s FUEL_BRIQUETTE is an `inputs_solid` entry consumed by
## the recipe, not a `fuel_buffer` — buildings.gd:346-350 says so in prose and
## names the slot `input_fuel` with kind `"input"`, NOT kind `"fuel"`.
##
## ─────────────────────────────────────────────────────────────────────────────
## ⚠ WHERE #25 IS STALE — "zero tick-level coverage" is no longer true of ONE row
## ─────────────────────────────────────────────────────────────────────────────
## #25's verification notes assert that "No test file emits ticks against an OVEN
## ... through a recipe cycle" and that "no test anywhere executes IDLE→RUNNING→
## output for these 9 recipes". Re-derived today, that is FALSE for `oven_bread`.
## `test_inserter_shared_input_cap.gd` — which did not exist when #25 was written;
## it landed when audit #3 closed — places a real OVEN, pins its `recipe_id`
## (:90-92), pre-loads 8 RISEN_DOUGH (:95), belt-and-inserter-feeds it fuel, and
## ticks it 400 + 400 times through full bakes.
##
## That is genuine tick-level execution of `oven_bread`, and it is worth naming
## rather than quietly duplicating. What it is NOT is a lock on the recipe DATA:
## its two production assertions are `bread_made > 0` (:116) and
## `bread_later > bread_made` (:127) — LOWER BOUNDS, the exact shape #26 identified
## as the reason gaps survive. Measured on `oven_bread`, three mutations, one at a
## time: swapping the output item to LOAF_PACK DOES redden it (bread falls to
## zero); raising the RISEN_DOUGH input from 1 to 2, and halving `time_ticks` from
## 120 to 60, each leave it GREEN — fewer-but-still-some and faster both satisfy
## `> 0` and `>` previous. All three redden this suite.
##
## So the finding's SUBSTANCE stands for all nine and its wording is stale for one.
## The rest of the "only UI-slot assertions touch these machines" account holds:
## test_building_ui_2/3 assert slot layouts without ticking, and
## test_cloth_prefer_dir.gd:27-29 still says in as many words that it pre-loads
## `out_buffer` to skip the recipe cycle.
##
## ─────────────────────────────────────────────────────────────────────────────
## WHY N = 2 CYCLES, AND WHY THE TICK COUNTS ARE EXACT RATHER THAN GENEROUS
## ─────────────────────────────────────────────────────────────────────────────
## Two constraints, pre-computed rather than discovered: `output_capacity` 8 caps
## cycles (yeast emits 2/cycle → N ≤ 3 before `_has_room_for_outputs` blocks) and
## `input_capacity` 8 caps a belt-fed pre-load (4:1 recipes → N = 2). N = 2
## uniformly is inside both and still gives exact-ratio evidence: with 8 BREAD in
## and 2 LOAF_PACK out, a 4:1 row that became 2:1 produces 4 and reddens.
##
## The completion tick is DERIVED from `Processor.tick`'s state machine, not
## copied from a run. IDLE consumes and sets `progress = 1` on the tick it fires;
## RUNNING increments and emits when `progress >= time_ticks`; the IDLE arm does
## not run again on the emitting tick because `s` was read before the match. So
## with a pre-loaded buffer and no belts:
##
##     cycle 1 consumes on tick 1        and emits on tick T
##     cycle 2 consumes on tick T + 1    and emits on tick 2T
##
## — N cycles complete on EXACTLY tick N·T. That is what makes `time_ticks`
## lockable: each row is sampled at tick N·T − 1 (must hold N−1 outputs) and at
## tick N·T (must hold N). A halved duration finishes both cycles early and fails
## the first sample; a doubled one fails the second. A budget of "N·T plus
## margin, then count" cannot see either.
##
## ─────────────────────────────────────────────────────────────────────────────
## REACHABILITY — BOTH SIDES OF EVERY CYCLE, PLUS AN EXPLICIT DEAD-MACHINE CONTROL
## ─────────────────────────────────────────────────────────────────────────────
## A processor that never runs leaves `in_buffer` full and `out_buffer` empty, so
## "no wrong item was produced" and "no extra input was eaten" are both trivially
## true of a machine that is not ticking at all. Every row therefore asserts
## inputs CONSUMED and outputs PRODUCED at exact counts, and `_case_dry_recipes`
## carries an explicit `REACHABILITY CONTROL` sampled at tick 1: every machine
## must be RUNNING with `progress == 1` and must have given up exactly one
## cycle's inputs. A world whose tick signal is not wired fails that control
## before any recipe assertion is reached, so their silence means something.
##
## No `>=` appears in this file. Lower bounds are what let #26's gap exist.
##
## ─────────────────────────────────────────────────────────────────────────────
## THE FLUID NEGATIVE CASES ARE THE MOST VALUABLE PART OF THE FLUID HALF
## ─────────────────────────────────────────────────────────────────────────────
## `yeast_culture` and `retter_fiber` are the only two of the nine with an
## `inputs_fluid` entry, and before this suite the water gate was asserted for
## the MIXER alone (test_mixer_dough.gd Phase 2). The positive case proves the
## pump+pipe fixture feeds them; the negative case — pump removed, inputs
## reloaded, ticked a full budget — proves the gate is what stopped them, and
## asserts the inputs are STILL THERE rather than merely that no output appeared.
## Deleting `inputs_fluid` from either row reddens the negative case and nothing
## else, which is exactly the mutation the finding's own verification note names
## as invisible to the suite as it stood.
##
## ─────────────────────────────────────────────────────────────────────────────
## SCOPE — what this file deliberately does NOT cover.
## ─────────────────────────────────────────────────────────────────────────────
## Pre-loading `in_buffer` bypasses the belt PULL path and the `prefer_dir` port
## rotation, as #25's fix text prescribes; those are covered by
## test_thresher_prefer_dir.gd, test_thresher_rotation.gd and
## test_cloth_prefer_dir.gd. Machines are spaced with a clear cell between
## footprints so `_try_push_outputs` finds no belt or chest sink and outputs stay
## in `out_buffer` where they can be counted — the push path is
## test_processor_feeder_push.gd's. This suite locks recipe DATA and the
## default-recipe wiring, which is the surface the finding names.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

## Cycles run per recipe. See the header for why 2 and not more.
const CYCLES: int = 2

## Ticks emitted past the slowest row's exact completion tick. Only ever used to
## prove nothing MORE happens; the exact counts are sampled before it.
const MARGIN: int = 100

## The seven recipes with no fluid input. One table, one driver.
## Every field is a literal restatement of a `recipes.gd` row.
static func _dry_rows() -> Array:
	return [
		{
			"recipe_id": "proofer_rise",
			"type": Buildings.Type.PROOFER,
			"pos": Vector2i(0, 0),
			"footprint": Vector2i(2, 2),
			"inputs_per_cycle": [[Items.Type.DOUGH, 1]],
			"output_per_cycle": [Items.Type.RISEN_DOUGH, 1],
			"cycle_ticks": 400,
		},
		{
			"recipe_id": "oven_bread",
			"type": Buildings.Type.OVEN,
			"pos": Vector2i(3, 0),
			"footprint": Vector2i(2, 2),
			# Two solid inputs. Both must be consumed every cycle — the fuel
			# briquette is a recipe input, not a Burner charge.
			"inputs_per_cycle": [[Items.Type.RISEN_DOUGH, 1], [Items.Type.FUEL_BRIQUETTE, 1]],
			"output_per_cycle": [Items.Type.BREAD, 1],
			"cycle_ticks": 120,
		},
		{
			"recipe_id": "packager_loaves",
			"type": Buildings.Type.PACKAGER,
			"pos": Vector2i(6, 0),
			"footprint": Vector2i(2, 2),
			"inputs_per_cycle": [[Items.Type.BREAD, 4]],      # 4:1
			"output_per_cycle": [Items.Type.LOAF_PACK, 1],
			"cycle_ticks": 80,
		},
		{
			"recipe_id": "briquetter_fuel",
			"type": Buildings.Type.BRIQUETTER,
			"pos": Vector2i(9, 0),
			"footprint": Vector2i(1, 1),
			"inputs_per_cycle": [[Items.Type.STRAW, 3]],      # 3:1
			"output_per_cycle": [Items.Type.FUEL_BRIQUETTE, 1],
			"cycle_ticks": 100,
		},
		{
			"recipe_id": "press_sugar",
			"type": Buildings.Type.SUGAR_PRESS,
			"pos": Vector2i(11, 0),
			"footprint": Vector2i(1, 1),
			"inputs_per_cycle": [[Items.Type.SUGAR_BEET, 1]],
			"output_per_cycle": [Items.Type.SUGAR, 1],
			"cycle_ticks": 100,
		},
		{
			"recipe_id": "loom_cloth",
			"type": Buildings.Type.LOOM,
			"pos": Vector2i(13, 0),
			"footprint": Vector2i(1, 1),
			"inputs_per_cycle": [[Items.Type.FIBER, 3]],      # 3:1
			"output_per_cycle": [Items.Type.CLOTH, 1],
			"cycle_ticks": 120,
		},
		{
			"recipe_id": "tailor_bag",
			"type": Buildings.Type.TAILOR,
			"pos": Vector2i(15, 0),
			"footprint": Vector2i(1, 1),
			"inputs_per_cycle": [[Items.Type.CLOTH, 4]],      # 4:1
			"output_per_cycle": [Items.Type.BAG, 1],
			"cycle_ticks": 160,
		},
	]

## The two recipes with an `inputs_fluid` entry. Same row shape; each gets its
## own world with the water + PUMP + PIPE fixture, then the pump-removal case.
static func _fluid_rows() -> Array:
	return [
		{
			"recipe_id": "yeast_culture",
			"type": Buildings.Type.YEAST_CULTURE,
			"pos": Vector2i(3, 0),
			"footprint": Vector2i(1, 1),
			"inputs_per_cycle": [[Items.Type.SUGAR, 1]],
			"output_per_cycle": [Items.Type.YEAST, 2],        # the only 1:2 row
			"cycle_ticks": 200,
		},
		{
			"recipe_id": "retter_fiber",
			"type": Buildings.Type.RETTER,
			"pos": Vector2i(3, 0),
			"footprint": Vector2i(1, 1),
			"inputs_per_cycle": [[Items.Type.FLAX, 1]],
			"output_per_cycle": [Items.Type.FIBER, 1],
			"cycle_ticks": 160,
		},
	]

static func test_name() -> String:
	return "processor recipes (#25: nine bread + cloth rows, exact ratios and durations)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_state_enum(failures)
	_case_dry_recipes(parent, failures)
	_case_fluid_recipes(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "9 recipes ran %d exact cycles each; both fluid rows refused every cycle without a pump" % CYCLES }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures)] }

## Drift alarm. The cases below compare `b.state["state"]` against
## `Processor.IDLE` / `Processor.RUNNING`, which are production constants sitting
## on the expected side of an assertion. They are not recipe data and are not
## what this suite protects, but the dependence should be visible rather than
## implicit — so it is pinned to a literal exactly once, here.
static func _case_state_enum(failures: Array) -> void:
	_check(failures, Processor.IDLE == 0, "(0) Processor.IDLE should be 0, got %d" % Processor.IDLE)
	_check(failures, Processor.RUNNING == 1, "(0) Processor.RUNNING should be 1, got %d" % Processor.RUNNING)

## (1) THE SEVEN DRY ROWS. One shared world, one driver, exact samples.
static func _case_dry_recipes(parent: Node, failures: Array) -> void:
	var rows: Array = _dry_rows()
	var world = GridWorldScript.new()
	parent.add_child(world)
	TickSystem.current_tick = 0

	var machines: Array = []
	for row in rows:
		var b: Building = _place_and_preload(world, row, failures, "(1)")
		if b == null:
			_cleanup(world)
			return
		machines.append(b)

	_drive_and_assert(world, rows, machines, failures, "(1)", true)
	_cleanup(world)

## (2) THE TWO FLUID ROWS. Each gets its own world so the pump removal in its
## negative half cannot reach the other's network.
static func _case_fluid_recipes(parent: Node, failures: Array) -> void:
	for row in _fluid_rows():
		var tag: String = "(2 %s)" % row["recipe_id"]
		var world = GridWorldScript.new()
		parent.add_child(world)
		TickSystem.current_tick = 0

		# Fixture lifted from test_mixer_dough.gd: water at (0,0), pump at (1,0),
		# pipe at (2,0), machine at (3,0). The pipe sits on the machine's W
		# perimeter cell, which `fluid_available_for_building` scans.
		world.tiles[Vector2i(0, 0)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
		for x in range(1, 4):
			world.set_overlay(Vector2i(x, 0), Terrain.Overlay.STONE)
		if not world.place_building(Buildings.Type.PUMP, Vector2i(1, 0)):
			_check(failures, false, "%s pump placement failed" % tag)
			_cleanup(world)
			continue
		if not world.place_building(Buildings.Type.PIPE, Vector2i(2, 0)):
			_check(failures, false, "%s pipe placement failed" % tag)
			_cleanup(world)
			continue

		var b: Building = _place_and_preload(world, row, failures, tag)
		if b == null:
			_cleanup(world)
			continue
		_check(failures, world.fluid_available_for_building(b),
			"%s machine should see water through the pipe on its W perimeter cell" % tag)

		# Positive half — identical treatment to the dry rows.
		_drive_and_assert(world, [row], [b], failures, tag, false)

		# ── Negative half: same machine, same inputs, no pump. ──
		# A path assertion, not a count: the recipe must be stopped BY THE WATER
		# GATE, so the inputs must still be sitting in the buffer afterwards.
		world.remove_building_at(Vector2i(1, 0))
		_check(failures, not world.fluid_available_for_building(b),
			"%s water should be gone once the pump is removed" % tag)
		_preload(b, row)
		var budget: int = CYCLES * int(row["cycle_ticks"]) + MARGIN
		for _i in budget:
			TickSystem.current_tick += 1
			TickSystem.tick.emit(TickSystem.current_tick)

		var out_type: int = int(row["output_per_cycle"][0])
		_check(failures, _bag_count(b.state.get("out_buffer", []), out_type) == 0,
			"%s expected 0 output without a pump, got %d — the recipe ran without water" \
				% [tag, _bag_count(b.state.get("out_buffer", []), out_type)])
		_check(failures, _bag_total(b.state.get("out_buffer", [])) == 0,
			"%s out_buffer should be empty without a pump, holds %s" % [tag, str(b.state.get("out_buffer", []))])
		_check(failures, int(b.state.get("state", -1)) == Processor.IDLE,
			"%s should stay IDLE without water, got state %d" % [tag, int(b.state.get("state", -1))])
		_check(failures, int(b.state.get("progress", -1)) == 0,
			"%s progress should stay 0 without water, got %d" % [tag, int(b.state.get("progress", -1))])
		# Both sides. A machine that consumed its inputs and then produced
		# nothing is a DIFFERENT bug from one that never started.
		for pair in row["inputs_per_cycle"]:
			var item_type: int = int(pair[0])
			var want: int = CYCLES * int(pair[1])
			var have: int = _bag_count(b.state.get("in_buffer", []), item_type)
			_check(failures, have == want,
				"%s input %d should be untouched at %d without water, got %d" % [tag, item_type, want, have])

		_cleanup(world)

# ---------- driver ----------

## Emit ticks against `world` and sample every row at its two exact checkpoints.
##
## `with_control` runs the dead-machine REACHABILITY CONTROL at tick 1. It is on
## for the shared dry world (where one control covers all seven) and off for the
## single-machine fluid worlds, whose positive halves are already preceded by an
## explicit `fluid_available_for_building` assertion and whose negative halves
## depend on the machine staying still.
static func _drive_and_assert(world, rows: Array, machines: Array, failures: Array, tag: String, with_control: bool) -> void:
	var total: int = 0
	for row in rows:
		total = max(total, CYCLES * int(row["cycle_ticks"]))
	total += MARGIN

	# Per-row samples: -1 means "checkpoint never reached", which fails below.
	var at_penultimate: Array = []
	var at_completion: Array = []
	for _i in rows.size():
		at_penultimate.append(-1)
		at_completion.append(-1)

	for t in range(1, total + 1):
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)

		if t == 1 and with_control:
			_assert_reachability(rows, machines, failures, tag)

		for i in rows.size():
			var done_tick: int = CYCLES * int(rows[i]["cycle_ticks"])
			var out_type: int = int(rows[i]["output_per_cycle"][0])
			if t == done_tick - 1:
				at_penultimate[i] = _bag_count(machines[i].state.get("out_buffer", []), out_type)
			elif t == done_tick:
				at_completion[i] = _bag_count(machines[i].state.get("out_buffer", []), out_type)

	for i in rows.size():
		var row: Dictionary = rows[i]
		var b: Building = machines[i]
		var rid: String = str(row["recipe_id"])
		var out_type: int = int(row["output_per_cycle"][0])
		var per_cycle_out: int = int(row["output_per_cycle"][1])

		# The default-recipe wiring: `make()` must have pinned this id itself.
		_check(failures, str(b.state.get("recipe_id", "")) == rid,
			"%s %s: recipe_id should be '%s', got '%s'" % [tag, rid, rid, str(b.state.get("recipe_id", ""))])

		# DURATION. Derived in the header: N cycles complete on exactly tick N·T.
		_check(failures, at_penultimate[i] == (CYCLES - 1) * per_cycle_out,
			"%s %s: at tick %d (one before completion) expected %d output, got %d — cycle length is not %d ticks" \
				% [tag, rid, CYCLES * int(row["cycle_ticks"]) - 1, (CYCLES - 1) * per_cycle_out, at_penultimate[i], int(row["cycle_ticks"])])
		_check(failures, at_completion[i] == CYCLES * per_cycle_out,
			"%s %s: at tick %d (completion) expected %d output, got %d — cycle length is not %d ticks" \
				% [tag, rid, CYCLES * int(row["cycle_ticks"]), CYCLES * per_cycle_out, at_completion[i], int(row["cycle_ticks"])])

		# OUTPUT — exact identity and exact count, and nothing else in the bag.
		var got_out: int = _bag_count(b.state.get("out_buffer", []), out_type)
		_check(failures, got_out == CYCLES * per_cycle_out,
			"%s %s: expected exactly %d of item %d after %d cycles, got %d. out_buffer: %s" \
				% [tag, rid, CYCLES * per_cycle_out, out_type, CYCLES, got_out, str(b.state.get("out_buffer", []))])
		_check(failures, _bag_total(b.state.get("out_buffer", [])) == CYCLES * per_cycle_out,
			"%s %s: out_buffer should hold ONLY %d of item %d, holds %s" \
				% [tag, rid, CYCLES * per_cycle_out, out_type, str(b.state.get("out_buffer", []))])

		# INPUT — the other side of the ratio. Pre-load was exactly N cycles'
		# worth, so anything left over means the recipe ate less than declared,
		# and the output check above means it ate no more.
		for pair in row["inputs_per_cycle"]:
			var item_type: int = int(pair[0])
			var left: int = _bag_count(b.state.get("in_buffer", []), item_type)
			_check(failures, left == 0,
				"%s %s: expected 0 of input %d left after %d cycles, got %d — ratio is not %d per cycle" \
					% [tag, rid, item_type, CYCLES, left, int(pair[1])])
		_check(failures, _bag_total(b.state.get("in_buffer", [])) == 0,
			"%s %s: in_buffer should be empty after %d cycles, holds %s" % [tag, rid, CYCLES, str(b.state.get("in_buffer", []))])

		# Nothing more happens once the inputs are gone: the machine parks IDLE
		# with progress 0 for the whole MARGIN, rather than starting a cycle it
		# cannot finish.
		_check(failures, int(b.state.get("state", -1)) == Processor.IDLE,
			"%s %s: should be IDLE once inputs are exhausted, got state %d" % [tag, rid, int(b.state.get("state", -1))])
		_check(failures, int(b.state.get("progress", -1)) == 0,
			"%s %s: progress should be 0 once inputs are exhausted, got %d" % [tag, rid, int(b.state.get("progress", -1))])

## REACHABILITY CONTROL. Sampled after the FIRST tick only.
##
## A machine that is not being ticked at all — an unwired tick signal, a dropped
## `Processor.tick` dispatch arm, a `recipe_id` the registry cannot resolve —
## sits at IDLE with `progress` 0 and a full `in_buffer`. That state satisfies
## "no wrong item was produced" and "no extra input was eaten" trivially, so
## without this control the ratio and identity assertions could be green for a
## world in which nothing runs. Here it must have STARTED, and it must have paid
## exactly one cycle's inputs to do so.
static func _assert_reachability(rows: Array, machines: Array, failures: Array, tag: String) -> void:
	for i in rows.size():
		var row: Dictionary = rows[i]
		var b: Building = machines[i]
		var rid: String = str(row["recipe_id"])
		_check(failures, int(b.state.get("state", -1)) == Processor.RUNNING,
			"%s REACHABILITY CONTROL: %s should be RUNNING after one tick, got state %d — is anything ticking?" \
				% [tag, rid, int(b.state.get("state", -1))])
		_check(failures, int(b.state.get("progress", -1)) == 1,
			"%s REACHABILITY CONTROL: %s should have progress 1 after one tick, got %d" \
				% [tag, rid, int(b.state.get("progress", -1))])
		for pair in row["inputs_per_cycle"]:
			var item_type: int = int(pair[0])
			var want: int = (CYCLES - 1) * int(pair[1])
			var have: int = _bag_count(b.state.get("in_buffer", []), item_type)
			_check(failures, have == want,
				"%s REACHABILITY CONTROL: %s should have %d of input %d left after consuming one cycle, got %d" \
					% [tag, rid, want, item_type, have])

# ---------- fixture helpers ----------

## Pave the row's footprint, place the building, pre-load N cycles of inputs.
## Returns null on placement failure (already recorded as a failure).
static func _place_and_preload(world, row: Dictionary, failures: Array, tag: String) -> Building:
	var pos: Vector2i = row["pos"]
	var fp: Vector2i = row["footprint"]
	for dx in fp.x:
		for dy in fp.y:
			world.set_overlay(Vector2i(pos.x + dx, pos.y + dy), Terrain.Overlay.STONE)
	if not world.place_building(row["type"], pos):
		_check(failures, false, "%s %s: placement failed at %s (%s)" % [tag, str(row["recipe_id"]), str(pos), world.last_building_place_error])
		return null
	var b: Building = world.building_at(pos)
	if b == null:
		_check(failures, false, "%s %s: no building at %s after placement" % [tag, str(row["recipe_id"]), str(pos)])
		return null
	_preload(b, row)
	return b

## Load exactly N cycles' worth of every input and reset the machine to a fresh
## IDLE. Writing `in_buffer` directly bypasses `input_capacity`, which is why the
## 4:1 rows can hold 8 here — see the header.
static func _preload(b: Building, row: Dictionary) -> void:
	var bag: Array = []
	for pair in row["inputs_per_cycle"]:
		bag.append([int(pair[0]), CYCLES * int(pair[1])])
	b.state["in_buffer"] = bag
	b.state["out_buffer"] = []
	b.state["state"] = Processor.IDLE
	b.state["progress"] = 0

# ---------- small helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _bag_count(bag: Array, item_type: int) -> int:
	for entry in bag:
		if int(entry[0]) == item_type:
			return int(entry[1])
	return 0

## Total items in a [[type, count], ...] bag, across every type. Used so an
## output of the WRONG type cannot hide behind a zero count of the right one.
static func _bag_total(bag: Array) -> int:
	var n: int = 0
	for entry in bag:
		n += int(entry[1])
	return n

static func _cleanup(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
	world.queue_free()
