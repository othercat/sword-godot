# SPDX-License-Identifier: MIT
extends RefCounted
## Production window host for the pal98 scene display: one real 320x200
## content viewport presented through an integer-fit letterbox on the actual
## window, with the inverse click mapping back to logical frame coordinates.
## Presentation failures are named and never reported as the previous
## frame's success.
const WindowScale = preload("res://src/native_pal98_window_scale.gd")

var error: String = ""
var window: Window
var stage: SubViewport
var frame_view: TextureRect
var fit: Dictionary = {}
var _display

func bind_host(host_window: Window, content_parent: Node, game, display, page_view: TextureRect = null) -> bool:
	error = ""; window = null; stage = null; frame_view = null; fit = {}; _display = null
	if host_window == null or not host_window.is_inside_tree():
		error = "scene window host requires a real window in the tree"; return false
	if content_parent == null or not content_parent.is_inside_tree():
		error = "scene window host requires an in-tree content parent"; return false
	if DisplayServer.get_name() == "headless":
		error = "scene window host requires a non-headless display server"; return false
	if game == null or game.state.is_empty():
		error = "scene window host requires an opened game with a resting state"; return false
	if display == null or not display.bind(game):
		error = display.error if display != null else "scene window host requires the display owner"; return false
	var stage_view := SubViewport.new()
	stage_view.size = Vector2i(320, 200)
	stage_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	content_parent.add_child(stage_view)
	var view := TextureRect.new()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.texture = stage_view.get_texture()
	content_parent.add_child(view)
	if not display.bind_display_target(stage_view, view if page_view == null else page_view):
		error = display.error
		stage_view.queue_free(); view.queue_free()
		return false
	window = host_window; stage = stage_view; frame_view = view; _display = display
	var laid: Dictionary = apply_fit()
	if laid.has("error"): return false
	return true

## Re-fit the presentation to the current window size: integer scale, centred
## letterbox, and the content view laid out exactly on that rectangle.
func apply_fit() -> Dictionary:
	if window == null: return {"error": "scene window host is not bound"}
	var computed: Dictionary = WindowScale.fit(window.size)
	if computed.has("error"): error = str(computed.error); return computed
	fit = computed.duplicate(true)
	if frame_view != null:
		frame_view.position = Vector2(computed.content_offset)
		frame_view.size = Vector2(computed.content_size)
	error = ""
	return fit

func window_to_content(window_position: Vector2i) -> Dictionary:
	var mapped: Dictionary = WindowScale.map_to_content(window_position, fit)
	if mapped.has("error"): error = str(mapped.error)
	return mapped

func present_frame() -> Dictionary:
	if _display == null: return {"error": "scene window host is not bound"}
	var presented: Dictionary = _display.present()
	if presented.has("error"): error = str(presented.error)
	return presented

func tick_frame(key_levels: PackedInt32Array, timer_tick: bool = false) -> Dictionary:
	if _display == null: return {"error": "scene window host is not bound"}
	return _display.tick_presented(key_levels, timer_tick)

func republish_frame() -> Dictionary:
	if _display == null: return {"error": "scene window host is not bound"}
	var republished: Dictionary = _display.republish()
	if republished.has("error"): error = str(republished.error)
	return republished
