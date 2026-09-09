# SPDX-License-Identifier: MIT
extends "res://tests/test_attack_formula.gd"
const RandomHit = preload("res://src/native_attack_random.gd")
const Rng = preload("res://src/native_rng.gd")

func finish() -> void:
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"saves":saves,
		"physical_input":false,"full_playthrough":false,"original_combat_parity":false,
		"synthetic_scope":"exact arithmetic and cursor boundaries; callback failure; isolated hit/status fixtures; 60/100 display steps",
		"real_content_scope":"author-built five-person story, target input, save/reload, ordinary win/loss/escape"},"\t"))
	print("attack random checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)

func run() -> void:
	var args = OS.get_cmdline_user_args(); if args.size() != 2: quit(2); return
	spec = JSON.parse_string(FileAccess.get_file_as_string(args[0])); current_package = spec.package; output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var vectors = JSON.parse_string(FileAccess.get_file_as_string(spec.vectors))
	for row in vectors.hits:
		check(RandomHit.vary(int(row.base),row.rolls,row.forced,row.bonus) == int(row.expected),"rational damage vector " + row.name)
	for row in vectors.streams:
		check(Rng.advance(int(row.seed),int(row.count)) == int(row.expected),"jump vector " + str(row))
	root.size = Vector2i(1280,800); app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false); app.saves = Save.new(output.path_join("saves"))
	check(app.open_package(spec.package),"author package opens with pinned random capability")
	if app.session.package == null: finish(); return
	var s = app.session; s.set_focus(true,s._last_usec)
	check(s.state.rng == Rng.initial(0),"new run uses authored seed, no wall-clock reseed")
	await click(option("继续")); await click(option("五人")); await click(option("继续"))
	check(s.battle_open() and s.state.active_party.size() == int(spec.get("party_count",5)),"traditional battle preserves authored party count")
	if not s.battle_open(): finish(); return
	var initial: String = save("before-hit"); var start: Dictionary = s.state.duplicate(true)
	var enemy_ids: Array = start.extensions[Battle.KEY].enemies.map(func(e): return e.instance_id)
	await click(option("攻击",true)); await click(option("返回命令"))
	check(s.state == start,"target cancel consumes no random draw")
	check(not s.battle_command("attack","missing.enemy") and s.state == start,"invalid target preserves complete state and cursor")
	await click(option("攻击",true)); await click(option("攻击 1"))
	var first: Dictionary = s.state.duplicate(true)
	check(s.state.rng.state == "%06x:4" % Rng.advance(0,4),"one committed hit consumes exactly four draws")
	check(app.battle_view.playing(),"real resource hit has active presentation")
	for fps in [60,100]:
		for i in range(4): app.battle_view._process(1.0 / fps)
		check(s.state == first,"display frames preserve authority and cursor at " + str(fps))
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("random-hit.png")); await drain()
	var after: String = save("after-hit")
	check(app.saves.load_into(s,initial),"restore earlier cursor differs from live cursor")
	check(s.battle_command("attack",enemy_ids[0]),"replayed attack accepted"); await drain()
	check(s.state.rng == first.rng and s.state.entities == first.entities and s.state.extensions[Battle.KEY] == first.extensions[Battle.KEY],"replay matches damage, effects, target, turn and next cursor")
	check(app.saves.load_into(s,after),"advanced cursor loads")
	var fresh = Session.new(); check(fresh.activate(s.package),"independent fresh session starts")
	var reader = Save.new(output.path_join("fresh"))
	check(reader.load_into(fresh,after) and fresh.state.rng == first.rng,"fresh run accepts advanced saved cursor")
	check(s.battle_command("attack",enemy_ids[1]) and fresh.battle_command("attack",enemy_ids[1]),"continuous and restored sessions take next hit"); await drain()
	check(s.state.rng == fresh.state.rng and s.state.entities == fresh.state.entities and s.state.scopes == fresh.state.scopes,"next hit and victory settle identically after reload")
	check(not s.battle_open() and s.state.rng.state.ends_with(":8"),"win commits exactly eight draws total"); save("win")
	check(app.saves.load_into(s,after),"reload before terminal callback fixture")
	var node: Dictionary = s.package.index.nodes[s.state.extensions[Battle.KEY].node_id]; var callback: String = node.on_win
	node.on_win = "node.fixture.missing"; var before_fault: Dictionary = s.state.duplicate(true)
	check(not s.battle_command("attack",enemy_ids[1]) and s.state == before_fault,"failed terminal callback rolls back consumed random draws, HP and settlement")
	node.on_win = callback
	for cursor in ["000000:4","000000:00","000000:1","000000:0\n","ffffff:4294967296"]:
		var bad: Dictionary = start.duplicate(true); bad.rng.state = cursor
		check(not s.restore(bad) and s.state == before_fault,"malformed or inconsistent saved cursor rejects atomically " + cursor)
	var bad_algorithm: Dictionary = start.duplicate(true); bad_algorithm.rng.algorithm = "unknown.rng"
	check(not s.restore(bad_algorithm) and s.state == before_fault,"unknown saved algorithm rejects atomically")
	var limit: Dictionary = start.duplicate(true); limit.rng.state = "%06x:%d" % [Rng.advance(0,Rng.MAX_DRAWS),Rng.MAX_DRAWS]
	check(s.restore(limit),"maximum legal cursor validated without linear replay")
	var exhausted: String = save("exhausted-cursor"); var full: Dictionary = s.state.duplicate(true)
	check(not s.battle_command("attack",enemy_ids[0]) and s.state == full,"exhausted stream rejects whole command without partial advance")
	check(app.saves.load_into(s,exhausted),"exhausted cursor remains loadable")
	check(app.saves.load_into(s,initial),"restore for guard and enemy-turn checks")
	for i in range(start.active_party.size()): check(s.battle_command("guard"),"guard command " + str(i)); await drain()
	check(s.state.rng == start.rng,"guard and deterministic enemy attacks consume no draws in this profile"); save("guarded-round")
	check(s.battle_command("item",start.active_party[0],"","item.miaopang.camp.medicine"),"authored medicine use remains supported"); await drain()
	check(s.state.rng == start.rng,"item effects do not consume ordinary-hit randomness"); save("item-only")
	check(app.saves.load_into(s,initial),"restore for skill")
	check(s.battle_command("skill",enemy_ids[0],"skill.miaopang.camp.heavy"),"authored attack skill remains supported"); await drain()
	check(s.state.rng == start.rng,"skill effects do not consume ordinary-hit randomness"); save("skill-only")
	check(app.saves.load_into(s,initial),"restore for escape")
	check(s.battle_command("escape"),"escape commits"); await drain()
	check(s.state.rng == start.rng and not s.battle_open(),"escape consumes no draw"); save("escape")
	check(app.saves.load_into(s,initial),"restore for defeat")
	var attempts: int = 0
	while s.battle_open() and attempts < 100:
		check(s.battle_command("guard"),"defeat guard " + str(attempts)); attempts += 1; await drain()
	check(not s.battle_open() and s.state.rng == start.rng,"defeat uses existing enemy rules without false RNG parity"); save("loss")
	# Synthetic state fixture isolates unclamped damage and status/definition binding.
	var isolated = Package.new(); check(isolated.load_package(spec.package),"separate arithmetic fixture admits real package")
	var config: Dictionary = isolated.world.extensions[RandomHit.KEY]
	# Seed 3's fourth draw lands inside the exclusive bonus bucket; seed 0
	# does not. Exercise the actual definition binding on a successful roll.
	config.seed = 3
	var branch_rolls: Array = [12282554,12371605,9297668,4919735]
	for forced in [false,true]:
		for bonus in [false,true]:
			var fixture: Dictionary = start.duplicate(true); var source: Dictionary = Battle.actor(fixture,fixture.active_party[0]); var target: Dictionary = fixture.extensions[Battle.KEY].enemies[0]
			fixture.rng = Rng.initial(3)
			isolated.index.actor_definitions[target.definition_id].max_hp = 100000; target.hp = 100000
			config.bonus_actor_definitions = [source.definition_id] if bonus else []
			if forced:
				fixture.extensions[Battle.KEY].statuses.append({"actor_id":source.instance_id,"status_id":config.critical_status_id,"source_id":source.instance_id,"stacks":1,"remaining_rounds":2})
			var attack: int = Battle.Statuses.stat(isolated,fixture,source,"attack"); var defense: int = Battle.Statuses.stat(isolated,fixture,target,"defense")
			var base: int = Formula.ordinary(isolated.world,attack,defense,true,false)
			var expected: int = RandomHit.vary(base,branch_rolls,forced,bonus); var events: Array = []
			check(Battle._hit(isolated,fixture,source,target,false,events).is_empty(),"isolated hit resolves")
			check(events[0].amount == expected and target.hp == 100000-expected and fixture.rng.state.ends_with(":4"),"bound status and definition preserve four draws " + str([forced,bonus]))
	var old_package = Package.new(); var old_session = Session.new()
	check(old_package.load_package(spec.old_package) and old_session.activate(old_package),"fixed-formula old package still loads")
	check(Save.new(output.path_join("old-read")).load_into(old_session,spec.old_save),"historical fixed-formula save loads unchanged")
	check(old_session.state.rng.algorithm == "pal.native.unused.v1","old content keeps its original unused stream")
	var old_before: Dictionary = old_session.state.duplicate(true)
	check(not Save.new().load_into(old_session,after) and old_session.state == old_before,"different content/rule save rejected without conversion")
	finish()
