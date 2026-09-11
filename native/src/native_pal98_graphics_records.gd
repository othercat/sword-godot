# SPDX-License-Identifier: MIT
extends RefCounted
## Addressed reads from one admitted graphics snapshot. Decoded cache is bounded;
## all public results are detached and failures include the original file identity.
const Yj2 = preload("res://src/native_pal98_yj2.gd")
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const CACHE_BYTES = 16777216
var error: String = ""
var _metadata: Dictionary = {}
var _files: Dictionary = {}
var _cache: Dictionary = {}
var _cache_order: Array = []
var _cache_bytes: int = 0

func load_source(source) -> bool:
	if source == null or source.metadata().is_empty(): error = "admitted graphics snapshot required"; return false
	var metadata: Dictionary = source.metadata(); var files: Dictionary = {}
	for role in metadata.files: files[role] = source.copy_bytes(role)
	_metadata = metadata; _files = files; _cache.clear(); _cache_order.clear(); _cache_bytes = 0; error = ""
	return true

func metadata() -> Dictionary:
	return _metadata.duplicate(true)

func _source(role: String, index: int) -> Dictionary:
	var source: Dictionary = {"file_role": role, "chunk_index": index}
	if not _metadata.is_empty() and _files.has(role):
		source.merge({"fingerprint": _metadata.fingerprint, "source_fingerprint": _metadata.source_fingerprint,
			"path": _metadata.files[role].path, "file_sha256": _metadata.files[role].sha256})
	return source

func raw_chunk(role: String, index: int) -> Dictionary:
	var source: Dictionary = _source(role, index)
	if not _files.has(role): return {"error": "graphics role not loaded", "source": source}
	var bytes: PackedByteArray = _files[role]
	var count: int = int(bytes.decode_u32(0) / 4) - 1
	if index < 0 or index >= count: return {"error": "graphics chunk index outside MKF", "source": source}
	var start: int = bytes.decode_u32(index * 4); var end: int = bytes.decode_u32((index + 1) * 4)
	source.byte_offset = start; source.size_bytes = end - start
	return {"value": bytes.slice(start, end), "source": source}

func chunk_count(role: String) -> Dictionary:
	if not _files.has(role): return {"error": "graphics role not loaded", "source": _source(role, -1)}
	return {"value": int(_files[role].decode_u32(0) / 4) - 1, "source": _source(role, -1)}

func decoded_chunk(role: String, index: int) -> Dictionary:
	if role not in ["MAP.MKF", "MGO.MKF"]: return {"error": "YJ2 is only selected for MAP/MGO", "source": _source(role, index)}
	var key: String = "%s:%d" % [role, index]
	if _cache.has(key): return _cache[key].duplicate(true)
	var raw: Dictionary = raw_chunk(role, index)
	if raw.has("error"): return raw
	var result: Dictionary = Yj2.decode(raw.value, 65536 if role == "MAP.MKF" else 8388608)
	result.source = raw.source
	if result.has("error"): return result
	if role == "MAP.MKF" and result.value.size() != 65536: return {"error": "MAP decoded size must be 65536", "source": raw.source}
	var length: int = result.value.size()
	while _cache_bytes + length > CACHE_BYTES and not _cache_order.is_empty():
		var oldest: String = _cache_order.pop_front()
		_cache_bytes -= _cache[oldest].value.size(); _cache.erase(oldest)
	_cache[key] = result.duplicate(true); _cache_order.append(key); _cache_bytes += length
	return result

func group(role: String, index: int) -> Dictionary:
	if role not in ["GOP.MKF", "MGO.MKF"]: return {"error": "sprite groups require GOP/MGO", "source": _source(role, index)}
	var result: Dictionary = raw_chunk(role, index) if role == "GOP.MKF" else decoded_chunk(role, index)
	if result.has("error"): return result
	var shape: Dictionary = Indexed.frame_count(result.value)
	if shape.has("error"): shape.source = result.source; return shape
	result.frame_count = shape.value; result.final_table_word = shape.final_table_word
	return result

func frame(role: String, chunk_index: int, frame_index: int) -> Dictionary:
	var bytes: Dictionary = group(role, chunk_index)
	if bytes.has("error"): return bytes
	var result: Dictionary = Indexed.frame(bytes.value, frame_index)
	result.source = bytes.source; result.source.frame_index = frame_index
	if result.has("byte_offset"): result.source.decoded_frame_offset = result.byte_offset
	return result

func palette(chunk_index: int, variant: int) -> Dictionary:
	var raw: Dictionary = raw_chunk("PAT.MKF", chunk_index)
	if raw.has("error"): return raw
	if variant < 0 or variant > 1 or (variant + 1) * 768 > raw.value.size(): return {"error": "selected palette variant absent", "source": raw.source}
	var bytes: PackedByteArray = raw.value.slice(variant * 768, (variant + 1) * 768)
	var issue: String = Indexed.validate_palette(bytes)
	if not issue.is_empty(): return {"error": issue, "source": raw.source}
	raw.source.variant = variant; raw.source.variant_byte_offset = raw.source.byte_offset + variant * 768
	return {"value": bytes, "source": raw.source}

func rgba_frame(role: String, chunk_index: int, frame_index: int, palette_index: int, variant: int, literal_255_transparent: bool) -> Dictionary:
	var selected: Dictionary = frame(role, chunk_index, frame_index)
	if selected.has("error"): return selected
	var rgb6: Dictionary = palette(palette_index, variant)
	if rgb6.has("error"): rgb6.frame_source = selected.source; return rgb6
	var result: Dictionary = Indexed.rgba(selected.value, rgb6.value, literal_255_transparent)
	result.source = selected.source; result.palette_source = rgb6.source
	return result
