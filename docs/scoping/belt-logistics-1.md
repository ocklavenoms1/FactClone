# Belt Logistics Session 1 — design record

**Status: DESIGN LOCKED 2026-08-26. Implementation in progress (Task 1 dispatched).**
Full evidence in the design-pass transcript; this is the decision record that survives it.
Scope (user-set): SPLITTER + UNDERGROUND BELT pair. No filtering (filters live in the
inserter tier). Belts only; underground pipes are a follow-up.

## Decisions, with the one-line reason

| # | Decision | Why |
|---|---|---|
| Q1 | Splitter is its **own module**, dispatched as a Building in BOTH belt passes — not `Type.BELT`, not a `belt.gd` extension | the MEDIUM_POLE precedent (`buildings.gd:127-145`): same family, own enum value, shared predicate; variant state inside BELT would branch every external caller of `belt.gd:110-157` |
| Q2 | `state["next_out"]` (0/1), `.get()`-defaulted, **resumes** across save/load | `current_tick` round-trips (`save_system.gd:344/:642`), so a reset would be the only tick-relevant state that forgets — and it is literally testable |
| Q3 | All-to-open-side, decided in the splitter's **own Pass 2**; toggle `next_out` **only on successful delivery** | no third pass, no Pass-1 cross-read; the blocked policy falls out of the toggle rule with zero extra state |
| Q4 | The two-pass contract **fits**; the real novelty is the rotatable 2×1 footprint | Pass 2 is the neighbour-read phase (`belt.gd:77-101`); every existing footprint is square and `can_place_building` takes no dir — Task 1 is the enabler |
| Q5 | **Two enum entries** (`UNDERGROUND_BELT_ENTRY`/`_EXIT`) + shared `UNDERGROUND_TYPES` dict, appended after SUBSTATION | entry and exit tick and draw differently — the axis the registry dispatches on; append-only per `buildings.gd:11` |
| Q6 | Pairing is **recomputed per advance tick**, nearest exit within span, matching dir; no stored partner | the power-network precedent transfers whole ("only positions persist"); ~4 dict hits per entry per advance tick (estimate); staleness cannot exist |
| Q6b | Span constant: **own `const UNDERGROUND_MAX_SPAN := 3`, documented-equal to the basic pole's range, pinned by a test literal** | coupling the power table to the belt module means a pole rebalance silently rebalances tunnels — the named silent-compensation shape; prose equalities drift, test literals redden |
| Q7 | Unpaired entry **refuses input** (acts full → upstream jams, visible backpressure); re-pair is automatic by construction | inert-but-accepting is the #19 infinite-sink shape, disqualified by name; destroying the entry destroys tunnel contents, same as a belt's slots — a decision, not an accident |
| Q8 | **Items-in-tunnel** as a slots array (`state["tunnel"]`, length gap×`SLOTS_PER_TILE`) | throughput parity with surface belts is identical *by construction*; rides `b.to_dict()` verbatim; ring-conservation counts it with the same loop. Teleport's delay constant is a free parameter with no source |
| Q9 | Rectangle style; bodies stay strictly inside footprints; the tunnel's dashed pair-indicator lives in a **dedicated pass** beside `_draw_power_wires` | anything spanning tiles in the per-building loop inherits the z-order finding; a dedicated pass has a defined layer |
| Q10 | **No schema bump** — SAVE_VERSION stays 18 | append-only enum + `.get()`-defaulted flat state fields; the #11 malformed-save guards verified not to reject the new fields |
| Latency | **LOCKED (user, 2026-08-26): one belt-tile-equivalent internal lane.** | verbatim reasoning: slot arithmetic stays derivable from existing constants rather than bespoke per test; and zero-latency would be the first exception to a timing model where everything on the belt clock takes time proportional to distance — **exceptions are where throughput bugs hide** |

## Standing constraints this arc inherits

- **R1/#31 is decided**: everything here ticks on the tick clock, gated on `Belt.is_advance_tick()`. No `_process` simulation.
- **#17 is LIVE** and this design neither widens nor decides it: the splitter has no Pass-1 belt interaction. If #17 ever resolves by moving machine↔belt exchanges to Pass 2, the splitter is already on the right side.
- **`belt.gd` gains exactly one Pass-2 branch** (hand into a splitter). Feeding the splitter by Pass-1 pull would be a new #17 instance — refused at design time.
- **`test_tick_loop_wiring.gd`'s header** ("BELT is the only type `post_tick_one` dispatches") goes false the moment SPLITTER joins the pass — **amend it in the same task that falsifies it** (user-mandated; the R5 lesson applied in advance).
- The z-order finding stands; nothing in this arc may enlarge it or quietly fix it.
- The measured handoff trajectory (`0,1,2,4,5,6,8,9,10,11`; front slot never a resting position) must generalise through a splitter — `test_belt.gd`'s pattern extends, and any deviation is a design change to be said out loud.

## PAUSE-gate checklist (accumulating; run at this arc's first visual gate)

1. **R-key rotate on a placed splitter → expect the refusal toast** ("changes shape when
   rotated — remove and re-place it instead"). The in-place-rotate path lives in
   `main.gd` and cannot be tested headless; Task 1 guarded it and this is its only gate.

2. **Broken underground pair stops flow at the entry** — destroy the exit, confirm items
   pile up on the feeding belt (visible backpressure), nothing spills, nothing sinks into
   the entry. The refusal is suite-tested; what the gate confirms is that it READS as a
   jam to a player rather than as a broken machine.

## Session task order

1. **Dir-aware footprints** (the enabler; canary = `test_hover_preview_agreement.gd`, reddening there is signal)
2. Enum + DATA rows (+ `UNDERGROUND_TYPES`)
3. Splitter core (round-robin lane; RED literals derived from existing constants — legal now the lane is locked)
4. Splitter jam/ring + the wiring-header amendment
5. Underground core (pairing scan, tunnel, refuse-when-unpaired)
6. Save round-trip + drawing

Per-task duties: RED first, every mutation echoed from disk, line endings byte-checked,
expectations as literals never computed by the module under test, path assertions with at
least one case whose expected value differs under rotation.
