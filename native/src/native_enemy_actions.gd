# SPDX-License-Identifier: MIT
extends RefCounted
## Authored ordered choices; all skill execution stays in the shared effect engine.
const KEY = "pal.native.enemy-actions"
const SCHEMA = "pal.native.enemy-actions.v1"
const CAPABILITY = "battle.enemy-actions.v1"
const HASH_KEY = "pal.native.component-contracts"
const RULE = "native.enemy-actions.v1"
const Skills = preload("res://src/native_skills.gd")
const Progression = preload("res://src/native_progression.gd")

static func used(content: Dictionary) -> bool:
	return content.extensions.has(KEY)

static func policy(content: Dictionary, encounter_id: String, instance_id: String) -> Dictionary:
	for row in content.extensions.get(KEY, {}).get("policies", []):
		if row.encounter_id == encounter_id and row.instance_id == instance_id: return row
	return {}

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var seen: Dictionary = {}
	for row in package.world.extensions[KEY].policies:
		var key: Array = [row.encounter_id, row.instance_id]
		if seen.has(key): return "duplicate enemy action policy"
		seen[key] = true
		var encounters: Array = package.world.get("encounters", []).filter(func(e): return e.id == row.encounter_id)
		if encounters.is_empty(): return "unresolved enemy policy encounter"
		var enemies: Array = encounters[0].enemies.filter(func(e): return e.instance_id == row.instance_id)
		if enemies.is_empty(): return "unresolved enemy policy instance"
		var actor: Dictionary = package.index.actor_definitions.get(enemies[0].definition_id, {})
		for rule in row.rules:
			var skill: Dictionary = Skills.definition(package, rule.skill_id)
			if skill.is_empty() or rule.skill_id not in actor.get("skill_ids", []): return "enemy must own policy skill"
			if skill.target_mode == "all" and rule.target != "first": return "all-target rule needs canonical first selector"
			if rule.target == "self" and [skill.target_side, skill.target_mode, skill.target_life] != ["ally", "single", "living"]: return "self selector requires living single ally"
	return ""

static func target_id(package, state: Dictionary, source: Dictionary, skill: Dictionary, selector: String) -> String:
	if skill.target_mode == "all": return ""
	if selector == "self": return source.instance_id
	var rows: Array = Skills.eligible(state, skill, source.instance_id)
	if rows.is_empty(): return ""
	var selected: Dictionary = rows[0]
	if selector == "lowest_hp":
		for row in rows.slice(1):
			# Integer cross multiplication preserves declared-order ties without floats.
			if int(row.hp) * int(Progression.stats(package, selected).max_hp) < int(selected.hp) * int(Progression.stats(package, row).max_hp): selected = row
	return selected.instance_id

static func plan(package, state: Dictionary, source: Dictionary) -> Dictionary:
	var battle: Dictionary = state.extensions[Skills.KEY]
	for rule in policy(package.world, battle.encounter_id, source.instance_id).get("rules", []):
		if battle.round < rule.first_round or (int(battle.round) - int(rule.first_round)) % int(rule.every_rounds) != 0: continue
		if int(source.hp) * 100 > int(Progression.stats(package, source).max_hp) * int(rule.self_hp_percent): continue
		var skill: Dictionary = Skills.definition(package, rule.skill_id)
		var prepared: Dictionary = Skills.plan(package, state, source, rule.skill_id, target_id(package, state, source, skill, rule.target))
		if not prepared.has("error"): return prepared
	return {}  # No usable authored rule: the caller performs the normal physical attack.

static func validate_cast(content: Dictionary, battle: Dictionary, command: Dictionary) -> String:
	if command.source in battle.party: return ""
	var executed_round: int = int(battle.round) - 1
	for rule in policy(content, battle.encounter_id, command.source).get("rules", []):
		if rule.skill_id == command.skill_id and executed_round >= rule.first_round and (executed_round - int(rule.first_round)) % int(rule.every_rounds) == 0: return ""
	return "enemy cast lacks an applicable authored round rule"

static func _delta(event: Dictionary) -> int:
	if event.kind in ["attack", "damage", "status_damage"]: return -int(event.amount)
	if event.kind in ["heal", "revive", "status_heal"]: return int(event.amount)
	return 0

static func validate_trace(package, state: Dictionary, blocks: Array) -> String:
	if not used(package.world) or blocks.is_empty(): return ""
	var battle: Dictionary = state.extensions[Skills.KEY]; var party: Array = battle.party
	var enemies: Array = battle.enemies.map(func(e): return e.instance_id)
	var hp: Dictionary = {}; var maximum: Dictionary = {}
	for row in state.entities + battle.enemies:
		if row.instance_id in party or row.instance_id in enemies:
			hp[row.instance_id] = int(row.hp); maximum[row.instance_id] = int(Progression.stats(package, row).max_hp)
	for index in range(battle.events.size() - 1, -1, -1):
		var event: Dictionary = battle.events[index]
		hp[event.target] -= _delta(event)
		if hp[event.target] < 0 or hp[event.target] > maximum[event.target]: return "HP result has no bounded preimage"
	var cursor: int = 0; var enemy_phase: bool = false
	for index in range(blocks.size()):
		var block: Array = blocks[index]; var command: Dictionary = block[0]; var source: String = command.source
		if hp[source] <= 0: return "dead instance acted"
		if index > 0:
			if not enemy_phase: return "enemy acted before party finished"
			while cursor < enemies.size() and hp[enemies[cursor]] == 0: cursor += 1
			if cursor >= enemies.size() or source != enemies[cursor]: return "missing living enemy action or repeated revived seat"
			cursor += 1
		if command.kind in ["cast", "item_use"]:
			var definition: Dictionary = Skills.definition(package, command.get("skill_id", ""))
			if command.kind == "item_use":
				definition = package.world.item_definitions.filter(func(i): return i.id == command.item_id)[0].battle_use
			var allies: Array = party if source in party else enemies
			var opponents: Array = enemies if source in party else party
			var side: Array = allies if definition.target_side == "ally" else opponents
			var eligible: Array = side.filter(func(id): return (hp[id] > 0) == (definition.target_life == "living"))
			var targets: Array = block.filter(func(e): return e.get("effect_index", -1) == 0).map(func(e): return e.target)
			if (targets != eligible if definition.target_mode == "all" else targets.size() != 1 or targets[0] not in eligible): return "action-time life or complete target set mismatch"
			if index > 0 and command.kind == "cast":
				var matching: bool = false; var round_no: int = int(battle.round) - 1
				for rule in policy(package.world, battle.encounter_id, source).get("rules", []):
					if rule.skill_id != command.skill_id or round_no < rule.first_round or (round_no - int(rule.first_round)) % int(rule.every_rounds) != 0 or hp[source] * 100 > maximum[source] * int(rule.self_hp_percent): continue
					if definition.target_mode == "all": matching = true; break
					var selected: String = source if rule.target == "self" else eligible[0]
					if rule.target == "lowest_hp":
						for id in eligible.slice(1):
							if hp[id] * maximum[selected] < hp[selected] * maximum[id]: selected = id
					matching = matching or targets == [selected]
				if not matching: return "enemy cast target/HP/round lacks matching rule"
		for event in block: hp[event.target] += _delta(event)
		if index == 0:
			var following: int = -1
			for slot in range(party.find(source) + 1, party.size()):
				if hp[party[slot]] > 0: following = slot; break
			enemy_phase = following < 0
			if not enemy_phase and (blocks.size() != 1 or battle.turn != following): return "party turn progression mismatch"
	if enemy_phase:
		while cursor < enemies.size() and hp[enemies[cursor]] == 0: cursor += 1
		if cursor != enemies.size() or battle.round < 2: return "enemy phase incomplete"
		var first_living: String = ""
		for id in party:
			if state.entities.any(func(a): return a.instance_id == id and a.hp > 0): first_living = id; break
		if first_living != party[battle.turn]: return "completed round must resume first living party seat"
		if not battle.guarding.is_empty(): return "completed round must clear guarding"
	return ""
