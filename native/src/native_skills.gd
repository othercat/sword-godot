# SPDX-License-Identifier: MIT
extends RefCounted
## Ordered, deterministic Native skill components. No legacy indices or renderer.
const CAPABILITY = "battle.skills.v1"
const RULE = "native.skill-effects.v1"
const KEY = "pal.native.battle"

static func used(content: Dictionary) -> bool:
	return not content.get("skill_definitions", []).is_empty() or content.actor_definitions.any(func(a): return not a.get("skill_ids", []).is_empty())

static func definition(package, id: String) -> Dictionary:
	for skill in package.world.get("skill_definitions", []):
		if skill.id == id: return skill
	return {}

static func validate_content(package) -> String:
	var ids: Dictionary = {}
	for skill in package.world.get("skill_definitions", []):
		if ids.has(skill.id): return "duplicate skill identity"
		ids[skill.id] = true
		if skill.target_life == "dead":
			if skill.effects[0].op != "revive" or not skill.effects.slice(1).all(func(e): return e.op == "heal"): return "dead-target skill requires revive followed only by healing"
		elif skill.effects.any(func(e): return e.op == "revive"): return "revive requires dead targets"
	for actor in package.world.actor_definitions:
		for id in actor.get("skill_ids", []):
			if not ids.has(id) or not actor.has("combat"): return "loadout requires a declared skill and combat stats"
	return ""

static func eligible(state: Dictionary, skill: Dictionary) -> Array:
	var battle: Dictionary = state.extensions[KEY]
	var rows: Array = battle.enemies if skill.target_side == "enemy" else battle.party.map(func(id): return state.entities.filter(func(a): return a.instance_id == id)[0])
	return rows.filter(func(a): return a.hp > 0 if skill.target_life == "living" else a.hp == 0)

static func plan(package, state: Dictionary, source: Dictionary, skill_id: String, target: String) -> Dictionary:
	var skill: Dictionary = definition(package, skill_id)
	if skill.is_empty() or skill_id not in package.index.actor_definitions[source.definition_id].get("skill_ids", []): return {"error": "此角色未掌握该技能。"}
	if source.mp < skill.mp_cost: return {"error": "真气不足。"}
	var targets: Array = eligible(state, skill)
	if skill.target_mode == "single": targets = targets.filter(func(a): return a.instance_id == target)
	elif not target.is_empty(): return {"error": "全体技能不能指定单个目标。"}
	if targets.is_empty(): return {"error": "没有符合存活状态和阵营的目标。"}
	return {"skill": skill, "targets": targets}

static func apply(package, state: Dictionary, source: Dictionary, prepared: Dictionary) -> void:
	var battle: Dictionary = state.extensions[KEY]; var skill: Dictionary = prepared.skill
	source.mp -= int(skill.mp_cost)
	battle.events.append({"kind": "cast", "source": source.instance_id, "target": source.instance_id, "amount": skill.mp_cost, "skill_id": skill.id})
	# Effect order is authoritative; each effect visits the original legal targets.
	for i in range(skill.effects.size()):
		var effect: Dictionary = skill.effects[i]
		for target in prepared.targets:
			var amount: int = 0; var actor: Dictionary = package.index.actor_definitions[target.definition_id]
			match effect.op:
				"damage":
					amount = maxi(1, int(effect.power) - int(actor.combat.defense))
					if target.instance_id in battle.guarding: amount = (amount + 1) >> 1
					amount = mini(amount, int(target.hp)); target.hp -= amount
				"heal":
					if target.hp > 0: amount = mini(int(effect.power), int(actor.max_hp - target.hp)); target.hp += amount
				"revive":
					if target.hp == 0: amount = mini(int(effect.power), int(actor.max_hp)); target.hp = amount
			battle.events.append({"kind": effect.op, "source": source.instance_id, "target": target.instance_id, "amount": amount, "skill_id": skill.id, "effect_index": i})

static func validate_events(package, state: Dictionary) -> String:
	if not state.extensions.has(KEY): return ""
	var battle: Dictionary = state.extensions[KEY]; var cast: Dictionary = {}; var seen: Dictionary = {}; var last_effect: int = -1
	var groups: Array = []; var closed: bool = false
	for i in range(battle.events.size()):
		var event: Dictionary = battle.events[i]
		if event.kind not in ["cast", "damage", "heal", "revive"]:
			if not cast.is_empty():
				closed = true
				if event.kind != "attack" or event.source not in battle.enemies.map(func(a): return a.instance_id) or event.target not in battle.party: return "only enemy retaliation may follow skill effects"
			continue
		var skill: Dictionary = definition(package, event.skill_id)
		var sources: Array = state.entities.filter(func(a): return a.instance_id == event.source)
		if skill.is_empty() or event.source not in battle.party or sources.is_empty(): return "unknown skill/caster in result"
		if skill.id not in package.index.actor_definitions[sources[0].definition_id].get("skill_ids", []): return "result caster does not own skill"
		if event.kind == "cast":
			if i != 0 or not cast.is_empty() or event.target != event.source or event.amount != skill.mp_cost: return "invalid or duplicate MP debit result"
			cast = event
			for _effect in skill.effects: groups.append([])
			continue
		if cast.is_empty() or event.skill_id != cast.skill_id or event.source != cast.source: return "effect without matching cast"
		if closed: return "effect block is interrupted by retaliation"
		var index: int = event.effect_index
		if index < 0 or index >= skill.effects.size() or index < last_effect: return "effect order/reference mismatch"
		last_effect = index
		if event.kind != skill.effects[index].op or event.amount > skill.effects[index].power: return "effect result exceeds skill definition"
		var side: Array = battle.party if skill.target_side == "ally" else battle.enemies.map(func(a): return a.instance_id)
		var key: String = str(index) + ":" + event.target
		if event.target not in side or seen.has(key): return "wrong side or repeated effect target"
		seen[key] = true; groups[index].append(event.target)
	if not cast.is_empty():
		if groups[0].is_empty() or not groups.all(func(group): return group == groups[0]): return "every declared effect requires the same ordered targets"
		var skill: Dictionary = definition(package, cast.skill_id)
		var side: Array = battle.party if skill.target_side == "ally" else battle.enemies.map(func(a): return a.instance_id)
		if groups[0] != side.filter(func(id): return id in groups[0]): return "effect targets must retain side order"
		if skill.target_mode == "single" and groups[0].size() != 1: return "single skill has multiple targets"
	return ""
