# SPDX-License-Identifier: MIT
extends SceneTree
## GPU/window probe of the corrected coordinator's current caches and states.
## Explicit probe initialization, scripted nominal ticks/presses and named gaps
## remain visible; this script does not enable ordinary Session or physical input.
const Game = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Composition = preload("res://src/native_pal98_scene_composition.gd")
const DialogueHost = preload("res://src/native_pal98_dialogue_host.gd")
const Surface = preload("res://src/native_pal98_dialogue_surface.gd")
const FontOwner = preload("res://src/native_ui_font.gd")
const Schema = preload("res://src/native_schema.gd")
class Clock:
	func consume(units: int) -> Dictionary: return {"consumed":units}
class Runtime:
	func answer(request: Dictionary) -> Dictionary:
		return {"completed":true,"pumped":request.get("events",[])}
class DialogueRecorder extends DialogueHost:
	var draws: Array = []
	func answer(request: Dictionary) -> Dictionary:
		if request.get("kind") in ["draw_string","draw_glyph"]: draws.append(request.duplicate(true))
		return super.answer(request)

var checks: Array = []
var details: Dictionary = {}
var stage: SubViewport
var frame_view: TextureRect
var args: PackedStringArray
func check(ok: bool, name: String) -> void:
	checks.append({"name":name,"passed":ok})
	if not ok: push_error(name)

func _initialize() -> void:
	args=OS.get_cmdline_user_args()
	if args.size()!=4 or DisplayServer.get_name()=="headless": quit(2); return
	call_deferred("_run")

func _compose(game, hide_party := false, hide_events := false) -> Dictionary:
	var g: Dictionary = game.state.globals
	var events: Dictionary = game.state.events.duplicate(true)
	if hide_events: events.event_count=0
	var caller := {"map_id":g.loaded_map_id,"palette_index":0,"palette_variant":0,
		"map_mode":0,"clip_bottom":200,"viewport_x":g.viewport_x,"viewport_y":g.viewport_y,
		"member_last":-1 if hide_party else g.member_last,"follower_count":0 if hide_party else g.follower_count,
		"team_layer":g.party_layer_word,"party_records":game.state.party_records}
	var composed: Dictionary = Composition.build("render_scene_frame",game.records,game.storage,events,game.cache,caller)
	if composed.has("error"): return composed
	for child in stage.get_children():
		stage.remove_child(child); child.free()
	stage.add_child(composed.value)
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = stage.get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	return {"image":pixels,"requests":composed.requests,"sprite_rows":composed.sprite_rows}

func _window_pixels() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = get_root().get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels

func _run() -> void:
	get_root().title="PAL Wanxiang | reviewed source probe (not ordinary Session)"
	get_root().size=Vector2i(640,400)
	get_root().content_scale_size=Vector2i(640,400)
	var package = Package.new()
	check(package.load_package(args[0]),"admitted original input")
	if not package.error.is_empty(): finish(); return
	var game=Game.new()
	check(game.open(package),"coordinator assembled")
	if not game.error.is_empty(): finish(); return
	var gaps=Config.bind_gaps(game)
	game.bind_clock(Clock.new());game.bind_runtime(Runtime.new());game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	var dialogue=DialogueRecorder.new()
	dialogue.bind(package.pal98_sources);dialogue.bind_page_owner(game.renderer)
	game.dialogue_host=dialogue
	var initial: Dictionary=game.new_state(0x12345,Config.configuration())
	if initial.has("error"): check(false,str(initial.error));finish();return
	var begun: Dictionary=Config.run(game)
	check(not begun.has("error") and begun.get("completed"),"replay reaches real reload terminal")
	if begun.has("error") or not begun.get("completed"): finish();return
	check(game.state.globals.loaded_map_id==12,"source MAP12 selected")
	check(game.executor.installed_rgb6()==game.records.palette(0,0).value,"selected GPU palette equals active palette")
	if not checks.back().passed:finish();return
	stage=SubViewport.new();stage.size=Vector2i(320,200)
	stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	stage.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	get_root().add_child(stage)
	frame_view=TextureRect.new();frame_view.size=Vector2(640,400);frame_view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	frame_view.texture=stage.get_texture();get_root().add_child(frame_view)
	var empty: Dictionary=await _compose(game,true,true)
	var party_only: Dictionary=await _compose(game,false,true)
	if empty.has("error") or party_only.has("error"):check(false,"party composition failed");finish();return
	check(empty.image.get_data()!=party_only.image.get_data(),"actual party pixels differ from map with no sprites")
	var before: Dictionary=await _compose(game)
	if before.has("error"):check(false,"composition failed: "+str(before.error));finish();return
	check(before.requests.filter(func(r):return r.kind=="event").size()==2,"both actual event sprites resolve")
	check(before.image.get_data()!=party_only.image.get_data(),"actual event pixels are presented")
	var before_window: Image=await _window_pixels()
	check(before_window.get_size()==Vector2i(640,400),"actual window render target captured")
	check(before_window.save_png(args[1])==OK,"before window PNG saved")
	details.before_sha256=Schema.digest(before_window.get_data())
	# Render actual recorded source draw requests into the displayed target.
	# This replayed surface probe is separate from the still-pending F03 host.
	var surface=Surface.new();get_root().add_child(surface)
	var colours:=PackedColorArray()
	var palette:PackedByteArray=game.executor.installed_rgb6()
	for index in range(256):colours.append(Color8(palette[index*3]*4,palette[index*3+1]*4,palette[index*3+2]*4))
	check(surface.configure(FontOwner.create(),colours,before.image),"dialogue GPU target configured")
	frame_view.texture=surface.get_texture()
	var draw_count:=0;var start_text:=false
	for request in dialogue.draws:
		if request.kind=="draw_string":start_text=true
		if not start_text:continue
		var drawn:Dictionary=await surface.apply_request(request,package.pal98_sources.metadata().text_encoding)
		if drawn.has("error"):check(false,str(drawn.error));finish();return
		draw_count+=1
		if draw_count>=8:break
	var text_window:Image=await _window_pixels()
	check(draw_count>1 and surface.text_snapshot().size()==draw_count and text_window.get_data()!=before_window.get_data(),"real source text draws change actual window")
	check(text_window.save_png(args[1].get_basename()+"-dialogue.png")==OK,"dialogue window PNG saved")
	details.text_draws=draw_count
	frame_view.texture=stage.get_texture()
	var start_world:Vector2i=Vector2i(game.state.globals.world_x,game.state.globals.world_y)
	var moved:=0
	for step in range(5):
		var tick:Dictionary=game.tick(PackedInt32Array([0,0,0,2,0,0,0,0,0]))
		if tick.has("error"):check(false,str(tick.error));finish();return
		if tick.input_move:moved+=1
	var after:Dictionary=await _compose(game)
	if after.has("error"):check(false,"walk composition failed: "+str(after.error));finish();return
	var after_window:Image=await _window_pixels()
	check(moved>0 and Vector2i(game.state.globals.world_x,game.state.globals.world_y)!=start_world,"production input changes current world")
	check(after.image.get_data()!=before.image.get_data() and after_window.get_data()!=before_window.get_data(),"moving changes composed pixels AND actual window")
	check(after_window.save_png(args[2])==OK,"after window PNG saved")
	details.after_sha256=Schema.digest(after_window.get_data())
	details.world=[game.state.globals.world_x,game.state.globals.world_y];details.moved=moved
	details.named_gaps=gaps.seen
	# Negative control: current composition errors cannot be turned into an old-frame pass.
	game.state.party_records[0].current_frame=32767
	var refused:Dictionary=Composition.build("render_scene_frame",game.records,game.storage,game.state.events,game.cache,
		{"map_id":12,"palette_index":0,"palette_variant":0,"map_mode":0,"clip_bottom":200,
		"viewport_x":game.state.globals.viewport_x,"viewport_y":game.state.globals.viewport_y,
		"member_last":0,"follower_count":0,"team_layer":0,"party_records":game.state.party_records})
	check(refused.has("error"),"invalid current sprite frame is an error, never old-frame success")
	game.cancel()
	finish()

func finish() -> void:
	var failed:int=checks.filter(func(row):return not row.passed).size()
	var file=FileAccess.open(args[3],FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed,
		"success":failed==0,"details":details,"original_gameplay":false,"injected_logical_input":true,
		"scope":"actual GPU and window probe; synthetic initializer/clock; text replay; named gaps retained"},"  "))
	file.close();quit(1 if failed else 0)
