# SPDX-License-Identifier: MIT
extends SceneTree
const AppScene = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const Session = preload("res://src/native_session.gd")
var app
var checks: Array = []
var failures: int = 0
var output_dir: String

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})
	if not condition:
		failures += 1
		push_error(name)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	root.size = Vector2i(1280, 800)
	app = AppScene.instantiate()
	root.add_child(app)
	app.key_bindings.apply(app.key_bindings.preset("wasd"))
	await process_frame
	output_dir = ProjectSettings.globalize_path("res://generated/pal/visual_tests").path_join(Session.unique("native-ui"))
	DirAccess.make_dir_recursive_absolute(output_dir)
	app.saves = Save.new(args[1].path_join(Session.unique("ui-save-test")))
	check(app.open_package(args[0]), "same application loads actual Studio package")
	await process_frame
	await process_frame
	check(app.world_view.tiles is TileMapLayer and app.world_view.tiles.get_used_cells().size() == 300, "formal TileMapLayer has 300 synthetic tiles")
	check(app.roster.get_child_count() == 4 and app.world_view.actors.size() == 5, "UI shows four members and five world entities")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("01-dialogue.png"))
	await _click(app.save_button)
	check(app.saves.generations(app.session).size() == 1, "mouse Save button writes isolated generation")
	await _click(app.options.get_child(0))
	check(app.session.current_node().op == "choice" and app.options.get_child_count() == 2, "mouse Continue opens real choice UI")
	await _click(app.options.get_child(0))
	check(not app.session.dialogue_open and app.session.state.scopes.run[app.session.package.world.variables[0].id] == true, "mouse choice commits real declared variable")
	var previous = app.session.entity(app.session.state.active_party[0]).position.duplicate()
	_key(KEY_S, true)
	for _i in range(10): await physics_frame
	_key(KEY_S, false)
	await process_frame
	check(app.session.entity(app.session.state.active_party[0]).position.y > previous.y, "injected keyboard travels through application input")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await process_frame
	check(app.session.paused, "Escape pauses from application input")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await process_frame
	_key(KEY_F9, true)
	_key(KEY_F9, false)
	await process_frame
	await process_frame
	check(app.save_picker.visible and app.save_list.get_child_count() == 1, "F9 opens save selection UI")
	check(app.session.modal and app.session.state.clock.logic_paused, "save dialog has an authoritative paused clock")
	await RenderingServer.frame_post_draw
	app.save_picker.get_texture().get_image().save_png(output_dir.path_join("save-picker.png"))
	await _click(app.save_list.get_child(0))
	if app.session.state.timeline_epoch != 1:
		print(JSON.stringify({"debug": "load-ui", "message": app.message.text, "save_error": app.saves.error, "button_rect": str(app.save_list.get_child(0).get_global_rect()), "dialog_size": str(app.save_picker.size), "focused": app.session.focused}))
	check(app.session.state.timeline_epoch == 1 and app.session.current_node().op == "dialogue", "mouse load restores checkpoint in same application")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("02-restored.png"))
	# Mutate this synthetic in-memory fixture only to exercise the visible error
	# path. The source package and all stored generations remain unchanged.
	root.grab_focus()
	await process_frame
	await process_frame
	app.session.package.index.nodes["node.miaopang.native.accept"].next = "node.miaopang.native.accept"
	await _click(app.options.get_child(0))
	var before = app.session.snapshot()
	await _click(app.options.get_child(0))
	check(app.message.text.contains("budget exceeded"), "automatic execution failure is visible in player UI")
	check(app.session.state.cursor == before.cursor and app.session.state.scopes == before.scopes, "failed UI transition preserves story state")
	var report = {"passed": checks.size() - failures, "failed": failures, "checks": checks, "evidence_kind": "windowed-engine-injected-ui-input", "physical_human_input": false, "full_playthrough": false, "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "screenshots": output_dir}
	var file = FileAccess.open(output_dir.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures == 0 else 1)

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
