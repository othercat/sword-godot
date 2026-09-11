# SPDX-License-Identifier: MIT
extends SceneTree
const Execute = preload("res://src/native_pal98_text_execution.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Package = preload("res://src/native_package.gd")
const Schema = preload("res://src/native_schema.gd")
const Reader = preload("res://src/native_json.gd")
var checks: Array = []
var failed: int = 0
var reference: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: push_error("Expected source-window report and fresh output"); quit(2); return
	if DirAccess.dir_exists_absolute(args[1]): push_error("Use a fresh output directory"); quit(2); return
	DirAccess.make_dir_recursive_absolute(args[1])
	_synthetic()
	var reader = Reader.new(); var fixture = reader.decode(FileAccess.get_file_as_bytes(args[0]))
	if not fixture is Dictionary or not reader.error.is_empty(): push_error("Invalid source-window report"); quit(2); return
	_real(fixture)
	var file = FileAccess.open(args[1].path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failed == 0,"failed":failed,"checks":checks,"reference":reference,
		"request_kernel_only":true,"renderer_executed":false,"original_gameplay":false,"human_acceptance":false},"\t")); file.close()
	print("PAL98 text execution requests: ",checks.size()," checks, ",failed," failed")
	quit(0 if failed == 0 else 1)

func _zero(count: int) -> PackedByteArray:
	var result = PackedByteArray(); result.resize(count); return result

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4; var result = _zero(size); result.encode_u32(0,size)
	for i in range(chunks.size()): size += chunks[i].size(); result.encode_u32((i + 1) * 4,size)
	for chunk in chunks: result.append_array(chunk)
	return result

func _records(messages: Array):
	var offsets = _zero((messages.size() + 1) * 4); var payload = PackedByteArray(); var scripts = _zero((messages.size() + 1) * 8)
	for i in range(messages.size()):
		payload.append_array(messages[i]); offsets.encode_u32((i + 1) * 4,payload.size())
		scripts.encode_u16((i + 1) * 8,0xffff); scripts.encode_u16((i + 1) * 8 + 2,i)
	var files: Dictionary = {"data":_mkf([_zero(0),_zero(0),_zero(0),_zero(900)]),
		"sss":_mkf([_zero(0),_zero(16),_zero(14),offsets,scripts]),"words":_zero(10),"messages":payload}
	var hashes: Dictionary = {}; var entries: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(files[role])
	var identity: String = Sources.fingerprint("gbk",hashes)
	for role in Sources.FILES: entries[role] = {"path":"content/pal98-sources/" + identity + "/" + Sources.FILES[role],"sha256":hashes[role],"size_bytes":files[role].size()}
	var source = Sources.new()
	check(source.load_source({"schema":Sources.SCHEMA,"kind":"content","dialect":"pal98-win95","text_encoding":"gbk",
		"fingerprint":identity,"files":entries,"label":"Synthetic text execution","license":"CC0-1.0","redistributable":true,"provenance":{"status":"synthetic"}},files,Schema.new()),"synthetic execution source admitted")
	return source.open_records()

func _context(overrides: Dictionary = {}) -> Dictionary:
	# Probe inputs, not inferred original cold-start values.
	var result: Dictionary = {"x":10,"y":20,"colour":79,"alternate_colour":45,"icon":0,"line_count":3,"skip_word":0,"delay_units":3,"timer_counter":2}
	result.merge(overrides,true); return result

func _ticks(records, result: Dictionary, count: int) -> Dictionary:
	for i in range(count):
		if result.has("error"): return result
		result = Execute.step(records,result.state,{"kind":"tick"})
	return result

func _synthetic() -> void:
	var payloads: Array = []
	for value in ["AB","\"($10)~30$99Z","~00","","x","x","~30~80","A~01B","A","A".repeat(256),"A~30$","$00A","~00~00A"]: payloads.append(value.to_ascii_buffer())
	payloads[4] = PackedByteArray([129]); payloads[5] = PackedByteArray([0])
	var records = _records(payloads)
	var context: Dictionary = _context({"icon":2}); var original: Dictionary = context.duplicate(true)
	var started: Dictionary = Execute.begin_instruction(records,1,context)
	check(started.request.kind == "draw_glyph" and started.request.nul_terminated_bytes == PackedByteArray([65,0]) and started.state.x == 10 and started.state.timer_counter == 2 and context == original,"begin requests first glyph without advancing coordinates, timing or caller context")
	check(started.request.palette_word == 79 and started.request.shadow_word == 0 and started.request.y == 20 and started.instruction_source.record_index == 1,"draw request keeps palette/shadow/coordinates and referring instruction")
	check(started.state.icon == 0 and context.icon == 2,"T82 entry resets icon without changing caller input context")
	var wrong: Dictionary = Execute.step(records,started.state,{"kind":"input","action":2})
	check(wrong.diagnostic.code == "invalid_text_signal" and not wrong.has("state") and started.state.x == 10,"early input cannot skip the glyph or publish a candidate")
	var ticking: Dictionary = _ticks(records,started,1)
	check(ticking.request == started.request and ticking.state.timer_counter == 3,"timer continues while a draw acknowledgement is pending")
	var drawn: Dictionary = Execute.step(records,ticking.state,{"kind":"drawn"})
	check(drawn.request.kind == "poll_input" and drawn.state.x == 18 and drawn.state.timer_counter == 0,"wtime uses elapsed counter and clears it before the post-glyph input poll")
	var next: Dictionary = Execute.step(records,drawn.state,{"kind":"input","action":1})
	check(next.request.kind == "draw_glyph" and next.request.nul_terminated_bytes == PackedByteArray([66,0]) and next.state.skip_word == 0,"non-2 action continues without setting skip")
	var waiting: Dictionary = Execute.step(records,next.state,{"kind":"drawn"})
	check(waiting.request == {"kind":"wait","model":"wtime","target_counter":3} and waiting.state.x == 18,"next glyph waits with X still at its drawing origin")
	check(Execute.step(records,waiting.state,{"kind":"input","action":2}).has("error"),"input is not polled during the pending wtime")
	var before_end: Dictionary = _ticks(records,waiting,2)
	check(before_end.state.phase == "wait_wtime" and before_end.state.timer_counter == 2 and before_end.state.x == 18,"wtime retains the glyph origin below target")
	var at_end: Dictionary = _ticks(records,before_end,1)
	check(at_end.request.kind == "poll_input" and at_end.state.timer_counter == 0 and at_end.state.x == 26,"wtime completion resets counter then advances X before polling input")
	var finished: Dictionary = Execute.step(records,at_end.state,{"kind":"input","action":2})
	check(finished.request.kind == "return" and finished.state.skip_word == -1 and finished.state.line_count == 3 and finished.state.y == 20,"EOF preserves skip/line/Y without adding a confirmation or caller line increment")
	check(Execute.step(records,finished.state,{"kind":"tick"}).diagnostic.code == "text_already_complete","completed invocation refuses further signals")
	var skipped: Dictionary = Execute.begin_message(records,8,_context({"skip_word":5,"timer_counter":100}))
	skipped = Execute.step(records,skipped.state,{"kind":"drawn"})
	check(skipped.request.kind == "poll_input" and skipped.state.timer_counter == 100,"every nonzero skip suppresses wtime without suppressing input")
	skipped = _ticks(records,skipped,1); skipped = Execute.step(records,skipped.state,{"kind":"input","action":0})
	check(skipped.state.skip_word == 5 and skipped.state.timer_counter == 101,"input polls preserve nonzero skip and the running timer unless action is 2")
	var delayed: Dictionary = Execute.begin_message(records,1,_context({"skip_word":-1,"timer_counter":999}))
	check(delayed.request == {"kind":"wait","model":"delay1","target_counter":43} and delayed.state.colour == 45 and delayed.state.alternate_colour == 79 and delayed.state.icon == 1 and delayed.state.delay_units == 14,"controls update their own fields before delay1")
	check(delayed.state.line_count == 0 and delayed.state.skip_word == 0 and delayed.state.timer_counter == 0,"delay1 clears line/skip and resets timer before waiting")
	delayed = _ticks(records,delayed,43)
	check(delayed.request.kind == "draw_glyph" and delayed.request.nul_terminated_bytes == PackedByteArray([90,0]) and delayed.state.delay_units == 141 and delayed.state.timer_counter == 43,"delay1 retains elapsed counter and resumes following speed control/glyph")
	var reset_skip: Dictionary = Execute.begin_message(records,7,_context({"delay_units":1,"timer_counter":0}))
	reset_skip = Execute.step(records,reset_skip.state,{"kind":"drawn"}); reset_skip = _ticks(records,reset_skip,1)
	reset_skip = Execute.step(records,reset_skip.state,{"kind":"input","action":2})
	check(reset_skip.state.phase == "wait_delay1" and reset_skip.state.skip_word == 0,"tilde clears skip set by the preceding glyph input")
	reset_skip = _ticks(records,reset_skip,1); reset_skip = Execute.step(records,reset_skip.state,{"kind":"drawn"})
	check(reset_skip.request.kind == "poll_input" and reset_skip.state.timer_counter == 0,"glyph after delay1 can complete wtime immediately using its retained counter")
	var pair: Dictionary = Execute.begin_message(records,6,_context()); pair = _ticks(records,pair,43)
	check(pair.request.model == "delay1" and pair.request.target_counter == 114 and pair.state.timer_counter == 0,"second tilde starts a fresh delay after the first completes")
	pair = _ticks(records,pair,114)
	check(pair.request.kind == "return" and pair.state.timer_counter == 114,"second delay completes without erasing its counter")
	var zero_wait: Dictionary = Execute.begin_message(records,2,_context())
	check(zero_wait.request.kind == "return" and zero_wait.state.timer_counter == 0 and zero_wait.state.line_count == 0,"zero delay still performs its initial state reset")
	var empty: Dictionary = Execute.begin_message(records,3,context)
	var empty_expected: Dictionary = context.duplicate(true); empty_expected.icon = 0
	check(empty.request.kind == "return" and Execute.context_from(empty.state) == empty_expected,"empty text still resets icon while preserving other explicit fields")
	var zero_speed: Dictionary = Execute.begin_message(records,11,_context({"timer_counter":100}))
	zero_speed = Execute.step(records,zero_speed.state,{"kind":"drawn"})
	check(zero_speed.request.kind == "poll_input" and zero_speed.state.timer_counter == 0,"zero wtime still resets existing timer and polls input")
	check(Execute.begin_message(records,12,context).request.kind == "draw_glyph","consecutive zero delays resume the remaining glyph")
	var lead: Dictionary = Execute.begin_message(records,4,context)
	check(lead.request.nul_terminated_bytes == PackedByteArray([129,0,0]) and lead.request.loader_zero and lead.request.source_size_bytes == 1,"terminal DBCS glyph distinguishes loader zero from final string terminator")
	var nul: Dictionary = Execute.begin_message(records,5,context); nul = Execute.step(records,nul.state,{"kind":"drawn"})
	nul = _ticks(records,nul,1)
	check(nul.state.x == 18,"NUL source glyph still follows the post-wait coordinate advance")
	var edge: Dictionary = Execute.begin_message(records,4,_context({"x":32751,"skip_word":1})); edge = Execute.step(records,edge.state,{"kind":"drawn"})
	check(edge.state.x == 32767,"maximum nonoverflowing I2 coordinate is retained")
	var overflow: Dictionary = Execute.begin_instruction(records,5,_context({"x":32752}))
	overflow = Execute.step(records,overflow.state,{"kind":"drawn"}); var overflow_state: Dictionary = overflow.state.duplicate(true)
	check(overflow.state.phase == "wait_wtime" and overflow.state.x == 32752,"coordinate overflow is deferred until the glyph wait completes")
	var rejected: Dictionary = _ticks(records,overflow,1)
	check(rejected.diagnostic.code == "text_coordinate_i2_overflow" and rejected.diagnostic.instruction_source.record_index == 5 and rejected.diagnostic.relative_byte_offset == 0 and rejected.diagnostic.timer_counter == 0 and not rejected.has("state") and overflow.state == overflow_state,"post-wait I2 overflow keeps completed timer ordering and glyph address without publishing a candidate")
	var skip_overflow: Dictionary = Execute.begin_message(records,8,_context({"x":32760,"skip_word":1,"timer_counter":99}))
	check(Execute.step(records,skip_overflow.state,{"kind":"drawn"}).diagnostic.timer_counter == 99,"skipped wait overflow does not clear the timer")
	for value in [-32768,-1]:
		var unsigned_wait: Dictionary = Execute.begin_message(records,8,_context({"delay_units":value,"timer_counter":4294967296 + value - 1}))
		unsigned_wait = Execute.step(records,unsigned_wait.state,{"kind":"drawn"})
		check(unsigned_wait.request.target_counter == 4294967296 + value,"negative I2 delay compares as sign-extended unsigned32: " + str(value))
		unsigned_wait = _ticks(records,unsigned_wait,1)
		check(unsigned_wait.request.kind == "poll_input" and unsigned_wait.state.timer_counter == 0,"unsigned wait completes at exact boundary: " + str(value))
	var wrapped: Dictionary = Execute.begin_message(records,8,_context({"timer_counter":4294967295})); wrapped = _ticks(records,wrapped,1)
	check(wrapped.state.timer_counter == 0 and wrapped.request.kind == "draw_glyph","nominal timer tick wraps at unsigned32 while glyph is pending")
	for invalid in [{},_context({"extra":0}),_context({"skip_word":true}),_context({"x":32768}),_context({"timer_counter":-1})]:
		check(Execute.begin_message(records,0,invalid).diagnostic.code == "invalid_text_context","malformed explicit context is rejected: " + str(invalid.size()))
	check(Execute.begin_message(records,9,context).diagnostic.code == "message_length_u1_unimplemented" and Execute.begin_message(records,10,context).diagnostic.code == "truncated_text_parameter","unsupported whole source plan starts no execution candidate")
	check(Execute.begin_instruction(records,0,context).diagnostic.code == "not_message_instruction" and Execute.begin_message(null,0,context).diagnostic.code == "not_loaded","source errors propagate before execution")
	var other = _records(["different".to_ascii_buffer()])
	check(Execute.step(other,started.state,{"kind":"drawn"}).diagnostic.code == "text_source_mismatch","execution state cannot cross source fingerprints")
	for invalid in [{"phase":"wait_delay1"},{"next_token":255},{"timer_counter":4294967296},{"extra":1}]:
		var changed: Dictionary = started.state.duplicate(true); changed.merge(invalid,true)
		check(Execute.step(records,changed,{"kind":"drawn"}).has("error"),"incoherent internal state rejected: " + str(invalid.keys()[0]))
	for event in [{"kind":"tick","count":2},{"kind":"unknown"},{"kind":"input","action":0.5}]:
		check(Execute.step(records,drawn.state,event).diagnostic.code == "invalid_text_signal","invalid or batched signal rejected: " + str(event.kind))
	var decoded = JSON.parse_string(JSON.stringify(started.state))
	check(not Execute.step(records,decoded,{"kind":"drawn"}).has("error"),"integral JSON numbers can resume the internal candidate without public-save claims")
	started.request.nul_terminated_bytes[0] = 0; started.source.byte_offset = 999; context.x = 999
	check(Execute.begin_message(records,0,original).request.nul_terminated_bytes == PackedByteArray([65,0]) and records.message_bytes(0).source.byte_offset == 0,"request/context/source outputs do not mutate source records")

func _normal(result: Dictionary) -> Dictionary:
	var request: Dictionary = result.request.duplicate(true)
	for key in request.keys():
		if request[key] is PackedByteArray: request[key + "_hex"] = request[key].hex_encode(); request.erase(key)
	return {"state":result.state.duplicate(true),"request":request}

func _drive(records, index: int, context: Dictionary, by_instruction: bool = true) -> Dictionary:
	var result: Dictionary = Execute.begin_instruction(records,index,context) if by_instruction else Execute.begin_message(records,index,context)
	if result.has("error"): return result
	var trace: Array = [_normal(result)]; var counts: Dictionary = {"drawn":0,"tick":0,"input":0}
	for budget in range(4096):
		if result.request.kind == "return":
			var proof: Dictionary = {"entry_kind":"instruction" if by_instruction else "message","entry_index":index,"context":context,"source":result.source,
				"trace":trace,"trace_sha256":Schema.digest(JSON.stringify(trace,"",true,true).to_utf8_buffer()),"events":counts}
			if result.has("instruction_source"): proof.instruction_source = result.instruction_source
			return proof
		var event: Dictionary
		match result.request.kind:
			"draw_glyph": event = {"kind":"drawn"}
			"wait": event = {"kind":"tick"}
			_: event = {"kind":"input","action":0}
		counts[event.kind] += 1
		result = Execute.step(records,result.state,event)
		if result.has("error"): return result
		trace.append(_normal(result))
	return {"error":"text request budget exceeded"}

func _real(fixture: Dictionary) -> void:
	var package = Package.new(); check(package.load_package(fixture.package),"ordinary source package loads for text execution requests")
	if package.pal98_sources == null: return
	var records = package.pal98_sources.open_records()
	check(records.metadata().fingerprint == fixture.fingerprint,"execution request source matches loaded package identity")
	var pcs: Array = [10,14,16,17]; var xs: Array = [80,44,44,44]; var ys: Array = [40,126,126,142]
	var lines: Array = [1,1,1,2]; var delays: Array = [3,14,1,1]; var expected_ticks: Array = [211,69,9,97]
	var expected_x: Array = [272,236,188,204]; var bodies: Array = []
	for i in range(pcs.size()):
		var context: Dictionary = _context({"x":xs[i],"y":ys[i],"line_count":lines[i],"delay_units":delays[i],"skip_word":0,"timer_counter":0})
		var body: Dictionary = _drive(records,pcs[i],context)
		check(not body.has("error"),"real body source reaches request return under explicit probe context: " + str(pcs[i]))
		if body.has("error"): return
		check(body.events.tick == expected_ticks[i] and body.trace[-1].state.x == expected_x[i],"real body nominal wait count and glyph advances: " + str(pcs[i]))
		bodies.append(body)
	check(bodies.map(func(body): return body.events.drawn) == [12,12,9,11] and bodies.all(func(body): return body.events.input == body.events.drawn),"four bodies request input once per glyph; title message is not sent to T82")
	var continuations: Array = []
	for index in [8603,9213,10218,11122,11123]:
		var proof: Dictionary = _drive(records,index,_context({"timer_counter":0}),false)
		check(not proof.has("error"),"real post-delay message completes all request phases: " + str(index))
		if proof.has("error"): return
		check(proof.trace[-1].state.delay_units == 1 if index != 11123 else proof.trace[-1].state.timer_counter == 114,"post-delay source control updates final state: " + str(index))
		continuations.append(proof)
	reference = {"profile":Execute.PROFILE,"source_fingerprint":records.metadata().fingerprint,
		"package_sha256":Schema.digest(FileAccess.get_file_as_bytes(fixture.package)),"package_content_lock":package.content_lock,"bodies":bodies,"continuations":continuations,
		"probe_schedule":"one tick only while waiting; zero-tick draw/input acknowledgement; input action 0",
		"initial_skip_and_timer_are_probe_inputs":true,"opening_caller_executed":false,"excluded_title_pc":13}
