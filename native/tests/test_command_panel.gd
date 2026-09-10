# SPDX-License-Identifier: MIT
extends "res://tests/test_legacy_battle_import.gd"
const CommandPanel = preload("res://src/native_command_panel.gd")
const CommandButton = preload("res://src/native_classic_command_button.gd")
const StatePreviewButton = preload("res://tests/command_state_preview_button.gd")
var windows: Array = []
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size()!=2: quit(2); return
	output=args[1];DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0])).fixtures
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
				for choice in node.options:
					if choice.id.ends_with(".train"):selected=choice.id
				check(not selected.is_empty() and app.session.advance_dialogue(selected),"training branch")
			else:check(false,"unexpected entry");finish();return
		app._refresh();await settle()
		var s=app.session;var view=app.battle_view
		check(s.battle_open(),"authored five-person battle reached")
		if not s.battle_open():finish();return
		var battle: Dictionary = s.state.extensions[Battle.KEY]
		var profile: Dictionary = CommandPanel.for_encounter(s.package.world,battle.encounter_id)
		var authority: Dictionary = s.state.duplicate(true); var world_before: Dictionary = s.package.world.duplicate(true)
		for extent in [Vector2i(1440,960),Vector2i(980,720),Vector2i(1680,900)]:
			root.size=extent;await settle();await RenderingServer.frame_post_draw
			check(s.state==authority,"window resize keeps combat authority")
			if not profile.is_empty():
				var layout: Dictionary = CommandPanel.geometry(profile,app.responsive_hud.boxes.content)
				for button in app.responsive_hud.commands.get_children():
					check(button.get_rect().is_equal_approx(layout.buttons[button.symbol]),"actual hit rectangle matches authored geometry after resize")
					var row: Dictionary = profile.buttons.filter(func(b):return b.command==button.symbol)[0]
					check(button.skin.is_empty()==(row.appearance=="builtin"),"image/text appearance independently bound")
					if row.appearance=="image":
						for sprite in row.sprites:check(button.skin["command."+button.symbol+"."+sprite.state]==s.package.textures[sprite.asset_id],"original texture object retained for "+button.symbol+" "+sprite.state)
					if button.symbol=="cooperative":check(button.disabled,"skin cannot enable absent cooperative rules")
				check(app.responsive_hud.boxes.content.grow(.01).encloses(layout.panel),"default clamp keeps whole group in play region")
			var motion=InputEventMouseMotion.new();motion.position=Vector2(5,5);Input.parse_input_event(motion);await settle()
			var path=output.path_join(fixture.label+"-%dx%d.png" % [extent.x,extent.y]);root.get_texture().get_image().save_png(path)
			windows.append({"path":path,"package_path":package_path,"viewport":[extent.x,extent.y]})
		root.grab_focus();await settle()
		var initial: String = save(app,"initial-"+fixture.label)
		# Exercise the same disposal/rebuild calls used when battle closes, retaining this live package.
		app._set_classic_mode(false);await settle();check(s.package.world==world_before,"leaving HUD never mutates package command profile")
		app._refresh();await settle();check(s.package.world==world_before,"reopening HUD keeps every command binding")
		await click(option(app,"攻击",true));await settle();var target=option(app,"攻击全体")
		if target==null:finish();return
		await click(target);await settle();check(view.playing(),"original command image reaches ordinary attack target and animation")
		view.skip();await settle();save(app,"after-attack-"+fixture.label)
		check(app.saves.load_into(s,initial),"matching package save restores after action");app._refresh();await settle()
		check(s.package.world==world_before,"attack and reload preserve presentation content")
		if fixture.label in ["original-bronze-states","original-default-states"]:await artwork_sheet(app,profile,fixture.label)
		if not profile.is_empty():await small_rectangles(profile,s.package)
		root.remove_child(app);app.queue_free();await process_frame
	finish()
func small_rectangles(profile: Dictionary, package) -> void:
	var p: Dictionary = profile.duplicate(true)
	for requested in [Vector2(100,10),Vector2(3.4,3.4),Vector2(.05,.05)]:
		for mode in ["builtin","image"]:
			var button=CommandButton.new();button.symbol="attack";button.text="攻击";root.add_child(button)
			p.buttons.filter(func(b):return b.command=="attack")[0].appearance=mode
			CommandPanel.apply_button(button,p,package);button.reference_size=0;button.custom_minimum_size=requested;button.size=requested;await settle()
			check(button.size.is_equal_approx(requested),"authored "+mode+" rectangle not enlarged by native Button text: "+str(requested))
			check(button.accessibility_name=="攻击","authored image retains accessible command name")
			button.disabled=true;check(button.skin_state()=="disabled","disabled color only selected for disabled command")
			button.disabled=false;check(button.skin_state()!="disabled","available command restores normal or focused appearance")
			check(button.get_combined_minimum_size().x<=requested.x+.001 and button.get_combined_minimum_size().y<=requested.y+.001,"minimum size respects small non-square authored button")
			root.remove_child(button);button.queue_free();await process_frame
func artwork_sheet(app, profile: Dictionary, name: String) -> void:
	await cooperative_state_transition(app,profile,name=="original-default-states")
	var viewport=SubViewport.new();viewport.size=Vector2i(600,680);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var background=ColorRect.new();background.color=Color("161b16");background.size=viewport.size;viewport.add_child(background)
	var font: Font=app.battle_view.display_font
	var label=Label.new();label.text="操作盘原图 · 默认三态" if name=="original-default-states" else "操作盘原图 · 备用配色";label.position=Vector2(18,12);label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",24);background.add_child(label)
	for i in range(3):
		var heading=Label.new();heading.text=["正常","选中","不可用"][i];heading.position=Vector2(130+i*150,55);heading.add_theme_font_override("font",font);background.add_child(heading)
	var commands=["attack","skills","cooperative","misc"]
	for row in range(4):
		var name_label=Label.new();name_label.text=["攻击","术","合体","其他"][row];name_label.position=Vector2(22,132+row*132);name_label.add_theme_font_override("font",font);background.add_child(name_label)
		for column in range(3):
			var button=StatePreviewButton.new();button.symbol=commands[row];button.text=name_label.text;background.add_child(button)
			CommandPanel.apply_button(button,profile,app.session.package);button.preview_state=["normal","focus","disabled"][column];button.disabled=column==2
			button.position=Vector2(112+column*150,85+row*132);button.custom_minimum_size=Vector2(120,120);button.size=Vector2(120,120)
	var foot=Label.new();foot.text="原图造型与RGBA显示调色；素材对照不代表指令已可用。";foot.position=Vector2(18,636);foot.add_theme_font_override("font",font);foot.add_theme_font_size_override("font_size",16);background.add_child(foot)
	await settle();await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(output.path_join(name+"-three-states.png"))
	root.remove_child(viewport);viewport.queue_free();await process_frame
func cooperative_state_transition(app, profile: Dictionary, distinct_disabled_art: bool) -> void:
	# Render the real button, without overriding skin_state or enabling a battle rule.
	var viewport=SubViewport.new();viewport.size=Vector2i(120,120);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var button=CommandButton.new();button.symbol="cooperative";button.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.focus_mode=Control.FOCUS_NONE
	viewport.add_child(button);CommandPanel.apply_button(button,profile,app.session.package)
	button.custom_minimum_size=Vector2(120,120);button.size=Vector2(120,120)
	await settle();await RenderingServer.frame_post_draw
	check(button.skin_state()=="normal","available cooperative button selects normal artwork")
	var normal=viewport.get_texture().get_image().get_data()
	button.disabled=true
	await settle();await RenderingServer.frame_post_draw
	check(button.skin_state()=="disabled","unavailable cooperative button selects disabled artwork")
	if distinct_disabled_art:
		check(viewport.get_texture().get_image().get_data()!=normal,"original dark-red disabled artwork differs from available artwork on GPU")
	button.disabled=false
	await settle();await RenderingServer.frame_post_draw
	check(button.skin_state()=="normal","reenabled cooperative button returns to normal state")
	check(viewport.get_texture().get_image().get_data()==normal,"reenabled cooperative button restores identical normal pixels")
	root.remove_child(viewport);viewport.queue_free();await process_frame
func finish() -> void:
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"success":failed==0,"failed":failed,"checks":checks,"windows":windows,"saves":saves,"physical_input":false,"full_playthrough":false,"art_acceptance":false},"\t"))
	print("command panel checks=%d failed=%d" % [checks.size(),failed]);quit(0 if failed==0 else 1)
