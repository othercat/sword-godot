# SPDX-License-Identifier: MIT
extends SceneTree
const Queue = preload("res://src/native_pal98_depth_queue.gd")
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
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
	if args.size() != 2: quit(2); return
	output = args[1]
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): quit(2); return
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if reference.get("cases", []).size() != 13 or not reference.get("guarded_output", false) or not reference.get("tree_consumed", false): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(120).timeout.connect(func(): check(false, "depth queue watchdog expired"); finish())
	root.size = Vector2i(1040, 720); root.title = "PAL Wanxiang | original depth queue comparison"
	var viewport = SubViewport.new(); viewport.size = Vector2i(320, 200)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var palette = PackedByteArray(); palette.resize(768)
	for colour in range(256):
		palette[colour * 3] = colour % 64; palette[colour * 3 + 1] = (colour * 7) % 64; palette[colour * 3 + 2] = (colour * 13) % 64
	# Distinguish literal0/255 from the explicit index7 background.
	palette[765] = 0; palette[766] = 0; palette[767] = 63
	var underlay = ColorRect.new(); underlay.size = Vector2(320, 200); underlay.z_index = -3
	var initial: int = reference.initial_index
	underlay.color = Color8(palette[initial * 3] * 4, palette[initial * 3 + 1] * 4, palette[initial * 3 + 2] * 4); viewport.add_child(underlay)
	var display = TextureRect.new(); display.texture = viewport.get_texture(); display.position = Vector2(40, 60); display.size = Vector2(960, 600)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; root.add_child(display)
	var label = Label.new(); label.position = Vector2(40, 20); root.add_child(label)
	var queue = Queue.new()
	for scene in reference.cases:
		var rows: Array = []
		for row in scene.rows:
			var decoded: Dictionary = Indexed.rle(str(row.rle).hex_decode())
			if decoded.has("error"): check(false, "synthetic oracle RLE invalid"); finish(); return
			rows.append({"x": int(row.x), "sort_y": int(row.sort_y), "layer_offset": int(row.layer_offset), "frame": decoded.value,
				"source": {"fixture": scene.name, "index": rows.size()}})
		check(queue.load_rows(rows), "source-order rows accepted: " + scene.name)
		if scene.name == "nonstable-tie": check(queue.draw_order().map(func(row): return row.submission_index) == [2, 1, 0], "nonstable equal-depth ordering matches original")
		if scene.name == "signed-depth": check(queue.draw_order().map(func(row): return row.submission_index) == [1, 0], "depth comparison is signed16")
		if scene.name == "wrapped-top": check(queue.draw_order()[0].top_y == -1, "ntre top subtraction wraps16 bits")
		var queued_before_render: Array = queue.rows()
		var rendered: Dictionary = queue.make_view(palette, scene.clip_bottom)
		if scene.name == "top-skip-word-wrap":
			check(rendered.get("error", "").contains("top-skip WORD wrap"), "original top-skip overflow explicitly rejected before GPU allocation")
			check(queue.rows() == queued_before_render, "unsupported original clip retains the source queue")
			var wrapped: PackedByteArray = FileAccess.get_file_as_bytes(args[0].get_base_dir().path_join(scene.path))
			check(wrapped.size() == 64000 and wrapped[0] == 21 and wrapped[319] == 21 and wrapped[320] == 7 and rows[0].frame.indices[129 * 512] == 149, "original oracle confirms WORD skip uses row1 instead of GPU row129")
			cases.append({"name": scene.name, "diagnosed": true, "original_indices_sha256": Schema.digest(wrapped)})
			continue
		if scene.name in ["x-run-word-wrap", "offscreen"]:
			check(rendered.get("error", "").contains("horizontal run WORD wrap"), "original horizontal overflow explicitly rejected before GPU allocation")
			check(queue.rows() == queued_before_render, "unsupported original horizontal wrap retains the source queue")
			var wrapped: PackedByteArray = FileAccess.get_file_as_bytes(args[0].get_base_dir().path_join(scene.path))
			if scene.name == "x-run-word-wrap":
				check(wrapped.size() == 64000 and wrapped[0] == 22 and wrapped[6] == 22 and wrapped[7] == 7, "original oracle confirms offscreen skip can wrap a literal to left edge")
			else:
				var blank = PackedByteArray(); blank.resize(64000); blank.fill(7)
				check(wrapped == blank, "horizontal wrap gate conservatively diagnoses even a fully offscreen terminal literal")
			cases.append({"name": scene.name, "diagnosed": true, "original_indices_sha256": Schema.digest(wrapped)})
			continue
		check(not rendered.has("error"), "depth GPU candidate prepared: " + scene.name)
		if rendered.has("error"): finish(); return
		viewport.add_child(rendered.value)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[0].get_base_dir().path_join(scene.path))
		check(bytes.size() == 64000, "original guarded target has expected length: " + scene.name)
		var expected: PackedByteArray = rgba_indices(bytes, palette)
		label.text = "原版深度队列对照 · %s · 合成精灵，场景逻辑未运行" % scene.name
		await process_frame; await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
		var actual: PackedByteArray = image.get_data(); var same: bool = actual == expected
		check(same, "actual GPU equals original IPNA/ntre: " + scene.name)
		cases.append({"name": scene.name, "equal": same, "submission_order": rendered.submission_order,
			"original_indices_sha256": Schema.digest(bytes), "expected_rgba_sha256": Schema.digest(expected), "actual_rgba_sha256": Schema.digest(actual)})
		if not same or scene.name == "literal-zero-255":
			image.save_png(output.path_join(scene.name + "-actual.png"))
			Image.create_from_data(320, 200, false, Image.FORMAT_RGBA8, expected).save_png(output.path_join(scene.name + "-expected.png"))
		if scene.name == "literal-zero-255": root.get_texture().get_image().save_png(output.path_join("depth-window.png"))
		rendered.value.queue_free(); await process_frame
	_boundaries(queue, palette)
	complete = true; finish()

func _boundaries(queue, palette: PackedByteArray) -> void:
	var frame: Dictionary = Indexed.rle("0100010001ff".hex_decode()).value
	var row: Dictionary = {"x": 0, "sort_y": 1, "layer_offset": 0, "frame": frame, "source": {"label": "retained"}}
	check(queue.load_rows([row]), "single source row accepted")
	row.frame.indices[0] = 0; row.source.label = "changed"
	check(queue.rows()[0].frame.indices[0] == 255 and queue.rows()[0].source.label == "retained", "caller mutations cannot change queued frame or identity")
	var detached: Array = queue.draw_order(); detached[0].frame.indices[0] = 0
	check(queue.rows()[0].frame.indices[0] == 255, "draw-order results are detached")
	var retained: Array = queue.rows()
	for field in ["x", "sort_y", "layer_offset"]:
		var invalid: Dictionary = retained[0].duplicate(true); invalid[field] = 32768
		check(not queue.load_rows([invalid]) and queue.rows() == retained, "invalid signed field preserves previous queue: " + field)
	var damaged: Dictionary = retained[0].duplicate(true); damaged.frame.coverage = PackedByteArray()
	check(not queue.load_rows([damaged]) and queue.rows() == retained, "truncated plane preserves previous queue")
	check(queue.make_view(palette, -1).has("error") and queue.make_view(palette, 201).has("error") and queue.make_view(palette.slice(0, 2), 200).has("error"), "explicit clip and palette validation")
	var large: Array = []; large.resize(256); large.fill(retained[0])
	check(not queue.load_rows(large) and queue.rows() == retained, "original256-row division trap becomes an explicit failure")
	large.resize(255); check(queue.load_rows(large) and queue.draw_order().size() == 255, "largest safe original depth count")
	check(queue.load_rows([]) and queue.rows().is_empty(), "explicit clear does not replay stale rows")
	var geometry: Dictionary = {"width": 45, "height": 31}
	var party: Dictionary = Queue.row_for_sprite("party", 160, 112, 0, geometry, {"frame": 0})
	var event: Dictionary = Queue.row_for_sprite("event", 160, 112, 0, geometry, {"frame": 0})
	check(party.value.x == 138 and party.value.sort_y == 122 and party.value.layer_offset == 6 and Queue.signed16(party.value.sort_y - party.value.layer_offset - 31) == 85, "T163 party anchor uses width/2 and height-4")
	check(event.value.x == 138 and event.value.sort_y == 121 and event.value.layer_offset == 2 and Queue.signed16(event.value.sort_y - event.value.layer_offset - 31) == 88, "T163 event anchor remains independent of party")
	check(Queue.row_for_sprite("party", 0, -32768, -5, geometry, {}).has("error"), "T163 rejects overflowing intermediate even if final sortY would fit")
	check(Queue.row_for_sprite("event", -32768, 0, 0, geometry, {}).has("error") and Queue.row_for_sprite("party", 0, 0, 32767, geometry, {}).has("error"), "T163 x and layer arithmetic is checked")
	check(Queue.row_for_sprite("unknown", 0, 0, 0, geometry, {}).has("error"), "unknown source kind never guesses an anchor")
	var tall: Dictionary = {"width": 1, "height": 201, "indices": PackedByteArray(), "coverage": PackedByteArray()}
	tall.indices.resize(201); tall.coverage.resize(201)
	check(queue.load_rows([{"x": 0, "sort_y": -32568, "layer_offset": 0, "frame": tall}]) and queue.make_view(palette, 200).get("error", "").contains("bottom-clip signed WORD wrap"), "unsafe original signed bottom overflow diagnosed without invoking DLL")
	var boundary: Dictionary = {"width": 255, "height": 258, "indices": PackedByteArray(), "coverage": PackedByteArray()}
	boundary.indices.resize(255 * 258); boundary.coverage.resize(255 * 258)
	check(queue.load_rows([{"x": 0, "sort_y": 1, "layer_offset": 0, "frame": boundary}]), "top-skip65535 input accepted")
	var maximum_skip: Dictionary = queue.make_view(palette, 200)
	check(not maximum_skip.has("error"), "unsigned top-skip65535 remains supported")
	if maximum_skip.has("value"): maximum_skip.value.free()

func rgba_indices(bytes: PackedByteArray, palette: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray(); result.resize(bytes.size() * 4)
	for index in range(bytes.size()):
		for channel in range(3): result[index * 4 + channel] = palette[bytes[index] * 3 + channel] * 4
		result[index * 4 + 3] = 255
	return result

func finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0 and complete, "failed": failed, "complete": complete, "checks": checks, "cases": cases,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"original_gameplay": false, "synthetic_sprites": true, "map_occlusion_marks": false}, "\t")); file.close()
	print("Original depth queue: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 and complete else 1)
