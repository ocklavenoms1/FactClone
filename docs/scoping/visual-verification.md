# Visual verification — design pass

**Status: DESIGN PASS. Nothing here is implemented.**
Written 2026-08-24 after the art probe measured the render-coverage ceiling.

The premise: nothing in 57 suites has ever executed a `_draw()`. That is why the
wire-rendering arc took six iterations and why every PAUSE gate routes through a
human's eyes. This document re-scopes the visual-verification work against what
the probe actually established.

---

## The ceiling is not what I said it was

I recorded it as "no `CanvasItem` can receive `NOTIFICATION_DRAW` during a
headless run". **That is wrong, and I measured it wrong by not testing it.**

Probe: a scratch Godot project (outside this repo) with a `Node2D` whose `_draw()`
increments a counter, run under `--headless`:

```
PROBE: headless=headless
PROBE: draw_calls before any frame = 0
PROBE: after 1 process_frame, draw_calls = 1
PROBE: after 3 process_frames, draw_calls = 2
PROBE: viewport image = null
```

So the ceiling splits cleanly in two:

- **`_draw()` DOES execute headless**, provided something yields a frame
  (`await get_tree().process_frame`). The draw *code path* is reachable.
- **Pixels do NOT exist headless.** `get_viewport().get_texture().get_image()`
  returns **null**. No assertion about rendered output is possible.

The true statement is narrower and more useful: **headless can prove that draw
code ran and which branch it took; it cannot prove what appeared on screen.**

### Why the runner does not do this today

`test_runner.gd:101` is `for test_class in TESTS: var raw = test_class.run(self)` —
synchronous, inside `_ready`. `_ready` *can* be a coroutine in Godot 4, so the loop
could `await`. The obstacle is not structural; it is that awaiting a
non-coroutine emits a warning, and this project treats warnings as errors (see
below), so `await test_class.run(...)` across all 57 existing synchronous suites
would need care. An opt-in second entry point (`run_async`, dispatched only when
`test_class.has_method("run_async")`) sidesteps that without touching 57 files.

### The recording-canvas route is CLOSED, and that is worth knowing

The obvious design — pass `draw_one()` a fake canvas that records calls — does not
compile here. Measured:

```
SCRIPT ERROR: Parse Error: The method "draw_rect()" overrides a method from native
class "CanvasItem". This won't be called by the engine and may not work as
expected. (Warning treated as error.)
```

A `Node2D` subclass cannot shadow `draw_rect`/`draw_texture_rect` under this
project's warnings-as-errors setting. And `Buildings.draw_one(b, canvas: CanvasItem,
…)` types the parameter, so a plain `RefCounted` recorder cannot be substituted
either.

**Do not spend a session discovering this.** Loosening the parameter type purely
for testability is a real option, but it is a production change made for a test,
and it should be a conscious decision rather than a side effect.

---

## Four routes, with what each can and cannot prove

| route | proves | cannot prove | cost |
|---|---|---|---|
| **A. Pure decision functions** — test the data that drives drawing, never the drawing | colour tables, state→string maps, geometry math | that anything is called, or looks right | lowest; needs no engine support at all |
| **B. Frame-yield headless** — `run_async` + `await process_frame` | `_draw()` ran; with instrumentation, which branch | anything about pixels | medium; runner change, opt-in |
| **C. Windowed pixel capture** — off-screen window, `save_png`, compare | actual appearance, regressions, byte-identity | nothing about *why* | medium-high; slower, needs determinism care |
| **D. Loosen the canvas param + recorder** | exact draw calls and arguments | appearance | low once done, but changes production signatures for testability |

**Route A covers more of the scoped work than expected** — see below. Route C is
already proven working in this repo (six byte-identical frames, md5
`4a2f646cf8fe8f65cb987697f5e38fd7`, and a windowed capture with legible HUD text).

Route C has one hard-won caveat recorded from the probe: **the capture harness was
non-deterministic and nearly got away with it.** Warmup counted in *frames* while
`TickSystem` emits at 20 Hz, so tick count during warmup varied with frame rate;
two runs matched twice and the third differed by 70 pixels in exactly the
tick-driven cells (belt chevrons, forge mouth). Any pixel-comparison work must
pause ticks first. A second trap: `add_child` from `_ready` fails **silently**
("Parent node is busy setting up children"), producing a flat grey frame that
hashes identically across runs — a perfect "identical" result meaning nothing.

---

## Re-scoping the five items

### 1. Colour-distance assertion over `BODY_COLOR_BY_TYPE` — **Route A, cheapest, do first**

`inserter.gd:87` holds the table; `:214` is the accessor. This is **pure data**. It
needs no frame, no window, no runner change. The original scoping treated it as
visual work; it is not — it is a table assertion that happens to be about colour.
Assert pairwise perceptual distance exceeds a floor so two tiers can never become
indistinguishable.

Cost: revised **down**. This is an ordinary unit test.

### 2. Assert the "Status: NO POWER" string — **Route A, also cheaper than scoped**

`inserter_panel.gd:122` is `status_text = "Status: NO POWER"` — a plain assignment
in a state→string mapping. Nothing about it requires rendering. The original
framing ("assert the *rendered* string") overstated the problem: assert the mapping,
not the pixels.

Cost: revised **down**. Caveat worth checking during implementation: confirm the
string is not *also* constructed elsewhere, or the test pins one of two copies.

### 3. `--write-movie` boot smoke — **Route C, revised UP in value**

Originally costed as speculative. The probe proved the mechanism: off-screen
windowed capture works, HUD text is legible, and the run completes cleanly.

This is now the **highest-value item in the set**, because it is the only one that
catches whole-game breakage rather than one function's behaviour. A boot that
crashes, fails to wire a scene, or throws during the first frames is exactly the
failure class no unit test in this project can see.

Grep the run for **both** `Parse Error` **and** `SCRIPT ERROR` — and note the
corollary below: a summary line saying "passed" is not sufficient evidence.

Do **not** try to assert on pixel content here. Boot smoke's job is "did the game
come up without errors", not "does it look right".

### 4. Console: `tick_speed` always reports the wrong "was" — **confirmed, trivial**

`console.gd:732-733`:
```gdscript
TickSystem.tick_rate_multiplier = m
return "Tick speed → %.2f× (was %.2fx)." % [m, TickSystem.tick_rate_multiplier]
```
The assignment precedes the format, so **both `%.2f` arguments resolve to `m`** and
the message always reads "→ N× (was N×)". Capture the old value before assigning.
Route A; a one-line fix with a one-line test.

Note the citation drifted: this was recorded as `console.gd:707-708`; the sprite
command pushed it to `:732-733`.

### 5. Console: inverted error classifier — **citation needs re-deriving first**

I could not locate the classifier by grep during this pass. `console.gd:527-531`
(the previously recorded citation) is `_cmd_set_soil`'s bounds/null branch, which
*returns* error strings — so the classifier is likely elsewhere, or the finding
describes the return-convention rather than a classifier. **Re-derive the citation
before scoping this**; do not inherit the line number.

---

## Recommended session shape

**Items 1, 2 and 4 are ordinary unit tests and a one-line fix.** They do not need
the ceiling lifted and should not wait on it. They are Route A entirely.

**Item 3 is the one that changes what this project can verify**, and it is
independent of the runner question.

**The runner question (Route B) is not needed by any of the five items.** That is
the most useful thing this pass establishes: the frame-yield capability is real,
but nothing currently scoped requires it. Open it as its own decision later, when
something actually needs `_draw()` to execute, rather than building it speculatively
alongside work that does not use it.

## Open questions, not decided here

- Should `Buildings.draw_one`'s `canvas` parameter be loosened to allow a recorder
  (Route D)? Production signature changed for testability — a real trade.
- Should the runner gain `run_async` (Route B)? Not needed by items 1-5.
- Item 5's actual location.
