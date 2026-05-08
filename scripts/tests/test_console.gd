extends RefCounted

## Dev Console parser + end-to-end command tests (session-dev-console).
##
## Two layers of coverage per design pass Q8:
##   1. Parser-layer (cheap): tokenization, unknown command, item/building
##      name resolution, wrong-arg-count messages, type-coerce errors.
##   2. End-to-end (minimal): one item-mutation command (give) and one
##      world-state command (tp) — proves dispatcher wires into game
##      state correctly. Exhaustive per-command tests skipped — these
##      are dev-only commands; manual PAUSE smoke covers the rest.

const ConsoleScript = preload("res://scripts/ui/console.gd")
const GridWorldScript = preload("res://scripts/world/grid_world.gd")

static func test_name() -> String:
	return "dev console (parser + give + tp end-to-end)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- 1. Parser tokenization + dispatch ----------
	# Build a console node, but don't add to scene tree (we only call
	# `execute` directly — UI layer untouched).
	var console = ConsoleScript.new()
	parent.add_child(console)

	# Empty input → empty output, no error.
	_check(failures, console.execute("") == "",
		"empty input should return empty string")
	_check(failures, console.execute("   ") == "",
		"whitespace-only input should return empty string")

	# Unknown command.
	var unknown: String = console.execute("flarp wheat 10")
	_check(failures, unknown.begins_with("Unknown command: flarp"),
		"unknown command should produce 'Unknown command:' prefix, got '%s'" % unknown)

	# Help works without world wiring.
	var help_out: String = console.execute("help")
	_check(failures, help_out.find("give") >= 0 and help_out.find("place") >= 0 and help_out.find("destroy") >= 0,
		"help should list give/place/destroy among commands, got '%s'" % help_out)
	# help <cmd> should show usage.
	var help_give: String = console.execute("help give")
	_check(failures, help_give.find("Usage: give <item> <count>") >= 0,
		"help give should show usage line, got '%s'" % help_give)
	# help <unknown> should error.
	var help_unknown: String = console.execute("help xyzzy")
	_check(failures, help_unknown.begins_with("Unknown command: xyzzy"),
		"help on unknown command should error")

	# Item name resolution (case-insensitive).
	_check(failures, ConsoleScript._resolve_item("wheat") == Items.Type.WHEAT,
		"_resolve_item lowercase 'wheat' → Items.Type.WHEAT")
	_check(failures, ConsoleScript._resolve_item("WHEAT") == Items.Type.WHEAT,
		"_resolve_item uppercase 'WHEAT' → Items.Type.WHEAT")
	_check(failures, ConsoleScript._resolve_item("compost_low") == Items.Type.COMPOST_LOW,
		"_resolve_item 'compost_low' → COMPOST_LOW")
	_check(failures, ConsoleScript._resolve_item("nonsense") == -1,
		"_resolve_item unknown returns -1")

	# Building name resolution.
	_check(failures, ConsoleScript._resolve_building("composter") == Buildings.Type.COMPOSTER,
		"_resolve_building 'composter' → COMPOSTER")
	_check(failures, ConsoleScript._resolve_building("FERTILIZER_APPLICATOR") == Buildings.Type.FERTILIZER_APPLICATOR,
		"_resolve_building uppercase 'FERTILIZER_APPLICATOR' resolves")
	_check(failures, ConsoleScript._resolve_building("flubber") == -1,
		"_resolve_building unknown returns -1")

	# Direction resolution.
	_check(failures, ConsoleScript._resolve_dir("E") == Belt.DIR_E, "_resolve_dir 'E' → DIR_E")
	_check(failures, ConsoleScript._resolve_dir("e") == Belt.DIR_E, "_resolve_dir lowercase 'e' → DIR_E")
	_check(failures, ConsoleScript._resolve_dir("0") == Belt.DIR_E, "_resolve_dir '0' → DIR_E")
	_check(failures, ConsoleScript._resolve_dir("3") == Belt.DIR_N, "_resolve_dir '3' → DIR_N")
	_check(failures, ConsoleScript._resolve_dir("garbage") == -1, "_resolve_dir invalid returns -1")

	# Wrong arg count.
	var no_args: String = console.execute("give")
	_check(failures, no_args.begins_with("Usage: give"),
		"give with no args → 'Usage:' message, got '%s'" % no_args)
	var too_many: String = console.execute("give wheat 10 extra")
	_check(failures, too_many.begins_with("Usage: give"),
		"give with extra args → 'Usage:' message, got '%s'" % too_many)

	# Type-coerce failure.
	var bad_count: String = console.execute("give wheat banana")
	_check(failures, bad_count.find("not a number") >= 0,
		"give with non-numeric count → 'not a number', got '%s'" % bad_count)

	# Domain failure: unknown item.
	var bad_item: String = console.execute("give flarpitem 10")
	_check(failures, bad_item.begins_with("Item not found"),
		"give with unknown item → 'Item not found', got '%s'" % bad_item)

	# Tick speed clamp.
	# Need TickSystem available — it's an autoload, should always be there.
	var ts_too_high: String = console.execute("tick_speed 100")
	_check(failures, ts_too_high.find("must be between") >= 0,
		"tick_speed 100 should error with 'must be between', got '%s'" % ts_too_high)
	var ts_too_low: String = console.execute("tick_speed 0.01")
	_check(failures, ts_too_low.find("must be between") >= 0,
		"tick_speed 0.01 should error, got '%s'" % ts_too_low)
	# Valid tick_speed works.
	var ts_ok: String = console.execute("tick_speed 2")
	_check(failures, ts_ok.find("Tick speed") >= 0,
		"tick_speed 2 should succeed, got '%s'" % ts_ok)
	_check(failures, abs(TickSystem.tick_rate_multiplier - 2.0) < 0.001,
		"tick_speed 2 should set TickSystem.tick_rate_multiplier to 2.0, got %f" % TickSystem.tick_rate_multiplier)
	# Reset for cleanliness.
	console.execute("tick_speed 1")

	console.queue_free()

	# ---------- 2. End-to-end: give → inventory mutation ----------
	console = ConsoleScript.new()
	parent.add_child(console)
	var inv := Inventory.new(16)
	console.player_inventory = inv
	# `give wheat 10` should add 10 wheat.
	var give_out: String = console.execute("give wheat 10")
	_check(failures, inv.total_of(Items.Type.WHEAT) == 10,
		"give wheat 10 should result in 10 wheat in inventory, got %d" % inv.total_of(Items.Type.WHEAT))
	_check(failures, give_out.find("Added 10× Wheat") >= 0,
		"give output should confirm '10× Wheat', got '%s'" % give_out)
	# Stacking: a second give adds to total.
	console.execute("give wheat 5")
	_check(failures, inv.total_of(Items.Type.WHEAT) == 15,
		"second give should bring total to 15, got %d" % inv.total_of(Items.Type.WHEAT))
	# Negative count → error.
	var neg: String = console.execute("give wheat -3")
	_check(failures, neg.find("must be > 0") >= 0,
		"give with negative count should error, got '%s'" % neg)
	console.queue_free()

	# ---------- 3. End-to-end: tp → player position mutation ----------
	console = ConsoleScript.new()
	parent.add_child(console)
	var fake_player := Node2D.new()
	parent.add_child(fake_player)
	fake_player.global_position = Vector2.ZERO
	var world = GridWorldScript.new()
	parent.add_child(world)
	console.player = fake_player
	console.grid_world = world

	var tp_out: String = console.execute("tp 50 50")
	_check(failures, tp_out.find("(50, 50)") >= 0,
		"tp 50 50 output should mention '(50, 50)', got '%s'" % tp_out)
	# Tile (50, 50) center is at (50*32 + 16, 50*32 + 16) = (1616, 1616) per
	# grid_world.tile_to_world_center.
	var expected: Vector2 = Vector2(1616, 1616)
	_check(failures, fake_player.global_position.distance_to(expected) < 0.01,
		"tp 50 50 should put player at world center (1616, 1616), got %s" % str(fake_player.global_position))

	# Out-of-bounds tp.
	var tp_oob: String = console.execute("tp 99999 99999")
	_check(failures, tp_oob.find("outside world bounds") >= 0,
		"tp out-of-bounds should error, got '%s'" % tp_oob)
	# Player should NOT have moved.
	_check(failures, fake_player.global_position.distance_to(expected) < 0.01,
		"out-of-bounds tp should not move player")

	console.queue_free()
	fake_player.queue_free()
	_disconnect(world)
	world.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "all parser + give + tp checks passed" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 5))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

static func _disconnect(world) -> void:
	if world == null:
		return
	if TickSystem.tick.is_connected(world._on_tick):
		TickSystem.tick.disconnect(world._on_tick)
