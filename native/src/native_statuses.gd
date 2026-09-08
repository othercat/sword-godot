# SPDX-License-Identifier: MIT
extends RefCounted
## Battle-scoped, authored status instances. All writes occur on a session candidate.
const CAPABILITY = "battle.statuses.v1"
const RULE = "native.battle-statuses.v1"
const KEY = "pal.native.battle"
const MAX_PER_ACTOR = 16
const EFFECT_OPS = ["status_add", "status_remove"]

static func uses(content: Dictionary) -> Array:
	var result: Array = content.get("skill_definitions", []).duplicate()
	for item in content.get("item_definitions", []):
		if item.battle_use != null: result.append(item.battle_use)
	return result

static func used(content: Dictionary) -> bool:
	return not content.get("status_definitions", []).is_empty() or uses(content).any(func(u): return u.effects.any(func(e): return e.op in EFFECT_OPS))

static func definition(package, id: String) -> Dictionary:
	return package.index.get("status_definitions", {}).get(id, {})

static func validate_content(package) -> String:
	var definitions: Dictionary = {}
	for row in package.world.get("status_definitions", []):
		if definitions.has(row.id): return "duplicate status definition"
		definitions[row.id] = row
	package.index.status_definitions = definitions
	for use in uses(package.world):
		for effect in use.effects:
			if effect.op not in EFFECT_OPS: continue
			if not definitions.has(effect.status_id): return "unknown effect status"
			if effect.op == "status_add" and effect.stacks > definitions[effect.status_id].max_stacks: return "application exceeds authored stack limit"
	return ""

static func rows(state: Dictionary, id: String) -> Array:
	return state.extensions.get(KEY, {}).get("statuses", []).filter(func(r): return r.actor_id == id)

static func find(state: Dictionary, actor_id: String, status_id: String) -> Dictionary:
	for row in rows(state, actor_id):
		if row.status_id == status_id: return row
	return {}

static func actor(state: Dictionary, id: String) -> Dictionary:
	for row in state.entities:
		if row.instance_id == id: return row
	for row in state.extensions[KEY].enemies:
		if row.instance_id == id: return row
	return {}

static func blocking(package, state: Dictionary, id: String, flag: String) -> String:
	for row in rows(state, id):
		if definition(package, row.status_id)[flag]: return row.status_id
	return ""

static func stat(package, state: Dictionary, value: Dictionary, field: String) -> int:
	var base: int = package.index.actor_definitions[value.definition_id].combat[field]
	var percent: int = 100
	for row in rows(state, value.instance_id): percent += int(definition(package, row.status_id)[field + "_percent_delta"]) * int(row.stacks)
	return base * maxi(0, percent) / 100

static func add(package, state: Dictionary, source: Dictionary, target: Dictionary, effect: Dictionary) -> Dictionary:
	if target.hp <= 0: return {"amount": 0}
	var spec: Dictionary = definition(package, effect.status_id)
	var current: Dictionary = find(state, target.instance_id, effect.status_id)
	if current.is_empty():
		if rows(state, target.instance_id).size() >= MAX_PER_ACTOR: return {"error": "此角色的状态种类已达到上限（16种）。"}
		current = {"actor_id": target.instance_id, "status_id": spec.id, "source_id": source.instance_id, "stacks": int(effect.stacks), "remaining_rounds": int(spec.duration_rounds)}
		state.extensions[KEY].statuses.append(current)
	else:
		current.source_id = source.instance_id
		if spec.reapply == "replace":
			current.stacks = int(effect.stacks); current.remaining_rounds = int(spec.duration_rounds)
		else:
			current.stacks = mini(int(spec.max_stacks), int(current.stacks) + int(effect.stacks)) if spec.reapply == "stack" else maxi(int(current.stacks), int(effect.stacks))
			current.remaining_rounds = maxi(int(current.remaining_rounds), int(spec.duration_rounds))
	state.extensions[KEY].statuses.sort_custom(func(a, b): return a.actor_id < b.actor_id or (a.actor_id == b.actor_id and a.status_id < b.status_id))
	return {"amount": int(current.stacks)}

static func remove(state: Dictionary, target: String, id: String) -> int:
	var current: Dictionary = find(state, target, id)
	if current.is_empty(): return 0
	var count: int = current.stacks
	state.extensions[KEY].statuses.erase(current)
	return count

static func after_damage(package, state: Dictionary, source: String, target: Dictionary, amount: int) -> void:
	if amount <= 0: return
	for row in rows(state, target.instance_id):
		var spec: Dictionary = definition(package, row.status_id)
		var reason: String = "death" if target.hp == 0 and spec.remove_on_death else ("damage" if spec.remove_on_damage else "")
		if reason.is_empty(): continue
		var count: int = remove(state, target.instance_id, row.status_id)
		state.extensions[KEY].events.append({"kind": "status_clear", "source": source, "target": target.instance_id, "amount": count, "status_id": row.status_id, "reason": reason})

static func end_round(package, state: Dictionary) -> void:
	var battle: Dictionary = state.extensions[KEY]
	var ids: Array = battle.party + battle.enemies.map(func(e): return e.instance_id)
	for id in ids:
		var target: Dictionary = actor(state, id)
		for row in rows(state, id):
			if find(state, id, row.status_id).is_empty(): continue
			var spec: Dictionary = definition(package, row.status_id)
			for index in range(spec.round_end_effects.size()):
				if target.hp <= 0 or find(state, id, row.status_id).is_empty(): break
				var effect: Dictionary = spec.round_end_effects[index]
				var amount: int = mini(int(effect.power) * int(row.stacks), int(target.hp) if effect.op == "damage" else int(package.index.actor_definitions[target.definition_id].max_hp - target.hp))
				target.hp += -amount if effect.op == "damage" else amount
				battle.events.append({"kind": "status_" + effect.op, "source": row.source_id, "target": id, "amount": amount, "status_id": row.status_id, "tick_index": index})
				if effect.op == "damage": after_damage(package, state, row.source_id, target, amount)
			if find(state, id, row.status_id).is_empty(): continue
			row.remaining_rounds -= 1
			if row.remaining_rounds == 0:
				var count: int = remove(state, id, row.status_id)
				battle.events.append({"kind": "status_clear", "source": row.source_id, "target": id, "amount": count, "status_id": row.status_id, "reason": "expired"})

static func describe(package, state: Dictionary, id: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for row in rows(state, id): result.append("%s×%d · %d轮" % [definition(package, row.status_id).display_name, row.stacks, row.remaining_rounds])
	return result

static func validate_state(package, state: Dictionary) -> String:
	var battle: Dictionary = state.extensions.get(KEY, {})
	if battle.is_empty(): return ""
	if battle.has("statuses") != used(package.world): return "status instance field/capability mismatch"
	var ids: Array = battle.party + battle.enemies.map(func(e): return e.instance_id)
	var keys: Array = []; var counts: Dictionary = {}
	for row in battle.get("statuses", []):
		var key: String = row.actor_id + "\t" + row.status_id
		var spec: Dictionary = definition(package, row.status_id)
		if key in keys or row.actor_id not in ids or row.source_id not in ids or spec.is_empty(): return "duplicate or unknown status instance"
		if row.stacks > spec.max_stacks or row.remaining_rounds > spec.duration_rounds: return "status instance exceeds authored bounds"
		if actor(state, row.actor_id).hp == 0 and spec.remove_on_death: return "death-cleared status retained"
		keys.append(key); counts[row.actor_id] = counts.get(row.actor_id, 0) + 1
		if counts[row.actor_id] > MAX_PER_ACTOR: return "per-actor status budget exceeded"
	var sorted: Array = keys.duplicate(); sorted.sort()
	if sorted != keys: return "status instances require stable identity order"
	var periodic: bool = false; var cause: Dictionary = {}
	var mutations: Dictionary = {}; var tick_counts: Dictionary = {}
	var last_actor: int = -1; var last_status: String = ""
	var completed_round: bool = battle.events.any(func(e): return e.source not in battle.party and e.kind in ["attack", "status_skip"])
	for index in range(battle.events.size()):
		var event: Dictionary = battle.events[index]
		if event.kind not in ["status_clear", "status_damage", "status_heal", "status_skip", "status_add", "status_remove"]:
			if periodic: return "command/retaliation after round-end processing"
			cause = event; continue
		var spec: Dictionary = definition(package, event.status_id)
		if spec.is_empty(): return "unknown event status"
		var key: String = event.target + "\t" + event.status_id
		if event.kind in ["status_damage", "status_heal"] or (event.kind == "status_clear" and event.reason == "expired"):
			var position: int = ids.find(event.target)
			if position < last_actor or (position == last_actor and event.status_id < last_status): return "periodic actor/status order mismatch"
			if mutations.get(key, {}).get("kind") in ["status_remove", "status_clear"]: return "periodic component after status removal"
			last_actor = position; last_status = event.status_id; completed_round = true
		match event.kind:
			"status_add", "status_remove":
				if periodic or event.amount > spec.max_stacks: return "status effect result outside bounds"
				cause = event
			"status_clear":
				if event.amount <= 0 or event.amount > spec.max_stacks: return "invalid cleared stack count"
				if mutations.get(key, {}).get("kind") in ["status_remove", "status_clear"]: return "already removed status cleared again"
				if event.reason == "expired": periodic = true
				else:
					if cause.get("kind") not in ["attack", "damage", "status_damage"] or cause.amount <= 0 or cause.source != event.source or cause.target != event.target: return "clear lacks matching damage cause"
					if not spec["remove_on_" + event.reason]: return "clear policy disabled"
			"status_skip":
				if periodic or not spec.skip_turn or event.amount != 0 or event.source != event.target: return "invalid skipped action"
				if event.source not in (battle.party if index == 0 else battle.enemies.map(func(e): return e.instance_id)): return "skip actor in wrong phase"
				cause = event
			_:
				periodic = true
				if event.tick_index >= spec.round_end_effects.size() or event.tick_index != tick_counts.get(key, 0): return "missing, repeated or unordered periodic component"
				tick_counts[key] = int(event.tick_index) + 1
				var effect: Dictionary = spec.round_end_effects[event.tick_index]
				if event.kind != "status_" + effect.op or event.amount > effect.power * spec.max_stacks: return "periodic result exceeds definition"
				if event.kind == "status_damage" and event.amount <= 0: return "periodic damage must be positive"
				cause = event
		if periodic and battle.round < 2: return "round-end events before first completed round"
		if event.kind in ["status_remove", "status_clear"] or (event.kind == "status_add" and event.amount > 0): mutations[key] = event
	for event in mutations.values():
		var current: Dictionary = find(state, event.target, event.status_id)
		if event.kind != "status_add":
			if not current.is_empty(): return "removed status retained"
			continue
		var remaining: int = int(definition(package, event.status_id).duration_rounds) - (1 if completed_round else 0)
		if current.is_empty() or current.stacks != event.amount or current.source_id != event.source or current.remaining_rounds != remaining: return "status instance disagrees with last application"
	return ""
