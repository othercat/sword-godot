# SPDX-License-Identifier: MIT
extends RefCounted
## One optional HP widget; caller supplies displayed values, never final-state guesses.
const KEY = "pal.native.enemy-overlay"
const SCHEMA = KEY+".v1"
const CAPABILITY = "graphics.enemy-overlay.v1"
const TEXT_RESOLUTION = 4.0
const Classic = preload("res://src/native_classic_battle.gd")
static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func for_encounter(content: Dictionary, id: String) -> Dictionary:
	for row in content.extensions.get(KEY,{}).get("encounters",[]):
		if row.encounter_id==id:return row
	return {}
static func validate_content(package) -> String:
	if not used(package.world):return ""
	var issue: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not issue.is_empty():return issue
	var seen: Array = []
	for row in package.world.extensions[KEY].encounters:
		if row.encounter_id in seen or not package.world.encounters.any(func(e):return e.id==row.encounter_id):return "duplicate or unknown enemy overlay encounter"
		if Classic.for_encounter(package.world,row.encounter_id).is_empty():return "enemy overlay requires explicit oblique presentation"
		seen.append(row.encounter_id)
		var encounter: Dictionary = package.world.encounters.filter(func(e):return e.id==row.encounter_id)[0]
		var overridden: Array = []
		for item in row.get("overrides",[]):
			if item.instance_id in overridden or not encounter.enemies.any(func(e):return e.instance_id==item.instance_id):return "duplicate or unknown enemy overlay override"
			overridden.append(item.instance_id)
	return ""
static func for_actor(profile: Dictionary, id: String) -> Dictionary:
	for item in profile.get("overrides",[]):
		if item.instance_id==id:
			var result: Dictionary = profile.duplicate(true)
			result.offset=item.offset;result.bar_width=item.bar_width;return result
	return profile
static func place(rect: Rect2, bounds: Rect2, enabled: bool) -> Dictionary:
	if not enabled or not rect.has_area():return {"rect":rect,"fit":1.0}
	var factor: float = minf(1.0,minf(bounds.size.x/rect.size.x,bounds.size.y/rect.size.y))
	var size: Vector2 = rect.size*factor
	return {"rect":Rect2(rect.position.clamp(bounds.position,bounds.end-size),size),"fit":factor}
static func metrics(profile: Dictionary, font: Font = null) -> Dictionary:
	var line: float = float(profile.font_size) if font==null else font.get_height(int(profile.font_size*TEXT_RESOLUTION))/TEXT_RESOLUTION
	var ascent: float = float(profile.font_size) if font==null else font.get_ascent(int(profile.font_size*TEXT_RESOLUTION))/TEXT_RESOLUTION
	var lines: int = (1 if profile.value_format!="none" else 0)+(1 if profile.show_name else 0)
	return {"line":line+2.0,"ascent":ascent+1.0,"height":profile.bar_height+2.0+lines*(line+2.0),"lines":lines}
static func measure(profile: Dictionary, visual: Rect2, font: Font = null) -> Rect2:
	if profile.is_empty():return Rect2()
	var height: float = metrics(profile,font).height
	var point=Vector2(visual.get_center().x-profile.bar_width/2.0,visual.position.y-height if profile.placement=="above-body" else visual.end.y)
	return Rect2(point+Vector2(profile.offset.x,profile.offset.y),Vector2(profile.bar_width,height))
static func short_text(font: Font, value: String, width: float, size: int) -> String:
	if font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=width:return value
	while value.length()>0:
		value=value.left(value.length()-1)
		if font.get_string_size(value+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=width:return value+"…"
	return ""
static func paint(canvas: CanvasItem, font: Font, profile: Dictionary, rect: Rect2, hp: int, maximum: int, actor_name: String, factor: float) -> void:
	if not rect.has_area():return
	# Scale the same measured local layout. Rounding the final font separately
	# would make a clamped two-line widget paint outside its declared rectangle.
	var font_size: int = int(profile.font_size*TEXT_RESOLUTION)
	var geometry: Dictionary = metrics(profile,font)
	var local_size: Vector2 = rect.size/factor*TEXT_RESOLUTION
	canvas.draw_set_transform(rect.position,0,Vector2.ONE*factor/TEXT_RESOLUTION)
	var y: float = 0.0
	var values: Array = []
	if profile.show_name:values.append(actor_name)
	if profile.value_format!="none":values.append(str(hp) if profile.value_format=="current" else "%d/%d" % [hp,maximum])
	for value in values:
		var text: String = short_text(font,value,local_size.x,font_size)
		canvas.draw_string(font,Vector2(0,y+geometry.ascent*TEXT_RESOLUTION),text,HORIZONTAL_ALIGNMENT_CENTER,local_size.x,font_size,Color(profile.colors.text))
		y+=geometry.line*TEXT_RESOLUTION
	var bar=Rect2(0,y,local_size.x,(profile.bar_height+2.0)*TEXT_RESOLUTION)
	canvas.draw_rect(bar,Color(profile.colors.border))
	var inside=bar.grow(-TEXT_RESOLUTION)
	if inside.has_area():
		canvas.draw_rect(inside,Color(profile.colors.empty))
		inside.size.x*=clampf(float(hp)/maxi(1,maximum),0,1)
		canvas.draw_rect(inside,Color(profile.colors.hp))
	canvas.draw_set_transform(Vector2.ZERO)
