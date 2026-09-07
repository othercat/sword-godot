# SPDX-License-Identifier: MIT
extends RefCounted
## Pending authoritative footsteps. Path planning belongs to this runtime only.
const Schema = preload("res://src/native_schema.gd")
const RULE = "native.party-trail.v1"
const CAPABILITY = "movement.party-trail.v1"
const EXTENSION = "pal.native.party-trail"
const MAX_STEPS = 4096
const MAX_VISITS = 65536
const DIRECTIONS = [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]

static func used(content: Dictionary) -> bool:
	return content.get("party_movement_rule") == RULE

static func revision(state: Dictionary) -> int:
	return int(state.get("extensions", {}).get(EXTENSION, {}).get("revision", 0))

static func point(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}

static func cell(value: Dictionary) -> Vector2i:
	return Vector2i(value.x, value.y)

static func actors(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for actor in state.entities: result[actor.instance_id] = actor
	return result

static func obstacles(state: Dictionary, members: Array) -> Dictionary:
	var result: Dictionary = {}
	for actor in state.entities:
		if actor.scene_id == state.cursor.scene_id and actor.instance_id not in members:
			result[cell(actor.position)] = true
	return result

static func walkable(package, scene: String, position: Vector2i, occupied: Dictionary) -> bool:
	return not occupied.has(position) and package.can_stand(scene, point(position))

static func _route(package, scene: String, start: Vector2i, target: Vector2i, occupied: Dictionary, budget: Dictionary) -> Dictionary:
	if start == target: return {"steps": []}
	var frontier: Array[Vector2i] = [start]
	var parents: Dictionary = {start: start}
	var head: int = 0
	while head < frontier.size():
		if budget.remaining <= 0: return {"error": "队伍集合路径超过规划预算，请缩短伙伴间距离。"}
		budget.remaining -= 1
		var current: Vector2i = frontier[head]
		head += 1
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if parents.has(next) or not walkable(package, scene, next, occupied): continue
			parents[next] = current
			if next == target:
				# Stop adjacent to the predecessor. Future steps append its vacated tile.
				var path: Array = []
				var cursor: Vector2i = current
				while cursor != start:
					path.append(point(cursor))
					if path.size() > MAX_STEPS: return {"error": "队伍集合路径过长，请先让伙伴靠近。"}
					cursor = parents[cursor]
				path.reverse()
				return {"steps": path}
			frontier.append(next)
	return {"error": "伙伴之间没有可走的集合路径；队伍和位置已保留。"}

static func reseed(package, candidate: Dictionary, members: Array, force: bool = false, shared_budget: Dictionary = {}) -> String:
	if not used(package.world): return ""
	if not force and candidate.extensions.has(EXTENSION) and members == candidate.active_party: return ""
	if members.is_empty() or members.size() > 32 or revision(candidate) >= 2147483647:
		return "队伍人数或调整次数超出范围；状态已保留。"
	var entities: Dictionary = actors(candidate)
	var seen: Dictionary = {}
	var occupied: Dictionary = obstacles(candidate, members)
	for id in members:
		if seen.has(id) or id not in candidate.roster or not entities.has(id): return "队伍成员必须是候补名单内的唯一人物实例。"
		seen[id] = true
		var actor: Dictionary = entities[id]
		if actor.scene_id != candidate.cursor.scene_id: return "伙伴不在当前场景，无法加入队伍；状态已保留。"
		if not walkable(package, candidate.cursor.scene_id, cell(actor.position), occupied): return "队员与退队人物或阻挡重叠，请先分开站位。"
	var followers: Array = []
	var budget: Dictionary = {"remaining": MAX_VISITS} if shared_budget.is_empty() else shared_budget
	for slot in range(1, members.size()):
		var path: Dictionary = _route(package, candidate.cursor.scene_id, cell(entities[members[slot]].position), cell(entities[members[slot - 1]].position), occupied, budget)
		if path.has("error"): return path.error
		followers.append({"instance_id": members[slot], "predecessor_id": members[slot - 1], "steps": path.steps})
	# Planning never moves a character. The story executor commits this whole candidate.
	for id in candidate.active_party + members:
		var pose: Dictionary = entities[id].components["pal.native.pose"]
		pose.moving_until_tick = int(candidate.clock.logic_tick)
		pose.step_phase = 0
	candidate.active_party = members.duplicate()
	candidate.extensions[EXTENSION] = {"revision": revision(candidate) + 1, "scene_id": candidate.cursor.scene_id, "next_tick": int(candidate.clock.logic_tick), "followers": followers}
	return ""

static func step(package, candidate: Dictionary, direction: Vector2i) -> Dictionary:
	if absi(direction.x) + absi(direction.y) > 1: return {"error": "队伍每步只能沿一个相邻格移动。"}
	var trail: Dictionary = candidate.extensions[EXTENSION]
	if candidate.clock.logic_tick < trail.next_tick: return {"moved": []}
	var entities: Dictionary = actors(candidate)
	var occupied: Dictionary = obstacles(candidate, candidate.active_party)
	var planned: Dictionary = {}
	var changed: Array = []
	var leader: String = candidate.active_party[0]
	var old: Vector2i = cell(entities[leader].position)
	var target: Vector2i = old + direction
	planned[leader] = target if direction != Vector2i.ZERO and walkable(package, candidate.cursor.scene_id, target, occupied) else old
	if planned[leader] != old: changed.append({"instance_id": leader, "delta": direction})
	var followers: Array = trail.followers.duplicate(true)
	for row in followers:
		var previous: Vector2i = cell(entities[row.predecessor_id].position)
		var position: Vector2i = cell(entities[row.instance_id].position)
		if planned[row.predecessor_id] != previous:
			var tail: Vector2i = position if row.steps.is_empty() else cell(row.steps.back())
			if tail != previous: row.steps.append(point(previous))
		planned[row.instance_id] = position
		if not row.steps.is_empty():
			var next: Vector2i = cell(row.steps[0])
			var delta: Vector2i = next - position
			if absi(delta.x) + absi(delta.y) != 1 or not walkable(package, candidate.cursor.scene_id, next, occupied):
				return {"error": "伙伴的待走路径被阻断；本步队伍位置已保留。"}
			planned[row.instance_id] = next
			row.steps.pop_front()
			changed.append({"instance_id": row.instance_id, "delta": delta})
		if row.steps.size() > MAX_STEPS: return {"error": "队伍待走路径超过预算；本步状态已保留。"}
	if changed.is_empty(): return {"moved": []}
	for id in planned: entities[id].position = point(planned[id])
	trail.followers = followers
	trail.next_tick = int(candidate.clock.logic_tick) + (6 if package.movement_rule(candidate.cursor.scene_id) == "pal.walk.v1" else 8)
	return {"moved": changed}

static func validate_state(package, state: Dictionary) -> String:
	if not used(package.world):
		return "unexpected saved party trail" if state.extensions.has(EXTENSION) else ""
	var trail = state.extensions.get(EXTENSION)
	if not package.index.scenes.has(state.cursor.scene_id): return "unknown saved trail scene"
	var period: int = 6 if package.movement_rule(state.cursor.scene_id) == "pal.walk.v1" else 8
	if not trail is Dictionary or trail.size() != 4 or not Schema.is_type(trail.get("revision"), "integer") or trail.revision < 1 or trail.revision > 2147483647: return "invalid saved party trail revision"
	if trail.get("scene_id") != state.cursor.scene_id or not Schema.is_type(trail.get("next_tick"), "integer") or trail.next_tick < 0 or trail.next_tick > int(state.clock.logic_tick) + period: return "invalid saved party trail scene/cadence"
	if state.active_party.is_empty() or not trail.get("followers") is Array or trail.followers.size() != state.active_party.size() - 1: return "invalid saved follower count"
	var entities: Dictionary = actors(state)
	var occupied: Dictionary = obstacles(state, state.active_party)
	for id in state.active_party:
		if not entities.has(id) or entities[id].scene_id != state.cursor.scene_id: return "saved party must share trail scene"
		if not walkable(package, state.cursor.scene_id, cell(entities[id].position), occupied): return "saved party blocked by inactive actor"
	for slot in range(1, state.active_party.size()):
		var row = trail.followers[slot - 1]
		if not row is Dictionary or row.size() != 3 or row.get("instance_id") != state.active_party[slot] or row.get("predecessor_id") != state.active_party[slot - 1] or not row.get("steps") is Array or row.steps.size() > MAX_STEPS: return "invalid saved follower identity/path"
		var previous: Vector2i = cell(entities[row.instance_id].position)
		for value in row.steps:
			if not value is Dictionary or value.size() != 2 or not Schema.is_type(value.get("x"), "integer") or not Schema.is_type(value.get("y"), "integer"): return "invalid saved trail point"
			var next: Vector2i = cell(value)
			if absi(next.x - previous.x) + absi(next.y - previous.y) != 1 or not walkable(package, state.cursor.scene_id, next, occupied): return "disconnected or blocked saved trail"
			previous = next
		var predecessor: Vector2i = cell(entities[row.predecessor_id].position)
		if absi(previous.x - predecessor.x) + absi(previous.y - predecessor.y) > 1: return "saved trail does not reach predecessor"
	return ""
