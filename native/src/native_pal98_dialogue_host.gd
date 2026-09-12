# SPDX-License-Identifier: MIT
extends RefCounted
## Answers the T258 dialogue caller's host requests with explicit policies and
## real text decoding: draw/capture/restore requests are recorded, `poll_input`
## follows a declared input policy and `wait` advances an explicit tick counter.
##
## It renders nothing, polls no device and reads no wall clock, so the caller
## stays responsible for pixels, physical input and timing. Every receipt keeps
## the decoded text next to the source byte receipt it came from.
const Codec = preload("res://src/native_pal98_text_codec.gd")

var error: String = ""
var _codec
var _actions: Array = []
var _default_action: int = 2
var _ticks: int = 0
var _receipts: Array = []

func bind(source) -> bool:
	if source == null or source.metadata().is_empty():
		error = "pal98-dialogue-host: admitted source required"; return false
	var codec = Codec.new()
	if not codec.open(source.metadata().text_encoding):
		error = "pal98-dialogue-host: " + codec.error; return false
	_codec = codec; error = ""; return true

## Scripted input: the first entries are consumed in order, then the default
## action repeats. This is an explicit policy, not a device or an input model.
func set_input_policy(actions: Array, default_action: int = 2) -> void:
	for action in actions:
		if typeof(action) != TYPE_INT or action < -32768 or action > 32767:
			error = "pal98-dialogue-host: input action outside I2"; return
	_actions = actions.duplicate(); _default_action = default_action

func ticks() -> int:
	return _ticks

func receipts() -> Array:
	return _receipts.duplicate(true)

func texts() -> Array:
	var result: Array = []
	for receipt in _receipts:
		if receipt.has("text"): result.append(receipt.text)
	return result

func _failure(message: String) -> Dictionary:
	error = "pal98-dialogue-host: " + message
	return {"error": error}

## Returns the caller's expected host event for one dialogue request.
func answer(request: Dictionary) -> Dictionary:
	if not request.get("kind") is String: return _failure("request shape")
	var receipt: Dictionary = {"kind": request.kind}
	match request.kind:
		"capture_background":
			_receipts.append(receipt); return {"kind": "captured"}
		"restore_background":
			_receipts.append(receipt); return {"kind": "restored"}
		"draw_dialogue_icon":
			receipt.index = request.get("index"); receipt.x = request.get("x"); receipt.y = request.get("y")
			_receipts.append(receipt); return {"kind": "drawn"}
		"draw_dialogue_box":
			receipt.x = request.get("x"); receipt.y = request.get("y")
			receipt.half_length = request.get("half_length")
			_receipts.append(receipt); return {"kind": "box_drawn"}
		"draw_string", "draw_glyph":
			if not request.get("nul_terminated_bytes") is PackedByteArray:
				return _failure(request.kind + " requires the source bytes")
			# The caller hands over the source run with a trailing NUL load
			# sentinel; the sentinel is not part of the drawn text.
			var raw: PackedByteArray = request.nul_terminated_bytes
			while raw.size() > 0 and raw[raw.size() - 1] == 0:
				raw = raw.slice(0, raw.size() - 1)
			var decoded: Dictionary = _codec.decode(raw)
			if decoded.has("error"): return _failure(str(decoded.error))
			receipt.x = request.get("x"); receipt.y = request.get("y")
			receipt.palette_word = request.get("palette_word"); receipt.shadow_word = request.get("shadow_word")
			receipt.codepoints = decoded.codepoints.duplicate()
			if decoded.has("text"): receipt.text = decoded.text
			if request.has("byte_offset"): receipt.byte_offset = request.byte_offset
			_receipts.append(receipt); return {"kind": "drawn"}
		"poll_input":
			var action: int = _default_action
			if not _actions.is_empty(): action = _actions.pop_front()
			receipt.model = request.get("model"); receipt.action = action
			_receipts.append(receipt); return {"kind": "input", "action": action}
		"wait":
			_ticks += 1
			receipt.model = request.get("model"); receipt.target_counter = request.get("target_counter")
			receipt.ticks = _ticks
			_receipts.append(receipt); return {"kind": "tick"}
	return _failure("unhandled dialogue request " + request.kind)
