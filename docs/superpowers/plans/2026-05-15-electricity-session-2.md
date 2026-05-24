# Electricity Arc Session 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 3 new electric buildings (Windmill, Steam Generator, Accumulator) + extend `PowerNetwork.update_supply_demand` to a 3-stage flow that handles accumulator charge/discharge while preserving Foundation's consumer satisfaction contract.

**Architecture:** Windmill and Steam Generator mirror `WaterWheel` as static `RefCounted` modules (existing generator pattern). Steam Generator integrates `Burner` as its 5th consumer (Smelter precedent). Accumulator is 1×1 with `charge: float` state; its mutation happens INSIDE `PowerNetwork.update_supply_demand` 3-stage pre-pass (Stage 1: sum raw_supply+demand → Stage 2: accumulator charge/discharge → Stage 3: satisfaction with effective_supply). Accumulator's own `tick()` is a no-op. Save schema stays v18.

**Tech Stack:** Godot 4.6.2 / GDScript / `class_name X extends RefCounted` static modules. Reuses existing `Burner` module API (`try_pull_fuel`, `consume_tick`), `PowerNetwork` adjacency helpers (`_adjacent_component_id`, `_supply_component_id`), `Buildings.all_edge_cells`. Headless test runner at `scripts/tests/test_runner.gd`.

**Plan source:** `docs/superpowers/specs/2026-05-15-electricity-session-2-design.md` (committed at `56130e2`).

---

## File map

| File | Purpose | Change type |
|---|---|---|
| `scripts/world/buildings.gd` | Type enum + DATA + dispatch | Modify — 3 enum entries + 3 DATA blocks + 4 dispatch sites |
| `scripts/world/windmill.gd` | Always-active generator | NEW |
| `scripts/world/steam_generator.gd` | Fuel-powered generator (Burner integration) | NEW |
| `scripts/world/accumulator.gd` | Storage with fill-bar visual | NEW |
| `scripts/world/power_network.gd` | 3-stage `update_supply_demand` + Windmill/Steam/Accumulator branches + new per-component dict members | Modify (substantial — Phase 4 highest-risk) |
| `scripts/world/grid_world.gd` | Dirty-flag hooks for 3 new types + new dict member declarations for accumulator state | Modify (2 regions) |
| `scripts/ui/hotbar.gd` | Power category 3 → 6 slots | Modify (1 region) |
| `scripts/tests/test_power_network.gd` | Append ~8 new sub-cases (windmill, steam, accumulator) | Modify |
| `scripts/tests/test_building_ui_4.gd` | Append 3 new types to `passive` array | Modify (1 line) |
| `PROJECT_LOG.md` | Prepend session ship entry | Modify |
| `NOTES.md` | DBV count update (6 → 7) + Electricity Arc tracker update | Modify |

3 new production files, 5 modified production files, 2 housekeeping. Save schema unchanged.

---

## Task overview

| # | Task | TDD red | TDD green | Manual gate |
|---|---|---|---|---|
| 1 | Threshold audit (37/37 baseline) | — | run tests | — |
| 2 | Windmill (enum + DATA + module + dispatch + `update_supply_demand` Windmill branch) | sub-cases (1)(2) fail | windmill module + 1 elif branch | — |
| 3 | Steam Generator (enum + DATA + module + dispatch + Burner integration + `update_supply_demand` Steam branch) | sub-cases (3)(4)(5) fail | steam_generator module + Burner reuse | — |
| 4 | Accumulator skeleton (enum + DATA + module stub + dispatch — no PowerNetwork integration yet, visual stub) | — | scaffold for Task 5 | — |
| 5 | **PowerNetwork 3-stage refactor + accumulator math + sub-cases (6)(7)(8)(9)** (HIGHEST-RISK TASK) | regression check Foundation sub-cases (1)-(10) PASS first, THEN add accumulator sub-cases | 3-stage `update_supply_demand` + new dict members + accumulator dispatch | — |
| 6 | Accumulator visual fill-bar (replace Task 4 stub `draw` with full fill-bar implementation) | — (visual only) | full `draw` with charge fraction lerp | covered by PAUSE 1 |
| 7 | Hotbar Power category 3 → 6 slots | — (visual) | 3 slot appends | — |
| 8 | Save round-trip sub-case (10) — accumulator charge preserved | sub-case (10) likely passes on first run (save shape unchanged) | already wired in T4+T5 | — |
| 9 | PAUSE 1 visual smoke (3 new buildings + accumulator behavior) | — | — | user smoke |
| 10 | PAUSE 2 full gameplay (multi-generator factory + brownout/recovery cycles) | — | — | user smoke |
| 11 | Ship (PROJECT_LOG + NOTES + tag + push) | — | — | — |

**Watch points (baked into specific tasks per user):**
- **Task 5 highest-risk**: Foundation's 10 sub-cases MUST still pass after the refactor before any accumulator sub-cases are added. RED-GREEN-RED-GREEN order: refactor → run all → fix any regressions → add new sub-cases → run all again.
- **Task 3 parametric pattern**: Steam Generator is 5th Burner consumer (Smelter precedent). Should be parametric application, not novel work. Implementer brief explicitly cites Smelter as the template.
- **Task 6 z-order**: fill-bar drawn inside building rect AFTER body draw, BEFORE post-pass border indicators. Verify no z-order clipping issues.

**Validated protocols apply:**
- DBV at **7 catches** (Cluster A + Inserter Arc + Electricity Foundation + Cluster B spec→plan + Electricity Session 2 spec) — 100% capture rate
- UX iteration trap (after 2 visual iterations on single item, force the rule)
- Magic-number-in-tests audit (no constants changed this session, but Task 5's refactor changes the per-component dict shape — same cascade-grep discipline applies)
- Variable name pre-check before multi-edit on shared test files (test_power_network.gd grows from sub-case 10 to sub-case 18)
- `--headless --import` parse verification for new `.gd` files (Windmill, Steam Generator, Accumulator)
- Line-quoting on reviewers

---

## Task 1: Threshold audit

**Files:** none (verification only)

**Purpose:** Confirm 37/37 PASS baseline. HEAD must be `56130e2` (spec commit).

- [ ] **Step 1: Verify HEAD + working tree**

Run:
```bash
git status
git log --oneline -1
```
Expected: working tree clean (2 untracked `.uid` files from Cluster B are OK; will pick up in Task 2 commit), HEAD = `56130e2` (Spec: Electricity Arc Session 2).

- [ ] **Step 2: Run full test suite**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `37 passed, 0 failed`.

- [ ] **Step 3: No commit (verification only)**

Proceed to Task 2.

---

## Task 2: Windmill (enum + DATA + module + dispatch + update_supply_demand branch)

**Files:**
- Modify: `scripts/world/buildings.gd` (WINDMILL enum + DATA + 4 dispatch sites)
- Create: `scripts/world/windmill.gd`
- Modify: `scripts/world/grid_world.gd` (extend dirty-flag hook lines to include WINDMILL)
- Modify: `scripts/world/power_network.gd` (add WINDMILL branch in update_supply_demand walk)
- Modify: `scripts/tests/test_power_network.gd` (append sub-cases 11 + 12 — windmill placement + windmill joins network supply)
- Modify: `scripts/tests/test_building_ui_4.gd` (append WINDMILL to passive array)

**Purpose:** First new generator. Always active (no resource dependency). Validates the 3-generator-types-in-network pattern before Steam Generator adds Burner complexity in Task 3.

### Step 1: Variable name pre-check for new sub-cases

Run:
```bash
grep -n "^\s*var \(wind_b\|comp_wind\|supply_wind\)\b" scripts/tests/test_power_network.gd
```
Expected: no matches. Variables `_wind` suffix used for clarity.

### Step 2: Write failing sub-cases (11) + (12) to test_power_network.gd

Find the end of sub-case (10) — the save round-trip from Foundation. Insert BEFORE the final `_disconnect(world)` and `if failures.is_empty()` block (or just before the success return if there's no disconnect):

```gdscript

	# ===========================================================================
	# (11) WINDMILL ALWAYS ACTIVE — no resource dependency. output_active=true
	# from initialization (no tick required to "warm up").
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.WINDMILL, Vector2i(4, 5))
	var wind_b: Building = world.building_at(Vector2i(4, 5))
	_check(failures, bool(wind_b.state.get("output_active", false)),
		"(11) windmill should be output_active=true from placement, got %s" % str(wind_b.state.get("output_active", false)))

	# ===========================================================================
	# (12) WINDMILL JOINS NETWORK SUPPLY — windmill adjacent to pole contributes
	# MAX_OUTPUT (6) to supply pool.
	# ===========================================================================
	# Pole east of the windmill at (6, 5). Adjacent to windmill's (5, 5) cell.
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	PowerNetwork.update_supply_demand(world)
	var comp_wind: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	_check(failures, comp_wind >= 0, "(12) pole should be in a network, got comp_id %d" % comp_wind)
	if comp_wind >= 0:
		var supply_wind: int = PowerNetwork.supply_for(world, comp_wind)
		_check(failures, supply_wind == Windmill.MAX_OUTPUT,
			"(12) windmill supply should equal MAX_OUTPUT (%d), got %d" % [Windmill.MAX_OUTPUT, supply_wind])
```

Update test_name() and success message (the existing message says "10 sub-cases pass"; bump to 12):
```gdscript
static func test_name() -> String:
	return "power network (topology + generator + consumer + linear satisfaction + save + windmill)"
```
And bump the success message to "12 sub-cases pass: ... + windmill placement + windmill joins network supply".

### Step 3: Run tests to verify (11) and (12) fail

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```

Expected: parse error or runtime failure on `Buildings.Type.WINDMILL` / `Windmill.MAX_OUTPUT` (enum + class don't exist yet).

### Step 4: Add WINDMILL enum entry to Buildings.Type

In `scripts/world/buildings.gd`, find the end of the `Type` enum. The last entry should be `ELECTRIC_LAMP,` from Foundation. Append before the closing brace:

```gdscript
	ELECTRIC_LAMP,
	# Electricity Arc Session 2 (session-electricity-generators-storage):
	# More generators + storage.
	# Windmill — 2x2, no resource dependency, always output_active=true,
	# MAX_OUTPUT=6 (60% of WaterWheel — placement flexibility tradeoff).
	# Steam Generator — 2x2, fuel-powered via Burner (5th consumer),
	# MAX_OUTPUT=20 when active, cycle-based fuel (1 unit per 20 ticks).
	# Accumulator — 1x1, battery storage. Capacity 50, ±5/tick. Charge
	# state in pre-pass via PowerNetwork 3-stage update_supply_demand.
	WINDMILL,
	STEAM_GENERATOR,
	ACCUMULATOR,
}
```

Note: all 3 enum entries added in this task (atomic enum extension). DATA entries + dispatch for STEAM_GENERATOR and ACCUMULATOR land in Tasks 3 + 4 respectively. Only WINDMILL DATA + dispatch + module ships now.

### Step 5: Append WINDMILL DATA entry to buildings.gd

After the existing ELECTRIC_LAMP DATA block (search for `Type.ELECTRIC_LAMP:`), insert:

```gdscript
	Type.WINDMILL: {
		"name": "Windmill",
		"swatch_color": Color(0.85, 0.85, 0.75),    # bone-white / canvas-sail
		"footprint": Vector2i(2, 2),
		"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,                 # wind comes from anywhere; visual is rotating blades
		"player_drainable": false,
		"walkable": false,
		# No slot_layout — windmill has no items. Info via Q-inspect.
	},
```

### Step 6: Extend dispatch in buildings.gd for WINDMILL

`make` (after `Type.ELECTRIC_LAMP:` case):
```gdscript
		Type.WINDMILL:
			return Windmill.make(pos)
```

`tick_one` (after ELECTRIC_LAMP case):
```gdscript
		Type.WINDMILL:
			Windmill.tick(b, world)
```

`draw_one` (after ELECTRIC_LAMP case):
```gdscript
		Type.WINDMILL:
			Windmill.draw(b, canvas, world_pos, tile_size)
```

`info_lines_for` (after ELECTRIC_LAMP case):
```gdscript
			Type.WINDMILL:
				return Windmill.info_lines(b, world)
```

### Step 7: Create `scripts/world/windmill.gd`

```gdscript
class_name Windmill
extends RefCounted

## Windmill — wind-powered generator.
##
## 2x2 footprint. No resource dependency — output_active=true from
## placement. MAX_OUTPUT = 6 power units (60% of WaterWheel's 10,
## reflecting placement flexibility tradeoff: free placement vs lower
## throughput).
##
## State:
##   output_active: bool        — always true (kept for power_network
##                                interface parity with other generators)
##   blade_rotation: float      — visual rotation accumulator [0, TAU)
##
## Power network contract: when output_active (always for windmill),
## contributes MAX_OUTPUT to the supply of the component containing any
## adjacent pole. Adjacency resolved by Buildings.all_edge_cells() via
## PowerNetwork._adjacent_component_id (strict cardinal — generator rule).

const MAX_OUTPUT: int = 6
const ROTATION_PER_TICK: float = 0.10 * TAU / 20.0      # ~1 full rotation / 10 sec (slower than WaterWheel)

const SAIL_COLOR: Color = Color(0.92, 0.90, 0.82)       # off-white canvas
const FRAME_COLOR: Color = Color(0.45, 0.35, 0.25)      # wooden frame
const HUB_COLOR: Color = Color(0.30, 0.25, 0.20)        # dark hub center
const BASE_COLOR: Color = Color(0.55, 0.50, 0.45)       # stone base

static func make(pos: Vector2i) -> Building:
	var state: Dictionary = {
		"output_active": true,         # always true — no resource dep
		"blade_rotation": 0.0,
	}
	return Building.new(Buildings.Type.WINDMILL, pos, state)

## Tick: advance blade_rotation. output_active stays true (no condition).
static func tick(b: Building, _world) -> void:
	var rot: float = float(b.state.get("blade_rotation", 0.0)) + ROTATION_PER_TICK
	if rot >= TAU:
		rot -= TAU
	b.state["blade_rotation"] = rot

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	# 2x2 base — stone foundation.
	var base_rect: Rect2 = Rect2(world_pos, Vector2(tile_size * 2, tile_size * 2))
	canvas.draw_rect(base_rect, BASE_COLOR, true)
	canvas.draw_rect(base_rect, FRAME_COLOR, false, 2.0)
	# Central tower — vertical bar from base to top.
	var center: Vector2 = world_pos + Vector2(tile_size, tile_size)
	var tower_w: float = float(tile_size) * 0.20
	var tower_rect: Rect2 = Rect2(
		Vector2(center.x - tower_w * 0.5, world_pos.y + float(tile_size) * 0.35),
		Vector2(tower_w, float(tile_size) * 1.3)
	)
	canvas.draw_rect(tower_rect, FRAME_COLOR, true)
	# 4 rotating sails — cross pattern from hub.
	var rot: float = float(b.state.get("blade_rotation", 0.0))
	var sail_len: float = float(tile_size) * 0.80
	for i in range(4):
		var angle: float = rot + (TAU / 4.0) * float(i)
		var tip: Vector2 = center + Vector2(cos(angle), sin(angle)) * sail_len
		canvas.draw_line(center, tip, SAIL_COLOR, 4.0)
	# Hub circle at center.
	canvas.draw_circle(center, float(tile_size) * 0.10, HUB_COLOR)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	lines.append("Output: %d / %d units (always active)" % [MAX_OUTPUT, MAX_OUTPUT])
	# Network info — only meaningful if adjacent to a pole.
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
	else:
		lines.append("Network: #%d" % comp_id)
	# Output_active suppression for symmetry with other generators in info display.
	lines.append("Status: %s" % ("Active" if bool(b.state.get("output_active", true)) else "Idle"))
	return lines
```

### Step 8: Add WINDMILL branch to PowerNetwork.update_supply_demand

In `scripts/world/power_network.gd`, find the existing generator/consumer walk in `update_supply_demand` (around line 122). The current shape:

```gdscript
	for anchor in world.buildings:
		var b: Building = world.buildings[anchor]
		if b.type == Buildings.Type.WATER_WHEEL:
			var gen_comp: int = _adjacent_component_id(world, b)
			if gen_comp < 0:
				continue
			if bool(b.state.get("output_active", false)):
				world._component_supply[gen_comp] = int(world._component_supply.get(gen_comp, 0)) + WaterWheel.MAX_OUTPUT
		elif b.type == Buildings.Type.ELECTRIC_LAMP:
			...
```

Add a new `elif` branch for WINDMILL — placed AFTER the WATER_WHEEL branch, BEFORE the ELECTRIC_LAMP branch (groups generators together):

```gdscript
		elif b.type == Buildings.Type.WINDMILL:
			var gen_comp_w: int = _adjacent_component_id(world, b)
			if gen_comp_w < 0:
				continue
			if bool(b.state.get("output_active", true)):
				world._component_supply[gen_comp_w] = int(world._component_supply.get(gen_comp_w, 0)) + Windmill.MAX_OUTPUT
```

Variable `gen_comp_w` suffixed to avoid scope collision with the WATER_WHEEL branch's `gen_comp`.

### Step 9: Extend grid_world.gd dirty-flag hooks for WINDMILL

In `scripts/world/grid_world.gd`, find the existing power network dirty-flag hook lines in `place_building` (search for `Buildings.Type.POWER_POLE or t == Buildings.Type.WATER_WHEEL`). Extend each instance to include WINDMILL (one in place_building, one in remove_building_at):

```gdscript
if t == Buildings.Type.POWER_POLE or t == Buildings.Type.WATER_WHEEL or t == Buildings.Type.ELECTRIC_LAMP or t == Buildings.Type.WINDMILL:
    _power_network_dirty = true
```

(STEAM_GENERATOR and ACCUMULATOR get added in Tasks 3 + 4 respectively. WINDMILL only here.)

### Step 10: Extend test_building_ui_4.gd passive array for WINDMILL

In `scripts/tests/test_building_ui_4.gd`, find the existing `passive` array (line ~85). It currently includes POWER_POLE, WATER_WHEEL, ELECTRIC_LAMP. Append `Buildings.Type.WINDMILL`:

```gdscript
var passive: Array = [..., Buildings.Type.WINDMILL]
```

(STEAM_GENERATOR and ACCUMULATOR get added in Tasks 3 + 4 respectively.)

### Step 11: Verify parse + tests

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" --quit 2>&1 | tail -15
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -5
```

Expected: no parse errors. `Windmill` class registers. `37 passed, 0 failed` with sub-cases (11) and (12) passing.

### Step 12: Pick up untracked .uid files from Cluster B

Cluster B Task 6 left 2 untracked `.uid` files: `scripts/ui/item_picker_modal.gd.uid` and `scripts/tests/test_item_picker_modal.gd.uid`. Add them to this commit (housekeeping batched with first new-file commit of this session):

```bash
git add scripts/ui/item_picker_modal.gd.uid scripts/tests/test_item_picker_modal.gd.uid
```

### Step 13: Commit

```bash
git add scripts/world/buildings.gd scripts/world/windmill.gd scripts/world/power_network.gd scripts/world/grid_world.gd scripts/tests/test_power_network.gd scripts/tests/test_building_ui_4.gd
git commit -m "$(cat <<'EOF'
Task 2: Windmill (enum + DATA + module + network branch + tests)

First new generator of Electricity Session 2:
- Buildings.Type.WINDMILL enum + DATA (2x2, no resource dep, walkable=false,
  bone-white swatch)
- scripts/world/windmill.gd — make/tick/draw/info_lines, MAX_OUTPUT=6
- state.output_active always true (no resource gating)
- Visual: 2x2 stone base + tower + 4 rotating sails + dark hub
- Rotation rate 0.10*TAU/20 (1 rotation per ~10s — slower than WaterWheel)

PowerNetwork.update_supply_demand: new WINDMILL branch placed between
WATER_WHEEL and ELECTRIC_LAMP (groups generators). Variable name
suffixed _w to avoid scope collision.

grid_world dirty-flag hooks extended (place_building + remove_building_at)
to include WINDMILL. STEAM_GENERATOR + ACCUMULATOR enum entries added
atomically but no DATA / dispatch yet — those land in Tasks 3 + 4.

test_power_network.gd sub-cases (11) + (12) — windmill always active +
windmill joins network supply. 37/37 PASS.

Also: pick up 2 .uid files from Cluster B Task 6 (test_item_picker_modal +
item_picker_modal). Standard housekeeping pattern.
EOF
)"
```

---

## Task 3: Steam Generator (Burner integration)

**Files:**
- Modify: `scripts/world/buildings.gd` (STEAM_GENERATOR DATA entry + dispatch — enum entry already added in Task 2)
- Create: `scripts/world/steam_generator.gd`
- Modify: `scripts/world/grid_world.gd` (extend dirty-flag hooks for STEAM_GENERATOR)
- Modify: `scripts/world/power_network.gd` (add STEAM_GENERATOR branch in update_supply_demand walk)
- Modify: `scripts/tests/test_power_network.gd` (append sub-cases 13, 14, 15)
- Modify: `scripts/tests/test_building_ui_4.gd` (passive array — STEAM_GENERATOR is NOT passive; it has a fuel slot. SKIP this file. Will need an interaction-UI entry instead — verify against test_building_ui_4 conventions.)

### Pre-task check: test_building_ui_4 expectation for Steam Generator

Steam Generator has a `slot_layout` with a fuel slot. Per `test_building_ui_4.gd`, buildings with `slot_layout` are NOT passive — they're expected to open `BuildingPanel`. Foundation's WATER_WHEEL + ELECTRIC_LAMP have no slot_layout, so they're passive. STEAM_GENERATOR has fuel slot, so it should be detected as having interaction UI automatically by the existing dispatcher (mirrors SMELTER).

**Action**: do NOT add STEAM_GENERATOR to passive array. If test_building_ui_4 fails, debug then — it likely passes automatically because Steam Generator inherits from the slot_layout → BuildingPanel dispatch chain.

### Step 1: Variable name pre-check for new sub-cases

Run:
```bash
grep -n "^\s*var \(steam_b\|comp_steam\|supply_steam_no_fuel\|supply_steam_with_fuel\|supply_steam_exhausted\)\b" scripts/tests/test_power_network.gd
```
Expected: no matches.

### Step 2: Write failing sub-cases (13)(14)(15) to test_power_network.gd

Append AFTER sub-case (12) (windmill sub-cases from Task 2):

```gdscript

	# ===========================================================================
	# (13) STEAM GENERATOR NO FUEL — empty fuel_buffer → output_active=false,
	# component supply contribution = 0.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.STEAM_GENERATOR, Vector2i(4, 5), Belt.DIR_E)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	var steam_b: Building = world.building_at(Vector2i(4, 5))
	# fuel_buffer starts at 0 from Burner.make_state()
	# Tick to attempt fuel pull (no source, fails) and update output_active.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	_check(failures, not bool(steam_b.state.get("output_active", true)),
		"(13) steam generator no fuel: output_active should be false, got %s" % str(steam_b.state.get("output_active", false)))
	var comp_steam: int = PowerNetwork.network_id_at(world, Vector2i(6, 5))
	if comp_steam >= 0:
		var supply_steam_no_fuel: int = PowerNetwork.supply_for(world, comp_steam)
		_check(failures, supply_steam_no_fuel == 0,
			"(13) steam generator no fuel: network supply should be 0, got %d" % supply_steam_no_fuel)

	# ===========================================================================
	# (14) STEAM GENERATOR WITH FUEL — manually set fuel_buffer=100, tick →
	# output_active=true, component supply += MAX_OUTPUT (20).
	# ===========================================================================
	steam_b.state["fuel_buffer"] = 100
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	_check(failures, bool(steam_b.state.get("output_active", false)),
		"(14) steam generator with fuel: output_active should be true, got %s" % str(steam_b.state.get("output_active", false)))
	if comp_steam >= 0:
		var supply_steam_with_fuel: int = PowerNetwork.supply_for(world, comp_steam)
		_check(failures, supply_steam_with_fuel == SteamGenerator.MAX_OUTPUT,
			"(14) steam generator with fuel: network supply should equal MAX_OUTPUT (%d), got %d" % [SteamGenerator.MAX_OUTPUT, supply_steam_with_fuel])

	# ===========================================================================
	# (15) STEAM GENERATOR FUEL EXHAUSTION — set fuel_buffer=2, tick 41 cycles
	# (41 ticks per cycle? no, CYCLE_TICKS=20 → 41 ticks consumes ~2 units).
	# After exhaustion, fuel_buffer=0, output_active=false.
	# ===========================================================================
	steam_b.state["fuel_buffer"] = 2
	steam_b.state["fuel_burn_progress"] = 0
	for _i in 41:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, int(steam_b.state.get("fuel_buffer", -1)) == 0,
		"(15) steam generator fuel exhaustion: fuel_buffer should be 0 after 41 ticks, got %d" % int(steam_b.state.get("fuel_buffer", -1)))
	# One more tick to flip output_active off (Burner.consume_tick returned false this round).
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	_check(failures, not bool(steam_b.state.get("output_active", true)),
		"(15) steam generator fuel exhaustion: output_active should be false after fuel runs out")
```

Update test_name() and success message — bump from "12 sub-cases" to "15".

### Step 3: Run tests to verify (13)(14)(15) fail

Expected: parse error or runtime failure on `Buildings.Type.STEAM_GENERATOR` / `SteamGenerator.MAX_OUTPUT`.

### Step 4: Append STEAM_GENERATOR DATA entry to buildings.gd

After the WINDMILL DATA block (added in Task 2), insert:

```gdscript
	Type.STEAM_GENERATOR: {
		"name": "Steam Generator",
		"swatch_color": Color(0.40, 0.35, 0.32),    # dark iron / industrial
		"footprint": Vector2i(2, 2),
		"requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
		"supports_direction": true,                  # fuel input port rotates
		"player_drainable": false,
		"walkable": false,
		"slot_layout": [
			{
				"id": "fuel", "kind": "fuel",
				"accepts": [Items.Type.WOOD, Items.Type.COAL, Items.Type.FUEL_BRIQUETTE],
				"max_stack": 16, "state_field": "fuel_buffer",
			},
		],
	},
```

### Step 5: Extend dispatch in buildings.gd for STEAM_GENERATOR

`make` (after WINDMILL case):
```gdscript
		Type.STEAM_GENERATOR:
			return SteamGenerator.make(pos, dir)
```

`tick_one` (after WINDMILL case):
```gdscript
		Type.STEAM_GENERATOR:
			SteamGenerator.tick(b, world)
```

`draw_one` (after WINDMILL case):
```gdscript
		Type.STEAM_GENERATOR:
			SteamGenerator.draw(b, canvas, world_pos, tile_size)
```

`info_lines_for` (after WINDMILL case):
```gdscript
			Type.STEAM_GENERATOR:
				return SteamGenerator.info_lines(b, world)
```

### Step 6: Create `scripts/world/steam_generator.gd`

Mirror Smelter's Burner integration. Reference `scripts/world/smelter.gd:60-110` for the exact pattern.

```gdscript
class_name SteamGenerator
extends RefCounted

## Steam Generator — fuel-powered electric generator.
##
## 2x2 footprint. Burner module 5th consumer (after Drill, Smelter,
## Inserter, Fast Inserter). MAX_OUTPUT = 20 power units when active.
## Cycle-based fuel: 1 fuel unit per CYCLE_TICKS (20 ticks = 1.0s).
##
## Fuel economy:
##   - 1 WOOD = 1 unit = 1 second of 20-power output
##   - 1 COAL = 4 units = 4 seconds of 20-power output
##   - 1 FUEL_BRIQUETTE = 8 units = 8 seconds of 20-power output
##
## State:
##   dir: int                    — facing direction (fuel input port rotates)
##   output_active: bool         — set per-tick based on fuel availability
##   fuel_buffer: int            — Burner units remaining
##   fuel_burn_progress: int     — Burner ticks toward next unit
##   last_fuel_item: int         — Burner display field (-1 = none yet)
##
## Power network contract: when output_active, contributes MAX_OUTPUT to
## the supply of the component containing any adjacent pole. Adjacency
## resolved by Buildings.all_edge_cells() — strict cardinal generator rule.

const MAX_OUTPUT: int = 20
const CYCLE_TICKS: int = 20                          # 1 fuel unit per cycle (1.0s @ 20 TPS)

const FUEL_PORT_DIR: int = Belt.DIR_S                # restrict fuel intake to S edge (canonical)

const BODY_COLOR: Color = Color(0.40, 0.35, 0.32)    # dark iron
const STACK_COLOR: Color = Color(0.30, 0.25, 0.22)   # darker smokestack
const STEAM_COLOR: Color = Color(0.90, 0.90, 0.92, 0.7)  # translucent white steam
const IDLE_TINT: Color = Color(0.55, 0.55, 0.55)

## Build initial state. Burner fields merged in via Burner.make_state().
static func make(pos: Vector2i, dir: int = 0) -> Building:
	var state: Dictionary = {
		"dir": dir,
		"output_active": false,
	}
	for k in Burner.make_state().keys():
		state[k] = Burner.make_state()[k]
	return Building.new(Buildings.Type.STEAM_GENERATOR, pos, state)

## Tick: pull fuel, consume fuel unit per cycle, update output_active.
static func tick(b: Building, world) -> void:
	# Step 1: pull fuel into buffer if low (S edge, rotated by b.dir).
	Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR))
	# Step 2: try to consume 1 fuel unit this cycle. If success, output_active.
	var consumed: bool = Burner.consume_tick(b, CYCLE_TICKS)
	b.state["output_active"] = consumed

static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var active: bool = bool(b.state.get("output_active", false))
	var tint: Color = Color.WHITE if active else IDLE_TINT
	# 2x2 body.
	var body_rect: Rect2 = Rect2(world_pos, Vector2(tile_size * 2, tile_size * 2))
	canvas.draw_rect(body_rect, BODY_COLOR * tint, true)
	canvas.draw_rect(body_rect, STACK_COLOR, false, 2.0)
	# Smokestack — vertical bar on right half.
	var stack_w: float = float(tile_size) * 0.35
	var stack_rect: Rect2 = Rect2(
		Vector2(world_pos.x + float(tile_size) * 1.3, world_pos.y + float(tile_size) * 0.2),
		Vector2(stack_w, float(tile_size) * 0.9)
	)
	canvas.draw_rect(stack_rect, STACK_COLOR, true)
	# Steam puff visual when active — 3 translucent circles above smokestack.
	if active:
		var stack_top: Vector2 = stack_rect.position + Vector2(stack_w * 0.5, 0)
		for i in range(3):
			var offset: Vector2 = Vector2(float(i - 1) * 4.0, -float(tile_size) * (0.15 + 0.10 * float(i)))
			canvas.draw_circle(stack_top + offset, float(tile_size) * 0.10, STEAM_COLOR)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	var active: bool = bool(b.state.get("output_active", false))
	var output_str: String = "%d / %d units" % [MAX_OUTPUT if active else 0, MAX_OUTPUT]
	var status_str: String = "active" if active else "no fuel"
	lines.append("Output: %s (%s)" % [output_str, status_str])
	# Burner.info_lines provides fuel buffer state, current fuel item, etc.
	for line in Burner.info_lines(b):
		lines.append(line)
	# Network info.
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
	else:
		lines.append("Network: #%d" % comp_id)
	# Facing.
	lines.append("Facing: %s (R to rotate; fuel port on S edge of canonical)" % Belt.DIR_NAMES[int(b.state.get("dir", 0))])
	return lines
```

### Step 7: Add STEAM_GENERATOR branch to PowerNetwork.update_supply_demand

In `scripts/world/power_network.gd`, after the WINDMILL branch (added in Task 2), insert:

```gdscript
		elif b.type == Buildings.Type.STEAM_GENERATOR:
			var gen_comp_s: int = _adjacent_component_id(world, b)
			if gen_comp_s < 0:
				continue
			if bool(b.state.get("output_active", false)):
				world._component_supply[gen_comp_s] = int(world._component_supply.get(gen_comp_s, 0)) + SteamGenerator.MAX_OUTPUT
```

Variable `gen_comp_s` for collision-free scope.

### Step 8: Extend grid_world.gd dirty-flag hooks for STEAM_GENERATOR

In `scripts/world/grid_world.gd`, both hook lines (place_building + remove_building_at) get extended:

```gdscript
if t == Buildings.Type.POWER_POLE or t == Buildings.Type.WATER_WHEEL or t == Buildings.Type.ELECTRIC_LAMP or t == Buildings.Type.WINDMILL or t == Buildings.Type.STEAM_GENERATOR:
    _power_network_dirty = true
```

### Step 9: Verify parse + tests

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" --quit 2>&1 | tail -15
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```

Expected: no parse errors. SteamGenerator class registers. `37 passed, 0 failed` with sub-cases (13)(14)(15) passing.

**If `test_building_ui_4.gd` fails** because Steam Generator's slot_layout doesn't auto-detect as having UI: investigate. Either add STEAM_GENERATOR to passive array (less likely — it has a fuel slot) or extend the BuildingPanel dispatch in main.gd. Report findings.

### Step 10: Commit

```bash
git add scripts/world/buildings.gd scripts/world/steam_generator.gd scripts/world/power_network.gd scripts/world/grid_world.gd scripts/tests/test_power_network.gd
git commit -m "$(cat <<'EOF'
Task 3: Steam Generator (Burner integration + tests)

5th Burner consumer (after Drill / Smelter / Inserter ×3 tiers):
- Buildings.Type.STEAM_GENERATOR DATA (2x2, STONE/PATH, fuel slot:
  WOOD/COAL/FUEL_BRIQUETTE, max_stack 16, supports_direction for
  fuel port rotation)
- scripts/world/steam_generator.gd — make/tick/draw/info_lines
- Mirrors Smelter Burner integration: try_pull_fuel(S edge), consume_tick
  with CYCLE_TICKS=20 (1 fuel unit per 1.0s cycle), output_active set by
  Burner.consume_tick return value
- MAX_OUTPUT=20 (2x WaterWheel — fuel overhead tradeoff)
- Visual: 2x2 industrial body + smokestack + animated steam puffs when active

PowerNetwork.update_supply_demand: new STEAM_GENERATOR branch after
WINDMILL. Variable name suffixed _s.

grid_world dirty-flag hooks extended for STEAM_GENERATOR.

test_power_network.gd sub-cases (13)(14)(15) — no-fuel idle, with-fuel
active, fuel exhaustion sequence. 37/37 PASS.
EOF
)"
```

---

## Task 4: Accumulator skeleton

**Files:**
- Modify: `scripts/world/buildings.gd` (ACCUMULATOR DATA entry + dispatch — enum entry already added in Task 2)
- Create: `scripts/world/accumulator.gd` (skeleton — `make`, stub `draw`, `info_lines`; no `tick`; full visual in Task 6)
- Modify: `scripts/world/grid_world.gd` (extend dirty-flag hooks for ACCUMULATOR + add `_component_accumulators`, `_component_raw_supply`, `_component_accumulator_supply`, `_component_accumulator_drain` dict members)
- Modify: `scripts/tests/test_building_ui_4.gd` (append ACCUMULATOR to passive array — accumulator has no slot_layout)

**Purpose:** Land the type + state shape + grid_world plumbing. NO PowerNetwork integration yet (that's Task 5, the high-risk task). NO real visual yet (Task 6). This task is pure scaffolding so Task 5 has the type to dispatch on.

### Step 1: Append ACCUMULATOR DATA entry to buildings.gd

After the STEAM_GENERATOR DATA block:

```gdscript
	Type.ACCUMULATOR: {
		"name": "Accumulator",
		"swatch_color": Color(0.30, 0.30, 0.40),    # dark slate
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": false,
		"player_drainable": false,
		"walkable": false,
		# No slot_layout — accumulator has no items; charge state is internal.
	},
```

### Step 2: Extend dispatch in buildings.gd for ACCUMULATOR

`make` (after STEAM_GENERATOR case):
```gdscript
		Type.ACCUMULATOR:
			return Accumulator.make(pos)
```

`tick_one`: **no case for ACCUMULATOR** (charge mutation happens in PowerNetwork pre-pass per spec Q8). Skip.

`draw_one` (after STEAM_GENERATOR case):
```gdscript
		Type.ACCUMULATOR:
			Accumulator.draw(b, canvas, world_pos, tile_size)
```

`info_lines_for` (after STEAM_GENERATOR case):
```gdscript
			Type.ACCUMULATOR:
				return Accumulator.info_lines(b, world)
```

### Step 3: Create `scripts/world/accumulator.gd` skeleton

```gdscript
class_name Accumulator
extends RefCounted

## Accumulator — battery storage for the electricity arc.
##
## 1x1 footprint. Stores power between excess/deficit cycles. Charge
## mutation happens in PowerNetwork.update_supply_demand 3-stage pre-pass
## (Stage 2: charge from excess, discharge into deficit). Accumulator's
## own tick() is a no-op — building has no per-tick visual animation.
##
## State:
##   charge: float        — current stored energy [0.0, MAX_CAPACITY]
##                          Float allows even-distribution fractions when
##                          multiple accumulators on same network split
##                          excess that doesn't divide evenly (e.g., 3 acc
##                          + 4 excess = 1.33 per accumulator).
##
## Constants:
##   MAX_CAPACITY: int = 50           — max storable units
##   MAX_CHARGE_RATE: int = 5         — units per tick when supply > demand
##   MAX_DISCHARGE_RATE: int = 5      — units per tick when supply < demand
##
## Power network contract: accumulator joins network via _adjacent_component_id
## (strict cardinal — same as generators). PowerNetwork.update_supply_demand
## classifies it in Stage 1, mutates its charge in Stage 2, computes
## effective_supply (raw + accumulator_supply - accumulator_drain) in Stage 3.

const MAX_CAPACITY: int = 50
const MAX_CHARGE_RATE: int = 5
const MAX_DISCHARGE_RATE: int = 5

const OFF_COLOR: Color = Color(0.30, 0.30, 0.30)    # empty bar
const FULL_COLOR: Color = Color(0.95, 0.78, 0.30)   # full bar (matches SlotWidget.BORDER_HOVER family)
const BASE_COLOR: Color = Color(0.30, 0.30, 0.40)   # body / battery casing
const FRAME_COLOR: Color = Color(0.20, 0.20, 0.28)  # bar frame outline

static func make(pos: Vector2i) -> Building:
	var state: Dictionary = {
		"charge": 0.0,
	}
	return Building.new(Buildings.Type.ACCUMULATOR, pos, state)

## STUB draw — placeholder body only. Full fill-bar visual lands in Task 6.
static func draw(_b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var body_rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(body_rect, BASE_COLOR, true)
	canvas.draw_rect(body_rect, FRAME_COLOR, false, 2.0)

static func info_lines(b: Building, world) -> Array:
	var lines: Array = []
	var charge: float = float(b.state.get("charge", 0.0))
	var pct: int = int(round((charge / float(MAX_CAPACITY)) * 100.0))
	lines.append("Charge: %d / %d units (%d%%)" % [int(round(charge)), MAX_CAPACITY, pct])
	# Network info.
	var comp_id: int = PowerNetwork._adjacent_component_id(world, b)
	if comp_id < 0:
		lines.append("Network: (not adjacent to a pole)")
	else:
		lines.append("Network: #%d" % comp_id)
	return lines
```

### Step 4: Extend grid_world.gd

In `scripts/world/grid_world.gd`, two changes:

(a) Extend dirty-flag hooks (both places — place_building + remove_building_at):
```gdscript
if t == Buildings.Type.POWER_POLE or t == Buildings.Type.WATER_WHEEL or t == Buildings.Type.ELECTRIC_LAMP or t == Buildings.Type.WINDMILL or t == Buildings.Type.STEAM_GENERATOR or t == Buildings.Type.ACCUMULATOR:
    _power_network_dirty = true
```

(b) Add new dict members for the 3-stage flow. Find the existing power-network dict member block (`_pole_component`, `_component_supply`, `_component_demand`, `_component_satisfaction`, `_power_network_dirty`). Append:

```gdscript
# Electricity Session 2 (session-electricity-generators-storage) — accumulator
# 3-stage update_supply_demand needs additional per-component intermediate
# state. Populated by PowerNetwork.update_supply_demand each tick.
var _component_raw_supply: Dictionary = {}            # int (comp_id) → int (units; generators only, before accumulator effects)
var _component_accumulators: Dictionary = {}          # int (comp_id) → Array[Building] (accumulator buildings per component)
var _component_accumulator_supply: Dictionary = {}    # int (comp_id) → float (total discharge contribution)
var _component_accumulator_drain: Dictionary = {}     # int (comp_id) → float (total charge consumption)
```

### Step 5: Extend test_building_ui_4.gd passive array for ACCUMULATOR

In `scripts/tests/test_building_ui_4.gd`, append `Buildings.Type.ACCUMULATOR` to the passive array.

### Step 6: Verify parse + tests

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --import --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" --quit 2>&1 | tail -15
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```

Expected: no parse errors. Accumulator class registers. `37 passed, 0 failed` (no new tests this task — Task 5 adds the accumulator-specific sub-cases).

### Step 7: Commit

```bash
git add scripts/world/buildings.gd scripts/world/accumulator.gd scripts/world/grid_world.gd scripts/tests/test_building_ui_4.gd
git commit -m "$(cat <<'EOF'
Task 4: Accumulator skeleton (state model + stub visual)

Pre-Task-5 scaffolding for the PowerNetwork 3-stage refactor:
- Buildings.Type.ACCUMULATOR DATA (1x1, dark slate swatch, NO
  slot_layout — charge is internal state, not items)
- scripts/world/accumulator.gd — make/draw stub/info_lines, NO tick
  (mutation happens in PowerNetwork pre-pass per spec Q8)
- state.charge: float = 0.0 (float for even-distribution fractions)
- Constants: MAX_CAPACITY=50, MAX_CHARGE_RATE=5, MAX_DISCHARGE_RATE=5

grid_world.gd:
- Dirty-flag hooks extended for ACCUMULATOR (place_building +
  remove_building_at)
- 4 new dict members for 3-stage flow:
  _component_raw_supply (generators only, before accumulator effects)
  _component_accumulators (per-component accumulator Building lists)
  _component_accumulator_supply (total discharge contribution)
  _component_accumulator_drain (total charge consumption)

Stub draw: just body rect + frame. Full fill-bar visual lands in Task 6
(visual-only, after Task 5 wires in the charge mutation logic).

test_building_ui_4 passive array extended for ACCUMULATOR.

37/37 PASS unchanged — no new tests this task. Accumulator-specific
sub-cases (6-9 per spec §7) land in Task 5 after the 3-stage refactor.
EOF
)"
```

---

## Task 5: PowerNetwork 3-stage refactor + accumulator math + sub-cases 16–19 (HIGHEST-RISK)

**Files:**
- Modify: `scripts/world/power_network.gd` (refactor `update_supply_demand` to 3-stage flow + add ACCUMULATOR classification in Stage 1 + Stage 2 charge/discharge math + Stage 3 effective_supply satisfaction)
- Modify: `scripts/tests/test_power_network.gd` (append sub-cases 16, 17, 18, 19)

**Purpose:** Extend `update_supply_demand` from current 1-walk to 3-stage internal flow. **CRITICAL**: Foundation's existing 10 sub-cases (1)-(10) plus this session's (11)-(15) MUST still pass after the refactor BEFORE adding accumulator sub-cases. Regression discipline is paramount.

**Watch point**: this is the highest-risk task per user. Foundation's consumer satisfaction contract (`world.power_satisfaction_at(b.anchor)`) MUST return identical values for non-accumulator networks after the refactor. Lamps continue to behave identically. The only behavior change: networks with accumulators see charge/discharge in their `_component_satisfaction`.

### Step 1: Variable name pre-check for new sub-cases

Run:
```bash
grep -n "^\s*var \(acc_b\|comp_acc\|charge_pre\|charge_post\|sat_acc\|wheel_a\|lamp_a\|acc_a\|acc_b\|acc_c\)\b" scripts/tests/test_power_network.gd
```
Expected: no matches. Variables in new sub-cases use `_acc` suffix for clarity.

### Step 2: Refactor update_supply_demand to 3-stage flow

In `scripts/world/power_network.gd`, locate the current `update_supply_demand` function. Replace its body. The new shape (concrete code below):

```gdscript
## Per-tick orchestrator. Called from grid_world._on_tick BEFORE the
## building tick loop. 3-stage flow (extended at Electricity Session 2):
##
## Stage 1: walk all buildings. Classify by type:
##   - Generators (WATER_WHEEL, WINDMILL, STEAM_GENERATOR) → sum MAX_OUTPUT
##     into _component_raw_supply when output_active.
##   - Consumers (ELECTRIC_LAMP) → sum DEMAND into _component_demand.
##   - Accumulators (ACCUMULATOR) → register in _component_accumulators
##     list per component (no supply/demand contribution yet).
##
## Stage 2: per component, compute excess = raw_supply - demand. For each
## accumulator in the component:
##   - excess > 0: charge by min(excess_per_acc, MAX_CHARGE_RATE,
##     MAX_CAPACITY - acc.charge). Mutate acc.state.charge.
##     Track total _component_accumulator_drain (acts as additional
##     "consumption" — units siphoned from the network into storage).
##   - excess < 0: discharge by min(deficit_per_acc, MAX_DISCHARGE_RATE,
##     acc.charge). Mutate acc.state.charge. Track total
##     _component_accumulator_supply (acts as additional "supply" —
##     units fed from storage into the network).
##   - excess == 0: no-op.
##
## Stage 3: effective_supply = raw_supply + accumulator_supply -
## accumulator_drain. satisfaction = min(1.0, effective_supply / max(1, demand)).
##
## State mutation in pre-pass justified: accumulator charge IS network
## state. Consumer interface contract unchanged — world.power_satisfaction_at
## returns post-accumulator satisfaction; lamps modulate brightness identically;
## future Session 4+ processors apply 1.0 / max(0.1, satisfaction) identically.
static func update_supply_demand(world) -> void:
	if world._power_network_dirty:
		rebuild_topology(world)
	# Reset all per-component accumulators.
	for comp_id in world._pole_component.values():
		world._component_supply[comp_id] = 0
		world._component_demand[comp_id] = 0
		world._component_raw_supply[comp_id] = 0
		world._component_accumulators[comp_id] = []
		world._component_accumulator_supply[comp_id] = 0.0
		world._component_accumulator_drain[comp_id] = 0.0

	# ----- Stage 1: classify and sum raw_supply + demand -----
	for anchor in world.buildings:
		var b: Building = world.buildings[anchor]
		if b.type == Buildings.Type.WATER_WHEEL:
			var gen_comp: int = _adjacent_component_id(world, b)
			if gen_comp < 0:
				continue
			if bool(b.state.get("output_active", false)):
				world._component_raw_supply[gen_comp] = int(world._component_raw_supply.get(gen_comp, 0)) + WaterWheel.MAX_OUTPUT
		elif b.type == Buildings.Type.WINDMILL:
			var gen_comp_w: int = _adjacent_component_id(world, b)
			if gen_comp_w < 0:
				continue
			if bool(b.state.get("output_active", true)):
				world._component_raw_supply[gen_comp_w] = int(world._component_raw_supply.get(gen_comp_w, 0)) + Windmill.MAX_OUTPUT
		elif b.type == Buildings.Type.STEAM_GENERATOR:
			var gen_comp_s: int = _adjacent_component_id(world, b)
			if gen_comp_s < 0:
				continue
			if bool(b.state.get("output_active", false)):
				world._component_raw_supply[gen_comp_s] = int(world._component_raw_supply.get(gen_comp_s, 0)) + SteamGenerator.MAX_OUTPUT
		elif b.type == Buildings.Type.ELECTRIC_LAMP:
			var con_comp: int = _supply_component_id(world, b)
			if con_comp < 0:
				continue
			world._component_demand[con_comp] = int(world._component_demand.get(con_comp, 0)) + ElectricLamp.DEMAND
		elif b.type == Buildings.Type.ACCUMULATOR:
			var acc_comp: int = _adjacent_component_id(world, b)
			if acc_comp < 0:
				continue
			world._component_accumulators[acc_comp].append(b)

	# ----- Stage 2: accumulator charge/discharge per component -----
	for comp_id in world._pole_component.values():
		var raw_supply: int = int(world._component_raw_supply.get(comp_id, 0))
		var demand: int = int(world._component_demand.get(comp_id, 0))
		var accumulators: Array = world._component_accumulators.get(comp_id, [])
		if accumulators.is_empty():
			continue
		var excess: int = raw_supply - demand
		var acc_count: int = accumulators.size()
		if excess > 0:
			# Charge: distribute excess evenly across accumulators.
			var excess_per_acc: float = float(excess) / float(acc_count)
			for acc in accumulators:
				var current_charge: float = float(acc.state.get("charge", 0.0))
				var capacity_remaining: float = float(Accumulator.MAX_CAPACITY) - current_charge
				var delta: float = min(excess_per_acc, float(Accumulator.MAX_CHARGE_RATE), capacity_remaining)
				if delta <= 0.0:
					continue
				acc.state["charge"] = current_charge + delta
				world._component_accumulator_drain[comp_id] = float(world._component_accumulator_drain.get(comp_id, 0.0)) + delta
		elif excess < 0:
			# Discharge: distribute deficit evenly across accumulators.
			var deficit: int = -excess
			var deficit_per_acc: float = float(deficit) / float(acc_count)
			for acc in accumulators:
				var current_charge_d: float = float(acc.state.get("charge", 0.0))
				var delta_d: float = min(deficit_per_acc, float(Accumulator.MAX_DISCHARGE_RATE), current_charge_d)
				if delta_d <= 0.0:
					continue
				acc.state["charge"] = current_charge_d - delta_d
				world._component_accumulator_supply[comp_id] = float(world._component_accumulator_supply.get(comp_id, 0.0)) + delta_d

	# ----- Stage 3: effective_supply + satisfaction -----
	# Per Foundation comment block: dem == 0 → satisfaction 1.0 (benign;
	# no consumer reads sat when no consumer exists). Reaffirmed at Task 7
	# Cluster B review.
	for comp_id in world._pole_component.values():
		var raw: int = int(world._component_raw_supply.get(comp_id, 0))
		var acc_sup: float = float(world._component_accumulator_supply.get(comp_id, 0.0))
		var acc_drain: float = float(world._component_accumulator_drain.get(comp_id, 0.0))
		var effective_supply: float = float(raw) + acc_sup - acc_drain
		# _component_supply exposes effective supply for Q-inspect and existing
		# supply_for() API — preserves Foundation contract for consumers.
		world._component_supply[comp_id] = int(round(effective_supply))
		var dem: int = int(world._component_demand.get(comp_id, 0))
		var sat: float = 1.0 if dem == 0 else min(1.0, effective_supply / float(dem))
		world._component_satisfaction[comp_id] = sat
```

**Critical detail**: `_component_supply` is now populated with EFFECTIVE supply (raw + accumulator_supply - accumulator_drain), not raw. Existing `supply_for(world, comp_id)` query returns effective supply for Q-inspect. This matches the consumer-facing intuition ("supply" = what the network can deliver right now).

Foundation consumer satisfaction contract preserved: `power_satisfaction_at(pos)` reads `_component_satisfaction[comp_id]`, which is now computed with effective_supply. Lamps don't see any difference until accumulators are placed in their network.

### Step 3: Run ALL tests — regression check Foundation sub-cases (1)–(15) MUST PASS

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```

**Expected: 37/37 PASS.** Foundation sub-cases (1)–(10) test no-accumulator networks; sub-cases (11)(12) test windmill, (13)(14)(15) test steam generator — none involve accumulators, so behavior should be identical.

**If ANY existing sub-case fails: STOP. Report BLOCKED.** Do NOT add accumulator sub-cases (16-19) on top of a regression. The 3-stage refactor must be a bit-for-bit behavior-preserving change for non-accumulator networks. Investigate the failure — likely culprit is the `_component_supply` semantic change (now effective; was raw). If Foundation sub-cases assert specific supply values, they should still see the raw value since accumulator_supply and accumulator_drain are both 0 for those tests.

### Step 4: Write failing accumulator sub-cases (16)(17)(18)(19) in test_power_network.gd

Append AFTER sub-case (15):

```gdscript

	# ===========================================================================
	# (16) ACCUMULATOR CHARGES FROM EXCESS — wheel (10) + 0 lamps + 1 accumulator
	# → excess 10, accumulator gains MAX_CHARGE_RATE (5) per tick. After 11 ticks
	# (50 / 5 = 10 ticks to fill from 0), charge caps at MAX_CAPACITY (50).
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	world.place_building(Buildings.Type.ACCUMULATOR, Vector2i(7, 5))
	# Tick wheel to set output_active.
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	# Now update_supply_demand 11 times to fully charge accumulator (50 / 5 = 10
	# ticks + 1 to verify cap behavior).
	for _i in 11:
		PowerNetwork.update_supply_demand(world)
	var acc_b: Building = world.building_at(Vector2i(7, 5))
	var charge_after_11: float = float(acc_b.state.get("charge", 0.0))
	_check(failures, charge_after_11 == float(Accumulator.MAX_CAPACITY),
		"(16) accumulator should be at MAX_CAPACITY (%d) after 11 charge ticks, got %f" % [Accumulator.MAX_CAPACITY, charge_after_11])

	# ===========================================================================
	# (17) ACCUMULATOR DISCHARGES INTO DEFICIT — pre-charged accumulator (50),
	# 0 generators + 1 lamp (demand 1). Accumulator discharges to meet demand.
	# Satisfaction should be 1.0 since accumulator can fully cover.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5))
	world.place_building(Buildings.Type.ACCUMULATOR, Vector2i(6, 5))
	world.place_building(Buildings.Type.ELECTRIC_LAMP, Vector2i(4, 5))
	var acc_b_17: Building = world.building_at(Vector2i(6, 5))
	acc_b_17.state["charge"] = 10.0   # pre-charge
	PowerNetwork.update_supply_demand(world)
	var comp_17: int = PowerNetwork.network_id_at(world, Vector2i(5, 5))
	if comp_17 >= 0:
		var sat_17: float = PowerNetwork.satisfaction_for(world, comp_17)
		_check(failures, abs(sat_17 - 1.0) < 0.001,
			"(17) accumulator discharge: satisfaction should be 1.0 (demand met by storage), got %f" % sat_17)
		# Accumulator should have discharged 1 unit (matched demand).
		var charge_post_17: float = float(acc_b_17.state.get("charge", 0.0))
		_check(failures, abs(charge_post_17 - 9.0) < 0.001,
			"(17) accumulator should have discharged 1 unit (10 - 1 = 9), got charge %f" % charge_post_17)

	# ===========================================================================
	# (18) ACCUMULATOR CAPACITY CAP — accumulator at full (50), generator
	# producing 100 excess. Charge stays at 50, no overflow.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	world.tiles[Vector2i(3, 5)] = Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE)
	world.place_building(Buildings.Type.WATER_WHEEL, Vector2i(4, 5), Belt.DIR_W)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	world.place_building(Buildings.Type.ACCUMULATOR, Vector2i(7, 5))
	var acc_b_18: Building = world.building_at(Vector2i(7, 5))
	acc_b_18.state["charge"] = 50.0   # pre-fill to cap
	TickSystem.current_tick += 1
	TickSystem.tick.emit(TickSystem.current_tick)
	PowerNetwork.update_supply_demand(world)
	var charge_post_18: float = float(acc_b_18.state.get("charge", 0.0))
	_check(failures, charge_post_18 == 50.0,
		"(18) accumulator at cap with excess: charge should stay at MAX_CAPACITY (50), got %f" % charge_post_18)

	# ===========================================================================
	# (19) MULTI-ACCUMULATOR EVEN DISTRIBUTION — 2 accumulators, generator with
	# excess 6 → each gains 3 per tick (even split).
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
		world.set_overlay(Vector2i(x, 6), Terrain.Overlay.STONE)
	# Place windmill (output 6, no resource dep — simplest) + pole + 2 accumulators.
	world.place_building(Buildings.Type.WINDMILL, Vector2i(4, 5))
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(6, 5))
	world.place_building(Buildings.Type.ACCUMULATOR, Vector2i(7, 5))
	world.place_building(Buildings.Type.ACCUMULATOR, Vector2i(5, 7))
	# Windmill is always active; no tick needed for output_active.
	# Both accumulators at 0, excess = 6 (windmill) - 0 (demand) = 6.
	# Even split: 3 per accumulator.
	PowerNetwork.update_supply_demand(world)
	var acc_a_19: Building = world.building_at(Vector2i(7, 5))
	var acc_b_19: Building = world.building_at(Vector2i(5, 7))
	var charge_a: float = float(acc_a_19.state.get("charge", 0.0))
	var charge_b: float = float(acc_b_19.state.get("charge", 0.0))
	_check(failures, abs(charge_a - 3.0) < 0.001,
		"(19) multi-accumulator even split: accumulator A should gain 3 (6 / 2), got %f" % charge_a)
	_check(failures, abs(charge_b - 3.0) < 0.001,
		"(19) multi-accumulator even split: accumulator B should gain 3 (6 / 2), got %f" % charge_b)
```

Update test_name() and success message — bump to "19 sub-cases pass: ... + steam generator + accumulator charge/discharge/cap/multi".

### Step 5: Run tests — expect 37/37 PASS with all new sub-cases passing

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```

Expected: `37 passed, 0 failed`. All 19 internal sub-cases of test_power_network.gd pass.

### Step 6: Commit

```bash
git add scripts/world/power_network.gd scripts/tests/test_power_network.gd
git commit -m "$(cat <<'EOF'
Task 5: PowerNetwork 3-stage refactor + accumulator math + sub-cases 16-19

HIGHEST-RISK TASK of Electricity Session 2. Refactors update_supply_demand
from 1-walk to 3-stage internal flow:

Stage 1: walk all buildings, classify by type:
  - Generators (WATER_WHEEL, WINDMILL, STEAM_GENERATOR) → sum MAX_OUTPUT
    into _component_raw_supply when output_active
  - Consumers (ELECTRIC_LAMP) → sum DEMAND into _component_demand
  - Accumulators (ACCUMULATOR) → register in _component_accumulators list

Stage 2: per component, compute excess = raw_supply - demand.
  - excess > 0: charge accumulators evenly, mutate state.charge, track
    _component_accumulator_drain
  - excess < 0: discharge accumulators evenly (capped by individual charge),
    mutate state.charge, track _component_accumulator_supply

Stage 3: effective_supply = raw + accumulator_supply - accumulator_drain.
  _component_supply now stores EFFECTIVE supply (preserves supply_for()
  API + Q-inspect). satisfaction = min(1.0, effective_supply / demand).

Foundation consumer satisfaction contract PRESERVED — lamps see no
behavior change unless accumulators present in their network. Regression
verified: Foundation sub-cases (1)-(10) + this session's (11)-(15) all
still PASS after refactor.

State mutation in pre-pass justified — accumulator charge IS network
state. Accumulator's own tick() is a no-op (per Task 4 spec).

test_power_network.gd sub-cases (16)(17)(18)(19) — charge from excess,
discharge into deficit, capacity cap, multi-accumulator even split.
37/37 PASS.
EOF
)"
```

---

## Task 6: Accumulator visual fill-bar (replace Task 4 stub)

**Files:**
- Modify: `scripts/world/accumulator.gd` (replace stub `draw` with full fill-bar implementation)

**Purpose:** Visual feedback — vertical fill-bar inside building rect that scales with charge level. Z-order: body → fill-bar → frame outline (bar drawn on top of body, frame on top of bar to keep visual border crisp).

### Step 1: Replace stub draw in accumulator.gd

In `scripts/world/accumulator.gd`, replace the existing `static func draw(_b, canvas, world_pos, tile_size)` stub with:

```gdscript
## Full visual: body + vertical fill-bar (bottom-up) + frame outline.
## Bar color lerps from OFF_COLOR (empty) to FULL_COLOR (full).
##
## Z-order (bottom to top):
##   1. Body rect (BASE_COLOR)
##   2. Bar frame outline (FRAME_COLOR, just the outline of the bar inset)
##   3. Bar fill (lerped color, scales bottom-up by charge fraction)
##   4. Body frame outline (FRAME_COLOR, on top of everything)
##
## Bar geometry: ~60% of building height (top 20% to bottom 20% are inset
## frame margin). Bar fills bottom-up: empty bar is just the frame outline;
## full bar fills the inner rect entirely.
static func draw(b: Building, canvas: CanvasItem, world_pos: Vector2, tile_size: int) -> void:
	var charge: float = float(b.state.get("charge", 0.0))
	var fraction: float = clamp(charge / float(MAX_CAPACITY), 0.0, 1.0)
	# 1. Body rect.
	var body_rect: Rect2 = Rect2(world_pos, Vector2(tile_size, tile_size))
	canvas.draw_rect(body_rect, BASE_COLOR, true)
	# 2. Bar frame outline (inset).
	var inset: float = float(tile_size) * 0.20
	var bar_outer: Rect2 = Rect2(
		world_pos + Vector2(inset, inset),
		Vector2(float(tile_size) - 2.0 * inset, float(tile_size) - 2.0 * inset)
	)
	canvas.draw_rect(bar_outer, FRAME_COLOR, false, 1.5)
	# 3. Bar fill (bottom-up). Inner rect tracks bar_outer bounds minus 1px
	# frame width.
	if fraction > 0.0:
		var bar_inner_max_height: float = bar_outer.size.y - 2.0
		var fill_height: float = bar_inner_max_height * fraction
		var bar_fill: Rect2 = Rect2(
			bar_outer.position + Vector2(1.0, bar_outer.size.y - 1.0 - fill_height),
			Vector2(bar_outer.size.x - 2.0, fill_height)
		)
		var bar_color: Color = OFF_COLOR.lerp(FULL_COLOR, fraction)
		canvas.draw_rect(bar_fill, bar_color, true)
	# 4. Body frame outline (on top).
	canvas.draw_rect(body_rect, FRAME_COLOR, false, 2.0)
```

### Step 2: Run tests — expect 37/37 PASS (visual-only change)

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```

Expected: `37 passed, 0 failed`. Visual change not exercised in headless (no display server).

### Step 3: Commit

```bash
git add scripts/world/accumulator.gd
git commit -m "$(cat <<'EOF'
Task 6: Accumulator visual fill-bar (replace Task 4 stub)

Replaces Task 4's body-rect-only stub with full fill-bar visual:
- Vertical fill-bar inside 60% of building height (20% inset top + bottom)
- Bar color lerps OFF_COLOR (gray) → FULL_COLOR (warm yellow, matches
  SlotWidget.BORDER_HOVER family) by charge fraction
- Bottom-up fill (empty bar is just the frame outline; full bar fills
  inner rect)
- Z-order: body → bar frame → bar fill → body frame (crisp outer border)

Visual verification deferred to PAUSE 1. 37/37 PASS unchanged (no
headless rendering).
EOF
)"
```

---

## Task 7: Hotbar Power category 3 → 6 slots

**Files:**
- Modify: `scripts/ui/hotbar.gd` (extend Power category slots array)

**Purpose:** Make 3 new buildings placeable from the hotbar UI. Order: existing (pole, wheel, lamp) + new (windmill, steam generator, accumulator). Smoke verified at PAUSE 1.

### Step 1: Locate Power category in hotbar.gd

Run:
```bash
grep -n "Power\|POWER_POLE\|WATER_WHEEL\|ELECTRIC_LAMP" scripts/ui/hotbar.gd
```

Find the existing Power category block (added at Foundation Task 8).

### Step 2: Append 3 slots

In `scripts/ui/hotbar.gd`, locate the Power category slots array. Currently:

```gdscript
	categories.append({
		"name": "Power",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.POWER_POLE },
			{ "kind": "building", "value": Buildings.Type.WATER_WHEEL },
			{ "kind": "building", "value": Buildings.Type.ELECTRIC_LAMP },
		],
		"selected": 0,
	})
```

Replace with the 6-slot version:

```gdscript
	categories.append({
		"name": "Power",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.POWER_POLE },
			{ "kind": "building", "value": Buildings.Type.WATER_WHEEL },
			{ "kind": "building", "value": Buildings.Type.ELECTRIC_LAMP },
			# Electricity Session 2 — generators + storage.
			{ "kind": "building", "value": Buildings.Type.WINDMILL },
			{ "kind": "building", "value": Buildings.Type.STEAM_GENERATOR },
			{ "kind": "building", "value": Buildings.Type.ACCUMULATOR },
		],
		"selected": 0,
	})
```

### Step 3: Run tests — expect 37/37 PASS

Hotbar changes don't affect tests.

### Step 4: Commit

```bash
git add scripts/ui/hotbar.gd
git commit -m "$(cat <<'EOF'
Task 7: Hotbar Power category 3 → 6 slots

Appends WINDMILL + STEAM_GENERATOR + ACCUMULATOR to the Power
category after existing POWER_POLE/WATER_WHEEL/ELECTRIC_LAMP. Order:
generators first, then consumer, then new generators, then storage.

Smoke verification deferred to PAUSE 1. 37/37 PASS unchanged.
EOF
)"
```

---

## Task 8: Save round-trip sub-case (20) — accumulator charge preserved

**Files:**
- Modify: `scripts/tests/test_power_network.gd` (append sub-case 20)

**Purpose:** Lock down save/load preservation for accumulator charge. Place accumulator with mid-charge value, save, reload, verify charge preserved. Should pass on first run since save schema unchanged and state fields persist via existing serialization.

### Step 1: Append sub-case (20) to test_power_network.gd

Append AFTER sub-case (19):

```gdscript

	# ===========================================================================
	# (20) ACCUMULATOR SAVE ROUND-TRIP — accumulator with charge=25, save,
	# reload, verify charge preserved. Validates that float state field
	# survives save schema v18 serialization unchanged.
	# ===========================================================================
	world.queue_free()
	world = GridWorldScript.new()
	parent.add_child(world)
	for x in range(0, 15):
		world.set_overlay(Vector2i(x, 5), Terrain.Overlay.STONE)
	world.place_building(Buildings.Type.POWER_POLE, Vector2i(5, 5))
	world.place_building(Buildings.Type.ACCUMULATOR, Vector2i(6, 5))
	var acc_b_20: Building = world.building_at(Vector2i(6, 5))
	acc_b_20.state["charge"] = 25.0   # mid-range value to validate save
	# Save.
	var orig_path_20: String = SaveSystem.save_path
	SaveSystem.save_path = TEST_SAVE_PATH
	var player_a_20 := Node2D.new()
	parent.add_child(player_a_20)
	if not SaveSystem.save_game(world, player_a_20, Inventory.new(16)):
		SaveSystem.save_path = orig_path_20
		_disconnect(world)
		player_a_20.queue_free()
		if FileAccess.file_exists(TEST_SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
		return { "ok": false, "message": "(20) save_game failed for accumulator round-trip" }
	# Load into a fresh world.
	_disconnect(world)
	world = GridWorldScript.new()
	parent.add_child(world)
	var player_b_20 := Node2D.new()
	parent.add_child(player_b_20)
	var result_20: LoadResult = SaveSystem.load_game(world, player_b_20, Inventory.new(16))
	if not result_20.success:
		SaveSystem.save_path = orig_path_20
		_disconnect(world)
		player_a_20.queue_free()
		player_b_20.queue_free()
		if FileAccess.file_exists(TEST_SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
		return { "ok": false, "message": "(20) load_game failed: %s" % result_20.error_message }
	# Verify charge preserved.
	var acc_after_20: Building = world.building_at(Vector2i(6, 5))
	_check(failures, acc_after_20 != null and acc_after_20.type == Buildings.Type.ACCUMULATOR,
		"(20) loaded building at (6,5) should be ACCUMULATOR")
	if acc_after_20 != null:
		var charge_post_load: float = float(acc_after_20.state.get("charge", -1.0))
		_check(failures, abs(charge_post_load - 25.0) < 0.001,
			"(20) loaded accumulator charge should be 25.0, got %f" % charge_post_load)
	# Cleanup.
	SaveSystem.save_path = orig_path_20
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	player_a_20.queue_free()
	player_b_20.queue_free()
```

Update success message to "20 sub-cases pass: ... + accumulator save round-trip".

### Step 2: Run tests — expect 37/37 PASS

Expected: passes on first run (save schema unchanged; float fields serialize as-is via existing pattern).

### Step 3: Commit

```bash
git add scripts/tests/test_power_network.gd
git commit -m "$(cat <<'EOF'
Task 8: Save round-trip sub-case (20) — accumulator charge preserved

Place accumulator with charge=25, save via SaveSystem (TEST_SAVE_PATH),
reload into fresh world, verify accumulator type preserved + charge
value preserved.

Save schema v18 handles float state fields via existing serialization.
No schema bump required. Last code task of session — PAUSE 1 + PAUSE 2
+ ship follow.

37/37 PASS.
EOF
)"
```

---

## Task 9: PAUSE 1 — visual smoke

**Files:** none (manual gate)

**Purpose:** User-driven visual verification of 3 new buildings + accumulator behavior. Visual aspects headless tests can't cover.

### Step 1: Launch game

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9"
```

### Step 2: User verifies smoke matrix

| # | Check | What to verify |
|---|---|---|
| 1 | Hotbar Power category has 6 slots | bone-white windmill + dark-iron steam + dark-slate accumulator after the existing 3 |
| 2 | Windmill | placeable anywhere on grass/stone/path, 2×2, rotating sails visible (slower than water wheel), Q-inspect shows "Output: 6/6 units (always active)" |
| 3 | Steam Generator | placeable on stone/path, 2×2, fuel slot accepts WOOD/COAL/FUEL_BRIQUETTE. Empty fuel → no smoke; with fuel → smoke puffs visible above smokestack. Q-inspect shows Output + Burner fuel state. |
| 4 | Accumulator | placeable anywhere on grass/stone/path, 1×1, fill-bar starts gray (empty). Connect to a network with excess supply → fill-bar grows bottom-up + color shifts gray→golden. Drain network (more demand than supply) → fill-bar shrinks; if accumulator drains fully, fill returns to gray. |
| 5 | Accumulator Q-inspect | shows "Charge: X / 50 units (Y%)" + network info |

### Step 3: Report PASS or FAIL with detail

If FAIL: per UX iteration trap protocol, after 2 visual iterations on a single item, STOP and force a rule conversation.

### Step 4: Close game on PASS, proceed to PAUSE 2

---

## Task 10: PAUSE 2 — full gameplay

**Files:** none (manual gate)

**Purpose:** Multi-generator, multi-accumulator factory exercising charge/discharge cycles, brownout recovery, save round-trip mid-charge.

### Step 1: Launch game (same command as Task 9)

### Step 2: User builds a representative factory + plays a session segment

Suggested 5-10 minute session:

- Place 1 windmill + 1 water wheel + 1 steam generator (fueled) on a shared pole network
- Wire 5+ lamps to that network — observe full brightness
- Place 2-3 accumulators on the same network — observe them charging during excess
- Remove the water wheel (or move it away from water) — observe satisfaction stays at 1.0 while accumulators discharge to cover deficit, then lamps dim once accumulators drain
- Add the water wheel back — accumulators recharge, lamps return to full brightness
- Mid-charge save → reload → all 3 generator types and accumulator charges preserved; network behavior continues from saved state

### Step 3: Report PASS or FAIL

PASS criteria: all 3 building types work in concert + accumulator charge/discharge cycles behave per spec + no Foundation regressions (existing pole/wheel/lamp behavior unchanged).

### Step 4: Close game on PASS, proceed to ship

---

## Task 11: Ship — PROJECT_LOG + NOTES + tag + push

**Files:**
- Modify: `PROJECT_LOG.md` (prepend session entry)
- Modify: `NOTES.md` (DBV count 6 → 7 + Electricity Arc tracker update — Session 2 SHIPPED)

### Step 1: Prepend PROJECT_LOG entry

Open `PROJECT_LOG.md`. Insert new entry at the top (after file header, before previous most-recent entry — `QoL Cluster B`). Use template:

```markdown
---

## Electricity Arc Session 2 — More Generators + Accumulator

**Date:** 2026-05-15
**Tag:** `session-electricity-generators-storage`
**Save schema:** v18 unchanged (all UI/state-layer; append-only enum + float state fields persist via existing serialization)
**Test count:** 37/37 PASS (internal sub-cases in test_power_network.gd grow 10 → 20)

Continues Electricity Foundation. Adds 3 new buildings (Windmill, Steam Generator, Accumulator) + extends `PowerNetwork.update_supply_demand` from 1-walk to 3-stage internal flow with accumulator charge/discharge math.

### What shipped

- **Windmill** (1 new file, 1 enum entry + DATA + dispatch): 2×2, no resource dep, always `output_active=true`, MAX_OUTPUT=6 (60% of WaterWheel — placement-flexibility tradeoff). Visual: bone-white sails on stone base, 4 rotating blades.
- **Steam Generator** (1 new file, 1 enum entry + DATA + dispatch + Burner integration): 5th Burner consumer (after Drill / Smelter / Inserter ×3 tiers). 2×2, fuel slot accepts WOOD/COAL/FUEL_BRIQUETTE, MAX_OUTPUT=20 when active, cycle-based fuel (1 unit per CYCLE_TICKS=20 ticks). Visual: industrial body + smokestack + steam puff animation when active.
- **Accumulator** (1 new file, 1 enum entry + DATA + dispatch + NO tick): 1×1, MAX_CAPACITY=50, MAX_CHARGE_RATE=5, MAX_DISCHARGE_RATE=5. State: `charge: float` (float for even-distribution fractions). Visual: vertical fill-bar inset inside body, lerps OFF_COLOR (gray) → FULL_COLOR (warm yellow) by charge fraction. Q-inspect shows "Charge: X/50 units (Y%)".
- **PowerNetwork 3-stage refactor** (extended update_supply_demand): Stage 1 classifies buildings + sums raw_supply + demand. Stage 2 distributes excess/deficit across accumulators evenly (mutating charge state). Stage 3 computes effective_supply = raw + accumulator_supply - accumulator_drain and satisfaction = min(1.0, effective_supply / demand). Foundation consumer satisfaction contract preserved bit-for-bit for non-accumulator networks.
- **Hotbar Power category** grows 3 → 6 slots.
- **8 new test sub-cases** in test_power_network.gd (Windmill ×2, Steam Generator ×3, Accumulator behavior ×4, save round-trip ×1).

### Decisions

- **Q1 Windmill footprint**: 2×2 (parity with WaterWheel, visual weight signals "substantial generator")
- **Q2 Windmill output**: 6 power units (40% below WaterWheel; reflects free-placement advantage)
- **Q3 Windmill adjacency**: strict cardinal pole adjacency (Foundation Q3 reused)
- **Q4 Steam Generator architecture**: single building, not boiler+engine chain. fluids.gd has only WATER type — single Steam Generator avoids fluid-system expansion
- **Q5 Steam fuel rate**: cycle-based, 1 unit per 20 ticks (1.0s), matches Smelter convention
- **Q6 Steam output**: 20 power units (2× WaterWheel, reflects fuel overhead)
- **Q7 Accumulator state**: `charge: float`, capacity 50, ±5/tick. Float allows even-distribution fractions
- **Q8 Network logic**: 3-stage internal flow in update_supply_demand. State mutation in pre-pass justified — accumulators ARE network state. Accumulator's own tick() is a no-op
- **Q9 Accumulator visual**: vertical fill-bar, gray→golden lerp, bottom-up fill, 60% of building height inset
- **Q10 Multi-accumulator distribution**: even (predictable; priority-based deferred to future)
- **No save schema bump**: append-only enum + float state field via existing serialization. Stays at v18

### Lessons

- **DBV at 7 catches** (Cluster A + Inserter Arc ×2 + Electricity Foundation ×2 + Cluster B spec→plan + Electricity Session 2 spec). 100% capture rate. Electricity Session 2 spec used DBV pre-implementation to verify Burner API, WaterWheel pattern, single-fluid-WATER constraint (which validated single-building Steam Generator design), and Smelter DATA shape — caught all 4 verifications pre-implementation, eliminating any first-task BLOCKED scenarios.
- **3-stage refactor regression discipline (Task 5)**: Foundation's 10 sub-cases + Session 2's earlier sub-cases (11-15) MUST PASS after the refactor before any accumulator-specific sub-cases (16-19) added. Bit-for-bit behavior preservation for non-accumulator networks. Verified at Step 3 of Task 5.
- **State mutation in pre-pass justified for accumulators**: charge IS network state. Per Foundation precedent (output_active set in generator tick), accumulator charge could have lived in accumulator.tick(); but the 3-stage flow needs the post-discharge value for satisfaction in the SAME tick — splitting across pre-pass + building tick would either delay satisfaction by 1 tick OR require a 2-pass tick loop (more complex). Pre-pass mutation is the right call for tightly-coupled network state.
- **Parametric Burner consumer pattern proven** (5th application): Steam Generator integration was ~30 lines mirroring Smelter. Future power tiers (combustion engine? gas turbine?) extend the same way.

### Cluster status

Electricity Arc: Sessions 1 + 2 of 5 shipped. Sessions 3 (pole tiers parametric), 4 (electric processors using `1.0 / max(0.1, satisfaction)` cycle multiplier), and 5 (electric inserter — closes both Inserter Arc and Electricity Arc) remaining.

### Commit chain (compact)

`56130e2` spec → `<plan SHA>` plan → `<T2-T8 SHAs>` 7 task commits → `<ship SHA>` ship. Detailed commit shas filled in at commit time.

---
```

### Step 2: Update NOTES.md

(a) Find the DBV section header (`## Working protocol: Design Brief Verification (validated session-inserter-long-reach)`). Update the count:

```markdown
Senior dev briefs describe code changes at conceptual level; implementation agents should ALWAYS verify against actual current code shape via code search + line citations before accepting brief assumptions. **Seven data points** across Cluster A + Inserter Arc + Electricity Arc + Cluster B + Electricity Session 2:
```

Append a new data point:

```markdown
- **Electricity Session 2 spec (4 verifications pre-implementation)**: brainstorming-time DBV verified Burner API signature at `burner.gd:59` (try_pull_fuel + consume_tick), WaterWheel module pattern at `water_wheel.gd:1-90` (precedent for Windmill + Steam Generator), fluids.gd having only WATER type (validating single-building Steam Generator design without fluid expansion), and Smelter DATA shape at `buildings.gd:475-507` (fuel slot template). All caught pre-implementation; no first-task BLOCKED scenarios. Shows DBV value applies at spec-writing time, not just brief-reading time.
```

Update the "Pattern" paragraph: "100% of conceptual errors caught by code-citation verification across 7 incidents."

(b) Find the Electricity Arc tracker section. Update Session 2 status:

```markdown
- **Session 2 (`session-electricity-generators-storage`)** — SHIPPED. Windmill (2×2, no resource dep, MAX_OUTPUT=6) + Steam Generator (2×2, Burner 5th consumer, MAX_OUTPUT=20, CYCLE_TICKS=20) + Accumulator (1×1, charge: float, capacity 50, ±5/tick, vertical fill-bar visual). PowerNetwork.update_supply_demand extended to 3-stage flow (raw_supply+demand → accumulator charge/discharge → effective_supply satisfaction). Foundation consumer contract preserved. 8 new test sub-cases. 37/37 PASS. Save schema unchanged v18.
```

Mark remaining sessions:
```markdown
- **Session 3 — Pole Tiers**: medium pole + substation via RANGE_BY_TYPE / SUPPLY_RADIUS_BY_TYPE parametric tables. Reuses BFS — only lookups change.
- **Session 4 — Electric Processors**: electric variants of smelter / drill. First consumers using `1.0 / max(0.1, satisfaction)` cycle-multiplier contract.
- **Session 5 — Electric Inserters**: closes both Inserter Arc AND Electricity Arc.
```

### Step 3: Final test run

```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn"
```
Expected: `37 passed, 0 failed`.

### Step 4: Commit ship entry

```bash
git add PROJECT_LOG.md NOTES.md
git commit -m "$(cat <<'EOF'
Ship session-electricity-generators-storage: PROJECT_LOG + NOTES

PROJECT_LOG: full session entry. What shipped (3 new buildings:
Windmill / Steam Generator / Accumulator; PowerNetwork 3-stage refactor;
hotbar 3→6 slots; 8 new test sub-cases). Decisions (Q1-Q10 all locked
per spec). Lessons (DBV at 7 catches with brainstorming-time pre-impl
verification; 3-stage refactor regression discipline; state-mutation-
in-pre-pass justified for accumulators).

NOTES: DBV count updated 6 → 7 with new Electricity Session 2 spec
entry (4-verifications-pre-impl pattern). Electricity Arc tracker
updated — Session 2 SHIPPED; Sessions 3-5 remaining.

Final test count: 37/37 PASS. test_power_network.gd internal sub-cases
grew 10 → 20. Save schema unchanged at v18. Ready for tag + push.
EOF
)"
```

### Step 5: Tag commit

```bash
git tag session-electricity-generators-storage
git log --oneline -1
git tag --list | grep -i electric
```
Expected: 2 electric tags — `session-electricity-foundation` + `session-electricity-generators-storage`.

### Step 6: Push branch + tag

```bash
git push origin claude/silly-bardeen-3279e9
git push origin session-electricity-generators-storage
```

### Step 7: Verify on origin

```bash
git ls-remote origin refs/heads/claude/silly-bardeen-3279e9 refs/tags/session-electricity-generators-storage
```
Expected: both refs at the ship commit SHA.

### Step 8: Report to user

Report: ship commit SHA, tag pushed, test count (37/37 unchanged at runner level — internal sub-cases grew 10 → 20), total commits this session, total tag count (34 → 35).

---

## Self-review (writing-plans skill, completed at plan-write time)

**Spec coverage:**

- Spec §4.Q1-Q3 (Windmill): Task 2 ✓
- Spec §4.Q4-Q6 (Steam Generator): Task 3 ✓
- Spec §4.Q7 (Accumulator state): Tasks 4 (skeleton) + 5 (math) ✓
- Spec §4.Q8 (3-stage network logic): Task 5 ✓
- Spec §4.Q9 (Accumulator visual): Task 6 ✓
- Spec §4.Q10 (Even distribution): Task 5 sub-case (19) ✓
- Spec §5 (building specs): Tasks 2, 3, 4, 6 ✓
- Spec §6 (module changes): Tasks 2, 3, 4, 5 ✓
- Spec §7 (~8 new test sub-cases): Tasks 2 (×2), 3 (×3), 5 (×4), 8 (×1) — total 10 (slight over-delivery vs ~8 estimate) ✓
- Spec §8 (touchpoint inventory): all 11 items mapped to task steps ✓
- Spec §9 (implementation order): reflected in Task 2-11 sequence ✓
- Spec §10 (validation criteria): reflected in PAUSE 1 + PAUSE 2 smoke (Tasks 9 + 10) ✓
- Spec §11 (out-of-scope reminders): not in any task — out-of-scope items correctly NOT addressed ✓

**Placeholder scan:** No TBD / "implement appropriately" / "similar to Task N" patterns. Each task has complete code blocks.

**Type consistency:**
- `Windmill.MAX_OUTPUT` = 6, used Tasks 2 + 5
- `SteamGenerator.MAX_OUTPUT` = 20, `SteamGenerator.CYCLE_TICKS` = 20, `SteamGenerator.FUEL_PORT_DIR` = Belt.DIR_S, used Tasks 3 + 5
- `Accumulator.MAX_CAPACITY` = 50, `Accumulator.MAX_CHARGE_RATE` = 5, `Accumulator.MAX_DISCHARGE_RATE` = 5, used Tasks 4 + 5 + 6 + 8
- `PowerNetwork.update_supply_demand(world)` — signature unchanged (still takes world only); internal flow extended
- New dict members: `_component_raw_supply`, `_component_accumulators`, `_component_accumulator_supply`, `_component_accumulator_drain` — used consistently across Tasks 4 (declared in grid_world) + 5 (populated and consumed in power_network)

No type drift across tasks. Plan ready for execution.
