# SPDX-License-Identifier: MIT
# Parameterized real data test. No original assets or source locations in this repo.
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Terrain = preload("res://src/native_terrain.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
const Save = preload("res://src/native_save.gd")
const Schema = preload("res://src/native_schema.gd")
const AppScene = preload("res://scenes/main.tscn")
var checks: Array = []
var failures: int = 0
var output: String

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok:
		failures += 1
		push_error(name)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(2)
		return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var app = AppScene.instantiate(); root.size = Vector2i(1280, 800); root.add_child(app)
	await process_frame
	app.set_physics_process(false)
	check(app.open_package(args[0]), "normal bounded loader activates actual terrain and source PNG package")
	if app.session.state.is_empty():
		quit(1)
		return
	app.session.advance_dialogue(); app.session.advance_dialogue(app.session.current_node().options[1].id); app.session.set_focus(true)
	var package = app.session.package
	var map_data: Dictionary = package.index.maps[package.index.scenes[app.session.state.cursor.scene_id].map_id]
	var world = app.world_view; world.set_process(false)
	var id: String = app.session.state.active_party[0]
	check(map_data.terrain.cells.size() == 16384 and map_data.blocked.size() == 687, "all actual source cells and collision flags retained")
	check(world.terrain_layers.size() == 2 and world.terrain_layers.all(func(layer): return layer is TileMapLayer), "actual lower and upper images use TileMapLayer")
	check(world.terrain_layers[0].tile_set == world.terrain_layers[1].tile_set, "flat layers share padded GPU textures instead of multiplying the image budget")
	check(world.terrain_layers[0].tile_set.get_source_count() == 1, "296 actual source tiles share one GPU atlas")
	check(world.tiles.get_used_cells().is_empty(), "real terrain does not allocate hidden diagnostic cells")
	check(world.terrain_layers[0].get_used_cells().size() == 16384 and world.terrain_layers[1].get_used_cells().size() == 3391, "both actual layers retain every placement")
	check(world.depth_tiles.size() == 932, "explicit depth approximation keeps both source height groups")
	check(not package.can_stand(app.session.state.cursor.scene_id, {"x": 0, "y": -63}), "bounding rectangle gap is unavailable")
	check(map_data.blocked.all(func(point): return not package.can_stand(app.session.state.cursor.scene_id, point)), "every original blocked cell rejects standing")
	check(app._terrain_camera and world.scale == Vector2(2, 2), "real map uses a following view instead of shrinking the entire map")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("terrain-start.png"))
	var before: Dictionary = app.session.snapshot()
	var map_node: int = world.terrain_layers[0].get_instance_id()
	var actor_node: int = world.actors[id].get_instance_id()
	world.bind(app.session)
	check(world.terrain_layers[0].get_instance_id() == map_node and world.actors[id].get_instance_id() != actor_node, "same immutable map retains terrain while resetting actor presentation")
	check(not app.session.move(Vector2i.LEFT) and app.session.snapshot() == before, "source blocked neighbor rejects whole move without altering state")
	for direction in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]:
		for _tick in range(6): app.session.tick()
		var previous: Dictionary = app.session.entity(id).position.duplicate()
		check(app.session.move(direction), "source courtyard accepts route step " + str(direction))
		world._process(0.5); app._follow_world()
		var current: Dictionary = app.session.entity(id).position
		check(Vector2i(current.x - previous.x, current.y - previous.y) == direction, "map PNGs do not change logical step " + str(direction))
		check(world.actors[id].position.distance_to(MapProjection.project(Vector2(current.x, current.y), map_data.coordinates)) < 0.01, "feet converge to imported grid " + str(direction))
		check(app.session.state.active_party.all(func(member): return package.can_stand(app.session.entity(member).scene_id, app.session.entity(member).position)), "all four party members remain on available source cells")
	var storage = Save.new(output.path_join("saves")); before = app.session.snapshot()
	check(storage.save(app.session), "actual terrain play writes an isolated Native save")
	var save_path: String = storage.last_path
	for _tick in range(6): app.session.tick()
	app.session.move(Vector2i.DOWN)
	check(storage.load_into(app.session, save_path), "actual terrain save reloads with the same source content lock")
	check(app.session.entity(id).position == before.entities[0].position, "terrain save restores authoritative foot position")
	world._process(0.0); app._fit_world()
	check(world.visuals[id].elapsed_us == 0.0, "load resets map animation presentation history")
	check(world.terrain_layers[0].get_instance_id() == map_node, "save restore keeps same immutable terrain nodes")
	var invalid: Dictionary = app.session.snapshot(); invalid.entities[0].position = {"x": 0, "y": -63}
	check(not app.session.restore(invalid), "saved position validator rejects rectangle gaps")
	var retained: Dictionary = app.session.snapshot()
	for defect in ["missing-capability", "dimensions", "unavailable-spawn", "flat-offset"]:
		check(not app.open_package(_variant(args[0], defect)) and app.session.snapshot() == retained, "bad terrain cannot replace active session: " + defect)
	await _render_checks(package, map_data)
	await _packed_checks(map_data)
	await _flat_map_check(package, map_data, args[2])
	check(Terrain._atlas_grid(Vector2i(32, 16), 296) != Vector2i.ZERO, "common original tile sizes fit bounded packed atlas")
	check(Terrain._atlas_grid(Vector2i(8192, 8192), 1) == Vector2i.ZERO and Terrain._atlas_grid(Vector2i(4096, 4096), 16) == Vector2i.ZERO, "oversized and wasteful HD packing falls back before allocation")
	var previous_texture = world.terrain_layers[0].tile_set.get_source(0).texture
	check(app.open_package(args[0]), "same path can be opened as a fresh validated package")
	check(world.terrain_layers[0].get_instance_id() != map_node and world.terrain_layers[0].tile_set.get_source(0).texture != previous_texture, "new package instance never keeps prior terrain or GPU texture identity")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("terrain-restored.png"))
	var report: Dictionary = {"passed": checks.size() - failures, "failed": failures, "checks": checks, "save_path": save_path,
		"real_source_map": true, "real_source_frames": true, "synthetic_story": true, "physical_input": false, "full_playthrough": false,
		"hd_art_acceptance": false, "legacy_occlusion_parity": false, "renderer": RenderingServer.get_current_rendering_method()}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print(JSON.stringify(report)); quit(0 if failures == 0 else 1)

func _render_checks(package, map_data: Dictionary) -> void:
	var viewport = SubViewport.new(); viewport.size = Vector2i(96, 96); viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var sample: Dictionary = map_data.duplicate(true); sample.coordinates.origin = {"x": 0, "y": 0}
	sample.terrain.tiles = [sample.terrain.tiles[0]]
	var layer: Dictionary = {"id": "layer.test", "draw_order": -1, "depth_sort": false, "placements": [{"position": {"x": 0, "y": 0}, "tile_id": sample.terrain.tiles[0].id, "sort_offset_y": 0}]}
	var floor_layer = Terrain.make_flat(sample, layer, package.textures, {}); floor_layer.position += Vector2(48, 48); viewport.add_child(floor_layer)
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image(); var source: Image = package.textures[sample.terrain.tiles[0].asset_id].get_image(); var equal: bool = true
	for y in source.get_height():
		for x in source.get_width():
			if source.get_pixel(x, y).a > 0.99 and not source.get_pixel(x, y).is_equal_approx(image.get_pixel(32 + x, 40 + y)): equal = false
	check(equal, "real odd-height tile has exact palette and (16,8) raster anchor through TileMapLayer")
	floor_layer.queue_free(); await process_frame
	var hd = Image.create(64, 30, false, Image.FORMAT_RGBA8); hd.fill(Color.GREEN)
	sample.terrain.tiles[0] = {"id": "tile.hd", "asset_id": "asset.hd", "width": 64, "height": 30, "anchor": {"x": 32, "y": 16}, "scale_milli": 500}
	layer.placements[0].tile_id = "tile.hd"
	var hd_layer = Terrain.make_flat(sample, layer, {"asset.hd": ImageTexture.create_from_image(hd)}, {})
	check(hd_layer is TileMapLayer and hd_layer.scale == Vector2(0.5, 0.5) and hd_layer.tile_set.get_source(0).texture.get_width() == 64, "synthetic 2x texture retains source detail and logical cell scale")
	hd_layer.free()
	sample.terrain.tiles[0].scale_milli = 333
	var arbitrary = Terrain.make_flat(sample, layer, {"asset.hd": ImageTexture.create_from_image(hd)}, {})
	check(arbitrary is Terrain.FlatLayer and is_equal_approx(arbitrary.items[0].rect.size.x, 64 * 0.333), "nonintegral HD scale has a CanvasItem path without resampling")
	arbitrary.free()
	var parent = Node2D.new(); parent.position = Vector2(48, 48); parent.y_sort_enabled = true; viewport.add_child(parent)
	var red = Image.create(16, 16, false, Image.FORMAT_RGBA8); red.fill(Color.RED)
	sample.terrain.tiles = [{"id": "tile.cover", "asset_id": "asset.cover", "width": 16, "height": 16, "anchor": {"x": 8, "y": 16}, "scale_milli": 1000}]
	layer.placements[0].tile_id = "tile.cover"; layer.placements[0].sort_offset_y = 10
	var covers = Terrain.add_depth(sample, layer, {"asset.cover": ImageTexture.create_from_image(red)}, parent)
	check(covers[0].position + covers[0].get_child(0).position == Vector2(-8, -16), "sorting offset does not move tile raster")
	var body = Node2D.new(); body.position = Vector2(0, 7); parent.add_child(body)
	var blue = Image.create(8, 32, false, Image.FORMAT_RGBA8); blue.fill(Color.BLUE)
	var sprite = Sprite2D.new(); sprite.centered = false; sprite.position = Vector2(-4, -32); sprite.texture = ImageTexture.create_from_image(blue); body.add_child(sprite)
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(48, 40).r > 0.99, "synthetic actor behind explicit depth is occluded")
	body.position.y = 13; await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(48, 40).b > 0.99, "synthetic actor in front is visible")
	body.position.y = 10; await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(48, 40).b > 0.99, "equal depth preserves actor-after-terrain tie order")
	viewport.queue_free(); await process_frame

func _packed_checks(map_data: Dictionary) -> void:
	var viewport = SubViewport.new(); viewport.size = Vector2i(96, 96); viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var sample: Dictionary = map_data.duplicate(true); sample.coordinates.origin = {"x": 0, "y": 0}
	sample.terrain.tiles = [
		{"id": "tile.red", "asset_id": "asset.red", "width": 11, "height": 9, "anchor": {"x": 3, "y": 1}, "scale_milli": 1000},
		{"id": "tile.green", "asset_id": "asset.green", "width": 17, "height": 15, "anchor": {"x": 1, "y": 14}, "scale_milli": 1000}]
	var red = Image.create(11, 9, false, Image.FORMAT_RGBA8); red.fill(Color.RED)
	var green = Image.create(17, 15, false, Image.FORMAT_RGBA8); green.fill(Color.GREEN)
	var layer: Dictionary = {"id": "layer.packed", "draw_order": -1, "depth_sort": false, "placements": [
		{"position": {"x": 0, "y": 0}, "tile_id": "tile.red", "sort_offset_y": 0},
		{"position": {"x": 1, "y": 0}, "tile_id": "tile.green", "sort_offset_y": 0}]}
	var packed = Terrain.make_flat(sample, layer, {"asset.red": ImageTexture.create_from_image(red), "asset.green": ImageTexture.create_from_image(green)}, {})
	packed.position += Vector2(48, 48); viewport.add_child(packed)
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	check(packed.tile_set.get_source_count() == 1 and packed.get_cell_atlas_coords(Vector2i(1, 0)) != Vector2i.ZERO, "unequal synthetic images use distinct coordinates in one atlas")
	check(image.get_pixel(45, 47).r > 0.99 and image.get_pixel(63, 42).g > 0.99 and image.get_pixel(44, 47).a == 0.0 and image.get_pixel(63, 41).a == 0.0, "noncentral anchors and different image sizes retain exact GPU raster positions")
	packed.queue_free(); await process_frame
	# Each thin image is small; only the hypothetical common cell is expensive.
	# Exercise the actual fallback without allocating a giant test image.
	sample.coordinates.tile_width = 2; sample.coordinates.tile_height = 2
	sample.terrain.tiles[0].width = 4096; sample.terrain.tiles[0].height = 2; sample.terrain.tiles[0].anchor = {"x": 2048, "y": 1}
	sample.terrain.tiles[1].width = 2; sample.terrain.tiles[1].height = 4096; sample.terrain.tiles[1].anchor = {"x": 1, "y": 2048}
	red = Image.create(4096, 2, false, Image.FORMAT_RGBA8); red.fill(Color.RED)
	green = Image.create(2, 4096, false, Image.FORMAT_RGBA8); green.fill(Color.GREEN)
	var separate = Terrain.make_flat(sample, layer, {"asset.red": ImageTexture.create_from_image(red), "asset.green": ImageTexture.create_from_image(green)}, {})
	separate.position += Vector2(48, 48); viewport.add_child(separate)
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	check(separate.tile_set.get_source_count() == 2 and separate.get_cell_atlas_coords(Vector2i(1, 0)) == Vector2i.ZERO, "uneven HD sizes actually use separate bounded sources")
	check(image.get_pixel(25, 48).r > 0.99 and image.get_pixel(49, 25).g > 0.99, "nonpacked fallback retains both source anchors in GPU rendering")
	viewport.queue_free(); await process_frame

func _flat_map_check(package, map_data: Dictionary, reference_path: String) -> void:
	var expected = Image.load_from_file(reference_path)
	var viewport = SubViewport.new(); viewport.size = expected.get_size(); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var black = ColorRect.new(); black.size = Vector2(viewport.size); black.color = Color.BLACK; black.z_index = -3; viewport.add_child(black)
	var atlas_cache: Dictionary = {}
	for definition in map_data.terrain.layers:
		if definition.depth_sort: continue
		var layer = Terrain.make_flat(map_data, definition, package.textures, atlas_cache); layer.position += Vector2(16, 8); viewport.add_child(layer)
	await RenderingServer.frame_post_draw
	var actual = viewport.get_texture().get_image(); actual.convert(Image.FORMAT_RGBA8); expected.convert(Image.FORMAT_RGBA8)
	actual.save_png(output.path_join("flat-map-native.png"))
	var left = expected.get_data(); var right = actual.get_data(); var differences: int = 0
	for index in left.size():
		if absi(int(left[index]) - int(right[index])) > 1: differences += 1
	check(differences == 0, "full actual lower-upper map matches independent tool overview within one byte per channel (different channels: %d)" % differences)
	viewport.queue_free(); await process_frame

func _variant(path: String, defect: String) -> String:
	var reader = ZIPReader.new(); reader.open(path); var files: Dictionary = {}
	for name in reader.get_files(): files[name] = reader.read_file(name)
	reader.close()
	var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
	var content: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
	var map_data: Dictionary = content.maps[0]
	if defect == "missing-capability": manifest.required_capabilities.erase("world.tile-layers.v1")
	if defect == "dimensions": map_data.terrain.tiles[0].width += 1
	if defect == "unavailable-spawn": map_data.terrain.cells.erase(content.entities[0].position)
	if defect == "flat-offset": map_data.terrain.layers[0].placements[0].sort_offset_y = 1
	files["content/world.json"] = JSON.stringify(content).to_utf8_buffer()
	for row in manifest.files: row.sha256 = Schema.digest(files[row.path]); row.size_bytes = files[row.path].size()
	files["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
	var path_out: String = output.path_join(defect + ".zip"); var writer = ZIPPacker.new(); writer.open(path_out)
	for name in files: writer.start_file(name); writer.write_file(files[name]); writer.close_file()
	writer.close(); return path_out
