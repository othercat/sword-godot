# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
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
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not oracle.get("source_unchanged", false) or oracle.get("rows", []).size() != 20: quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(120).timeout.connect(func(): check(false, "map background watchdog expired"); finish())
	root.size = Vector2i(1040, 720); root.title = "PAL Wanxiang | original map background comparison"
	var package = Package.new()
	check(package.load_package(args[0]), "ordinary author package admission: " + package.error)
	if package.pal98_graphics == null: finish(); return
	var records = package.pal98_graphics.open_records()
	check(records.metadata().files["MAP.MKF"].sha256 == oracle.map_sha256 and records.metadata().files["GOP.MKF"].sha256 == oracle.gop_sha256, "original oracle identifies exact admitted MAP/GOP")
	var palette: PackedByteArray = records.palette(0, 0).value
	var viewport = SubViewport.new(); viewport.size = Vector2i(320, 200)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	# Oracle initializes every target pixel to source index0. This is an explicit
	# test input, not inferred original cold-start framebuffer/palette state.
	var underlay = ColorRect.new(); underlay.size = Vector2(320, 200)
	underlay.color = Color8(palette[0] * 4, palette[1] * 4, palette[2] * 4); underlay.z_index = -3
	viewport.add_child(underlay)
	var display = TextureRect.new(); display.texture = viewport.get_texture()
	display.position = Vector2(40, 60); display.size = Vector2(960, 600)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; root.add_child(display)
	var label = Label.new(); label.position = Vector2(40, 20); root.add_child(label)
	var background = Background.new()
	check(background.make_view(0, 0, 0).has("error"), "unloaded background fails")
	check(Background.descriptor(65535, false).frame == 511 and Background.descriptor(65535, true).frame == 510 and Background.descriptor(65535, true).height == 15, "separate descriptor frame/height bits")
	check(Background.descriptor(0, false).present and not Background.descriptor(0x2f00, true).present and Background.descriptor(0x2000, false).blocked, "lower zero always drawn; upper presence ignores height/block flags")
	var index: int = 0
	for row in oracle.rows:
		var loaded: bool = background.load_source(records, row.map_index, 0, 0)
		check(loaded, "explicit map/palette loaded: %d" % row.map_index)
		if not loaded: break
		var original_source: Dictionary = background.source()
		check(not background.load_source(records, row.map_index, 0, 2) and background.source() == original_source, "failed palette selection preserves prior background inputs")
		var result: Dictionary = background.make_view(row.map_x, row.map_y, row.half)
		check(not result.has("error"), "background view builds: " + str(row.path) + " " + str(result.get("error", "")))
		if result.has("error"): break
		var node = result.value; viewport.add_child(node)
		check(node is TileMapLayer and node.y_sort_enabled and not node.x_draw_order_reversed and node.get_used_cells().size() == (13 + int(row.half)) * 22, "TileMap cell and draw-order policy")
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(args[1].get_base_dir().path_join(row.path))
		check(bytes.size() == 64000 and Schema.digest(bytes) == row.sha256 and row.initial_index == 0, "fixed original vmap oracle bytes: " + str(row.path))
		var expected: PackedByteArray = rgba_indices(bytes, palette)
		label.text = "原版背景资源对照 · MAP %d · 坐标 %d,%d/%d · 场景逻辑尚未运行" % [row.map_index, row.map_x, row.map_y, row.half]
		await process_frame; await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
		var actual: PackedByteArray = image.get_data()
		var same: bool = actual == expected
		check(same, "TileMap GPU equals original vmap: " + str(row.path))
		cases.append({"map_index": row.map_index, "map_x": row.map_x, "map_y": row.map_y, "half": row.half,
			"source": result.source, "cells": result.cells, "pairs": result.pairs, "equal": same,
			"expected_rgba_sha256": Schema.digest(expected), "actual_rgba_sha256": Schema.digest(actual)})
		if not same or index in [0, 15, 17]:
			image.save_png(output.path_join("case-%02d-actual.png" % index))
			Image.create_from_data(320, 200, false, Image.FORMAT_RGBA8, expected).save_png(output.path_join("case-%02d-expected.png" % index))
		if index == 17: root.get_texture().get_image().save_png(output.path_join("map-background-window.png"))
		node.queue_free(); await process_frame
		index += 1
	check(index == oracle.rows.size(), "all original background views completed")
	check(background.draw_plan(-32769, 0, 0).has("error") and background.draw_plan(0, 32768, 0).has("error") and background.draw_plan(0, 0, 2).has("error"), "explicit vmap input bounds")
	var wrapped: Dictionary = background.draw_plan(63, 127, 1)
	check(wrapped.value[2].offset == 8 and wrapped.value[0].offset == 65528, "linear16-bit MAP address wrap preserves cross-row carry")
	complete = true
	finish()

func rgba_indices(bytes: PackedByteArray, palette: PackedByteArray) -> PackedByteArray:
	var result = PackedByteArray(); result.resize(bytes.size() * 4)
	for index in range(bytes.size()):
		var colour: int = bytes[index] * 3
		for channel in range(3): result[index * 4 + channel] = palette[colour + channel] * 4
		result[index * 4 + 3] = 255
	return result

func finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0 and complete, "checks": checks, "failed": failed, "complete": complete, "cases": cases,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name(),
		"original_gameplay": false, "depth_occlusion": false, "cold_start_palette": false}, "\t")); file.close()
	print("Original map backgrounds: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 and complete else 1)
