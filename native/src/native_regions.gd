# SPDX-License-Identifier: MIT
extends RefCounted
const Condition = preload("res://src/native_condition.gd")
const Schema = preload("res://src/native_schema.gd")
const KEY = "pal.native.regions"
const CAPABILITY = "world.regions.v1"
const LIMIT = 9007199254740991

static func used(content: Dictionary) -> bool:
	return content.scenes.any(func(scene): return not scene.get("triggers", []).is_empty())

static func rows(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for scene in content.scenes:
		for trigger in scene.get("triggers", []): result[trigger.id] = {"scene": scene, "trigger": trigger}
	return result

static func contains(region: Dictionary, point: Dictionary) -> bool:
	return point.x >= region.origin.x and point.y >= region.origin.y and point.x < region.origin.x + region.width and point.y < region.origin.y + region.height

static func crosses(trigger: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	return (not contains(trigger.region, a) and contains(trigger.region, b)) if trigger.event == "enter" else (contains(trigger.region, a) and not contains(trigger.region, b))

static func ordered(a: Dictionary, b: Dictionary) -> bool:
	return a.priority > b.priority if a.priority != b.priority else a.id < b.id

static func validate(package) -> String:
	var all_rows: Dictionary = rows(package.world)
	var count: int = 0
	var area: int = 0
	for scene in package.world.scenes: count += scene.get("triggers", []).size()
	if count != all_rows.size() or count > 4096: return "regions duplicate id or count budget"
	package.index.regions = all_rows
	for row in all_rows.values(): area += row.trigger.region.width * row.trigger.region.height
	if area > 262144: return "regions total area budget"
	var safe: Dictionary = {}
	for point in package.world.safe_points: safe[point.scene_id + "|" + point.node_id] = true
	var crossing_costs: Dictionary = {}
	for row in all_rows.values():
		var trigger: Dictionary = row.trigger
		if not package.index.nodes.has(trigger.node_id): return "region unresolved event node"
		if (trigger.policy == "cooldown") != (trigger.cooldown_ticks > 0): return "region cooldown/policy mismatch"
		if trigger.condition != null:
			var issue: String = Condition.validate(trigger.condition, package.index.variables)
			if not issue.is_empty(): return issue
		var region: Dictionary = trigger.region
		var map_data: Dictionary = package.index.maps[row.scene.map_id]
		var origin: Dictionary = map_data.coordinates.origin
		if region.origin.x < origin.x or region.origin.y < origin.y or region.origin.x + region.width > origin.x + map_data.width or region.origin.y + region.height > origin.y + map_data.height: return "region outside map rectangle"
		var walkable: bool = false
		for y in range(region.origin.y, region.origin.y + region.height):
			for x in range(region.origin.x, region.origin.x + region.width):
				if package.can_stand(row.scene.id, {"x": x, "y": y}):
					walkable = true
					break
			if walkable: break
		if not walkable: return "region has no walkable cell"
		var pending: Array = [[row.scene.id, trigger.node_id, false]]
		var active: Dictionary = {}
		var done: Dictionary = {}
		var visits: int = 0
		while not pending.is_empty():
			var frame: Array = pending.pop_back()
			var key: String = frame[0] + "|" + frame[1]
			if frame[2]:
				active.erase(key)
				done[key] = true
				continue
			if done.has(key): continue
			if active.has(key): return "potential automatic region event cycle"
			visits += 1
			if visits > 1024: return "region event graph budget"
			if not package.index.nodes.has(frame[1]): return "unresolved region event route"
			var node: Dictionary = package.index.nodes[frame[1]]
			if node.op in ["dialogue", "choice", "end"]:
				if not safe.has(key): return "region event wait lacks scene safe point"
				done[key] = true
				continue
			active[key] = true
			pending.append([frame[0], frame[1], true])
			if node.op == "scene_transfer": pending.append([node.scene_id, node.next, false])
			elif node.op == "branch": pending.append_array([[frame[0], node.then, false], [frame[0], node["else"], false]])
			else: pending.append([frame[0], node.next, false])
		var edges: Array = []
		for x in range(region.origin.x, region.origin.x + region.width):
			edges.append([x, region.origin.y - 1, x, region.origin.y])
			edges.append([x, region.origin.y + region.height, x, region.origin.y + region.height - 1])
		for y in range(region.origin.y, region.origin.y + region.height):
			edges.append([region.origin.x - 1, y, region.origin.x, y])
			edges.append([region.origin.x + region.width, y, region.origin.x + region.width - 1, y])
		for edge in edges:
			if trigger.event == "exit": edge = [edge[2], edge[3], edge[0], edge[1]]
			var key: String = JSON.stringify([row.scene.id, edge])
			crossing_costs[key] = crossing_costs.get(key, 0) + visits
			if crossing_costs[key] > 1024: return "overlapping region event batch budget; reduce automatic graph"

	return ""

static func initialize(content: Dictionary, state: Dictionary) -> void:
	if used(content): state.extensions[KEY] = {"version": 1, "sequence": 0, "pending": [], "fired": {}, "mutex": {}}

static func clear_pending(state: Dictionary) -> void:
	if state.extensions.has(KEY): state.extensions[KEY].pending.clear()

static func enqueue(package, before: Dictionary, candidate: Dictionary) -> String:
	if not used(package.world): return ""
	if before.cursor.scene_id != candidate.cursor.scene_id or before.active_party[0] != candidate.active_party[0]: return ""
	var a: Dictionary = before.entities.filter(func(e): return e.instance_id == before.active_party[0])[0].position
	var b: Dictionary = candidate.entities.filter(func(e): return e.instance_id == candidate.active_party[0])[0].position
	if a == b: return ""
	var selected: Array = []
	for trigger in package.index.scenes[candidate.cursor.scene_id].get("triggers", []):
		if crosses(trigger, a, b): selected.append(trigger)
	selected.sort_custom(ordered)
	var ext: Dictionary = candidate.extensions[KEY]
	if ext.pending.size() + selected.size() > 256 or ext.sequence > LIMIT - selected.size(): return "region event queue/sequence budget"
	for trigger in selected:
		ext.sequence += 1
		ext.pending.append({"trigger_id": trigger.id, "scene_id": candidate.cursor.scene_id, "sequence": ext.sequence, "tick": candidate.clock.logic_tick, "from": a.duplicate(), "to": b.duplicate()})
	return ""

# Return one eligible node after atomically reserving its policy/mutex in the
# candidate. The caller executes effects before publishing that same candidate.
static func next_event(package, candidate: Dictionary) -> Dictionary:
	if not candidate.extensions.has(KEY): return {}
	var ext: Dictionary = candidate.extensions[KEY]
	var index: Dictionary = package.index.regions
	while not ext.pending.is_empty():
		var event: Dictionary = ext.pending.pop_front()
		var trigger: Dictionary = index[event.trigger_id].trigger
		var fired: Dictionary = ext.fired.get(trigger.id, {})
		if trigger.policy == "once" and not fired.is_empty(): continue
		if trigger.policy == "cooldown" and not fired.is_empty() and candidate.clock.logic_tick - fired.last_tick < trigger.cooldown_ticks: continue
		if trigger.mutex_group != null and ext.mutex.get(trigger.mutex_group, trigger.id) != trigger.id: continue
		if trigger.condition != null:
			var result: Dictionary = Condition.evaluate(trigger.condition, package.index.variables, candidate.scopes)
			if result.has("error"): return result
			if not result.value: continue
		if fired.get("count", 0) >= LIMIT: return {"error": "region fired count budget"}
		ext.fired[trigger.id] = {"count": fired.get("count", 0) + 1, "last_tick": candidate.clock.logic_tick}
		if trigger.mutex_group != null: ext.mutex[trigger.mutex_group] = trigger.id
		candidate.extensions["pal.native.executor"] = {"activation": "region." + str(event.sequence), "step": 0}
		return {"node_id": trigger.node_id}
	return {}

static func validate_state(package, state: Dictionary) -> String:
	var index: Dictionary = rows(package.world)
	var ext: Variant = state.extensions.get(KEY)
	if index.is_empty(): return "unexpected region scheduler" if ext != null else ""
	if ext == null: return "missing region scheduler state"
	if ext.fired.size() > index.size() or ext.mutex.size() > index.size(): return "region saved record budget"
	var total: int = 0
	for id in ext.fired:
		var record: Variant = ext.fired[id]
		if not index.has(id) or not record is Dictionary or record.size() != 2 or not record.has("count") or not record.has("last_tick"): return "invalid region fired record"
		if not Schema.is_type(record.count, "integer") or record.count < 1 or record.count > LIMIT or not Schema.is_type(record.last_tick, "integer") or record.last_tick < 0 or record.last_tick > state.clock.logic_tick: return "invalid region fired count/tick"
		if index[id].trigger.policy == "once" and record.count != 1: return "region once fired multiple times"
		total += int(record.count)
		if total > ext.sequence: return "region fired count exceeds sequence"
		var group: Variant = index[id].trigger.mutex_group
		if group != null and ext.mutex.get(group) != id: return "region fired trigger lost mutex"
	for group in ext.mutex:
		var id: Variant = ext.mutex[group]
		if not id is String or not index.has(id) or not ext.fired.has(id) or index[id].trigger.mutex_group != group: return "invalid region mutex winner"
	var previous: int = 0
	var seen: Dictionary = {}
	var prior_trigger: Dictionary = {}
	var expected_sequence: int = int(ext.sequence) - ext.pending.size() + 1
	for event in ext.pending:
		if not index.has(event.trigger_id) or seen.has(event.trigger_id): return "unknown/duplicate queued region"
		seen[event.trigger_id] = true
		var row: Dictionary = index[event.trigger_id]
		if event.scene_id != row.scene.id or event.scene_id != state.cursor.scene_id: return "stale queued region scene"
		if event.sequence <= previous or event.sequence > ext.sequence or event.tick > state.clock.logic_tick: return "invalid region sequence/tick"
		previous = int(event.sequence)
		if event.sequence != expected_sequence: return "region queue is not sequence tail"
		expected_sequence += 1
		if not package.can_stand(event.scene_id, event.from) or not package.can_stand(event.scene_id, event.to): return "queued region uses invalid map cell"
		var first: Dictionary = ext.pending[0]
		if event.from != first.from or event.to != first.to or event.tick != first.tick: return "region queue mixes movement batches"
		if not prior_trigger.is_empty() and not ordered(prior_trigger, row.trigger): return "region queue priority order"
		prior_trigger = row.trigger

		if absi(event.from.x - event.to.x) + absi(event.from.y - event.to.y) != 1 or not crosses(row.trigger, event.from, event.to): return "invalid region crossing"
	if not ext.pending.is_empty() and package.index.nodes.get(state.cursor.node_id, {}).get("op") not in ["dialogue", "choice"]: return "pending regions lack waiting owner"
	return ""
