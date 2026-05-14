# Stewardship — design notes

Forward-looking design plans that aren't yet implemented. Each entry should answer: what's the goal, what hooks exist today, what blocks it, what's the target session.

Move entries to `CHANGELOG.md` (or just delete them) once the corresponding work ships.

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

## Inserter Arc — 2 of 6 sessions shipped

**Status:** Sessions 1 (basic, foundation) + 2 (fast tier + filter, parametric refactor) shipped. 4 remaining sessions queued; each adds a tier or capability, none architecturally blocking.

**Shipped:**
- **Session 1 (`session-inserter-foundation`)** — basic 1-tile inserter, fuel-powered via Burner module, 1.0s cycle. Universal source/dest (belt/chest/Processor). Closes the "can't connect chest to building without a belt" hole.
- **Session 2 (`session-inserter-fast-filter`)** — Fast Inserter: 0.5s cycle (twice as fast), single-slot filter (drop-to-set, RMB-clear). Inserter.gd refactored to tier-parametric (`CYCLE_TICKS_BY_TYPE` / `BODY_COLOR_BY_TYPE` Dictionary lookup tables); both basic and fast share `Inserter.tick`. New `'filter'` slot kind in BuildingPanel. Pre-existing Session 1 fuel-port bug caught at PAUSE 1 and fixed (now uses `FUEL_PORT_DIR = Belt.DIR_S`, mirroring Smelter pattern).

**Queued (re-plan each at session start):**
- **Session 3 — Long-Reach Inserter.** Same code path as basic/fast; `ARM_LENGTH_BY_TYPE` table with longer reach (1.2 fraction of tile_size), `source_tile`/`dest_tile` use 2-tile offsets. Visual: longer arm. Cycle speed: 1.5s (slower for distance trade-off). No filter.
- **Session 4 — Electric Inserter + multi-filter.** Switches from fuel-powered to electric power (requires Electricity Arc to ship first — separate prereq). Multi-slot filter: 3 filter slots, picks any of the 3 types. Electric tier is base for the next steps.
- **Session 5 — Long-Reach Fast Inserter / Long-Reach Electric.** Combines reach + speed/power dimensions. Tier-parametric tables make this ~30 lines per variant.
- **Session 6 — Stack Inserter (electric).** Picks UP TO 3 items per cycle (or per stack-size config), drops them as a single batch. Throughput scaling for late-game. Fundamentally different from prior tiers' "1 item per cycle" model — needs careful design pass.

**Architectural extension cost per future tier:** add 1 row to each `*_BY_TYPE` table in `inserter.gd`, add 1 enum entry + DATA entry + dispatch case in `buildings.gd`, ~85 lines for a specialized panel if needed (most tiers reuse FastInserterPanel). Stack inserter is the exception — needs a different state shape for batch-pickup.

**Cross-cutting:**
- Filter tracking is universal (`filter_item_type` on every inserter type, default -1). Multi-filter (Session 4) extends to an Array of types.
- Burner module is shared across drill / smelter / inserter / fast inserter / future kilns. The FUEL PORT DIRECTION pattern (perpendicular edge, never `-1`) is now documented in the Burner header.
- Click-handling-extraction trigger from this section's "Click-handling duplication" entry is now MET (filter slot's RMB-clear is a panel-specific click semantic). Captured in QoL Polish Session below.

---

## QoL Polish Session — Cluster C SHIPPED, A+B queued

**Status:** Cluster C (building-blocks-movement) shipped as a small post-session fix immediately after `session-inserter-fast-filter`. Clusters A (click extraction + stack-split + quantity picker) and B (tooltips + filter dropdown + filter status diagnostic) remain queued for a dedicated future session. Six original items minus Cluster C → 5 remaining. Estimated 3-4 hours for the remaining clusters.

**Items (ordered by architectural dependency, NOT priority):**

1. **Click-handling extraction** — refactor pick/drop/swap logic shared by `BuildingPanel._handle_player_slot_click` and `inventory_grid._handle_left_click_player` into a shared helper. Most likely shape: `SlotWidget.handle_click(slot_provider, cursor, modifiers) -> void` OR `CursorStack.click_swap(slot, cursor, modifiers) -> void`. Decide concrete shape during implementation. **This is the architectural prerequisite for items 2+3** — both modify the click-handling code paths in identical ways, refactoring first means one site to edit instead of two. Trigger criteria from prior NOTES.md entry NOW MET (per session-inserter-fast-filter — filter slot RMB-clear is the first context-specific click semantic).

2. **Shift+click stack-split (half).** Empty cursor + shift-click on slot → take half (rounded up) into cursor. Cursor-holding-stack + shift-click → drop half. Applies to: inventory grid, chest panels, building input slots, fuel slots (half-by-item-count, then convert to units on drop). NOT filter slots (metadata, no shift behavior).

3. **Ctrl+click quantity picker modal.** Click → opens a small popup near the slot with a number input + confirm/cancel. New small UI element, ~100 lines. Same slot-applicability as #2.

4. **Item hover tooltips with descriptions.** Hover any slot (inventory or panel) for ~500ms → tooltip with item name + description. Requires `Items.gd` description field per item type (~30 items × ~50-char descriptions). Tooltip widget is shared component. Estimated ~150 lines for the tooltip rendering + ~30 lines for description field plumbing. Per-item description text is content authoring (~1 hour).

5. **Filter dropdown picker (complementing drop-to-set).** Clicking the filter slot opens a scrollable item picker overlay; click an item to set the filter. Drop-to-set still works as alternative path (Factorio-style — click OR drop both work). Estimated ~120 lines: picker widget + close-on-click-outside + item-list scrolling.

6. **Building-blocks-movement with per-building `walkable` flag.** **SHIPPED** (Cluster C, immediately post-session-inserter-fast-filter). PROJECT_LOG entry "Cluster C — Building-blocks-movement (small post-session fix)" has the details. Walkable: BELT + INSERTER + FAST_INSERTER (thin devices). Blocked: everything else including PIPE (per locked Q4). Player-on-tile placement rejected with toast. 33/33 tests passing.

**One smaller follow-up captured during Session 2 PAUSE 2:**

7. **Filter status diagnostic.** When fast inserter has filter set but no matching items in source, panel shows `Status: IDLE` with no hint why. Add a `Status: IDLE (no items match filter)` line. ~5 lines. Tag it onto whichever QoL sub-session ships #5 (filter dropdown).

**One follow-up captured during session-qol-cluster-a GATE 1 smoke:**

8. **Close-on-padding-click UX.** Currently panels close when an LMB lands on any non-slot pixel within or outside the panel rectangle (intentional pre-existing behavior, explicitly documented in inline comments at `building_panel.gd:188-192` "Click outside any slot — close panel (cursor persists)", `chest_panel.gd:97-100`, and `inventory_grid.gd:110-112`). Factorio convention treats empty panel space as a no-op; only an explicit close button, Esc, OR a click in the dimmed-out background area outside the panel rectangle closes. Worth revisiting as UX polish. Decision points for future design pass:
   - Should panel padding/header/footer be no-op (and only Esc + close button + dim-background click close)?
   - Or keep current behavior but make the "hit-test" area more obvious (e.g., explicit close button glyph)?
   - Migration concern: muscle memory of long-time players may rely on the current behavior; surveying decision worth a brief design-pass.
   Possibly bundled with Cluster B's tooltip work (items 4+5+7) since both address panel discoverability/feedback. ~10-30 lines depending on resolution.

**Architectural notes:**
- Items 1+2+3 form a cluster (click-handling). Land together.
- Items 4+5+7 form a cluster (UI feedback / discoverability). Land together — item 8 may bundle in.
- Item 6 is standalone (player movement / placement).
- Multi-session split: cluster-by-cluster is the obvious cut. Single-session: do extraction first, then 2+3, then 4+5+7+8, then 6.

**Save schema impact:** none expected. Stack-split / picker / tooltips / movement are all UI-layer + read-only checks. Walkable flag is data registry, not save state.

**Tests:** est ~6-8 new sub-suites across the cluster.

---

## Dev Console — SHIPPED (session-dev-console)

**Status:** SHIPPED. 12 commands, debug-build-only, in-memory history, 29/29 tests passing. Manual smoke deferred to first real-use session per session-end decision.

**Commands:** `help`, `seed`, `tile [radius]`, `give`, `place`, `destroy`, `tp`, `set_soil`, `deplete_area`, `fertilize`, `clear`, `tick_speed`. See PROJECT_LOG entry for full table + design rationale.

**Manual-smoke-at-first-use note:** ✅ **COMPLETED at session-soil-exhaustion-4 PAUSE 1.** First real-use was the wasteland session, exactly as anticipated. Caught 2 real bugs (Bug 1: `tile` command displayed raw enum ints; Bug 2 CRITICAL: Premium Compost hotbar slot was missing — wasteland recovery path unreachable via hand-apply). Both fixed before that session's commit. The "ship tooling without exhaustive UI testing, surface bugs on first real use" pattern paid off — UI bugs surfaced in a low-stakes context (one session's PAUSE) rather than blocking gameplay forever. **Validated this protocol for future tooling sessions.**

**File-size finding:** `console.gd` ended up at 657 lines vs the 300–400 design-pass estimate. Two underestimates:
- **UI layer underestimated** (~80 lines for Godot Control / RichTextLabel / LineEdit setup — anchors, theme overrides, signal wiring, color-bbcode helpers).
- **Command bodies averaged 22 lines, not 10** (validation discipline non-negotiable: 2–4 arg checks + 2–3 error returns + the operation per command).

If `console.gd` grows beyond ~800 lines (e.g., adding more commands or richer UI), split into `console.gd` (UI + activation) + `console_commands.gd` (parser + command implementations). ~30-min refactor when triggered. Today the single-file shape is more convenient for adding commands; defer the split.

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
- **Fertilizer Applicator (Session 3.5):** 1×1 footprint, 5×5 coverage, belt-fed or drag-drop compost input, auto-applies to most-depleted eligible tile at 1-per-5-sec rate. Tier-preference (MID before LOW). Three-state machine (IDLE / SCANNING / BLOCKED). Specialized panel with 5×5 coverage mini-grid + cell color states (pristine/eligible/LOW-fertilized/MID-fertilized/impassable). **Session 4: input slot accepts HIGH alongside LOW + MID.**
- **Wasteland mechanics (Session 4):** tile soil at 0 for 60 sec → scarred (persistent). Wasteland blocks all passive regen. Distinct visual (near-black tint + X-shaped crack pattern). Q-inspect: "DEAD — will scar in Xs" during grace, "WASTELAND" once scarred. PlanterPanel: "IDLE — tile is WASTELAND" + action prompt.
- **Premium Compost / COMPOST_HIGH (Session 4):** 8× regen for 120s (top tier). On wasteland: snap soil to 30 + erase scarred flag + apply boost (~21 min total recovery designed). On healthy tile: just a stronger MID. Recipes: BREAD × 2 → HIGH (5s? actually 10s), LOAF_PACK × 1 → HIGH (10s — same time, better deal). Stacking: HIGH > MID > LOW; lower-on-higher rejected. LOW/MID on wasteland REJECTED (only HIGH restores).
- Save schema v14 → v15 → v16 → v17 → v18 (wasteland state added at v18). 4 schema bumps in the arc; migration framework still queued.
- Tests: 31 sub-suites total — 17 soil + 5 fertilizer-chain + 4 fertilizer-applicator + **9 wasteland sub-suites** (trigger + grace + recovery + planter idle + save v18 + composter HIGH recipes + stacking + grace-rescue).

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
