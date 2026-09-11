# SPDX-License-Identifier: MIT
extends RefCounted
## Explicit stepping of the recovered glyph/wait/input sequence. Callers supply
## context and acknowledge requests. No wall clock, renderer or Session is used.
const Text = preload("res://src/native_pal98_text_tokens.gd")
const PROFILE = "pal98.text-execution-subset.v1"
const I2_FIELDS = ["x", "y", "colour", "alternate_colour", "icon", "line_count", "skip_word", "delay_units"]
const STATE_KEYS = ["profile", "source_id", "message_index", "instruction_index", "next_token", "phase",
	"x", "y", "colour", "alternate_colour", "icon", "line_count", "skip_word", "delay_units", "timer_counter"]
const UINT32_MODULUS = 4294967296

static func begin_message(records, index: int, context: Dictionary) -> Dictionary:
	return _begin(Text.read_message(records, index), -1, context)

static func begin_instruction(records, pc: int, context: Dictionary) -> Dictionary:
	# Resolve source only. The caller must already have selected the T82 body
	# branch; this does not dispatch FFFF title/mode/overflow/background behavior.
	return _begin(Text.read_instruction(records, pc), pc, context)

static func context_from(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in I2_FIELDS + ["timer_counter"]:
		if state.has(key): result[key] = state[key]
	return result

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= low and value <= high

static func _context_valid(context: Dictionary) -> bool:
	if context.size() != I2_FIELDS.size() + 1: return false
	for key in I2_FIELDS:
		if not _integer(context.get(key), -32768, 32767): return false
	return _integer(context.get("timer_counter"), 0, UINT32_MODULUS - 1)

static func _failure(code: String, detail: String, plan: Dictionary = {}, state: Dictionary = {}) -> Dictionary:
	var diagnostic: Dictionary = plan.get("source", {}).duplicate(true)
	diagnostic.code = code
	for key in ["offset_directory_source", "instruction_source", "instruction_words"]:
		if plan.has(key): diagnostic[key] = plan[key].duplicate(true)
	for key in ["message_index", "instruction_index", "next_token", "phase"]:
		if state.has(key): diagnostic[key] = state[key]
	var cursor = state.get("next_token")
	if _integer(cursor, 0, plan.get("tokens", []).size() - 1):
		diagnostic.relative_byte_offset = plan.tokens[int(cursor)].offset
		diagnostic.error_byte_offset = plan.source.byte_offset + diagnostic.relative_byte_offset
	return {"error": "pal98-text-execution: " + detail, "diagnostic": diagnostic}

static func _begin(plan: Dictionary, pc: int, context: Dictionary) -> Dictionary:
	if plan.has("error"): return plan
	if not _context_valid(context): return _failure("invalid_text_context", "explicit I2 text fields and unsigned timer counter required", plan)
	var state: Dictionary = {"profile": PROFILE, "source_id": plan.source.fingerprint,
		"message_index": plan.source.record_index, "instruction_index": pc, "next_token": 0, "phase": "run"}
	for key in context: state[key] = int(context[key])
	state.icon = 0
	_pump(state, plan)
	return _result(state, plan)

static func _plan_for(records, state: Dictionary) -> Dictionary:
	if state.size() != STATE_KEYS.size() or not STATE_KEYS.all(func(key): return state.has(key)) or state.get("profile") != PROFILE:
		return _failure("invalid_text_state", "unsupported internal text state", {}, state)
	if not _context_valid(context_from(state)) or not _integer(state.message_index, 0, 65535) or not _integer(state.instruction_index, -1, 65535) or not _integer(state.next_token, 0, 255):
		return _failure("invalid_text_state", "text state values outside source ranges", {}, state)
	var plan: Dictionary = Text.read_instruction(records, int(state.instruction_index)) if state.instruction_index >= 0 else Text.read_message(records, int(state.message_index))
	if plan.has("error"): return plan
	if state.source_id != plan.source.fingerprint or state.message_index != plan.source.record_index:
		return _failure("text_source_mismatch", "text state belongs to another source/message", plan, state)
	var cursor: int = int(state.next_token); var phase = state.phase; var count: int = plan.tokens.size()
	var coherent: bool = false
	if phase == "draw": coherent = cursor < count and plan.tokens[cursor].kind == "glyph"
	elif phase in ["wait_wtime", "input"]:
		coherent = cursor > 0 and cursor <= count and plan.tokens[cursor - 1].kind == "glyph"
		if phase == "wait_wtime": coherent = coherent and state.skip_word == 0 and state.timer_counter < _unsigned_delay(int(state.delay_units))
	elif phase == "wait_delay1":
		coherent = cursor > 0 and cursor <= count and plan.tokens[cursor - 1].kind == "timed_delay" and state.line_count == 0 and state.skip_word == 0 and state.timer_counter < plan.tokens[cursor - 1].units
	elif phase == "complete": coherent = cursor == count
	if not coherent: return _failure("invalid_text_phase", "text phase/cursor is inconsistent with source plan", plan, state)
	return plan

static func step(records, state: Dictionary, event: Dictionary) -> Dictionary:
	var plan: Dictionary = _plan_for(records, state)
	if plan.has("error"): return plan
	var kind = event.get("kind"); var phase = state.phase
	if phase == "complete": return _failure("text_already_complete", "returned text cannot accept more signals", plan, state)
	if kind == "tick":
		if event.size() != 1: return _failure("invalid_text_signal", "one nominal timer tick has no payload", plan, state)
	elif kind == "drawn":
		if phase != "draw" or event.size() != 1: return _failure("invalid_text_signal", "draw acknowledgement requires a pending glyph", plan, state)
	elif kind == "input":
		if phase != "input" or event.size() != 2 or not _integer(event.get("action"), -32768, 32767):
			return _failure("invalid_text_signal", "input action requires the post-glyph poll", plan, state)
	else: return _failure("invalid_text_signal", "unknown text signal", plan, state)
	var candidate: Dictionary = state.duplicate(true)
	for key in I2_FIELDS + ["timer_counter", "next_token", "message_index", "instruction_index"]: candidate[key] = int(candidate[key])
	if kind == "tick":
		candidate.timer_counter = (candidate.timer_counter + 1) % UINT32_MODULUS
		if not _resolve_wait(candidate, plan): return _overflow(candidate, plan)
	elif kind == "drawn":
		candidate.next_token += 1
		if candidate.skip_word == 0:
			candidate.phase = "wait_wtime"
			if not _resolve_wait(candidate, plan): return _overflow(candidate, plan)
		elif not _finish_glyph(candidate, plan): return _overflow(candidate, plan)
	else:
		if event.action == 2: candidate.skip_word = -1
		candidate.phase = "run"; _pump(candidate, plan)
	return _result(candidate, plan)

static func _unsigned_delay(value: int) -> int:
	# PAL.DLL sign-extends the I2 request and compares it as unsigned 32-bit.
	return value if value >= 0 else UINT32_MODULUS + value

static func _overflow(state: Dictionary, plan: Dictionary) -> Dictionary:
	var result: Dictionary = _failure("text_coordinate_i2_overflow", "post-wait X advance exceeds original I2 range", plan, state)
	result.diagnostic.relative_byte_offset = plan.tokens[state.next_token - 1].offset
	result.diagnostic.error_byte_offset = plan.source.byte_offset + result.diagnostic.relative_byte_offset
	result.diagnostic.timer_counter = state.timer_counter; result.diagnostic.skip_word = state.skip_word
	return result

static func _finish_glyph(state: Dictionary, plan: Dictionary) -> bool:
	# Original checked X advance follows wtime (when enabled), then input polling.
	state.phase = "after_glyph_wait"
	var x: int = state.x + plan.tokens[state.next_token - 1].advance_pixels
	if x > 32767: return false
	state.x = x; state.phase = "input"; return true

static func _resolve_wait(state: Dictionary, plan: Dictionary) -> bool:
	if state.phase == "wait_wtime" and state.timer_counter >= _unsigned_delay(state.delay_units):
		state.timer_counter = 0
		return _finish_glyph(state, plan)
	elif state.phase == "wait_delay1" and state.timer_counter >= plan.tokens[state.next_token - 1].units:
		state.phase = "run"; _pump(state, plan)
	return true

static func _pump(state: Dictionary, plan: Dictionary) -> void:
	while state.next_token < plan.tokens.size():
		var token: Dictionary = plan.tokens[state.next_token]
		if token.kind == "glyph": state.phase = "draw"; return
		state.next_token += 1
		match token.kind:
			"swap_colours":
				var colour: int = state.colour; state.colour = state.alternate_colour; state.alternate_colour = colour
			"select_icon": state.icon = token.index
			"character_delay": state.delay_units = token.units
			"timed_delay":
				state.line_count = 0; state.skip_word = 0; state.timer_counter = 0; state.phase = "wait_delay1"
				_resolve_wait(state, plan); return
	state.phase = "complete"

static func _result(state: Dictionary, plan: Dictionary) -> Dictionary:
	var request: Dictionary
	match state.phase:
		"draw":
			var token: Dictionary = plan.tokens[state.next_token]; var bytes: PackedByteArray = token.bytes.duplicate(); bytes.append(0)
			request = {"kind": "draw_glyph", "x": state.x, "y": state.y, "palette_word": state.colour, "shadow_word": 0,
				"nul_terminated_bytes": bytes, "loader_zero": token.loader_zero,
				"relative_byte_offset": token.offset, "byte_offset": plan.source.byte_offset + token.offset, "source_size_bytes": token.size_bytes}
		"input": request = {"kind": "poll_input"}
		"wait_wtime", "wait_delay1":
			request = {"kind": "wait", "model": "wtime" if state.phase == "wait_wtime" else "delay1",
				"target_counter": _unsigned_delay(state.delay_units) if state.phase == "wait_wtime" else plan.tokens[state.next_token - 1].units}
		_:
			request = {"kind": "return", "termination": plan.termination, "consumed_bytes": plan.consumed_bytes,
				"remaining_bytes": plan.remaining_bytes.duplicate()}
	var result: Dictionary = {"state": state.duplicate(true), "request": request, "source": plan.source.duplicate(true)}
	for key in ["offset_directory_source", "instruction_source", "instruction_words"]:
		if plan.has(key): result[key] = plan[key].duplicate(true)
	return result
