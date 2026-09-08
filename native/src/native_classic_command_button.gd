# SPDX-License-Identifier: MIT
extends Button
## Original vector ornaments, not extracted Legacy menu graphics. Button retains
## its normal keyboard, focus, disabled and accessibility semantics.
var symbol: String = ""
var reference_size: int = 68
var skin: Dictionary = {}

func skin_state() -> String:
	if disabled: return "disabled"
	return "focus" if has_focus() or is_hovered() or is_pressed() else "normal"

func _ready() -> void:
	custom_minimum_size = Vector2(reference_size, reference_size)
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		add_theme_color_override(color, Color.TRANSPARENT)
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up]: event.connect(queue_redraw)

func _draw() -> void:
	var state: String = skin_state()
	var key: String = "command." + symbol + "." + state
	var texture: Texture2D = skin.get(key, skin.get("command." + symbol + ".normal"))
	if texture != null:
		var fallback: bool = not skin.has(key)
		draw_texture_rect(texture,Rect2(Vector2.ZERO,size),false,Color(.45,.45,.45) if fallback and disabled else Color.WHITE)
		if fallback and state == "focus": draw_rect(Rect2(Vector2.ONE,size-Vector2(2,2)),Color("ead296"),false,1)
		return
	var center = size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0 - 3.0
	var tint = Color("d9b978") if has_focus() or is_hovered() else Color("6ca9a4")
	if disabled: tint = Color("62706d")
	var polygon = PackedVector2Array()
	for i in range(8): polygon.append(center + Vector2.from_angle(PI/8.0 + i*TAU/8.0) * radius)
	draw_colored_polygon(polygon, Color("132827") if not is_pressed() else Color("35443a"))
	polygon.append(polygon[0]); draw_polyline(polygon, tint, 1.5, true)
	for i in range(8):
		var direction = Vector2.from_angle(i*TAU/8.0)
		var tangent = direction.orthogonal()
		for ring in [0.76, 0.85]:
			var at = center + direction * radius * ring
			draw_line(at-tangent*3.5, at+tangent*3.5, tint.darkened(0.2), 1.0, true)
	var font = get_theme_font("font")
	if reference_size == 30:
		var glyph: String = {"attack":"攻","skills":"术","cooperative":"合","misc":"杂"}.get(symbol, "")
		draw_string(font,center+Vector2(-6,4),glyph,HORIZONTAL_ALIGNMENT_LEFT,14,12,tint)
		return
	var mark: String = {"attack":"剑", "skills":"术", "items":"药", "misc":"策"}.get(symbol, "")
	var label = tr(text)
	draw_string(font, center + Vector2(-font.get_string_size(mark,HORIZONTAL_ALIGNMENT_LEFT,-1,22).x/2.0,1), mark,HORIZONTAL_ALIGNMENT_LEFT,-1,22,tint)
	draw_string(font, center + Vector2(-font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x/2.0,17),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,tint)
