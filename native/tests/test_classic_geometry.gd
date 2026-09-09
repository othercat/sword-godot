# SPDX-License-Identifier: MIT
extends SceneTree
## Retained real artwork; party-count and extreme action records are declared fixtures.
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
var checks: Array = []
var windows: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	for fixture in fixtures:
		root.size = Vector2i(1280,800)
		var app = App.instantiate(); root.add_child(app); await settle()
		app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
		app.saves = Save.new(output.path_join("saves"))
		check(app.open_package(fixture.path),fixture.name+" package loads")
		root.grab_focus(); await settle()
		app.session.set_focus(true,app.session._last_usec); await settle()
		await click(option(app,"继续")); await click(option(app,"五人")); await click(option(app,"继续"))
		var s = app.session; var view = app.battle_view
		check(s.battle_open() and s.state.active_party.size() == fixture.party,fixture.name+" authored party enters classic battle")
		var before: Dictionary = s.state.duplicate(true)
		for size in [Vector2i(1280,800),Vector2i(1024,768),Vector2i(1920,1080),Vector2i(1680,720)]:
			root.size = size; await settle(); await settle()
			await geometry(app,fixture,"idle")
			check(s.state == before,fixture.name+" window resizing preserves authority "+str(size))
			var image = root.get_texture().get_image()
			check(root.size == size and image.get_size() == size,fixture.name+" root GUI uses full actual window "+str(size))
			var shot = output.path_join(fixture.name+"-%dx%d.png" % [size.x,size.y]); image.save_png(shot)
			windows.append({"case":fixture.name,"party":fixture.party,"requested":[size.x,size.y],"actual":[root.size.x,root.size.y],"captured":[image.get_width(),image.get_height()],"logical_gui":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"battle_pixels":[app.viewport.size.x,app.viewport.size.y],"screenshot":shot})
		root.size = Vector2i(1280,800); await settle(); await settle()
		check(app.saves.save(s),fixture.name+" initial command save"); var baseline: String = app.saves.last_path
		saves.append({"package_path":fixture.path,"save_path":baseline})
		await click(option(app,"攻击",true)); var target = option(app,"攻击 2")
		target.grab_focus(); await settle()
		var target_ids: Array = view.target_ids.duplicate()
		root.size = Vector2i(1680,720); await settle(); await settle()
		check(view.target_ids == target_ids and root.gui_get_focus_owner() == target,fixture.name+" resize retains exact target identity and focus")
		await key(KEY_ENTER)
		check(view.playing(),fixture.name+" GUI Enter commits selected attack")
		var committed: Dictionary = s.state.duplicate(true); var phase_checks: int = 0
		while view.playing():
			var phase: Dictionary = view.presentation.current()
			view._process((phase.duration_us*.5-view.presentation.elapsed_us)/1000000.0)
			await settle(); await geometry(app,fixture,"phase-"+str(phase_checks)); phase_checks += 1
			if phase.action == "attack" and phase_checks == 1: root.get_texture().get_image().save_png(output.path_join(fixture.name+"-attack.png"))
			view._process((phase.duration_us-view.presentation.elapsed_us+1)/1000000.0); await settle()
		check(phase_checks > 1 and s.state == committed,fixture.name+" all action phases preserve committed authority")
		check(app.saves.save(s),fixture.name+" post action save"); saves.append({"package_path":fixture.path,"save_path":app.saves.last_path})
		check(app.saves.load_into(s,baseline) and not view.playing(),fixture.name+" restore returns to command state without replay")
		root.remove_child(app); app.queue_free(); await process_frame
	var r = {"checks":checks,"failed":failed,"windows":windows,"saves":saves,"engine_injected_input":true,"physical_input":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(r,"\t"))
	print("classic geometry checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
func geometry(app, fixture: Dictionary, phase: String) -> void:
	var view = app.battle_view; var bounds: Rect2 = app.viewport.get_visible_rect()
	var label: String = fixture.name+" "+phase+" "+str(root.size)
	check(view.displayed_bodies.values().all(func(body): return bounds.encloses(body.rect)),label+" complete sprite rectangles remain inside battlefield")
	check(view.displayed_bodies.values().all(func(body): return bounds.has_point(body.anchor) and bounds.has_point(body.effect_origin)),label+" feet and result text stay visible")
	check(app.options.get_children().filter(func(c): return c is Button).all(func(c): return app.classic_scroll.get_global_rect().encloses(c.get_global_rect())),label+" command hit areas fit")
	check(app.classic_hud.cards.values().all(func(c): return root.get_visible_rect().encloses(c.panel.get_global_rect())),label+" all party information remains visible")
	check(app.classic_hud.size.x <= fixture.party*246+1 and app.classic_hud.cards.values().all(func(c): return c.panel.size.x >= 200),label+" party cards remain compact and readable")
	check(is_equal_approx(view.background_rect.size.x/view.background_rect.size.y,1.6),label+" background retains original aspect")
	var tr: Transform2D = root.get_stretch_transform()*app.render_surface.get_global_transform_with_canvas()
	var pixels = Vector2i((app.render_surface.size*Vector2(tr.x.length(),tr.y.length())).ceil())
	check(app.viewport.size == pixels,label+" battlefield uses output pixel density")
	if fixture.get("extreme",false) and view.displayed_bodies.has("instance.miaopang.camp.fist"):
		check(view.displayed_bodies["instance.miaopang.camp.fist"].get("sprite_fit",1.0) == 1.0,label+" oversized hero does not shrink normal companions")
func option(app, prefix: String, exact: bool = false) -> Button:
	for c in app.options.get_children():
		if c is Button and (c.text == prefix if exact else c.text.begins_with(prefix)): return c
	check(false,"missing command "+prefix); return null
func click(control: Control) -> void:
	if control == null: return
	control.grab_focus(); await settle()
	for down in [true,false]:
		var e = InputEventMouseButton.new(); e.position = control.get_global_rect().get_center(); e.global_position = e.position; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; root.push_input(e,true)
	await settle()
func key(code: Key) -> void:
	for down in [true,false]:
		var e = InputEventKey.new(); e.keycode = code; e.physical_keycode = code; e.pressed = down; root.push_input(e,true)
	await settle()
func settle() -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
