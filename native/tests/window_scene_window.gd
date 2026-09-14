# SPDX-License-Identifier: MIT
extends SceneTree
## N02 production window-host probe: the scene window owner binds the live
## opening to a real window, presents the composed map/party/event frame,
## advances it through movement ticks, republishes after a palette-variant
## change, fits integer scaling with click mapping, and refuses failures
## without claiming the previous frame. Probe initialization and scripted
## presses stay visible; not ordinary Session acceptance.
const Game = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Display = preload("res://src/native_pal98_scene_display.gd")
const Host = preload("res://src/native_pal98_scene_window.gd")
const Schema = preload("res://src/native_schema.gd")

class Clock:
	func consume(units: int) -> Dictionary: return {"consumed": units}
class Runtime:
	func answer(request: Dictionary) -> Dictionary:
		return {"completed": true, "pumped": request.get("events", [])}

var checks: Array = []
var details: Dictionary = {}
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
	if args.size() != 5 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("_run")

func _run() -> void:
	get_root().title = "PAL Wanxiang | production window host probe"
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
	var begun: Dictionary = Config.run(game)
	check(not begun.has("error") and begun.get("completed"), "replay reaches the resting scene")
	if begun.has("error") or not begun.get("completed"): finish(); return
	check(game.state.globals.loaded_map_id == 12, "source MAP12 selected")

	var host = Host.new()
	var display = Display.new()
	check(host.bind_host(get_root(), get_root(), game, display),
		"the window host binds the live game to the real window: " + host.error)
	if host.error: finish(); return
	check(host.stage != null and host.stage.is_inside_tree() and host.stage.size == Vector2i(320, 200),
		"the host owns a real 320x200 content viewport in the tree")
	check(host.fit.scale == 2 and host.fit.content_size == Vector2i(640, 400)
		and host.fit.content_offset == Vector2i(0, 0),
		"the initial fit is the integer 2x layout filling the 640x400 window")
	check(host.frame_view.position == Vector2(0, 0) and host.frame_view.size == Vector2(640, 400),
		"the content view is laid out on the fit rectangle")

	var first: Dictionary = host.present_frame()
	if first.has("error"): check(false, "first present refused: " + str(first.error)); finish(); return
	check(first.requests.filter(func(r): return r.kind == "party").size() == 1
		and first.requests.filter(func(r): return r.kind == "event").size() == 2,
		"the presented frame carries the real party and both event sprites")
	var before: Image = await _window_pixels()
	check(before.save_png(args[1]) == OK, "before PNG saved")
	var before_digest: String = Schema.digest(before.get_data())
	details.before_sha256 = before_digest

	var start_world: Vector2i = Vector2i(game.state.globals.world_x, game.state.globals.world_y)
	var moved := 0
	for step in range(5):
		var shown: Dictionary = await host.tick_frame(PackedInt32Array([0, 0, 0, 2, 0, 0, 0, 0, 0]))
		if shown.has("error"): check(false, "host tick refused: " + str(shown.error)); finish(); return
		if shown.input_move: moved += 1
	check(moved > 0 and Vector2i(game.state.globals.world_x, game.state.globals.world_y) != start_world,
		"the host moves the real world through its ticks")
	var after: Image = await _window_pixels()
	check(after.save_png(args[2]) == OK, "after PNG saved")
	var after_digest: String = Schema.digest(after.get_data())
	details.after_sha256 = after_digest
	check(after_digest != before_digest, "movement changed the actual window frame")

	# A palette change through the real intpate install plus the day/night
	# word presents a different frame through the same host.
	var night_block: Dictionary = game.records.palette(0, 1)
	check(not night_block.has("error"), "the night palette block is readable")
	var installed: Dictionary = game.executor.answer({"kind": "apply_palette", "procedure": "intpate",
		"offset": 384, "byte_offset": 768, "length": 768, "bytes": night_block.value})
	check(not installed.has("error"), "the night intpate install succeeds: " + str(installed.get("error", "")))
	game.state.globals.day_night_word = 384
	var night: Dictionary = host.present_frame()
	if night.has("error"): check(false, "night present refused: " + str(night.error)); finish(); return
	check(display.active_variant() == 1, "the active palette variant follows the day/night word")
	var night_image: Image = await _window_pixels()
	check(night_image.save_png(args[3]) == OK, "night PNG saved")
	var night_digest: String = Schema.digest(night_image.get_data())
	details.night_sha256 = night_digest
	check(night_digest != after_digest, "the palette change presented a different window frame")
	game.state.globals.day_night_word = 0

	# Resizing re-fits; the click mapping follows the live fit and the margins
	# are refused by name.
	get_root().size = Vector2i(960, 600)
	await process_frame
	var refit: Dictionary = host.apply_fit()
	check(not refit.has("error") and refit.scale == 3 and refit.content_offset == Vector2i(0, 0)
		and host.frame_view.size == Vector2(960, 600),
		"a larger window re-fits to the integer 3x layout: " + str(refit))
	var mapped: Dictionary = host.window_to_content(Vector2i(100, 60))
	check(not mapped.has("error") and mapped.position == Vector2i(33, 20),
		"a window position maps onto the logical frame: " + str(mapped.get("position", Vector2i(-1, -1))))
	get_root().size = Vector2i(700, 400)
	await process_frame
	var letterbox: Dictionary = host.apply_fit()
	check(not letterbox.has("error") and letterbox.scale == 2 and letterbox.content_offset == Vector2i(30, 0),
		"a wider aspect keeps a centred letterbox: " + str(letterbox))
	check(host.window_to_content(Vector2i(10, 10)).has("error"),
		"a click in the letterbox margin is refused by name")
	get_root().size = Vector2i(300, 200)
	await process_frame
	var too_small: Dictionary = host.apply_fit()
	check(too_small.has("error") and host.fit.scale == 2,
		"a sub-logical window is refused by name and the previous fit survives: " + str(too_small.get("error", "")))

	# The accepted page survives the refits without a new composition.
	var republished: Dictionary = host.republish_frame()
	check(not republished.has("error") and republished.frame_count == display.frame_count,
		"the accepted page republishes onto the refitted window: " + str(republished.get("error", "")))

	# A broken current state is refused by name; no new frame is claimed.
	var frames_before: int = display.frame_count
	var receipt_before: Dictionary = display.last_receipt
	game.state.party_records[0].current_frame = 32767
	var refused: Dictionary = host.present_frame()
	check(refused.has("error"), "an invalid frame request fails through the host: " + str(refused.get("error", "")))
	check(refused.has("error") and display.frame_count == frames_before
		and display.last_receipt == receipt_before,
		"the refused presentation neither republishes nor advances the accepted frame: " + str(refused.get("error", "")))
	details.named_gaps = gaps.seen
	details.presented_frames = display.frame_count
	game.cancel()
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[4], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed,
		"failed": failed, "success": failed == 0, "details": details,
		"original_gameplay": false, "injected_logical_input": true,
		"scope": "production scene window host; integer fit, click mapping, palette republish; probe initialization and scripted presses"}, "  "))
	file.close(); quit(1 if failed else 0)
