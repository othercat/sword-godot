# SPDX-License-Identifier: MIT
extends SceneTree
## Walk the wake-up room looking for the door trigger: after the transition
## the lane holds bounded direction sequences and reports whatever changes -
## a scene/map change names the trigger entry, staying put names the limit.
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
	var start: Dictionary = app.pal98.game.state.globals
	details.start = {"scene": start.current_scene, "map": start.loaded_map_id, "world": [start.world_x, start.world_y]}
	# Bounded sweep: down, left, down - the wake room's exit stairs sit low-left.
	var moved_scenes: Array = []
	var last_error := ""
	for phase in [["down", 420], ["left", 420], ["down", 420]]:
		var slot: int = 1 if phase[0] == "down" else 2
		for step in range(int(phase[1])):
			keys = PackedInt32Array([0,0,0,0,0,0,0,0,0])
			keys[slot] = 3
			var result: Dictionary = await host.tick_frame(keys, true)
			if result.has("error"):
				last_error = str(result.error); break
			var g: Dictionary = app.pal98.game.state.globals
			var here := str(g.current_scene) + "/" + str(g.loaded_map_id)
			if moved_scenes.is_empty() or moved_scenes.back() != here:
				moved_scenes.append(here)
				details["at_" + phase[0] + "_" + str(step)] = {
					"scene": g.current_scene, "map": g.loaded_map_id,
					"world": [g.world_x, g.world_y]}
			if app.pal98.game.awaiting_player and step > 10:
				details.parked_during_walk = here
		if not last_error.is_empty(): break
	details.sweep = moved_scenes
	details.walk_error = last_error
	var g: Dictionary = app.pal98.game.state.globals
	details.end = {"scene": g.current_scene, "map": g.loaded_map_id, "world": [g.world_x, g.world_y],
		"awaiting_player": app.pal98.game.awaiting_player}
	check(moved_scenes.size() >= 1, "the sweep observed at least the starting scene")
	check(moved_scenes.size() >= 2 or not last_error.is_empty() or details.has("parked_during_walk"),
		"the sweep names its outcome: scene change, named error, or a park")
	finish()
func finish() -> void:
	if app != null and app.pal98 != null: app._stop_pal98()
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size()-failed, "failed": failed,
		"details": details, "scope": "real window bounded walk probe; not physical acceptance"}, "  ")); file.close()
	quit(1 if failed else 0)
