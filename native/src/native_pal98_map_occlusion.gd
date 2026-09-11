# SPDX-License-Identifier: MIT
extends RefCounted
## Explicit original map marks and map-owned depth rows. No session/caller state.
const Indexed = preload("res://src/native_pal98_indexed_image.gd")
const Queue = preload("res://src/native_pal98_depth_queue.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
var error: String = ""
var _map: PackedByteArray
var _gop: PackedByteArray
var _flags: PackedByteArray
var _source: Dictionary = {}

func load_source(records, map_index: int) -> bool:
	if records == null: error = "addressed graphics reader required"; return false
	var map: Dictionary = records.decoded_chunk("MAP.MKF", map_index)
	var gop: Dictionary = records.group("GOP.MKF", map_index)
	for selected in [map, gop]:
		if selected.has("error"): error = selected.error; return false
	if map.value.size() != 65536: error = "original map must contain65536 decoded bytes"; return false
	_map = map.value.duplicate(); _gop = gop.value.duplicate()
	_source = {"map": map.source.duplicate(true), "gop": gop.source.duplicate(true)}
	clear_marks(); error = ""; return true

func source() -> Dictionary:
	return _source.duplicate(true)

func clear_marks() -> void:
	_flags.resize(16384); _flags.fill(0)

func marks() -> PackedByteArray:
	return _flags.duplicate()

func replace_marks(flags: PackedByteArray) -> bool:
	if _map.size() != 65536: error = "original map occlusion not loaded"; return false
	if flags.size() != 16384: error = "original map flags require16384 bytes"; return false
	_flags = flags.duplicate(); error = ""; return true

static func world_to_cell(world_x: int, world_y: int) -> Dictionary:
	if world_x < -32768 or world_x > 32767 or world_y < -32768 or world_y > 32767:
		return {"error": "exrij input requires signed16 coordinates"}
	if world_x < 0 or world_y < 0: return {"value": {"x": 0, "y": 0, "half": 0}}
	var column: int = world_x >> 5; var row: int = world_y >> 4
	var u: int = world_x & 31; var v: int = world_y & 15
	var diagonal_sum: int = u + 2 * v; var other_sum: int = 32 - u + 2 * v
	var half: int = 0
	if diagonal_sum >= 48: column += 1; row += 1
	elif diagonal_sum >= 16:
		if other_sum < 16: column += 1
		elif other_sum >= 48: row += 1
		else: half = 1
	return {"value": {"x": mini(column, 63), "y": mini(row, 127), "half": half}}

func mark_cells(cutoff_y: int, cells: Array) -> Dictionary:
	if _map.size() != 65536: return {"error": "original map occlusion not loaded"}
	if cutoff_y < -32768 or cutoff_y > 32767: return {"error": "exbb cutoff requires signed16"}
	if cells.size() > 1048576: return {"error": "map mark request budget"}
	var candidate: PackedByteArray = _flags.duplicate(); var changed: int = 0
	for cell in cells:
		if not cell is Dictionary or not cell.get("half") is int or cell.half not in [0, 1]: return {"error": "map mark requires explicit half0/1"}
		for axis in ["x", "y"]:
			if not cell.get(axis) is int or cell[axis] < -32768 or cell[axis] > 32767:
				return {"error": "map mark requires signed16 " + axis}
		var index: int = (cell.y * 128 + cell.x * 2 + cell.half) & 65535
		# Original flags base receives this zero-extended WORD index. Only the
		# MAP byte address wraps again; flags do not wrap to their16KiB extent.
		if index >= 16384:
			return {"error": "original exbb flag address outside owned16384 bytes", "flag_offset": index, "cell": cell.duplicate(true), "source": source()}
		var map_offset: int = index * 4 & 65535; var before: int = candidate[index]
		for layer in range(2):
			var height: int = (_map.decode_u16(map_offset + layer * 2) >> 8) & 15
			if height != 0 and Queue.signed16((cell.y + height) * 16 + cell.half * 8 + 8) >= cutoff_y:
				candidate[index] |= 1 << layer
		if candidate[index] != before: changed += 1
	_flags = candidate
	return {"value": changed, "requests": cells.size(), "source": source()}

func mark_sprite(screen_x: int, screen_y: int, viewport_x: int, viewport_y: int, layer_base: int, width: int, height: int, skip_map_value: int) -> Dictionary:
	if _map.size() != 65536: return {"error": "original map occlusion not loaded"}
	for value in [screen_x, screen_y, viewport_x, viewport_y, layer_base, skip_map_value]:
		if value < -32768 or value > 32767: return {"error": "T163 map caller requires signed16 values"}
	if width < 1 or height < 1 or width > 8192 or height > 8192: return {"error": "T163 decoded sprite dimensions required"}
	if skip_map_value != 0 or layer_base >= 72: return {"value": 0, "requests": 0, "skipped": true}
	var world_x: int = screen_x + viewport_x; var cutoff: int = screen_y + viewport_y
	if world_x < -32768 or world_x > 32767 or cutoff < -32768 or cutoff > 32767:
		return {"error": "T163 world coordinate signed16 overflow"}
	var center: Dictionary = world_to_cell(world_x, cutoff).value
	var height_cells: int = (height + 15) >> 4; var half_width: int = width >> 6
	var cells: Array = []
	# T163 expands the full sprite dimensions around its original foot. It has
	# no preliminary screen clipping and makes five marks per inclusive cell.
	for row in range(center.y - height_cells, center.y + 1):
		for column in range(center.x - half_width, center.x + half_width + 1):
			cells.append({"x": column, "y": row, "half": center.half})
			cells.append({"x": column - 1, "y": row, "half": center.half})
			cells.append({"x": column + 1, "y": row, "half": center.half})
			if center.half == 0:
				cells.append({"x": column, "y": row, "half": 1})
				cells.append({"x": column - 1, "y": row, "half": 1})
			else:
				cells.append({"x": column + 1, "y": row + 1, "half": 0})
				cells.append({"x": column, "y": row + 1, "half": 0})
	var marked: Dictionary = mark_cells(cutoff, cells)
	if not marked.has("error"): marked.center = center; marked.height_cells = height_cells; marked.half_width_cells = half_width
	return marked

func queue_rows(viewport_x: int, viewport_y: int) -> Dictionary:
	if _map.size() != 65536: return {"error": "original map occlusion not loaded"}
	if viewport_x < -32768 or viewport_x > 32767 or viewport_y < -32768 or viewport_y > 32767:
		return {"error": "exmap viewport requires signed16 coordinates"}
	var rows: Array = []; var frames: Dictionary = {}; var pixels: int = 0
	# exmap decrements its remaining count before processing a set flag: the
	# final16383 half-cell is not emitted, even when its flags are nonzero.
	for at in range(16383):
		var marked: int = _flags[at] & 3
		if marked == 0: continue
		var map_y: int = at >> 7; var map_x: int = (at >> 1) & 63; var half: int = at & 1
		for layer_index in range(2):
			if (marked & (1 << layer_index)) == 0: continue
			var word: int = _map.decode_u16(at * 4 + layer_index * 2)
			var descriptor: Dictionary = Background.descriptor(word, layer_index == 1)
			if layer_index == 1 and not descriptor.present:
				# Original exmap wraps (index0-1)*2 in BX and reads GOP+65534.
				# Background vmap's absent-upper rule does not apply to this path.
				return {"error": "marked upper index0 uses unsupported original GOP directory wrap", "source": source(), "map_byte_offset": at * 4 + 2}
			var frame_index: int = descriptor.frame
			if not frames.has(frame_index):
				var decoded: Dictionary = Indexed.frame(_gop, frame_index)
				if decoded.has("error"): decoded.source = source(); decoded.map_byte_offset = at * 4 + layer_index * 2; return decoded
				# A frame decoder also reports the unused bytes before the next
				# pointer. Aliased directory entries must not multiply those tails
				# outside the pixel budget; retain only the two rendering planes.
				frames[frame_index] = {"width": decoded.value.width, "height": decoded.value.height,
					"indices": decoded.value.indices, "coverage": decoded.value.coverage}
			var frame: Dictionary = frames[frame_index]
			pixels += frame.width * frame.height
			if pixels > Queue.PIXEL_BUDGET: return {"error": "map depth row pixel budget", "source": source()}
			if rows.size() >= 255: return {"error": "map rows exceed original ntre safe count", "source": source()}
			var layer: int = descriptor.height * 8 + layer_index
			rows.append({"x": Queue.signed16(map_x * 32 + half * 16 - viewport_x - 16),
				"sort_y": Queue.signed16(map_y * 16 + half * 8 - viewport_y + 7 + layer), "layer_offset": layer,
				"frame": frame.duplicate(true), "source": {"map": _source.map.duplicate(true), "gop": _source.gop.duplicate(true),
					"map_byte_offset": at * 4 + layer_index * 2, "half_cell": at, "layer": layer_index, "descriptor": word, "frame": frame_index}})
	return {"value": rows, "source": source(), "terminal_mark": _flags[16383]}
