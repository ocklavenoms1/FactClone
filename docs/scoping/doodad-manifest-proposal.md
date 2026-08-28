# Doodad asset contract — PROPOSAL, not a decision

**Status: proposed to the designer 2026-08-28. Awaiting ratification.**
The building contract was ratified before it was relied on; this one gets the
same treatment. Nothing here is settled until the designer says so.

Written after Ground Phase 2 Session 1 built placement, suppression, draw order
and gates against the manifest the art session had already delivered
(`art/doodads.json` + `art/sprites/doodads/<name>.json`, committed at `1cfcd99`).
This document proposes keeping that contract essentially as delivered, and
states exactly which fields the game reads — so the art side knows what it is
promising and what it is merely recording.

## The proposal in one line

**Keep the delivered contract unchanged.** It is already lighter than the
building contract in the right places, and the one field the game most depends
on (`anchor_mode`) is explicit here where buildings only imply it.

## What the game actually reads at runtime

Four fields per doodad. Everything else is provenance, authoring input, or
assertion material.

| field | why the game needs it |
|---|---|
| `name` | selects the PNG and keys the variant table |
| `sprite_px` `[w, h]` | asserted equal to the PNG's real dimensions; a mismatch drops that variant to a placeholder **loudly** rather than drawing it wrong |
| `anchor_px` `[x, y]` | the ground-contact point the doodad is placed by |
| `status` | `"calibration"` entries are excluded from placement — `_calib_disc` must never appear in a player's world |

Read but never applied: **`plan_squash`**, asserted equal to `1.0` (see below).
Informational only: `kind`, `materials`, `seed`, `master`, `lock_stamp`,
`render_px`, `crop_offset_px`, `note`.

`kind` deserves a note because it is the field most likely to be assumed
load-bearing: it carries **no geometry for the game**. It selects `height_px`
vs `plan_px` at authoring time, and by the time a PNG exists that distinction
is already resolved into pixels.

## The rule that ruins the read if either side assumes the other applies it

**GROUND_SQUASH (0.86603) is baked into the sprite. The game applies NOTHING.**

This is the one line in this contract worth reading twice, because both halves
are individually plausible and the failure is silent-ish — it does not crash,
it just makes doodads the only objects in the game disagreeing with the tile
grid they sit on.

The mechanism, from `art/PIPELINE.md` §1: the camera squashes the ground plane
by sin 60° = 0.86603, and the anamorphic correction bakes that into the render
height and undoes it in the LANCZOS downsample. That is *why* one ground tile
is exactly 32×32 rather than 32×28. Ground plan shapes therefore arrive at true
proportions already, and a second squash in the game would halve them again.

Measured, not argued: `_calib_disc` exists so this can be checked rather than
believed, and it comes back **32×33 at alpha>127** — round within a pixel.

The contract is therefore:

- the art side applies the squash (inside the render, then undoes it),
- the manifest records `plan_squash: 1.0` as the statement that the sprite is
  already correct,
- the game **asserts** that value and never multiplies by it.

A `plan_squash` other than 1.0 should be treated as a manifest error, not as an
instruction — if a doodad ever genuinely needs a different plan scale, that is a
contract change to negotiate, not a number to quietly honour.

## What the contract does not carry, and who owns it instead

- **Variant grouping and selection weight.** Nothing in the manifest says how
  often `pebble_cluster` should appear relative to `weed_clump`. Selection is
  currently uniform over the four variants, hashed per cell. If the designer
  wants weighting, that is a field to add (`weight`, default 1.0) — proposed,
  not assumed.
- **Density.** Owned by the game (`Doodads.CANDIDATE_PROBABILITY`, currently
  0.125 — one candidate per 8 tiles of area). The brief's "~1 per 6–10 tiles"
  was read as area rather than as a 6–10-tile cell; the other reading is 4–8×
  sparser and is a one-constant change if that was meant.
- **Contrast.** Owned by `art/tools/assert_doodad_contrast.py`, which composites
  each doodad over the ground and takes the p95 luminance ratio. The game's
  `ground_verify.py` deliberately does **not** re-implement that statistic — it
  wraps that tool and asserts the manifest's `ground_hex` and `contrast_cap`
  still match the shipped green and the shipped cap.

## The two copies this contract creates, and why they are asserted

`art/doodads.json` holds `ground_hex` and `contrast_cap` — copies of values the
game owns. They cannot be removed (the art tools need them standalone), so they
are asserted instead: `ground_verify.py` fails if `ground_hex` drifts from the
shipped green or `contrast_cap` from the shipped cap.

Without that assertion, changing the ground colour would leave every doodad
validated against a ground the game no longer draws, and nothing anywhere would
report it. This is the sixth recorded instance of the same shape (NOTES, silent
compensation): *a value that must equal another value is a silent-compensation
site — read it, don't copy it; if you must copy it, assert the copy.*

## Open question this contract cannot answer

The 1.25:1 contrast cap is currently unreachable by construction, and the art
side's own analysis is the reason: a cap of C admits a luminance window C²
wide (1.5625), a doodad cannot be fitted into a window narrower than its own
shading range because scaling slides a distribution rather than narrowing it,
and the locked rig's measured diffuse range is 2.72:1 — putting the floor under
any cap at √2.72 = **1.65**. Best achieved so far: twig 1.79, pebbles 2.07,
grass 2.33, weed 2.59.

That is a decision about the cap or the rig, not about this contract. The
game-side contrast gate is shipped **dormant** and arms when the cap is ruled.
