# SPDX-License-Identifier: MIT
extends RefCounted
## The two-level collision probe behind the exgm1/exgm2 externals: the map
## level tests bit 0x2000 of the selected half-cell's LOWER descriptor. The
## upper descriptor and the other half are not collision inputs. The
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
	var slots = events_state.get("active_slots"); var count = events_state.get("event_count")
	if not slots is Array or slots.size() != 160 or typeof(count) != TYPE_INT or count < 0 or count > 160:
		error = "pal98-collision-probe: requires 160 event slots and an explicit current count"; return false
	for index in range(count):
		if not slots[index] is PackedByteArray or slots[index].size() != 32:
			error = "pal98-collision-probe: unknown or malformed current event %d" % (index + 1); return false
	_map = map_bytes.duplicate(); _events_state = events_state.duplicate(true); error = ""; return true

## exgm1 swaps the row bytes, adds column*4 and half*2, then doubles AX.
## This addresses one lower WORD at (row*512 + column*8 + half*4) & 65535.
func map_blocked(candidate_x: int, candidate_y: int) -> Dictionary:
	if _map.size() != 65536: return _failure("map/event source not bound")
	var cell: Dictionary = Occlusion.world_to_cell(candidate_x, candidate_y)
	if cell.has("error"): return cell
	var half: int = cell.value.half
	var at: int = (cell.value.y * 512 + cell.value.x * 8 + half * 4) & 65535
	var blocked: bool = (_map.decode_u16(at) & 0x2000) != 0
	var selected: Dictionary = {"cell": [cell.value.x, cell.value.y, half], "blocked": blocked, "map_byte_offset": at}
	return {"value": selected}

## The event-level scan: any active event with state > 1 whose position sits
## within abs(dx) + 2*abs(dy) < 16 of the candidate clears the acceptance.
static func _signed(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

func event_blocked(candidate_x: int, candidate_y: int, excluded_event_id: int = 0) -> Dictionary:
	if _events_state.is_empty(): return _failure("map/event source not bound")
	if candidate_x < -32768 or candidate_x > 32767 or candidate_y < -32768 or candidate_y > 32767:
		return _failure("event candidate requires signed coordinates")
	if excluded_event_id < -32768 or excluded_event_id > 65535: return _failure("excluded event id requires a WORD")
	var slots: Array = _events_state.get("active_slots", [])
	for index in range(_events_state.event_count):
		if index + 1 == (excluded_event_id & 65535): continue
		var row = slots[index]
		var state: int = row.decode_s16(12)
		if state <= 1: continue
		# The native external uses wrapping 16-bit SUB/ABS/ADD, then signed JGE.
		# In particular abs(-32768) remains 0x8000; do not replace with I4 distance.
		var dx: int = absi(_signed(row.decode_s16(2) - candidate_x)) & 65535
		var dy: int = absi(_signed(row.decode_s16(4) - candidate_y)) & 65535
		if _signed(dx + 2 * dy) < 16:
			return {"value": {"blocked": true, "event_slot": index, "event_id": index + 1}}
	return {"value": {"blocked": false}}

## The combined two-level probe in the original's order: map first, then
## events. Either block clears the acceptance.
func probe(candidate_x: int, candidate_y: int, excluded_event_id: int = 0) -> Dictionary:
	if candidate_x < -32768 or candidate_x > 32767 or candidate_y < -32768 or candidate_y > 32767:
		return _failure("the probe candidate leaves I2")
	var map: Dictionary = map_blocked(candidate_x, candidate_y)
	if map.has("error"): return map
	if map.value.blocked:
		return {"accepted": false, "reason": "map_blocked", "cell": map.value.cell}
	var events: Dictionary = event_blocked(candidate_x, candidate_y, excluded_event_id)
	if events.has("error"): return events
	if events.value.blocked:
		return {"accepted": false, "reason": "event_proximity", "event_slot": events.value.event_slot}
	return {"accepted": true, "cell": map.value.cell}
