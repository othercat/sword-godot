# SPDX-License-Identifier: MIT
extends SceneTree
## EnterScript owner probes: synthetic instructions plus the admitted ordinary
## source package. Host effects are explicit acknowledgements; no ordinary
## Session, rendering, audio, save or gameplay is activated here.
const Enter = preload("res://src/native_pal98_enter_script.gd")
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Reload = preload("res://src/native_pal98_resource_reload.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Schema = preload("res://src/native_schema.gd")
const Package = preload("res://src/native_package.gd")
const EntryHost = preload("res://src/native_pal98_entry_host.gd")
const DialogueHost = preload("res://src/native_pal98_dialogue_host.gd")
const Inventory = preload("res://src/native_pal98_inventory.gd")
var checks: Array = []
var failed: int = 0
var package
var coverage: Dictionary = {}

## Explicit display double: it acknowledges render/restore requests so the chain
## can be driven, and records what it was asked to do.
class DisplayDouble:
	var requests: Array = []
	func answer(request: Dictionary) -> Dictionary:
		requests.append(request.kind)
		return {"completed": true}

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4; var bytes = _zero(size); bytes.encode_u32(0, size)
	for i in range(chunks.size()): size += chunks[i].size(); bytes.encode_u32((i + 1) * 4, size)
	for chunk in chunks: bytes.append_array(chunk)
	return bytes

## Synthetic admitted source: scene boundaries, scene enter words, program and
## optional message payloads. Instruction index 0 stays the reserved zero record.
func _source(boundaries: Array, enter_words: Array, program: Array, messages: Array = [], event_count: int = 1):
	var events: PackedByteArray = _zero(event_count * 32)
	var scenes: PackedByteArray = _zero((boundaries.size() + 1) * 8)
	for index in range(boundaries.size()):
		scenes.encode_u16(index * 8, 20)
		scenes.encode_u16(index * 8 + 2, enter_words[index])
		scenes.encode_u16(index * 8 + 6, boundaries[index])
	var offsets: PackedByteArray = _zero((messages.size() + 1) * 4); var payload = PackedByteArray()
	for i in range(messages.size()):
		payload.append_array(messages[i]); offsets.encode_u32((i + 1) * 4, payload.size())
	var scripts: PackedByteArray = _zero((program.size() + 1) * 8)
	for i in range(program.size()):
		for word in range(4): scripts.encode_u16((i + 1) * 8 + word * 2, program[i][word] & 0xffff)
	var files: Dictionary = {"data": _mkf([_zero(0), _zero(0), _zero(0), _zero(900)]),
		"sss": _mkf([events, scenes, _zero(14), offsets, scripts]), "words": _zero(10), "messages": payload}
	var hashes: Dictionary = {}; var entries: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(files[role])
	var identity: String = Sources.fingerprint("gbk", hashes)
	for role in Sources.FILES: entries[role] = {"path": "content/pal98-sources/" + identity + "/" + Sources.FILES[role], "sha256": hashes[role], "size_bytes": files[role].size()}
	var source = Sources.new()
	if not source.load_source({"schema": Sources.SCHEMA, "kind": "content", "dialect": "pal98-win95", "text_encoding": "gbk",
		"fingerprint": identity, "files": entries, "label": "Synthetic enter script", "license": "CC0-1.0", "redistributable": true,
		"provenance": {"status": "synthetic"}}, files, Schema.new()): return null
	return source

func _context(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44, "origin_y": 26, "mode": 1,
		"line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202, "icon": 2, "skip_word": 0, "delay_units": 1, "input_action": 99,
		"capture_gate": 1, "restore_gate": 0, "colours": [79, 45, 26, 141], "timer_counter": 0}
	result.merge(overrides, true); return result

func _fixture(source, scene_id: int = 1) -> Dictionary:
	var events = Events.new(); events.load_source(source)
	var equipment = Equipment.new()
	equipment.read_tables(source.copy_chunk("data",3), source.copy_chunk("sss",2), source.copy_chunk("sss",4))
	return {"globals": {"current_scene": scene_id, "requested_scene": scene_id, "party_x": 160, "party_y": 112,
			"viewport_x": 864, "viewport_y": 912, "resource_flags": 0, "direction_word": 0, "loaded_map_id": 0,
			"member_last": 1, "follower_count": 0, "battle_mode": 0, "midi_track": 0, "battle_music_track": 0,
			"day_night_word": 0, "fade_gate_word": 0},
		"events": events.source_state(), "dialogue": _context(), "rng": Random.create(0x12345),
		# Five active members keep the fixed G04AC projection and the equipment
		# projections the same size, so multi-member entry commands can run.
		"equipment": equipment.initial_state([0, 1]),
		"inventory_bytes": _zero(1536),
		# The fixed G04AC projection: five slots, of which the active count is
		# carried by globals.member_last and the equipment role projection.
		"party_records": [{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 3},
			{"role_id": 1, "screen_x": 176, "screen_y": 104, "current_frame": 3},
			{"role_id": 0, "screen_x": 192, "screen_y": 96, "current_frame": 3},
			{"role_id": 0, "screen_x": 208, "screen_y": 88, "current_frame": 3},
			{"role_id": 0, "screen_x": 224, "screen_y": 80, "current_frame": 3}],
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

func _drive(owner, first: Dictionary) -> Dictionary:
	var result: Dictionary = first; var requests: Array = []
	for step in range(16384):
		if not result.has("request"): return {"result": result, "requests": requests}
		var request: Dictionary = result.request; requests.append(request)
		if request.kind == "dialogue": result = owner.resume(request.id, {"event": _dialogue_event(request.effect)})
		elif request.has("state"): result = owner.resume(request.id, {"state": request.state, "completed": true})
		else: result = owner.resume(request.id, {"completed": true})
	return {"result": {"error": "enter script driver budget exceeded"}, "requests": requests}

## Drives an invocation with the real owner adapter for command-owned requests
## and the display double for render/restore/audio requests.
func _drive_with_host(owner, first: Dictionary, adapter, dialogue_host = null) -> Dictionary:
	var result: Dictionary = first; var requests: Array = []
	for step in range(16384):
		if not result.has("request"): return {"result": result, "requests": requests}
		var request: Dictionary = result.request; requests.append(request)
		if request.kind == "dialogue":
			if dialogue_host != null:
				result = owner.resume(request.id, {"event": dialogue_host.answer(request.effect)})
			else:
				result = owner.resume(request.id, {"event": _dialogue_event(request.effect)})
		elif request.has("original_entry"):
			result = owner.resume(request.id, adapter.answer(request))
		elif request.has("state"):
			result = owner.resume(request.id, {"state": request.state, "completed": true})
		else:
			result = owner.resume(request.id, {"completed": true})
	return {"result": {"error": "enter script driver budget exceeded"}, "requests": requests}

func _owner(source) -> Variant:
	var owner = Enter.new()
	if not owner.load_source(source): push_error("enter owner load failed: " + owner.error); return null
	return owner

func _synthetic_checks() -> void:
	_inventory_checks()
	var program: Array = [[0x0046, 0x0020, 0x0040, 0x0000], [0x0065, 0x0000, 0x00C1, 0x0000],
		[0x0015, 0x0000, 0x0000, 0x0000], [0x0075, 0x0001, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var source = _source([0, 0], [1, 0], program)
	check(source != null, "synthetic admitted source builds")
	if source == null: return
	var owner = _owner(source)
	if owner == null: return
	check(owner.scene_count() == 2, "synthetic source exposes its records minus the terminal boundary")
	var state = _fixture(source)
	var mismatch = owner.start(state, 1, 2)
	check(mismatch.has("error") and str(mismatch.error).contains("does not match"), "request entry must equal the scene record enter word")
	var outside = owner.start(state, 3, 1)
	check(outside.has("error") and str(outside.error).contains("playable table"), "runtime scene outside the table is refused")
	var unknown = _fixture(source); unknown.globals.party_x = null
	var missing_run = owner.start(unknown, 1, 1)
	check(missing_run.has("error") and str(missing_run.error).contains("party screen anchor"),
		"unknown party anchor fails 0x0046 explicitly: " + str(missing_run.get("error", "")))
	var before = state.duplicate(true)
	var run = _drive(owner, owner.start(state, 1, 1))
	check(state == before, "enter script never mutates the caller's state")
	var result: Dictionary = run.result
	check(not result.has("error"), "the reviewed entry prefix completes: " + str(result.get("error", "")))
	var kinds: Array = result.effects.map(func(effect): return effect.kind)
	check(kinds == ["party_map_position", "role_map_sprite", "party_direction_frame", "party_composition"],
		"entry effects keep the original instruction order including the party rebuild")
	check(result.effects[0].world_x == 1024 and result.effects[0].world_y == 1024, "0x0046 applies the original world formula")
	check(result.effects[0].viewport_x == 864 and result.effects[0].viewport_y == 912, "0x0046 anchors the original viewport")
	check(result.effects[0].previous_x == 1024 and result.effects[0].previous_y == 1024,
		"0x0046 copies the new world position into the previous-position words")
	check(result.effects[0].trail_slots == 5 and result.effects[0].party_slots == 5,
		"0x0046 writes the fixed trail array and the backed party slots")
	# 0x0046 with full five-slot backing, formation steps and the replay request.
	var map_program: Array = [[0x0046, 0x0020, 0x0040, 0x0000], [0x0001, 0, 0, 0]]
	var map_source = _source([0, 0], [1, 0], map_program)
	var map_owner = _owner(map_source)
	var map_state = _fixture(map_source)
	while map_state.party_records.size() < 5:
		map_state.party_records.append({"role_id": 0, "screen_x": 0, "screen_y": 0, "current_frame": 3})
	var fields: Array = []
	for slot in range(5): fields.append(map_state.equipment.party_fields[0].duplicate(true))
	map_state.equipment.party_fields = fields
	map_state.equipment.party_roles = [0, 0, 0, 0, 0]
	map_state.equipment.party_statuses = fields.duplicate(true)
	var map_run = _drive(map_owner, map_owner.start(map_state, 1, 1))
	check(not map_run.result.has("error"), "0x0046 completes with five backed slots: " + str(map_run.result.get("error", "")))
	check(map_run.result.state.party_records[0].screen_x == 160 and map_run.result.state.party_records[0].screen_y == 112
		and map_run.result.state.party_records[1].screen_x == 176 and map_run.result.state.party_records[1].screen_y == 104,
		"0x0046 steps the member screen positions with the direction-0 formation table")
	check(map_run.result.state.party_records[4].current_frame == 3
		and map_run.result.state.party_records[2].current_frame == 3,
		"0x0046 copies the leader frame word to every member slot")
	check(map_run.result.state.party_trail[0].x == 1024 and map_run.result.state.party_trail[0].y == 1024
		and map_run.result.state.party_trail[1].x == 1040 and map_run.result.state.party_trail[1].y == 1016
		and map_run.result.state.party_trail[4].direction_word == 0,
		"0x0046 writes the five trail entries from member position plus viewport")
	check(map_run.result.unimplemented.is_empty(), "a fully backed 0x0046 reports no sub-effect gap")
	check(map_run.requests.map(func(request): return request.kind).has("render_current_map_background"),
		"non-battle 0x0046 asks the host to re-render the map background")
	var far_program: Array = [[0x0046, 0x0020, 0x0190, 0x0000], [0x0001, 0, 0, 0]]
	var far_source = _source([0, 0], [1, 0], far_program)
	var far_owner = _owner(far_source)
	var far = far_owner.start(_fixture(far_source), 1, 1)
	check(far.has("error") and str(far.error).contains("ffxy"), "0x0046 refuses a viewport outside the reviewed ffxy bounds")
	check(result.effects[1].sprite_word == 193 and result.effects[1].role == 0, "0x0065 writes role0 map sprite 193")
	check(result.effects[2].frame_word == 0 and result.effects[2].direction_word == 0, "0x0015 writes direction 0 and frame 0")
	check(result.effects[3].roles == [0] and result.effects[3].member_last == 0,
		"0x0075 rebuilds the single-member party from argument 1")
	check(result.get("partial") == true and result.unimplemented.size() == 1,
		"the run reports its named sub-effect gaps instead of a full success")
	check(str(result.unimplemented[0].sub_effect).contains("T230"),
		"named gaps cover the T230 member sync")
	var owner_kinds: Array = run.requests.filter(func(request): return request.has("procedure")).map(func(request): return request.kind)
	check(owner_kinds == ["render_current_map_background", "load_party_sprites", "rebuild_party_equipment"],
		"0x0046 asks for the background replay and 0x0075 asks the sprite and equipment owners before the trigger resumes")
	# ByRef entry: a scene whose enter block returns advances the entry word.
	var simple = _source([0, 0], [1, 0], [[0x0041, 0, 0, 0], [0x0001, 0, 0, 0]])
	var simple_owner = _owner(simple)
	var simple_state = _fixture(simple)
	var completed = _drive(simple_owner, simple_owner.start(simple_state, 1, 1))
	# The original return handling is fixed by opcode: 0001 increments the entry
	# before exiting, 0000 restores the saved entry instead.
	check(not completed.result.has("error") and completed.result.return_entry == 3,
		"0x0041 followed by opcode 0001 returns the incremented ByRef entry: " + str(completed.result.get("return_entry", completed.result.get("error"))))
	check(completed.result.get("partial") == false, "a run with no named sub-effect gap is not marked partial")
	check(completed.result.effects[0].kind == "script_failure_word" and completed.result.state.globals.trigger_success_word == 0, "0x0041 writes G0302 = 0")
	check(not simple_state.globals.has("trigger_success_word"), "completed candidate stays detached from the caller")
	# 0x0048 is the original explicit no-op.
	var noop = _source([0, 0], [1, 0], [[0x0048, 0, 0, 0], [0x0001, 0, 0, 0]])
	var noop_owner = _owner(noop)
	var noop_result = _drive(noop_owner, noop_owner.start(_fixture(noop), 1, 1))
	check(not noop_result.result.has("error") and noop_result.result.effects[0].kind == "original_no_op", "0x0048 stays an explicit original no-op")
	# 0x0015 formula and slot bounds.
	var frame_program: Array = [[0x0015, 0x0002, 0x0001, 0x0000], [0x0001, 0, 0, 0]]
	var frame_source = _source([0, 0], [1, 0], frame_program)
	var frame_owner = _owner(frame_source)
	var frame_state = _fixture(frame_source)
	var frame_result = _drive(frame_owner, frame_owner.start(frame_state, 1, 1))
	check(not frame_result.result.has("error") and frame_result.result.effects[0].frame_word == 7 and frame_result.result.effects[0].direction_word == 2,
		"0x0015 computes direction*3+Arg1 for the party slot")
	var slot_program: Array = [[0x0015, 0x0000, 0x0000, 0x0004], [0x0001, 0, 0, 0]]
	var slot_source = _source([0, 0], [1, 0], slot_program)
	var slot_owner = _owner(slot_source)
	var slot_result = slot_owner.start(_fixture(slot_source), 1, 1)
	check(not slot_result.has("error"), "0x0015 accepts a backed party slot inside the fixed array")
	var beyond_program: Array = [[0x0015, 0x0000, 0x0000, 0x0009], [0x0001, 0, 0, 0]]
	var beyond_source = _source([0, 0], [1, 0], beyond_program)
	var beyond_owner = _owner(beyond_source)
	var beyond = beyond_owner.start(_fixture(beyond_source), 1, 1)
	check(beyond.has("error") and str(beyond.error).contains("party record"), "0x0015 refuses a slot beyond the fixed array")
	# 0x0059 valid changed scene and unchanged scene.
	var scene_program: Array = [[0x0059, 0x0002, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var scene_source = _source([0, 0, 0], [1, 0, 0], scene_program)
	var scene_owner = _owner(scene_source)
	var scene_state = _fixture(scene_source)
	var scene_result = _drive(scene_owner, scene_owner.start(scene_state, 1, 1))
	check(not scene_result.result.has("error") and scene_result.result.state.globals.requested_scene == 2
		and scene_result.result.state.globals.resource_flags == 12, "0x0059 requests scene 2 and sets the original event/EnterScript mask")
	check(scene_result.result.state.globals.party_layer_word == 0 and scene_result.result.unimplemented.is_empty(),
		"0x0059 clears the party layer word without a sub-effect gap")
	check(scene_result.result.get("partial") == false, "a run without named gaps is not partial")
	var same_program: Array = [[0x0059, 0x0001, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var same_source = _source([0, 0], [1, 0], same_program)
	var same_owner = _owner(same_source)
	var same_result = _drive(same_owner, same_owner.start(_fixture(same_source), 1, 1))
	check(not same_result.result.has("error") and same_result.result.effects[0].kind == "scene_request_skipped", "0x0059 leaves an unchanged scene alone")
	var bad_scene: Array = [[0x0059, 0x0009, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var bad_source = _source([0, 0], [1, 0], bad_scene)
	var bad_owner = _owner(bad_source)
	var bad_result = _drive(bad_owner, bad_owner.start(_fixture(bad_source), 1, 1))
	check(not bad_result.result.has("error") and bad_result.result.effects[0].kind == "scene_request_skipped", "0x0059 refuses a scene outside the playable table")
	# 0x0065 role sprite and the unimplemented reload branch.
	var sprite_program: Array = [[0x0065, 0x0000, 0x00C1, 0x0000], [0x0001, 0, 0, 0]]
	var sprite_source = _source([0, 0], [1, 0], sprite_program)
	var sprite_owner = _owner(sprite_source)
	var sprite_state = _fixture(sprite_source)
	var sprite_result = _drive(sprite_owner, sprite_owner.start(sprite_state, 1, 1))
	check(not sprite_result.result.has("error") and sprite_result.result.state.equipment.role_words[2] == 193, "0x0065 writes role0 map sprite 193 in the admitted role table")
	var reload_program: Array = [[0x0065, 0x0000, 0x00C1, 0x0001], [0x0001, 0, 0, 0]]
	var reload_source = _source([0, 0], [1, 0], reload_program)
	var reload_owner = _owner(reload_source)
	var reload_run = _drive(reload_owner, reload_owner.start(_fixture(reload_source), 1, 1))
	check(not reload_run.result.has("error") and reload_run.result.effects[0].reload == true
		and reload_run.result.effects[0].reloaded == true,
		"0x0065 asks the sprite owner for the outside-battle field reload: " + str(reload_run.result.get("error", "")))
	check(reload_run.requests.map(func(request): return request.kind).has("load_party_sprites"),
		"the 0x0065 reload reaches the host as a real owner request")
	var battle_state = _fixture(reload_source); battle_state.globals.battle_mode = 1
	var battle_owner = _owner(reload_source)
	var battle_run = _drive(battle_owner, battle_owner.start(battle_state, 1, 1))
	check(not battle_run.result.has("error") and battle_run.result.effects[0].reloaded == false
		and battle_run.result.unimplemented.size() == 1,
		"0x0065 in battle mode names the suppressed reload instead of faking it")
	# 0x0016 resolved event fields: zero no-op, current event, scene record, global fallback.
	var event_program: Array = [[0x0016, 0xFFFF, 0x1234, 0x5678], [0x0001, 0, 0, 0]]
	var event_source = _source([0, 2], [1, 0], event_program, [], 2)
	var event_owner = _owner(event_source)
	var event_state = _fixture(event_source)
	var event_storage = Events.new(); event_storage.load_source(event_source)
	event_state.events = event_storage.load_scene_events(event_state.events, 1).state
	check(event_state.events.event_count == 2, "the synthetic scene exposes two event records")
	var entry_context = _drive(_owner(event_source), _owner(event_source).start(event_state, 1, 1))
	check(entry_context.result.has("error") and str(entry_context.result.error).contains("scene-entry context 0"),
		"0x0016 names the unowned scene-entry event context instead of writing slot 0")
	var event_run = _drive(event_owner, event_owner.start(event_state, 1, 1, 2))
	check(not event_run.result.has("error") and event_run.result.effects[0].scope == "current_event"
		and event_run.result.effects[0].event_id == 2,
		"a negative 0x0016 target writes the current event slot: " + str(event_run.result.get("error", "")))
	var written_row: PackedByteArray = event_run.result.state.events.active_slots[1]
	check(written_row.decode_u16(20) == 0x1234 and written_row.decode_u16(22) == 0x5678,
		"0x0016 writes fields +20/+22 of the resolved record")
	var scene_target_program: Array = [[0x0016, 0x0002, 0x00AA, 0x00BB], [0x0001, 0, 0, 0]]
	var scene_event_source = _source([0, 2], [1, 0], scene_target_program, [], 2)
	var scene_event_owner = _owner(scene_event_source)
	var scene_event_state = _fixture(scene_event_source)
	var scene_event_storage = Events.new(); scene_event_storage.load_source(scene_event_source)
	scene_event_state.events = scene_event_storage.load_scene_events(scene_event_state.events, 1).state
	var scene_event_run = _drive(scene_event_owner, scene_event_owner.start(scene_event_state, 1, 1))
	check(not scene_event_run.result.has("error") and scene_event_run.result.effects[0].scope == "current_scene"
		and scene_event_run.result.effects[0].event_id == 2,
		"a positive 0x0016 target resolves against the scene event base")
	var global_program: Array = [[0x0016, 0x0001, 0x0BAD, 0x0F00], [0x0001, 0, 0, 0]]
	var global_source = _source([0, 0], [1, 0], global_program, [], 1)
	var global_owner = _owner(global_source)
	var global_state = _fixture(global_source)
	var global_storage = Events.new(); global_storage.load_source(global_source)
	global_state.events = global_storage.load_scene_events(global_state.events, 1).state
	var global_run = _drive(global_owner, global_owner.start(global_state, 1, 1))
	check(not global_run.result.has("error") and global_run.result.effects[0].scope == "global_table"
		and global_run.result.state.events.global_events.decode_u16(20) == 0x0BAD,
		"an out-of-scene 0x0016 target falls back to the global event table: "
			+ str(global_run.result.get("error", global_run.result.get("effects", []))))
	var zero_program: Array = [[0x0016, 0x0000, 0x0001, 0x0002], [0x0001, 0, 0, 0]]
	var zero_source = _source([0, 2], [1, 0], zero_program, [], 2)
	var zero_owner = _owner(zero_source)
	var zero_run = _drive(zero_owner, zero_owner.start(_fixture(zero_source), 1, 1))
	check(not zero_run.result.has("error") and zero_run.result.effects[0].kind == "event_fields_skipped",
		"a zero 0x0016 target stays the original no-op")
	# 0x0035 / 0x0047 / 0x004A / 0x0053 / 0x0054.
	var state_program: Array = [[0x0035, 0x0003, 0x0000, 0x0000], [0x0047, 0x0012, 0x0000, 0x0000],
		[0x004A, 0x0009, 0x0000, 0x0000], [0x0053, 0x0000, 0x0000, 0x0000],
		[0x0054, 0x0000, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var state_source = _source([0, 0], [1, 0], state_program)
	var state_owner = _owner(state_source)
	var state_adapter = EntryHost.new()
	var state_cache = Cache.new(); state_cache.load_source(package.pal98_graphics, package.pal98_sources)
	var state_kernel = Equipment.new()
	state_kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var state_value = _fixture(state_source)
	state_adapter.bind(state_cache, state_kernel, state_value.inventory_bytes, [0, 0, 0, 0, 0, 0])
	state_adapter.bind_display(DisplayDouble.new())
	var state_run = _drive_with_host(state_owner, state_owner.start(state_value, 1, 1), state_adapter)
	var state_kinds: Array = state_run.result.effects.map(func(effect): return effect.kind)
	check(not state_run.result.has("error") and state_kinds == ["screen_shake", "sound_effect", "battlefield",
		"day_night_palette", "day_night_palette"],
		"0x0035/0x0047/0x004A/0x0053/0x0054 apply in order: " + str(state_kinds))
	check(state_run.result.state.globals.shake_count_word == 3
		and state_run.result.state.globals.shake_amplitude_word == 4,
		"0x0035 stores the count and default amplitude 4")
	check(state_run.result.state.globals.battlefield_word == 9
		and state_run.result.state.globals.day_night_word == 384,
		"0x004A stores the battlefield word and 0x0054 selects the night offset")
	check(state_run.requests.map(func(request): return request.kind).has("play_sound_effect"),
		"0x0047 asks the audio owner to play the effect")
	# 0x001F through the real inventory owner.
	# 0x006E party step: position copies, viewport delta, layer and owners.
	var step_program: Array = [[0x006E, 0x0010, 0xFFF8, 0x0002], [0x0001, 0, 0, 0]]
	var step_source = _source([0, 0], [1, 0], step_program)
	var step_owner = _owner(step_source)
	var step_state = _fixture(step_source)
	step_state.globals.world_x = 1024; step_state.globals.world_y = 1024
	var step_adapter = EntryHost.new()
	var step_cache = Cache.new(); step_cache.load_source(package.pal98_graphics, package.pal98_sources)
	var step_kernel = Equipment.new()
	step_kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	step_adapter.bind(step_cache, step_kernel, step_state.inventory_bytes, [0, 0, 0, 0, 0, 0])
	step_adapter.bind_display(DisplayDouble.new())
	var step_run = _drive_with_host(step_owner, step_owner.start(step_state, 1, 1), step_adapter)
	var step_effects: Array = step_run.result.get("effects", [])
	check(not step_run.result.has("error") and step_effects.size() == 1
		and step_effects[0].delta_x == 16 and step_effects[0].delta_y == -8 and step_effects[0].moved == true,
		"0x006E applies the party step deltas: " + str(step_run.result.get("error", "")))
	check(step_run.result.state.globals.viewport_x == 880 and step_run.result.state.globals.viewport_y == 904
		and step_run.result.state.globals.previous_viewport_x == 864
		and step_run.result.state.globals.party_layer_word == 16
		and step_run.result.state.globals.previous_x == 1024,
		"0x006E keeps the previous copies and stores the layer word")
	var step_requests: Array = step_run.requests.map(func(request): return request.kind)
	check(step_requests.has("post_move_update") and step_requests.has("update_viewport_and_party_position"),
		"a moving 0x006E requests both movement owners: " + str(step_requests))
	var idle_program: Array = [[0x006E, 0x0000, 0x0000, 0x0001], [0x0001, 0, 0, 0]]
	var idle_source = _source([0, 0], [1, 0], idle_program)
	var idle_owner = _owner(idle_source)
	var idle_state = _fixture(idle_source)
	idle_state.globals.world_x = 1024; idle_state.globals.world_y = 1024
	var idle_run = _drive(idle_owner, idle_owner.start(idle_state, 1, 1))
	var idle_effects: Array = idle_run.result.get("effects", [])
	check(not idle_run.result.has("error") and idle_effects.size() == 1 and idle_effects[0].moved == false
		and idle_run.requests.is_empty(),
		"a zero-delta 0x006E stores the layer word without movement requests")
	# 0x006D scene script words: set the pair, then clear it.
	var scene_words_program: Array = [[0x006D, 0x0001, 0x0DD9, 0x0014], [0x0001, 0, 0, 0]]
	var scene_words_source = _source([0, 0], [1, 0], scene_words_program)
	var scene_words_owner = _owner(scene_words_source)
	var scene_words_run = _drive(scene_words_owner, scene_words_owner.start(_fixture(scene_words_source), 1, 1))
	check(not scene_words_run.result.has("error")
		and scene_words_run.result.effects[0].enter_word == 0x0DD9
		and scene_words_run.result.effects[0].leave_word == 0x0014,
		"0x006D writes the scene's enter and leave script words: "
			+ str(scene_words_run.result.get("error", "")))
	var clear_program: Array = [[0x006D, 0x0001, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var clear_source = _source([0, 0], [1, 0], clear_program)
	var clear_owner = _owner(clear_source)
	var clear_state = _fixture(clear_source)
	clear_state.events.scene_records = clear_state.events.scene_records.duplicate()
	clear_state.events.scene_records.encode_u16(4, 0x0014)
	var clear_run = _drive(clear_owner, clear_owner.start(clear_state, 1, 1))
	var clear_effects: Array = clear_run.result.get("effects", [])
	check(not clear_run.result.has("error") and clear_effects.size() == 1
		and clear_effects[0].pair_cleared == true
		and clear_effects[0].enter_word == 0 and clear_effects[0].leave_word == 0,
		"a zero argument pair clears both scene script words: "
			+ str(clear_run.result.get("error", "")))
	var mixed_program: Array = [[0x006D, 0x0001, 0x0123, 0x0000], [0x0001, 0, 0, 0]]
	var mixed_source = _source([0, 0], [1, 0], mixed_program)
	var mixed_owner = _owner(mixed_source)
	var mixed_state = _fixture(mixed_source)
	mixed_state.events.scene_records = mixed_state.events.scene_records.duplicate()
	mixed_state.events.scene_records.encode_u16(4, 0x0014)
	var mixed_run = _drive(mixed_owner, mixed_owner.start(mixed_state, 1, 1))
	var mixed_effects: Array = mixed_run.result.get("effects", [])
	check(not mixed_run.result.has("error") and mixed_effects.size() == 1
		and mixed_effects[0].enter_word == 0x0123 and mixed_effects[0].leave_word == 0x0014,
		"a single zero argument leaves the other script word untouched")
	var bad_scene_program: Array = [[0x006D, 0x0000, 0x0001, 0x0000], [0x0001, 0, 0, 0]]
	var bad_scene_source = _source([0, 0], [1, 0], bad_scene_program)
	var bad_scene_owner = _owner(bad_scene_source)
	check(bad_scene_owner.start(_fixture(bad_scene_source), 1, 1).has("error"),
		"0x006D refuses a nonpositive scene argument")
	var item_program: Array = [[0x001F, 0x00C4, 0x0002, 0x0000], [0x0001, 0, 0, 0]]
	var item_source = _source([0, 0], [1, 0], item_program)
	var item_owner = _owner(item_source)
	var item_adapter = EntryHost.new()
	var item_cache = Cache.new(); item_cache.load_source(package.pal98_graphics, package.pal98_sources)
	var item_kernel = Equipment.new()
	item_kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var item_state = _fixture(item_source)
	item_adapter.bind(item_cache, item_kernel, item_state.inventory_bytes, [0, 0, 0, 0, 0, 0])
	item_adapter.bind_inventory(Inventory.new())
	item_adapter.bind_display(DisplayDouble.new())
	var item_run = _drive_with_host(item_owner, item_owner.start(item_state, 1, 1), item_adapter)
	check(not item_run.result.has("error"), "0x001F completes through the real inventory owner: "
		+ str(item_run.result.get("error", "")))
	var added_bytes: PackedByteArray = item_run.result.state.inventory_bytes
	check(added_bytes.decode_s16(0) == 0x00C4 and added_bytes.decode_s16(2) == 2
		and added_bytes.decode_s16(4) == 0,
		"the chain's 0x001F writes the item through T152 + T140")
	var item_answer: Dictionary = {}
	for answer in item_adapter.answered():
		if answer.get("kind") == "add_inventory_item": item_answer = answer
	check(item_answer.get("mode") == "created" and item_answer.get("slot") == 0,
		"the inventory owner reports the created record: " + str(item_answer))
	# A nonpositive amount defaults to one, as the original case does.
	var default_amount_program: Array = [[0x001F, 0x00C4, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var default_amount_source = _source([0, 0], [1, 0], default_amount_program)
	var default_amount_owner = _owner(default_amount_source)
	var default_adapter = EntryHost.new()
	default_adapter.bind(item_cache, item_kernel, _zero(1536), [0, 0, 0, 0, 0, 0])
	default_adapter.bind_inventory(Inventory.new())
	default_adapter.bind_display(DisplayDouble.new())
	var default_item_run = _drive_with_host(default_amount_owner,
		default_amount_owner.start(_fixture(default_amount_source), 1, 1),
		default_adapter)
	check(not default_item_run.result.has("error")
		and default_item_run.result.state.inventory_bytes.decode_s16(2) == 1,
		"a nonpositive 0x001F amount becomes one")
	# 0x0075 party rebuild: multi-member, default role and out-of-range argument.
	var multi_program: Array = [[0x0075, 0x0002, 0x0003, 0x0000], [0x0001, 0, 0, 0]]
	var multi_source = _source([0, 0], [1, 0], multi_program)
	var multi_owner = _owner(multi_source)
	var multi_state = _fixture(multi_source)
	while multi_state.party_records.size() < 3:
		multi_state.party_records.append({"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 0})
	var multi_fields: Array = []
	for slot in range(3): multi_fields.append(multi_state.equipment.party_fields[0].duplicate(true))
	multi_state.equipment.party_fields = multi_fields
	multi_state.equipment.party_statuses = multi_fields.duplicate(true)
	multi_state.equipment.party_roles = [0, 1, 2]
	var multi_result = _drive(multi_owner, multi_owner.start(multi_state, 1, 1))
	check(not multi_result.result.has("error") and multi_result.result.effects[0].roles == [1, 2]
		and multi_result.result.effects[0].member_last == 1 and multi_result.result.effects[0].inactive_slots == 3,
		"0x0075 rebuilds a two-member party and leaves the inactive slot untouched")
	check(multi_result.result.state.equipment.party_roles == [1, 2]
		and multi_result.result.state.party_records.size() == 5
		and multi_result.result.state.party_records[0].role_id == 1 and multi_result.result.state.party_records[1].role_id == 2,
		"the rebuilt composition writes the fixed party slots and the active equipment roles")
	check(multi_result.result.state.equipment.party_fields.size() == 2
		and multi_result.result.state.equipment.party_statuses.size() == 2,
		"the equipment projections follow the active member set")
	var default_program: Array = [[0x0075, 0x0000, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var default_source = _source([0, 0], [1, 0], default_program)
	var default_owner = _owner(default_source)
	var default_result = _drive(default_owner, default_owner.start(_fixture(default_source), 1, 1))
	check(not default_result.result.has("error") and default_result.result.effects[0].roles == [0],
		"a nonpositive first 0x0075 argument selects role 0")
	var bad_role_program: Array = [[0x0075, 0x0007, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var bad_role_source = _source([0, 0], [1, 0], bad_role_program)
	var bad_role_owner = _owner(bad_role_source)
	var bad_role = bad_role_owner.start(_fixture(bad_role_source), 1, 1)
	check(bad_role.has("error") and str(bad_role.error).contains("outside the source role table"),
		"0x0075 refuses a role argument outside the admitted role table")
	# 0x003B / 0x003D dialog globals and 0x008E background restore.
	var layout_program: Array = [[0x003B, 0x0000, 0x0000, 0x0000], [0x003D, 0x0000, 0x0000, 0x0000],
		[0x008E, 0x0000, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var layout_source = _source([0, 0], [1, 0], layout_program)
	var layout_owner = _owner(layout_source)
	var layout_result = _drive(layout_owner, layout_owner.start(_fixture(layout_source), 1, 1))
	check(not layout_result.result.has("error"), "the dialog-global commands complete: " + str(layout_result.result.get("error", "")))
	var layout_kinds: Array = layout_result.result.effects.map(func(effect): return effect.kind)
	check(layout_kinds == ["dialog_globals", "dialog_globals", "restore_dialog_background"],
		"0x003B, 0x003D and 0x008E apply in original order: " + str(layout_kinds))
	check(layout_result.result.state.dialogue.mode == 2 and layout_result.result.state.dialogue.origin_x == 44
		and layout_result.result.state.dialogue.origin_y == 126 and layout_result.result.state.dialogue.title_x == 12
		and layout_result.result.state.dialogue.title_y == 108,
		"0x003D writes the original lower-dialog geometry")
	check(layout_result.result.state.dialogue.capture_gate == 0 and layout_result.result.state.dialogue.restore_gate == 0,
		"0x008E clears both dialog gates")
	check(layout_result.requests.map(func(request): return request.kind).has("restore_dialog_background"),
		"0x008E asks the host to restore the captured dialog background")
	var centred_program: Array = [[0x003B, 0x0000, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var centred_source = _source([0, 0], [1, 0], centred_program)
	var centred_owner = _owner(centred_source)
	var centred = _drive(centred_owner, centred_owner.start(_fixture(centred_source), 1, 1))
	check(centred.result.state.dialogue.mode == 0 and centred.result.state.dialogue.origin_x == 80
		and centred.result.state.dialogue.origin_y == 40, "0x003B writes the original centered-dialog globals")
	var no_context_source = _source([0, 0], [1, 0], centred_program)
	var no_context_owner = _owner(no_context_source)
	var no_context_state = _fixture(no_context_source)
	no_context_state.dialogue = {}
	var no_context = no_context_owner.start(no_context_state, 1, 1)
	check(no_context.has("error"), "dialog-global commands refuse a missing dialogue context")
	# Relayed dialogue: the message instruction reaches the host, not a fake draw.
	var message_program: Array = [[0xFFFF, 0x0000, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var message_source = _source([0, 0], [1, 0], message_program, ["hello".to_utf8_buffer()])
	var message_owner = _owner(message_source)
	var message_result = _drive(message_owner, message_owner.start(_fixture(message_source), 1, 1))
	check(message_result.requests.size() > 0 and message_result.requests[0].kind == "dialogue", "FFFF is relayed to the host as a dialogue request")
	check(message_result.requests[0].has("state") and message_result.requests[0].state.get("dialogue", {}).has("mode"),
		"relayed effects carry the pending explicit state for the host")
	check(not message_result.result.has("error"), "relayed dialogue completion finishes the enter script")
	# Stale and cancelled completions cannot advance a new invocation.
	var stale_owner = _owner(simple)
	var first_step = stale_owner.start(_fixture(simple), 1, 1)
	check(stale_owner.resume("stale", {"event": {}}).has("error"), "stale completion is refused")
	stale_owner.cancel()
	check(stale_owner.resume(first_step.get("request", {}).get("id", "x"), {"event": {}}).has("error"), "cancelled invocation rejects its old request id")

## Full T212 cycle over admitted sources: the reload chain asks this owner for the
## scene entry script, the real owners answer the command requests, and the host
## answers the render/audio requests. A redirected real scene record keeps the
## cycle on an entry block whose commands are implemented.
## Runs every admitted scene's real enter script until the first command this
## consumer cannot execute, and records the depth plus the blocking opcode. This
## is a coverage report over the real pool, not a gameplay or Session claim.
func _coverage_checks() -> void:
	var records = package.pal98_sources.open_records()
	var commands = Commands.new()
	commands.load_source(package.pal98_sources)
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	var summary: Dictionary = records.table_summary()
	var scene_count: int = int(summary.counts.scenes)
	var rows: Array = []
	var blocked: Dictionary = {}
	var started: int = 0
	var completed: int = 0
	var depth_total: int = 0
	for raw in range(scene_count):
		var scene: Dictionary = records.scene(raw)
		if scene.has("error"): continue
		var entry: int = scene.value.enter_script_word
		if entry == 0: continue
		started += 1
		var owner = _owner(package.pal98_sources)
		if owner == null: continue
		var adapter = EntryHost.new()
		var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
		var kernel = Equipment.new()
		kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
			package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
		var state = _fixture(package.pal98_sources, raw + 1)
		state.events = storage.source_state()
		adapter.bind(cache, kernel, state.inventory_bytes, [0, 0, 0, 0, 0, 0])
		adapter.bind_inventory(Inventory.new())
		adapter.bind_display(DisplayDouble.new())
		var dialogue_host = DialogueHost.new(); dialogue_host.bind(package.pal98_sources)
		var run = _drive_with_host(owner, owner.start(state, raw + 1, entry), adapter, dialogue_host)
		var steps: int = run.result.get("effects", []).size()
		depth_total += steps
		if not run.result.has("error"):
			completed += 1
			rows.append({"runtime_scene": raw + 1, "entry": entry, "steps": steps, "blocked": ""})
		else:
			var opcode: String = "-"
			var words = run.result.get("diagnostic", {}).get("words", [])
			if words is Array and words.size() > 0: opcode = "0x%04X" % words[0]
			blocked[opcode] = blocked.get(opcode, 0) + 1
			rows.append({"runtime_scene": raw + 1, "entry": entry, "steps": steps, "blocked": opcode,
				"error": str(run.result.get("error", ""))})
	coverage = {"scenes_with_entry": started, "completed": completed,
		"average_effect_depth": (float(depth_total) / float(started)) if started > 0 else 0.0,
		"blocking_opcodes": blocked, "rows": rows}
	check(started >= 150, "the admitted pool exposes its scene entry scripts: " + str(started))
	check(completed >= 1 and coverage.average_effect_depth > 0.0,
		"at least one real scene entry runs to a return: " + str(completed))
	check(blocked.has("0x003C") or blocked.has("0x0075") or blocked.size() > 0,
		"the coverage report names the next blocking commands: " + str(blocked))

## T140/T144/T152 arithmetic over explicit inventory bytes.
func _inventory_checks() -> void:
	var inventory = Inventory.new()
	var bytes = _zero(1536)
	var created: Dictionary = inventory.add_item_amount(bytes, 0x00C4, 3)
	check(created.mode == "created" and created.slot == 0 and created.amount == 3,
		"adding an unknown item creates the first free record")
	check(created.inventory_bytes.decode_s16(0) == 0x00C4 and created.inventory_bytes.decode_s16(2) == 3
		and created.inventory_bytes.decode_s16(4) == 0,
		"the created record writes ItemId/Amount and clears AmountInUse")
	var merged: Dictionary = inventory.add_item_amount(created.inventory_bytes, 0x00C4, 2)
	check(merged.mode == "merged" and merged.slot == 0 and merged.amount == 5,
		"a living match takes the checked delta")
	check(inventory.add_item_amount(bytes, 0, 5).mode == "ignored", "a nonpositive item id returns immediately")
	var duplicate: PackedByteArray = created.inventory_bytes.duplicate()
	duplicate.encode_s16(6, 0x00C4); duplicate.encode_s16(8, 7)
	var duplicate_add: Dictionary = inventory.add_item_amount(duplicate, 0x00C4, 1)
	check(duplicate_add.slot == 0 and duplicate_add.amount == 4, "the add path merges the first living match")
	check(inventory.find_last_active_slot(duplicate, 0x00C4).value == 1,
		"the last-slot query returns the highest duplicate index")
	check(inventory.find_last_active_slot(bytes, 0x00C4).value == -1, "an absent item reports -1")
	var full = _zero(1536)
	for slot in range(256):
		full.encode_s16(slot * 6, 0x0100 + slot); full.encode_s16(slot * 6 + 2, 1)
	check(inventory.add_item_amount(full, 0x7FFF, 1).mode == "no_space",
		"a full inventory ends silently without a partial write")
	var messy = _zero(1536)
	messy.encode_s16(3 * 6, 0x0011); messy.encode_s16(3 * 6 + 2, 150)
	messy.encode_s16(7 * 6, 0x0022); messy.encode_s16(7 * 6 + 2, 5)
	var compressed: Dictionary = inventory.compress_and_return_last_slot(messy)
	check(compressed.last_slot == 1 and compressed.inventory_bytes.decode_s16(0) == 0x0011
		and compressed.inventory_bytes.decode_s16(2) == 99 and compressed.inventory_bytes.decode_s16(6) == 0x0022
		and compressed.inventory_bytes.decode_s16(8) == 5,
		"compress clamps to 99 and moves living records to the front in order")
	check(inventory.compress_and_return_last_slot(_zero(1536)).last_slot == -1, "an empty inventory compresses to -1")
	var overflow = _zero(1536)
	overflow.encode_s16(0, 0x0033); overflow.encode_s16(2, 32000)
	check(inventory.add_item_amount(overflow, 0x0033, 1000).has("error"),
		"a merge that leaves the signed I2 range is diagnosed instead of wrapped")

func _drive_reload(driver, step: Dictionary, cache, kernel) -> Dictionary:
	var effect_runs: Array = []
	var rounds := 0
	while step.has("request") and rounds < 64:
		rounds += 1
		var request: Dictionary = step.request
		if request.kind == "enter_script":
			var adapter = EntryHost.new()
			if not adapter.bind(cache, kernel, request.state.inventory_bytes, [0, 0, 0, 0, 0, 0]):
				return {"step": {"error": "cycle adapter bind failed: " + adapter.error}}
			adapter.bind_display(DisplayDouble.new())
			adapter.bind_inventory(Inventory.new())
			var dialogue_host = DialogueHost.new()
			dialogue_host.bind(package.pal98_sources)
			var owner = _owner(package.pal98_sources)
			var entry_state: Dictionary = request.state.duplicate(true)
			entry_state.dialogue = _context(); entry_state.rng = Random.create(0x12345)
			var run = _drive_with_host(owner, owner.start(entry_state, request.scene_id, request.entry,
				request.event_id), adapter, dialogue_host)
			if run.result.has("error"): return {"step": run.result}
			effect_runs.append(run.result.effects.duplicate(true))
			step = driver.resume(request.id, {"state": run.result.state,
				"return_entry": run.result.return_entry})
		else:
			step = driver.resume(request.id, {"completed": true})
	return {"step": step, "effect_runs": effect_runs}

func _pool_block(records, opcode: int, argument: int) -> int:
	for index in range(1, package.pal98_sources.counts().scripts - 1):
		var probe: Dictionary = records.instruction(index)
		if probe.has("error"): continue
		if probe.value.words[0] != opcode or probe.value.words[1] != argument: continue
		var following: Dictionary = records.instruction(index + 1)
		if not following.has("error") and following.value.words[0] in [0x0000, 0x0001]: return index
	return -1

func _cycle_checks() -> void:
	var records = package.pal98_sources.open_records()
	var minimal := -1
	for index in range(1, package.pal98_sources.counts().scripts - 1):
		var probe: Dictionary = records.instruction(index)
		if probe.has("error"): continue
		if probe.value.words[0] == 0x0015 and probe.value.words[1] == 0:
			var following: Dictionary = records.instruction(index + 1)
			if not following.has("error") and following.value.words[0] in [0x0000, 0x0001]:
				minimal = index; break
	check(minimal > 0, "the admitted script pool has a reviewed minimal entry block for a full cycle")
	if minimal <= 0: return
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	var reload_state = _fixture(package.pal98_sources)
	reload_state.inventory_bytes = PackedByteArray(); reload_state.inventory_bytes.resize(1536)
	reload_state.globals.resource_flags = 29
	reload_state.events = storage.source_state()
	reload_state.events.scene_records = reload_state.events.scene_records.duplicate()
	reload_state.events.scene_records.encode_u16(2, minimal)
	var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
	var kernel = Equipment.new()
	kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	var driver = Reload.new()
	check(driver.load_source(package.pal98_sources, package.pal98_graphics), "cycle owner binds the admitted sources")
	var cycle: Dictionary = _drive_reload(driver, driver.start(reload_state, cache), cache, kernel)
	var step: Dictionary = cycle.step
	var effects: Array = cycle.get("effect_runs", [[]])[0]
	var trace: Array = step.get("trace", [])
	check(not step.has("error"), "the full T212 cycle completes: " + str(step.get("error", "")))
	check(trace.has("load_events") and trace.has("load_event_sprites") and trace.has("load_party_sprites")
		and trace.has("enter_script:1") and trace.has("prepare_equipment"),
		"the cycle runs events, sprites, EnterScript, MIDI-safe equipment preparation in order: " + str(trace))
	check(effects.size() == 1 and effects[0].kind == "party_direction_frame",
		"the redirected real entry block ran its reviewed command: " + str(effects))
	check(step.state.globals.resource_flags == 0 and step.state.globals.direction_word == 0,
		"the completed cycle consumes the mask and keeps the script's direction word")
	# Second scenario: a real scene-request block restarts the chain on another
	# scene whose (redirected) event range is empty, so the whole loop closes.
	var request_block: int = _pool_block(records, 0x0059, 2)
	check(request_block > 0, "the admitted script pool has a real scene-request block for scene 2")
	if request_block <= 0: return
	var chain_state = _fixture(package.pal98_sources)
	chain_state.inventory_bytes = PackedByteArray(); chain_state.inventory_bytes.resize(1536)
	chain_state.globals.resource_flags = 29
	chain_state.events = storage.source_state()
	chain_state.events.scene_records = chain_state.events.scene_records.duplicate()
	chain_state.events.scene_records.encode_u16(2, request_block)
	chain_state.events.scene_records.encode_u16(10, minimal)
	chain_state.events.scene_records.encode_u16(14, 0)
	chain_state.events.scene_records.encode_u16(22, 0)
	chain_state.events.scene_records.encode_u16(30, 0)
	var chain_cache = Cache.new(); chain_cache.load_source(package.pal98_graphics, package.pal98_sources)
	var chain_driver = Reload.new()
	check(chain_driver.load_source(package.pal98_sources, package.pal98_graphics), "restart chain owner binds the admitted sources")
	var restarted_cycle: Dictionary = _drive_reload(chain_driver, chain_driver.start(chain_state, chain_cache),
		chain_cache, kernel)
	var restarted_step: Dictionary = restarted_cycle.step
	var restarted_trace: Array = restarted_step.get("trace", [])
	check(not restarted_step.has("error"), "the scene-request restart chain completes: " + str(restarted_step.get("error", "")))
	check(restarted_trace.count("entry") == 2 and restarted_trace.has("commit_events")
		and restarted_trace.has("enter_script:1") and restarted_trace.has("enter_script:2"),
		"the real scene request restarts the chain and both entry scripts run: " + str(restarted_trace))
	check(restarted_step.state.globals.current_scene == 2 and restarted_step.state.globals.requested_scene == 2
		and restarted_step.state.globals.resource_flags == 0,
		"the restarted chain ends on the requested scene with a consumed mask")
	check(restarted_cycle.effect_runs.size() == 2 and restarted_cycle.effect_runs[0].size() == 1
		and restarted_cycle.effect_runs[0][0].kind == "scene_request"
		and restarted_cycle.effect_runs[1][0].kind == "party_direction_frame",
		"both entry scripts applied their reviewed effects: " + str(restarted_cycle.effect_runs))

func _real_checks() -> void:
	_coverage_checks()
	_cycle_checks()
	var records = package.pal98_sources.open_records()
	var opening: Dictionary = records.scene_for_runtime_id(1)
	check(not opening.has("error") and opening.value.map_word == 20 and opening.value.enter_script_word == 4,
		"admitted source opening scene is map20 with enter script 4")
	var owner = _owner(package.pal98_sources)
	if owner == null: return
	var state = _fixture(package.pal98_sources)
	var run = _drive(owner, owner.start(state, 1, 4))
	var opening_result: Dictionary = run.result
	check(not opening_result.has("error"), "real opening entry runs to its terminal phase: " + str(opening_result.get("error", "")))
	var kinds: Array = opening_result.effects.map(func(effect): return effect.kind)
	check(kinds.slice(0, 4) == ["party_map_position", "role_map_sprite", "party_direction_frame", "party_composition"],
		"real opening executes 0x0046, 0x0065, 0x0015 and 0x0075 in original order: " + str(kinds))
	check(kinds.has("dialog_globals") and kinds.has("restore_dialog_background") and kinds.has("scene_request"),
		"real opening runs the text globals, the background restore and the scene request")
	check(opening_result.state.globals.requested_scene == 2 and opening_result.state.globals.resource_flags == 12,
		"real opening asks for runtime scene 2 with the original event/EnterScript mask")
	check(opening_result.return_entry == 4, "real opening returns the ByRef entry saved by opcode 0000")
	check(opening_result.effects[0].world_x == 1024 and opening_result.effects[0].viewport_x == 864 and opening_result.effects[0].viewport_y == 912,
		"real opening world (1024,1024) yields viewport (864,912)")
	check(opening_result.effects[1].sprite_word == 193 and opening_result.effects[2].frame_word == 0,
		"real opening writes role0 sprite 193 and frame 0")
	check(opening_result.effects[3].roles == [0], "real opening rebuilds its single-member party from the real argument")
	var opening_requests: Array = run.requests.map(func(request): return request.kind)
	# Real second-scene entry: music, battle music, world position, cross-fade,
	# then the named 0x003C upper-dialog gap.
	var scene2: Dictionary = records.scene_for_runtime_id(2)
	check(not scene2.has("error") and scene2.value.map_word == 12 and scene2.value.enter_script_word > 0,
		"admitted source runtime scene 2 is map12 with a real enter script")
	var scene2_owner = _owner(package.pal98_sources)
	var scene2_state = _fixture(package.pal98_sources, 2)
	var scene2_adapter = EntryHost.new()
	var scene2_cache = Cache.new(); scene2_cache.load_source(package.pal98_graphics, package.pal98_sources)
	var scene2_kernel = Equipment.new()
	scene2_kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
		package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
	check(scene2_adapter.bind(scene2_cache, scene2_kernel, scene2_state.inventory_bytes, [0, 0, 0, 0, 0, 0]),
		"second-scene adapter binds the real owners")
	var scene2_display = DisplayDouble.new(); scene2_adapter.bind_display(scene2_display)
	var scene2_run = _drive_with_host(scene2_owner, scene2_owner.start(scene2_state, 2,
		scene2.value.enter_script_word), scene2_adapter)
	var scene2_result: Dictionary = scene2_run.result
	check(scene2_result.has("error") and (scene2_result.get("diagnostic", {}).has("words")
		or str(scene2_result.get("error", "")).contains("pal98-entry-host")),
		"the second scene's real entry stops at a named command with its source receipt: "
			+ str(scene2_result.get("error", "")))
	var scene2_kinds: Array = scene2_result.effects.map(func(effect): return effect.kind)
	check(scene2_kinds.slice(0, 4) == ["field_music", "battle_music", "party_map_position", "cross_fade"],
		"the second scene runs its reviewed commands in order: " + str(scene2_kinds))
	check(scene2_result.effects[0].track == 31 and scene2_result.effects[0].played == true,
		"0x0043 sets and plays the real field track 31")
	check(scene2_result.effects[1].track == 37, "0x0045 stores the real battle track 37")
	check(scene2_result.effects[2].world_x == 1312 and scene2_result.effects[2].world_y == 288
		and scene2_result.effects[2].viewport_x == 1152 and scene2_result.effects[2].viewport_y == 176,
		"the second scene's 0x0046 applies its real world and viewport words")
	check(scene2_result.effects[3].first == 2 and scene2_result.effects[3].second == 0,
		"0x0073 passes the real cross-fade arguments")
	var scene2_requests: Array = scene2_run.requests.map(func(request): return request.kind)
	check(scene2_requests.has("play_midi") and scene2_requests.has("clear_effective_cross_fade"),
		"the second scene's music and cross-fade reach the host: " + str(scene2_requests))
	check(scene2_kinds.has("dialog_globals") and scene2_kinds.size() >= 5,
		"the second scene's entry advances past its music, position and text commands: " + str(scene2_kinds))
	check(opening_requests.has("load_party_sprites") and opening_requests.has("rebuild_party_equipment"),
		"real opening asks the sprite and equipment owners: " + str(opening_requests))
	check(opening_requests.has("restore_dialog_background") and opening_requests.count("dialogue") >= 5,
		"real opening relays the background restore and the five FFFF dialogues to the host")
	check(opening_result.get("partial") == true and opening_result.unimplemented.size() >= 3,
		"the completed opening still reports its named sub-effect gaps")
	check(opening_requests.has("render_current_map_background") and opening_requests.has("render_scene"),
		"the opening replays the map background and the scene frame through the host")
	check(opening_result.trace.size() >= 16, "real opening executes the whole 16-instruction entry sequence")
	check(opening_requests.count("load_party_sprites") == 1 and opening_requests.count("rebuild_party_equipment") == 1,
		"each party-owner request is answered exactly once")
	# A scene record redirected to a real minimal entry block completes the chain.
	var minimal := -1
	var minimal_increments := true
	for index in range(1, package.pal98_sources.counts().scripts - 1):
		var probe: Dictionary = records.instruction(index)
		if probe.has("error"): continue
		if probe.value.words[0] == 0x0015 and probe.value.words[1] == 0:
			var following: Dictionary = records.instruction(index + 1)
			if not following.has("error") and following.value.words[0] in [0x0000, 0x0001]:
				minimal = index; minimal_increments = following.value.words[0] == 0x0001; break
	check(minimal > 0, "real script pool contains a reviewed 0x0015/return entry block")
	if minimal > 0:
		var storage = Events.new(); storage.load_source(package.pal98_sources)
		var redirected = _fixture(package.pal98_sources)
		redirected.events = storage.source_state()
		redirected.events.scene_records = redirected.events.scene_records.duplicate()
		redirected.events.scene_records.encode_u16(2, minimal)
		var short_owner = _owner(package.pal98_sources)
		var short_result = _drive(short_owner, short_owner.start(redirected, 1, minimal))
		# Opcode 0001 increments the already-advanced entry again; opcode 0000
		# restores the saved entry (the value the invocation started with).
		var expected_entry: int = minimal + 2 if minimal_increments else minimal
		check(not short_result.result.has("error") and short_result.result.return_entry == expected_entry,
			"real minimal entry block completes with the opcode-defined ByRef entry: "
				+ str(short_result.result.get("return_entry", short_result.result.get("error"))) + " vs " + str(expected_entry))
		check(short_result.result.effects.size() == 1 and short_result.result.effects[0].kind == "party_direction_frame",
			"real minimal entry block executes the reviewed 0x0015 case")
	# Resource chain integration: T212 requests this owner and adopts its ByRef entry.
	var driver = Reload.new()
	check(driver.load_source(package.pal98_sources, package.pal98_graphics), "resource reload binds the admitted sources and graphics")
	var reload_state = _fixture(package.pal98_sources)
	var inventory = PackedByteArray(); inventory.resize(1536)
	reload_state.inventory_bytes = inventory
	reload_state.globals.resource_flags = 29
	reload_state.globals.save_slot = 0
	var cache = Cache.new(); cache.load_source(package.pal98_graphics, package.pal98_sources)
	var step: Dictionary = driver.start(reload_state, cache)
	for index in range(64):
		if step.has("request") and step.request.kind == "enter_script": break
		if not step.has("request"): break
		step = driver.resume(step.request.id, {"completed": true})
	check(step.has("request") and step.request.kind == "enter_script" and step.request.entry == 4,
		"T212 requests the real scene EnterScript 4")
	if step.has("request"):
		var request_state: Dictionary = step.request.state.duplicate(true)
		request_state.dialogue = _context(); request_state.rng = Random.create(0x12345)
		var chained = _owner(package.pal98_sources)
		var host_cache = Cache.new()
		host_cache.load_source(package.pal98_graphics, package.pal98_sources)
		var host_kernel = Equipment.new()
		host_kernel.read_tables(package.pal98_sources.copy_chunk("data", 3),
			package.pal98_sources.copy_chunk("sss", 2), package.pal98_sources.copy_chunk("sss", 4))
		var adapter = EntryHost.new()
		check(adapter.bind(host_cache, host_kernel, request_state.inventory_bytes, [0, 0, 0, 0, 0, 0]),
			"real owner adapter binds the sprite cache, equipment kernel and inventory")
		var display = DisplayDouble.new(); adapter.bind_display(display)
		var dialogue_host = DialogueHost.new()
		check(dialogue_host.bind(package.pal98_sources), "dialogue host binds the admitted text encoding")
		dialogue_host.set_input_policy([2], 2)
		var chained_run = _drive_with_host(chained, chained.start(request_state, step.request.scene_id,
			step.request.entry, step.request.event_id), adapter, dialogue_host)
		var chained_result: Dictionary = chained_run.result
		var answers: Array = adapter.answered()
		var sprite_answer: Dictionary = {}
		for answer in answers:
			if answer.get("kind") == "load_party_sprites": sprite_answer = answer
		check(not sprite_answer.is_empty() and sprite_answer.used_words > 0
			and sprite_answer.role_sprite_ids[0] == 193 and sprite_answer.loaded_mgo_chunks == [193],
			"the real sprite cache loads role 0's reviewed map sprite 193: " + str(answers))
		check(chained_result.state.party_records[0].cache_word_offset == 0
			and str(chained_result.state.party_records[0].get("role_id")) == "0",
			"the loaded party sprite offset reaches the commanding state")
		var usage_clear: bool = true
		for slot in range(256):
			if chained_result.state.inventory_bytes.decode_u16(slot * 6 + 4) != 0: usage_clear = false
		check(usage_clear, "the real equipment kernel clears all 256 inventory usage fields")
		check(display.requests.has("render_current_map_background") or display.requests.has("render_scene"),
			"the display double records the render requests the chain emitted: " + str(display.requests))
		var drawn: Array = dialogue_host.texts()
		var receipt_kinds: Array = dialogue_host.receipts().map(func(receipt): return receipt.kind)
		check(drawn.size() >= 5, "the dialogue host composes the opening's real message text: "
			+ str(drawn.size()) + " of " + str(receipt_kinds))
		var codec = preload("res://src/native_pal98_text_codec.gd").new()
		codec.open(package.pal98_sources.metadata().text_encoding)
		# The title path draws message 1 as one whole string, so its composed text
		# can be compared with the decoded source bytes directly.
		var whole: Dictionary = {}
		for receipt in dialogue_host.receipts():
			if receipt.kind == "draw_string": whole = receipt
		var title = records.message_bytes(1)
		check(not title.has("error"), "the source title message is readable")
		var expected: Dictionary = codec.decode(title.value.bytes)
		check(not expected.has("error") and not whole.is_empty() and whole.text == expected.text,
			"the whole-string draw matches the decoded source title message")
		var glyph_receipts: Array = dialogue_host.receipts().filter(func(receipt): return receipt.kind == "draw_glyph")
		check(glyph_receipts.size() >= 40 and glyph_receipts[0].codepoints.size() >= 1,
			"the typewriter path emits per-glyph draws with decoded codepoints: " + str(glyph_receipts.size()))
		check(dialogue_host.receipts().size() >= drawn.size() and dialogue_host.ticks() >= 0,
			"the dialogue host keeps a receipt per composed run")
		check(not chained_result.has("error") and chained_result.state.globals.requested_scene == 2,
			"T212 request is answered by the real entry script up to its scene request")
		check(chained_result.effects.size() >= 4 and chained_result.effects[0].world_x == 1024
			and chained_result.effects[3].kind == "party_composition",
			"chained entry still applies the real opening position and party rebuild")
		var restarted = driver.resume(step.request.id, {"state": chained_result.state,
			"return_entry": chained_result.return_entry})
		check(restarted.has("error") and str(restarted.error).contains("Unknown") and restarted.trace.count("entry") == 2,
			"the real scene request restarts the T212 chain to scene 2 and stops on the documented sprite-cache Unknown backing: "
				+ str(restarted.get("error", "")))
		check(restarted.trace.has("commit_events") and restarted.trace.has("load_events"),
			"the restart commits the previous scene's events and loads the new scene's event backing")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	package = Package.new()
	if not package.load_package(args[0]):
		push_error("enter script package rejected: " + str(package.error)); quit(2); return
	if package.pal98_sources == null or package.pal98_graphics == null:
		push_error("enter script needs an admitted source and graphics component"); quit(2); return
	_synthetic_checks()
	_real_checks()
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks,
		"coverage": coverage,
		"host_effects": "explicit acknowledgements only", "original_gameplay": false}, "\t")); file.close()
	print("EnterScript owner: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
