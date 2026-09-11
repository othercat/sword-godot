# SPDX-License-Identifier: MIT
extends RefCounted
## Immutable, addressed views over admitted Win95 source files. These views do
## not execute instructions, decode legacy text, or become mutable game state.
const TABLES = {"roles": ["data", 3], "events": ["sss", 0], "scenes": ["sss", 1],
	"objects": ["sss", 2], "message_offsets": ["sss", 3], "scripts": ["sss", 4]}
const RECORD_SIZES = {"events": 32, "scenes": 8, "objects": 14, "scripts": 8}
var error: String = ""
var _metadata: Dictionary = {}
var _files: Dictionary = {}
var _chunks: Dictionary = {}
var _locations: Dictionary = {}

func load_source(source) -> bool:
	if source == null or source.metadata().is_empty():
		error = "pal98-records: admitted source snapshot required"; return false
	var metadata: Dictionary = source.metadata()
	var files: Dictionary = {}; var chunks: Dictionary = {}; var locations: Dictionary = {}
	for role in ["data", "sss", "words", "messages"]: files[role] = source.copy_bytes(role)
	# Source admission has already checked every MKF offset. Copy the snapshot so
	# replacing the caller's source later cannot mix old and new records.
	for table in TABLES:
		var spec: Array = TABLES[table]
		chunks[table] = source.copy_chunk(spec[0], spec[1])
		locations[table] = {"role": spec[0], "chunk_index": spec[1], "chunk_offset": files[spec[0]].decode_u32(spec[1] * 4)}
	_metadata = metadata; _files = files; _chunks = chunks; _locations = locations; error = ""
	return true

func metadata() -> Dictionary:
	return _metadata.duplicate(true)

func _source(table: String, index: int = -1) -> Dictionary:
	var location: Dictionary = _locations.get(table, {"role": table})
	var role: String = location.role
	var result: Dictionary = {"table": table, "record_index": index}
	if _metadata.is_empty(): return result
	result.merge({"fingerprint": _metadata.fingerprint, "file_role": role,
		"path": _metadata.files[role].path, "file_sha256": _metadata.files[role].sha256})
	if location.has("chunk_index"):
		result.chunk_index = location.chunk_index; result.chunk_offset = location.chunk_offset
	return result

func _failure(code: String, message: String, table: String, index: int = -1) -> Dictionary:
	var diagnostic: Dictionary = _source(table, index); diagnostic.code = code
	return {"error": "pal98-records: " + message, "diagnostic": diagnostic}

func _shape(table: String, width: int, minimum: int = 0) -> Dictionary:
	if _metadata.is_empty(): return _failure("not_loaded", "admitted source snapshot required", table)
	var bytes: PackedByteArray = _chunks[table]
	if bytes.size() % width != 0 or bytes.size() < width * minimum:
		var result: Dictionary = _failure("table_shape", "record alignment/count: " + table, table)
		result.diagnostic.size_bytes = bytes.size(); result.diagnostic.record_size = width
		result.diagnostic.minimum_records = minimum; return result
	return {"count": int(bytes.size() / width)}

static func _words(bytes: PackedByteArray) -> Array:
	var result: Array = []
	for offset in range(0, bytes.size(), 2): result.append(bytes.decode_u16(offset))
	return result

func _record(table: String, index: int, width: int, minimum: int = 0) -> Dictionary:
	var shape: Dictionary = _shape(table, width, minimum)
	if shape.has("error"): shape.diagnostic.record_index = index; return shape
	if index < 0 or index >= shape.count:
		var result: Dictionary = _failure("index_out_of_range", "record outside " + table, table, index)
		result.diagnostic.record_count = shape.count; return result
	var source: Dictionary = _source(table, index)
	source.byte_offset = source.chunk_offset + index * width; source.size_bytes = width
	return {"value": {"raw_index": index, "words": _words(_chunks[table].slice(index * width, (index + 1) * width))}, "source": source}

func table_summary() -> Dictionary:
	if _metadata.is_empty(): return _failure("not_loaded", "admitted source snapshot required", "scenes")
	var result: Dictionary = {"counts": {}, "issues": []}
	for table in RECORD_SIZES:
		var width: int = RECORD_SIZES[table]
		var shape: Dictionary = _shape(table, width, 2 if table == "scenes" else 0)
		if shape.has("error"): result.issues.append(shape)
		else: result.counts[table] = shape.count - 1 if table == "scenes" else shape.count
	result.counts.roles = 6; result.counts.words = int(_files.words.size() / 10)
	result.counts.messages = int(_chunks.message_offsets.size() / 4) - 1
	return result

func role_record(role_index: int) -> Dictionary:
	if _metadata.is_empty(): return _failure("not_loaded", "admitted source snapshot required", "roles", role_index)
	if role_index < 0 or role_index >= 6: return _failure("index_out_of_range", "source role outside 0..5", "roles", role_index)
	var words: Array = []
	for field in range(75): words.append(_chunks.roles.decode_u16((field * 6 + role_index) * 2))
	var source: Dictionary = _source("roles", role_index)
	# Seventy-five separated WORDs, not a contiguous 150-byte role record.
	source.first_word_offset = source.chunk_offset + role_index * 2
	source.word_stride_bytes = 12; source.word_count = 75; source.word_size_bytes = 2
	return {"value": {"role_index": role_index, "words": words}, "source": source}

func event_record(raw_index: int) -> Dictionary:
	return _record("events", raw_index, 32)

func object_record(raw_index: int) -> Dictionary:
	return _record("objects", raw_index, 14, 1)

func scene_record(raw_index: int) -> Dictionary:
	var result: Dictionary = _record("scenes", raw_index, 8, 2)
	if result.has("error"): return result
	result.value.is_terminal_boundary = raw_index == int(_chunks.scenes.size() / 8) - 1
	return result

func scene(raw_index: int) -> Dictionary:
	var record: Dictionary = scene_record(raw_index)
	if record.has("error"): return record
	if record.value.is_terminal_boundary: return _failure("terminal_scene_record", "terminal event boundary is not a playable scene", "scenes", raw_index)
	var events: Dictionary = _shape("events", 32)
	if events.has("error"): return events
	var next: Dictionary = scene_record(raw_index + 1)
	var words: Array = record.value.words
	var start: int = words[3]; var finish: int = next.value.words[3]
	if finish < start or finish > events.count:
		var result: Dictionary = _failure("scene_event_bounds", "scene event range is outside SSS0", "scenes", raw_index)
		result.diagnostic.event_start = start; result.diagnostic.event_end_exclusive = finish
		result.diagnostic.event_count = events.count; return result
	return {"value": {"raw_index": raw_index, "map_word": words[0], "enter_script_word": words[1],
		"leave_script_word": words[2], "event_start": start, "event_end_exclusive": finish},
		"source": record.source, "end_boundary_source": next.source}

func scene_for_runtime_id(runtime_scene_id: int) -> Dictionary:
	# The Win95 loader stores raw scene 0 at runtime scene 1. This conversion does
	# not manufacture a Native scene ID or claim that the scene's scripts run.
	if runtime_scene_id < 1 or runtime_scene_id > 65535:
		var result: Dictionary = _failure("runtime_scene_id", "runtime scene requires a nonzero WORD", "scenes")
		result.diagnostic.runtime_scene_id = runtime_scene_id; return result
	return scene(runtime_scene_id - 1)

func instruction(raw_index: int) -> Dictionary:
	var result: Dictionary = _record("scripts", raw_index, 8, 1)
	if result.has("error"): return result
	var words: Array = result.value.words
	result.value.opcode = words[0]; result.value.operands = words.slice(1)
	# Opcode 0, instruction index 0 and unknown opcode words stay inspectable.
	# Entry/return, U2 PC wrap and supported semantics belong to the interpreter.
	return result

func word_bytes(raw_index: int) -> Dictionary:
	if _metadata.is_empty(): return _failure("not_loaded", "admitted source snapshot required", "words", raw_index)
	var count: int = int(_files.words.size() / 10)
	if raw_index < 0 or raw_index >= count: return _failure("index_out_of_range", "word outside WORD.DAT", "words", raw_index)
	var source: Dictionary = _source("words", raw_index); source.byte_offset = raw_index * 10; source.size_bytes = 10
	return {"value": {"raw_index": raw_index, "text_encoding": _metadata.text_encoding,
		"bytes": _files.words.slice(raw_index * 10, (raw_index + 1) * 10)}, "source": source}

func message_bytes(raw_index: int) -> Dictionary:
	if _metadata.is_empty(): return _failure("not_loaded", "admitted source snapshot required", "messages", raw_index)
	var offsets: PackedByteArray = _chunks.message_offsets
	var count: int = int(offsets.size() / 4) - 1
	if raw_index < 0 or raw_index >= count: return _failure("index_out_of_range", "message outside SSS3 directory", "messages", raw_index)
	var start: int = offsets.decode_u32(raw_index * 4); var finish: int = offsets.decode_u32((raw_index + 1) * 4)
	var source: Dictionary = _source("messages", raw_index); source.byte_offset = start; source.size_bytes = finish - start
	var directory: Dictionary = _source("message_offsets", raw_index)
	directory.byte_offset = directory.chunk_offset + raw_index * 4; directory.size_bytes = 8
	return {"value": {"raw_index": raw_index, "text_encoding": _metadata.text_encoding,
		"bytes": _files.messages.slice(start, finish)}, "source": source, "offset_directory_source": directory}

func message_tail() -> Dictionary:
	if _metadata.is_empty(): return _failure("not_loaded", "admitted source snapshot required", "messages")
	var start: int = _chunks.message_offsets.decode_u32(_chunks.message_offsets.size() - 4)
	var source: Dictionary = _source("messages"); source.byte_offset = start; source.size_bytes = _files.messages.size() - start
	return {"value": {"bytes": _files.messages.slice(start)}, "source": source}

func message_for_instruction(raw_index: int) -> Dictionary:
	var entry: Dictionary = instruction(raw_index)
	if entry.has("error"): return entry
	if entry.value.opcode != 0xffff:
		var result: Dictionary = _failure("not_message_instruction", "instruction is not FFFF", "scripts", raw_index)
		result.diagnostic.instruction_source = entry.source; result.diagnostic.instruction_words = entry.value.words
		return result
	var result: Dictionary = message_bytes(entry.value.operands[0])
	# Resolve the reference without executing text controls or inventing a player
	# confirmation gate. A bad message retains both sides of the broken reference.
	var context: Dictionary = result.diagnostic if result.has("error") else result
	context.instruction_source = entry.source; context.instruction_words = entry.value.words
	return result
