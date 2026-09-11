# SPDX-License-Identifier: MIT
extends SceneTree
const Reload = preload("res://src/native_pal98_resource_reload.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed: int = 0
var package

func check(ok: bool, label: String) -> void:
	checks.append({"name":label, "passed":ok})
	if not ok: failed += 1; push_error(label)

func fixture() -> Dictionary:
	var source = package.pal98_sources
	var events = Events.new(); events.load_source(source)
	var equipment = Equipment.new(); equipment.read_tables(source.copy_chunk("data",3),source.copy_chunk("sss",2),source.copy_chunk("sss",4))
	var inventory = PackedByteArray(); inventory.resize(1536)
	for slot in range(256): inventory.encode_u16(slot*6+4, 123)
	# Explicit lifecycle fixture, not the original game's initial state.
	return {"globals":{"current_scene":0,"requested_scene":1,"resource_flags":29,
		"loaded_map_id":0,"member_last":0,"follower_count":0,"viewport_x":864,"viewport_y":912,
		"wave_phase":7,"wave_amplitude":8,"midi_track":1,"save_slot":2},
		"events":events.source_state(), "equipment":equipment.initial_state([0]),
		"party_records":[{"role_id":0,"screen_x":160,"screen_y":112,"current_frame":0}],
		"inventory_bytes":inventory}

func owner():
	var result = Reload.new()
	check(result.load_source(package.pal98_sources,package.pal98_graphics), "reload owner binds admitted tables and graphics")
	return result

func cache():
	var result = Cache.new(); result.load_source(package.pal98_graphics,package.pal98_sources); return result

func finish_callbacks(driver, step: Dictionary) -> Dictionary:
	for index in range(200):
		if not step.has("request"): return step
		var request = step.request
		if request.kind == "enter_script":
			step = driver.resume(request.id,{"state":request.state,"return_entry":request.entry})
		elif request.kind in ["render_background","play_midi"]:
			# These explicit doubles exercise orchestration; they are NOT GPU,
			# audio, interpreter or original-gameplay acceptance.
			step = driver.resume(request.id,{"completed":true})
		else: return {"error":"unexpected callback in fixture"}
	return {"error":"test callback budget"}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size()!=2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	package = Package.new()
	check(package.load_package(args[0]), "ordinary authored source package admitted")
	if package.pal98_sources == null or package.pal98_graphics == null: finish(args[1]); return
	var state = fixture(); var before = state.duplicate(true); var original_cache = cache()
	var before_party = original_cache.snapshot("party"); var before_event = original_cache.snapshot("event")
	var driver = owner(); var step = driver.start(state, original_cache)
	check(step.has("request") and step.request.kind == "render_background", "actual event/map/cache work reaches background request before party or EnterScript")
	if not step.has("request"): print(step); finish(args[1]); return
	check(step.trace == ["entry","load_events","load_map_gop:20","load_event_sprites","render_background"], "T212 initial order and direct MAP20 loading preserved")
	check(step.request.state.globals.party_x == 160 and step.request.state.globals.party_y == 112 and step.request.state.globals.map_mode == 0 and step.request.state.globals.wave_phase == 0, "scene change writes anchors/mode and clears wave")
	check(step.request.map_cache.map_bytes == package.pal98_graphics.open_records().decoded_chunk("MAP.MKF",20).value, "request owns exact admitted decoded MAP20 bytes")
	var token: String = step.request.id
	check(driver.resume("stale",{"completed":true}).has("error") and driver.start(state,original_cache).has("error"), "stale response and overlapping start cannot replace pending reload")
	step.request.map_cache.map_bytes[0] ^= 255
	step = driver.resume(token,{"completed":true})
	check(step.has("request") and step.request.kind == "enter_script" and step.request.event_id == 0 and step.request.entry == 4 and step.request.state.globals.resource_flags == 0, "party load precedes real scene EnterScript4 request and mask retains only bit2")
	var response = step.request.state.duplicate(true)
	step = driver.resume(step.request.id,{"state":response,"return_entry":5})
	check(not step.has("error") and not step.has("request"), "bounded ordinary source equipment entries finish reload")
	if step.has("error") or step.has("request"): print(step); finish(args[1]); return
	check(step.trace == ["entry","load_events","load_map_gop:20","load_event_sprites","render_background","load_party_sprites","enter_script:1","prepare_equipment"], "completed T212 sequence includes equipment after EnterScript")
	check(step.state.events.scene_records.decode_u16(2) == 5 and state == before and original_cache.snapshot("party") == before_party and original_cache.snapshot("event") == before_event, "ByRef entry updates only completed candidate; caller state/caches retained")
	check(step.map_cache.map_bytes == package.pal98_graphics.open_records().decoded_chunk("MAP.MKF",20).value, "mutating background request bytes cannot mutate retained map cache")
	var usage_clear: bool = true
	for slot in range(256):
		if step.state.inventory_bytes.decode_u16(slot*6+4) != 0: usage_clear = false
	check(usage_clear and not step.cache.resolve("party",step.state.party_records[0].cache_word_offset,0).has("error"), "actual party sprite and all256 inventory usage fields prepared")
	var stable = step
	var same = stable.state.duplicate(true); same.globals.resource_flags = 0; same.globals.wave_phase = 12
	var reused = finish_callbacks(driver,driver.start(same,stable.cache,stable.map_cache))
	check(not reused.has("error") and not reused.trace.has("load_map_gop:20") and reused.state.globals.wave_phase == 12, "same-map reload retains known cache and wave state without map I/O")
	var missing = driver.start(same,stable.cache)
	check(missing.has("error") and missing.error.contains("matching cache"), "same loaded ID cannot invent unknown map backing")
	var midi_state = stable.state.duplicate(true); midi_state.globals.resource_flags = 2; midi_state.globals.midi_track = 7
	var midi = driver.start(midi_state,stable.cache,stable.map_cache)
	midi = driver.resume(midi.request.id,{"completed":true})
	check(midi.has("request") and midi.request.kind == "play_midi" and midi.request.track == 7 and midi.request.loop == 1 and midi.request.state.globals.resource_flags == 2, "MIDI request preserves flag until acknowledged and uses loop1")
	var rejected = driver.resume(midi.request.id,{})
	check(rejected.has("error") and midi_state.globals.resource_flags == 2, "unacknowledged audio cannot count as completed reload")
	var save_state = fixture(); save_state.globals.resource_flags = 32
	var saved = driver.start(save_state,original_cache)
	check(saved.has("request") and saved.request.kind == "load_save" and saved.request.slot == 2, "save bit requests actual save owner before resource work")
	var saved_response = saved.request.state.duplicate(true); saved_response.globals.resource_flags = 7
	saved_response.globals.wave_phase = 15
	var save_next = driver.resume(saved.request.id,{"state":saved_response})
	check(save_next.request.state.globals.wave_phase == 15 and not save_next.trace.has("commit_events"), "save branch bypasses non-save scene-change wave/writeback path")
	var saved_final = finish_callbacks(driver,save_next)
	check(not saved_final.has("error") and saved_final.trace.has("play_midi"), "save-return flags are consumed by normal resource and MIDI phases")
	var stale_token: String = token
	var pending = driver.start(fixture(),original_cache); stale_token = pending.request.id; driver.cancel()
	check(driver.resume(stale_token,{"completed":true}).has("error"), "cancel invalidates pending request generation")
	var invalid = fixture(); invalid.globals.viewport_x = null
	check(driver.start(invalid,original_cache).has("error") and original_cache.snapshot("party") == before_party, "Unknown viewport fails without publishing prepared cache")
	var different = stable.state.duplicate(true); different.events.source_fingerprint = "another"
	check(driver.start(different,stable.cache,stable.map_cache).has("error"), "foreign event state rejected")
	# Synthetic scene boundaries over real resource bytes exercise the retained
	# active buffer when a caller changes scene WITHOUT flag4.
	var retained = fixture(); retained.globals.current_scene = 1; retained.globals.requested_scene = 2; retained.globals.resource_flags = 0
	retained.events.scene_records.encode_u16(0,20); retained.events.scene_records.encode_u16(6,0)
	retained.events.scene_records.encode_u16(8,20); retained.events.scene_records.encode_u16(14,1)
	retained.events.scene_records.encode_u16(22,2)
	retained.events.loaded_scene_id = 1; retained.events.event_count = 1
	var row = PackedByteArray(); row.resize(32); row.encode_u16(16,2); row.encode_u16(20,1)
	retained.events.active_slots[0] = row
	var switched = finish_callbacks(driver,driver.start(retained,original_cache))
	check(not switched.has("error") and switched.state.globals.current_scene == 2 and switched.state.events.loaded_scene_id == 1 and not switched.trace.has("load_events"), "without flag4 current scene changes while event backing remains from previous load")
	if not switched.has("error"):
		var old_first: PackedByteArray = switched.state.events.global_events.slice(0,32)
		switched.state.events.active_slots[0][2] = 77
		var changed_row: PackedByteArray = switched.state.events.active_slots[0].duplicate()
		switched.state.globals.requested_scene = 1
		var back = finish_callbacks(driver,driver.start(switched.state,switched.cache,switched.map_cache))
		check(not back.has("error") and back.state.events.global_events.slice(32,64) == changed_row and back.state.events.global_events.slice(0,32) == old_first, "T175 writes retained buffer at CURRENT scene2 base rather than its old loaded scene1 base")
	# EnterScript's returned ByRef entry remains bound to its original scene,
	# even when the script requests another scene and restarts the whole owner.
	var redirect = fixture(); redirect.events.scene_records.encode_u16(8,10)
	redirect.events.scene_records.encode_u16(14,0); redirect.events.scene_records.encode_u16(22,0)
	var redirected = driver.start(redirect,original_cache)
	redirected = driver.resume(redirected.request.id,{"completed":true})
	var changed = redirected.request.state.duplicate(true)
	changed.globals.requested_scene = 2; changed.globals.resource_flags = 12
	redirected = driver.resume(redirected.request.id,{"state":changed,"return_entry":123})
	check(redirected.request.kind == "render_background" and redirected.request.state.globals.current_scene == 2 and redirected.request.map_cache.map_id == 10, "scene-changing EnterScript restarts entry/writeback/resources before next script")
	redirected = finish_callbacks(driver,redirected)
	check(not redirected.has("error") and redirected.state.events.scene_records.decode_u16(2) == 123 and redirected.trace.count("entry") == 2 and redirected.trace.has("enter_script:2"), "original EnterScript ByRef target survives redirected second scene and terminal equipment")
	var invalid_party = stable.state.duplicate(true); invalid_party.globals.resource_flags = 0; invalid_party.party_records[0].role_id = 0.0
	var invalid_party_result = finish_callbacks(driver,driver.start(invalid_party,stable.cache,stable.map_cache))
	check(invalid_party_result.has("error"), "party role float does not bypass validation when sprite reload is skipped")
	var cyclic = driver.start(redirect,original_cache)
	for index in range(200):
		if not cyclic.has("request"): break
		var request = cyclic.request
		if request.kind == "enter_script":
			var cycle_state = request.state.duplicate(true)
			cycle_state.globals.requested_scene = 2 if cycle_state.globals.current_scene == 1 else 1
			cycle_state.globals.resource_flags = 12
			cyclic = driver.resume(request.id,{"state":cycle_state,"return_entry":request.entry})
		else: cyclic = driver.resume(request.id,{"completed":true})
	check(cyclic.has("error") and cyclic.error.contains("budget") and original_cache.snapshot("party") == before_party, "cyclic EnterScript scene restarts diagnose at explicit budget without publishing candidate cache")
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	check(storage.commit_current_events(stable.state.events,1.0).has("error") and storage.commit_current_events(stable.state.events,null).has("error"), "explicit T175 current scene refuses implicit float and Unknown")
	finish(args[1])

func finish(path: String) -> void:
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failed==0,"failed":failed,"checks":checks,
		"display_audio_script_save_callbacks":"explicit test doubles", "original_gameplay":false},"\t")); file.close()
	print("Original resource reload: ",checks.size()," checks, ",failed," failed"); quit(0 if failed==0 else 1)
