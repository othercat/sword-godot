# SPDX-License-Identifier: MIT
extends RefCounted
## T209/T213 consume current state, not new-game defaults or current MGO IDs.
## A request identifies a loaded cache slot; resource binding remains separate.

static func _i2(value) -> bool:
	return value is int and value >= -32768 and value <= 32767

static func _failure(message: String, kind: String, slot: int) -> Dictionary:
	return {"error": message, "sprite_kind": kind, "runtime_slot": slot}

static func event_requests(storage, state: Dictionary, viewport_x, viewport_y) -> Dictionary:
	if storage == null: return _failure("runtime scene event storage required", "event", 0)
	var issue: String = storage.validate_state(state)
	if not issue.is_empty(): return _failure(issue, "event", 0)
	if not _i2(viewport_x) or not _i2(viewport_y): return _failure("viewport requires known signed16 values", "event", 0)
	var requests: Array = []
	for slot in range(1, state.event_count + 1):
		var row: PackedByteArray = storage.event_record(state, slot).value
		if row.decode_s16(12) <= 0: continue
		# Original T213 checks these operations before any screen/SpriteId gate.
		var x: int = row.decode_s16(2) - viewport_x
		if not _i2(x): return _failure("T213 screen X signed16 overflow", "event", slot)
		var y: int = row.decode_s16(4) - viewport_y
		if not _i2(y): return _failure("T213 screen Y signed16 overflow", "event", slot)
		var layer: int = row.decode_s16(6) * 8
		if not _i2(layer): return _failure("T213 layer signed16 overflow", "event", slot)
		if x < -64 or x > 384 or y < 0 or y > 328: continue
		var current: int = row.decode_s16(22); var directions: int = row.decode_s16(18)
		if directions == 3:
			if current == 2: current = 0
			elif current == 3: current = 2
		var base: int = row.decode_s16(20) * directions
		if not _i2(base): return _failure("T213 direction/frame multiplication signed16 overflow", "event", slot)
		var sprite_id: int = row.decode_s16(16)
		if sprite_id <= 0: continue
		var frame: int = base + current
		if not _i2(frame): return _failure("T213 frame addition signed16 overflow", "event", slot)
		requests.append({"kind": "event", "slot": slot, "frame_offset": frame,
			"screen_x": x, "screen_y": y, "layer_base": layer, "observed_sprite_id": sprite_id})
	return {"value": requests}

static func party_requests(member_last, follower_count, party_records: Array, layer_base) -> Dictionary:
	for value in [member_last, follower_count, layer_base]:
		if not _i2(value): return _failure("T209 requires known signed16 caller values", "party", -1)
	var last: int = member_last + follower_count
	if not _i2(last): return _failure("T209 member/follower upper bound signed16 overflow", "party", -1)
	if last >= 255: return _failure("T209 requested rows exceed original ntre safe count", "party", -1)
	if last >= party_records.size(): return _failure("T209 party backing slot unavailable", "party", last)
	var requests: Array = []
	for slot in range(last + 1):
		var row = party_records[slot]
		if not row is Dictionary: return _failure("T209 party slot has unknown state", "party", slot)
		for field in ["x", "y", "current_frame"]:
			if not _i2(row.get(field)): return _failure("T209 party slot requires known signed16 " + field, "party", slot)
		# T209 does not perform T213's screen filter or direction remapping.
		requests.append({"kind": "party", "slot": slot, "frame_offset": row.current_frame,
			"screen_x": row.x, "screen_y": row.y, "layer_base": layer_base, "follower": slot > member_last})
	return {"value": requests}

static func collect(owner: String, storage, event_state: Dictionary, caller: Dictionary) -> Dictionary:
	if owner not in ["render_scene_frame", "submain"]: return {"error": "explicit original scene composition owner required"}
	for field in ["viewport_x", "viewport_y", "member_last", "follower_count", "team_layer"]:
		if not _i2(caller.get(field)): return {"error": "scene caller requires known signed16 " + field}
	if not caller.get("party_records") is Array: return {"error": "scene caller requires party backing projection"}
	var order: Array = ["event", "party"] if owner == "render_scene_frame" else ["party", "event"]
	var result: Array = []
	for kind in order:
		var selected: Dictionary
		if kind == "event": selected = event_requests(storage, event_state, caller.viewport_x, caller.viewport_y)
		else: selected = party_requests(caller.member_last, caller.follower_count, caller.party_records, caller.team_layer)
		if selected.has("error"): selected.owner = owner; return selected
		result.append_array(selected.value)
	if result.size() > 255: return {"error": "combined sprite requests exceed original ntre safe count", "owner": owner}
	return {"value": result, "owner": owner}
