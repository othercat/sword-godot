# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Package = preload("res://src/native_package.gd")
const Save = preload("res://src/native_save.gd")
const Session = preload("res://src/native_session.gd")
const Battle = preload("res://src/native_battle.gd")
const Formula = preload("res://src/native_attack_formula.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
var spec: Dictionary
var current_package: String
var app
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func settle() -> void:
	await process_frame; await process_frame; await process_frame
func option(prefix: String, exact: bool = false) -> Button:
	for control in app._battle_controls():
		if control is Button and (control.text == prefix if exact else control.text.begins_with(prefix)): return control
	check(false,"missing input control " + prefix); return null
func click(control: Button) -> void:
	if control == null: return
	check(not control.disabled,"selected input is enabled")
	var point: Vector2 = control.get_global_rect().get_center()
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event,true)
	await settle()
func drain() -> void:
	# Explicit presentation fast-forward, never a second rule resolution.
	app.battle_view.skip(); await settle()
func save(label: String) -> String:
	check(app.saves.save(app.session),label + " saves through production writer")
	var path: String = app.saves.last_path
	saves.append({"label":label,"package_path":current_package,"save_path":path}); return path
func finish() -> void:
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"saves":saves,
		"physical_input":false,"full_playthrough":false,"original_combat_parity":false,
		"synthetic_scope":"arithmetic vectors, callback fault and isolated hit-state fixtures; 60/100 display steps",
		"real_content_scope":"current author package, five-person story entry and ordinary win/loss/escape commands; three/four are explicit party-count variants"},"\t"))
	print("attack formula checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
func run() -> void:
	var args = OS.get_cmdline_user_args(); if args.size() != 2: quit(2); return
	spec = JSON.parse_string(FileAccess.get_file_as_string(args[0])); current_package = spec.package; output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec.vectors))
	var content: Dictionary = {"extensions": {Formula.KEY: {"profile": Formula.PROFILE}}}
	for row in vectors.base: check(Formula.base_damage(int(row[0]),int(row[1])) == row[2],"specified base vector " + str(row))
	for row in vectors.attacks: check(Formula.ordinary(content,int(row.attack),int(row.defense),row.party_source,row.guarded) == row.expected,"direction/guard vector " + str(row))
	check(Formula.ordinary({"extensions":{}},20,10,true,false) == 10 and Formula.ordinary({"extensions":{}},20,9,false,true) == 6,"absent profile keeps old subtraction and ceil-half")
	root.size = Vector2i(1280,800); app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
	app.saves = Save.new(output.path_join("saves")); check(app.open_package(spec.package),"compiled author package opens")
	if app.session.package == null: finish(); return
	var s = app.session; s.set_focus(true,s._last_usec)
	check(Formula.used(s.package.world) and s.package.manifest.ruleset_hash == spec.ruleset_hash,"runtime pins selected formula rule identity")
	await click(option("继续")); await click(option("五人")); await click(option("继续"))
	check(s.battle_open() and s.state.active_party.size() == 5,"existing story enters five-person battle")
	if not s.battle_open(): finish(); return
	var initial: String = save("initial"); var initial_state: Dictionary = s.state.duplicate(true)
	var battle: Dictionary = s.state.extensions[Battle.KEY]; var enemies: Array = battle.enemies.map(func(e): return e.instance_id)
	var hero: Dictionary = Battle.actor(s.state,battle.party[0])
	check(Battle.Statuses.stat(s.package,s.state,hero,"attack") == 28 and Battle.Statuses.stat(s.package,s.state,hero,"defense") == 8,"source stats include existing weapon modifier")
	check(not s.battle_command("attack","enemy.missing") and s.state == initial_state,"invalid target does not consume or mutate authority")
	for i in range(5): check(s.battle_command("guard"),"normal five-party guard " + str(i)); await drain()
	battle = s.state.extensions[Battle.KEY]
	var hits: Array = battle.events.filter(func(e): return e.kind == "attack")
	check(hits.size() == 2 and hits.all(func(e): return e.amount == 47),"enemy source60 versus guarded effective defense16 produces 47 per hit")
	check(Battle.actor(s.state,battle.party[0]).hp == 26 and battle.round == 2 and battle.guarding.is_empty(),"guard damage and round boundary commit exactly once")
	var guarded_save: String = save("guarded-round")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("formula-guarded.png"))
	await click(option("攻击",true)); await click(option("攻击 2"))
	battle = s.state.extensions[Battle.KEY]
	check(battle.enemies[0].hp == 28 and battle.enemies[1].hp == 0 and battle.events[0].amount == 28,"mouse-selected instance clamps requested56 to current28 HP")
	var after_hit: Dictionary = s.state.duplicate(true)
	check(app.battle_view.playing(),"selected ordinary hit has active authored playback")
	var before_display: Array = [app.battle_view.presentation.phase_index,app.battle_view.presentation.elapsed_us]
	app.battle_view._process(1.0/60); app.battle_view._process(1.0/100)
	check(before_display != [app.battle_view.presentation.phase_index,app.battle_view.presentation.elapsed_us],"synthetic60/100 steps advance active playback")
	check(s.state == after_hit,"active playback at synthetic60/100 steps does not repeat damage")
	await drain()
	save("selected-target")
	check(app.saves.load_into(s,guarded_save) and s.state.extensions[Battle.KEY].enemies.all(func(e): return e.hp == 28),"load restores target HP and command point")
	check(s.state.rng == {"algorithm":"pal.native.unused.v1","state":"unused"},"deterministic base profile leaves RNG unused")
	# Failure injection stays inside the private loaded package, restored immediately.
	var node: Dictionary = s.current_node(); var callback: String = node.on_win
	check(s.battle_command("attack",enemies[0]),"first ordinary hit before callback fault"); await drain()
	node.on_win = "node.fixture.missing"; var before_fault: Dictionary = s.state.duplicate(true)
	check(not s.battle_command("attack",enemies[1]) and s.state == before_fault,"terminal callback failure rolls back HP, events and settlement")
	node.on_win = callback
	check(s.battle_command("attack",enemies[1]),"ordinary terminal attack succeeds after callback restoration"); await drain()
	check(not s.battle_open() and initial_state.extensions[Battle.KEY].execution_id in s.state.committed_effect_ids,"victory callback commits once")
	var won: String = save("win"); var won_state: Dictionary = s.state.duplicate(true)
	check(app.saves.load_into(s,won) and s.state.entities == won_state.entities and s.state.committed_effect_ids == won_state.committed_effect_ids,"victory save does not replay rewards")
	check(app.saves.load_into(s,initial),"restore entry for loss")
	var steps: int = 0
	while s.battle_open() and steps < 100:
		check(s.battle_command("guard"),"ordinary loss route guard " + str(steps)); await drain(); steps += 1
	check(not s.battle_open() and initial_state.active_party.all(func(id): return Battle.actor(s.state,id).hp == 0),"ordinary enemy attacks reach complete party defeat")
	save("loss")
	check(app.saves.load_into(s,initial),"restore entry for escape")
	check(s.battle_command("escape"),"ordinary escape command"); await drain(); check(not s.battle_open(),"escape follows existing callback"); save("escape")
	if spec.has("old_save"):
		var previous_package = Package.new(); var previous_session = Session.new()
		check(previous_package.load_package(spec.old_package) and previous_session.activate(previous_package),"historical package starts an independent session")
		var previous_saves = Save.new(output.path_join("historical-read-only"))
		check(previous_saves.load_into(previous_session,spec.old_save),"unchanged historical save loads with its original package")
		check(not Formula.used(previous_session.package.world) and previous_session.battle_open(),"historical save is a valid prior-formula battle checkpoint")
		var before_old: Dictionary = s.state.duplicate(true)
		check(not app.saves.load_into(s,spec.old_save) and app.saves.error == "save identity mismatch: content_lock" and s.state == before_old,"valid previous save is rejected for changed content identity without mutation")
	# Arithmetic integration fixtures deliberately differ from playable source data.
	var isolated = Package.new(); check(isolated.load_package(spec.package),"isolated fixture loads through admission")
	var fixture: Dictionary = initial_state.duplicate(true); var target: Dictionary = fixture.extensions[Battle.KEY].enemies[0]
	var attacker: Dictionary = Battle.actor(fixture,fixture.active_party[0])
	isolated.index.actor_definitions[target.definition_id].combat.defense = 1000
	var brace: String = "status.miaopang.camp.brace"
	isolated.index.status_definitions[brace].remove_on_damage = true
	fixture.extensions[Battle.KEY].statuses.append({"actor_id":target.instance_id,"status_id":brace,"source_id":attacker.instance_id,"stacks":1,"remaining_rounds":2})
	var before_zero: Dictionary = fixture.duplicate(true); var events: Array = []
	Battle._hit(isolated,fixture,attacker,target,false,events)
	check(events.size() == 1 and events[0].amount == 0 and fixture == before_zero,"zero damage emits an attack without clearing status or granting participation")
	isolated.index.actor_definitions[target.definition_id].combat.defense = 10; target.hp = 500
	isolated.index.actor_definitions[target.definition_id].max_hp = 500; events = []
	Battle._hit(isolated,fixture,attacker,target,false,events)
	check(events[0].amount == 34 and target.hp == 466,"equipment attack28 and40percent defense status14 feed the curve")
	# Prior positive hit removes the damage-sensitive brace, leaving defense10.
	var effect_issue: String = Battle.Skills.Effects.apply(isolated,fixture,attacker,{"effects":[{"op":"damage","power":20}]},[target],"skill_id","skill.fixture")
	check(effect_issue.is_empty() and target.hp == 456,"skill damage remains power-minus-defense instead of using ordinary curve")
	for variant in spec.party_variants:
		current_package = variant.package
		check(app.open_package(current_package),"compiled party-count variant opens " + str(variant.count))
		s = app.session; s.set_focus(true,s._last_usec); await settle()
		await click(option("继续")); await click(option("五人")); await click(option("继续"))
		check(s.battle_open() and s.state.active_party.size() == variant.count,"synthetic authored party count reaches actual battle " + str(variant.count))
		if not s.battle_open(): finish(); return
		for i in range(int(variant.count)): check(s.battle_command("guard"),"variant guard command " + str(variant.count) + "/" + str(i)); await drain()
		battle = s.state.extensions[Battle.KEY]
		check(Battle.actor(s.state,battle.party[0]).hp == 26,"same directional curve after complete party round " + str(variant.count))
		var checkpoint: String = save("party-" + str(variant.count))
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("formula-party-" + str(variant.count) + ".png"))
		var variant_enemies: Array = battle.enemies.map(func(e): return e.instance_id)
		check(s.battle_command("attack",variant_enemies[0]),"variant first ordinary attack"); await drain()
		check(app.saves.load_into(s,checkpoint) and s.state.active_party.size() == variant.count and s.state.extensions[Battle.KEY].enemies[0].hp == 28,"variant save restores command and roster")
		for id in variant_enemies: check(s.battle_command("attack",id),"variant target identity and terminal settlement"); await drain()
		check(not s.battle_open(),"variant reaches existing victory callback"); save("party-" + str(variant.count) + "-win")
	finish()
