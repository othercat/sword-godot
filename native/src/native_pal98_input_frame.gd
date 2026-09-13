# SPDX-License-Identifier: MIT
extends RefCounted
## One nominal map tick. Input polling can also be used without movement by
## dialogue hosts. The moving branch uses ffxy and whole-step rollback;
## the idle branch rebuilds standing frames without shifting the trail.
const DirectionInput = preload("res://src/native_pal98_direction_input.gd")
const Requests = preload("res://src/native_pal98_scene_sprite_requests.gd")
var error: String = ""
var _input = DirectionInput.new()
var _facing = null
var _probe = null
var _logical_map: Array = []
var _layer_base: int = 0
var _events = null
var _confirm_slot: int = -1

func _failure(message: String) -> Dictionary:
	error = "pal98-input-frame: " + message
	return {"error": error}

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _signed(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

func bind(facing, probe, logical_map: Array, layer_base: int, confirm_slot: int = -1) -> bool:
	if facing == null or not facing.has_method("answer") or probe == null or not probe.has_method("probe"):
		error = "pal98-input-frame: movement and collision owners required"; return false
	if logical_map.size() < 8 or not _i2(layer_base) or confirm_slot < -1 or confirm_slot >= logical_map.size():
		error = "pal98-input-frame: invalid map, layer or confirm slot"; return false
	for slot in range(logical_map.size()):
		if typeof(logical_map[slot]) != TYPE_INT or logical_map[slot] < 0:
			error = "pal98-input-frame: key map requires nonnegative integer indices"; return false
	_facing = facing; _probe = probe; _logical_map = logical_map.duplicate()
	_layer_base = layer_base; _confirm_slot = confirm_slot; error = ""; return true

func bind_events(storage) -> bool:
	if storage == null or not storage.has_method("event_record"):
		error = "pal98-input-frame: scene-events storage required"; return false
	_events = storage; error = ""; return true

## A new press is level 2. Held (3), released (1) and idle (0) are not edges.
func poll(key_levels) -> Dictionary:
	if _facing == null: return _failure("bind input owners first")
	var result: Dictionary = _input.resolve(key_levels, _logical_map)
	if result.has("error"): return _failure(str(result.error))
	var confirm := false
	if _confirm_slot >= 0:
		var mapped: int = _logical_map[_confirm_slot]
		if mapped >= key_levels.size(): return _failure("confirm mapping leaves key table")
		var level = key_levels[mapped]
		if typeof(level) != TYPE_INT or level < 0 or level > 3: return _failure("confirm level requires 0..3")
		confirm = level == 2
	result.confirm = confirm
	return result

func tick(state: Dictionary, key_levels) -> Dictionary:
	error = ""
	var resolved: Dictionary = poll(key_levels)
	if resolved.has("error"): return resolved
	if not state.get("globals") is Dictionary: return _failure("tick requires globals")
	var next: Dictionary = state.duplicate(true)
	var g: Dictionary = next.globals
	for key in ["party_x", "party_y", "viewport_x", "viewport_y"]:
		if not _i2(g.get(key)): return _failure("movement requires I2 " + key)
	# These are caller-owned pre-step words, even on idle/blocked frames.
	g.previous_x = _signed(g.viewport_x + g.party_x)
	g.previous_y = _signed(g.viewport_y + g.party_y)
	g.previous_viewport_x = g.viewport_x; g.previous_viewport_y = g.viewport_y
	var moved := false; var pending_step := false
	if resolved.direction_x != 0 or resolved.direction_y != 0:
		var iso: Dictionary = _input.convert_to_isometric(resolved.direction_x, resolved.direction_y)
		var prepared: Dictionary = _input.probe_and_prepare(
			{"x": g.party_x, "y": g.party_y}, {"x": g.viewport_x, "y": g.viewport_y},
			iso.direction_x, iso.direction_y, _probe)
		if prepared.has("error"): return _failure(str(prepared.error))
		var faced: Dictionary = _facing.answer({"kind": "face_party_toward",
			"delta_x": iso.direction_x, "delta_y": iso.direction_y, "state": next})
		if faced.has("error"): return _failure(str(faced.error))
		next = faced.state; g = next.globals
		pending_step = prepared.get("pending_steps") == 1
		if pending_step:
			for key in ["ffxy_max_x", "ffxy_max_y"]:
				if not _i2(g.get(key)) or g[key] < 0: return _failure("ffxy requires explicit nonnegative I2 " + key)
			var x: int = g.viewport_x + prepared.delta_x; var y: int = g.viewport_y + prepared.delta_y
			if not _i2(x) or not _i2(y): return _failure("viewport step leaves I2")
			x = clampi(x, 0, g.ffxy_max_x); y = clampi(y, 0, g.ffxy_max_y)
			if x == g.previous_viewport_x: y = g.previous_viewport_y
			if y == g.previous_viewport_y: x = g.previous_viewport_x
			g.viewport_x = x; g.viewport_y = y
			moved = x != g.previous_viewport_x or y != g.previous_viewport_y
	g.world_x = _signed(g.viewport_x + g.party_x); g.world_y = _signed(g.viewport_y + g.party_y)
	var result: Dictionary = _facing.answer({"kind": "post_move_update" if pending_step else "rebuild_no_move_frames", "state": next})
	if result.has("error"): return _failure(str(result.error))
	var final: Dictionary = result.state
	var party: Dictionary = Requests.party_requests(final.globals.member_last,
		final.globals.follower_count, final.get("party_records", []), _layer_base)
	if party.has("error"): return _failure(str(party.error))
	var requests: Array = party.value
	if _events != null:
		var events: Dictionary = Requests.event_requests(_events, final.get("events", {}),
			final.globals.viewport_x, final.globals.viewport_y)
		if events.has("error"): return _failure(str(events.error))
		requests += events.value
	return {"completed": true, "state": final, "requests": requests, "input_move": moved,
		"confirm": resolved.confirm, "receipt": {"kind": "input_frame_tick",
		"direction": [resolved.direction_x, resolved.direction_y], "moved": moved, "confirm": resolved.confirm}}
