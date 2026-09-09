# SPDX-License-Identifier: MIT
extends RefCounted
## Receipt admission, separate from execution. Historical growth/loadout inputs are
## bounded evidence; pending battles additionally bind them to actual actor state.
const E = preload("res://src/native_enemy_physical.gd")
const Contract = preload("res://src/native_schema.gd")
const Effects = preload("res://src/native_battle_effects.gd")

static func validate(package, state: Dictionary, stats: Callable) -> String:
	var component = state.extensions.get(E.KEY); var content: Dictionary = package.world
	if not E.used(content): return "unexpected enemy physical state" if component != null else ""
	var issue: String = package.schema.validate(E.SCHEMA,component)
	if not issue.is_empty(): return issue
	if component.kind != "state": return "wrong enemy physical state kind"
	for pair in [[E.PHYSICAL,"pal.native.player-physical.v1"]]+([[E.TRAINING,"pal.native.training.v1"]] if content.extensions.has(E.TRAINING) else []):
		issue = package.schema.validate(pair[1],state.extensions.get(pair[0]))
		if not issue.is_empty(): return issue
		if state.extensions[pair[0]].kind != "state": return "enemy physical dependency requires state kind"
	var training: bool = content.extensions.has(E.TRAINING); var credits: Dictionary = {}
	for credit in state.extensions.get(E.TRAINING,{}).get("credits",[]): credits[credit.execution_id] = credit
	var cursor: int = 0; var seen: Array = []
	for row in E.records(state):
		var pending: bool = row.outcome.is_empty(); var identity: String = row.execution_id
		if identity in seen or row.rng_start != cursor: return "duplicate battle or unowned inter-battle random gap"
		seen.append(identity)
		var encounters: Array = content.encounters.filter(func(e): return e.id == row.encounter_id)
		if encounters.size() != 1 or not row.party.all(func(id): return id in content.roster): return "unknown enemy physical encounter or party"
		var node: Dictionary = package.index.nodes.get(row.node_id,{})
		if node.get("op") != "battle" or node.encounter_id != row.encounter_id: return "enemy physical battle node mismatch"
		if identity != "effect."+Contract.digest(JSON.stringify([state.run_id,row.activation,int(row.executor_step),row.node_id]).to_utf8_buffer()): return "enemy physical execution mismatch"
		if (identity in state.committed_effect_ids) == pending: return "enemy physical commit/outcome mismatch"
		if pending and (component.pending == null or component.pending != row): return "unfinished completed enemy physical battle"
		var last_round: int = 1; var guarding: Array = []; var last_hp: Variant = null
		var statuses: Dictionary = {}; var current: Dictionary = {}
		var status_clock: Dictionary = {"until":{},"source":{},"completed_round":0}
		if pending:
			for actor in state.entities:
				if actor.instance_id in row.party: current[actor.instance_id] = {"stats":stats.call(actor),"equipment":actor.components.get("pal.native.equipment",{}).get("loadout",[]).map(func(i): return i.item_id)}
		for i in range(row.commands.size()):
			var command: Dictionary = row.commands[i]
			if command.step != i+1 or command.source not in row.party or command.rng_before != cursor: return "enemy physical command source, step or random gap"
			if command.round not in [last_round,last_round+1] or (i == 0 and command.round != 1): return "enemy physical round order mismatch"
			if command.round != status_clock.completed_round+1: return "command round differs from completed enemy phases"
			var start: int = row.party.find(row.commands[i-1].source)+1 if i > 0 and row.commands[i-1].round == command.round else 0
			var living: Array = row.party.slice(start).filter(func(id): return command.hp_before.any(func(a): return a.instance_id == id and a.hp > 0))
			if living.is_empty() or living[0] != command.source: return "command skipped or repeated a living party seat"
			if command.round != last_round: guarding.clear()
			last_round = command.round
			if command.action == "guard": guarding.append(command.source)
			var draws: int = command.physical_draws
			if command.action == "attack":
				var config: Dictionary = content.extensions[E.PHYSICAL]
				var allowed: Array = [2,3] if package.index.entities[command.source].definition_id in config.all_target_actor_definitions else [5,9]
				var double: bool = config.double_attack_status_id != null and statuses.get(command.source+"\t"+str(config.double_attack_status_id),0) > 0
				if draws != allowed[int(double)]: return "player draw count differs from active double-attack status"
			else:
				if draws != 0: return "physical draws on another action"
				draws = int(training and command.action in ["skill","escape"])
			if cursor > E.Rng.MAX_DRAWS-draws or command.rng_after_player != cursor+draws: return "player interval mismatch"
			if last_hp != null and not Contract.equal(last_hp,command.hp_before): return "inter-command HP gap"
			issue = _events(package,row,command,guarding,statuses,current,status_clock)
			if not issue.is_empty(): return issue
			var first: Dictionary = command.events[0]
			if first.source != command.source or first.kind != {"skill":"cast","item":"item_use","wait":"status_skip"}.get(command.action,command.action): return "player event identity mismatch"
			if first.get("skill_id") != command.skill_id or first.get("item_id") != command.item_id: return "player ability identity mismatch"
			var merged: Dictionary = E.consume(content,state,identity,int(command.step),int(command.rng_after_player))
			if merged.has("error"): return merged.error
			cursor = merged.end; last_hp = command.hp_after
		if pending:
			var battle = state.extensions.get(E.BATTLE)
			if battle == null: return "enemy physical pending lacks battle"
			for field in ["execution_id","encounter_id","node_id","party"]:
				if not Contract.equal(row[field],battle[field]): return "enemy physical pending identity mismatch"
			if row.commands.size() != battle.step or (not row.commands.is_empty() and not Contract.equal(row.commands[-1].events,battle.events)): return "current command/events mismatch"
			if last_hp != null and not Contract.equal(last_hp,E.health(state)): return "pending HP differs from live state"
			var actual: Dictionary = {}
			for status in battle.get("statuses",[]): actual[status.actor_id+"\t"+status.status_id] = status.stacks
			if not Contract.equal(actual,statuses): return "pending status stacks differ from event history"
			if battle.round != status_clock.completed_round+1: return "pending round differs from completed enemy phases"
			for status in battle.get("statuses",[]):
				var key: String = status.actor_id+"\t"+status.status_id
				if status.remaining_rounds != status_clock.until[key]-status_clock.completed_round or status.source_id != status_clock.source[key]: return "pending status duration/source differs from event history"
		else:
			if last_hp == null: return "completed enemy physical battle lacks command"
			var hp: Dictionary = {}
			for actor in last_hp: hp[actor.instance_id] = actor.hp
			if row.outcome == "win" and not encounters[0].enemies.all(func(e): return hp[e.instance_id] == 0): return "victory has living enemy"
			if row.outcome == "loss" and not row.party.all(func(id): return hp[id] == 0): return "defeat has living ally"
			if row.outcome == "escape" and row.commands[-1].action != "escape": return "escape lacks command"
			if training:
				if not credits.has(identity) or credits[identity].rng_end < cursor: return "missing growth settlement interval"
				cursor = credits[identity].rng_end # Training independently verifies allocation draws.
		if row.rng_end != cursor: return "enemy physical battle random end mismatch"
	if (component.pending != null) != state.extensions.has(E.BATTLE): return "enemy physical pending presence mismatch"
	if training:
		if credits.size() != component.completed.size() or not component.completed.all(func(r): return credits.has(r.execution_id)): return "training/enemy history mismatch"
		for row in E.records(state):
			var other = state.extensions[E.TRAINING].pending if row.outcome.is_empty() else credits[row.execution_id]
			if other == null: return "missing training battle owner"
			for field in ["execution_id","encounter_id","node_id","party","rng_start"]:
				if not Contract.equal(row[field],other[field]): return "training/enemy battle identity mismatch"
			if row.commands.size() != other.actions.size(): return "training/enemy command count mismatch"
			for i in range(row.commands.size()):
				for field in ["step","source","action","skill_id","item_id","physical_draws","rng_before"]:
					if not Contract.equal(row.commands[i][field],other.actions[i][field]): return "training/enemy player metadata mismatch"
				if row.commands[i].rng_after_player != other.actions[i].rng_after: return "training/enemy player interval mismatch"
	var physical: Dictionary = state.extensions[E.PHYSICAL]
	for key in ["last_battle","pending"]:
		var p = physical[key]; var expected = component.pending if key == "pending" else (null if component.completed.is_empty() else component.completed[-1])
		if (p == null) != (expected == null): return "physical/enemy battle presence mismatch"
		if p == null: continue
		for field in ["execution_id","encounter_id","party","rng_start","outcome"]:
			if not Contract.equal(p[field],expected[field]): return "physical/enemy battle identity mismatch"
		var commands: Array = expected.commands.filter(func(c): return c.action == "attack")
		if commands.size() != p.actions.size(): return "physical/enemy action count mismatch"
		for i in range(commands.size()):
			for field in ["step","source","rng_before"]:
				if not Contract.equal(commands[i][field],p.actions[i][field]): return "physical/enemy player metadata mismatch"
			if commands[i].rng_after_player != p.actions[i].rng_after: return "physical/enemy player interval mismatch"
	if E.cursor(state) != cursor: return "global RNG differs from merged history"
	return E.Rng.validate(state.rng,int(content.extensions[E.RANDOM].seed),1)

static func _skill(content: Dictionary, id: Variant) -> Dictionary:
	for skill in content.get("skill_definitions", []):
		if skill.id == id: return skill
	return {}

static func _owners(package, row: Dictionary, command: Dictionary) -> String:
	var battle: Dictionary = {"party":row.party,"enemies":package.world.encounters.filter(func(e): return e.id == row.encounter_id)[0].enemies,"events":command.events,"step":command.step}
	var proxy: Dictionary = {"extensions":{E.BATTLE:battle,E.PHYSICAL:{},E.KEY:{}}}
	var partition: Dictionary = Effects.action_blocks(proxy)
	if partition.has("error"): return partition.error
	for block in partition.blocks:
		var first: Dictionary = block[0]; var issue: String = ""
		if first.kind == "cast":
			var spec: Dictionary = _skill(package.world,first.skill_id)
			if spec.is_empty(): return "unknown historical skill"
			issue = Effects.validate_events(package,proxy,spec,"skill_id",spec.id,"cast",int(spec.mp_cost),block)
		elif first.kind == "item_use":
			var spec: Dictionary = E.item_definition(package.world,first.item_id)
			if spec.is_empty() or spec.battle_use == null: return "unknown historical item"
			issue = Effects.validate_events(package,proxy,spec.battle_use,"item_id",spec.id,"item_use",int(spec.consumable),block)
		if not issue.is_empty(): return issue
	return ""

static func _events(package, row: Dictionary, command: Dictionary, guarding: Array, statuses: Dictionary, current: Dictionary, status_clock: Dictionary) -> String:
	var issue: String = _owners(package,row,command)
	if not issue.is_empty(): return issue
	var enemies: Array = package.world.encounters.filter(func(e): return e.id == row.encounter_id)[0].enemies
	var enemy_ids: Array = enemies.map(func(e): return e.instance_id); var ids: Array = row.party+enemy_ids
	if command.hp_before.map(func(a): return a.instance_id) != ids or command.hp_after.map(func(a): return a.instance_id) != ids: return "health identities/order mismatch"
	var hp: Dictionary = {}
	for actor in command.hp_before: hp[actor.instance_id] = actor.hp
	if hp[command.source] <= 0: return "dead player issued command"
	var starts: Array = []; var receipts: Dictionary = {}; var previous: int = -1
	for i in range(command.events.size()):
		if command.events[i].kind == "attack" and command.events[i].source in enemy_ids: starts.append(i)
	if not Contract.equal(starts,command.enemy_actions.map(func(a): return a.event_start)): return "missing, duplicate or orphan enemy attack"
	for action in command.enemy_actions:
		var index: int = enemy_ids.find(action.source)
		if index <= previous: return "duplicate or unordered enemy attack"
		previous = index; receipts[int(action.event_start)] = action
	var gear: Array = package.world.extensions.get("pal.native.equipment",{}).get("items",[]).map(func(i): return i.item_id)
	var cause: Dictionary = {}; var enemy_cursor: int = 0; var enemy_phase: bool = false; var round_tail: bool = false
	for index in range(command.events.size()):
		var event: Dictionary = command.events[index]
		if event.source not in ids or event.target not in ids: return "unknown event instance"
		if event.kind in ["status_damage","status_heal"] or (event.kind == "status_clear" and event.reason == "expired"):
			if not round_tail:
				if not enemy_phase or enemy_ids.slice(enemy_cursor).any(func(id): return hp[id] > 0) or not row.party.any(func(id): return hp[id] > 0) or not enemy_ids.any(func(id): return hp[id] > 0): return "status round tail precedes complete living enemy phase"
				round_tail = true
		if event.kind in ["attack","cast","status_skip"] and event.source in enemy_ids:
			if not row.party.any(func(id): return hp[id] > 0) or not enemy_ids.any(func(id): return hp[id] > 0): return "enemy action after terminal outcome"
			if not enemy_phase and row.party.slice(row.party.find(command.source)+1).any(func(id): return hp[id] > 0): return "enemy acted before remaining party turns"
			while enemy_cursor < enemy_ids.size() and hp[enemy_ids[enemy_cursor]] == 0: enemy_cursor += 1
			if enemy_cursor >= enemy_ids.size() or event.source != enemy_ids[enemy_cursor]: return "missing living enemy action or repeated seat"
			enemy_cursor += 1; enemy_phase = true
		if receipts.has(index):
			var action: Dictionary = receipts[index]
			if hp[action.source] <= 0 or action.party.map(func(a): return a.instance_id) != row.party: return "dead enemy or party order mismatch"
			for actor in action.party:
				var id: String = actor.instance_id
				if actor.definition_id != package.index.entities[id].definition_id or actor.hp != hp[id] or actor.hp > actor.max_hp: return "action-time identity/HP preimage mismatch"
				if actor.guarding != (id in guarding): return "guard differs from command history"
				var expected: Array = _status_rows(statuses,id)
				if not Contract.equal(actor.statuses,expected): return "status snapshot differs from event lineage"
				if not actor.equipment.all(func(item): return item in gear): return "unknown equipment snapshot"
				if current.has(id):
					var base: Dictionary = current[id].stats
					if actor.max_hp != base.max_hp or actor.defense != _stat(package,int(base.defense),statuses,id,"defense") or actor.equipment != current[id].equipment: return "pending stats/equipment differ from actual actor"
			var definition: String = enemies[enemy_ids.find(action.source)].definition_id
			if action.attack != _stat(package,int(package.index.actor_definitions[definition].combat.attack),statuses,action.source,"attack"): return "enemy attack differs from authored stats/status lineage"
			if not Contract.equal(event,{"kind":"attack","source":action.source,"target":action.target,"amount":action.amount}): return "physical result event mismatch"
			var end: int = index+int(action.event_count)
			if end > command.events.size(): return "attack block exceeds event list"
			var effects: Array = []
			for e in command.events.slice(index+1,end):
				if e.kind not in ["status_clear","damage","heal","revive","status_add","status_remove"] or e.source != action.source or e.target != action.target: return "foreign event in enemy attack block"
				if e.kind != "status_clear": effects.append(e)
			var policy: Dictionary = package.world.extensions[E.KEY].enemy_effects.filter(func(e): return e.definition_id == definition)[0]
			var attached = E.item_definition(package.world,policy.item_id).get("battle_use")
			if action.effect_pass and attached == null: return "attached effect has no authored item"
			var expected_effects: Array = attached.effects if action.effect_pass else []
			if effects.size() != expected_effects.size(): return "attached effect count mismatch"
			for i in range(effects.size()):
				var actual: Dictionary = effects[i]; var spec: Dictionary = expected_effects[i]
				if actual.get("item_id") != policy.item_id or actual.get("effect_index") != i or actual.kind != spec.op: return "attached effect identity/order mismatch"
				if spec.op in ["status_add","status_remove"]:
					if actual.get("status_id") != spec.status_id or actual.amount > package.index.status_definitions[spec.status_id].max_stacks: return "attached status mismatch"
				elif actual.amount > spec.power: return "attached effect exceeds power"
			if end < command.events.size():
				var next: Dictionary = command.events[end]
				if next.kind not in ["attack","cast","status_skip","status_damage","status_heal"] and not (next.kind == "status_clear" and next.reason == "expired"): return "truncated attack event block"
		issue = _status_event(package,event,hp,statuses,cause,status_clock,int(command.round))
		if not issue.is_empty(): return issue
		if event.kind != "status_clear": cause = event
		if event.kind in ["attack","damage","status_damage"]: hp[event.target] -= int(event.amount)
		elif event.kind in ["heal","revive","status_heal"]: hp[event.target] += int(event.amount)
		if hp[event.target] < 0 or hp[event.target] > 1000000: return "HP trace outside Native bounds"
	for actor in command.hp_after:
		if hp[actor.instance_id] != actor.hp: return "HP after command mismatch"
	var escaped: bool = row.outcome == "escape" and command.action == "escape" and command.step == row.commands.size()
	if not escaped and row.party.any(func(id): return hp[id] > 0) and enemy_ids.any(func(id): return hp[id] > 0) and (enemy_phase or not row.party.slice(row.party.find(command.source)+1).any(func(id): return hp[id] > 0)):
		if enemy_ids.slice(enemy_cursor).any(func(id): return hp[id] > 0): return "unfinished living enemy phase"
	if round_tail or (enemy_phase and row.party.any(func(id): return hp[id] > 0) and enemy_ids.any(func(id): return hp[id] > 0)):
		status_clock.completed_round = command.round
		if status_clock.until.values().any(func(until): return until <= command.round): return "missing required status expiration"
	return ""

static func _status_rows(statuses: Dictionary, id: String) -> Array:
	var result: Array = []; var keys: Array = statuses.keys(); keys.sort()
	for key in keys:
		if key.get_slice("\t",0) == id: result.append({"status_id":key.get_slice("\t",1),"stacks":statuses[key]})
	return result

static func _stat(package, base: int, statuses: Dictionary, id: String, field: String) -> int:
	var percent: int = 100
	for status in _status_rows(statuses,id): percent += int(package.index.status_definitions[status.status_id][field+"_percent_delta"])*int(status.stacks)
	return base*maxi(0,percent)/100

static func _status_event(package, event: Dictionary, hp: Dictionary, statuses: Dictionary, cause: Dictionary, status_clock: Dictionary, round_no: int) -> String:
	if not str(event.kind).begins_with("status_"): return ""
	var spec: Dictionary = package.index.status_definitions.get(event.status_id,{})
	if spec.is_empty(): return "unknown status event"
	var key: String = event.target+"\t"+event.status_id; var old: int = statuses.get(key,0)
	match event.kind:
		"status_add":
			if event.amount > 0:
				var owner: Dictionary = E.item_definition(package.world,event.item_id).battle_use if event.has("item_id") else _skill(package.world,event.skill_id)
				var added: int = owner.effects[int(event.effect_index)].stacks
				var expected: int = mini(int(spec.max_stacks),old+added) if spec.reapply == "stack" else added if spec.reapply == "replace" else maxi(old,added)
				if hp[event.target] <= 0 or event.amount != expected: return "status addition differs from authored stack policy"
				statuses[key] = event.amount
				var deadline: int = round_no+int(spec.duration_rounds)-1
				status_clock.until[key] = deadline if spec.reapply == "replace" else maxi(int(status_clock.until.get(key,0)),deadline)
				status_clock.source[key] = event.source
			elif hp[event.target] != 0: return "zero status addition on living actor"
		"status_remove", "status_clear":
			if event.amount != old: return "status removal lacks prior stacks"
			if event.kind == "status_clear" and event.reason == "expired":
				if old <= 0 or status_clock.until.get(key) != round_no or event.source != status_clock.source.get(key): return "status expiration differs from authored duration/source"
			if event.kind == "status_clear" and event.reason != "expired":
				if cause.is_empty() or cause.kind not in ["attack","damage","status_damage"] or cause.amount <= 0 or cause.source != event.source or cause.target != event.target: return "status clear lacks positive damage cause"
				if not spec["remove_on_"+event.reason]: return "status clear policy disabled"
			statuses.erase(key)
			status_clock.until.erase(key); status_clock.source.erase(key)
		"status_skip":
			if old <= 0 or not spec.skip_turn: return "skip lacks active blocking status"
		"status_damage", "status_heal":
			if old <= 0 or event.tick_index >= spec.round_end_effects.size(): return "periodic effect lacks active owner"
			var effect: Dictionary = spec.round_end_effects[int(event.tick_index)]
			if event.source != status_clock.source.get(key): return "periodic source differs from status application"
			if event.kind != "status_"+effect.op or event.amount > int(effect.power)*old: return "periodic effect differs from active stacks"
	return ""
