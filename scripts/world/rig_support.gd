class_name RigSupport
extends RefCounted

## SHARED SMOKE-TEST RIG SCAFFOLDING (Electricity Session 4, Task 1).
##
## The phase-1 pave loop and the phase-2 adopt-or-collide classifier that
## ElectricRig, PoleTierRig and PoleGameplayRig each carried as a near-verbatim
## copy. PoleTierRig's build() named this refactor — a shared RigSupport with
## pave_rect() and place_or_adopt() — and said a THIRD rig should trigger it;
## the third (PoleGameplayRig) shipped at pole-tiers PAUSE 2 and the cut was
## deferred on scheduling only, because electric_rig.gd was that session's
## untouched control. Extracted at the top of Electricity Session 4, before the
## fourth rig (processor_rig) could copy the scaffolding a fourth time. The
## seam is recorded in NOTES.md under "Queued: extract RigSupport".
##
## WHAT DELIBERATELY DOES NOT LIVE HERE:
##   - the power LEVER (apply_power_state / sustain_fuel / state_label): it has
##     had exactly one implementation, on ElectricRig, since the second rig
##     shipped, so there is no duplication to remove, and moving it would churn
##     main.gd and the rig suites for a rename.
##   - anything LAYOUT: plans, offsets, pave rectangles, demand composition.
##     Those differences are the rigs' identity, and the three known ones this
##     extraction had to preserve stay where they were: ElectricRig's
##     source-chest arm (served generically by owned_anchors() on CHEST, not by
##     a chest branch here), PoleGameplayRig's THREE pave rectangles (it calls
##     pave_rect once per rectangle), and its bridge substation staying outside
##     plan() (so the classifier never sees it and a toggled-off bridge cannot
##     break all-or-nothing adoption).

## Phase 1: pave one INCLUSIVE rectangle [lo..hi] (rig-relative; `origin` maps
## it to world tiles) with STONE overlay, skipping any cell that already holds
## a building.
##
## Writing a fresh Tile does three jobs at once, and all three are needed for a
## rig to land on ANY world seed:
##   1. clears a WATER base, which can_place_building rejects outright;
##   2. resets resource_node to ResourceNodes.DEFAULT (Tile._init's third
##      default), which is what lets set_overlay past its deposit/tree guard
##      and stops can_place_building's own resource-node guard firing;
##   3. clears any stale overlay so the STONE write below is the only one.
##
## This IS destructive: it overwrites base, overlay and resource_node across
## the rectangle and discards regrowth timers. Deliberate — it is the only way
## to make placement seed-independent.
##
## The direct `world.tiles[cell] =` write does not itself record into
## tile_modifications, but it does not need to: the set_overlay on the next
## line records the WHOLE tile (base, overlay AND resource_node — see
## grid_world.gd:347) once it has applied, so the base reset is saved too.
## That only holds because the Tile written here always carries Overlay.NONE,
## which keeps set_overlay off its `current_overlay == overlay` idempotent
## early return (grid_world.gd:337) — the one path that records nothing.
##
## STONE is fixed, not a parameter: it is in the requires_overlay intersection
## of every building type any rig places (STEAM_GENERATOR is the strict one at
## [STONE, PATH]), and it reads as a deliberate pad against the surrounding
## grass. A rig that needs a different overlay is a rig this helper does not
## serve. Each rig's build() keeps the note on which of ITS types constrain
## that intersection.
##
## The building skip protects someone ELSE's building: set_overlay would
## refuse anyway, but the Tile.new above it would already have stripped that
## building's terrain out from under it.
static func pave_rect(world, origin: Vector2i, lo: Vector2i, hi: Vector2i) -> void:
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell: Vector2i = origin + Vector2i(x, y)
			if world.has_building_at(cell):
				continue
			world.tiles[cell] = Tile.new(Terrain.Base.GRASS, Terrain.Overlay.NONE)
			world.set_overlay(cell, Terrain.Overlay.STONE)

## Phase 2: walk a plan() — [rig_relative_offset, building_type, dir] triples —
## and build it, or ADOPT a rig that is already standing.
##
## Three outcomes, and telling them apart is what keeps a rig's lever alive:
##
##   BUILT    — every planned cell was empty and got its building. Normal.
##   ADOPTED  — every planned cell was ALREADY occupied by a building of
##              exactly the planned type, anchored exactly where the plan puts
##              it. That is what a relaunch onto a saved game looks like, or a
##              respawn key pressed without moving. The right answer is to
##              RE-ATTACH the lever: hand back the rig's real anchors (via
##              owned_anchors) instead of empty arrays, which would otherwise
##              leave a visibly complete rig the lever refuses to touch and
##              that goes dark when its fuel buffers run out.
##   COLLIDED — anything in between: the plan overlaps the player's own base,
##              or another rig. Callers report it as INCOMPLETE, and
##              owned_anchors hands back only what THIS call placed — never a
##              matched foreign building (see the data-loss note there).
##
## Type AND anchor are both checked. building_at() resolves any footprint cell
## to its owning anchor, so a 2x2 building sitting one tile off would
## otherwise report as "already exactly ours" from the wrong cell. Adoption is
## all-or-nothing: "some of it was already here" IS the collision case, and a
## half-adopted rig has the wrong demand total.
##
## Returns plain data (house law):
##   placed / skipped / matched  — the classifier's counts. skipped includes
##                                 both occupied cells and place_building
##                                 refusals; matched counts the subset of
##                                 skips that were exact plan matches.
##   adopted                     — placed == 0 and matched == entries.size()
##   built_by_type               — Dictionary: building type -> Array of the
##                                 anchors THIS call placed, in plan order.
##   matched_by_type             — Dictionary: building type -> Array of the
##                                 exact pre-existing matches, in plan order.
##
## Callers do not read the two dictionaries directly — owned_anchors() applies
## the adoption rule for them.
static func place_or_adopt(world, origin: Vector2i, entries: Array) -> Dictionary:
	var placed: int = 0
	var skipped: int = 0
	var matched: int = 0
	var built_by_type: Dictionary = {}
	var matched_by_type: Dictionary = {}
	for entry in entries:
		var pos: Vector2i = origin + (entry[0] as Vector2i)
		var btype: int = int(entry[1])
		var dir: int = int(entry[2])
		if world.has_building_at(pos):
			skipped += 1
			var sitting: Building = world.building_at(pos)
			if sitting != null and sitting.type == btype and sitting.anchor == pos:
				matched += 1
				if not matched_by_type.has(btype):
					matched_by_type[btype] = []
				matched_by_type[btype].append(pos)
			continue
		if not world.place_building(btype, pos, dir):
			skipped += 1
			continue
		placed += 1
		if not built_by_type.has(btype):
			built_by_type[btype] = []
		built_by_type[btype].append(pos)
	return {
		"placed": placed,
		"skipped": skipped,
		"matched": matched,
		"adopted": placed == 0 and matched == entries.size(),
		"built_by_type": built_by_type,
		"matched_by_type": matched_by_type,
	}

## The anchors a rig may treat as ITS OWN for `btype`, in plan order, under the
## adoption rule: the matched anchors when the whole rig was adopted, otherwise
## only the anchors this call placed.
##
## The COLLIDED case is why this cannot be "matched-or-built": a matched
## foreign building is type-identical to the rig's own, and ElectricRig
## seeding a chest it merely MATCHED during a collision would destroy
## everything a player had stored in it, with no undo. Adoption — ALL entries
## matched — is the one case where matched buildings are provably the rig's,
## because the only thing that looks exactly like the whole rig is the rig.
##
## Order is plan order, which is load-bearing for STEAM_GENERATOR: the lever
## fuels the FIRST N anchors (ElectricRig.FUELLED_BY_STATE), so every rig's
## plan() emits its generators in A, B order and this preserves it.
static func owned_anchors(report: Dictionary, btype: int) -> Array:
	var by_type: Dictionary = report["matched_by_type"] if bool(report["adopted"]) else report["built_by_type"]
	return by_type.get(btype, [])
