# SPDX-License-Identifier: MIT
extends RefCounted
## The real scene-background renderer behind the render_current_map_background
## request (original entry 0x0041CB34): the original resets the view offsets,
## latches the render origin to the current viewport, converts the viewport
## pixel to a map cell/half and flattens the map. Native already owns that
## decomposition (draw_plan) and the tile/palette decode, so this module blits
## the same plan into a software 320x200 RGBA frame with a content hash — real
## pixel evidence a headless drive can verify, with a per-render receipt.
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
const Schema = preload("res://src/native_schema.gd")
const WIDTH := 320
const HEIGHT := 200

var error: String = ""
var _records
var _renders: Array = []
var _indices: PackedByteArray = PackedByteArray()
var _coverage: PackedByteArray = PackedByteArray()
var _rgba: PackedByteArray = PackedByteArray()
var _live_palette: PackedByteArray = PackedByteArray()

func _failure(message: String) -> Dictionary:
	error = "pal98-scene-render: " + message
	return {"error": error}

func bind(records) -> bool:
	if records == null:
		error = "pal98-scene-render: addressed graphics reader required"; return false
	_records = records; _renders = []; _indices.clear(); _coverage.clear(); _rgba.clear(); _live_palette.clear()
	_capture_page.clear()
	error = ""; return true

func current_rgba() -> PackedByteArray:
	return _rgba.duplicate()

## Install into the indexed software surface. Existing pixels are recoloured
## immediately and later renders retain this palette. Window upload is a
## separate consumer; this receipt never claims a GPU frame was presented.
func install_palette(rgb6: PackedByteArray) -> Dictionary:
	var issue = Indexed.validate_palette(rgb6)
	if not issue.is_empty(): return _failure(issue)
	var pixels = _rgba
	if not _indices.is_empty():
		var mapped = Indexed.rgba({"width": WIDTH, "height": HEIGHT, "indices": _indices, "coverage": _coverage}, rgb6, false)
		if mapped.has("error"): return _failure(mapped.error)
		pixels = mapped.value
	_live_palette = rgb6.duplicate(); _rgba = pixels.duplicate()
	return {"completed": true, "surface": "indexed_software", "has_frame": not _indices.is_empty(),
		"rgba_sha256": Schema.digest(_rgba) if not _rgba.is_empty() else ""}

func receipts() -> Array:
	return _renders.duplicate(true)

## Blit covered indices in the existing map plan order. Skipped RLE/literal
## 255 pixels preserve the destination; RGB conversion follows composition.
func _blit(frame_buffer: PackedByteArray, image: Dictionary, origin: Vector2i) -> void:
	var width := int(image.width); var height := int(image.height)
	var pixels: PackedByteArray = image.indices
	for row in range(height):
		var y := origin.y + row
		if y < 0 or y >= HEIGHT: continue
		for column in range(width):
			var x := origin.x + column
			if x < 0 or x >= WIDTH: continue
			var at := y * WIDTH + x
			var src := row * width + column
			if image.coverage[src] == 0 or pixels[src] == 255: continue
			frame_buffer[at] = pixels[src]

## Renders the loaded map at the state's current viewport the way the original
## background pass does: convert the viewport pixel to a map cell/half, flatten
## the map with the installed palette (source selection before first install),
## and clip to the 320x200 drawing window.
func render(state: Dictionary, palette_index: int = 0, palette_variant: int = 0) -> Dictionary:
	if _records == null: return _failure("graphics reader not bound")
	if not state.get("globals") is Dictionary: return _failure("render requires the pending state")
	var globals: Dictionary = state.globals
	var map_id = globals.get("loaded_map_id")
	var viewport_x = globals.get("viewport_x"); var viewport_y = globals.get("viewport_y")
	if not map_id is int or not viewport_x is int or not viewport_y is int:
		return _failure("render requires the explicit loaded map id and viewport words")
	var cell: Dictionary = Occlusion.world_to_cell(viewport_x, viewport_y)
	if cell.has("error"): return _failure(str(cell.error))
	var background = Background.new()
	if not background.load_source(_records, map_id, palette_index, palette_variant):
		return _failure(str(background.error))
	var plan: Dictionary = background.draw_plan(cell.value.x, cell.value.y, cell.value.half)
	if plan.has("error"): return _failure(str(plan.error))
	var group: Dictionary = _records.group("GOP.MKF", map_id)
	if group.has("error"): return _failure(str(group.error))
	var palette: Dictionary = _records.palette(palette_index, palette_variant)
	if palette.has("error"): return _failure(str(palette.error))
	var frame_buffer := PackedByteArray(); frame_buffer.resize(WIDTH * HEIGHT)
	var images: Dictionary = {}
	var rendered_cells: int = 0
	for cell_plan in plan.value:
		for piece in ["lower", "upper"]:
			var descriptor: Dictionary = cell_plan[piece]
			if piece == "upper" and not descriptor.present: continue
			var frame_index: int = descriptor.frame
			if frame_index < 0: continue
			if not images.has(frame_index):
				var decoded: Dictionary = Indexed.frame(group.value, frame_index)
				if decoded.has("error"): return _failure(str(decoded.error))
				images[frame_index] = decoded.value
			var origin: Vector2i = Vector2i(cell_plan.top_left.x, cell_plan.top_left.y)
			_blit(frame_buffer, images[frame_index], origin)
		rendered_cells += 1
	var coverage = PackedByteArray(); coverage.resize(WIDTH * HEIGHT); coverage.fill(1)
	var rgb6: PackedByteArray = _live_palette if not _live_palette.is_empty() else palette.value
	var mapped = Indexed.rgba({"width": WIDTH, "height": HEIGHT, "indices": frame_buffer, "coverage": coverage}, rgb6, false)
	if mapped.has("error"): return _failure(mapped.error)
	var pixels: PackedByteArray = mapped.value
	var candidate = state.duplicate(true)
	candidate.globals.view_offset_x = 0; candidate.globals.view_offset_y = 0
	candidate.globals.previous_viewport_x = viewport_x; candidate.globals.previous_viewport_y = viewport_y
	var identity: Dictionary = background.source()
	var receipt: Dictionary = {"kind": "render_current_map_background", "map_id": map_id,
		"map_cell": [cell.value.x, cell.value.y, cell.value.half],
		"cells": rendered_cells, "tiles": images.size(),
		"frame_sha256": Schema.digest(pixels), "palette_sha256": Schema.digest(rgb6), "identity": identity,
		"surface": "indexed_software"}
	_indices = frame_buffer; _coverage = coverage; _rgba = pixels; _live_palette = rgb6.duplicate()
	_renders.append(receipt)
	return {"completed": true, "state": candidate, "rgba": pixels.duplicate(), "width": WIDTH, "height": HEIGHT,
		"receipt": receipt}

## Non-battle T121 preparation only: G01B0 is the new target while pushscr
## captures the OLD displayed page into G00C0. Build an isolated candidate;
## neither the current page nor the dialogue capture changes here. T121's
## lane execution, timing and final presentation are still unbound, so this
## preparation must never acknowledge the full host command as completed.
func prepare_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	if _records == null or _indices.is_empty(): return _failure("cross-fade requires a bound current indexed page")
	if not state.get("globals") is Dictionary or typeof(state.globals.get("battle_mode")) != TYPE_INT:
		return _failure("cross-fade requires explicit battle mode")
	if state.globals.battle_mode != 0: return _failure("T121 battle target preparation owner not bound")
	if first < -32768 or first > 32767 or second < -32768 or second > 32767:
		return _failure("T121 arguments outside I2")
	var target = get_script().new()
	target.bind(_records)
	if not _live_palette.is_empty():
		var installed: Dictionary = target.install_palette(_live_palette)
		if installed.has("error"): return installed
	var rendered: Dictionary = target.render(state)
	if rendered.has("error"): return rendered
	var receipt: Dictionary = {"kind": "clear_effective_cross_fade",
		"first": first, "second": second, "pixels_per_lane": 0x29AC,
		"base_page_sha256": Schema.digest(_indices),
		"base_rgba_sha256": Schema.digest(_rgba),
		"target_sha256": rendered.receipt.frame_sha256,
		"boundary": "T121 lane execution (adpic), timing and final presentation not implemented"}
	return {"completed": false, "prepared": true, "receipt": receipt,
		"candidate_state": rendered.state, "target_rgba": rendered.rgba,
		"base_page": {"indices": _indices.duplicate(), "coverage": _coverage.duplicate()},
		"target_page": {"indices": target._indices.duplicate(), "coverage": target._coverage.duplicate()}}

var _transition_clock

func bind_transition_clock(clock) -> bool:
	if clock == null or not clock.has_method("consume"):
		error = "the transition clock must consume logical units"; return false
	_transition_clock = clock; error = ""; return true

## The recovered map T121 execution (PAL98_CLEAR_EFFECTIVE_CROSS_FADE_STAGE_
## OPINION.md): phases default to 88 when the argument is zero, the VB For
## includes its upper bound, lane = phase % 6, every phase presents and
## consumes wtime(delay) through the bound logical clock, and the exact target
## page is presented only after the loop (popscr(G01B0)). The PAL.dll adpic
## pixel blend and the G050C lane initialisation are unrecovered, so the
## per-phase presented pixels stay on the pre-transition page: an explicitly
## named approximation; the phase count, timing, lane rotation and endpoint
## are evidence-pinned. Nothing is acknowledged before the endpoint.
func execute_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	if _transition_clock == null: return _failure("T121 execution requires a bound logical clock")
	var prepared: Dictionary = prepare_clear_cross_fade(state, first, second)
	if prepared.has("error"): return prepared
	var phases: int = 88 if first == 0 else first
	if phases < 0 or phases > 32767 or second < 0:
		return _failure("T121 phases or delay outside the original range")
	var phase_receipts: Array = []
	for phase in range(phases + 1):
		var consumed: Dictionary = _transition_clock.consume(second)
		if consumed.has("error"): return _failure("T121 wtime: " + str(consumed.error))
		phase_receipts.append({"phase": phase, "lane": phase % 6,
			"step": "adpic0" if phase < 6 else "adpic", "wtime": second,
			"presented": "pre_transition_page"})
	_indices = prepared.target_page.indices
	_coverage = prepared.target_page.coverage
	_rgba = prepared.target_rgba
	var receipt: Dictionary = {"kind": "clear_effective_cross_fade", "completed": true,
		"phases": phases + 1, "pixels_per_lane": 0x29AC, "delay": second,
		"phase_receipts": phase_receipts, "lane_rotation": "phase % 6",
		"endpoint_sha256": Schema.digest(_rgba),
		"named_gap": "per-phase adpic blending and G050C lane initialisation are unrecovered PAL.dll helpers; mid-phase pixels stay on the pre-transition page, the endpoint page is exact"}
	_renders.append(receipt)
	return {"completed": true, "state": prepared.candidate_state, "receipt": receipt}

## Production host adapter: preparation alone never releases a script waiter.
func answer(request: Dictionary) -> Dictionary:
	var result: Dictionary
	match request.get("kind"):
		"render_current_map_background":
			if not request.get("state") is Dictionary: return _failure("render host requires pending state")
			return render(request.state)
		"capture_dialog_background": result = capture_page()
		"restore_dialog_background": result = restore_dialog_background()
		"clear_effective_cross_fade":
			if not request.get("state") is Dictionary: return _failure("cross-fade host requires pending state")
			for key in ["first", "second"]:
				if typeof(request.get(key)) != TYPE_INT: return _failure("cross-fade requires explicit " + key)
			var executed = execute_clear_cross_fade(request.state, request.first, request.second)
			if executed.has("error"): return executed
			return executed
		_: return _failure("unhandled scene-page request " + str(request.get("kind")))
	if not result.has("error") and request.get("state") is Dictionary:
		result.state = request.state.duplicate(true)
	return result

## DialogueCaller uses these names, not the display family's command names.
func answer_dialogue(request: Dictionary) -> Dictionary:
	var result: Dictionary
	var event: String
	match request.get("kind"):
		"capture_background": result = capture_page(); event = "captured"
		"restore_background": result = restore_dialog_background(); event = "restored"
		_: return _failure("unhandled dialogue-page request " + str(request.get("kind")))
	if result.has("error"): return result
	# DialogueCaller validates the event's exact shape. Pixel evidence remains
	# in receipts(), not in extra event fields that invalidate the signal.
	return {"kind": event}

var _capture_page: Dictionary = {}

## G00C0: capture the composed indexed page (indices + coverage) at dialog
## open. Later renders overwrite the screen, never the page; only a new
## capture replaces it. Refuses while the surface is empty.
func capture_page() -> Dictionary:
	if _indices.is_empty():
		return _failure("capture_page requires a rendered indexed surface")
	_capture_page = {"indices": _indices.duplicate(), "coverage": _coverage.duplicate(),
		"sha256": Schema.digest(_indices)}
	var receipt: Dictionary = {"kind": "capture_dialog_background",
		"page_sha256": _capture_page.sha256}
	_renders.append(receipt)
	return {"completed": true, "receipt": receipt}

## G00C0 restore: copy the captured page back into the surface and recompose
## the RGBA through the live palette. Without a captured page the refusal
## stands: a map render receipt is not G00C0.
func restore_dialog_background() -> Dictionary:
	if _capture_page.is_empty():
		return _failure("restore_dialog_background requires the captured-page owner; a map receipt is not G00C0")
	var indices: PackedByteArray = _capture_page.indices.duplicate()
	var coverage: PackedByteArray = _capture_page.coverage.duplicate()
	var palette: PackedByteArray = _live_palette
	var mapped = Indexed.rgba({"width": WIDTH, "height": HEIGHT, "indices": indices, "coverage": coverage}, palette, false)
	if mapped.has("error"): return _failure(mapped.error)
	_indices = indices; _coverage = coverage; _rgba = mapped.value
	var receipt: Dictionary = {"kind": "restore_dialog_background",
		"page_sha256": _capture_page.sha256,
		"frame_sha256": Schema.digest(_rgba), "from_page": true}
	_renders.append(receipt)
	return {"completed": true, "receipt": receipt}
