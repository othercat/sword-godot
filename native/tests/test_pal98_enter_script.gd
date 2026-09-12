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
var checks: Array = []
var failed: int = 0
var package

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
func _source(boundaries: Array, enter_words: Array, program: Array, messages: Array = []):
	var events: PackedByteArray = _zero(32)
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
			"member_last": 0, "follower_count": 0},
		"events": events.source_state(), "dialogue": _context(), "rng": Random.create(0x12345),
		"equipment": equipment.initial_state([0]),
		"party_records": [{"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 3}]}

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
	for step in range(4096):
		if not result.has("request"): return {"result": result, "requests": requests}
		var request: Dictionary = result.request; requests.append(request)
		if request.kind == "dialogue": result = owner.resume(request.id, {"event": _dialogue_event(request.effect)})
		elif request.has("state"): result = owner.resume(request.id, {"state": request.state, "completed": true})
		else: result = owner.resume(request.id, {"completed": true})
	return {"result": {"error": "enter script driver budget exceeded"}, "requests": requests}

func _owner(source) -> Variant:
	var owner = Enter.new()
	if not owner.load_source(source): push_error("enter owner load failed: " + owner.error); return null
	return owner

func _synthetic_checks() -> void:
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
	check(result.effects[1].sprite_word == 193 and result.effects[1].role == 0, "0x0065 writes role0 map sprite 193")
	check(result.effects[2].frame_word == 0 and result.effects[2].direction_word == 0, "0x0015 writes direction 0 and frame 0")
	check(result.effects[3].roles == [0] and result.effects[3].member_last == 0,
		"0x0075 rebuilds the single-member party from argument 1")
	check(result.get("partial") == true and result.unimplemented.size() == 4,
		"the run reports its named sub-effect gaps instead of a full success")
	check(str(result.unimplemented[0].sub_effect).contains("G04AC") and str(result.unimplemented[3].sub_effect).contains("T230"),
		"named gaps cover the 0x0046 sub-effects and the T230 member sync")
	var owner_kinds: Array = run.requests.filter(func(request): return request.has("procedure")).map(func(request): return request.kind)
	check(owner_kinds == ["load_party_sprites", "rebuild_party_equipment"],
		"0x0075 asks the sprite and equipment owners before the trigger resumes")
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
	check(slot_result.has("error") and str(slot_result.error).contains("party record"), "0x0015 refuses an unknown party slot")
	# 0x0059 valid changed scene and unchanged scene.
	var scene_program: Array = [[0x0059, 0x0002, 0x0000, 0x0000], [0x0001, 0, 0, 0]]
	var scene_source = _source([0, 0, 0], [1, 0, 0], scene_program)
	var scene_owner = _owner(scene_source)
	var scene_state = _fixture(scene_source)
	var scene_result = _drive(scene_owner, scene_owner.start(scene_state, 1, 1))
	check(not scene_result.result.has("error") and scene_result.result.state.globals.requested_scene == 2
		and scene_result.result.state.globals.resource_flags == 12, "0x0059 requests scene 2 and sets the original event/EnterScript mask")
	check(scene_result.result.unimplemented.size() == 1 and str(scene_result.result.unimplemented[0].sub_effect).contains("G028A"),
		"0x0059 reports the unnamed G028A word instead of guessing")
	check(scene_result.result.get("partial") == true, "named sub-effect gaps mark the terminal result partial")
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
	var reload_result = reload_owner.start(_fixture(reload_source), 1, 1)
	check(reload_result.has("error") and str(reload_result.error).contains("sprite reload"), "0x0065 refuses the outside-battle reload it cannot perform")
	# 0x0075 party rebuild: multi-member, default role and out-of-range argument.
	var multi_program: Array = [[0x0075, 0x0002, 0x0003, 0x0000], [0x0001, 0, 0, 0]]
	var multi_source = _source([0, 0], [1, 0], multi_program)
	var multi_owner = _owner(multi_source)
	var multi_state = _fixture(multi_source)
	while multi_state.party_records.size() < 3:
		multi_state.party_records.append({"role_id": 0, "screen_x": 160, "screen_y": 112, "current_frame": 0})
	multi_state.equipment.party_roles = [0, 1, 2]
	var multi_result = _drive(multi_owner, multi_owner.start(multi_state, 1, 1))
	check(not multi_result.result.has("error") and multi_result.result.effects[0].roles == [1, 2]
		and multi_result.result.effects[0].member_last == 1 and multi_result.result.effects[0].dropped_slots == 1,
		"0x0075 rebuilds a two-member party and drops the unused slot")
	check(multi_result.result.state.equipment.party_roles == [1, 2]
		and multi_result.result.state.party_records.size() == 2,
		"the rebuilt composition reaches both the party records and the equipment roles")
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

func _real_checks() -> void:
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
	check(opening_requests.has("load_party_sprites") and opening_requests.has("rebuild_party_equipment"),
		"real opening asks the sprite and equipment owners: " + str(opening_requests))
	check(opening_requests.has("restore_dialog_background") and opening_requests.count("dialogue") >= 5,
		"real opening relays the background restore and the five FFFF dialogues to the host")
	check(opening_result.get("partial") == true and opening_result.unimplemented.size() >= 5,
		"the completed opening still reports its named sub-effect gaps")
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
		var chained_run = _drive(chained, chained.start(request_state, step.request.scene_id, step.request.entry, step.request.event_id))
		var chained_result: Dictionary = chained_run.result
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
		"host_effects": "explicit acknowledgements only", "original_gameplay": false}, "\t")); file.close()
	print("EnterScript owner: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
