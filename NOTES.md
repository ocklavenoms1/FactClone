# Stewardship — design notes

Forward-looking design plans that aren't yet implemented. Each entry should answer: what's the goal, what hooks exist today, what blocks it, what's the target session.

**Lifecycle:** delete an entry once nothing in it is still forward-looking. `PROJECT_LOG.md`
and git history are this project's shipped-work record. **There is no `CHANGELOG.md` and one
should not be created** — this line named one from the file's first commit to 2026-08-25, and
`git log --all --diff-filter=A -- '**/CHANGELOG*'` returns nothing: the destination half of
the rule was never reachable, so "move it" always meant "leave it here" (audit #35).

**Delete the entry, not the section it sits in.** Shipped sections here carry live tails, and
a blanket delete-on-ship loses them silently — the `console.gd` split trigger under "Dev
Console" (audit **#34**, still owed) and the `MIGRATIONS` per-file split under
"Schema-mismatch UX" are both live triggers inside sections marked SHIPPED. Extract the tail
into its own entry first, then delete the rest.

**Why this is worth enforcing rather than restating:** a retained SHIPPED narrative keeps its
numbers, and its numbers are written in the present tense. Audit findings **#80** (Dev
Console), **#81** and **#82** (both in "Building Interaction UI — multi-session arc COMPLETE")
are all stale counts sitting inside sections marked SHIPPED / COMPLETE. That is not a
coincidence about those three sections; it is the failure mode this rule exists to prevent,
measured. Sections are named rather than cited by line here on purpose — a rule against stale
facts should not carry two line numbers that go stale on the next insert.

---

## ⚠ `audit-hardening-stale-base` IS NOT A DEAD ARCHIVE — DO NOT DELETE

**A prior session characterized this branch as "safe to delete whenever." That was wrong.**
It is the **only copy** of the fixes for a set of audit findings that are **still live on main**.

Discovered 2026-08-21 during Electricity Session 3 Task 1, when a code reviewer noticed in
passing that `save_system.gd` repopulates `grid_world.buildings` on load without marking
either network cache dirty. That is audit finding **#1** (HIGH), described verbatim in
`docs/audits/2026-07-19-flaw-review.md:55` — including the detail that
`mark_fluid_network_dirty()` "is never called anywhere in the codebase."

**#1 itself is now CLOSED on main** — `SaveSystem.load_game` calls both
`mark_power_network_dirty()` and `mark_fluid_network_dirty()` at the end of its world-mutation
section, covered by `scripts/tests/test_load_network_invalidation.gd`
(Electricity Session 3 Task 5b). It was fixed here, not merged from the branch below, because
Task 5 added `world._pole_cells` — a second cache on the same lifecycle — and shipping that
into a known-live invalidation hole would have widened the finding. **The rest of the branch is
still unapplied**, which is the whole point of this entry.

The other fixes exist. They are not on main:

```
git merge-base --is-ancestor 497b5ce HEAD   ->  NO
git branch --contains 497b5ce               ->  audit-hardening-stale-base only
```

**Eight hardening commits never reached main:**

| commit | findings it fixed |
|---|---|
| `2014b60` hardening-6: bounded perf | #29, #32, #72, #73, #74 |
| `be80226` hardening-5: test-debt | #25, #26, #28, #63, #69 |
| `c5b5921` doc sweep | #34-36, #41/#44, #43, #67-68, #76-84 |
| `ce4058a` hardening-4: placement guards | #10, #16 |
| `50ecc12` hotfix | OS.alert out of SaveSystem |
| `3e76e19` hardening-3: soil-arc | #4, #5, #7, #47, #51 |
| `497b5ce` hardening-2: load correctness | #1, #11, #12, #13, #21 |
| `653f5a2` hardening-1: item conservation | #2/#6, #3, #8, #9, #19 |

**How this happened:** the 2026-07 audit ran against a stale clone (94 commits behind real
trunk). The fixes were written against that stale code. We reset to real main, re-verified
the ten HIGH findings as still-live, and went to feature work — and the branch was then
mentally filed as superseded. It is not superseded; it is *unapplied*.

### Which findings are actually closed on main is UNKNOWN

Confirmed closed on main, re-fixed in later sessions:
- **#1** — load_game not invalidating the network caches (`session-electricity-pole-tiers` Task 5b, `scripts/tests/test_load_network_invalidation.gd`). Fixed on main directly, NOT cherry-picked.
- **#2 / #6** — mid-swing fuel outage destroying the held item (`session-inserter-electric`, `37ff498`)
- **#8 / #9** — shared-buffer slot rendering (the diagnostic reframed it, then the resolver landed)
- **#10** — placement terrain guards (`test_placement_terrain_guards.gd` is on main)

Everything else in the table above has **no verified status**.

### The re-application session (queued)

**Its FIRST task is a status table, before any fixing.** For every finding in those eight
commits: is it still reproducible on current main? Do not cherry-pick — each fix was written
against a stale clone and must be re-verified against current code first. Two precedents for
why: the **#8/#9** pass found the finding was real but *the wrong shape*, and **#10**'s blast
radius had **grown** since the audit was written.

Immediate priority is the load-correctness cluster, because those are the ones with a
confirmed-live HIGH: **#11** save-field shape validation, **#12** atomic save write,
**#13** vision/map refresh after quick-load, **#21** load-failure fallthrough overwriting a
recoverable save. (**#1** is already closed — see above. It was the one member of this cluster
that a feature session happened to be standing on top of.)

---

## Working protocol: git commits with a concurrent pipeline — ALWAYS use an explicit pathspec

**Never use bare `git commit` or `git commit --amend` in this repo.** Always name the paths:

```
git commit -F - -- scripts/world/foo.gd scripts/tests/test_foo.gd
```

`--amend` and bare `commit` commit **the whole index**, regardless of what you staged. The
`art/` Blender pipeline runs as a **separate concurrent session** that stages its own work into
the same index, so files can appear there between your `git status` check and your commit.

**Triggered by:** Electricity Session 3 Task 1 (2026-08-21). An implementer ran `--amend` and
swallowed **65 `art/` files** into a script-only commit (69 files, +2644/−1497). Repaired with
`git reset --mixed <prev>`, which moves HEAD and the index but **never touches the working
tree** — so nothing was lost. Note the one real consequence: the reset **cleared the index**, so
any deliberate staging by the concurrent session was discarded (content intact, `git add` may
need repeating).

**Rule is permanent, not session-scoped.** Verify after every commit with
`git show --name-only --format="" HEAD`.

### The other half: NEVER LEAVE THE INDEX DIRTY

The pathspec rule above only protects *your own* commits. It does nothing about the reverse
direction — **a bare `git commit` from the OTHER session absorbs whatever you have staged.**

**Triggered by:** Electricity Session 3 Task 9 review (2026-08-22), the third incident of this
class. A reviewer ran `git checkout b1a8c4c^ -- scripts/tests/test_runner.gd` to simulate a
pre-commit tree. That command **stages**. While it sat in the index, the art session's bare
commit `e3b0bb4` swept it up and deleted

```gdscript
	preload("res://scripts/tests/test_mixed_tier_save_roundtrip.gd"),
```

from `test_runner.gd`. **HEAD silently stopped registering a test file.** A clean checkout
would have run 45 tests and reported green while the save-round-trip coverage did not execute
at all — the worst possible failure shape, since a missing test looks exactly like a passing one.

**Rule: no session may leave the index dirty, even briefly.** For reading a file at another
revision use `git show <ref>:<path> > /tmp/scratch`, or a `git worktree`. **Never** use an
index-touching command — `git checkout <ref> -- <path>`, `git restore --staged`, `git add` —
without committing in the same breath.

**Detection:** after any task that adds a test file, confirm the registration survived:
`git show HEAD:scripts/tests/test_runner.gd | grep -c <new_test>`. A dropped registration
does not redden anything.

---

## Working protocol: worktree absolute paths

When a session runs in a git worktree (CWD = `.claude/worktrees/<branch>/`), Write/Edit tools follow file paths **literally**. Passing a main-repo absolute path (e.g., `C:\Users\elham\facvtorio\docs\...`) writes to the **main repo**, not the worktree — and the cross-repo write is hard to detect because `git status` of the worktree shows clean (the file landed somewhere the worktree's index can't see).

**Rule:** in a worktree session, always use the worktree's absolute path (e.g., `C:\Users\elham\facvtorio\.claude\worktrees\<branch>\docs\...`) or relative paths from CWD. Verify with `pwd` before any Write/Edit if uncertain.

**Triggered by:** `session-qol-cluster-a` planning phase. The design spec landed in the main repo at `C:\Users\elham\facvtorio\docs\superpowers\specs\...` while the worktree was at `C:\Users\elham\facvtorio\.claude\worktrees\silly-bardeen-3279e9\`. Recovered by `mv` + re-commit; cost was ~3 minutes, but the next instance might land deeper into a session before being noticed.

**Related — Windows shell redirect caveat:** when subagents run Bash on Windows, **avoid `2>nul`** for stderr redirection — Windows Bash interop creates a literal file named `nul` in the CWD instead of redirecting to the null device. Use `2>/dev/null` (Git Bash translates this correctly) or skip stderr redirection entirely and inspect exit codes. Triggered during `session-qol-cluster-a` Task 4 fix-up cycle: a `nul` file (110 bytes containing a `git` error) appeared in the worktree, caught at pre-GATE-1 hygiene check.

---

## Code Quality Reviewer Protocol (validated session-qol-cluster-a)

When flagging missing code or omitted lines, quote the exact line(s) by line number from the file. Do not flag omissions based on pattern-matching; verify by reading the file content.

**Empirical impact:** false-positive rate dropped from 50% pre-protocol (3 false positives in 6 reviews) to 0% post-protocol (0 false positives in 9 reviews) across `session-qol-cluster-a`. Apply to all subagent-driven sessions going forward.

**Bake into reviewer subagent briefs:**

> When flagging missing code, omitted lines, or absent assertions, **quote the exact line(s) by line number from the file**. Do NOT flag omissions based on pattern-matching or what you "expect" to see; verify by reading the file content first. If you can't quote the relevant line range showing the omission, do not make the claim.

---

## Opus reviewer behavior — prompt-injection awareness

Across Tasks 13, 15, 18 of `session-qol-cluster-a` (3 data points), Opus reviewer subagents explicitly identified and ignored ambient context that leaked into tool output (system-reminders about MCP instructions, link-safety prompts, etc.). Sonnet did not surface this behavior in 6 reviews. Real model-level provenance reasoning, context-dependent (fires when noise is present, not routine per review). For review work specifically, Opus shows higher resistance to context contamination.

**Practical implication:** when reviewer subagents need to read tool output that may include unrelated system-reminders or MCP instructions (e.g., during multi-step file inspection), Opus is more likely to correctly partition signal from noise. Worth the cost difference for high-stakes reviews of foundational code or signature-changing refactors.

---

## Test fixture leakage into game saves (discovered session-qol-cluster-a)

`scripts/tests/test_save_migration.gd` uses `user://test_save_migration.json` as a fixture path for negative-path tests (writes a v19 "future save" then asserts the v18 game rejects it). The test has pre-cleanup (L108-109) and post-cleanup (L218-219), but if the test process is killed mid-run before reaching post-cleanup (e.g., interrupted Godot test runner, killed during cold-import stall), the file persists.

**Symptom:** game launch shows a "Save incompatible — Save is v19; this game is v18" popup pointing to `test_save_migration.json`. The game's save-load path apparently scans for any `.json` and treats the test fixture as a candidate save.

**Workaround:** delete the file manually OR re-run the full test suite (pre-cleanup at L108 will remove it).

**Proper fix (deferred to future session):** filter the save-load scan in `scripts/systems/save_system.gd` to exclude paths starting with `test_*.json`. ~3-line change. The test fixture shouldn't be visible to the main game's save loader at all. Tag for a brief design pass (does the game's save-load scan SHOULD enumerate user data, or only load explicit slot paths? Likely the latter — fix is even smaller).

---

## Test Layering Strategy (validated session-qol-cluster-a)

- **Helper/utility math:** pure-logic tests in `test_*.gd` files (no panel calls). Examples: `SlotClickHandler.split_half`, `ctrl_click_max`, `ctrl_click_transfer` — all tested via direct calls in `test_slot_click_handler.gd` sub-suites #1, #2-#5, #8, #9, #11a.
- **Dispatcher integration:** integration-tested at manual smoke gates (GATE 1, GATE 2, PAUSE 2). Player exercises the wired path in-game; controller validates against the spec acceptance matrix.
- **Per-kind dispatcher max formulas** (1-2 line expressions, data-shape coupled): covered by integration smoke, **NOT unit-tested**. Examples: chest's `min(cursor.count, Chest.free_capacity(building))`, fuel's `free_units / energy_per`, building input's `min(cursor.count, max_stack - current)`.

**Rationale:** dispatcher formulas wrap pure-logic helpers; helper bugs propagate (caught by helper unit tests); dispatcher bugs are caught at integration smoke when ctrl picker mis-opens or transfers wrong amounts. Adding unit tests for each dispatcher formula would inflate test count without catching bugs the helper tests + smoke don't catch.

**When to deviate:** if a dispatcher formula has non-obvious branching (e.g., the silent-atomic-clamp case for fuel drop in `_drop_into_fuel`), DO write a pure-logic test for the formula itself (see sub-suite #9 for the precedent). The principle is "test the math when the math is hard," not "test every dispatcher line."

---

## Subagent Protocol Gap (discovered session-qol-cluster-a Task 23)

Static-analysis-by-reading catches a lot but doesn't catch "this script doesn't parse against its actual base class." Code reviewers read diffs at Tasks 18-22 without instantiating or `--headless --import` verifying `scripts/ui/quantity_picker_modal.gd` against PopupPanel/Window API. The script called `get_viewport_rect()` — a `CanvasItem` method that does NOT exist on `Window` (PopupPanel's actual base). The bug was LATENT for 5 task cycles: test_runner doesn't load main.gd (only test_*.gd files), so the parse error never triggered during test runs. Game launched fine because `@onready var quantity_picker: QuantityPickerModal` resolved to null when the script failed to parse, and Task 19's defensive `quantity_picker != null` gate silently no-op'd ctrl+click. GATE 2 smoke tested shift only — ctrl was never exercised. Bug was caught only when Task 23 implementer tried to instantiate the picker scene in a sub-suite.

**Future enhancement candidate:** implementer briefs for tasks creating `.gd` files with `extends <UnusualBaseClass>` (anything beyond Node/Control/Reference/RefCounted) should require a `godot --headless --import` verification step before reporting DONE. This catches parse errors against base-class APIs that test_runner doesn't load.

**Cost:** ~1 additional command per qualifying task (~30s). **Benefit:** catch parse-against-base-class bugs at creation rather than at PAUSE/smoke (which is hours or sessions later, with reviewer + integration cycles consumed in between).

**Tangentially:** code-quality reviewer briefs could also request "run `--headless --import` against the new/modified script files to confirm they parse against actual API" as a sanity step. The line-quoting protocol (validated this session) catches false-positive omissions but doesn't catch "this method doesn't exist on the actual base class."

---

## Working protocol: Design Brief Verification (validated session-inserter-long-reach)

Senior dev briefs describe code changes at conceptual level; implementation agents should ALWAYS verify against actual current code shape via code search + line citations before accepting brief assumptions. **Six data points** across Cluster A + Inserter Arc + Electricity Arc + Cluster B:

- **Cluster A Task 14:** refuse-clamp semantic conflation caught by spec re-read before code.
- **Inserter Session 3 Q4:** brief said "modify tick to use REACH lookup"; verification against `inserter.gd:134-190` revealed tick is already accessor-driven. REACH belongs in `source_tile()` / `dest_tile()` accessors, NOT in tick. Tick stays tier-agnostic.
- **Inserter Session 3 Task 6:** brief template contained 5 stale API references (SaveSystem `save_game(world, save_path)` signature — actually `(world, player, inventory)`; state field `current_fuel_item` — actually `last_fuel_item`; LoadResult shape; placement coordinate `(5,5)` outside stone overlay; standalone save path — should reuse `TEST_SAVE_PATH` + `_cleanup` helper). Implementer caught all five by comparing against sub-case (9) precedent + checking actual `save_system.gd` / `burner.gd` signatures.
- **Electricity Foundation Q1:** brief said "per-pole `network_id` field, recompute on changes." Code search at `grid_world.gd:475-565` revealed the codebase precedent is graph + dirty-flag with grid_world-level state maps (no per-instance field). Mirror that exactly. Saves stay flat — only pole positions persist; network rebuilt on load. Controller (planner) wrote the wrong brief; implementer correctly refused to scope-deviate and reported BLOCKED.
- **Electricity Foundation Task 2 (forward references):** original brief had `update_supply_demand` reference `Buildings.Type.WATER_WHEEL` / `ElectricLamp.DEMAND` etc. before those existed. GDScript 4 resolves class_name globals and enum members at PARSE time (not lazily). Implementer caught the parse-error precondition before any commit. Defer forward-referencing functions to the task that introduces their dependencies.
- **Cluster B spec→plan (3 corrections in one pass):** (a) Spec referenced `grid_world.world_pos_to_tile` as "existing helper or similar" — DBV found actual name is `world_to_tile(world_pos: Vector2) -> Vector2i` at `grid_world.gd:230` (already used by main.gd:434). (b) Spec implied SlotWidget could host hover-detection — DBV found it's `extends RefCounted` (render-only); hover must live in slot-owning Controls. (c) NOTES item 9 claimed `test_building_ui_2.gd:122` locked the chest-bug behavior — DBV found line at 127 asserts a DIFFERENT path (drop into empty slot). Plan added a NEW test sub-case rather than flipping a non-existent assertion. **All three caught at plan-writing time before any code touched.**

**Pattern:** brief assumptions about code structure are approximate; verification against current code is cheap and catches imprecision before it propagates. **100% of conceptual errors caught by code-citation verification across 6 incidents.** Bake into all implementer-subagent briefs: "before accepting a brief's description of an existing API or code shape, verify by grep + line citation. If the brief and code disagree, the code wins; flag the discrepancy in your DONE report."

**Corollary:** NOTES line references go stale as code evolves. Always grep for the asserted content rather than trusting a line number from legacy notes. Cluster B item 9 was the canonical example: NOTES authored months earlier cited line 122; the relevant code had moved to 127 AND changed code paths.

---

## Working protocol: Variable name pre-check before multi-edit on shared test files

When appending new sub-cases to a test file's existing `run()` function (where all locals share one scope), grep for variable names you plan to declare BEFORE writing the code. GDScript 4.x rejects same-scope re-declaration as a parse error — and the error doesn't surface clearly when the test process is run via `| tail -N`; the pipe buffers and the runtime appears to hang.

**Triggered by:** `session-inserter-long-reach` Task 2 — implementer subagent stalled at test-verification step (35 tool uses, no final report) because `var fast_b: Building` collided with a prior `var fast_b` declaration in sub-case (2) of the same `run()`. Controller diff-inspected, found the parse error in raw Godot output (no pipe), renamed sub-case 11 locals to `_r` suffix, tests passed.

**Pre-check protocol (now standard in implementer briefs for multi-edit test tasks):**

```bash
grep -n "^\s*var \(<NAME1>\|<NAME2>\|...\)\b" scripts/tests/<target_test>.gd
```

If any match, suffix with the sub-case number (`_11`, `_12`, etc.) for clarity. Tasks 3, 4, 5, 6 of `session-inserter-long-reach` all succeeded without stalling after this pre-check was added to briefs.

**Also bake into reviewer briefs:** when reading test sub-case diffs, verify variable names don't collide with declarations earlier in the same `run()` function — line-quote the prior declaration if found.

---

## Working protocol: Edit-tool CRLF caveat on Windows

Triggered during `session-inserter-long-reach` Task 4. The `Edit` tool refused string-not-found on `scripts/main.gd` despite verified-correct tab indentation in the input. Root cause: CRLF-vs-LF mismatch between the file on disk and the Edit input string (Windows-only). Implementer worked around via PowerShell:

```powershell
[System.IO.File]::WriteAllText(<path>, <content_with_preserved_CRLF>)
```

(Read raw bytes first, confirm CRLF, do string-replace in-memory, write back.) Final on-disk bytes verified by re-reading the edited region.

**Pattern:** if `Edit` fails string-not-found and the search string is byte-identical to what `Read` returned, suspect line-ending mismatch. The harness on Windows can mojibake between LF (what Edit ships) and CRLF (what `git diff` and Godot write). PowerShell direct-write or a normalize-line-endings preprocess step bypasses the issue.

Related to the existing `2>nul` caveat above — both are Windows-specific tooling friction modes worth documenting.

---

## Working protocol: UX iteration trap — require the rule, not the symptom

When iterating on visual / UX feedback features (wire rendering, lamp brightness, hotbar layout, etc.) based on screenshot feedback: **after 2 failed iterations, STOP and require the user to articulate the rule, not describe the symptom.**

**Earned at `session-electricity-foundation` PAUSE 1.** Wire rendering took **5 iterations** before locking the actual mental model:

1. **Mesh** (every in-range pair) → user: "too tangled in clusters" (showed 5 poles → 10 wires)
2. **Nearest-neighbor** → user: "two pairs that should bridge don't" (2×2 layout, mutually-nearest pairs)
3. **Euclidean-nearest** (vs Chebyshev) → user: "wrong neighbor selected on ties" (one wire pick was misleading)
4. **MST (Kruskal)** → user: "these 2 should connect directly" (MST routed through other poles)
5. **Mesh-within-network + POLE_RANGE=3 + supply-radius=1** → PASS

**And it happened again.** `session-electricity-pole-tiers` Task 7 shipped MST — option 4
above — without reading this section, and PAUSE 1 rejected it for the same reason, on the
same four-pole square. The recovery was NOT another symptom iteration: the rule was written
down first (the Gabriel graph, with `<=` and the both-reach guard), the failure modes were
enumerated before any code, and the fix landed in one pass. **That is the protocol working.**
See "Wire rendering: MST was REJECTED TWICE" above for the rule itself.

Each iteration was symptom-driven: "this wire shouldn't exist" / "this wire is missing" — the user described what they saw, not the underlying expectation. Asking 4-option-choice questions failed twice (user dismissed). The 5th iteration succeeded because the user (and the controller) finally agreed to lock option (b) explicitly, then layer two refinements (range and supply area) once option (b)'s flaws surfaced.

**Pattern:** symptom-driven iteration on visual features is a trap. The user can describe what they see and what they don't want, but extracting the rule requires forcing the conversation past the "doesn't this look better?" loop. Concrete tactics:

- **After 2 failures:** propose 3-4 concrete algorithmic rules as multiple-choice with descriptions. Force a single explicit pick before any more code.
- **After 4 failures:** STOP entirely. Don't iterate without the rule even if you have a hypothesis. The hypothesis is wrong (your evidence: it didn't work the last 4 times).
- **Use Factorio (or other reference game) names** for proposed rules when applicable — players know "supply area," "Gabriel graph" is conceptually clear via reference even without the name.

Apply to any future visual-feedback feature: render styles, animation timing, color choices, layout decisions.

---

## Working protocol: Magic-number-in-tests audit pattern

When changing a "magic number" constant in code that has embedded geometry / values in tests, grep for that number across tests FIRST and audit each occurrence. Distinguish (a) hardcoded value being asserted (must update) from (b) coincidental usage (leave alone).

**Earned at `session-electricity-foundation` POLE_RANGE 5→3 reduction.** The change to `power_network.gd:28` was 1 line but cascaded to 5 test sub-case layouts in `test_power_network.gd`:

- Sub-case (2) in-range: `(0,5)` and `(5,5)` at dist 5 — would no longer be in-range with POLE_RANGE=3. Updated to `(3,5)`.
- Sub-case (3) out-of-range: `(0,5)` and `(11,5)` at dist 11 — still out of range. Coincidental; left alone.
- Sub-case (4) bridge merge: 10-tile gap with bridge at midpoint (5 from each end) — bridge no longer reaches either end. Updated to 6-tile gap with bridge at 3 from each end.
- Sub-case (5) split: depended on (4)'s layout. Updated together.
- Sub-case (9) brownout: pole chain at 5-tile spacing `[6, 11, 16, 21, 26]` — broken. Updated to 3-tile spacing `[6, 9, 12, 15, 18]`.
- Sub-case (10) save round-trip: poles at dist 5 — updated to dist 3.

**Pattern (concrete steps):**

1. `grep -n "<OLD_VALUE>\|<MAGIC_NUMBER>" scripts/tests/*.gd`
2. For each match: determine if it's an assertion of the old value (UPDATE) or a coincidental tile/index (LEAVE).
3. After updates, run the full test suite — any failures point to missed occurrences.
4. Note the pattern: simple constant changes can have cascade depth >1. Diff before commit.

---

## Electricity Network Design Decision (asymmetric — earned `session-electricity-foundation`)

Generators require strict cardinal adjacency to pole (physical wiring metaphor).
Consumers require Chebyshev distance ≤ that pole tier's supply radius (supply area metaphor).

**Constants:** the two flat consts `POLE_RANGE = 3` / `SUPPLY_RADIUS = 1` were replaced by per-tier tables at `session-electricity-pole-tiers` Task 4 — `PowerNetwork.POLE_RANGE_BY_TYPE` (basic 3, medium 6, substation 11) and `PowerNetwork.SUPPLY_RADIUS_BY_TYPE` (1, 2, 4), each with a `*_DEFAULT` for lookup misses. The basic pole's row still carries the original numbers, so nothing about the shipped basic-pole behaviour moved.

**Rationale:** matches Factorio convention. Two different concepts:

- **Generator-to-pole** = high-current connection, robust contact required. Code: `PowerNetwork._adjacent_component_id(world, b)` — iterates `Buildings.all_edge_cells()` for 4-directional 1-tile adjacency, filtered on `Buildings.POLE_TYPES` so every tier counts.
- **Consumer-to-pole** = supply area, electromagnetic field metaphor, more forgiving. Code: `PowerNetwork._supply_component_id(world, b)` — iterates b's full footprint and hands each cell to `_covering_component_id`, which is also what `power_satisfaction_at` calls, so the two consumer paths cannot disagree. That resolver scans a box sized to `max_supply_radius()` (the widest tier), then filters each candidate against its OWN radius, and measures distance to the matched **footprint cell** via `world._pole_cells` — so the 2×2 substation covers `anchor-4 .. anchor+1+4`, ten cells per axis, rather than a 9×9 hung off its anchor.

**Forward implications for future sessions:**

- **Future electric processors (Sessions 5+: electric smelter, drill, inserter) are CONSUMERS** — they use supply-area rule. Their tick reads `world.power_satisfaction_at(b.anchor)` and applies the arc-wide cycle-multiplier `1.0 / max(0.1, satisfaction)`.
- **Future generators (windmill, steam engine, solar) use strict adjacency** — same as water wheel. Their tick computes `output_active` based on their condition (wind direction, fuel level, daylight, etc.) and pre-tick supply pass sums them into the network's supply pool.
- **Pole tier expansion (Session 3 candidate)** would add `RANGE_BY_TYPE` and/or `SUPPLY_RADIUS_BY_TYPE` parametric tables — medium pole has wider connection range AND larger supply area; substation even larger.

---

## Queued: extract `RigSupport` — the third rig has now landed, and it is the trigger

`electric_rig.gd`, `pole_tier_rig.gd` and `pole_gameplay_rig.gd` each carry their own copy of
two things: a **phase-1 pave loop** (fresh `Tile` + `set_overlay(STONE)`, skipping cells that
already hold a building) and a **phase-2 adopt-or-collide classifier** (walk `plan()`, count
placed / skipped / matched, `adopted = placed == 0 and matched == entries.size()`, hand back
generator anchors either way). `pole_tier_rig.gd`'s header names the refactor — a shared
`RigSupport` with `pave_rect()` and `place_or_adopt()` — and says **a third rig is what should
trigger it**. Session 3 PAUSE 2 shipped that third rig, so the trigger has fired.

**Deferred at PAUSE 2, deliberately, and not for the reason PoleTierRig gave.** Its reason was
"nothing needs it yet"; that is now spent. The remaining reason is scheduling: the extraction
has to touch `electric_rig.gd`, which is Session 3's untouched control — `test_electric_rig.gd`
pins exact satisfaction values with `==` rather than `is_equal_approx` — and restructuring the
one stable reference point in the session at its final gate is the wrong trade. Take it at the
TOP of the next session that opens any rig file, while the suite is green and nothing is gated
on those three modules.

The three plans differ in ways the extraction has to keep: ElectricRig has a source-chest arm
the other two do not, PoleGameplayRig paves **three** rectangles rather than one and keeps one
building (its bridge substation) deliberately outside `plan()`.

---

## Queued: split `test_pole_tiers.gd` — the seam is measured and clean

1800-odd lines, 12 sub-cases across six tasks. Coherent only under "everything Session 3
touched". **Deferred at Session 3's PAUSE 1 re-gate** — moving 700 lines of the session's own
safety net immediately before a visual gate is the wrong trade for a pure refactor. It is one
task away from being a junk drawer, so take it early in whatever session next opens the file.

**Cut AFTER sub-case (10) — i.e. at the (10)/(11) boundary. Sub-cases (11) and (12) move
TOGETHER.** (10) times `power_satisfaction_at` and belongs with the supply-area cases, so it
stays; (12) times `wire_edges` and shares helpers with (11), so it goes.

*(This paragraph first read "cut between (11) and (12) — NOT (10)/(11)", which contradicted
both its own justification and the list below: that list moves `_plain_gabriel_edges`, which
is (11)'s, and `WIRE_*`/`FRAME_US`, which are (12)'s, so both sub-cases move and the boundary
is the one before (11). Corrected at the Task 8 quality review, where the seam was re-verified
by checking that every name below first appears at or after the start of (11).)*

Everything below moves to `test_wire_edges.gd`. Verified to have **zero callers** elsewhere in
the file:

- helpers: `_plain_gabriel_edges`, `_edge_key`, `_same_edge_set`, `_edge_list_str`,
  `_layout_str`, `_check_edges_reachable`, `_check_spans`, `_edges_span_component`,
  `_mesh_pair_count`, `_poles_by_component`, `_edges_by_component`
- constants: `K4_POLES`, `K4_FAR_PAIR`, `K4_SIDES`, `TRIPLE_*`, `SWEEP_*`, `WIRE_*`, `FRAME_US`

Only generic scaffolding is shared — `_check`, `_make_world`, `_teardown`, `_place_all`,
`_component_count`, about 40 lines to duplicate or hoist.

The justification is not size alone: the wire renderer now has its own rule, its own fixture
set, its own budget constant and its own history section in this file. That is a subsystem.

---

## Wire-edge cost: cache the edge list, invalidate from `mark_dirty`

Measured at Electricity Session 3 Tasks 7 and 8, headless console build. `wire_edges` runs
**every frame** from `_draw_power_wires`.

| poles in one component | Gabriel (shipped, Task 8) | MST (Task 7) | the mesh before it |
|---|---|---|---|
| 12 (the rigs) | ~0.2 ms — ~1% of a 60 fps frame | 0.16 ms | — |
| 50 | ~2.5 ms — ~15% | 2.5 ms | — |
| 100 | **~10 ms — ~60%** | **12.5 ms** | **8.3 ms — 50%** |

**The Gabriel column is rounded to one figure on purpose.** Eleven consecutive warm runs
spanned ±20% at every size (165–286 µs, 2273–3347 µs, 9482–12487 µs), a cold run reached
**15.4 ms** at 100 poles, and a second reviewer's machine read 13.2 ms. The MST and mesh
columns are **single** Task 7 readings. Read them as the *same order at every size* — the data
does not support calling either faster, and any tighter number here is noise. This table was
rewritten three times, once per review, chasing digits that were never stable; sub-case (12)
prints the live figure on every run and that is the one to read.

**The quadratic pair scan is INHERITED, not introduced by any of the three.** All of them
have to ask `poles_connected` about every pair to know what the graph *is*; what differs is
what they do afterwards. MST also weighed each accepted pair and rescanned for the cheapest
edge (~1.5× the mesh). Gabriel's blocker filter is `O(E·D)` **only because of the both-reach
guard** — a blocker must be a common neighbour, so the search is one adjacency list rather
than the whole component. Measured on sub-case (12)'s own grids with only the guard neutered,
the unguarded `O(N³)` filter costs **0.23 / 4.0 / 17.1 ms** (the 50-pole figure reached 7.1 ms
on a reviewer's machine, still under sub-case (12)'s 8000 µs gate — the guard is caught on
**correctness** by (11c) and (11d), not on time): past a whole frame at 100 poles,
and the only reading in this table that is unambiguously worse than the MST. So 100 poles on
one network was already unaffordable before Task 7, and still is. Nothing in the suite would
catch a regression here except sub-case (12) — it is a rendering path.

**The fix, when it becomes real: cache `wire_edges`' return on the world and invalidate it
from `mark_power_network_dirty`.** Topology only changes on placement or removal, so a cached
edge list is correct for every frame in between, and it collapses per-frame cost to zero.
Small, well-scoped, no correctness property spent. Reported and deliberately NOT implemented
at Task 7 — measurement precedes optimisation, and the number was not yet worth acting on.

`test_pole_tiers.gd` sub-case (12) gates the **50-pole** figure at 8000 µs and prints all
three on every run. 12 poles would not catch a regression to a cubic formulation (the plan's
original `remaining × in_tree` Prim's measured 0.73 ms at 12 — inside any noise-tolerant
budget — but **340 ms at 100**, twenty frames per frame). 100 would require writing down that
three quarters of a frame is acceptable. **The 8000 µs constant did not move across the
Gabriel rewrite**, which is the point: a budget that has to be relaxed for a visual change was
measuring the wrong thing.

---

## Wire rendering: MST was REJECTED TWICE. What ships is the GABRIEL GRAPH

**Read this before changing wire rendering again. Three rules have now been tried on this
one function, and two of them were rejected at a visual gate.**

| rule | K4 of four basic poles | verdict |
|---|---|---|
| mesh (every in-range pair) | 6 wires | "too tangled in clusters" — Foundation PAUSE 1, iteration 1. Survived to ship only because `POLE_RANGE` was capped at 3; unshippable once the substation carries 11 |
| minimum spanning tree | 3 wires, a **star** | **REJECTED TWICE** — Foundation PAUSE 1 iteration 4 ("these 2 should connect directly") and again at Session 3 PAUSE 1 after Task 7 reintroduced it |
| **Gabriel graph (shipped, Task 8)** | **4 wires, the square's outline** | passed |

**The MST objection is inherent, not tunable.** An MST routes through intermediates. In a
square of four equidistant poles every tie resolves to the lex-first pole, so the tree is a
star out of the north-west corner and the south-east pole reaches across the **diagonal**
rather than to either of the two neighbours it is visually adjacent to. No tie-break fixes
that; a tree of N-1 edges simply cannot draw a closed square.

**Why mesh could not just come back.** At Foundation there was one tier and every pole was
interchangeable, so mesh at range 3 was affordable. Per-tier ranges changed the arithmetic:
a substation at range 11 in a mesh fans out to nearly every pole around it, because
either-reaches forms the link regardless of the small pole's reach. That is iteration 1's
"too tangled" at several times the scale. Reverting to mesh means capping ranges, which costs
the substation its reason to exist.

### The rule that ships

Wire A—B unless a third pole C lies inside the circle with AB as diameter — the **Gabriel
graph**, tested in exact integers on doubled footprint centres as
`|CA|² + |CB|² <= |AB|²`, with **two non-negotiable modifications**:

1. **`<=`, not `<`.** The four-pole square is *exactly degenerate*: for a diagonal both sides
   are 72 in doubled units, so C sits precisely on the circle. Under `<` the diagonals
   survive and Gabriel collapses back into the 6-wire mesh.
2. **A blocker must be reachable from BOTH endpoints.** Not a refinement — load-bearing three
   times over. (a) `<=` alone suppresses every right-angle configuration (Thales) and
   **disconnects real layouts**: plain Gabriel filtered by range can delete the only reachable
   bridge, leaving a pole the BFS calls powered and the renderer draws with no wire at all.
   Minimal case: `SUBSTATION` at (0,0) with basic poles at (-2,1) and (-3,-3) — the pole at
   (-3,-3) renders bare. (b) It is what makes the emitted set provably spanning: weight the
   reachable graph by Euclidean distance and take any MST T; if C suppressed an edge A—B of T
   then `|CA| < |AB|` and `|CB| < |AB|` strictly and both C—A and C—B are reachable, so
   swapping gives a strictly lighter tree — contradiction. No MST edge is ever suppressed.
   (c) It is the performance fix: a blocker must be a common neighbour, so the filter is
   `O(E·D)` rather than `O(N³)`. Measured at 100 poles, same code, guard neutered: 17.1 ms
   unguarded against ~10 ms guarded, with the MST it replaced at 12.5 ms.
   The guarded form is the same order as the tree; the unguarded form is past a whole frame.

**`<=` and the both-reach guard are a package.** Neither ships without the other. This is
stated in `wire_edges`' docstring in the code as well, deliberately, because it is the kind of
thing that becomes tribal knowledge and then gets "simplified" away.

**Geometry point: the footprint centre in DOUBLED integer coordinates** (`Vector2i(2*anchor.x
+ fp.x, 2*anchor.y + fp.y)`). 1×1 poles land on odd coordinates, the 2×2 substation on even
ones, every squared distance is an exact int, and there are **no floats and no epsilon
anywhere**. Not "nearest cell of the footprint" — that makes A's point depend on B, the test
stops being symmetric, and the connectivity proof above collapses.

**What the change actually moved on screen.** Only the K4. The pole-tier rig's mixed-tier bus
comes out with the *identical* five-edge chain under MST and under Gabriel — verified against
the edge lists, not by eye. The east control block is the whole visible diff: a 3-wire star
with a diagonal becomes a closed 4-wire square.

### If the Gabriel graph is ever itself rejected

Nobody has costed this: **mesh-within-network for basic and medium poles, a sparser rule for
substations.** Local clusters keep the look that passed at Foundation; the backbone stops
fanning out. More complex than any pure rule. It implements *"clusters should mesh, backbones
shouldn't"* — so if that is ever the articulated rule, this is the shape it takes.

---

## Supply-scan cost: the memo is the lever, NOT the early return

Measured at Electricity Session 3 Task 6, headless console build (debug checks on, so
these are upper bounds — a release export is faster).

| configuration | µs/call | vs pre-Session-3 |
|---|---|---|
| pre-Session-3 (9-cell box, first hit) | 1.03 | 1.0× |
| 81-cell box, **first hit** | 5.23 | 5.1× |
| **shipped** — 81-cell box, exhaustive | **10.68** | **10.4×** |
| shipped, dense pole field (22 candidates) | 17.50 | 17.0× |

**At the shipped rigs' 24 consumers this is 1.1% of a 50 ms tick** (1.8% worst case), so it
was not worth acting on. It reaches 10% of a tick at ~216 consumers.

### If it ever DOES become real, reach for the memo — not the early return

The tempting fix is restoring `_covering_component_id`'s early return, which is safe today
only because of an invariant documented in its docstring. **Don't.** Two reasons the
measurement settled:

1. **It isn't where the cost is.** On an uncovered probe, where nothing can bail early:
   shipped 8.54 µs, first-hit 8.44 µs, pre-Session-3 1.08 µs. So **~8.4 µs is the bare
   81-cell box walk, which the early return does not touch.** It is a 2.0× saving on a
   10.4× regression, not a rollback of it.
2. **A per-tick memo on the world is BOTH larger and free of correctness cost.** Consumers
   are scanned more than once per tick — 2 per lamp, 3 per powered electric inserter — so
   the rigs' 24 consumers cost **52 scans/tick**. A memo collapses that to **24: a 2.17×
   saving, larger than the early return's 2.0×**, while keeping the exhaustive scan and its
   robustness. `inserter.gd` names this at the double-lookup site. After the memo, a spatial
   index over poles is the next step.

Spending the robustness property on the smaller of two available wins is a bad trade.

### The thing to actually watch is DENSITY, not the absolute number

The exhaustive scan compares every candidate in the box, so its cost scales with **poles per
box** — 10.7 µs at 8 candidates, 17.5 µs at 22 — where a first-hit scan stays nearly flat
(5.23 → 5.77). **The scenario that would change this answer is pole-dense endgame layouts
paired with consumer counts in the hundreds**, not consumer count alone.

`test_pole_tiers.gd` sub-case (10) prints the measured figure on **every** suite run, pass or
fail, with the machine's own empty-loop floor alongside it. So the number surfaces on its own
rather than needing to be remembered — and a red can be divided by the machine's speed
instead of guessed at.

---

## Electricity Arc — 3 of N sessions shipped

**Session 3 (`session-electricity-pole-tiers`) — POLE TIERS.** MEDIUM_POLE (1×1, wire range 6,
supply radius 2) and SUBSTATION (**2×2**, range 11, radius 4). The two flat constants became
`POLE_RANGE_BY_TYPE` / `SUPPLY_RADIUS_BY_TYPE`, and four things came with them:

- **`poles_connected` is the single reachability predicate**, called by both the topology BFS
  and the wire renderer. Never re-derive the rule from a distance check — the dangerous
  divergence (renderer stricter than BFS) leaves poles in one component with no wire and no
  signal anywhere. `_pole_distance` is Chebyshev footprint-to-footprint; the Gabriel blocker
  test is Euclidean-squared on doubled centres. **Two metrics, not interchangeable.**
- **Either-reaches**, `max(range_a, range_b)`. Symmetric, so the BFS stays order-independent.
- **`_pole_cells`** maps every pole footprint cell to its anchor, so 2×2 poles resolve from all
  four cells. Consumer supply is one resolver, `_covering_component_id`, nearest-pole tie-break.
- **Wire rendering is a GABRIEL GRAPH** — see the wire-rendering section above before touching
  it. `<=` and the both-reach guard ship as a package and neither is optional.

**Queued Session 3 "Power Pole Tiers" below is DONE — ignore it.** Sessions 4 (electric
processors) and 5 (electric inserters) were both partly absorbed by the Inserter Arc; re-scope
rather than building as written.

**Density judged, not assumed** (PAUSE 2, hand-inspected): 16 poles across all three tiers draw
**26 wires** — an orthogonal lattice with short diagonals off the substations, no crossings, no
wire passing over a pole. Far sparser than mesh at range 11, modestly denser than MST's `n-1`.
That is the reference point for the next power session; if the "too tangled" complaint returns,
compare against this, not against memory.

**The arc's consumer side is no longer theoretical.** `session-inserter-electric` shipped
ELECTRIC_INSERTER — the first consumer that is not the lamp, and the first to use the
locked cycle-multiplier contract rather than only modulating a colour. It landed from the
*Inserter* arc, which means the queued "Session 5 — Electric Inserters" below is now largely
absorbed; re-scope it rather than building it. Two contracts got their first real exercise:

- **The cycle-multiplier contract survived contact**, with one correction. This section's
  locked form was `1.0 / max(0.1, satisfaction)`; the shipped form is
  `ceil(cycle_ticks / max(POWER_EPSILON, satisfaction))` with `POWER_EPSILON = 0.05`. Same
  shape, different floor — 0.05 was chosen so the epsilon doubles as the STATE_NO_POWER
  cutoff, one constant instead of two that must agree. Future electric processors should
  copy the SHIPPED form, not the line above.
- **Consumer demand must be CONSTANT, not duty-cycled.** `update_supply_demand` runs as a
  pre-pass at the top of `GridWorld._on_tick`, so any activity flag it reads is one tick
  stale — a demand that varies with activity creates an undamped delayed-feedback loop and
  every lamp on the network flickers. This is a topological consequence of the pre-pass, not
  a balance choice, and it binds every future consumer. Validated at PAUSE 2: lamps steady.

**Status:** Sessions 1 (foundation) + 2 (generators + storage) shipped. Linear-satisfaction model locked as arc-wide consumer interface contract. Asymmetric generator-vs-consumer pole rules locked (see "Electricity Network Design Decision" above). `PowerNetwork.update_supply_demand` is now a 3-stage settle (supply → storage decision → satisfaction) — any future storage tier plugs into that, don't special-case it. Future sessions extend.

**Shipped:**

- **Session 1 (`session-electricity-foundation`)** — POWER_POLE (1×1, walkable) + WATER_WHEEL (2×2, requires water adjacency, MAX_OUTPUT=10) + ELECTRIC_LAMP (1×1, DEMAND=1, brightness modulates with satisfaction) + PowerNetwork module (BFS topology + dirty-flag + per-component supply/demand/satisfaction). Wire rendering: mesh-within-network. Hotbar "Power" category. 10-sub-case dedicated test file `test_power_network.gd`. Save schema unchanged at v18.
  - `POLE_RANGE = 3` (pole-to-pole connectivity, Chebyshev)
  - `SUPPLY_RADIUS = 1` (consumer-to-pole, Chebyshev)

- **Session 2 (`session-electricity-2`)** — WINDMILL (2×2, no resource dependency, always active, MAX_OUTPUT=6 — 60% of Water Wheel, traded for placement freedom) + STEAM_GENERATOR (2×2, Burner-powered as the 5th consumer, MAX_OUTPUT=20, 1 fuel unit per 20 ticks, `FUEL_PORT_DIR = Belt.DIR_S`) + ACCUMULATOR (1×1 storage, MAX_CAPACITY=50, ±5/tick). `PowerNetwork.update_supply_demand` refactored to 3 stages so storage can be settled after supply/demand are totalled; `rebuild_topology` clears the intermediate dicts. Accumulator fill-bar visual. Hotbar Power 3 → 6 slots. `test_power_network.gd` sub-cases 16-20. Save v18 unchanged (accumulator `charge` is per-building state).
  - Solar (daylight-dependent) was scoped out of Session 2 and remains unbuilt.

**Queued (re-plan each at session start):**

- **Session 3 — TBD.** Candidates: Solar generator (daylight cycle — needs a day/night system first), medium pole / substation tiers, electric-powered processors (the linear-satisfaction contract already supports throughput scaling; no consumer uses it yet beyond the lamp's brightness).
- **Session 3 — Power Pole Tiers.** Medium pole + substation with wider connection range AND wider supply area. `RANGE_BY_TYPE` + `SUPPLY_RADIUS_BY_TYPE` parametric tables on `power_network.gd`. Reuses BFS — only lookups change.
- **Session 4 — Electric Processors.** Electric variants of smelter, drill. First consumers using the `1.0 / max(0.1, satisfaction)` cycle-multiplier arc-wide contract.
- **Session 5 — Electric Inserters (closes Inserter Arc).** Combines reach + speed + electric power. Reuses Inserter parametric tables. Last session of both arcs.

**Cross-cutting contracts (locked at Session 1):**

- **Consumer interface** — every electric consumer reads `world.power_satisfaction_at(b.anchor)`. Lamps modulate brightness; processors will multiply `cycle_ticks` by `1.0 / max(0.1, satisfaction)`.
- **Network identity** — component IDs are dynamic labels, NOT stable references. Users identify networks by topology, not ID. Don't persist component IDs.
- **Save** — only building positions persist. Network is rebuilt on load via dirty flag. Test `tile_modifications` quirk: save-roundtrip tests must write to BOTH `world.tiles` AND `world.tile_modifications` for terrain (e.g., water tiles), since SaveSystem only persists `tile_modifications`.

---

## Inserter Arc — 4 of 6 sessions shipped

**Status:** Sessions 1 (basic, foundation) + 2 (fast tier + filter, parametric refactor) + 3 (long-reach, parametric extension to orthogonal reach axis) + 4 (electric tier, cross-arc into Electricity) shipped. 2 remaining sessions queued; each adds a tier or capability, none architecturally blocking.

**Session 4 shipped only HALF its scoped content.** It was queued below as "Electric Inserter + multi-filter"; the electric tier shipped, multi-filter did not. The tier reuses the fast tier's single scalar `filter_item_type` verbatim. 3-slot multi-filter is re-queued as its own item — do not assume it exists.

**Shipped:**
- **Session 1 (`session-inserter-foundation`)** — basic 1-tile inserter, fuel-powered via Burner module, 1.0s cycle. Universal source/dest (belt/chest/Processor). Closes the "can't connect chest to building without a belt" hole.
- **Session 2 (`session-inserter-fast-filter`)** — Fast Inserter: 0.5s cycle (twice as fast), single-slot filter (drop-to-set, RMB-clear). Inserter.gd refactored to tier-parametric (`CYCLE_TICKS_BY_TYPE` / `BODY_COLOR_BY_TYPE` Dictionary lookup tables); both basic and fast share `Inserter.tick`. New `'filter'` slot kind in BuildingPanel. Pre-existing Session 1 fuel-port bug caught at PAUSE 1 and fixed (now uses `FUEL_PORT_DIR = Belt.DIR_S`, mirroring Smelter pattern).
- **Session 3 (`session-inserter-long-reach`)** — Long-Reach Inserter: 2-tile reach (orthogonal upgrade axis from speed+filter), 1.5s cycle (slower to balance reach), rust-red color, no filter. NEW `REACH_BY_TYPE` parametric table + `reach(b)` accessor; REFACTORED `ARM_LENGTH` const → `ARM_LENGTH_BY_TYPE` table + `arm_length(b)` accessor. `source_tile()` / `dest_tile()` multiply offset by `reach(b)` — zero tick changes (already accessor-driven). Long-reach arm bumped from initial 1.10 → 2.00 × tile_size at PAUSE 2 smoke gate to physically reach the 2-tile-away tiles. Reuses basic `InserterPanel` (no filter row).

- **Session 4 (`session-inserter-electric`)** — Electric Inserter: 5-tick cycle (0.25s, fastest tier), 1-tile reach, electric cyan, single filter, and **no fuel slot at all**. Four rows added to the existing `*_BY_TYPE` tables plus a NEW `POWER_DEMAND_BY_TYPE` (5 units/tick); `is_electric(b)` is DERIVED from membership in that table, so "draws power" and "is not a burner" cannot drift apart. Brownout is `ceil(cycle_ticks / max(POWER_EPSILON, satisfaction))` with `POWER_EPSILON = 0.05` bounding the worst case at 20× rated. NEW `STATE_NO_POWER = 5` across six sites. Reuses `FastInserterPanel` (opposite dispatch call from long-reach, opposite reason). Closed audit findings #2 and #6 (mid-swing fuel outage destroyed the held item) on the *fuel* tiers as a prerequisite. Save v18 unchanged.

**Queued (re-plan each at session start):**
- **Multi-filter (3 filter slots).** Descoped out of Session 4 and NOT shipped. `filter_item_type` is a scalar on every tier today; multi-filter extends it to an Array of types and touches the filter slot kind in `BuildingPanel`, the picker modal, and `_try_pickup`'s gate. Size it fresh — the Session 4 estimate covered a session that did something else.
- **Session 5 — Long-Reach Fast Inserter / Long-Reach Electric.** Combines reach + speed/power dimensions. Tier-parametric tables make this ~30 lines per variant (validated by Session 3's clean orthogonal-axis addition, and again by Session 4's four-row extension).
- **Session 6 — Stack Inserter (electric).** Picks UP TO 3 items per cycle (or per stack-size config), drops them as a single batch. Throughput scaling for late-game. Fundamentally different from prior tiers' "1 item per cycle" model — needs careful design pass.

**Cluster B candidates surfaced during Session 3:**
- E-key adjacency-scan picks first found building (inserter beats chest when both adjacent). User wants mouse-hover-aware dispatch — "whichever I hover over should open when I click E". Pre-existing pre-Session-3 behavior, deferred to QoL Cluster B / future session.

**Architectural extension cost per future tier:** add 1 row to each `*_BY_TYPE` table in `inserter.gd`, add 1 enum entry + DATA entry + dispatch case in `buildings.gd`, ~85 lines for a specialized panel if needed (most tiers reuse FastInserterPanel). Stack inserter is the exception — needs a different state shape for batch-pickup.

**Cross-cutting:**
- Filter tracking is universal (`filter_item_type` on every inserter type, default -1). Multi-filter (Session 4) extends to an Array of types.
- Burner module is shared across drill / smelter / inserter / fast inserter / future kilns. The FUEL PORT DIRECTION pattern (perpendicular edge, never `-1`) is now documented in the Burner header.
- Click-handling-extraction trigger from this section's "Click-handling duplication" entry is now MET (filter slot's RMB-clear is a panel-specific click semantic). Captured in QoL Polish Session below.

---

## Queued: gate-automation + console fixes (~1-2 hours, scoped `session-inserter-electric`)

Scoped by an investigation into reducing human eye-time at PAUSE gates. The finding that
shaped it: **5 of 10 PAUSE 1/2 checks were already covered** by tests that same session had
committed, so the expensive options (a spec-driven scenario runner, a screenshot pipeline)
would each have added only ~1-2 net checks. This is the cheap residue that closes everything
closeable. Deliberately NOT building the scenario+capture boot scene — revisit that when a
session's gate is pixel-heavy (Electricity Foundation was, and burned five iterations).

- **Colour-distance assertion over `BODY_COLOR_BY_TYPE`** (`inserter.gd:87-92`) with a minimum
  pairwise floor. ~5 lines, no new infrastructure. Covers the objective half of "is the new
  tier distinct". Measured distances today — **the pair to watch is not the obvious one**:

  | RGB dist | pair |
  |---|---|
  | 0.197 | basic bronze vs long-reach rust — **closest overall, pre-existing** |
  | 0.300 | fast blue-grey vs electric cyan — closest involving the new tier |
  | 0.656 | basic bronze vs electric cyan |

  Set the floor below 0.197 or the assertion reds on existing colours. That bronze/rust
  proximity is worth a design look independently.
- **Assert the rendered `"Status: NO POWER"` string** (`inserter_panel.gd:122`). Currently the
  only genuine coverage gap of the ten gate checks: `STATE_NO_POWER` is asserted at state
  level, but nothing asserts the panel actually says so.
- **Boot smoke as a documented ritual** — zero code. Boots the real `main.tscn` with full
  scene-tree and autoload wiring, catching *runtime* boot failures the isolated test harness
  cannot reach, and hands back a readable frame. ~2.5s, off-screen, disturbs nothing:

  ```
  ./tools/Godot_v4.6.3-stable_win64_console.exe --write-movie <scratch>/g.png \
    --quit-after 150 --resolution 1280x720 --position 6000,6000 --path .
  ```

  Grep the output for `Parse Error` **and** `SCRIPT ERROR` per the house rule. Note
  `--write-movie` **hard-crashes under `--headless`** (dummy rasterizer, signal 11) and leaves
  a 0-byte `.wav` behind — do not wrap it in a "did an output file appear?" check.

**Two console bugs found incidentally, both in `scripts/ui/console.gd`:**

- **The error classifier is inverted on the most common rejection.** `:302` tests
  `begins_with("tile (") and find("out of") >= 0`, but the message at six sites is
  `"Tile %s is outside world bounds."` — `"outside"` does not contain `"out of"`, and no other
  clause in the chain matches. **A rejected `place` or `tp` is reported to the user as a
  success.** This is why the console cannot be trusted as a scenario-setup layer.
- **`tick_speed` always reports the wrong "was".** `:707` assigns
  `TickSystem.tick_rate_multiplier = m`, then `:708` reads that same variable back for the
  `(was %.2fx)` half of the message. It always prints the new value. (Same string also mixes
  `×` and ASCII `x`.)

---

## Queued (balance): steam generator fuel buffer is too small to anchor a grid

`Burner.FUEL_BUFFER_CAPACITY` is a single shared constant (16 units) across every Burner
consumer — drill, smelter, the three fuel inserter tiers, and the steam generator. The
generator burns **1 unit/sec** (`CYCLE_TICKS = 20` at 20 TPS), so a full buffer is
**~16 seconds** of runtime, and 4 coal fills it. That is fine for a drill the player tends and
wrong for the building the whole electric grid hangs off — it means hand-feeding a generator
roughly every quarter minute, or committing a belt to it immediately.

Surfaced while building the PAUSE 1 rig, which had to re-assert fuel every frame to keep the
generators lit long enough to observe a brownout — the workaround is the evidence.

**Candidate fix:** a per-building `FUEL_BUFFER_CAPACITY_BY_TYPE` table on `burner.gd`, exactly
the parametric shape the inserter tiers already use (`CYCLE_TICKS_BY_TYPE`, `REACH_BY_TYPE`,
`POWER_DEMAND_BY_TYPE`), with the existing 16 as the lookup-miss default so every current
consumer is unchanged by construction. Note `try_pull_fuel` is the only enforcer of the cap —
nothing clamps `fuel_buffer` on write — so the table must be consulted there. Check the panel's
`Fuel: n / N` display reads the same table, and check whether a bigger buffer needs a save note
(it should not: `fuel_buffer` is an existing int field).

---

## QoL Polish Session — Clusters A+B+C ALL SHIPPED, backlog empty

**Status:** All three clusters shipped. Cluster A (`session-qol-cluster-a`) — click extraction + stack-split + quantity picker. Cluster B (`session-qol-cluster-b`) — item tooltips, filter picker, filter status, E-key hover, chest silent-merge. Cluster C — building-blocks-movement (small post-session fix). Item 8 (close-on-padding) shipped as Cluster A PAUSE 2 fix. **NOTES.md QoL backlog is now empty.** Future polish items go to a new Cluster D / E as they accumulate.

**Items (ordered by architectural dependency, NOT priority):**

1. **Click-handling extraction.** **SHIPPED** (Cluster A — `session-qol-cluster-a`). Static `SlotClickHandler` module at `scripts/ui/slot_click_handler.gd` with `handle_player_slot`, `ctrl_click_max`, `ctrl_click_transfer`, `split_half`. Inline shift/ctrl branches in chest_panel + BuildingPanel dispatchers for per-kind context (Q2 minimal-extraction principle).

2. **Shift+click stack-split (half).** **SHIPPED** (Cluster A). Full matrix per spec §5.1: player-slot silent-clamp on same-type drop, chest refuse-with-toast convention preserved on no-fit, fuel atomic conversion with stranded-units fallback, filter no-op (no toast).

3. **Ctrl+click quantity picker modal.** **SHIPPED** (Cluster A). `QuantityPickerModal extends PopupPanel` at `scripts/ui/quantity_picker_modal.gd`, hard-modal via `popup_exclusive_on_parent`, edge-flip placement, asymmetric fuel labels per direction. Pre-open gate suppresses picker for no-op cells (different-type, full same-type, etc.).

4. **Item hover tooltips with descriptions.** **SHIPPED** (Cluster B — `session-qol-cluster-b`). NEW `TooltipManager extends Control` (single shared widget in `$HUD`, 500ms hover delay, edge-flip placement). `Items.gd` `description` field added to all 27 entries with code-citation-grounded text (~13-17 words each). Slot-owning Controls (inventory_grid + 3 panel types) call `start_hover` / `end_hover` from mouse-motion handlers. `_hover_item_type` placed on `BuildingPanel` base class so all 20+ building panels get hover for free.

5. **Filter dropdown picker (complementing drop-to-set).** **SHIPPED** (Cluster B). NEW `ItemPickerModal extends PopupPanel` cloning QuantityPickerModal pattern. Plain-LMB on fast inserter filter slot with empty cursor opens scrollable list of all 27 items; current filter highlighted in `SlotWidget.BORDER_HOVER`. Drop-to-set preserved as alternate path.

6. **Building-blocks-movement with per-building `walkable` flag.** **SHIPPED** (Cluster C, immediately post-session-inserter-fast-filter). PROJECT_LOG entry "Cluster C — Building-blocks-movement (small post-session fix)" has the details. Walkable: BELT + INSERTER + FAST_INSERTER (thin devices). Blocked: everything else including PIPE (per locked Q4). Player-on-tile placement rejected with toast. 33/33 tests passing.

**One smaller follow-up captured during Session 2 PAUSE 2:**

7. **Filter status diagnostic.** **SHIPPED** (Cluster B). `Inserter.info_lines` appends `Status: IDLE (no items match filter)` when filter set AND source has no matching items. New static helper `_source_has_matching_item` mirrors `_try_pickup`'s TYPE dispatch (BELT/CHEST/Processor) read-only — BELT branch intentionally scans ALL slots (not facing-only) to avoid false-positive flicker during transient flow.

**One follow-up captured during session-qol-cluster-a GATE 1 smoke (since SHIPPED):**

8. **Close-on-padding-click UX.** **SHIPPED** (Cluster A PAUSE 2 fix, commit `7998024`). User escalated from "log for Cluster B" to "fix now" during PAUSE 2 smoke. `_close()` / `close()` calls in inventory_grid.gd / chest_panel.gd / building_panel.gd `_gui_input` slot_idx<0 branches removed. Clicks inside panel padding now no-op; Esc still closes via the unchanged Esc handler path. Migration concern (muscle-memory players) deemed non-issue — solo-dev player can adapt.

**One UX wart captured during session-qol-cluster-a GATE 2 smoke:**

9. **Chest deposit-on-same-type-slot triggers deposit-and-take-back.** **SHIPPED** (Cluster B). 5-line silent-merge branch at `chest_panel.gd` plain-LMB drop logic: when cursor type matches existing view's type, `_bag_add` + `cursor.clear` + return (no swap). DBV during Cluster B planning revealed NOTES item-9's claim that `test_building_ui_2.gd:122` locked the buggy behavior was incorrect — actual line at 127 asserts a DIFFERENT path (drop into empty slot). Plan correctly added NEW test sub-case covering both merge (same type) and swap (different type) rather than flipping a non-existent assertion.

**Architectural notes:**
- ~~Items 1+2+3 form a cluster (click-handling). Land together.~~ **SHIPPED** as Cluster A.
- ~~Items 4+5+7 form a cluster (UI feedback / discoverability). Land together — item 9 (chest swap UX) may bundle in.~~ **SHIPPED** as Cluster B (`session-qol-cluster-b`) along with the E-key item from session-electricity-foundation Cluster B candidate. All 5 items shipped together as planned.
- ~~Item 6 is standalone (player movement / placement).~~ **SHIPPED** as Cluster C.
- ~~Item 8 (close-on-padding)~~ **SHIPPED** as Cluster A PAUSE 2 fix.
- **All QoL backlog items shipped.** Cluster B took ~3 hours (matching estimate). Add new items here as they accumulate from future-session smoke gates.

**Save schema impact:** none across Cluster A or Cluster B (both UI-layer only).

**Cluster A actual:** 13 internal sub-suites added (target: 6-8 — exceeded for thorough ctrl-picker orchestration coverage). Runner pass count 33 → 34 (one new test file: `test_slot_click_handler.gd`).

**Cluster B actual:** 5 items + ~10 sub-cases across 4 test files. Runner pass count 35 → 37 (two new test files: `test_tooltip_manager.gd`, `test_item_picker_modal.gd`; sub-cases also appended to `test_inserter.gd` + `test_building_ui_2.gd`).

---

## Dev Console — SHIPPED (session-dev-console)

**Status:** SHIPPED. Debug-build-only, in-memory history. Manual smoke deferred to first real-use session per session-end decision.

**Commands (14):** `clear`, `deplete_area`, `destroy`, `fertilize`, `give`, `help`, `place`, `seed`, `set_soil`, `sprites`, `tick_speed`, `tile`, `tp`, `wasteland`.

That count and that list are **checked, not decorative**: `scripts/tests/test_console_guards.gd` parses this line out of `NOTES.md` and compares it against `console.gd`'s `_register_commands()`, the same way it already does for `console.gd`'s own header (audit #79). Three copies of one fact existed — the registry, the file header, and this line — and this was the unguarded one. See PROJECT_LOG entry for the full command table + design rationale.

**What this line said before, and why the fix is not just a bigger number** (audit #80): it read "12 commands ... 29/29 tests passing" and named twelve, omitting `sprites` and `wasteland` for two sessions. The `29` was never console coverage — PROJECT_LOG's session entry reads "**Tests: 28 → 29 passing**", i.e. the whole runner's suite count on the day the console shipped. Updating 29 to today's runner figure would have preserved a sentence that misleads about what it counts, so the figure is gone from this status line instead: runner-wide totals live in the audit's baselines block beside the command that produces them, and the console's own suites are `test_console.gd`, `test_console_error_classifier.gd`, `test_console_guards.gd` and `test_console_backtick_toggle.gd`.

**Manual-smoke-at-first-use note:** ✅ **COMPLETED at session-soil-exhaustion-4 PAUSE 1.** First real-use was the wasteland session, exactly as anticipated. Caught 2 real bugs (Bug 1: `tile` command displayed raw enum ints; Bug 2 CRITICAL: Premium Compost hotbar slot was missing — wasteland recovery path unreachable via hand-apply). Both fixed before that session's commit. The "ship tooling without exhaustive UI testing, surface bugs on first real use" pattern paid off — UI bugs surfaced in a low-stakes context (one session's PAUSE) rather than blocking gameplay forever. **Validated this protocol for future tooling sessions.**

**File-size finding:** `console.gd` **shipped at** 657 lines vs the 300–400 design-pass estimate. That is a dated fact about the ship commit, not a description of the file today — see the trigger below for the live figure. Two underestimates:
- **UI layer underestimated** (~80 lines for Godot Control / RichTextLabel / LineEdit setup — anchors, theme overrides, signal wiring, color-bbcode helpers).
- **Command bodies averaged 22 lines, not 10** (validation discipline non-negotiable: 2–4 arg checks + 2–3 error returns + the operation per command).

**SPLIT TRIGGER — FIRED, AND THE SPLIT IS OWED.** If `console.gd` grows beyond ~800 lines (e.g., adding more commands or richer UI), split into `console.gd` (UI + activation) + `console_commands.gd` (parser + command implementations). It did.

**Run `wc -l < scripts/ui/console.gd` rather than reading a number here.** No current figure is pinned in this paragraph on purpose: every session that has touched this file has moved it, and each pinned figure in turn — 657, then 812, then 1068 — went stale inside a cluster or two. At the 2026-08-25 measurement it stood at **1127**, i.e. **327 over** a "~800" trigger, up from 268 over one cluster earlier. It has only ever grown, and it grows whenever this file is touched, which is itself the argument for scheduling the split rather than re-measuring it.

**"Defer the split" is no longer the standing decision.** It was written when the file was under the trigger. Nothing has been waived and the trigger has not been raised: this is a recorded acknowledgement that a documented trigger fired and the action has not been taken. Audit finding **#34** stays LIVE and the split is its remaining work — correcting the line count closes the paragraph, not the finding.

**The "~30-min refactor" estimate is the design pass's, made at 657 lines.** It has not been re-derived at 1127 and should not be quoted as if it had; the audit's cluster-J entry carries a measured seam assessment (what moves, what is shared, how many external citations point into this file). Read that before scheduling.

**Strategic value receipt:** Session 4 (wasteland) and save migration framework both unblocked by console. Replaces 5–10 min "build a chain to test" loops with 3-line console state setup. Cost recovered within 2–3 future sessions.

---

## Schema-mismatch UX — both fixes SHIPPED

**Status:** quick fix shipped as a standalone post-3.5 hotfix; migration framework shipped at `session-save-migration`. Both halves of the gap captured in NOTES.md after session-soil-exhaustion-3-5 PAUSE 5 are now closed.

### Quick fix — SHIPPED (~10 LOC)

When `SaveSystem.load_game` returns `result.success == false` (schema mismatch, corrupt JSON, missing fields, anything), `main.gd:_ready` now falls through to a `_generate_fresh_world()` helper instead of leaving the world in default empty state. Toast surfaces "Save incompatible — fresh world (seed N)" so the player knows what happened. The `OS.alert + push_error` from `save_system.gd` still fires first (informative), then the fallthrough generates a usable world.

Verified by writing a deliberately-invalid `version: 99` save and launching: `push_error` + `OS.alert` fire as before, then `push_warning("Save load failed... — generating fresh world.")` fires, and the player sees a populated world rather than an empty one.

### Migration framework — SHIPPED (`session-save-migration`)

`MIGRATIONS` Dict in `save_system.gd` keys source-version → migration method name. `_try_migrate(data, from, to)` walks the chain one step at a time, verifying each step bumps the version field correctly. `_dispatch_migration(name, data)` routes via match-statement (GDScript static dispatch via `Object.call(name)` doesn't work on static methods — match was the foolproof fix).

`load_game` now: read JSON → if version < SAVE_VERSION, run migrations → if version > SAVE_VERSION, hard-fail (forward-only) → otherwise apply data to world. Worldgen version stays as a separate hard-fail axis (procgen-output changes can't be migrated). When a migration gap exists (e.g., v14 has no MIGRATIONS[14]), `_try_migrate` returns null → load fails → post-3.5 hotfix regenerates fresh world. Player never stranded.

**Where migrations live:** centralized in `save_system.gd` for now — single file, easy to grep, all migrations share the same Dictionary→Dictionary signature. **If `MIGRATIONS` grows past ~5 entries OR a single migration exceeds ~80 lines, refactor to per-file modules under `scripts/systems/migrations/v<N>_to_v<N+1>.gd`.** ~30-min refactor when triggered. Today (1 migration, ~10 lines) the single-file shape is right.

**Schema-bump protocol** lives in CONVENTIONS.md → "Save schema" section. Replaces the previous "hard-fail and document why" protocol. New protocol: bump SAVE_VERSION → write migration → register → dispatch case → test → PROJECT_LOG.

**Breaking-change reset point: v17.** Pre-v17 saves are not preserved. Documented in CONVENTIONS.md.

### First-encounter receipt

session-soil-exhaustion-3-5 PAUSE 5 — user had a v16 save lingering from before Session 3's bump to v17, relaunched after Session 3 work, saw an empty world during Applicator smoke testing. Burned ~10 min on diagnosis (was there a bug from Session 3.5 changes?) before checking the launch's stderr. Session 3.5 changes were innocent; the gap was the post-fail fallthrough. Quick fix shipped immediately after 3.5.

---

## Soil exhaustion arc — **COMPLETE (Sessions 1–4 shipped)**

**Status:** **ARC CLOSED at session-soil-exhaustion-4.** Sessions 1+2+3+3.5+4 ship the complete stewardship loop: deplete fast → grace warning → wasteland scarring → Premium Compost restoration. Real failure state, real recovery path. Optional Session 5 (legumes) deferred indefinitely as polish.

Per-tile soil (NOT region-based — Session 1's region scope was reversed at Session 2; see PROJECT_LOG reversal #5). Foundation includes depletion-on-harvest with 3×3 falloff, fallow regeneration, visual tints showing dead zones, fertilizer chain (Composter + hand-apply at Session 3, Fertilizer Applicator automation at Session 3.5), per-tile boost state with timed decay, **wasteland mechanics + Premium Compost recovery at Session 4**, save v18.

### Architecture (current)

- **Per-tile storage**: `GridWorld.tile_soil_modifications: Dictionary[Vector2i (tile pos) → int (0..100)]`. Sparse — only modified tiles in dict, default 100 implicit.
- **Falloff**: planter harvest depletes 9 tiles. Center loses crop's `soil_cost`; 8 neighbors lose `max(1, ceil(soil_cost * 0.6))`. Per-crop costs: WHEAT 5/3, SUGAR_BEET 8/5, FLAX 3/2.
- **Per-tile regen**: 1 soil point per 30 sec when no active planter's 3×3 area covers the tile. `tile_regen_progress` accumulator (in-memory only, not persisted; lossy on save/load up to 30 sec).
- **Visual tints**: SoilLevel enum (PRISTINE/HEALTHY/DAMAGED/DYING/DEAD); rendering pass in `GridWorld._draw` overlays DAMAGED+ tints on grass + SOIL_TILLED tiles. Stone/path/water unaffected.
- **Soil-zero gate**: planter at `growth == 0` AND `tile_soil_health(b.anchor) <= 0` stays idle. In-progress crops (growth > 0) finish gracefully.
- **Single-planter oscillation**: idle planter on dead tile → tile regens to 1 → planter activates → consumes → tile drops → idle → cycle. PlanterPanel mini-grid flicker IS the player feedback.

### What's shipped (sessions 1 + 2 + 3 + 3.5 + 4)

- Per-tile storage + helpers (`tile_soil_health`, `deplete_tile_soil`, `deplete_planter_area`).
- `Planter.CROP_DATA` with `growth_ticks` + `soil_cost` per crop.
- `Planter.tick(b, world)` + `Planter.try_extract(b, world)` plumbed for per-tile access.
- `Planter.is_active(b)` helper — used by regen blocking.
- `_tick_soil_regen(delta)` — per-frame regen iteration with fertilizer multiplier (Session 3).
- Visual rendering: tint pass in `GridWorld._draw`; level-aware Q-inspect; PlanterPanel 3×3 mini-grid; fertilizer green-tint overlay (Session 3).
- Composter building + 3 recipes (wheat/flax → LOW, sugar_beet → MID); 12th ProcessorPanel consumer. **At Session 3.5: gained `prefer_dir = Belt.DIR_E` on outputs + `supports_direction = true` (rotatable) to fix backward-contamination bug when downstream jams.**
- `tile_fertilizer_state` dict + `try_apply_fertilizer` + `_tick_fertilizer_decay` (Session 3).
- NEW `item_apply` hotbar kind + Soil category (4 slots after 3.5: Composter + Fertilizer Applicator + 2 hand-apply) + dim-on-empty inventory.
- Q-inspect fertilizer line with multiplier + remaining time (Session 3).
- **Fertilizer Applicator (Session 3.5):** 1×1 footprint, 5×5 coverage, belt-fed or drag-drop compost input, auto-applies to most-depleted eligible tile at 1-per-5-sec rate. Tier-preference (richest first: HIGH → MID → LOW). Three-state machine (IDLE / SCANNING / BLOCKED). Specialized panel with 5×5 coverage mini-grid + cell color states (pristine/eligible/LOW-/MID-/HIGH-fertilized/impassable). **Session 4: input slot accepts HIGH alongside LOW + MID** — but only the slot did. The tick logic kept two hardcoded [MID, LOW] lists until audit #4/#5 (2026-08-23), so belt-fed Premium Compost was inert and one scarred tile could wedge the machine in BLOCKED forever. Both closed together: `TIER_PREFERENCE` is now the single accept-and-prefer list, and tile eligibility skips wasteland unless the selected tier can restore it (`GridWorld.wasteland_accepts_tier`).
- **Wasteland mechanics (Session 4):** tile soil at 0 for 60 sec → scarred (persistent). Wasteland blocks all passive regen. Distinct visual (near-black tint + X-shaped crack pattern). Q-inspect: "DEAD — will scar in Xs" during grace, "WASTELAND" once scarred. PlanterPanel: "IDLE — tile is WASTELAND" + action prompt.
- **Premium Compost / COMPOST_HIGH (Session 4):** 8× regen for 120s (top tier). On wasteland: snap soil to 30 + erase scarred flag + apply boost (~21 min total recovery designed). On healthy tile: just a stronger MID. Recipes: BREAD × 2 → HIGH (5s? actually 10s), LOAF_PACK × 1 → HIGH (10s — same time, better deal). Stacking: HIGH > MID > LOW; lower-on-higher rejected. LOW/MID on wasteland REJECTED (only HIGH restores).
- Save schema v14 → v15 → v16 → v17 → v18 (wasteland state added at v18). 4 schema bumps in the arc; migration framework still queued.
- Tests: 44 sub-suites total — 17 soil + 5 fertilizer-chain + 4 fertilizer-applicator + **11 wasteland sub-suites** (trigger + grace + blocks regen + planter idle + recovery + save v18 + composter HIGH recipes + stacking + grace-rescue + grace-rescue-under-active-farming + late-compost-refused) + **7 applicator-wasteland-recovery** (audit #4/#5: belt-fed HIGH + HIGH selection + scarred-tile wedge + HIGH restore + accepts-list drift guard both directions + aggregate buffer cap + panel cell colours). The old total here read 31 against addends summing to 35 — corrected while adding the new file; the wasteland list then named only 8 of its 9 ("blocks regen", sub-suite 3, was missing) and the same short list was in `test_wasteland.gd`'s own success string. Wasteland went 9 → 10 (total 42 → 43) at audit #7, then 10 → 11 (total 43 → 44) at the #7 follow-up that made a too-late compost apply refuse instead of consume. Counting rule, so the addends stay checkable: only top-level numbered sub-suites count — letter-suffixed parts (fertilizer-chain 4a/4b, applicator 1/1b, wasteland 10a-c and 11a-d) are one sub-suite each. That makes `test_fertilizer_chain.gd` hold 6 `# ---------- N.` headers for 5 sub-suites and `test_fertilizer_applicator.gd` 5 for 4, because those two files give their letter-suffixed parts a full header. `test_wasteland.gd` does not: its 10a-c and 11a-d sit under one parent header each with a shorter `# ---` marker, so it holds exactly 11 headers for 11 sub-suites. `test_soil_exhaustion.gd` (17) and `test_applicator_wasteland_recovery.gd` (7) have no letter-suffixed parts at all.

### Remaining sessions in the arc

- **Optional Session 5 — Crop rotation / legumes (per-tile). DEFERRED INDEFINITELY.** Polish, not core. Legume crops with negative `soil_cost` would heal their 3×3 area instead of depleting. Fertilizer chain is orthogonal — legumes are an alternative to fertilization, not a replacement. The arc is COMPLETE without this; revisit only if playtest pressure surfaces a gap. Hooks ready: `Planter.CROP_DATA` accepts negative `soil_cost`, `deplete_tile_soil` clamps at 0 today (easy to extend to negative for legume healing).

**All Sessions 3-5 INHERITED per-tile semantics.** Region-based versions of these would have been fundamentally different (per-region fertilizer; per-region wasteland; per-region rotation healing) — none transferable. **Catching the reversal at Session 2 was load-bearing for the entire arc.**

### Lessons captured during the arc (gameplay testing notes)

- **Worldgen quirk: `tile (0, 0)` is grass at worldgen v4** (Session 4 fixed the Session 3-era issue where the spawn-area-safety-net often placed a fallback lake at origin). For console testing flows, `(0, 0)` is now a reliable "fresh tile" starting point. **If something seems off, run `tile <x> <y>` first to verify the tile's actual state** — never assume.

- **Wasteland trigger requires soil-stuck-at-0**, NOT just briefly-at-0. The grace timer counts down only while soil == 0; regen lifts soil to 1 within 30 sec of reaching 0 if no active planter overlaps. So a single console `set_soil 0 0 0` won't trigger wasteland — soil regens before grace expires. Two reliable test paths:
  1. **`wasteland <x> <y>` console command** (added Session 4) — directly forces scarred state, bypasses 60-sec grace. Use for quick UI/visual verification.
  2. **Set up an active planter cluster** that keeps the tile depleted (overlapping 3×3 areas blocking regen). Use for "natural play" testing of the grace-period mechanic itself.

- **Tests don't replace smoke for end-to-end UX flows.** Bug 2 from session-soil-exhaustion-4 PAUSE 1 (Premium Compost hotbar slot missing) was invisible at the data layer (`try_apply_fertilizer` works) but broken at the UX layer (no slot to click). The whole wasteland recovery path was unreachable via hand-apply. **Protocol for future sessions: when adding a new tier or category, smoke the full PLAYER path (click hotbar → see toast → check tile state), not just the data path (`assert apply succeeded`).** The "ship tooling without exhaustive UI testing, surface bugs on first real use" pattern from session-dev-console was validated: 2 real bugs caught on the Dev Console's first deployment, both fixed before commit.

---

## RESOLVED 2026-08-26 (was Queued): soil/fertilizer/regrowth on `_process` — the split is now DELIBERATE

**Audit #31 closed WONTFIX-with-rationale after a measured design pass** (evidence absorbed
into `docs/scoping/r1-two-clocks.md`). The tick clock drives the factory sim; soil regen,
fertilizer decay and tree regrowth run on wall-clock **by design** — slow world processes on
a different scale from factory iteration, so `tick_speed` accelerates throughput, not the
land's recovery. `tick_system.gd` now states both clocks and why. The three migration
options are priced in the scoping doc; **option 4 (the fix text's own variant) is
disqualified by measurement — it re-opens #7 at every tier with a green suite.** Do not
reopen as a cheap win. The entry below is kept as the original statement of the problem.

### Original entry (historical)

**This is audit finding #31** (LIVE — MEDIUM), not a new defect. Re-derived 2026-08-23 while
re-applying the audit #7 fix and briefly mis-filed as "newly found R1" before anyone checked
the table it was already in. **Recorded, not fixed** — it is a design call, not a cleanup.

**Two-sided, and either side could be the wrong one.** `scripts/systems/tick_system.gd:5-7`
states the simulation advances on tick boundaries — "Buildings, crops, weather, etc. all
advance on tick boundaries — **never on `_process`**". But `GridWorld._process`
(`grid_world.gd:1182-1191`) hands the **raw engine delta** to `_tick_regrowth`,
`_tick_fertilizer_decay` and `_tick_soil_regen`. Those three are the whole soil arc's clock:
wasteland grace, soil regen, fertilizer decay, tree regrowth.

`TickSystem.tick_rate_multiplier` scales only `TickSystem._accumulator`
(`tick_system.gd:42`), so it has no effect on anything driven from `_process`.

**Reproduction:** dev console `tick_speed 10` (clamp is `[TICK_SPEED_MIN 0.1,
TICK_SPEED_MAX 10.0]`, `console.gd:39-40`). Crops, belts, inserters and processors run 10×.
Wasteland grace still burns 60 real seconds, soil still regens 1 point per 30 real seconds,
fertilizer still decays in real time. So at 10× a planter depletes its 3×3 ten times faster
while the tile recovers at the same speed — the soil balance the arc was tuned against is
silently a different game whenever the console is used to fast-forward.

**The call to make:** either the three `_process` ticks move onto `TickSystem.tick` (a
behavior change: regen would gain tick granularity, and `tick_speed` would then accelerate
soil — arguably what a player fast-forwarding expects), or the `tick_system.gd` doc comment
is narrowed to say what is actually true (buildings tick; per-tile soil/fertilizer/regrowth
are frame-driven and deliberately real-time). Do not "fix" it by editing whichever side is
cheaper to touch.

**Scoped in full at `docs/scoping/r1-two-clocks.md`** — the evidence on which side is
wrong, what breaks on migration, and a third option (move to ticks but exempt from the
multiplier) that is probably the worst of the three. The write-up's decisive finding:
**no existing test would catch this change in either direction.** Every soil-arc test
calls `world._tick_soil_regen(delta)` directly, bypassing `_process` and `TickSystem`
both, so all 44 sub-suites stay green through a migration that changes the game. The
first work item under any option is a wiring test — drive `TickSystem.tick`, assert
soil moved — because nothing does that today.

**That first work item is now done** — `scripts/tests/test_tick_loop_wiring.gd`, landed
2026-08-24 and described in the entry directly below. It changes nothing about the
decision; it makes the decision **visible**. Whoever moves the three systems onto ticks
now gets sub-cases (7), (8) and (9) in the face and has to state which option they took.
**The decision itself is still open.**

---

## Landed: the tick loop's own call sites are pinned (`test_tick_loop_wiring.gd`)

Added 2026-08-24. New coverage, not a bug fix — nothing was broken, and nothing in
`scripts/` outside the tests changed. Suite went 54 → **55**.

**The gap it closes.** Every other suite in the project reaches a simulation system by
calling it directly with hand-supplied arguments — `world._tick_soil_regen(1.0)`,
`Belt.tick(b, w)`, `PowerNetwork.update_supply_demand(world)`. None of them goes through
`GridWorld._on_tick` or `GridWorld._process`. So the suite pinned the *functions* and
nothing pinned the *wiring*: a deleted call site changed the game and shipped green.
Same failure class as the dropped test registration that `test_registration_completeness.gd`
guards — absence indistinguishable from success.

**How bad it actually was — measured, by deleting each call site in turn and running the
54-suite baseline without the new file:**

| call site (`grid_world.gd`) | pre-existing suite result |
|---|---|
| `_ready` → `TickSystem.tick.connect(_on_tick)` | 18 suites red |
| `_on_tick` → `PowerNetwork.update_supply_demand(self)` | 2 suites red |
| `_on_tick` → `Buildings.tick_one(...)` | 18 suites red |
| `_on_tick` → `Buildings.post_tick_one(...)` | **54 passed, 0 failed** |
| `_process` → `_tick_regrowth(delta)` | **54 passed, 0 failed** |
| `_process` → `_tick_fertilizer_decay(delta)` | **54 passed, 0 failed** |
| `_process` → `_tick_soil_regen(delta)` | **54 passed, 0 failed** |

Four of the seven were undetectable. The `post_tick_one` row is the one worth staring at:
belt-to-belt handoff is the only thing that pass dispatches, and removing it stops every
belt chain in the game one tile short of its destination while the runner prints
`54 passed, 0 failed`. Nothing covered it because every other belt consumer *pulls*
(`Chest.tick`, `Processor._try_pull_inputs`, `Inserter._try_pickup`) rather than being
pushed to, so a suite can run a belt into a chest and never touch pass 2. The three rows
that DO redden existing suites redden them only with downstream symptoms — "expected ≥9
grain, got 0", 18 suites at once — with nothing naming the cause.

**What it asserts.** Ten sub-cases, each with a PREMISE floor so it cannot pass vacuously.
A `TickSystem.tick` emission must drive the power pre-pass, building pass 1 (belt shift,
mill starting a cycle, inserter picking up) and building pass 2 (belt handoff); a
`_process(delta)` call must drive regrowth, fertilizer decay and soil regen. Observable
simulation state only — no call counters, and **no instrumentation was added to
production code**.

**Two-sided on purpose, and this is the part not to "simplify" later.** Each sub-case also
asserts the *other* clock does NOT do that work. That is what stops the file from
degenerating into "either path works", which would recreate the gap it exists to close —
and it is what makes finding #31 visible. The file states in its own header that it pins
today's wiring rather than blessing it.

---

## Landed: a test suite that ERRORS no longer hangs the whole runner

Found and fixed 2026-08-23 during the #11/#13/#21 review response. Recorded because the
failure signature is one this project has lost time to before, and because the fix
changes what a red run looks like.

**The failure.** GDScript has no try/except, so a suite that hits a runtime error simply
stops and `run()` hands back whatever its declared return type defaults to. Two shapes,
and only one of them was survivable:

- `run()` declared `-> Dictionary` (all 54 suites today) unwinds to `{}`. That reads as
  `ok == false`, prints `FAIL`, costs one suite, and the run completes. Survivable.
- `run()` with **no return annotation** unwinds to `null`, and the runner's
  `var result: Dictionary = test_class.run(self)` rejected null on the ASSIGNMENT. That
  second error aborted `_ready` itself: **`exit=124`, nine PASS lines, no summary,
  `get_tree().quit()` never reached.** The process hung until the timeout killed it —
  indistinguishable from the compile-error hang, and equally uninformative.

Nothing enforced the annotation, so the safe shape was a convention every suite happened
to follow.

**The fix** (`scripts/tests/test_runner.gd`): take the result into an **untyped** local,
which cannot fail; scrub fixtures; then check the shape and report
`ERROR <name> — run() returned Nil instead of a result Dictionary` before continuing.
Re-measured against the same reproduction: `exit=1`, `53 passed, 1 failed`, summary
printed.

**Side benefit worth knowing about.** The fixture scrub used to sit between `run()` and
the pass/fail branch, so it covered PASS and FAIL but not ERROR — an errored suite left
its `.tmp`/`.bak`/`.incompatible` sidecars behind, which is exactly the suite most likely
to have made a mess. The scrub now runs before the shape check, so it covers all three.
That closes a hole in the "a suite written later cannot forget to opt in" guarantee the
runner-side scrub exists for.

**Related but NOT fixed:** audit #63 (runner restores neither `SaveSystem.save_path` nor
`tick_rate_multiplier`) stays live. Its verification note argued the risk was low because
"a hard error aborts the runner's own _ready loop … loud failure, not silent corruption".
The measurement above shows that abort was silent, not loud. The reasoning is corrected
in the audit; the finding's actual subject is untouched.

---

## Art pipeline probe — four contract findings, one shipping blocker (2026-08-24)

`session-art-probe-1`. Sprite path behind `SpriteLibrary.enabled`, off by default, three
assets (chest, smelter, power_pole). Flag-off rendering proven byte-identical: six frames,
three at `42f6758` and three after, all md5 `4a2f646cf8fe8f65cb987697f5e38fd7`, 0 of 921600
pixels differing.

### 1. The tan pad under sprites is the SOIL TINT, not the shadow layer

A hard-edged, footprint-shaped tan pad appears under each sprite once the flag is on.
Diagnosed by elimination, all four measured rather than reasoned:

- **Not `draw_one`** — `grid_world.gd:1727-1731` is `if not drew_sprite:`, genuinely exclusive.
- **Not `SpriteLibrary.draw_building`** — `sprite_library.gd:455-479` draws shadow + body only.
- **Not body overflow** — the smelter is `sprite_px [64,96]` against `footprint Vector2i(2,2)`
  = 64 px (`buildings.gd:520`). **Body width equals footprint width exactly**; there is no
  horizontal overflow to spill.
- **Not the shadow layer** — the tempting hypothesis was a tan tint baked into the *faint*
  end of the shadow ramp, which would survive a high-alpha spot check. Sampled every
  non-zero alpha pixel in all three shadow PNGs, bucketed by alpha in steps of 32:
  **every bucket is mean RGB (0,0,0), max channel ≤ 1.** Pure black across the entire ramp.

What remains, and what the pixels support: the buildings sit on tiles carrying a **soil
tint** (`SOIL_TINT_DAMAGED/DYING/DEAD`, `grid_world.gd:1434-1436`). Sampled pad
(138,126,101); `SOIL_TINT_DAMAGED` over grass composites to (116,114,75), closest of the
three, with the residual explained by the shadow darkening part of the pad and by the base
terrain colour under those tiles not being plain grass.

**So this is not an art-side fix.** It is a pre-existing terrain behaviour that opaque
rectangles concealed for the whole life of the project, and sprite transparency revealed.
Decide whether depleted soil should read through under a building at all — that is a design
question, not a bug.

**Contract line worth adding anyway:** shadow layers are **pure black, alpha-only, no baked
colour**. This is currently *true* of all three assets and now measured, so write it down as
a requirement before asset four rather than discover it violated at asset nineteen.

### 2. Z-order is placement-order dependent, and it PERSISTS THROUGH SAVE/LOAD

**This is a correctness issue, not polish.** `grid_world.gd:1709` iterates `for anchor_key in
buildings:` — Dictionary **insertion order**, i.e. the order the player built things — with
only a footprint cull. No depth sort.

While every building was a tile-bound opaque rectangle this was unobservable. Sprites
overflow up to 64 px upward, so build order becomes visible: two identical factories on
identical tiles render differently depending on what was placed first. Captured both ways —
chest-first shows the pole's insulators over the chest; pole-first shows the chest
decapitating the pole.

**And the ordering round-trips.** `save_system.gd:291` iterates `grid_world.buildings` into
an array; `:789` re-inserts with `grid_world.buildings[b.anchor] = b` in array order. So
insertion order is serialized and restored — the wrong picture is *stable across sessions*,
not a transient artifact.

"Add a depth sort" reads as optional until you know the current behaviour is
non-deterministic with respect to a factory's layout. It is. **Not built this session by
instruction; recorded here so the next reader knows the severity.**

### 3. `anchor_px` points at an empty row on all three assets — needs a contract line

**⚠ SHIPPED, and the numbers below were wrong. See "Zero-padding rule — LANDED" at the
end of this section for the enforced rule and the re-measured counts.**

~~Every body sprite is **fully transparent in its bottom 8 rows** (`power_pole.png` and
`smelter_idle.png` empty at y=88..95; `chest.png` at y=56..63).~~ **Not true of any of the
three.** Re-measured from the files 2026-08-24: `chest.png` is empty at y=59..63 (5 rows),
`power_pole.png` at y=89..95 (7), and `smelter_idle.png` / `smelter_smelting.png` at **0
rows** — their bottom row carries a stray pixel at alpha 3/255. The original claim put
`smelter_idle.png` at y=88..95 when y=88 is solid at alpha 255.

`anchor_px` is `[sprite_w/2, sprite_h]`, so the anchor names a row with no artwork in it.
Geometrically self-consistent, but "sprite bottom edge" and "where the object visually
meets the ground" are different rows and **nothing in the JSON says by how much**.

At three assets it is invisible. At twenty, inconsistent bottom padding is per-asset
vertical jitter with **no test that can catch it** — every sprite is "correctly placed" by
the contract while sitting at a different apparent height.

**Resolve before asset four**, either way:
- add **`ground_contact_px`** to the JSON schema (the row where the object actually touches
  ground) and draw against that, or
- **mandate zero bottom padding** so `anchor_px.y == sprite_h` is also the contact row.

The first is more honest about 3/4-view art; the second is cheaper and testable by a loader
assertion (bottom row must contain at least one non-zero alpha pixel).

### 4. ⚠ SHIPPING BLOCKER — no `.import` sidecars, so `load()` fails outright

Measured: `ResourceLoader.exists("res://art/sprites/chest.png")` → **false**;
`FileAccess.file_exists` on the same path → **true**; `load()` → `No loader found for
resource`. `.godot/imported/` contains only `icon.svg`. The loader therefore uses
`Image.load()` + `ImageTexture.create_from_image()` (`sprite_library.gd:19-38`).

**An exported build will not pack unimported files.** This must resolve before any real art
ships. Two honest options:

**(a) Import them properly as Godot resources.** Costs: generating sidecars requires running
the editor, which **writes into `art/`** — and `art/` is owned by a concurrent Blender
session. That ownership conflict is what pushed the probe to `Image.load()` in the first
place.

**(b) Commit to runtime `Image.load()`** plus an explicit export-preset rule packing
`art/sprites/*` as loose files. Costs: no import-time compression, no mipmaps, no texture
streaming; every sprite is decoded at runtime (measured 1.4 ms/asset cold, ~28 ms at twenty).

### Decisions taken 2026-08-24

**`.import` — option (a), separate source from shipped. DECIDED.** `art/` stays
Blender-owned; `art/build.ps1` gains a copy step into a game-facing directory Godot imports
normally. Rationale: it resolves the ownership conflict rather than papering over it, the
importer does its job (compression, mipmaps, platform variants) instead of runtime
`Image.load()`, and the export gap closes as a side effect. The extra hop is trivial next to
maintaining a runtime loading path forever. **Not yet implemented.**

**`ground_contact_px` — zero-padding mandate, not a schema field. DECIDED.** Sprites must
have no transparent bottom padding, so `anchor_px.y == sprite_h` is also the contact row. The
loader enforces it: the bottom row must carry artwork, fail loud otherwise. Rationale: a
schema field nobody can verify is worse than a constraint the loader checks. **LANDED — see
below.**

### Zero-padding rule — LANDED, and ⚠ ALL THREE ASSETS NEED RE-EXPORT BEFORE THE SPRITE PATH RENDERS AGAIN

`sprite_library.gd` (`BOTTOM_ROW_MIN_ALPHA`, `empty_bottom_rows`, the
`require_ground_contact` arm of `_load_texture`) now rejects any body master or shadow whose
bottom row carries no artwork. Applied to bodies and shadows, **not** to the glow — a glow is
an additive overlay on the hot part of a machine, and `smelter_glow.png` is legitimately
empty for its bottom 12 rows.

**Per-asset empty bottom rows, measured at the rule's threshold:**

| file | empty bottom rows | bottom row's strongest alpha |
|---|---|---|
| `chest.png` | **7** | 0 |
| `smelter_idle.png` | **2** | 3 |
| `smelter_smelting.png` | **2** | 3 |
| `power_pole.png` | **9** | 0 |
| `chest_shadow.png` | 0 | 160 |
| `smelter_shadow.png` | 0 | 162 |
| `power_pole_shadow.png` | 0 | 159 |
| `smelter_glow.png` | 12 | 0 — exempt, not a silhouette |

**All three declared assets therefore fail to load.** `sprites on` reports `loaded=0
failed=3`, `report()` push_errors, every declared building gets the magenta fallback cross,
and `tools/boot_smoke.ps1` fails if the flag is ever turned on. The flag is off by default,
so nothing user-facing changed. **Art must re-export the three bodies with the silhouette
flush to the bottom edge.** When that lands, `test_sprite_manifest.gd` sub-case (1) goes red
from the other direction and its comment says what to restore.

**The rule carries an ALPHA THRESHOLD (8/255), and that is load-bearing.** Written as "at
least one non-zero alpha pixel" it **grandfathers the smelter**: both masters have a stray
pixel at alpha 3/255 in their bottom row, ~1% opacity, invisible — and a strict-zero rule
accepts them. Measured by mutation: dropping the threshold to 0.5/255 makes the smelter load
and the suite says so. Per-row maxima show a clean gap — anti-aliasing noise at 1, 3, 4;
real silhouette at 18, 57, 130, 233, 255; nothing between 5 and 17. 8 sits in the gap.

**Tan pad — OPEN DESIGN ITEM, not a defect.** Depleted soil reading through under buildings
is a design question. For: visible soil state without opening a panel. Against: buildings
that look seated rather than floating on a coloured pad. Not blocking; decide when it
matters. Explicitly **not** an art-side fix — the shadow layers were measured clean across
the whole alpha ramp.

**Recommendation — (a), with a build step that resolves the ownership conflict.** Separate
source from shipped: `art/` stays Blender-owned working directory, and `art/build.ps1`
(which already exists) copies finished sprites into a game-facing directory Godot imports
normally. Nothing writes into `art/` from the engine, the export packs real resources, and
the pipeline shape already matches — `art/renders` → `art/sprites` gains one more hop. This
is a pipeline change, so it is a decision, not a cleanup.

## Queued: two live tails lifted out of the root plan files before deleting them (2026-08-25)

`SESSION_E_PLAN.md` and `INVENTORY_UI_PLAN.md` were deleted (audit #36 / #77). Both were
stale hand-off briefs — v9/v10 schema snapshots against a live v18, 8-and-9-test counts
against 66 — and `INVENTORY_UI_PLAN.md` was worse than its finding said: its "Locked design
decisions" click table binds shift-click to *transfer entire stack*, while what actually
shipped binds shift+LMB to **half-stack** (`slot_click_handler.gd:33-34`). A file headed
"locked" describing the scheme that lost is worse than a stale version number.

**Everything below was verified still-open before the files were removed.** This is the
whole of what was worth keeping; the rest is in `PROJECT_LOG.md` and git history.

### Camera zoom — zoom level is not persisted, and that question was never answered

Zoom shipped (see "Camera zoom — shipped + polished" below). Its plan listed four open
questions, and shipping settled some silently. **One is verifiably still open:**
`grep -c zoom scripts/systems/save_system.gd` returns **0** — zoom level is not saved, so
every load resets the player's chosen framing.

The original note argued it "probably" should persist, as player-comfort state, but "not a
save-shape change worth bumping the schema for — could go in a separate ui-prefs file."
That framing is still the useful one: a UI-prefs file avoids a schema bump entirely.

Three others were never explicitly resolved on the record and are worth *checking* rather
than assuming: **pinch-zoom on touch** (no touch input layer exists), **zoom-to-cursor vs
zoom-to-centre** (settled by whatever shipped, but not written down), and
**wheel-while-modifier conflicts** (if shift+wheel or alt+wheel ever bind elsewhere, plain
wheel must stay zoom — verify the InputMap).

### Inventory slot grid — right-click half-stack and drag-and-drop are unshipped

The plan's deferred "v2" list. Measured: `grep -c MOUSE_BUTTON_RIGHT` returns **0** across
`inventory_grid.gd`, `chest_panel.gd` and `slot_click_handler.gd`, so both of these are
genuinely not implemented:

- **Right-click for half-stack pickup.** Note the collision to resolve first: half-stack is
  already bound to **shift+LMB**, so this is now a question of which gesture owns it, not a
  missing feature.
- **Drag-and-drop for moving stacks** between slots, with drag-plus-modifier to split.

The other two v2 items look superseded rather than pending — ctrl+LMB ships a quantity
picker (`slot_click_handler.gd:13, 30`), which covers "transfer one" more generally. Confirm
before scheduling either.

## Protocol: assert the PATH, not the result — an answer can arrive by any route

**Codified 2026-08-25 from audit #16's mutation M3, and placed above silent compensation
because it is how a silent-compensation defect survives a mutation pass.**

**The shape:** a guard is deleted. Its absence produces two runtime faults. The faults
cancel into the correct answer. Every assertion on the output passes. The guard is gone.
**Only the error count differs.**

The worked case. `hover_preview_blocked` opens with `if building_type < 0: return false` —
the neutral hover, where the preview highlights an existing building rather than a
placement. Delete that guard and the suite reports **68 passed, 0 failed**, above **8
`SCRIPT ERROR` lines**:

1. `Buildings.requires_overlay(-1)` — out-of-bounds Dictionary read, function aborts.
2. `Buildings.footprint_of(-1)` — same, aborts, hands back the declared return default:
   an empty `Array`.
3. `can_place_building` walks **zero** cells, finds nothing blocking, returns `true`.
4. The caller computes `not true` = `false` — **exactly what the guard would have
   returned**, reached by faulting twice per call.

Four assertions checked the answer. Four passed.

**The rule, stated as the test to apply:** *a test that asserts the answer cannot
distinguish "the guard worked" from "the guard is missing and two faults cancelled."* Those
are different states of the program and an output comparison sees neither — it sees only
the value they happen to share. Where a guard exists to make something happen **a
particular way**, assert the way.

**In practice: plant a sentinel that only the intended path preserves.** The strengthened
assertion writes a sentinel into `last_building_place_error` and requires it to **survive**
the neutral call. `can_place_building` clears that string on its first line, so a surviving
sentinel proves the early return fired *before* delegating. It cannot be satisfied by any
other route to the same boolean. M3 re-run against it reddens four times.

Outcomes have more than one cause; that is precisely what makes them weak evidence. Prefer
an assertion that names the route: a sentinel, a call counter, an observable side effect
that only the intended branch produces.

### An assertion that derives its expectation from the code under test cannot see it change

**#26, mutation M4.** `Belt.is_advance_tick()` was mutated to `return true`. The suite's path
assertion computed *which slot to expect* by calling `Belt.is_advance_tick()` — the very
function under mutation. Expectation and behaviour moved together, stayed in agreement, and
the assertion passed. **Only the reachability control caught it.**

Fixed by deriving the expectation from a source the mutation cannot reach:
`TickSystem.current_tick / Belt.TICKS_PER_SLOT` instead of asking production whether this is
an advance tick. Re-run, M4 now reddens at tick 1.

**This is the mirror of #27 and it is easier to miss.** #27's suite *reimplemented*
production, so the copy could drift — visible on inspection, since the duplicated constants
sit right there. Here the suite *calls* production to compute what it expects, which looks
like the responsible thing to do — no duplication, no drift, a single source of truth. Both
make the test agree with production **by construction**; only one of them looks wrong.

**The rule: an assertion's expected value must not be computed by any code path the
assertion is meant to protect.** Derive it from a constant, from arithmetic the production
path does not perform, or from a value fixed before the run. If you cannot state where the
expectation comes from *independently of the thing under test*, the assertion is checking
that production agrees with itself.

#### THE EVIDENCE TABLE — cite this instead of re-litigating

**This A/B settles the rule.** The next time anyone argues "surely calling production is
cleaner than duplicating constants" — and someone will, because it *is* cleaner and it
*looks* like best practice — the answer is this table, measured on #25 (2026-08-25), not a
re-run of the argument.

Two versions of the same recipe suite. Identical driving code, identical machines, identical
tick counts. The only difference: where the **expected** values come from. Five mutations to
`recipes.gd`, applied one at a time:

| mutation to the table | expectations as LITERALS | expectations from `Recipes.get_recipe()` |
|---|---|---|
| output item type swapped | **RED** | GREEN |
| input ratio changed | **RED** | GREEN |
| `time_ticks` halved | **RED** | GREEN |
| fluid gate removed | **RED** | GREEN |
| output count changed | **RED** | GREEN |

**Five for five against three delegated fields.** The delegated version still ran the
machines, consumed inputs, produced outputs, and asserted exact counts — and detected
nothing, because when the table moved its expectations moved with it. The only red in those
runs came from a *different* suite. Not weakened — **blind**: there is no partial credit,
no weaker-class detection. A suite whose expectations come from the system under test
detects **none of the class it was written for**, while looking and running exactly like
one that does.

#### This one is a CHECK, not a caution — it is mechanically greppable

Almost every protocol in this file needs judgement. This one does not, and that makes it
worth more than its size. **The tell is syntactic: the expected side of an assertion
contains a call into the module being tested.** A first-cut sweep, deliberately
over-inclusive, to be read rather than trusted:

    grep -nE "_check\(.*(Belt|Inserter|Processor|Chest|Smelter|Composter|Planter|GridWorld|SaveSystem|Buildings)\." scripts/tests/*.gd

Every hit is a place where production appears inside an assertion. Most are legitimate —
*acting* on the system under test, or reading its state to compare against a literal. The
ones that matter are where the production call sits on the **expected** side, deciding what
the assertion should compare to. That distinction is the part a human still makes; finding
the candidates is not.

Worth building into a suite if this recurs a third time: a guard that flags assertions whose
expected expression calls the module under test. It would have caught M4 at authoring time.

#### Same failure, opposite appearance — which is why one is easy and one is not

- **#27** — the suite **reimplemented** production: its own `SLOTS_PER_BAG`, `BAG_CAP`,
  `STARTING_CAPACITY`, its own `_try_consume` carrying the ordering rule. **Visible on
  inspection.** Duplicated constants sitting in a test file look wrong to anyone reading
  them, and the finding was raised by exactly that reading.
- **M4** — the suite **called** production to compute what it expected
  (`Belt.is_advance_tick()` deciding which slot the item should be in). **Looks like best
  practice**: no duplication, no drift, a single source of truth. It reads as the fix for
  #27, and it is the same defect.

Both make the test agree with production **by construction**. The duplication version is
caught by review; the delegation version is caught only by mutation, and only if the
mutation targets the shared function — M4 passed until the expectation was re-derived from
`TickSystem.current_tick / Belt.TICKS_PER_SLOT`, a source the mutation could not reach.

**So "don't duplicate production in tests" is half a rule.** The whole one is: don't let the
expectation and the behaviour come from the same place, by copying **or** by calling.

### The three-count run protocol catches bad TESTS, not just compile breaks

Worth stating separately, because it is wider than the use it was written for. The standing
rule — check `passed,` **and** `Parse Error` **and** `SCRIPT ERROR` — was written after a
compile error printed `57 passed, 0 failed` above 268 error lines. **M3 is the other use:
the suite was green, the summary was truthful (every assertion really did pass), and the
only evidence of a deleted guard was the `SCRIPT ERROR` count.**

So the third count is not redundancy against compile breaks. It is the only signal
available when a test passes for the wrong reason and the program is faulting its way to
the right answer. Read all three, every run, including the runs that look clean.


## Protocol: silent compensation — when absence is indistinguishable from success

**Codified at the audit re-application session (2026-08-24)** after the third instance in
one session. It is a property of this codebase, not three coincidences.

**Pattern:** a system stops running, and something downstream compensates well enough that
nothing observable changes. No exception, no wrong value, no red test — just a quieter
version of the same behaviour. The compensation is what makes it invisible, and the
compensation is usually *good design* elsewhere (a pull-based consumer, a defensive
default, a tolerant loop). That is why these survive review: every individual piece is
correct.

**Three instances, all found the hard way:**

1. **A test registration was deleted** from `test_runner.gd` by a concurrent session's bare
   `git commit` absorbing a staged deletion. HEAD ran one whole file fewer and printed
   green — the runner reports what it was told to run, so a shorter list is a successful
   run. *Compensator:* the pass/fail summary is derived from the registry, not from disk.
   Now guarded by `test_registration_completeness.gd`.

2. **`Inventory.load_array` truncated the player's inventory** on a malformed row. A
   GDScript runtime error aborts only the innermost function, so `load_array` died and
   `load_game` carried on to `success = true` with `skipped_entries` at **0** — the load
   did not merely fail to notice, it affirmatively reported nothing was skipped. One
   corruption shape (`"xy"`) produced no error line at all, since `int("x")` is 0.
   *Compensator:* the caller's success path had no dependency on the callee finishing.
   Fixed at `7a86195`; recorded as R3 in the audit tracker.

3. **`Buildings.post_tick_one` — pass 2 of the documented two-pass tick — was wholly
   uncovered.** Delete it and belt-to-belt handoff stops everywhere in the game while the
   runner prints `54 passed, 0 failed`. *Compensator:* every other belt consumer
   (`Chest.tick`, `Processor._try_pull_inputs`, `Inserter._try_pickup`) **pulls** rather
   than being pushed to, so a suite can run a belt into a chest and never touch pass 2.
   Now pinned by `test_tick_loop_wiring.gd`.

### The detection question

**For each system: if it silently stopped running, what would notice — and how would the
failure present?** "A test would fail" is not an answer until you have deleted the call and
watched it fail. In all three cases above the honest answer was "nothing", and in two of
them the intuition beforehand was "obviously something would".

A second-order form worth asking too: *what compensates for this system?* A system with a
pull-based consumer, a tolerant default, or a caller that does not depend on it finishing
is a candidate before you test anything.

### Current coverage, so the next arc does not add a fourth

`test_tick_loop_wiring.gd` now pins seven call sites — the `TickSystem.tick` connect,
`PowerNetwork.update_supply_demand`, `Buildings.tick_one`, `Buildings.post_tick_one`, and
the three `_process` calls (`_tick_regrowth`, `_tick_fertilizer_decay`, `_tick_soil_regen`).
Each was verified by deleting it and watching a specific sub-case redden.

**Still unasked, and worth asking before the next arc:** the systems reached *inside*
`Buildings.tick_one`'s dispatch rather than at the loop level — per-building tick handlers,
the burner fuel path, fluid network updates — plus anything a future arc adds to either
entry point. The wiring test pins that the **loop** runs; it does not pin that the loop
dispatches to every building type it should. That is the same shape one level down.

**When adding a system to any tick path, delete the call and run the suite before you
consider it covered.** If nothing reddens, the coverage does not exist yet.

**First cache built under this protocol (2026-08-26, audit #29):** the
`_active_regrowth` index in `grid_world.gd` — and a cache is this failure shape's
natural habitat, because a stale entry is absence wearing success (a chopped tree
that silently never regrows). Two deliberate choices, recorded so the next cache
copies them rather than re-deriving: the hot loop reads `resource_state[pos]`
**unguarded**, so a stale index entry faults loudly every frame instead of
self-healing — do not "harden" that read; and every invalidation edge got a
drop-the-call mutation run before the fix was called covered (`test_regrowth_index.gd`'s
header carries the M1-M6 ledger; three of the six drops announce themselves only in
the `SCRIPT ERROR` count, which is the three-count protocol earning its keep again).
The same day, #32's prescribed caches were **declined** when measurement put their
benefit below their invalidation risk — the tracker's #29/#32 measurement note has
the numbers. The pair is the protocol's decision rule in miniature: a cache is
justified when the measured waste is large AND every edge can be made loud; absent
either half, the walk you can see beats the cache you cannot.

### Fourth instance (2026-08-24): the sprite draw call site

`SpriteLibrary.draw_building` was added to the building draw loop and **deleting the call
site left the suite at `57 passed, 0 failed`** — the same shape as `Buildings.post_tick_one`
before `test_tick_loop_wiring.gd`. Found by applying the rule above rather than by accident.

The sprite path is doubly exposed to this: a sprite that fails to load falls back to
`draw_one()`, so the building **still renders** and a broken asset looks like a working game.
That is why the guards there are deliberately loud — a startup manifest line reporting
loaded-vs-declared, a `push_error` when any declared sprite fails, and a magenta X painted
over any building that fell back. Verified by moving `chest.png` aside and running it, not
by assuming it would be obvious.

### ⚠ A structural ceiling: no CanvasItem can be render-tested headless

The sprite call site is now pinned **by source text, not by execution**. `test_runner.gd`
calls suites synchronously and never yields a frame, so **no `CanvasItem` in this project can
receive `NOTIFICATION_DRAW` during a headless run**. Nothing in the suite has ever executed a
`_draw()`.

**⚠ CORRECTED 2026-08-24, and I had it wrong by not testing it.** `_draw()` **does** execute
under `--headless` if something yields a frame. Measured in a scratch project: draw-call
count goes 0 → 1 after one `await get_tree().process_frame`, and rises again after a further
`queue_redraw()`. What is genuinely absent is **pixels** —
`get_viewport().get_texture().get_image()` returns **null** headless.

The accurate statement: **headless can prove that draw code ran and which branch it took; it
cannot prove what appeared on screen.** The runner does not do this today only because its
loop is synchronous (`test_runner.gd:111`, dispatching at `:134`), not because the engine forbids it — an opt-in
`run_async` dispatched via `has_method` would sidestep the await-on-non-coroutine warning without
touching 57 synchronous suites.

Also measured, and it closes the obvious workaround: **a recording-canvas double does not
compile here.** Shadowing `draw_rect` on a `Node2D` subclass is `Parse Error: The method
"draw_rect()" overrides a method from native class "CanvasItem" … (Warning treated as
error.)`, and `Buildings.draw_one`'s `canvas` parameter is typed `CanvasItem`, so a plain
`RefCounted` recorder cannot be substituted either.

The consequence that survives the correction: **rendering *appearance* defects still cannot
redden a headless run, so a green suite carries no information about what the game looks
like.** The executed check for the sprite path remains a windowed flag-on/flag-off pixel
differential. Full re-scope in `docs/scoping/visual-verification.md`.

### Input CAN be driven headless — but not through the root Window (measured, cluster H)

The neighbouring `_draw` ceiling made it natural to assume `_input` / `_unhandled_input`
were equally out of reach without a frame. **They are not**, and audit cluster H (#22 /
#58 / #59) is tested behaviourally because of it. Measured on Godot 4.6.3 `--headless`
inside `test_runner.tscn`, all from `_ready` with no frame yielded:

- **`push_input` on a `SubViewport` works.** `_input` and `_unhandled_input` both fire,
  synchronously, repeatedly, including after a handler has called
  `set_input_as_handled()`. GUI dispatch works inside it too: a focused `LineEdit` in a
  SubViewport really does receive a key and really does insert the character.
- **⚠ `push_input` on the ROOT WINDOW delivers nothing here.** Zero `_input` calls for a
  key nothing binds. The root's `is_input_handled()` reads true and stays true, i.e.
  `push_input` returns before the reset it normally does first — and a *forced* handled
  flag does not block delivery, so the stuck flag is a symptom of the early return, not
  its cause. The same call on the same root Window works from a `--script` SceneTree
  during a real frame; the difference left is the runner's no-frame property. **The
  exact gate was not identified.** What matters: a suite that pushes into the root
  Window is green and empty. Parent the node under test into a `SubViewport` and push
  there.
- **`push_input` does not touch the `Input` singleton.** `Input.is_action_just_pressed`
  stays false for a pushed event; only `Input.parse_input_event` (the OS path) and
  `Input.action_press` write action state. Code that mixes event handlers with polled
  actions — `main.gd` does — needs both driven, separately.
- **⚠ `Input.action_press` sticks for the whole run.** `is_action_just_pressed` is
  `pressed_process_frame == Engine.get_process_frames()`, and `get_process_frames()` is
  0 for the entire headless run, so one press reads as just-pressed forever.
  `Input.action_release` does **not** undo it (`pressed` goes false, `just_pressed`
  stays true). Two consequences: **no suite can assert "and the next press behaves
  differently"** — that shape is hand-only — and a press leaks into every later suite.
- **A whole `Main` from `main.tscn` instantiates and runs `_ready` headless**, with
  `@onready` refs resolved. Guard `SaveSystem.save_path` first (audit #63: the runner
  restores it for nobody) or `Main._ready` will load a previous suite's fixture. Free it
  with `free()`, not `queue_free()` — no frames means a queued free never happens and the
  orphan keeps eating input for the rest of the run.

Working harness: `scripts/tests/esc_input_harness.gd`. It re-measures the channel at the
top of every suite with a key nothing binds rather than trusting any of the above.

**A frame-stamp guard is therefore untestable in this suite.** Audit #22's prescribed fix
was to compare `Engine.get_process_frames()`; because that value never changes here, such
a guard cannot be exercised and would misbehave under the runner. Cluster H shipped a
one-shot read-and-clear latch instead. Reach for a latch, not a frame stamp, whenever a
cross-handler guard needs to be verifiable.

### ⚠ Rule recursion: a rule against a failure shape is itself subject to that shape

**This has now happened at least four times, which makes it a pattern rather than
carelessness.** Each time, a rule was written to catch a specific failure, and the rule
went on to commit that exact failure:

1. **The audit tracker's anti-drift baseline block drifted.** Written to stop stale
   counts; shipped with two wrong counts, and instructed readers to propagate one of
   them ("correct #82 to 13" — the 13th match was a doc comment).
2. **Finding #31 was re-filed as "R1, newly found"** — in the document whose entire
   purpose is knowing what is already tracked.
3. **`git checkout -- <path>` was used one command after writing the rule against it**,
   reverting the very edit the rule existed to protect.
4. **The zero-padding rule would have grandfathered the smelter.** The rule was adopted
   specifically to close the silent-compensation shape, and as first specified — "the
   bottom row must contain at least one non-zero alpha pixel" — both smelter masters
   passed on a single stray pixel at **alpha 3 of 255**. Absence indistinguishable from
   success, reappearing *inside* the rule written to close it. Caught only because the
   implementer measured the alpha distribution instead of reading the rule back and
   agreeing with it.

5. **The `pre_overlay` rollback was read back and agreed with — one session after
   recording the practice against exactly that.** Cluster G's #23 was pre-derived as
   MIS-SHAPED on the grounds that a rollback call existed and dated to the original
   console commit. It existed; it had never once worked. See "Age as evidence" below.

**Why it keeps happening:** writing a rule creates the feeling of having handled the
problem, and that feeling substitutes for checking. The rule is the newest, least-tested
artefact in the repo at the moment it is written, and it is the one thing nobody thinks
to test — because it is the test.

**The practice:** **verify the rule by mutation, not by reading it back.** Construct the
case the rule is supposed to reject and confirm it *is* rejected. For a threshold, derive
it from measured data and check the distribution has a gap where you put it — the alpha-8
figure survives because per-row maxima cluster at 1, 3, 4 (anti-aliasing) and 18+ (real
silhouette), with nothing between 5 and 17. For a count, re-derive it from the source. For
a status claim, run the command in the row.

A rule you have only read is a rule you have only hoped for.

### Age as evidence: a long-lived guard nothing exercises is the likeliest to be broken

Cluster G, finding #23. `_cmd_place` captures `pre_overlay`, paints an overlay to retry a
placement, and restores `pre_overlay` on failure — with a comment saying so. The rollback
call dates to `42e46f0`, the original Dev Console commit. That age was read as evidence the
finding was stale.

**It was evidence the defect was old.** `pre_overlay` is `Overlay.NONE` on bare grass, and
`Terrain.can_place_overlay` returns false for NONE (`terrain.gd:85-86`, "use clear path,
not paint"). So `set_overlay(pos, NONE)` returns false and changes nothing: the rollback
had been a silent no-op for its entire life, leaving stray Stone in the save-persisted
`tile_modifications` dict every time a console placement failed on grass.

**The inversion:** age reads as battle-tested and means unexamined. A guard that has
survived years without a test has not been *proven*; it has been *unquestioned*, and the
longer it sits the more confidently it gets skipped. Nothing had exercised this one, so
nothing had ever contradicted it.

This is the same family as silent compensation, one level up: **the signal that suggests
safety is the signal that should prompt the check.** A `# this is handled` comment, a guard
with a reassuring name, a line old enough to feel load-bearing — each is a reason to
construct the failing case, not a reason to skip it. Applies with particular force to
inherited defect reports: "the code already handles that" is a hypothesis.

### A tier above rule recursion: the verification tooling reporting success while doing nothing

**This is not a fifth instance of rule recursion — it is a level up.** The four instances
above are *rules* that failed to catch what they targeted. This is the **mechanism that
adjudicates every other claim** returning success while doing nothing.

**A mutation that silently fails to apply produces a green suite indistinguishable from a
guard that is not load-bearing** — and the recorded conclusion would be to strike a real
guard from the record as unnecessary. Every other protocol in this file bottoms out in
"mutate it and see". If the mutation is a no-op, all of them fail open at once, quietly,
and in the direction of deleting protection.

**The only check that catches it is echoing the mutated line back from disk.** Not the
tool's exit code, not the absence of an error, not re-reading the command you typed.

**Second instance of the same tier, found in Cluster H: the *editing* tool silently
rewrote two files wholesale from CRLF to LF.** `git autocrlf=true` normalised it back on
the way into the index, so **the diff showed nothing** — and the change was invisible until
a multi-line mutation anchor stopped matching mid-matrix. Same shape: a tool reported
success, altered something it never mentioned, and the safety net that should have surfaced
it (the diff) was the thing that hid it.

### THE STANDING CHECK (two incidents is enough; do not wait for a third)

**After any multi-file edit pass, and before trusting any mutation result, run this.** It is
a step, not a habit. A mutation that stops matching is the **lucky** outcome; the unlucky one
still matches and silently targets the wrong line, producing a result that is confidently
reported and simply about something else.

    python -c "import glob;m=[(f,c,l) for f in glob.glob('scripts/**/*.gd',recursive=True) for d in [open(f,'rb').read()] for c in [d.count(b'
')] for l in [d.count(b'
')-c] if c and l];print('MIXED-ENDING FILES:',m) if m else print('no mixed-ending files')"

**⚠ Use a byte count, not `grep`.** Measured on this box: `grep -c` for a carriage return
returns **0** on a CRLF file — it opens in text mode and strips them — while the anchored
form returns the *total line count* on an LF file. Both answers look plausible and both are
wrong. The check above reads bytes for exactly this reason; do not "simplify" it to a grep.
`git ls-files --eol` is the other trustworthy source.

**Measured 2026-08-24 — the first version of this check was wrong, in the direction of false
alarm.** It asserted "zero lone LFs", which flagged **29 files** on its first run. All 29 are
*uniformly* LF and perfectly healthy; **genuinely mixed files: 0**. A check that reports 29
false positives gets ignored by its third run, which is its own silent-compensation shape —
so this is the rule-recursion practice applying to the rule written one paragraph earlier.

**The real hazard is a file containing BOTH endings**, where a multi-line anchor breaks
mid-file and a `
`-assuming pattern matches some lines and not others. That is what the
check above tests.

**The second half of the check is not automatable, so hold it as a habit:** this repo is
**130 CRLF / 29 LF**, split by which tool created each file. A mutation pattern that
hardcodes either ending is wrong for a large minority of the tree. **Always write `
?
`**,
and never infer a file's convention from its neighbours.

### Why this class stays invisible: `autocrlf` is a safety net that hides the damage it normalises

Both incidents were invisible for the same reason, and it is worth stating alone because it
inverts an assumption this project leans on constantly.

`core.autocrlf=true` converts line endings on the way into the index. So when a tool
rewrites a file's endings wholesale, git normalises the rewrite back out and **the diff is
clean**. The safety net is working exactly as designed, and that is precisely the problem:
the diff is clean *because the tool cleaned it*.

**So "no diff" carries no information about whether a file changed.** It means "no
difference git chose to show you", which is a far weaker claim than it reads as. Any
verification that bottoms out in "the diff was empty" — that a revert landed, that an edit
was scoped, that nothing else moved — inherits that weakness. Compare bytes or hashes when
the answer matters.

Cluster C, measured: **three mutations silently no-op'd** — two `perl -0pi` and one `sed`,
all defeated by CRLF line endings that the patterns did not account for. One of the three
produced a **fully green suite**, which reads exactly like "this guard is not load-bearing"
and would have been recorded as a false negative — a guard deleted from the record because
the tool that was supposed to break it never did.

This is silent compensation in the *verification tooling*, and it is the most dangerous
place yet for it, because a mutation pass is what this project uses to decide whether
anything else is real. A mutation that does not apply produces the same green as a
mutation that applies and is survived.

**This is why the standing rule is to echo the mutated line back from disk, not to trust
that the substitution ran.** All three were caught by the echo and by nothing else. On this
repo specifically: files are CRLF, so any pattern anchored to `$` or `
` needs `
?`, and
a substitution that reports success without changing the file is the normal failure, not
the exotic one. Assert the file changed — compare a hash, or count matches before and
after — rather than assuming a zero exit code means a zero-diff edit did something.

### Corollary: `passed,` alone is not a safe signal

During the same session a genuine **Parse Error** was introduced and the runner still printed
**`57 passed, 0 failed`** with **268 `SCRIPT ERROR` lines** above it. The summary line was
truthful about the suites that ran and silent about the file that failed to compile — silent
compensation in the test harness itself.

The standing run protocol checks **all three** counts (`passed,` **and** `Parse Error` **and**
`SCRIPT ERROR`) for exactly this reason. That protocol is load-bearing, not belt-and-braces;
it is what caught this.

## Protocol: reproduce the described consequence, not just the described mechanism

**Codified at the audit re-application session (2026-08-24)**, after two findings in one
session diverged from their own descriptions — in opposite directions, and both had
survived adversarial verification.

**The standard, for any inherited defect report:** a finding names a *mechanism* and a
*consequence*. Verification usually confirms the mechanism, because the mechanism is what
you can read in the code. The consequence is what determines severity and what determines
whether a fix is complete — and it is the half that goes unchecked.

**Two divergences this session, one each way:**

- **#8/#9** described item destruction across four call sites. The mechanism was quoted
  correctly; the consequence could not occur, because the audit had misread render-scratch
  and single-type buffers. Closed as NOT-A-BUG. **Wrong in the direction of alarm.**
- **#11** described a crash on a malformed save. True for every shape it enumerated — but
  for `player_inventory` the reality was silent truncation with a zero skip-count.
  **Wrong in the direction of comfort**, and marked CLOSED on a fix that addressed every
  mechanism the title named while the stated consequence stayed reachable. Its row now
  cites two commits and says the first closure was premature.

Both passed 1-2 independent skeptic passes instructed to REFUTE. **Adversarial verification
confirms that something is there. It does not confirm what shape it is.**

**⚠ THE PRESCRIBED FIX IS THE LEAST-VERIFIED PART OF ANY FINDING.** Not "a hypothesis to
sanity-check" — the *weakest* section of the entry, and the one most likely to do harm.

Rank the parts of a finding by how close their author stood to the code. The **evidence
block** is quoted source. The **verification notes** were written by a skeptic trying to
refute. The **description** is one author's reading. The **fix text** is the furthest out:
prose about code that does not exist yet, written by someone who **never executed any of
it** — not against this engine, this Godot version, or this harness.

**Two prescriptions this session would have shipped a bug worse than the finding:**

- **#22** prescribed recording `Engine.get_process_frames()` to suppress a double-action.
  `get_process_frames()` returns **0 for an entire headless run**, so a stamp of 0 compares
  equal forever and the guard would have **wedged the Esc chain shut permanently**.
- **#35** prescribed deleting NOTES entries once the work ships. That would have silently
  removed live forward-looking tails — including **#34's own split trigger**, which lives
  inside a section headed "Dev Console — SHIPPED", and the `MIGRATIONS` split trigger inside
  "Schema-mismatch UX — both fixes SHIPPED". Obeyed as written, it would have deleted the
  trigger that #34 exists to report as breached.

Both were prescribed by the audit. Both were worse than the defect they closed. Neither was
detectable by reading — only by checking the prescription's assumptions against the running
system.

**So: treat the fix text as one hypothesis among several, never as the spec.** Read it for
what its author noticed, then decide the fix yourself from the evidence. This session has
departed from the prescription in **#7, #12, #21, #22, #33 and #35** — six of the ones
actually attempted. Departure is the norm here, not the exception, and **~54 findings remain,
each carrying a prescription with the same provenance**. Record every departure loudly
enough that a future reader does not "restore" it.

### A severity claim is a claim about a consequence — and inherits the same provenance

**#19 is the worked example, and the bad claim was one I wrote.** Early in the re-application
session I recorded a mis-rating note in the tracker: #19 is rated MEDIUM but "the outcome is
item duplication or destruction depending on which side of the bypass you land on", which is
HIGH-shaped. I then repeated it in briefs as established fact.

**Measured: neither happens.** Item accounting across a full-chest overfill is **2450 before,
2450 after** — one leaves the source, one arrives at the destination. Nothing is duplicated
and nothing is destroyed. The real behaviour is the third option nobody named: items are
**stored past a soft cap**, so an inserter-fed chest becomes an infinite sink and backpressure
never arrives. That is workflow-level, and **MEDIUM was right all along**.

Severity is not metadata. **It is a compressed claim about a consequence**, and it comes from
the same place a fix text does — someone reasoning about code they did not run. "Duplication
or destruction" was written from the shape of the bypass, not from counting items. Re-rate by
**measuring the outcome**, and when you overturn a rating, replace the old note rather than
appending to it, so the next reader hits the correction before the claim.

(The audit did miss one genuine destruction path here, in a place it never looked: a chest
whose state has no `"bag"` key. `state.get("bag", [])` returns the *default literal*, so the
append lands in a temporary and the item is discarded. Closed incidentally by delegating to
`Chest.try_insert`, which repairs the shape through `Chest._bag`.)

### ⚠ FIXES ARE NOT MONOTONE — the intermediate state can be worse than either endpoint

Same finding, mutation M1: delegate to `Chest.try_insert` **but keep `return true`**.
Measured: conservation breaks, **2450 → 2441, nine items destroyed**.

Read the three states in order. **Unfixed:** the chest overfills, every item still exists.
**Half-fixed:** `try_insert` refuses at capacity and returns false, but the caller reports
success anyway, so the arm clears a held item that was never stored — **silent deletion**.
**Fixed:** the refusal propagates, the arm blocks, nothing is lost.

The midpoint is worse than the start. "Some of the fix" is not "some of the benefit", and a
partial application moved this defect *into* the destruction class the finding wrongly
claimed it was already in.

**This changes what a mutation pass is for.** The habitual question is "does removing this
line redden something" — a check that the guard is load-bearing. That is necessary and not
sufficient. The other question is **"is every intermediate state of this change safe?"**,
because the half-states are reachable: by an interrupted edit, by a partial revert, by a
merge that takes one hunk of two, by a future reader who deletes what looks like a redundant
line.

So mutate **toward** the fix as well as away from it. For any change with more than one
moving part, construct the partial applications and check them — M1 exists precisely because
that half-state is one plausible edit away, and nothing else in the suite would have caught
it. Where a partial state is genuinely unsafe, say so in the retention comment: "these two
lines land together" is information a future editor cannot derive.

### ⚠ Never shift a citation by arithmetic — a known-good delta on an unverified number produces a wrong number that looks verified

**#16's fix inserted a method at `grid_world.gd:494`, shifting every citation below it by
exactly +39.** Rows #17, #29, #30, #31 and #32 all point into that range. The obvious move
is to add 39 to each and move on. **Do not.**

The delta is correct. The inputs are not. Several of those rows were **already stale by an
unmeasured amount** before the insertion — the document even contradicted itself about one,
with #30's row saying the terrain loop is at `:1598` while a cost note said `:1619`. The
truth, re-derived, is **`:1658`**.

Apply `old + 39` to a number that was already wrong and you get a number that is still
wrong, now carrying the appearance of having been maintained. **The arithmetic launders the
staleness**: a reader sees a recently-updated figure and stops checking. That is strictly
worse than leaving the old number, which at least looks its age.

**The rule: re-derive, or warn. Never arithmetic.** If you have time to re-derive the rows
you disturbed, do that. If you do not, write a warning block saying *"every `<file>`
citation below line N shifted by +D on <date>; re-derive before use"* — which is honest
about exactly what is and is not known. What was done here: a `+39` warning block above the
MEDIUM table, plus one row re-derived because it had been measured.

The general form is the currency/consistency distinction from the tracker's header, one
level down: **a transformation applied to an unverified value yields an unverified value,
however sound the transformation.** Confidence does not propagate through arithmetic; only
measurement creates it.

### Findings carry stale COSTS as well as stale citations — re-derive both

**#34 is the worked example, and it is the shape that commits a session to work it never
scoped.** Its fix text estimates *"~30-min refactor when triggered"* for splitting
`console.gd`. That number was written when the file was **657 lines**. It is now **1127**.

Worse, the estimate measures only the mechanical move, and the prescribed two-file cut
**is not achievable as written**: `execute` dispatches via `Callable(self, entry["fn"])`, so
every `_cmd_*` must live on the same object as the registry — a plain `RefCounted` helper
cannot hold them. Four things straddle the seam the plan does not mention, and 20 static
call sites across three test files move with it.

A finding that *looks* cheap and is not is more dangerous than one that looks expensive,
because it gets picked up as filler at the end of a session and then cannot be put down
cleanly. **Re-derive the cost the way you re-derive the citation** — before committing to a
batch size, not after. Cheapness is a claim in the entry, and it ages exactly like a line
number.


**⚠ A reproduction must be verified to exercise the mechanism before its result is
trusted.** A repro that produces nothing is indistinguishable from a fixed bug — the same
absence-equals-success shape, relocated into the verification step itself.

Cluster G, #23, measured: the building proposed for the repro was SMELTER, chosen because
it is 2×2. But `SMELTER`'s `requires_overlay` includes `Terrain.Overlay.NONE`, so it
places on bare grass directly and **the auto-overlay code path never runs**. Following that
brief would have produced silence, and the silence would have read as "the finding is
closed". The buildings that actually exercise it are MIXER / OVEN / PROOFER / PACKAGER —
2×2 *and* overlay-requiring. With MIXER both halves of the finding reproduce and compound.

So the check has two steps, not one: **first confirm the case reaches the code, then read
what it does.** Print from inside the branch, assert a precondition, or mutate the
mechanism and watch the repro change — a repro whose result does not move when you break
the thing it targets was never testing it.

**⚠ Reproduce the TITLE, not just the paragraph. The title is the claim; the paragraph is
one author's account of it.** The audit's sections were written by different passes, and
across ~60 remaining findings they carry this structure throughout — title, description,
evidence, fix text and verification notes are five accounts that can disagree about what
the defect is. A description that does not reproduce is evidence about *that account*, not
about the finding. Read the whole entry, and hold the title as the thing to be shown true
or false.

Cluster C, #18 is the worked example. Its title is "`STATE_NO_FUEL` has no fallback — smelter wedges
with fuel available". The *description* points at the NO_FUEL arm, which re-checks and
restarts correctly; on that basis the finding was nearly written off as false. But its
**fix text** names a third route: `SMELTER`'s `slot_layout` binds an `"input"` slot to
`in_buffer`, so `BuildingPanel._take_from_slot` can empty a stalled smelter from the panel.
Measured: 400 ticks, `fuel_buffer` 8, four copper ore untouched on the belt, status
"NO FUEL" — the title, word for word, by a mechanism the description never mentions.

**⚠ A THIRD CLASS, and the running ratio (as of 2026-08-26).**

**WRONG-BY-SUPERVENING-DECISION** — a prescription that was *correct when written* and was
invalidated by a decision taken later. #32's move-to-tick item is the first instance: sound
under the audit's premises, forbidden the day #31 closed WONTFIX and pinned the three
systems to wall-clock. Nothing about the prescription's own text betrays this — it reads as
well today as the day it was written — **the tracker is the only thing that would tell
you.** So prescription verification now has a third question alongside "does it run in this
environment" and "what does it not assert": **"has any decision since made this
forbidden?"** The decisions that have already changed what is permissible since the audit
was written: the R1/#31 WONTFIX (no re-clocking soil/fertilizer/regrowth), the #16
extraction (the hover predicate is a tested method now, not an inline block), and the #21
narrowing (fresh-world fallthrough is sanctioned for two of its three cases).

**The ledger, with provenance (each classification is recorded in the tracker at its
finding):** RIGHT — #29 (taken nearly as written), #28 (its Fix section had already been
corrected in place), #38 (verified correct during its cost-check, unimplemented). WRONG —
#22 (permanent wedge), #35 (deletes live triggers), #16 (untestable as prescribed), #26/R5
(correct given its premise; the premise was a wrong comment), #7 (would have made wasteland
organically unreachable), #32's item 3 (supervening, above). SHORT — #25 (blind to
`time_ticks`), #32's items 1/2/4 (improve the cited 23-32% while the dominant cost is
unreachable). PARTIAL — #12 (its `error_message` signalling was unimplementable under the
API's own convention), #21 (over-broad, narrowed on its own conventions).

Counted over the prescriptions actually put to the test: **roughly one in three survived
contact unchanged.** The exact fraction moves with how you bucket the partials — the
stable conclusion is that **following a fix text unverified is a coin flip weighted
against you**, and 46 findings remain, every one carrying a prescription written before
all three of the decisions above.

**⚠ TWO PRESCRIPTION CLASSES — and the short one is more dangerous than the wrong one.**

- **WRONG prescriptions** — #22 (frame stamp that wedges the Esc chain), #35 (delete-on-ship
  that removes live triggers), #16 (untestable-in-place swap), R5 (12-slot path that fails
  against correct code). Each ships something broken and **produces a symptom**: a red test,
  a wedged chain, a missing trigger someone eventually reaches for. The failure announces
  itself, sooner or later, because something observable is worse than before.
- **SHORT prescriptions** — #25. Not wrong: everything it prescribes is correct. It is
  incomplete. A suite built exactly to its shape (pre-load N cycles, tick to a budget,
  assert exact final counts) came back RED on four table mutations and **GREEN on
  `time_ticks`** — halve a recipe's duration and the final counts are identical, so nothing
  sees it. That suite ships **green**, the finding is marked closed, and the defect class it
  was written to lock is intact. **No symptom, ever.** Nothing observable is worse; there is
  simply a hole where coverage is recorded as existing.

**A wrong prescription fails loudly. A short one closes the row.** The wrong kind costs a
session; the short kind costs the belief that the finding is handled, which is
open-endedly worse because nothing prompts anyone to look again — the row says CLOSED, the
suite says green, and both are truthful about everything except the gap.

Closing #25's gap needed two per-row samples at tick N·T−1 and N·T — derived from
`Processor.tick`'s state machine, not from observing a run.

**Practical consequence, applying to every remaining finding whose prescription is a
test:** before accepting the prescribed shape, ask **"what mutation would this shape not
catch?"** — and answer it concretely, against the data or behaviour the finding claims to
lock. #25's answer was `time_ticks`, and nothing in the prescribed form would ever have
surfaced it. If the answer is "none I can construct", say so; if there is one, the
prescription is short and the missing assertion is part of the fix.

**⚠ A finding inherits the errors of the DOCUMENTATION it was written from — and then
carries them with the audit's authority.**

Three of this session's bad prescriptions were flawed at the prescription: #22's frame stamp,
#35's delete-on-ship, #16's untestable-in-place swap. **R5 is a different kind.** #26's fix
text was *correct given its premise*. The premise was a wrong comment in the code it
described.

`belt.gd:6-7` said "Items advance one slot per belt tick", unqualified. #26 read it, believed
it, and prescribed asserting a **"12 slots total path"**. Measured, an item traverses **11**
slots in 9 advance ticks — `0, 1, 2, 4, 5, 6, 8, 9, 10, 11`, with 3 and 7 never appearing,
because Pass 1 moves an item into a front slot and Pass 2 of the *same* tick hands it across.
**A test written faithfully to the prescription fails against working code.** #26 also names
the wrong hazard: the double-move it warns about cannot happen; the real one is slot N−2 →
front → next belt.

**The diagnostic rule: when a prescription fails against working code, suspect the comment it
was derived from before suspecting the code.** A static-read audit reads comments as evidence
— it has little else — so a wrong comment does not stay local. It propagates into every
finding written about that code, and arrives wearing the audit's authority rather than the
comment's.

**What this means for what is left.** 49 findings remain open. Every one was produced by
reading code and comments, and **the comments are demonstrably unreliable** — that is what a
large part of the LOW tier is *about*, which makes the input to the audit and one of its
outputs the same defect class. So a finding that will not reproduce is three hypotheses, not
one: the code changed, the finding was wrong, **or the comment it trusted was wrong**. Check
the third before concluding either of the first two, and when it is the third, fix the
comment as well as the finding — otherwise the next reader derives the same error from the
same source.

**⚠ And the entry is VERSIONED — a claim about a finding is not part of the finding.**

Corrections land in one section and not the others, so a section can be stale *relative to
its own document* — including stale because we edited a neighbouring section and not it.

**Measured, twice, and both were mine:**

- **#19's severity.** I wrote that its outcome is "item duplication or destruction",
  called it HIGH-shaped, and repeated it across briefs as settled. Conservation holds
  exactly: 2450 items before, 2450 after. Neither happens.
- **#28's prescription.** I briefed an implementer that the prescribed fix was "**known to
  be wrong**, and the audit says so itself". The Fix paragraph had **already been rewritten
  to the corrected version**; only the verification note still carried the wrong one, as
  the thing being corrected. I was quoting an earlier session's *report about* the entry
  instead of the entry.

**The tell, which is the operative part: once "the cost-check found X" becomes "X",
provenance is gone and nothing prompts a re-check.** Both claims were derived once,
correctly caveated at the time, and then restated as fact in the next brief — at which
point they read as properties of the codebase rather than as somebody's measurement with a
date on it. Nothing about a bare assertion invites re-derivation. That is the whole
mechanism, and it is entirely upstream of whether the original derivation was any good.

**The practice: when carrying a claim about a finding into a brief, carry where it came
from — or re-derive it.** "The cost-check on 2026-08-25 measured X" survives contact with a
reader who can check it. "X" does not. Re-read the entry at dispatch; never brief from a
previous brief.


**In practice:** before closing an inherited finding, construct the failure the finding
describes and watch it happen. If the reproduction does not match the description, *the
mismatch is the finding* — record it before fixing it, because it tells you the severity
was assigned from the wrong facts. This applies to all 68 findings still live in
`docs/audits/2026-07-19-flaw-review.md`.

Related: the STATUS RULE at the top of that document (a status claim describes what shipped
on `main`, verified by commit) governs the *closing* half; this protocol governs the
*opening* half.

## Protocol: locked architectural decisions can be reversed by reconnaissance findings

**Codified at session-building-ui-4** after the third project-level architectural reversal. Extended at session-soil-exhaustion-2 with the playtest-gate addition.

**Pattern:** when the user (or a prior design pass) locks in an architectural decision before implementation, and the implementation includes a "verify before code" reconnaissance step, the audit can produce findings that invalidate the locked decision's premise. **Reversing during the design-pass writeup is correct.** It's cheaper than shipping the bad abstraction and removing it later (10× cost differential at typical session-cascade depth).

**Six reversals so far:**
1. **`session-mining-manual` — deposit-overlay rule reversal.** Original: "overlay obscures deposit, RMB-clear reveals." Reversed to: "overlay placement BLOCKED on deposits." The UX trap (player accidentally paves over and loses the deposit) was visible in playtest within minutes.
2. **`session-building-ui-3` — fluid_indicator extracted to shared helper BEFORE ProcessorPanel extension.** User pushback added a 3a→3b→3c sequencing: extract from MixerPanel first, refactor MixerPanel to use shared, THEN extend ProcessorPanel. Avoided two divergent fluid renderers.
3. **`session-building-ui-4` — ExtractionPanel intermediate deferred.** Reconnaissance found harvester (3×3 coverage) and planter (no coverage, int-typed output) share <30% layout. Forcing them into one base class would mean "if-has-coverage" branches with no real abstraction value.
4. **`session-soil-exhaustion-1` (in-flight Session 2 attempt) — region-regen partial work salvaged, region-scoped logic rewritten.** Mid-session pivot from region-regen to per-tile rewrite preserved scope-agnostic UI scaffolding (~30 lines).
5. **`session-soil-exhaustion-2` — region-based soil → per-tile soil.** **The most expensive reversal in the project.** Region scope (32×32 = 1024 tiles per planter) decoupled cause from effect; player UX in playtest was disconnected. Per-tile (3×3 = 9 tiles) localizes the effect. Caught ~1 hour after Session 1 ship; would have cascaded across Sessions 3-5 (fertilizer chain, wasteland, legumes — all fundamentally different under per-tile vs region scope). Estimated 10× cost if caught later.
6. **`session-zoom-to-map` — separate-render approach → wheel-trigger of existing M-key modal.** ~2 sessions of work fully discarded (`MapBackdrop` Node2D + cross-fade alpha math + dynamic resolution-independent `_zoom_min()` + click-to-pan with smooth lerp + click-vs-drag distinction + dual-texture plan). Replaced with ~30 lines: at the existing zoom floor, one more wheel-down opens the existing M-key modal. Triggered by user clarification at PAUSE 2 manual smoke after diagnostic instrumentation confirmed the cross-fade math was correct but solving the wrong problem. Discarded cleanly via `git restore . && git clean -fd` from clean HEAD; zero salvage attempted because every line of the discarded work encoded the wrong abstraction. **Lesson surfaced:** "exactly like Factorio" is a reference, not a spec — see `Protocol: unpack reference-style requirements before design pass` below.

**Protocol:**
- Always honor a "verify before implementation" step in the implementation order — don't skip it.
- If the audit reveals the locked decision's premise is wrong, **reverse during the design-pass writeup, not silently in code.**
- Document the reversal explicitly in PROJECT_LOG with the audit findings as evidence.
- Cost to reverse during writeup: ~10 minutes. Cost to ship-then-remove a bad abstraction: hours-to-days.

If a reversal feels expensive (e.g., the user pre-committed publicly to the original choice), that's a smell that the audit step was treated as ceremony rather than gate. The audit IS the gate.

---

## Protocol: unpack reference-style requirements before design pass

**Codified at session-zoom-to-map** after reversal #6 (separate-render zoom-to-map → wheel-trigger of M-key modal). ~2 sessions of work fully discarded.

**Pattern:** when a feature is described with a reference rather than a behavioral specification — phrases like "exactly like Factorio," "like Minecraft does it," "the way most games handle this" — there's a hidden ambiguity. The reference compresses a large mental model into a few words; the listener decompresses with their own mental model, which is rarely identical to the speaker's. Both parties feel aligned because the phrase "exactly like X" sounds precise. It isn't. **Reference-style phrasing always preserves the speaker's escape hatch ("oh, that's not what I meant").**

**Concrete example — session-zoom-to-map:** the user wanted "wheel-out triggers the existing M-key map modal" (an alternate input route to a known surface). The implementer's mental model for "exactly like Factorio's zoom-to-map" was a continuous cross-fade rendering between world view and a baked-texture map view. Both were locally consistent with "exactly like Factorio." The reversal cost: ~2 sessions of work + diagnostic effort + a full discard.

**Protocol — when the user uses reference-style phrasing:**

The next response MUST be specific behavioral verification BEFORE any design pass. Concretely:

1. Refuse to do a design pass on the reference alone. Don't say "great, here's the design pass for our 'exactly like Factorio' zoom feature."
2. Ask for **frame-by-frame description**: "Tell me the exact sequence of inputs and what should happen at each step. What does the player press / scroll / click? What changes on screen? What state does the game enter?"
3. Pin down the EXIT condition: "How does the player get OUT of this state?" (Often the most diagnostic question — separate-render zoom-to-map had no clear exit; wheel-trigger has wheel-up.)
4. Pin down the GATING: "What ELSE is happening — can the player still move? Place buildings? See the world?"
5. Only after the behavioral spec is clear: design pass.

**Smell test for reference-style requirements:**
- Phrases that compress a feature into a citation: "like Factorio," "the way Minecraft does it," "exactly how Diablo handles inventory," "standard MMO targeting."
- Phrases that name a feel rather than a behavior: "make it feel polished," "the usual zoom-out experience."
- Phrases that name a system without scoping: "add a tech tree," "a research mechanic."

**When reference-style phrasing is OK:**
- The reference is a tightening constraint on an already-clear spec ("the placement preview should ghost the building like Factorio does — half-alpha, color-tinted by validity").
- The reference is to a feature that exists in this codebase already ("wire it up like the existing M-key map modal").
- The reference is in a "how" not a "what" ("use the same lerp-rate as the camera smooth-zoom").

In all OK cases, the spec already exists or the reference points to in-codebase behavior. The dangerous form is reference-as-spec: when the entire feature definition relies on the listener's interpretation of the reference.

**Failure mode of skipping this protocol:** the listener does the design pass with their own mental model of the reference, the user nods because "exactly like X" sounds right to them too, implementation ships, playtest reveals the divergence. By that point, the cost is sunk. **Cost of unpacking the reference upfront: 5–15 minutes of dialogue. Cost of NOT unpacking: ~2 sessions of dead work in the worst case (reversal #6 evidence).**

---

## Protocol: manual mechanic before automation (within an arc)

**Codified at session-soil-exhaustion-3** after the second instance of the pattern. Earlier instance: `session-mining-manual` (Spacebar-to-mine-while-adjacent) shipped before `session-mining-drill` (Mining Drill building automates extraction). Soil arc applies the same pattern: `session-soil-exhaustion-3` ships hand-apply fertilizer; Fertilizer Applicator deferred to Session 3.5 / 4.

**Pattern:** when a session's scope contains BOTH a foundational mechanic AND its automation, ship the foundational mechanic alone first. Automation lands in the next session. Two sessions instead of one — but each smaller, each individually validatable, and the foundation gets playtested before automation builds on top of it.

**Why this works:**

1. **Playtest reveals foundation issues.** Hand-apply fertilizer in Session 3 might reveal "the boost is too short" or "the stacking rules feel wrong." If we'd built the Applicator on top of those rules in the same session, the rework cost would multiply. With separate sessions, we can adjust the foundation without unwinding the automation layer.
2. **Scope discipline.** A session that ships "manual + automation" almost always over-runs and gets mid-session-cut anyway. Pre-cutting at design pass is cheaper than mid-session triage. The cut is RECOVERED in the next session, not lost.
3. **Each session has a clear ship moment.** "Hand-apply fertilizer works" is a coherent, testable, demoable session. "Hand-apply + Applicator" is a longer session whose ship moment is fuzzier ("automation works for the simple case, breaks edge case X").
4. **The foundational mechanic teaches the player BEFORE the automation hides it.** Player learns "compost tiles to boost regen" by hand-applying. Then Applicator becomes "the thing that does what I was doing manually," not "a new mysterious building."

**Protocol:**

- At design-pass time, scan the proposed scope for "automation of a new manual mechanic." If both are present, propose splitting at design pass.
- The split is: ship the manual mechanic this session; defer automation to a follow-up.
- Document in PROJECT_LOG that automation was deferred + WHY (not as scope creep — as deliberate manual-before-automation discipline).
- The follow-up session is small (~30–80% of the original scope's automation portion) because the foundation is already in place. Don't underestimate it, but don't oversell it either.

**Three instances so far:**
1. **Mining arc:** `session-mining-manual` (Spacebar-to-mine, ore drains from deposits adjacent to player) → `session-mining-drill` (1×1 building auto-extracts from coverage). Worked perfectly.
2. **Soil arc — fertilizer:** `session-soil-exhaustion-3` (hand-apply fertilizer via NEW item_apply hotbar kind) → `session-soil-exhaustion-3-5` (Fertilizer Applicator: 5×5 coverage, belt-fed, tier-preference, most-depleted-first targeting). Worked perfectly. By 3.5, the per-tile fertilizer state was already validated by ~2 hours of Session 3 playtest — automation just plumbed onto a known-good foundation.

**Pattern observation across the three instances:** each session is incrementally smoother than the last. By the third instance, the design pass writes itself (most decisions inherit from the manual mechanic) and the automation session is mostly plumbing. **The pattern earns its keep specifically when the manual mechanic has design uncertainty** — if the foundation might need adjustment after playtest, building automation on top first means double the rework. With three confirmed wins, treat this as the default for any "manual + automation in same scope" proposal.

**When NOT to apply this pattern:**
- The "automation" is a trivial wrapper around the manual (e.g., a hotkey for what would otherwise require multiple clicks). Ship in the same session.
- The "manual mechanic" is too painful to use without automation (e.g., manual belt-by-belt routing of every item in a factory). Ship together; the manual is just the spec for the automation.
- Both are tiny (e.g., `manual = 2 clicks per use`, `automation = 1-line config flag`). Ship together; splitting is more ceremony than the work.

**Failure mode:** trying to ship both in one session, hitting scope creep at PAUSE time, then choosing between (a) shipping only the manual and pretending the automation was always Session N+1, or (b) shipping both half-done. Either is worse than the pre-cut.

---

## Protocol: playtest gates between foundational sessions

**Codified at session-soil-exhaustion-2** after reversal #5 (region-based soil → per-tile).

**Pattern:** design passes can verify *correctness* of an architecture, but not *fit* with how it actually plays. Region-based soil was internally consistent and well-specified — it just felt wrong when played. **Playtest is the gate that catches scope errors design doesn't.**

**Protocol:**
- After a foundational session ships, **play 30+ minutes** before approving the design pass for any dependent session.
- "Foundational" means: introduces a new mechanic that future sessions will build on (e.g., soil-exhaustion-1 was foundational for sessions 2-5; building-ui-1 was foundational for sessions 2-4).
- During the 30 min: actually USE the mechanic. Watch how it FEELS. Pay attention to "this doesn't quite work" sensations even when nothing's broken.
- Surface any feel-disconnect findings BEFORE the next session's design pass. The cost of catching scope errors at session N+1 is always lower than at N+3.

**Example application — soil-exhaustion arc:**
- Session 1 (region) shipped at ~morning.
- Playtest revealed disconnect within 30 min (one harvest, no visible effect).
- Session 2 design pass kicked off ~1 hour after Session 1 ship — flagged the reversal in re-orientation.
- Session 2 implemented the per-tile refactor instead of regen-on-region.

**When to skip the gate:** sessions that don't introduce new mechanics (e.g., UI polish, additional building panels, test refactors). The playtest gate applies specifically to *foundational* sessions.

**Failure mode:** skipping the playtest gate because "the design feels right." Reversal #5 originated from a Session 1 design that felt right at design-pass time. Playtest disagreed. Trust the playtest.

---

## Click-handling duplication (BuildingPanel ↔ inventory_grid)

**Status:** still 2 implementations after session-building-ui-3. Audit verified at session 3 design pass: ChestPanel overrides `_gui_input` for hit-test routing only; calls `_handle_player_slot_click` from BuildingPanel base unchanged. No third copy exists.

**Why still NOT extracted:**
- True duplication count is 2, hasn't grown since Session 1. The 14 BuildingPanel subclasses (after Sessions 1+2+3) all *inherit* one implementation; they don't duplicate it.
- Extracting now produces a 25-line static helper that saves ~50 lines. Modest. Risk: an abstraction that doesn't fit a future divergence (e.g., right-click half-stack might want different player-slot vs building-slot behavior).

**Refined trigger criteria** (replacing the original "4+ consumers" wording):
- **Third *implementation* of the click logic appears** (not a subclass — a genuine new copy of pick/place/combine/swap).
- **New behavior added that requires both call sites to be updated identically** (e.g., right-click half-stack, shift-click bulk transfer in modals).
- **Player-slot click logic genuinely diverges between modals** (one modal needs different semantics, current logic is identical).

When any one fires: extract to `CursorStack.click_swap(slot, cursor) -> void` or `SlotWidget.handle_click(slot_provider, cursor)`.

---

## Building Interaction UI — multi-session arc **COMPLETE** (Sessions 1+2+3+4 shipped)

**Status:** **All 4 sessions SHIPPED.** Every interactive building in the game has a specialized UI panel. Only passive infrastructure (Pipe/Pump/Belt) remains UI-less, by design.

**14 specialized panels:**
- Session 1: SmelterPanel, DrillPanel
- Session 2: ChestPanel, MillPanel, OvenPanel, ProoferPanel, PackagerPanel, MixerPanel
- Session 3: LoomPanel, TailorPanel, BriquetterPanel, SugarPressPanel, RetterPanel, YeastCulturePanel
- Session 4: ThresherPanel (catch-up), PlanterPanel (handles 3 variants), HarvesterPanel

**Final reuse milestones:**
- **ProcessorPanel: 11 consumers** (Mill, Oven, Proofer, Packager, Loom, Tailor, Briquetter, Sugar Press, Retter, Yeast Culture, Thresher) — all 5–10 line `extends ProcessorPanel` subclasses with no overrides.
- **`draw_fluid_indicator` shared helper**: 3 consumers (Mixer, Retter, Yeast Culture).
- **`output_multi` slot kind**: 2 consumers (Drill, Harvester).
- **`fluid_indicator` slot kind**: 3 consumers (Mixer, Retter, Yeast Culture).

**Future UI work** (not part of the arc):
- Polish (deferred to playtest feedback): right-click half-stack, true mouse drag, panel transitions.
- New buildings: future processors inherit ProcessorPanel automatically (~10 lines per new building).
- SmelterPanel + DrillPanel still standalone (predate ProcessorPanel) — could migrate in a future polish session if divergence becomes painful. Not currently painful.

### What's shipped (sessions 1+2)

**Foundation (session-building-ui-1):**
- `scripts/ui/cursor_stack.gd` — shared cursor object, persists across modals, serializes to `player_progression["cursor"]`.
- `scripts/ui/slot_widget.gd` — extracted slot rendering (used by inventory_grid + every building panel). Now also hosts the `chest_bag_to_slot_views` adapter (moved from inventory_grid at session 2).
- `scripts/ui/building_panel.gd` — base class with modal lifecycle, drag-drop, kind-validation (input/output/fuel/output_multi/chest_bag/fluid_indicator), lossy fuel take-back, player inventory render at bottom. `_top_area_height()` virtual hook for subclasses needing taller panels.
- `Buildings.slot_layout_for(t)` + `has_interaction_ui(t)` data registry.
- Hotbar `has_selection()` / `clear_selection()` + neutral visual.
- `main.gd` Esc priority chain + click-to-open dispatch + Manhattan-1 adjacency check + cursor save/load.
- Multi-tile hover rect.

**Session 1 panels:**
- `scripts/ui/smelter_panel.gd` — flow layout with progress bar, fuel slot.
- `scripts/ui/drill_panel.gd` — coverage 2×2, multi-output sub-slots, fuel slot.

**Session 2 panels:**
- `scripts/ui/processor_panel.gd` — intermediate base for Mill/Proofer/Packager/Oven (~10 lines each as subclass).
- `scripts/ui/chest_panel.gd` — bulk-storage 6×4 grid + capacity header. Replaces old inventory_grid paired-view (removed ~150 lines from inventory_grid.gd).
- `scripts/ui/mill_panel.gd` / `proofer_panel.gd` / `packager_panel.gd` / `oven_panel.gd` — each `extends ProcessorPanel` with no overrides. Slot_layout in Buildings.DATA drives rendering.
- `scripts/ui/mixer_panel.gd` — extends BuildingPanel directly; 2 solid inputs side-by-side + fluid indicator + output.
- E-key unified: opens building UI for any adjacent building with `has_interaction_ui`; falls back to drain for legacy harvester.

**Tests: 24/24 passing.** Tests cover all 4 sessions' invariants — cursor stack, slot_layout shapes, hotbar selection, click resolution, drag-drop semantics, ChestPanel pick/drop, multi-input dispatch (oven), mixer fluid indicator, E-key adjacency scan, ProcessorPanel reuse milestones (10 → 11 consumers), planter int-typed-output handling, harvester coverage scan, and the **arc-COMPLETE check** (every interactive building has a UI; only Pipe/Pump/Belt are UI-less).

### Cross-cutting follow-ups (deferred)

- **Right-click half-stack** in building slots — building UI v2 polish.
- **Animations / transitions** for modal open/close — defer.
- **Drag-and-drop visual** — currently click-to-pickup, click-to-place. Real mouse drag (button-down + move + button-up) may feel more natural; defer until playtest confirms the click pattern is unwieldy.
- **SmelterPanel + DrillPanel migration to ProcessorPanel-style** — they predate the intermediate class. Could refactor if divergence becomes painful. Not currently painful.

### Hooks shipped (final tally)

- `Buildings.slot_layout_for(t)` + `has_interaction_ui(t)` — data registry.
- `BuildingPanel` base (~400 lines): modal lifecycle, drag-drop, kind-validation, `draw_fluid_indicator` helper, player inventory render.
- `ProcessorPanel` intermediate (~230 lines): 11 consumers via pure `extends`.
- `CursorStack` shared object (one instance, all modals).
- `SlotWidget` static helper: slot rendering + chest-bag adapter.
- Esc priority chain in main.gd.
- E-key unified dispatch — opens building UI for any adjacent building with `has_interaction_ui`.

---

## Tile passability system (post-mining-manual)

**Status:** shipped at `session-mining-manual`. `Tile.is_passable() -> bool` is the generic blocker check. Today only water blocks; player movement uses per-axis sliding via `Player._move_with_passability(delta)`.

**Foundation for future blocker types:**
- **Cliffs / elevation barriers** — a future `Tile.cliff: bool` field or a `Terrain.Base.CLIFF` enum value with `is_passable() = false`. Player can't walk off a cliff edge; future ladder/ramp buildings allow traversal.
- **Walls** — placeable building or terrain that blocks movement. `tile.has_wall: bool` field, `is_passable()` returns false. Player walks around. Doors are walls with a `passable_when_open` flag.
- **Structures** — large buildings could mark their footprint cells as impassable so player walks around them rather than through. Today buildings don't block movement (player walks through them visually, which is a small UX wart).

**Why generic `is_passable()` over specific `is_water()`:**
- Future blocker types add their own logic to `Tile.is_passable()` rather than touching player movement code
- Per-axis sliding logic in `Player._move_with_passability` doesn't care WHY a tile blocks; works for any combination of blockers
- New blocker = override one method, no other code changes needed

**Don't pre-build:**
- Wall buildings, cliff terrain, ladder mechanics — wait for them to be needed in actual gameplay before scaffolding
- Save format implications — adding fields to Tile is a schema bump; do it when the feature lands, not pre-emptively

---

## Map polish (post-explore-map session)

**Status:** the M-key fullscreen map + minimap shipped at `session-explore-map`. Three-state visibility (unrevealed / fog / active), drag-pan, region-level fog tracking, save persistence — all live. What remains is polish.

**Deferred items captured during the session:**

- **Mouse-wheel zoom on M-map.** Currently fixed at the auto-computed display scale. Wheel could zoom in (smaller area, more detail) or out (whole world more visible). Pan-clamp adjusts naturally. ~30 min of work.
- **Map markers / waypoints.** Right-click on map to drop a marker; visible on M-map and minimap. Persists in save. Useful when the player has scattered outposts to remember. v2 feature; no architectural blocker.
- **Click-to-pan-from-minimap.** Right now minimap is `MOUSE_FILTER_IGNORE` (passive). Could open M-map at clicked position. Mild scope creep; defer until "I want to see X area" becomes a real friction.
- **Facing-direction arrow on player marker.** Currently a dot. Player has no `facing` state today; would need to derive from velocity or track explicitly. Defer until needed.
- **Fog-vs-active visual distinction beyond brightness.** 0.45 brightness multiplier reads but is subtle. Could add a desaturation overlay or animated edge for clearer "this is current vision." Wait for playtest feedback before tuning.

**Radar buildings (Stage 2 of exploration):** the architecture supports them trivially. A radar building's tick (or place-time) hook would call `world.region_visibility[r] = 1` for the regions it covers. Visual would be a different state (maybe value = 3 = "remote-revealed") if we want to distinguish player-explored from radar-revealed. Out of scope for Stage 1; designed for when bigger maps make this gameplay-meaningful.

---

## Tooling: godot-mcp (installed, capability honestly documented)

- **Repo:** [satelliteoflove/godot-mcp](https://github.com/satelliteoflove/godot-mcp), addon version **2.17.0**.
- **Status:** installed and connected. Capabilities and limitations characterized via direct verification. **Smaller win than the original install plan claimed; documentation below is the truthful version.**

### What MCP **CAN** do (confirmed by verification)

| Capability | Tool / action | Notes |
|---|---|---|
| Capture a screenshot of the running game | `editor screenshot_game` | **The only confirmed live-state path.** Returns a real PNG of the running Godot window — visible HUD, real-time tick count, current player position, building visuals. Solves the original "I can't see the screen" debugging problem at the visual level. |
| Run / stop the project | `editor run`, `editor stop` | Launches the game from the editor and reports `is_playing` via `editor get_state`. |
| Read the editor's loaded scene tree | `node find`, `node get_properties` | Returns built-in Godot properties (position, scale, modulate, etc.) and `@export`-annotated script vars **at their authored scene-file default values** — see caveat below. |
| Look up Godot API documentation | `godot_docs` | Search/lookup against the engine's docs; useful for "how does Camera2D.zoom work" type queries. |
| Control the editor's 2D viewport | `editor set_viewport_2d` | Pan/zoom the editor view (not the running game). |
| Editor-side selection / scene editing | `node create / update / delete / reparent`, `scene open / save / create` | Authoring tools — useful for tooling/automation, irrelevant to live-state debugging. |

### What MCP **CANNOT** do (confirmed by failed verification attempts)

| Capability we wanted | Tool that should have worked | What actually happened |
|---|---|---|
| Read live game state (variables in the running game process) | `node get_properties` on `/root/Main` etc. | **Returns the editor's static scene tree, not the running game's runtime state.** Player.position read as `(64, 64)` (scene-file default) while the live game had the player at world `(64, 416)`. |
| Read custom GDScript `var` declarations | `node get_properties` | Plain `var` is invisible. Only `@export`-annotated vars surface — and even then, only their **scene-file default values**, not live runtime values. |
| Read Dictionary-typed game state | n/a | `GridWorld.buildings` (the master dict of Building instances by anchor) is a custom var holding RefCounted instances. Not readable through any MCP tool. |
| Capture game stdout | `editor get_log_messages` (with `source=game`) | Returned `No log messages` even when game was running. Stdout-print-then-read fallback is unreliable. |
| Inject input into the running game | `input sequence` | The tool reports "executed" but the action does not reach the running game process — `_demo_origin` and `_demo_spawned` did not change after `debug_spawn_demo` injection while the game was running. Action injection appears to target the editor's input map, not the live game. |

### Critical caveat — read this before assuming MCP can debug your game

**MCP reads the editor's static scene tree, NOT the running game process.** When `editor.run` launches the game, it forks a separate process; the editor's scene tree continues to reflect the **authored `.tscn` file content** — built-in property defaults, exported var defaults, the static layout. Anything that changes at runtime (player movement, F11 demo state, Building dict contents, tick count) is invisible to `node get_properties`.

Adding `@export` to a script var **does NOT make its live runtime value readable**. It only makes the var visible to the inspector / scene serializer. MCP reads the scene-file default, not the running value. We tested this directly: `@export var _demo_origin` returned `(0, 0)` (its initial default) regardless of F11 state in the live game.

**The single confirmed live-state path is `editor screenshot_game`.** Everything else is editor-scene introspection at the authored level.

### Verification scope (revised after honest characterization)

The original four-check protocol assumed MCP could read live game state. It cannot. Use this **two-check** smoke test instead when re-verifying a fresh install:

1. **`editor get_state` reports `is_playing: true` after `editor run`.** Confirms editor↔game launch control works.
2. **`editor screenshot_game` returns a valid PNG of the running game window.** Confirms the live-state path. Visual content (player position, building counts, HUD text) reads correctly from the screenshot.

That's the verifiable scope. Everything beyond that — reading state programmatically, injecting input, capturing stdout — is **either limited to editor-scene defaults or doesn't work at all** in the current install.

### Workarounds and future work

- **Reading live state when needed:** use `editor screenshot_game` and read the HUD strip visually. The HUD already shows player tile, hover tile, building count, current tick, holding-item — most of what's needed for "where am I in the world."
- **Reading per-Building state (in_buffer, out_buffer, etc.):** **manual Q-inspect with eyes on screen.** No MCP path. Don't build a workflow that assumes MCP can answer this.
- **Future Option (deferred indefinitely): debug-bridge autoload.** The addon already adds an `MCPGameBridge` autoload that runs in the game. In principle a custom bridge layer could expose live state as JSON via a new MCP command. **Real work, not free.** Defer until the screenshot-only path proves insufficient at least 3 times — and even then, weigh against simpler answers like "instrument the game with on-screen debug overlays" or "write programmatic E2E tests via PlayGodot from the Randroids-Dojo skill pack."

### Install footprint

- `claude mcp add godot-mcp -- npx @satelliteoflove/godot-mcp` registers the server (modifies `~/.claude.json` project block).
- `addons/godot_mcp/` directory in the project root (the addon files).
- `project.godot` has `[editor_plugins] enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")`, an `MCPGameBridge` autoload entry, and a `[godot_mcp]` config section (port 6550, bind_mode=0). These were auto-added when the plugin first loaded; not corruption, not to be reverted.
- 8 tests pass post-install. Plugin GDScript is well-isolated.

### Known gotchas (verified)

- **Plugin only binds the WebSocket when the *editor* is running, not the game.** Launching with just `Godot --path X` opens the game (not the editor); the WebSocket server stays unbound. Use `Godot --editor --path X` to launch the editor; `_enter_tree()` in `plugin.gd` runs only in editor context.
- **Stale game processes block MCP connection.** During verification, an orphan game process from an earlier run held the editor's earlier WebSocket connection in a stuck state; killing the orphan unblocked MCP. If `editor get_state` returns "Not connected" but `netstat` shows port 6550 LISTENING, check for stale Godot processes via `tasklist` and kill them.
- **Headless import logs `[godot-mcp] Plugin disabled` at shutdown** — graceful shutdown message, not an error.

---

## Camera zoom — shipped + polished

**Status:** mouse-wheel zoom + smooth-lerp shipped at `session-camera-zoom`. The stash's displacement bug was diagnosed (sub-pixel jitter from non-integer zoom × fractional camera position) and fixed via project-level pixel-snap rendering. The hover-outline-fades-at-low-zoom limitation that was deferred from that session was closed at `session-polish-1` via `screen_px(2.0)` floor. **No active limitations.**

### What `screen_px()` is used for now

`grid_world.gd::screen_px(world_px)` returns `max(world_px, world_px / camera.zoom.x)`. At zoom ≥ 1, it returns `world_px` (the floor wins); at zoom < 1, it returns `world_px / zoom` so the rendered output is at least `world_px` screen pixels.

**Used selectively:**
- **Hover rect outline** (line 427-ish in `_draw`) — vanishing-at-low-zoom was the worse failure mode than ~0.15 screen-pixel overshoot at min zoom.

**NOT used for:**
- Grid lines, building borders, port dots, direction arrow strokes — these stay in world units to match tile boundaries exactly. Overshoot on these (especially port dots, where the radius is small) was visible at low zoom and looked bad. Per-call dimensional choice.

The trade-off is acknowledged: at zoom 0.85 (min), the hover outline overshoots the tile by ~0.18 world units / ~0.15 screen pixels per side. Under perception threshold; visibility win is the priority for hover specifically.

### Long-term solution: sprite migration

The wider "outlines on placeholder art" question is solved by **moving from colored rectangles to actual sprites** — sprite outlines are inside the sprite texture, not draw_rect calls, so they don't have the screen/world dimension question at all. Sprite migration is its own future session.

---

## Cloth chain prefer_dir — shipped, save migration recorded

**Status:** shipped at `session-polish-1`. The Session E follow-up about no-prefer_dir on cloth recipes is closed. Retter/Loom/Tailor now use canonical-east ports with rotation; the F11 demo rotates them south to match the chain's vertical layout.

### Save migration notes (informational, no version bump)

Save schema stayed at v10 — no structural change. But any save with cloth processors placed before `session-polish-1` will need each processor rotated south manually. Defensive `.get("dir", 0)` reads everywhere mean the save loads cleanly; the chain just doesn't produce until rotation is applied.

**The migration steps:**
1. Hover the Retter with empty hand. Press R three times until toast says "Retter rotated to S".
2. Repeat for Loom and Tailor.
3. Chain resumes within ~30 seconds.

Alternative: delete the save (`%APPDATA%\Godot\app_userdata\Stewardship\save_slot_1.json`) and re-spawn with F11 — the demo now spawns them rotated.

### Lesson recorded

R-key rotates a placed building IN PLACE when hand is empty (`main.gd::167-171`), gated on `Buildings.supports_direction(t)`. Discovered during the polish session by reading the actual code rather than assuming "rotation only works during placement preview." First instinct was to write migration docs as "remove + replace each cloth processor" — much worse UX than rotating in place. **Lesson: read the code before writing migration docs.**

---

## Resource harvesting + smelting roadmap (manual + drill + smelter shipped; lumber-camp + kilns next)

**Status update:**
- **Manual tier shipped** for both ore and trees.
  - Ore mining at `session-mining-manual`: walk adjacent → hold Space → drain richness → tile reverts at 0. 5 ore items.
  - Tree chopping at `session-tree-harvest`: walk adjacent → hold Space → 2-second chop → wood (1-4 yield) → 5-minute regrowth.
- **Burner mining drill shipped** at `session-mining-drill`. 2×2 building, fed fuel from adjacent belt/chest, produces ore at 0.5/sec into prefer_dir output port. Highest-richness-wins deposit selection across the 4-tile footprint. Generic `Burner` module ready for smelter / kiln reuse — **validated this session.**
- **Burner smelter shipped** at `session-smelter`. 2×2 building, fed iron or copper ore from W edge + fuel from S edge, produces ingots out E edge at 0.5/sec. **Multi-recipe runtime selection** via FIFO over input buffer (`_maybe_select_recipe`); recipe switches automatically when input changes. Burner module reusability validated: ~13–15 fuel lines vs drill's ~11, parity.
- Save v14 persists per-tile state (richness, regrowth_remaining) via generic Dict-shape `resource_state_modifications`. Drill + smelter state lives on `Building.state` (no schema change at either session).

**What remains: lumber-camp tier + ore→ingot consumers + clay/stone processing.**

**Lumber camp (likely next-after-UI):** placeable building that automates tree chopping. Calls `GridWorld.chop_tree(pos)` on a schedule, reads `GridWorld.wood_yield_for_tree(pos)` for output count. Could be Burner-fed for speed or passive (design TBD).

**Charcoal Kiln (next likely burner consumer):** WOOD → CHARCOAL. CHARCOAL becomes a higher-tier fuel (~8 units?) — single FUEL_VALUES dict entry. Validates Burner module's third consumer.

**Brick Kiln:** CLAY → BRICK (building material). Same shape as Charcoal Kiln; different recipe.

**Stone Crusher:** RAW_STONE → STONE_BLOCK. Stone overlay becomes a consumable (no longer free-paint).

**Tier-2 drill / electric smelter:** deferred until electricity. Architecturally trivial — speed multiplier on `time_ticks` / `DRILL_TICKS_PER_ORE`.

Manual harvest stays as the fallback / early-game tool. Drill is unambiguously slower than manual for stone/coal/clay (0.5 vs 2/sec) but unattended — a *bank* of drills is a different game. Smelter at 1:1 with drill output makes the "1 drill + 1 smelter" the basic ore-tier unit.

**Hooks already in place (as of session-smelter):**

- `ResourceNodes.is_renewable(t)` distinguishes ore from trees in behavior.
- `GridWorld.deplete_resource(pos, amount)` — canonical ore extraction primitive (used by manual mining AND mining drill).
- `GridWorld.chop_tree(pos)` — canonical tree chop primitive (single-shot, starts regrowth).
- `GridWorld.wood_yield_for_tree(pos)` — deterministic yield helper.
- `resource_state[pos]` — per-tile dict; `{richness, original_richness}` for ore, `{regrowth_remaining}` for chopped trees, future fields for future types.
- Save format v14 — `resource_state_modifications` is generic Dict; future state types add keys without schema bump.
- `Burner` static helpers (`scripts/world/burner.gd`) — fuel buffer, fuel pull from belt/chest, per-tick consumption. **Validated reusable at session-smelter** (~13–15 fuel lines in smelter vs drill's ~11). Charcoal Kiln + Brick Kiln are next consumers; will reuse without extension.
- Building-placement-cancels-regrowth (`GridWorld.place_building`) — generic to all building types. Future 2×2+ buildings inherit it for free.
- **Multi-recipe Processor pattern** (`smelter.gd::_maybe_select_recipe`): pre-tick recipe selection wrapping `Processor` helpers. Foundation for any future building that needs runtime recipe switching (configurable Oven via UI, refinery, etc.). Smelter calls `Processor._try_pull_inputs / _has_all_inputs / _has_room_for_outputs / _consume_inputs / _emit_outputs / _try_push_outputs` directly — Processor's helpers double as building blocks for non-Processor.tick state machines.

**Stage 5 (processing chains)** — still the plan:
- `stone_crusher`: `raw_stone × N → stone_block × 1` (the existing stone overlay becomes a consumable item).
- `smelter`: `iron_ore + fuel_briquette → iron_ingot`.
- `sawmill`: `wood × N → planks × 1`.
- `charcoal_kiln`: `wood → charcoal` (alternative fuel to coal/briquettes).
- `brick_kiln`: `clay → brick` (building material).

**Stone overlay becomes a consumable** at processing-chain ship: hotbar's "Stone" slot stops being a free brush. Painting consumes 1 `stone_block` per tile. Belts, harvesters, mills, etc. that currently require Stone overlay continue to work — the overlay still exists, you just have to manufacture it now.

## Sapling visualization during tree regrowth (deferred polish)

**Status:** at `session-tree-harvest`, chopped tile regrowth uses empty-grass rendering during the 5-minute timer. Player can't visually distinguish a regrowing tile from default grass — they only know via Q-inspect or by waiting and watching.

**Polish path:** small sapling sprite drawn on regrowing tiles, growing in size toward mature as the timer ticks down. Cheap render (one circle that scales 0.0 → 0.32 over 300 sec). ~20 lines of code in `_draw_resource` or a new `_draw_regrowth`. Defer until "I can't tell which tiles I chopped" becomes a real complaint in playtest.

**Design sketch:**

1. **World-gen extension.** `GridWorld.generate_default_world()` (or its successor) places resource_node deposits in irregular clusters far from spawn — stone deposits in rocky regions, wood groves at forest edges, ore in deeper veins. Deterministic shapes, like the Session B water lake.
2. **Mining buildings.** Two new placeable types:
   - **Quarry:** placed adjacent to stone/ore deposits. Periodically extracts `raw_stone` / `raw_ore` items into its output buffer. Like Harvester for crops, but consumes the deposit (depletion is the soft-threat — eventually a deposit runs dry).
   - **Lumber Camp:** same idea for wood groves → `raw_wood`.
3. **Processing.** New Processor recipes:
   - `stone_crusher`: `raw_stone × N` → `stone_block × 1` (the existing stone overlay is renamed `STONE_BLOCK_TILE` or similar; the consumable item is `stone_block`).
   - `smelter`: `raw_ore + fuel_briquette` → `metal_ingot`.
   - `sawmill`: `raw_wood` → `planks`.
4. **Stone overlay becomes a consumable.** The hotbar's "Stone" slot stops being a free brush. Painting consumes 1 `stone_block` from player inventory per tile. Belts, harvesters, mills, etc. that currently require Stone overlay continue to work — the overlay still exists, you just have to manufacture it now.
5. **Player inventory pressure.** This is the gating effect — early game you're working with what you can carry from a quarry, late game you have a stone-block stockpile and freely build big factories.

**What this unlocks:**

- A real mid-game economy (not just "I can paint anything for free").
- A stewardship-themed soft-threat: deposits deplete; over-mining a region forces you to relocate quarries.
- A reason to build long supply lines back to your factory hub (raw materials don't spawn where you want to build).

**Migration concerns:**

- Existing v8 saves with the current "free stone" model will need a one-time conversion when this lands: scan tiles, count stone overlays, credit player inventory with that many stone_blocks. Document in save migration log.
- Hotbar layout will shift: Stone moves from Terrain category to a new Materials category alongside future planks/ingots.

**Don't pre-build:**

- The Quarry / Sawmill / Smelter aren't generic Processors quite — they consume a deposit (resource_node) on the tile they sit on or adjacent to, not items from a belt. Will likely need a separate `Extractor` base class. Do not generalize until the second extractor type lands.

**Until then:**

- Stone is free in the hotbar. Don't gate Sessions C-F on this.
- `resource_node` field round-trips through saves but is otherwise inert.
- Remove the F12 yeast spawn debug at the same time as wiring real ore→ingot processing — both are "scaffold I owe the codebase."

---

## Building size tiers

The game has a deliberate vocabulary of footprint sizes. Each tier corresponds to a category of equipment with consistent visual / spatial weight. Keeping tiers stable makes layouts feel intentional.

| Tier | Footprint | Examples (current and planned) |
|---|---|---|
| **1×1** | Tools, throughput devices, simple processes | Planter, Harvester, Belt, Pipe, Pump, Mill, Thresher, Briquetter, Sugar Press, Yeast Culture, Chest |
| **2×2** | Substantial machinery, mid-tier processing | Mixer, Oven, Proofer, Packager (Session D scope) |
| **3×3** | Major industrial equipment, late-game specialty | (planned) Smelter, Refinery, Silo, Brewery; possible Oven upgrade if 2×2 feels too small after playtest |
| **4×4+** | Endgame megabuildings (reactors, mass storage, factories-in-a-box) | Deferred indefinitely; not designed yet |

### Sizes are data

Footprint lives in `Buildings.DATA[type].footprint`. Changing a building's tier is a one-line edit; the multi-tile infrastructure (edge_cells, placement validation, rendering, occupied map) handles any size uniformly. **Oven starts as 2×2 in Session D. If 2×2 feels too small after playtest, upgrade to 3×3 in a future session by editing `Buildings.DATA[OVEN].footprint`.** Save schema bump on upgrade because existing saves' OVEN entries claim a different footprint.

### Open questions for 3×3 (and anything larger)

A 2×2 building has 2 edge cells per side. `prefer_dir: Belt.DIR_E` for a 2×2 is unambiguous-ish: scan both east-edge cells, push to first that accepts.

A 3×3 has **3** edge cells per side. `prefer_dir: Belt.DIR_E` is ambiguous — which east cell does the recipe mean? Three reasonable answers, each with tradeoffs:

1. **Any cell, first match.** Recipe says "east edge"; Processor scans (X+3, Y), (X+3, Y+1), (X+3, Y+2) in order; pushes/pulls at first that accepts. Simplest, current behavior generalized. Caveat: ordering is implicit (which cell is "first"?); two outputs both saying "east" might collide on the same belt unintentionally.

2. **Specific cell via offset.** Recipe declares both edge AND offset along that edge: `[item, count, dir, offset]`. E.g. "east edge, middle cell" = `[BREAD, 1, DIR_E, 1]`. Most explicit; requires recipe authors to think about port placement. Best for visual clarity (large machines have specific input/output points) but more verbose.

3. **All cells must accept.** Output items duplicate to every edge cell on that edge — recipe produces 1 bread, but *all 3 east-edge cells* receive it (as 3 copies, or block until all 3 can accept). Mostly nonsensical for current items; might make sense for fluid recipes where "fluid leaves on east edge" = pipe at any east cell suffices. Probably not the right answer for 3×3 solid outputs.

**Recommended for when 3×3 lands:** option 2 (specific cell via offset). Add the `offset` element only when the recipe actually needs it; default to "first match" (option 1) when omitted. Backwards-compatible with 2×2 recipes that don't specify an offset.

When 3×3 ships, also consider:
- Whether `Buildings.edge_cells` should support an optional offset parameter, returning a single cell instead of all edge cells.
- How the info panel displays per-port positions ("Bread → E[1]" vs "Bread → E").
- Visual tells on the building itself — do players SEE that fuel must enter via the southwest tile of a 3×3 Smelter, or do they have to learn it from the recipe?

These are real design questions that 2×2 lets us defer. Don't try to solve them in Session D; capture the tradeoffs here so future-me has the framing pre-loaded.

## Debug scenario: the ELECTRIC_INSERTER smoke-test rig (session-inserter-electric, PAUSE 1)

Discoverability note, not design: the launch command and the two keys were
previously written down nowhere in the repo, which made a scenario built for a
human to LOOK at findable only by grepping `main.gd`.

**Launch with it already built:**

```
./tools/Godot_v4.6.3-stable_win64_console.exe --path . -- --scenario=electric_rig
```

The bare `--` is mandatory and silent when missing. The flag is read from
`OS.get_cmdline_user_args()`, which is populated *only* by args after the
separator — Godot's own parser swallows anything before it, and the game then
boots normally with no warning and no visual difference from a plain launch.

**Keys, both live even while a building panel is open** (they sit above
`_process`'s modal early-return, deliberately — the dest chest's panel is how
you compare throughput between states):

| Key | Effect |
|---|---|
| `F10` | Spawn the rig south of the player. On ground that already holds an intact rig it ADOPTS that one — re-attaching the lever after a save/load — instead of scattering a second copy. Shift+F10 clears the dedup flag. |
| `F8` | THE LEVER: FULL → BROWNOUT → ZERO → FULL. Changes only how many of the two steam generators carry fuel. Nothing is built or removed. |

**What the three states mean.** Demand is pinned at exactly 40 (4 electric
inserters × 5 + 20 lamps × 1) and each fuelled generator supplies 20, so the
lever lands on exactly 1.00 / 0.50 / 0.00 satisfaction — hero inserter cycle 5
ticks, 10 ticks, then `STATE_NO_POWER`. The arithmetic is pinned headlessly in
`scripts/tests/test_electric_rig.gd`; the rig exists for the half a test cannot
check (lamp brightness, arm speed, no flicker).

**Two things that are not bugs.** Satisfaction lags an F8 press by ~0.1 s —
`update_supply_demand` is a pre-pass that runs before the generators' own tick.
And hand-editing a rig generator's fuel slot is meaningless: the lever owns
that field. Emptying it by hand leaves that generator dark until the next F8.

**This is PERMANENT INFRASTRUCTURE, not session scaffolding — reuse it.** Any
future power-related session gets its smoke setup for free: a live network with
a real generator, a real brownout at an exact midpoint, and a one-key sweep
through the whole satisfaction range, without building anything by hand. That is
the setup cost of every electric gate from here on, already paid.

Extending it for a new consumer is the cheap path *provided the demand total
stays 40* — that number is what makes the lever land on exactly 0.50 rather than
somewhere near it, and `test_electric_rig.gd` asserts satisfaction with `==`, not
`is_equal_approx`, precisely so a drifted total reddens instead of passing
quietly. Swap a consumer OUT when you add one in: one electric inserter (5) is
five lamps (1). If a future session genuinely needs a different total, change the
generator count too and re-derive — do not leave the midpoint approximate.

Its real lesson is cheaper than the rig: **the human gate went from "construct
the scenario, then look" to "look".** Most of a PAUSE gate's cost was never the
looking. Build the rig FIRST next time, before the gate, not after the tier.
