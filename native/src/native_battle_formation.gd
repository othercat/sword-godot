# SPDX-License-Identifier: MIT
extends RefCounted
## Disposable geometry only. Points are percentages of each authored side region.
const KEY = "pal.native.battle-formation"
const SCHEMA = KEY+".v1"
const CAPABILITY = "graphics.battle-formation.v1"
const Classic = preload("res://src/native_classic_battle.gd")
static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func for_encounter(content: Dictionary, id: String) -> Dictionary:
	for row in content.extensions.get(KEY,{}).get("encounters",[]):
		if row.encounter_id == id: return row
	return {}
static func validate_content(package) -> String:
	if not used(package.world): return ""
	var error: String = package.schema.validate(SCHEMA,package.world.extensions[KEY])
	if not error.is_empty(): return error
	var seen: Array = []
	for row in package.world.extensions[KEY].encounters:
		var encounter: Array = package.world.encounters.filter(func(e):return e.id == row.encounter_id)
		if encounter.size()!=1 or row.encounter_id in seen: return "duplicate or unknown formation encounter"
		seen.append(row.encounter_id)
		if Classic.for_encounter(package.world,row.encounter_id).is_empty(): return "formation requires explicit oblique presentation"
		for side in ["party","enemy"]:
			var r: Dictionary = row[side].region
			if r.x+r.width>100 or r.y+r.height>100: return "formation region exceeds actor canvas"
		var counts: Array = []
		for slots in row.party.get("slots_by_count",[]):
			if slots.count in counts or slots.slots.size()!=slots.count: return "duplicate or incomplete party count layout"
			counts.append(slots.count)
		if row.enemy.has("positions"):
			var ids: Array = []
			for point in row.enemy.positions:
				if point.instance_id in ids or not encounter[0].enemies.any(func(e):return e.instance_id==point.instance_id): return "unknown or duplicate formation enemy"
				ids.append(point.instance_id)
			if ids.size()!=encounter[0].enemies.size(): return "formation points must cover all enemy instances"
	return ""
static func anchor_seed(group: Dictionary, id: String, index: int, count: int, side: int) -> Vector2:
	if side==0:
		for row in group.get("positions",[]):
			if row.instance_id==id:return Vector2(row.x,row.y)/100.0
	else:
		for row in group.get("slots_by_count",[]):
			if row.count==count:return Vector2(row.slots[index].x,row.slots[index].y)/100.0
	if count==1:return Vector2(.5,.65)
	var t: float = float(index)/float(count-1)
	var point = Vector2(.15+.7*t,.9-.65*t)
	if side==0 and index%2==1:point+=Vector2(-.06,-.18)
	return point
static func arrange(group: Dictionary, entries: Array, bounds: Vector2, side: int) -> Dictionary:
	var r: Dictionary = group.region
	var region = Rect2(bounds*Vector2(r.x,r.y)/100.0,bounds*Vector2(r.width,r.height)/100.0)
	var bodies: Array = [];var separation: float = 1.0
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		bodies.append({"id":entry.id,"position":region.position+anchor_seed(group,entry.id,i,entries.size(),side)*region.size,"extent":entry.extent})
	if group.separate_overlaps:
		for i in range(bodies.size()):
			for j in range(i+1,bodies.size()):
				var a: Dictionary = bodies[i];var b: Dictionary = bodies[j];var delta: Vector2 = b.position-a.position
				var required: float = INF
				for axis in range(2):
					if is_zero_approx(delta[axis]):continue
					var gap: float = a.extent.end[axis]-b.extent.position[axis] if delta[axis]>0 else b.extent.end[axis]-a.extent.position[axis]
					required=minf(required,(gap+group.gap)/absf(delta[axis]))
				if is_finite(required):separation=maxf(separation,required)
	for body in bodies:body.position=region.get_center()+(body.position-region.get_center())*separation
	var total=Rect2();var first: bool = true
	for body in bodies:
		var rect: Rect2 = body.extent;rect.position+=body.position
		total=rect if first else total.merge(rect);first=false
	# Resting layout margin. Temporary attack/cover destinations are bounded below,
	# using the moving actor's own fitted extent, including in very small regions.
	var safe=region.grow_individual(-minf(18,region.size.x*.1),-minf(8,region.size.y*.1),-minf(18,region.size.x*.1),-minf(8,region.size.y*.1))
	var factor: float = 1.0;var shift=Vector2.ZERO
	if group.fit=="contain" and total.has_area():
		factor=minf(1.0,minf(safe.size.x/total.size.x,safe.size.y/total.size.y))
		shift=safe.get_center()-total.get_center()*factor
	var offset=Vector2(group.offset.x,group.offset.y);var result: Dictionary = {};var occupied: Dictionary = {}
	for body in bodies:
		var position: Vector2 = body.position*factor+shift+offset
		result[body.id]=position;occupied[body.id]=Rect2(position+body.extent.position*factor,body.extent.size*factor)
	var conflicts: Array = []
	var ids: Array = result.keys()
	for i in range(ids.size()):
		if not region.grow(.01).encloses(occupied[ids[i]]):conflicts.append("outside-region:"+ids[i])
		for j in range(i+1,ids.size()):
			if occupied[ids[i]].intersects(occupied[ids[j]]):conflicts.append("overlap:"+ids[i]+":"+ids[j])
	return {"anchors":result,"fit":factor,"separation":separation,"region":region,"occupied":occupied,"conflicts":conflicts}
static func motion_anchor(wanted: Vector2, extent: Rect2, region: Rect2) -> Vector2:
	var result: Vector2 = wanted
	for axis in range(2):
		var low: float = region.position[axis]-extent.position[axis]
		var high: float = region.end[axis]-extent.end[axis]
		result[axis]=clampf(wanted[axis],low,high) if high>=low else (low+high)/2.0
	return result
static func shadow_for(group: Dictionary, id: String, index: int, count: int, side: int) -> Dictionary:
	var fallback: Dictionary = group.get("shadow",{"enabled":true,"attachment":"visible-foot","width":18 if side==1 else 28,"height":4 if side==1 else 5,"offset":{"x":0,"y":0},"color":"#00000050"})
	if side==0:
		for point in group.get("positions",[]):
			if point.instance_id==id:return point.get("shadow",fallback)
	else:
		for row in group.get("slots_by_count",[]):
			if row.count==count:return row.slots[index].get("shadow",fallback)
	return fallback
static func shadow_extent(shadow: Dictionary, visual: Rect2, factor: float) -> Rect2:
	if not shadow.enabled:return Rect2()
	var offset=Vector2(shadow.offset.x,shadow.offset.y)*factor
	var half=Vector2(shadow.width,shadow.height)*factor/2.0
	# All possible visible contacts lie within the all-action alpha bounds.
	# This conservative union keeps frame switches from refitting the group.
	var contacts: Rect2 = visual if shadow.attachment=="visible-foot" else Rect2()
	return Rect2(contacts.position+offset-half,contacts.size+half*2.0)
