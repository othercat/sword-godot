# SPDX-License-Identifier: MIT
extends RefCounted
## Authored layout, style and portrait bindings are separate from battle authority.
const KEY = "pal.native.battle-hud"
const SCHEMA = "pal.native.battle-hud.v1"
const CAPABILITY = "graphics.battle-hud.v1"
const Classic = preload("res://src/native_classic_battle.gd")
const Box = preload("res://src/native_box_layout.gd")
const Placement = preload("res://src/native_hud_placement.gd")
static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func definition(content: Dictionary) -> Dictionary: return content.extensions.get(KEY,{})
static func portraits(content: Dictionary) -> Array: return definition(content).get("portraits",[])
static func for_encounter(content: Dictionary, encounter_id: String) -> Dictionary:
	var value: Dictionary = definition(content)
	for binding in value.get("encounters",[]):
		if binding.encounter_id == encounter_id:
			var layout: Dictionary = {}; var style: Dictionary = {}
			for row in value.layouts:
				if row.id == binding.layout_id: layout = row
			for row in value.styles:
				if row.id == binding.style_id: style = row
			return {"layout":layout,"style":style,"placement":Placement.for_encounter(content,encounter_id)}
	return {}
static func portrait(content: Dictionary, definition_id: String) -> Dictionary:
	for row in portraits(content):
		if row.definition_id == definition_id: return row
	return Classic.portrait(content,definition_id)
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var value: Dictionary = definition(package.world)
	var layouts: Array = []; var styles: Array = []; var encounters: Array = []; var actors: Array = []
	for row in value.layouts:
		if row.id in layouts: return "duplicate HUD layout"
		if row.min_card_width > row.card_width: return "HUD minimum width exceeds preferred width"
		layouts.append(row.id)
	for row in value.styles:
		if row.id in styles: return "duplicate HUD style"
		styles.append(row.id)
	for binding in value.encounters:
		if binding.encounter_id in encounters or not package.world.get("encounters",[]).any(func(e): return e.id == binding.encounter_id): return "duplicate or unknown HUD encounter"
		if binding.layout_id not in layouts or binding.style_id not in styles: return "unknown HUD layout/style"
		if Classic.for_encounter(package.world,binding.encounter_id).is_empty(): return "HUD v1 requires an explicit battle presentation layout"
		for legacy in package.world.extensions.get("pal.native.battle-ui",{}).get("encounters",[]):
			if legacy.encounter_id == binding.encounter_id: return "remove legacy PNG skin before enabling responsive HUD"
		var profile: Dictionary = for_encounter(package.world,binding.encounter_id)
		if profile.style.portrait_size+8 > profile.layout.card_height or profile.style.portrait_size+90 > profile.layout.min_card_width or profile.style.font_size*4+12 > profile.layout.card_height: return "HUD style does not fit layout"
		encounters.append(binding.encounter_id)
	for row in portraits(package.world):
		if row.definition_id in actors or not package.index.actor_definitions.has(row.definition_id): return "duplicate or unknown HUD portrait actor"
		if package.index.assets.get(row.asset_id,{}).get("kind") != "texture": return "HUD portrait must reference texture"
		actors.append(row.definition_id)
	return ""

static func geometry(layout: Dictionary, bounds: Vector2, count: int, placement: Dictionary = {}) -> Dictionary:
	if not placement.is_empty(): return Placement.geometry(placement,layout,bounds,count)
	var margin: float = minf(layout.margin,minf(bounds.x,bounds.y)*.05)
	var gap: float = layout.gap
	var region = Rect2(Vector2.ZERO,bounds)
	var dock: String = layout.dock
	var columns: int = clampi(floori((bounds.x-margin*2+gap)/(layout.min_card_width+gap)),1,mini(maxi(1,count),layout.max_columns))
	var rows: int = ceili(float(count)/columns)
	if dock == "right" and layout.min_card_width > bounds.x*.35: dock = "bottom"
	if dock == "bottom":
		region.size.y = minf(bounds.y*.45,rows*layout.card_height+maxi(0,rows-1)*gap+margin*2)
		region.position.y = bounds.y-region.size.y
	else:
		region.size.x = minf(layout.card_width+margin*2,bounds.x*.38)
		region.position.x = bounds.x-region.size.x
	var inner: Rect2 = region.grow(-margin)
	var cards: Array = Box.flow(count,inner,Vector2(layout.card_width,layout.card_height),layout.min_card_width,gap,layout.max_columns if dock == "bottom" else 1)
	var content = Rect2(Vector2.ZERO,bounds)
	if layout.reserve_space:
		if dock == "bottom": content.size.y = region.position.y
		else: content.size.x = region.position.x
	var command_side: float = minf(layout.command_size,minf(content.size.x/4,content.size.y/4))
	var command_origin = Vector2(margin,maxf(margin,(region.position.y if dock == "bottom" else bounds.y)-command_side*2-margin))
	var commands: Dictionary = {}
	for row in [["attack",Vector2(1,0)],["skills",Vector2(0,.5)],["cooperative",Vector2(2,.5)],["misc",Vector2(1,1)]]:
		commands[row[0]] = Rect2(command_origin+row[1]*command_side,Vector2.ONE*command_side)
	return {"cards":cards,"content":content,"region":region,"commands":commands,"effective_dock":dock}
