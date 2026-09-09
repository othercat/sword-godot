# SPDX-License-Identifier: MIT
extends RefCounted
## Authored seven-track practice. Gameplay RNG and growth are transaction-owned.
const Rng = preload("res://src/native_rng.gd")
const Contract = preload("res://src/native_schema.gd")
const KEY = "pal.native.training"
const SCHEMA = "pal.native.training.v1"
const CAPABILITY = "actors.secondary-training.v1"
const ESCAPE_CAPABILITY = "battle.escape-check.v1"
const PROFILE = "pal98.secondary-training.v1"
const GROWTH = "pal.native.progression"
const PHYSICAL = "pal.native.player-physical"
const RANDOM = "pal.native.attack-random"
const BATTLE = "pal.native.battle"
const FIELDS = ["max_hp", "max_mp", "attack", "magic_strength", "defense", "dexterity", "flee_rate"]
const LABELS = ["体力", "真气", "武术", "灵力", "防御", "身法", "吉运"]
const RULE_FIELDS = ["profile", "stat_caps", "reward_cap", "level_costs", "profiles", "enemy_dexterity"]
const HEALTH_KINDS = ["attack", "damage", "status_damage", "heal", "revive", "status_heal"]

static func used(content: Dictionary) -> bool: return content.extensions.has(KEY)
static func cursor(state: Dictionary) -> int: return str(state.rng.state).split(":")[1].to_int()
static func profile(content: Dictionary, definition_id: String) -> Dictionary:
	for row in content.extensions.get(KEY, {}).get("profiles", []):
		if row.definition_id == definition_id: return row
	return {}
static func rule(content: Dictionary) -> Variant:
	if not used(content): return null
	var result: Dictionary = {}
	for field in RULE_FIELDS: result[field] = content.extensions[KEY][field].duplicate(true) if content.extensions[KEY][field] is Array else content.extensions[KEY][field]
	return result
static func initial(value: Dictionary) -> Dictionary:
	return {"schema": SCHEMA, "kind": "actor", "levels": value.initial_levels.duplicate(), "experience": value.initial_experience.duplicate(), "gains": [0,0,0,0,0,0,0]}

static func validate_content(package) -> String:
	if not used(package.world): return ""
	var value: Dictionary = package.world.extensions[KEY]
	var issue: String = package.schema.validate(SCHEMA, value)
	if not issue.is_empty(): return issue
	if value.kind != "content": return "training requires content configuration"
	if not package.world.extensions.has(PHYSICAL) or not package.world.extensions.has(GROWTH): return "training requires physical actions and primary growth"
	var seen: Array = []; var costs: Array = value.level_costs
	for row in value.profiles:
		if row.definition_id in seen or not package.index.progression_profiles.has(row.definition_id): return "training profile must match primary growth exactly once"
		seen.append(row.definition_id)
		for i in range(7):
			if row.initial_levels[i] >= costs.size() or row.initial_experience[i] >= costs[int(row.initial_levels[i])]: return "initial training level or experience exceeds level cost"
		for i in range(3):
			if row.extra_stats[i] > value.stat_caps[[3,5,6][i]]: return "extra stat exceeds training cap"
		var definition: Dictionary = package.index.actor_definitions[row.definition_id]
		var base: Dictionary = {"max_hp": definition.max_hp, "max_mp": definition.max_mp}; base.merge(definition.combat)
		for level in [base] + package.index.progression_profiles[row.definition_id].levels:
			for i in [0,1,2,4]:
				if level[FIELDS[i]] > value.stat_caps[i]: return "primary growth stat exceeds training cap"
	if seen.size() != package.index.progression_profiles.size(): return "training must cover all primary growth profiles"
	for id in package.world.roster:
		if package.index.entities[id].definition_id not in seen: return "every roster member needs primary growth and training"
	var enemies: Array = []
	for encounter in package.world.get("encounters", []):
		for enemy in encounter.enemies:
			if enemy.definition_id not in enemies: enemies.append(enemy.definition_id)
	seen = []
	for enemy in value.enemy_dexterity:
		if enemy.definition_id in seen or enemy.definition_id not in enemies: return "duplicate or unknown enemy dexterity"
		seen.append(enemy.definition_id)
	if seen.size() != enemies.size(): return "enemy dexterity must cover every enemy definition"
	for reward in package.world.extensions[GROWTH].rewards:
		if reward.dead_percent != 0 or reward.final_eligibility != "living": return "training requires final-living encounter-total rewards"
	return ""

static func bases(content: Dictionary, definition_id: String, primary: Dictionary) -> Array:
	var result: Dictionary = primary.duplicate(); var extra: Array = profile(content, definition_id).extra_stats
	for i in range(3): result[FIELDS[[3,5,6][i]]] = extra[i]
	return FIELDS.map(func(field): return int(result[field]))

static func modify_stats(package, actor: Dictionary, values: Dictionary) -> Dictionary:
	if not actor.get("components", {}).has(KEY): return values
	var result: Dictionary = values.duplicate(); var base: Array = bases(package.world, actor.definition_id, values)
	for i in range(7): result[FIELDS[i]] = mini(int(package.world.extensions[KEY].stat_caps[i]), int(base[i]) + int(actor.components[KEY].gains[i]))
	return result

static func initialize(package, state: Dictionary) -> void:
	if not used(package.world): return
	state.extensions[KEY] = {"schema": SCHEMA, "kind": "state", "pending": null, "credits": []}
	for actor in state.entities:
		var row: Dictionary = profile(package.world, actor.definition_id)
		if not row.is_empty(): actor.components[KEY] = initial(row)

static func begin(content: Dictionary, state: Dictionary) -> void:
	if not used(content): return
	var battle: Dictionary = state.extensions[BATTLE]; var executor: Dictionary = state.extensions["pal.native.executor"]
	state.extensions[KEY].pending = {"execution_id": battle.execution_id, "encounter_id": battle.encounter_id, "node_id": battle.node_id, "activation": executor.activation, "executor_step": int(executor.step)-1, "party": battle.party.duplicate(), "rng_start": cursor(state), "actions": []}

static func nearest_even(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	var whole: int = numerator / denominator; var remainder: int = numerator % denominator
	return whole + int(remainder * 2 > denominator or (remainder * 2 == denominator and whole % 2 != 0))

static func escape_success(flee: int, difficulty: int, roll: int) -> bool:
	var rounded: PackedFloat32Array = [float(difficulty * roll) / Rng.DENOMINATOR]
	return flee >= rounded[0]

static func difficulty(content: Dictionary, enemies: Array) -> int:
	var levels: Dictionary = {}; var dexterity: Dictionary = {}; var total: int = 0
	for row in content.extensions[PHYSICAL].enemy_stats: levels[row.definition_id] = int(row.level)
	for row in content.extensions[KEY].enemy_dexterity: dexterity[row.definition_id] = int(row.dexterity)
	for enemy in enemies:
		if enemy.hp > 0: total += 4 * (levels[enemy.definition_id] + 6) + dexterity[enemy.definition_id]
	return total

static func flee_stat(content: Dictionary, actor: Dictionary) -> int:
	return mini(int(content.extensions[KEY].stat_caps[6]), int(profile(content, actor.definition_id).extra_stats[2]) + int(actor.components[KEY].gains[6]))

static func attempt(content: Dictionary, state: Dictionary, actor: Dictionary) -> Dictionary:
	var draws: Dictionary = Rng.draw(state.rng, 1)
	if draws.has("error"): return draws
	var flee: int = flee_stat(content, actor); var challenge: int = difficulty(content, state.extensions[BATTLE].enemies); var roll: int = draws.rolls[0]
	return {"effective_flee": flee, "difficulty": challenge, "roll": roll, "success": escape_success(flee, challenge, roll)}

static func action_result(content: Dictionary, action: Dictionary, definition_id: String, previous: Array) -> Dictionary:
	var counts: Array = previous.duplicate(); var end: int = int(action.rng_before); var value: Dictionary = content.extensions[PHYSICAL]
	if action.action == "attack":
		var allowed: Array = [2,3] if definition_id in value.all_target_actor_definitions else [5,9]
		if action.physical_draws not in allowed or (action.physical_draws == allowed[1] and value.double_attack_status_id == null): return {"error": "invalid physical draw count"}
		end += int(action.physical_draws)
		counts[0] = nearest_even(int(counts[0]) * Rng.DENOMINATOR + 2 * Rng.advance(int(content.extensions[RANDOM].seed), end), Rng.DENOMINATOR); counts[2] += 1
	else:
		if action.physical_draws != 0: return {"error": "nonphysical action has physical draws"}
		if action.action == "skill":
			end += 1; counts[1] = nearest_even(int(counts[1]) * Rng.DENOMINATOR + 2 * Rng.advance(int(content.extensions[RANDOM].seed), end), Rng.DENOMINATOR); counts[3] += 1
		elif action.action == "guard": counts[4] += 2
		elif action.action == "escape":
			end += 1
			var escaped = action.escape
			if escaped == null: return {"error": "escape receipt missing"}
			var roll: int = Rng.advance(int(content.extensions[RANDOM].seed), end)
			if escaped.roll != roll or escaped.success != escape_success(int(escaped.effective_flee), int(escaped.difficulty), roll): return {"error": "escape random comparison mismatch"}
			if not escaped.success: counts[6] += 2
	if (action.escape != null) != (action.action == "escape"): return {"error": "escape receipt on another action"}
	if end > Rng.MAX_DRAWS or counts.max() > 1000000: return {"error": "random or practice budget exceeded"}
	return {"counts": counts, "rng_after": end}

static func note(content: Dictionary, state: Dictionary, action: String, source: Dictionary, skill_id: String, item_id: String, before: int, escaped: Variant) -> String:
	if not used(content): return ""
	if action == "skill":
		var draws: Dictionary = Rng.draw(state.rng, 1)
		if draws.has("error"): return draws.error
	var actions: Array = state.extensions[KEY].pending.actions; var counts: Array = [0,0,0,0,0,0,0]
	for previous in actions:
		if previous.source == source.instance_id: counts = previous.counts
	var row: Dictionary = {"step": state.extensions[BATTLE].step, "source": source.instance_id, "action": action, "skill_id": skill_id if action == "skill" else null, "item_id": item_id if action == "item" else null, "physical_draws": cursor(state)-before if action == "attack" else 0, "rng_before": before, "rng_after": cursor(state), "counts": [], "escape": escaped, "enemy_health_events": []}
	var result: Dictionary = action_result(content, row, source.definition_id, counts)
	if result.has("error"): return result.error
	if result.rng_after != cursor(state): return "unrecorded random consumer in player action"
	row.counts = result.counts; actions.append(row)
	return ""

static func health_events(battle: Dictionary) -> Array:
	var result: Array = []; var enemies: Array = battle.enemies.map(func(e): return e.instance_id)
	for event in battle.events:
		if event.target in enemies and event.amount != 0 and event.kind in HEALTH_KINDS:
			result.append({"kind": event.kind, "source": event.source, "target": event.target, "amount": event.amount})
	return result

static func finish_command(content: Dictionary, state: Dictionary) -> void:
	if used(content): state.extensions[KEY].pending.actions[-1].enemy_health_events = health_events(state.extensions[BATTLE])

static func reward_amount(content: Dictionary, credit: Dictionary, policy: Dictionary, identity: String) -> int:
	if credit.outcome != "win" or identity not in credit.living or policy.is_empty(): return 0
	var total: int = 0
	for enemy in policy.enemies: total += int(enemy.experience)
	return mini(int(content.extensions[KEY].reward_cap), total)

static func allocate(value: Dictionary, before: Dictionary, counts: Array, reward: int, base: Array, seed: int, start: int) -> Dictionary:
	var after: Dictionary = before.duplicate(true); var grants: Array = []; var recovery: Array = [0,0]; var end: int = start
	var total: int = 0
	for count in counts: total += int(count)
	total = maxi(1,total); var last: int = value.level_costs.size()-1
	for i in range(7):
		var old: int = int(before.experience[i]); var xp: int = nearest_even(old * total + 2 * reward * int(counts[i]), total)
		grants.append(xp-old); var level: int = int(before.levels[i]); var gain: int = int(before.gains[i])
		while xp >= int(value.level_costs[level]):
			var cost: int = int(value.level_costs[level])
			if level == last:
				xp %= cost; break
			xp -= cost; level += 1
			if end >= Rng.MAX_DRAWS: return {"error": "growth random budget exhausted"}
			end += 1; var amount: int = nearest_even(Rng.DENOMINATOR + Rng.advance(seed,end), Rng.DENOMINATOR)
			gain += mini(maxi(0, int(value.stat_caps[i])-int(base[i])-gain), amount)
			if i < 2: recovery[i] += amount
		after.levels[i] = level; after.experience[i] = xp; after.gains[i] = gain
	return {"after": after, "grants": grants, "recovery": recovery, "rng_after": end}

static func settle(package, state: Dictionary, outcome: String, base_stats: Callable, effective_stats: Callable) -> String:
	if not used(package.world): return ""
	var ledger: Dictionary = state.extensions[KEY]
	if ledger.credits.size() >= 10000: return "training credit history limit; command retained"
	var battle: Dictionary = state.extensions[BATTLE]; var credit: Dictionary = ledger.pending.duplicate(true)
	credit.outcome = outcome; credit.step = battle.step; credit.awards = []
	credit.living = battle.party.filter(func(id): return state.entities.any(func(a): return a.instance_id == id and a.hp > 0))
	var policy: Dictionary = package.index.progression_rewards.get(credit.encounter_id, {})
	for id in battle.party:
		var actor: Dictionary = state.entities.filter(func(a): return a.instance_id == id)[0]
		var before: Dictionary = actor.components[KEY].duplicate(true); var counts: Array = [0,0,0,0,0,0,0]
		for action in credit.actions:
			if action.source == id: counts = action.counts
		var amount: int = reward_amount(package.world,credit,policy,id); var start: int = cursor(state)
		var result: Dictionary = {"after": before, "grants": [0,0,0,0,0,0,0], "recovery": [0,0], "rng_after": start}
		if outcome == "win" and id in credit.living and not policy.is_empty(): result = allocate(package.world.extensions[KEY],before,counts,amount,bases(package.world,actor.definition_id,base_stats.call(actor)),int(package.world.extensions[RANDOM].seed),start)
		if result.has("error"): return result.error
		actor.components[KEY] = result.after.duplicate(true)
		var effective: Dictionary = effective_stats.call(actor)
		actor.hp = mini(int(effective.max_hp), int(actor.hp)+int(result.recovery[0])); actor.mp = mini(int(effective.max_mp), int(actor.mp)+int(result.recovery[1]))
		state.rng.state = "%06x:%d" % [Rng.advance(int(package.world.extensions[RANDOM].seed),int(result.rng_after)), result.rng_after]
		credit.awards.append({"instance_id": id, "reward": amount, "before": before, "after": result.after.duplicate(true), "grants": result.grants, "recovery": result.recovery, "rng_before": start, "rng_after": result.rng_after})
	credit.rng_end = cursor(state); ledger.credits.append(credit); ledger.pending = null
	return ""

static func validate_shapes(package, state: Dictionary) -> String:
	var value = state.extensions.get(KEY)
	if not used(package.world): return "unexpected training state" if value != null or state.entities.any(func(a): return a.components.has(KEY)) else ""
	var issue: String = package.schema.validate(SCHEMA,value)
	if not issue.is_empty(): return issue
	if value.kind != "state": return "wrong training state kind"
	for actor in state.entities:
		var row: Dictionary = profile(package.world, actor.definition_id); var actual = actor.components.get(KEY)
		if row.is_empty() != (actual == null): return "training actor/profile mismatch"
		if actual != null:
			issue = package.schema.validate(SCHEMA,actual)
			if not issue.is_empty(): return issue
			if actual.kind != "actor": return "wrong training actor kind"
	return ""

static func _trace(package, state: Dictionary, row: Dictionary, start: int, expected: Dictionary) -> Dictionary:
	if row.rng_start != start or row.party.is_empty() or row.party.any(func(id): return not expected.has(id)): return {"error": "training party or random continuation mismatch"}
	var node: Dictionary = package.index.nodes.get(row.node_id,{})
	var encounters: Array = package.world.encounters.filter(func(e): return e.id == row.encounter_id)
	if node.get("op") != "battle" or node.encounter_id != row.encounter_id or encounters.is_empty(): return {"error": "training battle node mismatch"}
	var identity: String = "effect." + Contract.digest(JSON.stringify([state.run_id,row.activation,int(row.executor_step),row.node_id]).to_utf8_buffer())
	if row.execution_id != identity: return {"error": "training execution mismatch"}
	var counts: Dictionary = {}; var hp: Dictionary = {}; var maximum: Dictionary = {}; var enemies: Array = []
	for id in row.party: counts[id] = [0,0,0,0,0,0,0]
	for enemy in encounters[0].enemies:
		var copy: Dictionary = enemy.duplicate(); copy.hp = int(package.index.actor_definitions[enemy.definition_id].max_hp)
		enemies.append(copy); hp[enemy.instance_id] = copy.hp; maximum[enemy.instance_id] = copy.hp
	var end: int = start
	for index in range(row.actions.size()):
		var action: Dictionary = row.actions[index]
		if action.step != index+1 or not counts.has(action.source) or action.rng_before != end: return {"error": "training step, source or random gap"}
		if (action.skill_id != null) != (action.action == "skill") or (action.item_id != null) != (action.action == "item"): return {"error": "training ability identity mismatch"}
		if action.action == "skill" and not package.world.get("skill_definitions",[]).any(func(s): return s.id == action.skill_id): return {"error": "unknown training skill"}
		if action.action == "item" and not package.world.get("item_definitions",[]).any(func(s): return s.id == action.item_id and s.battle_use != null): return {"error": "unknown training item"}
		var definition_id: String = package.index.entities[action.source].definition_id
		if action.action == "escape":
			if action.escape == null or not encounters[0].allow_escape: return {"error": "missing or forbidden escape attempt"}
			for enemy in enemies: enemy.hp = hp[enemy.instance_id]
			var historical: Dictionary = {"definition_id": definition_id, "components": {KEY: expected[action.source]}}
			if action.escape.difficulty != difficulty(package.world,enemies) or action.escape.effective_flee != flee_stat(package.world,historical): return {"error": "historical escape inputs differ from health and growth lineage"}
			if action.escape.success and (index != row.actions.size()-1 or row.get("outcome") != "escape"): return {"error": "successful escape must end battle"}
		var changed: Dictionary = action_result(package.world,action,definition_id,counts[action.source])
		if changed.has("error"): return changed
		if not Contract.equal(action.counts,changed.counts) or action.rng_after != changed.rng_after: return {"error": "training practice or random receipt mismatch"}
		counts[action.source] = changed.counts; end = changed.rng_after
		for event in action.enemy_health_events:
			if not hp.has(event.target) or (not hp.has(event.source) and not counts.has(event.source)): return {"error": "unknown health event actor"}
			hp[event.target] += -int(event.amount) if event.kind in ["attack","damage","status_damage"] else int(event.amount)
			if hp[event.target] < 0 or hp[event.target] > maximum[event.target]: return {"error": "historical enemy health outside authored range"}
	if row.get("outcome") == "win":
		if hp.values().any(func(value): return value > 0): return {"error": "victory health history has living enemy"}
	elif row.get("outcome") in ["escape","loss"]:
		if hp.values().all(func(value): return value == 0): return {"error": "nonvictory health history has no living enemy"}
	else:
		for enemy in state.extensions[BATTLE].enemies:
			if hp[enemy.instance_id] != enemy.hp: return {"error": "pending enemy health differs from history"}
	return {"counts": counts, "rng_after": end}

static func validate_state(package, state: Dictionary, base_stats: Callable) -> String:
	var issue: String = validate_shapes(package,state)
	if not issue.is_empty() or not used(package.world): return issue
	var value: Dictionary = package.world.extensions[KEY]; var ledger: Dictionary = state.extensions[KEY]
	var entities: Dictionary = {}; var expected: Dictionary = {}; var primary: Dictionary = {}; var primary_xp: Dictionary = {}; var executions: Dictionary = {}
	for actor in state.entities:
		entities[actor.instance_id] = actor
		var row: Dictionary = profile(package.world, actor.definition_id)
		if not row.is_empty():
			expected[actor.instance_id] = initial(row); primary_xp[actor.instance_id] = package.index.progression_profiles[actor.definition_id].initial_experience
	for credit in state.extensions[GROWTH].credits: primary[credit.execution_id] = credit
	var end: int = 0
	for credit in ledger.credits:
		if executions.has(credit.execution_id) or credit.execution_id not in state.committed_effect_ids: return "duplicate or uncommitted training credit"
		var trace: Dictionary = _trace(package,state,credit,end,expected)
		if trace.has("error"): return trace.error
		end = trace.rng_after; executions[credit.execution_id] = credit
		if credit.step != credit.actions.size() or credit.living != credit.party.filter(func(id): return id in credit.living): return "training final step or eligibility mismatch"
		if (credit.outcome == "win" and credit.living.is_empty()) or (credit.outcome == "loss" and not credit.living.is_empty()): return "training outcome/living mismatch"
		var policy: Dictionary = package.index.progression_rewards.get(credit.encounter_id,{})
		var parent: Dictionary = primary.get(credit.execution_id,{})
		if not policy.is_empty():
			if parent.is_empty(): return "missing primary credit"
			for field in ["party","encounter_id","node_id","outcome","step","living"]:
				if not Contract.equal(parent[field],credit[field]): return "training/primary credit mismatch"
		if credit.awards.map(func(a): return a.instance_id) != credit.party.filter(func(id): return expected.has(id)): return "training award recipient/order mismatch"
		for award in credit.awards:
			var id: String = award.instance_id; var reward: int = reward_amount(package.world,credit,policy,id)
			if not Contract.equal(award.before,expected[id]) or award.rng_before != end or award.reward != reward: return "training reward or before-state mismatch"
			var actor: Dictionary = entities[id].duplicate(true)
			if not parent.is_empty(): primary_xp[id] = parent.awards.filter(func(a): return a.instance_id == id)[0].after_experience
			actor.components[GROWTH].experience = primary_xp[id]
			var result: Dictionary = {"after": expected[id], "grants": [0,0,0,0,0,0,0], "recovery": [0,0], "rng_after": end}
			if credit.outcome == "win" and id in credit.living and not policy.is_empty(): result = allocate(value,expected[id],trace.counts[id],reward,bases(package.world,actor.definition_id,base_stats.call(actor)),int(package.world.extensions[RANDOM].seed),end)
			if result.has("error"): return result.error
			for field in ["after","grants","recovery","rng_after"]:
				if not Contract.equal(award[field],result[field]): return "training allocation or random lineage mismatch"
			expected[id] = result.after.duplicate(true); end = result.rng_after
		if credit.rng_end != end: return "training credit random end mismatch"
		if credit.outcome == "escape" and (credit.actions.is_empty() or credit.actions[-1].action != "escape" or credit.actions[-1].escape == null or not credit.actions[-1].escape.success): return "escape outcome lacks successful attempt"
	for id in expected:
		if not Contract.equal(entities[id].components[KEY],expected[id]): return "actor differs from training lineage"
	for id in primary:
		if not executions.has(id): return "primary credit missing from training history"
	var pending = ledger.pending; var battle = state.extensions.get(BATTLE)
	if (pending != null) != (battle != null): return "pending training/battle mismatch"
	if pending != null:
		if executions.has(pending.execution_id) or pending.execution_id in state.committed_effect_ids: return "pending training already committed"
		for field in ["execution_id","encounter_id","party","node_id"]:
			if not Contract.equal(pending[field],battle[field]): return "pending training identity mismatch"
		var executor: Dictionary = state.extensions["pal.native.executor"]
		if pending.activation != executor.activation or pending.executor_step != executor.step-1: return "pending training executor mismatch"
		var trace: Dictionary = _trace(package,state,pending,end,expected)
		if trace.has("error"): return trace.error
		end = trace.rng_after; executions[pending.execution_id] = pending
		if pending.actions.size() != battle.step: return "missing current command receipt"
		if not pending.actions.is_empty():
			var current: Dictionary = pending.actions[-1]; var command: Dictionary = battle.events[0]
			var kind: String = {"skill":"cast","item":"item_use","wait":"status_skip"}.get(current.action,current.action)
			if command.kind != kind or command.source != current.source or current.skill_id != command.get("skill_id") or current.item_id != command.get("item_id"): return "current training command event mismatch"
			if not Contract.equal(current.enemy_health_events,health_events(battle)): return "current enemy health events differ from battle"
	if cursor(state) != end: return "global random stream differs from command and growth receipts"
	for key in ["last_battle","pending"]:
		var physical = state.extensions[PHYSICAL][key]
		if physical == null: continue
		var row: Dictionary = executions.get(physical.execution_id,{})
		if row.is_empty(): return "physical battle lacks training history"
		for field in ["encounter_id","party","rng_start"]:
			if not Contract.equal(physical[field],row[field]): return "physical/training battle mismatch"
		var commands: Array = row.actions.filter(func(a): return a.action == "attack")
		if commands.size() != physical.actions.size(): return "physical/training action count mismatch"
		for i in range(commands.size()):
			var action: Dictionary = commands[i]; var other: Dictionary = physical.actions[i]
			for field in ["step","source","rng_before","rng_after"]:
				if action[field] != other[field]: return "physical/training action mismatch"
			if action.counts[0] != other.health_count or action.counts[2] != other.attack_count: return "physical/training counts mismatch"
	return ""

static func label(content: Dictionary, actor: Dictionary) -> String:
	if not actor.components.has(KEY): return ""
	var value: Dictionary = actor.components[KEY]; var result: PackedStringArray = []
	for i in range(7): result.append("%s %d级 · %d/%d" % [LABELS[i],value.levels[i],value.experience[i],content.extensions[KEY].level_costs[int(value.levels[i])]])
	return "副经历\n" + "\n".join(result)

static func summary(package, state: Dictionary) -> String:
	var credits: Array = state.extensions.get(KEY,{}).get("credits",[])
	if credits.is_empty(): return ""
	var lines: PackedStringArray = []
	for award in credits[-1].awards:
		var changes: PackedStringArray = []
		for i in range(7):
			if award.after.levels[i] > award.before.levels[i]: changes.append("%s +%d级" % [LABELS[i],award.after.levels[i]-award.before.levels[i]])
		if not changes.is_empty(): lines.append(package.index.actor_definitions[package.index.entities[award.instance_id].definition_id].display_name + "：" + "、".join(changes))
	return "\n".join(lines)
