# SPDX-License-Identifier: MIT
extends RefCounted
## Shared target selection and ordered effects for Native skills and items.
const KEY = "pal.native.battle"
const Statuses = preload("res://src/native_statuses.gd")

static func validate_definition(definition: Dictionary) -> String:
	if definition.target_life == "dead":
		if definition.effects[0].op != "revive" or not definition.effects.slice(1).all(func(e): return e.op in ["heal", "status_add", "status_remove"]): return "dead targets require revive followed only by healing/statuses"
	elif definition.effects.any(func(e): return e.op == "revive"): return "revive requires dead targets"
	return ""

static func eligible(state: Dictionary, definition: Dictionary, source_id: String = "") -> Array:
	var battle: Dictionary = state.extensions[KEY]
	var source_is_enemy: bool = not source_id.is_empty() and source_id not in battle.party
	var select_enemies: bool = (definition.target_side == "enemy") != source_is_enemy
	var rows: Array = battle.enemies if select_enemies else battle.party.map(func(id): return state.entities.filter(func(a): return a.instance_id == id)[0])
	return rows.filter(func(a): return a.hp > 0 if definition.target_life == "living" else a.hp == 0)

static func plan(state: Dictionary, definition: Dictionary, target: String, source_id: String = "") -> Dictionary:
	var targets: Array = eligible(state, definition, source_id)
	if definition.target_mode == "single": targets = targets.filter(func(a): return a.instance_id == target)
	elif not target.is_empty(): return {"error": "全体效果不能指定单个目标。"}
	if targets.is_empty(): return {"error": "没有符合存活状态和阵营的目标。"}
	return {"targets": targets}

static func apply(package, state: Dictionary, source: Dictionary, definition: Dictionary, targets: Array, identity_key: String, identity: String) -> String:
	var battle: Dictionary = state.extensions[KEY]
	# Each effect visits the original legal targets, even after an earlier effect changes HP.
	for i in range(definition.effects.size()):
		var effect: Dictionary = definition.effects[i]
		for target in targets:
			var amount: int = 0; var actor: Dictionary = Statuses.Progression.stats(package, target)
			match effect.op:
				"damage":
					amount = maxi(1, int(effect.power) - Statuses.stat(package, state, target, "defense"))
					if target.instance_id in battle.guarding: amount = (amount + 1) >> 1
					amount = mini(amount, int(target.hp)); target.hp -= amount
				"heal":
					if target.hp > 0: amount = mini(int(effect.power), int(actor.max_hp - target.hp)); target.hp += amount
				"revive":
					if target.hp == 0: amount = mini(int(effect.power), int(actor.max_hp)); target.hp = amount
				"status_add":
					var result: Dictionary = Statuses.add(package, state, source, target, effect)
					if result.has("error"): return result.error
					amount = result.amount
				"status_remove": amount = Statuses.remove(state, target.instance_id, effect.status_id)
			var event: Dictionary = {"kind": effect.op, "source": source.instance_id, "target": target.instance_id, "amount": amount, "effect_index": i}
			if effect.op in Statuses.EFFECT_OPS: event.status_id = effect.status_id
			event[identity_key] = identity; battle.events.append(event)
			if effect.op == "damage": Statuses.after_damage(package, state, source.instance_id, target, amount)
	return ""

static func action_blocks(state: Dictionary) -> Dictionary:
	var battle: Dictionary = state.extensions[KEY]
	if battle.events.is_empty() != (battle.step == 0): return {"error": "only initial battle step has empty events"}
	var enemies: Array = battle.enemies.map(func(a): return a.instance_id)
	var blocks: Array = []; var periodic: bool = false; var last_enemy: int = -1
	for event in battle.events:
		if event.kind in ["status_damage", "status_heal"] or (event.kind == "status_clear" and event.reason == "expired"):
			if blocks.is_empty() or last_enemy < 0: return {"error": "round-end effects without enemy phase"}
			periodic = true; continue
		if event.kind == "status_clear":
			if blocks.is_empty(): return {"error": "clear without command"}
			if not periodic: blocks[-1].append(event)
			continue # Statuses validates the immediate damage cause, including the periodic tail.
		if periodic: return {"error": "action/effect after round-end tail"}
		if event.kind == "attack" and state.extensions.has("pal.native.player-physical") and blocks.size() == 1 and last_enemy < 0 and blocks[0][0].kind == "attack" and event.source == blocks[0][0].source:
			if event.target not in enemies: return {"error":"physical target in wrong faction"}
			blocks[0].append(event)
			continue # The player physical validator owns the exact aggregate sequence.
		if event.kind in ["attack", "guard", "escape", "cast", "item_use", "status_skip"]:
			if blocks.is_empty():
				if event.source not in battle.party: return {"error": "first command must belong to party"}
			else:
				if event.kind not in ["attack", "cast", "status_skip"] or event.source not in enemies: return {"error": "invalid enemy command"}
				var index: int = enemies.find(event.source)
				if index <= last_enemy: return {"error": "duplicate or unordered enemy action"}
				last_enemy = index
			if event.kind == "attack":
				if event.target not in (enemies if blocks.is_empty() else battle.party): return {"error": "attack target in wrong faction"}
			elif event.target != event.source: return {"error": "command must target its source identity"}
			blocks.append([event])
		else:
			if event.kind not in ["damage", "heal", "revive", "status_add", "status_remove"] or blocks.is_empty() or blocks[-1][0].kind not in ["cast", "item_use"]: return {"error": "orphan effect"}
			blocks[-1].append(event)
	return {"blocks": blocks}

static func validate_events(package, state: Dictionary, definition: Dictionary, identity_key: String, identity: String, command_kind: String, cost: int, events: Array = []) -> String:
	var battle: Dictionary = state.extensions[KEY]
	if events.is_empty():
		var partition: Dictionary = action_blocks(state)
		if partition.has("error"): return partition.error
		if partition.blocks.is_empty(): return "missing use/cast result"
		events = partition.blocks[0]
	var command: Dictionary = events[0]
	if command.kind != command_kind or command.get(identity_key) != identity: return "missing leading use/cast identity"
	if command.target != command.source or command.amount != cost: return "invalid source or debit result"
	var enemies: Array = battle.enemies.map(func(a): return a.instance_id)
	var allies: Array = battle.party if command.source in battle.party else enemies
	var opponents: Array = enemies if command.source in battle.party else battle.party
	var side: Array = allies if definition.target_side == "ally" else opponents
	var groups: Array = []; var seen: Dictionary = {}; var last: int = -1
	for _effect in definition.effects: groups.append([])
	for event in events.slice(1):
		if event.kind == "status_clear": continue # Immediate cause and policy checked by Statuses.
		if event.get(identity_key) != identity or event.source != command.source: return "interrupted or mismatched effect source"
		var index: int = event.effect_index
		if index < 0 or index >= groups.size() or index < last: return "effect order/reference mismatch"
		last = index
		var effect: Dictionary = definition.effects[index]
		if event.kind != effect.op: return "effect kind mismatch"
		if effect.op in Statuses.EFFECT_OPS:
			if event.status_id != effect.status_id: return "effect status identity mismatch"
			if effect.op == "status_add" and event.amount > 0:
				var spec: Dictionary = Statuses.definition(package, effect.status_id)
				if event.amount < effect.stacks or (spec.reapply == "replace" and event.amount != effect.stacks): return "status reapplication disagrees with declared stacks"
		elif event.amount > effect.power: return "effect result exceeds definition"
		var key: String = str(index) + ":" + event.target
		if event.target not in side or seen.has(key): return "wrong side or repeated effect target"
		seen[key] = true; groups[index].append(event.target)
	if groups[0].is_empty() or not groups.all(func(group): return group == groups[0]): return "every declared effect requires the same ordered targets"
	if groups[0] != side.filter(func(id): return id in groups[0]): return "effect targets must retain side order"
	if definition.target_mode == "single" and groups[0].size() != 1: return "single effect has multiple targets"
	return ""
