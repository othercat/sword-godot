# SPDX-License-Identifier: MIT
extends "res://tests/test_attack_formula.gd"
const E = preload("res://src/native_enemy_physical.gd")
const Training = preload("res://src/native_training.gd")
var last_result: Dictionary = {}
var input_states: Array = []
var observed: Dictionary = {"hit":0,"block":0,"cover":0,"attached":0,"rejection":0,"post_kill":0,"status":0,"enemy_cast":0}

func finish() -> void:
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"saves":saves,"observed":observed,"input_states":input_states,
		"physical_input":false,"full_playthrough":false,"original_combat_parity":false,
		"synthetic_scope":"defense animation projection, clock steps and save tampering; named package variants",
		"real_content_scope":"GUI-authored package, framework menu input, ordered battle rules, attached effects, save/replay and two-battle settlement when configured"},"\t"))
	print("enemy physical window checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)

func choose(prefix: String, exact: bool = false) -> void:
	# Measure after the new menu has completed layout and one actual draw. The
	# framework input is sent once; it is never retried or replaced by a command.
	root.grab_focus()
	await settle(); await RenderingServer.frame_post_draw
	check(root.has_focus() and app.session.focused,"visible test window has focus before "+prefix)
	if not root.has_focus() or not app.session.focused: return
	var control = option(prefix,exact)
	var before: Dictionary = {"prefix":prefix,"focused":app.session.focused,"node":app.session.state.cursor.node_id,
		"rect":str(control.get_global_rect()) if control != null else "missing"}
	await click(control)
	before["after_node"] = app.session.state.cursor.node_id; before["after_focus"] = app.session.focused
	before["error"] = app.session.error; input_states.append(before)

func save(label: String) -> String:
	var ok: bool = app.saves.save(app.session)
	check(ok,label+" saves through production writer: "+app.saves.error)
	if not ok:
		FileAccess.open(output.path_join(label+"-rejected-state.json"),FileAccess.WRITE).store_string(JSON.stringify(app.session.snapshot(),"\t"))
		return ""
	var path: String = app.saves.last_path
	saves.append({"label":label,"package_path":current_package,"save_path":path}); return path

func command(action: String, target: String = "") -> bool:
	var s = app.session; var step: int = s.state.extensions[Battle.KEY].step
	app._battle_action(action,target)
	return not s.battle_open() or s.state.extensions[Battle.KEY].step != step

func attack() -> bool:
	var s = app.session; var battle: Dictionary = s.state.extensions[Battle.KEY]
	var actor: Dictionary = Battle.actor(s.state,battle.party[battle.turn])
	if not Battle.Statuses.blocking(s.package,s.state,actor.instance_id,"skip_turn").is_empty(): return command("wait")
	var target: String = "" if Battle.PlayerPhysical.all_targets(s.package.world,actor.definition_id) else battle.enemies.filter(func(e): return e.hp > 0)[0].instance_id
	return command("attack",target)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args(); if args.size() != 2: quit(2); return
	spec = JSON.parse_string(FileAccess.get_file_as_string(args[0])); current_package = spec.package; output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800); app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false); app.saves = Save.new(output.path_join("saves"))
	check(app.open_package(spec.package),"GUI-authored enemy physical package admitted")
	if app.session.package == null: finish(); return
	var s = app.session; s.set_focus(true,s._last_usec)
	s.battle_committed.connect(func(_before,result,_ending):
		last_result = result.duplicate(true)
		for event in result.events:
			observed.status += int(event.kind == "status_add" and event.amount > 0)
			observed.enemy_cast += int(event.kind == "cast" and event.source not in result.party)
		for action in result.get("enemy_physical_actions",[]):
			observed[action.outcome] += 1
			observed.attached += int(action.effect_pass)
			observed.rejection += int(action.sampled_slots.size() > 1)
			observed.post_kill += int(action.effect_pass and action.amount == action.party.filter(func(a): return a.instance_id == action.target)[0].hp))
	await choose("继续"); await choose("五人"); await choose("继续")
	if failed > 0: finish(); return
	check(s.battle_open() and s.state.active_party.size() == int(spec.party_count),"authored route selects expected traditional party count")
	if not s.battle_open(): finish(); return
	check(app.battle_view.classic_layout().preset == "pal.dream-oblique.v1","enemy rules preserve named Dream geometry")
	var initial: String = save("initial"); var start: Dictionary = s.state.duplicate(true)
	check(not s.battle_command("skill","enemy.missing","skill.missing") and s.state == start,"invalid skill preserves all enemy/player draws and state")
	await defense_projection(start,"block"); await defense_projection(start,"cover")
	await choose("其他",true); await choose("防御",true); await drain()
	check(s.state.extensions[E.KEY].pending.commands[0].action == "guard","traditional menu submits the actual first guard")
	var guard_budget: int = 0
	while s.battle_open() and s.state.extensions[Battle.KEY].round == 1 and guard_budget < 32:
		var source: String = s.state.extensions[Battle.KEY].party[s.state.extensions[Battle.KEY].turn]
		var action: String = "wait" if not Battle.Statuses.blocking(s.package,s.state,source,"skip_turn").is_empty() else "guard"
		if spec.get("mixed_skill",false) and guard_budget == 0:
			var caster: Dictionary = Battle.actor(s.state,source)
			var skill: String = Session.Progression.skill_ids(s.package,caster)[0]
			var definition: Dictionary = Battle.Skills.definition(s.package,skill)
			var target: String = "" if definition.target_mode == "all" else source if definition.target_side == "ally" else s.state.extensions[Battle.KEY].enemies[0].instance_id
			check(s.battle_command("skill",target,skill),"actual skill and enemy physical share one command stream: "+s.error)
		else: check(command(action),"finish party command phase "+str(guard_budget)+": "+s.error)
		await drain(); guard_budget += 1
	check(s.battle_open() and observed.hit+observed.block+observed.cover > 0,"actual enemy phase produces physical receipts")
	if not s.battle_open(): finish(); return
	check(s.state.extensions["pal.native.inventory"] == start.extensions["pal.native.inventory"],"enemy attached items do not debit player inventory")
	var round_save: String = save("enemy-round"); var round_state: Dictionary = s.state.duplicate(true)
	var fresh = Session.new(); check(fresh.activate(s.package) and Save.new(output.path_join("fresh")).load_into(fresh,round_save),"fresh runtime restores enemy and training intervals")
	for defect in ["receipt","target","equipment","defense","round","rng","hp","orphan"]:
		var bad: Dictionary = round_state.duplicate(true); var record: Dictionary = bad.extensions[E.KEY].pending.commands[-1]
		var first: Dictionary = record.enemy_actions[0]
		match defect:
			"receipt": record.enemy_actions.clear()
			"target": first.target = "instance.missing"
			"equipment": first.party[0].equipment.append("item.missing")
			"defense": first.party[0].defense += 1
			"round": record.round += 1
			"rng": record.rng_after += 1
			"hp": first.party[0].hp -= 1
			"orphan": bad.extensions[E.KEY].pending.commands[0].events.append({"kind":"damage","source":start.active_party[0],"target":start.extensions[Battle.KEY].enemies[0].instance_id,"amount":1,"item_id":"item.missing","effect_index":0})
		check(not s.restore(bad) and s.state == round_state,"tampered history rejects atomically "+defect)
	check(attack(),"continued player attack after enemy draws: "+s.error); await drain()
	var after: Dictionary = s.state.duplicate(true); check(app.saves.load_into(s,round_save) and attack(),"same command replays from saved RNG"); await drain()
	FileAccess.open(output.path_join("continued.json"),FileAccess.WRITE).store_string(JSON.stringify(after,"\t"))
	FileAccess.open(output.path_join("replayed.json"),FileAccess.WRITE).store_string(JSON.stringify(s.state,"\t"))
	var continued_extensions: Dictionary = after.extensions.duplicate(true); continued_extensions.erase("pal.native.timing")
	var replayed_extensions: Dictionary = s.state.extensions.duplicate(true); replayed_extensions.erase("pal.native.timing")
	check(s.state.rng == after.rng and s.state.entities == after.entities and replayed_extensions == continued_extensions,"continuous/replayed combat and story authority are identical")
	check(s.state.extensions["pal.native.timing"].reason == "save-load-practice","restoring retains the existing timing-credit invalidation")
	var limit: int = 0; var second_guarded: bool = false
	while s.battle_open() and limit < 80:
		if s.state.extensions[E.KEY].completed.size() == 1 and s.state.extensions[Battle.KEY].step == 0:
			var between: String = save("between-battles")
			if between.is_empty(): finish(); return
			var restored: bool = app.saves.load_into(s,between)
			check(restored,"second battle loads after first growth settlement: "+app.saves.error)
			if not restored: finish(); return
			var ledger: Dictionary = s.state.extensions[E.KEY]
			check(ledger.completed[0].rng_end == ledger.pending.rng_start,"growth end is next battle start")
			var second_budget: int = 0
			while s.battle_open() and s.state.extensions[Battle.KEY].round == 1 and second_budget < 32:
				check(command("guard"),"second battle guard consumes the continued stream"); await drain(); second_budget += 1
			second_guarded = true
		if not s.battle_open(): break
		check(attack(),"complete authored battle "+str(limit)+": "+s.error); await drain(); limit += 1
	check(not s.battle_open(),"battle route reaches a normal result")
	if not s.battle_open():
		check(s.state.extensions[E.KEY].pending == null,"settlement archives the full enemy ledger")
		var final_save: String = save("settled")
		check(app.saves.load_into(s,final_save),"settled history restores without repaying growth")
		if spec.get("two_battles",false): check(second_guarded and s.state.extensions[E.KEY].completed.size() == 2,"two battles keep enemy/growth history connected")
	for kind in spec.get("required_observations",[]): check(observed[kind] > 0,"actual configured rule observed "+kind)
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("enemy-physical-result.png"))
	finish()

func defense_projection(start: Dictionary, kind: String) -> void:
	var view = app.battle_view; var s = app.session
	var target: String = start.active_party[1]; var defender: String = start.active_party[0]
	var source: String = start.extensions[Battle.KEY].enemies[0].instance_id
	var result: Dictionary = start.extensions[Battle.KEY].duplicate(true)
	result.events = [{"kind":"attack","source":source,"target":target,"amount":0}]
	result.enemy_physical_actions = [{"event_start":0,"source":source,"target":target,"coverer":defender if kind == "cover" else null,"outcome":kind}]
	await settle(); view.queue_redraw(); await RenderingServer.frame_post_draw
	var baseline: Dictionary = view.displayed_bodies.duplicate(true); var projection: Transform2D = view.projection
	view.present_committed(start,result,""); await settle(); await RenderingServer.frame_post_draw
	var p = view.presentation
	check(p.phases.size() == (4 if kind == "cover" else 2),"synthetic "+kind+" expands into attack/defense/motion phases")
	var moving: String = defender if kind == "cover" else target
	if kind == "cover":
		check(view.displayed_bodies[moving].anchor.is_equal_approx(baseline[moving].anchor),"cover starts at static anchor")
		view._process(.09); await RenderingServer.frame_post_draw
		check(not view.displayed_bodies[moving].anchor.is_equal_approx(baseline[moving].anchor),"cover moves through an intermediate anchor")
		view._process(.09); await RenderingServer.frame_post_draw
		var at: Vector2 = view.displayed_bodies[moving].anchor
		check(p.current().actor_id == source and p.pose_for(moving) == "defend","coverer remains defending during enemy attack")
		check(view.displayed_frames[moving].resolved_action == "defend" and not view.displayed_frames[moving].fallback,"real authored coverer frame resolves to defend")
		view._process(float(p.current().duration_us)/1000000.0); await RenderingServer.frame_post_draw
		check(view.displayed_bodies[moving].anchor.is_equal_approx(at),"coverer holds contact position through zero-damage settlement")
		root.get_texture().get_image().save_png(output.path_join("cover-contact.png"))
		view._process(float(p.current().duration_us)/1000000.0); await RenderingServer.frame_post_draw
		check(p.current().cover.motion == "out","cover enters return phase")
		view._process(.09); await RenderingServer.frame_post_draw
		check(not view.displayed_bodies[moving].anchor.is_equal_approx(at),"cover returns through an intermediate anchor")
	else:
		check(p.pose_for(target) == "defend","block target defends while enemy attacks")
	check(view.projection == projection,"defense motion cannot refit the camera")
	for id in start.active_party:
		if id != moving: check(view.displayed_bodies[id].anchor.is_equal_approx(baseline[id].anchor),"defense preserves other party anchor "+id)
	view._process(100.0); await RenderingServer.frame_post_draw
	check(p.consumed == [0] and s.state == start,"defense consumes one original event without changing authority")
	view.skip(); await RenderingServer.frame_post_draw
	check(view.displayed_bodies[moving].anchor.is_equal_approx(baseline[moving].anchor),"defense skip/completion restores exact static anchor")
	for hz in [60,100,144,240]:
		p.begin(s.package,start,result,"")
		for _frame in range(hz*10): p.advance(1.0/hz,true)
		check(not p.active and p.consumed == [0] and s.state == start,"synthetic defense playback preserves RNG and HP at "+str(hz))
	view.skip(); await settle()
