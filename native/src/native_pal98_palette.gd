# SPDX-License-Identifier: MIT
extends RefCounted
## G0150 palette buffer arithmetic for the 0x0080 day/night toggle, recovered
## from the PALOLD exports behind the case's thunks: copymen (import slot 58,
## thunk 0x00417604), cvpate (slot 45, thunk 0x00417498) and intpate (slot 47,
## thunk 0x004174D0). The buffer is explicit byte state: the day block sits at
## [0,0x180), the night block at [0x180,0x300), the fade work area at
## [0x300,0x600) and the constructed color target at [0x480,0x780); the
## G026C day/night offset slides the active 0x300-byte window between the day
## and night blocks.
const BLOCK = 0x180
const DAY_NIGHT_MAX = 0x180
const WORK = 0x300
const TARGET = 0x480
const LENGTH = 0x300
const BUFFER = 0x780
const ROUNDS = 32

var error: String = ""

func _failure(message: String) -> Dictionary:
	error = "pal98-palette: " + message
	return {"error": error}

func _shape_issue(palette_bytes) -> String:
	if not palette_bytes is PackedByteArray or palette_bytes.size() != BUFFER:
		return "palette requires the explicit 0x780-byte G0150 buffer"
	return ""

## copymen(dst=&buf[WORK], src=&buf[day_night], 0x300): a forward byte copy
## that saves the active palette window into the work area.
func save_current(palette_bytes: PackedByteArray, day_night: int) -> void:
	for index in range(LENGTH):
		palette_bytes[WORK + index] = palette_bytes[day_night + index]

## cvpate(current=&buf[WORK], target=&buf[target_offset]): each of the 0x300
## work bytes moves toward its target byte by +2 when below or -1 when above,
## with 8-bit wraparound exactly like the native body; a rising byte may pass
## its target by one and settles on the following round. Returns how many
## bytes moved this round.
func converge_once(palette_bytes: PackedByteArray, target_offset: int) -> Dictionary:
	if target_offset < 0 or target_offset + LENGTH > palette_bytes.size():
		return _failure("target block outside the palette buffer")
	var moved: int = 0
	for index in range(LENGTH):
		var current: int = palette_bytes[WORK + index]
		var target: int = palette_bytes[target_offset + index]
		if current < target:
			current = (current + 2) & 0xFF
			moved += 1
		elif current > target:
			current = (current - 1) & 0xFF
			moved += 1
		palette_bytes[WORK + index] = current
	return {"moved": moved}
