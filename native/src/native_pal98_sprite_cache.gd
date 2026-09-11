# SPDX-License-Identifier: MIT
extends RefCounted
## Explicit T98/T99 cache reloads; T163 reads loaded WORD offsets, not current IDs.
## Unknown bytes stay unknown. Failures do not publish partial original writes.
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const CACHE_BYTES = 65536
var error: String = ""
var _reader
var _source: Dictionary = {}
var _event: Dictionary = {}
var _party: Dictionary = {}

static func _i2(value) -> bool:
	return value is int and value >= -32768 and value <= 32767

static func _empty() -> Dictionary:
	var bytes = PackedByteArray(); bytes.resize(CACHE_BYTES)
	var owners = PackedInt32Array(); owners.resize(CACHE_BYTES); owners.fill(-1)
	return {"bytes": bytes, "owners": owners, "used_words": null}

func load_source(graphics, tables) -> bool:
	if graphics == null or tables == null: error = "admitted graphics and table snapshots required"; return false
	var gm: Dictionary = graphics.metadata(); var tm: Dictionary = tables.metadata()
	if gm.is_empty() or tm.is_empty() or tm.get("provenance", {}).get("source_revision") != "sha256:" + str(gm.get("source_fingerprint", "")):
		error = "sprite cache graphics/table source origin mismatch"; return false
	var reader = graphics.open_records()
	if reader == null: error = "graphics snapshot reader unavailable"; return false
	_reader = reader; _source = {"graphics_fingerprint": gm.fingerprint, "table_fingerprint": tm.fingerprint,
		"origin_fingerprint": gm.source_fingerprint}
	_event = _empty(); _party = _empty(); error = ""; return true

func snapshot(kind: String) -> Dictionary:
	if _source.is_empty() or kind not in ["event", "party"]: return {}
	return {"source": _source.duplicate(true), "cache": (_event if kind == "event" else _party).duplicate(true)}

func source() -> Dictionary:
	return _source.duplicate(true)

func fork_for_reload():
	if _source.is_empty(): return null
	var candidate = get_script().new()
	# Reader source bytes are immutable; its decode FIFO is not game state.
	candidate._reader = _reader; candidate._source = _source.duplicate(true)
	candidate._event = _event.duplicate(true); candidate._party = _party.duplicate(true)
	return candidate

func _failure(message: String, kind: String, slot: int) -> Dictionary:
	return {"error": message, "source": _source.duplicate(true), "sprite_kind": kind, "runtime_slot": slot}

func _size(sprite_id: int) -> Dictionary:
	var raw: Dictionary = _reader.raw_chunk("MGO.MKF", sprite_id)
	if raw.has("error"): return raw
	if raw.value.size() < 4: return {"error": "paksize header unavailable", "source": raw.source}
	# paksize SARs signed32, then VB StoreLocalI2 truncates rather than checks.
	var words: int = (raw.value.decode_s32(0) >> 1) & 65535
	return {"value": words - 65536 if words >= 32768 else words, "source": raw.source}

func _write(cache: Dictionary, word_offset: int, sprite_id: int) -> String:
	if word_offset < 0: return "negative original cache write address is not owned"
	var decoded: Dictionary = _reader.decoded_chunk("MGO.MKF", sprite_id)
	if decoded.has("error"): return str(decoded.error)
	var start: int = word_offset * 2
	if start + decoded.value.size() > CACHE_BYTES: return "decoded MGO exceeds owned signed-WORD cache address space"
	# Odd terminal bytes are written too. The next floor(size/2) append can
	# overwrite that byte, exactly as separate unpak and paksize operations do.
	for index in range(decoded.value.size()):
		cache.bytes[start + index] = decoded.value[index]; cache.owners[start + index] = sprite_id
	return ""

static func _word(cache: Dictionary, offset: int) -> Dictionary:
	if offset < 0 or offset >= 32768: return {"error": "cache WORD address outside owned signed16 range"}
	var at: int = offset * 2
	if cache.owners[at] < 0 or cache.owners[at + 1] < 0: return {"error": "original sprite cache bytes are Unknown"}
	return {"value": cache.bytes.decode_s16(at)}

func load_events(storage, state: Dictionary) -> Dictionary:
	if _source.is_empty() or storage == null: return _failure("sprite cache source/storage not loaded", "event", 0)
	var issue: String = storage.validate_state(state)
	if not issue.is_empty(): return _failure(issue, "event", 0)
	if state.source_fingerprint != _source.table_fingerprint: return _failure("event/cache table fingerprint mismatch", "event", 0)
	var candidate: Dictionary = state.duplicate(true); var cache: Dictionary = _event.duplicate(true)
	var accumulated: int = 0; var loaded: Array = []
	for index in range(candidate.event_count):
		var row: PackedByteArray = candidate.active_slots[index]
		var sprite_id: int = row.decode_s16(16)
		if sprite_id > 0:
			var matching: int = -1
			for earlier in range(index):
				if candidate.active_slots[earlier].decode_s16(16) == sprite_id: matching = earlier
			if matching >= 0:
				row.encode_s16(26, candidate.active_slots[matching].decode_s16(26))
			else:
				var size: Dictionary = _size(sprite_id)
				if size.has("error"): return _failure(str(size.error), "event", index + 1)
				var total: int = accumulated + size.value
				if not _i2(total): return _failure("T98 accumulated WORD count signed16 overflow before unpak", "event", index + 1)
				if total > 0:
					issue = _write(cache, accumulated, sprite_id)
					if not issue.is_empty(): return _failure(issue, "event", index + 1)
					row.encode_s16(26, accumulated); accumulated = total; loaded.append(sprite_id)
				else: row.encode_s16(16, 0)
		# This common tail also runs when SpriteId is nonpositive or was cleared.
		var count: int = 0; var base: int = row.decode_s16(26)
		while true:
			var address: int = base + count
			if not _i2(address): return _failure("T98 directory address signed16 overflow", "event", index + 1)
			var word: Dictionary = _word(cache, address)
			if word.has("error"): return _failure(str(word.error), "event", index + 1)
			if word.value <= 0: break
			count += 1
			if not _i2(count): return _failure("T98 positive directory count signed16 overflow", "event", index + 1)
		row.encode_s16(28, count)
		if count == 0: row.encode_s16(16, 0)
		candidate.active_slots[index] = row
	cache.used_words = accumulated; _event = cache
	return {"state": candidate, "loaded_mgo_chunks": loaded, "used_words": accumulated}

func load_party(member_last, follower_count, party_records: Array, role_sprite_ids: Array) -> Dictionary:
	if _source.is_empty(): return _failure("sprite cache source not loaded", "party", -1)
	if not _i2(member_last) or not _i2(follower_count): return _failure("T99 requires known signed16 counters", "party", -1)
	if party_records.size() > 255 or role_sprite_ids.size() > 32768: return _failure("T99 caller projection exceeds owned budget", "party", -1)
	var candidate: Array = party_records.duplicate(true); var cache: Dictionary = _party.duplicate(true)
	var accumulated: int = 0; var loaded: Array = []; var ordinary_ids: Array = []
	var ordinary_count: int = maxi(member_last + 1, 0)
	for ordinal in range(ordinary_count + maxi(follower_count, 0)):
		var ordinary: bool = ordinal < ordinary_count
		var slot: int = ordinal if ordinary else member_last + ordinal - ordinary_count + 1
		if not _i2(slot): return _failure("T99 follower slot signed16 overflow", "party", -1)
		if slot < 0 or slot >= 255 or slot >= candidate.size(): return _failure("T99 party backing slot unavailable", "party", slot)
		if not candidate[slot] is Dictionary or not _i2(candidate[slot].get("role_id")):
			return _failure("T99 requires known signed16 RoleId", "party", slot)
		var role_id: int = candidate[slot].role_id; var sprite_id: int = role_id
		var matching: int = -1
		if ordinary:
			if role_id < 0 or role_id >= role_sprite_ids.size() or not _i2(role_sprite_ids[role_id]):
				return _failure("T99 role field2 unavailable or Unknown", "party", slot)
			sprite_id = role_sprite_ids[role_id]
			for earlier in range(ordinary_ids.size()):
				if ordinary_ids[earlier] == sprite_id: matching = earlier
			ordinary_ids.append(sprite_id)
		if matching >= 0:
			candidate[slot].cache_word_offset = candidate[matching].cache_word_offset
		else:
			var size: Dictionary = _size(sprite_id)
			if size.has("error"): return _failure(str(size.error), "party", slot)
			var issue: String = _write(cache, accumulated, sprite_id)
			if not issue.is_empty(): return _failure(issue, "party", slot)
			candidate[slot].cache_word_offset = accumulated; loaded.append(sprite_id)
			accumulated += size.value
			# Original T99 overflows after unpak/offset writes. Native returns an
			# atomic diagnostic, never publishes those partial original effects.
			if not _i2(accumulated): return _failure("T99 accumulated WORD count signed16 overflow after unpak", "party", slot)
	cache.used_words = accumulated; _party = cache
	return {"party_records": candidate, "loaded_mgo_chunks": loaded, "used_words": accumulated}

func resolve(kind: String, word_offset, frame_offset) -> Dictionary:
	if _source.is_empty() or kind not in ["event", "party"]: return _failure("loaded event/party cache required", kind, -1)
	if not _i2(word_offset) or not _i2(frame_offset): return _failure("T163 cache/frame offsets require known signed16", kind, -1)
	var cache: Dictionary = _event if kind == "event" else _party
	var address: int = word_offset + frame_offset
	if not _i2(address): return _failure("T163 frame table address signed16 overflow", kind, -1)
	var pointer: Dictionary = _word(cache, address)
	if pointer.has("error"): return _failure(str(pointer.error), kind, -1)
	var frame_word: int = word_offset + pointer.value
	if not _i2(frame_word): return _failure("T163 frame pointer addition signed16 overflow", kind, -1)
	var width: Dictionary = _word(cache, frame_word)
	if width.has("error"): return _failure(str(width.error), kind, -1)
	if not _i2(frame_word + 1): return _failure("T163 frame height address signed16 overflow", kind, -1)
	var height: Dictionary = _word(cache, frame_word + 1)
	if height.has("error"): return _failure(str(height.error), kind, -1)
	var start: int = frame_word * 2; var end: int = start
	while end < CACHE_BYTES and cache.owners[end] >= 0: end += 1
	var decoded: Dictionary = Indexed.rle(cache.bytes.slice(start, end))
	if decoded.has("error"): return _failure(str(decoded.error) + "; cache reads stop at known bytes", kind, -1)
	var chunks: Array = [cache.owners[address * 2]]
	if cache.owners[address * 2 + 1] not in chunks: chunks.append(cache.owners[address * 2 + 1])
	for at in range(start, start + decoded.value.consumed_bytes):
		if cache.owners[at] not in chunks: chunks.append(cache.owners[at])
	var sources: Array = []
	for chunk in chunks: sources.append(_reader.raw_chunk("MGO.MKF", chunk).source)
	var frame: Dictionary = decoded.value; frame.erase("tail")
	return {"value": frame, "source": {"cache_kind": kind, "cache_word_offset": word_offset,
		"frame_offset": frame_offset, "decoded_byte_offset": start, "graphics": _source.duplicate(true), "mgo_chunks": sources}}

func resolve_requests(storage, event_state: Dictionary, party_records: Array, requests: Array) -> Dictionary:
	if _source.is_empty() or storage == null: return _failure("loaded cache and event storage required", "", -1)
	var issue: String = storage.validate_state(event_state)
	if not issue.is_empty(): return _failure(issue, "event", 0)
	if event_state.source_fingerprint != _source.table_fingerprint: return _failure("event/cache table fingerprint mismatch", "event", 0)
	if requests.size() > 255: return _failure("sprite request count exceeds safe255 rows", "", -1)
	var results: Array = []; var pixels: int = 0
	for request in requests:
		if not request is Dictionary or request.get("kind") not in ["event", "party"] or not request.get("slot") is int:
			return _failure("explicit sprite kind and integer cache slot required", "", -1)
		var kind: String = request.kind; var slot: int = request.slot; var offset
		if kind == "event":
			var row: Dictionary = storage.event_record(event_state, slot)
			if row.has("error"): return _failure(str(row.error), kind, slot)
			offset = row.value.decode_s16(26)
		else:
			if slot < 0 or slot >= party_records.size() or not party_records[slot] is Dictionary:
				return _failure("party cache slot unavailable", kind, slot)
			offset = party_records[slot].get("cache_word_offset")
		var selected: Dictionary = resolve(kind, offset, request.get("frame_offset"))
		if selected.has("error"): selected.runtime_slot = slot; return selected
		pixels += selected.value.width * selected.value.height
		if pixels > Indexed.MAX_PIXELS: return _failure("resolved sprite pixel budget", kind, slot)
		results.append({"request": request.duplicate(true), "frame": selected.value, "source": selected.source})
	return {"value": results}
