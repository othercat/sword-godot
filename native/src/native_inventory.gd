# SPDX-License-Identifier: MIT
extends RefCounted
const EnemyPhysicalValidator = preload("res://src/native_enemy_physical_validator.gd")
## String identities and bounded stacks; mutations belong to the session candidate.
const CAPABILITY = "inventory.items.v1"
const RULE = "native.inventory-items.v1"
const KEY = "pal.native.inventory"
const Effects = preload("res://src/native_battle_effects.gd")

static func used(content: Dictionary) -> bool:
	return not content.get("item_definitions", []).is_empty() or not content.get("initial_inventory", []).is_empty() or content.nodes.any(func(n): return n.op == "inventory")

static func definitions(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item in content.get("item_definitions", []): result[item.id] = item
	return result

static func definition(package, id: String) -> Dictionary:
	return definitions(package.world).get(id, {})

static func _validate_stacks(stacks: Array, items: Dictionary, ordered: bool = false) -> String:
	var ids: Array = []
	for stack in stacks:
		if stack.item_id in ids or not items.has(stack.item_id): return "unknown or duplicate inventory item"
		ids.append(stack.item_id)
		if stack.count <= 0 or stack.count > items[stack.item_id].max_stack: return "inventory count exceeds authored bounds"
	if ordered:
		var sorted: Array = ids.duplicate(); sorted.sort()
		if ids != sorted: return "saved stacks must be ordered by identity"
	return ""

static func validate_content(package) -> String:
	var items: Dictionary = definitions(package.world)
	if items.size() != package.world.get("item_definitions", []).size(): return "duplicate item identity"
	for item in items.values():
		if item.battle_use != null:
			var issue: String = Effects.validate_definition(item.battle_use)
			if not issue.is_empty(): return issue
	var issue: String = _validate_stacks(package.world.get("initial_inventory", []), items)
	if not issue.is_empty(): return issue
	for node in package.world.nodes:
		if node.op != "inventory": continue
		var ids: Array = []
		for change in node.changes:
			if change.item_id in ids or not items.has(change.item_id): return "unknown or repeated inventory change"
			ids.append(change.item_id)
	return ""

static func initialize(content: Dictionary, state: Dictionary) -> void:
	if not used(content): return
	var stacks: Array = content.get("initial_inventory", []).duplicate(true)
	stacks.sort_custom(func(a, b): return a.item_id < b.item_id)
	state.extensions[KEY] = {"version": 1, "stacks": stacks}

static func count(state: Dictionary, id: String) -> int:
	for stack in state.extensions.get(KEY, {}).get("stacks", []):
		if stack.item_id == id: return int(stack.count)
	return 0

static func change(package, state: Dictionary, changes: Array) -> String:
	if not state.extensions.has(KEY): return "inventory state is missing"
	var values: Dictionary = {}; var items: Dictionary = definitions(package.world); var seen: Dictionary = {}
	for stack in state.extensions[KEY].stacks: values[stack.item_id] = int(stack.count)
	for delta in changes:
		if seen.has(delta.item_id) or not items.has(delta.item_id): return "unknown or repeated inventory change"
		seen[delta.item_id] = true
		var next: int = int(values.get(delta.item_id, 0)) + int(delta.delta)
		if next < 0 or next > items[delta.item_id].max_stack: return "物品数量不足或超过作者设定的上限。"
		values[delta.item_id] = next
	var ids: Array = values.keys(); ids.sort(); var stacks: Array = []
	for id in ids:
		if values[id] > 0: stacks.append({"item_id": id, "count": values[id]})
	state.extensions[KEY].stacks = stacks
	return ""

static func plan(package, state: Dictionary, item_id: String, target: String) -> Dictionary:
	var item: Dictionary = definition(package, item_id)
	if item.is_empty() or item.battle_use == null: return {"error": "此物品不能在战斗中使用。"}
	if count(state, item_id) < 1: return {"error": "物品数量不足。"}
	var result: Dictionary = Effects.plan(state, item.battle_use, target)
	if not result.has("error"): result.item = item
	return result

static func apply(package, state: Dictionary, source: Dictionary, prepared: Dictionary) -> String:
	var item: Dictionary = prepared.item; var cost: int = 1 if item.consumable else 0
	if cost > 0:
		var issue: String = change(package, state, [{"item_id": item.id, "delta": -cost}])
		if not issue.is_empty(): return issue
	state.extensions[Effects.KEY].events.append({"kind": "item_use", "source": source.instance_id, "target": source.instance_id, "amount": cost, "item_id": item.id})
	return Effects.apply(package, state, source, item.battle_use, prepared.targets, "item_id", item.id)

static func validate_state(package, state: Dictionary) -> String:
	if state.extensions.has(KEY) != used(package.world): return "inventory state/capability mismatch"
	if state.extensions.has(KEY):
		var issue: String = _validate_stacks(state.extensions[KEY].stacks, definitions(package.world), true)
		if not issue.is_empty(): return issue
	var battle: Dictionary = state.extensions.get(Effects.KEY, {})
	if battle.is_empty() or not battle.events.any(func(e): return e.has("item_id")): return ""
	if battle.events[0].kind != "item_use" and package.world.extensions.has("pal.native.enemy-physical"):
		return EnemyPhysicalValidator.validate(package,state,func(a): return Effects.Statuses.Progression.stats(package,a))
	var item: Dictionary = definition(package, battle.events[0].get("item_id", ""))
	if item.is_empty() or item.battle_use == null: return "unknown or unusable item result"
	var remaining: int = count(state, item.id)
	if (remaining + 1 > item.max_stack if item.consumable else remaining < 1): return "post-use count cannot follow a legal inventory debit"
	return Effects.validate_events(package, state, item.battle_use, "item_id", item.id, "item_use", 1 if item.consumable else 0)
