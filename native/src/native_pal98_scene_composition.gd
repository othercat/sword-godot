# SPDX-License-Identifier: MIT
extends RefCounted
## Builds one GPU view from explicit original current state and loaded resources.
## Does not initialize a game, reload sprites, advance scripts or choose defaults.
const Requests = preload("res://src/native_pal98_scene_sprite_requests.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
const Queue = preload("res://src/native_pal98_depth_queue.gd")

static func build(owner: String, records, storage, event_state: Dictionary, cache, caller: Dictionary) -> Dictionary:
	for field in ["map_id", "palette_index", "palette_variant", "map_mode", "clip_bottom"]:
		if not Requests._i2(caller.get(field)): return {"error": "scene composition requires known signed16 " + field}
	if caller.map_mode != 0: return {"error": "original nonzero DrawMap mode owner is not implemented"}
	if caller.clip_bottom < 0 or caller.clip_bottom > 200: return {"error": "scene depth clip requires0..200"}
	if records == null or cache == null or cache.source().is_empty(): return {"error": "scene requires addressed graphics and loaded sprite cache"}
	if records.metadata().get("fingerprint") != cache.source().graphics_fingerprint: return {"error": "scene graphics/cache fingerprint mismatch"}
	var requests: Dictionary = Requests.collect(owner, storage, event_state, caller)
	if requests.has("error"): return requests
	var resolved: Dictionary = cache.resolve_requests(storage, event_state, caller.party_records, requests.value)
	if resolved.has("error"): return resolved
	var background = Background.new(); var marks = Occlusion.new(); var queue = Queue.new()
	if not background.load_source(records, caller.map_id, caller.palette_index, caller.palette_variant): return {"error": background.error}
	if not marks.load_source(records, caller.map_id): return {"error": marks.error}
	var rows: Array = []
	for selected in resolved.value:
		var request: Dictionary = selected.request
		var row: Dictionary = Queue.row_for_sprite(request.kind, request.screen_x, request.screen_y, request.layer_base, selected.frame, selected.source)
		if row.has("error"): return row
		rows.append(row.value)
		var mark: Dictionary = marks.mark_sprite(request.screen_x, request.screen_y, caller.viewport_x, caller.viewport_y,
			request.layer_base, selected.frame.width, selected.frame.height, caller.map_mode)
		if mark.has("error"): return mark
	var map_rows: Dictionary = marks.queue_rows(caller.viewport_x, caller.viewport_y)
	if map_rows.has("error"): return map_rows
	rows.append_array(map_rows.value)
	if not queue.load_rows(rows): return {"error": queue.error}
	var cell: Dictionary = Occlusion.world_to_cell(caller.viewport_x, caller.viewport_y).value
	var palette: Dictionary = records.palette(caller.palette_index, caller.palette_variant)
	if palette.has("error"): return palette
	var depth_view: Dictionary = queue.make_view(palette.value, caller.clip_bottom)
	if depth_view.has("error"): return depth_view
	var map_view: Dictionary = background.make_view(cell.x, cell.y, cell.half)
	if map_view.has("error"): depth_view.value.free(); return map_view
	var view = Control.new(); view.size = Vector2(320,200); view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE; view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var underlay = ColorRect.new(); underlay.size = view.size; underlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underlay.color = Color8(palette.value[0] * 4, palette.value[1] * 4, palette.value[2] * 4)
	view.add_child(underlay); view.add_child(map_view.value); view.add_child(depth_view.value)
	return {"value":view, "owner":owner, "requests":requests.value, "flags":marks.marks(),
		"sprite_rows":resolved.value.size(), "map_rows":map_rows.value.size(), "background_cell":cell,
		"submission_order":depth_view.submission_order, "source":background.source(), "sprite_source":cache.source()}
