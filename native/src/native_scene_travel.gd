# SPDX-License-Identifier: MIT
extends RefCounted
const Schema = preload("res://src/native_schema.gd")
const CAPABILITY = "world.scene-travel.v1"
const GATE_CAPABILITY = "world.portal-gates.v1"
const Condition = preload("res://src/native_condition.gd")

static func gates_used(content: Dictionary) -> bool:
	return content.scenes.any(func(scene): return scene.get("portals", []).any(func(row): return row.has("gate")))

const EXTENSION = "pal.native.scene-travel"

static func used(content: Dictionary) -> bool:
	for scene in content.scenes:
		if not scene.get("entrances", []).is_empty() or not scene.get("portals", []).is_empty(): return true
	for node in content.nodes:
		if node.op == "scene_transfer": return true
	return false

static func entrance(package, scene_id: String, id: String) -> Dictionary:
	for row in package.index.scenes.get(scene_id, {}).get("entrances", []):
		if row.id == id: return row
	return {}

static func portal(package, scene_id: String, id: String) -> Dictionary:
	for row in package.index.scenes.get(scene_id, {}).get("portals", []):
		if row.id == id: return row
	return {}

static func validate(package) -> String:
	for scene in package.world.scenes:
		var ids: Dictionary = {}
		for row in scene.get("entrances", []):
			if ids.has(row.id): return "duplicate entrance ID"
			ids[row.id] = true
			var slots: Dictionary = {}
			var previous: Dictionary = {}
			for point in row.positions:
				var cell = Vector2i(point.x, point.y)
				if not package.can_stand(scene.id, point) or slots.has(cell): return "entrance outside walkable domain or duplicate slot"
				if not previous.is_empty() and abs(point.x - previous.x) + abs(point.y - previous.y) != 1: return "entrance slots must form an adjacent chain"
				slots[cell] = true
				previous = point
		ids = {}
		var cells: Dictionary = {}
		for row in scene.get("portals", []):
			if row.has("gate"):
				var issue: String = Condition.validate(row.gate.condition, package.index.variables)
				if not issue.is_empty(): return issue
				if row.gate.blocked_text.strip_edges().is_empty(): return "blocked text must not be blank"
			var cell = Vector2i(row.position.x, row.position.y)
			if ids.has(row.id) or cells.has(cell) or not package.can_stand(scene.id, row.position): return "duplicate or unwalkable portal"
			ids[row.id] = true
			cells[cell] = true
			if package.index.nodes.get(row.transfer_node, {}).get("op") != "scene_transfer": return "portal must bind a transfer node"
	for node in package.world.nodes:
		if node.op != "scene_transfer": continue
		if entrance(package, node.scene_id, node.entrance_id).is_empty(): return "unknown destination entrance"
		if package.index.nodes.get(node.next, {}).get("op") not in ["dialogue", "choice", "end"]: return "arrival must be a waiting node"
		var safe: bool = false
		for point in package.world.safe_points:
			safe = safe or (point.scene_id == node.scene_id and point.node_id == node.next)
		if not safe: return "arrival requires a safe point"
	for scene in package.world.scenes:
		for row in scene.get("portals", []):
			if row.reverse_portal == null: continue
			var node: Dictionary = package.index.nodes[row.transfer_node]
			var back: Dictionary = portal(package, node.scene_id, row.reverse_portal)
			if back.is_empty() or back.reverse_portal != row.id: return "missing reciprocal portal"
			var reverse: Dictionary = package.index.nodes[back.transfer_node]
			if reverse.scene_id != scene.id: return "reciprocal portal returns to wrong scene"
			if entrance(package, node.scene_id, node.entrance_id).positions[0] != back.position: return "arrival must match reverse portal cell"
			if entrance(package, scene.id, reverse.entrance_id).positions[0] != row.position: return "reverse arrival must match portal cell"
	return ""

static func revision(state: Dictionary) -> int:
	return int(state.get("extensions", {}).get(EXTENSION, {}).get("revision", 0))

static func prepare(package, candidate: Dictionary, node: Dictionary) -> String:
	var destination: Dictionary = entrance(package, node.scene_id, node.entrance_id)
	if destination.is_empty() or candidate.active_party.size() > destination.positions.size(): return "入口落点不足，无法容纳当前队伍；状态已保留。"
	if revision(candidate) >= 2147483647: return "场景切换计数达到上限；状态已保留。"
	var entities: Dictionary = {}
	for item in candidate.entities: entities[item.instance_id] = item
	var destinations: Array = destination.positions.slice(0, candidate.active_party.size())
	for point in destinations:
		if not package.can_stand(node.scene_id, point): return "入口落点被地图阻挡；状态已保留。"
		for other in candidate.entities:
			if other.instance_id not in candidate.active_party and other.scene_id == node.scene_id and other.position == point: return "入口落点被人物占用；状态已保留。"
	for id in candidate.active_party:
		var actor: Dictionary = package.index.actor_definitions[entities[id].definition_id]
		var sprite: Dictionary = package.index.sprite_sets.get(actor.get("map_sprite_set"), {})
		if sprite.get("playback") == "pal.walk-phase.v1" and package.movement_rule(node.scene_id) != "pal.walk.v1": return "队员的行走素材与目标场景规则不匹配；状态已保留。"
	# All checks precede writes; caller commits this candidate with story effects.
	for slot in range(candidate.active_party.size()):
		var item: Dictionary = entities[candidate.active_party[slot]]
		item.scene_id = node.scene_id
		item.position = destinations[slot].duplicate()
		item.components["pal.native.pose"] = {"facing": destination.facing, "moving_until_tick": int(candidate.clock.logic_tick), "step_phase": 0}
	candidate.cursor.scene_id = node.scene_id
	candidate.extensions[EXTENSION] = {"revision": revision(candidate) + 1, "scene_id": node.scene_id, "entrance_id": node.entrance_id}
	if package.movement_rule(node.scene_id) == "pal.walk.v1": candidate.extensions["pal.native.walk"] = {"next_tick": int(candidate.clock.logic_tick)}
	else: candidate.extensions.erase("pal.native.walk")
	return ""

static func validate_state(package, state: Dictionary) -> String:
	if not state.extensions.has(EXTENSION): return ""
	var travel = state.extensions[EXTENSION]
	if not travel is Dictionary or travel.size() != 3 or not Schema.is_type(travel.get("revision"), "integer") or travel.revision < 1 or travel.revision > 2147483647: return "invalid saved scene travel revision"
	if travel.get("scene_id") != state.cursor.scene_id or not travel.get("entrance_id") is String: return "saved arrival/current scene mismatch"
	if entrance(package, travel.scene_id, travel.entrance_id).is_empty(): return "saved arrival entrance missing"
	return ""
