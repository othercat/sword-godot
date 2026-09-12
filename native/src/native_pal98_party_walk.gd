# SPDX-License-Identifier: MIT
extends RefCounted
## Shared party-walk body behind ExecuteScriptCommand 0x0070 (speed 2) and the
## 0x007A/0x007B entries (speeds 4/8).
##
## The reviewed body computes the walk target with the 0x0046 formula, faces the
## party through the external `extf` stub (0x004172D8), advances the viewport by
## the generated formation tables scaled by the speed, and per step calls
## PostMoveUpdate (0x0041D2CC), StartFrameAndProcessEvents(0) (0x0041D17C),
## UpdateViewportAndPartyPosition (0x0041CC3C) and RenderSceneFrame(1)
## (0x0041CB64), looping while the world position has not reached the target and
## syncing the members from the trail on arrival.
##
## Facing and the world/trail arithmetic stay with their owners: this module owns
## the target, the loop and the viewport steps, and reports every step as an
## explicit request.
# G044C / G0464 from the generated initializer: the 2:1 walk steps per direction.
const WALK_STEP_X = [-1, -1, 1, 1]
const WALK_STEP_Y = [1, -1, 1, -1]
const MAX_STEPS = 512

var error: String = ""

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _signed(value: int) -> int:
	return value if value < 32768 else value - 65536

func _failure(message: String) -> Dictionary:
	error = "pal98-walk: " + message
	return {"error": error}

## Starts a walk from the instruction words, or reports that the party is already
## at the target. The returned `pending` dictionary continues the walk.
func begin(state: Dictionary, words: Array, speed: int) -> Dictionary:
	if not state.get("globals") is Dictionary: return _failure("explicit globals required")
	if not _i2(speed) or speed <= 0: return _failure("walk speed outside I2")
	for word in words:
		if typeof(word) != TYPE_INT or word < 0 or word > 65535: return _failure("walk words must be U2")
	var arg0: int = _signed(words[1]); var arg1: int = _signed(words[2]); var arg2: int = _signed(words[3])
	var target_x: int = (arg0 * 2 + arg2) * 16
	var target_y: int = (arg1 * 2 + arg2) * 8
	if not _u2_or_i2(target_x) or not _u2_or_i2(target_y): return _failure("walk target leaves WORD range")
	var pending: Dictionary = {"speed": speed, "target_x": target_x, "target_y": target_y,
		"steps": 0, "words": words.duplicate()}
	# The body copies the world position into the previous-position words before
	# the stepping loop starts.
	state.globals.previous_x = state.globals.get("world_x", 0)
	state.globals.previous_y = state.globals.get("world_y", 0)
	return {"pending": pending, "phase": "check",
		"effect": {"kind": "party_walk_begin", "target_x": target_x, "target_y": target_y, "speed": speed}}

static func _u2_or_i2(value: int) -> bool:
	return value >= -32768 and value <= 65535

## Advances one walk step after the previous requests were answered. Returns
## either more requests with an updated pending state, or a terminal result with
## the applied effects.
func advance(state: Dictionary, pending: Dictionary) -> Dictionary:
	if not state.get("globals") is Dictionary: return _failure("explicit globals required")
	if not pending.get("steps") is int: return _failure("walk pending shape")
	var globals: Dictionary = state.globals
	for key in ["world_x", "world_y", "viewport_x", "viewport_y"]:
		if not _i2(globals.get(key)): return _failure("walk requires the explicit " + key)
	if pending.steps >= MAX_STEPS: return _failure("walk step budget exceeded")
	var at_target: bool = globals.world_x == pending.target_x and globals.world_y == pending.target_y
	var effects: Array = []
	if at_target:
		if pending.get("synced", false):
			return {"done": true, "terminal": true, "effects": effects, "requests": []}
		# Arrival: the original runs the member/trail sync on the reviewed owner.
		pending.synced = true
		return {"pending": pending, "done": true, "effects": effects,
			"requests": [{"kind": "sync_members_from_trail", "original_entry": "0x0041D2E4",
				"procedure": "SyncMembersFromTrail", "walk_steps": pending.steps}]}
	if pending.get("facing", false):
		var direction: int = _signed(globals.get("direction_word", -1))
		if direction < 0 or direction >= WALK_STEP_X.size():
			return _failure("walk facing needs a known direction word")
		# The reviewed body scales X by speed*2 and Y by speed, i.e. a 2:1 step.
		var step_x: int = WALK_STEP_X[direction] * pending.speed * 2
		var step_y: int = WALK_STEP_Y[direction] * pending.speed
		var viewport_x: int = globals.viewport_x + step_x
		var viewport_y: int = globals.viewport_y + step_y
		if not _i2(viewport_x) or not _i2(viewport_y): return _failure("walk viewport step leaves I2 range")
		globals.previous_viewport_x = globals.viewport_x; globals.previous_viewport_y = globals.viewport_y
		globals.viewport_x = viewport_x; globals.viewport_y = viewport_y
		effects.append({"kind": "party_walk_step", "direction": direction, "speed": pending.speed,
			"step_x": step_x, "step_y": step_y, "viewport_x": viewport_x, "viewport_y": viewport_y})
		pending.steps += 1
		pending.facing = false
		return {"pending": pending, "effects": effects, "requests": [
			{"kind": "post_move_update", "original_entry": "0x0041D2CC", "procedure": "PostMoveUpdate"},
			{"kind": "start_frame_and_process_events", "original_entry": "0x0041D17C",
				"procedure": "StartFrameAndProcessEvents", "mode": 0},
			{"kind": "update_viewport_and_party_position", "original_entry": "0x0041CC3C",
				"procedure": "UpdateViewportAndPartyPosition"},
			{"kind": "render_scene_frame", "original_entry": "0x0041CB64",
				"procedure": "RenderSceneFrame", "mode": 1},
		]}
	# The step is recomputed from the current delta every iteration; facing is the
	# external extf stub, so it is always an owner request.
	var delta_x: int = pending.target_x - globals.world_x
	var delta_y: int = pending.target_y - globals.world_y
	pending.facing = true
	return {"pending": pending, "effects": effects, "requests": [
		{"kind": "face_party_toward", "original_entry": "0x004172D8", "procedure": "ExternalExtf",
			"delta_x": delta_x, "delta_y": delta_y},
	]}
