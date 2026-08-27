# Implementation Plan — Electricity Session 4: Electric Processors

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development —
> one fresh implementer per task, review between tasks. Steps use `- [ ]` for tracking.

**Goal:** ELECTRIC_SMELTER and ELECTRIC_DRILL — powered variants beside the burner originals.

**Architecture:** The electric-inserter shape applied inside two existing modules: new enum
values 37/38 with own DATA rows (no fuel slot), but NO new tick modules — `smelter.gd` and
`mining_drill.gd` each gain a module-local `POWER_DEMAND_BY_TYPE`, derived `is_electric(b)`,
and an effective-target computation; `if not electric` gates on every Burner call site.
Duplicating a shipped state machine is the #15/#18 drift shape — refused at design time.

**Baseline:** `9fc91a5`, 76/76 green, tree clean.
**Design pass:** approved 2026-08-27. **Decisions locked:**
- Demand **10 / 10** (2× inserter's 5; N=4 smelters = 40 = exactly 2 steam generators or
  4 water wheels; flagged as the likeliest playtest retune).
- **Speed: electric 20% faster.** Ratio confirmed by user; the user's quoted absolutes
  ("16 vs 20") sit on a wrong base — the verified burner base is **40 ticks**
  (`recipes.gd` `time_ticks: 40`; `DRILL_TICKS_PER_ORE = 40`), so the ratio lands as
  **electric 32 vs burner 40**, machine-side multiplier only, **never** an edit to the
  shared recipe rows. State both numbers + the 0.8 ratio in DATA comments so a future
  balance pass sees the intent. ⚠ If the user corrects the base, only the multiplier
  constant moves.
- **Mid-cycle brownout semantics: target-stretch** (int progress; elapsed work revalued
  when satisfaction changes). Effective target = `ceil(base × 0.8_if_electric / max(0.05, sat))`
  — copy the shipped form (`inserter.gd:170`, `:259-264`), NOT the Session-1 doc
  (`NOTES.md:596-602` corrects it; `power_network.gd:21`/`:625` still carry the stale
  formula and get fixed in Task 7).
- **Stall scope:** under NO_POWER, belt pulls into `in_buffer` and output pushes keep
  running (mirrors burner NO_FUEL; minimal diff).
- **Q3 dual-pin (user):** freeze-and-resume is pinned by BOTH the at-M elapsed assertion
  (`progress == e`, buffers unchanged) AND the wall-clock completion identity (first emit
  at literal `N + outage + remainder`). The completion identity is the stronger pin — it
  is the one that catches a "helpful" drain-during-outage; the elapsed form alone stays
  green under exactly that regression. Constraints as literals: `e ≠ 0`,
  `outage > T_eff − e`, `outage mod T_eff ≠ 0`.
- **Q4 structural guard (user):** fuel fields present-but-unused (the `Burner.make_state()`
  merge stays). Ship a **shape assertion at make()** — the electric variant's state key
  set pinned as a literal — plus the named mutation: **adding an idiom-consistent
  defensive `.get()` at the reader whose bare access is currently the loud guard must
  still redden the suite**. The protection must not rest on a crash-by-absence. (If no
  bare-access site exists, the implementer says so rather than inventing one.) NOTES
  records this under silent compensation as "guarded by an emergent property".
- **Rig:** second scenario `--scenario=processor_rig`; `electric_rig`'s demand-40 `==`
  invariant untouched. Two scenarios with two exact-sum invariants beat one with a
  recomputed total. RigSupport extraction (already-fired trigger, `NOTES.md:340-362`)
  goes FIRST.

**Standing protocols (every task):** three-count runs (`passed,` + `Parse Error` +
`SCRIPT ERROR`); every mutation echoed from disk and reverted from a file copy; line
endings byte-counted after each pass; expectations as literals, never computed by the
module under test; assert the path; pathspec commits with the Co-Authored-By trailer;
`art/` read-only; real saves untouched (`save_slot_1.json` + two `.pre-pause1-backup`);
`.gd.uid` via the editor pass for every new file (**skipped three sessions running**);
`--headless --import` after adding files; re-derive every cited line at dispatch.

---

## Burner-regression rule (binds Tasks 3-5)

`test_smelter.gd` and `test_mining_drill.gd` are the burner pins and **neither file's
literals move** — 4 ingots @200 ticks fuel 8→4, batch FIFO at 40/80/120/160, drill 1 ore
@40 with fuel 4→3 at 8 ore. Both suites green with unchanged literals + no edit inside a
burner-only branch + the un-gate mutations reddening burner literals = the originals
provably unchanged. Two-direction guard per half (the electric-inserter (2a) pattern):
`power_demand(burner_type) == 0` AND `is_electric(burner) == false`.

## Task 1 — RigSupport extraction (S)

The fired trigger from NOTES: three rigs share scaffolding; the fourth (Task 6) must not
copy it a fourth time. Extract the shared rig helpers into `scripts/world/rig_support.gd`
per the seam NOTES records; the three existing rigs delegate.
- [ ] Baseline run: 76/76, three counts clean.
- [ ] Extract; rigs delegate; **no literal in `test_electric_rig.gd` / pole rig suites moves**.
- [ ] Full suite green; line endings; pathspec commit.

## Task 2 — Registry rows (S)

Enum `ELECTRIC_SMELTER` (37), `ELECTRIC_DRILL` (38) appended after UNDERGROUND_BELT_EXIT;
DATA rows (2×2 / 1×1 mirroring originals, **no `"fuel"` slot kind** — the
`buildings.gd:709-720` electric-inserter comment is the model), make/tick/draw/info
dispatch arms, hotbar **Mining beside originals** (2→4 of 9). Body colours distinct from
the burner originals AND from each other (mind the ΔE floor suite).
- [ ] RED: registry sub-cases in the two new suites — enum ints **37/38 as literals**,
      footprints, no-fuel-slot shape, colour distance. Run: fails "type not found".
- [ ] Implement rows + arms. `--headless --import`. Suite green.
- [ ] Pathspec commit.

## Task 3 — Smelter half (M)

`smelter.gd` parametric: `make(b_type)`, `POWER_DEMAND_BY_TYPE = {ELECTRIC_SMELTER: 10}`,
derived `is_electric`, `SPEED_RATIO` electric 0.8 (DATA-commented 32-vs-40), effective
target at the `:121` compare, NO_POWER write + progress-preserving resume (the IDLE-arm
re-entry is the reset-AND-double-consume hazard — resume rule: `progress > 0` ⇒ SMELTING,
consume nothing), gates on `:81`, `:112`, `:117`, `:125-165`, `:262`;
`power_network.gd` consumer arm via `_supply_component_id`.
- [ ] RED first: `scripts/tests/test_electric_smelter.gd` — #25 row-shape + two-sample
      protocol, per-row powered fixture (`_verified_satisfaction`): sat 1.00 → 2 cycles
      at tick **64** exactly (T_eff 32; sample at 63 holds 1); 0.50 → **128**; 0.05
      boundary (`<=`) → NO_POWER, 0 output, inputs at full preload; 0.00 → direct
      `effective` call == **640** (`ceil(32/0.05)` pins rounding). Plus: 3a/3b fuel
      sentinel; wood-on-fuel-belt-not-eaten; Q3 dual-pin freeze case; constant-demand;
      make() shape assertion; two-direction burner guard; save round-trip (enum 37
      literal, mid-batch progress).
- [ ] Implement. Suite green, `test_smelter.gd` untouched-and-green.
- [ ] Mutations (echoed, each → named assertion): un-gate `try_pull_fuel` → wood-belt
      case; un-gate `consume_tick` → 3b sentinel; un-gate NO_FUEL write → 3a; invert
      `is_electric` → burner fuel literals red; **defensive-`.get()` addition → shape
      assertion still reds (Q4)**; resume-through-IDLE → dual-pin completion identity red;
      drain-during-outage → completion identity red while elapsed-form alone would stay
      green (demonstrate exactly that, it is the user's stated reason for the dual pin).
- [ ] Pathspec commit.

## Task 4 — Drill half (M-L, the session's largest)

Everything in Task 3 against `mining_drill.gd`'s own machine: `drill_progress`, threshold
compare `:140` (base 40, electric 32), fuel sites `:119`, `:146-150`, `:283`,
`validate_placement` `:98-99` parametrised for 38, NO_FUEL's existing freeze-at-threshold
precedent extended to NO_POWER-anywhere, **DEPLETED vs NO_POWER precedence decided and
pinned** (recommend DEPLETED wins — it is the permanent fact), richness-unchanged premise
in the freeze case (a runaway drill drains the deposit — the drill's extra path signal).
- [ ] RED first: `scripts/tests/test_electric_drill.gd` — same families; ore N at ticks
      **32N** (sat 1.0) / **64N** (0.5); epsilon; dual-pin freeze with richness premise;
      wood-belt on any edge (drill pulls all four — the case is mandatory); 3a/3b; shape
      assertion; two-direction guard; save round-trip (enum 38); DEPLETED/NO_POWER.
- [ ] Implement. `test_mining_drill.gd` untouched-and-green. Same mutation set + precedence flip.
- [ ] Pathspec commit.

## Task 5 — Panels (M)

No `_slot_y_offsets` collision (both panels use per-kind rect matches — verified in the
design pass) but: fuel labels drawn unconditionally (`smelter_panel.gd:130-140`,
`drill_panel.gd:167-177`), status matches have **no NO_POWER arm** (`:146-155` / `:184-196`
— an electric machine would render "Status: Idle", the exact lie the inserter panel work
exists to prevent), drill hardcodes `"/ 40"` (`:145`) — must show the effective target.
- [ ] RED first: rendered-string assertions (the mapping, not pixels — Route A): NO_POWER
      status string per panel (pays the NOTES gate-automation debt), no fuel text for
      electric, drill progress shows effective. Mutation: delete the NO_POWER arm → red.
- [ ] Implement (`is_electric` gates + arms + row compaction per `inserter_panel.gd:182-190`).
- [ ] Pathspec commit.

## Task 6 — processor_rig scenario (M)

`--scenario=processor_rig` on RigSupport: 2 electric smelters + 2 electric drills = **40
demand** against the 2×20 steam blocks (midpoint exactly 0.50), F-key lever per
electric_rig conventions. New suite asserts placements and demand with **`==`** — never
`>=` (#26 is the record of what lower bounds cost). `test_electric_rig.gd` untouched.
- [ ] RED: the new rig suite's exact-sum literals. Implement. Commit.

## Task 7 — Close-out (S)

- [ ] Fix the two stale formula comments (`power_network.gd:21`, `:625`) + NOTES' echoes.
- [ ] NOTES: silent-compensation instance "guarded by an emergent property" (user's
      wording: the absence that currently protects is one idiom-consistent edit from
      becoming the absence that bills nothing); arc updates.
- [ ] `.gd.uid` sidecars for BOTH new suites (do not skip a fourth time). Boot smoke.
- [ ] PROJECT_LOG entry, tag `session-electricity-processors`, push.

## PAUSE-gate list (accumulates for this session's visual gate)

1. Electric smelter/drill visually distinct from burner originals at a glance.
2. Brownout legibility: at 0.5 satisfaction both machines visibly run at half speed.
3. NO_POWER panel status reads correctly; no fuel row on electric panels.
4. `processor_rig` F-key sweep: 1.00 / 0.50 / 0.00 behave as the suite's literals say.
