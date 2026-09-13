# SPDX-License-Identifier: MIT
extends SceneTree
## F14 window-fit and restore probe: integer scale with letterbox margins at
## multiple window sizes, click coordinates mapping back to the logical
## frame, and a minimize/restore round trip that republishes the accepted
## page without advancing any logic tick. Probe initialization and scripted
## presses stay visible; not ordinary acceptance.
const Game = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Display = preload("res://src/native_pal98_scene_display.gd")
const WindowScale = preload("res://src/native_pal98_window_scale.gd")

class Clock:
	var units := 0
	func consume(units_in: int) -> Dictionary: units += units_in; return {"consumed": units_in}
class Runtime:
	func answer(request: Dictionary) -> Dictionary:
		return {"completed": true, "pumped": request.get("events", [])}

var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray

func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)

static func unverified_inputs() -> Dictionary:
	var probe: Dictionary = Config.configuration()
	return {"globals": probe.globals, "dialogue": probe.dialogue,
		"party_trail": probe.party_trail, "inventory_bytes": probe.inventory_bytes}

func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 3 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("_run")

func _run() -> void:
	var package = Package.new()
	check(package.load_package(args[0]), "admitted original input")
	if not package.error.is_empty(): finish(); return
	var game = Game.new()
	check(game.open(package), "coordinator assembled")
	if not game.error.is_empty(): finish(); return
	Config.bind_gaps(game)
	var clock := Clock.new()
	game.bind_clock(clock); game.bind_runtime(Runtime.new()); game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	if game.new_state_from_source(0x12345, "explicit_replay", unverified_inputs()).has("error"):
		check(false, "derived opening state"); finish(); return
	var begun: Dictionary = Config.run(game)
	check(not begun.has("error") and begun.get("completed"), "replay reaches the resting state")
	if begun.has("error") or not begun.get("completed"): finish(); return

	var display = Display.new()
	check(display.bind(game), "display binds")
	var stage := SubViewport.new(); stage.size = Vector2i(320, 200)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(stage)
	var frame_view := TextureRect.new(); frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame_view.texture = stage.get_texture(); get_root().add_child(frame_view)
	check(display.bind_display_target(stage), "display target bound")

	# Integer scale and letterbox at several window sizes.
	var sizes: Array = [Vector2i(960, 600), Vector2i(1280, 720), Vector2i(500, 500)]
	var fits: Dictionary = {}
	for size in sizes:
		var fit: Dictionary = WindowScale.fit(size)
		fits[size] = fit
		check(fit.scale >= 1 and Vector2i(fit.content_offset) * 2 + Vector2i(fit.content_size) <= size,
			"fit at " + str(size) + " keeps an integer scale inside the window")
	check(fits[Vector2i(960, 600)].scale == 3 and fits[Vector2i(500, 500)].scale == 1,
		"the scale follows the smaller axis: " + str(fits[Vector2i(960, 600)].scale) + "/" + str(fits[Vector2i(500, 500)].scale))

	# Click mapping round-trips to the logical frame and refuses the margins.
	var fit960: Dictionary = fits[Vector2i(960, 600)]
	var inside: Dictionary = WindowScale.map_to_content(Vector2i(100, 60), fit960)
	check(not inside.has("error") and inside.position == Vector2i(33, 20),
		"a window click maps to the logical frame position: " + str(inside.get("position", Vector2i(-1, -1))))
	var margin: Dictionary = WindowScale.map_to_content(Vector2i(5, 5), WindowScale.fit(Vector2i(960, 700)))
	check(margin.has("error"), "a letterbox-margin click is refused by name")

	# Minimize/restore: republish without any logic tick or state change.
	var first: Dictionary = display.present()
	if first.has("error"): check(false, "present refused: " + str(first.error)); finish(); return
	var units_before := clock.units
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await process_frame
	var republished: Dictionary = display.republish()
	check(republished.get("completed", false), "restore republishes the accepted page")
	check(clock.units == units_before, "no logic tick advanced across minimize/restore")
	check(not game.state.is_empty() and game.state.globals.current_scene == 2,
		"the authoritative state is untouched by the visibility round trip")
	var after_window: Image = get_root().get_texture().get_image()
	check(after_window.save_png(args[1]) == OK, "restored window PNG saved")
	details.clock_units = clock.units
	details.presented_frames = display.frame_count
	game.cancel()
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed,
		"failed": failed, "success": failed == 0, "details": details,
		"original_gameplay": false, "injected_logical_input": true,
		"scope": "window fit computation, click mapping and restore republish; probe initialization; named gaps retained"}, "  "))
	file.close(); quit(1 if failed else 0)
