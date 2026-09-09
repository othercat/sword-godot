# SPDX-License-Identifier: MIT
extends RefCounted
## Player action orchestration. Enemy actions and the existing growth rules remain separate.
const KEY = "pal.native.player-physical"
const SCHEMA = "pal.native.player-physical.v1"
const CAPABILITY = "battle.player-physical.v1"
const PROFILE = "pal98.player-physical.v1"
const BATTLE = "pal.native.battle"
const RandomHit = preload("res://src/native_attack_random.gd")
const Rng = preload("res://src/native_rng.gd")
const Formula = preload("res://src/native_attack_formula.gd")
const Statuses = preload("res://src/native_statuses.gd")

static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)

static func rule(content: Dictionary) -> Variant:
	if not used(content): return null
	var result: Dictionary = {}
	for field in ["profile","double_attack_status_id","all_target_actor_definitions","enemy_stats","target_orders"]:
		result[field] = content.extensions[KEY][field]
	return result

static func all_targets(content: Dictionary, definition_id: String) -> bool:
	return used(content) and definition_id in content.extensions[KEY].all_target_actor_definitions

static func order(content: Dictionary, encounter_id: String) -> Array:
	return content.extensions[KEY].target_orders.filter(func(row): return row.encounter_id == encounter_id)[0].enemy_ids

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var value = package.world.extensions[KEY]
	var issue: String = package.schema.validate(SCHEMA, value)
	if not issue.is_empty(): return issue
	if value.kind != "content" or not RandomHit.used(package.world): return "player physical requires authored random inputs"
	var enemy_ids: Array = []; var encounters: Dictionary = {}
	for encounter in package.world.encounters:
		encounters[encounter.id] = encounter.enemies.map(func(e): return e.instance_id)
		for enemy in encounter.enemies:
			if enemy.definition_id not in enemy_ids: enemy_ids.append(enemy.definition_id)
	var stats: Array = value.enemy_stats.map(func(row): return row.definition_id)
	if stats.size() != enemy_ids.size() or not enemy_ids.all(func(id): return stats.count(id) == 1): return "player physical enemy definitions must be covered exactly once"
	var orders: Array = value.target_orders.map(func(row): return row.encounter_id)
	if orders.size() != encounters.size() or not encounters.keys().all(func(id): return orders.count(id) == 1): return "player physical encounter orders must be covered exactly once"
	for row in value.target_orders:
		if row.enemy_ids.size() != encounters[row.encounter_id].size() or not row.enemy_ids.all(func(id): return id in encounters[row.encounter_id]): return "player physical requires every enemy in the target order"
	var ally_definitions: Array = package.world.roster.map(func(id): return package.index.entities[id].definition_id)
	if not value.all_target_actor_definitions.all(func(id): return id in ally_definitions): return "player physical all-target actor must belong to roster"
	if value.double_attack_status_id != null and not package.index.status_definitions.has(value.double_attack_status_id): return "player physical unknown double-attack status"
	return ""

static func initialize(content: Dictionary, state: Dictionary) -> void:
	if used(content): state.extensions[KEY] = {"schema":SCHEMA,"kind":"state","pending":null,"last_battle":null}

static func begin(content: Dictionary, state: Dictionary) -> void:
	if not used(content): return
	var battle: Dictionary = state.extensions[BATTLE]
	state.extensions[KEY].pending = {"execution_id":battle.execution_id,"encounter_id":battle.encounter_id,"party":battle.party.duplicate(),"rng_start":cursor(state.rng),"actions":[],"outcome":""}

static func settle(content: Dictionary, state: Dictionary, outcome: String) -> void:
	if not used(content): return
	var ledger: Dictionary = state.extensions[KEY].pending
	ledger.outcome = outcome; state.extensions[KEY].last_battle = ledger; state.extensions[KEY].pending = null

static func cursor(rng: Dictionary) -> int: return rng.state.get_slice(":",1).to_int()

static func counts(ledger: Dictionary, source: String) -> Array:
	for i in range(ledger.actions.size()-1,-1,-1):
		var action: Dictionary = ledger.actions[i]
		if action.source == source: return [int(action.health_count),int(action.attack_count)]
	return [0,0]

static func calculate(content: Dictionary, action: Dictionary, definition_id: String, old_health: int, old_attack: int) -> Dictionary:
	var value: Dictionary = content.extensions[KEY]; var hit_rule: Dictionary = content.extensions[RandomHit.KEY]
	var all: bool = all_targets(content,definition_id); var bouts: int = 2 if action.double_attack else 1
	var required: int = (1 if all else 4) * bouts + 1
	if int(action.rng_before) > Rng.MAX_DRAWS-required: return {"error":"随机序列已达到当前规则上限；本次行动保留原状态。"}
	var rng: Dictionary = {"algorithm":Rng.ALGORITHM,"state":"%06x:%d" % [Rng.advance(int(hit_rule.seed),int(action.rng_before)),int(action.rng_before)]}
	var bases: Array = []
	for target in action.targets:
		var enemy: Dictionary = value.enemy_stats.filter(func(row): return row.definition_id == target.definition_id)[0]
		var defense: int = int(target.defense)+(int(enemy.level)+6)*4
		bases.append(Formula.base_damage(int(action.attack),defense)*2 / maxi(1,int(enemy.physical_resistance)))
	var hits: Array = []
	for _bout in range(bouts):
		if all:
			var roll: int = Rng.draw(rng,1).rolls[0]
			var multiplier: int = 3 if roll*6 / Rng.DENOMINATOR == 4 or action.forced_critical else 1
			var row: Array = []
			for i in range(bases.size()): row.append(RandomHit.nearest_even(int(bases[i])*multiplier,1 << i))
			hits.append(row)
		else:
			var rolls: Array = Rng.draw_four(rng).rolls
			hits.append([RandomHit.vary(int(bases[0]),rolls,action.forced_critical,definition_id in hit_rule.bonus_actor_definitions)])
	var health_roll: int = Rng.draw(rng,1).rolls[0]
	return {"hits":hits,"rng_after":cursor(rng),"health_count":RandomHit.nearest_even(old_health*Rng.DENOMINATOR+2*health_roll,Rng.DENOMINATOR),"attack_count":old_attack+1,"rng":rng}

static func apply(package, state: Dictionary, source: Dictionary, target_id: String) -> String:
	var battle: Dictionary = state.extensions[BATTLE]; var value: Dictionary = package.world.extensions[KEY]
	var hit_rule: Dictionary = package.world.extensions[RandomHit.KEY]
	var targets: Array = []
	if all_targets(package.world,source.definition_id):
		if not target_id.is_empty(): return "全体普攻不能指定单个敌人。"
		for id in order(package.world,battle.encounter_id):
			var enemy: Dictionary = battle.enemies.filter(func(row): return row.instance_id == id)[0]
			if enemy.hp > 0: targets.append(enemy)
	else: targets = battle.enemies.filter(func(row): return row.instance_id == target_id and row.hp > 0)
	if targets.is_empty(): return "请选择存活的敌人。"
	var action: Dictionary = {"step":battle.step,"source":source.instance_id,"attack":Statuses.stat(package,state,source,"attack"),
		"forced_critical":hit_rule.critical_status_id != null and not Statuses.find(state,source.instance_id,hit_rule.critical_status_id).is_empty(),
		"double_attack":value.double_attack_status_id != null and not Statuses.find(state,source.instance_id,value.double_attack_status_id).is_empty(),
		"rng_before":cursor(state.rng),"targets":targets.map(func(row): return {"instance_id":row.instance_id,"definition_id":row.definition_id,"hp":row.hp,"defense":Statuses.stat(package,state,row,"defense")})}
	var ledger: Dictionary = state.extensions[KEY].pending; var old: Array = counts(ledger,source.instance_id)
	var result: Dictionary = calculate(package.world,action,source.definition_id,old[0],old[1])
	if result.has("error"): return result.error
	state.rng = result.rng
	for key in ["hits","rng_after","health_count","attack_count"]: action[key] = result[key]
	ledger.actions.append(action)
	# Compute both bouts before any HP or status mutation. Aggregate once per target.
	for i in range(targets.size()):
		var requested: int = 0
		for hit in action.hits: requested += int(hit[i])
		var target: Dictionary = targets[i]; var amount: int = mini(int(target.hp),requested)
		target.hp -= amount
		battle.events.append({"kind":"attack","source":source.instance_id,"target":target.instance_id,"amount":amount})
		Statuses.after_damage(package,state,source.instance_id,target,amount)
	return ""

static func latest(state: Dictionary) -> Dictionary:
	var ledger = state.extensions.get(KEY,{}).get("pending")
	return ledger.actions[-1] if ledger != null and not ledger.actions.is_empty() else {}

static func validate_state(package, state: Dictionary) -> String:
	var component = state.extensions.get(KEY)
	if not used(package.world): return "unexpected player physical state" if component != null else ""
	if component == null: return "missing player physical state"
	var issue: String = package.schema.validate(SCHEMA,component)
	if not issue.is_empty(): return issue
	if component.kind != "state": return "wrong player physical state kind"
	var value: Dictionary = package.world.extensions[KEY]; var hit_rule: Dictionary = package.world.extensions[RandomHit.KEY]
	var end: int = 0
	for key in ["last_battle","pending"]:
		var ledger = component[key]
		if ledger == null: continue
		var encounters: Array = package.world.encounters.filter(func(row): return row.id == ledger.encounter_id)
		if encounters.is_empty() or ledger.party.is_empty() or not ledger.party.all(func(id): return package.index.entities.has(id)): return "physical ledger encounter or party mismatch"
		if key == "last_battle":
			if ledger.outcome not in ["win","loss","escape"] or ledger.execution_id not in state.committed_effect_ids: return "uncommitted physical battle ledger"
		elif not ledger.outcome.is_empty() or (ledger.rng_start != end and not package.world.extensions.has("pal.native.training")): return "physical pending random continuation mismatch"
		var enemies: Dictionary = {}
		for enemy in encounters[0].enemies: enemies[enemy.instance_id] = enemy.definition_id
		var previous_step: int = 0; var rng_cursor: int = ledger.rng_start; var practice: Dictionary = {}
		for action in ledger.actions:
			if action.step <= previous_step or action.source not in ledger.party or (action.rng_before != rng_cursor and (not package.world.extensions.has("pal.native.training") or action.rng_before < rng_cursor)): return "physical action source, step or random gap"
			var definition_id: String = package.index.entities[action.source].definition_id
			var targets: Array = []
			for target in action.targets:
				if target.instance_id in targets or enemies.get(target.instance_id) != target.definition_id: return "physical target identity mismatch"
				if target.hp > package.index.actor_definitions[target.definition_id].max_hp: return "physical target HP exceeds definition"
				targets.append(target.instance_id)
			if all_targets(package.world,definition_id):
				if targets != order(package.world,ledger.encounter_id).filter(func(id): return id in targets): return "physical target order mismatch"
			elif targets.size() != 1: return "single physical action has multiple targets"
			if action.double_attack and value.double_attack_status_id == null: return "unbound double attack"
			if action.forced_critical and hit_rule.critical_status_id == null: return "unbound forced critical"
			var old: Array = practice.get(action.source,[0,0]); var expected: Dictionary = calculate(package.world,action,definition_id,old[0],old[1])
			if expected.has("error"): return expected.error
			for field in ["hits","rng_after","health_count","attack_count"]:
				if action[field] != expected[field]: return "physical hit, random or practice mismatch"
			practice[action.source] = [action.health_count,action.attack_count]
			rng_cursor = action.rng_after; previous_step = action.step
		end = rng_cursor
	if cursor(state.rng) != end and not package.world.extensions.has("pal.native.training"): return "physical random cursor differs from action ledger"
	var pending = component.pending; var battle = state.extensions.get(BATTLE)
	if (pending != null) != (battle != null): return "physical pending battle presence mismatch"
	if pending != null:
		for field in ["execution_id","encounter_id","party"]:
			if pending[field] != battle[field]: return "physical pending identity mismatch"
		var current: Dictionary = latest(state)
		if not current.is_empty() and current.step > battle.step: return "physical action lies after battle"
		var events: Array = battle.events.filter(func(event): return event.kind == "attack" and event.source in battle.party)
		if not events.is_empty():
			if current.is_empty() or current.step != battle.step or events.size() != current.targets.size(): return "missing physical action receipt"
			for i in range(events.size()):
				var requested: int = 0
				for hit in current.hits: requested += int(hit[i])
				if [events[i].source,events[i].target,events[i].amount] != [current.source,current.targets[i].instance_id,mini(int(current.targets[i].hp),requested)]: return "physical aggregate event mismatch"
			var hp: Dictionary = {}
			for enemy in battle.enemies: hp[enemy.instance_id] = enemy.hp
			for i in range(battle.events.size()-1,-1,-1):
				var event: Dictionary = battle.events[i]
				if not hp.has(event.target): continue
				if event.kind in ["attack","damage","status_damage"]: hp[event.target] += int(event.amount)
				elif event.kind in ["heal","revive","status_heal"]: hp[event.target] -= int(event.amount)
			for target in current.targets:
				if hp[target.instance_id] != target.hp: return "physical target HP differs from command preimage"
			if all_targets(package.world,package.index.entities[current.source].definition_id):
				if current.targets.map(func(t): return t.instance_id) != order(package.world,battle.encounter_id).filter(func(id): return hp[id] > 0): return "physical all-target action omits a living enemy"
		elif not current.is_empty() and current.step == battle.step: return "physical receipt without attack event"
	return ""
