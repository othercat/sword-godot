# SPDX-License-Identifier: MIT
extends SceneTree
const Text = preload("res://src/native_pal98_text_tokens.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Package = preload("res://src/native_package.gd")
const Schema = preload("res://src/native_schema.gd")
const Reader = preload("res://src/native_json.gd")
var checks: Array = []
var failed: int = 0
var output: String
var reference: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: push_error("Expected source-window report and fresh output"); quit(2); return
	output = args[1]
	if DirAccess.dir_exists_absolute(output): push_error("Use a fresh output directory"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	_synthetic()
	var reader = Reader.new(); var fixture = reader.decode(FileAccess.get_file_as_bytes(args[0]))
	if not fixture is Dictionary or not reader.error.is_empty(): push_error("Invalid source-window report"); quit(2); return
	_real(fixture)
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "reference": reference,
		"text_plan_only": true, "original_gameplay": false, "human_acceptance": false}, "\t")); file.close()
	print("PAL98 byte text plans: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4; var bytes = _zero(size); bytes.encode_u32(0,size)
	for i in range(chunks.size()): size += chunks[i].size(); bytes.encode_u32((i + 1) * 4, size)
	for chunk in chunks: bytes.append_array(chunk)
	return bytes

func _records(messages: Array, encoding: String = "gbk"):
	var offsets = _zero((messages.size() + 1) * 4); var payload = PackedByteArray()
	var scripts = _zero((messages.size() + 1) * 8)
	for i in range(messages.size()):
		payload.append_array(messages[i]); offsets.encode_u32((i + 1) * 4, payload.size())
		scripts.encode_u16((i + 1) * 8, 0xffff); scripts.encode_u16((i + 1) * 8 + 2, i)
	var files: Dictionary = {"data": _mkf([_zero(0),_zero(0),_zero(0),_zero(900)]),
		"sss": _mkf([_zero(0),_zero(16),_zero(14),offsets,scripts]), "words": _zero(10), "messages": payload}
	var hashes: Dictionary = {}; var entries: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(files[role])
	var identity: String = Sources.fingerprint(encoding, hashes)
	for role in Sources.FILES:
		entries[role] = {"path": "content/pal98-sources/" + identity + "/" + Sources.FILES[role], "sha256": hashes[role], "size_bytes": files[role].size()}
	var component: Dictionary = {"schema": Sources.SCHEMA, "kind": "content", "dialect": "pal98-win95", "text_encoding": encoding,
		"fingerprint": identity, "files": entries, "label": "Synthetic text", "license": "CC0-1.0", "redistributable": true, "provenance": {"status": "synthetic"}}
	var source = Sources.new(); check(source.load_source(component, files, Schema.new()), "synthetic text source admits complete bytes")
	return source.open_records()

func _normal(plan: Dictionary) -> Dictionary:
	var tokens: Array = []
	for token in plan.tokens:
		var value: Dictionary = token.duplicate(true)
		if value.has("bytes"): value.bytes_hex = value.bytes.hex_encode(); value.erase("bytes")
		tokens.append(value)
	return {"tokens": tokens, "consumed_bytes": plan.consumed_bytes, "remaining_hex": plan.remaining_bytes.hex_encode(), "termination": plan.termination}

func _synthetic() -> void:
	check(Text.read_message(null,0).diagnostic.code == "not_loaded" and Text.read_instruction(null,1).diagnostic.code == "not_loaded", "unloaded text requests are diagnosed")
	var messages: Array = [PackedByteArray(), "ABC".to_ascii_buffer(), PackedByteArray([0x81,34,0x81,36,0x81,126,0x81,40,0x81,41]),
		PackedByteArray([0x80,0,127]), PackedByteArray([34,36,49,48,65,40,41,126,51,48,83]), PackedByteArray([0x81]),
		"$".to_ascii_buffer(), "$1".to_ascii_buffer(), "A$x1".to_ascii_buffer(), "~0x".to_ascii_buffer(),
		"A".repeat(255).to_ascii_buffer(), "A".repeat(256).to_ascii_buffer(), "~30$99".to_ascii_buffer(), "~30$".to_ascii_buffer()]
	var records = _records(messages)
	var empty: Dictionary = Text.read_message(records,0)
	check(empty.tokens.is_empty() and empty.termination == "end" and empty.consumed_bytes == 0, "empty message has no implicit wait or confirmation")
	var ascii: Dictionary = Text.read_message(records,1)
	check(ascii.tokens.size() == 3 and ascii.tokens.all(func(t): return t.kind == "glyph" and t.advance_pixels == 8 and t.size_bytes == 1 and not t.loader_zero), "single bytes advance eight pixels without decoding")
	var dbcs: Dictionary = Text.read_message(records,2)
	check(dbcs.tokens.size() == 5 and dbcs.tokens.all(func(t): return t.kind == "glyph" and t.advance_pixels == 16 and t.size_bytes == 2), "all five ASCII controls remain ordinary bytes when they are DBCS trails")
	var boundary: Dictionary = Text.read_message(records,3)
	check(boundary.tokens.size() == 3 and boundary.tokens[0].bytes == PackedByteArray([128]) and boundary.tokens[1].bytes == PackedByteArray([0]), "0x80 and NUL are preserved single bytes in original comparison")
	var controls: Dictionary = Text.read_message(records,4)
	check(controls.tokens.map(func(t): return t.kind) == ["swap_colours","character_delay","glyph","select_icon","select_icon","timed_return"], "exactly five control families are recognized in source order")
	check(controls.tokens[1].units == 14 and controls.tokens[3].index == 2 and controls.tokens[4].index == 1 and controls.tokens[5].units == 43, "control parameters retain source meanings and nominal tick values")
	check(controls.consumed_bytes == 10 and controls.remaining_bytes == PackedByteArray([83]) and controls.termination == "timed_return", "timed return stops before unconsumed source suffix")
	var lead: Dictionary = Text.read_message(records,5)
	check(lead.tokens.size() == 1 and lead.tokens[0].bytes == PackedByteArray([129,0]) and lead.tokens[0].loader_zero and lead.tokens[0].size_bytes == 1 and lead.consumed_bytes == 1, "final DBCS lead reads explicit loader zero without inventing a source byte")
	for index in [6,7]:
		var result: Dictionary = Text.read_message(records,index)
		check(result.diagnostic.code == "truncated_text_parameter" and not result.has("tokens"), "truncated parameter refuses partial plan: " + str(index))
	for index in [8,9]:
		var result: Dictionary = Text.read_instruction(records,index + 1)
		check(result.diagnostic.code == "nondecimal_text_parameter_unimplemented" and not result.has("tokens") and result.diagnostic.instruction_source.record_index == index + 1, "unsupported parameter retains referring PC: " + str(index))
	var parameter: Dictionary = Text.read_message(records,8)
	check(parameter.diagnostic.relative_byte_offset == 1 and parameter.diagnostic.error_byte_offset == records.message_bytes(8).source.byte_offset + 1, "parameter diagnostic identifies source byte without changing message range")
	check(parameter.diagnostic.offset_directory_source == records.message_bytes(8).offset_directory_source and controls.offset_directory_source == records.message_bytes(4).offset_directory_source, "successful and failed plans retain both SSS3 boundary addresses")
	check(Text.read_message(records,10).tokens.size() == 255, "original U1 maximum message length is supported")
	var long_message: Dictionary = Text.read_instruction(records,12)
	check(long_message.diagnostic.code == "message_length_u1_unimplemented" and long_message.diagnostic.size_bytes == 256 and long_message.diagnostic.instruction_source.record_index == 12 and records.message_bytes(11).value.bytes.size() == 256, "long message remains readable but needs a separate execution owner")
	var returned: Dictionary = Text.read_message(records,12)
	check(returned.tokens.size() == 1 and returned.tokens[0].units == 43 and returned.remaining_bytes == "$99".to_ascii_buffer(), "speed control after timed return is not consumed")
	check(Text.read_message(records,13).remaining_bytes == "$".to_ascii_buffer(), "malformed control in unconsumed suffix does not reject completed prefix")
	check(Text.read_instruction(records,0).diagnostic.code == "not_message_instruction" and Text.read_instruction(records,100).diagnostic.code == "index_out_of_range", "wrong and missing instructions preserve source diagnostics")
	controls.tokens[1].units = 999; controls.remaining_bytes[0] = 0
	check(Text.read_message(records,4).tokens[1].units == 14 and records.message_bytes(4).value.bytes[-1] == 83, "plans and source records do not alias caller mutations")
	var values: Array = [0,1,2,3,5,7,10,30,40,60,99]; var expected: Array = [0,1,3,4,7,10,14,43,57,86,141]
	var delays: Array = []
	for number in values: delays.append(("$%02d~%02d" % [number,number]).to_ascii_buffer())
	var delay_records = _records(delays, "big5")
	for i in range(values.size()):
		var plan: Dictionary = Text.read_message(delay_records,i)
		check(plan.tokens[0].units == expected[i] and plan.tokens[1].units == expected[i] and plan.text_encoding == "big5", "decimal timing vector with explicit Big5 source: " + str(values[i]))

func _real(fixture: Dictionary) -> void:
	var package = Package.new(); check(package.load_package(fixture.package), "ordinary locked source package loads for text consumer")
	if package.pal98_sources == null: push_error(package.error); return
	var records = package.pal98_sources.open_records(); var summary: Dictionary = records.table_summary()
	check(records.metadata().fingerprint == fixture.fingerprint, "loaded source identity matches the source-window report")
	var rows: Array = []; var unsupported: Array = []; var opening: Array = []; var suffixes: Array = []
	var token_count: int = 0; var controls: Dictionary = {"swap_colours":0,"character_delay":0,"timed_return":0,"icon1":0,"icon2":0}
	for index in range(summary.counts.messages):
		var plan: Dictionary = Text.read_message(records,index)
		if plan.has("error"):
			unsupported.append(plan); rows.append({"index":index,"code":plan.diagnostic.code}); continue
		var normalized: Dictionary = _normal(plan)
		rows.append({"index":index,"plan_sha256":Schema.digest(JSON.stringify(normalized,"",true,true).to_utf8_buffer())})
		token_count += plan.tokens.size()
		for token in plan.tokens:
			if token.kind == "select_icon": controls["icon" + str(token.index)] += 1
			elif controls.has(token.kind): controls[token.kind] += 1
		if index < 5: opening.append({"index":index,"source":plan.source,"offset_directory_source":plan.offset_directory_source,"plan":normalized})
		if not plan.remaining_bytes.is_empty(): suffixes.append({"index":index,"source_offset":plan.source.byte_offset + plan.consumed_bytes,"remaining_hex":plan.remaining_bytes.hex_encode()})
	check(rows.size() == 13862 and unsupported.size() == 1 and unsupported[0].diagnostic.record_index == 13513 and unsupported[0].diagnostic.code == "message_length_u1_unimplemented", "all source messages classified with one explicit long-message boundary")
	check(token_count == 116027 and controls == {"swap_colours":305,"character_delay":109,"timed_return":135,"icon1":10,"icon2":18}, "consumed token/control counts match independent byte scan")
	check(suffixes.map(func(row): return row.index) == [8603,9213,10218,11122,11123], "all five source suffixes after timed return remain unconsumed")
	check(opening.map(func(row): return row.plan.tokens.size()) == [14,4,14,9,12], "opening five message token counts match source")
	var first: Dictionary = Text.read_instruction(records,10)
	check(first.tokens[0].kind == "character_delay" and first.tokens[0].units == 14 and first.tokens[-1].kind == "timed_return" and first.tokens[-1].units == 43 and first.instruction_source.record_index == 10, "opening FFFF reaches parameterized text plan with exact instruction receipt")
	var broken: Dictionary = Text.read_instruction(records,44957)
	check(broken.diagnostic.code == "index_out_of_range" and broken.diagnostic.record_index == 13862 and broken.diagnostic.instruction_source.record_index == 44957, "original invalid FFFF retains message and referring instruction diagnosis")
	reference = {"package_sha256":Schema.digest(FileAccess.get_file_as_bytes(fixture.package)), "package_content_lock":package.content_lock,
		"source_fingerprint":records.metadata().fingerprint,"message_plans":rows,"unsupported":unsupported,"opening":opening,
		"unconsumed_suffixes":suffixes,"token_count":token_count,"controls":controls}
