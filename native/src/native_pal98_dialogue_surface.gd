# SPDX-License-Identifier: MIT
extends SubViewport
## One explicit 320x200 candidate target. Capture/restore operate on actual
## rendered pixels; system-font RGBA output is not original indexed GDI parity.
## No script dispatch, clock, input, public state or save contract is owned here.
const TextLayer = preload("res://src/native_pal98_text_layer.gd")
const Schema = preload("res://src/native_schema.gd")
var _background: TextureRect
var _text: TextLayer
var _captured: Image
var _capture_sha: String = ""
var _configured: bool = false
var _busy: bool = false

func _opaque_image(background: Image) -> Image:
	if background == null or background.is_empty() or background.is_compressed() or background.get_size() != Vector2i(320,200): return null
	var initial: Image = background.duplicate(); initial.convert(Image.FORMAT_RGBA8)
	# A supplied mip chain is not part of the fixed-size target image. Normalize
	# only the private copy before validation, upload and exact base-level hashes.
	initial.clear_mipmaps()
	var bytes: PackedByteArray = initial.get_data()
	for offset in range(3,bytes.size(),4):
		if bytes[offset] != 255: return null
	return initial

func configure(font: Font, palette: PackedColorArray, background: Image) -> bool:
	if _configured: return false
	var initial: Image = _opaque_image(background)
	if initial == null: return false
	var layer = TextLayer.new()
	if not layer.configure(font,palette): layer.free(); return false
	size = Vector2i(320,200); disable_3d = true; transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_background = TextureRect.new(); _background.texture = ImageTexture.create_from_image(initial)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _background.size = Vector2(320,200)
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; _background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background); _text = layer; add_child(_text); _configured = true
	return true

func text_snapshot() -> Array:
	return _text.snapshot() if _configured else []

func captured_sha256() -> String:
	return _capture_sha

func _failure(code: String, source: Dictionary) -> Dictionary:
	var diagnostic: Dictionary = source.duplicate(true); diagnostic.code = code
	return {"error":"pal98-dialogue-surface: " + code,"diagnostic":diagnostic}

func _rendered_frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _pixels() -> Image:
	var pixels: Image = get_texture().get_image(); pixels.convert(Image.FORMAT_RGBA8); return pixels

func _target_error(source: Dictionary) -> Dictionary:
	if not _configured or not is_inside_tree(): return _failure("dialogue_surface_not_ready",source)
	if DisplayServer.get_name() == "headless": return _failure("dialogue_surface_requires_renderer",source)
	if _busy: return _failure("dialogue_surface_request_pending",source)
	if size != Vector2i(320,200) or render_target_update_mode != SubViewport.UPDATE_ALWAYS: return _failure("dialogue_surface_target_changed",source)
	return {}

func replace_scene_frame(background: Image, source: Dictionary = {}) -> Dictionary:
	var invalid: Dictionary = _target_error(source)
	if not invalid.is_empty(): return invalid
	var initial: Image = _opaque_image(background)
	if initial == null: return _failure("invalid_dialogue_scene_frame",source)
	var receipt: Dictionary = {"kind":"replace_scene_frame","source":source.duplicate(true)}
	_busy = true; _background.texture = ImageTexture.create_from_image(initial); _text.clear_text()
	await _rendered_frame()
	_busy = false
	invalid = _target_error(receipt.source)
	if not invalid.is_empty(): return invalid
	receipt.rendered_process_frame = Engine.get_process_frames(); receipt.rgba_sha256 = Schema.digest(_pixels().get_data())
	if receipt.rgba_sha256 != Schema.digest(initial.get_data()): return _failure("dialogue_scene_frame_mismatch",receipt.source)
	# Scene composition replaces displayed pixels, not the saved dialog snapshot.
	return {"event":{"kind":"scene_frame_drawn"},"receipt":receipt}

func apply_request(request: Dictionary, encoding: String, source: Dictionary = {}) -> Dictionary:
	var invalid: Dictionary = _target_error(source)
	if not invalid.is_empty(): return invalid
	source = source.duplicate(true)
	var kind = request.get("kind")
	if kind not in ["draw_glyph","draw_string","capture_background","restore_background"]:
		return _failure("dialogue_surface_request_unimplemented",source)
	if kind in ["capture_background","restore_background"] and request.size() != 1:
		return _failure("invalid_dialogue_background_request",source)
	if kind == "restore_background" and _captured == null: return _failure("dialogue_background_not_captured",source)
	var queued: Dictionary = {}
	if kind in ["draw_glyph","draw_string"]:
		queued = _text.append_draw(request,encoding,source)
		if queued.has("error"): return queued
	_busy = true
	if kind == "restore_background":
		_background.texture = ImageTexture.create_from_image(_captured)
		_text.clear_text()
	await _rendered_frame()
	_busy = false
	invalid = _target_error(source)
	if not invalid.is_empty(): return invalid
	var event: String = "drawn"
	var receipt: Dictionary = {"kind":kind,"source":source.duplicate(true),"rendered_process_frame":Engine.get_process_frames()}
	if kind in ["draw_glyph","draw_string"]:
		if not _text.commands_submitted(queued.receipt.serial): return _failure("dialogue_draw_not_submitted",source)
		receipt.text = queued.receipt
	else:
		var pixels: Image = _pixels(); var digest: String = Schema.digest(pixels.get_data())
		if kind == "capture_background":
			_captured = pixels; _capture_sha = digest; event = "captured"
		else:
			if digest != _capture_sha: return _failure("dialogue_background_restore_mismatch",source)
			event = "restored"
		receipt.rgba_sha256 = digest
	return {"event":{"kind":event},"receipt":receipt}
