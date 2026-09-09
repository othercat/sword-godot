# SPDX-License-Identifier: MIT
extends Node2D
const Sampling = preload("res://src/native_sampling.gd")
const ActorVisual = preload("res://src/native_actor_visual.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
const Terrain = preload("res://src/native_terrain.gd")
const SceneTravel = preload("res://src/native_scene_travel.gd")
const PartyTrail = preload("res://src/native_party_trail.gd")
const MapPerformance = preload("res://src/native_performance.gd")
## TileMapLayer + separate actor nodes. The authoritative world uses tile units.
var session
var tiles: TileMapLayer
var actors: Dictionary = {}
var backdrop: Sprite2D
var visuals: Dictionary = {}
var _history: String = ""
var terrain_layers: Array = []
var depth_tiles: Array = []
var _map: Dictionary = {}
var portal_markers: Array = []
var _map_key: String = ""
var _actor_layer: Node2D

func bind(model) -> void:
	session = model
	var scene: Dictionary = session.package.index.scenes[session.state.cursor.scene_id]
	var map_data: Dictionary = session.package.index.maps[scene.map_id]
	# A package is immutable after validation. Retain only the current map;
	# a new package instance releases textures even when it has the same IDs.
	var map_key: String = "%s/%s/%s" % [session.package.get_instance_id(), session.state.content_lock, scene.map_id]
	if map_key != _map_key:
		for child in get_children():
			remove_child(child)
			child.queue_free()
		terrain_layers = []; depth_tiles = []
		actors = {}; portal_markers = []
		_map = map_data; _map_key = map_key
		_build_map()
	else:
		for child in actors.values() + portal_markers:
			child.get_parent().remove_child(child)
			child.queue_free()
	actors = {}
	visuals = {}
	portal_markers = []
	_history = _history_key()
	var height: int = map_data.coordinates.tile_height
	_build_portals_and_actors(scene, height)
	_apply_performance()

func _build_diagnostic_tiles() -> void:
	var map_data: Dictionary = _map
	var width: int = map_data.coordinates.tile_width
	var height: int = map_data.coordinates.tile_height
	# Keep the diagnostic handle for callers, without building invisible cells
	# or textures when an authored terrain layer already provides the map.
	tiles = TileMapLayer.new()
	tiles.texture_filter = Sampling.resolve(session.package.world, "map_terrain")
	add_child(tiles)
	if map_data.has("terrain"):
		tiles.visible = false
		return
	var atlas_image = Image.create(width * 2, height, false, Image.FORMAT_RGBA8)
	atlas_image.fill(Color.TRANSPARENT)
	# Procedural diagnostic tiles only; still drawn by the formal TileMapLayer.
	for cell in range(2):
		for y in range(height):
			for x in range(width):
				var distance: float = absf((x + 0.5) / width - 0.5) * 2.0 + absf((y + 0.5) / height - 0.5) * 2.0
				if map_data.coordinates.kind == "isometric" and distance > 1.0: continue
				var edge: bool = distance > 0.92 if map_data.coordinates.kind == "isometric" else x == 0 or y == 0 or x == width - 1 or y == height - 1
				atlas_image.set_pixel(x + cell * width, y, Color("293c39") if edge else (Color("304741") if cell == 0 else Color("6d5947")))
	var source = TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas_image)
	source.texture_region_size = Vector2i(width, height)
	source.create_tile(Vector2i.ZERO)
	source.create_tile(Vector2i(1, 0))
	var tile_set = TileSet.new()
	tile_set.tile_size = Vector2i(width, height)
	if map_data.coordinates.kind == "isometric":
		tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
		tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN

	tile_set.add_source(source, 0)
	tiles.tile_set = tile_set
	# Godot adds a half-tile center offset; the Native contract centers tile (0,0) at zero.
	tiles.position = MapProjection.project(Vector2(map_data.coordinates.origin.x, map_data.coordinates.origin.y), map_data.coordinates) - Vector2(width, height) / 2.0
	for y in int(map_data.height):
		for x in int(map_data.width):
			var logical = {"x": x + map_data.coordinates.origin.x, "y": y + map_data.coordinates.origin.y}
			tiles.set_cell(Vector2i(x, y), 0, Vector2i(1, 0) if session.package.map_blocked[map_data.id].has(Vector2i(logical.x, logical.y)) else Vector2i.ZERO)

func _build_map() -> void:
	var map_data: Dictionary = _map
	_build_diagnostic_tiles()
	backdrop = null
	if map_data.background_asset != null:
		backdrop = Sprite2D.new()
		backdrop.texture_filter = Sampling.resolve(session.package.world, "map_background")
		backdrop.texture = session.package.textures[map_data.background_asset]
		backdrop.centered = false
		var rect: Rect2 = MapProjection.bounds(map_data)
		backdrop.position = rect.position
		backdrop.scale = rect.size / backdrop.texture.get_size()
		add_child(backdrop)
	_actor_layer = Node2D.new()
	_actor_layer.y_sort_enabled = true
	add_child(_actor_layer)
	if map_data.has("terrain"):
		var atlas_cache: Dictionary = {}
		for layer in map_data.terrain.layers:
			if layer.depth_sort:
				depth_tiles.append_array(Terrain.add_depth(map_data, layer, session.package.textures, _actor_layer))
			else:
				var drawn = Terrain.make_flat(map_data, layer, session.package.textures, atlas_cache)
				drawn.texture_filter = Sampling.resolve(session.package.world, "map_terrain")
				add_child(drawn)
				terrain_layers.append(drawn)

	for tile in depth_tiles: tile.texture_filter = Sampling.resolve(session.package.world, "map_terrain")

func _build_portals_and_actors(scene: Dictionary, height: int) -> void:
	for portal in scene.get("portals", []):
		var marker = Polygon2D.new()
		marker.polygon = PackedVector2Array([Vector2(0, -6), Vector2(9, 0), Vector2(0, 6), Vector2(-9, 0)])
		marker.color = Color("bfa766")
		marker.position = MapProjection.project(Vector2(portal.position.x, portal.position.y), _map.coordinates)
		add_child(marker)
		var label = Label.new()
		label.text = portal.display_name
		label.position = Vector2(-50, 8)
		label.size.x = 100
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		marker.add_child(label)
		portal_markers.append(marker)
	for item in session.state.entities:
		if item.scene_id != session.state.cursor.scene_id: continue
		var definition: Dictionary = session.package.index.actor_definitions[item.definition_id]
		var body = Node2D.new()
		_actor_layer.add_child(body)
		var visual = ActorVisual.new()
		body.add_child(visual)
		var color = Color("b4965c") if item.instance_id == session.state.active_party[0] else (Color("74658a") if item.instance_id in session.state.active_party else Color("667f91"))
		visual.bind(definition, session.package, height, color)
		visual.present(item, int(session.state.clock.logic_tick), 0.0, false, item.instance_id == session.state.active_party[0])
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
		label.visible = not _map.has("terrain")
		body.add_child(label)
		actors[item.instance_id] = body
		body.position = MapProjection.project(Vector2(item.position.x, item.position.y), _map.coordinates)

func _process(delta: float) -> void:
	if session == null or session.state.is_empty(): return
	if _history != _history_key():
		bind(session)
		return
	var running: bool = not session.paused and not session.modal and session.focused
	for item in session.state.entities:
		if not actors.has(item.instance_id): continue
		var target = MapProjection.project(Vector2(item.position.x, item.position.y), _map.coordinates)
		# Time-based presentation interpolation only; does not feed world state.
		if running: actors[item.instance_id].position = actors[item.instance_id].position.lerp(target, 1.0 - exp(-24.0 * delta))
		visuals[item.instance_id].present(item, int(session.state.clock.logic_tick), delta, running, item.instance_id == session.state.active_party[0])
	_apply_performance()

func _apply_performance() -> void:
	if not session.performance_open(): return
	var row: Dictionary = MapPerformance.for_node(session.package.world, session.state.cursor.node_id)
	var elapsed: int = int(session.state.extensions[MapPerformance.KEY].active.elapsed_ticks)
	for track in row.tracks:
		var item: Dictionary = session.entity(track.actor_id)
		actors[track.actor_id].position = MapProjection.project(Vector2(item.position.x, item.position.y), _map.coordinates) + Vector2(track.offset.x, track.offset.y)
		visuals[track.actor_id].present_performance(MapPerformance.clip_for(session.package.world, track.clip_id), floori(elapsed * 1000000.0 / 60.0))
		for actor_id in track.hide_actor_ids: actors[actor_id].visible = false

func _history_key(model = null) -> String:
	var value: Dictionary = session.state if model == null else model.state
	var performance = value.extensions.get(MapPerformance.KEY, {}).get("active")
	return "%s/%s/%s/%s/%s/%s/%s/%s" % [value.session_id, value.timeline_epoch, value.cursor.scene_id, value.content_lock, SceneTravel.revision(value), PartyTrail.revision(value), JSON.stringify(value.active_party), "" if performance == null else performance.node_id]
