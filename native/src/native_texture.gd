# SPDX-License-Identifier: MIT
extends RefCounted

static func fix_transparent_edges(image: Image) -> void:
	if image.get_format() != Image.FORMAT_RGBA8 or image.detect_alpha() == Image.ALPHA_NONE:
		return
	# PNG uses straight alpha. Invisible white/magenta can bleed into filtered
	# edges. Godot also adjusts some low-alpha RGB, so restore every nonzero-alpha
	# source pixel with its native mask blit. No visible color/alpha is quantized.
	var original: Image = image.duplicate()
	image.fix_alpha_edges()
	image.blit_rect_mask(original, original, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
