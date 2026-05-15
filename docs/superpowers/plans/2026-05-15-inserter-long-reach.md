# Long-Reach Inserter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `LONG_REACH_INSERTER` as the third tier in the Inserter parametric family — 2-tile reach, 1.5s cycle, no filter, rust-red color.

**Architecture:** Extend existing parametric tables in `inserter.gd` (CYCLE_TICKS_BY_TYPE, BODY_COLOR_BY_TYPE) with new tier rows. Introduce **new** `REACH_BY_TYPE` table with `reach(b)` accessor and refactor existing `ARM_LENGTH` const into an `ARM_LENGTH_BY_TYPE` table with `arm_length(b)` accessor. `source_tile()` / `dest_tile()` multiply offset vector by `reach(b)`. Tick logic stays tier-agnostic (zero changes). Reuses existing `InserterPanel` (no filter row). Append-only enum + DATA in `buildings.gd`. Save schema unchanged at v18.

**Tech Stack:** Godot 4.6.2, GDScript, static module pattern (`class_name Inserter extends RefCounted`), Burner module fuel integration, `TickSystem` headless tests via `scripts/tests/test_runner.gd`.

**Plan source:** `docs/superpowers/specs/2026-05-15-inserter-long-reach-design.md` (committed at `0612547`).

---

## File map

| File | Purpose | Change type |
|---|---|---|
| `scripts/world/buildings.gd` | Type enum, DATA, dispatch tables | Modify (append-only) |
| `scripts/world/inserter.gd` | Parametric tables + accessors + source/dest/draw | Modify (refactor + extend) |
| `scripts/main.gd` | Building → panel dispatch | Modify (append case) |
| `scripts/ui/hotbar.gd` | Inserters category slot list | Modify (append slot) |
| `scripts/tests/test_inserter.gd` | Inserter test sub-cases | Modify (append 5 sub-cases) |
| `PROJECT_LOG.md` | Session log entry | Modify (prepend entry) |
| `NOTES.md` | Working protocols / pins | Modify (add pattern observation) |
| `docs/superpowers/plans/2026-05-15-inserter-long-reach.md` | This plan | Already created |

---

## Task overview

| # | Task | TDD red | TDD green | Manual gate |
|---|---|---|---|---|
| 1 | Threshold audit (verify 34/34 baseline) | — | run tests | — |
| 2 | Parametric refactor: ARM_LENGTH const→table + new REACH_BY_TYPE | sub-case (11) regression FAIL | accessors + source/dest update | — |
| 3 | Add LONG_REACH_INSERTER tier (enum + DATA + dispatch + rows) | sub-cases (12)(13) FAIL | append all entries atomically | — |
| 4 | Hotbar + panel routing | — | append slot + dispatch case | — |
| 5 | Cross-tile transport integration test | sub-case (14) FAIL | already wired in T3+T4 — should PASS | — |
| 6 | Save round-trip test | sub-case (15) FAIL | append-only enum + .get() defaults → PASS | — |
| 7 | PAUSE 1 visual + PAUSE 2 gameplay | — | — | user smoke |
| 8 | Ship (PROJECT_LOG + NOTES + tag + push) | — | — | — |

**Test sub-case numbering reminder:** test_inserter.gd already has sub-cases (1)–(10). New sub-cases (11)–(15) append inside the same `run()` function. The TESTS array in `test_runner.gd` stays at 34 entries — the "PASS inserter" description line grows.

**Subagent protocol:** Each code task (T2–T6) gets the standard triad — implementer + spec reviewer + code quality reviewer (line-quoting enabled). Manual T7 + T8 stay with the controller. Strengthened scope-deviation protocol applies: implementer MUST flag any change beyond the task's listed file edits, including silent default-value additions.

---

## Task 1: Threshold audit

**Files:** none (verification only)

**Purpose:** Confirm 34/34 PASS baseline before any change. Establishes the regression ceiling.

- [ ] **Step 1: Verify HEAD + working tree**

Run:
```bash
git status
git log --oneline -1
```
Expected output:
- Working tree clean
- HEAD is `0612547` (Spec: Long-Reach Inserter)

- [ ] **Step 2: Run full test suite**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: `34 passed, 0 failed`. Three intentional stderr noises (save-migration negative paths, slot-handler headless popup-parent reuse) — these are NOT failures.

- [ ] **Step 3: No commit (verification only)**

Proceed to Task 2.

---

## Task 2: Parametric refactor — ARM_LENGTH const → table + new REACH_BY_TYPE

**Files:**
- Modify: `scripts/world/inserter.gd:55-104` (table additions, accessor additions, ARM_LENGTH const removal)
- Modify: `scripts/world/inserter.gd:195-204` (source_tile / dest_tile)
- Modify: `scripts/world/inserter.gd:506` (arm_len uses arm_length accessor)
- Modify: `scripts/tests/test_inserter.gd` (append sub-case 11 — regression)

**Purpose:** Refactor `const ARM_LENGTH` into the `*_BY_TYPE` dispatch pattern + introduce REACH_BY_TYPE with a default-1 fallback. This is the only structural change to `inserter.gd`; existing tier behavior is unchanged. TDD red comes from the new accessor calls in sub-case (11).

- [ ] **Step 1: Write the failing regression sub-case (11) — append inside test_inserter.gd run()**

Find the end of sub-case (10) in `scripts/tests/test_inserter.gd` and append:

```gdscript
	# ===========================================================================
	# (11) PARAMETRIC REFACTOR REGRESSION — Session 3 (long-reach prep).
	# Guards the ARM_LENGTH const → ARM_LENGTH_BY_TYPE refactor and the new
	# REACH_BY_TYPE accessor. Asserts that basic + fast tiers' values are
	# unchanged after the refactor.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.INSERTER, Vector2i(10, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.FAST_INSERTER, Vector2i(15, 10), Belt.DIR_E)
	var basic_b: Building = world.building_at(Vector2i(10, 10))
	var fast_b: Building = world.building_at(Vector2i(15, 10))
	# Cycle ticks unchanged (already covered by (1)(2), repeated here as a
	# package — readers landing on (11) get the full refactor contract).
	_check(failures, Inserter.cycle_ticks(basic_b) == 20,
		"(11) basic cycle_ticks should remain 20, got %d" % Inserter.cycle_ticks(basic_b))
	_check(failures, Inserter.cycle_ticks(fast_b) == 10,
		"(11) fast cycle_ticks should remain 10, got %d" % Inserter.cycle_ticks(fast_b))
	# NEW: reach() accessor returns 1 for both pre-existing tiers.
	_check(failures, Inserter.reach(basic_b) == 1,
		"(11) basic reach should be 1, got %d" % Inserter.reach(basic_b))
	_check(failures, Inserter.reach(fast_b) == 1,
		"(11) fast reach should be 1, got %d" % Inserter.reach(fast_b))
	# NEW: arm_length() accessor returns 0.55 for both pre-existing tiers
	# (was a const before the refactor; baseline preserved).
	_check(failures, abs(Inserter.arm_length(basic_b) - 0.55) < 0.001,
		"(11) basic arm_length should be 0.55, got %f" % Inserter.arm_length(basic_b))
	_check(failures, abs(Inserter.arm_length(fast_b) - 0.55) < 0.001,
		"(11) fast arm_length should be 0.55, got %f" % Inserter.arm_length(fast_b))
	# source_tile / dest_tile remain 1-tile offset for both tiers across rotations.
	for dir in [Belt.DIR_E, Belt.DIR_S, Belt.DIR_W, Belt.DIR_N]:
		basic_b.state["dir"] = dir
		fast_b.state["dir"] = dir
		var v: Vector2i = Belt.DIR_VECS[dir]
		var basic_expected_src: Vector2i = Vector2i(basic_b.anchor.x - v.x, basic_b.anchor.y - v.y)
		var basic_expected_dst: Vector2i = Vector2i(basic_b.anchor.x + v.x, basic_b.anchor.y + v.y)
		_check(failures, Inserter.source_tile(basic_b) == basic_expected_src,
			"(11) basic source_tile dir=%d should be %s, got %s" % [dir, str(basic_expected_src), str(Inserter.source_tile(basic_b))])
		_check(failures, Inserter.dest_tile(basic_b) == basic_expected_dst,
			"(11) basic dest_tile dir=%d should be %s, got %s" % [dir, str(basic_expected_dst), str(Inserter.dest_tile(basic_b))])
		var fast_expected_src: Vector2i = Vector2i(fast_b.anchor.x - v.x, fast_b.anchor.y - v.y)
		var fast_expected_dst: Vector2i = Vector2i(fast_b.anchor.x + v.x, fast_b.anchor.y + v.y)
		_check(failures, Inserter.source_tile(fast_b) == fast_expected_src,
			"(11) fast source_tile dir=%d should be %s, got %s" % [dir, str(fast_expected_src), str(Inserter.source_tile(fast_b))])
		_check(failures, Inserter.dest_tile(fast_b) == fast_expected_dst,
			"(11) fast dest_tile dir=%d should be %s, got %s" % [dir, str(fast_expected_dst), str(Inserter.dest_tile(fast_b))])
```

Also update `test_name()` description to include "+ refactor regression":
```gdscript
static func test_name() -> String:
	return "inserter (parametric refactor + filter pickup + drop-to-set + RMB-clear + save + fuel-port fix + refactor regression)"
```

- [ ] **Step 2: Run tests to verify (11) fails with parse error**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: parse error / runtime error on `Inserter.reach(...)` and `Inserter.arm_length(...)` — these accessors don't exist yet. Test suite reports failure on `test_inserter.gd`.

- [ ] **Step 3: Refactor inserter.gd — remove ARM_LENGTH const, add tables + accessors**

In `scripts/world/inserter.gd`, locate line 72:
```gdscript
# Animation parameter shared across tiers (LONG_INSERTER would override).
const ARM_LENGTH: float = 0.55       # fraction of tile_size
```

Replace with:
```gdscript
# Per-tier reach (in tiles). Source = anchor - reach*DIR_VECS[dir]; dest =
# anchor + reach*DIR_VECS[dir]. New table introduced at session-inserter-
# long-reach to support reach as an orthogonal upgrade axis from speed.
# Default fallback = 1 (basic-equivalent — preserves existing tier behavior).
#   INSERTER:             1 — basic (Session 1)
#   FAST_INSERTER:        1 — fast (Session 2)
#   LONG_REACH_INSERTER:  added at session-inserter-long-reach (Session 3)
const REACH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:      1,
	Buildings.Type.FAST_INSERTER: 1,
}
const REACH_DEFAULT: int = 1

# Per-tier arm length (fraction of tile_size). REFACTORED from a single
# `const ARM_LENGTH = 0.55` at session-inserter-long-reach — long-reach
# tier needs a longer arm visual, so the param becomes per-type. Baseline
# 0.55 preserved for INSERTER / FAST_INSERTER (pure additive change).
#   INSERTER:             0.55 — basic
#   FAST_INSERTER:        0.55 — fast (visually identical to basic)
#   LONG_REACH_INSERTER:  added at session-inserter-long-reach (Session 3)
const ARM_LENGTH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:      0.55,
	Buildings.Type.FAST_INSERTER: 0.55,
}
const ARM_LENGTH_DEFAULT: float = 0.55
```

In `scripts/world/inserter.gd`, locate the accessor block around lines 99-104:
```gdscript
## Cycle ticks for this inserter's tier. Public API — also called by
## InserterPanel / FastInserterPanel for "Cycle: Xs" displays.
static func cycle_ticks(b: Building) -> int:
	return int(CYCLE_TICKS_BY_TYPE.get(b.type, CYCLE_TICKS_DEFAULT))

## Body color for this inserter's tier. Public API — used by draw().
static func body_color(b: Building) -> Color:
	return BODY_COLOR_BY_TYPE.get(b.type, BODY_COLOR_DEFAULT)
```

Append two new accessors directly after `body_color`:
```gdscript

## Reach (in tiles) for this inserter's tier. Public API — used by
## source_tile() and dest_tile() to compute the offset along b.dir.
## Default fallback = 1 (basic-equivalent).
static func reach(b: Building) -> int:
	return int(REACH_BY_TYPE.get(b.type, REACH_DEFAULT))

## Arm length (fraction of tile_size) for this inserter's tier. Public API
## — used by draw(). Default fallback = 0.55 (basic-equivalent baseline).
static func arm_length(b: Building) -> float:
	return float(ARM_LENGTH_BY_TYPE.get(b.type, ARM_LENGTH_DEFAULT))
```

- [ ] **Step 4: Update source_tile / dest_tile to multiply by reach**

In `scripts/world/inserter.gd`, locate lines 195-204:
```gdscript
## Source tile = anchor + opposite-of-dir. dir=E → source is west.
static func source_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	return Vector2i(b.anchor.x - v.x, b.anchor.y - v.y)

## Destination tile = anchor + dir. dir=E → destination is east.
static func dest_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	return Vector2i(b.anchor.x + v.x, b.anchor.y + v.y)
```

Replace with:
```gdscript
## Source tile = anchor + opposite-of-dir * reach. dir=E, reach=1 → source
## is west (1 tile away); reach=2 → source is 2 tiles west.
static func source_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	var r: int = reach(b)
	return Vector2i(b.anchor.x - v.x * r, b.anchor.y - v.y * r)

## Destination tile = anchor + dir * reach. dir=E, reach=1 → destination
## is east (1 tile away); reach=2 → destination is 2 tiles east.
static func dest_tile(b: Building) -> Vector2i:
	var d: int = int(b.state.get("dir", 0))
	var v: Vector2i = Belt.DIR_VECS[d]
	var r: int = reach(b)
	return Vector2i(b.anchor.x + v.x * r, b.anchor.y + v.y * r)
```

- [ ] **Step 5: Update draw() to use arm_length accessor**

In `scripts/world/inserter.gd`, locate line 506:
```gdscript
		# Draw arm — line from pivot to arm tip.
		var arm_len: float = float(tile_size) * ARM_LENGTH
```

Replace with:
```gdscript
		# Draw arm — line from pivot to arm tip. Arm length is per-tier
		# (long-reach uses 2x); see ARM_LENGTH_BY_TYPE.
		var arm_len: float = float(tile_size) * arm_length(b)
```

- [ ] **Step 6: Run tests to verify (11) passes and all 34 still pass**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: `34 passed, 0 failed`. The "PASS inserter" line now includes regression coverage.

- [ ] **Step 7: Commit**

```bash
git add scripts/world/inserter.gd scripts/tests/test_inserter.gd
git commit -m "$(cat <<'EOF'
Task 2: Parametric refactor — ARM_LENGTH const→table + new REACH_BY_TYPE

Refactor `const ARM_LENGTH = 0.55` into ARM_LENGTH_BY_TYPE dictionary +
arm_length(b) accessor. Add new REACH_BY_TYPE dictionary + reach(b)
accessor with default fallback = 1. source_tile() / dest_tile() now
multiply the direction vector by reach(b). draw() uses arm_length(b).

Baseline 0.55 preserved for INSERTER / FAST_INSERTER — pure additive
change, no visual or behavioral change to existing tiers.

Test_inserter.gd sub-case (11) added: parametric refactor regression
asserting basic + fast cycle_ticks/reach/arm_length values across all
4 rotations. 34/34 still PASS.

Prep step for Session 3 (long-reach tier). Tier addition follows in Task 3.
EOF
)"
```

---

## Task 3: Add LONG_REACH_INSERTER tier — enum + DATA + dispatch + parametric rows

**Files:**
- Modify: `scripts/world/buildings.gd:81` (enum append)
- Modify: `scripts/world/buildings.gd:~589` (DATA entry — append after FAST_INSERTER block)
- Modify: `scripts/world/buildings.gd:794` (`make` dispatch case)
- Modify: `scripts/world/buildings.gd:825` (`tick_one` case label)
- Modify: `scripts/world/buildings.gd:886` (`draw_one` case label)
- Modify: `scripts/world/buildings.gd:1086` (`info_lines` case label)
- Modify: `scripts/world/inserter.gd:55-78` (rows for CYCLE_TICKS, BODY_COLOR, REACH, ARM_LENGTH)
- Modify: `scripts/tests/test_inserter.gd` (append sub-cases 12 + 13)

**Purpose:** Append the new tier atomically across all parametric tables and dispatch cases. After this task, the tier exists structurally but isn't yet placeable via hotbar (Task 4) or visible in panel routing (Task 4).

- [ ] **Step 1: Write failing sub-cases (12) and (13) — append inside test_inserter.gd run()**

Append after sub-case (11):

```gdscript
	# ===========================================================================
	# (12) LONG-REACH INSERTER CYCLE TIMING — 30 ticks per cycle (1.5s @ 20 TPS).
	# Drop fires when cycle_progress first reaches 0.5; with inc = 1/30, that's
	# the 15th tick of WORKING_OUT.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	if not world.place_building(Buildings.Type.LONG_REACH_INSERTER, Vector2i(10, 10), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(12) long-reach inserter placement failed" }
	# Source 2 tiles west of inserter; dest 2 tiles east.
	world.place_building(Buildings.Type.CHEST, Vector2i(8, 10), Belt.DIR_E)
	world.place_building(Buildings.Type.CHEST, Vector2i(12, 10), Belt.DIR_E)
	var lr: Building = world.building_at(Vector2i(10, 10))
	src_chest = world.building_at(Vector2i(8, 10))
	dst_chest = world.building_at(Vector2i(12, 10))
	lr.state["fuel_buffer"] = 100
	src_chest.state["bag"] = [[Items.Type.WHEAT, 5]]
	# Cycle ticks lookup returns 30.
	_check(failures, Inserter.cycle_ticks(lr) == 30,
		"(12) long-reach cycle_ticks should be 30, got %d" % Inserter.cycle_ticks(lr))
	# Reach lookup returns 2.
	_check(failures, Inserter.reach(lr) == 2,
		"(12) long-reach reach should be 2, got %d" % Inserter.reach(lr))
	# Arm length returns 1.10.
	_check(failures, abs(Inserter.arm_length(lr) - 1.10) < 0.001,
		"(12) long-reach arm_length should be 1.10, got %f" % Inserter.arm_length(lr))
	# Body color returns the rust-red entry (not the default).
	var lr_color: Color = Inserter.body_color(lr)
	_check(failures, abs(lr_color.r - 0.65) < 0.01 and abs(lr_color.g - 0.30) < 0.01 and abs(lr_color.b - 0.22) < 0.01,
		"(12) long-reach body_color should be rust-red (0.65, 0.30, 0.22), got (%f, %f, %f)" % [lr_color.r, lr_color.g, lr_color.b])

	# ===========================================================================
	# (13) LONG-REACH 2-TILE REACH — source/dest tiles offset by 2 across all
	# 4 rotations. Validates that source_tile() / dest_tile() multiply by reach(b).
	# ===========================================================================
	for dir2 in [Belt.DIR_E, Belt.DIR_S, Belt.DIR_W, Belt.DIR_N]:
		lr.state["dir"] = dir2
		var v2: Vector2i = Belt.DIR_VECS[dir2]
		var expected_src: Vector2i = Vector2i(lr.anchor.x - v2.x * 2, lr.anchor.y - v2.y * 2)
		var expected_dst: Vector2i = Vector2i(lr.anchor.x + v2.x * 2, lr.anchor.y + v2.y * 2)
		_check(failures, Inserter.source_tile(lr) == expected_src,
			"(13) long-reach source_tile dir=%d should be %s, got %s" % [dir2, str(expected_src), str(Inserter.source_tile(lr))])
		_check(failures, Inserter.dest_tile(lr) == expected_dst,
			"(13) long-reach dest_tile dir=%d should be %s, got %s" % [dir2, str(expected_dst), str(Inserter.dest_tile(lr))])
```

Also update `test_name()` description to mention long-reach:
```gdscript
static func test_name() -> String:
	return "inserter (parametric refactor + filter pickup + drop-to-set + RMB-clear + save + fuel-port fix + refactor regression + long-reach tier)"
```

- [ ] **Step 2: Run tests to verify (12) and (13) fail**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: parse error on `Buildings.Type.LONG_REACH_INSERTER` (enum doesn't exist yet). Test suite reports failure on `test_inserter.gd`.

- [ ] **Step 3: Append LONG_REACH_INSERTER to enum in buildings.gd**

In `scripts/world/buildings.gd`, locate line 81 (current end of the Type enum block):
```gdscript
	FAST_INSERTER,
}
```

Insert the new enum entry before the closing brace:
```gdscript
	FAST_INSERTER,
	# Inserter Arc Session 3 (session-inserter-long-reach): LONG_REACH tier.
	# Same code path as basic + fast (Inserter.tick is parametric on b.type),
	# but reach is 2 tiles (REACH_BY_TYPE table) and cycle is 1.5s. No filter
	# — filter is a fast-axis capability, long-reach is the reach-axis upgrade.
	# Players choose long-reach to bridge a 1-tile gap without an extra building;
	# slower cycle balances the reach advantage. Color: rust-red (weathered
	# industrial). Future combinations (long-reach-fast, long-reach-electric)
	# extend the same data tables in later sessions.
	LONG_REACH_INSERTER,
}
```

- [ ] **Step 4: Append DATA entry in buildings.gd**

In `scripts/world/buildings.gd`, locate the end of the `Type.FAST_INSERTER` DATA block (around line 588 — the line `},` that closes FAST_INSERTER's entry):

After the closing `},` of FAST_INSERTER, insert:
```gdscript
	Type.LONG_REACH_INSERTER: {
		"name": "Long-Reach Inserter",
		"swatch_color": Color(0.65, 0.30, 0.22),    # rust-red: "reach" tier (Session 3)
		"footprint": Vector2i(1, 1),
		"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
		"supports_direction": true,                  # source/dest/fuel rotate together
		"player_drainable": false,
		# Walkable like the basic/fast inserter (thin device, arm swings overhead).
		"walkable": true,
		# Inserter UI (session-inserter-long-reach):
		# Same 2-slot layout as basic INSERTER — held_item (read-only display) +
		# fuel (Burner pattern, 16 units capacity). NO filter slot: filter is a
		# fast-tier capability, not the reach axis. Panel reuses InserterPanel
		# (NOT FastInserterPanel) via main.gd dispatch.
		"slot_layout": [
			{
				"id": "held_item", "kind": "output",
				"accepts": [],                       # informational; any item can be held
				"max_stack": 1, "state_field": "held_item_buffer",
			},
			{
				"id": "fuel", "kind": "fuel",
				"accepts": [Items.Type.WOOD, Items.Type.COAL, Items.Type.FUEL_BRIQUETTE],
				"max_stack": 16, "state_field": "fuel_buffer",
			},
		],
	},
```

- [ ] **Step 5: Append `make` dispatch case in buildings.gd**

In `scripts/world/buildings.gd`, locate the `make` function around line 791-794:
```gdscript
		Type.INSERTER:
			return Inserter.make(pos, dir, Type.INSERTER)
		Type.FAST_INSERTER:
			return Inserter.make(pos, dir, Type.FAST_INSERTER)
```

After the FAST_INSERTER case (before `push_error(...)`), add:
```gdscript
		Type.LONG_REACH_INSERTER:
			return Inserter.make(pos, dir, Type.LONG_REACH_INSERTER)
```

- [ ] **Step 6: Extend `tick_one` / `draw_one` / `info_lines` case labels**

In `scripts/world/buildings.gd`, locate line 825:
```gdscript
		Type.INSERTER, Type.FAST_INSERTER:
			# Custom tick — phase machine + parametric cycle speed via
			# Inserter.cycle_ticks(b) lookup. Same code path for both
			# basic (1.0s cycle) and fast (0.5s cycle, with filter slot)
			# tiers. Uses Burner module via try_pull_fuel restricted to
			# FUEL_PORT_DIR (S edge in canonical orientation) so source
			# items aren't consumed as fuel.
			Inserter.tick(b, world)
```

Replace the case label (one-line edit):
```gdscript
		Type.INSERTER, Type.FAST_INSERTER, Type.LONG_REACH_INSERTER:
			# Custom tick — phase machine + parametric cycle speed via
			# Inserter.cycle_ticks(b) lookup. Same code path across all
			# tiers: basic (1.0s cycle), fast (0.5s cycle, filter slot),
			# long-reach (1.5s cycle, 2-tile reach). Tier-specific values
			# resolved by *_BY_TYPE tables in inserter.gd. Uses Burner
			# module via try_pull_fuel restricted to FUEL_PORT_DIR (S edge
			# in canonical orientation) so source items aren't consumed
			# as fuel.
			Inserter.tick(b, world)
```

Similarly, locate line 886:
```gdscript
		Type.INSERTER, Type.FAST_INSERTER:
			Inserter.draw(b, canvas, world_pos, tile_size)
```

Replace:
```gdscript
		Type.INSERTER, Type.FAST_INSERTER, Type.LONG_REACH_INSERTER:
			Inserter.draw(b, canvas, world_pos, tile_size)
```

And locate line 1086:
```gdscript
			Type.INSERTER, Type.FAST_INSERTER:
				return Inserter.info_lines(b, world)
```

Replace:
```gdscript
			Type.INSERTER, Type.FAST_INSERTER, Type.LONG_REACH_INSERTER:
				return Inserter.info_lines(b, world)
```

- [ ] **Step 7: Append rows to parametric tables in inserter.gd**

In `scripts/world/inserter.gd`, locate the CYCLE_TICKS_BY_TYPE table (lines 55-58):
```gdscript
const CYCLE_TICKS_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:      20,    # 1.0s — basic
	Buildings.Type.FAST_INSERTER: 10,    # 0.5s — twice as fast
}
```

Append row:
```gdscript
const CYCLE_TICKS_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:            20,    # 1.0s — basic
	Buildings.Type.FAST_INSERTER:       10,    # 0.5s — twice as fast
	Buildings.Type.LONG_REACH_INSERTER: 30,    # 1.5s — slower, balances reach
}
```

Locate BODY_COLOR_BY_TYPE table (lines 65-68):
```gdscript
const BODY_COLOR_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:      Color(0.55, 0.45, 0.30),    # bronze
	Buildings.Type.FAST_INSERTER: Color(0.45, 0.55, 0.70),    # cool blue-grey
}
```

Append row:
```gdscript
const BODY_COLOR_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:            Color(0.55, 0.45, 0.30),    # bronze
	Buildings.Type.FAST_INSERTER:       Color(0.45, 0.55, 0.70),    # cool blue-grey
	Buildings.Type.LONG_REACH_INSERTER: Color(0.65, 0.30, 0.22),    # rust-red — "reach" tier
}
```

Locate REACH_BY_TYPE table (added in Task 2):
```gdscript
const REACH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:      1,
	Buildings.Type.FAST_INSERTER: 1,
}
```

Append row:
```gdscript
const REACH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:            1,
	Buildings.Type.FAST_INSERTER:       1,
	Buildings.Type.LONG_REACH_INSERTER: 2,
}
```

Locate ARM_LENGTH_BY_TYPE table (added in Task 2):
```gdscript
const ARM_LENGTH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:      0.55,
	Buildings.Type.FAST_INSERTER: 0.55,
}
```

Append row:
```gdscript
const ARM_LENGTH_BY_TYPE: Dictionary = {
	Buildings.Type.INSERTER:            0.55,
	Buildings.Type.FAST_INSERTER:       0.55,
	Buildings.Type.LONG_REACH_INSERTER: 1.10,    # 2x — visually communicates reach
}
```

- [ ] **Step 8: Run tests to verify (12) and (13) pass**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: `34 passed, 0 failed`. The "PASS inserter" line description includes "long-reach tier".

- [ ] **Step 9: Commit**

```bash
git add scripts/world/buildings.gd scripts/world/inserter.gd scripts/tests/test_inserter.gd
git commit -m "$(cat <<'EOF'
Task 3: Add LONG_REACH_INSERTER tier — enum + DATA + dispatch + table rows

Atomic append of the third inserter tier:

- Buildings.Type.LONG_REACH_INSERTER enum entry (post-FAST_INSERTER)
- DATA registration: 1x1 footprint, rust-red swatch (0.65, 0.30, 0.22),
  supports_direction, walkable, slot_layout matches basic (held_item +
  fuel, NO filter slot — filter is a fast-axis capability)
- make / tick_one / draw_one / info_lines dispatch cases extended
- Inserter.gd parametric table rows: CYCLE_TICKS=30, BODY_COLOR=rust-red,
  REACH=2, ARM_LENGTH=1.10

Test sub-cases (12) + (13) added: cycle timing/reach/color/arm_length
lookups for long-reach + 2-tile source/dest computation across all 4
rotations. 34/34 PASS.

NOT YET WIRED into hotbar or panel routing — Task 4.
EOF
)"
```

---

## Task 4: Hotbar + panel routing

**Files:**
- Modify: `scripts/ui/hotbar.gd:117` (Inserters category append)
- Modify: `scripts/main.gd:973` (panel dispatch append)

**Purpose:** Make the tier placeable from the hotbar and openable as a panel. No new test — wiring is covered by smoke (Task 7 PAUSE 1) plus implicit coverage from the cross-tile transport test in Task 5.

- [ ] **Step 1: Append hotbar slot**

In `scripts/ui/hotbar.gd`, locate the Inserters category (lines 110-120):
```gdscript
	categories.append({
		"name": "Inserters",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.INSERTER },
			# Inserter Arc Session 2 (session-inserter-fast-filter): fast tier.
			# Same building category; cycle is 0.5s and the panel adds a filter
			# slot for selective pickup (drop item to set, RMB to clear).
			{ "kind": "building", "value": Buildings.Type.FAST_INSERTER },
		],
		"selected": 0,
	})
```

Replace the slots array with the new 3-slot version:
```gdscript
	categories.append({
		"name": "Inserters",
		"slots": [
			{ "kind": "building", "value": Buildings.Type.INSERTER },
			# Inserter Arc Session 2 (session-inserter-fast-filter): fast tier.
			# Same building category; cycle is 0.5s and the panel adds a filter
			# slot for selective pickup (drop item to set, RMB to clear).
			{ "kind": "building", "value": Buildings.Type.FAST_INSERTER },
			# Inserter Arc Session 3 (session-inserter-long-reach): long-reach
			# tier. 2-tile reach (bridges 1-tile gap), 1.5s cycle, no filter.
			# Reuses basic InserterPanel via main.gd dispatch (no filter row).
			{ "kind": "building", "value": Buildings.Type.LONG_REACH_INSERTER },
		],
		"selected": 0,
	})
```

- [ ] **Step 2: Append panel dispatch case**

In `scripts/main.gd`, locate lines 970-973:
```gdscript
			Buildings.Type.INSERTER:
				inserter_panel.open(b, grid_world)
			Buildings.Type.FAST_INSERTER:
				fast_inserter_panel.open(b, grid_world)
```

After the FAST_INSERTER case, add:
```gdscript
			Buildings.Type.LONG_REACH_INSERTER:
				# Reuses basic InserterPanel — no filter row needed (filter is a
				# fast-axis capability, long-reach is the reach-axis upgrade).
				inserter_panel.open(b, grid_world)
```

- [ ] **Step 3: Run tests to confirm no regression**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: `34 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/hotbar.gd scripts/main.gd
git commit -m "$(cat <<'EOF'
Task 4: LONG_REACH_INSERTER hotbar + panel routing

- hotbar.gd: append LONG_REACH_INSERTER as 3rd slot in Inserters category
  (basic → fast → long-reach, left to right)
- main.gd: dispatch LONG_REACH_INSERTER → inserter_panel (basic panel, no
  filter row); FAST_INSERTER → fast_inserter_panel unchanged

Tier is now placeable from the hotbar and opens the correct panel.
34/34 PASS.
EOF
)"
```

---

## Task 5: Cross-tile transport integration test

**Files:**
- Modify: `scripts/tests/test_inserter.gd` (append sub-case 14)

**Purpose:** Full end-to-end integration test — chest → long_reach → belt with intermediate empty tiles. Validates the entire pipeline: placement, fuel, source pickup, swing-out, drop-to-belt, swing-in. Item count is the success signal.

- [ ] **Step 1: Write failing sub-case (14)**

Append after sub-case (13) in `scripts/tests/test_inserter.gd`:

```gdscript
	# ===========================================================================
	# (14) LONG-REACH CROSS-TILE TRANSPORT — full pipeline integration.
	# Layout: chest@(0,0) → long_reach@(2,0) (dir=E) → belt@(4,0), with empty
	# tiles at (1,0) and (3,0). Validates that the entire transport pipeline
	# works across a 2-tile gap (placement + fuel + pickup + swing + drop +
	# return). One full cycle = 30 ticks; expect 1 wheat in belt.slot facing
	# the inserter after 30 ticks.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	if not world.place_building(Buildings.Type.LONG_REACH_INSERTER, Vector2i(2, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(14) long-reach inserter placement at (2,0) failed" }
	if not world.place_building(Buildings.Type.CHEST, Vector2i(0, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(14) source chest placement at (0,0) failed" }
	if not world.place_building(Buildings.Type.BELT, Vector2i(4, 0), Belt.DIR_E):
		_disconnect(world); world.queue_free()
		return { "ok": false, "message": "(14) dest belt placement at (4,0) failed" }
	var lr2: Building = world.building_at(Vector2i(2, 0))
	var src2: Building = world.building_at(Vector2i(0, 0))
	var belt: Building = world.building_at(Vector2i(4, 0))
	# Confirm source_tile / dest_tile compute correctly with the 2-tile reach.
	_check(failures, Inserter.source_tile(lr2) == Vector2i(0, 0),
		"(14) source_tile should be (0,0), got %s" % str(Inserter.source_tile(lr2)))
	_check(failures, Inserter.dest_tile(lr2) == Vector2i(4, 0),
		"(14) dest_tile should be (4,0), got %s" % str(Inserter.dest_tile(lr2)))
	# Pre-fuel + load source.
	lr2.state["fuel_buffer"] = 100
	src2.state["bag"] = [[Items.Type.WHEAT, 5]]
	# Run 30 ticks — one full cycle.
	for _i in 30:
		TickSystem.current_tick += 1
		TickSystem.tick.emit(TickSystem.current_tick)
	# Belt should now contain exactly one wheat.
	var belt_slots: Array = belt.state.get("slots", [])
	var wheat_on_belt: int = 0
	for s in belt_slots:
		if int(s) == Items.Type.WHEAT:
			wheat_on_belt += 1
	_check(failures, wheat_on_belt == 1,
		"(14) belt should contain 1 wheat after 1 cycle, got %d" % wheat_on_belt)
	# Source chest should have 4 wheat remaining.
	var src2_count: int = _bag_count(src2.state.get("bag", []), Items.Type.WHEAT)
	_check(failures, src2_count == 4,
		"(14) source chest should have 4 wheat after 1 cycle, got %d" % src2_count)
```

Update `test_name()` description to mention cross-tile:
```gdscript
static func test_name() -> String:
	return "inserter (parametric refactor + filter pickup + drop-to-set + RMB-clear + save + fuel-port fix + refactor regression + long-reach tier + cross-tile)"
```

- [ ] **Step 2: Run tests — expect (14) to pass on first run**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: `34 passed, 0 failed`. (Task 3 already wired the full transport pipeline — this test is verification, not red→green for new code.)

If FAIL: regression in Task 2 / Task 3. Inspect failure message and fix before proceeding.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_inserter.gd
git commit -m "$(cat <<'EOF'
Task 5: Cross-tile transport integration test (sub-case 14)

Full pipeline test: chest@(0,0) → long_reach@(2,0) → belt@(4,0) with
empty (1,0) and (3,0). One full cycle (30 ticks) transports 1 wheat;
source chest decrements to 4; belt slot facing inserter holds 1 wheat.

Validates the entire long-reach transport contract end-to-end. Passes
on first run since Tasks 2+3 wired all required behavior; sub-case
serves as regression guard for future inserter refactors.

34/34 PASS.
EOF
)"
```

---

## Task 6: Save round-trip test

**Files:**
- Modify: `scripts/tests/test_inserter.gd` (append sub-case 15)

**Purpose:** Confirm long-reach building + state (held item, partial cycle_progress, partial fuel) survives a full save → reload cycle. Validates that the append-only enum + `.get()`-defaulted state fields work on the persistence path.

- [ ] **Step 1: Write failing sub-case (15)**

Append after sub-case (14):

```gdscript
	# ===========================================================================
	# (15) LONG-REACH SAVE ROUND-TRIP — state preservation across save/load.
	# Place a long-reach inserter with held item, partial cycle_progress, and
	# partial fuel buffer; save; load; verify all state preserved. Validates
	# append-only enum compatibility and .get()-defaulted state fields.
	# ===========================================================================
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	world.place_building(Buildings.Type.LONG_REACH_INSERTER, Vector2i(5, 5), Belt.DIR_S)
	var lr3: Building = world.building_at(Vector2i(5, 5))
	# Set state we want to preserve.
	lr3.state["fuel_buffer"] = 42
	lr3.state["current_fuel_item"] = Items.Type.COAL
	lr3.state["cycle_progress"] = 0.33
	lr3.state["state"] = Inserter.STATE_WORKING_OUT
	lr3.state["held_item_buffer"] = [[Items.Type.WHEAT, 1]]
	# Save.
	var save_path: String = "user://test_long_reach_save.json"
	var save_result: Dictionary = SaveSystem.save_game(world, save_path)
	_check(failures, bool(save_result.get("ok", false)),
		"(15) save_game should succeed, got error: %s" % str(save_result.get("error_message", "")))
	# Tear down and recreate.
	_disconnect(world); world.queue_free()
	world = _make_world(parent)
	# Load.
	var load_result: Dictionary = SaveSystem.load_game(world, save_path)
	_check(failures, bool(load_result.get("ok", false)),
		"(15) load_game should succeed, got error: %s" % str(load_result.get("error_message", "")))
	# Verify state preserved.
	var lr3_after: Building = world.building_at(Vector2i(5, 5))
	_check(failures, lr3_after != null and lr3_after.type == Buildings.Type.LONG_REACH_INSERTER,
		"(15) loaded building at (5,5) should be LONG_REACH_INSERTER, got %s" % (str(lr3_after.type) if lr3_after else "null"))
	if lr3_after != null:
		_check(failures, int(lr3_after.state.get("dir", -1)) == Belt.DIR_S,
			"(15) loaded dir should be DIR_S, got %d" % int(lr3_after.state.get("dir", -1)))
		_check(failures, int(lr3_after.state.get("fuel_buffer", 0)) == 42,
			"(15) loaded fuel_buffer should be 42, got %d" % int(lr3_after.state.get("fuel_buffer", 0)))
		_check(failures, int(lr3_after.state.get("current_fuel_item", -1)) == Items.Type.COAL,
			"(15) loaded current_fuel_item should be COAL, got %d" % int(lr3_after.state.get("current_fuel_item", -1)))
		_check(failures, abs(float(lr3_after.state.get("cycle_progress", 0.0)) - 0.33) < 0.001,
			"(15) loaded cycle_progress should be 0.33, got %f" % float(lr3_after.state.get("cycle_progress", 0.0)))
		_check(failures, int(lr3_after.state.get("state", -1)) == Inserter.STATE_WORKING_OUT,
			"(15) loaded state should be STATE_WORKING_OUT, got %d" % int(lr3_after.state.get("state", -1)))
		var held_buf: Array = lr3_after.state.get("held_item_buffer", [])
		_check(failures, held_buf.size() == 1 and int(held_buf[0][0]) == Items.Type.WHEAT,
			"(15) loaded held_item_buffer should be [[WHEAT,1]], got %s" % str(held_buf))
	# Cleanup the test save file.
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
```

Update `test_name()` description (final form):
```gdscript
static func test_name() -> String:
	return "inserter (parametric refactor + filter pickup + drop-to-set + RMB-clear + save + fuel-port fix + refactor regression + long-reach tier + cross-tile + long-reach save)"
```

- [ ] **Step 2: Run tests — expect (15) to pass on first run**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: `34 passed, 0 failed`. (Save schema unchanged at v18; append-only enum + uniform state shape means no migration needed.)

If FAIL: investigate save_system handling of unknown types or missing state fields. Per spec section 5, no migration should be needed.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_inserter.gd
git commit -m "$(cat <<'EOF'
Task 6: Save round-trip test (sub-case 15)

Place long-reach inserter with held item + partial cycle_progress +
partial fuel; save to user://test_long_reach_save.json; tear down +
reload; verify type, dir, fuel_buffer, current_fuel_item, cycle_progress,
state, and held_item_buffer all preserved.

Validates append-only enum compatibility (LONG_REACH_INSERTER added at
end of Buildings.Type, gets next int) and .get()-defaulted state fields
on the persistence path. Save schema unchanged at v18.

34/34 PASS — last code task before manual PAUSE checkpoints.
EOF
)"
```

---

## Task 7: PAUSE 1 (visual smoke) + PAUSE 2 (full gameplay)

**Files:** none (manual verification only)

**Purpose:** User-driven visual confirmation of behavior that headless tests can't validate — animation, color, hotbar entry, panel UX, in-game side-by-side comparison with basic/fast tiers.

**This task is NOT executed by a subagent.** Controller (Claude) opens the game and walks the user through both gates.

- [ ] **Step 1: PAUSE 1 — visual smoke**

Launch the game:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9"
```

User verifies:
1. Hotbar Inserters category shows 3 slots (basic + fast + long-reach in that order).
2. Long-reach swatch renders rust-red, distinct from bronze and blue-grey.
3. Place long-reach next to chest with 1-tile gap, then chest 2 tiles further. Item transports across the gap.
4. Cycle visually slower than basic (~1.5s per cycle vs 1.0s).
5. Arm extends ~2x further than basic. Animation swings smoothly through 30 ticks.
6. Right-click long-reach opens InserterPanel (NOT FastInserterPanel — no filter slot visible).
7. Fuel slot accepts wood/coal/briquette.

If any item fails: investigate, fix, re-run smoke. Do NOT proceed to PAUSE 2 until all pass.

- [ ] **Step 2: PAUSE 2 — full gameplay (3-tier coexistence)**

Build a small factory with all 3 inserter types operating in parallel:
- Basic inserter pulls wheat from chest to belt
- Fast inserter pulls wheat from another chest to another belt (faster)
- Long-reach pulls wheat from chest 2 tiles away to belt 2 tiles away on the other side

User verifies:
1. All 3 types fuel independently (each with its own fuel buffer).
2. All 3 types run their correct cycle speed (basic = 1.0s, fast = 0.5s, long-reach = 1.5s).
3. Save mid-operation → reload → all 3 still operate correctly.
4. No console errors / parse errors / runtime errors.

If any item fails: report to user, investigate, fix.

- [ ] **Step 3: PAUSE 2 GREEN signal**

Wait for user to explicitly confirm PAUSE 2 passes (e.g. "all good", "PAUSE 2 PASS"). Do NOT proceed to ship without explicit approval.

---

## Task 8: Ship — PROJECT_LOG + NOTES + tag + push

**Files:**
- Modify: `PROJECT_LOG.md` (prepend session entry)
- Modify: `NOTES.md` (add Design Brief Verification pattern + Inserter Arc 3 of 6 shipped marker)

**Purpose:** Final session housekeeping — log the session, document lessons learned, tag the commit, push.

- [ ] **Step 1: Prepend PROJECT_LOG entry**

Open `PROJECT_LOG.md`. Insert a new entry at the top (after the file header, before the previous most-recent entry):

```markdown
## 2026-05-15 — Inserter Arc Session 3 of 6 (Long-Reach Inserter)

Tag: `session-inserter-long-reach`
Spec: `docs/superpowers/specs/2026-05-15-inserter-long-reach-design.md`
Plan: `docs/superpowers/plans/2026-05-15-inserter-long-reach.md`
Save schema: v18 unchanged
Sub-cases added: 5 (test_inserter.gd internal sub-cases 11–15)
TESTS file count: 34 (unchanged)

### What shipped

- New `Buildings.Type.LONG_REACH_INSERTER` tier — 1×1, 2-tile reach, 1.5s cycle, fuel-powered, no filter, rust-red color.
- `Inserter` parametric tables extended: `CYCLE_TICKS_BY_TYPE`, `BODY_COLOR_BY_TYPE` (rows appended); `REACH_BY_TYPE` (new); `ARM_LENGTH_BY_TYPE` (refactored from `const ARM_LENGTH`).
- `source_tile()` / `dest_tile()` multiply offset vector by `reach(b)`. Tick logic unchanged (already tier-agnostic).
- Hotbar Inserters category: 3rd slot added (basic → fast → long-reach).
- Panel routing: long-reach → `InserterPanel` (basic, no filter row).
- 5 new test sub-cases in `test_inserter.gd`: regression (11), cycle timing (12), 2-tile reach (13), cross-tile transport (14), save round-trip (15).

### Decisions

- Q1 — Body color: rust-red `Color(0.65, 0.30, 0.22)`. Maximally distinct from existing bronze (basic) and blue-grey (fast); avoids olive-green which would clash with `FERTILIZER_APPLICATOR`'s sage.
- Q2 — Parametric extension shape: `REACH_BY_TYPE` new; `ARM_LENGTH` const → `ARM_LENGTH_BY_TYPE` table. Baseline 0.55 preserved for basic/fast (pure additive change, no visual delta on existing tiers).
- Q3 — State shape: universal — `filter_item_type: -1` exists on long-reach but is unused. Cost of uniform persistence shape.
- Q4 — **Assumption correction**: spec brief said "modify tick"; code search revealed `tick()` is already accessor-driven (calls `source_tile()` / `dest_tile()` via `_try_pickup` / `_try_drop`). REACH lookup belongs at the accessor level. Tick is unchanged.
- Q5 — Arm-angle math is length-independent (`canonical_angle` is purely state + `cycle_progress`); verified at draw site (lines 491-511).
- Q6 — Long-reach reuses `InserterPanel`, not `FastInserterPanel` — no filter capability.
- Q7 — Hotbar position: 3rd slot in Inserters category.
- Q8 — 5 sub-cases inside `test_inserter.gd`: regression / cycle / reach / cross-tile / save round-trip.
- ARM_LENGTH baseline: 0.55 retained (rejected the 0.6 in the original spec brief to keep regression surface zero).

### Lessons

- **Design Brief Verification (new working protocol):** Senior dev briefs describe code changes at conceptual level; implementation must verify against actual current code shape via code search + line citations before accepting brief assumptions. Two instances across the arc: Cluster A Task 14 (refuse-clamp semantic conflation), Inserter Session 3 (Q4 "modify tick" vs accessor-level change). Pattern: brief assumptions about code structure are approximate; verification is cheap and catches imprecision before it propagates.
- **Parametric pattern scales cleanly:** Adding a new orthogonal upgrade axis (reach) was a 5-line change to the parametric refactor — one new `REACH_BY_TYPE` table + accessor. Validates the design choice from Session 2.
- **Append-only enum + `.get()` defaults** continue to keep save schema flat. No migration needed for the 3rd tier in this family.
- **Test count terminology**: "sub-suites" in the user's brief sometimes means "internal sub-cases" (this session's pattern) and sometimes means "test files" (Cluster A). Treat as ambiguous in future briefs; disambiguate before implementation.

```

- [ ] **Step 2: Update NOTES.md — add Design Brief Verification pattern**

Open `NOTES.md`. Find an appropriate section for working protocols (look for "Working protocol:" lines or similar pinned patterns) and add the following pin:

```markdown
**Working protocol: Design Brief Verification (validated session-inserter-long-reach):**
Senior dev briefs describe code changes at conceptual level. Implementation
agent should ALWAYS verify against actual current code shape via code search
+ line citations before accepting brief assumptions. Two instances this arc:
- Cluster A Task 14: refuse-clamp semantic conflation caught by spec read
- Inserter Session 3 Q4: "modify tick" should have been "modify source_tile/
  dest_tile accessors" — caught by code search

Pattern: brief assumptions about code structure are approximate; verification
against current code is cheap and catches imprecision before it propagates.
Apply to all future sessions where a brief describes "modify X" — first locate
X in current code, then confirm the brief's description matches the actual shape.
```

Also locate the "Inserter Arc" tracking section (if present) and add a "Session 3 SHIPPED" marker, or create the tracking section if not yet present:

```markdown
## Inserter Arc progress

- Session 1 (foundation) — SHIPPED — `session-inserter-foundation` — basic 1-tile inserter
- Session 2 (fast + filter) — SHIPPED — `session-inserter-fast-filter` — 0.5s cycle + filter slot + parametric refactor
- Session 3 (long-reach) — SHIPPED — `session-inserter-long-reach` — 2-tile reach + 1.5s cycle (third tier on parametric foundation)
- Session 4 (electricity foundation) — PENDING — separate arc, prerequisite for Session 5
- Session 5 (electric inserters) — PENDING — very fast + multi-filter, requires power
- Session 6 (long-reach variants) — PENDING — long-reach-fast, long-reach-electric combinations
```

- [ ] **Step 3: Run final test suite to confirm 34/34**

Run:
```bash
"C:/Users/elham/Godot/Godot_v4.6.2-stable_win64.exe" --headless --path "C:/Users/elham/facvtorio/.claude/worktrees/silly-bardeen-3279e9" "res://scenes/test_runner.tscn" 2>&1 | tail -50
```
Expected: `34 passed, 0 failed`. The "PASS inserter" line includes all 15 sub-cases.

- [ ] **Step 4: Commit ship entry**

```bash
git add PROJECT_LOG.md NOTES.md
git commit -m "$(cat <<'EOF'
Ship session-inserter-long-reach: PROJECT_LOG entry + NOTES updates

PROJECT_LOG: full session entry — what shipped (5 code changes, 5 test
sub-cases), Q1–Q8 decisions (including Q4 assumption correction +
ARM_LENGTH baseline retention), lessons (Design Brief Verification
protocol, parametric pattern scaling, save schema stability).

NOTES: Design Brief Verification protocol pin (validated across Cluster A
Task 14 + Inserter Session 3 Q4). Inserter Arc progress tracking section
— Session 3 SHIPPED, Sessions 4–6 PENDING.

Final test count: 34/34 sub-suites PASS, test_inserter.gd grew to 15
internal sub-cases.
EOF
)"
```

- [ ] **Step 5: Tag commit**

```bash
git tag session-inserter-long-reach
git log --oneline -1
git tag --list | grep inserter
```

Expected:
- `git log` shows the ship commit
- `git tag --list` shows 3 inserter tags: `session-inserter-foundation`, `session-inserter-fast-filter`, `session-inserter-long-reach`

- [ ] **Step 6: Push branch + tag**

```bash
git push origin claude/silly-bardeen-3279e9
git push origin session-inserter-long-reach
```

Expected:
- Branch push succeeds (already tracking `origin/claude/silly-bardeen-3279e9`)
- Tag push succeeds: `* [new tag] session-inserter-long-reach -> session-inserter-long-reach`

- [ ] **Step 7: Verify on origin**

```bash
git ls-remote origin refs/heads/claude/silly-bardeen-3279e9 refs/tags/session-inserter-long-reach
```

Expected: both refs point to the same ship commit SHA.

- [ ] **Step 8: Report to user**

Report: ship commit SHA, tag pushed, test count, total commits this session, total tag count.

---

## Self-review (writing-plans skill, completed at plan-write time)

**Spec coverage:**
- Spec section 4.Q1 (rust-red color) → Task 3 step 4 (DATA entry swatch_color)
- Spec section 4.Q2 (parametric tables) → Task 2 step 3 (ARM_LENGTH + REACH) + Task 3 step 7 (rows for long-reach)
- Spec section 4.Q3 (uniform state shape) → covered by Task 3 step 5 (`make` calls `Inserter.make(pos, dir, Type.LONG_REACH_INSERTER)` — uniform state shape inherited)
- Spec section 4.Q4 (tick unchanged, REACH at accessor level) → Task 2 step 4 (source_tile/dest_tile only)
- Spec section 4.Q5 (arm-angle math length-independent) → Task 2 step 5 (draw uses arm_length accessor)
- Spec section 4.Q6 (InserterPanel reuse) → Task 4 step 2 (main.gd dispatch)
- Spec section 4.Q7 (hotbar 3rd slot) → Task 4 step 1
- Spec section 4.Q8 (5 sub-cases) → Tasks 2 (11), 3 (12)(13), 5 (14), 6 (15)
- Spec section 5 (no schema bump) → Task 6 (save round-trip validates this)
- Spec section 6 (touchpoint inventory 15 entries) → all 15 entries mapped to specific task steps
- Spec section 7 (implementation order) → reflected in Task 1–8 sequence
- Spec section 8 (validation criteria 8 items) → covered by Task 7 PAUSE 1 + Task 6 (save) + Task 5 (cross-tile)

**Placeholder scan:** No TBD / TODO / "implement later" / "similar to Task N" patterns. Each task contains complete code.

**Type consistency:**
- `Inserter.cycle_ticks(b)`, `Inserter.body_color(b)`, `Inserter.reach(b)`, `Inserter.arm_length(b)` — used consistently across all tasks.
- `Inserter.source_tile(b)`, `Inserter.dest_tile(b)` — used consistently.
- `Buildings.Type.LONG_REACH_INSERTER` — used consistently (not `LongReachInserter` or other variants).
- `REACH_BY_TYPE` / `ARM_LENGTH_BY_TYPE` / `CYCLE_TICKS_BY_TYPE` / `BODY_COLOR_BY_TYPE` — all share the `*_BY_TYPE` naming pattern.

No issues found. Plan ready for execution.
