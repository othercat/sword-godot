# SPDX-License-Identifier: MIT
extends ConfirmationDialog
const Keys = preload("res://src/native_key_bindings.gd")
var app
var draft: Dictionary = {}
var picker: FileDialog
var preview: RichTextLabel
var notice: Label

func setup(owner_app) -> void:
	app = owner_app; title = "按键设置"; size = Vector2i(720,560); min_size = Vector2i(600,420)
	get_ok_button().text = "应用并保存"; get_cancel_button().text = "取消"; dialog_hide_on_ok = false
	var body = VBoxContainer.new(); add_child(body)
	var presets = HBoxContainer.new(); body.add_child(presets)
	app._button(presets,"传统方向键",_preset.bind("classic"))
	app._button(presets,"WASD 行走",_preset.bind("wasd"))
	app._button(presets,"导入 key.ini",func(): picker.popup_centered_ratio(0.8))
	var help = Label.new(); help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; help.custom_minimum_size.x = 560
	help.text = "鼠标始终可用。方向键选择命令和目标；确认键执行，取消键返回。文件及设置窗口使用常规 Enter / Esc。F5 保存、F9 读档；导入的显式映射优先。"
	body.add_child(help)
	preview = RichTextLabel.new(); preview.size_flags_vertical = Control.SIZE_EXPAND_FILL; preview.custom_minimum_size.y = 180
	body.add_child(preview)
	notice = Label.new(); notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; notice.custom_minimum_size.x = 560; body.add_child(notice)
	picker = FileDialog.new(); picker.access = FileDialog.ACCESS_FILESYSTEM; picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.ini ; PALDLL 按键配置"]); picker.title = "选择 key.ini（只读导入）"; add_child(picker)
	picker.file_selected.connect(import_path); confirmed.connect(_apply)

func open() -> void:
	draft = app.key_bindings.profile.duplicate(true)
	_preview(app.input_profile_notice if not app.input_profile_notice.is_empty() else "按键设置独立保存在本机；不会更改 MOD 或存档。")
	size = Vector2i(720,560); popup_centered()

func _preset(value: String) -> void:
	draft = Keys.preset(value); _preview("预览中，点击应用后生效。" + ("WASD 占用原防御、状态和装备快捷键，可使用鼠标菜单。" if value == "wasd" else ""))

func import_path(path: String) -> void:
	var result: Dictionary = Keys.import_file(path)
	if result.has("error"):
		# A failed second selection cannot accidentally apply the prior draft.
		draft = {}; get_ok_button().disabled = true; notice.text = result.error; return
	draft = result.profile
	_preview("\n".join(result.notices) + "\n未配置的键补回传统默认；禁用项不补回。原 key.ini 保持不变。")

func _preview(text: String) -> void:
	var model = Keys.new(); model.apply(draft); preview.text = model.describe(); notice.text = text; get_ok_button().disabled = false

func _apply() -> void:
	if draft.is_empty(): return
	if not app.key_bindings.save_profile(app.input_profile_path,draft): notice.text = app.key_bindings.error; return
	app._clear_input(); app.input_router.clear(); app.input_profile_notice = ""; app.message.text = "按键配置已保存。"; hide(); app._refresh()
