# SPDX-License-Identifier: MIT
extends "res://tests/test_legacy_battle_import.gd"
## Actual compiled author fixtures, GPU drawing, resize and same-package saves.
const Canvas = preload("res://src/native_battle_canvas.gd")
var windows: Array = []
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0])).fixtures
	var baseline_bodies: Dictionary = {}
	for fixture in fixtures:
		package_path = fixture.package_path; root.size = Vector2i(1440,960)
		var app = App.instantiate(); root.add_child(app); await settle(); root.grab_focus(); await settle()
		app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
		app.saves = Save.new(output.path_join("saves-"+fixture.label))
		check(app.open_package(package_path),"open "+fixture.label)
		if app.session.package == null: finish(); return
		for i in range(40):
			if app.session.battle_open(): break
			var node: Dictionary = app.session.current_node()
			if node.op == "dialogue": check(app.session.advance_dialogue(),"authored dialogue")
			elif node.op == "choice":
				var selected: String = ""
				for row in node.options:
					if row.id.ends_with(".train"): selected = row.id
				check(not selected.is_empty() and app.session.advance_dialogue(selected),"authored training branch")
			else: check(false,"unexpected entry"); finish(); return
		app._refresh(); await settle()
		var s = app.session; var view = app.battle_view
		check(s.battle_open(),"five-versus-five battle reached")
		if not s.battle_open(): finish(); return
		var battle: Dictionary = s.state.extensions[Battle.KEY]
		check(battle.party.size()==5 and battle.enemies.size()==5,"ten stable instances")
		var profile: Dictionary = Canvas.for_encounter(s.package.world,battle.encounter_id)
		if profile.is_empty(): profile = Canvas.default_profile()
		var authority: Dictionary = s.state.duplicate(true)
		for size in [Vector2i(1440,960),Vector2i(980,720),Vector2i(1680,900)]:
			root.size = size; await settle(); await RenderingServer.frame_post_draw
			check(s.state == authority,"resize changes no authority")
			var bounds: Vector2 = view.size
			var region = Rect2(bounds*Vector2(profile.region.x,profile.region.y)/100.0,bounds*Vector2(profile.region.width,profile.region.height)/100.0)
			check(view.background_canvas.is_equal_approx(region),"background uses whole canvas percentages")
			check(region.grow(.01).encloses(view.background_rect),"image stays in authored region")
			if profile.fit != "contain": check(view.background_rect.is_equal_approx(region),"fill modes cover region")
			if profile.fit != "stretch": check(is_equal_approx(view.background_rect.size.x/view.background_source.size.x,view.background_rect.size.y/view.background_source.size.y),"aspect preserved by source sampling")
			var pixel: Color = app.viewport.get_texture().get_image().get_pixel(2,2)
			if profile.region.x > 0:
				var matte = Color(profile.matte)
				check(absf(pixel.r-matte.r)<.02 and absf(pixel.g-matte.g)<.02 and absf(pixel.b-matte.b)<.02,"GPU outside region is authored RGBA matte")
			else: check(pixel.g > pixel.r+.03,"GPU top-left has real forest image instead of old stage letterbox")
			var body_key: String = str(size)
			if fixture.label == "default-cover": baseline_bodies[body_key] = view.displayed_bodies.duplicate(true)
			else: check(view.displayed_bodies == baseline_bodies[body_key],"canvas edit leaves every actor projection and identity unchanged")
			var path = output.path_join(fixture.label+"-%dx%d.png" % [size.x,size.y])
			root.get_texture().get_image().save_png(path); windows.append({"path":path,"package_path":package_path,"viewport":[size.x,size.y],"canvas_size":str(bounds),"background":str(view.background_rect),"source":str(view.background_source)})
		root.size = Vector2i(1440,960); root.grab_focus(); await settle()
		var initial: String = save(app,"initial-"+fixture.label)
		check(not s.state.extensions.has(Canvas.KEY),"background layout is not saved as authority")
		await click(option(app,"其他",true)); await click(option(app,"防御",true)); view.skip(); await settle()
		check(s.state.extensions[Battle.KEY].turn != authority.extensions[Battle.KEY].turn,"normal routed defense advances party turn")
		save(app,"after-guard-"+fixture.label)
		check(app.saves.load_into(s,initial),"same-package initial save restores"); await settle()
		check(s.state.extensions[Battle.KEY].turn == authority.extensions[Battle.KEY].turn,"restore keeps original active actor")
		root.remove_child(app); app.queue_free(); await process_frame
	finish()
func finish() -> void:
	var report = {"success":failed==0,"checks":checks,"failed":failed,"saves":saves,"windows":windows,"physical_input":false,"full_playthrough":false,"art_acceptance":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("battle canvas checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
