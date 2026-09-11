# SPDX-License-Identifier: MIT
extends RefCounted
## Original vmap background stage, not exmap/ntre sprite occlusion or a Session.
## Compose each lower/upper tile pair, then draw cells in original row order.
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const Terrain = preload("res://src/native_terrain.gd")
const PIXEL_BUDGET = 33554432
var error: String = ""
var _map: PackedByteArray
var _gop: PackedByteArray
var _palette: PackedByteArray
var _identity: Dictionary = {}

func load_source(records, map_index: int, palette_index: int, variant: int) -> bool:
	if records == null: error = "addressed graphics reader required"; return false
	var map: Dictionary = records.decoded_chunk("MAP.MKF", map_index)
	var gop: Dictionary = records.group("GOP.MKF", map_index)
	var palette: Dictionary = records.palette(palette_index, variant)
	for selected in [map, gop, palette]:
		if selected.has("error"): error = selected.error; return false
	_map = map.value.duplicate(); _gop = gop.value.duplicate(); _palette = palette.value.duplicate()
	_identity = {"map": map.source.duplicate(true), "gop": gop.source.duplicate(true), "palette": palette.source.duplicate(true)}
	error = ""; return true

func source() -> Dictionary:
	return _identity.duplicate(true)

static func descriptor(value: int, upper: bool) -> Dictionary:
	var frame: int = (value & 255) | ((value & 4096) >> 4)
	return {"word": value & 65535, "frame": frame - 1 if upper else frame,
		"present": not upper or frame != 0, "height": (value >> 8) & 15,
		"blocked": (value & 8192) != 0}

func draw_plan(map_x: int, map_y: int, half: int) -> Dictionary:
	if _map.size() != 65536: return {"error": "original map background not loaded"}
	if map_x < -32768 or map_x > 32767 or map_y < -32768 or map_y > 32767 or half not in [0, 1]: return {"error": "vmap requires signed16 coordinates and half0/1"}
	var result: Array = []
	for row in range(13 + half):
		for subrow in range(2):
			for column in range(11):
				var at: int = (((map_y + row) * 64 + map_x + column) * 2 + subrow) * 4 & 65535
				result.append({"offset": at, "column": column, "row": row, "half": subrow,
					"lower": descriptor(_map.decode_u16(at), false), "upper": descriptor(_map.decode_u16(at + 2), true),
					"cell": Vector2i(column + row + subrow, row - column),
					"top_left": Vector2i(column * 32 + subrow * 16 - 16 - half * 16, row * 16 + subrow * 8 - 8 - half * 8)})
	return {"value": result, "source": source(), "map_x": map_x, "map_y": map_y, "half": half}

func _image(frame_index: int) -> Dictionary:
	var decoded: Dictionary = Indexed.frame(_gop, frame_index)
	if decoded.has("error"): return decoded
	var rgba: Dictionary = Indexed.rgba(decoded.value, _palette, true)
	if rgba.has("error"): return rgba
	return {"value": Image.create_from_data(rgba.width, rgba.height, false, Image.FORMAT_RGBA8, rgba.value)}

func make_view(map_x: int, map_y: int, half: int) -> Dictionary:
	var plan: Dictionary = draw_plan(map_x, map_y, half)
	if plan.has("error"): return plan
	var tiles: Array = []; var placements: Array = []; var images: Dictionary = {}; var textures: Dictionary = {}
	var used: Dictionary = {}; var image_pixels: int = 0; var pair_pixels: int = 0
	for cell in plan.value:
		var low: int = cell.lower.frame; var high: int = cell.upper.frame
		var key: String = "%d:%d" % [low, high]
		if not used.has(key):
			for frame_index in [low, high]:
				if frame_index < 0 or images.has(frame_index): continue
				var decoded: Dictionary = _image(frame_index)
				if decoded.has("error"): decoded.source = source(); decoded.map_byte_offset = cell.offset; return decoded
				image_pixels += decoded.value.get_width() * decoded.value.get_height()
				if image_pixels > PIXEL_BUDGET: return {"error": "background source image pixel budget", "source": source()}
				images[frame_index] = decoded.value
			var size: Vector2i = images[low].get_size()
			if high >= 0: size = size.max(images[high].get_size())
			pair_pixels += size.x * size.y
			if pair_pixels > PIXEL_BUDGET: return {"error": "background tile-pair pixel budget", "source": source()}
			var pair = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8); pair.fill(Color.TRANSPARENT)
			pair.blit_rect(images[low], Rect2i(Vector2i.ZERO, images[low].get_size()), Vector2i.ZERO)
			if high >= 0: pair.blend_rect(images[high], Rect2i(Vector2i.ZERO, images[high].get_size()), Vector2i.ZERO)
			textures[key] = ImageTexture.create_from_image(pair)
			tiles.append({"id": key, "asset_id": key, "width": size.x, "height": size.y,
				"anchor": {"x": 16, "y": 8}, "scale_milli": 1000})
			used[key] = true
		placements.append({"position": {"x": cell.cell.x, "y": cell.cell.y}, "tile_id": key, "sort_offset_y": 0})
	var map: Dictionary = {"coordinates": {"kind": "isometric", "tile_width": 32, "tile_height": 16, "origin": {"x": 0, "y": 0}}, "terrain": {"tiles": tiles}}
	var layer: Dictionary = {"draw_order": 0, "placements": placements}
	var node: Node2D = Terrain.make_flat(map, layer, textures, {})
	if not node is TileMapLayer:
		node.free(); return {"error": "background atlas exceeds TileMap GPU budget", "source": source()}
	# Y then X follows vmap's row/half/column order. Pair composition preserves
	# lower-before-upper within the cell. This is not the unstable ntre sort.
	node.y_sort_enabled = true; node.x_draw_order_reversed = false
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.collision_enabled = false; node.navigation_enabled = false; node.occlusion_enabled = false
	node.position -= Vector2(half * 16, half * 8)
	return {"value": node, "source": source(), "cells": placements.size(), "pairs": tiles.size(),
		"source_pixels": image_pixels, "pair_pixels": pair_pixels, "plan": plan.value}
