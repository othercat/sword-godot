# SPDX-License-Identifier: MIT
extends RefCounted
const Config = preload("res://src/native_story_notice.gd")
var scroll: ScrollContainer
var text: Label
var _context: String = ""

func setup(app) -> void:
	scroll = ScrollContainer.new(); scroll.name = "StoryNotice"; scroll.visible = false
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app.dialogue.add_child(scroll)
	text = Label.new(); text.name = "StoryNoticeText"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_color_override("font_color", Color("e4d5b5"))
	text.add_theme_font_size_override("font_size", 20)
	scroll.add_child(text)
	app.dialogue.resized.connect(func(): _fit(app))

func refresh(app) -> void:
	var row: Dictionary = {}
	var node: Dictionary = app.session.current_node()
	if node.get("op") == "end" and not app.session.dialogue_open and not app.session.battle_open() and not app.session.performance_open() and not app.battle_view.playing():
		row = Config.for_node(app.session.package.world, node.id)
	scroll.visible = not row.is_empty()
	var next: String = "" if row.is_empty() else str(app.session.package.get_instance_id()) + "/" + row.node_id
	if next != _context:
		_context = next; scroll.scroll_vertical = 0
	text.text = "" if row.is_empty() else row.title + "\n" + row.text
	_fit(app)

func _fit(app) -> void:
	if not scroll.visible: return
	# Keep the normal interaction hint outside this bounded text scroll. Long
	# notices must not expand the legacy VBox and take space away from the map.
	var available: float = app.map_ui.layers.dialogue.layer.size.y if app.map_ui.active else 170.0
	scroll.custom_minimum_size.y = clampf(available - app.dialogue_text.get_combined_minimum_size().y - 24.0, 24.0, 130.0)
