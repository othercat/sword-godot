# SPDX-License-Identifier: MIT
extends SceneTree
## Explicit resource-composition comparison; does not create an original Session.
const Package = preload("res://src/native_package.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
const Queue = preload("res://src/native_pal98_depth_queue.gd")
const Schema = preload("res://src/native_schema.gd")
var output: String
var checks: Array = []
var cases: Array = []
var failed: int = 0
var complete: bool = false

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3: quit(2); return
	output = args[2]
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): quit(2); return
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if reference.get("cases", []).size() != 6 or not reference.get("source_unchanged", false) or not reference.get("guarded_output", false): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(180).timeout.connect(func(): check(false, "scene graphics watchdog expired"); finish())
	var package = Package.new(); check(package.load_package(args[0]), "ordinary author graphics package admitted: " + package.error)
	if package.pal98_graphics == null: finish(); return
	var records = package.pal98_graphics.open_records()
	var files: Dictionary = records.metadata().files
	check(files["MAP.MKF"].sha256 == "62739644af65b5e80c0736d31da00e4fe805a56ee5c5fede6558c0c13bacd575" and files["GOP.MKF"].sha256 == "5745d016a8d9c280b90a8b92d2871210a2dd0a0c04a79d4c8e65f4d0396aa04b" and files["MGO.MKF"].sha256 == "62ce20393e378c80538ba8b9ad1a24112e491f5afc5f350c5ebb00190b2317a0", "admitted bytes match fixed original scene oracle sources")
	var palette: PackedByteArray = records.palette(0, 0).value
	root.size = Vector2i(1040, 720); root.title = "PAL Wanxiang | original source scene composition"
	var viewport = SubViewport.new(); viewport.size = Vector2i(320, 200); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST; root.add_child(viewport)
	var underlay = ColorRect.new(); underlay.size = Vector2(320, 200); underlay.z_index = -3
	underlay.color = Color8(palette[0] * 4, palette[1] * 4, palette[2] * 4); viewport.add_child(underlay)
	var display = TextureRect.new(); display.texture = viewport.get_texture(); display.position = Vector2(40, 60); display.size = Vector2(960, 600)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; root.add_child(display)
	var label = Label.new(); label.position = Vector2(40, 20); root.add_child(label)
	var background = Background.new(); var occlusion = Occlusion.new(); var queue = Queue.new()
	for scene in reference.cases:
		check(background.load_source(records, scene.map, 0, 0) and occlusion.load_source(records, scene.map), "original map and explicit day palette loaded: " + scene.name)
		var rows: Array = []
		for sprite in scene.sprites:
			var frame: Dictionary = records.frame("MGO.MKF", sprite.mgo, sprite.frame)
			check(not frame.has("error"), "selected source sprite decoded: " + scene.name)
			if frame.has("error"): finish(); return
			var row: Dictionary = Queue.row_for_sprite(sprite.kind, sprite.x, sprite.y, sprite.layer, frame.value, frame.source)
			check(not row.has("error"), "source sprite T163 row formed")
			if row.has("error"): finish(); return
			rows.append(row.value)
			var mark: Dictionary = occlusion.mark_sprite(sprite.x, sprite.y, scene.viewport_x, scene.viewport_y, sprite.layer, frame.value.width, frame.value.height, 0)
			check(not mark.has("error"), "T163 source bbox marks accepted: " + str(mark.get("error", "")))
			if mark.has("error"): finish(); return
		var expected_flags: PackedByteArray = FileAccess.get_file_as_bytes(args[1].get_base_dir().path_join(scene.flags))
		check(occlusion.marks() == expected_flags, "all16384 map flag bytes equal original exrij/exbb: " + scene.name)
		var map_rows: Dictionary = occlusion.queue_rows(scene.viewport_x, scene.viewport_y)
		check(not map_rows.has("error"), "original marked GOP frames queued: " + str(map_rows.get("error", "")))
		if map_rows.has("error"): finish(); return
		if scene.map != 20: check(not map_rows.value.is_empty(), "real occluding tiles required for map10/12 coverage")
		rows.append_array(map_rows.value)
		check(queue.load_rows(rows), "explicit sprites then original map rows admitted")
		var map_view: Dictionary = background.make_view(scene.map_x, scene.map_y, scene.half)
		var depth_view: Dictionary = queue.make_view(palette, 200)
		check(not map_view.has("error") and not depth_view.has("error"), "source background and depth GPU candidates prepared")
		if map_view.has("error") or depth_view.has("error"): finish(); return
		viewport.add_child(map_view.value); viewport.add_child(depth_view.value)
		label.text = "原包场景图形组合 · %s · 显式测试帧，原版脚本未运行" % scene.name
		await process_frame; await RenderingServer.frame_post_draw
		var original: PackedByteArray = FileAccess.get_file_as_bytes(args[1].get_base_dir().path_join(scene.path))
		var expected = PackedByteArray(); expected.resize(original.size() * 4)
		for pixel in range(original.size()):
			for channel in range(3): expected[pixel * 4 + channel] = palette[original[pixel] * 3 + channel] * 4
			expected[pixel * 4 + 3] = 255
		var image: Image = viewport.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
		var actual: PackedByteArray = image.get_data()
		check(original.size() == 64000 and actual == expected, "actual GPU composition equals original vmap/T163 marks/exmap/ntre: " + scene.name)
		cases.append({"name": scene.name, "map_rows": map_rows.value.size(), "sprite_rows": scene.sprites.size(), "equal": actual == expected,
			"flags_sha256": Schema.digest(expected_flags), "expected_rgba_sha256": Schema.digest(expected), "actual_rgba_sha256": Schema.digest(actual)})
		image.save_png(output.path_join(scene.name + "-actual.png"))
		if actual != expected: Image.create_from_data(320, 200, false, Image.FORMAT_RGBA8, expected).save_png(output.path_join(scene.name + "-expected.png"))
		if scene.name in ["map20-party", "map10-event-party"]: root.get_texture().get_image().save_png(output.path_join(scene.name + "-window.png"))
		map_view.value.queue_free(); depth_view.value.queue_free(); await process_frame
	complete = true; finish()

func finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": complete and failed == 0, "complete": complete, "failed": failed, "checks": checks, "cases": cases,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "original_gameplay": false,
		"explicit_test_state": true, "source_palette": {"chunk": 0, "variant": 0}, "mac_amd_acceptance": false}, "\t")); file.close()
	print("Original source scene graphics: ", checks.size(), " checks, ", failed, " failed"); quit(0 if complete and failed == 0 else 1)
