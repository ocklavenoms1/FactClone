class_name SlotClickHandler
extends RefCounted

## Shared click-handling logic for slot widgets (player inventory, chest,
## building input/output/fuel/filter). See spec:
## docs/superpowers/specs/2026-05-10-qol-cluster-a-design.md
##
## Static module — mirrors Burner / Processor / Inserter / Belt pattern.
## Pure functions; no scene-tree dependency.

const MOD_NONE: int = 0
const MOD_SHIFT: int = 1
const MOD_CTRL: int = 2

## Returns ceil(n / 2). The shared half-split math used by every kind's
## shift+LMB branch. Always non-negative; split_half(0) = 0.
static func split_half(n: int) -> int:
	if n <= 0:
		return 0
	return int(ceil(n / 2.0))
