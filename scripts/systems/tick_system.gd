extends Node

## Global simulation heartbeat. Autoloaded as TickSystem.
##
## Emits `tick` 20 times per second (every 50ms), independent of frame rate.
##
## THE TWO CLOCKS — a decision, not an accident (audit #31, decided 2026-08-26):
##
##   - The TICK clock drives the factory sim: buildings, belts, machines,
##     inserters, power. `tick_speed N` scales it; `paused` gates it.
##   - Soil regen, fertilizer decay and tree regrowth run on WALL-CLOCK
##     (`GridWorld._process`, raw engine delta) BY DESIGN. They are slow
##     world processes on a different scale from factory iteration — 30 s
##     per soil point, 60 s grace, 30-120 s boosts — so `tick_speed`
##     accelerates THROUGHPUT and not world recovery. Fast-forwarding your
##     factory does not fast-forward the land's forgiveness.
##
## This comment used to claim ticks were "the *only* clock" — that claim was
## the defect in audit #31, not the code. The split is priced in
## `docs/scoping/r1-two-clocks.md` (three migration options costed, a fourth
## disqualified by measurement); `test_tick_loop_wiring.gd` sub-cases 7-9 pin
## this wiring two-sided, so moving the three systems onto ticks reddens the
## suite and forces the author to say so.
##
## Usage:
##   func _ready() -> void:
##       TickSystem.tick.connect(_on_tick)
##   func _on_tick(tick_no: int) -> void:
##       ...
##
## `tick_no` is monotonically increasing across the session. Use it for
## periodic logic ("every 60 ticks = once per 3 seconds").

signal tick(tick_no: int)

const TICKS_PER_SECOND: int = 20
const TICK_INTERVAL_SEC: float = 1.0 / float(TICKS_PER_SECOND)

var current_tick: int = 0
var paused: bool = false

# Tick rate multiplier (session-dev-console). Console `tick_speed N`
# sets this to N to fast-forward (or slow down) simulation. 1.0 = normal
# 20 tps, 2.0 = 40 tps, 0.5 = 10 tps. Clamped at the console layer to
# [0.1, 10.0] — values above 10× start breaking tick-dependent systems
# (belt timing, animations, etc.). Default 1.0 preserves prior behavior.
var tick_rate_multiplier: float = 1.0

var _accumulator: float = 0.0

func _process(delta: float) -> void:
	if paused:
		return
	# Multiplier applies on the accumulator-feed step rather than the
	# threshold so paused/un-paused transitions don't lose accumulated
	# fractional progress. multiplier=2.0 → accumulator fills twice as
	# fast → twice as many ticks emit per real second.
	_accumulator += delta * tick_rate_multiplier
	# Advance as many ticks as the accumulator allows. This keeps simulation
	# at a consistent 20Hz × multiplier even if the renderer hitches.
	while _accumulator >= TICK_INTERVAL_SEC:
		_accumulator -= TICK_INTERVAL_SEC
		current_tick += 1
		tick.emit(current_tick)

func reset() -> void:
	current_tick = 0
	_accumulator = 0.0
