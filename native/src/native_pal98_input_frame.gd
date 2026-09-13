# SPDX-License-Identifier: MIT
extends RefCounted
## The production input frame tick of the ordinary-map loop: one logic tick
## polls the eight logical key slots, converts the resolved direction to the
## isometric diagonal, probes the step candidate through the two-level
## collision owner, faces the party through the real extf owner, applies the
## 16/8 viewport step and runs PostMoveUpdate's world/phase/trail/member
## work, then publishes the T209 party (and, when bound, T213 event) draw
## requests computed from the resulting state.
##
## This owner is the production caller of the frame chain; assembling these
## requests inside a test does not substitute for it. The state stays with
## the caller: a refused or failed tick publishes nothing. previous_x/y are
## refreshed here (as the caller of PostMoveUpdate) exactly when the tick
## moves the viewport; the scene-events storage must be rebound by the host
## when the scene or its events change.
const DirectionInput = preload("res://src/native_pal98_direction_input.gd")
const Requests = preload("res://src/native_pal98_scene_sprite_requests.gd")

var error: String = ""
var _input: DirectionInput
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

## facing: the movement owner with the member executor bound; probe: the
## two-level collision owner; logical_map: the eight-entry G0854 slot map
## (nine or more when a confirm slot is bound); layer_base: the explicit T209
## layer base word. confirm_slot: the logical slot (index into logical_map)
## whose new press means the player's confirm; the original confirm mapping
## is not decoded, so the host binds it explicitly and -1 keeps the tick
## direction-only.
func bind(facing, probe, logical_map: Array, layer_base: int, confirm_slot: int = -1) -> bool:
	if facing == null or not facing.has_method("answer"):
		error = "pal98-input-frame: the movement owner is required"; return false
	if probe == null or not probe.has_method("probe"):
		error = "pal98-input-frame: the collision probe owner is required"; return false
	if logical_map.size() < 8:
		error = "pal98-input-frame: the logical key map requires eight slots"; return false
	if not _i2(layer_base):
		error = "pal98-input-frame: the T209 layer base requires an I2"; return false
	if confirm_slot >= 0 and confirm_slot >= logical_map.size():
		error = "pal98-input-frame: the confirm slot must index the logical key map"; return false
	_facing = facing; _probe = probe; _logical_map = logical_map.duplicate()
	_layer_base = layer_base; _confirm_slot = confirm_slot
	_input = DirectionInput.new(); error = ""; return true

## Optional T213 side: the scene-events storage. Rebind after the scene or
## its events change; an unbound storage publishes party requests only.
func bind_events(storage) -> bool:
	if storage == null:
		error = "pal98-input-frame: the scene-events storage is required"; return false
	_events = storage; error = ""; return true

## One logic tick. Returns the new state plus the draw requests computed from
## it; every request kind the tick emitted is listed in the receipt.
func tick(state: Dictionary, key_levels) -> Dictionary:
	error = ""
	if _facing == null: return _failure("bind the movement, probe and key-map owners first")
	if not state is Dictionary or not state.get("globals") is Dictionary:
		return _failure("tick requires the pending state and globals")
	var resolved: Dictionary = _input.resolve(key_levels, _logical_map)
	if resolved.has("error"): return _failure(str(resolved.error))
	var direction_x: int = resolved.direction_x
	var direction_y: int = resolved.direction_y
	# The bound confirm slot is a new-press/held level on the same key-state
	# table; the tick reports it so the host can gate dialogue advances on it.
	var confirm := false
	if _confirm_slot >= 0:
		var mapped: int = _logical_map[_confirm_slot]
		if mapped >= 0 and mapped < key_levels.size():
			var level = key_levels[mapped]
			confirm = typeof(level) == TYPE_INT and level >= 2
	var moving := false
	var next_state: Dictionary = state
	if direction_x != 0 or direction_y != 0:
		var iso: Dictionary = _input.convert_to_isometric(direction_x, direction_y)
		if iso.has("error"): return _failure(str(iso.error))
		var globals: Dictionary = state.globals
		for key in ["party_x", "party_y", "viewport_x", "viewport_y"]:
			if not _i2(globals.get(key)): return _failure("movement requires the explicit WORD " + key)
		var prepared: Dictionary = _input.probe_and_prepare(
			{"x": globals.party_x, "y": globals.party_y},
			{"x": globals.viewport_x, "y": globals.viewport_y},
			iso.direction_x, iso.direction_y, _probe)
		if prepared.has("error"): return _failure(str(prepared.error))
		if prepared.get("pending_steps") == 1:
			var faced: Dictionary = _facing.answer({"kind": "face_party_toward",
				"delta_x": prepared.delta_x, "delta_y": prepared.delta_y, "state": state})
			if faced.has("error"): return _failure(str(faced.error))
			var stepped: Dictionary = faced.state
			var step_globals: Dictionary = stepped.globals
			# This owner is PostMoveUpdate's caller on the input path: refresh
			# the previous-position words before the step, as the reviewed walk
			# loop does, then move the viewport by the 16/8 isometric deltas.
			step_globals.previous_x = step_globals.world_x
			step_globals.previous_y = step_globals.world_y
			step_globals.previous_viewport_x = step_globals.viewport_x
			step_globals.previous_viewport_y = step_globals.viewport_y
			var viewport_x: int = step_globals.viewport_x + prepared.delta_x
			var viewport_y: int = step_globals.viewport_y + prepared.delta_y
			if not _i2(viewport_x) or not _i2(viewport_y):
				return _failure("the input viewport step leaves I2")
			step_globals.viewport_x = viewport_x
			step_globals.viewport_y = viewport_y
			next_state = stepped
			moving = true
	var post: Dictionary = _facing.answer({"kind": "post_move_update", "state": next_state})
	if post.has("error"): return _failure(str(post.error))
	var final: Dictionary = post.state
	var party: Dictionary = Requests.party_requests(final.globals.member_last,
		final.globals.follower_count, final.get("party_records", []), _layer_base)
	if party.has("error"): return _failure(str(party.error))
	var requests: Array = party.value
	if _events != null:
		var events: Dictionary = Requests.event_requests(_events, final,
			final.globals.viewport_x, final.globals.viewport_y)
		if events.has("error"): return _failure(str(events.error))
		requests += events.value
	return {"completed": true, "state": final, "requests": requests, "input_move": moving,
		"confirm": confirm,
		"receipt": {"kind": "input_frame_tick", "direction": [direction_x, direction_y],
			"moved": moving, "confirm": confirm}}
