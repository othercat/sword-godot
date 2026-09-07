# SPDX-License-Identifier: MIT
extends Control
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const World = preload("res://src/native_world.gd")
const WalkInput = preload("res://src/native_walk_input.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
var session = Session.new()
var saves = Save.new()
var world_view
var title_label: Label
var message: Label
var roster: VBoxContainer
var dialogue: VBoxContainer
var dialogue_text: Label
var options: VBoxContainer
var save_button: Button
var pause_button: Button
var picker: FileDialog
var save_picker: AcceptDialog
var save_list: VBoxContainer
var viewport: SubViewport
var fps_label: Label
var walk_input = WalkInput.new()
var _last_physics_usec: int = 0
var _gap_frame: int = -1
var _movement_frame: int = -1
var _stats_elapsed: float = 0.0
var _preview_stop_file: String = ""
var _preview_elapsed: float = 0.0

func _ready() -> void:
	get_window().gui_embed_subwindows = true
	var theme_data = Theme.new()
	theme_data.default_font_size = 20
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Noto Sans CJK SC", "PingFang SC", "sans-serif"])
	theme_data.default_font = font
	theme = theme_data
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var header = HBoxContainer.new()
	layout.add_child(header)
	title_label = Label.new()
	title_label.text = "仙剑·万相"
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color("d7be86"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	_button(header, "打开 MOD", _show_picker)
	pause_button = _button(header, "暂停", _pause)
	save_button = _button(header, "保存", _save)
	_button(header, "读档", _show_saves)
	var frames = OptionButton.new()
	for rate in [60, 100, 120, 144, 240]: frames.add_item("%d 帧" % rate, rate)
	frames.add_item("不限帧率", 0)
	frames.item_selected.connect(func(i): Engine.max_fps = frames.get_item_id(i))
	Engine.max_fps = 60
	header.add_child(frames)
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	layout.add_child(body)
	var sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 230
	body.add_child(sidebar)
	var party_title = Label.new()
	party_title.text = "同行伙伴"
	party_title.add_theme_color_override("font_color", Color("d7be86"))
	sidebar.add_child(party_title)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(scroll)
	roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 12)
	scroll.add_child(roster)
	var instructions = Label.new()
	instructions.text = "方向键 / WASD 行走\n空格 / Enter 交谈\nEsc 暂停\nF5 保存 · F9 读档"
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.add_theme_color_override("font_color", Color("9aa9a8"))
	sidebar.add_child(instructions)
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var frame = SubViewportContainer.new()
	frame.stretch = true
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(frame)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 580)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(viewport)
	world_view = World.new()
	viewport.add_child(world_view)
	frame.resized.connect(_fit_world)
	dialogue = VBoxContainer.new()
	dialogue.custom_minimum_size.y = 170
	center.add_child(dialogue)
	dialogue_text = Label.new()
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.text = "打开工坊导出的 MOD，开始一段新的故事。"
	dialogue_text.add_theme_color_override("font_color", Color("e4d5b5"))
	dialogue.add_child(dialogue_text)
	options = VBoxContainer.new()
	dialogue.add_child(options)
	var footer = HBoxContainer.new()
	layout.add_child(footer)
	message = Label.new()
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.add_theme_font_size_override("font_size", 16)
	message.text = "本地试玩 · 存档独立保存"
	footer.add_child(message)
	fps_label = Label.new()
	fps_label.add_theme_font_size_override("font_size", 16)
	footer.add_child(fps_label)
	picker = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.zip ; 万相内容包"])
	picker.title = "打开 MOD 内容包"
	picker.file_selected.connect(open_package)
	add_child(picker)
	save_picker = AcceptDialog.new()
	save_picker.title = "选择存档"
	save_picker.min_size = Vector2i(680, 300)
	add_child(save_picker)
	save_list = VBoxContainer.new()
	save_picker.add_child(save_list)
	picker.visibility_changed.connect(_modal_changed)
	save_picker.visibility_changed.connect(_modal_changed)
	session.changed.connect(_refresh)
	get_window().focus_entered.connect(func(): session.set_focus(true))
	get_window().focus_exited.connect(func(): walk_input.clear(); session.set_focus(false))
	save_button.disabled = true
	var args = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--save-root": saves = Save.new(args[i + 1])
		if args[i] == "--preview-stop-file": _preview_stop_file = args[i + 1]
	for i in range(args.size() - 1):
		if args[i] == "--package": open_package(args[i + 1])

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func open_package(path: String) -> bool:
	var candidate = Package.new()
	if not candidate.load_package(path) or not session.activate(candidate):
		message.text = "无法打开 MOD：" + (candidate.error if not candidate.error.is_empty() else session.error)
		if not _preview_stop_file.is_empty(): printerr("[Native preview] " + message.text)
		return false
	walk_input.clear()
	saves.envelope_extensions = {}
	saves.source_origin = "normal"
	saves.migrations = []
	title_label.text = candidate.manifest.display_name
	if candidate.manifest.extensions.has("pal.native.distribution"): title_label.text += " · 本地素材试玩"
	world_view.bind(session)
	_fit_world()
	_refresh()
	message.text = "已打开 · %d 位同行伙伴" % session.state.active_party.size()
	if not _preview_stop_file.is_empty(): print("[Native preview] package loaded: " + candidate.manifest.package_id + " node=" + session.state.cursor.node_id)
	return true

func _fit_world() -> void:
	if session.state.is_empty(): return
	var map_data: Dictionary = session.package.index.maps[session.package.index.scenes[session.state.cursor.scene_id].map_id]
	var bounds: Rect2 = MapProjection.bounds(map_data)
	var scale_value: float = minf((viewport.size.x - 32.0) / bounds.size.x, (viewport.size.y - 32.0) / bounds.size.y)
	world_view.scale = Vector2.ONE * scale_value
	world_view.position = (Vector2(viewport.size) - bounds.size * scale_value) / 2.0 - bounds.position * scale_value

func _refresh() -> void:
	if not is_instance_valid(roster) or session.state.is_empty(): return
	for child in roster.get_children():
		roster.remove_child(child)
		child.queue_free()
	for id in session.state.active_party:
		var actor: Dictionary = session.entity(id)
		var definition: Dictionary = session.package.index.actor_definitions[actor.definition_id]
		var label = Label.new()
		label.text = "%s\n气血 %d / %d   真气 %d" % [definition.display_name, actor.hp, definition.max_hp, actor.mp]
		label.add_theme_font_size_override("font_size", 17)
		roster.add_child(label)
	for child in options.get_children():
		options.remove_child(child)
		child.queue_free()
	var node: Dictionary = session.current_node()
	if node.op == "dialogue" and session.dialogue_open:
		var speaker: String = ""
		if node.speaker != null: speaker = session.package.index.actor_definitions[session.entity(node.speaker).definition_id].display_name + "\n"
		dialogue_text.text = speaker + node.text
		_button(options, "继续", _continue)
	elif node.op == "choice" and session.dialogue_open:
		dialogue_text.text = node.prompt
		for option in node.options: _button(options, option.text, _continue.bind(option.id))
	else:
		dialogue_text.text = "整装待发。靠近伙伴后按空格交谈。"
	save_button.disabled = not session.can_save()
	pause_button.text = "继续" if session.paused else "暂停"

func _continue(choice_id: String = "") -> void:
	if not session.advance_dialogue(choice_id) and not session.error.is_empty():
		message.text = session.error
		if not _preview_stop_file.is_empty(): printerr("[Native preview] node=" + session.state.cursor.node_id + " " + session.error)

func _show_picker() -> void:
	walk_input.clear()
	picker.popup_centered_ratio(0.8)

func _modal_changed() -> void:
	walk_input.clear()
	session.set_modal(picker.visible or save_picker.visible)

func _pause() -> void:
	walk_input.clear()
	session.set_pause(not session.paused)

func _save() -> void:
	if session.state.is_empty(): return
	session.account_time(Time.get_ticks_usec())
	message.text = "已保存 · 保留所有历史存档" if saves.save(session) else saves.error

func _show_saves() -> void:
	if session.state.is_empty(): return
	walk_input.clear()
	for child in save_list.get_children():
		save_list.remove_child(child)
		child.queue_free()
	var available: Array = saves.generations(session)
	if available.is_empty():
		var label = Label.new()
		label.text = "这个 MOD 还没有存档。"
		save_list.add_child(label)
	for generation in available:
		_button(save_list, Time.get_datetime_string_from_unix_time(generation.modified).replace("T", " ") + " · " + generation.path.get_file().substr(12, 8), func():
			if saves.load_into(session, generation.path):
				world_view.bind(session)
				_fit_world()
				message.text = "已恢复存档 · 本次为练习记录"
				save_picker.hide()
			else: message.text = saves.error)
	save_picker.popup_centered()

func _input(event: InputEvent) -> void:
	# A GUI may consume a release after focus changes; never leave movement held.
	if event is InputEventKey and not event.pressed: walk_input.key_event(event.keycode, false)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	if picker.visible or save_picker.visible: return
	if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		walk_input.key_event(event.keycode, event.pressed, event.echo)
	if not event.pressed or event.echo: return
	if event.keycode in [KEY_ENTER, KEY_SPACE]:
		if not session.interact() and not session.error.is_empty(): message.text = session.error
	elif event.keycode == KEY_ESCAPE: _pause()
	elif event.keycode == KEY_F5: _save()
	elif event.keycode == KEY_F9: _show_saves()

func _physics_process(_delta: float) -> void:
	if picker.visible or save_picker.visible: return
	session.tick()
	var now: int = Time.get_ticks_usec()
	var render_frame: int = Engine.get_process_frames()
	if movement_frame_allowed(now, render_frame) and session.sample_movement(walk_input): _movement_frame = render_frame

func movement_frame_allowed(now: int, render_frame: int) -> bool:
	# A stall does not replay keyboard movement through Godot's bounded catch-up.
	if _last_physics_usec > 0 and now - _last_physics_usec > 250000:
		_gap_frame = render_frame
		session.stop_walking()
	_last_physics_usec = now
	return _gap_frame != render_frame and (session.movement_rule() != "pal.walk.v1" or _movement_frame != render_frame)

func _process(delta: float) -> void:
	# Explicit Studio preview only: an empty local marker asks this child to exit.
	# No IP transport, arbitrary commands, or normal player-mode polling.
	if not _preview_stop_file.is_empty():
		_preview_elapsed += delta
		if _preview_elapsed >= 0.5:
			_preview_elapsed = 0.0
			if FileAccess.file_exists(_preview_stop_file):
				print("[Native preview] stop requested")
				get_tree().quit()
	session.account_time(Time.get_ticks_usec())
	_stats_elapsed += delta
	if _stats_elapsed >= 0.5:
		_stats_elapsed = 0.0
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
