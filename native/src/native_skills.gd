# SPDX-License-Identifier: MIT
extends RefCounted
## Ordered, deterministic Native skill components. No legacy indices or renderer.
const CAPABILITY = "battle.skills.v1"
const RULE = "native.skill-effects.v1"
const KEY = "pal.native.battle"
const Effects = preload("res://src/native_battle_effects.gd")
const Statuses = preload("res://src/native_statuses.gd")

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
		var issue: String = Effects.validate_definition(skill)
		if not issue.is_empty(): return issue
	for actor in package.world.actor_definitions:
		for id in actor.get("skill_ids", []):
			if not ids.has(id) or not actor.has("combat"): return "loadout requires a declared skill and combat stats"
	return ""

static func eligible(state: Dictionary, skill: Dictionary, source_id: String = "") -> Array:
	return Effects.eligible(state, skill, source_id)

static func plan(package, state: Dictionary, source: Dictionary, skill_id: String, target: String) -> Dictionary:
	if not Statuses.blocking(package, state, source.instance_id, "block_skills").is_empty(): return {"error": "当前状态下不能施放技能。"}
	var skill: Dictionary = definition(package, skill_id)
	if skill.is_empty() or skill_id not in Statuses.Progression.skill_ids(package, source): return {"error": "此角色未掌握该技能。"}
	if source.mp < skill.mp_cost: return {"error": "真气不足。"}
	var result: Dictionary = Effects.plan(state, skill, target, source.instance_id)
	if not result.has("error"): result.skill = skill
	return result

static func apply(package, state: Dictionary, source: Dictionary, prepared: Dictionary) -> String:
	var battle: Dictionary = state.extensions[KEY]; var skill: Dictionary = prepared.skill
	source.mp -= int(skill.mp_cost)
	battle.events.append({"kind": "cast", "source": source.instance_id, "target": source.instance_id, "amount": skill.mp_cost, "skill_id": skill.id})
	return Effects.apply(package, state, source, skill, prepared.targets, "skill_id", skill.id)

static func validate_events(package, state: Dictionary) -> String:
	if not state.extensions.has(KEY): return ""
	var battle: Dictionary = state.extensions[KEY]
	if not battle.events.any(func(e): return e.has("skill_id")): return ""
	var partition: Dictionary = Effects.action_blocks(state)
	if partition.has("error"): return partition.error
	for block in partition.blocks:
		var command: Dictionary = block[0]
		if command.kind != "cast":
			if block.any(func(e): return e.has("skill_id")): return "skill effect without cast"
			continue
		var skill: Dictionary = definition(package, command.get("skill_id", ""))
		var sources: Array = (state.entities + battle.enemies).filter(func(a): return a.instance_id == command.source)
		if skill.is_empty() or sources.is_empty(): return "unknown skill/caster in result"
		if skill.id not in Statuses.Progression.skill_ids(package, sources[0]): return "result caster does not own skill"
		if sources[0].mp + skill.mp_cost > Statuses.Progression.stats(package, sources[0]).max_mp: return "post-cast MP cannot follow a legal debit"
		var issue: String = Effects.validate_events(package, state, skill, "skill_id", skill.id, "cast", int(skill.mp_cost), block)
		if not issue.is_empty(): return issue
	return ""
