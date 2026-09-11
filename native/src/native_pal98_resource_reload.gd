# SPDX-License-Identifier: MIT
extends RefCounted
## T212/T246 orchestration over actual source-bound event/sprite/map caches.
## Explicit requests must be completed by the script, display, save and audio
## owners. Request emission is not execution; no ordinary Session is activated.
const Events = preload("res://src/native_pal98_scene_events.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const MAX_RESTARTS = 64
var error: String = ""
var _storage = Events.new()
var _equipment = Equipment.new()
var _graphics
var _source: Dictionary = {}
var _state: Dictionary = {}
var _cache
var _map: Dictionary = {}
var _phase: String = "idle"
var _pending: Dictionary = {}
var _generation: int = 0
var _serial: int = 0
var _restarts: int = 0
var _enter_scene: int = 0
var _trace: Array = []

func load_source(tables, graphics) -> bool:
	if _phase not in ["idle", "complete", "failed"]: error = "resource reload is active"; return false
	if tables == null or graphics == null: error = "admitted sources required"; return false
	var tm: Dictionary = tables.metadata(); var gm: Dictionary = graphics.metadata()
	if tm.is_empty() or gm.is_empty() or tm.get("provenance", {}).get("source_revision") != "sha256:" + str(gm.get("source_fingerprint", "")):
		error = "resource reload source origin mismatch"; return false
	var storage = Events.new(); var equipment = Equipment.new(); var reader = graphics.open_records()
	if not storage.load_source(tables): error = storage.error; return false
	if not equipment.read_tables(tables.copy_chunk("data", 3), tables.copy_chunk("sss", 2), tables.copy_chunk("sss", 4)):
		error = equipment.error; return false
	if reader == null: error = "graphics reader unavailable"; return false
	_storage = storage; _equipment = equipment; _graphics = reader
	_source = {"tables": tm.fingerprint, "graphics": gm.fingerprint}; error = ""; return true

func _state_issue(state: Dictionary) -> String:
	if not state.get("globals") is Dictionary or not state.get("events") is Dictionary or not state.get("equipment") is Dictionary:
		return "resource reload requires explicit globals/event/equipment state"
	if not state.get("party_records") is Array or not state.get("inventory_bytes") is PackedByteArray:
		return "resource reload requires explicit party and inventory backing"
	var issue: String = _storage.validate_state(state.events)
	if not issue.is_empty(): return issue
	return _equipment.validate_state(state.equipment)

func start(state: Dictionary, cache, map_cache: Dictionary = {}) -> Dictionary:
	if _phase not in ["idle", "complete", "failed"]: return {"error": "resource reload already active"}
	if _source.is_empty() or cache == null: return {"error": "resource reload source/cache unavailable"}
	var issue = _state_issue(state)
	if not issue.is_empty(): return {"error": issue}
	var cs: Dictionary = cache.source()
	if cs.get("table_fingerprint") != _source.tables or cs.get("graphics_fingerprint") != _source.graphics:
		return {"error": "resource reload cache identity mismatch"}
	_cache = cache.fork_for_reload()
	if _cache == null: return {"error": "resource reload cache cannot be forked"}
	_state = state.duplicate(true); _map = map_cache.duplicate(true)
	_phase = "entry"; _pending = {}; _generation += 1; _serial = 0; _restarts = 0; _trace = []; error = ""
	return _advance()

func cancel() -> void:
	_generation += 1; _pending = {}; _state = {}; _map = {}; _cache = null; _phase = "idle"

func _fail(message: String) -> Dictionary:
	error = message
	var phase = _phase; _phase = "failed"; _pending = {}
	return {"error": message, "phase": phase, "trace": _trace.duplicate(true)}

func _words(keys: Array) -> String:
	for key in keys:
		var value = _state.globals.get(key)
		if not value is int or value < -32768 or value > 32767: return "known signed I2 required: " + key
	return ""

func _request(kind: String, details: Dictionary = {}) -> Dictionary:
	_serial += 1
	_pending = {"id": str(get_instance_id()) + ":" + str(_generation) + ":" + str(_serial), "kind": kind}
	var request = _pending.duplicate(true); request.merge(details, false)
	request.state = _state.duplicate(true)
	return {"request": request, "trace": _trace.duplicate(true)}

func resume(request_id: String, response: Dictionary) -> Dictionary:
	# A stale completion cannot change the pending operation or new generation.
	if _pending.is_empty() or request_id != _pending.id: return {"error": "stale resource request completion"}
	if response.has("error"): return _fail(str(response.error))
	var kind: String = _pending.kind
	if kind in ["load_save", "enter_script"]:
		if not response.get("state") is Dictionary: return _fail("completed state owner did not return state")
		var issue = _state_issue(response.state)
		if not issue.is_empty(): return _fail(issue)
		if kind == "enter_script":
			var entry = response.get("return_entry")
			if not entry is int or entry < 0 or entry > 65535: return _fail("EnterScript must return its ByRef entry WORD")
		_state = response.state.duplicate(true)
		if kind == "enter_script":
			_state.events.scene_records.encode_u16((_enter_scene - 1) * 8 + 2, response.return_entry)
			_phase = "after_enter"
		else: _phase = "common"
	else:
		if response.get("completed") != true or typeof(response.get("completed")) != TYPE_BOOL:
			return _fail("display/audio request requires explicit completion")
		_phase = "party" if kind == "render_background" else "equipment"
	_pending = {}
	return _advance()

func _scene_word(offset: int) -> Dictionary:
	var scene: int = _state.globals.current_scene
	var records: PackedByteArray = _state.events.scene_records
	if scene < 1 or scene >= int(records.size() / 8): return {"error": "current scene outside runtime scene table"}
	return {"value": records.decode_u16((scene - 1) * 8 + offset)}

func _ensure_map() -> String:
	var issue = _words(["loaded_map_id"])
	if not issue.is_empty(): return issue
	var selected = _scene_word(0)
	if selected.has("error"): return selected.error
	var map_id: int = selected.value
	if map_id >= 32768: return "negative signed original MAP identity is not implemented"
	if map_id != _state.globals.loaded_map_id:
		var map: Dictionary = _graphics.decoded_chunk("MAP.MKF", map_id)
		if map.has("error"): return map.error
		var gop: Dictionary = _graphics.raw_chunk("GOP.MKF", map_id)
		if gop.has("error"): return gop.error
		_map = {"map_id": map_id, "graphics_fingerprint": _source.graphics,
			"map_bytes": map.value.duplicate(), "gop_bytes": gop.value.duplicate(),
			"map_source": map.source.duplicate(true), "gop_source": gop.source.duplicate(true)}
		_trace.append("load_map_gop:" + str(map_id))
	elif _map.get("map_id") != map_id or _map.get("graphics_fingerprint") != _source.graphics:
		return "unchanged loaded map identity has no known matching cache"
	if not _map.get("map_bytes") is PackedByteArray or _map.map_bytes.size() != 65536 or not _map.get("gop_bytes") is PackedByteArray or _map.gop_bytes.size() < 2:
		return "loaded MAP/GOP cache backing is missing or outside supported shape"
	# Common-tail assignment also occurs on the original no-I/O branch.
	_state.globals.loaded_map_id = map_id
	return ""

func _advance() -> Dictionary:
	while true:
		var g: Dictionary = _state.globals
		var issue = _words(["resource_flags", "current_scene", "requested_scene"])
		if not issue.is_empty(): return _fail(issue)
		match _phase:
			"entry":
				_restarts += 1
				if _restarts > MAX_RESTARTS: return _fail("EnterScript scene reload budget exceeded")
				g.battle_mode = 0; g.move_dx = 0; g.move_dy = 0; _trace.append("entry")
				if (g.resource_flags & 32) != 0:
					issue = _words(["save_slot"])
					if not issue.is_empty(): return _fail(issue)
					return _request("load_save", {"slot": g.save_slot})
				if g.current_scene != g.requested_scene:
					g.wave_phase = 0; g.wave_amplitude = 0
					if g.current_scene > 0:
						var committed = _storage.commit_current_events(_state.events, g.current_scene)
						if committed.has("error"): return _fail(committed.error)
						_state.events = committed.state; _trace.append("commit_events")
				_phase = "common"
			"common":
				g.map_mode = 0; g.party_x = 160; g.party_y = 112; g.current_scene = g.requested_scene
				if (g.resource_flags & 4) != 0:
					var loaded = _storage.load_scene_events(_state.events, g.current_scene)
					if loaded.has("error"): return _fail(loaded.error)
					_state.events = loaded.state; _trace.append("load_events")
				issue = _ensure_map()
				if not issue.is_empty(): return _fail(issue)
				var sprites = _cache.load_events(_storage, _state.events)
				if sprites.has("error"): return _fail(sprites.error)
				_state.events = sprites.state; _trace.append("load_event_sprites")
				issue = _words(["viewport_x", "viewport_y"])
				if not issue.is_empty(): return _fail(issue)
				g.ring_x = 0; g.ring_y = 0; g.background_x = g.viewport_x; g.background_y = g.viewport_y
				_phase = "background"; _trace.append("render_background")
				return _request("render_background", {"map_cache": _map.duplicate(true)})
			"party":
				if (g.resource_flags & 1) != 0:
					issue = _words(["member_last", "follower_count"])
					if not issue.is_empty(): return _fail(issue)
					var ids: Array = []
					for role in range(6):
						var word: int = _state.equipment.role_words[12 + role]
						ids.append(word if word < 32768 else word - 65536)
					var party = _cache.load_party(g.member_last, g.follower_count, _state.party_records, ids)
					if party.has("error"): return _fail(party.error)
					_state.party_records = party.party_records; _trace.append("load_party_sprites")
				_phase = "enter"
			"enter":
				if (g.resource_flags & 8) != 0:
					g.resource_flags &= 2
					var entry = _scene_word(2)
					if entry.has("error"): return _fail(entry.error)
					_enter_scene = g.current_scene; _trace.append("enter_script:" + str(_enter_scene))
					return _request("enter_script", {"entry": entry.value, "event_id": 0, "scene_id": _enter_scene})
				_phase = "midi"
			"after_enter":
				_phase = "entry" if g.requested_scene != g.current_scene else "midi"
			"midi":
				if (g.resource_flags & 2) != 0:
					issue = _words(["midi_track"])
					if not issue.is_empty(): return _fail(issue)
					_trace.append("play_midi")
					return _request("play_midi", {"track": g.midi_track, "loop": 1})
				_phase = "equipment"
			"equipment":
				g.resource_flags = 0
				issue = _words(["member_last"])
				if not issue.is_empty(): return _fail(issue)
				if g.member_last + 1 != _state.equipment.party_roles.size(): return _fail("party/equipment member count mismatch")
				for slot in range(g.member_last + 1):
					if slot >= _state.party_records.size() or not _state.party_records[slot] is Dictionary: return _fail("party/equipment backing mismatch")
					var role_id = _state.party_records[slot].get("role_id")
					if typeof(role_id) != TYPE_INT or role_id != _state.equipment.party_roles[slot]: return _fail("party/equipment role identity mismatch")
				var prepared = _equipment.prepare_party_equipment(_state.equipment, _state.inventory_bytes)
				if prepared.has("error"): return _fail(prepared.error)
				_state.equipment = prepared.state; _state.inventory_bytes = prepared.inventory_bytes
				_trace.append("prepare_equipment"); _phase = "complete"
				return {"state": _state.duplicate(true), "cache": _cache, "map_cache": _map.duplicate(true), "trace": _trace.duplicate(true)}
			_: return _fail("invalid resource reload phase")
	return _fail("resource reload ended without a terminal phase")
