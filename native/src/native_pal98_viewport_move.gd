# SPDX-License-Identifier: MIT
extends RefCounted
## ExecuteScriptCommand 0x007F: the viewport/member move state machine.
##
## Decoded from 0x00425A7C..0x00425D24 (PAL.EXE 75d612b9…c450):
## - the restore form `(A0,A1,A2) = (0,0,-1)` puts the party anchor back at
##   `(160,112)`, recomputes the viewport as `world - anchor` and runs the round
##   loop zero times without calling a host (0x00425AA8..0x00425AEA);
## - otherwise the round limit is `A2` (0x00425AEE stores +0x20 in the loop
##   limit): a nonpositive `A2` defaults to one round, the same relation the
##   0x001A selector uses at 0x00421718;
## - each round saves the viewport in the `G0330/G0332` copies, then picks the
##   mode from the three arguments: `(A0 | A1 | A2) = 0` re-anchors and writes
##   `A2 = -1` back (0x00425B5C..0x00425BA6), `A2 < 0` sets the absolute
##   viewport `(A0*32-160, A1*16-112)` (0x00425BB6..0x00425BE2) and a nonnegative
##   `A2` advances the viewport by `(A0,A1)` (0x00425BEC). The round recomputes
##   the anchor as `world - viewport`, writes the leader record and shifts
##   members 1..member_last by the anchor delta (0x00425C38..0x00425CE2), then
##   requests StartFrameAndProcessEvents(0), the update only for `A2 >= 0`, and
##   RenderSceneFrame(1) (0x00425CEE..0x00425D0C).
##
## VB40032 token 0034 is bitwise OR; 0096 is signed >=. A background request
## suspends the command before the dependent anchor/member work. Frame requests
## likewise finish before the next round reads the host's written-back state.
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

## Validates the instruction and computes the round plan without touching state.
func begin(words: Array) -> Dictionary:
	if words.size() != 4: return _failure("four instruction words required")
	for word in words:
		if typeof(word) != TYPE_INT or word < 0 or word > 65535: return _failure("arguments must be U2")
	var arg0: int = _signed(words[1]); var arg1: int = _signed(words[2]); var arg2: int = _signed(words[3])
	var restore: bool = arg2 == -1 and arg0 == 0 and arg1 == 0
	var rounds: int = 0
	if not restore: rounds = 1 if arg2 <= 0 else arg2
	# MAX_ROUNDS is a Native guard, not an original byte.
	if rounds > MAX_ROUNDS: return _failure("viewport move round count outside the owned budget")
	return {"restore": restore, "rounds": rounds, "next": 1, "phase": "round",
		"arg0": arg0, "arg1": arg1, "arg2": arg2}

## Advances to the next host boundary. Only a valid step updates the caller's
## state and plan; rejected arithmetic/backing never publishes a partial step.
func advance(state: Dictionary, pending: Dictionary) -> Dictionary:
	if pending.get("terminal", false): return {"terminal": true}
	if not state.get("globals") is Dictionary: return _failure("explicit globals required")
	if not state.get("party_records") is Array: return _failure("explicit party records required")
	var candidate: Dictionary = {"globals": state.globals.duplicate(true),
		"party_records": state.party_records.duplicate(true)}
	var next_pending: Dictionary = pending.duplicate(true)
	var result: Dictionary = _advance(candidate, next_pending)
	if result.has("error"): return result
	state.globals.merge(candidate.globals, true)
	state.party_records.assign(candidate.party_records)
	pending.merge(next_pending, true)
	result.pending = pending
	return result

func _restore_anchor(globals: Dictionary) -> Dictionary:
	var x: int = globals.world_x - DEFAULT_ANCHOR_X
	var y: int = globals.world_y - DEFAULT_ANCHOR_Y
	if not _i2(x) or not _i2(y): return _failure("restored viewport leaves I2 range")
	globals.party_x = DEFAULT_ANCHOR_X; globals.party_y = DEFAULT_ANCHOR_Y
	globals.viewport_x = x; globals.viewport_y = y
	return {}

func _background_request() -> Dictionary:
	return {"kind": "render_current_map_background", "original_entry": "0x0041CB34",
		"procedure": "RenderCurrentMapBackground"}

func _advance(state: Dictionary, pending: Dictionary) -> Dictionary:
	var globals: Dictionary = state.globals
	for key in ["world_x", "world_y", "viewport_x", "viewport_y", "party_x", "party_y", "member_last"]:
		if not _i2(globals.get(key)): return _failure("viewport move requires the explicit " + key)
	var effects: Array = []
	var requests: Array = []
	if pending.restore:
		var restored: Dictionary = _restore_anchor(globals)
		if restored.has("error"): return restored
		pending.restore = false
		effects.append({"kind": "viewport_restore", "viewport_x": globals.viewport_x,
			"viewport_y": globals.viewport_y})
		pending.terminal = true
		return {"effects": effects, "requests": requests, "pending": pending, "terminal": true}
	if pending.phase == "round":
		globals.previous_viewport_x = globals.viewport_x
		globals.previous_viewport_y = globals.viewport_y
		pending.saved_anchor_x = globals.party_x; pending.saved_anchor_y = globals.party_y
		pending.mode = "delta"
		if (int(pending.arg0) | int(pending.arg1) | int(pending.arg2)) == 0:
			var restored: Dictionary = _restore_anchor(globals)
			if restored.has("error"): return restored
			pending.mode = "reanchor"
			pending.phase = "background"
			return {"effects": [], "requests": [_background_request()]}
		elif pending.arg2 < 0:
			var tile_x: int = pending.arg0 * 32; var tile_y: int = pending.arg1 * 16
			if not _i2(tile_x) or not _i2(tile_y): return _failure("absolute viewport multiply leaves I2 range")
			var viewport_x: int = tile_x - DEFAULT_ANCHOR_X
			var viewport_y: int = tile_y - DEFAULT_ANCHOR_Y
			if not _i2(viewport_x) or not _i2(viewport_y): return _failure("absolute viewport leaves I2 range")
			globals.viewport_x = viewport_x; globals.viewport_y = viewport_y
			pending.mode = "absolute"
			pending.phase = "background"
			return {"effects": [], "requests": [_background_request()]}
		else:
			var moved_x: int = globals.viewport_x + pending.arg0
			var moved_y: int = globals.viewport_y + pending.arg1
			if not _i2(moved_x) or not _i2(moved_y): return _failure("viewport delta leaves I2 range")
			globals.viewport_x = moved_x; globals.viewport_y = moved_y
	elif pending.phase == "background":
		# Re-anchor resumes at 0x425B9E and skips the world-minus-viewport
		# recomputation; absolute resumes at 0x425BE8 and performs it.
		if pending.mode == "reanchor": pending.arg2 = -1
	else:
		return _failure("unknown viewport continuation phase")
	if pending.mode != "reanchor":
		var x: int = globals.world_x - globals.viewport_x
		var y: int = globals.world_y - globals.viewport_y
		if not _i2(x) or not _i2(y): return _failure("anchor recompute leaves I2 range")
		globals.party_x = x; globals.party_y = y
	var anchor_x: int = globals.party_x; var anchor_y: int = globals.party_y
	if globals.member_last < 0 or globals.member_last >= state.party_records.size():
		return _failure("member count exceeds the explicit party records")
	var leader: Dictionary = _member(state, 0)
	if leader.is_empty(): return _failure("party record 0 shape")
	leader.screen_x = anchor_x; leader.screen_y = anchor_y
	var shifted: int = 0
	for slot in range(1, int(globals.member_last) + 1):
		var member: Dictionary = _member(state, slot)
		if member.is_empty(): return _failure("member record shape at slot " + str(slot))
		if not _i2(member.get("screen_x")) or not _i2(member.get("screen_y")):
			return _failure("member screen position missing")
		var dx: int = anchor_x - int(pending.saved_anchor_x)
		var dy: int = anchor_y - int(pending.saved_anchor_y)
		if not _i2(dx) or not _i2(dy): return _failure("member anchor delta leaves I2 range")
		var x: int = member.screen_x + dx; var y: int = member.screen_y + dy
		if not _i2(x) or not _i2(y): return _failure("member screen position leaves I2 range")
		member.screen_x = x; member.screen_y = y
		shifted += 1
	effects.append({"kind": "viewport_move", "mode": pending.mode, "round": pending.next,
		"viewport_x": globals.viewport_x, "viewport_y": globals.viewport_y,
		"anchor_x": anchor_x, "anchor_y": anchor_y, "members_shifted": shifted})
	requests.append({"kind": "start_frame_and_process_events", "original_entry": "0x0041D17C",
		"procedure": "StartFrameAndProcessEvents", "mode": 0})
	if pending.arg2 >= 0:
		requests.append({"kind": "update_viewport_and_party_position", "original_entry": "0x0041CC3C",
			"procedure": "UpdateViewportAndPartyPosition"})
	requests.append({"kind": "render_scene_frame", "original_entry": "0x0041CB64",
		"procedure": "RenderSceneFrame", "mode": 1})
	pending.next += 1
	pending.phase = "round"
	if pending.next > int(pending.rounds): pending.terminal = true
	return {"effects": effects, "requests": requests, "pending": pending,
		"terminal": pending.get("terminal", false)}
