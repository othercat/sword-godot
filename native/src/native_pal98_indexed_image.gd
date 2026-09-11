# SPDX-License-Identifier: MIT
extends RefCounted
## Raw bounded RLE/word-pointer/RGB6 formats; no implicit palette or frame policy.
const MAX_BYTES = 8388608
const MAX_PIXELS = 33554432

static func frame_count(group: PackedByteArray) -> Dictionary:
	if group.size() < 4 or group.size() > MAX_BYTES: return {"error": "sprite group byte budget"}
	var words: int = group.decode_u16(0)
	if words < 2 or words > 4097 or words * 2 > group.size(): return {"error": "sprite group word directory"}
	return {"value": words - 1, "final_table_word": group.decode_u16((words - 1) * 2)}

static func frame(group: PackedByteArray, index: int) -> Dictionary:
	var count: Dictionary = frame_count(group)
	if count.has("error"): return count
	if index < 0 or index >= count.value: return {"error": "sprite frame index outside group"}
	var start: int = group.decode_u16(index * 2) * 2
	if start < (count.value + 1) * 2 or start >= group.size():
		return {"error": "sprite frame pointer outside data", "frame_index": index, "byte_offset": start, "group_size": group.size()}
	# Pointers alias and may be reordered. Only the requested pointer is required
	# to be valid; the final table word is not an end-of-file pointer.
	var end: int = group.size()
	for other in range(count.value):
		var candidate: int = group.decode_u16(other * 2) * 2
		if candidate > start and candidate < end: end = candidate
	var result: Dictionary = rle(group.slice(start, end))
	result.frame_index = index; result.byte_offset = start; result.frame_count = count.value
	return result

static func rle(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4 or bytes.size() > MAX_BYTES: return {"error": "RLE byte budget"}
	var width: int = bytes.decode_u16(0); var height: int = bytes.decode_u16(2)
	if width < 1 or width > 8192 or height < 1 or height > 8192 or width * height > MAX_PIXELS: return {"error": "RLE pixel budget"}
	var indices = PackedByteArray(); indices.resize(width * height)
	var coverage = PackedByteArray(); coverage.resize(width * height)
	var cursor: int = 4
	for row in range(height):
		var column: int = 0
		while column < width:
			if cursor >= bytes.size(): return {"error": "RLE truncated row", "row": row}
			var command: int = bytes[cursor]; cursor += 1
			var count: int = command & 127
			if count > width - column: return {"error": "RLE run crosses row", "row": row}
			if command < 128:
				if count > bytes.size() - cursor: return {"error": "RLE truncated literal", "row": row}
				for offset in range(count):
					var at: int = row * width + column + offset
					indices[at] = bytes[cursor + offset]; coverage[at] = 1
				cursor += count
			column += count
	return {"value": {"width": width, "height": height, "indices": indices, "coverage": coverage,
		"consumed_bytes": cursor, "tail": bytes.slice(cursor)}}

static func validate_palette(rgb6: PackedByteArray) -> String:
	if rgb6.size() != 768: return "select exactly one 768-byte RGB6 palette"
	for channel in rgb6:
		if channel > 63: return "RGB6 palette channel above 63"
	return ""

static func rgba(decoded: Dictionary, rgb6: PackedByteArray, literal_255_transparent: bool) -> Dictionary:
	var issue: String = validate_palette(rgb6)
	if not issue.is_empty(): return {"error": issue}
	if not decoded.get("indices") is PackedByteArray or not decoded.get("coverage") is PackedByteArray: return {"error": "decoded RLE planes required"}
	var width: int = decoded.get("width", 0); var height: int = decoded.get("height", 0)
	if width < 1 or width > 8192 or height < 1 or height > 8192 or width * height > MAX_PIXELS: return {"error": "RGBA pixel budget"}
	var indices: PackedByteArray = decoded.indices; var coverage: PackedByteArray = decoded.coverage
	if indices.size() != width * height or coverage.size() != indices.size(): return {"error": "decoded RLE plane dimensions"}
	var output = PackedByteArray(); output.resize(indices.size() * 4)
	for at in range(indices.size()):
		if coverage[at] == 0 or (literal_255_transparent and indices[at] == 255): continue
		var colour: int = indices[at] * 3
		for channel in range(3): output[at * 4 + channel] = rgb6[colour + channel] * 4
		output[at * 4 + 3] = 255
	return {"value": output, "width": width, "height": height}
