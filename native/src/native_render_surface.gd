# SPDX-License-Identifier: MIT
extends TextureRect
const Sampling = preload("res://src/native_sampling.gd")

## Keep world coordinates independent of the root window's render pixel density.
## Input commands stay in the root GUI; only battle hover descriptions cross here.
var viewport: SubViewport
var battle_view: Control
signal logical_size_changed

func configure(target: SubViewport) -> void:
	viewport = target
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture = viewport.get_texture()
	viewport.size_2d_override_stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(sync_size)
	get_viewport().size_changed.connect(sync_size)
	sync_size.call_deferred()

func bind_content(content: Dictionary) -> void:
	texture_filter = Sampling.resolve(content, "surface")

func sync_size() -> void:
	if not is_instance_valid(viewport) or size.x < 2 or size.y < 2: return
	# CanvasItems scales the root GUI to output pixels, but a SubViewportContainer
	# with stretch=true only allocates its logical Control size. Own the buffer
	# here so high-resolution art is rasterized at the displayed pixel density.
	var transform: Transform2D = get_viewport().get_stretch_transform() * get_global_transform_with_canvas()
	var density = Vector2(transform.x.length(), transform.y.length())
	var logical = Vector2i(size)
	var pixels = Vector2i((size * density).ceil()).max(Vector2i(2, 2))
	var changed: bool = viewport.size_2d_override != logical
	viewport.size_2d_override = logical
	viewport.size = pixels
	if is_instance_valid(battle_view): battle_view.size = Vector2(logical); battle_view.queue_redraw()
	if changed: logical_size_changed.emit()

func _get_tooltip(at_position: Vector2) -> String:
	if is_instance_valid(battle_view) and battle_view.visible and size.x > 0 and size.y > 0:
		return battle_view._get_tooltip(at_position * Vector2(viewport.size_2d_override) / size)
	return ""
