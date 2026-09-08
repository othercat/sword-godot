# SPDX-License-Identifier: MIT
extends SceneTree
const App=preload("res://scenes/main.tscn")
const Battle=preload("res://src/native_battle.gd")
const Save=preload("res://src/native_save.gd")
var checks: Array=[]
var failed: int=0
var output: String
var saves: Array=[]
var companions: bool=false
var real_background: bool=false
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
		app.saves=Save.new(output.path_join("saves"))
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
		var third: Dictionary=session.entity(session.state.active_party[2])
		companions=third.definition_id!=session.entity(session.state.active_party[1]).definition_id
		if companions:
			check(third.instance_id.begins_with("instance.author.") and third.definition_id.begins_with("actor.author."),"runtime uses actual author-created character identities")
			var ids: Dictionary={}
			for member in session.state.active_party:
				var shown: Dictionary=view.displayed_frames[member]; ids[shown.asset_id]=true
				check(session.package.textures[shown.asset_id].get_image().detect_alpha()!=Image.ALPHA_NONE,"every companion body retains actual transparent PNG "+member)
			check(ids.size()==3,"three generated body designs populate independent party instances")
		real_background=not view.background_asset.is_empty()
		if real_background:
			check("graphics.battle-scene.v1" in session.package.manifest.required_capabilities,"background has explicit loader capability")
			var texture: Texture2D=session.package.textures[view.background_asset]
			check(texture.get_width()==320 and texture.get_height()==200,"original FBP PNG is loaded without source-game importer")
			var bounds: Vector2=view.get_viewport_rect().size
			check(view.background_rect.encloses(Rect2(Vector2.ZERO,bounds)),"cover fills battle viewport without letterbox gaps")
			check(is_equal_approx(view.background_rect.size.x/view.background_rect.size.y,1.6),"cover keeps original aspect instead of stretching")
			var with_background=view.get_viewport().get_texture().get_image().get_pixel(5,5)
			var encounter: Dictionary=Battle.encounter(session.package.world,session.state.extensions[Battle.KEY].encounter_id)
			var background_id: String=encounter.background_asset
			encounter.background_asset=null; view.queue_redraw(); await RenderingServer.frame_post_draw
			check(view.get_viewport().get_texture().get_image().get_pixel(5,5)!=with_background,"GPU battle surface changes when PNG is disabled")
			encounter.background_asset=background_id; view.queue_redraw(); await RenderingServer.frame_post_draw
			check(app.saves.save(session),"background encounter can save authoritative state")
			saves.append({"save_path":app.saves.last_path,"package_path":path,"party":size})
			check(app.saves.load_into(session,app.saves.last_path),"background encounter save reloads")
			await RenderingServer.frame_post_draw
			check(view.background_asset==background_id and session.battle_open(),"background restored through encounter identity without saving rendering state")
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
		if companions:
			for member in session.state.active_party.slice(1,3):
				await click(option(app,"攻击 1")); await RenderingServer.frame_post_draw
				check(view.displayed_frames[member].action=="attack","actual companion command starts its own action clip")
				view.skip()
		# Exercise each authored pose through the actual renderer; these explicit
		# diagnostic phase selections are visual checks, not legal skill actions.
		for member in (session.state.active_party.slice(0,3) if companions else [hero]):
			var definition: Dictionary=session.package.index.actor_definitions[session.entity(member).definition_id]
			for clip in session.package.index.battle_sprite_sets[definition.battle_sprite_set].clips:
				view.present_committed(before,session.state.extensions[Battle.KEY],"")
				view.presentation.phases=[{"actor_id":member,"action":clip.action,"event":{},"event_index":-1,"duration_us":1000000}]
				view.presentation.phase_index=0; view.presentation.elapsed_us=0; view.presentation.active=true; app._refresh()
				await RenderingServer.frame_post_draw
				check(view.displayed_frames[member].asset_id==clip.frames[0].asset_id,"renderer consumes generated "+member+" "+clip.action+" frame")
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
	var report={"checks":checks,"failed":failed,"generated_art":true,"synthetic_partners":not companions,"real_background":real_background,"saves":saves,"diagnostic_all_action_rendering":true,"physical_input":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t")); print(JSON.stringify(report)); quit(0 if failed==0 else 1)
