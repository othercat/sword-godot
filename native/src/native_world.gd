# SPDX-License-Identifier: MIT
extends Node2D
const ActorVisual = preload("res://src/native_actor_visual.gd")
## TileMapLayer + separate actor nodes. The authoritative world uses tile units.
var session
var tiles: TileMapLayer
var actors: Dictionary = {}
var backdrop: Sprite2D
var visuals: Dictionary = {}
var _history: String = ""

func bind(model) -> void:
	session = model
	for child in get_children():
		remove_child(child)
		child.queue_free()
	actors = {}
	visuals = {}
	_history = _history_key()
	var scene: Dictionary = session.package.index.scenes[session.state.cursor.scene_id]
	var map_data: Dictionary = session.package.index.maps[scene.map_id]
	var width: int = map_data.coordinates.tile_width
	var height: int = map_data.coordinates.tile_height
	var atlas_image = Image.create(width * 2, height, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color("293c39"))
	atlas_image.fill_rect(Rect2i(1, 1, width - 2, height - 2), Color("304741"))
	atlas_image.fill_rect(Rect2i(width, 0, width, height), Color("54423b"))
	atlas_image.fill_rect(Rect2i(width + 5, 5, width - 10, height - 10), Color("6d5947"))
	var source = TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas_image)
	source.texture_region_size = Vector2i(width, height)
	source.create_tile(Vector2i.ZERO)
	source.create_tile(Vector2i(1, 0))
	var tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(width, height)
	tile_set.add_source(source, 0)
	tiles = TileMapLayer.new()
	tiles.tile_set = tile_set
	add_child(tiles)
	for y in int(map_data.height):
		for x in int(map_data.width):
			var logical = {"x": x + map_data.coordinates.origin.x, "y": y + map_data.coordinates.origin.y}
			tiles.set_cell(Vector2i(logical.x, logical.y), 0, Vector2i(1, 0) if logical in map_data.blocked else Vector2i.ZERO)
	if map_data.background_asset != null:
		backdrop = Sprite2D.new()
		backdrop.texture = session.package.textures[map_data.background_asset]
		backdrop.centered = false
		backdrop.position = Vector2(map_data.coordinates.origin.x * width - width / 2.0, map_data.coordinates.origin.y * height - height / 2.0)
		backdrop.scale = Vector2(map_data.width * width, map_data.height * height) / backdrop.texture.get_size()
		add_child(backdrop)
	var actor_layer = Node2D.new()
	actor_layer.y_sort_enabled = true
	add_child(actor_layer)
	for item in session.state.entities:
		if item.scene_id != session.state.cursor.scene_id: continue
		var definition: Dictionary = session.package.index.actor_definitions[item.definition_id]
		var body = Node2D.new()
		actor_layer.add_child(body)
		var visual = ActorVisual.new()
		body.add_child(visual)
		var color = Color("b4965c") if item.instance_id == session.state.active_party[0] else (Color("74658a") if item.instance_id in session.state.active_party else Color("667f91"))
		visual.bind(definition, session.package, height, color)
		visual.present(item, int(session.state.clock.logic_tick), 0.0, false)
		visuals[item.instance_id] = visual
		var label = Label.new()
		label.text = definition.display_name
		label.position = Vector2(-48, -67)
		label.size = Vector2(96, 25)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		body.add_child(label)
		actors[item.instance_id] = body
		body.position = tiles.map_to_local(Vector2i(item.position.x, item.position.y))

func _process(delta: float) -> void:
	if session == null or session.state.is_empty(): return
	if _history != _history_key():
		bind(session)
		return
	var running: bool = not session.paused and not session.modal and session.focused
	for item in session.state.entities:
		if not actors.has(item.instance_id): continue
		var target = tiles.map_to_local(Vector2i(item.position.x, item.position.y))
		# Time-based presentation interpolation only; does not feed world state.
		if running: actors[item.instance_id].position = actors[item.instance_id].position.lerp(target, 1.0 - exp(-24.0 * delta))
		visuals[item.instance_id].present(item, int(session.state.clock.logic_tick), delta, running)

func _history_key() -> String:
	return "%s/%s/%s/%s" % [session.state.session_id, session.state.timeline_epoch, session.state.cursor.scene_id, session.state.content_lock]
