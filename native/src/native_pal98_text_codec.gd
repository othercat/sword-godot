# SPDX-License-Identifier: MIT
extends RefCounted
## Strict, host-independent source decoding. Controls, NULs and padding remain
## data here; T82 byte segmentation and GDI string termination belong elsewhere.
const PROFILE = "pal98.codepages-dotnet8.v1"
const LIMIT = 8 * 1024 * 1024
const TABLES = {
	"gbk":{"page":936,"sha256":"fed0b8ec03389f7e558d2e63b954ca77027186e961ed11cdebefeb6f304100a5"},
	"big5":{"page":950,"sha256":"1e536aeb5f9cad1767aecb1e40a42d26753c040ea9d47c7829f004e558a30f33"}}
const INVALID = 4294967295
const LEAD = 4294967294
var _table: PackedByteArray = PackedByteArray()
var _encoding: String = ""
var error: String = ""

func open(encoding: String) -> bool:
	_table.clear(); _encoding = ""; error = ""
	if not TABLES.has(encoding): error = "unsupported explicit source encoding"; return false
	var expected: Dictionary = TABLES[encoding]
	var path: String = "res://encodings/cp%d.bin" % expected.page
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() != 263180:
		error = "missing or malformed bundled codepage table"; return false
	var bytes: PackedByteArray = file.get_buffer(263180); file.close()
	var hash = HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	if hash.finish().hex_encode() != expected.sha256 or bytes.slice(0,4) != "PWCP".to_ascii_buffer() or bytes.decode_u32(4) != 1 or bytes.decode_u32(8) != expected.page:
		error = "bundled codepage table integrity mismatch"; return false
	_table = bytes; _encoding = encoding; return true

func metadata() -> Dictionary:
	return {"profile":PROFILE,"encoding":_encoding,"table_sha256":TABLES[_encoding].sha256} if not _table.is_empty() else {}

func decode(bytes: PackedByteArray) -> Dictionary:
	if _table.is_empty(): return _failure("text_codec_not_loaded",-1)
	if bytes.size() > LIMIT: return _failure("text_decode_budget",-1)
	var points: PackedInt32Array = PackedInt32Array(); var offset: int = 0
	while offset < bytes.size():
		var first: int = bytes[offset]; var scalar: int = _table.decode_u32(12 + first * 4)
		var size: int = 1
		if scalar == LEAD:
			if offset + 1 >= bytes.size(): return _failure("truncated_text_sequence",offset)
			scalar = _table.decode_u32(12 + 256 * 4 + (first * 256 + bytes[offset + 1]) * 4); size = 2
		if scalar == INVALID: return _failure("invalid_text_sequence",offset)
		points.append(scalar); offset += size
	# Godot replaces U+0000 when parsing a String. Keep the lossless result as
	# scalars/UTF-8 bytes; expose a String only when it can represent every scalar.
	var utf8: PackedByteArray = PackedByteArray()
	for scalar in points:
		if scalar < 128: utf8.append(scalar)
		elif scalar < 2048: utf8.append_array(PackedByteArray([0xc0 | (scalar >> 6),0x80 | (scalar & 63)]))
		elif scalar < 65536: utf8.append_array(PackedByteArray([0xe0 | (scalar >> 12),0x80 | ((scalar >> 6) & 63),0x80 | (scalar & 63)]))
		else: utf8.append_array(PackedByteArray([0xf0 | (scalar >> 18),0x80 | ((scalar >> 12) & 63),0x80 | ((scalar >> 6) & 63),0x80 | (scalar & 63)]))
	var result: Dictionary = metadata()
	result.utf8 = utf8; result.codepoints = points
	if points.has(0): result.text_projection_error = "godot_string_contains_nul"
	else: result.text = utf8.get_string_from_utf8()
	return result

func _failure(code: String, offset: int) -> Dictionary:
	return {"error":"pal98-text-codec: " + code,"diagnostic":{"code":code,"relative_byte_offset":offset,"text_encoding":_encoding}}

func read_message(records, index: int) -> Dictionary:
	if records == null: return _failure("not_loaded",-1)
	return _record(records.message_bytes(index))

func read_word(records, index: int) -> Dictionary:
	if records == null: return _failure("not_loaded",-1)
	return _record(records.word_bytes(index))

func _record(record: Dictionary) -> Dictionary:
	if record.has("error"): return record
	if record.value.text_encoding != _encoding: return _failure("text_encoding_mismatch",-1)
	var decoded: Dictionary = decode(record.value.bytes)
	var result: Dictionary = record.duplicate(true)
	if decoded.has("error"):
		result.error = decoded.error; result.diagnostic = record.source.duplicate(true)
		result.diagnostic.merge(decoded.diagnostic,true)
		if decoded.diagnostic.relative_byte_offset >= 0:
			result.diagnostic.error_byte_offset = record.source.byte_offset + decoded.diagnostic.relative_byte_offset
	else:
		result.decoded = decoded
	return result
