# SPDX-License-Identifier: MIT
extends "res://tests/test_statuses.gd"
const Presentation = preload("res://src/native_battle_presentation.gd")
var pending: Array = []
var traces: Array = []
var observed: Dictionary = {}
var signals_seen: int = 0
var event_kinds: Dictionary = {}

func click(control: Control) -> void:
	var app = root.get_children().filter(func(node): return node.has_method("_battle_action"))[0]
	if not observed.has(app.get_instance_id()):
		observed[app.get_instance_id()] = true
		# Freeze the app's wall-clock accounting while checking exact snapshots;
		# actual GPU frame waits otherwise legitimately change clock fields.
		app.set_physics_process(false); app.set_process(false); app.battle_view.set_process(false)
		check("graphics.battle-animation.v1" in app.session.package.manifest.required_capabilities, "combined authored status/action package enables committed playback")
		app.session.battle_committed.connect(func(before, result, outcome):
			signals_seen += 1
			pending.append({"before":before.duplicate(true), "result":result.duplicate(true), "outcome":outcome}))
	await super.click(control)
	while not pending.is_empty(): await trace_command(app, pending.pop_front())

func trace_command(app, receipt: Dictionary) -> void:
	var view = app.battle_view; var p = view.presentation; var session = app.session
	var authority: Dictionary = session.state.duplicate(true)
	var previous: Array = receipt.before.extensions[Battle.KEY].statuses.duplicate(true)
	var original_round: int = receipt.before.extensions[Battle.KEY].round
	var settled: bool = false; var timeline: Array = []
	check(view.playing(), "successful transaction has an active display projection")
	for field in ["paused", "modal", "focused"]:
		session.set(field, field != "focused")
		var index: int = p.phase_index; var elapsed: float = p.elapsed_us; var statuses: Array = p.battle.statuses.duplicate(true)
		view._process(1.0)
		check(p.phase_index == index and p.elapsed_us == elapsed and p.battle.statuses == statuses and session.state == authority, "display statuses freeze on " + field)
		session.set(field, field == "focused")
	while view.playing():
		var phase: Dictionary = p.current(); var event: Dictionary = phase.event
		var kind: String = event.get("kind", "")
		var rows: Array = p.battle.statuses.duplicate(true)
		if phase.has("status_snapshot"):
			settled = true
			check(p.consumed == range(receipt.result.events.size()) and rows == receipt.result.statuses and p.battle.round == receipt.result.round, "silent lifetime settlement waits for every original event")
		elif kind == "status_add":
			var current: Array = rows.filter(func(row): return row.actor_id == event.target and row.status_id == event.status_id)
			if event.amount > 0:
				check(current.size() == 1 and current[0].stacks == event.amount and current[0].source_id == event.source and current[0].remaining_rounds == session.package.index.status_definitions[event.status_id].duration_rounds, "status application projects committed total/source/lifetime at its event")
			else: check(rows == previous, "zero application does not overwrite a retained status")
		elif kind in ["status_remove", "status_clear"]:
			check(not rows.any(func(row): return row.actor_id == event.target and row.status_id == event.status_id), "remove/clear is visible at its original event")
		else: check(rows == previous, "damage, healing, poses and metadata cannot silently add/remove/tick statuses")
		if not settled: check(p.battle.round == original_round, "round label does not jump to final authority during events")
		if kind != "": event_kinds[kind] = true
		for id in p.actors:
			var expected: Array = rows.filter(func(row): return row.actor_id == id)
			var exposed: Array = view.display_statuses(id)
			check(exposed == expected and view.describe_statuses(id).size() == expected.size(), "shared UI snapshot and description use the current actor's status rows")
			if not exposed.is_empty(): exposed[0].stacks = 999
			exposed.clear()
			check(view.display_statuses(id) == expected, "consumer mutations cannot alias presentation status rows")
		if kind == "status_add" and traces.is_empty():
			await RenderingServer.frame_post_draw
			check(view._status_regions.any(func(region): return region.text.contains(session.package.index.status_definitions[event.status_id].display_name)), "actual body tooltip keeps the current status during playback")
			root.get_texture().get_image().save_png(output.path_join("status-event-%d.png" % p.consumed.size()))
		timeline.append({"phase":p.phase_index,"event_index":phase.event_index,"kind":kind,"settled":settled,"round":p.battle.round,"statuses":rows})
		previous = rows
		view._process((float(phase.duration_us) - p.elapsed_us + 0.1) / 1000000.0)
	check(settled and p.battle.statuses == receipt.result.statuses and p.consumed == range(receipt.result.events.size()), "completed projection matches exact committed status result once")
	check(session.state == authority, "all display phases preserve authority, RNG, events and inventory")
	for hz in [60, 100, 144, 240]:
		var sampled = Presentation.new(); sampled.begin(session.package, receipt.before, receipt.result, receipt.outcome)
		for _step in range(hz * 120):
			if not sampled.active: break
			sampled.advance(1.0 / hz, true)
		check(not sampled.active and sampled.battle.statuses == receipt.result.statuses and sampled.consumed == range(receipt.result.events.size()), "status playback matches at " + str(hz) + " Hz")
	var jumped = Presentation.new(); jumped.begin(session.package, receipt.before, receipt.result, receipt.outcome); jumped.advance(600.0, true)
	check(not jumped.active and jumped.battle.statuses == receipt.result.statuses and jumped.consumed == p.consumed, "one large delta preserves status order and settlement")
	traces.append({"party":receipt.before.active_party.size(),"step":receipt.result.step,"outcome":receipt.outcome,"timeline":timeline})

func probes(app, opening: Dictionary) -> void:
	# Base probes include capacity/callback rollback. They are synthetic in-memory
	# candidates, separate from the ordinary UI lifecycle traced above.
	super.probes(app, opening)
	pending.clear(); app.battle_view.skip()
	projection_cases(app, opening)
	terminal_cases(app, opening)
	var session = app.session; var view = app.battle_view
	session.state = opening.duplicate(true)
	check(session.battle_command("skill", "", session.package.world.skill_definitions[0].id), "interruptible real status command commits")
	var committed: Dictionary = session.state.duplicate(true)
	var path: String = saves[-1].package_path
	check(app.saves.save(session), "save during status display publishes authority")
	saves.append({"party":opening.active_party.size(),"stage":"during-status-display","package_path":path,"save_path":app.saves.last_path})
	check(app.saves.load_into(session, app.saves.last_path) and not view.playing() and view.presentation.package == null, "load discards status display and its package reference")
	check(session.state.extensions[Battle.KEY] == committed.extensions[Battle.KEY], "load retains exact committed status outcome without replay")
	check(view.display_statuses(committed.extensions[Battle.KEY].enemies[0].instance_id) == Statuses.rows(session.state, committed.extensions[Battle.KEY].enemies[0].instance_id), "post-load UI uses authority statuses")
	pending.clear()
	session.state = opening.duplicate(true)
	check(session.battle_command("skill", "", session.package.world.skill_definitions[0].id), "second real status command starts for skip")
	committed = session.state.duplicate(true); view.skip()
	check(not view.playing() and view.presentation.battle.is_empty() and session.state == committed, "skip drops the projection without reapplying statuses")
	pending.clear()
	check(app.open_package(path) and not view.playing() and view.presentation.package == null, "new package clears all prior status projection history")

func terminal_cases(app, opening: Dictionary) -> void:
	var session = app.session; var package = session.package; var hero: String = opening.active_party[0]
	var specs: Array = package.world.status_definitions
	# Synthetic HP/turn setup isolates two legitimate command boundaries. Neither
	# result increments round, but only the status-tick victory decrements lifetime.
	for periodic in [false, true]:
		pending.clear(); session.state = opening.duplicate(true)
		var b: Dictionary = session.state.extensions[Battle.KEY]
		var status_id: String = specs[5].id if periodic else specs[6].id
		Statuses.add(package,session.state,session.entity(hero),session.entity(hero),{"status_id":status_id,"stacks":1})
		if periodic:
			b.turn = b.party.size() - 1
			for enemy in b.enemies:
				enemy.hp = 1
				Statuses.add(package,session.state,session.entity(hero),enemy,{"status_id":specs[0].id,"stacks":1})
		else:
			for id in b.party: session.entity(id).hp = 1 if id == hero else 0
		var before: Dictionary = session.state.duplicate(true)
		check(session.battle_command("guard") and not session.battle_open() and pending.size() == 1, "terminal command publishes exactly one pre-cleanup receipt")
		if pending.is_empty(): continue
		var receipt: Dictionary = pending[0]
		check(receipt.outcome == ("win" if periodic else "loss") and receipt.result.round == b.round, "enemy early-loss and status-tick win both retain current round number")
		var rows: Array = receipt.result.statuses.filter(func(row):return row.actor_id == hero and row.status_id == status_id)
		var initial: Dictionary = Statuses.find(before,hero,status_id)
		check(rows.size() == 1 and rows[0].remaining_rounds == initial.remaining_rounds - (1 if periodic else 0), "only completed status-tick path decrements lifetime; dead retained status is preserved")
		var committed: Dictionary = session.state.duplicate(true)
		var p = Presentation.new(); p.begin(package,before,receipt.result,receipt.outcome); p.advance(600.0,true)
		check(p.battle.statuses == receipt.result.statuses and session.state == committed, "terminal projection copies precise pre-cleanup statuses without inferring a tick from round")
		app.battle_view.skip()
	pending.clear()

func projection_cases(app, opening: Dictionary) -> void:
	var package = app.session.package; var before: Dictionary = opening.duplicate(true)
	var hero: String = before.active_party[0]; var ally: String = before.active_party[1]
	var specs: Array = package.world.status_definitions; var poison: String = specs[0].id; var replace: String = specs[7].id
	before.extensions[Battle.KEY].statuses = [{"actor_id":hero,"status_id":poison,"source_id":hero,"stacks":3,"remaining_rounds":1}]
	var result: Dictionary = before.extensions[Battle.KEY].duplicate(true)
	result.events = [event("guard",hero,hero,0), event("status_add",ally,hero,3,poison), event("status_add",ally,hero,0,poison), event("status_add",hero,ally,2,replace), event("status_add",ally,ally,1,replace), event("status_remove",hero,hero,3,poison), event("status_remove",hero,hero,0,poison)]
	result.statuses = [{"actor_id":ally,"status_id":replace,"source_id":ally,"stacks":1,"remaining_rounds":1}]
	result.round += 1
	var p = Presentation.new(); p.begin(package,before,result,"")
	check(p.battle.statuses[0].remaining_rounds == 1, "capped status keeps prior lifetime until reapplication")
	next_phase(p)
	check(p.battle.statuses[0].stacks == 3 and p.battle.statuses[0].source_id == ally and p.battle.statuses[0].remaining_rounds == specs[0].duration_rounds, "capped stack application uses total three, refreshes source and duration")
	var old: Array = p.battle.statuses.duplicate(true); next_phase(p)
	check(p.battle.statuses == old, "zero add to dead/persistent target retains its previous row")
	next_phase(p); next_phase(p)
	check(p.battle.statuses.any(func(row):return row.actor_id == ally and row.status_id == replace and row.stacks == 1 and row.source_id == ally), "replace can lower two stacks to one with a new source")
	next_phase(p); old = p.battle.statuses.duplicate(true); next_phase(p)
	check(p.battle.statuses == old and old.size() == 1, "absent remove is harmless")
	check(p.battle.statuses != result.statuses, "silent remaining-round decrement is not shown in advance")
	next_phase(p)
	check(p.battle.statuses == result.statuses and p.battle.round == result.round, "silent no-tick duration settles only after the last event")
	# Double physical bouts contain synthetic hit phases; original clear/add events
	# must stay after both bouts and retain their original indices.
	var enemy: Dictionary = before.extensions[Battle.KEY].enemies[0]
	before.extensions[Battle.KEY].statuses = [{"actor_id":enemy.instance_id,"status_id":poison,"source_id":hero,"stacks":1,"remaining_rounds":2}]
	result = before.extensions[Battle.KEY].duplicate(true)
	result.events = [event("attack",hero,enemy.instance_id,7), event("status_clear",hero,enemy.instance_id,1,poison)]
	result.events[1].reason = "damage"; result.statuses = []
	result.physical_action = {"source":hero,"targets":[{"instance_id":enemy.instance_id,"hp":enemy.hp}],"hits":[[3],[4]]}
	p.begin(package,before,result,"win")
	while p.active and p.current().event_index != 1:
		check(p.battle.statuses == before.extensions[Battle.KEY].statuses, "synthetic physical bouts do not clear status before its original event")
		next_phase(p)
	check(p.active and p.battle.statuses.is_empty() and p.consumed == [0,1], "double-hit aggregate and clear consume original events once")
	next_phase(p)
	check(p.current().has("status_snapshot"), "status settlement precedes terminal victory poses")
	next_phase(p)
	check(p.current().action == "victory" and p.battle.statuses.is_empty(), "terminal pose reads the settled pre-cleanup result")
	p.clear(); check(p.battle.is_empty() and p.actors.is_empty() and p.package == null, "explicit clear releases disposable status snapshots")

func event(kind: String, source: String, target: String, amount: int, status_id: String = "") -> Dictionary:
	var value = {"kind":kind,"source":source,"target":target,"amount":amount}
	if not status_id.is_empty(): value.status_id = status_id
	return value

func next_phase(p) -> void:
	p.advance((float(p.current().duration_us) - p.elapsed_us + 0.1) / 1000000.0, true)

func _finish() -> void:
	for kind in ["status_add","status_remove","status_clear","status_damage","status_heal","status_skip","revive"]:
		check(event_kinds.has(kind), "ordinary UI lifecycle exercises " + kind)
	var report = {"checks":checks,"failed":failed,"saves":saves,"traces":traces,"signals_seen":signals_seen,"physical_input":false,"engine_injected_input":true,"synthetic_in_memory_probes":true,"real_assets":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("status presentation checks=%d traces=%d failed=%d" % [checks.size(),traces.size(),failed]); quit(0 if failed == 0 else 1)
