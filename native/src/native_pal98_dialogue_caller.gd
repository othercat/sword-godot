# SPDX-License-Identifier: MIT
extends RefCounted
## Recovered FFFF/ClearText request composition. No general SSS dispatcher,
## display buffers, wall clock, physical input or public save state is owned here.
const Text = preload("res://src/native_pal98_text_execution.gd")
const PROFILE = "pal98.dialogue-caller-subset.v1"
const WORD_FIELDS = ["local_x","local_y","title_x","title_y","origin_x","origin_y","mode",
	"line_count","boxed_count","draw_x","draw_y","icon","skip_word","delay_units","input_action","capture_gate","restore_gate"]
const KEYS = ["profile","source_id","operation","message_index","instruction_index","context","phase","body","remaining_polls"]
const PHASES = ["capture","overflow_icon","overflow_input","overflow_restore","box","box_text","title","mode9","body",
	"clear_poll","clear_wait","clear_restore","clear_icon","clear_input","complete"]

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value) and value >= low and value <= high

static func _context_valid(context: Dictionary) -> bool:
	if context.size() != WORD_FIELDS.size() + 2: return false
	for key in WORD_FIELDS:
		if not _integer(context.get(key),-32768,32767): return false
	var colours = context.get("colours")
	return colours is Array and colours.size() == 4 and colours.all(func(value): return _integer(value,-32768,32767)) and _integer(context.get("timer_counter"),0,4294967295)

static func _context_copy(context: Dictionary) -> Dictionary:
	var result: Dictionary = context.duplicate(true)
	for key in WORD_FIELDS + ["timer_counter"]: result[key] = int(result[key])
	for index in range(4): result.colours[index] = int(result.colours[index])
	return result

static func enter_trigger_context(context: Dictionary) -> Dictionary:
	# Apply once at T258 entry, never once per message. All other supplied
	# globals/locals are preserved; this does not guess their cold-start values.
	if not _context_valid(context): return _failure("invalid_dialogue_context")
	var candidate: Dictionary = _context_copy(context)
	candidate.merge({"line_count":0,"boxed_count":0,"colours":[79,45,26,141],"mode":1,
		"title_x":12,"title_y":8,"origin_x":44,"origin_y":26},true)
	return {"context":candidate}

static func _failure(code: String, source: Dictionary = {}, state: Dictionary = {}) -> Dictionary:
	var diagnostic: Dictionary = source.get("source",source).duplicate(true)
	diagnostic.code = code
	for key in ["operation","phase","message_index","instruction_index"]:
		if state.has(key): diagnostic[key] = state[key]
	for key in ["offset_directory_source","instruction_source","instruction_words"]:
		if source.has(key): diagnostic[key] = source[key].duplicate(true)
	return {"error":"pal98-dialogue-caller: " + code,"diagnostic":diagnostic}

static func begin_message(records, index: int, context: Dictionary) -> Dictionary:
	return _begin(records,index,-1,"message",context)

static func begin_instruction(records, pc: int, context: Dictionary) -> Dictionary:
	if pc < 0: return records.message_for_instruction(pc) if records != null else _failure("not_loaded",{},{"instruction_index":pc})
	return _begin(records,-1,pc,"message",context)

static func begin_clear(records, context: Dictionary) -> Dictionary:
	return _begin(records,-1,-1,"clear",context)

static func _source(records, state: Dictionary) -> Dictionary:
	if records == null or records.metadata().is_empty(): return _failure("not_loaded")
	if state.operation == "clear": return {"source":{"fingerprint":records.metadata().fingerprint,"scope":"dialogue-clear"}}
	return records.message_for_instruction(state.instruction_index) if state.instruction_index >= 0 else records.message_bytes(state.message_index)

static func _begin(records, index: int, pc: int, operation: String, context: Dictionary) -> Dictionary:
	if not _context_valid(context): return _failure("invalid_dialogue_context")
	var state: Dictionary = {"profile":PROFILE,"source_id":"","operation":operation,"message_index":index,"instruction_index":pc,
		"context":_context_copy(context),"phase":"start","body":{},"remaining_polls":0}
	var source: Dictionary = _source(records,state)
	if source.has("error"): return source
	state.source_id = source.source.fingerprint
	if operation == "message":
		state.message_index = source.source.record_index
		if source.value.bytes.size() > 255: return _failure("message_length_u1_unimplemented",source,state)
		if state.context.line_count > 3: _icon_wait(state,"overflow")
		else: return _line_start(records,state,source)
	else:
		if state.context.boxed_count != 0: state.remaining_polls = 160; state.phase = "clear_poll"
		elif state.context.line_count != 0: _icon_wait(state,"clear")
		else: _clear_done(state)
	return _result(state,source,records)

static func _icon_wait(state: Dictionary, prefix: String) -> void:
	state.context.skip_word = 0
	if state.context.mode != 0: state.phase = prefix + "_icon"
	else: state.context.input_action = 0; state.phase = prefix + "_input"

static func _clear_done(state: Dictionary) -> void:
	state.context.line_count = 0; state.context.boxed_count = 0; state.phase = "complete"

static func _line_start(records, state: Dictionary, source: Dictionary) -> Dictionary:
	if state.context.line_count == 0:
		state.context.local_x = state.context.origin_x; state.context.local_y = state.context.origin_y
		if state.context.capture_gate == 0: state.phase = "capture"; return _result(state,source)
	return _dispatch(records,state,source)

static func _add(context: Dictionary, key: String, increment: int) -> bool:
	var value: int = context[key] + increment
	if value < -32768 or value > 32767: return false
	context[key] = value; return true

static func _is_title(bytes: PackedByteArray, context: Dictionary) -> bool:
	var length: int = bytes.size()
	if length == 0: return false # The caller diagnoses the unclosed negative-index read separately.
	var penultimate: int = bytes[length - 2] if length >= 2 else length
	var last: int = bytes[length - 1]
	return context.mode > 0 and context.line_count == 0 and (last == 0x3a or (penultimate == 0xa1 and last == 0x47) or (penultimate == 0xa3 and last == 0xba))

static func _body_failure(body: Dictionary, source: Dictionary, state: Dictionary) -> Dictionary:
	var result: Dictionary = body.duplicate(true)
	# Keep the child byte offset and phase, while retaining the outer FFFF call
	# even for lexical failures that occur before a child state is created.
	result.diagnostic.caller_operation = state.operation; result.diagnostic.caller_phase = state.phase
	result.diagnostic.message_index = state.message_index; result.diagnostic.instruction_index = state.instruction_index
	for key in ["instruction_source","instruction_words"]:
		if source.has(key) and not result.diagnostic.has(key): result.diagnostic[key] = source[key].duplicate(true)
	return result

static func _dispatch(records, state: Dictionary, source: Dictionary) -> Dictionary:
	var context: Dictionary = state.context; var bytes: PackedByteArray = source.value.bytes; var length: int = bytes.size()
	if context.mode >= 10:
		var centered: int = context.origin_x - int(length / 2) * 8
		if centered < -32768: return _failure("dialogue_coordinate_i2_overflow",source,state)
		context.local_x = centered; state.phase = "box"
	else:
		# Original And/Or evaluates B[n-1] even when mode<=0 or line!=0.
		# For empty messages this is index -1; its address-helper behavior is
		# unclosed. Do not substitute T82's known empty-body success.
		if length == 0: return _failure("empty_message_title_read_unimplemented",source,state)
		if _is_title(bytes,context): state.phase = "title"
		elif context.mode == 9:
			if context.local_y <= 100 and context.local_x + 28 > 32767: return _failure("dialogue_coordinate_i2_overflow",source,state)
			state.phase = "mode9"
		else:
			if not _add(context,"line_count",1): return _failure("dialogue_line_i2_overflow",source,state)
			var body: Dictionary = Text.begin_instruction(records,state.instruction_index,_body_context(context)) if state.instruction_index >= 0 else Text.begin_message(records,state.message_index,_body_context(context))
			if body.has("error"): return _body_failure(body,source,state)
			state.body = body.state; state.phase = "body"; _sync_body(state)
			if body.request.kind == "return": return _body_done(state,source)
	return _result(state,source,records)

static func _body_context(context: Dictionary) -> Dictionary:
	return {"x":context.local_x,"y":context.local_y,"colour":context.colours[0],"alternate_colour":context.colours[1],
		"icon":context.icon,"line_count":context.line_count,"skip_word":context.skip_word,"delay_units":context.delay_units,"timer_counter":context.timer_counter}

static func _sync_body(state: Dictionary) -> void:
	var context: Dictionary = state.context; var body: Dictionary = state.body
	context.draw_x = body.x; context.draw_y = body.y
	context.colours[0] = body.colour; context.colours[1] = body.alternate_colour
	for key in ["icon","line_count","skip_word","delay_units","timer_counter"]: context[key] = body[key]

static func _body_done(state: Dictionary, source: Dictionary) -> Dictionary:
	if not _add(state.context,"local_y",18 if state.context.mode == 0 else 16): return _failure("dialogue_coordinate_i2_overflow",source,state)
	state.phase = "complete"; return _result(state,source)

static func _state_source(records, state: Dictionary) -> Dictionary:
	if state.size() != KEYS.size() or not KEYS.all(func(key): return state.has(key)) or state.profile != PROFILE or state.operation not in ["message","clear"]:
		return _failure("invalid_dialogue_state")
	if not state.context is Dictionary or not _context_valid(state.context) or not state.body is Dictionary or state.phase not in PHASES or not _integer(state.remaining_polls,0,160):
		return _failure("invalid_dialogue_state")
	if not _integer(state.message_index,-1,65535) or not _integer(state.instruction_index,-1,65535): return _failure("invalid_dialogue_state")
	if (state.operation == "clear" and (state.message_index != -1 or state.instruction_index != -1 or state.phase not in ["clear_poll","clear_wait","clear_restore","clear_icon","clear_input","complete"])) or (state.operation == "message" and (state.message_index < 0 or state.phase.begins_with("clear_"))):
		return _failure("invalid_dialogue_state")
	var source: Dictionary = _source(records,state)
	if source.has("error"): return source
	if source.source.fingerprint != state.source_id or (state.operation == "message" and source.source.record_index != state.message_index): return _failure("dialogue_source_mismatch",source,state)
	if state.operation == "message" and source.value.bytes.size() > 255: return _failure("message_length_u1_unimplemented",source,state)
	var context: Dictionary = state.context; var phase: String = state.phase
	var coherent: bool = true
	if phase == "capture": coherent = context.line_count == 0 and context.capture_gate == 0 and context.local_x == context.origin_x and context.local_y == context.origin_y
	elif phase in ["overflow_icon","overflow_input"]: coherent = context.line_count > 3 and context.skip_word == 0
	elif phase == "overflow_restore": coherent = context.line_count == 0 and context.input_action != 0
	elif phase in ["box","box_text"]:
		coherent = context.mode >= 10 and context.local_x == context.origin_x - int(source.value.bytes.size() / 2) * 8
		if phase == "box_text": coherent = coherent and context.local_x + 6 <= 32767 and context.local_y + 8 <= 32767
	elif phase == "mode9":
		coherent = context.mode == 9 and not source.value.bytes.is_empty() and not _is_title(source.value.bytes,context)
		coherent = coherent and (context.local_y > 100 or context.local_x + 28 <= 32767)
	elif phase == "title": coherent = context.mode < 10 and _is_title(source.value.bytes,context)
	elif phase == "body": coherent = context.mode < 10 and context.mode != 9 and not source.value.bytes.is_empty()
	elif phase in ["clear_poll","clear_wait"]:
		coherent = context.boxed_count != 0 and state.remaining_polls >= 1
		if phase == "clear_wait": coherent = coherent and context.timer_counter == 0
	elif phase == "clear_restore": coherent = context.boxed_count != 0 and context.restore_gate != 0
	elif phase in ["clear_icon","clear_input"]: coherent = context.boxed_count == 0 and context.line_count != 0 and context.skip_word == 0
	if phase in ["clear_icon","overflow_icon"]: coherent = coherent and context.mode != 0
	if phase in ["clear_input","overflow_input"]: coherent = coherent and context.input_action == 0
	if phase not in ["body","complete"]: coherent = coherent and state.body.is_empty()
	if state.operation == "message": coherent = coherent and state.remaining_polls == 0
	if not coherent: return _failure("invalid_dialogue_phase",source,state)
	if state.phase == "body":
		if state.body.get("source_id") != state.source_id or state.body.get("message_index") != state.message_index or state.body.get("instruction_index") != state.instruction_index or state.body.get("phase") == "complete": return _failure("dialogue_body_mismatch",source,state)
		var plan: Dictionary = Text.inspect_state(records,state.body)
		if plan.has("error"): return _body_failure(plan,source,state)
		var synchronized: Dictionary = state.duplicate(true); _sync_body(synchronized)
		if synchronized.context != state.context: return _failure("dialogue_body_mismatch",source,state)
	return source

static func step(records, state: Dictionary, event: Dictionary) -> Dictionary:
	var source: Dictionary = _state_source(records,state)
	if source.has("error"): return source
	if state.phase == "complete": return _failure("dialogue_already_complete",source,state)
	var candidate: Dictionary = state.duplicate(true); candidate.context = _context_copy(state.context)
	var context: Dictionary = candidate.context; var phase: String = candidate.phase; var kind = event.get("kind")
	if phase == "body":
		var body: Dictionary = Text.step(records,candidate.body,event)
		if body.has("error"): return _body_failure(body,source,state)
		candidate.body = body.state; _sync_body(candidate)
		if body.request.kind == "return": return _body_done(candidate,source)
	elif kind == "tick" and event.size() == 1:
		context.timer_counter = (context.timer_counter + 1) % 4294967296
		if phase == "clear_wait" and context.timer_counter >= 1: _poll_wait_done(candidate)
	elif phase in ["overflow_input","clear_input","clear_poll"] and kind == "input" and event.size() == 2 and _integer(event.get("action"),-32768,32767):
		if phase == "clear_poll":
			if event.action != 0: _timed_clear_done(candidate)
			elif context.timer_counter >= 1: _poll_wait_done(candidate)
			else: candidate.phase = "clear_wait"
		else:
			context.input_action = int(event.action)
			if event.action != 0:
				context.line_count = 0
				if phase == "overflow_input": candidate.phase = "overflow_restore"
				else: _clear_done(candidate)
	elif event.size() == 1 and ((phase == "capture" and kind == "captured") or (phase in ["overflow_restore","clear_restore"] and kind == "restored") or (phase == "box" and kind == "box_drawn") or (phase in ["title","mode9","box_text","overflow_icon","clear_icon"] and kind == "drawn")):
		match phase:
			"capture": return _dispatch(records,candidate,source)
			"overflow_restore","clear_restore":
				context.capture_gate = 0; context.restore_gate = 0
				if phase == "overflow_restore": return _line_start(records,candidate,source)
				_clear_done(candidate)
			"overflow_icon","clear_icon": context.input_action = 0; candidate.phase = "overflow_input" if phase == "overflow_icon" else "clear_input"
			"box":
				if context.local_x + 6 > 32767 or context.local_y + 8 > 32767: return _failure("dialogue_coordinate_i2_overflow",source,candidate)
				candidate.phase = "box_text"
			"box_text":
				if not _add(context,"local_y",18): return _failure("dialogue_coordinate_i2_overflow",source,candidate)
				if not _add(context,"boxed_count",1): return _failure("dialogue_box_count_i2_overflow",source,candidate)
				context.line_count = context.boxed_count; candidate.phase = "complete"
			"title": candidate.phase = "complete"
			"mode9":
				if not _add(context,"origin_y",16) or not _add(context,"local_y",16): return _failure("dialogue_coordinate_i2_overflow",source,candidate)
				candidate.phase = "complete"
	else: return _failure("invalid_dialogue_signal",source,state)
	return _result(candidate,source,records)

static func _poll_wait_done(state: Dictionary) -> void:
	state.context.timer_counter = 0; state.remaining_polls -= 1
	if state.remaining_polls == 0: _timed_clear_done(state)
	else: state.phase = "clear_poll"

static func _timed_clear_done(state: Dictionary) -> void:
	if state.context.restore_gate != 0: state.phase = "clear_restore"
	else: _clear_done(state)

static func _result(state: Dictionary, source: Dictionary, records = null) -> Dictionary:
	var context: Dictionary = state.context; var phase: String = state.phase; var request: Dictionary
	match phase:
		"capture": request = {"kind":"capture_background"}
		"overflow_restore","clear_restore": request = {"kind":"restore_background"}
		"overflow_icon","clear_icon": request = {"kind":"draw_dialogue_icon","index":context.icon,"x":context.draw_x,"y":context.draw_y}
		"overflow_input","clear_input": request = {"kind":"poll_input","model":"until_nonzero"}
		"clear_poll": request = {"kind":"poll_input","model":"bounded_clear","remaining_polls":state.remaining_polls}
		"clear_wait": request = {"kind":"wait","model":"wtime","target_counter":1}
		# Box/Strip uses nonzero=enabled, opposite to DrawString's shadow word.
		"box": request = {"kind":"draw_dialogue_box","x":context.local_x,"y":context.local_y,"half_length":int(source.value.bytes.size() / 2),"shadow_enabled_word":0}
		"body":
			var inspected: Dictionary = Text.inspect_state(records,state.body)
			if inspected.has("error"): return _body_failure(inspected,source,state)
			request = inspected.request
		"title","mode9","box_text":
			var bytes: PackedByteArray = source.value.bytes.duplicate(); bytes.append(0)
			var position: Vector2i = Vector2i(context.local_x,context.local_y); var colour: int = context.colours[0]; var shadow: int = 0
			if phase == "title": position = Vector2i(context.title_x,context.title_y); colour = 140
			elif phase == "box_text": position += Vector2i(6,8); colour = 64; shadow = 3
			else: position.x += 0 if context.local_y > 100 else 28
			request = {"kind":"draw_string","x":position.x,"y":position.y,"palette_word":colour,"shadow_word":shadow,
				"nul_terminated_bytes":bytes,"byte_offset":source.source.byte_offset,"source_size_bytes":source.source.size_bytes}
		_: request = {"kind":"return","operation":state.operation}
	var result: Dictionary = {"state":state.duplicate(true),"request":request,"source":source.source.duplicate(true)}
	for key in ["offset_directory_source","instruction_source","instruction_words"]:
		if source.has(key): result[key] = source[key].duplicate(true)
	return result
