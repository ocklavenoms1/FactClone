extends Node

## Global simulation heartbeat. Autoloaded as TickSystem.
##
## Emits `tick` 20 times per second (every 50ms), independent of frame rate.
## This is the *only* clock the simulation should care about. Buildings,
## crops, weather, etc. all advance on tick boundaries — never on _process.
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
