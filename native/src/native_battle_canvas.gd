# SPDX-License-Identifier: MIT
extends RefCounted
## Background geometry is independent of actor projection and HUD reservation.
const KEY = "pal.native.battle-canvas"
const SCHEMA = "pal.native.battle-canvas.v1"
const CAPABILITY = "graphics.battle-canvas.v1"
static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func for_encounter(content: Dictionary, encounter_id: String) -> Dictionary:
	for row in content.extensions.get(KEY,{}).get("encounters",[]):
		if row.encounter_id == encounter_id: return row
	return {}
static func default_profile() -> Dictionary:
	return {"fit":"cover","region":{"x":0,"y":0,"width":100,"height":100},"alignment":{"x":50,"y":50},"matte":"#18232bff"}
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Array = []
	for row in package.world.extensions[KEY].encounters:
		if row.encounter_id in seen or not package.world.get("encounters",[]).any(func(e):return e.id == row.encounter_id): return "duplicate or unknown battle canvas encounter"
		if row.region.x+row.region.width > 100 or row.region.y+row.region.height > 100: return "battle canvas region exceeds viewport"
		seen.append(row.encounter_id)
	return ""
static func placement(profile: Dictionary, bounds: Vector2, source_size: Vector2) -> Dictionary:
	var row: Dictionary = profile.region
	var region = Rect2(bounds*Vector2(row.x,row.y)/100.0,bounds*Vector2(row.width,row.height)/100.0)
	var source = Rect2(Vector2.ZERO,source_size)
	if bounds.x <= 0 or bounds.y <= 0 or source_size.x <= 0 or source_size.y <= 0: return {"canvas":region,"destination":Rect2(),"source":Rect2()}
	if profile.fit == "stretch": return {"canvas":region,"destination":region,"source":source}
	var factor: float = maxf(region.size.x/source_size.x,region.size.y/source_size.y) if profile.fit == "cover" else minf(region.size.x/source_size.x,region.size.y/source_size.y)
	var rendered: Vector2 = source_size*factor
	var origin: Vector2 = region.position+(region.size-rendered)*Vector2(profile.alignment.x,profile.alignment.y)/100.0
	if profile.fit == "cover":
		return {"canvas":region,"destination":region,"source":Rect2((region.position-origin)/factor,region.size/factor)}
	return {"canvas":region,"destination":Rect2(origin,rendered),"source":source}
