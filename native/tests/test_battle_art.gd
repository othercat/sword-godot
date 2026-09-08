# SPDX-License-Identifier: MIT
extends SceneTree
const App=preload("res://scenes/main.tscn")
const Battle=preload("res://src/native_battle.gd")
var checks: Array=[]
var failed: int=0
var output: String
func check(ok:bool,label:String)->void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed+=1; push_error(label)
func _initialize()->void: _run.call_deferred()
func _run()->void:
	var args=OS.get_cmdline_user_args()
	if args.size()!=4: quit(2); return
	output=args[3]; DirAccess.make_dir_recursive_absolute(output); root.size=Vector2i(1280,800)
	for path in args.slice(0,3):
		var app=App.instantiate(); root.add_child(app); await process_frame
		if not app.open_package(path): check(false,app.session.error); _finish(); return
		app.set_physics_process(false); app.battle_view.set_process(false)
		await process_frame; await click(option(app,"继续"))
		var session=app.session; var view=app.battle_view; var hero: String=session.state.active_party[0]; var size: int=session.state.active_party.size()
		var actor: Dictionary=session.package.index.actor_definitions[session.entity(hero).definition_id]
		var sprite: Dictionary=session.package.index.battle_sprite_sets[actor.battle_sprite_set]
		check(sprite.clips.size()==11 and sprite.clips.reduce(func(n,c):return n+c.frames.size(),0)==16,"eleven generated action clips retain sixteen distinct poses "+str(size))
		await RenderingServer.frame_post_draw
		var body: Dictionary=view.displayed_frames[hero]
		var img: Image=session.package.textures[body.asset_id].get_image()
		check(img.detect_alpha()!=Image.ALPHA_NONE and img.get_width()>180,"real generated RGBA body is loaded outside palette limit")
		root.get_texture().get_image().save_png(output.path_join("battle-"+str(size)+".png"))
		var before: Dictionary=session.state.duplicate(true)
		await click(option(app,"攻击 1"))
		check(view.playing() and session.state.extensions[Battle.KEY].enemies[0].hp==162,"real art attack uses committed battle result")
		var seen: Dictionary={}
		for step in range(3):
			await RenderingServer.frame_post_draw
			body=view.displayed_frames[hero]; seen[body.frame_id]=true
			check(body.action=="attack" and body.rect.position.x>=0 and body.rect.position.y>=0,"authored attack frame and anchor stay inside battle viewport")
			if step==1: root.get_texture().get_image().save_png(output.path_join("attack-"+str(size)+".png"))
			view._process(.12)
		check(seen.size()==3,"anticipation contact recovery are three distinct image frames")
		view.skip()
		# Exercise each authored pose through the actual renderer; these explicit
		# diagnostic phase selections are visual checks, not legal skill actions.
		for clip in sprite.clips:
			view.present_committed(before,session.state.extensions[Battle.KEY],"")
			view.presentation.phases=[{"actor_id":hero,"action":clip.action,"event":{},"event_index":-1,"duration_us":1000000}]
			view.presentation.phase_index=0; view.presentation.elapsed_us=0; view.presentation.active=true; app._refresh()
			await RenderingServer.frame_post_draw
			check(view.displayed_frames[hero].asset_id==clip.frames[0].asset_id,"renderer consumes generated "+clip.action+" frame")
		view.skip(); root.remove_child(app); app.queue_free(); await process_frame
	_finish()
func option(app,prefix:String)->Button:
	for child in app.options.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	check(false,"missing command "+prefix); return null
func click(control:Control)->void:
	if control==null:return
	await process_frame
	var p=control.get_global_rect().get_center()
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
	await process_frame; await process_frame
func _finish()->void:
	var report={"checks":checks,"failed":failed,"generated_art":true,"synthetic_partners":true,"diagnostic_all_action_rendering":true,"physical_input":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")); print(JSON.stringify(report)); quit(0 if failed==0 else 1)
