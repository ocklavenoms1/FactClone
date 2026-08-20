# Design Spec — Inserter Arc Session 4: Electric Inserter

**Date:** 2026-08-20
**Baseline:** `a38b4d7`, 39/39 green, tree clean, `main` sole branch
**Save impact:** v18 unchanged (new building type appended to enum; new state fields on a new type only)

All claims below verified by code citation (DBV). Where the locked design brief and the
code disagreed, the code wins and the discrepancy is flagged.

---

## 1. Verification of locked decisions

### 1.1 Parametric pattern holds — CONFIRMED, with one exception

`Inserter.tick` is genuinely tier-agnostic. Everything tier-specific resolves through
accessors:

- `cycle_ticks(b)` → `CYCLE_TICKS_BY_TYPE` (`inserter.gd:128-129`)
- `body_color(b)` → `BODY_COLOR_BY_TYPE` (`:132-133`)
- `reach(b)` → `REACH_BY_TYPE` (`:138-139`), consumed by `source_tile`/`dest_tile`
- `arm_length(b)` → `ARM_LENGTH_BY_TYPE` (`:143-144`), consumed by `draw`

**Exception:** `Burner.consume_tick(b, ticks)` is called unconditionally in three state
arms (`inserter.gd:198, 214, ~230`), and the fuel pull at `:178-182` runs before the
state machine. An electric tier has no `fuel_buffer`, so these must be gated. This is the
*only* place the tick is not tier-agnostic.

**Conclusion:** no new module. Add four table rows plus a fuel-vs-electric branch. Estimated
delta in `inserter.gd`: ~35 lines.

### 1.2 Consumer supply rule — CONFIRMED

Consumers use `_supply_component_id` (`power_network.gd:273-297`), which scans
`SUPPLY_RADIUS` Chebyshev around **every footprint cell** for a pole.
`SUPPLY_RADIUS = 1` (`:45`). Generators use `_adjacent_component_id` (strict cardinal).
The asymmetry is real and documented at `:296-300`.

For a 1×1 consumer the per-position helper `power_satisfaction_at(world, pos)`
(`:312-325`) is the correct call — it is explicitly described as "the per-position
equivalent of `_supply_component_id` for 1×1 callers." The electric inserter is 1×1, so
it uses `power_satisfaction_at(b.anchor)`, exactly as `ElectricLamp.tick` does
(`electric_lamp.gd:30-31`).

### 1.3 Satisfaction contract — CONFIRMED, formula is correct

Stage 3 (`power_network.gd:229-243`):

```gdscript
var effective_supply: float = float(raw) + acc_sup - acc_drain
var sat: float = 1.0 if dem == 0 else min(1.0, effective_supply / float(dem))
```

Range `[0.0, 1.0]`, capped at 1.0, and `dem == 0 → 1.0`. `power_satisfaction_at` returns
`0.0` when no pole is within `SUPPLY_RADIUS`.

The briefed formula `BASE / max(0.1, satisfaction)` is arithmetically sound: sat 1.0 → 5
ticks, sat 0.5 → 10, floor 0.1 → 50 ticks (10× worst case). **But see §3.3** — the floor
creates a behavioral problem at sat == 0.

### 1.4 Tick ordering — CONFIRMED, and it decides §2

`PowerNetwork.update_supply_demand(self)` runs as a **pre-pass** at `grid_world.gd:631`,
*before* the two building-tick loops at `:633-637`. Consumers therefore read
current-tick satisfaction. The comment block at `:620-630` documents one known lag:
a generator's `output_active` is set during its own tick, which fires *after* the
pre-pass, so a newly-placed generator contributes 0 supply on its first tick.

### 1.5 Filter reuse — CONFIRMED

`FAST_INSERTER` DATA declares the filter slot as kind `"filter"`, `state_field
"filter_item_type"`, `accepts: []`. `filter_item_type` already exists in **every**
inserter's state (`Inserter.make`, default `-1`) and is checked in `_try_pickup`
regardless of tier. The picker is wired in `FastInserterPanel`. Reuse is a DATA copy plus
panel routing — no new slot kind, no new picker.

---

## 2. THE ARCHITECTURAL QUESTION: constant vs duty-cycled demand

### What the code says

Demand is **fully recomputed every tick, not cached and not dirty-flagged.**
`update_supply_demand` resets all per-component accumulators (`power_network.gd:157-164`)
then re-sums by iterating every building in Stage 1 (`:165-192`). The
`_power_network_dirty` flag gates only `rebuild_topology` — the *graph* — never the
supply/demand numbers.

So the cost objection against duty-cycling is **void**: reading a different field per
inserter in Stage 1 costs nothing extra, and forces no rebuilds.

### Why I still recommend CONSTANT

Three code-grounded reasons, in increasing severity:

**(a) It matches the only existing consumer.** `ElectricLamp` adds `DEMAND`
unconditionally (`power_network.gd:186-190`) — no activity gate — even though its
*brightness* modulates. Demand is constant; only the visual responds. Duty-cycling the
inserter would make the arc's two consumers behave on different principles.

**(b) Satisfaction is per-component and global, so oscillation is contagious.**
`power_satisfaction_at` returns the whole component's `sat`. Inserters starting and
stopping would swing `dem`, which swings `sat`, which visibly flickers every lamp on the
same network — a consumer that did nothing wrong.

**(c) The decisive one — duty-cycling creates a feedback loop fed by stale state.**
Demand is computed in the pre-pass, *before* the inserter ticks (`grid_world.gd:631`
precedes `:633`). At pre-pass time the inserter's activity flag is from the **previous**
tick. So the loop is: last tick's activity → this tick's demand → this tick's
satisfaction → this tick's cycle speed → next tick's activity. That is a delayed-feedback
control loop with no damping, and the classic failure mode is a limit cycle — inserters
synchronising into alternating draw/idle waves, with lamps strobing in sympathy. The
Foundation comment at `grid_world.gd:626-630` already flags this exact class of
tick-ordering lag as a known wart.

**Recommendation: CONSTANT demand.** An idle inserter taxing the grid is a *legible* cost
the player can plan around ("don't over-build inserters"), and it's a design lever, not a
bug. Duty-cycling buys thematic realism and pays for it with an undamped feedback loop
and cross-consumer flicker. If duty-cycling is ever wanted, it needs a damping mechanism
(hysteresis or a smoothed demand average) designed deliberately — not as a side effect.

---

## 3. Remaining determinations

### 3.1 Demand magnitude — recommend 5

Existing scale: lamp 1; windmill 6; water wheel 10; steam generator 20.

At 5, one windmill powers one electric inserter with 1 to spare for a lamp; a steam
generator powers four. Given the tier is **2× faster than the fast inserter** (5 ticks vs
10, `CYCLE_TICKS_BY_TYPE`) *and* eliminates fuel logistics entirely, it should read as a
real infrastructure commitment. 5 does that.

Endorsing the briefed guess — but flagging it as **the number most likely to need
playtest tuning**, and it is a one-const change (`ElectricInserter.DEMAND`).

### 3.2 Visual — recommend electric cyan `Color(0.25, 0.75, 0.80)`

Taken: bronze `(0.55,0.45,0.30)` basic; cool blue-grey `(0.45,0.55,0.70)` fast; rust-red
`(0.65,0.30,0.22)` long-reach. Cyan is unambiguous against all three (the fast tier's
blue-grey is desaturated and darker), reads "electric" semantically, and does not collide
with the lamp's warm yellow `(1.00,0.90,0.50)` or the steam generator's dark iron
`(0.40,0.35,0.32)`.

### 3.3 Powerless behavior — the brief's precedent DOES NOT EXIST

**The briefed precedent is wrong, and this matters.** The h1 fix (fuel-out preserves the
held item) lived on `audit-hardening-stale-base` and **was never ported**. Verified:
`grep "held_item_type(b) >= 0" scripts/world/inserter.gd` → no match. The
`STATE_IDLE, STATE_NO_FUEL` arm (`inserter.gd:191-199`) still calls `_try_pickup` then
`_set_held`, overwriting any held item.

Two consequences:

1. **Audit finding #2/#6 is still live** for all three fuel tiers: an inserter that runs
   out of fuel mid-swing has its held item destroyed on refuel.
2. If the electric tier is implemented correctly (hold on power loss), the tiers will
   **diverge** — electric preserves, fuel destroys.

**Recommendation:** hold the item (correct behavior), and fix the fuel-tier bug in the
same session so all four tiers behave identically. The fix is the one already designed and
proven on the archive branch: in the `IDLE/NO_FUEL` arm, if `held_item_type(b) >= 0`,
resume the delivery (re-enter `WORKING_OUT` with `cycle_progress` clamped to `[0.0, 0.5]`)
instead of picking up. Same guard serves a new `STATE_NO_POWER`.

If you prefer to keep the session scoped tightly, the alternative is to defer the fuel fix
and accept documented divergence — but that ships a known item-destruction bug alongside a
tier that visibly does the right thing, which is the worse outcome.

### 3.4 Zero-satisfaction needs a distinct state — NOT in the brief

`BASE / max(0.1, satisfaction)` at sat == 0.0 yields 50 ticks: an inserter with **no power
source at all** still completes a swing every 2.5 s. That is wrong on two counts — it
performs work from nothing, and "unpowered" becomes indistinguishable from "severely
browned out."

The lamp's precedent is that sat 0.0 is fully off (`OFF_COLOR`, `electric_lamp.gd:18`).

**Recommendation:** add `STATE_NO_POWER` mirroring `STATE_NO_FUEL`. Below a small epsilon
(suggest `sat < 0.05`, matching the lamp's documented on/off threshold) the inserter
stalls, holds any held item, and tints to signal it. The proportional formula applies only
above the epsilon, so the useful brownout range is `[0.05, 1.0]` → cycle `[5, 100]` ticks.
If a 20× worst case feels too punishing, raise the epsilon rather than reintroducing the
0.1 floor.

### 3.5 Where the slowdown hooks — one substitution

`inserter.gd:188` computes `var inc: float = 1.0 / float(ticks)` once from
`cycle_ticks(b)`, and all four state arms advance `cycle_progress` by `inc`. Substituting
an effective tick count at that single line stretches the arm interpolation smoothly
across the longer cycle — **no stutter, no stall**, exactly the briefed feel, and it falls
out of the existing structure rather than needing new interpolation code.

---

## 4. Proposed test sub-cases

Existing `test_inserter.gd` conventions apply (world helper, `_check`, `_disconnect`,
`TEST_SAVE_PATH` + `_cleanup`).

1. **Registry/tables** — 1×1, `supports_direction`, cycle 5, reach 1, cyan, walkable.
2. **Full-power transport** — sat 1.0 → one item per 5-tick cycle.
3. **Brownout slowdown (the novel case)** — sat 0.5 → the same swing takes 10 ticks; assert
   an intermediate `cycle_progress` proving the arm *interpolated* rather than jumped.
4. **Brownout is smooth, not stalled** — at sat 0.5, `cycle_progress` strictly increases
   every tick (no tick where it fails to advance).
5. **No power → stalls, holds item** — sat below epsilon: state is `NO_POWER`,
   `held_item_buffer` intact across many ticks, nothing delivered.
6. **Power restored mid-swing → resumes, item conserved** — the electric analogue of the
   h1 case; total item count conserved across the outage.
7. **Fuel-tier parity (if §3.3 fix included)** — same conservation assertion for basic tier
   across a fuel outage. This is a RED test against current code.
8. **No fuel slot** — DATA has no `"fuel"` kind; `Burner.consume_tick` never runs for the
   electric tier (assert `fuel_buffer` absent/untouched).
9. **Supply area** — powered at Chebyshev 1 from a pole; unpowered at Chebyshev 2.
10. **Constant demand** — component demand includes `DEMAND` whether the inserter is idle
    or mid-swing (locks the §2 decision).
11. **Filter parity** — filter set → only matching items picked; RMB clears.
12. **Save round-trip** — type, `filter_item_type`, `cycle_progress`, held item survive.
13. **Tier regression** — basic/fast/long-reach cycles, reaches, and fuel behavior unchanged.

---

## 5. Implementation order (RED-before-fix throughout)

1. Enum + DATA + `make()`/dispatch stubs + `--headless --import` (new-file registration).
2. RED: sub-cases 1-2 → tables (four rows) → green.
3. RED: 8, 10 → fuel-branch gating + demand in Stage 1 → green.
4. RED: 3, 4 → `effective_cycle_ticks` at the `inc` site → green.
5. RED: 5, 6 → `STATE_NO_POWER` + held-item guard → green.
6. RED: 7 → fuel-tier parity fix (audit #2/#6) → green. **Scope decision required first.**
7. RED: 9, 11, 12 → supply area, filter routing, save → green.
8. 13 regression, hotbar slot, panel routing, PROJECT_LOG + NOTES, tag.

---

## 6. Open decisions for the user

1. **Demand = 5?** Endorsed, flagged as the likeliest tuning target.
2. **Include the fuel-tier held-item fix (§3.3)?** Recommend yes — otherwise the session
   ships a tier that behaves correctly beside three that destroy items.
3. **`STATE_NO_POWER` with epsilon 0.05 (§3.4)?** Recommend yes — the briefed 0.1 floor
   lets an unpowered machine work.
