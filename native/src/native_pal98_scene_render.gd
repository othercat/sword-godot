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
var _tile_cache: Dictionary = {}

func _failure(message: String) -> Dictionary:
	error = "pal98-scene-render: " + message
	return {"error": error}

func bind(records) -> bool:
	if records == null:
		error = "pal98-scene-render: addressed graphics reader required"; return false
	_records = records; _tile_cache = {}; _renders = []; error = ""; return true

func receipts() -> Array:
	return _renders.duplicate(true)

## Software blit of one 32x16 tile-pair image at the plan's top-left offset,
## clipped to the 320x200 frame; alpha 0 stays transparent.
func _blit(frame_buffer: PackedByteArray, image: Dictionary, origin: Vector2i) -> void:
	var width := int(image.width); var height := int(image.height)
	var pixels: PackedByteArray = image.value
	for row in range(height):
		var y := origin.y + row
		if y < 0 or y >= HEIGHT: continue
		for column in range(width):
			var x := origin.x + column
			if x < 0 or x >= WIDTH: continue
			var at := (y * WIDTH + x) * 4
			var src := (row * width + column) * 4
			if pixels[src + 3] == 0: continue
			frame_buffer[at] = pixels[src]
			frame_buffer[at + 1] = pixels[src + 1]
			frame_buffer[at + 2] = pixels[src + 2]
			frame_buffer[at + 3] = 255

## Renders the loaded map at the state's current viewport the way the original
## background pass does: convert the viewport pixel to a map cell/half, flatten
## the map with the day palette, clip to the 320x200 drawing window.
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
	var frame_buffer := PackedByteArray(); frame_buffer.resize(WIDTH * HEIGHT * 4)
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
				var rgba: Dictionary = Indexed.rgba(decoded.value, palette.value, true)
				if rgba.has("error"): return _failure(str(rgba.error))
				images[frame_index] = rgba
			var origin: Vector2i = Vector2i(cell_plan.top_left.x, cell_plan.top_left.y)
			_blit(frame_buffer, images[frame_index], origin)
		rendered_cells += 1
	var identity: Dictionary = background.source()
	var receipt: Dictionary = {"kind": "render_current_map_background", "map_id": map_id,
		"map_cell": [cell.value.x, cell.value.y, cell.value.half],
		"cells": rendered_cells, "tiles": images.size(),
		"frame_sha256": Schema.digest(frame_buffer), "identity": identity}
	_renders.append(receipt)
	return {"completed": true, "rgba": frame_buffer, "width": WIDTH, "height": HEIGHT,
		"receipt": receipt}

## The 0x0073 clear-effective-cross-fade preparation (original entry
## 0x0041CEC4, non-battle branch): render the current map background, record
## the prepared lane parameters (0x29AC pixels per lane, effective phases with
## the 0 defaulting to 88) and render the post-fade background. The per-lane
## fade animation itself is presentation; the renders and parameters here are
## the headless-verifiable preparation.
func prepare_clear_cross_fade(state: Dictionary, first: int, second: int) -> Dictionary:
	var before: int = _renders.size()
	var rendered: Dictionary = render(state)
	if rendered.has("error"): return rendered
	var phases: int = 88 if first == 0 else first
	var prepared: Dictionary = {"kind": "clear_effective_cross_fade",
		"phases": phases, "delay": second, "pixels_per_lane": 0x29AC,
		"pre_render": rendered.receipt}
	_renders.append(prepared)
	var after: Dictionary = render(state)
	if after.has("error"): return after
	prepared.post_render = after.receipt
	prepared.renders_before = before
	return {"completed": true, "receipt": prepared.duplicate(true)}

## The 0x008E dialog-background restore: the dialog box was drawn over the
## last flattened background, so the restore re-establishes exactly that
## frame. With no rendered frame yet there is nothing to restore and the
## refusal is named instead of pretended.
func restore_dialog_background() -> Dictionary:
	if _renders.is_empty():
		return _failure("no rendered background exists to restore")
	var last: Dictionary = _renders[_renders.size() - 1]
	var receipt: Dictionary = {"kind": "restore_dialog_background",
		"frame_sha256": last.frame_sha256, "map_id": last.map_id,
		"map_cell": last.map_cell}
	_renders.append(receipt)
	return {"completed": true, "receipt": receipt}
