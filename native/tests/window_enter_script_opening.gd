# SPDX-License-Identifier: MIT
extends SceneTree
## Windowed, chain-driven opening frame: the real entry script's own effects
## (world position, viewport, role map sprite) feed the verified background and
## depth composition, and the window is captured as evidence.
##
## This is a window probe, not an ordinary Session: no input device, audio,
## save or original process is involved, and the composed frame uses explicit
## day palette 0.
const Enter = preload("res://src/native_pal98_enter_script.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const DialogueHost = preload("res://src/native_pal98_dialogue_host.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
const Package = preload("res://src/native_package.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
const Queue = preload("res://src/native_pal98_depth_queue.gd")

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

func _dialogue_event(effect: Dictionary) -> Dictionary:
	match effect.get("kind"):
		"capture_background": return {"kind": "captured"}
		"restore_background": return {"kind": "restored"}
		"draw_dialogue_box": return {"kind": "box_drawn"}
		"draw_dialogue_icon", "draw_glyph", "draw_string": return {"kind": "drawn"}
		"wait": return {"kind": "tick"}
	return {"kind": "input", "action": 2}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3: quit(2); return
	create_timer(240).timeout.connect(func(): check(false, "opening window probe watchdog"); finish(args))
	var package = Package.new()
	if not package.load_package(args[0]):
		push_error("package rejected: " + str(package.error)); quit(2); return
	if package.pal98_sources == null or package.pal98_graphics == null:
		push_error("sources and graphics required"); quit(2); return
	var records = package.pal98_graphics.open_records()
	var source_records = package.pal98_sources.open_records()
	var palette: PackedByteArray = records.palette(0, 0).value
	var owner = Enter.new()
	check(owner.load_source(package.pal98_sources), "enter owner binds the admitted sources")
	var adapter = EntryHost.new()
	var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
	var kernel = Equipment.new()
	kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var state = _fixture(package.pal98_sources)
	check(adapter.bind(cache, kernel, state.inventory_bytes, [0, 0, 0, 0, 0, 0]), "owner adapter binds the real owners")
	adapter.bind_display(DisplayDouble.new())
	var dialogue_host = DialogueHost.new(); dialogue_host.bind(package.pal98_sources)
	var result: Dictionary = owner.start(state, 1, 4)
	var requests: Array = []
	for step in range(4096):
		if not result.has("request"): break
		var request: Dictionary = result.request; requests.append(request)
		if request.kind == "dialogue": result = owner.resume(request.id, {"event": dialogue_host.answer(request.effect)})
		elif request.has("original_entry"): result = owner.resume(request.id, adapter.answer(request))
		elif request.has("state"): result = owner.resume(request.id, {"state": request.state, "completed": true})
		else: result = owner.resume(request.id, {"completed": true})
	check(not result.has("error"), "the real opening entry completes: " + str(result.get("error", "")))
	if result.has("error"): finish(args); return
	var position: Dictionary = result.effects[0]
	var sprite_word: int = result.effects[1].sprite_word
	check(position.world_x == 1024 and position.viewport_x == 864 and position.viewport_y == 912,
		"the chain produced the real opening position and viewport")
	check(sprite_word == 193, "the chain produced role 0's real map sprite id")
	var cell: Dictionary = Occlusion.world_to_cell(position.viewport_x, position.viewport_y)
	check(not cell.has("error") and cell.value.x == 27 and cell.value.y == 57 and cell.value.half == 0,
		"the chain viewport maps to the documented original exrij cell: " + str(cell.get("value", cell)))
	var root = Window.new(); root.size = Vector2i(560, 400)
	root.title = "PAL Wanxiang | chain-driven original opening frame (explicit probe)"
	get_root().add_child(root)
	var viewport = SubViewport.new(); viewport.size = Vector2i(320, 200)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var underlay = ColorRect.new(); underlay.size = Vector2(320, 200); underlay.z_index = -3
	underlay.color = Color8(palette[0] * 4, palette[1] * 4, palette[2] * 4); viewport.add_child(underlay)
	var background = Background.new(); var occlusion = Occlusion.new(); var queue = Queue.new()
	var map_id: int = source_records.scene_for_runtime_id(1).value.map_word
	check(background.load_source(records, map_id, 0, 0) and occlusion.load_source(records, map_id),
		"the chain's map identity and explicit day palette load")
	var rows: Array = []
	var frame: Dictionary = records.frame("MGO.MKF", sprite_word, 0)
	check(not frame.has("error"), "the chain's sprite word decodes a real frame: " + str(frame.get("error", "")))
	if frame.has("error"): finish(args); return
	var row: Dictionary = Queue.row_for_sprite("party", state.globals.party_x, state.globals.party_y, 0,
		frame.value, frame.source)
	check(not row.has("error"), "the party sprite forms a T163 depth row: " + str(row.get("error", "")))
	if row.has("error"): finish(args); return
	rows.append(row.value)
	var mark: Dictionary = occlusion.mark_sprite(state.globals.party_x, state.globals.party_y,
		position.viewport_x, position.viewport_y, 0, frame.value.width, frame.value.height, 0)
	check(not mark.has("error"), "the source bounding box marks the map: " + str(mark.get("error", "")))
	var map_rows: Dictionary = occlusion.queue_rows(position.viewport_x, position.viewport_y)
	check(not map_rows.has("error"), "the marked map frames queue: " + str(map_rows.get("error", "")))
	if map_rows.has("error"): finish(args); return
	rows.append_array(map_rows.value)
	check(queue.load_rows(rows), "explicit sprite then original map rows admitted")
	var map_view: Dictionary = background.make_view(cell.value.x, cell.value.y, cell.value.half)
	var depth_view: Dictionary = queue.make_view(palette, 200)
	check(not map_view.has("error") and not depth_view.has("error"), "background and depth views prepared")
	if map_view.has("error") or depth_view.has("error"): finish(args); return
	viewport.add_child(map_view.value); viewport.add_child(depth_view.value)
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	check(image.get_size() == Vector2i(320, 200), "captured frame is the fixed 320x200 target")
	var distinct: Dictionary = {}
	for y in range(0, 200, 2):
		for x in range(0, 320, 2):
			distinct[image.get_pixel(x, y).to_rgba32()] = true
	check(distinct.size() >= 8, "captured frame carries composed pixel content: " + str(distinct.size()))
	var error: int = image.save_png(args[1])
	check(error == OK, "captured frame saved for review")
	finish(args)

func finish(args: Array) -> void:
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks,
		"original_gameplay": false, "window_probe": true}, "\t")); file.close()
	print("Opening window probe: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
