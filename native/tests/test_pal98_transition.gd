# SPDX-License-Identifier: MIT
extends SceneTree
## T121 preparation is isolated; missing pixel/presentation owners cannot ACK it.
const Renderer = preload("res://src/native_pal98_scene_render.gd")
const Package = preload("res://src/native_package.gd")
class Clock:
	var calls := 0
	func consume(units: int) -> Dictionary:
		calls += 1; return {"consumed": units}
class EmptyClock:
	func consume(_units: int) -> Dictionary: return {}
var checks: Array = []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: push_error(label)
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error(package.error); quit(2); return
	var renderer = Renderer.new(); renderer.bind(package.pal98_graphics.open_records())
	check(not renderer.bind_transition_clock(42), "non-object clock is rejected")
	var a = {"globals":{"loaded_map_id":20,"viewport_x":448,"viewport_y":368,
		"view_offset_x":13,"view_offset_y":9,"previous_viewport_x":0,"previous_viewport_y":0,"battle_mode":0}}
	var b = a.duplicate(true); b.globals.loaded_map_id = 12
	check(not renderer.render(b).has("error"), "target MAP12 background is independently readable")
	var target = renderer.current_rgba()
	check(not renderer.render(a).has("error"), "current MAP20 page renders")
	var before = renderer.current_rgba()
	check(not renderer.capture_page().has("error"), "independent dialogue capture exists")
	var prepared = renderer.prepare_clear_cross_fade(b,0,3)
	check(prepared.get("prepared",false) and not prepared.get("completed",false), "preparation is not completion")
	check(prepared.target_rgba == target and renderer.current_rgba() == before, "candidate target never replaces current page")
	check(prepared.base_page.indices != prepared.target_page.indices, "base and target pages remain distinct")
	check(prepared.candidate_state.globals.view_offset_x == 0 and prepared.candidate_state.globals.previous_viewport_x == 448,
		"candidate carries the actual T244 writeback")
	var clock = Clock.new(); check(renderer.bind_transition_clock(clock), "clock binds independently")
	var refused = renderer.answer({"kind":"clear_effective_cross_fade","state":b,"first":0,"second":3})
	check(refused.has("error") and not refused.get("completed",false) and refused.get("prepared",false),
		"full command refuses while lane/full-scene/presentation/shake owners are absent")
	check(renderer.current_rgba() == before and clock.calls == 0, "refusal neither publishes nor fabricates consumed time")
	renderer.bind_transition_clock(EmptyClock.new())
	check(renderer.execute_clear_cross_fade(b,3,1).has("error"), "empty clock cannot turn unsupported transition into success")
	check(not renderer.restore_dialog_background().has("error") and renderer.current_rgba() == before,
		"attempt leaves the independent captured page intact")
	var battle = b.duplicate(true); battle.globals.battle_mode = 1
	check(renderer.prepare_clear_cross_fade(battle,0,1).has("error"), "unowned battle branch remains explicit")
	check(renderer.prepare_clear_cross_fade(b,32768,1).has("error"), "arguments outside I2 are refused")
	renderer.bind(package.pal98_graphics.open_records())
	check(renderer.restore_dialog_background().has("error"), "source rebind invalidates capture")
	var failed = checks.filter(func(x):return not x.passed).size()
	var f = FileAccess.open(args[1],FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed},"  ")); f.close()
	quit(1 if failed else 0)
