# SPDX-License-Identifier: MIT
extends RefCounted
## Palette requests install into a bound indexed pixel surface. Waits, event
## pumps and frames require explicit execution owners. Software pixel updates
## and test clocks do not establish a rendered window or an ordinary Session.
const LENGTH = 0x300
const MAX_BYTE_OFFSET = 0x900

var error: String = ""
var _installed: PackedByteArray = PackedByteArray()
var _receipts: Array = []
var _generation: int = 0
var _clock = null
var _inputs: Array = []
var _frame: int = 0
var _surface = null
var _runtime = null

func bind_surface(surface) -> bool:
	if surface == null or not surface.has_method("install_palette"):
		error = "pal98-display-palette: indexed pixel surface required"; return false
	_surface = surface; error = ""; return true

func bind_runtime(owner) -> bool:
	if owner == null or not owner.has_method("answer"):
		error = "pal98-display-palette: frame/event execution owner required"; return false
	_runtime = owner; error = ""; return true

func _install_surface(bytes: PackedByteArray) -> Dictionary:
	if _surface == null: return _failure("no indexed pixel surface bound for palette install")
	var applied: Dictionary = _surface.install_palette(bytes)
	if applied.has("error"): return _failure(str(applied.error))
	if applied.get("completed") != true: return _failure("pixel surface did not complete palette install")
	return applied

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

## Cold start: install the admitted day palette before any fade runs, with the
## same receipt discipline as a fade install.
func install_cold(rgb6: PackedByteArray) -> Dictionary:
	if not rgb6 is PackedByteArray or rgb6.size() != LENGTH:
		return _failure("the cold display palette requires exactly 0x300 RGB6 bytes")
	for channel in rgb6:
		if channel > 63:
			return _failure("the cold display palette has an RGB6 channel above 63")
	var applied = _install_surface(rgb6)
	if applied.has("error"): return applied
	_installed = rgb6.duplicate()
	_generation += 1
	var receipt: Dictionary = {"kind": "cold_load", "byte_offset": 0, "generation": _generation}
	_receipts.append(receipt)
	return {"completed": true, "install": receipt.duplicate(true), "surface": applied}

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
			var applied = _install_surface(bytes)
			if applied.has("error"): return applied
			_installed = bytes.duplicate()
			_generation += 1
			var receipt: Dictionary = {"kind": request.kind, "byte_offset": byte_offset,
				"generation": _generation, "first": [bytes[0], bytes[1], bytes[2]],
				"last": [bytes[LENGTH - 3], bytes[LENGTH - 2], bytes[LENGTH - 1]]}
			_receipts.append(receipt)
			return {"completed": true, "install": receipt.duplicate(true), "surface": applied}
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
			if _runtime == null: return _failure("no event execution owner bound")
			var forwarded = request.duplicate(true); forwarded.events = _inputs.duplicate(true)
			var result: Dictionary = _runtime.answer(forwarded)
			if result.has("error"): return _failure(str(result.error))
			if result.get("completed") != true: return _failure("event owner did not complete")
			_inputs.clear()
			return result
		"fade_frame":
			var argument = request.get("argument")
			if argument is bool or not argument is int or argument < 0:
				return _failure("fade_frame requires a nonnegative frame advance")
			if _runtime == null: return _failure("no frame execution owner bound")
			var result: Dictionary = _runtime.answer(request.duplicate(true))
			if result.has("error"): return _failure(str(result.error))
			if result.get("completed") != true or typeof(result.get("frame")) != TYPE_INT or result.frame < 0:
				return _failure("frame owner did not return completed frame identity")
			_frame = result.frame
			return result
	return _failure("not a display palette request: " + str(request.kind))
