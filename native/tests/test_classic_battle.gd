# SPDX-License-Identifier: MIT
extends SceneTree
## Real window, retained author art and declared 3/4 participant fixture variants.
const App = preload("res://scenes/main.tscn")
const Battle = preload("res://src/native_battle.gd")
const Save = preload("res://src/native_save.gd")
const Package = preload("res://src/native_package.gd")
const SessionInventory = preload("res://src/native_inventory.gd")
var checks: Array = []
var windows: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> bool:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
	return ok
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() not in [6,7]: quit(2); return
	output = args[5]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280,800)
	for name in DirAccess.get_files_at(args[4]):
		var package = Package.new()
		check(not package.load_package(args[4].path_join(name)) and not package.error.is_empty(),"reject malformed component " + name)
	for path in args.slice(0,3):
		var app = await open_battle(path)
		if app == null: finish(); return
		var session = app.session; var view = app.battle_view
		var party: Array = session.state.active_party.duplicate(); var count: int = party.size()
		check(app.classic_mode and not app.sidebar.visible and app.classic_hud.visible,"classic opt-in replaces sidebar with bottom cards " + str(count))
		check(app.classic_hud.cards.size() == count and app.classic_hud.cards[party[0]].portrait_asset != "" and party.slice(1).all(func(id): return app.classic_hud.cards[id].portrait_asset == ""),"only matching hero receives portrait " + str(count))
		check(app.classic_root and app.options.get_children().filter(func(c): return c is Button).map(func(c): return c.text) == ["攻击","技能","物品","其他"],"four traditional command entries keep normal Button semantics " + str(count))
		var authority: Dictionary = session.state.duplicate(true)
		for size in [Vector2i(1280,800),Vector2i(1024,768),Vector2i(1920,1080)]:
			root.size = size; await settle(); await settle()
			var bounds: Rect2 = app.viewport.get_visible_rect()
			var transform: Transform2D = root.get_stretch_transform() * app.render_surface.get_global_transform_with_canvas()
			var expected = Vector2i((app.render_surface.size * Vector2(transform.x.length(),transform.y.length())).ceil())
			check(app.viewport.size == expected and app.viewport.get_texture().get_image().get_size() == expected,"battle texture has actual output pixel density " + str(count) + " " + str(size))
			check(Vector2i(bounds.size) == Vector2i(app.render_surface.size) and session.state == authority,"resizing preserves logical drawing and authority " + str(count) + " " + str(size))
			check(app.options.get_children().filter(func(c): return c is Button).all(func(c): return app.classic_scroll.get_global_rect().encloses(c.get_global_rect())),"all four icon hit areas fit without scrolling " + str(count) + " " + str(size))
			check(bounds.encloses(view.classic_stage) and is_equal_approx(view.classic_stage.size.x/view.classic_stage.size.y,1.6),"classic reference canvas contains full 320x200 image " + str(count) + " " + str(size))
			check(is_equal_approx(view.background_rect.size.x/view.background_rect.size.y,1.6) and view.background_rect.is_equal_approx(view.classic_stage),"real background is uncropped " + str(count) + " " + str(size))
			check(party.all(func(id): return bounds.encloses(view.displayed_bodies[id].rect)),"authored party art fits battlefield " + str(count) + " " + str(size))
			check(app.classic_hud.cards.values().all(func(card): return root.get_visible_rect().encloses(card.panel.get_global_rect())),"all party cards fit actual GUI " + str(count) + " " + str(size))
			var image: Image = root.get_texture().get_image(); var shot = output.path_join("classic-%d-%dx%d.png" % [count,size.x,size.y]); image.save_png(shot)
			windows.append({"party":count,"requested_window":[size.x,size.y],"actual_window":[root.size.x,root.size.y],"captured_pixels":[image.get_width(),image.get_height()],"battle_viewport":[app.viewport.size.x,app.viewport.size.y],"logical_battle_size":[bounds.size.x,bounds.size.y],"root_density":[transform.x.length(),transform.y.length()],"screenshot":shot})
		root.size = Vector2i(1280,800); await settle()
		var before: Dictionary = session.state.duplicate(true)
		await click(app,option(app,"攻击",true)); check(app.classic_attack and session.state == before,"attack opens target stage without committing " + str(count))
		var target = option(app,"攻击 2"); target.grab_focus(); await settle()
		check(view.target_ids == [session.state.extensions[Battle.KEY].enemies[1].instance_id],"keyboard focused enemy has stable target identity " + str(count))
		await key(KEY_ESCAPE); check(not app.classic_attack and session.state == before,"escape returns from target stage without pausing or mutation " + str(count))
		await click(app,option(app,"其他",true)); check(app.classic_misc and option(app,"防御",true) != null and option(app,"撤离",true) != null,"other commands expose existing defense and escape " + str(count))
		await key(KEY_ESCAPE); check(app.classic_root and not app.classic_misc and session.state == before,"cancel other commands leaves authority unchanged " + str(count))
		var attack = option(app,"攻击",true); attack.grab_focus(); await key(KEY_TAB)
		check(root.gui_get_focus_owner() == option(app,"技能",true),"Tab follows attack to skill " + str(count))
		await key(KEY_ENTER); check(app.skill_menu.mode == "skills","keyboard activates the focused classic icon " + str(count)); await key(KEY_ESCAPE)
		for menu in ["技能","物品"]:
			await click(app,option(app,menu,true)); var last = option(app,"取消",true); last.grab_focus(); await settle()
			check(app.classic_scroll.get_global_rect().encloses(last.get_global_rect()),"keyboard focus scrolls last " + menu + " command into view " + str(count))
			await key(KEY_ESCAPE); check(session.state == before,"cancel " + menu + " consumes no resources " + str(count))
		await click(app,app.save_button); var saved = app.saves.last_path
		check(not saved.is_empty(),"command boundary save " + str(count)); saves.append({"package_path":path,"save_path":saved})
		# Execute a skill using the same menu used by the player; MP projection enters at cast.
		await click(app,option(app,"技能",true)); await click(app,app.options.get_child(0)); await click(app,app.options.get_child(0))
		check(view.playing(),"skill confirm starts real presentation " + str(count)); await phases(app,count)
		check(app.saves.load_into(session,saved),"load restores initial command state " + str(count)); await settle()
		# Advance through an enemy turn; every visible HP/MP value follows the disposable snapshot.
		for i in range(count):
			await command(app,"防御"); await phases(app,count)
		check(session.entity(party[0]).hp < before.entities[0].hp,"enemy retaliation reaches authoritative HP " + str(count))
		check(app.saves.load_into(session,saved),"load clears playback and transient command page " + str(count)); await settle()
		await click(app,option(app,"攻击",true)); await click(app,option(app,"攻击 1"))
		check(view.playing(),"real attack begins before skip " + str(count)); view.skip(); await settle()
		check(not view.playing() and not app.classic_attack,"skip returns to command root once " + str(count))
		check(app.saves.load_into(session,saved),"load after skip " + str(count)); await settle()
		# Complete the authored encounter using GUI input, retaining the old party through final animation.
		for i in range(100):
			if not session.battle_open(): break
			await click(app,option(app,"攻击",true)); var chosen: Button
			for control in app.options.get_children():
				if control is Button and control.text.begins_with("攻击 ") and not control.disabled: chosen = control; break
			await click(app,chosen)
			if not session.battle_open():
				check(view.playing() and session.state.active_party.size() == 3 and app.classic_hud.cards.size() == count,"final animation retains original party snapshot after scripted retirement " + str(count))
				await phases(app,count)
			else: view.skip(); await settle()
		check(not session.battle_open() and not app.classic_mode and app.sidebar.visible and app.classic_hud.cards.is_empty(),"victory restores map layout and releases HUD " + str(count))
		check(app.saves.load_into(session,saved),"save reload re-enters classic view " + str(count)); await settle()
		await command(app,"撤离"); await phases(app,count)
		check(not session.battle_open() and not app.classic_mode,"escape result also restores map layout " + str(count))
		await defeat(app,path,saved,count)
		var old = weakref(session.package)
		check(app.open_package(args[3]),"existing unmodified package still loads on same app"); await settle()
		check(old.get_ref() == null and not app.classic_mode and app.classic_hud.cards.is_empty(),"package swap releases classic textures and cards")
		await enter(app); check(not app.classic_mode and app.sidebar.visible and option(app,"攻击 1") != null,"old package retains original direct target commands")
		root.remove_child(app); app.queue_free(); await process_frame
	if args.size() == 7: await revival(args[6])
	finish()

func command(app, name: String) -> void:
	if name in ["防御","撤离"] and app.classic_root: await click(app,option(app,"其他",true))
	await click(app,option(app,name,true))

func defeat(app, path: String, baseline: String, count: int) -> void:
	var s = app.session; var view = app.battle_view
	check(app.saves.load_into(s,baseline),"defeat reloads original authored content " + str(count)); await settle()
	var party: Array = s.state.active_party.duplicate(); var death_seen: bool = false
	for step in range(600):
		if not s.battle_open(): break
		if view.playing(): view.skip(); await settle()
		var living: Array = party.filter(func(id): return s.entity(id).hp > 0)
		await command(app,"防御")
		var deaths: Array = living.filter(func(id): return s.entity(id).hp == 0)
		if not deaths.is_empty():
			if not s.battle_open(): check(view.playing() and view.presentation.outcome == "loss" and app.classic_hud.cards.size() == count,"final defeat preserves old party until death animation completes " + str(count))
			await phases(app,count); death_seen = true
			if s.battle_open():
				check(deaths.all(func(id): return view.displayed_frames[id].action == "dead" and app.classic_hud.cards[id].hp == 0),"dead pose and HUD agree after lethal authored hit " + str(count))
				check(s.entity(s.state.extensions[Battle.KEY].party[s.state.extensions[Battle.KEY].turn]).hp > 0,"dead actors do not receive commands " + str(count))
	check(death_seen and not s.battle_open() and party.all(func(id): return s.entity(id).hp == 0),"ordinary guard commands reach all-dead defeat " + str(count))
	if s.battle_open(): return
	await phases(app,count)
	check(not app.classic_mode and app.classic_hud.cards.is_empty() and s.state.cursor.scene_id == "scene.miaopang.camp.loss","defeat restores independent loss scene " + str(count))
	await click(app,option(app,"继续"))
	check(s.state.cursor.node_id == "node.miaopang.camp.loss-end" and not s.state.scopes.run["flag.miaopang.camp.mission"],"loss reaches authored endpoint without mission reward " + str(count))
	var cursor: Dictionary = s.state.cursor.duplicate(true); var effects: Array = s.state.committed_effect_ids.duplicate()
	check(app.saves.save(s),"defeat save " + str(count)); saves.append({"package_path":path,"save_path":app.saves.last_path,"stage":"defeat"})
	check(app.saves.load_into(s,app.saves.last_path) and s.state.cursor == cursor and s.state.committed_effect_ids == effects and not view.playing(),"defeat reload does not replay callbacks " + str(count)); await settle()
	root.size = Vector2i(1920,1080); await settle(); await settle()
	check(app.world_view.scale == Vector2(2,2) and app.viewport.size.x > app.viewport.size_2d_override.x,"map keeps logical camera zoom while raising texture resolution " + str(count))
	root.get_texture().get_image().save_png(output.path_join("map-density-"+str(count)+".png"))

func revival(path: String) -> void:
	# Explicitly authored verification variant: retained art, added revival skill/item.
	var app = await open_battle(path)
	if app == null: return
	var s = app.session; var view = app.battle_view; var hero: String = s.state.active_party[0]
	for step in range(600):
		if s.entity(hero).hp == 0 or not s.battle_open(): break
		if view.playing(): view.skip(); await settle()
		await command(app,"防御")
	check(s.battle_open() and s.entity(hero).hp == 0,"verification variant reaches hero death through authored retaliation")
	if not s.battle_open(): app.queue_free(); return
	await phases(app,5)
	check(app.classic_hud.cards[hero].face.modulate == Color(.4,.4,.4,1) and view.displayed_frames[hero].action == "dead","matching hero portrait dims with dead combat pose")
	check(app.saves.save(s),"revival dead-target baseline save"); var dead_save: String = app.saves.last_path
	saves.append({"package_path":path,"save_path":dead_save,"stage":"dead-target"})
	for menu in ["技能","物品"]:
		check(app.saves.load_into(s,dead_save),"reload same dead target before " + menu); await settle()
		var before: Dictionary = s.state.duplicate(true)
		await command(app,menu); await click(app,option(app,"复活验证"))
		var targets: Array = app.options.get_children().filter(func(c): return c.has_meta("battle_target_ids"))
		check(targets.size() == 5 and targets.filter(func(c): return not c.disabled).all(func(c): return c.get_meta("battle_target_ids") == [hero]),"only dead hero is eligible for " + menu)
		await key(KEY_ESCAPE); check(s.state == before,"cancel revival target consumes nothing " + menu)
		await command(app,menu); await click(app,option(app,"复活验证")); await click(app,option(app,"1 ·"))
		check(view.playing() and s.entity(hero).hp == 60 and view.presentation.actors[hero].hp == 0,"revival authority precedes visible recovery " + menu)
		var expected_kinds: Array = ["cast","revive","heal"] if menu == "技能" else ["item_use","revive","heal"]
		check(view.presentation.phases.filter(func(p): return not p.event.is_empty()).map(func(p): return p.event.kind) == expected_kinds,"revival effects preserve declared order " + menu)
		var acting: String = before.extensions[Battle.KEY].party[before.extensions[Battle.KEY].turn]
		var old_actor: Dictionary = before.entities.filter(func(e): return e.instance_id == acting)[0]
		check(s.entity(acting).mp == old_actor.mp-(3 if menu == "技能" else 0),"revival consumes MP exactly once only for skill " + menu)
		check(SessionInventory.count(s.state,"item.miaopang.camp.revive-check") == (1 if menu == "技能" else 0),"revival item consumed exactly once only for item " + menu)
		var observed: Array = []
		while view.playing():
			observed.append({"hp":view.presentation.actors[hero].hp,"pose":view.displayed_frames[hero].action})
			var phase: Dictionary = view.presentation.current()
			view._process((phase.duration_us-view.presentation.elapsed_us+1)/1000000.0); await settle()
		check(observed.any(func(row): return row.hp == 24 and row.pose == "dying") and view.displayed_frames[hero].action == "idle" and app.classic_hud.cards[hero].hp == 60,"revive then heal updates pose and HUD by event " + menu)
		check(app.classic_hud.cards[hero].face.modulate == Color.WHITE,"revival restores portrait color " + menu)
		check(app.saves.save(s),"revival settled save " + menu); saves.append({"package_path":path,"save_path":app.saves.last_path,"stage":"revive-"+menu})
		var committed: Dictionary = s.state.duplicate(true)
		check(app.saves.load_into(s,app.saves.last_path) and s.state.entities == committed.entities and s.state.extensions == committed.extensions and not view.playing(),"revival save reload does not repeat consumption or animation " + menu)
	root.remove_child(app); app.queue_free(); await process_frame
func phases(app, count: int) -> void:
	var view = app.battle_view; var session = app.session; var authority: Dictionary = session.state.duplicate(true)
	if view.playing():
		for mode in ["pause","focus"]:
			if mode == "pause": session.set_pause(true,session._last_usec)
			else: session.set_focus(false,session._last_usec)
			var phase: int = view.presentation.phase_index; var elapsed: float = view.presentation.elapsed_us
			view._process(3.0)
			check(view.presentation.phase_index == phase and view.presentation.elapsed_us == elapsed,mode+" freezes display " + str(count))
			if mode == "pause": session.set_pause(false,session._last_usec)
			else: session.set_focus(true,session._last_usec)
	for i in range(500):
		if not view.playing(): break
		var ids: Array = view.display_battle().party
		check(ids.all(func(id): return app.classic_hud.cards[id].hp == view.presentation.actors[id].hp and app.classic_hud.cards[id].mp == view.presentation.actors[id].mp),"HUD matches displayed phase HP MP " + str(count) + ":" + str(i))
		var remaining: float = (view.presentation.current().duration_us-view.presentation.elapsed_us+1)/1000000.0
		view._process(remaining); await settle()
	check(not view.playing() and session.state == authority,"presentation completion does not recalculate authority " + str(count))
func open_battle(path: String):
	var app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
	app.saves = Save.new(output.path_join("saves"))
	if not check(app.open_package(path),"package loads " + path): app.queue_free(); return null
	app.session.set_focus(true); await settle(); await enter(app)
	if not check(app.session.battle_open(),"authored opening enters encounter"): app.queue_free(); return null
	return app
func enter(app) -> void:
	await click(app,option(app,"继续")); await click(app,option(app,"五人")); await click(app,option(app,"继续"))
func option(app, prefix: String, exact: bool = false) -> Button:
	for child in app.options.get_children():
		if child is Button and (child.text == prefix if exact else child.text.begins_with(prefix)): return child
	check(false,"missing command " + prefix); return null
func settle() -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
func click(app, control: Control) -> void:
	if control == null: return
	control.grab_focus(); await settle()
	for down in [true,false]:
		var e = InputEventMouseButton.new(); e.position = control.get_global_rect().get_center(); e.global_position = e.position; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; root.push_input(e,true)
	await settle()
func key(code: Key) -> void:
	for down in [true,false]:
		var e = InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down; root.push_input(e,true)
	await settle()
func finish() -> void:
	var report = {"checks":checks,"failed":failed,"windows":windows,"saves":saves,"engine_injected_input":true,"physical_input":false,"full_playthrough":false,"synthetic_party_variants":[3,4],"authored_party":5}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")); print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
