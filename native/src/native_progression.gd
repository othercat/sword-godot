# SPDX-License-Identifier: MIT
extends RefCounted
## Persistent world-actor growth; transient enemies keep their authored base stats.
const KEY = "pal.native.progression"
const SCHEMA = "pal.native.progression.v1"
const CAPABILITY = "actors.progression.v1"
const MAX_EXPERIENCE = 1000000000
const BATTLE = "pal.native.battle"
const Contract = preload("res://src/native_schema.gd")

static func used(content: Dictionary) -> bool:
	return content.extensions.has(KEY)

static func profile(package, definition_id: String) -> Dictionary:
	return package.index.get("progression_profiles", {}).get(definition_id, {})

static func reward(package, encounter_id: String) -> Dictionary:
	return package.index.get("progression_rewards", {}).get(encounter_id, {})

static func level(value: Dictionary, experience: int) -> int:
	return 1 + value.levels.filter(func(row): return row.experience <= experience).size()

static func learned(value: Dictionary, experience: int) -> Array:
	var result: Array = []
	for row in value.levels:
		if row.experience <= experience: result.append_array(row.learn_skills)
	return result

static func stats(package, actor: Dictionary) -> Dictionary:
	var definition: Dictionary = package.index.actor_definitions[actor.definition_id]
	var result: Dictionary = {"max_hp": definition.max_hp, "max_mp": definition.max_mp}
	result.merge(definition.get("combat", {}))
	var value: Dictionary = actor.get("components", {}).get(KEY, {})
	if not value.is_empty():
		for row in profile(package, actor.definition_id).levels:
			if row.experience <= value.experience:
				for field in ["max_hp", "max_mp", "attack", "defense"]: result[field] = row[field]
	return result

static func skill_ids(package, actor: Dictionary) -> Array:
	var result: Array = package.index.actor_definitions[actor.definition_id].get("skill_ids", []).duplicate()
	result.append_array(actor.get("components", {}).get(KEY, {}).get("learned_skills", []))
	return result

static func label(package, actor: Dictionary) -> String:
	var value: Dictionary = actor.get("components", {}).get(KEY, {})
	if value.is_empty(): return ""
	var future: Array = profile(package, actor.definition_id).levels.filter(func(row): return row.experience > value.experience)
	return "等级 %d · 经验 %d%s" % [value.level, value.experience, " / %d" % future[0].experience if not future.is_empty() else "（最高等级）"]

static func summary(package, state: Dictionary) -> String:
	var credits: Array = state.extensions.get(KEY, {}).get("credits", [])
	if credits.is_empty(): return ""
	var credit: Dictionary = credits[-1]; var lines: PackedStringArray = ["最近战斗经验 · " + {"win": "胜利", "loss": "失败", "escape": "撤离"}[credit.outcome]]
	for award in credit.awards:
		var actor: Dictionary = state.entities.filter(func(a): return a.instance_id == award.instance_id)[0]
		var title: String = package.index.actor_definitions[actor.definition_id].display_name
		lines.append("%s +%d%s" % [title, award.amount, " · %d→%d级" % [award.before_level, award.after_level] if award.after_level != award.before_level else ""])
	return "\n".join(lines)

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var component: Dictionary = package.world.extensions[KEY]
	if component.kind != "content": return "wrong progression component kind"
	var profiles: Dictionary = {}; var rewards: Dictionary = {}
	for value in component.profiles:
		if profiles.has(value.definition_id): return "duplicate growth definition"
		var definition: Dictionary = package.index.actor_definitions.get(value.definition_id, {})
		if not definition.has("combat"): return "growth requires combat definition"
		var previous: Dictionary = {"max_hp": definition.max_hp, "max_mp": definition.max_mp}; previous.merge(definition.combat)
		var threshold: int = 0; var skills: Array = definition.get("skill_ids", []).duplicate()
		for row in value.levels:
			if row.experience <= threshold: return "growth thresholds must strictly increase"
			threshold = int(row.experience)
			for field in previous:
				if row[field] < previous[field]: return "growth stats must not decrease"
				previous[field] = row[field]
			for id in row.learn_skills:
				if id in skills or not package.world.get("skill_definitions", []).any(func(s): return s.id == id): return "unknown or repeated level skill"
				skills.append(id)
		if skills.size() > 1024: return "combined skill capacity exceeded"
		profiles[value.definition_id] = value
	for value in component.rewards:
		if rewards.has(value.encounter_id): return "duplicate reward encounter"
		var encounters: Array = package.world.get("encounters", []).filter(func(e): return e.id == value.encounter_id)
		if encounters.is_empty() or value.enemies.map(func(e): return e.instance_id) != encounters[0].enemies.map(func(e): return e.instance_id): return "reward enemy identity/order mismatch"
		rewards[value.encounter_id] = value
	package.index.progression_profiles = profiles; package.index.progression_rewards = rewards
	return ""

static func initialize(package, state: Dictionary) -> void:
	if not used(package.world): return
	state.extensions[KEY] = {"schema": SCHEMA, "kind": "ledger", "pending": null, "credits": []}
	for actor in state.entities:
		var value: Dictionary = profile(package, actor.definition_id)
		if value.is_empty(): continue
		var experience: int = int(value.initial_experience)
		actor.components[KEY] = {"schema": SCHEMA, "kind": "actor", "experience": experience, "level": level(value, experience), "learned_skills": learned(value, experience)}
		var effective: Dictionary = stats(package, actor); actor.hp = effective.max_hp; actor.mp = effective.max_mp

static func begin(package, state: Dictionary) -> void:
	var battle: Dictionary = state.extensions[BATTLE]
	if not used(package.world) or reward(package, battle.encounter_id).is_empty(): return
	state.extensions[KEY].pending = {"execution_id": battle.execution_id, "encounter_id": battle.encounter_id, "party": battle.party.duplicate(), "defeats": []}
	var pending: Dictionary = state.extensions[KEY].pending; var executor: Dictionary = state.extensions["pal.native.executor"]
	pending.node_id = battle.node_id; pending.activation = executor.activation; pending.executor_step = int(executor.step) - 1

static func note_damage(package, state: Dictionary, source_id: String, target: Dictionary, amount: int) -> void:
	if amount <= 0 or target.hp != 0 or not used(package.world): return
	var pending = state.extensions[KEY].pending
	if pending == null or target.instance_id in pending.party: return
	if pending.defeats.any(func(row): return row.enemy_id == target.instance_id): return
	var battle: Dictionary = state.extensions[BATTLE]
	var living: Array = battle.party.filter(func(id): return state.entities.any(func(a): return a.instance_id == id and a.hp > 0))
	pending.defeats.append({"enemy_id": target.instance_id, "source_id": source_id, "step": battle.step, "living": living})

static func entitlement(credit: Dictionary, policy: Dictionary, id: String) -> int:
	if credit.outcome != "win" or (policy.final_eligibility == "living" and id not in credit.living): return 0
	var amount: int = 0
	for defeat in credit.defeats:
		var earned: int = int(policy.enemies.filter(func(e): return e.instance_id == defeat.enemy_id)[0].experience)
		amount += earned if id in defeat.living else earned * int(policy.dead_percent) / 100
	return amount

static func settle(package, state: Dictionary, outcome: String) -> String:
	if not used(package.world) or state.extensions[KEY].pending == null: return ""
	var ledger: Dictionary = state.extensions[KEY]
	if ledger.credits.size() >= 100000: return "growth credit history limit; command retained"
	var battle: Dictionary = state.extensions[BATTLE]; var credit: Dictionary = ledger.pending.duplicate(true)
	credit.outcome = outcome; credit.step = battle.step; credit.awards = []
	credit.living = battle.party.filter(func(id): return state.entities.any(func(a): return a.instance_id == id and a.hp > 0))
	var policy: Dictionary = reward(package, credit.encounter_id)
	for id in battle.party:
		var actor: Dictionary = state.entities.filter(func(a): return a.instance_id == id)[0]
		if not actor.components.has(KEY): continue
		var value: Dictionary = actor.components[KEY]; var growth: Dictionary = profile(package, actor.definition_id)
		var before: int = int(value.experience); var amount: int = mini(MAX_EXPERIENCE - before, entitlement(credit, policy, id)); var after: int = before + amount
		var old_level: int = int(value.level); var old_stats: Dictionary = stats(package, actor)
		value.experience = after; value.level = level(growth, after); value.learned_skills = learned(growth, after)
		credit.awards.append({"instance_id": id, "amount": amount, "before_experience": before, "after_experience": after, "before_level": old_level, "after_level": value.level})
		if value.level != old_level:
			var effective: Dictionary = stats(package, actor)
			if growth.recovery == "keep_deficit":
				if actor.hp > 0: actor.hp += effective.max_hp - old_stats.max_hp
				actor.mp += effective.max_mp - old_stats.max_mp
			elif growth.recovery == "full_living" and actor.hp > 0:
				actor.hp = effective.max_hp; actor.mp = effective.max_mp
	ledger.credits.append(credit); ledger.pending = null
	return ""

static func _trace(package, state: Dictionary, row: Dictionary, step: int) -> String:
	var policy: Dictionary = reward(package, row.encounter_id)
	if policy.is_empty() or row.party.is_empty() or row.party.any(func(id): return not package.index.entities.has(id)): return "unknown reward/party"
	var node: Dictionary = package.index.nodes.get(row.node_id, {})
	if node.get("op") != "battle" or node.encounter_id != row.encounter_id: return "reward battle node/encounter mismatch"
	var expected: String = "effect." + Contract.digest(JSON.stringify([state.run_id, row.activation, int(row.executor_step), row.node_id]).to_utf8_buffer())
	if row.execution_id != expected: return "reward execution identity mismatch"
	var enemies: Array = policy.enemies.map(func(e): return e.instance_id)
	var seen: Array = []; var previous: int = 0
	for defeat in row.defeats:
		if defeat.enemy_id in seen or defeat.enemy_id not in enemies: return "duplicate or unknown defeat"
		seen.append(defeat.enemy_id)
		if defeat.step < previous or defeat.step > step: return "defeat step order/range"
		previous = int(defeat.step)
		if defeat.source_id not in row.party and defeat.source_id not in enemies: return "unknown defeat source"
		if defeat.living != row.party.filter(func(id): return id in defeat.living): return "defeat eligibility order/identity"
	return ""

static func _delta(event: Dictionary) -> int:
	if event.kind in ["attack", "damage", "status_damage"]: return -int(event.amount)
	if event.kind in ["heal", "revive", "status_heal"]: return int(event.amount)
	return 0

static func _current_defeats(state: Dictionary, pending: Dictionary) -> String:
	var battle: Dictionary = state.extensions[BATTLE]; var party: Array = battle.party
	var enemies: Array = battle.enemies.map(func(e): return e.instance_id); var hp: Dictionary = {}
	for actor in state.entities + battle.enemies:
		if actor.instance_id in party or actor.instance_id in enemies: hp[actor.instance_id] = int(actor.hp)
	for i in range(battle.events.size() - 1, -1, -1):
		var event: Dictionary = battle.events[i]
		if not hp.has(event.source) or not hp.has(event.target): return "unknown defeat event actor"
		hp[event.target] -= _delta(event)
	var seen: Array = pending.defeats.filter(func(d): return d.step < battle.step).map(func(d): return d.enemy_id)
	var expected: Array = []
	for event in battle.events:
		var before: int = hp[event.target]; hp[event.target] += _delta(event)
		if before > 0 and hp[event.target] == 0 and event.target in enemies and event.target not in seen:
			seen.append(event.target)
			expected.append({"enemy_id": event.target, "source_id": event.source, "step": battle.step, "living": party.filter(func(id): return hp[id] > 0)})
	return "" if Contract.equal(expected, pending.defeats.filter(func(d): return d.step == battle.step)) else "current-step first defeat differs from HP events"

static func validate_state(package, state: Dictionary) -> String:
	var component = state.extensions.get(KEY)
	if not used(package.world):
		return "unrequested progression state" if component != null or state.entities.any(func(a): return a.components.has(KEY)) else ""
	var issue: String = package.schema.validate(SCHEMA, component)
	if not issue.is_empty(): return issue
	if component.kind != "ledger": return "wrong progression state kind"
	var experience: Dictionary = {}; var entities: Dictionary = {}
	for actor in state.entities:
		entities[actor.instance_id] = actor
		var growth: Dictionary = profile(package, actor.definition_id); var value = actor.components.get(KEY)
		if growth.is_empty() != (value == null): return "actor component/profile mismatch"
		if growth.is_empty(): continue
		issue = package.schema.validate(SCHEMA, value)
		if not issue.is_empty(): return issue
		if value.kind != "actor" or value.level != level(growth, int(value.experience)) or value.learned_skills != learned(growth, int(value.experience)): return "level/learned skill lineage mismatch"
		experience[actor.instance_id] = int(growth.initial_experience)
	var seen: Array = []
	for credit in component.credits:
		if credit.execution_id in seen or credit.execution_id not in state.committed_effect_ids: return "duplicate/uncommitted reward execution"
		seen.append(credit.execution_id)
		issue = _trace(package, state, credit, int(credit.step))
		if not issue.is_empty(): return issue
		if credit.living != credit.party.filter(func(id): return id in credit.living): return "final eligibility order/identity"
		var policy: Dictionary = reward(package, credit.encounter_id)
		if credit.outcome == "win" and (credit.living.is_empty() or credit.defeats.size() != policy.enemies.size()): return "victory requires all defeated and living party"
		if credit.outcome == "loss" and not credit.living.is_empty(): return "loss has living party"
		if credit.awards.map(func(a): return a.instance_id) != credit.party.filter(func(id): return experience.has(id)): return "award recipient/order mismatch"
		for award in credit.awards:
			var id: String = award.instance_id; var before: int = experience[id]
			var amount: int = mini(MAX_EXPERIENCE - before, entitlement(credit, policy, id)); var after: int = before + amount
			var growth: Dictionary = profile(package, entities[id].definition_id)
			if [award.before_experience, award.after_experience, award.amount, award.before_level, award.after_level] != [before, after, amount, level(growth, before), level(growth, after)]: return "reward amount/experience lineage mismatch"
			experience[id] = after
	for id in experience:
		if entities[id].components[KEY].experience != experience[id]: return "actor XP differs from initial and committed awards"
	var pending = component.pending; var battle = state.extensions.get(BATTLE)
	var expected: bool = battle != null and not reward(package, battle.encounter_id).is_empty()
	if (pending != null) != expected: return "pending reward/battle mismatch"
	if pending != null:
		if [pending.execution_id, pending.encounter_id, pending.party] != [battle.execution_id, battle.encounter_id, battle.party]: return "pending battle identity mismatch"
		if pending.execution_id in seen or pending.execution_id in state.committed_effect_ids: return "pending reward already committed"
		var executor: Dictionary = state.extensions.get("pal.native.executor", {})
		if [pending.activation, pending.executor_step, pending.node_id] != [executor.get("activation"), int(executor.get("step", 0)) - 1, battle.node_id]: return "pending executor mismatch"
		issue = _trace(package, state, pending, int(battle.step))
		if not issue.is_empty(): return issue
		if battle.enemies.any(func(e): return e.hp == 0 and not pending.defeats.any(func(d): return d.enemy_id == e.instance_id)): return "dead enemy lacks first-defeat credit"
		issue = _current_defeats(state, pending)
		if not issue.is_empty(): return issue
	return ""
