# SPDX-License-Identifier: MIT
extends RefCounted
## Window fitting for the production display: an integer scale of the logical
## 320x200 frame with centred letterbox margins, and the inverse mapping from
## window coordinates back to logical frame coordinates. Pure computation; no
## logic ticks, no state access, no rendering side effects.
const LOGICAL_SIZE := Vector2i(320, 200)

## Integer scale with centred margins. The scale never drops below 1 and
## never becomes fractional, so pixels stay square at every window size.
static func fit(window_size: Vector2i) -> Dictionary:
	if window_size.x <= 0 or window_size.y <= 0:
		return {"error": "window size must be positive"}
	var scale: int = maxi(1, mini(window_size.x / LOGICAL_SIZE.x, window_size.y / LOGICAL_SIZE.y))
	var content := LOGICAL_SIZE * scale
	var offset := Vector2i((window_size.x - content.x) / 2, (window_size.y - content.y) / 2)
	return {"scale": scale, "content_size": content, "content_offset": offset,
		"window_size": window_size}

## Inverse mapping for click hit-testing: a window position inside the
## content rectangle becomes a logical frame position; anything in the
## letterbox margins is outside and refused by name.
static func map_to_content(window_position: Vector2i, fit: Dictionary) -> Dictionary:
	if not fit.has("content_offset") or not fit.has("scale"):
		return {"error": "map_to_content requires a computed fit"}
	var offset: Vector2i = fit.content_offset
	var content: Vector2i = fit.content_size
	var local := window_position - offset
	if local.x < 0 or local.y < 0 or local.x >= content.x or local.y >= content.y:
		return {"error": "window position is outside the displayed frame"}
	var scale: int = fit.scale
	return {"position": Vector2i(local.x / scale, local.y / scale)}
