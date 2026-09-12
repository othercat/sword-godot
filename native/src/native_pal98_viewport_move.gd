# SPDX-License-Identifier: MIT
extends RefCounted
## ExecuteScriptCommand 0x007F: the viewport/member move state machine.
##
## Decoded from 0x00425A7C..0x00425D24:
## - the restore form `(A0,A1,A2) = (-1,0,0)` puts the party anchor back at
##   `(160,112)`, recomputes the viewport as `world - anchor` and renders;
## - otherwise `A0` (default 1) repeats the round; each round saves the current
##   viewport in the `G0330/G0332` copies, applies one of three modes, then
##   recomputes the anchor as `world - viewport` and shifts every member record
##   by the anchor delta before the frame, the optional viewport/party update and
##   the scene render.
##
## The three modes are the re-anchor form (`A0,A1` nonzero with `A2 = 0`, which
## also clears `A2` to -1), the absolute form (`A2 < 0`: the viewport becomes
## `(A0*32-160, A1*16-112)`) and the delta form (the viewport advances by the two
## arguments). Frames and renders stay explicit owner requests.
const DEFAULT_ANCHOR_X = 160
const DEFAULT_ANCHOR_Y = 112
const MAX_ROUNDS = 512

var error: String = ""

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _signed(value: int) -> int:
	return value if value < 32768 else value - 65536

func _failure(message: String) -> Dictionary:
	error = "pal98-viewport: " + message
	return {"error": error}

func _member(state: Dictionary, slot: int) -> Dictionary:
	var records = state.get("party_records")
	if not records is Array or slot >= records.size(): return {}
	var record = records[slot]
	return record if record is Dictionary else {}

## Runs the whole case. `party_x/party_y` are the anchor words, `party_records`
## the fixed member projection and the viewport/world words live in `globals`.
func run(state: Dictionary, words: Array) -> Dictionary:
	if not state.get("globals") is Dictionary: return _failure("explicit globals required")
	if not state.get("party_records") is Array: return _failure("explicit party records required")
	if words.size() != 4: return _failure("four instruction words required")
	for word in words:
		if typeof(word) != TYPE_INT or word < 0 or word > 65535: return _failure("arguments must be U2")
	var globals: Dictionary = state.globals
	for key in ["world_x", "world_y", "viewport_x", "viewport_y", "party_x", "party_y"]:
		if not _i2(globals.get(key)): return _failure("viewport move requires the explicit " + key)
	var arg0: int = _signed(words[1]); var arg1: int = _signed(words[2]); var arg2: int = _signed(words[3])
	var effects: Array = []
	var requests: Array = []
	var restore: bool = arg0 == -1 and arg1 == 0 and arg2 == 0
	# The decoded body defaults a zero count to one and lets VB's For run zero
	# times for a negative count.
	var rounds: int = 0
	if not restore:
		rounds = 1 if arg0 == 0 else maxi(arg0, 0)
	if rounds < 0 or rounds > MAX_ROUNDS: return _failure("viewport move round count outside the owned budget")
	if restore:
		globals.party_x = DEFAULT_ANCHOR_X; globals.party_y = DEFAULT_ANCHOR_Y
		globals.viewport_x = globals.world_x - DEFAULT_ANCHOR_X
		globals.viewport_y = globals.world_y - DEFAULT_ANCHOR_Y
		requests.append({"kind": "render_current_map_background", "original_entry": "0x0041CB34",
			"procedure": "RenderCurrentMapBackground"})
		effects.append({"kind": "viewport_restore", "viewport_x": globals.viewport_x,
			"viewport_y": globals.viewport_y})
	for round_index in range(rounds):
		globals.previous_viewport_x = globals.viewport_x
		globals.previous_viewport_y = globals.viewport_y
		var saved_anchor_x: int = globals.party_x; var saved_anchor_y: int = globals.party_y
		var mode: String = "delta"
		if arg0 != 0 and arg1 != 0 and arg2 == 0:
			mode = "reanchor"
			globals.party_x = DEFAULT_ANCHOR_X; globals.party_y = DEFAULT_ANCHOR_Y
			globals.viewport_x = globals.world_x - DEFAULT_ANCHOR_X
			globals.viewport_y = globals.world_y - DEFAULT_ANCHOR_Y
			requests.append({"kind": "render_current_map_background", "original_entry": "0x0041CB34",
				"procedure": "RenderCurrentMapBackground"})
			arg2 = -1
		elif arg2 < 0:
			mode = "absolute"
			var viewport_x: int = arg0 * 32 - DEFAULT_ANCHOR_X
			var viewport_y: int = arg1 * 16 - DEFAULT_ANCHOR_Y
			if not _i2(viewport_x) or not _i2(viewport_y): return _failure("absolute viewport leaves I2 range")
			globals.viewport_x = viewport_x; globals.viewport_y = viewport_y
			requests.append({"kind": "render_current_map_background", "original_entry": "0x0041CB34",
				"procedure": "RenderCurrentMapBackground"})
		else:
			var moved_x: int = globals.viewport_x + arg0
			var moved_y: int = globals.viewport_y + arg1
			if not _i2(moved_x) or not _i2(moved_y): return _failure("viewport delta leaves I2 range")
			globals.viewport_x = moved_x; globals.viewport_y = moved_y
		var anchor_x: int = globals.world_x - globals.viewport_x
		var anchor_y: int = globals.world_y - globals.viewport_y
		if not _i2(anchor_x) or not _i2(anchor_y): return _failure("anchor recompute leaves I2 range")
		globals.party_x = anchor_x; globals.party_y = anchor_y
		var leader: Dictionary = _member(state, 0)
		if leader.is_empty(): return _failure("party record 0 shape")
		leader.screen_x = anchor_x; leader.screen_y = anchor_y
		var shifted: int = 0
		for slot in range(1, state.party_records.size()):
			var member: Dictionary = _member(state, slot)
			if member.is_empty(): continue
			if not member.get("screen_x") is int or not member.get("screen_y") is int:
				return _failure("member screen position missing")
			member.screen_x = member.screen_x - saved_anchor_x + anchor_x
			member.screen_y = member.screen_y - saved_anchor_y + anchor_y
			shifted += 1
		effects.append({"kind": "viewport_move", "mode": mode, "round": round_index + 1,
			"viewport_x": globals.viewport_x, "viewport_y": globals.viewport_y,
			"anchor_x": anchor_x, "anchor_y": anchor_y, "members_shifted": shifted})
		requests.append({"kind": "start_frame_and_process_events", "original_entry": "0x0041D17C",
			"procedure": "StartFrameAndProcessEvents", "mode": 0})
		if arg2 != 0:
			requests.append({"kind": "update_viewport_and_party_position", "original_entry": "0x0041CC3C",
				"procedure": "UpdateViewportAndPartyPosition"})
		requests.append({"kind": "render_scene_frame", "original_entry": "0x0041CB64",
			"procedure": "RenderSceneFrame", "mode": 1})
	return {"effects": effects, "requests": requests, "rounds": rounds, "restore": restore}
