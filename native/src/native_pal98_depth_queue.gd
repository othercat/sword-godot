# SPDX-License-Identifier: MIT
extends RefCounted
## Explicit original depth rows, already queued in their caller's order.
## Does not choose party/event order, mark map flags or infer original state.
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const PIXEL_BUDGET = 33554432
var error: String = ""
var _rows: Array = []

static func signed16(value: int) -> int:
	var low: int = value & 65535
	return low - 65536 if low >= 32768 else low

static func row_for_sprite(kind: String, screen_x: int, screen_y: int, layer_base: int, frame: Dictionary, source: Dictionary) -> Dictionary:
	if kind not in ["party", "event"]: return {"error": "explicit party/event sprite kind required"}
	for value in [screen_x, screen_y, layer_base]:
		if value < -32768 or value > 32767: return {"error": "sprite caller value outside signed16"}
	if not frame.get("width") is int or frame.width < 1 or frame.width > 8192: return {"error": "positive decoded sprite width required"}
	var x: int = screen_x - int(frame.width / 2)
	var base_y: int = screen_y + layer_base
	var sort_y: int = base_y + (10 if kind == "party" else 9)
	var layer: int = layer_base + (6 if kind == "party" else 2)
	# T163 uses checked VB I2 intermediates. Unlike ntre's later top subtraction,
	# an overflowing intermediate may not wrap back into the valid final range.
	for value in [x, base_y, sort_y, layer]:
		if value < -32768 or value > 32767: return {"error": "T163 sprite coordinate signed16 overflow"}
	var identity: Dictionary = source.duplicate(true); identity.sprite_kind = kind
	return {"value": {"x": x, "sort_y": sort_y, "layer_offset": layer, "frame": frame.duplicate(true), "source": identity}}

func load_rows(rows: Array) -> bool:
	# addtre can hold256 rows, but original ntre's DIV DL cannot produce that
	# 8-bit count. Preserve a diagnostic instead of executing the original trap.
	if rows.size() > 255: error = "original ntre count exceeds its 8-bit division limit"; return false
	var candidate: Array = []; var pixels: int = 0
	for row in rows:
		if not row is Dictionary: error = "depth row must be a dictionary"; return false
		for field in ["x", "sort_y", "layer_offset"]:
			if not row.get(field) is int or row[field] < -32768 or row[field] > 32767:
				error = "depth row requires signed16 " + field; return false
		var frame = row.get("frame")
		if not frame is Dictionary or not frame.get("width") is int or not frame.get("height") is int:
			error = "decoded depth frame dimensions required"; return false
		var width: int = frame.width; var height: int = frame.height
		if width < 1 or height < 1 or width > 8192 or height > 8192:
			error = "depth frame dimensions outside budget"; return false
		pixels += width * height
		if pixels > PIXEL_BUDGET: error = "depth frame pixel budget"; return false
		if not frame.get("indices") is PackedByteArray or not frame.get("coverage") is PackedByteArray or frame.indices.size() != width * height or frame.coverage.size() != width * height:
			error = "decoded depth frame planes required"; return false
		var source_value = row.get("source", {})
		if not source_value is Dictionary: error = "depth source identity must be a dictionary"; return false
		candidate.append({"x": row.x, "sort_y": row.sort_y, "layer_offset": row.layer_offset,
			"frame": {"width": width, "height": height, "indices": frame.indices.duplicate(), "coverage": frame.coverage.duplicate()},
			"source": source_value.duplicate(true), "submission_index": candidate.size()})
	_rows = candidate; error = ""; return true

func rows() -> Array:
	return _rows.duplicate(true)

func draw_order() -> Array:
	var rows: Array = _rows.duplicate(true)
	# This non-adjacent exchange preserves original ntre's nonstable tie effects.
	# A stable sort or Godot y_sort gives a different order for [22,22,18].
	for at in range(rows.size()):
		for later in range(at + 1, rows.size()):
			if rows[at].sort_y > rows[later].sort_y:
				var before: Dictionary = rows[at]; rows[at] = rows[later]; rows[later] = before
	for row in rows:
		row.top_y = signed16(row.sort_y - row.layer_offset - row.frame.height)
	return rows

func make_view(rgb6: PackedByteArray, clip_bottom: int) -> Dictionary:
	var issue: String = Indexed.validate_palette(rgb6)
	if not issue.is_empty(): return {"error": issue}
	if clip_bottom < 0 or clip_bottom > 200: return {"error": "depth target clip must be within0..200"}
	var ordered: Array = draw_order()
	var pictures: Array = []
	for row in ordered:
		if row.top_y >= 0 and row.top_y + row.frame.height - clip_bottom > 32767:
			return {"error": "original IPNA bottom-clip signed WORD wrap is not implemented", "source": row.source, "submission_index": row.submission_index}
		var visible_rows: bool = clip_bottom > 0 and row.top_y < clip_bottom and row.top_y + row.frame.height > 0
		if visible_rows and row.x + row.frame.width > 32767:
			return {"error": "original IPNA horizontal run WORD wrap is not implemented", "source": row.source, "submission_index": row.submission_index}
		# putipna's negative-top pixel skip multiplies in a WORD. When it wraps,
		# ordinary GPU clipping selects a different source row. Keep this known
		# unsupported boundary explicit instead of drawing silently wrong pixels.
		if visible_rows and row.top_y < 0 and -row.top_y * row.frame.width >= 65536:
			return {"error": "original IPNA top-skip WORD wrap is not implemented", "source": row.source, "submission_index": row.submission_index}
		# putipna copies literal payloads, including255; only skip commands are
		# transparent. Background putp mode0 intentionally uses another policy.
		var rgba: Dictionary = Indexed.rgba(row.frame, rgb6, false)
		if rgba.has("error"): return rgba
		pictures.append(Image.create_from_data(rgba.width, rgba.height, false, Image.FORMAT_RGBA8, rgba.value))
	var view = Control.new(); view.size = Vector2(320, clip_bottom); view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE; view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var submission_order: Array = []
	for index in range(ordered.size()):
		var row: Dictionary = ordered[index]
		var sprite = Sprite2D.new(); sprite.centered = false
		sprite.texture = ImageTexture.create_from_image(pictures[index]); sprite.position = Vector2(row.x, row.top_y)
		view.add_child(sprite); submission_order.append(row.submission_index)
	return {"value": view, "submission_order": submission_order, "rows": ordered}
