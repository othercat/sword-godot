# SPDX-License-Identifier: MIT
extends RefCounted
## Shared target selection and ordered effects for Native skills and items.
const KEY = "pal.native.battle"

static func validate_definition(definition: Dictionary) -> String:
	if definition.target_life == "dead":
		if definition.effects[0].op != "revive" or not definition.effects.slice(1).all(func(e): return e.op == "heal"): return "dead targets require revive followed only by healing"
	elif definition.effects.any(func(e): return e.op == "revive"): return "revive requires dead targets"
	return ""

static func eligible(state: Dictionary, definition: Dictionary) -> Array:
	var battle: Dictionary = state.extensions[KEY]
	var rows: Array = battle.enemies if definition.target_side == "enemy" else battle.party.map(func(id): return state.entities.filter(func(a): return a.instance_id == id)[0])
	return rows.filter(func(a): return a.hp > 0 if definition.target_life == "living" else a.hp == 0)

static func plan(state: Dictionary, definition: Dictionary, target: String) -> Dictionary:
	var targets: Array = eligible(state, definition)
	if definition.target_mode == "single": targets = targets.filter(func(a): return a.instance_id == target)
	elif not target.is_empty(): return {"error": "全体效果不能指定单个目标。"}
	if targets.is_empty(): return {"error": "没有符合存活状态和阵营的目标。"}
	return {"targets": targets}

static func apply(package, state: Dictionary, source: Dictionary, definition: Dictionary, targets: Array, identity_key: String, identity: String) -> void:
	var battle: Dictionary = state.extensions[KEY]
	# Each effect visits the original legal targets, even after an earlier effect changes HP.
	for i in range(definition.effects.size()):
		var effect: Dictionary = definition.effects[i]
		for target in targets:
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
			var event: Dictionary = {"kind": effect.op, "source": source.instance_id, "target": target.instance_id, "amount": amount, "effect_index": i}
			event[identity_key] = identity; battle.events.append(event)

static func validate_events(state: Dictionary, definition: Dictionary, identity_key: String, identity: String, command_kind: String, cost: int) -> String:
	var battle: Dictionary = state.extensions[KEY]; var events: Array = battle.events; var command: Dictionary = events[0]
	if command.kind != command_kind or command.get(identity_key) != identity: return "missing leading use/cast identity"
	if command.source not in battle.party or command.target != command.source or command.amount != cost: return "invalid source or debit result"
	var enemies: Array = battle.enemies.map(func(a): return a.instance_id)
	var side: Array = battle.party if definition.target_side == "ally" else enemies
	var groups: Array = []; var seen: Dictionary = {}; var last: int = -1; var closed: bool = false
	for _effect in definition.effects: groups.append([])
	for event in events.slice(1):
		if event.kind not in ["damage", "heal", "revive"]:
			closed = true
			if event.kind != "attack" or event.source not in enemies or event.target not in battle.party: return "only enemy retaliation may follow effects"
			continue
		if closed or event.get(identity_key) != identity or event.source != command.source: return "interrupted or mismatched effect source"
		var index: int = event.effect_index
		if index < 0 or index >= groups.size() or index < last: return "effect order/reference mismatch"
		last = index
		if event.kind != definition.effects[index].op or event.amount > definition.effects[index].power: return "effect result exceeds definition"
		var key: String = str(index) + ":" + event.target
		if event.target not in side or seen.has(key): return "wrong side or repeated effect target"
		seen[key] = true; groups[index].append(event.target)
	if groups[0].is_empty() or not groups.all(func(group): return group == groups[0]): return "every declared effect requires the same ordered targets"
	if groups[0] != side.filter(func(id): return id in groups[0]): return "effect targets must retain side order"
	if definition.target_mode == "single" and groups[0].size() != 1: return "single effect has multiple targets"
	return ""
