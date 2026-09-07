# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const KEY = "pal.native.regions"
var checks: Array = []
var failed: int = 0
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok:
		failed += 1
		push_error(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	root.size = Vector2i(1280, 800)
	var app = App.instantiate(); root.add_child(app)
	await process_frame
	app.saves = Save.new(args[1].path_join("saves"))
	check(app.open_package(args[0]), "actual application loads author region package")
	await process_frame; await process_frame
	await _click(app.options.get_child(0))
	await _click(app.options.get_child(1))
	check(not app.session.dialogue_open, "mouse input finishes initial conversation")
	var leader: String = app.session.state.active_party[0]
	_key(KEY_W, true)
	for _i in range(16): await physics_frame
	check(app.session.dialogue_open and app.session.entity(leader).position == {"x": 1, "y": 1}, "keyboard enters region and dialogue stops held movement at boundary")
	check(app.session.state.extensions[KEY].pending.size() == 1 and app.session.state.extensions[KEY].fired.size() == 1, "actual window has one dispatched and one queued event")
	await _click(app.save_button)
	check(not app.saves.last_path.is_empty() and app.saves.error.is_empty(), "mouse saves queued region generation")
	var save_path: String = app.saves.last_path
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1].path_join("region-window-waiting.png"))
	await _click(app.options.get_child(0))
	await _click(app.options.get_child(1))
	check(not app.session.dialogue_open and app.session.state.extensions[KEY].fired.size() == 2, "mouse continuation drains queued conditional event")
	check(app.session.state.scopes.run[app.session.package.world.variables[0].id] == true, "queued region reward reaches authoritative state")
	for _i in range(16): await physics_frame
	check(app.session.entity(leader).position == {"x": 1, "y": 1}, "old held direction does not leak past dialogue")
	_key(KEY_W, false)
	_key(KEY_S, true)
	for _i in range(2): await physics_frame
	_key(KEY_S, false)
	for _i in range(8): await physics_frame
	_key(KEY_W, true)
	for _i in range(2): await physics_frame
	_key(KEY_W, false)
	await process_frame
	check(app.session.entity(leader).position == {"x": 1, "y": 1} and not app.session.dialogue_open, "real input recrosses once region without repeating dialogue")
	_key(KEY_F9, true); _key(KEY_F9, false)
	await process_frame; await process_frame
	check(app.save_picker.visible and app.save_list.get_child_count() == 1, "F9 opens the actual queued save")
	await _click(app.save_list.get_child(0))
	check(app.session.state.timeline_epoch == 1 and app.session.dialogue_open and app.session.state.extensions[KEY].pending.size() == 1, "mouse load restores waiting queue without synthesizing entry")
	check(app.session.state.extensions[KEY].fired.size() == 1, "load preserves exact earlier once claims")
	await _click(app.options.get_child(0)); await _click(app.options.get_child(1))
	check(app.session.state.extensions[KEY].fired.size() == 2 and app.session.state.extensions[KEY].pending.is_empty(), "loaded conversation drains remaining event once")
	var report: Dictionary = {"checks": checks, "failed": failed, "save_path": save_path, "engine_injected_input": true, "physical_human_input": false, "full_playthrough": false, "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method()}
	FileAccess.open(args[1].path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t", false, true))
	print(JSON.stringify(report))
	quit(0 if failed == 0 else 1)

func _click(control: Control) -> void:
	var position: Vector2 = control.get_global_rect().get_center()
	if control.get_window() != root: position += Vector2(control.get_window().position)
	var motion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event, true)
	await process_frame
	await process_frame

func _key(code: Key, down: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
