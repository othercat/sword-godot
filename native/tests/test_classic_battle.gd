# SPDX-License-Identifier: MIT
extends SceneTree
## Real window, retained author art and declared 3/4 participant fixture variants.
const App = preload("res://scenes/main.tscn")
const Battle = preload("res://src/native_battle.gd")
const Save = preload("res://src/native_save.gd")
const Package = preload("res://src/native_package.gd")
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
	if args.size() != 6: quit(2); return
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
		for size in [Vector2i(1280,800),Vector2i(1024,768),Vector2i(1920,1080)]:
			root.size = size; await settle(); await settle()
			var bounds = Rect2(Vector2.ZERO,Vector2(app.viewport.size))
			check(bounds.encloses(view.classic_stage) and is_equal_approx(view.classic_stage.size.x/view.classic_stage.size.y,1.6),"classic reference canvas contains full 320x200 image " + str(count) + " " + str(size))
			check(is_equal_approx(view.background_rect.size.x/view.background_rect.size.y,1.6) and view.background_rect.is_equal_approx(view.classic_stage),"real background is uncropped " + str(count) + " " + str(size))
			check(party.all(func(id): return bounds.encloses(view.displayed_bodies[id].rect)),"authored party art fits battlefield " + str(count) + " " + str(size))
			check(app.classic_hud.cards.values().all(func(card): return root.get_visible_rect().encloses(card.panel.get_global_rect())),"all party cards fit actual GUI " + str(count) + " " + str(size))
			var image: Image = root.get_texture().get_image(); var shot = output.path_join("classic-%d-%dx%d.png" % [count,size.x,size.y]); image.save_png(shot)
			windows.append({"party":count,"requested_window":[size.x,size.y],"actual_window":[root.size.x,root.size.y],"captured_pixels":[image.get_width(),image.get_height()],"battle_viewport":[app.viewport.size.x,app.viewport.size.y],"screenshot":shot})
		root.size = Vector2i(1280,800); await settle()
		var before: Dictionary = session.state.duplicate(true)
		await click(app,option(app,"攻击",true)); check(app.classic_attack and session.state == before,"attack opens target stage without committing " + str(count))
		var target = option(app,"攻击 2"); target.grab_focus(); await settle()
		check(view.target_ids == [session.state.extensions[Battle.KEY].enemies[1].instance_id],"keyboard focused enemy has stable target identity " + str(count))
		await key(KEY_ESCAPE); check(not app.classic_attack and session.state == before,"escape returns from target stage without pausing or mutation " + str(count))
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
			await click(app,option(app,"防御",true)); await phases(app,count)
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
		await click(app,option(app,"撤离",true)); await phases(app,count)
		check(not session.battle_open() and not app.classic_mode,"escape result also restores map layout " + str(count))
		var old = weakref(session.package)
		check(app.open_package(args[3]),"existing unmodified package still loads on same app"); await settle()
		check(old.get_ref() == null and not app.classic_mode and app.classic_hud.cards.is_empty(),"package swap releases classic textures and cards")
		await enter(app); check(not app.classic_mode and app.sidebar.visible and option(app,"攻击 1") != null,"old package retains original direct target commands")
		root.remove_child(app); app.queue_free(); await process_frame
	finish()
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
