extends Node2D

## Ground Rendering Phase 1 — reproducible capture harness.
##
## Boots the real game (scenes/main.tscn) in an off-screen window, stages
## the shots, saves PNGs to docs/captures/ground-phase1/ and prints camera
## state for every rendered frame. Run scripts/tools/ground_verify.py
## against the PNGs afterwards.
##
## INVOCATION (from repo root; windowed — NOT --headless, pixels must
## exist; ticks are paused by the harness itself so no --fixed-fps):
##
##   ./tools/Godot_v4.6.3-stable_win64_console.exe --path . \
##       --resolution 1920x1080 --position 6000,6000 \
##       res://scenes/ground_capture.tscn > /tmp/ground_capture.log 2>&1
##
## THE THREE ROUTE C TRAPS (docs/scoping/visual-verification.md:95-109),
## all three honoured here:
##
##   1. Warmup in ticks, not frames — stronger: TickSystem.paused = true is
##      the FIRST statement of _ready, before main.tscn even exists, and
##      the run FAILS if current_tick moved by the end. Nothing tick-driven
##      can animate between captures.
##   2. add_child from _ready fails SILENTLY ("Parent node is busy setting
##      up children") and hands back a flat grey frame that hashes
##      identically. Scene assembly is deferred behind one process_frame
##      await, AND every captured frame is asserted non-flat (100-pixel
##      sample, luminance variance > 0) before it is trusted.
##   3. The off-screen window receives LIVE mouse input (zoom drifted
##      1.5 -> 5.23 -> 0.85 in a recorded run). Input is disabled at the
##      viewport (dynamically — belt) and per-node on main/player/grid
##      (braces), main + player processing is frozen after boot, AND the
##      camera state is printed every frame with a guard that fails the
##      run if it ever differs from what the harness set.

const OUT_DIR: String = "res://docs/captures/ground-phase1"

# The three candidate greens. b is the shader's authored default.
const GREEN_A: Color = Color("2E3A26")
const GREEN_B: Color = Color("2A3830")
const GREEN_C: Color = Color("333D2A")

# Pure-ground staging: a tile band OUTSIDE worldgen bounds (nothing is
# ever generated there — clean grass guaranteed) but INSIDE the +-10000 px
# Background rect (+-312 tiles). Verified per run anyway.
const STAGE_MARGIN_TILES: int = 24

# Target integer pixel offset for the scroll pair (must be >= 200).
const SCROLL_TARGET_PX: float = 240.0

var _main_scene: Node = null
var _grid: Node2D = null
var _player: Node2D = null
var _camera: Camera2D = null
var _background: ColorRect = null
var _hud: CanvasLayer = null

var _frame_no: int = 0
var _expected_cam_pos: Vector2 = Vector2.INF
var _expected_zoom: Vector2 = Vector2.INF
var _drift_detected: bool = false
var _boot_zoom: Vector2 = Vector2.ZERO
var _tick_at_boot: int = -1
var _failed: bool = false
var _meta: Dictionary = {"captures": []}

func _ready() -> void:
	# TRAP 1: freeze the tick clock before anything tick-driven exists.
	TickSystem.paused = true
	_tick_at_boot = TickSystem.current_tick
	print("GROUND_CAPTURE: TickSystem.paused=true at boot, current_tick=%d" % _tick_at_boot)
	# Off-screen backstop (primary is the --position 6000,6000 CLI flag).
	get_window().position = Vector2i(6000, 6000)
	await _run()

func _process(_delta: float) -> void:
	# Per-frame camera evidence + drift guard (TRAP 3).
	_frame_no += 1
	if _camera == null:
		return
	var pos: Vector2 = _camera.global_position
	var zoom: Vector2 = _camera.zoom
	print("FRAME %d cam_pos=(%.2f, %.2f) zoom=(%.4f, %.4f) tick=%d" % [
		_frame_no, pos.x, pos.y, zoom.x, zoom.y, TickSystem.current_tick])
	if _expected_cam_pos != Vector2.INF:
		if pos.distance_to(_expected_cam_pos) > 0.01 \
				or abs(zoom.x - _expected_zoom.x) > 0.0001 \
				or abs(zoom.y - _expected_zoom.y) > 0.0001:
			_drift_detected = true
			print("GROUND_CAPTURE DRIFT: expected cam_pos=(%.2f, %.2f) zoom=(%.4f, %.4f)" % [
				_expected_cam_pos.x, _expected_cam_pos.y, _expected_zoom.x, _expected_zoom.y])

func _fail(msg: String) -> void:
	_failed = true
	push_error("GROUND_CAPTURE FAIL: " + msg)
	print("GROUND_CAPTURE FAIL: " + msg)
	get_tree().quit(1)

func _run() -> void:
	# TRAP 2: leave _ready's setup phase before assembling the scene.
	await get_tree().process_frame

	_main_scene = load("res://scenes/main.tscn").instantiate()
	add_child(_main_scene)
	if not _main_scene.is_inside_tree() or _main_scene.get_child_count() == 0:
		_fail("main.tscn did not assemble (busy-parent silent add_child failure?)")
		return

	_grid = _main_scene.get_node("GridWorld")
	_player = _main_scene.get_node("Player")
	_camera = _main_scene.get_node("Player/Camera")
	_background = _main_scene.get_node("Background")
	_hud = _main_scene.get_node("HUD")

	# TRAP 3: kill input FIRST — the off-screen window gets live mouse input.
	var vp: Viewport = get_viewport()
	if vp.has_method("set_disable_input"):
		vp.call("set_disable_input", true)
		print("GROUND_CAPTURE: viewport input disabled via set_disable_input(true)")
	else:
		print("GROUND_CAPTURE: Viewport.set_disable_input unavailable — relying on per-node disable + drift guard")
	for n in [_main_scene, _player, _grid]:
		n.set_process_input(false)
		n.set_process_unhandled_input(false)
		n.set_process_unhandled_key_input(false)

	# Record the game's default zoom BEFORE freezing anything.
	_boot_zoom = _camera.zoom
	print("GROUND_CAPTURE: GAME ZOOM (camera default) = (%.4f, %.4f), main.target_zoom=%.4f" % [
		_boot_zoom.x, _boot_zoom.y, _main_scene.target_zoom])
	print("GROUND_CAPTURE: world_seed=%d" % _grid.world_seed)

	# Freeze the game loop: no zoom lerp, no hover updates, no harvest
	# polling, no player physics. GridWorld._process stays ON — it owns
	# queue_redraw(); its wall-clock systems (soil regen at 30 s/point)
	# cannot move a SoilLevel band within this run's ~2 s.
	_main_scene.set_process(false)
	_main_scene.set_physics_process(false)
	_player.set_process(false)
	_player.set_physics_process(false)
	_hud.visible = false
	_grid.show_hover = false

	await get_tree().process_frame

	var mat: ShaderMaterial = _background.material as ShaderMaterial
	if mat == null:
		_fail("Background has no ShaderMaterial — main.tscn wiring missing")
		return

	# ---------- pure-ground staging (outside worldgen bounds) ----------
	var stage_tile: Vector2i = _find_clean_ground_stage()
	if _failed:
		return
	var stage_pos: Vector2 = Vector2(stage_tile.x * GridWorld.TILE_SIZE + 16, stage_tile.y * GridWorld.TILE_SIZE + 16)
	print("GROUND_CAPTURE: pure-ground stage tile=%s world=(%.1f, %.1f)" % [str(stage_tile), stage_pos.x, stage_pos.y])

	_grid.visible = false
	_player.visible = false
	_move_camera(stage_pos)

	# ---------- captures 1a/1b/1c: ground alone, three candidates ----------
	var candidates: Array = [
		["ground_green_a.png", GREEN_A],
		["ground_green_b.png", GREEN_B],
		["ground_green_c.png", GREEN_C],
	]
	for pair in candidates:
		mat.set_shader_parameter("base_color", pair[1])
		var ok: bool = await _capture(String(pair[0]))
		if not ok:
			return
	# Restore the authored default for the remaining shots.
	mat.set_shader_parameter("base_color", GREEN_B)

	# ---------- capture 2: composite ----------
	var anchor: Vector2i = _find_clean_composite_patch()
	if _failed:
		return
	print("GROUND_CAPTURE: composite anchor tile=%s" % str(anchor))
	if not _stage_composite(anchor):
		return
	SpriteLibrary.enabled = true
	SpriteLibrary.ensure_loaded()
	for line in SpriteLibrary.manifest_report_lines():
		print("GROUND_CAPTURE sprites: %s" % String(line))
	if not SpriteLibrary.failures().is_empty():
		_fail("SpriteLibrary reported failures: %s" % str(SpriteLibrary.failures()))
		return
	var comp_center: Vector2 = Vector2((anchor.x + 2) * GridWorld.TILE_SIZE + 16, anchor.y * GridWorld.TILE_SIZE + 16)
	_grid.visible = true
	_move_camera(comp_center)
	_deplete_one_ore_in_view(comp_center)
	var comp_ok: bool = await _capture("ground_composite.png")
	SpriteLibrary.enabled = false
	if not comp_ok:
		return

	# ---------- captures 3: scroll pair (world-locked swim test) ----------
	_grid.visible = false
	_move_camera(stage_pos)
	# World->screen scale from the live transforms (stretch x camera zoom).
	var world_to_screen: Transform2D = vp.get_final_transform() * vp.canvas_transform
	var s: float = world_to_screen.get_scale().x
	var world_dx: float = SCROLL_TARGET_PX / s
	var px_check: float = world_dx * s
	print("GROUND_CAPTURE: scroll scale=%.6f world_dx=%.6f px_offset=%.6f" % [s, world_dx, px_check])
	if abs(px_check - round(px_check)) > 0.001 or round(px_check) < 200:
		_fail("scroll pixel offset %f is not a whole number >= 200" % px_check)
		return
	_meta["scroll_px_offset"] = int(round(px_check))
	_meta["scroll_world_dx"] = world_dx
	_meta["world_to_screen_scale"] = s
	if not await _capture("ground_scroll_1.png"):
		return
	_move_camera(stage_pos + Vector2(world_dx, 0.0))
	if not await _capture("ground_scroll_2.png"):
		return

	# ---------- close out ----------
	if TickSystem.current_tick != _tick_at_boot:
		_fail("ticks advanced during capture: %d -> %d" % [_tick_at_boot, TickSystem.current_tick])
		return
	if _drift_detected:
		_fail("camera drifted from harness-set state (see DRIFT lines above)")
		return
	_write_meta()
	print("GROUND_CAPTURE: ALL CAPTURES OK (tick still %d, zoom still (%.4f, %.4f))" % [
		TickSystem.current_tick, _camera.zoom.x, _camera.zoom.y])
	get_tree().quit(0)

func _move_camera(world_pos: Vector2) -> void:
	_player.global_position = world_pos
	_expected_cam_pos = world_pos
	_expected_zoom = _boot_zoom

## One capture: two awaited frames (uniform/scene changes settle, frame
## renders), grab the root viewport, assert non-flat (TRAP 2), save PNG,
## record camera state.
func _capture(file_name: String) -> bool:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		_fail("%s: viewport image is null (headless run? pixels need a window)" % file_name)
		return false
	var stats: Dictionary = _sample_stats(img)
	print("CAPTURE %s: %dx%d cam_pos=(%.2f, %.2f) zoom=(%.4f, %.4f) tick=%d lum_var=%.8f mean_rgb=(%.4f, %.4f, %.4f)" % [
		file_name, img.get_width(), img.get_height(),
		_camera.global_position.x, _camera.global_position.y,
		_camera.zoom.x, _camera.zoom.y, TickSystem.current_tick,
		stats["variance"], stats["mean_r"], stats["mean_g"], stats["mean_b"]])
	if stats["variance"] <= 0.0:
		_fail("%s: FLAT frame (100-sample luminance variance = 0) — untrustworthy capture" % file_name)
		return false
	var abs_dir: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err: int = img.save_png(abs_dir + "/" + file_name)
	if err != OK:
		_fail("%s: save_png error %d" % [file_name, err])
		return false
	_meta["captures"].append({
		"file": file_name,
		"width": img.get_width(),
		"height": img.get_height(),
		"cam_x": _camera.global_position.x,
		"cam_y": _camera.global_position.y,
		"zoom": _camera.zoom.x,
		"tick": TickSystem.current_tick,
	})
	return true

## 100-pixel sample (10x10 grid): luminance variance + channel means.
func _sample_stats(img: Image) -> Dictionary:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var lums: Array = []
	var sum_r: float = 0.0
	var sum_g: float = 0.0
	var sum_b: float = 0.0
	for iy in range(10):
		for ix in range(10):
			var px: Color = img.get_pixel(int((float(ix) + 0.5) * w / 10.0), int((float(iy) + 0.5) * h / 10.0))
			lums.append(0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b)
			sum_r += px.r
			sum_g += px.g
			sum_b += px.b
	var mean: float = 0.0
	for l in lums:
		mean += l
	mean /= lums.size()
	var variance: float = 0.0
	for l in lums:
		variance += (l - mean) * (l - mean)
	variance /= lums.size()
	return {"variance": variance, "mean_r": sum_r / 100.0, "mean_g": sum_g / 100.0, "mean_b": sum_b / 100.0}

## True if nothing world-stateful touches this tile.
func _cell_clean(c: Vector2i) -> bool:
	return not _grid.tiles.has(c) \
		and not _grid.occupied.has(c) \
		and not _grid.tile_soil_modifications.has(c) \
		and not _grid.tile_wasteland_state.has(c) \
		and not _grid.tile_fertilizer_state.has(c)

## Pure-ground stage: east of WORLD_MAX (worldgen never writes there) but
## inside the Background rect. Scanned anyway — a save could carry player
## edits out of bounds. View at default zoom is 40x22.5 tiles; the scan
## window covers view + padding + the scroll offset.
func _find_clean_ground_stage() -> Vector2i:
	var sx: int = WorldGenerator.WORLD_MAX + STAGE_MARGIN_TILES
	for sy in [0, -40, 40, -80, 80]:
		var dirty: bool = false
		for dy in range(-16, 17):
			for dx in range(-26, 33):
				if not _cell_clean(Vector2i(sx + dx, sy + dy)):
					dirty = true
					break
			if dirty:
				break
		if not dirty:
			# Background bound check: view right edge + scroll must stay
			# inside +10000 px.
			var right_edge: float = float(sx * GridWorld.TILE_SIZE + 16) + 640.0 + SCROLL_TARGET_PX
			if right_edge < 10000.0:
				return Vector2i(sx, sy)
	_fail("no clean pure-ground stage found east of worldgen bounds")
	return Vector2i.ZERO

## Composite patch: 9x8 clean tiles inside worldgen bounds. Prefers an
## anchor whose camera view also contains a real ore deposit, so the
## depletion-faded ore fill gets photographed compositing over the noise.
## Walks the world's tiles in insertion order (deterministic for a given
## world) trying a handful of anchor offsets beside each ore tile; falls
## back to a plain deterministic scan if no ore-adjacent patch is clean.
func _find_clean_composite_patch() -> Vector2i:
	for p in _grid.tiles.keys():
		var t = _grid.tiles[p]
		if not ResourceNodes.is_ore(t.resource_node):
			continue
		# Camera center is anchor + (2, 0); every offset keeps the ore
		# well inside the 40x22.5-tile view at default zoom.
		for off in [Vector2i(6, 0), Vector2i(8, 2), Vector2i(-12, 0), Vector2i(6, -5), Vector2i(0, 7), Vector2i(-12, -5)]:
			var a: Vector2i = p + off
			if _patch_clean_and_in_bounds(a):
				return a
	for ay in range(-240, 234, 7):
		for ax in range(-240, 234, 7):
			if _patch_clean_and_in_bounds(Vector2i(ax, ay)):
				return Vector2i(ax, ay)
	_fail("no clean 9x8 composite patch inside worldgen bounds")
	return Vector2i.ZERO

## The 9x8 cells around anchor `a` (the staged cluster + margin) are all
## clean and inside worldgen bounds.
func _patch_clean_and_in_bounds(a: Vector2i) -> bool:
	if a.x - 2 < WorldGenerator.WORLD_MIN or a.x + 6 >= WorldGenerator.WORLD_MAX:
		return false
	if a.y - 4 < WorldGenerator.WORLD_MIN or a.y + 3 >= WorldGenerator.WORLD_MAX:
		return false
	for dy in range(-4, 4):
		for dx in range(-2, 7):
			if not _cell_clean(Vector2i(a.x + dx, a.y + dy)):
				return false
	return true

## Stage the composite cluster, all adjacent:
##   (ax,   ay-1) damaged soil (bare grass, soil=40 -> DAMAGED tint)
##   (ax+1, ay-1) POWER_POLE          (ax+2..3, ay-1..ay) SMELTER 2x2
##   (ax,   ay)   PATH + CHEST        (ax+1, ay) bare PATH overlay
func _stage_composite(a: Vector2i) -> bool:
	if not _grid.set_overlay(Vector2i(a.x, a.y), Terrain.Overlay.PATH):
		_fail("composite: PATH overlay at %s refused: %s" % [str(a), _grid.last_place_error])
		return false
	if not _grid.set_overlay(Vector2i(a.x + 1, a.y), Terrain.Overlay.PATH):
		_fail("composite: PATH overlay at %s refused: %s" % [str(a + Vector2i(1, 0)), _grid.last_place_error])
		return false
	if not _grid.place_building(Buildings.Type.CHEST, Vector2i(a.x, a.y)):
		_fail("composite: CHEST refused: %s" % _grid.last_building_place_error)
		return false
	if not _grid.place_building(Buildings.Type.POWER_POLE, Vector2i(a.x + 1, a.y - 1)):
		_fail("composite: POWER_POLE refused: %s" % _grid.last_building_place_error)
		return false
	if not _grid.place_building(Buildings.Type.SMELTER, Vector2i(a.x + 2, a.y - 1)):
		_fail("composite: SMELTER refused: %s" % _grid.last_building_place_error)
		return false
	# Damaged soil on bare grass — same write console `set_soil` performs.
	# 40 sits in the DAMAGED band (30..69) -> visible yellow-brown tint.
	_grid.tile_soil_modifications[Vector2i(a.x, a.y - 1)] = 40
	print("GROUND_CAPTURE: composite staged — soil(40)@%s pole@%s smelter@%s path@%s chest-on-path@%s" % [
		str(Vector2i(a.x, a.y - 1)), str(Vector2i(a.x + 1, a.y - 1)),
		str(Vector2i(a.x + 2, a.y - 1)), str(Vector2i(a.x + 1, a.y)), str(Vector2i(a.x, a.y))])
	return true

## If an ore deposit sits inside the composite view, drain it to ~25%
## richness so the depletion-faded fill composites translucently over the
## ground noise (the thing Phase 1 changes under it). Optional showcase —
## prints what it did either way.
func _deplete_one_ore_in_view(center: Vector2) -> void:
	var ct: Vector2i = _grid.world_to_tile(center)
	for dy in range(-11, 12):
		for dx in range(-20, 21):
			var p: Vector2i = Vector2i(ct.x + dx, ct.y + dy)
			var t = _grid.tiles.get(p)
			if t == null or not ResourceNodes.is_ore(t.resource_node):
				continue
			var orig: int = _grid.original_richness_at(p)
			var cur: int = _grid.richness_at(p)
			if orig <= 0:
				continue
			var target: int = max(1, orig / 4)
			if cur > target:
				_grid.deplete_resource(p, cur - target)
			print("GROUND_CAPTURE: depleted ore at %s from %d to %d/%d for the fade showcase" % [str(p), cur, _grid.richness_at(p), orig])
			return
	print("GROUND_CAPTURE: no ore deposit inside composite view — fade showcase skipped")

func _write_meta() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var f: FileAccess = FileAccess.open(abs_dir + "/capture_meta.json", FileAccess.WRITE)
	if f == null:
		_fail("cannot write capture_meta.json")
		return
	f.store_string(JSON.stringify(_meta, "\t"))
	f.close()
