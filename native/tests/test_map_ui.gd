# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const Config = preload("res://src/native_map_ui.gd")
var checks: Array = []
var failed: int = 0
var output: String
var saves: Array = []
var app

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks.append({"name":label, "passed":ok})
	if not ok: failed += 1; push_error(label)
	return ok
func settle() -> void:
	for _i in range(3): await process_frame
	await RenderingServer.frame_post_draw
func capture(label: String) -> void:
	await settle(); root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func record_save(package_path: String, label: String) -> String:
	app.saves = Save.new(output.path_join(label))
	if not check(app.saves.save(app.session), "actual save " + label): return ""
	saves.append({"package_path":package_path, "save_path":app.saves.last_path, "label":label})
	return app.saves.last_path
func finish() -> void:
	var report = {"checks":checks, "failed":failed, "passed":checks.size()-failed, "saves":saves, "physical_input":false, "packaged_player":false, "human_art_acceptance":false, "full_playthrough":false, "renderer":RenderingServer.get_current_rendering_method(), "adapter":RenderingServer.get_video_adapter_name()}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print(JSON.stringify({"failed":failed, "checks":checks.size(), "saves":saves.size()})); quit(0 if failed == 0 else 1)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() not in [3, 4]: quit(2); return
	output = args[2]; DirAccess.make_dir_recursive_absolute(output)
	var baseline = Package.new()
	if not check(baseline.load_package(args[1]), "baseline package admits unchanged v1 contracts"): finish(); return
	app = App.instantiate(); root.add_child(app); await process_frame
	app.set_process(false); app.set_physics_process(false)
	var sidebar_flags: int = app.sidebar.size_flags_horizontal
	var dialogue_flags: int = app.dialogue.size_flags_horizontal
	if not check(app.open_package(args[0]), "GUI-authored map UI package admitted"): push_error(app.message.text); finish(); return
	app.session.focused = true; await settle()
	var package = app.session.package; var profile: Dictionary = Config.for_scene(package.world, app.session.state.cursor.scene_id)
	check(app.map_ui.active and app.map_ui.surface.visible and not app.map_ui.body.visible, "authored workspace replaces only map body")
	check(package.world.maps == baseline.world.maps and package.world.entities == baseline.world.entities and package.world.nodes == baseline.world.nodes, "authored UI package preserves real tilemap, placements and story")
	check(app._camera_overview and app.world_view.show_actor_names and app._camera_zoom == 1.5, "author overview, names and follow zoom take effect")
	check(app.dialogue_text.get_theme_font_size("font_size") == 22 and app.dialogue_text.get_theme_color("font_color") == Color("#e4d5b5ff"), "dialogue uses authored font and RGBA")
	for size in [Vector2i(1280,800), Vector2i(1600,900)]:
		root.size = size; await settle()
		for element in profile.elements:
			var actual: Control = app.map_ui.layers[element.kind].layer; var r: Dictionary = element.rect
			var expected = Rect2(app.map_ui.surface.size*Vector2(r.x,r.y)/100.0,app.map_ui.surface.size*Vector2(r.width,r.height)/100.0)
			check(actual.get_rect().is_equal_approx(expected), "%s authored rectangle follows actual workspace %s" % [element.kind,size])
		check(app.stage.get_parent() == app.map_ui.layers.map.layer and app.viewport.size_2d_override == Vector2i(app.stage.size), "render viewport matches authored map region after resize")
	await capture("map-ui-authored")
	var authority: Dictionary = app.session.snapshot()
	app.map_zoom.value = 1.25; app.map_overview.button_pressed = false; app.map_names.button_pressed = false; await settle()
	check(app._camera_zoom == 1.25 and not app._camera_overview and not app.world_view.show_actor_names, "explicit player controls override author defaults")
	check(app.session.snapshot() == authority and not app.session.state.extensions.has(Config.KEY), "player view controls never enter authority or saves")
	await capture("map-ui-follow")
	var saved = record_save(args[0], "before-dialogue")
	app.dialogue_text.text += "\n".repeat(50) + "长对白可达性探针"
	await settle(); var scroll: ScrollContainer = app.map_ui.layers.dialogue.scroll
	check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "long dialogue uses a real scroll range")
	var button: Button = app.options.get_children()[0]; button.grab_focus(); await settle()
	check(scroll.scroll_vertical > 0, "focus brings continue button into the dialogue scroll view")
	app._refresh(); await settle()
	check(app.saves.load_into(app.session, saved), "load actual UI-authored save")
	app.session.focused = true; await settle()
	check(app._camera_zoom == 1.25 and not app._camera_overview and not app.world_view.show_actor_names, "save load preserves explicit local view overrides")
	app.map_ui.reset_camera(app); await settle()
	check(app._camera_overview and app.world_view.show_actor_names and app._camera_zoom == 1.5, "restore author view clears local overrides")
	# Compare real movement/collision commands in packages differing only by UI.
	var shadow = Session.new(); check(shadow.activate(baseline, 1000), "activate independent baseline movement consumer")
	for _step in range(20):
		if not app.session.dialogue_open: break
		var node: Dictionary = app.session.current_node(); var choice: String = ""
		if node.op == "choice": choice = node.options.filter(func(o): return o.id.ends_with(".skip"))[0].id
		check(app.session.advance_dialogue(choice) and shadow.advance_dialogue(choice), "same initial dialogue path in authored and baseline packages")
	check(not app.session.dialogue_open and not shadow.dialogue_open, "both packages reach real map walking")
	var moved: int = 0; var rejected: int = 0
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.ZERO]:
		for _i in range(8): app.session.tick(); shadow.tick()
		var result: bool = app.session.move(direction); var control: bool = shadow.move(direction)
		if result: moved += 1
		else: rejected += 1
		check(result == control and app.session.state.entities == shadow.state.entities, "map UI keeps movement result, feet, followers and collision for " + str(direction))
	check(moved > 0 and rejected > 0, "comparison includes successful walk and rejected command")
	await capture("map-ui-walking")
	record_save(args[0], "after-walking")
	# Return through a real save, enter the existing practice battle, then load out.
	check(app.saves.load_into(app.session, saved), "restore opening to exercise battle transition")
	app.session.focused = true; app.session.advance_dialogue()
	check(app.session.advance_dialogue("choice.miaopang.camp.practice-choice.train") and app.session.advance_dialogue(), "existing five-person practice path enters battle")
	await settle()
	check(app.session.battle_open() and not app.map_ui.active and app.map_ui.body.visible, "battle restores legacy presentation parents")
	check(app.stage.get_parent() == app.center and app.dialogue.get_parent() == app.center, "non-classic battle keeps its original stage and dialogue consumers")
	check(app.sidebar.size_flags_horizontal == sidebar_flags and app.dialogue.size_flags_horizontal == dialogue_flags, "battle restores original container sizing flags, not only parents")
	check(app.dialogue_text.get_theme_font_size("font_size") == 20, "map font override does not leak into battle")
	check(not app.map_reset.visible, "map-only reset control does not alter legacy battle UI")
	await capture("map-ui-battle-restored")
	check(app.saves.load_into(app.session, saved), "real save returns from battle to authored map")
	app.session.focused = true; await settle()
	check(app.map_ui.active and app.dialogue_text.get_theme_font_size("font_size") == 22, "map presentation reapplies after battle save restore")
	app.map_zoom.value = 1.0; await settle()
	check(app.open_package(args[1]), "switch to unbound baseline package")
	app.session.focused = true; await settle()
	check(not app.map_ui.active and app.map_ui.player_camera.is_empty() and app.dialogue.get_parent() == app.center, "package switch releases authored layout and local overrides")
	check(app.open_package(args[0]), "reopen authored map package")
	app.session.focused = true; await settle()
	check(app.map_ui.active and app._camera_overview and app._camera_zoom == 1.5, "new package instance reapplies only its author defaults")
	await capture("map-ui-reopened")
	record_save(args[0], "reopened")
	if args.size() == 4:
		check(app.open_package(args[3]), "existing v2 battle-card package still admitted")
		app.session.focused = true; await settle()
		check(app.session.advance_dialogue() and app.session.battle_open(), "existing v2 fixture reaches battle through its opening dialogue")
		await settle()
		check(app.classic_mode and not app.map_ui.active and app.dialogue.get_parent() == app.classic_scroll, "responsive battle keeps its own command container after map switch")
		await capture("map-ui-v2-battle-preserved")
		check(app.open_package(args[0]), "return from responsive battle to authored map")
		app.session.focused = true; await settle()
		check(app.map_ui.active and not app.classic_mode and app.dialogue.get_parent() == app.map_ui.layers.dialogue.scroll, "map restores correctly from classic command container")
	finish()
