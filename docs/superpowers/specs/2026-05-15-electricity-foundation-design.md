# Electricity Foundation — Electricity Arc Session 1 of N

**Session tag (planned):** `session-electricity-foundation`
**Date:** 2026-05-15
**Save schema impact:** none (v18 unchanged — append-only enum + `.get()`-defaulted state fields)
**Test count target:** 34 → 35 (+1 new test file `test_power_network.gd` with 10 internal sub-cases)
**Methodology:** Superpowers brainstorming → writing-plans → subagent-driven TDD → verification-before-completion. Layered onto the validated CLAUDE.md project protocols (design pass / PAUSE checkpoints / PROJECT_LOG / tagged commit). Last session locked the Design Brief Verification protocol (validated across Cluster A + Inserter Arc 3 = 8 cases of catching brief imprecision via code citation).

---

## 1. Context

Electricity is a **NEW major arc** with no architectural prerequisites — it slots cleanly into the existing world model. This foundation session ships the **minimum viable electric network**: one generator type (Water Wheel), one consumer type (Electric Lamp), the network topology (poles + wires + BFS), and a per-network supply/demand model with **linear satisfaction scaling**.

Future sessions extend in this order (re-plan at each session start):

| Session | Adds | Architectural cost |
|---|---|---|
| 1 — Foundation (this) | Pole, Wheel, Lamp, Network module | Module + 3 buildings + grid_world maps + dedicated test file |
| 2 — More Generators + Storage | Windmill, Steam Engine, Solar, Accumulator | DATA entries + dispatch cases, no new architecture |
| 3 — Power Pole Tiers | Medium pole + substation (wider connection range) | `RANGE_BY_TYPE` parametric table |
| 4 — Electric Processors | Electric variants of smelter, drill | First consumers using the linear-satisfaction throughput multiplier |
| 5 — Electric Inserters | Closes the Inserter Arc — combines reach + power axes | Reuses Inserter parametric tables |

Linear satisfaction (decided this session) becomes the interface contract for every future electric consumer.

## 2. Scope (locked — do not extend)

**In:**

- `Buildings.Type.POWER_POLE` — 1×1 connector
- `Buildings.Type.WATER_WHEEL` — 2×2 generator, requires water adjacency, 10-unit output
- `Buildings.Type.ELECTRIC_LAMP` — 1×1 consumer, 1-unit demand, brightness scales with network satisfaction
- `scripts/world/power_network.gd` — pure-logic module (BFS, supply/demand, satisfaction)
- `scripts/world/grid_world.gd` — new dict members for component maps + dirty-flag + `_draw_power_wires`
- Wire rendering as global draw pass between connected poles
- Q-inspect info_lines for pole / wheel / lamp showing network ID + supply/demand/satisfaction
- Hotbar "Power" category with 3 slots
- `scripts/tests/test_power_network.gd` — NEW dedicated file with 10 internal sub-cases

**Out (deferred to future sessions):**

- Other generators (windmill, steam engine, solar) — Session 2
- Accumulator / battery storage — Session 2
- Electric variants of existing buildings (smelter, drill, inserter) — Sessions 4+
- Multiple pole tiers (medium, substation) — Session 3
- Underground wires — deferred indefinitely
- Per-fluid networks for non-water generators — N/A this session (water wheel uses existing terrain query, not fluid network)
- Wire-cost / wire-as-item resource — deferred (poles auto-wire by proximity, no inventory cost)

## 3. Methodology layering

| Project protocol | Superpowers layer |
|---|---|
| Design pass + PAUSE checkpoints | brainstorming + this spec |
| Per-task implementation | writing-plans → subagent triad (implementer + spec reviewer + code quality reviewer) |
| TDD discipline | sub-case red→green per task |
| PROJECT_LOG + NOTES update | end of session |
| Tagged commit + push | terminal step |

Validated protocols from last 2 sessions apply:

- Line-quoting on reviewers (0 false positives across 17+ reviews)
- Design Brief Verification (8 cases across Cluster A + Inserter Arc 3 of catching brief imprecision via code citation — Q1 in this spec is the most recent example)
- Variable name pre-check before multi-edit test files (prevents the Task 2 stall pattern)
- Subagent stall recovery via controller diff-inspection (Cluster A Tasks 12/14/21, Inserter Session 3 Task 2)
- Edit-tool CRLF caveat on Windows — PowerShell fallback documented in NOTES
- `--headless --import` verification for new files with unusual base classes

## 4. Design decisions (Q1–Q8 locked)

### Q1 — Power network data model: graph + dirty-flag, NOT per-pole network_id

**Brief leaned (c).** Code verification against `grid_world.gd:475-565` (existing fluid network implementation) revealed the codebase precedent is (a): BFS over positions, two dictionaries on the world (`_pipe_component[pos] → comp_id`, `_component_has_pump[comp_id] → bool`), dirty flag for lazy rebuild, lex-sorted start points for deterministic IDs, pipes' own state is `{}`.

**Decision: mirror the fluid pattern exactly.** New world-level members:

```gdscript
# grid_world.gd
var _pole_component: Dictionary = {}              # Vector2i → int
var _component_supply: Dictionary = {}            # int → int (units)
var _component_demand: Dictionary = {}            # int → int (units)
var _component_satisfaction: Dictionary = {}      # int → float ∈ [0, 1]
var _power_network_dirty: bool = true
```

`POWER_POLE.state = {}` — no per-instance `network_id` field. Network membership is a computed property of the world, not stored data.

**Rebuild trigger**: `mark_power_network_dirty()` called from `place_building` / `remove_building` whenever a pole/generator/consumer is involved. Rebuild logic in `PowerNetwork.rebuild(world)`.

**Save shape**: only pole positions persist; network rebuilt on load via dirty flag.

### Q2 — Connection range: 5 tiles Chebyshev

Two poles auto-connect if `max(abs(p1.x - p2.x), abs(p1.y - p2.y)) <= 5`. Single pole type for foundation session.

Rationale: Stewardship belts are 1×1, processors 2×2. A 5-tile range = 4 empty tiles between poles, comfortably bridges a typical 3-4-building chain segment without pole-spam. Lower bound (3-tile) makes long belts annoying; higher bound (9-tile, Factorio medium) leaves players placing one giant pole per quadrant — wrong feel for cozy farming.

Future medium pole / substation will live in a `RANGE_BY_TYPE` parametric table (Session 3 design), so adding tiers is a 1-row change per tier.

### Q3 — Building-network association: adjacency via `Buildings.all_edge_cells()`

A generator or consumer joins network X if any cell along its footprint perimeter is adjacent (4-directional) to a pole in network X. This mirrors `fluid_available_for_building` at `grid_world.gd:491`, which uses the same `Buildings.all_edge_cells()` helper at `buildings.gd:738`.

- 2×2 Water Wheel has 8 perimeter cells → 8 chances to land adjacent to a pole
- 1×1 Electric Lamp has 4 perimeter cells → 4 chances

Ambiguity case: a building adjacent to TWO poles in DIFFERENT networks. The brief doesn't address this. **Resolution**: building joins the network of the FIRST pole found in `_pole_component` iteration order (lex-sorted, deterministic). Documented as a known v1 simplification; tier-3+ poles or substations might want explicit network-selection UI later.

### Q4 — Brownout strategy: LINEAR SATISFACTION SCALING

**User chose (a) over my recommendation of (b).** Each network has `satisfaction: float ∈ [0.0, 1.0]`:

```
satisfaction = min(1.0, supply / max(1, demand))
```

(`max(1, demand)` guards against div-by-zero when network has no consumers — satisfaction is then 1.0 trivially.)

**Consumer interface contract** (applies to all future electric consumers, not just this session):

- Each consumer's tick reads `world.power_satisfaction_at(b.anchor)` → float
- Consumer uses the value to scale its tick-rate or output
- Visual feedback at the consumer's draw site

**Lamp specifics** (this session's only consumer): brightness scales with satisfaction.

- `satisfaction == 0.0`: lamp draws dark gray (off)
- `satisfaction > 0.0`: lamp draws warm yellow with alpha/brightness proportional to satisfaction
- `satisfaction == 1.0`: full brightness + glow halo

**Implication for future sessions**: when Session 4 adds electric processors, each one multiplies its `cycle_ticks(b)` by `1.0 / max(0.1, satisfaction)` (slows down under brownout) and clamps output ratio to satisfaction. Min 0.1 floor avoids div-by-zero / infinite cycles. This is the established contract; future sessions don't get to debate it.

### Q5 — Tick integration: two-pass per-tick power update

Mirrors fluid network's lazy rebuild pattern + adds per-tick supply/demand pass:

1. **On placement/removal**: `mark_power_network_dirty()` set (same shape as `mark_fluid_network_dirty()`).
2. **Pre-tick in `_on_tick`** (before any building ticks):
   - If `_power_network_dirty`: `PowerNetwork.rebuild_topology(world)` — BFS over poles, fill `_pole_component`. Clear `_component_supply` / `_component_demand` / `_component_satisfaction`.
   - Walk generators: each computes `output_active` (water wheel checks water adjacency), accumulate `_component_supply[comp_id] += output_active ? max_output : 0`.
   - Walk consumers: accumulate `_component_demand[comp_id] += demand`.
   - Walk components: `_component_satisfaction[comp_id] = min(1.0, supply / max(1, demand))`.
3. **Generator tick** (`Buildings.tick_one`): water wheel updates `output_active` state (checked in pre-tick). No direct network write.
4. **Consumer tick**: reads `world.power_satisfaction_at(b.anchor)`, updates `state.satisfaction` (drives visual).

Cost: rebuild_topology is O(poles + edges), supply/demand pass is O(generators + consumers + components). Worst case ~200 buildings on a maxed network — well within budget.

**Pre-tick hook**: `grid_world._on_tick` already exists (line 568). Add the `PowerNetwork.update_supply_demand(world)` call there at the top, before the building tick loop.

## 5. Specific buildings

### POWER_POLE (1×1)

```gdscript
Type.POWER_POLE: {
    "name": "Power Pole",
    "swatch_color": Color(0.50, 0.38, 0.25),    # dark wood-brown
    "footprint": Vector2i(1, 1),
    "requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
    "supports_direction": false,
    "player_drainable": false,
    "walkable": true,                            # thin pole, player walks under wires
}
```

- `state = {}` — empty; network membership tracked at `_pole_component` level
- `make(pos) -> Building`: `Building.new(POWER_POLE, pos, {})`
- `tick`: NONE (pole is passive infrastructure, like belt/pipe)
- `draw`: dark wood base + tall pole + small "T" crossarm at top. ~`tile_size * 0.15` wide pole.
- `info_lines`: `Network: #N` + `Capacity: S/D units` + `Satisfaction: P%`

### WATER_WHEEL (2×2)

```gdscript
Type.WATER_WHEEL: {
    "name": "Water Wheel",
    "swatch_color": Color(0.40, 0.55, 0.65),    # wet wood-teal
    "footprint": Vector2i(2, 2),
    "requires_overlay": [Terrain.Overlay.STONE, Terrain.Overlay.PATH],
    "supports_direction": true,                  # wheel faces water direction
    "player_drainable": false,
    "walkable": false,
}
```

- `state = {dir, output_active, wheel_rotation}`
  - `dir: int` — which way the wheel "faces" (water expected on this edge)
  - `output_active: bool` — set per-tick based on water adjacency
  - `wheel_rotation: float` — visual rotation accumulator [0, TAU); advances when active
- `MAX_OUTPUT: int = 10` — constant in `water_wheel.gd`
- `tick(b, world)`:
  - Check if at least one cell of `Buildings.edge_cells(b.type, b.anchor, b.state.dir)` is a `Terrain.Type.WATER` tile
  - Set `output_active` accordingly
  - If active, advance `wheel_rotation += 0.15 * TAU / 20.0` (about 1 full rotation every 6.67 seconds)
- `draw`: 2×2 wooden frame + rotating wheel cel (rotation driven by `wheel_rotation`)
- `info_lines`: `Output: M/M units (water adjacent: yes/no)` + `Network: #N` (or `(no network — not adjacent to a pole)`)

### ELECTRIC_LAMP (1×1)

```gdscript
Type.ELECTRIC_LAMP: {
    "name": "Electric Lamp",
    "swatch_color": Color(0.95, 0.85, 0.45),    # warm yellow
    "footprint": Vector2i(1, 1),
    "requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH, Terrain.Overlay.SOIL_TILLED],
    "supports_direction": false,
    "player_drainable": false,
    "walkable": false,
}
```

- `state = {satisfaction}` — float in [0, 1], updated per-tick
- `DEMAND: int = 1` — constant in `electric_lamp.gd`
- `tick(b, world)`:
  - `b.state.satisfaction = world.power_satisfaction_at(b.anchor)`
- `draw`: 1×1 base + central glow circle. Color = `lerp(Color(0.3, 0.3, 0.3), Color(1.0, 0.9, 0.5), satisfaction)`. Glow halo (larger faded circle) only at `satisfaction > 0.05`.
- `info_lines`: `Demand: D units` + `Network: #N` + `Satisfaction: P% (FULL / BROWNOUT / NO POWER)`

## 6. Module: `scripts/world/power_network.gd`

`class_name PowerNetwork extends RefCounted`. Pure-logic, mirrors Burner shape. All static methods.

```gdscript
# Public API
static func mark_dirty(world) -> void
static func update_supply_demand(world) -> void   # called from grid_world._on_tick pre-pass
static func rebuild_topology(world) -> void       # BFS, called if dirty
static func is_powered_at(world, pos: Vector2i) -> bool       # convenience wrapper
static func power_satisfaction_at(world, pos: Vector2i) -> float  # consumer query
static func network_id_at(world, pos: Vector2i) -> int        # for Q-inspect (-1 if no network)
static func supply_for(world, comp_id: int) -> int
static func demand_for(world, comp_id: int) -> int

# Constants
const POLE_RANGE: int = 5    # Chebyshev tiles
```

Convenience wrappers `is_powered_at` and `power_satisfaction_at` delegate to the world's dict members. `update_supply_demand` is the per-tick orchestrator.

`grid_world.gd` gets thin glue: `mark_power_network_dirty()`, `power_satisfaction_at(pos)` (delegates to PowerNetwork), `is_pole_at(pos)`. Mirrors how grid_world wraps the fluid network.

## 7. Wire rendering — global draw pass in `grid_world._draw`

New helper `_draw_power_wires()` called from `_draw` between the per-building draw loop and the post-pass border/port indicators.

Algorithm:
1. Build set of pole positions (cheap — already in `_pole_component`)
2. For each pole, find in-range poles (5-tile Chebyshev) within the same component
3. For each unique pair (canonical ordering: smaller anchor first), draw a line from pole-top to pole-top
4. Line color: golden `Color(0.85, 0.70, 0.40)` if `_component_satisfaction[comp_id] > 0.0`, dark brown `Color(0.30, 0.22, 0.15)` if no power
5. Line thickness: 2px

Uses lex-sorted iteration for determinism (avoids draw-order flicker between frames).

## 8. UX: Q-inspect info_lines

Already specified per building above. Network ID display uses the dynamic comp_id which can change after rebuild — that's acceptable since IDs are just labels, not stable references. Users see numeric labels like `#0`, `#1`; if they care about a specific network they identify it by topology, not ID.

## 9. Save schema: NO bump (stays v18)

- Append-only enum: POWER_POLE, WATER_WHEEL, ELECTRIC_LAMP at end of `Buildings.Type` enum (gets next 3 ints)
- New state fields default via `.get(field, default)` — old saves work unchanged
- Network maps (`_pole_component`, `_component_supply`, etc.) are NOT serialized — rebuilt on load via dirty flag
- Same precedent as every prior building-type addition (Inserter Arc, Fertilizer Arc, etc.)
- Old saves never contain pole/wheel/lamp types, so no migration path needed

## 10. Tests: dedicated `scripts/tests/test_power_network.gd`

NEW test file (count: 34 → 35 runner-level entries). Mirrors `test_fluid_network.gd` precedent for the fluid arc's foundation file.

Internal sub-cases (1)–(10):

1. **Place single pole** — network created (component id 0), pole's position in `_pole_component`
2. **Two poles in range** — within 5-tile Chebyshev, same component id
3. **Two poles out of range** — 6+ tiles apart, different component ids
4. **Bridge merges networks** — place 3rd pole linking two separate networks, expect single component
5. **Remove pole splits** — remove a bridging pole, expect two components again
6. **Generator joins network** — water wheel adjacent to pole, supply accumulates correctly
7. **Consumer joins network** — lamp adjacent to pole, demand accumulates correctly
8. **Supply sufficient** — wheel (10) > lamp (1), `satisfaction == 1.0`, lamp state.satisfaction == 1.0
9. **Brownout** — supply 1 (one weak generator) vs demand 10 (ten lamps), `satisfaction == 0.1`, lamps all show 0.1
10. **Save round-trip** — place 2 poles + 1 wheel + 1 lamp, save, reload, verify network reconstructed, lamp still receiving power

Sub-cases (8) and (9) explicitly cover the linear satisfaction model — assertion is `abs(satisfaction - expected) < 0.01`. Sub-case (10) confirms save schema correctness without bump.

For sub-cases involving Water Wheel, the test setup must paint terrain with a WATER tile adjacent to the wheel's facing edge (or use `_make_world` variant that includes water near the test coords).

## 11. Touchpoint inventory

| File | Change type |
|---|---|
| `scripts/world/buildings.gd` | Modify — 3 enum entries + 3 DATA entries + 4 dispatch sites (make / tick_one / draw_one / info_lines) |
| `scripts/world/power_pole.gd` | NEW — make/draw + minimal info_lines, no tick |
| `scripts/world/water_wheel.gd` | NEW — make/tick/draw/info_lines + water-adjacency check |
| `scripts/world/electric_lamp.gd` | NEW — make/tick/draw/info_lines |
| `scripts/world/power_network.gd` | NEW — pure-logic module (BFS, supply/demand, queries) |
| `scripts/world/grid_world.gd` | Modify — new dict members + `mark_power_network_dirty()` + pre-tick orchestrator call + `_draw_power_wires` |
| `scripts/ui/hotbar.gd` | Modify — append "Power" category with 3 slots |
| `scripts/tests/test_power_network.gd` | NEW — 10 internal sub-cases |
| `scripts/tests/test_runner.gd` | Modify — append new test file to TESTS array |

**5 new files, 4 modified files, save schema unchanged.**

## 12. Implementation order (high-level — detailed task breakdown in plan)

1. **Threshold audit** — assert 34/34 PASS pre-change
2. **Power module + grid_world plumbing** — `power_network.gd` skeleton with constants + grid_world dict members + `mark_dirty` glue. No buildings yet; nothing visible.
3. **Power Pole building** — enum + DATA + `power_pole.gd` (make/draw) + buildings.gd dispatch cases. First test sub-cases (1)(2)(3)(4)(5) become writable.
4. **Water Wheel building** — enum + DATA + `water_wheel.gd` (make/tick/draw/info_lines + water adjacency) + dispatch cases. Test sub-case (6) becomes writable.
5. **Electric Lamp building** — enum + DATA + `electric_lamp.gd` (make/tick/draw/info_lines) + dispatch cases. Test sub-cases (7)(8)(9) become writable.
6. **PowerNetwork tick orchestration** — `update_supply_demand` + grid_world `_on_tick` integration. Test sub-cases (8)(9) pass with linear satisfaction working.
7. **Wire rendering** — `_draw_power_wires` in grid_world. Visual only.
8. **Hotbar Power category** — 3 slots appended.
9. **Test file** — `test_power_network.gd` with all 10 sub-cases, including save round-trip (10).
10. **PAUSE 1: visual smoke** — place poles, see wires; place wheel near water, see active state; place lamp, see brightness scale with brownout.
11. **PAUSE 2: full gameplay** — 5-pole grid, 2 wheels, 5 lamps, disconnect by removing a pole, observe split + half goes dark.
12. **Ship** — PROJECT_LOG entry + NOTES update (Electricity Arc 1 of N + linear-satisfaction contract pinned) + tag + push.

Estimated 12-14 tasks total (foundation arc is larger surface than parametric tier additions).

## 13. Validation criteria at commit

- [ ] All 3 building types placeable from "Power" hotbar category
- [ ] Two poles within 5 tiles auto-connect (wires visible between them)
- [ ] Two poles 6+ tiles apart do NOT connect (no wire)
- [ ] Water wheel near water shows `output_active = true` (wheel rotates); away from water → idle
- [ ] Lamp adjacent to wheel + pole = bright; lamp on isolated network = dark
- [ ] Brownout test: 1 wheel + 10 lamps → all lamps dim (~10% brightness via linear scaling)
- [ ] Disconnect by removing bridging pole → network splits, downstream lamps go dark
- [ ] Q-inspect on each building type shows network ID + supply/demand/satisfaction correctly
- [ ] Save mid-operation → reload → all 3 building types preserved, network rebuilt correctly
- [ ] 34 → 35 test files passing (new `test_power_network.gd` with 10 sub-cases)
- [ ] Save schema unchanged at v18
- [ ] Tagged `session-electricity-foundation`, pushed to origin

## 14. Out-of-scope reminders (anti-scope-creep)

- **No additional generators** — windmill / steam engine / solar are Session 2
- **No accumulator/battery** — storage is Session 2
- **No electric variants of existing buildings** — Sessions 4+
- **No multi-tier poles** — single 5-tile pole this session
- **No wire-as-item resource** — poles auto-wire by proximity
- **No power switches** — can't manually toggle a network off
- **No fuel-powered generators** — water wheel is sustainable-only this session
- **No power-line rendering polish** — flat lines, no sag, no transparency
- **No animations beyond water wheel rotation** — lamps don't pulse, poles don't sway

## 15. Decision log (for PROJECT_LOG entry at session end)

- **Q1**: Mirror fluid-network pattern (grid_world dirty-flag + dict maps), NOT per-pole state field — code citation at `grid_world.gd:475-565` proves precedent. Design Brief Verification protocol applied.
- **Q2**: 5-tile Chebyshev connection range. Single pole tier for foundation; parametric `RANGE_BY_TYPE` table pattern reserved for Session 3.
- **Q3**: Building-network adjacency via `Buildings.all_edge_cells()` perimeter scan — mirrors `fluid_available_for_building`. Ambiguity (building adjacent to 2 different networks) resolved by lex-first iteration order.
- **Q4**: **Linear satisfaction scaling (user override of my recommendation).** Each network has `satisfaction: float` ∈ [0,1]. Consumers scale throughput/visual. Lamp brightness scales with ratio. **This becomes the consumer interface contract for the entire arc.**
- **Q5**: Pre-tick rebuild pass in `grid_world._on_tick` orchestrates `PowerNetwork.update_supply_demand`. Consumer ticks then query world's satisfaction state.
- **Building specs locked**: Pole 1×1 walkable, Wheel 2×2 facing-direction, Lamp 1×1 with brightness modulation.
- **No schema bump**: append-only enum + `.get()` defaults + network rebuild on load.
- **Test file structure**: NEW dedicated `test_power_network.gd` (mirrors `test_fluid_network.gd` precedent), 10 internal sub-cases, runner-level count 34 → 35.
- **Future arc sessions slot at**: 2 (more generators/storage), 3 (pole tiers), 4+ (electric processors using satisfaction multiplier), 5 (electric inserters — closes Inserter Arc).
