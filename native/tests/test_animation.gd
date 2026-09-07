# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const World = preload("res://src/native_world.gd")
const MapAnimation = preload("res://src/native_map_animation.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var failures: int = 0
var scratch: String

func check(condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})
	if not condition:
		failures += 1
		push_error(name)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	scratch = args[1]
	DirAccess.make_dir_recursive_absolute(scratch)
	var package = Package.new()
	check(package.load_package(args[0]), "actual Studio animation ZIP loads and fully decodes PNG frames")
	if not package.error.is_empty():
		push_error(package.error)
		quit(1)
		return
	var session = Session.new()
	check(session.activate(package, 0), "animated content activates with no Legacy data")
	root.size = Vector2i(1100, 800)
	var world = World.new()
	root.add_child(world)
	world.set_process(false)
	world.position = Vector2(60, 100)
	world.bind(session)
	check(world.tiles is TileMapLayer and world.visuals.size() == 5, "same TileMapLayer world renders five animated instances")
	var leader_id: String = session.state.active_party[0]
	var visual = world.visuals[leader_id]
	check(visual.sprite.visible and not visual.fallback.visible, "declared animation replaces static placeholder")
	await process_frame
	await RenderingServer.frame_post_draw
	var image_dir = ProjectSettings.globalize_path("res://generated/pal/visual_tests").path_join(Session.unique("animation"))
	DirAccess.make_dir_recursive_absolute(image_dir)
	root.get_texture().get_image().save_png(image_dir.path_join("01-idle.png"))
	session.advance_dialogue()
	session.advance_dialogue(package.world.nodes[1].options[0].id)
	for _i in 8: session.tick()
	var before_move = session.snapshot()
	check(session.move(Vector2i.DOWN), "logic movement selects walking pose")
	var leader: Dictionary = session.entity(leader_id)
	check(leader.components["pal.native.pose"].facing == "down", "leader uses logical world direction")
	var all_facings: bool = true
	for i in range(1, 4):
		var item: Dictionary = session.entity(session.state.active_party[i])
		var old: Dictionary = before_move.entities[i].position
		var delta = Vector2i(item.position.x - old.x, item.position.y - old.y)
		var expected: String = ("right" if delta.x > 0 else "left") if absi(delta.x) > absi(delta.y) else ("down" if delta.y > 0 else "up")
		all_facings = all_facings and (delta == Vector2i.ZERO or item.components["pal.native.pose"].facing == expected)
	check(all_facings, "all followers update their own direction, not the leader direction")
	visual.present(leader, int(session.state.clock.logic_tick), 0.0, true)
	var first: String = visual.displayed_frame.frame_id
	var first_size: Vector2 = visual.sprite.texture.get_size()
	var before = session.snapshot()
	visual.present(leader, int(session.state.clock.logic_tick), 0.010, true)
	check(visual.displayed_frame.frame_id != first and visual.sprite.texture.get_size() != first_size, "100 Hz frame timing selects a different sized PNG without a logic tick")
	check(session.state == before, "rendering frames does not mutate authoritative state")
	var frame: Dictionary = visual.displayed_frame
	check(visual.sprite.position + Vector2(frame.anchor.x, frame.anchor.y) * visual.sprite.scale == Vector2.ZERO, "second-sized frame keeps exact foot anchor")
	check(visual.sprite.scale == Vector2.ONE * 0.125, "declared HD scale is used without automatic texture fit")
	check(visual.sprite.texture.get_image().get_pixel(0, 0).a == 0.0, "actual texture alpha preserves empty padding")
	var elapsed: float = visual.elapsed_us
	session.set_pause(true, 0)
	world._process(0.1)
	check(visual.elapsed_us == elapsed and session.state.clock.logic_tick == before.clock.logic_tick, "pause freezes animation and logical clock")
	session.set_pause(false, 0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(image_dir.path_join("02-walk-second-frame.png"))
	var clip: Dictionary = MapAnimation.clip_for(package.world.sprite_sets[0], "walk", "down")
	check(MapAnimation.frame_at(clip, 9999).frame_id == first and MapAnimation.frame_at(clip, 10000).frame_id != first and MapAnimation.frame_at(clip, 20000).frame_id == first, "frame boundaries use half-open intervals and explicit looping")
	var hold: Dictionary = clip.duplicate(true)
	hold.loop = false
	check(MapAnimation.frame_at(hold, 9000000).frame_id == hold.frames[-1].frame_id, "non-looping clips hold their final frame")
	var fallback: Dictionary = package.world.sprite_sets[0].duplicate(true)
	fallback.clips = fallback.clips.filter(func(c): return c.action == "idle")
	fallback.missing_action = "idle"
	check(MapAnimation.clip_for(fallback, "walk", "left").facing == "left", "missing walk falls back to same-direction idle")
	fallback.missing_action = "static"
	check(MapAnimation.clip_for(fallback, "walk", "left").is_empty(), "explicit static fallback has no implicit animation")
	var storage = Save.new(scratch.path_join("saves"))
	check(storage.save(session), "walking pose persists in an actual isolated save")
	var save_path: String = storage.last_path
	for _i in 8: session.tick()
	session.move(Vector2i.RIGHT)
	check(storage.load_into(session, save_path), "saved pose reloads through the same storage consumer")
	world._process(0.05)
	visual = world.visuals[leader_id]
	check(visual.elapsed_us == 0.0 and visual.selection == "walk/down", "load epoch resets visual history while retaining pose action and facing")
	var restored: Dictionary = session.entity(leader_id).position
	var restored_map: Dictionary = package.index.maps[package.index.scenes[session.state.cursor.scene_id].map_id]
	check(world.actors[leader_id].position == MapProjection.project(Vector2(restored.x, restored.y), restored_map.coordinates), "load snaps to restored foot position without old interpolation history")
	check(not session.move(Vector2i.DOWN), "load retains remaining logical movement cooldown")
	var old_save = session.snapshot()
	for item in old_save.entities: item.components["pal.native.pose"].erase("moving_until_tick")
	check(session.restore(old_save, 0), "older draft pose without deadline loads as idle")
	var invalid_pose = session.snapshot()
	invalid_pose.entities[0].components["pal.native.pose"].moving_until_tick = int(invalid_pose.clock.logic_tick) + 9
	check(not session.restore(invalid_pose, 0), "future movement deadline rejected before state replacement")
	_test_rejected_packages(args[0])
	var color_evidence: Dictionary = await _test_truecolor(package, args[0], image_dir)
	var report = {"passed": checks.size() - failures, "failed": failures, "checks": checks, "images": image_dir, "save": save_path, "truecolor": color_evidence, "synthetic_assets": true, "physical_input": false, "full_playthrough": false}
	var output = FileAccess.open(scratch.path_join("results.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ", true))
	output.close()
	print(JSON.stringify(report))
	quit(0 if failures == 0 else 1)

func _test_truecolor(package, package_path: String, image_dir: String) -> Dictionary:
	var archive = ZIPReader.new()
	archive.open(package_path)
	var visible_changes: int = 0
	var alpha_changes: int = 0
	var minimum_colors: int = 16777216
	var first_source: Image
	var first_texture: Texture2D
	var alphas: Dictionary = {}
	for asset in package.world.assets:
		var source = Image.new()
		source.load_png_from_buffer(archive.read_file(asset.path))
		source.convert(Image.FORMAT_RGBA8)
		var texture: Texture2D = package.textures[asset.id]
		var loaded: Image = texture.get_image()
		loaded.convert(Image.FORMAT_RGBA8)
		var before: PackedByteArray = source.get_data()
		var after: PackedByteArray = loaded.get_data()
		var colors: Dictionary = {}
		for offset in range(0, before.size(), 4):
			var a: int = before[offset + 3]
			alphas[a] = true
			if a != after[offset + 3]: alpha_changes += 1
			if a > 0 and (before[offset] != after[offset] or before[offset + 1] != after[offset + 1] or before[offset + 2] != after[offset + 2]): visible_changes += 1
			if a == 255: colors[(int(after[offset]) << 16) | (int(after[offset + 1]) << 8) | int(after[offset + 2])] = true
		minimum_colors = mini(minimum_colors, colors.size())
		if first_source == null:
			first_source = source
			first_texture = texture
	archive.close()
	check(minimum_colors > 256, "every Studio-packaged frame keeps more than 256 opaque RGB colors in the runtime texture")
	check(visible_changes == 0 and alpha_changes == 0, "all visible source RGB and all alpha bytes survive texture preparation unchanged")
	check(alphas.size() == 256, "the packaged fixture and runtime retain all 256 alpha levels, including 1..19")
	var fixed_image: Image = first_texture.get_image()
	check(first_source.get_pixel(39, 20) == Color(1, 1, 1, 0) and fixed_image.get_pixel(39, 20).a == 0.0 and fixed_image.get_pixel(39, 20).r < 0.05, "transparent white beside a saturated edge receives neighboring RGB without becoming visible")
	# Read the same loaded texture back through the actual GPU path at 1:1.
	var viewport = SubViewport.new()
	viewport.size = first_source.get_size()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite = Sprite2D.new()
	sprite.texture = first_texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = viewport.get_texture().get_image()
	rendered.save_png(image_dir.path_join("03-truecolor.png"))
	var gpu_colors: Dictionary = {}
	var opaque_mismatch: int = 0
	var gpu_alpha_mismatch: int = 0
	for y in first_source.get_height():
		for x in first_source.get_width():
			var original: Color = first_source.get_pixel(x, y)
			var actual: Color = rendered.get_pixel(x, y)
			if absf(original.a - actual.a) > 1.0 / 255.0 + 0.00001: gpu_alpha_mismatch += 1
			if original.a == 1.0:
				gpu_colors[actual.to_rgba32()] = true
				if absf(original.r - actual.r) > 1.0 / 255.0 + 0.00001 or absf(original.g - actual.g) > 1.0 / 255.0 + 0.00001 or absf(original.b - actual.b) > 1.0 / 255.0 + 0.00001: opaque_mismatch += 1
	check(gpu_colors.size() > 256 and opaque_mismatch == 0, "GPU readback retains over 256 opaque colors within one channel byte at 1:1")
	check(gpu_alpha_mismatch == 0, "GPU readback retains the alpha ramp within one byte")
	viewport.queue_free()
	# Same packaged image, raw versus prepared, under linear magnification.
	var edge_view = SubViewport.new()
	edge_view.size = Vector2i(256, 128)
	edge_view.transparent_bg = true
	edge_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(edge_view)
	for i in 2:
		var atlas = AtlasTexture.new()
		atlas.atlas = ImageTexture.create_from_image(first_source) if i == 0 else first_texture
		atlas.region = Rect2(36, 16, 8, 8)
		var edge = Sprite2D.new()
		edge.texture = atlas
		edge.centered = false
		edge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		edge.scale = Vector2(16, 16)
		edge.position.x = i * 128
		edge_view.add_child(edge)
	await process_frame
	await RenderingServer.frame_post_draw
	var edge_image: Image = edge_view.get_texture().get_image()
	edge_image.save_png(image_dir.path_join("04-transparent-edge-before-after.png"))
	var raw_edge: Color = edge_image.get_pixel(60, 64)
	var fixed_edge: Color = edge_image.get_pixel(188, 64)
	check(raw_edge.a > 0 and raw_edge.a < 1 and absf(raw_edge.a - fixed_edge.a) < 0.005 and raw_edge.r > fixed_edge.r + 0.05, "linear GPU filtering no longer mixes the transparent white matte into the edge; coverage stays unchanged")
	edge_view.queue_free()
	return {"frames": package.world.assets.size(), "min_opaque_rgb_colors": minimum_colors, "visible_rgb_changes": visible_changes, "alpha_changes": alpha_changes, "alpha_levels": alphas.size(), "gpu_opaque_colors": gpu_colors.size(), "gpu_opaque_mismatches": opaque_mismatch, "gpu_alpha_mismatches": gpu_alpha_mismatch, "raw_edge_rgba": [raw_edge.r, raw_edge.g, raw_edge.b, raw_edge.a], "prepared_edge_rgba": [fixed_edge.r, fixed_edge.g, fixed_edge.b, fixed_edge.a], "rendering_device": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method()}

func _test_rejected_packages(path: String) -> void:
	var reader = ZIPReader.new()
	reader.open(path)
	var files: Dictionary = {}
	for name in reader.get_files(): files[name] = reader.read_file(name)
	reader.close()
	for defect in ["dimensions", "anchor", "duplicate_clip", "duplicate_frame", "duration_zero", "missing_asset", "missing_capability", "invalid_png"]:
		var changed: Dictionary = files.duplicate(true)
		var content: Dictionary = JSON.parse_string(changed["content/world.json"].get_string_from_utf8())
		var manifest: Dictionary = JSON.parse_string(changed["manifest.json"].get_string_from_utf8())
		var sprite: Dictionary = content.sprite_sets[0]
		var frame: Dictionary = sprite.clips[0].frames[0]
		match defect:
			"dimensions": frame.width += 1
			"anchor": frame.anchor.y = frame.height + 1
			"duplicate_clip": sprite.clips[1] = sprite.clips[0].duplicate(true)
			"duplicate_frame": sprite.clips[0].frames.append(frame.duplicate(true))
			"duration_zero": frame.duration_us = 0
			"missing_asset": frame.asset_id = "asset.missing"
			"missing_capability": manifest.required_capabilities.erase(MapAnimation.CAPABILITY)
			"invalid_png":
				var asset: Dictionary = content.assets[0]
				changed[asset.path] = "not an image".to_utf8_buffer()
				asset.sha256 = Schema.digest(changed[asset.path])
				asset.size_bytes = changed[asset.path].size()
		changed["content/world.json"] = JSON.stringify(content).to_utf8_buffer()
		for row in manifest.files:
			row.sha256 = Schema.digest(changed[row.path])
			row.size_bytes = changed[row.path].size()
		changed["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
		var target: String = scratch.path_join(defect + ".zip")
		var writer = ZIPPacker.new()
		writer.open(target)
		for name in changed:
			writer.start_file(name)
			writer.write_file(changed[name])
			writer.close_file()
		writer.close()
		var rejected = Package.new()
		check(not rejected.load_package(target), "reject declared animation " + defect + " without silent fallback")
