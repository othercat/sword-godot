# SPDX-License-Identifier: MIT
extends "res://tests/test_legacy_battle_import.gd"
const Placement = preload("res://src/native_hud_placement.gd")
## Authored variants and real routed GUI input. No legacy parity or art verdict.
var windows: Array = []
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0])).fixtures
	for fixture in fixtures:
		package_path = fixture.package_path; root.size = Vector2i(1280,800)
		var app = App.instantiate(); root.add_child(app); await settle(); root.grab_focus(); await settle()
		app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
		app.saves = Save.new(output.path_join("saves-"+fixture.label))
		check(app.open_package(package_path),"open "+fixture.label)
		if app.session.package == null: finish(); return
		root.grab_focus(); await settle()
		for i in range(30):
			if app.session.battle_open(): break
			var node: Dictionary = app.session.current_node()
			if node.op == "dialogue": check(app.session.advance_dialogue(),"advance authored dialogue")
			elif node.op == "choice":
				var selected: String = ""
				for row in node.options:
					if row.id.ends_with(".train"): selected = row.id
				check(not selected.is_empty() and app.session.advance_dialogue(selected),"select authored training branch")
			else: check(false,"unexpected story entry"); finish(); return
		app._refresh(); await settle()
		var s = app.session; var view = app.battle_view
		if not s.battle_open(): check(false,"battle entry"); finish(); return
		check(app._responsive_mode() and app.dream_hud == app.responsive_hud,"authored HUD selected")
		var authority: Dictionary = s.state.duplicate(true)
		var battle: Dictionary = s.state.extensions[Battle.KEY]
		var placement: Dictionary = Placement.for_encounter(s.package.world,battle.encounter_id)
		check(battle.party.size() == int(fixture.count),"authored party count")
		for size in [Vector2i(1440,960),Vector2i(980,720),Vector2i(1680,900)]:
			root.size = size; await settle(); await RenderingServer.frame_post_draw
			check(s.state == authority,"resize keeps authority")
			var hud = app.dream_hud
			check(view.presentation_rect(view.size).is_equal_approx(hud.boxes.content),"actors and HUD use the same content rectangle including origin")
			if not placement.is_empty():
				var expected = Rect2(hud.size*Vector2(placement.content_region.x,placement.content_region.y)/100,hud.size*Vector2(placement.content_region.width,placement.content_region.height)/100)
				check(hud.boxes.content.is_equal_approx(expected),"authored content region follows viewport percentage")
				check(expected.grow(.01).encloses(view.classic_stage),"actor stage follows reserved region origin")
			for button in app.dream_hud.commands.get_children():
				check(button.get_rect().is_equal_approx(app.dream_hud.boxes.commands[button.symbol]),"resized root command "+button.symbol)
			for id in battle.party:
				var card: Dictionary = app.dream_hud.cards[id]
				check(card.instance_id == id and card.hp == s.entity(id).hp and card.mp == s.entity(id).mp,"HUD reads stable instance")
				if placement.is_empty(): check(not hud.boxes.content.intersects(card.panel_rect),"HUD reserved space")
				else:
					var region = Rect2(hud.size*Vector2(placement.cards_region.x,placement.cards_region.y)/100,hud.size*Vector2(placement.cards_region.width,placement.cards_region.height)/100)
					check(region.grow(.01).encloses(card.panel_rect),"card stays within freely placed group")
					check(card.panel_rect.grow(.01).encloses(card.face_rect),"portrait fits resized card")
					for table in placement.slots_by_count:
						if table.count == battle.party.size():
							var authored: Dictionary = table.slots[battle.party.find(id)]
							var exact = Rect2(region.position+region.size*Vector2(authored.x,authored.y)/100,region.size*Vector2(authored.width,authored.height)/100)
							check(card.panel_rect.is_equal_approx(exact),"manual card follows current seat rectangle")
			var path = output.path_join(fixture.label+"-%dx%d.png" % [size.x,size.y])
			root.get_texture().get_image().save_png(path); windows.append({"path":path,"package_path":package_path,"viewport":[size.x,size.y]})
		root.size = Vector2i(1280,800); await settle(); root.grab_focus(); await settle()
		var initial: String = save(app,"initial-"+fixture.label)
		check(not s.state.extensions.has(Placement.KEY),"placement does not become saved authority")
		var actor: Dictionary = s.entity(battle.party[battle.turn])
		var all_targets: bool = Battle.PlayerPhysical.all_targets(s.package.world,actor.definition_id)
		var target_label: String = "攻击全体" if all_targets else "攻击 2"
		var expected_ids: Array = Battle.PlayerPhysical.order(s.package.world,battle.encounter_id) if all_targets else [battle.enemies[1].instance_id]
		await click(option(app,"攻击",true)); var target = option(app,target_label)
		if target == null: finish(); return
		target.grab_focus(); await settle(); check(view.target_ids == expected_ids,"target focus uses authored enemy identities")
		await key(KEY_ESCAPE); check(app.classic_root and s.state == authority,"cancel leaves state unchanged")
		await click(option(app,"攻击",true)); target = option(app,target_label)
		s.set_pause(true,s._last_usec); await settle()
		var paused_state: Dictionary = s.state.duplicate(true)
		await click(option(app,target_label)); check(s.state == paused_state,"paused routed click cannot commit")
		s.set_pause(false,s._last_usec); await settle(); await click(option(app,target_label))
		check(view.playing(),"routed target starts playback")
		var committed: Dictionary = s.state.duplicate(true)
		check(app.dream_hud.visible and not app.dream_hud.commands.visible,"status overlay stays visible while commands hide")
		for delta in [1.0/60,1.0/144]: view._process(delta)
		await settle(); check(s.state == committed,"display clocks do not recommit")
		for id in view.presentation.actors:
			if app.dream_hud.cards.has(id): check(app.dream_hud.cards[id].hp == view.presentation.actors[id].hp,"HUD follows playback snapshot")
		view.skip(); await settle(); save(app,"after-action-"+fixture.label)
		check(app.saves.load_into(s,initial),"save restores initial command phase"); await settle()
		check(app.classic_root and app.dream_hud.cards.size() == int(fixture.count),"restore rebuilds HUD and root commands")
		await click(option(app,"其他",true)); await click(option(app,"防御",true)); view.skip(); await settle()
		check(s.entity(s.state.extensions[Battle.KEY].party[s.state.extensions[Battle.KEY].turn]).instance_id != actor.instance_id,"normal guard advances to next member")
		await click(option(app,"攻击",true)); target = option(app,"攻击 2")
		if target == null: finish(); return
		target.grab_focus(); await settle(); check(view.target_ids == [s.state.extensions[Battle.KEY].enemies[1].instance_id],"second member single target identity")
		await key(KEY_ESCAPE)
		root.remove_child(app); app.queue_free(); await process_frame
	finish()
func key(code: int) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down; root.push_input(event,true)
	await settle()
func finish() -> void:
	var report = {"success":failed==0,"checks":checks,"failed":failed,"saves":saves,"windows":windows,"engine_injected_input":true,"physical_input":false,"full_playthrough":false,"art_acceptance":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("responsive HUD checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
