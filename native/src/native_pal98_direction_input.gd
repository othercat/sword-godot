# SPDX-License-Identifier: MIT
extends RefCounted
## The recovered PollAndResolveDirection (0x0041CCE4, T-recovered): per-frame
## input-direction resolution over eight logical key slots. Each slot reads a
## key level of 2 (newly pressed this frame) or 3 (held); slots 0/4 pull up
## (negative Y), 1/5 down, 2/6 left, 3/7 right. A new press weighs 2 against a
## held 1, new presses override in the right > left > down > up order, and an
## axis resolves alone only while the other axis has no pressed key. The
## result is at most one nonzero axis component, consumed by the isometric
## conversion on the movement path.
var error: String = ""

func _failure(message: String) -> Dictionary:
	error = "pal98-direction-input: " + message
	return {"error": error}

## key_levels: eight key states indexed through logical_map (values 0..3);
## logical_map: the G0854 slot-to-key map (at least 8 entries).
func resolve(key_levels, logical_map: Array) -> Dictionary:
	if not key_levels is Array and not key_levels is PackedInt32Array:
		return _failure("key levels require an array")
	if key_levels.size() < 8:
		return _failure("key levels require the eight-entry state table")
	if logical_map.size() < 8:
		return _failure("the logical key map requires eight slots")
	for slot in range(8):
		var mapped = logical_map[slot]
		if mapped is bool or not mapped is int or mapped < 0 or mapped >= key_levels.size():
			return _failure("logical key slot %d leaves the state table" % slot)
	var level := func(slot: int) -> int:
		var value = key_levels[logical_map[slot]]
		if value is bool or not value is int: return 0
		return value
	var negative_y := 0; var positive_y := 0
	var negative_x := 0; var positive_x := 0
	var direction_x := 0; var direction_y := 0
	for state in range(2, 4):
		var weight: int = 4 - state
		if level.call(0) == state or level.call(4) == state: negative_y = weight
		if level.call(1) == state or level.call(5) == state: positive_y = weight
		if level.call(2) == state or level.call(6) == state: negative_x = weight
		if level.call(3) == state or level.call(7) == state: positive_x = weight
	if negative_y + positive_y == 0:
		direction_y = 0
		if negative_x > positive_x: direction_x = -1
		if negative_x < positive_x: direction_x = 1
	if negative_x + positive_x == 0:
		direction_x = 0
		if negative_y > positive_y: direction_y = -1
		if negative_y < positive_y: direction_y = 1
	# A new press (weight 2) overrides in the fixed right > left > down > up
	# order; the trailing guards drop directions whose weight was zero.
	if negative_y == 2: direction_y = -1; direction_x = 0
	if positive_y == 2: direction_y = 1; direction_x = 0
	if negative_x == 2: direction_x = -1; direction_y = 0
	if positive_x == 2: direction_x = 1; direction_y = 0
	if positive_x == 0 and direction_x == 1: direction_x = 0
	if negative_x == 0 and direction_x == -1: direction_x = 0
	if positive_y == 0 and direction_y == 1: direction_y = 0
	if negative_y == 0 and direction_y == -1: direction_y = 0
	return {"direction_x": direction_x, "direction_y": direction_y}

const MOVE_STEP_X = 16
const MOVE_STEP_Y = 8

## The SubMain inline (0x0041B1BA..0x0041B1EA): a cartesian screen direction
## becomes the isometric diagonal pair, so the input walk moves along the
## map's tile diagonals.
func convert_to_isometric(direction_x: int, direction_y: int) -> Dictionary:
	if direction_x == 0: direction_x = -direction_y
	if direction_y == 0: direction_y = direction_x
	return {"direction_x": direction_x, "direction_y": direction_y}

## The SubMain inline ProbeAndPrepareMove (0x0041B1F0..0x0041B27A): build the
## step candidate from the party-in-viewport and viewport words, run the
## two-level collision probe (the exgm1/exgm2 externals stay injected), and
## accept it as a one-step movement with the 16/8 isometric deltas.
func probe_and_prepare(party_pos: Dictionary, viewport: Dictionary, direction_x: int,
		direction_y: int, probe) -> Dictionary:
	if direction_x == 0: return {"pending_steps": 0}
	var pos_x = party_pos.get("x"); var pos_y = party_pos.get("y")
	var vp_x = viewport.get("x"); var vp_y = viewport.get("y")
	if not pos_x is int or not pos_y is int or not vp_x is int or not vp_y is int:
		return _failure("probe and prepare requires the explicit party and viewport words")
	var candidate_y: int = ((pos_y + vp_y + 32768) & 0xFFFF) - 32768 + direction_y * MOVE_STEP_Y
	var candidate_x: int = ((pos_x + vp_x + 32768) & 0xFFFF) - 32768 + direction_x * MOVE_STEP_X
	if candidate_y < -32768 or candidate_y > 32767 or candidate_x < -32768 or candidate_x > 32767:
		return _failure("move candidate leaves I2")
	if probe == null or not probe.has_method("probe"):
		return _failure("the collision probe owner is required")
	var accepted: Dictionary = probe.probe(candidate_x, candidate_y)
	if accepted.has("error"): return accepted
	if not accepted.get("accepted", false):
		return {"pending_steps": 0}
	return {"pending_steps": 1, "delta_x": direction_x * MOVE_STEP_X,
		"delta_y": direction_y * MOVE_STEP_Y}
