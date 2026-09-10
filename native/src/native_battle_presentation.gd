# SPDX-License-Identifier: MIT
extends RefCounted
## Disposable display projection of a committed result. Never calls game rules.
const Battle = preload("res://src/native_battle.gd")
const Frames = preload("res://src/native_map_animation.gd")
var package
var context: String = ""
var battle: Dictionary = {}
var actors: Dictionary = {}
var phases: Array = []
var phase_index: int = 0
var elapsed_us: float = 0.0
var active: bool = false
var outcome: String = ""
var consumed: Array = []
var _command_actor: String = "" # Construction context, separate from reaction focus.

static func state_context(state: Dictionary) -> String:
	return "%s:%s:%s" % [state.content_lock, state.session_id, state.timeline_epoch]

func begin(value, before: Dictionary, result: Dictionary, ending: String) -> void:
	clear(); package = value; context = state_context(before); outcome = ending
	battle = before.extensions[Battle.KEY].duplicate(true)
	for id in battle.party: actors[id] = Battle.actor(before, id).duplicate(true)
	for enemy in battle.enemies: actors[enemy.instance_id] = enemy
	var physical: Dictionary = result.get("physical_action", {})
	var enemy_receipts: Dictionary = {}
	for action in result.get("enemy_physical_actions", []): enemy_receipts[int(action.event_start)] = action
	var expanded: bool = false
	for i in range(result.events.size()):
		var event: Dictionary = result.events[i]
		if event.kind in ["attack","cast","item_use","guard","escape","status_skip"]: _command_actor=event.source
		elif event.kind in ["status_damage","status_heal"] or (event.kind=="status_clear" and event.get("reason")=="expired"): _command_actor=""
		var physical_event: bool = event.kind == "attack" and not physical.is_empty() and event.source == physical.source
		if physical_event:
			if not expanded: _physical_phases(physical); expanded = true
			var receipt: Dictionary = event.duplicate(true); receipt.kind = "physical_commit"; receipt.amount = 0
			_add(event.target, "", receipt, i); phases[-1].duration_us = 1
		elif enemy_receipts.has(i) and enemy_receipts[i].outcome in ["block","cover"]:
			_enemy_defense_phases(enemy_receipts[i],event,i)
		elif event.kind == "attack":
			_add(event.source, "attack", {}, -1)
			_add(event.target, "hit", event, i)
		elif event.kind == "cast": _add(event.source, "cast", event, i)
		elif event.kind == "item_use": _add(event.source, "item", event, i)
		elif event.kind in ["damage", "status_damage"]: _add(event.target, "hit", event, i)
		elif event.kind == "guard": _add(event.source, "defend", event, i)
		elif event.kind == "escape":
			_add(event.source, "escape", event, i)
			if ending != "escape": _add(event.source,"idle",{},-1)
		elif event.kind == "status_skip": _add(event.source, "sleep", event, i)
		else: _add(event.target, "", event, i) # Metadata/healing keep the HP-derived base pose.
		if not physical_event and event.kind in ["attack", "damage", "status_damage"] and _final_hp(event.target, result.events.slice(0, i + 1)) == 0:
			_add(event.target, "dead", {}, -1)
	_command_actor=""
	if result.has("statuses"):
		# Duration decrements have no event. Reconcile only after every original
		# event, before terminal poses; this is a display boundary, not a rule tick.
		_add("", "", {}, -1)
		phases[-1].duration_us = 1
		phases[-1].status_snapshot = result.statuses.duplicate(true)
		phases[-1].round_snapshot = result.round
	if not ending.is_empty():
		for id in battle.party:
			if _final_hp(id, result.events) > 0:
				_add(id, "victory" if ending == "win" else ("escape" if ending == "escape" else "idle"), {}, -1)
	active = not phases.is_empty()
	if active: _enter()

func _enemy_defense_phases(action: Dictionary, event: Dictionary, index: int) -> void:
	var cover: bool = action.outcome == "cover"
	var defender: String = action.coverer if cover else action.target
	if cover:
		_add(defender,"defend",{},-1)
		phases[-1].duration_us = 180000
		_defense_metadata(action,"in")
	_add(action.source,"attack",{},-1)
	_defense_metadata(action,"hold")
	_add(defender,"defend",event,index) # The original zero-damage result is consumed once.
	_defense_metadata(action,"hold")
	if cover:
		_add(defender,"defend",{},-1)
		phases[-1].duration_us = 180000
		_defense_metadata(action,"out")

func _defense_metadata(action: Dictionary, motion: String) -> void:
	phases[-1].reaction = action.outcome
	phases[-1].defender_id = action.coverer if action.outcome == "cover" else action.target
	if action.outcome == "cover": phases[-1].cover = {"actor_id":action.coverer,"target_id":action.target,"attacker_id":action.source,"motion":motion}

func pose_for(id: String) -> String:
	var phase: Dictionary = current()
	if phase.get("defender_id") == id: return "defend"
	return str(phase.get("action","")) if phase.get("actor_id") == id else ""

func position_for(id: String, anchors: Dictionary) -> Vector2:
	var origin: Vector2 = anchors[id]; var phase: Dictionary = current()
	var cover: Dictionary = phase.get("cover",{})
	if cover.get("actor_id") != id: return origin
	var target: Vector2 = anchors[cover.target_id]
	var toward: Vector2 = anchors[cover.attacker_id]-target
	# A temporary display offset; the static formation, fitting and authority stay fixed.
	var destination: Vector2 = target+toward.normalized()*minf(8.0,toward.length()/4.0)
	var progress: float = clampf(elapsed_us/float(phase.duration_us),0.0,1.0)
	if cover.motion == "hold": return destination
	return origin.lerp(destination,1.0-progress if cover.motion == "out" else progress)

func _physical_phases(action: Dictionary) -> void:
	# The authoritative per-target settlement is aggregated. Display each already
	# calculated bout, then consume its original event indices exactly once.
	var remaining: Array = action.targets.map(func(t): return int(t.hp))
	for bout in range(action.hits.size()):
		_add(action.source,"attack",{},-1)
		for i in range(action.targets.size()):
			var id: String = action.targets[i].instance_id
			var amount: int = mini(remaining[i],int(action.hits[bout][i])); remaining[i] -= amount
			_add(id,"hit",{"kind":"attack","source":action.source,"target":id,"amount":amount},-1)
			if bout == action.hits.size()-1 and remaining[i] == 0: _add(id,"dead",{},-1)

func _final_hp(id: String, events: Array) -> int:
	var hp: int = actors[id].hp
	for event in events:
		if event.target != id: continue
		if event.kind in ["attack", "damage", "status_damage"]: hp -= int(event.amount)
		elif event.kind in ["heal", "revive", "status_heal"]: hp += int(event.amount)
	return hp

func _add(id: String, action: String, event: Dictionary, index: int) -> void:
	var clip: Dictionary = clip_for(id, action)
	var duration: int = 0
	for frame in clip.get("frames", []): duration += int(frame.duration_us)
	phases.append({"actor_id": id, "action": action, "event": event.duplicate(true), "event_index": index,
		"command_actor_id":_command_actor, "duration_us": duration if duration > 0 else 180000})

func clip_for(id: String, action: String) -> Dictionary:
	if not actors.has(id): return {}
	var definition: Dictionary = package.index.actor_definitions[actors[id].definition_id]
	var set_id = definition.get("battle_sprite_set")
	if set_id == null: return {}
	return Frames.clip_for(package.index.battle_sprite_sets[set_id], action, "upper_left" if id in battle.party else "lower_right")

func _enter() -> void:
	var phase: Dictionary = phases[phase_index]
	if phase.has("status_snapshot"):
		battle.statuses = phase.status_snapshot.duplicate(true)
		battle.round = phase.round_snapshot
	var event: Dictionary = phase.event
	if event.is_empty(): return
	if phase.event_index >= 0: consumed.append(phase.event_index)
	var target: Dictionary = actors[event.target]
	if event.kind in ["attack", "damage", "status_damage"]: target.hp -= int(event.amount)
	elif event.kind in ["heal", "revive", "status_heal"]: target.hp += int(event.amount)
	elif event.kind == "cast": actors[event.source].mp -= int(event.amount)
	elif event.kind == "guard" and event.source not in battle.guarding: battle.guarding.append(event.source)
	elif event.kind in ["status_add", "status_remove", "status_clear"]: _status_event(event)
	# HP is a projection of bounded authoritative amounts, never a second formula.

func _status_event(event: Dictionary) -> void:
	var rows: Array = battle.get("statuses", [])
	var matches: Array = rows.filter(func(row): return row.actor_id == event.target and row.status_id == event.status_id)
	if event.kind != "status_add":
		for row in matches: rows.erase(row)
		return
	# amount is the committed TOTAL stack count, including refresh/replace/cap.
	# Zero means the target could not receive the status; retain any old row.
	if int(event.amount) == 0: return
	var current: Dictionary = matches[0] if not matches.is_empty() else {}
	if current.is_empty():
		current = {"actor_id": event.target, "status_id": event.status_id}
		rows.append(current)
	current.source_id = event.source
	current.stacks = int(event.amount)
	current.remaining_rounds = int(package.index.status_definitions[event.status_id].duration_rounds)
	rows.sort_custom(func(a, b): return a.actor_id < b.actor_id or (a.actor_id == b.actor_id and a.status_id < b.status_id))
	battle.statuses = rows

func advance(delta: float, running: bool) -> bool:
	if not active or not running: return false
	elapsed_us += maxf(0.0, delta) * 1000000.0
	while active and elapsed_us >= phases[phase_index].duration_us:
		elapsed_us -= phases[phase_index].duration_us; phase_index += 1
		if phase_index == phases.size(): active = false; return true
		_enter()
	return false

func current() -> Dictionary:
	return phases[phase_index] if active else {}

func clear() -> void:
	package = null
	context = ""; battle = {}; actors = {}; phases = []; phase_index = 0
	elapsed_us = 0.0; active = false; outcome = ""; consumed = []
	_command_actor = ""
