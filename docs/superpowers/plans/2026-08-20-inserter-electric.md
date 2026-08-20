# Implementation Plan — Inserter Arc Session 4: Electric Inserter

**Spec:** `docs/superpowers/specs/2026-08-20-inserter-electric-design.md`
**Baseline:** `a38b4d7`, 39/39 green, tree clean
**Approved:** demand 5 · fuel-tier held-item fix in-session · `STATE_NO_POWER` at epsilon 0.05 · constant demand

11 tasks. Every code task is RED-before-fix: write the failing test, run it, confirm it
fails for the *expected reason*, then implement. Run `--headless --import` after any task
that adds a file. Filter test output on **both** `passed,` and `Parse Error` — a compile
error kills the runner before it prints a summary and reads exactly like a hang.

---

## State-branch site inventory (verified `a38b4d7`)

`STATE_NO_POWER` must be handled at **6 sites**. Falling through to a default renders it
indistinguishable from IDLE:

| # | Site | Function | Consequence if missed |
|---|---|---|---|
| 1 | `inserter.gd:181` | `tick()` | — (this is the NO_FUEL *write*; electric needs its own) |
| 2 | `inserter.gd:191` | `tick()` | resume/pickup arm — the h1 bug site |
| 3 | `inserter.gd:509` | `info_lines()` | Q-inspect says "Idle" for an unpowered machine |
| 4 | `inserter.gd:563,565` | `draw()` tint | looks identical to idle |
| 5 | `inserter.gd:588` | `draw()` arm angle | arm freezes mid-swing instead of parking |
| 6 | `inserter_panel.gd:98-110,121` | `_draw_building_specific` | panel status + bar colour |

`FastInserterPanel` does not override the status match (it calls `super` at
`fast_inserter_panel.gd:69`), so site 6 covers fast and electric together.

---

## Task 1 — RED: fuel-tier held-item destruction (all three tiers)

**Sequenced first by user decision:** electric must inherit correct behavior from a fixed
shared path, not implement it correctly beside three broken siblings.

New file `scripts/tests/test_inserter_fuel_conservation.gd`, registered in `test_runner.gd`.
Then `--headless --import`.

For each of `INSERTER`, `FAST_INSERTER`, `LONG_REACH_INSERTER`:
- Source chest with N items, dest chest, **no** fuel source at the S port.
- Fuel the inserter, tick until it is verifiably mid-swing holding an item
  (`state == STATE_WORKING_OUT` and `held_item_type(b) >= 0`), then zero `fuel_buffer`.
- Assert it enters `STATE_NO_FUEL` **still holding** the item.
- Refuel; run to completion; assert **total conservation**: `source + dest + held == N`.

Reach the mid-swing state by ticking to it, not by computing an exact tick count —
`cycle_progress` accumulates `1.0/ticks` floats and exact-tick scheduling is fragile.

**Expected RED:** conservation fails (`N-1`), because `:191`'s arm calls `_try_pickup` then
`_set_held`, overwriting the held item.

## Task 2 — GREEN: resume-delivery guard

In `inserter.gd:191`, before attempting pickup: if `held_item_type(b) >= 0`, clamp
`cycle_progress` into `[0.0, 0.5]`, set `STATE_WORKING_OUT`, and return. At 0.5 the next
tick re-attempts the drop and re-enters `BLOCKED_AT_DEST` if still blocked.

Closes audit **#2/#6**. Task 1 goes green; all 39 existing suites must stay green.

## Task 3 — ELECTRIC_INSERTER registration (no behavior yet)

- `buildings.gd`: append `ELECTRIC_INSERTER` to the enum (append-only contract), DATA
  entry — 1×1, `supports_direction: true`, `walkable: true`, cyan
  `Color(0.25, 0.75, 0.80)`, `requires_overlay` matching the other inserter tiers.
- **Slot layout: `held_item` + `filter` only — NO `fuel` slot.**
- `make()` case → `Inserter.make(pos, dir, Type.ELECTRIC_INSERTER)`.
- Extend the three shared dispatch cases to the comma pattern (`tick_one`, `draw_one`,
  `info_lines_for`).
- `--headless --import`.

## Task 4 — RED→GREEN: parametric table rows

RED: sub-cases 1-2 — registry (1×1, walkable, cycle 5, reach 1) and full-power transport
(one item per 5-tick cycle at satisfaction 1.0).

GREEN: one row each in `CYCLE_TICKS_BY_TYPE` (5), `BODY_COLOR_BY_TYPE` (cyan),
`REACH_BY_TYPE` (1), `ARM_LENGTH_BY_TYPE` (0.55). No new module.

## Task 5 — RED→GREEN: fuel-branch gating + constant demand

RED: sub-case 8 (no fuel slot in DATA; `Burner.consume_tick` never runs for the electric
tier) and sub-case 10 (component demand includes `DEMAND` whether the inserter is idle or
mid-swing — locks the constant-demand decision).

GREEN:
- `inserter.gd`: gate the fuel pull at `:178-182` and the three `Burner.consume_tick`
  calls (`:198, :214, :~230`) behind a tier predicate — suggest `is_electric(b)` reading a
  small `POWERED_BY_TYPE` table so future electric tiers are a row, not a branch.
- `power_network.gd` Stage 1: add an `ELECTRIC_INSERTER` arm using
  `_supply_component_id` (consumer rule), adding `ElectricInserter.DEMAND = 5`
  **unconditionally** — mirrors the `ELECTRIC_LAMP` arm at `:186-190`.

Constant demand is the whole point of the arm being unconditional; do not gate it on
activity.

## Task 6 — RED→GREEN: brownout slowdown

RED: sub-case 3 (at satisfaction 0.5 a swing takes 10 ticks, not 5) and sub-case 4 (the
novel one — `cycle_progress` strictly increases *every* tick at sat 0.5; no tick where it
fails to advance). Sub-case 4 is what proves smooth interpolation rather than a stall.

GREEN: at `inserter.gd:188`, substitute an effective tick count:

```gdscript
var ticks: int = effective_cycle_ticks(b, world)
var inc: float = 1.0 / float(ticks)
```

with `effective_cycle_ticks` = `cycle_ticks(b)` for fuel tiers, and for electric
`int(ceil(BASE / max(EPSILON, sat)))` where `sat = world.power_satisfaction_at(b.anchor)`.
Because `inc` feeds all four state arms, the arm interpolation stretches across the longer
cycle automatically — no new interpolation code.

## Task 7 — RED→GREEN: STATE_NO_POWER at all 6 sites

RED: sub-case 5 (below epsilon: state is `NO_POWER`, held item intact across many ticks,
nothing delivered) and sub-case 6 (power restored mid-swing → resumes, item conserved —
the electric analogue of Task 1).

GREEN: add `const STATE_NO_POWER: int = 5` and handle all six sites from the inventory
above — tick write, tick arm (reuse Task 2's guard), `info_lines` status string
("NO POWER — connect a pole within 1 tile"), draw tint (suggest a desaturated cyan
distinct from `TINT_NO_FUEL`), draw arm angle (park at rest, matching `STATE_NO_FUEL`),
and the panel status + bar colour.

`EPSILON = 0.05`, matching the lamp's documented on/off threshold. Useful brownout range
is `[0.05, 1.0]` → cycle `[5, 100]` ticks.

## Task 8 — RED→GREEN: supply area, filter, save

RED: sub-case 9 (powered at Chebyshev 1 from a pole, unpowered at Chebyshev 2),
sub-case 11 (filter set → only matching items picked; RMB clears), sub-case 12 (save
round-trip preserves type, `filter_item_type`, `cycle_progress`, held item).

GREEN: panel routing in `main.gd` — electric reuses `FastInserterPanel` (it has the filter
row and no fuel row is drawn for a DATA entry lacking the slot; **verify** rather than
assume, since `_slot_y_offsets` may position a fuel row unconditionally).

## Task 9 — Regression + hotbar

Sub-case 13: basic / fast / long-reach cycles, reaches, and fuel behavior unchanged.
Add the 4th slot to the Inserters hotbar category (`hotbar.gd`).
Full suite green, zero error lines.

## Task 10 — PAUSE 1 (visual smoke) · USER GATE

Launch; user verifies: cyan body distinct from the three existing tiers; arm animation
smooth at full power; **visibly slower but still smooth** under brownout; parks at rest
and reads "NO POWER" when unpowered; hotbar shows 4 inserter slots; panel shows the filter
row and no fuel row.

## Task 11 — PAUSE 2 (gameplay) · USER GATE, then ship

Gameplay: build a real line — accumulator-backed network, electric inserters feeding a
processor, then starve the generators and watch the inserters slow smoothly rather than
stutter, and confirm lamps on the same network do **not** flicker (the constant-demand
decision paying off).

Ship: PROJECT_LOG entry, NOTES (Inserter Arc → 4 of 6; note audit #2/#6 closed), tag
`session-inserter-electric`, commit, push to `main`.

---

## Risks

1. **`FastInserterPanel` fuel-row assumption** (Task 8) — `_slot_y_offsets` may place a
   fuel row unconditionally. Verify before reusing; a dedicated `ElectricInserterPanel` is
   the fallback (~40 lines).
2. **Task 2 touches the shared path all three fuel tiers use** — the 39-suite regression
   after Task 2 is the real gate, not Task 1 going green.
3. **`effective_cycle_ticks` calls into `world`** — `cycle_ticks(b)` is currently pure and
   is called by panels for the "Cycle: Xs" display. Keep `cycle_ticks` pure and add
   `effective_cycle_ticks(b, world)` alongside, so panel callers don't need a world ref.
4. **Tick-order lag** (`grid_world.gd:620-630`): a newly-placed generator contributes 0
   supply on its first tick, so an electric inserter may show NO_POWER for one tick after
   the network is completed. Pre-existing and documented; assert in tests with a settling
   tick rather than treating it as a bug.
