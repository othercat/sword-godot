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

## The 0x0073 preparation (original entry 0x0041CEC4, T121, non-battle
## branch): render the fresh background, capture it as the base page (the
## original copies the rendered half over the base page), pin the recovered
## lane parameters (0x29AC pixels per lane, phases default 88) and render the
## post-fade background. The per-lane dissolve itself runs through PAL.dll's
## adpic, whose pixel rule is not recovered - the receipt names it as the
## remaining presentation boundary instead of faking the transition.
func prepare_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	var rendered: Dictionary = render(state)
	if rendered.has("error"): return rendered
	var captured: Dictionary = capture_page()
	if captured.has("error"): return captured
	var phases: int = 88 if first == 0 else first
	var final: Dictionary = render(state)
	if final.has("error"): return final
	var receipt: Dictionary = {"kind": "clear_effective_cross_fade",
		"phases": phases, "delay": second, "pixels_per_lane": 0x29AC,
		"base_page_sha256": captured.receipt.page_sha256,
		"target_sha256": rendered.receipt.frame_sha256,
		"final_sha256": final.receipt.frame_sha256,
		"boundary": "per-lane dissolve (adpic) not recovered; presentation pending"}
	_renders.append(receipt)
	return {"completed": true, "receipt": receipt}

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
	_indices = _capture_page.indices.duplicate()
	_coverage = _capture_page.coverage.duplicate()
	var palette: PackedByteArray = _live_palette
	var mapped = Indexed.rgba({"width": WIDTH, "height": HEIGHT, "indices": _indices, "coverage": _coverage}, palette, false)
	if mapped.has("error"): return _failure(mapped.error)
	_rgba = mapped.value
	var receipt: Dictionary = {"kind": "restore_dialog_background",
		"page_sha256": _capture_page.sha256,
		"frame_sha256": Schema.digest(_rgba), "from_page": true}
	_renders.append(receipt)
	return {"completed": true, "receipt": receipt}
