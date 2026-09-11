# SPDX-License-Identifier: MIT
extends SceneTree
const Layer = preload("res://src/native_pal98_text_layer.gd")
const Execute = preload("res://src/native_pal98_text_execution.gd")
const Package = preload("res://src/native_package.gd")
const FontSource = preload("res://src/native_ui_font.gd")
const Schema = preload("res://src/native_schema.gd")
const Reader = preload("res://src/native_json.gd")
const PALETTE_SHA = "5adc8f7f2d2247bc56e6af641adada7967e13699515eb2f628368ac2944ba306"
var checks: Array = []
var failed: int = 0
var output: String
var font: Font
var surfaces: Array = []
var probes: Array = []

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)

func read(path: String):
	var parser = Reader.new(); var value = parser.decode(FileAccess.get_file_as_bytes(path))
	assert(parser.error.is_empty()); return value

func _initialize() -> void: _run.call_deferred()

func _surface(palette: PackedColorArray) -> Dictionary:
	var viewport = SubViewport.new(); viewport.size = Vector2i(320,200)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var layer = Layer.new(); viewport.add_child(layer)
	check(layer.configure(font,palette),"explicit font and 256-colour target configured")
	var result: Dictionary = {"viewport":viewport,"layer":layer}; surfaces.append(result); return result

func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func _image(surface: Dictionary) -> Image:
	var image: Image = surface.viewport.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8); return image

func _request(bytes: PackedByteArray, overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"kind":"draw_glyph","x":12,"y":20,"palette_word":79,"shadow_word":0,"nul_terminated_bytes":bytes}
	result.merge(overrides,true); return result

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4 or DirAccess.dir_exists_absolute(args[3]): push_error("Expected GUI report, execution report, explicit palette MKF and fresh output"); quit(2); return
	output = args[3]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1040,720); root.title = "PAL Wanxiang | original text drawing probe"
	font = FontSource.create()
	var gui = read(args[0]); var execution = read(args[1])
	check(execution.success and execution.request_kernel_only,"source-bound execution evidence admitted")
	var palette_bytes = FileAccess.get_file_as_bytes(args[2])
	check(palette_bytes.size() == 776 and Schema.digest(palette_bytes) == PALETTE_SHA,"explicit prior PAT0/day RGB6 palette is unchanged; cold start not inferred")
	if failed != 0: quit(1); return
	var palette: PackedColorArray = PackedColorArray()
	for index in range(256):
		palette.append(Color8(palette_bytes[8 + index * 3] * 4,palette_bytes[9 + index * 3] * 4,palette_bytes[10 + index * 3] * 4))
	var synthetic = _surface(palette); var plain = _surface(palette)
	var glyph: Dictionary = _request(PackedByteArray([0xd6,0xd0,0]))
	var queued = synthetic.layer.append_draw(glyph,"gbk",{"byte_offset":100})
	check(queued.get("queued",false) and not synthetic.layer.commands_submitted(queued.receipt.serial),"accepted glyph is queued, not acknowledged as displayed")
	var no_shadow = glyph.duplicate(true); no_shadow.shadow_word = -1
	check(plain.layer.append_draw(no_shadow,"gbk").get("queued",false),"nonzero signed shadow flag suppresses shadow")
	await _frame()
	check(synthetic.layer.commands_submitted(queued.receipt.serial),"draw commands submitted before host acknowledgement")
	var shaded_image = _image(synthetic); var plain_image = _image(plain)
	check(not shaded_image.is_invisible() and not plain_image.is_invisible(),"decoded Chinese produces actual GPU ink with existing UI font")
	check(shaded_image.get_data() != plain_image.get_data(),"zero shadow flag produces additional visible ink")
	plain.layer.clear_text()
	var high_colour = glyph.duplicate(true); high_colour.palette_word = 0x14f
	check(plain.layer.append_draw(high_colour,"gbk").receipt.foreground_index == 79,"palette parameter uses its low byte")
	await _frame(); check(shaded_image.get_data() == _image(plain).get_data(),"high-byte colour bits do not change displayed pixels")
	plain.layer.clear_text()
	check(plain.layer.append_draw(_request(PackedByteArray([0xa4,0xa4,0])),"big5").receipt.text == "中","explicit Big5 draw decodes the same character")
	await _frame(); check(shaded_image.get_data() == _image(plain).get_data(),"GBK and Big5 source bytes for the same character produce identical candidate ink")
	var before: Array = synthetic.layer.snapshot()
	for bad in [_request(PackedByteArray([0x81,0,0])),_request(PackedByteArray([65])),_request(PackedByteArray([65,0]),{"x":-1}),_request(PackedByteArray([65,0]),{"palette_word":-1}),_request(PackedByteArray([9,0]))]:
		check(synthetic.layer.append_draw(bad,"gbk",{"byte_offset":100}).has("error") and synthetic.layer.snapshot() == before,"unsupported draw preserves prior display: " + bad.nul_terminated_bytes.hex_encode())
	var truncated = synthetic.layer.append_draw(_request(PackedByteArray([0x81,0,0])),"gbk",{"byte_offset":100})
	check(truncated.diagnostic.code == "truncated_text_sequence" and truncated.diagnostic.error_byte_offset == 100,"lone source lead is located without guessing GDI replacement ink")
	var interior = synthetic.layer.append_draw(_request(PackedByteArray([0x81,0,0]),{"byte_offset":109}),"gbk",{"byte_offset":100,"size_bytes":30})
	check(interior.diagnostic.byte_offset == 100 and interior.diagnostic.size_bytes == 30 and interior.diagnostic.error_byte_offset == 109,"glyph failure keeps full message receipt and separate exact draw offset")
	plain.layer.clear_text()
	check(plain.layer.append_draw(_request(PackedByteArray([0,0x81,0])),"gbk").receipt.bytes_before_nul == 0,"first NUL terminates the drawing input before trailing invalid bytes")
	await _frame(); check(_image(plain).is_invisible(),"NUL-only draw has no ink")
	plain.layer.clear_text()
	check(plain.layer.append_draw(_request(PackedByteArray([0xd6,0xd0,0]),{"x":316,"y":195}),"gbk").receipt.clip_height == 5,"default target clipping has explicit bottom height")
	await _frame(); var clipped = _image(plain).get_used_rect()
	check(clipped == Rect2i() or (clipped.position.x >= 316 and clipped.position.y >= 195 and clipped.end.x <= 320 and clipped.end.y <= 200),"edge drawing stays inside its original target region")
	var package = Package.new(); check(package.load_package(gui.package),"ordinary source package loads for actual text drawing")
	if package.pal98_sources == null: quit(1); return
	var records = package.pal98_sources.open_records()
	check(records.metadata().fingerprint == gui.fingerprint,"display source identity matches ordinary package")
	var bodies: Array = execution.reference.bodies
	for body in bodies:
		var surface = _surface(palette)
		var result: Dictionary = Execute.begin_instruction(records,int(body.entry_index),body.context)
		var draws: int = 0; var ticks: int = 0
		for budget in range(4096):
			if result.has("error") or result.request.kind == "return": break
			match result.request.kind:
				"draw_glyph":
					var accepted: Dictionary = surface.layer.append_draw(result.request,records.metadata().text_encoding,result.source)
					if accepted.has("error"): result = accepted; break
					await _frame()
					if not surface.layer.commands_submitted(accepted.receipt.serial): result = {"error":"draw not submitted"}; break
					draws += 1; result = Execute.step(records,result.state,{"kind":"drawn"})
				"wait": ticks += 1; result = Execute.step(records,result.state,{"kind":"tick"})
				_: result = Execute.step(records,result.state,{"kind":"input","action":0})
		check(not result.has("error") and result.request.kind == "return" and draws == body.events.drawn and ticks == body.events.tick,"actual source glyph drawing completes explicit body request trace: PC" + str(body.entry_index))
		await _capture(surface,"body-pc" + str(body.entry_index),{"pc":body.entry_index,"source":body.source,"draws":draws,"ticks":ticks})
	var title = _surface(palette); var message: Dictionary = records.message_bytes(1)
	var bytes: PackedByteArray = message.value.bytes.duplicate(); bytes.append(0)
	var title_draw: Dictionary = title.layer.append_draw(_request(bytes,{"kind":"draw_string","x":12,"y":108,"palette_word":140}),"gbk",message.source)
	check(title_draw.get("queued",false) and title_draw.receipt.bytes_before_nul == 7,"opening title uses full raw string at (12,108), palette140")
	await _capture(title,"title-message1",{"source":message.source,"caller_dispatch_executed":false})
	# Display separate source probes. This is not an assembled opening or a game.
	var caption = Label.new(); caption.text = "Source text probes | explicit PAT0/day | existing system font | gameplay not running"
	caption.add_theme_font_override("font",font); caption.position = Vector2(16,8); root.add_child(caption)
	for index in range(5):
		var display = TextureRect.new(); display.texture = surfaces[index + 2].viewport.get_texture()
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		display.position = Vector2(12 + (index % 3) * 344,60 + (index / 3) * 300); display.size = Vector2(320,200); root.add_child(display)
		var label = Label.new(); label.text = probes[index].label; label.position = display.position - Vector2(0,24); root.add_child(label)
	await _frame(); root.get_texture().get_image().save_png(output.path_join("text-probe-window.png"))
	var file = FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failed == 0,"failed":failed,"checks":checks,"probes":probes,
		"font_names":FontSource.NAMES,"font_family":font.get_font_name(),"font_size":16,
		"engine":Engine.get_version_info(),"os":OS.get_name(),"display_server":DisplayServer.get_name(),
		"adapter":RenderingServer.get_video_adapter_name(),"rendering_method":RenderingServer.get_current_rendering_method(),
		"palette_sha256":PALETTE_SHA,"palette_choice":"explicit PAT0/day; original cold start unknown",
		"source_fingerprint":gui.fingerprint,"package_sha256":FileAccess.get_sha256(gui.package),
		"execution_report_sha256":FileAccess.get_sha256(args[1]),"renderer_executed":true,
		"real_clock_or_input":false,"original_gameplay":false,"original_gdi_pixel_parity":false,"human_acceptance":false},"\t")); file.close()
	print("PAL98 text drawing: ",checks.size()," checks; ",failed," failed")
	quit(0 if failed == 0 else 1)

func _capture(surface: Dictionary, label: String, detail: Dictionary) -> void:
	await _frame(); var image = _image(surface)
	check(not image.is_invisible(),"source text has visible candidate ink: " + label)
	var path: String = output.path_join(label + ".png"); image.save_png(path)
	detail.merge({"label":label,"path":path,"rgba_sha256":Schema.digest(image.get_data()),"png_sha256":FileAccess.get_sha256(path),
		"runs":surface.layer.snapshot(),"used_rect":str(image.get_used_rect())})
	probes.append(detail)
