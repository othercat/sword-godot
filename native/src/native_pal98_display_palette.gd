# SPDX-License-Identifier: MIT
extends RefCounted
## The real palette display executor for the EnterScript owner's fade family:
## apply_palette installs the received RGB6 block as the live display palette,
## fade_wait consumes its delay from a bound logical clock, fade_event_pump
## drains a bound input queue and fade_frame advances the bound frame counter.
## A receipt is returned only for work this executor actually did, and every
## install bumps a generation carried on the receipt. Requests outside the
## palette family are refused by name so the EntryHost keeps its forwarding
## rules; this module never acknowledges an install it did not perform.
const LENGTH = 0x300
const MAX_BYTE_OFFSET = 0x900

var error: String = ""
var _installed: PackedByteArray = PackedByteArray()
var _receipts: Array = []
var _generation: int = 0
var _clock = null
var _inputs: Array = []
var _frame: int = 0

func _failure(message: String) -> Dictionary:
	error = "pal98-display-palette: " + message
	return {"error": error}

## The fade delays must come from an explicit logical clock owner, never from
## wall time; a caller without one gets a named refusal at the first wait.
func bind_clock(clock) -> bool:
	if clock == null or not clock.has_method("consume"):
		error = "pal98-display-palette: the logical clock must expose consume(units)"
		return false
	_clock = clock; error = ""; return true

## Explicit input events available to the next fade_event_pump.
func offer_input(event: Dictionary) -> bool:
	if not event is Dictionary:
		error = "pal98-display-palette: input events are dictionaries"; return false
	_inputs.append(event); error = ""; return true

## What the screen would sample right now: the last installed 768-byte RGB6
## block, or an empty array before the first install.
func installed_rgb6() -> PackedByteArray:
	return _installed.duplicate()

func receipts() -> Array:
	return _receipts.duplicate(true)

func install_generation() -> int:
	return _generation

func frame() -> int:
	return _frame

func answer(request: Dictionary) -> Dictionary:
	if not request is Dictionary or not request.get("kind") is String:
		return _failure("owner request shape")
	match request.kind:
		"apply_palette":
			if request.get("procedure") != "intpate":
				return _failure("apply_palette expects the intpate procedure")
			var offset = request.get("offset"); var byte_offset = request.get("byte_offset")
			var length = request.get("length"); var bytes = request.get("bytes")
			if offset is bool or byte_offset is bool or length is bool \
					or not offset is int or not byte_offset is int or not length is int:
				return _failure("install identity fields must be integers")
			if length != LENGTH or not bytes is PackedByteArray or bytes.size() != LENGTH:
				return _failure("intpate installs exactly one 0x300-byte palette block")
			if byte_offset != offset * 2 or byte_offset < 0 or byte_offset > MAX_BYTE_OFFSET:
				return _failure("install WORD offset and byte offset disagree or leave the G0150 backing")
			for channel in bytes:
				if channel > 63:
					return _failure("install block has an RGB6 channel above 63")
			_installed = bytes.duplicate()
			_generation += 1
			var receipt: Dictionary = {"kind": request.kind, "byte_offset": byte_offset,
				"generation": _generation, "first": [bytes[0], bytes[1], bytes[2]],
				"last": [bytes[LENGTH - 3], bytes[LENGTH - 2], bytes[LENGTH - 1]]}
			_receipts.append(receipt)
			return {"completed": true, "install": receipt.duplicate(true)}
		"fade_wait":
			var delay = request.get("delay")
			if delay is bool or not delay is int or delay < 1:
				return _failure("fade_wait requires a positive delay unit count")
			if _clock == null:
				return _failure("no logical clock bound for fade_wait")
			var consumed: Dictionary = _clock.consume(delay)
			if consumed.has("error"): return _failure(str(consumed.error))
			return {"completed": true, "waited": delay, "clock": consumed}
		"fade_event_pump":
			var pumped: Array = _inputs.duplicate(true)
			_inputs.clear()
			return {"completed": true, "pumped": pumped}
		"fade_frame":
			var argument = request.get("argument")
			if argument is bool or not argument is int or argument < 0:
				return _failure("fade_frame requires a nonnegative frame advance")
			_frame += argument
			return {"completed": true, "frame": _frame}
	return _failure("not a display palette request: " + str(request.kind))
