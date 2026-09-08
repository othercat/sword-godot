# SPDX-License-Identifier: MIT
extends Control
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const World = preload("res://src/native_world.gd")
const WalkInput = preload("res://src/native_walk_input.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
const Battle = preload("res://src/native_battle.gd")
const Statuses = preload("res://src/native_statuses.gd")
const BattleView = preload("res://src/native_battle_view.gd")
var battle_view
var classic_hud = preload("res://src/native_battle_hud.gd").new()
var dream_hud = preload("res://src/native_dream_battle_hud.gd").new()
var sidebar: VBoxContainer
var center: VBoxContainer
var stage: Control
var classic_commands: PanelContainer
var classic_scroll: ScrollContainer
var classic_mode: bool = false
var classic_attack: bool = false
var classic_misc: bool = false
var classic_root: bool = false
var render_surface: TextureRect
var _classic_context: String = ""
var session = Session.new()
var saves = Save.new()
var world_view
var title_label: Label
var message: Label
var roster: VBoxContainer
var dialogue: VBoxContainer
var dialogue_text: Label
var instructions: Label
var options: GridContainer
var target_pages: HBoxContainer
var skill_menu = preload("res://src/native_skill_menu.gd").new()
var item_menu = preload("res://src/native_skill_menu.gd").new(true)
var equipment_button: Button
var equipment_menu = preload("res://src/native_equipment_menu.gd").new()
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
var _hover_target: Button
var _focus_target: Button
var _ui_generation: int = 0

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
	title_label.clip_text = true; title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 230
	body.add_child(sidebar)
	var party_title = Label.new()
	party_title.text = "同行伙伴"
	party_title.add_theme_color_override("font_color", Color("d7be86"))
	sidebar.add_child(party_title)
	equipment_button = _button(sidebar, "装备", _show_equipment); equipment_button.visible = false
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(scroll)
	roster = VBoxContainer.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 12)
	scroll.add_child(roster)
	instructions = Label.new()
	instructions.text = "方向键 / WASD 行走\n空格 / Enter 交谈\nEsc 暂停\nF5 保存 · F9 读档"
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.add_theme_color_override("font_color", Color("9aa9a8"))
	sidebar.add_child(instructions)
	center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	stage = Control.new(); stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL; center.add_child(stage)
	render_surface = preload("res://src/native_render_surface.gd").new()
	render_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(render_surface)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 580)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_surface.add_child(viewport)
	render_surface.configure(viewport)
	world_view = World.new()
	viewport.add_child(world_view)
	render_surface.logical_size_changed.connect(_fit_world)
	dream_hud.visible = false; stage.add_child(dream_hud)
	classic_commands = PanelContainer.new(); classic_commands.visible = false; stage.add_child(classic_commands)
	classic_scroll = ScrollContainer.new(); classic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	classic_scroll.follow_focus = true
	classic_commands.add_child(classic_scroll)
	stage.resized.connect(_fit_classic_controls)
	classic_hud.visible = false; classic_hud.custom_minimum_size.y = 90; center.add_child(classic_hud)
	dialogue = VBoxContainer.new()
	dialogue.custom_minimum_size.y = 170
	center.add_child(dialogue)
	dialogue_text = Label.new()
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.text = "打开工坊导出的 MOD，开始一段新的故事。"
	dialogue_text.add_theme_color_override("font_color", Color("e4d5b5"))
	dialogue.add_child(dialogue_text)
	target_pages = HBoxContainer.new(); target_pages.visible = false; dialogue.add_child(target_pages)
	options = GridContainer.new(); options.columns = 1
	options.resized.connect(_fit_battle_commands)
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
	picker.filters = PackedStringArray(["manifest.json ; 万相 MOD 目录入口", "*.zip ; 万相压缩内容包"])
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
	equipment_menu.setup(self); add_child(equipment_menu)
	equipment_menu.visibility_changed.connect(_modal_changed)
	session.changed.connect(_refresh)
	battle_view = BattleView.new(); battle_view.display_font = font; battle_view.visible = false; viewport.add_child(battle_view)
	render_surface.battle_view = battle_view
	get_window().focus_entered.connect(func(): session.set_focus(true))
	get_window().focus_exited.connect(func(): walk_input.clear(); session.set_focus(false))
	session.battle_committed.connect(battle_view.present_committed)
	battle_view.playback_finished.connect(_refresh)
	battle_view.display_changed.connect(_refresh_classic_hud)
	save_button.disabled = true
	var args = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--save-root": saves = Save.new(args[i + 1])
		if args[i] == "--preview-stop-file": _preview_stop_file = args[i + 1]
	for i in range(args.size() - 1):
		if args[i] == "--package": open_package(args[i + 1])

func _button(parent: Node, text: String, action: Callable, icon: String = "") -> Button:
	var button: Button = Button.new() if icon.is_empty() else preload("res://src/native_classic_command_button.gd").new()
	if not icon.is_empty(): button.symbol = icon
	button.text = text
	button.custom_minimum_size.y = 38
	if parent == options and session.battle_open():
		button.clip_text = true; button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",17)
		button.tooltip_text = text
	button.pressed.connect(action)
	button.mouse_entered.connect(func(): _hover_target = button; _update_target_preview())
	button.gui_input.connect(func(event):
		if event is InputEventMouseMotion: _hover_target = button; _update_target_preview())
	button.mouse_exited.connect(func():
		if _hover_target == button: _hover_target = null
		_update_target_preview())
	button.focus_entered.connect(func(): _hover_target = null; _focus_target = button; _update_target_preview())
	button.focus_exited.connect(func():
		if _focus_target == button: _focus_target = null
		_update_target_preview())
	parent.add_child(button)
	return button

func _bind_battle_target(button: Button, ids: Array, scope: String = "attack") -> void:
	button.set_meta("battle_target_ids",ids.duplicate())
	button.set_meta("battle_focus_key",scope+":"+JSON.stringify(ids))

func _update_target_preview() -> void:
	if not is_instance_valid(battle_view): return
	var ids: Array = []
	if session.battle_open() and session.focused and not session.paused and not session.modal and not battle_view.playing():
		for control in [_hover_target,_focus_target]:
			if is_instance_valid(control) and control.is_visible_in_tree() and not control.disabled:
				ids = control.get_meta("battle_target_ids",[]); break
	battle_view.preview_targets(ids)

func _fit_battle_commands() -> void:
	if not is_instance_valid(options): return
	if not session.battle_open(): options.custom_minimum_size.y = 0; return
	if _dream_mode():
		options.custom_minimum_size.y = 0; options.columns = 1 if _dream_misc() else 3; return
	if classic_mode: options.custom_minimum_size.y = 0; options.columns = 3 if classic_root else 2; return
	if battle_view.playing(): return
	var columns: int = 4 if options.size.x >= 840 else (3 if options.size.x >= 620 else 2)
	var count: int = options.get_child_count()
	if skill_menu.mode == "closed" and item_menu.mode == "closed":
		var targets: Array = options.get_children().filter(func(c): return c.has_meta("battle_target_ids"))
		if not targets.is_empty():
			# Reserve a full target page during commands and playback. Otherwise
			# the last short page expands the battlefield and changes camera fit.
			count += mini(BattleView.PAGE_SIZE,session.state.extensions[Battle.KEY].enemies.size()) - targets.size()
			var row_height: float = targets[0].get_combined_minimum_size().y
			var rows: int = ceili(count / float(mini(columns,count)))
			options.custom_minimum_size.y = rows * row_height + (rows-1) * options.get_theme_constant("v_separation")
	options.columns = mini(columns,maxi(1,count))

func _fit_classic_controls() -> void:
	if not is_instance_valid(classic_commands): return
	if _dream_mode():
		var frame: Rect2 = BattleView.Classic.stage_rect(stage.size)
		var zoom: float = frame.size.x/320.0
		dream_hud.position = frame.position; dream_hud.scale = Vector2(zoom,zoom)
		dream_hud.visible = not battle_view.playing()
		dream_hud.commands.visible = classic_root
		classic_commands.visible = not classic_root
		classic_commands.scale = Vector2(zoom,zoom)
		var panel = Rect2(2,20,71,112) if _dream_misc() else Rect2(10,42,300,114)
		if item_menu.mode != "closed": panel = Rect2(2,0,316,150)
		if battle_view.playing(): panel = Rect2(2,20,105,42)
		classic_commands.position = frame.position+panel.position*zoom; classic_commands.size = panel.size
		classic_commands.remove_theme_stylebox_override("panel")
		options.add_theme_constant_override("v_separation",1); options.add_theme_constant_override("h_separation",3)
		dialogue.add_theme_constant_override("separation",1)
		dialogue_text.add_theme_font_size_override("font_size",8)
		dialogue_text.visible = not classic_root and not _dream_misc()
		for control in options.get_children()+target_pages.get_children():
			if control is Button:
				control.custom_minimum_size.y = 17; control.add_theme_font_size_override("font_size",8)
		options.columns = 1 if _dream_misc() else 3
		return
	classic_commands.scale = Vector2.ONE; dialogue_text.visible = true
	options.remove_theme_constant_override("v_separation"); options.remove_theme_constant_override("h_separation")
	dialogue.remove_theme_constant_override("separation")
	classic_commands.size = Vector2(minf(240 if classic_root else 330,stage.size.x-8),minf(300 if classic_root else 280,stage.size.y))
	classic_commands.position = Vector2(8,maxf(0,stage.size.y-classic_commands.size.y-8))
	if classic_root: classic_commands.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	else: classic_commands.remove_theme_stylebox_override("panel")
	dialogue_text.add_theme_font_size_override("font_size",16 if classic_mode else 20)

func _refresh_classic_hud() -> void:
	if is_instance_valid(battle_view) and classic_mode:
		if _dream_mode(): dream_hud.bind(battle_view)
		else: classic_hud.bind(battle_view)

func _dream_mode() -> bool:
	return is_instance_valid(battle_view) and BattleView.Classic.is_dream(battle_view.classic_layout()) and battle_view.visible

func _dream_misc() -> bool:
	return classic_misc and skill_menu.mode == "closed" and item_menu.mode == "closed"

func _battle_controls() -> Array:
	return options.get_children()+target_pages.get_children()+dream_hud.commands.get_children()

func _dream_root(battle: Dictionary, actor: Dictionary) -> void:
	for symbol in ["attack","skills","cooperative","misc"]:
		var action: Callable
		match symbol:
			"attack": action = _classic_select_attack.bind(true)
			"skills": action = skill_menu._open.bind(self)
			"misc": action = _classic_select_misc.bind(true)
			_: action = func(): pass
		var labels = {"attack":"攻击","skills":"技能","cooperative":"合击","misc":"其他"}
		var button: Button = _button(dream_hud.commands,labels[symbol],action,symbol)
		button.skin = Session.Package.BattleUi.for_encounter(session.package,battle.encounter_id)
		# Invisible Button text still contributes to its minimum hit size.
		button.clip_text = true; button.add_theme_font_size_override("font_size",8)
		button.reference_size = 30; button.custom_minimum_size = Vector2(30,30)
		var rect: Rect2 = BattleView.Classic.dream_command_rect(symbol,battle.party.size())
		button.position = rect.position; button.size = rect.size
		if symbol == "cooperative": button.disabled = true; button.tooltip_text = "当前内容没有合击命令。"
		if symbol == "skills":
			button.disabled = Session.Progression.skill_ids(session.package,actor).is_empty() or not Statuses.blocking(session.package,session.state,actor.instance_id,"block_skills").is_empty()
		button.queue_redraw()

func _set_classic_mode(enabled: bool) -> void:
	if classic_mode != enabled:
		classic_mode = enabled; classic_attack = false; classic_misc = false
		dialogue.reparent(classic_scroll if enabled else center)
		dialogue.custom_minimum_size.y = 0 if enabled else 170
		dialogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		options.custom_minimum_size.y = 0
		if not enabled: classic_hud.clear()
	var dream: bool = enabled and _dream_mode()
	sidebar.visible = not enabled; classic_hud.visible = enabled and not dream; classic_commands.visible = enabled
	dream_hud.visible = dream
	if not dream: dream_hud.clear()
	_fit_classic_controls(); _refresh_classic_hud()

func _classic_select_attack(value: bool) -> void:
	classic_attack = value; _refresh()

func _classic_select_misc(value: bool) -> void:
	classic_misc = value; _refresh()

func _classic_spacer() -> void:
	var spacer = Control.new(); spacer.custom_minimum_size = Vector2(68,68)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE; options.add_child(spacer)

func _restore_battle_focus(key: String, generation: int) -> void:
	if not is_inside_tree(): return
	if generation != _ui_generation or not session.battle_open() or battle_view.playing() or session.paused or session.modal or not session.focused: return
	var first: Button
	for control in _battle_controls():
		if control is not Button or control.disabled: continue
		if first == null: first = control
		if str(control.get_meta("battle_focus_key",control.text.get_slice("\n",0))) == key: control.grab_focus(); return
	if first != null: first.grab_focus()

func _battle_target_detail(target: Dictionary) -> String:
	var definition: Dictionary = session.package.index.actor_definitions[target.definition_id]
	var effective: Dictionary = Session.Progression.stats(session.package, target)
	var detail: String = "%s\n气血 %d / %d · 真气 %d / %d" % [definition.display_name,target.hp,effective.max_hp,target.mp,effective.max_mp]
	var statuses: PackedStringArray = Statuses.describe(session.package,session.state,target.instance_id)
	return detail + ("\n" + "\n".join(statuses) if not statuses.is_empty() else "")

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
	message.text = "已打开内容包"
	if not _preview_stop_file.is_empty(): print("[Native preview] package loaded: " + candidate.manifest.package_id + " node=" + session.state.cursor.node_id)
	return true

func _fit_world() -> void:
	if session.state.is_empty(): return
	var map_data: Dictionary = session.package.index.maps[session.package.index.scenes[session.state.cursor.scene_id].map_id]
	var bounds: Rect2 = MapProjection.bounds(map_data)
	var logical_size: Vector2 = viewport.get_visible_rect().size
	var scale_value: float = minf((logical_size.x - 32.0) / bounds.size.x, (logical_size.y - 32.0) / bounds.size.y)
	_camera_map = session.state.cursor.scene_id
	_camera_bounds = bounds
	_terrain_camera = map_data.has("terrain")
	if _terrain_camera: scale_value = 2.0
	world_view.scale = Vector2.ONE * scale_value
	world_view.position = (logical_size - bounds.size * scale_value) / 2.0 - bounds.position * scale_value
	_follow_world()

var _camera_map: String = ""
var _camera_bounds: Rect2
var _terrain_camera: bool = false
var _presentation_key: String = ""

func _follow_world() -> void:
	if not _terrain_camera or session.state.is_empty() or not world_view.actors.has(session.state.active_party[0]): return
	var center: Vector2 = world_view.actors[session.state.active_party[0]].position
	var logical_size: Vector2 = viewport.get_visible_rect().size
	var half_view = logical_size / world_view.scale / 2.0
	for axis in range(2):
		center[axis] = _camera_bounds.get_center()[axis] if _camera_bounds.size[axis] <= half_view[axis] * 2.0 else clampf(center[axis], _camera_bounds.position[axis] + half_view[axis], _camera_bounds.end[axis] - half_view[axis])
	world_view.position = logical_size / 2.0 - center * world_view.scale

func _refresh() -> void:
	if not is_instance_valid(roster) or session.state.is_empty(): return
	_ui_generation += 1
	equipment_button.visible = Session.Equipment.used(session.package.world)
	equipment_button.disabled = session.battle_open() or battle_view.playing() or session.paused or session.modal
	var focus = get_viewport().gui_get_focus_owner()
	var restore_focus: bool = focus == null or focus.get_parent() in [options,target_pages,dream_hud.commands]
	var focus_key: String = str(focus.get_meta("battle_focus_key",focus.text.get_slice("\n",0))) if restore_focus and focus is Button else ""
	_hover_target = null; _focus_target = null; battle_view.preview_targets([])
	if session.dialogue_open or session.battle_open(): walk_input.clear()
	var key: String = world_view._history_key(session) + ":battle=" + str(session.battle_open())
	world_view.visible = not session.battle_open() and not battle_view.playing()
	instructions.text = ("选择下方命令行动\n轮到的伙伴以金框标出\nEsc 暂停\nF5 保存 · F9 读档" if session.battle_open() else "方向键 / WASD 行走\n空格 / Enter 交谈\nEsc 暂停\nF5 保存 · F9 读档")
	battle_view.bind(session); battle_view.visible = session.battle_open() or battle_view.playing()
	_set_classic_mode(battle_view.visible and not battle_view.classic_layout().is_empty())
	world_view.visible = not battle_view.visible
	if key != _presentation_key:
		_presentation_key = key
		walk_input.clear()
		world_view.bind(session)
		_fit_world()
	for child in roster.get_children():
		roster.remove_child(child)
		child.queue_free()
	for id in session.state.active_party:
		var actor: Dictionary = session.entity(id)
		var definition: Dictionary = session.package.index.actor_definitions[actor.definition_id]
		var label = Label.new()
		var effective: Dictionary = Session.Progression.stats(session.package, actor)
		label.text = "%s\n气血 %d / %d   真气 %d" % [definition.display_name, actor.hp, effective.max_hp, actor.mp]
		var growth_label: String = Session.Progression.label(session.package, actor)
		if not growth_label.is_empty(): label.text += "\n" + growth_label
		label.add_theme_font_size_override("font_size", 17)
		roster.add_child(label)
	var reward_summary: String = Session.Progression.summary(session.package, session.state)
	if not reward_summary.is_empty():
		var reward_label = Label.new(); reward_label.name = "GrowthRewardSummary"; reward_label.text = reward_summary
		reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; reward_label.add_theme_font_size_override("font_size", 15)
		roster.add_child(reward_label)
	for child in options.get_children():
		options.remove_child(child)
		child.queue_free()
	for child in target_pages.get_children():
		target_pages.remove_child(child); child.queue_free()
	dream_hud.clear_commands()
	target_pages.visible = false; options.columns = 1; classic_root = false
	var node: Dictionary = session.current_node()
	if battle_view.playing():
		dialogue_text.text = "正在播放行动结果…"
		_button(options, "跳过演出", battle_view.skip)
	elif session.battle_open():
		var battle: Dictionary = session.state.extensions[Battle.KEY]
		var actor: Dictionary = session.entity(battle.party[battle.turn])
		var context: String = "%s:%s:%s:%s" % [session.state.session_id,session.state.timeline_epoch,battle.execution_id,battle.step]
		if context != _classic_context: _classic_context = context; classic_attack = false; classic_misc = false
		skill_menu.sync_context(self, battle, actor); item_menu.sync_context(self, battle, actor)
		dialogue_text.text = "%s · 第 %d 回合 · %s 行动" % [Battle.encounter(session.package.world, battle.encounter_id).display_name, battle.round, session.package.index.actor_definitions[actor.definition_id].display_name]
		var status_text: String = "；".join(Statuses.describe(session.package, session.state, actor.instance_id))
		if not status_text.is_empty(): dialogue_text.text += "\n" + status_text
		if not Statuses.blocking(session.package, session.state, actor.instance_id, "skip_turn").is_empty():
			_button(options, "跳过行动", _battle_action.bind("wait", ""))
		elif classic_mode and (skill_menu.mode != "closed" or item_menu.mode != "closed"):
			if skill_menu.mode != "closed": skill_menu.render(self,battle,actor)
			else: item_menu.render(self,battle,actor)
		elif classic_mode and not classic_attack:
			if classic_misc:
				if _dream_mode(): item_menu.render(self,battle,actor)
				_button(options,"防御",_battle_action.bind("guard",""))
				_button(options,"撤离",_battle_action.bind("escape","")).disabled = not Battle.encounter(session.package.world,battle.encounter_id).allow_escape
				_button(options,"返回命令",_classic_select_misc.bind(false))
			else:
				classic_root = true; options.columns = 3
				if _dream_mode(): _dream_root(battle,actor)
				else:
					_classic_spacer(); _button(options,"攻击",_classic_select_attack.bind(true),"attack"); _classic_spacer()
					skill_menu.render(self,battle,actor,"skills"); _classic_spacer(); item_menu.render(self,battle,actor,"items")
					_classic_spacer(); _button(options,"其他",_classic_select_misc.bind(true),"misc"); _classic_spacer()
		else:
			var start: int = battle_view.enemy_page * BattleView.PAGE_SIZE
			options.columns = 2 if battle.enemies.size() > 1 else 1
			if battle_view.page_count() > 1:
				target_pages.visible = true
				_button(target_pages, "上一组敌人", _change_enemy_page.bind(-1)).disabled = battle_view.enemy_page == 0
				var page_label = Label.new(); page_label.text = "%d / %d" % [battle_view.enemy_page + 1, battle_view.page_count()]; target_pages.add_child(page_label)
				_button(target_pages, "下一组敌人", _change_enemy_page.bind(1)).disabled = battle_view.enemy_page == battle_view.page_count() - 1
			for i in range(start, mini(start + BattleView.PAGE_SIZE, battle.enemies.size())):
				var enemy: Dictionary = battle.enemies[i]
				var definition: Dictionary = session.package.index.actor_definitions[enemy.definition_id]
				var label: String = "攻击 " + BattleView.enemy_label(session.package,enemy,i) + "\n气血 %d / %d" % [enemy.hp,definition.max_hp]
				var target_button = _button(options,label,_battle_action.bind("attack",enemy.instance_id))
				target_button.tooltip_text = _battle_target_detail(enemy)
				target_button.disabled = enemy.hp == 0
				_bind_battle_target(target_button,[enemy.instance_id])
			if classic_mode and classic_attack: _button(options,"返回命令",_classic_select_attack.bind(false))
			if not classic_mode:
				_button(options, "防御", _battle_action.bind("guard", ""))
				_button(options, "撤离", _battle_action.bind("escape", "")).disabled = not Battle.encounter(session.package.world, battle.encounter_id).allow_escape
				if item_menu.mode == "closed": skill_menu.render(self, battle, actor)
				if skill_menu.mode == "closed": item_menu.render(self, battle, actor)
	elif node.op == "dialogue" and session.dialogue_open:
		var speaker: String = ""
		if node.speaker != null: speaker = session.package.index.actor_definitions[session.entity(node.speaker).definition_id].display_name + "\n"
		dialogue_text.text = speaker + node.text
		_button(options, "继续", _continue)
	elif node.op == "choice" and session.dialogue_open:
		dialogue_text.text = node.prompt
		for option in node.options: _button(options, option.text, _continue.bind(option.id))
	else:
		dialogue_text.text = "整装待发。靠近伙伴后按空格交谈。"
		for portal in session.package.index.scenes[session.state.cursor.scene_id].get("portals", []):
			if portal.position == session.entity(session.state.active_party[0]).position:
				var status: Dictionary = session.portal_status(portal)
				dialogue_text.text = portal.display_name + (" · 按空格进入" if status.allowed else " · " + status.text)
	save_button.disabled = not session.can_save()
	pause_button.text = "继续" if session.paused else "暂停"
	_fit_battle_commands()
	_fit_classic_controls()
	if restore_focus: _restore_battle_focus.call_deferred(focus_key,_ui_generation)

func _change_enemy_page(direction: int) -> void:
	if not session.battle_open(): return
	battle_view.enemy_page = clampi(battle_view.enemy_page + direction, 0, battle_view.page_count() - 1)
	_refresh()

func _battle_action(action: String, target: String) -> void:
	if battle_view.playing(): return
	if session.battle_command(action, target): message.text = ""
	else: message.text = session.error

func _continue(choice_id: String = "") -> void:
	if battle_view.playing(): return
	if not session.advance_dialogue(choice_id) and not session.error.is_empty():
		message.text = session.error
		if not _preview_stop_file.is_empty(): printerr("[Native preview] node=" + session.state.cursor.node_id + " " + session.error)

func _show_picker() -> void:
	walk_input.clear()
	picker.popup_centered_ratio(0.8)

func _show_equipment() -> void:
	walk_input.clear(); equipment_menu.open()

func _modal_changed() -> void:
	walk_input.clear()
	session.set_modal(picker.visible or save_picker.visible or equipment_menu.visible)

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
	if picker.visible or save_picker.visible or equipment_menu.visible: return
	if battle_view.playing() and event.keycode in [KEY_ENTER, KEY_SPACE, KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		walk_input.clear(); return
	if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		walk_input.key_event(event.keycode, event.pressed, event.echo)
	if not event.pressed or event.echo: return
	if event.keycode in [KEY_ENTER, KEY_SPACE]:
		if session.interact(): message.text = ""
		elif not session.error.is_empty(): message.text = session.error
	elif event.keycode == KEY_ESCAPE:
		if battle_view.playing(): _pause()
		elif session.battle_open() and skill_menu.mode != "closed": skill_menu.cancel(self)
		elif session.battle_open() and item_menu.mode != "closed": item_menu.cancel(self)
		elif session.battle_open() and classic_mode and classic_attack: _classic_select_attack(false)
		elif session.battle_open() and classic_mode and classic_misc: _classic_select_misc(false)
		else: _pause()
	elif event.keycode == KEY_F5: _save()
	elif event.keycode == KEY_F9: _show_saves()

func _physics_process(_delta: float) -> void:
	if picker.visible or save_picker.visible or equipment_menu.visible: return
	session.tick()
	if battle_view.playing():
		walk_input.clear(); return
	var now: int = Time.get_ticks_usec()
	var render_frame: int = Engine.get_process_frames()
	if movement_frame_allowed(now, render_frame):
		if session.sample_movement(walk_input): _movement_frame = render_frame
		elif not session.error.is_empty(): message.text = session.error

func movement_frame_allowed(now: int, render_frame: int) -> bool:
	# A stall does not replay keyboard movement through Godot's bounded catch-up.
	if _last_physics_usec > 0 and now - _last_physics_usec > 250000:
		_gap_frame = render_frame
		session.stop_walking()
	_last_physics_usec = now
	return _gap_frame != render_frame and (session.movement_rule() != "pal.walk.v1" or _movement_frame != render_frame)

func _process(delta: float) -> void:
	if not session.state.is_empty():
		if _camera_map != session.state.cursor.scene_id: _fit_world()
		else: _follow_world()
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
