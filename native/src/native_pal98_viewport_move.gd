# SPDX-License-Identifier: MIT
extends RefCounted
## ExecuteScriptCommand 0x007F: the viewport/member move state machine.
##
## Decoded from 0x00425A7C..0x00425D24 (PAL.EXE 75d612b9…c450):
## - the restore form `(A0,A1,A2) = (0,0,-1)` puts the party anchor back at
##   `(160,112)`, recomputes the viewport as `world - anchor`, renders and runs
##   the round loop zero times (0x00425AA8..0x00425AEA);
## - otherwise the round limit is `A2` (0x00425AEE stores +0x20 in the loop
##   limit): a nonpositive `A2` defaults to one round, the same relation the
##   0x001A selector uses at 0x00421718;
## - each round saves the viewport in the `G0330/G0332` copies, then picks the
##   mode from the live `A2`: `A2 = 0` re-anchors at `(160,112)` and writes
##   `A2 = -1` back (0x00425B5C..0x00425BA6), `A2 < 0` sets the absolute
##   viewport `(A0*32-160, A1*16-112)` (0x00425BB6..0x00425BE2) and a positive
##   `A2` advances the viewport by `(A0,A1)` (0x00425BEC). The round recomputes
##   the anchor as `world - viewport`, writes the leader record and shifts
##   members 1..member_last by the anchor delta (0x00425C38..0x00425CE2), then
##   requests StartFrameAndProcessEvents(0), the viewport/party update and
##   RenderSceneFrame(1) (0x00425CEE..0x00425D0C).
##
## The original evaluates a dead `A0 <op> A1` before the mode branch and never
## consumes it, so the mode choice depends on `A2` alone. One round runs per
## `advance`: the host answers each round's requests before the next round reads
## the written-back state, because the frame events inside the loop may mutate it.
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
	return {"restore": restore, "rounds": rounds, "next": 1,
		"arg0": arg0, "arg1": arg1, "arg2": arg2}

## Runs one round (or the one-shot restore) against the current state and returns
## that round's effects and requests. `pending` is the plan from `begin`, mutated
## in place; `terminal` marks the machine as finished.
func advance(state: Dictionary, pending: Dictionary) -> Dictionary:
	if pending.get("terminal", false): return {"terminal": true}
	if not state.get("globals") is Dictionary: return _failure("explicit globals required")
	if not state.get("party_records") is Array: return _failure("explicit party records required")
	var globals: Dictionary = state.globals
	for key in ["world_x", "world_y", "viewport_x", "viewport_y", "party_x", "party_y", "member_last"]:
		if not _i2(globals.get(key)): return _failure("viewport move requires the explicit " + key)
	var effects: Array = []
	var requests: Array = []
	if pending.restore:
		pending.restore = false
		globals.party_x = DEFAULT_ANCHOR_X; globals.party_y = DEFAULT_ANCHOR_Y
		globals.viewport_x = globals.world_x - DEFAULT_ANCHOR_X
		globals.viewport_y = globals.world_y - DEFAULT_ANCHOR_Y
		requests.append({"kind": "render_current_map_background", "original_entry": "0x0041CB34",
			"procedure": "RenderCurrentMapBackground"})
		effects.append({"kind": "viewport_restore", "viewport_x": globals.viewport_x,
			"viewport_y": globals.viewport_y})
		pending.terminal = true
		return {"effects": effects, "requests": requests, "pending": pending, "terminal": true}
	globals.previous_viewport_x = globals.viewport_x
	globals.previous_viewport_y = globals.viewport_y
	var saved_anchor_x: int = globals.party_x; var saved_anchor_y: int = globals.party_y
	var mode: String = "delta"
	if pending.arg2 == 0:
		mode = "reanchor"
		globals.party_x = DEFAULT_ANCHOR_X; globals.party_y = DEFAULT_ANCHOR_Y
		globals.viewport_x = globals.world_x - DEFAULT_ANCHOR_X
		globals.viewport_y = globals.world_y - DEFAULT_ANCHOR_Y
		requests.append({"kind": "render_current_map_background", "original_entry": "0x0041CB34",
			"procedure": "RenderCurrentMapBackground"})
		pending.arg2 = -1
	elif pending.arg2 < 0:
		mode = "absolute"
		var viewport_x: int = pending.arg0 * 32 - DEFAULT_ANCHOR_X
		var viewport_y: int = pending.arg1 * 16 - DEFAULT_ANCHOR_Y
		if not _i2(viewport_x) or not _i2(viewport_y): return _failure("absolute viewport leaves I2 range")
		globals.viewport_x = viewport_x; globals.viewport_y = viewport_y
		requests.append({"kind": "render_current_map_background", "original_entry": "0x0041CB34",
			"procedure": "RenderCurrentMapBackground"})
	else:
		var moved_x: int = globals.viewport_x + pending.arg0
		var moved_y: int = globals.viewport_y + pending.arg1
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
	for slot in range(1, mini(int(globals.member_last), state.party_records.size() - 1) + 1):
		var member: Dictionary = _member(state, slot)
		if member.is_empty(): continue
		if not member.get("screen_x") is int or not member.get("screen_y") is int:
			return _failure("member screen position missing")
		member.screen_x = member.screen_x - saved_anchor_x + anchor_x
		member.screen_y = member.screen_y - saved_anchor_y + anchor_y
		shifted += 1
	effects.append({"kind": "viewport_move", "mode": mode, "round": pending.next,
		"viewport_x": globals.viewport_x, "viewport_y": globals.viewport_y,
		"anchor_x": anchor_x, "anchor_y": anchor_y, "members_shifted": shifted})
	requests.append({"kind": "start_frame_and_process_events", "original_entry": "0x0041D17C",
		"procedure": "StartFrameAndProcessEvents", "mode": 0})
	if pending.arg2 != 0:
		requests.append({"kind": "update_viewport_and_party_position", "original_entry": "0x0041CC3C",
			"procedure": "UpdateViewportAndPartyPosition"})
	requests.append({"kind": "render_scene_frame", "original_entry": "0x0041CB64",
		"procedure": "RenderSceneFrame", "mode": 1})
	pending.next += 1
	if pending.next > int(pending.rounds): pending.terminal = true
	return {"effects": effects, "requests": requests, "pending": pending,
		"terminal": pending.get("terminal", false)}
