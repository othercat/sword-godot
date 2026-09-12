# SPDX-License-Identifier: MIT
extends SceneTree
## Synthetic T258 driver probes. Every effect is an explicit host
## acknowledgement; no original Session, save or gameplay is activated.
const Trigger = preload("res://src/native_pal98_trigger.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var failed: int = 0

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

func _source(events_count: int, boundaries: Array, program: Array, messages: Array = []):
	var events: PackedByteArray = _zero(events_count * 32)
	var scenes: PackedByteArray = _zero(boundaries.size() * 8)
	for index in range(boundaries.size()): scenes.encode_u16(index * 8 + 6, boundaries[index])
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
		"fingerprint": identity, "files": entries, "label": "Synthetic trigger", "license": "CC0-1.0", "redistributable": true,
		"provenance": {"status": "synthetic"}}, files, Schema.new()): return null
	return source

func _context(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"local_x": 101, "local_y": 102, "title_x": 12, "title_y": 8, "origin_x": 44, "origin_y": 26, "mode": 1,
		"line_count": 0, "boxed_count": 0, "draw_x": 201, "draw_y": 202, "icon": 2, "skip_word": 0, "delay_units": 1, "input_action": 99,
		"capture_gate": 1, "restore_gate": 0, "colours": [79, 45, 26, 141], "timer_counter": 0}
	result.merge(overrides, true); return result

func _state(source, scene_id: int = 0, seed: int = 0x12345, dialogue: Dictionary = {}, globals: Dictionary = {}) -> Dictionary:
	var storage = Events.new()
	if not storage.load_source(source): return {}
	var events: Dictionary = storage.source_state()
	if scene_id > 0: events = storage.load_scene_events(events, scene_id).state
	return {"globals": globals, "events": events, "dialogue": _context(dialogue), "rng": Random.create(seed)}

func _dialogue_event(effect: Dictionary) -> Dictionary:
	match effect.get("kind"):
		"capture_background": return {"kind": "captured"}
		"restore_background": return {"kind": "restored"}
		"draw_dialogue_box": return {"kind": "box_drawn"}
		"draw_dialogue_icon", "draw_glyph", "draw_string": return {"kind": "drawn"}
		"wait": return {"kind": "tick"}
	return {"kind": "input", "action": 2}

func _kinds(requests: Array) -> Array:
	return requests.map(func(request): return request.kind)

func _drive(trigger, first: Dictionary, script: Dictionary = {}) -> Dictionary:
	var result: Dictionary = first; var requests: Array = []
	for step in range(4096):
		if result.has("error") or result.has("state"): return {"result": result, "requests": requests}
		var request: Dictionary = result.request; requests.append(request)
		var response: Dictionary
		match request.kind:
			"dialogue": response = {"event": _dialogue_event(request.effect)}
			"execute_command": response = {"state": request.state, "entry": script.get("command_entry", request.entry), "event_id": request.event_id}
			"yes_no": response = {"state": request.state, "result": script.yes_no.pop_front()}
			"battle": response = {"state": request.state, "result": script.battle.pop_front()}
			_: response = {"state": request.state, "completed": true}
		result = trigger.resume(request.id, response)
	return {"result": {"error": "trigger driver budget exceeded"}, "requests": requests}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.dir_exists_absolute(args[0]) or FileAccess.file_exists(args[0]): quit(2); return
	DirAccess.make_dir_recursive_absolute(args[0])
	_returns_and_wrap()
	_command_gate()
	_yes_no()
	_idle()
	_recursion()
	_random()
	_message()
	_redraw_and_battle()
	_frames()
	_isolation()
	var file = FileAccess.open(args[0].path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks,
		"host_side_effects_acknowledged_only": true, "original_trigger_executed": false, "original_gameplay": false}, "\t")); file.close()
	print("PAL98 trigger: ", checks.size(), " checks; ", failed, " failed")
	quit(0 if failed == 0 else 1)

func _returns_and_wrap() -> void:
	# 0000 returns the saved entry; 0008 replaces it with current+1; 0001 returns next.
	var source = _source(0, [0, 0], [[0, 0, 0, 0], [1, 0, 0, 0]])
	var trigger = Trigger.new(); check(trigger.load_source(source), "trigger source admitted")
	var run: Dictionary = _drive(trigger, trigger.start(_state(source), 1, 1))
	check(not run.result.has("error") and run.result.return_entry == 1 and run.requests.is_empty(), "0000 returns saved entry and stops without effects")
	run = _drive(trigger, trigger.start(_state(source), 2, 1))
	check(run.result.return_entry == 3 and trigger.error.is_empty(), "0001 returns incremented entry and stops")
	source = _source(0, [0, 0], [[8, 0, 0, 0], [0, 0, 0, 0]])
	check(trigger.load_source(source), "trigger source reload after completion")
	run = _drive(trigger, trigger.start(_state(source), 1, 1))
	check(run.result.return_entry == 2 and _kinds(run.requests) == ["execute_command"], "0008 saves current+1 for the later 0000 return")
	check(run.result.state.globals.trigger_success_word == -1, "T258 entry sets G0302 success word to -1")
	# A host-modified T240 entry of 65535 increments to zero; the loop head writes it back and exits.
	source = _source(0, [0, 0], [[11, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source), 1, 1), {"command_entry": 65535})
	check(run.result.return_entry == 0, "U2 increment wrap to zero exits and writes back zero")
	run = _drive(trigger, trigger.start(_state(source), 3, 1))
	check(not run.result.has("error") and run.result.return_entry == 3 and run.requests.is_empty(), "entry beyond script maximum exits immediately")
	run = _drive(trigger, trigger.start(_state(source), 0, 1))
	check(run.result.return_entry == 0 and run.requests.is_empty(), "zero entry exits immediately")

func _command_gate() -> void:
	# Every continuing path reaches the T240 request, including FFFF and local controls.
	# T258 entry already zeroed both line counters, so the clear split is observed
	# through a line left pending by an FFFF message.
	var source = _source(0, [0, 0], [[0xffff, 0, 0, 0], [0x8000, 0, 0, 0], [11, 0, 0, 0], [1, 0, 0, 0]], ["A".to_ascii_buffer()])
	var trigger = Trigger.new(); trigger.load_source(source)
	var run: Dictionary = _drive(trigger, trigger.start(_state(source), 1, 1))
	var commands: Array = run.requests.filter(func(request): return request.kind == "execute_command")
	check(commands.size() == 3 and run.result.return_entry == 5, "FFFF, negative command and >000A all reach the T240 request")
	check(commands[0].words[0] == 0xffff and commands[0].entry == 1, "T240 request carries the four record words and the current entry")
	check(commands[0].state.dialogue.line_count == 1 and commands[1].state.dialogue.line_count == 1, "FFFF and negative commands enter T240 without clearing")
	check(commands[1].words[0] == 0x8000, "u16 >= 32768 non-FFFF commands are signed <= 10 and skip the clear")
	check(commands[2].words[0] == 11 and commands[2].state.dialogue.line_count == 0, ">000A clears dialog state before T240")
	check(_kinds(run.requests) == ["dialogue", "dialogue", "dialogue", "execute_command", "execute_command", "dialogue", "dialogue", "execute_command"],
		"the >000A clear is the real ClearText chain between the two command gates")

func _yes_no() -> void:
	# 000A clears both line counters once, repeats menu19 until non-negative; 0 jumps to Arg0, 1 continues.
	var source = _source(0, [0, 0], [[10, 4, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0], [1, 0, 0, 0]])
	var trigger = Trigger.new(); trigger.load_source(source)
	var run: Dictionary = _drive(trigger, trigger.start(_state(source, 0, 0x12345, {"line_count": 3, "boxed_count": 2}), 1, 1), {"yes_no": [-1, 0]})
	check(_kinds(run.requests) == ["yes_no", "yes_no"], "negative menu result repeats the menu without another instruction")
	check(run.requests[0].menu_id == 19 and run.requests[0].initial_selection == 0, "menu19 with zero initial selection")
	check(run.requests[0].state.dialogue.line_count == 0 and run.requests[0].state.dialogue.boxed_count == 0, "000A clears both line counters once before the menu")
	check(run.result.return_entry == 5, "choice 0 jumps to Arg0 and continues there")
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source), 1, 1), {"yes_no": [1]})
	check(_kinds(run.requests) == ["yes_no", "execute_command"] and run.result.return_entry == 3, "choice 1 continues through T240 and the next entry")

func _idle_counter(source, events_state: Dictionary, event_id: int) -> int:
	var storage = Events.new(); storage.load_source(source)
	var row: Dictionary = storage.event_record(events_state, event_id)
	return _signed(row.value.decode_u16(24)) if not row.has("error") else -99999

static func _signed(value: int) -> int:
	return value if value < 32768 else value - 65536

func _idle() -> void:
	# 0002 jumps cross-call with the +24 TriggerIdleFrame count; 0003 jumps in-call.
	var source = _source(4, [0, 4], [[2, 4, 2, 0], [1, 0, 0, 0], [0, 0, 0, 0], [1, 0, 0, 0]])
	var trigger = Trigger.new(); trigger.load_source(source)
	var run: Dictionary = _drive(trigger, trigger.start(_state(source, 1), 1, 1))
	check(run.result.return_entry == 4 and run.requests.is_empty(), "0002 jump exits the invocation at the target")
	check(_idle_counter(source, run.result.state.events, 1) == 1, "0002 stores the incremented idle count on jump")
	run = _drive(trigger, trigger.start(run.result.state, 1, 1))
	check(run.result.return_entry == 3 and _kinds(run.requests) == ["execute_command"], "0002 no-jump resets the count and continues through T240")
	check(_idle_counter(source, run.result.state.events, 1) == 0, "0002 reaching the limit resets the idle count to zero")
	source = _source(4, [0, 4], [[2, 3, 0, 0], [1, 0, 0, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 1), 1, 1))
	check(run.result.return_entry == 3 and _idle_counter(source, run.result.state.events, 1) == 0, "zero-target 0002 yields without touching the idle count")
	source = _source(4, [0, 4], [[3, 1, 3, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 1), 1, 1))
	check(run.result.return_entry == 3 and run.result.steps == 4 and _kinds(run.requests) == ["execute_command"],
		"0003 jumps within the same invocation until the count reaches the limit")
	check(_idle_counter(source, run.result.state.events, 1) == 0, "0003 also resets the count on the final no-jump")
	source = _source(4, [0, 4], [[3, 2, 0, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 1), 1, 1))
	check(run.result.return_entry == 3 and run.result.steps == 2 and run.requests.is_empty(), "zero-target 0003 restarts in-call without T240")
	trigger.load_source(source)
	var bounded: Dictionary = _drive(trigger, trigger.start(_state(source, 1), 1, 1, 1))
	check(bounded.result.has("error") and str(bounded.result.error).contains("budget"), "instruction budget is an explicit bounded diagnostic")

func _recursion() -> void:
	# 0004: positive Arg1 converts through the scene record base; otherwise the current context recurses.
	var source = _source(7, [3, 7], [[4, 2, 0, 0], [8, 0, 0, 0], [1, 0, 0, 0]])
	var trigger = Trigger.new(); trigger.load_source(source)
	var state: Dictionary = _state(source, 1, 0x12345, {}, {"current_scene": 1})
	var run: Dictionary = _drive(trigger, trigger.start(state, 1, 1))
	check(_kinds(run.requests) == ["execute_command", "execute_command", "execute_command"], "0004 recursion and the parent afterwards continue through T240")
	check(run.requests[0].event_id == 1 and run.requests[0].entry == 2, "non-positive Arg1 keeps the current event context")
	check(run.requests[1].words == [4, 4, 0, 0], "child ByRef entry return writes back the parent record Arg0 local")
	check(run.result.return_entry == 4 and run.result.steps == 5, "recursion returns into the parent loop with one increment")
	source = _source(7, [3, 7], [[4, 2, 5, 0], [8, 0, 0, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 1, 0x12345, {}, {"current_scene": 1}), 1, 1))
	check(run.requests[0].event_id == 2, "positive Arg1 converts through the scene event base index")
	source = _source(7, [3, 7], [[4, 2, 99, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 1, 0x12345, {}, {"current_scene": 1}), 1, 1))
	check(run.result.return_entry == 3 and run.result.steps == 2 and _kinds(run.requests) == ["execute_command"],
		"out-of-range converted event skips the recursion and continues")
	source = _source(7, [3, 7], [[4, 1, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 1, 0x12345, {}, {"current_scene": 1}), 1, 1))
	check(run.result.has("error") and str(run.result.error).contains("recursion budget"), "unbounded self recursion is an explicit depth diagnostic")
	source = _source(7, [3, 7], [[4, 2, 5, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 1), 1, 1))
	check(run.result.has("error") and str(run.result.error).contains("current scene"), "positive Arg1 without a known current scene diagnoses")

func _random() -> void:
	# 0006: strict signedI2(Arg0) < CSng(Rnd*100), consumed before the target is read.
	# Seed 251392 yields Single(0.43) whose Single product is exactly 43.0.
	var seed: int = 251392; var stepped: int = 7214202
	var value: float = Random.ordinary_next(Random.create(seed), "ordinary").value
	var bytes = PackedByteArray(); bytes.resize(4); bytes.encode_float(0, value * 100.0)
	check(bytes.decode_float(0) == 43.0, "fixed seed reproduces the exact-integer Single product")
	var source = _source(0, [0, 0], [[6, 43, 3, 0], [1, 0, 0, 0], [1, 0, 0, 0]])
	var trigger = Trigger.new(); trigger.load_source(source)
	var run: Dictionary = _drive(trigger, trigger.start(_state(source, 0, seed), 1, 1))
	check(run.result.return_entry == 3 and _kinds(run.requests) == ["execute_command"], "threshold equal to the product fails the strict < gate")
	check(run.result.state.rng.live_seed == stepped and run.result.state.rng.mirror_seed == stepped, "the gate consumes exactly one two-step Rnd")
	source = _source(0, [0, 0], [[6, 42, 3, 0], [1, 0, 0, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 0, seed), 1, 1))
	check(run.result.return_entry == 4 and run.requests.is_empty(), "one below the product takes the in-call jump without T240")
	source = _source(0, [0, 0], [[6, 42, 0, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 0, seed), 1, 1))
	check(run.result.return_entry == 1 and run.result.state.rng.live_seed == stepped, "taken zero target exits with the entry unchanged and Rnd still consumed")
	source = _source(0, [0, 0], [[6, 0xA68D, 0, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 0, seed), 1, 1))
	check(run.result.return_entry == 1, "signed negative threshold is always below the nonnegative product")

func _message() -> void:
	# FFFF composes the dialogue caller chain, then continues through T240.
	var source = _source(0, [0, 0], [[0xffff, 0, 0, 0], [1, 0, 0, 0]], ["A".to_ascii_buffer()])
	var trigger = Trigger.new(); trigger.load_source(source)
	var run: Dictionary = _drive(trigger, trigger.start(_state(source, 0, 0x12345, {"capture_gate": 0}), 1, 1))
	var kinds: Array = _kinds(run.requests)
	check(kinds[0] == "dialogue" and run.requests[0].effect.kind == "capture_background", "first-line message captures the background")
	check("execute_command" in kinds and run.result.return_entry == 3, "message completion continues through T240 to the next entry")
	check(run.requests[0].state.dialogue.colours == [79, 45, 26, 141] and run.requests[0].state.dialogue.mode == 1
		and run.requests[0].state.dialogue.local_x == 44 and run.requests[0].state.dialogue.local_y == 26,
		"T258 entry colours, mode and text origin reach the message chain")
	check(run.requests[0].state.globals.trigger_success_word == -1, "G0302 -1 is visible to effects")
	check(run.result.state.dialogue.line_count == 0, "the exit ClearText consumed the drawn line")

func _redraw_and_battle() -> void:
	# 0005: clear, FBP restore split, G02EE mode, Arg1 default 1, optional rebuild, render, reset.
	var source = _source(0, [0, 0], [[5, 2, 0, 1], [1, 0, 0, 0]])
	var trigger = Trigger.new(); trigger.load_source(source)
	var run: Dictionary = _drive(trigger, trigger.start(_state(source, 0, 0x12345, {"capture_gate": 0}), 1, 1))
	check(_kinds(run.requests) == ["sync_party_for_redraw", "render_scene", "execute_command"], "non-FBP 0005 rebuilds party frames, renders, then reaches T240")
	check(run.requests[0].state.globals.redraw_mode == 2 and run.requests[1].mode == 1, "G02EE holds Arg0 during the render with Arg1 defaulted to one")
	check(run.requests[2].state.globals.redraw_mode == 0 and run.requests[2].words == [5, 2, 1, 1], "render completion resets G02EE; T240 sees the defaulted Arg1")
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source, 0, 0x12345, {"capture_gate": 1}), 1, 1))
	check(_kinds(run.requests) == ["restore_background", "execute_command"], "FBP 0005 restores the background instead of rendering")
	check(run.requests[1].state.dialogue.capture_gate == 0 and run.requests[1].state.dialogue.restore_gate == 0, "restore acknowledgement resets both dialog gates")
	# 0007: clear, battle, then result 1/2 jump to Arg1/Arg2; no T240 on this path.
	source = _source(0, [0, 0], [[7, 5, 4, 5], [1, 0, 0, 0], [0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source), 1, 1), {"battle": [1]})
	check(_kinds(run.requests) == ["battle"] and run.result.return_entry == 5, "battle result 1 jumps to Arg1 past the increment")
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source), 1, 1), {"battle": [2]})
	check(run.result.return_entry == 1, "battle result 2 jumps to Arg2 whose 0000 returns the saved entry")
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source), 1, 1), {"battle": [0]})
	check(run.result.return_entry == 3 and run.requests[0].enemy_team == 5 and run.requests[0].argument == 5, "other battle results continue at the incremented entry")

func _frames() -> void:
	# 0009: clear, Arg0 default 1, per-frame optional movement/sync then main frame and render.
	var source = _source(0, [0, 0], [[9, 2, 3, 1], [1, 0, 0, 0]])
	var trigger = Trigger.new(); trigger.load_source(source)
	var run: Dictionary = _drive(trigger, trigger.start(_state(source), 1, 1))
	check(_kinds(run.requests) == ["advance_party_movement", "sync_party_frames", "main_frame", "render_scene",
		"advance_party_movement", "sync_party_frames", "main_frame", "render_scene", "execute_command"], "two full real frames before T240")
	check(run.requests[2].mode == 3 and run.requests[3].mode == 1, "main frame uses Arg1; the render uses one")
	source = _source(0, [0, 0], [[9, 0, 2, 0], [1, 0, 0, 0]])
	trigger.load_source(source)
	run = _drive(trigger, trigger.start(_state(source), 1, 1))
	check(_kinds(run.requests) == ["main_frame", "render_scene", "execute_command"] and run.requests[2].words[1] == 1,
		"zero Arg0 defaults to one frame and zero Arg2 skips movement; T240 sees the defaulted Arg0")

func _isolation() -> void:
	var source = _source(0, [0, 0], [[11, 0, 0, 0], [1, 0, 0, 0]])
	var trigger = Trigger.new(); trigger.load_source(source)
	var state: Dictionary = _state(source)
	var first: Dictionary = trigger.start(state, 1, 1)
	var pending: Dictionary = first.request
	check(trigger.resume("bogus-id", {"state": pending.state, "entry": 1, "event_id": 1}).has("error"), "stale request id is rejected")
	var run: Dictionary = _drive(trigger, first)
	check(run.result.return_entry == 3, "the live request still completes after the stale attempt")
	first = trigger.start(state, 1, 1)
	trigger.cancel()
	check(trigger.resume(first.request.id, {"state": first.request.state, "entry": 1, "event_id": 1}).has("error"), "cancel invalidates the pending request")
	run = _drive(trigger, trigger.start(state, 1, 1))
	check(run.result.return_entry == 3, "a fresh start after cancel is fully isolated")
	first = trigger.start(state, 1, 1)
	var failed_run: Dictionary = trigger.resume(first.request.id, {"error": "host blew up"})
	check(str(failed_run.error).contains("host failed") and not trigger.error.is_empty(), "host errors fail the trigger with diagnostics")
	check(trigger.start(state, 1, 1).has("request"), "failed trigger accepts a fresh start")
	check(trigger.start(state, 1, 1).has("error"), "a second start while active is rejected")
	trigger.cancel()
	run = _drive(trigger, trigger.start(state, 1, 1))
	run.result.state.globals.trigger_success_word = 99
	check(state.globals.is_empty() and not run.result.state.globals.is_empty(), "input state is not mutated and the result is detached")
	var bad: Dictionary = trigger.start({"globals": {}}, 1, 1)
	check(bad.has("error"), "incomplete state is rejected with an explicit error")
	var unloaded = Trigger.new()
	check(unloaded.start(_state(source), 1, 1).has("error") and not unloaded.load_source(null), "unloaded or invalid sources are rejected")
