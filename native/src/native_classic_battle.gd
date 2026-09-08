# SPDX-License-Identifier: MIT
extends RefCounted
## Optional content-only projection; no actor, turn or damage authority.
const KEY = "pal.native.battle-layout"
const SCHEMA = "pal.native.battle-layout.v1"
const CAPABILITY = "graphics.battle-layout.v1"
const SCHEMA_V2 = "pal.native.battle-layout.v2"
const CAPABILITY_V2 = "graphics.battle-layout.v2"
const DREAM = "pal.dream-oblique.v1"
const SIZE = Vector2(320,200)

static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func definition(content: Dictionary) -> Dictionary: return content.extensions.get(KEY,{})
static func schema_id(content: Dictionary) -> String:
	var value = content.extensions.get(KEY,{})
	return str(value.get("schema",SCHEMA)) if value is Dictionary else SCHEMA
static func capability(content: Dictionary) -> String: return CAPABILITY_V2 if schema_id(content) == SCHEMA_V2 else CAPABILITY
static func is_dream(layout: Dictionary) -> bool: return layout.get("preset") == DREAM
static func party_issue(content: Dictionary, encounter_id: String, count: int) -> String:
	return "梦时空布局需要1至5名参战伙伴。" if is_dream(for_encounter(content,encounter_id)) and (count < 1 or count > 5) else ""
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
	var identity: String = schema_id(package.world)
	if identity not in [SCHEMA,SCHEMA_V2]: return "unknown battle layout version"
	var issue: String = package.schema.validate(identity,package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	value = definition(package.world)
	var layouts: Array = []; var encounters: Array = []
	for row in value.layouts:
		if row.id in layouts: return "duplicate battle layout"
		layouts.append(row.id)
	for row in value.encounters:
		if row.encounter_id in encounters or not package.world.get("encounters",[]).any(func(e): return e.id == row.encounter_id): return "duplicate or unknown layout encounter"
		if row.layout_id not in layouts: return "unknown layout reference"
		var dream: bool = is_dream(for_encounter(package.world,row.encounter_id))
		var enemies: Array = package.world.encounters.filter(func(e): return e.id == row.encounter_id)[0].enemies
		if dream and (enemies.size() < 1 or enemies.size() > 5): return "Dream presentation requires one to five enemies"
		if row.has("enemy_positions"):
			if not dream: return "explicit enemy positions require Dream presentation"
			var ids: Array = []
			for point in row.enemy_positions:
				if point.instance_id in ids or not enemies.any(func(e): return e.instance_id == point.instance_id): return "unknown or duplicate enemy position"
				ids.append(point.instance_id)
			if ids.size() != enemies.size(): return "enemy positions must cover all encounter instances"
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

static func dream_enemy_anchor(content: Dictionary, encounter_id: String, instance_id: String, index: int, count: int) -> Vector2:
	for binding in definition(content).get("encounters",[]):
		if binding.encounter_id == encounter_id:
			for point in binding.get("enemy_positions",[]):
				if point.instance_id == instance_id: return Vector2(point.x,point.y)
	# Named reference geometry. No legacy object IDs or resource loading in the runtime.
	var positions = {1:[Vector2(100,110)],2:[Vector2(70,130),Vector2(140,106)],
		3:[Vector2(70,140),Vector2(100,110),Vector2(160,100)],
		4:[Vector2(70,140),Vector2(100,110),Vector2(160,100),Vector2(50,100)],
		5:[Vector2(70,140),Vector2(100,110),Vector2(160,100),Vector2(30,110),Vector2(90,80)]}
	return positions[count][index]

static func dream_status_origin(index: int, count: int) -> Vector2:
	if index == 4: return Vector2(245,117)
	return Vector2((14 if count >= 4 else 91)+77*index,165)

static func dream_command_rect(symbol: String, count: int) -> Rect2:
	var points = {"attack":Vector2(27,140),"skills":Vector2(0,155),"cooperative":Vector2(54,155),"misc":Vector2(27,170)}
	return Rect2(points[symbol]-Vector2(0,47 if count >= 4 else 0),Vector2(30,30))

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
