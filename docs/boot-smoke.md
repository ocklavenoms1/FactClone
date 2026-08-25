# Boot smoke — the ritual

**Status: implemented and running.** Script: `tools/boot_smoke.ps1`.

The one check in this repo that exercises the **whole game** rather than one
function. Every one of the 60 suites reaches its subject by calling it directly;
none of them boots `main.tscn`, wires a scene, or executes a frame. A boot that
crashes, fails to wire a node, or throws during the first frames is exactly the
failure class no unit test here can see.

---

## The command

```
powershell -ExecutionPolicy Bypass -File tools\boot_smoke.ps1
```

which runs, verbatim:

```
tools\Godot_v4.6.3-stable_win64_console.exe --path <repo> --position 6000,6000 --fixed-fps 60 --quit-after 120
```

Optional: `-Frames <n>` to change the frame count, `-LogPath <path>` to keep the
log somewhere specific, `-KeepLog` to print the log on a pass as well as a fail.

### Why each flag

| flag | why |
|---|---|
| `--position 6000,6000` | The window opens off-screen. A **real window is required** — the dummy rasterizer under `--headless` renders nothing. |
| `--fixed-fps 60` | Pins `delta` to 1/60 and drops real-time sync, so the run is fast *and* deterministic in tick count. See trap 1. |
| `--quit-after 120` | 120 frames = 2.00 s of simulated time = exactly 40 `TickSystem` ticks. Exits cleanly. |

**⚠ `--write-movie` hard-crashes under `--headless`** (dummy rasterizer, signal
11). Never combine them. This ritual does not use `--write-movie` at all; frame
capture is a separate concern and boot smoke does not need it.

---

## Pass criteria — all five must hold

1. **Process exit code is 0.**
2. **The log contains the engine banner** (`Godot Engine v…`).
3. **Zero lines match `Parse Error`.**
4. **Zero lines match `SCRIPT ERROR`.**
5. **Zero lines match `ERROR`.**

`WARNING` lines are counted and printed but do **not** fail the run.

Matching is PowerShell `-like`, which is **case-insensitive**. That is deliberate
— it catches both `Parse Error:` and the engine's own lower-case `"Parse error"`
in `Failed to load script … with error "Parse error"` — but it means the counts
this script prints can be higher than `grep -c` on the same log. Do not read a
mismatch as a bug.

### Why criterion 1 is the weakest one, and cannot stand alone

**Measured, not assumed.** `--quit-after` exits **0** in all three failure modes
below, including the one where the game's entire main script failed to load:

| induced fault | exit | `Parse Error` | `SCRIPT ERROR` | `ERROR` |
|---|---|---|---|---|
| clean | 0 | 0 | 0 | 0 |
| syntax error in `main.gd` | **0** | 2 | 1 | 2 |
| `grid_world.no_such_method_at_all()` in `main.gd:_ready` | **0** | 0 | 1 | 1 |
| `get_parent().add_child(…)` from `main.gd:_ready` | **0** | 0 | **0** | **1** |

In the second row `main.gd` never loaded at all and the process still reported
success. **The greps are doing all the work.** A boot-smoke script that checked
only the exit code would be a green light wired to nothing.

### Why criterion 5 exists, when the scoping doc only asked for 3 and 4

Look at the last row. `add_child` from `_ready` fails with

```
ERROR: Parent node is busy setting up children, `add_child()` failed.
```

which is **neither** a `Parse Error` **nor** a `SCRIPT ERROR`. Exit code 0.
Under the originally-scoped three criteria that run **passes**, with a node
silently missing from the scene. Criterion 5 is the one that catches it, and it
was added after reproducing the fault rather than after reasoning about it.

Cost of criterion 5: it is broad, so a run that legitimately logs an `ERROR:`
line will fail. That is the intended trade. If a legitimate one ever appears,
fix it or narrow the criterion *with the specific string*, and record why here —
do not widen the tolerance.

---

## The two traps, and how this ritual is built around them

Both were recorded during the art probe. Both produced **false confidence**
before they were caught, which is why they are named rather than assumed away.

### Trap 1 — warmup counted in frames is non-deterministic

`TickSystem` emits at 20 Hz off wall-clock `delta`, so "run N frames" produces a
tick count that varies with frame rate. The art probe's pixel-capture harness
matched twice and differed the third time by 70 pixels, in exactly the
tick-driven cells (belt chevrons, forge mouth).

**How this ritual handles it:** `--fixed-fps 60` makes `delta` exactly 1/60
every frame and drops real-time synchronisation, so 120 frames is exactly 2.00 s
of simulated time and exactly 40 ticks on any machine. Ticks are **not** paused
— boot smoke *wants* the tick path exercised, and pinning the fps gets
determinism without giving that up.

**Note this ritual does not strictly need determinism**, because it asserts on
error lines and not on pixels or counts. Fixing the fps is cheap insurance
against a future criterion that does need it, and it makes the run faster.

### Trap 2 — `add_child` from `_ready` fails silently

The art probe hit this and got a flat grey frame that hashed **identically** on
every run — a perfect "identical result" meaning nothing. Any check based on
"did two runs agree" would have passed.

**How this ritual handles it:** it does not compare frames at all, and criterion
5 catches the engine's `ERROR:` line directly. Reproduced above, in the table.

---

## What boot smoke does NOT do

**It does not assert on pixel content.** It answers "did the game come up
without errors", not "does it look right". There is no screenshot, no hash, no
comparison. Adding one would import trap 1 and trap 2 wholesale, and the
scoping pass (`docs/scoping/visual-verification.md`, route C) already records
what that costs.

**It is not a suite entry, and cannot be.** `test_runner.gd` calls every suite
synchronously inside `_ready`, with no window and no frame yield. Boot smoke
needs a real window and a real main loop. Registering it would mean either a
second runner or the `run_async` change that route B scopes and nothing
currently needs.

**It does not replace the headless suite.** They see different things: the suite
sees behaviour with no renderer, boot smoke sees wiring with no assertions.

---

## When to run it

- Before any commit that touches `scenes/main.tscn`, `scripts/main.gd`, an
  autoload, or a `@onready` wiring path.
- After adding a `class_name`, since the class cache and the game's own load
  order are not the same thing the headless runner exercises.
- Any time the headless suite is green and the change felt like it should have
  been riskier than that.

## Literal output of a passing run

```
BOOT SMOKE: C:\Users\ockla\FACTCLONE\tools\Godot_v4.6.3-stable_win64_console.exe --path C:\Users\ockla\FACTCLONE --position 6000,6000 --fixed-fps 60 --quit-after 120
BOOT SMOKE: log -> C:\Users\ockla\AppData\Local\Temp\factclone_boot_smoke.log

  exit code      : 0
  engine banner  : 1
  Parse Error    : 0
  SCRIPT ERROR   : 0
  ERROR          : 0
  WARNING        : 0   (reported, not a failure - see docs/boot-smoke.md)

BOOT SMOKE: PASS (120 frames)
```
