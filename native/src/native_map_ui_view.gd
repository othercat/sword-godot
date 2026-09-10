# SPDX-License-Identifier: MIT
extends RefCounted
const Config = preload("res://src/native_map_ui.gd")
var surface: Control
var body: Control
var profile: Dictionary = {}
var active: bool = false
var layers: Dictionary = {}
var origins: Array = []
var styles: Dictionary = {}
var player_camera: Dictionary = {}
var _package_id: int = 0
var _camera_context: String = ""

func setup(app, original_body: Control) -> void:
	body = original_body
	surface = Control.new(); surface.name = "AuthoredMapWorkspace"
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.visible = false; surface.clip_contents = true
	body.get_parent().add_child(surface)
	body.get_parent().move_child(surface, body.get_index() + 1)
	surface.resized.connect(func(): _place(app))

func current(app) -> Dictionary:
	if app.session.state.is_empty(): return {}
	return Config.for_scene(app.session.package.world, app.session.state.cursor.scene_id)

func prepare(app) -> void:
	if active and (current(app).is_empty() or app.session.battle_open() or app.battle_view.playing()): _restore(app)

func apply(app) -> void:
	_sync_camera(app)
	for node in styles.keys():
		if not is_instance_valid(node): styles.erase(node)
	var candidate: Dictionary = current(app)
	app.map_reset.visible = not candidate.is_empty() and not app.session.battle_open() and not app.battle_view.playing()
	if candidate.is_empty() or app.session.battle_open() or app.battle_view.playing(): return
	profile = candidate
	if not active:
		active = true; body.visible = false; surface.visible = true
		for kind in ["map", "party", "dialogue"]:
			var child: Control = app.stage if kind == "map" else (app.sidebar if kind == "party" else app.dialogue)
			origins.append({"node":child, "parent":child.get_parent(), "index":child.get_index(), "minimum":child.custom_minimum_size, "horizontal":child.size_flags_horizontal, "vertical":child.size_flags_vertical})
			child.custom_minimum_size = Vector2.ZERO
			var layer = Control.new(); layer.name = "MapUi_" + kind; layer.clip_contents = true
			layer.mouse_filter = Control.MOUSE_FILTER_PASS; surface.add_child(layer)
			layers[kind] = {"layer":layer, "content":child}
			if kind == "map":
				child.reparent(layer); child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			else:
				var panel = PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layer.add_child(panel)
				var scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.follow_focus = true
				panel.add_child(scroll); child.reparent(scroll); child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				layers[kind]["panel"] = panel; layers[kind]["scroll"] = scroll
		var roster_scroll: ScrollContainer = app.roster.get_parent()
		layers.party["roster_scroll_mode"] = roster_scroll.vertical_scroll_mode
		roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(app)

func _place(app) -> void:
	if not active or surface.size.x <= 0 or surface.size.y <= 0: return
	for element in profile.elements:
		var item: Dictionary = layers[element.kind]; var rect: Dictionary = element.rect
		var layer: Control = item.layer
		layer.position = surface.size * Vector2(rect.x, rect.y) / 100.0
		layer.size = surface.size * Vector2(rect.width, rect.height) / 100.0
		surface.move_child(layer, surface.get_child_count()-1)
		layer.visible = element.get("visible", true)
		if element.kind == "map": continue
		var background = StyleBoxFlat.new(); background.bg_color = Color(element.background)
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: background.set_content_margin(side, 8)
		item.panel.add_theme_stylebox_override("panel", background)
		_style(item.content, int(element.font_size), Color(element.foreground))
	# _set_classic_mode owns the legacy sidebar visibility. Apply authored visibility
	# after it, but keep the actual widget alive for restoration and local preferences.
	app.sidebar.visible = true

func _style(node: Node, font_size: int, color: Color) -> void:
	if node is Label or node is BaseButton or node is LineEdit:
		if not styles.has(node):
			styles[node] = {"font_override":node.has_theme_font_size_override("font_size"), "font":node.get_theme_font_size("font_size"), "color_override":node.has_theme_color_override("font_color"), "color":node.get_theme_color("font_color")}
			if node is Label: styles[node]["wrap"] = node.autowrap_mode
		node.add_theme_font_size_override("font_size", font_size)
		node.add_theme_color_override("font_color", color)
		if node is Label: node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for child in node.get_children(): _style(child, font_size, color)

func _restore(app) -> void:
	for node in styles:
		if not is_instance_valid(node): continue
		var old: Dictionary = styles[node]
		if old.font_override: node.add_theme_font_size_override("font_size", old.font)
		else: node.remove_theme_font_size_override("font_size")
		if old.color_override: node.add_theme_color_override("font_color", old.color)
		else: node.remove_theme_color_override("font_color")
		if old.has("wrap"): node.autowrap_mode = old.wrap
	styles.clear()
	app.roster.get_parent().vertical_scroll_mode = layers.party.roster_scroll_mode
	for origin in origins:
		origin.node.reparent(origin.parent)
		origin.parent.move_child(origin.node, mini(origin.index, origin.parent.get_child_count()-1))
		origin.node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		origin.node.custom_minimum_size = origin.minimum
		origin.node.size_flags_horizontal = origin.horizontal
		origin.node.size_flags_vertical = origin.vertical
	origins.clear()
	for child in surface.get_children(): surface.remove_child(child); child.queue_free()
	layers.clear(); profile = {}; active = false
	surface.visible = false; body.visible = true
	app._fit_world.call_deferred()

func user_camera(app, field: String, value: Variant) -> void:
	player_camera[field] = value
	_camera_context = ""
	_sync_camera(app)

func reset_camera(app) -> void:
	player_camera.clear(); _camera_context = ""
	_sync_camera(app)

func _sync_camera(app) -> void:
	if app.session.state.is_empty(): return
	var package_id: int = app.session.package.get_instance_id()
	if package_id != _package_id:
		_package_id = package_id; player_camera.clear(); _camera_context = ""
	var context: String = str(package_id) + "/" + app.session.state.cursor.scene_id
	if context == _camera_context: return
	_camera_context = context
	var camera: Dictionary = current(app).get("camera", {"mode":"follow", "zoom":2.0, "actor_names":false}).duplicate()
	for field in player_camera: camera[field] = player_camera[field]
	app._camera_overview = camera.mode == "overview"; app._camera_zoom = camera.zoom
	app.map_overview.set_pressed_no_signal(app._camera_overview)
	app.map_zoom.set_value_no_signal(app._camera_zoom)
	app.map_names.set_pressed_no_signal(camera.actor_names)
	app.world_view.set_actor_names_visible(camera.actor_names)
	app._fit_world()
