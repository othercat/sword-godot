# SPDX-License-Identifier: MIT
extends SceneTree
const Codec = preload("res://src/native_pal98_text_codec.gd")
const Package = preload("res://src/native_package.gd")
const Schema = preload("res://src/native_schema.gd")
const Reader = preload("res://src/native_json.gd")
var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)

func read(path: String):
	var parser = Reader.new(); var value = parser.decode(FileAccess.get_file_as_bytes(path))
	assert(parser.error.is_empty()); return value

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3 or DirAccess.dir_exists_absolute(args[2]): push_error("Expected source-window report, exported oracle directory and fresh output"); quit(2); return
	DirAccess.make_dir_recursive_absolute(args[2])
	var reference = read(args[1].path_join("reference.json")); var gui = read(args[0]); var codec = Codec.new()
	check(not codec.open("GBK") and codec.metadata().is_empty(),"encoding is explicit; aliases are not silently guessed")
	check(codec.decode(PackedByteArray()).diagnostic.code == "text_codec_not_loaded","unloaded codec refuses data")
	for row in reference.tables:
		check(codec.open(row.encoding),"bundled strict table opens: " + row.encoding)
		var oracle: PackedByteArray = FileAccess.get_file_as_bytes(args[1].path_join("oracle/" + row.file))
		check(oracle.size() == 65792 * 12 and Schema.digest(oracle) == row.oracle_sha256,"framework oracle length and identity: " + row.encoding)
		var errors: Array = []; var success: int = 0; var invalid: int = 0
		for index in range(65792):
			var input: PackedByteArray = PackedByteArray([index]) if index < 256 else PackedByteArray([(index - 256) >> 8,(index - 256) & 255])
			var result: Dictionary = codec.decode(input); var count: int = oracle.decode_u32(index * 12)
			var ok: bool
			if count == 4294967295:
				invalid += 1; ok = result.has("error") and result.diagnostic.relative_byte_offset == oracle.decode_u32(index * 12 + 4)
			else:
				success += 1; var points: PackedInt32Array = PackedInt32Array()
				for point in range(count): points.append(oracle.decode_u32(index * 12 + 4 + point * 4))
				ok = not result.has("error") and result.codepoints == points
				# A Godot String cannot preserve NUL. Such valid decoded data has
				# a lossless scalar/UTF-8 result and an explicit projection boundary.
				if ok and points.has(0):
					ok = not result.has("text") and result.text_projection_error == "godot_string_contains_nul"
				elif ok:
					ok = result.text.length() == points.size()
					for point in range(result.text.length()): ok = ok and result.text.unicode_at(point) == points[point]
			if not ok and errors.size() < 8: errors.append({"hex":input.hex_encode(),"native":result,"oracle_count":count})
		check(errors.is_empty(),"all 65792 whole byte sequences match current framework, including invalid offsets: " + row.encoding + " " + str(errors))
		row.native_success = success; row.native_invalid = invalid
	check(codec.open("gbk"),"GBK reopened for fixed vectors and source records")
	check(codec.decode(PackedByteArray([0x80])).text == "€","Windows CP936 euro mapping is retained")
	check(codec.decode(PackedByteArray([0x81])).diagnostic.code == "truncated_text_sequence","terminal lead is diagnosed before any replacement text")
	check(codec.decode(PackedByteArray([65,0x81,0x30])).diagnostic.relative_byte_offset == 1,"malformed interior sequence reports its source byte offset")
	var whole: Dictionary = codec.decode(PackedByteArray([0xd6,0xd0,0,65,32,32]))
	check(not whole.has("text") and whole.utf8 == PackedByteArray([0xe4,0xb8,0xad,0,65,32,32]) and whole.codepoints == PackedInt32Array([0x4e2d,0,65,32,32]),"ordinary decoding preserves NUL, spaces and source controls without replacement text")
	var budget: PackedByteArray = PackedByteArray(); budget.resize(Codec.LIMIT + 1)
	check(codec.decode(budget).diagnostic.code == "text_decode_budget","decode allocation budget is enforced")
	var package = Package.new(); check(package.load_package(gui.package),"same ordinary source package is admitted")
	var source_errors: Array = []; var passed: int = 0
	if package.pal98_sources != null:
		var records = package.pal98_sources.open_records()
		check(records.metadata().fingerprint == reference.source_fingerprint,"codec probes bind source identity")
		for row in reference.source_rows:
			var source: Dictionary = records.word_bytes(int(row.index)) if row.role == "words" else records.message_bytes(int(row.index)) if row.role == "messages" else records.message_tail()
			var bytes: PackedByteArray = source.value.bytes; var decoded: Dictionary = codec.decode(bytes)
			var ok: bool = Schema.digest(bytes) == row.bytes_sha256 and bytes.size() == row.size_bytes and source.source.byte_offset == row.byte_offset
			if row.success:
				ok = ok and not decoded.has("error") and Schema.digest(decoded.utf8) == row.utf8_sha256 and decoded.codepoints.size() == row.codepoints
			else: ok = ok and decoded.has("error") and decoded.diagnostic.relative_byte_offset == row.error_offset
			if ok: passed += 1
			elif source_errors.size() < 8: source_errors.append({"role":row.role,"index":row.index,"native":decoded})
		check(source_errors.is_empty() and passed == 14428,"all 565 raw words, 13862 messages and separate tail match framework: " + str(source_errors))
		var record: Dictionary = codec.read_message(records,0)
		check(not record.has("error") and record.decoded.text.contains("$10") and record.has("offset_directory_source"),"source helper retains controls and both source receipts")
		check(codec.read_word(records,0).value.bytes.size() == 10,"fixed word records are not trimmed")
		check(codec.open("big5") and codec.read_message(records,0).diagnostic.code == "text_encoding_mismatch","caller cannot reinterpret a GBK source as Big5")
		codec.open("gbk"); record.decoded.text = "changed"; record.value.bytes[0] = 0
		check(codec.read_message(records,0).decoded.text.contains("$10"),"returned decoded data cannot mutate source records")
	var file = FileAccess.open(args[2].path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failed == 0,"failed":failed,"checks":checks,"tables":reference.tables,
		"source_records_compared":passed,"reference_sha256":Schema.digest(FileAccess.get_file_as_bytes(args[1].path_join("reference.json"))),
		"source_fingerprint":reference.source_fingerprint,"package_sha256":reference.package_sha256,
		"renderer_executed":false,"original_gameplay":false,"human_acceptance":false},"\t")); file.close()
	print("PAL98 codec: ",checks.size()," checks; ",failed," failed; 131584 byte sequences and ",passed," source records")
	quit(0 if failed == 0 else 1)
