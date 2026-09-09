# SPDX-License-Identifier: MIT
extends Control
## A separate CanvasItem keeps one presentation scope's filter local to its draw calls.
var paint: Callable

func _init(callback: Callable) -> void:
	paint = callback
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	paint.call(self)
