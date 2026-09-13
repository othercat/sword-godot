# SPDX-License-Identifier: MIT
extends RefCounted
## The two-level collision probe behind the exgm1/exgm2 externals: the map
## level tests the blocked bit (0x2000) of the map words at the candidate's
## cell — either the lower or the upper word blocks the tile pair — and the
## event level refuses candidates within abs(dx) + 2*abs(dy) < 16 of any
## active event whose state exceeds 1. The probed cell comes from the same
## world-to-cell conversion the render and occlusion owners share.
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")

var error: String = ""
var _map: PackedByteArray = PackedByteArray()
var _events_state: Dictionary = {}

func _failure(message: String) -> Dictionary:
	error = "pal98-collision-probe: " + message
	return {"error": error}

## map_bytes: the 65536-byte MAP buffer; events_state: the scene-events state
## whose active slots carry the original 32-byte event records.
func bind(map_bytes: PackedByteArray, events_state: Dictionary) -> bool:
	if not map_bytes is PackedByteArray or map_bytes.size() != 65536:
		error = "pal98-collision-probe: the map buffer requires 65536 bytes"; return false
	if not events_state is Dictionary or not events_state.get("active_slots") is Array:
		error = "pal98-collision-probe: the event state requires the active slots"; return false
	_map = map_bytes.duplicate(); _events_state = events_state; error = ""; return true

## The blocked-bit test over both words of the candidate's tile pair.
func map_blocked(candidate_x: int, candidate_y: int) -> Dictionary:
	var cell: Dictionary = Occlusion.world_to_cell(candidate_x, candidate_y)
	if cell.has("error"): return cell
	var half: int = cell.value.half
	var blocked := false
	for subrow in range(2):
		var at: int = (((cell.value.y) * 64 + cell.value.x) * 2 + subrow) * 4 & 65535
		for offset in [at, at + 2]:
			var word: int = _map.decode_u16(offset)
			if word & 0x2000 != 0: blocked = true
	var selected: Dictionary = {"cell": [cell.value.x, cell.value.y, half], "blocked": blocked}
	return {"value": selected}

## The event-level scan: any active event with state > 1 whose position sits
## within abs(dx) + 2*abs(dy) < 16 of the candidate clears the acceptance.
func event_blocked(candidate_x: int, candidate_y: int) -> Dictionary:
	var slots: Array = _events_state.get("active_slots", [])
	for index in range(slots.size()):
		var row = slots[index]
		if not row is PackedByteArray or row.size() != 32: continue
		var state: int = row.decode_s16(12)
		if state <= 1: continue
		var dx: int = absi(row.decode_s16(2) - candidate_x)
		var dy: int = absi(row.decode_s16(4) - candidate_y)
		if dx + 2 * dy < 16:
			return {"value": {"blocked": true, "event_slot": index}}
	return {"value": {"blocked": false}}

## The combined two-level probe in the original's order: map first, then
## events. Either block clears the acceptance.
func probe(candidate_x: int, candidate_y: int) -> Dictionary:
	if candidate_x < -32768 or candidate_x > 32767 or candidate_y < -32768 or candidate_y > 32767:
		return _failure("the probe candidate leaves I2")
	var map: Dictionary = map_blocked(candidate_x, candidate_y)
	if map.has("error"): return map
	if map.value.blocked:
		return {"accepted": false, "reason": "map_blocked", "cell": map.value.cell}
	var events: Dictionary = event_blocked(candidate_x, candidate_y)
	if events.has("error"): return events
	if events.value.blocked:
		return {"accepted": false, "reason": "event_proximity", "event_slot": events.value.event_slot}
	return {"accepted": true, "cell": map.value.cell}
