# SPDX-License-Identifier: MIT
extends SceneTree
## Production display-loop probe: the scene display owner publishes every
## tick's resulting state to the real window, and each tick's T209 requests
## must be the composed frame's party position. Probe initialization, scripted
## presses and named gaps stay visible; not ordinary Session acceptance.
const Game = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Display = preload("res://src/native_pal98_scene_display.gd")
const Schema = preload("res://src/native_schema.gd")

class Clock:
	func consume(units: int) -> Dictionary: return {"consumed": units}
class Runtime:
	func answer(request: Dictionary) -> Dictionary:
		return {"completed": true, "pumped": request.get("events", [])}

var checks: Array = []
var details: Dictionary = {}
var stage: SubViewport
var frame_view: TextureRect
var args: PackedStringArray

func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)

func _window_pixels() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = get_root().get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels

static func unverified_inputs() -> Dictionary:
	var probe: Dictionary = Config.configuration()
	return {"globals": probe.globals, "dialogue": probe.dialogue,
		"party_trail": probe.party_trail, "inventory_bytes": probe.inventory_bytes}

func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 4 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("_run")

func _run() -> void:
	get_root().title = "PAL Wanxiang | production display loop probe"
	get_root().size = Vector2i(640, 400)
	get_root().content_scale_size = Vector2i(640, 400)
	var package = Package.new()
	check(package.load_package(args[0]), "admitted original input")
	if not package.error.is_empty(): finish(); return
	var game = Game.new()
	check(game.open(package), "coordinator assembled")
	if not game.error.is_empty(): finish(); return
	var gaps = Config.bind_gaps(game)
	game.bind_clock(Clock.new()); game.bind_runtime(Runtime.new()); game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	var initial: Dictionary = game.new_state_from_source(0x12345, "explicit_replay", unverified_inputs())
	if initial.has("error"): check(false, str(initial.error)); finish(); return
	check(initial.experience.size() == 5, "the F01 derived opening state prepares inside the production loop")
	var begun: Dictionary = Config.run(game)
	check(not begun.has("error") and begun.get("completed"), "replay reaches real reload terminal")
	if begun.has("error") or not begun.get("completed"): finish(); return
	check(game.state.globals.loaded_map_id == 12, "source MAP12 selected")
	var display = Display.new()
	check(display.bind(game), "production display binds the live game")
	stage = SubViewport.new(); stage.size = Vector2i(320, 200)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	get_root().add_child(stage)
	frame_view = TextureRect.new(); frame_view.size = Vector2(640, 400)
	frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame_view.texture = stage.get_texture(); get_root().add_child(frame_view)
	check(display.bind_display_target(stage), "display target is the real presented viewport")
	check(game.executor.installed_rgb6() == game.records.palette(0, 0).value
		and display.active_variant() == 0 and game.state.globals.day_night_word == 0,
		"the palette view derives from the current day/night word and the installed colors match it")
	var first: Dictionary = display.present()
	if first.has("error"): check(false, "present refused: " + str(first.error)); finish(); return
	check(first.requests.filter(func(r): return r.kind == "party").size() == 1
		and first.requests.filter(func(r): return r.kind == "event").size() == 2,
		"the published frame carries the real party and both event sprites")
	var before_window: Image = await _window_pixels()
	check(before_window.get_size() == Vector2i(640, 400), "the published frame fills the real window")
	check(before_window.save_png(args[1]) == OK, "before window PNG saved")
	details.before_sha256 = Schema.digest(before_window.get_data())
	var start_world: Vector2i = Vector2i(game.state.globals.world_x, game.state.globals.world_y)
	var moved := 0
	var last_digest := ""
	for step in range(5):
		var shown: Dictionary = await display.tick_presented(PackedInt32Array([0, 0, 0, 2, 0, 0, 0, 0, 0]))
		if shown.has("error"): check(false, "tick_presented refused: " + str(shown.error)); finish(); return
		if shown.input_move: moved += 1
		var party_request: Dictionary = {}
		for r in shown.tick.requests:
			if r.get("kind") == "party": party_request = r; break
		var linked := false
		for r in shown.composition.requests:
			if r.get("kind") == "party" and r.screen_x == party_request.get("screen_x") \
					and r.screen_y == party_request.get("screen_y"): linked = true
		check(linked, "tick " + str(step) + ": the tick's T209 position is the composed frame's party position")
		var image: Image = await _window_pixels()
		var digest: String = Schema.digest(image.get_data())
		if last_digest != "" and digest != last_digest: details.frames_advanced = true
		last_digest = digest
	check(moved > 0 and Vector2i(game.state.globals.world_x, game.state.globals.world_y) != start_world,
		"the production loop moves the real world through displayed ticks")
	check(details.get("frames_advanced", false), "successive displayed ticks change actual window pixels")
	var after_window: Image = await _window_pixels()
	check(after_window.get_data() != before_window.get_data(), "movement changed the actual window frame")
	check(after_window.save_png(args[2]) == OK, "after window PNG saved")
	details.after_sha256 = Schema.digest(after_window.get_data())
	details.world = [game.state.globals.world_x, game.state.globals.world_y]
	details.presented_frames = display.frame_count
	# Negative control: a broken current state is refused by name and the
	# owner never republishes the old frame as the new frame's success.
	var frames_before: int = display.frame_count
	var receipt_before: Dictionary = display.last_receipt
	game.state.party_records[0].current_frame = 32767
	var refused: Dictionary = display.present()
	check(refused.has("error") and display.frame_count == frames_before
		and display.last_receipt == receipt_before,
		"invalid current sprite frame is refused by name; the old frame is not republished: " + str(refused.get("error", "")))
	details.named_gaps = gaps.seen
	game.cancel()
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[3], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed,
		"failed": failed, "success": failed == 0, "details": details,
		"original_gameplay": false, "injected_logical_input": true,
		"scope": "production scene display owner; probe initialization and scripted presses; named gaps retained"}, "  "))
	file.close(); quit(1 if failed else 0)
