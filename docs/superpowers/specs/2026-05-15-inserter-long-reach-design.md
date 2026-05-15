# Long-Reach Inserter — Inserter Arc Session 3 of 6

**Session tag (planned):** `session-inserter-long-reach`
**Date:** 2026-05-15
**Save schema impact:** none (v18, append-only enum + state fields via `.get()`)
**Test count target:** 34 → 39 (+5 sub-suites, appended to `test_inserter.gd`)
**Methodology:** Superpowers brainstorming → writing-plans → subagent-driven TDD → verification-before-completion, wrapped by CLAUDE.md project protocols (design pass / PAUSE checkpoints / PROJECT_LOG / tagged commit). Last session validated this layering across 27 tasks with zero false positives from line-quoting code review.

---

## 1. Context

Inserter Arc maps a three-axis space for active item-routing devices:

| Axis | Variant | Status |
|---|---|---|
| Baseline | `INSERTER` — 1-tile reach, 1.0s cycle, no filter | Shipped (session-inserter-foundation) |
| Speed + Filter | `FAST_INSERTER` — 1-tile reach, 0.5s cycle, single-slot filter | Shipped (session-inserter-fast-filter) |
| **Reach** | **`LONG_REACH_INSERTER` — 2-tile reach, 1.5s cycle, no filter** | **This session** |

The two-axis split is intentional: "speed + filter" and "reach" are orthogonal upgrades. Players choose long-reach when factory layout has a 1-tile gap to bridge without extra building; they choose fast when throughput matters. Future sessions combine them (Session 6: long-reach-fast, long-reach-electric).

The architectural prerequisite — parametric refactor of `Inserter` across `*_BY_TYPE` tables — was completed in Session 2. Session 3 is the third tier on the same refactor, validating that the parametric shape generalizes cleanly to a different upgrade axis.

## 2. Scope (locked — do not extend)

**In:**

- New `Buildings.Type.LONG_REACH_INSERTER` enum entry + DATA registration.
- Extend `CYCLE_TICKS_BY_TYPE` and `BODY_COLOR_BY_TYPE`.
- Add new `REACH_BY_TYPE` table + `reach(b)` accessor.
- Refactor `ARM_LENGTH` const → `ARM_LENGTH_BY_TYPE` table + `arm_length(b)` accessor (counted as parametric refactor for the third tier).
- Modify `source_tile()` / `dest_tile()` to multiply offset vector by `reach(b)`. Tick stays unchanged.
- Reuse `InserterPanel` (no filter row).
- Append to Inserters hotbar category.
- 5 new sub-suites appended to `test_inserter.gd`.

**Out (deferred to future sessions):**

- Electricity foundation (Session 4 — separate arc).
- Electric inserters (Session 5).
- Long-reach + fast / long-reach + electric variants (Session 6).
- Any filter capability on long-reach (filter belongs to the speed axis, not the reach axis).
- Visual change to existing INSERTER / FAST_INSERTER arm lengths (preserves 0.55 baseline).
- Any change to fuel economics or recipe semantics.

## 3. Methodology layering

The wrapper stays as CLAUDE.md prescribes; Superpowers slots into the design + inner loop:

| Project protocol | Superpowers layer |
|---|---|
| Design pass + PAUSE checkpoints | brainstorming + this spec |
| Per-task implementation | writing-plans → subagent triad (implementer + spec reviewer + code quality reviewer) |
| TDD discipline | enforced via Test Layering Strategy + subagent prompts |
| PROJECT_LOG + NOTES update | end of session |
| Tagged commit + push | terminal step |

Validated last session: line-quoting protocol on code reviewers (0 FP across 17 reviews), DONE_PENDING_VERIFICATION protocol for slow-test stalls, strengthened scope-deviation protocol.

## 4. Design decisions (Q1–Q8 locked)

### Q1 — Body color: rust-red `Color(0.65, 0.30, 0.22)`

Maximally distinct from bronze (basic, `Color(0.55, 0.45, 0.30)`) and cool blue-grey (fast, `Color(0.45, 0.55, 0.70)`). Rust-red sits opposite blue-grey on the color wheel and shares warm-tone family with bronze without colliding. Reads as "weathered industrial reach" — fits the slow-but-far axis. Avoids olive-green which would conflict with `FERTILIZER_APPLICATOR`'s sage `Color(0.55, 0.70, 0.55)`.

### Q2 — Parametric extension shape

Add rows to `inserter.gd`:

```gdscript
const CYCLE_TICKS_BY_TYPE: Dictionary = {
    Buildings.Type.INSERTER:            20,    # 1.0s
    Buildings.Type.FAST_INSERTER:       10,    # 0.5s
    Buildings.Type.LONG_REACH_INSERTER: 30,    # 1.5s — slower to balance reach
}

const BODY_COLOR_BY_TYPE: Dictionary = {
    Buildings.Type.INSERTER:            Color(0.55, 0.45, 0.30),
    Buildings.Type.FAST_INSERTER:       Color(0.45, 0.55, 0.70),
    Buildings.Type.LONG_REACH_INSERTER: Color(0.65, 0.30, 0.22),    # rust-red
}

# NEW table — reach in tiles. Default fallback = 1 (basic-equivalent).
const REACH_BY_TYPE: Dictionary = {
    Buildings.Type.INSERTER:            1,
    Buildings.Type.FAST_INSERTER:       1,
    Buildings.Type.LONG_REACH_INSERTER: 2,
}
const REACH_DEFAULT: int = 1

# REFACTORED from `const ARM_LENGTH: float = 0.55` (line 72 of current code).
# Baseline 0.55 preserved for INSERTER / FAST_INSERTER — pure additive change.
# Long-reach: 2.00 — physically reaches the 2-tile-away source/dest (Q5
# revision during Task 4 smoke gate: original 1.10 stylized choice was
# confusing; players couldn't tell long-reach apart from basic visually).
const ARM_LENGTH_BY_TYPE: Dictionary = {
    Buildings.Type.INSERTER:            0.55,
    Buildings.Type.FAST_INSERTER:       0.55,
    Buildings.Type.LONG_REACH_INSERTER: 2.00,    # physically reaches 2-tile-away source/dest
}
const ARM_LENGTH_DEFAULT: float = 0.55

static func reach(b: Building) -> int:
    return int(REACH_BY_TYPE.get(b.type, REACH_DEFAULT))

static func arm_length(b: Building) -> float:
    return float(ARM_LENGTH_BY_TYPE.get(b.type, ARM_LENGTH_DEFAULT))
```

The 1.10-tile arm visually extends ~1 tile past the inserter's center (tip enters but doesn't fully span the 2-tile gap) — stylized, not physical. Matches Factorio-style swing aesthetics.

### Q3 — State shape: identical, `filter_item_type: -1` universal

`Inserter.make()` already unconditionally sets `filter_item_type: -1` regardless of `b_type` (line 114 in current code). Long-reach inherits without touching `make()` — pass `Buildings.Type.LONG_REACH_INSERTER` as the `b_type` arg, state shape is identical. The unused filter field is the cost of universal state shape; the alternative (per-tier state branching in `make`) breaks the parametric pattern and complicates save/load. Reaffirmed from Session 2 Q3.

### Q4 — Tick logic: zero changes (assumption corrected)

User's session prompt assumed REACH lookup goes into tick; **verification against `inserter.gd:134-190` shows tick is already accessor-driven** (it calls `_try_pickup` / `_try_drop`, which themselves call `source_tile()` / `dest_tile()`). The REACH lookup goes into the **accessors**, not tick:

```gdscript
# BEFORE (inserter.gd:195-204):
static func source_tile(b: Building) -> Vector2i:
    var d: int = int(b.state.get("dir", 0))
    var v: Vector2i = Belt.DIR_VECS[d]
    return Vector2i(b.anchor.x - v.x, b.anchor.y - v.y)

# AFTER:
static func source_tile(b: Building) -> Vector2i:
    var d: int = int(b.state.get("dir", 0))
    var v: Vector2i = Belt.DIR_VECS[d]
    var r: int = reach(b)
    return Vector2i(b.anchor.x - v.x * r, b.anchor.y - v.y * r)
```

Symmetric change for `dest_tile()`. This automatically propagates to:

- `_try_pickup` / `_try_drop` (call source/dest)
- `info_lines` source/destination display (line 441-442)
- Any external caller in `buildings.gd` / panels

Tick stays tier-agnostic. **This is the cleanest possible change for a reach-axis upgrade** — validates the parametric refactor's design.

### Q5 — Animation: arm-angle math is length-independent

Verified `inserter.gd:484-511`:
- `canonical_angle` is a pure function of state + `cycle_progress` (lines 491-501).
- Arm length only appears as the radius multiplier at line 506 (`arm_len = float(tile_size) * ARM_LENGTH`).
- Swap `ARM_LENGTH` → `arm_length(b)`; math is unchanged.

The arm tip is drawn at `center + arm_dir * arm_len`. With `arm_len = tile_size * 1.10`, the tip extends ~1 tile past the inserter center along the swing arc. The held item dot rides at the tip — visually communicates the reach even though it doesn't physically span the 2-tile gap. Same compromise as Factorio.

### Q6 — Panel reuse: InserterPanel (no filter row)

Long-reach has no filter capability, so it dispatches to `InserterPanel` (basic), NOT `FastInserterPanel`. `main.gd:970-973` already does per-type dispatch — append one case. Confirmed `inserter.gd:430` surfaces the filter info line ONLY for `FAST_INSERTER`, so long-reach correctly won't show that line via the shared `info_lines` function.

### Q7 — Hotbar: append as 3rd slot in Inserters category

`hotbar.gd:110-120` Inserters category currently has 2 slots (basic + fast). Append `{ "kind": "building", "value": Buildings.Type.LONG_REACH_INSERTER }` as the 3rd. Order: basic → fast → long-reach (left to right).

### Q8 — Test sub-suites (5)

Appended to `test_inserter.gd`:

1. **Long-reach cycle timing** — 30 ticks per cycle (15 swing-out + 15 swing-in). Tick a long-reach inserter with fueled chest → empty belt and verify item arrives at tick 15 (drop fires when `cycle_progress` first reaches `0.5`; with `inc = 1/30`, that's the 15th tick).
2. **2-tile reach** — `source_tile()` returns `anchor - 2*DIR_VECS[dir]` and `dest_tile()` returns `anchor + 2*DIR_VECS[dir]` across all 4 rotations (DIR_E, DIR_S, DIR_W, DIR_N).
3. **Cross-tile transport** — full integration test: chest@(0,0) → long_reach@(2,0) (dir=E) → belt@(4,0), with empty (1,0) and (3,0); fuel the inserter, tick 30 times (one full cycle), verify one item delivered into belt.
4. **Save round-trip** — place a long-reach inserter with held item, partial cycle_progress, and partial fuel buffer; save and reload via `save_system`; verify all state preserved. Validates `.get()`-defaulted state fields and append-only enum compatibility.
5. **Parametric refactor regression** — basic INSERTER cycle remains 20 ticks AND source/dest remain 1-tile reach; FAST_INSERTER cycle remains 10 ticks AND source/dest remain 1-tile reach. Guards specifically against the `ARM_LENGTH` const → `ARM_LENGTH_BY_TYPE` refactor and the new `REACH_BY_TYPE` accessor.

## 5. Save schema: no bump

Append-only enum (LONG_REACH_INSERTER added at end of `Buildings.Type` enum, gets next int). No new state fields — long-reach inherits the universal inserter state shape, including the pre-existing `filter_item_type: -1` field (unused for this tier but uniform across the family). Old saves: never contain long-reach buildings, so no migration. Loading a Session 3 save in Session 2 build: would fail with "unknown building type" at the enum level, same precedent as Session 2 saves on Session 1 build. Same precedent as every prior append-only tier addition.

Save schema stays at v18.

## 6. Touchpoint inventory

15 files / sections, 1 new table, 1 const → table refactor, zero tick changes.

| File | Line (approx) | Change |
|---|---|---|
| `scripts/world/buildings.gd` | 81 | append `LONG_REACH_INSERTER` to enum |
| `scripts/world/buildings.gd` | ~589 | append DATA entry (rust-red, 1×1, supports_direction, slot_layout same as INSERTER — 2 slots: held_item + fuel) |
| `scripts/world/buildings.gd` | 794 | append `make` dispatch case |
| `scripts/world/buildings.gd` | 825 | extend `tick_one` case label |
| `scripts/world/buildings.gd` | 886 | extend `draw_one` case label |
| `scripts/world/buildings.gd` | 1086 | extend `info_lines` case label |
| `scripts/world/inserter.gd` | 55 | extend `CYCLE_TICKS_BY_TYPE` |
| `scripts/world/inserter.gd` | 65 | extend `BODY_COLOR_BY_TYPE` |
| `scripts/world/inserter.gd` | 72 | refactor `ARM_LENGTH` const → `ARM_LENGTH_BY_TYPE` dict + `arm_length(b)` accessor |
| `scripts/world/inserter.gd` | ~73 | NEW `REACH_BY_TYPE` dict + `reach(b)` accessor |
| `scripts/world/inserter.gd` | 195–204 | `source_tile` / `dest_tile` multiply offset by `reach(b)` |
| `scripts/world/inserter.gd` | 506 | `arm_len` uses `arm_length(b)` |
| `scripts/main.gd` | 973 | append panel dispatch case (long-reach → `inserter_panel`) |
| `scripts/ui/hotbar.gd` | 117 | append hotbar slot |
| `scripts/tests/test_inserter.gd` | end of file | append 5 sub-suites |

## 7. Implementation order (high-level — detailed task breakdown in plan)

1. Test threshold audit (assert 34/34 PASS before any change)
2. Append `LONG_REACH_INSERTER` enum + DATA + dispatch cases (buildings.gd)
3. Extend / refactor parametric tables in `inserter.gd` (CYCLE_TICKS_BY_TYPE, BODY_COLOR_BY_TYPE, ARM_LENGTH const→table, new REACH_BY_TYPE)
4. Modify `source_tile()` / `dest_tile()` to use `reach(b)`; modify `draw()` to use `arm_length(b)`
5. Regression check: run full test suite, confirm 34/34 still PASS (parametric refactor must not break basic + fast)
6. Hotbar append (Inserters category 3rd slot)
7. Main.gd panel dispatch append
8. **PAUSE 1: visual smoke** — place long-reach in dev console, verify 2-tile reach + slower cycle + rust-red color + extended arm
9. Append 5 sub-suites to test_inserter.gd, verify 39/39 PASS
10. **PAUSE 2: full gameplay** — build factory with all 3 inserter types side by side; confirm they coexist, fuel independently, transport correctly
11. PROJECT_LOG entry + NOTES update (Inserter Arc 3 of 6 shipped)
12. Commit + tag `session-inserter-long-reach` + push

## 8. Validation criteria at commit

- [ ] `LONG_REACH_INSERTER` places via hotbar, accepts fuel (wood / coal / briquette)
- [ ] 2-tile reach: `source_tile()` returns `anchor - 2*DIR_VECS[dir]`, `dest_tile()` returns `anchor + 2*DIR_VECS[dir]` for all 4 rotations
- [ ] Cycle visibly slower than basic (1.5s vs 1.0s) — observable by side-by-side play
- [ ] Item transports across 2-tile gap (chest → long_reach → belt with empty intermediate tiles)
- [ ] Arm visible at ~2x length, animation swings full half-cycle in 15 ticks
- [ ] Basic + fast inserters still work (visual + cycle + reach regression — guarded by test 5)
- [ ] 34 → 39 sub-suites passing
- [ ] Save schema unchanged at v18
- [ ] Tagged `session-inserter-long-reach`, pushed to origin

## 9. Out-of-scope reminders (anti-scope-creep)

- **No filter on long-reach** — filter is a fast-axis capability. Players who want both buy a long-reach-fast variant in Session 6.
- **No fuel economy changes** — burning coal vs wood affects fuel ECONOMY (how often refill) per Reversal #7 from Session 1, not throughput. Long-reach uses same burner contract.
- **No 3-tile reach variant** — REACH_BY_TYPE supports arbitrary int, but additional reach tiers are deferred.
- **No animation polish beyond arm extension** — no easing curves, no anticipation frames; the existing linear interpolation is reused as-is.
- **No new slot_layout shape** — long-reach reuses INSERTER's 2-slot layout (held_item + fuel). No filter slot.

## 10. Decision log (for PROJECT_LOG entry at session end)

- Q1: rust-red `Color(0.65, 0.30, 0.22)` — maximal distinction from existing tiers + warm-tone family with bronze
- Q2: REACH_BY_TYPE new; ARM_LENGTH refactored const → table; CYCLE_TICKS / BODY_COLOR extended
- Q3: universal state shape — `filter_item_type: -1` exists on long-reach but is unused
- Q4: **assumption corrected** — REACH applies at accessor level (source_tile / dest_tile), not in tick; tick stays tier-agnostic
- Q5: arm-angle math is length-independent, verified at draw site
- Q6: long-reach reuses `InserterPanel` (no filter row)
- Q7: hotbar append as 3rd slot in Inserters category
- Q8: 5 sub-suites: cycle timing, 2-tile reach, cross-tile transport, save round-trip, parametric refactor regression
- ARM_LENGTH baseline: 0.55 preserved (not 0.6) for basic/fast — pure additive change, smaller regression surface
