# SPDX-License-Identifier: MIT
extends "res://tests/test_attack_formula.gd"
const Physical = preload("res://src/native_player_physical.gd")
const RandomHit = preload("res://src/native_attack_random.gd")
const Rng = preload("res://src/native_rng.gd")

func press(key: Key) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = key; event.physical_keycode = key; event.pressed = down
		root.push_input(event,true)
	await settle()

func finish() -> void:
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"saves":saves,
		"physical_input":false,"full_playthrough":false,"original_combat_parity":false,"secondary_growth_complete":false,
		"synthetic_scope":"fixed rational vectors, budget boundary, isolated all-double/dead-slot fixture, 60/100 display stepping",
		"real_content_scope":"GUI-authored original-asset story; all/single/double commands; status skill; win/loss/escape; save and replay"},"\t"))
	print("player physical checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)

func run() -> void:
	var args = OS.get_cmdline_user_args(); if args.size() != 2: quit(2); return
	spec = JSON.parse_string(FileAccess.get_file_as_string(args[0])); current_package = spec.package; output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800); app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false); app.saves = Save.new(output.path_join("saves"))
	check(app.open_package(spec.package),"author package admitted with physical capability")
	if app.session.package == null: finish(); return
	var s = app.session; s.set_focus(true,s._last_usec)
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec.vectors))
	for row in vectors.actions:
		var world: Dictionary = s.package.world.duplicate(true)
		world.extensions[Physical.KEY].enemy_stats = row.enemy_stats
		world.extensions[Physical.KEY].all_target_actor_definitions = ["actor.test"] if row.all_targets else []
		world.extensions[RandomHit.KEY].seed = row.seed
		world.extensions[RandomHit.KEY].bonus_actor_definitions = ["actor.test"] if row.bonus else []
		var result: Dictionary = Physical.calculate(world,row.action,"actor.test",row.old_health,row.old_attack)
		for key in row.expected:
			var expected = row.expected[key]
			if key == "hits": expected = expected.map(func(bout): return bout.map(func(hit): return int(hit)))
			check(result.get(key) == expected,"independent rational vector %s / %s" % [row.name,key])
	await click(option("继续")); await click(option("五人")); await click(option("继续"))
	check(s.battle_open() and s.state.active_party.size() == int(spec.party_count),"authored story enters traditional battle with chosen party count")
	if not s.battle_open(): finish(); return
	var initial: String = save("initial"); var start: Dictionary = s.state.duplicate(true)
	var enemies: Array = start.extensions[Battle.KEY].enemies.map(func(e): return e.instance_id)
	var order: Array = Physical.order(s.package.world,start.extensions[Battle.KEY].encounter_id)
	check(order == [enemies[1],enemies[0]],"authored all-target order differs from visual enemy order")
	check(app.battle_view.classic_layout().preset == "pal.dream-oblique.v1","physical rules preserve named Dream presentation")
	await click(option("攻击",true)); var all_button = option("攻击全体",true)
	all_button.grab_focus(); await settle()
	check(app.battle_view.target_ids == order,"one all-target input highlights both stable instances")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("physical-targets.png"))
	await click(option("返回命令")); check(s.state == start,"cancel preserves authority and random cursor")
	check(not s.battle_command("attack",enemies[0]) and s.state == start,"all-target command rejects a single target atomically")
	await click(option("攻击",true)); await click(option("攻击全体",true))
	var first: Dictionary = s.state.duplicate(true); var receipt: Dictionary = Physical.latest(first)
	check(receipt.hits == [[54,27]] and receipt.rng_after == 2 and receipt.attack_count == 1,"all attack resolves one shared critical roll and one action-tail draw")
	check(first.extensions[Battle.KEY].enemies[0].hp == 1 and first.extensions[Battle.KEY].enemies[1].hp == 0,"halving follows explicit order and settles once per target")
	check(app.battle_view.playing(),"all attack produces real-resource presentation")
	for fps in [60,100]:
		for i in range(4): app.battle_view._process(1.0/fps)
		check(s.state == first,"display stepping leaves authority unchanged at " + str(fps))
	await drain(); var after: String = save("after-all")
	check(app.saves.load_into(s,initial),"load restores initial command")
	await click(option("攻击",true)); option("攻击全体",true).grab_focus(); await press(KEY_ENTER)
	check(Physical.latest(s.state).get("rng_after") == 2,"keyboard confirm replays all-target command"); await drain()
	check(s.state.extensions[Physical.KEY] == first.extensions[Physical.KEY] and s.state.extensions[Battle.KEY] == first.extensions[Battle.KEY] and s.state.entities == first.entities and s.state.rng == first.rng,"replay restores target effects, practice ledger and stream")
	check(s.state.extensions["pal.native.timing"] == {"eligible":false,"reason":"save-load-practice"},"replay preserves existing noncompetitive timing marker")
	check(app.saves.load_into(s,after),"advanced physical ledger loads")
	var fresh = Session.new(); check(fresh.activate(s.package),"fresh session starts")
	check(Save.new(output.path_join("fresh")).load_into(fresh,after),"fresh session reads advanced physical save")
	await click(option("攻击",true)); var living_button = option("攻击 1")
	check(option("攻击 2").disabled,"single-target picker excludes defeated instance")
	await click(living_button); check(fresh.battle_command("attack",enemies[0]),"fresh session applies same next single attack"); await drain()
	check(not s.battle_open() and s.state.rng.state.ends_with(":7"),"single attack follows all attack and normal victory")
	check(s.state.rng == fresh.state.rng and s.state.entities == fresh.state.entities and s.state.extensions == fresh.state.extensions,"fresh and continuous next action settle identically")
	var won: String = save("win"); var won_state: Dictionary = s.state.duplicate(true)
	check(s.state.extensions[Physical.KEY].pending == null and s.state.extensions[Physical.KEY].last_battle.actions.size() == 2,"victory retains completed action ledger")
	check(app.saves.load_into(s,won) and s.state.entities == won_state.entities and s.state.committed_effect_ids == won_state.committed_effect_ids,"victory load does not repay rewards or counters")
	check(app.saves.load_into(s,after),"restore before callback failure fixture")
	var node: Dictionary = s.package.index.nodes[s.state.extensions[Battle.KEY].node_id]; var callback: String = node.on_win
	node.on_win = "node.fixture.missing"; var before_fault: Dictionary = s.state.duplicate(true)
	check(not s.battle_command("attack",enemies[0]) and s.state == before_fault,"callback failure rolls back hits, counters, cursor and settlement")
	node.on_win = callback
	for defect in ["hit","count","cursor","target","battle-target"]:
		var bad: Dictionary = first.duplicate(true); var action: Dictionary = bad.extensions[Physical.KEY].pending.actions[0]
		if defect == "hit": action.hits[0][0] += 1
		elif defect == "count": action.health_count += 1
		elif defect == "cursor": action.rng_after += 1
		elif defect == "battle-target": bad.extensions[Battle.KEY].enemies[0].instance_id = "enemy.missing"
		else: action.targets[0].instance_id = "enemy.missing"
		check(not s.restore(bad) and s.state == before_fault,"invalid saved action rejects atomically " + defect)
	# Real authored status skill enables two single-target bouts on the fist.
	check(app.saves.load_into(s,initial),"restore for authored double-attack status skill")
	check(s.battle_command("guard"),"hero guards while fist prepares"); await drain()
	var fist: String = start.active_party[1]
	check(s.battle_command("skill",fist,"skill.miaopang.camp.brace"),"fist applies authored brace skill"); await drain()
	for i in range(2,start.active_party.size()): check(s.battle_command("guard"),"round guard " + str(i)); await drain()
	check(s.battle_command("guard"),"next round reaches buffed fist"); await drain()
	var before_double: String = save("before-double"); var double_start: Dictionary = s.state.duplicate(true)
	await click(option("攻击",true)); await click(option("攻击 2"))
	var doubled: Dictionary = s.state.duplicate(true); var double_receipt: Dictionary = Physical.latest(doubled)
	check(double_receipt.double_attack and double_receipt.forced_critical and double_receipt.hits.size() == 2 and double_receipt.rng_after == 9,"authored status triggers two four-draw bouts plus one health draw")
	check(double_receipt.attack_count == 1 and doubled.extensions[Battle.KEY].step == double_start.extensions[Battle.KEY].step+1,"double attack spends one command and one practice action")
	var presentation = app.battle_view.presentation
	check(presentation.phases.filter(func(p): return p.actor_id == fist and p.action == "attack").size() == 2,"both physical bouts have authored attack playback")
	var event_count: int = doubled.extensions[Battle.KEY].events.size()
	app.battle_view._process(100.0); await settle()
	check(presentation.consumed == range(event_count),"aggregate event indices consumed once after both display bouts")
	check(s.state == doubled,"complete double playback cannot recalculate rules")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("physical-double-result.png"))
	var double_save: String = save("after-double")
	check(app.saves.load_into(s,before_double) and s.battle_command("attack",enemies[1]),"replay double from saved status and cursor"); await drain()
	check(s.state.extensions == doubled.extensions and s.state.rng == doubled.rng,"double replay matches both bouts and practice counts")
	check(app.saves.load_into(s,double_save),"double action ledger reloads")
	check(app.saves.load_into(s,initial),"restore for skill-only evidence")
	check(s.battle_command("skill",enemies[0],"skill.miaopang.camp.heavy"),"normal skill remains independent"); await drain()
	check(s.state.rng == start.rng and Physical.latest(s.state).is_empty(),"skill does not consume physical draws or practice counters"); save("skill-only")
	check(app.saves.load_into(s,initial),"restore for escape")
	check(s.battle_command("escape"),"normal escape accepted"); await drain()
	check(not s.battle_open() and s.state.rng == start.rng and s.state.extensions[Physical.KEY].last_battle.outcome == "escape","escape settles empty physical ledger"); save("escape")
	check(app.saves.load_into(s,initial),"restore for loss")
	var attempts: int = 0
	while s.battle_open() and attempts < 100:
		check(s.battle_command("guard"),"normal loss guard " + str(attempts)); await drain(); attempts += 1
	check(not s.battle_open() and s.state.rng == start.rng and s.state.extensions[Physical.KEY].last_battle.outcome == "loss","normal enemy actions reach loss without physical draws"); save("loss")
	# Isolated all-double fixture is separate from the authored route and saves.
	var isolated = Package.new(); check(isolated.load_package(spec.package),"separate all-double fixture admits parent package")
	var fixture: Dictionary = start.duplicate(true); var b: Dictionary = fixture.extensions[Battle.KEY]; b.step = 1
	var hero: Dictionary = Battle.actor(fixture,b.party[0]); b.enemies[0].hp = 0
	b.statuses.append({"actor_id":hero.instance_id,"status_id":isolated.world.extensions[Physical.KEY].double_attack_status_id,"source_id":hero.instance_id,"stacks":1,"remaining_rounds":2})
	check(Physical.apply(isolated,fixture,hero,"").is_empty(),"isolated all-double executes")
	var all_double: Dictionary = Physical.latest(fixture)
	check(all_double.hits == [[54],[54]] and all_double.targets.size() == 1 and all_double.targets[0].instance_id == enemies[1],"dead enemy neither receives hits nor consumes a halving position")
	check(all_double.rng_after == 3 and all_double.attack_count == 1 and b.events.filter(func(e): return e.kind == "attack").size() == 1,"all-double uses two shared rolls, one tail and one aggregate target event")
	check(Physical.validate_state(isolated,fixture).is_empty(),"all-double preimage receipt is consistent")
	var limit_rng: Dictionary = {"algorithm":Rng.ALGORITHM,"state":"%06x:%d" % [Rng.advance(0,Rng.MAX_DRAWS-1),Rng.MAX_DRAWS-1]}
	var before_limit: Dictionary = limit_rng.duplicate(true)
	check(Rng.draw(limit_rng,2).has("error") and limit_rng == before_limit,"draw budget rejects before partial cursor advance")
	var budget_action: Dictionary = receipt.duplicate(true); budget_action.rng_before = Rng.MAX_DRAWS-1
	check(Physical.calculate(s.package.world,budget_action,hero.definition_id,0,0).has("error"),"whole-action budget accounts for tail draw")
	var old_package = Package.new(); var old_session = Session.new()
	check(old_package.load_package(spec.old_package) and old_session.activate(old_package),"previous four-draw profile still activates")
	check(Save.new(output.path_join("old-read")).load_into(old_session,spec.old_save),"previous profile save remains loadable with its own package")
	check(not old_session.state.extensions.has(Physical.KEY),"old package does not acquire new ledger")
	var old_before: Dictionary = old_session.state.duplicate(true)
	check(not Save.new().load_into(old_session,after) and old_session.state == old_before,"changed package save is not silently migrated")
	finish()
