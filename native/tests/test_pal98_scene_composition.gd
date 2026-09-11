# SPDX-License-Identifier: MIT
extends SceneTree
## Source resource fixtures, not reconstructed original new-game state.
const Package = preload("res://src/native_package.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Composition = preload("res://src/native_pal98_scene_composition.gd")
const Schema = preload("res://src/native_schema.gd")
var output: String
var checks: Array = []
var cases: Array = []
var failed: int = 0
var complete: bool = false

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3: quit(2); return
	output = args[2]
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): quit(2); return
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if reference.get("cases",[]).size() != 6 or not reference.get("source_unchanged",false) or not reference.get("guarded_output",false): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(180).timeout.connect(func(): check(false,"scene composition watchdog expired"); finish())
	var package = Package.new(); check(package.load_package(args[0]), "ordinary authored source package admitted: " + package.error)
	if package.pal98_sources == null or package.pal98_graphics == null: finish(); return
	var records = package.pal98_graphics.open_records(); var palette: PackedByteArray = records.palette(0,0).value
	var files: Dictionary = records.metadata().files
	check(files["MAP.MKF"].sha256 == "62739644af65b5e80c0736d31da00e4fe805a56ee5c5fede6558c0c13bacd575" and files["GOP.MKF"].sha256 == "5745d016a8d9c280b90a8b92d2871210a2dd0a0c04a79d4c8e65f4d0396aa04b" and files["MGO.MKF"].sha256 == "62ce20393e378c80538ba8b9ad1a24112e491f5afc5f350c5ebb00190b2317a0", "graphics identities match fixed original composition oracle")
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	root.size = Vector2i(1040,720); root.title = "PAL Wanxiang | source state and loaded cache composition"
	var viewport = SubViewport.new(); viewport.size = Vector2i(320,200); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST; root.add_child(viewport)
	var display = TextureRect.new(); display.texture = viewport.get_texture(); display.position = Vector2(40,60); display.size = Vector2(960,600)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; root.add_child(display)
	var label = Label.new(); label.position = Vector2(40,20); root.add_child(label)
	for scene in reference.cases:
		var cache = Cache.new(); check(cache.load_source(package.pal98_graphics,package.pal98_sources), "explicit cache owner created: " + scene.name)
		var state: Dictionary = storage.source_state(); state.loaded_scene_id = 1
		var party: Array = []; var roles: Array = []; var events: Array = []; var team_layer: int = 0
		for sprite in scene.sprites:
			if sprite.kind == "event":
				var row = PackedByteArray(); row.resize(32)
				for pair in [[2,int(sprite.x+scene.viewport_x)],[4,int(sprite.y+scene.viewport_y)],[6,int(sprite.layer/8)],[12,1],[16,int(sprite.mgo)],[18,1],[20,0],[22,int(sprite.frame)]]:
					row.encode_s16(pair[0],pair[1])
				events.append(row)
			else:
				party.append({"role_id":roles.size(),"x":int(sprite.x),"y":int(sprite.y),"current_frame":int(sprite.frame)})
				roles.append(int(sprite.mgo)); team_layer = int(sprite.layer)
		state.event_count = events.size()
		for index in range(events.size()): state.active_slots[index] = events[index]
		var loaded_events: Dictionary = cache.load_events(storage,state)
		var loaded_party: Dictionary = cache.load_party(party.size()-1,0,party,roles)
		check(not loaded_events.has("error") and not loaded_party.has("error"), "T98/T99 load source-bound scene cache: " + scene.name)
		if loaded_events.has("error") or loaded_party.has("error"): finish(); return
		state = loaded_events.state; party = loaded_party.party_records
		var caller: Dictionary = {"map_id":int(scene.map),"palette_index":0,"palette_variant":0,"map_mode":0,"clip_bottom":200,
			"viewport_x":int(scene.viewport_x),"viewport_y":int(scene.viewport_y),"member_last":party.size()-1,"follower_count":0,"team_layer":team_layer,"party_records":party}
		var owner: String = "render_scene_frame" if scene.sprites[0].kind == "event" else "submain"
		var prior_state: Dictionary = state.duplicate(true); var prior_caller: Dictionary = caller.duplicate(true)
		var prior_event: Dictionary = cache.snapshot("event"); var prior_party: Dictionary = cache.snapshot("party")
		var built: Dictionary = Composition.build(owner,records,storage,state,cache,caller)
		check(not built.has("error"), "state requests and cache frames reach GPU composition: " + scene.name + " " + str(built.get("error","")))
		if built.has("error"): finish(); return
		check(built.background_cell == {"x":int(scene.map_x),"y":int(scene.map_y),"half":int(scene.half)}, "pixel viewport derives exact original vmap cell: " + scene.name)
		check(built.requests.map(func(row):return row.kind) == scene.sprites.map(func(row):return row.kind), "actual owner preserves original sprite submission order: " + scene.name)
		var flags: PackedByteArray = FileAccess.get_file_as_bytes(args[1].get_base_dir().path_join(scene.flags))
		check(built.flags == flags, "all16384 flags match original through state/cache/T163 chain: " + scene.name)
		if int(scene.map) != 20: check(built.map_rows > 0, "nonempty original map occlusion required")
		viewport.add_child(built.value)
		label.text = "原始资源状态到缓存/绘制 · %s · 显式夹具，非原版新游戏" % scene.name
		await process_frame; await RenderingServer.frame_post_draw
		var original: PackedByteArray = FileAccess.get_file_as_bytes(args[1].get_base_dir().path_join(scene.path))
		var expected = PackedByteArray(); expected.resize(original.size()*4)
		for pixel in range(original.size()):
			for channel in range(3): expected[pixel*4+channel] = palette[original[pixel]*3+channel]*4
			expected[pixel*4+3] = 255
		var image: Image = viewport.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
		var actual: PackedByteArray = image.get_data()
		check(actual == expected and original.size() == 64000, "GPU frame equals original oracle after state/cache composition: " + scene.name)
		check(state == prior_state and caller == prior_caller and cache.snapshot("event") == prior_event and cache.snapshot("party") == prior_party, "composition preserves caller state and both loaded caches: " + scene.name)
		cases.append({"name":scene.name,"owner":owner,"map_rows":built.map_rows,"sprite_rows":built.sprite_rows,"equal":actual==expected,"actual_rgba_sha256":Schema.digest(actual),"expected_rgba_sha256":Schema.digest(expected),"flags_sha256":Schema.digest(flags)})
		image.save_png(output.path_join(scene.name+"-actual.png"))
		if actual != expected: Image.create_from_data(320,200,false,Image.FORMAT_RGBA8,expected).save_png(output.path_join(scene.name+"-expected.png"))
		if scene.name == "map10-event-party": root.get_texture().get_image().save_png(output.path_join(scene.name+"-window.png"))
		var invalid: Dictionary = caller.duplicate(true); invalid.map_mode = 1
		check(Composition.build(owner,records,storage,state,cache,invalid).has("error"), "nonzero DrawMap mode is not replaced by ordinary scene draw")
		invalid = caller.duplicate(true); invalid.palette_variant = null
		check(Composition.build(owner,records,storage,state,cache,invalid).has("error"), "Unknown palette is not silently day0")
		invalid = caller.duplicate(true); invalid.map_id = float(caller.map_id)
		check(Composition.build(owner,records,storage,state,cache,invalid).has("error"), "composition rejects float IDs before typed helpers")
		if not party.is_empty():
			invalid = caller.duplicate(true); invalid.party_records[0].cache_word_offset = null
			var rejected: Dictionary = Composition.build(owner,records,storage,state,cache,invalid)
			check(rejected.has("error") and not rejected.has("value") and cache.snapshot("party") == prior_party, "Unknown loaded cache binding rejects without publishing a view or mutating cache")
		built.value.queue_free(); await process_frame
	complete = true; finish()

func finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":complete and failed==0,"complete":complete,"failed":failed,"checks":checks,"cases":cases,
		"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"original_gameplay":false,"explicit_test_state":true,"ordinary_session":false,"mac_amd_acceptance":false},"\t")); file.close()
	print("Original scene state composition: ",checks.size()," checks, ",failed," failed"); quit(0 if complete and failed==0 else 1)
