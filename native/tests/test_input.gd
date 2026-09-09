# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Keys = preload("res://src/native_key_bindings.gd")
const Save = preload("res://src/native_save.gd")
const Battle = preload("res://src/native_battle.gd")
var app
var output: String
var spec: Dictionary
var checks: Array = []
var saves: Array = []
var failed: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func settle() -> void:
	await process_frame; await process_frame; await process_frame
func event(code: int, pressed: bool = true, echo: bool = false, physical: int = 0, location: int = 0) -> InputEventKey:
	var e = InputEventKey.new(); e.keycode = code; e.physical_keycode = physical if physical else code
	e.pressed = pressed; e.echo = echo; e.location = location; return e
func key(code: int, location: int = 0) -> void:
	root.push_input(event(code,true,false,0,location),true); await settle()
	root.push_input(event(code,false,false,0,location),true); await settle()
func click(control: Control) -> void:
	if control == null: check(false,"clickable control exists"); return
	var point: Vector2 = control.get_global_rect().get_center()
	if control.get_window() != root: point += Vector2(control.get_window().position)
	for down in [true,false]:
		var e = InputEventMouseButton.new(); e.position = point; e.global_position = point; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; root.push_input(e,true)
	await settle()
func option(prefix: String) -> Button:
	for control in app._battle_controls():
		if control is Button and control.text.begins_with(prefix): return control
	check(false,"control exists: " + prefix); return null
func state() -> Dictionary: return app.session.state.duplicate(true)
func drain() -> void: app.battle_view.skip(); await settle()
func save(label: String) -> String:
	await key(KEY_F5)
	var path: String = app.saves.last_path; check(not path.is_empty(),label+" via F5")
	saves.append({"package_path":spec.package,"save_path":path,"label":label}); return path
func restored(path: String) -> void:
	check(app.saves.load_into(app.session,path),"restore isolated baseline"); await settle()
func finish() -> void:
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"saves":saves,
		"physical_input":false,"full_playthrough":false,"platform_input_parity":false,
		"evidence_kind":"windowed-engine-injected-keyboard-and-mouse; parser and focus signals synthetic",
		"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	print("input checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
func run() -> void:
	var args = OS.get_cmdline_user_args(); if args.size() != 2: quit(2); return
	spec = JSON.parse_string(FileAccess.get_file_as_string(args[0])); output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	parser_checks()
	root.size = Vector2i(1280,800)
	app = App.instantiate(); app.input_profile_path = output.path_join("input.json"); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
	var header_button: Button = app.pause_button.get_parent().get_children().filter(func(c): return c is Button and c.text == "按键")[0]
	app.pause_button.grab_focus()
	for i in range(8):
		if root.gui_get_focus_owner() == header_button: break
		await key(KEY_TAB)
	check(root.gui_get_focus_owner() == header_button,"Tab reaches visible header settings")
	await key(KEY_ENTER)
	check(app.input_settings.visible,"Enter activates focused header settings before a package is loaded")
	app.input_settings.hide(); await settle()
	header_button.grab_focus(); await key(KEY_TAB)
	check(root.gui_get_focus_owner() == app.frame_selector,"Tab reaches FPS selector from settings")
	await key(KEY_ENTER)
	check(app.frame_selector.get_popup().visible and app.session.modal,"confirm opens actual FPS popup and blocks gameplay input")
	await key(KEY_DOWN); await key(KEY_ENTER)
	check(Engine.max_fps == 100 and not app.frame_selector.get_popup().visible and not app.session.modal,"keyboard selects 100 FPS and returns from popup")
	app.frame_selector.select(0); Engine.max_fps = 60; app.frame_selector.release_focus()
	app.saves = Save.new(output.path_join("saves")); check(app.open_package(spec.package),"unchanged authored package loads")
	if app.session.package == null: finish(); return
	app.session.set_focus(true,app.session._last_usec); await settle()
	check(app.key_bindings.profile.preset == "classic","new installation uses traditional PC controls")
	var lock: String = app.session.state.content_lock
	await key(KEY_ENTER)
	check(app.session.current_node().op == "choice","confirm advances one dialogue node only")
	option("五人").grab_focus(); await key(KEY_ENTER); await key(KEY_SPACE)
	check(app.session.battle_open() and app.session.state.active_party.size() == 5,"keyboard choices enter existing five-member story encounter")
	if not app.session.battle_open(): finish(); return
	var initial: String = await save("initial command point")
	var before: Dictionary = state()
	option("攻击").grab_focus(); root.push_input(event(KEY_ENTER),true); await settle()
	root.push_input(event(KEY_ENTER,true,true),true); await settle()
	check(app.classic_attack and state() == before,"held confirm and OS repeat open target stage without attacking")
	root.push_input(event(KEY_ENTER,false),true); await settle()
	var first: Button = option("攻击 1"); first.grab_focus(); await key(KEY_RIGHT)
	var enemy_id: String = app.session.state.extensions[Battle.KEY].enemies[1].instance_id
	check(app.battle_view.target_ids == [enemy_id],"direction selects second target using stable instance preview")
	await key(KEY_CTRL,KEY_LOCATION_LEFT)
	check(app.session.state.extensions[Battle.KEY].enemies[0].hp == 28 and app.session.state.extensions[Battle.KEY].enemies[1].hp == 0,"left Ctrl confirms selected target exactly once")
	before = state()
	for code in [KEY_D,KEY_ENTER,KEY_F,KEY_RIGHT]: await key(code)
	check(app.battle_view.playing() and state() == before,"action playback rejects extra combat and movement keys")
	await key(KEY_ESCAPE); check(app.session.paused,"cancel pauses playback")
	await key(KEY_ESCAPE); check(not app.session.paused,"cancel resumes paused playback")
	await drain(); await save("keyboard target committed")
	await restored(initial)
	before = state()
	await key(KEY_F); check(app.skill_menu.mode == "skills","F opens current actor skills")
	await key(KEY_E); check(app.item_menu.mode == "items" and app.skill_menu.mode == "closed","E switches to items with no competing skill menu")
	await key(KEY_F); check(app.skill_menu.mode == "skills" and app.item_menu.mode == "closed","F switches back without stale item selection")
	await key(KEY_ENTER); check(app.skill_menu.mode == "targets","confirm chooses an enabled skill")
	await key(KEY_ALT,KEY_LOCATION_RIGHT)
	check(app.skill_menu.mode == "closed" and state() == before,"right Alt cancels skill target without spending MP or an action")
	await key(KEY_F); await key(KEY_ENTER); await key(KEY_ENTER)
	check(app.session.state.extensions[Battle.KEY].step == before.extensions[Battle.KEY].step+1 and app.session.entity(app.session.state.active_party[0]).mp < before.entities[0].mp,"keyboard skill selection commits current actor MP and one action")
	await drain(); await restored(initial); before = state()
	for code in [KEY_R,KEY_A,KEY_W]:
		await key(code); check(state() == before and app.message.text.contains("尚未支持"),"unsupported rule is explicit and inert " + str(code))
	await key(KEY_D)
	check(app.session.state.extensions[Battle.KEY].step == before.extensions[Battle.KEY].step+1,"D commits one existing defense action")
	await drain(); await restored(initial)
	await key(KEY_S); await settle()
	check(app.status_picker.visible and app.session.modal and app.status_text.text.contains("攻击"),"S opens a read-only effective party status window")
	before = state(); await key(KEY_D); check(state() == before,"status dialog does not leak combat shortcuts")
	await RenderingServer.frame_post_draw; app.status_picker.get_texture().get_image().save_png(output.path_join("status.png"))
	app.status_picker.hide(); await settle(); app.session.set_focus(true,app.session._last_usec)
	await settings_checks()
	check(app.session.state.content_lock == lock,"input preferences never alter content identity")
	# Restored state rebinds command focus, not old target Button references.
	app.key_bindings.apply(Keys.preset("classic")); await restored(initial)
	await key(KEY_ENTER); await key(KEY_RIGHT); await key(KEY_F9); await settle()
	check(app.save_picker.visible and app.session.modal,"F9 opens immutable save generations from target selection")
	var epoch: int = app.session.state.timeline_epoch
	await click(app.save_list.get_child(0)); app.session.set_focus(true,app.session._last_usec); await settle()
	check(not app.save_picker.visible and app.session.state.timeline_epoch == epoch+1 and app.input_router.movement.is_empty(),"mouse load resets epoch and held movement through existing save UI")
	await restored(initial)
	var encounter: Dictionary = Battle.encounter(app.session.package.world,app.session.state.extensions[Battle.KEY].encounter_id)
	encounter.allow_escape = false; before = state(); await key(KEY_Q)
	check(state() == before and not app.session.error.is_empty(),"escape shortcut respects existing denied-escape rule (in-memory fixture)")
	encounter.allow_escape = true; await key(KEY_Q); await drain()
	check(not app.session.battle_open(),"Q uses existing allowed escape callback")
	await save("escape")
	await key(KEY_ENTER)
	check(not app.session.dialogue_open,"confirm leaves escape dialogue for map")
	await movement_checks()
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(output.path_join("map-input.png"))
	await paged_checks()
	var saved_profile: String = app.input_profile_path
	app.queue_free(); await settle()
	app = App.instantiate(); app.input_profile_path = saved_profile; root.add_child(app); await settle()
	check(app.key_bindings.bindings[0x1c] == 0 and app.key_bindings.bindings[0x2c] == 2,"fresh application startup reloads user-confirmed import independent of temporary presets")
	app.queue_free(); await settle()
	app = App.instantiate(); app.input_profile_path = output.path_join("broken.json"); root.add_child(app); await settle()
	check(app.open_package(spec.package) and app.message.text.contains("传统默认键"),"bad local profile notice survives opening a valid package")
	app.input_settings.open(); await settle()
	check(app.input_settings.notice.text.contains("无法读取"),"configuration recovery notice remains available in settings")
	app.queue_free(); await settle(); finish()

func paged_checks() -> void:
	app.key_bindings.apply(Keys.preset("classic")); app.input_router.clear()
	check(app.open_package(spec.paged_package),"retained authored nine-enemy package loads for paging")
	app.session.set_focus(true,app.session._last_usec); await settle()
	option("继续").grab_focus(); await key(KEY_ENTER)
	check(app.session.battle_open() and app.battle_view.page_count() == 2,"generic layout retains two target pages")
	var before: Dictionary = state(); await key(KEY_PAGEDOWN)
	check(app.battle_view.enemy_page == 1 and state() == before,"PageDown changes target page without authority mutation")
	await key(KEY_KP_9)
	check(app.battle_view.enemy_page == 0 and state() == before,"keypad PageUp alias returns to first target page")

func parser_checks() -> void:
	var model = Keys.new(); var parsed: Dictionary = Keys.import_file(spec.key_ini)
	for path in ["//not-a-host.invalid/share/key.ini","\\\\not-a-host.invalid\\share\\key.ini","https://not-a-host.invalid/key.ini","file://not-a-host.invalid/share/input.json"]:
		check(Keys.import_file(path).get("error","").contains("本地") and not model.load_profile(path) and not model.save_profile(path,Keys.preset("classic")),"strict-offline config paths rejected before I/O " + path)
	check(not parsed.has("error") and model.apply(parsed.profile),"actual PALDLL key.ini parses without any Config side effect")
	check(model.bindings[0x21] == 16 and model.bindings[0x9c] == 2,"real UTF-8 sample includes F magic and extended keypad confirm")
	check(not parsed.notices.is_empty(),"ignored Config section is disclosed")
	parsed = Keys.parse_ini("[Remap]\n0x23=0x03\n0x21=0x00\n0x23=0x0b\n".to_utf8_buffer()); model.apply(parsed.profile)
	check(model.bindings[0x23] == 3 and model.bindings[0x21] == 0 and model.bindings[0xc8] == 3,"sparse overlay keeps first duplicate, explicit disable and missing defaults")
	check(model.bindings.keys()[0] == 0x23 and model.bindings.keys()[1] == 0x21 and parsed.notices.size() == 1,"explicit ordering is retained with duplicate diagnostic")
	check(model.action(event(KEY_J,true,false,KEY_H)) == "up","physical QWERTY position wins over localized key label")
	for row in [[KEY_CTRL,KEY_LOCATION_LEFT,0x1d],[KEY_CTRL,KEY_LOCATION_RIGHT,0x9d],[KEY_ALT,KEY_LOCATION_RIGHT,0xb8],[KEY_SHIFT,KEY_LOCATION_RIGHT,0x36],[KEY_KP_8,0,0x48],[KEY_UP,0,0xc8],[KEY_KP_ENTER,0,0x9c]]:
		check(Keys.scan(event(row[0],true,false,0,row[1])) == row[2],"physical identity fixture " + str(row))
	for text in ["", "[Remap]\nH=0x03", "[Remap]\n0x23=0x03junk", "[Remap]\n0x00=0x03", "[Remap]\n0x23=0xff", "[Remap]\n0x100=0x03", "[Remap]\n0x23=0x03=0x04"]:
		check(Keys.parse_ini(text.to_utf8_buffer()).has("error"),"reject malformed import without partial application " + text.replace("\n"," / "))
	check(Keys.parse_ini(PackedByteArray([255,254,91,0,82,0])).has("error"),"UTF-16 is explicitly rejected")
	var large = PackedByteArray(); large.resize(Keys.LIMIT+1)
	check(Keys.parse_ini(large).has("error"),"import byte budget enforced")
	check(Keys.parse_ini("\uFEFF[Remap]\n0x21=0x10\u00a0 ;中文注释\n".to_utf8_buffer()).profile.remap == [[0x21,16]],"UTF-8 BOM and nonbreaking-space sample accepted")
	var gbk: PackedByteArray = "[Remap]\n0x21=0x10 ;".to_ascii_buffer(); gbk.append_array(PackedByteArray([0xd6,0xd0,0xce,0xc4]))
	check(Keys.parse_ini(gbk).profile.remap == [[0x21,16]],"GBK comment bytes need no Python or code-page runtime")
	check(Keys.parse_ini("[Remap]\n;empty".to_ascii_buffer()).profile.remap.is_empty(),"empty remap resolves defaults")
	var old: Dictionary = model.profile.duplicate(true)
	check(not model.apply({"version":1,"preset":"key_ini","remap":[[35,3.5]]}) and model.profile == old,"invalid local profile cannot replace current bindings")
	var path: String = output.path_join("profile-check.json")
	check(model.save_profile(path,Keys.preset("wasd")),"preferences first save succeeds")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(model.save_profile(path,Keys.preset("classic")),"second preference save replaces after backup")
	var backups = Array(DirAccess.get_files_at(output)).filter(func(name): return name.begins_with("profile-check.json.backup-"))
	check(backups.size() == 1 and FileAccess.get_file_as_bytes(output.path_join(backups[0])) == bytes,"prior local preference bytes preserved in unique backup")
	var fresh = Keys.new(); check(fresh.load_profile(path) and fresh.profile == Keys.preset("classic"),"fresh model reloads persisted preference")
	FileAccess.open(output.path_join("broken.json"),FileAccess.WRITE).store_string("{broken")
	check(not fresh.load_profile(output.path_join("broken.json")) and fresh.profile == Keys.preset("classic"),"malformed existing file is left untouched and default remains")
	check(not fresh.save_profile(output,Keys.preset("wasd")) and fresh.profile == Keys.preset("classic"),"failed filesystem publication leaves live bindings intact")

func settings_checks() -> void:
	var old: Dictionary = app.key_bindings.profile.duplicate(true)
	app.input_settings.open(); await settle()
	app.input_settings.import_path(spec.remap)
	check(app.key_bindings.profile == old and app.input_settings.draft.remap.size() == 4,"import is review-only until Apply")
	app.input_settings.import_path(spec.bad_remap)
	check(app.input_settings.get_ok_button().disabled and app.key_bindings.profile == old,"bad second selection disables stale draft application")
	app.input_settings.import_path(spec.remap)
	await RenderingServer.frame_post_draw; app.input_settings.get_texture().get_image().save_png(output.path_join("key-import.png"))
	await click(app.input_settings.get_cancel_button())
	check(not app.input_settings.visible and app.key_bindings.profile == old and not FileAccess.file_exists(app.input_profile_path),"mouse Cancel leaves preferences and gameplay unchanged")
	app.input_settings.open(); await settle(); app.input_settings.import_path(spec.remap)
	await click(app.input_settings.get_ok_button()); app.session.set_focus(true,app.session._last_usec)
	check(not app.input_settings.visible and app.key_bindings.bindings[0x23] == 3 and app.key_bindings.bindings[0x21] == 0,"mouse Apply activates reviewed imported bindings")
	var fresh = Keys.new(); check(fresh.load_profile(app.input_profile_path) and fresh.bindings == app.key_bindings.bindings,"actual UI output reloads with same effective bindings")
	var before: Dictionary = state(); option("攻击").grab_focus(); await key(KEY_ENTER)
	check(state() == before and not app.classic_attack,"explicit disabled Enter cannot fall through to GUI accept")
	await key(KEY_Z); check(app.classic_attack,"remapped Z confirmation reaches existing attack stage")
	await key(KEY_ESCAPE); before = state(); await key(KEY_F)
	check(app.skill_menu.mode == "closed" and state() == before,"explicit disabled F does not retain default magic action")

func movement_checks() -> void:
	app.key_bindings.apply(Keys.parse_ini("[Remap]\n0x23=0x03\n0x24=0x03".to_ascii_buffer()).profile)
	root.push_input(event(KEY_H),true); root.push_input(event(KEY_J),true); await settle()
	check(app.walk_input.sample("pal.walk.v1") == Vector2i.UP,"two imported aliases feed named movement policy")
	root.push_input(event(KEY_H,false),true); await settle()
	check(app.walk_input.sample("pal.walk.v1") == Vector2i.UP,"one alias release preserves other held alias")
	root.push_input(event(KEY_J,false),true); await settle()
	check(app.walk_input.sample("pal.walk.v1") == Vector2i.ZERO,"last alias release stops movement")
	root.push_input(event(KEY_H),true); await settle(); app._pause(); app._pause()
	root.push_input(event(KEY_J),true); root.push_input(event(KEY_J,false),true); await settle()
	check(app.walk_input.sample("pal.walk.v1") == Vector2i.ZERO,"pre-pause alias cannot keep post-pause movement stuck")
	root.push_input(event(KEY_H,false),true); root.push_input(event(KEY_H),true); await settle()
	root.focus_exited.emit(); root.focus_entered.emit(); await settle()
	root.push_input(event(KEY_H,true,true),true); await settle()
	check(app.walk_input.sample("pal.walk.v1") == Vector2i.ZERO,"focus signal clears movement and ignores held-key repeat on return")
	root.push_input(event(KEY_H,false),true); root.push_input(event(KEY_H),true); await settle()
	app.input_settings.open(); await settle(); root.push_input(event(KEY_H,false),true); app.input_settings.hide(); await settle()
	check(app.walk_input.sample("pal.walk.v1") == Vector2i.ZERO,"modal release cannot leak into resumed map movement")
	app.key_bindings.apply(Keys.preset("wasd")); app.input_router.clear()
	root.push_input(event(KEY_S),true); await settle()
	check(app.walk_input.sample("pal.walk.v1") == Vector2i.DOWN and not app.status_picker.visible,"explicit WASD preset resolves S conflict as movement")
	root.push_input(event(KEY_S,false),true); await settle()
