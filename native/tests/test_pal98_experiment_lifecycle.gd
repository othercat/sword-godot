# SPDX-License-Identifier: MIT
extends SceneTree
const Scene = preload("res://src/native_pal98_app_scene.gd")
var checks: Array = []
var first: Dictionary = {}
var scene

class FakeGame:
	var state := {"globals": {"world_x": 1, "world_y": 2}}
	func has_pending_presentation() -> bool: return false
	func is_dialogue_parked() -> bool: return false
	func pending_kind() -> String: return ""
	func cancel() -> void: state = {}
class FakeDisplay:
	var surface = RefCounted.new()
class DelayedHost:
	signal release
	var calls := 0
	func tick_frame(_levels, _due) -> Dictionary:
		calls += 1
		await release
		return {"completed": true}
	func unbind() -> void: pass

func check(ok: bool, name: String) -> void:
	checks.append({"passed": ok, "name": name})
	if not ok: push_error(name)
func _initialize() -> void: call_deferred("run")
func first_tick() -> void: first = await scene.tick(0.01, PackedInt32Array())
func run() -> void:
	scene = Scene.new()
	check(not scene.start(null, null, null) and scene.error.contains("opt-in"), "provisional inputs are opt-in")
	check(Scene.EventPump.new().answer({"kind": "unowned"}).has("error"), "unknown request cannot succeed")
	check(Scene.EventPump.new().answer({"kind": "fade_event_pump"}).has("error"), "unimplemented event pump cannot succeed")
	scene.game = FakeGame.new(); scene.display = FakeDisplay.new(); var host = DelayedHost.new(); scene.host = host
	first_tick.call_deferred(); await process_frame
	check(first.is_empty() and host.calls == 1, "pending frame awaits host acknowledgement")
	var second: Dictionary = await scene.tick(0.01, PackedInt32Array())
	check(second.get("pending", false) and host.calls == 1, "second frame does not reenter display")
	host.release.emit(); await process_frame
	check(first.get("completed", false), "acknowledged frame completes")
	first = {}; first_tick.call_deferred(); await process_frame
	scene.stop(); scene.game = FakeGame.new(); scene.display = FakeDisplay.new(); scene.host = DelayedHost.new()
	host.release.emit(); await process_frame
	check(first.get("error", "").contains("stale"), "old acknowledgement after rebind is refused")
	check(scene.active() and scene.game.state.globals.world_x == 1, "old completion preserves replacement state")
	check(not scene._ticking, "replacement has no leaked frame lock")
	scene.stop()
	var failed: int = checks.filter(func(x): return not x.passed).size()
	var out = {"checks": checks, "passed": checks.size() - failed, "failed": failed}
	var args = OS.get_cmdline_user_args()
	if args.size() == 1:
		var file = FileAccess.open(args[0], FileAccess.WRITE); file.store_string(JSON.stringify(out, "  ")); file.close()
	print(JSON.stringify(out)); quit(1 if failed else 0)
