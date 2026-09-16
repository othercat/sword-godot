# SPDX-License-Identifier: MIT
extends SceneTree
## Walk from the wake-up rest to the door event's recorded position (scene-2
## event slot 1 at words[2],[4] = 512,800; stairs cluster near 640,608): the
## lane homes step by step and reports a scene change (trigger entry), a
## named error, or the honest limit of the sweep.
const App = preload("res://src/native_app.gd")
const Schema = preload("res://src/native_schema.gd")

class NamedGap:
	var seen: Array = []
	func answer(request: Dictionary) -> Dictionary:
		seen.append(request.kind)
		var result := {"completed": true}
		if request.get("state") is Dictionary: result.state = request.state.duplicate(true)
		return result

var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray
var app
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)
func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 2 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("run")
func run() -> void:
	get_root().size = Vector2i(960, 640)
	app = App.new(); get_root().add_child(app); await process_frame
	app.open_package(args[0])
	if not app.start_original_experiment(): finish(); return
	app.set_physics_process(false)
	var gap = NamedGap.new()
	for kind in ["restore_dialog_background_without_initial_page", "upper_dialog_layout",
			"start_frame_and_process_events", "update_viewport_and_party_position",
			"render_scene_frame", "sync_party_for_redraw", "render_scene",
			"advance_party_movement", "sync_party_frames", "main_frame",
			"move_and_animate_event_object_one_step"]:
		app.pal98.game.bind_named_double(kind, gap)
	var host = app.pal98.host
	var keys := PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var press := false
	var drained := false
	for step in range(12000):
		keys[8] = 2 if press else 0
		if press: press = false
		var result: Dictionary = await host.tick_frame(keys, true)
		if result.has("error"):
			details.open_error = str(result.error); finish(); return
		if result.get("completed", false) and app.pal98.game.awaiting_player:
			break
		if result.get("awaiting_effect", false) or app.pal98.game.is_dialogue_parked():
			if not drained:
				var page: Dictionary = await host.present_pending_page()
				if page.has("error"):
					details.open_error = str(page.error); finish(); return
				drained = true
				app.pal98.game._presentation_required = false
			press = true
			continue
	var targets: Array = [[512, 800], [640, 608], [672, 624], [720, 664]]
	var start: Dictionary = app.pal98.game.state.globals
	details.start = {"scene": start.current_scene, "world": [start.world_x, start.world_y]}
	var outcome := ""
	var first_error := ""
	for target in targets:
		var goal: Array = [int(target[0]), int(target[1])]
		var last: Array = [999999, 999999]
		var stuck := 0
		var axis := 0
		for step in range(2600):
			var g: Dictionary = app.pal98.game.state.globals
			if g.current_scene != start.current_scene or g.loaded_map_id != start.loaded_map_id:
				outcome = "scene_changed"
				details.trigger = {"scene": g.current_scene, "map": g.loaded_map_id,
					"world": [g.world_x, g.world_y], "target": goal}
				break
			var here: Array = [int(g.world_x), int(g.world_y)]
			if here == last:
				stuck += 1
				if stuck >= 90: axis = (axis + 1) % 2  # slide around furniture
			else:
				stuck = 0; axis = 0 if abs(goal[0] - here[0]) >= abs(goal[1] - here[1]) else 1
			last = here
			var dx: int = goal[0] - here[0]
			var dy: int = goal[1] - here[1]
			if abs(dx) < 12 and abs(dy) < 12:
				outcome = "reached_target"
				details.reached = {"target": goal, "world": here}
				break
			keys = PackedInt32Array([0,0,0,0,0,0,0,0,0])
			var use_x := axis == 0
			if stuck >= 90: use_x = not use_x  # keep the slid axis until moving again
			if use_x: keys[2 if dx < 0 else 7] = 3
			else: keys[0 if dy < 0 else 1] = 3
			var result: Dictionary = await host.tick_frame(keys, true)
			if result.has("error"):
				first_error = str(result.error); break
		if outcome != "": break
		if not first_error.is_empty(): break
	if outcome == "":
		var g: Dictionary = app.pal98.game.state.globals
		outcome = "named_error" if not first_error.is_empty() else "sweep_exhausted"
		details.limit = {"world": [g.world_x, g.world_y], "error": first_error,
			"scene": g.current_scene, "map": g.loaded_map_id,
			"awaiting_player": app.pal98.game.awaiting_player}
	details.outcome = outcome
	check(outcome == "scene_changed" or outcome == "reached_target",
		"the homing walk names its outcome: " + outcome)
	finish()
func finish() -> void:
	if app != null and app.pal98 != null: app._stop_pal98()
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size()-failed, "failed": failed,
		"details": details, "scope": "real window homing walk; not physical acceptance"}, "  ")); file.close()
	quit(1 if failed else 0)
