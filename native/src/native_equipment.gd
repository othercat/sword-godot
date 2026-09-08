# SPDX-License-Identifier: MIT
extends RefCounted
## Stable equipped item references; the session owns atomic bag/loadout changes.
const KEY = "pal.native.equipment"
const SCHEMA = "pal.native.equipment.v1"
const CAPABILITY = "actors.equipment.v1"

static func used(content: Dictionary) -> bool:
	return content.extensions.has(KEY)

static func definition(content: Dictionary) -> Dictionary:
	return content.extensions.get(KEY, {})

static func items(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row in definition(content).get("items", []): result[row.item_id] = row
	return result

static func loadout(actor: Dictionary) -> Array:
	return actor.get("components", {}).get(KEY, {}).get("loadout", [])

static func eligible(item: Dictionary, definition_id: String) -> bool:
	return item.allowed_definitions.is_empty() or definition_id in item.allowed_definitions

static func validate_loadout(rows: Array, definition_id: String, content: Dictionary, ordered: bool = false) -> String:
	var slots: Array = definition(content).slots.map(func(s): return s.id); var gear: Dictionary = items(content)
	var ids: Array = []
	for row in rows:
		if row.slot_id in ids or row.slot_id not in slots: return "duplicate or unknown equipment slot"
		ids.append(row.slot_id)
		var item: Dictionary = gear.get(row.item_id, {})
		if item.is_empty() or item.slot_id != row.slot_id: return "equipment item does not fit slot"
		if not eligible(item, definition_id): return "actor is not eligible for equipment"
	var sorted: Array = ids.duplicate(); sorted.sort()
	return "saved equipment slots must be ordered by identity" if ordered and ids != sorted else ""

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var issue: String = package.schema.validate(SCHEMA, package.world.extensions[KEY])
	if not issue.is_empty(): return issue
	var component: Dictionary = definition(package.world)
	if component.kind != "content": return "wrong equipment content kind"
	var slots: Array = []; var gear: Dictionary = items(package.world); var catalog: Dictionary = {}
	for row in package.world.get("item_definitions", []): catalog[row.id] = row
	for row in component.slots:
		if row.id in slots: return "duplicate equipment slot"
		slots.append(row.id)
	if gear.size() != component.items.size(): return "duplicate equipment item"
	for row in gear.values():
		if not catalog.has(row.item_id) or catalog[row.item_id].consumable: return "equipment requires nonconsumable item"
		if row.slot_id not in slots: return "unknown item slot"
		for id in row.allowed_definitions:
			if not package.index.actor_definitions.get(id, {}).has("combat"): return "unknown or noncombat equipment eligibility"
	var seen: Array = []; var remaining: Dictionary = {}
	for row in package.world.get("initial_inventory", []): remaining[row.item_id] = int(row.count)
	for row in component.initial_loadouts:
		var actor: Dictionary = package.index.entities.get(row.instance_id, {})
		if row.instance_id in seen or actor.is_empty(): return "duplicate or unknown equipment actor"
		seen.append(row.instance_id)
		if not package.index.actor_definitions[actor.definition_id].has("combat"): return "equipment requires combat actor"
		issue = validate_loadout(row.loadout, actor.definition_id, package.world)
		if not issue.is_empty(): return issue
		for slot in row.loadout:
			remaining[slot.item_id] = int(remaining.get(slot.item_id, 0)) - 1
			if remaining[slot.item_id] < 0: return "initial equipment exceeds shared initial inventory"
	return ""

static func initialize(package, state: Dictionary) -> Array:
	if not used(package.world): return []
	var equipped: Dictionary = {}; var costs: Dictionary = {}
	for row in definition(package.world).initial_loadouts: equipped[row.instance_id] = row.loadout
	for actor in state.entities:
		if not package.index.actor_definitions[actor.definition_id].has("combat"): continue
		var rows: Array = equipped.get(actor.instance_id, []).duplicate(true)
		rows.sort_custom(func(a, b): return a.slot_id < b.slot_id)
		actor.components[KEY] = {"schema": SCHEMA, "kind": "actor", "loadout": rows}
		for row in rows: costs[row.item_id] = int(costs.get(row.item_id, 0)) - 1
	var changes: Array = []
	for id in costs: changes.append({"item_id": id, "delta": costs[id]})
	return changes

static func modify_stats(package, actor: Dictionary, values: Dictionary) -> Dictionary:
	var result: Dictionary = values.duplicate(); var gear: Dictionary = items(package.world)
	for row in loadout(actor):
		for field in gear[row.item_id].modifiers: result[field] += gear[row.item_id].modifiers[field]
	for field in result: result[field] = clampi(int(result[field]), 1 if field in ["max_hp", "attack"] else 0, 1000000)
	return result

static func plan(package, actor: Dictionary, slot_id: String, item_id: String) -> Dictionary:
	if not actor.get("components", {}).has(KEY): return {"error": "这个人物没有装备能力。"}
	if not definition(package.world).slots.any(func(s): return s.id == slot_id): return {"error": "装备槽不存在。"}
	var rows: Array = loadout(actor).duplicate(true); var previous: String = ""
	for row in rows:
		if row.slot_id == slot_id: previous = row.item_id
	if previous == item_id: return {"error": "装备没有变化。"}
	rows = rows.filter(func(r): return r.slot_id != slot_id)
	if not item_id.is_empty(): rows.append({"slot_id": slot_id, "item_id": item_id})
	rows.sort_custom(func(a, b): return a.slot_id < b.slot_id)
	var issue: String = validate_loadout(rows, actor.definition_id, package.world, true)
	if not issue.is_empty(): return {"error": "这件装备不适合此人物或装备槽。"}
	var changes: Array = []
	if not previous.is_empty(): changes.append({"item_id": previous, "delta": 1})
	if not item_id.is_empty(): changes.append({"item_id": item_id, "delta": -1})
	return {"loadout": rows, "changes": changes}

static func validate_state(package, state: Dictionary) -> String:
	if state.extensions.has(KEY): return "equipment belongs to actor components"
	for actor in state.entities:
		var expected: bool = used(package.world) and package.index.actor_definitions.get(actor.definition_id, {}).has("combat")
		if actor.components.has(KEY) != expected: return "equipment actor/capability mismatch"
		if not expected: continue
		var issue: String = package.schema.validate(SCHEMA, actor.components[KEY])
		if not issue.is_empty(): return issue
		if actor.components[KEY].kind != "actor": return "wrong equipment actor kind"
		issue = validate_loadout(loadout(actor), actor.definition_id, package.world, true)
		if not issue.is_empty(): return issue
	for actor in state.extensions.get("pal.native.battle", {}).get("enemies", []):
		if actor.get("components", {}).has(KEY): return "transient enemies cannot carry world equipment"
	return ""
