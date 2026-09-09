# SPDX-License-Identifier: MIT
extends RefCounted
## Optional single-opponent physical action. Rendering never consumes this stream.
const KEY = "pal.native.enemy-physical"
const SCHEMA = "pal.native.enemy-physical.v1"
const CAPABILITY = "battle.enemy-physical.v1"
const PROFILE = "pal98.enemy-single-physical.v1"
const PHYSICAL = "pal.native.player-physical"
const TRAINING = "pal.native.training"
const RANDOM = "pal.native.attack-random"
const BATTLE = "pal.native.battle"
const Rng = preload("res://src/native_rng.gd")
const Formula = preload("res://src/native_attack_formula.gd")
const RESULT_FIELDS = ["rng_after","target","coverer","outcome","amount","effect_pass","effect_resistance","sampled_slots"]
const RULE_FIELDS = ["profile","weak_hp_below","weak_hp_percent","ineligible_status_ids","protect_status_id","actors","resistance_modifiers","enemy_effects"]

static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func item_definition(content: Dictionary, id: Variant) -> Dictionary:
	for item in content.get("item_definitions", []):
		if item.id == id: return item
	return {}
static func cursor(state: Dictionary) -> int: return str(state.rng.state).get_slice(":",1).to_int()
static func rule(content: Dictionary) -> Variant:
	if not used(content): return null
	var result: Dictionary = {}
	for field in RULE_FIELDS: result[field] = content.extensions[KEY][field]
	return result

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var content: Dictionary = package.world; var value = content.extensions[KEY]
	var issue: String = package.schema.validate(SCHEMA,value)
	if not issue.is_empty(): return issue
	if value.kind != "content" or not content.extensions.has(PHYSICAL): return "enemy physical requires player physical levels and RNG"
	var actors: Array = value.actors.map(func(a): return a.instance_id)
	if actors.size() != content.roster.size() or not content.roster.all(func(id): return actors.count(id) == 1): return "enemy physical requires every roster instance exactly once"
	for actor in value.actors:
		if actor.coverer_id != null and (actor.coverer_id not in actors or actor.coverer_id == actor.instance_id): return "unknown or self coverer"
	var statuses: Dictionary = package.index.status_definitions
	if not value.ineligible_status_ids.all(func(id): return statuses.has(id)): return "unknown guard-ineligible status"
	if value.protect_status_id != null and not statuses.has(value.protect_status_id): return "unknown protect status"
	var equipment: Array = content.extensions.get("pal.native.equipment",{}).get("items",[]).map(func(i): return i.item_id)
	var seen: Array = []
	for row in value.resistance_modifiers:
		var identity: Array = [row.kind,row.id]
		if identity in seen: return "duplicate resistance modifier"
		seen.append(identity)
		if not (statuses.has(row.id) if row.kind == "status" else row.id in equipment): return "unknown resistance modifier"
	var enemies: Array = []
	for encounter in content.get("encounters",[]):
		for enemy in encounter.enemies:
			if enemy.definition_id not in enemies: enemies.append(enemy.definition_id)
	var bindings: Array = value.enemy_effects.map(func(e): return e.definition_id)
	if bindings.size() != enemies.size() or not enemies.all(func(id): return bindings.count(id) == 1): return "enemy physical requires each enemy effect binding"
	for row in value.enemy_effects:
		if row.item_id == null:
			if row.rate != 0: return "absent attached item needs zero rate"
			continue
		var item = item_definition(content,row.item_id).get("battle_use")
		if item == null or item.target_side != "enemy" or item.target_mode != "single": return "attached item requires a single-opponent effect"
	return ""

static func nearest(n: int, d: int) -> int:
	var q: int = n / d; var r: int = n % d
	return q + int(2*r > d or (2*r == d and q % 2 == 1))

static func qualified(value: Dictionary, actor: Dictionary) -> bool:
	if actor.hp <= 0 or actor.statuses.any(func(s): return s.status_id in value.ineligible_status_ids): return false
	return not (actor.hp < value.weak_hp_below and actor.hp*100 <= actor.max_hp*value.weak_hp_percent)

static func resistance(value: Dictionary, actor: Dictionary) -> int:
	var result: int = value.actors.filter(func(a): return a.instance_id == actor.instance_id)[0].effect_resistance
	for modifier in value.resistance_modifiers:
		var count: int = actor.equipment.count(modifier.id) if modifier.kind == "equipment" else 0
		if modifier.kind == "status":
			for status in actor.statuses:
				if status.status_id == modifier.id: count += int(status.stacks)
		result += int(modifier.delta)*count
	return clampi(result,-1000000000,1000000000)

static func calculate(content: Dictionary, action: Dictionary, definition_id: String) -> Dictionary:
	var value: Dictionary = content.extensions[KEY]; var party: Array = action.party
	if not party.any(func(a): return a.hp > 0): return {"error":"no living enemy-attack target"}
	var before: int = action.rng_before
	var rng: Dictionary = {"algorithm":Rng.ALGORITHM,"state":"%06x:%d" % [Rng.advance(int(content.extensions[RANDOM].seed),before),before]}
	var sampled: Array = []; var target: Dictionary = {}
	for _attempt in range(128):
		var selection: Dictionary = Rng.draw(rng,1)
		if selection.has("error"): return selection
		var slot: int = int(selection.rolls[0])*party.size()/Rng.DENOMINATOR
		sampled.append(slot)
		if party[slot].hp > 0: target = party[slot]; break
	if target.is_empty(): return {"error":"目标拒绝采样达到128次上限，本次行动保留原状态。"}
	var block: Dictionary = Rng.draw(rng,1)
	if block.has("error"): return block
	var outcome: String = "hit"; var coverer: Variant = null
	if block.rolls[0] >= 9868951:
		if qualified(value,target): outcome = "block"
		else:
			var selected = value.actors.filter(func(a): return a.instance_id == target.instance_id)[0].coverer_id
			for candidate in party:
				if candidate.instance_id == selected and qualified(value,candidate): outcome = "cover"; coverer = selected
	var amount: int = 0
	if outcome == "hit":
		var draws: Dictionary = Rng.draw(rng,3)
		if draws.has("error"): return draws
		var level: int = content.extensions[PHYSICAL].enemy_stats.filter(func(e): return e.definition_id == definition_id)[0].level
		var attack: int = nearest((int(action.attack)+(level+6)*6)*Rng.DENOMINATOR+int(draws.rolls[0]),Rng.DENOMINATOR)
		var base: int = Formula.base_damage(attack,int(target.defense)*(2 if target.guarding else 1))
		amount = nearest(base*(8*Rng.DENOMINATOR+int(draws.rolls[1]))+8*int(draws.rolls[2]),8*Rng.DENOMINATOR)
		if target.statuses.any(func(s): return s.status_id == value.protect_status_id): amount /= 2
		amount = mini(amount,int(target.hp))
	var tail: Dictionary = Rng.draw(rng,2) # Both draws occur for hit, block, cover and zero rate.
	if tail.has("error"): return tail
	var policy: Dictionary = value.enemy_effects.filter(func(e): return e.definition_id == definition_id)[0]
	var effect_resistance: int = resistance(value,target)
	var gates: PackedFloat32Array = [float(tail.rolls[0])*10/Rng.DENOMINATOR,float(tail.rolls[1])*100/Rng.DENOMINATOR]
	return {"rng":rng,"rng_after":str(rng.state).get_slice(":",1).to_int(),"target":target.instance_id,"coverer":coverer,"outcome":outcome,"amount":amount,
		"effect_pass":outcome == "hit" and policy.rate > gates[0] and gates[1] > effect_resistance,"effect_resistance":effect_resistance,"sampled_slots":sampled}

static func initialize(content: Dictionary, state: Dictionary) -> void:
	if used(content): state.extensions[KEY] = {"schema":SCHEMA,"kind":"state","pending":null,"completed":[]}

static func begin(content: Dictionary, state: Dictionary) -> String:
	if not used(content): return ""
	if state.extensions[KEY].completed.size() >= 10000: return "enemy physical battle history budget exceeded"
	var battle: Dictionary = state.extensions[BATTLE]; var executor: Dictionary = state.extensions["pal.native.executor"]
	# The executor has already advanced past the battle node.
	state.extensions[KEY].pending = {"execution_id":battle.execution_id,"encounter_id":battle.encounter_id,"node_id":battle.node_id,"activation":executor.activation,
		"executor_step":int(executor.step)-1,"party":battle.party.duplicate(),"rng_start":cursor(state),"rng_end":cursor(state),"outcome":"","commands":[]}
	return ""

static func health(state: Dictionary) -> Array:
	if not state.extensions.has(BATTLE): return []
	var battle: Dictionary = state.extensions[BATTLE]; var actors: Array = state.entities+battle.enemies
	return (battle.party+battle.enemies.map(func(e): return e.instance_id)).map(func(id): return {"instance_id":id,"hp":actors.filter(func(a): return a.instance_id == id)[0].hp})

static func note_player(content: Dictionary, state: Dictionary, action: String, source: String, skill: String, item: String, before: int, hp: Array) -> void:
	if not used(content): return
	var battle: Dictionary = state.extensions[BATTLE]; var end: int = cursor(state)
	state.extensions[KEY].pending.commands.append({"step":battle.step,"round":battle.round,"source":source,"action":action,"skill_id":null if skill.is_empty() else skill,"item_id":null if item.is_empty() else item,
		"physical_draws":end-before if action == "attack" else 0,"rng_before":before,"rng_after_player":end,"rng_after":end,"hp_before":hp,"hp_after":[],"enemy_actions":[],"events":[]})

static func snapshot(package, state: Dictionary, stats: Callable, defense: Callable) -> Array:
	var battle: Dictionary = state.extensions[BATTLE]; var result: Array = []
	for id in battle.party:
		var actor: Dictionary = state.entities.filter(func(a): return a.instance_id == id)[0]
		var statuses: Array = []
		for status in battle.get("statuses",[]):
			if status.actor_id == id: statuses.append({"status_id":status.status_id,"stacks":status.stacks})
		result.append({"instance_id":id,"definition_id":actor.definition_id,"hp":actor.hp,"max_hp":stats.call(actor).max_hp,"defense":defense.call(actor),
			"guarding":id in battle.guarding,"statuses":statuses,"equipment":actor.components.get("pal.native.equipment",{}).get("loadout",[]).map(func(i): return i.item_id)})
	return result

static func apply(package, state: Dictionary, source: Dictionary, attack: int, party: Array, after_damage: Callable, attached: Callable) -> String:
	var battle: Dictionary = state.extensions[BATTLE]
	var action: Dictionary = {"source":source.instance_id,"attack":attack,"party":party,"rng_before":cursor(state),"event_start":battle.events.size(),"event_count":0}
	var result: Dictionary = calculate(package.world,action,source.definition_id)
	if result.has("error"): return result.error
	state.rng = result.rng
	for field in RESULT_FIELDS: action[field] = result[field]
	var target: Dictionary = state.entities.filter(func(a): return a.instance_id == action.target)[0]
	target.hp -= int(action.amount)
	battle.events.append({"kind":"attack","source":source.instance_id,"target":action.target,"amount":action.amount})
	after_damage.call(source.instance_id,target,action.amount)
	if action.effect_pass:
		var policy: Dictionary = package.world.extensions[KEY].enemy_effects.filter(func(e): return e.definition_id == source.definition_id)[0]
		var issue: String = attached.call(source,policy.item_id,target) # Frozen target, including HP=0; no inventory debit.
		if not issue.is_empty(): return issue
	action.event_count = battle.events.size()-int(action.event_start)
	state.extensions[KEY].pending.commands[-1].enemy_actions.append(action)
	return ""

static func finish_command(content: Dictionary, state: Dictionary) -> void:
	if not used(content): return
	var ledger: Dictionary = state.extensions[KEY].pending; var command: Dictionary = ledger.commands[-1]
	command.hp_after = health(state); command.events = state.extensions[BATTLE].events.duplicate(true)
	command.rng_after = cursor(state); ledger.rng_end = cursor(state)

static func settle(content: Dictionary, state: Dictionary, outcome: String) -> void:
	if not used(content): return
	var component: Dictionary = state.extensions[KEY]; var row: Dictionary = component.pending
	row.outcome = outcome; row.rng_end = cursor(state); component.completed.append(row); component.pending = null

static func records(state: Dictionary) -> Array:
	var value: Dictionary = state.extensions[KEY]
	return value.completed+([] if value.pending == null else [value.pending])

static func consume(content: Dictionary, state: Dictionary, execution: String, step: int, before: int) -> Dictionary:
	if not used(content): return {"end":before}
	var rows: Array = records(state).filter(func(r): return r.execution_id == execution)
	if rows.size() != 1 or step < 1 or step > rows[0].commands.size(): return {"error":"enemy physical missing or duplicate command owner"}
	var row: Dictionary = rows[0]; var command: Dictionary = row.commands[step-1]
	if command.step != step or command.rng_after_player != before: return {"error":"enemy interval begins outside player end"}
	var enemies: Array = content.encounters.filter(func(e): return e.id == row.encounter_id)[0].enemies
	for action in command.enemy_actions:
		var source: Array = enemies.filter(func(e): return e.instance_id == action.source)
		if source.size() != 1 or action.rng_before != before: return {"error":"enemy source or random gap"}
		var result: Dictionary = calculate(content,action,source[0].definition_id)
		if result.has("error"): return result
		for field in RESULT_FIELDS:
			if result[field] != action[field]: return {"error":"enemy physical recomputed %s mismatch" % field}
		before = result.rng_after
	if before != command.rng_after: return {"error":"unowned enemy random interval"}
	return {"end":before}
