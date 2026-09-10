# SPDX-License-Identifier: MIT
extends RefCounted
## Authored rectangles only. Existing widgets retain data, resources and input.
const KEY = "pal.native.hud-placement"
const SCHEMA = KEY + ".v1"
const CAPABILITY = "graphics.hud-placement.v1"
const SCHEMA_V2 = KEY + ".v2"
const CAPABILITY_V2 = "graphics.hud-placement.v2"
const Box = preload("res://src/native_box_layout.gd")
static func used(world: Dictionary) -> bool: return world.get("extensions",{}).has(KEY)
static func schema_id(world: Dictionary) -> String:
	var value: Variant = world.get("extensions",{}).get(KEY,{})
	return str(value.get("schema",SCHEMA)) if value is Dictionary else SCHEMA
static func capability(world: Dictionary) -> String: return CAPABILITY_V2 if schema_id(world)==SCHEMA_V2 else CAPABILITY
static func for_encounter(world: Dictionary, encounter: String) -> Dictionary:
	# HUD validation can ask for its profile before this component is validated.
	var component: Variant = world.get("extensions",{}).get(KEY,{})
	if not component is Dictionary or not component.get("encounters",[]) is Array: return {}
	for row in component.get("encounters",[]):
		if row is Dictionary and row.get("encounter_id","") == encounter: return row
	return {}
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var identity: String = schema_id(package.world)
	if identity not in [SCHEMA,SCHEMA_V2]: return "HUD placement: unknown schema version"
	var issue: String = package.schema.validate(identity,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Array = []
	var hud: Array = package.world.extensions.get("pal.native.battle-hud",{}).get("encounters",[])
	for row in package.world.extensions[KEY].encounters:
		if row.encounter_id in seen or not package.world.encounters.any(func(e):return e.id == row.encounter_id): return "HUD placement: duplicate or unknown encounter"
		if not hud.any(func(e):return e.encounter_id == row.encounter_id): return "HUD placement requires responsive battle HUD"
		seen.append(row.encounter_id)
		var layouts: Array = [row]; var ids: Array = []; var previous: Dictionary = {}
		for variant in row.get("variants",[]):
			if variant.id in ids: return "HUD placement: duplicate aspect variant identity"
			ids.append(variant.id)
			var ratio: Dictionary = variant.min_aspect
			if not previous.is_empty() and ratio.width*previous.height <= previous.width*ratio.height: return "HUD placement: aspect thresholds must increase strictly"
			previous = ratio; layouts.append(variant.layout)
		for layout in layouts:
			issue = validate_layout(layout)
			if not issue.is_empty(): return issue
	return ""
static func validate_layout(row: Dictionary) -> String:
	var counts: Array = []
	var rectangles: Array = [row.cards_region,row.content_region]
	for table in row.slots_by_count:
		if table.count in counts or table.slots.size() != table.count: return "HUD placement: duplicate count or incomplete seats"
		counts.append(table.count); rectangles.append_array(table.slots)
	for rect in rectangles:
		if rect.x+rect.width > 100 or rect.y+rect.height > 100: return "HUD placement rectangle exceeds parent"
	return ""
static func selected_variant(row: Dictionary, bounds: Vector2) -> Dictionary:
	var selected: Dictionary = {}
	for variant in row.get("variants",[]):
		if bounds.x*variant.min_aspect.height >= bounds.y*variant.min_aspect.width: selected = variant
	return selected
static func select_layout(row: Dictionary, bounds: Vector2) -> Dictionary:
	var selected: Dictionary = selected_variant(row,bounds)
	return row if selected.is_empty() else selected.layout
static func rectangle(value: Dictionary, parent: Rect2) -> Rect2:
	return Rect2(parent.position+parent.size*Vector2(value.x,value.y)/100,parent.size*Vector2(value.width,value.height)/100)
static func geometry(profile: Dictionary, layout: Dictionary, bounds: Vector2, count: int) -> Dictionary:
	var variant: Dictionary = selected_variant(profile,bounds)
	profile = profile if variant.is_empty() else variant.layout
	var stage = Rect2(Vector2.ZERO,bounds)
	var region: Rect2 = rectangle(profile.cards_region,stage)
	var content: Rect2 = rectangle(profile.content_region,stage)
	var margin: float = minf(layout.margin,minf(region.size.x,region.size.y)*.1)
	var cards: Array = []
	for table in profile.slots_by_count:
		if table.count == count:
			for rect in table.slots: cards.append(rectangle(rect,region))
			break
	if cards.is_empty():
		cards = Box.flow(count,region.grow(-margin),Vector2(layout.card_width,layout.card_height),layout.min_card_width,layout.gap,profile.max_columns)
	var command_side: float = minf(layout.command_size,minf(content.size.x,content.size.y)/4)
	var command_margin: float = minf(layout.margin,minf(content.size.x,content.size.y)*.05)
	var command_origin: Vector2 = content.position+Vector2(command_margin,maxf(command_margin,content.size.y-command_side*2-command_margin))
	var commands: Dictionary = {}
	for row in [["attack",Vector2(1,0)],["skills",Vector2(0,.5)],["cooperative",Vector2(2,.5)],["misc",Vector2(1,1)]]:
		commands[row[0]] = Rect2(command_origin+row[1]*command_side,Vector2.ONE*command_side)
	return {"cards":cards,"content":content,"region":region,"commands":commands,"effective_dock":"authored","variant_id":variant.get("id","default"),"variant_name":variant.get("display_name","默认布局")}
