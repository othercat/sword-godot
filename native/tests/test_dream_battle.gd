# SPDX-License-Identifier: MIT
extends "res://tests/test_legacy_battle_import.gd"
## Reference coordinates are supplied independently by the evidence runner.
var windows: Array = []
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for fixture in spec.fixtures:
		fixture.count = int(fixture.count)
		package_path = fixture.package_path; root.size = Vector2i(1280,800)
		var app = App.instantiate(); root.add_child(app); await settle()
		app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
		app.saves = Save.new(output.path_join("saves-"+str(fixture.count)))
		check(app.open_package(package_path),"open Dream authored variant "+str(fixture.count))
		if app.session.package == null: finish(); return
		root.grab_focus(); await settle()
		app.session.set_focus(true,app.session._last_usec); await settle()
		await click(option(app,"继续")); await click(option(app,"五人")); await click(option(app,"继续"))
		var s = app.session; var view = app.battle_view
		if not s.battle_open(): check(false,"enter Dream battle"); finish(); return
		var battle: Dictionary = s.state.extensions[Battle.KEY]; var party: Array = battle.party.duplicate()
		check(party.size() == fixture.count,"authored party count "+str(fixture.count))
		check(app._dream_mode() and not app.classic_hud.visible and not app.sidebar.visible,"Dream shares the field instead of the old external HUD")
		check(app.dream_hud.commands.get_children().map(func(c): return c.text) == ["攻击","技能","合击","其他"],"source root command identities")
		check(option(app,"合击",true).disabled,"unimplemented cooperative rule is explicit")
		var authority: Dictionary = s.state.duplicate(true)
		for window_size in [Vector2i(1280,800),Vector2i(1920,1080),Vector2i(1680,720)]:
			root.size = window_size; await settle(); await settle(); await RenderingServer.frame_post_draw
			var bounds: Vector2 = app.viewport.get_visible_rect().size
			var factor: float = minf(bounds.x/320.0,bounds.y/200.0)
			var origin: Vector2 = (bounds-Vector2(320,200)*factor)/2.0
			for i in range(party.size()):
				var expected: Vector2 = Vector2(spec.party[str(fixture.count)][i][0],spec.party[str(fixture.count)][i][1])
				check(view.displayed_bodies[party[i]].anchor.distance_to(origin+expected*factor)<.01,"source party foot %d at %s" % [i,str(window_size)])
				var p: Vector2 = Vector2(spec.hud[str(fixture.count)][i][0],spec.hud[str(fixture.count)][i][1])
				var card: Dictionary = app.dream_hud.cards[party[i]]
				check(card.panel_rect.is_equal_approx(Rect2(p,Vector2(75,35))) and card.face_rect.position.is_equal_approx(p-Vector2(2,4)),"source status and portrait rect %d" % i)
				var world_point = app.dream_hud.get_global_transform()*expected
				check(world_point.distance_to(app.render_surface.get_global_transform()*(origin+expected*factor))<1.5,"HUD and battlefield share one scale %d" % i)
			for i in range(battle.enemies.size()):
				var pos = Vector2(fixture.enemy_positions[i][0],fixture.enemy_positions[i][1])
				check(view.displayed_bodies[battle.enemies[i].instance_id].anchor.distance_to(origin+pos*factor)<.01,"source enemy foot %d" % i)
			for button in app.dream_hud.commands.get_children():
				var p: Array = spec.commands["many" if fixture.count>=4 else "few"][button.symbol]
				check(button.position.is_equal_approx(Vector2(p[0],p[1])) and button.size.is_equal_approx(Vector2(30,30)),"source icon hit rectangle %s at %s size %s" % [button.symbol,str(button.position),str(button.size)])
			check(s.state == authority,"window changes do not modify authority")
			var image: Image = root.get_texture().get_image(); var path = output.path_join("dream-%d-%dx%d.png" % [fixture.count,window_size.x,window_size.y]); image.save_png(path)
			windows.append({"party":fixture.count,"window":[root.size.x,root.size.y],"screenshot":path,"render_pixels":[app.viewport.size.x,app.viewport.size.y],"reference_scale":factor})
		root.size = Vector2i(1280,800); await settle()
		var saved: String = save(app,"dream-initial-"+str(fixture.count))
		await click(option(app,"攻击",true)); var target = option(app,"攻击 2"); target.grab_focus(); await settle()
		check(view.target_ids == [battle.enemies[1].instance_id],"target focus remains bound to enemy instance")
		await key(KEY_ESCAPE); check(app.classic_root and s.state == authority,"target cancel keeps authority")
		await click(option(app,"其他",true)); await click(option(app,"物品",true))
		check(app.item_menu.mode == "items","items reachable through source misc region")
		await key(KEY_ESCAPE); await key(KEY_ESCAPE)
		var attack = option(app,"攻击",true); attack.grab_focus(); await key(KEY_TAB)
		check(root.gui_get_focus_owner() == option(app,"技能",true),"keyboard root focus follows attack to magic")
		await key(KEY_ENTER); check(app.skill_menu.mode == "skills","keyboard activates source magic position")
		var last = option(app,"取消",true); last.grab_focus(); await settle()
		check(app.classic_scroll.get_global_rect().encloses(last.get_global_rect()),"long menu keeps cancel reachable")
		await key(KEY_ESCAPE)
		await click(option(app,"攻击",true)); await click(option(app,"攻击 2"))
		check(view.playing(),"target confirmation starts real action")
		var committed: Dictionary = s.state.duplicate(true)
		view._process(1.0/60); view._process(1.0/100); await settle()
		check(s.state == committed and not app.dream_hud.visible,"display clocks do not apply authority and command HUD hides during action")
		view.skip(); await settle(); save(app,"dream-after-action-"+str(fixture.count))
		check(app.saves.load_into(s,saved),"restore command state and layout from authored package")
		await settle(); check(app.classic_root and app.dream_hud.cards.size() == fixture.count,"restore resets transient controls")
		# Exercise source five-slot defaults without replacing the imported mapping.
		var content: Dictionary = s.package.world.duplicate(true)
		for row in content.extensions["pal.native.battle-layout"].encounters: row.erase("enemy_positions")
		for n in range(1,6):
			for i in range(n):
				var p = Vector2(spec.enemy[str(n)][i][0],spec.enemy[str(n)][i][1])
				check(Battle.Classic.dream_enemy_anchor(content,battle.encounter_id,"enemy.synthetic",i,n).is_equal_approx(p),"named source enemy default %d:%d" % [n,i])
		check(not Battle.Classic.party_issue(content,battle.encounter_id,6).is_empty(),"unsupported sixth source slot is rejected explicitly")
		root.remove_child(app); app.queue_free(); await process_frame
	finish()

func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down; root.push_input(event,true)
	await settle()

func finish() -> void:
	var report = {"checks":checks,"failed":failed,"saves":saves,"windows":windows,"engine_injected_input":true,
		"physical_input":false,"full_playthrough":false,"source_game_executed":false,"synthetic_party_count_variants":true}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Dream reference checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
