# SPDX-License-Identifier: MIT
extends SceneTree
## Real window/input projection checks; retained author packages, no original writes.
const App = preload("res://scenes/main.tscn")
const Battle = preload("res://src/native_battle.gd")
const Save = preload("res://src/native_save.gd")
var checks: Array = []
var windows: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 5: quit(2); return
	output = args[4]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800)
	var app = await open_battle(args[0])
	if app == null: finish(); return
	var session = app.session; var view = app.battle_view
	var ids: Array = session.state.extensions[Battle.KEY].enemies.map(func(e): return e.instance_id)
	var first = option(app,"攻击 1"); first.grab_focus(); await settle()
	var before: Dictionary = session.state.duplicate(true)
	var pixels_a: PackedByteArray = app.viewport.get_texture().get_image().get_data()
	await hover(first)
	await key(KEY_TAB)
	check(app.get_viewport().gui_get_focus_owner() == option(app,"攻击 2") and view.target_ids == [ids[1]],"stationary mouse on A then real GUI Tab highlights focused B")
	var pixels_b: PackedByteArray = app.viewport.get_texture().get_image().get_data()
	check(pixels_a != pixels_b and session.state == before,"GPU target overlay changes without advancing HP MP inventory or state")
	await key(KEY_ENTER)
	var battle: Dictionary = session.state.extensions[Battle.KEY]
	check(battle.enemies[0].hp == 36 and battle.enemies[1].hp == 18 and view.playing() and view.target_ids.is_empty(),"GUI Enter attacks highlighted instance B once and clears preview for playback")
	view.skip(); await settle()
	await hover(option(app,"攻击 1")); option(app,"防御").grab_focus(); await settle()
	check(view.target_ids.is_empty(),"keyboard focus on non-target command clears stationary mouse target")
	await hover(option(app,"攻击 3")); check(view.target_ids == [ids[2]],"new mouse motion takes target ownership after keyboard input")
	await hover(option(app,"防御")); check(view.target_ids.is_empty(),"hovering a non-target command clears preview")
	await click(app.target_pages.get_child(2)); option(app,"攻击 9").grab_focus(); await settle()
	check(view.enemy_page == 1 and view.target_ids == [ids[8]],"page two uses stable ninth instance identity")
	var projection: Transform2D = view.projection
	await click(app.target_pages.get_child(0)); await settle()
	check(view.projection.is_equal_approx(projection) and ids[8] not in view.target_ids,"paging preserves fitted camera and drops off-page target")
	option(app,"攻击 4").grab_focus(); await settle(); app._refresh(); await settle()
	check(view.target_ids == [ids[3]] and app.get_viewport().gui_get_focus_owner() == option(app,"攻击 4"),"refresh restores target focus by identity after rebuilding controls")
	for mode in ["pause","modal","focus"]:
		if mode == "pause": session.set_pause(true)
		elif mode == "modal": session.set_modal(true)
		else: session.set_focus(false)
		await settle(); check(view.target_ids.is_empty(),mode+" clears target preview")
		if mode == "pause": session.set_pause(false)
		elif mode == "modal": session.set_modal(false)
		else: session.set_focus(true)
		await settle()
	await window_cases(app,"enemy-nine")
	# Explicit in-memory large-art stress: same private PNGs, authored records restored.
	var definition: Dictionary = session.package.index.actor_definitions[battle.enemies[0].definition_id]
	var sprite: Dictionary = session.package.index.battle_sprite_sets[definition.battle_sprite_set]
	var originals: Array = []
	for clip in sprite.clips:
		for frame in clip.frames: originals.append([frame,frame.scale_milli]); frame.scale_milli = 8000
	view.invalidate_layout(); await window_cases(app,"synthetic-eightfold-enemies")
	for pair in originals: pair[0].scale_milli = pair[1]
	view.invalidate_layout(); await settle()
	# Package swap to a non-battle scene must release the previous texture owner now.
	var old_package = weakref(session.package)
	check(app.open_package(args[1]),"next package opens before entering battle")
	await settle()
	check(not session.battle_open() and view._extent_package == session.package and view._frame_extents.is_empty(),"non-battle package swap clears old frame extents immediately")
	check(old_package.get_ref() == null,"previous package is released on non-battle package swap")
	await dispose(app)
	for kind in ["skill","item"]:
		app = await open_battle(args[1] if kind == "skill" else args[2])
		if app == null: finish(); return
		await targets(app,kind); await dispose(app)
	app = await open_battle(args[3])
	if app == null: finish(); return
	await window_cases(app,"generated-five-party")
	var anchors: Array = app.session.state.active_party.map(func(id): return app.battle_view.displayed_bodies[id].anchor)
	var diagonal: bool = true
	for i in range(1,anchors.size()): diagonal = diagonal and anchors[i].x > anchors[i-1].x and anchors[i].y < anchors[i-1].y
	check(anchors.size() == 5 and diagonal,"five authored party bodies retain their rising diagonal after fit")
	await dispose(app); finish()
func targets(app, kind: String) -> void:
	var session = app.session; var view = app.battle_view
	var menu: String = "技能" if kind == "skill" else "物品"
	var catalog: Array = session.package.world.skill_definitions if kind == "skill" else session.package.world.item_definitions
	var party: Array = session.state.active_party.duplicate()
	var enemies: Array = session.state.extensions[Battle.KEY].enemies.map(func(e): return e.instance_id)
	var before: Dictionary = session.state.duplicate(true)
	await click(option(app,menu)); await click(option(app,catalog[0].display_name+" ·"))
	option(app,"3 ·").grab_focus(); await settle()
	check(view.target_ids == [enemies[2]] and session.state == before,kind+" single target uses exact instance without consuming resources")
	await click(option(app,"取消")); await click(option(app,menu)); await click(option(app,catalog[1].display_name+" ·"))
	var all_button = option(app,"施放于全部" if kind == "skill" else "用于全部")
	all_button.grab_focus(); await settle()
	check(view.target_ids == enemies and session.state == before,kind+" all-target preview includes the whole eligible set")
	await key(KEY_ENTER)
	check(session.state.extensions[Battle.KEY].enemies.map(func(e): return e.hp) == [85,85,85],kind+" GUI confirmation applies all-target result")
	# Static mode keeps nonblocking feedback through the same projection.
	view._elapsed = .175; view.queue_redraw(); await settle()
	var active_pixels: PackedByteArray = app.viewport.get_texture().get_image().get_data()
	before = session.state.duplicate(true); view._elapsed = 1.0; view.queue_redraw(); await settle()
	check(active_pixels != app.viewport.get_texture().get_image().get_data() and session.state == before and not view.playing(),kind+" static cast/damage feedback remains visible and nonblocking")
	for _i in range(party.size()):
		if session.state.extensions[Battle.KEY].round > 1: break
		await click(option(app,"防御"))
	check(session.entity(party[0]).hp == 0,"normal enemy response creates a dead ally for "+kind+" revive")
	await click(option(app,menu)); await click(option(app,catalog[3].display_name+" ·"))
	option(app,"1 ·").grab_focus(); await settle()
	check(view.target_ids == [party[0]] and not option(app,"1 ·").disabled and option(app,"2 ·").disabled,kind+" revival highlights dead ally and excludes living allies")
	await key(KEY_ENTER); check(session.entity(party[0]).hp > 0,kind+" keyboard confirmation revives the highlighted ally")
	view._elapsed = .175; view.queue_redraw(); await settle()
	active_pixels = app.viewport.get_texture().get_image().get_data()
	view._elapsed = 1.0; view.queue_redraw(); await settle()
	check(active_pixels != app.viewport.get_texture().get_image().get_data(),kind+" static healing feedback remains visible")
func window_cases(app, label: String) -> void:
	for size in [Vector2i(1024,768),Vector2i(1280,800),Vector2i(1920,1080),Vector2i(1720,720)]:
		root.size = size; await settle(); await settle()
		var view = app.battle_view; var bounds: Rect2 = app.viewport.get_visible_rect()
		var contained: bool = true; var separate: bool = true
		var bodies: Array = view.displayed_bodies.values()
		for i in range(bodies.size()):
			contained = contained and bounds.encloses(bodies[i].rect)
			for j in range(i+1,bodies.size()): separate = separate and not bodies[i].rect.intersects(bodies[j].rect)
		var controls_fit: bool = true
		for control in app.options.get_children(): controls_fit = controls_fit and root.get_visible_rect().encloses(control.get_global_rect())
		check(contained and separate and controls_fit,label+" body extents separate and all controls fit "+str(size))
		var ratios: bool = true
		for id in view.displayed_frames:
			var data: Dictionary = view.displayed_frames[id]
			var texture: Texture2D = app.session.package.textures[data.asset_id]
			ratios = ratios and is_equal_approx(data.rect.size.x/data.rect.size.y,texture.get_width()/float(texture.get_height()))
		check(ratios,label+" authored image proportions survive camera fit "+str(size))
		var screenshot = output.path_join(label+"-"+str(size.x)+"x"+str(size.y)+".png")
		var pixels: Image = root.get_texture().get_image(); pixels.save_png(screenshot)
		windows.append({"case":label,"requested_window":[size.x,size.y],"actual_window":[root.size.x,root.size.y],"gui_size":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],"captured_pixels":[pixels.get_width(),pixels.get_height()],"battle_viewport":[app.viewport.size.x,app.viewport.size.y],"projection_scale":view.projection.x.x,"spacing":view.layout_spacing,"screenshot":screenshot})
func open_battle(path: String):
	var app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false)
	app.saves = Save.new(output.path_join("saves"))
	if not app.open_package(path): check(false,"package opens "+path); await dispose(app); return null
	await settle(); await click(option(app,"继续"))
	app.battle_view.set_process(false); await settle()
	check(app.session.battle_open(),"retained author package enters battle")
	return app
func dispose(app) -> void:
	root.remove_child(app); app.queue_free(); await process_frame
func settle() -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
func option(app, prefix: String) -> Button:
	for child in app.options.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false,"missing option "+prefix); return null
func hover(control: Control) -> void:
	var event = InputEventMouseMotion.new(); event.position = control.get_global_rect().get_center(); event.global_position = event.position; event.relative = Vector2.ONE
	root.push_input(event,true); await settle()
func click(control: Control) -> void:
	if control == null: return
	await settle()
	for down in [true,false]:
		var event = InputEventMouseButton.new(); event.position = control.get_global_rect().get_center(); event.global_position = event.position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; root.push_input(event,true)
	await settle()
func key(code: Key) -> void:
	for down in [true,false]:
		var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down; root.push_input(event,true)
	await settle()
func finish() -> void:
	var report = {"checks":checks,"failed":failed,"windows":windows,"engine_injected_input":true,"physical_input":false,"full_playthrough":false,"synthetic_large_art_scale":8,"screenshots_private":true}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")); print(JSON.stringify(report)); quit(0 if failed == 0 else 1)
