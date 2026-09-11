# SPDX-License-Identifier: MIT
extends SceneTree
const Caller = preload("res://src/native_pal98_dialogue_caller.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Package = preload("res://src/native_package.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var failed: int = 0
var reference: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4; var bytes = _zero(size); bytes.encode_u32(0,size)
	for i in range(chunks.size()): size += chunks[i].size(); bytes.encode_u32((i + 1) * 4,size)
	for chunk in chunks: bytes.append_array(chunk)
	return bytes

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
		"fingerprint":identity,"files":entries,"label":"Synthetic dialogue caller","license":"CC0-1.0","redistributable":true,"provenance":{"status":"synthetic"}},files,Schema.new()),"synthetic caller source admitted")
	return source.open_records()

func _context(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"local_x":101,"local_y":102,"title_x":12,"title_y":8,"origin_x":44,"origin_y":26,"mode":1,
		"line_count":0,"boxed_count":0,"draw_x":201,"draw_y":202,"icon":2,"skip_word":0,"delay_units":1,"input_action":99,
		"capture_gate":1,"restore_gate":0,"colours":[79,45,26,141],"timer_counter":0}
	result.merge(overrides,true); return result

func _normal(result: Dictionary) -> Dictionary:
	if result.has("error"): return result
	var request: Dictionary = result.request.duplicate(true)
	if request.has("nul_terminated_bytes"):
		request.nul_terminated_bytes_hex = request.nul_terminated_bytes.hex_encode(); request.erase("nul_terminated_bytes")
	return {"state":result.state.duplicate(true),"request":request}

func _drive(records, result: Dictionary, bounded_action: int = 0) -> Dictionary:
	var trace: Array = [_normal(result)]; var counts: Dictionary = {}
	for budget in range(8192):
		if result.has("error") or result.request.kind == "return": return {"result":result,"trace":trace,"counts":counts}
		var kind: String = result.request.kind; var event: Dictionary
		match kind:
			"capture_background": event = {"kind":"captured"}
			"restore_background": event = {"kind":"restored"}
			"draw_dialogue_box": event = {"kind":"box_drawn"}
			"draw_dialogue_icon","draw_glyph","draw_string": event = {"kind":"drawn"}
			"wait": event = {"kind":"tick"}
			_: event = {"kind":"input","action":2 if result.request.get("model") == "until_nonzero" else bounded_action if result.request.get("model") == "bounded_clear" else 0}
		counts[kind] = counts.get(kind,0) + 1
		result = Caller.step(records,result.state,event); trace.append(_normal(result))
	return {"result":{"error":"caller budget exceeded"},"trace":trace,"counts":counts}

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.dir_exists_absolute(args[1]): push_error("Expected source-window report and fresh output"); quit(2); return
	DirAccess.make_dir_recursive_absolute(args[1])
	var records = _records(["AB".to_ascii_buffer(),":".to_ascii_buffer(),PackedByteArray([0xa1,0x47]),PackedByteArray([0xa3,0xba]),PackedByteArray(),"ABC".to_ascii_buffer(),"$00A~00".to_ascii_buffer(),"x".repeat(256).to_ascii_buffer(),"$".to_ascii_buffer()])
	var seed: Dictionary = _context({"line_count":5,"boxed_count":7,"mode":9,"colours":[1,2,3,4],"skip_word":-1,"delay_units":27})
	var entered: Dictionary = Caller.enter_trigger_context(seed)
	check(entered.context.mode == 1 and entered.context.colours == [79,45,26,141] and entered.context.line_count == 0 and entered.context.boxed_count == 0,"trigger entry applies recovered fields once")
	check(entered.context.local_x == 101 and entered.context.local_y == 102 and entered.context.skip_word == -1 and entered.context.delay_units == 27 and seed.line_count == 5,"trigger entry preserves uninitialized fields and input context")
	for index in [1,2,3]:
		var title: Dictionary = Caller.begin_message(records,index,_context())
		check(title.request.kind == "draw_string" and title.request.palette_word == 140 and title.request.x == 12 and title.request.y == 8,"all recovered title suffix forms, including one-byte colon: " + str(index))
		var done: Dictionary = Caller.step(records,title.state,{"kind":"drawn"})
		check(done.request.kind == "return" and done.state.context.line_count == 0 and done.state.context.local_y == 26 and done.state.context.draw_x == 201,"title has no T82 cursor/line/spacing side effects")
	var body: Dictionary = _drive(records,Caller.begin_instruction(records,1,_context({"mode":3})))
	check(not body.result.has("error") and body.counts.draw_glyph == 2 and body.result.state.context.local_y == 42 and body.result.state.context.line_count == 1,"mode3 uses ordinary T82 body and sixteen-pixel spacing")
	check(body.result.state.context.local_x == 44 and body.result.state.context.draw_x == 60 and body.result.state.context.draw_y == 26,"T258 line origin remains separate from advanced T82 cursor")
	var zero_mode: Dictionary = _drive(records,Caller.begin_message(records,1,_context({"mode":0})))
	check(zero_mode.counts.draw_glyph == 1 and zero_mode.result.state.context.local_y == 44,"mode0 colon is ordinary body with eighteen-pixel spacing")
	var timed: Dictionary = _drive(records,Caller.begin_message(records,6,_context({"mode":0})))
	check(timed.result.state.context.line_count == 0 and timed.result.state.context.local_y == 44,"body tilde clearing is not undone by caller line increments")
	for origin_y in [100,101]:
		var mode9: Dictionary = Caller.begin_message(records,0,_context({"mode":9,"origin_y":origin_y}))
		check(mode9.request.x == (72 if origin_y == 100 else 44) and mode9.request.y == origin_y and mode9.request.palette_word == 79,"mode9 condition changes X offset, not Y: " + str(origin_y))
		mode9 = Caller.step(records,mode9.state,{"kind":"drawn"})
		check(mode9.state.context.origin_y == origin_y + 16 and mode9.state.context.local_y == origin_y + 16 and mode9.state.context.line_count == 0,"mode9 advances global originY and localY without adding a line")
	check(Caller.begin_message(records,1,_context({"mode":9})).request.palette_word == 140,"title branch precedes mode9")
	var boxed: Dictionary = Caller.begin_message(records,5,_context({"mode":10,"boxed_count":2}))
	check(boxed.request.kind == "draw_dialogue_box" and boxed.request.x == 36 and boxed.request.half_length == 1 and boxed.request.shadow_enabled_word == 0,"boxed mode centers by truncated half byte length and passes the Box shadow flag")
	boxed = Caller.step(records,boxed.state,{"kind":"box_drawn"})
	check(boxed.request.kind == "draw_string" and boxed.request.x == 42 and boxed.request.y == 34 and boxed.request.palette_word == 64 and boxed.request.shadow_word == 3,"box precedes offset whole-string draw with recovered colour and shadow word")
	boxed = Caller.step(records,boxed.state,{"kind":"drawn"})
	check(boxed.state.context.local_y == 44 and boxed.state.context.boxed_count == 3 and boxed.state.context.line_count == 3,"boxed Y and counter advance in order; line count copies boxed count")
	check(Caller.begin_message(records,1,_context({"mode":11})).request.kind == "draw_dialogue_box","mode>=10 precedes title predicate")
	check(Caller.begin_message(records,4,_context({"mode":10})).request.half_length == 0,"boxed empty text never enters the title negative-index predicate")
	for mode in [0,1,9]: check(Caller.begin_message(records,4,_context({"mode":mode})).diagnostic.code == "empty_message_title_read_unimplemented","empty caller predicate remains unclosed even when Boolean title condition would be false")
	var overflow: Dictionary = Caller.begin_message(records,0,_context({"line_count":4,"boxed_count":2,"capture_gate":7,"restore_gate":8,"skip_word":-1}))
	check(overflow.request.kind == "draw_dialogue_icon" and overflow.state.context.skip_word == 0 and overflow.request.x == 201 and overflow.request.y == 202,"overflow starts IconWait at old global glyph cursor and clears skip")
	overflow = Caller.step(records,overflow.state,{"kind":"drawn"})
	check(overflow.request.model == "until_nonzero" and overflow.state.context.input_action == 0,"nonzero-input helper clears its own action after icon drawing")
	overflow = Caller.step(records,overflow.state,{"kind":"input","action":0})
	check(overflow.state.context.line_count == 4,"zero input leaves overflow wait pending")
	overflow = Caller.step(records,overflow.state,{"kind":"input","action":-2})
	check(overflow.request.kind == "restore_background" and overflow.state.context.line_count == 0 and overflow.state.context.boxed_count == 2 and overflow.state.context.input_action == -2,"nonzero input clears line but preserves boxed counter")
	overflow = Caller.step(records,overflow.state,{"kind":"restored"})
	check(overflow.request.kind == "capture_background" and overflow.state.context.capture_gate == 0 and overflow.state.context.restore_gate == 0 and overflow.state.context.local_y == 26,"restore clears both gates before line-zero origin copy and capture")
	overflow = Caller.step(records,overflow.state,{"kind":"captured"})
	check(overflow.request.kind == "draw_glyph" and overflow.state.context.capture_gate == 0 and overflow.state.context.boxed_count == 2,"capture does not set gate flags or erase boxed counter")
	var clear: Dictionary = Caller.begin_clear(records,_context({"mode":0,"line_count":-1,"skip_word":-1,"restore_gate":1}))
	check(clear.request.model == "until_nonzero" and clear.state.context.skip_word == 0,"mode0 ClearText still waits for input without drawing an icon")
	clear = Caller.step(records,clear.state,{"kind":"input","action":2})
	check(clear.request.kind == "return" and clear.state.context.restore_gate == 1,"ordinary ClearText path does not restore solely because restore_gate is nonzero")
	var immediate: Dictionary = Caller.begin_clear(records,_context({"skip_word":-1}))
	check(immediate.request.kind == "return" and immediate.state.context.skip_word == -1 and immediate.state.context.input_action == 99,"empty ClearText only clears its two counts")
	var bounded: Dictionary = _drive(records,Caller.begin_clear(records,_context({"boxed_count":2,"timer_counter":7,"skip_word":-1})))
	check(bounded.counts.poll_input == 160 and bounded.counts.wait == 159 and bounded.result.state.context.timer_counter == 0,"160-poll timeout performs 160 wtime calls; first can consume carried counter without a tick")
	check(bounded.result.state.context.boxed_count == 0 and bounded.result.state.context.skip_word == -1 and bounded.result.state.context.input_action == 99,"timed clear preserves skip and nonzero-helper action field")
	var early: Dictionary = Caller.begin_clear(records,_context({"boxed_count":-1,"restore_gate":1,"skip_word":-1}))
	early = Caller.step(records,early.state,{"kind":"input","action":5})
	check(early.request.kind == "restore_background" and early.state.context.boxed_count == -1 and early.state.context.skip_word == -1,"timed clear checks restore gate after early input, before count reset")
	early = Caller.step(records,early.state,{"kind":"restored"})
	check(early.request.kind == "return" and early.state.context.boxed_count == 0 and early.state.context.restore_gate == 0,"timed clear completes count resets after acknowledged restore")
	var overflow_y: Dictionary = _drive(records,Caller.begin_message(records,0,_context({"origin_y":32760})))
	check(overflow_y.result.diagnostic.code == "dialogue_coordinate_i2_overflow" and not overflow_y.result.has("state"),"post-body local Y overflow diagnoses without publishing a candidate")
	check(Caller.begin_message(records,7,_context()).diagnostic.code == "message_length_u1_unimplemented","oversized source stays explicit")
	check(Caller.begin_message(records,0,_context({"colours":[1,2,3]})).has("error"),"incomplete caller context is rejected")
	check(Caller.step(records,immediate.state,{"kind":"tick"}).diagnostic.code == "dialogue_already_complete","completed caller cannot accept more events")
	_rejections(records)
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(args[0])); var package = Package.new()
	check(package.load_package(fixture.package),"ordinary source package loads for caller probes")
	if package.pal98_sources != null: _real(package.pal98_sources.open_records(),fixture)
	_synthetic_traces(records)
	var file = FileAccess.open(args[1].path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failed == 0,"failed":failed,"checks":checks,"reference":reference,
		"host_side_effects_acknowledged_only":true,"original_trigger_executed":false,"original_gameplay":false,"human_acceptance":false},"\t")); file.close()
	print("PAL98 dialogue caller: ",checks.size()," checks; ",failed," failed")
	quit(0 if failed == 0 else 1)

func _rejections(records) -> void:
	var invalid: Dictionary = Caller.begin_instruction(records,9,_context())
	var expected: Dictionary = records.message_for_instruction(9)
	check(invalid.diagnostic.code == "truncated_text_parameter" and invalid.diagnostic.instruction_index == 9 and invalid.diagnostic.instruction_source == expected.instruction_source and invalid.diagnostic.instruction_words == expected.instruction_words and invalid.diagnostic.error_byte_offset == expected.source.byte_offset and not invalid.has("state"),"FFFF lexical failure retains instruction receipt and exact source byte")
	var pending: Dictionary = Caller.begin_instruction(records,1,_context({"origin_x":32760,"delay_units":0}))
	invalid = Caller.step(records,pending.state,{"kind":"drawn"})
	expected = records.message_for_instruction(1)
	check(invalid.diagnostic.code == "text_coordinate_i2_overflow" and invalid.diagnostic.instruction_index == 1 and invalid.diagnostic.instruction_source == expected.instruction_source and invalid.diagnostic.instruction_words == expected.instruction_words and invalid.diagnostic.phase == "after_glyph_wait" and not invalid.has("state"),"FFFF post-draw failure retains child phase and outer instruction identity")
	check(pending.state.body.x == 32760 and pending.state.body.phase == "draw","failed step leaves its input candidate detached; this does not undo host drawing")
	pending = Caller.begin_instruction(records,2,_context({"mode":9}))
	var altered: Dictionary = pending.state.duplicate(true); altered.phase = "mode9"
	invalid = Caller.step(records,altered,{"kind":"drawn"})
	check(invalid.diagnostic.code == "invalid_dialogue_phase" and not invalid.has("state"),"a mode9 title cannot be resumed as a mode9 body")
	pending = Caller.begin_instruction(records,1,_context())
	for mode in [9,10]:
		altered = pending.state.duplicate(true); altered.context.mode = mode
		invalid = Caller.step(records,altered,{"kind":"drawn"})
		check(invalid.diagnostic.code == "invalid_dialogue_phase" and not invalid.has("state"),"ordinary body rejects incompatible mode: " + str(mode))
	altered = pending.state.duplicate(true); altered.body.instruction_index = -1
	check(Caller.step(records,altered,{"kind":"drawn"}).diagnostic.code == "dialogue_body_mismatch","nested body cannot discard outer instruction identity")
	for context in [_context({"mode":10,"origin_y":32760}),_context({"mode":10,"origin_x":32762})]:
		pending = Caller.begin_instruction(records,5,context) # Empty boxed message keeps the supplied X.
		altered = pending.state.duplicate(true); altered.phase = "box_text"
		invalid = Caller.step(records,altered,{"kind":"drawn"})
		check(invalid.diagnostic.code == "invalid_dialogue_phase" and not invalid.has("state"),"boxed text admission rechecks checked I2 draw offsets")
	pending = Caller.begin_instruction(records,1,_context({"mode":9,"origin_y":100}))
	altered = pending.state.duplicate(true); altered.context.local_x = 32760
	check(Caller.step(records,altered,{"kind":"drawn"}).diagnostic.code == "invalid_dialogue_phase","mode9 admission rechecks its conditional X offset")
	check(Caller.begin_instruction(records,-1,_context()).diagnostic.table == "scripts","negative instruction entry is diagnosed as an instruction source")

func _real(records, fixture: Dictionary) -> void:
	var context: Dictionary = _context({"mode":0,"origin_x":80,"origin_y":40,"capture_gate":0})
	var messages: Array = []
	for pc in [10,13,14,16,17]:
		if pc == 13: context.merge({"mode":2,"title_x":12,"title_y":108,"origin_x":44,"origin_y":126},true)
		if pc == 16: context.capture_gate = 0; context.restore_gate = 0 # Explicit earlier 008E host effect; not executed here.
		var proof: Dictionary = _drive(records,Caller.begin_instruction(records,pc,context))
		check(not proof.result.has("error") and proof.result.request.kind == "return","real caller source completes with explicit host acknowledgements: PC" + str(pc))
		if proof.result.has("error"): return
		context = proof.result.state.context.duplicate(true)
		messages.append({"pc":pc,"trace":proof.trace,"counts":proof.counts,"source":proof.result.source,
			"instruction_source":proof.result.instruction_source,"instruction_words":proof.result.instruction_words})
	check(messages.map(func(row): return row.trace[-1].state.context.local_y) == [58,126,142,142,158],"real caller keeps corrected local Y sequence across title, tilde and body")
	check(messages.map(func(row): return row.trace[-1].state.context.origin_y) == [40,126,126,126,126],"ordinary opening bodies never advance global originY")
	check(messages.map(func(row): return row.trace[-1].state.context.line_count) == [0,0,0,1,0],"real opening line-count sequence has no overflow confirmation")
	check(messages[1].counts.draw_string == 1 and not messages[1].counts.has("draw_glyph"),"opening title is actually dispatched separately from T82")
	reference = {"source_fingerprint":fixture.fingerprint,"package_sha256":FileAccess.get_sha256(fixture.package),"messages":messages,
		"initial_context":_context({"mode":0,"origin_x":80,"origin_y":40,"capture_gate":0}),"mode_setup_and_008e_injected":true}

func _synthetic_traces(records) -> void:
	var cases: Array = [
		{"index":1},{"index":2},{"index":3},{"index":1,"context":{"mode":0}},
		{"index":0,"context":{"mode":3}},
		{"index":0,"context":{"mode":9,"origin_y":100}},
		{"index":0,"context":{"mode":9,"origin_y":101}},
		{"index":1,"context":{"mode":9}},
		{"index":5,"context":{"mode":10,"boxed_count":2}},
		{"index":1,"context":{"mode":11}},
		{"index":4,"context":{"mode":10}},
		{"index":0,"context":{"line_count":4,"boxed_count":2,"capture_gate":7,"restore_gate":8,"skip_word":-1}},
		{"index":0,"context":{"mode":0,"line_count":4}},
		{"operation":"clear","context":{"mode":0,"line_count":-1,"skip_word":-1,"restore_gate":1}},
		{"operation":"clear","context":{"line_count":3}},
		{"operation":"clear","context":{"skip_word":-1}},
		{"operation":"clear","context":{"boxed_count":2,"timer_counter":7,"skip_word":-1}},
		{"operation":"clear","context":{"boxed_count":-1,"restore_gate":1,"skip_word":-1},"bounded_action":5},
	]
	var probes: Array = []
	for index in range(cases.size()):
		var spec: Dictionary = cases[index]; var context: Dictionary = _context(spec.get("context",{}))
		var operation: String = spec.get("operation","message"); var message_index: int = spec.get("index",-1)
		var result: Dictionary = Caller.begin_clear(records,context) if operation == "clear" else Caller.begin_message(records,message_index,context)
		var proof: Dictionary = _drive(records,result,spec.get("bounded_action",0))
		check(not proof.result.has("error"),"synthetic caller trace completes: " + str(index))
		if proof.result.has("error"): continue
		var payload: PackedByteArray = records.message_bytes(message_index).value.bytes if operation == "message" else PackedByteArray()
		probes.append({"operation":operation,"message_index":message_index,"context":context,"bytes_hex":payload.hex_encode(),
			"bounded_action":spec.get("bounded_action",0),"trace":proof.trace,"counts":proof.counts,"source":proof.result.source})
	reference.synthetic_cases = probes
