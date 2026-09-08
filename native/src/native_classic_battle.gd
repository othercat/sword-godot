# SPDX-License-Identifier: MIT
extends RefCounted
## Optional content-only projection; no actor, turn or damage authority.
const KEY = "pal.native.battle-layout"
const SCHEMA = "pal.native.battle-layout.v1"
const CAPABILITY = "graphics.battle-layout.v1"
const SIZE = Vector2(320,200)

static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func definition(content: Dictionary) -> Dictionary: return content.extensions.get(KEY,{})
static func for_encounter(content: Dictionary, encounter_id: String) -> Dictionary:
	var component: Dictionary = definition(content)
	for binding in component.get("encounters",[]):
		if binding.encounter_id == encounter_id:
			for layout in component.layouts:
				if layout.id == binding.layout_id: return layout
	return {}
static func portrait(content: Dictionary, definition_id: String) -> Dictionary:
	for row in definition(content).get("portraits",[]):
		if row.definition_id == definition_id: return row
	return {}
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var value: Dictionary
	var issue: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	value = definition(package.world)
	var layouts: Array = []; var encounters: Array = []
	for row in value.layouts:
		if row.id in layouts: return "duplicate battle layout"
		layouts.append(row.id)
	for row in value.encounters:
		if row.encounter_id in encounters or not package.world.get("encounters",[]).any(func(e): return e.id == row.encounter_id): return "duplicate or unknown layout encounter"
		if row.layout_id not in layouts: return "unknown layout reference"
		encounters.append(row.encounter_id)
	var faces: Array = []
	for row in value.portraits:
		if row.definition_id in faces or not package.index.actor_definitions.has(row.definition_id): return "duplicate or unknown portrait actor"
		if package.index.assets.get(row.asset_id,{}).get("kind") != "texture": return "portrait must reference texture"
		faces.append(row.definition_id)
	return ""
static func stage_rect(bounds: Vector2) -> Rect2:
	var scale_value: float = minf(bounds.x / SIZE.x,bounds.y / SIZE.y)
	return Rect2((bounds - SIZE * scale_value) / 2.0,SIZE * scale_value)
static func party_anchor(index: int, count: int) -> Vector2:
	# Reference foot coordinates only; stable identity remains in battle.party.
	var positions = {
		1:[Vector2(240,170)], 2:[Vector2(200,176),Vector2(256,152)],
		3:[Vector2(180,180),Vector2(234,170),Vector2(270,146)],
		4:[Vector2(160,180),Vector2(217,175),Vector2(255,155),Vector2(285,135)],
		5:[Vector2(160,180),Vector2(210,175),Vector2(240,160),Vector2(265,145),Vector2(285,125)]}
	if positions.has(count): return positions[count][index]
	return Vector2(190+(index%4)*30,100+(index/4)*90.0/maxi(1,ceili(count/4.0)))

static func sprite_fit(extent: Rect2, foot: Vector2, requested_scale: float, side: int) -> float:
	# Constrain only an overflowing actor. A single union of all facing/action
	# frames prevents breathing scale during attacks; other actors keep their size.
	# Motion is in reference coordinates and is not affected by sprite scaling.
	var motion = Vector2(-18,-8) if side == 1 else Vector2(18,8)
	var safe = Rect2(Vector2(4,4),SIZE-Vector2(8,8))
	var factor: float = 1.0
	for axis in range(2):
		var lower: float = extent.position[axis]*requested_scale
		var upper: float = extent.end[axis]*requested_scale
		if lower < 0:
			factor = minf(factor,(foot[axis]+minf(0,motion[axis])-safe.position[axis])/-lower)
		if upper > 0:
			factor = minf(factor,(safe.end[axis]-foot[axis]-maxf(0,motion[axis]))/upper)
	return clampf(factor,0.0,1.0)
