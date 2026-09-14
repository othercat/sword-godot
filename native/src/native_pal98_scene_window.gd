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
var _generation := 0
var _presenting := false

## Only this host's nodes and signals are released. A pending presentation
## must observe the changed generation before publishing a completion.
func unbind() -> void:
	_generation += 1; _presenting = false
	if is_instance_valid(window):
		if window.size_changed.is_connected(_on_size_changed): window.size_changed.disconnect(_on_size_changed)
		if window.tree_exiting.is_connected(unbind): window.tree_exiting.disconnect(unbind)
	if _display != null and _display.has_method("unbind_display_target"):
		_display.unbind_display_target()
	for owned in [frame_view, stage]:
		if is_instance_valid(owned):
			if owned.get_parent() != null: owned.get_parent().remove_child(owned)
			owned.queue_free()
	window = null; stage = null; frame_view = null; fit = {}; _display = null

func _on_size_changed() -> void:
	apply_fit()

func bind_host(host_window: Window, content_parent: Node, game, display, page_view: TextureRect = null) -> bool:
	unbind(); error = ""
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
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture = stage_view.get_texture()
	content_parent.add_child(view)
	if not display.bind_display_target(stage_view, view if page_view == null else page_view):
		error = display.error
		content_parent.remove_child(stage_view); content_parent.remove_child(view)
		stage_view.queue_free(); view.queue_free()
		return false
	window = host_window; stage = stage_view; frame_view = view; _display = display
	window.min_size = Vector2i(maxi(window.min_size.x, 320), maxi(window.min_size.y, 200))
	window.size_changed.connect(_on_size_changed)
	window.tree_exiting.connect(unbind)
	var laid: Dictionary = apply_fit()
	if laid.has("error"): unbind(); return false
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
	if _presenting: return {"error": "scene window presentation is pending"}
	var presented: Dictionary = _display.present()
	if presented.has("error"): error = str(presented.error)
	return presented

func tick_frame(key_levels: PackedInt32Array, timer_tick: bool = false) -> Dictionary:
	if _display == null: return {"error": "scene window host is not bound"}
	if _presenting: return {"error": "scene window presentation is pending"}
	var generation := _generation
	_presenting = true
	var result: Dictionary = await _display.tick_presented(key_levels, timer_tick)
	if generation != _generation: return {"error": "stale scene window presentation"}
	_presenting = false
	if result.has("error"): error = str(result.error)
	return result

## The production dialogue surface binding, delegated to the display owner.
func bind_dialogue_surface(dialogue_surface, font_owner, text_encoding: String) -> bool:
	if _display == null: error = "scene window host is not bound"; return false
	var bound: bool = _display.bind_dialogue_surface(dialogue_surface, font_owner, text_encoding)
	if not bound: error = _display.error
	return bound

## Publishes the parked presentation page onto the window; the app loop calls
## this after a tick reports awaiting_presentation, exactly once per beat.
func present_pending_page() -> Dictionary:
	if _display == null: return {"error": "scene window host is not bound"}
	if _presenting: return {"error": "scene window presentation is pending"}
	var generation := _generation
	_presenting = true
	var page: Dictionary = await _display.present_dialogue_page()
	if generation != _generation: return {"error": "stale scene window presentation"}
	_presenting = false
	if page.has("error"): error = str(page.error)
	return page

func republish_frame() -> Dictionary:
	if _display == null: return {"error": "scene window host is not bound"}
	if _presenting: return {"error": "scene window presentation is pending"}
	var republished: Dictionary = _display.republish()
	if republished.has("error"): error = str(republished.error)
	return republished
