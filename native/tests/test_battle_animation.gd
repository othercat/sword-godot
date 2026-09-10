# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Battle = preload("res://src/native_battle.gd")
const Presentation = preload("res://src/native_battle_presentation.gd")
const Frames = preload("res://src/native_map_animation.gd")
const Save = preload("res://src/native_save.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4: quit(2); return
	output = args[3]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280,800)
	for path in args.slice(0,3):
		var app = App.instantiate(); root.add_child(app); await process_frame
		app.saves = Save.new(output.path_join("saves"))
		if not app.open_package(path): check(false, "authored action package loads: " + app.session.error); _finish(); return
		app.set_physics_process(false); app.battle_view.set_process(false)
		await process_frame; await click(option(app,"继续"))
		var session = app.session; var view = app.battle_view; var party: Array = session.state.active_party.duplicate(); var size: int = party.size()
		check(session.battle_open() and session.package.index.battle_sprite_sets.size() == 3, "actual authored side-facing sets load " + str(size))
		await RenderingServer.frame_post_draw
		check(view.displayed_frames.size() == size + 3, "every party/enemy instance has independent authored body " + str(size))
		check(range(1,size).all(func(i):return view.displayed_frames[party[i]].anchor.x>view.displayed_frames[party[i-1]].anchor.x and view.displayed_frames[party[i]].anchor.y<view.displayed_frames[party[i-1]].anchor.y),"3/4/5 party seats form a rising diagonal independent of definition IDs")
		root.get_texture().get_image().save_png(output.path_join("battle-"+str(size)+".png"))
		check(app.saves.save(session), "actual pre-command save")
		var baseline: String = app.saves.last_path; record(app,path,"before",size)
		var before: Dictionary = session.state.duplicate(true)
		await click(option(app,"攻击 1"))
		check(view.playing() and option(app,"跳过演出") != null, "committed attack enters skippable playback")
		var committed: Dictionary = session.state.duplicate(true)
		check(committed.extensions[Battle.KEY].enemies[0].hp == 162, "one authoritative attack applied before display")
		check(view.presentation.current().action == "attack" and view.presentation.actors[committed.extensions[Battle.KEY].enemies[0].instance_id].hp == 180, "damage display waits for hit phase")
		app._battle_action("attack",committed.extensions[Battle.KEY].enemies[0].instance_id)
		check(session.state == committed, "stale attack cannot submit through UI during playback")
		for field in ["paused","modal","focused"]:
			session.set(field, field != "focused"); var elapsed: float = view.presentation.elapsed_us
			view._process(1.0); check(view.presentation.elapsed_us == elapsed and session.state == committed, "freeze presentation on " + field)
			session.set(field, field == "focused")
		view._process(0.05)
		check(view.presentation.current().action == "hit" and view.presentation.actors[committed.extensions[Battle.KEY].enemies[0].instance_id].hp == 162, "hit projects exact committed amount after source action")
		check(app.saves.save(session), "saving during hit uses authoritative post-command state"); record(app,path,"during-hit",size)
		var during: String = app.saves.last_path
		check(app.saves.load_into(session,during) and not view.playing(), "load clears display history without repeating command")
		check(session.state.extensions[Battle.KEY] == committed.extensions[Battle.KEY], "loading during display preserves committed battle exactly")
		check(app.saves.load_into(session,baseline), "baseline restores for refresh sampling")
		check(session.battle_command("attack",session.state.extensions[Battle.KEY].enemies[0].instance_id), "fresh command for 60/100 sampling")
		var result: Dictionary = session.state.extensions[Battle.KEY].duplicate(true)
		var sequences: Array = []
		for hz in [60,100,144,240]:
			var p = Presentation.new(); p.begin(session.package,session_state_like(before,session.state),result,"")
			for step in range(hz): p.advance(1.0/hz,true)
			check(not p.active and p.consumed == [0], "ordered projection completes once at " + str(hz))
			sequences.append(p.actors.duplicate(true))
		check(sequences.all(func(s): return s == sequences[0]), "60/100/144/240 projections end identically")
		view.skip()
		# Real skill and item menus retain their old selection during the display;
		# the first Escape must pause, not silently consume that stale menu.
		await click(option(app,"技能")); await click(option(app,"群攻术")); await click(option(app,"施放于全部"))
		check(view.playing(), "actual all-target skill starts cast/effect sequence")
		key(app,KEY_ESCAPE); check(session.paused, "first Escape pauses skill playback"); key(app,KEY_ESCAPE)
		var settled: Dictionary = session.state.duplicate(true); view._process(10.0)
		check(not view.playing() and session.state == settled, "complete multi-target result does not cast again")
		await click(option(app,"物品")); await click(option(app,"调息散")); await click(option(app,"用于全部"))
		check(view.playing(), "actual all-target item starts item/effect sequence")
		key(app,KEY_ESCAPE); check(session.paused, "first Escape pauses item playback"); key(app,KEY_ESCAPE)
		settled=session.state.duplicate(true); await click(option(app,"跳过演出")); check(clock_only(settled,session.state),"skip cannot consume items twice")
		# Run legitimate authored group attacks to a win; no HP/clear-enemy shortcut.
		for step in range(80):
			if not session.battle_open(): break
			if view.playing(): view.skip()
			var b: Dictionary = session.state.extensions[Battle.KEY]
			if not session.battle_command("skill","",session.package.world.skill_definitions[4].id):
				check(session.battle_command("attack",b.enemies.filter(func(e): return e.hp>0)[0].instance_id), "fallback legitimate attack")
		check(not session.battle_open() and view.playing() and view.visible and not app.world_view.visible, "final blow remains visible after authoritative win callback")
		var cursor: Dictionary = session.state.cursor.duplicate(true); var effects: Array = session.state.committed_effect_ids.duplicate()
		key(app,KEY_ENTER); key(app,KEY_SPACE); key(app,KEY_RIGHT); app._physics_process(1.0/60)
		check(session.state.cursor==cursor and session.state.committed_effect_ids==effects, "ending playback blocks hidden dialogue input")
		check(app.saves.save(session), "save during victory published"); record(app,path,"win",size)
		var winning: String = app.saves.last_path; view._process(120.0)
		check(not view.playing() and session.state.cursor==cursor and session.state.committed_effect_ids==effects, "completion reveals already-committed callback exactly once")
		check(app.saves.load_into(session,winning) and not view.playing(), "victory load does not replay or reaward")
		check(app.saves.load_into(session,baseline), "escape baseline restores")
		await click(option(app,"撤离")); check(view.playing() and not session.battle_open(), "escape action has a completion sequence")
		check(app.saves.save(session), "escape save published"); record(app,path,"escape",size)
		# Explicit synthetic callback shape: no story wait after battle, to exercise hidden map input.
		var end_node: Dictionary = session.current_node(); var original_op: String = end_node.op
		end_node.op="end"; session.dialogue_open=false
		var positions: Array = session.state.entities.map(func(e): return e.position.duplicate())
		var held = InputEventKey.new(); held.keycode=KEY_RIGHT; held.pressed=true
		app._unhandled_key_input(held)
		check(app.walk_input.sample("pal.walk.v1")==Vector2i.ZERO,"playback key handler refuses new held direction")
		app.walk_input.key_event(KEY_RIGHT,true) # A key held before playback began.
		app._physics_process(0.25)
		check(app.walk_input.sample("pal.walk.v1")==Vector2i.ZERO,"playback physics actively clears a pre-existing held direction")
		var released=InputEventKey.new(); released.keycode=KEY_RIGHT; released.pressed=false; app._input(released)
		key(app,KEY_ENTER)
		check(session.state.entities.map(func(e): return e.position)==positions,"ending playback blocks hidden map movement and interaction")
		end_node.op=original_op; session.dialogue_open=true
		await death_and_revival(app,path,baseline,size)
		check(app.open_package(path) and not view.playing() and view.presentation.package==null, "new package activation releases old playback and package reference")
		root.remove_child(app); app.queue_free(); await process_frame
	_finish()

func death_and_revival(app,path:String,baseline:String,size:int)->void:
	var session=app.session; var view=app.battle_view; var hero: String=session.state.active_party[0]
	check(app.saves.load_into(session,baseline),"death branch restores immutable authored baseline")
	# Legitimate guard rounds: no altered HP, enemy stats or content lock.
	for step in range(600):
		if session.entity(hero).hp==0 or not session.battle_open(): break
		if view.playing(): view.skip()
		if not session.battle_command("guard",""): check(false,"guard branch: "+session.error); return
	check(session.battle_open() and session.entity(hero).hp==0,"authored retaliation kills hero while allies remain")
	if not session.battle_open(): return
	var death_seen: bool=false
	while view.playing():
		await RenderingServer.frame_post_draw
		if view.displayed_frames.get(hero,{}).get("action")=="dead": death_seen=true
		var phase: Dictionary=view.presentation.current()
		view._process((phase.duration_us-view.presentation.elapsed_us+1)/1000000.0)
	check(death_seen,"actual hero dead frame is drawn after lethal hit")
	check(app.saves.save(session),"death command save"); record(app,path,"death",size)
	await click(option(app,"技能")); await click(option(app,"复苏术")); await click(option(app,"1 ·"))
	check(view.playing() and session.entity(hero).hp==20 and view.presentation.actors[hero].hp==0,"revival authority commits while display still shows dead target")
	view._process(.05); await RenderingServer.frame_post_draw
	check(view.presentation.actors[hero].hp==12 and view.displayed_frames[hero].action=="dying","revive event projects its own amount and HP-derived pose")
	check(app.saves.save(session),"revival during display save"); record(app,path,"revive",size)
	view._process(10.0); await RenderingServer.frame_post_draw
	check(view.displayed_frames[hero].action=="idle" and session.entity(hero).hp==20,"healing completion restores living base pose without replay")
	# Diagnostic event list for death-related metadata; does not write Session.
	var before: Dictionary=session.state.duplicate(true); var result: Dictionary=before.extensions[Battle.KEY].duplicate(true)
	var enemy: String=result.enemies[0].instance_id
	result.events=[{"kind":"attack","source":enemy,"target":hero,"amount":20},
		{"kind":"status_clear","source":hero,"target":hero,"amount":0,"status_id":session.package.world.status_definitions[0].id,"reason":"death"}]
	view.present_committed(before,result,""); app._refresh()
	while view.playing():
		await RenderingServer.frame_post_draw
		var phase: Dictionary=view.presentation.current()
		if phase.event.get("kind")=="status_clear": check(view.displayed_frames[hero].action=="dead","death metadata cannot draw an idle corpse")
		view._process((phase.duration_us-view.presentation.elapsed_us+1)/1000000.0)
	check(clock_only(before,session.state),"synthetic metadata projection leaves game authority untouched")
	check(app.saves.load_into(session,baseline),"loss branch restores original authored state")
	for step in range(2000):
		if not session.battle_open(): break
		if view.playing(): view.skip()
		if not session.battle_command("guard",""): check(false,"loss guard branch: "+session.error); return
	check(not session.battle_open() and view.playing() and view.visible and view.presentation.outcome=="loss","natural all-dead result retains final presentation after loss callback")
	var cursor: Dictionary=session.state.cursor.duplicate(true); var credits: Array=session.state.committed_effect_ids.duplicate()
	death_seen=false
	while view.playing():
		await RenderingServer.frame_post_draw
		var phase: Dictionary=view.presentation.current()
		if phase.action=="dead": death_seen=view.displayed_frames[phase.actor_id].action=="dead"
		view._process((phase.duration_us-view.presentation.elapsed_us+1)/1000000.0)
	check(death_seen and session.state.cursor==cursor and session.state.committed_effect_ids==credits,"last fallen actor draws dead before loss callback is revealed once")
	check(app.saves.save(session),"actual loss save"); record(app,path,"loss",size)
	check(app.saves.load_into(session,app.saves.last_path) and not view.playing() and session.state.committed_effect_ids==credits,"loss load does not replay callback")
	# Keep an old package reference active so the following open-package check is meaningful.
	check(app.saves.load_into(session,baseline),"switch-package baseline")
	check(session.battle_command("attack",session.state.extensions[Battle.KEY].enemies[0].instance_id) and view.playing(),"old package presentation is active before switch")

func session_state_like(before: Dictionary, current: Dictionary) -> Dictionary:
	var value=before.duplicate(true); value.session_id=current.session_id; value.timeline_epoch=current.timeline_epoch; return value
func clock_only(before: Dictionary, after: Dictionary) -> bool:
	var expected=before.duplicate(true); expected.state_revision+=after.clock.logic_tick-before.clock.logic_tick; expected.clock=after.clock.duplicate(true)
	if expected!=after: print(JSON.stringify({"debug":"authority difference","keys":after.keys().filter(func(k):return expected.get(k)!=after[k])}))
	return expected==after
func record(app,path:String,stage:String,size:int)->void:
	saves.append({"party":size,"package_path":path,"save_path":app.saves.last_path,"stage":stage})
func key(app,code:int)->void:
	var e=InputEventKey.new(); e.keycode=code; e.pressed=true; app._unhandled_key_input(e)
	var release=InputEventKey.new(); release.keycode=code; release.pressed=false; app._input(release)
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
	var report={"checks":checks,"failed":failed,"saves":saves,"engine_injected_input":true,"physical_input":false,"synthetic_callback_and_display_sampling":true,"real_assets":false,"full_playthrough":false}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if failed==0 else 1)
