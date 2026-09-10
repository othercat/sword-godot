# SPDX-License-Identifier: MIT
extends Control
## One clipped, non-interactive draw item preserves authored order and filter.
const Card = preload("res://src/native_party_card.gd")
const Sampling = preload("res://src/native_sampling.gd")
const TextFit = preload("res://src/native_enemy_overlay.gd")
const TEXT_RESOLUTION = 4.0
var element: Dictionary = {}
var snapshot: Dictionary = {}
var package
var active: bool = false
var rendered_text: String = ""
var rendered_fill: Rect2 = Rect2()
var rendered_font_size: int = 0
func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE; clip_contents=true
func bind(next_package, next_element: Dictionary, card: Dictionary, selected: bool, fallback_filter: int) -> void:
	package=next_package; element=next_element; snapshot=card; active=selected
	var rect: Rect2 = Card.rectangle(element,card.panel_rect)
	position=rect.position; size=rect.size; visible=element.visible
	var widget: String = element.get("filter","inherit")
	var legacy: int = fallback_filter if widget=="inherit" else (CanvasItem.TEXTURE_FILTER_NEAREST if widget=="nearest" else CanvasItem.TEXTURE_FILTER_LINEAR)
	texture_filter=Sampling.resolve(package.world,"portrait" if element.kind=="portrait" else "hud",legacy,"" if widget=="inherit" else widget)
	queue_redraw()
func _image(binding: Variant, bounds: Rect2, tint: Color, fit: String) -> void:
	if binding==null: return
	var texture: Texture2D = package.textures[binding.asset_id]
	if fit=="contain":
		var extent: Vector2 = texture.get_size()*minf(bounds.size.x/texture.get_width(),bounds.size.y/texture.get_height())
		bounds=Rect2(bounds.get_center()-extent/2,extent)
	draw_texture_rect(texture,bounds,false,tint)
func _draw() -> void:
	rendered_text=""; rendered_fill=Rect2(); rendered_font_size=0
	if element.is_empty() or size.x<=0 or size.y<=0: return
	var bounds=Rect2(Vector2.ZERO,size)
	if element.kind=="panel":
		var style=StyleBoxFlat.new(); style.bg_color=Color(element.fill)
		style.border_color=Color(element.active_border if active else element.border)
		style.set_border_width_all(roundi(minf(size.x,size.y)*element.border_width/100))
		style.set_corner_radius_all(roundi(minf(size.x,size.y)*element.rounding/100))
		draw_style_box(style,bounds)
	if element.kind in ["panel","portrait","image"]:
		var binding: Variant = element.image
		if element.kind=="portrait" and binding==null and not snapshot.portrait_asset.is_empty(): binding={"asset_id":snapshot.portrait_asset}
		var tint=Color(element.tint)
		if element.kind=="portrait" and element.dim_on_death and snapshot.hp==0: tint*=Color(.45,.45,.45,1)
		_image(binding,bounds,tint,element.fit)
		if element.kind=="panel":
			var outline=StyleBoxFlat.new(); outline.bg_color=Color.TRANSPARENT
			outline.border_color=Color(element.active_border if active else element.border)
			outline.set_border_width_all(roundi(minf(size.x,size.y)*element.border_width/100))
			outline.set_corner_radius_all(roundi(minf(size.x,size.y)*element.rounding/100)); draw_style_box(outline,bounds)
	elif element.kind=="bar":
		draw_rect(bounds,Color(element.track)); _image(element.track_image,bounds,Color.WHITE,"stretch")
		var ratio: float = Card.fraction(element,snapshot)
		rendered_fill=Card.fill_rect(bounds,ratio,element.direction)
		if rendered_fill.has_area():
			draw_rect(rendered_fill,Color(element.fill))
			if element.fill_image!=null:
				var texture: Texture2D = package.textures[element.fill_image.asset_id]
				draw_texture_rect_region(texture,rendered_fill,Card.fill_rect(Rect2(Vector2.ZERO,texture.get_size()),ratio,element.direction))
	elif element.kind=="text":
		var font: Font = get_theme_font("font"); var local_size: Vector2 = size*TEXT_RESOLUTION
		var font_size: int = maxi(1,floori(local_size.y*element.font_height/100))
		while font_size>1 and font.get_height(font_size)>local_size.y: font_size-=1
		var value: String = Card.text(element,snapshot)
		if element.overflow=="shrink":
			while font_size>1 and font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>local_size.x: font_size-=1
		rendered_text=TextFit.short_text(font,value,local_size.x,font_size)
		rendered_font_size=font_size
		var align: int = {"left":HORIZONTAL_ALIGNMENT_LEFT,"center":HORIZONTAL_ALIGNMENT_CENTER,"right":HORIZONTAL_ALIGNMENT_RIGHT}[element.align]
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE/TEXT_RESOLUTION)
		draw_string(font,Vector2(0,(local_size.y-font.get_height(font_size))/2+font.get_ascent(font_size)),rendered_text,align,local_size.x,font_size,Color(element.color))
		draw_set_transform(Vector2.ZERO)
