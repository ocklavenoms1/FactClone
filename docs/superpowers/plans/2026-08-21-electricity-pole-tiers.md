# Electricity Session 3 — Pole Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MEDIUM_POLE and SUBSTATION tiers to the power network by making `POLE_RANGE` and `SUPPLY_RADIUS` per-type, with an either-reaches connection rule, multi-cell pole support, nearest-pole supply tie-break, and MST wire rendering.

**Architecture:** `power_network.gd` currently hardcodes two global constants that are read from *four* places, two of which duplicate the read. This session converts them to `*_BY_TYPE` tables behind a single shared predicate (`poles_connected`) and a single shared radius accessor, adds a `_pole_cells` map so multi-cell poles resolve from any footprint cell, and replaces the O(n²) mesh wire render with a per-component minimum spanning tree.

**Tech Stack:** Godot 4.6.3, GDScript, tab-indented, `class_name` + static-method modules. Headless test runner at `res://scenes/test_runner.tscn`.

---

## Baseline and non-negotiables

**Starting state:** HEAD `b1283df`, `42 passed, 0 failed`.

This plan's code was read against `69f3cb7`. `b1283df` ("Art Pipeline Session 1") landed between the design pass and this plan, and it touched **zero** files under `scripts/` or `project.godot` — verified with `git diff --name-only 69f3cb7..b1283df -- scripts/ project.godot`, which returns nothing. Every line citation below therefore still holds, and the two commits are byte-identical for every file this session edits. Where a step below checks out a "before" version for comparison, either SHA gives the same result.

Verify before starting:

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|passed,"
```

Expected: `42 passed, 0 failed` and **zero** `Parse Error` lines.

**CRITICAL — read this before your first test run.** A GDScript compile error kills the runner *before* it prints a summary and looks **exactly like a hang**. Always grep for **both** `passed,` and `Parse Error`. Never conclude "it hung".

**CRITICAL — new `class_name` modules.** A newly added `class_name` is invisible to `--headless` runs until the global class cache is rebuilt. If you see `Identifier "X" not declared` for a file that plainly declares it, run:

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit
```

**House law (violations are defects, not style):**
- Tab indentation.
- JSON coerces ints to floats — wrap every numeric read out of dictionary/saved state in `int()`.
- Use `.get(key, default)` on dictionaries for forward-compatibility.
- No objects in `Building.state` — plain data only.
- Tick determinism: no RNG, no iteration-order dependence.
- No bare reserved method names (`get`, `set`, `has`, `connect`, `free`).
- Comment density is deliberately high. **A factually wrong comment is a real defect.** Do not write a comment you have not verified.
- **Never put the substring `"; "` inside a test failure message** — it collides with the runner's `"; ".join()` separator and splits one failure into two.

**Do not touch:** the untracked `art/` directory (a live pipeline owned elsewhere) or the `audit-hardening-stale-base` branch (a dead archive).

**Locked design decisions** (confirmed by the user, do not re-litigate):

| # | Decision |
|---|---|
| 1 | Connection rule is **either-reaches**: `chebyshev(a,b) <= max(range(a), range(b))` |
| 2 | Wire rendering becomes a **minimum spanning tree per component** |
| 3 | Substation is **2×2**, with a `_pole_cells` fix applied before saves depend on the broken version |
| 4 | Supply tie-break is **nearest pole, ties to the larger supply radius** |

**Locked numbers:**

| Tier | Wire range (Chebyshev) | Supply radius | Supply area | Footprint |
|---|---|---|---|---|
| `POWER_POLE` | 3 | 1 | 3×3 | 1×1 |
| `MEDIUM_POLE` | 6 | 2 | 5×5 | 1×1 |
| `SUBSTATION` | 11 | 4 | 9×9 | 2×2 |

Substation wire range is 11 rather than the 8 originally proposed because MST rendering decouples wire *count* from wire *range* — the K4 density complaint that forced `POLE_RANGE` from 5 down to 3 no longer applies. Supply radius stays capped at 4 because consumer-side query cost is `(2r+1)²` and every consumer pays the maximum tier's box.

---

## File structure

| File | Responsibility | Action |
|---|---|---|
| `scripts/world/buildings.gd` | `Type` enum, `DATA` rows, `make`/`draw`/`info_lines` dispatch, `POLE_TYPES` and `POWER_NETWORK_TYPES` sets | Modify |
| `scripts/world/medium_pole.gd` | Medium pole `make` + `draw` | Create |
| `scripts/world/substation.gd` | Substation `make` + `draw` (2×2) | Create |
| `scripts/world/power_pole.gd` | Basic pole; `info_lines` generalised to serve all three tiers | Modify |
| `scripts/world/power_network.gd` | `POLE_RANGE_BY_TYPE`, `SUPPLY_RADIUS_BY_TYPE`, `poles_connected`, `_pole_cells`, nearest-pole resolution | Modify |
| `scripts/world/grid_world.gd` | `_pole_cells` declaration, dirty-flag set lookup, MST wire render | Modify |
| `scripts/world/pole_tier_rig.gd` | The `--scenario=pole_tiers` layout and its MST A/B comparison block | Create |
| `scripts/main.gd` | Scenario flag arm, spawn function, key binding | Modify |
| `scripts/ui/hotbar.gd` | Two new Power-category slots (6 → 8 of 9) | Modify |
| `scripts/tests/test_pole_tiers.gd` | All new network behaviour | Create |
| `scripts/tests/test_pole_tier_rig.gd` | Rig layout + topology assertions | Create |
| `scripts/tests/test_runner.gd` | Register the two new test files | Modify |

---

## Task 1: `POWER_NETWORK_TYPES` set — kill the duplicated `or` chains

The six-type `or` chain is duplicated at `grid_world.gd:474` (place) and `grid_world.gd:495` (remove). `ELECTRIC_INSERTER` is already missing from both. Benign for a consumer (demand is rescanned every tick), **not** benign for a pole, which changes topology.

**Files:**
- Modify: `scripts/world/buildings.gd`
- Modify: `scripts/world/grid_world.gd:474`, `scripts/world/grid_world.gd:495`
- Test: `scripts/tests/test_pole_tiers.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test_pole_tiers.gd`:

```gdscript
extends RefCounted

## Pole tiers (Electricity Session 3) — parametric POLE_RANGE / SUPPLY_RADIUS,
## either-reaches connection, multi-cell poles, nearest-pole supply tie-break.
##
## Sub-case index (each task appends its own _case_* and wires it into run()):
##   1. POWER_NETWORK_TYPES membership (Task 1).

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "pole tiers (network-type set)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_network_type_set(failures)
	if failures.is_empty():
		return { "ok": true, "message": "1 sub-case passes: network-type set" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) POWER_NETWORK_TYPES — the single source of truth for "placing or
# removing this marks the power topology dirty".
#
# Previously an `or` chain duplicated at grid_world.gd:474 and :495. Two
# hand-maintained copies of one list is how a seventh type gets added to one
# and not the other; the failure is silent (the network simply never
# rebuilds) until some unrelated pole placement happens to rebuild it.
# ===========================================================================
static func _case_network_type_set(failures: Array) -> void:
	var want: Array = [
		Buildings.Type.POWER_POLE,
		Buildings.Type.WATER_WHEEL,
		Buildings.Type.ELECTRIC_LAMP,
		Buildings.Type.WINDMILL,
		Buildings.Type.STEAM_GENERATOR,
		Buildings.Type.ACCUMULATOR,
		Buildings.Type.ELECTRIC_INSERTER,
	]
	for t in want:
		_check(failures, Buildings.POWER_NETWORK_TYPES.has(t),
			"(1) POWER_NETWORK_TYPES is missing %s, so placing one would not mark the topology dirty" % Buildings.name_of(t))
	_check(failures, not Buildings.POWER_NETWORK_TYPES.has(Buildings.Type.BELT),
		"(1) POWER_NETWORK_TYPES contains BELT, which would rebuild the power topology on every belt placement")

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
```

- [ ] **Step 2: Register the test and run it to verify it fails**

Add to the `TESTS` array in `scripts/tests/test_runner.gd`, after the `test_electric_rig.gd` line:

```gdscript
	preload("res://scripts/tests/test_pole_tiers.gd"),
```

Run:

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,"
```

Expected: a `Parse Error` naming `POWER_NETWORK_TYPES` (the constant does not exist yet). That counts as the RED state for this step — the identifier is genuinely undefined.

- [ ] **Step 3: Add the set to `buildings.gd`**

Add immediately after the `DATA` dictionary's closing brace in `scripts/world/buildings.gd`:

```gdscript
## Every building type whose placement or removal changes the POWER topology
## or the supply/demand totals, and therefore must set world._power_network_dirty.
##
## Single source of truth. This replaces two hand-maintained `or` chains that
## used to live at grid_world.gd's place and remove paths. They had already
## drifted: ELECTRIC_INSERTER was in neither, which was benign only because
## consumer demand is rescanned from scratch every tick. A POLE missing from
## this set is NOT benign — topology is cached until something marks it dirty,
## so the new pole would sit inert until an unrelated pole was placed.
##
## Dictionary-as-set (Godot 4 has no built-in Set); values are ignored.
const POWER_NETWORK_TYPES: Dictionary = {
	Type.POWER_POLE: true,
	Type.MEDIUM_POLE: true,
	Type.SUBSTATION: true,
	Type.WATER_WHEEL: true,
	Type.WINDMILL: true,
	Type.STEAM_GENERATOR: true,
	Type.ACCUMULATOR: true,
	Type.ELECTRIC_LAMP: true,
	Type.ELECTRIC_INSERTER: true,
}

## The subset of POWER_NETWORK_TYPES that are POLES — the buildings that form
## network components via BFS and project a supply area. Generators and
## consumers are in POWER_NETWORK_TYPES but not here.
const POLE_TYPES: Dictionary = {
	Type.POWER_POLE: true,
	Type.MEDIUM_POLE: true,
	Type.SUBSTATION: true,
}
```

**Note:** this references `Type.MEDIUM_POLE` and `Type.SUBSTATION`, which Task 2 adds. Add the two enum entries now as part of this step so the file compiles — append them to the end of the `Type` enum, after `ELECTRIC_INSERTER`:

```gdscript
	# Electricity Arc Session 3 (session-electricity-pole-tiers): pole tiers.
	# Medium Pole — 1x1, wire range 6, supply radius 2.
	# Substation  — 2x2, wire range 11, supply radius 4. The backbone piece.
	# Both are POWER_POLE with different numbers; see POLE_RANGE_BY_TYPE and
	# SUPPLY_RADIUS_BY_TYPE in power_network.gd. Appended at the END of the
	# enum so every previously-saved type keeps its integer value.
	MEDIUM_POLE,
	SUBSTATION,
```

- [ ] **Step 4: Replace both `or` chains in `grid_world.gd`**

At `scripts/world/grid_world.gd:474`, replace:

```gdscript
	if t == Buildings.Type.POWER_POLE or t == Buildings.Type.WATER_WHEEL or t == Buildings.Type.ELECTRIC_LAMP or t == Buildings.Type.WINDMILL or t == Buildings.Type.STEAM_GENERATOR or t == Buildings.Type.ACCUMULATOR:
		_power_network_dirty = true
```

with:

```gdscript
	if Buildings.POWER_NETWORK_TYPES.has(t):
		_power_network_dirty = true
```

At `scripts/world/grid_world.gd:495`, replace:

```gdscript
	if b.type == Buildings.Type.POWER_POLE or b.type == Buildings.Type.WATER_WHEEL or b.type == Buildings.Type.ELECTRIC_LAMP or b.type == Buildings.Type.WINDMILL or b.type == Buildings.Type.STEAM_GENERATOR or b.type == Buildings.Type.ACCUMULATOR:
		_power_network_dirty = true
```

with:

```gdscript
	if Buildings.POWER_NETWORK_TYPES.has(b.type):
		_power_network_dirty = true
```

- [ ] **Step 5: Run the suite**

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,"
```

Expected: `43 passed, 0 failed`, zero `Parse Error`.

- [ ] **Step 6: Commit**

```bash
git add scripts/world/buildings.gd scripts/world/grid_world.gd scripts/tests/test_pole_tiers.gd scripts/tests/test_runner.gd
git commit -m "Pole Tiers Task 1: POWER_NETWORK_TYPES set replaces two or-chains"
```

---

## Task 2: Register both tiers as placeable buildings

Placeable and drawable, with no network behaviour yet — `rebuild_topology` still only recognises `POWER_POLE`, so these are inert. That is intentional: it makes Task 4's test genuinely RED.

**Files:**
- Create: `scripts/world/medium_pole.gd`, `scripts/world/substation.gd`
- Modify: `scripts/world/buildings.gd` (DATA rows + `make`/`draw`/`info_lines` dispatch)
- Modify: `scripts/ui/hotbar.gd:149`
- Test: `scripts/tests/test_pole_tiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test_pole_tiers.gd`, and add `_case_registration(parent, failures)` to `run()`:

```gdscript
# ===========================================================================
# (2) REGISTRATION — both tiers exist, are placeable, and carry the numbers
# the whole session's arithmetic depends on.
#
# Footprint is asserted as a LITERAL rather than read back from DATA: the
# point is to pin the design decision (substation is 2x2) independently of
# the implementation, so a silent edit to DATA reddens here.
# ===========================================================================
static func _case_registration(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rows: Array = [
		[Buildings.Type.POWER_POLE,  Vector2i(1, 1), Vector2i(5, 5),  "basic"],
		[Buildings.Type.MEDIUM_POLE, Vector2i(1, 1), Vector2i(10, 5), "medium"],
		[Buildings.Type.SUBSTATION,  Vector2i(2, 2), Vector2i(15, 5), "substation"],
	]
	for row in rows:
		var t: int = int(row[0])
		var want_fp: Vector2i = row[1]
		var pos: Vector2i = row[2]
		var label: String = String(row[3])
		_check(failures, Buildings.footprint_of(t) == want_fp,
			"(2) footprint_of(%s) should be %s, got %s" % [label, str(want_fp), str(Buildings.footprint_of(t))])
		_check(failures, Buildings.POLE_TYPES.has(t),
			"(2) POLE_TYPES is missing %s, so BFS will never treat it as a pole" % label)
		_check(failures, world.place_building(t, pos),
			"(2) placing a %s at %s failed: %s" % [label, str(pos), str(world.last_place_error)])
		var b: Building = world.building_at(pos)
		_check(failures, b != null and b.type == t,
			"(2) no %s building at %s after placement" % [label, str(pos)])
	# The substation occupies all FOUR of its cells, not just the anchor.
	# occupied is what save/load rehydrates from, so a wrong footprint here
	# silently corrupts collision after a reload.
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_check(failures, world.has_building_at(Vector2i(15, 5) + d),
			"(2) substation cell %s is not marked occupied" % str(Vector2i(15, 5) + d))
	_teardown(world)

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.generate_default_world()
	return world

static func _teardown(world) -> void:
	if world == null:
		return
	world.queue_free()
```

- [ ] **Step 2: Run to verify it fails**

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,"
```

Expected: `FAIL  pole tiers` with failures naming `footprint_of(medium)` and `footprint_of(substation)` (both return the `Vector2i(1,1)` default because no DATA row exists yet).

- [ ] **Step 3: Create `scripts/world/medium_pole.gd`**

```gdscript
class_name MediumPole
extends RefCounted

## Medium Pole — the middle wire tier (Electricity Session 3).
##
## 1x1 like the basic pole, but wire range 6 (vs 3) and supply radius 2
## (vs 1), so it covers a 5x5 area instead of 3x3. The numbers live in
## power_network.gd's POLE_RANGE_BY_TYPE / SUPPLY_RADIUS_BY_TYPE, NOT here —
## this module owns only identity and pixels.
##
## Visually distinguished from the basic pole by a taller shaft, a second
## crossarm, and a cooler grey-brown body. Both tiers must be tellable apart
## at a glance on a dense bus, which is a PAUSE 1 check.
##
## State: empty {} (network membership lives at world._pole_component).

const BODY_COLOR: Color = Color(0.45, 0.42, 0.38)        # weathered grey-brown
const POLE_COLOR: Color = Color(0.38, 0.35, 0.32)
const CROSSARM_COLOR: Color = Color(0.30, 0.28, 0.26)

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.MEDIUM_POLE, pos, {})

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var center: Vector2 = world_pos + Vector2(tile_size * 0.5, tile_size * 0.5)
	var base_size: float = float(tile_size) * 0.34
	var base_rect: Rect2 = Rect2(
		center - Vector2(base_size * 0.5, base_size * 0.5),
		Vector2(base_size, base_size)
	)
	canvas.draw_rect(base_rect, BODY_COLOR, true)
	canvas.draw_rect(base_rect, CROSSARM_COLOR, false, 1.5)
	# Taller shaft than the basic pole (0.68 vs 0.55 of a tile).
	var shaft_width: float = float(tile_size) * 0.12
	var shaft_rect: Rect2 = Rect2(
		Vector2(center.x - shaft_width * 0.5, world_pos.y + float(tile_size) * 0.04),
		Vector2(shaft_width, float(tile_size) * 0.68)
	)
	canvas.draw_rect(shaft_rect, POLE_COLOR, true)
	# TWO crossarms — the at-a-glance tell versus the basic pole's one.
	var crossarm_width: float = float(tile_size) * 0.62
	var crossarm_height: float = float(tile_size) * 0.08
	for y_frac in [0.10, 0.26]:
		var arm: Rect2 = Rect2(
			Vector2(center.x - crossarm_width * 0.5, world_pos.y + float(tile_size) * y_frac),
			Vector2(crossarm_width, crossarm_height)
		)
		canvas.draw_rect(arm, CROSSARM_COLOR, true)
```

- [ ] **Step 4: Create `scripts/world/substation.gd`**

```gdscript
class_name Substation
extends RefCounted

## Substation — the backbone wire tier (Electricity Session 3).
##
## 2x2, wire range 11, supply radius 4 (a 9x9 covered area measured from the
## FOOTPRINT, not the anchor — see PowerNetwork._pole_cells). It is the piece
## that bridges two separate pole clusters into one network.
##
## This is the project's first MULTI-CELL POLE. Every distance computation in
## power_network.gd that used to assume a pole occupies exactly one cell had
## to be taught otherwise; if you are adding a third multi-cell pole, the
## thing to re-read is _pole_cells, not this file.
##
## State: empty {} (network membership lives at world._pole_component).

const BODY_COLOR: Color = Color(0.38, 0.40, 0.46)        # cold steel-blue
const FRAME_COLOR: Color = Color(0.26, 0.28, 0.33)
const INSULATOR_COLOR: Color = Color(0.72, 0.74, 0.70)   # pale ceramic

static func make(pos: Vector2i) -> Building:
	return Building.new(Buildings.Type.SUBSTATION, pos, {})

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# Spans the full 2x2 footprint. world_pos is the ANCHOR cell's top-left,
	# so the body is 2 tiles on a side.
	var span: float = float(tile_size) * 2.0
	var inset: float = float(tile_size) * 0.18
	var body: Rect2 = Rect2(
		world_pos + Vector2(inset, inset),
		Vector2(span - inset * 2.0, span - inset * 2.0)
	)
	canvas.draw_rect(body, BODY_COLOR, true)
	canvas.draw_rect(body, FRAME_COLOR, false, 2.0)
	# Four insulators at the corners of the housing — reads as high-voltage
	# gear rather than a big box, and marks the four cells it occupies.
	var r: float = float(tile_size) * 0.13
	for corner in [Vector2(0.5, 0.5), Vector2(1.5, 0.5), Vector2(0.5, 1.5), Vector2(1.5, 1.5)]:
		canvas.draw_circle(world_pos + corner * float(tile_size), r, INSULATOR_COLOR)
```

- [ ] **Step 5: Add the DATA rows**

In `scripts/world/buildings.gd`, immediately after the `Type.POWER_POLE` DATA row (which ends at line 729):

```gdscript
	Type.MEDIUM_POLE: {
		"name": "Medium Pole",
		"swatch_color": Color(0.45, 0.42, 0.38),    # weathered grey-brown
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": false,
		# Walkable like the basic pole — player walks under the wires.
		"walkable": true,
		# No slot_layout — passive infrastructure, Q-inspect only.
	},
	Type.SUBSTATION: {
		"name": "Substation",
		"swatch_color": Color(0.38, 0.40, 0.46),    # cold steel-blue
		"footprint": Vector2i(2, 2),
		"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": false,
		# NOT walkable, unlike the two thin pole tiers — this is a 2x2 fenced
		# installation, not a post. Deliberate divergence from POWER_POLE.
		"walkable": false,
		# No slot_layout — passive infrastructure, Q-inspect only.
	},
```

- [ ] **Step 6: Add `make` / `draw` / `info_lines` dispatch**

Find the `Type.POWER_POLE:` arm in `Buildings.make` (near `buildings.gd:971`'s neighbourhood — locate it with `grep -n "Type.POWER_POLE:" scripts/world/buildings.gd`) and add alongside it:

```gdscript
		Type.MEDIUM_POLE:
			return MediumPole.make(pos)
		Type.SUBSTATION:
			return Substation.make(pos)
```

Do the same in the `draw` dispatch:

```gdscript
		Type.MEDIUM_POLE:
			MediumPole.draw(b, canvas, world_pos, tile_size)
		Type.SUBSTATION:
			Substation.draw(b, canvas, world_pos, tile_size)
```

And in the `info_lines` dispatch, route **all three** pole tiers to `PowerPole.info_lines`, which is tier-agnostic (it only reads network membership):

```gdscript
		Type.POWER_POLE, Type.MEDIUM_POLE, Type.SUBSTATION:
			return PowerPole.info_lines(b, world)
```

- [ ] **Step 7: Add the two hotbar slots**

In `scripts/ui/hotbar.gd`, inside the `"Power"` category's `slots` array, after the `ACCUMULATOR` entry at line 149:

```gdscript
			# Electricity Session 3 (session-electricity-pole-tiers): wire tiers.
			# Medium = range 6 / supply radius 2. Substation = range 11 / radius 4
			# and 2x2. Both cost more than the basic pole; the substation is the
			# piece that bridges two separate clusters into one network.
			{ "kind": "building", "value": Buildings.Type.MEDIUM_POLE },
			{ "kind": "building", "value": Buildings.Type.SUBSTATION },
```

Power category goes 6 → 8 slots. `SLOTS_PER_CATEGORY_MAX` is 9 (`hotbar.gd:49`), so this fits with one slot spare.

- [ ] **Step 8: Run the suite**

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,"
```

Expected: `43 passed, 0 failed`, zero `Parse Error`. If you get `Identifier "MediumPole" not declared`, rebuild the class cache (see the baseline section) and re-run.

- [ ] **Step 9: Commit**

```bash
git add scripts/world/medium_pole.gd scripts/world/substation.gd scripts/world/buildings.gd scripts/ui/hotbar.gd scripts/tests/test_pole_tiers.gd
git commit -m "Pole Tiers Task 2: register MEDIUM_POLE and SUBSTATION as placeable"
```

---

## Task 3: The `--scenario=pole_tiers` rig — BUILT BEFORE THE TIER LOGIC

Last session's cheapest lesson: build the rig first, so the gate is a looking exercise rather than a construction exercise. The rig cannot precede Task 2 (it places buildings that must exist), but it precedes every line of network logic. Its test will be **RED until Task 7** and that is the point — it is the scenario-level RED.

**Keep `--scenario=electric_rig` untouched.** It is the control. `test_electric_rig.gd:58` pins `EXPECTED_DEMAND = 40` and `:174` asserts satisfaction with `==` deliberately.

**Files:**
- Create: `scripts/world/pole_tier_rig.gd`
- Create: `scripts/tests/test_pole_tier_rig.gd`
- Modify: `scripts/main.gd` (scenario arm at `:342-345`, spawn function, key binding)
- Modify: `project.godot` (one new input action)
- Modify: `scripts/tests/test_runner.gd`

- [ ] **Step 1: Create `scripts/world/pole_tier_rig.gd`**

```gdscript
class_name PoleTierRig
extends RefCounted

## POLE TIER SMOKE-TEST RIG (session-electricity-pole-tiers, PAUSE 1).
##
## Two things to look at, side by side, in one screen:
##
##   NORTH BLOCK — the MIXED-TIER topology demo. Two basic-pole clusters too
##   far apart to see each other, each with its own generator and consumers,
##   plus ONE substation positioned to bridge them. Before the substation
##   exists there are two networks; with it there is one. This is what makes
##   the either-reaches rule and the substation's range 11 visible.
##
##   SOUTH BLOCK — the MST REGRESSION CONTROL. Basic poles ONLY, in the dense
##   arrangement that produced the original complaint (POLE_RANGE was cut from
##   5 to 3 at Foundation PAUSE 1 because "5-tile range produced too many
##   in-range pairs in dense layouts (K4 with 6 wires for 4 poles)").
##   Session 3 replaces mesh rendering with a minimum spanning tree, which
##   changes SHIPPED, GATE-APPROVED visuals. This block exists so the simple
##   basic-pole case can be judged against what it looked like before.
##
## Demand is pinned at exactly 40 across BOTH blocks combined, matching the
## electric rig, so the satisfaction numbers read the same and the F8 lever
## behaves identically. Composition:
##    4 x ELECTRIC_INSERTER @ Inserter.POWER_DEMAND_BY_TYPE = 5  -> 20
##   20 x ELECTRIC_LAMP     @ ElectricLamp.DEMAND           = 1  -> 20
##
## Deliberately ABSENT, and must stay absent: ACCUMULATOR (Stage 2 charge and
## discharge smears the crisp 1.00 / 0.50 / 0.00 states into ramps) and
## WINDMILL (its supply arm defaults output_active to TRUE, so one touching
## any pole on the bus silently adds 6 units and moves the midpoint off 0.50).
##
## This module owns the LAYOUT. main.gd owns the key binding and the toast.
## The power LEVER is reused verbatim from ElectricRig — the two rigs share a
## generator contract, so there is exactly one implementation of "how many
## generators have fuel" and it cannot drift between scenarios.

# Rig origin relative to the player tile at spawn time. The rig is wide and
# short so both blocks fit one 1280x720 screen without the bottom row landing
# under the hotbar strip. Measured by off-screen frame capture, not derived —
# see ElectricRig.ORIGIN_OFFSET for why arithmetic was not trusted here.
const ORIGIN_OFFSET: Vector2i = Vector2i(-13, 1)

# Phase 1 paving rectangle, INCLUSIVE, in rig-relative coordinates.
const PAVE_MIN: Vector2i = Vector2i(-1, 0)
const PAVE_MAX: Vector2i = Vector2i(27, 11)

# --- NORTH BLOCK: mixed-tier bridge demo -----------------------------------
# Cluster A basic poles at x = 0 and 3 (Chebyshev 3 apart: exactly POLE_RANGE,
# so they join). Cluster B at x = 22 and 25. The two clusters are 19 apart —
# far beyond any tier's reach. The SUBSTATION sits at x = 12, which is 12 from
# cluster A's near pole and 10 from cluster B's near pole.
#
# THE NUMBERS ARE THE TEST. Substation range is 11:
#   - to cluster B's pole at x=22: distance 10 <= 11  -> joins under EITHER rule
#   - to cluster A's pole at x=3:  distance 9  <= 11  -> joins, but ONLY because
#     either-reaches uses max(11, 3). Under a both-reaches (min) rule it would
#     need distance <= 3 and the bridge would not form.
# So the north block renders the locked design decision directly: if someone
# flips the rule to min, this rig visibly splits into two networks.
const CLUSTER_A_POLES: Array = [Vector2i(0, 2), Vector2i(3, 2)]
const CLUSTER_B_POLES: Array = [Vector2i(22, 2), Vector2i(25, 2)]
const SUBSTATION_OFFSET: Vector2i = Vector2i(12, 2)
# A medium pole at x=8, 5 from cluster A's far pole (x=3). 5 > 3 and 5 <= 6,
# so it reaches the basic pole but the basic pole cannot reach it: the
# asymmetric case, on screen.
const MEDIUM_POLE_OFFSET: Vector2i = Vector2i(8, 2)

# --- SOUTH BLOCK: MST regression control -----------------------------------
# Four basic poles in a tight square, 3 apart on both axes. Under the OLD mesh
# renderer this is the K4: all six pairs are within range, so six wires. Under
# MST it is three. This is the exact shape the user rejected at Foundation
# PAUSE 1, reproduced so the change can be judged on the case that motivated it.
const MST_CONTROL_POLES: Array = [
	Vector2i(2, 9), Vector2i(5, 9), Vector2i(2, 11), Vector2i(5, 11),
]

# Generators. Two steam generators (2x2, MAX_OUTPUT 20 each), each CARDINALLY
# TOUCHING a pole — generators use _adjacent_component_id, not the consumers'
# wireless supply area, so "near a pole" is not enough.
const GEN_A_OFFSET: Vector2i = Vector2i(0, 4)
const GEN_B_OFFSET: Vector2i = Vector2i(3, 4)

# Power-state lever values, re-exported from ElectricRig so callers need only
# one import. These are the SAME ints, not parallel definitions.
const POWER_FULL: int     = ElectricRig.POWER_FULL
const POWER_BROWNOUT: int = ElectricRig.POWER_BROWNOUT
const POWER_ZERO: int     = ElectricRig.POWER_ZERO

const EXPECTED_DEMAND: int = 40
const EXPECTED_LAMPS: int = 20
const EXPECTED_INSERTERS: int = 4

## Build the rig. Returns a dictionary with the same shape ElectricRig.build
## returns, so main.gd's spawn/adopt/toast handling is identical for both.
##
## Keys: placed, skipped, gen_anchors, substation, adopted.
static func build(world, origin: Vector2i) -> Dictionary:
	# PHASE 1 — pave the whole rectangle BEFORE placing anything.
	# can_place_building validates the FULL footprint, so the 2x2 generators
	# and the 2x2 substation need their overlay on all four cells before their
	# anchor row runs. Interleaving paving with placement makes the rig
	# seed-dependent: it would succeed or fail based on what terrain the world
	# happened to generate underneath. ElectricRig.build has the same split for
	# the same reason.
	for y in range(PAVE_MIN.y, PAVE_MAX.y + 1):
		for x in range(PAVE_MIN.x, PAVE_MAX.x + 1):
			var cell: Vector2i = origin + Vector2i(x, y)
			world.tiles[cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
			world.set_overlay(cell, Terrain.Overlay.STONE)

	# PHASE 2 — place.
	var placed: int = 0
	var skipped: int = 0
	var gen_anchors: Array = []

	for entry in _placements():
		var t: int = int(entry[0])
		var pos: Vector2i = origin + entry[1]
		if world.place_building(t, pos):
			placed += 1
			if t == Buildings.Type.STEAM_GENERATOR:
				gen_anchors.append(pos)
		else:
			skipped += 1

	# PHASE 3 — light the generators. Same contract as ElectricRig: seed
	# fuel_buffer directly and let the generator's own tick flip output_active.
	ElectricRig.apply_power_state(world, gen_anchors, POWER_FULL, true)

	return {
		"placed": placed,
		"skipped": skipped,
		"gen_anchors": gen_anchors,
		"substation": origin + SUBSTATION_OFFSET,
		"adopted": false,
	}

## The full placement list as [type, rig_relative_offset] pairs.
## Walked by build() and asserted against by test_pole_tier_rig.gd, so the
## test and the game can never disagree about what the rig contains.
static func _placements() -> Array:
	var out: Array = []
	for p in CLUSTER_A_POLES:
		out.append([Buildings.Type.POWER_POLE, p])
	for p in CLUSTER_B_POLES:
		out.append([Buildings.Type.POWER_POLE, p])
	for p in MST_CONTROL_POLES:
		out.append([Buildings.Type.POWER_POLE, p])
	out.append([Buildings.Type.MEDIUM_POLE, MEDIUM_POLE_OFFSET])
	out.append([Buildings.Type.SUBSTATION, SUBSTATION_OFFSET])
	out.append([Buildings.Type.STEAM_GENERATOR, GEN_A_OFFSET])
	out.append([Buildings.Type.STEAM_GENERATOR, GEN_B_OFFSET])
	# 4 electric inserters (5 each = 20). Placed inside cluster A and B supply
	# areas. They have no chests: they are pure LOAD. Constant demand means an
	# inserter with nothing to move still draws its full 5 — that is the
	# session-inserter-electric design decision doing work here.
	for p in [Vector2i(1, 1), Vector2i(2, 3), Vector2i(23, 1), Vector2i(24, 3)]:
		out.append([Buildings.Type.ELECTRIC_INSERTER, p])
	# 20 lamps (1 each = 20). Split across all three tiers' supply areas so
	# brownout dimming is visible next to every pole type.
	for p in _lamp_offsets():
		out.append([Buildings.Type.ELECTRIC_LAMP, p])
	return out

## The 20 lamp positions. Each must sit within the supply radius of SOME pole
## in the network or it contributes no demand and the 40 total is missed.
static func _lamp_offsets() -> Array:
	return [
		# Cluster A basic poles (radius 1): 6 lamps.
		Vector2i(0, 1), Vector2i(0, 3), Vector2i(1, 2),
		Vector2i(3, 1), Vector2i(3, 3), Vector2i(4, 2),
		# Medium pole at (8,2), radius 2: 6 lamps in its 5x5.
		Vector2i(6, 1), Vector2i(6, 3), Vector2i(7, 0),
		Vector2i(9, 0), Vector2i(10, 1), Vector2i(10, 3),
		# Substation at (12,2), 2x2, radius 4: 4 lamps well outside any
		# basic pole's reach, so they prove the wide supply area works.
		Vector2i(9, 4), Vector2i(16, 1), Vector2i(16, 4), Vector2i(12, 6),
		# Cluster B basic poles (radius 1): 4 lamps.
		Vector2i(22, 1), Vector2i(22, 3), Vector2i(25, 1), Vector2i(25, 3),
	]
```

- [ ] **Step 2: Write the rig test**

Create `scripts/tests/test_pole_tier_rig.gd`:

```gdscript
extends RefCounted

## Pole tier rig (Electricity Session 3, PAUSE 1) — the layout the human looks
## at, asserted headlessly so what the test proves and what they see cannot
## drift. Drives PoleTierRig.build, the same entry point main.gd calls.
##
## THIS TEST IS RED UNTIL TASK 7. That is deliberate: the rig is built before
## the tier logic (last session's lesson), so it is the scenario-level RED that
## Tasks 4-7 turn green. Sub-cases 3 and 4 are the ones that stay red longest.
##
## Sub-cases:
##   1. The layout lands — every placement succeeds, nothing skipped.
##   2. Demand totals EXACTLY 40, matching the electric rig's invariant.
##   3. The substation bridges: ONE network with it, TWO clusters without it.
##   4. The MST control block is a separate, basic-pole-only network.

const GridWorldScript = preload("res://scripts/world/grid_world.gd")

const RIG_ORIGIN: Vector2i = Vector2i(40, 40)

static func test_name() -> String:
	return "pole tier rig (layout lands + demand 40 + substation bridges + MST control block)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []
	_case_layout(parent, failures)
	_case_demand(parent, failures)
	_case_bridge(parent, failures)
	if failures.is_empty():
		return { "ok": true, "message": "3 sub-cases pass: layout lands + demand 40 + substation bridges" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) THE LAYOUT LANDS.
# Every satisfaction number below is downstream of the rig being fully built.
# A silent skip (terrain guard, collision) makes later assertions fail for a
# reason that has nothing to do with what they claim to test.
# ===========================================================================
static func _case_layout(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleTierRig.build(world, RIG_ORIGIN)
	var want: int = PoleTierRig._placements().size()
	_check(failures, int(rig.get("skipped", -1)) == 0,
		"(1) the rig skipped %d placements, so the layout is incomplete and every later number is wrong" % int(rig.get("skipped", -1)))
	_check(failures, int(rig.get("placed", -1)) == want,
		"(1) placed %d buildings, expected %d" % [int(rig.get("placed", -1)), want])
	_check(failures, rig.get("gen_anchors", []).size() == 2,
		"(1) expected 2 steam generators, got %d" % rig.get("gen_anchors", []).size())
	_teardown(world)

# ===========================================================================
# (2) DEMAND IS EXACTLY 40.
# Asserted with == on purpose, mirroring test_electric_rig.gd. The three lever
# positions land on 1.00 / 0.50 / 0.00 only because supply arrives in 20-unit
# blocks against a demand of exactly 40. Miss by one lamp and brownout quietly
# becomes 20/39 = 0.5128 while every test still passes.
# ===========================================================================
static func _case_demand(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	PoleTierRig.build(world, RIG_ORIGIN)
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)
	var total: int = 0
	for comp_id in _unique_components(world):
		total += PowerNetwork.demand_for(world, comp_id)
	_check(failures, total == PoleTierRig.EXPECTED_DEMAND,
		"(2) total network demand is %d, expected exactly %d — the lever's 0.50 midpoint depends on this" % [total, PoleTierRig.EXPECTED_DEMAND])
	_teardown(world)

# ===========================================================================
# (3) THE SUBSTATION BRIDGES, AND THE MST BLOCK STAYS SEPARATE.
#
# With the substation: cluster A + medium pole + substation + cluster B are
# ONE component. The MST control block (south, basic poles only, 7 tiles below)
# is a SECOND component — it is a rendering control and must not be wired into
# the main bus, or its wire count stops being comparable to the old behaviour.
#
# Without the substation: the north bus splits. Cluster A and the medium pole
# stay joined (distance 5 <= medium's 6, either-reaches), but cluster B is
# orphaned. So removing one building goes 2 components -> 3.
#
# This sub-case IS the either-reaches decision. Under a both-reaches rule the
# substation-to-cluster-A link (distance 9, basic range 3) would not form and
# the count would be wrong in the first half.
# ===========================================================================
static func _case_bridge(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var rig: Dictionary = PoleTierRig.build(world, RIG_ORIGIN)
	PowerNetwork.rebuild_topology(world)
	var with_sub: int = _unique_components(world).size()
	_check(failures, with_sub == 2,
		"(3) with the substation there should be exactly 2 components (the bridged north bus and the MST control block), got %d" % with_sub)

	# remove_building_at, NOT remove_building — grid_world.gd:483.
	world.remove_building_at(rig["substation"])
	PowerNetwork.rebuild_topology(world)
	var without_sub: int = _unique_components(world).size()
	_check(failures, without_sub == 3,
		"(3) removing the substation should orphan cluster B, giving 3 components, got %d — if this says 2 the bridge was never load-bearing" % without_sub)
	_teardown(world)

# ---------- helpers ----------

static func _unique_components(world) -> Array:
	var seen: Dictionary = {}
	for pos in world._pole_component:
		seen[int(world._pole_component[pos])] = true
	return seen.keys()

static func _make_world(parent: Node):
	var world = GridWorldScript.new()
	parent.add_child(world)
	world.generate_default_world()
	return world

static func _teardown(world) -> void:
	if world == null:
		return
	world.queue_free()

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
```

- [ ] **Step 3: Register the test and run it to confirm RED**

Add to `scripts/tests/test_runner.gd`'s `TESTS` array:

```gdscript
	preload("res://scripts/tests/test_pole_tier_rig.gd"),
```

Run:

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,"
```

Expected: `FAIL  pole tier rig` with **sub-cases 2 and 3 both failing**. `rebuild_topology` still collects only `Buildings.Type.POWER_POLE`, so:

- **Sub-case 3** fails because the medium pole and substation are invisible to BFS — the component count is wrong and the bridge does not exist.
- **Sub-case 2** fails *as a consequence*: the 10 lamps positioned inside the medium pole's and substation's supply areas resolve to no component, so they contribute no demand. The total will read **30, not 40**.

**Sub-case 1 passes** — placement itself works after Task 2.

**This is the correct RED.** Do not "fix" sub-case 2 by moving lamps next to basic poles — the lamp positions are what prove the wide supply areas work once Task 5 lands.

Record the exact failure text; Task 7's GREEN step compares against it.

- [ ] **Step 4: Wire the scenario flag into `main.gd`**

At `scripts/main.gd:342-345`, extend the existing loop:

```gdscript
	for arg in OS.get_cmdline_user_args():
		if arg == "--scenario=electric_rig":
			_spawn_electric_rig(grid_world.world_to_tile(player.global_position))
			break
		if arg == "--scenario=pole_tiers":
			_spawn_pole_tier_rig(grid_world.world_to_tile(player.global_position))
			break
```

Add the spawn function immediately after `_spawn_electric_rig` (which ends near `main.gd:1460`):

```gdscript
## Spawn the pole-tier smoke rig (Electricity Session 3, PAUSE 1).
## Mirrors _spawn_electric_rig's dedup + toast conventions exactly. The two
## rigs share ElectricRig's power lever, so F8 works on whichever is spawned.
func _spawn_pole_tier_rig(player_tile: Vector2i) -> void:
	var origin: Vector2i = player_tile + PoleTierRig.ORIGIN_OFFSET
	var rig: Dictionary = PoleTierRig.build(grid_world, origin)

	_rig_spawned = true
	_rig_origin = origin
	_rig_gen_anchors = rig["gen_anchors"]
	_rig_source_chest = Vector2i.ZERO
	_rig_source_seeded = false
	_rig_power_state = ElectricRig.POWER_FULL

	var placed: int = int(rig["placed"])
	var skipped: int = int(rig["skipped"])
	if skipped > 0:
		_show_toast("[rig] INCOMPLETE — %d of %d placed, %d skipped (collisions). F8 still cycles what got built; move and Shift+F10 for a clean one." % [placed, placed + skipped, skipped])
		return
	_show_toast("[rig] Pole tiers ready — substation at %s bridges two clusters. South block is the basic-pole MST control. F8 cycles power." % str(rig["substation"]))
```

**Note on `_rig_source_seeded = false`:** the pole-tier rig has no source chest, so the F8 handler must not try to refill one. Setting the flag false is what suppresses that — `_cycle_rig_power` already guards on it.

- [ ] **Step 5: Add the manual-spawn key**

In `project.godot`'s `[input]` section, add an action mirroring the existing `debug_spawn_electric_rig` entry byte-for-byte in shape, bound to **F7** (keycode `4194338`; verify against the documented F11 = `4194342` and F10 = `4194341`):

```
debug_spawn_pole_tier_rig={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":4194338,"physical_keycode":0,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

In `scripts/main.gd`, alongside the existing F10 gate (which sits **above** the modal early-return — keep the new one there too, or it dies whenever a panel is open):

```gdscript
	if Input.is_action_just_pressed("debug_spawn_pole_tier_rig"):
		if Input.is_key_pressed(KEY_SHIFT):
			_rig_spawned = false
			_show_toast("[rig] Rig flag cleared. Next F7 spawns fresh.")
		elif _rig_spawned:
			_show_toast("[rig] A rig already exists at %s. Shift+F7 to allow respawn." % str(_rig_origin))
		else:
			_spawn_pole_tier_rig(grid_world.world_to_tile(player.global_position))
```

- [ ] **Step 6: Verify the scenario boots and capture a frame**

```bash
mkdir -p /tmp/rigcap && ./tools/Godot_v4.6.3-stable_win64_console.exe --write-movie /tmp/rigcap/f.png --quit-after 150 --resolution 1280x720 --position 6000,6000 --path . -- --scenario=pole_tiers 2>&1 | grep -Ei "error|frames at"
```

Expected: `150 frames at 60 FPS`, zero error lines. Read `/tmp/rigcap/f00000149.png` and confirm the HUD `Buildings:` count matches `PoleTierRig._placements().size()`, and that both blocks are on screen with the bottom row clear of the hotbar strip. If the bottom row is clipped, adjust `PoleTierRig.ORIGIN_OFFSET.y` and re-capture — **measure, do not derive**.

- [ ] **Step 7: Commit**

```bash
git add scripts/world/pole_tier_rig.gd scripts/tests/test_pole_tier_rig.gd scripts/tests/test_runner.gd scripts/main.gd project.godot
git commit -m "Pole Tiers Task 3: pole_tiers rig + MST control block (RED until Task 7)"
```

---

## Task 4: Parametric tables + `poles_connected` (either-reaches) + BFS

**Files:**
- Modify: `scripts/world/power_network.gd:34-45` (constants → tables), `:88-90` (pole collection), `:104-112` (BFS predicate)
- Test: `scripts/tests/test_pole_tiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test_pole_tiers.gd`, wiring `_case_either_reaches(parent, failures)` and `_case_order_independence(parent, failures)` into `run()`:

```gdscript
# ===========================================================================
# (3) EITHER-REACHES — the locked connection rule.
#
# rule: chebyshev(a, b) <= max(range(a), range(b))
#
# A basic pole (range 3) and a medium pole (range 6) five tiles apart are
# CONNECTED, because 5 <= max(3, 6). Under a both-reaches (min) rule they
# would not be: 5 > min(3, 6) = 3. This sub-case IS the design decision, so
# it must go red if anyone flips the rule.
#
# The rule has to be SYMMETRIC or the BFS becomes a directed flood fill whose
# component grouping depends on lex start order — see sub-case 4.
# ===========================================================================
static func _case_either_reaches(parent: Node, failures: Array) -> void:
	var rows: Array = [
		# [type_a, type_b, distance, connected?, why]
		[Buildings.Type.POWER_POLE,  Buildings.Type.POWER_POLE,  3,  true,  "basic-basic at exactly range 3"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.POWER_POLE,  4,  false, "basic-basic one past range 3"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.MEDIUM_POLE, 5,  true,  "basic-medium at 5: only medium reaches, max(3,6)=6"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.MEDIUM_POLE, 7,  false, "basic-medium at 7: past both, max(3,6)=6"],
		[Buildings.Type.POWER_POLE,  Buildings.Type.SUBSTATION,  9,  true,  "basic-substation at 9: only substation reaches, max(3,11)=11"],
		[Buildings.Type.MEDIUM_POLE, Buildings.Type.SUBSTATION,  11, true,  "medium-substation at exactly 11"],
		[Buildings.Type.MEDIUM_POLE, Buildings.Type.SUBSTATION,  12, false, "medium-substation one past 11"],
	]
	for row in rows:
		var ta: int = int(row[0])
		var tb: int = int(row[1])
		var dist: int = int(row[2])
		var want: bool = bool(row[3])
		var why: String = String(row[4])
		var world = _make_world(parent)
		var pa: Vector2i = Vector2i(5, 5)
		var pb: Vector2i = Vector2i(5 + dist, 5)
		if not world.place_building(ta, pa) or not world.place_building(tb, pb):
			_check(failures, false, "(3) SETUP failed placing the pair for case: %s" % why)
			_teardown(world)
			continue
		PowerNetwork.rebuild_topology(world)
		var same: bool = int(world._pole_component.get(pa, -1)) == int(world._pole_component.get(pb, -2))
		_check(failures, same == want,
			"(3) %s: expected connected=%s, got %s" % [why, str(want), str(same)])
		_teardown(world)

# ===========================================================================
# (4) ORDER INDEPENDENCE — the trap a directed predicate falls into.
#
# If the BFS predicate is `dist <= range_of(the pole being expanded from)`
# rather than a symmetric max(), the pole graph becomes DIRECTED. Flood fill
# over a directed graph produces components that depend on which node the walk
# starts from, and rebuild_topology sorts its start points lex
# (power_network.gd:91). The result would be deterministic but ARBITRARY:
# whether two poles share a network would hinge on which had the smaller
# (x, y). Tests using one placement order would pass; the mirrored layout
# would behave differently.
#
# This builds the same three poles twice in mirrored order and asserts the
# GROUPING is identical, not merely that ids match (ids are assigned by walk
# order and are expected to differ).
# ===========================================================================
static func _case_order_independence(parent: Node, failures: Array) -> void:
	var basic: Vector2i = Vector2i(5, 5)
	var medium: Vector2i = Vector2i(10, 5)
	var far: Vector2i = Vector2i(30, 5)

	var forward = _make_world(parent)
	forward.place_building(Buildings.Type.POWER_POLE, basic)
	forward.place_building(Buildings.Type.MEDIUM_POLE, medium)
	forward.place_building(Buildings.Type.POWER_POLE, far)
	PowerNetwork.rebuild_topology(forward)
	var f_joined: bool = int(forward._pole_component.get(basic, -1)) == int(forward._pole_component.get(medium, -2))
	var f_far: bool = int(forward._pole_component.get(basic, -1)) == int(forward._pole_component.get(far, -2))
	_teardown(forward)

	var reverse = _make_world(parent)
	reverse.place_building(Buildings.Type.POWER_POLE, far)
	reverse.place_building(Buildings.Type.MEDIUM_POLE, medium)
	reverse.place_building(Buildings.Type.POWER_POLE, basic)
	PowerNetwork.rebuild_topology(reverse)
	var r_joined: bool = int(reverse._pole_component.get(basic, -1)) == int(reverse._pole_component.get(medium, -2))
	var r_far: bool = int(reverse._pole_component.get(basic, -1)) == int(reverse._pole_component.get(far, -2))
	_teardown(reverse)

	_check(failures, f_joined == r_joined,
		"(4) basic and medium group differently depending on placement order (forward=%s reverse=%s), which means the connection predicate is not symmetric" % [str(f_joined), str(r_joined)])
	_check(failures, f_far == r_far,
		"(4) the far pole groups differently depending on placement order (forward=%s reverse=%s)" % [str(f_far), str(r_far)])
	_check(failures, f_joined,
		"(4) basic at %s and medium at %s are 5 apart and should be connected under either-reaches" % [str(basic), str(medium)])
```

- [ ] **Step 2: Run to verify it fails**

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,"
```

Expected: `FAIL  pole tiers` on sub-case 3's medium and substation rows — those poles are not collected by `rebuild_topology` at all yet, so both sides read `-1`/`-2` and never match.

- [ ] **Step 3: Replace the constants with tables**

In `scripts/world/power_network.gd`, replace lines 27-45 (the `POLE_RANGE` and `SUPPLY_RADIUS` const blocks) with:

```gdscript
# Per-tier maximum Chebyshev distance for pole-to-pole auto-connection.
#
# The basic pole's 3 is a PAUSE 1 user decision, reduced from 5 because
# "5-tile range produced too many in-range pairs in dense layouts (K4 with 6
# wires for 4 poles)". That complaint was about WIRE COUNT, and Session 3
# removed its cause by rendering a minimum spanning tree per component instead
# of a full mesh — which is why the substation can afford 11 without
# reintroducing the hairball.
#
# Lookup miss returns POLE_RANGE_DEFAULT, so a future pole tier that forgets
# its row behaves like a basic pole rather than failing to connect at all.
const POLE_RANGE_BY_TYPE: Dictionary = {
	Buildings.Type.POWER_POLE:  3,
	Buildings.Type.MEDIUM_POLE: 6,
	Buildings.Type.SUBSTATION:  11,
}
const POLE_RANGE_DEFAULT: int = 3

# Per-tier supply-area Chebyshev radius for CONSUMERS (Factorio-style
# wireless supply). Radius r covers a (2r+1) square centred on the pole's
# FOOTPRINT — see _pole_cells for why footprint and not anchor.
#
# WHY THESE STOP AT 4. The lookup is consumer-outward: a consumer scans a box
# around ITSELF and asks what poles are in it (power_satisfaction_at), because
# it cannot know in advance which tier might be covering it. That means every
# consumer pays the box of the LARGEST tier on the map, every tick, even where
# no substation exists. Cost is (2r+1)^2: radius 1 is 9 checks, radius 4 is 81,
# radius 7 would be 225. 4 is the affordability ceiling, not a balance choice.
const SUPPLY_RADIUS_BY_TYPE: Dictionary = {
	Buildings.Type.POWER_POLE:  1,
	Buildings.Type.MEDIUM_POLE: 2,
	Buildings.Type.SUBSTATION:  4,
}
const SUPPLY_RADIUS_DEFAULT: int = 1

# The widest supply radius any tier declares. Consumer-side scans must size
# their box to THIS and then filter per-pole, because the consumer does not
# know what tier will answer. Derived at first use rather than hardcoded so it
# cannot drift from the table above.
static var _max_supply_radius_cache: int = -1

## Widest supply radius across all pole tiers. Consumer-side scan box size.
static func max_supply_radius() -> int:
	if _max_supply_radius_cache < 0:
		var m: int = SUPPLY_RADIUS_DEFAULT
		for t in SUPPLY_RADIUS_BY_TYPE:
			m = max(m, int(SUPPLY_RADIUS_BY_TYPE[t]))
		_max_supply_radius_cache = m
	return _max_supply_radius_cache

## Wire range for one pole type.
static func pole_range(t: int) -> int:
	return int(POLE_RANGE_BY_TYPE.get(t, POLE_RANGE_DEFAULT))

## Supply radius for one pole type.
static func supply_radius(t: int) -> int:
	return int(SUPPLY_RADIUS_BY_TYPE.get(t, SUPPLY_RADIUS_DEFAULT))

## THE connection predicate — the single source of truth for "are these two
## poles wired together". Called by BOTH rebuild_topology's BFS and
## grid_world._draw_power_wires. That sharing is the entire point: these used
## to be two independent reads of one constant (power_network.gd:111 and
## grid_world.gd:1672), and with per-type ranges two reads WILL diverge.
##
## The divergence is dangerous in one direction specifically. If the renderer
## is STRICTER than the BFS, poles are in one component but no wire is drawn —
## an invisible connection, with no test or visual signal. (Looser is caught by
## the renderer's same-component guard.) One predicate makes that unreachable.
##
## RULE: EITHER-REACHES — chebyshev(a, b) <= max(range(a), range(b)).
## Symmetric, so the BFS stays an undirected flood fill and component grouping
## cannot depend on lex start order. It also mirrors the asymmetry the project
## already chose for consumers: a pole reaches OUT to things that do not reach
## back. A min() rule would cap a substation talking to basic poles at the
## basic pole's 3, making the backbone tier useless in mixed networks.
static func poles_connected(world, anchor_a: Vector2i, anchor_b: Vector2i) -> bool:
	if anchor_a == anchor_b:
		return false
	var ba: Building = world.buildings.get(anchor_a, null)
	var bb: Building = world.buildings.get(anchor_b, null)
	if ba == null or bb == null:
		return false
	if not Buildings.POLE_TYPES.has(ba.type) or not Buildings.POLE_TYPES.has(bb.type):
		return false
	var reach: int = max(pole_range(ba.type), pole_range(bb.type))
	return _pole_distance(ba, bb) <= reach

## Chebyshev distance between two poles, measured FOOTPRINT to FOOTPRINT
## rather than anchor to anchor.
##
## For 1x1 poles these are identical. For the 2x2 substation, anchor-to-anchor
## under-measures by up to 1 per axis depending on which side the other pole
## sits — so a substation would reach further "up-left" than "down-right",
## which is invisible in tests built around a single orientation and obvious
## on screen. Footprint-to-footprint is orientation-independent.
static func _pole_distance(a: Building, b: Building) -> int:
	var fa: Vector2i = Buildings.footprint_of(a.type)
	var fb: Vector2i = Buildings.footprint_of(b.type)
	var dx: int = max(0, max(a.anchor.x - (b.anchor.x + fb.x - 1), b.anchor.x - (a.anchor.x + fa.x - 1)))
	var dy: int = max(0, max(a.anchor.y - (b.anchor.y + fb.y - 1), b.anchor.y - (a.anchor.y + fa.y - 1)))
	return max(dx, dy)
```

- [ ] **Step 4: Teach the BFS about all pole tiers**

In `rebuild_topology`, replace the pole-collection block at lines 87-91:

```gdscript
	var pole_anchors: Array = []
	for anchor in world.buildings:
		if world.buildings[anchor].type == Buildings.Type.POWER_POLE:
			pole_anchors.append(anchor)
	pole_anchors.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
```

with:

```gdscript
	var pole_anchors: Array = []
	for anchor in world.buildings:
		if Buildings.POLE_TYPES.has(world.buildings[anchor].type):
			pole_anchors.append(anchor)
	pole_anchors.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
```

And replace the BFS in-range check at lines 103-112:

```gdscript
			# Find all poles within POLE_RANGE Chebyshev distance.
			for other in pole_anchors:
				if other == p:
					continue
				if world._pole_component.has(other):
					continue
				var dx: int = abs(other.x - p.x)
				var dy: int = abs(other.y - p.y)
				if max(dx, dy) <= POLE_RANGE:
					queue.append(other)
```

with:

```gdscript
			# Find all poles this one is wired to. poles_connected is the
			# SHARED predicate — grid_world._draw_power_wires calls the same
			# function, so the graph the BFS builds and the graph the renderer
			# draws cannot disagree.
			for other in pole_anchors:
				if world._pole_component.has(other):
					continue
				if PowerNetwork.poles_connected(world, p, other):
					queue.append(other)
```

(The `other == p` guard is now redundant — `poles_connected` returns false for identical anchors — but leaving it out is fine because `p` is already in `_pole_component` by this line and the `has(other)` guard catches it.)

- [ ] **Step 5: Keep the two consumer paths compiling**

Deleting the `SUPPLY_RADIUS` const breaks its two remaining readers — `_supply_component_id` (`power_network.gd:293`) and `power_satisfaction_at` (`:334`) — with `Identifier "SUPPLY_RADIUS" not declared`. Task 5 rewrites both properly; this step is the bridge so Task 4 lands green on its own.

In **both** functions, change:

```gdscript
	var radius: int = SUPPLY_RADIUS
```

to:

```gdscript
	# TEMPORARY (Task 4 -> Task 5): the consumer-side scan is still sized to
	# the basic pole's radius and still takes the first pole it hits. That is
	# behaviourally IDENTICAL to pre-Session-3, so the existing suite stays
	# green — but it means MEDIUM_POLE and SUBSTATION connect to the network
	# without yet projecting their wider supply areas. Task 5 replaces both of
	# these functions with the per-pole-radius resolver.
	var radius: int = SUPPLY_RADIUS_DEFAULT
```

**Do not use `max_supply_radius()` here.** A wider box with first-hit-wins would power consumers 4 tiles from a *basic* pole, which changes shipped behaviour and reddens `test_power_network.gd` and `test_electric_rig.gd` for a reason unrelated to this task.

- [ ] **Step 6: Run the suite**

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,"
```

Expected:

- `pole tiers` sub-cases 3 and 4 **pass** — the connection rule is live.
- `pole tier rig` sub-case 3 **passes** — the substation now bridges the two clusters.
- `pole tier rig` sub-case 2 **still fails at demand 30, not 40.** This is correct and expected: Step 5's bridge keeps the consumer scan at the basic pole's radius 1, so the 10 lamps sitting in the medium pole's and substation's wider areas still resolve to no component. Task 5 is what closes this. Do not chase it here.
- `test_power_network.gd` must stay **fully green** — it asserts basic-pole behaviour at range 3, unchanged by this task.

If `test_power_network.gd` or `test_electric_rig.gd` reddens, **stop and report**: basic-pole or exact-satisfaction behaviour changed, which is out of scope for this task and means the Step 5 bridge was written with `max_supply_radius()` instead of `SUPPLY_RADIUS_DEFAULT`.

- [ ] **Step 7: Commit**

```bash
git add scripts/world/power_network.gd scripts/tests/test_pole_tiers.gd
git commit -m "Pole Tiers Task 4: parametric ranges + shared either-reaches predicate"
```

---

## Task 5: `_pole_cells` — multi-cell poles resolve from any footprint cell

`_pole_component` is keyed by **anchor only** (`power_network.gd:88-90`, `:102`), but the two consumer query paths test raw cells against it (`:306`, `:338`). A 2×2 substation therefore answers only from its top-left cell, making its supply box off-centre.

**Files:**
- Modify: `scripts/world/grid_world.gd:219` (declare `_pole_cells`)
- Modify: `scripts/world/power_network.gd` (`rebuild_topology`, `_supply_component_id`, `power_satisfaction_at`)
- Test: `scripts/tests/test_pole_tiers.gd`

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/test_pole_tiers.gd`, wiring `_case_multicell_supply(parent, failures)` into `run()`:

```gdscript
# ===========================================================================
# (5) MULTI-CELL SUPPLY SYMMETRY.
#
# A 2x2 substation at anchor (10,10) occupies (10,10)..(11,11). With supply
# radius 4, coverage must extend 4 tiles beyond the FOOTPRINT in every
# direction: x from 6 to 15, y from 6 to 15.
#
# The bug this catches: _pole_component holds only the ANCHOR, so a raw-cell
# lookup finds the substation only at (10,10). Coverage would then run
# (6..14, 6..14) — correct on the anchor side, one short on the far side. The
# FAR EDGE is the direction that fails, so it is asserted explicitly. A test
# that only probed left and up would pass against the broken code.
# ===========================================================================
static func _case_multicell_supply(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var anchor: Vector2i = Vector2i(10, 10)
	if not world.place_building(Buildings.Type.SUBSTATION, anchor):
		_check(failures, false, "(5) SETUP: could not place the substation at %s" % str(anchor))
		_teardown(world)
		return
	# A generator so the component has nonzero satisfaction; without supply,
	# power_satisfaction_at returns 0.0 for "covered" and "not covered" alike
	# and the sub-case would prove nothing.
	world.place_building(Buildings.Type.STEAM_GENERATOR, Vector2i(12, 10))
	var gen: Building = world.building_at(Vector2i(12, 10))
	if gen != null:
		gen.state["fuel_buffer"] = 16
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)

	# Inside on the FAR side (anchor + footprint - 1 + radius = 11 + 4 = 15).
	var inside: Array = [
		Vector2i(15, 10), Vector2i(10, 15), Vector2i(15, 15),   # far edges
		Vector2i(6, 10), Vector2i(10, 6),                       # near edges
	]
	for pos in inside:
		_check(failures, PowerNetwork.power_satisfaction_at(world, pos) > 0.0,
			"(5) %s is within the substation's radius-4 area measured from its 2x2 footprint and should be powered" % str(pos))
	# Just outside on every side.
	var outside: Array = [Vector2i(16, 10), Vector2i(10, 16), Vector2i(5, 10), Vector2i(10, 5)]
	for pos in outside:
		_check(failures, PowerNetwork.power_satisfaction_at(world, pos) == 0.0,
			"(5) %s is one tile past the substation's supply area and must NOT be powered" % str(pos))
	_teardown(world)
```

- [ ] **Step 2: Run to verify it fails**

Expected: `FAIL  pole tiers` on `(5) (15, 10) is within ...` and `(5) (10, 15) is within ...` — the far edges — while the near edges pass. That asymmetry is the signature of the anchor-only bug.

- [ ] **Step 3: Declare `_pole_cells` on the world**

In `scripts/world/grid_world.gd`, immediately after line 219's `_pole_component` declaration:

```gdscript
var _pole_cells: Dictionary = {}                  # Vector2i (any pole footprint cell) → Vector2i (that pole's anchor)
```

- [ ] **Step 4: Populate it in `rebuild_topology`**

Add `world._pole_cells.clear()` alongside the other clears at the top of `rebuild_topology` (after `world._pole_component.clear()`), and populate it in the BFS assignment. Replace:

```gdscript
				world._pole_component[p] = next_id
```

with:

```gdscript
				world._pole_component[p] = next_id
				# Index EVERY footprint cell back to this anchor. Consumer
				# queries hit raw cells and cannot know a 2x2 substation's
				# anchor, so without this map a multi-cell pole answers only
				# from its top-left cell and its supply box sits off-centre.
				var pole_fp: Vector2i = Buildings.footprint_of(world.buildings[p].type)
				for fy in range(pole_fp.y):
					for fx in range(pole_fp.x):
						world._pole_cells[p + Vector2i(fx, fy)] = p
```

- [ ] **Step 5: Rewrite `power_satisfaction_at` for per-pole radius**

Replace `power_satisfaction_at` (`power_network.gd:331-342`) entirely:

```gdscript
## Public query: per-tile satisfaction for consumers. Returns 0.0 if no pole
## covers `pos`. Returns [0.0, 1.0] otherwise.
##
## Session 3 changed the shape of this scan, not just its numbers. Supply
## radius is a property of the POLE, but this lookup runs from the CONSUMER's
## position, which cannot know in advance which tier might be covering it. So
## the box is sized to max_supply_radius() and each candidate is then filtered
## by ITS OWN radius. A pole whose radius is smaller than the box is found and
## rejected; that rejection is the per-type behaviour.
##
## Tie-break when two poles cover the same tile: NEAREST wins, ties to the
## LARGER supply radius. With radii of 1 and 4 the overlap case stopped being
## a corner case, and the pre-Session-3 behaviour (first cell hit by the scan
## order) was arbitrary and undocumented.
static func power_satisfaction_at(world, pos: Vector2i) -> float:
	if world._power_network_dirty:
		rebuild_topology(world)
	var comp_id: int = _covering_component_id(world, pos)
	if comp_id < 0:
		return 0.0
	return float(world._component_satisfaction.get(comp_id, 0.0))

## Resolve which pole component covers `pos`, applying the nearest-pole
## tie-break. Returns -1 if nothing covers it.
##
## NOTE: this cannot early-return on the first hit, because a nearer pole may
## appear later in the scan order. It evaluates every candidate in the box and
## picks. Task 6 measured that cost; see the benchmark sub-case in
## test_pole_tiers.gd for the number and the reasoning.
static func _covering_component_id(world, pos: Vector2i) -> int:
	var radius: int = max_supply_radius()
	var best_comp: int = -1
	var best_dist: int = 0x7FFFFFFF
	var best_radius: int = -1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell: Vector2i = pos + Vector2i(dx, dy)
			if not world._pole_cells.has(cell):
				continue
			var anchor: Vector2i = world._pole_cells[cell]
			if not world._pole_component.has(anchor):
				continue
			var pole: Building = world.buildings.get(anchor, null)
			if pole == null or not Buildings.POLE_TYPES.has(pole.type):
				continue
			# Chebyshev from the consumer tile to the nearest cell of this
			# pole's footprint — abs(dx/dy) of the cell we just matched.
			var dist: int = max(abs(dx), abs(dy))
			var r: int = supply_radius(pole.type)
			if dist > r:
				continue
			# Nearest wins; ties go to the larger supply radius. Both keys are
			# deterministic, so no iteration-order dependence survives.
			if dist < best_dist or (dist == best_dist and r > best_radius):
				best_dist = dist
				best_radius = r
				best_comp = int(world._pole_component[anchor])
	return best_comp
```

- [ ] **Step 6: Route `_supply_component_id` through the same resolver**

Replace `_supply_component_id` (`power_network.gd:292-315`) entirely:

```gdscript
## Find the component ID covering building `b`, checking every cell of its
## footprint. Used by CONSUMERS (lamps, electric inserters). Returns -1 if no
## pole covers any of its cells.
##
## Delegates to _covering_component_id so multi-cell consumers and multi-cell
## POLES share one implementation of the radius filter and the nearest-pole
## tie-break. Before Session 3 this duplicated the scan loop with its own
## first-hit-wins rule, which is exactly how the two paths would drift.
static func _supply_component_id(world, b: Building) -> int:
	var fp: Vector2i = Buildings.footprint_of(b.type)
	for fy in range(fp.y):
		for fx in range(fp.x):
			var comp_id: int = _covering_component_id(world, b.anchor + Vector2i(fx, fy))
			if comp_id >= 0:
				return comp_id
	return -1
```

- [ ] **Step 7: Run the suite**

Expected:

- `pole tiers` sub-case 5 **passes** — multi-cell supply is symmetric.
- `pole tier rig` sub-case 2 **finally passes at demand 40** — the lamps in the medium pole's and substation's areas now resolve to a component. This is the task that closes the gap Task 4 left open, so the rig test should now be green except for anything MST-dependent.
- **`test_electric_rig.gd` and `test_electric_inserter.gd` must both stay green.** They assert exact satisfaction values through this exact code path, so a regression here surfaces there first. `test_electric_rig.gd` in particular asserts satisfaction with `==` rather than `is_equal_approx`, deliberately — if the nearest-pole tie-break has changed which component a rig consumer resolves to, that is where you will see it.

- [ ] **Step 8: Commit**

```bash
git add scripts/world/grid_world.gd scripts/world/power_network.gd scripts/tests/test_pole_tiers.gd
git commit -m "Pole Tiers Task 5: _pole_cells + nearest-pole supply resolution"
```

---

## Task 6: Measure the nearest-pole cost — **USER GATE if significant**

The tie-break removed the early return: `_covering_component_id` now evaluates every candidate in a box that also grew from 3×3 to 9×9. Worst case went from ~1 check to 81. This task measures the real per-consumer-per-tick cost and reports it.

**Files:**
- Test: `scripts/tests/test_pole_tiers.gd`

- [ ] **Step 1: Write the benchmark sub-case**

Append to `scripts/tests/test_pole_tiers.gd`, wiring `_case_supply_scan_cost(parent, failures)` into `run()`:

```gdscript
# ===========================================================================
# (6) SUPPLY-SCAN COST.
#
# Session 3 made this scan strictly more expensive in two independent ways:
#   - the box grew from (2*1+1)^2 = 9 cells to (2*4+1)^2 = 81
#   - the nearest-pole tie-break removed the early return, so all 81 are
#     evaluated rather than stopping at the first hit
#
# power_satisfaction_at is called by every electric consumer every tick, so
# this is a per-consumer-per-tick cost, not a one-off.
#
# This sub-case is a REGRESSION TRIPWIRE, not a pass/fail benchmark. The
# threshold is deliberately loose — it exists to catch an accidental
# order-of-magnitude change (e.g. someone making the scan allocate), not to
# police microseconds. Machine-speed variance must not redden the suite.
# ===========================================================================
const SCAN_BENCH_CONSUMERS: int = 200
const SCAN_BENCH_ITERATIONS: int = 50
# 200 consumers x 50 iterations = 10000 calls. At 20 TPS a frame budget is
# 50 ms; a realistic map has far fewer than 200 electric consumers. Anything
# under 500 ms for 10000 calls is comfortably inside budget with headroom.
const SCAN_BENCH_BUDGET_MS: int = 500

static func _case_supply_scan_cost(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	# Worst realistic case: a substation (largest box) with a dense field of
	# consumer tiles inside its area, so every call does the full scan AND
	# finds candidates it must compare rather than bailing early.
	world.place_building(Buildings.Type.SUBSTATION, Vector2i(20, 20))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(24, 20))
	world.place_building(Buildings.Type.MEDIUM_POLE, Vector2i(18, 24))
	PowerNetwork.rebuild_topology(world)
	PowerNetwork.update_supply_demand(world)

	var probes: Array = []
	for i in SCAN_BENCH_CONSUMERS:
		probes.append(Vector2i(16 + (i % 10), 16 + int(i / 10.0) % 10))

	var start_usec: int = Time.get_ticks_usec()
	for _iter in SCAN_BENCH_ITERATIONS:
		for p in probes:
			PowerNetwork.power_satisfaction_at(world, p)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0

	var calls: int = SCAN_BENCH_CONSUMERS * SCAN_BENCH_ITERATIONS
	_check(failures, elapsed_ms < float(SCAN_BENCH_BUDGET_MS),
		"(6) %d power_satisfaction_at calls took %.1f ms, past the %d ms tripwire — the supply scan has regressed by roughly an order of magnitude, not by a little" % [calls, elapsed_ms, SCAN_BENCH_BUDGET_MS])
	# Always report the number, pass or fail. The point of this sub-case is the
	# measurement; a silent pass tells the next reader nothing.
	print("[bench] power_satisfaction_at: %d calls in %.1f ms (%.1f us/call)" % [calls, elapsed_ms, elapsed_ms * 1000.0 / float(calls)])
	_teardown(world)
```

- [ ] **Step 2: Run and record the number**

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --headless --path . res://scenes/test_runner.tscn 2>&1 | grep -E "Parse Error|FAIL|passed,|\[bench\]"
```

Record the printed `us/call` figure.

- [ ] **Step 3: Compare against the pre-Session-3 baseline**

Stash the working tree, check out `69f3cb7`, and run the same benchmark shape against the old first-hit-wins scan to get the "before" number:

```bash
git stash && git checkout 69f3cb7 -- scripts/world/power_network.gd
```

Re-run, record, then restore:

```bash
git checkout HEAD -- scripts/world/power_network.gd && git stash pop
```

- [ ] **Step 4: USER GATE — report the comparison**

Report to the user:
- microseconds per call, before and after
- the multiplier
- the projected cost at a realistic consumer count (the pole-tier rig has 24 electric consumers; the electric rig has 24)
- whether it is a meaningful fraction of the 50 ms tick budget

**If the increase is significant, STOP and surface it.** The user's instruction: *"if it's significant, surface it and we'll reconsider the tie-break."* Do not proceed to Task 7 on your own judgement — the fallback is first-hit-wins with a documented scan order, which is a one-function revert of `_covering_component_id`'s comparison block.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/test_pole_tiers.gd
git commit -m "Pole Tiers Task 6: supply-scan cost tripwire + measured baseline"
```

---

## Task 7: MST wire rendering + shared predicate in the renderer

**Files:**
- Modify: `scripts/world/grid_world.gd:1645-1683` (`_draw_power_wires`)
- Test: `scripts/tests/test_pole_tiers.gd`

- [ ] **Step 1: Write the failing test**

The renderer draws directly to a canvas, so the testable unit is the **edge list**. Extract it as a pure function and test that. Append to `scripts/tests/test_pole_tiers.gd`, wiring `_case_mst_edges(parent, failures)` into `run()`:

```gdscript
# ===========================================================================
# (7) MST WIRE EDGES.
#
# Two claims:
#   (a) A component of N poles produces EXACTLY N-1 wires. That is what makes
#       wire count independent of wire range, which is what lets the
#       substation afford range 11 without the K4 hairball that forced
#       POLE_RANGE down from 5 to 3 at Foundation PAUSE 1.
#   (b) Every emitted edge satisfies poles_connected. The renderer must never
#       draw a wire the BFS would not have walked, and must never omit one it
#       did — pre-Session-3 these were two independent reads of one constant
#       (power_network.gd:111 and grid_world.gd:1672).
#
# The K4 square is the exact shape from the original complaint: four poles,
# all six pairs in range. Mesh drew 6 wires; MST draws 3.
# ===========================================================================
static func _case_mst_edges(parent: Node, failures: Array) -> void:
	var world = _make_world(parent)
	var square: Array = [Vector2i(5, 5), Vector2i(8, 5), Vector2i(5, 8), Vector2i(8, 8)]
	for p in square:
		world.place_building(Buildings.Type.POWER_POLE, p)
	PowerNetwork.rebuild_topology(world)

	var edges: Array = PowerNetwork.wire_edges(world)
	_check(failures, edges.size() == 3,
		"(7) four mutually-in-range poles should yield 3 MST wires, got %d (6 means the mesh renderer is still in place)" % edges.size())

	# Every edge must be a real connection.
	for e in edges:
		_check(failures, PowerNetwork.poles_connected(world, e[0], e[1]),
			"(7) the renderer emitted a wire between %s and %s that poles_connected rejects" % [str(e[0]), str(e[1])])

	# Every pole must appear in at least one edge — an MST spans its component,
	# so an isolated pole inside a multi-pole component means a broken tree.
	var touched: Dictionary = {}
	for e in edges:
		touched[e[0]] = true
		touched[e[1]] = true
	for p in square:
		_check(failures, touched.has(p),
			"(7) pole %s appears in no wire, so the spanning tree does not span its component" % str(p))

	# A second, disconnected component contributes its own N-1.
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(40, 40))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(43, 40))
	PowerNetwork.rebuild_topology(world)
	_check(failures, PowerNetwork.wire_edges(world).size() == 4,
		"(7) 4-pole component (3 wires) plus a 2-pole component (1 wire) should total 4, got %d" % PowerNetwork.wire_edges(world).size())
	_teardown(world)
```

- [ ] **Step 2: Run to verify it fails**

Expected: `Parse Error` naming `wire_edges` (the function does not exist yet). That is the RED.

- [ ] **Step 3: Add `wire_edges` to `power_network.gd`**

Append to `scripts/world/power_network.gd`:

```gdscript
## The wire edge list: one minimum spanning tree per network component.
## Returns an Array of [anchor_a, anchor_b] pairs.
##
## WHY A TREE AND NOT A MESH. Before Session 3 the renderer drew every
## in-range pair inside a component — O(n^2) wires. That is what forced
## POLE_RANGE down from 5 to 3 at Foundation PAUSE 1: "5-tile range produced
## too many in-range pairs in dense layouts (K4 with 6 wires for 4 poles)".
## Per-type ranges would have reintroduced that at several times the scale,
## because a substation at range 11 is in range of nearly every pole around
## it and either-reaches means the link forms regardless of the small pole's
## reach. A spanning tree makes wire count N-1 no matter the range, which is
## what lets the substation afford 11.
##
## Prim's algorithm, weighted by pole-to-pole Chebyshev distance so the tree
## prefers short local hops and uses a long substation span only where nothing
## shorter joins the two halves — which is exactly where a long wire is
## informative rather than noise.
##
## DETERMINISM: candidate poles are walked in lex-sorted order and ties in
## distance are broken by that order, so the same layout always yields the
## same tree. Tick determinism is house law and the renderer is not exempt —
## a tree that reshuffled between frames would shimmer.
static func wire_edges(world) -> Array:
	if world._power_network_dirty:
		rebuild_topology(world)
	# Group pole anchors by component, lex-sorted for determinism.
	var by_comp: Dictionary = {}
	for anchor in world._pole_component:
		var cid: int = int(world._pole_component[anchor])
		if not by_comp.has(cid):
			by_comp[cid] = []
		by_comp[cid].append(anchor)

	var edges: Array = []
	var comp_ids: Array = by_comp.keys()
	comp_ids.sort()
	for cid in comp_ids:
		var poles: Array = by_comp[cid]
		poles.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
		if poles.size() < 2:
			continue
		# Prim's: grow a tree from the lex-first pole.
		var in_tree: Array = [poles[0]]
		var remaining: Array = poles.slice(1)
		while not remaining.is_empty():
			var best_i: int = -1
			var best_from: Vector2i = in_tree[0]
			var best_dist: int = 0x7FFFFFFF
			for i in remaining.size():
				for from_anchor in in_tree:
					if not poles_connected(world, from_anchor, remaining[i]):
						continue
					var a: Building = world.buildings.get(from_anchor, null)
					var b: Building = world.buildings.get(remaining[i], null)
					if a == null or b == null:
						continue
					var d: int = _pole_distance(a, b)
					if d < best_dist:
						best_dist = d
						best_i = i
						best_from = from_anchor
			if best_i < 0:
				# Nothing left reaches the tree. Cannot happen for a component
				# the BFS built with this same predicate, but bailing beats
				# looping forever if the two ever disagree.
				break
			edges.append([best_from, remaining[best_i]])
			in_tree.append(remaining[best_i])
			remaining.remove_at(best_i)
	return edges
```

- [ ] **Step 4: Rewrite `_draw_power_wires` to consume the edge list**

Replace the body of `_draw_power_wires` (`grid_world.gd:1645-1683`) from the `poles_by_comp` block onward:

```gdscript
func _draw_power_wires() -> void:
	if _power_network_dirty:
		PowerNetwork.rebuild_topology(self)
	# Colors named for the network state they represent, not for the hue.
	const WIRE_THICKNESS: float = 2.0
	var WIRE_COLOR_LIVE: Color = Color(0.85, 0.70, 0.40)    # golden — network has power
	var WIRE_COLOR_DEAD: Color = Color(0.30, 0.22, 0.15)    # dark brown — no supply
	# Session 3: the edge list is a minimum spanning tree per component,
	# computed by PowerNetwork.wire_edges. The renderer no longer decides
	# which poles are connected — it used to re-derive that from POLE_RANGE
	# independently of the BFS (the old line here read
	# `if max(dx, dy) > PowerNetwork.POLE_RANGE: continue`), and with per-type
	# ranges two independent derivations WILL diverge. The dangerous direction
	# is a renderer stricter than the BFS: poles in one component with no wire
	# drawn, which produces an invisible connection and no test signal.
	for edge in PowerNetwork.wire_edges(self):
		var pa: Vector2i = edge[0]
		var pb: Vector2i = edge[1]
		var cid: int = int(_pole_component.get(pa, -1))
		var sat: float = float(_component_satisfaction.get(cid, 0.0))
		var wire_color: Color = WIRE_COLOR_LIVE if sat > 0.0 else WIRE_COLOR_DEAD
		draw_line(_pole_wire_anchor(pa), _pole_wire_anchor(pb), wire_color, WIRE_THICKNESS)

## Screen-space point a wire attaches to for the pole at `anchor`.
## Centred on the pole's FOOTPRINT, not its anchor cell: a 2x2 substation's
## wire would otherwise hang off its top-left quarter.
func _pole_wire_anchor(anchor: Vector2i) -> Vector2:
	var b: Building = buildings.get(anchor, null)
	var fp: Vector2i = Buildings.footprint_of(b.type) if b != null else Vector2i(1, 1)
	return Vector2(
		float(anchor.x) * TILE_SIZE + float(fp.x) * TILE_SIZE * 0.5,
		float(anchor.y) * TILE_SIZE + float(fp.y) * TILE_SIZE * 0.16
	)
```

- [ ] **Step 5: Run the suite**

Expected: **`45 passed, 0 failed`**, zero `Parse Error`. `pole tier rig` should now be fully green — this is the task that turns the Task 3 RED green.

- [ ] **Step 6: Capture a frame of both rigs**

```bash
mkdir -p /tmp/mstcap && ./tools/Godot_v4.6.3-stable_win64_console.exe --write-movie /tmp/mstcap/f.png --quit-after 150 --resolution 1280x720 --position 6000,6000 --path . -- --scenario=pole_tiers 2>&1 | grep -Ei "error|frames at"
```

Read the last frame and confirm the south MST control block shows **3** wires among its four poles, not 6.

- [ ] **Step 7: Commit**

```bash
git add scripts/world/power_network.gd scripts/world/grid_world.gd scripts/tests/test_pole_tiers.gd
git commit -m "Pole Tiers Task 7: MST wire rendering via shared connection predicate"
```

---

## Task 8: PAUSE 1 — visual smoke **· USER GATE**

Launch both rigs and hand the user the keys. **Do not proceed without their verdict.**

- [ ] **Step 1: Run the suite one final time and confirm 45 green**

- [ ] **Step 2: Launch the pole-tier rig**

```bash
./tools/Godot_v4.6.3-stable_win64_console.exe --path . -- --scenario=pole_tiers
```

- [ ] **Step 3: Present this checklist to the user**

| # | Check | Where |
|---|---|---|
| 1 | Three pole tiers are tellable apart at a glance | North block |
| 2 | Substation reads as a 2×2 installation, not a big pole | North block, x≈12 |
| 3 | Wires from the substation span to both clusters | North block |
| 4 | **MST regression: the basic-pole square shows 3 wires, not 6** | **South block** |
| 5 | **Does the simple basic-pole case look WORSE than before?** | **South block** |
| 6 | Lamps near all three tiers dim together under F8 brownout | Both |
| 7 | Lamps do not flicker under sustained brownout | Both |
| 8 | Hotbar Power category shows 8 slots | HUD |

**Check 5 is the one that matters.** The user's condition: *"It changes shipped, gate-approved visuals. I want a basic-pole-only layout compared against current behavior before I'll accept it didn't make the simple case worse."*

To show the before/after, capture the same south block on `69f3cb7`:

```bash
git stash && git checkout 69f3cb7 && ./tools/Godot_v4.6.3-stable_win64_console.exe --write-movie /tmp/before/f.png --quit-after 150 --resolution 1280x720 --position 6000,6000 --path . -- --scenario=electric_rig
git checkout main && git stash pop
```

The electric rig's pole bus is basic-poles-only and is the closest available pre-change control.

- [ ] **Step 4: Record the verdict.** If MST is rejected on check 5, the fallback is to keep the shared predicate (Task 7's real correctness win) and revert only `wire_edges` to a mesh, which also forces the substation's range back down from 11 to 8.

---

## Task 9: Save round-trip + mixed-tier sweep

**Files:**
- Test: `scripts/tests/test_pole_tiers.gd`

- [ ] **Step 1: Write the test**

Append, wiring `_case_save_roundtrip(parent, failures)` into `run()`:

```gdscript
# ===========================================================================
# (8) SAVE ROUND-TRIP WITH MIXED TIERS.
#
# No schema bump is expected and this sub-case is what proves it:
#   - the Type enum is append-only (MEDIUM_POLE and SUBSTATION were added at
#     the END), so every previously-saved type keeps its integer value
#   - poles carry EMPTY state, so there is nothing per-building to migrate
#   - _pole_component and _pole_cells are never serialized; they rebuild from
#     the dirty flag on load
#
# The one thing that genuinely must survive is the 2x2 substation's OCCUPANCY:
# save_system.gd:479-482 rehydrates it from footprint_of(b.type), so a wrong
# footprint silently corrupts collision only after a reload.
# ===========================================================================
static func _case_save_roundtrip(parent: Node, failures: Array) -> void:
	var world_a = _make_world(parent)
	world_a.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5))
	world_a.place_building(Buildings.Type.MEDIUM_POLE, Vector2i(10, 5))
	world_a.place_building(Buildings.Type.SUBSTATION, Vector2i(18, 5))
	PowerNetwork.rebuild_topology(world_a)
	var comps_before: int = _component_count(world_a)

	var dicts: Array = []
	for anchor in world_a.buildings:
		dicts.append(world_a.buildings[anchor].to_dict())
	_teardown(world_a)

	var world_b = _make_world(parent)
	for d in dicts:
		var b: Building = Building.from_dict(d)
		world_b.buildings[b.anchor] = b
		var fp: Vector2i = Buildings.footprint_of(b.type)
		for dx in fp.x:
			for dy in fp.y:
				world_b.occupied[Vector2i(b.anchor.x + dx, b.anchor.y + dy)] = b.anchor
	world_b._power_network_dirty = true
	PowerNetwork.rebuild_topology(world_b)

	_check(failures, _component_count(world_b) == comps_before,
		"(8) component count changed across the save round-trip: %d before, %d after" % [comps_before, _component_count(world_b)])
	var sub: Building = world_b.building_at(Vector2i(19, 6))
	_check(failures, sub != null and sub.type == Buildings.Type.SUBSTATION,
		"(8) the substation's far footprint cell (19, 6) does not resolve to the substation after reload, so occupancy was rehydrated with the wrong footprint")
	_teardown(world_b)

static func _component_count(world) -> int:
	var seen: Dictionary = {}
	for pos in world._pole_component:
		seen[int(world._pole_component[pos])] = true
	return seen.size()
```

- [ ] **Step 2: Run, expect green** (the implementation from Tasks 2-5 should already satisfy it — if not, that is a real defect and the point of the sub-case).

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_pole_tiers.gd
git commit -m "Pole Tiers Task 9: mixed-tier save round-trip"
```

---

## Task 10: PAUSE 2 — gameplay **· USER GATE** — then ship

- [ ] **Step 1: PAUSE 2 checklist** — build a real mixed-tier grid by hand in-game and confirm: a substation bridges two hand-built clusters; consumers in overlapping supply areas pick the nearer pole; F8 brownout scales smoothly; lamps do not flicker.

- [ ] **Step 2: On approval, write the PROJECT_LOG entry.** Insert after the header `---` at `PROJECT_LOG.md:11`, following the What shipped / Decisions / Lessons format. Must cover: the two tiers and their numbers; the either-reaches rule and *why symmetry was required* (directed BFS is order-dependent); the shared `poles_connected` predicate replacing two independent constant reads and which divergence direction fails silently; `_pole_cells`; the nearest-pole tie-break with its measured cost; MST rendering and its link to the Foundation PAUSE 1 K4 complaint; `POWER_NETWORK_TYPES`.

- [ ] **Step 3: Update `NOTES.md`.** Electricity Arc 2 → 3 of N. Add the shipped Session 3 entry. Remove "Session 3 — Power Pole Tiers" from the queued list. Update the Session 1 cross-cutting contract block, which documents `POLE_RANGE = 3` and `SUPPLY_RADIUS = 1` as global constants — they are now tables.

- [ ] **Step 4: Tag and push.**

```bash
git tag -a session-electricity-pole-tiers -m "Electricity Arc Session 3 — Pole Tiers"
git push origin main && git push origin session-electricity-pole-tiers
```

---

## Protocol notes for the executing agent

**Full triad on every task, no compression.** Tasks 1, 4, 5, 6 and 7 all touch `power_network.gd`, which everything electric depends on. Tasks 2 and 3 are additive but feed the same module. The compression rule requires *all three* of: small change, already constrained by reviewed tests, scope verified yourself. No task here clears it.

**Design Brief Verification.** Every line citation in this plan was verified against `69f3cb7`, which is byte-identical to the `b1283df` starting point for every file this session touches (see Baseline). If a citation does not match what you find, **the code wins** — say so explicitly in your report rather than working around it silently. Line numbers will drift as tasks land; the surrounding code quoted in each step is the reliable anchor, not the number.

**Standing block.** None yet. If a cross-task item emerges, carry it verbatim into every subsequent task brief and re-emit it in each DONE report.

**Reviewers must line-quote.** A review finding without a `path:line` citation and the quoted line is not actionable and should be sent back.
