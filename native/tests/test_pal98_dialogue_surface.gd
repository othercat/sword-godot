# SPDX-License-Identifier: MIT
extends SceneTree
const Surface = preload("res://src/native_pal98_dialogue_surface.gd")
const Caller = preload("res://src/native_pal98_dialogue_caller.gd")
const Package = preload("res://src/native_package.gd")
const FontSource = preload("res://src/native_ui_font.gd")
const Schema = preload("res://src/native_schema.gd")
const Reader = preload("res://src/native_json.gd")
const PALETTE_SHA = "5adc8f7f2d2247bc56e6af641adada7967e13699515eb2f628368ac2944ba306"
var checks: Array = []
var failed: int = 0
var output: String
var snapshots: Array = []
var draws: Array = []
var effects: Array = []
var matched_boundaries: int = 0
signal pending_finished
signal pending_started
var pending_reply: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)

func _read(path: String):
	var parser = Reader.new(); var result = parser.decode(FileAccess.get_file_as_bytes(path))
	assert(parser.error.is_empty()); return result

func _initialize() -> void: _run.call_deferred()

func _frame() -> void:
	await process_frame; await RenderingServer.frame_post_draw

func _pixels(surface) -> Image:
	var result: Image = surface.get_texture().get_image(); result.convert(Image.FORMAT_RGBA8); return result

func _digest(surface) -> String: return Schema.digest(_pixels(surface).get_data())

func _request(text: String, x: int = 8) -> Dictionary:
	var bytes: PackedByteArray = text.to_ascii_buffer(); bytes.append(0)
	return {"kind":"draw_string","x":x,"y":12,"palette_word":79,"shadow_word":0,"nul_terminated_bytes":bytes}

func _normal(result: Dictionary) -> Dictionary:
	var request: Dictionary = result.request.duplicate(true)
	if request.has("nul_terminated_bytes"):
		request.nul_terminated_bytes_hex = request.nul_terminated_bytes.hex_encode(); request.erase("nul_terminated_bytes")
	return {"state":result.state.duplicate(true),"request":request}

func _drive(surface, records, result: Dictionary, expected: Array) -> Dictionary:
	var boundary: int = 0
	for budget in range(8192):
		if result.has("error"): return result
		if boundary >= expected.size() or _normal(result) != expected[boundary]: return {"error":"caller renderer trace differs at boundary " + str(boundary)}
		boundary += 1; matched_boundaries += 1
		if result.request.kind == "return":
			if boundary != expected.size(): return {"error":"caller renderer trace ended early"}
			return result
		var event: Dictionary
		if result.request.kind == "wait": event = {"kind":"tick"}
		elif result.request.kind == "poll_input": event = {"kind":"input","action":0}
		else:
			var applied: Dictionary = await surface.apply_request(result.request,records.metadata().text_encoding,result.source)
			if applied.has("error"): return applied
			event = applied.event
			applied.receipt.instruction_source = result.instruction_source.duplicate(true)
			applied.receipt.instruction_words = result.instruction_words.duplicate(true)
			if event.kind == "drawn": draws.append(applied.receipt)
			else: effects.append(applied.receipt)
		result = Caller.step(records,result.state,event)
	return {"error":"caller renderer probe budget exceeded"}

func _capture(surface, label: String) -> String:
	await _frame(); var pixels: Image = _pixels(surface); var path: String = output.path_join(label + ".png")
	pixels.save_png(path); var digest: String = Schema.digest(pixels.get_data())
	snapshots.append({"label":label,"path":path,"rgba_sha256":digest,"png_sha256":FileAccess.get_sha256(path),"text_runs":surface.text_snapshot()})
	return digest

func _pending_capture(surface) -> void:
	pending_started.emit()
	pending_reply = await surface.apply_request({"kind":"capture_background"},"gbk")
	pending_finished.emit()

func _pending_scene(surface, background: Image) -> void:
	pending_started.emit()
	pending_reply = await surface.replace_scene_frame(background)
	pending_finished.emit()

func _asynchronous_rejections(surface, background: Image) -> void:
	var saved: String = surface.captured_sha256()
	surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rejected: Dictionary = await surface.apply_request({"kind":"capture_background"},"gbk")
	check(rejected.has("error") and rejected.diagnostic.code == "dialogue_surface_target_changed" and surface.captured_sha256() == saved,"disabled target cannot acknowledge a stale capture")
	rejected = await surface.replace_scene_frame(background)
	check(rejected.has("error") and rejected.diagnostic.code == "dialogue_surface_target_changed","disabled target cannot acknowledge scene replacement")
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_pending_capture.call_deferred(surface)
	await pending_started
	await process_frame
	rejected = await surface.apply_request({"kind":"capture_background"},"gbk")
	check(rejected.has("error") and rejected.diagnostic.code == "dialogue_surface_request_pending","concurrent request is rejected during an actual pending render")
	root.remove_child(surface)
	await pending_finished
	check(pending_reply.has("error") and pending_reply.diagnostic.code == "dialogue_surface_not_ready" and not pending_reply.has("event") and surface.captured_sha256() == saved,"detached target cannot complete a pending capture")
	root.add_child(surface); await _frame()
	_pending_capture.call_deferred(surface)
	await pending_started
	await process_frame; surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await pending_finished
	check(pending_reply.has("error") and pending_reply.diagnostic.code == "dialogue_surface_target_changed" and not pending_reply.has("event"),"capture rechecks update mode after the render barrier")
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS; await _frame()
	_pending_scene.call_deferred(surface,background)
	await pending_started
	await process_frame; surface.size = Vector2i(319,200)
	await pending_finished
	check(pending_reply.has("error") and pending_reply.diagnostic.code == "dialogue_surface_target_changed" and not pending_reply.has("event"),"scene replacement cannot acknowledge a target resized during its wait")
	surface.size = Vector2i(320,200); await _frame()
	var recovered: Dictionary = await surface.replace_scene_frame(background)
	check(not recovered.has("error"),"explicit scene replacement recovers after test invalidation; no implicit rollback claimed")

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4 or DirAccess.dir_exists_absolute(args[3]): push_error("Expected GUI report, caller report, explicit palette and fresh output"); quit(2); return
	output = args[3]; DirAccess.make_dir_recursive_absolute(output)
	create_timer(20.0).timeout.connect(func(): push_error("dialogue surface probe watchdog expired"); quit(3))
	var source_files: Dictionary = {}
	for path in ["src/native_pal98_dialogue_surface.gd","src/native_pal98_dialogue_caller.gd","src/native_pal98_text_execution.gd",
		"src/native_pal98_text_layer.gd","src/native_pal98_text_codec.gd","src/native_ui_font.gd","tests/test_pal98_dialogue_surface.gd"]:
		source_files[path] = FileAccess.get_sha256("res://" + path)
	root.size = Vector2i(992,672); root.title = "PAL Wanxiang | dialogue target rendering probe"
	var gui = _read(args[0]); var caller = _read(args[1]); var palette_bytes = FileAccess.get_file_as_bytes(args[2])
	check(caller.success and caller.host_side_effects_acknowledged_only,"source caller reference admitted")
	check(palette_bytes.size() == 776 and Schema.digest(palette_bytes) == PALETTE_SHA,"explicit PAT0/day palette remains unchanged")
	if failed != 0: quit(1); return
	var palette: PackedColorArray = PackedColorArray()
	for index in range(256): palette.append(Color8(palette_bytes[8 + index * 3] * 4,palette_bytes[9 + index * 3] * 4,palette_bytes[10 + index * 3] * 4))
	# A deliberately synthetic opaque target proves copying independently of
	# unclosed original scene/frame/palette cold-start facts. It is not game art.
	var initial = Image.create(320,200,false,Image.FORMAT_RGBA8)
	for y in range(200):
		for x in range(320): initial.set_pixel(x,y,Color8(12 + (x / 16) % 2 * 8,16 + (y / 16) % 2 * 8,32))
	var surface = Surface.new(); root.add_child(surface)
	check(surface.configure(FontSource.create(),palette,initial),"explicit opaque target and existing font configured")
	var display = TextureRect.new(); display.texture = surface.get_texture(); display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.position = Vector2(16,48); display.size = Vector2(960,600); root.add_child(display)
	var caption = Label.new(); caption.text = "Actual text/capture/restore | synthetic background | explicit ticks/input | not a game run"
	caption.position = Vector2(16,16); root.add_child(caption)
	await _frame(); var baseline: String = _digest(surface)
	var reply: Dictionary = await surface.apply_request({"kind":"restore_background"},"gbk")
	check(reply.has("error") and reply.diagnostic.code == "dialogue_background_not_captured" and _digest(surface) == baseline,"restore without snapshot rejects without changing target")
	reply = await surface.apply_request({"kind":"capture_background"},"gbk")
	check(reply.event.kind == "captured" and reply.receipt.rgba_sha256 == baseline,"capture acknowledges actual rendered target bytes")
	reply = await surface.apply_request(_request("A"),"gbk")
	check(reply.event.kind == "drawn" and reply.receipt.text.text == "A" and _digest(surface) != baseline,"text acknowledgement follows actual displayed ink")
	var first: String = _digest(surface)
	reply = await surface.apply_request({"kind":"capture_background"},"gbk")
	check(reply.receipt.rgba_sha256 == first,"later capture includes existing text")
	reply = await surface.apply_request(_request("B",28),"gbk")
	check(_digest(surface) != first,"subsequent draw changes target without overwriting saved snapshot")
	reply = await surface.apply_request({"kind":"restore_background"},"gbk")
	check(reply.event.kind == "restored" and _digest(surface) == first and surface.text_snapshot().is_empty(),"restore reproduces captured pixels and removes post-capture drawing nodes")
	reply = await surface.replace_scene_frame(initial)
	check(reply.event.kind == "scene_frame_drawn" and _digest(surface) == baseline and surface.captured_sha256() == first,"scene replacement clears old ink but preserves the dialog snapshot")
	var mipmapped: Image = initial.duplicate(); mipmapped.generate_mipmaps()
	var mip_hash: String = Schema.digest(mipmapped.get_data())
	reply = await surface.replace_scene_frame(mipmapped)
	check(not reply.has("error") and _digest(surface) == baseline and mipmapped.has_mipmaps() and Schema.digest(mipmapped.get_data()) == mip_hash,"opaque mipmapped input uses its base image without changing the supplied mip chain")
	reply = await surface.apply_request({"kind":"restore_background"},"gbk")
	check(_digest(surface) == first,"snapshot remains restorable after scene composition")
	var bad_image = Image.create(320,200,false,Image.FORMAT_RGBA8); bad_image.fill(Color(0,0,0,0))
	reply = await surface.replace_scene_frame(bad_image)
	check(reply.has("error") and _digest(surface) == first,"transparent scene candidate is rejected without changing target")
	for kind in ["draw_dialogue_box","draw_dialogue_icon"]:
		reply = await surface.apply_request({"kind":kind},"gbk")
		check(reply.has("error") and reply.diagnostic.code == "dialogue_surface_request_unimplemented" and _digest(surface) == first,"missing UI resource path diagnoses without fake acknowledgement: " + kind)
	var bad_text = _request("A"); bad_text.nul_terminated_bytes = PackedByteArray([0x81,0,0])
	reply = await surface.apply_request(bad_text,"gbk",{"byte_offset":100})
	check(reply.has("error") and reply.diagnostic.error_byte_offset == 100 and _digest(surface) == first,"bad source encoding propagates its byte diagnostic without changing prior display")
	await _asynchronous_rejections(surface,initial)
	reply = await surface.replace_scene_frame(initial)
	var package = Package.new(); check(package.load_package(gui.package),"ordinary source package loads for rendered caller sequence")
	if package.pal98_sources == null: quit(1); return
	var records = package.pal98_sources.open_records(); var context: Dictionary = caller.reference.initial_context.duplicate(true)
	var title_sha: String = ""
	var source_rows: Array = []
	for probe in caller.reference.messages:
		var pc: int = int(probe.pc)
		if pc == 13:
			var refresh: Dictionary = records.instruction(11)
			check(refresh.value.words == [5,0,0,0] and context.capture_gate == 0 and Caller.begin_clear(records,context).request.kind == "return","explicit PC11 host effect matches source words and no-wait clear branch")
			reply = await surface.replace_scene_frame(initial,refresh.source); effects.append(reply.receipt)
			check(_digest(surface) == baseline,"PC11 explicit scene replacement removes first message pixels")
			context.merge({"mode":2,"title_x":12,"title_y":108,"origin_x":44,"origin_y":126},true)
		if pc == 16:
			var restore: Dictionary = records.instruction(15); check(restore.value.words == [0x8e,0,0,0],"explicit PC15 host restore is bound to original instruction words")
			reply = await surface.apply_request({"kind":"restore_background"},"gbk",restore.source); effects.append(reply.receipt)
			check(reply.event.kind == "restored" and _digest(surface) == title_sha,"PC15 actually restores the captured title and removes the preceding body")
			context.capture_gate = 0; context.restore_gate = 0
		var result: Dictionary = await _drive(surface,records,Caller.begin_instruction(records,pc,context),probe.trace)
		check(not result.has("error"),"actual drawing/background acknowledgements preserve caller trace: PC" + str(pc))
		if result.has("error"): push_error(result.error); break
		context = result.state.context.duplicate(true)
		var digest: String = await _capture(surface,"message-pc" + str(pc))
		if pc == 13: title_sha = digest
		source_rows.append({"pc":pc,"source":result.source,"instruction_source":result.instruction_source,"instruction_words":result.instruction_words,"context":context.duplicate(true)})
	check(source_rows.size() == 5 and draws.size() == 45,"five source messages produce 44 body glyphs and one whole title")
	check(source_rows.map(func(row): return row.context.local_y) == [58,126,142,142,158],"rendered sequence retains corrected caller-local Y progression")
	await _frame(); root.get_texture().get_image().save_png(output.path_join("dialogue-target-window.png"))
	check(source_files.keys().all(func(path): return FileAccess.get_sha256("res://" + path) == source_files[path]),"rendered implementation and probe sources remain unchanged during the run")
	var report: Dictionary = {"success":failed == 0,"failed":failed,"checks":checks,"source_messages":source_rows,"snapshots":snapshots,"draws":draws,"effects":effects,
		"source_files":source_files,
		"matched_caller_boundaries":matched_boundaries,"source_fingerprint":gui.fingerprint,"package_sha256":FileAccess.get_sha256(gui.package),
		"caller_report_sha256":FileAccess.get_sha256(args[1]),"palette_sha256":PALETTE_SHA,"initial_background_rgba_sha256":baseline,
		"background_kind":"explicit synthetic opaque target","engine":Engine.get_version_info(),"os":OS.get_name(),"display_server":DisplayServer.get_name(),
		"adapter":RenderingServer.get_video_adapter_name(),"rendering_method":RenderingServer.get_current_rendering_method(),
		"renderer_executed":true,"background_capture_restore_executed":true,"scene_frame_supplied_by_probe":true,"mode_and_pc11_pc15_effects_explicit":true,
		"real_clock_or_input":false,"original_trigger_executed":false,"original_gameplay":false,"original_gdi_pixel_parity":false,"human_acceptance":false}
	var file = FileAccess.open(output.path_join("results.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("PAL98 dialogue surface: ",checks.size()," checks; ",failed," failed"); quit(0 if failed == 0 else 1)
