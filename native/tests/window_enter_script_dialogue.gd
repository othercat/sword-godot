# SPDX-License-Identifier: MIT
extends SceneTree
## Windowed, chain-driven dialogue frame: the real opening entry script composes
## its first FFFF message through the reviewed dialogue caller, the raw source
## message bytes go through the admitted codec, and the real dialogue surface
## draws them on the captured target.
##
## The background is an explicit probe frame (chain-driven camera, flat palette
## fill), the font is the Native system-font candidate and no original GDI pixel
## parity is claimed. No input device, audio, save or original process is used.
const Enter = preload("res://src/native_pal98_enter_script.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const DialogueHost = preload("res://src/native_pal98_dialogue_host.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
const Package = preload("res://src/native_package.gd")
const Surface = preload("res://src/native_pal98_dialogue_surface.gd")
const UiFont = preload("res://src/native_ui_font.gd")

class DisplayDouble:
	func answer(_request: Dictionary) -> Dictionary:
		return {"completed": true}

var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _context() -> Dictionary:
	return {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44, "origin_y": 26, "mode": 1,
		"line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202, "icon": 2, "skip_word": 0, "delay_units": 1,
		"input_action": 99, "capture_gate": 1, "restore_gate": 0, "colours": [79, 45, 26, 141], "timer_counter": 0}

func _fixture(source) -> Dictionary:
	var storage = Events.new(); storage.load_source(source)
	var equipment = Equipment.new()
	equipment.read_tables(source.copy_chunk("data", 3), source.copy_chunk("sss", 2), source.copy_chunk("sss", 4))
	var inventory = PackedByteArray(); inventory.resize(1536)
	return {"globals": {"current_scene": 1, "requested_scene": 1, "party_x": 160, "party_y": 112,
			"viewport_x": 0, "viewport_y": 0, "resource_flags": 0, "direction_word": 0, "loaded_map_id": 0,
			"member_last": 0, "follower_count": 0, "battle_mode": 0, "midi_track": 0, "battle_music_track": 0,
			"day_night_word": 0, "fade_gate_word": 0},
		"events": storage.source_state(), "dialogue": _context(), "rng": Random.create(0x12345),
		"equipment": equipment.initial_state([0]), "inventory_bytes": inventory,
		"party_records": [{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 0}],
		"party_trail": [{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}, {"x": 0, "y": 0, "direction_word": 0},
			{"x": 0, "y": 0, "direction_word": 0}]}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3: quit(2); return
	create_timer(240).timeout.connect(func(): check(false, "dialogue window probe watchdog"); finish(args))
	var package = Package.new()
	if not package.load_package(args[0]):
		push_error("package rejected: " + str(package.error)); quit(2); return
	if package.pal98_sources == null or package.pal98_graphics == null:
		push_error("sources and graphics required"); quit(2); return
	var palette: PackedByteArray = package.pal98_graphics.open_records().palette(0, 0).value
	var surface = Surface.new()
	get_root().add_child(surface)
	await process_frame
	var background := Image.create(320, 200, false, Image.FORMAT_RGBA8)
	background.fill(Color8(palette[0] * 4, palette[1] * 4, palette[2] * 4))
	var colors: PackedColorArray = PackedColorArray()
	for index in range(256):
		colors.append(Color8(palette[index * 3] * 4, palette[index * 3 + 1] * 4, palette[index * 3 + 2] * 4))
	check(surface.configure(UiFont.create(), colors, background), "dialogue surface configures an explicit opaque probe frame")
	var owner = Enter.new()
	check(owner.load_source(package.pal98_sources), "enter owner binds the admitted sources")
	var adapter = EntryHost.new()
	var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
	var kernel = Equipment.new()
	kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var state = _fixture(package.pal98_sources)
	adapter.bind(cache, kernel, state.inventory_bytes, [0, 0, 0, 0, 0, 0])
	adapter.bind_display(DisplayDouble.new())
	var dialogue_host = DialogueHost.new(); dialogue_host.bind(package.pal98_sources)
	var result: Dictionary = owner.start(state, 1, 4)
	var text_runs: Array = []
	var drawn: int = 0
	for step in range(4096):
		if not result.has("request"): break
		var request: Dictionary = result.request
		if request.kind == "dialogue":
			var effect: Dictionary = request.effect
			var receipt: Dictionary = dialogue_host.answer(effect)
			if effect.kind == "draw_string" and text_runs.size() < 1:
				var drawn_result: Dictionary = await surface.apply_request(effect,
					package.pal98_sources.metadata().text_encoding)
				if drawn_result.has("error"): push_error("surface draw failed: " + str(drawn_result.error))
				else: drawn += 1
				text_runs.append(dialogue_host.receipts().back())
			result = owner.resume(request.id, {"event": receipt})
		elif request.has("original_entry"): result = owner.resume(request.id, adapter.answer(request))
		elif request.has("state"): result = owner.resume(request.id, {"state": request.state, "completed": true})
		else: result = owner.resume(request.id, {"completed": true})
	check(not result.has("error"), "the real opening entry completes: " + str(result.get("error", "")))
	check(drawn >= 1, "the surface accepted the whole-string draw request: " + str(drawn))
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = surface.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	check(image.get_size() == Vector2i(320, 200), "captured dialogue frame is the fixed 320x200 target")
	var distinct: Dictionary = {}
	for y in range(0, 200, 2):
		for x in range(0, 320, 2):
			distinct[image.get_pixel(x, y).to_rgba32()] = true
	check(distinct.size() >= 3, "the captured frame carries the probe background and text pixels: " + str(distinct.size()))
	var snapshot: Array = surface.text_snapshot()
	check(snapshot.size() >= 1, "the surface reports its composed text runs: " + str(snapshot.size()))
	check(image.save_png(args[1]) == OK, "captured dialogue frame saved for review")
	finish(args)

func finish(args: Array) -> void:
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks,
		"original_gameplay": false, "window_probe": true, "system_font_candidate": true}, "\t")); file.close()
	print("Dialogue window probe: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
