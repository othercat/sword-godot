# SPDX-License-Identifier: MIT
extends Control
## Internal PAL98 drawing adapter, not a script caller or Session. System-font
## ink is a presentation candidate; it is not the original indexed GDI raster.
const Codec = preload("res://src/native_pal98_text_codec.gd")
const MAX_RUNS = 4096
var _font: Font
var _palette: PackedColorArray = PackedColorArray()
var _codecs: Dictionary = {}
var _runs: Array = []
var _serial: int = 0

class TextRun extends Control:
	var line: TextLine
	var shadow: bool
	var foreground_index: int
	var foreground: Color
	var shadow_colour: Color
	var commands_submitted: bool = false
	func _draw() -> void:
		if shadow: line.draw(get_canvas_item(),Vector2(1,1),shadow_colour)
		if foreground_index != 255: line.draw(get_canvas_item(),Vector2.ZERO,foreground)
		commands_submitted = true

func configure(font: Font, palette: PackedColorArray) -> bool:
	if font == null or palette.size() != 256: return false
	for colour in palette:
		if not is_finite(colour.r) or not is_finite(colour.g) or not is_finite(colour.b) or colour.a != 1.0 or colour.r < 0 or colour.r > 1 or colour.g < 0 or colour.g > 1 or colour.b < 0 or colour.b > 1: return false
	clear_text(); _font = font; _palette = palette.duplicate()
	size = Vector2(320,200); clip_contents = true; mouse_filter = Control.MOUSE_FILTER_IGNORE
	return true

func clear_text() -> void:
	for run in _runs: remove_child(run.node); run.node.queue_free()
	_runs.clear()

func snapshot() -> Array:
	return _runs.map(func(run): return run.receipt.duplicate(true))

func commands_submitted(serial: int) -> bool:
	for run in _runs:
		if run.receipt.serial == serial: return run.node.commands_submitted
	return false

static func _i2(value) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value) and value >= -32768 and value <= 32767

func _failure(code: String, source: Dictionary, relative: int = -1, draw_start: int = -1) -> Dictionary:
	var diagnostic: Dictionary = source.duplicate(true)
	diagnostic.code = code
	if relative >= 0:
		diagnostic.relative_draw_byte_offset = relative
		if draw_start >= 0:
			diagnostic.draw_byte_offset = draw_start; diagnostic.error_byte_offset = draw_start + relative
	return {"error":"pal98-text-layer: " + code,"diagnostic":diagnostic}

func append_draw(request: Dictionary, encoding: String, source: Dictionary = {}) -> Dictionary:
	if _font == null: return _failure("text_layer_not_configured",source)
	if _runs.size() >= MAX_RUNS: return _failure("text_layer_budget",source)
	if request.get("kind") not in ["draw_glyph","draw_string"]: return _failure("not_text_draw_request",source)
	for key in ["x","y","palette_word","shadow_word"]:
		if not _i2(request.get(key)): return _failure("invalid_text_draw_field",source)
	# Original negative/out-of-surface coordinates can access invalid memory.
	# Diagnose those inputs; the Native candidate never reproduces unsafe copies.
	if request.x < 0 or request.x >= 320 or request.y < 0 or request.y >= 200:
		return _failure("text_target_bounds_unimplemented",source)
	if (int(request.palette_word) & 255) == 255 and int(request.shadow_word) == 0:
		return _failure("text_transparent_foreground_mask_unimplemented",source)
	var bytes = request.get("nul_terminated_bytes")
	if not bytes is PackedByteArray or bytes.is_empty() or bytes.size() > 256 or bytes[-1] != 0:
		return _failure("invalid_text_draw_buffer",source)
	if not _codecs.has(encoding):
		var codec = Codec.new()
		if not codec.open(encoding): return _failure("text_codec_unavailable",source)
		_codecs[encoding] = codec
	var used: int = bytes.find(0)
	var draw_start: int = int(request.get("byte_offset",source.get("byte_offset",-1)))
	var decoded: Dictionary = _codecs[encoding].decode(bytes.slice(0,used))
	if decoded.has("error"): return _failure(decoded.diagnostic.code,source,decoded.diagnostic.relative_byte_offset,draw_start)
	for index in range(decoded.codepoints.size()):
		var scalar: int = decoded.codepoints[index]
		if scalar < 32 or (scalar >= 127 and scalar <= 159): return _failure("text_control_ink_unimplemented",source)
		if not _font.has_char(scalar): return _failure("text_font_glyph_missing",source)
	var line = TextLine.new(); line.direction = TextServer.DIRECTION_LTR; line.preserve_invalid = false
	line.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if not decoded.text.is_empty() and not line.add_string(decoded.text,_font,16): return _failure("text_font_shape_failed",source)
	var run = TextRun.new(); run.line = line; run.shadow = int(request.shadow_word) == 0
	run.foreground_index = int(request.palette_word) & 255
	run.foreground = _palette[run.foreground_index]; run.shadow_colour = _palette[0]
	run.position = Vector2(request.x,request.y); run.size = Vector2(320 - request.x,mini(20,200 - int(request.y)))
	run.clip_contents = true; run.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_serial += 1
	var receipt: Dictionary = {"serial":_serial,"text":decoded.text,"encoding":encoding,
		"table_sha256":decoded.table_sha256,"source":source.duplicate(true),"bytes_before_nul":used,
		"draw_byte_offset":draw_start,"source_size_bytes":request.get("source_size_bytes",source.get("size_bytes",used)),
		"x":int(request.x),"y":int(request.y),"foreground_index":run.foreground_index,"shadow":run.shadow,
		"font_size":16,"font_family":_font.get_font_name(),"shape_width":line.get_size().x,
		"clip_width":int(run.size.x),"clip_height":int(run.size.y),"request_kind":request.kind}
	_runs.append({"node":run,"receipt":receipt}); add_child(run)
	# Acceptance only queues rendering. The host must observe a rendered frame
	# before acknowledging the execution request; no timer/input is advanced here.
	return {"queued":true,"receipt":receipt.duplicate(true)}
