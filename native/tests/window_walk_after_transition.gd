# SPDX-License-Identifier: MIT
extends SceneTree
## Real experimental window, post-transition walking: direction input during
## dialogue parks must not move anyone, and a held direction at rest moves
## the leader over the real map. Synthetic levels, not physical acceptance.
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
	if not app.open_package(args[0]):
		pass  # guarded original admission: continue to the experimental start
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
	var dialogue_ticks := 0
	var dialogue_world_still := true
	var first_error := ""
	var outcome := ""
	for step in range(12000):
		keys[8] = 2 if press else 0
		if press: press = false
		var result: Dictionary = await host.tick_frame(keys, true)
		if result.has("error"):
			first_error = str(result.error); outcome = "named_error"; break
		if result.get("transition", {}) is Dictionary and not result.get("transition", {}).is_empty() \
				or result.get("pending_kind", "") == "clear_effective_cross_fade":
			continue
		if result.get("completed", false) and app.pal98.game.awaiting_player:
			outcome = "resting_scene"; break
		if result.get("awaiting_effect", false) or app.pal98.game.is_dialogue_parked():
			dialogue_ticks += 1
			keys[7] = 3  # hold right through every dialogue beat
			if not drained:
				var page: Dictionary = await host.present_pending_page()
				if page.has("error"):
					first_error = str(page.error); outcome = "presentation_error"; break
				drained = true
				app.pal98.game._presentation_required = false
			press = true
			var globals: Dictionary = app.pal98.game.state.globals
			var here: Array = [globals.current_scene, globals.loaded_map_id]
			# Script events may legitimately move the party during dialogue
			# (the wake-up walk); input must not move the MAP there.
			if here != details.get("dialogue_scene", []):
				details.dialogue_scene = here
				details.dialogue_map = globals.loaded_map_id
			elif globals.loaded_map_id != details.dialogue_map:
				dialogue_world_still = false
			continue
	check(dialogue_ticks > 0, "the lane observed dialogue parks")
	check(dialogue_world_still, "held direction input changed no map during dialogue parks")
	if outcome != "resting_scene":
		details.outcome = {"outcome": outcome, "first_error": first_error}
		finish(); return
	var globals: Dictionary = app.pal98.game.state.globals
	var before: Array = [globals.world_x, globals.world_y]
	details.rest_world = before
	for step in range(180):
		keys[7] = 3  # hold right for three simulated seconds
		var result: Dictionary = await host.tick_frame(keys, true)
		if result.has("error"):
			details.walk_error = str(result.error); break
	keys[7] = 0
	await host.tick_frame(keys, true)
	var after: Dictionary = app.pal98.game.state.globals
	var moved: Array = [after.world_x, after.world_y]
	details.walk_world = moved
	details.stand_ins = gap.seen
	check(moved[0] != before[0] or moved[1] != before[1], "a held direction moved the party at rest")
	check(after.current_scene == globals.current_scene and after.loaded_map_id == globals.loaded_map_id,
		"walking stayed on the same scene and map")
	finish()
func finish() -> void:
	if app.pal98 != null: app._stop_pal98()
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size()-failed, "failed": failed,
		"details": details, "scope": "real window, synthetic levels; not physical acceptance"}, "  ")); file.close()
	quit(1 if failed else 0)
