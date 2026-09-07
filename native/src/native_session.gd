# SPDX-License-Identifier: MIT
extends RefCounted
const Regions = preload("res://src/native_regions.gd")
const Condition = preload("res://src/native_condition.gd")
signal changed
const Package = preload("res://src/native_package.gd")
const Schema = preload("res://src/native_schema.gd")
const SceneTravel = preload("res://src/native_scene_travel.gd")
const PartyTrail = preload("res://src/native_party_trail.gd")
const TIMING_RULES = "practice.v1;rta=monotonic-including-pause;active=focused-unpaused;load=ineligible;tick=60"
var package
var state: Dictionary = {}
var error: String = ""
var dialogue_open: bool = true
var paused: bool = false
var focused: bool = true
var modal: bool = false
var _last_usec: int = 0
var _move_tick: int = -8

static func unique(prefix: String) -> String:
	return prefix + "." + Crypto.new().generate_random_bytes(16).hex_encode()

func activate(candidate, now_usec: int = -1) -> bool:
	# Candidate validation/automatic execution completes before replacing live state.
	if candidate == null or not candidate.error.is_empty() or candidate.world.is_empty():
		error = "invalid package candidate"
		return false
	var previous_package = package
	var previous_state = state
	package = candidate
	var world: Dictionary = package.world
	state = {"schema": "pal.native.state.v1", "runtime_id": "pal.wanxiang", "runtime_version": "0.1.0", "build_id": "native.preview.1", "session_id": unique("session"), "timeline_epoch": 0, "state_revision": 0, "profile_id": "profile.local.preview", "run_id": unique("run"), "package_id": world.package_id, "content_lock": package.content_lock, "ruleset_id": package.manifest.ruleset_id, "ruleset_hash": package.manifest.ruleset_hash,
		"clock": {"logic_tick": 0, "ticks_per_second": 60, "rta_usec": 0, "active_game_usec": 0, "continuity": "continuous", "timing_ruleset": "timing.native.practice.v1", "logic_paused": false, "timing_state": "running", "reason": "playing", "timing_ruleset_hash": Schema.digest(TIMING_RULES.to_utf8_buffer())},
		"entities": [], "roster": world.roster.duplicate(), "active_party": world.active_party.duplicate(), "narrative_cast": world.narrative_cast.duplicate(), "scopes": {"profile": {}, "run": {}, "chapter": {}},
		"cursor": {"scene_id": world.entry_scene, "node_id": world.entry_node, "safe_point_id": null, "phase": "before_node"}, "rng": {"algorithm": "pal.native.unused.v1", "state": "unused"}, "committed_effect_ids": [],
		"extensions": {"pal.native.executor": {"activation": unique("activation"), "step": 0}, "pal.native.timing": {"eligible": false, "reason": "preview-practice"}}}
	for source in world.entities:
		var definition: Dictionary = package.index.actor_definitions[source.definition_id]
		state.entities.append({"entity_kind": "actor", "component_schema_version": 1, "instance_id": source.instance_id, "definition_id": source.definition_id, "scene_id": source.scene_id, "position": source.position.duplicate(), "hp": definition.max_hp, "mp": definition.max_mp, "components": {"pal.native.pose": {"facing": source.facing, "moving_until_tick": 0, "step_phase": 0}}})
	for variable in world.variables: state.scopes[variable.scope][variable.id] = variable.initial
	Regions.initialize(world, state)
	error = PartyTrail.reseed(package, state, world.active_party)
	if not error.is_empty() or not _advance(world.entry_node):
		package = previous_package
		state = previous_state
		return false
	_last_usec = Time.get_ticks_usec() if now_usec < 0 else now_usec
	_move_tick = -movement_ticks()
	if movement_rule() == "pal.walk.v1": state.extensions["pal.native.walk"] = {"next_tick": 0}
	paused = false
	modal = false
	dialogue_open = current_node().op != "end"
	changed.emit()
	return true

func current_node() -> Dictionary:
	return {} if state.is_empty() else package.index.nodes[state.cursor.node_id]

func entity(id: String) -> Dictionary:
	return _candidate_entity(state, id)

static func _candidate_entity(candidate: Dictionary, id: String) -> Dictionary:
	for item in candidate.entities:
		if item.instance_id == id: return item
	return {}

func advance_dialogue(choice_id: String = "") -> bool:
	if state.is_empty() or paused or modal or not focused or not dialogue_open: return false
	var node: Dictionary = current_node()
	var target: String = ""
	if node.op == "dialogue": target = node.next
	elif node.op == "choice":
		for choice in node.options:
			if choice.id == choice_id: target = choice.next
	if target.is_empty(): return false
	if not _advance(target): return false
	dialogue_open = current_node().op != "end"
	changed.emit()
	return true

func interact() -> bool:
	if state.is_empty() or paused or modal or not focused: return false
	if dialogue_open: return advance_dialogue()
	error = ""
	var leader: Dictionary = entity(state.active_party[0])
	for portal in package.index.scenes[state.cursor.scene_id].get("portals", []):
		if portal.position == leader.position: return _interact_node(portal.transfer_node)
	for source in package.world.entities:
		var target: Dictionary = entity(source.instance_id)
		if source.interaction_node == null or target.scene_id != leader.scene_id: continue
		if abs(target.position.x - leader.position.x) + abs(target.position.y - leader.position.y) <= 1:
			return _interact_node(source.interaction_node)
	return false

func _interact_node(node_id: String) -> bool:
	var old = state.duplicate(true)
	state.extensions["pal.native.executor"] = {"activation": unique("activation"), "step": 0}
	if not _advance(node_id):
		state = old
		return false
	dialogue_open = current_node().op != "end"
	changed.emit()
	return true

func _advance(first: String) -> bool:
	var candidate: Dictionary = state.duplicate(true)
	var budget: Dictionary = {"remaining": 1024, "planning": {"remaining": PartyTrail.MAX_VISITS}}
	if not _execute(candidate, first, budget) or not _drain_regions(candidate, budget): return false
	candidate.state_revision += 1
	_publish(candidate)
	return true

func _publish(candidate: Dictionary) -> void:
	var transferred: bool = SceneTravel.revision(candidate) != SceneTravel.revision(state)
	state = candidate
	if transferred: _move_tick = int(state.clock.logic_tick) - movement_ticks()
	dialogue_open = current_node().op != "end"
	error = ""

func _drain_regions(candidate: Dictionary, budget: Dictionary) -> bool:
	while package.index.nodes[candidate.cursor.node_id].op == "end":
		var event: Dictionary = Regions.next_event(package, candidate)
		if event.has("error"):
			error = event.error
			return false
		if event.is_empty(): return true
		if not _execute(candidate, event.node_id, budget): return false
	return true

func _execute(candidate: Dictionary, first: String, budget: Dictionary) -> bool:
	var next: String = first
	var planning_budget: Dictionary = budget.planning
	while budget.remaining > 0:
		budget.remaining -= 1
		if not package.index.nodes.has(next):
			error = "unresolved story target; state retained"
			return false
		var node: Dictionary = package.index.nodes[next]
		candidate.cursor.node_id = next
		candidate.cursor.safe_point_id = null
		for point in package.world.safe_points:
			if point.scene_id == candidate.cursor.scene_id and point.node_id == next:
				candidate.cursor.safe_point_id = point.id
				break
		if node.op in ["dialogue", "choice", "end"]:
			return true
		var executor: Dictionary = candidate.extensions["pal.native.executor"]
		var effect_id: String = "effect." + Schema.digest(JSON.stringify([candidate.run_id, executor.activation, executor.step, next]).to_utf8_buffer())
		executor.step += 1
		match node.op:
			"set":
				var scope: String = package.index.variables[node.variable].scope
				candidate.scopes[scope][node.variable] = node.value
				candidate.committed_effect_ids.append(effect_id)
				next = node.next
			"party":
				if PartyTrail.used(package.world):
					error = PartyTrail.reseed(package, candidate, node.members, false, planning_budget)
					if not error.is_empty(): return false
				else:
					for member in node.members:
						var actor: Dictionary = _candidate_entity(candidate, member)
						if actor.scene_id != candidate.cursor.scene_id:
							error = "party member is outside current scene; state retained"
							return false
				candidate.active_party = node.members.duplicate()
				candidate.committed_effect_ids.append(effect_id)
				next = node.next
			"scene_transfer":
				error = SceneTravel.prepare(package, candidate, node)
				if not error.is_empty(): return false
				Regions.clear_pending(candidate)
				error = PartyTrail.reseed(package, candidate, candidate.active_party, true, planning_budget)
				if not error.is_empty(): return false
				candidate.committed_effect_ids.append(effect_id)
				next = node.next
			"branch":
				if node.has("condition"):
					var decision: Dictionary = Condition.evaluate(node.condition, package.index.variables, candidate.scopes)
					if decision.has("error"):
						error = decision.error
						return false
					next = node.then if decision.value else node["else"]
				else:
					var scope: String = package.index.variables[node.variable].scope
					next = node.then if Schema.equal(candidate.scopes[scope][node.variable], node.equals) else node["else"]
		if candidate.committed_effect_ids.size() > 100000:
			error = "effect history limit; state retained"
			return false
	error = "automatic node budget exceeded; state retained"
	return false

func tick() -> void:
	if state.is_empty() or paused or modal or not focused: return
	state.clock.logic_tick += 1
	state.state_revision += 1

func account_time(now_usec: int) -> void:
	if state.is_empty(): return
	var elapsed: int = maxi(0, now_usec - _last_usec)
	_last_usec = maxi(_last_usec, now_usec)
	state.clock.rta_usec += elapsed
	if not paused and not modal and focused: state.clock.active_game_usec += elapsed
	if elapsed > 5000000: state.clock.continuity = "gap"
	state.clock.logic_paused = paused or modal or not focused
	state.clock.timing_state = "excluded" if paused or modal or not focused else "running"
	state.clock.reason = "user_pause" if paused or modal else ("playing" if focused else "unfocused")

func set_pause(value: bool, now_usec: int = -1) -> void:
	account_time(Time.get_ticks_usec() if now_usec < 0 else now_usec)
	paused = value
	account_time(_last_usec)
	changed.emit()

func set_focus(value: bool, now_usec: int = -1) -> void:
	account_time(Time.get_ticks_usec() if now_usec < 0 else now_usec)
	focused = value
	account_time(_last_usec)
	changed.emit()

func set_modal(value: bool, now_usec: int = -1) -> void:
	account_time(Time.get_ticks_usec() if now_usec < 0 else now_usec)
	modal = value
	account_time(_last_usec)
	changed.emit()

func move(direction: Vector2i) -> bool:
	if state.is_empty() or paused or modal or not focused or dialogue_open or absi(direction.x) + absi(direction.y) > 1: return false
	var before: Dictionary = state
	var before_tick: int = _move_tick
	state = before.duplicate(true)
	var moved: bool = _move_trail(direction) if PartyTrail.used(package.world) else _move_legacy(direction)
	var candidate: Dictionary = state
	state = before
	if not moved:
		_move_tick = before_tick
		return false
	error = Regions.enqueue(package, before, candidate)
	var budget: Dictionary = {"remaining": 1024, "planning": {"remaining": PartyTrail.MAX_VISITS}}
	if not error.is_empty() or not _drain_regions(candidate, budget):
		_move_tick = before_tick
		return false
	_publish(candidate)
	changed.emit()
	return true

func _move_legacy(direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO: return false
	if state.clock.logic_tick - _move_tick < movement_ticks(): return false
	var leader: Dictionary = entity(state.active_party[0])
	var point: Dictionary = {"x": leader.position.x + direction.x, "y": leader.position.y + direction.y}
	if not package.can_stand(leader.scene_id, point): return false
	for other in state.entities:
		if other.instance_id not in state.active_party and other.scene_id == leader.scene_id and other.position == point: return false
	# Every active member follows the previous member's authoritative tile.
	var previous = leader.position.duplicate()
	leader.position = point
	_mark_motion(leader, direction)
	for i in range(1, state.active_party.size()):
		var follower: Dictionary = entity(state.active_party[i])
		var old = follower.position.duplicate()
		follower.position = previous
		follower.scene_id = leader.scene_id
		_mark_motion(follower, Vector2i(previous.x - old.x, previous.y - old.y))
		previous = old
	_move_tick = state.clock.logic_tick
	state.state_revision += 1
	return true

func _move_trail(direction: Vector2i) -> bool:
	var candidate: Dictionary = state.duplicate(true)
	var result: Dictionary = PartyTrail.step(package, candidate, direction)
	if result.has("error"):
		error = result.error
		return false
	if result.moved.is_empty(): return false
	for row in result.moved: _mark_motion(_candidate_entity(candidate, row.instance_id), row.delta)
	candidate.state_revision += 1
	state = candidate
	_move_tick = int(state.clock.logic_tick)
	error = ""
	return true

func _mark_motion(actor: Dictionary, delta: Vector2i) -> void:
	if delta == Vector2i.ZERO: return
	var pose: Dictionary = actor.components["pal.native.pose"]
	pose.facing = ("right" if delta.x > 0 else "left") if absi(delta.x) > absi(delta.y) else ("down" if delta.y > 0 else "up")
	pose.moving_until_tick = int(state.clock.logic_tick) + movement_ticks()
	if movement_rule() == "pal.walk.v1": pose.step_phase = (int(pose.get("step_phase", 0)) + 1) % 4

func snapshot() -> Dictionary:
	return state.duplicate(true)

func can_save() -> bool:
	return not state.is_empty() and state.cursor.safe_point_id != null

func validate_saved(candidate: Dictionary) -> String:
	var issue: String = package.schema.validate("pal.native.state.v1", candidate)
	if not issue.is_empty(): return issue
	issue = SceneTravel.validate_state(package, candidate)
	if not issue.is_empty(): return issue
	issue = PartyTrail.validate_state(package, candidate)
	if not issue.is_empty(): return issue
	issue = Regions.validate_state(package, candidate)
	if not issue.is_empty(): return issue
	if candidate.cursor.safe_point_id == null: return "live cursor is not a save boundary"
	for key in ["runtime_id", "package_id", "profile_id", "content_lock", "ruleset_id", "ruleset_hash"]:
		if candidate[key] != state[key]: return "save identity mismatch: " + key
	if candidate.clock.ticks_per_second != 60 or candidate.clock.timing_ruleset_hash != state.clock.timing_ruleset_hash or candidate.rng != state.rng: return "unsupported save clock/RNG"
	var safe = package.index.safe_points.get(candidate.cursor.safe_point_id)
	if safe == null or safe.scene_id != candidate.cursor.scene_id or safe.node_id != candidate.cursor.node_id: return "save cursor/safe-point mismatch"
	if package.index.nodes[candidate.cursor.node_id].op not in ["dialogue", "choice", "end"]: return "save cursor is not a waiting boundary"
	var ids: Dictionary = {}
	for item in candidate.entities:
		if ids.has(item.instance_id) or not package.index.entities.has(item.instance_id): return "invalid saved entity identity"
		ids[item.instance_id] = true
		if not package.index.scenes.has(item.scene_id): return "saved scene missing"
		if item.definition_id != package.index.entities[item.instance_id].definition_id: return "saved definition changed"
		var definition: Dictionary = package.index.actor_definitions[item.definition_id]
		var sprite_id = definition.get("map_sprite_set")
		if sprite_id != null and package.index.sprite_sets[sprite_id].get("playback") == "pal.walk-phase.v1" and package.movement_rule(item.scene_id) != "pal.walk.v1": return "saved PAL phase entity requires PAL walking map"
		if item.hp > definition.max_hp or item.mp > definition.max_mp or not package.can_stand(item.scene_id, item.position): return "saved stat/position range"
		var pose = item.components.get("pal.native.pose")
		if not pose is Dictionary or pose.get("facing") not in ["up", "down", "left", "right"]: return "missing pose component"
		var period: int = 6 if package.movement_rule(item.scene_id) == "pal.walk.v1" else 8
		if int(pose.get("moving_until_tick", 0)) > int(candidate.clock.logic_tick) + period: return "saved movement deadline outside supported window"
	if package.movement_rule(candidate.cursor.scene_id) == "pal.walk.v1":
		var walk = candidate.extensions.get("pal.native.walk")
		if not walk is Dictionary or not Schema.is_type(walk.get("next_tick"), "integer") or walk.next_tick < 0 or walk.next_tick > int(candidate.clock.logic_tick) + 6: return "invalid saved walk cadence"
	if ids.size() != package.world.entities.size(): return "save entity set mismatch"
	if candidate.active_party.is_empty(): return "this runtime requires an active party leader"
	for key in ["roster", "active_party", "narrative_cast"]:
		for id in candidate[key]:
			if not ids.has(id): return "unresolved saved " + key
	for id in candidate.active_party:
		if id not in candidate.roster: return "saved party outside roster"
		for item in candidate.entities:
			if item.instance_id == id and item.scene_id != candidate.cursor.scene_id: return "active party must share the current scene"
	for variable in package.world.variables:
		if not Schema.is_type(candidate.scopes[variable.scope].get(variable.id), variable.type): return "saved variable type mismatch"
	var executor = candidate.extensions.get("pal.native.executor")
	if not executor is Dictionary or not executor.get("activation") is String or not Schema.is_type(executor.get("step"), "integer") or executor.step < 0: return "missing executor resume state"
	return ""

func restore(candidate: Dictionary, now_usec: int = -1) -> bool:
	error = validate_saved(candidate)
	if not error.is_empty(): return false
	account_time(Time.get_ticks_usec() if now_usec < 0 else now_usec)
	var old = state
	state = candidate.duplicate(true)
	state.session_id = old.session_id
	state.timeline_epoch = old.timeline_epoch + 1
	state.state_revision = old.state_revision + 1
	state.clock.rta_usec = maxi(old.clock.rta_usec, state.clock.rta_usec)
	state.clock.active_game_usec = maxi(old.clock.active_game_usec, state.clock.active_game_usec)
	state.clock.continuity = "gap"
	state.extensions["pal.native.timing"] = {"eligible": false, "reason": "save-load-practice"}
	_move_tick = int(state.clock.logic_tick) - movement_ticks()
	for item in state.entities:
		_move_tick = maxi(_move_tick, int(item.components["pal.native.pose"].get("moving_until_tick", 0)) - movement_ticks())
	dialogue_open = current_node().op != "end"
	account_time(_last_usec)
	changed.emit()
	return true

func movement_rule() -> String:
	return "native.grid.v1" if state.is_empty() else package.movement_rule(state.cursor.scene_id)

func movement_ticks() -> int:
	return 6 if movement_rule() == "pal.walk.v1" else 8

func sample_movement(input) -> bool:
	if state.is_empty() or paused or modal or not focused or dialogue_open: return false
	if movement_rule() == "pal.walk.v1":
		var walk: Dictionary = state.extensions["pal.native.walk"]
		if state.clock.logic_tick < walk.next_tick: return false
		walk.next_tick = int(state.clock.logic_tick) + 6
		state.state_revision += 1
	var direction: Vector2i = input.sample(movement_rule())
	if move(direction): return true
	if direction == Vector2i.ZERO or state.clock.logic_tick - _move_tick >= movement_ticks(): stop_walking()
	return false

func stop_walking() -> void:
	if movement_rule() != "pal.walk.v1": return
	var modified: bool = false
	for id in state.active_party:
		var pose: Dictionary = entity(id).components["pal.native.pose"]
		modified = modified or int(pose.get("moving_until_tick", 0)) > int(state.clock.logic_tick) or int(pose.get("step_phase", 0)) % 2 != 0
		pose.moving_until_tick = mini(int(pose.get("moving_until_tick", 0)), int(state.clock.logic_tick))
		pose.step_phase = int(pose.get("step_phase", 0)) & 2
	if modified:
		state.state_revision += 1
		changed.emit()
