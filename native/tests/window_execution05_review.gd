# SPDX-License-Identifier: MIT
extends SceneTree
const Game = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
const Config = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const Display = preload("res://src/native_pal98_scene_display.gd")
const Opening = preload("res://src/native_pal98_opening_init.gd")
const Renderer = preload("res://src/native_pal98_scene_render.gd")
const Admission = preload("res://src/native_pal98_original_admission.gd")
const App = preload("res://src/native_app.gd")
const Scale = preload("res://src/native_pal98_window_scale.gd")
const Schema = preload("res://src/native_schema.gd")
class Clock:
	func consume(units: int) -> Dictionary: return {"consumed": units}
class EmptyClock:
	func consume(_units: int) -> Dictionary: return {}
class Runtime:
	func answer(request: Dictionary) -> Dictionary: return {"completed":true,"pumped":request.get("events",[])}
var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray
func check(ok: bool, name: String, actual = null) -> void:
	checks.append({"name": name,"passed":ok,"actual":actual})
func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	call_deferred("run")
func pixels(stage: SubViewport) -> PackedByteArray:
	await process_frame
	await RenderingServer.frame_post_draw
	return stage.get_texture().get_image().get_data()
func run() -> void:
	get_root().size = Vector2i(640,400)
	var p = Package.new()
	check(p.load_package(args[0]),"original input admitted",p.error)
	var words: Array = []; words.resize(450); words.fill(1)
	words[36] = true
	var level = Opening.base_levels(words)
	check(level.has("error"),"base level bool rejected before int coercion",level)
	words[36] = 1.5
	level = Opening.base_levels(words)
	check(level.has("error"),"base level fraction rejected before int coercion",level)
	var game = Game.new(); game.open(p); Config.bind_gaps(game)
	game.bind_clock(Clock.new()); game.bind_runtime(Runtime.new()); game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	var initial = Config.configuration()
	game.new_state_from_source(0x12345,"explicit_replay",initial)
	var replay = Config.run(game)
	check(not replay.has("error"),"source replay reaches resting map",replay.get("error",""))
	if replay.has("error"): finish(); return
	var display = Display.new(); display.bind(game)
	var unbound = display.present()
	check(unbound.has("error"),"presentation requires a live display target")
	if unbound.has("value"): unbound.value.free()
	var stage = SubViewport.new(); stage.size = Vector2i(320,200); stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(stage); display.bind_display_target(stage)
	var view = TextureRect.new(); view.size = Vector2(640,400); view.texture = stage.get_texture(); get_root().add_child(view)
	var first = display.present(); check(not first.has("error"),"live initial frame composes",first.get("error",""))
	var before = await pixels(stage)
	var black = PackedByteArray(); black.resize(768)
	var installed = game.executor.install_cold(black)
	check(installed.get("completed",false),"live palette owner accepts black")
	display.present()
	var after = await pixels(stage)
	check(before != after,"installed palette changes the actual scene display",{"before":Schema.digest(before),"after":Schema.digest(after)})
	var dark := true
	for i in range(0,after.size(),4):
		if after[i] != 0 or after[i+1] != 0 or after[i+2] != 0: dark = false; break
	check(dark,"all black active palette is black on actual GPU frame")
	var new_game = Game.new(); new_game.open(p)
	new_game.new_state_from_source(42,"explicit_replay",initial)
	display.bind(new_game)
	check(display.last_receipt.is_empty(),"rebinding source clears the previous accepted frame")
	check(display.republish().has("error"),"rebinding cannot republish prior game page")
	var renderer = Renderer.new(); renderer.bind(p.pal98_graphics.open_records())
	var state = {"globals":{"loaded_map_id":20,"viewport_x":448,"viewport_y":368,"view_offset_x":0,"view_offset_y":0,"previous_viewport_x":0,"previous_viewport_y":0,"battle_mode":0}}
	renderer.render(state); var old_pixels = renderer.current_rgba()
	state.globals.loaded_map_id = 12
	renderer.bind_transition_clock(Clock.new())
	var transition = renderer.execute_clear_cross_fade(state,0,1)
	check(not transition.get("completed",false),"missing lane/presentation/shake owners cannot complete T121",transition.get("receipt",{}).get("named_gap",""))
	check(renderer.current_rgba() == old_pixels,"unimplemented full transition preserves current page")
	renderer.bind_transition_clock(EmptyClock.new())
	var clock_result = renderer.execute_clear_cross_fade(state,3,1)
	check(clock_result.has("error"),"empty clock receipt does not acknowledge consumed time")
	var admission = Admission.inspect(args[1])
	check(admission.get("playable",false),"valid author package admission reflects formal session play",admission.get("capabilities",[]))
	var small = Scale.fit(Vector2i(160,100))
	check(small.has("error") or (small.content_size.x <= 160 and small.content_size.y <= 100),"undersized window is constrained or refused, never silently cropped",small)
	var app = App.new(); get_root().add_child(app); await process_frame; app.set_physics_process(false)
	check(app.open_package(args[1]),"formal app starts the valid author package")
	var live_id = app.session.state.session_id
	var file = FileAccess.open(args[2],FileAccess.WRITE); file.store_string("bad zip");file.close()
	app.open_package(args[2]); app._modal_changed()
	check(app.load_error_picker.visible and app.session.modal,"load error modal pauses current session",{"visible":app.load_error_picker.visible,"modal":app.session.modal})
	check(app.session.state.session_id == live_id,"failed load preserves session identity")
	app.load_error_picker.hide(); app.admission_picker.popup_centered(); app._modal_changed()
	check(app.session.modal,"admission modal pauses current session")
	app.admission_picker.hide(); app._modal_changed()
	check(not app.session.modal,"closing all dialogs restores session modal state")
	game.cancel(); new_game.cancel(); finish()
func finish() -> void:
	var failed = checks.filter(func(x):return not x.passed).size()
	var f = FileAccess.open(args[3],FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed,"details":details},"  "));f.close()
	quit(1 if failed else 0)
