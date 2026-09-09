# SPDX-License-Identifier: MIT
extends "res://tests/test_legacy_battle_import.gd"
const Formation = preload("res://src/native_battle_formation.gd")
const Overlay = preload("res://src/native_enemy_overlay.gd")
var windows: Array = []
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	output=args[1];DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0])).fixtures
	var manual_anchors: Dictionary = {}
	for fixture in fixtures:
		package_path=fixture.package_path;root.size=Vector2i(1440,960)
		var app=App.instantiate();root.add_child(app);await settle();root.grab_focus();await settle()
		app.set_process(false);app.set_physics_process(false);app.battle_view.set_process(false)
		app.saves=Save.new(output.path_join("saves-"+fixture.label))
		check(app.open_package(package_path),"open "+fixture.label)
		if app.session.package==null:finish();return
		for i in range(40):
			if app.session.battle_open():break
			var node: Dictionary = app.session.current_node()
			if node.op=="dialogue":check(app.session.advance_dialogue(),"author dialogue")
			elif node.op=="choice":
				var selected: String = ""
				for option in node.options:
					if option.id.ends_with(".train"):selected=option.id
				check(not selected.is_empty() and app.session.advance_dialogue(selected),"training branch")
			else:check(false,"unexpected entry");finish();return
		app._refresh();await settle()
		var s=app.session;var view=app.battle_view
		check(s.battle_open(),"real authored battle reached")
		if not s.battle_open():finish();return
		var battle: Dictionary = s.state.extensions[Battle.KEY]
		var formation: Dictionary = Formation.for_encounter(s.package.world,battle.encounter_id)
		var overlay: Dictionary = Overlay.for_encounter(s.package.world,battle.encounter_id)
		var authority: Dictionary = s.state.duplicate(true)
		check(battle.party.size()==5 and battle.enemies.size()==5,"ten stable battle instances")
		for size in [Vector2i(1440,960),Vector2i(980,720),Vector2i(1680,900)]:
			root.size=size;await settle();await RenderingServer.frame_post_draw
			check(s.state==authority,"resizing never writes combat authority")
			if not formation.is_empty():
				for side in ["party","enemy"]:
					var result: Dictionary = view.formation_diagnostics[side]
					check(result.anchors.size()==5,"each side resolves every instance")
					for id in result.anchors:
						var body: Dictionary = view.displayed_bodies[id]
						check(body.anchor.is_equal_approx(view.projection*result.anchors[id]),"drawing consumes resolved instance anchor")
						check(is_equal_approx(body.sprite_fit,formation[side].scale_milli/1000.0*result.fit),"all actors share side scale")
						if result.fit<1:check(result.region.grow(.01).encloses(result.occupied[id]),"fitted all-action range stays in region")
				for id in view.displayed_markers:
					check(absf(view.displayed_markers[id].get_center().x-view.displayed_bodies[id].visible_rect.get_center().x)<.1,"party marker follows moved body")
					if formation.party.fit=="contain":check(view.classic_stage.grow(.01).encloses(view.displayed_markers[id]),"fitted party marker is fully on actor canvas")
				check(view.displayed_shadows.size()==10,"ten per-instance shadows use new presentation configuration")
				for id in view.displayed_shadows:
					var shadow: Dictionary = view.displayed_shadows[id]
					check(shadow.rect.size.x>shadow.rect.size.y,"authored ground projection is a flat ellipse")
					if shadow.profile.attachment=="visible-foot":check(shadow.rect.get_center().is_equal_approx(shadow.contact),"grounded shadow touches current frame foot without a floating gap")
			if fixture.label=="manual-retreat-larger-bosses":
				var anchors: Dictionary = {}
				for id in view.displayed_bodies:anchors[id]=view.displayed_bodies[id].anchor
				manual_anchors[str(size)]=anchors
			if fixture.label=="manual-enemy-hp-bars":
				for id in view.displayed_bodies:check(view.displayed_bodies[id].anchor==manual_anchors[str(size)][id],"HP overlay keeps manual foot positions")
			if not overlay.is_empty():
				check(view.displayed_enemy_overlays.size()==5,"five enemy overlays bind independent instances")
				for row in battle.enemies:
					var widget: Dictionary = view.displayed_enemy_overlays[row.instance_id]
					check(widget.hp==row.hp and widget.max_hp>=row.hp,"initial HP widget reads instance and effective maximum")
					check(widget.profile==Overlay.for_actor(overlay,row.instance_id),"draw widget resolves per-instance style")
					if overlay.clamp_to_canvas:check(view.presentation_rect(view.size).grow(.1).encloses(widget.rect),"complete health label and bar are clamped to actor canvas")
					var measured: Dictionary = Overlay.metrics(widget.profile,view.display_font)
					check(is_equal_approx(measured.height*widget.factor,widget.rect.size.y),"font metrics and uniformly scaled painted border share the measured widget height")
			var motion=InputEventMouseMotion.new();motion.position=Vector2(5,5);Input.parse_input_event(motion);await settle()
			var path=output.path_join(fixture.label+"-%dx%d.png" % [size.x,size.y])
			root.get_texture().get_image().save_png(path);windows.append({"path":path,"package_path":package_path,"viewport":[size.x,size.y],"formation":str(view.formation_diagnostics)})
		root.grab_focus();await settle()
		var initial: String = save(app,"initial-"+fixture.label)
		check(not s.state.extensions.has(Formation.KEY) and not s.state.extensions.has(Overlay.KEY),"presentation components are not saved authority")
		await click(option(app,"攻击",true));await settle()
		var target=option(app,"攻击全体")
		if target==null:finish();return
		target.grab_focus();await settle()
		check(view.target_ids.size()==5,"authored all-target command retains five stable targets")
		await click(target);await settle()
		check(view.playing(),"routed attack starts normal playback")
		var committed: Dictionary = s.state.duplicate(true)
		for step in range(36):
			view._process(.1);await settle()
			check(s.state==committed,"playback never re-runs damage")
			if not overlay.is_empty() and not view.display_battle().is_empty():
				for row in view.display_battle().enemies:
					check(view.displayed_enemy_overlays[row.instance_id].hp==row.hp,"enemy HP follows displayed hit timeline")
		view.skip();await settle();save(app,"after-attack-"+fixture.label)
		check(app.saves.load_into(s,initial),"restore original matching package save");await settle()
		check(s.state.extensions[Battle.KEY].enemies==authority.extensions[Battle.KEY].enemies,"reload restores HP and enemy identity")
		root.remove_child(app);app.queue_free();await process_frame
	finish()
func finish() -> void:
	var report={"success":failed==0,"failed":failed,"checks":checks,"windows":windows,"saves":saves,"physical_input":false,"full_playthrough":false,"art_acceptance":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("formation checks=%d failed=%d" % [checks.size(),failed]);quit(0 if failed==0 else 1)
