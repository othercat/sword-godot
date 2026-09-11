# SPDX-License-Identifier: MIT
extends RefCounted
## Addressed byte-level text plans. No rendering, clock advancement, input polling,
## dialog-state mutation or public save representation is performed here.
const PROFILE = "pal98.text-byte-plan.v1"
const MAX_MESSAGE_BYTES = 255

static func read_message(records, index: int) -> Dictionary:
	if records == null: return {"error": "pal98-text: source records required", "diagnostic": {"code": "not_loaded", "message_index": index}}
	return _scan(records.message_bytes(index))

static func read_instruction(records, pc: int) -> Dictionary:
	if records == null: return {"error": "pal98-text: source records required", "diagnostic": {"code": "not_loaded", "instruction_index": pc}}
	return _scan(records.message_for_instruction(pc))

static func _failure(message: Dictionary, code: String, detail: String, offset: int) -> Dictionary:
	var diagnostic: Dictionary = message.source.duplicate(true)
	diagnostic.code = code; diagnostic.relative_byte_offset = offset
	diagnostic.error_byte_offset = message.source.byte_offset + offset
	for key in ["offset_directory_source", "instruction_source", "instruction_words"]:
		if message.has(key): diagnostic[key] = message[key].duplicate(true)
	return {"error": "pal98-text: " + detail, "diagnostic": diagnostic}

static func _scan(message: Dictionary) -> Dictionary:
	if message.has("error"): return message
	var bytes: PackedByteArray = message.value.bytes
	if bytes.size() > MAX_MESSAGE_BYTES:
		return _failure(message, "message_length_u1_unimplemented", "message exceeds original checked U1 length; extended text owner required", 0)
	var tokens: Array = []; var offset: int = 0; var termination: String = "end"
	while offset < bytes.size():
		var byte: int = bytes[offset]
		var token: Dictionary = {"offset": offset, "size_bytes": 1}
		match byte:
			34:
				token.kind = "swap_colours"
			36, 126:
				if offset + 2 >= bytes.size():
					return _failure(message, "truncated_text_parameter", "control requires two source parameter bytes", offset)
				var tens: int = bytes[offset + 1]; var units: int = bytes[offset + 2]
				if tens < 48 or tens > 57 or units < 48 or units > 57:
					return _failure(message, "nondecimal_text_parameter_unimplemented", "nondecimal control arithmetic is outside this verified subset", offset)
				var number: int = (tens - 48) * 10 + units - 48
				# For decimal 00..99 this exactly matches Single(dd*10/7), then
				# CInt. No half ties occur in this bounded domain. These are the
				# original parameters, not milliseconds or Native logic ticks.
				token.units = int((number * 10 + 3) / 7); token.size_bytes = 3
				token.kind = "character_delay" if byte == 36 else "timed_return"
			40, 41:
				token.kind = "select_icon"; token.index = 2 if byte == 40 else 1
			_:
				var width: int = 2 if byte > 128 else 1
				token.size_bytes = mini(width, bytes.size() - offset)
				var glyph: PackedByteArray = bytes.slice(offset, offset + token.size_bytes)
				token.loader_zero = token.size_bytes < width
				# The original loader supplies a trailing zero outside M.MSG.
				# A final double-byte lead reads it; do not forge it as source data.
				if token.loader_zero: glyph.append(0)
				token.kind = "glyph"; token.bytes = glyph; token.advance_pixels = width * 8
		tokens.append(token)
		offset += token.size_bytes
		if token.kind == "timed_return": termination = "timed_return"; break
	var result: Dictionary = {"profile": PROFILE, "source": message.source.duplicate(true),
		"text_encoding": message.value.text_encoding, "tokens": tokens, "consumed_bytes": offset,
		"remaining_bytes": bytes.slice(offset), "termination": termination}
	for key in ["offset_directory_source", "instruction_source", "instruction_words"]:
		if message.has(key): result[key] = message[key].duplicate(true)
	return result
