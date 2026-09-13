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

## Two map renders do not execute the scene/page/phase work required by T121.
func prepare_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	var result = _failure("clear_effective_cross_fade requires scene/page and per-phase execution owners")
	result.request = {"kind": "clear_effective_cross_fade", "first": first, "second": second,
		"battle_mode": state.get("globals", {}).get("battle_mode")}
	return result

## G00C0 is the captured composed page, not the most recent map render.
## The existing DialogueSurface capture/restore owner must be wired by a Session.
func restore_dialog_background() -> Dictionary:
	return _failure("restore_dialog_background requires the captured-page owner; a map receipt is not G00C0")
