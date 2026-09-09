# SPDX-License-Identifier: MIT
extends "res://tests/test_attack_formula.gd"
const Training = preload("res://src/native_training.gd")
const Physical = preload("res://src/native_player_physical.gd")
const Rng = preload("res://src/native_rng.gd")

func finish() -> void:
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"saves":saves,
		"physical_input":false,"full_playthrough":false,"original_combat_parity":false,
		"synthetic_scope":"integer/binary32 boundaries, callback and RNG budget fault, save tampering, 60/100 presentation steps",
		"real_content_scope":"GUI-authored original-asset story, actual battle commands and primary/secondary settlement, save restore, three/four party variants"},"\t"))
	print("training checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)

func counts(state: Dictionary, id: String) -> Array:
	var value: Array = [0,0,0,0,0,0,0]
	for row in state.extensions[Training.KEY].pending.actions:
		if row.source == id: value = row.counts
	return value

func attack() -> bool:
	var s = app.session; var battle: Dictionary = s.state.extensions[Battle.KEY]
	var actor: Dictionary = Battle.actor(s.state,battle.party[battle.turn])
	var target: String = "" if Physical.all_targets(s.package.world,actor.definition_id) else battle.enemies.filter(func(e): return e.hp > 0)[0].instance_id
	var step: int = battle.step
	app._battle_action("attack",target)
	return not s.battle_open() or s.state.extensions[Battle.KEY].step > step

func run() -> void:
	var args = OS.get_cmdline_user_args(); if args.size() != 2: quit(2); return
	spec = JSON.parse_string(FileAccess.get_file_as_string(args[0])); current_package = spec.package; output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800); app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false); app.saves = Save.new(output.path_join("saves"))
	check(app.open_package(spec.package),"GUI-authored training package admitted")
	if app.session.package == null: finish(); return
	var s = app.session; s.set_focus(true,s._last_usec)
	check(Training.used(s.package.world) and Training.ESCAPE_CAPABILITY in s.package.manifest.required_capabilities,"capability selects training and escape together")
	var value: Dictionary = {"level_costs":[2,3,5],"stat_caps":[999,999,999,999,999,999,999]}
	var before: Dictionary = {"schema":Training.SCHEMA,"kind":"actor","levels":[0,0,0,0,0,0,0],"experience":[0,0,0,0,0,0,0],"gains":[0,0,0,0,0,0,0]}
	var result: Dictionary = Training.allocate(value,before,[1,1,1,1,1,1,1],7,[10,10,10,10,10,10,10],0,0)
	check(result.after.levels == [1,1,1,1,1,1,1] and result.after.gains == [2,1,1,2,1,2,2] and result.rng_after == 7,"seven independent fixed-seed growth vectors consume category order")
	value.level_costs = [10,20]; before.experience = [1,0,0,0,0,0,0]
	result = Training.allocate(value,before,[1,3,0,0,0,0,0],1,[10,10,10,10,10,10,10],0,0)
	check(result.after.experience == [2,2,0,0,0,0,0] and result.grants == [1,2,0,0,0,0,0],"whole-value nearest-even preserves old odd experience at half tie")
	value.level_costs = [2,3,5]; before.levels = [2,2,2,2,2,2,2]; before.experience = [4,0,0,0,0,0,0]
	result = Training.allocate(value,before,[1,0,0,0,0,0,0],13,[10,10,10,10,10,10,10],0,Rng.MAX_DRAWS)
	check(result.after.experience[0] == 0 and result.rng_after == Rng.MAX_DRAWS,"last level consumes threshold modulo without another random draw")
	value.level_costs = [1,1,10]; before.levels[0] = 0; before.experience[0] = 0
	result = Training.allocate(value,before,[1,0,0,0,0,0,0],2,[999,10,10,10,10,10,10],0,0)
	check(result.after.gains[0] == 0 and result.recovery[0] == 3 and result.rng_after == 2,"capped HP keeps raw two-level recovery and RNG consumption")
	var original: Dictionary = before.duplicate(true)
	check(Training.allocate(value,before,[1,0,0,0,0,0,0],2,[10,10,10,10,10,10,10],0,Rng.MAX_DRAWS-1).has("error") and before == original,"growth budget failure leaves input intact")
	check(Training.escape_success(2,3,11184811) and not Training.escape_success(2,3,11184812),"explicit binary32 escape comparison at rounding boundary")
	await click(option("继续")); await click(option("五人")); await click(option("继续"))
	check(s.battle_open() and s.state.active_party.size() == int(spec.party_count),"authored route enters selected traditional party size")
	if not s.battle_open(): finish(); return
	var initial: String = save("initial"); var start: Dictionary = s.state.duplicate(true); var party: Array = start.active_party
	check(app.battle_view.classic_layout().preset == "pal.dream-oblique.v1","training leaves named Dream geometry selected")
	app._show_status(); await settle(); check(app.status_picker.visible and app.status_text.text.contains("副经历") and app.status_text.text.contains("吉运"),"status UI exposes all seven tracks and extra stats")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("training-status.png")); app.status_picker.hide(); await settle()
	app._battle_action("escape",""); await settle()
	check(s.battle_open() and app.message.text.contains("撤离失败") and Training.cursor(s.state) == 1,"low authored flee fails through the UI command and one logic draw")
	check(counts(s.state,party[0]) == [0,0,0,0,0,0,2],"failed escape adds only flee practice")
	var failed_state: Dictionary = s.state.duplicate(true)
	for fps in [60,100]:
		for i in range(5): app.battle_view._process(1.0/fps)
		check(s.state == failed_state,"escape presentation cannot advance RNG or counts at " + str(fps))
	await drain(); var failed_save: String = save("failed-escape")
	check(s.battle_command("guard"),"next party member can guard after failed escape"); await drain()
	check(counts(s.state,party[1])[4] == 2,"guard contributes two defense practice")
	var current: Dictionary = Battle.actor(s.state,s.state.extensions[Battle.KEY].party[s.state.extensions[Battle.KEY].turn])
	var skills: Array = Session.Progression.skill_ids(s.package,current); var skill: String = skills[0]
	var definition: Dictionary = s.package.world.skill_definitions.filter(func(r): return r.id == skill)[0]
	var target: String = current.instance_id if definition.target_side == "ally" else s.state.extensions[Battle.KEY].enemies[0].instance_id
	check(s.battle_command("skill",target,skill),"third member casts the authored available skill"); await drain()
	check(Training.cursor(s.state) == 2 and counts(s.state,current.instance_id)[3] == 1,"successful cast contributes one logic draw and magic practice")
	var mixed: String = save("mixed-commands"); var mixed_state: Dictionary = s.state.duplicate(true)
	for defect in ["old-difficulty","old-flee","old-null","actor-growth","command-gap","enemy-health"]:
		var bad: Dictionary = mixed_state.duplicate(true); var action: Dictionary = bad.extensions[Training.KEY].pending.actions[0]
		if defect == "old-difficulty": action.escape.difficulty = 0
		elif defect == "old-flee": action.escape.effective_flee = 1
		elif defect == "old-null": action.escape = null
		elif defect == "actor-growth": Battle.actor(bad,party[0]).components[Training.KEY].gains[6] = 1
		elif defect == "command-gap": bad.extensions[Training.KEY].pending.actions[1].rng_before += 1
		else: bad.extensions[Battle.KEY].enemies[0].hp -= 1
		check(not s.restore(bad) and s.state == mixed_state,"tampered earlier command rejects atomically " + defect)
	var fresh = Session.new(); check(fresh.activate(s.package) and Save.new(output.path_join("fresh")).load_into(fresh,mixed),"fresh runtime restores mixed practice and random history")
	var attempts: int = 0
	while s.battle_open() and attempts < 30:
		check(attack(),"normal attack completes mixed practice battle " + str(attempts)); await drain(); attempts += 1
	check(not s.battle_open() and s.state.extensions[Training.KEY].credits[-1].outcome == "win","normal battle reaches victory with training settlement")
	check(app.message.text.is_empty(),"next successful UI command clears the earlier escape failure notice")
	var won: Dictionary = s.state.duplicate(true); var credit: Dictionary = won.extensions[Training.KEY].credits[-1]
	check(credit.rng_end > mixed_state.extensions[Training.KEY].pending.actions[-1].rng_after and credit.awards.any(func(a): return a.after.levels != a.before.levels),"victory produces actual secondary levels after primary awards")
	for award in credit.awards:
		check(award.reward == (40 if award.instance_id in credit.living else 0),"final living policy awards encounter total " + award.instance_id)
		check(award.after.levels[5] == award.before.levels[5] and award.after.experience[5] == 1,"dexterity receives no invented action count " + award.instance_id)
		var actor: Dictionary = Battle.actor(won,award.instance_id); var stats: Dictionary = Session.Progression.stats(s.package,actor)
		check(actor.hp <= stats.max_hp and actor.mp <= stats.max_mp,"secondary recovery respects effective caps " + award.instance_id)
	var won_save: String = save("win"); check(app.saves.load_into(s,won_save) and s.state.entities == won.entities and s.state.committed_effect_ids == won.committed_effect_ids,"won save does not repay primary or secondary growth")
	check(not Training.summary(s.package,s.state).is_empty(),"growth summary has visible category gains")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("training-victory.png"))
	# Restore the same mixed command boundary and replay the same remaining inputs.
	check(app.saves.load_into(s,mixed),"reload mixed-command boundary")
	attempts = 0
	while s.battle_open() and attempts < 30:
		check(attack(),"replay action " + str(attempts)); await drain(); attempts += 1
	check(s.state.entities == won.entities and s.state.extensions[Training.KEY] == won.extensions[Training.KEY] and s.state.rng == won.rng,"save replay reproduces all growth, counts and random state")
	# A second, successful attempt after loading the earlier failure uses a high-flee partner.
	check(app.saves.load_into(s,failed_save) and s.battle_command("escape"),"high-flee partner attempts escape"); await drain()
	check(not s.battle_open() and s.state.extensions[Training.KEY].credits[-1].outcome == "escape" and Training.cursor(s.state) == 2,"successful escape ends the battle after the next logic draw")
	check(s.state.entities == failed_state.entities,"escape pays no primary experience or secondary growth"); save("escape")
	# A qualified zero-heal cast still receives practice; an item does not.
	check(app.saves.load_into(s,initial) and s.battle_command("skill",party[0],"skill.miaopang.camp.heal"),"full-health target accepts qualified healing spell"); await drain()
	check(counts(s.state,party[0])[3] == 1 and Training.cursor(s.state) == 1,"zero effective healing still counts one successful cast"); save("zero-heal")
	check(app.saves.load_into(s,initial) and s.battle_command("item",party[0],"","item.miaopang.camp.medicine"),"normal item use succeeds"); await drain()
	check(counts(s.state,party[0]) == [0,0,0,0,0,0,0] and Training.cursor(s.state) == 0,"item consumes neither practice nor training random draws"); save("item")
	check(app.saves.load_into(s,initial),"restore for ordinary defeat")
	attempts = 0
	while s.battle_open() and attempts < 100:
		check(s.battle_command("guard"),"normal defeat guard " + str(attempts)); await drain(); attempts += 1
	check(not s.battle_open() and s.state.extensions[Training.KEY].credits[-1].outcome == "loss","enemy actions lead to normal defeat")
	check(s.state.extensions[Training.KEY].credits[-1].awards.all(func(a): return a.reward == 0 and a.after == a.before),"defeat cannot award secondary growth"); save("loss")
	# Fault injection is isolated in the in-memory callback and restored immediately.
	check(app.saves.load_into(s,initial) and attack(),"restore and prepare last-enemy boundary"); await drain()
	var prewin: String = save("before-win"); var retained: Dictionary = s.state.duplicate(true)
	var node: Dictionary = s.package.index.nodes[retained.extensions[Battle.KEY].node_id]; var callback: String = node.on_win
	node.on_win = "node.missing.callback"
	check(not attack() and s.state == retained,"callback failure rolls back attack, training, primary award, RNG and HP")
	node.on_win = callback
	check(app.saves.load_into(s,prewin) and attack(),"restored callback completes the same winning command"); await drain(); save("single-win")
	var old = Package.new(); var old_session = Session.new()
	check(old.load_package(spec.old_package) and old_session.activate(old),"prior standalone physical package remains loadable")
	check(Save.new(output.path_join("old-read")).load_into(old_session,spec.old_save) and not old_session.state.extensions.has(Training.KEY),"prior package save does not acquire secondary state")
	var old_state: Dictionary = old_session.state.duplicate(true)
	check(not Save.new().load_into(old_session,won_save) and old_session.state == old_state,"new rules save does not silently migrate into old package")
	finish()
