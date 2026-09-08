# SPDX-License-Identifier: MIT
extends RefCounted
## Deterministic Native foundation; deliberately not PAL.EXE damage parity.
const CAPABILITY = "battle.turn-core.v1"
const RULE = "native.battle-turn-core.v1"
const KEY = "pal.native.battle"
const Schema = preload("res://src/native_schema.gd")
const Skills = preload("res://src/native_skills.gd")
const Inventory = preload("res://src/native_inventory.gd")
const Statuses = preload("res://src/native_statuses.gd")
const EnemyActions = preload("res://src/native_enemy_actions.gd")

static func used(content: Dictionary) -> bool:
	return not content.get("encounters", []).is_empty() or content.nodes.any(func(n): return n.op == "battle")

static func encounter(content: Dictionary, id: String) -> Dictionary:
	for row in content.get("encounters", []):
		if row.id == id: return row
	return {}

static func actor(state: Dictionary, id: String) -> Dictionary:
	for row in state.entities:
		if row.instance_id == id: return row
	return {}

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var ids: Dictionary = {}
	for row in package.world.get("encounters", []):
		if ids.has(row.id): return "duplicate encounter ID"
		ids[row.id] = true
		var enemies: Dictionary = {}
		for enemy in row.enemies:
			if enemies.has(enemy.instance_id) or package.index.entities.has(enemy.instance_id): return "duplicate or world-colliding enemy identity"
			enemies[enemy.instance_id] = true
			if not package.index.actor_definitions.get(enemy.definition_id, {}).has("combat"): return "enemy requires declared combat stats"
	for id in package.world.roster:
		if not package.index.actor_definitions[package.index.entities[id].definition_id].has("combat"): return "roster member requires declared combat stats"
	for node in package.world.nodes:
		if node.op != "battle": continue
		if not ids.has(node.encounter_id): return "unresolved encounter"
		for field in ["on_win", "on_loss", "on_escape"]:
			if not package.index.nodes.has(node[field]): return "unresolved battle callback"
	return ""

static func begin(package, state: Dictionary, node: Dictionary, execution_id: String) -> String:
	if state.extensions.has(KEY): return "battle is already active"
	var turn: int = _living_turn(state, state.active_party, 0)
	if turn < 0: return "battle entry requires a living party member"
	var enemies: Array = []
	for source in encounter(package.world, node.encounter_id).enemies:
		var definition: Dictionary = package.index.actor_definitions[source.definition_id]
		enemies.append({"instance_id": source.instance_id, "definition_id": source.definition_id, "hp": definition.max_hp, "mp": definition.max_mp})
	state.extensions[KEY] = {"version": 1, "node_id": node.id, "encounter_id": node.encounter_id, "execution_id": execution_id, "round": 1, "step": 0, "turn": turn, "party": state.active_party.duplicate(), "enemies": enemies, "guarding": [], "events": []}
	if Statuses.used(package.world): state.extensions[KEY].statuses = []
	state.cursor.phase = "battle_command"
	return ""

static func _living_turn(state: Dictionary, party: Array, start: int) -> int:
	for i in range(start, party.size()):
		if actor(state, party[i]).hp > 0: return i
	return -1

static func validate_state(package, state: Dictionary) -> String:
	var ext = state.extensions.get(KEY)
	if ext == null:
		return "battle cursor requires active battle" if state.cursor.phase == "battle_command" or package.index.nodes[state.cursor.node_id].op == "battle" else ""
	if state.cursor.phase != "battle_command" or ext.node_id != state.cursor.node_id: return "battle cursor mismatch"
	var node: Dictionary = package.index.nodes.get(ext.node_id, {})
	if node.get("op") != "battle" or node.encounter_id != ext.encounter_id: return "battle encounter/node mismatch"
	if ext.party != state.active_party or ext.turn >= ext.party.size(): return "battle party/turn mismatch"
	if actor(state, ext.party[ext.turn]).hp <= 0: return "dead actor cannot own command turn"
	var source: Dictionary = encounter(package.world, ext.encounter_id)
	if source.is_empty() or source.enemies.size() != ext.enemies.size(): return "battle enemy roster mismatch"
	var alive: bool = false
	var all_ids: Array = ext.party.duplicate()
	for i in range(source.enemies.size()):
		var enemy: Dictionary = ext.enemies[i]
		if enemy.instance_id != source.enemies[i].instance_id or enemy.definition_id != source.enemies[i].definition_id: return "battle enemy identity/order mismatch"
		var definition: Dictionary = package.index.actor_definitions[enemy.definition_id]
		if enemy.hp > definition.max_hp or enemy.mp > definition.max_mp: return "enemy stats exceed definition"
		alive = alive or enemy.hp > 0; all_ids.append(enemy.instance_id)
	if not alive: return "finished battle cannot wait for commands"
	for id in ext.guarding:
		if id not in ext.party.slice(0, ext.turn): return "guard must belong to an earlier party turn"
	for event in ext.events:
		if event.source not in all_ids or event.target not in all_ids: return "battle event has unknown actor"
	var executor = state.extensions.get("pal.native.executor")
	if not executor is Dictionary or not executor.get("activation") is String or not Schema.is_type(executor.get("step"), "integer") or executor.step < 1: return "missing battle executor resume state"
	var expected: String = "effect." + Schema.digest(JSON.stringify([state.run_id, executor.activation, int(executor.step) - 1, ext.node_id]).to_utf8_buffer())
	if ext.execution_id != expected or expected in state.committed_effect_ids: return "invalid or already committed battle execution"
	if ext.events.size() > 8192: return "battle event budget exceeded"
	var partition: Dictionary = Skills.Effects.action_blocks(state)
	if partition.has("error"): return partition.error
	for block in partition.blocks:
		if block[0].kind == "cast":
			var cast_issue: String = EnemyActions.validate_cast(package.world, ext, block[0])
			if not cast_issue.is_empty(): return cast_issue
	var issue: String = Skills.validate_events(package, state)
	if issue.is_empty(): issue = Inventory.validate_state(package, state)
	if issue.is_empty(): issue = EnemyActions.validate_trace(package, state, partition.blocks)
	return Statuses.validate_state(package, state) if issue.is_empty() else issue

static func command(package, state: Dictionary, action: String, target: String = "", skill_id: String = "", item_id: String = "") -> Dictionary:
	var issue: String = validate_state(package, state)
	if not issue.is_empty(): return {"error": issue}
	if not state.extensions.has(KEY): return {"error": "no active battle"}
	var battle: Dictionary = state.extensions[KEY]
	if battle.step >= 100000: return {"error": "battle action budget exceeded"}
	var source: Dictionary = actor(state, battle.party[battle.turn])
	var blocked: String = Statuses.blocking(package, state, source.instance_id, "skip_turn")
	if not blocked.is_empty() and action != "wait": return {"error": "当前状态下无法行动，请选择跳过行动。"}
	if blocked.is_empty() and action == "wait": return {"error": "当前角色可以行动。"}
	var enemy: Dictionary = {}
	var prepared: Dictionary = {}
	if action != "skill" and not skill_id.is_empty(): return {"error": "skill identity supplied to another action"}
	if action != "item" and not item_id.is_empty(): return {"error": "item identity supplied to another action"}
	if action == "skill":
		prepared = Skills.plan(package, state, source, skill_id, target)
		if prepared.has("error"): return prepared
	elif action == "item":
		prepared = Inventory.plan(package, state, item_id, target)
		if prepared.has("error"): return prepared
	elif action == "attack":
		for row in battle.enemies:
			if row.instance_id == target and row.hp > 0: enemy = row
		if enemy.is_empty(): return {"error": "choose a living enemy"}
	elif action == "escape":
		if not encounter(package.world, battle.encounter_id).allow_escape: return {"error": "此战不能撤离。"}
	elif action not in ["guard", "wait"]: return {"error": "unsupported battle action"}
	battle.events = []; battle.step += 1
	if action == "escape":
		battle.events.append({"kind": "escape", "source": source.instance_id, "target": source.instance_id, "amount": 0})
		return {"outcome": "escape"}
	if action == "wait":
		battle.events.append({"kind": "status_skip", "source": source.instance_id, "target": source.instance_id, "amount": 0, "status_id": blocked})
	elif action == "guard":
		battle.guarding.append(source.instance_id)
		battle.events.append({"kind": "guard", "source": source.instance_id, "target": source.instance_id, "amount": 0})
	elif action == "skill":
		issue = Skills.apply(package, state, source, prepared)
		if not issue.is_empty(): return {"error": issue}
	elif action == "item":
		issue = Inventory.apply(package, state, source, prepared)
		if not issue.is_empty(): return {"error": issue}
	else: _hit(package, state, source, enemy, false, battle.events)
	if _living_turn(state, battle.party, 0) < 0: return {"outcome": "loss"}
	if battle.enemies.all(func(row): return row.hp == 0): return {"outcome": "win"}
	var next: int = _living_turn(state, battle.party, battle.turn + 1)
	if next >= 0:
		battle.turn = next
		return {}
	# Resolve each living enemy from the state produced by the previous complete action.
	for row in battle.enemies:
		if row.hp <= 0: continue
		var enemy_blocked: String = Statuses.blocking(package, state, row.instance_id, "skip_turn")
		if not enemy_blocked.is_empty():
			battle.events.append({"kind": "status_skip", "source": row.instance_id, "target": row.instance_id, "amount": 0, "status_id": enemy_blocked})
			continue
		var enemy_plan: Dictionary = EnemyActions.plan(package, state, row)
		if not enemy_plan.is_empty():
			issue = Skills.apply(package, state, row, enemy_plan)
			if not issue.is_empty(): return {"error": issue} # Apply failure rolls back the whole command.
		else:
			var defender: Dictionary = actor(state, battle.party[_living_turn(state, battle.party, 0)])
			_hit(package, state, row, defender, defender.instance_id in battle.guarding, battle.events)
		if _living_turn(state, battle.party, 0) < 0: return {"outcome": "loss"}
		if battle.enemies.all(func(e): return e.hp == 0): return {"outcome": "win"}
	Statuses.end_round(package, state)
	if _living_turn(state, battle.party, 0) < 0: return {"outcome": "loss"}
	if battle.enemies.all(func(row): return row.hp == 0): return {"outcome": "win"}
	if battle.round >= 10000: return {"error": "battle round budget exceeded"}
	battle.round += 1; battle.turn = _living_turn(state, battle.party, 0); battle.guarding = []
	return {}

static func _hit(package, state: Dictionary, source: Dictionary, target: Dictionary, guarded: bool, events: Array) -> void:
	var attack: int = Statuses.stat(package, state, source, "attack")
	var defense: int = Statuses.stat(package, state, target, "defense")
	var damage: int = maxi(1, attack - defense)
	if guarded: damage = (damage + 1) >> 1
	damage = mini(damage, int(target.hp)); target.hp -= damage
	events.append({"kind": "attack", "source": source.instance_id, "target": target.instance_id, "amount": damage})
	Statuses.after_damage(package, state, source.instance_id, target, damage)
