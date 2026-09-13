# SPDX-License-Identifier: MIT
extends SceneTree
## Actual source glyph requests -> rendered viewport receipts. Probe initial
## words, initial uncaptured-page gap and system-font ink remain explicit.
const Game = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Display = preload("res://src/native_pal98_scene_display.gd")
const Surface = preload("res://src/native_pal98_dialogue_surface.gd")
const FontOwner = preload("res://src/native_ui_font.gd")
const Schema = preload("res://src/native_schema.gd")
class Clock:
	func consume(units: int) -> Dictionary: return {"consumed":units}
class Runtime:
	func answer(request: Dictionary) -> Dictionary: return {"completed":true,"pumped":request.get("events",[])}
var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray
func check(ok: bool, name: String) -> void:
	checks.append({"name":name,"passed":ok})
	if not ok: push_error(name)
func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 3 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("run")
func pixels() -> Image:
	await process_frame; await RenderingServer.frame_post_draw
	var value = get_root().get_texture().get_image(); value.convert(Image.FORMAT_RGBA8); return value
func run() -> void:
	get_root().size = Vector2i(640,400)
	get_root().content_scale_size = Vector2i(640,400)
	var package = Package.new(); check(package.load_package(args[0]), "source input admits")
	if not package.error.is_empty(): finish(); return
	var game = Game.new(); check(game.open(package), "coordinator assembles")
	Config.bind_gaps(game); game.bind_clock(Clock.new()); game.bind_runtime(Runtime.new())
	game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	var initial = game.new_state_from_source(0x12345,"explicit_replay",Config.configuration())
	check(not initial.has("error"), "source experience and explicit probe words initialize")
	var begun = game.begin()
	check(not begun.has("error") and game.pending_kind() == "wait", "explicit recording setup reaches first timer")
	if begun.has("error"): details.failure=begun; finish(); return
	var prebind_count: int = game.pending_page_requests().size()
	details.prebind_recorded_draws = prebind_count
	var display = Display.new(); check(display.bind(game), "current game binds")
	var stage = SubViewport.new(); stage.size=Vector2i(320,200); stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	stage.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	get_root().add_child(stage)
	var view=TextureRect.new();view.size=Vector2(640,400);view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;get_root().add_child(view)
	check(display.bind_display_target(stage,view), "real target binds")
	var surface=Surface.new();get_root().add_child(surface)
	check(display.bind_dialogue_surface(surface,FontOwner.create(),package.pal98_sources.metadata().text_encoding),
		"presentation binding requires actual surface acknowledgements")
	var bare = display.present()
	check(not bare.has("error"), "current map and characters compose")
	if bare.has("error"): details.failure=bare;finish();return
	var before = await pixels()
	var zeros=PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var still=game.tick(zeros,false)
	check(not still.has("error") and game.pending_kind()=="wait","no nominal timer means no delay progress")
	var world=Vector2i(game.state.globals.world_x,game.state.globals.world_y)
	for tick in range(4096):
		if game.has_pending_presentation(): break
		var next=game.tick(zeros,true)
		if next.has("error"): details.failure=next;check(false,"source drive");finish();return
	check(game.has_pending_presentation(),"source draw parks before acknowledgement")
	var pending=game.pending_presentation()
	if pending.is_empty(): finish();return
	check(game.pending_page_requests().size()==prebind_count,"new unrendered glyph is not an accepted page command")
	game.tick(zeros,true)
	check(game.pending_presentation().id==pending.id,"timer input cannot release a pending draw")
	check(game.resume_dialogue(pending.id,{"kind":"drawn"}).has("error"),"input continuation cannot ACK rendering")
	check(game.resume_presentation(pending.id,{"receipt":7}).has("error") and game.pending_presentation().id==pending.id,
		"malformed receipt leaves the pending draw intact")
	check(game.resume_presentation(pending.id,{"receipt":{"source":7}}).has("error") and game.pending_presentation().id==pending.id,
		"malformed receipt source cannot release a draw")
	check(game.resume_presentation("old-id",{"event":{"kind":"drawn"}}).has("error") and game.pending_presentation().id==pending.id,
		"stale draw receipt leaves the current request intact")
	var page=await display.present_dialogue_page()
	check(not page.has("error") and not surface.text_snapshot().is_empty(),"real rendered receipt releases source glyph")
	if page.has("error"):details.failure=page;finish();return
	var first=surface.text_snapshot()[0]
	var after=await pixels()
	check(after.get_data()!=before.get_data(),"accepted source text changes actual window pixels")
	check(after.save_png(args[1])==OK,"actual source text screenshot saved")
	for tick in range(4096):
		if surface.text_snapshot().size()>=prebind_count+2:break
		var next=await display.tick_presented(zeros,true)
		if next.has("error"):details.failure=next;check(false,"second source glyph");finish();return
	var snapshot=surface.text_snapshot()
	details.accepted_text_runs=snapshot
	check(snapshot.size()>=prebind_count+2 and snapshot[0].text==first.text and snapshot[0].x==first.x,
		"first source glyph survives subsequent typing waits and draws")
	check(game.pending_page_requests().size()>=2,"accepted same-page history accumulates")
	check(Vector2i(game.state.globals.world_x,game.state.globals.world_y)==world,"typing waits never move world")
	var shown=await pixels()
	check(shown.save_png(args[1])==OK,"retained text screenshot saved at final typing boundary")
	check(display.republish().get("completed",false) and view.texture==surface.get_texture(),"restore republishes accepted dialogue surface")
	var reshown=await pixels()
	check(reshown.get_data()==shown.get_data(),"republish preserves displayed dialogue pixels")
	# Pending callbacks cannot revive the previous game after a cancellation.
	var old_generation=game.presentation_generation()
	game.cancel()
	check(game.presentation_generation()!=old_generation and display.republish().has("error"),"cancel invalidates old accepted page")
	check(game.resume_presentation(pending.id,{"event":{"kind":"drawn"}}).has("error"),"cancel rejects prior presentation request")
	display.bind(game)
	check(surface.captured_sha256().is_empty() and display.last_receipt.is_empty(),"rebind clears captured and accepted pages")
	details.scope="source glyphs and waits on actual viewport; explicit initialization/gaps and system-font ink; not ordinary gameplay"
	finish()
func finish() -> void:
	var failed=checks.filter(func(x):return not x.passed).size()
	var f=FileAccess.open(args[2],FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed,"details":details},"  "));f.close()
	quit(1 if failed else 0)
