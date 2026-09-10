# SPDX-License-Identifier: MIT
extends RefCounted
## Card-local presentation. Callers supply one displayed actor snapshot.
const KEY = "pal.native.party-card"
const SCHEMA = KEY+".v1"
const CAPABILITY = "graphics.party-card.v1"
static func used(content: Dictionary) -> bool: return content.get("extensions",{}).has(KEY)
static func for_encounter(content: Dictionary, encounter: String) -> Dictionary:
	var component: Variant = content.get("extensions",{}).get(KEY,{})
	if not component is Dictionary or not component.get("encounters",[]) is Array: return {}
	for row in component.get("encounters",[]):
		if row is Dictionary and row.get("encounter_id")==encounter: return row
	return {}
static func elements(profile: Dictionary, definition: String) -> Array:
	for row in profile.get("overrides",[]):
		if row.definition_id==definition: return row.elements
	return profile.get("elements",[])
static func element_lists(content: Dictionary) -> Array:
	var result: Array = []
	for row in content.get("extensions",{}).get(KEY,{}).get("encounters",[]):
		result.append(row.elements)
		for overridden in row.overrides: result.append(overridden.elements)
	return result
static func sprites(content: Dictionary) -> Array:
	var result: Array = []
	for rows in element_lists(content):
		for element in rows:
			for key in ["image","fill_image","track_image"]:
				if element.get(key)!=null: result.append(element[key])
	return result
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Array = []
	var hud: Array = package.world.extensions.get("pal.native.battle-hud",{}).get("encounters",[])
	for row in package.world.extensions[KEY].encounters:
		if row.encounter_id in seen or not package.world.encounters.any(func(e):return e.id==row.encounter_id): return "party card: duplicate or unknown encounter"
		if not hud.any(func(e):return e.encounter_id==row.encounter_id): return "party card requires responsive HUD"
		seen.append(row.encounter_id)
		var overridden: Array = []
		for item in row.overrides:
			if item.definition_id in overridden or not package.index.actor_definitions.has(item.definition_id): return "party card: duplicate or unknown character override"
			overridden.append(item.definition_id)
	for rows in element_lists(package.world):
		var ids: Array = []
		for element in rows:
			if element.id in ids: return "party card: duplicate element identity"
			ids.append(element.id)
			var rect: Dictionary = element.rect
			if rect.x+rect.width>100 or rect.y+rect.height>100: return "party card element exceeds parent card"
	for sprite in sprites(package.world):
		if package.index.assets.get(sprite.asset_id,{}).get("kind")!="texture": return "party card image must reference texture"
	return ""
static func rectangle(element: Dictionary, card: Rect2) -> Rect2:
	var rect: Dictionary = element.rect
	return Rect2(card.position+card.size*Vector2(rect.x,rect.y)/100,card.size*Vector2(rect.width,rect.height)/100)
static func fraction(element: Dictionary, card: Dictionary) -> float:
	var maximum: int = int(card.stats["max_"+element.source])
	return 0.0 if maximum<=0 else clampf(float(card[element.source])/maximum,0.0,1.0)
static func fill_rect(bounds: Rect2, ratio: float, direction: String) -> Rect2:
	var result: Rect2 = bounds; ratio=clampf(ratio,0.0,1.0)
	if direction in ["left-to-right","right-to-left"]:
		result.size.x*=ratio
		if direction=="right-to-left": result.position.x=bounds.end.x-result.size.x
	else:
		result.size.y*=ratio
		if direction=="bottom-to-top": result.position.y=bounds.end.y-result.size.y
	return result
static func text(element: Dictionary, card: Dictionary) -> String:
	if element.source in ["name","literal"]:
		return str(card.name if element.source=="name" else element.text).replace("\r"," ").replace("\n"," ")
	var value: int = int(card[element.source]); var maximum: int = int(card.stats["max_"+element.source])
	if element.format=="percent": return "%d%%" % floori(fraction(element,card)*100)
	if element.format=="current": return str(value)
	var numeric: String = "%d / %d" % [value,maximum]
	return ((element.label+" " if not element.label.is_empty() else "")+numeric).replace("\r"," ").replace("\n"," ") if element.format=="labeled" else numeric
