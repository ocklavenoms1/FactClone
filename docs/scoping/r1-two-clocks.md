# R1 — Two clocks: `_process` delta vs `TickSystem`

**Status: OPEN SCOPING QUESTION. Do not fix in passing.**
**This scopes audit finding #31** (LIVE — MEDIUM), not a new defect.

Re-derived 2026-08-23 during the audit re-application session while reviewing
the finding-#7 fix, and filed as "R1, newly found" before anyone noticed #31
already said it — in the document whose whole purpose is catching that. The R1
entry is withdrawn; the filename stays so links resolve. Read #31's entry
alongside this: it carries the original evidence and a fix prescription, and
this document disagrees with one line of it (see "Would any existing test
catch the change?").

This looks like a wrong comment. It is a simulation-determinism decision.

---

## The contradiction

`scripts/systems/tick_system.gd:5-7` states the law:

> Emits `tick` 20 times per second (every 50ms), independent of frame rate.
> This is the *only* clock the simulation should care about. Buildings,
> crops, weather, etc. all advance on tick boundaries — never on \_process.

`scripts/world/grid_world.gd:1182-1191` breaks it three times:

```gdscript
func _process(delta: float) -> void:
	_tick_regrowth(delta)
	_tick_fertilizer_decay(delta)
	_tick_soil_regen(delta)
	queue_redraw()
```

All three take the **raw engine frame delta**. `GridWorld` is the only
non-test subscriber to `TickSystem.tick` (`grid_world.gd:242`), and its
`_on_tick` (`:635`) drives buildings and belts. So the project runs two
clocks side by side, and the doc comment asserts only one exists.

`TickSystem.tick_rate_multiplier` scales only `TickSystem._accumulator`
(`tick_system.gd:42`). The console clamps it to `[0.1, 10.0]`
(`console.gd:39-40`). It therefore has **no effect whatsoever** on soil
regen, fertilizer decay, or resource regrowth.

### Observable consequence

`tick_speed 10` accelerates crops, belts, machines and drills tenfold, and
leaves wasteland grace, soil recovery, fertilizer expiry and tree regrowth
running at real time. A player fast-forwarding to watch a farm deplete gets
depletion at 10× and recovery at 1×, which is not a slower version of the
game — it is a different balance curve.

---

## Which side is wrong

The evidence points at the code, not the comment, on three counts.

**1. The team already built a workaround for the symptom.**
`PROJECT_LOG.md:775` says the `wasteland <x> <y>` console command exists
because it *"bypasses 60-sec grace — required for testing wasteland mechanics
without setting up active planters to keep soil pinned at 0."* That command
would have been unnecessary had `tick_speed 10` worked on grace: the 60-second
wait becomes 6 seconds. A debug command was written to route around a clock
split nobody had named.

**2. The law is stated as law, not as description.** `CONVENTIONS.md` carries
tick determinism as project law, and `tick_system.gd`'s wording is
prescriptive — "the *only* clock the simulation should care about", "never on
`_process`". Comments that describe get corrected; comments that legislate get
enforced. Nothing in the repo records a decision to exempt the soil systems.

**3. The split silently weakened the #7 fix.** The sub-frame tie recorded at
`841fe3f` — a rescue landing on the tick grace expires loses by up to one frame
delta — exists because grace advances on a variable-width frame delta. On a
fixed 0.05 s tick the window is a known constant instead of a function of the
player's frame rate. Under `_process`, a single engine hitch long enough to
exhaust remaining grace scars a tile in one call; `TickSystem`'s accumulator
loop would instead deliver that same elapsed time as a burst of fixed 0.05 s
ticks, which the grace logic handles correctly. **Moving to ticks closes that
hole as a side effect** rather than needing its own guard.

The counter-argument deserves stating fairly: wall-clock behaviour is
*currently correct* at `tick_rate_multiplier == 1.0`. Summed frame deltas equal
elapsed real time, so a 60-second grace expires after 60 real seconds at any
frame rate. Nothing is visibly broken in normal play. This is a latent
correctness and consistency defect, not a live gameplay bug — which is exactly
why it needs a decision rather than a hotfix.

---

## What breaks if the three systems move onto ticks

Concrete, in rough order of risk.

**Rate arithmetic must be re-derived, not re-typed.** Each system would take
`TICK_INTERVAL_SEC` (0.05) instead of a frame delta. At 60 fps the call
frequency drops from 60/s to 20/s and the per-call delta triples. The
*products* are equal, so `SECONDS_PER_SOIL_POINT`, `WASTELAND_GRACE_SEC` and
the fertilizer durations keep their meanings — but every accumulator that
truncates (`int(prog)` in `_tick_soil_regen`) changes its rounding granularity.
Worth measuring, not assuming.

**Ordering becomes load-bearing in a new place.** `_process` currently
guarantees fertilizer decay runs before soil regen, and the comment at
`grid_world.gd:1184-1188` explains why: otherwise a boost-expired tile fires
one last boosted regen. Moving into `_on_tick` means that ordering has to be
re-established relative to the building/belt two-pass tick, which has its own
documented ordering law. This is the highest-risk part of the change.

**`tick_speed` becomes genuinely global** — the point of the change, and also a
balance change. Anyone who has tuned against the current split behaviour is
tuning against a bug, but they may still have tuned against it.

**Pause would start applying.** `TickSystem.paused` gates tick emission, so
soil regen and fertilizer decay would freeze with everything else. Note: nothing
in `scripts/` outside tests ever sets `paused` — it has **zero non-test
writers**, so this is theoretical today. That dead field is worth its own small
finding.

**Save/load is unaffected.** `decay_remaining` is persisted in seconds
(clock-agnostic) and `tile_regen_progress` is deliberately not serialized
(design Q5), so neither representation assumes a clock.

**Cost goes down, not up.** Three sparse-dict walks per frame become three per
tick — a 3× reduction at 60 fps. Findings #30/#32 (per-frame rebuild costs)
would partly close as a side effect.

---

## Would any existing test catch the change?

**No. Not one.** This is the strongest argument that the decision needs a plan
rather than an edit.

Every soil-arc test drives the private method directly with a hand-supplied
delta — `world._tick_soil_regen(1.0)`, `world._tick_soil_regen(0.1)`, and so on
throughout `test_wasteland.gd` (`:49, :59, :69, :75, :90, :256, :268, :304,
:315, :353, :356, :386, :452-455, :477-479` …), and the same pattern in
`test_soil_exhaustion.gd` and `test_fertilizer_chain.gd`. The tests bypass
`_process` **and** `TickSystem` entirely.

The consequence is stark: all 44 soil-arc sub-suites would stay green through a
migration that changed the game's behaviour, because they would keep calling the
same private method with the same deltas they always did. The suite pins the
*function*, not the *wiring*. Whichever way this is decided, the first work item
is a test that exercises the wiring — drive `TickSystem.tick`, assert soil
actually moved — because today nothing does.

That gap also means the current split is untested in both directions: no test
asserts soil regen *does* respond to `tick_speed`, and none asserts it *doesn't*.

---

## The decision to make

Four options, in the order I would defend them (the fourth is finding #31's own):

1. **Move the three systems onto `TickSystem`.** Honours the stated law, makes
   `tick_speed` global, closes the oversized-delta hole, reduces per-frame cost.
   Costs: re-derive the rate arithmetic, re-establish ordering against the
   two-pass building tick, and accept a real balance change under fast-forward.
2. **Amend the law to name two clocks deliberately** — tick clock for discrete
   simulation, real-time clock for continuous environmental processes — and say
   why, in `tick_system.gd` and `CONVENTIONS.md`. Cheapest, and defensible:
   "soil recovers in real time" is a coherent design stance. Costs: `tick_speed`
   stays a partial fast-forward forever, and the `wasteland` debug command stays
   load-bearing.
3. **Move them onto ticks but exempt them from `tick_rate_multiplier`.** Gets
   frame-rate independence without the balance change. Probably the worst of the
   three — it keeps two clocks while looking like one, which is how this defect
   arose.
4. **Finding #31's own variant of option 1: run them every N ticks rather than
   every tick**, with `dt = N * TICK_INTERVAL_SEC`. #31 proposes N=20 (a 1 s
   cadence), reasoning that soil granularity is 30 s per point so the coarser
   step is invisible and cheapest. Worth costing against plain option 1 — it cuts
   the sparse-dict walks another 20×, but it also makes the grace timer's
   resolution 1 s, which interacts with the sub-frame tie recorded at `841fe3f`
   and with the `grace_admits_tier` threshold shipped at `e47b6a2`. Neither is
   obviously broken by it; neither has been checked.

Not decided here. Option 2 is a legitimate design answer and this document does
not assume otherwise; it argues only that the current state — a law the code
breaks in three places, with no test on either side — is not one of the options.

Note that #31's fix text picks option 1 (or 4) outright and treats the doc
comment as correct by default. That is a reasonable default, but it is a choice,
and #31 does not present it as one.
