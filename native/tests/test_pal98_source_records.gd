# SPDX-License-Identifier: MIT
extends SceneTree
const Sources = preload("res://src/native_pal98_sources.gd")
const Records = preload("res://src/native_pal98_source_records.gd")
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
	if args.size() != 2: push_error("Expected source-window report and fresh output directory"); quit(2); return
	output = args[1]
	if DirAccess.dir_exists_absolute(output): push_error("Use a fresh evidence directory"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	_synthetic()
	var reader = Reader.new(); var fixture = reader.decode(FileAccess.get_file_as_bytes(args[0]))
	if not fixture is Dictionary or not reader.error.is_empty(): push_error("Invalid source-window report"); quit(2); return
	_real(fixture)
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "reference": reference,
		"original_gameplay": false, "human_acceptance": false}, "\t")); file.close()
	print("PAL98 addressed source records: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _u16(words: Array) -> PackedByteArray:
	var bytes = _zero(words.size() * 2)
	for i in range(words.size()): bytes.encode_u16(i * 2, words[i])
	return bytes

func _u32(words: Array) -> PackedByteArray:
	var bytes = _zero(words.size() * 4)
	for i in range(words.size()): bytes.encode_u32(i * 4, words[i])
	return bytes

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4
	var bytes = _zero(size); bytes.encode_u32(0, size)
	for i in range(chunks.size()): size += chunks[i].size(); bytes.encode_u32((i + 1) * 4, size)
	for chunk in chunks: bytes.append_array(chunk)
	return bytes

func _descriptor(payloads: Dictionary, encoding: String = "gbk") -> Dictionary:
	var hashes: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(payloads[role])
	var identity: String = Sources.fingerprint(encoding, hashes); var files: Dictionary = {}
	for role in Sources.FILES:
		files[role] = {"path": "content/pal98-sources/" + identity + "/" + Sources.FILES[role], "sha256": hashes[role], "size_bytes": payloads[role].size()}
	return {"schema": Sources.SCHEMA, "kind": "content", "dialect": "pal98-win95", "text_encoding": encoding,
		"fingerprint": identity, "label": "Synthetic record views", "license": "CC0-1.0", "redistributable": true,
		"files": files, "provenance": {"status": "synthetic"}}

func _load(payloads: Dictionary, encoding: String = "gbk"):
	var source = Sources.new()
	check(source.load_source(_descriptor(payloads, encoding), payloads, Schema.new()), "synthetic source admission")
	return source

func _synthetic() -> void:
	check(Sources.new().open_records() == null, "unloaded source cannot produce record reader")
	var empty = Records.new()
	for result in [empty.instruction(0), empty.role_record(0), empty.scene(0), empty.word_bytes(0), empty.message_bytes(0), empty.message_tail(), empty.table_summary()]:
		check(result.get("diagnostic", {}).get("code") == "not_loaded", "unloaded record request gives diagnostic")
	var roles = _zero(900); roles.encode_u16((29 * 6 + 5) * 2, 0x8001); roles.encode_u16((74 * 6) * 2, 0xffff)
	var data: Array = [_zero(0), PackedByteArray([1,2,3]), _zero(0), roles]
	var events = _zero(64); events.encode_u16(0, 0xffff); events.encode_u16(62, 0x8000)
	var scenes = _u16([20,4,0,0, 12,65535,77,0, 999,888,777,2])
	var objects = _u16([1,2,3,4,5,6,7, 65535,32768,9,10,11,12,13])
	var scripts = _u16([0,1,2,3, 65535,65535,0x1234,0x8000, 0xeeee,4,5,6, 0x75,1,0,0])
	var sss: Array = [events, scenes, objects, _u32([0,3,3,7]), scripts]
	var words = _zero(20); words[0] = 0; words[1] = 0xff; words[9] = 0x20; words[19] = 0x81
	var payloads: Dictionary = {"data": _mkf(data), "sss": _mkf(sss), "words": words, "messages": PackedByteArray([0,0xff,0x20, 0x81,0,0xfe,0x20, 9,8])}
	var source = _load(payloads); var records = source.open_records()
	check(records != null, "admitted source exposes addressed reader")
	if records == null: return
	var counts: Dictionary = records.table_summary()
	check(counts.issues.is_empty() and counts.counts == {"events": 2, "scenes": 2, "objects": 2, "scripts": 4, "roles": 6, "words": 2, "messages": 3}, "scene count excludes terminal boundary")
	var role: Dictionary = records.role_record(5)
	check(role.value.words.size() == 75 and role.value.words[29] == 0x8001 and records.role_record(0).value.words[74] == 65535, "field-major role words preserve signed bit patterns and final field")
	check(role.source.first_word_offset == payloads.data.decode_u32(12) + 10 and role.source.word_stride_bytes == 12 and role.source.word_count == 75 and not role.source.has("size_bytes"), "role address declares separated WORDs instead of contiguous record")
	var first: Dictionary = records.scene_for_runtime_id(1); var second: Dictionary = records.scene(1)
	check(first.value == {"raw_index": 0, "map_word": 20, "enter_script_word": 4, "leave_script_word": 0, "event_start": 0, "event_end_exclusive": 0}, "runtime scene 1 resolves raw scene 0 and empty event range")
	check(second.value.event_start == 0 and second.value.event_end_exclusive == 2 and second.value.enter_script_word == 65535, "scene retains unexecuted entry word and uses next boundary")
	check(records.scene_record(2).value.words == [999,888,777,2] and records.scene_record(2).value.is_terminal_boundary, "terminal scene words retained without zeroing or interpreting map")
	check(records.scene(2).diagnostic.code == "terminal_scene_record", "terminal boundary cannot be played as scene")
	for id in [0,-1,65536]: check(records.scene_for_runtime_id(id).diagnostic.code == "runtime_scene_id", "invalid runtime scene word rejected: " + str(id))
	var event: Dictionary = records.event_record(1)
	check(event.value.words[15] == 0x8000 and event.source.byte_offset == payloads.sss.decode_u32(0) + 32 and event.source.size_bytes == 32, "event raw words and exact file offset")
	check(records.object_record(1).value.words == [65535,32768,9,10,11,12,13], "object words preserve all fourteen bytes")
	var instruction: Dictionary = records.instruction(1)
	check(instruction.value.words == [65535,65535,0x1234,0x8000] and instruction.value.opcode == 65535 and instruction.value.operands == [65535,0x1234,0x8000], "instruction words and operands retain full U2 range")
	check(records.instruction(0).value.opcode == 0 and records.instruction(2).value.opcode == 0xeeee, "zero PC and unknown opcode are inspectable data")
	check(instruction.source.byte_offset == payloads.sss.decode_u32(16) + 8, "instruction receipt addresses original SSS4 file bytes")
	check(records.word_bytes(0).value.bytes == words.slice(0,10) and records.word_bytes(1).value.bytes == words.slice(10), "word preserves NUL, invalid legacy bytes and spaces")
	check(records.message_bytes(0).value.bytes == PackedByteArray([0,255,32]) and records.message_bytes(1).value.bytes.is_empty(), "message boundaries preserve empty record and raw bytes")
	var message: Dictionary = records.message_bytes(2)
	check(message.value.bytes == PackedByteArray([129,0,254,32]) and message.source.byte_offset == 3 and message.source.size_bytes == 4, "message addresses exact M.MSG span")
	check(message.offset_directory_source.byte_offset == payloads.sss.decode_u32(12) + 8 and message.offset_directory_source.size_bytes == 8, "message receipt also addresses both SSS3 boundary entries")
	check(records.message_tail().value.bytes == PackedByteArray([9,8]), "unindexed tail is separate from final message")
	var bad_message: Dictionary = records.message_for_instruction(1)
	check(bad_message.diagnostic.code == "index_out_of_range" and bad_message.diagnostic.record_index == 65535 and bad_message.diagnostic.instruction_source.record_index == 1 and bad_message.diagnostic.instruction_words == [65535,65535,0x1234,0x8000], "broken FFFF reference retains message index and referring instruction address")
	check(records.message_for_instruction(2).diagnostic.code == "not_message_instruction", "message resolver does not reinterpret unknown opcode as text")
	for row in [["role_record",6],["role_record",-1],["event_record",2],["event_record",-1],["object_record",2],["scene_record",3],["instruction",4],["instruction",-1],["word_bytes",2],["message_bytes",3],["message_bytes",-1]]:
		var result: Dictionary = records.call(row[0], row[1])
		check(result.diagnostic.code == "index_out_of_range" and result.diagnostic.record_index == row[1] and result.diagnostic.fingerprint == source.metadata().fingerprint, "bad index has exact source diagnostic: " + row[0] + ":" + str(row[1]))
	role.value.words[29] = 0; event.value.words[15] = 0; instruction.value.words[0] = 0; message.value.bytes[0] = 0
	var metadata: Dictionary = records.metadata(); metadata.fingerprint = "changed"
	check(records.role_record(5).value.words[29] == 0x8001 and records.event_record(1).value.words[15] == 0x8000 and records.instruction(1).value.opcode == 65535 and records.message_bytes(2).value.bytes[0] == 129, "record arrays and raw byte views are detached")
	check(records.metadata().fingerprint == source.metadata().fingerprint, "metadata is detached")
	var old_fingerprint: String = records.metadata().fingerprint
	check(source.load_source(_descriptor(payloads, "big5"), payloads, Schema.new()), "caller source can be replaced")
	check(records.metadata().fingerprint == old_fingerprint and records.message_bytes(0).value.text_encoding == "gbk" and source.open_records().message_bytes(0).value.text_encoding == "big5", "old reader stays bound to whole old snapshot after source replacement")
	var shifted_data: Array = data.duplicate(true); shifted_data[0] = PackedByteArray([5,4,3,2,1]); shifted_data[3].encode_u16((29 * 6 + 5) * 2, 0x2222)
	var shifted_sss: Array = sss.duplicate(true); shifted_sss[0].append_array(_zero(32)); shifted_sss[4].encode_u16(8, 0xdddd)
	var shifted_payloads: Dictionary = payloads.duplicate(true); shifted_payloads.data = _mkf(shifted_data); shifted_payloads.sss = _mkf(shifted_sss); shifted_payloads.messages[0] = 0xaa
	check(source.load_source(_descriptor(shifted_payloads, "big5"), shifted_payloads, Schema.new()), "source replacement changes bytes and both MKF chunk starts")
	var shifted = source.open_records()
	check(records.instruction(1).value.opcode == 0xffff and shifted.instruction(1).value.opcode == 0xdddd and shifted.instruction(1).source.byte_offset == records.instruction(1).source.byte_offset + 32, "old and new instruction snapshots retain separate values and offsets")
	check(records.role_record(5).value.words[29] == 0x8001 and shifted.role_record(5).value.words[29] == 0x2222 and shifted.role_record(5).source.first_word_offset == records.role_record(5).source.first_word_offset + 5, "old and new role snapshots retain separate values and nonaligned chunk starts")
	check(records.message_bytes(0).value.bytes[0] == 0 and shifted.message_bytes(0).value.bytes[0] == 0xaa and records.metadata().fingerprint == old_fingerprint and shifted.metadata().fingerprint != old_fingerprint, "source replacement does not mix message bytes or fingerprints")
	check(not records.load_source(Sources.new()) and records.metadata().fingerprint == old_fingerprint and records.instruction(1).value.opcode == 65535, "failed reader replacement retains usable old snapshot")
	for defect in ["events-alignment", "scenes-alignment", "scenes-no-terminal", "scene-backward", "scene-outside"]:
		var changed: Array = sss.duplicate(true)
		match defect:
			"events-alignment": changed[0].append(1)
			"scenes-alignment": changed[1].append(1)
			"scenes-no-terminal": changed[1] = _zero(8)
			"scene-backward": changed[1].encode_u16(6,1)
			"scene-outside": changed[1].encode_u16(14,3)
		var bad_payloads: Dictionary = payloads.duplicate(true); bad_payloads.sss = _mkf(changed)
		var bad_source = _load(bad_payloads); var bad = bad_source.open_records()
		var result: Dictionary = bad.scene(0)
		check(result.has("error"), "target scene diagnoses malformed source: " + defect)
		check(bad.instruction(2).value.opcode == 0xeeee and bad_source.copy_bytes("sss") == bad_payloads.sss, "malformed scene does not drop source or hide independent instruction: " + defect)
		if defect == "scene-backward": check(bad.scene(1).has("value"), "unrelated valid scene survives another scene's backward range")
	var large: Array = sss.duplicate(true); large[4] = _zero(65536 * 8); large[4].encode_u16(65535 * 8, 0xeeee)
	var large_payloads: Dictionary = payloads.duplicate(true); large_payloads.sss = _mkf(large)
	var full = _load(large_payloads).open_records()
	check(full.instruction(65535).value.opcode == 0xeeee and full.instruction(65536).has("error"), "last U2 instruction is readable without wrap or out-of-range fetch")
	for offsets in [[0], [0,0], [0,0,0]]:
		var zero_sss: Array = sss.duplicate(true); zero_sss[3] = _u32(offsets)
		var zero_payloads: Dictionary = payloads.duplicate(true); zero_payloads.sss = _mkf(zero_sss); zero_payloads.messages = _zero(0)
		var zero_records = _load(zero_payloads).open_records()
		check(zero_records.table_summary().counts.messages == offsets.size() - 1 and zero_records.message_tail().value.bytes.is_empty(), "zero-byte M.MSG retains explicit directory count: " + str(offsets.size()))
		check(zero_records.message_bytes(0).has("error") if offsets.size() == 1 else zero_records.message_bytes(0).value.bytes.is_empty(), "missing message differs from present empty message: " + str(offsets.size()))
	var tail_sss: Array = sss.duplicate(true); tail_sss[3] = _u32([0])
	var tail_payloads: Dictionary = payloads.duplicate(true); tail_payloads.sss = _mkf(tail_sss)
	var only_tail = _load(tail_payloads).open_records()
	check(only_tail.table_summary().counts.messages == 0 and only_tail.message_bytes(0).has("error") and only_tail.message_tail().value.bytes == payloads.messages, "nonempty M.MSG with only zero boundary remains entirely unindexed tail")

func _real(fixture: Dictionary) -> void:
	var package = Package.new()
	check(package.load_package(fixture.package), "ordinary private ZIP package admitted for record consumer")
	if package.pal98_sources == null: push_error(package.error); return
	var source = package.pal98_sources; var records = source.open_records()
	var summary: Dictionary = records.table_summary()
	check(summary.issues.is_empty(), "real SSS0/SSS1 record shapes are available")
	if not summary.issues.is_empty(): return
	check(summary.counts == {"events": 5077, "scenes": 294, "objects": 565, "scripts": 44959, "roles": 6, "words": 565, "messages": 13862}, "locked baseline record counts")
	var hashes: Dictionary = {}; var scene_ranges: Array = []; var valid_ranges: bool = true; var broken_messages: Array = []
	for spec in [["events","event_record",0,summary.counts.events],["scenes","scene_record",1,summary.counts.scenes + 1],["objects","object_record",2,summary.counts.objects],["scripts","instruction",4,summary.counts.scripts]]:
		var bytes = PackedByteArray(); var addresses_ok: bool = true
		var original: PackedByteArray = source.copy_chunk("sss", spec[2]); var sss: PackedByteArray = source.copy_bytes("sss")
		var chunk_offset: int = sss.decode_u32(spec[2] * 4)
		for i in range(spec[3]):
			var row: Dictionary = records.call(spec[1], i)
			if row.has("error"): addresses_ok = false; break
			var raw: PackedByteArray = _u16(row.value.words)
			addresses_ok = addresses_ok and row.source.byte_offset == chunk_offset + bytes.size() and row.source.size_bytes == raw.size()
			bytes.append_array(raw)
			if spec[0] == "scripts" and row.value.opcode == 0xffff:
				var resolved: Dictionary = records.message_for_instruction(i)
				if resolved.has("error"): broken_messages.append(resolved)
		check(addresses_ok and bytes == original, "all addressed records reconstruct SSS table: " + spec[0])
		hashes[spec[0]] = Schema.digest(bytes)
	var data3 = _zero(900); var role_rows: Array = []
	for role in range(6):
		var row: Dictionary = records.role_record(role); role_rows.append({"role_index": role, "source": row.source})
		for field in range(75): data3.encode_u16((field * 6 + role) * 2, row.value.words[field])
	check(data3 == source.copy_chunk("data",3), "all six role views reconstruct original field-major DATA3")
	hashes.roles = Schema.digest(data3)
	for i in range(summary.counts.scenes):
		var row: Dictionary = records.scene(i)
		if row.has("error"): valid_ranges = false; scene_ranges.append(row)
		else: scene_ranges.append(row.value)
	check(valid_ranges, "all locked baseline scene event ranges are bounded")
	var word_bytes = PackedByteArray(); var messages = PackedByteArray(); var indexed_message_bytes: int = 0
	for i in range(summary.counts.words): word_bytes.append_array(records.word_bytes(i).value.bytes)
	var message_offsets: Array = []; var empty_messages: int = 0
	for i in range(summary.counts.messages):
		var row: Dictionary = records.message_bytes(i); var bytes: PackedByteArray = row.value.bytes
		message_offsets.append(row.source.byte_offset); messages.append_array(bytes)
		if bytes.is_empty(): empty_messages += 1
	indexed_message_bytes = messages.size(); message_offsets.append(indexed_message_bytes)
	var tail: Dictionary = records.message_tail(); messages.append_array(tail.value.bytes)
	check(word_bytes == source.copy_bytes("words"), "all fixed-width words reconstruct WORD.DAT without decoding")
	check(messages == source.copy_bytes("messages") and tail.value.bytes.size() == 20, "all message spans plus distinct tail reconstruct M.MSG")
	check(_u32(message_offsets) == source.copy_chunk("sss",3), "message receipts reconstruct every original SSS3 offset")
	hashes.words = Schema.digest(word_bytes); hashes.messages = Schema.digest(messages); hashes.message_offsets = Schema.digest(_u32(message_offsets))
	var opening: Dictionary = records.scene_for_runtime_id(1)
	check(opening.value == {"raw_index": 0, "map_word": 20, "enter_script_word": 4, "leave_script_word": 0, "event_start": 0, "event_end_exclusive": 0}, "source opening resolves map20/enter4 without authored scene conversion")
	var entries: Array = []
	for pc in range(4,20): entries.append(records.instruction(pc))
	check(entries[0].value.words == [0x46,0x20,0x40,0] and entries[4].value.words == [5,0,0,0] and entries[14].value.words == [0x59,2,0,0], "real opening instructions preserve recovered entry, wait and scene request")
	var message_source: Dictionary = records.message_bytes(0).source
	check(message_source.fingerprint == fixture.fingerprint, "text span shares the same locked source identity as scripts")
	var opening_message: Dictionary = records.message_for_instruction(10)
	check(opening_message.value.bytes == records.message_bytes(0).value.bytes and opening_message.instruction_source.record_index == 10 and opening_message.instruction_words == [65535,0,0,0], "real first FFFF resolves raw message zero with referring instruction receipt")
	check(broken_messages.size() == 1 and broken_messages[0].diagnostic.code == "index_out_of_range" and broken_messages[0].diagnostic.record_index >= summary.counts.messages, "known unexecuted out-of-range message stays in source and is locally diagnosed")
	reference = {"package_sha256": Schema.digest(FileAccess.get_file_as_bytes(fixture.package)), "package_content_lock": package.content_lock,
		"source_fingerprint": source.metadata().fingerprint, "record_counts": summary.counts, "reconstructed_sha256": hashes,
		"opening_scene": opening, "opening_instructions": entries, "scene_ranges": scene_ranges, "roles": role_rows,
		"indexed_message_bytes": indexed_message_bytes, "empty_messages": empty_messages, "tail_source": tail.source,
		"broken_message_references": broken_messages}
