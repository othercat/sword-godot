# SPDX-License-Identifier: MIT
extends RefCounted
## Real EnterScript owner for the T212 resource chain.
##
## `native_pal98_resource_reload.gd` requests EnterScript/event0 with the current
## scene's enter word. This owner answers that request with the actual script:
## it re-reads the scene record from the admitted source, runs the reviewed T258
## control flow over the real SSS4 instruction pool, consumes the T240 commands
## it can execute through `native_pal98_script_commands.gd`, relays the
## remaining host effects outward, and returns the ByRef entry plus the updated
## state to the caller.
##
## It does not activate an ordinary Session, render, play audio or write saves.
## Dialogue rendering, sprite loading and every unlisted command stay explicit
## host or diagnostic boundaries. The source-only preview guard is unchanged.
const Trigger = preload("res://src/native_pal98_trigger.gd")
const Commands = preload("res://src/native_pal98_script_commands.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const MAX_COMMANDS = 4096

var error: String = ""
var _trigger
var _commands
var _records
var _storage
var _identity: String = ""
var _scene_count: int = 0
var _phase: String = "idle"
var _scene: int = 0
var _entry: int = 0
var _event_id: int = 0
var _scene_receipt: Dictionary = {}
var _pending: Dictionary = {}
var _owner_queue: Array = []
var _owner_resume: Dictionary = {}
var _generation: int = 0
var _serial: int = 0
var _commands_run: int = 0
var _effects: Array = []
var _unimplemented: Array = []
var _trace: Array = []

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _u2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 65535

func load_source(source) -> bool:
	if _phase not in ["idle", "complete", "failed"]:
		error = "pal98-enter: owner is active"; return false
	if source == null or source.metadata().is_empty():
		error = "pal98-enter: admitted source snapshot required"; return false
	var records = source.open_records()
	var storage = Events.new()
	var trigger = Trigger.new()
	var commands = Commands.new()
	if records == null or not storage.load_source(source):
		error = "pal98-enter: source tables unavailable"; return false
	if not trigger.load_source(source):
		error = "pal98-enter: " + trigger.error; return false
	if not commands.load_source(source):
		error = "pal98-enter: " + commands.error; return false
	var summary: Dictionary = records.table_summary()
	if not summary.get("issues", []).is_empty() or not summary.get("counts", {}).has("scenes"):
		error = "pal98-enter: source scene table is malformed"; return false
	_records = records; _storage = storage; _trigger = trigger; _commands = commands
	_identity = source.metadata().fingerprint; _scene_count = int(summary.counts.scenes)
	error = ""; return true

func source_identity() -> String:
	return _identity

func scene_count() -> int:
	return _scene_count

func commands() -> Array:
	return _effects.duplicate(true)

func _failure(message: String, step: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	error = message
	var diagnostic: Dictionary = {"source_fingerprint": _identity, "phase": _phase, "scene": _scene,
		"entry": _entry, "event_id": _event_id, "commands_run": _commands_run,
		"scene_source": _scene_receipt.duplicate(true)}
	if step.has("trace"): diagnostic.trigger_trace = step.trace
	diagnostic.merge(extra, true)
	_phase = "failed"; _pending = {}; _owner_queue = []; _owner_resume = {}
	return {"error": "pal98-enter: " + message, "diagnostic": diagnostic,
		"effects": _effects.duplicate(true), "unimplemented": _unimplemented.duplicate(true),
		"trace": _trace.duplicate(true)}

func _state_issue(state: Dictionary) -> String:
	for key in ["globals", "events", "dialogue", "rng"]:
		if not state.get(key) is Dictionary: return "enter script requires explicit " + key
	if not state.get("party_records") is Array: return "enter script requires explicit party records"
	if not state.get("equipment") is Dictionary: return "enter script requires explicit equipment state"
	var issue: String = _storage.validate_state(state.events)
	if not issue.is_empty(): return issue
	if state.party_records.is_empty(): return "enter script requires at least one party record"
	for record in state.party_records:
		if not record is Dictionary: return "enter script party record shape"
	return ""

## Run the scene's real enter script. The caller adopts the returned state and
## ByRef entry only on terminal success; failures publish no candidate.
func start(state: Dictionary, scene_id, entry, event_id = 0) -> Dictionary:
	if _phase not in ["idle", "complete", "failed"]: return {"error": "pal98-enter: owner is active"}
	if _identity.is_empty(): return {"error": "pal98-enter: source unavailable"}
	if not _u2(scene_id) or scene_id < 1 or scene_id > _scene_count:
		return {"error": "pal98-enter: runtime scene outside the playable table"}
	if not _u2(entry) or not _i2(event_id):
		return {"error": "pal98-enter: enter script requires a U2 entry and I2 event context"}
	if not state is Dictionary: return {"error": "pal98-enter: explicit state required"}
	var issue: String = _state_issue(state)
	if not issue.is_empty(): return {"error": "pal98-enter: " + issue}
	var scene: Dictionary = _records.scene_for_runtime_id(scene_id)
	if scene.has("error"): return {"error": "pal98-enter: " + str(scene.error), "diagnostic": scene.get("diagnostic", {})}
	# T212 reads the enter word from the loaded (mutable) scene table and writes
	# the ByRef result back into the same record, so that record is the authority.
	# The immutable source record is kept beside it as a review receipt.
	var scene_records: PackedByteArray = state.events.scene_records
	var state_entry: int = scene_records.decode_u16((scene_id - 1) * 8 + 2)
	if state_entry != entry:
		return {"error": "pal98-enter: EnterScript request does not match the loaded scene record's enter word",
			"diagnostic": {"requested_entry": entry, "loaded_entry": state_entry,
				"source_entry": scene.value.enter_script_word, "scene_source": scene.source.duplicate(true)}}
	error = ""
	_scene = scene_id; _entry = entry; _event_id = event_id
	_scene_receipt = scene.source.duplicate(true); _scene_receipt.merge(scene.value.duplicate(true), true)
	_effects = []; _unimplemented = []; _trace = []; _pending = {}; _commands_run = 0
	_serial = 0; _generation += 1; _phase = "active"
	return _advance(_trigger.start(state.duplicate(true), entry, event_id))

func cancel() -> void:
	_generation += 1; _pending = {}
	_owner_queue = []; _owner_resume = {}
	if _trigger != null: _trigger.cancel()
	_phase = "idle"

## Relays one pending command-owner request. The trigger stays suspended until
## every request of that command has been answered.
func _relay_owner() -> Dictionary:
	var request: Dictionary = _owner_queue.pop_front()
	_serial += 1
	_pending = {"id": "%s:%s:%s" % [str(get_instance_id()), _generation, _serial],
		"owner": true, "kind": request.kind}
	var relay: Dictionary = request.duplicate(true)
	relay.id = _pending.id
	relay.scene = _scene
	relay.entry = _entry
	relay.scene_source = _scene_receipt.duplicate(true)
	# The host needs the state as it stands after the command's own effects, so
	# sprite and equipment owners work on the new composition.
	relay.state = _owner_resume.get("state", {}).duplicate(true)
	return {"request": relay, "effects": _effects.duplicate(true),
		"unimplemented": _unimplemented.duplicate(true), "trace": _trace.duplicate(true)}

func _relay(step: Dictionary) -> Dictionary:
	var request: Dictionary = step.request
	_serial += 1
	_pending = {"id": "%s:%s:%s" % [str(get_instance_id()), _generation, _serial],
		"inner": request.id, "kind": request.kind}
	var relay: Dictionary = {"id": _pending.id, "kind": request.kind, "scene": _scene,
		"entry": _entry, "event_id": request.get("event_id"), "pc": request.get("pc"),
		"scene_source": _scene_receipt.duplicate(true)}
	for key in ["effect", "dialogue_source"]:
		if request.has(key):
			var value = request[key]
			relay[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	# Every relayed effect carries the pending state so a host can answer with the
	# same explicit backing the trigger will validate on the way back.
	relay.state = request.state.duplicate(true) if request.get("state") is Dictionary else {}
	return {"request": relay, "effects": _effects.duplicate(true),
		"unimplemented": _unimplemented.duplicate(true), "trace": _trace.duplicate(true)}

func _advance(step: Dictionary) -> Dictionary:
	while true:
		if step.has("error"): return _failure(str(step.error), step, step.get("diagnostic", {}))
		if step.has("return_entry"):
			if not _u2(step.return_entry) or not _i2(step.get("return_event_id")):
				return _failure("enter script returned an invalid ByRef entry", step)
			_phase = "complete"
			return {"state": step.state, "return_entry": step.return_entry,
				"return_event_id": step.return_event_id, "steps": step.get("steps", 0),
				"scene": _scene, "scene_source": _scene_receipt.duplicate(true),
				"effects": _effects.duplicate(true), "unimplemented": _unimplemented.duplicate(true),
				# A terminal success with named sub-effect gaps is not full
				# completion of the original entry script; callers must not read
				# this as an unimplemented-free result.
				"partial": not _unimplemented.is_empty(),
				"trace": _trace.duplicate(true)}
		if not step.has("request"): return _failure("enter script stopped without a terminal phase", step)
		var request: Dictionary = step.request
		if request.kind != "execute_command": return _relay(step)
		if _commands_run >= MAX_COMMANDS: return _failure("enter script command budget exceeded", step)
		_commands_run += 1
		var result: Dictionary = _commands.consume(step.request.state, request)
		if result.has("error"):
			# Terminate the T258 invocation through its own host-error contract so a
			# later start is not blocked by a still-active trigger.
			_trigger.resume(request.id, {"error": str(result.error)})
			return _failure(str(result.error), step, result.get("diagnostic", {}))
		_effects.append_array(result.effects)
		_unimplemented.append_array(result.unimplemented)
		_trace.append({"command": result.opcode, "effects": result.effects.duplicate(true),
			"unimplemented": result.unimplemented.duplicate(true)})
		var owner_requests: Array = result.get("requests", [])
		if not owner_requests.is_empty():
			# Command-owned work (sprite/equipment/member owners) must be answered
			# by the host before the trigger continues with this command's result.
			_owner_queue = owner_requests.duplicate(true)
			_owner_resume = {"id": request.id, "state": result.state,
				"entry": result.entry, "event_id": result.event_id}
			_trace.append({"command": result.opcode, "requests": owner_requests.duplicate(true)})
			return _relay_owner()
		step = _trigger.resume(request.id, {"state": result.state, "entry": result.entry,
			"event_id": result.event_id})
	return _failure("enter script ended without a terminal phase")

func resume(request_id: String, response: Dictionary) -> Dictionary:
	if _pending.is_empty() or request_id != _pending.id:
		return {"error": "pal98-enter: stale or absent script completion"}
	var kind: String = _pending.kind
	var owner_request: bool = _pending.get("owner", false)
	var inner: String = _pending.get("inner", "")
	_pending = {}
	if response.has("error"): return _failure("host failed: " + str(response.error))
	if owner_request:
		if response.get("completed") != true or typeof(response.get("completed")) != TYPE_BOOL:
			return _failure("command-owner request requires explicit completion")
		var resume: Dictionary = _owner_resume.duplicate(true)
		if response.has("state"):
			if not response.state is Dictionary: return _failure("owner request state must be a dictionary")
			var issue: String = _state_issue(response.state)
			if not issue.is_empty(): return _failure(issue)
			resume.state = response.state
		if not _owner_queue.is_empty(): return _relay_owner()
		_owner_resume = {}
		return _advance(_trigger.resume(resume.id, {"state": resume.state, "entry": resume.entry,
			"event_id": resume.event_id}))
	if kind == "dialogue":
		if response.size() != 1 or not response.get("event") is Dictionary:
			return _failure("dialogue completion must carry exactly one explicit event")
		return _advance(_trigger.resume(inner, {"event": response.event}))
	return _advance(_trigger.resume(inner, response))
