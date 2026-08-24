# Review Findings -- full-codebase flaw audit (2026-07-19)

> ## ⚠ READ THIS BEFORE ACTING ON ANY FINDING BELOW
>
> **This audit was run against a stale baseline.** It analysed a fresh clone
> that landed on `origin/main` at `38917d5` (Cluster C) — but the live work at
> the time sat 94 commits ahead on a feature branch that was never pushed.
> QoL Cluster A, Long-Reach Inserter, Electricity Foundation, and QoL Cluster B
> were all invisible to it. Line numbers, file shapes, and several findings
> describe code that had already changed.
>
> ## ⚠⚠ THE STATUS RULE — read before writing any status into this document
>
> **A status claim in this document describes what shipped on `main`, verified
> by commit. Work on an unmerged branch does not count as closed.**
>
> This document violated that rule for a month and it cost real money. The
> remediation block below used to credit six "session-hardening-N" commits that
> live only on `audit-hardening-stale-base` and were never merged. Anyone reading
> the doc at HEAD would have believed **77 live findings were fixed** — including
> four HIGHs and a non-atomic save write that can destroy the player's only save
> slot. Finding #1 sat live for a month behind exactly this wording before
> anyone noticed.
>
> When you close a finding, cite the commit that closed it **on main**, and say
> which test covers it. "Fixed at session-X" is not a status; `git merge-base
> --is-ancestor <sha> main` is.
>
> **Status: verified finding-by-finding against `24d4114` on 2026-08-22.
> 7 CLOSED, 77 LIVE at that verification.** Nothing was found MOVED, DISPROVED or UNVERIFIABLE — the
> audit's *content* held up; what rotted was the claim that it had been acted on.
> Full table below. Every citation in that table is a **current** line number.
>
> **The lesson, which is the reason this document is kept:** a static-read audit
> produces *confident* findings. Confidence is not reproduction. Every finding
> acted on was first re-verified against current code with a RED test that
> demonstrated the defect concretely — and that discipline paid twice:
>
> - #8/#9 was re-confirmed as real (multi-type buffers are the designed steady
>   state for Mixer/Oven/Thresher; a single click destroyed sibling stacks), but
>   the audit's *shape* was stale — the defect had spread from 2 call sites to 4
>   as Cluster A and Cluster B faithfully copied the broken assumption.
> - #10's blast radius had **grown**: Electricity Foundation added two more
>   `Overlay.NONE`-accepting buildings after the audit ran, and Session 2 added
>   two more again.
>
> Treat every finding below as a **hypothesis with a citation**, not a defect
> report. Grep for the asserted behavior, confirm the current line numbers, and
> write a failing test before scoping any fix.
>
> — annotated 2026-08-20, after the branch landed on trunk (`0e47747`)

Method: 10 parallel review dimensions (save integrity, sim core, machines, soil/worldgen, UI panels, main/console, test quality, performance, conventions, doc drift) over the full `scripts/` tree + docs. Every raw finding was then adversarially verified by 1-2 independent skeptic passes instructed to REFUTE it against the actual code; only findings that survived are listed. Baseline at audit time: commit `38917d5`, 33/33 test suites passing on Godot 4.6.3.

Stats: 106 raw findings -> 86 after dedup -> **84 confirmed**, 2 refuted, 0 unresolved. Three residual duplicate pairs are cross-referenced inline.

Severity is post-verification (verifiers could downgrade/upgrade). Line numbers reference the audited commit.

## STATUS TABLE — verified against `24d4114`, 2026-08-22

Five independent verifiers took disjoint slices, read-only, forbidden from trusting
either the audit's line numbers or any prior status claim. Every row required a
citation in **today's** code. Result at verification: **7 CLOSED, 77 LIVE, 0 MOVED,
0 DISPROVED, 0 UNVERIFIABLE.**

**Progress since that verification** — the two numbers are kept separate on purpose.
The verification result is a dated measurement and should not be edited; this line is
the running total, and the CLOSED table below is the authority for which is which.

| date | closed since | running total |
|---|---|---|
| 2026-08-22 | — | 7 closed / 77 live |
| 2026-08-22 | #3 | **8 closed / 76 live** |
| 2026-08-23 | #4 + #5 (one unit) | **10 closed / 74 live** |
| 2026-08-23 | #83 | **11 closed / 73 live** |
| 2026-08-23 | #7 | **12 closed / 72 live** — no HIGH remains |
| 2026-08-23 | #12 | **13 closed / 71 live** |
| 2026-08-23 | #11 | **14 closed / 70 live** |
| 2026-08-23 | #13 | **15 closed / 69 live** |
| 2026-08-23 | #21 (narrowed — see below) | **16 closed / 68 live** |

Every original line number in this document has drifted — `NOTES.md` content moved
~700 lines, `grid_world.gd` ~+80, `main.gd` ~+230. Use the citations here, not the
ones in the finding bodies below.

### What the previous version of this block claimed, and why it was wrong

It credited six `session-hardening-N` commits. **Only one of them is an ancestor of
`main`.** The rest live on `audit-hardening-stale-base`, unmerged. The artifacts it
named as coverage — `test_item_conservation.gd`, `test_load_correctness.gd`,
`test_soil_arc_fixes.gd`, `test_placement_guards.gd`, `test_recipe_execution.gd`,
`test_belt_two_pass.gd`, `test_building_indices.gd` — **none exist on trunk.**

Six findings were nevertheless closed on main, independently, by later feature
sessions that re-derived the defect from scratch. That is the only reason any HIGH
is closed at all.

### CLOSED (16)

| # | Finding | Closed by | Coverage on main |
|---|---|---|---|
| 1 | load_game leaves both network caches stale | `b0fc362` | `test_load_network_invalidation.gd` |
| 2 | fuel outage destroys held item | `37ff498` | `test_inserter_fuel_conservation.gd` |
| 6 | (duplicate of #2) | `37ff498`, extended to NO_POWER at `0e9e49a` | same |
| 8 | slot take clears whole shared buffer | `6478690` | `test_shared_buffer_slots.gd` |
| 9 | shared-field slots all render `buf[0]` | `6478690` | same |
| 10 | Overlay.NONE buildings placeable on water/ore | `6478690` | `test_placement_terrain_guards.gd` |
| 3 | aggregate `in_buffer` cap deadlocks mixed-input processors | `08e052c` + `6d0f5e9` | `test_inserter_shared_input_cap.gd` |
| 56 | duplicated slot handlers diverge on empty-cursor | `83a72cc` + `fa4b5ca` — **accidental**, a side effect of deduplicating into `SlotClickHandler` | shared handler |
| 4 | applicator never pulls or applies COMPOST_HIGH | `4c021fb` | `test_applicator_wasteland_recovery.gd` |
| 5 | one scarred tile permanently wedges LOW/MID application | `4c021fb` — same commit, see the interlock note below | same |
| 83 | "31 sub-suites total" but components sum to 35 | `4c021fb` — `NOTES.md:842`, the soil arc's sub-suite tally, now states a total its own addends sum to | doc-only; no test |
| 7 | grace timer runs on actively-farmed soil-0 tiles, making the documented fertilizer rescue impossible | `b92a769` — **not** the fix this audit prescribed; see the entry below | `test_wasteland.gd` sub-suite 10 (10a rescue / 10b design control / 10c narrowness) |
| 12 | non-atomic save write — a crash mid-write destroys the only slot | `b04c1f6` — the prescribed fix, with two departures recorded below | `test_save_atomicity.gd` (6 sub-cases) |
| 11 | load_game indexes save arrays without shape validation | `61de9ee` + `7a86195` | `test_load_malformed_save.gd` (10 sub-cases). **Two commits, deliberately.** `61de9ee` closed the *mechanism* the title names — unguarded array indexing. But the title also names a *consequence*, "crashes load instead of triggering the fresh-world fallthrough", and that stayed reachable through two non-array shapes (`player_progression` as a non-Dictionary; a building whose `"s"` is a String) until `7a86195`. Marking this CLOSED at `61de9ee` alone was premature — see R2. |
| 13 | F9 quick-load leaves vision and the map stale | `9508d3f` — the fix text's optional shared helper taken as mandatory; see the entry below | `test_quick_load_refresh.gd` (3 sub-cases) |
| 21 | forward-incompat save armed for destruction | `1198233` — **scoped down to one of the three cases it named**; see the scoping note below | `test_forward_incompat_save.gd` (9 sub-cases) |

Each was checked for the half-fix pattern. #8/#9's resolver reaches all four call
sites (take, ctrl-take, draw, hover); #10 guards every footprint cell for every type
with the drill exemption scoped to the resource-node check only.

**This block used to say "none is partial", and that claim did not survive the review
of #11/#13/#21.** Three defects in the closed work were found by that review and are
recorded where they belong rather than here: #11's residual `Inventory.load_array`
truncation (see #11's entry — the note describing it was itself wrong about what it
did), #21's worldgen alert still quoting `save_path` (see #21's scoping note), and
**R2**, two save shapes that still reached #11's exact bricked-boot failure. All three
are fixed; the lesson kept is that a half-fix check performed by the same pass that
wrote the fix is not independent evidence. Prefer the per-finding notes below to this
summary line.

### LIVE — HIGH (0)

None. #7 was the last one and closed at `b92a769` (2026-08-23). Every HIGH this
audit raised is now closed on `main` with test coverage named in the CLOSED
table above.

**#4 and #5 interlocked and were fixed as one unit** at `4c021fb` (2026-08-23).
#5's wedge only fired for LOW/MID because that was all the applicator could hold —
which was #4's pull filter. Fixing #4 alone would have changed which tier hit the
scarred tile; fixing #5 alone would have left automated wasteland recovery
impossible. Both reproduced first: RED showed 0 of 4 belt-fed Premium Compost
pulled and tier `-1` on the target for #4, and a soil-40 tile still unfertilized
with the machine in `STATE_BLOCKED` for #5.

The shipped guard is the one prescribed in #4's fix text, with one change worth
recording. Rather than writing `selected_tier == COMPOST_HIGH` a second time in the
applicator, the tier rule moved into `GridWorld.wasteland_accepts_tier()`;
`try_apply_fertilizer` gates on it and the tile picker asks it, so there is one copy
instead of two that can drift — which is the failure mode that produced #4 in the
first place. Mutating that predicate to `return true` reddens both `test_wasteland`
and the new suite, which is what demonstrates it is shared rather than merely
extracted. The guard is conditional, not a blanket wasteland skip: mutating it to
skip every scarred tile cures #5 and reddens the recovery sub-suite instead.

### LIVE — MEDIUM (22)

| # | Finding | Today's citation |
|---|---|---|
| 14 | processors push outputs backward onto feeder belts | `processor.gd:221-230, 260-269` |
| 15 | composter pins a starved recipe forever | `composter.gd:74-78` |
| 16 | hover preview contradicts `can_place_building`, both directions | `grid_world.gd:1731-1741` (bad check `:1736`) — **was cited `:1598-1606`, which now lands on #30's terrain loop**. Interlocks with #38: #38's headline symptom *is* this bug |
| 17 | pass-1 belt mutations make timing insertion-order dependent | `grid_world.gd:648-654` vs `CONVENTIONS.md:142` |
| 18 | `STATE_NO_FUEL` has no fallback — smelter wedges with fuel available | `smelter.gd:117-125` |
| 19 | `_drop_to_chest` bypasses `Chest.TOTAL_CAPACITY` — **see mis-rating note below** | `inserter.gd:641-654` |
| 20 | zero-richness ghost rim ore tiles | `world_generator.gd:352-368` |
| 22 | one Esc press performs two actions | `map_panel.gd:274-276` (was `:243-245`), `console.gd:180-182` (accurate), `main.gd:691-703` (was `:611-622`). One unit with #58 + #59 |
| 23 | console `place` paves anchor only; leaves stray STONE on failure | `console.gd:625-639` |
| 24 | unbounded radius in `deplete_area` / `tile` | `console.gd:550-562, 743-744, 782-812` |
| 25 | nine bread/cloth recipes never tick-tested | no suite in `scripts/tests/` ticks them |
| 26 | no dedicated belt two-pass test | no `test_belt.gd`; `CONVENTIONS.md:142` untested |
| 27 | bag-cap phases assert an in-test mirror of production logic | `test_bag_cap.gd:20-21, 108-115` |
| 28 | BLOCKED_OUTPUT phase asserts neither state nor recovery | `test_smelter.gd:153-171` |
| 29 | `_tick_regrowth` walks all of `resource_state` per frame | `grid_world.gd:1470-1490` (early-out at `:1471`) — was cited `:1330-1356`. **Partly closed by #31's migration**; fix #31 first or fix both as one unit |
| 30 | `_draw` walks every tile and building per frame | `queue_redraw()` `grid_world.gd:1191`, terrain loop `:1598`, buildings loop `:1688` — was cited `:1103, 1464-1469, 1554-1563`. **NOT affected by #31**: `queue_redraw()` stays in `_process` under every proposed fix |
| 31 | soil regen / fert decay / regrowth advance in `_process`, not on ticks | `grid_world.gd:1182-1191` vs `tick_system.gd:5-7` — **scoped at `docs/scoping/r1-two-clocks.md`**; its fix text's "no test changes needed" is true and is the hazard |
| 32 | `_tick_soil_regen` rebuilds its active set from ALL buildings per frame | active-tiles rebuild `grid_world.gd:1223-1232`, keys snapshot `:1239`, call site `:1190` — **was cited `:1128-1149`, which now lands on `wood_yield_for_tree`**. Partly closed by #31; same unit as #29 |
| 33 | per-tick transient allocations in processor pull/push | `processor.gd:101-102, 119, 126`; `buildings.gd:936-956` |
| 34 | console.gd split trigger breached; NOTES says 657 lines | `NOTES.md:773, 777`; file is 812 lines. **Same edit as #80** — both resolve to `NOTES.md:773` + `:777`, at different severities. Fix as one; see R3's pattern note |
| 35 | NOTES lifecycle rule names a `CHANGELOG.md` that has never existed | `NOTES.md:5` |
| 36 | stale `SESSION_E_PLAN.md` hand-off brief (v9 / 8 tests) | `SESSION_E_PLAN.md:3, 7-8, 48` |

### LIVE — LOW (46)

| # | Finding | Today's citation |
|---|---|---|
| 37 | `tile_regen_progress` not cleared on load | sibling clears at `save_system.gd:724, 737, 752, 766`; **`tile_regen_progress.clear()` appears nowhere in the file** — was cited `:550-579` |
| 38 | load rehydrates explicit default-grass tiles | `save_system.gd:663-664` — was cited `:515-516`. Its headline symptom *is* #16; fix #16 first, then re-scope |
| 39 | Harvester reassigns `b.state["buffer"]` instead of mutating | `harvester.gd:123, 163` |
| 40 | drill pulls fuel from all 4 edges | `mining_drill.gd:119` |
| 41 | composter recipes comment claims non-rotatable | `recipes.gd:207-208` |
| 42 | unbounded tick catch-up loop | `tick_system.gd:42-46` |
| 43 | `try_pull_fuel` docstring says inserters pass -1 | `burner.gd:56` |
| 44 | composter header claims non-rotatable (dup #41) | `composter.gd:15, 69` |
| 45 | fallback-lake exclusion tests only the anchor | `world_generator.gd:448` |
| 46 | regen accumulators bleed on load (dup #37) | same site as #37 — was cited `:550-579` |
| 47 | `set_soil` doesn't clear wasteland | `console.gd:527-531` |
| 48 | `deplete_planter_area` writes out-of-world tiles | `grid_world.gd:703-710, 734-741` |
| 49 | `_neighbor_falloff_cost` floors at 1 | `grid_world.gd:719-720` |
| 50 | spawn sort lacks a tie-break | `main.gd:540-543` — was cited `:460-462` |
| 51 | `try_apply_fertilizer` accepts water / OOB / paved tiles | `grid_world.gd:769-795` |
| 52 | panel keeps a stale ref after console destroy | `building_panel.gd:78-83` |
| 53 | chest swap capacity ignores the outgoing stack | `chest_panel.gd:235-253` |
| 54 | hotbar keys not gated by modals | `hotbar.gd:266` |
| 55 | drill panel overflows its 280px top area | `drill_panel.gd:54, 57, 180` |
| 57 | chest capacity label hardcodes 2400 | `chest_panel.gd:56` |
| 58 | duplicate unconditional `close_info_panel` handler | `main.gd:801-802` — **was cited `:721-722`; `:802` now lands in #59's neighbourhood**. One unit with #22 + #59 |
| 59 | backtick cannot close the console | `main.gd:878-881` (was `:802-805`); `console.gd:162-180`. One unit with #22 + #58 |
| 60 | F11 demo writes tiles bypassing `tile_modifications` | `main.gd:1547` — was cited `:1463-1464` |
| 61 | `on_impassable` escape valve permits free water walking | `player.gd:82` |
| 62 | `tick_speed` reads "was" after assignment | `console.gd:707-708` |
| 63 | runner restores neither `save_path` nor tick rate | **no restoration exists** — `SaveSystem.save_path` appears in `test_runner.gd` only in comments (`:121-124`, `:167-168`), and `tick_rate_multiplier` not at all. Was cited `:80-83`. Scope is **21** suites overriding `save_path`, not the 10 the body claims |
| 64 | hotbar cycling / disabled-slot / map / minimap have zero coverage | `hotbar.gd:277, 374` |
| 65 | cursor backward-compat test is a tautology | `test_building_ui.gd:278-283` |
| 66 | seed-uniqueness tests fabricate seeds | `test_random_seed_save_roundtrip.gd:25` |
| 67 | round-trip suite labelled v14; save is v18 | `test_save_load_roundtrip.gd:3, 31, 241` |
| 68 | determinism spot-check pinned to worldgen VERSION 3 (now 4) | `test_worldgen_determinism.gd:77, 82` |
| 69 | ui_2 frees a world without `_disconnect` | `test_building_ui_2.gd:145` |
| 70 | ambient trees sample noise for all 262k tiles — **deferred pending profiling** | `world_generator.gd:423-429` |
| 71 | port indicators re-resolve recipes per frame — **deferred pending profiling** | `buildings.gd:1228-1277` |
| 72 | `_is_tile_actively_farmed` scans all buildings per frame | `grid_world.gd:1395-1405` — was cited `:1261-1271` |
| 73 | `_all_building_panels` allocates a fresh 22-array per call | `main.gd:1178-1188` — was cited `:1095-1103` |
| 74 | post-tick pass iterates all buildings for belt-only logic | `grid_world.gd:654` |
| 75 | `class_name DevConsole` lives in `console.gd` | `console.gd:1` |
| 76 | soil arc says "migration framework still queued" | `NOTES.md:841` vs `:793` |
| 77 | stale `INVENTORY_UI_PLAN.md` at repo root | `INVENTORY_UI_PLAN.md:7` |
| 78 | CONVENTIONS layout lists `assets/`, omits `tools/` + `addons/` | `CONVENTIONS.md:65` |
| 79 | console.gd header says 12 commands; registry has 13 | `console.gd:19-20` vs `:344-407` |
| 80 | NOTES Dev Console: 12 cmds / 29 tests / 657 lines | `NOTES.md:767, 769, 773`. **Same edit as #34** (MEDIUM) — duplicate at different severities. Also pairs with #79: same command count, two files |
| 81 | "14 specialized panels" vs 17 listed vs 21 real | `NOTES.md:1139` — was cited `:998, 1000, 1039`. **21 is correct** (26 `*_panel.gd` minus 5 non-building-specific); see the baselines block |
| 82 | ProcessorPanel "11 consumers", code has 12 | `NOTES.md:1146` (was `:1007`) vs `:834`. **Understated by one, not two** — the real count is 12; the baselines block briefly said 13 and was wrong |
| 84 | cloth-chain enum comment still future-tense | `buildings.gd:46-48` |

### Scoping note — #21 was closed NARROWER than it was written

**Do not "complete" this finding by making the other two cases stop generating a
fresh world.** #21's title names three load failures — forward-incompat, worldgen
mismatch, migration failure — and treats all three as a save being destroyed. Its
own verification notes already concluded it overreaches on two of them, and
`CONVENTIONS.md` sanctions the fallthrough for those two in as many words:

> Migration returns `null` (or a dict with an unexpected version field) → `_try_migrate`
> aborts the chain → `load_game` returns `success = false` with a descriptive
> `error_message`. `main.gd`'s post-3.5 hotfix catches this and falls through to
> fresh-world generation. Player isn't stranded; their save data is genuinely lost in
> this case. — *Failure handling*

> `worldgen_version` … stays as hard-fail. Procgen output changing for the same seed
> cannot be migrated … Better to surface the failure and let the post-3.5 hotfix
> regenerate fresh. — *Worldgen version is a separate axis*

Neither is recoverable by any build, so there is nothing to preserve them *for*, and
the migration-failure alert already warns about the F5 overwrite. Only the
forward-incompat case is a genuine defect, because only it tells the player their
save still works elsewhere. Sub-cases 5 and 6 of `test_forward_incompat_save.gd` pin
the other two as failure-with-a-message that preserves nothing; mutating
`load_game` to preserve on worldgen mismatch reddens sub-case 5.

**What the `.bak` mechanism had already changed.** Finding #12's atomic write
(`b04c1f6`) post-dates this audit and moves the live save to `.bak` before the new
one lands, so the first F5 after the fallthrough does **not** destroy the newer
save. Traced and asserted rather than assumed — sub-case 2 pins it. What #12 does
not give is durability: `.bak` is a rotating slot, so the **second** F5 moves the
fresh world onto it and the newer save is gone. The window was two keypresses, not
one. Mutating `INCOMPAT_SUFFIX` to `".bak"` leaves sub-cases 1 and 2 passing and
reddens sub-case 3 with the preserved copy reading `version 18 / world_seed 61002`
— the first fresh save, rotated on top — which is that argument as an assertion.

**Scope correction (re-measured 2026-08-23).** The prediction above under-claimed.
The *values* were exactly right, but the mutation reddens more than sub-case 3: **all
four** of sub-case 3's assertions (version, seed, the lost future field, and
byte-identity), **sub-case 7's PREMISE** ("the preserved copy should be the only thing
left on disk" — with the two suffixes aliased, the scrub loop that clears `.bak`
removes it), and now **sub-case 8** as well, which under the aliasing finds the
worldgen fixture it just moved to `bak_path` sitting at `kept_path`. Six assertions
across three sub-cases, not four across one. Sub-case 8's reddening is path aliasing
rather than a signal about preservation, and is recorded here so a future reader does
not read it as one.

Consequently **the audit's fix text is partly redundant and was not implemented as
written.** "Copy the save aside before returning" was kept, because rotation still
reaches `.bak`; the copy goes to a `.incompatible` sidecar `save_game` never writes
and `save_exists` deliberately never counts (sub-case 7 pins that — counting it
would re-run the refusal dialog on every subsequent boot forever). "Extend the alert
text" was kept and reworded to match the migration-failure alert's existing
overwrite warning. No `LoadResult` failure-kind field was added, despite the
precedent of `used_backup` and `skipped_entries`: the alert is authored at the
failure site where the kind is already known statically, and it is modal and
blocking, so the player has read the full explanation before `main.gd`'s toast is
drawn. A field re-deriving in `main.gd` what `save_system.gd` just finished saying
would be plumbing for a weaker restatement.

One thing found while tracing that the finding does not mention: the alert quoted
`save_path` unconditionally, so a save reached through the `.bak` fallback was
reported at a path that does not exist.

**This paragraph previously claimed the fix was complete, and it was not.** It read
"Both the message and the copy now use the path the data was actually read from;
sub-case 4 covers it." Both halves of that were wrong.

*Wrong on scope.* Only the FORWARD-INCOMPAT alert was changed at `1198233`. The
**worldgen-mismatch** alert a few lines below it still read `_native_path(save_path)`,
with `source_path` in scope on that very line — and that alert is the one that tells
the player to **delete** the file it names. A crash between `save_game`'s two renames
leaves only `.bak`; if that save also has a worldgen mismatch, the player is sent to
delete a file that does not exist while the real one sits at `.bak` and is rotated
away by the second F5. Fixed 2026-08-23; the rule is now stated at the site rather
than left to the two branches happening to agree.

*Wrong on coverage.* Sub-case 4 asserts the **copy** is taken from the backup and
that `error_message` still names the versions. It does not assert the **path in the
message**, and no test can: `error_message` deliberately does not carry the path
(`main.gd` toasts it, and a full native path belongs in the modal), and the dialog
text reaches only `push_error` and a fixture-gated `OS.alert`. Sub-case 8 was added
to pin that the worldgen branch is genuinely REACHABLE through `.bak` — the
precondition the defect needed — and the string itself is guarded by the comment at
the branch and by review. Recorded as a known coverage gap rather than papered over.

Every other path-quoting message in `save_system.gd` was checked at the same time and
is correct: `_preserve_incompatible`'s two `push_error`s quote their own `source_path`
/ `dest`; `save_game`'s two rename failures quote `tmp_path` / `bak_path`, which are
the paths those messages are about; the `.bak`-recovery `push_warning` names both
deliberately. `_native_path` is used at exactly three sites, all dialog text, matching
its docstring.

### Severity note — #19 is arguably mis-rated

`_drop_to_chest` survived the entire Inserter Arc rework **byte-shape-identical** and
remains the only path in the game that bypasses `Chest.TOTAL_CAPACITY` — every other
producer goes through `Chest.try_insert` (`chest.gd:77-81`), which enforces it. That
now includes the electric tier.

It is rated MEDIUM, but the outcome is item duplication or destruction depending on
which side of the bypass you land on, and `BLOCKED_AT_DEST` never fires for chests as
a result. That is HIGH-shaped. Re-rate when fixing rather than inheriting the
severity from a document that also claimed it was fixed.

### Current baselines for count-type findings

**Re-derive these before citing one. A bare number here is exactly the drift that
findings #79-#83 are about, and this block went stale itself** — it read "48 test
suites" until 2026-08-23, two suites behind, inside the document tracking that
class of defect. Each entry below carries the command that produces it, so a
reader can check in one line instead of trusting the number.

Verified 2026-08-23 at `09ab238`; the test-suite row re-derived 2026-08-23 at
`233467f` (50 → 51, the #12 suite) and again at `bf839ba` (51 → 52, the #11
suite), and again at `c6c24af` (52 → 54, the #13 and #21 suites), by re-running
the command rather than incrementing. `SAVE_VERSION` was re-checked at each and
is unchanged at 18 — #12 changed the write mechanism, #11 the read robustness,
#13 nothing in this file at all, and #21 only what `load_game` does with a
version it has already decided it cannot read. None touched the schema.

Re-derived again 2026-08-23 for the #11/#13/#21 review response: the suite count is
**still 54**, because that pass added sub-cases to two existing files rather than new
files — `test_load_malformed_save.gd` 6 → 10 sub-cases, `test_forward_incompat_save.gd`
7 → 9. Sub-case counts are not in this table on purpose; they live beside the finding
that owns them, where they can be checked against the file. `SAVE_VERSION` re-checked
and unchanged at 18: that pass changed only what the reader does with data it cannot
parse, never what the writer emits.

| Value | Command |
|---|---|
| `SAVE_VERSION` **18** | `grep 'const SAVE_VERSION' scripts/systems/save_system.gd` |
| worldgen `VERSION` **4** | `grep 'const VERSION' scripts/world/world_generator.gd` |
| **55** test suites | `grep -c 'res://scripts/tests/test_' scripts/tests/test_runner.gd` |
| console **13** commands | `grep -cE '^\s*"[a-z_]+": \{' scripts/ui/console.gd` |
| `console.gd` **812** lines | `wc -l < scripts/ui/console.gd` |
| **12** ProcessorPanel subclasses | `grep -rlc '^extends ProcessorPanel' scripts/ui/*.gd \| wc -l` |
| **21** building-specific panels | `ls scripts/ui/*_panel.gd \| wc -l` = 26, minus the 5 that are not building-specific: `building_panel`, `processor_panel` (base classes), `info_panel`, `inventory_panel`, `map_panel` |

**Correction, 2026-08-24 — this block was wrong when written, in both rows.** It is
recorded rather than quietly fixed, because a block whose whole purpose is stopping
count drift becoming the source of count drift is worth being able to point at.

**The ProcessorPanel row said 13 and instructed a reader to "fix #82's count to 13
rather than copying the audit's figure."** The unanchored `grep -rc` matched a
**doc comment** at `processor_panel.gd:24` — the base class describing itself with
the words ​`just \`extends ProcessorPanel\``. The real count is **12**, which
`NOTES.md:834` ("12th ProcessorPanel consumer") had said all along. **#82 is
understated by one, not two.** The command is now anchored to `^extends`.

**"21 specialized panels" was dropped as uncheckable. It is checkable** — the five
excluded files are identifiable by inspection and named above, and 26 − 5 = 21. The
original figure was right; dropping it was the error. Finding #81's "21 real" stands.

### Deferred by prior decision, still valid

**#45** — its 2-line fix changes worldgen output and needs a v4→v5 bump that
hard-fails every existing save; ship it batched with other worldgen changes.
**#30, #33, #70, #71** — deferred pending profiling; the analyses in their entries
stand ready.

---

## DEFECTS FOUND DURING RE-APPLICATION — deliberately outside the numbered tables

This audit tracks exactly **84** findings and every table above is arithmetic against
that number (16 closed / 68 live). Defects discovered *while closing* those findings
are recorded here instead of being numbered #85+, so the 84-row arithmetic stays
checkable. These are **not** audit findings; nothing above counts them. Forward-looking
copies live in `NOTES.md` under their own `## Queued:` headings.

### R1 — WITHDRAWN. It was already finding #31, and filing it here was the error.

**Withdrawn 2026-08-23**, the same day it was filed. R1 described soil regen, fertilizer
decay and tree regrowth running on `_process` instead of ticks. That is **finding #31**,
LIVE — MEDIUM in the table above, filed in the original 2026-07-19 audit. Recording it as
"newly found" was exactly the drift this document exists to catch, committed inside the
document itself.

Nothing is lost: the scoping work done under the R1 name is real and now hangs off #31.
See **`docs/scoping/r1-two-clocks.md`** (filename kept so existing links resolve).

The one thing the scoping added that #31 did not have is a disagreement with #31's own
fix text, and it is worth stating here because it changes the size of the job. #31 says:

> No test changes needed — `test_fertilizer_chain.gd`, `test_soil_exhaustion.gd`, and
> `test_tree_harvest_lifecycle.gd` all invoke the `_tick_*` helpers directly with explicit
> deltas, so relocating the call site is transparent to the 33/33 suite.

That is **factually true and is the problem, not the reassurance**. The suite pins the
*functions*; nothing pins the *wiring*. A migration that changes the game therefore ships
green, and so would a migration that silently dropped one of the three calls. Under any
option chosen for #31, the first work item is a wiring test — drive `TickSystem.tick`,
assert soil actually moved — because nothing does that today, in either direction.


### R2. Two save shapes still reach #11's bricked-boot failure — `player_progression` and a building's `"s"` state

**Found:** 2026-08-23, while verifying the "only two uncounted drop sites" claim during
the #11/#13/#21 review response. **FIXED in the same pass** — recorded here anyway,
because what they mean for #11's CLOSED status is a judgement call for a human, not a
cleanup.

Finding #11 is closed on the strength of `_first_mistyped_array_field` plus a per-entry
guard on every collection, and the CLOSED block above states "Each was checked for the
half-fix pattern; **none is partial**." Two shapes escaped both, and both produced
exactly #11's headline failure: `load_game` aborts, the caller receives **null** instead
of a LoadResult, `main.gd` dereferences it, and the boot bricks on every subsequent run
until the file is deleted by hand.

**Reproduction** (both measured, literal):

```
"player_progression": "not a dictionary"
  SCRIPT ERROR: Invalid assignment of property or key 'player_progression' with value
  of type 'String' on a base object of type 'RefCounted (LoadResult)'.
     at: load_game (res://scripts/systems/save_system.gd:808)
  → load_game returned NULL

"buildings": [ ..., {"t": 1, "x": 40, "y": 41, "s": "not a dictionary"} ]
  SCRIPT ERROR: Invalid type in function 'new' in base 'GDScript'. Cannot convert
  argument 3 from String to Dictionary.     at: from_dict (building.gd:28)
  SCRIPT ERROR: Invalid access to property or key 'anchor' on a base object of type 'Nil'.
     at: load_game (res://scripts/systems/save_system.gd:760)
  → load_game returned NULL
```

**Why `ARRAY_FIELDS` could never have caught either.** `player_progression` is *supposed*
to be a Dictionary, so the array-field validator has nothing to say about it, and
`LoadResult.player_progression` is typed — the assignment itself raises, after every
world mutation has already been applied. The building case passes the container check
AND the per-entry `is Dictionary` check and then dies one level further in, inside
`Building._init`'s typed `initial_state` parameter. Both are *inside* structures #11's
fix validated the *outside* of.

**Fixed:** type-check before the assignment and count the drop; `Building.from_dict`
returns null for an unreadable `"s"` and `load_game` skips and counts it. Coverage is
sub-cases 8 and 9 of `test_load_malformed_save.gd`. Mutation-tested: removing the
progression guard reddens sub-case 8 with the null-result message; removing
`load_game`'s `if b == null` reddens sub-case 9 the same way. Removing `from_dict`'s own
check does **not** redden the suite — `load_game`'s null guard still catches it — but it
puts one SCRIPT ERROR back in the log, which is why both are kept.

**Open question for a human, deliberately not decided here:** whether #11 returns to
LIVE. The argument for is that "none is partial" is now demonstrably false for #11 and
the audit's own half-fix check missed these. The argument against is that every shape
#11's text *named* is genuinely closed and both of these were found and fixed within the
same review cycle. The 16-closed / 68-live arithmetic below is unchanged pending that
call.

**Not exhaustive.** Two further shapes were noticed and NOT chased: `Building.from_dict`
silently defaults a missing `"t"` to type 0 rather than dropping the entry, and two
`buildings` rows sharing an anchor silently overwrite (`save_game` cannot produce that,
a hand-edit can). Neither aborts the load; both are uncounted.

---

### R3. A malformed inventory row silently truncated the save — and #11 described it as a crash

**Found:** 2026-08-23, by the review of the #11/#13/#21 fixes. **FIXED at `7a86195`.**
Recorded as its own entry rather than folded into #11's closure note, because what
matters here is not the bug — it is that **the finding's stated consequence and its
actual consequence were different, and the stated one was the less dangerous of the two.**

#11 said a malformed save "crashes load". For every shape it enumerated, that was
right. For `player_inventory` it was wrong in the direction that hurts: `Inventory.load_array`
indexed `entry[0]`/`entry[1]` per slot with no guard, and a GDScript runtime error
aborts only the **innermost** function — so `load_array` died, `load_game` carried
straight on, and `result.success` was set to `true`.

**Measured**, corrupting row 2 of a well-typed 16-slot inventory with a marker stack at row 5:

```
(PROBE-TRUNC) success=true skipped=0 flour(row0)=23 wheat(row5)=0
SCRIPT ERROR: Invalid access of index '1' on a base object of type: 'Array'.
   at: Inventory.load_array (res://scripts/world/inventory.gd:150)
```

Row 0 loaded; rows 2-15 were never written. Five corruption shapes (`[7]`, `7`, `"xy"`,
`{"a":1}`, `[]`) all gave `success=true, skipped=0`. **The `"xy"` shape emitted no
SCRIPT ERROR at all** — `int("x")` is 0, so the loss was entirely undiagnosed.

The aggravating detail: the boot toast read `"World loaded from save (seed N)"` with no
suffix, because `skipped_entries` was **0**. The load did not merely fail to notice the
loss — it affirmatively reported that nothing had been skipped. Next F5 wrote the
truncated inventory over the only save.

#### The pattern, which is the reason this is its own entry

**This is the second time in one session that a finding was real but the wrong shape.**

- **#8/#9** were closed as NOT-A-BUG: the audit had misread render-scratch and
  single-type buffers, and the item-destruction it described could not occur. Wrong
  in the direction of alarm.
- **R3** is the mirror: the audit described a loud crash and the reality was silent
  data loss with a counter asserting cleanliness. Wrong in the direction of comfort.

Both survived adversarial verification by 1-2 independent skeptics instructed to
refute. Verification confirms that *something* is there; it does not confirm the
*shape*, and shape determines both severity and whether a fix is complete. #11 was
marked CLOSED on a fix that addressed every mechanism its title named while its
stated consequence stayed reachable — see #11's row, which now cites two commits.

**Practical rule this earns:** when closing a finding, reproduce the described
consequence, not just the described mechanism. If the reproduction does not match the
description, the mismatch is the finding — record it before fixing it.

## HIGH -- player-visible breakage or item loss  (10 findings)

### 1. load_game replaces all buildings without invalidating the fluid-network cache — stale pipe/pump connectivity after F9 quick-load
**Where:** `scripts/systems/save_system.gd:465` | **Category:** bug, found by save-integrity

load_game rebuilds grid_world.buildings directly (bypassing place_building/remove_building, which are the only code paths that set _fluid_network_dirty), and never calls mark_fluid_network_dirty(). GridWorld's mark_fluid_network_dirty() exists precisely for 'code paths that mutate buildings without going through place_building / remove_building' but is never called anywhere in the codebase. The initial _ready load is safe only because _fluid_network_dirty starts true; a mid-session F9 quick-load (main.gd:519) reuses the live GridWorld whose _pipe_component/_component_has_pump maps were already rebuilt. Failure scenario: player has a pump+pipe run feeding a Mixer (network rebuilt, dirty=false), presses F9 to load an older save in which those pipes do not exist; the loaded world's Mixer still passes _has_fluid_inputs because the stale _pipe_component map says a pump-bearing pipe is adjacent, so it produces dough with no water network — and conversely, pipes that exist only in the loaded save are invisible until the player happens to place/remove any pipe or pump. Wrong simulation state persists indefinitely.

**Evidence:**
```
save_system.gd:465-471: `for bdict in data.get("buildings", []): var b: Building = Building.from_dict(bdict); grid_world.buildings[b.anchor] = b ...` — no dirty-marking. grid_world.gd:466-467: `func mark_fluid_network_dirty() -> void: _fluid_network_dirty = true` (defined, never called; confirmed by project-wide grep).
```
**Fix:** In SaveSystem.load_game, add `grid_world.mark_fluid_network_dirty()` immediately after the buildings restoration loop (after save_system.gd:471, before the player_inventory block). This is the exact use case the method's doc comment (grid_world.gd:463-465) names. Regression test: in a single GridWorld, place pump+pipe via place_building, assert fluid_available_at(adjacent) is true (forces rebuild, dirty=false), save; remove the pipe network via remove_building_at and query again; then re-place, save a pipeless variant separately — simplest form: world A with pump+pipe, query to clear dirty, save_game a snapshot taken from an empty world into the same path, load_game into world A, assert fluid_available_at(previously-true pos) is now false without any place/remove call.

<details><summary>Verification notes</summary>

- Confirmed. load_game (save_system.gd:375-376, 465-471) clears and rebuilds buildings/occupied without touching _fluid_network_dirty; the only code setting the flag is place_building (grid_world.gd:437) and remove_building_at (:456), and mark_fluid_network_dirty (:466) has zero callers project-wide. F9 quick-load (main.gd:518-519) reuses the live GridWorld whose network was already rebuilt (pipe.gd:45 draws query it every frame, processor.gd:169/371 every tick), so dirty=false at load time and all post-load fluid queries (grid_world.gd:475-522) read the stale _pipe_component/_component_has_pump maps until an unrelated pipe/pump place/remove. Existing tests load into fresh GridWorld instances where dirty is still true from init, which is why 33/33 passes without covering this.
- Reproduced by trace. load_game (save_system.gd:375-376, 465-471) clears and repopulates grid_world.buildings directly without touching _fluid_network_dirty; the only setters are place_building (grid_world.gd:437) and remove_building_at (:456), and mark_fluid_network_dirty (:466-467) has zero call sites project-wide. main.gd:519 F9 quick-load reuses the live GridWorld whose flag was cleared to false by any prior fluid query (_rebuild_fluid_network, grid_world.gd:564). Post-load, fluid_available_for_building/_edge (grid_world.gd:492, 515) skip the rebuild and consult the stale pre-load _pipe_component/_component_has_pump maps, so processor.gd:61/163-172 lets a Mixer produce with no water network (or starves one that should be fed), and building_panel.gd:446 plus pipe coloring show stale connectivity until any pipe/pump place/remove. Tests pass 33/33 because every test and the _ready load use a fresh GridWorld where the flag initializes true (grid_world.gd:211).

</details>

### 2. Inserter destroys its held item after running out of fuel mid-swing
**Where:** `scripts/world/inserter.gd:155` | **Category:** bug, found by sim-core

At the top of Inserter.tick, an empty fuel buffer overwrites the state to STATE_NO_FUEL and returns, regardless of whether the inserter was mid-cycle (WORKING_OUT or BLOCKED_AT_DEST) holding an item. STATE_NO_FUEL shares a match branch with STATE_IDLE, so after refueling, the branch calls _try_pickup and _set_held, which overwrites held_item_buffer with the newly picked item. The previously held item is erased from the world. Concrete scenario: basic inserter with 1 wood (1 fuel unit, 20 burn ticks) picks an item; the unit expires during the swing-out; next tick fuel_buffer<=0 and the S-edge fuel port has no belt (hand-fueled case), so state becomes NO_FUEL while held_item_buffer still contains the item. The player refuels via the panel; next tick the NO_FUEL branch picks a new item from the source belt and _set_held replaces the buffer -> one item permanently destroyed. Even if the source stays empty, the held item is stranded forever since only a successful pickup exits NO_FUEL.

**Evidence:**
```
Line 141: `b.state["state"] = STATE_NO_FUEL` (unconditional, even mid-swing); lines 151-157: `STATE_IDLE, STATE_NO_FUEL: var picked: int = _try_pickup(b, world); if picked >= 0: _set_held(b, picked)` — _set_held does `b.state["held_item_buffer"] = [[item_type, 1]]`, discarding any held item.
```
**Fix:** In the STATE_IDLE/STATE_NO_FUEL match branch of Inserter.tick (scripts/world/inserter.gd:151), before attempting pickup, add: if held_item_type(b) >= 0, set b.state["state"] = STATE_WORKING_OUT, clamp b.state["cycle_progress"] to [0.0, 0.5] (it is preserved across the NO_FUEL overwrite, so the arm resumes exactly where it stopped; 0.5 re-attempts the drop and re-enters BLOCKED_AT_DEST if still blocked), and skip _try_pickup for that tick. Add a regression test: hand-fuel a basic inserter with exactly 1 wood (via fuel_buffer), tick until fuel exhausts mid-swing with an item held, refuel via fuel_buffer, run to completion, and assert the total item count across source, held_item_buffer, and destination is conserved (no item destroyed, held item eventually delivered).

<details><summary>Verification notes</summary>

- Confirmed. inserter.gd:139-142 unconditionally overwrites any state (incl. WORKING_OUT/BLOCKED_AT_DEST with a held item) to STATE_NO_FUEL when fuel_buffer<=0 and try_pull_fuel fails, without clearing or checking held_item_buffer. Lines 151-159 share the IDLE/NO_FUEL branch: _try_pickup then _set_held (line 214: b.state["held_item_buffer"] = [[item_type, 1]]) blindly replaces the buffer, destroying the previously held item; _try_drop is never called from this branch, so the held item can never be delivered. Reachability verified: burner.gd consume_tick is called 21 times per unblocked basic cycle vs 20 ticks per fuel unit, so the exhaustion point drifts and lands mid-hold; hand-refuel writes fuel_buffer directly (building_panel.gd:310-331), completing the destruction scenario. No guard exists anywhere on the path, and test_inserter.gd:327-339 only covers NO_FUEL entry from idle — no test covers mid-swing exhaustion or item conservation.
- Confirmed by trace. inserter.gd:139-142 unconditionally overwrites state to STATE_NO_FUEL when fuel_buffer hits 0 and the S fuel port has no supply, even when the inserter is WORKING_OUT/BLOCKED_AT_DEST with held_item_buffer populated. After refuel via panel (building_panel.gd:331), the shared STATE_IDLE/STATE_NO_FUEL branch (inserter.gd:151-157) calls _try_pickup — which never checks held_item_type — and _set_held (:213-214) replaces held_item_buffer, destroying the held item (source item already removed at :278); if the source is empty the held item is stranded forever since the branch never attempts a drop. One correction to the reviewer's concrete scenario: with fresh 1 wood at fuel_burn_progress 0, the 20th burn tick lands during WORKING_IN (hand empty), not the swing-out — a cycle costs 21 consume ticks (1 pickup + 10 out + 10 in). The bug is still reachable: exhaustion lands at cumulative consume tick 20u, and 20u mod 21 falls in the held-item window {1..11} whenever u mod 21 is in {10..20} (e.g. 11 cumulative wood units → exhaustion mid-WORKING_OUT at cycle_progress 0.45; 10 units + blocked drop → NO_FUEL overwriting BLOCKED_AT_DEST). Hand-fed inserters running dry hit these residues routinely, so item destruction is a real recurring outcome, not a corner case.

</details>

### 3. Inserter drop uses aggregate in_buffer capacity, permanently deadlocking mixed-input processors (Oven, Mixer)
**Where:** `scripts/world/inserter.gd:375` | **Category:** bug, found by sim-core

Processor input capacity is per item type (processor.gd line 105: `_buffer_count(b.state["in_buffer"], item_type) >= capacity`), so an Oven can legitimately hold 8 risen dough plus 8 briquettes in the shared in_buffer. Inserter._drop_to_processor instead sums ALL entries in in_buffer and rejects the drop when the aggregate reaches the slot's max_stack (8). Concrete deadlock: Oven fed risen dough by belt (Processor pulls dough until 8/8) and fuel briquettes by inserter. Once in_buffer holds 8 dough and 0 briquettes, the recipe cannot start (missing fuel input), so the buffer never drains; the inserter's capacity check `current_total >= cap` fails forever; the inserter sits in BLOCKED_AT_DEST and the whole bread line halts permanently. The same happens on the Mixer (flour fills 8, yeast can never be inserted).

**Evidence:**
```
Lines 369-376: `var current_total: int = 0; for entry in in_buf: current_total += int(entry[1]); ... var cap: int = int(slot.get("max_stack", 8)); if current_total >= cap: return false` — versus Processor._try_pull_inputs which caps per item: `if _buffer_count(b.state["in_buffer"], item_type) >= capacity: continue`.
```
**Fix:** In Inserter._drop_to_processor (scripts/world/inserter.gd:368-376), replace the aggregate sum with a per-item-type count mirroring Processor pull semantics: delete the current_total loop and change the check to `if Processor._buffer_count(in_buf, item) >= cap: return false` (with `var in_buf: Array = dst.state.get("in_buffer", [])` kept above it). Optionally, to also honor the stale comment at lines 372-373, derive cap from the building's current recipe when set: `var recipe: Dictionary = Recipes.get_recipe(str(dst.state.get("recipe_id", ""))); var cap: int = int(recipe["input_capacity"]) if not recipe.is_empty() else int(slot.get("max_stack", 8))` — both values are 8 today, so the minimal per-item fix alone resolves the deadlock. Add a regression test: fill an Oven's in_buffer with 8 RISEN_DOUGH, verify _drop_to_processor still accepts a FUEL_BRIQUETTE and rejects a 9th RISEN_DOUGH.

<details><summary>Verification notes</summary>

- Confirmed. inserter.gd:368-376 aggregates ALL in_buffer entries against the single slot's max_stack (8), while Processor caps per item type (processor.gd:97,105 input_capacity=8). Oven (buildings.gd:287-303, comment: "both inputs share in_buffer (multi-type bag)") and Mixer (buildings.gd:213-233) have two input slots sharing state_field "in_buffer"; recipes oven_bread (recipes.gd:82) and mixer_dough (recipes.gd:55) need both item types to start. Belt pull fills the first input to 8; the inserter-fed second input then always fails the aggregate check, the recipe can never start (_has_all_inputs, processor.gd:144-150), the buffer never drains, and the inserter retries forever in STATE_BLOCKED_AT_DEST (inserter.gd:172-181) with no fallback. Inserter-to-processor-input is an explicitly supported path (inserter.gd:15-16, _drop_to_processor). Note also comment drift at inserter.gd:372-373 ("use recipe capacity if a recipe is set") which the code never implements. 33/33 tests passing is consistent — no test covers inserter-fed mixed-input processors.
- Reproduced by trace. Oven's two input slots (buildings.gd 288-297) share state_field "in_buffer"; Processor._try_pull_inputs caps per item type (processor.gd:105, input_capacity=8 documented "per item type" in recipes.gd:17), so a W-belt legitimately fills in_buffer to [[RISEN_DOUGH,8]] whenever briquettes lag. Then _has_all_inputs (processor.gd:144-150) fails on fuel, buffer never drains, and Inserter._drop_to_processor sums ALL entries (inserter.gd:369-371) against cap=8 (line 374), returning false at 375-376 forever. Inserter enters STATE_BLOCKED_AT_DEST (inserter.gd:172) and retries/fails every tick (line 178) — absorbing deadlock. Same for inserter-fed yeast on Mixer (buildings.gd:215-223). Only caveat: all-belt feeds are unaffected (Oven fuel has a DIR_S belt port, recipes.gd:82), so the bug requires an inserter-fed second input — a fully supported topology.

</details>

### 4. Fertilizer Applicator never pulls or applies COMPOST_HIGH despite DATA advertising wasteland-recovery automation
**Where:** `scripts/world/fertilizer_applicator.gd:156` | **Category:** bug, found by sim-core

buildings.gd's FERTILIZER_APPLICATOR slot_layout (line 607) accepts COMPOST_LOW/MID/HIGH with the comment 'Session 4: HIGH tier added so applicators can be belt-fed Premium Compost for wasteland-recovery automation.' But the tick logic was never updated: _try_pull_input's accept list contains only COMPOST_LOW and COMPOST_MID, so belt-fed Premium Compost is never pulled; and _select_fertilizer_from_buffer only checks MID then LOW, so even a hand-dropped COMPOST_HIGH in the buffer is never selected (returns -1, which sets the machine to STATE_IDLE at line 118-119 despite has_input being true). The advertised wasteland-recovery automation is completely non-functional, and HIGH items dropped into the slot consume buffer capacity while doing nothing.

**Evidence:**
```
Lines 155-156: `Belt.try_pull_matching(neighbor, b.anchor, [Items.Type.COMPOST_LOW, Items.Type.COMPOST_MID])`; lines 170-178 check only `Items.Type.COMPOST_MID` then `Items.Type.COMPOST_LOW`; buildings.gd line 607: `"accepts": [Items.Type.COMPOST_LOW, Items.Type.COMPOST_MID, Items.Type.COMPOST_HIGH]`.
```
**Fix:** In scripts/world/fertilizer_applicator.gd: (1) add Items.Type.COMPOST_HIGH to the pull list at lines 155-156; (2) add a highest-priority HIGH pass in _select_fertilizer_from_buffer (HIGH > MID > LOW) and update its "only 2 valid item types" comment; (3) in _pick_most_depleted_eligible_tile (and _count_eligible_tiles), skip tiles where world.is_wasteland_at(pos) is true when selected_tier != COMPOST_HIGH — otherwise a MID-loaded applicator adjacent to wasteland picks the scarred tile, try_apply_fertilizer rejects it (grid_world.gd:703-704), and the machine wedges in STATE_BLOCKED while healthy depleted tiles go unserved. Note wasteland tiles ARE correctly eligible for HIGH (tier -1 < HIGH; soil below full) and try_apply_fertilizer's wasteland branch handles restoration. Add tests in scripts/tests/test_fertilizer_applicator.gd: (a) belt-fed COMPOST_HIGH is pulled and de-wastelands a scarred tile in coverage after APPLY_INTERVAL_TICKS; (b) buffer with HIGH only does not idle-wedge; (c) MID-loaded applicator skips a scarred tile and applies to a normal depleted tile.

<details><summary>Verification notes</summary>

- Confirmed. buildings.gd:602-610 advertises COMPOST_HIGH acceptance ("Session 4 ... wasteland-recovery automation" comment at 605-607) and building_panel.gd:274-280 enforces that accepts list, so HIGH really can enter in_buffer by hand-drop. But fertilizer_applicator.gd:155-156 pulls only [COMPOST_LOW, COMPOST_MID] (the only automation intake), and _select_fertilizer_from_buffer (168-178) checks only MID then LOW — a HIGH-only buffer returns -1, hitting the lines 118-119 branch that sets STATE_IDLE despite has_input==true, leaving the HIGH item dead in the buffer. grid_world.gd:690-716 shows try_apply_fertilizer fully supports HIGH including wasteland restore (702-705), so no guard elsewhere compensates; the applicator simply never invokes it with HIGH. Test gap also real: test_fertilizer_applicator.gd has zero HIGH/wasteland coverage (test_wasteland.gd covers hand-apply only). The 33/33 passing suite never exercises the broken path.
- Reproduced by trace. (1) Belt-fed path: fertilizer_applicator.gd:155-156 passes accept list [COMPOST_LOW, COMPOST_MID] to Belt.try_pull_matching; belt.gd:139 rejects any slot item not in that list and returns -1 (belt.gd:143), so a belt carrying COMPOST_HIGH is never pulled — buffer stays empty, applicator stays STATE_IDLE forever, contradicting buildings.gd:605-607 whose slot_layout accepts COMPOST_HIGH with the explicit 'belt-fed Premium Compost for wasteland-recovery automation' comment. (2) Hand-drop path: building_panel.gd:274-280 validates drops against the slot_layout accepts list, so COMPOST_HIGH CAN land in in_buffer; next tick has_input is true (line 93), scan reaches threshold, but _select_fertilizer_from_buffer (lines 170-178) only checks COMPOST_MID then COMPOST_LOW and returns -1 for a HIGH-only buffer, hitting the 'defensive corruption' branch at lines 118-120 which sets STATE_IDLE — the HIGH item sits inert consuming INPUT_BUFFER_CAPACITY (line 146); mixed with LOW/MID it is skipped as dead weight while lower tiers are applied. (3) Downstream support exists and is wasted: grid_world.gd:690-716 try_apply_fertilizer handles HIGH including the wasteland-restore branch (702-706), and enum ordering (grid_world.gd:109, items.gd:58) makes HIGH > MID > LOW comparisons valid — only the applicator's two hardcoded lists were never updated. Not a CONVENTIONS.md violation (int() coercion is used throughout); it is a genuine logic bug. The 33/33 passing suite covers hand-apply HIGH (test_wasteland.gd:111-231) but has no applicator-with-HIGH test, which is why it passes.

</details>

### 5. One scarred wasteland tile in coverage permanently blocks the applicator for LOW/MID compost
**Where:** `scripts/world/fertilizer_applicator.gd:212` | **Category:** bug, found by sim-core

_pick_most_depleted_eligible_tile filters on soil<100 and fertilizer tier, but never checks GridWorld.is_wasteland_at. A scarred tile has soil_health 0 (it stays in tile_soil_modifications because regen is skipped), so it always wins the 'most depleted' sort. The tick comment claims 'try_apply_fertilizer returns false only on lower-tier-rejected, which _pick_most_depleted_eligible_tile already filters', but grid_world.gd lines 702-704 also reject LOW/MID on scarred tiles (`if is_wasteland_at(pos): if tier != Items.Type.COMPOST_HIGH: return false`). Result: applicator loaded with LOW/MID picks the scarred tile every tick, try_apply_fertilizer returns false, state becomes STATE_BLOCKED, and the identical target is re-picked forever — even when other eligible depleted tiles (soil 20-60) sit in the same 5x5. The soil-recovery automation dies precisely in the wasteland scenario it exists to mitigate.

**Evidence:**
```
Lines 207-213 eligibility checks: `if soil >= GridWorld.TILE_SOIL_FULL: continue` and `if current_tier >= selected_tier: continue` — no is_wasteland_at check; grid_world.gd 702-704: `if is_wasteland_at(pos): if tier != Items.Type.COMPOST_HIGH: return false`.
```
**Fix:** In fertilizer_applicator.gd, add a wasteland guard to BOTH _pick_most_depleted_eligible_tile and _count_eligible_tiles, after the bounds checks: `if world.is_wasteland_at(pos) and selected_tier != Items.Type.COMPOST_HIGH: continue`. (The HIGH exemption is currently unreachable via belt pull, which only accepts LOW/MID, but buildings.gd line 607 already lists COMPOST_HIGH in the applicator's drag-drop accepts, so keep it for forward-compatibility with HIGH-loaded applicators de-wastelanding tiles.) Also correct the stale comment at lines 129-131 to note that try_apply_fertilizer can additionally return false for non-HIGH tiers on wasteland, now filtered by the picker. Add a regression test in scripts/tests/test_fertilizer_applicator.gd: scar one tile in coverage (soil 0, grace expired), deplete a second tile to e.g. 40, load the applicator with COMPOST_LOW, tick past APPLY_INTERVAL_TICKS, assert the boost lands on the non-scarred tile and state returns to SCANNING rather than sticking in STATE_BLOCKED.

<details><summary>Verification notes</summary>

- Confirmed. fertilizer_applicator.gd _pick_most_depleted_eligible_tile (lines 196-222) checks only bounds, soil<100 (209), and fertilizer tier (212) — no is_wasteland_at. A scarred tile's soil_health is permanently 0 (grid_world.gd 616 reads tile_soil_modifications; regen loop skips scarred tiles at 1106-1107 and never erases the entry), so it always wins the most-depleted sort over any other eligible tile. tile_fertilizer_tier returns -1 on scarred tiles, so the tier filter passes. try_apply_fertilizer (grid_world.gd 702-704) rejects any tier != COMPOST_HIGH on wasteland, and the applicator can only ever select LOW/MID (_try_pull_input line 156, _select_fertilizer_from_buffer 168-178). tick() line 137 sets STATE_BLOCKED; on subsequent ticks scan_progress sits at threshold (line 105 skipped) and the same scarred target is deterministically re-picked forever — a permanent stall even with other depleted tiles (soil 20-60) in coverage. The comment at lines 129-131 ("returns false only on lower-tier-rejected") is factually wrong. No test covers applicator+wasteland (test_fertilizer_applicator.gd has none). Bonus inconsistency: _count_eligible_tiles (291-305) counts the scarred tile, so Q-inspect shows a nonzero eligible count alongside the "BLOCKED — no eligible tiles" status.
- Reproduced by trace. Scarred tile stays at soil 0 (regen skipped, grid_world.gd:1103-1108) so tile_soil_health=0 always wins the most-depleted sort (fertilizer_applicator.gd:198, 216); eligibility checks at lines 209/212 lack any is_wasteland_at test and tile_fertilizer_tier returns -1 on scarred tiles. try_apply_fertilizer rejects LOW/MID on wasteland (grid_world.gd:702-704), and the applicator can only ever hold LOW/MID (pull filter, fertilizer_applicator.gd:156). Tick then sets STATE_BLOCKED (line 137); with scan_progress held at threshold the identical target is deterministically re-picked every tick — permanent deadlock even when other eligible tiles (soil 20-60) are in coverage. The comment at lines 129-131 claiming false is only lower-tier-rejected is wrong. _count_eligible_tiles (lines 291-305) shares the bug, so the panel shows the dead tile as eligible while status says BLOCKED.

</details>

### 6. Mid-cycle fuel exhaustion overwrites working state and destroys the held item on refuel
**Where:** `scripts/world/inserter.gd:141` | **Category:** bug, found by machines
> Duplicate of finding #2 (independently rediscovered by a second dimension -- kept for its extra evidence).

Inserter.tick's fuel gate runs before the state machine and unconditionally sets STATE_NO_FUEL when the buffer is empty and no fuel is adjacent, even if the inserter is in WORKING_OUT/BLOCKED_AT_DEST/WORKING_IN while holding an item (fuel can hit 0 mid-swing because fuel_burn_progress carries across cycles). When fuel later arrives, the STATE_IDLE/STATE_NO_FUEL branch calls _try_pickup and _set_held, which replaces held_item_buffer with the newly picked item — the item the arm was carrying is silently deleted. If the source is empty instead, the inserter idles forever while still holding the stranded item. Scenario: inserter with fuel_buffer=1 and carried-over fuel_burn_progress starts a swing; buffer hits 0 mid-swing; adjacent chest is out of wood for a few seconds; state becomes NO_FUEL with an iron ore in hand; player refills wood; next tick the inserter picks a NEW ore from the source belt and the held ore vanishes from the world.

**Evidence:**
```
if fuel_units <= 0:
	if not Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR)):
		b.state["state"] = STATE_NO_FUEL
		return
...
match s:
	STATE_IDLE, STATE_NO_FUEL:
		var picked: int = _try_pickup(b, world)
		if picked >= 0:
			_set_held(b, picked)
```
**Fix:** Two-part fix in scripts/world/inserter.gd tick(): (1) Move the state read above the fuel gate and only stamp NO_FUEL from resting states, freezing working states in place so the swing resumes intact on refuel: `var s: int = int(b.state.get("state", STATE_IDLE))` first, then in the gate `if not Burner.try_pull_fuel(...): if s == STATE_IDLE or s == STATE_NO_FUEL: b.state["state"] = STATE_NO_FUEL; return` — held_item_buffer and cycle_progress are untouched, so WORKING_OUT/BLOCKED_AT_DEST/WORKING_IN resume exactly where they stopped. (If the NO_FUEL tint should still show while frozen mid-swing, add a separate boolean state flag e.g. "fuel_starved" set/cleared at the gate and read by draw()/info_lines instead of overloading "state".) (2) Defense-in-depth in the STATE_IDLE/STATE_NO_FUEL branch: before _try_pickup, `if held_item_type(b) >= 0:` restore the interrupted swing instead of picking (`b.state["state"] = STATE_BLOCKED_AT_DEST if float(b.state.get("cycle_progress", 0.0)) >= 0.5 else STATE_WORKING_OUT`) so any legacy/saved state holding an item can never be overwritten by _set_held. Add a regression test: inserter with fuel_buffer=1 and fuel_burn_progress preset near ticks_per_unit, run until NO_FUEL occurs mid-swing with an item held, refill fuel chest, tick on, and assert total item conservation plus eventual delivery of the originally held item.

<details><summary>Verification notes</summary>

- Confirmed. The fuel gate (inserter.gd:138-141) runs before the state match and unconditionally sets STATE_NO_FUEL on empty buffer + failed pull, regardless of current state. Mid-swing exhaustion is reachable: Burner.consume_tick (burner.gd:125-134) carries fuel_burn_progress across cycles and each cycle makes ticks+1 consume calls vs ticks_per_unit=ticks (pickup tick at line 159 plus per-tick at 174/190; BLOCKED ticks consume none), so with fuel_buffer=1 the unit-completion tick generically lands inside WORKING_OUT while held_item_buffer is populated. After refuel, s==STATE_NO_FUEL matches the STATE_IDLE/STATE_NO_FUEL branch (line 151) which calls _try_pickup then _set_held (line 155); _set_held (line 214) unconditionally replaces held_item_buffer, deleting the carried item. If the source is empty the inserter idles in NO_FUEL holding the stranded item with no resume path. No guard exists anywhere in the file (the IDLE/NO_FUEL branch never checks held_item_type), and test_inserter.gd only tests cold-start NO_FUEL and wood conservation in that scenario (lines 327-359) — no mid-swing-exhaustion or refuel-with-held-item test, so 33/33 passing does not contradict the bug.
- Confirmed by concrete trace. The fuel gate (inserter.gd:139-142) runs before the state machine and unconditionally overwrites any state with STATE_NO_FUEL when fuel_buffer<=0 and no adjacent fuel, even in WORKING_OUT/BLOCKED_AT_DEST with an item in held_item_buffer. Fuel genuinely expires mid-swing: Burner.consume_tick (burner.gd:125-134) carries fuel_burn_progress across cycles, and a full cycle makes 21 consume calls (start tick :159 + 10 out :174 + 10 in :190) against ticks_per_unit=20, so drift is guaranteed. With fuel_buffer=1, progress=16: buffer hits 0 at cycle_progress=0.2 holding an ore; next tick state becomes NO_FUEL. On refuel, the STATE_IDLE/STATE_NO_FUEL branch (:151-159) calls _try_pickup (removes a new item from the source) then _set_held (:213-214), which assigns held_item_buffer=[[new,1]], deleting the previously held item (already removed from its belt slot at :278 — no other copy exists). If the source is empty, the inserter idles forever holding the stranded item since _try_drop is only reachable from WORKING_OUT/BLOCKED_AT_DEST. Tests (33/33) don't cover mid-swing fuel exhaustion.

</details>

### 7. Grace timer runs on actively-farmed soil-0 tiles where regen is blocked, making the documented fertilizer rescue impossible
**Where:** `scripts/world/grid_world.gd:1090` | **Category:** bug, found by soil-worldgen

In _tick_soil_regen the wasteland grace timer is decremented (lines 1077-1094) BEFORE the active-farming check at line 1109, which does `tile_regen_progress.erase(pos); continue`, skipping all regen (including the fertilizer boost read at line 1119). So a soil-0 tile inside any active planter's 3x3 accrues grace decay every frame while its soil can never rise. The documented rescue path (try_apply_fertilizer comment, lines 683-688: 'the boost adds soil -> regen tick lifts soil > 0 -> grace entry erased') therefore never fires for actively-farmed tiles: the player sees the 'will scar in Xs' countdown, applies Premium Compost, try_apply_fertilizer returns true, main.gd consumes the item — and the tile scars at grace expiry anyway. Note this is effectively the ONLY organic scarring path: an inactive soil-0 tile always self-rescues (30 s/point regen < 60 s grace), so every real scar happens exactly where the advertised counter-play is a silent no-op. test_wasteland.gd's grace-rescue suite (case 9) only tests the no-active-planter case, so the gap is untested.

**Evidence:**
```
ws["decay_remaining"] = float(ws["decay_remaining"]) - delta
...
if active_tiles.has(pos):
	tile_regen_progress.erase(pos)
	continue
```
**Fix:** In _tick_soil_regen, gate the grace-timer decrement on the tile not being actively farmed: wrap lines 1090-1094 in `if not active_tiles.has(pos):` (active_tiles is already computed at line 1054, before the loop, so no reordering is needed). This pauses the scar countdown while the tile is inside an active planter's 3x3, consistent with the existing rule 'active farming = no regen' — neither decay nor recovery advances while active. Leave the grace-erase else branch (1095-1101) and the same-tick rescue (1136-1139) untouched. Update the comment block at 1071-1076 and the try_apply_fertilizer doc (682-685) to state that grace is paused during active farming. Add a test in test_wasteland.gd: place an active planter (growth > 0 or holding output) whose 3x3 overlaps a soil-0 neighbor, tick past WASTELAND_GRACE_SEC, assert the tile is NOT scarred and grace_remaining is unchanged; optionally also assert that applying COMPOST_HIGH then deactivating the planter lets boosted regen rescue the tile. Alternative (if the design intent is that active tiles CAN scar): instead let fertilizer-boosted regen run on active soil-0 tiles by moving the active_tiles check after a soil==0-with-boost exception — but the pause approach is simpler and matches the documented rescue promise.

**SHIPPED at `b92a769` (2026-08-23) — the Alternative, NOT the prescribed Fix. Do not re-apply the prescribed Fix.**
The prescribed fix (wrapping the grace decrement in `if not active_tiles.has(pos):`) was **rejected**: it contradicts a recorded design decision. `PROJECT_LOG.md:775` describes the `wasteland <x> <y>` console command as forcing scarred state at a tile "(bypasses 60-sec grace). Required for testing wasteland mechanics without setting up active planters to keep soil pinned at 0." — i.e. active planters pinning soil at 0 IS the organic scarring path, on the record. The audit's own text concedes the point ("this active-tile path is effectively the only organic scarring route") without following it through. Under the prescribed fix a **continuously**-active planter holds its soil-0 neighbours at `grace = 60.00` forever, so the one scarring path the player can find and understand is gone, and the whole Session 4 arc (v18 schema, wasteland visuals, Premium Compost recipes, the applicator recovery path that closed #4/#5) becomes console-only dead content. The finding is real; the prescription would have traded a broken counter-play for a dead mechanic.

**Correction (2026-08-23), and this entry is the correcting record.** The reasoning above originally rested on "an inactive soil-0 tile always self-rescues (`SECONDS_PER_SOIL_POINT` 30 < `WASTELAND_GRACE_SEC` 60)". **That claim is false as stated**, and `b92a769`'s commit message carries it; the commit is on a shared index and cannot be amended, so the correction lives here. Self-rescue is only guaranteed for a tile that is inactive across the **entire** grace window from soil-0 onset — 30 beats 60 only when the full 60 is available. Measured counter-example on shipped `main`: burn a soil-0 tile's grace down to 15.0 s under an active planter, then let the planter go idle; `tile_regen_progress` was erased on the last active frame, so the tile needs 30 s for +1 soil and has 15 s of grace, and it scars while **fully inactive**. Consequence for the rejection: an *oscillating* planter could still scar a tile even with grace paused, so "organically unreachable" was too strong. The conclusion is unchanged — the argument that carries it is the documented, discoverable path (`PROJECT_LOG.md:775`), not the arithmetic. A future reader spot-checking the old premise would have found it wrong and could have concluded the whole rejection was unfounded. Live copies of the false claim were corrected at the same time in `grid_world.gd` `_tick_soil_regen` and `test_wasteland.gd` sub-suite 10b. The audit's own finding text and Verification notes above are a dated record and are left as written.

What shipped is the Alternative, scoped narrowly: `grid_world.gd` `_tick_soil_regen` now reads `if active_tiles.has(pos) and not (soil_now == 0 and _fertilizer_boost_multiplier(pos) > 1.0):`. The exception requires soil == 0 **and** a live boost, so "active farming = no regen" still holds for boosted tiles above soil 0; scarred tiles `continue` earlier and can never reach it. Once soil hits 1 the exception lapses and the planter's next harvest takes the tile back to 0 — fertilizer buys the player out of scarring, not out of depletion. The `_tick_soil_regen` doc block and the `try_apply_fertilizer` "Grace rescue" doc were corrected in the same commit; the latter had promised a rescue it could not deliver.

Coverage is `test_wasteland.gd` sub-suite 10, which is built to keep this decision from being re-litigated silently. RED before the fix was exactly the two 10a assertions. Mutation-tested three ways: reverting to the plain `if active_tiles.has(pos):` reddens **10a**; implementing the prescribed pause-grace fix instead reddens **10b** (the control asserting an *unfertilized* soil-0 tile under an active planter still scars) *and* 10a's soil assertion, proving the two candidate designs are distinguishable by test; dropping the `soil_now == 0` clause reddens **10c** (soil climbs 50 → 58). 10b exists specifically so a future session that "simplifies" this into the prescribed fix gets a failure instead of a green suite.

**Follow-up shipped 2026-08-23: the symptom survived near the end of grace.** The exception lets the boost regenerate an actively-farmed soil-0 tile, but the boost delivers its first soil point only after `SECONDS_PER_SOIL_POINT / fertilizer_multiplier(tier)` seconds — **3.75 s** (HIGH, 8×), **7.5 s** (MID, 4×), **15 s** (LOW, 2×). Applied with less grace left than that, `try_apply_fertilizer` still returned `true`, `main.gd` consumed the compost, and the tile scarred anyway: measured on shipped `main` at 0.1 s ticks, HIGH at 3.09 s grace → consumed, scarred at soil 0; HIGH at 5.09 s → rescued. Verbatim the audit's own repro, and the "will scar in Xs" countdown invites exactly that late application. `try_apply_fertilizer` now **refuses** an apply whose tier cannot lift soil before the grace runs out, on the same reasoning as the LOW/MID-on-scar rejection: the player keeps the compost, and the tile scars either way. Boost *duration* is not also binding — LOW 30 s ≥ 15 s, MID 60 s ≥ 7.5 s, HIGH 120 s ≥ 3.75 s. The gate ignores accumulated `tile_regen_progress` (not serialized per design Q5, so the decision must not flip across a save/load); ignoring it can only refuse conservatively on a tile that then rescues itself, which costs the player nothing. The predicate is public (`GridWorld.grace_admits_tier`) because `FertilizerApplicator._tile_eligible` must ask it too — a soil-0 tile in grace wins the most-depleted sort every time, so a picker that nominated tiles the apply refuses would sit BLOCKED re-nominating the same tile until it scarred, which is **#5's shape** again. Coverage is `test_wasteland.gd` sub-suite **11** (a: per-tier boundary; b: honest outcome through real ticks; c: the scarred-tile restore path stays immune; d: picker/apply agreement); RED before the fix was 10 assertions. Mutation-tested three ways: deleting the rejection reddens 9 of them; hardcoding the threshold at HIGH's 3.75 s reddens exactly the MID and LOW boundary cases (4 assertions), proving the per-tier derivation is guarded; removing the `_tile_eligible` gate reddens 11d's eligibility assertion alone.

<details><summary>Verification notes</summary>

- Confirmed by direct code reading. (1) Quoted code exists as claimed: grid_world.gd lines 1078-1094 advance the grace timer unconditionally for every soil-0 tile, and lines 1109-1113 (`if active_tiles.has(pos): tile_regen_progress.erase(pos); continue`) skip the entire regen block — including the fertilizer boost read at 1119 and the same-tick grace erase at 1136-1139 — for tiles in an active planter's 3x3. (2) No guard elsewhere: the only paths that erase an unscarred grace entry are lines 1101 and 1139, both gated on soil rising above 0, which cannot happen while the active check blocks regen (verified via grep: tile_wasteland_state.erase appears only at 775 (scarred restore), 1101, 1139). try_apply_fertilizer (lines 690-716) never adds soil for unscarred tiles — it only writes boost state and returns true, so main.gd consumes the item while the rescue silently cannot occur. (3) Scenario reachable: Planter.is_active (planter.gd:146-147) is true during growth OR while holding uncollected ripe output (indefinitely), and planter_panel.gd:126-131 confirms cycles continue with soil at 0; adjacent planters with overlapping 3x3s or a growing/ripe planter beside a depleted neighbor keeps a soil-0 tile active past the 60s grace (WASTELAND_GRACE_SEC=60, line 133). The 'will scar in Xs' countdown is shown to the player (info_panel.gd:269, console.gd:771). (4) Test gap confirmed: test_wasteland.gd case 9 (lines 235-263) places no planter — no test covers grace + active tile. (5) Side claim also checks out: inactive soil-0 tiles self-rescue since SECONDS_PER_SOIL_POINT=30 < 60s grace. This is a genuine behavior/documentation contradiction (try_apply_fertilizer doc lines 682-685 promises a rescue that is a no-op on active tiles) plus a silent item-consumption bug.
- Confirmed by trace. Grace timer advances at grid_world.gd:1090 before the active-tiles early-continue at 1109-1113, which skips the fertilizer-boost regen at 1119-1129. A soil-0 tile in an active planter's 3x3 (active = growth>0 or output>0, planter.gd:146-147) therefore counts down 60s (WASTELAND_GRACE_SEC, line 133) while soil is pinned at 0. try_apply_fertilizer (line 690) succeeds during grace (is_wasteland_at false pre-scar, lines 751-753) and main.gd:735 consumes the item, but fertilizer only writes boost state — soil never rises, so the documented rescue (comment lines 682-685) never triggers and the tile scars at 1091-1092. Inactive soil-0 tiles always self-rescue (30s/point regen < 60s grace), so this active-tile path is effectively the only organic scarring route. test_wasteland.gd case 9 (lines 235-263) creates no buildings, so active_tiles is empty and the gap is untested; 33/33 passing is consistent with the bug.

</details>

### 8. Taking from an input/output slot destroys every other entry in a shared buffer
**Where:** `scripts/ui/building_panel.gd:369` | **Category:** bug, found by ui-panels

BuildingPanel._take_from_slot for kinds "input"/"output" picks only buf[0] onto the cursor but then calls buf.clear(), erasing ALL entries in the state buffer. Several buildings bind multiple panel slots to the SAME state field: Mixer's two input slots both use state_field "in_buffer" (buildings.gd:217,222), Oven's dough+briquette inputs share "in_buffer" (buildings.gd:291,296), and Thresher's grain+straw outputs share "out_buffer" (buildings.gd:249,251). Processor._try_pull_inputs routinely fills these buffers with both item types during normal belt-fed play (processor.gd:140 adds every pulled input to in_buffer). So clicking any of these slots with an empty cursor gives the player buf[0] (which may not even be the item type the clicked slot is labeled for — clicking the Mixer's Yeast slot yields flour) and permanently deletes the second entry. This is guaranteed item destruction in routine gameplay, not an edge case.

**Evidence:**
```
"input", "output":
    var buf: Array = building.state.get(field, [])
    if buf.is_empty():
        return
    var entry = buf[0]
    cursor.pick(int(entry[0]), int(entry[1]))
    buf.clear()
    building.state[field] = buf
```
**Fix:** In building_panel.gd _take_from_slot, "input"/"output" branch: instead of taking buf[0] and clearing, resolve the entry belonging to the clicked slot and remove only it. E.g.: var accepts: Array = slot_def.get("accepts", []); var idx: int = -1; if accepts.is_empty(): idx = 0 else: for i in buf.size(): if int(buf[i][0]) in accepts: idx = i; break. If idx == -1 return (the slot's item type isn't in the buffer — nothing to take even though a sibling slot's item is). Then cursor.pick(int(buf[idx][0]), int(buf[idx][1])); buf.remove_at(idx); building.state[field] = buf. This preserves sibling entries in shared buffers (Mixer/Oven in_buffer, Thresher out_buffer), fixes the wrong-item pick (Yeast slot no longer yields flour), and for empty/multi-accepts slot defs (idx=0 + remove_at) degrades to the old single-entry behavior without destroying extra entries. Add a regression test: fill a Thresher out_buffer with grain+straw, _take_from_slot on the grain slot, assert cursor holds grain and out_buffer still contains the straw entry.

<details><summary>Verification notes</summary>

- Confirmed. building_panel.gd:362-370 matches the quoted code exactly: "input"/"output" take picks buf[0] then buf.clear(). Shared-field bindings verified in scripts/world/buildings.gd — Mixer input_flour/input_yeast both bind "in_buffer" (lines 217, 222), Oven input_dough/input_fuel share "in_buffer" (291, 296), Thresher output_grain/output_straw share "out_buffer" (249, 251). Buffers genuinely hold multiple type-entries concurrently: processor.gd:140 (_try_pull_inputs appends every belt-pulled input type into in_buffer) and processor.gd:191-193 (_emit_outputs adds ALL recipe outputs to out_buffer — Thresher's wheat→grain+straw recipe puts two entries in out_buffer every craft, confirmed at recipes.gd:24). Click dispatch is unguarded: _gui_input → _handle_building_slot_click (line 256) calls _take_from_slot whenever cursor is empty. Grep across scripts/ui shows only planter_panel.gd overrides _take_from_slot; mixer_panel extends BuildingPanel, thresher_panel/oven_panel extend ProcessorPanel which extends BuildingPanel — none override the take path. Existing tests (test_building_ui.gd:204,227; test_building_ui_4.gd:121-128) only exercise fuel, output_multi, and single-entry buffers, so the 33/33 pass does not cover the multi-entry case. Clicking the Thresher grain slot while out_buffer holds [[GRAIN,n],[STRAW,m]] yields whichever entry is index 0 and silently erases the other — guaranteed item destruction in routine belt-fed play, plus the picked item can mismatch the slot label.
- Confirmed by full trace. (1) Shared buffers: buildings.gd — Mixer input_flour/input_yeast both state_field "in_buffer" (lines 217, 222), Oven input_dough/input_fuel share "in_buffer" (291, 296), Thresher output_grain/output_straw share "out_buffer" (249, 251). (2) Buffers genuinely hold multiple typed entries: processor.gd _buffer_add (279-284) appends one [type,count] entry per type; _try_pull_inputs adds every pulled input to in_buffer (140), _emit_outputs adds GRAIN and STRAW to out_buffer (191-193), and recipes.gd:30-33 documents outputs staying buffered when a port lacks a belt. The panel's own _drop_into_input (building_panel.gd:294-305) also builds multi-entry buffers when the player hand-loads both Mixer/Oven inputs. (3) Click path: _handle_building_slot_click (250-256) with empty cursor calls _take_from_slot; for kind "input"/"output" it picks buf[0] and calls buf.clear() (367-369), destroying every other entry. No subclass overrides intervene — grep shows only planter_panel.gd overrides _take_from_slot; mixer_panel.gd overrides only _building_slot_rects/_draw_building_specific, thresher/oven panels override nothing. Concrete repro: Thresher with straw port un-belted accumulates out_buffer=[[GRAIN,3],[STRAW,3]]; player clicks either output slot with empty cursor → cursor gets 3 grain, buf.clear() permanently deletes 3 straw. Mixer: in_buffer=[[FLOUR,2],[YEAST,1]] → clicking the yeast slot yields flour and destroys the yeast. Related symptom: _draw_slots (513-517) also renders buf[0] for both shared slots, so the yeast slot even displays flour. Tests pass 33/33 because existing take tests (test_building_ui.gd:227, test_building_ui_4.gd:121) only exercise single-entry buffers.

</details>

### 9. Every slot bound to the same state_field renders buf[0] — second buffer entry is invisible
**Where:** `scripts/ui/building_panel.gd:516` | **Category:** bug, found by ui-panels

BuildingPanel._draw_slots for "input"/"output" kinds unconditionally displays buf[0] regardless of which slot_def is being rendered. For the Mixer, both the Flour slot and the Yeast slot render the flour entry (buf[0]) with the flour count — the buffered yeast is never shown anywhere; for the Thresher, both the slot labeled "Grain" and the slot labeled "Straw" show whichever entry is first in out_buffer. The display actively lies about slot contents (Straw slot shows Grain x3) and masks the item-loss bug in _take_from_slot: the player clicks a slot showing straw-labeled grain, receives grain, and the straw is silently deleted. Same pattern for Oven (dough+briquette both render the dough entry).

**Evidence:**
```
match kind:
    "input", "output":
        var buf: Array = building.state.get(field, [])
        if not buf.is_empty():
            item_type = int(buf[0][0])
            count = int(buf[0][1])
```
**Fix:** In BuildingPanel._draw_slots ("input"/"output" branch, lines 512-517): every input/output slot_def in buildings.gd carries a single-type "accepts" list, so select the entry by accepted type instead of position — var accepts: Array = slot_def.get("accepts", []); if accepts.size() >= 1: item_type stays -1 unless _buffer_count(buf, int(accepts[0])) > 0, in which case item_type = int(accepts[0]) and count = _buffer_count(buf, int(accepts[0])); fall back to buf[0] only when accepts is empty (preserves current behavior for unconstrained slots). Apply the same accepts-keyed selection in _take_from_slot (lines 362-370) and replace buf.clear() with removing only the matched entry (mirror the "output_multi" branch's remove_at pattern), so taking from the Flour slot leaves the yeast entry intact — otherwise the display fix would expose but not stop the item deletion. Add a test: Mixer with in_buffer=[[FLOUR,2],[YEAST,3]] must render/take yeast from the yeast slot without losing flour.

<details><summary>Verification notes</summary>

- Confirmed. building_panel.gd lines 512-517: "input"/"output" branch reads buf[0] unconditionally, ignoring which slot_def is being drawn. Shared-field layouts are real: buildings.gd lines 215-222 (Mixer: input_flour + input_yeast both state_field "in_buffer"), 248-251 (Thresher: output_grain + output_straw both "out_buffer"), 289-296 (Oven: input_dough + input_fuel both "in_buffer"). Multi-entry buffers are reachable: processor.gd lines 17-18 define buffers as [[type,count],...] bags; _drop_into_input (building_panel.gd 294-308) appends each dropped type into the shared field, and recipes.gd 22-37 shows thresher_wheat emits both GRAIN and STRAW into out_buffer via _buffer_add. No guard exists elsewhere: MixerPanel._building_slot_rects (mixer_panel.gd 41-64) and ProcessorPanel._building_slot_rects (processor_panel.gd 60-104) override only slot POSITIONS; content rendering falls through to the base _draw_slots buf[0] path, and slot labels (drawn from accepts[]) name the wrong item over the buf[0] icon. The masking claim is also confirmed: _take_from_slot lines 362-370 picks buf[0] then buf.clear(), silently deleting the second entry — the comment "one entry — any type" (line 363) documents a single-entry assumption the Mixer/Thresher/Oven layouts violate. No test in scripts/tests/ covers per-slot rendering of shared-field buffers (test_building_ui_3/4 only check structural panel purity).
- Confirmed by trace. buildings.gd: Mixer (lines 213-233) and Oven (287-303) each have two "input" slot_defs sharing state_field "in_buffer"; Thresher (245-252) has two "output" slot_defs sharing "out_buffer". processor.gd _buffer_add (appends per-type entries) plus recipe thresher_wheat (recipes.gd 30-33, outputs GRAIN+STRAW, committed at processor.gd 193) and manual drops via _drop_into_input (building_panel.gd 294-308) produce multi-entry buffers in normal play. building_panel.gd _draw_slots lines 512-517 reads buf[0] for every "input"/"output" slot, ignoring slot_def/accepts — so both Mixer slots render the flour entry and both Thresher slots render whichever entry is first; the second entry is invisible. No subclass (processor_panel.gd, mixer_panel.gd, thresher_panel.gd, oven_panel.gd) overrides _draw_slots. The masking claim also verified: _take_from_slot lines 361-370 picks buf[0] then buf.clear(), silently deleting the unrendered entry when the player clicks a slot showing the wrong item.

</details>

### 10. Buildings that accept Overlay.NONE (Smelter, Composter, Inserters, Applicator) can be placed on water and on top of ore deposits / mature trees
**Where:** `scripts/world/grid_world.gd:396` | **Category:** bug, found by main-console

can_place_building validates only occupancy and 'overlay_at(cell) in allowed_overlays'; it never checks the tile base or resource_node. Water tiles carry Overlay.NONE (Terrain.can_place_overlay forbids overlays on water), and deposit/tree tiles also carry Overlay.NONE per the 'no overlay on deposits' invariant. So every building whose requires_overlay includes Terrain.Overlay.NONE — Smelter (buildings.gd:457), Composter (491), Inserter (526), Fast Inserter (554), Fertilizer Applicator (593) — passes placement on a lake tile or directly on top of an iron vein or mature tree via the normal hotbar path (main.gd _try_place). This defeats the invariant set_overlay enforces ('Mine the iron first' / 'Can't pave over tree') and which MiningDrill.validate_placement explicitly re-implements ('Drill can't extend into water', 'Chop trees from drill area first'): select Smelter in the hotbar, click a water tile from shore → a 2x2 smelter floats mid-lake; click an ore tile → the deposit is buried under the building and no longer minable or inspectable.

**Evidence:**
```
grid_world.gd:392-401 checks only 'if has_building_at(cell)' and 'if not (overlay_at(cell) in allowed_overlays)'; smelter DATA: '"requires_overlay": [Terrain.Overlay.NONE, Terrain.Overlay.STONE, Terrain.Overlay.PATH]'. Only PUMP and MINING_DRILL get type-specific extra rules (grid_world.gd:403-410).
```
**Fix:** In can_place_building's footprint loop (grid_world.gd:392-401), after the occupancy check add: (1) if base_at(cell) == Terrain.Base.WATER: set last_building_place_error = "%s can't be placed on water" % Buildings.name_of(t); return false — apply to all types (harmless duplicate of MiningDrill's own water check). (2) if tiles.has(cell) and tiles[cell].resource_node != ResourceNodes.Type.NONE and t != Buildings.Type.MINING_DRILL: mirror set_overlay's messaging ("Mine the %s first." for ores via ResourceNodes.is_ore, else "Can't build over %s.") and return false. MINING_DRILL is exempted from the resource_node rejection because it must sit on ore; its validate_placement (mining_drill.gd:106-109) already rejects trees and water in-footprint. Add tests: smelter on water fails, smelter on IRON deposit fails, smelter on TREE fails, mining drill on ore still succeeds; also assert regrowth_remaining is not erased by a rejected placement.

<details><summary>Verification notes</summary>

- Confirmed. can_place_building (grid_world.gd:389-411) checks only occupancy (393) and overlay membership (396) plus PUMP/MINING_DRILL specials (403-410); no base or resource_node check. Water tiles are Tile.new(WATER, Overlay.NONE, NONE) (world_generator.gd:276,476) and overlay_at (238-241) returns NONE for them; deposit/tree tiles also carry Overlay.NONE per set_overlay's guard (292-298). Smelter/Composter/Inserter/Fast Inserter/Applicator all list Overlay.NONE (buildings.gd:457,491,526,554,593), so placement passes on water and on ore/tree tiles via main.gd _try_place (651-686), which adds no terrain guard. MiningDrill.validate_placement (mining_drill.gd:104-113) proves the invariant was intended per-building only. test_placement_rules.gd:86's "planter on water" test fails for overlay-mismatch (Planter needs SOIL_TILLED), so no test covers NONE-accepting buildings on water/deposits. Bonus: place_building (427-432) erases regrowth_remaining in footprint, so building over a regrowing tree stump permanently cancels regrowth.
- Reproduced by trace. (1) Water: world_generator.gd:276/476 stores water tiles as Tile.new(Terrain.Base.WATER, Terrain.Overlay.NONE, ...), and Terrain.can_place_overlay (terrain.gd:82-84) guarantees water can never gain an overlay, so overlay_at(waterCell) is always NONE (grid_world.gd:238-241). can_place_building (grid_world.gd:389-411) checks only has_building_at and 'overlay_at(cell) in allowed_overlays', with type-specific extras only for PUMP and MINING_DRILL. Smelter's requires_overlay includes Overlay.NONE (buildings.gd:457, also 491/526/554/593 and PUMP at 427), so can_place_building(SMELTER, waterCell) returns true; place_building (415-435) does no further terrain check; main.gd _try_place (651-686) adds only the player-in-footprint guard. Result: 2x2 smelter placed mid-lake via the normal hotbar path. (2) Ore/tree: deposit tiles carry overlay NONE (invariant confirmed by grid_world.gd:1404 and set_overlay's explicit guard at 291-298 'Mine the iron first' / 'Can't pave over tree'; test_placement_rules.gd:92 seeds Tile(GRASS, NONE, IRON)), so the same overlay check passes and a smelter/inserter lands directly on an iron vein or mature tree, defeating the invariant set_overlay enforces and MiningDrill.validate_placement re-implements (mining_drill.gd:98-114). The 33/33 test pass is consistent: test_placement_rules.gd:86 only tests PLANTER on water, which fails via its SOIL_TILLED overlay requirement, never a NONE-accepting building; no test covers building-on-deposit. CONVENTIONS.md:136 even names 'planters on water' as silent corruption to be avoided, so this violates stated project intent, not just taste.

</details>

## MEDIUM -- real defects, edge-case or workflow-level  (26 findings)

### 11. load_game indexes save-file arrays without shape validation — malformed save crashes load instead of triggering the documented fresh-world fallthrough
**Where:** `scripts/systems/save_system.gd:373` | **Category:** bug, found by save-integrity

The load path only guards against JSON parse failure (line 323). After that, it performs direct indexing on player-authored data: player_pos[0]/[1] with no size check, entry[0]..entry[3] for tile_modifications (only index 4 is size-guarded at line 391), and entry[0]..entry[3] for tile_soil/fertilizer/wasteland entries; typed declarations like `var player_pos: Array = data.get("player", [0, 0])` also raise runtime type errors if the field is a non-Array. CONVENTIONS.md ('Migration robustness') explicitly requires defensiveness because saves 'may have been hand-edited, partially corrupted' and warns that direct reads 'will crash on a hand-truncated save'. Failure scenario: a hand-edited v18 save with "player": [12.0] (one element) or a 3-element tile_modifications entry parses as valid JSON, passes all version checks, then aborts load_game with a script error mid-function; the caller receives no LoadResult (null), so main.gd's `result.success` dereference errors and the documented corrupt-save → fresh-world fallthrough (CONVENTIONS 'Failure handling', main.gd:236-245) never runs — every subsequent boot repeats the failure until the file is deleted manually.

**Evidence:**
```
save_system.gd:372-373: `var player_pos: Array = data.get("player", [0, 0])` / `player.global_position = Vector2(float(player_pos[0]), float(player_pos[1]))`; :390-392 `var pos := Vector2i(int(entry[0]), int(entry[1])) ... Tile.new(int(entry[2]), int(entry[3]), rnode)` with only `entry.size() > 4` guarded; contrast with the one defensive read at :408 `entry[2] if entry.size() > 2 and entry[2] is Dictionary else {}`.
```
**Fix:** In load_game (save_system.gd), validate shape before every direct index. (1) Player: read untyped `var player_pos = data.get("player", [0, 0])`, then `if player_pos is Array and player_pos.size() >= 2:` set position, else push_warning and keep default spawn. (2) For each collection loop (tile_modifications, resource_state_modifications, tile_soil_modifications, tile_fertilizer_state, tile_wasteland_state, explored_regions, buildings): fetch into an untyped var, and if `typeof(x) != TYPE_ARRAY` set result.error_message = "Save field '<name>' has wrong type." , push_error, and return result (so main.gd's fresh-world fallthrough at main.gd:236-245 fires); inside each loop, `if not (entry is Array) or entry.size() < N: push_warning("Skipping malformed <name> entry: %s" % str(entry)); continue` with N = the highest index used + 1 (4 for tile_modifications/fertilizer/wasteland, 3 for soil, 2 for explored_regions/resource_state), mirroring the existing :408 pattern. Also guard `bdict is Dictionary` before Building.from_dict at :465-466 and `data["player_inventory"] is Array` at :473-474. Add a test in scripts/tests/ that writes a v18 save with a 1-element "player" array and a 3-element tile_modifications entry, calls load_game, and asserts a non-null LoadResult is returned (either success with entries skipped, or success=false with error_message) rather than a script error.

<details><summary>Verification notes</summary>

- Confirmed. All quoted code exists: unguarded player_pos[0]/[1] at save_system.gd:372-373; entry[0]..[3] indexed without size checks for tile_modifications (:389-392, only entry[4] guarded), tile_soil (:429-431), tile_fertilizer (:439-444), tile_wasteland (:451-456), explored_regions (:462-463); the sole defensive read is :408. No guard elsewhere — only the JSON-parse/top-level-Dict check (:322-326) and version checks (:329-370) precede the indexing, so a hand-edited v18 save (SAVE_VERSION=18, :121) with matching worldgen_version and a short array reaches the crash. A GDScript out-of-bounds index (or non-Array assigned to typed `player_pos: Array`) aborts load_game with null return; main.gd:231-232 then dereferences null via `result.success`, so the documented fresh-world fallthrough (main.gd:236-245, CONVENTIONS.md:122-126) never runs and the crash repeats every boot. CONVENTIONS.md:114-118 explicitly requires defensiveness for hand-edited/corrupted saves. No test in scripts/tests/ covers malformed entries — all save tests (test_save_load_roundtrip.gd, test_save_migration.gd, test_wasteland.gd:172, test_fertilizer_chain.gd:201) use well-formed data, consistent with 33/33 passing. Minor caveat: the 'Migration robustness' section is textually scoped to migrations, but the Failure-handling contract applies to load_game directly, and the crash stands on its own.

</details>

**CLOSED 2026-08-23 at `61de9ee`.** The two-tier validation above shipped as
prescribed. Coverage is `scripts/tests/test_load_malformed_save.gd`, six
sub-cases asserting on **loaded field values** (seed / player position / flour
count / the surviving tile, chest and soil entries), not on the call's return.
Every fixture is a save the real `save_game` wrote, read back as JSON with one
field edited — so each is genuinely a v18 save that parses and passes every
version check before reaching the indexing. `SAVE_VERSION` did not move;
`test_save_migration.gd`, `test_save_load_roundtrip.gd` and
`test_save_atomicity.gd` pass unmodified.

**RED**, literally: five of the six fixtures made `load_game` return **null**,
with **6 SCRIPT ERRORs** — `Out of bounds get index '1' (on base: 'Array')` at
the player read, `Trying to assign value of type 'String' to a variable of type
'Array'` at the typed declaration, `Invalid access of index '3'` in the
`tile_modifications` loop, `Invalid access of index '1' on a base object of
type: 'String'` in the soil loop, and `Cannot convert argument 1 from String to
Dictionary` at `Building.from_dict` twice. That error count is **expected in RED
and is zero post-fix** — the same convention as the migration suite's
deliberate failure-path ERROR lines. Sub-case 6 (a well-formed save) was
correctly green pre-fix; it is the regression control.

**Three decisions on top of the fix text.**

1. **The type check runs ONCE, up front, over `ARRAY_FIELDS` — not per loop.**
   The fix text puts it inside each collection's block. Hoisting it ahead of the
   first world mutation means a mistyped field cannot leave `grid_world`
   regenerated from the seed with some collections applied and others not, which
   the caller cannot distinguish from a completed load. It also puts the list of
   validated fields in one readable place instead of eight.
2. **Skips are counted and surfaced, which the fix text does not ask for.**
   Silently dropping malformed rows means a player's buildings vanish with no
   indication — a worse failure than a load that says so. The count rides on
   `LoadResult.skipped_entries` and both `main.gd` load sites append it to their
   toast, following the `used_backup` precedent from #12 exactly: a field set on
   the success path only, handled at both call sites. Mutating the counter to
   always report 0 reddens sub-cases 1, 2, 3 and 5, so the count is real rather
   than decorative.
3. **An unreadable `"player"` counts as a skipped entry.** The fix text treats it
   as warn-and-continue only. A silently reset spawn is lost data the player
   reads as the game teleporting them, so it is reported like any other drop.

**`data["player_inventory"] is Array` needs no separate guard**, contrary to the
fix text's last sentence: the field is in `ARRAY_FIELDS`, so a non-Array already
failed the load before the `load_array` call is reached.

**Mutation-tested four ways**, each verified as applied by echoing the mutated
line: dropping `"tile_soil_modifications"` from `ARRAY_FIELDS` reddens sub-case
4a — and note it does *not* crash, it makes the load silently succeed having
discarded the whole collection, which is what the type check is for; removing
the `tile_modifications` entry-size guard reddens sub-case 3 with the original
`Invalid access of index '3'` crash; pinning `result.skipped_entries` to 0
reddens 1, 2, 3 and 5; restoring the typed `var player_pos: Array = ...`
declaration reddens sub-case 2 alone, which is the one fixture that never
reaches an index.

**Residual — CLOSED 2026-08-23, and the note that recorded it was wrong about what
it did.** It read: "a corrupt *row* inside a well-typed `player_inventory` array
crashes there rather than in `load_game`."

**It did not crash the load. It silently truncated the inventory, which is quieter
and worse.** A GDScript runtime error aborts only the INNERMOST function, so the
unguarded `entry[1]` killed `Inventory.load_array` alone and `load_game` carried
straight on to `result.success = true`. Every slot from the bad row onward was never
written, `skipped_entries` stayed **0**, and `main.gd` toasted "World loaded from save
(seed N)" with no suffix at all. The next F5 then wrote the truncated inventory over
the only save slot. A future reader must not go looking for a loud failure — there
was nothing in the log to find.

One of the five corruption shapes produced no log line whatever: a String row such as
`"xy"` is indexable and `int("x")` is `0`, so it raised no error, wrote item id 0 into
the slot, and did not even truncate. Entirely undiagnosed.

Fixed by guarding each row in `load_array` (`entry is Array and entry.size() >= 2`),
clearing the slot rather than leaving a half-parsed id behind, and RETURNING the skip
count so `load_game` can fold it into `skipped`. The return value is the load-bearing
half: a guard alone would have stopped the truncation while still reporting a clean
load. Coverage is sub-case 7 of `test_load_malformed_save.gd`, five shapes
(`[7]` / `7` / `"xy"` / `{"a":1}` / `[]`), asserting on the stack stored AFTER the
corrupted row rather than on the call's return.

Mutation-tested three ways, each verified by echoing the mutated line: removing the
row guard reddens all five shapes (15 assertions) and restores 4 SCRIPT ERRORs;
pinning `load_array`'s return to 0 reddens exactly the five count assertions and
nothing else; dropping the `skipped +=` at the call site does the same, which is what
makes the wiring — not just the guard — a tested claim.

**This does NOT reopen #11.** #11's headline defect is the null return that bricks
the boot, and that remains closed for every shape #11 named. This was the separate,
quieter defect the note above misdescribed. See R2 below for two shapes that DO still
reach #11's headline failure and were found while verifying this one.

**What `skipped_entries` measures, decided rather than left implicit.** The review
asked whether the count should become per-collection so the toast could name which
data was lost. **It stays scalar.** The case that most wants naming does not reach the
count at all: a collection that is present but MISTYPED — `"buildings": {"chest": 1}`
— is not skipped row by row, it fails the load outright through
`_first_mistyped_array_field` with the field named in `error_message`, which sub-case
4b has pinned since `61de9ee`. So "your whole base is gone" is already reported as a
named failure, not as a count of 1. (The review's demonstration of the opposite —
`success=true skipped=1 buildings=0` — does not reproduce against this code; it
predates that guard.) What remains is genuine per-row damage, where a per-collection
breakdown would render as "1 buildings, 1 tiles" and still not answer the question the
player has, which is *how much*. That question is unanswerable from a corrupt row:
the data needed to size the loss is the data that could not be read.

The real defect was therefore not the number but the sentence around it. A row is not
a common unit — one `buildings` row is one building, one `player_inventory` row is a
whole stack, one `player` field is the spawn position — so the count reports
INCIDENCE, never volume. `main.gd._skipped_suffix` now ends "— check your base and
inventory", which is the part the player can act on, and the limit is documented at
`LoadResult.skipped_entries` with the argument above so a future reader can overturn
it deliberately rather than by accident.

### 12. save_game writes the save file non-atomically — a crash mid-write destroys the only save slot
**Where:** `scripts/systems/save_system.gd:296` | **Category:** design-flaw, found by save-integrity

FileAccess.open(save_path, FileAccess.WRITE) truncates the existing save immediately, then the entire JSON blob is written in one store_string call. If the process is killed or power is lost between truncation and completed flush/close, the single save slot (user://save_slot_1.json) is left empty or partially written. A partial file fails JSON.parse on next boot, load returns failure, and main.gd's hotfix silently regenerates a fresh world — the player's entire progress is unrecoverable even though a valid save existed moments before F5. For a single-slot save system with a migration framework this careful about preserving saves across versions, losing the slot to an interrupted write is the bigger practical risk.

**Evidence:**
```
save_system.gd:296-301: `var file := FileAccess.open(save_path, FileAccess.WRITE) ... file.store_string(JSON.stringify(data)) file.close()` — no temp file, no rename, no backup of the previous save.
```
**Fix:** In save_game, derive paths from the current static save_path (tests override it, line 127): (1) write JSON to save_path + ".tmp" and close; (2) if the real save exists, rename it to save_path + ".bak" via DirAccess.rename_absolute (or copy_absolute); (3) rename the .tmp over save_path with DirAccess.rename_absolute — atomic on the same filesystem [**FALSE ON WINDOWS — see the CLOSED note below.** `DirAccess.rename_absolute` unlinks an existing destination before renaming (`DirAccessWindows::rename`), verified empirically: renaming a *missing* source over an existing destination destroyed the destination and returned an error. A direct .tmp → save_path rename therefore has its own delete-then-rename window with nothing backed up. Moving the live save to `.bak` FIRST — step (2) — is what makes step (3)'s destination guaranteed-absent, and is an ordering requirement, not merely a backup step]; on any rename error, push_error and return false without touching the original. In load_game, when the primary file fails to parse (the null/typeof check at lines 322-326), attempt save_path + ".bak" before returning failure, and set error_message to note the backup was used so main.gd can toast it. Add a test in scripts/tests/ that writes garbage to save_path with a valid .bak present and asserts load_game recovers.

<details><summary>Verification notes</summary>

- Confirmed. save_system.gd:296-301 opens save_path with FileAccess.WRITE (truncate-on-open), writes the whole JSON in one store_string, no temp/rename/backup. Project-wide grep finds zero atomic-write or .bak logic; PROJECT_LOG.md:208/214 explicitly lists backup-before-migration as deferred. load_game:314-326 has no fallback — a partial/empty file fails JSON.parse_string and returns failure, and main.gd:230-245's hotfix then regenerates a fresh world, with comments (main.gd:243, save_system.gd:342) confirming the old save is overwritten on next F5. Single slot (line 122) means an interrupted write destroys all progress. Only nit: failure isn't fully "silent" (push_error + toast fire), but the loss is unrecoverable as claimed.

</details>

**CLOSED 2026-08-23 at `b04c1f6`.** The three-step write above shipped as prescribed
— `.tmp`, live → `.bak`, `.tmp` → live, all through `DirAccess.rename_absolute` on
globalized paths. Coverage is `scripts/tests/test_save_atomicity.gd`, six sub-cases
asserting on **loaded field values** (world_seed / player position / flour count, all
three different between the two states) rather than on `save_game`'s return.
`SAVE_VERSION` did not move; `test_save_migration.gd` and
`test_save_load_roundtrip.gd` pass unmodified.

**Two departures from the fix text. Do not "restore" either one.**

1. **The backup notice is `LoadResult.used_backup`, not a note in `error_message`.**
   The fix text says to "set error_message to note the backup was used so main.gd
   can toast it." That is unimplementable under this API's own convention
   (`load_result.gd:11-15`, `save_system.gd`'s header on `load_game`): recovering
   from `.bak` is `success == true`, and a non-empty `error_message` on a result is
   defined to mean the load *failed*. Writing the notice there would have made every
   caller that branches on `error_message != ""` treat a successful recovery as a
   failure — including `main.gd`'s F9 path, which toasts `error_message` verbatim.
   The notice is its own boolean field, meaningful only on success, toasted at both
   `main.gd` load sites. Sub-case 5 exists to hold this line: a corrupt save with no
   backup must report a non-empty `error_message` **and** `used_backup == false`.
2. **`save_exists()` now counts the `.bak` sidecar**, which the fix text does not
   mention. Without it the fix half-works: a crash between the two renames leaves
   `save_path` absent, `main.gd:336` gates its entire load path on `save_exists()`,
   and the boot would skip straight to fresh-world generation over a backup
   `load_game` could have read — the same progress loss the finding is about,
   reached through the window the fix itself introduces. Mutating `save_exists`
   back to a `save_path`-only check reddens sub-case 3's `save_exists` assertion
   alone.

**Beyond the prescription, and load-bearing:** the live save is moved to `.bak`
*before* the `.tmp` is moved into place, and the retention comment at that line says
why it is an ordering requirement rather than merely a backup step.
`DirAccess.rename_absolute` deletes an existing destination before renaming
(`DirAccessWindows::rename`), so renaming `.tmp` straight over a live `save_path`
would have its own delete-then-rename window with nothing backed up — a smaller
version of the original defect. Mutating the ordering (skipping the `.bak` rename and
overwriting directly) leaves every other suite green and reddens sub-cases 3 and 4.

**The seam.** `save_game` carries `_interrupt_after_stage`, a test-only static that
aborts after a named stage's work has actually been performed, so the on-disk state
is what a kill at that instant would leave. It is gated on `_is_test_fixture_path`:
the static could survive a test's early return, and an ungated leak would make every
later save in the process return false — or, at the `backup_renamed` stage, leave no
save file at all. The gate cannot hide a vacuous test, because every sub-case asserts
the on-disk state an abort produces; making `_should_interrupt` always return false
reddens sub-cases 2, 3 and 4 on loaded field values.

**RED before the fix** was the property itself, not the seam: save state A, perform
the truncating partial write an interrupted old-style save leaves, assert `load_game`
still returns A. It failed with `load_game failed (error_message=Save file is corrupt
or unreadable.)` while the same file's "A saves and loads back as A" sub-case passed.
Mutation-tested six further ways: reverting `save_game` to the single truncating
write (seam still aborting mid-body) reddens sub-cases 2, 3 and 4 — 13 assertions,
re-measured 2026-08-23; sub-case 4 reddens because it reads the `.bak` sub-case 3 is
supposed to have left, and the mutation leaves none; removing the `.bak`
fallback from `load_game` reddens 3 and 4; moving `file.close()` to after both renames
reddens 17 suites, because on Windows the renames then fail outright; the
`save_exists` and inert-seam mutations are described above; and moving the
`tmp_written` seam to *before* the temp write reddens exactly the assertion that the
abort happens after real work.


### 13. F9 quick-load never refreshes vision or map dirty state — active vision and map texture stay stale until the player crosses a region boundary
**Where:** `scripts/main.gd:519` | **Category:** bug, found by save-integrity

load_game clears region_visibility and restores all explored regions as fog (state 1); active state is documented as 'recomputed from player position at load time'. The _ready load path does this recomputation (main.gd:253-254 calls update_vision), but the quick_load branch does not, and _process only calls update_vision when the player's region CHANGES (main.gd:340). Failure scenario: player quick-loads while standing in the same region as the loaded player position (the common case — F5 then F9 at the same spot): _player_last_region is unchanged, so no vision update runs; the 5×5 around the player remains fog instead of active, and regions explored during the current session but absent from the loaded save were erased from region_visibility without map_panel being marked dirty, so the M-map/minimap keep rendering the pre-load exploration state. The save's own documented load contract (save_system.gd:458-460: 'Active state will be set by main.gd's vision update after load completes') is not honored on this path.

**Evidence:**
```
main.gd:518-524: quick_load branch calls only `SaveSystem.load_game(...)` + `_apply_loaded_progression(...)` + toast; contrast _ready path main.gd:253-254: `_player_last_region = GridWorld.region_of_world_pos(player.global_position); grid_world.update_vision(_player_last_region)`.
```
**Fix:** In main.gd's quick_load success branch (after _apply_loaded_progression, ~line 521), add: `_player_last_region = GridWorld.region_of_world_pos(player.global_position); grid_world.update_vision(_player_last_region)` (mirroring main.gd:253-254). Then force a full map rebuild rather than a changed-regions-only dirty marking, because load_game erased region_visibility entries that no per-region diff will report: either add a `map_panel.mark_all_dirty()` that appends every region in the 16x16 grid to _dirty_regions, or reset the background build (`_initial_built = false; _build_index = 0` via a public `restart_build()` on map_panel) so tick_background_build re-renders the whole texture progressively, matching post-_ready behavior. Optionally extract the shared post-load refresh (recompute region + update_vision + map refresh) into one helper called from both _ready and the quick_load handler so the two load paths cannot drift again.

<details><summary>Verification notes</summary>

- Confirmed. main.gd:518-524 quick_load calls only load_game + _apply_loaded_progression + toast; save_system.gd:461-463 clears region_visibility and restores explored regions as fog with an explicit comment (458-460) that main.gd's post-load vision update will set active state. That update exists only on the _ready path (main.gd:253-254) and on region-cross in _process (main.gd:340-343), so F9 in the same region as the loaded position (the common F5-then-F9 case) leaves _player_last_region unchanged and no vision update runs. No compensating guard: map_panel.tick_background_build early-returns after initial build (map_panel.gd:126-128), toggle() only drains already-dirty regions (map_panel.gd:93-98), and nothing marks regions dirty on load — so the map texture (map_panel.gd:179 reads region_visibility only on region redraw) keeps pre-load state, including session-explored regions erased from region_visibility. Tests cover update_vision and roundtrip fog collapse but not the F9 path, so 33/33 passing does not refute it.

</details>

**CLOSED 2026-08-23 at `9508d3f`.** Both halves fixed, and the fix text's *optional*
last sentence — "optionally extract the shared post-load refresh … into one helper" —
was treated as the mandatory part, because the drift between the two load paths IS the
finding and leaving two copies invites it back. `main._refresh_after_load()` is called
from `_ready` and from the new `_quick_load()`. Of the two map-refresh shapes the fix
text offered, the **background-build reset** was chosen over `mark_all_dirty()`:
`_apply_dirty_regions` only runs while the map is OPEN, so the dirty-list route would
leave the minimap — which samples the same texture every frame — stale until an
M-press, and it drains all 256 regions in one ~26 ms frame after paying 32,640
comparisons to `mark_region_dirty`'s linear dedup. `MapPanel.rebuild_all()` instead
lets the existing 8-regions-per-frame build repaint over ~32 frames at the ~0.8 ms/frame
it already costs.

Coverage is `scripts/tests/test_quick_load_refresh.gd`, asserting **state values**:
`region_visibility` states for the vision half and pixels read back out of the map
panel's own image for the map half. It drives the real `_quick_load()` rather than the
shared helper, since a test calling the helper directly would have passed against the
bug. RED before the fix showed all 25 regions at state 1 and the stale region's pixel
still at `(0.1176, 0.2471, 0.1176)` — grass green × the 0.45 fog dimming. Removing
`update_vision` from the helper reddens sub-case 1; removing `rebuild_all` reddens only
sub-case 2; calling the helper from `_ready` alone reddens sub-case 1, which is what
proves F9 routes through it.

### 14. Processors without an output prefer_dir push outputs backward onto their feeder belts, jamming the input line
**Where:** `scripts/world/processor.gd:229` | **Category:** design-flaw, found by sim-core

In the no-preference push path, _try_push_outputs tries every adjacent belt on all 4 edges, including a feeder belt that faces the processor. Belt.try_insert does not check the belt's orientation. Mill (recipes.gd line 44), Briquetter, Yeast Culture, and Sugar Press all lack output prefer_dir. Concrete scenario: a Mill fed grain by a west belt, with its east output belt full (or not yet built). The mill inserts flour into the feeder belt's back slot; the flour rides toward the mill's front slot where nothing consumes it (the mill pulls only grain). Every time slot 0 frees, more flour is inserted, until the feeder belt is 100% flour — grain can no longer enter and the line is dead until the player hand-clears the belt. recipes.gd lines 213-218 explicitly names this exact failure mode ('pushing compost BACKWARD onto the input belt') and fixed it only for the Composter.

**Evidence:**
```
processor.gd lines 227-230: `for dir in 4: for cell in Buildings.edge_cells(...): if _try_push_belt_to_cell(b, world, item_type, cell): return`; recipes.gd line 44: `"outputs_solid": [[Items.Type.FLOUR, 1]]` (no prefer_dir); recipes.gd comment: 'a jammed downstream belt would cause Processor._try_push_outputs to fall through to other directions — including pushing compost BACKWARD onto the input belt'.
```
**Fix:** In Processor._try_push_belt_to_cell (processor.gd:260), refuse belts that face into the processor: after resolving `neighbor`, compute `var belt_dir: int = int(neighbor.state["dir"])` and return false if `cell + Belt.DIR_VECS[belt_dir]` is a cell occupied by building `b` (use the footprint/ownership lookup, e.g. world.building_at(cell + Belt.DIR_VECS[belt_dir]) == b, so multi-tile processors are covered). This is the systemic fix — it protects all current and future no-prefer_dir recipes and also the Composter's non-preferred edges if its prefer_dir push ever falls back. Optionally, additionally add prefer_dir entries to mill_grain_to_flour, briquetter_fuel, yeast_culture, and press_sugar for consistency with the rest of the registry, but the guard alone closes the defect.

<details><summary>Verification notes</summary>

- Confirmed. processor.gd:221-230 no-preference path pushes to belts on all 4 edges via _try_push_belt_to_cell (lines 260-269), which has no orientation guard; Belt.try_insert (belt.gd:96-101) blindly fills back slot 0. The _opposite guard exists only in Belt.post_tick (belt.gd:79-83) for belt-to-belt handoff, not for processor pushes. Mill (recipes.gd:44), Briquetter (:107), Yeast Culture (:118), and Sugar Press (:129) all lack output prefer_dir. The jam is reachable: mill's pull accepts only GRAIN (try_pull_matching filters by accept list, belt.gd:139), so flour inserted into the east-facing feeder belt is never removed — the belt's front-slot handoff is a no-op into non-belt buildings (belt.gd:88) — and repeated pushes saturate the feeder with flour, permanently blocking grain. recipes.gd:213-218 explicitly documents this exact backward-push failure and fixed it only for the Composter, corroborating the flaw was known and left open for the other four recipes.

</details>

### 15. Composter recipe auto-selection pins a starved recipe forever when a leftover input can't reach the required count
**Where:** `scripts/world/composter.gd:76` | **Category:** design-flaw, found by sim-core

_maybe_select_recipe picks the first in_buffer entry with count > 0 and returns, without checking whether that recipe's required input count (all composter crop recipes need 2) can be satisfied. Because the selected recipe then gates _try_pull_inputs to that one item type, other valid inputs are never pulled and the port-peek fallback is never reached. Concrete scenario: a belt delivers wheat one item at a time; the supply ends leaving 1 wheat in the buffer (odd leftovers are common since the recipe consumes 2 per batch); the player switches the farm to sugar beets and the belt fills with beets. Every IDLE tick re-picks composter_low_wheat from the 1-wheat entry, the machine pulls nothing, and it stalls permanently despite a full belt of processable beets touching it.

**Evidence:**
```
Lines 74-78: `for entry in b.state.get("in_buffer", []): ... if int(entry[1]) > 0 and _INPUT_TO_RECIPE.has(item_type): b.state["recipe_id"] = _INPUT_TO_RECIPE[item_type]; return` — no check against the recipe's `[[Items.Type.WHEAT, 2]]` requirement (recipes.gd line 222).
```
**Fix:** In Composter._maybe_select_recipe (scripts/world/composter.gd:74-78), before pinning a buffered recipe, verify it can actually start: look up the candidate recipe via Recipes.get_recipe(_INPUT_TO_RECIPE[item_type]) and only pin if Processor._has_all_inputs(b, recipe) passes; otherwise continue to the next buffer entry and then fall through to port peek, so a runnable recipe wins over a starved one. Alternatively (simpler and preserving FIFO intent): also allow pinning when an adjacent belt carries more of that item (peek), but the _has_all_inputs gate is the minimal correct fix. Applying the same guard to Smelter._maybe_select_recipe is optional future-proofing — all current smelt recipes need only 1 input so it cannot exhibit this stall today. Add a regression test: buffer [[WHEAT,1]], belt full of SUGAR_BEET adjacent, tick N times, assert recipe_id becomes composter_mid_beet and COMPOST_MID is produced.

<details><summary>Verification notes</summary>

- Confirmed. composter.gd:74-78 pins the recipe from the first in_buffer entry with count>0 and returns before port peek, with no runnability check. processor.gd:96-128 builds pull accept-lists solely from the pinned recipe's inputs_solid, and belt.gd:139 rejects non-matching items, so beets are never pulled while composter_low_wheat is pinned. recipes.gd:222 requires 2 wheat; _has_all_inputs (processor.gd:144-150) fails with 1, _buffer_remove (287-295) never clears a nonzero leftover entry, and composter.gd:61 re-pins every IDLE tick — grep shows no other code resets recipe_id. Scenario (odd leftover after crop switch) is reachable and produces a permanent stall recoverable only by demolish/rebuild. No test in scripts/tests covers a starved leftover (test_fertilizer_chain.gd manually resets buffers between cases). One correction: the smelter half of the claim's fix is not load-bearing — all smelt recipes (recipes.gd:186,197) need only 1 input, so count>0 implies runnable there; the defect is composter-specific today.

</details>

### 16. Placement hover preview blocked-check contradicts can_place_building in both directions
**Where:** `scripts/world/grid_world.gd:1519` | **Category:** bug, found by sim-core

The hover preview marks a cell blocked if `tiles.has(cell)` — i.e., if the tile merely exists in the sparse dict. But most buildings REQUIRE an overlay tile (Mill/Belt/Smelter etc. need STONE/PATH/SOIL_TILLED), and every overlay tile has a tiles entry, so all legal placements on prepared ground preview red 'blocked' while the click succeeds. Conversely, a bare default-grass tile has no tiles entry, so holding a Mill (which cannot be placed on grass) over grass previews white 'valid' while the click fails. The preview is wrong on essentially every placement, and it ignores type-specific rules (Pump water adjacency, MiningDrill ore coverage) that can_place_building enforces.

**Evidence:**
```
Lines 1516-1521: `if hover_building_type >= 0: for dx in fp_size.x: for dy in fp_size.y: ... if tiles.has(cell) or has_building_at(cell): blocked = true` — versus can_place_building line 396: `if not (overlay_at(cell) in allowed_overlays)`.
```
**Fix:** In grid_world.gd _draw (around line 1514-1523), replace the ad-hoc loop with a delegation to the real rule, preserving last_building_place_error since _draw runs every frame: `var blocked: bool = false; if hover_building_type >= 0: var saved_err: String = last_building_place_error; blocked = not can_place_building(hover_building_type, rect_anchor); last_building_place_error = saved_err`. This keeps preview and placement permanently in sync (including overlay requirements, Pump water adjacency, and MiningDrill ore coverage) while leaving the error message readers (main.gd:681, console.gd:620) unaffected. Optionally add a test that asserts preview-blocked state equals can_place_building for a building on stone overlay and on bare grass.

<details><summary>Verification notes</summary>

- Confirmed. grid_world.gd:1519 marks the hover preview blocked on `tiles.has(cell)`, but set_overlay (325-328) stores a tiles entry for every STONE/PATH/SOIL_TILLED overlay, and most buildings' requires_overlay (buildings.gd:89-409) demand exactly those overlays — so every legal placement on prepared ground previews red while the click succeeds via can_place_building:396. Conversely bare grass has no tiles entry (overlay_at:238-241 defaults NONE), so overlay-requiring buildings preview valid over grass while placement fails. Preview also omits Pump (403) and MiningDrill (406-410) rules. Reachable: main.gd:428 sets hover_building_type from the hotbar; no other guard corrects the preview, and no test covers it (33/33 pass because tests only exercise place_building).

</details>

### 17. Pass-1 belt mutations make item timing depend on building insertion order (violates the two-pass contract)
**Where:** `scripts/world/processor.gd:81` | **Category:** convention-violation, found by sim-core

CONVENTIONS.md (Tick determinism) says 'Two-pass tick (Belt) lives in Buildings.tick_one / post_tick_one. Don't add hidden cross-building reads inside Pass 1', and belt.gd's header requires both passes to 'read a stable current state'. Processor.tick (also Smelter, Chest.tick, Inserter.tick, MiningDrill.tick) runs inside Pass 1 and both pulls from and pushes onto adjacent belts. Concrete consequence: a Mill that iterates before its output belt inserts flour into slot 0, and the belt's own Pass-1 shift (later the same tick) advances it to slot 1 — the item moves two slots in one tick. If the belt was placed before the mill, the item stays at slot 0 that tick. Identical layouts therefore have different throughput/timing depending on build order, and removing + re-placing a single belt (which moves it to the end of the insertion-ordered dict) changes simulation behavior of an otherwise identical world. It stays deterministic per-save, but the stable-state guarantee the two-pass design documents is not actually held.

**Evidence:**
```
processor.gd lines 55 and 81: `_try_pull_inputs(b, world, recipe)` / `_try_push_outputs(b, world, recipe)` called from Processor.tick, which grid_world.gd lines 572-573 runs in the first pass (`for anchor in buildings: Buildings.tick_one(...)`); belt.gd lines 14-15: 'Both passes must read a stable "current state" — that's what the two passes guarantee.'
```
**Fix:** Two acceptable resolutions: (a) Move machine↔belt exchanges out of Pass 1 — dispatch Processor/Smelter/Chest/Inserter/MiningDrill belt pulls/pushes from Buildings.post_tick_one so every Belt.tick shift completes before any machine touches belt slots (machine internal state machines can stay in Pass 1); note Pass-2 machine-vs-belt-handoff ordering still needs a defined rule. Or (b) accept current semantics explicitly: fix the false comment at grid_world.gd:569-571 ("pass 1 mutates self only"), amend CONVENTIONS.md:142 to state machine-belt exchanges intentionally run in Pass 1 with insertion-order timing, and add a regression test placing mill-then-belt and belt-then-mill asserting the exact per-order slot timing so future refactors can't silently change save behavior. Option (b) is the low-risk choice given 33/33 tests pin current behavior indirectly.

<details><summary>Verification notes</summary>

- Confirmed. CONVENTIONS.md:142 forbids cross-building reads in Pass 1; grid_world.gd:569-575 comments claim "pass 1 mutates self only" yet buildings.gd:798-832 dispatches Processor.tick/Smelter.tick/Chest.tick/Inserter.tick/MiningDrill.tick in tick_one (Pass 1), and processor.gd:55/81 via lines 138, 244, 266 both pulls from (Belt.try_pull_matching) and pushes onto (Belt.try_insert, belt.gd:96-101, no phase guard) adjacent belts. Belt's Pass-1 shift (belt.gd:54-61) runs in the same insertion-ordered dict loop, so machine-before-belt order lets an inserted item shift slot 0→1 the same advance tick while belt-before-machine leaves it at slot 0 — identical layouts differ in timing by build order, and re-placing a belt changes simulation. No guard exists; no test in scripts/tests/ pins this ordering.

</details>

### 18. STATE_NO_FUEL has no fallback to IDLE, so a smelter can wedge permanently with fuel available
**Where:** `scripts/world/smelter.gd:117` | **Category:** bug, found by machines

The state machine's only exit from STATE_NO_FUEL is straight to SMELTING when _has_all_inputs AND fuel both hold. _maybe_select_recipe is gated on state == STATE_IDLE, so while NO_FUEL the recipe stays pinned and _try_pull_inputs keeps accepting only the pinned ore. Scenario: smelter selects smelt_iron, runs out of fuel with iron ore buffered (NO_FUEL); player takes the iron ore out via the smelter panel and reroutes the line to copper, then adds fuel — _has_all_inputs(smelt_iron) is false forever, the recipe can never re-select to smelt_copper, and the smelter shows 'NO FUEL' indefinitely despite having fuel and copper available. Compare STATE_BLOCKED_OUTPUT, which correctly falls back to IDLE when the condition clears.

**Evidence:**
```
STATE_NO_FUEL:
	if Processor._has_all_inputs(b, recipe) and Processor._has_room_for_outputs(b, recipe):
		if Burner.consume_tick(b, FUEL_PER_INGOT):
			...
	# else: still stalled (no transition back to IDLE)
```
**Fix:** In smelter.gd's STATE_NO_FUEL branch, add a targeted fallback so the state machine can return to IDLE (where _maybe_select_recipe runs) when the inputs that justified NO_FUEL are gone:

	STATE_NO_FUEL:
		if Processor._has_all_inputs(b, recipe) and Processor._has_room_for_outputs(b, recipe):
			if Burner.consume_tick(b, FUEL_PER_INGOT):
				Processor._consume_inputs(b, recipe)
				b.state["progress"] = 1
				b.state["state"] = STATE_SMELTING
		elif not Processor._has_all_inputs(b, recipe):
			# Inputs were removed (e.g. via panel) — return to IDLE so
			# _maybe_select_recipe can re-select next tick.
			b.state["state"] = STATE_IDLE

Prefer this targeted `elif` over an unconditional `else: state = IDLE`: an unconditional fallback would also fire in the normal fuel-starved-with-inputs case and oscillate IDLE<->NO_FUEL every tick (flickering the status/tint), whereas the elif reverts only when the wedge condition (missing inputs) actually holds. Add a regression test in scripts/tests/test_smelter.gd: drive smelter to NO_FUEL, clear in_buffer (simulating panel take-out), add fuel, tick, assert state returns to IDLE and that feeding copper ore then re-selects smelt_copper.

<details><summary>Verification notes</summary>

- Confirmed. The quoted code is accurate: smelter.gd's STATE_NO_FUEL branch (lines 117-125) has exactly one exit — to SMELTING — requiring _has_all_inputs AND _has_room_for_outputs AND a successful fuel consume; unlike STATE_BLOCKED_OUTPUT (lines 126-128) there is no fallback to IDLE. _maybe_select_recipe is called only at line 85, gated on state == STATE_IDLE (line 84), so the recipe stays pinned while NO_FUEL. Processor._try_pull_inputs (processor.gd lines 96-128) builds its accept list solely from the pinned recipe's inputs_solid, so a smelt_iron-pinned smelter never pulls copper ore. The scenario's enabler is real: the smelter's slot_layout (buildings.gd lines 463-470) exposes an "input" slot bound to in_buffer, and building_panel.gd _take_from_slot (lines 358-370, kind "input") clears the entire in_buffer on a cursor-empty click — so the player can remove the buffered iron ore while NO_FUEL. After that, _has_all_inputs(smelt_iron) is false forever, fuel is never consumed, and no code path returns the state to IDLE; even manually dropping copper ore into the slot does not recover (still no IRON_ORE, and reselection never runs outside IDLE). Only recovery is re-feeding iron ore or demolish/rebuild, while the panel misleadingly reports "NO FUEL" with a full fuel buffer. test_smelter.gd (lines 129-145) covers NO_FUEL entry and fuel-arrival recovery with inputs intact, but not the inputs-removed case — consistent with 33/33 passing. No guard elsewhere writes smelter state or recipe_id (grep across scripts confirms writes only at smelter.gd 107/109/116/124/128, 153/164).

</details>

### 19. _drop_to_chest bypasses Chest.TOTAL_CAPACITY, letting inserters overfill chests without bound
**Where:** `scripts/world/inserter.gd:353` | **Category:** bug, found by machines

Every other producer (MiningDrill._try_push_to, Processor._try_push_to_cell, Harvester._try_feed_belt) inserts into chests via Chest.try_insert, which enforces free_capacity against TOTAL_CAPACITY (2400) and returns false when full. The inserter's private _drop_to_chest appends directly to the bag and unconditionally returns true, so an inserter feeding a full chest never enters BLOCKED_AT_DEST and the bag grows past 2400 indefinitely. Scenario: chest at 2400/2400 fed by an inserter — the fill bar clamps at 100% while the real count keeps climbing, breaking the aggregate-capacity invariant the ChestPanel, fill bar, and Chest.tick all assume; the intended backpressure (inserter stalls, upstream belt backs up) never happens. The in-code comment only waives PER-STACK caps, not the aggregate cap.

**Evidence:**
```
static func _drop_to_chest(chest: Building, item: int) -> bool:
	var bag: Array = chest.state.get("bag", [])
	...
	bag.append([item, 1])
	return true
```
**Fix:** In scripts/world/inserter.gd replace the entire body of _drop_to_chest (lines 341-354) with: `return Chest.try_insert(chest, item, 1)`. Chest.try_insert already handles top-up-or-append via _bag_add and returns false when free_capacity < 1, which makes _try_drop return false and the inserter correctly enter/stay in BLOCKED_AT_DEST until the chest has room. Optionally add a regression test: fill a chest to 2400 via Chest._bag_add, run an inserter drop cycle, assert Chest.total_items stays 2400 and the inserter state is STATE_BLOCKED_AT_DEST.

<details><summary>Verification notes</summary>

- Confirmed. inserter.gd:341-354 appends to the chest bag with no capacity check and always returns true; the chest branch of _try_drop (line 334-335) has no other gate, so the state machine (lines 167-178) can never enter BLOCKED_AT_DEST for a chest. Chest.try_insert (chest.gd:77-81) enforces TOTAL_CAPACITY=2400 and is used by processor.gd:242/255, harvester.gd:83, mining_drill.gd:252 — inserter is the sole writer bypassing it. Chest.make always initializes "bag", so the append mutates real state and overfill genuinely accumulates past 2400 while the fill bar (chest.gd:155) clamps at 100%. No test in scripts/tests/ covers inserter-into-full-chest, so 33/33 passing is consistent with the bug.

</details>

### 20. Patch rims generate zero-richness 'ghost' ore tiles that render at full alpha and yield one free item when mined
**Where:** `scripts/world/world_generator.gd:361` | **Category:** bug, found by soil-worldgen

In _place_patch, tiles pass the boundary test using effective_radius (up to 1.4x base via perturbation) but intra_intensity uses base_radius with clamp to [0,1], so every rim tile with dist in (base_radius, effective_radius] gets intensity 0 and `richness = int(round(0 * ...)) = 0` (tiles just inside base_radius can also round to 0 near origin). The tile is still written with a resource_node and `resource_state[pos] = {"richness": 0, "original_richness": 0}`. Two downstream effects: (1) _depletion_alpha_at (grid_world.gd:1332) hits the `if original <= 0: return FULL_DEPOSIT_ALPHA` defensive branch, so an empty deposit renders at FULL opacity instead of the depleted fade — the tile looks richest on the whole patch rim; (2) manual harvest (main.gd:831-833) does `player_inventory.add(item_type, amount)` BEFORE `deplete_resource(pos, 1)`, which extracts 0 and immediately reverts the tile — the player receives 1 ore conjured from nothing per ghost tile. MiningDrill is unaffected (it filters richness_at > 0).

**Evidence:**
```
var intra_intensity: float = clamp(1.0 - pow(dist / base_radius, 2.0), 0.0, 1.0)
...
var richness: int = int(round(intra_intensity * float(BASE_RICHNESS[type]) * distance_multiplier))
world.tiles[pos] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE, type)
```
**Fix:** 1) In world_generator.gd _place_patch, after computing richness at line 361, add `if richness <= 0: continue` before the tile/resource_state writes (lines 362-368), and bump the worldgen VERSION constant since generated world layout changes deterministically. 2) Independently harden main.gd _try_harvest_tick: for the ore branch, call `var extracted: int = grid_world.deplete_resource(pos, 1)` first and only then `player_inventory.add(item_type, extracted)` when extracted > 0 (the has_room_for check at line 826 already runs before this, so reordering is safe and makes inventory gains match actual extraction).

<details><summary>Verification notes</summary>

- Confirmed end-to-end. world_generator.gd:354 gates on effective_radius (up to 1.4x base via SHAPE_PERTURB_AMOUNT=0.4, line 56) while line 357 computes intensity against base_radius with clamp(...,0.0,1.0), so rim tiles with dist in (base_radius, effective_radius] get richness=0 at line 361 yet are still written with a resource_node (line 362) and resource_state {richness:0, original_richness:0} (line 368) — no richness>0 guard exists in _place_patch. grid_world.gd:1332-1333 returns FULL_DEPOSIT_ALPHA when original<=0, so ghost tiles render at full opacity. main.gd:831-833 adds the item before deplete_resource; the target gate (main.gd:802-803) checks only resource_node, and deplete_resource (grid_world.gd:852-882) does not early-return for the ghost tile (resource_state entry exists), extracts 0, erases the tile, and returns 0 after the item was already granted — 1 free ore per ghost tile. MiningDrill confirmed unaffected (mining_drill.gd:163,189,298 filter richness_at>0). No test covers rim richness.

</details>

### 21. Load-failure fallthrough treats 'save from newer version' and worldgen mismatch as corrupt: fresh world silently overwrites a fully recoverable save on next F5
**Where:** `scripts/main.gd:244` | **Category:** bug, found by main-console

In _ready, every load failure falls through to _generate_fresh_world(), regardless of failure kind. SaveSystem.load_game returns success=false for three very different cases: (a) genuinely corrupt JSON, (b) save version > SAVE_VERSION (save is valid, just written by a newer binary — the alert explicitly tells the player 'Update the game to load this save'), and (c) worldgen version mismatch (save data is valid for a build with the old worldgen). CONVENTIONS.md line 126 specifies forward incompatibility 'hard-fails with a clear "update the game" message', but main.gd converts it into a playable fresh world with a new random seed; the moment the player reflexively presses F5, save_game overwrites the newer-version save at the same path and the data the dialog told them to preserve is destroyed. No .bak copy is made in any failure path, so even the corrupt-JSON case loses a potentially hand-recoverable file.

**Evidence:**
```
main.gd:243-245: 'push_warning("Save load failed (%s) — generating fresh world." % result.error_message); var fail_msg: String = "Save incompatible — fresh world (seed %d)" % _generate_fresh_world()' — while save_system.gd:352 alerts 'Update the game to load this save, or delete to start fresh' for the version > SAVE_VERSION case, then returns the same success=false LoadResult main treats as corrupt.
```
**Fix:** Scope the fix to the forward-incompat (version > SAVE_VERSION) path rather than all failures. Minimal: in save_system.gd's v>SAVE_VERSION branch, before returning, copy the save aside (DirAccess.copy_absolute(save_path, save_path + '.bak')) and append 'Playing on will overwrite this file on next F5; a backup was kept at save.json.bak' to the alert, matching the explicit overwrite warning the migration-failure alert already has (line 342). Optionally add a 'kind' field (CORRUPT/FORWARD_INCOMPAT/WORLDGEN_MISMATCH/MIGRATION_FAIL) to LoadResult so main.gd can vary the toast, but do not block fresh-world generation for worldgen mismatch or migration failure — CONVENTIONS.md:125 and :136 explicitly prescribe that fallthrough. A .corrupt copy for the unparseable-JSON case is a nice-to-have, not a convention requirement.

<details><summary>Verification notes</summary>

- Quoted code confirmed: main.gd:235-245 treats all load failures identically (fresh world), save_system.gd:346-356 returns the same success=false for version>SAVE_VERSION after an alert promising 'Update the game to load this save', and main.gd:512-514 + save_system.gd:296-302 show F5 overwrites save_path unconditionally with no .bak or guard. However, two of the three cited cases are explicitly convention-sanctioned: CONVENTIONS.md:136 blesses fresh-world regeneration for worldgen mismatch, and CONVENTIONS.md:125 blesses it for migration failure (whose alert at save_system.gd:342 even warns about F5 overwrite). The real defect is narrower than claimed: only the forward-incompat case violates CONVENTIONS.md:126's intent — the alert tells the player the save is recoverable after updating, but the game silently arms one-keypress destruction of that valid save with no overwrite warning. Reachable but requires binary downgrade/newer synced save plus an explicit F5 after a modal alert; no autosave exists.
- Reproduced for the forward-incompat case: save v19 vs SAVE_VERSION=18 → save_system.gd:346-356 alerts "Update the game to load this save", returns success=false; main.gd:236-245 then generates a playable fresh world, and F5 (main.gd:512-514 → save_system.gd:296-302) opens the same save_path with FileAccess.WRITE and unconditionally destroys the newer, fully-recoverable save the dialog told the player to keep — no .bak in any path. However, the claim overreaches on the other two cases: CONVENTIONS.md:125 explicitly sanctions fresh-world fallthrough for migration failure ("save data is genuinely lost in this case", and the alert at save_system.gd:342 even warns "overwritten on next F5"), and CONVENTIONS.md:136 explicitly endorses the fallthrough for worldgen mismatch. Only the version>SAVE_VERSION path is a genuine defect: its alert promises recoverability but carries no overwrite warning and the code arms silent destruction.

</details>

**CLOSED 2026-08-23 at `1198233`, scoped to the forward-incompat case only** — see
the scoping note in the status block above for the `CONVENTIONS.md` quotes that
narrow it and for the traced `.bak` interaction. Three corrections to the fix text
as written, all of them consequences of `b04c1f6` post-dating this audit:

1. **"copy the save aside … to `save_path + '.bak'`" would now destroy it.** `.bak` is
   the atomic write's rotation slot: `save_game` moves the live save there on every
   F5, so a copy left at that path survives exactly one more save. The copy goes to
   a `.incompatible` sidecar instead, which `save_game` never writes.
2. **"arms one-keypress destruction" is no longer true — it is two.** The first F5
   *moves* the newer save to `.bak` rather than truncating it; the second rotates the
   fresh world on top. The verification notes' reproduction predates the atomic write.
3. **No `LoadResult` `kind` field was added**, though the fix text offers one and
   `used_backup` / `skipped_entries` set the precedent. The alert is written where the
   kind is statically known and is modal, so the player has read it before `main.gd`
   toasts; a field would only let `main.gd` restate it more weakly.

The alert now names the path the data was actually read from — it previously always
named `save_path`, which is wrong when the `.bak` fallback supplied the data — and
carries the F5 overwrite warning the fix text asked for, worded to match the
migration-failure alert that already had one. Coverage is
`scripts/tests/test_forward_incompat_save.gd`, 7 sub-cases, asserting the preserved
copy's **parsed contents and bytes**, not its existence. `SAVE_VERSION` did not move.

### 22. One Esc press performs two actions: modal Esc handlers in _input race main's polled Esc priority chain in the same frame
**Where:** `scripts/ui/map_panel.gd:243` | **Category:** bug, found by main-console

MapPanel._input and DevConsole._input close their modal on KEY_ESCAPE during the input phase and call set_input_as_handled(). But set_input_as_handled only stops event propagation — it does not affect Input.is_action_just_pressed polling, which main.gd's Esc priority chain (main.gd:379-390) uses later in the same frame's _process. Because the modal is already closed by the time the chain runs, the chain's map/console step is skipped and it falls through to the NEXT step. Concrete scenario: player has a hotbar selection, opens the map with M, presses Esc once → MapPanel._input closes the map, then main's chain sees map_panel.is_open()==false and executes step 5, clearing the hotbar selection and showing the 'Hotbar cleared' toast. Similarly, Esc with the console open above the map closes both the console and the map in one press. This violates the documented one-action-per-press Esc chain design.

**Evidence:**
```
map_panel.gd:243-245: 'if _is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: toggle(); get_viewport().set_input_as_handled()' — while main.gd:379 polls 'if Input.is_action_just_pressed("close_info_panel"):' the same frame (polling ignores the handled flag). Same pattern in console.gd:180-182.
```
**Fix:** 1) Delete the KEY_ESCAPE branch in map_panel.gd _input (lines 241-245 become unnecessary — main's chain step 3 at main.gd:384-385 already closes the map on Esc, and the _draw hint text stays accurate). 2) For the console, which must keep intercepting Esc in _input (it owns keyboard focus): in console.gd's KEY_ESCAPE branch record the frame, e.g. set a public `var consumed_esc_frame: int = -1` to Engine.get_process_frames() inside _close() (or just in the Esc branch). In main.gd, guard the chain: `if Input.is_action_just_pressed("close_info_panel") and (dev_console == null or dev_console.consumed_esc_frame != Engine.get_process_frames()):`. This preserves one-action-per-press for both modals without changing input routing.

<details><summary>Verification notes</summary>

- Confirmed. map_panel.gd:243-245 and console.gd:180-182 close their modal on raw KEY_ESCAPE in _input and call set_input_as_handled(), which only stops event propagation — it does not clear Input action state. project.godot maps close_info_panel to keycode 4194305 (Escape), and main.gd:379-390 polls Input.is_action_just_pressed in _process, which runs after _input in the same frame and ignores the handled flag. No guard exists in main.gd (no is_input_handled check, no frame-stamp flag). Therefore one Esc with the map open closes the map in the input phase, then the chain at main.gd:384 sees is_open()==false and falls through to step 4/5 (clearing info-panel target or hotbar selection + toast). The console gate at main.gd:362 similarly fails after console._input already closed it, so one Esc closes console plus executes a chain step. Violates the documented one-action-per-press chain (main.gd:372-378).

</details>

### 23. Console 'place' auto-overlay only paves the anchor cell (2x2 buildings can never auto-place) and the failed-restore path leaves a stray permanent STONE overlay
**Where:** `scripts/ui/console.gd:634` | **Category:** bug, found by main-console

Two defects in _cmd_place's overlay-bypass retry. (1) On failure it calls grid_world.set_overlay(pos, picked_overlay) for the anchor cell only, then retries; for 2x2 overlay-requiring buildings (Mixer, Oven, Proofer, Packager) the retry still fails because the other three footprint cells lack the overlay — so 'place mixer 5 5' on grass always fails despite the help text 'Bypasses overlay check'. (2) The rollback 'grid_world.set_overlay(pos, pre_overlay)' silently fails whenever pre_overlay is Overlay.NONE, because Terrain.can_place_overlay returns false for NONE ('use clear path, not paint'). Concrete repro: 'place pump 10 10' on plain grass far from water → first attempt fails (needs Stone), STONE is auto-painted and the retry fails on 'Pump must be adjacent to water', the restore no-ops, and the tile keeps a stray STONE overlay that is recorded in tile_modifications and persists into the save even though nothing was placed.

**Evidence:**
```
console.gd:634-638: 'grid_world.set_overlay(pos, picked_overlay)' (anchor only, no footprint loop) then '# Restore overlay; placement still fails for some other reason.\n\t\t\tgrid_world.set_overlay(pos, pre_overlay)' — but terrain.gd:85-86: 'if overlay == Overlay.NONE: return false  # use clear path, not paint'.
```
**Fix:** In _cmd_place (console.gd:633-638): before the retry, iterate the full footprint (var fp: Vector2i = Buildings.footprint_of(btype); for dx in fp.x: for dy in fp.y: var cell = pos + Vector2i(dx, dy)), recording each cell's prior overlay in a Dictionary and calling grid_world.set_overlay(cell, picked_overlay) only for cells whose current overlay is not already in requires_overlay. If any set_overlay call fails (e.g. resource node under a footprint cell), or the retried place_building fails, roll back every cell that was painted: use grid_world.clear_tile(cell) when the recorded prior overlay was Terrain.Overlay.NONE (clear_tile handles the NONE case and keeps tile_modifications consistent), else grid_world.set_overlay(cell, prior). This fixes both the 2x2 auto-place failure and the stray-STONE persistence in one change.

<details><summary>Verification notes</summary>

- Both defects confirmed. (1) console.gd:634 paints only the anchor cell, but grid_world.can_place_building (grid_world.gd:392-401) requires the overlay on every footprint cell; MIXER/PROOFER/OVEN/PACKAGER are 2x2 with requires_overlay [STONE, PATH] only (buildings.gd:205-206, 257-258, 278-279, 308-309), so the retry at console.gd:635 always fails on the 3 unpainted cells despite help text 'Bypasses overlay check' (console.gd:378). (2) The rollback at console.gd:638 calls set_overlay(pos, NONE) when pre_overlay was NONE, which terrain.gd:85-86 rejects ('use clear path, not paint'), so the restore silently no-ops; the earlier successful paint already wrote tile_modifications (grid_world.gd:330), the save-persisted store (grid_world.gd:26-36). The pump repro is reachable: PUMP requires [STONE, PATH] (buildings.gd:197-198) and the water-adjacency check runs after the overlay check (grid_world.gd:403-404), so 'place pump 10 10' on grass far from water leaves a stray persistent STONE overlay. No guard elsewhere; no test covers the console retry branch.

</details>

### 24. deplete_area and tile accept unbounded radius: a single typo freezes the game for minutes to hours
**Where:** `scripts/ui/console.gd:555` | **Category:** bug, found by main-console

Both commands validate radius >= 0 but impose no upper bound, and both run O((2r+1)^2) loops synchronously on the main thread. 'deplete_area 0 0 999999' iterates ~4x10^12 cells (the _in_world_bounds continue still executes per cell) — a hard multi-hour freeze forcing a process kill and losing all unsaved progress. 'tile 0 0 99999' additionally builds a (2r+1)x(2r+1) text grid, appending ~4 chars per cell into a String — tens of gigabytes, ending in an OOM crash. The world is only 512x512 tiles ([WORLD_MIN, WORLD_MAX)), so any radius beyond ~512 is pure wasted work; the dev console exists precisely for fast iteration, and it should not be able to hang the session on a fat-fingered argument.

**Evidence:**
```
console.gd:551: 'return "Radius must be >= 0 (got %d)." % radius' is the only bound; console.gd:555-561 then runs 'for dx in range(-radius, radius + 1): for dy in range(-radius, radius + 1): ... if not _in_world_bounds(pos): continue'. Same unbounded pattern in _cmd_tile / _format_tile_grid (console.gd:743-744, 789-810).
```
**Fix:** For deplete_area, instead of an arbitrary cap, intersect the loop bounds with the world before iterating: for x in range(max(center.x - radius, WorldGenerator.WORLD_MIN), min(center.x + radius + 1, WorldGenerator.WORLD_MAX)) and likewise for y. This bounds the work to at most 512x512 (~262k) iterations for any radius, removes the per-cell _in_world_bounds continue, and requires no magic cap or new error message. For tile, a cap is genuinely needed because the cost is output size, not just iteration: after the radius < 0 check at console.gd:743, add 'if radius > 16: return "Radius must be <= 16 for grid mode (got %d)." % radius' before calling _format_tile_grid.

<details><summary>Verification notes</summary>

- Confirmed. console.gd:550-551 is the only radius validation for deplete_area (rejects only negatives); lines 555-561 then run the full nested range(-radius, radius+1) loops synchronously, with _in_world_bounds (line 558, defined at 450-452 against WorldGenerator.WORLD_MIN/MAX = -256/256, world_generator.gd:34-35) only issuing a per-cell continue — every cell is still visited. _parse_int (console.gd:415-418) is a bare is_valid_int/int() with no clamping, and both commands are registered and reachable in the command table (lines 350, 395). _cmd_tile has the identical negative-only check at 743-744 and _format_tile_grid (782-812) appends ~4 chars per cell into a String, so a large radius both freezes and balloons memory. No guard exists anywhere on either path; the O((2r+1)^2) main-thread freeze on a fat-fingered radius is real. Worse than the claim: GDScript range() materializes an Array, so the inner range(-radius, radius+1) allocates a multi-million-element array on every outer iteration for huge radii, adding allocation churn on top of the iteration cost.

</details>

### 25. Nine processor recipes (bread + cloth chains) are never executed by any test
**Where:** `scripts/tests/test_runner.gd:14` | **Category:** test-gap, found by test-quality

Recipes proofer_rise, oven_bread, packager_loaves, briquetter_fuel, yeast_culture, press_sugar, retter_fiber, loom_cloth, and tailor_bag (recipes.gd lines 63-164) have zero tick-level coverage. The only tests touching these machines are UI slot-layout assertions (test_building_ui_2/3 check 'accepts' lists) and test_cloth_prefer_dir, which explicitly pre-loads out_buffer to 'skip the water+flax+recipe-cycle setup'. The Session C bread chain past the mixer (proofer -> oven -> packager) and the entire cloth production line are untested, as is the retter/yeast-culture fluid gating (only the mixer's is verified). Recipe data is exactly the kind of dispatch-table content the project's checklist culture depends on tests to lock.

**Evidence:**
```
test_cloth_prefer_dir.gd:27-29: "We pre-load out_buffer directly to skip the water+flax+recipe-cycle setup. The PUSH path is what we're testing; pull and recipe correctness are covered by other tests (mixer_dough, thresher_*)." — but those tests cover only mixer/thresher recipes, not the 9 listed. No test file emits ticks against an OVEN, PROOFER, PACKAGER, BRIQUETTER, SUGAR_PRESS, LOOM, TAILOR, RETTER, or YEAST_CULTURE.
```
**Fix:** Add scripts/tests/test_processor_recipes.gd following test_mixer_dough.gd's closed-system pattern: for each of the 9 recipe ids, place the building on stone, pre-load in_buffer with N cycles of exact inputs (bypasses prefer_dir pull, which is fine — pull is covered by thresher/cloth prefer_dir tests), set state=Processor.IDLE/progress=0, emit N*time_ticks+margin ticks, assert out_buffer holds exactly N outputs and in_buffer is empty. For the two fluid-gated recipes (retter_fiber, yeast_culture) reuse test_mixer_dough's water-tile+PUMP+PIPE layout along one edge, and add a Phase 2 negative case: remove the pump, reload inputs, tick, assert state stays IDLE and out_buffer stays empty. Multi-count recipes (packager_loaves 4:1, loom_cloth 3:1, tailor_bag 4:1, briquetter_fuel 3:1) get exact-ratio assertions; oven_bread pre-loads both RISEN_DOUGH and FUEL_BRIQUETTE and asserts both are consumed per cycle. Register the suite in test_runner.gd.

<details><summary>Verification notes</summary>

- Confirmed. The 9 recipes exist in scripts/world/recipes.gd (proofer_rise L63, oven_bread L76, packager_loaves L90, briquetter_fuel L102, yeast_culture L113, press_sugar L124, retter_fiber L138, loom_cloth L152, tailor_bag L164-175; claimed range 63-164 is off by one entry's tail but substantively right). Exhaustive grep of scripts/tests/ shows only three call sites placing any of the 9 building types: test_building_ui_2.gd:151 (OVEN — pure drag-drop/slot UI assertions; its only TickSystem references are cleanup disconnect at L243-244, zero ticks emitted), test_building_ui_3.gd:87 (RETTER — same UI-only pattern), and test_cloth_prefer_dir.gd:58/127 (RETTER — ticks 1500x but pre-loads out_buffer at L84/L151 and empties in_buffer, so the recipe cycle never runs; the quoted L27-29 comment exists verbatim). test_mixer_dough.gd covers fluid gating for MIXER only (Phase 2, pump removal); test_fluid_network.gd places only PUMP/PIPE — so retter_fiber and yeast_culture water gating is untested. test_bag_cap.gd is inventory-bag mechanics, not the TAILOR. No test anywhere executes IDLE→RUNNING→output for these 9 recipes. Severity adjusted high→medium: it is a genuine gap spanning two production chains plus two fluid-gated machines, but CONVENTIONS.md mandates tests only for save migrations (L109), no defect is demonstrated, and the buffer/state machinery these recipes run on (Processor) IS tick-covered via mixer/thresher/smelter/composter tests — the untested surface is primarily the data rows (counts, prefer_dirs, fluid flags), not the engine.
- Confirmed by exhaustive grep of all 33 tests in test_runner.gd (lines 14-48): no test ever ticks an OVEN, PROOFER, PACKAGER, BRIQUETTER, SUGAR_PRESS, LOOM, TAILOR, RETTER, or YEAST_CULTURE through a recipe cycle. test_building_ui_2/3/4 only assert slot layouts and panel drag-drop (the OVEN placed at ui_2:151 is never ticked); test_cloth_prefer_dir.gd:84-87/151-154 explicitly empties in_buffer and pre-loads out_buffer to bypass the recipe. Buildings.slot_layout_for (buildings.gd:662-663) reads hardcoded slot_layout, not Recipes.DATA, so UI accepts-list checks do not lock recipe data. Reproduction: deleting yeast_culture.inputs_fluid (recipes.gd:117) or changing oven_bread's RISEN_DOUGH count (recipes.gd:82) leaves the suite 33/33 — no assertion reads those fields at execution time; fluid gating is asserted only for the mixer (test_mixer_dough.gd:67-78). Severity lowered from high to medium because all 9 machines are thin wrappers dispatching to the shared Processor.tick (buildings.gd:809-812), whose mechanisms (multi-cycle runs, multi-input consumption, fluid gating, prefer_dir, multi-output) are already locked by mixer/thresher/mill/smelter/composter tests — the unguarded surface is recipe data and default-recipe wiring, not the engine.

</details>

### 26. Belt two-pass tick semantics have no dedicated test
**Where:** `scripts/tests/test_runner.gd:14` | **Category:** test-gap, found by test-quality

CONVENTIONS.md line 142 makes the two-pass belt tick (Belt.tick pass 1 intra-belt shift, Belt.post_tick pass 2 handoff via Buildings.tick_one/post_tick_one) a named determinism law: 'Don't add hidden cross-building reads inside Pass 1.' Yet no suite in TESTS targets belts directly. Belts appear only as incidental transport in chain tests whose thresholds are lower bounds (>=7 flour, >=9 grain) with generous tick budgets. A regression that makes items advance two slots per advance-tick, double-move across a belt-to-belt handoff in one tick, or leak items between passes would make transport faster, satisfying every existing >= threshold, and the exact-count closed-system tests (mixer, thresher) involve no belts at all.

**Evidence:**
```
test_runner.gd TESTS array (lines 15-47) contains no belt suite; CONVENTIONS.md:142: "Two-pass tick (Belt) lives in `Buildings.tick_one` / `post_tick_one`. Don't add hidden cross-building reads inside Pass 1."; belt.gd:52-64 implements the two passes.
```
**Fix:** Add scripts/tests/test_belt.gd and register it in test_runner.gd TESTS. Cases: (1) Single-item advance: place 3 belts in a line (all DIR_E), insert one item via Belt.try_insert, then drive ticks one at a time (TickSystem.current_tick += 1; TickSystem.tick.emit(...)). Note belts only advance when current_tick % Belt.TICKS_PER_SLOT == 0 (belt.gd:49-50), so after each advance tick assert the item occupies exactly one expected slot index/belt (12 slots total path) and all other slots are -1 — this catches double-shift in pass 1 AND same-tick shift+handoff double-move at the belt-to-belt boundary (an item entering next_slots[0] in pass 2 must not move again that tick). (2) Jam/compression: 3-belt line with no consumer past the head (post_tick returns at belt.gd:73 when next tile is empty); keep inserting until full and assert items compress to occupy the head slots with total count conserved — never vanished, never duplicated. (3) Opposite-facing guard: two belts facing each other; assert no handoff ever occurs (belt.gd:82). (4) Conservation ring: 4 belts in a 2x2 square (E,S,W,N) with N items; run several hundred ticks and assert total occupied-slot count stays exactly N. Use exact equality assertions throughout — no >= thresholds.

<details><summary>Verification notes</summary>

- Confirmed. test_runner.gd:14-48 lists 33 suites, none belt-focused. CONVENTIONS.md:142 verbatim names the two-pass belt tick as a determinism law; implementation is scripts/world/belt.gd:54-88 (pass 1 tick, pass 2 post_tick) dispatched via buildings.gd:798/835 and grid_world.gd:573-575. Refutation failed: every belt-involving test uses only lower-bound thresholds (test_wheat_to_flour.gd:77-80 >=7; test_thresher_prefer_dir.gd:77-78 >=9; test_thresher_rotation.gd:127-132 >=9) plus type-purity checks, so a double-advance, same-tick double-handoff, or duplication regression passes all of them; the exact-count thresher test (test_thresher_multioutput.gd:28) pre-loads in_buffer and uses no belts; test_inserter.gd writes belt slots directly without ticking belt advancement. No per-tick slot-position assertion exists in scripts/tests/. Severity lowered to medium: genuine gap on a documented invariant, but no live defect — belt.gd is currently correct and the suite passes 33/33.
- Confirmed. test_runner.gd:14-48 lists 33 suites, none targets belts; grep shows no test references Belt.tick/post_tick/SLOTS_PER_TILE/TICKS_PER_SLOT. CONVENTIONS.md:142 names the two-pass belt tick as a determinism law, implemented in scripts/world/belt.gd (Pass 1 lines 54-61, Pass 2 lines 64-88). Traced a concrete missed regression: removing belt.gd:87 (slots[front_idx] = -1) duplicates the item at every belt-to-belt handoff, yet test_wheat_to_flour.gd:77 only asserts flour >= 7 (duplication increases flour, still passes), test_thresher_multioutput/test_mixer_dough read processor buffers with no belts, and test_inserter pulls via slot-scanning try_pull_matching so it is insensitive to belt speed/duplication. A 2-slots-per-advance-tick regression likewise passes all lower-bound thresholds. 33/33 would stay green under a broken determinism law. Severity lowered to medium: it is a coverage gap, not current wrong behavior — belt.gd is presently correct.

</details>

### 27. Bag-cap phases 2-3 assert on an in-test mirror, not main.gd's actual consume logic
**Where:** `scripts/tests/test_bag_cap.gd:108` | **Category:** test-gap, found by test-quality

The cap-of-5 lifecycle and the cap-before-no-bag failure-ordering assertions run entirely against the test's local _try_consume helper, a hand-copied mirror of main.gd's _confirm_bag_consume (main.gd:1248-1260), using test-local constants BAG_CAP=5 and SLOTS_PER_BAG=4 that duplicate main.gd:9-10. Only the Inventory.expand phase touches production code. If someone swaps the two precondition checks in _confirm_bag_consume, changes BAG_CAP to 10, or removes the bag-removal line, game behavior changes while every assertion in this suite still passes — the test verifies its own copy.

**Evidence:**
```
test_bag_cap.gd:103-107: "Mirrors the precondition + action ordering in main.gd's _confirm_bag_consume() ... **Cap-reached check fires BEFORE no-bag check**" — the ordering being 'locked in' exists only inside static func _try_consume in the test file.
```
**Fix:** Two-step, minimal-churn fix: (1) Kill constant drift now — in test_bag_cap.gd replace the local consts with `const MainScript := preload("res://scripts/main.gd")` and use `MainScript.BAG_CAP` / `MainScript.SLOTS_PER_BAG` (Godot 4 allows reading consts off a script resource without instantiating the Node2D). (2) Extract the decision logic — add a static, side-effect-free func on main.gd (or a small BagRules class), e.g. `static func bag_consume_verdict(bags_consumed: int, bag_count: int) -> String` returning "cap"/"no_bag"/"ok", have both _request_bag_consume (main.gd:1235-1240) and _confirm_bag_consume (main.gd:1250-1255) branch on it, and rewrite the test's _try_consume to call that static for the verdict, keeping only the remove+expand side effects locally. This makes phases 2-3 assert production ordering and cap value; the removal side effect (main.gd:1256) remains untested unless a headless scene test is added, which the file header already scopes out.

<details><summary>Verification notes</summary>

- Confirmed. test_bag_cap.gd:108-115 _try_consume is a hand-copied mirror of main.gd:1248-1257 _confirm_bag_consume, and test-local BAG_CAP/SLOTS_PER_BAG (test:20-21) duplicate main.gd:9-10. Project-wide grep shows no test calls _request_bag_consume/_confirm_bag_consume (only call sites: main.gd:535,537) and no test reads main.gd's constants; other bags_consumed hits (test_save_load_roundtrip.gd:121,227; test_building_ui.gd:251,276) only test persistence/fixtures, not the cap decision. Swapping the checks at main.gd:1250/1253, changing BAG_CAP, or deleting the remove at main.gd:1256 leaves all 33 tests green. Mitigation: the scope limitation is documented in the test header (lines 15-18), making this a deliberate tradeoff — but the header also claims to "lock in" cap and ordering (lines 5-13, 106-107), which it does not do for production code, so the gap is real.

</details>

### 28. BLOCKED_OUTPUT sub-suite never asserts the state value nor the promised recovery
**Where:** `scripts/tests/test_smelter.gd:153` | **Category:** test-gap, found by test-quality

The file docstring (lines 13-14) promises coverage of 'BLOCKED_OUTPUT state when output buffer fills (and recovery when it drains)'. The actual phase only asserts that inputs, output, and fuel are unchanged after 50 ticks; it never checks state == Smelter.STATE_BLOCKED_OUTPUT, and it never drains the output buffer to verify the smelter resumes. Phase 7 immediately overwrites all state fields manually, so a bug where the smelter reports the wrong state to the UI, or fails to leave BLOCKED_OUTPUT after the output drains (permanent stall), passes this suite.

**Evidence:**
```
Lines 156-170 set out_buffer to cap and then check only: iron ore unconsumed, output still 8, fuel still 4 — no `_check(... state ... == Smelter.STATE_BLOCKED_OUTPUT ...)` and no drain-then-resume assertions, despite docstring line 14: "(and recovery when it drains)".
```
**Fix:** In Phase 6 of scripts/tests/test_smelter.gd, replace the at-cap setup with a one-below-cap setup so the smelter actually enters BLOCKED_OUTPUT via smelter.gd:116: set in_buffer = [[Items.Type.IRON_ORE, 2]], out_buffer = [[Items.Type.IRON_INGOT, 7]], state = Smelter.STATE_IDLE, progress = 0, recipe_id = "smelt_iron", fuel_buffer = 4. Tick ~45 so one 40-tick batch completes and emits the 8th ingot; then assert int(smelter.state.get("state", -1)) == Smelter.STATE_BLOCKED_OUTPUT, out count == 8, and remaining iron ore == 1 (second batch must not start). Tick ~50 more and re-assert ore == 1 and out == 8 (stall holds, fuel only decremented by the one completed batch: expect 3). Then drain: smelter.state["out_buffer"] = [] and tick ~50; assert state has left BLOCKED_OUTPUT, a new ingot was produced (out iron ingot count == 1), and in_buffer iron == 0 — this exercises the recovery branch at smelter.gd:126-128. Keep the existing keep-IDLE-when-pre-blocked checks if desired, but do not assert STATE_BLOCKED_OUTPUT on the old at-cap-from-IDLE setup, which legitimately stays IDLE.

<details><summary>Verification notes</summary>

- Confirmed test gap and doc drift: docstring (test_smelter.gd:13-14) promises BLOCKED_OUTPUT coverage "and recovery when it drains", but Phase 6 (lines 156-170) asserts only unchanged buffers/fuel — no state assertion, no drain/resume — and Phase 7 (173-178) overwrites all state. The BLOCKED_OUTPUT entry (smelter.gd:116) and recovery branch (smelter.gd:126-128) are exercised by no test in scripts/tests/ (thresher test asserts Processor.IDLE, different building/enum, no drain). Deleting the recovery check would still pass 33/33. Caveat: the reviewer's suggested fix is technically wrong — from IDLE with output at cap the smelter stays IDLE (smelter.gd:100-109 does nothing without room), so asserting STATE_BLOCKED_OUTPUT on the existing setup would fail against correct code; BLOCKED_OUTPUT is only entered when a completing batch emits into a now-full buffer (line 116). The fix must drive a batch to completion first.

</details>

### 29. _tick_regrowth iterates every ore deposit in resource_state every frame, not just active tree timers
**Where:** `scripts/world/grid_world.gd:1264` | **Category:** performance, found by perf-scale

_tick_regrowth runs from _process every frame. Its early-out is 'resource_state.is_empty()', but worldgen populates resource_state with an entry for EVERY ore deposit tile (world_generator.gd:368 'world.resource_state[pos] = {"richness": richness, ...}'), so it is never empty. With ~5% patch coverage of the 512x512 world, resource_state holds several thousand (~5-10k) entries. Every frame the code allocates a full keys() Array of all those entries and iterates them all, skipping each one via the 'regrowth_remaining' check — ~5-10k dict iterations plus one multi-thousand-element Array allocation per frame at 60fps (300-600k wasted iterations/sec, roughly a millisecond of GDScript per frame) even when zero trees have ever been chopped. Additionally, for each genuinely active timer it allocates a brand-new Dictionary per frame (line 1275) to mirror into resource_state_modifications — 60 dict allocations/sec per chopped tree. The docstring's claim 'Cost: O(active timers)' (line 1255) is wrong — it is O(all resource_state entries) — which is also doc-drift that will mislead future scaling work.

**Evidence:**
```
L1258: `if resource_state.is_empty(): return` ... L1264: `var keys: Array = resource_state.keys()` L1265: `for pos in keys:` L1267: `if not state.has("regrowth_remaining"): continue` ... L1275: `resource_state_modifications[pos] = {"regrowth_remaining": remaining}` — versus world_generator.gd:368 which puts every ore tile into resource_state. Comment L1255-1256: `## Cost: O(active timers).`
```
**Fix:** Add a sparse timer dict to GridWorld: `var _active_regrowth: Dictionary = {}  # Vector2i -> true`. Maintain it at every site that creates or removes a regrowth timer: (1) chop_tree (L915) adds the pos; (2) _restore_tree (L933) erases it; (3) the two defensive cancel paths that strip regrowth_remaining (~L301-306 and ~L425-430) erase it; (4) the save-load/deserialize path (~L860, v14 shape) rebuilds it by scanning restored resource_state once for entries with regrowth_remaining — otherwise loaded timers never tick. Rewrite _tick_regrowth to early-out on _active_regrowth.is_empty() and iterate _active_regrowth.keys() only. For the per-frame mirror allocation at L1275, mutate in place when the mirror entry exists (resource_state_modifications[pos]["regrowth_remaining"] = remaining) — chop_tree already seeds that dict at L916 — falling back to creating it only if absent. Fix the L1255 docstring to state the true cost, and apply the same treatment to the companion loop flagged at L1068 which self-describes as "Same iteration pattern as _tick_regrowth". Per the project's schema-bump discipline, note this changes no save format (in-memory index only, rebuilt on load).

<details><summary>Verification notes</summary>

- Confirmed. grid_world.gd L1015-1016 calls _tick_regrowth from _process every frame; L1258's only early-out is resource_state.is_empty(), and world_generator.gd L368 puts every ore-patch tile into resource_state at worldgen (~128 patches, ~5% coverage per L46/L48 comments -> thousands of entries), so the guard never fires. L1264 allocates a full keys() Array and L1265-1268 iterates all entries, skipping every ore tile via the regrowth_remaining check; L1275 allocates a new Dictionary per active timer per frame. Docstring L1255 ("Cost: O(active timers)... microseconds") contradicts actual O(|resource_state|) cost — doc drift confirmed. No frame-skip, dirty flag, or set_process guard exists anywhere in the file. Severity lowered to medium: it is pure wasted work (~thousands of dict iterations + one Array alloc per frame, likely sub-millisecond to ~1ms in GDScript), behaviorally correct, and invisible to the 33/33 test suite; it degrades frame budget headroom rather than gameplay.
- Reproduced by trace: world_generator.gd:368 puts every ore tile (~128 patches x ~60-80 tiles = ~5-10k entries) into resource_state, so the L1258 is_empty() early-out in grid_world.gd never fires; _process (L1015-1016) calls _tick_regrowth every frame, which allocates a full keys() Array (L1264) and iterates all entries, skipping every ore via the L1267 has("regrowth_remaining") check; L1275 additionally allocates a new Dictionary per active timer per frame. Docstring L1255 ("O(active timers)") and resource_nodes.gd:8-9 ("Most tiles with a resource_node have NO entry in resource_state") are both contradicted. Severity lowered to medium: no correctness impact, cost is bounded/constant (~5-10k dict iterations, sub-to-low-single-digit ms), world size is fixed, tests unaffected — but it is a genuine always-on hot-path waste versus documented design intent.

</details>

### 30. _draw iterates every world tile and every building each frame; culling is per-entry inside the loop
**Where:** `scripts/world/grid_world.gd:1385` | **Category:** performance, found by perf-scale

_process calls queue_redraw() unconditionally (line 1024), so _draw runs every frame. The terrain pass is `for tile_key in tiles:` — it walks the ENTIRE tiles dict (~15k+ entries on a typical seed: ~5% ore coverage plus 3-4k lake water plus forests/ambient trees) and rejects off-screen tiles with two bounds checks per entry. The buildings pass (line 1475) likewise walks ALL buildings with per-entry footprint culling. Cost is O(world content + total factory size) per frame instead of O(visible area): at 60fps that is ~1M dict iterations/sec for terrain alone, and a 10k-building megafactory adds another 600k iterations/sec (each with a footprint_of dict lookup) purely to discover that most buildings are off-screen. The visible window is at most ~70x40 tiles (~2800) even at min zoom, so >80% of this work is wasted, and the waste grows linearly as the factory and explored world grow — this is the code that will set the frame-rate ceiling long before the tick does. The Stage 3 plan in this same file ('extends to chunked infinite generation') makes full-dict iteration untenable.

**Evidence:**
```
L1024: `queue_redraw()` (every frame, unconditional). L1385-1390: `for tile_key in tiles:` ... `if tp.x < min_tile.x or tp.x > max_tile.x: continue`. L1475-1483: `for anchor_key in buildings:` ... `var fp: Vector2i = Buildings.footprint_of(b.type)` ... `if anchor.x + fp.x - 1 < min_tile.x or anchor.x > max_tile.x: continue`
```
**Fix:** Invert the terrain pass: iterate the already-computed visible rect (min_tile..max_tile, ~2800 tiles + padding) and use tiles.get(pos) lookups, making it O(view) regardless of world size — this also survives Stage 3 chunking unchanged. For buildings, add a region index (Vector2i region -> Array[anchor]) maintained in place_building/remove_building, reusing the existing 32x32 region primitive (WorldGenerator.REGION_SIZE and grid_world's region_of() helper at L596) so no new spatial concept is introduced; _draw then iterates only regions intersecting the view rect. Buildings spanning a region boundary should be registered in every region their footprint touches (or index by anchor and expand the queried region range by the max footprint size). Apply the same region bucketing to the soil/fertilizer/wasteland dicts only when profiling shows they matter — they are sparse and small today. Keep the footprint_of lookup after the cull check either way.

<details><summary>Verification notes</summary>

- All quoted code confirmed: unconditional queue_redraw() in _process (grid_world.gd L1024); terrain pass walks entire sparse tiles dict with per-entry bounds culling (L1385-1390); buildings pass walks all buildings and does the footprint_of dict lookup (buildings.gd L620) before the cull (L1475-1484); soil/fert/wasteland passes (L1414/1426/1443) repeat the pattern. No visibility guard, dirty flag, or spatial index exists anywhere on the draw path — region_visibility is never consulted in _draw. Scale estimate corroborated: 512x512 world (L17), ~5% non-default coverage per world_generator.gd L48-50 plus 6-10 forests and ambient trees gives ~10-15k tile entries walked per frame at 60fps. Cost is genuinely O(world content + building count) per frame vs an O(view) window of ~2800 tiles, and grows linearly with factory size; Stage 3 chunked-infinite comment at L15 makes full-dict iteration untenable. However, present impact is bounded (finite Stage 1 world, sparse tiles dict, small current factories — low single-digit ms/frame), so this is a scalability defect that is not yet frame-rate-limiting: severity adjusted high -> medium.
- Confirmed by direct trace: L1024 queue_redraw() is unconditional (sole call site), so _draw runs every frame; L1385 walks the entire sparse tiles dict with per-entry bounds culls (world gen puts ~10-15k entries in it: lakes r12-30 x2-4, forests r8-25 x6-10, ambient trees, ~256 region ore patches per world_generator.gd L40/51/113-139); L1475 walks ALL buildings with a footprint_of() call per entry before culling; the same pattern repeats at L1414/1426/1443. Cost is O(world content + factory size) per frame, not O(view), and L15's Stage 3 'chunked infinite generation' comment makes the pattern untenable long-term. Caveat: at the current 512x512 world this is a few ms/frame (a scaling ceiling, not a present-day stall), and no test covers it.

</details>

### 31. Soil regen, fertilizer decay, wasteland scarring, and tree regrowth advance in _process, violating the tick-only simulation law
**Where:** `scripts/world/grid_world.gd:1015` | **Category:** convention-violation, found by perf-scale

tick_system.gd's contract states the tick is 'the *only* clock the simulation should care about. Buildings, crops, weather, etc. all advance on tick boundaries — never on _process.' Yet GridWorld._process advances four pieces of simulation state (tree regrowth timers, fertilizer decay, soil regen with wasteland grace/scarring) using render-frame delta. Consequences: (1) performance — these O(N) passes run at display rate (60-144fps) instead of 20 tps, tripling-to-7x-ing their cost for zero gameplay benefit; (2) the console `tick_speed N` multiplier and `TickSystem.paused` do not apply — fast-forwarding makes planters grow/harvest faster (tick-driven) while soil regen and fertilizer decay stay at wall-clock rate, desynchronizing the exact soil-economy balance the sessions tuned (e.g. at tick_speed 10 a wheat cycle depletes soil 10x faster than it regens, scarring wasteland that would never occur at 1x); (3) frame-rate-dependent float accumulation makes soil timing differ between machines, undermining the project's determinism stance.

**Evidence:**
```
grid_world.gd L1015-1024: `func _process(delta: float) -> void: _tick_regrowth(delta) ... _tick_fertilizer_decay(delta) _tick_soil_regen(delta) queue_redraw()` — versus tick_system.gd L6-7: `## This is the *only* clock the simulation should care about. Buildings, crops, weather, etc. all advance on tick boundaries — never on _process.`
```
**Fix:** In grid_world.gd, move the three calls from _process (L1016-1023) into _on_tick (L568), passing a fixed dt of TickSystem.TICK_INTERVAL_SEC (or run every N ticks via `if tick_no % N == 0` with dt = N * TICK_INTERVAL_SEC — soil granularity is 30s/point so N=20, i.e. 1s cadence, is invisible and cheapest). Preserve the existing ordering: _tick_regrowth, then _tick_fertilizer_decay BEFORE _tick_soil_regen (the L1017-1021 comment explains the boost-expiry edge case). Keep queue_redraw() in _process. Update the "Per-frame" doc comments at L728, L1028, L1251 to say "per-tick". No test changes needed — test_fertilizer_chain.gd, test_soil_exhaustion.gd, and test_tree_harvest_lifecycle.gd all invoke the _tick_* helpers directly with explicit deltas, so relocating the call site is transparent to the 33/33 suite. This makes pause, tick_speed, and the test harness's paused-tick control apply uniformly, and removes frame-rate-dependent float accumulation.

<details><summary>Verification notes</summary>

- Confirmed. grid_world.gd L1015-1024 advances three simulation systems (tree regrowth L1257-1277, fertilizer decay L733-746, soil regen/wasteland L1049+) in _process with render delta, directly violating tick_system.gd L6-7's contract ("never on _process"). No guard exists: grid_world.gd never reads TickSystem.paused or tick_rate_multiplier; paused only gates TickSystem._process (L36-37) and console tick_speed (console.gd L707) only scales tick emission, so the tick_speed/pause desync is reachable exactly as claimed. Corroborating: test_runner.gd L52 pauses TickSystem for determinism, yet GridWorld._process still runs per headless frame — tests pass only because they call _tick_* helpers directly with explicit deltas. The 'per-frame by design' comments (L728-732) show intent but not an exemption from the stated contract, which CONVENTIONS.md's Tick determinism section reinforces.

</details>

### 32. _tick_soil_regen rebuilds the active-tiles set from ALL buildings every frame and its iteration set grows monotonically with scarred wasteland
**Where:** `scripts/world/grid_world.gd:1055` | **Category:** performance, found by perf-scale

Every frame (not tick), _tick_soil_regen: (a) iterates the ENTIRE buildings dict to find planters — in a 10k-building factory with 500 planters that is 10k dict iterations/frame just to filter; (b) allocates a fresh `active_tiles` Dictionary and performs 9 inserts per active planter (500 planters = 4.5k Vector2i dict inserts/frame = 270k/sec); (c) allocates a full keys() snapshot of tile_soil_modifications every frame. Worse, the iteration set never shrinks for wasteland: scarred tiles are skipped for regen (line 1106) but stay in tile_soil_modifications at soil 0 forever (only Premium Compost removes them), so every abandoned/scarred field permanently adds entries that are iterated (with a wasteland-state dict lookup each) 60 times per second for the rest of the save. At 5k modified tiles + 500 active planters this pass alone is ~20k dict operations/frame (~1.2M/sec), continuously, even when the player is nowhere near a farm.

**Evidence:**
```
L1054-1063: `var active_tiles: Dictionary = {}` ... `for anchor in buildings:` ... `for dx in range(-1, 2): for dy in range(-1, 2): active_tiles[Vector2i(...)] = true`. L1070: `for pos in tile_soil_modifications.keys():`. L1106-1107: `if is_wasteland_at(pos): continue` — scarred entries never leave tile_soil_modifications.
```
**Fix:** 1) Maintain a planter-only registry (Dictionary anchor -> Building) updated in place_building (L433) and the remove path, and iterate that instead of `buildings` at L1055 — keep the per-pass Planter.is_active check, since active/idle state changes without place/remove events. 2) Hoist `active_tiles` to a member scratch Dictionary and call clear() instead of reallocating (L1054). 3) Move the whole pass from _process to the game tick (coordinate with the related _process finding), passing accumulated delta — the grace-timer math (L1090) and regen accumulator (L1120) are already dt-scaled, and tests already call _tick_soil_regen with large dt values, so this is safe. 4) Maintain a `regen_candidates` Dictionary (subset of tile_soil_modifications keys) as the L1070 iteration source: add on soil modification, remove when a tile scars (L1092) and when it fully recovers (L1145), re-add in _restore_wasteland (L778). Keep tile_soil_modifications itself untouched so save schema v18 is unaffected; rebuild regen_candidates from tile_soil_modifications minus scarred tile_wasteland_state entries on load.

<details><summary>Verification notes</summary>

- Confirmed. _process (L1023) calls _tick_soil_regen every frame with only an is_empty() early-out (L1050). L1054-1063 reallocates active_tiles and iterates the ENTIRE anchor-keyed buildings dict (L46) to filter planters — no planter registry exists in the codebase. L1070 allocates a keys() snapshot per frame. Scarred tiles are skipped at L1106-1107 but never erased from tile_soil_modifications: the only erase paths (L628, L1145) require soil to rise, which scarred tiles cannot do, and _restore_wasteland (L772-780) is the sole exit, gated on Premium Compost. So the per-frame iteration set grows monotonically with abandoned wasteland, exactly as claimed. The function's own doc comment (L1031-1032) only accounts for O(planters×9), not the O(all-buildings) filter or the unbounded scarred-tile set. No guard refutes any part of the claim.

</details>

### 33. Per-tick transient Array/Dictionary allocations in every processor's pull/push path (edge_cells, accept lists, pull-order arrays)
**Where:** `scripts/world/processor.gd:102` | **Category:** performance, found by perf-scale

Processor.tick runs 20x/sec per machine and allocates on every tick regardless of whether anything moves: _try_pull_inputs builds a new `default_accept` Array and `per_dir_accept` Dictionary each call; every edge scan calls Buildings.edge_cells which allocates and fills a fresh Array (buildings.gd:681-701); the no-prefer push path scans chests then belts across 4 edges — up to 8 edge_cells allocations per output per tick; Belt.try_pull_matching allocates a 4-element `order` Array per candidate belt cell; Burner.try_pull_fuel and FertilizerApplicator._try_pull_input do the same. Inserter fuel-pull constructs literal arrays per tick too. The accept lists and edge-cell offsets are constants of (recipe, building type, dir) yet are recomputed and reallocated every tick. At 500 processors this is on the order of 100-300k short-lived Array/Dictionary allocations per second — in GDScript each is a refcounted heap object, so this is sustained allocator pressure that scales linearly with factory size and shows up as both per-tick cost and frame-time jitter.

**Evidence:**
```
processor.gd L102-103: `var default_accept: Array = []` / `var per_dir_accept: Dictionary = {}` (every tick); L224-229: `for dir in 4: for cell in Buildings.edge_cells(b.type, b.anchor, dir):` twice (chests then belts). buildings.gd L681-701: `static func edge_cells(...) -> Array: ... var cells: Array = [] ... cells.append(...)`. belt.gd L131-134: `var order: Array = [preferred]; for i in SLOTS_PER_TILE: ... order.append(i)` per pull attempt.
```
**Fix:** Three independent low-risk changes: (1) buildings.gd edge_cells — cache per (type, dir) as relative offsets in a static Dictionary keyed by t*4+dir (footprints are static per type), returning anchor+offset during iteration, or give callers an inline iteration helper; this fixes processor, burner, smelter, composter, mining_drill, and fertilizer_applicator at once. (2) belt.gd try_pull_matching — drop the order array: check `preferred` slot first, then loop 0..SLOTS_PER_TILE-1 skipping preferred. (3) processor.gd _try_pull_inputs — cache the (item_type, canonical_dir) grouping per recipe (computed once at Recipes load or lazily per recipe_id), but keep the capacity filter (L105) at pull time by checking _buffer_count inside _try_pull_from_cell/the accept match, since it depends on live buffer state and cannot be precomputed. Verify with the existing 33/33 headless suite; behavior must be identical (same pull order: pinned edges first, then 4-edge default scan).

<details><summary>Verification notes</summary>

- All cited code confirmed: processor.gd L101-102 allocates a fresh Array+Dictionary in _try_pull_inputs on every tick (called unconditionally at L55); buildings.gd L681-701 edge_cells returns a fresh Array per call with no caching anywhere; processor.gd L223-229 push path makes up to 8 edge_cells calls per output; belt.gd L131-134 builds an order Array per pull attempt. tick_system.gd L20 confirms 20 tps and grid_world.gd L568-575 ticks every building every tick with no idle-skip. Minor overstatements: the push path IS guarded when out_buffer is empty (L210-211 continue), and GDScript refcounting frees deterministically so "GC jitter" framing is weak — but the pull-path churn is unconditional and scales linearly with machine count, so the core finding stands. Also, the suggested Recipes.DATA precompute of accept lists is not fully possible: L105 filters by live in_buffer counts, so only the (item, dir) grouping is cacheable.

</details>

### 34. console.gd split trigger (~800 lines) already breached at 812 lines; NOTES still says 657 lines and 'defer the split'
**Where:** `NOTES.md:78` | **Category:** doc-drift, found by doc-drift

NOTES.md's Dev Console section defines an explicit refactor trigger: split console.gd into UI + command modules when it grows beyond ~800 lines. The file is now 812 lines (wc -l verified) — the wasteland command, tile-name formatting, and other Session 4 additions pushed it past the threshold — but NOTES.md still records the file at 657 lines with the split deferred. The project's own discipline (documented triggers fire actions) is silently violated: the trigger fired and neither the split happened nor was the doc updated with a conscious decision to waive it.

**Evidence:**
```
NOTES.md:78: 'If `console.gd` grows beyond ~800 lines ... split into `console.gd` (UI + activation) + `console_commands.gd` ... defer the split.' NOTES.md:74: '`console.gd` ended up at 657 lines'. Actual: `wc -l scripts/ui/console.gd` = 812.
```
**Fix:** Two valid resolutions, pick one and record it: (1) Perform the pre-planned ~30-min refactor exactly as cut in PROJECT_LOG.md:427 — console.gd keeps UI + LineEdit + activation, new scripts/ui/console_commands.gd gets the parser + command implementations (now 13+ commands including wasteland); update NOTES.md:74-78 and add a PROJECT_LOG entry noting the trigger fired. (2) If the single-file shape is still preferred, update NOTES.md:74 to the current 812-line count and rewrite NOTES.md:78 with an explicit decision to raise the trigger (e.g. ~1000 lines) or waive it, so the doc reflects a conscious call rather than silent drift. Option 2 is the cheaper honest fix; option 1 is what the project's own queued plan calls for.

<details><summary>Verification notes</summary>

- Confirmed on all points. NOTES.md:74 states "console.gd ended up at 657 lines" and NOTES.md:78 states the split trigger verbatim: split into console.gd (UI + activation) + console_commands.gd when the file "grows beyond ~800 lines ... defer the split." Actual wc -l on scripts/ui/console.gd is 812 lines, and Glob confirms no console_commands.gd exists — the split was never performed. PROJECT_LOG.md:397 and :427 corroborate that the ~800-line split is a formally queued trigger ("Console split if file grows past ~800 lines ... ~30-min refactor when triggered"), and grepping NOTES.md and PROJECT_LOG.md finds no waiver, raise, or conscious-deferral entry postdating the breach (the Session 4 wasteland command at NOTES.md:156 is what pushed it over). No guard or mitigating record exists anywhere; the doc is factually stale (657 vs 812) and the documented trigger fired without a recorded decision. Caveat keeping this at medium rather than high: the breach is marginal (812 vs a fuzzy "~800", 1.5% over), there is zero runtime impact, and the test suite is 33/33 — this is pure process/doc drift, exactly as the reviewer categorized it.

</details>

### 35. NOTES.md lifecycle rule points to CHANGELOG.md, which does not exist; 8+ SHIPPED sections never moved or deleted
**Where:** `NOTES.md:5` | **Category:** doc-drift, found by doc-drift

NOTES.md's header says entries must move to CHANGELOG.md (or be deleted) once the work ships. CHANGELOG.md does not exist anywhere in the repo, and NOTES.md (625 lines) retains at least eight fully-shipped sections marked SHIPPED/COMPLETE (Dev Console, Schema-mismatch UX, Soil exhaustion arc, Building Interaction UI arc, Tile passability, Camera zoom, Cloth chain prefer_dir, Map polish). The file's stated purpose — 'forward-looking design plans that aren't yet implemented' — no longer matches its contents, which is exactly how the stale status lines reported elsewhere in this review accumulated.

**Evidence:**
```
NOTES.md:5: 'Move entries to `CHANGELOG.md` (or just delete them) once the corresponding work ships.' Repo root listing shows only CONVENTIONS.md, INVENTORY_UI_PLAN.md, NOTES.md, PROJECT_LOG.md, SESSION_E_PLAN.md — no CHANGELOG.md.
```
**Fix:** Change NOTES.md:5 to: "Delete entries once the corresponding work ships — PROJECT_LOG.md and git history are the shipped-work record." Then prune the shipped sections (Dev Console, Schema-mismatch UX, Soil arc, Building Interaction UI, Tile passability, Camera zoom, Cloth chain prefer_dir, shipped halves of Inserter Arc / QoL / harvesting roadmap), but before deleting each, extract any still-forward-looking tails into their own short entries so they aren't lost — e.g. Camera zoom's "sprite migration is its own future session" (line 477-479), Dev Console's ~800-line console.gd split trigger (line 78), and the MIGRATIONS per-file refactor trigger (line 100). Do not create CHANGELOG.md — it would duplicate PROJECT_LOG.md's role.

<details><summary>Verification notes</summary>

- Confirmed. NOTES.md:5 reads verbatim "Move entries to `CHANGELOG.md` (or just delete them) once the corresponding work ships," and a repo-wide glob for **/CHANGELOG* finds nothing — the referenced file has never existed. NOTES.md:3 states the file holds "Forward-looking design plans that aren't yet implemented," yet the file retains at least 7 fully-shipped sections: Dev Console (line 66, "SHIPPED", follow-up smoke marked COMPLETED at line 72), Schema-mismatch UX (line 84, "both fixes SHIPPED... now closed"), Soil exhaustion arc (line 112, "ARC CLOSED"), Building Interaction UI (line 297, "COMPLETE... All 4 sessions SHIPPED"), Tile passability (line 363, "shipped"), Camera zoom (line 461, "shipped + polished... No active limitations"), Cloth chain prefer_dir (line 483, "shipped... closed"), plus Map (line 383, shipped with only polish remaining). One nuance the reviewer missed: several "shipped" sections carry genuinely forward-looking tails (Camera zoom's sprite-migration plan at line 477-479, Dev Console's 800-line split trigger at line 78, save-migration refactor trigger at line 100), so a blanket delete would lose live guidance — but that refines the fix, it does not refute the drift. No guard exists elsewhere; PROJECT_LOG.md is a separate log, not the CHANGELOG the rule names.

</details>

### 36. Stale context-brief plan file: describes save v9 / 8 tests; Session E shipped many sessions ago
**Where:** `SESSION_E_PLAN.md:3` | **Category:** doc-drift, found by doc-drift

SESSION_E_PLAN.md declares itself a hand-off brief 'loaded by the next session to re-establish context'. That purpose expired long ago: the cloth chain (Retter/Loom/Tailor), bag-as-consumable, and the camera-zoom adjacent request in this file all shipped (retter.gd/loom.gd/tailor.gd exist with panels; NOTES.md 'Cloth chain prefer_dir — shipped'). The file's snapshot — 'Save: v9', 'Tests: 8 passing', 'Schema bump v9 → v10 only if...' — is wildly divergent from reality (SAVE_VERSION 18, 33 test suites). If any future session actually loads it per its own instruction, it re-establishes a v9-era context, including a stale schema-bump instruction that predates the migration framework protocol in CONVENTIONS.md.

**Evidence:**
```
SESSION_E_PLAN.md:3: 'Loaded by the next session to re-establish context without a planning round-trip.' Lines 6-8: 'Tag: `session-d-complete` ... Save: v9 / Tests: 8 passing'. Actual: save_system.gd:121 'const SAVE_VERSION: int = 18'; 33 test suites in scripts/tests/.
```
**Fix:** Delete SESSION_E_PLAN.md — git history and PROJECT_LOG.md (Session E entries ~lines 2236-2256) preserve the narrative, and all content including the camera-zoom adjacent request has shipped (test_zoom_trigger_map.gd), so nothing needs folding into NOTES.md. Optionally reword INVENTORY_UI_PLAN.md:3, which cites SESSION_E_PLAN.md as its structural template, to avoid a dangling reference. Per project discipline ('Ask before deleting files'), confirm the deletion with the user first.

<details><summary>Verification notes</summary>

- Confirmed on every point. SESSION_E_PLAN.md:3 self-describes as a load-me hand-off brief; lines 6-8 snapshot 'Save: v9 / Tests: 8 passing' vs actual save_system.gd:121 SAVE_VERSION=18 and 33 test suites (34 files in scripts/tests/ incl. runner). All planned content shipped: scripts/world/retter.gd, loom.gd, tailor.gd + panels; test_bag_cap.gd, test_cloth_prefer_dir.gd; the adjacent camera-zoom request also shipped (test_zoom_trigger_map.gd), so nothing in the file is live. Line 48's 'Schema bump v9 → v10 only if...' contradicts the current CONVENTIONS.md Save schema protocol (lines 98-109: every bump requires a registered migration + test; NOTES.md:102 confirms it replaced the old protocol). File is still cited as a template at INVENTORY_UI_PLAN.md:3, so it retains ambient authority. No guard or reference makes the stale content harmless.

</details>

## LOW -- minor bugs, conventions, perf, doc drift  (48 findings)

### 37. load_game clears every parallel per-tile dict except tile_regen_progress — stale regen accumulators leak across loads
**Where:** `scripts/systems/save_system.gd:450` | **Category:** bug, found by save-integrity

load_game explicitly clears tile_soil_modifications (428), tile_fertilizer_state (438), tile_wasteland_state (450) and region_visibility (461), and WorldGenerator.generate clears tiles/resource_state/tile_modifications — but grid_world.tile_regen_progress (grid_world.gd:87) is never cleared on load. The docs acknowledge regen progress is not *serialized* (losing up to 30s of pending progress), but not that a mid-session load *keeps* the pre-load accumulators. Failure scenario: tile (10,10) has soil 40 with 0.97 accumulated progress; player F9-loads a save where (10,10) had soil 20 — the first regen frame adds delta to the stale 0.97 and immediately grants a soil point that was never earned in the loaded timeline. Entries for tiles that are pristine in the loaded save are never iterated by _tick_soil_regen (it walks tile_soil_modifications) so they linger in the dict indefinitely, and grant an unearned head start if that tile is later depleted again.

**Evidence:**
```
save_system.gd:428/438/450/461 clear the four sibling dicts; no `tile_regen_progress.clear()` anywhere in load_game or WorldGenerator.generate (world_generator.gd:212-216 clears only tiles, resource_state, tile_modifications).
```
**Fix:** In SaveSystem.load_game (scripts/systems/save_system.gd), add `grid_world.tile_regen_progress.clear()` adjacent to the `grid_world.tile_soil_modifications.clear()` at line 428, with a brief comment noting the accumulator is in-memory-only and must not survive a mid-session load. Optionally extend the v16 round-trip test in test_soil_exhaustion.gd: pre-seed world_b.tile_regen_progress before load_game and assert it is empty after a successful load.

<details><summary>Verification notes</summary>

- Confirmed. load_game (save_system.gd) clears tile_soil_modifications (428), tile_fertilizer_state (438), tile_wasteland_state (450), region_visibility (461), buildings/occupied (375-376), and WorldGenerator.generate (world_generator.gd:214-216) clears tiles/resource_state/tile_modifications — but grep shows no tile_regen_progress.clear() anywhere in the codebase; only per-tile erase() calls in grid_world.gd (779, 1094, 1112, 1146) and console.gd debug commands. The F9 mid-session load path (main.gd:519) reuses the live grid_world node, so pre-load accumulators survive. _tick_soil_regen (grid_world.gd:1120) seeds from tile_regen_progress.get(pos, 0.0), so a stale ~0.97 entry grants an immediate unearned soil point on the first post-load frame; entries for tiles pristine in the loaded save are never iterated (loop walks tile_soil_modifications.keys(), line 1070) and linger until that tile is later depleted. Docs (NOTES.md:122, PROJECT_LOG.md:735/818) only cover the serialization loss, not mid-session carryover. No test in scripts/tests/ loads into a world with pre-existing accumulator state (test_soil_exhaustion.gd only covers in-session erase).

</details>

### 38. load_game rehydrates explicit default-grass tiles into `tiles` that live code deliberately erases — post-load world state diverges from the equivalent live session
**Where:** `scripts/systems/save_system.gd:393` | **Category:** bug, found by save-integrity

chop_tree and deplete_resource intentionally erase a tile from `tiles` when it collapses to pure default (grass/no overlay/no resource) while KEEPING the tile_modifications entry as the procgen override. load_game reverses this: it unconditionally writes every tile_modifications entry into `grid_world.tiles`, so after a save/load cycle every fully-chopped/fully-mined default tile exists as an explicit Tile(GRASS, NONE, NONE) entry in `tiles`. The loaded world is therefore not state-identical to the session that was saved. Concrete symptom: the hover placement preview marks a cell blocked when `tiles.has(cell)` (grid_world.gd:1519), so after F5+F9 a tile where the player chopped a tree shows a red 'blocked' footprint preview when holding a building, while the identical pre-save session showed white — and placement actually succeeds, contradicting the preview. It also permanently grows the `tiles`/`tile_modifications` dicts with no-op entries.

**Evidence:**
```
grid_world.gd:921-923 (chop_tree): `tile_modifications[pos] = Tile.new(GRASS, NONE, NONE); tiles.erase(pos)`; save_system.gd:392-394 (load): `var modified := Tile.new(...); grid_world.tiles[pos] = modified; grid_world.tile_modifications[pos] = modified` — no collapse-to-default check; grid_world.gd:1519: `if tiles.has(cell) or has_building_at(cell): blocked = true`.
```
**Fix:** In save_system.gd load_game's tile_modifications loop (lines 389-396), mirror the runtime collapse rule: after building `modified`, keep `grid_world.tile_modifications[pos] = modified` unconditionally, but if `modified.base == Terrain.DEFAULT_BASE and modified.overlay == Terrain.DEFAULT_OVERLAY and modified.resource_node == ResourceNodes.DEFAULT` call `grid_world.tiles.erase(pos)` (an actual erase is required, not just skipping the insert, because WorldGenerator.generate has already inserted the canonical tile, e.g. the TREE tile, at that position); otherwise `grid_world.tiles[pos] = modified` as now. The existing `resource_state.erase(pos)` at line 395-396 stays as-is.

<details><summary>Verification notes</summary>

- Confirmed. (1) Quoted code exists exactly as claimed: chop_tree (grid_world.gd:921-923) and deplete_resource (grid_world.gd:875-877) both erase the tile from `tiles` when it collapses to Tile(GRASS, NONE, NONE) while keeping the tile_modifications override; clear_tile (359-360) follows the same collapse rule. (2) load_game (save_system.gd:389-396) unconditionally does `grid_world.tiles[pos] = modified` with no collapse check, and nothing later in load prunes it (only resource_state.erase at 396 — no tiles.erase anywhere in save_system.gd). Since WorldGenerator.generate already inserted the canonical tile (e.g. TREE), the pure-default modification overwrites rather than erases it, so post-load `tiles` contains explicit default-grass entries a live session would not have. (3) The symptom is reachable: save serializes all tile_modifications entries including the (GRASS, NONE, NONE) ones (save_system.gd:224-227), and the hover placement preview marks blocked on bare `tiles.has(cell)` (grid_world.gd:1519) while can_place_building (389-411) only checks occupancy + overlay_at — and several buildings allow Overlay.NONE (buildings.gd:427, 457, 491, 526, 554, 593), so after F5/F9 those buildings show a red preview on a fully-chopped/fully-depleted tile yet place successfully; pre-save the identical state showed white. For ore (no regrowth) the divergence is permanent; for trees it persists until the 300 s regrowth restores the tile. No guard refutes it; severity low is right (preview/UX inconsistency plus unbounded no-op dict growth, no gameplay-logic corruption since placement and passability read defaults correctly).

</details>

### 39. Harvester reassigns b.state["buffer"] to a new array — violates the CONVENTIONS.md mutate-in-place rule for building state
**Where:** `scripts/world/harvester.gd:123` | **Category:** convention-violation, found by save-integrity

CONVENTIONS.md (State storage) says: "Don't reassign b.state['key'] to a new array if other code holds a reference — mutate in place." Harvester._remove_from_buffer builds a fresh `keep` array and assigns it over state["buffer"], and drain_into does the same with `remaining`. Every other buffer in the codebase (Processor._buffer_remove, Chest._bag_remove, FertilizerApplicator._buffer_remove) mutates the existing array in place per the convention. Failure scenario: any code that captures the buffer array and uses it across a harvester tick or an E-drain — e.g. a building panel caching `building.state.get("buffer")` for its slot rendering, or a future test asserting through a held reference — silently observes the stale pre-drain array while the building's real state moved to a new object; the desync is invisible until items 'reappear' in the UI. The project made this rule law precisely because such aliasing bugs are hard to trace.

**Evidence:**
```
harvester.gd:110-123 (_remove_from_buffer): `var keep: Array = [] ... b.state["buffer"] = keep`; harvester.gd:151-163 (drain_into): `var remaining: Array = [] ... b.state["buffer"] = remaining`.
```
**Fix:** In harvester.gd, rewrite _remove_from_buffer and drain_into to mutate the existing array in place, matching Processor._buffer_remove (processor.gd:286). For _remove_from_buffer: iterate indices backward (for i in range(buf.size() - 1, -1, -1)), and for matching entries decrement entry[1] by the taken amount, calling buf.remove_at(i) when the entry reaches 0; return total removed. For drain_into: iterate backward over buf, call inv.add(type, count) per entry, set entry[1] to the leftover, remove_at(i) when leftover is 0; return moved. Drop the b.state["buffer"] = ... reassignment lines in both (the array is already the state value). No behavior change expected — the 33/33 test suite should still pass.

<details><summary>Verification notes</summary>

- Confirmed: harvester.gd:123 (_remove_from_buffer) and :163 (drain_into) reassign b.state["buffer"] to a freshly built array, while every peer buffer helper mutates in place (processor.gd:286-295, chest.gd:60-69, fertilizer_applicator.gd:239-247), and harvester's own _add_to_buffer (:101-108) mutates in place — so the file violates the CONVENTIONS.md:78 mutate-in-place rule as uniformly practiced. Caveat verified: no current code actually holds the buffer array across a reassignment (harvester_panel.gd:133 and building_panel.gd:374-380 re-fetch from b.state per call; single-threaded, no await), so the claimed desync is not reachable today — this is a prophylactic consistency violation, not a live bug, which keeps severity at low.

</details>

### 40. Drill pulls fuel from all four edges, eating its own coal output and any passing fuel belt
**Where:** `scripts/world/mining_drill.gd:119` | **Category:** design-flaw, found by sim-core

MiningDrill.tick calls Burner.try_pull_fuel(b, world, -1), which scans all 4 edges including the rotated-east output edge. A coal drill pushes mined coal onto its output belt; whenever fuel_buffer <= 12 (coal is 4 units and the pull skips only when it would exceed 16), the next tick pulls that same coal back off the output belt and burns it, silently taxing coal throughput. Any unrelated belt running along the drill's other edges carrying wood/coal/briquettes is also raided. Burner.gd's own header warns 'Do NOT pass -1 (scan-all-edges) in production code unless the building has no other item ports' — the drill has an output port, so the parenthetical excusing it (no *input* port) does not actually cover this case.

**Evidence:**
```
Line 119: `Burner.try_pull_fuel(b, world, -1)`; burner.gd lines 80-97 pull any FUEL_VALUES item from any belt slot on the scanned edge; mining_drill.gd lines 229-241 push output to the rotated-E edge cells that the -1 scan also covers.
```
**Fix:** Add `const FUEL_PORT_DIR: int = Belt.DIR_S` to MiningDrill (matching smelter.gd:39 / inserter.gd:87) and change mining_drill.gd:119 to `Burner.try_pull_fuel(b, world, Buildings.world_dir(b, FUEL_PORT_DIR))`. Update the doc comment at mining_drill.gd:13 ("Fuel input: any of 4 edges") and the burner.gd:22-25 parenthetical that excuses the drill's -1. Add a regression test mirroring test_inserter.gd case 10: place a coal drill with a belt on its output edge, let it push coal, run ticks with fuel_buffer <= 12, and assert the belt coal is not re-ingested. If deliberate coal self-fueling is ever wanted, implement it explicitly from output_buffer rather than by rescanning the output belt.

<details><summary>Verification notes</summary>

- Confirmed. mining_drill.gd:119 passes -1; burner.gd:63 scans all 4 edges and :80-97 pulls any FUEL_VALUES item from any belt slot with only a capacity guard (:91), so at fuel_buffer <= 12 a coal (4 units) is pulled. The output push (mining_drill.gd:229,236) targets the same rotated-E edge_cells the scan covers, and Belt.try_insert (belt.gd:96-100) leaves the coal in that tile's slots for >= 4 ticks/slot while the drill pulls every tick — the self-ingest loop and side-edge belt raiding are mechanically reachable with no guard anywhere. Violates burner.gd:12-25's own rule ('no other item ports' — the drill has an output port; the parenthetical only excuses lack of an input port); Smelter (smelter.gd:81) and Inserter (inserter.gd:140) both use FUEL_PORT_DIR, leaving the drill the sole -1 caller. No test in test_mining_drill.gd covers fuel items on the output belt. Mitigating: mining_drill.gd:13 documents all-edge fuel input as v1 intent, so this is a conscious-but-flawed design rather than an accident — severity stays low.

</details>

### 41. Composter comments claim '1x1 non-rotatable, no prefer_dir' while DATA and recipes implement the opposite
**Where:** `scripts/world/recipes.gd:207` | **Category:** doc-drift, found by sim-core

The comment block introducing the composter recipes says 'No prefer_dir on inputs/outputs (Composter is 1x1 non-rotatable; Processor falls back to any-side accept)', and composter.gd's header (lines 15-16) repeats 'composter is 1x1 non-rotatable; any adjacent belt works for both pull and push'. Both statements are false: buildings.gd Type.COMPOSTER declares `"supports_direction": true` (line 498) and every composter recipe output declares `Belt.DIR_E` prefer_dir (lines 224, 235, 246, 263, 274) — the very same file even explains the prefer_dir rationale six lines later. A future contributor trusting the header could reintroduce the backward-push jam the prefer_dir was added to prevent, or mis-diagnose why a rotated composter refuses to output to a given side.

**Evidence:**
```
recipes.gd lines 207-209: 'No prefer_dir on inputs/outputs (Composter is 1x1 non-rotatable...' immediately followed by lines 213-214: 'Composter outputs declare prefer_dir = canonical E so the rotated east edge is the only push target'; composter.gd lines 15-16 repeat the stale claim; buildings.gd line 498: `"supports_direction": true`.
```
**Fix:** In recipes.gd, rewrite the stale portion of the comment at lines 206-209 to: "Recipe inputs carry no prefer_dir (feeders may arrive from any side); outputs pin prefer_dir = canonical E, which rotates with the building (Composter supports_direction = true)" — the existing accurate rationale at lines 213-218 can stay as-is. In composter.gd, replace lines 15-16 with the same corrected statement (keep line 14's "No fuel" sentence). No code changes; buildings.gd lines 487-498 are already correct and self-documenting.

<details><summary>Verification notes</summary>

- Confirmed. recipes.gd lines 206-209 state "No prefer_dir on inputs/outputs (Composter is 1x1 non-rotatable...)" yet lines 213-218 in the same comment block explain that composter outputs DO declare prefer_dir = canonical E, and every composter recipe output carries Belt.DIR_E (lines 224, 235, 246, 263, 274) while inputs are 2-element (direction-free, e.g. line 222). composter.gd lines 15-16 repeat the stale claim ("No prefer_dir on inputs/outputs — composter is 1x1 non-rotatable; any adjacent belt works for both pull and push"). buildings.gd line 498 sets "supports_direction": true for Type.COMPOSTER, with lines 492-497 explicitly documenting it is rotatable precisely so the output prefer_dir rotates and backward-push jams are prevented. The old sentences directly contradict both the current DATA and the adjacent accurate comments; no code guard makes them true. Pure doc-drift, no runtime defect (33/33 tests unaffected).

</details>

### 42. Unbounded tick catch-up loop after a long frame stall
**Where:** `scripts/systems/tick_system.gd:45` | **Category:** performance, found by sim-core

The accumulator loop `while _accumulator >= TICK_INTERVAL_SEC` has no cap on ticks per frame. Godot does not clamp _process delta, so after an OS suspend, a long window drag, a debugger pause, or a multi-second GC/loading hitch, delta can be tens of seconds: 60 s * 20 tps * tick_rate_multiplier (up to 10 via the console) = up to 12,000 full-world ticks executed in a single frame, each iterating every building twice (tick + post_tick in grid_world._on_tick). On a large factory this appears as a multi-second freeze on resume, and if a tick ever costs more than 50 ms the loop can enter a spiral where each frame accumulates more debt than it retires.

**Evidence:**
```
Lines 42-48: `_accumulator += delta * tick_rate_multiplier` then `while _accumulator >= TICK_INTERVAL_SEC: _accumulator -= TICK_INTERVAL_SEC; current_tick += 1; tick.emit(current_tick)` — no max-ticks-per-frame clamp.
```
**Fix:** In tick_system.gd _process, clamp accumulated debt before draining: add `const MAX_CATCHUP_TICKS: int = 20` near TICK_INTERVAL_SEC, then after line 42 insert `_accumulator = minf(_accumulator, TICK_INTERVAL_SEC * MAX_CATCHUP_TICKS)`. This bounds any single frame to at most 20 ticks (1 s of sim time) regardless of stall length or multiplier, silently dropping excess sim debt after pathological stalls. Do not cap inside the loop with a counter that preserves leftover accumulator — that would smear thousands of queued ticks across subsequent frames and still stall; discarding the debt is the intended behavior. current_tick monotonicity (doc contract, lines 15-16) is unaffected. Optionally document the drop in the class comment.

<details><summary>Verification notes</summary>

- Confirmed. tick_system.gd:42-48 matches the quote verbatim: unbounded `while _accumulator >= TICK_INTERVAL_SEC` catch-up loop with no per-frame tick cap. No guard exists elsewhere: console.gd:704-707 only clamps tick_rate_multiplier to [0.1,10.0] (already assumed by the claim), project.godot sets no delta/fps options, and the `paused` flag (line 24) is never set on focus loss or suspend anywhere in scripts/. Godot 4 clamps physics steps but not _process delta, so a multi-second stall (OS suspend, Windows window drag blocking the main loop, debugger pause) yields delta equal to the stall; the loop then emits delta*20*multiplier ticks in one frame, each running grid_world._on_tick (grid_world.gd:568-575) which iterates every building twice (tick_one + post_tick_one). CONVENTIONS.md tick rules (lines 138-142) impose no catch-up cap, so this is a genuine performance defect, not a convention issue. Severity low stands: real-world impact is a freeze-on-resume proportional to stall length; the spiral case requires per-tick cost >50 ms, i.e. a game already below real-time.

</details>

### 43. try_pull_fuel docstring still says inserters pass -1 (scan-all-edges)
**Where:** `scripts/world/burner.gd:56` | **Category:** doc-drift, found by machines

The docstring reads 'buildings without one (e.g., drill in v1, inserters) pass -1', but Inserter.tick has passed a rotated FUEL_PORT_DIR since session-inserter-fast-filter — the file's own header (lines 12-25) describes fixing exactly that bug. A future burner consumer (charcoal kiln, brick kiln) written from this docstring would copy the -1 antipattern and reintroduce the source-tile-as-fuel bug the header warns about. Documentation that contradicts the file's own warning block is worse than no documentation.

**Evidence:**
```
## fuel_edge_dir: which world-space edge to scan (Belt.DIR_E/S/W/N) — if -1,
## scans all 4 edges. Buildings with a "fuel input port" pass their port
## direction; buildings without one (e.g., drill in v1, inserters) pass -1.
```
**Fix:** In burner.gd lines 54-56, change the try_pull_fuel docstring example list to: "Buildings with a fuel input port pass Buildings.world_dir(b, FUEL_PORT_DIR) (smelter, inserters); only buildings with no other item ports may pass -1 (currently just the mining drill in v1 — see the FUEL PORT DIRECTION warning above before adding new -1 callers)." No code changes needed; behavior is already correct and covered by test_inserter.gd case 10.

<details><summary>Verification notes</summary>

- Confirmed doc-drift. burner.gd:54-56 docstring says inserters pass -1, but inserter.gd:140 passes Buildings.world_dir(b, FUEL_PORT_DIR) (FUEL_PORT_DIR = Belt.DIR_S, inserter.gd:87). burner.gd's own header (lines 12-25) documents that Inserter's -1 was the source-tile-as-fuel bug fixed at session-inserter-fast-filter, and test_inserter.gd:309-334 asserts the fixed behavior. Only mining_drill.gd:119 still passes -1, so the "drill in v1" example is accurate; "inserters" is stale and contradicts the file's own required-pattern warning. No code defect, docstring only.

</details>

### 44. Composter header claims non-rotatable with no prefer_dir, contradicting DATA and its recipes
**Where:** `scripts/world/composter.gd:15` | **Category:** doc-drift, found by machines
> Duplicate of finding #41 (independently rediscovered by a second dimension -- kept for its extra evidence).

The file header says 'No prefer_dir on inputs/outputs — composter is 1×1 non-rotatable; any adjacent belt works for both pull and push', and _maybe_select_recipe's comment repeats 'composter is non-rotatable'. In reality Buildings.DATA sets supports_direction: true for COMPOSTER (with a long comment explaining the rotation rationale), and all five composter recipes declare output prefer_dir Belt.DIR_E, so pushes go ONLY to the rotated east edge. The stale recipes.gd comment block above the composter recipes even contradicts itself in the same paragraph. Anyone extending the composter from these headers (e.g. adding a recipe without the DIR_E output pin) would silently reintroduce the compost-pushed-backward-onto-input-belt bug the prefer_dir was added to prevent.

**Evidence:**
```
## No fuel (biological process) — recipe runs purely on input availability.
## No prefer_dir on inputs/outputs — composter is 1×1 non-rotatable; any
## adjacent belt works for both pull and push.  (vs buildings.gd: "supports_direction": true; recipes: [Items.Type.COMPOST_LOW, 1, Belt.DIR_E])
```
**Fix:** 1) composter.gd lines 14-16: replace with "No fuel (biological process). Rotatable (supports_direction) — inputs are direction-free (any adjacent belt feeds), but outputs declare canonical prefer_dir E, rotated by b.dir, so compost only pushes out the rotated east edge (prevents push-back onto input belts)." 2) composter.gd lines 69-70: change the port-peek rationale to "recipe INPUTS have no prefer_dir, so all 4 sides are valid feed edges" (drop the non-rotatable claim). 3) recipes.gd lines 207-209: delete the "No prefer_dir on inputs/outputs (Composter is 1×1 non-rotatable...)" sentence — the accurate contract already follows at lines 213-218.

<details><summary>Verification notes</summary>

- Confirmed: composter.gd:14-16 and :69-70 say non-rotatable/no prefer_dir, but buildings.gd:498 has supports_direction:true for COMPOSTER (comment at 493-497 says output direction constrained), and all 5 composter recipes pin output to Belt.DIR_E (recipes.gd:224,235,246,263,274). recipes.gd:207-209 vs 213-218 self-contradicts in one comment block. composter.gd:50-55 make() even contradicts its own header ("output prefer_dir rotates with the building"). Rotation is player-reachable (main.gd:443-451, 678). Pure doc-drift; runtime behavior correct, no guard needed or claimed.

</details>

### 45. Fallback-lake origin exclusion tests only the anchor, so the 4x4 footprint leaks into the spawn buffer on the negative side
**Where:** `scripts/world/world_generator.gd:448` | **Category:** bug, found by soil-worldgen

The v4 spawn-buffer check `max(abs(ax), abs(ay)) < FALLBACK_LAKE_ORIGIN_EXCLUSION` excludes anchors within Chebyshev 5 of origin, but the lake footprint extends in +dx/+dy only (anchor..anchor+3). For positive anchors like (6,0) the nearest water tile is at Chebyshev 6 as intended, but an anchor at (-6,0) — which passes the check — places water at (-3,0..3), Chebyshev 3 from origin. The in-code comment ('exclude any anchor whose 4x4 footprint would overlap the spawn-buffer zone') claims footprint-overlap exclusion, which is false for negative anchors. Since candidates are sorted distance-ascending and the seeded pick draws from the 10 closest, negative-quadrant Chebyshev-6 anchors are routinely in the pool, so on low-natural-water seeds forced water lands 3-5 tiles from spawn — half the documented 6-tile buffer. Origin itself stays dry (anchors covering (0,0) need Chebyshev <= 3 and are excluded), so the hard console-testing guarantee survives, but the buffer is asymmetric. Fixing this changes worldgen output and requires a VERSION bump per the file's own policy.

**Evidence:**
```
if max(abs(ax), abs(ay)) < FALLBACK_LAKE_ORIGIN_EXCLUSION:
	continue
```
**Fix:** In _ensure_spawn_area_water, replace the anchor-only check (line 448) with a nearest-footprint-tile Chebyshev check: `var nx: int = clampi(0, ax, ax + FALLBACK_LAKE_SIZE - 1)` and `var ny: int = clampi(0, ay, ay + FALLBACK_LAKE_SIZE - 1)`, then `if max(abs(nx), abs(ny)) < FALLBACK_LAKE_ORIGIN_EXCLUSION: continue`. This makes the code match the lines 446-447 comment exactly (equivalent to the reviewer's interval-overlap form but symmetric and self-documenting). Per the file's VERSION POLICY (lines 6-29, item 'Spawn safety net algorithm'), bump VERSION to 5 at line 31, note the diff in PROJECT_LOG, and update the line 147-156 constant doc to say the exclusion applies to the footprint, not just the anchor. Add a test in scripts/tests/ that forces the fallback on a low-water seed and asserts no water tile within Chebyshev FALLBACK_LAKE_ORIGIN_EXCLUSION of origin.

<details><summary>Verification notes</summary>

- Confirmed. Line 448 tests only the anchor, but the 4x4 footprint extends +dx/+dy (lines 473-476), so anchor (-6,0) passes and places water at (-3,0) — Chebyshev 3 from origin, versus 6 on the positive side. Inline comment (lines 446-447) falsely claims footprint-overlap exclusion. Scenario is reachable: candidates sort Euclidean-ascending (457-463) and the nearest ring (d²=36-37, includes (-6,0),(0,-6),(-6,±1)) fills the top-10 seeded pool (466-470). No downstream guard (_clamp_spawn_area_water_max at 478 only fires >900 tiles) and no test in scripts/tests/ covers the exclusion. However, the origin-dry guarantee (line 31, v4) holds — anchors covering (0,0) need max<=3 and are excluded — and the constant's own spec (lines 147-156) only promises anchor distance, so this is asymmetric-buffer + comment drift on rare low-water seeds, not a broken guarantee.

</details>

### 46. tile_regen_progress is not cleared on load, so the pre-load session's accumulators bleed into the loaded world
**Where:** `scripts/systems/save_system.gd:428` | **Category:** bug, found by soil-worldgen
> Duplicate of finding #37 (independently rediscovered by a second dimension -- kept for its extra evidence).

load_game clears tile_soil_modifications, tile_fertilizer_state, tile_wasteland_state, region_visibility, buildings, and resource_state_modifications, but never touches grid_world.tile_regen_progress (and _generate_fresh_world in main.gd doesn't either). main.gd's quick_load (main.gd:518-524) loads mid-session, so a tile that had accumulated up to ~1.0 progress (30 s of regen) before the load keeps that progress and applies it to the loaded world's soil value on the next frame — the reverse of the documented 'lossy up to 30 s' rule (the design accepts losing pending regen, not gaining phantom regen). Orphan entries for tiles that are pristine in the loaded save also persist indefinitely and are silently inherited if that tile is ever depleted again.

**Evidence:**
```
grid_world.tile_soil_modifications.clear()
... grid_world.tile_fertilizer_state.clear()
... grid_world.tile_wasteland_state.clear()
(no grid_world.tile_regen_progress.clear() anywhere in load_game)
```
**Fix:** Prefer clearing in one shared place: add `world.tile_regen_progress.clear()` to WorldGenerator.generate (world_generator.gd, next to the existing tiles/resource_state/tile_modifications clears at lines 214-216). Both load_game (save_system.gd:383) and _generate_fresh_world (main.gd:302) call generate(), so this single line fixes the mid-session quick_load bleed, the failed-load fresh-world fallthrough, and any future regeneration call site. Alternatively (if you want save_system to own all save-state resets), add `grid_world.tile_regen_progress.clear()` beside the tile_soil_modifications.clear() at save_system.gd:428 AND in main.gd._generate_fresh_world — but the generator-level clear is the smaller, more robust change. Optionally extend test_soil_exhaustion.gd with a check that generate() leaves tile_regen_progress empty.

<details><summary>Verification notes</summary>

- Confirmed. load_game (save_system.gd:375-463) clears buildings, occupied, resource_state_modifications (405), tile_soil_modifications (428), tile_fertilizer_state (438), tile_wasteland_state (450), and region_visibility (461), but never tile_regen_progress; WorldGenerator.generate (world_generator.gd:214-216) clears only tiles/resource_state/tile_modifications, and _generate_fresh_world (main.gd:299-309) adds nothing. quick_load (main.gd:518-524) mutates the live grid_world mid-session, and _tick_soil_regen (grid_world.gd:1120) reads tile_regen_progress.get(pos, 0.0) for every depleted tile, so pre-load accumulator values apply phantom regen (< 1 soil point per tile, since lines 1125/1141 keep only the fractional remainder) on the next frame. Orphan entries for tiles pristine in the loaded save persist because the loop keys off tile_soil_modifications. PROJECT_LOG.md:735/818 and NOTES.md:122 document save/load as lossy (losing regen), making phantom gain a documented-behavior violation. No test in scripts/tests covers load-time clearing (test_soil_exhaustion.gd:267/278 are in-session only).

</details>

### 47. set_soil does not clear wasteland state, producing a pristine-soil-but-scarred tile the regen loop can never heal
**Where:** `scripts/ui/console.gd:528` | **Category:** bug, found by soil-worldgen

`set_soil x y 100` erases the tile from tile_soil_modifications (and regen progress) but leaves any tile_wasteland_state entry intact. On a scarred tile this yields soil = 100 with scarred = true: the planter gate (Planter.tick line 90) still blocks growth, the wasteland tint still draws, and because the tile is no longer in tile_soil_modifications, _tick_soil_regen never iterates it — the scar is permanent short of Premium Compost, which then snaps soil DOWN from 100 to 30 via _restore_wasteland. The sibling `wasteland` command carefully writes all three dicts consistently (soil 0 + scarred + progress erase), so set_soil is the odd one out. Dev-only surface, but it undermines the console's role as the wasteland-testing tool.

**Evidence:**
```
if v >= GridWorld.TILE_SOIL_FULL:
	grid_world.tile_soil_modifications.erase(pos)
	grid_world.tile_regen_progress.erase(pos)
(no grid_world.tile_wasteland_state.erase(pos))
```
**Fix:** In _cmd_set_soil (console.gd, after computing v at line 526), erase the wasteland entry whenever v > 0: add `if v > 0: grid_world.tile_wasteland_state.erase(pos)` before the existing branch. This clears both scarred and grace entries on any positive set (mirroring the regen loop's rescue rule but extended to scars, which is the correct semantic for a dev override), while `set_soil x y 0` still leaves wasteland/grace state intact for testing the soil-0 arc. Optionally note the behavior in the command's help string.

<details><summary>Verification notes</summary>

- Confirmed. console.gd:527-529 erases only tile_soil_modifications and tile_regen_progress; nothing in _cmd_set_soil touches tile_wasteland_state. is_wasteland_at (grid_world.gd:751-753) reads only tile_wasteland_state, so `wasteland x y` then `set_soil x y 100` yields soil=100 + scarred=true: Planter.tick gates on it (planter.gd:90), the tint loop draws it (grid_world.gd:1443), and _tick_soil_regen iterates tile_soil_modifications.keys() only (grid_world.gd:1070) with its grace-clear branch explicitly skipping scarred entries (1100), so no tick path ever heals the scar. The sole escape, HIGH compost via try_apply_fertilizer:705 -> _restore_wasteland:778, unconditionally snaps soil to 30. The sibling _cmd_wasteland (console.gd:725-727) writes all three dicts consistently, confirming set_soil is the outlier. No guard elsewhere refutes it; test_wasteland.gd covers no set_soil interaction.

</details>

### 48. deplete_planter_area writes soil entries for out-of-world tiles at the map edge
**Where:** `scripts/world/grid_world.gd:662` | **Category:** bug, found by soil-worldgen

Neither deplete_tile_soil nor deplete_planter_area bounds-checks positions, and set_overlay/place_building don't either, so a planter placed at x or y = 255 (WORLD_MAX-1, reachable by normal tilling/placement) depletes neighbor tiles at coordinate 256 — outside [WORLD_MIN, WORLD_MAX). Those phantom entries are ticked by _tick_soil_regen every frame, tinted by the _draw soil pass beyond the world edge, serialized into tile_soil_modifications on save (e.g. [256, y, 97]), and can even start wasteland grace timers. The dev console guards every command with _in_world_bounds while the gameplay path doesn't, which is backwards.

**Evidence:**
```
for dx in range(-1, 2):
	for dy in range(-1, 2):
		...
		deplete_tile_soil(Vector2i(anchor.x + dx, anchor.y + dy), neighbor_cost)
```
**Fix:** Add the bounds check as a single choke point at the top of deplete_tile_soil (grid_world.gd:624): if pos.x < WORLD_MIN or pos.x >= WORLD_MAX or pos.y < WORLD_MIN or pos.y >= WORLD_MAX: return TILE_SOIL_FULL (out-of-world tiles are permanently pristine; return value keeps the signature contract). This covers deplete_planter_area's edge spill and any future caller. Note a wider related gap the finding only brushes: set_overlay/place_building themselves accept out-of-world positions (player can walk and build past the edge since absent tiles default to passable grass), which may deserve its own follow-up guard in can_place_building/set_overlay.

<details><summary>Verification notes</summary>

- Confirmed. deplete_tile_soil (grid_world.gd:624-631) and deplete_planter_area's 3x3 loop (655-662) have no bounds check; the placement path is equally unguarded (can_place_building:389, set_overlay:286, main.gd:_try_place:651, player movement passability-only with base_at:232 defaulting absent tiles to grass), so a planter at x=255 is reachable and its harvest (planter.gd:131) writes tile_soil_modifications[(256,y)]. Phantom entries are ticked by _tick_soil_regen (1049-1146, including wasteland grace at 1070-1080), tinted by the _draw soil pass (1414+, viewport-filtered only), and serialized/restored without validation (save_system.gd:256-257, 428-431). The console (console.gd:449-452, 558) and fertilizer_applicator.gd (202-205) do guard, confirming the claimed asymmetry.

</details>

### 49. _neighbor_falloff_cost floors at 1, so the documented negative-cost (legume) crops would damage neighbors while healing the center
**Where:** `scripts/world/grid_world.gd:641` | **Category:** design-flaw, found by soil-worldgen

Planter.CROP_DATA and soil_cost_for both document 'future legumes can return negative to heal soil', and deplete_tile_soil's erase-on->=100 branch handles negative amounts correctly for the center tile. But _neighbor_falloff_cost returns `max(1, ceil(cost * 0.6))`, so a healing crop with soil_cost -5 heals its center by 5 while depleting all 8 neighbors by 1 each harvest — a net-negative area effect that inverts the design intent the moment the first legume is added. Nothing fails today, but the trap is armed and no test covers a negative cost.

**Evidence:**
```
static func _neighbor_falloff_cost(center_cost: int) -> int:
	return max(1, int(ceil(float(center_cost) * 0.6)))
```
**Fix:** In grid_world.gd _neighbor_falloff_cost, make the floor apply only to positive costs while gating on strictly negative to preserve the existing falloff(0)==1 test (test_soil_exhaustion.gd:74): `static func _neighbor_falloff_cost(center_cost: int) -> int: if center_cost < 0: return int(ceil(float(center_cost) * 0.6)) return max(1, int(ceil(float(center_cost) * 0.6)))` — note GDScript ceil on negatives gives ceil(-3.0) = -3 (heal neighbors by 60%, rounded toward zero), matching the positive-cost magnitude convention. Update the comment at lines 633-639 to state the sign-aware behavior, and add a test asserting _neighbor_falloff_cost(-5) == -3 plus a deplete_planter_area integration case showing all 9 tiles heal, to land alongside (or ahead of) any Session 5 legume work.

<details><summary>Verification notes</summary>

- Confirmed. Code at grid_world.gd:640-641 matches verbatim; planter.gd:33/63 and PROJECT_LOG.md:582,838 document future legumes with negative soil_cost that heal their 3x3 AREA (not just center); deplete_tile_soil (grid_world.gd:624-631) does handle negative amounts (max(0, current - amount) plus erase-on->=100), so healing works for the center; but deplete_planter_area (655-662) feeds the cost through _neighbor_falloff_cost with no sign guard anywhere on the try_extract path (planter.gd:131), and max(1, ceil(-5*0.6)) = 1, so a cost -5 crop heals center +5 while depleting all 8 neighbors -1 — inverting the documented 3x3-healing intent. The max(1,...) floor's own comment (line 638) only justifies it for tiny POSITIVE costs. Test suite (test_soil_exhaustion.gd:66-75) covers falloff for 5,8,3,1,0 only; no negative-cost test exists. Not reachable today (no legume in CROP_DATA; Session 5 deferred per NOTES.md:114), exactly as the finding states — an accurately-scoped armed trap, not a current failure.

</details>

### 50. _safe_spawn_position sorts candidates without a tie-break, unlike every worldgen sort
**Where:** `scripts/main.gd:325` | **Category:** convention-violation, found by soil-worldgen

The spawn-candidate sort compares only squared distance; many candidates are equidistant from origin (e.g. (5,0), (0,5), (-5,0), (0,-5), (3,4), (4,3)...), and Array.sort_custom is documented as unstable, so the ordering of ties — and therefore which tile index the seeded rng.randi_range pick lands on within the top 20 — depends on the engine's sort implementation rather than on the seed. WorldGenerator's two candidate sorts (_ensure_spawn_area_water line 457, _clamp_spawn_area_water_max line 501) both add explicit 'then x, then y' tie-breaks for exactly this reason. Same binary reproduces today, but an engine upgrade can silently change the 'deterministic per seed' spawn the comment at lines 283-285 promises.

**Evidence:**
```
candidates.sort_custom(func(a, b):
	return (a.x * a.x + a.y * a.y) < (b.x * b.x + b.y * b.y)
)
```
**Fix:** In scripts/main.gd:324-326, replace the comparator with the worldgen pattern (world_generator.gd:457-463): compute da = a.x*a.x + a.y*a.y and db likewise; if da != db return da < db; if a.x != b.x return a.x < b.x; return a.y < b.y. This totally orders candidates so the seeded top-20 pick is engine-independent. No other call-site changes needed; note it may alter fresh-world spawns for existing seeds in the current binary (acceptable — only affects new worlds, saves store player position).

<details><summary>Verification notes</summary>

- Confirmed. main.gd:324-326 sorts spawn candidates by squared distance only, then a seeded rng picks from the top 20 (lines 327-330); the doc comment at 283-285 promises "same world_seed → same spawn". Equidistant ties are guaranteed in the top 20 (the distance-1 ring alone has 4 tiles) and Array.sort_custom is documented unstable, so tie order is engine-dependent. The convention precedent is exact: world_generator.gd:457-463 and 501-509 add distance-then-x-then-y tie-breaks on structurally identical seeded-pick sorts, and grid_world.gd:536 sorts lexicographically with a "Determinism" comment; CONVENTIONS.md lines 136-141 codify determinism reliance and treat same-seed procgen drift as a hard failure. No guard exists between the sort and the indexed pick. Tests passing is expected — within one binary the unstable sort is repeatable, so the defect only surfaces on engine upgrade.

</details>

### 51. try_apply_fertilizer accepts water, out-of-bounds, and infrastructure tiles; hand-apply consumes compost with zero effect and the fertilizer tint pass draws on them
**Where:** `scripts/world/grid_world.gd:690` | **Category:** design-flaw, found by soil-worldgen

try_apply_fertilizer validates only the tier and the wasteland/stacking rules — no terrain, bounds, or overlay check — and main.gd._try_apply_item consumes 1 compost whenever it returns true. Clicking a water tile (or a stone/path tile, or a spot past the world edge) with compost on the hotbar therefore succeeds, consumes the item, and buys nothing (soil under water/stone is gameplay-irrelevant and _soil_tint_for_tile deliberately filters those tiles). The fertilizer tint pass in _draw (lines 1426-1437) also lacks the infrastructure/water filter that the soil tint pass applies via _soil_tint_for_tile, so the wasted application paints a green square on water. The applicator building filters pristine tiles but the hand path doesn't even do that much for water.

**Evidence:**
```
func try_apply_fertilizer(pos: Vector2i, tier: int) -> bool:
	if fertilizer_duration(tier) <= 0.0:
		return false   # unknown tier — defensive guard
	(no base/overlay/bounds validation before writing tile_fertilizer_state)
```
**Fix:** In grid_world.gd try_apply_fertilizer, after the tier guard add: reject when pos.x/pos.y are outside [WORLD_MIN, WORLD_MAX) (constants at grid_world.gd:17-19), when base_at(pos) == Terrain.Base.WATER, or when overlay_at(pos) is Terrain.Overlay.STONE or PATH — return false so main.gd's existing reject branch toasts without consuming (add a distinct toast in main.gd:728-734 for the terrain-reject case, since the current two messages assume wasteland/tier rejects). Extract the WATER/STONE/PATH check into a small helper (e.g. _is_soil_relevant(pos)) shared by _soil_tint_for_tile (1236-1239) and reuse it in the fertilizer tint pass at 1426-1437 to skip drawing on soil-irrelevant tiles (guards pre-existing saves/console-injected state too). Add a test in scripts/tests/test_fertilizer_chain.gd asserting try_apply_fertilizer returns false on a water tile, a stone-overlay tile, and an out-of-bounds pos.

<details><summary>Verification notes</summary>

- Confirmed. try_apply_fertilizer (grid_world.gd:690-716) has only the tier guard (691), wasteland check (702-706), and stacking rules — no base/overlay/bounds validation. The hand path main.gd:_try_place (474, 687-693) passes raw hover_tile (from mouse, main.gd:413-414) with no reach/terrain gate, and _try_apply_item consumes 1 compost at main.gd:735 whenever the call returns true. A water tile is never wasteland and has no fertilizer state, so it hits the fresh-apply branch (708-710) and returns true — compost consumed for zero effect (water/paved tiles sit at TILE_SOIL_FULL per grid_world.gd:615-616 and _soil_tint_for_tile 1236-1239 documents them as soil-irrelevant). The fertilizer tint pass (1426-1437) indeed lacks the WATER/STONE/PATH filter the soil pass applies via _soil_tint_for_tile, so a green square is drawn on water. Applicator path filters bounds+pristine (fertilizer_applicator.gd:196-222) so only the hand path is exposed. No test in scripts/tests/ covers water/paved/OOB rejection. Only soft spot: the out-of-bounds leg depends on camera limits I did not trace, but the water/stone/path legs alone confirm the defect.

</details>

### 52. Panel keeps a stale Building reference after console destroy — deposits vanish into an orphan
**Where:** `scripts/ui/building_panel.gd:68` | **Category:** bug, found by ui-panels

open() stores the Building reference and nothing ever re-validates that the building still exists in grid_world. Normal input can't remove a building while a panel is open (main.gd:404 early-returns), but main.gd:567-574 deliberately allows the dev console to open over any modal, and console `destroy <x> <y>` (console.gd:642-663) calls grid_world.remove_building_at while the panel stays open and bound. The panel keeps rendering the orphaned building's state, and any items the player then drops into its slots (_drop_into_input writes building.state[...]) go into an object no longer in the world — permanently lost. Conversely, contents of the destroyed building remain pick-able from the ghost panel. Debug-build-only path, but it is a real item-loss/stale-UI hole and the only removal path that can race an open panel.

**Evidence:**
```
func open(b: Building, w: Node) -> void:
    building = b
    world = w
    visible = true  # no later check that b is still in world.buildings
```
**Fix:** Add a liveness guard in BuildingPanel._process (scripts/ui/building_panel.gd), which all subclass panels inherit: when visible, close() if the binding is stale — `if world == null or building == null or not world.buildings.has(building.anchor) or world.buildings[building.anchor] != building: close(); return` before the queue_redraw(). This covers the console destroy path and any future removal path (world is always grid_world, whose `buildings` dict is keyed by anchor — verified at main.gd:910-958 and grid_world.gd:454). Optionally also have console._cmd_destroy signal main to _close_active_building_panel() before removal for immediate UX, but the _process guard is the robust invariant.

<details><summary>Verification notes</summary>

- Confirmed. open() (building_panel.gd:68-73) binds building/world with no later liveness check (_process 62-64 only redraws; _gui_input 179 checks null only). Normal removal is gated by the modal early-return (main.gd:404), but the dev console opens over any modal by design (main.gd:565-579) and _cmd_destroy (console.gd:642-663) calls grid_world.remove_building_at (grid_world.gd:445-457), which only erases dict entries — no signal, no panel close (grep: _close_active_building_panel only called from Esc chain, main.gd:383). Building is RefCounted (building.gd:2), so the panel's ref keeps a silent orphan alive; _drop_into_input (294-308) deposits items into it (lost) and _take_from_slot (358+) still pulls from the ghost. Reachable without any race: open panel, toggle console, destroy, close console, interact. No test covers it. Only reachable in debug builds (OS.is_debug_build gate, main.gd:570), so severity lowered to low.

</details>

### 53. Chest swap capacity check ignores the outgoing stack, rejecting legitimate swaps near capacity
**Where:** `scripts/ui/chest_panel.gd:151` | **Category:** design-flaw, found by ui-panels

_handle_chest_slot_click rejects the drop when free_capacity < cursor.count, but in the swap path (view_present true) the clicked view's stack is removed immediately after the add, so the net capacity requirement is cursor.count minus the outgoing stack's count. A chest at 2395/2400 (free = 5) refuses a swap of 10 wheat (cursor) for a 50-coal view even though the post-swap total (2355) is far under capacity. No items are lost, but the player cannot perform swap operations in a nearly-full chest, which is exactly when they need to.

**Evidence:**
```
if Chest.free_capacity(building) < cursor.count:
    _toast("Chest full — cannot deposit...")
    return
Chest._bag_add(bag, cursor.item_type, cursor.count)
if view_present:
    ...
    Chest._bag_remove(bag, item_type2, c2)
```
**Fix:** In _handle_chest_slot_click (scripts/ui/chest_panel.gd, lines 150-163), account for the outgoing stack in the capacity check and remove it before adding. The views snapshot at line 138 predates any mutation, so c2 can be read up front:

    var outgoing: int = 0
    if view_present:
        outgoing = int(views[slot_idx]["count"])
    if Chest.free_capacity(building) + outgoing < cursor.count:
        _toast("Chest full — cannot deposit (need %d more capacity)" % (cursor.count - Chest.free_capacity(building) - outgoing))
        return
    if view_present:
        var v2 = views[slot_idx]
        var item_type2: int = int(v2["item_type"])
        Chest._bag_remove(bag, item_type2, outgoing)
        Chest._bag_add(bag, cursor.item_type, cursor.count)
        cursor.pick(item_type2, outgoing)
    else:
        Chest._bag_add(bag, cursor.item_type, cursor.count)
        cursor.clear()

Removing before adding keeps the bag total <= TOTAL_CAPACITY at every intermediate step (defensive, since _bag_add is unchecked). Add a regression test in scripts/tests/ for a swap on a chest whose free capacity is smaller than the cursor stack but whose net post-swap total fits.

<details><summary>Verification notes</summary>

- Confirmed in scripts/ui/chest_panel.gd: line 151 rejects when free_capacity < cursor.count regardless of view_present; lines 154-161 show the swap path removes the outgoing stack (c2) right after the add, so the net requirement is cursor.count - c2. free_capacity (chest.gd:71-72) is a pure aggregate and _bag_add (chest.gd:53) is unchecked, so no other guard compensates. Scenario is reachable (inserters can fill a chest to near TOTAL_CAPACITY via chest.gd:78-80; player cursor can hold a stack and click an occupied slot). No test in scripts/tests/ covers swap-near-capacity (test_building_ui_2.gd uses a chest at 80/2400). No item loss or crash — swaps are merely refused in near-full chests, so this is a design/UX flaw, not a correctness bug.

</details>

### 54. Hotbar keyboard input is not gated while modals are open — selection changes under panels
**Where:** `scripts/ui/hotbar.gd:224` | **Category:** bug, found by ui-panels

hotbar._process polls Tab/Shift-Tab/number keys every frame and only suppresses them when the dev console is open. main.gd gates all of ITS gameplay input when a building panel, inventory grid, or map panel is open (main.gd:404), but the hotbar's independent polling path has no equivalent gate. Concrete failure: player is in NEUTRAL mode (required to open a panel), opens a chest panel, presses a number key or Tab while the modal is up — selection silently changes. Because building placement uses Input.is_action_pressed (main.gd:472), the very click-and-hold that dismisses the panel can then immediately place the newly selected building on the tile under the mouse the next frame. The dev-console gate's own comment acknowledges this path needs separate gating, yet only one modal got it.

**Evidence:**
```
if dev_console != null and dev_console.is_open():
    return
if Input.is_action_just_pressed("next_category"):
    _cycle_category(1)
...
    if InputMap.has_action(action) and Input.is_action_just_pressed(action):
        set_selection_in_current(i)
```
**Fix:** In hotbar.gd, add alongside the existing dev_console ref: `var input_blocked: Callable = Callable()` (documented as optional, null/invalid falls through — same test-safe pattern as dev_console and player_inventory). At the top of _process, after the dev-console gate, add: `if input_blocked.is_valid() and input_blocked.call(): return`. In main.gd's _ready (near line 180 where dev_console is wired), set `hotbar.input_blocked = func() -> bool: return inventory_grid.is_open() or map_panel.is_open() or _any_building_panel_open()`. This reuses the exact modal predicate from main.gd:404 without giving hotbar three panel refs, and preserves the ungated fallback for tests/scripted scenes. Optionally extract the predicate into a main.gd helper `_modal_open()` used by both line 404 and the lambda so the two gates cannot drift.

<details><summary>Verification notes</summary>

- Confirmed. hotbar.gd:218-231 polls Input.is_action_just_pressed for next_category/prev_category/hotbar_1..9 every frame in _process, with the only early-return being the dev-console gate at 222-223 (whose comment at 74-78 explicitly says main.gd's gate does not cover this path). No set_process(false), no tree pause (TickSystem.paused only stops the game tick, not node processing), and Input singleton polling is unaffected by GUI focus, so open modals cannot consume these presses. main.gd:404 gates only main's own input; hotbar keeps running. The escalation is also real: panels open only in NEUTRAL mode (main.gd:460-462, requires current_kind()==""); a number key pressed while the panel is up sets a non-neutral selection (hotbar.gd:241-249); building_panel.gd:186-191 (and chest_panel.gd:89-102) close on the LMB *press*, so on the next frame main.gd:404 passes and Input.is_action_pressed("place_tile") at main.gd:472 is still true, firing _try_place with the silently-changed selection — an unintended placement (spending resources) on the tile under the mouse. No test in scripts/tests/ covers hotbar input gating.

</details>

### 55. Drill panel content overflows the default 280px top area and collides with the Inventory label
**Where:** `scripts/ui/drill_panel.gd:180` | **Category:** bug, found by ui-panels

DrillPanel does not override _top_area_height(), so it inherits PANEL_TOP_AREA_H_DEFAULT = 280 (building_panel.gd:89). Its own layout math exceeds that: output row at area.y+162, fuel slot spanning area.y+240..288 (past 280), and the status baseline at fuel_row_y + 48 + 18 = area.y+306. The player-grid "Inventory" header renders at grid.y - 8 = area.y+308 (grid.y = area bottom + 36). The status string (e.g. the long "Status: NO FUEL — feed wood, coal, or fuel briquette" at size 15 starting at panel x+40) extends horizontally past the centered "Inventory" label's x (~panel x+220), so the two texts draw on top of each other, 2px apart in baseline. Other panels with tall content (Chest 380, Harvester 380, FastInserter 360) override the hook; the drill was missed.

**Evidence:**
```
var status_y: float = fuel_row_y + FUEL_SLOT_SIZE + 18   # = area.y + 306, but _top_area_height() is the inherited 280
```
**Fix:** In C:/Users/ockla/FACTCLONE/scripts/ui/drill_panel.gd, add an override matching the pattern used by chest_panel.gd/harvester_panel.gd: `func _top_area_height() -> int: return 340` (content extends to status baseline at area.y+306 plus ~15px descent/breathing room; 340 keeps the fuel slot bottom at 288 and status line at 306 comfortably inside the top area, pushing the player grid and its Inventory label below). Add a brief comment noting the layout math (fuel slot bottom 288, status baseline 306) like fast_inserter_panel.gd:45 does.

<details><summary>Verification notes</summary>

- Confirmed. drill_panel.gd never overrides _top_area_height() so it inherits 280 (building_panel.gd:89,94-95). Verified layout math: output_row_y = area.y+162 (drill_panel.gd:54), fuel slot spans area.y+240..288 (lines 57,69), status baseline = area.y+306 (line 180, quoted evidence matches verbatim) — all past the 280px top area. Player grid starts at area.y+316 (building_panel.gd:105,109) with the "Inventory" label baseline at grid.y-8 = area.y+308 (building_panel.gd:492), 2px from the status baseline. Grid is 204px wide centered in the 640px panel, so label x = panel_x+218; the NO_FUEL (line 189) and DEPLETED status strings at size 15 starting at panel_x+40 extend past x=218 and draw through the label. NO_FUEL is trivially reachable (unfueled drill). No clipping or guard exists; the 33/33 passing tests are logic tests that cannot detect draw overlap. Minor caveat: short statuses (Drilling/Idle/Blocked) end before the label's x, so glyph-on-glyph overlap occurs only in NO_FUEL and DEPLETED states.

</details>

### 56. Duplicated player-slot click handlers diverge on the empty-cursor definition
**Where:** `scripts/ui/inventory_grid.gd:122` | **Category:** convention-violation, found by ui-panels

The documented duplication (BuildingPanel._handle_player_slot_click vs inventory_grid._handle_left_click_player) is otherwise line-for-line identical, but the empty-cursor guard differs: BuildingPanel uses `not cursor.has_item()` (item_type >= 0 AND count > 0) while inventory_grid uses `cursor.item_type < 0` only. A cursor with item_type >= 0 and count == 0 is constructible from corrupted/hand-edited save data (e.g. a building buffer entry [5, 0]: _take_from_slot calls cursor.pick(5, 0) without a count guard). In that state BuildingPanel treats the cursor as empty (pick branch) while inventory_grid treats it as full and will write a ghost stack (item_type set, count 0) into an empty slot then clear the cursor. Harmless today, but it is exactly the silent behavioral drift the inlined-duplication comment (building_panel.gd:213-215) promises to avoid.

**Evidence:**
```
inventory_grid.gd: if cursor.item_type < 0:
building_panel.gd:221: if not cursor.has_item():
```
**Fix:** In inventory_grid.gd:122, change `if cursor.item_type < 0:` to `if not cursor.has_item():` so both duplicated handlers share CursorStack's single empty definition. Optionally harden the source of the degenerate state: in CursorStack.pick (cursor_stack.gd:24-26), add `if c <= 0: clear(); return` (safe — all legitimate pick callers pass count > 0), which also protects building_panel's _take_from_slot against zero-count buffer entries from corrupted saves.

<details><summary>Verification notes</summary>

- Confirmed. inventory_grid.gd:122 uses `cursor.item_type < 0` while building_panel.gd:221 uses `not cursor.has_item()` (item_type >= 0 AND count > 0, cursor_stack.gd:21-22), despite building_panel.gd:213-215 promising "Same semantics as inventory_grid._handle_left_click_player". The degenerate cursor (type set, count 0) is reachable exactly as claimed: building state loads unsanitized (save_system.gd:466 -> building.gd:27-31), and _take_from_slot's input/output branch (building_panel.gd:365-368) checks only buf.is_empty() before cursor.pick(type, count) with no count guard (pick itself has none, cursor_stack.gd:24-26). CursorStack.from_dict sanitizes only the cursor field, not building buffers. In that state the two handlers diverge: building_panel picks, inventory_grid places a ghost stack (item_type set, count 0) into an empty slot and clears the cursor. Impact is benign (ItemStack.is_empty() treats count<=0 as empty, item_stack.gd:13-14) and requires a hand-edited/corrupted save, so severity stays low — but the behavioral drift between documented-identical duplicates is real.

</details>

### 57. Chest capacity display hardcodes 2400 instead of Chest.TOTAL_CAPACITY
**Where:** `scripts/ui/chest_panel.gd:56` | **Category:** doc-drift, found by ui-panels

The capacity header formats the literal 2400 with only a comment pointing at Chest.TOTAL_CAPACITY, while the actual accept/reject logic in the same file uses Chest.free_capacity (which reads the real constant). If TOTAL_CAPACITY is ever tuned (it is explicitly documented in chest.gd as derived from the old 24x100 model, i.e. a tunable), the panel will display the stale number: e.g. with TOTAL_CAPACITY lowered to 1200, the header reads "Capacity: 1200 / 2400" while deposits are rejected with "Chest full" — the UI and the enforcement contradict each other.

**Evidence:**
```
var cap_text: String = "Capacity: %d / %d" % [total, 2400]   # Chest.TOTAL_CAPACITY
```
**Fix:** In scripts/ui/chest_panel.gd line 56, replace the literal with the constant: var cap_text: String = "Capacity: %d / %d" % [total, Chest.TOTAL_CAPACITY] (drop the now-redundant comment). Optionally, in the same spirit, buildings.gd:181 ("max_stack": 2400) should reference Chest.TOTAL_CAPACITY too, though that is outside this finding's scope.

<details><summary>Verification notes</summary>

- Confirmed. chest_panel.gd:56 formats the literal 2400 (constant named only in a trailing comment), while deposit enforcement in the same file (lines 151-152) uses Chest.free_capacity, which derives from Chest.TOTAL_CAPACITY (chest.gd:18, 71-72). chest.gd:129 shows the project's own display code uses the constant, so line 56 is an inconsistent hardcode. No guard keeps them in sync; tuning TOTAL_CAPACITY would produce the claimed UI/enforcement contradiction. Currently benign (both 2400, 33/33 tests pass), hence low severity. Related hardcodes also exist at buildings.gd:181 and test_building_ui_2.gd:32.

</details>

### 58. Leftover unconditional close_info_panel handler clears the info panel on the same Esc press that closed a modal via the priority chain
**Where:** `scripts/main.gd:489` | **Category:** bug, found by main-console

The Esc priority chain at main.gd:379-390 already handles info_panel.clear_target() as step 4. But lines 489-490 contain a second, unconditional handler for the same action further down _process. When Esc closes the inventory grid or a building panel via the chain (step 1/2), the modal-open early-return at line 404 no longer fires (the modal just closed), execution reaches line 489, and Input.is_action_just_pressed("close_info_panel") is still true for this frame — so the info panel target is also cleared. Scenario: player Q-inspects a smelter (info panel showing), opens the inventory grid with I, presses Esc to close the grid → the grid closes AND the inspected-building panel vanishes, requiring a re-inspect. The chain was designed for exactly one action per press.

**Evidence:**
```
main.gd:489-490: 'if Input.is_action_just_pressed("close_info_panel"):\n\t\tinfo_panel.clear_target()' — duplicating chain step 4 at main.gd:386-387 ('elif info_panel.has_target(): info_panel.clear_target()').
```
**Fix:** Delete lines 489-490 of scripts/main.gd (the `if Input.is_action_just_pressed("close_info_panel"): info_panel.clear_target()` block after _try_inspect). The Esc priority chain at 379-390 already owns info-panel clearing as step 4, preserving one-action-per-press semantics. No other changes needed; the chain's step 4 covers every legitimate case the deleted block handled.

<details><summary>Verification notes</summary>

- Confirmed. main.gd:489-490 duplicates chain step 4 (386-387). The modal-open early-return at 404 is evaluated AFTER the chain closes a modal (steps 1-3, lines 380-385), so on the same Esc frame it is false and execution reaches 489, where is_action_just_pressed("close_info_panel") is still true for the whole frame — clearing the info panel target set by _try_inspect (837-854). No guard exists: inventory/map toggles (367-371) don't clear the target, and info_panel.gd's _process auto-clear (93-121) only fires when the target entity itself disappears. The scenario (inspect building, open grid with I, Esc closes grid AND wipes the info panel) is reachable. Lines 489-490 are otherwise a pure no-op since chain step 4 already handled the no-modal case, so deletion is safe.

</details>

### 59. Backtick opens the dev console but cannot close it: the focused LineEdit consumes the key before _unhandled_input
**Where:** `scripts/main.gd:571` | **Category:** bug, found by main-console

The console toggle lives in Main._unhandled_input. While the console is open its LineEdit holds focus (console.gd:266-268 re-grabs focus every frame), and a focused LineEdit consumes printable key events at the GUI dispatch stage — so _unhandled_input never receives the backtick and the toggle branch is unreachable in the open state. Pressing ` while the console is open types a literal '`' character into the command field instead of closing the console; the only close paths are Esc and clicking nothing. This contradicts both the code comment ('Backtick (`/~ key) toggles') and standard dev-console UX, and litters commands with stray backticks when the player expects toggle behavior.

**Evidence:**
```
main.gd:570-574: 'if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:\n\t\tif event.keycode == KEY_QUOTELEFT:   # backtick\n\t\t\tif dev_console != null:\n\t\t\t\tdev_console.toggle()' — inside _unhandled_input, which focused-LineEdit key consumption prevents from running while the console is open.
```
**Fix:** In DevConsole._input (console.gd:158-182), add a KEY_QUOTELEFT case to the existing match: call _close() and get_viewport().set_input_as_handled(), mirroring the KEY_ESCAPE branch. Since _input runs before GUI dispatch, this both closes the console and prevents the literal '`' from being inserted into the LineEdit. Keep the main.gd:570-574 branch unchanged for the open direction (and it remains harmless as a fallback). Optionally extend test_console.gd with a routing test feeding a QUOTELEFT InputEventKey through _input while open to assert visible becomes false.

<details><summary>Verification notes</summary>

- Confirmed. main.gd:570-574 handles KEY_QUOTELEFT only in _unhandled_input; DevConsole._input (console.gd:158-182) intercepts Enter/Tab/Up/Down/Escape but not backtick, and console.gd:266-268 re-grabs LineEdit focus every frame while visible. In Godot's pipeline the focused LineEdit consumes the printable backtick at GUI dispatch (inserting a literal '`') before _unhandled_input runs, so the close direction of the toggle is unreachable — contradicting the comments at main.gd:566 and console.gd:7 that promise toggle behavior. Grep shows no other KEY_QUOTELEFT / _shortcut_input / _unhandled_key_input handler that could rescue it, and test_console.gd only tests execute(), not input routing.

</details>

### 60. F11 demo writes water tiles directly into grid_world.tiles, bypassing tile_modifications — demo terrain silently reverts on save/load
**Where:** `scripts/main.gd:1177` | **Category:** bug, found by main-console

_spawn_demo_chain sets base terrain via 'grid_world.tiles[pos] = Tile.new(base, Terrain.Overlay.NONE)' without recording an entry in grid_world.tile_modifications. SaveSystem.save_game persists only tile_modifications (save_system.gd:224-227) and rebuilds everything else from the seed, so after F5 + reload the demo's two water tiles revert to canonical procgen terrain while the pumps and pipes (buildings, which do persist) remain. Because _rebuild_fluid_network only checks that a component touches a pump — never that the pump touches water (grid_world.gd:559-560) — the chains keep running with pumps 'drawing water from grass', a silent world-state divergence that undermines the demo's stated purpose as an integration-verification baseline. The direct write also skips set_overlay's resource_state cleanup, so a demo water tile stamped over an ore deposit leaves orphaned richness state behind.

**Evidence:**
```
main.gd:1176-1177: 'if base != -1:\n\t\t\tgrid_world.tiles[pos] = Tile.new(base, Terrain.Overlay.NONE)' — no tile_modifications write, unlike set_overlay which records 'tile_modifications[pos] = Tile.new(...)' (grid_world.gd:330).
```
**Fix:** In _spawn_demo_chain (main.gd:1176-1177), replace the direct write with a path that keeps saves consistent: after `grid_world.tiles[pos] = Tile.new(base, Terrain.Overlay.NONE)`, add `grid_world.tile_modifications[pos] = Tile.new(base, Terrain.Overlay.NONE, ResourceNodes.DEFAULT)` and clear stale resource state: `grid_world.resource_state.erase(pos)` and `grid_world.resource_state_modifications.erase(pos)` (mirrors set_overlay's cleanup at grid_world.gd:304-311 and the load-side sync at save_system.gd:395-396). Better long-term: add a `GridWorld.set_base(pos, base)` helper that does all four steps (tiles write, tile_modifications record, resource_state + resource_state_modifications cleanup) per the invariant documented at grid_world.gd:26-34, and call it from the demo. Optionally cover with a test: run _spawn_demo_chain equivalent placement, save+load, assert base_at(water_pos) == Terrain.Base.WATER.

<details><summary>Verification notes</summary>

- Confirmed. main.gd:1176-1177 writes grid_world.tiles[pos] directly with no tile_modifications entry, and the water plan entry (main.gd:1145) has overlay=-1 so the set_overlay path (grid_world.gd:330, which does record modifications) never runs for it. SaveSystem persists only tile_modifications (save_system.gd:221-227) and load regenerates from seed (save_system.gd:381-394, world_generator.gd:216 clears tiles), so the demo water tile reverts on reload. Buildings reload without re-validation (save_system.gd:466-467 uses Building.from_dict directly; Pump.is_valid_placement only runs in place_building at grid_world.gd:403), and _rebuild_fluid_network (grid_world.gd:542-561) checks only pump presence, never water adjacency — so chains keep running against grass, exactly the claimed silent divergence. Also violates the stated invariant at grid_world.gd:34 that tile mutations must go through helpers that update tile_modifications. No test in scripts/tests/ covers the demo path. Severity low is correct: debug-only F11 feature, affects only devs saving/loading a demo world.

</details>

### 61. on_impassable escape valve grants unrestricted movement: a player standing on water can walk across the entire lake
**Where:** `scripts/player.gd:82` | **Category:** design-flaw, found by main-console

_move_with_passability allows the full movement delta whenever the player's current tile is impassable, with no requirement that the move heads toward passable ground. The valve is meant to let a mis-placed player 'walk off' (comment: 'allow free movement off it'), but as written the player can move deeper into water indefinitely — while on any water tile, every neighboring water tile is a legal destination, so water stops being a barrier entirely. Reachable states: the extreme-seed spawn fallback drops the player at (0,0) 'on water' (main.gd:318-322), and the dev console's tp command teleports onto water freely; from either, the player can tour the whole ocean, cross to otherwise-unreachable landmasses, and bypass all terrain gating rather than just escaping.

**Evidence:**
```
player.gd:73 'var on_impassable: bool = not grid_world.is_passable_at(current_tile)' then player.gd:82-84: 'if on_impassable or grid_world.is_passable_at(target_tile) or target_tile == current_tile:\n\t\tglobal_position = target_pos\n\t\treturn' — on_impassable short-circuits all destination checks.
```
**Fix:** In _move_with_passability, replace the bare `on_impassable or ...` disjunct at player.gd:82 with an escape-directed check: when on_impassable, accept the move only if (a) the target tile is passable, (b) target_tile == current_tile, or (c) the target tile's BFS distance to the nearest passable tile is strictly less than the current tile's (compute with a small breadth-first search over tiles, capped at ~8 tiles radius, cache the result per current_tile to avoid per-frame BFS). Simpler and equally acceptable given the low reachability: on detecting on_impassable at the start of _move_with_passability, snap global_position to the nearest passable tile center (same capped BFS) and return — this also fixes the extreme-seed (0,0) spawn in main.gd:322 without touching main.gd. If tp-onto-water is considered a legitimate dev affordance, keep the valve but gate it behind dev_console visibility instead, and add a test in scripts/tests/ covering that a player on water cannot step onto a second water tile.

<details><summary>Verification notes</summary>

- Confirmed. player.gd:73 sets on_impassable from the current tile, and player.gd:82-84 short-circuit ALL destination checks when it is true — the full delta is applied regardless of where it leads. The check re-runs each frame on the new tile, so while on water every neighboring water tile stays legal: the valve permits unrestricted water traversal, not just escape. Both claimed entry states are reachable: main.gd:311-322 falls back to spawning at (0,0) on water when no passable tile is in the spawn radius (its comment even cites this valve), and console.gd:498-511 (_cmd_tp) teleports with only a bounds check, no passability check. No guard, snap, or directional constraint exists anywhere else on the movement path (_move_with_passability at player.gd:68-99 is the sole path when grid_world is wired), and no test in scripts/tests/ covers the on-impassable case. Severity stays low: the state is unreachable in normal play (safe-spawn succeeds, water blocks entry), so only extreme seeds and the dev tool expose it.

</details>

### 62. tick_speed reports the new multiplier as the old one — 'was' value read after assignment
**Where:** `scripts/ui/console.gd:708` | **Category:** bug, found by main-console

_cmd_tick_speed assigns TickSystem.tick_rate_multiplier = m and then formats the confirmation string using TickSystem.tick_rate_multiplier for the '(was %.2fx)' placeholder — which now already holds the new value. The command always prints e.g. 'Tick speed → 4.00x (was 4.00x)', so the one piece of information the message exists to convey (what the multiplier changed from, useful when restoring normal speed after a fast-forward test) is never shown.

**Evidence:**
```
console.gd:707-708: 'TickSystem.tick_rate_multiplier = m\n\treturn "Tick speed → %.2f× (was %.2fx)." % [m, TickSystem.tick_rate_multiplier]'.
```
**Fix:** In _cmd_tick_speed (scripts/ui/console.gd), before line 707 add `var old: float = TickSystem.tick_rate_multiplier`, then after the assignment return `"Tick speed → %.2f× (was %.2f×)." % [m, old]`. (Optionally also unify the mixed '×'/'x' glyphs in the same string while touching it.)

<details><summary>Verification notes</summary>

- Confirmed. console.gd:707 assigns TickSystem.tick_rate_multiplier = m, then line 708 formats the '(was %.2fx)' placeholder from TickSystem.tick_rate_multiplier, which already holds m. tick_rate_multiplier is a plain field (tick_system.gd:31) with no setter/clamp that could preserve or transform the old value, so the message always echoes the new multiplier twice. test_console.gd:107-108 only asserts the stored value, not the message string, so the passing suite doesn't cover this. Cosmetic-output bug only: the multiplier is set correctly; only the informational 'was' value is wrong.

</details>

### 63. Runner restores neither SaveSystem.save_path nor tick_rate_multiplier between tests
**Where:** `scripts/tests/test_runner.gd:64` | **Category:** design-flaw, found by test-quality

Per-test isolation resets current_tick and disconnects tick listeners, but two pieces of global mutable state are left to each test's own discipline: SaveSystem.save_path (overridden by 10 suites, each of which must restore it on every exit path — the pattern is duplicated ~10 times across _fail/_cleanup helpers) and TickSystem.tick_rate_multiplier (mutated by test_console, restored by a trailing execute call). The runner's own comment (lines 67-68) admits a hard error inside a test cannot be caught; such an abort mid-suite would strand save_path on a test file for any suites that DO use the default path, and there is no central guarantee. One missed restore in a future test silently redirects later suites' save I/O.

**Evidence:**
```
test_runner.gd:62-65 resets only current_tick and tick connections: "# Per-test isolation: reset tick counter and clear any tick listeners"; contrast test_save_load_roundtrip.gd:37-38 / test_smelter.gd:189-190 etc., which each privately snapshot and restore SaveSystem.save_path.
```
**Fix:** In test_runner.gd _ready loop, immediately before `result = test_class.run(self)` (line 69), snapshot `var orig_save_path: String = SaveSystem.save_path` and `var orig_rate: float = TickSystem.tick_rate_multiplier`; immediately after the run (before the pass/fail accounting), assign both back. Optionally also re-assert `TickSystem.paused = true`. Keep the existing per-suite restores as redundant defense; no test changes required. Do not rely on this to survive hard errors — those abort the runner loop entirely and are already loud.

<details><summary>Verification notes</summary>

- Core claim confirmed: test_runner.gd:62-65 restores only current_tick and tick connections; SaveSystem.save_path (static var, save_system.gd:127) is snapshotted/restored privately by 12 suites, several on 2-3 exit paths each (e.g. test_mining_drill.gd:202,259; test_save_load_roundtrip.gd:238,283), and TickSystem.tick_rate_multiplier is restored only by a trailing execute in test_console.gd:110. No central guarantee exists. However the scariest prong is wrong: a GDScript hard error aborts the runner's own _ready loop, so later suites never run with a stranded path (loud failure, not silent corruption), save_path resets each process start, and all 12 SaveSystem-using suites currently override save_path before I/O, so no suite depends on the default. No CONVENTIONS.md rule mandates central restoration. Real as a latent design-flaw/hardening gap, but no reachable failure today and the severity is overstated.

</details>

**Correction 2026-08-23 — "loud failure, not silent corruption" was false, and that half
is now fixed (#63 itself stays LIVE).** The verification note above rests on a hard
error aborting the runner being obvious. It was not. Measured: a suite whose `run()`
returns null — which is what an UNDECLARED return type does when a runtime error
unwinds it — made `var result: Dictionary = test_class.run(self)` raise on the
ASSIGNMENT, aborting `_ready` itself. Result: **`exit=124`, nine PASS lines, no
summary, no `get_tree().quit()`** — the process simply sat there until the CI timeout
killed it. That is the same signature as the compile-error hang this project has
already been bitten by, and it is indistinguishable from a genuine hang.

Worth noting the two shapes differ, which is why this went unnoticed: a suite declaring
`-> Dictionary` (all 54 do today) unwinds to `{}`, not null, so it reads as an ordinary
FAIL and costs one suite. Only the undeclared-return shape hangs — but nothing enforces
the annotation.

Fixed: the runner now takes the result into an untyped local, scrubs, and checks the
shape, reporting `ERROR <name> — run() returned Nil instead of a result Dictionary`.
Re-measured against the same reproduction: `exit=1`, `53 passed, 1 failed`, summary
printed. This also closes the gap the fixture scrub had — it sat between `run()` and
the pass/fail branch, so it covered PASS and FAIL but not ERROR, which bounded the
"a suite cannot forget to opt in" guarantee that scrub is built on.

**#63's actual subject — `save_path` and `tick_rate_multiplier` not being restored
centrally — is untouched and remains LIVE.** What changed is only that its stated
reason for being low-risk no longer holds.

### 64. Hotbar category cycling, disabled-slot logic, map panel, and minimap have zero coverage
**Where:** `scripts/tests/test_runner.gd:14` | **Category:** test-gap, found by test-quality

PROJECT_LOG names 'Hotbar categories' (Pre-Session-B) and 'Exploration UI — M-key fullscreen map + minimap + fog-of-war' as shipped features. test_building_ui covers only the selection sentinel (has_selection/clear_selection/current_kind); hotbar._cycle_category (hotbar.gd:233) and _is_slot_disabled (hotbar.gd:330) are never called by a test. test_zoom_trigger_map deliberately tests only the pure _compute_zoom_action helper, and test_region_visibility tests the visibility model — map_panel.gd and minimap.gd themselves (toggle wiring, region rendering source data) have no test. A regression in category cycling order or in the disabled-slot predicate (which gates what the player can place) would ship undetected.

**Evidence:**
```
hotbar.gd:233 `func _cycle_category(delta: int)` and :330 `func _is_slot_disabled(slot: Dictionary)` have no references anywhere under scripts/tests/; test_zoom_trigger_map.gd:5-8: "Exercises the pure-static `_compute_zoom_action` ... Modal toggle is reported as a flag".
```
**Fix:** In test_building_ui.gd's hotbar section (after line 105): call hotbar._cycle_category(1) categories.size() times asserting current_category returns to its start (wrap-around) and that current_kind() differs across at least two categories; same with delta -1. For _is_slot_disabled, note it returns false when player_inventory == null — assign a stub object exposing total_of(item_type) (0 for one item, >0 for another) to hotbar.player_inventory, then assert _is_slot_disabled on an {"kind": "item_apply", "value": ...} slot is true at 0 and false otherwise, and that a "building"-kind slot is never disabled. Drop the claim's framing that the predicate gates placement — it is a dim-only affordance. Optionally add a map_panel smoke test (preload, add_child, toggle(), assert visible flag flips) mirroring the panel pattern at test_building_ui.gd:93-94; minimap can piggyback on the same pattern.

<details><summary>Verification notes</summary>

- Test gap confirmed: project-wide grep for _cycle_category/_is_slot_disabled hits only hotbar.gd (defs at 233/330, callers at 225-227/374) and PROJECT_LOG.md:567 — zero references under scripts/tests/. test_building_ui.gd:93-106 exercises only the selection API (has_selection/current_kind/clear_selection/set_selection_in_current), never cycling or the disabled predicate. test_zoom_trigger_map.gd:5-8 matches the quote verbatim (pure _compute_zoom_action only), and map_panel.gd/minimap.gd appear in scripts/tests/ only inside a comment — no test instantiates either. PROJECT_LOG.md:2438 (Hotbar categories) and :1836 (Exploration UI) confirm both shipped. However, the claimed impact is overstated: hotbar.gd:323-326's doc comment states _is_slot_disabled is visual dimming ONLY — placement validity is checked at click-time with a toast, so it does NOT gate what the player can place; it also returns false whenever player_inventory is null (the test context), so a test needs an inventory stub. _cycle_category is 3 lines of well-known modular arithmetic. No CONVENTIONS.md rule mandates test coverage outside save migrations (line 109). Real but low-impact gap.

</details>

### 65. Cursor backward-compat check is a tautology that cannot fail
**Where:** `scripts/tests/test_building_ui.gd:279` | **Category:** test-gap, found by test-quality

The 'backward-compat: old save without cursor key' check constructs a local dict without a cursor key, evaluates `if bare_progression.has("cursor")` (always false), so from_dict is never called, and then asserts a freshly constructed, untouched CursorStack is empty. Every line involved lives in the test; main.gd's real cursor-restoration path (reading progression["cursor"] on load) is not invoked. The assertion can never fail regardless of production behavior, so it documents intent while verifying nothing.

**Evidence:**
```
Lines 276-281: `var bare_progression: Dictionary = {"bags_consumed": 5}` ... `if bare_progression.has("cursor"): fresh_cursor.from_dict(...)` ... `_check(failures, not fresh_cursor.has_item(), "backward-compat: progression without cursor key should leave cursor empty")`.
```
**Fix:** In the first half of the same test (which already does a real SaveSystem round-trip at lines 244-272), add a second round-trip: save with progression = {"bags_consumed": 5} (no "cursor" key), call SaveSystem.load_game, and assert `not result.player_progression.has("cursor")` — proving the save/load pipeline does not synthesize the key, which is the actual precondition main.gd:262-265 relies on. Then delete the tautological block at 274-281 (its from_dict-on-missing-keys behavior is already covered by c4 at lines 55-57). Optionally extend the loaded_cursor mirror at 267-268 to include main.gd's `is Dictionary` guard so the mirror matches main.gd:264 exactly; full end-to-end coverage of main.gd's _load restoration would require instantiating main.gd, which this suite intentionally avoids.

<details><summary>Verification notes</summary>

- Confirmed. test_building_ui.gd:276-281 matches the quote: local dict {"bags_consumed": 5} makes has("cursor") statically false, the from_dict call at 279 is dead, and line 280 asserts emptiness of an untouched CursorStack.new() from line 277 — a property already covered by c4.from_dict({}) at lines 55-57. The real restoration path (main.gd:262-265, which additionally guards `loaded["cursor"] is Dictionary` — a guard the test mirror omits) is never exercised; the file deliberately avoids instantiating main.gd (comment at lines 295-296). Grep of scripts/tests/ shows no other test (including all test_save*.gd migration suites, zero cursor hits) covers loading a save whose progression lacks the cursor key. Only nuance: the assert would fail if CursorStack.new() defaulted non-empty, so it is not a 100% literal tautology, but that adds zero marginal coverage.

</details>

### 66. 'Random seed' uniqueness phase tests seeds fabricated inside the test, not the game's randomization
**Where:** `scripts/tests/test_random_seed_save_roundtrip.gd:25` | **Category:** test-gap, found by test-quality

The first phase generates ten seeds via `Time.get_ticks_usec() + i * 1000` inside the test and asserts they are unique — an assertion about the test's own arithmetic (guaranteed unique by the +i*1000 spacing). The game's actual fresh-start seed randomization in main.gd is never called, so if it regressed to always producing seed 0, this suite still passes. The save/load round-trip half of the test is sound; the uniqueness half provides no protection for the feature its name implies ('random seed at fresh start').

**Evidence:**
```
Lines 21-25: "# Generate ten \"random\" seeds and ensure they're not all identical. # (Pseudo-random via Time + index; just needs to vary.)" `seeds.append(int(Time.get_ticks_usec() + i * 1000) & 0x7FFFFFFF)`.
```
**Fix:** Extract just the seed-pick from main.gd's `_generate_fresh_world()` into a side-effect-free static helper (e.g. `static func new_world_seed() -> int: return randi() & 0x7FFFFFFF` on WorldGenerator, since _generate_fresh_world itself has heavy side effects — generate(), camera, spawn), have main.gd line 300 call it, then replace the test's lines 21-29 Time arithmetic with 10 calls to that helper asserting >1 unique value (not all 10 — randi() collisions in 10 draws are astronomically unlikely but asserting mere variation is the honest contract). Keep the round-trip half unchanged.

<details><summary>Verification notes</summary>

- Confirmed. test_random_seed_save_roundtrip.gd lines 21-29 fabricate seeds via `Time.get_ticks_usec() + i * 1000` — since ticks_usec is monotonically non-decreasing across the loop and each index adds a distinct +i*1000 offset, the 10 values are unique by construction; the assertion at line 28 can effectively never fire and exercises no game code. The game's real fresh-start randomization is `grid_world.world_seed = randi()` in main.gd line 300 inside `_generate_fresh_world()`. Grep of scripts/tests/ shows no test calls `_generate_fresh_world`, `randi`, or any seed-generation helper — the only hits for "randomized" are this test's own comment and failure string. So a regression where fresh worlds always got seed 0 (or a constant) would pass 33/33. The round-trip half (lines 31-73) is genuinely sound and unaffected. No `randomize()` call exists anywhere in scripts/ (Godot 4 auto-seeds the global RNG, so that itself is not a bug), but nothing tests seed variation.

</details>

### 67. Round-trip suite still titled and documented as locking the v14 schema; save is v18
**Where:** `scripts/tests/test_save_load_roundtrip.gd:31` | **Category:** doc-drift, found by test-quality

SaveSystem.SAVE_VERSION is 18 (save_system.gd:121) and this suite actually saves/loads v18 data, but test_name() returns 'save/load round-trip (v14)', the header comment says 'locks the v14 schema', and the success message claims 'v14 round-trip preserves ...'. CI output therefore reports a v14 lock four schema versions after the fact, and the docstring's field inventory stops at v14, obscuring that soil/fertilizer/wasteland fields are intentionally covered by other suites rather than forgotten here.

**Evidence:**
```
Line 3: "## Save/load round-trip test — locks the v14 schema."; line 31: `return "save/load round-trip (v14)"`; line 241 success message begins "v14 round-trip preserves seed, ..." — versus save_system.gd:121 `const SAVE_VERSION: int = 18`.
```
**Fix:** In scripts/tests/test_save_load_roundtrip.gd: (1) change line 31 to derive the label from the constant — return "save/load round-trip (v%d)" % SaveSystem.SAVE_VERSION — so it can never drift again; (2) update the line 241 success message to drop the hardcoded "v14" (e.g. "round-trip preserves seed, ..."); (3) amend the header docstring (line 3) to say it locks the current save schema, and add one line noting that v15-v18 fields (soil/fertilizer/wasteland, migration paths) are covered by test_fertilizer_chain.gd and test_save_migration.gd rather than this suite.

<details><summary>Verification notes</summary>

- Confirmed doc-drift. test_save_load_roundtrip.gd line 3 ("locks the v14 schema"), line 31 ("save/load round-trip (v14)"), and line 241 ("v14 round-trip preserves ...") all claim v14, while the suite exercises the live SaveSystem (save_game at line 130, load_game at line 142) whose SAVE_VERSION is 18 (scripts/systems/save_system.gd:121 — note actual path is scripts/systems/, not scripts/ as the reviewer cited). The docstring changelog (lines 5-8) stops at v14. Sibling suites label current versions (test_fertilizer_chain "save v17", test_save_migration "v17→v18"), so the stale label is drift, not an intentional frozen-name convention. Purely cosmetic; no functional impact and 33/33 passes are unaffected.

</details>

### 68. Spot-check comment pins seed-42 output to WorldGenerator VERSION 3; generator is at VERSION 4
**Where:** `scripts/tests/test_worldgen_determinism.gd:77` | **Category:** doc-drift, found by test-quality

The spot-check block documents its coordinates as 'locking the exact procgen output of seed 42 at WorldGenerator.VERSION = 3' and promises 'If WorldGenerator changes, these will fail FIRST and force a VERSION bump.' world_generator.gd:31 is now `const VERSION: int = 4` (fallback-lake inner-exclusion). The v3->v4 bump happened without updating or re-verifying this anchor comment, so the tripwire's own provenance is stale — a reader auditing determinism cannot tell whether the three spot values were re-captured for v4 or merely happen to still pass.

**Evidence:**
```
Lines 76-79: "Coordinates and content captured from the worldgen-stage1 smoke output for seed 42 — locking the exact procgen output of seed 42 at WorldGenerator.VERSION = 3." vs world_generator.gd:31: `const VERSION: int = 4   # ... v4 = fallback-lake inner-exclusion`.
```
**Fix:** Re-run the seed-42 generation under VERSION 4 and confirm the three spot tiles ((0,0) grass, (45,45) water, (3,46) tree) still classify as expected, then update both comment references (lines 77 and 82 of scripts/tests/test_worldgen_determinism.gd) to "VERSION = 4". Optionally add a hard tripwire so the drift cannot recur silently: assert the generator's VERSION constant equals an EXPECTED_WORLDGEN_VERSION const in the test (e.g. `if WorldGenScript.VERSION != 4: failures.append("spot checks captured for worldgen v4, generator is v%d — re-capture and bump" % WorldGenScript.VERSION)`), and add "update determinism spot-check anchor" to the documented VERSION-bump procedure in PROJECT_LOG/NOTES.

<details><summary>Verification notes</summary>

- Verified: test_worldgen_determinism.gd lines 76-77 and 82 pin spot-check provenance to "WorldGenerator.VERSION = 3", while scripts/world/world_generator.gd:31 (reviewer's path was scripts/world_generator.gd — minor error) is const VERSION: int = 4. Git confirms the drift was accidental: commit 18a0e66 bumped VERSION 3->4 and touched 18 files but not the determinism test (its last change was 7ae12de, when VERSION was 3). The test contains no dynamic reference to the VERSION constant, so no guard mitigates the stale anchor. The suite passing 33/33 shows the three values still hold under v4 but does not refute the claim — it is precisely the "pass without re-captured provenance" ambiguity the reviewer flags, and the v4 change (fallback-lake inner-exclusion affecting water placement) makes the (45,45) water check's stale provenance non-trivial.

</details>

### 69. World freed without disconnecting its TickSystem.tick handler, breaking the suite's own isolation pattern
**Where:** `scripts/tests/test_building_ui_2.gd:145` | **Category:** bug, found by test-quality

At the transition from the chest phase to the oven phase, the test calls `world.queue_free()` directly, omitting the `_disconnect(world)` call used at every other world teardown in the suite (e.g. line 210 `_disconnect(world); world.queue_free()`). Because queue_free is deferred and the entire 33-suite run executes inside one _ready() frame, the discarded world stays connected to TickSystem.tick until the frame ends. Today this test emits no ticks so nothing observable happens, but if a tick-emitting section is ever added after line 145 (the file already imports the tick-driven world pattern), the zombie world's buildings would tick alongside the live one, and the failure would be baffling to diagnose. The runner's per-test _disconnect_all only protects OTHER suites, not later sections of this one.

**Evidence:**
```
Line 145: `world.queue_free()` with no preceding `_disconnect(world)` — contrast line 210 of the same file: `_disconnect(world); world.queue_free()` and the identical paired pattern in every other suite.
```
**Fix:** In scripts/tests/test_building_ui_2.gd, change line 145 from `world.queue_free()` to `_disconnect(world); world.queue_free()`, matching the teardown convention used at lines 91, 152, 197, and 210 of the same file and across all other suites.

<details><summary>Verification notes</summary>

- Confirmed. Line 145 of test_building_ui_2.gd is bare `world.queue_free()` while lines 91, 152, 197, 210 (and every other suite) use `_disconnect(world); world.queue_free()`. GridWorld._ready (grid_world.gd:218) connects TickSystem.tick, queue_free is deferred past the single _ready() frame the whole run executes in, and after the reassignment at line 146 the old world reference is unreachable, so line 210's _disconnect only covers the new world. test_runner.gd:65 `_disconnect_all` only runs before the NEXT suite, so it cannot protect later sections of this file. No ticks are emitted in this file today, so no current failure (matches 33/33), but the teardown-pattern violation and the zombie-connection window within the test are both concretely real.

</details>

### 70. _place_ambient_trees samples noise for all 262,144 tiles on every world generation, including every save load
**Where:** `scripts/world/world_generator.gd:416` | **Category:** performance, found by perf-scale

Pass 4 walks the full 512x512 world and calls _ambient_density_noise.get_noise_2d plus _hash3_unit for every plains tile. Because procgen rehydration reruns generate() on EVERY save load (loaded worlds are 'reconstructed by regenerating from seed'), this ~262k-iteration, ~500k-native-call pass is paid at every game start and every F9 load — a load-time hitch of hundreds of milliseconds in GDScript that dwarfs the other passes (lakes/patches/forests touch only their bounded areas). The effective spawn probability is at most AMBIENT_BASE_PROBABILITY * 2.0 = 0.4%, so 99.6% of the noise samples are computed only to be discarded by the roll comparison.

**Evidence:**
```
L416-429: `for x in range(WORLD_MIN, WORLD_MAX): for y in range(WORLD_MIN, WORLD_MAX): ... var raw: float = _ambient_density_noise.get_noise_2d(x, y) ... var roll: float = _hash3_unit(seed + SEED_OFFSET_AMBIENT_TREE, x, y); if roll < probability:` — noise sampled before the roll test.
```
**Fix:** In _place_ambient_trees, compute the roll first and early-continue before sampling noise: `var roll := _hash3_unit(seed + SEED_OFFSET_AMBIENT_TREE, x, y); if roll >= MAX_AMBIENT_PROBABILITY: continue` where `const MAX_AMBIENT_PROBABILITY := AMBIENT_BASE_PROBABILITY * 2.0`. Two cautions: (1) output identity requires get_noise_2d <= 1.0 strictly; Godot FastNoiseLite fractal bounding keeps Perlin FBM ~within [-1,1] but it is not a hard documented guarantee with fractal_octaves=2, so use a small safety margin (e.g. threshold AMBIENT_BASE_PROBABILITY * 2.05 — still skips ~99.6% of noise calls). (2) Do NOT rely on test_worldgen_determinism.gd to prove no VERSION bump is needed — it compares two runs of the same code and only spot-checks 3 tiles. Verify with a one-off before/after full-world dump diff (tiles + resource_state) across 2-3 seeds; if identical, no VERSION bump per the L6-29 policy. Note the fix removes the native noise call but not the 262k-iteration loop or hash calls, so expect roughly halved pass time, not 250x.

<details><summary>Verification notes</summary>

- Confirmed. world_generator.gd L416-429 samples _ambient_density_noise.get_noise_2d for every unoccupied tile in the 512x512 world before the roll test; max spawn probability is 0.004 (L132, L425-426) so ~99.6% of samples are discarded. save_system.gd L383 reruns generate() on every load (procgen rehydration, documented L35-65), and main.gd L302 on every new game, so the pass is paid at every start/load; all other passes are bounded (lakes/forests r<=30, 256 region rolls, 60x60 safety net). Minor overstatements: _hash3_unit is GDScript not native, and the fix eliminates only the noise calls (~40-60% of pass time), not 250x total time. Also the suggested verification is inadequate: test_worldgen_determinism.gd compares two runs of the same code (L26-30) and cannot detect output drift vs old saves beyond 3 spot-check tiles.

</details>

### 71. _draw_port_indicators re-resolves recipes and allocates edge-cell arrays for every visible recipe building every frame
**Where:** `scripts/world/buildings.gd:925` | **Category:** performance, found by perf-scale

draw_one runs per visible building per frame (queue_redraw is unconditional), and its post-pass _draw_port_indicators does per-frame work that is constant data: Recipes.get_recipe lookup, then for each declared port a fresh edge_cells Array allocation, and for any-edge fluid inputs a 4-edge scan (all perimeter cells) each calling _fluid_active -> building_at -> is_pipe_in_pump_component. Each active/inactive dot also issues a 16-segment draw_arc. At overview zoom (~70x40 tiles visible) a dense factory can have several hundred recipe buildings on screen: ~300 buildings x ~4-8 array allocations + probes = ~2k allocations and ~10k dict lookups per frame (120k+/sec) spent redrawing indicators whose state changes at most once per tick, not per frame.

**Evidence:**
```
L925-973: `static func _draw_port_indicators(...)` ... `var recipe: Dictionary = Recipes.get_recipe(b.state["recipe_id"])` ... `for cell in edge_cells(b.type, b.anchor, dir):` (per port, per frame) ... `else: for d in 4: for cell in edge_cells(b.type, b.anchor, d): if _fluid_active(canvas, cell):`
```
**Fix:** Cache the resolved port list per building (array of {world_dir, cells, color, kind}) computed on place/rotate/recipe-change and invalidated by those events only, so the per-frame path reduces to active-probe + draw. Additionally gate _draw_port_indicators on a tile_size/zoom threshold (e.g. skip when tile pixel size < ~8px), since dots with _PORT_RADIUS 4.0 are sub-pixel noise at overview zoom — this eliminates the cost exactly where visible-building counts peak. The active-probes (_solid_input_active/_fluid_active) must stay per-frame or move to per-tick, since neighbor state changes at tick rate; a per-tick cached active flag on the Building would also remove the per-frame dict probes.

<details><summary>Verification notes</summary>

- Confirmed end-to-end: grid_world.gd L1024 queue_redraw() runs unconditionally every _process frame; L1475-1484 calls Buildings.draw_one for every viewport-visible building; buildings.gd L892 unconditionally invokes _draw_port_indicators, which per frame does a Recipes.get_recipe lookup (L928), allocates a fresh Array in edge_cells per declared port (L681-699), scans all 4 edges calling _fluid_active->building_at->fluid probe for any-edge fluid inputs (L970-973, L1026+), and issues a 16-segment draw_arc per dot (L990-992). No cache, dirty-flag, or zoom guard exists anywhere on this path (L985-987 comment confirms low-zoom behavior is an acknowledged open item). The redundant-per-frame-work mechanism is real; only the reviewer's ~300-building magnitude estimate is speculative, and get_recipe is a cheap dict-reference lookup rather than a true re-resolution, which keeps this a constant-factor churn issue, not a correctness or algorithmic defect.

</details>

### 72. _is_tile_actively_farmed scans all buildings per call and is invoked every frame by the open info panel
**Where:** `scripts/world/grid_world.gd:1182` | **Category:** performance, found by perf-scale

tile_soil_activity -> _is_tile_actively_farmed iterates the entire buildings dict to find planters within Chebyshev distance 1 of the queried tile. InfoPanel._process queue_redraws every frame while a target is set, and its tile-target draw path calls world.tile_soil_activity (info_panel.gd:229), so with Q-inspect open on a tile in a 10k-building factory this is 10k dict iterations x 60fps = 600k iterations/sec for a single status label. The relevant planters can only be at the 9 cells around pos, which the `occupied` map answers in O(9).

**Evidence:**
```
L1182-1192: `func _is_tile_actively_farmed(pos: Vector2i) -> bool: for anchor in buildings: var b: Building = buildings[anchor] if b == null or b.type != Buildings.Type.PLANTER: continue ... if abs(pos.x - b.anchor.x) <= 1 and abs(pos.y - b.anchor.y) <= 1: return true`
```
**Fix:** Rewrite `_is_tile_actively_farmed` (grid_world.gd:1182) to invert the query: for dx in -1..1, for dy in -1..1, let `cell = pos + Vector2i(dx, dy)`; `var b: Building = building_at(cell)`; return true if `b != null and b.type == Buildings.Type.PLANTER and b.anchor == cell and Planter.is_active(b)`. `building_at` is already null-safe (grid_world.gd:372-373). The `b.anchor == cell` check is technically redundant for a 1x1 footprint but guards the semantics if planter size ever changes; keep it or drop it with a comment. Also update the docstring at L1179 which currently claims "O(planters) scan". Semantics are identical, so the existing 33/33 suite should still pass; optionally add a scripts/tests case asserting ACTIVE_FARMING for each of the 9 cells around an active planter and REGENERATING for a modified tile at Chebyshev distance 2.

<details><summary>Verification notes</summary>

- Confirmed. grid_world.gd:1182-1192 iterates the full `buildings` dict per call, filtering to PLANTER inside the loop (so cost is O(all buildings), not O(planters), despite the comment at L1179). Call chain verified: info_panel.gd:93-122 `_process` calls `queue_redraw()` unconditionally every frame while a TILE target is set (TILE has no auto-close, L116-121), `_draw` -> `_draw_tile` (L131, 190) -> `_draw_soil_footer` (L215) -> `world.tile_soil_activity(target_anchor)` (L229) -> `_is_tile_actively_farmed` (grid_world.gd:1174). Only partial mitigation: tile_soil_activity L1172 returns early for tiles absent from `tile_soil_modifications`, so the scan runs only when inspecting a modified (farmed/regenerating) tile — but that is exactly the claimed scenario, so it is reachable. Fix semantics verified: planter footprint is 1x1 (buildings.gd:88) and `building_at` (grid_world.gd:371-374) is a null-safe O(1) occupied-map lookup, so the 9-cell inversion is equivalent. Severity stays low: per-frame cost on one UI path, no correctness impact.

</details>

### 73. _all_building_panels allocates a fresh 22-element Array at least twice per frame
**Where:** `scripts/main.gd:860` | **Category:** performance, found by perf-scale

_all_building_panels() constructs a new 22-element Array on every call. _process calls _any_building_panel_open() twice per frame on the common path (minimap visibility at line 353 and the modal gate at line 404), and the Esc handler can add a third — so 2-3 array constructions plus 22 is_open() dynamic calls each, 60x/sec, forever. The identical list is already built once in _ready (local `all_panels`, line 185) and handed to player.building_panels; the panel set never changes at runtime, so the per-frame reconstruction is pure churn. Small in absolute terms but it sits on the every-frame path and is free to eliminate.

**Evidence:**
```
L860-868: `func _all_building_panels() -> Array: return [ building_panel, smelter_panel, ... fast_inserter_panel, ]` — called from `_any_building_panel_open()` (L871-875), invoked at L353 (`minimap.visible = not (... or _any_building_panel_open())`) and L404 (`if inventory_grid.is_open() or map_panel.is_open() or _any_building_panel_open():`).
```
**Fix:** In main.gd, add a member `var _building_panels: Array = []`. In _ready, assign the existing L185-192 list to it (replacing the local `all_panels`) and keep `player.building_panels = _building_panels`. Change _all_building_panels() to `return _building_panels` (or inline the member at the three iteration sites L872, L879 and delete the helper). List order is unchanged, so _close_active_building_panel's first-open-wins behavior is preserved. Optionally, for O(1) checks, maintain an `_open_panel` reference set in the panel open/close paths so _any_building_panel_open() becomes a null-check — but the member-cache alone removes all per-frame allocation and is the low-risk change.

<details><summary>Verification notes</summary>

- Confirmed in scripts/main.gd: _all_building_panels() (L860-868) builds a fresh 22-element array literal per call; _any_building_panel_open() (L871-875) invokes it and is called from _process (L335) at L353 (unconditional, no early return before it) and L404 (common path, skipped only when dev console open per L362-363), plus L382 on Esc and _close_active_building_panel (L879). The identical static list is already built once in _ready (L185-192) and handed to player.building_panels (L199); no cache or guard exists. Pure per-frame allocation churn, no correctness impact — real but minor.

</details>

### 74. Post-tick pass iterates all buildings although only belts have phase-2 logic
**Where:** `scripts/world/grid_world.gd:574` | **Category:** performance, found by perf-scale

_on_tick's second pass dispatches post_tick_one for every building every tick, but Buildings.post_tick_one is a match with a single BELT case — every non-belt building pays a static call + match fall-through 20 times per second for nothing. Belt.post_tick additionally early-returns on 3 of every 4 ticks (is_advance_tick), so in a 10k-building factory with 3k belts, ~185k of the 200k post-tick dispatches per second do zero work. This overhead scales linearly with total building count and sits inside the hot tick loop that the death-spiral risk (tick_system finding) makes precious.

**Evidence:**
```
grid_world.gd L574-575: `for anchor in buildings: Buildings.post_tick_one(buildings[anchor], self)` — buildings.gd L835-838: `static func post_tick_one(b: Building, world: Node2D) -> void: match b.type: Type.BELT: Belt.post_tick(b, world)`
```
**Fix:** Maintain a belt-anchor registry in grid_world.gd (e.g. `var _belt_anchors: Dictionary = {}`, anchor -> Building), inserted in place_building and erased in remove_building when b.type == Buildings.Type.BELT, and rebuilt wherever saves are deserialized (verify the load path goes through place_building; if it populates `buildings` directly, rebuild _belt_anchors there too). Run pass 2 as `for anchor in _belt_anchors: Belt.post_tick(_belt_anchors[anchor], self)`. Determinism is preserved: Godot Dictionaries are insertion-ordered and belt insertion order is a subsequence of building insertion order. Two amendments to the reviewer's suggestion: (1) prefer guarding the pass with `if not Belt.is_advance_tick(): return`-style skip at the top of pass 2 rather than deleting the check inside Belt.post_tick — keep the internal check as well so Belt.post_tick stays safe if called elsewhere; (2) if pass 2 now calls Belt.post_tick directly, either retire Buildings.post_tick_one or leave a comment on it and on the buildings.gd L17 checklist noting that any future building gaining phase-2 logic must also register in the new pass-2 collection, since the belt-specific is_advance_tick hoist would not apply to other types.

<details><summary>Verification notes</summary>

- Every cited fact checks out. grid_world.gd L574-575 does run pass 2 over the entire buildings dict calling Buildings.post_tick_one; buildings.gd L835-838 is a match with the single Type.BELT case (and the file's own checklist at L17 documents post_tick_one as belts-only); belt.gd L64-66 early-returns unless is_advance_tick(), which with TICKS_PER_SLOT = 4 (belt.gd L22, L49-50) fires on 1 of 4 ticks — so the 185k-of-200k wasted-dispatch arithmetic is correct. Grep confirms no belts-only registry exists anywhere in grid_world.gd, so no guard refutes the claim. It is a genuine structural inefficiency in the hot 20 tps loop, but only that: no correctness impact, GDScript enum-match fall-through is cheap per call, and pass 1 (tick_one) must iterate all buildings anyway, so the marginal cost is one extra full iteration plus a trivial static call per building. Real, and correctly rated low.

</details>

### 75. class_name DevConsole lives in console.gd — file name does not match class_name
**Where:** `scripts/ui/console.gd:1` | **Category:** convention-violation, found by conventions-sweep

CONVENTIONS.md ('File names match class_name') requires every file declaring class_name Foo to be named foo.gd. console.gd declares class_name DevConsole; the compliant name is dev_console.gd. This is the only mismatch in the scripts/ tree (all 45 other class_name declarations match their file names), so it stands out as a drift that search/tooling conventions rely on: a grep for dev_console.gd or a file-browser scan for the DevConsole implementation comes up empty. Failure scenario: a future session (or an automated refactor) creates a new dev_console.gd for the DevConsole class, producing a duplicate class_name registration error at parse time.

**Evidence:**
```
scripts/ui/console.gd:1: class_name DevConsole
```
**Fix:** Rename via `git mv scripts/ui/console.gd scripts/ui/dev_console.gd` AND `git mv scripts/ui/console.gd.uid scripts/ui/dev_console.gd.uid` (the .uid sidecar exists and must move with the script to preserve Godot 4.6 UID stability). Then update two load-bearing references: scenes/main.tscn:32 ext_resource path `res://scripts/ui/console.gd` -> `res://scripts/ui/dev_console.gd`, and scripts/tests/test_console.gd:13 preload path likewise. Optionally fix the prose comment at scripts/main.gd:578 ("console.gd's _input"). Do NOT rename the class to Console: DevConsole is load-bearing as the scene node name ($HUD/DevConsole in main.gd:113, main.tscn:299) and documented in hotbar.gd/player.gd comments — the file rename is the smaller, convention-compliant change. Re-run the headless test suite to confirm 33/33 afterward.

<details><summary>Verification notes</summary>

- Confirmed. scripts/ui/console.gd:1 declares `class_name DevConsole`, and CONVENTIONS.md:31-33 explicitly requires "Every file declaring class_name Foo must be named foo.gd (snake_case)". A mechanical scan of all 46 class_name declarations under scripts/ shows console.gd is the only file/class mismatch (45 others match), matching the reviewer's count. No guard prevents the claimed failure: nothing stops a future dev_console.gd from re-registering DevConsole, which Godot rejects at parse time as a duplicate global class name. The rename's blast radius is exactly as claimed: scenes/main.tscn:32 (ext_resource path), scripts/tests/test_console.gd:13 (preload path), plus a comment at scripts/main.gd:578; DevConsole references in main.gd/player.gd/hotbar.gd are node names or comments unaffected by a file rename.

</details>

### 76. Soil-arc section claims migration framework is 'still queued' though it shipped
**Where:** `NOTES.md:142` | **Category:** doc-drift, found by doc-drift

The soil-exhaustion arc section's shipped-list ends with 'migration framework still queued', but the migration framework shipped at session-save-migration (PROJECT_LOG entry dated 2026-05-08; MIGRATIONS registry live at scripts/systems/save_system.gd line 148 with the v17-to-v18 entry). NOTES.md even contradicts itself: its own 'Schema-mismatch UX' section (line 94) says 'Migration framework — SHIPPED'. A reader planning save-schema work from the soil-arc section would wrongly conclude schema bumps still destroy player saves, which changes how cautiously they would approach a bump.

**Evidence:**
```
NOTES.md:142: 'Save schema v14 → v15 → v16 → v17 → v18 ... 4 schema bumps in the arc; migration framework still queued.' vs NOTES.md:94: '### Migration framework — SHIPPED (`session-save-migration`)' and save_system.gd:148-151: 'const MIGRATIONS: Dictionary = { ... 17: "_migrate_v17_to_v18",'
```
**Fix:** In C:/Users/ockla/FACTCLONE/NOTES.md line 142, replace 'migration framework still queued.' with 'migration framework SHIPPED at session-save-migration (v17 → v18 migrates forward; pre-v17 is the breaking-change reset point — see the Schema-mismatch UX section above and CONVENTIONS.md).'

<details><summary>Verification notes</summary>

- Confirmed. NOTES.md:142 says 'migration framework still queued' inside the soil-arc section, directly contradicting NOTES.md:94 ('Migration framework — SHIPPED (session-save-migration)') and the live MIGRATIONS registry at save_system.gd:148-151 (17: "_migrate_v17_to_v18"; header comments at lines 130-147 confirm migration replaced hard-fail). Commit 6aa3b35 also confirms the framework shipped. No alternate reading of 'still queued' survives — it is stale doc-drift from before session-save-migration landed.

</details>

### 77. Stale plan file: inventory grid / chest paired-view shipped and was since superseded by ChestPanel
**Where:** `INVENTORY_UI_PLAN.md:7` | **Category:** doc-drift, found by doc-drift

INVENTORY_UI_PLAN.md is a v10-era session brief ('Save: v10. 9 tests passing.') for the slot-grid inventory and two-way chest transfer. All of it shipped (inventory_grid.gd exists; test_bag_cap.gd, test_chest_paired_view.gd exist), and its centerpiece chest paired-view design was later replaced by ChestPanel at session-building-ui-2 (NOTES.md:335: ChestPanel 'Replaces old inventory_grid paired-view, removed ~150 lines from inventory_grid.gd'). The file now documents a superseded design as if it were the plan of record, at the repo root where it competes with NOTES.md for attention.

**Evidence:**
```
INVENTORY_UI_PLAN.md:7: '- Save: v10. 9 tests passing.' and line 32: 'open BOTH grids side-by-side (chest's bag + player's inventory)' — the design NOTES.md:335 says was replaced: 'chest_panel.gd — bulk-storage 6×4 grid ... Replaces old inventory_grid paired-view'.
```
**Fix:** Delete C:/Users/ockla/FACTCLONE/INVENTORY_UI_PLAN.md (shipped behavior is documented in PROJECT_LOG.md and NOTES.md's Building Interaction UI section). Two dangling references to handle: (1) scripts/world/buildings.gd:987 comment 'INVENTORY_UI_PLAN-style follow-up' — reword to a generic 'plan-file follow-up' or point at NOTES.md; (2) PROJECT_LOG.md:2128 mentions the file but is a historical log entry and should be left as-is. Alternative minimal fix if the team prefers keeping session briefs: prepend a SUPERSEDED banner pointing to chest_panel.gd / NOTES.md and move it out of the repo root.

<details><summary>Verification notes</summary>

- Confirmed. INVENTORY_UI_PLAN.md:7 reads exactly '- Save: v10. 9 tests passing.' (repo is now save v18, 33/33 tests) and line 32/52 lock the chest paired-view design. Everything shipped: scripts/ui/inventory_grid.gd, scripts/tests/test_bag_cap.gd, scripts/tests/test_chest_paired_view.gd, scripts/ui/chest_panel.gd all exist. Supersession is confirmed twice: NOTES.md:335 ('chest_panel.gd ... Replaces old inventory_grid paired-view, removed ~150 lines from inventory_grid.gd') and inventory_grid.gd's own header (lines 18-20: 'Chest paired-view was REMOVED from this file. Chest interaction now lives in scripts/ui/chest_panel.gd'). The plan file at repo root thus documents a stale save version, stale test count, and a superseded chest-interaction design with no supersession banner. No refutation found — nothing in the file marks it historical.

</details>

### 78. File-layout section lists nonexistent assets/ directory and omits real top-level dirs tools/ and addons/
**Where:** `CONVENTIONS.md:65` | **Category:** doc-drift, found by doc-drift

CONVENTIONS.md's file-layout tree ends with 'assets/ # sprites, audio, fonts (mostly unused while graphics deferred)', but no assets/ directory exists in the repo. Meanwhile two real top-level directories are absent from the layout: tools/ and addons/ (the latter hosting godot_mcp, which NOTES.md documents extensively as part of the install footprint). Since CONVENTIONS.md is 'project law', its map of the repo should match the territory — a newcomer or automated tool trusting the layout would look for assets in a directory that was never created.

**Evidence:**
```
CONVENTIONS.md:65: 'assets/                         # sprites, audio, fonts (mostly unused while graphics deferred)'. Actual root listing: CONVENTIONS.md, INVENTORY_UI_PLAN.md, NOTES.md, PROJECT_LOG.md, SESSION_E_PLAN.md, addons, icon.svg, project.godot, scenes, scripts, tools — no assets.
```
**Fix:** In CONVENTIONS.md's File layout tree: (1) delete the assets/ line at :65, or reword it to 'assets/  # (planned — not yet created; graphics deferred)'; (2) add 'addons/godot_mcp/  # editor MCP bridge (tracked)' since it is versioned repo content; (3) optionally add 'tools/  # local Godot 4.6.3 binaries (git-ignored, not part of repo)' to explain the directory newcomers will see on disk. No code changes needed; doc-only edit.

<details><summary>Verification notes</summary>

- Confirmed. CONVENTIONS.md:65 lists assets/ in the "## File layout" tree (header at line 39), but no assets/ directory exists on disk or in git. addons/godot_mcp/ is git-tracked yet omitted from the tree. tools/ is also omitted but contains only git-ignored Godot binaries (.gitignore *.exe/*.zip), so that half of the claim is weaker — omission of an untracked local-install dir is defensible, though MEMORY.md relies on it. Net: the map does not match the territory in a doc labeled project law.

</details>

### 79. console.gd header says '12 commands' and omits the wasteland command from its own list
**Where:** `scripts/ui/console.gd:19` | **Category:** doc-drift, found by doc-drift

The file header enumerates '12 commands: help, seed, tile, give, place, destroy, tp, set_soil, deplete_area, fertilize, clear, tick_speed', but the _commands registry in the same file now contains 13 entries — 'wasteland <x> <y>' was added at session-soil-exhaustion-4 (registered at line 407). The architecture docstring is the first thing a reader trusts when opening the file, and it undercounts and mis-enumerates the command set it purports to describe.

**Evidence:**
```
console.gd:19-20: '##   - 12 commands: help, seed, tile, give, place, destroy, tp, set_soil,\n##     deplete_area, fertilize, clear, tick_speed.' vs console.gd:407: '"usage": "wasteland <x> <y>"' in the _commands dict.
```
**Fix:** In C:/Users/ockla/FACTCLONE/scripts/ui/console.gd lines 19-20, either update to "13 commands: clear, deplete_area, destroy, fertilize, give, help, place, seed, set_soil, tick_speed, tile, tp, wasteland" or (more durable) drop the hardcoded count/list and say "Commands are registered in the _commands dict in _ready(); see 'help' in-game for the current list" so the header cannot drift again.

<details><summary>Verification notes</summary>

- Confirmed doc-drift. console.gd:19-20 says "12 commands" listing help, seed, tile, give, place, destroy, tp, set_soil, deplete_area, fertilize, clear, tick_speed. The _commands dict populated at line 344 has 13 entries (usage strings at lines 347-407), including "wasteland <x> <y>" at line 407, which is absent from the header list. Counted the registry entries directly; no dynamic registration elsewhere changes the count.

</details>

### 80. Dev Console section: command list omits wasteland; '12 commands, 29/29 tests passing' both stale
**Where:** `NOTES.md:70` | **Category:** doc-drift, found by doc-drift

The Dev Console section's status line says '12 commands ... 29/29 tests passing' and the Commands line enumerates 12 names. The console now has 13 commands (wasteland added at session-soil-exhaustion-4, per PROJECT_LOG's Session 4 entry 'Dev Console additions'), and the runner is at 33 suites. The section also pins console.gd at 657 lines (line 74), now 812. Since NOTES.md presents this as current Status rather than a dated snapshot, every one of these numbers actively misinforms.

**Evidence:**
```
NOTES.md:68: 'SHIPPED. 12 commands, debug-build-only, in-memory history, 29/29 tests passing.' NOTES.md:70: '**Commands:** `help`, `seed`, `tile [radius]`, `give`, `place`, `destroy`, `tp`, `set_soil`, `deplete_area`, `fertilize`, `clear`, `tick_speed`.' Actual registry in console.gd includes `wasteland` (line 407); 33 test suites exist.
```
**Fix:** In NOTES.md Dev Console section: (1) line 68 — change to "13 commands" and either drop the test count or state "33/33 suites passing (runner-wide)"; (2) line 70 — add `wasteland` to the command list; (3) line 74 — update 657 to 812, and explicitly note that this crosses the ~800-line split threshold at line 78, so either do the console.gd/console_commands.gd split or record a decision to defer it; or move the whole shipped section to PROJECT_LOG per the file's lifecycle rule.

<details><summary>Verification notes</summary>

- Confirmed on all counts: NOTES.md:68 says "12 commands ... 29/29 tests passing" and NOTES.md:70 lists 12 names omitting wasteland, but console.gd's _register_commands() has 13 entries including "wasteland" (console.gd:405, impl at :710); test_runner.gd TESTS array has 33 suites (lines 15-47); NOTES.md:74 says 657 lines but console.gd is 812 lines. Bonus drift: 812 exceeds the ~800-line split trigger the same section sets at NOTES.md:78, so the stale figure masks that the documented refactor condition has fired.

</details>

### 81. '14 specialized panels' headline enumerates 17 and the repo now has 21
**Where:** `NOTES.md:301` | **Category:** doc-drift, found by doc-drift

The Building Interaction UI section's headline count is internally inconsistent with its own enumeration: '14 specialized panels:' is followed by a per-session list totaling 17 (Session 1: 2, Session 2: 6, Session 3: 6, Session 4: 3). And the actual repo now contains 21 specialized building panels — the 17 listed plus composter_panel.gd, fertilizer_applicator_panel.gd, inserter_panel.gd, and fast_inserter_panel.gd, all added after the arc closed. The same section's 'Tests: 24/24 passing' (line 340) is similarly frozen at arc-close time while the runner is at 33. Since the section is framed as current status ('COMPLETE ... Every interactive building in the game has a specialized UI panel'), the counts mislead.

**Evidence:**
```
NOTES.md:301: '**14 specialized panels:**' followed by lines 303-305 listing 2+6+6+3 = 17 panels. scripts/ui/ contains 21 building-specific panels (adds composter, fertilizer_applicator, inserter, fast_inserter). NOTES.md:340: '**Tests: 24/24 passing.**' vs 33 current suites.
```
**Fix:** In NOTES.md: (1) change line 301 to match reality — either '17 specialized panels (as of session-building-ui-4):' keeping the enumeration frozen with an explicit date-stamp, or '21 specialized panels:' adding a post-arc line 'Post-arc: ComposterPanel, FertilizerApplicatorPanel, InserterPanel, FastInserterPanel'; (2) update line 340 from 'Tests: 24/24 passing' to either the current count (33/33) or reword to a non-frozen form like 'covered by the building-UI suites (test_building_ui through test_building_ui_4) in the full runner', so the number cannot silently drift again; (3) optionally soften line 299's 'Every interactive building has a specialized UI panel' to note it was true at arc close and post-arc buildings have continued the pattern.

<details><summary>Verification notes</summary>

- Confirmed on all three counts. NOTES.md:301 says '14 specialized panels:' but lines 302-305 enumerate 2+6+6+3 = 17 (the '14' matches line 285's Sessions-1+2+3 subclass tally, never updated for Session 4). scripts/ui/ has 21 building-specific panels: the 17 listed plus composter_panel.gd (extends ProcessorPanel), fertilizer_applicator_panel.gd (extends BuildingPanel), inserter_panel.gd (extends BuildingPanel), fast_inserter_panel.gd (extends InserterPanel). NOTES.md:340 says 'Tests: 24/24 passing' while test_runner.gd preloads 33 suites (lines 15-47), matching the 33/33 baseline. Section is framed as current status, so the stale counts mislead.

</details>

### 82. 'ProcessorPanel: 11 consumers' contradicted by code (12) and by NOTES.md itself
**Where:** `NOTES.md:308` | **Category:** doc-drift, found by doc-drift

The 'Final reuse milestones' bullet claims ProcessorPanel has 11 consumers and lists them; grep shows 12 files with 'extends ProcessorPanel' (excluding the base class): the 11 listed plus composter_panel.gd. NOTES.md's own soil-arc section (line 135) already calls Composter the '12th ProcessorPanel consumer', so the two sections of the same document disagree. Consumer counts are used in this project as refactor-trigger inputs (cf. click-handling '4+ consumers' criteria), so drifted counts have downstream decision weight, not just cosmetic cost.

**Evidence:**
```
NOTES.md:308: '**ProcessorPanel: 11 consumers** (Mill, Oven, Proofer, Packager, Loom, Tailor, Briquetter, Sugar Press, Retter, Yeast Culture, Thresher)' vs NOTES.md:135: '12th ProcessorPanel consumer' (Composter). Grep 'extends ProcessorPanel' matches 12 consumer files including scripts/ui/composter_panel.gd.
```
**Fix:** In NOTES.md, update line 308 to "**ProcessorPanel: 12 consumers**" adding Composter to the list (or append "(as of arc close; Composter became the 12th in the soil arc — see line 135)"), and update line 353's "11 consumers" to match. Optionally also refresh the stale "(10 → 11 consumers)" phrasing in the test summary at line 340 for consistency.

<details><summary>Verification notes</summary>

- Confirmed. NOTES.md:308 and :353 both say 11 ProcessorPanel consumers (Composter not listed), while NOTES.md:135 calls Composter the "12th ProcessorPanel consumer" and PROJECT_LOG.md:529 agrees. Grep shows exactly 12 subclass files with `extends ProcessorPanel` in scripts/ui/, including composter_panel.gd. The only defense — reading line 308 as an end-of-arc snapshot — fails because the bullet has no as-of annotation and the same document contradicts it at line 135.

</details>

### 83. Soil-arc test tally: '31 sub-suites total' but the listed components sum to 35
**Where:** `NOTES.md:143` | **Category:** doc-drift, found by doc-drift

The soil-arc shipped-list says 'Tests: 31 sub-suites total — 17 soil + 5 fertilizer-chain + 4 fertilizer-applicator + 9 wasteland sub-suites', but 17+5+4+9 = 35, not 31. The '31' appears to be the runner-level suite count at session-soil-exhaustion-4 time (PROJECT_LOG: 'Tests: 30 → 31 passing'), conflated with the per-file sub-suite tally. Whichever number is intended, the sentence as written cannot be internally consistent, and future sessions using it to sanity-check coverage will trip on the mismatch.

**Evidence:**
```
NOTES.md:143: 'Tests: 31 sub-suites total — 17 soil + 5 fertilizer-chain + 4 fertilizer-applicator + **9 wasteland sub-suites**' (components sum to 35). PROJECT_LOG.md:296 for the same session: '**Tests: 30 → 31 passing**, but the new test file (`test_wasteland.gd`) has 9 sub-suites'.
```
**Fix:** In NOTES.md:143, separate the two counting schemes and timestamp the runner figure, e.g.: "Tests: 35 soil-arc sub-suites (17 soil + 5 fertilizer-chain + 4 fertilizer-applicator + 9 wasteland); runner-level suite count was 31 at arc close (now higher — later arcs added suites)." Optionally verify the "17 soil" figure against test_soil_exhaustion.gd (its success message at line 344 does not self-report a count) before committing the 35 total.

<details><summary>Verification notes</summary>

- Confirmed. NOTES.md:143 says "31 sub-suites total" while its own component list (17+5+4+9) sums to 35 — internally inconsistent regardless of intent. PROJECT_LOG.md:296/307 proves "31" is the runner-level suite count at session-soil-4 ("Tests: 30 → 31 passing"; "+1 test... but the file packs 9 sub-suites internally"), conflated with the per-file sub-suite tally. Component counts corroborated in code: test_wasteland.gd:266 (9), test_fertilizer_chain.gd:207 (5), test_fertilizer_applicator.gd:191 (4). Additionally the "31" runner figure is now stale (current runner: 33/33).

</details>

### 84. Stale enum comment: cloth-chain slots described as 'reserved', dispatch 'lands when the buildings ship' — they shipped long ago
**Where:** `scripts/world/buildings.gd:42` | **Category:** doc-drift, found by doc-drift

The comment above the RETTER/LOOM/TAILOR enum entries still reads as if the cloth buildings are unimplemented placeholders: 'DATA + make()/tick_one()/draw_one() dispatch land when the buildings themselves ship.' The buildings shipped at Session E with full DATA entries, dispatch cases, dedicated logic files (retter.gd, loom.gd, tailor.gd), panels, and tests (test_cloth_prefer_dir.gd), and NOTES.md records the chain as shipped-plus-polished. A reader scanning the enum to learn which types are live gets told these three are still pending.

**Evidence:**
```
buildings.gd:42-44: '# Cloth chain — enum slots reserved by Session E groundwork.\n# DATA + make()/tick_one()/draw_one() dispatch land when the buildings\n# themselves ship. Recipes already reference these enum values.' Actual: scripts/world/retter.gd, loom.gd, tailor.gd exist with panels (loom_panel.gd etc.) and NOTES.md:484 'Cloth chain prefer_dir — shipped'.
```
**Fix:** Replace buildings.gd:42-44 with a past-tense note matching the style of neighboring entries, e.g.: "# Cloth chain (Session E groundwork, shipped session-building-ui-3): Retter (flax + water -> fiber), Loom (3x fiber -> cloth), Tailor (4x cloth -> bag). Enum order fixed for save compatibility." Keep the RETTER/LOOM/TAILOR entries and the append-only ordering untouched.

<details><summary>Verification notes</summary>

- Confirmed. buildings.gd:42-44 contains the exact quoted comment claiming DATA + make()/tick_one()/draw_one() dispatch "land when the buildings themselves ship" (future tense). But the buildings are fully shipped: DATA entries exist at lines 373 (RETTER), 390 (LOOM), 405 (TAILOR) with complete slot_layouts; make() dispatch at 777-782 calls Retter.make/Loom.make/Tailor.make; tick_one dispatch at 811; draw_one dispatch at 872-876; info_lines at 1082; and scripts/world/retter.gd, loom.gd, tailor.gd all exist. The comment's "enum slots reserved" framing actively misleads a reader scanning the enum for live building types. No guard or context mitigates it — the drift is genuine. Pure doc issue, no runtime effect; 33/33 tests unaffected.

</details>

## Refuted during verification (for the record)

- `scripts/main.gd:260` -- _apply_loaded_progression merges instead of replacing — F9 load keeps current-session cursor/progression keys absent from the loaded save (item duplication) (claimed by save-integrity, refuted on code inspection)
- `scripts/main.gd:638` -- Wheel-up-to-close-map (zoom behaviors A/B) is dead in-game: the open MapPanel's MOUSE_FILTER_STOP consumes wheel events before _unhandled_input (claimed by main-console, refuted on code inspection)

