# Session E — Cloth chain + bag-as-consumable

Starting brief saved at the close of Session D. Loaded by the next session to re-establish context without a planning round-trip.

**Current state at hand-off:**
- Tag: `session-d-complete` (commit `79ce642`)
- Save: v9
- Tests: 8 passing
- Shipped through Session D: multi-tile (2×2 Mixer/Oven/Proofer/Packager), rotation (Mixer/Oven/Proofer/Packager/Thresher with `state.dir` + `Buildings.world_dir`), visual upgrades (footprint border, port indicators, distinct pipe rendering).

---

## Order of work

1. **Audit existing test thresholds** (per Session C/D lesson) — anything still on minimum-viable counts? Tighten anything that's still ≥1-over-short-window.

2. **Add cloth chain content:**
   - **Items:** flax, fiber, cloth, bag.
   - **Recipes:**
     - Retter: `flax + water → fiber`
     - Loom: `3 fiber → cloth`
     - Tailor: `4 cloth → bag`
   - **Buildings:** Retter, Loom, Tailor.
   - **Flax Planter** as a separate hotbar entry (mirrors the Wheat / Sugar Beet pattern from Session C).

3. **Bag-as-consumable mechanic:** player consumes bag from inventory, gains +N slots permanently, capped at 5 consumed total. Toast on attempt to exceed cap. (Decision #3 from Session A planning, confirmed.)

4. **F11 demo extended** with cloth chain running parallel to bread chain, sharing the pump+pipe water network — that's the integration test (multi-consumer fluid network was implicit in Session B/D, now stress-tested).

5. **PROJECT_LOG entry, commit + tag `session-e-complete`.**

## Design questions to resolve in design pass (before code)

- **Building sizes** (confirm during design pass before implementing):
  - **Loom** probably 2×2 (industrial loom is big)
  - **Retter** probably 2×2 (it's a vat, water-bath)
  - **Tailor** probably 1×1 (tailor's bench, smaller)
- **prefer_dir layouts** for each new recipe — canonical orientation, will rotate via `Buildings.world_dir`.
- **Bag effect detail:** how many slots per bag? Spec said "+N"; pin a number during design (probably +4 or +5 — playtest-validate).
- **Cap of 5 bags:** is that 5 total bag-uses or 5 simultaneously held? Spec says "5 consumed total" → permanent cap on lifetime upgrades.

## Discipline (unchanged)

- Design before implementation. Show the plan, get approval, then code.
- Q-inspect when in doubt.
- Ask before deleting files.
- Verify before commit (8+ tests pass, F11 demo runs end-to-end including the new cloth path).
- Schema bump v9 → v10 only if tile / building state shape changes; new building types and recipe content are forward-compat additions.

## After Session E

Session F brings the premium feedback loop (Trough, Coop, optional Egg Collector, premium bread, configurable Oven via info panel, score/value system). Re-confirm score system before implementing — spec recommended deferring to F unless playtest demand emerges sooner.

---

## Adjacent feature requests (not part of Session E)

### Camera zoom

**Goal:** mouse-wheel zoom for surveying large factories without losing the close-in detail of single-tile inspection.

**Spec:**
- Mouse wheel scrolls to zoom in/out.
- Min zoom shows roughly **5×5 tiles** (close-in detail; matches today's view at default).
- Max zoom shows roughly **40×40 tiles** (factory overview).
- Smooth interpolation between zoom levels — not snap-to-step.
- **Render-layer requirement:** hover indicators, port dots, footprint borders, and item sprites must remain readable at max zoom. If anything renders too small to see at 40×40 zoom, treat it as a render-layer problem to flag during implementation, not a deferred polish task — overview that doesn't surface state is useless.

**Implementation hint (not a decision):** GridWorld already takes `@export var camera: Camera2D` — zoom is just `camera.zoom = Vector2(z, z)`. The hard part will be making port dots / borders visible at low zoom (they're computed at fixed pixel sizes today, e.g. `_PORT_RADIUS = 4.0` in `buildings.gd`). Likely fix: scale dot/border sizes inversely with `camera.zoom` so they stay visible-but-not-overwhelming.

**Out of scope for this note (open questions for the zoom session):**
- **Pinch-zoom on touch.** Mouse-wheel only for now; touch is a separate input layer.
- **Zoom-to-cursor vs zoom-to-center.** Both are reasonable; pick during implementation. Factorio uses zoom-to-cursor; some RTSes use zoom-to-center. Try one, see how it feels.
- **Zoom level persistence in saves.** Probably yes (it's player-comfort state, like cursor position would be), but not a save-shape change worth bumping the schema for. Could go in a separate "ui prefs" file.
- **Mouse-wheel-while-pressed conflicts.** If shift+wheel or alt+wheel ever bind to other actions, plain wheel needs to stay zoom. Verify the InputMap doesn't already use wheel.

**Sizing as a session:** small standalone session. Probably ~2-3 hours including the render-scaling fixes for indicators. Could land as a Session E sub-slice if Session E proper finishes early; otherwise its own session before F.
