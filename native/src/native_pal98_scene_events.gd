# SPDX-License-Identifier: MIT
extends RefCounted
## Source-bound runtime event storage, independently expressing T201/T175 copies.
## Unloaded slots are unknown, not invented cold-start zero records.
const CAPACITY = 160
const RECORD_BYTES = 32
const PROFILE = "pal98.scene-events.v1"
var error: String = ""
var _source: Dictionary = {}
var _events: PackedByteArray
var _scenes: PackedByteArray

func load_source(source) -> bool:
	if source == null or source.metadata().is_empty(): error = "admitted source snapshot required"; return false
	var events: PackedByteArray = source.copy_chunk("sss", 0)
	var scenes: PackedByteArray = source.copy_chunk("sss", 1)
	if events.size() % RECORD_BYTES != 0 or events.size() > 8388608 or scenes.size() < 16 or scenes.size() % 8 != 0 or scenes.size() > 32767 * 8:
		error = "original scene/event table shape outside owned budget"; return false
	_events = events.duplicate(); _scenes = scenes.duplicate(); _source = source.metadata().duplicate(true)
	error = ""; return true

func source() -> Dictionary:
	return _source.duplicate(true)

func source_state() -> Dictionary:
	if _source.is_empty(): return {}
	var slots: Array = []; slots.resize(CAPACITY)
	return {"profile": PROFILE, "source_fingerprint": _source.fingerprint,
		"global_events": _events.duplicate(), "scene_records": _scenes.duplicate(),
		"loaded_scene_id": 0, "event_count": 0, "active_slots": slots}

func validate_state(state: Dictionary) -> String:
	if _source.is_empty(): return "scene event source not loaded"
	if state.size() != 7 or state.get("profile") != PROFILE or state.get("source_fingerprint") != _source.fingerprint:
		return "scene event state source/profile mismatch"
	for field in ["global_events", "scene_records"]:
		if not state.get(field) is PackedByteArray: return "scene event state requires owned bytes: " + field
	if state.global_events.size() != _events.size() or state.scene_records.size() != _scenes.size(): return "scene event state table length mismatch"
	if not state.get("loaded_scene_id") is int or state.loaded_scene_id < 0 or state.loaded_scene_id >= int(_scenes.size() / 8): return "loaded scene outside source table"
	if not state.get("event_count") is int or state.event_count < 0 or state.event_count > CAPACITY: return "current event count outside owned160 slots"
	if state.loaded_scene_id == 0 and state.event_count != 0: return "unloaded scene has an active event count"
	if not state.get("active_slots") is Array or state.active_slots.size() != CAPACITY: return "scene event backing requires160 known-or-unknown slots"
	for index in range(CAPACITY):
		var slot = state.active_slots[index]
		if slot == null:
			if index < state.event_count: return "current event prefix contains unknown bytes"
		elif not slot is PackedByteArray or slot.size() != RECORD_BYTES: return "active event slot requires32 bytes"
	return ""

func _failure(message: String, scene_id: int = 0) -> Dictionary:
	return {"error": message, "source": source(), "runtime_scene_id": scene_id}

func _range(state: Dictionary, scene_id: int) -> Dictionary:
	if scene_id < 1 or scene_id >= int(_scenes.size() / 8): return _failure("runtime scene has no following source boundary", scene_id)
	# Original runtime scene1 owns raw scene0. The fixed helper uses checked I2
	# scene+1 and boundary subtraction; unsupported signed addresses diagnose.
	if scene_id >= 32767: return _failure("T201 scene+1 signed16 overflow", scene_id)
	var bytes: PackedByteArray = state.scene_records
	var first: int = bytes.decode_u16((scene_id - 1) * 8 + 6)
	var next: int = bytes.decode_u16(scene_id * 8 + 6)
	if first > 32767 or next > 32767: return _failure("scene event boundary requires unresolved signed source address", scene_id)
	var count: int = next - first
	if count < -32768 or count > 32767: return _failure("T201 count signed16 overflow", scene_id)
	if count < 0: return _failure("negative original event copy length is not supported", scene_id)
	var loaded: int = mini(count, CAPACITY)
	if first * RECORD_BYTES + loaded * RECORD_BYTES > state.global_events.size(): return _failure("current scene event copy exceeds owned global table", scene_id)
	return {"first": first, "raw_count": count, "count": loaded}

func load_scene_events(state: Dictionary, scene_id: int) -> Dictionary:
	var issue: String = validate_state(state)
	if not issue.is_empty(): return _failure(issue, scene_id)
	var selected: Dictionary = _range(state, scene_id)
	if selected.has("error"): return selected
	var candidate: Dictionary = state.duplicate(true)
	for index in range(selected.count):
		var at: int = (selected.first + index) * RECORD_BYTES
		candidate.active_slots[index] = candidate.global_events.slice(at, at + RECORD_BYTES)
	# T201 overwrites only the current prefix. Known older backing slots remain
	# available; never clear them merely because the next scene is smaller.
	candidate.loaded_scene_id = scene_id; candidate.event_count = selected.count
	return {"state": candidate, "raw_count": selected.raw_count, "loaded_count": selected.count, "first_global_index": selected.first}

func commit_current_events(state: Dictionary, current_scene = -1) -> Dictionary:
	var issue: String = validate_state(state)
	if not issue.is_empty(): return _failure(issue)
	if typeof(current_scene) != TYPE_INT: return _failure("T175 current scene must be an integer")
	if current_scene == -1: current_scene = state.loaded_scene_id
	if current_scene < 1 or current_scene >= int(state.scene_records.size() / 8): return _failure("T175 requires a current scene inside the table")
	# T175 consumes the caller's current count; it does not recompute T201's
	# next-scene difference. A resource switch without flag4 retains the loaded
	# backing while changing the CURRENT scene; the live owner passes that scene.
	var first: int = state.scene_records.decode_u16((current_scene - 1) * 8 + 6)
	if first > 32767: return _failure("scene event writeback requires unresolved signed source address", current_scene)
	var end: int = (first + state.event_count) * RECORD_BYTES
	if end > state.global_events.size(): return _failure("current event writeback exceeds owned global table", current_scene)
	var candidate: Dictionary = state.duplicate(true)
	for index in range(state.event_count):
		var at: int = (first + index) * RECORD_BYTES
		var row: PackedByteArray = state.active_slots[index]
		for offset in range(RECORD_BYTES): candidate.global_events[at + offset] = row[offset]
	return {"state": candidate, "written_records": state.event_count, "first_global_index": first}

func event_record(state: Dictionary, event_id: int) -> Dictionary:
	var issue: String = validate_state(state)
	if not issue.is_empty(): return _failure(issue)
	if event_id < 1 or event_id > CAPACITY: return _failure("runtime event slot outside owned1..160")
	var bytes = state.active_slots[event_id - 1]
	if bytes == null: return _failure("runtime event slot has no known source bytes")
	return {"value": bytes.duplicate(), "runtime_event_id": event_id, "inside_current_count": event_id <= state.event_count}

## The original event array always has 160 records, so a caller that materializes
## a record into an Unknown slot is writing real bytes. This differs from
## replace_event_record, which requires a prior known record.
func write_event_record(state: Dictionary, event_id: int, bytes: PackedByteArray) -> Dictionary:
	var issue: String = validate_state(state)
	if not issue.is_empty(): return _failure(issue)
	if event_id < 1 or event_id > CAPACITY: return _failure("runtime event slot outside owned1..160")
	if bytes.size() != RECORD_BYTES: return _failure("written event requires32 bytes")
	var candidate: Dictionary = state.duplicate(true); candidate.active_slots[event_id - 1] = bytes.duplicate()
	return {"state": candidate}

func replace_event_record(state: Dictionary, event_id: int, bytes: PackedByteArray) -> Dictionary:
	var selected: Dictionary = event_record(state, event_id)
	if selected.has("error"): return selected
	if bytes.size() != RECORD_BYTES: return _failure("replacement event requires32 bytes")
	var candidate: Dictionary = state.duplicate(true); candidate.active_slots[event_id - 1] = bytes.duplicate()
	return {"state": candidate}
