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

var _accumulator: float = 0.0

func _process(delta: float) -> void:
	if paused:
		return
	_accumulator += delta
	# Advance as many ticks as the accumulator allows. This keeps simulation
	# at a consistent 20Hz even if the renderer hitches.
	while _accumulator >= TICK_INTERVAL_SEC:
		_accumulator -= TICK_INTERVAL_SEC
		current_tick += 1
		tick.emit(current_tick)

func reset() -> void:
	current_tick = 0
	_accumulator = 0.0
