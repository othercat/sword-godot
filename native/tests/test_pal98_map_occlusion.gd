# SPDX-License-Identifier: MIT
extends SceneTree
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
const Queue = preload("res://src/native_pal98_depth_queue.gd")
const Schema = preload("res://src/native_schema.gd")
var output: String
var checks: Array = []
var cases: Array = []
var failed: int = 0
var complete: bool = false

class FixtureRecords extends RefCounted:
	var map: PackedByteArray
	var gop: PackedByteArray
	func decoded_chunk(_name: String, index: int) -> Dictionary:
		return {"value": map.duplicate(), "source": {"fixture": "synthetic-map", "chunk": index}}
	func group(_name: String, index: int) -> Dictionary:
		return {"value": gop.duplicate(), "source": {"fixture": "synthetic-gop", "chunk": index}}

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
	if reference.get("cases", []).size() != 8 or not reference.get("source_unchanged", false) or not reference.get("guarded_output", false): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(120).timeout.connect(func(): check(false, "map occlusion watchdog expired"); finish())
	var input_root: String = args[0].get_base_dir()
	var coordinates: PackedByteArray = FileAccess.get_file_as_bytes(input_root.path_join("coordinates.i16"))
	check(reference.coordinate_count == 5305 and coordinates.size() == 53050, "original coordinate corpus length")
	var mismatches: Array = []
	for at in range(0, coordinates.size(), 10):
		var x: int = coordinates.decode_s16(at); var y: int = coordinates.decode_s16(at + 2)
		var cell: Dictionary = Occlusion.world_to_cell(x, y).value
		if cell.half != coordinates.decode_s16(at + 4) or cell.x != coordinates.decode_s16(at + 6) or cell.y != coordinates.decode_s16(at + 8): mismatches.append({"x": x, "y": y, "actual": cell})
	check(mismatches.is_empty(), "all5305 exrij original outputs match including diagonal ties, signed input and clamps")
	if not mismatches.is_empty(): cases.append({"coordinate_mismatches": mismatches.slice(0, 10)})
	var fixture = FixtureRecords.new(); fixture.gop = FileAccess.get_file_as_bytes(input_root.path_join(reference.gop))
	fixture.map = FileAccess.get_file_as_bytes(input_root.path_join("marks.map"))
	var occlusion = Occlusion.new()
	check(occlusion.load_source(fixture, 0), "synthetic mark source loaded")
	for request in reference.marks:
		var initial = PackedByteArray(); initial.resize(16384); initial.fill(0x40)
		check(occlusion.replace_marks(initial), "explicit flags accepted")
		var result: Dictionary = occlusion.mark_cells(request.cutoff, [{"x": int(request.x), "y": int(request.y), "half": int(request.half)}])
		var address: int = (int(request.y) * 128 + int(request.x) * 2 + int(request.half)) & 65535
		if address >= 16384:
			check(result.get("flag_offset", -1) == address and result.has("error") and occlusion.marks() == initial, "out-of-owned flags diagnosed atomically: " + str(address))
		else:
			var expected: PackedByteArray = initial.duplicate()
			for change in request.changes: expected[int(change.offset)] = int(change.value)
			check(not result.has("error") and occlusion.marks() == expected, "exbb flags exactly match original including alias, H*16 and signed cutoff: " + str(address))
	_boundaries(occlusion, fixture)
	_alias_frames()
	root.size = Vector2i(1040, 720); root.title = "PAL Wanxiang | original map occlusion comparison"
	var viewport = SubViewport.new(); viewport.size = Vector2i(320, 200); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST; root.add_child(viewport)
	var palette = PackedByteArray(); palette.resize(768)
	for colour in range(256):
		palette[colour * 3] = colour % 64; palette[colour * 3 + 1] = (colour * 7) % 64; palette[colour * 3 + 2] = (colour * 13) % 64
	var underlay = ColorRect.new(); underlay.size = Vector2(320, 200); underlay.z_index = -3
	underlay.color = Color8(palette[21] * 4, palette[22] * 4, palette[23] * 4); viewport.add_child(underlay)
	var display = TextureRect.new(); display.texture = viewport.get_texture(); display.position = Vector2(40, 60); display.size = Vector2(960, 600)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; root.add_child(display)
	var label = Label.new(); label.position = Vector2(40, 20); root.add_child(label)
	for scene in reference.cases:
		fixture.map.resize(65536); fixture.map.fill(0)
		var flags = PackedByteArray(); flags.resize(16384)
		for cell in scene.cells:
			fixture.map.encode_u16(int(cell.at) * 4, int(cell.lower)); fixture.map.encode_u16(int(cell.at) * 4 + 2, int(cell.upper)); flags[int(cell.at)] = int(cell.flags)
		check(occlusion.load_source(fixture, 0) and occlusion.replace_marks(flags), "exmap source snapshot accepted: " + scene.name)
		var rows: Dictionary = occlusion.queue_rows(scene.viewport_x, scene.viewport_y)
		check(not rows.has("error"), "exmap produces addressed rows: " + scene.name)
		if rows.has("error"): finish(); return
		if scene.name == "terminal-not-emitted": check(rows.value.is_empty() and rows.terminal_mark == 3, "last original flag byte is read but not emitted")
		if scene.name == "linear-order": check(rows.value.map(func(row): return row.source.map_byte_offset) == [3104, 3106, 3108, 3112], "exmap source order is row/column/half and lower/upper")
		var queue = Queue.new(); check(queue.load_rows(rows.value), "map rows enter ordinary depth adapter: " + scene.name)
		var rendered: Dictionary = queue.make_view(palette, 200); check(not rendered.has("error"), "map depth GPU candidate: " + scene.name)
		if rendered.has("error"): finish(); return
		viewport.add_child(rendered.value); label.text = "原版地图遮挡图块对照 · %s · 合成资源，非场景执行" % scene.name
		await process_frame; await RenderingServer.frame_post_draw
		var original: PackedByteArray = FileAccess.get_file_as_bytes(input_root.path_join(scene.path))
		var expected = PackedByteArray(); expected.resize(original.size() * 4)
		for pixel in range(original.size()):
			for channel in range(3): expected[pixel * 4 + channel] = palette[original[pixel] * 3 + channel] * 4
			expected[pixel * 4 + 3] = 255
		var image: Image = viewport.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
		var actual: PackedByteArray = image.get_data()
		check(original.size() == 64000 and actual == expected, "GPU map depth equals original exmap/ntre: " + scene.name)
		cases.append({"name": scene.name, "rows": rows.value.size(), "equal": actual == expected, "expected_rgba_sha256": Schema.digest(expected), "actual_rgba_sha256": Schema.digest(actual)})
		if actual != expected or scene.name == "linear-order": image.save_png(output.path_join(scene.name + ".png"))
		if scene.name == "linear-order": root.get_texture().get_image().save_png(output.path_join("map-occlusion-window.png"))
		rendered.value.queue_free(); await process_frame
	complete = true; finish()

func _boundaries(occlusion, fixture) -> void:
	check(Occlusion.world_to_cell(32768, 0).has("error") and Occlusion.world_to_cell(0, -32769).has("error"), "exrij rejects non-I2 input")
	var retained: PackedByteArray = occlusion.marks()
	check(occlusion.mark_cells(0, [{"x": 0, "y": 0, "half": 1.0}]).has("error") and occlusion.marks() == retained, "non-integer half gets a diagnostic and preserves flags")
	check(not occlusion.replace_marks(PackedByteArray()) and occlusion.marks() == retained, "invalid flags preserve old marks")
	var alias: Dictionary = occlusion.mark_cells(0, [{"x": 64, "y": 0, "half": 0}])
	check(not alias.has("error"), "expanded column64 aliases next row instead of clamping")
	retained = occlusion.marks()
	var mixed: Dictionary = occlusion.mark_cells(-32768, [{"x": 1, "y": 0, "half": 0}, {"x": -1, "y": 0, "half": 0}])
	check(mixed.has("error") and occlusion.marks() == retained, "late out-of-owned mark preserves entire prior flag snapshot")
	var skipped: Dictionary = occlusion.mark_sprite(0, 0, 0, 0, 72, 32, 48, 0)
	check(skipped.get("skipped", false) and occlusion.marks() == retained, "layer72 skips only map marks")
	check(occlusion.mark_sprite(0, 0, 0, 0, 0, 32, 48, -1).get("skipped", false), "nonzero original map skip flag respected")
	check(occlusion.mark_sprite(32767, 0, 1, 0, 0, 32, 48, 0).has("error") and occlusion.marks() == retained, "T163 checked world overflow preserves flags")
	var marked: Dictionary = occlusion.mark_sprite(160, 112, 864, 912, 0, 45, 31, 0)
	check(not marked.has("error") and marked.requests == 15 and marked.center == {"x": 32, "y": 64, "half": 0}, "T163 full sprite bbox makes five marks per inclusive cell")
	var source_before: Dictionary = occlusion.source(); retained = occlusion.marks(); fixture.map.resize(4)
	check(not occlusion.load_source(fixture, 1) and occlusion.source() == source_before and occlusion.marks() == retained, "failed source replacement preserves map and marks")
	fixture.map.resize(65536); fixture.map.fill(0); fixture.map.encode_u16(2, 0x0100)
	occlusion.load_source(fixture, 0); var invalid = PackedByteArray(); invalid.resize(16384); invalid[0] = 2; occlusion.replace_marks(invalid)
	check(occlusion.queue_rows(0, 0).get("error", "").contains("GOP directory wrap"), "marked upper index0 never inherits background absence policy")
	occlusion.clear_marks(); check(occlusion.queue_rows(0, 0).value.is_empty(), "explicit clear removes previous rows")

func _alias_frames() -> void:
	var fixture = FixtureRecords.new(); fixture.map.resize(65536); fixture.gop.resize(65536)
	for index in range(4): fixture.gop.encode_u16(index * 2, 4)
	fixture.gop.encode_u16(8, 1); fixture.gop.encode_u16(10, 1); fixture.gop[12] = 1; fixture.gop[13] = 99
	var flags = PackedByteArray(); flags.resize(16384)
	for index in range(3): fixture.map.encode_u16(index * 4, index); flags[index] = 1
	var occlusion = Occlusion.new(); occlusion.load_source(fixture, 0); occlusion.replace_marks(flags)
	var rows: Dictionary = occlusion.queue_rows(0, 0)
	check(not rows.has("error") and rows.value.size() == 3, "aliased GOP frame indices accepted")
	if rows.has("error"): return
	check(rows.value.all(func(row): return not row.frame.has("tail") and row.frame.size() == 4 and row.frame.indices.size() == 1), "depth rows discard large decoder tails rather than multiplying unbudgeted bytes")
	rows.value[0].frame.indices[0] = 1
	check(rows.value[1].frame.indices[0] == 99 and occlusion.queue_rows(0, 0).value[0].frame.indices[0] == 99, "aliased frame planes remain detached")

func finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": complete and failed == 0, "complete": complete, "failed": failed, "checks": checks, "cases": cases,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "original_gameplay": false, "synthetic_resources": true}, "\t")); file.close()
	print("Original map occlusion: ", checks.size(), " checks, ", failed, " failed"); quit(0 if complete and failed == 0 else 1)
