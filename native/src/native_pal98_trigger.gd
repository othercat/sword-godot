# SPDX-License-Identifier: MIT
extends RefCounted
## T258 control flow over admitted records. Effects belong to explicit hosts.
## This driver is not a public save format or an ordinary Session activation.
const Dialogue = preload("res://src/native_pal98_dialogue_caller.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Random = preload("res://src/native_pal98_fixed_random.gd")
const MAX_STEPS = 65536
const MAX_DEPTH = 64
var error: String = ""
var _records
var _events
var _identity: String = ""
var _last: int = -1
var _state: Dictionary = {}
var _frames: Array = []
var _trace: Array = []
var _phase: String = "idle"
var _pending: Dictionary = {}
var _child: Dictionary = {}
var _after_dialogue: String = ""
var _generation: int = 0
var _serial: int = 0
var _steps: int = 0
var _budget: int = MAX_STEPS

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _u2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 65535

static func _signed(value: int) -> int:
	return value if value < 32768 else value - 65536

static func _next(value: int) -> int:
	return (value + 1) & 65535

func load_source(source) -> bool:
	if _phase not in ["idle", "complete", "failed"]: error = "trigger active"; return false
	if source == null or source.metadata().is_empty(): error = "admitted trigger source required"; return false
	var records = source.open_records(); var storage = Events.new()
	if records == null or not storage.load_source(source): error = "trigger tables unavailable"; return false
	var count: int = source.counts().scripts
	if count < 1 or count > 65536: error = "trigger script table outside U2 range"; return false
	_records = records; _events = storage; _identity = source.metadata().fingerprint; _last = count - 1
	error = ""; return true

func _state_issue(state: Dictionary) -> String:
	for key in ["globals", "events", "dialogue", "rng"]:
		if not state.get(key) is Dictionary: return "trigger requires explicit " + key
	var issue: String = _events.validate_state(state.events)
	if not issue.is_empty(): return issue
	if Dialogue.enter_trigger_context(state.dialogue).has("error"): return "invalid trigger dialogue context"
	return Random.validate(state.rng)

func start(state: Dictionary, entry, event_id, step_budget: int = MAX_STEPS) -> Dictionary:
	if _phase not in ["idle", "complete", "failed"]: return {"error":"trigger already active"}
	if _identity.is_empty(): return {"error":"trigger source unavailable"}
	if not _u2(entry) or not _i2(event_id) or step_budget < 1 or step_budget > MAX_STEPS:
		return {"error":"trigger requires U2 entry, I2 event context and bounded instruction budget"}
	var issue = _state_issue(state)
	if not issue.is_empty(): return {"error":issue}
	_state = state.duplicate(true); _frames = []; _trace = []; _pending = {}; _child = {}
	_steps = 0; _budget = step_budget; _serial = 0; _generation += 1
	_enter(entry, event_id); return _advance()

func cancel() -> void:
	_generation += 1; _phase = "idle"; _pending = {}; _child = {}; _frames = []; _state = {}; _trace = []

func _enter(entry: int, event_id: int) -> void:
	_frames.append({"pc":entry,"saved":entry,"event_id":event_id,"words":[],"receipt":{}})
	_state.globals.trigger_success_word = -1
	_state.dialogue = Dialogue.enter_trigger_context(_state.dialogue).context
	_phase = "fetch"

func _fail(message: String) -> Dictionary:
	error = message
	var diagnostic: Dictionary = {"source_fingerprint":_identity,"phase":_phase,"steps":_steps,"depth":_frames.size()}
	if not _frames.is_empty():
		var frame: Dictionary = _frames.back()
		diagnostic.merge({"pc":frame.pc,"event_id":frame.event_id,"instruction":frame.receipt.duplicate(true),"words":frame.words.duplicate()})
	_phase = "failed"; _pending = {}; _child = {}; _state = {}; _frames = []
	return {"error":"pal98-trigger: " + message,"diagnostic":diagnostic,"trace":_trace.duplicate(true)}

func _request(kind: String, details: Dictionary = {}) -> Dictionary:
	_serial += 1
	_pending = {"id":"%s:%s:%s" % [get_instance_id(),_generation,_serial],"kind":kind,
		"source_fingerprint":_identity,"state":_state.duplicate(true),"pc":_frames.back().pc,"event_id":_frames.back().event_id}
	_pending.merge(details, true)
	return {"request":_pending.duplicate(true),"steps":_steps}

func _dialogue(operation: String, after: String) -> Dictionary:
	_after_dialogue = after; _phase = "dialogue"
	var result: Dictionary = Dialogue.begin_instruction(_records,_frames.back().pc,_state.dialogue) if operation == "message" else Dialogue.begin_clear(_records,_state.dialogue)
	return _dialogue_result(result)

func _dialogue_result(result: Dictionary) -> Dictionary:
	if result.has("error"): return _fail(str(result))
	_child = result.state
	_state.dialogue = _child.context.duplicate(true)
	if result.request.kind == "return":
		_child = {}; _phase = _after_dialogue; return {}
	return _request("dialogue", {"effect":result.request,"dialogue_source":result.get("source",{})})

func _accept_state(response: Dictionary) -> String:
	if not response.get("state") is Dictionary: return "host must return the source-bound candidate state"
	var issue = _state_issue(response.state)
	if not issue.is_empty(): return issue
	if not _i2(response.state.globals.get("trigger_success_word")): return "host lost trigger success word"
	_state = response.state.duplicate(true); return ""

func resume(request_id: String, response: Dictionary) -> Dictionary:
	if _pending.is_empty() or _pending.id != request_id: return {"error":"stale or absent trigger request"}
	if response.has("error"): return _fail("host failed: " + str(response.error))
	var kind: String = _pending.kind
	var frame: Dictionary = _frames.back()
	if kind == "dialogue":
		if response.size() != 1 or not response.get("event") is Dictionary: return _fail("dialogue requires one explicit event")
		var result = _dialogue_result(Dialogue.step(_records,_child,response.event))
		if not result.is_empty(): return result
	else:
		var issue = _accept_state(response)
		if not issue.is_empty(): return _fail(issue)
		match kind:
			"execute_command":
				if not _u2(response.get("entry")) or not _i2(response.get("event_id")):
					return _fail("command must return its ByRef U2 entry and I2 event context")
				frame.pc = _next(response.entry); frame.event_id = response.event_id; _phase = "fetch"
			"battle":
				if not _i2(response.get("result")): return _fail("battle requires signed result")
				frame.pc = _next(frame.pc)
				if response.result == 1 and frame.words[2] != 0: frame.pc = frame.words[2]
				if response.result == 2 and frame.words[3] != 0: frame.pc = frame.words[3]
				_phase = "fetch"
			"yes_no":
				if not _i2(response.get("result")): return _fail("menu requires signed result")
				if response.result < 0: _phase = "choice"
				elif response.result == 0: frame.pc = frame.words[1]; _phase = "fetch"
				else: _phase = "command"
			_:
				if response.get("completed") != true or typeof(response.get("completed")) != TYPE_BOOL:
					return _fail("effect needs explicit completed acknowledgement")
				match kind:
					"sync_party_for_redraw": _phase = "redraw_render"
					"render_scene":
						if _phase == "redraw_render": _state.globals.redraw_mode = 0; _phase = "command"
						else: frame.remaining -= 1; _phase = "frame_start"
					"restore_background":
						_state.dialogue.capture_gate = 0; _state.dialogue.restore_gate = 0; _phase = "command"
					"advance_party_movement": _phase = "frame_sync"
					"sync_party_frames": _phase = "frame_main"
					"main_frame": _phase = "frame_render"
					_: return _fail("unrecognized pending effect")
	_pending = {}
	return _advance()

func _idle_jump(frame: Dictionary) -> Dictionary:
	var limit: int = _signed(frame.words[2])
	var jump: bool = limit == 0
	if limit != 0:
		var row: Dictionary = _events.event_record(_state.events,frame.event_id)
		if row.has("error"): return _fail(str(row.error))
		var bytes: PackedByteArray = row.value
		var count: int = _signed(bytes.decode_u16(24)) + 1
		if count > 32767: return _fail("TriggerIdleFrame I2 overflow")
		jump = count < limit
		bytes.encode_u16(24,count & 65535 if jump else 0)
		_state.events = _events.replace_event_record(_state.events,frame.event_id,bytes).state
	if jump:
		frame.pc = frame.words[1]
		_phase = "exit" if frame.words[0] == 2 else "fetch"
	else: _phase = "command"
	return {}

func _recurse(frame: Dictionary) -> Dictionary:
	var event_id: int = frame.event_id
	var argument: int = _signed(frame.words[2])
	if argument > 0:
		var scene = _state.globals.get("current_scene")
		if not _i2(scene) or scene < 1 or scene > int(_state.events.scene_records.size() / 8):
			return _fail("recursive call requires known current scene")
		var first: int = _signed(_state.events.scene_records.decode_u16((scene - 1) * 8 + 6))
		event_id = argument - first
		if not _i2(event_id): return _fail("recursive event conversion I2 overflow")
		if event_id <= 0 or event_id > _state.events.event_count: _phase = "command"; return {}
	if _frames.size() >= MAX_DEPTH: return _fail("trigger recursion budget exceeded")
	# Only these two coordinates are T258 locals. Other dialogue values are
	# globals and keep the child invocation's changes after it returns.
	frame.local_x = _state.dialogue.local_x; frame.local_y = _state.dialogue.local_y
	_enter(frame.words[1],event_id); return {}

func _advance() -> Dictionary:
	while true:
		var frame: Dictionary = _frames.back()
		var result: Dictionary = {}
		match _phase:
			"fetch":
				if frame.pc == 0 or frame.pc > _last: _phase = "exit"; continue
				if _steps >= _budget: return _fail("trigger instruction budget exceeded")
				var record: Dictionary = _records.instruction(frame.pc)
				if record.has("error"): return _fail(str(record))
				frame.words = record.value.words.duplicate(); frame.receipt = record.source.duplicate(true)
				_steps += 1; _trace.append({"pc":frame.pc,"event_id":frame.event_id,"words":frame.words.duplicate()})
				match frame.words[0]:
					0: frame.pc = frame.saved; _phase = "exit"
					1: frame.pc = _next(frame.pc); _phase = "exit"
					2, 3: result = _idle_jump(frame)
					4: result = _recurse(frame)
					5: result = _dialogue("clear","redraw")
					6:
						var random: Dictionary = Random.ordinary_next(_state.rng,"ordinary")
						if random.has("error"): return _fail(str(random.error))
						_state.rng = random.state
						var scaled = PackedByteArray(); scaled.resize(4); scaled.encode_float(0,random.value * 100.0)
						if _signed(frame.words[1]) < scaled.decode_float(0):
							if frame.words[2] != 0: frame.pc = frame.words[2]; _phase = "fetch"
							else: _phase = "exit"
						else: _phase = "command"
					7: result = _dialogue("clear","battle")
					8: frame.saved = _next(frame.pc); _phase = "command"
					9: result = _dialogue("clear","frames")
					10:
						_state.dialogue.line_count = 0; _state.dialogue.boxed_count = 0; _phase = "choice"
					65535: result = _dialogue("message","command")
					_:
						if _signed(frame.words[0]) > 10: result = _dialogue("clear","command")
						else: _phase = "command"
			"command":
				# ALL continuing paths reach T240, including FFFF/local controls.
				# Its DoEvents gate occurs before the signed command<=10 return.
				return _request("execute_command",{"words":frame.words.duplicate(),"entry":frame.pc,
					"instruction_source":frame.receipt.duplicate(true)})
			"redraw":
				if _state.dialogue.capture_gate != 0: return _request("restore_background")
				_state.globals.redraw_mode = _signed(frame.words[1])
				if frame.words[2] == 0: frame.words[2] = 1
				_phase = "redraw_render"
				if frame.words[3] != 0: return _request("sync_party_for_redraw")
			"redraw_render": return _request("render_scene",{"mode":_signed(frame.words[2])})
			"battle": return _request("battle",{"enemy_team":_signed(frame.words[1]),"argument":_signed(frame.words[3])})
			"choice": return _request("yes_no",{"menu_id":19,"initial_selection":0})
			"frames":
				if frame.words[1] == 0: frame.words[1] = 1
				frame.remaining = _signed(frame.words[1]); _phase = "frame_start"
			"frame_start":
				if frame.remaining <= 0: _phase = "command"
				elif frame.words[3] != 0: return _request("advance_party_movement")
				else: _phase = "frame_main"
			"frame_sync": return _request("sync_party_frames")
			"frame_main": return _request("main_frame",{"mode":_signed(frame.words[2])})
			"frame_render": return _request("render_scene",{"mode":1})
			"exit": result = _dialogue("clear","return")
			"return":
				var entry: int = frame.pc
				_frames.pop_back()
				if _frames.is_empty():
					_phase = "complete"; _pending = {}
					return {"state":_state.duplicate(true),"return_entry":entry,"steps":_steps,"trace":_trace.duplicate(true)}
				var parent: Dictionary = _frames.back()
				parent.words[1] = entry # Recursive ByRef targets the local Arg0, not the SSS row.
				_state.dialogue.local_x = parent.local_x; _state.dialogue.local_y = parent.local_y
				_phase = "command"
			_: return _fail("invalid trigger phase")
		if not result.is_empty(): return result
	return _fail("unreachable trigger phase")
