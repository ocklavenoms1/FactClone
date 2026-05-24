# Electricity Arc Session 2 — More Generators + Accumulator

**Session tag (planned):** `session-electricity-generators-storage`
**Date:** 2026-05-15
**Save schema impact:** none (v18 unchanged — append-only enum + `.get()`-defaulted state)
**Test count target:** 37 → ~38 (sub-cases appended to existing `test_power_network.gd`; no new test file)
**Methodology:** Superpowers brainstorming → writing-plans → subagent-driven TDD → verification-before-completion. Validated protocols: DBV (6 catches, 100% capture), UX iteration trap (post-2-failures force rule), magic-number test-coord audit, variable name pre-check, line-quoting on reviewers, --headless --import for new files.

---

## 1. Context

Continues the Electricity Arc shipped at `session-electricity-foundation` (HEAD `a3358fc`). Foundation provided:

- `PowerNetwork` module (BFS topology + dirty-flag + per-component supply/demand/satisfaction)
- POWER_POLE (1×1 connector)
- WATER_WHEEL (2×2 generator, requires water adjacency, MAX_OUTPUT=10)
- ELECTRIC_LAMP (1×1 consumer, DEMAND=1, brightness modulates with satisfaction)
- **Arc-wide consumer interface contract**: `satisfaction = min(1.0, supply / max(1, demand))` with consumers reading `world.power_satisfaction_at(b.anchor)`. Future processors (Session 4+) apply `1.0 / max(0.1, satisfaction)` cycle-multiplier.
- **Asymmetric pole rules**: generators strict cardinal adjacency; consumers Chebyshev radius ≤ SUPPLY_RADIUS=1.

This session adds **3 new buildings + accumulator network logic**:

| # | Building | Role | Footprint | Output |
|---|---|---|---|---|
| 1 | Windmill | Generator (no resource dep) | 2×2 | 6 power/tick |
| 2 | Steam Generator | Generator (fuel-powered) | 2×2 | 20 power/tick when active |
| 3 | Accumulator | Storage (charge↔discharge) | 1×1 | ±5 power/tick, capacity 50 |

Future sessions: pole tiers (Session 3 — parametric), electric processors (Session 4), electric inserters (Session 5).

## 2. Scope (locked — do not extend)

**In:**

- `Buildings.Type.WINDMILL` — 2×2 generator, always active (no resource gating), 6 power units
- `Buildings.Type.STEAM_GENERATOR` — 2×2 generator, fuel-powered via Burner (5th consumer), 20 power units when active, cycle-based fuel rate (1 unit per 20 ticks)
- `Buildings.Type.ACCUMULATOR` — 1×1 storage, capacity 50 units, ±5/tick charge/discharge, vertical fill-bar visual
- Extend `PowerNetwork.update_supply_demand` to a **3-stage internal flow** (raw_supply+demand → accumulator charge/discharge → satisfaction with effective_supply)
- Hotbar Power category grows 3 → 6 slots (pole, wheel, lamp, windmill, steam, accumulator)
- ~8 new test sub-cases appended to `test_power_network.gd`

**Out (deferred to future sessions):**

- Solar panels (requires day/night cycle which doesn't exist yet)
- Pole tiers (medium pole, substation) — Session 3 parametric extension
- Electric processors (smelter, drill) — Session 4
- Electric inserter — Session 5
- Steam as a fluid (single-building Steam Generator avoids fluid-system expansion)
- Priority-based accumulator distribution (even-distribution v1)
- Accumulator-to-accumulator wireless transfer across networks
- Brownout indicator on consumers (existing lamp brightness modulation already shows this)

## 3. Methodology layering

Subagent triad per task (implementer + spec reviewer + code quality reviewer). Line-quoting on reviewers. Strengthened scope-deviation. DBV continues. UX iteration trap protocol applies. Variable name pre-check. `--headless --import` verification for new `.gd` files (Windmill, Steam Generator, Accumulator).

Per-task time estimate (per user): Windmill ~1h (easiest), Steam ~45min (Burner integration), Accumulator ~1h (network logic extension). **Total ~3h.**

## 4. Design decisions (Q1–Q10 locked)

### Q1 — Windmill footprint: 2×2

Parity with WaterWheel for visual weight + parity with Mixer/Briquetter-class processors. Justified: even though Windmill has no resource dependency, it's a substantial generator that should "feel" comparable to its water-wheel cousin. 1×2 alternative rejected — would visually undersell the 6-unit output.

### Q2 — Windmill output: 6 power units (vs WaterWheel's 10)

Tradeoff: free placement (no terrain dep) vs lower throughput. Players who don't have water access (or want to extend networks beyond shorelines) can use windmills at 60% efficiency. With multiple windmills the math works for distributed micro-grids; water wheels remain the higher-density option where geography permits.

### Q3 — Windmill adjacency: strict cardinal (same as WaterWheel)

Per Foundation Q3 — generators strict cardinal pole adjacency. Reuse existing `PowerNetwork._adjacent_component_id` (4-cell perimeter scan via `Buildings.all_edge_cells`). No code change needed in PowerNetwork — Windmill slots in as a 3rd generator type in `update_supply_demand`.

### Q4 — Steam Generator: single building, NOT boiler+engine chain

User leans (a) — simplest. Verified against codebase: `fluids.gd` has only WATER type; expanding to STEAM as a separate fluid + boiler→pipe→engine chain would be substantial scope expansion. Single Steam Generator with internal fuel→power conversion is the right v1.

Future: if Session 5+ wants the boiler+engine chain (e.g., for thermal logistics depth), the single Steam Generator can be retired or coexist. No commitment now.

### Q5 — Steam Generator fuel consumption: cycle-based, 1 unit per 20 ticks (1.0s) while active

**User chose (a) — cycle-based, matching Smelter / Inserter Burner convention.**

Concrete math:
- Burner.FUEL_VALUES: WOOD=1, COAL=4, FUEL_BRIQUETTE=8
- Cycle ticks: 20 (1.0s @ 20 TPS)
- 1 WOOD = 1 energy unit = 1 cycle (1.0 second of 20-power output)
- 1 COAL = 4 energy units = 4 cycles (4.0 seconds of 20-power output)
- 1 FUEL_BRIQUETTE = 8 energy units = 8 cycles (8.0 seconds of 20-power output)
- Fuel buffer cap: 16 units (matches Smelter convention)

Steam Generator state shape:
```gdscript
{
    "output_active": false,         # set per-tick based on fuel availability
    "fuel_buffer": 0,               # Burner state (units, not items)
    "fuel_burn_progress": 0,        # Burner state (ticks toward next unit consumed)
    "last_fuel_item": -1,           # Burner state (for visual indicator)
}
```

Reuses existing Burner module API: `Burner.try_pull_fuel(b, world, fuel_edge_dir)` + `Burner.consume_tick(b, cycle_ticks)`. No new Burner code needed — Steam Generator just calls into it like Smelter/Inserter do.

### Q6 — Steam Generator output: 20 power units (2× WaterWheel)

Tradeoff: fuel-cost overhead + 2×2 footprint with port complexity (fuel input) → highest power density per building. Players progress from passive (water wheel, free 10) → flexible (windmill, free 6) → fuel-powered (steam, 20 but consumes fuel).

### Q7 — Accumulator state model: `charge: float`, capacity 50, ±5/tick

```gdscript
{
    "charge": 0.0,                  # current stored energy [0.0, MAX_CAPACITY]
}
```

Constants on Accumulator module:
```gdscript
const MAX_CAPACITY: int = 50           # power units storable
const MAX_CHARGE_RATE: int = 5         # units per tick when supply > demand
const MAX_DISCHARGE_RATE: int = 5      # units per tick when supply < demand
```

Float `charge` to allow fractional accumulation under even distribution (3 accumulators sharing 4 units of excess each get 1.33 — float math prevents truncation loss). Display rounds to int in Q-inspect ("Charge: 12/50 units").

### Q8 — Network logic: 3-stage internal flow in update_supply_demand (USER LOCKED)

Current Foundation flow: single walk → supply + demand summed → satisfaction. Extension to handle accumulators requires a 3-stage flow inside `update_supply_demand`:

**Stage 1 — Raw supply + demand:**

Walk all buildings. Classify by type:
- Generators (WATER_WHEEL, WINDMILL, STEAM_GENERATOR) → contribute MAX_OUTPUT to `_component_raw_supply[comp_id]` when `state.output_active == true`
- Consumers (ELECTRIC_LAMP) → contribute DEMAND to `_component_demand[comp_id]`
- Accumulators (ACCUMULATOR) → classified but NOT yet summed; track per-component accumulator list `_component_accumulators[comp_id] = [Building...]` for Stage 2

**Stage 2 — Accumulator charge/discharge:**

For each component:
- `excess = raw_supply - demand` (signed: positive = surplus, negative = deficit)
- For each accumulator in `_component_accumulators[comp_id]` (even distribution):
  - If `excess > 0`: try to charge — `delta = min(excess_per_accumulator, MAX_CHARGE_RATE, MAX_CAPACITY - charge)`. Mutate `state.charge += delta`. Track total `_component_accumulator_drain[comp_id] += delta`.
  - If `excess < 0`: try to discharge — `delta = min(deficit_per_accumulator, MAX_DISCHARGE_RATE, charge)`. Mutate `state.charge -= delta`. Track total `_component_accumulator_supply[comp_id] += delta`.
  - If `excess == 0`: no-op.

`excess_per_accumulator = excess / len(accumulators_in_component)` — even distribution per user lean.

**Stage 3 — Satisfaction with effective supply:**

```
effective_supply = raw_supply + _component_accumulator_supply[comp_id] - _component_accumulator_drain[comp_id]
satisfaction = min(1.0, effective_supply / max(1, demand))
```

Stored in `_component_satisfaction[comp_id]` as before. Consumer interface contract UNCHANGED — `world.power_satisfaction_at(pos)` returns the post-accumulator value. Lamps continue to modulate brightness identically. Future Session 4+ processors apply `1.0 / max(0.1, satisfaction)` cycle-multiplier identically.

**Storage mutation in pre-pass justified**: accumulators ARE network state. Per Foundation precedent (fluid network was query-driven, lazy rebuild), the accumulator charge is a per-tick network-wide computation that fundamentally happens at the network level, not the building level. Building's own `tick()` becomes visual-only (no-op for storage, or update visual indicator).

### Q9 — Accumulator visual: vertical fill-bar inside building rect (USER LOCKED)

Bar fills bottom-up as charge accumulates. Color shifts:
- 0% charge → gray `Color(0.30, 0.30, 0.30)`
- 100% charge → golden `Color(0.95, 0.78, 0.30)` (matches `SlotWidget.BORDER_HOVER` warm-yellow family for project visual consistency)

Interpolation via `OFF_COLOR.lerp(FULL_COLOR, charge / MAX_CAPACITY)`. Empty stays gray (still visible to confirm building exists); full glows.

Bar takes ~60% of building height inside an inset rect (small frame around it). Building body remains a constant base color (dark slate `Color(0.30, 0.30, 0.40)` for "battery" connotation).

Q-inspect shows numeric charge: `"Charge: 12 / 50 units"` + network info per existing power-building pattern.

### Q10 — Multi-accumulator distribution: even (USER LOCKED)

Simpler than priority-based. Predictable for players: 3 accumulators each get 1/3 of network excess; on discharge, each contributes 1/3 of the deficit (up to its individual charge). Future session can add priority via `RANGE_BY_TYPE`-style parametric table if needed.

### Save schema: NO bump (stays v18)

- Append-only enum: WINDMILL, STEAM_GENERATOR, ACCUMULATOR at end of `Buildings.Type` (gets next 3 ints)
- New state fields default via `.get(field, default)` — old saves work unchanged
- Same precedent as every prior building-type addition

## 5. Specific buildings

### WINDMILL (2×2)

```gdscript
Type.WINDMILL: {
    "name": "Windmill",
    "swatch_color": Color(0.85, 0.85, 0.75),    # bone-white / canvas-sail
    "footprint": Vector2i(2, 2),
    "requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
    "supports_direction": false,                 # wind comes from anywhere; visual is rotating blades
    "player_drainable": false,
    "walkable": false,
}
```

- `state = {output_active: true, blade_rotation: 0.0}` (always active — no resource gating)
- `MAX_OUTPUT: int = 6`
- `BLADE_ROTATION_PER_TICK: float = 0.10 * TAU / 20.0` (slower than water wheel — visual differentiation)
- `make(pos)`: `Building.new(WINDMILL, pos, {output_active: true, blade_rotation: 0.0})`
- `tick(b, world)`: advance `blade_rotation`; `output_active` stays true (no condition)
- `draw`: 2×2 base + rotating 4-blade visual (X-pattern), bone-white color
- `info_lines`: `Output: 6 / 6 units (always active)` + `Network: #N` (or "(not adjacent to a pole)")

### STEAM_GENERATOR (2×2)

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
}
```

- `state = {dir, output_active: false, fuel_buffer: 0, fuel_burn_progress: 0, last_fuel_item: -1}` (Burner state inline)
- `MAX_OUTPUT: int = 20`
- `CYCLE_TICKS: int = 20` (1 fuel unit per cycle)
- `FUEL_PORT_DIR: int = Belt.DIR_S` (mirrors Smelter — restricts fuel intake to S edge of canonical orientation; protects against fuel ports overlapping non-fuel adjacents)
- `make(pos, dir)`: initializes Burner state via `Burner.make_state()` merge pattern
- `tick(b, world)`:
  - Pull fuel if buffer empty: `Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR))`
  - If `fuel_buffer > 0`: `output_active = true`, `Burner.consume_tick(b, CYCLE_TICKS)`
  - Else: `output_active = false`
- `draw`: 2×2 industrial body + smokestack (small rectangle on top) + steam puff visual when active (small white circles above smokestack, animated)
- `info_lines`: `Output: 20/20 units (active)` or `Output: 0/20 units (no fuel)` + Burner.info_lines (fuel buffer state) + Network info

### ACCUMULATOR (1×1)

```gdscript
Type.ACCUMULATOR: {
    "name": "Accumulator",
    "swatch_color": Color(0.30, 0.30, 0.40),    # dark slate
    "footprint": Vector2i(1, 1),
    "requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
    "supports_direction": false,
    "player_drainable": false,
    "walkable": false,
}
```

- `state = {charge: 0.0}` (float — even-distribution allows fractional)
- `MAX_CAPACITY: int = 50`
- `MAX_CHARGE_RATE: int = 5`
- `MAX_DISCHARGE_RATE: int = 5`
- `OFF_COLOR: Color = Color(0.30, 0.30, 0.30)` (empty)
- `FULL_COLOR: Color = Color(0.95, 0.78, 0.30)` (full, matches SlotWidget hover-yellow family)
- `BASE_COLOR: Color = Color(0.30, 0.30, 0.40)` (battery body)
- `make(pos)`: `Building.new(ACCUMULATOR, pos, {charge: 0.0})`
- `tick(b, world)`: NO-OP (charge mutation happens in `PowerNetwork.update_supply_demand` pre-pass per Q8)
- `draw`: 1×1 base body in BASE_COLOR + vertical fill-bar inside (60% of building height, inset rect), bar color = `OFF_COLOR.lerp(FULL_COLOR, charge / MAX_CAPACITY)`. Bar height scales with charge fraction (bottom-up fill).
- `info_lines`: `Charge: X / 50 units (Y%)` + adjacency check (whether attached to a network)

## 6. Module changes

### `scripts/world/power_network.gd` — extend update_supply_demand to 3-stage

Replace current single-walk with 3 stages. New per-component intermediate state:
- `_component_raw_supply: Dictionary` — generator output only (before accumulator effects)
- `_component_accumulators: Dictionary` — list of accumulator Buildings per component (cleared and rebuilt per call)
- `_component_accumulator_supply: Dictionary` — total discharge contribution per component
- `_component_accumulator_drain: Dictionary` — total charge consumption per component

`_component_satisfaction[comp_id]` remains the consumer-facing query result; consumers see the post-accumulator value.

Add public query: `accumulator_charge_for(world, comp_id) -> float` for Q-inspect (returns total network-wide charge across all accumulators in component, for diagnostic display).

### `scripts/world/grid_world.gd` — dirty-flag hooks

Extend `place_building` and `remove_building_at` dirty-flag triggers to include the 3 new types:

```gdscript
if t == Buildings.Type.POWER_POLE or t == Buildings.Type.WATER_WHEEL or t == Buildings.Type.ELECTRIC_LAMP \
    or t == Buildings.Type.WINDMILL or t == Buildings.Type.STEAM_GENERATOR or t == Buildings.Type.ACCUMULATOR:
    _power_network_dirty = true
```

### `scripts/ui/hotbar.gd` — append 3 slots

Power category grows 3 → 6 slots. Order: pole, wheel, lamp, **windmill, steam generator, accumulator**. Players see "generators first, then consumers/storage" reading left-to-right.

## 7. Tests

**~8 new sub-cases appended to `scripts/tests/test_power_network.gd`** (no new test file — runner count stays at 37 per Foundation precedent; sub-cases internal count grows from 10 to ~18).

### Sub-case list (all in `test_power_network.gd run()`)

1. **Windmill always active** — place windmill, no resource setup needed → `output_active == true` after tick.
2. **Windmill joins network supply** — windmill adjacent to pole → component supply == WindMill.MAX_OUTPUT (6).
3. **Steam Generator no fuel** — place steam, empty fuel_buffer → `output_active == false`, component supply stays 0.
4. **Steam Generator with fuel** — manually set `fuel_buffer = 100`, tick → `output_active == true`, component supply += 20.
5. **Steam Generator fuel exhaustion** — set `fuel_buffer = 2`, tick 41 cycles → fuel_buffer eventually depleted, output_active flips false.
6. **Accumulator charges from excess** — wheel (10) + 0 lamps → excess 10, accumulator gains charge (5 per tick capped). Run 11 ticks → charge stabilizes at 50.
7. **Accumulator discharges into deficit** — 0 generators + 1 lamp (demand 1), pre-charged accumulator (charge=10) → accumulator discharges 1 per tick (capped by demand), satisfaction = 1.0 (effective_supply matches demand).
8. **Accumulator capacity cap** — accumulator already at 50 charge, excess 100 → no further charging, charge stays at 50.
9. **Multi-accumulator even distribution** — 2 accumulators, excess 6 → each gains 3 per tick (even split).
10. **Accumulator save round-trip** — place accumulator with charge=25, save, reload → charge preserved.

### Test approach for state-mutating pre-pass

Tests call `PowerNetwork.update_supply_demand(world)` directly (matching Foundation Task 7 test pattern — TickSystem is paused in test_runner; explicit pre-pass invocation needed). After call, assert on `_component_supply`, `_component_satisfaction`, and accumulator `state.charge` directly.

### Variable name discipline

Per validated protocol (Variable name pre-check before multi-edit), each new sub-case uses suffixed names (`_w` for windmill, `_s` for steam, `_a` for accumulator) to avoid collisions with existing sub-cases (1)-(10).

## 8. Touchpoint inventory

| File | Change |
|---|---|
| `scripts/world/buildings.gd` | 3 enum entries + 3 DATA entries + dispatch (make / tick_one / draw_one / info_lines_for) |
| `scripts/world/windmill.gd` | NEW — make/tick/draw/info_lines (always active) |
| `scripts/world/steam_generator.gd` | NEW — make/tick/draw/info_lines + Burner integration |
| `scripts/world/accumulator.gd` | NEW — make/draw/info_lines (no tick — pre-pass handles state) |
| `scripts/world/power_network.gd` | Extend `update_supply_demand` to 3-stage flow + add WINDMILL/STEAM_GENERATOR/ACCUMULATOR branches + new dict members (`_component_raw_supply`, `_component_accumulators`, `_component_accumulator_supply`, `_component_accumulator_drain`) + new public query `accumulator_charge_for` |
| `scripts/world/grid_world.gd` | Extend dirty-flag hooks in `place_building` + `remove_building_at` for 3 new types + new dict member declarations |
| `scripts/ui/hotbar.gd` | Append 3 slots to Power category |
| `scripts/tests/test_power_network.gd` | Append ~8 new sub-cases + update test_name() description |
| `scripts/tests/test_building_ui_4.gd` | Append 3 new types to `passive` array (precedent from Foundation Tasks 3+5+6) |

**3 new production files + 4 modified + 2 housekeeping (.uid).**

## 9. Implementation order (high-level — detailed task breakdown in plan)

1. **Threshold audit** — 37/37 PASS baseline
2. **Windmill** — enum + DATA + module + dispatch + sub-cases (1)+(2)
3. **Steam Generator** — enum + DATA + module (Burner integration) + dispatch + sub-cases (3)(4)(5)
4. **Accumulator + 3-stage network logic** — enum + DATA + module + PowerNetwork extension + dispatch + sub-cases (6)(7)(8)(9)
5. **Hotbar Power category extension** — append 3 slots
6. **Save round-trip sub-case** (10) — accumulator charge survives reload
7. **PAUSE 1** — visual smoke (place all 3 types, verify visuals + power flow)
8. **PAUSE 2** — full gameplay (multi-generator, multi-accumulator factory; brownout/recovery cycles)
9. **Ship** — PROJECT_LOG + NOTES + tag + push

Estimated 9-10 tasks. Smaller than Foundation (12) since most architecture exists; mostly addition + one network-logic extension.

## 10. Validation criteria at commit

- [ ] All 3 building types placeable from Power hotbar (6 slots total)
- [ ] Windmill always shows `output_active=true`; rotating blades visible; contributes 6 power per tick
- [ ] Steam Generator with fuel: output_active=true, smoke visual, contributes 20 power, fuel_buffer decrements
- [ ] Steam Generator without fuel: output_active=false, no smoke, 0 power contribution
- [ ] Accumulator visual fill-bar reflects charge level (gray → golden as charges)
- [ ] Excess network supply charges accumulators (observable via Q-inspect charge increase)
- [ ] Deficit drains accumulators (charge decrease, satisfaction stays at 1.0 until accumulator empties)
- [ ] Multi-accumulator: charge distributes evenly under excess; discharge distributes evenly under deficit
- [ ] Save mid-charge → reload → accumulator charge preserved
- [ ] Foundation behavior unchanged: pole/wheel/lamp still work; existing tests still pass
- [ ] 37 → ~37 (or 38 if new test file) tests passing
- [ ] Save schema unchanged at v18
- [ ] Tagged `session-electricity-generators-storage`, pushed to origin

## 11. Out-of-scope reminders (anti-scope-creep)

- **No solar panels** — requires day/night cycle (separate arc)
- **No pole tiers** — Session 3 parametric extension
- **No electric processors** — Session 4
- **No electric inserter** — Session 5
- **No steam as fluid** — single Steam Generator does internal fuel→power; fluid expansion deferred
- **No priority-based accumulator distribution** — even-distribution v1
- **No accumulator-to-accumulator wireless transfer across networks**
- **No brownout indicator on consumers** — existing lamp brightness modulation suffices
- **No new fuel types** — steam uses existing WOOD/COAL/FUEL_BRIQUETTE
- **No accumulator panel UI** — Q-inspect info_lines suffices for v1

## 12. Decision log (for PROJECT_LOG entry at session end)

- **Q1 — Windmill footprint**: 2×2 (visual parity with WaterWheel, signals "substantial generator")
- **Q2 — Windmill output**: 6 power units (40% below WaterWheel's 10, reflects free-placement advantage)
- **Q3 — Windmill adjacency**: strict cardinal pole adjacency (Foundation Q3 rule reused)
- **Q4 — Steam Generator architecture**: single building (not boiler+engine chain), no fluid system expansion
- **Q5 — Steam Generator fuel rate**: cycle-based, 1 unit per 20 ticks (matches Smelter convention)
- **Q6 — Steam Generator output**: 20 power units (2× WaterWheel, reflects fuel overhead)
- **Q7 — Accumulator state**: `charge: float`, capacity 50, ±5/tick. Float allows even-distribution fractions.
- **Q8 — Network logic**: 3-stage internal flow in `update_supply_demand` (raw_supply+demand → accumulator → satisfaction). State mutation in pre-pass justified — accumulators ARE network state.
- **Q9 — Accumulator visual**: vertical fill-bar, gray→golden lerp, bottom-up fill, ~60% of building height
- **Q10 — Multi-accumulator distribution**: even (predictable, simple). Priority deferred.
- **No save schema bump**: append-only enum + `.get()` defaults. Stays at v18.
- **Future arc continuation**: Session 3 (pole tiers), Session 4 (electric processors), Session 5 (electric inserters — closes both Inserter Arc AND Electricity Arc).
