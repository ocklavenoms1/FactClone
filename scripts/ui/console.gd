class_name DevConsole
extends Control

## Dev Console — in-game command console for development testing
## (session-dev-console).
##
## Press backtick (`) to toggle. Debug-build-only — gated by
## OS.is_debug_build() at activation time in main.gd.
##
## Replaces the "build a planter chain to test the next thing" loop with
## one-line state setup. Future sessions (Session 4 wasteland, Session 5
## legumes, save migration framework) lean on this for fast iteration.
##
## Architecture (see PROJECT_LOG session-dev-console + NOTES.md design pass):
##   - Tokenize-and-dispatch parser: split input on whitespace, first
##     token = command name, rest = String args. Each command is a
##     method that takes Array[String] and returns String (output or
##     error).
##   - 12 commands: help, seed, tile, give, place, destroy, tp, set_soil,
##     deplete_area, fertilize, clear, tick_speed.
##   - In-memory history (up/down arrow); not persisted across sessions.
##   - Scrollback buffer ~200 lines, ~30 visible.

# Visual constants.
const PANEL_BG: Color = Color(0.0, 0.0, 0.0, 0.85)
const PANEL_BORDER: Color = Color(0.3, 0.4, 0.3, 0.95)
const TEXT_COLOR: Color = Color(0.85, 0.92, 0.85)
const ECHO_COLOR: Color = Color(0.65, 0.85, 1.0)        # user-typed lines
const ERROR_COLOR: Color = Color(1.0, 0.55, 0.40)       # error output
const PROMPT: String = "> "
const FONT_SIZE: int = 14
const SCROLLBACK_VISIBLE_LINES: int = 30
const SCROLLBACK_BUFFER_MAX: int = 200
const HISTORY_MAX: int = 50
const PANEL_HEIGHT_FRACTION: float = 0.40   # bottom 40% of viewport

# Tick speed clamp (per design Q3 addition).
const TICK_SPEED_MIN: float = 0.1
const TICK_SPEED_MAX: float = 10.0

# Wire references to game state — set by main.gd at _ready.
var grid_world: Node2D = null
var player: Node2D = null
var player_inventory: Inventory = null

# Scrollback (output history) — Array of {text: String, color: Color}.
var _scrollback: Array = []
# Command history — Array[String] of past commands. Up/down navigates.
var _history: Array = []
var _history_index: int = -1   # -1 = not navigating; >=0 = current pos in history

# UI nodes (built in _ready).
var _input_field: LineEdit = null
var _output_label: RichTextLabel = null

# Command registry — populated in _ready() so Items.Type / Buildings.Type
# enums are loaded. Each entry: { fn: String (method name), usage: String,
# help: String }.
var _commands: Dictionary = {}

func _ready() -> void:
	# Layer + sizing — bottom 40% of viewport, full width.
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0 - PANEL_HEIGHT_FRACTION
	anchor_bottom = 1.0
	visible = false

	# Background panel + border (drawn via _draw).
	# Output scrollback (RichTextLabel for color-per-line support).
	_output_label = RichTextLabel.new()
	_output_label.bbcode_enabled = true
	_output_label.scroll_active = true
	_output_label.scroll_following = true
	_output_label.fit_content = false
	_output_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_output_label.add_theme_color_override("default_color", TEXT_COLOR)
	_output_label.anchor_left = 0.0
	_output_label.anchor_right = 1.0
	_output_label.anchor_top = 0.0
	_output_label.anchor_bottom = 1.0
	_output_label.offset_left = 8
	_output_label.offset_right = -8
	_output_label.offset_top = 8
	_output_label.offset_bottom = -36   # leave room for input line
	_output_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_output_label)

	# Input LineEdit at the bottom.
	_input_field = LineEdit.new()
	_input_field.placeholder_text = "type 'help' for commands"
	_input_field.add_theme_font_size_override("font_size", FONT_SIZE)
	_input_field.add_theme_color_override("font_color", TEXT_COLOR)
	_input_field.anchor_left = 0.0
	_input_field.anchor_right = 1.0
	_input_field.anchor_top = 1.0
	_input_field.anchor_bottom = 1.0
	_input_field.offset_left = 8
	_input_field.offset_right = -8
	_input_field.offset_top = -28
	_input_field.offset_bottom = -4
	_input_field.text_submitted.connect(_on_input_field_submitted)
	add_child(_input_field)

	_register_commands()

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, PANEL_BG, true)
	# Top border separator.
	draw_line(Vector2(0, 0), Vector2(size.x, 0), PANEL_BORDER, 2.0)

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		_close()
	else:
		_open()

func _open() -> void:
	visible = true
	_input_field.grab_focus()
	_input_field.clear()
	_history_index = -1
	queue_redraw()

func _close() -> void:
	visible = false
	_input_field.release_focus()

# ---------- input ----------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Up / Down arrow walk through history.
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_history_navigate(-1)
			get_viewport().set_input_field_as_handled()
		elif event.keycode == KEY_DOWN:
			_history_navigate(+1)
			get_viewport().set_input_field_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_field_as_handled()

func _history_navigate(direction: int) -> void:
	if _history.is_empty():
		return
	if _history_index == -1:
		# Start at most-recent on first up-press; ignore down-press.
		if direction < 0:
			_history_index = _history.size() - 1
		else:
			return
	else:
		_history_index = clamp(_history_index + direction, 0, _history.size() - 1)
	_input_field.text = _history[_history_index]
	_input_field.caret_column = _input_field.text.length()

func _on_input_field_submitted(line: String) -> void:
	var trimmed: String = line.strip_edges()
	_input_field.clear()
	_history_index = -1
	if trimmed == "":
		return
	# Echo the typed command in scrollback.
	_append_line(PROMPT + trimmed, ECHO_COLOR)
	# Push to history (no consecutive duplicates).
	if _history.is_empty() or _history.back() != trimmed:
		_history.append(trimmed)
		if _history.size() > HISTORY_MAX:
			_history.pop_front()
	# Execute and append result.
	var result: String = execute(trimmed)
	if result != "":
		# Heuristic: if first word is "Error" / starts with "Unknown"/"Usage"/etc.,
		# render in error color. Otherwise default. Cheap classifier.
		var color: Color = ERROR_COLOR if _looks_like_error(result) else TEXT_COLOR
		_append_line(result, color)

static func _looks_like_error(text: String) -> bool:
	var lower: String = text.to_lower()
	return lower.begins_with("unknown") \
		or lower.begins_with("usage") \
		or lower.begins_with("error") \
		or lower.begins_with("cannot") \
		or lower.begins_with("not found") \
		or lower.begins_with("tile (") and lower.find("out of") >= 0 \
		or lower.find("must be between") >= 0 \
		or lower.find("is not a number") >= 0 \
		or lower.begins_with("item not found") \
		or lower.begins_with("building not found") \
		or lower.begins_with("no building")

# ---------- output ----------

func _append_line(text: String, color: Color = TEXT_COLOR) -> void:
	_scrollback.append({"text": text, "color": color})
	if _scrollback.size() > SCROLLBACK_BUFFER_MAX:
		_scrollback.pop_front()
	# Render via bbcode for per-line color.
	var bbcode_color: String = _color_to_bbcode(color)
	_output_label.append_text("[color=%s]%s[/color]\n" % [bbcode_color, text.replace("[", "[lb]")])

static func _color_to_bbcode(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]

# ---------- parser + dispatch ----------

## Public for testing — returns the output string for a single command line.
## No side effects on UI (scrollback / history); pure execute path.
func execute(line: String) -> String:
	var tokens: PackedStringArray = line.strip_edges().split(" ", false)
	if tokens.is_empty():
		return ""
	var cmd_name: String = tokens[0].to_lower()
	var args: Array = []
	for i in range(1, tokens.size()):
		args.append(tokens[i])
	if not _commands.has(cmd_name):
		return "Unknown command: %s. Type 'help' for list." % cmd_name
	var entry: Dictionary = _commands[cmd_name]
	var fn: Callable = Callable(self, entry["fn"])
	return fn.call(args)

func _register_commands() -> void:
	# Sorted in design-pass display order. `help` lists them alphabetically
	# (uses Dictionary iteration order — GDScript preserves insertion order,
	# so we register them alphabetically here).
	_commands = {
		"clear": {
			"fn": "_cmd_clear",
			"usage": "clear inventory | clear chest <x> <y>",
			"help": "Wipe the player inventory or a named chest's contents. Explicit target required.",
		},
		"deplete_area": {
			"fn": "_cmd_deplete_area",
			"usage": "deplete_area <x> <y> <radius> [amount]",
			"help": "Bulk soil depletion across a Chebyshev-distance ≤ radius square. Default amount = 50.",
		},
		"destroy": {
			"fn": "_cmd_destroy",
			"usage": "destroy <x> <y>",
			"help": "Remove the building at tile (x, y). No drops — clean test removal.",
		},
		"fertilize": {
			"fn": "_cmd_fertilize",
			"usage": "fertilize <x> <y> <tier>",
			"help": "Direct write to tile_fertilizer_state. tier = low or mid. Bypasses inventory check.",
		},
		"give": {
			"fn": "_cmd_give",
			"usage": "give <item> <count>",
			"help": "Add count items to player inventory. Item is the enum name (wheat, compost_low, ...).",
		},
		"help": {
			"fn": "_cmd_help",
			"usage": "help [<cmd>]",
			"help": "List all commands, or show usage for one command.",
		},
		"place": {
			"fn": "_cmd_place",
			"usage": "place <building> <x> <y> [dir]",
			"help": "Place a building at tile (x, y). dir = E|S|W|N or 0|1|2|3. Bypasses overlay check.",
		},
		"seed": {
			"fn": "_cmd_seed",
			"usage": "seed",
			"help": "Print the current world seed.",
		},
		"set_soil": {
			"fn": "_cmd_set_soil",
			"usage": "set_soil <x> <y> <value>",
			"help": "Direct write to tile_soil_modifications. value clamped to 0..100. Skips falloff math.",
		},
		"tick_speed": {
			"fn": "_cmd_tick_speed",
			"usage": "tick_speed <multiplier>",
			"help": "Multiply tick rate. 1.0 = normal, 2.0 = 2× speed, 0.5 = half. Clamped to [0.1, 10.0].",
		},
		"tile": {
			"fn": "_cmd_tile",
			"usage": "tile <x> <y> [radius]",
			"help": "Print tile state at (x, y). With radius > 0, prints a (2r+1)×(2r+1) grid of soil values.",
		},
		"tp": {
			"fn": "_cmd_tp",
			"usage": "tp <x> <y>",
			"help": "Teleport the player to tile (x, y).",
		},
		"wasteland": {
			"fn": "_cmd_wasteland",
			"usage": "wasteland <x> <y>",
			"help": "Force tile (x, y) into scarred wasteland state. Useful for testing wasteland visuals + Premium Compost recovery without setting up active planters to keep soil at 0. Soil is also forced to 0.",
		},
	}

# ---------- arg-parsing helpers ----------

## Parse a string as an int. Returns [success, value]. Caller checks success.
static func _parse_int(s: String) -> Array:
	if s.is_valid_int():
		return [true, int(s)]
	return [false, 0]

static func _parse_float(s: String) -> Array:
	if s.is_valid_float():
		return [true, float(s)]
	return [false, 0.0]

## Resolve an item name (case-insensitive) to Items.Type, or -1 if unknown.
static func _resolve_item(name: String) -> int:
	var upper: String = name.to_upper()
	if Items.Type.keys().has(upper):
		return Items.Type[upper]
	return -1

## Resolve a building name (case-insensitive) to Buildings.Type, or -1 if unknown.
static func _resolve_building(name: String) -> int:
	var upper: String = name.to_upper()
	if Buildings.Type.keys().has(upper):
		return Buildings.Type[upper]
	return -1

## Resolve a direction string (E/S/W/N or 0..3) to Belt.DIR_*, or -1 if invalid.
static func _resolve_dir(s: String) -> int:
	var lower: String = s.to_lower()
	match lower:
		"e", "0": return Belt.DIR_E
		"s", "1": return Belt.DIR_S
		"w", "2": return Belt.DIR_W
		"n", "3": return Belt.DIR_N
	return -1

## Tile-bounds check: WORLD_MIN <= pos < WORLD_MAX (per WorldGenerator).
static func _in_world_bounds(pos: Vector2i) -> bool:
	return pos.x >= WorldGenerator.WORLD_MIN and pos.x < WorldGenerator.WORLD_MAX \
		and pos.y >= WorldGenerator.WORLD_MIN and pos.y < WorldGenerator.WORLD_MAX

# ---------- command implementations ----------

func _cmd_help(args: Array) -> String:
	if args.size() == 0:
		var lines: Array = ["Commands (type 'help <cmd>' for usage):"]
		var names: Array = _commands.keys()
		names.sort()
		for name in names:
			lines.append("  %s" % name)
		return "\n".join(lines)
	if args.size() != 1:
		return "Usage: help [<cmd>]"
	var cmd: String = String(args[0]).to_lower()
	if not _commands.has(cmd):
		return "Unknown command: %s" % cmd
	var entry: Dictionary = _commands[cmd]
	return "Usage: %s\n%s" % [entry["usage"], entry["help"]]

func _cmd_seed(args: Array) -> String:
	if args.size() != 0:
		return "Usage: seed"
	if grid_world == null:
		return "Cannot read seed — grid_world not wired."
	return "World seed: %d" % grid_world.world_seed

func _cmd_give(args: Array) -> String:
	if args.size() != 2:
		return "Usage: give <item> <count>"
	var item: int = _resolve_item(String(args[0]))
	if item < 0:
		return "Item not found: '%s'. Try 'help give'." % args[0]
	var count_parsed: Array = _parse_int(String(args[1]))
	if not count_parsed[0]:
		return "'%s' is not a number. Usage: give <item> <count>" % args[1]
	var count: int = count_parsed[1]
	if count <= 0:
		return "Count must be > 0 (got %d)." % count
	if player_inventory == null:
		return "Cannot give — player_inventory not wired."
	var added: int = player_inventory.add(item, count)
	if added == count:
		return "Added %d× %s to inventory." % [added, Items.name_of(item)]
	return "Added %d× %s (inventory partially full — %d items dropped)." % [added, Items.name_of(item), count - added]

func _cmd_tp(args: Array) -> String:
	if args.size() != 2:
		return "Usage: tp <x> <y>"
	var x_parsed: Array = _parse_int(String(args[0]))
	var y_parsed: Array = _parse_int(String(args[1]))
	if not x_parsed[0] or not y_parsed[0]:
		return "Usage: tp <x> <y> (both args must be integers)"
	var pos: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	if not _in_world_bounds(pos):
		return "Tile %s is outside world bounds [%d, %d)." % [str(pos), WorldGenerator.WORLD_MIN, WorldGenerator.WORLD_MAX]
	if player == null or grid_world == null:
		return "Cannot teleport — player/grid_world not wired."
	player.global_position = grid_world.tile_to_world_center(pos)
	return "Player → tile %s." % str(pos)

func _cmd_set_soil(args: Array) -> String:
	if args.size() != 3:
		return "Usage: set_soil <x> <y> <value>"
	var x_parsed: Array = _parse_int(String(args[0]))
	var y_parsed: Array = _parse_int(String(args[1]))
	var v_parsed: Array = _parse_int(String(args[2]))
	if not x_parsed[0] or not y_parsed[0] or not v_parsed[0]:
		return "Usage: set_soil <x> <y> <value> (all args must be integers)"
	var pos: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	if not _in_world_bounds(pos):
		return "Tile %s is outside world bounds." % str(pos)
	if grid_world == null:
		return "Cannot set soil — grid_world not wired."
	var v: int = clamp(v_parsed[1], 0, GridWorld.TILE_SOIL_FULL)
	if v >= GridWorld.TILE_SOIL_FULL:
		grid_world.tile_soil_modifications.erase(pos)
		grid_world.tile_regen_progress.erase(pos)
	else:
		grid_world.tile_soil_modifications[pos] = v
	return "Tile %s soil → %d." % [str(pos), v]

func _cmd_deplete_area(args: Array) -> String:
	if args.size() < 3 or args.size() > 4:
		return "Usage: deplete_area <x> <y> <radius> [amount]"
	var x_parsed: Array = _parse_int(String(args[0]))
	var y_parsed: Array = _parse_int(String(args[1]))
	var r_parsed: Array = _parse_int(String(args[2]))
	if not x_parsed[0] or not y_parsed[0] or not r_parsed[0]:
		return "Usage: deplete_area <x> <y> <radius> [amount] (x, y, radius must be integers)"
	var amount: int = 50
	if args.size() == 4:
		var a_parsed: Array = _parse_int(String(args[3]))
		if not a_parsed[0]:
			return "Amount '%s' is not a number. Usage: deplete_area <x> <y> <radius> [amount]" % args[3]
		amount = a_parsed[1]
	var center: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	var radius: int = r_parsed[1]
	if radius < 0:
		return "Radius must be >= 0 (got %d)." % radius
	if grid_world == null:
		return "Cannot deplete — grid_world not wired."
	var n: int = 0
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos: Vector2i = Vector2i(center.x + dx, center.y + dy)
			if not _in_world_bounds(pos):
				continue
			grid_world.deplete_tile_soil(pos, amount)
			n += 1
	return "Depleted %d tiles around %s by %d." % [n, str(center), amount]

func _cmd_fertilize(args: Array) -> String:
	if args.size() != 3:
		return "Usage: fertilize <x> <y> <tier> (tier = low | mid | high)"
	var x_parsed: Array = _parse_int(String(args[0]))
	var y_parsed: Array = _parse_int(String(args[1]))
	if not x_parsed[0] or not y_parsed[0]:
		return "Usage: fertilize <x> <y> <tier> (x, y must be integers)"
	var tier_str: String = String(args[2]).to_lower()
	var tier: int = -1
	if tier_str == "low":
		tier = Items.Type.COMPOST_LOW
	elif tier_str == "mid":
		tier = Items.Type.COMPOST_MID
	elif tier_str == "high":
		tier = Items.Type.COMPOST_HIGH
	else:
		return "Tier must be 'low', 'mid', or 'high' (got '%s')." % args[2]
	var pos: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	if not _in_world_bounds(pos):
		return "Tile %s is outside world bounds." % str(pos)
	if grid_world == null:
		return "Cannot fertilize — grid_world not wired."
	# Direct write — bypasses stacking rules of try_apply_fertilizer so the
	# console always does what the user asked for. (No "rejected because
	# higher tier already there" surprise in dev workflow.)
	grid_world.tile_fertilizer_state[pos] = {
		"tier": tier,
		"remaining": GridWorld.fertilizer_duration(tier),
	}
	return "Tile %s fertilized: %s (%.1fs)." % [str(pos), Items.name_of(tier), GridWorld.fertilizer_duration(tier)]

func _cmd_place(args: Array) -> String:
	if args.size() < 3 or args.size() > 4:
		return "Usage: place <building> <x> <y> [dir]"
	var btype: int = _resolve_building(String(args[0]))
	if btype < 0:
		return "Building not found: '%s'. Try 'help place'." % args[0]
	var x_parsed: Array = _parse_int(String(args[1]))
	var y_parsed: Array = _parse_int(String(args[2]))
	if not x_parsed[0] or not y_parsed[0]:
		return "Usage: place <building> <x> <y> [dir] (x, y must be integers)"
	var dir: int = Belt.DIR_E
	if args.size() == 4:
		dir = _resolve_dir(String(args[3]))
		if dir < 0:
			return "Direction '%s' invalid. Use E|S|W|N or 0|1|2|3." % args[3]
	var pos: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	if not _in_world_bounds(pos):
		return "Tile %s is outside world bounds." % str(pos)
	if grid_world == null:
		return "Cannot place — grid_world not wired."
	# Bypass requires_overlay check — console always succeeds (or surfaces
	# a real error like "tile occupied"). Use the existing `place_building`
	# but swap the tile's overlay if needed first.
	if not grid_world.place_building(btype, pos, dir):
		# place_building set last_building_place_error — surface it.
		var err: String = grid_world.last_building_place_error
		# Auto-set the FIRST non-NONE overlay from the building's
		# requires_overlay list. Buildings differ — Planter wants
		# SOIL_TILLED, Mill wants STONE/PATH, etc. Try the building's
		# own preferred overlay rather than blanket STONE.
		var pre_overlay: int = grid_world.overlay_at(pos)
		var data: Dictionary = Buildings.DATA.get(btype, {})
		var requires_overlay: Array = data.get("requires_overlay", [])
		var picked_overlay: int = -1
		for ov in requires_overlay:
			if int(ov) != Terrain.Overlay.NONE:
				picked_overlay = int(ov)
				break
		if picked_overlay >= 0:
			grid_world.set_overlay(pos, picked_overlay)
			if grid_world.place_building(btype, pos, dir):
				return "Placed %s at %s (auto-set %s overlay)." % [Buildings.name_of(btype), str(pos), Terrain.overlay_name(picked_overlay)]
			# Restore overlay; placement still fails for some other reason.
			grid_world.set_overlay(pos, pre_overlay)
		return "Cannot place %s at %s: %s" % [Buildings.name_of(btype), str(pos), err]
	return "Placed %s at %s (dir %s)." % [Buildings.name_of(btype), str(pos), Belt.DIR_NAMES[dir]]

func _cmd_destroy(args: Array) -> String:
	if args.size() != 2:
		return "Usage: destroy <x> <y>"
	var x_parsed: Array = _parse_int(String(args[0]))
	var y_parsed: Array = _parse_int(String(args[1]))
	if not x_parsed[0] or not y_parsed[0]:
		return "Usage: destroy <x> <y> (both args must be integers)"
	var pos: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	if not _in_world_bounds(pos):
		return "Tile %s is outside world bounds." % str(pos)
	if grid_world == null:
		return "Cannot destroy — grid_world not wired."
	# Resolve to the building's anchor — multi-tile buildings may be
	# clicked at a non-anchor cell; remove_building_at expects the anchor.
	if not grid_world.has_building_at(pos):
		return "No building at %s." % str(pos)
	var b: Building = grid_world.building_at(pos)
	var anchor: Vector2i = b.anchor if b != null else pos
	var bname: String = Buildings.name_of(b.type) if b != null else "(unknown)"
	if grid_world.remove_building_at(anchor):
		return "Removed %s from %s." % [bname, str(anchor)]
	return "Cannot remove building at %s." % str(pos)

func _cmd_clear(args: Array) -> String:
	if args.size() < 1:
		return "Usage: clear inventory | clear chest <x> <y>"
	var target: String = String(args[0]).to_lower()
	if target == "inventory":
		if args.size() != 1:
			return "Usage: clear inventory"
		if player_inventory == null:
			return "Cannot clear — player_inventory not wired."
		var slots_n: int = player_inventory.slots.size()
		for s in player_inventory.slots:
			s.clear()
		return "Cleared player inventory (%d slots)." % slots_n
	elif target == "chest":
		if args.size() != 3:
			return "Usage: clear chest <x> <y>"
		var x_parsed: Array = _parse_int(String(args[1]))
		var y_parsed: Array = _parse_int(String(args[2]))
		if not x_parsed[0] or not y_parsed[0]:
			return "Usage: clear chest <x> <y> (x, y must be integers)"
		var pos: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
		if grid_world == null:
			return "Cannot clear — grid_world not wired."
		if not grid_world.has_building_at(pos):
			return "No building at %s." % str(pos)
		var b: Building = grid_world.building_at(pos)
		if b == null or b.type != Buildings.Type.CHEST:
			return "Building at %s is not a Chest." % str(pos)
		# Chest stores items in `bag` field as Array of [type, count].
		b.state["bag"] = []
		return "Cleared chest at %s." % str(pos)
	return "Usage: clear inventory | clear chest <x> <y>"

func _cmd_tick_speed(args: Array) -> String:
	if args.size() != 1:
		return "Usage: tick_speed <multiplier>"
	var m_parsed: Array = _parse_float(String(args[0]))
	if not m_parsed[0]:
		return "'%s' is not a number. Usage: tick_speed <multiplier>" % args[0]
	var m: float = m_parsed[1]
	if m < TICK_SPEED_MIN or m > TICK_SPEED_MAX:
		return "tick_speed must be between %.1f and %.1f (got %s). Multipliers above %dx may break tick-dependent systems." % [TICK_SPEED_MIN, TICK_SPEED_MAX, args[0], int(TICK_SPEED_MAX)]
	TickSystem.tick_rate_multiplier = m
	return "Tick speed → %.2f× (was %.2fx)." % [m, TickSystem.tick_rate_multiplier]

func _cmd_wasteland(args: Array) -> String:
	if args.size() != 2:
		return "Usage: wasteland <x> <y>"
	var x_parsed: Array = _parse_int(String(args[0]))
	var y_parsed: Array = _parse_int(String(args[1]))
	if not x_parsed[0] or not y_parsed[0]:
		return "Usage: wasteland <x> <y> (both args must be integers)"
	var pos: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	if not _in_world_bounds(pos):
		return "Tile %s is outside world bounds." % str(pos)
	if grid_world == null:
		return "Cannot wasteland — grid_world not wired."
	# Direct write — soil to 0 + scarred flag set. Bypasses grace timer
	# entirely. Useful for testing wasteland mechanics without setting
	# up active planters to keep soil pinned at 0 for 60 sec.
	grid_world.tile_soil_modifications[pos] = 0
	grid_world.tile_wasteland_state[pos] = {"scarred": true, "decay_remaining": 0.0}
	grid_world.tile_regen_progress.erase(pos)
	return "Tile %s → WASTELAND (scarred). Apply Premium Compost to restore." % str(pos)

func _cmd_tile(args: Array) -> String:
	if args.size() < 2 or args.size() > 3:
		return "Usage: tile <x> <y> [radius]"
	var x_parsed: Array = _parse_int(String(args[0]))
	var y_parsed: Array = _parse_int(String(args[1]))
	if not x_parsed[0] or not y_parsed[0]:
		return "Usage: tile <x> <y> [radius] (x, y must be integers)"
	var radius: int = 0
	if args.size() == 3:
		var r_parsed: Array = _parse_int(String(args[2]))
		if not r_parsed[0]:
			return "Radius '%s' is not a number." % args[2]
		radius = r_parsed[1]
	if radius < 0:
		return "Radius must be >= 0 (got %d)." % radius
	if grid_world == null:
		return "Cannot query — grid_world not wired."
	var center: Vector2i = Vector2i(x_parsed[1], y_parsed[1])
	if radius == 0:
		# Single-tile detail mode.
		return _format_tile_detail(center)
	# Multi-tile grid mode — print a (2r+1)×(2r+1) grid of soil values.
	return _format_tile_grid(center, radius)

func _format_tile_detail(pos: Vector2i) -> String:
	var lines: Array = ["Tile %s:" % str(pos)]
	if not _in_world_bounds(pos):
		lines.append("  (out of world bounds)")
		return "\n".join(lines)
	var soil: int = grid_world.tile_soil_health(pos)
	lines.append("  Soil: %d / %d" % [soil, GridWorld.TILE_SOIL_FULL])
	var fert_tier: int = grid_world.tile_fertilizer_tier(pos)
	if fert_tier >= 0:
		var remaining: float = grid_world.tile_fertilizer_remaining(pos)
		lines.append("  Fertilizer: %s (%.1fs remaining)" % [Items.name_of(fert_tier), remaining])
	# Wasteland line (Session 4) — show scarred / in-grace / no.
	if grid_world.is_wasteland_at(pos):
		lines.append("  Wasteland: SCARRED (apply Premium Compost to restore)")
	else:
		var grace: float = grid_world.tile_wasteland_grace_remaining(pos)
		if grace > 0.0:
			lines.append("  Wasteland: in grace, will scar in %.1fs" % grace)
	# Base/overlay names instead of raw enum ints.
	var base: int = grid_world.base_at(pos)
	var overlay: int = grid_world.overlay_at(pos)
	lines.append("  Base: %s, Overlay: %s" % [Terrain.base_name(base), Terrain.overlay_name(overlay)])
	if grid_world.has_building_at(pos):
		var b: Building = grid_world.building_at(pos)
		var bname: String = Buildings.name_of(b.type) if b != null else "(?)"
		lines.append("  Building: %s (anchor %s)" % [bname, str(b.anchor) if b != null else "?"])
	return "\n".join(lines)

func _format_tile_grid(center: Vector2i, radius: int) -> String:
	# Soil values rendered as 3-char-wide cells; building presence marked with
	# a leading 'B'; out-of-bounds shown as '---'. Fertilized tiles get a
	# trailing 'L' or 'M' (LOW/MID).
	var lines: Array = ["Soil grid centered on %s, radius %d:" % [str(center), radius]]
	# Header row: x coordinates.
	var header: String = "      "
	for dx in range(-radius, radius + 1):
		header += "%4d" % (center.x + dx)
	lines.append(header)
	for dy in range(-radius, radius + 1):
		var row: String = "%5d " % (center.y + dy)
		for dx in range(-radius, radius + 1):
			var pos: Vector2i = Vector2i(center.x + dx, center.y + dy)
			if not _in_world_bounds(pos):
				row += " ---"
				continue
			var soil: int = grid_world.tile_soil_health(pos)
			var marker: String = " "
			if grid_world.has_building_at(pos):
				marker = "B"
			else:
				var fert_tier: int = grid_world.tile_fertilizer_tier(pos)
				if fert_tier == Items.Type.COMPOST_LOW:
					marker = "L"
				elif fert_tier == Items.Type.COMPOST_MID:
					marker = "M"
			row += "%3d%s" % [soil, marker]
		lines.append(row)
	lines.append("(B = building, L = LOW fertilizer, M = MID fertilizer)")
	return "\n".join(lines)
