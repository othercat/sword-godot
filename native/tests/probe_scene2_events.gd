# SPDX-License-Identifier: MIT
extends SceneTree
## Diagnostic dump (not a suite): the resting scene-2 event table with each
## event's position and the head of its program, for trigger entry work.
const ProbeConfig = preload("res://tests/fixtures/pal98_new_game_probe.gd")
const NewGame = preload("res://src/native_pal98_new_game.gd")
const Package = preload("res://src/native_package.gd")
class Clock:
	var frame := 0
	func consume(units: int) -> Dictionary:
		frame += units; return {"consumed": units, "total": frame}
class Runtime:
	func answer(request: Dictionary) -> Dictionary:
		return {"completed": true}
class NamedGap:
	func answer(request: Dictionary) -> Dictionary:
		var result := {"completed": true}
		if request.get("state") is Dictionary: result.state = request.state.duplicate(true)
		return result
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error(package.error); quit(2); return
	var game = NewGame.new()
	if not game.open(package): push_error(game.error); quit(2); return
	game.bind_recording_dialogue_for_probe()
	var gaps = NamedGap.new()
	for kind in ["clear_effective_cross_fade", "restore_dialog_background_without_initial_page",
			"upper_dialog_layout", "start_frame_and_process_events", "update_viewport_and_party_position",
			"render_scene_frame", "sync_party_for_redraw", "render_scene", "advance_party_movement",
			"sync_party_frames", "main_frame", "move_and_animate_event_object_one_step",
			"play_midi", "play_sound_effect"]:
		game.bind_named_double(kind, gaps)
	game.bind_clock(Clock.new()); game.bind_runtime(Runtime.new())
	game.bind_key_map([0,1,2,3,4,5,6,7,8],0,8)
	var fresh: Dictionary = game.new_state(0x12345, ProbeConfig.configuration())
	if fresh.has("error"): push_error(str(fresh.error)); quit(2); return
	var result: Dictionary = ProbeConfig.run(game)
	if result.has("error"): push_error(str(result.error)); quit(2); return
	var globals: Dictionary = game.state.globals
	var events: Dictionary = game.state.events
	var scripts: PackedByteArray = package.pal98_sources.copy_chunk("sss", 4)
	var rows: Array = []
	for slot in range(1, int(events.get("event_count", 0)) + 1):
		var record: Dictionary = game.storage.event_record(events, slot)
		if record.has("error"): rows.append({"slot": slot, "error": record.error}); continue
		var bytes: PackedByteArray = record.value
		var entry: int = bytes.decode_u16(8)
		var words: Array = []
		for at in range(0, 32, 2):
			words.append(bytes.decode_u16(at))
		rows.append({"slot": slot, "entry": entry, "words": words})
	var out = {"scene": globals.current_scene, "map": globals.loaded_map_id,
		"world": [globals.world_x, globals.world_y], "count": events.get("event_count", 0), "events": rows}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "  ") + "\n"); file.close()
	print("scene ", globals.current_scene, " map ", globals.loaded_map_id, " events ", rows.size())
	quit(0)
